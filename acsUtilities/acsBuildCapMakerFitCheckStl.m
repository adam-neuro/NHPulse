function out = acsBuildCapMakerFitCheckStl(layoutOrSkin, varargin)
% ACSBUILDCAPMAKERFITCHECKSTL Build a fast PLA-only cap fit-check scaffold.
%
% out = acsBuildCapMakerFitCheckStl(layout)
% creates a minimal PLA scaffold from a capMaker skin mesh: a sparse
% triangular rail grid plus small circular electrode-location markers when
% layout coordinates are available. The output is intended to test gross cap
% shape quickly before committing to a full TPE-on-PLA manufacturing run.
%
% layoutOrSkin may be a finalized layout struct/MAT report, a skin-cache MAT
% file containing TRskin, or a triangulation. If a layout is supplied, the
% function uses layout.layout.skin.cacheFile unless skinCacheFile is supplied.
%
% Name-value options:
%   skinCacheFile        : explicit capMaker skin cache ['']
%   outputDir            : folder for STL/report ['']
%   fitCheckTag          : output stem ['']
%   force                : overwrite existing outputs [false]
%   electrodeNames       : subset of layout names to mark [{} = all]
%   includeElectrodeMarkers : add small circular markers [true]
%   gridSurfaceMaxFaces  : decimated triangle-grid target faces [140]
%   railWidthMm          : PLA rail width [2.5]
%   railHeightMm         : PLA rail height [2]
%   railEmbedFraction    : fraction of rail below skin surface [0.45]
%   railMinLengthMm      : skip short decimated edges [3]
%   railZThresholdMm     : ignore crop-bed/base faces below this Z [1]
%   railPerimeterFactor  : perimeter rail width multiplier [1.5]
%   railEdgeMarginMm     : omit rails within this distance of crop rim [10]
%   markerOuterDiameterMm: electrode marker outside diameter [7]
%   markerInnerDiameterMm: electrode marker inside diameter [4]
%   markerHeightMm       : electrode marker height along surface normal [0.8]
%   markerEmbedMm        : marker depth below surface [0.1]
%   markerSegments       : marker circle resolution [24]
%   markerSupportCount   : support struts from marker to grid vertices [3]
%   markerSupportMaxLengthMm : warn if marker support exceeds this [18]
%   earExclusionMode     : 'auto', 'always', 'never', or 'none' ['auto']
%   earExclusionFile     : explicit saved ear-exclusion MAT file ['']
%   earRailExclusionGeometry : 'sphere3d', 'xyDisk', or 'none' ['sphere3d']
%   paintedExclusionVertexToleranceMm : exact painted-vertex match tolerance [1e-3]
%   implantExclusionFile : saved implant/headpost exclusion MAT file(s) ['']
%   componentCleanupMode : 'none' or 'largest' rail component cleanup ['none']
%   showFigures          : show QC figure [false]
%   saveFigures          : save QC PNG [false]
%   saveMeshMat          : save mesh MAT [true]
%   verbose              : print summary [true]

    if nargin < 1 || isempty(layoutOrSkin)
        error('acsBuildCapMakerFitCheckStl:MissingInput', ...
            'Provide a layout, skin-cache file, or triangulation.');
    end

    opts = parseInputs(varargin{:});
    addLocalDependencies();

    [layout, layoutSource] = readLayoutOrEmpty(layoutOrSkin);
    [TRskinFull, skinSource] = readSkinMesh(layoutOrSkin, layout, opts);
    [names, targetsMm, roles] = selectedLayoutSites(layout, opts);
    earExclusions = resolveEarExclusions(layoutOrSkin, skinSource, opts);
    implantExclusions = resolveImplantExclusions(opts);
    [earSphereCenters, earSphereRadii] = railEarSpheres(earExclusions, opts);
    exclusionPolys = railImplantPolys(implantExclusions);
    exclusionPolys = [railEarPolys(earExclusions, opts), exclusionPolys]; %#ok<AGROW>
    paintedVertexPoints = paintedRailVertexExclusionPoints(earExclusions);

    opts = resolveOutputPaths(layoutSource, skinSource, opts);
    ensureDir(opts.outputDir);
    requireWritableOutputs(opts);

    TRgridSkin = decimateTriangulation(TRskinFull, opts.gridSurfaceMaxFaces, opts);
    [TRrails, railBuildInfo] = makeEdgeRails(TRgridSkin, ...
        opts.railWidthMm, opts.railHeightMm, ...
        opts.railEmbedFraction, opts.railMinLengthMm, ...
        opts.railZThresholdMm, [], ...
        'EarExcludePolys', exclusionPolys, ...
        'BoundaryMarginMm', opts.railEdgeMarginMm, ...
        'SphereExcludeCenters', earSphereCenters, ...
        'SphereExcludeRadii', earSphereRadii, ...
        'VertexExcludePoints', paintedVertexPoints, ...
        'VertexExcludeToleranceMm', opts.paintedExclusionVertexToleranceMm, ...
        'PerimeterFactor', opts.railPerimeterFactor, ...
        'Verbose', opts.verbose);
    warnSparseRailBuild(railBuildInfo, opts);
    TRrailsRaw = TRrails;
    [TRrails, componentCleanupInfo] = cleanupRailComponents( ...
        TRrails, railBuildInfo, opts);

    markerInfo = struct([]);
    TRmarkers = [];
    TRmarkerSupports = [];
    markerSupportInfo = struct('siteName', {}, 'lengthMm', {}, ...
        'endpointMm', {});
    markerSurfaceMm = zeros(0, 3);
    if opts.includeElectrodeMarkers && ~isempty(targetsMm)
        [markerSurfaceMm, markerNormals] = snapTargetsToSurface(TRskinFull, targetsMm);
        [TRmarkers, markerInfo] = makeMarkerArray(markerSurfaceMm, ...
            markerNormals, names, opts);
        [TRmarkerSupports, markerSupportInfo] = makeMarkerSupportRails( ...
            markerSurfaceMm, markerNormals, names, TRgridSkin, opts);
        warnLongMarkerSupports(markerSupportInfo, opts);
    elseif opts.includeElectrodeMarkers
        warning('acsBuildCapMakerFitCheckStl:NoLayoutMarkers', ...
            'No layout coordinates were found; writing sparse grid without electrode markers.');
    end

    TRfit = concatTriangulations({TRrails, TRmarkerSupports, TRmarkers});
    if isempty(TRfit)
        error('acsBuildCapMakerFitCheckStl:EmptyFitCheckMesh', ...
            'No fit-check mesh was generated.');
    end

    stlwrite_boxsafe(TRfit, opts.stlFile);

    qcFile = '';
    fig = [];
    if opts.showFigures || opts.saveFigures
        figVisible = 'off';
        if opts.showFigures
            figVisible = 'on';
        end
        fig = makeQcFigure(TRskinFull, TRgridSkin, TRrails, TRmarkers, ...
            TRmarkerSupports, TRfit, componentCleanupInfo, ...
            markerSurfaceMm, names, roles, ...
            earExclusions, implantExclusions, exclusionPolys, opts, figVisible);
        if opts.saveFigures
            qcFile = fullfile(opts.outputDir, [opts.fitCheckTag '_qc.png']);
            saveQcFigure(fig, qcFile);
        end
        if ~opts.showFigures
            close(fig);
            fig = [];
        end
    end

    out = struct();
    out.createdOn = char(datetime('now'));
    out.type = 'capMakerPlaFitCheck';
    out.fitCheckMode = 'sparseTriGrid';
    out.fitCheckTag = opts.fitCheckTag;
    out.outputDir = opts.outputDir;
    out.stlFile = opts.stlFile;
    out.reportMat = opts.reportMat;
    out.meshMat = opts.meshMat;
    out.qcFigure = qcFile;
    out.skinSource = skinSource;
    out.names = names;
    out.siteRoles = roles;
    out.layoutCoordinatesMm = targetsMm;
    out.markerSurfaceMm = markerSurfaceMm;
    out.markerInfo = markerInfo;
    out.markerSupportInfo = markerSupportInfo;
    out.earExclusions = compactEarExclusions(earExclusions);
    out.implantExclusions = compactImplantExclusions(implantExclusions);
    out.railExclusionInfo = struct( ...
        'earGeometry', opts.earRailExclusionGeometry, ...
        'earSphereCenters', earSphereCenters, ...
        'earSphereRadii', earSphereRadii, ...
        'paintedVertexPoints', paintedVertexPoints, ...
        'paintedVertexToleranceMm', opts.paintedExclusionVertexToleranceMm, ...
        'railEdgeMarginMm', opts.railEdgeMarginMm, ...
        'nProjectedPolys', numel(exclusionPolys));
    out.railBuildInfo = railBuildInfo;
    out.componentCleanupInfo = componentCleanupInfo;
    out.meshInfo = struct( ...
        'skin', meshStats(TRskinFull), ...
        'gridSkin', meshStats(TRgridSkin), ...
        'railsRaw', meshStats(TRrailsRaw), ...
        'rails', meshStats(TRrails), ...
        'markers', meshStats(TRmarkers), ...
        'markerSupports', meshStats(TRmarkerSupports), ...
        'fitCheck', meshStats(TRfit));
    out.options = opts;
    if opts.saveMeshMat
        meshes = struct('TRfit', TRfit, 'TRrails', TRrails, ...
            'TRrailsRaw', TRrailsRaw, ...
            'TRmarkers', TRmarkers, 'TRmarkerSupports', TRmarkerSupports, ...
            'TRgridSkin', TRgridSkin, 'TRskin', TRskinFull); %#ok<NASGU>
        save(opts.meshMat, 'meshes', '-v7.3');
    end
    if isgraphics(fig)
        out.figure = fig;
    end

    outForSave = out;
    if isfield(outForSave, 'figure')
        outForSave = rmfield(outForSave, 'figure');
    end
    save(opts.reportMat, 'outForSave', '-v7.3');

    if opts.verbose
        printSummary(out);
    end
end

function opts = parseInputs(varargin)
    p = inputParser;
    p.FunctionName = 'acsBuildCapMakerFitCheckStl';
    addParameter(p, 'skinCacheFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'outputDir', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'fitCheckTag', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'force', false, @isBoolLike);
    addParameter(p, 'electrodeNames', {}, @(x) iscell(x) || ischar(x) || isstring(x));
    addParameter(p, 'includeElectrodeMarkers', true, @isBoolLike);
    addParameter(p, 'gridSurfaceMaxFaces', 140, @isPositiveScalar);
    addParameter(p, 'railWidthMm', 2.5, @isPositiveScalar);
    addParameter(p, 'railHeightMm', 2, @isPositiveScalar);
    addParameter(p, 'railEmbedFraction', 0.45, @isUnitScalar);
    addParameter(p, 'railMinLengthMm', 3, @isNonnegativeScalar);
    addParameter(p, 'railZThresholdMm', 1, @isNonnegativeScalar);
    addParameter(p, 'railPerimeterFactor', 1.5, @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 1);
    addParameter(p, 'railEdgeMarginMm', 10, @isNonnegativeScalar);
    addParameter(p, 'markerOuterDiameterMm', 7, @isPositiveScalar);
    addParameter(p, 'markerInnerDiameterMm', 4, @isNonnegativeScalar);
    addParameter(p, 'markerHeightMm', 0.8, @isPositiveScalar);
    addParameter(p, 'markerEmbedMm', 0.1, @isNonnegativeScalar);
    addParameter(p, 'markerSegments', 24, @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 8);
    addParameter(p, 'markerSupportCount', 3, @isNonnegativeScalar);
    addParameter(p, 'markerSupportMaxLengthMm', 18, @isPositiveScalar);
    addParameter(p, 'earExclusionMode', 'auto', @(x) ischar(x) || isstring(x));
    addParameter(p, 'earExclusionFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'earRailExclusionGeometry', 'sphere3d', ...
        @(x) ischar(x) || isstring(x));
    addParameter(p, 'paintedExclusionRailMarginMm', 2, @isNonnegativeScalar);
    addParameter(p, 'paintedExclusionVertexToleranceMm', 1e-3, ...
        @isNonnegativeScalar);
    addParameter(p, 'implantExclusionFile', '', ...
        @(x) isempty(x) || ischar(x) || isstring(x) || iscell(x));
    addParameter(p, 'componentCleanupMode', 'none', ...
        @(x) ischar(x) || isstring(x));
    addParameter(p, 'showFigures', false, @isBoolLike);
    addParameter(p, 'saveFigures', false, @isBoolLike);
    addParameter(p, 'saveMeshMat', true, @isBoolLike);
    addParameter(p, 'verbose', true, @isBoolLike);
    parse(p, varargin{:});

    opts = p.Results;
    opts.skinCacheFile = expandUserPath(char(opts.skinCacheFile));
    opts.outputDir = expandUserPath(char(opts.outputDir));
    opts.fitCheckTag = safeName(char(opts.fitCheckTag));
    opts.force = logical(opts.force);
    opts.electrodeNames = normalizeNameInput(opts.electrodeNames);
    opts.includeElectrodeMarkers = logical(opts.includeElectrodeMarkers);
    opts.gridSurfaceMaxFaces = round(double(opts.gridSurfaceMaxFaces));
    opts.railWidthMm = double(opts.railWidthMm);
    opts.railHeightMm = double(opts.railHeightMm);
    opts.railEmbedFraction = double(opts.railEmbedFraction);
    opts.railMinLengthMm = double(opts.railMinLengthMm);
    opts.railZThresholdMm = double(opts.railZThresholdMm);
    opts.railPerimeterFactor = double(opts.railPerimeterFactor);
    opts.railEdgeMarginMm = double(opts.railEdgeMarginMm);
    opts.markerOuterDiameterMm = double(opts.markerOuterDiameterMm);
    opts.markerInnerDiameterMm = double(opts.markerInnerDiameterMm);
    if opts.markerInnerDiameterMm >= opts.markerOuterDiameterMm
        error('acsBuildCapMakerFitCheckStl:BadMarkerDiameters', ...
            'markerInnerDiameterMm must be smaller than markerOuterDiameterMm.');
    end
    opts.markerHeightMm = double(opts.markerHeightMm);
    opts.markerEmbedMm = double(opts.markerEmbedMm);
    opts.markerSegments = round(double(opts.markerSegments));
    opts.markerSupportCount = round(double(opts.markerSupportCount));
    opts.markerSupportMaxLengthMm = double(opts.markerSupportMaxLengthMm);
    opts.earExclusionMode = normalizeEarExclusionMode(opts.earExclusionMode);
    opts.earExclusionFile = expandUserPath(char(opts.earExclusionFile));
    opts.earRailExclusionGeometry = normalizeEarRailExclusionGeometry( ...
        opts.earRailExclusionGeometry);
    opts.paintedExclusionRailMarginMm = double(opts.paintedExclusionRailMarginMm);
    opts.paintedExclusionVertexToleranceMm = double( ...
        opts.paintedExclusionVertexToleranceMm);
    opts.implantExclusionFile = normalizeFileList(opts.implantExclusionFile);
    opts.componentCleanupMode = normalizeComponentCleanupMode( ...
        opts.componentCleanupMode);
    opts.showFigures = logical(opts.showFigures);
    opts.saveFigures = logical(opts.saveFigures);
    opts.saveMeshMat = logical(opts.saveMeshMat);
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

function tf = isUnitScalar(x)
    tf = isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0 && x <= 1;
end

function addLocalDependencies()
    repoRoot = fileparts(fileparts(mfilename('fullpath')));
    addpath(repoRoot);
    addpath(fullfile(repoRoot, 'capMaker', 'core'));
    addpath(fullfile(repoRoot, 'capMaker', 'geometry'));
end

function [layout, source] = readLayoutOrEmpty(value)
    source = struct('type', '', 'file', '', 'label', '');
    layout = struct();
    if isstruct(value) && isLayoutStruct(value)
        layout = value;
        source.type = 'layoutStruct';
        source.label = 'layout struct';
        return;
    end
    if ischar(value) || isstring(value)
        fileName = expandUserPath(char(value));
        if exist(fileName, 'file') == 2
            S = load(fileName);
            candidate = firstStruct(S);
            if isLayoutStruct(candidate)
                layout = candidate;
                source.type = 'layoutFile';
                source.file = fileName;
                source.label = fileStem(fileName);
            end
        end
    end
end

function tf = isLayoutStruct(S)
    tf = isstruct(S) && isfield(S, 'names') && ...
        (isfield(S, 'layoutCoordinatesMm') || isfield(S, 'voxelCoordinates'));
end

function [TRskin, source] = readSkinMesh(originalInput, layout, opts)
    source = struct('type', '', 'file', '', 'cacheFile', '', 'label', '');
    value = [];
    if ~isempty(opts.skinCacheFile)
        value = opts.skinCacheFile;
    elseif isstruct(layout) && isfield(layout, 'layout') && ...
            isfield(layout.layout, 'skin') && ...
            isfield(layout.layout.skin, 'cacheFile') && ...
            ~isempty(layout.layout.skin.cacheFile)
        value = layout.layout.skin.cacheFile;
    else
        value = originalInput;
    end

    if isa(value, 'triangulation')
        TRskin = value;
        source.type = 'triangulation';
        source.label = 'triangulation';
        return;
    end
    if isstruct(value) && isfield(value, 'TRskin')
        TRskin = ensureTriangulation(value.TRskin);
        source.type = 'skinStruct';
        source.label = 'skin struct';
        return;
    end
    if isstruct(value) && isfield(value, 'skin') && ...
            isfield(value.skin, 'cacheFile')
        value = value.skin.cacheFile;
    end
    if ~(ischar(value) || isstring(value))
        error('acsBuildCapMakerFitCheckStl:MissingSkinCache', ...
            'Could not resolve a skin cache. Pass skinCacheFile explicitly.');
    end
    fileName = expandUserPath(char(value));
    if exist(fileName, 'file') ~= 2
        error('acsBuildCapMakerFitCheckStl:SkinCacheNotFound', ...
            'Skin cache not found: %s', fileName);
    end
    raw = load(fileName);
    if isfield(raw, 'TRskin')
        TRskin = ensureTriangulation(raw.TRskin);
    else
        S = firstStruct(raw);
        if ~isfield(S, 'TRskin')
            error('acsBuildCapMakerFitCheckStl:MissingTRskin', ...
                'Skin cache does not contain TRskin: %s', fileName);
        end
        TRskin = ensureTriangulation(S.TRskin);
    end
    source.type = 'skinCache';
    source.file = fileName;
    source.cacheFile = fileName;
    source.label = fileStem(fileName);
end

function [names, coords, roles] = selectedLayoutSites(layout, opts)
    names = {};
    coords = zeros(0, 3);
    roles = {};
    if ~isLayoutStruct(layout)
        return;
    end
    allNames = normalizeNameInput(layout.names);
    if isfield(layout, 'layoutCoordinatesMm') && ~isempty(layout.layoutCoordinatesMm)
        allCoords = double(layout.layoutCoordinatesMm);
    else
        warning('acsBuildCapMakerFitCheckStl:NoPrintFrameLayoutCoordinates', ...
            ['Layout does not contain layoutCoordinatesMm in capMaker print-frame ', ...
             'millimeters; skipping electrode markers.']);
        return;
    end
    if size(allCoords, 1) ~= numel(allNames) || size(allCoords, 2) ~= 3
        error('acsBuildCapMakerFitCheckStl:BadLayoutCoordinates', ...
            'Layout coordinates must be N x 3 and match layout.names.');
    end
    if isfield(layout, 'siteRoles') && numel(layout.siteRoles) == numel(allNames)
        allRoles = normalizeNameInput(layout.siteRoles);
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
                error('acsBuildCapMakerFitCheckStl:MissingElectrode', ...
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

function earExclusions = resolveEarExclusions(layoutOrSkin, skinSource, opts)
    earExclusions = struct();
    if strcmp(opts.earExclusionMode, 'none')
        return;
    end
    earSource = layoutOrSkin;
    if ~isempty(skinSource.cacheFile)
        earSource = skinSource.cacheFile;
    end
    earFile = opts.earExclusionFile;
    if isempty(earFile) && ~isempty(skinSource.cacheFile)
        earFile = defaultEarFile(skinSource.cacheFile);
    end
    try
        earExclusions = acsSelectEarExclusionSpheres(earSource, ...
            'outputFile', earFile, ...
            'editMode', opts.earExclusionMode, ...
            'showFigures', ~strcmp(opts.earExclusionMode, 'never'), ...
            'saveFigures', opts.saveFigures, ...
            'verbose', opts.verbose);
    catch ME
        warning('acsBuildCapMakerFitCheckStl:EarExclusionsUnavailable', ...
            'Could not resolve ear exclusions for fit-check rails: %s', ME.message);
        earExclusions = struct();
    end
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
    if strcmp(opts.earRailExclusionGeometry, 'none') || ...
            strcmp(opts.earRailExclusionGeometry, 'xyDisk')
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
        warning('acsBuildCapMakerFitCheckStl:BadEarSphereExclusions', ...
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
    if strcmp(opts.earRailExclusionGeometry, 'xyDisk') && ...
            isfield(earExclusions, 'exclusionCenters') && ...
            isfield(earExclusions, 'exclusionRadiusMM') && ...
            ~isempty(earExclusions.exclusionCenters)
        centers = double(earExclusions.exclusionCenters);
        radii = double(earExclusions.exclusionRadiusMM(:));
        if isscalar(radii) && size(centers, 1) > 1
            radii = repmat(radii, size(centers, 1), 1);
        end
        theta = linspace(0, 2 * pi, 80);
        theta(end) = [];
        for i = 1:min(size(centers, 1), numel(radii))
            x = centers(i, 1) + radii(i) * cos(theta);
            y = centers(i, 2) + radii(i) * sin(theta);
            polys{end + 1} = polyshape(x, y, 'Simplify', true); %#ok<AGROW>
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

function implantExclusions = resolveImplantExclusions(opts)
    implantExclusions = repmat(emptyImplantExclusion(), 0, 1);
    files = opts.implantExclusionFile;
    if isempty(files)
        return;
    end
    for i = 1:numel(files)
        fileName = files{i};
        if exist(fileName, 'file') ~= 2
            warning('acsBuildCapMakerFitCheckStl:ImplantExclusionNotFound', ...
                'Implant exclusion file not found: %s', fileName);
            continue;
        end
        try
            S = loadPreferredStructFromMat(fileName, ...
                {'exclusion', 'outForSave', 'outSaved', 'out'});
            implantExclusions(end + 1, 1) = normalizeImplantExclusion(S, fileName); %#ok<AGROW>
        catch ME
            warning('acsBuildCapMakerFitCheckStl:BadImplantExclusion', ...
                'Could not read implant exclusion %s: %s', fileName, ME.message);
        end
    end
end

function polys = railImplantPolys(implantExclusions)
    polys = {};
    if isempty(implantExclusions)
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
    if ~strcmpi(char(value.coordinateFrame), 'capMakerPrintMm')
        warning('acsBuildCapMakerFitCheckStl:NonPrintFrameImplantExclusion', ...
            ['Skipping implant exclusion "%s" from %s because coordinateFrame ', ...
             'is "%s", not "capMakerPrintMm".'], ...
            value.name, fileName, char(value.coordinateFrame));
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

function compact = compactEarExclusions(earExclusions)
    compact = struct();
    fields = {'outputFile', 'exclusionCenters', 'exclusionRadiusMM', ...
        'paintedExclusionVertex', 'paintedExclusionCoordinatesMm', ...
        'customExclusionVertexInd', 'customExclusionCoordinatesMm', ...
        'source', 'meshFingerprint'};
    for i = 1:numel(fields)
        if isfield(earExclusions, fields{i})
            compact.(fields{i}) = earExclusions.(fields{i});
        end
    end
end

function compact = compactImplantExclusions(implantExclusions)
    compact = rmfieldIfPresent(implantExclusions, {'keepoutPoly', 'railExclusionPolys'});
end

function value = loadPreferredStructFromMat(fileName, preferredNames)
    info = whos('-file', fileName);
    names = {info.name};
    for i = 1:numel(preferredNames)
        hit = find(strcmp(names, preferredNames{i}), 1);
        if isempty(hit) || ~strcmp(info(hit).class, 'struct')
            continue;
        end
        raw = load(fileName, preferredNames{i});
        value = raw.(preferredNames{i});
        return;
    end
    raw = load(fileName);
    value = firstStruct(raw);
end

function opts = resolveOutputPaths(layoutSource, skinSource, opts)
    if isempty(opts.outputDir)
        if ~isempty(skinSource.cacheFile)
            opts.outputDir = fullfile(fileparts(skinSource.cacheFile), 'fitChecks');
        elseif ~isempty(layoutSource.file)
            opts.outputDir = fullfile(fileparts(layoutSource.file), 'fitChecks');
        else
            opts.outputDir = fullfile(pwd, 'fitChecks');
        end
    end
    if isempty(opts.fitCheckTag)
        if ~isempty(layoutSource.label)
            opts.fitCheckTag = safeName([layoutSource.label '_fitCheckSparseTriGrid']);
        elseif ~isempty(skinSource.label)
            opts.fitCheckTag = safeName([skinSource.label '_fitCheckSparseTriGrid']);
        else
            opts.fitCheckTag = 'fitCheckSparseTriGrid';
        end
    end
    opts.stlFile = fullfile(opts.outputDir, [opts.fitCheckTag '_PLA.stl']);
    opts.reportMat = fullfile(opts.outputDir, [opts.fitCheckTag '_report.mat']);
    opts.meshMat = fullfile(opts.outputDir, [opts.fitCheckTag '_meshes.mat']);
end

function requireWritableOutputs(opts)
    files = {opts.stlFile, opts.reportMat};
    if opts.saveMeshMat
        files{end + 1} = opts.meshMat;
    end
    for i = 1:numel(files)
        if exist(files{i}, 'file') == 2 && ~opts.force
            error('acsBuildCapMakerFitCheckStl:OutputExists', ...
                ['Output already exists: %s\nUse force=true to overwrite, ', ...
                 'or choose a new fitCheckTag/outputDir.'], files{i});
        end
    end
end

function TRout = decimateTriangulation(TRin, maxFaces, opts)
    TRout = TRin;
    nFaces = size(TRin.ConnectivityList, 1);
    if isempty(maxFaces) || nFaces <= maxFaces
        logMsg(opts, 'Fit-check grid skin has %d faces; no decimation needed.', nFaces);
        return;
    end
    logMsg(opts, 'Decimating fit-check grid skin from %d to about %d faces.', ...
        nFaces, maxFaces);
    try
        [F2, V2] = reducepatch(TRin.ConnectivityList, TRin.Points, maxFaces);
        TRout = triangulation(double(F2), double(V2));
        try
            TRout = unifyOutwardNormalsRobust(TRout);
        catch
        end
    catch ME
        warning('acsBuildCapMakerFitCheckStl:DecimationFailed', ...
            'Grid decimation failed (%s). Using the source mesh.', ME.message);
        TRout = TRin;
    end
end

function [snapped, normals] = snapTargetsToSurface(TRskin, targetsMm)
    V = double(TRskin.Points);
    Nv = vertexNormal(TRskin);
    Nv = normalizeRows(Nv);
    snapped = zeros(size(targetsMm));
    normals = zeros(size(targetsMm));
    for i = 1:size(targetsMm, 1)
        d2 = sum((V - targetsMm(i, :)) .^ 2, 2);
        [~, idx] = min(d2);
        snapped(i, :) = V(idx, :);
        normals(i, :) = Nv(idx, :);
    end
end

function [TRmarkers, info] = makeMarkerArray(points, normals, names, opts)
    TRlist = cell(size(points, 1), 1);
    info = repmat(struct('name', '', 'centerMm', zeros(1, 3), ...
        'normal', zeros(1, 3), 'supportLengthMm', []), size(points, 1), 1);
    for i = 1:size(points, 1)
        TRlist{i} = makeRingMarker(points(i, :), normals(i, :), opts);
        info(i).name = names{i};
        info(i).centerMm = points(i, :);
        info(i).normal = normals(i, :);
    end
    TRmarkers = concatTriangulations(TRlist);
end

function TR = makeRingMarker(center, normal, opts)
    n = normalizeVector(normal);
    [u, v] = tangentBasis(n);
    outerR = 0.5 * opts.markerOuterDiameterMm;
    innerR = 0.5 * opts.markerInnerDiameterMm;
    z0 = -opts.markerEmbedMm;
    z1 = opts.markerHeightMm - opts.markerEmbedMm;
    K = opts.markerSegments;
    theta = linspace(0, 2 * pi, K + 1)';
    theta(end) = [];
    dirs = cos(theta) * u + sin(theta) * v;
    outerBottom = center + outerR * dirs + z0 * n;
    outerTop = center + outerR * dirs + z1 * n;
    innerBottom = center + innerR * dirs + z0 * n;
    innerTop = center + innerR * dirs + z1 * n;
    V = [outerBottom; outerTop; innerBottom; innerTop];
    ob = 0; ot = K; ib = 2 * K; it = 3 * K;
    F = zeros(0, 3);
    for k = 1:K
        k2 = mod(k, K) + 1;
        F = [F; ... %#ok<AGROW>
            ob + k, ob + k2, ot + k2; ob + k, ot + k2, ot + k; ...
            ib + k2, ib + k, it + k2; ib + k, it + k, it + k2; ...
            ot + k, ot + k2, it + k2; ot + k, it + k2, it + k; ...
            ob + k2, ob + k, ib + k2; ob + k, ib + k, ib + k2];
    end
    TR = triangulation(F, V);
end

function [TRsupports, supportInfo] = makeMarkerSupportRails(points, normals, ...
        names, TRgridSkin, opts)
    supportInfo = struct('siteName', {}, 'lengthMm', {}, 'endpointMm', {});
    if opts.markerSupportCount <= 0 || isempty(points)
        TRsupports = [];
        return;
    end
    Vgrid = double(TRgridSkin.Points);
    TRlist = {};
    for i = 1:size(points, 1)
        d2 = sum((Vgrid - points(i, :)) .^ 2, 2);
        [~, order] = sort(d2, 'ascend');
        useRows = order(1:min(opts.markerSupportCount, numel(order)));
        for j = 1:numel(useRows)
            endpoint = Vgrid(useRows(j), :);
            if norm(endpoint - points(i, :)) < 1e-6
                continue;
            end
            TRlist{end + 1} = makeRailSegment(points(i, :), endpoint, ... %#ok<AGROW>
                normals(i, :), opts);
            supportInfo(end + 1, 1) = struct( ... %#ok<AGROW>
                'siteName', names{i}, ...
                'lengthMm', norm(endpoint - points(i, :)), ...
                'endpointMm', endpoint);
        end
    end
    TRsupports = concatTriangulations(TRlist);
end

function TR = makeRailSegment(Pi, Pj, normal, opts)
    seg = Pj - Pi;
    L = norm(seg);
    if L <= 1e-9
        TR = [];
        return;
    end
    t = seg / L;
    n = normalizeVector(normal);
    w = cross(n, t);
    if norm(w) < 1e-9
        [~, ax] = min(abs(n));
        e = zeros(1, 3);
        e(ax) = 1;
        w = cross(n, e);
    end
    w = normalizeVector(w);
    halfW = 0.5 * opts.railWidthMm;
    zBot = -opts.railEmbedFraction * opts.railHeightMm;
    zTop = (1 - opts.railEmbedFraction) * opts.railHeightMm;
    ext = min(halfW, 0.25 * L);
    P1 = Pi - ext * t;
    P2 = Pj + ext * t;
    V = [ ...
        P1 - halfW * w + zBot * n; ...
        P1 + halfW * w + zBot * n; ...
        P1 + halfW * w + zTop * n; ...
        P1 - halfW * w + zTop * n; ...
        P2 - halfW * w + zBot * n; ...
        P2 + halfW * w + zBot * n; ...
        P2 + halfW * w + zTop * n; ...
        P2 - halfW * w + zTop * n];
    F = convhulln(V);
    C = mean(V, 1);
    for f = 1:size(F, 1)
        a = V(F(f, 1), :);
        b = V(F(f, 2), :);
        c = V(F(f, 3), :);
        N = cross(b - a, c - a);
        if norm(N) > 0
            fc = (a + b + c) / 3;
            if dot(N, C - fc) > 0
                F(f, [2 3]) = F(f, [3 2]);
            end
        end
    end
    TR = triangulation(F, V);
end

function warnLongMarkerSupports(markerSupportInfo, opts)
    if isempty(markerSupportInfo)
        return;
    end
    L = double([markerSupportInfo.lengthMm]);
    longRows = find(L > opts.markerSupportMaxLengthMm);
    if ~isempty(longRows)
        longSites = unique({markerSupportInfo(longRows).siteName});
        warning('acsBuildCapMakerFitCheckStl:LongMarkerSupports', ...
            ['%d electrode marker support strut(s) exceed %.1f mm ', ...
             '(%s). Consider increasing gridSurfaceMaxFaces or inspecting ', ...
             'the fit-check QC figure.'], numel(longRows), ...
            opts.markerSupportMaxLengthMm, strjoin(longSites, ', '));
    end
end

function warnSparseRailBuild(info, opts)
    if isempty(info) || ~isstruct(info) || ~isfield(info, 'nCandidateEdges')
        return;
    end
    if info.nCandidateEdges <= 0
        return;
    end
    builtFraction = info.nBuiltRails / info.nCandidateEdges;
    if builtFraction < 0.10
        warning('acsBuildCapMakerFitCheckStl:SparseRailBuild', ...
            ['Only %d/%d candidate skin edges became PLA rails. ', ...
             'Skipped: short=%d, base=%d, paintedVertex=%d, ', ...
             'boundary=%d, sphere=%d, projectedPoly=%d. ', ...
             'For a gross fit check, try ', ...
             'earExclusionMode=''none'', implantExclusionFile={headpostExclusionFile}, ', ...
             'or railEdgeMarginMm=0.'], ...
            info.nBuiltRails, info.nCandidateEdges, ...
            info.nSkippedShort, info.nSkippedBase, ...
            info.nSkippedVertexExclusion, ...
            info.nSkippedBoundaryMargin, info.nSkippedSphere, ...
            info.nSkippedProjectedPoly);
    elseif opts.verbose
        fprintf(['Fit-check rail build kept %d/%d candidate edges ', ...
            '(skipped paintedVertex=%d, boundary=%d, sphere=%d, projectedPoly=%d).\n'], ...
            info.nBuiltRails, info.nCandidateEdges, ...
            info.nSkippedVertexExclusion, ...
            info.nSkippedBoundaryMargin, info.nSkippedSphere, ...
            info.nSkippedProjectedPoly);
    end
end

function [TRclean, cleanupInfo] = cleanupRailComponents(TRrails, railBuildInfo, opts)
    cleanupInfo = initComponentCleanupInfo(opts.componentCleanupMode);
    if strcmp(opts.componentCleanupMode, 'none')
        returnWithOriginal();
        return;
    end
    cleanupInfo.enabled = true;
    if isempty(TRrails) || isempty(TRrails.Points) || ...
            isempty(TRrails.ConnectivityList)
        returnWithOriginal();
        return;
    end
    if isempty(railBuildInfo) || ~isstruct(railBuildInfo) || ...
            ~isfield(railBuildInfo, 'builtEdges') || ...
            ~isfield(railBuildInfo, 'builtFaceRanges')
        warning('acsBuildCapMakerFitCheckStl:MissingRailComponentInfo', ...
            ['componentCleanupMode=%s was requested, but rail provenance ', ...
             'is unavailable. Writing the unpruned rail mesh.'], ...
            opts.componentCleanupMode);
        returnWithOriginal();
        return;
    end

    F = double(TRrails.ConnectivityList);
    builtEdges = double(railBuildInfo.builtEdges);
    faceRanges = double(railBuildInfo.builtFaceRanges);
    nRails = size(builtEdges, 1);
    if nRails == 0 || isempty(F)
        returnWithOriginal();
        return;
    end
    if size(faceRanges, 1) ~= nRails
        warning('acsBuildCapMakerFitCheckStl:BadRailComponentInfo', ...
            ['Rail component cleanup expected one face range per built rail; ', ...
             'writing the unpruned rail mesh.']);
        returnWithOriginal();
        return;
    end

    comp = railSourceEdgeComponents(builtEdges);
    counts = accumarray(comp(:), 1);
    [~, keepComp] = max(counts);
    keepRail = comp(:) == keepComp;
    keepFace = false(size(F, 1), 1);
    for i = find(keepRail(:))'
        rows = faceRanges(i, :);
        firstFace = max(1, round(rows(1)));
        lastFace = min(size(F, 1), round(rows(2)));
        if lastFace >= firstFace
            keepFace(firstFace:lastFace) = true;
        end
    end

    cleanupInfo.nComponentsBefore = numel(counts);
    cleanupInfo.componentRailCounts = sort(counts(:), 'descend');
    cleanupInfo.keptComponent = keepComp;
    cleanupInfo.keptRails = nnz(keepRail);
    cleanupInfo.removedRails = nRails - cleanupInfo.keptRails;
    cleanupInfo.facesBefore = size(F, 1);
    cleanupInfo.verticesBefore = size(TRrails.Points, 1);
    TRclean = keepTriangulationFaces(TRrails, keepFace);
    cleanupInfo.facesAfter = meshFaceCount(TRclean);
    cleanupInfo.verticesAfter = meshVertexCount(TRclean);
    cleanupInfo.removedFaces = cleanupInfo.facesBefore - cleanupInfo.facesAfter;
    cleanupInfo.removedVertices = cleanupInfo.verticesBefore - cleanupInfo.verticesAfter;

    if opts.verbose && cleanupInfo.removedRails > 0
        fprintf(['Fit-check component cleanup kept largest rail component ', ...
            '(%d/%d rails, %d/%d faces).\n'], ...
            cleanupInfo.keptRails, nRails, ...
            cleanupInfo.facesAfter, cleanupInfo.facesBefore);
    end

    function returnWithOriginal()
        TRclean = TRrails;
        cleanupInfo.facesBefore = meshFaceCount(TRrails);
        cleanupInfo.facesAfter = cleanupInfo.facesBefore;
        cleanupInfo.verticesBefore = meshVertexCount(TRrails);
        cleanupInfo.verticesAfter = cleanupInfo.verticesBefore;
    end
end

function info = initComponentCleanupInfo(mode)
    info = struct( ...
        'enabled', false, ...
        'mode', mode, ...
        'nComponentsBefore', 0, ...
        'componentRailCounts', zeros(0, 1), ...
        'keptComponent', 0, ...
        'keptRails', 0, ...
        'removedRails', 0, ...
        'facesBefore', 0, ...
        'facesAfter', 0, ...
        'removedFaces', 0, ...
        'verticesBefore', 0, ...
        'verticesAfter', 0, ...
        'removedVertices', 0);
end

function comp = railSourceEdgeComponents(builtEdges)
    nRails = size(builtEdges, 1);
    if nRails == 0
        comp = zeros(0, 1);
        return;
    end
    endpoints = [builtEdges(:, 1); builtEdges(:, 2)];
    railRows = [(1:nRails)'; (1:nRails)'];
    [~, ~, vertexGroup] = unique(endpoints);
    incidentRails = accumarray(vertexGroup, railRows, [], @(x){unique(x(:))});
    I = zeros(0, 1);
    J = zeros(0, 1);
    for i = 1:numel(incidentRails)
        rows = incidentRails{i};
        if numel(rows) < 2
            continue;
        end
        rows = rows(:);
        I = [I; repmat(rows(1), numel(rows) - 1, 1)]; %#ok<AGROW>
        J = [J; rows(2:end)]; %#ok<AGROW>
    end
    G = graph(I, J, [], nRails);
    comp = conncomp(G)';
end

function TRout = keepTriangulationFaces(TR, keepFace)
    keepFace = logical(keepFace(:));
    F = double(TR.ConnectivityList);
    V = double(TR.Points);
    if numel(keepFace) ~= size(F, 1)
        error('acsBuildCapMakerFitCheckStl:BadFaceMask', ...
            'Face mask length does not match triangulation face count.');
    end
    Fkeep = F(keepFace, :);
    if isempty(Fkeep)
        TRout = [];
        return;
    end
    used = unique(Fkeep(:));
    remap = zeros(size(V, 1), 1);
    remap(used) = 1:numel(used);
    TRout = triangulation(remap(Fkeep), V(used, :));
end

function n = meshFaceCount(TR)
    if isempty(TR) || isempty(TR.ConnectivityList)
        n = 0;
    else
        n = size(TR.ConnectivityList, 1);
    end
end

function n = meshVertexCount(TR)
    if isempty(TR) || isempty(TR.Points)
        n = 0;
    else
        n = size(TR.Points, 1);
    end
end

function fig = makeQcFigure(TRskin, TRgridSkin, TRrails, TRmarkers, ...
        TRsupports, TRfit, componentCleanupInfo, markerPoints, names, roles, ...
        earExclusions, implantExclusions, railExclusionPolys, opts, figVisible)
    fig = figure('Name', 'CapMaker PLA fit-check QC', ...
        'NumberTitle', 'off', 'Color', 'w', 'Visible', figVisible, ...
        'Position', [100 80 1300 720]);
    tl = tiledlayout(fig, 1, 2, 'Padding', 'compact', 'TileSpacing', 'compact');

    ax1 = nexttile(tl);
    hold(ax1, 'on');
    drawTri(ax1, TRskin, [0.78 0.80 0.84], 0.18, 'none');
    drawTri(ax1, TRgridSkin, [0.15 0.45 0.90], 0.18, [0.20 0.28 0.40]);
    drawFitCheckExclusions(ax1, TRskin, earExclusions, ...
        implantExclusions, railExclusionPolys);
    if ~isempty(markerPoints)
        scatter3(ax1, markerPoints(:, 1), markerPoints(:, 2), markerPoints(:, 3), ...
            30, [0.90 0.25 0.10], 'filled');
    end
    title(ax1, 'Sparse triangle grid source');
    format3d(ax1);

    ax2 = nexttile(tl);
    hold(ax2, 'on');
    if isstruct(componentCleanupInfo) && ...
            isfield(componentCleanupInfo, 'enabled') && ...
            componentCleanupInfo.enabled
        drawTri(ax2, TRfit, [0.12 0.33 0.72], 1.0, 'none');
    else
        drawTri(ax2, TRrails, [0.12 0.33 0.72], 1.0, 'none');
        drawTri(ax2, TRsupports, [0.10 0.50 0.80], 1.0, 'none');
        drawTri(ax2, TRmarkers, [0.95 0.45 0.10], 1.0, 'none');
    end
    drawFitCheckExclusions(ax2, TRskin, earExclusions, ...
        implantExclusions, railExclusionPolys);
    if ~isempty(markerPoints)
        scatter3(ax2, markerPoints(:, 1), markerPoints(:, 2), markerPoints(:, 3), ...
            18, [0 0 0], 'filled');
        for i = 1:numel(names)
            if i <= size(markerPoints, 1)
                text(ax2, markerPoints(i, 1), markerPoints(i, 2), ...
                    markerPoints(i, 3) + 2.5, labelForQc(names{i}, roles{i}), ...
                    'FontSize', 7, 'Interpreter', 'none', ...
                    'Color', [0.05 0.05 0.05]);
            end
        end
    end
    title(ax2, 'PLA fit-check STL');
    format3d(ax2);

    title(tl, sprintf('PLA sparse-triangle fit check: %s', opts.fitCheckTag), ...
        'Interpreter', 'none', 'FontWeight', 'bold');
end

function drawFitCheckExclusions(ax, TRskin, earExclusions, implantExclusions, ...
        railExclusionPolys)
    hold(ax, 'on');
    drawRailExclusionPolys(ax, TRskin, railExclusionPolys);
    drawEarExclusionSpheres(ax, earExclusions);
    drawPaintedExclusionPoints(ax, earExclusions);
    drawImplantExclusionBoundaries(ax, TRskin, implantExclusions);
end

function drawRailExclusionPolys(ax, TRskin, polys)
    if isempty(polys)
        return;
    end
    for i = 1:numel(polys)
        poly = polys{i};
        if isempty(poly)
            continue;
        end
        try
            if poly.NumRegions == 0 || area(poly) == 0
                continue;
            end
            [x, y] = boundary(poly);
            drawLiftedXyBoundary(ax, TRskin, x, y, [0.90 0.05 0.05], '-', 2.0);
        catch
        end
    end
end

function drawEarExclusionSpheres(ax, earExclusions)
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
    [sx, sy, sz] = sphere(24);
    for i = 1:min(size(centers, 1), numel(radii))
        if ~all(isfinite(centers(i, :))) || ~isfinite(radii(i)) || radii(i) <= 0
            continue;
        end
        surf(ax, centers(i, 1) + radii(i) * sx, ...
            centers(i, 2) + radii(i) * sy, ...
            centers(i, 3) + radii(i) * sz, ...
            'FaceColor', [0.45 0.10 0.75], ...
            'FaceAlpha', 0.10, ...
            'EdgeColor', [0.45 0.10 0.75], ...
            'EdgeAlpha', 0.15);
    end
end

function drawPaintedExclusionPoints(ax, earExclusions)
    if ~isfield(earExclusions, 'paintedExclusionCoordinatesMm') || ...
            isempty(earExclusions.paintedExclusionCoordinatesMm)
        return;
    end
    P = double(earExclusions.paintedExclusionCoordinatesMm);
    P = P(all(isfinite(P), 2), :);
    if isempty(P)
        return;
    end
    scatter3(ax, P(:, 1), P(:, 2), P(:, 3), 8, ...
        [0.70 0.00 0.95], 'filled', ...
        'MarkerFaceAlpha', 0.45, 'MarkerEdgeColor', 'none');
end

function drawImplantExclusionBoundaries(ax, TRskin, implantExclusions)
    if isempty(implantExclusions)
        return;
    end
    for i = 1:numel(implantExclusions)
        if isfield(implantExclusions(i), 'projectedCoordinatesMm') && ...
                ~isempty(implantExclusions(i).projectedCoordinatesMm)
            P = double(implantExclusions(i).projectedCoordinatesMm);
            P = P(all(isfinite(P), 2), :);
            if ~isempty(P)
                scatter3(ax, P(:, 1), P(:, 2), P(:, 3), 10, ...
                    [1.00 0.45 0.05], 'filled', ...
                    'MarkerFaceAlpha', 0.45, 'MarkerEdgeColor', 'none');
            end
        end
        if isfield(implantExclusions(i), 'keepoutBoundaryMm') && ...
                ~isempty(implantExclusions(i).keepoutBoundaryMm)
            B = double(implantExclusions(i).keepoutBoundaryMm);
            B = B(all(isfinite(B), 2), :);
            if size(B, 1) >= 2
                if size(B, 2) >= 3 && any(isfinite(B(:, 3)))
                    plot3(ax, B(:, 1), B(:, 2), B(:, 3), ...
                        '-', 'Color', [1.00 0.00 0.85], 'LineWidth', 2.0);
                else
                    drawLiftedXyBoundary(ax, TRskin, B(:, 1), B(:, 2), ...
                        [1.00 0.00 0.85], '-', 2.0);
                end
            end
        end
    end
end

function drawLiftedXyBoundary(ax, TRskin, x, y, colorValue, lineStyle, lineWidth)
    if iscell(x)
        for i = 1:numel(x)
            drawLiftedXyBoundary(ax, TRskin, x{i}, y{i}, ...
                colorValue, lineStyle, lineWidth);
        end
        return;
    end
    x = double(x(:));
    y = double(y(:));
    valid = isfinite(x) & isfinite(y);
    if nnz(valid) < 2
        return;
    end
    z = liftedBoundaryZ(TRskin, x, y);
    breaks = find(~valid);
    starts = [1; breaks + 1];
    stops = [breaks - 1; numel(x)];
    for i = 1:numel(starts)
        rows = starts(i):stops(i);
        rows = rows(valid(rows));
        if numel(rows) < 2
            continue;
        end
        plot3(ax, x(rows), y(rows), z(rows), lineStyle, ...
            'Color', colorValue, 'LineWidth', lineWidth);
    end
end

function z = liftedBoundaryZ(TRskin, x, y)
    V = double(TRskin.Points);
    z = nan(size(x));
    if isempty(V)
        z(:) = 0;
        return;
    end
    Vxy = V(:, 1:2);
    for i = 1:numel(x)
        if ~isfinite(x(i)) || ~isfinite(y(i))
            continue;
        end
        d2 = sum((Vxy - [x(i) y(i)]) .^ 2, 2);
        [~, idx] = min(d2);
        z(i) = V(idx, 3) + 0.8;
    end
end

function label = labelForQc(name, role)
    if isempty(role)
        label = name;
    else
        label = sprintf('%s (%s)', name, role);
    end
end

function drawTri(ax, TR, color, alphaValue, edgeColor)
    if isempty(TR) || isempty(TR.Points)
        return;
    end
    patch(ax, 'Faces', TR.ConnectivityList, 'Vertices', TR.Points, ...
        'FaceColor', color, 'FaceAlpha', alphaValue, 'EdgeColor', edgeColor);
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
    lighting(ax, 'flat');
end

function saveQcFigure(fig, fileName)
    ensureDir(fileparts(fileName));
    try
        exportgraphics(fig, fileName, 'Resolution', 200);
    catch
        saveas(fig, fileName);
    end
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
        V = [V; double(TR.Points)]; %#ok<AGROW>
        F = [F; double(TR.ConnectivityList) + offset]; %#ok<AGROW>
    end
    if isempty(F)
        TRout = [];
    else
        TRout = triangulation(F, V);
    end
end

function stats = meshStats(TR)
    if isempty(TR) || isempty(TR.Points)
        stats = struct('nVertices', 0, 'nFaces', 0, ...
            'boundsMm', zeros(0, 3));
        return;
    end
    stats = struct('nVertices', size(TR.Points, 1), ...
        'nFaces', size(TR.ConnectivityList, 1), ...
        'boundsMm', [min(TR.Points, [], 1); max(TR.Points, [], 1)]);
end

function TR = ensureTriangulation(value)
    if isa(value, 'triangulation')
        TR = value;
    elseif isstruct(value) && isfield(value, 'ConnectivityList') && ...
            isfield(value, 'Points')
        TR = triangulation(double(value.ConnectivityList), double(value.Points));
    else
        error('acsBuildCapMakerFitCheckStl:BadTriangulation', ...
            'Expected a triangulation or struct with Points/ConnectivityList.');
    end
end

function N = normalizeRows(N)
    mag = sqrt(sum(N .^ 2, 2));
    mag(mag == 0 | ~isfinite(mag)) = 1;
    N = bsxfun(@rdivide, N, mag);
end

function n = normalizeVector(n)
    n = double(n(:)');
    if numel(n) ~= 3 || any(~isfinite(n)) || norm(n) < 1e-12
        n = [0 0 1];
    else
        n = n / norm(n);
    end
end

function [u, v] = tangentBasis(n)
    n = normalizeVector(n);
    [~, ax] = min(abs(n));
    ref = zeros(1, 3);
    ref(ax) = 1;
    u = cross(n, ref);
    u = normalizeVector(u);
    v = cross(n, u);
    v = normalizeVector(v);
end

function S = firstStruct(raw)
    preferred = {'out', 'outForSave', 'combinedLayout', 'layout'};
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
    S = struct();
end

function mode = normalizeEarExclusionMode(mode)
    mode = lower(strtrim(char(mode)));
    switch mode
        case {'auto', 'always', 'never', 'none'}
            return;
        otherwise
            error('acsBuildCapMakerFitCheckStl:BadEarExclusionMode', ...
                'earExclusionMode must be auto, always, never, or none.');
    end
end

function mode = normalizeEarRailExclusionGeometry(mode)
    key = lower(regexprep(strtrim(char(mode)), '[\s_\-]+', ''));
    switch key
        case {'sphere3d', 'spheres3d', '3dsphere', '3dspheres', 'sphere'}
            mode = 'sphere3d';
        case {'xydisk', 'xydisks', 'projectedsphere', ...
                'projectedspheres', 'projected'}
            mode = 'xyDisk';
        case {'none', 'off', 'false'}
            mode = 'none';
        otherwise
            error('acsBuildCapMakerFitCheckStl:BadEarRailExclusionGeometry', ...
                'earRailExclusionGeometry must be sphere3d, xyDisk, or none.');
    end
end

function mode = normalizeComponentCleanupMode(mode)
    key = lower(regexprep(strtrim(char(mode)), '[\s_\-]+', ''));
    switch key
        case {'none', 'off', 'false', 'no'}
            mode = 'none';
        case {'largest', 'largestcomponent', 'keeplargest', ...
                'singlelargest', 'largestrail', 'largestrailcomponent'}
            mode = 'largest';
        otherwise
            error('acsBuildCapMakerFitCheckStl:BadComponentCleanupMode', ...
                'componentCleanupMode must be none or largest.');
    end
end

function files = normalizeFileList(value)
    if isempty(value)
        files = {};
        return;
    end
    if iscell(value)
        files = cellstr(value(:));
    elseif isstring(value)
        files = cellstr(value(:));
    elseif ischar(value)
        if size(value, 1) == 1
            files = {char(value)};
        else
            files = cellstr(value);
        end
    else
        files = cellstr(value(:));
    end
    files = files(:);
    keep = true(size(files));
    for i = 1:numel(files)
        files{i} = expandUserPath(strtrim(files{i}));
        keep(i) = ~isempty(files{i});
    end
    files = files(keep);
end

function S = rmfieldIfPresent(S, fields)
    for i = 1:numel(fields)
        if isstruct(S) && isfield(S, fields{i})
            S = rmfield(S, fields{i});
        end
    end
end

function value = getOptionalField(S, fieldName, defaultValue)
    if isstruct(S) && isfield(S, fieldName) && ~isempty(S.(fieldName))
        value = S.(fieldName);
    else
        value = defaultValue;
    end
end

function names = normalizeNameInput(value)
    if isempty(value)
        names = {};
    elseif iscell(value)
        names = cellstr(value(:));
    elseif isstring(value)
        names = cellstr(value(:));
    elseif ischar(value)
        if size(value, 1) == 1
            names = {char(value)};
        else
            names = cellstr(value);
        end
    else
        names = cellstr(value(:));
    end
    names = names(:);
end

function logMsg(opts, varargin)
    if isstruct(opts) && isfield(opts, 'verbose') && opts.verbose
        fprintf([varargin{1} '\n'], varargin{2:end});
    end
end

function printSummary(out)
    fprintf('\nCapMaker PLA fit-check STL\n');
    fprintf('  mode: sparseTriGrid\n');
    fprintf('  STL: %s\n', out.stlFile);
    fprintf('  grid faces: %d\n', out.meshInfo.gridSkin.nFaces);
    if isfield(out, 'railBuildInfo') && ~isempty(out.railBuildInfo)
        r = out.railBuildInfo;
        fprintf('  rail edges: %d built / %d candidates\n', ...
            r.nBuiltRails, r.nCandidateEdges);
        fprintf(['  skipped edges: short %d, base %d, painted vertex %d, ', ...
            'boundary %d, sphere %d, projected poly %d\n'], ...
            r.nSkippedShort, r.nSkippedBase, r.nSkippedVertexExclusion, ...
            r.nSkippedBoundaryMargin, ...
            r.nSkippedSphere, r.nSkippedProjectedPoly);
    end
    if isfield(out, 'componentCleanupInfo') && ...
            isstruct(out.componentCleanupInfo) && ...
            isfield(out.componentCleanupInfo, 'enabled') && ...
            out.componentCleanupInfo.enabled
        c = out.componentCleanupInfo;
        fprintf(['  component cleanup: kept %d rail(s), removed %d rail(s) ', ...
            'across %d component(s)\n'], ...
            c.keptRails, c.removedRails, c.nComponentsBefore);
    end
    fprintf('  marked electrode sites: %d\n', numel(out.names));
    fprintf('  report: %s\n\n', out.reportMat);
end

function ensureDir(folder)
    if ~isempty(folder) && exist(folder, 'dir') ~= 7
        mkdir(folder);
    end
end

function fileName = expandUserPath(fileName)
    if isempty(fileName)
        return;
    end
    if startsWith(fileName, '~')
        homeDir = char(java.lang.System.getProperty('user.home'));
        fileName = fullfile(homeDir, fileName(2:end));
    end
end

function stem = fileStem(fileName)
    [~, stem, ~] = fileparts(char(fileName));
end

function value = safeName(value)
    value = regexprep(char(value), '[^\w\-]+', '_');
    value = regexprep(value, '_+', '_');
    value = regexprep(value, '^_|_$', '');
end
