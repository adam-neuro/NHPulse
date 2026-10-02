function out = acsPrepareTesEegContrastProtocol(sourceIn, varargin)
% ACSPREPARETESEEGCONTRASTPROTOCOL Prepare two tES conditions from disk.
%
% out = acsPrepareTesEegContrastProtocol(capDesignTag) resolves the newest
% compatible finalized layout and target-optimized tES recipe under the
% configured output roots. It then builds/reuses the fixed-layout tES-to-EEG
% transfer matrix and finds a second stimulus with a predicted EEG artifact
% orthogonal to the target-optimized stimulus.
%
% The primary experiment-facing product is out.protocolFile. It contains a
% compact struct with a fixed channel order and signed currents in mA for:
%   1. targetOptimized
%   2. eegOrthogonalControl
%
% A matching CSV is written for human inspection. NHPulse does not assign
% Soterix hardware port numbers; that experiment-specific mapping should be
% joined to StoredName in the experimental-control system.
%
% With no source input, the existing NHPulse file picker is shown.
%
% Name-value options:
%   searchRoot       : root searched for tag-matching products ['']
%   outputFolder     : protocol output folder [beside resolved layout]
%   protocolTag      : output stem [source tag or resolved layout tag]
%   forceTransfer    : rebuild cached tES-to-EEG matrix [false]
%   forceModel       : rebuild direct-solve ROAST model [false]
%   transferOptions  : additional transfer-builder options [{}]
%   optimizerOptions : additional orthogonal-search options [{}]
%   showFigures      : show optimization comparison [true]
%   saveFigures      : save optimization comparison [true]
%   saveCsv          : save signed-current table [true]
%   verbose          : print paths and current tables [true]
%
% Example from a clean workspace:
%   protocol = acsPrepareTesEegContrastProtocol( ...
%       'M2107_tes8_eeg8_rhdlpfc1_phoneWarp');
%
% See also acsShowTesStimulationParameters,
%          acsOptimizeOrthogonalTesEegTopography.

    parameterNames = inputParameterNames();
    if nargin < 1
        sourceIn = [];
    elseif isNameValueKey(sourceIn, parameterNames)
        varargin = [{sourceIn}, varargin];
        sourceIn = [];
    end
    opts = parseInputs(varargin{:});
    addLocalDependencies();

    reviewArgs = {'searchRoot', opts.searchRoot, ...
        'showParameterFigure', false, ...
        'showField', 'never', ...
        'showEegTopography', 'never', ...
        'saveFigures', false, ...
        'saveTable', false, ...
        'verbose', false};
    if isempty(sourceIn)
        review = acsShowTesStimulationParameters(reviewArgs{:});
    else
        review = acsShowTesStimulationParameters(sourceIn, reviewArgs{:});
    end
    if isempty(review.layout)
        error('acsPrepareTesEegContrastProtocol:MissingLayout', ...
            ['The selected products contain a tES recipe but no finalized ', ...
             'combined tES/EEG layout. Select a combined-layout or ', ...
             'manufacturing report, or use a more specific cap-design tag.']);
    end

    selectedLayout = review.layout;
    [layout, layoutResolution] = resolveModelingLayout( ...
        selectedLayout, opts.searchRoot);
    optimizedRecipe = layoutRecipe(layout);
    review.layout = layout;
    review.recipe = optimizedRecipe;
    review.recipeInfo.layoutReportMat = getField(layout, 'reportMat', '');
    outputFolder = resolveOutputFolder(selectedLayout, review, opts.outputFolder);
    protocolTag = resolveProtocolTag(sourceIn, layout, opts.protocolTag);
    transferFile = fullfile(outputFolder, [protocolTag '_tesEegTransfer.mat']);
    optimizationFile = fullfile(outputFolder, ...
        [protocolTag '_orthogonalTesEegControl.mat']);
    transferSimulationTag = ['eegXfer_' shortHash(transferIdentity(layout))];

    transferArgs = mergeNameValuePairs({ ...
        'simulationTag', transferSimulationTag, ...
        'outputFile', transferFile, ...
        'force', opts.forceTransfer, ...
        'forceModel', opts.forceModel, ...
        'electrodeModel', 'biosemiPin', ...
        'resampling', 'off', ...
        'sampleDomain', 'electrode', ...
        'referenceMode', 'meanEeg', ...
        'verbose', opts.verbose}, opts.transferOptions);
    optimizerArgs = mergeNameValuePairs({ ...
        'transferOptions', transferArgs, ...
        'outputFile', optimizationFile, ...
        'showFigures', opts.showFigures, ...
        'saveFigures', opts.saveFigures, ...
        'showTopography', false, ...
        'saveTopography', false, ...
        'verbose', opts.verbose}, opts.optimizerOptions);
    optimizedControl = acsOptimizeOrthogonalTesEegTopography( ...
        layout, optimizedRecipe, optimizerArgs{:});

    channelTable = makeChannelTable(optimizedControl);
    protocol = makeProtocol(layout, review, optimizedControl, ...
        protocolTag, channelTable);
    protocolFile = fullfile(outputFolder, [protocolTag '_tesContrastProtocol.mat']);
    csvFile = fullfile(outputFolder, [protocolTag '_tesContrastCurrents.csv']);
    ensureDir(outputFolder);
    save(protocolFile, 'protocol', '-v7.3');
    if opts.saveCsv
        writetable(channelTable, csvFile);
    else
        csvFile = '';
    end

    out = struct();
    out.createdOn = char(datetime('now'));
    out.protocol = protocol;
    out.channelTable = channelTable;
    out.targetOptimizedRecipe = protocol.conditions(1).recipe;
    out.eegOrthogonalControlRecipe = protocol.conditions(2).recipe;
    out.optimization = optimizedControl;
    out.review = review;
    out.layoutResolution = layoutResolution;
    out.protocolFile = protocolFile;
    out.csvFile = csvFile;
    out.transferMatrixFile = transferFile;
    out.optimizationFile = optimizationFile;
    if opts.verbose
        printSummary(out);
    end
end

function opts = parseInputs(varargin)
    p = inputParser;
    p.FunctionName = 'acsPrepareTesEegContrastProtocol';
    addParameter(p, 'searchRoot', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'outputFolder', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'protocolTag', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'forceTransfer', false, @isBoolLike);
    addParameter(p, 'forceModel', false, @isBoolLike);
    addParameter(p, 'transferOptions', {}, @iscell);
    addParameter(p, 'optimizerOptions', {}, @iscell);
    addParameter(p, 'showFigures', true, @isBoolLike);
    addParameter(p, 'saveFigures', true, @isBoolLike);
    addParameter(p, 'saveCsv', true, @isBoolLike);
    addParameter(p, 'verbose', true, @isBoolLike);
    parse(p, varargin{:});
    opts = p.Results;
    opts.searchRoot = expandUserPath(char(opts.searchRoot));
    opts.outputFolder = expandUserPath(char(opts.outputFolder));
    opts.protocolTag = char(opts.protocolTag);
    opts.forceTransfer = logical(opts.forceTransfer);
    opts.forceModel = logical(opts.forceModel);
    opts.showFigures = logical(opts.showFigures);
    opts.saveFigures = logical(opts.saveFigures);
    opts.saveCsv = logical(opts.saveCsv);
    opts.verbose = logical(opts.verbose);
    validateNameValuePairs(opts.transferOptions, 'transferOptions');
    validateNameValuePairs(opts.optimizerOptions, 'optimizerOptions');
end

function names = inputParameterNames()
    names = {'searchRoot', 'outputFolder', 'protocolTag', 'forceTransfer', ...
        'forceModel', 'transferOptions', 'optimizerOptions', 'showFigures', ...
        'saveFigures', 'saveCsv', 'verbose'};
end

function tf = isNameValueKey(value, names)
    tf = (ischar(value) || isstring(value)) && any(strcmpi(char(value), names));
end

function tf = isBoolLike(x)
    tf = (islogical(x) || isnumeric(x)) && isscalar(x);
end

function validateNameValuePairs(value, label)
    if mod(numel(value), 2) ~= 0
        error('acsPrepareTesEegContrastProtocol:BadOptions', ...
            '%s must contain name-value pairs.', label);
    end
end

function addLocalDependencies()
    utilityRoot = fileparts(mfilename('fullpath'));
    repoRoot = fileparts(utilityRoot);
    if exist('setNHPulsePath', 'file') == 2
        try
            setNHPulsePath('repoRoot', repoRoot, 'verbose', false);
            return;
        catch
        end
    end
    addpath(utilityRoot);
end

function folder = resolveOutputFolder(layout, review, requested)
    if ~isempty(requested)
        folder = requested;
        ensureDir(folder);
        return;
    end
    candidates = {};
    if isfield(layout, 'reportMat') && ~isempty(layout.reportMat)
        candidates{end+1} = fileparts(char(layout.reportMat)); %#ok<AGROW>
    end
    if isfield(review.recipeInfo, 'layoutReportMat') && ...
            ~isempty(review.recipeInfo.layoutReportMat)
        candidates{end+1} = fileparts(char(review.recipeInfo.layoutReportMat)); %#ok<AGROW>
    end
    if isfield(layout, 't1File') && ~isempty(layout.t1File)
        candidates{end+1} = fileparts(char(layout.t1File)); %#ok<AGROW>
    end
    candidates{end+1} = pwd;
    folder = candidates{find(~cellfun(@isempty, candidates), 1)};
    ensureDir(folder);
end

function [layout, info] = resolveModelingLayout(selectedLayout, searchRoot)
    required = {'t1File', 'customLocationsFile', 'names', ...
        'layoutCoordinatesMm', 'tesNames', 'eegNames', 'tesCurrentsMa'};
    if hasFields(selectedLayout, required)
        layout = selectedLayout;
        info = struct('mode', 'selectedProduct', ...
            'selectedReport', getField(selectedLayout, 'reportMat', ''), ...
            'resolvedReport', getField(selectedLayout, 'reportMat', ''), ...
            'maximumCoordinateDifferenceMm', 0);
        return;
    end

    [selectedNames, selectedCoordinates] = layoutIdentity(selectedLayout);
    if isempty(selectedNames) || isempty(selectedCoordinates)
        error('acsPrepareTesEegContrastProtocol:IncompleteLayout', ...
            ['The selected manufacturing product lacks ROAST source fields ', ...
             'and does not contain enough electrode geometry to locate its ', ...
             'upstream combined layout.']);
    end
    roots = modelingLayoutSearchRoots(selectedLayout, searchRoot);
    candidates = repmat(struct('layout', [], 'file', '', 'difference', inf, ...
        'datenum', 0), 0, 1);
    patterns = {'*tesEeg*customLocations*_report.mat', ...
        '*combined*layout*_report.mat', '*tesEeg*_report.mat'};
    seen = {};
    for r = 1:numel(roots)
        for p = 1:numel(patterns)
            hits = dir(fullfile(roots{r}, '**', patterns{p}));
            hits = hits(~[hits.isdir]);
            for h = 1:numel(hits)
                fileName = fullfile(hits(h).folder, hits(h).name);
                key = lower(fileName);
                if any(strcmp(key, seen)), continue; end
                seen{end+1} = key; %#ok<AGROW>
                structs = loadStructs(fileName);
                for s = 1:numel(structs)
                    candidate = structs{s};
                    if ~hasFields(candidate, required), continue; end
                    [candidateNames, candidateCoordinates] = layoutIdentity(candidate);
                    if ~isequal(lower(string(selectedNames)), ...
                            lower(string(candidateNames))) || ...
                            ~isequal(size(selectedCoordinates), size(candidateCoordinates))
                        continue;
                    end
                    difference = max(abs(selectedCoordinates(:)-candidateCoordinates(:)));
                    if difference > 1e-5, continue; end
                    item = struct('layout', candidate, 'file', fileName, ...
                        'difference', difference, 'datenum', hits(h).datenum);
                    candidates(end+1, 1) = item; %#ok<AGROW>
                end
            end
        end
    end
    if isempty(candidates)
        error('acsPrepareTesEegContrastProtocol:NoUpstreamLayout', ...
            ['The selected manufacturing report omits t1File/customLocationsFile, ', ...
             'and no upstream combined layout with identical electrode names ', ...
             'and model coordinates was found. Provide the combined-layout ', ...
             'report directly or set searchRoot to the subject outputs folder.']);
    end
    differences = [candidates.difference];
    bestDifference = min(differences);
    eligible = find(abs(differences-bestDifference) <= 1e-12);
    [~, newest] = max([candidates(eligible).datenum]);
    chosen = candidates(eligible(newest));
    layout = chosen.layout;
    if ~isfield(layout, 'reportMat') || isempty(layout.reportMat)
        layout.reportMat = chosen.file;
    end
    info = struct('mode', 'matchedUpstreamCombinedLayout', ...
        'selectedReport', getField(selectedLayout, 'reportMat', ''), ...
        'resolvedReport', chosen.file, ...
        'maximumCoordinateDifferenceMm', chosen.difference);
end

function tf = hasFields(S, fields)
    tf = isstruct(S);
    for i = 1:numel(fields)
        tf = tf && isfield(S, fields{i}) && ~isempty(S.(fields{i}));
    end
end

function [names, coordinates] = layoutIdentity(layout)
    names = {};
    coordinates = [];
    if ~isfield(layout, 'names') || isempty(layout.names), return; end
    names = cellstr(string(layout.names(:)));
    coordinateFields = {'modelLayoutCoordinatesMm', 'layoutCoordinatesMm'};
    for i = 1:numel(coordinateFields)
        field = coordinateFields{i};
        if isfield(layout, field) && ~isempty(layout.(field))
            coordinates = double(layout.(field));
            break;
        end
    end
end

function roots = modelingLayoutSearchRoots(layout, requested)
    roots = {};
    if ~isempty(requested), roots{end+1} = requested; end %#ok<AGROW>
    if isfield(layout, 'reportMat') && ~isempty(layout.reportMat)
        reportFolder = fileparts(char(layout.reportMat));
        roots{end+1} = reportFolder; %#ok<AGROW>
        outputsRoot = ancestorNamed(reportFolder, 'outputs');
        if ~isempty(outputsRoot), roots{end+1} = outputsRoot; end %#ok<AGROW>
    end
    utilityRoot = fileparts(mfilename('fullpath'));
    roots{end+1} = fullfile(fileparts(utilityRoot), 'outputs'); %#ok<AGROW>
    roots{end+1} = fullfile(pwd, 'outputs'); %#ok<AGROW>
    keep = false(size(roots));
    keys = cell(size(roots));
    for i = 1:numel(roots)
        roots{i} = expandUserPath(char(roots{i}));
        keep(i) = exist(roots{i}, 'dir') == 7;
        keys{i} = lower(roots{i});
    end
    roots = roots(keep);
    keys = keys(keep);
    [~, uniqueRows] = unique(keys, 'stable');
    roots = roots(sort(uniqueRows));
end

function folder = ancestorNamed(folder, targetName)
    folder = char(folder);
    while ~isempty(folder)
        [parent, name] = fileparts(folder);
        if strcmpi(name, targetName), return; end
        if isempty(parent) || strcmp(parent, folder)
            folder = '';
            return;
        end
        folder = parent;
    end
end

function values = loadStructs(fileName)
    values = {};
    try
        raw = load(fileName);
    catch
        return;
    end
    names = fieldnames(raw);
    for i = 1:numel(names)
        if isstruct(raw.(names{i})) && isscalar(raw.(names{i}))
            values{end+1, 1} = raw.(names{i}); %#ok<AGROW>
        end
    end
end

function recipe = layoutRecipe(layout)
    if ~hasFields(layout, {'tesNames', 'tesCurrentsMa'})
        error('acsPrepareTesEegContrastProtocol:MissingOptimizedRecipe', ...
            'Resolved combined layout does not contain its optimized tES recipe.');
    end
    names = cellstr(string(layout.tesNames(:)));
    currents = double(layout.tesCurrentsMa(:));
    if numel(names) ~= numel(currents)
        error('acsPrepareTesEegContrastProtocol:RecipeSizeMismatch', ...
            'Resolved tES names and currents have different lengths.');
    end
    recipe = reshape([names, num2cell(currents)]', 1, []);
end

function tag = resolveProtocolTag(sourceIn, layout, requested)
    if ~isempty(requested)
        raw = requested;
    elseif ischar(sourceIn) || (isstring(sourceIn) && isscalar(sourceIn))
        raw = char(sourceIn);
        if exist(raw, 'file') == 2
            [~, raw] = fileparts(raw);
        end
    elseif isfield(layout, 'manufacturingTag') && ~isempty(layout.manufacturingTag)
        raw = layout.manufacturingTag;
    elseif isfield(layout, 'capDesignTag') && ~isempty(layout.capDesignTag)
        raw = layout.capDesignTag;
    else
        raw = 'tesEegContrast';
    end
    raw = safeFilePart(raw);
    if numel(raw) > 52
        raw = [raw(1:39) '_' shortHash(raw)];
    end
    tag = raw;
end

function identity = transferIdentity(layout)
    parts = {};
    fields = {'t1File', 'customLocationsFile', 'reportMat'};
    for i = 1:numel(fields)
        if isfield(layout, fields{i}) && ~isempty(layout.(fields{i}))
            parts{end+1} = char(layout.(fields{i})); %#ok<AGROW>
        end
    end
    if isfield(layout, 'tesNames')
        parts{end+1} = strjoin(cellstr(string(layout.tesNames(:))), '|'); %#ok<AGROW>
    end
    if isfield(layout, 'eegNames')
        parts{end+1} = strjoin(cellstr(string(layout.eegNames(:))), '|'); %#ok<AGROW>
    end
    identity = strjoin(parts, '::');
end

function merged = mergeNameValuePairs(defaults, overrides)
    validateNameValuePairs(defaults, 'defaults');
    validateNameValuePairs(overrides, 'overrides');
    merged = defaults;
    for i = 1:2:numel(overrides)
        key = char(overrides{i});
        defaultKeys = merged(1:2:end);
        idx = find(strcmpi(key, cellfun(@char, defaultKeys, ...
            'UniformOutput', false)), 1);
        if isempty(idx)
            merged(end+1:end+2) = overrides(i:i+1); %#ok<AGROW>
        else
            merged{2*idx} = overrides{i+1};
        end
    end
end

function T = makeChannelTable(result)
    optimized = result.baselineCurrentsMa(:);
    orthogonal = result.alternateCurrentsMa(:);
    names = result.tesNames(:);
    T = table((1:numel(names))', names, optimized, orthogonal, ...
        polarity(optimized), polarity(orthogonal), ...
        'VariableNames', {'ChannelOrder', 'StoredName', ...
        'TargetOptimizedCurrentMa', 'EegOrthogonalControlCurrentMa', ...
        'TargetOptimizedPolarity', 'EegOrthogonalControlPolarity'});
end

function labels = polarity(currents)
    labels = repmat({'off'}, numel(currents), 1);
    labels(currents > 1e-6) = {'anode'};
    labels(currents < -1e-6) = {'cathode'};
end

function protocol = makeProtocol(layout, review, result, tag, channelTable)
    protocol = struct();
    protocol.schema = 'nhpulse.tesContrastProtocol';
    protocol.schemaVersion = '1.0';
    protocol.createdOn = char(datetime('now'));
    protocol.protocolTag = tag;
    protocol.currentUnits = 'mA';
    protocol.currentSignConvention = ...
        'positive=anodal/source, negative=cathodal/sink';
    protocol.channelOrder = result.tesNames(:);
    protocol.channelTable = channelTable;
    protocol.hardwareChannelMapping = ...
        'Not assigned by NHPulse; map StoredName to Soterix/Runex ports explicitly.';
    conditionTemplate = struct('id', 0, 'name', '', 'description', '', ...
        'currentsMa', [], 'recipe', {{}}, 'predictedEegVoltageMicroV', []);
    protocol.conditions = repmat(conditionTemplate, 2, 1);
    protocol.conditions(1).id = 1;
    protocol.conditions(1).name = 'targetOptimized';
    protocol.conditions(1).description = ...
        'Brain-target-optimized stimulus from the finalized cap design.';
    protocol.conditions(1).currentsMa = result.baselineCurrentsMa(:);
    protocol.conditions(1).recipe = result.baselineRecipe;
    protocol.conditions(1).predictedEegVoltageMicroV = ...
        result.baselineEegVoltageMicroV(:);
    protocol.conditions(2).id = 2;
    protocol.conditions(2).name = 'eegOrthogonalControl';
    protocol.conditions(2).description = ...
        'Matched-current stimulus optimized for an orthogonal predicted EEG artifact.';
    protocol.conditions(2).currentsMa = result.alternateCurrentsMa(:);
    protocol.conditions(2).recipe = result.alternateRecipe;
    protocol.conditions(2).predictedEegVoltageMicroV = ...
        result.alternateEegVoltageMicroV(:);
    protocol.constraints = struct('totalCurrentMa', result.totalCurrentMa, ...
        'maxCurrentPerElectrodeMa', result.maxCurrentPerElectrodeMa, ...
        'netCurrentToleranceMa', 1e-6);
    protocol.predictedContrast = struct( ...
        'topographyCorrelation', result.topographyCorrelation, ...
        'weightedTopographyCorrelation', result.weightedTopographyCorrelation, ...
        'weightedSeparationMicroV', 1e6*result.weightedSeparationV, ...
        'eegNames', {result.eegNames(:)});
    protocol.sources = struct( ...
        'layoutReportMat', getField(review.recipeInfo, 'layoutReportMat', ''), ...
        'sparseReportMat', getField(review.recipeInfo, 'sparseReportMat', ''), ...
        'transferMatrixReport', result.transferMatrixReport, ...
        'optimizationReport', result.reportMat, ...
        't1File', getField(layout, 't1File', ''));
end

function value = getField(S, name, fallback)
    if isfield(S, name) && ~isempty(S.(name))
        value = S.(name);
    else
        value = fallback;
    end
end

function tag = safeFilePart(value)
    tag = regexprep(strtrim(char(value)), '[^A-Za-z0-9_-]+', '_');
    tag = regexprep(tag, '_+', '_');
    tag = regexprep(tag, '^_+|_+$', '');
    if isempty(tag), tag = 'tesEegContrast'; end
end

function h = shortHash(txt)
    txt = uint8(char(txt));
    value = 5381;
    modulus = 2^32;
    for i = 1:numel(txt)
        value = mod(value*33 + double(txt(i)), modulus);
    end
    h = lower(dec2hex(round(value), 8));
end

function ensureDir(folder)
    if exist(folder, 'dir') ~= 7, mkdir(folder); end
end

function value = expandUserPath(value)
    value = char(value);
    if startsWith(value, '~')
        home = getenv('USERPROFILE');
        if isempty(home), home = getenv('HOME'); end
        value = fullfile(home, value(2:end));
    end
end

function printSummary(out)
    fprintf('\nNHPulse tES contrast protocol\n');
    fprintf('  conditions: targetOptimized, eegOrthogonalControl\n');
    fprintf('  predicted topography correlation: %.6g\n', ...
        out.protocol.predictedContrast.topographyCorrelation);
    fprintf('  fixed channel order and signed currents (mA):\n');
    disp(out.channelTable(:, 1:4));
    fprintf('  protocol MAT: %s\n', out.protocolFile);
    if ~isempty(out.csvFile), fprintf('  current CSV: %s\n', out.csvFile); end
    fprintf(['  Map StoredName to physical Soterix/Runex channel numbers ', ...
        'before commanding hardware.\n\n']);
end
