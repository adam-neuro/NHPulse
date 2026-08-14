function out = acsSelectModelFiducials(layoutOrMesh, varargin)
% ACSSELECTMODELFIDUCIALS Select model-space fiducials on a capMaker head mesh.
%
% out = acsSelectModelFiducials(layoutOrSegOut)
% loads the full-head fiducial mesh associated with a layout report, skin
% mesh cache, or acsSegmentAnatomyWithTpm output and lets the user select
% named fiducials, typically Nas/Lpa/Rpa, in capMaker print-frame
% millimeters. The saved output can be passed directly to
% acsRegisterPolhemusFiducials.
%
% Name-value options:
%   fiducialLabels : labels to select, 'ask', or 'polhemus' [{'Nas','Lpa','Rpa'}]
%   polhemusFile   : optional saved acsPolhemus file used for labels ['']
%   meshStage      : 'fullHead' or 'cap' ['fullHead']
%   subjectId      : subject used for capMaker cache paths ['']
%   capMakerInputFile : explicit NIfTI/DICOM input for capMaker ['']
%   skinCacheFile  : explicit capMaker scalp mesh cache ['']
%   forceSkinMesh  : recompute capMaker scalp mesh [false]
%   skinMeshOptions: struct passed to skinMeshFromMPRAGE [struct()]
%   cropPlaneMode  : only used for meshStage='cap' with segOut input ['default']
%   cropPlaneFile  : only used for meshStage='cap' with segOut input ['']
%   outputFile     : MAT file for saved fiducials ['']
%   force          : ignore existing outputFile [false]
%   editMode       : 'auto', 'always', or 'never' ['auto']
%   displayMaxFaces: display mesh decimation target [35000]
%   meshAlpha      : mesh face opacity [1]
%   meshLighting   : 'flat', 'gouraud', or 'none' ['flat']
%   showFigures    : open selection GUI [true]
%   saveFigures    : save QC figure [false]
%   figureExportOptions : struct passed to acsExportFigure [struct()]
%   verbose        : print progress [true]

    if nargin < 1 || isempty(layoutOrMesh)
        error('acsSelectModelFiducials:MissingInput', ...
            'Provide a layout struct/report, skin mesh cache, or triangulation.');
    end

    opts = parseInputs(varargin{:});
    addLocalDependencies();
    opts.fiducialLabels = resolveRequestedFiducialLabels(opts);

    [TRskin, source] = readSkinMesh(layoutOrMesh, opts);
    if isempty(opts.outputFile)
        opts.outputFile = defaultOutputFile(source, opts.fiducialLabels);
    end

    existingFile = exist(opts.outputFile, 'file') == 2;
    openGui = shouldOpenGui(existingFile, opts);
    if ~existingFile && ~openGui
        error('acsSelectModelFiducials:NoExistingSelection', ...
            ['No saved model fiducials exist and the selection GUI is disabled. ', ...
             'Run with showFigures=true or provide outputFile for an existing report.']);
    end
    if existingFile && ~opts.force && ~openGui
        out = loadExisting(opts.outputFile);
        logMsg(opts, 'Reusing saved model fiducials: %s', opts.outputFile);
        return;
    end

    start = emptySelection(opts.fiducialLabels);
    if existingFile && ~opts.force
        existing = loadExisting(opts.outputFile);
        start = mergeExistingSelection(start, existing);
        logMsg(opts, 'Starting from saved model fiducials: %s', opts.outputFile);
    end

    accepted = true;
    fig = [];
    if openGui
        [start, accepted, fig] = selectFiducialsGui(TRskin, source, start, opts);
        if ~accepted
            if isgraphics(fig), delete(fig); end
            error('acsSelectModelFiducials:SelectionCanceled', ...
                'Model fiducial selection was canceled.');
        end
    end

    out = buildOutput(start, source, opts, fig);
    ensureDir(fileparts(opts.outputFile));
    out.outputFile = opts.outputFile;
    out.jsonFile = replaceExtension(opts.outputFile, '.json');
    outSaved = stripFigure(out);
    saveModelFiducialReport(opts.outputFile, outSaved);
    writeJson(out.jsonFile, jsonReady(outSaved));
    logMsg(opts, 'Saved model fiducials: %s', opts.outputFile);

    if opts.saveFigures
        qcStem = replaceExtension(opts.outputFile, '_qc');
        qcFiles = saveQcFigure(fig, qcStem, TRskin, out, opts);
        out.qcFiles = qcFiles;
        if ~isempty(qcFiles)
            out.qcFile = qcFiles{1};
        end
        outSaved = stripFigure(out);
        saveModelFiducialReport(opts.outputFile, outSaved);
    end

    if isgraphics(fig) && ~opts.showFigures
        delete(fig);
        out.figure = [];
    end
end

function opts = parseInputs(varargin)
    p = inputParser;
    p.FunctionName = 'acsSelectModelFiducials';
    addParameter(p, 'fiducialLabels', {'Nas', 'Lpa', 'Rpa'}, ...
        @(x) iscell(x) || isstring(x) || ischar(x));
    addParameter(p, 'polhemusFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'meshStage', 'fullHead', @isMeshStage);
    addParameter(p, 'subjectId', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'dicomDir', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'capMakerInputFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'skinCacheFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'forceSkinMesh', false, @isBoolLike);
    addParameter(p, 'skinMeshOptions', struct(), @(x) isempty(x) || isstruct(x));
    addParameter(p, 'cropPlaneMode', 'default', @isCropPlaneMode);
    addParameter(p, 'cropPlaneFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'outputFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'force', false, @isBoolLike);
    addParameter(p, 'editMode', 'auto', @isEditMode);
    addParameter(p, 'displayMaxFaces', 35000, @isPositiveScalar);
    addParameter(p, 'meshAlpha', 1, @isAlphaScalar);
    addParameter(p, 'meshLighting', 'flat', @isMeshLighting);
    addParameter(p, 'showFigures', true, @isBoolLike);
    addParameter(p, 'saveFigures', false, @isBoolLike);
    addParameter(p, 'figureExportOptions', struct(), @(x) isempty(x) || isstruct(x));
    addParameter(p, 'verbose', true, @isBoolLike);
    parse(p, varargin{:});

    opts = p.Results;
    opts.fiducialLabels = normalizeLabelCell(opts.fiducialLabels);
    opts.polhemusFile = expandUserPath(char(opts.polhemusFile));
    opts.meshStage = normalizeMeshStage(opts.meshStage);
    opts.subjectId = char(opts.subjectId);
    opts.dicomDir = expandUserPath(char(opts.dicomDir));
    opts.capMakerInputFile = expandUserPath(char(opts.capMakerInputFile));
    opts.skinCacheFile = expandUserPath(char(opts.skinCacheFile));
    opts.forceSkinMesh = logical(opts.forceSkinMesh);
    if isempty(opts.skinMeshOptions)
        opts.skinMeshOptions = struct();
    end
    opts.cropPlaneMode = normalizeCropPlaneMode(opts.cropPlaneMode);
    opts.cropPlaneFile = expandUserPath(char(opts.cropPlaneFile));
    opts.outputFile = expandUserPath(char(opts.outputFile));
    opts.force = logical(opts.force);
    opts.editMode = lower(char(opts.editMode));
    opts.displayMaxFaces = round(double(opts.displayMaxFaces));
    opts.meshAlpha = double(opts.meshAlpha);
    opts.meshLighting = normalizeMeshLighting(opts.meshLighting);
    opts.showFigures = logical(opts.showFigures);
    opts.saveFigures = logical(opts.saveFigures);
    if isempty(opts.figureExportOptions)
        opts.figureExportOptions = struct();
    end
    opts.verbose = logical(opts.verbose);
end

function tf = isBoolLike(x)
    tf = (islogical(x) || isnumeric(x)) && isscalar(x);
end

function tf = isPositiveScalar(x)
    tf = isnumeric(x) && isscalar(x) && isfinite(x) && x > 0;
end

function tf = isAlphaScalar(x)
    tf = isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0 && x <= 1;
end

function tf = isMeshLighting(x)
    if ~(ischar(x) || isstring(x))
        tf = false;
        return;
    end
    tf = any(strcmpi(char(x), {'flat', 'gouraud', 'none'}));
end

function tf = isCropPlaneMode(x)
    if ~(ischar(x) || isstring(x))
        tf = false;
        return;
    end
    tf = any(strcmpi(char(x), {'autoSelect', 'auto', 'select', ...
        'reuse', 'default'}));
end

function mode = normalizeCropPlaneMode(value)
    value = lower(strtrim(char(value)));
    switch value
        case {'autoselect', 'auto_select', 'askifmissing'}
            mode = 'autoSelect';
        case {'auto', 'reuseifavailable'}
            mode = 'auto';
        case {'select', 'ask', 'gui'}
            mode = 'select';
        case {'reuse', 'existing'}
            mode = 'reuse';
        case {'default', 'none'}
            mode = 'default';
        otherwise
            error('acsSelectModelFiducials:BadCropPlaneMode', ...
                ['cropPlaneMode must be autoSelect, auto, select, ', ...
                 'reuse, or default.']);
    end
end

function value = normalizeMeshLighting(value)
    value = lower(strtrim(char(value)));
    if ~any(strcmp(value, {'flat', 'gouraud', 'none'}))
        error('acsSelectModelFiducials:BadMeshLighting', ...
            'meshLighting must be ''flat'', ''gouraud'', or ''none''.');
    end
end

function tf = isEditMode(x)
    if ~(ischar(x) || isstring(x))
        tf = false;
        return;
    end
    tf = any(strcmpi(char(x), {'auto', 'always', 'never'}));
end

function tf = isMeshStage(x)
    if ~(ischar(x) || isstring(x))
        tf = false;
        return;
    end
    tf = any(strcmpi(char(x), {'fullHead', 'full', 'head', 'fiducial', ...
        'fiducials', 'cap', 'cropped', 'manufacturing'}));
end

function stage = normalizeMeshStage(value)
    value = lower(strtrim(char(value)));
    switch value
        case {'fullhead', 'full', 'head', 'fiducial', 'fiducials'}
            stage = 'fullHead';
        case {'cap', 'cropped', 'manufacturing'}
            stage = 'cap';
        otherwise
            error('acsSelectModelFiducials:BadMeshStage', ...
                'meshStage must be ''fullHead'' or ''cap''.');
    end
end

function labels = normalizeLabelCell(labelsIn)
    if isempty(labelsIn)
        labels = {};
    elseif iscell(labelsIn)
        labels = cellfun(@char, labelsIn(:), 'UniformOutput', false);
    elseif isstring(labelsIn)
        labels = cellstr(labelsIn(:));
    elseif ischar(labelsIn)
        if size(labelsIn, 1) == 1
            labels = {strtrim(labelsIn)};
        else
            labels = cellstr(labelsIn);
        end
    else
        labels = cellstr(labelsIn(:));
    end
    labels = labels(:);
end

function addLocalDependencies()
    repoRoot = fileparts(fileparts(mfilename('fullpath')));
    addpath(fullfile(repoRoot, 'acsUtilities'));
    addpath(fullfile(repoRoot, 'capMaker', 'core'));
    addpath(fullfile(repoRoot, 'capMaker', 'geometry'));
end

function labels = resolveRequestedFiducialLabels(opts)
    labels = opts.fiducialLabels;
    if isempty(labels)
        if ~isempty(opts.polhemusFile)
            labels = labelsFromPolhemusFile(opts.polhemusFile);
        else
            labels = selectLandmarksFromBullpen({'Nas', 'Lpa', 'Rpa'});
        end
        return;
    end

    if numel(labels) == 1
        request = lower(strtrim(labels{1}));
        switch request
            case {'ask', 'select', 'gui', 'bullpen', 'landmarks'}
                labels = selectLandmarksFromBullpen({'Nas', 'Lpa', 'Rpa'});
                return;
            case {'all', 'alllandmarks'}
                labels = normalizeLabelCell(acsMonkeyLandmarkBullpen('labels'));
                return;
            case {'anatomical', 'anatomicallandmarks'}
                labels = normalizeLabelCell(acsMonkeyLandmarkBullpen('anatomical'));
                return;
            case {'polhemus', 'frompolhemus', 'file'}
                if isempty(opts.polhemusFile)
                    [fname, folder] = uigetfile( ...
                        {'*.mat;*.json;*.txt', ...
                         'Polhemus session (*.mat, *.json, *.txt)'; ...
                         '*.*', 'All files'}, ...
                        'Select saved Polhemus session for fiducial labels');
                    if isequal(fname, 0)
                        error('acsSelectModelFiducials:NoPolhemusFile', ...
                            'No Polhemus file was selected.');
                    end
                    labels = labelsFromPolhemusFile(fullfile(folder, fname));
                else
                    labels = labelsFromPolhemusFile(opts.polhemusFile);
                end
                return;
        end
    end
    labels = cleanLabelList(labels);
end

function labels = selectLandmarksFromBullpen(defaultLabels)
    items = acsMonkeyLandmarkBullpen('struct');
    list = arrayfun(@(x) sprintf('%s - %s', x.label, x.displayName), ...
        items, 'UniformOutput', false);
    labelsAll = {items.label};
    defaultLabels = cleanLabelList(defaultLabels);
    defaultCanonical = acsMonkeyLandmarkBullpen('canonical', defaultLabels);
    initial = find(ismember(labelsAll, defaultCanonical));
    if isempty(initial)
        initial = 1:min(3, numel(labelsAll));
    end
    [selection, ok] = listdlg( ...
        'PromptString', {'Select model fiducials to mark.', ...
                         'Aliases such as Sep/Loc/Roc/Ini are accepted later.'}, ...
        'SelectionMode', 'multiple', ...
        'ListString', list, ...
        'InitialValue', initial, ...
        'Name', 'Model Fiducials');
    if ~ok || isempty(selection)
        error('acsSelectModelFiducials:SelectionCanceled', ...
            'Model fiducial label selection was canceled.');
    end
    labels = labelsAll(selection).';
end

function labels = labelsFromPolhemusFile(fileName)
    fileName = expandUserPath(fileName);
    if exist(fileName, 'file') ~= 2
        error('acsSelectModelFiducials:PolhemusFileNotFound', ...
            'Polhemus file not found: %s', fileName);
    end
    [~, ~, ext] = fileparts(fileName);
    switch lower(ext)
        case '.mat'
            S = load(fileName);
            labels = labelsFromPolhemusStruct(S);
        case '.json'
            labels = labelsFromPolhemusStruct(jsondecode(fileread(fileName)));
        otherwise
            labels = labelsFromTextFile(fileName);
    end
    labels = cleanLabelList(labels);
    if isempty(labels)
        error('acsSelectModelFiducials:NoPolhemusLabels', ...
            'No usable labels were found in Polhemus file: %s', fileName);
    end
end

function labels = labelsFromPolhemusStruct(S)
    labels = {};
    if ~isstruct(S)
        return;
    end
    preferred = {'out', 'session', 'polhemusSession', 'data'};
    for i = 1:numel(preferred)
        if isfield(S, preferred{i}) && isstruct(S.(preferred{i}))
            labels = labelsFromPolhemusStruct(S.(preferred{i}));
            if ~isempty(labels), return; end
        end
    end
    if isfield(S, 'referencePoints') && isstruct(S.referencePoints) && ...
            isfield(S.referencePoints, 'labels')
        labels = normalizeLabelCell(S.referencePoints.labels);
    elseif isfield(S, 'selectedLandmarkLabels') && ...
            ~isempty(S.selectedLandmarkLabels)
        labels = normalizeLabelCell(S.selectedLandmarkLabels);
    elseif isfield(S, 'activeReferenceLabels') && ...
            ~isempty(S.activeReferenceLabels)
        labels = normalizeLabelCell(S.activeReferenceLabels);
    elseif isfield(S, 'fiducials') && isstruct(S.fiducials) && ...
            isfield(S.fiducials, 'labels')
        labels = normalizeLabelCell(S.fiducials.labels);
    elseif isfield(S, 'labels') && ~isempty(S.labels)
        labels = normalizeLabelCell(S.labels);
    end
end

function labels = labelsFromTextFile(fileName)
    raw = regexp(fileread(fileName), '\r\n|\n|\r', 'split');
    labels = cell(0, 1);
    for i = 1:numel(raw)
        line = strtrim(raw{i});
        if isempty(line), continue; end
        parts = regexp(line, '[,\t ]+', 'split');
        if ~isempty(parts) && ~isempty(parts{1})
            labels{end + 1, 1} = parts{1}; %#ok<AGROW>
        end
    end
end

function labels = cleanLabelList(labelsIn)
    labels = normalizeLabelCell(labelsIn);
    labels = labels(~cellfun(@isempty, labels));
    labels = unique(labels, 'stable');
end

function tf = shouldOpenGui(existingFile, opts)
    if ~opts.showFigures
        tf = false;
        return;
    end
    switch opts.editMode
        case 'always'
            tf = true;
        case 'never'
            tf = false;
        otherwise
            tf = opts.force || ~existingFile;
    end
end

function selection = emptySelection(labels)
    n = numel(labels);
    selection = struct();
    selection.labels = labels(:);
    selection.coordinatesMm = nan(n, 3);
    selection.selectedVertex = nan(n, 1);
end

function selection = mergeExistingSelection(selection, existing)
    if ~isfield(existing, 'labels') || ~isfield(existing, 'coordinatesMm')
        return;
    end
    oldLabels = normalizeLabelCell(existing.labels);
    oldCoords = double(existing.coordinatesMm);
    oldVertex = nan(size(oldCoords, 1), 1);
    if isfield(existing, 'selectedVertex') && ~isempty(existing.selectedVertex)
        oldVertex = double(existing.selectedVertex(:));
    end
    for i = 1:numel(selection.labels)
        hit = findLabelAliasMatch(selection.labels{i}, oldLabels);
        if ~isempty(hit) && hit <= size(oldCoords, 1)
            selection.coordinatesMm(i, :) = oldCoords(hit, :);
            selection.selectedVertex(i) = oldVertex(hit);
        end
    end
end

function hit = findLabelAliasMatch(label, candidateLabels)
    hit = [];
    candidateNorm = normalizeLabelKeys(candidateLabels);
    aliases = requestedModelFiducialAliases(label);
    for i = 1:numel(aliases)
        hit = find(strcmp(candidateNorm, aliases{i}), 1);
        if ~isempty(hit)
            return;
        end
    end
end

function aliases = requestedModelFiducialAliases(label)
    exact = normalizeLabelKeys({label});
    try
        expanded = normalizeLabelKeys( ...
            acsMonkeyLandmarkBullpen('aliasesFor', label));
    catch
        expanded = {};
    end
    aliases = unique([exact(:); expanded(:)], 'stable');
end

function labels = normalizeLabelKeys(labelsIn)
    labels = normalizeLabelCell(labelsIn);
    labels = regexprep(labels, '[^A-Za-z0-9]', '');
    labels = cellfun(@lower, labels, 'UniformOutput', false);
end

function [TRskin, source] = readSkinMesh(value, opts)
    source = struct('type', '', 'file', '', 'layoutFile', '', ...
        'label', '', 't1File', '', 'meshStage', opts.meshStage, ...
        'coordinateFrame', 'capMakerPrintMm');

    if isa(value, 'triangulation')
        TRskin = value;
        source.type = 'triangulation';
        source.label = 'triangulation';
        source.coordinateFrame = 'modelMm';
        return;
    end

    if isstruct(value) && isfield(value, 'Points') && isfield(value, 'ConnectivityList')
        TRskin = triangulation(double(value.ConnectivityList), double(value.Points));
        source.type = 'meshStruct';
        source.label = 'mesh struct';
        source.coordinateFrame = 'modelMm';
        return;
    end

    if isstruct(value) && isLayoutLike(value)
        [TRskin, source] = readSkinMeshFromLayout(value, source, opts);
        return;
    end

    if isstruct(value) && isSegmentationLike(value)
        [TRskin, source] = readSkinMeshFromSegmentation(value, source, opts);
        return;
    end

    if isstruct(value)
        [TRskin, source] = readSkinMeshFromLayout(value, source, opts);
        return;
    end

    if ~(ischar(value) || isstring(value))
        error('acsSelectModelFiducials:BadInput', ...
            ['Input must be a segmentation output, layout, skin cache, ', ...
             'mesh struct, or triangulation.']);
    end

    fileName = expandUserPath(char(value));
    if exist(fileName, 'file') ~= 2
        error('acsSelectModelFiducials:FileNotFound', ...
            'File not found: %s', fileName);
    end
    S = load(fileName);
    if isSkinCacheStruct(S)
        [TRskin, source] = readSkinMeshFromCacheStruct(S, source, fileName, opts);
    else
        layout = firstStruct(S);
        source.layoutFile = fileName;
        if isSkinCacheStruct(layout)
            [TRskin, source] = readSkinMeshFromCacheStruct(layout, ...
                source, fileName, opts);
        elseif isLayoutLike(layout)
            [TRskin, source] = readSkinMeshFromLayout(layout, source, opts);
        elseif isSegmentationLike(layout)
            [TRskin, source] = readSkinMeshFromSegmentation(layout, ...
                source, opts);
            if isempty(source.layoutFile)
                source.layoutFile = fileName;
            end
        else
            [TRskin, source] = readSkinMeshFromLayout(layout, source, opts);
        end
        if isempty(source.label)
            source.label = getFileStem(fileName);
        end
    end
end

function tf = isLayoutLike(value)
    tf = isstruct(value) && isfield(value, 'layout') && ...
        isstruct(value.layout) && isfield(value.layout, 'skin') && ...
        isfield(value.layout.skin, 'cacheFile');
end

function tf = isSegmentationLike(value)
    tf = isstruct(value) && ...
        (isfield(value, 'roastReady') || ...
         isfield(value, 'activeSegmentationT1') || ...
         isfield(value, 'segmentationT1') || ...
         isfield(value, 'sourceT1'));
end

function [TRskin, source] = readSkinMeshFromLayout(layout, source, opts)
    if ~isfield(layout, 'layout') || ~isfield(layout.layout, 'skin') || ...
            ~isfield(layout.layout.skin, 'cacheFile') || ...
            isempty(layout.layout.skin.cacheFile)
        error('acsSelectModelFiducials:MissingSkinCache', ...
            'Layout does not report layout.skin.cacheFile.');
    end
    cacheFile = char(layout.layout.skin.cacheFile);
    if exist(cacheFile, 'file') ~= 2
        error('acsSelectModelFiducials:SkinCacheNotFound', ...
            'Skin cache not found: %s', cacheFile);
    end
    S = load(cacheFile);
    [TRskin, source] = readSkinMeshFromCacheStruct(S, source, cacheFile, opts);
    source.type = 'layout';
    source.file = cacheFile;
    if isfield(layout, 't1File') && ~isempty(layout.t1File)
        source.t1File = char(layout.t1File);
        source.label = getFileStem(layout.t1File);
    else
        source.label = getFileStem(cacheFile);
    end
end

function [TRskin, source] = readSkinMeshFromSegmentation(segOut, source, opts)
    [t1File, subjectId] = segmentationT1AndSubject(segOut, opts);
    [capInput, inputKind] = resolveCapMakerInput(t1File, opts);
    capWorkDir = resolveCapWorkDir(subjectId, t1File);
    selectingFullHead = strcmp(opts.meshStage, 'fullHead');
    cropPlaneFile = '';
    cropPlane = struct();
    skinOpts = opts.skinMeshOptions;
    if selectingFullHead
        skinOpts = fullHeadFiducialSkinOptions(skinOpts, inputKind);
    else
        cropPlaneFile = resolveCropPlaneFile(capWorkDir, capInput, inputKind, opts);
        [skinOpts, cropPlane] = resolveCropPlaneOptions( ...
            skinOpts, cropPlaneFile, capInput, inputKind, opts);
    end

    cacheFile = opts.skinCacheFile;
    if isempty(cacheFile) && selectingFullHead
        cacheFile = defaultFullHeadSkinCacheFile(capWorkDir, capInput, inputKind);
    elseif isempty(cacheFile)
        cacheFile = defaultSkinCacheFile(capWorkDir, capInput, inputKind);
    end

    needsInteractiveCrop = ~selectingFullHead && ...
        (strcmp(opts.cropPlaneMode, 'select') || ...
        (strcmp(opts.cropPlaneMode, 'autoSelect') && ...
         exist(cropPlaneFile, 'file') ~= 2));
    needsInteractiveCrop = logical(needsInteractiveCrop);
    useCachedMesh = ~opts.forceSkinMesh && ~needsInteractiveCrop && ...
        exist(cacheFile, 'file') == 2;
    cacheRejectReason = '';
    if useCachedMesh
        logMsg(opts, 'Loading capMaker scalp mesh cache: %s', cacheFile);
        S = load(cacheFile);
        if ~isfield(S, 'meta')
            useCachedMesh = false;
            cacheRejectReason = 'lacks capMaker metadata';
        elseif ~selectingFullHead && ~cachedMeshMatchesCropPlane(S.meta, cropPlane)
            useCachedMesh = false;
            cacheRejectReason = 'does not match selected crop plane';
        elseif selectingFullHead && ~cachedMeshHasFullHead(S, S.meta)
            useCachedMesh = false;
            cacheRejectReason = 'lacks full-head fiducial mesh';
        end
        if ~useCachedMesh
            logMsg(opts, 'Cached capMaker scalp mesh %s; recomputing.', ...
                cacheRejectReason);
        end
    end

    if ~useCachedMesh
        if exist('skinMeshFromMPRAGE', 'file') ~= 2
            error('acsSelectModelFiducials:MissingSkinMeshFromMPRAGE', ...
                'capMaker core function skinMeshFromMPRAGE was not found on the MATLAB path.');
        end
        logMsg(opts, 'Computing capMaker scalp mesh from %s: %s', ...
            inputKind, capInput);
        if ~selectingFullHead
            skinOpts = capMakerSkinOptions(skinOpts, inputKind);
        end
        if ~isfield(skinOpts, 'viz') || isempty(skinOpts.viz)
            skinOpts.viz = false;
        end
        [TRskinCache, meta] = skinMeshFromMPRAGE(capInput, skinOpts);
        if ~selectingFullHead && needsInteractiveCrop
            cropPlane = cropPlaneFromSkinMeta(meta, capInput, inputKind);
            saveCropPlane(cropPlaneFile, cropPlane);
            logMsg(opts, 'Saved capMaker crop plane: %s', cropPlaneFile);
        end
        TRfiducialHead = [];
        if isfield(meta, 'fiducialHead') && isstruct(meta.fiducialHead) && ...
                isfield(meta.fiducialHead, 'TR') && ~isempty(meta.fiducialHead.TR)
            TRfiducialHead = meta.fiducialHead.TR;
            meta.fiducialHead = rmfield(meta.fiducialHead, 'TR');
        end
        TRstableHead = [];
        if isfield(meta, 'stableHead') && isstruct(meta.stableHead) && ...
                isfield(meta.stableHead, 'TR') && ~isempty(meta.stableHead.TR)
            TRstableHead = meta.stableHead.TR;
            meta.stableHead = rmfield(meta.stableHead, 'TR');
        end
        ensureDir(fileparts(cacheFile));
        TRskin = TRskinCache; %#ok<NASGU>
        if ~isempty(TRfiducialHead) || ~isempty(TRstableHead)
            save(cacheFile, 'TRskin', 'TRfiducialHead', 'TRstableHead', ...
                'meta', '-v7.3');
            S = struct('TRskin', TRskinCache, ...
                'TRfiducialHead', TRfiducialHead, ...
                'TRstableHead', TRstableHead, 'meta', meta);
        else
            save(cacheFile, 'TRskin', 'meta', '-v7.3');
            S = struct('TRskin', TRskinCache, 'meta', meta);
        end
    end

    [TRskin, source] = readSkinMeshFromCacheStruct(S, source, cacheFile, opts);
    source.type = 'segmentation';
    source.t1File = t1File;
    source.subjectId = subjectId;
    source.capMakerInputFile = capInput;
    source.inputKind = inputKind;
    source.cropPlaneFile = cropPlaneFile;
    if selectingFullHead
        source.cropPlaneMode = 'notApplicable';
    else
        source.cropPlaneMode = opts.cropPlaneMode;
    end
    source.layoutFile = '';
    if ~isempty(subjectId)
        source.label = subjectId;
    else
        source.label = getFileStem(t1File);
    end
end

function [t1File, subjectId] = segmentationT1AndSubject(segOut, opts)
    subjectId = opts.subjectId;
    if isempty(subjectId) && isfield(segOut, 'subjectId') && ~isempty(segOut.subjectId)
        subjectId = char(segOut.subjectId);
    end
    if isempty(subjectId) && isfield(segOut, 'originalSubjectId') && ...
            ~isempty(segOut.originalSubjectId)
        subjectId = char(segOut.originalSubjectId);
    end

    t1File = '';
    if isfield(segOut, 'roastReady') && isstruct(segOut.roastReady) && ...
            isfield(segOut.roastReady, 't1File') && ~isempty(segOut.roastReady.t1File)
        t1File = char(segOut.roastReady.t1File);
    elseif isfield(segOut, 'activeSegmentationT1') && ...
            ~isempty(segOut.activeSegmentationT1)
        t1File = char(segOut.activeSegmentationT1);
    elseif isfield(segOut, 'segmentationT1') && ~isempty(segOut.segmentationT1)
        t1File = char(segOut.segmentationT1);
    elseif isfield(segOut, 'sourceT1') && ~isempty(segOut.sourceT1)
        t1File = char(segOut.sourceT1);
    elseif isfield(segOut, 't1File') && ~isempty(segOut.t1File)
        t1File = char(segOut.t1File);
    end
    t1File = expandUserPath(t1File);
    if isempty(t1File) || exist(t1File, 'file') ~= 2
        error('acsSelectModelFiducials:MissingSegmentationT1', ...
            'Segmentation input does not report an existing T1 file.');
    end
end

function [capInput, inputKind] = resolveCapMakerInput(t1File, opts)
    if ~isempty(opts.capMakerInputFile)
        capInput = opts.capMakerInputFile;
        inputKind = inferCapMakerInputKind(capInput);
        return;
    end
    if ~isempty(opts.dicomDir)
        capInput = opts.dicomDir;
        inputKind = 'dicom';
        return;
    end
    capInput = t1File;
    inputKind = inferCapMakerInputKind(capInput);
end

function kind = inferCapMakerInputKind(pathIn)
    if exist(pathIn, 'dir') == 7
        kind = 'dicom';
        return;
    end
    lowerPath = lower(char(pathIn));
    if endsWith(lowerPath, '.nii') || endsWith(lowerPath, '.nii.gz')
        kind = 'nifti';
    else
        kind = 'dicom';
    end
end

function capWorkDir = resolveCapWorkDir(subjectId, t1File)
    capWorkDir = '';
    if ~isempty(subjectId)
        try
            capWorkDir = acsSubjectPath(subjectId, 'capWork');
        catch
            capWorkDir = '';
        end
    end
    if ~isempty(capWorkDir)
        return;
    end
    capWorkDir = inferCapWorkDirFromT1(t1File);
end

function capWorkDir = inferCapWorkDirFromT1(t1File)
    cur = fileparts(t1File);
    for i = 1:8
        [parent, name] = fileparts(cur);
        if strcmpi(name, 'segmentation')
            capWorkDir = fullfile(parent, 'capMaker');
            return;
        end
        if isempty(parent) || strcmp(parent, cur)
            break;
        end
        cur = parent;
    end
    capWorkDir = fullfile(fileparts(t1File), 'capMaker');
end

function fileName = defaultSkinCacheFile(capWorkDir, capInput, inputKind)
    stem = capMakerInputStem(capInput, inputKind);
    fileName = fullfile(capWorkDir, [stem '_skinMesh.mat']);
end

function fileName = defaultFullHeadSkinCacheFile(capWorkDir, capInput, inputKind)
    stem = capMakerInputStem(capInput, inputKind);
    fileName = fullfile(capWorkDir, [stem '_fullHeadSkinMesh.mat']);
end

function fileName = resolveCropPlaneFile(capWorkDir, capInput, inputKind, opts)
    fileName = opts.cropPlaneFile;
    if isempty(fileName)
        stem = capMakerInputStem(capInput, inputKind);
        fileName = fullfile(capWorkDir, [stem '_cropPlane.mat']);
    elseif ~endsWith(lower(fileName), '.mat')
        fileName = [fileName '.mat'];
    end
end

function stem = capMakerInputStem(capInput, inputKind)
    if strcmp(inputKind, 'dicom')
        stem = 'dicom';
        return;
    end
    [~, stem] = fileparts(capInput);
    if endsWith(lower(stem), '.nii')
        [~, stem] = fileparts(stem);
    end
    stem = regexprep(stem, '[^a-zA-Z0-9_]', '_');
end

function [skinOpts, cropPlane] = resolveCropPlaneOptions( ...
        userSkinOpts, cropPlaneFile, capInput, inputKind, opts)
    skinOpts = userSkinOpts;
    if isempty(skinOpts)
        skinOpts = struct();
    end
    cropPlane = struct();

    switch opts.cropPlaneMode
        case 'select'
            if exist(cropPlaneFile, 'file') == 2
                cropPlane = loadCropPlane(cropPlaneFile);
                validateCropPlaneInput(cropPlane, capInput, inputKind, cropPlaneFile);
                skinOpts = applyCropPlaneDefaultsToSkinOptions(skinOpts, cropPlane);
                logMsg(opts, 'Starting from saved capMaker crop plane: %s', cropPlaneFile);
            end
            skinOpts.interactiveCrop = true;
        case {'auto', 'autoSelect', 'reuse'}
            if exist(cropPlaneFile, 'file') == 2
                cropPlane = loadCropPlane(cropPlaneFile);
                validateCropPlaneInput(cropPlane, capInput, inputKind, cropPlaneFile);
                skinOpts = applyCropPlaneToSkinOptions(skinOpts, cropPlane);
                logMsg(opts, 'Reusing saved capMaker crop plane: %s', cropPlaneFile);
            elseif strcmp(opts.cropPlaneMode, 'reuse')
                error('acsSelectModelFiducials:CropPlaneNotFound', ...
                    'Saved capMaker crop plane not found: %s', cropPlaneFile);
            elseif strcmp(opts.cropPlaneMode, 'autoSelect')
                skinOpts.interactiveCrop = true;
            end
        case 'default'
            % Keep skinMeshFromMPRAGE defaults or caller-supplied options.
        otherwise
            error('acsSelectModelFiducials:BadCropPlaneMode', ...
                'Unknown cropPlaneMode "%s".', opts.cropPlaneMode);
    end
end

function cropPlane = loadCropPlane(fileName)
    S = load(fileName, 'cropPlane');
    if ~isfield(S, 'cropPlane') || ~isstruct(S.cropPlane)
        error('acsSelectModelFiducials:BadCropPlaneFile', ...
            'Crop-plane file does not contain a cropPlane struct: %s', fileName);
    end
    cropPlane = S.cropPlane;
    validateCropPlane(cropPlane, fileName);
end

function saveCropPlane(fileName, cropPlane)
    validateCropPlane(cropPlane, fileName);
    ensureDir(fileparts(fileName));
    save(fileName, 'cropPlane');
    writeJson(replaceExtension(fileName, '.json'), jsonReady(cropPlane));
end

function cropPlane = cropPlaneFromSkinMeta(meta, capInput, inputKind)
    if ~isstruct(meta) || ~isfield(meta, 'align') || ...
            ~isfield(meta.align, 'dir') || ~isfield(meta.align, 'distance')
        error('acsSelectModelFiducials:MissingCropPlaneMeta', ...
            'skinMeshFromMPRAGE did not return the selected crop-plane metadata.');
    end
    cropPlane = struct();
    cropPlane.createdOn = char(datetime('now'));
    cropPlane.inputFile = capInput;
    cropPlane.inputKind = inputKind;
    cropPlane.cropAxis = double(meta.align.dir(:)');
    cropPlane.cropDistance = double(meta.align.distance);
    cropPlane.cropSide = char(meta.align.side);
    cropPlane.alignCrop = logical(meta.align.used);
end

function skinOpts = applyCropPlaneToSkinOptions(skinOpts, cropPlane)
    skinOpts.cropAxis = cropPlane.cropAxis;
    skinOpts.cropDistance = cropPlane.cropDistance;
    skinOpts.cropSide = cropPlane.cropSide;
    skinOpts.alignCrop = cropPlane.alignCrop;
    skinOpts.interactiveCrop = false;
end

function skinOpts = applyCropPlaneDefaultsToSkinOptions(skinOpts, cropPlane)
    if ~isfield(skinOpts, 'cropAxis') || isempty(skinOpts.cropAxis)
        skinOpts.cropAxis = cropPlane.cropAxis;
    end
    if ~isfield(skinOpts, 'cropDistance') || isempty(skinOpts.cropDistance)
        skinOpts.cropDistance = cropPlane.cropDistance;
    end
    if ~isfield(skinOpts, 'cropSide') || isempty(skinOpts.cropSide)
        skinOpts.cropSide = cropPlane.cropSide;
    end
    if ~isfield(skinOpts, 'alignCrop') || isempty(skinOpts.alignCrop)
        skinOpts.alignCrop = cropPlane.alignCrop;
    end
end

function validateCropPlane(cropPlane, fileName)
    required = {'cropAxis', 'cropDistance', 'cropSide', 'alignCrop'};
    for i = 1:numel(required)
        if ~isfield(cropPlane, required{i})
            error('acsSelectModelFiducials:BadCropPlaneFile', ...
                'Crop-plane file is missing "%s": %s', required{i}, fileName);
        end
    end
    validateattributes(cropPlane.cropAxis, {'numeric'}, ...
        {'vector', 'numel', 3, 'real', 'finite'});
    validateattributes(cropPlane.cropDistance, {'numeric'}, ...
        {'scalar', 'real', 'finite'});
    if ~any(strcmpi(char(cropPlane.cropSide), {'top', 'bottom'}))
        error('acsSelectModelFiducials:BadCropPlaneFile', ...
            'cropSide must be ''top'' or ''bottom'': %s', fileName);
    end
end

function validateCropPlaneInput(cropPlane, capInput, inputKind, fileName)
    if isfield(cropPlane, 'inputKind') && ...
            ~strcmpi(char(cropPlane.inputKind), inputKind)
        error('acsSelectModelFiducials:CropPlaneInputMismatch', ...
            'Saved crop plane input kind does not match current capMaker input: %s', fileName);
    end
    if isfield(cropPlane, 'inputFile') && ...
            ~strcmpi(normalizePath(cropPlane.inputFile), normalizePath(capInput))
        error('acsSelectModelFiducials:CropPlaneInputMismatch', ...
            'Saved crop plane was created for a different capMaker input: %s', fileName);
    end
end

function tf = cachedMeshMatchesCropPlane(meta, cropPlane)
    if isempty(fieldnames(cropPlane))
        tf = true;
        return;
    end
    tf = isstruct(meta) && isfield(meta, 'align') && ...
        isfield(meta.align, 'dir') && isfield(meta.align, 'distance') && ...
        isfield(meta.align, 'side') && ...
        max(abs(double(meta.align.dir(:)) - double(cropPlane.cropAxis(:)))) < 1e-8 && ...
        abs(double(meta.align.distance) - double(cropPlane.cropDistance)) < 1e-8 && ...
        strcmpi(char(meta.align.side), char(cropPlane.cropSide));
end

function tf = cachedMeshHasFullHead(S, meta)
    if isfield(S, 'TRfiducialHead') && ~isempty(S.TRfiducialHead)
        tf = true;
        return;
    end
    tf = isstruct(meta) && isfield(meta, 'fiducialHead') && ...
        isstruct(meta.fiducialHead) && isfield(meta.fiducialHead, 'TR') && ...
        ~isempty(meta.fiducialHead.TR);
end

function skinOpts = capMakerSkinOptions(userOpts, inputKind)
    skinOpts = userOpts;
    if isempty(skinOpts)
        skinOpts = struct();
    end
    if strcmp(inputKind, 'nifti')
        if ~isfield(skinOpts, 'permuteDims') || isempty(skinOpts.permuteDims)
            skinOpts.permuteDims = [1 2 3];
        end
        if ~isfield(skinOpts, 'flipDims') || isempty(skinOpts.flipDims)
            skinOpts.flipDims = [false false false];
        end
        if ~isfield(skinOpts, 'cropAxis') || isempty(skinOpts.cropAxis)
            skinOpts.cropAxis = [0 0.3 1];
        end
        if ~isfield(skinOpts, 'inputOrientation') || isempty(skinOpts.inputOrientation)
            skinOpts.inputOrientation = 'ras';
        end
    end
end

function skinOpts = fullHeadFiducialSkinOptions(userOpts, inputKind)
    skinOpts = capMakerSkinOptions(userOpts, inputKind);
    skinOpts.makeFullHeadMesh = true;
    skinOpts.interactiveCrop = false;
    skinOpts.alignCrop = false;
    skinOpts.centerXY = false;
    skinOpts.dropToZ0 = false;
    if ~isfield(skinOpts, 'fullHeadDecimate') || isempty(skinOpts.fullHeadDecimate)
        skinOpts.fullHeadDecimate = 35000;
    end
end


function tf = isSkinCacheStruct(S)
    tf = isfield(S, 'TRskin') || isfield(S, 'TRskinCache') || ...
        isfield(S, 'TRfiducialHead');
end

function [TRskin, source] = readSkinMeshFromCacheStruct(S, source, cacheFile, opts)
    source.type = 'skinCache';
    source.file = cacheFile;
    source.label = getFileStem(cacheFile);
    source.meshStage = opts.meshStage;
    source.coordinateFrame = skinCacheCoordinateFrame(S, opts.meshStage);

    switch opts.meshStage
        case 'fullHead'
            if isfield(S, 'TRfiducialHead') && ~isempty(S.TRfiducialHead)
                TRskin = S.TRfiducialHead;
                source.modelType = 'capMakerFullHeadMesh';
                return;
            end
            if isfield(S, 'meta') && isstruct(S.meta) && ...
                    isfield(S.meta, 'fiducialHead') && ...
                    isfield(S.meta.fiducialHead, 'TR') && ...
                    ~isempty(S.meta.fiducialHead.TR)
                TRskin = S.meta.fiducialHead.TR;
                source.modelType = 'capMakerFullHeadMesh';
                return;
            end
            error('acsSelectModelFiducials:MissingFullHeadMesh', ...
                ['Skin cache does not contain TRfiducialHead: %s\n', ...
                 'Rerun acsSelectModelFiducials with forceSkinMesh=true, ', ...
                 'or rerun the capMaker layout step so the cache is rebuilt ', ...
                 'with the full-head fiducial mesh. You can also call with ', ...
                 'meshStage=''cap'' for non-anatomical points.'], cacheFile);
        otherwise
            if isfield(S, 'TRskin')
                TRskin = S.TRskin;
            elseif isfield(S, 'TRskinCache')
                TRskin = S.TRskinCache;
            else
                error('acsSelectModelFiducials:BadSkinCache', ...
                    'Skin cache does not contain TRskin: %s', cacheFile);
            end
            source.modelType = 'capMakerCroppedCapMesh';
    end
end

function frame = skinCacheCoordinateFrame(S, meshStage)
    frame = 'capMakerPrintMm';
    if ~isfield(S, 'meta') || ~isstruct(S.meta)
        return;
    end
    meta = S.meta;
    if ~strcmp(meshStage, 'fullHead')
        return;
    end
    alignIdentity = true;
    printIdentity = true;
    if isfield(meta, 'align') && isstruct(meta.align) && ...
            isfield(meta.align, 'R') && ~isempty(meta.align.R)
        alignIdentity = max(abs(double(meta.align.R(:)) - eyeVector())) < 1e-8;
    end
    if isfield(meta, 'print') && isstruct(meta.print) && ...
            isfield(meta.print, 'T_world2print') && ~isempty(meta.print.T_world2print)
        printIdentity = max(abs(double(meta.print.T_world2print(:)) - eye4Vector())) < 1e-8;
    end
    if alignIdentity && printIdentity
        frame = 'capMakerPreCropWorldMm';
    end
end

function v = eyeVector()
    v = eye(3);
    v = v(:);
end

function v = eye4Vector()
    v = eye(4);
    v = v(:);
end

function value = firstStruct(S)
    preferred = {'out', 'outSaved', 'outToSave', 'segOut', ...
        'combinedLayout', 'layout'};
    for i = 1:numel(preferred)
        if isfield(S, preferred{i}) && isstruct(S.(preferred{i}))
            value = S.(preferred{i});
            return;
        end
    end
    names = fieldnames(S);
    for i = 1:numel(names)
        if isstruct(S.(names{i}))
            value = S.(names{i});
            return;
        end
    end
    error('acsSelectModelFiducials:NoStructInMat', ...
        'MAT file does not contain a layout or skin mesh cache.');
end

function [selection, accepted, fig] = selectFiducialsGui(TRskin, source, selection, opts)
    V = double(TRskin.Points);
    F = double(TRskin.ConnectivityList);
    displayMesh = decimateMeshForDisplay(F, V, opts.displayMaxFaces);
    n = numel(selection.labels);
    active = firstUnset(selection);
    accepted = false;
    dragStart = [];
    isWaiting = false;

    fig = figure( ...
        'Name', 'Select model fiducials', ...
        'NumberTitle', 'off', ...
        'Color', 'w', ...
        'ToolBar', 'figure', ...
        'MenuBar', 'figure', ...
        'CloseRequestFcn', @onCloseRequest);
    ax = axes('Parent', fig, 'Position', [0.03 0.08 0.72 0.86], ...
        'Tag', 'modelFiducialMainAxes');
    hold(ax, 'on');
    patch(ax, ...
        'Faces', displayMesh.faces, ...
        'Vertices', displayMesh.vertices, ...
        'FaceColor', [0.84 0.87 0.92], ...
        'EdgeColor', 'none', ...
        'FaceAlpha', opts.meshAlpha, ...
        'FaceLighting', opts.meshLighting, ...
        'BackFaceLighting', 'reverselit', ...
        'AmbientStrength', 0.45, ...
        'DiffuseStrength', 0.55, ...
        'SpecularStrength', 0.05);
    markerHandles = gobjects(n, 1);
    textHandles = gobjects(n, 1);
    for i = 1:n
        markerHandles(i) = scatter3(ax, nan, nan, nan, 100, ...
            [0.9 0.2 0.1], 'filled', 'MarkerEdgeColor', 'k', 'LineWidth', 1.0);
        textHandles(i) = text(ax, nan, nan, nan, '', ...
            'FontWeight', 'bold', 'Color', [0.05 0.05 0.05], ...
            'BackgroundColor', 'w', 'Margin', 1);
    end
    axis(ax, 'vis3d');
    axis(ax, 'equal');
    axis(ax, 'off');
    setInitialFiducialView(ax, V);
    cameraLight = camlight(ax, 'headlight');
    lighting(ax, opts.meshLighting);

    labelPopup = uicontrol(fig, ...
        'Style', 'popupmenu', ...
        'String', selection.labels, ...
        'Units', 'normalized', ...
        'Position', [0.78 0.86 0.18 0.05], ...
        'Value', active, ...
        'Callback', @onLabelPopup);
    status = uicontrol(fig, ...
        'Style', 'text', ...
        'Units', 'normalized', ...
        'Position', [0.77 0.43 0.21 0.40], ...
        'BackgroundColor', 'w', ...
        'HorizontalAlignment', 'left', ...
        'FontSize', 10);
    uicontrol(fig, ...
        'Style', 'pushbutton', ...
        'String', 'Previous', ...
        'Units', 'normalized', ...
        'Position', [0.78 0.34 0.085 0.055], ...
        'Callback', @onPrevious);
    uicontrol(fig, ...
        'Style', 'pushbutton', ...
        'String', 'Next', ...
        'Units', 'normalized', ...
        'Position', [0.875 0.34 0.085 0.055], ...
        'Callback', @onNext);
    uicontrol(fig, ...
        'Style', 'pushbutton', ...
        'String', 'Clear active', ...
        'Units', 'normalized', ...
        'Position', [0.78 0.27 0.18 0.055], ...
        'Callback', @onClearActive);
    uicontrol(fig, ...
        'Style', 'pushbutton', ...
        'String', 'Done', ...
        'Units', 'normalized', ...
        'Position', [0.78 0.17 0.18 0.07], ...
        'Callback', @onDone);
    uicontrol(fig, ...
        'Style', 'pushbutton', ...
        'String', 'Cancel', ...
        'Units', 'normalized', ...
        'Position', [0.78 0.07 0.18 0.06], ...
        'Callback', @onCancel);

    updateGraphics();
    if opts.verbose
        fprintf('\nModel fiducial selection controls:\n');
        fprintf('  Shift-click mesh: set active fiducial on the visible surface under the cursor\n');
        fprintf('  drag: rotate view\n');
        fprintf('  N/P or right/left arrows: next/previous fiducial\n');
        fprintf('  X/Y/Z: canonical views; Delete/C: clear active fiducial\n');
    end

    set(fig, ...
        'WindowButtonDownFcn', @onMouseDown, ...
        'WindowButtonUpFcn', @onMouseUp, ...
        'WindowKeyPressFcn', @onKeyPress);
    isWaiting = true;
    uiwait(fig);
    isWaiting = false;

    function onLabelPopup(~, ~)
        active = get(labelPopup, 'Value');
        updateGraphics();
    end

    function onPrevious(~, ~)
        active = max(1, active - 1);
        set(labelPopup, 'Value', active);
        updateGraphics();
    end

    function onNext(~, ~)
        active = min(n, active + 1);
        set(labelPopup, 'Value', active);
        updateGraphics();
    end

    function onClearActive(~, ~)
        selection.coordinatesMm(active, :) = nan(1, 3);
        selection.selectedVertex(active) = nan;
        updateGraphics();
    end

    function onMouseDown(~, ~)
        clickedAxes = ancestor(hittest(fig), 'axes');
        if isempty(clickedAxes) || clickedAxes ~= ax
            return;
        end
        modifiers = get(fig, 'CurrentModifier');
        if hasAnyModifier(modifiers, {'shift'})
            setActiveFromClick();
            return;
        end
        dragStart = get(fig, 'CurrentPoint');
        set(fig, 'WindowButtonMotionFcn', @onDrag);
    end

    function setActiveFromClick()
        [rayOrigin, rayDirection] = clickRay(ax);
        [point, ~] = firstMeshRayIntersection(displayMesh.faces, ...
            displayMesh.vertices, rayOrigin, rayDirection);
        if isempty(point)
            [point, vertex] = closestVertexToRay(V, rayOrigin, rayDirection);
        else
            vertex = closestVertexToPoint(V, point);
        end
        selection.coordinatesMm(active, :) = point;
        selection.selectedVertex(active) = vertex;
        if active < n
            active = active + 1;
            set(labelPopup, 'Value', active);
        end
        updateGraphics();
    end

    function onDrag(~, ~)
        pointer = get(fig, 'CurrentPoint');
        delta = pointer - dragStart;
        dragStart = pointer;
        camorbit(ax, -0.35 * delta(1), -0.35 * delta(2), 'camera');
        camlight(cameraLight, 'headlight');
        drawnow limitrate;
    end

    function onMouseUp(~, ~)
        dragStart = [];
        set(fig, 'WindowButtonMotionFcn', '');
    end

    function onKeyPress(~, event)
        switch lower(event.Key)
            case {'n', 'rightarrow'}
                onNext([], []);
            case {'p', 'leftarrow'}
                onPrevious([], []);
            case {'delete', 'backspace', 'c'}
                onClearActive([], []);
            case 'x'
                setCanonicalView([1 0 0], [0 0 1]);
            case 'y'
                setCanonicalView([0 1 0], [0 0 1]);
            case 'z'
                setCanonicalView([0 0 1], [0 1 0]);
            case 'return'
                onDone([], []);
        end
    end

    function setCanonicalView(axisDirection, upDirection)
        anchor = mean(V, 1);
        cameraDistance = norm(campos(ax) - camtarget(ax));
        if ~isfinite(cameraDistance) || cameraDistance <= 0
            cameraDistance = 1.5 * norm(max(V, [], 1) - min(V, [], 1));
        end
        camtarget(ax, anchor);
        campos(ax, anchor + cameraDistance * axisDirection);
        camup(ax, upDirection);
        camlight(cameraLight, 'headlight');
    end

    function onDone(~, ~)
        missing = selection.labels(any(~isfinite(selection.coordinatesMm), 2));
        if ~isempty(missing)
            answer = questdlg(sprintf( ...
                'Missing fiducials: %s\n\nSave anyway?', strjoin(missing, ', ')), ...
                'Missing model fiducials', 'Save anyway', 'Continue editing', ...
                'Continue editing');
            if ~strcmp(answer, 'Save anyway')
                return;
            end
        end
        accepted = true;
        resumeOrDeleteFigure();
    end

    function onCancel(~, ~)
        accepted = false;
        resumeOrDeleteFigure();
    end

    function onCloseRequest(~, ~)
        accepted = false;
        resumeOrDeleteFigure();
    end

    function resumeOrDeleteFigure()
        if ~isgraphics(fig)
            return;
        end
        if isWaiting
            uiresume(fig);
        else
            delete(fig);
        end
    end

    function updateGraphics()
        for j = 1:n
            p = selection.coordinatesMm(j, :);
            if all(isfinite(p))
                set(markerHandles(j), 'XData', p(1), 'YData', p(2), ...
                    'ZData', p(3), 'SizeData', 100 + 70 * (j == active), ...
                    'MarkerFaceColor', markerColor(j == active));
                set(textHandles(j), 'Position', p + [2 0 2], ...
                    'String', selection.labels{j}, 'Visible', 'on');
            else
                set(markerHandles(j), 'XData', nan, 'YData', nan, 'ZData', nan);
                set(textHandles(j), 'Visible', 'off');
            end
        end
        set(status, 'String', statusText(source, selection, active));
        title(ax, sprintf('Shift-click %s on %s mesh', ...
            selection.labels{active}, source.meshStage), ...
            'Interpreter', 'none');
        drawnow limitrate;
    end
end

function color = markerColor(isActive)
    if isActive
        color = [1.0 0.75 0.05];
    else
        color = [0.9 0.2 0.1];
    end
end

function textOut = statusText(source, selection, active)
    isSet = all(isfinite(selection.coordinatesMm), 2);
    if isSet(active)
        coordText = sprintf('[%.1f %.1f %.1f] mm', selection.coordinatesMm(active, :));
    else
        coordText = '(not set)';
    end
    textOut = sprintf(['Model: %s\nMesh: %s\nFrame: %s\n\nActive: %s\n%s\n\n', ...
        'Selected: %d / %d\n\nShift-click places active fiducial on the visible surface.\n', ...
        'Drag rotates view.'], ...
        source.label, source.meshStage, source.coordinateFrame, ...
        selection.labels{active}, coordText, nnz(isSet), numel(isSet));
end

function idx = firstUnset(selection)
    idx = find(any(~isfinite(selection.coordinatesMm), 2), 1);
    if isempty(idx)
        idx = 1;
    end
end

function out = buildOutput(selection, source, opts, fig)
    out = struct();
    out.createdOn = char(datetime('now'));
    out.labels = selection.labels(:);
    out.coordinatesMm = double(selection.coordinatesMm);
    out.selectedVertex = double(selection.selectedVertex(:));
    out.coordinateFrame = source.coordinateFrame;
    if isfield(source, 'modelType') && ~isempty(source.modelType)
        out.modelType = source.modelType;
    else
        out.modelType = 'modelMesh';
    end
    out.meshStage = opts.meshStage;
    out.source = source;
    out.options = opts;
    out.figure = fig;
    out.qcFile = '';
end

function out = loadExisting(fileName)
    S = load(fileName);
    if isfield(S, 'out')
        out = S.out;
    elseif isfield(S, 'outSaved')
        out = S.outSaved;
    else
        out = firstStruct(S);
    end
end

function stripped = stripFigure(S)
    stripped = S;
    if isfield(stripped, 'figure')
        stripped.figure = [];
    end
end

function mesh = decimateMeshForDisplay(F, V, maxFaces)
    mesh.faces = double(F);
    mesh.vertices = double(V);
    if maxFaces > 0 && size(mesh.faces, 1) > maxFaces
        [mesh.faces, mesh.vertices] = reducepatch(mesh.faces, mesh.vertices, maxFaces);
        mesh.faces = double(mesh.faces);
        mesh.vertices = double(mesh.vertices);
    end
    mesh.faces = orientFacesForDisplay(mesh.faces, mesh.vertices);
end

function F = orientFacesForDisplay(F, V)
    if isempty(F) || isempty(V)
        return;
    end
    try
        if exist('unifyOutwardNormalsRobust', 'file') == 2
            TR = unifyOutwardNormalsRobust(triangulation(F, V));
            F = double(TR.ConnectivityList);
            return;
        end
    catch
        % Fall through to a display-only centroid heuristic.
    end

    center = mean(V, 1);
    v1 = V(F(:, 1), :);
    v2 = V(F(:, 2), :);
    v3 = V(F(:, 3), :);
    normals = cross(v2 - v1, v3 - v1, 2);
    faceCenters = (v1 + v2 + v3) / 3;
    outward = faceCenters - center;
    flip = sum(normals .* outward, 2) < 0;
    F(flip, [2 3]) = F(flip, [3 2]);
end

function [point, vertex] = closestVertexToRay(V, rayOrigin, rayDirection)
    rel = bsxfun(@minus, V, rayOrigin);
    proj = rel * rayDirection(:);
    closest = bsxfun(@plus, rayOrigin, proj .* rayDirection);
    d2 = sum((V - closest) .^ 2, 2);
    [~, vertex] = min(d2);
    point = V(vertex, :);
end

function [point, faceIdx] = firstMeshRayIntersection(F, V, rayOrigin, rayDirection)
    point = [];
    faceIdx = nan;
    if isempty(F) || isempty(V)
        return;
    end

    F = double(F);
    V = double(V);
    rayOrigin = double(rayOrigin(:))';
    rayDirection = double(rayDirection(:))';
    rayDirection = rayDirection ./ max(norm(rayDirection), eps);

    v0 = V(F(:, 1), :);
    v1 = V(F(:, 2), :);
    v2 = V(F(:, 3), :);
    e1 = v1 - v0;
    e2 = v2 - v0;
    pvec = cross(repmat(rayDirection, size(e2, 1), 1), e2, 2);
    detVal = sum(e1 .* pvec, 2);
    detTol = 1e-10;
    nonparallel = abs(detVal) > detTol;
    if ~any(nonparallel)
        return;
    end

    invDet = zeros(size(detVal));
    invDet(nonparallel) = 1 ./ detVal(nonparallel);
    tvec = bsxfun(@minus, rayOrigin, v0);
    u = sum(tvec .* pvec, 2) .* invDet;
    qvec = cross(tvec, e1, 2);
    v = sum(repmat(rayDirection, size(qvec, 1), 1) .* qvec, 2) .* invDet;
    t = sum(e2 .* qvec, 2) .* invDet;

    epsBary = 1e-8;
    hit = nonparallel & t > detTol & ...
        u >= -epsBary & v >= -epsBary & (u + v) <= 1 + epsBary;
    if ~any(hit)
        return;
    end
    tHit = t;
    tHit(~hit) = Inf;
    [~, faceIdx] = min(tHit);
    point = rayOrigin + t(faceIdx) .* rayDirection;
end

function vertex = closestVertexToPoint(V, point)
    d2 = sum((double(V) - double(point)) .^ 2, 2);
    [~, vertex] = min(d2);
end

function [origin, direction] = clickRay(ax)
    cp = get(ax, 'CurrentPoint');
    origin = cp(1, :);
    direction = cp(2, :) - cp(1, :);
    n = norm(direction);
    if n <= eps
        direction = [0 0 1];
    else
        direction = direction ./ n;
    end
end

function setInitialFiducialView(ax, V)
    V = double(V);
    anchor = mean(V, 1);
    span = max(V, [], 1) - min(V, [], 1);
    cameraDistance = 3.0 * norm(span);
    if ~isfinite(cameraDistance) || cameraDistance <= 0
        cameraDistance = 250;
    end

    % capMaker convention for this workflow: -X left, +Y rostral, +Z dorsal.
    viewDirection = normalizeRow([-1 1 0.75]);
    camtarget(ax, anchor);
    campos(ax, anchor + cameraDistance * viewDirection);
    camup(ax, [0 0 1]);
    camva(ax, 12);
end

function tf = hasAnyModifier(modifiers, names)
    if isempty(modifiers)
        tf = false;
        return;
    end
    if ischar(modifiers)
        modifiers = {modifiers};
    end
    tf = any(ismember(lower(modifiers), lower(names)));
end

function row = normalizeRow(row)
    row = double(row(:))';
    n = norm(row);
    if n > eps && all(isfinite(row))
        row = row ./ n;
    end
end

function fileName = defaultOutputFile(source, labels)
    labelText = strjoin(labels(:)', '_');
    labelText = regexprep(labelText, '[^A-Za-z0-9_]+', '');
    if isempty(labelText)
        labelText = 'fiducials';
    end
    if ~isempty(source.file)
        folder = fileparts(source.file);
        stem = getFileStem(source.file);
    elseif ~isempty(source.t1File)
        folder = fullfile(fileparts(source.t1File), '..', 'capMaker');
        stem = getFileStem(source.t1File);
    else
        folder = pwd;
        stem = 'model';
    end
    fileName = fullfile(folder, [stem '_' source.meshStage ...
        '_modelFiducials_' labelText '.mat']);
end

function qcFiles = saveQcFigure(fig, fileStem, TRskin, out, opts)
    cameraState = captureCameraState(fig);
    fig2 = figure('Visible', 'off', 'Color', 'w');
    ax = axes('Parent', fig2);
    V = double(TRskin.Points);
    F = double(TRskin.ConnectivityList);
    displayMesh = decimateMeshForDisplay(F, V, opts.displayMaxFaces);
    patch(ax, 'Faces', displayMesh.faces, 'Vertices', displayMesh.vertices, ...
        'FaceColor', [0.85 0.88 0.94], 'EdgeColor', 'none', ...
        'FaceAlpha', 1, 'FaceLighting', 'flat', ...
        'BackFaceLighting', 'reverselit', 'AmbientStrength', 0.45, ...
        'DiffuseStrength', 0.55, 'SpecularStrength', 0.05);
    hold(ax, 'on');
    isSet = all(isfinite(out.coordinatesMm), 2);
    coords = out.coordinatesMm(isSet, :);
    labels = out.labels(isSet);
    scatter3(ax, coords(:, 1), coords(:, 2), coords(:, 3), 80, ...
        [0.9 0.2 0.1], 'filled', 'MarkerEdgeColor', 'k', 'LineWidth', 1.0);
    span = max(V, [], 1) - min(V, [], 1);
    labelOffset = 0.018 * max(norm(span), 1) * normalizeRow([1 1 0.4]);
    for i = 1:numel(labels)
        p = coords(i, :) + labelOffset;
        text(ax, p(1), p(2), p(3), labels{i}, ...
            'FontWeight', 'bold', 'Color', [0.05 0.05 0.05], ...
            'BackgroundColor', 'w', 'Margin', 1, 'Interpreter', 'none');
    end
    axis(ax, 'equal');
    axis(ax, 'vis3d');
    axis(ax, 'off');
    if isempty(cameraState)
        setInitialFiducialView(ax, V);
    else
        applyCameraState(ax, cameraState);
    end
    camlight(ax, 'headlight');
    lighting(ax, 'flat');
    qcFiles = acsExportFigure(fig2, fileStem, opts.figureExportOptions);
    close(fig2);
end

function state = captureCameraState(fig)
    state = [];
    if ~isgraphics(fig)
        return;
    end
    ax = findobj(fig, 'Type', 'axes', 'Tag', 'modelFiducialMainAxes');
    if isempty(ax) || ~isgraphics(ax(1))
        return;
    end
    ax = ax(1);
    state = struct( ...
        'CameraPosition', get(ax, 'CameraPosition'), ...
        'CameraTarget', get(ax, 'CameraTarget'), ...
        'CameraUpVector', get(ax, 'CameraUpVector'), ...
        'CameraViewAngle', get(ax, 'CameraViewAngle'));
end

function applyCameraState(ax, state)
    set(ax, ...
        'CameraPosition', state.CameraPosition, ...
        'CameraTarget', state.CameraTarget, ...
        'CameraUpVector', state.CameraUpVector, ...
        'CameraViewAngle', state.CameraViewAngle);
end

function saveModelFiducialReport(fileName, outSaved)
    out = outSaved; %#ok<NASGU>
    outForSave = outSaved; %#ok<NASGU>
    outToSave = outSaved; %#ok<NASGU>
    save(fileName, 'out', 'outSaved', 'outForSave', 'outToSave');
end

function writeJson(fileName, S)
    fid = fopen(fileName, 'wt');
    if fid < 0
        error('acsSelectModelFiducials:CouldNotWriteJson', ...
            'Could not write %s', fileName);
    end
    cleaner = onCleanup(@() fclose(fid));
    try
        txt = jsonencode(S, 'PrettyPrint', true);
    catch
        txt = jsonencode(S);
    end
    fprintf(fid, '%s', txt);
    clear cleaner;
end

function S = jsonReady(S)
    if isstruct(S)
        for k = 1:numel(S)
            names = fieldnames(S(k));
            for i = 1:numel(names)
                S(k).(names{i}) = jsonReady(S(k).(names{i}));
            end
        end
    elseif iscell(S)
        for i = 1:numel(S)
            S{i} = jsonReady(S{i});
        end
    elseif isa(S, 'matlab.ui.Figure')
        S = char(class(S));
    end
end

function ensureDir(folder)
    if isempty(folder), return; end
    if exist(folder, 'dir') ~= 7
        mkdir(folder);
    end
end

function fileName = replaceExtension(fileName, newExt)
    [folder, stem] = fileparts(fileName);
    fileName = fullfile(folder, [stem newExt]);
end

function stem = getFileStem(fileName)
    [~, stem] = fileparts(char(fileName));
end

function logMsg(opts, varargin)
    if opts.verbose
        fprintf([varargin{1} '\n'], varargin{2:end});
    end
end

function pathOut = expandUserPath(pathOut)
    if isempty(pathOut)
        return;
    end
    pathOut = char(pathOut);
    if startsWith(pathOut, '~')
        homeDir = getenv('HOME');
        if isempty(homeDir)
            homeDir = getenv('USERPROFILE');
        end
        if numel(pathOut) == 1
            pathOut = homeDir;
        elseif pathOut(2) == filesep || pathOut(2) == '/' || pathOut(2) == '\'
            pathOut = fullfile(homeDir, pathOut(3:end));
        end
    end
end

function value = normalizePath(value)
    value = expandUserPath(char(value));
    if isempty(value)
        return;
    end
    try
        if exist(value, 'file') == 2 || exist(value, 'dir') == 7
            value = char(java.io.File(value).getCanonicalPath());
        end
    catch
        value = char(value);
    end
    value = lower(strrep(value, '/', filesep));
end
