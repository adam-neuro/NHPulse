function out = acsMakeHeadpostExclusionFromPlacement(placementIn, surfaceSource, varargin)
% ACSMAKEHEADPOSTEXCLUSIONFROMPLACEMENT Build cap keepout from finalized headpost pose.
%
% out = acsMakeHeadpostExclusionFromPlacement(headpostPlacement, skinCacheFile)
% reads the finalized placed headpost mesh from acsPlanHeadpostPlacement,
% builds a no-print keepout around the exposed cylindrical post, and saves a
% standard implant exclusion product. This is intended to supersede the raw
% Polhemus-trace exclusion after the headpost GUI has been manually refined.
%
% Name-value options:
%   objectName     : saved object name ['headpost']
%   marginMm       : no-print buffer around selected footprint [5]
%   footprintMode  : 'postCylinder' or 'fullMesh' ['postCylinder']
%   postRadiusMm   : exposed post radius override [[] = placement estimate]
%   postCircleSamples : samples around post-cylinder footprint [96]
%   boundaryShrink : shrink factor passed to boundary() [0.75]
%   outputFile     : saved MAT exclusion file ['']
%   outputTag      : file/report tag ['headpostPlacementExclusion']
%   force          : overwrite existing output [false]
%   showFigures    : show QC figure [false]
%   saveFigures    : save QC figure [false]
%   verbose        : print summary [true]

    if nargin < 1 || isempty(placementIn)
        error('acsMakeHeadpostExclusionFromPlacement:MissingPlacement', ...
            'Provide a headpost placement struct or MAT file.');
    end
    if nargin < 2
        surfaceSource = [];
    elseif isNameValueStart(surfaceSource)
        varargin = [{surfaceSource}, varargin];
        surfaceSource = [];
    end

    opts = parseInputs(varargin{:});
    placement = readPlacement(placementIn);
    TRplaced = getPlacedMesh(placement);
    if isempty(surfaceSource)
        surfaceSource = getOptionalField(placement, 'surfaceSource', []);
    end
    [TRskin, source] = readSkinMeshOptional(surfaceSource);
    opts = resolveOutputFile(placement, source, opts);

    if exist(opts.outputFile, 'file') == 2 && ~opts.force
        S = load(opts.outputFile);
        out = firstStruct(S);
        if opts.verbose
            fprintf('Headpost placement exclusion already exists; reusing %s\n', ...
                opts.outputFile);
        end
        return;
    end

    P = double(TRplaced.Points);
    P = P(all(isfinite(P), 2), :);
    if size(P, 1) < 3
        error('acsMakeHeadpostExclusionFromPlacement:TooFewMeshPoints', ...
            'Placed headpost mesh must contain at least three finite vertices.');
    end

    [basePerimeter, footprintPoly, keepoutPoly, footprintInfo] = ...
        makeFootprintPolys(P, placement, opts);
    [x, y] = boundary(keepoutPoly);
    keep = isfinite(x) & isfinite(y);
    x = x(keep);
    y = y(keep);
    z = boundaryZ([x(:), y(:)], TRskin, medianFinite(P(:, 3)));
    keepoutBoundary = [x(:), y(:), z(:)];
    keepoutCenter = mean(basePerimeter(:, 1:2), 1);
    keepoutRadius = max(sqrt(sum((keepoutBoundary(:, 1:2) - ...
        keepoutCenter) .^ 2, 2)));

    fig = [];
    qcFile = '';
    if opts.showFigures || opts.saveFigures
        figVisible = 'off';
        if opts.showFigures
            figVisible = 'on';
        end
        fig = makeQcFigure(TRskin, TRplaced, basePerimeter, footprintPoly, ...
            keepoutPoly, keepoutBoundary, source, opts, figVisible);
        if opts.saveFigures
            qcFile = fullfile(fileparts(opts.outputFile), 'qc', ...
                [stripMatExtension(getFileName(opts.outputFile)) '_qc.png']);
            ensureDir(fileparts(qcFile));
            saveQcFigure(fig, qcFile);
        end
        if ~opts.showFigures
            close(fig);
            fig = [];
        end
    end

    out = struct();
    out.createdOn = char(datetime('now'));
    out.outputFile = opts.outputFile;
    out.qcFigure = qcFile;
    out.type = 'implantExclusion';
    out.name = opts.objectName;
    out.method = sprintf('finalized headpost placement %s footprint', ...
        opts.footprintMode);
    out.marginMm = opts.marginMm;
    out.footprintMode = opts.footprintMode;
    out.postRadiusMm = footprintInfo.postRadiusMm;
    out.footprintInfo = footprintInfo;
    out.coordinateFrame = 'capMakerPrintMm';
    out.placementFile = getOptionalField(placement, 'outputFile', '');
    out.surfaceSource = source;
    out.basePerimeterPrintMm = basePerimeter;
    out.projectedCoordinatesMm = basePerimeter;
    out.keepoutRadiusMm = keepoutRadius;
    out.footprintPoly = footprintPoly;
    out.keepoutPoly = keepoutPoly;
    out.railExclusionPolys = {keepoutPoly};
    out.keepoutBoundaryMm = keepoutBoundary;
    out.keepoutPolyX = keepoutBoundary(:, 1);
    out.keepoutPolyY = keepoutBoundary(:, 2);
    out.pointCoordinateFrames = struct( ...
        'basePerimeterPrintMm', 'capMakerPrintMm', ...
        'projectedCoordinatesMm', 'capMakerPrintMm', ...
        'keepoutBoundaryMm', 'capMakerPrintMm');
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
    p.FunctionName = 'acsMakeHeadpostExclusionFromPlacement';
    addParameter(p, 'objectName', 'headpost', @(x) ischar(x) || isstring(x));
    addParameter(p, 'marginMm', 5, @isNonnegativeScalar);
    addParameter(p, 'footprintMode', 'postCylinder', ...
        @(x) ischar(x) || isstring(x));
    addParameter(p, 'postRadiusMm', [], ...
        @(x) isempty(x) || isNonnegativeScalar(x));
    addParameter(p, 'postCircleSamples', 96, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 12);
    addParameter(p, 'boundaryShrink', 0.75, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0 && x <= 1);
    addParameter(p, 'outputFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'outputTag', 'headpostPlacementExclusion', ...
        @(x) ischar(x) || isstring(x));
    addParameter(p, 'force', false, @isBoolLike);
    addParameter(p, 'showFigures', false, @isBoolLike);
    addParameter(p, 'saveFigures', false, @isBoolLike);
    addParameter(p, 'verbose', true, @isBoolLike);
    parse(p, varargin{:});

    opts = p.Results;
    opts.objectName = safeName(char(opts.objectName));
    opts.marginMm = double(opts.marginMm);
    opts.footprintMode = normalizeFootprintMode(opts.footprintMode);
    if ~isempty(opts.postRadiusMm)
        opts.postRadiusMm = double(opts.postRadiusMm);
    end
    opts.postCircleSamples = round(double(opts.postCircleSamples));
    opts.boundaryShrink = double(opts.boundaryShrink);
    opts.outputFile = expandUserPath(char(opts.outputFile));
    opts.outputTag = safeName(char(opts.outputTag));
    opts.force = logical(opts.force);
    opts.showFigures = logical(opts.showFigures);
    opts.saveFigures = logical(opts.saveFigures);
    opts.verbose = logical(opts.verbose);
end

function tf = isNameValueStart(x)
    if ~(ischar(x) || isstring(x)) || numel(string(x)) ~= 1
        tf = false;
        return;
    end
    tf = any(strcmpi(char(x), {'objectName', 'marginMm', ...
        'footprintMode', 'postRadiusMm', 'postCircleSamples', ...
        'boundaryShrink', 'outputFile', 'outputTag', 'force', ...
        'showFigures', 'saveFigures', 'verbose'}));
end

function tf = isBoolLike(x)
    tf = (islogical(x) || isnumeric(x)) && isscalar(x);
end

function tf = isNonnegativeScalar(x)
    tf = isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0;
end

function value = normalizeFootprintMode(value)
    value = lower(strtrim(char(value)));
    switch regexprep(value, '[\s_\-]+', '')
        case {'post', 'postcylinder', 'cylinder', 'cylindricalpost'}
            value = 'postCylinder';
        case {'full', 'fullmesh', 'mesh', 'wholemesh', 'base'}
            value = 'fullMesh';
        otherwise
            error('acsMakeHeadpostExclusionFromPlacement:BadFootprintMode', ...
                'footprintMode must be ''postCylinder'' or ''fullMesh''.');
    end
end

function placement = readPlacement(value)
    if ischar(value) || isstring(value)
        S = loadStructFile(char(value));
        placement = readPlacement(S);
        return;
    end
    if ~isstruct(value)
        error('acsMakeHeadpostExclusionFromPlacement:BadPlacement', ...
            'placementIn must be a struct or MAT file.');
    end
    placement = value;
end

function TR = getPlacedMesh(placement)
    if isfield(placement, 'meshes') && isstruct(placement.meshes) && ...
            isfield(placement.meshes, 'TRplaced') && ...
            ~isempty(placement.meshes.TRplaced)
        TR = ensureTri(placement.meshes.TRplaced);
    elseif isfield(placement, 'TRplaced') && ~isempty(placement.TRplaced)
        TR = ensureTri(placement.TRplaced);
    else
        error('acsMakeHeadpostExclusionFromPlacement:MissingPlacedMesh', ...
            'Headpost placement does not contain meshes.TRplaced.');
    end
end

function [TRskin, source] = readSkinMeshOptional(value)
    TRskin = [];
    source = struct('type', '', 'file', '', 'cacheFile', '', ...
        'label', 'no surface source');
    if isempty(value)
        return;
    end
    if isa(value, 'triangulation')
        TRskin = value;
        source.type = 'triangulation';
        source.label = 'triangulation';
        return;
    end
    if isstruct(value) && isfield(value, 'TRskin') && ~isempty(value.TRskin)
        TRskin = ensureTri(value.TRskin);
        source.type = 'skinStruct';
        source.label = 'skin struct';
        return;
    end
    if isstruct(value)
        if isfield(value, 'cacheFile') && ~isempty(value.cacheFile)
            value = value.cacheFile;
        elseif isfield(value, 'file') && ~isempty(value.file)
            value = value.file;
        elseif isfield(value, 'source') && isstruct(value.source)
            [TRskin, source] = readSkinMeshOptional(value.source);
            return;
        end
    end
    if ~(ischar(value) || isstring(value))
        return;
    end
    fileName = expandUserPath(char(value));
    if exist(fileName, 'file') ~= 2
        return;
    end
    raw = load(fileName);
    if isfield(raw, 'TRskin') && ~isempty(raw.TRskin)
        TRskin = ensureTri(raw.TRskin);
    elseif isfield(raw, 'TRfiducialHead') && ~isempty(raw.TRfiducialHead)
        TRskin = ensureTri(raw.TRfiducialHead);
    else
        return;
    end
    source.type = 'skinCache';
    source.file = fileName;
    source.cacheFile = fileName;
    source.label = getFileName(fileName);
end

function [basePerimeter, footprintPoly, keepoutPoly, info] = ...
        makeFootprintPolys(points, placement, opts)
    switch opts.footprintMode
        case 'postCylinder'
            [basePerimeter, info] = postCylinderPerimeter(points, ...
                placement, opts);
        case 'fullMesh'
            [basePerimeter, info] = fullMeshPerimeter(points, opts);
        otherwise
            error('acsMakeHeadpostExclusionFromPlacement:BadFootprintMode', ...
                'Unknown footprintMode "%s".', opts.footprintMode);
    end

    footprintPoly = polyshape(basePerimeter(:, 1), basePerimeter(:, 2), ...
        'Simplify', true);
    try
        keepoutPoly = polybuffer(footprintPoly, opts.marginMm);
    catch
        keepoutPoly = fallbackBufferedPoly(basePerimeter(:, 1:2), ...
            opts.marginMm);
    end
end

function [basePerimeter, info] = postCylinderPerimeter(points, placement, opts)
    center = resolvePostCenter(points, placement);
    normalVector = resolvePostNormal(placement);
    postRadius = resolvePostRadius(points, center, normalVector, ...
        placement, opts);
    [u, v] = perpendicularBasis(normalVector);
    theta = linspace(0, 2*pi, opts.postCircleSamples + 1)';
    theta(end) = [];
    offsets = cos(theta) * u + sin(theta) * v;
    basePerimeter = bsxfun(@plus, center, postRadius * offsets);
    info = struct('mode', 'postCylinder', ...
        'centerMm', center, ...
        'normalVector', normalVector, ...
        'postRadiusMm', postRadius, ...
        'postCircleSamples', opts.postCircleSamples);
end

function [basePerimeter, info] = fullMeshPerimeter(points, opts)
    xy = unique(double(points(:, 1:2)), 'rows');
    if size(xy, 1) < 3
        error('acsMakeHeadpostExclusionFromPlacement:TooFewFootprintPoints', ...
            'At least three unique placed headpost XY points are needed.');
    end
    try
        k = boundary(xy(:, 1), xy(:, 2), opts.boundaryShrink);
    catch
        k = convhull(xy(:, 1), xy(:, 2));
    end
    baseXy = xy(k, :);
    z = repmat(medianFinite(points(:, 3)), size(baseXy, 1), 1);
    basePerimeter = [baseXy, z];
    info = struct('mode', 'fullMesh', ...
        'centerMm', mean(basePerimeter, 1), ...
        'normalVector', [0 0 1], ...
        'postRadiusMm', NaN, ...
        'postCircleSamples', size(basePerimeter, 1));
end

function center = resolvePostCenter(points, placement)
    center = [];
    if isstruct(placement) && isfield(placement, 'placement') && ...
            isstruct(placement.placement) && ...
            isfield(placement.placement, 'pose') && ...
            isstruct(placement.placement.pose) && ...
            isfield(placement.placement.pose, 'contactMm') && ...
            ~isempty(placement.placement.pose.contactMm)
        center = double(placement.placement.pose.contactMm(:)');
    elseif isstruct(placement) && isfield(placement, 'pose') && ...
            isstruct(placement.pose) && isfield(placement.pose, 'contactMm') && ...
            ~isempty(placement.pose.contactMm)
        center = double(placement.pose.contactMm(:)');
    end
    if numel(center) ~= 3 || any(~isfinite(center))
        center = median(double(points), 1);
    end
end

function normalVector = resolvePostNormal(placement)
    normalVector = [];
    if isstruct(placement) && isfield(placement, 'placement') && ...
            isstruct(placement.placement) && ...
            isfield(placement.placement, 'pose') && ...
            isstruct(placement.placement.pose) && ...
            isfield(placement.placement.pose, 'normalVector') && ...
            ~isempty(placement.placement.pose.normalVector)
        normalVector = double(placement.placement.pose.normalVector(:)');
    elseif isstruct(placement) && isfield(placement, 'pose') && ...
            isstruct(placement.pose) && ...
            isfield(placement.pose, 'normalVector') && ...
            ~isempty(placement.pose.normalVector)
        normalVector = double(placement.pose.normalVector(:)');
    end
    normalVector = normalizeRow(normalVector);
end

function postRadius = resolvePostRadius(points, center, normalVector, ...
        placement, opts)
    postRadius = opts.postRadiusMm;
    if isempty(postRadius)
        postRadius = getNestedOptionalField(placement, ...
            {'headpost', 'postRadiusEstimateMm'}, []);
    end
    if isempty(postRadius) || ~isscalar(postRadius) || ...
            ~isfinite(postRadius) || postRadius <= 0
        radial = pointLineDistance(points, center, normalVector);
        finiteRadial = radial(isfinite(radial) & radial > 0);
        if isempty(finiteRadial)
            postRadius = 5;
        else
            postRadius = percentileLocal(finiteRadial, 25);
        end
    end
    postRadius = double(postRadius);
end

function d = pointLineDistance(points, center, normalVector)
    delta = bsxfun(@minus, double(points), double(center));
    h = delta * normalizeRow(normalVector)';
    d2 = sum(delta .^ 2, 2) - h .^ 2;
    d = sqrt(max(d2, 0));
end

function [u, v] = perpendicularBasis(normalVector)
    n = normalizeRow(normalVector);
    ref = [0 0 1];
    if abs(dot(n, ref)) > 0.90
        ref = [1 0 0];
    end
    u = normalizeRow(cross(ref, n));
    v = normalizeRow(cross(n, u));
end

function z = boundaryZ(xy, TRskin, fallbackZ)
    if isempty(TRskin) || isempty(TRskin.Points)
        z = repmat(fallbackZ, size(xy, 1), 1);
        return;
    end
    idx = nearestRows(double(TRskin.Points(:, 1:2)), double(xy), 2500);
    z = double(TRskin.Points(idx, 3));
end

function fig = makeQcFigure(TRskin, TRplaced, basePerimeter, footprintPoly, ...
        keepoutPoly, keepoutBoundary, source, opts, figVisible)
    fig = figure('Name', 'Headpost placement exclusion QC', ...
        'NumberTitle', 'off', 'Color', 'w', 'Visible', figVisible, ...
        'Position', [100 80 1450 760]);
    tiledlayout(fig, 1, 2, 'Padding', 'loose', 'TileSpacing', 'loose');

    ax1 = nexttile;
    hold(ax1, 'on');
    if ~isempty(TRskin)
        hSkin = drawTri(ax1, TRskin, [0.74 0.76 0.80], 0.20);
    else
        hSkin = gobjects(0);
    end
    hHeadpost = drawTri(ax1, TRplaced, [0.45 0.48 0.52], 0.80);
    hKeepout = plot3(ax1, keepoutBoundary(:, 1), keepoutBoundary(:, 2), ...
        keepoutBoundary(:, 3), 'm-', 'LineWidth', 2.5);
    hFootprint = scatter3(ax1, basePerimeter(:, 1), basePerimeter(:, 2), ...
        basePerimeter(:, 3), 12, [0.05 0.30 0.85], 'filled');
    title(ax1, 'Placed headpost + keepout');
    legendHandles = [hSkin(:)' hHeadpost hKeepout hFootprint];
    legendLabels = [{'skin mesh'}, {'headpost'}, {'keepout'}, {'footprint'}];
    if isempty(hSkin)
        legendHandles = [hHeadpost hKeepout hFootprint];
        legendLabels = {'headpost', 'keepout', 'footprint'};
    end
    legend(ax1, legendHandles, legendLabels, ...
        'Location', 'northwest', 'Box', 'off', 'FontSize', 8);
    format3d(ax1);

    ax2 = nexttile;
    hold(ax2, 'on');
    hFootprint2 = plot(footprintPoly, 'FaceColor', [0.25 0.50 0.95], ...
        'FaceAlpha', 0.25, 'EdgeColor', [0.15 0.30 0.85]);
    hKeepout2 = plot(keepoutPoly, 'FaceColor', [0.95 0.15 0.45], ...
        'FaceAlpha', 0.20, 'EdgeColor', [0.80 0.05 0.30]);
    hFootprintPts = scatter(ax2, basePerimeter(:, 1), basePerimeter(:, 2), ...
        12, [0.05 0.30 0.85], 'filled');
    axis(ax2, 'equal');
    grid(ax2, 'on');
    xlabel(ax2, 'X (mm)');
    ylabel(ax2, 'Y (mm)');
    title(ax2, sprintf('%s + %.1f mm', ...
        opts.footprintMode, opts.marginMm), 'Interpreter', 'none');
    legend(ax2, [hFootprint2 hKeepout2 hFootprintPts], ...
        {'footprint', 'keepout', 'vertices'}, ...
        'Location', 'northwest', 'Box', 'off', 'FontSize', 8);

    compactFigureText(fig);
    sgtitle(fig, sprintf('Headpost exclusion QC: %s', opts.objectName), ...
        'Interpreter', 'none', 'FontWeight', 'bold');
end

function h = drawTri(ax, TR, color, alphaValue)
    h = patch(ax, 'Faces', TR.ConnectivityList, 'Vertices', TR.Points, ...
        'FaceColor', color, 'FaceAlpha', alphaValue, 'EdgeColor', 'none');
end

function format3d(ax)
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

function ps = fallbackBufferedPoly(xy, marginMm)
    theta = linspace(0, 2*pi, 32);
    theta(end) = [];
    allPts = zeros(0, 2);
    for i = 1:size(xy, 1)
        allPts = [allPts; xy(i, 1) + marginMm*cos(theta(:)), ...
            xy(i, 2) + marginMm*sin(theta(:))]; %#ok<AGROW>
    end
    k = convhull(allPts(:, 1), allPts(:, 2));
    ps = polyshape(allPts(k, 1), allPts(k, 2), 'Simplify', true);
end

function opts = resolveOutputFile(placement, source, opts)
    if ~isempty(opts.outputFile)
        return;
    end
    folder = pwd;
    stem = opts.objectName;
    placementFile = getOptionalField(placement, 'outputFile', '');
    if ~isempty(placementFile)
        folder = fileparts(placementFile);
        stem = stripMatExtension(getFileName(placementFile));
    elseif isfield(source, 'cacheFile') && ~isempty(source.cacheFile)
        folder = fileparts(source.cacheFile);
        stem = stripMatExtension(getFileName(source.cacheFile));
    end
    opts.outputFile = fullfile(folder, [stem '_' opts.outputTag '.mat']);
end

function idx = nearestRows(reference, query, chunk)
    idx = zeros(size(query, 1), 1);
    for a = 1:chunk:size(query, 1)
        b = min(size(query, 1), a + chunk - 1);
        D = squaredDistanceRows(query(a:b, :), reference);
        [~, idxLocal] = min(D, [], 2);
        idx(a:b) = idxLocal;
    end
end

function D = squaredDistanceRows(A, B)
    D = bsxfun(@plus, sum(A .^ 2, 2), sum(B .^ 2, 2)') - 2 * (A * B');
    D(D < 0) = 0;
end

function S = loadStructFile(fileName)
    fileName = expandUserPath(fileName);
    raw = load(fileName);
    S = firstStruct(raw);
end

function S = firstStruct(raw)
    preferred = {'out', 'outForSave', 'placement', 'exclusion'};
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
    error('acsMakeHeadpostExclusionFromPlacement:NoStructInFile', ...
        'Could not find a readable struct.');
end

function TR = ensureTri(value)
    if isa(value, 'triangulation')
        TR = value;
    elseif isstruct(value) && isfield(value, 'ConnectivityList') && ...
            isfield(value, 'Points')
        TR = triangulation(value.ConnectivityList, value.Points);
    elseif isstruct(value) && isfield(value, 'faces') && isfield(value, 'vertices')
        TR = triangulation(value.faces, value.vertices);
    else
        error('acsMakeHeadpostExclusionFromPlacement:BadTriangulation', ...
            'Expected a triangulation-like object.');
    end
end

function saveQcFigure(fig, fileName)
    try
        exportgraphics(fig, fileName, 'Resolution', 200);
    catch
        saveas(fig, fileName);
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

function fileName = getFileName(fileName)
    [~, stem, ext] = fileparts(char(fileName));
    fileName = [stem ext];
end

function stem = stripMatExtension(fileName)
    [~, stem, ext] = fileparts(char(fileName));
    if ~strcmpi(ext, '.mat')
        stem = [stem ext];
    end
end

function value = getOptionalField(S, fieldName, defaultValue)
    if isstruct(S) && isfield(S, fieldName) && ~isempty(S.(fieldName))
        value = S.(fieldName);
    else
        value = defaultValue;
    end
end

function value = getNestedOptionalField(S, fieldPath, defaultValue)
    value = S;
    for i = 1:numel(fieldPath)
        if ~isstruct(value) || ~isfield(value, fieldPath{i}) || ...
                isempty(value.(fieldPath{i}))
            value = defaultValue;
            return;
        end
        value = value.(fieldPath{i});
    end
end

function row = normalizeRow(row)
    row = double(row(:)');
    if numel(row) ~= 3
        row = [0 0 1];
        return;
    end
    n = norm(row);
    if n < eps || any(~isfinite(row))
        row = [0 0 1];
    else
        row = row ./ n;
    end
end

function value = percentileLocal(x, pct)
    x = sort(double(x(:)));
    x = x(isfinite(x));
    if isempty(x)
        value = NaN;
        return;
    end
    pct = max(0, min(100, double(pct)));
    pos = 1 + (numel(x) - 1) * pct / 100;
    lo = floor(pos);
    hi = ceil(pos);
    if lo == hi
        value = x(lo);
    else
        value = x(lo) + (x(hi) - x(lo)) * (pos - lo);
    end
end

function value = safeName(value)
    value = regexprep(char(value), '[^\w\-]+', '_');
    value = regexprep(value, '_+', '_');
    value = regexprep(value, '^_|_$', '');
    if isempty(value)
        value = 'headpost';
    end
end

function value = medianFinite(x)
    x = x(isfinite(x));
    if isempty(x)
        value = NaN;
    else
        value = median(x);
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
        if numel(fileName) == 1
            fileName = homeDir;
        elseif fileName(2) == filesep || fileName(2) == '/'
            fileName = fullfile(homeDir, fileName(3:end));
        end
    end
end

function printSummary(out)
    fprintf('\nHeadpost exclusion from finalized placement\n');
    fprintf('  object: %s\n', out.name);
    fprintf('  footprint mode: %s\n', out.footprintMode);
    if isfinite(out.postRadiusMm)
        fprintf('  post radius: %.3g mm\n', out.postRadiusMm);
    end
    fprintf('  margin: %.3g mm\n', out.marginMm);
    fprintf('  base perimeter points: %d\n', size(out.basePerimeterPrintMm, 1));
    fprintf('  output: %s\n', out.outputFile);
    if ~isempty(out.qcFigure)
        fprintf('  QC figure: %s\n', out.qcFigure);
    end
end
