function out = acsCapMakerPrintToMriFrame(pointsOrRegistration, modelSource, varargin)
% ACSCAPMAKERPRINTTOMRIFRAME Convert capMaker print-frame points to MRI frame.
%
% out = acsCapMakerPrintToMriFrame(pointsPrintMm, modelFiducials)
% uses the capMaker skin-mesh metadata associated with modelFiducials to map
% capMaker print-frame millimeter coordinates back through the print
% translation and crop-plane alignment into the input MRI frame.
%
% out = acsCapMakerPrintToMriFrame(registration)
% accepts an acsRegisterPolhemusFiducials output and converts its
% transformedSourcePointsMm when the registration target reports a skin mesh
% cache file.
%
% Name-value options:
%   labels     : point labels [{}]
%   outputFile : optional MAT report ['']
%   verbose    : print summary [true]

    if nargin < 1 || isempty(pointsOrRegistration)
        error('acsCapMakerPrintToMriFrame:MissingInput', ...
            'Provide capMaker print-frame points or a registration struct.');
    end
    if nargin < 2
        modelSource = [];
    elseif isNameValueStart(modelSource)
        varargin = [{modelSource}, varargin];
        modelSource = [];
    end

    opts = parseInputs(varargin{:});
    [pointsPrintMm, labels, resolvedSource, objectsPrint] = resolvePoints( ...
        pointsOrRegistration, modelSource, opts);
    [meta, skinSource] = readSkinMeta(resolvedSource);

    finalWorldMm = applyAffineToPoints(meta.print.T_print2world, pointsPrintMm);
    mriWorldMm = (meta.align.R \ finalWorldMm')';
    mriVoxel0 = applyAffineToPoints(inv(meta.original.vox2world), mriWorldMm);
    mriVoxel1 = mriVoxel0 + 1;

    out = struct();
    out.createdOn = char(datetime('now'));
    out.labels = labels(:);
    out.printCoordinatesMm = pointsPrintMm;
    out.finalWorldCoordinatesMm = finalWorldMm;
    out.mriWorldCoordinatesMm = mriWorldMm;
    out.mriVoxel0 = mriVoxel0;
    out.mriVoxel1 = mriVoxel1;
    out.objects = convertObjects(objectsPrint, meta);
    out.coordinateFrames = struct( ...
        'printCoordinatesMm', 'capMakerPrintMm', ...
        'finalWorldCoordinatesMm', 'capMakerPostCropWorldMm', ...
        'mriWorldCoordinatesMm', 'inputMriWorldMm', ...
        'mriVoxel0', 'zeroBasedInputMriVoxel', ...
        'mriVoxel1', 'oneBasedInputMriVoxel');
    out.skinSource = skinSource;
    out.skinMetaSummary = summarizeMeta(meta);

    if ~isempty(opts.outputFile)
        saveReport(out, opts.outputFile);
    end
    if opts.verbose
        printSummary(out);
    end
end

function opts = parseInputs(varargin)
    p = inputParser;
    p.FunctionName = 'acsCapMakerPrintToMriFrame';
    addParameter(p, 'labels', {}, @(x) iscell(x) || isstring(x) || ischar(x));
    addParameter(p, 'outputFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'verbose', true, @isBoolLike);
    parse(p, varargin{:});

    opts = p.Results;
    opts.labels = normalizeLabelCell(opts.labels);
    opts.outputFile = expandUserPath(char(opts.outputFile));
    opts.verbose = logical(opts.verbose);
end

function tf = isBoolLike(x)
    tf = (islogical(x) || isnumeric(x)) && isscalar(x);
end

function tf = isNameValueStart(x)
    if ~(ischar(x) || isstring(x)) || numel(string(x)) ~= 1
        tf = false;
        return;
    end
    tf = any(strcmpi(char(x), {'labels', 'outputFile', 'verbose'}));
end

function [pointsPrintMm, labels, modelSource, objectsPrint] = resolvePoints( ...
        value, modelSource, opts)
    labels = opts.labels;
    objectsPrint = emptyObjects();
    if isstruct(value) && isfield(value, 'transformedSourcePointsMm')
        pointsPrintMm = double(value.transformedSourcePointsMm);
        if isempty(labels) && isfield(value, 'sourceLabels')
            labels = normalizeLabelCell(value.sourceLabels);
        end
        if isempty(modelSource) && isfield(value, 'target')
            modelSource = value.target;
        end
        if isfield(value, 'registeredObjects')
            objectsPrint = value.registeredObjects;
        end
    elseif isstruct(value) && isfield(value, 'coordinatesMm')
        pointsPrintMm = double(value.coordinatesMm);
        if isempty(labels) && isfield(value, 'labels')
            labels = normalizeLabelCell(value.labels);
        end
        if isempty(modelSource) && isfield(value, 'source')
            modelSource = value;
        end
    else
        pointsPrintMm = double(value);
    end

    if size(pointsPrintMm, 2) ~= 3
        error('acsCapMakerPrintToMriFrame:BadPoints', ...
            'Points must be an N x 3 matrix.');
    end
    if isempty(labels)
        labels = defaultLabels(size(pointsPrintMm, 1));
    elseif numel(labels) ~= size(pointsPrintMm, 1)
        error('acsCapMakerPrintToMriFrame:BadLabels', ...
            'labels must match the number of points.');
    end
end

function objects = emptyObjects()
    objects = repmat(struct( ...
        'name', '', ...
        'labels', {{}}, ...
        'rows', [], ...
        'printCoordinatesMm', [], ...
        'finalWorldCoordinatesMm', [], ...
        'mriWorldCoordinatesMm', [], ...
        'mriVoxel0', [], ...
        'mriVoxel1', []), 0, 1);
end

function objects = convertObjects(objectsPrint, meta)
    objects = emptyObjects();
    if isempty(objectsPrint) || ~isstruct(objectsPrint)
        return;
    end
    for i = 1:numel(objectsPrint)
        coords = [];
        if isfield(objectsPrint(i), 'transformedCoordinatesMm') && ...
                ~isempty(objectsPrint(i).transformedCoordinatesMm)
            coords = double(objectsPrint(i).transformedCoordinatesMm);
        elseif isfield(objectsPrint(i), 'coordinatesMm') && ...
                ~isempty(objectsPrint(i).coordinatesMm)
            coords = double(objectsPrint(i).coordinatesMm);
        end
        if isempty(coords)
            continue;
        end
        obj = emptyObjects();
        obj(1).name = getObjectField(objectsPrint(i), 'name', sprintf('object%d', i));
        if isfield(objectsPrint(i), 'labels') && ~isempty(objectsPrint(i).labels)
            obj(1).labels = normalizeLabelCell(objectsPrint(i).labels);
        else
            obj(1).labels = defaultLabels(size(coords, 1));
        end
        if isfield(objectsPrint(i), 'rows')
            obj(1).rows = objectsPrint(i).rows;
        end
        obj(1).printCoordinatesMm = coords;
        obj(1).finalWorldCoordinatesMm = applyAffineToPoints( ...
            meta.print.T_print2world, coords);
        obj(1).mriWorldCoordinatesMm = ...
            (meta.align.R \ obj(1).finalWorldCoordinatesMm')';
        obj(1).mriVoxel0 = applyAffineToPoints( ...
            inv(meta.original.vox2world), obj(1).mriWorldCoordinatesMm);
        obj(1).mriVoxel1 = obj(1).mriVoxel0 + 1;
        objects(end + 1, 1) = obj; %#ok<AGROW>
    end
end

function value = getObjectField(S, fieldName, fallback)
    if isfield(S, fieldName) && ~isempty(S.(fieldName))
        value = char(S.(fieldName));
    else
        value = fallback;
    end
end

function [meta, source] = readSkinMeta(value)
    cacheFile = resolveSkinCacheFile(value);
    if exist(cacheFile, 'file') ~= 2
        error('acsCapMakerPrintToMriFrame:SkinCacheNotFound', ...
            'Skin mesh cache not found: %s', cacheFile);
    end
    S = load(cacheFile, 'meta');
    if ~isfield(S, 'meta')
        Sfull = load(cacheFile);
        try
            [meta, source] = readSkinMeta(firstStruct(Sfull));
            source.modelReportFile = cacheFile;
            return;
        catch
            error('acsCapMakerPrintToMriFrame:MissingMeta', ...
                'Skin mesh cache does not contain meta: %s', cacheFile);
        end
    end
    meta = S.meta;
    validateSkinMeta(meta, cacheFile);
    source = struct('skinCacheFile', cacheFile);
end

function cacheFile = resolveSkinCacheFile(value)
    cacheFile = '';
    if ischar(value) || isstring(value)
        cacheFile = expandUserPath(char(value));
        return;
    end
    if ~isstruct(value)
        error('acsCapMakerPrintToMriFrame:MissingSkinSource', ...
            'Provide a model fiducial report, layout, or skin cache file.');
    end

    if isfield(value, 'source') && isstruct(value.source) && ...
            isfield(value.source, 'file') && ~isempty(value.source.file)
        cacheFile = char(value.source.file);
    elseif isfield(value, 'file') && ~isempty(value.file)
        cacheFile = char(value.file);
    elseif isfield(value, 'target') && isstruct(value.target)
        cacheFile = resolveSkinCacheFile(value.target);
        return;
    elseif isfield(value, 'layout') && isstruct(value.layout) && ...
            isfield(value.layout, 'skin') && isfield(value.layout.skin, 'cacheFile')
        cacheFile = char(value.layout.skin.cacheFile);
    elseif isfield(value, 'skin') && isstruct(value.skin) && ...
            isfield(value.skin, 'cacheFile')
        cacheFile = char(value.skin.cacheFile);
    end

    if isempty(cacheFile)
        error('acsCapMakerPrintToMriFrame:MissingSkinSource', ...
            'Could not find a capMaker skin cache file in the provided source.');
    end
end

function value = firstStruct(S)
    preferred = {'out', 'outSaved', 'outToSave', 'registration', 'modelFiducials'};
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
    error('acsCapMakerPrintToMriFrame:NoStructInMat', ...
        'MAT file does not contain a readable struct.');
end

function validateSkinMeta(meta, cacheFile)
    requiredTop = {'print', 'align', 'original'};
    for i = 1:numel(requiredTop)
        if ~isfield(meta, requiredTop{i}) || ~isstruct(meta.(requiredTop{i}))
            error('acsCapMakerPrintToMriFrame:BadSkinMeta', ...
                'Skin meta is missing "%s": %s', requiredTop{i}, cacheFile);
        end
    end
    if ~isfield(meta.print, 'T_print2world') || ...
            ~isfield(meta.align, 'R') || ...
            ~isfield(meta.original, 'vox2world')
        error('acsCapMakerPrintToMriFrame:BadSkinMeta', ...
            'Skin meta is missing transform fields: %s', cacheFile);
    end
end

function summary = summarizeMeta(meta)
    summary = struct();
    summary.units = getFieldOr(meta, 'units', 'mm');
    summary.inputOrientation = '';
    summary.originalSize = [];
    summary.originalVoxelSize = [];
    summary.alignUsed = false;
    if isfield(meta, 'original')
        summary.inputOrientation = getFieldOr(meta.original, 'orientation', '');
        summary.originalSize = getFieldOr(meta.original, 'size', []);
        summary.originalVoxelSize = getFieldOr(meta.original, 'voxelSize', []);
    end
    if isfield(meta, 'align')
        summary.alignUsed = getFieldOr(meta.align, 'used', false);
        summary.alignDir = getFieldOr(meta.align, 'dir', []);
        summary.alignSide = getFieldOr(meta.align, 'side', '');
    end
end

function value = getFieldOr(S, fieldName, fallback)
    if isfield(S, fieldName) && ~isempty(S.(fieldName))
        value = S.(fieldName);
    else
        value = fallback;
    end
end

function pointsOut = applyAffineToPoints(M, pointsIn)
    pointsHom = [double(pointsIn), ones(size(pointsIn, 1), 1)];
    pointsHom = (double(M) * pointsHom')';
    pointsOut = pointsHom(:, 1:3);
end

function saveReport(out, outputFile)
    ensureDir(fileparts(outputFile));
    save(outputFile, 'out');
    [folder, stem] = fileparts(outputFile);
    jsonFile = fullfile(folder, [stem '.json']);
    writeJson(jsonFile, jsonReady(out));
end

function writeJson(fileName, S)
    fid = fopen(fileName, 'wt');
    if fid < 0
        error('acsCapMakerPrintToMriFrame:CouldNotWriteJson', ...
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
    end
end

function printSummary(out)
    fprintf('\ncapMaker print-to-MRI point conversion\n');
    fprintf('  points: %d\n', size(out.printCoordinatesMm, 1));
    if ~isempty(out.objects)
        fprintf('  object traces: %d\n', numel(out.objects));
    end
    fprintf('  skin cache: %s\n', out.skinSource.skinCacheFile);
    if ~isempty(out.skinMetaSummary.inputOrientation)
        fprintf('  input orientation: %s\n', out.skinMetaSummary.inputOrientation);
    end
    fprintf('\n');
end

function labels = defaultLabels(n)
    labels = cell(n, 1);
    for i = 1:n
        labels{i} = sprintf('point%d', i);
    end
end

function labels = normalizeLabelCell(labelsIn)
    if isempty(labelsIn)
        labels = {};
    elseif iscell(labelsIn)
        labels = cellstr(labelsIn(:));
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

function ensureDir(folder)
    if isempty(folder), return; end
    if exist(folder, 'dir') ~= 7
        mkdir(folder);
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
