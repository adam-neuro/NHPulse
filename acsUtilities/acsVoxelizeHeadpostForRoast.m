function out = acsVoxelizeHeadpostForRoast(headpostPlacement, baseMaskFile, varargin)
% ACSVOXELIZEHEADPOSTFORROAST Add a placed headpost mesh to a ROAST label mask.
%
% out = acsVoxelizeHeadpostForRoast(headpostPlacement, baseMaskFile)
% reads a placed headpost mesh in capMaker print-frame millimeters, maps it
% into the ROAST/T1 voxel grid, voxelizes it as label 7, and writes a
% derived ROAST hard-label mask.
%
% Label convention:
%   0 background, 1 white, 2 gray, 3 CSF, 4 bone, 5 skin, 6 air,
%   7 titanium.
%
% Name-value options:
%   skinCacheFile      : capMaker skin cache with transform metadata ['']
%   outputFile         : derived mask filename ['*_withHeadpost_T1orT2_SPM_masks.nii']
%   labelValue         : label assigned to the headpost [7]
%   labelName          : extra tissue name ['titanium']
%   conductivityField  : conductivity field name for ROAST ['titanium']
%   writableLabels     : labels that may become titanium [[0 4 5 6]]
%   protectedLabels    : labels that are never overwritten [[1 2 3]]
%   force              : overwrite existing output [false]
%   showFigures        : show QC figure [false]
%   saveFigures        : save QC figure [false]
%   overlayAlpha       : QC overlay transparency [0.55]
%   voxelizationMethod : 'auto', 'inpolyhedron', or 'ray' ['auto']
%   rayAxis            : 'auto', 'all', 'x', 'y', or 'z' ['auto']
%   chunkSize          : point chunk size for local ray casting [4000]
%   repairMeshNormals  : orient mesh faces before voxelization [true]
%   cleanupSkinComponents : remove disconnected scalp islands after voxelization [true]
%   skinCleanupMode    : 'largest' or 'minSize' ['largest']
%   minSkinComponentVoxels : minimum retained skin component for minSize [1000]
%   verbose            : print progress [true]

    if nargin < 1 || isempty(headpostPlacement)
        error('acsVoxelizeHeadpostForRoast:MissingPlacement', ...
            'Provide a headpost placement struct or MAT filename.');
    end
    if nargin < 2 || isempty(baseMaskFile)
        error('acsVoxelizeHeadpostForRoast:MissingMask', ...
            'Provide the source ROAST hard-label mask filename.');
    end

    opts = parseInputs(varargin{:});
    addLocalDependencies();

    placement = readPlacement(headpostPlacement);
    baseMaskFile = expandUserPath(char(baseMaskFile));
    requireFile(baseMaskFile, 'source ROAST hard-label mask');
    opts.skinCacheFile = resolveSkinCacheFile(opts.skinCacheFile, placement);
    if isempty(opts.outputFile)
        opts.outputFile = defaultOutputFile(baseMaskFile);
    end
    opts.outputFile = expandUserPath(opts.outputFile);

    if exist(opts.outputFile, 'file') == 2 && ~opts.force
        S = loadExistingReport(opts.outputFile);
        if ~isempty(S)
            out = S;
        else
            out = buildExistingReport(baseMaskFile, opts);
        end
        logMsg(opts, 'Headpost ROAST mask already exists; reusing %s', opts.outputFile);
        return;
    end

    Vmask = spm_vol(baseMaskFile);
    Vmask = Vmask(1);
    labels = uint8(round(spm_read_vols(Vmask)));
    TRplacedRaw = getPlacedMesh(placement);
    [TRplaced, meshPrepInfo] = prepareVoxelizationMesh(TRplacedRaw, opts);
    meta = readSkinMeta(opts.skinCacheFile);

    logMsg(opts, 'Mapping placed headpost mesh from capMaker print frame to ROAST voxel space.');
    [meshVoxel1, transformInfo] = printMmToT1Voxel1(TRplaced.Points, Vmask, meta);
    voxelizationMeshes = struct( ...
        'TRplacedRawPrintMm', TRplacedRaw, ...
        'TRplacedPreparedPrintMm', TRplaced, ...
        'TRplacedPreparedT1Voxel1', triangulation( ...
            TRplaced.ConnectivityList, meshVoxel1), ...
        'coordinateFrames', struct( ...
            'TRplacedRawPrintMm', 'capMakerPrintMm', ...
            'TRplacedPreparedPrintMm', 'capMakerPrintMm', ...
            'TRplacedPreparedT1Voxel1', 'T1 voxel coordinates, 1-based'));

    logMsg(opts, 'Voxelizing headpost mesh into ROAST label grid.');
    [headpostMask, voxelInfo] = voxelizeMeshInVoxelGrid( ...
        TRplaced.ConnectivityList, meshVoxel1, Vmask.dim(1:3), opts);
    voxelInfo.meshPreparation = meshPrepInfo;

    [labelsOut, overwriteInfo] = applyTitaniumLabel(labels, headpostMask, opts);
    [labelsOut, skinCleanupInfo] = cleanupSkinLabelComponents(labelsOut, opts);
    qcSliceInfo = headpostQcSliceInfo(labels, labelsOut, headpostMask, opts);
    writeLabelVolume(opts.outputFile, Vmask, labelsOut, ...
        sprintf('ACS ROAST labels with %s label %d', opts.labelName, opts.labelValue));

    qcFiles = {};
    fig = [];
    if opts.showFigures || opts.saveFigures
        figVisible = 'off';
        if opts.showFigures
            figVisible = 'on';
        end
        fig = makeQcFigure(labels, labelsOut, headpostMask, overwriteInfo, ...
            Vmask, opts, figVisible, qcSliceInfo);
        if opts.saveFigures
            qcDir = fullfile(fileparts(opts.outputFile), 'qc');
            ensureDir(qcDir);
            [~, stem] = fileparts(opts.outputFile);
            qcFile = fullfile(qcDir, [stem '_qc.png']);
            saveQcFigure(fig, qcFile);
            qcFiles = {qcFile};
        end
        if ~opts.showFigures && isgraphics(fig)
            close(fig);
            fig = [];
        end
    end

    out = struct();
    out.createdOn = char(datetime('now'));
    out.type = 'roastHeadpostMask';
    out.baseMaskFile = baseMaskFile;
    out.maskFile = opts.outputFile;
    out.outputFile = opts.outputFile;
    out.imageSize = Vmask.dim(1:3);
    out.labelValue = opts.labelValue;
    out.labelName = opts.labelName;
    out.extraTissues = struct( ...
        'label', opts.labelValue, ...
        'name', opts.labelName, ...
        'conductivityField', opts.conductivityField);
    out.material = ti6al4vMaterialSummary();
    out.skinCacheFile = opts.skinCacheFile;
    out.transformInfo = transformInfo;
    out.meshPreparation = meshPrepInfo;
    out.voxelizationMeshes = voxelizationMeshes;
    out.voxelization = voxelInfo;
    out.overwriteInfo = overwriteInfo;
    out.skinCleanup = skinCleanupInfo;
    out.qcSliceInfo = qcSliceInfo;
    out.voxelInspection = voxelInspectionSummary( ...
        labels, labelsOut, headpostMask, opts, 100000);
    out.voxelCounts = labelVoxelCounts(labelsOut);
    out.qcFiles = qcFiles(:);
    out.options = opts;
    out.figure = fig;

    outForSave = out;
    if isfield(outForSave, 'figure')
        outForSave = rmfield(outForSave, 'figure');
    end
    reportMat = reportFileForMask(opts.outputFile);
    save(reportMat, 'out', 'outForSave', '-v7.3');
    writeJsonReport(strrep(reportMat, '.mat', '.json'), removeFigureHandle(outForSave));
    printSummary(out, opts);
end

function opts = parseInputs(varargin)
    p = inputParser;
    p.FunctionName = 'acsVoxelizeHeadpostForRoast';
    addParameter(p, 'skinCacheFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'outputFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'labelValue', 7, @(x) isnumeric(x) && isscalar(x) && x > 6);
    addParameter(p, 'labelName', 'titanium', @(x) ischar(x) || isstring(x));
    addParameter(p, 'conductivityField', 'titanium', @(x) ischar(x) || isstring(x));
    addParameter(p, 'writableLabels', [0 4 5 6], @(x) isnumeric(x) && isvector(x));
    addParameter(p, 'protectedLabels', [1 2 3], @(x) isnumeric(x) && isvector(x));
    addParameter(p, 'force', false, @isBoolLike);
    addParameter(p, 'showFigures', false, @isBoolLike);
    addParameter(p, 'saveFigures', false, @isBoolLike);
    addParameter(p, 'overlayAlpha', 0.55, @(x) isnumeric(x) && isscalar(x) && x >= 0 && x <= 1);
    addParameter(p, 'voxelizationMethod', 'auto', @(x) ischar(x) || isstring(x));
    addParameter(p, 'rayAxis', 'auto', @(x) ischar(x) || isstring(x));
    addParameter(p, 'chunkSize', 4000, @(x) isnumeric(x) && isscalar(x) && x >= 100);
    addParameter(p, 'repairMeshNormals', true, @isBoolLike);
    addParameter(p, 'cleanupSkinComponents', true, @isBoolLike);
    addParameter(p, 'skinCleanupMode', 'largest', @(x) ischar(x) || isstring(x));
    addParameter(p, 'minSkinComponentVoxels', 1000, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0);
    addParameter(p, 'verbose', true, @isBoolLike);
    parse(p, varargin{:});

    opts = p.Results;
    opts.skinCacheFile = expandUserPath(char(opts.skinCacheFile));
    opts.outputFile = expandUserPath(char(opts.outputFile));
    opts.labelValue = uint8(round(double(opts.labelValue)));
    opts.labelName = safeName(lower(char(opts.labelName)));
    opts.conductivityField = safeName(lower(char(opts.conductivityField)));
    opts.writableLabels = unique(uint8(round(double(opts.writableLabels(:)'))));
    opts.protectedLabels = unique(uint8(round(double(opts.protectedLabels(:)'))));
    opts.force = logical(opts.force);
    opts.showFigures = logical(opts.showFigures);
    opts.saveFigures = logical(opts.saveFigures);
    opts.overlayAlpha = double(opts.overlayAlpha);
    opts.voxelizationMethod = validatestring(char(opts.voxelizationMethod), ...
        {'auto', 'inpolyhedron', 'ray'}, mfilename, 'voxelizationMethod');
    opts.rayAxis = normalizeRayAxis(opts.rayAxis);
    opts.chunkSize = round(double(opts.chunkSize));
    opts.repairMeshNormals = logical(opts.repairMeshNormals);
    opts.cleanupSkinComponents = logical(opts.cleanupSkinComponents);
    opts.skinCleanupMode = normalizeSkinCleanupMode(opts.skinCleanupMode);
    opts.minSkinComponentVoxels = round(double(opts.minSkinComponentVoxels));
    opts.verbose = logical(opts.verbose);

    if any(ismember(opts.protectedLabels, opts.writableLabels))
        error('acsVoxelizeHeadpostForRoast:ConflictingLabels', ...
            'protectedLabels and writableLabels must not overlap.');
    end
end

function tf = isBoolLike(x)
    tf = (islogical(x) || isnumeric(x)) && isscalar(x);
end

function mode = normalizeSkinCleanupMode(mode)
    mode = lower(strtrim(char(mode)));
    switch regexprep(mode, '[\s_\-]+', '')
        case {'largest', 'largestcomponent', 'main'}
            mode = 'largest';
        case {'minsize', 'minimumsize', 'threshold'}
            mode = 'minSize';
        otherwise
            error('acsVoxelizeHeadpostForRoast:BadSkinCleanupMode', ...
                'skinCleanupMode must be ''largest'' or ''minSize''.');
    end
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

function placement = readPlacement(value)
    if isstruct(value)
        placement = value;
        return;
    end
    fileName = expandUserPath(char(value));
    requireFile(fileName, 'headpost placement MAT file');
    placement = loadStructFilePreferSafe(fileName);
end

function S = firstStruct(raw)
    preferred = {'outForSave', 'out', 'headpostPlacement', 'placement'};
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
    error('acsVoxelizeHeadpostForRoast:NoStructInFile', ...
        'MAT file does not contain a readable struct.');
end

function S = loadStructFilePreferSafe(fileName)
    vars = whos('-file', fileName);
    names = {vars.name};
    preferred = {'outForSave', 'placement', 'headpostPlacement', 'out'};
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

function TR = getPlacedMesh(placement)
    if isfield(placement, 'meshes') && isstruct(placement.meshes) && ...
            isfield(placement.meshes, 'TRplaced')
        TR = ensureTri(placement.meshes.TRplaced);
        return;
    end
    if isfield(placement, 'TRplaced')
        TR = ensureTri(placement.TRplaced);
        return;
    end
    error('acsVoxelizeHeadpostForRoast:MissingPlacedMesh', ...
        'Headpost placement does not contain meshes.TRplaced.');
end

function [TRout, info] = prepareVoxelizationMesh(TRin, opts)
    TRout = ensureTri(TRin);
    info = struct();
    info.repairMeshNormals = opts.repairMeshNormals;
    info.before = meshTopologySummary(TRout);
    info.normalRepairApplied = false;
    info.normalRepairMethod = '';
    info.normalRepairError = '';

    if opts.repairMeshNormals
        if exist('unifyOutwardNormalsRobust', 'file') == 2
            try
                TRout = unifyOutwardNormalsRobust(TRout);
                info.normalRepairApplied = true;
                info.normalRepairMethod = 'unifyOutwardNormalsRobust';
            catch ME
                info.normalRepairError = ME.message;
                warning('acsVoxelizeHeadpostForRoast:NormalRepairFailed', ...
                    'Could not repair headpost face winding before voxelization: %s', ...
                    ME.message);
            end
        else
            info.normalRepairError = ...
                'unifyOutwardNormalsRobust was not found on the MATLAB path';
        end
    end

    info.after = meshTopologySummary(TRout);
    if info.after.boundaryEdgeCount > 0 || info.after.nonmanifoldEdgeCount > 0
        warning('acsVoxelizeHeadpostForRoast:NonWatertightHeadpostMesh', ...
            ['Headpost mesh may not be watertight: %d boundary edge(s), ', ...
             '%d non-manifold edge(s). Voxelization may show ray artifacts.'], ...
            info.after.boundaryEdgeCount, info.after.nonmanifoldEdgeCount);
    end
end

function info = meshTopologySummary(TR)
    V = double(TR.Points);
    F = double(TR.ConnectivityList);
    edges = [F(:, [1 2]); F(:, [2 3]); F(:, [3 1])];
    edges = sort(edges, 2);
    [uniqueEdges, ~, edgeGroup] = unique(edges, 'rows');
    edgeUseCount = accumarray(edgeGroup, 1);
    boundaryEdges = edgeUseCount == 1;
    nonmanifoldEdges = edgeUseCount > 2;

    info = struct();
    info.vertexCount = size(V, 1);
    info.faceCount = size(F, 1);
    info.uniqueEdgeCount = size(uniqueEdges, 1);
    info.boundaryEdgeCount = nnz(boundaryEdges);
    info.nonmanifoldEdgeCount = nnz(nonmanifoldEdges);
    info.isEdgeWatertight = info.boundaryEdgeCount == 0 && ...
        info.nonmanifoldEdgeCount == 0;
    info.signedVolume = meshSignedVolumeLocal(V, F);
    info.boundingBoxMm = [min(V, [], 1); max(V, [], 1)];
end

function value = meshSignedVolumeLocal(V, F)
    if isempty(V) || isempty(F)
        value = 0;
        return;
    end
    v1 = V(F(:, 1), :);
    v2 = V(F(:, 2), :);
    v3 = V(F(:, 3), :);
    value = sum(dot(v1, cross(v2, v3, 2), 2)) / 6;
end

function skinCacheFile = resolveSkinCacheFile(skinCacheFile, placement)
    if ~isempty(skinCacheFile)
        requireFile(skinCacheFile, 'capMaker skin cache');
        return;
    end
    if isfield(placement, 'surfaceSource') && isstruct(placement.surfaceSource)
        if isfield(placement.surfaceSource, 'cacheFile') && ...
                ~isempty(placement.surfaceSource.cacheFile)
            skinCacheFile = char(placement.surfaceSource.cacheFile);
        elseif isfield(placement.surfaceSource, 'file') && ...
                ~isempty(placement.surfaceSource.file)
            skinCacheFile = char(placement.surfaceSource.file);
        end
    end
    skinCacheFile = expandUserPath(skinCacheFile);
    requireFile(skinCacheFile, 'capMaker skin cache');
end

function meta = readSkinMeta(skinCacheFile)
    S = load(skinCacheFile, 'meta');
    if ~isfield(S, 'meta') || isempty(S.meta)
        error('acsVoxelizeHeadpostForRoast:MissingSkinMeta', ...
            'Skin cache does not contain metadata: %s', skinCacheFile);
    end
    meta = S.meta;
end

function [vox1, info] = printMmToT1Voxel1(pointsPrint, Vref, meta)
    [worldMm, info] = printMmToT1WorldMm(pointsPrint, Vref, meta);
    vox1 = worldMmToVoxel1(worldMm, Vref.mat);
end

function [t1WorldMm, info] = printMmToT1WorldMm(printMm, Vref, meta)
    requireSkinMetaTransforms(meta);
    orientation = capMakerVoxelOrientationFromMeta(meta);
    t1VoxelSize = voxelSizesFromMat(Vref.mat);
    capVoxel0 = capMakerPrintToCapVoxel(printMm, meta);
    rasVoxel1 = orientVoxelPointsToRas(capVoxel0, ...
        orientation.capMakerVoxelOrientation, orientation.size, ...
        orientation.voxelSize, t1VoxelSize);
    t1WorldMm = voxel1ToWorldMm(rasVoxel1, Vref.mat);

    info = orientation;
    info.method = 'capMakerPrintToT1World_v1';
    info.t1VoxelSize = t1VoxelSize;
    info.t1WorldReference = Vref.fname;
end

function capVoxel0 = capMakerPrintToCapVoxel(pointsPrint, meta)
    requireSkinMetaTransforms(meta);
    alignedWorldMm = applyAffineToPoints(meta.print.T_print2world, pointsPrint);
    capWorldMm = (double(meta.align.R) \ alignedWorldMm')';
    capVoxel0 = applyAffineToPoints(inv(double(meta.original.vox2world)), ...
        capWorldMm);
end

function rasVoxel1 = orientVoxelPointsToRas( ...
        voxel0, orientationCode, dims, srcVoxelSize, dstVoxelSize)
    orientationCode = validateOrientationCode(orientationCode);
    dims = double(dims(:)');
    srcVoxelSize = double(srcVoxelSize(:)');
    dstVoxelSize = double(dstVoxelSize(:)');

    targets = 'ras';
    opposites = 'lpi';
    rasMm = zeros(size(voxel0, 1), 3);
    for rasDim = 1:3
        srcDim = find(orientationCode == targets(rasDim) | ...
            orientationCode == opposites(rasDim), 1);
        if orientationCode(srcDim) == opposites(rasDim)
            coord0 = (dims(srcDim) - 1) - voxel0(:, srcDim);
        else
            coord0 = voxel0(:, srcDim);
        end
        rasMm(:, rasDim) = coord0 .* srcVoxelSize(srcDim);
    end

    rasVoxel1 = bsxfun(@rdivide, rasMm, dstVoxelSize) + 1;
end

function [mask, info] = voxelizeMeshInVoxelGrid(F, Vvox, dims, opts)
    dims = double(dims(:)');
    lo = max([1 1 1], floor(min(Vvox, [], 1)) - 1);
    hi = min(dims, ceil(max(Vvox, [], 1)) + 1);
    if any(hi < lo)
        error('acsVoxelizeHeadpostForRoast:MeshOutsideVolume', ...
            'Headpost mesh bounding box does not overlap the ROAST volume.');
    end

    [x, y, z] = ndgrid(lo(1):hi(1), lo(2):hi(2), lo(3):hi(3));
    points = [x(:), y(:), z(:)];
    clear x y z;

    [inside, method] = pointsInsideMesh(points, double(F), double(Vvox), opts);

    mask = false(dims);
    rows = points(inside, :);
    if ~isempty(rows)
        ind = sub2ind(dims, rows(:, 1), rows(:, 2), rows(:, 3));
        mask(ind) = true;
    end

    info = struct();
    info.method = method;
    info.meshVoxelBounds = [min(Vvox, [], 1); max(Vvox, [], 1)];
    info.candidateVoxelBounds = [lo; hi];
    info.candidateVoxelCount = size(points, 1);
    info.voxelCount = nnz(mask);
end

function [inside, method] = pointsInsideMesh(points, F, V, opts)
    useInpoly = any(strcmpi(opts.voxelizationMethod, {'auto', 'inpolyhedron'}));
    if useInpoly && exist('inpolyhedron', 'file') == 2
        try
            inside = inpolyhedron(F, V, points);
            method = 'inpolyhedron';
            return;
        catch ME
            if strcmpi(opts.voxelizationMethod, 'inpolyhedron')
                rethrow(ME);
            end
        end
    elseif strcmpi(opts.voxelizationMethod, 'inpolyhedron')
        error('acsVoxelizeHeadpostForRoast:MissingInpolyhedron', ...
            'voxelizationMethod="inpolyhedron" was requested, but inpolyhedron is not on the MATLAB path.');
    end

    axisList = rayAxisList(opts.rayAxis, F, V);
    inside = pointsInsideMeshByRay(points, F, V, opts, axisList);
    method = sprintf('ray casting %s', mat2str(axisList));
end

function inside = pointsInsideMeshByRay(P, F, V, opts, axisList)
    if nargin < 5 || isempty(axisList)
        axisList = rayAxisList(opts.rayAxis, F, V);
    end
    votes = false(size(P, 1), numel(axisList));
    for i = 1:numel(axisList)
        votes(:, i) = rayCastInsideAlongAxis(P, F, V, axisList(i), opts.chunkSize);
    end
    if size(votes, 2) == 1
        inside = votes(:, 1);
    else
        inside = sum(votes, 2) >= 2;
    end
end

function axisList = rayAxisList(rayAxis, F, V)
    switch rayAxis
        case 'x'
            axisList = 1;
        case 'y'
            axisList = 2;
        case 'z'
            axisList = 3;
        case 'all'
            axisList = [1 2 3];
        otherwise
            scores = projectedAreaScores(F, V);
            [~, axisList] = max(scores);
    end
end

function scores = projectedAreaScores(F, V)
    scores = zeros(1, 3);
    for axisId = 1:3
        order = [axisId setdiff(1:3, axisId, 'stable')];
        W = V(:, order);
        A = W(F(:, 2), 2:3) - W(F(:, 1), 2:3);
        B = W(F(:, 3), 2:3) - W(F(:, 1), 2:3);
        scores(axisId) = sum(abs(A(:, 1).*B(:, 2) - A(:, 2).*B(:, 1)));
    end
end

function inside = rayCastInsideAlongAxis(P, F, V, axisId, chunkSize)
    order = [axisId setdiff(1:3, axisId, 'stable')];
    P = P(:, order);
    V = V(:, order);
    T1 = V(F(:, 1), :);
    T2 = V(F(:, 2), :);
    T3 = V(F(:, 3), :);
    triMin23 = min(cat(3, T1(:, 2:3), T2(:, 2:3), T3(:, 2:3)), [], 3);
    triMax23 = max(cat(3, T1(:, 2:3), T2(:, 2:3), T3(:, 2:3)), [], 3);
    triMax1 = max([T1(:, 1), T2(:, 1), T3(:, 1)], [], 2);
    e1 = T2(:, 2:3) - T1(:, 2:3);
    e2 = T3(:, 2:3) - T1(:, 2:3);
    den = e1(:, 1).*e2(:, 2) - e1(:, 2).*e2(:, 1);
    goodTri = abs(den) > 1e-10;
    epsTol = 1e-9;

    inside = false(size(P, 1), 1);
    for a = 1:chunkSize:size(P, 1)
        b = min(size(P, 1), a + chunkSize - 1);
        Pc = P(a:b, :);
        count = zeros(size(Pc, 1), 1);
        for t = find(goodTri(:))'
            cand = Pc(:, 2) >= triMin23(t, 1) - epsTol & ...
                Pc(:, 2) <= triMax23(t, 1) + epsTol & ...
                Pc(:, 3) >= triMin23(t, 2) - epsTol & ...
                Pc(:, 3) <= triMax23(t, 2) + epsTol & ...
                Pc(:, 1) <= triMax1(t) + epsTol;
            if ~any(cand)
                continue;
            end
            Q = bsxfun(@minus, Pc(cand, 2:3), T1(t, 2:3));
            u = (Q(:, 1).*e2(t, 2) - Q(:, 2).*e2(t, 1)) ./ den(t);
            v = (e1(t, 1).*Q(:, 2) - e1(t, 2).*Q(:, 1)) ./ den(t);
            hit2 = u >= -epsTol & v >= -epsTol & (u + v) <= 1 + epsTol;
            if ~any(hit2)
                continue;
            end
            candRows = find(cand);
            hitRows = candRows(hit2);
            xInt = T1(t, 1) + u(hit2).*(T2(t, 1) - T1(t, 1)) + ...
                v(hit2).*(T3(t, 1) - T1(t, 1));
            hit = xInt > Pc(hitRows, 1) + epsTol;
            count(hitRows(hit)) = count(hitRows(hit)) + 1;
        end
        inside(a:b) = mod(count, 2) == 1;
    end
end

function [labelsOut, info] = applyTitaniumLabel(labels, headpostMask, opts)
    labelsOut = labels;
    candidate = logical(headpostMask);
    protected = candidate & ismember(labels, opts.protectedLabels);
    writable = candidate & ismember(labels, opts.writableLabels);
    skipped = candidate & ~protected & ~writable;
    labelsOut(writable) = opts.labelValue;

    info = struct();
    info.candidateVoxelCount = nnz(candidate);
    info.writtenVoxelCount = nnz(writable);
    info.protectedVoxelCount = nnz(protected);
    info.skippedVoxelCount = nnz(skipped);
    info.writableLabels = double(opts.writableLabels);
    info.protectedLabels = double(opts.protectedLabels);
    info.overwrittenByOriginalLabel = labelCountsForMask(labels, candidate);
    info.writtenByOriginalLabel = labelCountsForMask(labels, writable);
    info.protectedByOriginalLabel = labelCountsForMask(labels, protected);

    if info.protectedVoxelCount > 0
        warning('acsVoxelizeHeadpostForRoast:ProtectedOverlap', ...
            ['Headpost voxelization overlapped %d protected brain/CSF voxels. ', ...
             'Those voxels were not overwritten.'], info.protectedVoxelCount);
    end
    if info.skippedVoxelCount > 0
        warning('acsVoxelizeHeadpostForRoast:SkippedOverlap', ...
            ['Headpost voxelization included %d voxels whose labels are not writable. ', ...
             'Those voxels were not overwritten.'], info.skippedVoxelCount);
    end
end

function counts = labelCountsForMask(labels, mask)
    ids = 0:max(7, double(max(labels(:))));
    counts = struct();
    for i = 1:numel(ids)
        field = sprintf('label%d', ids(i));
        counts.(field) = nnz(mask & labels == ids(i));
    end
end

function [labelsOut, info] = cleanupSkinLabelComponents(labelsIn, opts)
    labelsOut = labelsIn;
    skin = labelsIn == 5;
    info = struct('enabled', opts.cleanupSkinComponents, ...
        'mode', opts.skinCleanupMode, ...
        'componentCountBefore', 0, ...
        'keptComponentCount', 0, ...
        'removedComponentCount', 0, ...
        'largestComponentVoxels', 0, ...
        'removedSkinVoxels', 0, ...
        'reason', '');
    if ~opts.cleanupSkinComponents
        info.reason = 'cleanupSkinComponents=false';
        return;
    end
    if nnz(skin) == 0
        info.reason = 'no skin voxels';
        return;
    end
    if exist('bwconncomp', 'file') ~= 2
        warning('acsVoxelizeHeadpostForRoast:MissingBwconncomp', ...
            'bwconncomp is unavailable; disconnected skin cleanup was skipped.');
        info.reason = 'bwconncomp unavailable';
        return;
    end

    CC = bwconncomp(skin, 26);
    sizes = cellfun(@numel, CC.PixelIdxList);
    info.componentCountBefore = CC.NumObjects;
    if isempty(sizes)
        info.reason = 'no connected components';
        return;
    end
    [largestSize, largestIdx] = max(sizes);
    info.largestComponentVoxels = largestSize;
    switch opts.skinCleanupMode
        case 'largest'
            keepComponents = largestIdx;
        case 'minSize'
            keepComponents = find(sizes >= opts.minSkinComponentVoxels);
            if isempty(keepComponents)
                keepComponents = largestIdx;
            end
        otherwise
            keepComponents = largestIdx;
    end

    keep = false(size(skin));
    for i = keepComponents(:)'
        keep(CC.PixelIdxList{i}) = true;
    end
    remove = skin & ~keep;
    labelsOut(remove) = uint8(0);

    info.keptComponentCount = numel(keepComponents);
    info.removedComponentCount = CC.NumObjects - numel(keepComponents);
    info.removedSkinVoxels = nnz(remove);
    if info.removedSkinVoxels == 0
        info.reason = 'no disconnected skin components removed';
    else
        info.reason = 'removed disconnected skin components';
    end
end

function fig = makeQcFigure(labels, labelsOut, headpostMask, overwriteInfo, Vref, opts, figVisible, qcSliceInfo)
    if nargin < 8 || isempty(qcSliceInfo)
        qcSliceInfo = headpostQcSliceInfo(labels, labelsOut, headpostMask, opts);
    end
    fig = figure('Name', 'ROAST headpost label QC', 'Color', 'w', ...
        'Visible', figVisible, 'Units', 'pixels', 'Position', [80 80 1500 820]);
    addFigureHeader(fig, sprintf('ROAST headpost label QC: label %d %s | written %d / candidate %d voxels', ...
        opts.labelValue, opts.labelName, ...
        overwriteInfo.writtenVoxelCount, overwriteInfo.candidateVoxelCount));

    dims = size(labels);
    sliceInd = qcSliceInfo.sliceIndices;
    axPos = threePanelPositions(0.24, 0.62);
    planeLabels = {'Sagittal', 'Coronal', 'Axial'};
    for dimToFix = 1:3
        ax = axes(fig, 'Position', axPos(dimToFix, :)); %#ok<LAXES>
        idx = max(1, min(dims(dimToFix), sliceInd(dimToFix)));
        baseSlice = rawSlice(labelsOut, dimToFix, idx);
        titaniumSlice = rawSlice(labelsOut == opts.labelValue, dimToFix, idx);
        protectedSlice = rawSlice(headpostMask & ismember(labels, opts.protectedLabels), dimToFix, idx);
        imagesc(ax, rot90(double(baseSlice)));
        axis(ax, 'image');
        axis(ax, 'off');
        colormap(ax, gray);
        hold(ax, 'on');
        rgb = zeros([size(titaniumSlice) 3], 'single');
        rgb(:, :, 1) = single(titaniumSlice);
        rgb(:, :, 2) = single(protectedSlice);
        overlay = image(ax, rot90Rgb(rgb));
        alpha = opts.overlayAlpha * double(titaniumSlice | protectedSlice);
        set(overlay, 'AlphaData', rot90(alpha));
        title(ax, sprintf('%s %d', planeLabels{dimToFix}, idx), ...
            'Interpreter', 'none', 'FontSize', 11, 'FontWeight', 'bold');
    end

    legendAx = axes(fig, 'Position', [0.06 0.04 0.88 0.12]); %#ok<LAXES>
    axis(legendAx, 'off');
    text(legendAx, 0.02, 0.72, 'Red: written titanium voxels', ...
        'Color', [0.8 0 0], 'FontWeight', 'bold');
    text(legendAx, 0.02, 0.42, 'Yellow/green: protected overlap, not overwritten', ...
        'Color', [0.45 0.35 0], 'FontWeight', 'bold');
    text(legendAx, 0.02, 0.12, ...
        sprintf('Writable labels: %s. Protected labels: %s.', ...
        mat2str(double(opts.writableLabels)), mat2str(double(opts.protectedLabels))), ...
        'Interpreter', 'none');
end

function info = headpostQcSliceInfo(labels, labelsOut, headpostMask, opts)
    dims = size(labels);
    rows = find(headpostMask);
    if isempty(rows)
        sliceInd = max(1, round(dims ./ 2));
    else
        [i, j, k] = ind2sub(dims, rows);
        sliceInd = round(median([i j k], 1));
    end

    written = headpostMask & (labelsOut == opts.labelValue);
    protected = headpostMask & ismember(labels, opts.protectedLabels);
    writtenPerSlice = zeros(1, 3);
    protectedPerSlice = zeros(1, 3);
    for dimToFix = 1:3
        idx = max(1, min(dims(dimToFix), sliceInd(dimToFix)));
        writtenPerSlice(dimToFix) = nnz(rawSlice(written, dimToFix, idx));
        protectedPerSlice(dimToFix) = nnz(rawSlice(protected, dimToFix, idx));
    end

    info = struct();
    info.sliceIndices = sliceInd;
    info.sliceLabels = {'Sagittal', 'Coronal', 'Axial'};
    info.writtenVoxelCountOnSlice = writtenPerSlice;
    info.protectedVoxelCountOnSlice = protectedPerSlice;
end

function info = voxelInspectionSummary(labels, labelsOut, headpostMask, opts, maxRows)
    if nargin < 5 || isempty(maxRows)
        maxRows = 100000;
    end
    written = headpostMask & (labelsOut == opts.labelValue);
    protected = headpostMask & ismember(labels, opts.protectedLabels);

    info = struct();
    info.maxStoredRows = maxRows;
    info.candidate = maskSubscriptSample(headpostMask, maxRows);
    info.written = maskSubscriptSample(written, maxRows);
    info.protected = maskSubscriptSample(protected, maxRows);
end

function sample = maskSubscriptSample(mask, maxRows)
    dims = size(mask);
    rows = find(mask);
    n = numel(rows);
    if n > maxRows
        keep = unique(round(linspace(1, n, maxRows)));
        rows = rows(keep);
    end
    [i, j, k] = ind2sub(dims, rows);
    sample = struct();
    sample.count = n;
    sample.storedCount = numel(rows);
    sample.truncated = n > maxRows;
    sample.linearIndices = rows(:);
    sample.subscripts = [i(:), j(:), k(:)];
end

function styles = labelNames()
    styles = {'background', 'white', 'gray', 'csf', 'bone', 'skin', 'air', 'titanium'};
end

function counts = labelVoxelCounts(labels)
    names = labelNames();
    counts = struct();
    maxLabel = max(double(labels(:)));
    for k = 0:max(maxLabel, numel(names) - 1)
        if k + 1 <= numel(names)
            field = names{k + 1};
        else
            field = sprintf('label%d', k);
        end
        counts.(field) = nnz(labels == k);
    end
end

function writeLabelVolume(fileName, Vref, labels, description)
    deleteDerivedNifti(fileName);
    Vout = Vref;
    Vout.fname = fileName;
    Vout.dim = size(labels);
    Vout.dt = [spm_type('uint8') spm_platform('bigend')];
    Vout.n = [1 1];
    Vout.private = [];
    Vout.pinfo = [1; 0; 0];
    Vout.descrip = description;
    ensureDir(fileparts(fileName));
    spm_write_vol(Vout, uint8(labels));
end

function fileName = defaultOutputFile(baseMaskFile)
    [folder, stem, ext] = fileparts(baseMaskFile);
    if strcmpi(ext, '.gz')
        [~, stem, ext2] = fileparts(stem);
        ext = [ext2 ext];
    end
    newStem = regexprep(stem, '_T1orT2_SPM_masks$', ...
        '_withHeadpost_T1orT2_SPM_masks');
    if strcmp(newStem, stem)
        newStem = [stem '_withHeadpost'];
    end
    if isempty(ext)
        ext = '.nii';
    end
    fileName = fullfile(folder, [newStem ext]);
end

function reportMat = reportFileForMask(maskFile)
    [folder, stem] = fileparts(maskFile);
    reportMat = fullfile(folder, [stem '_report.mat']);
end

function out = loadExistingReport(maskFile)
    out = [];
    reportMat = reportFileForMask(maskFile);
    if exist(reportMat, 'file') ~= 2
        return;
    end
    S = load(reportMat);
    try
        out = firstStruct(S);
    catch
        out = [];
    end
end

function out = buildExistingReport(baseMaskFile, opts)
    out = struct();
    out.type = 'roastHeadpostMask';
    out.baseMaskFile = baseMaskFile;
    out.maskFile = opts.outputFile;
    out.outputFile = opts.outputFile;
    out.reusedExisting = true;
    out.extraTissues = struct('label', opts.labelValue, ...
        'name', opts.labelName, 'conductivityField', opts.conductivityField);
    out.material = ti6al4vMaterialSummary();
    out.options = opts;
end

function material = ti6al4vMaterialSummary()
    resistivityRange = [168 170] * 1e-8;
    material = struct();
    material.name = 'Ti6Al4V Grade 5';
    material.resistivityOhmMRange = resistivityRange;
    material.defaultResistivityOhmM = mean(resistivityRange);
    material.conductivitySPerMRange = 1 ./ fliplr(resistivityRange);
    material.defaultConductivitySPerM = 1 / material.defaultResistivityOhmM;
    material.note = ['Conductivity is the reciprocal of resistivity; ', ...
        'use conductivities.titanium to override for a specific alloy/source.'];
end

function rayAxis = normalizeRayAxis(value)
    rayAxis = lower(strtrim(char(value)));
    switch rayAxis
        case {'auto', 'all', 'x', 'y', 'z'}
        otherwise
            error('acsVoxelizeHeadpostForRoast:BadRayAxis', ...
                'rayAxis must be ''auto'', ''all'', ''x'', ''y'', or ''z''.');
    end
end

function TR = ensureTri(value)
    if isa(value, 'triangulation')
        TR = value;
    elseif isstruct(value) && isfield(value, 'ConnectivityList') && isfield(value, 'Points')
        TR = triangulation(double(value.ConnectivityList), double(value.Points));
    else
        error('acsVoxelizeHeadpostForRoast:BadTriangulation', ...
            'Expected a triangulation or struct with Points and ConnectivityList.');
    end
end

function voxelSize = voxelSizesFromMat(M)
    voxelSize = sqrt(sum(double(M(1:3, 1:3)) .^ 2, 1));
    voxelSize(~isfinite(voxelSize) | voxelSize <= 0) = 1;
end

function worldMm = voxel1ToWorldMm(vox1, M)
    P = [double(vox1), ones(size(vox1, 1), 1)] * double(M)';
    worldMm = P(:, 1:3);
end

function vox1 = worldMmToVoxel1(worldMm, M)
    P = [double(worldMm), ones(size(worldMm, 1), 1)] / double(M)';
    vox1 = P(:, 1:3);
end

function pointsOut = applyAffineToPoints(M, pointsIn)
    pointsHom = [double(pointsIn), ones(size(pointsIn, 1), 1)];
    pointsHom = (double(M) * pointsHom')';
    pointsOut = pointsHom(:, 1:3);
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
        error('acsVoxelizeHeadpostForRoast:BadSkinMeta', ...
            'Skin metadata lacks capMaker print/original-volume transform fields.');
    end
end

function info = capMakerVoxelOrientationFromMeta(meta)
    requireSkinMetaTransforms(meta);
    info = struct();
    info.t1Orientation = 'ras';
    info.permuteDims = [1 2 3];
    info.flipDims = [false false false];
    if isfield(meta.original, 'orientation') && ~isempty(meta.original.orientation)
        info.t1Orientation = validateOrientationCode(meta.original.orientation);
    end
    if isfield(meta.original, 'permuteDims') && ~isempty(meta.original.permuteDims)
        info.permuteDims = validatePermuteDims(meta.original.permuteDims);
    end
    if isfield(meta.original, 'flipDims') && ~isempty(meta.original.flipDims)
        info.flipDims = validateFlipDims(meta.original.flipDims);
    end
    info.size = double(meta.original.size(:)');
    info.voxelSize = double(meta.original.voxelSize(:)');
    if numel(info.size) ~= 3 || numel(info.voxelSize) ~= 3
        error('acsVoxelizeHeadpostForRoast:BadSkinMeta', ...
            'Skin meta original.size and original.voxelSize must be length 3.');
    end
    info.capMakerVoxelOrientation = transformOrientationCode( ...
        info.t1Orientation, info.permuteDims, info.flipDims);
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
            error('acsVoxelizeHeadpostForRoast:BadOrientationCode', ...
                'Unknown orientation code "%s".', code);
    end
end

function code = validateOrientationCode(code)
    code = lower(strtrim(char(code)));
    code = regexprep(code, '[\s,;:_-]+', '');
    if numel(code) ~= 3 || any(~ismember(code, 'rlapsi'))
        error('acsVoxelizeHeadpostForRoast:BadOrientationCode', ...
            'Orientation code must contain one each of r/l, a/p, and s/i.');
    end
    classes = arrayfun(@orientationClass, code, 'UniformOutput', false);
    expected = {'left-right', 'anterior-posterior', 'superior-inferior'};
    for i = 1:numel(expected)
        if sum(strcmp(classes, expected{i})) ~= 1
            error('acsVoxelizeHeadpostForRoast:BadOrientationCode', ...
                'Orientation code must contain one each of r/l, a/p, and s/i.');
        end
    end
end

function permuteDims = validatePermuteDims(permuteDims)
    permuteDims = double(permuteDims(:)');
    if numel(permuteDims) ~= 3 || any(sort(permuteDims) ~= [1 2 3])
        error('acsVoxelizeHeadpostForRoast:BadPermuteDims', ...
            'permuteDims must be a permutation of [1 2 3].');
    end
end

function flipDims = validateFlipDims(flipDims)
    flipDims = logical(flipDims(:)');
    if numel(flipDims) ~= 3
        error('acsVoxelizeHeadpostForRoast:BadFlipDims', ...
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
            cls = 'unknown';
    end
end

function S = rawSlice(vol, dimToFix, idx)
    switch dimToFix
        case 1
            S = squeeze(vol(idx, :, :));
        case 2
            S = squeeze(vol(:, idx, :));
        case 3
            S = squeeze(vol(:, :, idx));
        otherwise
            error('acsVoxelizeHeadpostForRoast:BadSliceDimension', ...
                'Unsupported slice dimension %d.', dimToFix);
    end
end

function out = rot90Rgb(in)
    out = zeros([size(in, 2) size(in, 1) size(in, 3)], 'like', in);
    for c = 1:size(in, 3)
        out(:, :, c) = rot90(in(:, :, c));
    end
end

function positions = threePanelPositions(y0, h)
    margin = 0.045;
    gap = 0.035;
    w = (1 - 2 * margin - 2 * gap) / 3;
    positions = zeros(3, 4);
    for i = 1:3
        x0 = margin + (i - 1) * (w + gap);
        positions(i, :) = [x0 y0 w h];
    end
end

function addFigureHeader(fig, headerText)
    annotation(fig, 'textbox', [0.04 0.935 0.92 0.05], ...
        'String', headerText, ...
        'Interpreter', 'none', ...
        'HorizontalAlignment', 'center', ...
        'VerticalAlignment', 'middle', ...
        'FontWeight', 'bold', ...
        'FontSize', 12, ...
        'EdgeColor', 'none');
end

function report = removeFigureHandle(report)
    if isfield(report, 'figure')
        report = rmfield(report, 'figure');
    end
end

function saveQcFigure(fig, fileName)
    try
        exportgraphics(fig, fileName, 'Resolution', 150);
    catch
        saveas(fig, fileName);
    end
end

function writeJsonReport(fileName, report)
    fid = fopen(fileName, 'w');
    if fid == -1
        warning('acsVoxelizeHeadpostForRoast:CannotWriteJson', ...
            'Could not write report JSON: %s', fileName);
        return;
    end
    cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fprintf(fid, '%s', jsonencode(report, 'PrettyPrint', true));
end

function printSummary(out, opts)
    if ~opts.verbose
        return;
    end
    fprintf('\nROAST headpost voxelization\n');
    fprintf('  source mask: %s\n', out.baseMaskFile);
    fprintf('  output mask: %s\n', out.maskFile);
    fprintf('  label %d: %s\n', out.labelValue, out.labelName);
    fprintf('  candidate voxels: %d\n', out.voxelization.voxelCount);
    fprintf('  written voxels: %d\n', out.overwriteInfo.writtenVoxelCount);
    fprintf('  protected overlap skipped: %d\n', out.overwriteInfo.protectedVoxelCount);
    if isfield(out, 'skinCleanup') && isstruct(out.skinCleanup) && ...
            out.skinCleanup.enabled
        fprintf('  skin cleanup: %s, components %d -> %d, removed %d voxels\n', ...
            out.skinCleanup.mode, out.skinCleanup.componentCountBefore, ...
            out.skinCleanup.keptComponentCount, out.skinCleanup.removedSkinVoxels);
    end
    fprintf('  default Ti6Al4V conductivity: %.6g S/m\n', ...
        out.material.defaultConductivitySPerM);
end

function requireFile(fileName, label)
    if isempty(fileName) || exist(fileName, 'file') ~= 2
        error('acsVoxelizeHeadpostForRoast:MissingFile', ...
            '%s not found: %s', label, fileName);
    end
end

function deleteDerivedNifti(fileName)
    if exist(fileName, 'file') == 2
        delete(fileName);
    end
    [folder, base] = fileparts(fileName);
    matFile = fullfile(folder, [base '.mat']);
    if exist(matFile, 'file') == 2
        delete(matFile);
    end
end

function ensureDir(pathIn)
    if ~isempty(pathIn) && exist(pathIn, 'dir') ~= 7
        mkdir(pathIn);
    end
end

function name = getFileName(filePath)
    [~, name, ext] = fileparts(filePath);
    name = [name ext];
end

function name = safeName(value)
    name = regexprep(char(value), '[^A-Za-z0-9_]', '_');
end

function p = expandUserPath(p)
    if isempty(p)
        return;
    end
    p = char(p);
    if startsWith(p, '~')
        homeDir = getenv('HOME');
        if isempty(homeDir)
            homeDir = getenv('USERPROFILE');
        end
        if numel(p) == 1
            p = homeDir;
        elseif any(p(2) == ['/' '\'])
            p = fullfile(homeDir, p(3:end));
        end
    end
end

function logMsg(opts, varargin)
    if opts.verbose
        fprintf([varargin{1} '\n'], varargin{2:end});
    end
end
