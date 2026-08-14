function out = acsOptimizeSparseRoastLeadField(t1File, leadFieldTag, targetVoxel, varargin)
% ACSOPTIMIZESPARSEROASTLEADFIELD Select a small montage from a custom lead field.
%
% out = acsOptimizeSparseRoastLeadField(t1File, leadFieldTag, targetVoxel)
% reuses a ROAST-style weighted least-squares optimizer to match a desired
% field at one or more subject-space target voxels while penalizing
% off-target field in the brain.
%
% This utility does not run meshing or GetDP. It combines an existing custom
% lead field.
%
% Name-value options:
%   orientation          : N x 3 desired field directions [[0 0 1]]
%   targetWeights        : N x 1 nonnegative target weights [equal]
%   targetRadiusMm       : spherical target ROI radius [2]
%   activeElectrodeCount : requested active montage size [4]
%   totalCurrentMa       : maximum injected current into the head [2]
%   maxCurrentPerElectrodeMa : absolute per-electrode current cap
%                         [legacy: 2*totalCurrentMa/activeElectrodeCount]
%   currentThresholdMa   : threshold for reporting active channels [1e-6]
%   optType              : 'wls-l1per' or 'max-l1per' ['wls-l1per']
%   desiredIntensityVm   : desired target field for wls-l1per [1]
%   focalityK            : target/nontarget WLS weight ratio [0.02]
%   excludedElectrodeNames : candidates allowed for modeling but not selection [{}]
%   searchMode           : globalCvx, exhaustiveCvx, or developmentHeuristic ['globalCvx']
%   targetingTag         : report filename tag [auto]
%   maxFilenameBaseChars : max basename length for report/QC files [96]
%   maxSubsetCount       : exhaustiveCvx safety limit [100000]
%   returnMeshField      : include full reconstructed mesh field [false]
%   showFigures          : show QC summary [false]
%   saveFigures          : save QC summary [false]
%   saveReport           : save MAT report beside the T1 [true]
%   verbose              : print progress and selected montage [true]

    if nargin < 3
        error('acsOptimizeSparseRoastLeadField:MissingInputs', ...
            'Provide t1File, leadFieldTag, and one or more target voxels.');
    end

    opts = parseInputs(varargin{:});
    t1File = char(t1File);
    leadFieldTag = char(leadFieldTag);
    targetVoxel = validateTargetVoxel(targetVoxel);
    [folder, stem] = fileparts(t1File);
    addDependencies();

    resultFile = fullfile(folder, [stem '_' leadFieldTag '_roastResult.mat']);
    optionsFile = fullfile(folder, [stem '_' leadFieldTag '_roastOptions.mat']);
    meshFile = fullfile(folder, [stem '_' leadFieldTag '.mat']);
    requireFile(resultFile);
    requireFile(optionsFile);
    requireFile(meshFile);

    resultData = load(resultFile, 'A_all');
    optionsData = load(optionsFile, 'opt');
    meshData = load(meshFile, 'node', 'elem');
    if ~isfield(resultData, 'A_all')
        error('acsOptimizeSparseRoastLeadField:MissingMatrix', ...
            'Lead-field result does not contain A_all: %s', resultFile);
    end
    if ~isfield(optionsData, 'opt') || ~isfield(optionsData.opt, 'leadField') || ...
            isempty(optionsData.opt.leadField)
        error('acsOptimizeSparseRoastLeadField:MissingMetadata', ...
            'Lead-field options do not contain custom candidate metadata.');
    end
    if ~isfield(meshData, 'node') || ~isfield(meshData, 'elem')
        error('acsOptimizeSparseRoastLeadField:MissingMesh', ...
            'Lead-field mesh MAT file does not contain node and elem arrays.');
    end
    leadField = optionsData.opt.leadField;
    if ~strcmpi(leadField.mode, 'custom') || ...
            ~isfield(leadField, 'includePassiveElectrodes') || ...
            ~leadField.includePassiveElectrodes
        error('acsOptimizeSparseRoastLeadField:UnsupportedLeadField', ...
            ['Sparse capMaker selection requires a custom lead field that ', ...
             'retains passive contacts in every basis solve.']);
    end
    if optionsData.opt.resamp
        error('acsOptimizeSparseRoastLeadField:ResamplingNotSupported', ...
            'This development utility currently expects ROAST resampling to be off.');
    end

    allNames = leadField.electrodeNames(:);
    stimulusNames = leadField.stimulusElectrodeNames(:);
    approximationInfo = leadFieldApproximationInfo(leadField, optionsData.opt);
    nCandidates = numel(allNames);
    selectableMask = selectableElectrodeMask(allNames, opts.excludedElectrodeNames, ...
        opts.selectableElectrodeNames);
    validateSelectionSize(opts.activeElectrodeCount, nnz(selectableMask));
    if size(resultData.A_all, 3) ~= numel(stimulusNames)
        error('acsOptimizeSparseRoastLeadField:BadMatrixSize', ...
            'A_all contains %d basis fields, but metadata lists %d.', ...
            size(resultData.A_all, 3), numel(stimulusNames));
    end

    V = spm_vol(t1File);
    voxelSize = [V.mat(1, 1), V.mat(2, 2), V.mat(3, 3)];
    if any(voxelSize <= 0) || any(any(abs(V.mat(1:3, 1:3) - diag(voxelSize)) > 1e-9))
        error('acsOptimizeSparseRoastLeadField:NonCanonicalT1', ...
            'Expected a canonical RAS T1 with a positive diagonal voxel transform.');
    end
    if any(targetVoxel(:) <= 0) || any(any(bsxfun(@gt, targetVoxel, V.dim(1:3))))
        error('acsOptimizeSparseRoastLeadField:TargetOutsideVolume', ...
            'Target voxels must fall inside the modeled T1 volume.');
    end

    orientation = normalizeOrientations(opts.orientation, size(targetVoxel, 1));
    targetWeights = normalizeWeights(opts.targetWeights, size(targetVoxel, 1));
    brainNodes = findBrainNodes(meshData.elem);
    targetNodes = findTargetNodes(meshData.node, brainNodes, targetVoxel, ...
        voxelSize, opts.targetRadiusMm);
    candidateSensitivity = candidateDirectionalSensitivity(resultData.A_all, ...
        allNames, stimulusNames, targetNodes, orientation, targetWeights);

    focalInfo = struct();
    availableSubsetCount = countSubsets(nnz(selectableMask), opts.activeElectrodeCount);
    switch opts.optType
        case 'max-l1per'
            [bestCurrents, bestScore, bestSubset, subsets, scores, statuses] = ...
                runMaxDirectionalSearch(candidateSensitivity, allNames, ...
                stimulusNames, opts, availableSubsetCount, nCandidates, selectableMask);
        case 'wls-l1per'
            [bestCurrents, bestScore, bestSubset, subsets, scores, statuses, focalInfo] = ...
                runWeightedFocalSearch(resultData.A_all, meshData.node, ...
                brainNodes, targetNodes, candidateSensitivity, allNames, ...
                stimulusNames, orientation, targetWeights, opts, nCandidates, selectableMask);
        otherwise
            error('acsOptimizeSparseRoastLeadField:BadOptType', ...
                'Unsupported optimization type: %s', opts.optType);
    end

    if ~any(cellfun(@isSolved, statuses))
        error('acsOptimizeSparseRoastLeadField:NoSolvedMontage', ...
            'ROAST CVX optimization did not return a solved montage.');
    end
    selected = find(abs(bestCurrents) > opts.currentThresholdMa);
    if numel(selected) ~= opts.activeElectrodeCount
        warning('acsOptimizeSparseRoastLeadField:ActiveCountMismatch', ...
            ['Requested %d active electrodes, but %s returned %d above ', ...
             'the reporting threshold of %.6g mA. Inspect the montage.'], ...
            opts.activeElectrodeCount, opts.searchMode, numel(selected), ...
            opts.currentThresholdMa);
    end
    basisCoefficients = basisCoefficientsFromCurrents( ...
        bestCurrents, allNames, stimulusNames);
    targetProjectedField = projectedFieldAtTargets(resultData.A_all, ...
        basisCoefficients, targetNodes, orientation);

    out = struct();
    out.createdOn = char(datetime('now'));
    out.t1File = t1File;
    out.leadFieldTag = leadFieldTag;
    out.targetVoxel = targetVoxel;
    out.orientation = orientation;
    out.targetWeights = targetWeights;
    out.targetRadiusMm = opts.targetRadiusMm;
    out.targetNodeCounts = cellfun(@numel, targetNodes);
    out.activeElectrodeCountRequested = opts.activeElectrodeCount;
    out.activeElectrodeCountReturned = numel(selected);
    out.searchMode = opts.searchMode;
    out.availableSubsetCount = availableSubsetCount;
    out.subsetCount = size(subsets, 1);
    out.totalCurrentMa = opts.totalCurrentMa;
    out.maxCurrentPerElectrodeMa = opts.maxCurrentPerElectrodeMa;
    out.optType = opts.optType;
    out.desiredIntensityVm = opts.desiredIntensityVm;
    out.focalityK = opts.focalityK;
    out.focalInfo = focalInfo;
    out.electrodeNames = allNames;
    out.leadFieldApproximation = approximationInfo;
    out.selectableElectrodeMask = selectableMask(:);
    out.excludedElectrodeNames = allNames(~selectableMask);
    out.referenceElectrode = leadField.referenceElectrode;
    out.candidateSensitivityVmPerMa = candidateSensitivity;
    out.selectedSubsetIndices = bestSubset(:);
    out.selectedIndices = selected(:);
    out.selectedNames = allNames(selected);
    out.selectedPredictedNames = selectedPredictedNames(allNames(selected), ...
        approximationInfo);
    out.selectedPredictedCount = numel(out.selectedPredictedNames);
    out.currentsMa = bestCurrents;
    out.selectedCurrentsMa = bestCurrents(selected);
    out.objectiveVm = bestScore;
    out.targetProjectedFieldVm = targetProjectedField;
    out.basisCoefficientsMa = basisCoefficients;
    out.subsets = subsets;
    out.subsetObjectiveVm = scores;
    out.subsetStatus = statuses;
    out.recipe = makeRecipe(allNames(selected), bestCurrents(selected));
    out.fullRecipe = makeRecipe(allNames, bestCurrents);
    out.targetingTag = opts.targetingTag;
    [compactStem, fileNameInfo] = compactSparseFileStem(stem, leadFieldTag, ...
        opts.targetingTag, out, opts);
    out.fileNameInfo = fileNameInfo;
    out.reportMat = fullfile(folder, [compactStem '.mat']);
    out.qcFigure = '';
    out.customLocationsFile = candidateLocationsFile(folder, stem, leadFieldTag);
    [out.candidateVoxelCoordinates, out.selectedVoxelCoordinates] = ...
        readCandidateCoordinates(out.customLocationsFile, allNames, selected);

    if opts.returnMeshField
        out.meshFieldVm = reconstructMeshField(resultData.A_all, basisCoefficients);
    end

    fig = [];
    if opts.showFigures || opts.saveFigures
        figVisible = 'off';
        if opts.showFigures, figVisible = 'on'; end
        fig = makeQcFigure(out, figVisible);
        if opts.saveFigures
            qcDir = fullfile(folder, 'qc');
            ensureDir(qcDir);
            out.qcFigure = fullfile(qcDir, [compactStem '.png']);
            saveas(fig, out.qcFigure);
        end
        if ~opts.showFigures
            close(fig);
        end
    end

    if opts.saveReport
        save(out.reportMat, 'out');
    end
    if opts.verbose
        printSummary(out);
    end
end

function [fileStem, info] = compactSparseFileStem(t1Stem, leadFieldTag, ...
        targetingTag, out, opts)
    subjectTag = parseSubjectTag(t1Stem);
    lfTag = parseLeadFieldCountTag(leadFieldTag);
    activeTag = sprintf('tes%d', out.activeElectrodeCountRequested);
    modeTag = safeFileStem(out.searchMode);
    hashInput = strjoin({t1Stem, leadFieldTag, targetingTag, ...
        activeTag, modeTag, out.optType, sprintf('%.15g', opts.focalityK)}, '|');
    hashTag = shortHash(hashInput);

    fileStem = safeFileStem(strjoin({subjectTag, lfTag, activeTag, modeTag, ...
        hashTag}, '_'));
    if numel(fileStem) > opts.maxFilenameBaseChars
        keepN = max(16, opts.maxFilenameBaseChars - numel(hashTag) - 1);
        fileStem = [fileStem(1:keepN) '_' hashTag];
        fileStem = safeFileStem(fileStem);
    end

    info = struct();
    info.mode = 'compactHash';
    info.fileStem = fileStem;
    info.maxFilenameBaseChars = opts.maxFilenameBaseChars;
    info.longStem = safeFileStem([t1Stem '_' leadFieldTag '_' targetingTag]);
    info.hash = hashTag;
    info.subjectTag = subjectTag;
    info.leadFieldCountTag = lfTag;
    info.activeTag = activeTag;
    info.searchMode = out.searchMode;
    info.leadFieldTag = leadFieldTag;
    info.targetingTag = targetingTag;
end

function tag = parseSubjectTag(stem)
    stem = char(stem);
    tokens = regexp(stem, '(M\d+)', 'tokens', 'once');
    if ~isempty(tokens)
        tag = tokens{1};
        return;
    end
    parts = regexp(stem, '[_-]+', 'split');
    tag = parts{1};
    if isempty(tag)
        tag = 'subject';
    end
    tag = safeFileStem(tag);
end

function tag = parseLeadFieldCountTag(leadFieldTag)
    tokens = regexp(char(leadFieldTag), '(^|[_-])(lf\d+)($|[_-])', ...
        'tokens', 'once');
    if ~isempty(tokens)
        tag = tokens{2};
    else
        tag = 'lf';
    end
end

function stem = safeFileStem(stem)
    stem = regexprep(strtrim(char(stem)), '[^A-Za-z0-9_-]+', '_');
    stem = regexprep(stem, '_+', '_');
    stem = regexprep(stem, '^_+|_+$', '');
    if isempty(stem)
        stem = 'sparse';
    end
end

function h = shortHash(txt)
    txt = uint8(char(txt));
    value = 5381;
    modulus = 2 ^ 32;
    for i = 1:numel(txt)
        value = mod(value * 33 + double(txt(i)), modulus);
    end
    h = lower(dec2hex(round(value), 8));
end

function fileName = candidateLocationsFile(folder, stem, leadFieldTag)
    snapshot = fullfile(folder, [stem '_' leadFieldTag '_customLocations']);
    if exist(snapshot, 'file') == 2
        fileName = snapshot;
    else
        fileName = fullfile(folder, [stem '_customLocations']);
        warning('acsOptimizeSparseRoastLeadField:MissingLocationSnapshot', ...
            ['Lead field "%s" predates tagged custom-location snapshots. ', ...
             'Using the mutable default file for coordinate reporting.'], ...
            leadFieldTag);
    end
end

function info = leadFieldApproximationInfo(leadField, opt)
    info = struct( ...
        'approximate', false, ...
        'surrogateExpanded', false, ...
        'sourceLeadFieldTag', '', ...
        'predictedStimulusNames', {{}}, ...
        'copiedStimulusNames', {{}}, ...
        'warning', '');
    if isfield(leadField, 'approximate')
        info.approximate = logical(leadField.approximate);
    elseif isfield(opt, 'approximateLeadField')
        info.approximate = logical(opt.approximateLeadField);
    end
    if isfield(leadField, 'surrogateExpanded')
        info.surrogateExpanded = logical(leadField.surrogateExpanded);
    elseif isfield(opt, 'surrogateExpandedLeadField')
        info.surrogateExpanded = logical(opt.surrogateExpandedLeadField);
    end
    if isfield(leadField, 'sourceLeadFieldTag')
        info.sourceLeadFieldTag = char(leadField.sourceLeadFieldTag);
    end
    if isfield(leadField, 'approximation') && isstruct(leadField.approximation)
        A = leadField.approximation;
        if isfield(A, 'predictedStimulusNames')
            info.predictedStimulusNames = cellstr(A.predictedStimulusNames(:));
        end
        if isfield(A, 'copiedStimulusNames')
            info.copiedStimulusNames = cellstr(A.copiedStimulusNames(:));
        end
        if isfield(A, 'warning')
            info.warning = char(A.warning);
        end
        if isempty(info.sourceLeadFieldTag) && isfield(A, 'sourceLeadFieldTag')
            info.sourceLeadFieldTag = char(A.sourceLeadFieldTag);
        end
    end
    if isempty(info.warning) && isfield(opt, 'approximateLeadFieldWarning')
        info.warning = char(opt.approximateLeadFieldWarning);
    end
end

function names = selectedPredictedNames(selectedNames, approximationInfo)
    if ~isstruct(approximationInfo) || ...
            ~isfield(approximationInfo, 'predictedStimulusNames')
        names = {};
        return;
    end
    predicted = cellstr(approximationInfo.predictedStimulusNames(:));
    selectedNames = cellstr(selectedNames(:));
    isPredicted = ismember(lower(string(selectedNames)), lower(string(predicted)));
    names = selectedNames(isPredicted);
end

function opts = parseInputs(varargin)
    p = inputParser;
    p.FunctionName = 'acsOptimizeSparseRoastLeadField';
    addParameter(p, 'orientation', [0 0 1], ...
        @(x) isnumeric(x) && ismatrix(x) && size(x, 2) == 3 && ...
        all(isfinite(x(:))));
    addParameter(p, 'targetWeights', [], ...
        @(x) isempty(x) || (isnumeric(x) && isvector(x) && all(x >= 0)));
    addParameter(p, 'targetRadiusMm', 2, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x > 0);
    addParameter(p, 'activeElectrodeCount', 4, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && ...
        x >= 4 && x == round(x));
    addParameter(p, 'totalCurrentMa', 2, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x > 0);
    addParameter(p, 'maxCurrentPerElectrodeMa', [], ...
        @(x) isempty(x) || (isnumeric(x) && isscalar(x) && isfinite(x) && x > 0));
    addParameter(p, 'currentThresholdMa', 1e-6, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0);
    addParameter(p, 'optType', 'wls-l1per', @(x) ischar(x) || isstring(x));
    addParameter(p, 'desiredIntensityVm', 1, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x > 0);
    addParameter(p, 'focalityK', 0.02, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x > 0);
    addParameter(p, 'excludedElectrodeNames', {}, ...
        @(x) iscell(x) || ischar(x) || isstring(x));
    addParameter(p, 'selectableElectrodeNames', {}, ...
        @(x) iscell(x) || ischar(x) || isstring(x));
    addParameter(p, 'searchMode', 'globalCvx', @(x) ischar(x) || isstring(x));
    addParameter(p, 'targetingTag', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'maxFilenameBaseChars', 96, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 32);
    addParameter(p, 'maxSubsetCount', 100000, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 1);
    addParameter(p, 'returnMeshField', false, @isBoolLike);
    addParameter(p, 'showFigures', false, @isBoolLike);
    addParameter(p, 'saveFigures', false, @isBoolLike);
    addParameter(p, 'saveReport', true, @isBoolLike);
    addParameter(p, 'verbose', true, @isBoolLike);
    parse(p, varargin{:});
    opts = p.Results;
    opts.activeElectrodeCount = round(double(opts.activeElectrodeCount));
    opts.totalCurrentMa = double(opts.totalCurrentMa);
    if isempty(opts.maxCurrentPerElectrodeMa)
        opts.maxCurrentPerElectrodeMa = 2 * opts.totalCurrentMa / ...
            opts.activeElectrodeCount;
    else
        opts.maxCurrentPerElectrodeMa = double(opts.maxCurrentPerElectrodeMa);
    end
    opts.optType = normalizeOptType(opts.optType);
    opts.desiredIntensityVm = double(opts.desiredIntensityVm);
    opts.focalityK = double(opts.focalityK);
    opts.excludedElectrodeNames = normalizeNameList(opts.excludedElectrodeNames);
    opts.selectableElectrodeNames = normalizeNameList(opts.selectableElectrodeNames);
    opts.searchMode = normalizeSearchMode(opts.searchMode);
    opts.targetingTag = char(opts.targetingTag);
    if isempty(opts.targetingTag)
        if strcmp(opts.optType, 'wls-l1per')
            opts.targetingTag = sprintf('sparseWlsK%dFocal%g', ...
                opts.activeElectrodeCount, opts.focalityK);
        else
            opts.targetingTag = ['sparseMaxDirectionalK' ...
                num2str(opts.activeElectrodeCount)];
        end
    end
    opts.targetingTag = safeTag(opts.targetingTag);
    opts.maxFilenameBaseChars = round(double(opts.maxFilenameBaseChars));
    opts.maxSubsetCount = double(opts.maxSubsetCount);
    opts.returnMeshField = logical(opts.returnMeshField);
    opts.showFigures = logical(opts.showFigures);
    opts.saveFigures = logical(opts.saveFigures);
    opts.saveReport = logical(opts.saveReport);
    opts.verbose = logical(opts.verbose);
end

function optType = normalizeOptType(optType)
    optType = lower(strtrim(char(optType)));
    switch optType
        case {'max-l1per', 'maxl1per', 'max-directional', 'maxdirectional'}
            optType = 'max-l1per';
        case {'wls-l1per', 'wlsl1per', 'weighted-focal', 'weightedfocal'}
            optType = 'wls-l1per';
        otherwise
            error('acsOptimizeSparseRoastLeadField:BadOptType', ...
                'optType must be ''max-l1per'' or ''wls-l1per''.');
    end
end

function mode = normalizeSearchMode(mode)
    mode = lower(strtrim(char(mode)));
    switch mode
        case {'globalcvx', 'global', 'scalable', 'relaxed'}
            mode = 'globalCvx';
        case {'exhaustivecvx', 'exhaustive', 'enumerate'}
            mode = 'exhaustiveCvx';
        case {'developmentheuristic', 'heuristic', 'development', 'dummy', 'nocvx'}
            mode = 'developmentHeuristic';
        otherwise
            error('acsOptimizeSparseRoastLeadField:BadSearchMode', ...
                ['searchMode must be ''globalCvx'', ''exhaustiveCvx'', ', ...
                 'or ''developmentHeuristic''.']);
    end
end

function tf = isBoolLike(x)
    tf = (islogical(x) || isnumeric(x)) && isscalar(x);
end

function names = normalizeNameList(names)
    if isempty(names)
        names = {};
    elseif ischar(names) || isstring(names)
        names = cellstr(names(:));
    elseif iscell(names)
        names = cellfun(@char, names(:), 'UniformOutput', false);
    else
        error('acsOptimizeSparseRoastLeadField:BadNameList', ...
            'Electrode name lists must be char, string, or cell arrays.');
    end
    names = names(~cellfun(@isempty, names));
end

function mask = selectableElectrodeMask(allNames, excludedNames, selectableNames)
    allNames = cellfun(@char, allNames(:), 'UniformOutput', false);
    allLower = lowerCellstr(allNames);
    mask = true(numel(allNames), 1);
    if ~isempty(selectableNames)
        mask = ismember(allLower, lowerCellstr(selectableNames(:)));
    end
    if ~isempty(excludedNames)
        excludedLower = lowerCellstr(excludedNames(:));
        excluded = ismember(allLower, excludedLower);
        missing = setdiff(excludedLower, allLower);
        if ~isempty(missing)
            warning('acsOptimizeSparseRoastLeadField:ExcludedNameNotFound', ...
                'Excluded electrode name(s) not found in lead field: %s', ...
                strjoin(missing, ', '));
        end
        mask = mask & ~excluded;
    end
    if nnz(mask) < 1
        error('acsOptimizeSparseRoastLeadField:NoSelectableElectrodes', ...
            'No selectable electrodes remain after applying selection/exclusion lists.');
    end
end

function out = lowerCellstr(values)
    values = cellfun(@char, values(:), 'UniformOutput', false);
    out = cellfun(@lower, values, 'UniformOutput', false);
end

function addDependencies()
    repoRoot = fileparts(fileparts(mfilename('fullpath')));
    if exist('max_l1per', 'file') ~= 2
        addpath(repoRoot);
    end
    if exist('cvx_begin', 'file') ~= 2 || exist('spm_vol', 'file') ~= 2
        addpath(genpath(fullfile(repoRoot, 'lib')));
    end
end

function requireFile(fileName)
    if exist(fileName, 'file') ~= 2
        error('acsOptimizeSparseRoastLeadField:MissingFile', ...
            'Required file not found: %s', fileName);
    end
end

function targetVoxel = validateTargetVoxel(targetVoxel)
    validateattributes(targetVoxel, {'numeric'}, ...
        {'2d', 'real', 'finite', 'nonempty'});
    if size(targetVoxel, 2) ~= 3
        error('acsOptimizeSparseRoastLeadField:BadTargetShape', ...
            'targetVoxel must have three columns.');
    end
    targetVoxel = double(targetVoxel);
end

function validateSelectionSize(k, nCandidates)
    if mod(k, 2) ~= 0
        error('acsOptimizeSparseRoastLeadField:OddElectrodeCount', ...
            'activeElectrodeCount must be even for this sparse targeting workflow.');
    end
    if k > nCandidates
        error('acsOptimizeSparseRoastLeadField:TooManyElectrodes', ...
            'Requested %d active electrodes from only %d candidates.', ...
            k, nCandidates);
    end
end

function n = countSubsets(nCandidates, k)
    n = round(exp(gammaln(nCandidates + 1) - gammaln(k + 1) - ...
        gammaln(nCandidates - k + 1)));
end

function orientation = normalizeOrientations(orientation, nTargets)
    orientation = double(orientation);
    if size(orientation, 1) == 1 && nTargets > 1
        orientation = repmat(orientation, nTargets, 1);
    end
    if size(orientation, 1) ~= nTargets
        error('acsOptimizeSparseRoastLeadField:BadOrientationCount', ...
            'Provide one orientation or one orientation per target voxel.');
    end
    lengths = sqrt(sum(orientation .^ 2, 2));
    if any(lengths <= eps)
        error('acsOptimizeSparseRoastLeadField:ZeroOrientation', ...
            'Orientation vectors must have nonzero length.');
    end
    orientation = bsxfun(@rdivide, orientation, lengths);
end

function weights = normalizeWeights(weights, nTargets)
    if isempty(weights)
        weights = ones(nTargets, 1);
    end
    weights = double(weights(:));
    if numel(weights) ~= nTargets || sum(weights) <= 0
        error('acsOptimizeSparseRoastLeadField:BadWeights', ...
            'Provide one or more nonnegative target weights with a positive sum.');
    end
    weights = weights / sum(weights);
end

function brainNodes = findBrainNodes(elem)
    brainElem = elem(:, 5) == 1 | elem(:, 5) == 2;
    brainNodes = unique(elem(brainElem, 1:4));
    brainNodes = brainNodes(:);
    if isempty(brainNodes)
        error('acsOptimizeSparseRoastLeadField:NoBrainNodes', ...
            'Mesh does not contain white- or gray-matter elements.');
    end
end

function targetNodes = findTargetNodes(node, brainNodes, targetVoxel, voxelSize, radiusMm)
    brainMm = double(node(brainNodes, 1:3));
    targetMm = bsxfun(@times, targetVoxel, voxelSize);
    targetNodes = cell(size(targetVoxel, 1), 1);
    for i = 1:size(targetVoxel, 1)
        delta = bsxfun(@minus, brainMm, targetMm(i, :));
        inside = sqrt(sum(delta .^ 2, 2)) < radiusMm;
        targetNodes{i} = brainNodes(inside);
        if isempty(targetNodes{i})
            error('acsOptimizeSparseRoastLeadField:NoTargetNodes', ...
                ['No brain mesh nodes were found within %.3g mm of target ', ...
                 'voxel [%g %g %g]. Increase targetRadiusMm or inspect the target.'], ...
                radiusMm, targetVoxel(i, 1), targetVoxel(i, 2), targetVoxel(i, 3));
        end
    end
end

function sensitivity = candidateDirectionalSensitivity(A, allNames, stimulusNames, ...
        targetNodes, orientation, targetWeights)
    sensitivity = zeros(numel(allNames), 1);
    for i = 1:numel(allNames)
        basisIdx = find(strcmpi(allNames{i}, stimulusNames), 1);
        if isempty(basisIdx)
            continue;
        end
        for j = 1:numel(targetNodes)
            meanField = mean(A(targetNodes{j}, :, basisIdx), 1);
            sensitivity(i) = sensitivity(i) + ...
                targetWeights(j) * dot(meanField, orientation(j, :));
        end
    end
end

function [bestCurrents, bestScore, bestSubset, subsets, scores, statuses] = ...
        runMaxDirectionalSearch(candidateSensitivity, allNames, stimulusNames, ...
        opts, availableSubsetCount, nCandidates, selectableMask)
    selectableRows = find(selectableMask(:)).';
    switch opts.searchMode
        case 'globalCvx'
            if opts.verbose
                fprintf('\nRunning one global max-l1per solve (%d requested active electrodes of %d candidates)...\n', ...
                    opts.activeElectrodeCount, nCandidates);
            end
            [globalCurrents, globalScore, globalStatus] = optimizeGlobal( ...
                candidateSensitivity, allNames, stimulusNames, ...
                opts.totalCurrentMa, opts.maxCurrentPerElectrodeMa, ...
                selectableMask);
            subsets = find(abs(globalCurrents) > opts.currentThresholdMa)';
            scores = globalScore;
            currents = globalCurrents;
            statuses = {globalStatus};
        case 'exhaustiveCvx'
            if availableSubsetCount > opts.maxSubsetCount
                error('acsOptimizeSparseRoastLeadField:TooManySubsets', ...
                    ['Exhaustive search would evaluate %.0f subsets, above the ', ...
                     'configured maxSubsetCount of %.0f. Use searchMode ', ...
                     '''globalCvx'' or a smaller candidate set.'], ...
                    availableSubsetCount, opts.maxSubsetCount);
            end
            subsets = nchoosek(selectableRows, opts.activeElectrodeCount);
            scores = -inf(size(subsets, 1), 1);
            currents = zeros(nCandidates, size(subsets, 1));
            statuses = cell(size(subsets, 1), 1);
            if opts.verbose
                fprintf('\nSearching %d candidate subsets (%d active electrodes of %d)...\n', ...
                    size(subsets, 1), opts.activeElectrodeCount, nCandidates);
            end
            for i = 1:size(subsets, 1)
                subset = subsets(i, :);
                [subsetCurrents, scores(i), statuses{i}] = optimizeSubset( ...
                    subset, candidateSensitivity, opts.totalCurrentMa, ...
                    opts.maxCurrentPerElectrodeMa);
                currents(:, i) = subsetCurrents;
            end
        otherwise
            error('acsOptimizeSparseRoastLeadField:BadSearchMode', ...
                'Unsupported search mode: %s', opts.searchMode);
    end

    solved = cellfun(@isSolved, statuses);
    if strcmp(opts.searchMode, 'globalCvx')
        bestCurrents = currents;
        bestScore = scores;
        bestSubset = subsets;
        return;
    end
    scores(~solved) = -inf;
    [bestScore, bestIndex] = max(scores);
    bestCurrents = currents(:, bestIndex);
    bestSubset = subsets(bestIndex, :);
end

function [bestCurrents, bestScore, bestSubset, subsets, scores, statuses, info] = ...
        runWeightedFocalSearch(A_all, ~, brainNodes, targetNodes, ...
        candidateSensitivity, allNames, stimulusNames, orientation, ...
        targetWeights, opts, nCandidates, selectableMask)
    if strcmp(opts.searchMode, 'developmentHeuristic')
        [designMatrix, desiredField, weights, targetMask, nodeWeights] = ...
            buildWeightedFocalSystem(A_all, brainNodes, targetNodes, ...
            orientation, targetWeights, opts.desiredIntensityVm, opts.focalityK);
        [bestCurrents, bestScore, bestSubset, subsets, scores, statuses, info] = ...
            runDevelopmentHeuristicWls(designMatrix, desiredField, weights, ...
            targetMask, nodeWeights, candidateSensitivity, allNames, ...
            stimulusNames, opts, nCandidates, brainNodes, selectableMask);
        return;
    end
    if ~strcmp(opts.searchMode, 'globalCvx')
        warning('acsOptimizeSparseRoastLeadField:WlsIgnoresSearchMode', ...
            ['wls-l1per currently uses a global relaxation plus top-K ', ...
             'refinement. Ignoring searchMode="%s".'], opts.searchMode);
    end
    if opts.verbose
        fprintf('\nRunning global wls-l1per focal solve (%d requested active electrodes of %d candidates)...\n', ...
            opts.activeElectrodeCount, nCandidates);
    end

    [designMatrix, desiredField, weights, targetMask, nodeWeights] = ...
        buildWeightedFocalSystem(A_all, brainNodes, targetNodes, ...
        orientation, targetWeights, opts.desiredIntensityVm, opts.focalityK);
    maxCurrentPerElectrodeMa = opts.maxCurrentPerElectrodeMa;

    selectableStimulusMask = ismember(lowerCellstr(stimulusNames(:)), ...
        lowerCellstr(allNames(selectableMask)));
    [stimulusCurrents, globalStatus, globalResidual] = solveWlsGlobal( ...
        designMatrix, desiredField, weights, opts.totalCurrentMa, ...
        maxCurrentPerElectrodeMa, selectableStimulusMask, false);
    if ~isSolved(globalStatus)
        bestCurrents = zeros(numel(allNames), 1);
        bestScore = -inf;
        bestSubset = [];
        subsets = zeros(0, opts.activeElectrodeCount);
        scores = -inf;
        statuses = {globalStatus};
        info = struct( ...
            'globalStatus', globalStatus, ...
            'refinedStatus', '', ...
            'globalWeightedResidual', globalResidual, ...
            'refinedWeightedResidual', inf, ...
            'globalActiveCount', 0, ...
            'targetBrainNodeCount', nnz(targetMask), ...
            'brainNodeCount', numel(brainNodes), ...
            'focalityK', opts.focalityK, ...
            'desiredIntensityVm', opts.desiredIntensityVm, ...
            'targetWeightMean', mean(nodeWeights(targetMask)));
        return;
    end

    globalCurrents = currentsFromStimulus(stimulusCurrents, ...
        allNames, stimulusNames);
    selectedTopK = selectTopKCurrents(globalCurrents, ...
        opts.activeElectrodeCount, selectableMask);
    if opts.verbose
        fprintf('Refining wls-l1per solution on top %d physical contacts...\n', ...
            opts.activeElectrodeCount);
    end
    [refinedCurrents, refinedStatus, refinedResidual] = solveWlsSelected( ...
        designMatrix, desiredField, weights, allNames, stimulusNames, ...
        selectedTopK, opts.totalCurrentMa, maxCurrentPerElectrodeMa, false);

    if isSolved(refinedStatus)
        bestCurrents = refinedCurrents;
        bestSubset = selectedTopK(:)';
        bestStatus = refinedStatus;
        bestResidual = refinedResidual;
    else
        warning('acsOptimizeSparseRoastLeadField:WlsRefineFailed', ...
            ['The top-K wls-l1per refinement returned status "%s"; ', ...
             'falling back to the global relaxed solution.'], refinedStatus);
        bestCurrents = globalCurrents;
        bestSubset = find(abs(globalCurrents) > opts.currentThresholdMa)';
        bestStatus = globalStatus;
        bestResidual = globalResidual;
    end

    bestScore = dot(candidateSensitivity, bestCurrents);
    subsets = bestSubset;
    scores = bestScore;
    statuses = {bestStatus};
    info = struct( ...
        'globalStatus', globalStatus, ...
        'refinedStatus', refinedStatus, ...
        'globalWeightedResidual', globalResidual, ...
        'refinedWeightedResidual', refinedResidual, ...
        'selectedTopKIndices', selectedTopK(:), ...
        'selectedTopKNames', {allNames(selectedTopK)}, ...
        'globalCurrentsMa', globalCurrents, ...
        'globalActiveCount', nnz(abs(globalCurrents) > opts.currentThresholdMa), ...
        'targetBrainNodeCount', nnz(targetMask), ...
        'brainNodeCount', numel(brainNodes), ...
        'focalityK', opts.focalityK, ...
        'desiredIntensityVm', opts.desiredIntensityVm, ...
        'targetWeightMean', mean(nodeWeights(targetMask)), ...
        'chosenWeightedResidual', bestResidual);
end

function [designMatrix, desiredField, weights, targetMask, nodeWeights] = ...
        buildWeightedFocalSystem(A_all, brainNodes, targetNodes, ...
        orientation, targetWeights, desiredIntensityVm, focalityK)
    nBrain = numel(brainNodes);
    nBasis = size(A_all, 3);
    designMatrix = zeros(nBrain * 3, nBasis);
    designMatrix(1:nBrain, :) = reshape(A_all(brainNodes, 1, :), ...
        nBrain, nBasis);
    designMatrix(nBrain + (1:nBrain), :) = reshape(A_all(brainNodes, 2, :), ...
        nBrain, nBasis);
    designMatrix(2 * nBrain + (1:nBrain), :) = reshape(A_all(brainNodes, 3, :), ...
        nBrain, nBasis);

    desiredByNode = zeros(nBrain, 3);
    targetPriority = zeros(nBrain, 1);
    for i = 1:numel(targetNodes)
        [tf, localIdx] = ismember(targetNodes{i}, brainNodes);
        localIdx = localIdx(tf);
        if isempty(localIdx)
            continue;
        end
        desiredByNode(localIdx, :) = desiredByNode(localIdx, :) + ...
            targetWeights(i) * repmat(orientation(i, :), numel(localIdx), 1);
        targetPriority(localIdx) = targetPriority(localIdx) + targetWeights(i);
    end
    targetMask = targetPriority > 0;
    if ~any(targetMask)
        error('acsOptimizeSparseRoastLeadField:NoWeightedTargets', ...
            'No target nodes survived inside the brain-node set.');
    end
    desiredByNode(targetMask, :) = desiredIntensityVm * bsxfun(@rdivide, ...
        desiredByNode(targetMask, :), targetPriority(targetMask));
    desiredField = [desiredByNode(:, 1); desiredByNode(:, 2); ...
        desiredByNode(:, 3)];

    nTarget = nnz(targetMask);
    nNontarget = nBrain - nTarget;
    if nNontarget <= 0
        error('acsOptimizeSparseRoastLeadField:NoNontargetNodes', ...
            'The target mask covers every brain node; focal weighting needs non-target nodes.');
    end
    targetWeight = nBrain / nTarget * (focalityK / (focalityK + 1));
    nontargetWeight = nTarget / nNontarget * (targetWeight / focalityK);
    nodeWeights = nontargetWeight * ones(nBrain, 1);
    priority = targetPriority(targetMask);
    priority = priority / mean(priority);
    nodeWeights(targetMask) = targetWeight * priority;
    weights = [nodeWeights; nodeWeights; nodeWeights];
end

function [bestCurrents, bestScore, bestSubset, subsets, scores, statuses, info] = ...
        runDevelopmentHeuristicWls(designMatrix, desiredField, weights, ...
        targetMask, nodeWeights, candidateSensitivity, allNames, stimulusNames, ...
        opts, nCandidates, brainNodes, selectableMask)
    if opts.verbose
        fprintf('\nRunning development heuristic wls-l1per solve without CVX (%d requested active electrodes of %d candidates)...\n', ...
            opts.activeElectrodeCount, nCandidates);
    end

    selected = selectHeuristicSubset(candidateSensitivity, opts.activeElectrodeCount, ...
        selectableMask);
    maxCurrentPerElectrodeMa = opts.maxCurrentPerElectrodeMa;
    bestCurrents = heuristicBalancedCurrents(candidateSensitivity, selected, ...
        opts.totalCurrentMa, maxCurrentPerElectrodeMa);
    bestCurrents = min(max(bestCurrents, -maxCurrentPerElectrodeMa), maxCurrentPerElectrodeMa);
    bestCurrents = rebalanceSelectedCurrents(bestCurrents, selected, maxCurrentPerElectrodeMa);

    basisCoefficients = basisCoefficientsFromCurrentsForHeuristic( ...
        bestCurrents, allNames, stimulusNames);
    residual = weightedResidualForCoefficients(designMatrix, desiredField, ...
        weights, basisCoefficients);
    bestScore = dot(candidateSensitivity, bestCurrents);
    bestSubset = selected(:)';
    subsets = bestSubset;
    scores = bestScore;
    statuses = {'Solved developmentHeuristic'};
    info = struct( ...
        'globalStatus', 'Skipped CVX', ...
        'refinedStatus', 'Solved developmentHeuristic', ...
        'globalWeightedResidual', NaN, ...
        'refinedWeightedResidual', residual, ...
        'selectedTopKIndices', selected(:), ...
        'selectedTopKNames', {allNames(selected)}, ...
        'globalCurrentsMa', bestCurrents, ...
        'globalActiveCount', nnz(abs(bestCurrents) > opts.currentThresholdMa), ...
        'targetBrainNodeCount', nnz(targetMask), ...
        'brainNodeCount', numel(brainNodes), ...
        'focalityK', opts.focalityK, ...
        'desiredIntensityVm', opts.desiredIntensityVm, ...
        'targetWeightMean', mean(nodeWeights(targetMask)), ...
        'chosenWeightedResidual', residual, ...
        'warning', 'Development heuristic only; no CVX optimization was run.');
end

function selected = selectHeuristicSubset(sensitivity, k, selectableMask)
    sortable = abs(sensitivity(:));
    sortable(~selectableMask(:)) = -inf;
    [~, order] = sort(sortable, 'descend');
    selected = sort(order(1:k));
end

function currents = heuristicBalancedCurrents(sensitivity, selected, ...
        totalCurrentMa, maxCurrentPerElectrodeMa)
    currents = zeros(numel(sensitivity), 1);
    s = sensitivity(selected);
    [~, order] = sort(s, 'descend');
    nSource = max(1, floor(numel(selected) / 2));
    nSink = numel(selected) - nSource;
    if nSink == 0
        return;
    end
    sources = selected(order(1:nSource));
    sinks = selected(order((nSource + 1):end));
    currents(sources) = totalCurrentMa / nSource;
    currents(sinks) = -totalCurrentMa / nSink;
    currents = min(max(currents, -maxCurrentPerElectrodeMa), maxCurrentPerElectrodeMa);
end

function currents = rebalanceSelectedCurrents(currents, selected, maxCurrentPerElectrodeMa)
    imbalance = sum(currents(selected));
    if abs(imbalance) <= eps
        return;
    end
    currents(selected) = currents(selected) - imbalance / numel(selected);
    currents(selected) = min(max(currents(selected), -maxCurrentPerElectrodeMa), ...
        maxCurrentPerElectrodeMa);
end

function coefficients = basisCoefficientsFromCurrentsForHeuristic( ...
        currents, allNames, stimulusNames)
    coefficients = zeros(numel(stimulusNames), 1);
    for i = 1:numel(stimulusNames)
        idx = find(strcmpi(stimulusNames{i}, allNames), 1);
        if ~isempty(idx)
            coefficients(i) = currents(idx);
        end
    end
end

function residual = weightedResidualForCoefficients(designMatrix, desiredField, ...
        weights, coefficients)
    sqrtWeights = sqrt(weights(:));
    weightedDesign = bsxfun(@times, designMatrix, sqrtWeights);
    weightedDesired = sqrtWeights .* desiredField(:);
    residual = norm(weightedDesign * coefficients(:) - weightedDesired, 2);
end

function [stimulusCurrents, status, weightedResidual] = solveWlsGlobal( ...
        designMatrix, desiredField, weights, totalCurrentMa, ...
        maxCurrentPerElectrodeMa, selectableStimulusMask, verbose)
    nBasis = size(designMatrix, 2);
    selectableStimulusMask = logical(selectableStimulusMask(:));
    if numel(selectableStimulusMask) ~= nBasis
        error('acsOptimizeSparseRoastLeadField:BadSelectableStimulusMask', ...
            'Selectable stimulus mask does not match the lead-field basis size.');
    end
    invalidStimulusRows = find(~selectableStimulusMask);
    sqrtWeights = sqrt(weights(:));
    weightedDesign = bsxfun(@times, designMatrix, sqrtWeights);
    weightedDesired = sqrtWeights .* desiredField(:);
    if verbose
        cvx_begin
    else
        cvx_begin quiet
    end
              variable stimulusCurrents(nBasis);
              minimize( norm(weightedDesign * stimulusCurrents - ...
                  weightedDesired, 2) );
               subject to
                  norm([stimulusCurrents; -sum(stimulusCurrents)], 1) <= ...
                      2 * totalCurrentMa;
                  norm([stimulusCurrents; -sum(stimulusCurrents)], inf) <= ...
                      maxCurrentPerElectrodeMa;
                  if ~isempty(invalidStimulusRows)
                      stimulusCurrents(invalidStimulusRows) == 0;
                  end
    cvx_end
    status = cvx_status;
    if isSolved(status)
        weightedResidual = norm(weightedDesign * stimulusCurrents - ...
            weightedDesired, 2);
    else
        weightedResidual = inf;
        stimulusCurrents = zeros(nBasis, 1);
    end
end

function [fullCurrents, status, weightedResidual] = solveWlsSelected( ...
        designMatrix, desiredField, weights, allNames, stimulusNames, ...
        selected, totalCurrentMa, maxCurrentPerElectrodeMa, verbose)
    nSelected = numel(selected);
    selectedDesign = zeros(size(designMatrix, 1), nSelected);
    for i = 1:nSelected
        basisIdx = find(strcmpi(allNames{selected(i)}, stimulusNames), 1);
        if ~isempty(basisIdx)
            selectedDesign(:, i) = designMatrix(:, basisIdx);
        end
    end

    sqrtWeights = sqrt(weights(:));
    weightedDesign = bsxfun(@times, selectedDesign, sqrtWeights);
    weightedDesired = sqrtWeights .* desiredField(:);
    if verbose
        cvx_begin
    else
        cvx_begin quiet
    end
              variable selectedCurrents(nSelected);
              minimize( norm(weightedDesign * selectedCurrents - ...
                  weightedDesired, 2) );
               subject to
                  sum(selectedCurrents) == 0;
                  norm(selectedCurrents, 1) <= 2 * totalCurrentMa;
                  norm(selectedCurrents, inf) <= maxCurrentPerElectrodeMa;
    cvx_end
    status = cvx_status;
    fullCurrents = zeros(numel(allNames), 1);
    if isSolved(status)
        fullCurrents(selected) = selectedCurrents;
        weightedResidual = norm(weightedDesign * selectedCurrents - ...
            weightedDesired, 2);
    else
        weightedResidual = inf;
    end
end

function fullCurrents = currentsFromStimulus(stimulusCurrents, ...
        allNames, stimulusNames)
    fullCurrents = zeros(numel(allNames), 1);
    stimulusIndices = zeros(numel(stimulusNames), 1);
    for i = 1:numel(stimulusNames)
        stimulusIndices(i) = find(strcmpi(stimulusNames{i}, allNames), 1);
    end
    fullCurrents(stimulusIndices) = stimulusCurrents;
    referenceIndex = find(~ismember(1:numel(allNames), stimulusIndices), 1);
    if isempty(referenceIndex)
        error('acsOptimizeSparseRoastLeadField:MissingReference', ...
            'Custom lead-field metadata does not identify a reference electrode.');
    end
    fullCurrents(referenceIndex) = -sum(stimulusCurrents);
end

function selected = selectTopKCurrents(currents, k, selectableMask)
    sortableCurrents = abs(currents(:));
    sortableCurrents(~selectableMask(:)) = -inf;
    sortableCurrents(~isfinite(sortableCurrents)) = -inf;
    [~, order] = sort(sortableCurrents, 'descend');
    selected = sort(order(1:k));
end

function [fullCurrents, score, status] = optimizeSubset(subset, sensitivity, ...
        totalCurrentMa, maxCurrentPerElectrodeMa)
    localRef = subset(end);
    localStim = subset(1:end-1);
    localSensitivity = sensitivity(localStim) - sensitivity(localRef);
    [localCurrents, status] = solveMaxDirectionalCvx( ...
        localSensitivity, totalCurrentMa, maxCurrentPerElectrodeMa, 0);
    fullCurrents = zeros(numel(sensitivity), 1);
    fullCurrents(localStim) = localCurrents;
    fullCurrents(localRef) = -sum(localCurrents);
    score = dot(sensitivity, fullCurrents);
end

function [fullCurrents, score, status] = optimizeGlobal( ...
        sensitivity, allNames, stimulusNames, totalCurrentMa, ...
        maxCurrentPerElectrodeMa, selectableMask)
    stimulusIndices = zeros(numel(stimulusNames), 1);
    for i = 1:numel(stimulusNames)
        stimulusIndices(i) = find(strcmpi(stimulusNames{i}, allNames), 1);
    end
    stimulusIndices = stimulusIndices(selectableMask(stimulusIndices));
    [stimulusCurrents, status] = solveMaxDirectionalCvx( ...
        sensitivity(stimulusIndices), totalCurrentMa, ...
        maxCurrentPerElectrodeMa, 0);
    fullCurrents = zeros(numel(allNames), 1);
    fullCurrents(stimulusIndices) = stimulusCurrents;
    referenceIndex = find(selectableMask(:).' & ...
        ~ismember(1:numel(allNames), stimulusIndices), 1);
    if isempty(referenceIndex)
        error('acsOptimizeSparseRoastLeadField:MissingReference', ...
            ['Custom lead-field metadata does not identify a selectable ', ...
             'reference electrode. Do not exclude the passive reference ', ...
             'when using max-l1per/globalCvx.']);
    end
    fullCurrents(referenceIndex) = -sum(stimulusCurrents);
    score = dot(sensitivity, fullCurrents);
end

function [x, status] = solveMaxDirectionalCvx(f, totalCurrentMa, ...
        maxCurrentPerElectrodeMa, verbose)
    n = size(f, 1);
    if verbose
        cvx_begin
    else
        cvx_begin quiet
    end
              variable x(n);
              maximize( sum(f' * x) );
               subject to
                  norm([x; -sum(x)], 1) <= 2 * totalCurrentMa;
                  norm([x; -sum(x)], inf) <= maxCurrentPerElectrodeMa;
    cvx_end
    status = cvx_status;
end

function tf = isSolved(status)
    tf = (ischar(status) || (isstring(status) && isscalar(status))) && ...
        ~isempty(strfind(lower(char(status)), 'solved')); %#ok<STREMP>
end

function tag = safeTag(tag)
    tag = regexprep(strtrim(char(tag)), '[^A-Za-z0-9_-]+', '_');
    tag = regexprep(tag, '_+', '_');
    tag = regexprep(tag, '^_+|_+$', '');
    if isempty(tag)
        error('acsOptimizeSparseRoastLeadField:BadTargetingTag', ...
            'targetingTag must contain at least one filename-safe character.');
    end
end

function coefficients = basisCoefficientsFromCurrents(currents, allNames, stimulusNames)
    coefficients = zeros(numel(stimulusNames), 1);
    for i = 1:numel(stimulusNames)
        idx = find(strcmpi(stimulusNames{i}, allNames), 1);
        coefficients(i) = currents(idx);
    end
end

function values = projectedFieldAtTargets(A, coefficients, targetNodes, orientation)
    values = zeros(numel(targetNodes), 1);
    for i = 1:numel(targetNodes)
        field = reconstructFieldRows(A, coefficients, targetNodes{i});
        values(i) = dot(mean(field, 1), orientation(i, :));
    end
end

function field = reconstructMeshField(A, coefficients)
    field = reconstructFieldRows(A, coefficients, 1:size(A, 1));
end

function field = reconstructFieldRows(A, coefficients, rows)
    field = sum(bsxfun(@times, A(rows, :, :), ...
        reshape(coefficients, 1, 1, [])), 3);
end

function recipe = makeRecipe(names, currents)
    recipe = reshape([names(:), num2cell(currents(:))]', 1, []);
end

function [candidateCoords, selectedCoords] = readCandidateCoordinates(fileName, names, selected)
    candidateCoords = [];
    selectedCoords = [];
    if exist(fileName, 'file') ~= 2
        return;
    end
    fid = fopen(fileName, 'r');
    if fid == -1
        return;
    end
    cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
    C = textscan(fid, '%s %f %f %f');
    fileNames = C{1};
    fileCoords = [C{2}, C{3}, C{4}];
    candidateCoords = nan(numel(names), 3);
    for i = 1:numel(names)
        idx = find(strcmpi(names{i}, fileNames), 1);
        if ~isempty(idx)
            candidateCoords(i, :) = fileCoords(idx, :);
        end
    end
    selectedCoords = candidateCoords(selected, :);
end

function fig = makeQcFigure(out, visible)
    fig = figure('Name', 'Sparse ROAST targeting QC', 'Color', 'w', ...
        'Visible', visible, 'Position', [100 100 1200 420]);

    ax1 = subplot(1, 3, 1, 'Parent', fig);
    bar(ax1, out.currentsMa, 'FaceColor', [0.15 0.45 0.75]);
    hold(ax1, 'on');
    yline(ax1, 0, 'k-');
    xticks(ax1, 1:numel(out.electrodeNames));
    xticklabels(ax1, out.electrodeNames);
    xtickangle(ax1, 45);
    ylabel(ax1, 'Current (mA)');
    title(ax1, 'Selected montage');
    grid(ax1, 'on');

    ax2 = subplot(1, 3, 2, 'Parent', fig);
    bar(ax2, out.candidateSensitivityVmPerMa, 'FaceColor', [0.25 0.65 0.35]);
    hold(ax2, 'on');
    yline(ax2, 0, 'k-');
    xticks(ax2, 1:numel(out.electrodeNames));
    xticklabels(ax2, out.electrodeNames);
    xtickangle(ax2, 45);
    ylabel(ax2, 'Mean directional field (V/m per mA)');
    title(ax2, 'Candidate sensitivity');
    grid(ax2, 'on');

    ax3 = subplot(1, 3, 3, 'Parent', fig);
    if strcmp(out.optType, 'wls-l1per')
        axis(ax3, 'off');
        text(ax3, 0.05, 0.82, 'Weighted focal solve', ...
            'Units', 'normalized', 'FontWeight', 'bold');
        text(ax3, 0.05, 0.66, sprintf('Desired target field: %.6g V/m', ...
            out.desiredIntensityVm), 'Units', 'normalized');
        text(ax3, 0.05, 0.54, sprintf('Focality k: %.6g', ...
            out.focalityK), 'Units', 'normalized');
        if isfield(out.focalInfo, 'globalWeightedResidual')
            text(ax3, 0.05, 0.42, sprintf('Global residual: %.6g', ...
                out.focalInfo.globalWeightedResidual), 'Units', 'normalized');
        end
        if isfield(out.focalInfo, 'chosenWeightedResidual')
            text(ax3, 0.05, 0.30, sprintf('Chosen residual: %.6g', ...
                out.focalInfo.chosenWeightedResidual), 'Units', 'normalized');
        end
        text(ax3, 0.05, 0.18, sprintf('Target projection: %.6g V/m', ...
            out.objectiveVm), 'Units', 'normalized');
        title(ax3, 'Focal targeting');
    elseif strcmp(out.searchMode, 'globalCvx')
        axis(ax3, 'off');
        text(ax3, 0.05, 0.78, 'Global max-l1per solve', ...
            'Units', 'normalized', 'FontWeight', 'bold');
        text(ax3, 0.05, 0.60, sprintf('Candidates: %d', ...
            numel(out.electrodeNames)), 'Units', 'normalized');
        text(ax3, 0.05, 0.48, sprintf('Requested active contacts: %d', ...
            out.activeElectrodeCountRequested), 'Units', 'normalized');
        text(ax3, 0.05, 0.36, sprintf('Returned active contacts: %d', ...
            out.activeElectrodeCountReturned), 'Units', 'normalized');
        text(ax3, 0.05, 0.24, sprintf('Objective: %.6g V/m', ...
            out.objectiveVm), 'Units', 'normalized');
        title(ax3, 'Scalable targeting');
    else
        validScores = out.subsetObjectiveVm(isfinite(out.subsetObjectiveVm));
        histogram(ax3, validScores, min(25, max(5, numel(validScores))));
        hold(ax3, 'on');
        xline(ax3, out.objectiveVm, 'r-', 'LineWidth', 2);
        xlabel(ax3, 'Mean directional field (V/m)');
        ylabel(ax3, 'Candidate subsets');
        title(ax3, sprintf('Best %d-of-%d subset', ...
            out.activeElectrodeCountRequested, numel(out.electrodeNames)));
        grid(ax3, 'on');
    end
end

function ensureDir(folder)
    if exist(folder, 'dir') ~= 7
        mkdir(folder);
    end
end

function printSummary(out)
    fprintf('\nSparse ROAST lead-field targeting\n');
    fprintf('  lead field tag: %s\n', out.leadFieldTag);
    fprintf('  optimization type: %s\n', out.optType);
    fprintf('  search mode: %s\n', out.searchMode);
    if isfield(out, 'leadFieldApproximation') && ...
            isfield(out.leadFieldApproximation, 'approximate') && ...
            out.leadFieldApproximation.approximate
        fprintf('  lead field source: approximate/surrogate-expanded');
        if ~isempty(out.leadFieldApproximation.sourceLeadFieldTag)
            fprintf(' from %s', out.leadFieldApproximation.sourceLeadFieldTag);
        end
        fprintf('\n');
        fprintf('  selected predicted electrodes: %d / %d\n', ...
            out.selectedPredictedCount, numel(out.selectedNames));
        if out.selectedPredictedCount > 0
            fprintf('    %s\n', strjoin(out.selectedPredictedNames(:)', ', '));
        end
    end
    if strcmp(out.optType, 'wls-l1per')
        fprintf('  solved: weighted focal relaxation plus top-%d refinement over %d candidate electrodes\n', ...
            out.activeElectrodeCountRequested, numel(out.electrodeNames));
        fprintf('  active electrodes returned: %d requested, %d above threshold\n', ...
            out.activeElectrodeCountRequested, out.activeElectrodeCountReturned);
        fprintf('  desired target field: %.6g V/m\n', out.desiredIntensityVm);
        fprintf('  focality k: %.6g\n', out.focalityK);
        if isfield(out.focalInfo, 'globalWeightedResidual')
            fprintf('  global weighted residual: %.6g\n', ...
                out.focalInfo.globalWeightedResidual);
        end
        if isfield(out.focalInfo, 'chosenWeightedResidual')
            fprintf('  chosen weighted residual: %.6g\n', ...
                out.focalInfo.chosenWeightedResidual);
        end
    elseif strcmp(out.searchMode, 'globalCvx')
        fprintf('  solved: one global relaxation over %d candidate electrodes\n', ...
            numel(out.electrodeNames));
        fprintf('  active electrodes returned: %d requested, %d above threshold\n', ...
            out.activeElectrodeCountRequested, out.activeElectrodeCountReturned);
    else
        fprintf('  searched: best %d of %d candidate electrodes (%d subsets)\n', ...
            out.activeElectrodeCountRequested, numel(out.electrodeNames), ...
            out.subsetCount);
    end
    fprintf('  maximum current per electrode: %.6g mA\n', ...
        out.maxCurrentPerElectrodeMa);
    fprintf('  target directional field: %.6g V/m\n', out.objectiveVm);
    fprintf('  selected montage:\n');
    for i = 1:numel(out.selectedNames)
        fprintf('    %s: %.6g mA\n', out.selectedNames{i}, out.selectedCurrentsMa(i));
    end
    fprintf('\n');
end
