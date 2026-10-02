function out = acsBuildTesToEegTransferMatrix(layoutIn, varargin)
% ACSBUILDTESTOEEGTRANSFERMATRIX Build a cached linear tES-to-EEG map.
%
% out = acsBuildTesToEegTransferMatrix(combinedLayout) runs one direct
% ROAST/GetDP solve per independent tES current pattern. The resulting
% matrix maps balanced tES currents in mA to referenced EEG voltages in V:
%
%     eegVoltageV = out.transferMatrixVPerMa * tesCurrentsMa
%
% The finalized tES and EEG electrode geometry is held fixed. A single tES
% electrode is used as the electrical reference, so nTes-1 solves are
% sufficient. The small transfer matrix is cached for subsequent searches.
%
% Name-value options:
%   tesNames          : tES names [layout.tesNames or siteRoles]
%   eegNames          : EEG names [layout.eegNames or siteRoles]
%   referenceTesName  : tES basis reference [last tES name]
%   simulationTag     : reusable direct-solve tag ['tesEegTransferBasis']
%   outputFile        : cached MAT report [beside T1]
%   force             : rebuild even if a compatible cache exists [false]
%   forceModel        : rebuild tag-specific ROAST model on first solve [false]
%   electrodeModel, resampling, roastOptions, sampleDomain, referenceMode:
%                       forwarded to acsPredictEegVoltagesFromTes
%   verbose           : print progress [true]

% This builder is needed because historical ROAST lead-field products save
% electric-field basis vectors but not their nodal voltage basis vectors.

% See also acsOptimizeOrthogonalTesEegTopography,
%          acsPredictEegVoltagesFromTes.

    opts = parseInputs(varargin{:});
    layout = readStruct(layoutIn);
    requireFields(layout, {'t1File', 'names', 'customLocationsFile'});
    allNames = normalizeNames(layout.names);
    tesNames = resolveRoleNames(layout, opts.tesNames, allNames, 'tes');
    eegNames = resolveRoleNames(layout, opts.eegNames, allNames, 'eeg');
    assertDisjoint(tesNames, eegNames);

    if isempty(opts.referenceTesName)
        referenceTesName = tesNames{end};
    else
        referenceTesName = char(opts.referenceTesName);
        assertKnownNames({referenceTesName}, tesNames, 'referenceTesName');
    end
    referenceIndex = find(strcmpi(referenceTesName, tesNames), 1);
    basisIndices = setdiff((1:numel(tesNames))', referenceIndex, 'stable');

    [t1Folder, t1Stem] = fileparts(char(layout.t1File));
    if isempty(opts.outputFile)
        outputFile = fullfile(t1Folder, ...
            [t1Stem '_' opts.simulationTag '_transferMatrix.mat']);
    else
        outputFile = char(opts.outputFile);
    end
    checkpointFile = checkpointName(outputFile);
    request = makeRequest(layout, tesNames, eegNames, referenceTesName, opts);
    if ~opts.force && exist(outputFile, 'file') == 2
        cached = loadReport(outputFile);
        if isfield(cached, 'request') && isequaln(cached.request, request)
            out = cached;
            if opts.verbose
                fprintf('\nReusing cached tES-to-EEG transfer matrix:\n  %s\n', outputFile);
            end
            return;
        end
    end

    nEeg = numel(eegNames);
    nTes = numel(tesNames);
    [rawBasis, referencedBasis, basisReports, completed] = ...
        initializeProgress(checkpointFile, request, nEeg, numel(basisIndices), opts.force);
    for b = 1:numel(basisIndices)
        if completed(b)
            if opts.verbose
                fprintf('\ntES-to-EEG basis %d/%d already cached; skipping.\n', ...
                    b, numel(basisIndices));
            end
            continue;
        end
        tesIndex = basisIndices(b);
        recipe = {tesNames{tesIndex}, opts.basisCurrentMa, ...
            referenceTesName, -opts.basisCurrentMa};
        if opts.verbose
            fprintf('\ntES-to-EEG basis %d/%d: %s -> %s (%.4g mA)\n', ...
                b, numel(basisIndices), tesNames{tesIndex}, ...
                referenceTesName, opts.basisCurrentMa);
        end
        prediction = acsPredictEegVoltagesFromTes(layout, recipe, ...
            'eegNames', eegNames, ...
            'simulationTag', opts.simulationTag, ...
            'electrodeModel', opts.electrodeModel, ...
            'resampling', opts.resampling, ...
            'roastOptions', opts.roastOptions, ...
            'sampleDomain', opts.sampleDomain, ...
            'referenceMode', opts.referenceMode, ...
            'forceModel', opts.forceModel && b == 1, ...
            'forceDirectSolve', true, ...
            'execute', true, ...
            'showFigures', false, ...
            'saveFigures', false, ...
            'showTopography', false, ...
            'saveTopography', false, ...
            'saveReport', false, ...
            'verbose', opts.verbose);
        rawBasis(:, b) = prediction.eegVoltageRawV / opts.basisCurrentMa;
        referencedBasis(:, b) = ...
            prediction.eegVoltageReferencedV / opts.basisCurrentMa;
        basisReports{b} = compactPredictionRecord(prediction);
        completed(b) = true;
        saveProgress(checkpointFile, request, rawBasis, referencedBasis, ...
            basisReports, completed);
    end

    transfer = zeros(nEeg, nTes);
    rawTransfer = zeros(nEeg, nTes);
    transfer(:, basisIndices) = referencedBasis;
    rawTransfer(:, basisIndices) = rawBasis;

    out = struct();
    out.createdOn = char(datetime('now'));
    out.kind = 'nhpulse.tesToEegTransferMatrix';
    out.layoutSource = sourceLabel(layoutIn);
    out.t1File = char(layout.t1File);
    out.tesNames = tesNames(:);
    out.eegNames = eegNames(:);
    out.referenceTesName = referenceTesName;
    out.referenceTesIndex = referenceIndex;
    out.basisTesNames = tesNames(basisIndices);
    out.basisCurrentMa = opts.basisCurrentMa;
    out.transferMatrixVPerMa = transfer;
    out.rawTransferMatrixVPerMa = rawTransfer;
    out.referenceMode = opts.referenceMode;
    out.sampleDomain = opts.sampleDomain;
    out.simulationTag = opts.simulationTag;
    out.basisReports = basisReports;
    out.request = request;
    out.reportMat = outputFile;
    ensureParent(outputFile);
    outToSave = out; %#ok<NASGU>
    save(outputFile, 'outToSave', '-v7.3');
    if exist(checkpointFile, 'file') == 2
        delete(checkpointFile);
    end
    if opts.verbose
        fprintf('\ntES-to-EEG transfer matrix\n');
        fprintf('  size: %d EEG x %d tES\n', nEeg, nTes);
        fprintf('  tES reference: %s\n', referenceTesName);
        fprintf('  output: %s\n\n', outputFile);
    end
end

function opts = parseInputs(varargin)
    p = inputParser;
    p.FunctionName = 'acsBuildTesToEegTransferMatrix';
    addParameter(p, 'tesNames', {}, @isNameLike);
    addParameter(p, 'eegNames', {}, @isNameLike);
    addParameter(p, 'referenceTesName', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'basisCurrentMa', 1, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x > 0);
    addParameter(p, 'simulationTag', 'tesEegTransferBasis', @(x) ischar(x) || isstring(x));
    addParameter(p, 'outputFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'force', false, @isBoolLike);
    addParameter(p, 'forceModel', false, @isBoolLike);
    addParameter(p, 'electrodeModel', 'biosemiPin', @(x) ischar(x) || isstring(x));
    addParameter(p, 'resampling', 'off', @(x) ischar(x) || isstring(x));
    addParameter(p, 'roastOptions', {}, @iscell);
    addParameter(p, 'sampleDomain', 'electrode', @(x) ischar(x) || isstring(x));
    addParameter(p, 'referenceMode', 'meanEeg', @(x) isnumeric(x) || ischar(x) || isstring(x));
    addParameter(p, 'verbose', true, @isBoolLike);
    parse(p, varargin{:});
    opts = p.Results;
    opts.tesNames = normalizeNames(opts.tesNames);
    opts.eegNames = normalizeNames(opts.eegNames);
    opts.referenceTesName = char(opts.referenceTesName);
    opts.simulationTag = safeTag(opts.simulationTag);
    opts.outputFile = char(opts.outputFile);
    opts.force = logical(opts.force);
    opts.forceModel = logical(opts.forceModel);
    opts.verbose = logical(opts.verbose);
    opts.basisCurrentMa = double(opts.basisCurrentMa);
end

function tf = isNameLike(x)
    tf = isempty(x) || ischar(x) || isstring(x) || iscell(x);
end

function tf = isBoolLike(x)
    tf = (islogical(x) || isnumeric(x)) && isscalar(x);
end

function value = readStruct(value)
    if isstruct(value), return; end
    data = load(char(value));
    fields = fieldnames(data);
    for i = 1:numel(fields)
        if isstruct(data.(fields{i}))
            value = data.(fields{i});
            return;
        end
    end
    error('acsBuildTesToEegTransferMatrix:NoStruct', ...
        'MAT file did not contain a struct.');
end

function requireFields(S, names)
    for i = 1:numel(names)
        if ~isfield(S, names{i}) || isempty(S.(names{i}))
            error('acsBuildTesToEegTransferMatrix:MissingField', ...
                'Layout is missing required field "%s".', names{i});
        end
    end
end

function names = resolveRoleNames(layout, supplied, allNames, role)
    if ~isempty(supplied)
        names = supplied;
    else
        fieldName = [role 'Names'];
        if isfield(layout, fieldName) && ~isempty(layout.(fieldName))
            names = normalizeNames(layout.(fieldName));
        elseif isfield(layout, 'siteRoles') && ~isempty(layout.siteRoles)
            roles = normalizeNames(layout.siteRoles);
            names = allNames(strcmpi(roles, role));
        else
            names = allNames(startsWith(lower(string(allNames)), ['custom' role]));
        end
    end
    if isempty(names)
        error('acsBuildTesToEegTransferMatrix:MissingRoleNames', ...
            'Could not infer %s electrode names.', upper(role));
    end
    assertKnownNames(names, allNames, [role 'Names']);
end

function assertKnownNames(names, available, label)
    if ~all(ismember(lower(string(names)), lower(string(available))))
        error('acsBuildTesToEegTransferMatrix:UnknownName', ...
            '%s contains names not present in the fixed layout.', label);
    end
end

function assertDisjoint(a, b)
    if any(ismember(lower(string(a)), lower(string(b))))
        error('acsBuildTesToEegTransferMatrix:OverlappingRoles', ...
            'tES and EEG electrode-name sets must be disjoint.');
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
        error('acsBuildTesToEegTransferMatrix:BadNames', 'Invalid name list.');
    end
    names = names(:);
end

function request = makeRequest(layout, tesNames, eegNames, referenceTesName, opts)
    request = struct();
    request.t1File = char(layout.t1File);
    request.customLocationsFile = char(layout.customLocationsFile);
    request.customLocationsFingerprint = fileFingerprint(layout.customLocationsFile);
    request.tesNames = tesNames(:);
    request.eegNames = eegNames(:);
    request.referenceTesName = referenceTesName;
    request.basisCurrentMa = opts.basisCurrentMa;
    request.electrodeModel = char(opts.electrodeModel);
    request.resampling = char(opts.resampling);
    request.roastOptions = opts.roastOptions;
    request.sampleDomain = char(opts.sampleDomain);
    request.referenceMode = opts.referenceMode;
end

function fp = fileFingerprint(fileName)
    fp = struct('file', char(fileName), 'bytes', NaN, 'datenum', NaN);
    if exist(fileName, 'file') == 2
        info = dir(fileName);
        fp.bytes = info.bytes;
        fp.datenum = info.datenum;
    end
end

function record = compactPredictionRecord(prediction)
    record = struct('simulationTag', prediction.simulationTag, ...
        'fullRecipe', {prediction.fullRecipe}, ...
        'voltagePosFile', prediction.voltagePosFile, ...
        'meshFile', prediction.meshFile, ...
        'sampleQc', prediction.sampleQc);
end

function [rawBasis, referencedBasis, basisReports, completed] = ...
        initializeProgress(fileName, request, nEeg, nBasis, force)
    rawBasis = nan(nEeg, nBasis);
    referencedBasis = nan(nEeg, nBasis);
    basisReports = cell(nBasis, 1);
    completed = false(nBasis, 1);
    if force && exist(fileName, 'file') == 2
        delete(fileName);
    end
    if exist(fileName, 'file') ~= 2
        return;
    end
    data = load(fileName, 'progress');
    if ~isfield(data, 'progress') || ...
            ~isfield(data.progress, 'request') || ...
            ~isequaln(data.progress.request, request)
        return;
    end
    progress = data.progress;
    if isequal(size(progress.rawBasis), [nEeg nBasis]) && ...
            isequal(size(progress.referencedBasis), [nEeg nBasis]) && ...
            numel(progress.basisReports) == nBasis && ...
            numel(progress.completed) == nBasis
        rawBasis = progress.rawBasis;
        referencedBasis = progress.referencedBasis;
        basisReports = progress.basisReports;
        completed = logical(progress.completed(:));
    end
end

function saveProgress(fileName, request, rawBasis, referencedBasis, ...
        basisReports, completed)
    progress = struct('request', request, 'rawBasis', rawBasis, ...
        'referencedBasis', referencedBasis, 'basisReports', {basisReports}, ...
        'completed', completed, 'updatedOn', char(datetime('now'))); %#ok<NASGU>
    ensureParent(fileName);
    save(fileName, 'progress', '-v7.3');
end

function fileName = checkpointName(outputFile)
    [folder, stem] = fileparts(outputFile);
    fileName = fullfile(folder, [stem '_partial.mat']);
end

function value = loadReport(fileName)
    data = load(fileName);
    fields = fieldnames(data);
    value = data.(fields{1});
end

function label = sourceLabel(value)
    if ischar(value) || isstring(value), label = char(value); else, label = '<struct>'; end
end

function tag = safeTag(tag)
    tag = regexprep(char(tag), '[^A-Za-z0-9_]', '_');
    if isempty(tag), tag = 'tesEegTransferBasis'; end
    if ~isletter(tag(1)), tag = ['transfer_' tag]; end
end

function ensureParent(fileName)
    folder = fileparts(fileName);
    if ~isempty(folder) && exist(folder, 'dir') ~= 7, mkdir(folder); end
end
