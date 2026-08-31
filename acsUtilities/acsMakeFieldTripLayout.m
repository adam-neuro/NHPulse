function out = acsMakeFieldTripLayout(layoutIn, varargin)
% ACSMAKEFIELDTRIPLAYOUT Convert an NHPulse cap layout to a FieldTrip layout.
%
% out = acsMakeFieldTripLayout(layout)
% out = acsMakeFieldTripLayout(layoutMatFile)
% out = acsMakeFieldTripLayout(capDesignTag)
%
% Returns out.layout, a FieldTrip-compatible 2-D layout struct with fields:
%   pos, width, height, label, outline, mask
%
% The default behavior keeps EEG channels when they can be identified from
% siteRoles, eegNames, or channel names; otherwise all channels are included.
% Labels are cleaned from customEEG1 -> EEG1 by default.
%
% Name-value options:
%   includeRoles      : 'autoEeg', 'all', 'EEG', 'tES', or cellstr ['autoEeg']
%   labelMode         : 'stripCustom' or 'raw' ['stripCustom']
%   projectionPlane   : 'xy', 'xz', or 'yz' ['xy']
%   scaleMode         : 'unit' or 'mm' ['unit']
%   rotationDeg       : rotation applied after projection [0]
%   flipX             : flip plotted X after projection [false]
%   flipY             : flip plotted Y after projection [false]
%   outlineSource     : 'auto', 'skinCache', 'layout', or 'none' ['auto']
%   skinCacheFile     : explicit capMaker skin cache ['']
%   outlineMeshStage  : 'cap', 'fullHead', or 'auto' ['cap']
%   outlinePadding    : outline/mask expansion about center [1.03]
%   channelWidth      : layout.width value; [] chooses automatically [[]]
%   channelHeight     : layout.height value; [] chooses automatically [[]]
%   outputMatFile     : .mat file for layout/out; [] chooses automatically [[]]
%   outputLayFile     : FieldTrip .lay text file; [] chooses automatically [[]]
%   saveMat           : write outputMatFile [true]
%   saveLay           : write outputLayFile [true]
%   outputFolder      : override automatic output folder ['']
%   searchRoot        : folder to search for capDesignTag ['']
%   showFigure        : show QC plot [true]
%   saveFigure        : save QC PNG when outputMatFile is written [false]
%   verbose           : print summary [true]
%
% Example:
%   ftLayout = acsMakeFieldTripLayout('M2107_tes8_eeg8_rhdlpfc1_phoneWarp');
%   cfg = [];
%   cfg.layout = ftLayout.layout;
%   ft_topoplotER(cfg, timelock);

    parameterNames = inputParameterNames();
    if nargin < 1
        layoutIn = [];
    elseif isNameValueKey(layoutIn, parameterNames)
        varargin = [{layoutIn}, varargin];
        layoutIn = [];
    end

    opts = parseInputs(varargin{:});
    [capLayout, sourceInfo] = readLayout(layoutIn, opts);
    [allCoordsMm, allNames] = layoutCoordinatesAndNames(capLayout);
    allRoles = layoutSiteRoles(capLayout, allNames);
    keepRows = selectRowsForFieldTrip(allRoles, allNames, opts);

    coordsMm = allCoordsMm(keepRows, :);
    names = allNames(keepRows);
    roles = allRoles(keepRows);
    labels = displayLabels(names, opts.labelMode);

    xyRaw = projectCoordinates(coordsMm, opts.projectionPlane);
    outlineRaw = resolveOutlineRaw(capLayout, allCoordsMm, opts);
    [xy, outlineXY, transformInfo] = transformLayout2d(xyRaw, outlineRaw, opts);

    [width, height] = resolveChannelSize(xy, opts);
    ftLayout = struct();
    ftLayout.pos = xy;
    ftLayout.width = repmat(width, numel(labels), 1);
    ftLayout.height = repmat(height, numel(labels), 1);
    ftLayout.label = labels(:);
    ftLayout.outline = {};
    ftLayout.mask = {};
    if ~isempty(outlineXY)
        ftLayout.outline = {outlineXY};
        ftLayout.mask = {outlineXY};
    end
    ftLayout.cfg = struct();
    ftLayout.cfg.nhpulse = struct( ...
        'createdOn', char(datetime('now')), ...
        'sourceInfo', sourceInfo, ...
        'originalNames', {names(:)}, ...
        'siteRoles', {roles(:)}, ...
        'coordinatesMm', coordsMm, ...
        'projectionPlane', opts.projectionPlane, ...
        'transformInfo', transformInfo);

    [outputMatFile, outputLayFile] = resolveOutputFiles(opts, sourceInfo, capLayout);
    if ~isempty(outputMatFile)
        ensureDir(fileparts(outputMatFile));
        fieldtripLayout = ftLayout; %#ok<NASGU>
        outForSave = struct();
        outForSave.type = 'fieldtripLayout';
        outForSave.layout = ftLayout;
        outForSave.sourceInfo = sourceInfo;
        outForSave.options = opts;
        outForSave.coordinatesMm = coordsMm;
        outForSave.originalNames = names(:);
        outForSave.labels = labels(:);
        outForSave.siteRoles = roles(:);
        save(outputMatFile, 'fieldtripLayout', 'outForSave');
    end
    if ~isempty(outputLayFile)
        ensureDir(fileparts(outputLayFile));
        writeLayFile(outputLayFile, ftLayout);
    end

    fig = [];
    qcFigure = '';
    if opts.showFigure || opts.saveFigure
        figVisible = 'off';
        if opts.showFigure
            figVisible = 'on';
        end
        fig = makeQcFigure(ftLayout, roles, opts, figVisible);
        if opts.saveFigure && ~isempty(outputMatFile)
            [folder, stem] = fileparts(outputMatFile);
            qcFigure = fullfile(folder, [stem '_qc.png']);
            saveas(fig, qcFigure);
        end
        if ~opts.showFigure && isgraphics(fig)
            close(fig);
            fig = [];
        end
    end

    out = struct();
    out.type = 'fieldtripLayout';
    out.createdOn = char(datetime('now'));
    out.layout = ftLayout;
    out.labels = labels(:);
    out.originalNames = names(:);
    out.siteRoles = roles(:);
    out.coordinatesMm = coordsMm;
    out.outputMatFile = outputMatFile;
    out.outputLayFile = outputLayFile;
    out.qcFigure = qcFigure;
    out.sourceInfo = sourceInfo;
    out.options = opts;
    out.figure = fig;

    if opts.verbose
        fprintf('\nFieldTrip layout export\n');
        fprintf('  channels: %d / %d\n', numel(labels), numel(allNames));
        fprintf('  includeRoles: %s\n', rolesDescription(opts.includeRoles));
        fprintf('  labelMode: %s\n', opts.labelMode);
        fprintf('  projection: %s, scale: %s\n', opts.projectionPlane, opts.scaleMode);
        if ~isempty(outputMatFile)
            fprintf('  MAT: %s\n', outputMatFile);
        end
        if ~isempty(outputLayFile)
            fprintf('  LAY: %s\n', outputLayFile);
        end
    end
end

function opts = parseInputs(varargin)
    p = inputParser;
    p.FunctionName = 'acsMakeFieldTripLayout';
    addParameter(p, 'includeRoles', 'autoEeg', ...
        @(x) ischar(x) || isstring(x) || iscellstr(x));
    addParameter(p, 'labelMode', 'stripCustom', @(x) ischar(x) || isstring(x));
    addParameter(p, 'projectionPlane', 'xy', @(x) ischar(x) || isstring(x));
    addParameter(p, 'scaleMode', 'unit', @(x) ischar(x) || isstring(x));
    addParameter(p, 'rotationDeg', 0, @isFiniteScalar);
    addParameter(p, 'flipX', false, @isBoolLike);
    addParameter(p, 'flipY', false, @isBoolLike);
    addParameter(p, 'outlineSource', 'auto', @(x) ischar(x) || isstring(x));
    addParameter(p, 'skinCacheFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'outlineMeshStage', 'cap', @(x) ischar(x) || isstring(x));
    addParameter(p, 'outlinePadding', 1.03, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x > 0);
    addParameter(p, 'channelWidth', [], @(x) isempty(x) || isPositiveScalar(x));
    addParameter(p, 'channelHeight', [], @(x) isempty(x) || isPositiveScalar(x));
    addParameter(p, 'outputMatFile', [], ...
        @(x) isempty(x) || ischar(x) || isstring(x));
    addParameter(p, 'outputLayFile', [], ...
        @(x) isempty(x) || ischar(x) || isstring(x));
    addParameter(p, 'saveMat', true, @isBoolLike);
    addParameter(p, 'saveLay', true, @isBoolLike);
    addParameter(p, 'outputFolder', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'searchRoot', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'filePickerTitle', 'Select NHPulse layout MAT or custom-locations file', ...
        @(x) ischar(x) || isstring(x));
    addParameter(p, 'showFigure', true, @isBoolLike);
    addParameter(p, 'saveFigure', false, @isBoolLike);
    addParameter(p, 'verbose', true, @isBoolLike);
    parse(p, varargin{:});

    opts = p.Results;
    opts.includeRoles = normalizeIncludeRoles(opts.includeRoles);
    opts.labelMode = normalizeLabelMode(opts.labelMode);
    opts.projectionPlane = normalizeProjectionPlane(opts.projectionPlane);
    opts.scaleMode = normalizeScaleMode(opts.scaleMode);
    opts.rotationDeg = double(opts.rotationDeg);
    opts.flipX = logical(opts.flipX);
    opts.flipY = logical(opts.flipY);
    opts.outlineSource = normalizeOutlineSource(opts.outlineSource);
    opts.skinCacheFile = expandUserPath(char(opts.skinCacheFile));
    opts.outlineMeshStage = normalizeOutlineMeshStage(opts.outlineMeshStage);
    opts.outlinePadding = double(opts.outlinePadding);
    if ~isempty(opts.channelWidth)
        opts.channelWidth = double(opts.channelWidth);
    end
    if ~isempty(opts.channelHeight)
        opts.channelHeight = double(opts.channelHeight);
    end
    opts.outputMatFile = normalizeOptionalPath(opts.outputMatFile);
    opts.outputLayFile = normalizeOptionalPath(opts.outputLayFile);
    opts.saveMat = logical(opts.saveMat);
    opts.saveLay = logical(opts.saveLay);
    opts.outputFolder = expandUserPath(char(opts.outputFolder));
    opts.searchRoot = expandUserPath(char(opts.searchRoot));
    opts.filePickerTitle = char(opts.filePickerTitle);
    opts.showFigure = logical(opts.showFigure);
    opts.saveFigure = logical(opts.saveFigure);
    opts.verbose = logical(opts.verbose);
end

function names = inputParameterNames()
    names = {'includeRoles', 'labelMode', 'projectionPlane', 'scaleMode', ...
        'rotationDeg', 'flipX', 'flipY', 'outlineSource', 'skinCacheFile', ...
        'outlineMeshStage', 'outlinePadding', 'channelWidth', ...
        'channelHeight', 'outputMatFile', 'outputLayFile', 'saveMat', ...
        'saveLay', 'outputFolder', 'searchRoot', 'filePickerTitle', ...
        'showFigure', 'saveFigure', 'verbose'};
end

function tf = isNameValueKey(value, parameterNames)
    tf = (ischar(value) || isstring(value)) && ...
        any(strcmpi(char(value), parameterNames));
end

function tf = isBoolLike(x)
    tf = (islogical(x) || isnumeric(x)) && isscalar(x);
end

function tf = isFiniteScalar(x)
    tf = isnumeric(x) && isscalar(x) && isfinite(x);
end

function tf = isPositiveScalar(x)
    tf = isnumeric(x) && isscalar(x) && isfinite(x) && x > 0;
end

function value = normalizeOptionalPath(value)
    if isempty(value)
        return;
    end
    value = expandUserPath(char(value));
end

function roles = normalizeIncludeRoles(value)
    if ischar(value) || isstring(value)
        roles = {char(value)};
    else
        roles = cellfun(@char, value(:), 'UniformOutput', false);
    end
    roles = cellfun(@(x) lower(strtrim(x)), roles(:), 'UniformOutput', false);
    valid = {'autoeeg', 'all', 'eeg', 'tes', 'electrode'};
    for i = 1:numel(roles)
        if ~any(strcmp(roles{i}, valid))
            error('acsMakeFieldTripLayout:BadIncludeRoles', ...
                'includeRoles must be autoEeg, all, EEG, tES, or electrode.');
        end
    end
end

function mode = normalizeLabelMode(mode)
    mode = lower(strtrim(char(mode)));
    switch mode
        case {'stripcustom', 'display', 'clean', 'short'}
            mode = 'stripCustom';
        case {'raw', 'original'}
            mode = 'raw';
        otherwise
            error('acsMakeFieldTripLayout:BadLabelMode', ...
                'labelMode must be ''stripCustom'' or ''raw''.');
    end
end

function plane = normalizeProjectionPlane(plane)
    plane = lower(strtrim(char(plane)));
    switch plane
        case {'xy', 'print', 'capmaker', 'top'}
            plane = 'xy';
        case {'xz'}
            plane = 'xz';
        case {'yz'}
            plane = 'yz';
        otherwise
            error('acsMakeFieldTripLayout:BadProjectionPlane', ...
                'projectionPlane must be ''xy'', ''xz'', or ''yz''.');
    end
end

function mode = normalizeScaleMode(mode)
    mode = lower(strtrim(char(mode)));
    switch mode
        case {'unit', 'normalized', 'normalised'}
            mode = 'unit';
        case {'mm', 'millimeter', 'millimeters'}
            mode = 'mm';
        otherwise
            error('acsMakeFieldTripLayout:BadScaleMode', ...
                'scaleMode must be ''unit'' or ''mm''.');
    end
end

function source = normalizeOutlineSource(source)
    source = lower(strtrim(char(source)));
    switch source
        case {'auto', 'skin', 'skincache'}
            if strcmp(source, 'skin') || strcmp(source, 'skincache')
                source = 'skinCache';
            end
        case {'layout', 'electrodes'}
            source = 'layout';
        case {'none', 'off'}
            source = 'none';
        otherwise
            error('acsMakeFieldTripLayout:BadOutlineSource', ...
                'outlineSource must be ''auto'', ''skinCache'', ''layout'', or ''none''.');
    end
end

function stage = normalizeOutlineMeshStage(stage)
    stage = lower(strtrim(char(stage)));
    switch stage
        case {'cap', 'cropped', 'croppedcap'}
            stage = 'cap';
        case {'fullhead', 'full', 'head'}
            stage = 'fullHead';
        case {'auto'}
            stage = 'auto';
        otherwise
            error('acsMakeFieldTripLayout:BadOutlineMeshStage', ...
                'outlineMeshStage must be ''cap'', ''fullHead'', or ''auto''.');
    end
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
        layout = canonicalLayoutCandidate(layoutIn);
        if isempty(layout)
            error('acsMakeFieldTripLayout:BadStructInput', ...
                'Input struct does not look like an NHPulse layout.');
        end
        sourceInfo.mode = 'struct';
        sourceInfo.file = sourceFileFromLayout(layout);
        return;
    end
    if ~(ischar(layoutIn) || isstring(layoutIn))
        error('acsMakeFieldTripLayout:BadInput', ...
            'layoutIn must be empty, a struct, a file, or a cap-design tag.');
    end

    rawInput = char(layoutIn);
    fileName = expandUserPath(rawInput);
    if exist(fileName, 'file') == 2
        sourceInfo.mode = 'file';
        [layout, sourceInfo] = readLayoutFile(fileName, sourceInfo);
        return;
    end
    if endsWith(lower(fileName), '.mat') || looksLikeFilePath(fileName)
        error('acsMakeFieldTripLayout:MissingLayoutFile', ...
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
        error('acsMakeFieldTripLayout:NoDesktopPicker', ...
            ['No layout input was provided and MATLAB desktop file picking ', ...
             'is not available. Provide a MAT report path, custom-locations ', ...
             'file, or cap-design tag.']);
    end
    startDir = defaultSearchRoot(opts);
    [filePart, folder] = uigetfile( ...
        {'*.mat;*customLocations*', 'NHPulse layout MAT/custom-locations files'; ...
         '*.mat', 'MAT files (*.mat)'; ...
         '*.*', 'All files (*.*)'}, ...
        opts.filePickerTitle, startDir);
    if isequal(filePart, 0)
        error('acsMakeFieldTripLayout:FilePickerCancelled', ...
            'FieldTrip layout file selection was cancelled.');
    end
    fileName = fullfile(folder, filePart);
end

function [layout, sourceInfo] = readLayoutFile(fileName, sourceInfo)
    fileName = expandUserPath(char(fileName));
    if exist(fileName, 'file') ~= 2
        error('acsMakeFieldTripLayout:MissingLayoutFile', ...
            'Layout file not found: %s', fileName);
    end
    [~, ~, ext] = fileparts(fileName);
    if strcmpi(ext, '.mat')
        raw = load(fileName);
        [layout, variableName] = firstLayoutStruct(raw);
        sourceInfo.file = fileName;
        sourceInfo.variableName = variableName;
        return;
    end

    layout = readCustomLocationsText(fileName);
    sourceInfo.file = fileName;
    sourceInfo.variableName = 'customLocationsText';
end

function [layout, variableName] = firstLayoutStruct(raw)
    preferred = {'out', 'outForSave', 'outToSave', 'outSaved', ...
        'fieldtripLayout', 'layout', 'combinedLayout', 'manufacturing', ...
        'manufacturingPreflight'};
    for i = 1:numel(preferred)
        if isfield(raw, preferred{i})
            layout = canonicalLayoutCandidate(raw.(preferred{i}));
            if ~isempty(layout)
                variableName = preferred{i};
                return;
            end
        end
    end
    names = fieldnames(raw);
    for i = 1:numel(names)
        layout = canonicalLayoutCandidate(raw.(names{i}));
        if ~isempty(layout)
            variableName = names{i};
            return;
        end
    end
    error('acsMakeFieldTripLayout:NoLayoutInFile', ...
        ['MAT file does not contain a readable NHPulse layout. Expected ', ...
         'names/layoutCoordinatesMm, expandedLayout, or out.layout.']);
end

function layout = canonicalLayoutCandidate(value)
    layout = [];
    if ~isstruct(value) || isempty(value)
        return;
    end
    if numel(value) > 1
        value = value(1);
    end
    if isfield(value, 'layout') && isstruct(value.layout) && ...
            looksLikeFieldTripLayout(value.layout)
        layout = fieldTripLayoutToLayoutCandidate(value.layout);
        return;
    end
    if looksLikeFieldTripLayout(value)
        layout = fieldTripLayoutToLayoutCandidate(value);
        return;
    end
    if isfield(value, 'expandedLayout') && isstruct(value.expandedLayout) && ...
            looksLikeNhpulseLayout(value.expandedLayout)
        layout = value.expandedLayout;
        return;
    end
    if isfield(value, 'layout') && isstruct(value.layout) && ...
            looksLikeNhpulseLayout(value.layout)
        layout = value.layout;
        return;
    end
    if looksLikeNhpulseLayout(value)
        layout = value;
    end
end

function tf = looksLikeNhpulseLayout(S)
    tf = isstruct(S) && ...
        ((isfield(S, 'layoutCoordinatesMm') && ~isempty(S.layoutCoordinatesMm)) || ...
         (isfield(S, 'expandedLayoutCoordinatesMm') && ~isempty(S.expandedLayoutCoordinatesMm))) && ...
        ((isfield(S, 'names') && ~isempty(S.names)) || ...
         (isfield(S, 'expandedNames') && ~isempty(S.expandedNames)));
end

function tf = looksLikeFieldTripLayout(S)
    tf = isstruct(S) && isfield(S, 'pos') && isfield(S, 'label') && ...
        ~isempty(S.pos) && ~isempty(S.label);
end

function layout = fieldTripLayoutToLayoutCandidate(ftLayout)
    labels = cellstr(ftLayout.label(:));
    pos = double(ftLayout.pos);
    layout = struct();
    layout.names = labels(:);
    layout.layoutCoordinatesMm = [pos(:, 1:2), zeros(size(pos, 1), 1)];
    layout.siteRoles = inferRolesFromNames(labels);
end

function layout = readCustomLocationsText(fileName)
    fid = fopen(fileName, 'r');
    if fid < 0
        error('acsMakeFieldTripLayout:CannotOpenFile', ...
            'Could not open layout text file: %s', fileName);
    end
    cleaner = onCleanup(@() fclose(fid));
    data = textscan(fid, '%s%f%f%f', 'CommentStyle', '#');
    if isempty(data{1}) || any(cellfun(@isempty, data(2:4)))
        error('acsMakeFieldTripLayout:BadCustomLocationsFile', ...
            ['Could not read custom-locations text file. Expected rows like ', ...
             '"label x y z": %s'], fileName);
    end
    layout = struct();
    layout.names = data{1}(:);
    layout.layoutCoordinatesMm = [data{2}, data{3}, data{4}];
    layout.siteRoles = inferRolesFromNames(layout.names);
    layout.sourceNote = ['Read from custom-locations text file. These ', ...
        'coordinates may be ROAST voxel coordinates rather than capMaker ', ...
        'print-frame millimeters; prefer the matching *_report.mat file ', ...
        'when available.'];
    clear cleaner
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
    error('acsMakeFieldTripLayout:TagNotFound', ...
        ['Could not find a readable layout report matching tag "%s". ', ...
         'Searched:\n%s'], tag, triedRoots);
end

function roots = candidateSearchRoots(opts)
    roots = {};
    if ~isempty(opts.searchRoot)
        roots{end + 1} = opts.searchRoot; %#ok<AGROW>
    end
    try
        if exist('acsPaths', 'file') == 2
            P = acsPaths();
            fields = {'outputRoot', 'subjectOutputRoot'};
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
        key = lower(canonicalPath(root));
        if any(strcmp(key, seen))
            continue;
        end
        seen{end + 1} = key; %#ok<AGROW>
        roots{end + 1} = root; %#ok<AGROW>
    end
end

function value = canonicalPath(pathIn)
    try
        value = char(java.io.File(pathIn).getCanonicalPath());
    catch
        value = char(pathIn);
    end
end

function fileName = sourceFileFromLayout(layout)
    fileName = '';
    fields = {'reportMat', 'customLocationsFile', 'outputFile', 'sourceFile'};
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

function [coords, names] = layoutCoordinatesAndNames(layout)
    if isfield(layout, 'layoutCoordinatesMm') && ~isempty(layout.layoutCoordinatesMm)
        coords = double(layout.layoutCoordinatesMm);
    elseif isfield(layout, 'expandedLayoutCoordinatesMm') && ~isempty(layout.expandedLayoutCoordinatesMm)
        coords = double(layout.expandedLayoutCoordinatesMm);
    else
        error('acsMakeFieldTripLayout:MissingCoordinates', ...
            'Layout does not report layoutCoordinatesMm.');
    end
    if size(coords, 2) < 3
        error('acsMakeFieldTripLayout:BadCoordinates', ...
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
        error('acsMakeFieldTripLayout:NameCoordinateMismatch', ...
            'Layout has %d names and %d coordinate rows.', numel(names), size(coords, 1));
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
    inferred = inferRolesFromNames(names);
    unknown = strcmpi(roles, 'electrode');
    roles(unknown) = inferred(unknown);
end

function roles = inferRolesFromNames(names)
    names = cellstr(names(:));
    roles = repmat({'electrode'}, numel(names), 1);
    for i = 1:numel(names)
        lowerName = lower(char(names{i}));
        if contains(lowerName, 'tes')
            roles{i} = 'tES';
        elseif contains(lowerName, 'eeg')
            roles{i} = 'EEG';
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
        switch lower(strtrim(roles{i}))
            case 'tes'
                roles{i} = 'tES';
            case 'eeg'
                roles{i} = 'EEG';
            otherwise
                roles{i} = 'electrode';
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

function keep = selectRowsForFieldTrip(roles, names, opts)
    rolesLower = cellfun(@(x) lower(strtrim(char(x))), roles(:), ...
        'UniformOutput', false);
    request = opts.includeRoles;
    if any(strcmp(request, 'all'))
        keep = true(size(rolesLower));
    elseif any(strcmp(request, 'autoeeg'))
        keep = strcmp(rolesLower, 'eeg');
        if ~any(keep)
            namesLower = cellfun(@(x) lower(char(x)), names(:), ...
                'UniformOutput', false);
            keep = contains(namesLower, 'eeg');
        end
        if ~any(keep)
            keep = true(size(rolesLower));
            warning('acsMakeFieldTripLayout:NoEegRoles', ...
                ['No EEG roles were detected; including all channels. ', ...
                 'Use includeRoles=''EEG'' to require EEG-only input.']);
        end
    else
        keep = false(size(rolesLower));
        for i = 1:numel(request)
            switch request{i}
                case 'eeg'
                    keep = keep | strcmp(rolesLower, 'eeg');
                case 'tes'
                    keep = keep | strcmp(rolesLower, 'tes');
                case 'electrode'
                    keep = keep | strcmp(rolesLower, 'electrode');
            end
        end
    end
    if ~any(keep)
        error('acsMakeFieldTripLayout:NoSelectedChannels', ...
            'No channels matched includeRoles=%s.', rolesDescription(request));
    end
end

function labels = displayLabels(names, labelMode)
    labels = cellstr(names(:));
    if strcmpi(labelMode, 'raw')
        return;
    end
    for i = 1:numel(labels)
        label = regexprep(labels{i}, '^customTES', 'tES', 'ignorecase');
        label = regexprep(label, '^customEEG', 'EEG', 'ignorecase');
        label = regexprep(label, '^tes', 'tES', 'ignorecase');
        label = regexprep(label, '^eeg', 'EEG', 'ignorecase');
        labels{i} = label;
    end
end

function xy = projectCoordinates(coords, plane)
    switch plane
        case 'xy'
            xy = coords(:, [1 2]);
        case 'xz'
            xy = coords(:, [1 3]);
        case 'yz'
            xy = coords(:, [2 3]);
        otherwise
            error('acsMakeFieldTripLayout:BadProjectionPlane', ...
                'Unsupported projectionPlane "%s".', plane);
    end
end

function outlineRaw = resolveOutlineRaw(layout, allCoordsMm, opts)
    outlineRaw = zeros(0, 2);
    if strcmpi(opts.outlineSource, 'none')
        return;
    end
    if any(strcmpi(opts.outlineSource, {'auto', 'skinCache'}))
        skinCacheFile = opts.skinCacheFile;
        if isempty(skinCacheFile)
            skinCacheFile = skinCacheFromLayout(layout);
        end
        if ~isempty(skinCacheFile) && exist(skinCacheFile, 'file') == 2
            try
                points = readSkinCachePoints(skinCacheFile, opts.outlineMeshStage);
                outlineRaw = boundaryFromPoints(projectCoordinates(points, opts.projectionPlane));
                if ~isempty(outlineRaw)
                    return;
                end
            catch ME
                if strcmpi(opts.outlineSource, 'skinCache')
                    rethrow(ME);
                end
            end
        elseif strcmpi(opts.outlineSource, 'skinCache')
            error('acsMakeFieldTripLayout:MissingSkinCache', ...
                'Skin cache file not found: %s', skinCacheFile);
        end
    end
    if any(strcmpi(opts.outlineSource, {'auto', 'layout'}))
        outlineRaw = boundaryFromPoints(projectCoordinates(allCoordsMm, opts.projectionPlane));
    end
end

function fileName = skinCacheFromLayout(layout)
    fileName = '';
    if isfield(layout, 'layout') && isstruct(layout.layout) && ...
            isfield(layout.layout, 'skin') && isstruct(layout.layout.skin) && ...
            isfield(layout.layout.skin, 'cacheFile') && ~isempty(layout.layout.skin.cacheFile)
        fileName = expandUserPath(char(layout.layout.skin.cacheFile));
        return;
    end
    fields = {'skinCacheFile', 'capMakerSkinCacheFile'};
    for i = 1:numel(fields)
        if isfield(layout, fields{i}) && ~isempty(layout.(fields{i}))
            fileName = expandUserPath(char(layout.(fields{i})));
            return;
        end
    end
    if isfield(layout, 'targetOptions') && isstruct(layout.targetOptions) && ...
            isfield(layout.targetOptions, 'skinCacheFile') && ...
            ~isempty(layout.targetOptions.skinCacheFile)
        fileName = expandUserPath(char(layout.targetOptions.skinCacheFile));
    end
end

function points = readSkinCachePoints(skinCacheFile, meshStage)
    raw = load(skinCacheFile);
    switch meshStage
        case 'cap'
            points = pointsFromTriField(raw, {'TRskin'});
        case 'fullHead'
            points = pointsFromTriField(raw, {'TRfiducialHead', 'TRstableHead'});
        case 'auto'
            try
                points = pointsFromTriField(raw, {'TRskin'});
            catch
                points = pointsFromTriField(raw, {'TRfiducialHead', 'TRstableHead'});
            end
    end
end

function points = pointsFromTriField(raw, fields)
    points = [];
    for i = 1:numel(fields)
        if isfield(raw, fields{i}) && ~isempty(raw.(fields{i}))
            TR = raw.(fields{i});
            if isa(TR, 'triangulation')
                points = double(TR.Points);
            elseif isstruct(TR) && isfield(TR, 'Points')
                points = double(TR.Points);
            elseif isstruct(TR) && isfield(TR, 'vertices')
                points = double(TR.vertices);
            end
            if ~isempty(points)
                return;
            end
        end
    end
    error('acsMakeFieldTripLayout:MissingSkinMesh', ...
        'Skin cache does not contain the requested mesh stage.');
end

function boundaryXY = boundaryFromPoints(xy)
    xy = double(xy);
    xy = xy(all(isfinite(xy), 2), :);
    if size(xy, 1) < 3
        boundaryXY = zeros(0, 2);
        return;
    end
    xy = unique(round(xy, 6), 'rows');
    if size(xy, 1) < 3
        boundaryXY = zeros(0, 2);
        return;
    end
    try
        if exist('boundary', 'file') == 2
            idx = boundary(xy(:, 1), xy(:, 2), 0.85);
        else
            idx = convhull(xy(:, 1), xy(:, 2));
        end
    catch
        idx = convhull(xy(:, 1), xy(:, 2));
    end
    boundaryXY = xy(idx, :);
    boundaryXY = closePolygon(boundaryXY);
end

function xy = closePolygon(xy)
    if isempty(xy)
        return;
    end
    if any(xy(1, :) ~= xy(end, :))
        xy(end + 1, :) = xy(1, :);
    end
end

function [xy, outlineXY, info] = transformLayout2d(xyRaw, outlineRaw, opts)
    ref = xyRaw;
    if ~isempty(outlineRaw)
        ref = outlineRaw;
    end
    center = mean([min(ref, [], 1); max(ref, [], 1)], 1);
    xy = bsxfun(@minus, xyRaw, center);
    outlineXY = bsxfun(@minus, outlineRaw, center);

    if opts.rotationDeg ~= 0
        theta = opts.rotationDeg * pi / 180;
        R = [cos(theta), -sin(theta); sin(theta), cos(theta)];
        xy = xy * R';
        outlineXY = outlineXY * R';
    end
    if opts.flipX
        xy(:, 1) = -xy(:, 1);
        outlineXY(:, 1) = -outlineXY(:, 1);
    end
    if opts.flipY
        xy(:, 2) = -xy(:, 2);
        outlineXY(:, 2) = -outlineXY(:, 2);
    end
    if ~isempty(outlineXY)
        outlineXY = expandAboutCenter(outlineXY, opts.outlinePadding);
    end

    scale = 1;
    if strcmpi(opts.scaleMode, 'unit')
        ref2 = xy;
        if ~isempty(outlineXY)
            ref2 = outlineXY;
        end
        span = max(ref2, [], 1) - min(ref2, [], 1);
        scale = max(span);
        if ~isfinite(scale) || scale <= 0
            scale = 1;
        end
        xy = xy ./ scale;
        outlineXY = outlineXY ./ scale;
    end
    info = struct('centerBeforeTransform', center, ...
        'scaleDivisor', scale, ...
        'rotationDeg', opts.rotationDeg, ...
        'flipX', opts.flipX, ...
        'flipY', opts.flipY, ...
        'scaleMode', opts.scaleMode);
end

function xy = expandAboutCenter(xy, factor)
    if isempty(xy) || factor == 1
        return;
    end
    center = mean([min(xy, [], 1); max(xy, [], 1)], 1);
    xy = bsxfun(@plus, center, bsxfun(@times, bsxfun(@minus, xy, center), factor));
    xy = closePolygon(xy);
end

function [width, height] = resolveChannelSize(xy, opts)
    if isempty(opts.channelWidth)
        width = autoChannelSize(xy, opts.scaleMode);
    else
        width = opts.channelWidth;
    end
    if isempty(opts.channelHeight)
        height = autoChannelSize(xy, opts.scaleMode);
    else
        height = opts.channelHeight;
    end
end

function value = autoChannelSize(xy, scaleMode)
    if strcmpi(scaleMode, 'unit')
        value = 0.045;
        return;
    end
    if size(xy, 1) < 2
        value = 5;
        return;
    end
    D = squareformPdistLite(xy);
    D(D <= 0) = NaN;
    nn = min(D, [], 2, 'omitnan');
    value = max(3, min(8, 0.25 * median(nn, 'omitnan')));
    if ~isfinite(value)
        value = 5;
    end
end

function D = squareformPdistLite(xy)
    n = size(xy, 1);
    D = zeros(n, n);
    for i = 1:n
        delta = bsxfun(@minus, xy, xy(i, :));
        D(:, i) = sqrt(sum(delta .^ 2, 2));
    end
end

function [outputMatFile, outputLayFile] = resolveOutputFiles(opts, sourceInfo, layout)
    outputMatFile = opts.outputMatFile;
    outputLayFile = opts.outputLayFile;
    if ~opts.saveMat
        outputMatFile = '';
    end
    if ~opts.saveLay
        outputLayFile = '';
    end
    sourceFile = sourceInfo.file;
    if isempty(sourceFile)
        sourceFile = sourceFileFromLayout(layout);
    end
    if opts.saveMat && isempty(outputMatFile)
        outputMatFile = autoOutputPath(sourceFile, sourceInfo, layout, opts, ...
            '_fieldtripLayout.mat');
    end
    if opts.saveLay && isempty(outputLayFile)
        outputLayFile = autoOutputPath(sourceFile, sourceInfo, layout, opts, ...
            '_fieldtripLayout.lay');
    end
end

function fileName = autoOutputPath(sourceFile, sourceInfo, layout, opts, suffix)
    if ischar(sourceFile) && ~isempty(sourceFile)
        [folder, stem] = fileparts(sourceFile);
    elseif ~isempty(sourceInfo.tag)
        folder = pwd;
        stem = sourceInfo.tag;
    elseif isfield(layout, 'manufacturingTag') && ~isempty(layout.manufacturingTag)
        folder = pwd;
        stem = char(layout.manufacturingTag);
    else
        folder = pwd;
        stem = 'nhpulseLayout';
    end
    if ~isempty(opts.outputFolder)
        folder = opts.outputFolder;
    end
    stem = regexprep(stem, '_report$', '');
    stem = regexprep(stem, '_manufacturing$', '');
    fileName = fullfile(folder, [stem suffix]);
end

function writeLayFile(fileName, ftLayout)
    fid = fopen(fileName, 'w');
    if fid < 0
        error('acsMakeFieldTripLayout:CannotWriteLay', ...
            'Could not write FieldTrip layout file: %s', fileName);
    end
    cleaner = onCleanup(@() fclose(fid));
    for i = 1:numel(ftLayout.label)
        fprintf(fid, '%.9g\t%.9g\t%.9g\t%.9g\t%s\n', ...
            ftLayout.pos(i, 1), ftLayout.pos(i, 2), ...
            ftLayout.width(i), ftLayout.height(i), ftLayout.label{i});
    end
    clear cleaner
end

function fig = makeQcFigure(ftLayout, roles, opts, figVisible)
    fig = figure('Name', 'FieldTrip layout QC', 'Color', 'w', ...
        'Visible', figVisible, 'Position', [100 100 760 720]);
    ax = axes('Parent', fig, 'Position', [0.08 0.08 0.84 0.84]);
    hold(ax, 'on');
    if ~isempty(ftLayout.outline)
        outline = ftLayout.outline{1};
        plot(ax, outline(:, 1), outline(:, 2), 'k-', 'LineWidth', 1.5);
    end

    eegRows = strcmpi(roles, 'EEG');
    tesRows = strcmpi(roles, 'tES');
    otherRows = ~(eegRows | tesRows);
    if any(otherRows)
        scatter(ax, ftLayout.pos(otherRows, 1), ftLayout.pos(otherRows, 2), ...
            52, [0.50 0.50 0.50], 'filled', 'MarkerEdgeColor', 'k');
    end
    if any(tesRows)
        scatter(ax, ftLayout.pos(tesRows, 1), ftLayout.pos(tesRows, 2), ...
            62, [0.15 0.15 0.15], 'd', 'filled', 'MarkerEdgeColor', 'k');
    end
    if any(eegRows)
        scatter(ax, ftLayout.pos(eegRows, 1), ftLayout.pos(eegRows, 2), ...
            58, [0.20 0.55 0.95], 'filled', 'MarkerEdgeColor', 'k');
    end
    for i = 1:numel(ftLayout.label)
        text(ax, ftLayout.pos(i, 1), ftLayout.pos(i, 2), ...
            ['  ' ftLayout.label{i}], ...
            'FontSize', 9, 'Interpreter', 'none', ...
            'VerticalAlignment', 'middle', 'Color', [0.05 0.05 0.05]);
    end
    axis(ax, 'equal');
    box(ax, 'on');
    grid(ax, 'on');
    xlabel(ax, 'FieldTrip layout X');
    ylabel(ax, 'FieldTrip layout Y');
    title(ax, sprintf('FieldTrip layout (%s projection)', opts.projectionPlane), ...
        'Interpreter', 'none');
end

function textOut = rolesDescription(roles)
    if ischar(roles)
        textOut = roles;
    else
        textOut = strjoin(cellfun(@char, roles(:), 'UniformOutput', false), ',');
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
    if startsWith(pathOut, ['~' filesep]) || strcmp(pathOut, '~')
        homeDir = char(java.lang.System.getProperty('user.home'));
        if strcmp(pathOut, '~')
            pathOut = homeDir;
        else
            pathOut = fullfile(homeDir, pathOut(3:end));
        end
    end
end
