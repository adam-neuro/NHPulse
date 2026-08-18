function out = acsMakeRoastCapMakerLayout(roastSource, varargin)
% ACSMAKEROASTCAPMAKERLAYOUT Build ROAST custom electrodes with capMaker logic.
%
% out = acsMakeRoastCapMakerLayout(segOut) uses segOut.roastReady from
% acsSegmentAnatomyWithTpm, extracts an outer head surface, runs capMaker's
% autoElectrodeTargets on that surface, and writes the ROAST custom location file:
%   <T1 stem>_customLocations
%
% The custom location coordinates are written in ROAST's native voxel
% coordinate frame for the RAS working T1. Keep ROAST resampling off when
% using this file.
%
% Name-value options:
%   maskFile        : explicit ROAST hard-label mask file ['']
%   nElectrodes     : number of custom electrodes [8]
%   electrodeNames  : names in customLocations file [{'custom1', ...}]
%   capFraction     : superior head-surface fraction used for layout [0.45]
%   targetOptions   : struct passed to autoElectrodeTargets [cap defaults]
%                     set targetOptions.manualTargetsMm to reuse explicit
%                     capMaker print-frame target coordinates
%   earExclusionMode : 'auto', 'always', or 'never' ['auto']
%   earExclusionFile : explicit saved ear-exclusion MAT file ['']
%   strapExclusionMode : 'auto', 'always', or 'none' ['auto']
%   strapRostralOffsetMm : strap keepout offset rostral to ear edge [0]
%   strapWidthMm    : nominal chin-strap width for keepout [10]
%   strapMarginMm   : extra strap/electrode placement margin [2]
%   outputFile      : explicit customLocations path ['']
%   surfaceSource   : 'capMaker' or 'roastLabels' ['capMaker']
%   subjectId       : subject used to find capMaker DICOM/cache ['']
%   dicomDir        : explicit DICOM folder for legacy capMaker surface ['']
%   capMakerInputFile : explicit input for capMaker surface ['']
%   skinCacheFile   : capMaker scalp mesh cache ['']
%   forceSkinMesh   : recompute capMaker scalp mesh [false]
%   skinMeshOptions : struct passed to skinMeshFromMPRAGE [struct()]
%   cropPlaneMode   : autoSelect, auto, select, reuse, or default ['auto']
%   cropPlaneFile   : saved capMaker crop-plane MAT file ['']
%   t1Orientation   : raw T1 voxel orientation, or auto from segOut ['auto']
%   capMakerPermuteDims : capMaker pre-crop permuteDims [[3 1 2]]
%   capMakerFlipDims    : capMaker pre-crop flipDims [[false false true]]
%   capMakerVoxelOrientation : capMaker pre-crop voxel orientation ['auto']
%   capMakerTransformMode : 'metadata' or 'autoSearch' ['metadata']
%   transformSearchMaxPoints : scalp points used to score transforms [1500]
%   snapDistanceWarnVox : warn if final snap distance exceeds this [5]
%   forceLayout     : overwrite existing customLocations [false]
%   force           : legacy alias for forceLayout [false]
%   showFigures     : show QC figure [false]
%   saveFigures     : save QC figure [false]
%   rngSeed         : deterministic seed for capMaker target sampling [1]
%   verbose         : print progress [false]

    if nargin < 1 || isempty(roastSource)
        error('acsMakeRoastCapMakerLayout:MissingInput', ...
            'Provide a segmentation output struct, roastReady struct, or ROAST T1 filename.');
    end

    opts = parseInputs(varargin{:});
    addLocalDependencies();

    [t1File, maskFile] = resolveRoastInputs(roastSource, opts);
    if isempty(opts.outputFile)
        opts.outputFile = inferCustomLocationsFile(t1File);
    end
    opts.outputFile = expandUserPath(opts.outputFile);

    if exist(opts.outputFile, 'file') == 2 && ~opts.forceLayout && ...
            ~strcmp(opts.cropPlaneMode, 'select')
        logMsg(opts, 'Custom locations already exist; reusing %s', opts.outputFile);
        out = buildExistingReport(t1File, maskFile, opts);
        return;
    end

    targetOpts = capMakerTargetOptions(opts.targetOptions);
    names = normalizeElectrodeNames(opts.electrodeNames, opts.nElectrodes);
    labelSurface = roastLabelSurface(maskFile, opts);

    switch opts.surfaceSource
        case 'roastLabels'
            layout = makeLayoutFromRoastLabels(labelSurface, targetOpts, opts);
        case 'capMaker'
            layout = makeLayoutFromCapMaker(labelSurface, roastSource, t1File, targetOpts, opts);
        otherwise
            error('acsMakeRoastCapMakerLayout:BadSurfaceSource', ...
                'Unknown surfaceSource "%s".', opts.surfaceSource);
    end

    targetVox = layout.targetVox;
    targetMm = layout.targetMm;

    writeCustomLocations(opts.outputFile, names, targetVox);
    logMsg(opts, 'Wrote ROAST custom locations: %s', opts.outputFile);

    qcFiles = {};
    fig = [];
    if opts.showFigures || opts.saveFigures
        figVisible = 'off';
        if opts.showFigures
            figVisible = 'on';
        end
        fig = makeLayoutQcFigure(layout, labelSurface, names, opts, figVisible);
        if opts.saveFigures
            qcDir = fullfile(fileparts(opts.outputFile), 'qc');
            ensureDir(qcDir);
            [~, customStem] = fileparts(opts.outputFile);
            qcFile = fullfile(qcDir, [customStem '_qc.png']);
            saveQcFigure(fig, qcFile);
            qcFiles = {qcFile};
        end
        if ~opts.showFigures
            close(fig);
            fig = [];
        end
    end

    out = buildReport(t1File, maskFile, labelSurface.Vmask, opts, names, targetVox, ...
        targetMm, layout.layoutTargetsMm, layout.layoutInfo, targetOpts, ...
        layout.targetInfo, qcFiles);
    out.figure = fig;
    saveReport(out);
end

function opts = parseInputs(varargin)
    p = inputParser;
    p.FunctionName = 'acsMakeRoastCapMakerLayout';
    addParameter(p, 'maskFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'nElectrodes', 8, @(x) isnumeric(x) && isscalar(x) && x >= 1);
    addParameter(p, 'electrodeNames', {}, @(x) iscell(x) || ischar(x) || isstring(x));
    addParameter(p, 'capFraction', 0.45, @(x) isnumeric(x) && isscalar(x) && x > 0 && x <= 1);
    addParameter(p, 'targetOptions', struct(), @(x) isempty(x) || isstruct(x));
    addParameter(p, 'earExclusionMode', 'auto', @(x) ischar(x) || isstring(x));
    addParameter(p, 'earExclusionFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'strapExclusionMode', 'auto', @(x) ischar(x) || isstring(x));
    addParameter(p, 'strapRostralOffsetMm', 0, @isNonnegativeScalar);
    addParameter(p, 'strapWidthMm', 10, @isPositiveScalar);
    addParameter(p, 'holderOutsideDiaMm', 12, @isPositiveScalar);
    addParameter(p, 'strapMarginMm', 2, @isNonnegativeScalar);
    addParameter(p, 'strapExclusionRadiusMm', [], ...
        @(x) isempty(x) || isPositiveScalar(x));
    addParameter(p, 'strapLateralLengthMm', 35, @isPositiveScalar);
    addParameter(p, 'strapSampleSpacingMm', 5, @isPositiveScalar);
    addParameter(p, 'zBedMm', 0, @(x) isnumeric(x) && isscalar(x) && isfinite(x));
    addParameter(p, 'outputFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'surfaceSource', 'capMaker', @(x) ischar(x) || isstring(x));
    addParameter(p, 'subjectId', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'dicomDir', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'capMakerInputFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'skinCacheFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'forceSkinMesh', false, @isBoolLike);
    addParameter(p, 'skinMeshOptions', struct(), @(x) isempty(x) || isstruct(x));
    addParameter(p, 'cropPlaneMode', 'auto', @(x) ischar(x) || isstring(x));
    addParameter(p, 'cropPlaneFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 't1Orientation', 'auto', @(x) ischar(x) || isstring(x));
    addParameter(p, 'capMakerPermuteDims', [3 1 2], @(x) isnumeric(x) && numel(x) == 3);
    addParameter(p, 'capMakerFlipDims', [false false true], @(x) (isnumeric(x) || islogical(x)) && numel(x) == 3);
    addParameter(p, 'capMakerVoxelOrientation', 'auto', @(x) ischar(x) || isstring(x));
    addParameter(p, 'capMakerTransformMode', 'metadata', @(x) ischar(x) || isstring(x));
    addParameter(p, 'transformSearchMaxPoints', 1500, @(x) isnumeric(x) && isscalar(x) && x >= 1);
    addParameter(p, 'snapDistanceWarnVox', 5, @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x > 0));
    addParameter(p, 'forceLayout', [], @(x) isempty(x) || isBoolLike(x));
    addParameter(p, 'force', false, @isBoolLike);
    addParameter(p, 'showFigures', false, @isBoolLike);
    addParameter(p, 'saveFigures', false, @isBoolLike);
    addParameter(p, 'rngSeed', 1, @(x) isempty(x) || (isnumeric(x) && isscalar(x)));
    addParameter(p, 'verbose', false, @isBoolLike);
    parse(p, varargin{:});

    opts = p.Results;
    opts.maskFile = expandUserPath(char(opts.maskFile));
    opts.nElectrodes = round(double(opts.nElectrodes));
    opts.electrodeNames = normalizeNameInput(opts.electrodeNames);
    opts.capFraction = double(opts.capFraction);
    opts.earExclusionMode = normalizeEarExclusionMode(opts.earExclusionMode);
    opts.earExclusionFile = expandUserPath(char(opts.earExclusionFile));
    opts.strapExclusionMode = normalizeStrapExclusionMode(opts.strapExclusionMode);
    opts.strapRostralOffsetMm = double(opts.strapRostralOffsetMm);
    opts.strapWidthMm = double(opts.strapWidthMm);
    opts.holderOutsideDiaMm = double(opts.holderOutsideDiaMm);
    opts.strapMarginMm = double(opts.strapMarginMm);
    if ~isempty(opts.strapExclusionRadiusMm)
        opts.strapExclusionRadiusMm = double(opts.strapExclusionRadiusMm);
    end
    opts.strapLateralLengthMm = double(opts.strapLateralLengthMm);
    opts.strapSampleSpacingMm = double(opts.strapSampleSpacingMm);
    opts.zBedMm = double(opts.zBedMm);
    opts.outputFile = char(opts.outputFile);
    opts.surfaceSource = normalizeSurfaceSource(opts.surfaceSource);
    opts.subjectId = char(opts.subjectId);
    opts.dicomDir = expandUserPath(char(opts.dicomDir));
    opts.capMakerInputFile = expandUserPath(char(opts.capMakerInputFile));
    opts.skinCacheFile = expandUserPath(char(opts.skinCacheFile));
    opts.forceSkinMesh = logical(opts.forceSkinMesh);
    opts.cropPlaneMode = normalizeCropPlaneMode(opts.cropPlaneMode);
    opts.cropPlaneFile = expandUserPath(char(opts.cropPlaneFile));
    opts.t1Orientation = normalizeOrientationRequest(opts.t1Orientation);
    opts.capMakerPermuteDims = validatePermuteDims(opts.capMakerPermuteDims);
    opts.capMakerFlipDims = validateFlipDims(opts.capMakerFlipDims);
    opts.capMakerVoxelOrientation = normalizeOrientationRequest(opts.capMakerVoxelOrientation);
    opts.capMakerTransformMode = normalizeTransformMode(opts.capMakerTransformMode);
    opts.transformSearchMaxPoints = round(double(opts.transformSearchMaxPoints));
    if ~isempty(opts.snapDistanceWarnVox)
        opts.snapDistanceWarnVox = double(opts.snapDistanceWarnVox);
    end
    if isempty(opts.forceLayout)
        opts.forceLayout = logical(opts.force);
    else
        opts.forceLayout = logical(opts.forceLayout);
    end
    opts.force = opts.forceLayout;
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

function source = normalizeSurfaceSource(source)
    source = lower(strtrim(char(source)));
    switch source
        case {'capmaker', 'cap', 'skinmesh', 'skin'}
            source = 'capMaker';
        case {'roastlabels', 'roast', 'labels', 'mask'}
            source = 'roastLabels';
        otherwise
            error('acsMakeRoastCapMakerLayout:BadSurfaceSource', ...
                'surfaceSource must be ''capMaker'' or ''roastLabels''.');
    end
end

function addLocalDependencies()
    repoRoot = fileparts(fileparts(mfilename('fullpath')));
    if exist('setNHPulsePath', 'file') ~= 2
        addpath(repoRoot);
    end
    setNHPulsePath('repoRoot', repoRoot, 'verbose', false);
end

function [t1File, maskFile] = resolveRoastInputs(roastSource, opts)
    t1File = '';
    maskFile = opts.maskFile;

    if isstruct(roastSource)
        if isfield(roastSource, 'roastReady')
            roastSource = roastSource.roastReady;
        end
        if isfield(roastSource, 't1File')
            t1File = char(roastSource.t1File);
        end
        if isempty(maskFile) && isfield(roastSource, 'maskFile')
            maskFile = char(roastSource.maskFile);
        end
    else
        t1File = char(roastSource);
    end

    t1File = expandUserPath(t1File);
    if isempty(t1File) || exist(t1File, 'file') ~= 2
        error('acsMakeRoastCapMakerLayout:T1NotFound', ...
            'ROAST T1 file not found: %s', t1File);
    end

    if isempty(maskFile)
        maskFile = inferRoastMaskFile(t1File);
    end
    maskFile = expandUserPath(maskFile);
    if exist(maskFile, 'file') ~= 2
        error('acsMakeRoastCapMakerLayout:MaskNotFound', ...
            'ROAST hard-label mask file not found: %s', maskFile);
    end
end

function maskFile = inferRoastMaskFile(t1File)
    [folder, stem] = fileparts(t1File);
    maskFile = fullfile(folder, [stem '_T1orT2_SPM_masks.nii']);
end

function customFile = inferCustomLocationsFile(t1File)
    [folder, stem] = fileparts(t1File);
    customFile = fullfile(folder, [stem '_customLocations']);
end

function [Vmask, labels] = readLabelMask(maskFile)
    requireSpm();
    Vmask = spm_vol(maskFile);
    Vmask = Vmask(1);
    labels = uint8(round(spm_read_vols(Vmask)));
end

function requireSpm()
    if exist('spm_vol', 'file') ~= 2 || exist('spm_read_vols', 'file') ~= 2
        error('acsMakeRoastCapMakerLayout:MissingSpm', ...
            '%s', nhpulseMissingDependencyMessage('SPM', ...
            'SPM is required to read ROAST label volumes.', ...
            {'spm_vol', 'spm_read_vols'}));
    end
end

function voxelSize = voxelSizesFromMat(M)
    voxelSize = sqrt(sum(M(1:3, 1:3) .^ 2, 1));
    if any(~isfinite(voxelSize)) || any(voxelSize == 0)
        voxelSize = [1 1 1];
    end
end

function surface = roastLabelSurface(maskFile, opts)
    logMsg(opts, 'Reading ROAST label mask: %s', maskFile);
    [Vmask, labels] = readLabelMask(maskFile);
    labels = clearBoundaryConnectedValue(labels, uint8(6));
    voxelSize = voxelSizesFromMat(Vmask.mat);
    warnIfSolidHeadTouchesBoundary(labels, maskFile);

    headMask = labels > 0;
    if ~any(headMask(:))
        error('acsMakeRoastCapMakerLayout:EmptyHeadMask', ...
            'No head labels were found in %s.', maskFile);
    end

    logMsg(opts, 'Extracting ROAST outer head surface point cloud.');
    surfaceVox = mask2EdgePointCloud(uint8(headMask), 'erode', ones(3, 3, 3));
    if isempty(surfaceVox)
        error('acsMakeRoastCapMakerLayout:EmptySurface', ...
            'Could not extract a surface point cloud from %s.', maskFile);
    end

    surface = struct();
    surface.Vmask = Vmask;
    surface.labels = labels;
    surface.voxelSize = voxelSize;
    surface.headMask = headMask;
    surface.surfaceVox = double(surfaceVox);
    surface.surfaceMm = bsxfun(@times, double(surfaceVox), voxelSize);
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

function layout = makeLayoutFromRoastLabels(labelSurface, targetOpts, opts)
    [layoutPointsMm, capRows, layoutInfo] = makeLayoutFrame( ...
        labelSurface.surfaceVox, labelSurface.voxelSize, opts.capFraction);

    logMsg(opts, 'Running capMaker autoElectrodeTargets on ROAST outer surface for %d electrodes.', ...
        opts.nElectrodes);
    [layoutTargetsMm, nearestInd, targetInfo] = runAutoTargets(layoutPointsMm, ...
        opts.nElectrodes, targetOpts, opts.rngSeed);

    nearestInd = nearestInd(:);
    selectedSurfaceRows = capRows(nearestInd);
    targetVox = double(labelSurface.surfaceVox(selectedSurfaceRows, :));
    targetMm = bsxfun(@times, targetVox, labelSurface.voxelSize);

    layoutInfo.source = 'roastLabels';
    layoutInfo.layoutPointBounds = pointBounds(layoutPointsMm);
    if isfield(targetInfo, 'ellipseCurve')
        layoutInfo.ellipseBounds = pointBounds(targetInfo.ellipseCurve);
    end
    layout = struct();
    layout.targetVox = targetVox;
    layout.targetMm = targetMm;
    layout.layoutPointsMm = layoutPointsMm;
    layout.layoutTargetsMm = layoutTargetsMm;
    layout.layoutInfo = layoutInfo;
    layout.targetInfo = targetInfo;
end

function layout = makeLayoutFromCapMaker(labelSurface, roastSource, t1File, targetOpts, opts)
    subjectId = resolveSubjectId(roastSource, opts);
    opts.t1Orientation = resolveT1Orientation(roastSource, opts);
    [TRskin, skinMeta, skinInfo] = loadOrMakeCapMakerSkinMesh(subjectId, t1File, opts);

    if isfield(targetOpts, 'manualTargetsMm') && ...
            ~isempty(targetOpts.manualTargetsMm)
        [layoutTargetsMm, nearestInd, targetInfo] = manualCapMakerTargets( ...
            TRskin, targetOpts.manualTargetsMm, opts.nElectrodes);
        logMsg(opts, 'Using %d explicit capMaker print-frame electrode targets.', ...
            opts.nElectrodes);
    else
        [targetOpts, earExclusions] = acsApplyEarExclusionsToTargetOptions(targetOpts, skinInfo.cacheFile, ...
            'editMode', opts.earExclusionMode, ...
            'outputFile', opts.earExclusionFile, ...
            'showFigures', opts.showFigures, ...
            'saveFigures', opts.saveFigures, ...
            'showStrapPreview', ~strcmp(opts.strapExclusionMode, 'none'), ...
            'zBedMm', opts.zBedMm, ...
            'strapRostralOffsetMm', opts.strapRostralOffsetMm, ...
            'strapWidthMm', opts.strapWidthMm, ...
            'holderOutsideDiaMm', opts.holderOutsideDiaMm, ...
            'strapMarginMm', opts.strapMarginMm, ...
            'strapExclusionRadiusMm', opts.strapExclusionRadiusMm, ...
            'strapLateralLengthMm', opts.strapLateralLengthMm, ...
            'strapSampleSpacingMm', opts.strapSampleSpacingMm, ...
            'verbose', opts.verbose);
        targetOpts = acsAddStrapExclusionsToTargetOptions(targetOpts, earExclusions, ...
            'mode', opts.strapExclusionMode, ...
            'zBedMm', opts.zBedMm, ...
            'strapRostralOffsetMm', opts.strapRostralOffsetMm, ...
            'strapWidthMm', opts.strapWidthMm, ...
            'holderOutsideDiaMm', opts.holderOutsideDiaMm, ...
            'strapMarginMm', opts.strapMarginMm, ...
            'strapExclusionRadiusMm', opts.strapExclusionRadiusMm, ...
            'strapLateralLengthMm', opts.strapLateralLengthMm, ...
            'strapSampleSpacingMm', opts.strapSampleSpacingMm, ...
            'verbose', opts.verbose);
        logMsg(opts, 'Running capMaker autoElectrodeTargets on capMaker scalp mesh for %d electrodes.', ...
            opts.nElectrodes);
        [layoutTargetsMm, nearestInd, targetInfo] = runAutoTargets(TRskin, ...
            opts.nElectrodes, targetOpts, opts.rngSeed);
    end

    [targetVox, transformInfo] = capMakerTargetsToRoastVoxels( ...
        layoutTargetsMm, TRskin.Points, skinMeta, labelSurface, opts);
    if isfield(transformInfo, 'capMakerVoxelOrientation')
        logMsg(opts, 'capMaker pre-crop voxel orientation: %s (%s)', ...
            transformInfo.capMakerVoxelOrientation, ...
            transformInfo.capMakerVoxelOrientationSource);
    else
        logMsg(opts, 'capMaker-to-ROAST metadata transform unavailable; used fallback projection.');
    end
    targetMm = bsxfun(@times, targetVox, labelSurface.voxelSize);

    layoutInfo = struct();
    layoutInfo.source = 'capMaker';
    layoutInfo.subjectId = subjectId;
    layoutInfo.skin = skinInfo;
    layoutInfo.transform = transformInfo;
    layoutInfo.selectedSkinVertex = nearestInd(:);
    layoutInfo.capPointCount = size(TRskin.Points, 1);
    layoutInfo.layoutPointBounds = pointBounds(TRskin.Points);
    if isfield(targetInfo, 'ellipseCurve')
        layoutInfo.ellipseBounds = pointBounds(targetInfo.ellipseCurve);
    end

    layout = struct();
    layout.targetVox = targetVox;
    layout.targetMm = targetMm;
    layout.layoutPointsMm = TRskin.Points;
    layout.layoutTargetsMm = layoutTargetsMm;
    layout.layoutInfo = layoutInfo;
    layout.targetInfo = targetInfo;
end

function subjectId = resolveSubjectId(roastSource, opts)
    subjectId = strtrim(opts.subjectId);
    if ~isempty(subjectId)
        return;
    end
    if isstruct(roastSource)
        if isfield(roastSource, 'subjectId') && ~isempty(roastSource.subjectId)
            subjectId = char(roastSource.subjectId);
            return;
        end
        if isfield(roastSource, 'originalSubjectId') && ~isempty(roastSource.originalSubjectId)
            subjectId = char(roastSource.originalSubjectId);
            return;
        end
    end
    subjectId = 'M2107';
end

function [TRskin, meta, info] = loadOrMakeCapMakerSkinMesh(subjectId, t1File, opts)
    [capInput, inputKind] = resolveCapMakerInput(subjectId, t1File, opts);
    capWorkDir = acsSubjectPath(subjectId, 'capWork');
    cropPlaneFile = resolveCropPlaneFile(capWorkDir, capInput, inputKind, opts);
    [skinOpts, cropPlane] = resolveCropPlaneOptions( ...
        opts.skinMeshOptions, cropPlaneFile, capInput, inputKind, opts);

    cacheFile = opts.skinCacheFile;
    explicitSkinCacheFile = ~isempty(cacheFile);
    if isempty(cacheFile)
        cacheFile = defaultSkinCacheFile(capWorkDir, capInput, inputKind);
    end

    needsInteractiveCrop = strcmp(opts.cropPlaneMode, 'select') || ...
        (strcmp(opts.cropPlaneMode, 'autoSelect') && exist(cropPlaneFile, 'file') ~= 2);
    useCachedMesh = ~opts.forceSkinMesh && ...
        ~needsInteractiveCrop && ...
        exist(cacheFile, 'file') == 2;
    if useCachedMesh
        logMsg(opts, 'Loading capMaker scalp mesh cache: %s', cacheFile);
        S = load(cacheFile);
        TRskin = S.TRskin;
        meta = S.meta;
        if explicitSkinCacheFile
            useCachedMesh = true;
            cropPlane = cropPlaneFromLoadedSkinCache(meta, cropPlane);
        else
            useCachedMesh = cachedMeshMatchesCropPlane(meta, cropPlane);
        end
        cacheRejectReason = '';
        if ~useCachedMesh
            cacheRejectReason = 'does not match selected crop plane';
        end
        if useCachedMesh && ~cachedMeshHasFullHead(S, meta)
            useCachedMesh = false;
            cacheRejectReason = 'lacks full-head fiducial mesh';
        end
        if ~useCachedMesh
            logMsg(opts, 'Cached capMaker scalp mesh %s; recomputing.', ...
                cacheRejectReason);
        end
    end

    if useCachedMesh
        didCompute = false;
    else
        if exist('skinMeshFromMPRAGE', 'file') ~= 2
            error('acsMakeRoastCapMakerLayout:MissingSkinMeshFromMPRAGE', ...
                'capMaker core function skinMeshFromMPRAGE was not found on the MATLAB path.');
        end
        logMsg(opts, 'Computing capMaker scalp mesh from %s: %s', inputKind, capInput);
        skinOpts = capMakerSkinOptions(skinOpts, inputKind);
        if ~isfield(skinOpts, 'viz') || isempty(skinOpts.viz)
            skinOpts.viz = opts.showFigures;
        end
        [TRskin, meta] = skinMeshFromMPRAGE(capInput, skinOpts);
        if needsInteractiveCrop
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
        if ~isempty(TRfiducialHead) || ~isempty(TRstableHead)
            save(cacheFile, 'TRskin', 'TRfiducialHead', 'TRstableHead', ...
                'meta', '-v7.3');
        else
            save(cacheFile, 'TRskin', 'meta', '-v7.3');
        end
        didCompute = true;
    end

    info = struct();
    info.cacheFile = cacheFile;
    info.inputFile = capInput;
    info.inputKind = inputKind;
    info.cropPlaneMode = opts.cropPlaneMode;
    info.cropPlaneFile = cropPlaneFile;
    info.cropPlane = cropPlane;
    info.didCompute = didCompute;
    info.pointCount = size(TRskin.Points, 1);
end

function tf = cachedMeshHasFullHead(S, meta)
    if isfield(S, 'TRfiducialHead') && ~isempty(S.TRfiducialHead)
        tf = true;
        return;
    end
    tf = isstruct(meta) && isfield(meta, 'fiducialHead') && ...
        isstruct(meta.fiducialHead) && ...
        isfield(meta.fiducialHead, 'TR') && ...
        ~isempty(meta.fiducialHead.TR);
end

function fileName = defaultSkinCacheFile(capWorkDir, capInput, inputKind)
    stem = capMakerInputStem(capInput, inputKind);
    fileName = fullfile(capWorkDir, [stem '_skinMesh.mat']);
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
        case {'auto', 'reuse', 'autoSelect'}
            if exist(cropPlaneFile, 'file') == 2
                cropPlane = loadCropPlane(cropPlaneFile);
                validateCropPlaneInput(cropPlane, capInput, inputKind, cropPlaneFile);
                skinOpts = applyCropPlaneToSkinOptions(skinOpts, cropPlane);
                logMsg(opts, 'Reusing saved capMaker crop plane: %s', cropPlaneFile);
            elseif strcmp(opts.cropPlaneMode, 'reuse')
                error('acsMakeRoastCapMakerLayout:CropPlaneNotFound', ...
                    'Saved capMaker crop plane not found: %s', cropPlaneFile);
            elseif strcmp(opts.cropPlaneMode, 'autoSelect')
                skinOpts.interactiveCrop = true;
            end
        case 'default'
            % Keep skinMeshFromMPRAGE defaults or caller-supplied options.
        otherwise
            error('acsMakeRoastCapMakerLayout:BadCropPlaneMode', ...
                'Unknown cropPlaneMode "%s".', opts.cropPlaneMode);
    end
end

function cropPlane = loadCropPlane(fileName)
    S = load(fileName, 'cropPlane');
    if ~isfield(S, 'cropPlane') || ~isstruct(S.cropPlane)
        error('acsMakeRoastCapMakerLayout:BadCropPlaneFile', ...
            'Crop-plane file does not contain a cropPlane struct: %s', fileName);
    end
    cropPlane = S.cropPlane;
    validateCropPlane(cropPlane, fileName);
end

function saveCropPlane(fileName, cropPlane)
    validateCropPlane(cropPlane, fileName);
    ensureDir(fileparts(fileName));
    save(fileName, 'cropPlane');
    writeJsonReport([fileName(1:end - 4) '.json'], cropPlane);
end

function cropPlane = cropPlaneFromSkinMeta(meta, capInput, inputKind)
    if ~isstruct(meta) || ~isfield(meta, 'align') || ...
            ~isfield(meta.align, 'dir') || ~isfield(meta.align, 'distance')
        error('acsMakeRoastCapMakerLayout:MissingCropPlaneMeta', ...
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

function cropPlane = cropPlaneFromLoadedSkinCache(meta, fallbackCropPlane)
    cropPlane = fallbackCropPlane;
    if ~isstruct(meta) || ~isfield(meta, 'align') || ~isstruct(meta.align) || ...
            ~isfield(meta.align, 'dir') || ~isfield(meta.align, 'distance') || ...
            ~isfield(meta.align, 'side')
        return;
    end

    cropPlane = struct();
    cropPlane.createdOn = char(datetime('now'));
    cropPlane.inputFile = '';
    cropPlane.inputKind = 'skinCache';
    cropPlane.cropAxis = double(meta.align.dir(:)');
    cropPlane.cropDistance = double(meta.align.distance);
    cropPlane.cropSide = char(meta.align.side);
    if isfield(meta.align, 'used')
        cropPlane.alignCrop = logical(meta.align.used);
    else
        cropPlane.alignCrop = true;
    end
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
            error('acsMakeRoastCapMakerLayout:BadCropPlaneFile', ...
                'Crop-plane file is missing "%s": %s', required{i}, fileName);
        end
    end
    validateattributes(cropPlane.cropAxis, {'numeric'}, ...
        {'vector', 'numel', 3, 'real', 'finite'});
    validateattributes(cropPlane.cropDistance, {'numeric'}, ...
        {'scalar', 'real', 'finite'});
    if ~any(strcmpi(char(cropPlane.cropSide), {'top', 'bottom'}))
        error('acsMakeRoastCapMakerLayout:BadCropPlaneFile', ...
            'cropSide must be ''top'' or ''bottom'': %s', fileName);
    end
end

function validateCropPlaneInput(cropPlane, capInput, inputKind, fileName)
    if isfield(cropPlane, 'inputKind') && ...
            ~strcmpi(char(cropPlane.inputKind), inputKind)
        error('acsMakeRoastCapMakerLayout:CropPlaneInputMismatch', ...
            'Saved crop plane input kind does not match current capMaker input: %s', fileName);
    end
    if isfield(cropPlane, 'inputFile') && ...
            ~strcmpi(canonicalPath(cropPlane.inputFile), canonicalPath(capInput))
        error('acsMakeRoastCapMakerLayout:CropPlaneInputMismatch', ...
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

function [capInput, inputKind] = resolveCapMakerInput(subjectId, t1File, opts)
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
    inputKind = 'nifti';
end

function kind = inferCapMakerInputKind(pathIn)
    if exist(pathIn, 'dir') == 7
        kind = 'dicom';
        return;
    end
    lowerPath = lower(char(pathIn));
    if endsWith(lowerPath, '.nii') || endsWith(lowerPath, '.nii.gz')
        kind = 'nifti';
        return;
    end
    kind = 'dicom';
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

function [targetVox, info] = capMakerTargetsToRoastVoxels(targetsPrint, scalpPrint, skinMeta, labelSurface, opts)
    info = struct();
    info.method = 'capMakerMetaToRoastVoxelThenSnap';
    info.usedFallback = false;

    try
        orientationInfo = resolveCapMakerVoxelOrientation(skinMeta, opts);
        targetCapVoxel0 = capMakerPrintToCapVoxel(targetsPrint, skinMeta);
        scalpSamplePrint = samplePointMatrix(scalpPrint, opts.transformSearchMaxPoints);
        scalpCapVoxel0 = capMakerPrintToCapVoxel(scalpSamplePrint, skinMeta);

        [selectedCode, searchInfo] = chooseCapMakerOrientation( ...
            targetCapVoxel0, scalpCapVoxel0, orientationInfo, labelSurface, opts);
        targetVoxEstimate = orientVoxelPointsToRas(targetCapVoxel0, selectedCode, ...
            skinMeta.original.size, skinMeta.original.voxelSize, labelSurface.voxelSize);
        outside = pointsOutsideVolume(targetVoxEstimate, labelSurface.Vmask.dim(1:3));
        info.estimatedVoxelCoordinates = targetVoxEstimate;
        info.t1Orientation = orientationInfo.t1Orientation;
        info.capMakerVoxelOrientation = selectedCode;
        info.capMakerVoxelOrientationSource = orientationInfo.source;
        info.capMakerVoxelOrientationDerived = orientationInfo.capMakerVoxelOrientation;
        info.capMakerPermuteDims = orientationInfo.permuteDims;
        info.capMakerFlipDims = orientationInfo.flipDims;
        info.transformMode = opts.capMakerTransformMode;
        info.orientationSearch = searchInfo;
        info.outsideEstimateCount = nnz(outside);
        if nnz(outside) > floor(size(targetVoxEstimate, 1) / 2)
            error('acsMakeRoastCapMakerLayout:ManyTargetsOutside', ...
                'Most transformed capMaker targets fell outside the ROAST volume.');
        end
        [dist, idx] = map2Points(targetVoxEstimate, labelSurface.surfaceVox, 'closest');
        targetVox = double(labelSurface.surfaceVox(idx(:), :));
        info.snapDistanceVox = double(dist(:));
        warnIfLargeSnapDistance(info.snapDistanceVox, opts);
    catch ME
        warning('acsMakeRoastCapMakerLayout:CapMakerTransformFallback', ...
            ['Could not use capMaker metadata transform (%s). Falling back ', ...
             'to centered layout-frame projection.'], ME.message);
        [targetVox, fallbackInfo] = capMakerTargetsToRoastByLayoutFrame( ...
            targetsPrint, labelSurface, opts);
        info.usedFallback = true;
        info.fallback = fallbackInfo;
    end
end

function capVoxel0 = capMakerPrintToCapVoxel(pointsPrint, skinMeta)
    requireSkinMetaField(skinMeta, 'print');
    requireSkinMetaField(skinMeta, 'align');
    requireSkinMetaField(skinMeta, 'original');
    if ~isfield(skinMeta.print, 'T_print2world') || ...
            ~isfield(skinMeta.align, 'R') || ...
            ~isfield(skinMeta.original, 'vox2world') || ...
            ~isfield(skinMeta.original, 'voxelSize') || ...
            ~isfield(skinMeta.original, 'size')
        error('acsMakeRoastCapMakerLayout:IncompleteSkinMeta', ...
            'The capMaker skin mesh metadata is missing transform fields.');
    end

    finalWorld = applyAffineToPoints(skinMeta.print.T_print2world, pointsPrint);
    dicomWorld = (skinMeta.align.R \ finalWorld')';
    capVoxel0 = applyAffineToPoints(inv(skinMeta.original.vox2world), dicomWorld);
end

function requireSkinMetaField(S, fieldName)
    if ~isstruct(S) || ~isfield(S, fieldName)
        error('acsMakeRoastCapMakerLayout:IncompleteSkinMeta', ...
            'The capMaker skin mesh metadata is missing "%s".', fieldName);
    end
end

function rasVoxel1 = orientVoxelPointsToRas(voxel0, orientationCode, dims, srcVoxelSize, dstVoxelSize)
    orientationCode = validateOrientationCode(orientationCode);
    dims = double(dims(:)');
    srcVoxelSize = double(srcVoxelSize(:)');
    dstVoxelSize = double(dstVoxelSize(:)');

    targets = 'ras';
    opposites = 'lpi';
    rasMm = zeros(size(voxel0));
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

function [selectedCode, searchInfo] = chooseCapMakerOrientation( ...
        targetCapVoxel0, scalpCapVoxel0, orientationInfo, labelSurface, opts)
    derivedCode = orientationInfo.capMakerVoxelOrientation;
    searchInfo = struct();
    searchInfo.didSearch = false;
    searchInfo.derivedCode = derivedCode;
    searchInfo.selectedCode = derivedCode;

    if strcmp(opts.capMakerTransformMode, 'metadata') || ...
            ~strcmpi(opts.capMakerVoxelOrientation, 'auto')
        selectedCode = derivedCode;
        return;
    end

    candidates = candidateOrientationCodes(derivedCode);
    scores = repmat(struct( ...
        'code', '', ...
        'medianDistanceVox', Inf, ...
        'p95DistanceVox', Inf, ...
        'maxDistanceVox', Inf, ...
        'outsideFraction', Inf, ...
        'score', Inf), numel(candidates), 1);

    for i = 1:numel(candidates)
        estimate = orientVoxelPointsToRas(scalpCapVoxel0, candidates{i}, ...
            labelSafeDims(orientationInfo), ...
            labelSafeVoxelSize(orientationInfo), ...
            labelSurface.voxelSize);
        outside = pointsOutsideVolume(estimate, labelSurface.Vmask.dim(1:3));
        [dist, ~] = map2Points(estimate, labelSurface.surfaceVox, 'closest');
        dist = double(dist(:));
        outsideFraction = nnz(outside) / max(1, numel(outside));
        scores(i).code = candidates{i};
        scores(i).medianDistanceVox = median(dist);
        scores(i).p95DistanceVox = prctile(dist, 95);
        scores(i).maxDistanceVox = max(dist);
        scores(i).outsideFraction = outsideFraction;
        scores(i).score = scores(i).medianDistanceVox + ...
            0.25 * scores(i).p95DistanceVox + 1000 * outsideFraction;
    end

    [~, bestInd] = min([scores.score]);
    selectedCode = scores(bestInd).code;
    searchInfo.didSearch = true;
    searchInfo.selectedCode = selectedCode;
    searchInfo.scores = scores;

    targetEstimate = orientVoxelPointsToRas(targetCapVoxel0, selectedCode, ...
        labelSafeDims(orientationInfo), ...
        labelSafeVoxelSize(orientationInfo), ...
        labelSurface.voxelSize);
    [targetDist, ~] = map2Points(targetEstimate, labelSurface.surfaceVox, 'closest');
    searchInfo.selectedTargetSnapDistanceVox = double(targetDist(:));
end

function dims = labelSafeDims(info)
    dims = info.size;
end

function voxelSize = labelSafeVoxelSize(info)
    voxelSize = info.voxelSize;
end

function t1Orientation = resolveT1Orientation(roastSource, opts)
    if ~strcmpi(opts.t1Orientation, 'auto')
        t1Orientation = validateOrientationCode(opts.t1Orientation);
        return;
    end

    t1Orientation = '';
    if isstruct(roastSource) && isfield(roastSource, 'inputOrientations') && ...
            isstruct(roastSource.inputOrientations) && ...
            isfield(roastSource.inputOrientations, 't1')
        t1Orientation = char(roastSource.inputOrientations.t1);
    end

    if isempty(t1Orientation)
        t1Orientation = 'sar';
    end
    t1Orientation = validateOrientationCode(t1Orientation);
end

function info = resolveCapMakerVoxelOrientation(skinMeta, opts)
    info = struct();
    info.t1Orientation = validateOrientationCode(opts.t1Orientation);
    info.permuteDims = opts.capMakerPermuteDims;
    info.flipDims = opts.capMakerFlipDims;
    info.size = skinMeta.original.size;
    info.voxelSize = skinMeta.original.voxelSize;

    if isfield(skinMeta, 'original')
        if isfield(skinMeta.original, 'orientation') && ~isempty(skinMeta.original.orientation)
            info.t1Orientation = validateOrientationCode(skinMeta.original.orientation);
        end
        if isfield(skinMeta.original, 'permuteDims') && ~isempty(skinMeta.original.permuteDims)
            info.permuteDims = validatePermuteDims(skinMeta.original.permuteDims);
        end
        if isfield(skinMeta.original, 'flipDims') && ~isempty(skinMeta.original.flipDims)
            info.flipDims = validateFlipDims(skinMeta.original.flipDims);
        end
    end

    if strcmpi(opts.capMakerVoxelOrientation, 'auto')
        info.capMakerVoxelOrientation = transformOrientationCode( ...
            info.t1Orientation, info.permuteDims, info.flipDims);
        info.source = 'autoFromT1AndCapMakerPermuteFlip';
    else
        info.capMakerVoxelOrientation = validateOrientationCode(opts.capMakerVoxelOrientation);
        info.source = 'explicitCapMakerVoxelOrientation';
    end
end

function modes = normalizeTransformMode(modeIn)
    mode = lower(strtrim(char(modeIn)));
    switch mode
        case {'metadata', 'direct', 'deterministic'}
            modes = 'metadata';
        case {'autosearch', 'search', 'diagnostic'}
            modes = 'autoSearch';
        otherwise
            error('acsMakeRoastCapMakerLayout:BadTransformMode', ...
                'capMakerTransformMode must be ''metadata'' or ''autoSearch''.');
    end
end

function mode = normalizeCropPlaneMode(modeIn)
    mode = lower(strtrim(char(modeIn)));
    switch mode
        case {'auto', 'select', 'reuse', 'default'}
            % Accepted as-is.
        case {'autoselect', 'promptifmissing', 'selectifmissing'}
            mode = 'autoSelect';
        otherwise
            error('acsMakeRoastCapMakerLayout:BadCropPlaneMode', ...
                ['cropPlaneMode must be ''autoSelect'', ''auto'', ', ...
                 '''select'', ''reuse'', or ''default''.']);
    end
end

function mode = normalizeEarExclusionMode(modeIn)
    mode = lower(strtrim(char(modeIn)));
    switch mode
        case {'auto', 'always', 'never'}
            % Accepted as-is.
        case {'reuse', 'load'}
            mode = 'never';
        case {'select', 'edit'}
            mode = 'always';
        otherwise
            error('acsMakeRoastCapMakerLayout:BadEarExclusionMode', ...
                'earExclusionMode must be ''auto'', ''always'', or ''never''.');
    end
end

function mode = normalizeStrapExclusionMode(modeIn)
    mode = lower(strtrim(char(modeIn)));
    switch mode
        case {'auto', 'always', 'none'}
            % Accepted as-is.
        case {'off', 'never', 'ignore'}
            mode = 'none';
        case {'on', 'yes'}
            mode = 'auto';
        otherwise
            error('acsMakeRoastCapMakerLayout:BadStrapExclusionMode', ...
                'strapExclusionMode must be ''auto'', ''always'', or ''none''.');
    end
end

function codes = candidateOrientationCodes(preferredCode)
    preferredCode = validateOrientationCode(preferredCode);
    pos = 'ras';
    neg = 'lpi';
    axisOrders = perms(1:3);
    codes = cell(0, 1);
    for i = 1:size(axisOrders, 1)
        order = axisOrders(i, :);
        for signMask = 0:7
            code = repmat(' ', 1, 3);
            for dim = 1:3
                axisClass = order(dim);
                if bitget(signMask, dim)
                    code(dim) = neg(axisClass);
                else
                    code(dim) = pos(axisClass);
                end
            end
            codes{end + 1, 1} = code; %#ok<AGROW>
        end
    end
    codes = unique([{preferredCode}; codes], 'stable');
end

function pointsOut = samplePointMatrix(pointsIn, maxRows)
    pointsIn = double(pointsIn);
    if size(pointsIn, 1) <= maxRows
        pointsOut = pointsIn;
        return;
    end
    rows = unique(round(linspace(1, size(pointsIn, 1), maxRows)));
    pointsOut = pointsIn(rows, :);
end

function warnIfLargeSnapDistance(distVox, opts)
    if isempty(opts.snapDistanceWarnVox) || isempty(distVox)
        return;
    end
    maxDist = max(distVox(:));
    if maxDist <= opts.snapDistanceWarnVox
        return;
    end
    warning('acsMakeRoastCapMakerLayout:LargeSnapDistance', ...
        ['At least one custom electrode moved %.2f voxels while snapping ', ...
         'to the ROAST scalp surface (median %.2f voxels; threshold %.2f). ', ...
         'This usually indicates a capMaker-to-ROAST coordinate transform problem.'], ...
        maxDist, median(distVox(:)), opts.snapDistanceWarnVox);
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
            error('acsMakeRoastCapMakerLayout:BadOrientationCode', ...
                'Unknown orientation code "%s".', code);
    end
end

function request = normalizeOrientationRequest(request)
    request = lower(strtrim(char(request)));
    if strcmp(request, 'auto')
        return;
    end
    request = validateOrientationCode(request);
end

function code = validateOrientationCode(code)
    code = lower(strtrim(char(code)));
    code = regexprep(code, '[\s,;:_-]+', '');
    if numel(code) ~= 3
        error('acsMakeRoastCapMakerLayout:BadOrientationCode', ...
            'Orientation code must have exactly three characters.');
    end
    if any(~ismember(code, 'rlapsi'))
        error('acsMakeRoastCapMakerLayout:BadOrientationCode', ...
            'Orientation codes can only use r, l, a, p, s, and i.');
    end

    classes = cell(1, 3);
    for i = 1:3
        classes{i} = orientationClass(code(i));
    end
    expected = {'left-right', 'anterior-posterior', 'superior-inferior'};
    for i = 1:numel(expected)
        if sum(strcmp(classes, expected{i})) ~= 1
            error('acsMakeRoastCapMakerLayout:BadOrientationCode', ...
                'Use exactly one left/right, one anterior/posterior, and one superior/inferior direction.');
        end
    end
end

function permuteDims = validatePermuteDims(permuteDims)
    permuteDims = double(permuteDims(:)');
    if numel(permuteDims) ~= 3 || any(sort(permuteDims) ~= [1 2 3])
        error('acsMakeRoastCapMakerLayout:BadPermuteDims', ...
            'capMakerPermuteDims must be a permutation of [1 2 3].');
    end
end

function flipDims = validateFlipDims(flipDims)
    flipDims = logical(flipDims(:)');
    if numel(flipDims) ~= 3
        error('acsMakeRoastCapMakerLayout:BadFlipDims', ...
            'capMakerFlipDims must have three logical values.');
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
            error('acsMakeRoastCapMakerLayout:BadOrientationCode', ...
                'Unknown orientation code "%s".', code);
    end
end

function pointsOut = applyAffineToPoints(M, pointsIn)
    pointsHom = [double(pointsIn), ones(size(pointsIn, 1), 1)];
    pointsHom = (M * pointsHom')';
    pointsOut = pointsHom(:, 1:3);
end

function outside = pointsOutsideVolume(points, dims)
    dims = double(dims(:)');
    outside = any(points < 1, 2) | any(bsxfun(@gt, points, dims), 2);
end

function [targetVox, info] = capMakerTargetsToRoastByLayoutFrame(targetsPrint, labelSurface, opts)
    [layoutPointsMm, capRows, layoutInfo] = makeLayoutFrame( ...
        labelSurface.surfaceVox, labelSurface.voxelSize, opts.capFraction);
    [dist, idx] = map2Points(targetsPrint, layoutPointsMm, 'closest');
    selectedSurfaceRows = capRows(idx(:));
    targetVox = double(labelSurface.surfaceVox(selectedSurfaceRows, :));

    info = layoutInfo;
    info.method = 'centeredLayoutFrameNearest';
    info.snapDistanceMm = double(dist(:));
end

function [layoutPointsMm, capRows, info] = makeLayoutFrame(surfaceVox, voxelSize, capFraction)
    surfaceMm = bsxfun(@times, double(surfaceVox), voxelSize);
    superior = surfaceMm(:, 3);
    cutoff = prctile(superior, 100 * (1 - capFraction));
    keep = superior >= cutoff;
    capRows = find(keep);
    if numel(capRows) < 100
        error('acsMakeRoastCapMakerLayout:SparseCapSurface', ...
            'Only %d surface points remain after capFraction %.3f.', ...
            numel(capRows), capFraction);
    end

    layoutPointsMm = surfaceMm(capRows, :);
    xyCenter = 0.5 * (min(layoutPointsMm(:, 1:2), [], 1) + ...
        max(layoutPointsMm(:, 1:2), [], 1));
    zMin = min(layoutPointsMm(:, 3));
    layoutPointsMm(:, 1:2) = bsxfun(@minus, layoutPointsMm(:, 1:2), xyCenter);
    layoutPointsMm(:, 3) = layoutPointsMm(:, 3) - zMin;

    info = struct();
    info.capFraction = capFraction;
    info.superiorCutoffMm = cutoff;
    info.xyCenterMm = xyCenter;
    info.zMinMm = zMin;
    info.surfacePointCount = size(surfaceVox, 1);
    info.capPointCount = numel(capRows);
end

function bounds = pointBounds(points)
    bounds = struct();
    bounds.min = min(double(points), [], 1);
    bounds.max = max(double(points), [], 1);
end

function targetOpts = capMakerTargetOptions(userOpts)
    targetOpts = struct();
    targetOpts.placementMode = 'footprintCvt';
    % Legacy capMaker used a hard-coded headpost disk at [0 0]. The ROAST
    % integration should use explicit implant exclusion products instead.
    targetOpts.headpostCenter = [0 0];
    targetOpts.headpostRadius = 0;
    targetOpts.viz2D = false;
    targetOpts.viz3D = false;

    if nargin < 1 || isempty(userOpts)
        return;
    end
    fields = fieldnames(userOpts);
    for i = 1:numel(fields)
        targetOpts.(fields{i}) = userOpts.(fields{i});
    end
    if isfield(targetOpts, 'viz3D') && targetOpts.viz3D
        warning('acsMakeRoastCapMakerLayout:Viz3DDisabled', ...
            ['autoElectrodeTargets viz3D requires a triangulation. ', ...
             'Use acsMakeRoastCapMakerLayout showFigures instead.']);
        targetOpts.viz3D = false;
    end
end

function warnIfSolidHeadTouchesBoundary(labels, maskFile)
    boundary = false(size(labels));
    boundary(1, :, :) = true;
    boundary(end, :, :) = true;
    boundary(:, 1, :) = true;
    boundary(:, end, :) = true;
    boundary(:, :, 1) = true;
    boundary(:, :, end) = true;

    solidOnBoundary = nnz(labels(boundary) >= 1 & labels(boundary) <= 5);
    if solidOnBoundary > 0
        warning('acsMakeRoastCapMakerLayout:HeadTouchesBoundary', ...
            ['%s has solid head labels on the image boundary. If ROAST places ', ...
             'electrodes oddly, regenerate the anatomy/labels with more padding.'], ...
             maskFile);
    end
end

function [targets, nearestInd, infoOut] = manualCapMakerTargets(surface, ...
        manualTargetsMm, nElectrodes)
    targets = double(manualTargetsMm);
    if size(targets, 2) ~= 3 || size(targets, 1) ~= nElectrodes || ...
            any(~isfinite(targets(:)))
        error('acsMakeRoastCapMakerLayout:BadManualTargets', ...
            ['targetOptions.manualTargetsMm must be an nElectrodes x 3 ', ...
             'finite matrix in capMaker print-frame millimeters.']);
    end

    TRlayout = targetSurfaceAsStruct(surface);
    [distMm, nearestInd] = nearestPointRows(targets, TRlayout.Points);
    nearestInd = nearestInd(:);
    infoOut = struct();
    infoOut.placementMode = 'manualTargetsMm';
    infoOut.P2D = targets(:, 1:2);
    infoOut.manualTargetsMm = targets;
    infoOut.nearestSkinVertex = nearestInd;
    infoOut.snapDistanceMm = distMm(:);
end

function [targets, nearestInd, infoOut] = runAutoTargets(surface, nElectrodes, targetOpts, rngSeed)
    if exist('autoElectrodeTargets', 'file') ~= 2
        error('acsMakeRoastCapMakerLayout:MissingCapMaker', ...
            'capMaker geometry function autoElectrodeTargets was not found on the MATLAB path.');
    end

    if ~isempty(rngSeed)
        cleanup = setTemporaryRandomSeed(rngSeed); %#ok<NASGU>
    end

    TRlayout = targetSurfaceAsStruct(surface);
    [targets, nearestInd, infoOut] = autoElectrodeTargets(TRlayout, nElectrodes, targetOpts);
end

function [dist, idx] = nearestPointRows(queryPoints, referencePoints)
    queryPoints = double(queryPoints);
    referencePoints = double(referencePoints);
    idx = zeros(size(queryPoints, 1), 1);
    dist = zeros(size(queryPoints, 1), 1);
    for i = 1:size(queryPoints, 1)
        delta = bsxfun(@minus, referencePoints, queryPoints(i, :));
        d2 = sum(delta .^ 2, 2);
        [best, idx(i)] = min(d2);
        dist(i) = sqrt(best);
    end
end

function TRlayout = targetSurfaceAsStruct(surface)
    if isnumeric(surface)
        if size(surface, 2) ~= 3
            error('acsMakeRoastCapMakerLayout:BadSurfacePoints', ...
                'Numeric target surface must be an N x 3 point matrix.');
        end
        TRlayout = struct('Points', double(surface));
        return;
    end

    if isa(surface, 'triangulation')
        TRlayout = struct( ...
            'Points', double(surface.Points), ...
            'ConnectivityList', double(surface.ConnectivityList));
        return;
    end

    if isstruct(surface) && isfield(surface, 'Points')
        TRlayout = surface;
        TRlayout.Points = double(surface.Points);
        if isfield(surface, 'ConnectivityList')
            TRlayout.ConnectivityList = double(surface.ConnectivityList);
        end
        return;
    end

    error('acsMakeRoastCapMakerLayout:BadSurfaceInput', ...
        'Target surface must be a triangulation, struct with Points, or N x 3 matrix.');
end

function cleanup = setTemporaryRandomSeed(rngSeed)
    cleanup = [];
    seed = double(rngSeed);
    oldRng = [];
    oldRandState = [];

    try
        oldRng = rng;
    catch
        try
            oldRandState = rand('state'); %#ok<RAND>
        catch
        end
    end

    try
        rng(seed, 'twister');
    catch
        rand('state', seed); %#ok<RAND>
    end

    cleanup = onCleanup(@() restoreRandomState(oldRng, oldRandState));
end

function restoreRandomState(oldRng, oldRandState)
    if ~isempty(oldRng)
        try
            rng(oldRng);
            return;
        catch
        end
    end
    if ~isempty(oldRandState)
        try
            rand('state', oldRandState); %#ok<RAND>
        catch
        end
    end
end

function names = normalizeNameInput(names)
    if isempty(names)
        names = {};
    elseif ischar(names) || isstring(names)
        names = cellstr(string(names));
    elseif iscell(names)
        names = cellfun(@char, names(:), 'UniformOutput', false);
    else
        error('acsMakeRoastCapMakerLayout:BadElectrodeNames', ...
            'electrodeNames must be a cell array, char, or string array.');
    end
end

function names = normalizeElectrodeNames(names, nElectrodes)
    if isempty(names)
        names = arrayfun(@(i) sprintf('custom%d', i), 1:nElectrodes, ...
            'UniformOutput', false);
        return;
    end
    names = names(:)';
    if numel(names) ~= nElectrodes
        error('acsMakeRoastCapMakerLayout:NameCountMismatch', ...
            'Expected %d electrode names but got %d.', nElectrodes, numel(names));
    end
    for i = 1:numel(names)
        names{i} = strtrim(char(names{i}));
        if isempty(names{i})
            error('acsMakeRoastCapMakerLayout:EmptyElectrodeName', ...
                'Electrode names cannot be empty.');
        end
        if isempty(strfind(lower(names{i}), 'custom')) %#ok<STREMP>
            error('acsMakeRoastCapMakerLayout:NonCustomElectrodeName', ...
                'ROAST custom electrode names must contain "custom": %s', names{i});
        end
    end
end

function writeCustomLocations(fileName, names, coords)
    ensureDir(fileparts(fileName));
    fid = fopen(fileName, 'w');
    if fid == -1
        error('acsMakeRoastCapMakerLayout:CannotOpenOutput', ...
            'Could not open custom locations file for writing: %s', fileName);
    end
    cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
    for i = 1:numel(names)
        fprintf(fid, '%s %.6f %.6f %.6f\n', ...
            names{i}, coords(i, 1), coords(i, 2), coords(i, 3));
    end
end

function out = buildExistingReport(t1File, maskFile, opts)
    [names, coords] = readCustomLocations(opts.outputFile);
    out = struct();
    out.t1File = t1File;
    out.maskFile = maskFile;
    out.customLocationsFile = opts.outputFile;
    out.names = names(:);
    out.voxelCoordinates = coords;
    out.reusedExisting = true;
    out.recipeExample = recipeExample(names);
    out.roastCommandHint = roastCommandHint(t1File);
end

function [names, coords] = readCustomLocations(fileName)
    fid = fopen(fileName, 'r');
    if fid == -1
        error('acsMakeRoastCapMakerLayout:CannotReadCustomLocations', ...
            'Could not read custom locations file: %s', fileName);
    end
    cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
    C = textscan(fid, '%s %f %f %f');
    names = C{1};
    coords = [C{2}, C{3}, C{4}];
end

function out = buildReport(t1File, maskFile, Vmask, opts, names, targetVox, ...
        targetMm, layoutTargetsMm, layoutInfo, targetOpts, targetInfo, qcFiles)
    out = struct();
    out.createdOn = char(datetime('now'));
    out.t1File = t1File;
    out.maskFile = maskFile;
    out.customLocationsFile = opts.outputFile;
    out.names = names(:);
    out.voxelCoordinates = targetVox;
    out.scaledCoordinatesMm = targetMm;
    out.layoutCoordinatesMm = layoutTargetsMm;
    out.imageSize = Vmask.dim(1:3);
    out.voxelSize = voxelSizesFromMat(Vmask.mat);
    out.layout = layoutInfo;
    out.targetOptions = targetOpts;
    out.targetDiagnostics = compactTargetDiagnostics(targetInfo);
    out.qcFiles = qcFiles(:);
    out.reusedExisting = false;
    out.recipeExample = recipeExample(names);
    out.roastCommandHint = roastCommandHint(t1File);
    out.reportMat = reportMatFile(opts.outputFile);
    out.reportJson = reportJsonFile(opts.outputFile);
end

function diagnostics = compactTargetDiagnostics(targetInfo)
    diagnostics = targetInfo;
    heavyFields = {'region', 'regionR', 'headpostPoly', 'earPolys', ...
        'candidateVertex', 'eligibleMask', 'bottomVertexMask', ...
        'bottomFaceMask', 'rimSeeds', 'distRimMM', 'normalMask', ...
        'visibilityMask', 'exclusionMask', 'earExclusionMask', ...
        'headpostExclusionMask', 'customExclusionMask', 'meshEdges', ...
        'distMidlineMM', 'coverageVertex', 'coverageMask', ...
        'voronoiCellIndex', 'voronoiDistanceMM'};
    for i = 1:numel(heavyFields)
        if isfield(diagnostics, heavyFields{i})
            diagnostics = rmfield(diagnostics, heavyFields{i});
        end
    end
end

function recipe = recipeExample(names)
    if numel(names) < 2
        recipe = {};
        return;
    end
    recipe = {names{1}, 1, names{2}, -1};
end

function hint = roastCommandHint(t1File)
    hint = sprintf(['layout = acsMakeRoastCapMakerLayout(out, ''force'', true); ', ...
        'roast(''%s'', layout.recipeExample, ''resampling'', ''off'', ', ...
        '''simulationTag'', ''capMakerSmoke'')'], t1File);
end

function saveReport(out)
    reportMat = out.reportMat;
    reportJson = out.reportJson;
    if isfield(out, 'figure')
        out = rmfield(out, 'figure');
    end
    save(reportMat, 'out');
    writeJsonReport(reportJson, out);
end

function fileName = reportMatFile(customFile)
    fileName = [customFile '_report.mat'];
end

function fileName = reportJsonFile(customFile)
    fileName = [customFile '_report.json'];
end

function fig = makeLayoutQcFigure(layout, labelSurface, names, opts, figVisible)
    layoutPointsMm = layout.layoutPointsMm;
    layoutTargetsMm = layout.layoutTargetsMm;
    targetInfo = layout.targetInfo;
    fig = figure('Name', 'ROAST capMaker custom layout QC', 'Color', 'w', ...
        'Visible', figVisible, 'Units', 'pixels', 'Position', [100 100 1800 620]);
    annotation(fig, 'textbox', [0.04 0.93 0.92 0.05], ...
        'String', sprintf('ROAST custom electrode layout: %s', getFileName(opts.outputFile)), ...
        'Interpreter', 'none', 'HorizontalAlignment', 'center', ...
        'VerticalAlignment', 'middle', 'FontWeight', 'bold', ...
        'FontSize', 12, 'EdgeColor', 'none');

    ax1 = axes(fig, 'Position', [0.04 0.12 0.28 0.76]); %#ok<LAXES>
    hold(ax1, 'on');
    plot(ax1, layoutPointsMm(:, 1), layoutPointsMm(:, 2), '.', ...
        'Color', [0.78 0.78 0.78], 'MarkerSize', 2);
    if isfield(targetInfo, 'ellipseCurve')
        plot(ax1, targetInfo.ellipseCurve(:, 1), targetInfo.ellipseCurve(:, 2), ...
            'Color', [0.85 0.1 0.1], 'LineWidth', 1.2);
    end
    if isfield(targetInfo, 'P2D')
        scatter(ax1, targetInfo.P2D(:, 1), targetInfo.P2D(:, 2), ...
            55, 'k', 'filled');
        addPointLabels(ax1, targetInfo.P2D, names);
    end
    axis(ax1, 'equal');
    grid(ax1, 'on');
    xlabel(ax1, 'capMaker print X (mm)');
    ylabel(ax1, 'capMaker print Y (mm)');
    title(ax1, 'capMaker print-frame footprint');

    ax2 = axes(fig, 'Position', [0.37 0.12 0.27 0.76]); %#ok<LAXES>
    hold(ax2, 'on');
    sampleRows = samplePointRows(size(layoutPointsMm, 1), 25000);
    scatter3(ax2, layoutPointsMm(sampleRows, 1), layoutPointsMm(sampleRows, 2), ...
        layoutPointsMm(sampleRows, 3), 2, [0.75 0.75 0.75], 'filled');
    scatter3(ax2, layoutTargetsMm(:, 1), layoutTargetsMm(:, 2), ...
        layoutTargetsMm(:, 3), 70, [0.05 0.05 0.05], 'filled');
    addPointLabels3(ax2, layoutTargetsMm, names);
    axis(ax2, 'equal');
    grid(ax2, 'on');
    view(ax2, 35, 25);
    xlabel(ax2, 'capMaker print X (mm)');
    ylabel(ax2, 'capMaker print Y (mm)');
    zlabel(ax2, 'capMaker print Z (mm)');
    title(ax2, 'Selected capMaker scalp points');

    ax3 = axes(fig, 'Position', [0.70 0.12 0.27 0.76]); %#ok<LAXES>
    hold(ax3, 'on');
    roastSurfaceMm = labelSurface.surfaceMm;
    sampleRows = samplePointRows(size(roastSurfaceMm, 1), 25000);
    scatter3(ax3, roastSurfaceMm(sampleRows, 1), roastSurfaceMm(sampleRows, 2), ...
        roastSurfaceMm(sampleRows, 3), 2, [0.75 0.75 0.75], 'filled');
    scatter3(ax3, layout.targetMm(:, 1), layout.targetMm(:, 2), ...
        layout.targetMm(:, 3), 70, [0.02 0.25 0.9], 'filled');
    addPointLabels3(ax3, layout.targetMm, names);
    axis(ax3, 'equal');
    grid(ax3, 'on');
    view(ax3, 35, 25);
    xlabel(ax3, 'ROAST scaled voxel X (mm)');
    ylabel(ax3, 'ROAST scaled voxel Y (mm)');
    zlabel(ax3, 'ROAST scaled voxel Z (mm)');
    title(ax3, 'Written custom locations in ROAST frame');
end

function rows = samplePointRows(nRows, maxRows)
    if nRows <= maxRows
        rows = 1:nRows;
    else
        rows = unique(round(linspace(1, nRows, maxRows)));
    end
end

function addPointLabels(ax, points, names)
    for i = 1:size(points, 1)
        text(ax, points(i, 1), points(i, 2), ['  ' names{i}], ...
            'Interpreter', 'none', 'FontSize', 8, 'Color', [0.05 0.05 0.05]);
    end
end

function addPointLabels3(ax, points, names)
    for i = 1:size(points, 1)
        text(ax, points(i, 1), points(i, 2), points(i, 3), ['  ' names{i}], ...
            'Interpreter', 'none', 'FontSize', 8, 'Color', [0.05 0.05 0.05]);
    end
end

function saveQcFigure(fig, qcFile)
    try
        exportgraphics(fig, qcFile, 'Resolution', 150);
    catch
        saveas(fig, qcFile);
    end
end

function writeJsonReport(reportJson, report)
    fid = fopen(reportJson, 'w');
    if fid == -1
        warning('acsMakeRoastCapMakerLayout:CannotWriteJson', ...
            'Could not write JSON report: %s', reportJson);
        return;
    end
    cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
    try
        fprintf(fid, '%s', jsonencode(report, 'PrettyPrint', true));
    catch
        fprintf(fid, '%s', jsonencode(report));
    end
end

function ensureDir(pathIn)
    if isempty(pathIn)
        return;
    end
    if exist(pathIn, 'dir') ~= 7
        mkdir(pathIn);
    end
end

function name = getFileName(filePath)
    [~, name, ext] = fileparts(filePath);
    name = [name ext];
end

function p = expandUserPath(p)
    p = char(p);
    if isempty(p)
        return;
    end
    if startsWith(p, '~')
        homeDir = getenv('USERPROFILE');
        if isempty(homeDir)
            homeDir = getenv('HOME');
        end
        p = fullfile(homeDir, extractAfter(p, 1));
    end
end

function p = canonicalPath(p)
    p = expandUserPath(p);
    if isempty(p)
        return;
    end
    try
        p = char(java.io.File(p).getCanonicalPath());
    catch
        p = char(p);
    end
end

function logMsg(opts, varargin)
    if opts.verbose
        fprintf([varargin{1} '\n'], varargin{2:end});
    end
end
