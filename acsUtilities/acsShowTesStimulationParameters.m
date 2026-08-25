function out = acsShowTesStimulationParameters(sourceIn, varargin)
% ACSSHOWTESSTIMULATIONPARAMETERS Review a saved tES stimulation recipe.
%
% out = acsShowTesStimulationParameters() opens a file picker for a saved
% sparse optimization, combined layout, EEG prediction, or manufacturing MAT
% product and displays the tES currents.
%
% out = acsShowTesStimulationParameters(fileNameOrTag) accepts either a MAT
% file or a tag searched under the configured output folders.
%
% out = acsShowTesStimulationParameters(combinedLayout) or
% acsShowTesStimulationParameters(finalSparse) accepts in-memory structs.
%
% Name-value options:
%   sparseResult        : explicit sparse result struct/MAT file ['']
%   layout              : explicit combined layout struct/MAT file ['']
%   eegPrediction       : explicit EEG prediction struct/MAT file ['']
%   searchRoot          : folder searched for tags ['']
%   activeElectrodeCount: filter sparse results by requested count [[]]
%   currentThresholdMa  : current threshold for active channels [1e-6]
%   currentToleranceMa  : tolerance when matching saved products [1e-5]
%   labelMode           : 'display' or 'raw' ['display']
%   showParameterFigure : show a compact table figure [true]
%   showField           : 'auto', 'always', or 'never' ['auto']
%   showEegTopography   : 'auto', 'always', or 'never' ['auto']
%   fieldOptions        : extra options for acsVisualizeSparseRoastLeadField [{}]
%   topographyOptions   : extra options for acsVisualizeEegVoltageTopography [{}]
%   saveFigures         : save replayed figures where supported [false]
%   saveTable           : write current table CSV [false]
%   tableFile           : explicit CSV table output ['']
%   outputFolder        : folder for automatic CSV output ['']
%   filePickerTitle     : file-picker title ['Select tES stimulation MAT']
%   verbose             : print summary/table [true]

    parameterNames = inputParameterNames();
    if nargin < 1
        sourceIn = [];
    elseif isNameValueKey(sourceIn, parameterNames)
        varargin = [{sourceIn}, varargin];
        sourceIn = [];
    end

    opts = parseInputs(varargin{:});
    addLocalDependencies();

    state = emptyState();
    hasExplicitProducts = ~isempty(opts.sparseResult) || ...
        ~isempty(opts.layout) || ~isempty(opts.eegPrediction);
    if isempty(sourceIn)
        if ~hasExplicitProducts
            sourceFile = pickReviewFile(opts);
            state = ingestFile(state, sourceFile, 'primary');
            state.sourceMode = 'filePicker';
        end
    else
        state = ingestInput(state, sourceIn, 'primary', opts);
    end
    state = ingestOptional(state, opts.sparseResult, 'sparseResult', opts);
    state = ingestOptional(state, opts.layout, 'layout', opts);
    state = ingestOptional(state, opts.eegPrediction, 'eegPrediction', opts);
    state = completeState(state, opts);

    [currentTable, recipeInfo] = makeCurrentTable(state, opts);
    tableFile = maybeSaveCurrentTable(currentTable, state, opts);
    parameterFigure = maybeMakeParameterFigure(currentTable, recipeInfo, opts);
    fieldQc = maybeShowField(state, opts);
    eegTopography = maybeShowEegTopography(state, opts);

    out = struct();
    out.createdOn = char(datetime('now'));
    out.type = 'tesStimulationParameters';
    out.currentTable = currentTable;
    out.recipe = recipeInfo.recipe;
    out.sourceRecipe = recipeInfo.sourceRecipe;
    out.recipeInfo = recipeInfo;
    out.sourceInfo = state.sourceInfo;
    out.sparse = stripFigure(state.sparse);
    out.layout = stripFigure(state.layout);
    out.eegPrediction = stripFigure(state.eegPrediction);
    out.parameterFigure = parameterFigure;
    out.fieldQc = fieldQc;
    out.eegTopography = eegTopography;
    out.tableFile = tableFile;
    out.options = opts;

    if opts.verbose
        printSummary(out);
    end
end

function opts = parseInputs(varargin)
    p = inputParser;
    p.FunctionName = 'acsShowTesStimulationParameters';
    addParameter(p, 'sparseResult', [], @(x) true);
    addParameter(p, 'layout', [], @(x) true);
    addParameter(p, 'eegPrediction', [], @(x) true);
    addParameter(p, 'searchRoot', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'activeElectrodeCount', [], ...
        @(x) isempty(x) || (isnumeric(x) && isscalar(x) && isfinite(x) && x >= 1));
    addParameter(p, 'currentThresholdMa', 1e-6, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0);
    addParameter(p, 'currentToleranceMa', 1e-5, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0);
    addParameter(p, 'labelMode', 'display', @(x) ischar(x) || isstring(x));
    addParameter(p, 'showParameterFigure', true, @isBoolLike);
    addParameter(p, 'showField', 'auto', @(x) ischar(x) || isstring(x) || islogical(x) || isnumeric(x));
    addParameter(p, 'showEegTopography', 'auto', @(x) ischar(x) || isstring(x) || islogical(x) || isnumeric(x));
    addParameter(p, 'fieldOptions', {}, @iscell);
    addParameter(p, 'topographyOptions', {}, @iscell);
    addParameter(p, 'saveFigures', false, @isBoolLike);
    addParameter(p, 'saveTable', false, @isBoolLike);
    addParameter(p, 'tableFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'outputFolder', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'filePickerTitle', 'Select tES stimulation MAT', ...
        @(x) ischar(x) || isstring(x));
    addParameter(p, 'verbose', true, @isBoolLike);
    parse(p, varargin{:});

    opts = p.Results;
    opts.searchRoot = expandUserPath(char(opts.searchRoot));
    opts.activeElectrodeCount = double(opts.activeElectrodeCount);
    opts.currentThresholdMa = double(opts.currentThresholdMa);
    opts.currentToleranceMa = double(opts.currentToleranceMa);
    opts.labelMode = validatestring(char(opts.labelMode), {'display', 'raw'}, ...
        mfilename, 'labelMode');
    opts.showParameterFigure = logical(opts.showParameterFigure);
    opts.showField = normalizeAutoMode(opts.showField, 'showField');
    opts.showEegTopography = normalizeAutoMode(opts.showEegTopography, ...
        'showEegTopography');
    opts.saveFigures = logical(opts.saveFigures);
    opts.saveTable = logical(opts.saveTable);
    opts.tableFile = expandUserPath(char(opts.tableFile));
    opts.outputFolder = expandUserPath(char(opts.outputFolder));
    opts.filePickerTitle = char(opts.filePickerTitle);
    opts.verbose = logical(opts.verbose);
end

function names = inputParameterNames()
    names = {'sparseResult', 'layout', 'eegPrediction', 'searchRoot', ...
        'activeElectrodeCount', 'currentThresholdMa', 'currentToleranceMa', ...
        'labelMode', 'showParameterFigure', 'showField', ...
        'showEegTopography', 'fieldOptions', 'topographyOptions', ...
        'saveFigures', 'saveTable', 'tableFile', 'outputFolder', ...
        'filePickerTitle', 'verbose'};
end

function tf = isNameValueKey(value, parameterNames)
    tf = (ischar(value) || isstring(value)) && ...
        any(strcmpi(char(value), parameterNames));
end

function tf = isBoolLike(x)
    tf = (islogical(x) || isnumeric(x)) && isscalar(x);
end

function mode = normalizeAutoMode(value, name)
    if islogical(value) || isnumeric(value)
        if logical(value)
            mode = 'always';
        else
            mode = 'never';
        end
        return;
    end
    mode = lower(strtrim(char(value)));
    switch mode
        case {'auto', 'ifpresent', 'ifavailable'}
            mode = 'auto';
        case {'always', 'true', 'yes', 'on'}
            mode = 'always';
        case {'never', 'false', 'no', 'off', 'none'}
            mode = 'never';
        otherwise
            error('acsShowTesStimulationParameters:BadMode', ...
                '%s must be ''auto'', ''always'', or ''never''.', name);
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

function state = emptyState()
    state = struct();
    state.sparse = [];
    state.layout = [];
    state.eegPrediction = [];
    state.sparseCandidates = repmat(emptyCandidate(), 0, 1);
    state.layoutCandidates = repmat(emptyCandidate(), 0, 1);
    state.eegPredictionCandidates = repmat(emptyCandidate(), 0, 1);
    state.sourceInfo = repmat(emptySourceInfo(), 0, 1);
    state.sourceMode = '';
    state.tag = '';
end

function candidate = emptyCandidate()
    candidate = struct('value', [], 'sourceInfo', emptySourceInfo(), ...
        'score', 0);
end

function info = emptySourceInfo()
    info = struct('roleHint', '', 'file', '', 'variableName', '', ...
        'kind', '', 'tag', '', 'picked', false, 'datenum', 0);
end

function state = ingestOptional(state, value, roleHint, opts)
    if isempty(value)
        return;
    end
    state = ingestInput(state, value, roleHint, opts);
end

function state = ingestInput(state, value, roleHint, opts)
    if isstruct(value)
        info = emptySourceInfo();
        info.roleHint = roleHint;
        info.kind = 'struct';
        state = ingestStruct(state, value, info);
        return;
    end
    if ~(ischar(value) || isstring(value))
        error('acsShowTesStimulationParameters:BadInput', ...
            'Inputs must be empty, structs, MAT files, or search tags.');
    end

    raw = char(value);
    fileName = expandUserPath(raw);
    if exist(fileName, 'file') == 2
        state = ingestFile(state, fileName, roleHint);
        return;
    end
    if endsWith(lower(fileName), '.mat') || looksLikeFilePath(fileName)
        error('acsShowTesStimulationParameters:MissingFile', ...
            'MAT file not found: %s', fileName);
    end
    state.tag = raw;
    state = ingestTag(state, raw, opts);
end

function state = ingestFile(state, fileName, roleHint)
    fileName = expandUserPath(char(fileName));
    if exist(fileName, 'file') ~= 2
        error('acsShowTesStimulationParameters:MissingFile', ...
            'MAT file not found: %s', fileName);
    end
    raw = load(fileName);
    names = fieldnames(raw);
    added = false;
    for i = 1:numel(names)
        if ~isstruct(raw.(names{i})) || isempty(raw.(names{i}))
            continue;
        end
        value = raw.(names{i});
        info = emptySourceInfo();
        info.roleHint = roleHint;
        info.file = fileName;
        info.variableName = names{i};
        info.datenum = fileDatenum(fileName);
        before = candidateCount(state);
        state = ingestStruct(state, value, info);
        added = added || candidateCount(state) > before;
    end
    if ~added
        error('acsShowTesStimulationParameters:NoReadableStruct', ...
            ['MAT file does not contain a sparse result, combined layout, ', ...
             'EEG prediction, or manufacturing layout: %s'], fileName);
    end
end

function state = ingestStruct(state, value, info)
    if numel(value) > 1
        for i = 1:numel(value)
            state = ingestStruct(state, value(i), info);
        end
        return;
    end

    if looksLikeSparse(value)
        state = addCandidate(state, 'sparse', value, info);
    end
    if looksLikeLayout(value)
        state = addCandidate(state, 'layout', value, info);
    end
    if looksLikeEegPrediction(value)
        state = addCandidate(state, 'eegPrediction', value, info);
    end

    nestedFields = {'expandedLayout', 'layout', 'combinedLayout', ...
        'sparse', 'finalSparse', 'eegPrediction', 'topography'};
    for i = 1:numel(nestedFields)
        field = nestedFields{i};
        if isfield(value, field) && isstruct(value.(field)) && ...
                ~isempty(value.(field))
            nestedInfo = info;
            if isempty(nestedInfo.variableName)
                nestedInfo.variableName = field;
            else
                nestedInfo.variableName = [nestedInfo.variableName '.' field];
            end
            state = ingestStruct(state, value.(field), nestedInfo);
        end
    end
end

function n = candidateCount(state)
    n = numel(state.sparseCandidates) + numel(state.layoutCandidates) + ...
        numel(state.eegPredictionCandidates);
end

function state = addCandidate(state, kind, value, info)
    info.kind = kind;
    candidate = struct('value', value, 'sourceInfo', info, 'score', 0);
    switch kind
        case 'sparse'
            candidate.score = sparseScore(value, info);
            state.sparseCandidates(end + 1, 1) = candidate;
        case 'layout'
            candidate.score = layoutScore(value, info);
            state.layoutCandidates(end + 1, 1) = candidate;
        case 'eegPrediction'
            candidate.score = predictionScore(value, info);
            state.eegPredictionCandidates(end + 1, 1) = candidate;
    end
    state.sourceInfo(end + 1, 1) = info;
end

function tf = looksLikeSparse(S)
    tf = isstruct(S) && ...
        ((all(isfield(S, {'t1File', 'leadFieldTag', 'electrodeNames', ...
        'currentsMa', 'selectedIndices'}))) || ...
         (all(isfield(S, {'selectedNames', 'selectedCurrentsMa'}))));
end

function tf = looksLikeLayout(S)
    tf = isstruct(S) && isfield(S, 'names') && ~isempty(S.names) && ...
        isfield(S, 'layoutCoordinatesMm') && ~isempty(S.layoutCoordinatesMm);
end

function tf = looksLikeEegPrediction(S)
    tf = isstruct(S) && isfield(S, 'eegNames') && ...
        (isfield(S, 'eegVoltageReferencedMicroV') || ...
         isfield(S, 'eegVoltageReferencedV') || ...
         isfield(S, 'eegVoltageRawV'));
end

function score = sparseScore(S, info)
    score = info.datenum;
    if isfield(S, 'reportMat') && ~isempty(S.reportMat)
        score = max(score, fileDatenum(S.reportMat));
    end
    if isfield(S, 'selectedNames') && ~isempty(S.selectedNames)
        score = score + 10;
    end
end

function score = layoutScore(S, info)
    score = info.datenum;
    if isfield(S, 'reportMat') && ~isempty(S.reportMat)
        score = max(score, fileDatenum(S.reportMat));
    end
    if hasLayoutTesRecipe(S)
        score = score + 100;
    elseif isfield(S, 'siteRoles') && any(strcmpi(cellstr(S.siteRoles(:)), 'tES'))
        score = score + 10;
    end
end

function score = predictionScore(S, info)
    score = info.datenum;
    if isfield(S, 'reportMat') && ~isempty(S.reportMat)
        score = max(score, fileDatenum(S.reportMat));
    end
    if isfield(S, 'topography') && isstruct(S.topography)
        score = score + 10;
    end
end

function tf = hasLayoutTesRecipe(layout)
    tf = isfield(layout, 'tesNames') && ~isempty(layout.tesNames) && ...
        isfield(layout, 'tesCurrentsMa') && ~isempty(layout.tesCurrentsMa);
end

function tf = looksLikeFilePath(value)
    value = char(value);
    tf = contains(value, '/') || contains(value, '\') || ...
        ~isempty(regexp(value, '^[A-Za-z]:', 'once'));
end

function d = fileDatenum(fileName)
    d = 0;
    try
        info = dir(expandUserPath(char(fileName)));
        if ~isempty(info)
            d = info(1).datenum;
        end
    catch
    end
end

function fileName = pickReviewFile(opts)
    if ~usejava('desktop')
        error('acsShowTesStimulationParameters:NoDesktopPicker', ...
            ['No source was provided and MATLAB desktop file picking is ', ...
             'not available. Provide a sparse/layout/eegPrediction MAT file ', ...
             'or a search tag.']);
    end
    startDir = defaultSearchRoot(opts);
    [filePart, folder] = uigetfile( ...
        {'*.mat', 'Saved NHPulse/ROAST MAT products (*.mat)'; ...
         '*.*', 'All files (*.*)'}, ...
        opts.filePickerTitle, startDir);
    if isequal(filePart, 0)
        error('acsShowTesStimulationParameters:FilePickerCancelled', ...
            'tES stimulation file selection was cancelled.');
    end
    fileName = fullfile(folder, filePart);
end

function state = ingestTag(state, tag, opts)
    roots = candidateSearchRoots(opts);
    files = findTaggedReviewFiles(tag, roots);
    if isempty(files)
        error('acsShowTesStimulationParameters:TagNotFound', ...
            'Could not find saved stimulation/layout products matching tag "%s".', ...
            tag);
    end
    for i = 1:numel(files)
        try
            state = ingestFile(state, files{i}, 'tag');
        catch
        end
    end
end

function files = findTaggedReviewFiles(tag, roots)
    tag = safeSearchToken(tag);
    patterns = { ...
        sprintf('*%s*tesEeg*customLocations*_report.mat', tag), ...
        sprintf('*%s*manufacturing*_report.mat', tag), ...
        sprintf('*%s*eegVoltagePrediction.mat', tag), ...
        sprintf('*%s*lf*tes*.mat', tag), ...
        sprintf('*%s*customLocations*_report.mat', tag), ...
        sprintf('*%s*_report.mat', tag), ...
        sprintf('*%s*.mat', tag)};
    files = {};
    for pIdx = 1:numel(patterns)
        for rIdx = 1:numel(roots)
            hits = dir(fullfile(roots{rIdx}, '**', patterns{pIdx}));
            hits = hits(~[hits.isdir]);
            for hIdx = 1:numel(hits)
                fileName = fullfile(hits(hIdx).folder, hits(hIdx).name);
                if isLikelyReviewMat(fileName)
                    files{end + 1, 1} = fileName; %#ok<AGROW>
                end
            end
        end
    end
    files = uniqueFilesNewestFirst(files);
end

function tf = isLikelyReviewMat(fileName)
    [~, stem] = fileparts(fileName);
    lowerStem = lower(stem);
    reject = {'_roastresult', '_roastoptions', '_usedelecarea', ...
        '_acsleadfieldrequest', '_meshes', '_manufacturingskinmesh', ...
        '_skinmesh'};
    tf = ~any(contains(lowerStem, reject));
end

function token = safeSearchToken(token)
    token = char(token);
    token = strrep(token, '*', '');
    token = strrep(token, '?', '');
end

function files = uniqueFilesNewestFirst(files)
    files = cellfun(@expandUserPath, files(:), 'UniformOutput', false);
    [~, ia] = unique(lower(files), 'stable');
    files = files(sort(ia));
    dates = cellfun(@fileDatenum, files);
    [~, order] = sort(dates, 'descend');
    files = files(order);
end

function roots = candidateSearchRoots(opts)
    roots = {};
    if ~isempty(opts.searchRoot)
        roots{end + 1} = opts.searchRoot; %#ok<AGROW>
    end
    try
        if exist('acsPaths', 'file') == 2
            P = acsPaths();
            fields = {'outputRoot', 'subjectOutputRoot', 'capWorkFolder'};
            for i = 1:numel(fields)
                if isfield(P, fields{i}) && ~isempty(P.(fields{i}))
                    roots{end + 1} = P.(fields{i}); %#ok<AGROW>
                end
            end
        end
    catch
    end
    roots{end + 1} = fullfile(pwd, 'outputs'); %#ok<AGROW>
    roots{end + 1} = pwd; %#ok<AGROW>
    roots = uniqueExistingDirs(roots);
end

function root = defaultSearchRoot(opts)
    roots = candidateSearchRoots(opts);
    if isempty(roots)
        root = pwd;
    else
        root = roots{1};
    end
end

function roots = uniqueExistingDirs(rootsIn)
    roots = {};
    seen = {};
    for i = 1:numel(rootsIn)
        root = expandUserPath(char(rootsIn{i}));
        if isempty(root) || exist(root, 'dir') ~= 7
            continue;
        end
        try
            key = lower(char(java.io.File(root).getCanonicalPath()));
        catch
            key = lower(root);
        end
        if any(strcmp(key, seen))
            continue;
        end
        seen{end + 1} = key; %#ok<AGROW>
        roots{end + 1} = root; %#ok<AGROW>
    end
end

function state = completeState(state, opts)
    state.layout = chooseLayout(state.layoutCandidates);
    state.sparse = chooseSparse(state.sparseCandidates, state.layout, opts);
    state.eegPrediction = choosePrediction(state.eegPredictionCandidates, ...
        state.layout, opts);

    if isempty(state.layout) && ~isempty(state.sparse)
        state.layout = findLayoutMatchingSparse(state.sparse, opts);
    end
    if isempty(state.sparse) && ~isempty(state.layout)
        state.sparse = findSparseMatchingLayout(state.layout, opts);
    end
    if isempty(state.eegPrediction)
        state.eegPrediction = findPredictionMatchingLayoutOrSparse( ...
            state.layout, state.sparse, opts);
    end
end

function layout = chooseLayout(candidates)
    layout = [];
    if isempty(candidates)
        return;
    end
    scores = [candidates.score];
    [~, idx] = max(scores);
    layout = candidates(idx).value;
end

function sparse = chooseSparse(candidates, layout, opts)
    sparse = [];
    if isempty(candidates)
        return;
    end
    keep = true(numel(candidates), 1);
    if ~isempty(opts.activeElectrodeCount)
        for i = 1:numel(candidates)
            keep(i) = sparseRequestedCount(candidates(i).value) == ...
                opts.activeElectrodeCount;
        end
    end
    if ~any(keep)
        keep(:) = true;
    end
    candidates = candidates(keep);
    if ~isempty(layout) && hasLayoutTesRecipe(layout)
        match = false(numel(candidates), 1);
        for i = 1:numel(candidates)
            match(i) = sparseMatchesLayout(candidates(i).value, layout, opts);
        end
        if any(match)
            candidates = candidates(match);
        end
    end
    scores = [candidates.score];
    [~, idx] = max(scores);
    sparse = candidates(idx).value;
end

function n = sparseRequestedCount(sparse)
    n = NaN;
    if isfield(sparse, 'activeElectrodeCountRequested') && ...
            ~isempty(sparse.activeElectrodeCountRequested)
        n = double(sparse.activeElectrodeCountRequested);
    elseif isfield(sparse, 'selectedNames') && ~isempty(sparse.selectedNames)
        n = numel(sparse.selectedNames);
    elseif isfield(sparse, 'selectedIndices') && ~isempty(sparse.selectedIndices)
        n = numel(sparse.selectedIndices);
    end
end

function prediction = choosePrediction(candidates, layout, opts)
    prediction = [];
    if isempty(candidates)
        return;
    end
    if ~isempty(layout)
        match = false(numel(candidates), 1);
        for i = 1:numel(candidates)
            match(i) = predictionMatchesLayout(candidates(i).value, layout, opts);
        end
        if any(match)
            candidates = candidates(match);
        end
    end
    scores = [candidates.score];
    [~, idx] = max(scores);
    prediction = candidates(idx).value;
end

function sparse = findSparseMatchingLayout(layout, opts)
    sparse = [];
    if isempty(layout) || ~hasLayoutTesRecipe(layout)
        return;
    end
    roots = candidateSearchRoots(opts);
    files = {};
    for i = 1:numel(roots)
        hits = dir(fullfile(roots{i}, '**', '*lf*tes*.mat'));
        hits = hits(~[hits.isdir]);
        for j = 1:numel(hits)
            fileName = fullfile(hits(j).folder, hits(j).name);
            if isLikelyReviewMat(fileName)
                files{end + 1, 1} = fileName; %#ok<AGROW>
            end
        end
    end
    files = uniqueFilesNewestFirst(files);
    for i = 1:numel(files)
        try
            S = loadFirstStructOfKind(files{i}, 'sparse');
            if sparseMatchesLayout(S, layout, opts)
                sparse = S;
                return;
            end
        catch
        end
    end
end

function layout = findLayoutMatchingSparse(sparse, opts)
    layout = [];
    if isempty(sparse)
        return;
    end
    roots = candidateSearchRoots(opts);
    files = {};
    patterns = {'*tesEeg*customLocations*_report.mat', ...
        '*manufacturing*_report.mat', '*customLocations*_report.mat'};
    for pIdx = 1:numel(patterns)
        for rIdx = 1:numel(roots)
            hits = dir(fullfile(roots{rIdx}, '**', patterns{pIdx}));
            hits = hits(~[hits.isdir]);
            for hIdx = 1:numel(hits)
                fileName = fullfile(hits(hIdx).folder, hits(hIdx).name);
                if isLikelyReviewMat(fileName)
                    files{end + 1, 1} = fileName; %#ok<AGROW>
                end
            end
        end
    end
    files = uniqueFilesNewestFirst(files);
    for i = 1:numel(files)
        try
            L = loadFirstStructOfKind(files{i}, 'layout');
            if hasLayoutTesRecipe(L) && sparseMatchesLayout(sparse, L, opts)
                layout = L;
                return;
            end
        catch
        end
    end
end

function prediction = findPredictionMatchingLayoutOrSparse(layout, sparse, opts)
    prediction = [];
    roots = candidateSearchRoots(opts);
    files = {};
    for i = 1:numel(roots)
        hits = dir(fullfile(roots{i}, '**', '*eegVoltagePrediction.mat'));
        hits = hits(~[hits.isdir]);
        for j = 1:numel(hits)
            files{end + 1, 1} = fullfile(hits(j).folder, hits(j).name); %#ok<AGROW>
        end
    end
    files = uniqueFilesNewestFirst(files);
    for i = 1:numel(files)
        try
            P = loadFirstStructOfKind(files{i}, 'eegPrediction');
            if ~isempty(layout) && ~predictionMatchesLayout(P, layout, opts)
                continue;
            end
            if ~isempty(sparse) && ~predictionMatchesSparse(P, sparse, opts)
                continue;
            end
            prediction = P;
            return;
        catch
        end
    end
end

function S = loadFirstStructOfKind(fileName, kind)
    raw = load(fileName);
    names = fieldnames(raw);
    for i = 1:numel(names)
        value = raw.(names{i});
        if ~isstruct(value) || isempty(value)
            continue;
        end
        S = firstStructOfKind(value, kind);
        if ~isempty(S)
            return;
        end
    end
    error('acsShowTesStimulationParameters:NoMatchingStruct', ...
        'No %s struct in %s.', kind, fileName);
end

function S = firstStructOfKind(value, kind)
    S = [];
    if numel(value) > 1
        for i = 1:numel(value)
            S = firstStructOfKind(value(i), kind);
            if ~isempty(S), return; end
        end
        return;
    end
    switch kind
        case 'sparse'
            if looksLikeSparse(value), S = value; return; end
        case 'layout'
            if looksLikeLayout(value), S = value; return; end
        case 'eegPrediction'
            if looksLikeEegPrediction(value), S = value; return; end
    end
    nestedFields = {'expandedLayout', 'layout', 'combinedLayout', ...
        'sparse', 'finalSparse', 'eegPrediction'};
    for i = 1:numel(nestedFields)
        field = nestedFields{i};
        if isfield(value, field) && isstruct(value.(field)) && ...
                ~isempty(value.(field))
            S = firstStructOfKind(value.(field), kind);
            if ~isempty(S), return; end
        end
    end
end

function tf = sparseMatchesLayout(sparse, layout, opts)
    tf = false;
    if isempty(sparse) || isempty(layout) || ~hasLayoutTesRecipe(layout)
        return;
    end
    [sNames, sCurrents] = selectedSparseNamesAndCurrents(sparse, opts);
    if isfield(layout, 'sourceTesNames') && ~isempty(layout.sourceTesNames)
        lNames = normalizeNames(layout.sourceTesNames);
    else
        lNames = normalizeNames(layout.tesNames);
    end
    lCurrents = double(layout.tesCurrentsMa(:));
    if numel(sNames) ~= numel(lNames) || numel(sCurrents) ~= numel(lCurrents)
        return;
    end
    [sNamesSorted, sOrder] = sort(lower(string(sNames)));
    [lNamesSorted, lOrder] = sort(lower(string(lNames)));
    if ~isequal(sNamesSorted, lNamesSorted)
        return;
    end
    tf = max(abs(sCurrents(sOrder) - lCurrents(lOrder))) <= ...
        opts.currentToleranceMa;
end

function tf = predictionMatchesLayout(prediction, layout, opts)
    tf = true;
    if isempty(prediction) || isempty(layout)
        return;
    end
    if isfield(prediction, 'electrodeNames') && isfield(layout, 'names')
        pNames = normalizeNames(prediction.electrodeNames);
        lNames = normalizeNames(layout.names);
        tf = all(ismember(lower(string(prediction.eegNames)), lower(string(lNames)))) && ...
            any(ismember(lower(string(pNames)), lower(string(lNames))));
    end
    if tf && hasLayoutTesRecipe(layout) && ...
            isfield(prediction, 'currentsByElectrodeMa') && ...
            isfield(prediction, 'electrodeNames')
        names = normalizeNames(prediction.electrodeNames);
        rows = nameRows(normalizeNames(layout.tesNames), names);
        if all(rows > 0)
            predCurrents = double(prediction.currentsByElectrodeMa(rows));
            tf = max(abs(predCurrents(:) - double(layout.tesCurrentsMa(:)))) <= ...
                opts.currentToleranceMa;
        end
    end
end

function tf = predictionMatchesSparse(prediction, sparse, opts)
    tf = true;
    if isempty(prediction) || isempty(sparse) || ...
            ~isfield(prediction, 'inputTesRecipe')
        return;
    end
    try
        [pNames, pCurrents] = parseRecipe(prediction.inputTesRecipe);
        [sNames, sCurrents] = selectedSparseNamesAndCurrents(sparse, opts);
        if numel(pNames) ~= numel(sNames)
            tf = false;
            return;
        end
        [pNamesSorted, pOrder] = sort(lower(string(pNames)));
        [sNamesSorted, sOrder] = sort(lower(string(sNames)));
        if ~isequal(pNamesSorted, sNamesSorted)
            tf = false;
            return;
        end
        tf = max(abs(pCurrents(pOrder) - sCurrents(sOrder))) <= ...
            opts.currentToleranceMa;
    catch
        tf = true;
    end
end

function [currentTable, info] = makeCurrentTable(state, opts)
    layout = state.layout;
    sparse = state.sparse;
    prediction = state.eegPrediction;
    coordFrame = '';

    if ~isempty(layout) && hasLayoutTesRecipe(layout)
        storedNames = normalizeNames(layout.tesNames);
        currents = double(layout.tesCurrentsMa(:));
        if isfield(layout, 'sourceTesNames') && ~isempty(layout.sourceTesNames)
            sourceNames = normalizeNames(layout.sourceTesNames);
        else
            sourceNames = storedNames;
        end
        coords = coordsForNames(layout, storedNames);
        coordFrame = 'capMakerPrintMm';
        source = 'combined layout';
    elseif ~isempty(prediction) && isfield(prediction, 'activeTesNames') && ...
            isfield(prediction, 'currentsByElectrodeMa') && ...
            isfield(prediction, 'electrodeNames')
        storedNames = normalizeNames(prediction.activeTesNames);
        allNames = normalizeNames(prediction.electrodeNames);
        rows = nameRows(storedNames, allNames);
        if any(rows < 1)
            error('acsShowTesStimulationParameters:CurrentNameMismatch', ...
                'EEG prediction active tES names do not match electrodeNames.');
        end
        currents = double(prediction.currentsByElectrodeMa(rows));
        sourceNames = storedNames;
        coords = coordsForNames(layout, storedNames);
        coordFrame = 'layoutCoordinatesMm';
        source = 'EEG prediction';
    elseif ~isempty(sparse)
        [storedNames, currents] = selectedSparseNamesAndCurrents(sparse, opts);
        sourceNames = storedNames;
        coords = selectedSparseCoordinates(sparse, opts);
        coordFrame = 'ROAST custom-location coordinates';
        source = 'sparse optimization';
    else
        error('acsShowTesStimulationParameters:NoCurrentRecipe', ...
            ['No current recipe was found. Provide a finalSparse MAT file, ', ...
             'a combinedLayout MAT file, or an EEG prediction report.']);
    end

    if numel(sourceNames) ~= numel(storedNames)
        sourceNames = padNames(sourceNames, numel(storedNames));
    end
    if numel(currents) ~= numel(storedNames)
        error('acsShowTesStimulationParameters:CurrentNameMismatch', ...
            'Current vector length does not match tES channel names.');
    end
    if isempty(coords) || size(coords, 1) ~= numel(storedNames)
        coords = nan(numel(storedNames), 3);
    end
    displayNames = storedNames;
    if strcmpi(opts.labelMode, 'display')
        displayNames = displayLabels(storedNames);
    end
    polarity = currentPolarity(currents, opts.currentThresholdMa);

    currentTable = table(displayNames(:), storedNames(:), sourceNames(:), ...
        currents(:), polarity(:), abs(currents(:)), ...
        coords(:, 1), coords(:, 2), coords(:, 3), ...
        'VariableNames', {'Channel', 'StoredName', 'SourceElectrode', ...
        'CurrentMa', 'Polarity', 'AbsCurrentMa', 'X', 'Y', 'Z'});

    info = struct();
    info.source = source;
    info.coordinateFrame = coordFrame;
    info.totalAnodalCurrentMa = sum(currents(currents > opts.currentThresholdMa));
    info.totalCathodalCurrentMa = -sum(currents(currents < -opts.currentThresholdMa));
    info.netCurrentMa = sum(currents);
    info.nActive = nnz(abs(currents) > opts.currentThresholdMa);
    info.recipe = makeRecipe(storedNames, currents);
    info.sourceRecipe = makeRecipe(sourceNames, currents);
    info.sparseReportMat = getOptionalField(sparse, 'reportMat', '');
    info.layoutReportMat = getOptionalField(layout, 'reportMat', '');
    info.eegPredictionReportMat = getOptionalField(prediction, 'reportMat', '');
    if ~isempty(sparse)
        info.leadFieldTag = getOptionalField(sparse, 'leadFieldTag', '');
        info.targetingTag = getOptionalField(sparse, 'targetingTag', '');
        info.targetVoxel = getOptionalField(sparse, 'targetVoxel', []);
        info.targetProjectedFieldVm = getOptionalField(sparse, ...
            'targetProjectedFieldVm', []);
        info.objectiveVm = getOptionalField(sparse, 'objectiveVm', []);
        info.searchMode = getOptionalField(sparse, 'searchMode', '');
    end
end

function names = padNames(names, n)
    names = normalizeNames(names);
    if numel(names) >= n
        names = names(1:n);
        return;
    end
    names(end + 1:n, 1) = {''};
end

function [names, currents] = selectedSparseNamesAndCurrents(sparse, opts)
    if isfield(sparse, 'selectedNames') && isfield(sparse, 'selectedCurrentsMa') && ...
            ~isempty(sparse.selectedNames) && ~isempty(sparse.selectedCurrentsMa)
        names = normalizeNames(sparse.selectedNames);
        currents = double(sparse.selectedCurrentsMa(:));
        return;
    end
    requireSparseFields(sparse, {'electrodeNames', 'currentsMa', 'selectedIndices'});
    allNames = normalizeNames(sparse.electrodeNames);
    selected = double(sparse.selectedIndices(:));
    selected = selected(selected >= 1 & selected <= numel(allNames));
    if isempty(selected)
        selected = find(abs(double(sparse.currentsMa(:))) > opts.currentThresholdMa);
    end
    names = allNames(selected);
    currents = double(sparse.currentsMa(selected));
end

function coords = selectedSparseCoordinates(sparse, opts)
    coords = [];
    if isfield(sparse, 'selectedVoxelCoordinates') && ...
            ~isempty(sparse.selectedVoxelCoordinates)
        coords = double(sparse.selectedVoxelCoordinates);
        return;
    end
    if isfield(sparse, 'candidateVoxelCoordinates') && ...
            isfield(sparse, 'selectedIndices') && ...
            ~isempty(sparse.candidateVoxelCoordinates)
        allCoords = double(sparse.candidateVoxelCoordinates);
        selected = double(sparse.selectedIndices(:));
        selected = selected(selected >= 1 & selected <= size(allCoords, 1));
        coords = allCoords(selected, :);
        return;
    end
    if isfield(sparse, 'electrodeNames') && isfield(sparse, 'currentsMa') && ...
            isfield(sparse, 'candidateVoxelCoordinates') && ...
            ~isempty(sparse.candidateVoxelCoordinates)
        selected = find(abs(double(sparse.currentsMa(:))) > opts.currentThresholdMa);
        coords = double(sparse.candidateVoxelCoordinates(selected, :));
    end
end

function requireSparseFields(S, fields)
    for i = 1:numel(fields)
        if ~isfield(S, fields{i}) || isempty(S.(fields{i}))
            error('acsShowTesStimulationParameters:MissingSparseField', ...
                'Sparse result is missing required field "%s".', fields{i});
        end
    end
end

function coords = coordsForNames(layout, queryNames)
    coords = [];
    if isempty(layout) || ~isfield(layout, 'names') || ...
            ~isfield(layout, 'layoutCoordinatesMm')
        return;
    end
    allNames = normalizeNames(layout.names);
    allCoords = double(layout.layoutCoordinatesMm);
    rows = nameRows(queryNames, allNames);
    if any(rows < 1) || size(allCoords, 1) < max(rows)
        return;
    end
    coords = allCoords(rows, 1:3);
end

function rows = nameRows(queryNames, allNames)
    queryNames = normalizeNames(queryNames);
    allNames = normalizeNames(allNames);
    rows = zeros(numel(queryNames), 1);
    for i = 1:numel(queryNames)
        idx = find(strcmpi(queryNames{i}, allNames), 1);
        if ~isempty(idx)
            rows(i) = idx;
        end
    end
end

function labels = displayLabels(names)
    labels = normalizeNames(names);
    for i = 1:numel(labels)
        label = labels{i};
        label = regexprep(label, '^customTES', 'tES', 'ignorecase');
        label = regexprep(label, '^customEEG', 'EEG', 'ignorecase');
        label = regexprep(label, '^tes', 'tES', 'ignorecase');
        labels{i} = label;
    end
end

function polarity = currentPolarity(currents, threshold)
    polarity = repmat({''}, numel(currents), 1);
    for i = 1:numel(currents)
        if currents(i) > threshold
            polarity{i} = 'anode';
        elseif currents(i) < -threshold
            polarity{i} = 'cathode';
        else
            polarity{i} = 'zero';
        end
    end
end

function recipe = makeRecipe(names, currents)
    names = normalizeNames(names);
    recipe = reshape([names(:), num2cell(currents(:))]', 1, []);
end

function [names, currents] = parseRecipe(recipe)
    if ~iscell(recipe) || mod(numel(recipe), 2) ~= 0
        error('acsShowTesStimulationParameters:BadRecipe', ...
            'Recipe must be an alternating name/current cell array.');
    end
    names = normalizeNames(recipe(1:2:end));
    currents = cell2mat(recipe(2:2:end));
    currents = double(currents(:));
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
        error('acsShowTesStimulationParameters:BadNames', ...
            'Names must be char, string, or cell array.');
    end
    names = names(:);
end

function value = getOptionalField(S, fieldName, defaultValue)
    value = defaultValue;
    if isstruct(S) && isfield(S, fieldName) && ~isempty(S.(fieldName))
        value = S.(fieldName);
    end
end

function fig = maybeMakeParameterFigure(currentTable, recipeInfo, opts)
    fig = [];
    if ~opts.showParameterFigure
        return;
    end
    if ~usejava('desktop')
        return;
    end
    fig = figure('Name', 'tES stimulation parameters', ...
        'NumberTitle', 'off', 'Color', 'w', ...
        'WindowStyle', 'normal', 'Position', [140 140 980 360]);
    summaryText = sprintf([ ...
        'tES stimulation parameters | %d active channels | ', ...
        'anodal %.4g mA | cathodal %.4g mA | net %.4g mA'], ...
        recipeInfo.nActive, recipeInfo.totalAnodalCurrentMa, ...
        recipeInfo.totalCathodalCurrentMa, recipeInfo.netCurrentMa);
    uicontrol(fig, 'Style', 'text', 'Units', 'normalized', ...
        'Position', [0.03 0.88 0.94 0.08], ...
        'String', summaryText, 'BackgroundColor', 'w', ...
        'HorizontalAlignment', 'left', 'FontWeight', 'bold', ...
        'FontSize', 11);
    uitable(fig, 'Units', 'normalized', 'Position', [0.03 0.08 0.94 0.78], ...
        'Data', table2cell(currentTable), ...
        'ColumnName', currentTable.Properties.VariableNames, ...
        'RowName', [], ...
        'ColumnWidth', {78, 110, 115, 88, 78, 92, 70, 70, 70});
end

function tableFile = maybeSaveCurrentTable(currentTable, state, opts)
    tableFile = expandUserPath(char(opts.tableFile));
    if isempty(tableFile) && opts.saveTable
        folder = opts.outputFolder;
        if isempty(folder)
            folder = sourceOutputFolder(state);
        end
        if isempty(folder)
            folder = pwd;
        end
        tableFile = fullfile(folder, 'tesStimulationParameters.csv');
    end
    if isempty(tableFile)
        return;
    end
    ensureDir(fileparts(tableFile));
    writetable(currentTable, tableFile);
end

function folder = sourceOutputFolder(state)
    folder = '';
    infos = state.sourceInfo;
    for i = 1:numel(infos)
        if ~isempty(infos(i).file)
            folder = fileparts(infos(i).file);
            return;
        end
    end
    if ~isempty(state.layout) && isfield(state.layout, 'reportMat') && ...
            ~isempty(state.layout.reportMat)
        folder = fileparts(char(state.layout.reportMat));
    elseif ~isempty(state.sparse) && isfield(state.sparse, 'reportMat') && ...
            ~isempty(state.sparse.reportMat)
        folder = fileparts(char(state.sparse.reportMat));
    end
end

function fieldQc = maybeShowField(state, opts)
    fieldQc = [];
    if strcmp(opts.showField, 'never')
        return;
    end
    if isempty(state.sparse)
        handleOptionalMissing(opts.showField, ...
            'No sparse result is available for brain-field replay.');
        return;
    end
    if ~canVisualizeSparseField(state.sparse)
        handleOptionalMissing(opts.showField, ...
            'Saved lead-field/mesh products needed for brain-field replay were not found.');
        return;
    end
    args = mergeNameValueDefaults(opts.fieldOptions, ...
        {'showFigures', true, 'saveFigures', opts.saveFigures});
    try
        fieldQc = acsVisualizeSparseRoastLeadField(state.sparse, args{:});
    catch ME
        handleOptionalError(opts.showField, ME, 'brain-field replay');
    end
end

function tf = canVisualizeSparseField(sparse)
    tf = false;
    if isempty(sparse) || ~all(isfield(sparse, {'t1File', 'leadFieldTag'}))
        return;
    end
    t1File = char(sparse.t1File);
    [folder, stem] = fileparts(t1File);
    resultFile = fullfile(folder, [stem '_' char(sparse.leadFieldTag) ...
        '_roastResult.mat']);
    meshFile = fullfile(folder, [stem '_' char(sparse.leadFieldTag) '.mat']);
    tf = exist(resultFile, 'file') == 2 && exist(meshFile, 'file') == 2;
end

function eegTopography = maybeShowEegTopography(state, opts)
    eegTopography = [];
    if strcmp(opts.showEegTopography, 'never')
        return;
    end
    if isempty(state.eegPrediction)
        handleOptionalMissing(opts.showEegTopography, ...
            'No saved EEG prediction report is available for topography replay.');
        return;
    end
    if isempty(state.layout)
        handleOptionalMissing(opts.showEegTopography, ...
            'No combined layout is available for EEG topography replay.');
        return;
    end
    args = mergeNameValueDefaults(opts.topographyOptions, ...
        {'showFigures', true, 'saveFigures', opts.saveFigures});
    try
        eegTopography = acsVisualizeEegVoltageTopography( ...
            state.eegPrediction, state.layout, args{:});
    catch ME
        handleOptionalError(opts.showEegTopography, ME, 'EEG topography replay');
    end
end

function args = mergeNameValueDefaults(args, defaults)
    args = args(:)';
    existingNames = lower(string(args(1:2:end)));
    for i = 1:2:numel(defaults)
        name = lower(string(defaults{i}));
        if ~any(existingNames == name)
            args = [args, defaults(i:i + 1)]; %#ok<AGROW>
        end
    end
end

function handleOptionalMissing(mode, message)
    if strcmp(mode, 'always')
        error('acsShowTesStimulationParameters:MissingReplayInput', '%s', message);
    end
end

function handleOptionalError(mode, ME, label)
    if strcmp(mode, 'always')
        rethrow(ME);
    end
    warning('acsShowTesStimulationParameters:ReplayFailed', ...
        'Could not run %s: %s', label, ME.message);
end

function printSummary(out)
    info = out.recipeInfo;
    fprintf('\ntES stimulation parameters\n');
    fprintf('  source: %s\n', info.source);
    if isfield(info, 'leadFieldTag') && ~isempty(info.leadFieldTag)
        fprintf('  lead field: %s\n', info.leadFieldTag);
    end
    if isfield(info, 'targetingTag') && ~isempty(info.targetingTag)
        fprintf('  targeting: %s\n', info.targetingTag);
    end
    if isfield(info, 'targetVoxel') && ~isempty(info.targetVoxel)
        fprintf('  target voxel: %s\n', mat2str(info.targetVoxel));
    end
    if isfield(info, 'targetProjectedFieldVm') && ...
            ~isempty(info.targetProjectedFieldVm)
        fprintf('  target projected field: %s V/m\n', ...
            mat2str(info.targetProjectedFieldVm, 4));
    elseif isfield(info, 'objectiveVm') && ~isempty(info.objectiveVm)
        fprintf('  target objective: %.6g V/m\n', info.objectiveVm);
    end
    fprintf('  coordinate frame for X/Y/Z: %s\n', info.coordinateFrame);
    fprintf('  active channels: %d\n', info.nActive);
    fprintf('  total anodal/cathodal/net current: %.6g / %.6g / %.6g mA\n\n', ...
        info.totalAnodalCurrentMa, info.totalCathodalCurrentMa, ...
        info.netCurrentMa);
    disp(out.currentTable);
    if ~isempty(out.tableFile)
        fprintf('  table: %s\n', out.tableFile);
    end
    if isstruct(out.fieldQc) && isfield(out.fieldQc, 'qcFigure') && ...
            ~isempty(out.fieldQc.qcFigure)
        fprintf('  brain field figure: %s\n', out.fieldQc.qcFigure);
    end
    if isstruct(out.eegTopography) && isfield(out.eegTopography, 'qcFigure') && ...
            ~isempty(out.eegTopography.qcFigure)
        fprintf('  EEG topography figure: %s\n', out.eegTopography.qcFigure);
    end
end

function S = stripFigure(S)
    if ~isstruct(S) || isempty(S)
        return;
    end
    if isfield(S, 'figure')
        S = rmfield(S, 'figure');
    end
    if isfield(S, 'topography') && isstruct(S.topography) && ...
            isfield(S.topography, 'figure')
        S.topography = rmfield(S.topography, 'figure');
    end
end

function ensureDir(folder)
    if isempty(folder)
        return;
    end
    if exist(folder, 'dir') ~= 7
        mkdir(folder);
    end
end

function pathOut = expandUserPath(pathIn)
    pathOut = char(pathIn);
    if isempty(pathOut)
        return;
    end
    if startsWith(pathOut, '~')
        home = char(java.lang.System.getProperty('user.home'));
        if numel(pathOut) == 1
            pathOut = home;
        elseif any(pathOut(2) == ['/' '\'])
            pathOut = fullfile(home, pathOut(3:end));
        end
    end
end
