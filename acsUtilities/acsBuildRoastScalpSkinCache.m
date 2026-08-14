function out = acsBuildRoastScalpSkinCache(sourceIn, varargin)
% ACSBUILDROASTSCALPSKINCACHE Build a capMaker skin cache from ROAST labels.
%
% out = acsBuildRoastScalpSkinCache(segOut) extracts the external solid-head
% surface from the segmentation head mask when available, falling back to
% the ROAST hard-label mask otherwise, and saves a capMaker-compatible skin
% cache. The resulting cache can be used as the canonical scalp source for
% phone-scan warping, cap cropping, electrode layout, and manufacturing.
%
% The saved cache uses capMakerPreCropWorldMm as a simple zero-origin
% millimeter frame: voxel coordinate 0 maps to 0 mm and spacing is taken
% from the ROAST mask affine. No cap crop or printer-bed transform is applied.

    if nargin < 1 || isempty(sourceIn)
        error('acsBuildRoastScalpSkinCache:MissingInput', ...
            'Provide a segmentation output or ROAST hard-label mask file.');
    end

    opts = parseInputs(varargin{:});
    addLocalDependencies();
    [maskFile, t1File, source, opts] = resolveInputs(sourceIn, opts);

    if isempty(opts.outputFile)
        opts.outputFile = defaultOutputFile(maskFile, opts.outputTag);
    end
    if exist(opts.outputFile, 'file') == 2 && ~opts.force
        reuseBlocker = skinCacheReuseBlocker(opts.outputFile, source);
        if isempty(reuseBlocker)
            out = reuseOutput(opts.outputFile, maskFile, t1File, source, opts);
            if opts.verbose
                fprintf('Reusing ROAST-derived scalp skin cache: %s\n', opts.outputFile);
            end
            return;
        elseif opts.verbose
            warning('acsBuildRoastScalpSkinCache:StaleCache', ...
                ['Existing ROAST-derived scalp cache is not reusable (%s). ', ...
                 'Rebuilding %s.'], reuseBlocker, opts.outputFile);
        end
    end

    Vmask = spm_vol(maskFile);
    Vmask = Vmask(1);
    labels = uint8(round(spm_read_vols(Vmask)));
    [headMask, maskInfo] = makeCanonicalSurfaceMask(labels, Vmask, opts);
    [TRstableHead, surfaceInfo] = solidMaskToWorldSurface( ...
        headMask, Vmask.mat, opts);

    TRskin = TRstableHead;
    TRfiducialHead = TRstableHead;
    meta = makeSkinCacheMeta(Vmask, maskFile, t1File, source, ...
        TRstableHead, maskInfo, surfaceInfo, opts);
    cacheInfo = struct('createdOn', char(datetime('now')), ...
        'source', source, ...
        'maskInfo', maskInfo, ...
        'surfaceInfo', surfaceInfo, ...
        'coordinateFrame', 'capMakerPreCropWorldMm');

    ensureDir(fileparts(opts.outputFile));
    save(opts.outputFile, 'TRskin', 'TRfiducialHead', 'TRstableHead', ...
        'meta', 'cacheInfo', '-v7.3');

    qcFile = '';
    fig = [];
    if opts.showFigures || opts.saveFigures
        figVisible = 'off';
        if opts.showFigures
            figVisible = 'on';
        end
        fig = makeQcFigure(labels, headMask, TRstableHead, Vmask, ...
            opts, figVisible);
        if opts.saveFigures
            qcFile = fullfile(fileparts(opts.outputFile), 'qc', ...
                [stripMatExtension(getFileName(opts.outputFile)) '_qc.png']);
            ensureDir(fileparts(qcFile));
            saveQcFigure(fig, qcFile);
        end
        if ~opts.showFigures && isgraphics(fig)
            close(fig);
            fig = [];
        end
    end

    out = struct();
    out.createdOn = char(datetime('now'));
    out.type = 'roastScalpSkinCache';
    out.cacheFile = opts.outputFile;
    out.outputFile = opts.outputFile;
    out.maskFile = maskFile;
    out.t1File = t1File;
    out.coordinateFrame = 'capMakerPreCropWorldMm';
    out.meshStats = meshStats(TRstableHead);
    out.maskInfo = maskInfo;
    out.surfaceInfo = surfaceInfo;
    out.source = source;
    out.qcFigure = qcFile;
    out.options = opts;
    out.figure = fig;

    outForSave = out;
    if isfield(outForSave, 'figure')
        outForSave = rmfield(outForSave, 'figure');
    end
    reportFile = replaceExtension(opts.outputFile, '_report.mat');
    save(reportFile, 'outForSave', '-v7.3');
    writeJsonReport(replaceExtension(opts.outputFile, '_report.json'), ...
        outForSave);

    if opts.verbose
        printSummary(out);
    end
end

function opts = parseInputs(varargin)
    p = inputParser;
    p.FunctionName = 'acsBuildRoastScalpSkinCache';
    addParameter(p, 'maskFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'surfaceMaskFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 't1File', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'outputFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'outputTag', 'roastScalpSkinMesh', ...
        @(x) ischar(x) || isstring(x));
    addParameter(p, 'force', false, @isBoolLike);
    addParameter(p, 'headLabels', [], @(x) isempty(x) || ...
        (isnumeric(x) && isvector(x)));
    addParameter(p, 'clearBoundaryAir', true, @isBoolLike);
    addParameter(p, 'fillInternalHoles', true, @isBoolLike);
    addParameter(p, 'keepLargestComponent', true, @isBoolLike);
    addParameter(p, 'surfaceSmoothingSigmaVox', 0.7, @isNonnegativeScalar);
    addParameter(p, 'smoothIterations', 0, @isNonnegativeScalar);
    addParameter(p, 'maxFaces', 35000, @isPositiveScalar);
    addParameter(p, 'showFigures', false, @isBoolLike);
    addParameter(p, 'saveFigures', false, @isBoolLike);
    addParameter(p, 'verbose', true, @isBoolLike);
    parse(p, varargin{:});

    opts = p.Results;
    opts.maskFile = expandUserPath(char(opts.maskFile));
    opts.surfaceMaskFile = expandUserPath(char(opts.surfaceMaskFile));
    opts.t1File = expandUserPath(char(opts.t1File));
    opts.outputFile = expandUserPath(char(opts.outputFile));
    opts.outputTag = safeName(char(opts.outputTag));
    opts.force = logical(opts.force);
    if isempty(opts.headLabels)
        opts.headLabels = [];
    else
        opts.headLabels = unique(uint8(round(double(opts.headLabels(:)'))));
    end
    opts.clearBoundaryAir = logical(opts.clearBoundaryAir);
    opts.fillInternalHoles = logical(opts.fillInternalHoles);
    opts.keepLargestComponent = logical(opts.keepLargestComponent);
    opts.surfaceSmoothingSigmaVox = double(opts.surfaceSmoothingSigmaVox);
    opts.smoothIterations = round(double(opts.smoothIterations));
    opts.maxFaces = round(double(opts.maxFaces));
    opts.showFigures = logical(opts.showFigures);
    opts.saveFigures = logical(opts.saveFigures);
    opts.verbose = logical(opts.verbose);
end

function tf = isBoolLike(x)
    tf = (islogical(x) || isnumeric(x)) && isscalar(x);
end

function tf = isPositiveScalar(x)
    tf = isnumeric(x) && isscalar(x) && isfinite(x) && x > 0;
end

function tf = isNonnegativeScalar(x)
    tf = isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0;
end

function addLocalDependencies()
    repoRoot = fileparts(fileparts(mfilename('fullpath')));
    addpath(repoRoot);
    addpath(fullfile(repoRoot, 'acsUtilities'));
    addpath(fullfile(repoRoot, 'capMaker', 'core'));
    spmDir = fullfile(repoRoot, 'lib', 'spm12');
    if exist(spmDir, 'dir') == 7
        addpath(spmDir);
    end
end

function [maskFile, t1File, source, opts] = resolveInputs(sourceIn, opts)
    maskFile = opts.maskFile;
    t1File = opts.t1File;
    surfaceMaskFile = opts.surfaceMaskFile;
    source = struct('type', '', 'file', '', 'maskFile', '', ...
        'surfaceMaskFile', '', 'surfaceMaskRole', '', 't1File', '');
    if ischar(sourceIn) || isstring(sourceIn)
        maskFile = chooseIfEmpty(maskFile, expandUserPath(char(sourceIn)));
        source.type = 'maskFile';
        source.file = maskFile;
    elseif isstruct(sourceIn)
        source.type = 'struct';
        if isempty(maskFile)
            if isfield(sourceIn, 'roastReady') && isstruct(sourceIn.roastReady) && ...
                    isfield(sourceIn.roastReady, 'maskFile')
                maskFile = expandUserPath(char(sourceIn.roastReady.maskFile));
                source.type = 'segmentationOutput';
            elseif isfield(sourceIn, 'maskFile')
                maskFile = expandUserPath(char(sourceIn.maskFile));
            end
        end
        if isempty(t1File)
            if isfield(sourceIn, 'roastReady') && isstruct(sourceIn.roastReady) && ...
                    isfield(sourceIn.roastReady, 't1File')
                t1File = expandUserPath(char(sourceIn.roastReady.t1File));
            elseif isfield(sourceIn, 't1File')
                t1File = expandUserPath(char(sourceIn.t1File));
            end
        end
        if isempty(surfaceMaskFile)
            [surfaceMaskFile, surfaceRole] = subjectHeadSurfaceMask(sourceIn);
            source.surfaceMaskRole = surfaceRole;
        end
    else
        error('acsBuildRoastScalpSkinCache:BadInput', ...
            'sourceIn must be a struct or mask filename.');
    end
    requireFile(maskFile, 'ROAST hard-label mask');
    if ~isempty(surfaceMaskFile)
        requireFile(surfaceMaskFile, 'canonical scalp surface mask');
        opts.surfaceMaskFile = surfaceMaskFile;
        if isempty(source.surfaceMaskRole)
            source.surfaceMaskRole = 'explicit surfaceMaskFile';
        end
        opts.surfaceMaskRole = source.surfaceMaskRole;
    end
    if ~isempty(t1File)
        requireFile(t1File, 'T1 image');
    end
    source.maskFile = maskFile;
    source.surfaceMaskFile = opts.surfaceMaskFile;
    source.t1File = t1File;
end

function [maskFile, role] = subjectHeadSurfaceMask(S)
    maskFile = '';
    role = '';
    if ~isstruct(S) || ~isfield(S, 'subjectMasks') || ...
            ~isstruct(S.subjectMasks) || ~isfield(S.subjectMasks, 'files') || ...
            ~isstruct(S.subjectMasks.files)
        return;
    end
    files = S.subjectMasks.files;
    preferred = {'headMask', 'skinShellMask'};
    for i = 1:numel(preferred)
        if isfield(files, preferred{i}) && ~isempty(files.(preferred{i}))
            maskFile = expandUserPath(char(files.(preferred{i})));
            role = ['segOut.subjectMasks.files.' preferred{i}];
            return;
        end
    end
end

function value = chooseIfEmpty(value, fallback)
    if isempty(value)
        value = fallback;
    end
end

function fileName = defaultOutputFile(maskFile, outputTag)
    [folder, stem] = fileparts(maskFile);
    stem = regexprep(stem, '_T1orT2_SPM_masks.*$', '');
    fileName = fullfile(folder, [stem '_' outputTag '.mat']);
end

function out = reuseOutput(cacheFile, maskFile, t1File, source, opts)
    out = struct();
    out.createdOn = char(datetime('now'));
    out.type = 'roastScalpSkinCache';
    out.cacheFile = cacheFile;
    out.outputFile = cacheFile;
    out.maskFile = maskFile;
    out.t1File = t1File;
    out.coordinateFrame = 'capMakerPreCropWorldMm';
    out.source = source;
    out.reusedExistingCache = true;
    out.qcFigure = '';
    out.figure = [];
    try
        S = load(cacheFile, 'TRstableHead');
        if isfield(S, 'TRstableHead')
            out.meshStats = meshStats(S.TRstableHead);
        end
    catch
    end

    if opts.showFigures || opts.saveFigures
        S = load(cacheFile, 'TRstableHead');
        if isfield(S, 'TRstableHead') && ~isempty(S.TRstableHead)
            Vmask = spm_vol(maskFile);
            Vmask = Vmask(1);
            labels = uint8(round(spm_read_vols(Vmask)));
            [headMask, ~] = makeCanonicalSurfaceMask(labels, Vmask, opts);
            figVisible = 'off';
            if opts.showFigures
                figVisible = 'on';
            end
            fig = makeQcFigure(labels, headMask, S.TRstableHead, ...
                Vmask, opts, figVisible);
            if opts.saveFigures
                qcFile = fullfile(fileparts(cacheFile), 'qc', ...
                    [stripMatExtension(getFileName(cacheFile)) '_qc.png']);
                ensureDir(fileparts(qcFile));
                saveQcFigure(fig, qcFile);
                out.qcFigure = qcFile;
            end
            if opts.showFigures
                out.figure = fig;
            elseif isgraphics(fig)
                close(fig);
            end
        end
    end
end

function reason = skinCacheReuseBlocker(cacheFile, source)
    reason = '';
    try
        S = load(cacheFile, 'meta', 'cacheInfo', 'TRstableHead');
    catch ME
        reason = ['could not load cache: ' ME.message];
        return;
    end
    if ~isfield(S, 'TRstableHead') || isempty(S.TRstableHead)
        reason = 'TRstableHead is missing';
        return;
    end

    cachedSurfaceMask = '';
    if isfield(S, 'meta') && isstruct(S.meta) && ...
            isfield(S.meta, 'maskInfo') && isstruct(S.meta.maskInfo) && ...
            isfield(S.meta.maskInfo, 'surfaceMaskFile')
        cachedSurfaceMask = char(S.meta.maskInfo.surfaceMaskFile);
    elseif isfield(S, 'cacheInfo') && isstruct(S.cacheInfo) && ...
            isfield(S.cacheInfo, 'maskInfo') && isstruct(S.cacheInfo.maskInfo) && ...
            isfield(S.cacheInfo.maskInfo, 'surfaceMaskFile')
        cachedSurfaceMask = char(S.cacheInfo.maskInfo.surfaceMaskFile);
    end
    requestedSurfaceMask = char(getOptionalField(source, ...
        'surfaceMaskFile', ''));
    if ~samePathOrBothEmpty(cachedSurfaceMask, requestedSurfaceMask)
        reason = sprintf('surface mask changed from "%s" to "%s"', ...
            cachedSurfaceMask, requestedSurfaceMask);
    end
end

function tf = samePathOrBothEmpty(a, b)
    a = char(a);
    b = char(b);
    if isempty(a) && isempty(b)
        tf = true;
    elseif isempty(a) || isempty(b)
        tf = false;
    else
        tf = strcmpi(normalizePathForCompare(a), normalizePathForCompare(b));
    end
end

function value = normalizePathForCompare(value)
    value = expandUserPath(char(value));
    try
        if exist(value, 'file') == 2 || exist(value, 'dir') == 7
            value = char(java.io.File(value).getCanonicalPath());
        end
    catch
    end
    value = lower(strrep(value, '/', filesep));
end

function [headMask, info] = makeCanonicalSurfaceMask(labels, Vmask, opts)
    if ~isempty(opts.surfaceMaskFile)
        [surfaceMask, fileInfo] = readSurfaceMaskFile(opts.surfaceMaskFile, Vmask);
        [headMask, info] = cleanLogicalSurfaceMask(surfaceMask, opts);
        info.surfaceSource = 'surfaceMaskFile';
        info.surfaceMaskFile = opts.surfaceMaskFile;
        info.surfaceMaskRole = char(getOptionalField(opts, ...
            'surfaceMaskRole', fileInfo.role));
        info.surfaceMaskVoxelCount = fileInfo.voxelCount;
        return;
    end

    [headMask, info] = makeSolidHeadMask(labels, opts);
    info.surfaceSource = 'hardLabelMask';
    info.surfaceMaskFile = '';
    info.surfaceMaskRole = 'labels > 0 after optional air cleanup';
end

function [surfaceMask, info] = readSurfaceMaskFile(maskFile, Vref)
    Vsurf = spm_vol(maskFile);
    Vsurf = Vsurf(1);
    if any(double(Vsurf.dim(1:3)) ~= double(Vref.dim(1:3)))
        error('acsBuildRoastScalpSkinCache:SurfaceMaskDimMismatch', ...
            ['Surface mask dimensions do not match the ROAST mask.\n', ...
             '  surface: %s [%s]\n  ROAST: %s [%s]'], ...
            maskFile, sprintf('%d ', Vsurf.dim(1:3)), ...
            Vref.fname, sprintf('%d ', Vref.dim(1:3)));
    end
    surfaceMask = spm_read_vols(Vsurf) > 0;
    info = struct('file', maskFile, ...
        'role', 'canonical external head mask', ...
        'voxelCount', nnz(surfaceMask));
end

function [headMask, info] = cleanLogicalSurfaceMask(mask, opts)
    headMask = logical(mask);
    info = struct();
    info.headLabels = [];
    info.initialVoxelCount = nnz(headMask);
    info.keepLargestComponent = opts.keepLargestComponent;
    info.clearBoundaryAir = false;
    info.boundaryAirVoxelCount = 0;
    info.fillInternalHoles = opts.fillInternalHoles;
    info.componentCountBefore = NaN;
    info.componentCountAfter = NaN;
    info.removedVoxelCount = 0;
    info.filledVoxelCount = 0;

    if opts.keepLargestComponent
        [headMask, largestInfo] = keepLargest3dComponent(headMask);
        info.componentCountBefore = largestInfo.componentCountBefore;
        info.componentCountAfter = largestInfo.componentCountAfter;
        info.removedVoxelCount = largestInfo.removedVoxelCount;
    end
    if opts.fillInternalHoles
        before = headMask;
        headMask = fillInternal3dHoles(headMask);
        info.filledVoxelCount = nnz(headMask & ~before);
    end
    info.finalVoxelCount = nnz(headMask);
end

function [headMask, info] = makeSolidHeadMask(labels, opts)
    boundaryAirVoxelCount = 0;
    if opts.clearBoundaryAir
        before = labels == uint8(6);
        labels = clearBoundaryConnectedValue(labels, uint8(6));
        boundaryAirVoxelCount = nnz(before & labels ~= uint8(6));
    end

    if isempty(opts.headLabels)
        headMask = labels > 0;
        labelSet = unique(labels(headMask));
    else
        headMask = ismember(labels, opts.headLabels);
        labelSet = opts.headLabels;
    end
    info = struct();
    info.headLabels = double(labelSet(:)');
    info.initialVoxelCount = nnz(headMask);
    info.keepLargestComponent = opts.keepLargestComponent;
    info.clearBoundaryAir = opts.clearBoundaryAir;
    info.boundaryAirVoxelCount = boundaryAirVoxelCount;
    info.fillInternalHoles = opts.fillInternalHoles;
    info.componentCountBefore = NaN;
    info.componentCountAfter = NaN;
    info.removedVoxelCount = 0;
    info.filledVoxelCount = 0;

    if opts.keepLargestComponent
        [headMask, largestInfo] = keepLargest3dComponent(headMask);
        info.componentCountBefore = largestInfo.componentCountBefore;
        info.componentCountAfter = largestInfo.componentCountAfter;
        info.removedVoxelCount = largestInfo.removedVoxelCount;
    end
    if opts.fillInternalHoles
        before = headMask;
        headMask = fillInternal3dHoles(headMask);
        info.filledVoxelCount = nnz(headMask & ~before);
    end
    info.finalVoxelCount = nnz(headMask);
end

function labels = clearBoundaryConnectedValue(labels, labelValue)
    mask = labels == labelValue;
    if ~any(mask(:))
        return;
    end
    boundary = volumeBoundaryMask(size(labels));
    seed = mask & boundary;
    if ~any(seed(:))
        return;
    end
    exterior = connectedFromSeed(mask, seed);
    labels(exterior) = 0;
end

function boundary = volumeBoundaryMask(dims)
    boundary = false(dims);
    boundary(1, :, :) = true;
    boundary(end, :, :) = true;
    boundary(:, 1, :) = true;
    boundary(:, end, :) = true;
    boundary(:, :, 1) = true;
    boundary(:, :, end) = true;
end

function reached = connectedFromSeed(mask, seed)
    if exist('imreconstruct', 'file') == 2
        reached = imreconstruct(seed, mask) > 0;
        return;
    end

    reached = false(size(mask));
    frontier = seed & mask;
    se = false(3, 3, 3);
    se(2, 2, 1) = true;
    se(2, 2, 3) = true;
    se(2, 1, 2) = true;
    se(2, 3, 2) = true;
    se(1, 2, 2) = true;
    se(3, 2, 2) = true;

    while any(frontier(:))
        reached = reached | frontier;
        frontier = imdilate(frontier, se) & mask & ~reached;
    end
end

function [maskOut, info] = keepLargest3dComponent(maskIn)
    maskOut = logical(maskIn);
    info = struct('componentCountBefore', 0, ...
        'componentCountAfter', 0, ...
        'removedVoxelCount', 0);
    if exist('bwconncomp', 'file') ~= 2
        warning('acsBuildRoastScalpSkinCache:MissingBwconncomp', ...
            'bwconncomp unavailable; keeping all head-mask components.');
        return;
    end
    CC = bwconncomp(maskOut, 26);
    info.componentCountBefore = CC.NumObjects;
    if CC.NumObjects <= 1
        info.componentCountAfter = CC.NumObjects;
        return;
    end
    sizes = cellfun(@numel, CC.PixelIdxList);
    [~, keepIdx] = max(sizes);
    keep = false(size(maskOut));
    keep(CC.PixelIdxList{keepIdx}) = true;
    info.removedVoxelCount = nnz(maskOut & ~keep);
    maskOut = keep;
    info.componentCountAfter = 1;
end

function maskOut = fillInternal3dHoles(maskIn)
    maskOut = logical(maskIn);
    if exist('bwconncomp', 'file') ~= 2
        return;
    end
    exterior = ~maskOut;
    CC = bwconncomp(exterior, 6);
    if CC.NumObjects == 0
        return;
    end
    dims = size(maskOut);
    boundary = false(dims);
    boundary(1, :, :) = true;
    boundary(end, :, :) = true;
    boundary(:, 1, :) = true;
    boundary(:, end, :) = true;
    boundary(:, :, 1) = true;
    boundary(:, :, end) = true;
    keepExterior = false(dims);
    for i = 1:CC.NumObjects
        vox = CC.PixelIdxList{i};
        if any(boundary(vox))
            keepExterior(vox) = true;
        end
    end
    maskOut = ~keepExterior;
end

function [TR, info] = solidMaskToWorldSurface(mask, mat, opts)
    rows = find(mask);
    if isempty(rows)
        error('acsBuildRoastScalpSkinCache:EmptyHeadMask', ...
            'No voxels were available for scalp surface extraction.');
    end
    dims = size(mask);
    [i, j, k] = ind2sub(dims, rows);
    lo = max([1 1 1], min([i j k], [], 1) - 2);
    hi = min(double(dims), max([i j k], [], 1) + 2);
    local = mask(lo(1):hi(1), lo(2):hi(2), lo(3):hi(3));
    padded = false(size(local) + 2);
    padded(2:end - 1, 2:end - 1, 2:end - 1) = local;

    values = single(padded);
    if opts.surfaceSmoothingSigmaVox > 0 && exist('imgaussfilt3', 'file') == 2
        values = imgaussfilt3(values, opts.surfaceSmoothingSigmaVox);
    end
    [X, Y, Z] = localWorldGrid(size(padded), lo, mat);
    fv = isosurface(X, Y, Z, values, 0.5);
    if isempty(fv) || isempty(fv.faces) || isempty(fv.vertices)
        error('acsBuildRoastScalpSkinCache:EmptySurface', ...
            'ROAST solid-head surface extraction returned no faces.');
    end
    info = struct();
    info.boundingBoxVoxel1 = [lo; hi];
    info.faceCountBeforeReduction = size(fv.faces, 1);
    info.vertexCountBeforeReduction = size(fv.vertices, 1);
    info.maxFaces = opts.maxFaces;
    info.reduced = false;

    if size(fv.faces, 1) > opts.maxFaces && exist('reducepatch', 'file') == 2
        try
            fv = reducepatch(fv, opts.maxFaces);
            info.reduced = true;
        catch ME
            warning('acsBuildRoastScalpSkinCache:ReducepatchFailed', ...
                'Surface reduction failed: %s', ME.message);
        end
    end

    TR = triangulation(double(fv.faces), double(fv.vertices));
    if opts.smoothIterations > 0 && exist('laplacianSmoothTR', 'file') == 2
        TR = laplacianSmoothTR(TR, opts.smoothIterations, 0.5);
    end
    if exist('unifyOutwardNormalsRobust', 'file') == 2
        try
            TR = unifyOutwardNormalsRobust(TR);
        catch ME
            warning('acsBuildRoastScalpSkinCache:NormalRepairFailed', ...
                'Could not repair ROAST scalp mesh normals: %s', ME.message);
        end
    end
    info.faceCountAfterReduction = size(TR.ConnectivityList, 1);
    info.vertexCountAfterReduction = size(TR.Points, 1);
end

function [X, Y, Z] = localWorldGrid(localSize, lo, mat)
    % Padded local index 1 corresponds to global voxel index lo-1.
    i0 = (lo(1) - 2):(lo(1) + localSize(1) - 3);
    j0 = (lo(2) - 2):(lo(2) + localSize(2) - 3);
    k0 = (lo(3) - 2):(lo(3) + localSize(3) - 3);
    voxelSize = voxelSizesFromMat(mat);
    [I, J, K] = ndgrid(i0 .* voxelSize(1), ...
        j0 .* voxelSize(2), k0 .* voxelSize(3));
    X = I;
    Y = J;
    Z = K;
end

function meta = makeSkinCacheMeta(Vmask, maskFile, t1File, source, TR, ...
        maskInfo, surfaceInfo, opts)
    voxelSize = voxelSizesFromMat(Vmask.mat);
    dims = double(Vmask.dim(1:3));
    simpleVox2world = eye(4);
    simpleVox2world(1:3, 1:3) = diag(voxelSize);

    meta = struct();
    meta.createdOn = char(datetime('now'));
    meta.source = source;
    meta.source.type = 'roastCanonicalScalpMask';
    meta.source.maskFile = maskFile;
    meta.source.t1File = t1File;
    meta.vox2world = simpleVox2world;
    meta.bboxWorld = [0 0 0; (dims - 1) .* voxelSize];
    meta.voxelSize = voxelSize;
    meta.units = 'mm';
    meta.extentWorldMM = (dims - 1) .* voxelSize;
    meta.unitScale = 1;

    meta.print.used = true;
    meta.print.T_world2print = eye(4);
    meta.print.T_print2world = eye(4);

    meta.fiducialHead.available = true;
    meta.fiducialHead.cacheVariable = 'TRfiducialHead';
    meta.fiducialHead.coordinateFrame = 'capMakerPreCropWorldMm';
    meta.fiducialHead.sourceFrame = 'capMakerPreCropWorldMm';
    meta.fiducialHead.description = ['ROAST-derived full-head scalp ', ...
        'surface for model fiducials and phone-scan registration.'];
    meta.fiducialHead.pointCount = size(TR.Points, 1);
    meta.fiducialHead.faceCount = size(TR.ConnectivityList, 1);
    meta.fiducialHead.boundsWorldMM = [min(TR.Points, [], 1); ...
        max(TR.Points, [], 1)];

    meta.stableHead.available = true;
    meta.stableHead.cacheVariable = 'TRstableHead';
    meta.stableHead.coordinateFrame = 'capMakerPreCropWorldMm';
    meta.stableHead.description = ['ROAST-derived full-head external ', ...
        'solid-head surface before phone warp and cap crop.'];
    meta.stableHead.pointCount = size(TR.Points, 1);
    meta.stableHead.faceCount = size(TR.ConnectivityList, 1);
    meta.stableHead.boundsWorldMM = meta.fiducialHead.boundsWorldMM;

    meta.original.size = dims;
    meta.original.voxelSize = voxelSize;
    meta.original.vox2world = simpleVox2world;
    meta.original.permuteDims = [1 2 3];
    meta.original.flipDims = [false false false];
    meta.original.targetIsoMM = min(voxelSize);
    meta.original.orientation = 'ras';

    meta.align.used = false;
    meta.align.R = eye(3);
    meta.align.dir = [0 0.3 1] ./ norm([0 0.3 1]);
    meta.align.side = 'top';
    meta.align.frac = NaN;
    meta.align.distance = NaN;

    meta.roastScalp = struct();
    if ~isempty(getOptionalField(maskInfo, 'surfaceMaskFile', ''))
        meta.roastScalp.method = 'external surface of segmentation head mask in ROAST/T1 frame';
    else
        meta.roastScalp.method = 'external surface of ROAST solid-head label mask';
    end
    meta.roastScalp.maskInfo = maskInfo;
    meta.roastScalp.surfaceInfo = surfaceInfo;
    meta.roastScalp.options = opts;
end

function voxelSize = voxelSizesFromMat(M)
    voxelSize = sqrt(sum(double(M(1:3, 1:3)) .^ 2, 1));
    voxelSize(~isfinite(voxelSize) | voxelSize <= 0) = 1;
end

function fig = makeQcFigure(labels, headMask, TR, Vmask, opts, figVisible)
    fig = figure('Name', 'ROAST-derived scalp cache QC', ...
        'NumberTitle', 'off', 'Color', 'w', 'Visible', figVisible, ...
        'WindowStyle', 'normal', ...
        'Units', 'pixels', 'Position', safeFigurePosition([1200 720]));
    annotation(fig, 'textbox', [0.02 0.955 0.96 0.035], ...
        'String', 'ROAST-derived scalp cache QC', ...
        'Interpreter', 'none', 'FontSize', 13, 'FontWeight', 'bold', ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', ...
        'EdgeColor', 'none');

    ax3 = axes('Parent', fig, 'Position', [0.04 0.08 0.46 0.84]);
    patch(ax3, 'Faces', TR.ConnectivityList, 'Vertices', TR.Points, ...
        'FaceColor', [0.72 0.76 0.78], ...
        'FaceAlpha', 1, 'EdgeColor', 'none', ...
        'FaceLighting', 'flat', 'AmbientStrength', 0.75, ...
        'DiffuseStrength', 0.30, 'SpecularStrength', 0);
    axis(ax3, 'equal');
    axis(ax3, 'vis3d');
    axis(ax3, 'off');
    view(ax3, 35, 22);
    camlight(ax3, 'headlight');
    lighting(ax3, 'flat');
    title(ax3, sprintf('External solid-head surface (%d faces)', ...
        size(TR.ConnectivityList, 1)), 'Interpreter', 'none');

    sliceInd = chooseSliceIndices(headMask);
    planeNames = {'Sagittal', 'Coronal', 'Axial'};
    slicePositions = [ ...
        0.56 0.68 0.38 0.24; ...
        0.56 0.38 0.38 0.24; ...
        0.56 0.08 0.38 0.24];
    for dimToFix = 1:3
        ax = axes('Parent', fig, 'Position', slicePositions(dimToFix, :));
        drawSlice(ax, labels, headMask, dimToFix, sliceInd(dimToFix), Vmask);
        title(ax, sprintf('%s %d', planeNames{dimToFix}, ...
            sliceInd(dimToFix)), 'Interpreter', 'none', ...
            'FontSize', 10, 'FontWeight', 'bold');
    end
    if opts.verbose
        drawnow;
    end
end

function pos = safeFigurePosition(preferredSize)
    margin = 80;
    try
        oldUnits = get(groot, 'Units');
        set(groot, 'Units', 'pixels');
        screen = get(groot, 'ScreenSize');
        set(groot, 'Units', oldUnits);
    catch
        screen = [1 1 1280 800];
    end
    maxW = max(640, screen(3) - 2 * margin);
    maxH = max(480, screen(4) - 2 * margin);
    w = min(preferredSize(1), maxW);
    h = min(preferredSize(2), maxH);
    x = screen(1) + max(20, (screen(3) - w) / 2);
    y = screen(2) + max(40, (screen(4) - h) / 2);
    pos = round([x y w h]);
end

function sliceInd = chooseSliceIndices(mask)
    dims = size(mask);
    rows = find(mask);
    if isempty(rows)
        sliceInd = round(dims ./ 2);
        return;
    end
    [i, j, k] = ind2sub(dims, rows);
    sliceInd = round(median([i j k], 1));
    sliceInd = max([1 1 1], min(dims, sliceInd));
end

function drawSlice(ax, labels, headMask, dimToFix, idx, Vmask)
    [img, xvec, yvec] = sliceForDisplay(single(labels), dimToFix, idx);
    [headSlice, ~, ~] = sliceForDisplay(headMask, dimToFix, idx);
    imagesc(ax, xvec, yvec, img);
    set(ax, 'YDir', 'normal');
    axis(ax, 'image');
    axis(ax, 'off');
    colormap(ax, gray);
    hold(ax, 'on');
    if any(headSlice(:))
        contour(ax, xvec, yvec, double(headSlice), [0.5 0.5], ...
            'Color', [0.0 0.7 0.25], 'LineWidth', 1.0);
    end
    xlabel(ax, sprintf('voxel dim in %.3g mm units', min(voxelSizesFromMat(Vmask.mat))));
end

function [img, xvec, yvec] = sliceForDisplay(vol, dimToFix, idx)
    dims = size(vol);
    switch dimToFix
        case 1
            raw = squeeze(vol(idx, :, :));
            img = raw';
            xvec = 1:dims(2);
            yvec = 1:dims(3);
        case 2
            raw = squeeze(vol(:, idx, :));
            img = raw';
            xvec = 1:dims(1);
            yvec = 1:dims(3);
        case 3
            raw = squeeze(vol(:, :, idx));
            img = raw';
            xvec = 1:dims(1);
            yvec = 1:dims(2);
    end
end

function stats = meshStats(TR)
    V = double(TR.Points);
    stats = struct();
    stats.nVertices = size(V, 1);
    stats.nFaces = size(TR.ConnectivityList, 1);
    stats.bounds = [min(V, [], 1); max(V, [], 1)];
    stats.centroid = mean(V, 1);
    stats.span = diff(stats.bounds, 1, 1);
end

function printSummary(out)
    fprintf('\nROAST-derived scalp skin cache\n');
    fprintf('  mask: %s\n', out.maskFile);
    if isfield(out.maskInfo, 'surfaceMaskFile') && ...
            ~isempty(out.maskInfo.surfaceMaskFile)
        fprintf('  surface mask: %s\n', out.maskInfo.surfaceMaskFile);
        fprintf('  surface source: %s\n', out.maskInfo.surfaceMaskRole);
    end
    fprintf('  cache: %s\n', out.cacheFile);
    fprintf('  surface: %d vertices, %d faces\n', ...
        out.meshStats.nVertices, out.meshStats.nFaces);
    fprintf('  bounds mm: X[%.1f %.1f], Y[%.1f %.1f], Z[%.1f %.1f]\n', ...
        out.meshStats.bounds(1, 1), out.meshStats.bounds(2, 1), ...
        out.meshStats.bounds(1, 2), out.meshStats.bounds(2, 2), ...
        out.meshStats.bounds(1, 3), out.meshStats.bounds(2, 3));
    fprintf('  head mask voxels: %d -> %d, components %g -> %g, filled %d\n', ...
        out.maskInfo.initialVoxelCount, out.maskInfo.finalVoxelCount, ...
        out.maskInfo.componentCountBefore, out.maskInfo.componentCountAfter, ...
        out.maskInfo.filledVoxelCount);
    if ~isempty(out.qcFigure)
        fprintf('  QC figure: %s\n', out.qcFigure);
    end
end

function saveQcFigure(fig, fileName)
    try
        exportgraphics(fig, fileName, 'Resolution', 220);
    catch
        saveas(fig, fileName);
    end
end

function writeJsonReport(fileName, report)
    try
        report = rmfieldIfPresent(report, {'figure'});
        fid = fopen(fileName, 'w');
        if fid < 0
            return;
        end
        cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
        fprintf(fid, '%s', jsonencode(report, 'PrettyPrint', true));
    catch
    end
end

function S = rmfieldIfPresent(S, names)
    for i = 1:numel(names)
        if isfield(S, names{i})
            S = rmfield(S, names{i});
        end
    end
end

function value = getOptionalField(S, fieldName, defaultValue)
    value = defaultValue;
    if isstruct(S) && isfield(S, fieldName) && ~isempty(S.(fieldName))
        value = S.(fieldName);
    end
end

function requireFile(fileName, description)
    if isempty(fileName) || exist(fileName, 'file') ~= 2
        error('acsBuildRoastScalpSkinCache:MissingFile', ...
            'Could not find %s: %s', description, fileName);
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

function fileName = expandUserPath(fileName)
    if isempty(fileName)
        return;
    end
    fileName = char(fileName);
    if startsWith(fileName, '~')
        fileName = fullfile(char(java.lang.System.getProperty('user.home')), ...
            fileName(2:end));
    end
end

function name = safeName(name)
    name = regexprep(char(name), '[^a-zA-Z0-9_]+', '_');
    name = regexprep(name, '_+', '_');
    name = regexprep(name, '^_|_$', '');
    if isempty(name)
        name = 'roastScalpSkinMesh';
    end
end

function fileName = replaceExtension(fileName, newExt)
    [folder, stem] = fileparts(fileName);
    fileName = fullfile(folder, [stem newExt]);
end

function name = getFileName(fileName)
    [~, stem, ext] = fileparts(fileName);
    name = [stem ext];
end

function stem = stripMatExtension(fileName)
    [~, stem, ext] = fileparts(fileName);
    if strcmpi(ext, '.mat')
        return;
    end
    stem = [stem ext];
end
