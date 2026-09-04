function out = acsPlanVelcroAnchors(skinOrReport, varargin)
% ACSPLANVELCROANCHORS Plan six Velcro attachment loops for a cap STL.
%
% out = acsPlanVelcroAnchors(skinCacheFile) proposes six loop anchors around
% the lateral cap edge, opens a preview GUI for optional manual refinement,
% and saves a plan that can be passed to acsBuildCapMakerManufacturingStl.
% If the input is a manufacturing preflight/report with rail meshes, the
% automatic anchors are placed on the rail network instead of the scalp mesh:
%
%   velcroPlan = acsPlanVelcroAnchors(skinCacheForCap, ...
%       'earExclusionFile', activeEarExclusionFile, ...
%       'outputFile', fullfile(outputDir, 'velcroAnchors.mat'));
%
%   cap = acsBuildCapMakerManufacturingStl(layout, ...
%       'velcroAnchorMode', 'file', ...
%       'velcroAnchorFile', velcroPlan.outputFile, ...
%       'strapMode', 'none');
%
% The saved loops are intended as broad, reinforced attachment points for
% hook-and-loop straps: caudolateral, preauricular, and rostrolateral anchors
% on each side.
%
% Name-value options:
%   outputFile             : MAT file for saved anchor plan ['']
%   earExclusionFile       : saved ear/face exclusion file for auto placement ['']
%   force                  : ignore existing outputFile [false]
%   editMode               : 'auto', 'always', or 'never' ['auto']
%   showFigures            : open placement GUI / QC figure [true]
%   saveFigures            : save QC PNG next to outputFile [true]
%   displayMaxFaces        : mesh display face cap [30000]
%   meshAlpha              : scalp opacity [0.35]
%   pickRadiusMm           : visible-surface picking tolerance [[] = auto]
%   zBedMm                 : printer bed plane [0]
%   velcroLoopOuterLengthMm: oval loop length along the midline direction [20]
%   velcroLoopOuterWidthMm : oval loop width along the medial-lateral direction [13]
%   velcroLoopFrameWidthMm : material width around open slot [4]
%   velcroLoopThicknessMm  : loop thickness normal to scalp [3.5]
%   velcroLoopOutboardOffsetMm: shift loop center outside cap edge [5]
%   velcroLoopAttachLengthMm : inboard fusion pad length [9]
%   velcroLoopAttachWidthMm  : inboard fusion pad width [[] = outer width]
%   verbose                : print progress [true]

    if nargin < 1
        skinOrReport = '';
    end

    opts = parseInputs(varargin{:});
    addLocalDependencies();

    if isemptyInput(skinOrReport)
        skinOrReport = promptForSkinFile();
    end

    [TRskin, source, TRrails, siteMarkers] = readSkinMesh(skinOrReport);
    source.meshFingerprint = meshFingerprint(TRskin);
    [TRanchor, source] = chooseAnchorMesh(TRskin, TRrails, source);
    opts.geometry = velcroGeometryFromOptions(opts);
    if isempty(opts.outputFile)
        opts.outputFile = defaultOutputFile(source);
    end

    earExclusions = readEarExclusions(opts.earExclusionFile);
    proposal = autoSixPointAnchorPlan(TRanchor, earExclusions, opts);
    proposal = normalizeAnchorPlan(proposal, TRskin, opts);

    existingMatches = false;
    if exist(opts.outputFile, 'file') == 2
        existing = loadExistingPlan(opts.outputFile);
        existingMatches = savedPlanMatchesSource(existing, source);
        if ~opts.force && existingMatches
            try
                proposal = normalizeAnchorPlan(existing, TRskin, opts);
                logMsg(opts, 'Starting from saved Velcro anchor plan: %s', ...
                    opts.outputFile);
            catch ME
                warning('acsPlanVelcroAnchors:SavedPlanLoadFailed', ...
                    ['Could not load saved Velcro anchors from %s (%s). ', ...
                     'Using automatic proposal.'], opts.outputFile, ME.message);
            end
        elseif ~opts.force
            logMsg(opts, ['Saved Velcro anchor plan was made from a ', ...
                'different scalp/rail mesh fingerprint; starting from a ', ...
                'fresh automatic proposal.']);
        end
    end

    openGui = shouldOpenGui(opts.outputFile, opts, existingMatches);
    fig = [];
    accepted = true;
    if openGui
        [proposal, accepted, fig] = velcroAnchorGui(TRskin, TRanchor, ...
            proposal, siteMarkers, opts);
    end
    if ~accepted
        if isgraphics(fig)
            delete(fig);
        end
        error('acsPlanVelcroAnchors:Canceled', ...
            'Velcro anchor planning was canceled.');
    end

    out = buildOutput(proposal, source, opts);
    out.outputFile = opts.outputFile;
    out.jsonFile = replaceExtension(opts.outputFile, '.json');

    ensureDir(fileparts(opts.outputFile));
    outForSave = rmfieldIfPresent(out, {'figure'});
    velcroAnchors = outForSave; %#ok<NASGU>
    save(opts.outputFile, 'outForSave', 'velcroAnchors', '-v7.3');
    writeJsonReport(out.jsonFile, outForSave);

    qcFile = '';
    if opts.saveFigures
        qcFile = replaceExtension(opts.outputFile, '_qc.png');
        if ~isgraphics(fig)
            fig = makeQcFigure(TRskin, TRanchor, out, siteMarkers, opts, 'off');
        end
        saveQcFigure(fig, qcFile);
        out.qcFile = qcFile;
        outForSave = rmfieldIfPresent(out, {'figure'});
        velcroAnchors = outForSave; %#ok<NASGU>
        save(opts.outputFile, 'outForSave', 'velcroAnchors', '-v7.3');
    end

    if opts.showFigures && isgraphics(fig)
        out.figure = fig;
    elseif isgraphics(fig)
        delete(fig);
    end

    logMsg(opts, 'Saved Velcro anchor plan: %s', opts.outputFile);
    if ~isempty(qcFile)
        logMsg(opts, 'Saved Velcro anchor QC figure: %s', qcFile);
    end
end

function opts = parseInputs(varargin)
    p = inputParser;
    p.FunctionName = 'acsPlanVelcroAnchors';
    addParameter(p, 'outputFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'earExclusionFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'force', false, @isBoolLike);
    addParameter(p, 'editMode', 'auto', @(x) ischar(x) || isstring(x));
    addParameter(p, 'showFigures', true, @isBoolLike);
    addParameter(p, 'saveFigures', true, @isBoolLike);
    addParameter(p, 'displayMaxFaces', 30000, @isPositiveScalar);
    addParameter(p, 'meshAlpha', 0.35, @isUnitScalar);
    addParameter(p, 'pickRadiusMm', [], @(x) isempty(x) || isPositiveScalar(x));
    addParameter(p, 'zBedMm', 0, @(x) isnumeric(x) && isscalar(x) && isfinite(x));
    addParameter(p, 'velcroLoopOuterLengthMm', 20, @isPositiveScalar);
    addParameter(p, 'velcroLoopOuterWidthMm', 13, @isPositiveScalar);
    addParameter(p, 'velcroLoopFrameWidthMm', 4, @isPositiveScalar);
    addParameter(p, 'velcroLoopThicknessMm', 3.5, @isPositiveScalar);
    addParameter(p, 'velcroLoopOutboardOffsetMm', 5, @isNonnegativeScalar);
    addParameter(p, 'velcroLoopAttachLengthMm', 9, @isNonnegativeScalar);
    addParameter(p, 'velcroLoopAttachWidthMm', [], ...
        @(x) isempty(x) || isPositiveScalar(x));
    addParameter(p, 'verbose', true, @isBoolLike);
    parse(p, varargin{:});

    opts = p.Results;
    opts.outputFile = expandUserPath(char(opts.outputFile));
    opts.earExclusionFile = expandUserPath(char(opts.earExclusionFile));
    opts.force = logical(opts.force);
    opts.editMode = normalizeEditMode(opts.editMode);
    opts.showFigures = logical(opts.showFigures);
    opts.saveFigures = logical(opts.saveFigures);
    opts.displayMaxFaces = round(double(opts.displayMaxFaces));
    opts.meshAlpha = double(opts.meshAlpha);
    if ~isempty(opts.pickRadiusMm)
        opts.pickRadiusMm = double(opts.pickRadiusMm);
    end
    opts.zBedMm = double(opts.zBedMm);
    opts.velcroLoopOuterLengthMm = double(opts.velcroLoopOuterLengthMm);
    opts.velcroLoopOuterWidthMm = double(opts.velcroLoopOuterWidthMm);
    opts.velcroLoopFrameWidthMm = double(opts.velcroLoopFrameWidthMm);
    opts.velcroLoopThicknessMm = double(opts.velcroLoopThicknessMm);
    opts.velcroLoopOutboardOffsetMm = double(opts.velcroLoopOutboardOffsetMm);
    opts.velcroLoopAttachLengthMm = double(opts.velcroLoopAttachLengthMm);
    if isempty(opts.velcroLoopAttachWidthMm)
        opts.velcroLoopAttachWidthMm = opts.velcroLoopOuterWidthMm;
    else
        opts.velcroLoopAttachWidthMm = double(opts.velcroLoopAttachWidthMm);
    end
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

function mode = normalizeEditMode(mode)
    mode = lower(strtrim(char(mode)));
    switch mode
        case {'auto', 'always', 'never'}
            return;
        otherwise
            error('acsPlanVelcroAnchors:BadEditMode', ...
                'editMode must be ''auto'', ''always'', or ''never''.');
    end
end

function tf = isemptyInput(value)
    tf = isempty(value) || ((ischar(value) || isstring(value)) && ...
        strlength(string(value)) == 0);
end

function addLocalDependencies()
    repoRoot = fileparts(fileparts(mfilename('fullpath')));
    addpath(fullfile(repoRoot, 'acsUtilities'));
    addpath(fullfile(repoRoot, 'capMaker', 'core'));
    addpath(fullfile(repoRoot, 'capMaker', 'geometry'));
end

function fileName = promptForSkinFile()
    [name, folder] = uigetfile({'*.mat;*.stl', 'Mesh/report files (*.mat, *.stl)'}, ...
        'Select capMaker scalp mesh or manufacturing report');
    if isequal(name, 0)
        error('acsPlanVelcroAnchors:NoFileSelected', ...
            'No scalp mesh file was selected.');
    end
    fileName = fullfile(folder, name);
end

function geom = velcroGeometryFromOptions(opts)
    geom = struct( ...
        'outerLengthMm', opts.velcroLoopOuterLengthMm, ...
        'outerWidthMm', opts.velcroLoopOuterWidthMm, ...
        'frameWidthMm', opts.velcroLoopFrameWidthMm, ...
        'thicknessMm', opts.velcroLoopThicknessMm, ...
        'outboardOffsetMm', opts.velcroLoopOutboardOffsetMm, ...
        'attachLengthMm', opts.velcroLoopAttachLengthMm, ...
        'attachWidthMm', opts.velcroLoopAttachWidthMm, ...
        'floorAtBed', true);
    if geom.outerLengthMm <= 2 * geom.frameWidthMm || ...
            geom.outerWidthMm <= 2 * geom.frameWidthMm
        error('acsPlanVelcroAnchors:BadLoopGeometry', ...
            ['velcroLoopFrameWidthMm leaves no open slot. Increase ', ...
             'velcroLoopOuterLengthMm/velcroLoopOuterWidthMm or reduce ', ...
             'velcroLoopFrameWidthMm.']);
    end
end

function [TRskin, source, TRrails, siteMarkers] = readSkinMesh(value)
    source = struct('type', '', 'file', '', 'label', '');
    TRrails = [];
    siteMarkers = emptySiteMarkers();
    if isa(value, 'triangulation')
        TRskin = value;
        source.type = 'triangulation';
        source.label = 'triangulation';
        return;
    end
    if isstruct(value) && isfield(value, 'Points') && ...
            isfield(value, 'ConnectivityList')
        TRskin = triangulation(double(value.ConnectivityList), ...
            double(value.Points));
        source.type = 'meshStruct';
        source.label = 'mesh struct';
        return;
    end
    if isstruct(value)
        siteMarkers = readElectrodeMarkersFromStruct(value);
        [TRskin, source, TRrails] = readSkinMeshFromStruct(value, source);
        return;
    end
    if ~(ischar(value) || isstring(value))
        error('acsPlanVelcroAnchors:BadInput', ...
            'Input must be a skin mesh cache, report, mesh struct, or triangulation.');
    end

    fileName = expandUserPath(char(value));
    if exist(fileName, 'file') ~= 2
        error('acsPlanVelcroAnchors:FileNotFound', ...
            'Skin/report file not found: %s', fileName);
    end
    [~, ~, ext] = fileparts(fileName);
    switch lower(ext)
        case '.mat'
            S = load(fileName);
            source.file = fileName;
            source.label = fileLabel(fileName);
            siteMarkers = readElectrodeMarkersFromStruct(S);
            [TRskin, source, TRrails] = readSkinMeshFromStruct(S, source);
        case '.stl'
            TRskin = readStlTriangulationLocal(fileName);
            source.type = 'stl';
            source.file = fileName;
            source.label = fileLabel(fileName);
        otherwise
            error('acsPlanVelcroAnchors:UnsupportedFile', ...
                'Expected a MAT or STL file: %s', fileName);
    end
end

function [TRskin, source, TRrails] = readSkinMeshFromStruct(S, source)
    TRrails = readRailMeshFromStruct(S);
    candidates = {'TRskin', 'TRstableHead', 'TRwarped', 'TRscalp', ...
        'TRhead', 'TR'};
    for i = 1:numel(candidates)
        if isfield(S, candidates{i}) && ~isempty(S.(candidates{i}))
            TRskin = ensureTriangulation(S.(candidates{i}));
            source.type = candidates{i};
            return;
        end
    end
    if isfield(S, 'meshes') && isstruct(S.meshes)
        meshFields = {'skin', 'TRskin', 'railSource', 'TRrailSource', ...
            'manufacturingSkin', 'TRmanufacturingSkin'};
        for i = 1:numel(meshFields)
            if isfield(S.meshes, meshFields{i}) && ~isempty(S.meshes.(meshFields{i}))
                TRskin = ensureTriangulation(S.meshes.(meshFields{i}));
                source.type = ['meshes.' meshFields{i}];
                return;
            end
        end
    end
    cacheFile = inferSkinCacheFile(S);
    if ~isempty(cacheFile) && exist(cacheFile, 'file') == 2
        [TRskin, nestedSource, nestedRails] = readSkinMesh(cacheFile);
        if isempty(TRrails)
            TRrails = nestedRails;
        end
        source.type = ['cache:' nestedSource.type];
        source.file = nestedSource.file;
        source.label = nestedSource.label;
        return;
    end
    nested = firstStruct(S);
    if ~isempty(nested)
        cacheFile = inferSkinCacheFile(nested);
        if ~isempty(cacheFile) && exist(cacheFile, 'file') == 2
            [TRskin, nestedSource, nestedRails] = readSkinMesh(cacheFile);
            if isempty(TRrails)
                TRrails = nestedRails;
            end
            source.type = ['report:' nestedSource.type];
            source.file = nestedSource.file;
            source.label = nestedSource.label;
            return;
        end
        try
            [TRskin, source, nestedRails] = readSkinMeshFromStruct(nested, source);
            if isempty(TRrails)
                TRrails = nestedRails;
            end
            return;
        catch
        end
    end
    error('acsPlanVelcroAnchors:MissingSkinMesh', ...
        'Could not find a triangulation/skin mesh in the supplied input.');
end

function TRrails = readRailMeshFromStruct(S)
    TRrails = [];
    railFields = {'TRrails', 'TRrail', 'TRrailsBase', 'TRcapRails'};
    for i = 1:numel(railFields)
        if isfield(S, railFields{i}) && ~isempty(S.(railFields{i}))
            TRrails = ensureTriangulation(S.(railFields{i}));
            return;
        end
    end
    if isfield(S, 'meshes') && isstruct(S.meshes)
        meshFields = {'rails', 'TRrails', 'rail', 'TRrail'};
        for i = 1:numel(meshFields)
            if isfield(S.meshes, meshFields{i}) && ~isempty(S.meshes.(meshFields{i}))
                TRrails = ensureTriangulation(S.meshes.(meshFields{i}));
                return;
            end
        end
    end
end

function markers = emptySiteMarkers()
    markers = struct('pointsMm', zeros(0, 3), 'names', {{}}, ...
        'source', '');
end

function markers = readElectrodeMarkersFromStruct(S)
    markers = emptySiteMarkers();
    if ~isstruct(S)
        return;
    end

    direct = readDirectElectrodeMarkers(S);
    if ~isempty(direct.pointsMm)
        markers = direct;
        return;
    end

    preferred = {'out', 'outForSave', 'outSaved', 'manufacturing', ...
        'manufacturingPreflight', 'preflight', 'layout', 'combinedLayout'};
    for i = 1:numel(preferred)
        if isfield(S, preferred{i}) && isstruct(S.(preferred{i}))
            nested = readElectrodeMarkersFromStruct(S.(preferred{i}));
            if ~isempty(nested.pointsMm)
                markers = nested;
                return;
            end
        end
    end

    fields = fieldnames(S);
    for i = 1:numel(fields)
        value = S.(fields{i});
        if isstruct(value)
            nested = readElectrodeMarkersFromStruct(value);
            if ~isempty(nested.pointsMm)
                markers = nested;
                return;
            end
        end
    end
end

function markers = readDirectElectrodeMarkers(S)
    markers = emptySiteMarkers();
    if isfield(S, 'holderSurfaceCoordinatesMm') && ...
            ~isempty(S.holderSurfaceCoordinatesMm)
        markers.pointsMm = double(S.holderSurfaceCoordinatesMm);
        markers.source = 'holderSurfaceCoordinatesMm';
    elseif isfield(S, 'holderInfo') && isstruct(S.holderInfo) && ...
            isfield(S.holderInfo, 'surfacePointMm') && ...
            ~isempty(S.holderInfo)
        try
            markers.pointsMm = reshape([S.holderInfo.surfacePointMm], 3, []).';
            markers.source = 'holderInfo.surfacePointMm';
        catch
            markers.pointsMm = zeros(0, 3);
        end
    elseif isfield(S, 'layoutCoordinatesMm') && ~isempty(S.layoutCoordinatesMm)
        markers.pointsMm = double(S.layoutCoordinatesMm);
        markers.source = 'layoutCoordinatesMm';
    end
    markers = normalizeSiteMarkers(markers, readElectrodeNames(S));
end

function names = readElectrodeNames(S)
    if isfield(S, 'names') && ~isempty(S.names)
        names = cellstr(S.names(:));
    elseif isfield(S, 'labels') && ~isempty(S.labels)
        names = cellstr(S.labels(:));
    else
        names = {};
    end
end

function markers = normalizeSiteMarkers(markers, names)
    if isempty(markers.pointsMm) || size(markers.pointsMm, 2) ~= 3
        markers = emptySiteMarkers();
        return;
    end
    keep = all(isfinite(markers.pointsMm), 2);
    markers.pointsMm = markers.pointsMm(keep, :);
    n = size(markers.pointsMm, 1);
    if nargin < 2 || isempty(names)
        names = arrayfun(@(i) sprintf('site%d', i), ...
            (1:n).', 'UniformOutput', false);
    else
        names = cellstr(names(:));
        if numel(names) >= numel(keep)
            names = names(keep);
        end
        if numel(names) < n
            names(end + 1:n, 1) = arrayfun(@(i) sprintf('site%d', i), ...
                (numel(names) + 1:n).', 'UniformOutput', false);
        else
            names = names(1:n);
        end
    end
    markers.names = names(:);
end

function [TRanchor, source] = chooseAnchorMesh(TRskin, TRrails, source)
    if ~isempty(TRrails) && ~isempty(TRrails.Points)
        TRanchor = TRrails;
        source.anchorMeshType = 'rails';
        source.anchorMeshFingerprint = meshFingerprint(TRrails);
    else
        TRanchor = TRskin;
        source.anchorMeshType = 'skin';
        source.anchorMeshFingerprint = meshFingerprint(TRskin);
    end
    source.anchorPlanningVersion = 'velcroRailCornersMidlineEllipse_v03';
end

function cacheFile = inferSkinCacheFile(S)
    cacheFile = '';
    if isfield(S, 'layout') && isstruct(S.layout) && ...
            isfield(S.layout, 'skin') && isstruct(S.layout.skin) && ...
            isfield(S.layout.skin, 'cacheFile') && ~isempty(S.layout.skin.cacheFile)
        cacheFile = char(S.layout.skin.cacheFile);
    end
    if isempty(cacheFile) && isfield(S, 'manufacturingSurface') && ...
            isstruct(S.manufacturingSurface) && ...
            isfield(S.manufacturingSurface, 'cacheFile') && ...
            ~isempty(S.manufacturingSurface.cacheFile)
        cacheFile = char(S.manufacturingSurface.cacheFile);
    end
    if isempty(cacheFile) && isfield(S, 'options') && isstruct(S.options)
        optionFields = {'manufacturingSurfaceCacheFile', 'skinSourceCacheFile', ...
            'skinCacheFile'};
        for i = 1:numel(optionFields)
            if isfield(S.options, optionFields{i}) && ...
                    ~isempty(S.options.(optionFields{i}))
                cacheFile = char(S.options.(optionFields{i}));
                break;
            end
        end
    end
    if ~isempty(cacheFile)
        cacheFile = expandUserPath(cacheFile);
    end
end

function TR = ensureTriangulation(value)
    if isa(value, 'triangulation')
        TR = value;
    elseif isstruct(value) && isfield(value, 'Points') && ...
            isfield(value, 'ConnectivityList')
        TR = triangulation(double(value.ConnectivityList), double(value.Points));
    elseif isstruct(value) && isfield(value, 'vertices') && isfield(value, 'faces')
        TR = triangulation(double(value.faces), double(value.vertices));
    else
        error('acsPlanVelcroAnchors:BadMesh', ...
            'Mesh value must be a triangulation or faces/vertices struct.');
    end
    TR = triangulation(double(TR.ConnectivityList), double(TR.Points));
end

function S = firstStruct(raw)
    S = [];
    names = fieldnames(raw);
    for i = 1:numel(names)
        if isstruct(raw.(names{i}))
            S = raw.(names{i});
            return;
        end
    end
end

function earExclusions = readEarExclusions(fileName)
    earExclusions = struct();
    if isempty(fileName) || exist(fileName, 'file') ~= 2
        return;
    end
    S = load(fileName);
    candidates = {'out', 'earExclusions', 'outForSave'};
    for i = 1:numel(candidates)
        if isfield(S, candidates{i}) && isstruct(S.(candidates{i}))
            earExclusions = S.(candidates{i});
            return;
        end
    end
    earExclusions = firstStruct(S);
    if isempty(earExclusions)
        earExclusions = struct();
    end
end

function plan = autoSixPointAnchorPlan(TRskin, earExclusions, opts)
    V = double(TRskin.Points);
    V = V(all(isfinite(V), 2), :);
    V = V(V(:, 3) >= opts.zBedMm - 0.5, :);
    if size(V, 1) < 24
        V = double(TRskin.Points);
        V = V(all(isfinite(V), 2), :);
    end
    center = median(V, 1);
    xSpan = max(eps, max(V(:, 1)) - min(V(:, 1)));
    ySpan = max(eps, max(V(:, 2)) - min(V(:, 2)));
    zSpan = max(eps, max(V(:, 3)) - min(V(:, 3)));
    xTargets = [localPercentile(V(:, 1), 2), localPercentile(V(:, 1), 98)];
    xPreauricTargets = xTargets + ...
        [-opts.geometry.outerWidthMm, opts.geometry.outerWidthMm];
    yCaudal = localPercentile(V(:, 2), 2);
    yMid = localPercentile(V(:, 2), 50);
    yRostral = localPercentile(V(:, 2), 82);
    zTarget = localPercentile(V(:, 3), 35);

    if isfield(earExclusions, 'exclusionCenters') && ...
            isfield(earExclusions, 'exclusionRadiusMM') && ...
            size(earExclusions.exclusionCenters, 1) >= 2
        centers = double(earExclusions.exclusionCenters);
        radii = double(earExclusions.exclusionRadiusMM(:));
        if isscalar(radii)
            radii = repmat(radii, size(centers, 1), 1);
        end
        [~, leftEar] = min(centers(:, 1));
        [~, rightEar] = max(centers(:, 1));
        leftPreauricY = centers(leftEar, 2) + radii(leftEar) + 2;
        rightPreauricY = centers(rightEar, 2) + radii(rightEar) + 2;
    else
        leftPreauricY = yMid;
        rightPreauricY = yMid;
    end

    specs = {
        'leftCaudolateral',  -1, xTargets(1), yCaudal, 'caudalEdge'
        'leftPreauricular',  -1, xPreauricTargets(1), leftPreauricY, 'preauricular'
        'leftRostrolateral', -1, xTargets(1), yRostral, 'lateralEdge'
        'rightCaudolateral',  1, xTargets(2), yCaudal, 'caudalEdge'
        'rightPreauricular',  1, xPreauricTargets(2), rightPreauricY, 'preauricular'
        'rightRostrolateral', 1, xTargets(2), yRostral, 'lateralEdge'};

    anchors = zeros(size(specs, 1), 3);
    outDirs = zeros(size(specs, 1), 3);
    for i = 1:size(specs, 1)
        sideSign = specs{i, 2};
        target = [specs{i, 3}, specs{i, 4}, zTarget];
        placementMode = specs{i, 5};
        anchors(i, :) = selectAutoAnchor(V, target, sideSign, center, ...
            xSpan, ySpan, zSpan, placementMode);
        outDirs(i, :) = roleOutDir(anchors(i, :), center, sideSign, placementMode);
    end

    plan = struct();
    plan.createdOn = char(datetime('now'));
    plan.type = 'velcroAnchorPlan';
    plan.mode = 'sixPoint';
    if isfield(opts, 'anchorMeshLabel')
        plan.source = ['autoSixPoint:' opts.anchorMeshLabel];
    else
        plan.source = 'autoSixPoint';
    end
    plan.names = specs(:, 1);
    plan.anchorsMm = anchors;
    plan.outDirs = outDirs;
    plan.geometry = opts.geometry;
end

function anchor = selectAutoAnchor(V, target, sideSign, center, xSpan, ySpan, zSpan, mode)
    sideMask = sideSign * (V(:, 1) - center(1)) >= -0.08 * xSpan;
    if nnz(sideMask) < 6
        sideMask = true(size(V, 1), 1);
    end
    rows = find(sideMask);
    mode = lower(char(mode));
    switch mode
        case 'caudaledge'
            caudalCut = localPercentile(V(rows, 2), 6);
            caudalRows = rows(V(rows, 2) <= caudalCut);
            if numel(caudalRows) >= 6
                rows = caudalRows;
            end
            score = 0.35 * ((V(rows, 1) - target(1)) ./ xSpan) .^ 2 + ...
                7.00 * ((V(rows, 2) - target(2)) ./ ySpan) .^ 2 + ...
                0.08 * ((V(rows, 3) - target(3)) ./ zSpan) .^ 2;
        case 'lateraledge'
            lateralScore = sideSign * (V(rows, 1) - center(1));
            lateralCut = localPercentile(lateralScore, 88);
            lateralRows = rows(lateralScore >= lateralCut);
            if numel(lateralRows) >= 6
                rows = lateralRows;
            end
            score = 6.00 * ((V(rows, 1) - target(1)) ./ xSpan) .^ 2 + ...
                1.25 * ((V(rows, 2) - target(2)) ./ ySpan) .^ 2 + ...
                0.08 * ((V(rows, 3) - target(3)) ./ zSpan) .^ 2;
        otherwise
            score = 3.00 * ((V(rows, 1) - target(1)) ./ xSpan) .^ 2 + ...
                1.75 * ((V(rows, 2) - target(2)) ./ ySpan) .^ 2 + ...
                0.08 * ((V(rows, 3) - target(3)) ./ zSpan) .^ 2;
    end
    [~, localIdx] = min(score);
    anchor = V(rows(localIdx), :);
end

function plan = normalizeAnchorPlan(plan, TRskin, opts)
    if isfield(plan, 'anchorsMm')
        anchors = double(plan.anchorsMm);
    elseif isfield(plan, 'anchors')
        anchors = double(plan.anchors);
    else
        anchors = zeros(0, 3);
    end
    if size(anchors, 2) ~= 3
        error('acsPlanVelcroAnchors:BadAnchors', ...
            'Velcro anchor points must be N-by-3 coordinates in millimeters.');
    end
    nRaw = size(anchors, 1);
    keep = all(isfinite(anchors), 2);
    anchors = anchors(keep, :);
    if isempty(anchors)
        error('acsPlanVelcroAnchors:NoAnchors', ...
            'Velcro anchor plan contains no finite anchor points.');
    end

    if isfield(plan, 'names') && numel(plan.names) >= nRaw
        names = cellstr(plan.names(:));
        names = names(1:nRaw);
        names = names(keep);
    else
        names = defaultAnchorNames(size(anchors, 1));
    end
    outDirs = zeros(0, 3);
    if isfield(plan, 'outDirs') && size(plan.outDirs, 2) == 3 && ...
            size(plan.outDirs, 1) == nRaw
        outDirs = double(plan.outDirs);
        outDirs = outDirs(keep, :);
    elseif isfield(plan, 'outDirs') && size(plan.outDirs, 2) == 3 && ...
            size(plan.outDirs, 1) >= size(anchors, 1)
        outDirs = double(plan.outDirs(1:size(anchors, 1), :));
    end
    normals = zeros(0, 3);
    if isfield(plan, 'normals') && size(plan.normals, 2) == 3 && ...
            size(plan.normals, 1) == nRaw
        normals = double(plan.normals);
        normals = normals(keep, :);
    elseif isfield(plan, 'normals') && size(plan.normals, 2) == 3 && ...
            size(plan.normals, 1) >= size(anchors, 1)
        normals = double(plan.normals(1:size(anchors, 1), :));
    end
    [outDirs, normals] = completeAnchorFrames(TRskin, anchors, outDirs, normals);
    plan.names = names(:);
    plan.anchorsMm = anchors;
    plan.anchors = anchors;
    plan.outDirs = outDirs;
    plan.normals = normals;
    if isfield(plan, 'geometry') && isstruct(plan.geometry)
        plan.geometry = mergeGeometry(opts.geometry, plan.geometry);
    else
        plan.geometry = opts.geometry;
    end
end

function names = defaultAnchorNames(n)
    base = {'leftCaudolateral', 'leftPreauricular', 'leftRostrolateral', ...
        'rightCaudolateral', 'rightPreauricular', 'rightRostrolateral'};
    if n <= numel(base)
        names = base(1:n).';
    else
        names = arrayfun(@(i) sprintf('velcroAnchor%d', i), ...
            (1:n).', 'UniformOutput', false);
    end
end

function [outDirs, normals] = completeAnchorFrames(TRskin, anchors, outDirsIn, normalsIn)
    V = double(TRskin.Points);
    center = median(V, 1);
    surfaceNormals = surfaceNormalsAtPoints(TRskin, anchors);
    nAnchors = size(anchors, 1);
    outDirs = zeros(nAnchors, 3);
    normals = zeros(nAnchors, 3);
    for i = 1:nAnchors
        n = [0 0 1];
        if size(normalsIn, 1) >= i && norm(normalsIn(i, :)) > eps
            n = normalizeRow(normalsIn(i, :));
        elseif size(surfaceNormals, 1) >= i && norm(surfaceNormals(i, :)) > eps
            n = normalizeRow(surfaceNormals(i, :));
        end
        radial = anchors(i, :) - center;
        if dot(n, radial) < 0
            n = -n;
        end
        if n(3) < -0.85
            n = -n;
        end

        if size(outDirsIn, 1) >= i && norm(outDirsIn(i, :)) > eps
            d = normalizeRow(outDirsIn(i, :));
        else
            d = lateralOutDir(anchors(i, :), center, signWithFallback(radial(1)));
        end
        d = d - dot(d, n) * n;
        if norm(d) <= eps
            d = lateralOutDir(anchors(i, :), center, signWithFallback(radial(1)));
            d = d - dot(d, n) * n;
        end
        if norm(d) <= eps
            [d, ~] = localTransverseBasis(n);
        else
            d = normalizeRow(d);
        end
        normals(i, :) = n;
        outDirs(i, :) = d;
    end
end

function out = buildOutput(plan, source, opts)
    out = struct();
    out.createdOn = char(datetime('now'));
    out.type = 'velcroAnchorPlan';
    out.mode = 'sixPoint';
    out.source = source;
    out.names = plan.names;
    out.anchorsMm = plan.anchorsMm;
    out.anchors = plan.anchorsMm;
    out.outDirs = plan.outDirs;
    out.normals = plan.normals;
    out.geometry = plan.geometry;
    out.params = plan.geometry;
    out.options = rmfieldIfPresent(opts, {'geometry'});
end

function tf = shouldOpenGui(outputFile, opts, existingMatches)
    if ~opts.showFigures
        tf = false;
        return;
    end
    if nargin < 3
        existingMatches = true;
    end
    exists = exist(outputFile, 'file') == 2;
    switch opts.editMode
        case 'always'
            tf = true;
        case 'never'
            tf = false;
        otherwise
            tf = opts.force || ~exists || ~existingMatches;
    end
end

function [plan, accepted, fig] = velcroAnchorGui(TRskin, TRanchor, plan, ...
        siteMarkers, opts)
    V = double(TRskin.Points);
    Vanchor = double(TRanchor.Points);
    Fdisp = displayFaces(double(TRskin.ConnectivityList), opts.displayMaxFaces);
    FanchorDisp = displayFaces(double(TRanchor.ConnectivityList), opts.displayMaxFaces);
    accepted = false;
    finalPlan = plan;
    state = struct('plan', plan, 'active', 1, ...
        'showLabels', true, 'showOutlines', true, 'showElectrodes', true);

    fig = figure('Name', 'CapMaker Velcro anchor planner', ...
        'NumberTitle', 'off', 'Color', 'w', ...
        'Units', 'normalized', 'Position', [0.04 0.05 0.92 0.88]);
    ax = axes('Parent', fig, 'Units', 'normalized', ...
        'Position', [0.025 0.045 0.75 0.91]);
    hold(ax, 'on');
    patch(ax, 'Faces', Fdisp, 'Vertices', V, ...
        'FaceColor', [0.72 0.74 0.76], ...
        'FaceAlpha', opts.meshAlpha, ...
        'EdgeColor', 'none', 'HitTest', 'off');
    if ~sameMesh(TRskin, TRanchor)
        patch(ax, 'Faces', FanchorDisp, 'Vertices', Vanchor, ...
            'FaceColor', [0.05 0.28 0.85], ...
            'FaceAlpha', 0.35, ...
            'EdgeColor', 'none', 'HitTest', 'off');
    end
    electrodeGroup = hggroup('Parent', ax, 'Visible', onOff(state.showElectrodes));
    drawElectrodeMarkers(electrodeGroup, ax, siteMarkers);
    anchorGroup = hggroup('Parent', ax);

    axis(ax, 'equal');
    axis(ax, 'vis3d');
    axis(ax, 'off');
    view(ax, 3);
    camlight(ax, 'headlight');
    lighting(ax, 'flat');
    rotate3d(fig, 'on');
    title(ax, 'Velcro attachment anchors', 'Interpreter', 'none');
    fitCameraToMesh(ax, [V; Vanchor]);

    popup = uicontrol(fig, 'Style', 'popupmenu', 'Units', 'normalized', ...
        'Position', [0.795 0.86 0.185 0.05], ...
        'String', state.plan.names, 'Callback', @onPopup);
    status = uicontrol(fig, 'Style', 'text', 'Units', 'normalized', ...
        'Position', [0.795 0.68 0.185 0.16], 'BackgroundColor', 'w', ...
        'HorizontalAlignment', 'left', 'FontSize', 9);
    uicontrol(fig, 'Style', 'pushbutton', 'Units', 'normalized', ...
        'Position', [0.795 0.61 0.087 0.05], 'String', 'Previous', ...
        'Callback', @onPrevious);
    uicontrol(fig, 'Style', 'pushbutton', 'Units', 'normalized', ...
        'Position', [0.893 0.61 0.087 0.05], 'String', 'Next', ...
        'Callback', @onNext);
    uicontrol(fig, 'Style', 'pushbutton', 'Units', 'normalized', ...
        'Position', [0.795 0.55 0.087 0.05], 'String', 'Rotate -5', ...
        'Callback', @(varargin) rotateActive(-5));
    uicontrol(fig, 'Style', 'pushbutton', 'Units', 'normalized', ...
        'Position', [0.893 0.55 0.087 0.05], 'String', 'Rotate +5', ...
        'Callback', @(varargin) rotateActive(5));
    uicontrol(fig, 'Style', 'checkbox', 'Units', 'normalized', ...
        'Position', [0.795 0.49 0.185 0.04], 'String', 'Show outlines', ...
        'BackgroundColor', 'w', 'Value', state.showOutlines, ...
        'Callback', @onShowOutlines);
    uicontrol(fig, 'Style', 'checkbox', 'Units', 'normalized', ...
        'Position', [0.795 0.45 0.185 0.04], 'String', 'Show labels', ...
        'BackgroundColor', 'w', 'Value', state.showLabels, ...
        'Callback', @onShowLabels);
    uicontrol(fig, 'Style', 'checkbox', 'Units', 'normalized', ...
        'Position', [0.795 0.41 0.185 0.04], 'String', 'Show electrodes', ...
        'BackgroundColor', 'w', 'Value', state.showElectrodes, ...
        'Callback', @onShowElectrodes);
    uicontrol(fig, 'Style', 'pushbutton', 'Units', 'normalized', ...
        'Position', [0.795 0.37 0.185 0.06], 'String', 'Reset auto', ...
        'Callback', @onResetAuto);
    uicontrol(fig, 'Style', 'pushbutton', 'Units', 'normalized', ...
        'Position', [0.795 0.27 0.185 0.07], 'String', 'Done', ...
        'Callback', @onDone);
    uicontrol(fig, 'Style', 'pushbutton', 'Units', 'normalized', ...
        'Position', [0.795 0.18 0.185 0.07], 'String', 'Cancel', ...
        'Callback', @onCancel);
    helpText = sprintf(['Shift-click: move active anchor\n', ...
        '[/]: rotate active loop 5 deg\n', ...
        '1-6: choose | n/p: next/previous\n', ...
        'x/y/z: views | r: refit view\n', ...
        'd/Enter: done | Esc: cancel']);
    uicontrol(fig, 'Style', 'text', 'Units', 'normalized', ...
        'Position', [0.795 0.02 0.185 0.145], 'BackgroundColor', 'w', ...
        'HorizontalAlignment', 'left', 'FontSize', 7.5, 'String', helpText);

    set(fig, 'WindowButtonDownFcn', @onMouseDown);
    set(fig, 'WindowKeyPressFcn', @onKeyPress);
    refresh();
    fitCameraToMesh(ax, displayPoints());
    uiwait(fig);
    plan = finalPlan;

    function P = displayPoints()
        P = [V; Vanchor; siteMarkers.pointsMm; ...
            anchorPlanExtentPoints(state.plan)];
    end

    function refresh()
        if isgraphics(anchorGroup)
            delete(get(anchorGroup, 'Children'));
        end
        A = state.plan.anchorsMm;
        D = state.plan.outDirs;
        N = state.plan.normals;
        colors = repmat([0.00 0.60 0.65], size(A, 1), 1);
        colors(state.active, :) = [1.00 0.78 0.05];
        h = scatter3(ax, A(:, 1), A(:, 2), A(:, 3), 86, colors, ...
            'filled', 'MarkerEdgeColor', [0.05 0.05 0.05], ...
            'LineWidth', 1.0, 'HitTest', 'off');
        parentToGroup(h, anchorGroup);
        if state.showOutlines
            drawAnchorOutlines(anchorGroup, ax, state.plan);
        end
        if state.showLabels
            drawAnchorLabels(anchorGroup, ax, state.plan);
        end
        h = quiver3(ax, A(:, 1), A(:, 2), A(:, 3), ...
            12 * D(:, 1), 12 * D(:, 2), 12 * D(:, 3), ...
            0, 'Color', [0.00 0.45 0.55], 'LineWidth', 1.5, ...
            'HitTest', 'off');
        parentToGroup(h, anchorGroup);
        h = quiver3(ax, A(:, 1), A(:, 2), A(:, 3), ...
            8 * N(:, 1), 8 * N(:, 2), 8 * N(:, 3), ...
            0, 'Color', [0.45 0.45 0.45], 'LineWidth', 1.1, ...
            'HitTest', 'off');
        parentToGroup(h, anchorGroup);
        set(popup, 'Value', state.active);
        set(status, 'String', statusText(state.plan, state.active));
        drawnow limitrate;
    end

    function onMouseDown(~, event)
        if ~hasModifier(event, 'shift', fig)
            return;
        end
        disableToolbarModes(fig);
        idx = nearestVisibleVertexFromClick(ax, Vanchor, opts.pickRadiusMm);
        if isempty(idx) || ~isfinite(idx)
            return;
        end
        state.plan.anchorsMm(state.active, :) = Vanchor(idx, :);
        state.plan.anchors = state.plan.anchorsMm;
        state.plan = normalizeAnchorPlan(state.plan, TRskin, opts);
        refresh();
    end

    function onKeyPress(~, event)
        key = lower(char(event.Key));
        character = '';
        try
            character = char(event.Character);
        catch
        end
        if strcmp(character, '[') || any(strcmp(key, {'leftbracket', 'openbracket'}))
            rotateActive(-5);
            return;
        elseif strcmp(character, ']') || any(strcmp(key, {'rightbracket', 'closebracket'}))
            rotateActive(5);
            return;
        end
        switch key
            case {'1', '2', '3', '4', '5', '6'}
                idx = str2double(key);
                if idx <= numel(state.plan.names)
                    state.active = idx;
                end
            case 'n'
                onNext();
            case 'p'
                onPrevious();
            case 'r'
                fitCameraToMesh(ax, displayPoints());
            case {'x', 'y', 'z'}
                setNamedView(ax, displayPoints(), key);
            case {'d', 'return', 'enter'}
                onDone();
                return;
            case 'escape'
                onCancel();
                return;
        end
        refresh();
    end

    function rotateActive(deltaDeg)
        iActive = state.active;
        state.plan.outDirs(iActive, :) = rotateVectorAboutAxis( ...
            state.plan.outDirs(iActive, :), ...
            state.plan.normals(iActive, :), deltaDeg);
        state.plan = normalizeAnchorPlan(state.plan, TRskin, opts);
        refresh();
    end

    function onPopup(~, ~)
        state.active = get(popup, 'Value');
        refresh();
    end

    function onPrevious(varargin) %#ok<INUSD>
        state.active = max(1, state.active - 1);
        refresh();
    end

    function onNext(varargin) %#ok<INUSD>
        state.active = min(numel(state.plan.names), state.active + 1);
        refresh();
    end

    function onShowOutlines(src, ~)
        state.showOutlines = logical(get(src, 'Value'));
        refresh();
    end

    function onShowLabels(src, ~)
        state.showLabels = logical(get(src, 'Value'));
        refresh();
    end

    function onShowElectrodes(src, ~)
        state.showElectrodes = logical(get(src, 'Value'));
        if isgraphics(electrodeGroup)
            set(electrodeGroup, 'Visible', onOff(state.showElectrodes));
        end
    end

    function onResetAuto(varargin) %#ok<INUSD>
        state.plan = autoSixPointAnchorPlan(TRanchor, earExclusions, opts);
        state.plan = normalizeAnchorPlan(state.plan, TRskin, opts);
        refresh();
    end

    function onDone(varargin) %#ok<INUSD>
        accepted = true;
        finalPlan = state.plan;
        finalPlan.cameraState = captureCameraState(ax);
        if isgraphics(fig)
            uiresume(fig);
        end
    end

    function onCancel(varargin) %#ok<INUSD>
        accepted = false;
        finalPlan = state.plan;
        if isgraphics(fig)
            uiresume(fig);
        end
    end
end

function drawAnchorOutlines(parent, ax, plan)
    A = plan.anchorsMm;
    D = plan.outDirs;
    N = plan.normals;
    geom = plan.geometry;
    for i = 1:size(A, 1)
        [outer, inner, attach] = anchorOutline(A(i, :), D(i, :), N(i, :), geom);
        h = plot3(ax, outer(:, 1), outer(:, 2), outer(:, 3), ...
            'Color', [0.00 0.60 0.65], 'LineWidth', 2.0, ...
            'HitTest', 'off');
        parentToGroup(h, parent);
        h = plot3(ax, inner(:, 1), inner(:, 2), inner(:, 3), ...
            'Color', [0.00 0.30 0.38], 'LineWidth', 1.4, ...
            'HitTest', 'off');
        parentToGroup(h, parent);
        if ~isempty(attach)
            h = plot3(ax, attach(:, 1), attach(:, 2), attach(:, 3), ...
                'Color', [0.00 0.60 0.65], 'LineStyle', '--', ...
                'LineWidth', 1.2, 'HitTest', 'off');
            parentToGroup(h, parent);
        end
    end
end

function drawAnchorLabels(parent, ax, plan)
    A = plan.anchorsMm;
    names = cellstr(plan.names(:));
    for i = 1:size(A, 1)
        h = text(ax, A(i, 1), A(i, 2), A(i, 3), [' ' names{i}], ...
            'Color', [0.00 0.25 0.32], 'FontWeight', 'bold', ...
            'FontSize', 8, 'Interpreter', 'none', ...
            'HitTest', 'off');
        parentToGroup(h, parent);
    end
end

function drawElectrodeMarkers(parent, ax, siteMarkers)
    if isempty(siteMarkers) || ~isstruct(siteMarkers) || ...
            ~isfield(siteMarkers, 'pointsMm') || isempty(siteMarkers.pointsMm)
        return;
    end
    P = double(siteMarkers.pointsMm);
    if isempty(P) || size(P, 2) ~= 3
        return;
    end
    if isfield(siteMarkers, 'names')
        names = siteMarkers.names;
    else
        names = {};
    end
    if isempty(names)
        names = arrayfun(@(i) sprintf('site%d', i), ...
            (1:size(P, 1)).', 'UniformOutput', false);
    end
    names = cellstr(names(:));
    if numel(names) < size(P, 1)
        names(end + 1:size(P, 1), 1) = arrayfun(@(i) sprintf('site%d', i), ...
            (numel(names) + 1:size(P, 1)).', 'UniformOutput', false);
    end

    labels = regexprep(names(1:size(P, 1)), '^custom', '', 'ignorecase');
    labelsLower = lower(string(labels(:)));
    isEeg = contains(labelsLower, 'eeg');
    isTes = contains(labelsLower, 'tes');
    other = ~(isEeg | isTes);

    drawMarkerSubset(isTes, [0.90 0.12 0.10], 'o');
    drawMarkerSubset(isEeg, [0.58 0.10 0.80], 'd');
    drawMarkerSubset(other, [0.15 0.15 0.15], 's');

    for i = 1:size(P, 1)
        h = text(ax, P(i, 1), P(i, 2), P(i, 3), [' ' labels{i}], ...
            'Color', [0.08 0.08 0.08], 'FontSize', 7, ...
            'FontWeight', 'bold', 'Interpreter', 'none', ...
            'HitTest', 'off');
        parentToGroup(h, parent);
    end

    function drawMarkerSubset(mask, colorValue, markerValue)
        if ~any(mask)
            return;
        end
        h = scatter3(ax, P(mask, 1), P(mask, 2), P(mask, 3), ...
            58, colorValue, markerValue, 'filled', ...
            'MarkerEdgeColor', [0.02 0.02 0.02], ...
            'LineWidth', 0.8, 'HitTest', 'off');
        parentToGroup(h, parent);
    end
end

function [outer, inner, attach] = anchorOutline(anchor, outDir, normal, geom)
    [center, uHat, vHat, nHat] = anchorFrame(anchor, outDir, normal, geom);
    theta = linspace(0, 2*pi, 97).';
    outer = center + ...
        (geom.outerLengthMm / 2 * cos(theta)) * uHat + ...
        (geom.outerWidthMm / 2 * sin(theta)) * vHat + ...
        (0.55 * geom.thicknessMm) * nHat;
    innerLength = geom.outerLengthMm - 2 * geom.frameWidthMm;
    innerWidth = geom.outerWidthMm - 2 * geom.frameWidthMm;
    inner = center + ...
        (innerLength / 2 * cos(theta)) * uHat + ...
        (innerWidth / 2 * sin(theta)) * vHat + ...
        (0.58 * geom.thicknessMm) * nHat;
    attach = zeros(0, 3);
    if geom.attachLengthMm > 0
        u0 = -geom.attachWidthMm / 2;
        u1 = geom.attachWidthMm / 2;
        v0 = -geom.outerWidthMm / 2 - geom.attachLengthMm;
        v1 = -geom.outerWidthMm / 2 + geom.frameWidthMm;
        UV = [u0 v0; u1 v0; u1 v1; u0 v1; u0 v0];
        attach = center + UV(:, 1) * uHat + UV(:, 2) * vHat + ...
            (0.6 * geom.thicknessMm) * nHat;
    end
end

function [center, uHat, vHat, nHat] = anchorFrame(anchor, outDir, normal, geom)
    nHat = normalizeRow(normal);
    if norm(nHat) <= eps
        nHat = [0 0 1];
    end
    vHat = normalizeRow(outDir - dot(outDir, nHat) * nHat);
    if norm(vHat) <= eps
        [~, vHat] = localTransverseBasis(nHat);
    end
    uHat = normalizeRow(cross(nHat, vHat));
    if norm(uHat) <= eps
        [uHat, vHat] = localTransverseBasis(nHat);
    end
    center = anchor + geom.outboardOffsetMm * vHat;
end

function textOut = statusText(plan, active)
    p = plan.anchorsMm(active, :);
    geom = plan.geometry;
    textOut = sprintf(['Active: %s\n', ...
        'Anchor: [%.1f %.1f %.1f] mm\n', ...
        'Loop outer: %.1f x %.1f mm\n', ...
        'Frame/thickness: %.1f / %.1f mm\n', ...
        'Attach pad: %.1f x %.1f mm'], ...
        plan.names{active}, p(1), p(2), p(3), ...
        geom.outerLengthMm, geom.outerWidthMm, ...
        geom.frameWidthMm, geom.thicknessMm, ...
        geom.attachLengthMm, geom.attachWidthMm);
end

function fig = makeQcFigure(TRskin, TRanchor, out, siteMarkers, opts, visible)
    V = double(TRskin.Points);
    Vanchor = double(TRanchor.Points);
    Fdisp = displayFaces(double(TRskin.ConnectivityList), opts.displayMaxFaces);
    FanchorDisp = displayFaces(double(TRanchor.ConnectivityList), opts.displayMaxFaces);
    fig = figure('Name', 'CapMaker Velcro anchor QC', ...
        'NumberTitle', 'off', 'Color', 'w', 'Visible', visible, ...
        'Units', 'normalized', 'Position', [0.10 0.10 0.72 0.78]);
    ax = axes('Parent', fig, 'Units', 'normalized', ...
        'Position', [0.05 0.06 0.90 0.88]);
    hold(ax, 'on');
    patch(ax, 'Faces', Fdisp, 'Vertices', V, ...
        'FaceColor', [0.72 0.74 0.76], 'FaceAlpha', opts.meshAlpha, ...
        'EdgeColor', 'none');
    if ~sameMesh(TRskin, TRanchor)
        patch(ax, 'Faces', FanchorDisp, 'Vertices', Vanchor, ...
            'FaceColor', [0.05 0.28 0.85], 'FaceAlpha', 0.35, ...
            'EdgeColor', 'none');
    end
    group = hggroup('Parent', ax);
    drawElectrodeMarkers(group, ax, siteMarkers);
    drawAnchorOutlines(group, ax, out);
    drawAnchorLabels(group, ax, out);
    A = out.anchorsMm;
    h = scatter3(ax, A(:, 1), A(:, 2), A(:, 3), 86, [0.00 0.60 0.65], ...
        'filled', 'MarkerEdgeColor', [0.05 0.05 0.05]);
    parentToGroup(h, group);
    title(ax, 'Velcro attachment anchor plan', 'Interpreter', 'none');
    axis(ax, 'equal');
    axis(ax, 'vis3d');
    axis(ax, 'off');
    view(ax, 3);
    camlight(ax, 'headlight');
    lighting(ax, 'flat');
    fitCameraToMesh(ax, [V; Vanchor; siteMarkers.pointsMm; ...
        anchorPlanExtentPoints(out)]);
end

function idx = nearestVisibleVertexFromClick(ax, V, pickRadiusMm)
    [rayOrigin, rayDirection] = clickRay(ax);
    d = normalizeRow(rayDirection);
    W = bsxfun(@minus, V, rayOrigin);
    t = W * d(:);
    closest = bsxfun(@plus, rayOrigin, t .* d);
    dist2 = sum((V - closest) .^ 2, 2);
    dist2(t < 0) = inf;

    span = max(max(V, [], 1) - min(V, [], 1));
    if isempty(pickRadiusMm)
        pickRadiusMm = max(1.5, span / 80);
    end
    candidates = find(dist2 <= pickRadiusMm .^ 2 & isfinite(dist2));
    if isempty(candidates)
        [~, order] = sort(dist2, 'ascend');
        candidates = order(1:min(40, nnz(isfinite(dist2))));
    end
    candidates = candidates(isfinite(dist2(candidates)));
    if isempty(candidates)
        idx = [];
        return;
    end
    nearT = t(candidates);
    nearD = sqrt(dist2(candidates));
    score = nearT + 0.25 * pickRadiusMm * nearD ./ max(pickRadiusMm, eps);
    [~, localIdx] = min(score);
    idx = candidates(localIdx);
end

function [origin, direction] = clickRay(ax)
    cp = get(ax, 'CurrentPoint');
    origin = cp(1, :);
    direction = cp(2, :) - cp(1, :);
    if norm(direction) <= eps
        direction = [0 0 1];
    else
        direction = direction ./ norm(direction);
    end
end

function fitCameraToMesh(ax, V)
    finite = all(isfinite(V), 2);
    V = V(finite, :);
    if isempty(V)
        V = zeros(1, 3);
    end
    boundsMin = min(V, [], 1);
    boundsMax = max(V, [], 1);
    center = (boundsMin + boundsMax) ./ 2;
    spanVec = boundsMax - boundsMin;
    span = max(spanVec);
    if ~isfinite(span) || span <= eps
        span = 100;
        spanVec = [100 100 100];
    end
    pad = 0.04 * span;
    xlim(ax, [boundsMin(1) - pad, boundsMax(1) + pad]);
    ylim(ax, [boundsMin(2) - pad, boundsMax(2) + pad]);
    zlim(ax, [boundsMin(3) - pad, boundsMax(3) + pad]);
    direction = normalizeRow([1 -1 0.7]);
    viewAngleDeg = 18;
    radius = max(0.5 * norm(spanVec), span / 2);
    cameraDistance = 1.12 * radius / max(tand(viewAngleDeg / 2), eps);
    camtarget(ax, center);
    campos(ax, center + direction .* cameraDistance);
    camup(ax, [0 0 1]);
    camproj(ax, 'perspective');
    daspect(ax, [1 1 1]);
    set(ax, 'CameraViewAngle', viewAngleDeg);
    drawnow limitrate;
end

function setNamedView(ax, V, key)
    finite = all(isfinite(V), 2);
    V = V(finite, :);
    if isempty(V)
        V = zeros(1, 3);
    end
    boundsMin = min(V, [], 1);
    boundsMax = max(V, [], 1);
    center = (boundsMin + boundsMax) ./ 2;
    spanVec = boundsMax - boundsMin;
    span = max(spanVec);
    if ~isfinite(span) || span <= eps
        span = 100;
        spanVec = [100 100 100];
    end
    pad = 0.04 * span;
    xlim(ax, [boundsMin(1) - pad, boundsMax(1) + pad]);
    ylim(ax, [boundsMin(2) - pad, boundsMax(2) + pad]);
    zlim(ax, [boundsMin(3) - pad, boundsMax(3) + pad]);
    switch lower(key)
        case 'x'
            direction = [1 0 0];
            up = [0 0 1];
        case 'y'
            direction = [0 -1 0];
            up = [0 0 1];
        otherwise
            direction = [0 0 1];
            up = [0 1 0];
    end
    viewAngleDeg = 18;
    radius = max(0.5 * norm(spanVec), span / 2);
    cameraDistance = 1.12 * radius / max(tand(viewAngleDeg / 2), eps);
    camtarget(ax, center);
    campos(ax, center + direction .* cameraDistance);
    camup(ax, up);
    camproj(ax, 'perspective');
    daspect(ax, [1 1 1]);
    set(ax, 'CameraViewAngle', viewAngleDeg);
    drawnow limitrate;
end

function state = captureCameraState(ax)
    state = struct('CameraPosition', get(ax, 'CameraPosition'), ...
        'CameraTarget', get(ax, 'CameraTarget'), ...
        'CameraUpVector', get(ax, 'CameraUpVector'), ...
        'CameraViewAngle', get(ax, 'CameraViewAngle'));
end

function Fdisp = displayFaces(F, maxFaces)
    if size(F, 1) <= maxFaces
        Fdisp = F;
        return;
    end
    idx = unique(round(linspace(1, size(F, 1), maxFaces)));
    Fdisp = F(idx(:), :);
end

function P = anchorPlanExtentPoints(plan)
    P = zeros(0, 3);
    if ~isstruct(plan) || ~isfield(plan, 'anchorsMm') || ...
            ~isfield(plan, 'outDirs') || ~isfield(plan, 'normals') || ...
            ~isfield(plan, 'geometry')
        return;
    end
    A = double(plan.anchorsMm);
    D = double(plan.outDirs);
    N = double(plan.normals);
    geom = plan.geometry;
    if isempty(A) || size(A, 2) ~= 3
        return;
    end
    n = min([size(A, 1), size(D, 1), size(N, 1)]);
    for i = 1:n
        [outer, inner, attach] = anchorOutline(A(i, :), D(i, :), N(i, :), geom);
        P = [P; outer; inner; attach]; %#ok<AGROW>
    end
end

function tf = sameMesh(A, B)
    tf = isequal(size(A.Points), size(B.Points)) && ...
        isequal(size(A.ConnectivityList), size(B.ConnectivityList)) && ...
        isequal(double(A.Points), double(B.Points)) && ...
        isequal(double(A.ConnectivityList), double(B.ConnectivityList));
end

function normals = surfaceNormalsAtPoints(TRskin, points)
    V = double(TRskin.Points);
    Nv = vertexNormal(TRskin);
    Nv = bsxfun(@rdivide, Nv, max(sqrt(sum(Nv .^ 2, 2)), eps));
    center = median(V, 1);
    normals = zeros(size(points));
    for i = 1:size(points, 1)
        d2 = sum((V - points(i, :)) .^ 2, 2);
        [~, idx] = min(d2);
        n = Nv(idx, :);
        if dot(n, V(idx, :) - center) < 0
            n = -n;
        end
        normals(i, :) = normalizeRow(n);
    end
end

function dir = roleOutDir(point, center, sideSign, mode)
    if nargin < 3 || sideSign == 0 || ~isfinite(sideSign)
        sideSign = signWithFallback(point(1) - center(1));
    end
    if nargin < 4 || isempty(mode)
        mode = 'preauricular';
    end
    switch lower(char(mode))
        case 'caudaledge'
            caudalTiltDeg = 30;
            planarSpinDeg = 0;
        case 'lateraledge'
            caudalTiltDeg = 12;
            planarSpinDeg = 20 * sideSign;
        otherwise
            caudalTiltDeg = 5;
            planarSpinDeg = 0;
    end
    dir = [sideSign * cosd(caudalTiltDeg), -sind(caudalTiltDeg), 0];
    if planarSpinDeg ~= 0
        dir = rotateVectorAboutAxis(dir, [0 0 1], planarSpinDeg);
    end
    dir = normalizeRow(dir);
end

function dir = lateralOutDir(point, center, sideSign)
    if nargin < 3 || sideSign == 0 || ~isfinite(sideSign)
        sideSign = signWithFallback(point(1) - center(1));
    end
    dir = [sideSign 0 0];
    if norm(dir) <= eps
        dir = [sideSign 0 0];
    end
    dir = normalizeRow(dir);
end

function s = signWithFallback(value)
    if value < 0
        s = -1;
    else
        s = 1;
    end
end

function [u, v] = localTransverseBasis(n)
    n = normalizeRow(n);
    if abs(dot(n, [0 0 1])) < 0.9
        u = cross(n, [0 0 1]);
    else
        u = cross(n, [0 1 0]);
    end
    u = normalizeRow(u);
    v = normalizeRow(cross(n, u));
end

function row = normalizeRow(row)
    row = double(row(:).');
    n = norm(row);
    if n > eps
        row = row ./ n;
    end
end

function out = rotateVectorAboutAxis(vec, axisVec, angleDeg)
    vec = normalizeRow(vec);
    axisVec = normalizeRow(axisVec);
    if norm(vec) <= eps || norm(axisVec) <= eps
        out = vec;
        return;
    end
    c = cosd(angleDeg);
    s = sind(angleDeg);
    out = vec .* c + cross(axisVec, vec) .* s + ...
        axisVec .* dot(axisVec, vec) .* (1 - c);
    out = normalizeRow(out);
end

function logMsg(opts, varargin)
    if isstruct(opts) && isfield(opts, 'verbose') && opts.verbose
        fprintf([varargin{1} '\n'], varargin{2:end});
        drawnow('limitrate');
    end
end

function value = onOff(tf)
    if tf
        value = 'on';
    else
        value = 'off';
    end
end

function parentToGroup(h, group)
    if all(isgraphics(h)) && isgraphics(group)
        try
            set(h, 'Parent', group);
        catch
        end
    end
end

function q = localPercentile(values, pct)
    values = sort(values(isfinite(values(:))));
    if isempty(values)
        q = NaN;
        return;
    end
    pct = max(0, min(100, pct));
    pos = 1 + (numel(values) - 1) * pct / 100;
    lo = floor(pos);
    hi = ceil(pos);
    if lo == hi
        q = values(lo);
    else
        q = values(lo) + (pos - lo) * (values(hi) - values(lo));
    end
end

function geom = mergeGeometry(geom, overrides)
    fields = fieldnames(geom);
    for i = 1:numel(fields)
        if isfield(overrides, fields{i}) && ~isempty(overrides.(fields{i}))
            if strcmp(fields{i}, 'floorAtBed')
                geom.(fields{i}) = logical(overrides.(fields{i}));
            else
                value = double(overrides.(fields{i}));
                if isscalar(value) && isfinite(value)
                    geom.(fields{i}) = value;
                end
            end
        end
    end
end

function tf = savedPlanMatchesSource(plan, source)
    tf = isstruct(plan) && isfield(plan, 'source') && isstruct(plan.source) && ...
        isfield(plan.source, 'meshFingerprint') && ...
        meshFingerprintsMatch(plan.source.meshFingerprint, source.meshFingerprint);
    if ~tf
        return;
    end
    if isfield(source, 'anchorMeshFingerprint')
        tf = isfield(plan.source, 'anchorMeshFingerprint') && ...
            meshFingerprintsMatch(plan.source.anchorMeshFingerprint, ...
            source.anchorMeshFingerprint);
    end
    if tf && isfield(source, 'anchorPlanningVersion')
        tf = isfield(plan.source, 'anchorPlanningVersion') && ...
            strcmp(char(plan.source.anchorPlanningVersion), ...
            char(source.anchorPlanningVersion));
    end
end

function fp = meshFingerprint(TR)
    V = double(TR.Points);
    F = double(TR.ConnectivityList);
    fp = struct();
    fp.nPoints = size(V, 1);
    fp.nFaces = size(F, 1);
    fp.boundsMin = min(V, [], 1);
    fp.boundsMax = max(V, [], 1);
    fp.centroid = mean(V, 1);
    fp.pointSum = sum(V, 1);
    fp.pointSquaredSum = sum(V .^ 2, 1);
    fp.faceSum = sum(F, 1);
    fp.faceSquaredSum = sum(F .^ 2, 1);
end

function tf = meshFingerprintsMatch(a, b)
    fields = {'nPoints', 'nFaces', 'boundsMin', 'boundsMax', ...
        'pointSum', 'pointSquaredSum', 'faceSum', 'faceSquaredSum'};
    tf = true;
    for i = 1:numel(fields)
        if ~isfield(a, fields{i}) || ~isfield(b, fields{i})
            tf = false;
            return;
        end
        av = double(a.(fields{i}));
        bv = double(b.(fields{i}));
        if numel(av) ~= numel(bv) || any(abs(av(:) - bv(:)) > 1e-6)
            tf = false;
            return;
        end
    end
end

function out = loadExistingPlan(fileName)
    S = load(fileName);
    candidates = {'velcroAnchors', 'outForSave', 'out', 'anchorPlan', 'plan'};
    for i = 1:numel(candidates)
        if isfield(S, candidates{i}) && isstruct(S.(candidates{i})) && ...
                hasAnchorPoints(S.(candidates{i}))
            out = S.(candidates{i});
            return;
        end
    end
    out = firstStruct(S);
    if isempty(out) || ~hasAnchorPoints(out)
        error('acsPlanVelcroAnchors:BadSavedPlan', ...
            'No Velcro anchor plan was found in %s.', fileName);
    end
end

function tf = hasAnchorPoints(S)
    tf = isstruct(S) && ((isfield(S, 'anchorsMm') && ~isempty(S.anchorsMm)) || ...
        (isfield(S, 'anchors') && ~isempty(S.anchors)));
end

function fileName = defaultOutputFile(source)
    folder = pwd;
    stem = 'capMaker';
    if isfield(source, 'file') && ~isempty(source.file)
        folder = fileparts(source.file);
        stem = stripExtension(fileLabel(source.file));
    end
    stem = regexprep(stem, '(_printerBedSkinMesh|_manufacturingSkinMesh)$', '');
    fileName = fullfile(folder, [stem '_velcroAnchors.mat']);
end

function label = fileLabel(fileName)
    [~, name, ext] = fileparts(fileName);
    label = [name ext];
end

function stem = stripExtension(fileName)
    [~, stem] = fileparts(fileName);
end

function out = rmfieldIfPresent(S, fields)
    out = S;
    for i = 1:numel(fields)
        if isfield(out, fields{i})
            out = rmfield(out, fields{i});
        end
    end
end

function writeJsonReport(fileName, out)
    try
        ensureDir(fileparts(fileName));
        fid = fopen(fileName, 'w');
        cleaner = onCleanup(@() fclose(fid));
        fprintf(fid, '%s', jsonencode(jsonReady(out), 'PrettyPrint', true));
        delete(cleaner);
    catch ME
        warning('acsPlanVelcroAnchors:JsonWriteFailed', ...
            'Could not write JSON sidecar %s (%s).', fileName, ME.message);
    end
end

function value = jsonReady(value)
    if isa(value, 'triangulation') || isgraphics(value)
        value = [];
    elseif isstruct(value)
        fields = fieldnames(value);
        for i = 1:numel(fields)
            value.(fields{i}) = jsonReady(value.(fields{i}));
        end
    elseif iscell(value)
        for i = 1:numel(value)
            value{i} = jsonReady(value{i});
        end
    elseif isstring(value)
        value = cellstr(value);
    end
end

function saveQcFigure(fig, fileName)
    ensureDir(fileparts(fileName));
    try
        exportgraphics(fig, fileName, 'Resolution', 200);
    catch
        saveas(fig, fileName);
    end
end

function fileName = replaceExtension(fileName, newSuffix)
    [folder, stem] = fileparts(fileName);
    fileName = fullfile(folder, [stem newSuffix]);
end

function ensureDir(folder)
    if ~isempty(folder) && exist(folder, 'dir') ~= 7
        mkdir(folder);
    end
end

function pathOut = expandUserPath(pathIn)
    pathOut = char(pathIn);
    if isempty(pathOut)
        return;
    end
    if startsWith(pathOut, '~')
        home = char(java.lang.System.getProperty('user.home'));
        if isscalar(pathOut)
            pathOut = home;
        elseif any(pathOut(2) == ['/' filesep])
            pathOut = fullfile(home, pathOut(3:end));
        end
    end
end

function disableToolbarModes(fig)
    try
        zoom(fig, 'off');
    catch
    end
    try
        pan(fig, 'off');
    catch
    end
    try
        rotate3d(fig, 'off');
    catch
    end
end

function tf = hasModifier(event, name, fig)
    modifiers = {};
    try
        if isprop(event, 'Modifier')
            modifiers = event.Modifier;
        end
    catch
        modifiers = {};
    end
    if isempty(modifiers)
        try
            modifiers = get(fig, 'CurrentModifier');
        catch
            modifiers = {};
        end
    end
    if ischar(modifiers)
        modifiers = {modifiers};
    end
    tf = any(strcmpi(modifiers, name));
end

function TR = readStlTriangulationLocal(fileName)
    if exist('stlread', 'file') == 2
        raw = stlread(fileName);
        TR = ensureTriangulation(raw);
        return;
    end
    error('acsPlanVelcroAnchors:StlreadUnavailable', ...
        'MATLAB stlread is not available; provide a MAT mesh cache instead.');
end
