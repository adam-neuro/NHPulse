function out = acsBuildCapMakerSkinCache(sourceIn, varargin)
% ACSBUILDCAPMAKERSKINCACHE Build/rebuild a capMaker cropped skin cache.
%
% out = acsBuildCapMakerSkinCache(segOut) creates the capMaker TRskin cache
% without also creating electrode locations. This is useful when crop-plane
% selection needs to happen before scalp warp, implant exclusions, or layout.

    if nargin < 1 || isempty(sourceIn)
        error('acsBuildCapMakerSkinCache:MissingInput', ...
            'Provide a segmentation output or T1 NIfTI filename.');
    end

    opts = parseInputs(varargin{:});
    addLocalDependencies();
    [t1File, source] = resolveT1File(sourceIn, opts);
    capWorkDir = acsSubjectPath(opts.subjectId, 'capWork');
    stem = capMakerInputStem(t1File);

    cacheFile = opts.outputFile;
    if isempty(cacheFile)
        cacheFile = fullfile(capWorkDir, [stem '_skinMesh.mat']);
    end
    cropPlaneFile = opts.cropPlaneFile;
    if isempty(cropPlaneFile)
        cropPlaneFile = fullfile(capWorkDir, [stem '_cropPlane.mat']);
    elseif ~endsWith(lower(cropPlaneFile), '.mat')
        cropPlaneFile = [cropPlaneFile '.mat'];
    end

    [skinOpts, cropPlane] = resolveCropPlaneOptions( ...
        opts.skinMeshOptions, cropPlaneFile, t1File, opts);
    if exist(cacheFile, 'file') == 2 && ~opts.force && ...
            ~strcmp(opts.cropPlaneMode, 'select')
        S = load(cacheFile, 'meta', 'TRstableHead');
        if isfield(S, 'meta') && cachedMeshMatchesCropPlane(S.meta, cropPlane) && ...
                cachedMeshHasStableHead(S)
            out = makeReuseOutput(cacheFile, cropPlaneFile, cropPlane, source);
            if opts.verbose
                fprintf('Reusing capMaker skin cache: %s\n', cacheFile);
            end
            return;
        elseif opts.verbose
            fprintf('Existing capMaker skin cache is stale; rebuilding %s\n', ...
                cacheFile);
        end
    end

    if ~isfield(skinOpts, 'viz') || isempty(skinOpts.viz)
        skinOpts.viz = false;
    end
    skinOpts = capMakerSkinOptions(skinOpts);

    if opts.verbose
        fprintf('Building capMaker skin cache from T1: %s\n', t1File);
    end
    [TRskin, meta] = skinMeshFromMPRAGE(t1File, skinOpts);

    if strcmp(opts.cropPlaneMode, 'select') || ...
            (strcmp(opts.cropPlaneMode, 'autoSelect') && ...
             exist(cropPlaneFile, 'file') ~= 2)
        cropPlane = cropPlaneFromSkinMeta(meta, t1File);
        ensureDir(fileparts(cropPlaneFile));
        save(cropPlaneFile, 'cropPlane');
        writeJsonReport([cropPlaneFile(1:end - 4) '.json'], cropPlane);
    else
        cropPlane = cropPlaneFromSkinMeta(meta, t1File);
    end

    [meta, TRfiducialHead, TRstableHead] = extractEmbeddedMeshes(meta);
    ensureDir(fileparts(cacheFile));
    save(cacheFile, 'TRskin', 'TRfiducialHead', 'TRstableHead', 'meta', '-v7.3');

    out = struct();
    out.createdOn = char(datetime('now'));
    out.cacheFile = cacheFile;
    out.cropPlaneFile = cropPlaneFile;
    out.cropPlane = cropPlane;
    out.source = source;
    out.meshStats = struct( ...
        'skin', meshStats(TRskin), ...
        'fiducialHead', meshStats(TRfiducialHead), ...
        'stableHead', meshStats(TRstableHead));
    out.options = opts;

    if opts.verbose
        fprintf('Saved capMaker skin cache: %s\n', cacheFile);
        fprintf('Saved capMaker crop plane: %s\n', cropPlaneFile);
    end
end

function opts = parseInputs(varargin)
    p = inputParser;
    p.FunctionName = 'acsBuildCapMakerSkinCache';
    addParameter(p, 'subjectId', 'M2107', @(x) ischar(x) || isstring(x));
    addParameter(p, 't1File', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'outputFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'cropPlaneMode', 'autoSelect', @(x) ischar(x) || isstring(x));
    addParameter(p, 'cropPlaneFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'skinMeshOptions', struct(), @(x) isempty(x) || isstruct(x));
    addParameter(p, 'force', false, @isBoolLike);
    addParameter(p, 'showFigures', false, @isBoolLike);
    addParameter(p, 'verbose', true, @isBoolLike);
    parse(p, varargin{:});

    opts = p.Results;
    opts.subjectId = char(opts.subjectId);
    opts.t1File = expandUserPath(char(opts.t1File));
    opts.outputFile = expandUserPath(char(opts.outputFile));
    opts.cropPlaneMode = normalizeCropPlaneMode(opts.cropPlaneMode);
    opts.cropPlaneFile = expandUserPath(char(opts.cropPlaneFile));
    if isempty(opts.skinMeshOptions)
        opts.skinMeshOptions = struct();
    end
    opts.force = logical(opts.force);
    opts.showFigures = logical(opts.showFigures);
    opts.verbose = logical(opts.verbose);
end

function addLocalDependencies()
    repoRoot = fileparts(fileparts(mfilename('fullpath')));
    addpath(repoRoot);
    addpath(fullfile(repoRoot, 'capMaker', 'core'));
end

function [t1File, source] = resolveT1File(sourceIn, opts)
    source = struct('type', '', 'input', sourceIn);
    if ~isempty(opts.t1File)
        t1File = opts.t1File;
        source.type = 'explicitT1';
    elseif ischar(sourceIn) || isstring(sourceIn)
        t1File = expandUserPath(char(sourceIn));
        source.type = 't1File';
    elseif isstruct(sourceIn) && isfield(sourceIn, 'roastReady') && ...
            isstruct(sourceIn.roastReady) && isfield(sourceIn.roastReady, 't1File')
        t1File = expandUserPath(char(sourceIn.roastReady.t1File));
        source.type = 'segmentationOutput';
    elseif isstruct(sourceIn) && isfield(sourceIn, 't1File')
        t1File = expandUserPath(char(sourceIn.t1File));
        source.type = 'sourceStruct';
    else
        error('acsBuildCapMakerSkinCache:BadSource', ...
            'Could not resolve a T1 file from the supplied source.');
    end
    if exist(t1File, 'file') ~= 2
        error('acsBuildCapMakerSkinCache:MissingT1', ...
            'T1 file not found: %s', t1File);
    end
    source.t1File = t1File;
end

function [skinOpts, cropPlane] = resolveCropPlaneOptions( ...
        skinOpts, cropPlaneFile, t1File, opts)
    if isempty(skinOpts)
        skinOpts = struct();
    end
    cropPlane = struct();
    switch opts.cropPlaneMode
        case 'select'
            if exist(cropPlaneFile, 'file') == 2
                cropPlane = loadCropPlane(cropPlaneFile);
                skinOpts = applyCropPlaneDefaultsToSkinOptions(skinOpts, cropPlane);
            end
            skinOpts.interactiveCrop = true;
        case {'auto', 'reuse', 'autoSelect'}
            if exist(cropPlaneFile, 'file') == 2
                cropPlane = loadCropPlane(cropPlaneFile);
                skinOpts = applyCropPlaneToSkinOptions(skinOpts, cropPlane);
            elseif strcmp(opts.cropPlaneMode, 'reuse')
                error('acsBuildCapMakerSkinCache:CropPlaneNotFound', ...
                    'Saved crop plane not found: %s', cropPlaneFile);
            elseif strcmp(opts.cropPlaneMode, 'autoSelect')
                skinOpts.interactiveCrop = true;
            end
        case 'default'
            % Keep caller-provided skin options.
        otherwise
            error('acsBuildCapMakerSkinCache:BadCropPlaneMode', ...
                'Unknown cropPlaneMode "%s" for %s.', opts.cropPlaneMode, t1File);
    end
end

function skinOpts = capMakerSkinOptions(skinOpts)
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

function [meta, TRfiducialHead, TRstableHead] = extractEmbeddedMeshes(meta)
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
end

function out = makeReuseOutput(cacheFile, cropPlaneFile, cropPlane, source)
    out = struct('createdOn', char(datetime('now')), ...
        'cacheFile', cacheFile, ...
        'cropPlaneFile', cropPlaneFile, ...
        'cropPlane', cropPlane, ...
        'source', source, ...
        'reusedExistingCache', true);
end

function cropPlane = cropPlaneFromSkinMeta(meta, t1File)
    cropPlane = struct();
    cropPlane.createdOn = char(datetime('now'));
    cropPlane.inputFile = t1File;
    cropPlane.inputKind = 'nifti';
    cropPlane.cropAxis = double(meta.align.dir(:)');
    cropPlane.cropDistance = double(meta.align.distance);
    cropPlane.cropSide = char(meta.align.side);
    cropPlane.alignCrop = logical(meta.align.used);
end

function cropPlane = loadCropPlane(fileName)
    S = load(fileName, 'cropPlane');
    if ~isfield(S, 'cropPlane') || ~isstruct(S.cropPlane)
        error('acsBuildCapMakerSkinCache:BadCropPlaneFile', ...
            'Crop-plane file does not contain cropPlane: %s', fileName);
    end
    cropPlane = S.cropPlane;
end

function skinOpts = applyCropPlaneToSkinOptions(skinOpts, cropPlane)
    skinOpts.cropAxis = cropPlane.cropAxis;
    skinOpts.cropDistance = cropPlane.cropDistance;
    skinOpts.cropSide = cropPlane.cropSide;
    skinOpts.alignCrop = cropPlane.alignCrop;
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

function tf = cachedMeshHasStableHead(S)
    tf = isfield(S, 'TRstableHead') && ~isempty(S.TRstableHead);
    if tf
        return;
    end
    tf = isfield(S, 'meta') && isstruct(S.meta) && ...
        isfield(S.meta, 'stableHead') && isstruct(S.meta.stableHead) && ...
        isfield(S.meta.stableHead, 'TR') && ~isempty(S.meta.stableHead.TR);
end

function mode = normalizeCropPlaneMode(modeIn)
    mode = lower(strtrim(char(modeIn)));
    switch mode
        case {'auto', 'select', 'reuse', 'default'}
        case {'autoselect', 'promptifmissing', 'selectifmissing'}
            mode = 'autoSelect';
        otherwise
            error('acsBuildCapMakerSkinCache:BadCropPlaneMode', ...
                'cropPlaneMode must be autoSelect, auto, select, reuse, or default.');
    end
end

function stats = meshStats(TR)
    if isempty(TR)
        stats = struct('nVertices', 0, 'nFaces', 0, 'bounds', zeros(0, 3));
        return;
    end
    stats = struct('nVertices', size(TR.Points, 1), ...
        'nFaces', size(TR.ConnectivityList, 1), ...
        'bounds', [min(TR.Points, [], 1); max(TR.Points, [], 1)]);
end

function stem = capMakerInputStem(fileName)
    [~, stem] = fileparts(fileName);
    if endsWith(lower(stem), '.nii')
        [~, stem] = fileparts(stem);
    end
    stem = regexprep(stem, '[^a-zA-Z0-9_]', '_');
end

function tf = isBoolLike(x)
    tf = (islogical(x) || isnumeric(x)) && isscalar(x);
end

function writeJsonReport(fileName, value)
    try
        fid = fopen(fileName, 'w');
        cleaner = onCleanup(@() fclose(fid));
        fprintf(fid, '%s', jsonencode(value, 'PrettyPrint', true));
    catch
        % JSON is convenient but not required for the MATLAB pipeline.
    end
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

function ensureDir(folder)
    if isempty(folder)
        return;
    end
    if exist(folder, 'dir') ~= 7
        mkdir(folder);
    end
end
