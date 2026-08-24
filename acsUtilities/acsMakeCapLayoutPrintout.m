function out = acsMakeCapLayoutPrintout(layoutIn, varargin)
% ACSMAKECAPLAYOUTPRINTOUT Make a black-and-white cap wiring map.
%
% out = acsMakeCapLayoutPrintout() opens a file picker for a finalized
% cap/layout/manufacturing MAT product and writes a PDF printout next to it.
%
% out = acsMakeCapLayoutPrintout(fileNameOrTag) accepts either a MAT file or a
% cap-design tag. Tags are searched under the configured NHPulse output root.
%
% out = acsMakeCapLayoutPrintout(combinedLayout) draws a top-down capMaker
% print-frame footprint with electrode positions and labels. The figure is
% intended as a lab printout for wiring/checking cap layouts.
%
% Name-value options:
%   outputFile      : optional .pdf/.png/.svg export filename ['']
%   autoOutputFile  : when outputFile is empty, save a PDF beside source [true]
%   titleText       : title printed above the map ['Cap electrode layout']
%   labelMode       : 'display' or 'raw' ['display']
%   footprintSource : 'skinCache', 'layout', or 'auto' ['auto']
%   skinCacheFile   : explicit capMaker skin cache ['']
%   footprintMeshStage : 'fullHead', 'cap', or 'auto' ['auto']
%   searchRoot      : folder to search when fileNameOrTag is a tag ['']
%   outputFolder    : override automatic printout folder ['']
%   filePickerTitle : file-picker prompt ['Select cap layout/manufacturing MAT']
%   electrodeRadiusMm : outline radius for printed markers [5]
%   labelBackgroundAlpha : white label backing transparency [0.72]
%   labelBackgroundPaddingMm : label backing padding in print mm [0.8]
%   pageSizeInches  : figure size [8.5 11]
%   showFigures     : show figure [true]
%   saveFigures     : save outputFile when provided [true]
%   verbose         : print output summary [true]

    parameterNames = inputParameterNames();
    if nargin < 1
        layoutIn = [];
    elseif isNameValueKey(layoutIn, parameterNames)
        varargin = [{layoutIn}, varargin];
        layoutIn = [];
    end

    opts = parseInputs(varargin{:});
    [layout, sourceInfo] = readLayout(layoutIn, opts);
    [coords, names] = layoutCoordinatesAndNames(layout);
    roles = layoutSiteRoles(layout, names);
    displayNames = names;
    if strcmpi(opts.labelMode, 'display')
        displayNames = displayLabels(names);
    end
    [footprintXY, footprintInfo] = resolveFootprint(layout, coords, opts);

    figVisible = 'off';
    if opts.showFigures
        figVisible = 'on';
    end
    fig = makeFigure(footprintXY, coords(:, 1:2), displayNames, roles, ...
        opts, figVisible);

    outputFile = resolveOutputFile(opts.outputFile, layout, sourceInfo, opts);
    if opts.saveFigures && ~isempty(outputFile)
        ensureDir(fileparts(outputFile));
        saveFigure(fig, outputFile);
    end
    if ~opts.showFigures && isgraphics(fig)
        close(fig);
    end

    out = struct();
    out.createdOn = char(datetime('now'));
    out.type = 'capLayoutPrintout';
    out.names = names(:);
    out.displayNames = displayNames(:);
    out.siteRoles = roles(:);
    out.layoutCoordinatesMm = coords;
    out.footprintXYMm = footprintXY;
    out.footprintInfo = footprintInfo;
    out.outputFile = outputFile;
    out.sourceInfo = sourceInfo;
    out.options = opts;
    if opts.showFigures
        out.figure = fig;
    else
        out.figure = [];
    end

    if opts.verbose
        fprintf('\nCap layout printout\n');
        fprintf('  electrodes: %d\n', numel(names));
        fprintf('  footprint: %s\n', footprintInfo.source);
        if ~isempty(sourceInfo.file)
            fprintf('  source: %s\n', sourceInfo.file);
        end
        if ~isempty(outputFile)
            fprintf('  output: %s\n', outputFile);
        end
    end
end

function opts = parseInputs(varargin)
    p = inputParser;
    p.FunctionName = 'acsMakeCapLayoutPrintout';
    addParameter(p, 'outputFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'autoOutputFile', true, @isBoolLike);
    addParameter(p, 'titleText', 'Cap electrode layout', @(x) ischar(x) || isstring(x));
    addParameter(p, 'labelMode', 'display', @(x) ischar(x) || isstring(x));
    addParameter(p, 'footprintSource', 'auto', @(x) ischar(x) || isstring(x));
    addParameter(p, 'skinCacheFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'footprintMeshStage', 'auto', @(x) ischar(x) || isstring(x));
    addParameter(p, 'searchRoot', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'outputFolder', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'filePickerTitle', 'Select cap layout/manufacturing MAT', ...
        @(x) ischar(x) || isstring(x));
    addParameter(p, 'electrodeRadiusMm', 5, @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x > 0);
    addParameter(p, 'labelBackgroundAlpha', 0.72, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0 && x <= 1);
    addParameter(p, 'labelBackgroundPaddingMm', 0.8, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0);
    addParameter(p, 'pageSizeInches', [8.5 11], @(x) isnumeric(x) && numel(x) == 2 && all(x > 0));
    addParameter(p, 'showFigures', true, @isBoolLike);
    addParameter(p, 'saveFigures', true, @isBoolLike);
    addParameter(p, 'verbose', true, @isBoolLike);
    parse(p, varargin{:});

    opts = p.Results;
    opts.outputFile = expandUserPath(char(opts.outputFile));
    opts.autoOutputFile = logical(opts.autoOutputFile);
    opts.titleText = char(opts.titleText);
    opts.labelMode = validatestring(char(opts.labelMode), {'display', 'raw'}, ...
        mfilename, 'labelMode');
    opts.footprintSource = validatestring(char(opts.footprintSource), ...
        {'auto', 'skinCache', 'layout'}, mfilename, 'footprintSource');
    opts.skinCacheFile = expandUserPath(char(opts.skinCacheFile));
    opts.footprintMeshStage = validatestring(char(opts.footprintMeshStage), ...
        {'auto', 'fullHead', 'cap'}, mfilename, 'footprintMeshStage');
    opts.searchRoot = expandUserPath(char(opts.searchRoot));
    opts.outputFolder = expandUserPath(char(opts.outputFolder));
    opts.filePickerTitle = char(opts.filePickerTitle);
    opts.electrodeRadiusMm = double(opts.electrodeRadiusMm);
    opts.labelBackgroundAlpha = double(opts.labelBackgroundAlpha);
    opts.labelBackgroundPaddingMm = double(opts.labelBackgroundPaddingMm);
    opts.pageSizeInches = double(opts.pageSizeInches(:)');
    opts.showFigures = logical(opts.showFigures);
    opts.saveFigures = logical(opts.saveFigures);
    opts.verbose = logical(opts.verbose);
end

function names = inputParameterNames()
    names = {'outputFile', 'autoOutputFile', 'titleText', 'labelMode', ...
        'footprintSource', 'skinCacheFile', 'footprintMeshStage', ...
        'searchRoot', 'outputFolder', 'filePickerTitle', ...
        'electrodeRadiusMm', 'labelBackgroundAlpha', ...
        'labelBackgroundPaddingMm', 'pageSizeInches', 'showFigures', ...
        'saveFigures', 'verbose'};
end

function tf = isNameValueKey(value, parameterNames)
    tf = (ischar(value) || isstring(value)) && ...
        any(strcmpi(char(value), parameterNames));
end

function tf = isBoolLike(x)
    tf = (islogical(x) || isnumeric(x)) && isscalar(x);
end

function [layout, sourceInfo] = readLayout(layoutIn, opts)
    sourceInfo = emptySourceInfo();
    if isempty(layoutIn)
        fileName = pickLayoutFile(opts);
        sourceInfo.mode = 'filePicker';
        sourceInfo.picked = true;
        [layout, sourceInfo] = readLayoutFile(fileName, sourceInfo);
        return;
    end
    if isstruct(layoutIn)
        if isfield(layoutIn, 'expandedLayout') && ~isempty(layoutIn.expandedLayout)
            layout = layoutIn.expandedLayout;
        else
            layout = layoutIn;
        end
        sourceInfo.mode = 'struct';
        sourceInfo.file = sourceFileFromLayout(layout);
        return;
    end
    if ~(ischar(layoutIn) || isstring(layoutIn))
        error('acsMakeCapLayoutPrintout:BadLayoutInput', ...
            'layoutIn must be empty, a struct, MAT file, or cap-design tag.');
    end
    rawInput = char(layoutIn);
    fileName = expandUserPath(rawInput);
    if exist(fileName, 'file') == 2
        sourceInfo.mode = 'file';
        [layout, sourceInfo] = readLayoutFile(fileName, sourceInfo);
        return;
    end

    if endsWith(lower(fileName), '.mat') || looksLikeFilePath(fileName)
        error('acsMakeCapLayoutPrintout:MissingLayoutFile', ...
            'Layout file not found: %s', fileName);
    end

    sourceInfo.mode = 'tag';
    sourceInfo.tag = rawInput;
    fileName = findLayoutFileForTag(rawInput, opts);
    [layout, sourceInfo] = readLayoutFile(fileName, sourceInfo);
end

function sourceInfo = emptySourceInfo()
    sourceInfo = struct('mode', '', 'file', '', 'variableName', '', ...
        'tag', '', 'picked', false);
end

function tf = looksLikeFilePath(value)
    value = char(value);
    tf = contains(value, '/') || contains(value, '\') || ...
        ~isempty(regexp(value, '^[A-Za-z]:', 'once'));
end

function fileName = pickLayoutFile(opts)
    if ~usejava('desktop')
        error('acsMakeCapLayoutPrintout:NoDesktopPicker', ...
            ['No layout input was provided and MATLAB desktop file picking ', ...
             'is not available. Provide a MAT report path or cap-design tag.']);
    end
    startDir = defaultSearchRoot(opts);
    [filePart, folder] = uigetfile( ...
        {'*.mat', 'Cap layout/manufacturing MAT products (*.mat)'; ...
         '*.*', 'All files (*.*)'}, ...
        opts.filePickerTitle, startDir);
    if isequal(filePart, 0)
        error('acsMakeCapLayoutPrintout:FilePickerCancelled', ...
            'Cap layout printout file selection was cancelled.');
    end
    fileName = fullfile(folder, filePart);
end

function [layout, sourceInfo] = readLayoutFile(fileName, sourceInfo)
    fileName = expandUserPath(char(fileName));
    if exist(fileName, 'file') ~= 2
        error('acsMakeCapLayoutPrintout:MissingLayoutFile', ...
            'Layout file not found: %s', fileName);
    end
    S = load(fileName);
    [layout, variableName] = firstStruct(S);
    sourceInfo.file = fileName;
    sourceInfo.variableName = variableName;
end

function [S, variableName] = firstStruct(raw)
    preferred = {'out', 'outForSave', 'outToSave', 'outSaved', ...
        'layout', 'combinedLayout', 'manufacturing', 'fitCheckLayout'};
    for i = 1:numel(preferred)
        if isfield(raw, preferred{i})
            S = canonicalLayoutCandidate(raw.(preferred{i}));
            if ~isempty(S)
                variableName = preferred{i};
                return;
            end
        end
    end
    names = fieldnames(raw);
    for i = 1:numel(names)
        S = canonicalLayoutCandidate(raw.(names{i}));
        if ~isempty(S)
            variableName = names{i};
            return;
        end
    end
    error('acsMakeCapLayoutPrintout:NoStructInFile', ...
        ['MAT file does not contain a readable layout struct. Expected ', ...
         'names/layoutCoordinatesMm or an expandedLayout with those fields.']);
end

function layout = canonicalLayoutCandidate(value)
    layout = [];
    if ~isstruct(value) || isempty(value)
        return;
    end
    if numel(value) > 1
        value = value(1);
    end
    if isfield(value, 'expandedLayout') && isstruct(value.expandedLayout) && ...
            looksLikeLayout(value.expandedLayout)
        layout = value.expandedLayout;
        return;
    end
    if looksLikeLayout(value)
        layout = value;
    end
end

function tf = looksLikeLayout(S)
    tf = isstruct(S) && ...
        ((isfield(S, 'layoutCoordinatesMm') && ~isempty(S.layoutCoordinatesMm)) || ...
         (isfield(S, 'expandedLayoutCoordinatesMm') && ~isempty(S.expandedLayoutCoordinatesMm))) && ...
        ((isfield(S, 'names') && ~isempty(S.names)) || ...
         (isfield(S, 'expandedNames') && ~isempty(S.expandedNames)));
end

function fileName = findLayoutFileForTag(tag, opts)
    roots = candidateSearchRoots(opts);
    [~, tagStem, tagExt] = fileparts(char(tag));
    if isempty(tagStem)
        tagStem = char(tag);
    end
    if ~isempty(tagExt)
        tagStem = [tagStem tagExt];
    end
    patterns = { ...
        sprintf('*%s*tesEeg*customLocations*_report.mat', tagStem), ...
        sprintf('*%s*manufacturing_report.mat', tagStem), ...
        sprintf('*%s*customLocations*_report.mat', tagStem), ...
        sprintf('*%s*_report.mat', tagStem), ...
        sprintf('*%s*.mat', tagStem)};

    triedRoots = strjoin(roots, newline);
    for pIdx = 1:numel(patterns)
        for rIdx = 1:numel(roots)
            files = dir(fullfile(roots{rIdx}, '**', patterns{pIdx}));
            files = files(~[files.isdir]);
            for fIdx = 1:numel(files)
                candidate = fullfile(files(fIdx).folder, files(fIdx).name);
                try
                    sourceInfo = emptySourceInfo();
                    readLayoutFile(candidate, sourceInfo);
                    fileName = candidate;
                    return;
                catch
                end
            end
        end
    end

    error('acsMakeCapLayoutPrintout:TagNotFound', ...
        ['Could not find a readable cap layout/manufacturing report ', ...
         'matching tag "%s". Searched:\n%s'], tag, triedRoots);
end

function roots = candidateSearchRoots(opts)
    roots = {};
    if ~isempty(opts.searchRoot)
        roots{end + 1} = opts.searchRoot; %#ok<AGROW>
    end
    try
        if exist('acsPaths', 'file') == 2
            P = acsPaths();
            if isfield(P, 'outputRoot') && ~isempty(P.outputRoot)
                roots{end + 1} = P.outputRoot; %#ok<AGROW>
            end
            if isfield(P, 'subjectOutputRoot') && ~isempty(P.subjectOutputRoot)
                roots{end + 1} = P.subjectOutputRoot; %#ok<AGROW>
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
        key = lower(char(java.io.File(root).getCanonicalPath()));
        if any(strcmp(key, seen))
            continue;
        end
        seen{end + 1} = key; %#ok<AGROW>
        roots{end + 1} = root; %#ok<AGROW>
    end
end

function fileName = sourceFileFromLayout(layout)
    fileName = '';
    fields = {'reportMat', 'customLocationsFile', 'outputFile'};
    for i = 1:numel(fields)
        if isfield(layout, fields{i}) && ~isempty(layout.(fields{i}))
            candidate = expandUserPath(char(layout.(fields{i})));
            if exist(candidate, 'file') == 2
                fileName = candidate;
                return;
            end
        end
    end
end

function outputFile = resolveOutputFile(outputFile, layout, sourceInfo, opts)
    outputFile = expandUserPath(char(outputFile));
    if ~isempty(outputFile) || ~opts.autoOutputFile
        return;
    end
    sourceFile = sourceInfo.file;
    if isempty(sourceFile)
        sourceFile = sourceFileFromLayout(layout);
    end
    if ~isempty(opts.outputFolder)
        folder = opts.outputFolder;
    elseif ~isempty(sourceFile)
        folder = fileparts(sourceFile);
    else
        folder = pwd;
    end
    if ~isempty(sourceFile)
        [~, stem] = fileparts(sourceFile);
    elseif isfield(layout, 'manufacturingTag') && ~isempty(layout.manufacturingTag)
        stem = char(layout.manufacturingTag);
    else
        stem = 'capLayout';
    end
    stem = regexprep(stem, '_report$', '');
    stem = regexprep(stem, '_manufacturing$', '');
    outputFile = fullfile(folder, [stem '_layoutPrintout.pdf']);
end

function [coords, names] = layoutCoordinatesAndNames(layout)
    if isfield(layout, 'layoutCoordinatesMm') && ~isempty(layout.layoutCoordinatesMm)
        coords = double(layout.layoutCoordinatesMm);
    elseif isfield(layout, 'expandedLayoutCoordinatesMm') && ~isempty(layout.expandedLayoutCoordinatesMm)
        coords = double(layout.expandedLayoutCoordinatesMm);
    else
        error('acsMakeCapLayoutPrintout:MissingCoordinates', ...
            'Layout does not report layoutCoordinatesMm.');
    end
    if size(coords, 2) < 3
        error('acsMakeCapLayoutPrintout:BadCoordinates', ...
            'layoutCoordinatesMm must be N x 3.');
    end
    coords = coords(:, 1:3);

    if isfield(layout, 'names') && ~isempty(layout.names)
        names = cellstr(layout.names(:));
    elseif isfield(layout, 'expandedNames') && ~isempty(layout.expandedNames)
        names = cellstr(layout.expandedNames(:));
    else
        names = arrayfun(@(i) sprintf('E%d', i), 1:size(coords, 1), ...
            'UniformOutput', false)';
    end
    if numel(names) ~= size(coords, 1)
        names = arrayfun(@(i) sprintf('E%d', i), 1:size(coords, 1), ...
            'UniformOutput', false)';
    end
end

function labels = displayLabels(names)
    labels = cellstr(names(:));
    for i = 1:numel(labels)
        label = regexprep(labels{i}, '^customTES', 'tES', 'ignorecase');
        label = regexprep(label, '^customEEG', 'EEG', 'ignorecase');
        label = regexprep(label, '^tes', 'tES', 'ignorecase');
        label = regexprep(label, '^eeg', 'EEG', 'ignorecase');
        labels{i} = label;
    end
end

function roles = layoutSiteRoles(layout, names)
    n = numel(names);
    roles = repmat({'electrode'}, n, 1);
    if isfield(layout, 'siteRoles') && ~isempty(layout.siteRoles)
        candidate = normalizeRoleCell(layout.siteRoles);
        if numel(candidate) == n
            roles = candidate(:);
            return;
        end
    end
    if isfield(layout, 'tesNames') && ~isempty(layout.tesNames)
        roles = assignRoleByNames(roles, names, layout.tesNames, 'tES');
    end
    if isfield(layout, 'eegNames') && ~isempty(layout.eegNames)
        roles = assignRoleByNames(roles, names, layout.eegNames, 'EEG');
    end
    for i = 1:n
        lowerName = lower(char(names{i}));
        if contains(lowerName, 'tes')
            roles{i} = 'tES';
        elseif contains(lowerName, 'eeg')
            roles{i} = 'EEG';
        end
    end
end

function roles = assignRoleByNames(roles, allNames, queryNames, role)
    queryNames = cellstr(queryNames(:));
    for i = 1:numel(queryNames)
        idx = find(strcmpi(queryNames{i}, allNames), 1);
        if ~isempty(idx)
            roles{idx} = role;
        end
    end
end

function roles = normalizeRoleCell(rolesIn)
    if isstring(rolesIn)
        roles = cellstr(rolesIn(:));
    elseif ischar(rolesIn)
        roles = {rolesIn};
    elseif iscell(rolesIn)
        roles = cellfun(@char, rolesIn(:), 'UniformOutput', false);
    else
        roles = {};
    end
    for i = 1:numel(roles)
        if strcmpi(roles{i}, 'tes')
            roles{i} = 'tES';
        elseif strcmpi(roles{i}, 'eeg')
            roles{i} = 'EEG';
        else
            roles{i} = 'electrode';
        end
    end
end

function [footprintXY, info] = resolveFootprint(layout, coords, opts)
    info = struct('source', '', 'skinCacheFile', '');
    footprintXY = zeros(0, 2);

    skinCacheFile = opts.skinCacheFile;
    if isempty(skinCacheFile)
        skinCacheFile = skinCacheFromLayout(layout);
    end
    if any(strcmpi(opts.footprintSource, {'auto', 'skinCache'})) && ...
            ~isempty(skinCacheFile) && exist(skinCacheFile, 'file') == 2
        try
            [TRfootprint, meshInfo] = readSkinCacheFootprintMesh( ...
                skinCacheFile, opts.footprintMeshStage);
            if ~isempty(TRfootprint)
                footprintXY = footprintFromPoints(TRfootprint.Points(:, 1:2), 0.85);
                info.source = meshInfo.source;
                info.skinCacheFile = skinCacheFile;
                info.meshStage = meshInfo.meshStage;
                return;
            end
        catch ME
            if strcmpi(opts.footprintSource, 'skinCache')
                rethrow(ME);
            end
        end
    end
    if strcmpi(opts.footprintSource, 'skinCache')
        error('acsMakeCapLayoutPrintout:MissingSkinFootprint', ...
            'Could not load a skin-cache footprint.');
    end

    footprintXY = footprintFromPoints(coords(:, 1:2), 0.60);
    info.source = 'layout coordinate hull';
end

function [TR, info] = readSkinCacheFootprintMesh(skinCacheFile, meshStage)
    raw = load(skinCacheFile);
    info = struct('source', '', 'meshStage', '');
    TR = [];

    switch lower(char(meshStage))
        case 'fullhead'
            [TR, info] = fullHeadMeshFromCache(raw, skinCacheFile);
        case 'cap'
            [TR, info] = capMeshFromCache(raw, skinCacheFile);
        case 'auto'
            try
                [TR, info] = fullHeadMeshFromCache(raw, skinCacheFile);
            catch
                [TR, info] = capMeshFromCache(raw, skinCacheFile);
            end
        otherwise
            error('acsMakeCapLayoutPrintout:BadFootprintMeshStage', ...
                'Unknown footprintMeshStage "%s".', meshStage);
    end
end

function [TR, info] = fullHeadMeshFromCache(raw, skinCacheFile)
    if isfield(raw, 'TRfiducialHead') && ~isempty(raw.TRfiducialHead)
        TR = ensureTri(raw.TRfiducialHead);
        info = struct('source', 'skin cache full-head TRfiducialHead footprint', ...
            'meshStage', 'fullHead');
        return;
    end
    if isfield(raw, 'meta') && isstruct(raw.meta) && ...
            isfield(raw.meta, 'fiducialHead') && ...
            isstruct(raw.meta.fiducialHead) && ...
            isfield(raw.meta.fiducialHead, 'TR') && ...
            ~isempty(raw.meta.fiducialHead.TR)
        TR = ensureTri(raw.meta.fiducialHead.TR);
        info = struct('source', 'skin cache full-head meta.fiducialHead.TR footprint', ...
            'meshStage', 'fullHead');
        return;
    end
    if isfield(raw, 'TRstableHead') && ~isempty(raw.TRstableHead) && ...
            isfield(raw, 'meta') && isstruct(raw.meta)
        TRstable = ensureTri(raw.TRstableHead);
        pointsPrint = stableWorldToPrintMm(TRstable.Points, raw.meta);
        TR = triangulation(TRstable.ConnectivityList, pointsPrint);
        info = struct('source', 'skin cache full-head TRstableHead footprint', ...
            'meshStage', 'fullHead');
        return;
    end
    error('acsMakeCapLayoutPrintout:MissingFullHeadFootprint', ...
        ['Skin cache does not contain a full-head mesh: %s\n', ...
         'Expected TRfiducialHead or TRstableHead.'], skinCacheFile);
end

function [TR, info] = capMeshFromCache(raw, skinCacheFile)
    if isfield(raw, 'TRskin') && ~isempty(raw.TRskin)
        TR = ensureTri(raw.TRskin);
        info = struct('source', 'skin cache cropped-cap TRskin footprint', ...
            'meshStage', 'cap');
        return;
    end
    error('acsMakeCapLayoutPrintout:MissingCapFootprint', ...
        'Skin cache does not contain TRskin: %s', skinCacheFile);
end

function fileName = skinCacheFromLayout(layout)
    candidates = {};
    if isfield(layout, 'skinSource') && isstruct(layout.skinSource) && ...
            isfield(layout.skinSource, 'cacheFile') && ~isempty(layout.skinSource.cacheFile)
        candidates{end + 1} = layout.skinSource.cacheFile; %#ok<AGROW>
    end
    if isfield(layout, 'manufacturingSurface') && isstruct(layout.manufacturingSurface)
        if isfield(layout.manufacturingSurface, 'sourceCacheFile') && ...
                ~isempty(layout.manufacturingSurface.sourceCacheFile)
            candidates{end + 1} = layout.manufacturingSurface.sourceCacheFile; %#ok<AGROW>
        end
        if isfield(layout.manufacturingSurface, 'cacheFile') && ...
                ~isempty(layout.manufacturingSurface.cacheFile)
            candidates{end + 1} = layout.manufacturingSurface.cacheFile; %#ok<AGROW>
        end
    end
    if isfield(layout, 'options') && isstruct(layout.options)
        if isfield(layout.options, 'skinCacheFile') && ~isempty(layout.options.skinCacheFile)
            candidates{end + 1} = layout.options.skinCacheFile; %#ok<AGROW>
        end
        if isfield(layout.options, 'skinSourceCacheFile') && ...
                ~isempty(layout.options.skinSourceCacheFile)
            candidates{end + 1} = layout.options.skinSourceCacheFile; %#ok<AGROW>
        end
    end
    if isfield(layout, 'skin') && isstruct(layout.skin) && ...
            isfield(layout.skin, 'cacheFile') && ~isempty(layout.skin.cacheFile)
        candidates{end + 1} = layout.skin.cacheFile; %#ok<AGROW>
    end
    if isfield(layout, 'layout') && isstruct(layout.layout) && ...
            isfield(layout.layout, 'skin') && isstruct(layout.layout.skin) && ...
            isfield(layout.layout.skin, 'cacheFile') && ~isempty(layout.layout.skin.cacheFile)
        candidates{end + 1} = layout.layout.skin.cacheFile; %#ok<AGROW>
    end
    if isfield(layout, 'eegOnlyLayout') && isstruct(layout.eegOnlyLayout) && ...
            isfield(layout.eegOnlyLayout, 'layout') && ...
            isstruct(layout.eegOnlyLayout.layout) && ...
            isfield(layout.eegOnlyLayout.layout, 'skin') && ...
            isstruct(layout.eegOnlyLayout.layout.skin) && ...
            isfield(layout.eegOnlyLayout.layout.skin, 'cacheFile') && ...
            ~isempty(layout.eegOnlyLayout.layout.skin.cacheFile)
        candidates{end + 1} = layout.eegOnlyLayout.layout.skin.cacheFile; %#ok<AGROW>
    end
    if isfield(layout, 'assemblyOptions') && isstruct(layout.assemblyOptions) && ...
            isfield(layout.assemblyOptions, 'eegTargetOptions') && ...
            isstruct(layout.assemblyOptions.eegTargetOptions) && ...
            isfield(layout.assemblyOptions.eegTargetOptions, 'skinCacheFile') && ...
            ~isempty(layout.assemblyOptions.eegTargetOptions.skinCacheFile)
        candidates{end + 1} = layout.assemblyOptions.eegTargetOptions.skinCacheFile; %#ok<AGROW>
    end
    if isfield(layout, 'surfaceSource') && isstruct(layout.surfaceSource) && ...
            isfield(layout.surfaceSource, 'cacheFile') && ~isempty(layout.surfaceSource.cacheFile)
        candidates{end + 1} = layout.surfaceSource.cacheFile; %#ok<AGROW>
    end
    if isfield(layout, 'targetOptions') && isstruct(layout.targetOptions) && ...
            isfield(layout.targetOptions, 'skinCacheFile') && ~isempty(layout.targetOptions.skinCacheFile)
        candidates{end + 1} = layout.targetOptions.skinCacheFile; %#ok<AGROW>
    end

    fileName = '';
    for i = 1:numel(candidates)
        candidate = expandUserPath(char(candidates{i}));
        if ~isempty(candidate) && exist(candidate, 'file') == 2
            fileName = candidate;
            return;
        end
    end

    if ~isempty(candidates)
        fileName = expandUserPath(char(candidates{1}));
    end
end

function TR = ensureTri(value)
    if isa(value, 'triangulation')
        TR = value;
    elseif isstruct(value) && isfield(value, 'ConnectivityList') && isfield(value, 'Points')
        TR = triangulation(double(value.ConnectivityList), double(value.Points));
    else
        error('acsMakeCapLayoutPrintout:BadTriangulation', ...
            'Expected a triangulation or struct with Points and ConnectivityList.');
    end
end

function pointsPrint = stableWorldToPrintMm(pointsStable, meta)
    requireCapMakerMeta(meta);
    finalWorldMm = (double(meta.align.R) * double(pointsStable)')';
    pointsPrint = applyAffineToPoints(meta.print.T_world2print, finalWorldMm);
end

function requireCapMakerMeta(meta)
    ok = isstruct(meta) && isfield(meta, 'print') && ...
        isfield(meta.print, 'T_world2print') && ...
        isfield(meta, 'align') && isfield(meta.align, 'R');
    if ~ok
        error('acsMakeCapLayoutPrintout:MissingCapMakerMeta', ...
            ['Full-head TRstableHead footprints require skin cache metadata ', ...
             'with print.T_world2print and align.R.']);
    end
end

function pointsOut = applyAffineToPoints(M, pointsIn)
    pointsHom = [double(pointsIn), ones(size(pointsIn, 1), 1)];
    pointsHom = (double(M) * pointsHom')';
    pointsOut = pointsHom(:, 1:3);
end

function xy = footprintFromPoints(pointsXY, shrinkFactor)
    pointsXY = double(pointsXY);
    pointsXY = pointsXY(all(isfinite(pointsXY), 2), :);
    if size(pointsXY, 1) < 3
        xy = pointsXY;
        return;
    end
    try
        k = boundary(pointsXY(:, 1), pointsXY(:, 2), shrinkFactor);
    catch
        k = convhull(pointsXY(:, 1), pointsXY(:, 2));
    end
    xy = pointsXY(k, :);
end

function fig = makeFigure(footprintXY, electrodeXY, labels, roles, opts, figVisible)
    fig = figure('Name', 'Cap layout printout', ...
        'NumberTitle', 'off', 'Color', 'w', 'Visible', figVisible, ...
        'Units', 'inches', 'Position', [1 1 opts.pageSizeInches], ...
        'PaperUnits', 'inches', 'PaperPosition', [0 0 opts.pageSizeInches], ...
        'PaperSize', opts.pageSizeInches);
    ax = axes(fig, 'Position', [0.08 0.08 0.84 0.84]); %#ok<LAXES>
    hold(ax, 'on');
    if size(footprintXY, 1) >= 2
        plot(ax, footprintXY(:, 1), footprintXY(:, 2), 'k-', 'LineWidth', 1.2);
    end
    r = opts.electrodeRadiusMm;
    textHandles = gobjects(size(electrodeXY, 1), 1);
    for i = 1:size(electrodeXY, 1)
        markerXY = markerOutline(electrodeXY(i, :), r, roles{i});
        plot(ax, markerXY(:, 1), markerXY(:, 2), 'k-', ...
            'LineWidth', markerLineWidth(roles{i}));
        textHandles(i) = text(ax, electrodeXY(i, 1), electrodeXY(i, 2), labels{i}, ...
            'HorizontalAlignment', 'center', ...
            'VerticalAlignment', 'middle', ...
            'FontWeight', 'bold', ...
            'FontSize', 8, ...
            'Interpreter', 'none', ...
            'Color', 'k');
    end
    axis(ax, 'equal');
    axis(ax, 'off');
    title(ax, opts.titleText, 'Interpreter', 'none', ...
        'FontWeight', 'bold', 'FontSize', 13);
    addLabelBackings(ax, textHandles, opts);
end

function xy = markerOutline(centerXY, radiusMm, role)
    switch lower(char(role))
        case 'tes'
            theta = pi / 6 + (0:6)' * 2 * pi / 6;
        case 'eeg'
            theta = linspace(0, 2*pi, 60)';
        otherwise
            theta = pi / 4 + (0:4)' * 2 * pi / 4;
    end
    xy = double(centerXY(:)') + radiusMm * [cos(theta), sin(theta)];
end

function width = markerLineWidth(role)
    if strcmpi(role, 'tES')
        width = 1.25;
    else
        width = 1.0;
    end
end

function addLabelBackings(ax, textHandles, opts)
    if opts.labelBackgroundAlpha <= 0
        return;
    end
    drawnow;
    pad = opts.labelBackgroundPaddingMm;
    backingHandles = gobjects(numel(textHandles), 1);
    for i = 1:numel(textHandles)
        if ~isgraphics(textHandles(i))
            continue;
        end
        extent = get(textHandles(i), 'Extent');
        x = [extent(1) - pad, extent(1) + extent(3) + pad, ...
            extent(1) + extent(3) + pad, extent(1) - pad];
        y = [extent(2) - pad, extent(2) - pad, ...
            extent(2) + extent(4) + pad, extent(2) + extent(4) + pad];
        backingHandles(i) = patch(ax, x, y, 'w', ...
            'EdgeColor', 'none', ...
            'FaceAlpha', opts.labelBackgroundAlpha);
    end
    for i = 1:numel(textHandles)
        if isgraphics(textHandles(i))
            try
                uistack(textHandles(i), 'top');
            catch
            end
        end
    end
end

function saveFigure(fig, fileName)
    [folder, ~, ext] = fileparts(fileName);
    ensureDir(folder);
    ext = lower(ext);
    if isempty(ext)
        fileName = [fileName '.pdf'];
        ext = '.pdf';
    end
    switch ext
        case {'.pdf', '.svg'}
            exportgraphics(fig, fileName, 'ContentType', 'vector');
        case {'.png', '.tif', '.tiff', '.jpg', '.jpeg'}
            exportgraphics(fig, fileName, 'Resolution', 300);
        otherwise
            saveas(fig, fileName);
    end
end

function ensureDir(pathIn)
    if ~isempty(pathIn) && exist(pathIn, 'dir') ~= 7
        mkdir(pathIn);
    end
end

function pathOut = expandUserPath(pathIn)
    pathOut = char(pathIn);
    if isempty(pathOut)
        return;
    end
    if startsWith(pathOut, '~')
        homeDir = char(java.lang.System.getProperty('user.home'));
        if numel(pathOut) == 1
            pathOut = homeDir;
        elseif any(pathOut(2) == ['/' filesep])
            pathOut = fullfile(homeDir, pathOut(3:end));
        end
    end
end
