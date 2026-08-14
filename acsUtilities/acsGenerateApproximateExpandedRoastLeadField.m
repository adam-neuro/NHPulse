function out = acsGenerateApproximateExpandedRoastLeadField(baseLayoutIn, baseLeadFieldIn, expandedLayoutIn, varargin)
% ACSGENERATEAPPROXIMATEEXPANDEDROASTLEADFIELD Append surrogate columns to a lead field.
%
% out = acsGenerateApproximateExpandedRoastLeadField(baseLayout, baseLeadField,
% expandedLayout) writes ROAST-style lead-field products for an expanded
% capMaker candidate layout without running ROAST/GetDP. Existing basis
% fields are copied from baseLeadField. New basis fields are Gaussian RBF
% predictions from the existing basis fields as a function of capMaker
% print-frame electrode position.
%
% This is intended only for iterative candidate-growth guidance. Run a real
% acsGenerateRoastLeadField solve on the final candidate layout before final
% scientific interpretation.
%
% Name-value options:
%   simulationTag      : output tag [<baseTag>_surrogateExpandedK#]
%   kernelSigmaMm      : RBF sigma in capMaker print mm ['auto']
%   referenceElectrode : fixed basis reference [base lead-field reference]
%   force              : overwrite existing approximate products [false]
%   saveReport         : save MAT request report beside T1 [true]
%   verbose            : print summary [true]

    if nargin < 3
        error('acsGenerateApproximateExpandedRoastLeadField:MissingInput', ...
            'Provide baseLayout, baseLeadField, and expandedLayout.');
    end

    opts = parseInputs(varargin{:});
    addLocalDependencies();

    baseLayout = readLayout(baseLayoutIn);
    expandedLayout = readLayout(expandedLayoutIn);
    baseTag = resolveLeadFieldTag(baseLeadFieldIn);
    t1File = resolveT1(baseLayout);
    expandedT1 = resolveT1(expandedLayout);
    if ~samePath(t1File, expandedT1)
        error('acsGenerateApproximateExpandedRoastLeadField:T1Mismatch', ...
            'baseLayout and expandedLayout refer to different T1 files.');
    end

    [folder, stem] = fileparts(t1File);
    baseFiles = leadFieldFiles(folder, stem, baseTag);
    requireFiles(baseFiles, {'roastResultMat', 'roastOptionsMat', 'meshMat'});
    baseResult = load(baseFiles.roastResultMat, 'A_all');
    baseOptions = load(baseFiles.roastOptionsMat, 'opt');
    if ~isfield(baseResult, 'A_all')
        error('acsGenerateApproximateExpandedRoastLeadField:MissingAAll', ...
            'Base result does not contain A_all: %s', baseFiles.roastResultMat);
    end
    if ~isfield(baseOptions, 'opt') || ~isfield(baseOptions.opt, 'leadField')
        error('acsGenerateApproximateExpandedRoastLeadField:MissingOptions', ...
            'Base options do not contain opt.leadField: %s', baseFiles.roastOptionsMat);
    end

    baseLeadField = baseOptions.opt.leadField;
    validateBaseLeadField(baseLeadField);
    baseNames = normalizeNames(baseLeadField.electrodeNames);
    baseStimulusNames = normalizeNames(baseLeadField.stimulusElectrodeNames);
    baseReference = char(baseLeadField.referenceElectrode);
    if isempty(opts.referenceElectrode)
        opts.referenceElectrode = baseReference;
    end
    if ~strcmpi(opts.referenceElectrode, baseReference)
        error('acsGenerateApproximateExpandedRoastLeadField:ReferenceChanged', ...
            ['Approximate expansion requires the same reference electrode as ', ...
             'the base lead field (%s).'], baseReference);
    end

    expandedNames = normalizeNames(expandedLayout.names);
    validateExpandedNames(baseNames, expandedNames, opts.referenceElectrode);
    expandedStimulusNames = expandedNames(~strcmpi(expandedNames, opts.referenceElectrode));
    if isempty(opts.simulationTag)
        opts.simulationTag = sprintf('%s_surrogateExpandedK%d', ...
            baseTag, numel(expandedNames));
    end
    opts.simulationTag = safeTag(opts.simulationTag);
    outFiles = leadFieldFiles(folder, stem, opts.simulationTag);
    requireNoOverwrite(outFiles, opts.force);

    baseCoords = coordsByName(baseLayout, baseStimulusNames);
    expandedCoords = coordsByName(expandedLayout, expandedStimulusNames);
    queryIsCopied = ismember(lower(string(expandedStimulusNames)), ...
        lower(string(baseStimulusNames)));
    queryNewRows = find(~queryIsCopied);
    queryNewCoords = expandedCoords(queryNewRows, :);

    surrogate = [];
    if ~isempty(queryNewRows)
        surrogate = acsKernelRegressLeadFieldFeatures(baseCoords, ...
            queryNewCoords, ...
            'sigmaMm', opts.kernelSigmaMm, ...
            'leaveOneOut', true);
    end

    A_all = expandLeadFieldMatrix(baseResult.A_all, baseStimulusNames, ...
        expandedStimulusNames, surrogate, queryNewRows);
    snapshot = snapshotCustomLocations(expandedLayout, outFiles.customLocations, ...
        expandedNames, opts.force);
    copyMeshFile(baseFiles.meshMat, outFiles.meshMat, opts.force);

    approximateLeadField = makeApproximationMetadata(t1File, baseTag, opts, ...
        baseFiles, outFiles, baseNames, baseStimulusNames, expandedNames, ...
        expandedStimulusNames, baseCoords, expandedCoords, surrogate, ...
        queryNewRows, snapshot);
    opt = makeExpandedOptions(baseOptions.opt, opts, expandedNames, ...
        expandedStimulusNames, snapshot, approximateLeadField);

    save(outFiles.roastResultMat, 'A_all', 'approximateLeadField', '-v7.3');
    save(outFiles.roastOptionsMat, 'opt', 'approximateLeadField');

    out = buildReport(t1File, opts, outFiles, approximateLeadField);
    if opts.saveReport
        save(outFiles.requestMat, 'out');
    end
    if opts.verbose
        printSummary(out);
    end
end

function opts = parseInputs(varargin)
    p = inputParser;
    p.FunctionName = 'acsGenerateApproximateExpandedRoastLeadField';
    addParameter(p, 'simulationTag', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'kernelSigmaMm', 'auto', ...
        @(x) (ischar(x) || isstring(x)) || ...
        (isnumeric(x) && isscalar(x) && isfinite(x) && x > 0));
    addParameter(p, 'referenceElectrode', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'force', false, @isBoolLike);
    addParameter(p, 'saveReport', true, @isBoolLike);
    addParameter(p, 'verbose', true, @isBoolLike);
    parse(p, varargin{:});
    opts = p.Results;
    opts.simulationTag = char(opts.simulationTag);
    opts.referenceElectrode = char(opts.referenceElectrode);
    opts.force = logical(opts.force);
    opts.saveReport = logical(opts.saveReport);
    opts.verbose = logical(opts.verbose);
end

function tf = isBoolLike(x)
    tf = (islogical(x) || isnumeric(x)) && isscalar(x);
end

function addLocalDependencies()
    repoRoot = fileparts(fileparts(mfilename('fullpath')));
    addpath(repoRoot);
    addpath(fullfile(repoRoot, 'acsUtilities'));
end

function layout = readLayout(value)
    if isstruct(value)
        layout = value;
        return;
    end
    if ~(ischar(value) || isstring(value))
        error('acsGenerateApproximateExpandedRoastLeadField:BadLayout', ...
            'Layout inputs must be structs or MAT reports.');
    end
    data = load(char(value));
    layout = firstStruct(data);
end

function S = firstStruct(data)
    if isfield(data, 'out') && isstruct(data.out)
        S = data.out;
        return;
    end
    if isfield(data, 'outToSave') && isstruct(data.outToSave)
        S = data.outToSave;
        return;
    end
    fields = fieldnames(data);
    for i = 1:numel(fields)
        if isstruct(data.(fields{i}))
            S = data.(fields{i});
            return;
        end
    end
    error('acsGenerateApproximateExpandedRoastLeadField:NoStructInMat', ...
        'MAT file did not contain a struct result.');
end

function tag = resolveLeadFieldTag(value)
    if ischar(value) || isstring(value)
        tag = char(value);
    elseif isstruct(value) && isfield(value, 'simulationTag') && ...
            ~isempty(value.simulationTag)
        tag = char(value.simulationTag);
    elseif isstruct(value) && isfield(value, 'leadFieldTag') && ...
            ~isempty(value.leadFieldTag)
        tag = char(value.leadFieldTag);
    else
        error('acsGenerateApproximateExpandedRoastLeadField:BadLeadField', ...
            'baseLeadField must be a tag or struct with simulationTag.');
    end
end

function t1File = resolveT1(layout)
    if isfield(layout, 't1File') && ~isempty(layout.t1File)
        t1File = char(layout.t1File);
    elseif isfield(layout, 'roastReady') && isfield(layout.roastReady, 't1File')
        t1File = char(layout.roastReady.t1File);
    else
        error('acsGenerateApproximateExpandedRoastLeadField:MissingT1', ...
            'Layout does not contain t1File.');
    end
    if exist(t1File, 'file') ~= 2
        error('acsGenerateApproximateExpandedRoastLeadField:MissingT1File', ...
            'T1 file not found: %s', t1File);
    end
end

function validateBaseLeadField(leadField)
    if ~isfield(leadField, 'mode') || ~strcmpi(leadField.mode, 'custom') || ...
            ~isfield(leadField, 'includePassiveElectrodes') || ...
            ~leadField.includePassiveElectrodes
        error('acsGenerateApproximateExpandedRoastLeadField:UnsupportedLeadField', ...
            'Base lead field must be a custom capMaker lead field with passive contacts included.');
    end
    if ~isfield(leadField, 'electrodeNames') || ...
            ~isfield(leadField, 'stimulusElectrodeNames') || ...
            ~isfield(leadField, 'referenceElectrode')
        error('acsGenerateApproximateExpandedRoastLeadField:IncompleteLeadField', ...
            'Base lead field metadata is missing electrodeNames, stimulusElectrodeNames, or referenceElectrode.');
    end
end

function validateExpandedNames(baseNames, expandedNames, referenceElectrode)
    missingBase = setdiff(lower(string(baseNames)), lower(string(expandedNames)));
    if ~isempty(missingBase)
        error('acsGenerateApproximateExpandedRoastLeadField:MissingBaseElectrodes', ...
            'Expanded layout is missing base electrode(s): %s', ...
            strjoin(cellstr(missingBase), ', '));
    end
    if ~any(strcmpi(referenceElectrode, expandedNames))
        error('acsGenerateApproximateExpandedRoastLeadField:MissingReference', ...
            'Reference electrode "%s" is not in the expanded layout.', ...
            referenceElectrode);
    end
    if numel(unique(lower(string(expandedNames)))) ~= numel(expandedNames)
        error('acsGenerateApproximateExpandedRoastLeadField:DuplicateNames', ...
            'Expanded electrode names must be unique.');
    end
end

function names = normalizeNames(names)
    if isempty(names)
        names = {};
    elseif ischar(names)
        names = {names};
    elseif isstring(names)
        names = cellstr(names(:));
    elseif iscell(names)
        names = cellfun(@char, names(:), 'UniformOutput', false);
    else
        error('acsGenerateApproximateExpandedRoastLeadField:BadNames', ...
            'Electrode names must be char, string, or a cell array.');
    end
    names = names(:);
end

function coords = coordsByName(layout, names)
    if ~isfield(layout, 'names') || ~isfield(layout, 'layoutCoordinatesMm')
        error('acsGenerateApproximateExpandedRoastLeadField:MissingLayoutCoords', ...
            'Layout must contain names and layoutCoordinatesMm.');
    end
    layoutNames = normalizeNames(layout.names);
    layoutCoords = double(layout.layoutCoordinatesMm);
    coords = nan(numel(names), 3);
    for i = 1:numel(names)
        idx = find(strcmpi(names{i}, layoutNames), 1);
        if isempty(idx)
            error('acsGenerateApproximateExpandedRoastLeadField:MissingCoordinate', ...
                'Layout is missing coordinates for electrode "%s".', names{i});
        end
        coords(i, :) = layoutCoords(idx, :);
    end
end

function Aout = expandLeadFieldMatrix(Ain, baseStimulusNames, ...
        expandedStimulusNames, surrogate, queryNewRows)
    nNode = size(Ain, 1);
    nDim = size(Ain, 2);
    if nDim ~= 3
        error('acsGenerateApproximateExpandedRoastLeadField:BadAAllShape', ...
            'A_all must be nNode x 3 x nBasis.');
    end
    if size(Ain, 3) ~= numel(baseStimulusNames)
        error('acsGenerateApproximateExpandedRoastLeadField:BadAAllBasisCount', ...
            'A_all has %d columns, but metadata lists %d stimulus electrodes.', ...
            size(Ain, 3), numel(baseStimulusNames));
    end
    Aout = zeros(nNode, 3, numel(expandedStimulusNames), 'like', Ain);
    for i = 1:numel(expandedStimulusNames)
        baseIdx = find(strcmpi(expandedStimulusNames{i}, baseStimulusNames), 1);
        if ~isempty(baseIdx)
            Aout(:, :, i) = Ain(:, :, baseIdx);
        end
    end
    for i = 1:numel(queryNewRows)
        row = queryNewRows(i);
        weights = double(surrogate.weights(i, :));
        predicted = zeros(nNode, 3, 'like', Ain);
        for j = 1:numel(weights)
            if weights(j) ~= 0
                predicted = predicted + weights(j) .* Ain(:, :, j);
            end
        end
        Aout(:, :, row) = predicted;
    end
end

function snapshot = snapshotCustomLocations(layout, snapshot, names, force)
    if ~isfield(layout, 'customLocationsFile') || ...
            exist(layout.customLocationsFile, 'file') ~= 2
        error('acsGenerateApproximateExpandedRoastLeadField:MissingCustomLocations', ...
            'Expanded layout does not report a readable customLocationsFile.');
    end
    source = char(layout.customLocationsFile);
    validateLocationNames(source, names);
    if exist(snapshot, 'file') == 2 && ~force
        validateLocationNames(snapshot, names);
        if ~strcmp(fileread(source), fileread(snapshot))
            error('acsGenerateApproximateExpandedRoastLeadField:SnapshotConflict', ...
                'Output customLocations snapshot exists but differs: %s', snapshot);
        end
        return;
    end
    [ok, msg] = copyfile(source, snapshot, 'f');
    if ~ok
        error('acsGenerateApproximateExpandedRoastLeadField:CannotCopyCustomLocations', ...
            'Could not copy customLocations snapshot: %s', msg);
    end
end

function validateLocationNames(fileName, names)
    fid = fopen(fileName, 'r');
    if fid == -1
        error('acsGenerateApproximateExpandedRoastLeadField:CannotReadCustomLocations', ...
            'Could not read customLocations file: %s', fileName);
    end
    cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
    C = textscan(fid, '%s %f %f %f');
    fileNames = C{1};
    missing = setdiff(lower(string(names)), lower(string(fileNames)));
    if ~isempty(missing)
        error('acsGenerateApproximateExpandedRoastLeadField:MissingLocationName', ...
            'customLocations file is missing electrode(s): %s', ...
            strjoin(cellstr(missing), ', '));
    end
end

function copyMeshFile(source, dest, force)
    if exist(dest, 'file') == 2 && ~force
        return;
    end
    [ok, msg] = copyfile(source, dest, 'f');
    if ~ok
        error('acsGenerateApproximateExpandedRoastLeadField:CannotCopyMesh', ...
            'Could not copy base mesh MAT: %s', msg);
    end
end

function info = makeApproximationMetadata(t1File, baseTag, opts, baseFiles, ...
        outFiles, baseNames, baseStimulusNames, expandedNames, ...
        expandedStimulusNames, baseCoords, expandedCoords, surrogate, ...
        queryNewRows, snapshot)
    info = struct();
    info.createdOn = char(datetime('now'));
    info.approximate = true;
    info.warning = ['Surrogate-expanded lead field: use for candidate ', ...
        'growth only; run a final real ROAST lead field before interpretation.'];
    info.t1File = t1File;
    info.simulationTag = opts.simulationTag;
    info.sourceLeadFieldTag = baseTag;
    info.sourceLeadFieldFiles = baseFiles;
    info.files = outFiles;
    info.referenceElectrode = opts.referenceElectrode;
    info.baseElectrodeNames = baseNames(:);
    info.baseStimulusElectrodeNames = baseStimulusNames(:);
    info.expandedElectrodeNames = expandedNames(:);
    info.expandedStimulusElectrodeNames = expandedStimulusNames(:);
    info.copiedStimulusNames = expandedStimulusNames(setdiff( ...
        (1:numel(expandedStimulusNames))', queryNewRows));
    info.predictedStimulusNames = expandedStimulusNames(queryNewRows);
    info.baseStimulusCoordinatesMm = baseCoords;
    info.expandedStimulusCoordinatesMm = expandedCoords;
    info.customLocationsSnapshot = snapshot;
    info.kernelSigmaMm = [];
    info.kernelWeightTotal = [];
    info.kernelLeaveOneOut = [];
    if ~isempty(surrogate)
        info.kernelSigmaMm = surrogate.sigmaMm;
        info.kernelWeightTotal = surrogate.weightTotal;
        if isfield(surrogate, 'leaveOneOut')
            info.kernelLeaveOneOut = surrogate.leaveOneOut;
        end
    end
end

function opt = makeExpandedOptions(baseOpt, opts, expandedNames, ...
        expandedStimulusNames, snapshot, approximation)
    opt = baseOpt;
    opt.uniqueTag = opts.simulationTag;
    opt.approximateLeadField = true;
    opt.surrogateExpandedLeadField = true;
    opt.approximateLeadFieldWarning = approximation.warning;
    opt.leadField.mode = 'custom';
    opt.leadField.electrodeNames = expandedNames(:);
    opt.leadField.stimulusElectrodeNames = expandedStimulusNames(:);
    opt.leadField.referenceElectrode = opts.referenceElectrode;
    opt.leadField.includePassiveElectrodes = true;
    opt.leadField.approximate = true;
    opt.leadField.surrogateExpanded = true;
    opt.leadField.sourceLeadFieldTag = approximation.sourceLeadFieldTag;
    opt.leadField.customLocationsFile = snapshot;
    opt.leadField.approximation = approximation;
    if isfield(opt.leadField, 'customLocationFingerprint')
        opt.leadField = rmfield(opt.leadField, 'customLocationFingerprint');
    end
end

function out = buildReport(t1File, opts, files, approximation)
    out = struct();
    out.createdOn = char(datetime('now'));
    out.approximate = true;
    out.surrogateExpanded = true;
    out.warning = approximation.warning;
    out.t1File = t1File;
    out.simulationTag = opts.simulationTag;
    out.sourceLeadFieldTag = approximation.sourceLeadFieldTag;
    out.electrodeNames = approximation.expandedElectrodeNames;
    out.stimulusElectrodeNames = approximation.expandedStimulusElectrodeNames;
    out.referenceElectrode = opts.referenceElectrode;
    out.predictedStimulusNames = approximation.predictedStimulusNames;
    out.copiedStimulusNames = approximation.copiedStimulusNames;
    out.kernelSigmaMm = approximation.kernelSigmaMm;
    out.kernelLeaveOneOut = approximation.kernelLeaveOneOut;
    out.candidateLocationsSnapshot = approximation.customLocationsSnapshot;
    out.leadFieldResultMat = files.roastResultMat;
    out.roastOptionsMat = files.roastOptionsMat;
    out.meshMat = files.meshMat;
    out.reportMat = files.requestMat;
    out.validationRecipe = {};
end

function files = leadFieldFiles(folder, stem, simulationTag)
    prefix = fullfile(folder, [stem '_' simulationTag]);
    files = struct();
    files.roastResultMat = [prefix '_roastResult.mat'];
    files.roastOptionsMat = [prefix '_roastOptions.mat'];
    files.meshMat = [prefix '.mat'];
    files.customLocations = [prefix '_customLocations'];
    files.requestMat = [prefix '_acsApproxLeadFieldRequest.mat'];
end

function requireFiles(files, fields)
    for i = 1:numel(fields)
        fileName = files.(fields{i});
        if exist(fileName, 'file') ~= 2
            error('acsGenerateApproximateExpandedRoastLeadField:MissingFile', ...
                'Required file not found: %s', fileName);
        end
    end
end

function requireNoOverwrite(files, force)
    if force
        return;
    end
    fields = {'roastResultMat', 'roastOptionsMat', 'meshMat', 'requestMat'};
    for i = 1:numel(fields)
        if exist(files.(fields{i}), 'file') == 2
            error('acsGenerateApproximateExpandedRoastLeadField:OutputExists', ...
                'Output exists. Use force=true to overwrite: %s', ...
                files.(fields{i}));
        end
    end
end

function tag = safeTag(tag)
    tag = regexprep(strtrim(char(tag)), '[^A-Za-z0-9_-]+', '_');
    tag = regexprep(tag, '_+', '_');
    tag = regexprep(tag, '^_+|_+$', '');
    if isempty(tag)
        error('acsGenerateApproximateExpandedRoastLeadField:BadTag', ...
            'simulationTag must contain at least one filename-safe character.');
    end
end

function tf = samePath(a, b)
    a = char(a);
    b = char(b);
    try
        a = char(java.io.File(a).getCanonicalPath());
        b = char(java.io.File(b).getCanonicalPath());
    catch
    end
    tf = strcmpi(a, b);
end

function printSummary(out)
    fprintf('\nApproximate expanded ROAST lead field\n');
    fprintf('  tag: %s\n', out.simulationTag);
    fprintf('  source tag: %s\n', out.sourceLeadFieldTag);
    fprintf('  electrodes: %d total, %d stimulus bases\n', ...
        numel(out.electrodeNames), numel(out.stimulusElectrodeNames));
    fprintf('  copied bases: %d\n', numel(out.copiedStimulusNames));
    fprintf('  predicted bases: %d\n', numel(out.predictedStimulusNames));
    if ~isempty(out.kernelSigmaMm)
        fprintf('  kernel sigma: %.6g mm\n', out.kernelSigmaMm);
    end
    fprintf('  result: %s\n', out.leadFieldResultMat);
    fprintf('  warning: %s\n\n', out.warning);
end
