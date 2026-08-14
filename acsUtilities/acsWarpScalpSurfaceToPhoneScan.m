function out = acsWarpScalpSurfaceToPhoneScan(surfaceSource, phoneRegistrationIn, varargin)
% ACSWARPSCALPSURFACETOPHONESCAN Warp capMaker scalp surface toward a registered phone scan.
%
% out = acsWarpScalpSurfaceToPhoneScan(surfaceSource, phoneRegistration)
% extracts the registered phone/LiDAR head-scan mesh from
% acsRegisterPhoneScanToCapMakerFrame and passes a downsampled point cloud
% into acsWarpScalpSurfaceToPolhemusTrace. The phone scan acts like a dense
% scalp trace. Points near a finalized headpost placement can be removed
% before fitting, and distant remnants are rejected by the underlying
% maxTraceDistanceMm filter.
%
% surfaceSource should be the skin-cache product whose cap mesh you want to
% warp. The output is another skin-cache MAT that can be used by capMaker
% fit-check/manufacturing functions.
%
% Name-value options:
%   outputFile          : warped skin cache MAT ['']
%   outputTag           : output tag ['phoneScanWarp']
%   force               : overwrite existing products [false]
%   maxPhonePoints      : deterministic phone point subsample [35000]
%   traceSetName        : name recorded for phone point cloud ['phoneScanScalp']
%   headpostPlacementFile : finalized acsPlanHeadpostPlacement MAT ['']
%   phoneObjectExclusionFile : acsSelectPhoneScanObject output MAT ['']
%   excludePhoneObjectPoints : remove selected phone object points [true]
%   phoneObjectExclusionDistanceMm : object removal distance [4]
%   excludeHeadpostPoints : remove phone points near placed headpost [true]
%   headpostPointExclusionDistanceMm : headpost removal distance [15]
%   maxTraceDistanceMm  : reject phone points far from MRI surface [60]
%   maxInflationMm      : maximum outward warp [60]
%   displacementScale   : multiply accepted outward offsets [1]
%   normalOrientationMode : normal correction forwarded to surface warp ['autoRadial']
%   normalRadialFlipThreshold : radial-opposed fraction for autoRadial [0.02]
%   warpDirectionMode : displacement basis forwarded to surface warp ['blendRadial']
%   warpRadialBlendThreshold : normal/radial alignment threshold [0.35]
%   offsetProjectionMode : signed offset projection mode ['maxWarpRadial']
%   robustUpperPercentile : cap using trace offset percentile [99.8]
%   influenceRadiusMm   : warp influence radius [70]
%   influenceSigmaMm    : warp influence sigma [[] = radius/2]
%   coverageOffsetToleranceMm : near-zero scan points still count as coverage [0.5]
%   smoothingIterations : surface smoothing iterations [30]
%   smoothingBlend      : neighbor blend per smoothing iteration [0.45]
%   surfaceSmoothingIterations : post-warp Taubin mesh smoothing iterations [0]
%   surfaceSmoothingLambda : post-warp smoothing forward step [0.35]
%   surfaceSmoothingMu : post-warp smoothing reverse step [-0.37]
%   surfaceSmoothingPreserveBoundary : keep open-boundary vertices fixed [true]
%   dentRepairMode      : 'off', 'diagnose', or 'auto' ['off']
%   dentRepairMetric    : 'localLaplacian', 'radialEnvelope', or 'hybrid' ['localLaplacian']
%   dentRepairIterations : outward repair passes for local dents [2]
%   dentRepairRadiusMm  : neighborhood radius for local radial envelope [8]
%   dentRepairEnvelopePercentile : local radial envelope percentile [75]
%   dentRepairMinDentMm : minimum inward radial dent depth [2]
%   dentRepairNormalAngleDeg : normal roughness threshold for creases [35]
%   dentRepairLocalSmoothingIterations : local surface smoothing scale [3]
%   dentRepairDirectionRadialWeight : radial contribution to repair direction [0.25]
%   dentRepairBlend     : fraction of dent depth repaired per pass [0.85]
%   dentRepairMaxMoveMm : maximum repair move per vertex [8]
%   dentRepairMaxRings  : cap adjacency rings for neighborhood search [8]
%   dentRepairMaxFlaggedFraction : cap repaired vertices per pass [0.15]
%   dentRepairProtectBoundary : keep open-boundary vertices fixed [true]
%   seedWeight          : keep trace-constrained vertices near data [0.95]
%   seedAggregation     : per-vertex trace seed reducer ['median']
%   seedPercentile      : percentile for seedAggregation='percentile' [75]
%   interpK             : full-head-to-cap interpolation neighbors [6]
%   interpSigmaMm       : full-head-to-cap interpolation sigma [12]
%   makeRoastMask       : forward to acsWarpScalpSurfaceToPolhemusTrace [false]
%   roastMaskFile       : source ROAST hard-label mask ['']
%   roastMaskOutputFile : output warped hard-label mask ['']
%   roastT1File         : source ROAST T1 ['']
%   makeRoastT1Copy     : write copied T1 with matching warped stem [false]
%   roastSkinVoxelMode  : 'rasterSurfaceFill', 'closedSurfaceFill', 'surfaceNeighborhood', or 'sweptSegments' ['rasterSurfaceFill']
%   skinVoxelRadiusMm   : skin voxel marking radius around warp samples [0.8]
%   voxelSampleStepMm   : step along old-to-warped surface segments [0.5]
%   roastOverwriteLabels : labels allowed to become skin [[0 5 6]]
%   cleanupRoastSkinComponents : remove disconnected skin islands [true]
%   roastSkinCleanupMode : 'largest' or 'minSize' ['largest']
%   minRoastSkinComponentVoxels : min component size for minSize mode [1000]
%   showFigures         : show QC figure [true]
%   saveFigures         : save QC figure [true]
%   verbose             : print summary [true]

    if nargin < 1 || isempty(surfaceSource)
        error('acsWarpScalpSurfaceToPhoneScan:MissingSurface', ...
            'Provide a capMaker skin-cache surface source.');
    end
    if nargin < 2 || isempty(phoneRegistrationIn)
        error('acsWarpScalpSurfaceToPhoneScan:MissingPhoneRegistration', ...
            'Provide an acsRegisterPhoneScanToCapMakerFrame output or MAT file.');
    end

    opts = parseInputs(varargin{:});
    addLocalDependencies();

    phone = readRegisteredPhoneScan(phoneRegistrationIn, opts);
    [phone, phoneExclusion] = filterPhonePointsForWarp( ...
        phone, surfaceSource, opts);
    trace = makePhoneTrace(phone, opts);
    opts = resolveOutputFile(surfaceSource, phone, opts);

    warpArgs = { ...
        'traceSetName', opts.traceSetName, ...
        'outputFile', opts.outputFile, ...
        'outputTag', opts.outputTag, ...
        'force', opts.force, ...
        'inflateOnly', true, ...
        'maxTraceDistanceMm', opts.maxTraceDistanceMm, ...
        'maxInflationMm', opts.maxInflationMm, ...
        'displacementScale', opts.displacementScale, ...
        'normalOrientationMode', opts.normalOrientationMode, ...
        'normalRadialFlipThreshold', opts.normalRadialFlipThreshold, ...
        'warpDirectionMode', opts.warpDirectionMode, ...
        'warpRadialBlendThreshold', opts.warpRadialBlendThreshold, ...
        'offsetProjectionMode', opts.offsetProjectionMode, ...
        'robustUpperPercentile', opts.robustUpperPercentile, ...
        'influenceRadiusMm', opts.influenceRadiusMm, ...
        'influenceSigmaMm', opts.influenceSigmaMm, ...
        'coverageOffsetToleranceMm', opts.coverageOffsetToleranceMm, ...
        'smoothingIterations', opts.smoothingIterations, ...
        'smoothingBlend', opts.smoothingBlend, ...
        'surfaceSmoothingIterations', opts.surfaceSmoothingIterations, ...
        'surfaceSmoothingLambda', opts.surfaceSmoothingLambda, ...
        'surfaceSmoothingMu', opts.surfaceSmoothingMu, ...
        'surfaceSmoothingPreserveBoundary', ...
            opts.surfaceSmoothingPreserveBoundary, ...
        'dentRepairMode', opts.dentRepairMode, ...
        'dentRepairMetric', opts.dentRepairMetric, ...
        'dentRepairIterations', opts.dentRepairIterations, ...
        'dentRepairRadiusMm', opts.dentRepairRadiusMm, ...
        'dentRepairEnvelopePercentile', ...
            opts.dentRepairEnvelopePercentile, ...
        'dentRepairMinDentMm', opts.dentRepairMinDentMm, ...
        'dentRepairNormalAngleDeg', opts.dentRepairNormalAngleDeg, ...
        'dentRepairLocalSmoothingIterations', ...
            opts.dentRepairLocalSmoothingIterations, ...
        'dentRepairDirectionRadialWeight', ...
            opts.dentRepairDirectionRadialWeight, ...
        'dentRepairBlend', opts.dentRepairBlend, ...
        'dentRepairMaxMoveMm', opts.dentRepairMaxMoveMm, ...
        'dentRepairMaxRings', opts.dentRepairMaxRings, ...
        'dentRepairMaxFlaggedFraction', ...
            opts.dentRepairMaxFlaggedFraction, ...
        'dentRepairProtectBoundary', opts.dentRepairProtectBoundary, ...
        'seedWeight', opts.seedWeight, ...
        'seedAggregation', opts.seedAggregation, ...
        'seedPercentile', opts.seedPercentile, ...
        'interpK', opts.interpK, ...
        'interpSigmaMm', opts.interpSigmaMm, ...
        'makeRoastMask', opts.makeRoastMask, ...
        'roastMaskFile', opts.roastMaskFile, ...
        'roastMaskOutputFile', opts.roastMaskOutputFile, ...
        'roastT1File', opts.roastT1File, ...
        'makeRoastT1Copy', opts.makeRoastT1Copy, ...
        'roastSkinVoxelMode', opts.roastSkinVoxelMode, ...
        'skinVoxelRadiusMm', opts.skinVoxelRadiusMm, ...
        'voxelSampleStepMm', opts.voxelSampleStepMm, ...
        'roastOverwriteLabels', opts.roastOverwriteLabels, ...
        'cleanupRoastSkinComponents', opts.cleanupRoastSkinComponents, ...
        'roastSkinCleanupMode', opts.roastSkinCleanupMode, ...
        'minRoastSkinComponentVoxels', opts.minRoastSkinComponentVoxels, ...
        'showFigures', opts.showFigures, ...
        'saveFigures', opts.saveFigures, ...
        'verbose', opts.verbose};

    warpOut = acsWarpScalpSurfaceToPolhemusTrace(surfaceSource, trace, warpArgs{:});

    out = warpOut;
    out.type = 'phoneScanScalpWarp';
    out.phoneScan = phone.info;
    out.phoneTrace = rmfieldIfPresent(trace, {'coordinatesMm'});
    out.phoneTrace.nPointsUsed = size(trace.coordinatesMm, 1);
    out.phoneTrace.coordinateFrame = trace.coordinateFrame;
    out.phoneTrace.exclusionInfo = phoneExclusion;
    out.options.phoneScanWarp = opts;
    out.reportMat = defaultReportFile(out.outputFile);

    outForSave = out;
    if isfield(outForSave, 'figure')
        outForSave = rmfield(outForSave, 'figure');
    end
    save(out.reportMat, 'outForSave', '-v7.3');

    if opts.verbose
        fprintf('\nPhone-scan scalp warp\n');
        fprintf('  phone registration: %s\n', phone.info.file);
        fprintf('  phone points used: %d / %d\n', ...
            size(trace.coordinatesMm, 1), phone.info.nVertices);
        if isfield(phoneExclusion, 'nRemoved') && phoneExclusion.nRemoved > 0
            fprintf('  headpost-like phone points removed: %d\n', ...
                phoneExclusion.nRemoved);
        end
        fprintf('  phone frame: %s\n', trace.coordinateFrame);
        fprintf('  warped skin cache: %s\n', out.outputFile);
    end
end

function opts = parseInputs(varargin)
    p = inputParser;
    p.FunctionName = 'acsWarpScalpSurfaceToPhoneScan';
    addParameter(p, 'outputFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'outputTag', 'phoneScanWarp', @(x) ischar(x) || isstring(x));
    addParameter(p, 'force', false, @isBoolLike);
    addParameter(p, 'maxPhonePoints', 35000, @isPositiveScalar);
    addParameter(p, 'traceSetName', 'phoneScanScalp', @(x) ischar(x) || isstring(x));
    addParameter(p, 'headpostPlacementFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'phoneObjectExclusionFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'excludePhoneObjectPoints', true, @isBoolLike);
    addParameter(p, 'phoneObjectExclusionDistanceMm', 4, @isPositiveScalar);
    addParameter(p, 'excludeHeadpostPoints', true, @isBoolLike);
    addParameter(p, 'headpostPointExclusionDistanceMm', 15, @isPositiveScalar);
    addParameter(p, 'maxHeadpostExclusionPoints', 8000, @isPositiveScalar);
    addParameter(p, 'maxTraceDistanceMm', 60, @isPositiveScalar);
    addParameter(p, 'maxInflationMm', 60, @isPositiveScalar);
    addParameter(p, 'displacementScale', 1, @isPositiveScalar);
    addParameter(p, 'normalOrientationMode', 'autoRadial', ...
        @(x) ischar(x) || isstring(x));
    addParameter(p, 'normalRadialFlipThreshold', 0.02, @isUnitScalar);
    addParameter(p, 'warpDirectionMode', 'blendRadial', ...
        @(x) ischar(x) || isstring(x));
    addParameter(p, 'warpRadialBlendThreshold', 0.35, @isUnitScalar);
    addParameter(p, 'offsetProjectionMode', 'maxWarpRadial', ...
        @(x) ischar(x) || isstring(x));
    addParameter(p, 'robustUpperPercentile', 99.8, @isPercentScalar);
    addParameter(p, 'influenceRadiusMm', 70, @isPositiveScalar);
    addParameter(p, 'influenceSigmaMm', [], @(x) isempty(x) || isPositiveScalar(x));
    addParameter(p, 'coverageOffsetToleranceMm', 0.5, @isNonnegativeScalar);
    addParameter(p, 'smoothingIterations', 30, @isNonnegativeScalar);
    addParameter(p, 'smoothingBlend', 0.45, @isUnitScalar);
    addParameter(p, 'surfaceSmoothingIterations', 0, @isNonnegativeScalar);
    addParameter(p, 'surfaceSmoothingLambda', 0.35, @isFiniteScalar);
    addParameter(p, 'surfaceSmoothingMu', -0.37, @isFiniteScalar);
    addParameter(p, 'surfaceSmoothingPreserveBoundary', true, @isBoolLike);
    addParameter(p, 'dentRepairMode', 'off', @(x) ischar(x) || isstring(x));
    addParameter(p, 'dentRepairMetric', 'localLaplacian', ...
        @(x) ischar(x) || isstring(x));
    addParameter(p, 'dentRepairIterations', 2, @isNonnegativeScalar);
    addParameter(p, 'dentRepairRadiusMm', 8, @isPositiveScalar);
    addParameter(p, 'dentRepairEnvelopePercentile', 75, @isPercentScalar);
    addParameter(p, 'dentRepairMinDentMm', 2, @isNonnegativeScalar);
    addParameter(p, 'dentRepairNormalAngleDeg', 35, @isNonnegativeScalar);
    addParameter(p, 'dentRepairLocalSmoothingIterations', 3, ...
        @isNonnegativeScalar);
    addParameter(p, 'dentRepairDirectionRadialWeight', 0.25, @isUnitScalar);
    addParameter(p, 'dentRepairBlend', 0.85, @isUnitScalar);
    addParameter(p, 'dentRepairMaxMoveMm', 8, @isPositiveScalar);
    addParameter(p, 'dentRepairMaxRings', 8, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 1);
    addParameter(p, 'dentRepairMaxFlaggedFraction', 0.15, @isUnitScalar);
    addParameter(p, 'dentRepairProtectBoundary', true, @isBoolLike);
    addParameter(p, 'seedWeight', 0.95, @isUnitScalar);
    addParameter(p, 'seedAggregation', 'median', @(x) ischar(x) || isstring(x));
    addParameter(p, 'seedPercentile', 75, @isPercentScalar);
    addParameter(p, 'interpK', 6, @(x) isnumeric(x) && isscalar(x) && x >= 1);
    addParameter(p, 'interpSigmaMm', 12, @isPositiveScalar);
    addParameter(p, 'makeRoastMask', false, @isBoolLike);
    addParameter(p, 'roastMaskFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'roastMaskOutputFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'roastT1File', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'makeRoastT1Copy', false, @isBoolLike);
    addParameter(p, 'roastSkinVoxelMode', 'rasterSurfaceFill', ...
        @(x) ischar(x) || isstring(x));
    addParameter(p, 'skinVoxelRadiusMm', 0.8, @isNonnegativeScalar);
    addParameter(p, 'voxelSampleStepMm', 0.5, @isPositiveScalar);
    addParameter(p, 'roastOverwriteLabels', [0 5 6], ...
        @(x) isnumeric(x) && isvector(x));
    addParameter(p, 'cleanupRoastSkinComponents', true, @isBoolLike);
    addParameter(p, 'roastSkinCleanupMode', 'largest', ...
        @(x) ischar(x) || isstring(x));
    addParameter(p, 'minRoastSkinComponentVoxels', 1000, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0);
    addParameter(p, 'showFigures', true, @isBoolLike);
    addParameter(p, 'saveFigures', true, @isBoolLike);
    addParameter(p, 'verbose', true, @isBoolLike);
    parse(p, varargin{:});

    opts = p.Results;
    opts.outputFile = expandUserPath(char(opts.outputFile));
    opts.outputTag = safeName(char(opts.outputTag));
    opts.force = logical(opts.force);
    opts.maxPhonePoints = round(double(opts.maxPhonePoints));
    opts.traceSetName = char(opts.traceSetName);
    opts.headpostPlacementFile = expandUserPath(char(opts.headpostPlacementFile));
    opts.phoneObjectExclusionFile = expandUserPath(char(opts.phoneObjectExclusionFile));
    opts.excludePhoneObjectPoints = logical(opts.excludePhoneObjectPoints);
    opts.phoneObjectExclusionDistanceMm = double(opts.phoneObjectExclusionDistanceMm);
    opts.excludeHeadpostPoints = logical(opts.excludeHeadpostPoints);
    opts.headpostPointExclusionDistanceMm = double(opts.headpostPointExclusionDistanceMm);
    opts.maxHeadpostExclusionPoints = round(double(opts.maxHeadpostExclusionPoints));
    opts.maxTraceDistanceMm = double(opts.maxTraceDistanceMm);
    opts.maxInflationMm = double(opts.maxInflationMm);
    opts.displacementScale = double(opts.displacementScale);
    opts.normalOrientationMode = normalizeNormalOrientationMode( ...
        opts.normalOrientationMode);
    opts.normalRadialFlipThreshold = double(opts.normalRadialFlipThreshold);
    opts.warpDirectionMode = normalizeWarpDirectionMode(opts.warpDirectionMode);
    opts.warpRadialBlendThreshold = double(opts.warpRadialBlendThreshold);
    opts.offsetProjectionMode = char(opts.offsetProjectionMode);
    opts.robustUpperPercentile = double(opts.robustUpperPercentile);
    opts.influenceRadiusMm = double(opts.influenceRadiusMm);
    if isempty(opts.influenceSigmaMm)
        opts.influenceSigmaMm = opts.influenceRadiusMm / 2;
    else
        opts.influenceSigmaMm = double(opts.influenceSigmaMm);
    end
    opts.coverageOffsetToleranceMm = double(opts.coverageOffsetToleranceMm);
    opts.smoothingIterations = round(double(opts.smoothingIterations));
    opts.smoothingBlend = double(opts.smoothingBlend);
    opts.surfaceSmoothingIterations = round(double( ...
        opts.surfaceSmoothingIterations));
    opts.surfaceSmoothingLambda = double(opts.surfaceSmoothingLambda);
    opts.surfaceSmoothingMu = double(opts.surfaceSmoothingMu);
    opts.surfaceSmoothingPreserveBoundary = logical( ...
        opts.surfaceSmoothingPreserveBoundary);
    opts.dentRepairMode = normalizeDentRepairMode(opts.dentRepairMode);
    opts.dentRepairMetric = normalizeDentRepairMetric( ...
        opts.dentRepairMetric);
    opts.dentRepairIterations = round(double(opts.dentRepairIterations));
    opts.dentRepairRadiusMm = double(opts.dentRepairRadiusMm);
    opts.dentRepairEnvelopePercentile = double( ...
        opts.dentRepairEnvelopePercentile);
    opts.dentRepairMinDentMm = double(opts.dentRepairMinDentMm);
    opts.dentRepairNormalAngleDeg = double(opts.dentRepairNormalAngleDeg);
    opts.dentRepairLocalSmoothingIterations = round(double( ...
        opts.dentRepairLocalSmoothingIterations));
    opts.dentRepairDirectionRadialWeight = double( ...
        opts.dentRepairDirectionRadialWeight);
    opts.dentRepairBlend = double(opts.dentRepairBlend);
    opts.dentRepairMaxMoveMm = double(opts.dentRepairMaxMoveMm);
    opts.dentRepairMaxRings = round(double(opts.dentRepairMaxRings));
    opts.dentRepairMaxFlaggedFraction = double( ...
        opts.dentRepairMaxFlaggedFraction);
    opts.dentRepairProtectBoundary = logical(opts.dentRepairProtectBoundary);
    opts.seedWeight = double(opts.seedWeight);
    opts.seedAggregation = char(opts.seedAggregation);
    opts.seedPercentile = double(opts.seedPercentile);
    opts.interpK = round(double(opts.interpK));
    opts.interpSigmaMm = double(opts.interpSigmaMm);
    opts.makeRoastMask = logical(opts.makeRoastMask);
    opts.roastMaskFile = expandUserPath(char(opts.roastMaskFile));
    opts.roastMaskOutputFile = expandUserPath(char(opts.roastMaskOutputFile));
    opts.roastT1File = expandUserPath(char(opts.roastT1File));
    opts.makeRoastT1Copy = logical(opts.makeRoastT1Copy);
    opts.roastSkinVoxelMode = char(opts.roastSkinVoxelMode);
    opts.skinVoxelRadiusMm = double(opts.skinVoxelRadiusMm);
    opts.voxelSampleStepMm = double(opts.voxelSampleStepMm);
    opts.roastOverwriteLabels = unique(round(double(opts.roastOverwriteLabels(:))))';
    opts.cleanupRoastSkinComponents = logical(opts.cleanupRoastSkinComponents);
    opts.roastSkinCleanupMode = char(opts.roastSkinCleanupMode);
    opts.minRoastSkinComponentVoxels = round(double(opts.minRoastSkinComponentVoxels));
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

function tf = isFiniteScalar(x)
    tf = isnumeric(x) && isscalar(x) && isfinite(x);
end

function tf = isUnitScalar(x)
    tf = isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0 && x <= 1;
end

function tf = isPercentScalar(x)
    tf = isnumeric(x) && isscalar(x) && isfinite(x) && x > 0 && x <= 100;
end

function mode = normalizeNormalOrientationMode(mode)
    mode = lower(strtrim(char(mode)));
    mode = regexprep(mode, '[\s_\-]+', '');
    switch mode
        case {'globaltrace', 'trace', 'legacy'}
            mode = 'globalTrace';
        case {'autoradial', 'auto', 'radialauto'}
            mode = 'autoRadial';
        case {'radial', 'centroid', 'centerout'}
            mode = 'radial';
        case {'none', 'raw'}
            mode = 'none';
        otherwise
            error('acsWarpScalpSurfaceToPhoneScan:BadNormalMode', ...
                ['normalOrientationMode must be ''globalTrace'', ', ...
                 '''autoRadial'', ''radial'', or ''none''.']);
    end
end

function mode = normalizeWarpDirectionMode(mode)
    mode = lower(strtrim(char(mode)));
    mode = regexprep(mode, '[\s_\-]+', '');
    switch mode
        case {'normal', 'normals', 'meshnormal', 'meshnormals'}
            mode = 'normal';
        case {'blendradial', 'radialblend', 'hybridradial', 'hybrid'}
            mode = 'blendRadial';
        case {'radial', 'centroid', 'centerout'}
            mode = 'radial';
        otherwise
            error('acsWarpScalpSurfaceToPhoneScan:BadWarpDirectionMode', ...
                'warpDirectionMode must be ''normal'', ''blendRadial'', or ''radial''.');
    end
end

function mode = normalizeDentRepairMode(mode)
    mode = lower(strtrim(char(mode)));
    mode = regexprep(mode, '[\s_\-]+', '');
    switch mode
        case {'off', 'none', 'false', 'legacy'}
            mode = 'off';
        case {'diagnose', 'diagnostic', 'diagnostics', 'reportonly'}
            mode = 'diagnose';
        case {'auto', 'repair', 'on', 'true'}
            mode = 'auto';
        otherwise
            error('acsWarpScalpSurfaceToPhoneScan:BadDentRepairMode', ...
                'dentRepairMode must be ''off'', ''diagnose'', or ''auto''.');
    end
end

function mode = normalizeDentRepairMetric(mode)
    mode = lower(strtrim(char(mode)));
    mode = regexprep(mode, '[\s_\-]+', '');
    switch mode
        case {'local', 'laplacian', 'locallaplacian', 'localdefect'}
            mode = 'localLaplacian';
        case {'radial', 'radialenvelope', 'envelope', 'legacy'}
            mode = 'radialEnvelope';
        case {'hybrid', 'combined', 'both'}
            mode = 'hybrid';
        otherwise
            error('acsWarpScalpSurfaceToPhoneScan:BadDentRepairMetric', ...
                ['dentRepairMetric must be ''localLaplacian'', ', ...
                 '''radialEnvelope'', or ''hybrid''.']);
    end
end

function addLocalDependencies()
    repoRoot = fileparts(fileparts(mfilename('fullpath')));
    addpath(fullfile(repoRoot, 'acsUtilities'));
    addpath(fullfile(repoRoot, 'capMaker', 'core'));
    addpath(fullfile(repoRoot, 'capMaker', 'geometry'));
end

function opts = resolveOutputFile(surfaceSource, phone, opts)
    if ~isempty(opts.outputFile)
        return;
    end
    folder = '';
    stem = '';
    if ischar(surfaceSource) || isstring(surfaceSource)
        surfaceFile = expandUserPath(char(surfaceSource));
        folder = fileparts(surfaceFile);
        stem = stripMatExtension(getFileName(surfaceFile));
    elseif isfield(phone.info, 'file') && ~isempty(phone.info.file)
        folder = fileparts(phone.info.file);
        stem = 'skinMesh';
    end
    if isempty(folder)
        folder = pwd;
    end
    if isempty(stem)
        stem = 'skinMesh';
    end
    opts.outputFile = fullfile(folder, [stem '_' opts.outputTag '.mat']);
end

function phone = readRegisteredPhoneScan(value, opts)
    sourceFile = '';
    if ischar(value) || isstring(value)
        sourceFile = expandUserPath(char(value));
        if exist(sourceFile, 'file') ~= 2
            error('acsWarpScalpSurfaceToPhoneScan:RegistrationNotFound', ...
                'Phone registration file not found: %s', sourceFile);
        end
        S = load(sourceFile);
        C = firstStruct(S);
        if isfield(S, 'TRregisteredPhone') && ~isempty(S.TRregisteredPhone)
            C.TRregisteredPhone = S.TRregisteredPhone;
        end
    elseif isstruct(value)
        C = value;
    else
        error('acsWarpScalpSurfaceToPhoneScan:BadRegistrationInput', ...
            'Phone registration input must be a struct or MAT file.');
    end

    TR = [];
    if isfield(C, 'meshes') && isstruct(C.meshes) && ...
            isfield(C.meshes, 'TRregisteredPhone') && ...
            ~isempty(C.meshes.TRregisteredPhone)
        TR = ensureTriangulation(C.meshes.TRregisteredPhone);
    elseif isfield(C, 'TRregisteredPhone') && ~isempty(C.TRregisteredPhone)
        TR = ensureTriangulation(C.TRregisteredPhone);
    elseif isfield(C, 'registeredVertices') && isfield(C, 'faces')
        TR = triangulation(double(C.faces), double(C.registeredVertices));
    end
    if isempty(TR)
        error('acsWarpScalpSurfaceToPhoneScan:MissingRegisteredMesh', ...
            'Could not find a registered phone scan mesh in the supplied input.');
    end

    frame = '';
    if isfield(C, 'targetCoordinateFrame') && ~isempty(C.targetCoordinateFrame)
        frame = char(C.targetCoordinateFrame);
    elseif isfield(C, 'target') && isstruct(C.target) && ...
            isfield(C.target, 'coordinateFrame') && ~isempty(C.target.coordinateFrame)
        frame = char(C.target.coordinateFrame);
    end
    if isempty(frame)
        frame = 'capMakerPrintMm';
    end

    points = double(TR.Points);
    sampledPoints = deterministicSampleRows(points, opts.maxPhonePoints);
    phone = struct();
    phone.TRregisteredPhone = TR;
    phone.allPointsMm = points;
    phone.pointsMm = sampledPoints;
    phone.excludedPointsMm = zeros(0, 3);
    phone.coordinateFrame = frame;
    phone.info = struct( ...
        'file', sourceFile, ...
        'coordinateFrame', frame, ...
        'nVertices', size(points, 1), ...
        'nFaces', size(TR.ConnectivityList, 1), ...
        'nSampledPoints', size(sampledPoints, 1));
end

function [phone, exclusion] = filterPhonePointsForWarp(phone, surfaceSource, opts)
    exclusion = struct( ...
        'enabled', false, ...
        'method', 'none', ...
        'phoneObjectExclusionFile', opts.phoneObjectExclusionFile, ...
        'headpostPlacementFile', opts.headpostPlacementFile, ...
        'objectFrame', '', ...
        'headpostFrame', '', ...
        'phoneFrame', phone.coordinateFrame, ...
        'phoneObjectDistanceThresholdMm', opts.phoneObjectExclusionDistanceMm, ...
        'headpostDistanceThresholdMm', opts.headpostPointExclusionDistanceMm, ...
        'nBefore', size(phone.pointsMm, 1), ...
        'nRemoved', 0, ...
        'nAfter', size(phone.pointsMm, 1), ...
        'objectSelection', struct(), ...
        'headpostPlacement', struct(), ...
        'distanceSummaryMm', struct());

    methodParts = {};

    if opts.excludePhoneObjectPoints && ~isempty(opts.phoneObjectExclusionFile)
        if exist(opts.phoneObjectExclusionFile, 'file') ~= 2
            warning('acsWarpScalpSurfaceToPhoneScan:PhoneObjectExclusionNotFound', ...
                ['phoneObjectExclusionFile was supplied, but does not exist. ', ...
                 'Phone-scan object exclusion was skipped: %s'], ...
                opts.phoneObjectExclusionFile);
            objectInfo = struct('enabled', false, ...
                'method', 'phoneObjectExclusionFileNotFound', ...
                'file', opts.phoneObjectExclusionFile);
        else
            [phone, objectInfo] = applyPhoneObjectExclusion( ...
                phone, surfaceSource, opts);
            if isfield(objectInfo, 'enabled') && objectInfo.enabled
                methodParts{end + 1} = objectInfo.method; %#ok<AGROW>
                exclusion.enabled = true;
                exclusion.objectFrame = objectInfo.objectFrame;
            end
        end
        exclusion.objectSelection = objectInfo;
    elseif ~opts.excludePhoneObjectPoints
        exclusion.objectSelection = struct('enabled', false, ...
            'method', 'disabled');
    elseif isempty(opts.phoneObjectExclusionFile)
        exclusion.objectSelection = struct('enabled', false, ...
            'method', 'noPhoneObjectExclusionFile');
    end

    if opts.excludeHeadpostPoints && ~isempty(opts.headpostPlacementFile)
        [phone, headpostInfo] = applyPlacedHeadpostExclusion( ...
            phone, surfaceSource, opts);
        if isfield(headpostInfo, 'enabled') && headpostInfo.enabled
            methodParts{end + 1} = headpostInfo.method; %#ok<AGROW>
            exclusion.enabled = true;
            exclusion.headpostFrame = headpostInfo.headpostFrame;
        end
        exclusion.headpostPlacement = headpostInfo;
    elseif ~opts.excludeHeadpostPoints
        exclusion.headpostPlacement = struct('enabled', false, ...
            'method', 'disabled');
    elseif isempty(opts.headpostPlacementFile)
        exclusion.headpostPlacement = struct('enabled', false, ...
            'method', 'noHeadpostPlacementFile');
    end

    exclusion.nRemoved = exclusion.nBefore - size(phone.pointsMm, 1);
    exclusion.nAfter = size(phone.pointsMm, 1);
    if isempty(methodParts)
        exclusion.method = 'none';
    else
        exclusion.method = strjoin(methodParts, '+');
    end
end

function [phone, info] = applyPhoneObjectExclusion(phone, surfaceSource, opts)
    info = struct('enabled', false, ...
        'method', 'none', ...
        'file', opts.phoneObjectExclusionFile, ...
        'objectName', '', ...
        'objectFrame', '', ...
        'distanceThresholdMm', opts.phoneObjectExclusionDistanceMm, ...
        'nBefore', size(phone.pointsMm, 1), ...
        'nRemoved', 0, ...
        'nAfter', size(phone.pointsMm, 1), ...
        'distanceSummaryMm', struct());

    try
        [objectPoints, objectInfo] = readPhoneObjectPointsInFrame( ...
            opts.phoneObjectExclusionFile, phone.coordinateFrame, ...
            surfaceSource);
    catch ME
        warning('acsWarpScalpSurfaceToPhoneScan:PhoneObjectExclusionSkipped', ...
            ['Could not prepare phone object exclusion points. Continuing ', ...
             'without that exclusion. %s'], ME.message);
        info.method = 'phoneObjectTransformFailed';
        return;
    end

    info.objectName = objectInfo.objectName;
    info.objectFrame = objectInfo.coordinateFrame;
    if isempty(objectPoints)
        info.method = 'emptyPhoneObjectSelection';
        return;
    end

    [~, d] = nearestRows(objectPoints, phone.pointsMm, 1000);
    remove = d <= opts.phoneObjectExclusionDistanceMm;
    phone.excludedPointsMm = [phone.excludedPointsMm; phone.pointsMm(remove, :)];
    phone.pointsMm = phone.pointsMm(~remove, :);
    phone.info.nPhoneObjectExcludedPoints = nnz(remove);
    phone.info.nSampledPoints = size(phone.pointsMm, 1);

    info.enabled = true;
    info.method = 'distanceToSelectedPhoneObjectPoints';
    info.nRemoved = nnz(remove);
    info.nAfter = size(phone.pointsMm, 1);
    info.distanceSummaryMm = summarizeVector(d);
    if info.nRemoved == 0
        warning('acsWarpScalpSurfaceToPhoneScan:NoPhoneObjectPointsExcluded', ...
            ['No phone-scan points were within %.3g mm of the selected ', ...
             'phone object "%s". Check that the object selection and ', ...
             'registered phone mesh are in the same frame.'], ...
            opts.phoneObjectExclusionDistanceMm, info.objectName);
    end
end

function [phone, info] = applyPlacedHeadpostExclusion(phone, surfaceSource, opts)
    info = struct('enabled', false, ...
        'method', 'none', ...
        'file', opts.headpostPlacementFile, ...
        'headpostFrame', '', ...
        'distanceThresholdMm', opts.headpostPointExclusionDistanceMm, ...
        'nBefore', size(phone.pointsMm, 1), ...
        'nRemoved', 0, ...
        'nAfter', size(phone.pointsMm, 1), ...
        'distanceSummaryMm', struct());

    if exist(opts.headpostPlacementFile, 'file') ~= 2
        warning('acsWarpScalpSurfaceToPhoneScan:HeadpostPlacementNotFound', ...
            ['headpostPlacementFile was supplied, but does not exist. ', ...
             'Phone-scan headpost point exclusion was skipped: %s'], ...
            opts.headpostPlacementFile);
        info.method = 'headpostPlacementFileNotFound';
        return;
    end

    try
        [headpostPoints, headpostInfo] = readHeadpostPointsInFrame( ...
            opts.headpostPlacementFile, phone.coordinateFrame, ...
            surfaceSource, opts);
    catch ME
        warning('acsWarpScalpSurfaceToPhoneScan:HeadpostExclusionSkipped', ...
            ['Could not prepare placed headpost geometry for phone-scan ', ...
             'point exclusion. Continuing without headpost filtering. %s'], ...
            ME.message);
        info.method = 'headpostTransformFailed';
        return;
    end

    if isempty(headpostPoints)
        info.method = 'emptyHeadpostGeometry';
        return;
    end

    [~, d] = nearestRows(headpostPoints, phone.pointsMm, 1000);
    remove = d <= opts.headpostPointExclusionDistanceMm;
    phone.excludedPointsMm = [phone.excludedPointsMm; phone.pointsMm(remove, :)];
    phone.pointsMm = phone.pointsMm(~remove, :);
    phone.info.nSampledPointsBeforeHeadpostExclusion = numel(remove);
    phone.info.nSampledPointsAfterHeadpostExclusion = size(phone.pointsMm, 1);
    phone.info.nHeadpostExcludedPoints = nnz(remove);
    phone.info.nSampledPoints = size(phone.pointsMm, 1);

    info.enabled = true;
    info.method = 'distanceToPlacedHeadpostMeshVertices';
    info.headpostFrame = headpostInfo.coordinateFrame;
    info.nRemoved = nnz(remove);
    info.nAfter = size(phone.pointsMm, 1);
    info.distanceSummaryMm = summarizeVector(d);
    if info.nRemoved == 0
        warning('acsWarpScalpSurfaceToPhoneScan:NoHeadpostPointsExcluded', ...
            ['No phone-scan points were within %.3g mm of the placed ', ...
             'headpost. If the visible headpost is still driving the scalp ', ...
             'warp, increase headpostPointExclusionDistanceMm or check ', ...
             'the phone/headpost registration.'], ...
            opts.headpostPointExclusionDistanceMm);
    end
end

function [points, info] = readPhoneObjectPointsInFrame(fileName, targetFrame, ...
        surfaceSource)
    Sraw = load(fileName);
    S = firstStruct(Sraw);
    points = [];
    objectName = '';
    sourceFrame = '';

    if isfield(S, 'selectedCoordinatesMm') && ~isempty(S.selectedCoordinatesMm)
        points = double(S.selectedCoordinatesMm);
    elseif isfield(S, 'coordinatesMm') && ~isempty(S.coordinatesMm)
        points = double(S.coordinatesMm);
    elseif isfield(S, 'traceSets') && ~isempty(S.traceSets)
        ts = S.traceSets(1);
        if isfield(ts, 'coordinatesMm') && ~isempty(ts.coordinatesMm)
            points = double(ts.coordinatesMm);
        end
        if isfield(ts, 'name') && ~isempty(ts.name)
            objectName = char(ts.name);
        end
    elseif isfield(Sraw, 'phoneObject') && isstruct(Sraw.phoneObject)
        [points, info] = readPhoneObjectPointsInFrameStruct( ...
            Sraw.phoneObject, targetFrame, surfaceSource);
        return;
    end

    if isempty(objectName)
        objectName = char(getOptionalField(S, 'objectName', ...
            getOptionalField(S, 'name', 'phoneObject')));
    end
    if isfield(S, 'coordinateFrame') && ~isempty(S.coordinateFrame)
        sourceFrame = char(S.coordinateFrame);
    elseif isfield(S, 'source') && isstruct(S.source) && ...
            isfield(S.source, 'coordinateFrame') && ~isempty(S.source.coordinateFrame)
        sourceFrame = char(S.source.coordinateFrame);
    end
    if isempty(sourceFrame)
        sourceFrame = targetFrame;
    end

    [points, transform] = transformPointsBetweenFrames( ...
        points, sourceFrame, targetFrame, surfaceSource);
    info = struct('objectName', objectName, ...
        'coordinateFrame', targetFrame, ...
        'sourceFrame', sourceFrame, ...
        'transform', transform, ...
        'nPoints', size(points, 1));
end

function [points, info] = readPhoneObjectPointsInFrameStruct(S, targetFrame, ...
        surfaceSource)
    points = [];
    objectName = char(getOptionalField(S, 'objectName', ...
        getOptionalField(S, 'name', 'phoneObject')));
    if isfield(S, 'selectedCoordinatesMm') && ~isempty(S.selectedCoordinatesMm)
        points = double(S.selectedCoordinatesMm);
    elseif isfield(S, 'coordinatesMm') && ~isempty(S.coordinatesMm)
        points = double(S.coordinatesMm);
    elseif isfield(S, 'traceSets') && ~isempty(S.traceSets) && ...
            isfield(S.traceSets(1), 'coordinatesMm')
        points = double(S.traceSets(1).coordinatesMm);
        if isfield(S.traceSets(1), 'name') && ~isempty(S.traceSets(1).name)
            objectName = char(S.traceSets(1).name);
        end
    end
    sourceFrame = char(getOptionalField(S, 'coordinateFrame', targetFrame));
    [points, transform] = transformPointsBetweenFrames( ...
        points, sourceFrame, targetFrame, surfaceSource);
    info = struct('objectName', objectName, ...
        'coordinateFrame', targetFrame, ...
        'sourceFrame', sourceFrame, ...
        'transform', transform, ...
        'nPoints', size(points, 1));
end

function [points, info] = readHeadpostPointsInFrame(fileName, targetFrame, ...
        surfaceSource, opts)
    S = load(fileName);
    placement = firstStruct(S);
    TRplaced = [];
    if isfield(placement, 'meshes') && isstruct(placement.meshes) && ...
            isfield(placement.meshes, 'TRplaced') && ~isempty(placement.meshes.TRplaced)
        TRplaced = ensureTriangulation(placement.meshes.TRplaced);
    elseif isfield(S, 'TRplaced') && ~isempty(S.TRplaced)
        TRplaced = ensureTriangulation(S.TRplaced);
    elseif isfield(placement, 'TRplaced') && ~isempty(placement.TRplaced)
        TRplaced = ensureTriangulation(placement.TRplaced);
    end
    if isempty(TRplaced)
        error('acsWarpScalpSurfaceToPhoneScan:MissingHeadpostMesh', ...
            'Headpost placement file does not contain meshes.TRplaced.');
    end

    sourceFrame = 'capMakerPrintMm';
    if isfield(placement, 'coordinateFrame') && ~isempty(placement.coordinateFrame)
        sourceFrame = char(placement.coordinateFrame);
    end

    points = deterministicSampleRows(double(TRplaced.Points), ...
        opts.maxHeadpostExclusionPoints);
    [points, transform] = transformPointsBetweenFrames( ...
        points, sourceFrame, targetFrame, surfaceSource);

    info = struct('coordinateFrame', targetFrame, ...
        'sourceFrame', sourceFrame, 'transform', transform);
end

function [points, transform] = transformPointsBetweenFrames(points, sourceFrame, ...
        targetFrame, surfaceSource)
    sourceFrameNorm = normalizeCoordinateFrameName(sourceFrame);
    targetFrameNorm = normalizeCoordinateFrameName(targetFrame);
    if strcmpi(sourceFrameNorm, targetFrameNorm)
        transform = 'identity';
        return;
    end

    meta = readSurfaceMeta(surfaceSource);
    if strcmpi(sourceFrameNorm, 'capMakerPrintMm') && ...
            strcmpi(targetFrameNorm, 'capMakerPreCropWorldMm')
        points = printMmToStableWorld(points, meta);
        transform = 'print-to-pre-crop world via skin metadata';
    elseif strcmpi(sourceFrameNorm, 'capMakerPreCropWorldMm') && ...
            strcmpi(targetFrameNorm, 'capMakerPrintMm')
        points = stableWorldToPrintMm(points, meta);
        transform = 'pre-crop world-to-print via skin metadata';
    else
        error('acsWarpScalpSurfaceToPhoneScan:UnsupportedFrameTransform', ...
            'Cannot transform "%s" points into "%s".', ...
            sourceFrame, targetFrame);
    end
end

function meta = readSurfaceMeta(surfaceSource)
    meta = struct();
    if ischar(surfaceSource) || isstring(surfaceSource)
        fileName = expandUserPath(char(surfaceSource));
        if exist(fileName, 'file') == 2
            S = load(fileName, 'meta');
            if isfield(S, 'meta') && isstruct(S.meta)
                meta = S.meta;
            end
        end
    elseif isstruct(surfaceSource) && isfield(surfaceSource, 'meta') && ...
            isstruct(surfaceSource.meta)
        meta = surfaceSource.meta;
    end
    requireCapMakerMeta(meta);
end

function frame = normalizeCoordinateFrameName(frame)
    key = lower(regexprep(strtrim(char(frame)), '[\s_\-]+', ''));
    switch key
        case {'capmakerprintmm', 'print', 'printframe'}
            frame = 'capMakerPrintMm';
        case {'capmakerprecropworldmm', 'precrop', 'stable', ...
                'stableworld', 'stableworldmm', 'fullhead'}
            frame = 'capMakerPreCropWorldMm';
        otherwise
            frame = char(frame);
    end
end

function pointsStable = printMmToStableWorld(pointsPrint, meta)
    requireCapMakerMeta(meta);
    finalWorldMm = applyAffineToPoints(meta.print.T_print2world, pointsPrint);
    pointsStable = (double(meta.align.R) \ finalWorldMm')';
end

function pointsPrint = stableWorldToPrintMm(pointsStable, meta)
    requireCapMakerMeta(meta);
    finalWorldMm = (double(meta.align.R) * double(pointsStable)')';
    pointsPrint = applyAffineToPoints(meta.print.T_world2print, finalWorldMm);
end

function requireCapMakerMeta(meta)
    ok = isstruct(meta) && isfield(meta, 'print') && ...
        isfield(meta.print, 'T_print2world') && ...
        isfield(meta.print, 'T_world2print') && ...
        isfield(meta, 'align') && isfield(meta.align, 'R');
    if ~ok
        error('acsWarpScalpSurfaceToPhoneScan:MissingCapMakerMeta', ...
            ['Headpost-aware phone-scan scalp warping requires skin cache ', ...
             'metadata with print and align transforms.']);
    end
end

function pointsOut = applyAffineToPoints(T, pointsIn)
    pointsIn = double(pointsIn);
    P = [pointsIn, ones(size(pointsIn, 1), 1)] * double(T)';
    pointsOut = P(:, 1:3);
end

function value = getOptionalField(S, fieldName, defaultValue)
    value = defaultValue;
    if isstruct(S) && isfield(S, fieldName) && ~isempty(S.(fieldName))
        value = S.(fieldName);
    end
end

function trace = makePhoneTrace(phone, opts)
    trace = struct();
    trace.name = opts.traceSetName;
    trace.coordinateFrame = phone.coordinateFrame;
    trace.coordinatesMm = phone.pointsMm;
    trace.excludedCoordinatesMm = phone.excludedPointsMm;
    trace.labels = defaultLabels(size(phone.pointsMm, 1), 'phone');
    trace.rows = (1:size(phone.pointsMm, 1))';
    trace.source = struct( ...
        'type', 'registeredPhoneScan', ...
        'file', phone.info.file, ...
        'coordinateFrame', phone.coordinateFrame);
    trace.traceSets = struct( ...
        'name', opts.traceSetName, ...
        'coordinatesMm', phone.pointsMm, ...
        'labels', {trace.labels}, ...
        'rows', trace.rows);
end

function rows = deterministicSampleRows(points, maxRows)
    n = size(points, 1);
    if n <= maxRows
        rows = double(points);
        return;
    end
    idx = unique(round(linspace(1, n, maxRows)));
    rows = double(points(idx(:), :));
end

function labels = defaultLabels(n, prefix)
    labels = cell(n, 1);
    for i = 1:n
        labels{i} = sprintf('%s_%05d', prefix, i);
    end
end

function [idx, dist] = nearestRows(reference, query, chunk)
    reference = double(reference);
    query = double(query);
    idx = zeros(size(query, 1), 1);
    dist = zeros(size(query, 1), 1);
    if isempty(reference) || isempty(query)
        idx = zeros(size(query, 1), 1);
        dist = inf(size(query, 1), 1);
        return;
    end
    for a = 1:chunk:size(query, 1)
        b = min(size(query, 1), a + chunk - 1);
        D = squaredDistanceRows(query(a:b, :), reference);
        [d2, ii] = min(D, [], 2);
        idx(a:b) = ii;
        dist(a:b) = sqrt(d2);
    end
end

function D = squaredDistanceRows(A, B)
    A = double(A);
    B = double(B);
    D = bsxfun(@plus, sum(A .^ 2, 2), sum(B .^ 2, 2)') - 2 * (A * B');
    D = max(D, 0);
end

function summary = summarizeVector(x)
    x = double(x(:));
    x = x(isfinite(x));
    if isempty(x)
        summary = struct('n', 0, 'min', NaN, 'median', NaN, ...
            'p95', NaN, 'max', NaN);
        return;
    end
    summary = struct('n', numel(x), ...
        'min', min(x), ...
        'median', median(x), ...
        'p95', percentileLocal(x, 95), ...
        'max', max(x));
end

function value = percentileLocal(x, p)
    x = sort(double(x(:)));
    x = x(isfinite(x));
    if isempty(x)
        value = NaN;
        return;
    end
    if numel(x) == 1
        value = x;
        return;
    end
    pos = 1 + (numel(x) - 1) * (p / 100);
    lo = floor(pos);
    hi = ceil(pos);
    if lo == hi
        value = x(lo);
    else
        value = x(lo) + (pos - lo) * (x(hi) - x(lo));
    end
end

function TR = ensureTriangulation(value)
    if isa(value, 'triangulation')
        TR = value;
    elseif isstruct(value) && isfield(value, 'ConnectivityList') && ...
            isfield(value, 'Points')
        TR = triangulation(double(value.ConnectivityList), double(value.Points));
    elseif isstruct(value) && isfield(value, 'faces') && isfield(value, 'vertices')
        TR = triangulation(double(value.faces), double(value.vertices));
    else
        error('acsWarpScalpSurfaceToPhoneScan:BadTriangulation', ...
            'Expected a triangulation or faces/vertices structure.');
    end
end

function S = firstStruct(M)
    if isstruct(M) && isfield(M, 'out') && isstruct(M.out)
        S = M.out;
        return;
    end
    if isstruct(M) && isfield(M, 'outForSave') && isstruct(M.outForSave)
        S = M.outForSave;
        return;
    end
    if isstruct(M) && isfield(M, 'outSaved') && isstruct(M.outSaved)
        S = M.outSaved;
        return;
    end
    if isstruct(M)
        names = fieldnames(M);
        for i = 1:numel(names)
            if isstruct(M.(names{i}))
                S = M.(names{i});
                return;
            end
        end
    end
    S = M;
end

function S = rmfieldIfPresent(S, fields)
    for i = 1:numel(fields)
        if isfield(S, fields{i})
            S = rmfield(S, fields{i});
        end
    end
end

function ensureDir(folder)
    if ~isempty(folder) && exist(folder, 'dir') ~= 7
        mkdir(folder);
    end
end

function name = safeName(name)
    name = regexprep(char(name), '[^\w\-]+', '_');
    name = regexprep(name, '_+', '_');
    name = regexprep(name, '^_|_$', '');
    if isempty(name)
        name = 'phoneScanWarp';
    end
end

function fileName = expandUserPath(fileName)
    fileName = char(fileName);
    if startsWith(fileName, '~')
        homeDir = getenv('HOME');
        if isempty(homeDir)
            homeDir = getenv('USERPROFILE');
        end
        if numel(fileName) == 1
            fileName = homeDir;
        elseif fileName(2) == filesep || fileName(2) == '/' || fileName(2) == '\'
            fileName = fullfile(homeDir, fileName(3:end));
        end
    end
end

function name = getFileName(fileName)
    [~, stem, ext] = fileparts(char(fileName));
    name = [stem ext];
end

function stem = stripMatExtension(fileName)
    [~, stem] = fileparts(char(fileName));
end

function fileName = defaultReportFile(outputFile)
    [folder, stem] = fileparts(outputFile);
    fileName = fullfile(folder, [stem '_report.mat']);
end
