function out = acsMakeImplantExclusionFromPhoneObject(phoneObjectIn, targetSkinCacheFile, varargin)
% ACSMAKEIMPLANTEXCLUSIONFROMPHONEOBJECT Build a cap keepout from a painted phone-scan object.
%
% out = acsMakeImplantExclusionFromPhoneObject(phoneObjectIn, targetSkinCacheFile)
% transforms selected phone-scan object vertices into the current capMaker
% printer-bed frame, then delegates footprint projection/buffering to
% acsMakeImplantExclusionFromPolhemusTrace. This is intended for cases such
% as a visible headpost in a phone/LiDAR scan.
%
% Name-value options:
%   sourceSkinCacheFile : capMaker skin cache used by phone registration ['auto']
%   objectName          : object/trace name ['auto']
%   marginMm            : no-print buffer around projected footprint [5]
%   outputFile          : saved MAT exclusion file ['']
%   outputTag           : file/report tag ['phoneObjectExclusion']
%   projectionMode      : passed through to implant exclusion ['traceXY']
%   boundaryShrink      : boundary shrink factor [0.75]
%   force               : overwrite existing output [false]
%   showFigures         : show QC figure [false]
%   saveFigures         : save QC figure [false]
%   verbose             : print summary [true]

    if nargin < 1 || isempty(phoneObjectIn)
        error('acsMakeImplantExclusionFromPhoneObject:MissingObject', ...
            'Provide a phone object selection struct or MAT file.');
    end
    if nargin < 2 || isempty(targetSkinCacheFile)
        error('acsMakeImplantExclusionFromPhoneObject:MissingSkinCache', ...
            'Provide the target capMaker skin cache in printer-bed frame.');
    end

    opts = parseInputs(varargin{:});
    addLocalDependencies();

    object = readPhoneObject(phoneObjectIn);
    targetSkinCacheFile = expandUserPath(char(targetSkinCacheFile));
    if exist(targetSkinCacheFile, 'file') ~= 2
        error('acsMakeImplantExclusionFromPhoneObject:TargetSkinMissing', ...
            'Target skin cache not found: %s', targetSkinCacheFile);
    end
    if isempty(opts.objectName)
        opts.objectName = char(getOptionalField(object, 'objectName', ...
            getOptionalField(object, 'name', 'headpost')));
    end
    opts.outputFile = resolveOutputFile(targetSkinCacheFile, opts);

    if exist(opts.outputFile, 'file') == 2 && ~opts.force
        out = loadPreferredStruct(opts.outputFile);
        if opts.verbose
            fprintf('Phone object implant exclusion already exists; reusing %s\n', ...
                opts.outputFile);
        end
        return;
    end

    pointsIn = objectPoints(object);
    frameIn = objectCoordinateFrame(object);
    sourceSkinCacheFile = resolveSourceSkinCacheFile(object, opts);
    pointsPrint = transformObjectPointsToTargetPrint(pointsIn, frameIn, ...
        sourceSkinCacheFile, targetSkinCacheFile);

    labels = defaultLabels(size(pointsPrint, 1), opts.objectName);
    traceForExclusion = struct();
    traceForExclusion.type = 'phoneObjectTraceForImplantExclusion';
    traceForExclusion.coordinateFrame = 'capMakerPrintMm';
    traceForExclusion.meshSource = struct('file', targetSkinCacheFile, ...
        'cacheFile', targetSkinCacheFile, ...
        'coordinateFrame', 'capMakerPrintMm');
    traceForExclusion.traceSets = struct( ...
        'name', opts.objectName, ...
        'coordinatesMm', pointsPrint, ...
        'labels', {labels}, ...
        'rows', (1:size(pointsPrint, 1))');

    out = acsMakeImplantExclusionFromPolhemusTrace( ...
        traceForExclusion, targetSkinCacheFile, ...
        'objectName', opts.objectName, ...
        'marginMm', opts.marginMm, ...
        'boundaryShrink', opts.boundaryShrink, ...
        'outputFile', opts.outputFile, ...
        'projectionMode', opts.projectionMode, ...
        'frameTransformMode', 'never', ...
        'force', true, ...
        'showFigures', opts.showFigures, ...
        'saveFigures', opts.saveFigures, ...
        'verbose', opts.verbose);

    out.inputType = 'phoneScanObjectSelection';
    out.phoneObjectSource = compactPhoneObjectSource(object, phoneObjectIn);
    out.phoneObjectTransformInfo = struct( ...
        'inputFrame', frameIn, ...
        'outputFrame', 'capMakerPrintMm', ...
        'sourceSkinCacheFile', sourceSkinCacheFile, ...
        'targetSkinCacheFile', targetSkinCacheFile, ...
        'nPoints', size(pointsPrint, 1));
    out.phoneObjectRawCoordinatesMm = pointsIn;
    out.phoneObjectPrintCoordinatesMm = pointsPrint;

    outForSave = out;
    if isfield(outForSave, 'figure')
        outForSave = rmfield(outForSave, 'figure');
    end
    exclusion = outForSave; %#ok<NASGU>
    save(opts.outputFile, 'outForSave', 'exclusion', '-v7.3');
end

function opts = parseInputs(varargin)
    p = inputParser;
    p.FunctionName = 'acsMakeImplantExclusionFromPhoneObject';
    addParameter(p, 'sourceSkinCacheFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'objectName', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'marginMm', 5, @isNonnegativeScalar);
    addParameter(p, 'outputFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'outputTag', 'phoneObjectExclusion', @(x) ischar(x) || isstring(x));
    addParameter(p, 'projectionMode', 'traceXY', @(x) ischar(x) || isstring(x));
    addParameter(p, 'boundaryShrink', 0.75, @isUnitScalar);
    addParameter(p, 'force', false, @isBoolLike);
    addParameter(p, 'showFigures', false, @isBoolLike);
    addParameter(p, 'saveFigures', false, @isBoolLike);
    addParameter(p, 'verbose', true, @isBoolLike);
    parse(p, varargin{:});

    opts = p.Results;
    opts.sourceSkinCacheFile = expandUserPath(char(opts.sourceSkinCacheFile));
    opts.objectName = char(opts.objectName);
    opts.marginMm = double(opts.marginMm);
    opts.outputFile = expandUserPath(char(opts.outputFile));
    opts.outputTag = safeName(char(opts.outputTag));
    opts.projectionMode = char(opts.projectionMode);
    opts.boundaryShrink = double(opts.boundaryShrink);
    opts.force = logical(opts.force);
    opts.showFigures = logical(opts.showFigures);
    opts.saveFigures = logical(opts.saveFigures);
    opts.verbose = logical(opts.verbose);
end

function tf = isBoolLike(x)
    tf = (islogical(x) || isnumeric(x)) && isscalar(x);
end

function tf = isNonnegativeScalar(x)
    tf = isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0;
end

function tf = isUnitScalar(x)
    tf = isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0 && x <= 1;
end

function addLocalDependencies()
    repoRoot = fileparts(fileparts(mfilename('fullpath')));
    addpath(repoRoot);
    addpath(fullfile(repoRoot, 'acsUtilities'));
end

function object = readPhoneObject(value)
    if ischar(value) || isstring(value)
        fileName = expandUserPath(char(value));
        if exist(fileName, 'file') ~= 2
            error('acsMakeImplantExclusionFromPhoneObject:ObjectFileMissing', ...
                'Phone object file not found: %s', fileName);
        end
        object = loadPreferredStruct(fileName);
        object.outputFile = char(getOptionalField(object, 'outputFile', fileName));
        return;
    end
    if isstruct(value)
        object = value;
        return;
    end
    error('acsMakeImplantExclusionFromPhoneObject:BadObjectInput', ...
        'phoneObjectIn must be a struct or MAT file.');
end

function points = objectPoints(object)
    if isfield(object, 'selectedCoordinatesMm') && ~isempty(object.selectedCoordinatesMm)
        points = double(object.selectedCoordinatesMm);
    elseif isfield(object, 'coordinatesMm') && ~isempty(object.coordinatesMm)
        points = double(object.coordinatesMm);
    elseif isfield(object, 'traceSets') && ~isempty(object.traceSets) && ...
            isfield(object.traceSets(1), 'coordinatesMm')
        points = double(object.traceSets(1).coordinatesMm);
    else
        points = zeros(0, 3);
    end
    if size(points, 1) < 3 || size(points, 2) ~= 3
        error('acsMakeImplantExclusionFromPhoneObject:TooFewObjectPoints', ...
            'At least three phone object points are needed to make an exclusion footprint.');
    end
    if any(~isfinite(points(:)))
        error('acsMakeImplantExclusionFromPhoneObject:BadObjectPoints', ...
            'Phone object coordinates must be finite N x 3 values.');
    end
end

function frame = objectCoordinateFrame(object)
    frame = char(getOptionalField(object, 'coordinateFrame', 'capMakerPrintMm'));
    if isfield(object, 'pointCoordinateFrames') && ...
            isstruct(object.pointCoordinateFrames) && ...
            isfield(object.pointCoordinateFrames, 'selectedCoordinatesMm') && ...
            ~isempty(object.pointCoordinateFrames.selectedCoordinatesMm)
        frame = char(object.pointCoordinateFrames.selectedCoordinatesMm);
    end
end

function sourceSkinCacheFile = resolveSourceSkinCacheFile(object, opts)
    sourceSkinCacheFile = opts.sourceSkinCacheFile;
    if ~isempty(sourceSkinCacheFile)
        return;
    end
    if isfield(object, 'source') && isstruct(object.source) && ...
            isfield(object.source, 'target') && isstruct(object.source.target) && ...
            isfield(object.source.target, 'file') && ~isempty(object.source.target.file)
        sourceSkinCacheFile = expandUserPath(char(object.source.target.file));
        return;
    end
    sourceFile = '';
    if isfield(object, 'source') && isstruct(object.source) && ...
            isfield(object.source, 'file') && ~isempty(object.source.file)
        sourceFile = char(object.source.file);
    elseif isfield(object, 'source') && isstruct(object.source) && ...
            isfield(object.source, 'registrationFile') && ...
            ~isempty(object.source.registrationFile)
        sourceFile = char(object.source.registrationFile);
    end
    if isempty(sourceFile) || exist(sourceFile, 'file') ~= 2
        return;
    end
    try
        reg = loadPreferredStruct(sourceFile);
        if isfield(reg, 'target') && isstruct(reg.target) && ...
                isfield(reg.target, 'file') && ~isempty(reg.target.file)
            sourceSkinCacheFile = expandUserPath(char(reg.target.file));
        end
    catch
        sourceSkinCacheFile = '';
    end
end

function pointsPrint = transformObjectPointsToTargetPrint(pointsIn, frameIn, ...
        sourceSkinCacheFile, targetSkinCacheFile)
    frameKey = lower(strtrim(char(frameIn)));
    targetMeta = readSkinMeta(targetSkinCacheFile);
    switch frameKey
        case 'capmakerprintmm'
            if isempty(sourceSkinCacheFile) || sameFilePath(sourceSkinCacheFile, targetSkinCacheFile)
                pointsPrint = pointsIn;
            else
                sourceMeta = readSkinMeta(sourceSkinCacheFile);
                originalWorld = printMmToOriginalWorldMm(pointsIn, sourceMeta);
                pointsPrint = originalWorldMmToPrintMm(originalWorld, targetMeta);
            end
        case {'capmakerprecropworldmm', 'capmakerstableworldmm', 'modelmm'}
            pointsPrint = originalWorldMmToPrintMm(pointsIn, targetMeta);
        otherwise
            error('acsMakeImplantExclusionFromPhoneObject:UnknownCoordinateFrame', ...
                ['Phone object coordinates are in frame "%s". Provide or ', ...
                 'convert them to capMakerPrintMm or capMakerPreCropWorldMm.'], frameIn);
    end
end

function meta = readSkinMeta(fileName)
    fileName = expandUserPath(char(fileName));
    S = load(fileName, 'meta');
    if ~isfield(S, 'meta') || ~isstruct(S.meta)
        error('acsMakeImplantExclusionFromPhoneObject:MissingSkinMeta', ...
            'Skin cache does not contain meta: %s', fileName);
    end
    meta = S.meta;
    validateSkinMeta(meta, fileName);
end

function worldMm = printMmToOriginalWorldMm(printMm, meta)
    finalWorldMm = applyAffineToPoints(meta.print.T_print2world, printMm);
    worldMm = (double(meta.align.R) \ finalWorldMm')';
end

function printMm = originalWorldMmToPrintMm(worldMm, meta)
    finalWorldMm = (double(meta.align.R) * double(worldMm)')';
    printMm = applyAffineToPoints(meta.print.T_world2print, finalWorldMm);
end

function validateSkinMeta(meta, fileName)
    ok = isstruct(meta) && isfield(meta, 'align') && ...
        isfield(meta.align, 'R') && isfield(meta, 'print') && ...
        isfield(meta.print, 'T_world2print') && ...
        isfield(meta.print, 'T_print2world');
    if ~ok
        error('acsMakeImplantExclusionFromPhoneObject:BadSkinMeta', ...
            'Skin metadata lacks align.R or print transforms: %s', fileName);
    end
end

function pointsOut = applyAffineToPoints(M, pointsIn)
    pointsHom = [double(pointsIn), ones(size(pointsIn, 1), 1)];
    pointsHom = (double(M) * pointsHom')';
    pointsOut = pointsHom(:, 1:3);
end

function fileName = resolveOutputFile(targetSkinCacheFile, opts)
    if ~isempty(opts.outputFile)
        fileName = opts.outputFile;
        return;
    end
    [folder, stem] = fileparts(targetSkinCacheFile);
    fileName = fullfile(folder, sprintf('%s_%s_%s.mat', ...
        stem, safeName(opts.objectName), opts.outputTag));
end

function source = compactPhoneObjectSource(object, phoneObjectIn)
    source = struct();
    if ischar(phoneObjectIn) || isstring(phoneObjectIn)
        source.file = expandUserPath(char(phoneObjectIn));
    elseif isfield(object, 'outputFile')
        source.file = char(object.outputFile);
    else
        source.file = '';
    end
    source.objectName = char(getOptionalField(object, 'objectName', ...
        getOptionalField(object, 'name', '')));
    source.coordinateFrame = objectCoordinateFrame(object);
    source.nSelected = size(objectPoints(object), 1);
    if isfield(object, 'source')
        source.source = object.source;
    end
end

function labels = defaultLabels(n, prefix)
    labels = cell(n, 1);
    for i = 1:n
        labels{i} = sprintf('%s_%03d', char(prefix), i);
    end
end

function value = getOptionalField(S, fieldName, defaultValue)
    if isstruct(S) && isfield(S, fieldName) && ~isempty(S.(fieldName))
        value = S.(fieldName);
    else
        value = defaultValue;
    end
end

function S = loadPreferredStruct(fileName)
    raw = load(expandUserPath(char(fileName)));
    preferred = {'phoneObject', 'outForSave', 'outSaved', 'out', 'exclusion'};
    for i = 1:numel(preferred)
        if isfield(raw, preferred{i}) && isstruct(raw.(preferred{i}))
            S = raw.(preferred{i});
            return;
        end
    end
    names = fieldnames(raw);
    for i = 1:numel(names)
        if isstruct(raw.(names{i}))
            S = raw.(names{i});
            return;
        end
    end
    error('acsMakeImplantExclusionFromPhoneObject:NoStruct', ...
        'MAT file does not contain a readable struct: %s', fileName);
end

function tf = sameFilePath(a, b)
    if isempty(a) || isempty(b)
        tf = false;
        return;
    end
    tf = strcmpi(canonicalPath(a), canonicalPath(b));
end

function value = canonicalPath(value)
    value = expandUserPath(char(value));
    try
        if exist(value, 'file') == 2 || exist(value, 'dir') == 7
            value = char(java.io.File(value).getCanonicalPath());
        end
    catch
    end
    value = lower(strrep(value, '/', filesep));
end

function fileName = expandUserPath(fileName)
    if isempty(fileName)
        return;
    end
    if startsWith(fileName, '~')
        homeDir = getenv('HOME');
        if isempty(homeDir)
            homeDir = char(java.lang.System.getProperty('user.home'));
        end
        fileName = fullfile(homeDir, fileName(2:end));
    end
end

function value = safeName(value)
    value = regexprep(char(value), '[^\w\-]+', '_');
    value = regexprep(value, '_+', '_');
    value = regexprep(value, '^_|_$', '');
end
