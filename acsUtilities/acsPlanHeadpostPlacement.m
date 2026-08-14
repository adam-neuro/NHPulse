function out = acsPlanHeadpostPlacement(traceIn, surfaceSource, varargin)
% ACSPLANHEADPOSTPLACEMENT Place a titanium headpost CAD mesh on the skull.
%
% out = acsPlanHeadpostPlacement(headpostTraceQc, skinCacheFile, ...)
% resolves a Polhemus headpost trace into the current capMaker print frame,
% loads the simplified headpost STL, aligns the post axis/base to the trace,
% snaps the base to the skull compartment, and optionally opens a refinement
% GUI for yaw and translation. This utility does not modify ROAST labels.
%
% Typical call:
%   out = acsPlanHeadpostPlacement(headpostExclusion, skinCacheForCap, ...
%       'maskFile', segOut.roastReady.maskFile, ...
%       'showFigures', true, 'saveFigures', true);
%
% Coordinate conventions:
%   headpost CAD +X: subject right
%   headpost CAD +Y: rostral
%   headpost CAD +Z: dorsal / post up
%   output mesh frame: capMaker print-frame millimeters
%
% Name-value options:
%   meshFile              : STL headpost mesh [simplified headpost STL]
%   meshOriginMode        : passed to acsInspectHeadpostGeometry ['autoPostBase']
%   meshOriginMm          : manual STL local origin [[]]
%   headpostRefineMaxEdgeMm : shared-edge mesh refinement before bending [2]
%   headpostRefineMaxIterations : max refinement passes [5]
%   objectName            : Polhemus trace name ['headpost']
%   maskFile              : ROAST hard-label mask used for skull surface ['']
%   skullLabel            : ROAST hard-label value for bone [4]
%   skullSurfaceMaxFaces  : decimate skull surface for placement/QC [60000]
%   traceProjectionFile   : optional acsMakeImplantExclusion... cache ['']
%   initialYawDeg         : initial mesh yaw around +Z [0]
%   contactSearchRadiusMm : XY search radius for skull contact [8]
%   alignPostToSkullNormal : align local +Z to skull normal [true]
%   normalSearchRadiusMm : radius for fitting skull normal [[] = contact radius]
%   normalMinPoints      : minimum skull points for normal fit [12]
%   bendStraps            : bend low/base vertices toward skull [true]
%   bendMaxLocalZMm       : local STL Z threshold for bendable vertices [2]
%   bendInnerRadiusMm     : low vertices inside this radius stay rigid [[] = post radius]
%   bendSearchRadiusMm    : XY skull search radius while bending [5]
%   bendThicknessMode     : thickness direction, 'postNormal' or 'skullNormal' ['postNormal']
%   nudgeMm               : GUI translation step [1]
%   yawStepDeg            : GUI yaw step [2]
%   interactive           : open refinement GUI [true]
%   outputFile            : saved placement MAT ['']
%   outputTag             : output stem suffix ['headpostPlacement']
%   force                 : overwrite existing placement [false]
%   reuseExistingPose     : start from saved pose when force=true [true]
%   showFigures           : show QC/refinement figure [true]
%   saveFigures           : save QC figure [false]
%   verbose               : print summary [true]

    if nargin < 1 || isempty(traceIn)
        error('acsPlanHeadpostPlacement:MissingTrace', ...
            'Provide a headpost trace QC, exclusion product, or trace point matrix.');
    end
    if nargin < 2
        surfaceSource = [];
    elseif isNameValueStart(surfaceSource)
        varargin = [{surfaceSource}, varargin];
        surfaceSource = [];
    end

    opts = parseInputs(varargin{:});
    addLocalDependencies();

    if isempty(surfaceSource) && isfieldSafe(traceIn, 'surfaceSource')
        surfaceSource = traceIn.surfaceSource;
    end
    [TRskin, skinMeta, skinSource] = readSkinCache(surfaceSource);
    opts = resolveOutputFile(opts, skinSource);
    previousOut = [];
    if exist(opts.outputFile, 'file') == 2 && ~opts.force
        out = loadPlacementStruct(opts.outputFile);
        if opts.verbose
            fprintf('Headpost placement already exists; reusing %s\n', opts.outputFile);
        end
        return;
    elseif exist(opts.outputFile, 'file') == 2 && opts.force && opts.reuseExistingPose
        previousOut = loadExistingPlacementForInitialPose(opts.outputFile, opts);
    end

    trace = resolveTraceInPrintFrame(traceIn, skinSource, opts);
    headpost = readHeadpostMesh(opts);
    [TRskull, skullInfo] = skullSurfaceInPrintFrame(opts, skinMeta, TRskin);

    pose = initialPoseFromTrace(trace.coordinatesMm, TRskull, opts);
    pose = maybeReuseExistingPose(pose, previousOut);
    placement = makePlacement(headpost, TRskull, pose, opts);

    accepted = true;
    fig = [];
    if opts.interactive && opts.showFigures
        [placement, accepted, fig] = refinePlacementGui( ...
            headpost, TRskull, trace, placement, opts);
        if ~accepted
            error('acsPlanHeadpostPlacement:Canceled', ...
                'Headpost placement was canceled.');
        end
    elseif opts.showFigures || opts.saveFigures
        fig = makeQcFigure(headpost, TRskull, trace, placement, opts, 'on');
    end

    qcFile = '';
    if opts.saveFigures
        if isempty(fig) || ~isgraphics(fig)
            fig = makeQcFigure(headpost, TRskull, trace, placement, opts, 'off');
        end
        qcFile = fullfile(fileparts(opts.outputFile), 'qc', ...
            [stripMatExtension(getFileName(opts.outputFile)) '_qc.png']);
        ensureDir(fileparts(qcFile));
        saveQcFigure(fig, qcFile);
    end

    out = struct();
    out.createdOn = char(datetime('now'));
    out.type = 'headpostPlacement';
    out.outputFile = opts.outputFile;
    out.qcFigure = qcFile;
    out.coordinateFrame = 'capMakerPrintMm';
    out.trace = trace;
    out.surfaceSource = skinSource;
    out.skullSurfaceInfo = publicSkullInfo(skullInfo);
    out.headpost = headpostInfoForOutput(headpost);
    out.placement = placementSummary(placement);
    out.meshes = struct( ...
        'TRplaced', placement.TRplaced, ...
        'TRrigid', placement.TRrigid, ...
        'TRskull', TRskull);
    out.options = opts;
    out.figure = fig;

    outFull = out;
    outForSave = out;
    if isfield(outForSave, 'figure')
        outForSave = rmfield(outForSave, 'figure');
    end
    out = outForSave; %#ok<NASGU>
    ensureDir(fileparts(opts.outputFile));
    save(opts.outputFile, 'out', 'outForSave', '-v7.3');
    out = outFull;

    if opts.verbose
        printSummary(out);
    end
end

function opts = parseInputs(varargin)
    p = inputParser;
    p.FunctionName = 'acsPlanHeadpostPlacement';
    addParameter(p, 'meshFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'meshOriginMode', 'autoPostBase', @(x) ischar(x) || isstring(x));
    addParameter(p, 'meshOriginMm', [], ...
        @(x) isempty(x) || (isnumeric(x) && numel(x) == 3));
    addParameter(p, 'headpostRefineMaxEdgeMm', 2, @(x) isempty(x) || ...
        (isnumeric(x) && isscalar(x) && isfinite(x) && x > 0));
    addParameter(p, 'headpostRefineMaxIterations', 5, @(x) isnumeric(x) && ...
        isscalar(x) && isfinite(x) && x >= 0);
    addParameter(p, 'objectName', 'headpost', @(x) ischar(x) || isstring(x));
    addParameter(p, 'maskFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'skullLabel', 4, @(x) isnumeric(x) && isscalar(x));
    addParameter(p, 'skullSurfaceMaxFaces', 60000, ...
        @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x > 0));
    addParameter(p, 'traceProjectionFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'initialYawDeg', 0, @isFiniteScalar);
    addParameter(p, 'contactSearchRadiusMm', 8, @isPositiveScalar);
    addParameter(p, 'alignPostToSkullNormal', true, @isBoolLike);
    addParameter(p, 'normalSearchRadiusMm', [], ...
        @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x > 0));
    addParameter(p, 'normalMinPoints', 12, ...
        @(x) isnumeric(x) && isscalar(x) && x >= 3);
    addParameter(p, 'bendStraps', true, @isBoolLike);
    addParameter(p, 'bendMaxLocalZMm', 2, @isFiniteScalar);
    addParameter(p, 'bendInnerRadiusMm', [], ...
        @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x >= 0));
    addParameter(p, 'bendSearchRadiusMm', 5, @isPositiveScalar);
    addParameter(p, 'bendThicknessMode', 'postNormal', @(x) ischar(x) || isstring(x));
    addParameter(p, 'nudgeMm', 1, @isPositiveScalar);
    addParameter(p, 'yawStepDeg', 2, @isPositiveScalar);
    addParameter(p, 'interactive', true, @isBoolLike);
    addParameter(p, 'outputFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'outputTag', 'headpostPlacement', @(x) ischar(x) || isstring(x));
    addParameter(p, 'force', false, @isBoolLike);
    addParameter(p, 'reuseExistingPose', true, @isBoolLike);
    addParameter(p, 'showFigures', true, @isBoolLike);
    addParameter(p, 'saveFigures', false, @isBoolLike);
    addParameter(p, 'verbose', true, @isBoolLike);
    parse(p, varargin{:});

    opts = p.Results;
    opts.meshFile = expandUserPath(char(opts.meshFile));
    opts.meshOriginMode = char(opts.meshOriginMode);
    if ~isempty(opts.meshOriginMm)
        opts.meshOriginMm = double(opts.meshOriginMm(:)');
    end
    if ~isempty(opts.headpostRefineMaxEdgeMm)
        opts.headpostRefineMaxEdgeMm = double(opts.headpostRefineMaxEdgeMm);
    end
    opts.headpostRefineMaxIterations = round(double(opts.headpostRefineMaxIterations));
    opts.objectName = char(opts.objectName);
    opts.maskFile = expandUserPath(char(opts.maskFile));
    opts.skullLabel = double(opts.skullLabel);
    if isempty(opts.skullSurfaceMaxFaces)
        opts.skullSurfaceMaxFaces = [];
    else
        opts.skullSurfaceMaxFaces = round(double(opts.skullSurfaceMaxFaces));
    end
    opts.traceProjectionFile = expandUserPath(char(opts.traceProjectionFile));
    opts.initialYawDeg = double(opts.initialYawDeg);
    opts.contactSearchRadiusMm = double(opts.contactSearchRadiusMm);
    opts.alignPostToSkullNormal = logical(opts.alignPostToSkullNormal);
    if isempty(opts.normalSearchRadiusMm)
        opts.normalSearchRadiusMm = opts.contactSearchRadiusMm;
    else
        opts.normalSearchRadiusMm = double(opts.normalSearchRadiusMm);
    end
    opts.normalMinPoints = round(double(opts.normalMinPoints));
    opts.bendStraps = logical(opts.bendStraps);
    opts.bendMaxLocalZMm = double(opts.bendMaxLocalZMm);
    if ~isempty(opts.bendInnerRadiusMm)
        opts.bendInnerRadiusMm = double(opts.bendInnerRadiusMm);
    end
    opts.bendSearchRadiusMm = double(opts.bendSearchRadiusMm);
    opts.bendThicknessMode = validatestring(char(opts.bendThicknessMode), ...
        {'postNormal', 'skullNormal'}, mfilename, 'bendThicknessMode');
    opts.nudgeMm = double(opts.nudgeMm);
    opts.yawStepDeg = double(opts.yawStepDeg);
    opts.interactive = logical(opts.interactive);
    opts.outputFile = expandUserPath(char(opts.outputFile));
    opts.outputTag = safeName(char(opts.outputTag));
    opts.force = logical(opts.force);
    opts.reuseExistingPose = logical(opts.reuseExistingPose);
    opts.showFigures = logical(opts.showFigures);
    opts.saveFigures = logical(opts.saveFigures);
    opts.verbose = logical(opts.verbose);
end

function tf = isNameValueStart(x)
    if ~(ischar(x) || isstring(x)) || numel(string(x)) ~= 1
        tf = false;
        return;
    end
    names = {'meshFile', 'meshOriginMode', 'meshOriginMm', 'objectName', ...
        'headpostRefineMaxEdgeMm', 'headpostRefineMaxIterations', ...
        'maskFile', 'skullLabel', 'skullSurfaceMaxFaces', ...
        'traceProjectionFile', 'initialYawDeg', 'contactSearchRadiusMm', ...
        'alignPostToSkullNormal', 'normalSearchRadiusMm', 'normalMinPoints', ...
        'bendStraps', 'bendMaxLocalZMm', 'bendInnerRadiusMm', ...
        'bendSearchRadiusMm', 'bendThicknessMode', ...
        'nudgeMm', 'yawStepDeg', 'interactive', 'outputFile', ...
        'outputTag', 'force', 'reuseExistingPose', ...
        'showFigures', 'saveFigures', 'verbose'};
    tf = any(strcmpi(char(x), names));
end

function tf = isBoolLike(x)
    tf = (islogical(x) || isnumeric(x)) && isscalar(x);
end

function tf = isFiniteScalar(x)
    tf = isnumeric(x) && isscalar(x) && isfinite(x);
end

function tf = isPositiveScalar(x)
    tf = isFiniteScalar(x) && x > 0;
end

function addLocalDependencies()
    repoRoot = fileparts(fileparts(mfilename('fullpath')));
    addpath(repoRoot);
    addpath(fullfile(repoRoot, 'acsUtilities'));
    addpath(fullfile(repoRoot, 'capMaker', 'core'));
end

function opts = resolveOutputFile(opts, source)
    if ~isempty(opts.outputFile)
        return;
    end
    if isstruct(source) && isfield(source, 'cacheFile') && ~isempty(source.cacheFile)
        [folder, stem] = fileparts(source.cacheFile);
        if endsWith(lower(stem), '_skinmesh')
            stem = stem(1:end - numel('_skinMesh'));
        end
    else
        folder = pwd;
        stem = 'headpost';
    end
    opts.outputFile = fullfile(folder, [stem '_' opts.outputTag '.mat']);
end

function [TRskin, meta, source] = readSkinCache(value)
    if isempty(value)
        error('acsPlanHeadpostPlacement:MissingSkinCache', ...
            'Provide the current capMaker skin cache or a layout that references it.');
    end
    if isstruct(value) && isfield(value, 'surfaceSource')
        value = value.surfaceSource;
    elseif isstruct(value) && isfield(value, 'layout') && ...
            isstruct(value.layout) && isfield(value.layout, 'skin') && ...
            isfield(value.layout.skin, 'cacheFile')
        value = value.layout.skin.cacheFile;
    elseif isstruct(value) && isfield(value, 'skin') && ...
            isstruct(value.skin) && isfield(value.skin, 'cacheFile')
        value = value.skin.cacheFile;
    elseif isstruct(value) && isfield(value, 'cacheFile')
        value = value.cacheFile;
    elseif isstruct(value) && isfield(value, 'file')
        value = value.file;
    end
    if ~(ischar(value) || isstring(value))
        error('acsPlanHeadpostPlacement:BadSkinCache', ...
            'Could not resolve a skin cache filename.');
    end
    fileName = expandUserPath(char(value));
    if exist(fileName, 'file') ~= 2
        error('acsPlanHeadpostPlacement:SkinCacheNotFound', ...
            'Skin cache not found: %s', fileName);
    end
    S = load(fileName, 'TRskin', 'meta');
    if ~isfield(S, 'TRskin') || isempty(S.TRskin)
        error('acsPlanHeadpostPlacement:MissingTRskin', ...
            'Skin cache does not contain TRskin: %s', fileName);
    end
    if ~isfield(S, 'meta') || isempty(S.meta)
        error('acsPlanHeadpostPlacement:MissingSkinMeta', ...
            'Skin cache does not contain capMaker metadata: %s', fileName);
    end
    TRskin = ensureTri(S.TRskin);
    meta = S.meta;
    source = struct('type', 'skinCache', 'file', fileName, ...
        'cacheFile', fileName, 'label', stripMatExtension(getFileName(fileName)), ...
        'coordinateFrame', 'capMakerPrintMm');
end

function trace = resolveTraceInPrintFrame(traceIn, skinSource, opts)
    if isstruct(traceIn) && isfield(traceIn, 'traceCoordinatesMm') && ...
            ~isempty(traceIn.traceCoordinatesMm)
        coords = double(traceIn.traceCoordinatesMm);
        trace = buildTrace(coords, traceIn, 'traceCoordinatesMm from implant exclusion');
        return;
    end
    if isstruct(traceIn) && isfield(traceIn, 'projectedCoordinatesMm') && ...
            ~isempty(traceIn.projectedCoordinatesMm)
        coords = double(traceIn.projectedCoordinatesMm);
        trace = buildTrace(coords, traceIn, 'projectedCoordinatesMm from implant exclusion');
        return;
    end
    if isnumeric(traceIn) && size(traceIn, 2) == 3
        trace = buildTrace(double(traceIn), struct(), 'numeric point matrix');
        return;
    end

    traceProjectionFile = opts.traceProjectionFile;
    if isempty(traceProjectionFile) && ~isempty(opts.outputFile)
        [folder, stem] = fileparts(opts.outputFile);
        traceProjectionFile = fullfile(folder, [stem '_traceProjection.mat']);
    end
    projection = acsMakeImplantExclusionFromPolhemusTrace( ...
        traceIn, skinSource.cacheFile, ...
        'objectName', opts.objectName, ...
        'outputFile', traceProjectionFile, ...
        'outputTag', [opts.outputTag '_traceProjection'], ...
        'force', opts.force, ...
        'showFigures', false, ...
        'saveFigures', false, ...
        'verbose', opts.verbose);
    coords = double(projection.traceCoordinatesMm);
    trace = buildTrace(coords, projection, ...
        'acsMakeImplantExclusionFromPolhemusTrace traceCoordinatesMm');
    trace.projectionProduct = getOptionalField(projection, 'outputFile', traceProjectionFile);
end

function trace = buildTrace(coords, sourceStruct, method)
    coords = double(coords);
    if size(coords, 2) ~= 3 || size(coords, 1) < 3
        error('acsPlanHeadpostPlacement:BadTrace', ...
            'Headpost trace must be an N x 3 matrix with at least 3 points.');
    end
    keep = all(isfinite(coords), 2);
    coords = coords(keep, :);
    if size(coords, 1) < 3
        error('acsPlanHeadpostPlacement:BadTrace', ...
            'Headpost trace has fewer than 3 finite points.');
    end
    trace = struct();
    trace.name = char(getOptionalField(sourceStruct, 'name', 'headpost'));
    trace.coordinatesMm = coords;
    trace.coordinateFrame = 'capMakerPrintMm';
    trace.method = method;
    trace.centerMm = mean(coords, 1);
    trace.centerMedianMm = median(coords, 1);
    trace.boundsMm = struct('min', min(coords, [], 1), ...
        'max', max(coords, [], 1));
end

function headpost = readHeadpostMesh(opts)
    args = {'showFigures', false, 'saveFigures', false, ...
        'originMode', opts.meshOriginMode, 'verbose', false};
    if ~isempty(opts.meshOriginMm)
        args = [args, {'originMm', opts.meshOriginMm}]; %#ok<AGROW>
    end
    if isempty(opts.meshFile)
        meshQc = acsInspectHeadpostGeometry(args{:});
    else
        meshQc = acsInspectHeadpostGeometry(opts.meshFile, args{:});
    end
    TRraw = ensureTri(meshQc.mesh.TR);
    Vlocal = double(TRraw.Points) - double(meshQc.originMm);
    TRlocalRaw = triangulation(TRraw.ConnectivityList, Vlocal);
    [TRlocal, refineInfo] = refineTriByMaxEdge(TRlocalRaw, ...
        opts.headpostRefineMaxEdgeMm, opts.headpostRefineMaxIterations);
    headpost = struct();
    headpost.meshFile = meshQc.meshFile;
    headpost.originMm = meshQc.originMm;
    headpost.originInfo = meshQc.originInfo;
    headpost.coordinateConvention = meshQc.coordinateConvention;
    headpost.TRraw = TRraw;
    headpost.TRlocal = TRlocal;
    headpost.stats = meshQc.stats;
    headpost.stats.originalVertexCount = size(TRlocalRaw.Points, 1);
    headpost.stats.originalFaceCount = size(TRlocalRaw.ConnectivityList, 1);
    headpost.stats.vertexCount = size(TRlocal.Points, 1);
    headpost.stats.faceCount = size(TRlocal.ConnectivityList, 1);
    headpost.refinement = refineInfo;
    if isfield(meshQc.originInfo, 'postRadiusEstimateMm')
        headpost.postRadiusEstimateMm = meshQc.originInfo.postRadiusEstimateMm;
    else
        d = sqrt(sum(Vlocal(:, 1:2) .^ 2, 2));
        headpost.postRadiusEstimateMm = percentileLocal(d, 25);
    end
end

function [TRout, info] = refineTriByMaxEdge(TRin, maxEdgeMm, maxIterations)
    TRout = TRin;
    info = struct('enabled', false, ...
        'maxEdgeMm', maxEdgeMm, ...
        'maxIterations', maxIterations, ...
        'iterations', 0, ...
        'inputVertices', size(TRin.Points, 1), ...
        'inputFaces', size(TRin.ConnectivityList, 1), ...
        'outputVertices', size(TRin.Points, 1), ...
        'outputFaces', size(TRin.ConnectivityList, 1), ...
        'addedVertices', 0, ...
        'reason', '');
    if isempty(maxEdgeMm) || maxIterations < 1
        info.reason = 'disabled';
        return;
    end

    V = double(TRin.Points);
    F = double(TRin.ConnectivityList);
    for iter = 1:maxIterations
        [longEdges, maxEdge] = longMeshEdges(V, F, maxEdgeMm);
        if isempty(longEdges)
            info.reason = 'all edges within threshold';
            break;
        end

        [V, F, addedNow] = splitMeshEdges(V, F, longEdges);
        info.iterations = iter;
        info.addedVertices = info.addedVertices + addedNow;
        info.lastMaxEdgeMm = maxEdge;
        if addedNow == 0
            info.reason = 'no splittable edges';
            break;
        end
    end
    if info.iterations >= maxIterations
        [~, maxEdge] = longMeshEdges(V, F, maxEdgeMm);
        info.finalMaxEdgeMm = maxEdge;
        if maxEdge > maxEdgeMm
            info.reason = 'max iterations reached';
        else
            info.reason = 'all edges within threshold';
        end
    else
        [~, maxEdge] = longMeshEdges(V, F, maxEdgeMm);
        info.finalMaxEdgeMm = maxEdge;
    end

    TRout = triangulation(F, V);
    info.enabled = true;
    info.outputVertices = size(V, 1);
    info.outputFaces = size(F, 1);
end

function [longEdges, maxEdge] = longMeshEdges(V, F, maxEdgeMm)
    edges = [F(:, [1 2]); F(:, [2 3]); F(:, [3 1])];
    edges = sort(edges, 2);
    edges = unique(edges, 'rows');
    edgeVec = V(edges(:, 2), :) - V(edges(:, 1), :);
    edgeLen = rowNorms(edgeVec);
    if isempty(edgeLen)
        maxEdge = NaN;
        longEdges = zeros(0, 2);
        return;
    end
    maxEdge = max(edgeLen);
    longEdges = edges(edgeLen > maxEdgeMm, :);
end

function [Vout, Fout, addedVertices] = splitMeshEdges(V, F, longEdges)
    Vout = V;
    if isempty(longEdges)
        Fout = F;
        addedVertices = 0;
        return;
    end

    edgeMap = containers.Map('KeyType', 'char', 'ValueType', 'double');
    for i = 1:size(longEdges, 1)
        a = longEdges(i, 1);
        b = longEdges(i, 2);
        key = edgeKey(a, b);
        Vout(end + 1, :) = (V(a, :) + V(b, :)) ./ 2; %#ok<AGROW>
        edgeMap(key) = size(Vout, 1);
    end
    addedVertices = size(Vout, 1) - size(V, 1);

    Fcell = cell(size(F, 1), 1);
    for i = 1:size(F, 1)
        a = F(i, 1);
        b = F(i, 2);
        c = F(i, 3);
        m12 = edgeMidpointIfPresent(edgeMap, a, b);
        m23 = edgeMidpointIfPresent(edgeMap, b, c);
        m31 = edgeMidpointIfPresent(edgeMap, c, a);
        Fcell{i} = splitFaceByMidpoints(a, b, c, m12, m23, m31);
    end
    Fout = vertcat(Fcell{:});
end

function F = splitFaceByMidpoints(a, b, c, m12, m23, m31)
    e12 = ~isempty(m12);
    e23 = ~isempty(m23);
    e31 = ~isempty(m31);
    nSplit = e12 + e23 + e31;
    if nSplit == 0
        F = [a b c];
    elseif nSplit == 1
        if e12
            F = [a m12 c; m12 b c];
        elseif e23
            F = [a b m23; a m23 c];
        else
            F = [a b m31; b c m31];
        end
    elseif nSplit == 2
        if e12 && e23
            F = [m12 b m23; m12 m23 c; m12 c a];
        elseif e23 && e31
            F = [m23 c m31; m23 m31 a; m23 a b];
        else
            F = [m31 a m12; m31 m12 b; m31 b c];
        end
    else
        F = [a m12 m31; ...
             m12 b m23; ...
             m31 m23 c; ...
             m12 m23 m31];
    end
end

function idx = edgeMidpointIfPresent(edgeMap, a, b)
    key = edgeKey(a, b);
    if isKey(edgeMap, key)
        idx = edgeMap(key);
    else
        idx = [];
    end
end

function key = edgeKey(a, b)
    if a > b
        tmp = a;
        a = b;
        b = tmp;
    end
    key = sprintf('%d_%d', a, b);
end

function [TRskull, info] = skullSurfaceInPrintFrame(opts, skinMeta, TRskin)
    if isempty(opts.maskFile)
        warning('acsPlanHeadpostPlacement:NoMaskFile', ...
            ['No maskFile was provided. Falling back to cap scalp surface ', ...
             'instead of the skull compartment.']);
        TRskull = TRskin;
        info = struct('source', 'capMaker skin surface fallback', ...
            'maskFile', '', 'skullLabel', NaN, ...
            'nVertices', size(TRskin.Points, 1), ...
            'nFaces', size(TRskin.ConnectivityList, 1));
        return;
    end
    if exist(opts.maskFile, 'file') ~= 2
        error('acsPlanHeadpostPlacement:MaskNotFound', ...
            'ROAST mask file not found: %s', opts.maskFile);
    end
    Vmask = spm_vol(opts.maskFile);
    Vmask = Vmask(1);
    labels = round(spm_read_vols(Vmask));
    bone = labels == opts.skullLabel;
    if nnz(bone) < 10
        error('acsPlanHeadpostPlacement:NoSkullLabel', ...
            'Mask does not contain enough voxels with skullLabel=%d.', opts.skullLabel);
    end
    boneSmooth = smooth3(single(bone), 'box', 3) > 0.20;
    dims = size(boneSmooth);
    [x, y, z] = ndgrid(1:dims(1), 1:dims(2), 1:dims(3));
    fv = isosurface(x, y, z, boneSmooth, 0.5);
    if isempty(fv.vertices) || isempty(fv.faces)
        error('acsPlanHeadpostPlacement:NoSkullSurface', ...
            'Could not extract skull surface from %s.', opts.maskFile);
    end
    verticesWorld = applyAffineToPoints(Vmask.mat, double(fv.vertices));
    [verticesPrint, transformInfo] = t1WorldMmToPrintMm(verticesWorld, Vmask, skinMeta);
    TRskull = triangulation(double(fv.faces), verticesPrint);
    TRskull = decimateTri(TRskull, opts.skullSurfaceMaxFaces);
    info = struct('source', 'ROAST hard-label skull mask transformed to capMaker print frame', ...
        'maskFile', opts.maskFile, ...
        'skullLabel', opts.skullLabel, ...
        'printFrameMethod', transformInfo.method, ...
        'printFrameTransform', transformInfo, ...
        'nBoneVoxels', nnz(bone), ...
        'nVertices', size(TRskull.Points, 1), ...
        'nFaces', size(TRskull.ConnectivityList, 1));
end

function pose = initialPoseFromTrace(tracePoints, TRskull, opts)
    traceCenter = median(tracePoints, 1);
    contact = skullContactAtXY(TRskull.Points, traceCenter(1:2), ...
        opts.contactSearchRadiusMm);
    pose = struct();
    pose.centerXYMm = traceCenter(1:2);
    pose.zOffsetMm = 0;
    pose.contactMm = contact;
    pose.yawDeg = opts.initialYawDeg;
    pose.traceCenterMm = traceCenter;
    pose.method = 'trace median XY with skull contact Z';
end

function previousOut = loadExistingPlacementForInitialPose(fileName, opts)
    previousOut = [];
    try
        previousOut = loadPlacementStruct(fileName);
        if opts.verbose
            fprintf('Using existing headpost placement as refinement starting pose: %s\n', ...
                fileName);
        end
    catch ME
        if opts.verbose
            warning('acsPlanHeadpostPlacement:CannotReuseExistingPose', ...
                'Could not load existing headpost placement as initial pose: %s', ...
                ME.message);
        end
    end
end

function pose = maybeReuseExistingPose(pose, previousOut)
    if isempty(previousOut) || ~isstruct(previousOut) || ...
            ~isfield(previousOut, 'placement') || ...
            ~isfield(previousOut.placement, 'pose')
        return;
    end

    oldPose = previousOut.placement.pose;
    if isfield(oldPose, 'centerXYMm') && numel(oldPose.centerXYMm) == 2 && ...
            all(isfinite(double(oldPose.centerXYMm(:))))
        pose.centerXYMm = double(oldPose.centerXYMm(:)');
    elseif isfield(oldPose, 'contactMm') && numel(oldPose.contactMm) >= 2 && ...
            all(isfinite(double(oldPose.contactMm(1:2))))
        pose.centerXYMm = double(oldPose.contactMm(1:2));
    else
        return;
    end

    if isfield(oldPose, 'yawDeg') && isfinite(double(oldPose.yawDeg))
        pose.yawDeg = double(oldPose.yawDeg);
    end
    if isfield(oldPose, 'zOffsetMm') && isfinite(double(oldPose.zOffsetMm))
        pose.zOffsetMm = double(oldPose.zOffsetMm);
    end
    pose.method = 'existing placement pose reused as refinement initial state';
end

function placement = makePlacement(headpost, TRskull, pose, opts)
    contact = skullContactAtXY(TRskull.Points, pose.centerXYMm, ...
        opts.contactSearchRadiusMm);
    contact(3) = contact(3) + pose.zOffsetMm;
    pose.contactMm = contact;
    [normalVector, normalInfo] = skullNormalAtContact(TRskull, ...
        contact, pose.centerXYMm, opts);
    if ~opts.alignPostToSkullNormal
        normalVector = [0 0 1];
        normalInfo.method = 'imageZ';
        normalInfo.reason = 'alignPostToSkullNormal=false';
    end
    pose.normalVector = normalVector;
    pose.normalInfo = normalInfo;
    R = headpostRotation(normalVector, pose.yawDeg);
    Vlocal = double(headpost.TRlocal.Points);
    Vrigid = Vlocal * R' + contact;
    bendInfo = struct('enabled', false, 'nBentVertices', 0);
    Vplaced = Vrigid;
    if opts.bendStraps
        [Vplaced, bendInfo] = bendLowVerticesToSkull( ...
            Vrigid, Vlocal, TRskull.Points, headpost, ...
            pose.normalVector, opts);
    end
    placement = struct();
    placement.pose = pose;
    placement.rotationMatrix = R;
    placement.TRrigid = triangulation(headpost.TRlocal.ConnectivityList, Vrigid);
    placement.TRplaced = triangulation(headpost.TRlocal.ConnectivityList, Vplaced);
    placement.bendInfo = bendInfo;
    placement.traceFit = traceFitSummary(Vplaced, headpost, pose);
end

function [normalVector, info] = skullNormalAtContact(TRskull, contact, xy, opts)
    V = double(TRskull.Points);
    F = double(TRskull.ConnectivityList);
    if size(F, 1) < 1 || size(V, 1) < 3
        [normalVector, info] = skullNormalAtXY(V, xy, opts);
        info.method = ['fallbackPointPcaAfterFaceNormal: ' info.method];
        return;
    end

    centroids = (V(F(:, 1), :) + V(F(:, 2), :) + V(F(:, 3), :)) ./ 3;
    d3 = sqrt(sum((centroids - contact(:)') .^ 2, 2));
    rows = find(d3 <= opts.normalSearchRadiusMm);
    method = 'localFaceNormals3d';
    if numel(rows) < opts.normalMinPoints
        dxy = sqrt(sum((centroids(:, 1:2) - xy(:)') .^ 2, 2));
        rows = find(dxy <= opts.normalSearchRadiusMm);
        method = 'localFaceNormalsXy';
    end
    if numel(rows) < opts.normalMinPoints
        [~, order] = sort(d3, 'ascend');
        rows = order(1:min(numel(order), opts.normalMinPoints));
        method = 'nearestFaceNormals';
    end

    normals = triangleNormals(V, F(rows, :));
    keep = all(isfinite(normals), 2) & rowNorms(normals) > eps;
    rows = rows(keep);
    normals = normals(keep, :);
    info = struct('method', method, ...
        'searchRadiusMm', opts.normalSearchRadiusMm, ...
        'minPoints', opts.normalMinPoints, ...
        'usedFaces', numel(rows), ...
        'reason', '');
    if isempty(rows)
        [normalVector, info] = skullNormalAtXY(V, xy, opts);
        info.method = ['fallbackPointPcaAfterDegenerateFaces: ' info.method];
        return;
    end

    finiteV = V(all(isfinite(V), 2), :);
    if isempty(finiteV)
        skullCenter = [0 0 0];
    else
        skullCenter = mean(finiteV, 1);
    end
    faceOutward = centroids(rows, :) - skullCenter;
    flipRows = sum(normals .* faceOutward, 2) < 0;
    normals(flipRows, :) = -normals(flipRows, :);

    weights = 1 ./ max(d3(rows), 0.5) .^ 2;
    weights(~isfinite(weights)) = 0;
    if sum(weights) <= 0
        weights = ones(size(weights));
    end
    normalVector = sum(normals .* weights(:), 1) ./ sum(weights);
    normalVector = normalizeRow(normalVector);

    outward = contact(:)' - skullCenter;
    if norm(outward) > eps && dot(normalVector, outward) < 0
        normalVector = -normalVector;
    end
    if ~all(isfinite(normalVector)) || norm(normalVector) < eps
        [normalVector, pcaInfo] = skullNormalAtXY(V, xy, opts);
        info.method = ['fallbackPointPcaAfterCancelingFaces: ' pcaInfo.method];
        info.reason = pcaInfo.reason;
    end
    info.angleFromImageZDeg = acosd(max(-1, min(1, dot(normalVector, [0 0 1]))));
end

function normals = triangleNormals(V, F)
    e1 = V(F(:, 2), :) - V(F(:, 1), :);
    e2 = V(F(:, 3), :) - V(F(:, 1), :);
    normals = cross(e1, e2, 2);
    n = rowNorms(normals);
    keep = n > eps & isfinite(n);
    normals(keep, :) = normals(keep, :) ./ n(keep);
    normals(~keep, :) = NaN;
end

function [normalVector, info] = skullNormalAtXY(skullPoints, xy, opts)
    V = double(skullPoints);
    dxy = sqrt(sum((V(:, 1:2) - xy(:)') .^ 2, 2));
    rows = find(dxy <= opts.normalSearchRadiusMm);
    if numel(rows) < opts.normalMinPoints
        [~, order] = sort(dxy, 'ascend');
        rows = order(1:min(numel(order), opts.normalMinPoints));
    end
    P = V(rows, :);
    P = P(all(isfinite(P), 2), :);
    info = struct('method', 'localPlanePca', ...
        'searchRadiusMm', opts.normalSearchRadiusMm, ...
        'minPoints', opts.normalMinPoints, ...
        'usedPoints', size(P, 1), ...
        'reason', '');
    if size(P, 1) < 3
        normalVector = [0 0 1];
        info.method = 'fallbackImageZ';
        info.reason = 'Too few finite skull points for normal fit.';
        return;
    end
    center = mean(P, 1);
    C = bsxfun(@minus, P, center);
    try
        [~, ~, Vsvd] = svd(C, 0);
        normalVector = Vsvd(:, end)';
    catch
        normalVector = [0 0 1];
        info.method = 'fallbackImageZ';
        info.reason = 'SVD failed.';
        return;
    end
    outward = center - mean(V, 1);
    if dot(normalVector, outward) < 0
        normalVector = -normalVector;
    end
    normalVector = normalizeRow(normalVector);
    if ~all(isfinite(normalVector)) || norm(normalVector) < eps
        normalVector = [0 0 1];
        info.method = 'fallbackImageZ';
        info.reason = 'Degenerate fitted normal.';
    end
    info.angleFromImageZDeg = acosd(max(-1, min(1, dot(normalVector, [0 0 1]))));
end

function [Vout, info] = bendLowVerticesToSkull( ...
        Vrigid, Vlocal, skullPoints, headpost, normalVector, opts)
    Vout = Vrigid;
    bendInnerRadiusMm = opts.bendInnerRadiusMm;
    if isempty(bendInnerRadiusMm)
        bendInnerRadiusMm = headpost.postRadiusEstimateMm;
    end
    localDxy = sqrt(sum(Vlocal(:, 1:2) .^ 2, 2));
    lowMask = Vlocal(:, 3) <= opts.bendMaxLocalZMm & ...
        localDxy >= bendInnerRadiusMm;
    if nnz(lowMask) < 3
        info = struct('enabled', true, 'nBentVertices', 0, ...
            'reason', 'Too few vertices below bendMaxLocalZMm.');
        return;
    end
    localBaseZ = percentileLocal(Vlocal(lowMask, 3), 2);
    rows = find(lowMask);
    normalVector = normalizeRow(normalVector);
    localHeightAboveBase = Vlocal(rows, 3) - localBaseZ;
    clampedHeight = localHeightAboveBase < 0;
    localHeightAboveBase(clampedHeight) = 0;

    % Preserve strap thickness: query skull contact at the local bottom
    % footprint, then add the vertex's original local height. The default
    % uses the stable post normal for thickness; per-vertex skull normals are
    % available for experiments but can self-intersect on noisy skull meshes.
    bottomFootprint = Vrigid(rows, :) - ...
        bsxfun(@times, localHeightAboveBase(:), normalVector);
    skullZ = nan(numel(rows), 1);
    thicknessNormals = repmat(normalVector, numel(rows), 1);
    normalMethods = cell(numel(rows), 1);
    for i = 1:numel(rows)
        pxy = bottomFootprint(i, 1:2);
        contact = skullContactAtXY(skullPoints, pxy, opts.bendSearchRadiusMm);
        skullZ(i) = contact(3);
        if strcmpi(opts.bendThicknessMode, 'skullNormal')
            [thicknessNormals(i, :), normalInfo] = skullNormalAtXY(skullPoints, pxy, opts);
            if dot(thicknessNormals(i, :), normalVector) < 0
                thicknessNormals(i, :) = -thicknessNormals(i, :);
            end
            normalMethods{i} = normalInfo.method;
        else
            normalMethods{i} = 'postNormal';
        end
    end
    keep = isfinite(skullZ);
    rows = rows(keep);
    skullZ = skullZ(keep);
    bottomFootprint = bottomFootprint(keep, :);
    localHeightAboveBase = localHeightAboveBase(keep);
    clampedHeight = clampedHeight(keep);
    thicknessNormals = thicknessNormals(keep, :);
    normalMethods = normalMethods(keep);
    if isempty(rows)
        info = struct('enabled', true, 'nBentVertices', 0, ...
            'reason', 'No skull contacts found for low vertices.');
        return;
    end
    invalidNormals = ~all(isfinite(thicknessNormals), 2) | rowNorms(thicknessNormals) <= eps;
    thicknessNormals(invalidNormals, :) = repmat(normalVector, nnz(invalidNormals), 1);
    thicknessNormals = normalizeRows(thicknessNormals);
    basePoints = [bottomFootprint(:, 1:2), skullZ(:)];
    Vout(rows, :) = basePoints + bsxfun(@times, thicknessNormals, localHeightAboveBase(:));
    displacement = Vout(rows, 3) - Vrigid(rows, 3);
    preservedHeightError = dot( ...
        Vout(rows, :) - basePoints, thicknessNormals, 2) - ...
        localHeightAboveBase(:);
    info = struct('enabled', true, ...
        'method', ['bottom-footprint skull contact with preserved ' ...
        opts.bendThicknessMode ' height'], ...
        'nBentVertices', numel(rows), ...
        'bendMaxLocalZMm', opts.bendMaxLocalZMm, ...
        'bendInnerRadiusMm', bendInnerRadiusMm, ...
        'localBaseZMm', localBaseZ, ...
        'bendThicknessMode', opts.bendThicknessMode, ...
        'nHeightClampedVertices', nnz(clampedHeight), ...
        'nNormalFallbackVertices', nnz(invalidNormals), ...
        'normalMethodSummary', summarizeCellstr(normalMethods), ...
        'preservedHeightErrorMaxMm', max(abs(preservedHeightError)), ...
        'displacementMedianMm', median(displacement), ...
        'displacementMinMm', min(displacement), ...
        'displacementMaxMm', max(displacement));
end

function summary = traceFitSummary(Vplaced, headpost, pose)
    dxy = sqrt(sum((Vplaced(:, 1:2) - pose.traceCenterMm(1:2)) .^ 2, 2));
    summary = struct();
    summary.traceCenterMm = pose.traceCenterMm;
    summary.placedOriginMm = pose.contactMm;
    summary.postRadiusEstimateMm = headpost.postRadiusEstimateMm;
    summary.meshMinDistanceToTraceCenterXYMm = min(dxy);
end

function contact = skullContactAtXY(skullPoints, xy, searchRadius)
    V = double(skullPoints);
    dxy = sqrt(sum((V(:, 1:2) - xy(:)') .^ 2, 2));
    rows = find(dxy <= searchRadius);
    if isempty(rows)
        [~, row] = min(dxy);
        contact = V(row, :);
        contact(1:2) = xy;
        return;
    end
    [~, local] = max(V(rows, 3));
    row = rows(local);
    contact = V(row, :);
    contact(1:2) = xy;
end

function [placement, accepted, fig] = refinePlacementGui( ...
        headpost, TRskull, trace, placement, opts)
    accepted = false;
    state.pose = placement.pose;
    state.placement = placement;
    closeExistingPlacementGuiFigures();
    fig = figure('Name', 'Headpost placement refinement', ...
        'NumberTitle', 'off', 'Color', 'w', ...
        'Tag', 'acsPlanHeadpostPlacementRefinementFigure', ...
        'Position', [70 60 1450 860], ...
        'WindowKeyPressFcn', @onKey, ...
        'CloseRequestFcn', @onCancel);
    addPlacementMenus(fig);
    if opts.verbose
        fprintf(['Headpost placement GUI is waiting for Done. MATLAB may ', ...
            'show the command window as busy while the figure remains interactive.\n']);
    end
    redraw();
    uiwait(fig);
    if isgraphics(fig)
        placement = state.placement;
        if accepted
            set(fig, 'CloseRequestFcn', 'closereq');
        end
    end

    function onKey(~, event)
        mult = 1;
        if any(strcmpi(event.Modifier, 'shift'))
            mult = 5;
        end
        step = opts.nudgeMm * mult;
        yawStep = opts.yawStepDeg * mult;
        switch lower(event.Key)
            case 'leftarrow'
                state.pose.centerXYMm = state.pose.centerXYMm + [-step 0];
            case 'rightarrow'
                state.pose.centerXYMm = state.pose.centerXYMm + [step 0];
            case 'uparrow'
                state.pose.centerXYMm = state.pose.centerXYMm + [0 step];
            case 'downarrow'
                state.pose.centerXYMm = state.pose.centerXYMm + [0 -step];
            case 'u'
                state.pose.zOffsetMm = state.pose.zOffsetMm + step;
            case 'd'
                state.pose.zOffsetMm = state.pose.zOffsetMm - step;
            case {'comma', 'leftbracket'}
                state.pose.yawDeg = state.pose.yawDeg - yawStep;
            case {'period', 'rightbracket'}
                state.pose.yawDeg = state.pose.yawDeg + yawStep;
            case 'r'
                state.pose.zOffsetMm = 0;
            case {'return', 'enter'}
                onDone();
                return;
            case 'escape'
                onCancel();
                return;
            otherwise
                return;
        end
        state.placement = makePlacement(headpost, TRskull, state.pose, opts);
        redraw();
    end

    function redraw()
        cameraState = capturePlacementCamera(fig);
        drawPlacementFigure(fig, headpost, TRskull, trace, ...
            state.placement, opts, cameraState);
        addPlacementMenus(fig);
        uicontrol(fig, 'Style', 'pushbutton', 'String', 'Done', ...
            'Units', 'normalized', 'Position', [0.80 0.02 0.08 0.045], ...
            'Callback', @(~, ~) onDone());
        uicontrol(fig, 'Style', 'pushbutton', 'String', 'Cancel', ...
            'Units', 'normalized', 'Position', [0.89 0.02 0.08 0.045], ...
            'Callback', @(~, ~) onCancel());
        annotation(fig, 'textbox', [0.04 0.005 0.72 0.06], ...
            'String', ['Arrows: nudge X/Y. U/D: nudge Z offset. ', ...
            ',/. or [/] : yaw around skull normal. Shift = 5x. ', ...
            'R: reset Z offset. Enter = done.'], ...
            'EdgeColor', 'none', 'Interpreter', 'none', 'FontSize', 9);
        compactFigureText(fig);
        set(fig, 'WindowKeyPressFcn', @onKey);
        drawnow;
    end

    function addPlacementMenus(figHandle)
        oldMenus = findall(figHandle, 'Type', 'uimenu', ...
            'Tag', 'acsPlanHeadpostPlacementFileMenu');
        delete(oldMenus);
        menuFile = uimenu(figHandle, 'Text', 'File');
        set(menuFile, 'Tag', 'acsPlanHeadpostPlacementFileMenu');
        uimenu(menuFile, 'Text', 'Close', ...
            'MenuSelectedFcn', @(~, ~) close(figHandle));
    end

    function onDone(~, ~)
        accepted = true;
        if isgraphics(fig)
            uiresume(fig);
        end
    end

    function onCancel(~, ~)
        accepted = false;
        if isgraphics(fig)
            uiresume(fig);
            delete(fig);
        end
    end
end

function closeExistingPlacementGuiFigures()
    oldByTag = findall(0, 'Type', 'figure', ...
        'Tag', 'acsPlanHeadpostPlacementRefinementFigure');
    oldByName = findall(0, 'Type', 'figure', ...
        'Name', 'Headpost placement refinement');
    oldFigs = [oldByTag(:); oldByName(:)];
    for i = 1:numel(oldFigs)
        if isgraphics(oldFigs(i))
            try
                set(oldFigs(i), 'CloseRequestFcn', 'closereq');
                delete(oldFigs(i));
            catch
            end
        end
    end
end

function fig = makeQcFigure(headpost, TRskull, trace, placement, opts, visible)
    fig = figure('Name', 'Headpost placement QC', ...
        'NumberTitle', 'off', 'Color', 'w', 'Visible', visible, ...
        'Position', [70 60 1450 860]);
    drawPlacementFigure(fig, headpost, TRskull, trace, placement, opts, []);
end

function drawPlacementFigure(fig, headpost, TRskull, trace, placement, opts, cameraState)
    if nargin < 7
        cameraState = [];
    end
    clf(fig);
    ax = axes(fig, 'Position', [0.075 0.24 0.50 0.54], ...
        'Tag', 'headpostPlacementMainAxes'); %#ok<LAXES>
    hold(ax, 'on');
    skullPlot = decimateTri(TRskull, 25000);
    patch(ax, 'Faces', skullPlot.ConnectivityList, 'Vertices', skullPlot.Points, ...
        'FaceColor', [0.78 0.78 0.72], ...
        'FaceAlpha', 0.26, 'EdgeColor', 'none');
    patch(ax, 'Faces', placement.TRplaced.ConnectivityList, ...
        'Vertices', placement.TRplaced.Points, ...
        'FaceColor', [0.42 0.45 0.50], ...
        'FaceAlpha', 0.78, 'EdgeColor', 'none');
    if opts.bendStraps
        patch(ax, 'Faces', placement.TRrigid.ConnectivityList, ...
            'Vertices', placement.TRrigid.Points, ...
            'FaceColor', [0.70 0.70 0.70], ...
            'FaceAlpha', 0.12, 'EdgeColor', 'none', ...
            'HandleVisibility', 'off');
    end
    scatter3(ax, trace.coordinatesMm(:, 1), trace.coordinatesMm(:, 2), ...
        trace.coordinatesMm(:, 3), 36, [0.95 0.15 0.05], ...
        'filled', 'MarkerEdgeColor', 'k');
    drawPoseAxes(ax, placement.pose.contactMm, placement.rotationMatrix, ...
        0.30 * max(headpost.stats.rangeMm));
    axis(ax, 'equal');
    axis(ax, 'vis3d');
    grid(ax, 'on');
    xlabel(ax, 'X (mm)');
    ylabel(ax, 'Y (mm)');
    zlabel(ax, 'Z (mm)');
    view(ax, 3);
    camproj(ax, 'orthographic');
    camlight(ax, 'headlight');
    lighting(ax, 'gouraud');
    normalAngle = getOptionalField(placement.pose.normalInfo, ...
        'angleFromImageZDeg', NaN);
    title(ax, sprintf('Placement: yaw %.1f deg, dz %.1f mm, tilt %.1f deg', ...
        placement.pose.yawDeg, ...
        placement.pose.zOffsetMm, normalAngle), ...
        'Interpreter', 'none');
    legend(ax, {'skull surface', 'placed headpost', 'Polhemus trace'}, ...
        'Location', 'northwest', 'Box', 'off', 'FontSize', 8);
    restorePlacementCamera(ax, cameraState);

    ax2 = axes(fig, 'Position', [0.68 0.55 0.27 0.30]); %#ok<LAXES>
    drawTopProjection(ax2, TRskull, trace, placement);
    ax3 = axes(fig, 'Position', [0.67 0.12 0.29 0.32]); %#ok<LAXES>
    drawSummaryPanel(ax3, placement, headpost);
    compactFigureText(fig);
end

function drawTopProjection(ax, TRskull, trace, placement)
    hold(ax, 'on');
    V = double(TRskull.Points);
    if size(V, 1) > 10000
        rows = round(linspace(1, size(V, 1), 10000));
        V = V(rows, :);
    end
    scatter(ax, V(:, 1), V(:, 2), 2, [0.75 0.75 0.75], 'filled');
    P = double(placement.TRplaced.Points);
    try
        K = boundary(P(:, 1), P(:, 2), 0.8);
    catch
        K = convhull(P(:, 1), P(:, 2));
    end
    if numel(K) >= 3
        plot(ax, P(K, 1), P(K, 2), 'k-', 'LineWidth', 1.5);
    end
    scatter(ax, trace.coordinatesMm(:, 1), trace.coordinatesMm(:, 2), ...
        18, [0.95 0.15 0.05], 'filled');
    scatter(ax, placement.pose.contactMm(1), placement.pose.contactMm(2), ...
        55, [0.05 0.25 0.95], 'filled');
    axis(ax, 'equal');
    grid(ax, 'on');
    title(ax, 'Top projection', 'Interpreter', 'none');
    xlabel(ax, 'X');
    ylabel(ax, 'Y');
end

function drawSummaryPanel(ax, placement, headpost)
    axis(ax, 'off');
    b = placement.bendInfo;
    lines = { ...
        'Placement', ...
        sprintf('contact: [% .2f % .2f % .2f]', placement.pose.contactMm), ...
        sprintf('yaw: %.2f deg', placement.pose.yawDeg), ...
        sprintf('z offset: %.2f mm', placement.pose.zOffsetMm), ...
        sprintf('normal: [% .3f % .3f % .3f]', placement.pose.normalVector), ...
        sprintf('normal tilt: %.2f deg', getOptionalField( ...
        placement.pose.normalInfo, 'angleFromImageZDeg', NaN)), ...
        sprintf('normal method: %s', getOptionalField( ...
        placement.pose.normalInfo, 'method', 'unknown')), ...
        '', ...
        'Mesh', ...
        sprintf('faces: %d', headpost.stats.faceCount), ...
        sprintf('post radius est: %.2f mm', headpost.postRadiusEstimateMm), ...
        '', ...
        'Bending', ...
        sprintf('enabled: %d', logical(b.enabled)), ...
        sprintf('vertices: %d', getOptionalField(b, 'nBentVertices', 0))};
    if isfield(b, 'displacementMedianMm')
        lines{end + 1} = sprintf('median dz: %.2f mm', b.displacementMedianMm); %#ok<AGROW>
        lines{end + 1} = sprintf('range dz: %.2f..%.2f', ...
            b.displacementMinMm, b.displacementMaxMm); %#ok<AGROW>
    end
    text(ax, 0.0, 1.0, strjoin(lines, newline), ...
        'Units', 'normalized', 'VerticalAlignment', 'top', ...
        'Interpreter', 'none', 'FontName', 'Consolas');
end

function compactFigureText(fig)
    objs = findall(fig, '-property', 'FontSize');
    for i = 1:numel(objs)
        try
            objs(i).FontSize = min(objs(i).FontSize, 9);
        catch
        end
    end
end

function cameraState = capturePlacementCamera(fig)
    cameraState = [];
    if isempty(fig) || ~isgraphics(fig)
        return;
    end
    ax = findobj(fig, 'Type', 'axes', 'Tag', 'headpostPlacementMainAxes');
    if isempty(ax) || ~isgraphics(ax(1))
        return;
    end
    ax = ax(1);
    cameraState = struct( ...
        'CameraPosition', get(ax, 'CameraPosition'), ...
        'CameraTarget', get(ax, 'CameraTarget'), ...
        'CameraUpVector', get(ax, 'CameraUpVector'), ...
        'CameraViewAngle', get(ax, 'CameraViewAngle'), ...
        'XLim', get(ax, 'XLim'), ...
        'YLim', get(ax, 'YLim'), ...
        'ZLim', get(ax, 'ZLim'));
end

function restorePlacementCamera(ax, cameraState)
    if isempty(cameraState) || ~isstruct(cameraState)
        return;
    end
    props = {'CameraPosition', 'CameraTarget', 'CameraUpVector', ...
        'CameraViewAngle', 'XLim', 'YLim', 'ZLim'};
    for i = 1:numel(props)
        if isfield(cameraState, props{i}) && ...
                all(isfinite(double(cameraState.(props{i})(:))))
            set(ax, props{i}, cameraState.(props{i}));
        end
    end
end

function drawPoseAxes(ax, origin, R, len)
    colors = [0.85 0.05 0.05; 0.05 0.55 0.15; 0.05 0.20 0.85];
    labels = {'+X local right', '+Y local rostral', '+Z post axis'};
    dirs = eye(3) * R';
    for i = 1:3
        tip = origin + len * dirs(i, :);
        quiver3(ax, origin(1), origin(2), origin(3), ...
            len * dirs(i, 1), len * dirs(i, 2), len * dirs(i, 3), ...
            0, 'LineWidth', 2.5, 'Color', colors(i, :), ...
            'MaxHeadSize', 0.45, 'HandleVisibility', 'off');
        text(ax, tip(1), tip(2), tip(3), [' ' labels{i}], ...
            'Color', colors(i, :), 'FontWeight', 'bold', ...
            'Interpreter', 'none', 'HandleVisibility', 'off');
    end
end

function R = headpostRotation(normalVector, yawDeg)
    normalVector = normalizeRow(normalVector);
    Ralign = alignVectorRotation([0 0 1], normalVector);
    Ryaw = axisAngleRotation(normalVector, yawDeg);
    R = Ryaw * Ralign;
end

function R = alignVectorRotation(sourceVector, targetVector)
    a = normalizeRow(sourceVector);
    b = normalizeRow(targetVector);
    v = cross(a, b);
    s = norm(v);
    c = dot(a, b);
    if s < 1e-12
        if c > 0
            R = eye(3);
        else
            R = axisAngleRotation([1 0 0], 180);
        end
        return;
    end
    vx = [0 -v(3) v(2); v(3) 0 -v(1); -v(2) v(1) 0];
    R = eye(3) + vx + vx * vx * ((1 - c) / (s ^ 2));
end

function R = axisAngleRotation(axisVector, angleDeg)
    u = normalizeRow(axisVector);
    c = cosd(angleDeg);
    s = sind(angleDeg);
    C = 1 - c;
    x = u(1);
    y = u(2);
    z = u(3);
    R = [ ...
        c + x*x*C, x*y*C - z*s, x*z*C + y*s; ...
        y*x*C + z*s, c + y*y*C, y*z*C - x*s; ...
        z*x*C - y*s, z*y*C + x*s, c + z*z*C];
end

function row = normalizeRow(row)
    row = double(row(:)');
    n = norm(row);
    if n < eps || any(~isfinite(row))
        row = [0 0 1];
    else
        row = row ./ n;
    end
end

function rows = normalizeRows(rows)
    rows = double(rows);
    n = rowNorms(rows);
    keep = n > eps & isfinite(n) & all(isfinite(rows), 2);
    rows(keep, :) = bsxfun(@rdivide, rows(keep, :), n(keep));
    rows(~keep, :) = repmat([0 0 1], nnz(~keep), 1);
end

function n = rowNorms(M)
    n = sqrt(sum(double(M) .^ 2, 2));
end

function summary = summarizeCellstr(values)
    values = values(:);
    if isempty(values)
        summary = struct('names', {cell(0, 1)}, 'counts', zeros(0, 1));
        return;
    end
    emptyRows = cellfun(@isempty, values);
    values(emptyRows) = {'unknown'};
    [names, ~, idx] = unique(values);
    counts = accumarray(idx, 1);
    summary = struct('names', {names}, 'counts', counts);
end

function TRout = decimateTri(TRin, maxFaces)
    TRout = TRin;
    if isempty(maxFaces) || size(TRin.ConnectivityList, 1) <= maxFaces
        return;
    end
    try
        [F2, V2] = reducepatch(TRin.ConnectivityList, TRin.Points, maxFaces);
        TRout = triangulation(F2, V2);
    catch
        TRout = TRin;
    end
end

function [printMm, info] = t1WorldMmToPrintMm(t1WorldMm, Vref, meta)
    requireSkinMetaTransforms(meta);
    orientation = capMakerVoxelOrientationFromMeta(meta);
    t1VoxelSize = voxelSizesFromMat(Vref.mat);
    rasVoxel1 = worldMmToVoxel1(t1WorldMm, Vref.mat);
    capVoxel0 = rasVoxel1ToCapMakerVoxel0(rasVoxel1, ...
        orientation.capMakerVoxelOrientation, orientation.size, ...
        orientation.voxelSize, t1VoxelSize);
    capWorldMm = applyAffineToPoints(meta.original.vox2world, capVoxel0);
    alignedWorldMm = (double(meta.align.R) * capWorldMm')';
    printMm = applyAffineToPoints(meta.print.T_world2print, alignedWorldMm);

    info = orientation;
    info.method = 't1WorldToCapMakerPrint_v2';
    info.t1VoxelSize = t1VoxelSize;
    info.t1WorldReference = Vref.fname;
end

function capVoxel0 = rasVoxel1ToCapMakerVoxel0( ...
        rasVoxel1, orientationCode, dims, srcVoxelSize, dstVoxelSize)
    orientationCode = validateOrientationCode(orientationCode);
    dims = double(dims(:)');
    srcVoxelSize = double(srcVoxelSize(:)');
    dstVoxelSize = double(dstVoxelSize(:)');
    rasMm = bsxfun(@times, double(rasVoxel1) - 1, dstVoxelSize);

    targets = 'ras';
    opposites = 'lpi';
    capVoxel0 = zeros(size(rasVoxel1, 1), 3);
    for rasDim = 1:3
        srcDim = find(orientationCode == targets(rasDim) | ...
            orientationCode == opposites(rasDim), 1);
        coord0 = rasMm(:, rasDim) ./ srcVoxelSize(srcDim);
        if orientationCode(srcDim) == opposites(rasDim)
            coord0 = (dims(srcDim) - 1) - coord0;
        end
        capVoxel0(:, srcDim) = coord0;
    end
end

function voxelSize = voxelSizesFromMat(M)
    voxelSize = sqrt(sum(double(M(1:3, 1:3)) .^ 2, 1));
    voxelSize(~isfinite(voxelSize) | voxelSize <= 0) = 1;
end

function vox1 = worldMmToVoxel1(worldMm, M)
    P = [double(worldMm), ones(size(worldMm, 1), 1)] / double(M)';
    vox1 = P(:, 1:3);
end

function info = capMakerVoxelOrientationFromMeta(meta)
    requireSkinMetaTransforms(meta);
    info = struct();
    info.t1Orientation = 'ras';
    info.permuteDims = [1 2 3];
    info.flipDims = [false false false];
    if isfield(meta.original, 'orientation') && ...
            ~isempty(meta.original.orientation)
        info.t1Orientation = validateOrientationCode(meta.original.orientation);
    end
    if isfield(meta.original, 'permuteDims') && ...
            ~isempty(meta.original.permuteDims)
        info.permuteDims = validatePermuteDims(meta.original.permuteDims);
    end
    if isfield(meta.original, 'flipDims') && ...
            ~isempty(meta.original.flipDims)
        info.flipDims = validateFlipDims(meta.original.flipDims);
    end
    info.size = double(meta.original.size(:)');
    info.voxelSize = double(meta.original.voxelSize(:)');
    if numel(info.size) ~= 3 || numel(info.voxelSize) ~= 3
        error('acsPlanHeadpostPlacement:BadSkinMeta', ...
            'Skin meta original.size and original.voxelSize must be length 3.');
    end
    info.capMakerVoxelOrientation = transformOrientationCode( ...
        info.t1Orientation, info.permuteDims, info.flipDims);
end

function requireSkinMetaTransforms(meta)
    ok = isstruct(meta) && isfield(meta, 'print') && ...
        isfield(meta, 'align') && isfield(meta, 'original') && ...
        isfield(meta.print, 'T_world2print') && ...
        isfield(meta.print, 'T_print2world') && ...
        isfield(meta.align, 'R') && ...
        isfield(meta.original, 'vox2world') && ...
        isfield(meta.original, 'voxelSize') && ...
        isfield(meta.original, 'size');
    if ~ok
        error('acsPlanHeadpostPlacement:BadSkinMeta', ...
            ['Skin meta lacks the capMaker print/original-volume ', ...
             'transform fields needed to place ROAST surfaces in print frame.']);
    end
end

function codeOut = transformOrientationCode(codeIn, permuteDims, flipDims)
    codeIn = validateOrientationCode(codeIn);
    permuteDims = validatePermuteDims(permuteDims);
    flipDims = validateFlipDims(flipDims);

    codeOut = codeIn(permuteDims);
    for dim = 1:3
        if flipDims(dim)
            codeOut(dim) = oppositeOrientationCode(codeOut(dim));
        end
    end
    codeOut = validateOrientationCode(codeOut);
end

function code = oppositeOrientationCode(code)
    switch code
        case 'r'
            code = 'l';
        case 'l'
            code = 'r';
        case 'a'
            code = 'p';
        case 'p'
            code = 'a';
        case 's'
            code = 'i';
        case 'i'
            code = 's';
        otherwise
            error('acsPlanHeadpostPlacement:BadOrientationCode', ...
                'Unknown orientation code "%s".', code);
    end
end

function code = validateOrientationCode(code)
    code = lower(strtrim(char(code)));
    code = regexprep(code, '[\s,;:_-]+', '');
    if numel(code) ~= 3
        error('acsPlanHeadpostPlacement:BadOrientationCode', ...
            'Orientation code must have exactly three characters.');
    end
    if any(~ismember(code, 'rlapsi'))
        error('acsPlanHeadpostPlacement:BadOrientationCode', ...
            'Orientation codes can only use r, l, a, p, s, and i.');
    end

    classes = cell(1, 3);
    for i = 1:3
        classes{i} = orientationClass(code(i));
    end
    expected = {'left-right', 'anterior-posterior', 'superior-inferior'};
    for i = 1:numel(expected)
        if sum(strcmp(classes, expected{i})) ~= 1
            error('acsPlanHeadpostPlacement:BadOrientationCode', ...
                'Use exactly one left/right, one anterior/posterior, and one superior/inferior direction.');
        end
    end
end

function permuteDims = validatePermuteDims(permuteDims)
    permuteDims = double(permuteDims(:)');
    if numel(permuteDims) ~= 3 || any(sort(permuteDims) ~= [1 2 3])
        error('acsPlanHeadpostPlacement:BadPermuteDims', ...
            'permuteDims must be a permutation of [1 2 3].');
    end
end

function flipDims = validateFlipDims(flipDims)
    flipDims = logical(flipDims(:)');
    if numel(flipDims) ~= 3
        error('acsPlanHeadpostPlacement:BadFlipDims', ...
            'flipDims must have three logical values.');
    end
end

function cls = orientationClass(code)
    switch code
        case {'r', 'l'}
            cls = 'left-right';
        case {'a', 'p'}
            cls = 'anterior-posterior';
        case {'s', 'i'}
            cls = 'superior-inferior';
        otherwise
            error('acsPlanHeadpostPlacement:BadOrientationCode', ...
                'Unknown orientation code "%s".', code);
    end
end

function printMm = originalWorldMmToPrintMm(worldMm, meta)
    validateSkinMetaForTransform(meta);
    finalWorldMm = (double(meta.align.R) * double(worldMm)')';
    printMm = applyAffineToPoints(meta.print.T_world2print, finalWorldMm);
end

function validateSkinMetaForTransform(meta)
    if ~isstruct(meta) || ~isfield(meta, 'align') || ...
            ~isfield(meta.align, 'R') || ~isfield(meta, 'print') || ...
            ~isfield(meta.print, 'T_world2print')
        error('acsPlanHeadpostPlacement:BadSkinMeta', ...
            'Skin metadata is missing align.R or print.T_world2print.');
    end
end

function pointsOut = applyAffineToPoints(M, pointsIn)
    pointsHom = [double(pointsIn), ones(size(pointsIn, 1), 1)];
    pointsHom = (double(M) * pointsHom')';
    pointsOut = pointsHom(:, 1:3);
end

function TR = ensureTri(value)
    if isa(value, 'triangulation')
        TR = value;
    elseif isstruct(value) && isfield(value, 'ConnectivityList') && isfield(value, 'Points')
        TR = triangulation(double(value.ConnectivityList), double(value.Points));
    else
        error('acsPlanHeadpostPlacement:BadTriangulation', ...
            'Expected a triangulation or struct with Points and ConnectivityList.');
    end
end

function info = publicSkullInfo(info)
    if isfield(info, 'runtime')
        info = rmfield(info, 'runtime');
    end
end

function info = headpostInfoForOutput(headpost)
    info = rmfieldIfPresent(headpost, {'TRraw', 'TRlocal'});
end

function summary = placementSummary(placement)
    summary = placement;
    summary = rmfieldIfPresent(summary, {'TRrigid', 'TRplaced'});
end

function S = rmfieldIfPresent(S, fields)
    for i = 1:numel(fields)
        if isfield(S, fields{i})
            S = rmfield(S, fields{i});
        end
    end
end

function saveQcFigure(fig, fileName)
    try
        exportgraphics(fig, fileName, 'Resolution', 160);
    catch
        saveas(fig, fileName);
    end
end

function printSummary(out)
    fprintf('\nHeadpost placement\n');
    fprintf('  mesh: %s\n', out.headpost.meshFile);
    fprintf('  trace points: %d (%s)\n', ...
        size(out.trace.coordinatesMm, 1), out.trace.method);
    fprintf('  frame: %s\n', out.coordinateFrame);
    fprintf('  contact print mm: [% .3f % .3f % .3f]\n', ...
        out.placement.pose.contactMm);
    fprintf('  yaw: %.3f deg\n', out.placement.pose.yawDeg);
    if isfield(out.headpost, 'refinement') && ...
            isfield(out.headpost.refinement, 'enabled') && ...
            out.headpost.refinement.enabled
        r = out.headpost.refinement;
        fprintf('  headpost refinement: %d -> %d faces, %d added vertices, final max edge %.3g mm\n', ...
            r.inputFaces, r.outputFaces, r.addedVertices, ...
            getOptionalField(r, 'finalMaxEdgeMm', NaN));
    end
    fprintf('  bend enabled: %d, vertices bent: %d\n', ...
        logical(out.placement.bendInfo.enabled), ...
        getOptionalField(out.placement.bendInfo, 'nBentVertices', 0));
    fprintf('  output: %s\n', out.outputFile);
    if ~isempty(out.qcFigure)
        fprintf('  QC figure: %s\n', out.qcFigure);
    end
end

function value = getOptionalField(S, fieldName, defaultValue)
    if isstruct(S) && isfield(S, fieldName) && ~isempty(S.(fieldName))
        value = S.(fieldName);
    else
        value = defaultValue;
    end
end

function tf = isfieldSafe(S, fieldName)
    tf = isstruct(S) && isfield(S, fieldName);
end

function S = firstStruct(raw)
    preferred = {'outForSave', 'out', 'placement'};
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
    error('acsPlanHeadpostPlacement:NoStructInFile', ...
        'MAT file does not contain a readable struct.');
end

function S = loadPlacementStruct(fileName)
    vars = whos('-file', fileName);
    names = {vars.name};
    preferred = {'outForSave', 'placement', 'out'};
    for i = 1:numel(preferred)
        if any(strcmp(names, preferred{i}))
            raw = load(fileName, preferred{i});
            S = raw.(preferred{i});
            if isfield(S, 'figure')
                S = rmfield(S, 'figure');
            end
            return;
        end
    end
    raw = load(fileName);
    S = firstStruct(raw);
    if isfield(S, 'figure')
        S = rmfield(S, 'figure');
    end
end

function ensureDir(pathIn)
    if ~isempty(pathIn) && exist(pathIn, 'dir') ~= 7
        mkdir(pathIn);
    end
end

function fileName = getFileName(fileName)
    [~, stem, ext] = fileparts(fileName);
    fileName = [stem ext];
end

function stem = stripMatExtension(fileName)
    [~, stem] = fileparts(fileName);
end

function name = safeName(name)
    name = regexprep(name, '[^A-Za-z0-9_+-]', '_');
end

function value = percentileLocal(values, pct)
    values = sort(double(values(:)));
    values = values(isfinite(values));
    if isempty(values)
        value = NaN;
        return;
    end
    pct = min(max(double(pct), 0), 100);
    pos = 1 + (numel(values) - 1) * pct / 100;
    lo = floor(pos);
    hi = ceil(pos);
    if lo == hi
        value = values(lo);
    else
        value = values(lo) + (pos - lo) * (values(hi) - values(lo));
    end
end

function pathOut = expandUserPath(pathOut)
    if isempty(pathOut)
        return;
    end
    if startsWith(pathOut, '~')
        homeDir = getenv('HOME');
        if isempty(homeDir)
            homeDir = getenv('USERPROFILE');
        end
        if numel(pathOut) == 1
            pathOut = homeDir;
        elseif any(pathOut(2) == ['/' '\'])
            pathOut = fullfile(homeDir, pathOut(3:end));
        end
    end
end
