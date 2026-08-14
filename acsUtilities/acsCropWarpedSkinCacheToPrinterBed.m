function out = acsCropWarpedSkinCacheToPrinterBed(skinCacheFile, varargin)
% ACSCROPWARPEDSKINCACHETOPRINTERBED Crop a warped full-head skin cache for printing.
%
% out = acsCropWarpedSkinCacheToPrinterBed(skinCacheFile) reads a capMaker
% skin cache that contains TRstableHead, lets the user select or reuse a
% crop plane in the stable pre-crop world frame, clips the warped full-head
% surface to the printable cap footprint, rotates the crop plane to +Z, and
% writes a normal capMaker skin cache whose TRskin rests on printer-bed Z=0.
%
% Name-value options:
%   outputFile       : output skin cache MAT ['']
%   outputTag        : output suffix ['printerBedCrop']
%   cropPlaneFile    : saved crop-plane MAT ['']
%   cropPlaneMode    : 'autoSelect', 'select', 'reuse', 'auto', or 'default' ['autoSelect']
%   cropSide         : 'top' or 'bottom' half-space to keep ['top']
%   alignCrop        : rotate crop normal to +Z [true]
%   centerXY         : center cropped cap in printer XY [true]
%   dropToZ0         : translate cropped cap bottom to Z=0 [true]
%   contextObjectFile: phone object selection shown in crop GUI ['']
%   contextSourceSkinCacheFile : skin cache defining context object print frame ['']
%   contextPointMax  : max context points shown [2500]
%   displayMaxFaces  : max mesh faces shown in GUI [15000]
%   skinMaxFaces     : decimate output TRskin before saving [[] = no decimation]
%   keepLargestSkinComponent : drop small disconnected cap components [true]
%   minSkinComponentFaces : keep components with at least this many faces when
%                   keepLargestSkinComponent=false [0]
%   force            : overwrite existing output [false]
%   showFigures      : show crop/QC figures [true]
%   saveFigures      : save QC figure [true]
%   verbose          : print summary [true]

    if nargin < 1 || isempty(skinCacheFile)
        error('acsCropWarpedSkinCacheToPrinterBed:MissingInput', ...
            'Provide a warped capMaker skin cache file.');
    end

    opts = parseInputs(varargin{:});
    addLocalDependencies();

    skinCacheFile = expandUserPath(char(skinCacheFile));
    if exist(skinCacheFile, 'file') ~= 2
        error('acsCropWarpedSkinCacheToPrinterBed:SkinCacheNotFound', ...
            'Skin cache file not found: %s', skinCacheFile);
    end
    S = load(skinCacheFile);
    [TRstableHead, sourceMeta] = readStableHead(S, skinCacheFile);
    opts = resolveOutputPaths(skinCacheFile, opts);

    cropPlane = resolveCropPlane(TRstableHead, skinCacheFile, sourceMeta, opts);
    if exist(opts.outputFile, 'file') == 2 && ~opts.force && ...
            ~strcmp(opts.cropPlaneMode, 'select')
        Sout = load(opts.outputFile, 'meta', 'cropInfo', 'TRskin');
        if isfield(Sout, 'meta') && ...
                cachedMeshMatchesCropPlane(Sout.meta, cropPlane) && ...
                cachedOutputMatchesSkinMaxFaces(Sout, opts) && ...
                cachedOutputMatchesComponentCleanup(Sout, opts)
            out = reuseOutput(opts, cropPlane, skinCacheFile);
            if opts.verbose
                fprintf('Reusing cropped warped skin cache: %s\n', opts.outputFile);
            end
            return;
        end
    end

    [TRskin, TRfiducialHead, meta, cropInfo] = applyCropPlaneToStableHead( ...
        TRstableHead, sourceMeta, cropPlane, opts);

    ensureDir(fileparts(opts.outputFile));
    save(opts.outputFile, 'TRskin', 'TRfiducialHead', 'TRstableHead', ...
        'meta', 'cropInfo', '-v7.3');
    saveCropPlaneIfRequested(opts.cropPlaneFile, cropPlane);

    fig = [];
    qcFile = '';
    if opts.showFigures || opts.saveFigures
        figVisible = 'off';
        if opts.showFigures
            figVisible = 'on';
        end
        fig = makeQcFigure(TRstableHead, TRskin, TRfiducialHead, ...
            cropPlane, cropInfo, opts, figVisible);
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
    out.type = 'croppedWarpedSkinCache';
    out.inputFile = skinCacheFile;
    out.cacheFile = opts.outputFile;
    out.outputFile = opts.outputFile;
    out.cropPlaneFile = opts.cropPlaneFile;
    out.cropPlane = cropPlane;
    out.qcFigure = qcFile;
    out.meshStats = struct( ...
        'stableHead', meshStats(TRstableHead), ...
        'fiducialHead', meshStats(TRfiducialHead), ...
        'skin', meshStats(TRskin));
    out.cropInfo = cropInfo;
    out.options = opts;
    if isgraphics(fig)
        out.figure = fig;
    end

    outForSave = out;
    if isfield(outForSave, 'figure')
        outForSave = rmfield(outForSave, 'figure');
    end
    save([opts.outputFile(1:end - 4) '_report.mat'], 'outForSave', '-v7.3');

    if opts.verbose
        printSummary(out);
    end
end

function opts = parseInputs(varargin)
    p = inputParser;
    p.FunctionName = 'acsCropWarpedSkinCacheToPrinterBed';
    addParameter(p, 'outputFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'outputTag', 'printerBedCrop', @(x) ischar(x) || isstring(x));
    addParameter(p, 'cropPlaneFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'cropPlaneMode', 'autoSelect', @(x) ischar(x) || isstring(x));
    addParameter(p, 'cropSide', 'top', @(x) ischar(x) || isstring(x));
    addParameter(p, 'alignCrop', true, @isBoolLike);
    addParameter(p, 'centerXY', true, @isBoolLike);
    addParameter(p, 'dropToZ0', true, @isBoolLike);
    addParameter(p, 'contextObjectFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'contextSourceSkinCacheFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'contextPointMax', 2500, @isPositiveScalar);
    addParameter(p, 'displayMaxFaces', 15000, @isPositiveScalar);
    addParameter(p, 'skinMaxFaces', [], @(x) isempty(x) || isPositiveScalar(x));
    addParameter(p, 'keepLargestSkinComponent', true, @isBoolLike);
    addParameter(p, 'minSkinComponentFaces', 0, @isNonnegativeScalar);
    addParameter(p, 'force', false, @isBoolLike);
    addParameter(p, 'showFigures', true, @isBoolLike);
    addParameter(p, 'saveFigures', true, @isBoolLike);
    addParameter(p, 'verbose', true, @isBoolLike);
    parse(p, varargin{:});

    opts = p.Results;
    opts.outputFile = expandUserPath(char(opts.outputFile));
    opts.outputTag = safeName(char(opts.outputTag));
    opts.cropPlaneFile = expandUserPath(char(opts.cropPlaneFile));
    opts.cropPlaneMode = normalizeCropPlaneMode(opts.cropPlaneMode);
    opts.cropSide = normalizeCropSide(opts.cropSide);
    opts.alignCrop = logical(opts.alignCrop);
    opts.centerXY = logical(opts.centerXY);
    opts.dropToZ0 = logical(opts.dropToZ0);
    opts.contextObjectFile = expandUserPath(char(opts.contextObjectFile));
    opts.contextSourceSkinCacheFile = expandUserPath(char(opts.contextSourceSkinCacheFile));
    opts.contextPointMax = round(double(opts.contextPointMax));
    opts.displayMaxFaces = round(double(opts.displayMaxFaces));
    if ~isempty(opts.skinMaxFaces)
        opts.skinMaxFaces = round(double(opts.skinMaxFaces));
    end
    opts.keepLargestSkinComponent = logical(opts.keepLargestSkinComponent);
    opts.minSkinComponentFaces = round(double(opts.minSkinComponentFaces));
    opts.force = logical(opts.force);
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

function mode = normalizeCropPlaneMode(mode)
    mode = lower(strtrim(char(mode)));
    switch regexprep(mode, '[\s_\-]+', '')
        case {'autoselect', 'selectifmissing', 'promptifmissing'}
            mode = 'autoSelect';
        case {'select', 'always'}
            mode = 'select';
        case {'reuse', 'load'}
            mode = 'reuse';
        case {'auto'}
            mode = 'auto';
        case {'default'}
            mode = 'default';
        otherwise
            error('acsCropWarpedSkinCacheToPrinterBed:BadCropMode', ...
                'cropPlaneMode must be autoSelect, select, reuse, auto, or default.');
    end
end

function side = normalizeCropSide(side)
    side = lower(strtrim(char(side)));
    switch side
        case {'top', 'dorsal', 'above', 'keepabove'}
            side = 'top';
        case {'bottom', 'ventral', 'below', 'keepbelow'}
            side = 'bottom';
        otherwise
            error('acsCropWarpedSkinCacheToPrinterBed:BadCropSide', ...
                'cropSide must be ''top'' or ''bottom''.');
    end
end

function addLocalDependencies()
    repoRoot = fileparts(fileparts(mfilename('fullpath')));
    addpath(fullfile(repoRoot, 'acsUtilities'));
    addpath(fullfile(repoRoot, 'capMaker', 'core'));
end

function opts = resolveOutputPaths(inputFile, opts)
    [folder, stem] = fileparts(inputFile);
    if isempty(opts.outputFile)
        opts.outputFile = fullfile(folder, [stem '_' opts.outputTag '.mat']);
    end
    if isempty(opts.cropPlaneFile)
        opts.cropPlaneFile = fullfile(folder, [stem '_' opts.outputTag '_cropPlane.mat']);
    elseif ~endsWith(lower(opts.cropPlaneFile), '.mat')
        opts.cropPlaneFile = [opts.cropPlaneFile '.mat'];
    end
end

function tf = cachedOutputMatchesSkinMaxFaces(S, opts)
    if isempty(opts.skinMaxFaces)
        tf = true;
        return;
    end
    if ~isfield(S, 'TRskin') || isempty(S.TRskin)
        tf = false;
        return;
    end
    nFaces = size(S.TRskin.ConnectivityList, 1);
    tf = nFaces <= opts.skinMaxFaces;
    if isfield(S, 'cropInfo') && isstruct(S.cropInfo) && ...
            isfield(S.cropInfo, 'outputSkinDecimation') && ...
            isstruct(S.cropInfo.outputSkinDecimation) && ...
            isfield(S.cropInfo.outputSkinDecimation, 'requestedMaxFaces')
        requestedMaxFaces = S.cropInfo.outputSkinDecimation.requestedMaxFaces;
        if isempty(requestedMaxFaces)
            tf = false;
        else
            tf = tf && double(requestedMaxFaces) == double(opts.skinMaxFaces);
        end
    end
end

function tf = cachedOutputMatchesComponentCleanup(S, opts)
    tf = false;
    if ~isfield(S, 'cropInfo') || ~isstruct(S.cropInfo) || ...
            ~isfield(S.cropInfo, 'skinComponentCleanup') || ...
            ~isstruct(S.cropInfo.skinComponentCleanup)
        return;
    end
    c = S.cropInfo.skinComponentCleanup;
    expectedEnabled = opts.keepLargestSkinComponent || opts.minSkinComponentFaces > 0;
    if ~isfield(c, 'enabled') || logical(c.enabled) ~= expectedEnabled
        return;
    end
    if opts.keepLargestSkinComponent
        tf = isfield(c, 'mode') && strcmpi(char(c.mode), 'largest');
    elseif opts.minSkinComponentFaces > 0
        tf = isfield(c, 'mode') && strcmpi(char(c.mode), 'minFaces');
    else
        tf = true;
    end
end

function [TRstableHead, meta] = readStableHead(S, fileName)
    if isfield(S, 'TRstableHead') && ~isempty(S.TRstableHead)
        TRstableHead = ensureTriangulation(S.TRstableHead);
    elseif isfield(S, 'meta') && isstruct(S.meta) && ...
            isfield(S.meta, 'stableHead') && isstruct(S.meta.stableHead) && ...
            isfield(S.meta.stableHead, 'TR') && ~isempty(S.meta.stableHead.TR)
        TRstableHead = ensureTriangulation(S.meta.stableHead.TR);
    else
        error('acsCropWarpedSkinCacheToPrinterBed:MissingStableHead', ...
            ['Skin cache does not contain TRstableHead. Rebuild/warp from ', ...
             'a skin cache that preserved the full-head stable mesh: %s'], fileName);
    end
    meta = getOptionalField(S, 'meta', struct());
end

function cropPlane = resolveCropPlane(TRstableHead, inputFile, sourceMeta, opts)
    cropPlane = struct();
    if exist(opts.cropPlaneFile, 'file') == 2 && ...
            ~strcmp(opts.cropPlaneMode, 'select')
        cropPlane = loadCropPlane(opts.cropPlaneFile);
        if opts.verbose
            fprintf('Reusing warped-skin crop plane: %s\n', opts.cropPlaneFile);
        end
        return;
    elseif strcmp(opts.cropPlaneMode, 'reuse')
        error('acsCropWarpedSkinCacheToPrinterBed:CropPlaneNotFound', ...
            'Saved crop plane not found: %s', opts.cropPlaneFile);
    end

    V = double(TRstableHead.Points);
    cropAxis = defaultCropAxis(sourceMeta);
    s = V * cropAxis(:);
    if strcmp(opts.cropSide, 'top')
        cropDistance = percentileLocal(s, 30);
    else
        cropDistance = percentileLocal(s, 70);
    end

    openGui = opts.showFigures && ...
        (strcmp(opts.cropPlaneMode, 'select') || strcmp(opts.cropPlaneMode, 'autoSelect'));
    if openGui
        guiOpts = struct( ...
            'displayMaxFaces', opts.displayMaxFaces, ...
            'title', 'Crop warped scalp to printer bed', ...
            'contextPointsWorldMm', contextPointsPreCrop(opts), ...
            'contextPointLabels', {{'headpost'}});
        [cropAxis, cropDistance, accepted] = selectMeshCropPlane( ...
            TRstableHead, cropAxis, cropDistance, guiOpts);
        if ~accepted
            error('acsCropWarpedSkinCacheToPrinterBed:CropSelectionCanceled', ...
                'Warped-skin crop-plane selection was canceled.');
        end
    end

    cropPlane = struct();
    cropPlane.createdOn = char(datetime('now'));
    cropPlane.inputFile = inputFile;
    cropPlane.inputKind = 'warpedSkinCache';
    cropPlane.cropAxis = cropAxis(:)';
    cropPlane.cropDistance = double(cropDistance);
    cropPlane.cropSide = opts.cropSide;
    cropPlane.alignCrop = logical(opts.alignCrop);
end

function cropAxis = defaultCropAxis(meta)
    cropAxis = [0 0.3 1];
    if isstruct(meta) && isfield(meta, 'align') && ...
            isstruct(meta.align) && isfield(meta.align, 'dir') && ...
            ~isempty(meta.align.dir)
        cropAxis = double(meta.align.dir(:)');
    end
    cropAxis = cropAxis ./ max(norm(cropAxis), eps);
end

function points = contextPointsPreCrop(opts)
    points = zeros(0, 3);
    if isempty(opts.contextObjectFile) || exist(opts.contextObjectFile, 'file') ~= 2
        return;
    end
    S = loadStructFile(opts.contextObjectFile);
    if isfield(S, 'coordinatesMm') && ~isempty(S.coordinatesMm)
        points = double(S.coordinatesMm);
    elseif isfield(S, 'selectedCoordinatesMm') && ~isempty(S.selectedCoordinatesMm)
        points = double(S.selectedCoordinatesMm);
    else
        return;
    end
    frame = char(getOptionalField(S, 'coordinateFrame', 'capMakerPrintMm'));
    if strcmpi(frame, 'capMakerPreCropWorldMm')
        % Already in the desired crop-plane-independent frame.
    elseif strcmpi(frame, 'capMakerPrintMm')
        sourceFile = opts.contextSourceSkinCacheFile;
        if isempty(sourceFile)
            sourceFile = contextSourceFromPhoneObject(S);
        end
        if isempty(sourceFile) || exist(sourceFile, 'file') ~= 2
            warning('acsCropWarpedSkinCacheToPrinterBed:NoContextTransform', ...
                ['Could not transform context object points from print frame ', ...
                 'to pre-crop world; crop overlay will be omitted.']);
            points = zeros(0, 3);
            return;
        end
        raw = load(sourceFile, 'meta');
        if ~isfield(raw, 'meta')
            warning('acsCropWarpedSkinCacheToPrinterBed:NoContextMeta', ...
                'Context source skin cache lacks meta: %s', sourceFile);
            points = zeros(0, 3);
            return;
        end
        points = printMmToStableWorld(points, raw.meta);
    else
        warning('acsCropWarpedSkinCacheToPrinterBed:UnknownContextFrame', ...
            'Context object coordinateFrame "%s" is not supported for crop overlay.', frame);
        points = zeros(0, 3);
        return;
    end
    points = points(all(isfinite(points), 2), :);
    if size(points, 1) > opts.contextPointMax
        rows = unique(round(linspace(1, size(points, 1), opts.contextPointMax)));
        points = points(rows(:), :);
    end
end

function sourceFile = contextSourceFromPhoneObject(S)
    sourceFile = '';
    if isfield(S, 'source') && isstruct(S.source) && ...
            isfield(S.source, 'target') && isstruct(S.source.target) && ...
            isfield(S.source.target, 'file') && ~isempty(S.source.target.file)
        sourceFile = char(S.source.target.file);
        return;
    end
    if isfield(S, 'source') && isstruct(S.source) && ...
            isfield(S.source, 'file') && ~isempty(S.source.file) && ...
            exist(S.source.file, 'file') == 2
        try
            R = loadStructFile(S.source.file);
            if isfield(R, 'target') && isstruct(R.target) && ...
                    isfield(R.target, 'file') && ~isempty(R.target.file)
                sourceFile = char(R.target.file);
            end
        catch
            sourceFile = '';
        end
    elseif isfield(S, 'source') && isstruct(S.source) && ...
            isfield(S.source, 'registrationFile') && ...
            ~isempty(S.source.registrationFile) && ...
            exist(S.source.registrationFile, 'file') == 2
        try
            R = loadStructFile(S.source.registrationFile);
            if isfield(R, 'target') && isstruct(R.target) && ...
                    isfield(R.target, 'file') && ~isempty(R.target.file)
                sourceFile = char(R.target.file);
            end
        catch
            sourceFile = '';
        end
    end
end

function [TRskin, TRfiducialHead, meta, info] = applyCropPlaneToStableHead( ...
        TRstableHead, sourceMeta, cropPlane, opts)
    Vstable = double(TRstableHead.Points);
    F = double(TRstableHead.ConnectivityList);
    dir = double(cropPlane.cropAxis(:));
    dir = dir ./ max(norm(dir), eps);

    if cropPlane.alignCrop
        R = rotationFromVectorToZ(dir);
    else
        R = eye(3);
    end
    Vworld = (R * Vstable')';

    distance = double(cropPlane.cropDistance);
    z0 = distance;
    if strcmp(cropPlane.cropSide, 'bottom')
        Vwork = Vworld;
        Vwork(:, 3) = -Vwork(:, 3);
        TRwork = triangulation(F, Vwork);
        TRcropped = capBottomAtPlaneZ(TRwork, -z0, struct('reorient', true));
        Vcrop = double(TRcropped.Points);
        Vcrop(:, 3) = -Vcrop(:, 3);
        TRcropped = triangulation(TRcropped.ConnectivityList, Vcrop);
    else
        TRcropped = capBottomAtPlaneZ(triangulation(F, Vworld), z0, ...
            struct('reorient', true));
    end
    if isempty(TRcropped) || isempty(TRcropped.Points)
        error('acsCropWarpedSkinCacheToPrinterBed:EmptyCrop', ...
            'Crop plane removed the entire warped head mesh.');
    end
    [TRcropped, componentInfo] = cleanCroppedSkinComponents(TRcropped, opts);

    bb = [min(TRcropped.Points, [], 1); max(TRcropped.Points, [], 1)];
    t = [0 0 0];
    if opts.centerXY
        t(1) = -0.5 * (bb(1, 1) + bb(2, 1));
        t(2) = -0.5 * (bb(1, 2) + bb(2, 2));
    end
    if opts.dropToZ0
        t(3) = -bb(1, 3);
    end
    TRskinRaw = triangulation(TRcropped.ConnectivityList, TRcropped.Points + t);
    [TRskin, decimationInfo] = decimateOutputSkin(TRskinRaw, opts.skinMaxFaces);
    TRfiducialHead = triangulation(F, Vworld + t);

    T_world2print = eye(4);
    T_world2print(1:3, 4) = t(:);
    meta = sourceMeta;
    meta.units = 'mm';
    meta.print.used = true;
    meta.print.T_world2print = T_world2print;
    meta.print.T_print2world = inv(T_world2print);
    meta.align.used = cropPlane.alignCrop;
    meta.align.R = R;
    meta.align.dir = dir(:);
    meta.align.side = cropPlane.cropSide;
    meta.align.distance = distance;
    meta.align.frac = NaN;
    meta.fiducialHead.available = true;
    meta.fiducialHead.cacheVariable = 'TRfiducialHead';
    meta.fiducialHead.coordinateFrame = 'capMakerPrintMm';
    meta.fiducialHead.sourceFrame = 'capMakerPostCropWorldMm';
    meta.fiducialHead.pointCount = size(TRfiducialHead.Points, 1);
    meta.fiducialHead.faceCount = size(TRfiducialHead.ConnectivityList, 1);
    meta.stableHead.available = true;
    meta.stableHead.cacheVariable = 'TRstableHead';
    meta.stableHead.coordinateFrame = 'capMakerPreCropWorldMm';
    meta.stableHead.pointCount = size(TRstableHead.Points, 1);
    meta.stableHead.faceCount = size(TRstableHead.ConnectivityList, 1);
    meta.cropFromWarpedSkinCache = struct( ...
        'createdOn', char(datetime('now')), ...
        'method', 'mesh plane crop from warped stable full-head surface', ...
        'cropPlane', cropPlane);

    info = struct();
    info.rotation = R;
    info.translationMm = t;
    info.bedZMm = 0;
    info.prePrintCropBoundsMm = bb;
    info.printBoundsMm = [min(TRskin.Points, [], 1); max(TRskin.Points, [], 1)];
    info.outputSkinDecimation = decimationInfo;
    info.skinComponentCleanup = componentInfo;
end

function R = rotationFromVectorToZ(dir)
    dir = double(dir(:)) ./ max(norm(dir), eps);
    ez = [0; 0; 1];
    if dot(dir, ez) < 0
        dir = -dir;
    end
    v = cross(dir, ez);
    s = norm(v);
    c = dot(dir, ez);
    if s < 1e-12
        R = eye(3);
        return;
    end
    vx = [0 -v(3) v(2); v(3) 0 -v(1); -v(2) v(1) 0];
    R = eye(3) + vx + vx * vx * ((1 - c) / (s ^ 2));
end

function [cropAxis, cropDistance, accepted] = selectMeshCropPlane(TR, cropAxis, cropDistance, opts)
    V = double(TR.Points);
    F = double(TR.ConnectivityList);
    [Fdisplay, Vdisplay] = displayMeshForPatch(F, V, opts.displayMaxFaces);
    cropAxis = cropAxis(:) ./ max(norm(cropAxis), eps);
    accepted = false;
    dragStart = [];
    dragMode = '';

    anchor = mean(V(all(isfinite(V), 2), :), 1);
    bbMin = min(V, [], 1);
    bbMax = max(V, [], 1);
    diagMM = norm(bbMax - bbMin);
    if ~isfinite(diagMM) || diagMM <= 0
        diagMM = 100;
    end
    arrowLength = 1.1 * diagMM;
    planeHalfWidth = 0.65 * diagMM;
    contextPoints = getOptionalField(opts, 'contextPointsWorldMm', zeros(0, 3));

    fig = figure('Name', getOptionalField(opts, 'title', 'Crop warped scalp'), ...
        'NumberTitle', 'off', 'Color', 'w', 'Renderer', 'opengl', ...
        'CloseRequestFcn', @onCancel, ...
        'Position', [100 80 1180 760]);
    ax = axes('Parent', fig, 'Position', [0.04 0.08 0.74 0.86]);
    hold(ax, 'on');
    patch(ax, 'Faces', Fdisplay, 'Vertices', Vdisplay, ...
        'FaceColor', [0.78 0.80 0.83], ...
        'FaceAlpha', 1, ...
        'EdgeColor', 'none', ...
        'BackFaceLighting', 'reverselit');
    if ~isempty(contextPoints)
        scatter3(ax, contextPoints(:, 1), contextPoints(:, 2), ...
            contextPoints(:, 3), 18, [0.90 0.05 0.05], 'filled', ...
            'MarkerEdgeColor', 'none');
    end
    axis(ax, 'equal');
    axis(ax, 'vis3d');
    axis(ax, 'off');
    camproj(ax, 'orthographic');
    view(ax, 3);
    camtarget(ax, anchor);
    cameraLight = camlight(ax, 'headlight');
    lighting(ax, 'flat');

    axisArrow = quiver3(ax, anchor(1), anchor(2), anchor(3), ...
        0, 0, 0, 0, 'LineWidth', 2.5, ...
        'Color', [0 0.25 0.9], 'MaxHeadSize', 0.6);
    axisLine = plot3(ax, nan, nan, nan, ...
        'LineWidth', 2.0, 'Color', [0 0.25 0.9]);
    planePatch = patch(ax, 'Vertices', zeros(4, 3), ...
        'Faces', [1 2 3 4], ...
        'FaceColor', [0.95 0.15 0.1], ...
        'FaceAlpha', 0.16, ...
        'EdgeColor', [0.7 0 0], ...
        'LineWidth', 1.5);
    status = uicontrol(fig, 'Style', 'text', 'Units', 'normalized', ...
        'Position', [0.80 0.50 0.18 0.35], ...
        'BackgroundColor', 'w', 'HorizontalAlignment', 'left', ...
        'FontSize', 10);
    uicontrol(fig, 'Style', 'pushbutton', 'String', 'Done', ...
        'Units', 'normalized', 'Position', [0.81 0.22 0.16 0.08], ...
        'Callback', @onDone);
    uicontrol(fig, 'Style', 'pushbutton', 'String', 'Cancel', ...
        'Units', 'normalized', 'Position', [0.81 0.11 0.16 0.07], ...
        'Callback', @onCancel);

    updateGraphics();
    set(fig, 'WindowButtonDownFcn', @onMouseDown, ...
        'WindowButtonUpFcn', @onMouseUp, ...
        'WindowScrollWheelFcn', @onScroll, ...
        'WindowKeyPressFcn', @onKeyPress);
    uiwait(fig);
    if isgraphics(fig)
        delete(fig);
    end

    function onMouseDown(~, ~)
        clickedAxes = ancestor(hittest(fig), 'axes');
        if isempty(clickedAxes) || clickedAxes ~= ax
            return;
        end
        modifiers = get(fig, 'CurrentModifier');
        if hasAnyModifier(modifiers, {'control', 'command'})
            [rayOrigin, rayDirection] = clickRay(ax);
            clickPoint = rayPlaneIntersection(rayOrigin, rayDirection, ...
                anchor, cameraViewDirection(ax));
            newAxis = clickPoint - anchor;
            if norm(newAxis) > eps
                cropAxis = newAxis(:) / norm(newAxis);
                updateGraphics();
            end
        elseif hasAnyModifier(modifiers, {'alt', 'option'})
            [rayOrigin, rayDirection] = clickRay(ax);
            surfacePoint = closestVertexToRay(V, rayOrigin, rayDirection);
            cropDistance = dot(surfacePoint, cropAxis);
            updateGraphics();
        else
            dragStart = get(fig, 'CurrentPoint');
            if hasAnyModifier(modifiers, {'shift'})
                dragMode = 'roll';
            else
                dragMode = 'orbit';
            end
            set(fig, 'WindowButtonMotionFcn', @onDrag);
        end
    end

    function onDrag(~, ~)
        pointer = get(fig, 'CurrentPoint');
        delta = pointer - dragStart;
        dragStart = pointer;
        if strcmp(dragMode, 'roll')
            camroll(ax, delta(1) * 0.45);
        else
            camorbit(ax, -0.35 * delta(1), -0.35 * delta(2), 'camera');
        end
        camlight(cameraLight, 'headlight');
        drawnow limitrate;
    end

    function onMouseUp(~, ~)
        dragStart = [];
        dragMode = '';
        set(fig, 'WindowButtonMotionFcn', '');
    end

    function onScroll(~, event)
        cropDistance = cropDistance - event.VerticalScrollCount;
        updateGraphics();
    end

    function onKeyPress(~, event)
        switch lower(event.Key)
            case 'leftarrow'
                nudgeCropAxis([-1 0]);
            case 'rightarrow'
                nudgeCropAxis([1 0]);
            case 'uparrow'
                nudgeCropAxis([0 1]);
            case 'downarrow'
                nudgeCropAxis([0 -1]);
            case 'x'
                setCanonicalView([1 0 0], [0 0 1]);
            case 'y'
                setCanonicalView([0 1 0], [0 0 1]);
            case 'z'
                setCanonicalView([0 0 1], [0 1 0]);
        end
    end

    function nudgeCropAxis(screenStep)
        stepScale = 0.025;
        modifiers = get(fig, 'CurrentModifier');
        if hasAnyModifier(modifiers, {'shift'})
            stepScale = 5 * stepScale;
        end
        oldAxis = cropAxis(:) / norm(cropAxis);
        planeCenter = anchor(:) + (cropDistance - dot(anchor(:), oldAxis)) * oldAxis;
        [rightVec, upVec] = cameraScreenBasis(ax);
        deltaAxis = stepScale * (screenStep(1) * rightVec + screenStep(2) * upVec);
        cropAxis = oldAxis + deltaAxis(:);
        cropAxis = cropAxis ./ max(norm(cropAxis), eps);
        cropDistance = dot(planeCenter, cropAxis);
        updateGraphics();
    end

    function setCanonicalView(axisDirection, upDirection)
        cameraDistance = norm(campos(ax) - camtarget(ax));
        if ~isfinite(cameraDistance) || cameraDistance <= 0
            cameraDistance = 1.5 * diagMM;
        end
        camtarget(ax, anchor);
        campos(ax, anchor + cameraDistance * axisDirection);
        camup(ax, upDirection);
        camlight(cameraLight, 'headlight');
        drawnow limitrate;
    end

    function onDone(~, ~)
        accepted = true;
        uiresume(fig);
    end

    function onCancel(~, ~)
        accepted = false;
        uiresume(fig);
    end

    function updateGraphics()
        dir = cropAxis(:) / norm(cropAxis);
        planeCenter = anchor(:) + (cropDistance - dot(anchor(:), dir)) * dir;
        tail = anchor(:)' - 0.5 * arrowLength * dir(:)';
        head = anchor(:)' + 0.5 * arrowLength * dir(:)';
        set(axisArrow, 'XData', tail(1), 'YData', tail(2), 'ZData', tail(3), ...
            'UData', head(1) - tail(1), 'VData', head(2) - tail(2), ...
            'WData', head(3) - tail(3));
        set(axisLine, 'XData', [tail(1), head(1)], ...
            'YData', [tail(2), head(2)], 'ZData', [tail(3), head(3)]);
        set(planePatch, 'Vertices', cropPlaneQuad(planeCenter, dir, planeHalfWidth));
        nKeep = nnz((V * dir) >= cropDistance);
        set(status, 'String', sprintf([ ...
            'Mouse drag: orbit\nShift-drag: camera roll\n', ...
            'Wheel: move crop plane\nCtrl-click: aim crop vector\n', ...
            'Alt-click: move plane to surface\nArrows: nudge vector\n\n', ...
            'Kept vertices: %d / %d\nAxis: [%.3f %.3f %.3f]\nDistance: %.2f mm'], ...
            nKeep, size(V, 1), dir(1), dir(2), dir(3), cropDistance));
        drawnow limitrate;
    end
end

function q = cropPlaneQuad(center, dir, halfWidth)
    dir = dir(:) / norm(dir);
    aux = [1; 0; 0];
    if abs(dot(aux, dir)) > 0.9
        aux = [0; 1; 0];
    end
    u = cross(dir, aux);
    u = u / norm(u);
    v = cross(dir, u);
    q = [center(:)' + halfWidth * ( u + v)'; ...
         center(:)' + halfWidth * (-u + v)'; ...
         center(:)' + halfWidth * (-u - v)'; ...
         center(:)' + halfWidth * ( u - v)'];
end

function [origin, direction] = clickRay(ax)
    cp = get(ax, 'CurrentPoint');
    origin = cp(1, :);
    direction = cp(2, :) - cp(1, :);
    direction = direction ./ max(norm(direction), eps);
end

function point = closestVertexToRay(V, rayOrigin, rayDirection)
    d = rayDirection(:)' ./ max(norm(rayDirection), eps);
    W = bsxfun(@minus, V, rayOrigin);
    t = W * d(:);
    closest = bsxfun(@plus, rayOrigin, t .* d);
    dist2 = sum((V - closest) .^ 2, 2);
    dist2(t < 0) = inf;
    [~, idx] = min(dist2);
    point = V(idx, :);
end

function point = rayPlaneIntersection(origin, direction, planePoint, planeNormal)
    denom = dot(direction, planeNormal);
    if abs(denom) < 1e-9
        point = planePoint;
    else
        point = origin + dot(planePoint - origin, planeNormal) / denom * direction;
    end
end

function dir = cameraViewDirection(ax)
    dir = camtarget(ax) - campos(ax);
    dir = dir(:) ./ max(norm(dir), eps);
end

function [rightVec, upVec] = cameraScreenBasis(ax)
    viewDir = cameraViewDirection(ax);
    upVec = get(ax, 'CameraUpVector');
    upVec = upVec(:) ./ max(norm(upVec), eps);
    rightVec = cross(viewDir, upVec);
    rightVec = rightVec ./ max(norm(rightVec), eps);
    upVec = cross(rightVec, viewDir);
    upVec = upVec ./ max(norm(upVec), eps);
end

function tf = hasAnyModifier(modifiers, names)
    if ischar(modifiers)
        modifiers = {modifiers};
    end
    tf = any(ismember(lower(modifiers), lower(names)));
end

function [Fdisp, Vdisp] = displayMeshForPatch(F, V, maxFaces)
    Fdisp = double(F);
    Vdisp = double(V);
    if isempty(maxFaces) || size(Fdisp, 1) <= maxFaces
        return;
    end
    if exist('reducepatch', 'file') ~= 2
        warning('acsCropWarpedSkinCacheToPrinterBed:NoReducepatch', ...
            ['reducepatch is unavailable; displaying the full mesh instead ', ...
             'of a face-sampled mesh with holes.']);
        return;
    end
    try
        [F2, V2] = reducepatch(Fdisp, Vdisp, maxFaces);
        Fdisp = double(F2);
        Vdisp = double(V2);
        if exist('unifyOutwardNormalsRobust', 'file') == 2 && ...
                ~isempty(Fdisp)
            TRtmp = triangulation(Fdisp, Vdisp);
            TRtmp = unifyOutwardNormalsRobust(TRtmp);
            Fdisp = double(TRtmp.ConnectivityList);
            Vdisp = double(TRtmp.Points);
        end
    catch ME
        warning('acsCropWarpedSkinCacheToPrinterBed:DisplayReduceFailed', ...
            'Display mesh reduction failed; showing the full mesh. %s', ...
            ME.message);
        Fdisp = double(F);
        Vdisp = double(V);
    end
end

function fig = makeQcFigure(TRstableHead, TRskin, TRfiducialHead, ...
        cropPlane, cropInfo, opts, figVisible)
    fig = figure('Name', 'Warped scalp printer-bed crop QC', ...
        'NumberTitle', 'off', 'Color', 'w', 'Visible', figVisible, ...
        'Position', [100 80 1250 700]);
    tl = tiledlayout(fig, 1, 2, 'Padding', 'loose', 'TileSpacing', 'compact');
    ax1 = nexttile(tl);
    hold(ax1, 'on');
    drawTri(ax1, TRstableHead, [0.75 0.77 0.80], 0.35, 'none');
    drawCropPlane(ax1, TRstableHead.Points, cropPlane);
    title(ax1, 'Warped full head + crop plane');
    format3d(ax1);

    ax2 = nexttile(tl);
    hold(ax2, 'on');
    drawTri(ax2, TRfiducialHead, [0.75 0.77 0.80], 0.15, 'none');
    drawTri(ax2, TRskin, [0.15 0.42 0.90], 0.75, 'none');
    title(ax2, sprintf('Cropped print mesh: Z %.2f to %.2f mm', ...
        cropInfo.printBoundsMm(1, 3), cropInfo.printBoundsMm(2, 3)));
    format3d(ax2);
    title(tl, 'Warped scalp cropped to printer bed', ...
        'FontWeight', 'bold', 'Interpreter', 'none');
end

function drawCropPlane(ax, V, cropPlane)
    center = mean(V, 1);
    span = norm(max(V, [], 1) - min(V, [], 1));
    dir = double(cropPlane.cropAxis(:)) ./ norm(cropPlane.cropAxis);
    planeCenter = center(:) + (cropPlane.cropDistance - dot(center(:), dir)) * dir;
    q = cropPlaneQuad(planeCenter, dir, 0.55 * span);
    patch(ax, 'Vertices', q, 'Faces', [1 2 3 4], ...
        'FaceColor', [0.95 0.15 0.10], 'FaceAlpha', 0.18, ...
        'EdgeColor', [0.7 0 0], 'LineWidth', 1.5);
end

function drawTri(ax, TR, color, alphaValue, edgeColor)
    if isempty(TR) || isempty(TR.Points)
        return;
    end
    patch(ax, 'Faces', TR.ConnectivityList, 'Vertices', TR.Points, ...
        'FaceColor', color, 'FaceAlpha', alphaValue, ...
        'EdgeColor', edgeColor, 'FaceLighting', 'flat', ...
        'AmbientStrength', 0.85, 'DiffuseStrength', 0.25, ...
        'SpecularStrength', 0);
end

function format3d(ax)
    axis(ax, 'equal');
    axis(ax, 'vis3d');
    grid(ax, 'on');
    xlabel(ax, 'X mm');
    ylabel(ax, 'Y mm');
    zlabel(ax, 'Z mm');
    view(ax, 3);
    camlight(ax, 'headlight');
    lighting(ax, 'flat');
end

function saveQcFigure(fig, fileName)
    try
        exportgraphics(fig, fileName, 'Resolution', 200);
    catch
        saveas(fig, fileName);
    end
end

function saveCropPlaneIfRequested(fileName, cropPlane)
    ensureDir(fileparts(fileName));
    save(fileName, 'cropPlane');
    writeJsonReport(replaceExtension(fileName, '.json'), cropPlane);
end

function tf = cachedMeshMatchesCropPlane(meta, cropPlane)
    tf = isstruct(meta) && isfield(meta, 'align') && ...
        isfield(meta.align, 'dir') && isfield(meta.align, 'distance') && ...
        isfield(meta.align, 'side') && ...
        max(abs(double(meta.align.dir(:)) - double(cropPlane.cropAxis(:)))) < 1e-8 && ...
        abs(double(meta.align.distance) - double(cropPlane.cropDistance)) < 1e-8 && ...
        strcmpi(char(meta.align.side), char(cropPlane.cropSide));
end

function out = reuseOutput(opts, cropPlane, inputFile)
    out = struct('createdOn', char(datetime('now')), ...
        'type', 'croppedWarpedSkinCache', ...
        'inputFile', inputFile, ...
        'cacheFile', opts.outputFile, ...
        'outputFile', opts.outputFile, ...
        'cropPlaneFile', opts.cropPlaneFile, ...
        'cropPlane', cropPlane, ...
        'reusedExistingCache', true);
end

function pointsStable = printMmToStableWorld(pointsPrint, meta)
    requireCapMakerMeta(meta);
    finalWorldMm = applyAffineToPoints(meta.print.T_print2world, pointsPrint);
    pointsStable = (double(meta.align.R) \ finalWorldMm')';
end

function requireCapMakerMeta(meta)
    ok = isstruct(meta) && isfield(meta, 'print') && ...
        isfield(meta.print, 'T_print2world') && ...
        isfield(meta, 'align') && isfield(meta.align, 'R');
    if ~ok
        error('acsCropWarpedSkinCacheToPrinterBed:BadMeta', ...
            'Skin metadata lacks print.T_print2world or align.R.');
    end
end

function pointsOut = applyAffineToPoints(M, pointsIn)
    pointsHom = [double(pointsIn), ones(size(pointsIn, 1), 1)];
    pointsHom = (double(M) * pointsHom')';
    pointsOut = pointsHom(:, 1:3);
end

function S = loadStructFile(fileName)
    raw = load(expandUserPath(char(fileName)));
    S = firstStruct(raw);
end

function S = firstStruct(raw)
    preferred = {'outForSave', 'phoneObject', 'out', 'cropPlane'};
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
    error('acsCropWarpedSkinCacheToPrinterBed:NoStruct', ...
        'MAT file does not contain a readable struct.');
end

function cropPlane = loadCropPlane(fileName)
    S = load(fileName, 'cropPlane');
    if ~isfield(S, 'cropPlane') || ~isstruct(S.cropPlane)
        error('acsCropWarpedSkinCacheToPrinterBed:BadCropPlaneFile', ...
            'Crop-plane file does not contain cropPlane: %s', fileName);
    end
    cropPlane = S.cropPlane;
end

function TR = ensureTriangulation(value)
    if isa(value, 'triangulation')
        TR = value;
    elseif isstruct(value) && isfield(value, 'ConnectivityList') && ...
            isfield(value, 'Points')
        TR = triangulation(double(value.ConnectivityList), double(value.Points));
    else
        error('acsCropWarpedSkinCacheToPrinterBed:BadTriangulation', ...
            'Expected a triangulation or struct with Points/ConnectivityList.');
    end
end

function [TRout, info] = decimateOutputSkin(TRin, maxFaces)
    info = struct( ...
        'requestedMaxFaces', maxFaces, ...
        'didDecimate', false, ...
        'inputFaces', size(TRin.ConnectivityList, 1), ...
        'inputVertices', size(TRin.Points, 1), ...
        'outputFaces', size(TRin.ConnectivityList, 1), ...
        'outputVertices', size(TRin.Points, 1));
    TRout = TRin;
    if isempty(maxFaces) || ~isfinite(maxFaces) || maxFaces <= 0
        return;
    end
    maxFaces = round(double(maxFaces));
    if size(TRin.ConnectivityList, 1) <= maxFaces
        return;
    end
    try
        [F2, V2] = reducepatch(TRin.ConnectivityList, TRin.Points, maxFaces);
        TRout = triangulation(double(F2), double(V2));
        info.didDecimate = true;
        info.outputFaces = size(TRout.ConnectivityList, 1);
        info.outputVertices = size(TRout.Points, 1);
    catch ME
        warning('acsCropWarpedSkinCacheToPrinterBed:OutputDecimationFailed', ...
            'Could not decimate cropped output skin mesh (%s). Using full mesh.', ...
            ME.message);
    end
end

function [TRout, info] = cleanCroppedSkinComponents(TRin, opts)
    F = double(TRin.ConnectivityList);
    V = double(TRin.Points);
    nFaces = size(F, 1);
    info = struct( ...
        'enabled', opts.keepLargestSkinComponent || opts.minSkinComponentFaces > 0, ...
        'mode', 'none', ...
        'componentCountBefore', 0, ...
        'keptComponentCount', 0, ...
        'removedComponentCount', 0, ...
        'inputFaces', nFaces, ...
        'outputFaces', nFaces, ...
        'inputVertices', size(V, 1), ...
        'outputVertices', size(V, 1), ...
        'componentFaceCounts', [], ...
        'removedFaces', 0);
    TRout = TRin;
    if nFaces == 0 || ~info.enabled
        return;
    end
    if opts.keepLargestSkinComponent
        info.mode = 'largest';
    else
        info.mode = 'minFaces';
    end

    componentId = faceConnectedComponents(F);
    nComp = max(componentId);
    info.componentCountBefore = nComp;
    if nComp <= 1
        info.keptComponentCount = nComp;
        return;
    end
    counts = accumarray(componentId(:), 1, [nComp 1]);
    info.componentFaceCounts = counts(:)';
    if opts.keepLargestSkinComponent
        [~, largestIdx] = max(counts);
        keepComp = largestIdx;
    else
        keepComp = find(counts >= opts.minSkinComponentFaces);
        if isempty(keepComp)
            [~, largestIdx] = max(counts);
            keepComp = largestIdx;
        end
    end
    keepFaces = ismember(componentId, keepComp);
    info.keptComponentCount = numel(keepComp);
    info.removedComponentCount = nComp - info.keptComponentCount;
    info.removedFaces = nnz(~keepFaces);
    if ~any(keepFaces)
        warning('acsCropWarpedSkinCacheToPrinterBed:AllComponentsRemoved', ...
            'Cropped skin component cleanup would remove all faces; using original crop.');
        return;
    end
    [F2, V2] = compactTriangulation(F(keepFaces, :), V);
    TRout = triangulation(F2, V2);
    info.outputFaces = size(F2, 1);
    info.outputVertices = size(V2, 1);
end

function componentId = faceConnectedComponents(F)
    nFaces = size(F, 1);
    edgeRows = [F(:, [1 2]); F(:, [2 3]); F(:, [3 1])];
    faceRows = repmat((1:nFaces)', 3, 1);
    edgeRows = sort(edgeRows, 2);
    [~, order] = sortrows(edgeRows);
    edgeRows = edgeRows(order, :);
    faceRows = faceRows(order);

    parent = 1:nFaces;
    startIdx = 1;
    while startIdx <= size(edgeRows, 1)
        stopIdx = startIdx;
        while stopIdx < size(edgeRows, 1) && ...
                isequal(edgeRows(stopIdx + 1, :), edgeRows(startIdx, :))
            stopIdx = stopIdx + 1;
        end
        faces = unique(faceRows(startIdx:stopIdx));
        if numel(faces) > 1
            root = faces(1);
            for i = 2:numel(faces)
                parent = unionFaces(parent, root, faces(i));
            end
        end
        startIdx = stopIdx + 1;
    end
    for i = 1:nFaces
        parent(i) = findRoot(parent, i);
    end
    [~, ~, componentId] = unique(parent(:));
end

function parent = unionFaces(parent, a, b)
    ra = findRoot(parent, a);
    rb = findRoot(parent, b);
    if ra ~= rb
        parent(rb) = ra;
    end
end

function r = findRoot(parent, i)
    r = i;
    while parent(r) ~= r
        r = parent(r);
    end
end

function [F2, V2] = compactTriangulation(F, V)
    used = unique(F(:));
    map = zeros(size(V, 1), 1);
    map(used) = 1:numel(used);
    F2 = map(F);
    V2 = V(used, :);
end

function value = getOptionalField(S, fieldName, defaultValue)
    if isstruct(S) && isfield(S, fieldName) && ~isempty(S.(fieldName))
        value = S.(fieldName);
    else
        value = defaultValue;
    end
end

function stats = meshStats(TR)
    if isempty(TR) || isempty(TR.Points)
        stats = struct('nVertices', 0, 'nFaces', 0, 'boundsMm', zeros(0, 3));
        return;
    end
    stats = struct('nVertices', size(TR.Points, 1), ...
        'nFaces', size(TR.ConnectivityList, 1), ...
        'boundsMm', [min(TR.Points, [], 1); max(TR.Points, [], 1)]);
end

function value = percentileLocal(x, pct)
    x = sort(double(x(isfinite(x))));
    if isempty(x)
        value = NaN;
        return;
    end
    pos = 1 + (numel(x) - 1) * pct / 100;
    lo = floor(pos);
    hi = ceil(pos);
    if lo == hi
        value = x(lo);
    else
        value = x(lo) + (x(hi) - x(lo)) * (pos - lo);
    end
end

function printSummary(out)
    fprintf('\nWarped scalp printer-bed crop\n');
    fprintf('  input: %s\n', out.inputFile);
    fprintf('  cache: %s\n', out.cacheFile);
    fprintf('  crop plane: %s\n', out.cropPlaneFile);
    fprintf('  print bounds: [%s] to [%s] mm\n', ...
        sprintf('%.2f ', out.cropInfo.printBoundsMm(1, :)), ...
        sprintf('%.2f ', out.cropInfo.printBoundsMm(2, :)));
    if isfield(out.cropInfo, 'outputSkinDecimation') && ...
            isfield(out.cropInfo.outputSkinDecimation, 'didDecimate') && ...
            out.cropInfo.outputSkinDecimation.didDecimate
        d = out.cropInfo.outputSkinDecimation;
        fprintf('  output skin decimation: %d -> %d faces\n', ...
            d.inputFaces, d.outputFaces);
    end
    if isfield(out.cropInfo, 'skinComponentCleanup') && ...
            isstruct(out.cropInfo.skinComponentCleanup) && ...
            out.cropInfo.skinComponentCleanup.enabled
        c = out.cropInfo.skinComponentCleanup;
        fprintf('  cropped skin components: %d -> %d, removed %d faces\n', ...
            c.componentCountBefore, c.keptComponentCount, c.removedFaces);
    end
    if ~isempty(out.qcFigure)
        fprintf('  QC figure: %s\n', out.qcFigure);
    end
end

function writeJsonReport(fileName, value)
    try
        fid = fopen(fileName, 'w');
        cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
        fprintf(fid, '%s', jsonencode(value, 'PrettyPrint', true));
    catch
    end
end

function fileName = replaceExtension(fileName, ext)
    [folder, stem] = fileparts(fileName);
    fileName = fullfile(folder, [stem ext]);
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
    if ~isempty(folder) && exist(folder, 'dir') ~= 7
        mkdir(folder);
    end
end

function value = safeName(value)
    value = regexprep(char(value), '[^\w\-]+', '_');
    value = regexprep(value, '_+', '_');
    value = regexprep(value, '^_|_$', '');
end

function fileName = getFileName(fileName)
    [~, stem, ext] = fileparts(fileName);
    fileName = [stem ext];
end

function stem = stripMatExtension(fileName)
    [~, stem] = fileparts(fileName);
end
