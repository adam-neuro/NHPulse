function out = acsBuildCapMakerManufacturingStl(layoutIn, varargin)
% ACSBUILDCAPMAKERMANUFACTURINGSTL Build capMaker STL products from a layout.
%
% out = acsBuildCapMakerManufacturingStl(combinedLayout) takes a finalized
% ROAST/capMaker layout, places capMaker electrode holders at the layout's
% print-frame coordinates, adds rails and optional lateral straps, carves
% gel/electrode keepouts, and writes TPE/PLA STL files.
%
% Name-value options:
%   manufacturingTag      : output stem/folder tag ['']
%   outputDir             : explicit output folder ['']
%   force                 : overwrite existing STL/report files [false]
%   electrodeNames        : subset/order of layout names to manufacture [{}]
%   holderInsideDiaMm     : holder hole diameter [4]
%   holderOutsideDiaMm    : hex holder outside diameter [12]
%   holderHeightMm        : holder height [7]
%   holderEmbedMm         : embed holder into scalp surface [0.3]
%   holderNormalMode      : 'autoSmooth', 'smooth', or 'vertex' ['autoSmooth']
%   holderSmoothNormalRadiusMm : local normal interpolation radius [6]
%   holderNormalDeviationThresholdDeg : autoSmooth threshold [25]
%   holderPlacementSurfaceMode : 'full' or 'manufacturing' ['full']
%   holeInsideDiaMm       : hole keepout nominal diameter [holderInsideDiaMm]
%   holeKeepoutMode       : 'flared', 'tetra', or 'flaredAndTetra' ['flared']
%   holeBoreClearanceMm   : radial clearance through holder bore [0.1]
%   holeScalpClearanceMm  : radial clearance at scalp-side flare [holeClearanceMm]
%   holeClearanceMm       : legacy alias for scalp-side clearance [max(0.5, voxelSizeMm)]
%   holeTopExtendMm       : extension above holder top [1.5]
%   holeScalpExtendMm     : extension past holder base toward scalp [6]
%   holeScalpFlareDiaMm   : nominal scalp-side gel-pocket diameter [max(holeInsideDiaMm+2,6)]
%   railWidthMm           : rail width [2]
%   railHeightMm          : rail height [2]
%   railEmbedFraction     : rail embed fraction [0.5]
%   railMinLengthMm       : skip shorter rails [0]
%   railZThresholdMm      : cap base trim threshold [15]
%   railPerimeterFactor   : rim rail width multiplier [1.5]
%   railSurfaceMaxFaces   : decimate scalp before rail generation [5000]
%   railEarExclusionMode  : 'sphere3d', 'projectedSpheres', or 'none' ['sphere3d']
%   railEdgeMarginMm      : omit rails within this distance of crop rim [0]
%   paintedExclusionVertexToleranceMm : exact painted-vertex match tolerance [1e-3]
%   earExclusionMode      : 'auto', 'always', 'never', or 'none' ['auto']
%   earExclusionFile      : explicit saved ear exclusion MAT file ['']
%   earElectrodePolicy    : warn/error/ignore if holder centers are inside ears ['warn']
%   implantExclusionFile  : saved implant/headpost exclusion MAT file(s) ['']
%   implantRailExclusionMode : 'projectedPolys' or 'none' ['projectedPolys']
%   implantElectrodePolicy: warn/error/ignore if holder centers are inside keepouts ['warn']
%   strapMode             : 'earRostral', 'bboxLateral', or 'none' ['earRostral']
%   strapBedClearanceMm   : lowest corrugated TPE strap underside above support [0.2]
%   strapCorrAmpMm        : chin-strap square-wave half-height [2]
%   strapCorrPitchMm      : chin-strap square-wave cycle length [7]
%   strapCorrStyle        : 'rectilinear' or 'swept' ['rectilinear']
%   strapCorrFitIntegerCycles : adjust pitch to whole cycles per section [true]
%   strapRostralOffsetMm  : offset rostral to ear sphere edge [0]
%   strapAnchorZBandMm    : prefer rail vertices near bed within this band [8]
%   strapRampAutoRise     : increase ramp rise to reach rail anchors [true]
%   strapRampAttachOverlapMm : extra vertical overlap at rail anchor [1]
%   holderSupportMode     : 'nearestRail' or 'none' ['nearestRail']
%   holderSupportCount    : support struts per holder [2]
%   holderSupportMinAngleDeg : desired support angle spread [90]
%   holderSupportRespectEarExclusions : keep holder supports out of ear rail keepouts [false]
%   holderSupportRespectImplantExclusions : keep holder supports out of implant keepouts [true]
%   holderBridgeMode      : add holder-holder stabilizers when needed ['auto']
%   manufacturingSurfaceMaxFaces : decimated cap mesh face target [5000]
%   manufacturingSurfaceCacheFile: decimated cap mesh cache ['']
%   skinCacheFile         : override layout.layout.skin.cacheFile ['']
%   forceManufacturingSurface    : rebuild decimated cap mesh [false]
%   voxelSizeMm           : voxel boolean resolution [0.5]
%   fuseCloseVox          : pre-carve close radius to bridge rail pinholes [0]
%   carveCloseVox         : post-hole-carve close radius [0]
%   preserveFusedTpeOccupancy : preserve fused voxel occupancy through carving [true]
%   zBedMm                : printer bed plane [0]
%   holderBedClearancePolicy : warn/error/ignore for bed-clipped holders ['warn']
%   holderMinBedClearanceMm  : minimum holder clearance above zBed [1]
%   strapElectrodePolicy  : warn/error/ignore for holder/strap overlap ['warn']
%   keepLargestPla        : keep only largest PLA component [false]
%   minFinalTpeComponentVoxels : remove smaller TPE components [0]
%   minFinalPlaComponentVoxels : remove smaller PLA components [0]
%   inpolyhedronPath      : file/folder containing inpolyhedron ['']
%   preflightOnly         : stop after component/anchor QC without STL [false]
%   qcMaxFaces            : max faces per mesh in QC display [[] = no decim]
%   showQcLabels          : show electrode labels in pre-fuse QC panel [true]
%   showFigures           : show QC figure [false]
%   saveFigures           : save QC figure [false]
%   saveMeshMat           : save mesh MAT next to STLs [false]
%   returnMeshes          : include meshes in returned struct [true]
%   verbose               : print progress [true]

    if nargin < 1 || isempty(layoutIn)
        error('acsBuildCapMakerManufacturingStl:MissingInput', ...
            'Provide a finalized capMaker layout struct or MAT report.');
    end

    opts = parseInputs(varargin{:});
    addLocalDependencies();
    if ~opts.preflightOnly
        opts.inpolyhedronFile = ensureInpolyhedronAvailable(opts);
    end

    layout = readLayout(layoutIn);
    [TRskinFull, skinSource] = loadSkinMesh(layout, opts);
    opts.skinSourceCacheFile = skinSource.cacheFile;
    [names, targetsMm, roleLabels] = selectedLayoutSites(layout, opts);

    opts = resolveOutputPaths(layout, skinSource, opts);
    ensureDir(opts.outputDir);
    requireWritableOutputs(opts);

    stageTimer = tic;
    [TRskin, manufacturingSurfaceInfo] = loadOrMakeManufacturingSurface( ...
        TRskinFull, opts);
    logElapsed(opts, 'Prepared decimated manufacturing scalp mesh', stageTimer);

    logMsg(opts, 'Building capMaker manufacturing geometry for %d electrode sites.', ...
        numel(names));
    logMsg(opts, 'Output folder: %s', opts.outputDir);

    totalTimer = tic;
    logMsg(opts, 'Making electrode holder template.');
    holderTR = makeHolderMesh(opts);
    stageTimer = tic;
    logMsg(opts, 'Placing electrode holders on skin mesh.');
    TRholderSkin = holderPlacementSurface(TRskinFull, TRskin, opts);
    holderSurfaceMm = snapTargetsToSurface(TRholderSkin, targetsMm);
    checkHolderSnapDistance(holderSurfaceMm, targetsMm, names, opts);
    [TRholders, holeTops, holeBottoms, holderInfo] = placeElectrodeArrayOnSurface( ...
        TRholderSkin, holderTR, targetsMm, opts.holderEmbedMm, ...
        'NormalMode', opts.holderNormalMode, ...
        'SmoothNormalRadiusMm', opts.holderSmoothNormalRadiusMm, ...
        'NormalDeviationThresholdDeg', opts.holderNormalDeviationThresholdDeg);
    checkHolderBedClearance(holderInfo, names, opts);
    logElapsed(opts, 'Placed electrode holders', stageTimer);

    stageTimer = tic;
    logMsg(opts, 'Resolving ear exclusion spheres.');
    earExclusions = resolveEarExclusions(layout, skinSource, opts);
    checkLayoutAgainstEarExclusions(holderSurfaceMm, names, earExclusions, opts);
    logMsg(opts, 'Resolving ear rail exclusions.');
    [earSphereCenters, earSphereRadii] = railEarSpheres(earExclusions, opts);
    earPolys = railEarPolys(earExclusions, opts);
    paintedVertexPoints = paintedRailVertexExclusionPoints(earExclusions);
    logMsg(opts, 'Resolving implant exclusion zones.');
    implantExclusions = resolveImplantExclusions(opts);
    implantPolys = railImplantPolys(implantExclusions, opts);
    railExcludePolys = [earPolys(:); implantPolys(:)]';
    holderSupportExcludePolys = holderSupportExclusionPolys( ...
        earPolys, implantPolys, opts);
    checkLayoutAgainstImplantExclusions(holderSurfaceMm, names, implantPolys, opts);
    logElapsed(opts, 'Resolved ear exclusions', stageTimer);

    TRrailSkin = decimateTriangulation(TRskin, opts.railSurfaceMaxFaces, opts, ...
        'rail source mesh');
    stageTimer = tic;
    logMsg(opts, 'Building edge rails from rail source mesh.');
    [TRrailsBase, railBuildInfo] = makeEdgeRails(TRrailSkin, ...
        opts.railWidthMm, opts.railHeightMm, ...
        opts.railEmbedFraction, opts.railMinLengthMm, ...
        opts.railZThresholdMm, [], ...
        'PerimeterFactor', opts.railPerimeterFactor, ...
        'BoundaryMarginMm', opts.railEdgeMarginMm, ...
        'EarExcludePolys', railExcludePolys, ...
        'SphereExcludeCenters', earSphereCenters, ...
        'SphereExcludeRadii', earSphereRadii, ...
        'VertexExcludePoints', paintedVertexPoints, ...
        'VertexExcludeToleranceMm', opts.paintedExclusionVertexToleranceMm, ...
        'Verbose', opts.verbose);
    logElapsed(opts, 'Built edge rails', stageTimer);

    stageTimer = tic;
    logMsg(opts, 'Preparing strap occupancy and anchor heuristics.');
    strap = makeStrapOccupancy(TRrailsBase, TRskin, TRholders, earExclusions, opts);
    checkHoldersAgainstStrapOccupancy(holderInfo, names, strap, opts);
    logElapsed(opts, 'Built strap occupancy functions', stageTimer);

    stageTimer = tic;
    logMsg(opts, 'Adding holder support rails.');
    TRholderSupports = makeHolderSupportRails(holderSurfaceMm, names, ...
        TRrailsBase, opts, holderSupportExcludePolys);
    TRrails = concatTriangulations({TRrailsBase, TRholderSupports});
    logElapsed(opts, 'Added holder support rails', stageTimer);

    if opts.preflightOnly
        out = makePreflightOutput(layout, TRskin, TRrailSkin, TRholders, TRrails, ...
            targetsMm, names, roleLabels, earExclusions, implantExclusions, ...
            strap, TRholderSupports, holderInfo, manufacturingSurfaceInfo, ...
            railBuildInfo, opts, totalTimer);
        return;
    end

    fuseOpts = struct( ...
        'voxelSize', opts.voxelSizeMm, ...
        'padVox', opts.padVox, ...
        'zBed', opts.zBedMm, ...
        'tol', opts.inpolyhedronTol, ...
        'extraOccFns', {strap.occFns}, ...
        'extraPoints', strap.extraPoints, ...
        'protectExtraOccFns', true, ...
        'closeVox', opts.fuseCloseVox, ...
        'manifoldize', opts.manifoldize, ...
        'manifoldizeProtect6', opts.manifoldizeProtect6);

    logMsg(opts, 'Fusing holders, rails, and strap occupancy.');
    stageTimer = tic;
    [TRtpeRaw, occTpeRaw] = fuseTriListVoxel({TRholders, TRrails}, fuseOpts);
    logElapsed(opts, 'Fused TPE occupancy', stageTimer);

    TRholeKeepoutUnion = makeHoleKeepoutUnion(holeTops, holeBottoms, opts);

    carveOpts = struct( ...
        'voxelSize', opts.voxelSizeMm, ...
        'keepLargest', opts.keepLargestTpe, ...
        'zBed', opts.zBedMm, ...
        'tol', opts.inpolyhedronTol, ...
        'closeVox', opts.carveCloseVox, ...
        'returnMesh', false);
    if opts.preserveFusedTpeOccupancy
        carveBase = occTpeRaw;
        logMsg(opts, 'Carving gel/electrode keepouts from fused TPE raster.');
    else
        carveBase = TRtpeRaw;
        logMsg(opts, 'Carving gel/electrode keepouts from revoxelized TPE mesh.');
    end
    stageTimer = tic;
    [~, occTpeCarved] = carvePVA(carveBase, TRholeKeepoutUnion, carveOpts);
    logElapsed(opts, 'Carved TPE keepouts', stageTimer);

    plaOpts = struct( ...
        'marginMM', opts.plaMarginMm, ...
        'closeXYVox', opts.plaCloseXYVox, ...
        'keepLargestXY', opts.plaKeepLargestXY);
    stageTimer = tic;
    occPla = plaUnderfillFromTPE(occTpeCarved, [], plaOpts);
    logElapsed(opts, 'Built PLA underfill occupancy', stageTimer);

    stageTimer = tic;
    cropOptsTpe = struct( ...
        'keepLargest', opts.keepLargestTpe, ...
        'closeVox', opts.cropCloseVox, ...
        'minComponentVoxels', opts.minFinalTpeComponentVoxels, ...
        'clearShell', true);
    cropOptsPla = cropOptsTpe;
    cropOptsPla.keepLargest = opts.keepLargestPla;
    cropOptsPla.minComponentVoxels = opts.minFinalPlaComponentVoxels;
    [TRtpeFinal, occTpeCrop] = cropOccOutAABB_watertight( ...
        occTpeCarved, opts.cropBoxMin, opts.cropBoxMax, cropOptsTpe);
    [TRplaFinal, occPlaCrop] = cropOccOutAABB_watertight( ...
        occPla, opts.cropBoxMin, opts.cropBoxMax, cropOptsPla);
    logElapsed(opts, 'Remeshed final TPE/PLA crops', stageTimer);

    logMsg(opts, 'Writing STL files.');
    stageTimer = tic;
    stlwrite_boxsafe(TRtpeFinal, opts.tpeStlFile);
    stlwrite_boxsafe(TRplaFinal, opts.plaStlFile);
    logElapsed(opts, 'Wrote STL files', stageTimer);

    meshInfo = struct();
    meshInfo.skin = meshStats(TRskin);
    meshInfo.holders = meshStats(TRholders);
    meshInfo.rails = meshStats(TRrails);
    meshInfo.railBuild = railBuildInfo;
    meshInfo.tpeRaw = meshStats(TRtpeRaw);
    meshInfo.tpe = meshStats(TRtpeFinal);
    meshInfo.pla = meshStats(TRplaFinal);
    meshInfo.tpeClosure = checkMeshClosed(TRtpeFinal);
    meshInfo.plaClosure = checkMeshClosed(TRplaFinal);
    meshInfo.tpeComponents = occupancyComponentStats(occTpeCrop.occ);
    meshInfo.plaComponents = occupancyComponentStats(occPlaCrop.occ);

    qcFile = '';
    fig = [];
    if opts.showFigures || opts.saveFigures
        figVisible = 'off';
        if opts.showFigures
            figVisible = 'on';
        end
        logMsg(opts, 'Building manufacturing QC figure.');
        fig = makeQcFigure(TRskin, TRholders, TRrails, TRtpeFinal, TRplaFinal, ...
            targetsMm, names, roleLabels, earExclusions, implantExclusions, ...
            strap, holderInfo, opts, figVisible);
        if opts.saveFigures
            qcFile = fullfile(opts.outputDir, [opts.manufacturingTag '_qc.png']);
            saveQcFigure(fig, qcFile);
        end
        if ~opts.showFigures
            close(fig);
            fig = [];
        end
    end

    out = struct();
    out.createdOn = char(datetime('now'));
    out.manufacturingTag = opts.manufacturingTag;
    out.outputDir = opts.outputDir;
    out.tpeStlFile = opts.tpeStlFile;
    out.plaStlFile = opts.plaStlFile;
    out.reportMat = opts.reportMat;
    out.meshMat = opts.meshMat;
    out.qcFigure = qcFile;
    out.names = names;
    out.siteRoles = roleLabels;
    tesInfo = selectedTesInfo(layout, names);
    out.tesNames = tesInfo.tesNames;
    out.sourceTesNames = tesInfo.sourceTesNames;
    out.tesCurrentsMa = tesInfo.tesCurrentsMa;
    out.layoutCoordinatesMm = targetsMm;
    out.holderSurfaceCoordinatesMm = holderSurfacePointsFromInfo(holderInfo, targetsMm);
    out.holderInfo = holderInfo;
    out.skinSource = skinSource;
    out.manufacturingSurface = manufacturingSurfaceInfo;
    out.earExclusions = compactEarExclusions(earExclusions);
    out.implantExclusions = compactImplantExclusions(implantExclusions);
    out.strap = stripStrapFns(strap);
    out.holderSupports = meshStats(TRholderSupports);
    out.railBuildInfo = railBuildInfo;
    out.options = opts;
    out.meshInfo = meshInfo;
    if opts.returnMeshes
        out.meshes = struct( ...
            'skin', TRskin, ...
            'holders', TRholders, ...
            'rails', TRrails, ...
            'tpe', TRtpeFinal, ...
            'pla', TRplaFinal);
    end
    if isgraphics(fig)
        out.figure = fig;
    end

    if opts.saveMeshMat
        meshes = struct( ...
            'TRskin', TRskin, ...
            'TRholders', TRholders, ...
            'TRrails', TRrails, ...
            'TRtpe', TRtpeFinal, ...
            'TRpla', TRplaFinal, ...
            'occTpeRaw', occTpeRaw, ...
            'occTpeCarved', occTpeCarved, ...
            'occTpeCrop', occTpeCrop, ...
            'occPlaCrop', occPlaCrop); %#ok<NASGU>
        save(opts.meshMat, 'meshes', '-v7.3');
    end

    outFull = out;
    out = stripForSave(outFull); %#ok<NASGU>
    outToSave = out; %#ok<NASGU>
    outSaved = out; %#ok<NASGU>
    save(opts.reportMat, 'out', 'outToSave', 'outSaved', '-v7.3');
    out = outFull;
    logMsg(opts, 'Saved manufacturing report: %s', opts.reportMat);
    logElapsed(opts, 'Completed manufacturing build', totalTimer);
end

function opts = parseInputs(varargin)
    p = inputParser;
    p.FunctionName = 'acsBuildCapMakerManufacturingStl';
    addParameter(p, 'manufacturingTag', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'outputDir', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'force', false, @isBoolLike);
    addParameter(p, 'electrodeNames', {}, @(x) iscell(x) || ischar(x) || isstring(x));
    addParameter(p, 'holderInsideDiaMm', 4, @isPositiveScalar);
    addParameter(p, 'holderOutsideDiaMm', 12, @isPositiveScalar);
    addParameter(p, 'holderHeightMm', 7, @isPositiveScalar);
    addParameter(p, 'holderEmbedMm', 0.3, @isNonnegativeScalar);
    addParameter(p, 'holderNormalMode', 'autoSmooth', ...
        @(x) ischar(x) || isstring(x));
    addParameter(p, 'holderSmoothNormalRadiusMm', 6, @isPositiveScalar);
    addParameter(p, 'holderNormalDeviationThresholdDeg', 25, ...
        @isNonnegativeScalar);
    addParameter(p, 'holderPlacementSurfaceMode', 'full', ...
        @(x) ischar(x) || isstring(x));
    addParameter(p, 'holderSnapWarnDistanceMm', 1, @isNonnegativeScalar);
    addParameter(p, 'holderSnapErrorDistanceMm', 3, @isNonnegativeScalar);
    addParameter(p, 'holeInsideDiaMm', [], @(x) isempty(x) || isPositiveScalar(x));
    addParameter(p, 'holeKeepoutMode', 'flared', @(x) ischar(x) || isstring(x));
    addParameter(p, 'holeClearanceMm', [], @(x) isempty(x) || isNonnegativeScalar(x));
    addParameter(p, 'holeBoreClearanceMm', 0.1, @isNonnegativeScalar);
    addParameter(p, 'holeScalpClearanceMm', [], @(x) isempty(x) || isNonnegativeScalar(x));
    addParameter(p, 'holeTopExtendMm', 1.5, @isNonnegativeScalar);
    addParameter(p, 'holeScalpExtendMm', 6, @isNonnegativeScalar);
    addParameter(p, 'holeScalpFlareDiaMm', [], @(x) isempty(x) || isPositiveScalar(x));
    addParameter(p, 'holeCylinderSides', 32, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 8);
    addParameter(p, 'railWidthMm', 2, @isPositiveScalar);
    addParameter(p, 'railHeightMm', 2, @isPositiveScalar);
    addParameter(p, 'railEmbedFraction', 0.5, @isNonnegativeScalar);
    addParameter(p, 'railMinLengthMm', 0, @isNonnegativeScalar);
    addParameter(p, 'railZThresholdMm', 15, @isNonnegativeScalar);
    addParameter(p, 'railPerimeterFactor', 1.5, @isPositiveScalar);
    addParameter(p, 'railEdgeMarginMm', 0, @isNonnegativeScalar);
    addParameter(p, 'railSurfaceMaxFaces', 5000, ...
        @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x > 0));
    addParameter(p, 'railEarExclusionMode', 'sphere3d', @(x) ischar(x) || isstring(x));
    addParameter(p, 'paintedExclusionRailMarginMm', 2, @isNonnegativeScalar);
    addParameter(p, 'paintedExclusionVertexToleranceMm', 1e-3, ...
        @isNonnegativeScalar);
    addParameter(p, 'earExclusionMode', 'auto', @(x) ischar(x) || isstring(x));
    addParameter(p, 'earExclusionFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'earElectrodePolicy', 'warn', ...
        @(x) ischar(x) || isstring(x));
    addParameter(p, 'implantExclusionFile', '', ...
        @(x) ischar(x) || isstring(x) || iscell(x));
    addParameter(p, 'implantRailExclusionMode', 'projectedPolys', ...
        @(x) ischar(x) || isstring(x));
    addParameter(p, 'implantElectrodePolicy', 'warn', ...
        @(x) ischar(x) || isstring(x));
    addParameter(p, 'strapMode', 'earRostral', @(x) ischar(x) || isstring(x));
    addParameter(p, 'strapBedClearanceMm', 0.2, @isNonnegativeScalar);
    addParameter(p, 'strapCorrAmpMm', 2, @isNonnegativeScalar);
    addParameter(p, 'strapCorrPitchMm', 7, @isPositiveScalar);
    addParameter(p, 'strapCorrStyle', 'rectilinear', ...
        @(x) ischar(x) || isstring(x));
    addParameter(p, 'strapCorrFitIntegerCycles', true, @isBoolLike);
    addParameter(p, 'strapRostralOffsetMm', 0, @isNonnegativeScalar);
    addParameter(p, 'strapAnchorZBandMm', 8, @isPositiveScalar);
    addParameter(p, 'strapRampAutoRise', true, @isBoolLike);
    addParameter(p, 'strapRampAttachOverlapMm', 1, @isNonnegativeScalar);
    addParameter(p, 'holderSupportMode', 'nearestRail', @(x) ischar(x) || isstring(x));
    addParameter(p, 'holderSupportCount', 2, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0);
    addParameter(p, 'holderSupportMinAngleDeg', 90, @isNonnegativeScalar);
    addParameter(p, 'holderSupportRespectEarExclusions', false, @isBoolLike);
    addParameter(p, 'holderSupportRespectImplantExclusions', true, @isBoolLike);
    addParameter(p, 'holderBridgeMode', 'auto', @(x) ischar(x) || isstring(x));
    addParameter(p, 'holderBridgeMaxLengthMm', 35, ...
        @(x) isempty(x) || isPositiveScalar(x));
    addParameter(p, 'holderSupportWidthMm', [], @(x) isempty(x) || isPositiveScalar(x));
    addParameter(p, 'holderSupportHeightMm', [], @(x) isempty(x) || isPositiveScalar(x));
    addParameter(p, 'holderSupportEndpointSeparationMm', [], ...
        @(x) isempty(x) || isNonnegativeScalar(x));
    addParameter(p, 'holderSupportWarnLengthMm', 20, ...
        @(x) isempty(x) || isPositiveScalar(x));
    addParameter(p, 'manufacturingSurfaceMaxFaces', 5000, ...
        @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x > 0));
    addParameter(p, 'manufacturingSurfaceCacheFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'skinCacheFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'forceManufacturingSurface', false, @isBoolLike);
    addParameter(p, 'strapOptions', struct(), @(x) isempty(x) || isstruct(x));
    addParameter(p, 'strapFrameOptions', struct(), @(x) isempty(x) || isstruct(x));
    addParameter(p, 'voxelSizeMm', 0.5, @isPositiveScalar);
    addParameter(p, 'fuseCloseVox', 0, @isNonnegativeScalar);
    addParameter(p, 'carveCloseVox', 0, @isNonnegativeScalar);
    addParameter(p, 'preserveFusedTpeOccupancy', true, @isBoolLike);
    addParameter(p, 'padVox', 8, @isPositiveScalar);
    addParameter(p, 'zBedMm', 0, @(x) isnumeric(x) && isscalar(x) && isfinite(x));
    addParameter(p, 'holderBedClearancePolicy', 'warn', ...
        @(x) ischar(x) || isstring(x));
    addParameter(p, 'holderMinBedClearanceMm', 1, @isNonnegativeScalar);
    addParameter(p, 'strapElectrodePolicy', 'warn', ...
        @(x) ischar(x) || isstring(x));
    addParameter(p, 'strapElectrodeSampleRadiusMm', [], ...
        @(x) isempty(x) || isPositiveScalar(x));
    addParameter(p, 'strapElectrodeSampleCount', 12, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 4);
    addParameter(p, 'inpolyhedronTol', 1e-9, @isPositiveScalar);
    addParameter(p, 'inpolyhedronPath', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'manifoldize', true, @isBoolLike);
    addParameter(p, 'manifoldizeProtect6', true, @isBoolLike);
    addParameter(p, 'keepLargestTpe', true, @isBoolLike);
    addParameter(p, 'keepoutOptions', struct(), @(x) isempty(x) || isstruct(x));
    addParameter(p, 'plaMarginMm', 2, @isNonnegativeScalar);
    addParameter(p, 'plaCloseXYVox', 2, @isNonnegativeScalar);
    addParameter(p, 'plaKeepLargestXY', false, @isBoolLike);
    addParameter(p, 'keepLargestPla', false, @isBoolLike);
    addParameter(p, 'minFinalTpeComponentVoxels', 0, @isNonnegativeScalar);
    addParameter(p, 'minFinalPlaComponentVoxels', 0, @isNonnegativeScalar);
    addParameter(p, 'cropBoxMin', [-inf -inf 0], @(x) isnumeric(x) && numel(x) == 3);
    addParameter(p, 'cropBoxMax', [inf inf inf], @(x) isnumeric(x) && numel(x) == 3);
    addParameter(p, 'cropCloseVox', 0, @isNonnegativeScalar);
    addParameter(p, 'preflightOnly', false, @isBoolLike);
    addParameter(p, 'qcMaxFaces', 12000, ...
        @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x > 0));
    addParameter(p, 'showQcLabels', true, @isBoolLike);
    addParameter(p, 'showFigures', false, @isBoolLike);
    addParameter(p, 'saveFigures', false, @isBoolLike);
    addParameter(p, 'saveMeshMat', false, @isBoolLike);
    addParameter(p, 'returnMeshes', true, @isBoolLike);
    addParameter(p, 'verbose', true, @isBoolLike);
    parse(p, varargin{:});

    opts = p.Results;
    opts.manufacturingTag = char(opts.manufacturingTag);
    opts.outputDir = expandUserPath(char(opts.outputDir));
    opts.force = logical(opts.force);
    opts.electrodeNames = normalizeNameInput(opts.electrodeNames);
    opts.holderInsideDiaMm = double(opts.holderInsideDiaMm);
    opts.holderOutsideDiaMm = double(opts.holderOutsideDiaMm);
    opts.holderHeightMm = double(opts.holderHeightMm);
    opts.holderEmbedMm = double(opts.holderEmbedMm);
    opts.holderNormalMode = normalizeHolderNormalMode(opts.holderNormalMode);
    opts.holderSmoothNormalRadiusMm = double(opts.holderSmoothNormalRadiusMm);
    opts.holderNormalDeviationThresholdDeg = double( ...
        opts.holderNormalDeviationThresholdDeg);
    opts.holderPlacementSurfaceMode = normalizeHolderPlacementSurfaceMode( ...
        opts.holderPlacementSurfaceMode);
    opts.holderSnapWarnDistanceMm = double(opts.holderSnapWarnDistanceMm);
    opts.holderSnapErrorDistanceMm = double(opts.holderSnapErrorDistanceMm);
    if isempty(opts.holeInsideDiaMm)
        opts.holeInsideDiaMm = opts.holderInsideDiaMm;
    else
        opts.holeInsideDiaMm = double(opts.holeInsideDiaMm);
    end
    opts.holeKeepoutMode = normalizeHoleKeepoutMode(opts.holeKeepoutMode);
    if isempty(opts.holeClearanceMm)
        opts.holeClearanceMm = max(0.5, opts.voxelSizeMm);
    else
        opts.holeClearanceMm = double(opts.holeClearanceMm);
    end
    opts.holeBoreClearanceMm = double(opts.holeBoreClearanceMm);
    if isempty(opts.holeScalpClearanceMm)
        opts.holeScalpClearanceMm = opts.holeClearanceMm;
    else
        opts.holeScalpClearanceMm = double(opts.holeScalpClearanceMm);
    end
    opts.holeTopExtendMm = double(opts.holeTopExtendMm);
    opts.holeScalpExtendMm = double(opts.holeScalpExtendMm);
    if isempty(opts.holeScalpFlareDiaMm)
        opts.holeScalpFlareDiaMm = max(opts.holeInsideDiaMm + 2, 6);
    else
        opts.holeScalpFlareDiaMm = double(opts.holeScalpFlareDiaMm);
    end
    opts.holeCylinderSides = round(double(opts.holeCylinderSides));
    opts.railWidthMm = double(opts.railWidthMm);
    opts.railHeightMm = double(opts.railHeightMm);
    opts.railEmbedFraction = double(opts.railEmbedFraction);
    opts.railMinLengthMm = double(opts.railMinLengthMm);
    opts.railZThresholdMm = double(opts.railZThresholdMm);
    opts.railPerimeterFactor = double(opts.railPerimeterFactor);
    opts.railEdgeMarginMm = double(opts.railEdgeMarginMm);
    if isempty(opts.railSurfaceMaxFaces)
        opts.railSurfaceMaxFaces = [];
    else
        opts.railSurfaceMaxFaces = round(double(opts.railSurfaceMaxFaces));
    end
    opts.railEarExclusionMode = normalizeRailEarMode(opts.railEarExclusionMode);
    opts.paintedExclusionRailMarginMm = double(opts.paintedExclusionRailMarginMm);
    opts.paintedExclusionVertexToleranceMm = double( ...
        opts.paintedExclusionVertexToleranceMm);
    opts.earExclusionMode = normalizeEarMode(opts.earExclusionMode);
    opts.earExclusionFile = expandUserPath(char(opts.earExclusionFile));
    opts.earElectrodePolicy = normalizeImplantElectrodePolicy(opts.earElectrodePolicy);
    opts.implantExclusionFile = normalizeFileList(opts.implantExclusionFile);
    opts.implantRailExclusionMode = normalizeImplantRailMode(opts.implantRailExclusionMode);
    opts.implantElectrodePolicy = normalizeImplantElectrodePolicy(opts.implantElectrodePolicy);
    opts.strapMode = normalizeStrapMode(opts.strapMode);
    opts.strapBedClearanceMm = double(opts.strapBedClearanceMm);
    opts.strapCorrAmpMm = double(opts.strapCorrAmpMm);
    opts.strapCorrPitchMm = double(opts.strapCorrPitchMm);
    opts.strapCorrStyle = normalizeStrapCorrStyle(opts.strapCorrStyle);
    opts.strapCorrFitIntegerCycles = logical(opts.strapCorrFitIntegerCycles);
    opts.strapRostralOffsetMm = double(opts.strapRostralOffsetMm);
    opts.strapAnchorZBandMm = double(opts.strapAnchorZBandMm);
    opts.strapRampAutoRise = logical(opts.strapRampAutoRise);
    opts.strapRampAttachOverlapMm = double(opts.strapRampAttachOverlapMm);
    opts.holderSupportMode = normalizeHolderSupportMode(opts.holderSupportMode);
    opts.holderSupportCount = round(double(opts.holderSupportCount));
    opts.holderSupportMinAngleDeg = double(opts.holderSupportMinAngleDeg);
    opts.holderSupportRespectEarExclusions = logical(opts.holderSupportRespectEarExclusions);
    opts.holderSupportRespectImplantExclusions = logical(opts.holderSupportRespectImplantExclusions);
    opts.holderBridgeMode = normalizeHolderBridgeMode(opts.holderBridgeMode);
    if isempty(opts.holderBridgeMaxLengthMm)
        opts.holderBridgeMaxLengthMm = inf;
    else
        opts.holderBridgeMaxLengthMm = double(opts.holderBridgeMaxLengthMm);
    end
    if isempty(opts.holderSupportWidthMm)
        opts.holderSupportWidthMm = 1.25 * opts.railWidthMm;
    else
        opts.holderSupportWidthMm = double(opts.holderSupportWidthMm);
    end
    if isempty(opts.holderSupportHeightMm)
        opts.holderSupportHeightMm = opts.railHeightMm;
    else
        opts.holderSupportHeightMm = double(opts.holderSupportHeightMm);
    end
    if isempty(opts.holderSupportEndpointSeparationMm)
        opts.holderSupportEndpointSeparationMm = 0.5 * opts.holderOutsideDiaMm;
    else
        opts.holderSupportEndpointSeparationMm = double(opts.holderSupportEndpointSeparationMm);
    end
    if isempty(opts.holderSupportWarnLengthMm)
        opts.holderSupportWarnLengthMm = inf;
    else
        opts.holderSupportWarnLengthMm = double(opts.holderSupportWarnLengthMm);
    end
    if isempty(opts.manufacturingSurfaceMaxFaces)
        opts.manufacturingSurfaceMaxFaces = [];
    else
        opts.manufacturingSurfaceMaxFaces = round(double(opts.manufacturingSurfaceMaxFaces));
    end
    opts.manufacturingSurfaceCacheFile = expandUserPath(char(opts.manufacturingSurfaceCacheFile));
    opts.skinCacheFile = expandUserPath(char(opts.skinCacheFile));
    opts.forceManufacturingSurface = logical(opts.forceManufacturingSurface);
    if isempty(opts.strapOptions), opts.strapOptions = struct(); end
    if isempty(opts.strapFrameOptions), opts.strapFrameOptions = struct(); end
    opts.voxelSizeMm = double(opts.voxelSizeMm);
    opts.fuseCloseVox = round(double(opts.fuseCloseVox));
    opts.carveCloseVox = round(double(opts.carveCloseVox));
    opts.preserveFusedTpeOccupancy = logical(opts.preserveFusedTpeOccupancy);
    opts.padVox = round(double(opts.padVox));
    opts.zBedMm = double(opts.zBedMm);
    opts.holderBedClearancePolicy = normalizeImplantElectrodePolicy( ...
        opts.holderBedClearancePolicy);
    opts.holderMinBedClearanceMm = double(opts.holderMinBedClearanceMm);
    opts.strapElectrodePolicy = normalizeImplantElectrodePolicy( ...
        opts.strapElectrodePolicy);
    if isempty(opts.strapElectrodeSampleRadiusMm)
        opts.strapElectrodeSampleRadiusMm = 0.55 * opts.holderOutsideDiaMm;
    else
        opts.strapElectrodeSampleRadiusMm = double(opts.strapElectrodeSampleRadiusMm);
    end
    opts.strapElectrodeSampleCount = round(double(opts.strapElectrodeSampleCount));
    opts.inpolyhedronTol = double(opts.inpolyhedronTol);
    opts.inpolyhedronPath = expandUserPath(char(opts.inpolyhedronPath));
    opts.inpolyhedronFile = '';
    opts.manifoldize = logical(opts.manifoldize);
    opts.manifoldizeProtect6 = logical(opts.manifoldizeProtect6);
    opts.keepLargestTpe = logical(opts.keepLargestTpe);
    if isempty(opts.keepoutOptions), opts.keepoutOptions = struct(); end
    opts.plaMarginMm = double(opts.plaMarginMm);
    opts.plaCloseXYVox = round(double(opts.plaCloseXYVox));
    opts.plaKeepLargestXY = logical(opts.plaKeepLargestXY);
    opts.keepLargestPla = logical(opts.keepLargestPla);
    opts.minFinalTpeComponentVoxels = round(double(opts.minFinalTpeComponentVoxels));
    opts.minFinalPlaComponentVoxels = round(double(opts.minFinalPlaComponentVoxels));
    opts.cropBoxMin = double(opts.cropBoxMin(:)');
    opts.cropBoxMax = double(opts.cropBoxMax(:)');
    opts.cropCloseVox = round(double(opts.cropCloseVox));
    opts.preflightOnly = logical(opts.preflightOnly);
    if isempty(opts.qcMaxFaces)
        opts.qcMaxFaces = [];
    else
        opts.qcMaxFaces = round(double(opts.qcMaxFaces));
    end
    opts.showQcLabels = logical(opts.showQcLabels);
    opts.showFigures = logical(opts.showFigures);
    opts.saveFigures = logical(opts.saveFigures);
    opts.saveMeshMat = logical(opts.saveMeshMat);
    opts.returnMeshes = logical(opts.returnMeshes);
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
    addpath(fullfile(repoRoot, 'capMaker', 'geometry'));
end

function inpolyFile = ensureInpolyhedronAvailable(opts)
    inpolyFile = which('inpolyhedron');
    if ~isempty(inpolyFile)
        logMsg(opts, 'Using inpolyhedron: %s', inpolyFile);
        return;
    end

    candidates = inpolyhedronCandidates(opts);
    checked = {};
    for i = 1:numel(candidates)
        [added, checkedPath] = addInpolyhedronCandidate(candidates(i));
        if ~isempty(checkedPath)
            checked{end + 1} = checkedPath; %#ok<AGROW>
        end
        if added
            inpolyFile = which('inpolyhedron');
            if ~isempty(inpolyFile)
                logMsg(opts, 'Using inpolyhedron: %s', inpolyFile);
                return;
            end
        end
    end

    if isempty(checked)
        checkedText = 'No candidate paths were available.';
    else
        checkedText = sprintf('Candidate paths checked:\n  %s', ...
            strjoin(checked, sprintf('\n  ')));
    end

    msg = sprintf([ ...
        'inpolyhedron is required for full manufacturing STL voxel fusion, ', ...
        'but it is not on the MATLAB path.\n\n%s\n\n', ...
        'Fix this by either adding inpolyhedron.m to your MATLAB path, ', ...
        'passing ''inpolyhedronPath'', setting ACS_INPOLYHEDRON_PATH, ', ...
        'or adding "inpolyhedronPath" to local.paths.json.\n\n', ...
        'For this lab setup, the likely path is:\n  %s'], ...
        checkedText, likelyBoxInpolyhedronPath());
    error('acsBuildCapMakerManufacturingStl:MissingInpolyhedron', '%s', msg);
end

function candidates = inpolyhedronCandidates(opts)
    candidates = struct('path', {}, 'recursive', {});
    candidates = appendPathCandidate(candidates, opts.inpolyhedronPath, true);
    candidates = appendPathCandidate(candidates, getenv('ACS_INPOLYHEDRON_PATH'), true);
    candidates = appendPathCandidate(candidates, getenv('ACS_MATLAB_UTILS_ROOT'), true);

    cfg = readLocalPathsConfig();
    candidates = appendConfigCandidate(candidates, cfg, 'inpolyhedronPath', true);
    candidates = appendConfigCandidate(candidates, cfg, 'matlabUtilitiesRoot', true);
    candidates = appendConfigCandidate(candidates, cfg, 'externalMatlabUtilitiesRoot', true);

    try
        P = acsPaths();
        if ~isempty(P.boxRoot)
            candidates = appendPathCandidate(candidates, ...
                fullfile(P.boxRoot, 'SnyderLab', 'Matlab Routines', ...
                    'utils', 'inpolyhedron.m'), false);
            candidates = appendPathCandidate(candidates, ...
                fullfile(P.boxRoot, 'SnyderLab', 'Matlab Routines', ...
                    'utils'), false);
        end
    catch
        % acsPaths is best-effort here; the explicit/env/config candidates
        % above are enough for users with nonstandard setups.
    end
end

function candidates = appendConfigCandidate(candidates, cfg, fieldName, recursive)
    if isstruct(cfg) && isfield(cfg, fieldName) && ~isempty(cfg.(fieldName))
        candidates = appendPathCandidate(candidates, cfg.(fieldName), recursive);
    end
end

function candidates = appendPathCandidate(candidates, pathValue, recursive)
    if nargin < 3
        recursive = false;
    end
    if isempty(pathValue)
        return;
    end
    pathValue = expandUserPath(char(pathValue));
    if isempty(pathValue)
        return;
    end
    if ~isempty(candidates) && any(strcmpi(pathValue, {candidates.path}))
        return;
    end
    candidates(end + 1).path = pathValue; %#ok<AGROW>
    candidates(end).recursive = logical(recursive);
end

function cfg = readLocalPathsConfig()
    cfg = struct();
    try
        P = acsPaths();
        cfgFile = P.configFile;
    catch
        cfgFile = '';
    end
    if isempty(cfgFile) || exist(cfgFile, 'file') ~= 2
        return;
    end
    try
        cfg = jsondecode(fileread(cfgFile));
    catch ME
        warning('acsBuildCapMakerManufacturingStl:BadLocalPathsJson', ...
            'Could not read local paths config %s: %s', cfgFile, ME.message);
        cfg = struct();
    end
end

function [added, checkedPath] = addInpolyhedronCandidate(candidate)
    added = false;
    checkedPath = '';
    pathValue = candidate.path;
    if isempty(pathValue)
        return;
    end
    checkedPath = pathValue;

    if exist(pathValue, 'file') == 2
        [folderName, fileBase, fileExt] = fileparts(pathValue);
        if strcmpi([fileBase fileExt], 'inpolyhedron.m')
            addpath(folderName);
            added = true;
        end
        return;
    end

    if exist(pathValue, 'dir') ~= 7
        return;
    end

    directFile = fullfile(pathValue, 'inpolyhedron.m');
    if exist(directFile, 'file') == 2
        addpath(pathValue);
        added = true;
        return;
    end

    if candidate.recursive
        hit = findFirstInpolyhedron(pathValue);
        if ~isempty(hit)
            addpath(fileparts(hit));
            checkedPath = sprintf('%s (recursive)', pathValue);
            added = true;
        end
    end
end

function fileName = findFirstInpolyhedron(rootDir)
    fileName = '';
    try
        hits = dir(fullfile(rootDir, '**', 'inpolyhedron.m'));
    catch
        hits = [];
    end
    for i = 1:numel(hits)
        if ~hits(i).isdir
            fileName = fullfile(hits(i).folder, hits(i).name);
            return;
        end
    end
end

function pathText = likelyBoxInpolyhedronPath()
    try
        P = acsPaths();
        boxRoot = P.boxRoot;
    catch
        boxRoot = '';
    end
    if isempty(boxRoot)
        boxRoot = fullfile(getenv('USERPROFILE'), 'Box');
    end
    pathText = fullfile(boxRoot, 'SnyderLab', 'Matlab Routines', ...
        'utils', 'inpolyhedron.m');
end

function layout = readLayout(value)
    if isstruct(value)
        layout = value;
        return;
    end
    if ~(ischar(value) || isstring(value))
        error('acsBuildCapMakerManufacturingStl:BadLayout', ...
            'Layout input must be a struct or MAT report.');
    end
    fileName = expandUserPath(char(value));
    if exist(fileName, 'file') ~= 2
        error('acsBuildCapMakerManufacturingStl:LayoutNotFound', ...
            'Layout report not found: %s', fileName);
    end
    S = load(fileName);
    layout = firstStruct(S);
end

function value = firstStruct(S)
    preferred = {'out', 'outToSave', 'outSaved', 'combinedLayout', 'layout'};
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
    error('acsBuildCapMakerManufacturingStl:NoStructInMat', ...
        'MAT report does not contain a layout struct.');
end

function [TRskin, source] = loadSkinMesh(layout, opts)
    source = struct('cacheFile', '', 'label', '');
    if nargin >= 2 && isfield(opts, 'skinCacheFile') && ~isempty(opts.skinCacheFile)
        source.cacheFile = opts.skinCacheFile;
    else
        if ~isfield(layout, 'layout') || ~isfield(layout.layout, 'skin') || ...
                ~isfield(layout.layout.skin, 'cacheFile') || ...
                isempty(layout.layout.skin.cacheFile)
            error('acsBuildCapMakerManufacturingStl:MissingSkinCache', ...
                'Layout does not report layout.skin.cacheFile.');
        end
        source.cacheFile = expandUserPath(char(layout.layout.skin.cacheFile));
    end
    if exist(source.cacheFile, 'file') ~= 2
        error('acsBuildCapMakerManufacturingStl:SkinCacheNotFound', ...
            'Skin mesh cache not found: %s', source.cacheFile);
    end
    S = load(source.cacheFile, 'TRskin');
    if ~isfield(S, 'TRskin')
        error('acsBuildCapMakerManufacturingStl:BadSkinCache', ...
            'Skin cache does not contain TRskin: %s', source.cacheFile);
    end
    TRskin = S.TRskin;
    source.label = fileStem(source.cacheFile);
end

function [names, coords, roles] = selectedLayoutSites(layout, opts)
    required = {'names', 'layoutCoordinatesMm'};
    for i = 1:numel(required)
        if ~isfield(layout, required{i}) || isempty(layout.(required{i}))
            error('acsBuildCapMakerManufacturingStl:MissingLayoutField', ...
                'Layout is missing required field "%s".', required{i});
        end
    end
    allNames = toCellstrList(layout.names);
    allCoords = double(layout.layoutCoordinatesMm);
    if size(allCoords, 1) ~= numel(allNames) || size(allCoords, 2) ~= 3
        error('acsBuildCapMakerManufacturingStl:BadCoordinates', ...
            'layoutCoordinatesMm must be N x 3 and match layout.names.');
    end
    if isfield(layout, 'siteRoles') && numel(layout.siteRoles) == numel(allNames)
        allRoles = toCellstrList(layout.siteRoles);
    else
        allRoles = repmat({''}, numel(allNames), 1);
    end

    if isempty(opts.electrodeNames)
        rows = (1:numel(allNames))';
    else
        rows = zeros(numel(opts.electrodeNames), 1);
        for i = 1:numel(opts.electrodeNames)
            idx = find(strcmpi(opts.electrodeNames{i}, allNames), 1);
            if isempty(idx)
                error('acsBuildCapMakerManufacturingStl:MissingElectrode', ...
                    'Requested electrode "%s" was not found in layout.names.', ...
                    opts.electrodeNames{i});
            end
            rows(i) = idx;
        end
    end

    names = allNames(rows);
    coords = allCoords(rows, :);
    roles = allRoles(rows);
end

function tesInfo = selectedTesInfo(layout, manufacturedNames)
    tesInfo = struct('tesNames', {{}}, 'sourceTesNames', {{}}, ...
        'tesCurrentsMa', []);
    if ~isfield(layout, 'tesNames') || isempty(layout.tesNames) || ...
            ~isfield(layout, 'tesCurrentsMa') || isempty(layout.tesCurrentsMa)
        return;
    end

    allTesNames = toCellstrList(layout.tesNames);
    currents = double(layout.tesCurrentsMa(:));
    if isfield(layout, 'sourceTesNames') && ~isempty(layout.sourceTesNames)
        sourceNames = toCellstrList(layout.sourceTesNames);
    else
        sourceNames = allTesNames;
    end

    n = min([numel(allTesNames), numel(sourceNames), numel(currents)]);
    allTesNames = allTesNames(1:n);
    sourceNames = sourceNames(1:n);
    currents = currents(1:n);
    manufacturedNames = toCellstrList(manufacturedNames);

    keep = false(n, 1);
    for i = 1:n
        keep(i) = any(strcmpi(allTesNames{i}, manufacturedNames));
    end

    tesInfo.tesNames = allTesNames(keep);
    tesInfo.sourceTesNames = sourceNames(keep);
    tesInfo.tesCurrentsMa = currents(keep);
end

function opts = resolveOutputPaths(layout, skinSource, opts)
    if isempty(opts.manufacturingTag)
        if isfield(layout, 'reportMat') && ~isempty(layout.reportMat)
            opts.manufacturingTag = safeName(fileStem(layout.reportMat));
        elseif isfield(layout, 'customLocationsFile') && ~isempty(layout.customLocationsFile)
            opts.manufacturingTag = safeName(fileStem(layout.customLocationsFile));
        else
            opts.manufacturingTag = [safeName(skinSource.label) '_manufacturing'];
        end
    else
        opts.manufacturingTag = safeName(opts.manufacturingTag);
    end

    if isempty(opts.outputDir)
        baseDir = fileparts(skinSource.cacheFile);
        opts.outputDir = fullfile(baseDir, 'manufacturing', opts.manufacturingTag);
    end
    if isempty(opts.manufacturingSurfaceCacheFile)
        opts.manufacturingSurfaceCacheFile = fullfile(opts.outputDir, ...
            [opts.manufacturingTag '_manufacturingSkinMesh.mat']);
    end
    opts.tpeStlFile = fullfile(opts.outputDir, [opts.manufacturingTag '_tpe.stl']);
    opts.plaStlFile = fullfile(opts.outputDir, [opts.manufacturingTag '_pla.stl']);
    opts.reportMat = fullfile(opts.outputDir, [opts.manufacturingTag '_manufacturing_report.mat']);
    opts.meshMat = fullfile(opts.outputDir, [opts.manufacturingTag '_manufacturing_meshes.mat']);
end

function requireWritableOutputs(opts)
    files = {opts.tpeStlFile, opts.plaStlFile, opts.reportMat};
    if opts.saveMeshMat
        files{end + 1} = opts.meshMat;
    end
    existing = files(cellfun(@(f) exist(f, 'file') == 2, files));
    if ~isempty(existing) && ~opts.force
        error('acsBuildCapMakerManufacturingStl:OutputExists', ...
            ['Manufacturing output already exists. Use force=true to overwrite.\n', ...
             'First existing file: %s'], existing{1});
    end
end

function holderTR = makeHolderMesh(opts)
    if opts.holderInsideDiaMm >= opts.holderOutsideDiaMm
        error('acsBuildCapMakerManufacturingStl:BadHolderSize', ...
            'holderInsideDiaMm must be smaller than holderOutsideDiaMm.');
    end
    holderTR = makeElectrodeHolderHex(opts.holderInsideDiaMm, ...
        opts.holderOutsideDiaMm, opts.holderHeightMm);
    holderTR = unifyOutwardNormalsRobust(holderTR);
end

function TRholderSkin = holderPlacementSurface(TRskinFull, TRskinManufacturing, opts)
    switch opts.holderPlacementSurfaceMode
        case 'full'
            TRholderSkin = TRskinFull;
            logMsg(opts, 'Using full layout scalp mesh for electrode holder placement.');
        case 'manufacturing'
            TRholderSkin = TRskinManufacturing;
            logMsg(opts, 'Using decimated manufacturing scalp mesh for electrode holder placement.');
    end
end

function [TRskin, info] = loadOrMakeManufacturingSurface(TRskinFull, opts)
    info = struct();
    info.cacheFile = opts.manufacturingSurfaceCacheFile;
    info.sourceCacheFile = getOptionalField(opts, 'skinSourceCacheFile', '');
    info.maxFaces = opts.manufacturingSurfaceMaxFaces;
    info.usedCache = false;
    info.didDecimate = false;
    info.sourceMesh = meshStats(TRskinFull);

    if exist(info.cacheFile, 'file') == 2 && ~opts.forceManufacturingSurface
        logMsg(opts, 'Loading decimated manufacturing scalp mesh: %s', info.cacheFile);
        S = load(info.cacheFile, 'TRskin', 'info');
        if isfield(S, 'TRskin')
            TRskin = S.TRskin;
            cachedInfo = getOptionalField(S, 'info', struct());
            if manufacturingSurfaceCacheMatches(TRskin, cachedInfo, opts)
                info.usedCache = true;
                info.cachedInfo = cachedInfo;
                info.mesh = meshStats(TRskin);
                return;
            end
            logMsg(opts, 'Cached manufacturing scalp mesh does not match requested settings; rebuilding.');
        end
        warning('acsBuildCapMakerManufacturingStl:BadManufacturingSurfaceCache', ...
            'Manufacturing surface cache did not contain TRskin. Rebuilding: %s', ...
            info.cacheFile);
    end

    TRskin = decimateTriangulation(TRskinFull, opts.manufacturingSurfaceMaxFaces, ...
        opts, 'manufacturing scalp mesh');
    info.didDecimate = true;
    info.mesh = meshStats(TRskin);
    ensureDir(fileparts(info.cacheFile));
    save(opts.manufacturingSurfaceCacheFile, 'TRskin', 'info', '-v7.3');
    logMsg(opts, 'Saved decimated manufacturing scalp mesh: %s', ...
        opts.manufacturingSurfaceCacheFile);
end

function tf = manufacturingSurfaceCacheMatches(TRskin, cachedInfo, opts)
    if isempty(opts.manufacturingSurfaceMaxFaces)
        tf = true;
        return;
    end
    nFaces = size(TRskin.ConnectivityList, 1);
    tf = nFaces <= opts.manufacturingSurfaceMaxFaces;
    if isstruct(cachedInfo) && isfield(cachedInfo, 'maxFaces') && ...
            ~isempty(cachedInfo.maxFaces)
        tf = tf && double(cachedInfo.maxFaces) == double(opts.manufacturingSurfaceMaxFaces);
    end
    requestedSource = getOptionalField(opts, 'skinSourceCacheFile', '');
    cachedSource = '';
    if isstruct(cachedInfo) && isfield(cachedInfo, 'sourceCacheFile')
        cachedSource = cachedInfo.sourceCacheFile;
    end
    if ~isempty(requestedSource)
        tf = tf && strcmpi(char(cachedSource), char(requestedSource));
    end
end

function TRout = decimateTriangulation(TRin, maxFaces, opts, label)
    if nargin < 4 || isempty(label)
        label = 'mesh';
    end
    TRout = TRin;
    if isempty(maxFaces) || isempty(TRin) || isempty(TRin.Points)
        return;
    end
    nFaces = size(TRin.ConnectivityList, 1);
    if nFaces <= maxFaces
        logMsg(opts, '%s has %d faces; no decimation needed.', label, nFaces);
        return;
    end
    logMsg(opts, 'Decimating %s from %d to about %d faces.', ...
        label, nFaces, maxFaces);
    try
        [F2, V2] = reducepatch(TRin.ConnectivityList, TRin.Points, maxFaces);
        TRout = triangulation(F2, V2);
        TRout = unifyOutwardNormalsRobust(TRout);
    catch ME
        warning('acsBuildCapMakerManufacturingStl:RailDecimationFailed', ...
            '%s decimation failed (%s). Using undecimated mesh.', label, ME.message);
        TRout = TRin;
    end
end

function out = makePreflightOutput(layout, TRskin, TRrailSkin, TRholders, TRrails, ...
        targetsMm, names, roleLabels, earExclusions, implantExclusions, strap, ...
        TRholderSupports, holderInfo, manufacturingSurfaceInfo, ...
        railBuildInfo, opts, totalTimer)
    meshInfo = struct();
    meshInfo.skin = meshStats(TRskin);
    meshInfo.railSource = meshStats(TRrailSkin);
    meshInfo.holders = meshStats(TRholders);
    meshInfo.rails = meshStats(TRrails);
    meshInfo.holderSupports = meshStats(TRholderSupports);
    meshInfo.railBuild = railBuildInfo;
    meshInfo.holderClosure = checkMeshClosed(TRholders);
    meshInfo.railClosure = checkMeshClosed(TRrails);

    qcFile = '';
    fig = [];
    if opts.showFigures || opts.saveFigures
        emptyTri = [];
        figVisible = 'off';
        if opts.showFigures
            figVisible = 'on';
        end
        logMsg(opts, 'Building manufacturing preflight QC figure.');
        fig = makeQcFigure(TRskin, TRholders, TRrails, emptyTri, emptyTri, ...
            targetsMm, names, roleLabels, earExclusions, implantExclusions, ...
            strap, holderInfo, opts, figVisible);
        if opts.saveFigures
            qcFile = fullfile(opts.outputDir, [opts.manufacturingTag '_preflight_qc.png']);
            saveQcFigure(fig, qcFile);
        end
        if ~opts.showFigures
            close(fig);
            fig = [];
        end
    end

    out = struct();
    out.createdOn = char(datetime('now'));
    out.preflightOnly = true;
    out.manufacturingTag = opts.manufacturingTag;
    out.outputDir = opts.outputDir;
    out.reportMat = opts.reportMat;
    out.meshMat = opts.meshMat;
    out.qcFigure = qcFile;
    out.names = names;
    out.siteRoles = roleLabels;
    tesInfo = selectedTesInfo(layout, names);
    out.tesNames = tesInfo.tesNames;
    out.sourceTesNames = tesInfo.sourceTesNames;
    out.tesCurrentsMa = tesInfo.tesCurrentsMa;
    out.layoutCoordinatesMm = targetsMm;
    out.holderSurfaceCoordinatesMm = holderSurfacePointsFromInfo(holderInfo, targetsMm);
    out.holderInfo = holderInfo;
    out.manufacturingSurface = manufacturingSurfaceInfo;
    out.earExclusions = compactEarExclusions(earExclusions);
    out.implantExclusions = compactImplantExclusions(implantExclusions);
    out.strap = stripStrapFns(strap);
    out.holderSupports = meshStats(TRholderSupports);
    out.railBuildInfo = railBuildInfo;
    out.options = opts;
    out.meshInfo = meshInfo;
    if opts.returnMeshes
        out.meshes = struct( ...
            'skin', TRskin, ...
            'railSource', TRrailSkin, ...
            'holders', TRholders, ...
            'rails', TRrails);
    end
    if opts.saveMeshMat
        meshes = struct( ...
            'TRskin', TRskin, ...
            'TRrailSkin', TRrailSkin, ...
            'TRholders', TRholders, ...
            'TRrails', TRrails, ...
            'TRholderSupports', TRholderSupports); %#ok<NASGU>
        save(opts.meshMat, 'meshes', '-v7.3');
    end
    if isgraphics(fig)
        out.figure = fig;
    end

    outFull = out;
    out = stripForSave(outFull); %#ok<NASGU>
    outToSave = out; %#ok<NASGU>
    outSaved = out; %#ok<NASGU>
    save(opts.reportMat, 'out', 'outToSave', 'outSaved', '-v7.3');
    out = outFull;
    logMsg(opts, 'Saved manufacturing preflight report: %s', opts.reportMat);
    logElapsed(opts, 'Completed manufacturing preflight', totalTimer);
end

function snapped = snapTargetsToSurface(TRskin, targetsMm)
    V = double(TRskin.Points);
    snapped = zeros(size(targetsMm));
    for i = 1:size(targetsMm, 1)
        d2 = sum((V - targetsMm(i, :)) .^ 2, 2);
        [~, idx] = min(d2);
        snapped(i, :) = V(idx, :);
    end
end

function checkHolderSnapDistance(holderSurfaceMm, targetsMm, names, opts)
    if isempty(holderSurfaceMm) || isempty(targetsMm)
        return;
    end
    d = vecnorm(holderSurfaceMm - targetsMm, 2, 2);
    if any(d > opts.holderSnapErrorDistanceMm)
        txt = nameDistanceText(names, d > opts.holderSnapErrorDistanceMm, ...
            d, 'snap mm');
        error('acsBuildCapMakerManufacturingStl:HolderSnapTooFar', ...
            ['Electrode holder placement would move layout sites too far ', ...
             'from their finalized coordinates: %s. This usually means the ', ...
             'manufacturing surface differs from the layout surface; use ', ...
             'holderPlacementSurfaceMode=''full'' or refresh the skin cache.'], txt);
    end
    if any(d > opts.holderSnapWarnDistanceMm)
        txt = nameDistanceText(names, d > opts.holderSnapWarnDistanceMm, ...
            d, 'snap mm');
        warning('acsBuildCapMakerManufacturingStl:HolderSnapDistance', ...
            'Electrode holder placement moved layout sites by more than %.3g mm: %s', ...
            opts.holderSnapWarnDistanceMm, txt);
    end
end

function checkHolderBedClearance(holderInfo, names, opts)
    if strcmp(opts.holderBedClearancePolicy, 'ignore') || isempty(holderInfo)
        return;
    end
    minZ = [holderInfo.minZMm].';
    clearance = minZ - opts.zBedMm;
    tooClose = clearance < opts.holderMinBedClearanceMm;
    if ~any(tooClose)
        return;
    end
    txt = nameDistanceText(names, tooClose, clearance, 'clearance');
    msg = sprintf(['Electrode holder geometry is too close to the printer bed: %s. ', ...
        'Minimum requested clearance is %.3g mm above zBed=%.3g mm. ', ...
        'These holders may be clipped in the final STL; rerun layout placement ', ...
        'with a larger edge/crop margin or remove these sites.'], ...
        txt, opts.holderMinBedClearanceMm, opts.zBedMm);
    switch opts.holderBedClearancePolicy
        case 'error'
            error('acsBuildCapMakerManufacturingStl:HolderTooCloseToBed', '%s', msg);
        case 'warn'
            warning('acsBuildCapMakerManufacturingStl:HolderTooCloseToBed', '%s', msg);
    end
end

function checkHoldersAgainstStrapOccupancy(holderInfo, names, strap, opts)
    if strcmp(opts.strapElectrodePolicy, 'ignore') || isempty(holderInfo) || ...
            ~isfield(strap, 'occFns') || isempty(strap.occFns)
        return;
    end
    overlaps = false(numel(holderInfo), 1);
    nHits = zeros(numel(holderInfo), 1);
    for i = 1:numel(holderInfo)
        P = holderFootprintSamples(holderInfo(i), opts);
        hit = false(size(P, 1), 1);
        for f = 1:numel(strap.occFns)
            hit = hit | logical(strap.occFns{f}(P(:, 1), P(:, 2), P(:, 3)));
        end
        overlaps(i) = any(hit);
        nHits(i) = nnz(hit);
    end
    if ~any(overlaps)
        return;
    end
    txt = nameDistanceText(names, overlaps, nHits, 'sample hits');
    msg = sprintf(['Electrode holder sample points overlap the chin-strap occupancy: %s. ', ...
        'This may be acceptable near a strap junction only if the final keepout ', ...
        'still clears a usable gel/electrode hole through the merged material.'], txt);
    switch opts.strapElectrodePolicy
        case 'error'
            error('acsBuildCapMakerManufacturingStl:HolderOverlapsStrap', '%s', msg);
        case 'warn'
            warning('acsBuildCapMakerManufacturingStl:HolderOverlapsStrap', '%s', msg);
    end
end

function P = holderFootprintSamples(info, opts)
    u = double(info.holeAxis);
    if numel(u) ~= 3 || norm(u) < eps || any(~isfinite(u))
        u = [0 0 1];
    else
        u = u ./ norm(u);
    end
    [v, w] = localTransverseBasis(u);
    n = opts.strapElectrodeSampleCount;
    theta = linspace(0, 2*pi, n + 1).';
    theta(end) = [];
    radius = opts.strapElectrodeSampleRadiusMm;
    ringOffset = radius .* (cos(theta) * v + sin(theta) * w);
    centers = [
        double(info.surfacePointMm)
        double(info.holeBottomMm)
        double(info.holderCenterMm)
        ];
    P = centers;
    for c = 1:size(centers, 1)
        P = [P; centers(c, :) + ringOffset]; %#ok<AGROW>
    end
end

function txt = nameDistanceText(names, mask, values, valueLabel)
    rows = find(mask(:));
    parts = cell(numel(rows), 1);
    for i = 1:numel(rows)
        row = rows(i);
        value = values(row);
        if isfinite(value)
            parts{i} = sprintf('%s (%.3g %s)', names{row}, value, valueLabel);
        else
            parts{i} = names{row};
        end
    end
    txt = strjoin(parts, ', ');
end

function [v, w] = localTransverseBasis(u)
    u = u(:).';
    if abs(dot(u, [0 0 1])) < 0.9
        ref = [0 0 1];
    else
        ref = [1 0 0];
    end
    v = cross(u, ref);
    v = v ./ norm(v);
    w = cross(u, v);
    w = w ./ norm(w);
end

function TRkeepoutUnion = makeHoleKeepoutUnion(holeTops, holeBottoms, opts)
    TRlist = {};
    if any(strcmp(opts.holeKeepoutMode, {'flared', 'flaredAndTetra'}))
        TRflared = makeHoleClearingFrusta(holeTops, holeBottoms, ...
            opts.holeInsideDiaMm, ...
            'ClearanceMm', opts.holeClearanceMm, ...
            'BoreClearanceMm', opts.holeBoreClearanceMm, ...
            'ScalpClearanceMm', opts.holeScalpClearanceMm, ...
            'TopExtendMm', opts.holeTopExtendMm, ...
            'ScalpExtendMm', opts.holeScalpExtendMm, ...
            'ScalpFlareDiaMm', opts.holeScalpFlareDiaMm, ...
            'NumSides', opts.holeCylinderSides);
        TRlist = [TRlist; TRflared(:)]; %#ok<AGROW>
    end
    if any(strcmp(opts.holeKeepoutMode, {'tetra', 'flaredAndTetra'}))
        keepoutArgs = structToNameValue(opts.keepoutOptions);
        TRtets = makeHoleClearingTetras(holeTops, holeBottoms, ...
            opts.holeInsideDiaMm, keepoutArgs{:});
        TRlist = [TRlist; TRtets(:)]; %#ok<AGROW>
    end
    if isempty(TRlist)
        error('acsBuildCapMakerManufacturingStl:NoHoleKeepouts', ...
            'holeKeepoutMode "%s" did not create any cutter meshes.', ...
            opts.holeKeepoutMode);
    end
    TRkeepoutUnion = concatTriList(TRlist);
end

function TRsupports = makeHolderSupportRails(holderCentersMm, names, TRrailsBase, opts, railExcludePolys)
    if nargin < 5
        railExcludePolys = {};
    end
    TRsupports = [];
    if strcmp(opts.holderSupportMode, 'none') || opts.holderSupportCount == 0
        return;
    end
    if isempty(TRrailsBase) || isempty(TRrailsBase.Points)
        warning('acsBuildCapMakerManufacturingStl:NoBaseRailsForHolderSupport', ...
            'No base rails exist; holder support rails cannot be added.');
        return;
    end

    railPoints = uniqueRoundedRows(double(TRrailsBase.Points), 1e-3);
    railList = {};
    longSupport = false(size(holderCentersMm, 1), 1);
    supportLengths = zeros(size(holderCentersMm, 1), opts.holderSupportCount);
    selectedEndpoints = cell(size(holderCentersMm, 1), 1);
    supportSpreadDeg = zeros(size(holderCentersMm, 1), 1);
    supportCount = zeros(size(holderCentersMm, 1), 1);
    for i = 1:size(holderCentersMm, 1)
        selected = selectSupportEndpoints(holderCentersMm(i, :), railPoints, opts, ...
            railExcludePolys);
        selectedEndpoints{i} = selected;
        supportSpreadDeg(i) = supportAngleSpreadDeg(holderCentersMm(i, :), selected);
        for j = 1:size(selected, 1)
            L = norm(selected(j, :) - holderCentersMm(i, :));
            supportLengths(i, j) = L;
            if L > opts.holderSupportWarnLengthMm
                longSupport(i) = true;
            end
            if segmentInAnyPoly(holderCentersMm(i, :), selected(j, :), ...
                    railExcludePolys)
                continue;
            end
            railList{end + 1} = makeSegmentRail( ...
                holderCentersMm(i, :), selected(j, :), ...
                opts.holderSupportWidthMm, opts.holderSupportHeightMm, ...
                opts.railEmbedFraction, opts.railMinLengthMm); %#ok<AGROW>
            supportCount(i) = supportCount(i) + 1;
        end
    end

    bridgeInfo = struct('pairs', zeros(0, 2), 'lengthsMm', zeros(0, 1), ...
        'reason', {{}});
    if strcmp(opts.holderBridgeMode, 'auto')
        [bridgeList, bridgeInfo] = makeHolderStabilizingBridges( ...
            holderCentersMm, selectedEndpoints, supportSpreadDeg, opts, ...
            railExcludePolys);
        railList = [railList, bridgeList]; %#ok<AGROW>
    end

    if any(longSupport)
        warning('acsBuildCapMakerManufacturingStl:LongHolderSupportRail', ...
            ['%d holder support rail sets exceed %.1f mm. This usually means ', ...
             'a holder is outside the nearby cap rail network.'], ...
            nnz(longSupport), opts.holderSupportWarnLengthMm);
    end
    shortSupport = supportCount < opts.holderSupportCount;
    if any(shortSupport)
        warning('acsBuildCapMakerManufacturingStl:SparseHolderSupportRails', ...
            ['%d holder(s) received fewer than %d support struts: %s. ', ...
             'Inspect the preflight QC before manufacturing.'], ...
            nnz(shortSupport), opts.holderSupportCount, ...
            strjoin(names(shortSupport), ', '));
    end
    TRsupports = concatTriangulations(railList);
    if opts.verbose && ~isempty(TRsupports)
        supportLengthValues = nonzeros(supportLengths(:));
        if isempty(supportLengthValues)
            medianSupportLength = NaN;
        else
            medianSupportLength = median(supportLengthValues);
        end
        fprintf(['Holder support rails: %d struts, median rail-support length %.1f mm, ', ...
            '%d holder-holder bridges.\n'], ...
            numel(railList), medianSupportLength, ...
            size(bridgeInfo.pairs, 1));
        drawnow('limitrate');
    end
end

function selected = selectSupportEndpoints(center, railPoints, opts, railExcludePolys)
    if nargin < 4
        railExcludePolys = {};
    end
    d2 = sum((railPoints - center) .^ 2, 2);
    [~, order] = sort(d2, 'ascend');
    selected = zeros(0, 3);
    selectedDirs = zeros(0, 3);
    for k = 1:numel(order)
        candidate = railPoints(order(k), :);
        if norm(candidate - center) <= opts.railMinLengthMm
            continue;
        end
        if segmentInAnyPoly(center, candidate, railExcludePolys)
            continue;
        end
        candidateDir = normalizeRow(candidate - center);
        if isempty(selected)
            selected = candidate;
            selectedDirs = candidateDir;
        else
            sep = sqrt(sum((selected - candidate) .^ 2, 2));
            angleDeg = minAngleToDirectionsDeg(candidateDir, selectedDirs);
            if all(sep >= opts.holderSupportEndpointSeparationMm) && ...
                    angleDeg >= opts.holderSupportMinAngleDeg
                selected(end + 1, :) = candidate; %#ok<AGROW>
                selectedDirs(end + 1, :) = candidateDir; %#ok<AGROW>
            end
        end
        if size(selected, 1) >= opts.holderSupportCount
            break;
        end
    end
    if size(selected, 1) < opts.holderSupportCount
        selected = fillSupportEndpointsByBestSpread(center, railPoints, ...
            selected, opts, railExcludePolys);
    end
    if isempty(selected) && ~isempty(order)
        for k = 1:numel(order)
            candidate = railPoints(order(k), :);
            if ~segmentInAnyPoly(center, candidate, railExcludePolys)
                selected = candidate;
                break;
            end
        end
    end
end

function selected = fillSupportEndpointsByBestSpread(center, railPoints, selected, opts, railExcludePolys)
    if nargin < 5
        railExcludePolys = {};
    end
    targetCount = opts.holderSupportCount;
    if targetCount == 0
        return;
    end
    d = sqrt(sum((railPoints - center) .^ 2, 2));
    valid = d > opts.railMinLengthMm;
    while size(selected, 1) < targetCount && any(valid)
        bestRow = [];
        bestScore = -inf;
        for r = find(valid(:))'
            candidate = railPoints(r, :);
            if segmentInAnyPoly(center, candidate, railExcludePolys)
                continue;
            end
            if ~isempty(selected)
                sep = sqrt(sum((selected - candidate) .^ 2, 2));
                if any(sep < opts.holderSupportEndpointSeparationMm)
                    continue;
                end
            end
            trial = [selected; candidate]; %#ok<AGROW>
            spread = supportAngleSpreadDeg(center, trial);
            score = spread - 0.02 * d(r);
            if score > bestScore
                bestScore = score;
                bestRow = r;
            end
        end
        if isempty(bestRow)
            break;
        end
        selected(end + 1, :) = railPoints(bestRow, :); %#ok<AGROW>
        valid(bestRow) = false;
    end
end

function [bridgeList, bridgeInfo] = makeHolderStabilizingBridges( ...
        holderCentersMm, selectedEndpoints, supportSpreadDeg, opts, railExcludePolys)
    if nargin < 5
        railExcludePolys = {};
    end
    bridgeList = {};
    bridgeInfo = struct('pairs', zeros(0, 2), 'lengthsMm', zeros(0, 1), ...
        'reason', {{}});
    n = size(holderCentersMm, 1);
    if n < 2 || opts.holderSupportMinAngleDeg <= 0
        return;
    end

    needsBridge = supportSpreadDeg < opts.holderSupportMinAngleDeg;
    usedPairs = false(n, n);
    for i = find(needsBridge(:))'
        bestJ = [];
        bestScore = -inf;
        bestDist = inf;
        dirs = supportDirections(holderCentersMm(i, :), selectedEndpoints{i});
        for j = 1:n
            if i == j || usedPairs(min(i,j), max(i,j))
                continue;
            end
            dist = norm(holderCentersMm(j, :) - holderCentersMm(i, :));
            if dist > opts.holderBridgeMaxLengthMm || dist <= opts.holderOutsideDiaMm
                continue;
            end
            bridgeDir = normalizeRow(holderCentersMm(j, :) - holderCentersMm(i, :));
            angleDeg = minAngleToDirectionsDeg(bridgeDir, dirs);
            score = angleDeg - 0.01 * dist;
            if score > bestScore
                bestScore = score;
                bestDist = dist;
                bestJ = j;
            end
        end
        if isempty(bestJ)
            continue;
        end
        if segmentInAnyPoly(holderCentersMm(i, :), holderCentersMm(bestJ, :), ...
                railExcludePolys)
            continue;
        end
        pair = sort([i bestJ]);
        usedPairs(pair(1), pair(2)) = true;
        bridgeList{end + 1} = makeSegmentRail( ...
            holderCentersMm(i, :), holderCentersMm(bestJ, :), ...
            opts.holderSupportWidthMm, opts.holderSupportHeightMm, ...
            opts.railEmbedFraction, opts.railMinLengthMm); %#ok<AGROW>
        bridgeInfo.pairs(end + 1, :) = pair; %#ok<AGROW>
        bridgeInfo.lengthsMm(end + 1, 1) = bestDist; %#ok<AGROW>
        bridgeInfo.reason{end + 1, 1} = sprintf( ...
            'support spread %.1f deg < %.1f deg', ...
            supportSpreadDeg(i), opts.holderSupportMinAngleDeg); %#ok<AGROW>
    end
end

function spreadDeg = supportAngleSpreadDeg(center, endpoints)
    dirs = supportDirections(center, endpoints);
    if size(dirs, 1) < 2
        spreadDeg = 0;
        return;
    end
    dots = max(-1, min(1, dirs * dirs'));
    angles = acosd(dots);
    spreadDeg = max(angles(:));
end

function dirs = supportDirections(center, endpoints)
    if isempty(endpoints)
        dirs = zeros(0, 3);
        return;
    end
    dirs = endpoints - center;
    normValue = sqrt(sum(dirs .^ 2, 2));
    keep = normValue > 0;
    dirs = dirs(keep, :);
    normValue = normValue(keep);
    if isempty(dirs)
        dirs = zeros(0, 3);
        return;
    end
    dirs = bsxfun(@rdivide, dirs, normValue);
end

function angleDeg = minAngleToDirectionsDeg(direction, directions)
    direction = normalizeRow(direction);
    if isempty(directions) || all(direction == 0)
        angleDeg = 180;
        return;
    end
    dots = max(-1, min(1, directions * direction'));
    angleDeg = min(acosd(dots));
end

function tf = segmentInAnyPoly(P0, P1, polys)
    tf = false;
    if isempty(polys)
        return;
    end
    t = linspace(0, 1, 15)';
    xy = (1 - t) .* P0(1:2) + t .* P1(1:2);
    for i = 1:numel(polys)
        ps = polys{i};
        if isempty(ps) || ps.NumRegions == 0 || area(ps) == 0
            continue;
        end
        if any(isinterior(ps, xy(:, 1), xy(:, 2)))
            tf = true;
            return;
        end
    end
end

function row = normalizeRow(row)
    n = norm(row);
    if n <= 0 || ~isfinite(n)
        row = zeros(1, 3);
    else
        row = row ./ n;
    end
end

function TR = makeSegmentRail(P0, P1, railW, railH, embedFrac, minLen)
    seg = P1 - P0;
    L = norm(seg);
    if L <= minLen || L == 0
        TR = [];
        return;
    end
    t = seg / L;
    zAxis = [0 0 1];
    w = cross(zAxis, t);
    if norm(w) < 1e-9
        w = [1 0 0];
    end
    w = w / norm(w);

    zBot = -embedFrac * railH;
    zTop = (1 - embedFrac) * railH;
    halfW = 0.5 * railW;
    ext = min(halfW, 0.49 * L);
    A = P0 - ext * t;
    B = P1 + ext * t;

    Vrail = [
        A - halfW*w + zBot*zAxis
        A + halfW*w + zBot*zAxis
        A + halfW*w + zTop*zAxis
        A - halfW*w + zTop*zAxis
        B - halfW*w + zBot*zAxis
        B + halfW*w + zBot*zAxis
        B + halfW*w + zTop*zAxis
        B - halfW*w + zTop*zAxis];

    Frail = convhulln(Vrail);
    Crail = mean(Vrail, 1);
    for f = 1:size(Frail, 1)
        a = Vrail(Frail(f, 1), :);
        b = Vrail(Frail(f, 2), :);
        c = Vrail(Frail(f, 3), :);
        N = cross(b - a, c - a);
        if any(N)
            N = N / norm(N);
            fc = (a + b + c) / 3;
            if dot(N, Crail - fc) > 0
                Frail(f, [2 3]) = Frail(f, [3 2]);
            end
        end
    end
    TR = triangulation(Frail, Vrail);
end

function rows = uniqueRoundedRows(P, tol)
    if isempty(P)
        rows = P;
        return;
    end
    scale = 1 / tol;
    [~, idx] = unique(round(P * scale), 'rows', 'stable');
    rows = P(idx, :);
end

function TRout = concatTriangulations(TRlist)
    V = zeros(0, 3);
    F = zeros(0, 3);
    for i = 1:numel(TRlist)
        TR = TRlist{i};
        if isempty(TR) || isempty(TR.Points)
            continue;
        end
        offset = size(V, 1);
        V = [V; TR.Points]; %#ok<AGROW>
        F = [F; TR.ConnectivityList + offset]; %#ok<AGROW>
    end
    if isempty(F)
        TRout = [];
    else
        TRout = triangulation(F, V);
    end
end

function earExclusions = resolveEarExclusions(layout, skinSource, opts)
    earExclusions = struct();
    if strcmp(opts.earExclusionMode, 'none')
        return;
    end

    earFile = opts.earExclusionFile;
    if isempty(earFile)
        earFile = defaultEarFile(skinSource.cacheFile);
    end
    if strcmp(opts.earExclusionMode, 'never')
        if exist(earFile, 'file') ~= 2
            error('acsBuildCapMakerManufacturingStl:MissingEarExclusionFile', ...
                ['earExclusionMode=''never'' requires an existing saved ', ...
                 'ear exclusion file: %s'], earFile);
        end
        earExclusions = loadSavedEarExclusionsForSkin( ...
            earFile, skinSource.cacheFile, opts);
        warnIfEarExclusionsDifferFromLayout(layout, earExclusions);
        return;
    end
    try
        earExclusions = acsSelectEarExclusionSpheres(skinSource.cacheFile, ...
            'editMode', opts.earExclusionMode, ...
            'outputFile', earFile, ...
            'showFigures', opts.showFigures, ...
            'saveFigures', opts.saveFigures, ...
            'verbose', opts.verbose);
        warnIfEarExclusionsDifferFromLayout(layout, earExclusions);
    catch ME
        warning('acsBuildCapMakerManufacturingStl:EarExclusionsUnavailable', ...
            'Could not resolve ear exclusions (%s). Continuing without them.', ...
            ME.message);
        earExclusions = struct();
    end
end

function earExclusions = loadSavedEarExclusionsForSkin(earFile, skinCacheFile, opts)
    S = load(earFile);
    earExclusions = firstStruct(S);
    if ~isfield(earExclusions, 'exclusionCenters') || ...
            ~isfield(earExclusions, 'exclusionRadiusMM')
        error('acsBuildCapMakerManufacturingStl:BadEarExclusionFile', ...
            'Saved ear exclusion file does not contain exclusion centers/radii: %s', ...
            earFile);
    end
    skin = load(skinCacheFile, 'TRskin');
    if ~isfield(skin, 'TRskin')
        error('acsBuildCapMakerManufacturingStl:BadSkinCache', ...
            'Skin cache does not contain TRskin: %s', skinCacheFile);
    end
    V = double(skin.TRskin.Points);
    paintedRows = remapPaintedExclusionsToSkin(earExclusions, V);
    earExclusions.customExclusionVertexInd = paintedRows(:);
    earExclusions.paintedExclusionVertex = paintedRows(:);
    if ~isempty(paintedRows)
        P = V(paintedRows, :);
    else
        P = zeros(0, 3);
    end
    earExclusions.customExclusionCoordinatesMm = P;
    earExclusions.paintedExclusionCoordinatesMm = P;
    earExclusions.outputFile = earFile;
    earExclusions.appliedToSkinCacheFile = skinCacheFile;
    logMsg(opts, 'Loaded saved ear/painted exclusions: %s', earFile);
    logMsg(opts, '  painted exclusions remapped to %d current mesh vertices.', ...
        numel(paintedRows));
end

function rows = remapPaintedExclusionsToSkin(earExclusions, V)
    P = zeros(0, 3);
    if isfield(earExclusions, 'customExclusionCoordinatesMm') && ...
            ~isempty(earExclusions.customExclusionCoordinatesMm)
        P = double(earExclusions.customExclusionCoordinatesMm);
    elseif isfield(earExclusions, 'paintedExclusionCoordinatesMm') && ...
            ~isempty(earExclusions.paintedExclusionCoordinatesMm)
        P = double(earExclusions.paintedExclusionCoordinatesMm);
    end
    if size(P, 2) == 3
        P = P(all(isfinite(P), 2), :);
    else
        P = zeros(0, 3);
    end
    if ~isempty(P)
        rows = nearestVertexRows(V, P);
        rows = unique(rows(:));
        return;
    end
    rows = [];
    if isfield(earExclusions, 'customExclusionVertexInd') && ...
            ~isempty(earExclusions.customExclusionVertexInd)
        rows = double(earExclusions.customExclusionVertexInd(:));
    elseif isfield(earExclusions, 'paintedExclusionVertex') && ...
            ~isempty(earExclusions.paintedExclusionVertex)
        rows = double(earExclusions.paintedExclusionVertex(:));
    end
    rows = unique(round(rows(isfinite(rows) & rows >= 1 & rows <= size(V, 1))));
end

function rows = nearestVertexRows(V, P)
    rows = zeros(size(P, 1), 1);
    for i = 1:size(P, 1)
        d2 = sum((V - P(i, :)) .^ 2, 2);
        [~, rows(i)] = min(d2);
    end
end

function warnIfEarExclusionsDifferFromLayout(layout, earExclusions)
    layoutEars = layoutEarExclusions(layout);
    if isempty(layoutEars) || ~isfield(earExclusions, 'exclusionCenters') || ...
            ~isfield(earExclusions, 'exclusionRadiusMM')
        return;
    end
    if ~earExclusionsMatch(layoutEars, earExclusions, 1e-6)
        warning('acsBuildCapMakerManufacturingStl:EarExclusionsChangedAfterLayout', ...
            ['Current manufacturing ear exclusions differ from the ear ', ...
             'exclusions stored with the layout. Rerun the combined ', ...
             'tES+EEG layout step after editing ears so placement and ', ...
             'manufacturing use the same keepouts.']);
    end
end

function ears = layoutEarExclusions(layout)
    ears = [];
    paths = { ...
        {'eegTargetOptions', 'earExclusions'}, ...
        {'targetOptions', 'earExclusions'}};
    for i = 1:numel(paths)
        value = nestedField(layout, paths{i});
        if isstruct(value) && isfield(value, 'exclusionCenters') && ...
                isfield(value, 'exclusionRadiusMM')
            ears = value;
            return;
        end
    end
end

function value = nestedField(S, path)
    value = [];
    for i = 1:numel(path)
        if ~isstruct(S) || ~isfield(S, path{i})
            value = [];
            return;
        end
        S = S.(path{i});
    end
    value = S;
end

function tf = earExclusionsMatch(a, b, tol)
    ca = double(a.exclusionCenters);
    cb = double(b.exclusionCenters);
    ra = double(a.exclusionRadiusMM(:));
    rb = double(b.exclusionRadiusMM(:));
    if isscalar(ra) && size(ca, 1) > 1, ra = repmat(ra, size(ca, 1), 1); end
    if isscalar(rb) && size(cb, 1) > 1, rb = repmat(rb, size(cb, 1), 1); end
    tf = isequal(size(ca), size(cb)) && isequal(size(ra), size(rb)) && ...
        all(abs(ca(:) - cb(:)) <= tol) && all(abs(ra(:) - rb(:)) <= tol);
end

function fileName = defaultEarFile(skinCacheFile)
    [folder, stem] = fileparts(skinCacheFile);
    if endsWith(lower(stem), '_skinmesh')
        stem = stem(1:end - numel('_skinMesh'));
    end
    fileName = fullfile(folder, [stem '_earExclusions.mat']);
end

function [centers, radii] = railEarSpheres(earExclusions, opts)
    centers = zeros(0, 3);
    radii = zeros(0, 1);
    if ~strcmp(opts.railEarExclusionMode, 'sphere3d')
        return;
    end
    if ~isfield(earExclusions, 'exclusionCenters') || ...
            ~isfield(earExclusions, 'exclusionRadiusMM') || ...
            isempty(earExclusions.exclusionCenters)
        return;
    end
    centers = double(earExclusions.exclusionCenters);
    radii = double(earExclusions.exclusionRadiusMM(:));
    if isscalar(radii) && size(centers, 1) > 1
        radii = repmat(radii, size(centers, 1), 1);
    end
    if numel(radii) ~= size(centers, 1)
        warning('acsBuildCapMakerManufacturingStl:BadEarSphereExclusions', ...
            'Ear exclusion centers/radii do not match; skipping 3D ear rail exclusions.');
        centers = zeros(0, 3);
        radii = zeros(0, 1);
        return;
    end
    keep = all(isfinite(centers), 2) & isfinite(radii) & radii > 0;
    centers = centers(keep, :);
    radii = radii(keep);
end

function polys = railEarPolys(earExclusions, opts)
    polys = {};
    if strcmp(opts.railEarExclusionMode, 'projectedSpheres')
        if isfield(earExclusions, 'exclusionCenters') && ...
                isfield(earExclusions, 'exclusionRadiusMM') && ...
                ~isempty(earExclusions.exclusionCenters)
            centers = double(earExclusions.exclusionCenters);
            radii = double(earExclusions.exclusionRadiusMM(:));
            n = size(centers, 1);
            if numel(radii) == 1
                radii = repmat(radii, n, 1);
            end
            theta = linspace(0, 2*pi, 80);
            theta(end) = [];
            for i = 1:n
                x = centers(i, 1) + radii(i) * cos(theta);
                y = centers(i, 2) + radii(i) * sin(theta);
                polys{end + 1} = polyshape(x, y, 'Simplify', true); %#ok<AGROW>
            end
        end
    end
    polys = polys(:)';
end

function P = paintedRailVertexExclusionPoints(earExclusions)
    P = zeros(0, 3);
    if ~isfield(earExclusions, 'paintedExclusionCoordinatesMm') || ...
            isempty(earExclusions.paintedExclusionCoordinatesMm)
        return;
    end
    P = double(earExclusions.paintedExclusionCoordinatesMm);
    P = P(all(isfinite(P), 2), :);
end

function polys = holderSupportExclusionPolys(earPolys, implantPolys, opts)
    polys = {};
    if opts.holderSupportRespectEarExclusions
        polys = [polys, earPolys(:)']; %#ok<AGROW>
    end
    if opts.holderSupportRespectImplantExclusions
        polys = [polys, implantPolys(:)']; %#ok<AGROW>
    end
end

function checkLayoutAgainstEarExclusions(targetsMm, names, earExclusions, opts)
    if strcmp(opts.earElectrodePolicy, 'ignore')
        return;
    end
    minSignedDistance = inf(size(targetsMm, 1), 1);
    inside = false(size(targetsMm, 1), 1);
    if isfield(earExclusions, 'exclusionCenters') && ...
            isfield(earExclusions, 'exclusionRadiusMM') && ...
            ~isempty(earExclusions.exclusionCenters)
        centers = double(earExclusions.exclusionCenters);
        radii = double(earExclusions.exclusionRadiusMM(:));
        if isscalar(radii) && size(centers, 1) > 1
            radii = repmat(radii, size(centers, 1), 1);
        end
        if numel(radii) == size(centers, 1)
            for i = 1:size(centers, 1)
                d = sqrt(sum((targetsMm - centers(i, :)) .^ 2, 2)) - radii(i);
                replace = abs(d) < abs(minSignedDistance);
                minSignedDistance(replace) = d(replace);
                inside = inside | d < 0;
            end
        end
    end
    paintedPoints = paintedRailVertexExclusionPoints(earExclusions);
    if ~isempty(paintedPoints)
        dPainted = nearestPointDistances(targetsMm, paintedPoints) - ...
            opts.paintedExclusionVertexToleranceMm;
        paintedInside = dPainted <= 0;
        if any(paintedInside)
            replace = abs(dPainted) < abs(minSignedDistance);
            minSignedDistance(replace) = dPainted(replace);
            inside = inside | paintedInside;
        end
    end
    if ~any(inside)
        return;
    end
    txt = implantConflictText(names, inside, minSignedDistance);
    switch opts.earElectrodePolicy
        case 'error'
            error('acsBuildCapMakerManufacturingStl:ElectrodeInsideEarExclusion', ...
                ['Electrode holder center(s) fall inside ear/painted exclusion: %s. ', ...
                 'Signed distances are center-to-sphere-boundary mm; negative is inside.'], txt);
        case 'warn'
            warning('acsBuildCapMakerManufacturingStl:ElectrodeInsideEarExclusion', ...
                ['Electrode holder center(s) fall inside ear/painted exclusion: %s. ', ...
                 'Signed distances are center-to-sphere-boundary mm; negative is inside. ', ...
                 'Rerun the combined tES+EEG layout if these are not intentional.'], txt);
    end
end

function implantExclusions = resolveImplantExclusions(opts)
    implantExclusions = repmat(emptyImplantExclusion(), 0, 1);
    files = opts.implantExclusionFile;
    if isempty(files)
        return;
    end
    for i = 1:numel(files)
        fileName = files{i};
        if exist(fileName, 'file') ~= 2
            warning('acsBuildCapMakerManufacturingStl:ImplantExclusionNotFound', ...
                'Implant exclusion file not found: %s', fileName);
            continue;
        end
        try
            S = loadPreferredStructFromMat(fileName, ...
                {'exclusion', 'outForSave', 'outSaved', 'out'});
            implantExclusions(end + 1, 1) = normalizeImplantExclusion(S, fileName); %#ok<AGROW>
        catch ME
            warning('acsBuildCapMakerManufacturingStl:BadImplantExclusion', ...
                'Could not read implant exclusion %s: %s', fileName, ME.message);
        end
    end
end

function D = nearestPointDistances(Q, P)
    Q = double(Q);
    P = double(P);
    D = inf(size(Q, 1), 1);
    if isempty(Q) || isempty(P)
        return;
    end
    for i = 1:size(P, 1)
        d = sqrt(sum((Q - P(i, :)) .^ 2, 2));
        D = min(D, d);
    end
end

function value = loadPreferredStructFromMat(fileName, preferredNames)
    info = whos('-file', fileName);
    names = {info.name};
    for i = 1:numel(preferredNames)
        hit = find(strcmp(names, preferredNames{i}), 1);
        if isempty(hit)
            continue;
        end
        if ~strcmp(info(hit).class, 'struct')
            continue;
        end
        S = load(fileName, preferredNames{i});
        value = S.(preferredNames{i});
        return;
    end
    S = load(fileName);
    value = firstStruct(S);
end

function value = emptyImplantExclusion()
    value = struct( ...
        'name', '', ...
        'file', '', ...
        'marginMm', NaN, ...
        'coordinateFrame', '', ...
        'projectedCoordinatesMm', zeros(0, 3), ...
        'keepoutBoundaryMm', zeros(0, 3), ...
        'keepoutPoly', [], ...
        'railExclusionPolys', {{}});
end

function value = normalizeImplantExclusion(S, fileName)
    if isfield(S, 'exclusion') && isstruct(S.exclusion)
        S = S.exclusion;
    end
    value = emptyImplantExclusion();
    value.file = fileName;
    value.name = getOptionalField(S, 'name', fileStem(fileName));
    value.marginMm = getOptionalField(S, 'marginMm', NaN);
    value.coordinateFrame = getOptionalField(S, 'coordinateFrame', '');
    if ~isempty(value.coordinateFrame) && ...
            ~strcmpi(char(value.coordinateFrame), 'capMakerPrintMm')
        warning('acsBuildCapMakerManufacturingStl:NonPrintFrameImplantExclusion', ...
            ['Skipping implant exclusion "%s" from %s because its ', ...
             'coordinateFrame is "%s", not "capMakerPrintMm".'], ...
            value.name, fileName, char(value.coordinateFrame));
        return;
    elseif isempty(value.coordinateFrame)
        warning('acsBuildCapMakerManufacturingStl:UnknownFrameImplantExclusion', ...
            ['Skipping implant exclusion "%s" from %s because it does not ', ...
             'report a coordinateFrame. Regenerate this exclusion so it ', ...
             'can be written as capMakerPrintMm.'], value.name, fileName);
        return;
    end
    value.projectedCoordinatesMm = getOptionalField(S, ...
        'projectedCoordinatesMm', zeros(0, 3));
    value.keepoutBoundaryMm = getOptionalField(S, ...
        'keepoutBoundaryMm', zeros(0, 3));
    if isfield(S, 'keepoutPoly') && ~isempty(S.keepoutPoly)
        value.keepoutPoly = S.keepoutPoly;
    elseif isfield(S, 'keepoutPolyX') && isfield(S, 'keepoutPolyY') && ...
            ~isempty(S.keepoutPolyX) && ~isempty(S.keepoutPolyY)
        value.keepoutPoly = polyshape(double(S.keepoutPolyX(:)), ...
            double(S.keepoutPolyY(:)), 'Simplify', true);
    elseif ~isempty(value.keepoutBoundaryMm)
        value.keepoutPoly = polyshape(value.keepoutBoundaryMm(:, 1), ...
            value.keepoutBoundaryMm(:, 2), 'Simplify', true);
    end
    if isfield(S, 'railExclusionPolys') && ~isempty(S.railExclusionPolys)
        value.railExclusionPolys = S.railExclusionPolys;
    elseif ~isempty(value.keepoutPoly)
        value.railExclusionPolys = {value.keepoutPoly};
    end
end

function polys = railImplantPolys(implantExclusions, opts)
    polys = {};
    if strcmp(opts.implantRailExclusionMode, 'none') || isempty(implantExclusions)
        return;
    end
    for i = 1:numel(implantExclusions)
        if isfield(implantExclusions(i), 'railExclusionPolys') && ...
                ~isempty(implantExclusions(i).railExclusionPolys)
            polys = [polys, implantExclusions(i).railExclusionPolys(:)']; %#ok<AGROW>
        elseif isfield(implantExclusions(i), 'keepoutPoly') && ...
                ~isempty(implantExclusions(i).keepoutPoly)
            polys{end + 1} = implantExclusions(i).keepoutPoly; %#ok<AGROW>
        end
    end
end

function checkLayoutAgainstImplantExclusions(targetsMm, names, implantPolys, opts)
    if isempty(implantPolys) || strcmp(opts.implantElectrodePolicy, 'ignore')
        return;
    end
    inside = false(size(targetsMm, 1), 1);
    minSignedDistance = inf(size(targetsMm, 1), 1);
    for p = 1:numel(implantPolys)
        ps = implantPolys{p};
        if isempty(ps) || ps.NumRegions == 0 || area(ps) == 0
            continue;
        end
        insideThis = isinterior(ps, targetsMm(:, 1), targetsMm(:, 2));
        signedDistanceThis = signedDistanceToPolyBoundary(ps, targetsMm(:, 1:2), insideThis);
        replace = abs(signedDistanceThis) < abs(minSignedDistance);
        minSignedDistance(replace) = signedDistanceThis(replace);
        inside = inside | insideThis;
    end
    if ~any(inside)
        return;
    end
    txt = implantConflictText(names, inside, minSignedDistance);
    switch opts.implantElectrodePolicy
        case 'error'
            error('acsBuildCapMakerManufacturingStl:ElectrodeInsideImplantExclusion', ...
                ['Electrode holder center(s) fall inside implant exclusion: %s. ', ...
                 'Signed distances are center-to-boundary mm; negative is inside.'], txt);
        case 'warn'
            warning('acsBuildCapMakerManufacturingStl:ElectrodeInsideImplantExclusion', ...
                ['Electrode holder center(s) fall inside implant exclusion: %s. ', ...
                 'Signed distances are center-to-boundary mm; negative is inside. ', ...
                 'The holder mesh itself is not automatically removed.'], txt);
    end
end

function txt = implantConflictText(names, mask, signedDistance)
    rows = find(mask(:));
    parts = cell(numel(rows), 1);
    for i = 1:numel(rows)
        row = rows(i);
        d = signedDistance(row);
        if isfinite(d)
            if abs(d) < 0.25
                qualifier = 'near boundary';
            elseif d < 0
                qualifier = 'inside';
            else
                qualifier = 'outside';
            end
            parts{i} = sprintf('%s (%.3g mm, %s)', ...
                names{row}, d, qualifier);
        else
            parts{i} = names{row};
        end
    end
    txt = strjoin(parts, ', ');
end

function signedDistance = signedDistanceToPolyBoundary(ps, xy, inside)
    signedDistance = inf(size(xy, 1), 1);
    try
        [bx, by] = boundary(ps);
    catch
        return;
    end
    boundaryXY = [double(bx(:)), double(by(:))];
    boundaryXY = boundaryXY(all(isfinite(boundaryXY), 2), :);
    if isempty(boundaryXY)
        return;
    end
    for i = 1:size(xy, 1)
        d = min(hypot(boundaryXY(:, 1) - xy(i, 1), ...
            boundaryXY(:, 2) - xy(i, 2)));
        if inside(i)
            d = -d;
        end
        signedDistance(i) = d;
    end
end

function strap = makeStrapOccupancy(TRrails, TRskin, TRholders, earExclusions, opts)
    strap = struct();
    strap.mode = opts.strapMode;
    strap.anchors = zeros(0, 3);
    strap.outDirs = zeros(0, 3);
    strap.occFns = {};
    strap.extraPoints = [TRskin.Points; TRrails.Points; TRholders.Points];
    strap.params = struct();
    strap.frameOptions = struct();

    if strcmp(opts.strapMode, 'none')
        return;
    end

    common = defaultStrapCommon(opts);
    strapParams = mergeStructs(strapParamsFromCommon(common), opts.strapOptions);
    frameOpts = mergeStructs(strapFrameOptionsFromCommon(common), opts.strapFrameOptions);

    switch opts.strapMode
        case 'earRostral'
            [anchors, outDirs, source] = earRostralAnchors(TRrails, earExclusions, opts);
        case 'bboxLateral'
            [anchors, outDirs, source] = bboxLateralAnchors(TRrails, opts);
        otherwise
            error('acsBuildCapMakerManufacturingStl:BadStrapMode', ...
                'Unknown strap mode "%s".', opts.strapMode);
    end

    if isempty(anchors)
        warning('acsBuildCapMakerManufacturingStl:NoStrapAnchors', ...
            'No strap anchors were found. Continuing without straps.');
        strap.mode = 'none';
        return;
    end

    strapParams = maybeAutoRaiseStrapRamp(strapParams, anchors, opts);
    strap.params = strapParams;
    strap.frameOptions = frameOpts;
    logMsg(opts, ...
        '  strap parameters: style=%s, amp=%.3g mm, pitch=%.3g mm, width=%.3g mm, thickness=%.3g mm, rampRise=%.3g mm', ...
        char(getStructField(strapParams, 'style', opts.strapCorrStyle)), ...
        double(getStructField(strapParams, 'ampMM', opts.strapCorrAmpMm)), ...
        double(getStructField(strapParams, 'pitchMM', opts.strapCorrPitchMm)), ...
        double(getStructField(strapParams, 'widthMM', 10)), ...
        double(getStructField(strapParams, 'thickMM', 2.4)), ...
        double(getStructField(strapParams, 'rampRiseMM', 0)));

    strap.anchorSource = source;
    strap.anchors = anchors;
    strap.outDirs = outDirs;
    for i = 1:size(anchors, 1)
        anchor = anchors(i, :);
        outDir = outDirs(i, :);
        paramsI = strapParams;
        frameI = frameOpts;
        strap.occFns{end + 1} = @(X,Y,Z) strapFn_world( ...
            X, Y, Z, anchor, outDir, paramsI, frameI); %#ok<AGROW>
        strap.extraPoints = [strap.extraPoints; ...
            strapExtentPoints(anchor, outDir, paramsI, frameI)]; %#ok<AGROW>
    end
end

function strapParams = maybeAutoRaiseStrapRamp(strapParams, anchors, opts)
    if ~opts.strapRampAutoRise || isempty(anchors)
        return;
    end
    T = double(getStructField(strapParams, 'thickMM', 2.4));
    bedClearance = max(0, double(getStructField(strapParams, ...
        'bedClearanceMM', opts.strapBedClearanceMm)));
    zLow = opts.zBedMm + T / 2 + bedClearance;
    requestedRise = max(0, max(double(anchors(:, 3))) - zLow + ...
        opts.strapRampAttachOverlapMm);
    currentRise = double(getStructField(strapParams, 'rampRiseMM', 0));
    if requestedRise > currentRise
        strapParams.rampRiseMM = requestedRise;
    end
end

function common = defaultStrapCommon(opts)
    common = struct( ...
        'zBed', opts.zBedMm, ...
        'bedRunMM', 28, ...
        'rampRunMM', 14, ...
        'rampRiseMM', 10, ...
        'strapWidthMM', 10, ...
        'strapThickMM', 2.4, ...
        'strapBedClearanceMM', opts.strapBedClearanceMm, ...
        'corrAmpMM', opts.strapCorrAmpMm, ...
        'corrPitchMM', opts.strapCorrPitchMm, ...
        'corrStyle', opts.strapCorrStyle, ...
        'corrFitIntegerCycles', opts.strapCorrFitIntegerCycles, ...
        'ringOuterDiaMM', 20, ...
        'ringTubeDiaMM', 3.5, ...
        'ringOverlapMM', 5, ...
        'ringOffsetMM', 43);
end

function params = strapParamsFromCommon(common)
    params = struct( ...
        'widthMM', common.strapWidthMM, ...
        'thickMM', common.strapThickMM, ...
        'bedClearanceMM', common.strapBedClearanceMM, ...
        'ampMM', common.corrAmpMM, ...
        'pitchMM', common.corrPitchMM, ...
        'style', common.corrStyle, ...
        'fitIntegerCycles', common.corrFitIntegerCycles, ...
        'bedRunMM', common.bedRunMM, ...
        'rampRunMM', common.rampRunMM, ...
        'rampRiseMM', common.rampRiseMM, ...
        'nCycles', 0, ...
        'xStart', 0, ...
        'ringTubeDiaMM', common.ringTubeDiaMM, ...
        'ringOuterDiaMM', common.ringOuterDiaMM, ...
        'ringOverlapMM', common.ringOverlapMM);
end

function frameOpts = strapFrameOptionsFromCommon(common)
    frameOpts = struct( ...
        'zBed', common.zBed, ...
        'ringOffMM', common.ringOffsetMM, ...
        'startShiftMM', 0, ...
        'loop', struct( ...
            'enable', true, ...
            'xCenterMM', -4, ...
            'outerXMM', 12, ...
            'outerYMM', 18, ...
            'frameMM', 3.5, ...
            'thickMM', 2.8, ...
            'zCenterMM', common.zBed + 2.8/2));
end

function [anchors, outDirs, source] = earRostralAnchors(TRrails, earExclusions, opts)
    anchors = zeros(0, 3);
    outDirs = zeros(0, 3);
    source = 'earRostral';
    if ~isfield(earExclusions, 'exclusionCenters') || ...
            ~isfield(earExclusions, 'exclusionRadiusMM') || ...
            size(earExclusions.exclusionCenters, 1) < 2
        [anchors, outDirs, source] = bboxLateralAnchors(TRrails, opts);
        source = ['fallback_' source];
        return;
    end

    centers = double(earExclusions.exclusionCenters);
    radii = double(earExclusions.exclusionRadiusMM(:));
    if numel(radii) == 1
        radii = repmat(radii, size(centers, 1), 1);
    end

    [~, leftRow] = min(centers(:, 1));
    [~, rightRow] = max(centers(:, 1));
    rows = [leftRow; rightRow];
    signs = [-1; 1];
    for i = 1:2
        c = centers(rows(i), :);
        r = radii(rows(i));
        target = c;
        target(2) = c(2) + r + opts.strapRostralOffsetMm;
        target(3) = opts.zBedMm;
        anchor = nearestRailAnchor(TRrails, target, signs(i), opts);
        anchors(end + 1, :) = anchor; %#ok<AGROW>
        outDirs(end + 1, :) = [signs(i) 0 0]; %#ok<AGROW>
    end
end

function anchor = nearestRailAnchor(TRrails, target, sideSign, opts)
    V = double(TRrails.Points);
    if isempty(V)
        anchor = target;
        return;
    end
    sideMask = sideSign * V(:, 1) >= sideSign * target(1) - 5;
    zMask = abs(V(:, 3) - opts.zBedMm) <= opts.strapAnchorZBandMm;
    candidate = sideMask & zMask;
    if nnz(candidate) < 3
        candidate = sideMask;
    end
    if nnz(candidate) < 3
        candidate = true(size(V, 1), 1);
    end
    rows = find(candidate);
    d2 = sum((V(rows, 1:2) - target(1:2)) .^ 2, 2);
    [~, localIdx] = min(d2);
    anchor = V(rows(localIdx), :);
end

function [anchors, outDirs, source] = bboxLateralAnchors(TRrails, opts)
    V = double(TRrails.Points);
    if isempty(V)
        anchors = zeros(0, 3);
        outDirs = zeros(0, 3);
        source = 'bboxLateral';
        return;
    end
    zMask = abs(V(:, 3) - opts.zBedMm) <= opts.strapAnchorZBandMm;
    if nnz(zMask) < 3
        zMask = true(size(V, 1), 1);
    end
    rows = find(zMask);
    [~, leftLocal] = min(V(rows, 1));
    [~, rightLocal] = max(V(rows, 1));
    anchors = [V(rows(leftLocal), :); V(rows(rightLocal), :)];
    outDirs = [-1 0 0; 1 0 0];
    source = 'bboxLateral';
end

function stats = meshStats(TR)
    stats = struct();
    if isempty(TR) || isempty(TR.Points)
        stats.nVertices = 0;
        stats.nFaces = 0;
        stats.bounds = struct('min', [], 'max', []);
        return;
    end
    stats.nVertices = size(TR.Points, 1);
    stats.nFaces = size(TR.ConnectivityList, 1);
    stats.bounds = pointBounds(TR.Points);
end

function stats = occupancyComponentStats(occ)
    occ = logical(occ);
    CC = bwconncomp(occ, 26);
    sizes = cellfun(@numel, CC.PixelIdxList);
    stats = struct();
    stats.nComponents = CC.NumObjects;
    stats.componentVoxels = sort(sizes(:), 'descend');
    if isempty(sizes)
        stats.largestVoxels = 0;
        stats.totalVoxels = 0;
    else
        stats.largestVoxels = max(sizes);
        stats.totalVoxels = sum(sizes);
    end
end

function bounds = pointBounds(P)
    bounds = struct('min', min(P, [], 1), 'max', max(P, [], 1));
end

function fig = makeQcFigure(TRskin, TRholders, TRrails, TRtpe, TRpla, ...
        targetsMm, names, roles, earExclusions, implantExclusions, strap, ...
        holderInfo, opts, figVisible)
    TRskinDisplay = decimateForQc(TRskin, opts.qcMaxFaces, opts, 'skin QC mesh');
    TRholdersDisplay = decimateForQc(TRholders, opts.qcMaxFaces, opts, 'holder QC mesh');
    TRrailsDisplay = decimateForQc(TRrails, opts.qcMaxFaces, opts, 'rail QC mesh');
    TRtpeDisplay = decimateForQc(TRtpe, opts.qcMaxFaces, opts, 'TPE QC mesh');
    TRplaDisplay = decimateForQc(TRpla, opts.qcMaxFaces, opts, 'PLA QC mesh');
    holderSurfaceMm = holderSurfacePointsFromInfo(holderInfo, targetsMm);

    fig = figure('Name', 'CapMaker manufacturing STL QC', ...
        'NumberTitle', 'off', ...
        'Color', 'w', ...
        'Visible', figVisible, ...
        'Position', [100 80 1250 650]);
    tiledlayout(fig, 1, 2, 'Padding', 'compact', 'TileSpacing', 'compact');

    ax1 = nexttile;
    hold(ax1, 'on');
    drawTri(ax1, TRskinDisplay, [0.78 0.80 0.84], 0.18, 'none');
    drawTri(ax1, TRrailsDisplay, [0.08 0.30 0.85], 0.60, 'none');
    drawTri(ax1, TRholdersDisplay, [0.05 0.05 0.05], 0.75, 'none');
    drawHolderSiteMarkers(ax1, holderSurfaceMm, targetsMm);
    drawEarSpheres(ax1, earExclusions);
    drawImplantExclusions(ax1, implantExclusions);
    drawStrapAnchors(ax1, strap);
    if opts.showQcLabels
        labelPoints3(ax1, holderSurfaceMm, names, roles);
    end
    title(ax1, 'Pre-fuse components');
    format3d(ax1);

    ax2 = nexttile;
    hold(ax2, 'on');
    drawTri(ax2, TRplaDisplay, [0.88 0.88 0.88], 0.65, 'none');
    drawTri(ax2, TRtpeDisplay, [0.05 0.25 0.85], 0.55, 'none');
    drawHolderSiteMarkers(ax2, holderSurfaceMm, targetsMm);
    drawImplantExclusions(ax2, implantExclusions);
    drawStrapAnchors(ax2, strap);
    if isempty(TRplaDisplay) && isempty(TRtpeDisplay)
        title(ax2, 'Final STL meshes (not built in preflight)');
        text(ax2, 0.5, 0.5, 'Run the STL build cell to voxel-fuse TPE/PLA meshes.', ...
            'Units', 'normalized', ...
            'HorizontalAlignment', 'center', ...
            'FontSize', 11, ...
            'Color', [0.25 0.25 0.25]);
    else
        title(ax2, 'Final STL meshes');
    end
    format3d(ax2);

    sgtitle(fig, sprintf('CapMaker manufacturing STL QC: %s', opts.manufacturingTag), ...
        'Interpreter', 'none');
end

function P = holderSurfacePointsFromInfo(holderInfo, fallbackMm)
    P = fallbackMm;
    if ~isstruct(holderInfo) || isempty(holderInfo) || ...
            numel(holderInfo) ~= size(fallbackMm, 1) || ...
            ~isfield(holderInfo, 'surfacePointMm')
        return;
    end
    candidate = reshape([holderInfo.surfacePointMm], 3, []).';
    if size(candidate, 1) == size(fallbackMm, 1) && ...
            all(isfinite(candidate(:)))
        P = candidate;
    end
end

function drawHolderSiteMarkers(ax, holderSurfaceMm, requestedMm)
    if isempty(holderSurfaceMm)
        return;
    end
    plot3(ax, holderSurfaceMm(:, 1), holderSurfaceMm(:, 2), holderSurfaceMm(:, 3), ...
        'ko', 'MarkerFaceColor', 'y', 'MarkerSize', 5, ...
        'DisplayName', 'holder surface point');
    if nargin >= 3 && ~isempty(requestedMm) && ...
            size(requestedMm, 1) == size(holderSurfaceMm, 1)
        snapDistance = vecnorm(holderSurfaceMm - requestedMm, 2, 2);
        moved = snapDistance > 0.25;
        if any(moved)
            plot3(ax, requestedMm(moved, 1), requestedMm(moved, 2), ...
                requestedMm(moved, 3), 'o', ...
                'MarkerEdgeColor', [0.35 0.35 0.35], ...
                'MarkerFaceColor', 'none', ...
                'MarkerSize', 4, ...
                'LineWidth', 0.8, ...
                'DisplayName', 'requested layout point');
        end
    end
end

function drawTri(ax, TR, color, alphaValue, edgeColor)
    if isempty(TR) || isempty(TR.Points)
        return;
    end
    patch(ax, ...
        'Faces', TR.ConnectivityList, ...
        'Vertices', TR.Points, ...
        'FaceColor', color, ...
        'FaceAlpha', alphaValue, ...
        'EdgeColor', edgeColor);
end

function drawEarSpheres(ax, earExclusions)
    if isfield(earExclusions, 'exclusionCenters') && ...
            isfield(earExclusions, 'exclusionRadiusMM') && ...
            ~isempty(earExclusions.exclusionCenters)
        centers = double(earExclusions.exclusionCenters);
        radii = double(earExclusions.exclusionRadiusMM(:));
        if numel(radii) == 1
            radii = repmat(radii, size(centers, 1), 1);
        end
        [sx, sy, sz] = sphere(24);
        colors = [0.95 0.45 0.05; 0.05 0.35 0.95];
        for i = 1:size(centers, 1)
            c = centers(i, :);
            r = radii(i);
            color = colors(1 + mod(i - 1, size(colors, 1)), :);
            surf(ax, c(1) + r*sx, c(2) + r*sy, c(3) + r*sz, ...
                'FaceColor', color, ...
                'FaceAlpha', 0.12, ...
                'EdgeColor', color, ...
                'EdgeAlpha', 0.15);
        end
    end
    if isfield(earExclusions, 'paintedExclusionCoordinatesMm') && ...
            ~isempty(earExclusions.paintedExclusionCoordinatesMm)
        P = double(earExclusions.paintedExclusionCoordinatesMm);
        P = P(all(isfinite(P), 2), :);
        if ~isempty(P)
            scatter3(ax, P(:, 1), P(:, 2), P(:, 3), 16, ...
                [0.95 0.10 0.10], 'filled', ...
                'MarkerEdgeColor', [0.15 0.02 0.02], ...
                'LineWidth', 0.4);
        end
    end
end

function drawImplantExclusions(ax, implantExclusions)
    if isempty(implantExclusions)
        return;
    end
    for i = 1:numel(implantExclusions)
        if isfield(implantExclusions(i), 'projectedCoordinatesMm') && ...
                ~isempty(implantExclusions(i).projectedCoordinatesMm)
            P = double(implantExclusions(i).projectedCoordinatesMm);
            scatter3(ax, P(:, 1), P(:, 2), P(:, 3), 18, ...
                [0.95 0.05 0.45], 'filled', 'MarkerEdgeColor', 'k');
        end
        if isfield(implantExclusions(i), 'keepoutBoundaryMm') && ...
                ~isempty(implantExclusions(i).keepoutBoundaryMm)
            B = double(implantExclusions(i).keepoutBoundaryMm);
            plot3(ax, B(:, 1), B(:, 2), B(:, 3), ...
                'Color', [0.85 0.00 0.40], 'LineWidth', 2.2);
            label = char(getOptionalField(implantExclusions(i), 'name', 'implant'));
            center = mean(B(isfinite(sum(B, 2)), :), 1);
            if all(isfinite(center))
                text(ax, center(1), center(2), center(3), label, ...
                    'Color', [0.60 0.00 0.30], ...
                    'FontWeight', 'bold', ...
                    'Interpreter', 'none');
            end
        end
    end
end

function TRout = decimateForQc(TRin, maxFaces, opts, label)
    TRout = TRin;
    if isempty(maxFaces) || isempty(TRin) || isempty(TRin.Points)
        return;
    end
    nFaces = size(TRin.ConnectivityList, 1);
    if nFaces <= maxFaces
        return;
    end
    logMsg(opts, 'Decimating %s from %d to about %d faces for display.', ...
        label, nFaces, maxFaces);
    try
        [F2, V2] = reducepatch(TRin.ConnectivityList, TRin.Points, maxFaces);
        TRout = triangulation(F2, V2);
    catch ME
        warning('acsBuildCapMakerManufacturingStl:QcDecimationFailed', ...
            'Could not decimate %s (%s). Rendering full mesh.', label, ME.message);
        TRout = TRin;
    end
end

function drawStrapAnchors(ax, strap)
    if ~isfield(strap, 'anchors') || isempty(strap.anchors)
        return;
    end
    A = strap.anchors;
    D = strap.outDirs;
    scatter3(ax, A(:, 1), A(:, 2), A(:, 3), 80, ...
        'm', 'filled', 'MarkerEdgeColor', 'k');
    scale = 15;
    quiver3(ax, A(:, 1), A(:, 2), A(:, 3), ...
        scale * D(:, 1), scale * D(:, 2), scale * D(:, 3), ...
        0, 'Color', 'm', 'LineWidth', 2);
    lineLength = 35;
    if isfield(strap, 'frameOptions') && isfield(strap.frameOptions, 'ringOffMM') && ...
            ~isempty(strap.frameOptions.ringOffMM)
        lineLength = double(strap.frameOptions.ringOffMM);
    end
    for i = 1:size(A, 1)
        P = [A(i, :); A(i, :) + lineLength * D(i, :)];
        plot3(ax, P(:, 1), P(:, 2), P(:, 3), 'm--', 'LineWidth', 1.4);
    end
end

function labelPoints3(ax, P, names, roles)
    for i = 1:size(P, 1)
        label = names{i};
        if ~isempty(roles{i})
            label = sprintf('%s (%s)', label, roles{i});
        end
        text(ax, P(i, 1), P(i, 2), P(i, 3), [' ' label], ...
            'FontSize', 8, ...
            'Color', 'k', ...
            'Interpreter', 'none');
    end
end

function format3d(ax)
    axis(ax, 'equal');
    axis(ax, 'vis3d');
    grid(ax, 'on');
    xlabel(ax, 'X print mm');
    ylabel(ax, 'Y print mm');
    zlabel(ax, 'Z print mm');
    view(ax, 3);
    camlight(ax, 'headlight');
    lighting(ax, 'gouraud');
end

function saveQcFigure(fig, fileName)
    ensureDir(fileparts(fileName));
    try
        exportgraphics(fig, fileName, 'Resolution', 200);
    catch
        saveas(fig, fileName);
    end
end

function value = compactEarExclusions(earExclusions)
    value = struct();
    fields = {'outputFile', 'jsonFile', 'exclusionCenters', 'exclusionRadiusMM', ...
        'leftCenterMm', 'rightCenterMm', 'leftRadiusMm', 'rightRadiusMm', ...
        'paintedExclusionVertex', 'paintedExclusionCoordinatesMm', ...
        'customExclusionVertexInd', 'customExclusionCoordinatesMm', ...
        'method', 'source'};
    for i = 1:numel(fields)
        if isfield(earExclusions, fields{i})
            value.(fields{i}) = earExclusions.(fields{i});
        end
    end
end

function value = compactImplantExclusions(implantExclusions)
    value = repmat(struct( ...
        'name', '', ...
        'file', '', ...
        'marginMm', NaN, ...
        'coordinateFrame', '', ...
        'projectedCoordinatesMm', [], ...
        'keepoutBoundaryMm', []), 0, 1);
    if isempty(implantExclusions)
        return;
    end
    fields = {'name', 'file', 'marginMm', 'coordinateFrame', ...
        'projectedCoordinatesMm', 'keepoutBoundaryMm'};
    for i = 1:numel(implantExclusions)
        item = struct();
        for f = 1:numel(fields)
            if isfield(implantExclusions(i), fields{f})
                item.(fields{f}) = implantExclusions(i).(fields{f});
            else
                item.(fields{f}) = [];
            end
        end
        value(end + 1, 1) = item; %#ok<AGROW>
    end
end

function value = getOptionalField(S, fieldName, defaultValue)
    if isstruct(S) && isfield(S, fieldName)
        value = S.(fieldName);
    else
        value = defaultValue;
    end
end

function strap = stripStrapFns(strap)
    if isfield(strap, 'occFns')
        strap = rmfield(strap, 'occFns');
    end
end

function out = stripForSave(out)
    if isfield(out, 'figure')
        out = rmfield(out, 'figure');
    end
    if isfield(out, 'meshes')
        out = rmfield(out, 'meshes');
    end
end

function args = structToNameValue(S)
    args = {};
    if isempty(S)
        return;
    end
    names = fieldnames(S);
    for i = 1:numel(names)
        args(end + 1:end + 2) = {names{i}, S.(names{i})}; %#ok<AGROW>
    end
end

function out = mergeStructs(a, b)
    out = a;
    if isempty(b)
        return;
    end
    names = fieldnames(b);
    for i = 1:numel(names)
        out.(names{i}) = b.(names{i});
    end
end

function value = getStructField(S, fieldName, defaultValue)
    if isstruct(S) && isfield(S, fieldName) && ~isempty(S.(fieldName))
        value = S.(fieldName);
    else
        value = defaultValue;
    end
end

function mode = normalizeRailEarMode(modeIn)
    key = lower(regexprep(strtrim(char(modeIn)), '[\s_\-]+', ''));
    switch key
        case {'sphere3d', 'spheres3d', '3dsphere', '3dspheres', 'sphere'}
            mode = 'sphere3d';
        case {'projectedspheres', 'sphereprojection', 'projected', ...
                'xydisk', 'xydisks'}
            mode = 'projectedSpheres';
        case {'none', 'off', 'no'}
            mode = 'none';
        otherwise
            error('acsBuildCapMakerManufacturingStl:BadRailEarMode', ...
                'railEarExclusionMode must be ''sphere3d'', ''projectedSpheres'', or ''none''.');
    end
end

function mode = normalizeEarMode(modeIn)
    mode = lower(strtrim(char(modeIn)));
    switch mode
        case {'auto', 'always', 'never'}
            % accepted
        case {'none', 'off', 'no'}
            mode = 'none';
        case {'select', 'edit'}
            mode = 'always';
        case {'reuse', 'load'}
            mode = 'never';
        otherwise
            error('acsBuildCapMakerManufacturingStl:BadEarMode', ...
                'earExclusionMode must be ''auto'', ''always'', ''never'', or ''none''.');
    end
end

function mode = normalizeStrapMode(modeIn)
    mode = lower(strtrim(char(modeIn)));
    switch mode
        case {'earrostral', 'ear', 'ears', 'rostralear'}
            mode = 'earRostral';
        case {'bboxlateral', 'lateral', 'bbox'}
            mode = 'bboxLateral';
        case {'none', 'off', 'no'}
            mode = 'none';
        otherwise
            error('acsBuildCapMakerManufacturingStl:BadStrapMode', ...
                'strapMode must be ''earRostral'', ''bboxLateral'', or ''none''.');
    end
end

function style = normalizeStrapCorrStyle(styleIn)
    key = lower(regexprep(strtrim(char(styleIn)), '[\s_\-]+', ''));
    switch key
        case {'rectilinear', 'rect', 'square', 'squarewave', ...
                'voxel', 'voxelnative'}
            style = 'rectilinear';
        case {'swept', 'legacy', 'continuous'}
            style = 'swept';
        otherwise
            error('acsBuildCapMakerManufacturingStl:BadStrapCorrStyle', ...
                'strapCorrStyle must be ''rectilinear'' or ''swept''.');
    end
end

function mode = normalizeHolderSupportMode(modeIn)
    mode = lower(strtrim(char(modeIn)));
    switch mode
        case {'nearestrail', 'nearest', 'on', 'auto'}
            mode = 'nearestRail';
        case {'none', 'off', 'no'}
            mode = 'none';
        otherwise
            error('acsBuildCapMakerManufacturingStl:BadHolderSupportMode', ...
                'holderSupportMode must be ''nearestRail'' or ''none''.');
    end
end

function mode = normalizeHolderNormalMode(modeIn)
    mode = lower(strtrim(char(modeIn)));
    switch regexprep(mode, '[\s_\-]+', '')
        case {'vertex', 'raw', 'legacy'}
            mode = 'vertex';
        case {'smooth', 'smoothed', 'interpolated'}
            mode = 'smooth';
        case {'autosmooth', 'auto', 'repair'}
            mode = 'autoSmooth';
        otherwise
            error('acsBuildCapMakerManufacturingStl:BadHolderNormalMode', ...
                ['holderNormalMode must be ''autoSmooth'', ', ...
                 '''smooth'', or ''vertex''.']);
    end
end

function mode = normalizeHolderPlacementSurfaceMode(modeIn)
    key = lower(regexprep(strtrim(char(modeIn)), '[\s_\-]+', ''));
    switch key
        case {'full', 'fulllayout', 'layout', 'source', 'original'}
            mode = 'full';
        case {'manufacturing', 'decimated', 'rail', 'rails'}
            mode = 'manufacturing';
        otherwise
            error('acsBuildCapMakerManufacturingStl:BadHolderPlacementSurfaceMode', ...
                'holderPlacementSurfaceMode must be ''full'' or ''manufacturing''.');
    end
end

function mode = normalizeHolderBridgeMode(modeIn)
    mode = lower(strtrim(char(modeIn)));
    switch mode
        case {'auto', 'on', 'true'}
            mode = 'auto';
        case {'none', 'off', 'no', 'false'}
            mode = 'none';
        otherwise
            error('acsBuildCapMakerManufacturingStl:BadHolderBridgeMode', ...
                'holderBridgeMode must be ''auto'' or ''none''.');
    end
end

function mode = normalizeHoleKeepoutMode(modeIn)
    mode = lower(strtrim(char(modeIn)));
    switch mode
        case {'flared', 'frustum', 'frusta', 'cylinder', 'cylindrical', 'default'}
            mode = 'flared';
        case {'tetra', 'tetras', 'tetrahedral', 'legacy'}
            mode = 'tetra';
        case {'flaredandtetra', 'flared+tetra', 'frustumandtetra', ...
                'frustum+tetra', 'both', 'hybrid'}
            mode = 'flaredAndTetra';
        otherwise
            error('acsBuildCapMakerManufacturingStl:BadHoleKeepoutMode', ...
                'holeKeepoutMode must be ''flared'', ''tetra'', or ''flaredAndTetra''.');
    end
end

function mode = normalizeImplantRailMode(modeIn)
    mode = lower(strtrim(char(modeIn)));
    switch mode
        case {'projectedpolys', 'projectedpoly', 'polys', 'polygon', 'polygons', 'on', 'auto'}
            mode = 'projectedPolys';
        case {'none', 'off', 'no'}
            mode = 'none';
        otherwise
            error('acsBuildCapMakerManufacturingStl:BadImplantRailMode', ...
                'implantRailExclusionMode must be ''projectedPolys'' or ''none''.');
    end
end

function policy = normalizeImplantElectrodePolicy(policyIn)
    policy = lower(strtrim(char(policyIn)));
    switch policy
        case {'warn', 'warning'}
            policy = 'warn';
        case {'error', 'fail', 'stop'}
            policy = 'error';
        case {'ignore', 'none', 'off'}
            policy = 'ignore';
        otherwise
            error('acsBuildCapMakerManufacturingStl:BadImplantElectrodePolicy', ...
                'implantElectrodePolicy must be ''warn'', ''error'', or ''ignore''.');
    end
end

function files = normalizeFileList(value)
    if isempty(value)
        files = {};
    elseif iscell(value)
        files = cellfun(@(x) expandUserPath(char(x)), value(:), ...
            'UniformOutput', false);
    elseif isstring(value)
        files = cellfun(@(x) expandUserPath(char(x)), cellstr(value(:)), ...
            'UniformOutput', false);
    elseif ischar(value)
        if size(value, 1) > 1
            files = cellfun(@expandUserPath, cellstr(value), ...
                'UniformOutput', false);
        else
            files = {expandUserPath(char(value))};
        end
    else
        error('acsBuildCapMakerManufacturingStl:BadFileList', ...
            'Expected a filename, string array, or cell array of filenames.');
    end
    files = files(~cellfun(@isempty, files));
end

function names = normalizeNameInput(names)
    if isempty(names)
        names = {};
    elseif ischar(names) || isstring(names)
        names = toCellstrList(names);
    elseif iscell(names)
        names = cellfun(@char, names(:), 'UniformOutput', false);
    else
        error('acsBuildCapMakerManufacturingStl:BadNames', ...
            'electrodeNames must be a cell array, char, or string array.');
    end
end

function values = toCellstrList(values)
    if iscell(values)
        values = cellfun(@char, values(:), 'UniformOutput', false);
    elseif isstring(values)
        values = cellstr(values(:));
    elseif ischar(values)
        values = cellstr(values);
    else
        error('acsBuildCapMakerManufacturingStl:BadCellstrInput', ...
            'Expected a cell array, string array, or character array.');
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

function stem = fileStem(fileName)
    [~, stem] = fileparts(char(fileName));
end

function name = safeName(name)
    name = regexprep(char(name), '[^a-zA-Z0-9_+-]', '_');
    if isempty(name)
        name = 'capMakerManufacturing';
    end
end

function pathOut = expandUserPath(pathOut)
    if isempty(pathOut)
        return;
    end
    if startsWith(pathOut, '~')
        homeDir = getenv('HOME');
        if isempty(homeDir)
            homeDir = char(java.lang.System.getProperty('user.home'));
        end
        if numel(pathOut) == 1
            pathOut = homeDir;
        elseif pathOut(2) == filesep || pathOut(2) == '/'
            pathOut = fullfile(homeDir, pathOut(3:end));
        end
    end
end

function logMsg(opts, varargin)
    if opts.verbose
        fprintf([varargin{1} '\n'], varargin{2:end});
        drawnow('limitrate');
    end
end

function logElapsed(opts, label, timerValue)
    if opts.verbose
        fprintf('%s in %.1f s.\n', label, toc(timerValue));
    end
end
