function out = acsInspectHeadpostGeometry(meshFile, varargin)
% ACSINSPECTHEADPOSTGEOMETRY Inspect the primate headpost CAD mesh.
%
% out = acsInspectHeadpostGeometry() loads the default simplified headpost
% STL from capMaker/geometry, reports basic mesh statistics, and shows a
% four-panel orientation viewer.
%
% Coordinate convention expected for the CAD model:
%   +X: subject right
%   +Y: rostral
%   +Z: dorsal / post up
%
% Name-value options:
%   showFigures     : show the mesh viewer [true]
%   saveFigures     : save a PNG of the viewer [false]
%   outputDir       : figure output folder [<mesh folder>/qc]
%   displayMaxFaces : decimate only for display above this face count [50000]
%   originMode      : 'autoPostBase', 'stlZero', or 'manual' ['autoPostBase']
%   originMm        : manual local-frame origin shown by axes [[]]
%   axisLengthMm    : length of displayed local axes [[] = auto]
%   faceAlpha       : mesh transparency [0.90]
%   meshLighting    : 'flat', 'gouraud', or 'none' ['flat']
%   closeFigure     : close figure before returning [false]
%   verbose         : print summary [true]

    if nargin < 1
        meshFile = '';
    elseif isNameValueStart(meshFile)
        varargin = [{meshFile}, varargin];
        meshFile = '';
    end

    opts = parseInputs(varargin{:});
    if isempty(meshFile)
        meshFile = defaultHeadpostMeshFile();
    end
    meshFile = expandUserPath(char(meshFile));
    if exist(meshFile, 'file') ~= 2
        error('acsInspectHeadpostGeometry:MeshNotFound', ...
            'Headpost mesh file not found: %s', meshFile);
    end

    [TR, readInfo] = readStlTriangulation(meshFile);
    stats = meshStats(TR, meshFile);
    [originMm, originInfo] = resolveOrigin(TR, opts);
    convention = struct( ...
        'xPositive', '+X = subject right', ...
        'yPositive', '+Y = rostral', ...
        'zPositive', '+Z = dorsal / post up');

    fig = [];
    qcFile = '';
    if opts.showFigures || opts.saveFigures
        if isempty(opts.outputDir)
            opts.outputDir = fullfile(fileparts(meshFile), 'qc');
        end
        figVisible = 'off';
        if opts.showFigures
            figVisible = 'on';
        end
        fig = makeViewerFigure(TR, stats, meshFile, convention, ...
            originMm, originInfo, opts, figVisible);
        if opts.saveFigures
            ensureDir(opts.outputDir);
            qcFile = fullfile(opts.outputDir, ...
                [safeStem(meshFile) '_headpostGeometryQc.png']);
            saveQcFigure(fig, qcFile);
        end
        if opts.closeFigure && isgraphics(fig)
            close(fig);
            fig = [];
        end
    end

    out = struct();
    out.createdOn = char(datetime('now'));
    out.meshFile = meshFile;
    out.readInfo = readInfo;
    out.coordinateConvention = convention;
    out.originMm = originMm;
    out.originInfo = originInfo;
    out.stats = stats;
    out.qcFigure = qcFile;
    out.figure = fig;
    out.mesh = struct('TR', TR);

    if opts.verbose
        printSummary(out);
    end
end

function opts = parseInputs(varargin)
    p = inputParser;
    p.FunctionName = 'acsInspectHeadpostGeometry';
    addParameter(p, 'showFigures', true, @isBoolLike);
    addParameter(p, 'saveFigures', false, @isBoolLike);
    addParameter(p, 'outputDir', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'displayMaxFaces', 50000, @isPositiveScalar);
    addParameter(p, 'originMode', 'autoPostBase', @(x) ischar(x) || isstring(x));
    addParameter(p, 'originMm', [], @(x) isempty(x) || (isnumeric(x) && numel(x) == 3));
    addParameter(p, 'axisLengthMm', [], @(x) isempty(x) || isPositiveScalar(x));
    addParameter(p, 'faceAlpha', 0.90, @(x) isnumeric(x) && isscalar(x) && x >= 0 && x <= 1);
    addParameter(p, 'meshLighting', 'flat', @(x) ischar(x) || isstring(x));
    addParameter(p, 'closeFigure', false, @isBoolLike);
    addParameter(p, 'verbose', true, @isBoolLike);
    parse(p, varargin{:});

    opts = p.Results;
    opts.showFigures = logical(opts.showFigures);
    opts.saveFigures = logical(opts.saveFigures);
    opts.outputDir = expandUserPath(char(opts.outputDir));
    opts.displayMaxFaces = round(double(opts.displayMaxFaces));
    opts.originMode = normalizeOriginMode(opts.originMode);
    if ~isempty(opts.originMm)
        opts.originMm = double(opts.originMm(:)');
        opts.originMode = 'manual';
    end
    if ~isempty(opts.axisLengthMm)
        opts.axisLengthMm = double(opts.axisLengthMm);
    end
    opts.faceAlpha = double(opts.faceAlpha);
    opts.meshLighting = lower(strtrim(char(opts.meshLighting)));
    if ~any(strcmp(opts.meshLighting, {'flat', 'gouraud', 'none'}))
        error('acsInspectHeadpostGeometry:BadLighting', ...
            'meshLighting must be ''flat'', ''gouraud'', or ''none''.');
    end
    opts.closeFigure = logical(opts.closeFigure);
    opts.verbose = logical(opts.verbose);
end

function tf = isNameValueStart(value)
    tf = false;
    if ~(ischar(value) || (isstring(value) && isscalar(value)))
        return;
    end
    names = {'showFigures', 'saveFigures', 'outputDir', 'displayMaxFaces', ...
        'originMode', 'originMm', 'axisLengthMm', 'faceAlpha', 'meshLighting', ...
        'closeFigure', 'verbose'};
    tf = any(strcmpi(char(value), names));
end

function tf = isBoolLike(x)
    tf = (islogical(x) || isnumeric(x)) && isscalar(x);
end

function tf = isPositiveScalar(x)
    tf = isnumeric(x) && isscalar(x) && isfinite(x) && x > 0;
end

function mode = normalizeOriginMode(mode)
    mode = lower(strtrim(char(mode)));
    switch mode
        case {'autopostbase', 'auto', 'postbase', 'post-base'}
            mode = 'autoPostBase';
        case {'stlzero', 'zero', 'rawzero', 'cadzero'}
            mode = 'stlZero';
        case {'manual'}
            mode = 'manual';
        otherwise
            error('acsInspectHeadpostGeometry:BadOriginMode', ...
                'originMode must be ''autoPostBase'', ''stlZero'', or ''manual''.');
    end
end

function fileName = defaultHeadpostMeshFile()
    repoRoot = fileparts(fileparts(mfilename('fullpath')));
    fileName = fullfile(repoRoot, 'capMaker', 'geometry', ...
        'Primate Headpost Simplified.STL');
end

function [TR, readInfo] = readStlTriangulation(fileName)
    [~, ~, ext] = fileparts(fileName);
    if ~strcmpi(ext, '.stl')
        error('acsInspectHeadpostGeometry:UnsupportedMeshFormat', ...
            ['This first-pass inspector reads STL files. Export or pass the ', ...
             'simplified headpost STL instead of: %s'], fileName);
    end

    readInfo = struct('method', '', 'sourceFile', fileName);
    if exist('stlread', 'file') == 2
        try
            raw = stlread(fileName);
            [F, V] = facesVerticesFromStlread(raw);
            TR = triangulation(double(F), double(V));
            readInfo.method = 'stlread';
            return;
        catch
            try
                [F, V] = stlread(fileName);
                TR = triangulation(double(F), double(V));
                readInfo.method = 'stlread two-output';
                return;
            catch
            end
        end
    end

    [F, V, binaryInfo] = readBinaryStl(fileName);
    TR = triangulation(F, V);
    readInfo.method = 'local binary STL reader';
    readInfo.binaryInfo = binaryInfo;
end

function [F, V] = facesVerticesFromStlread(raw)
    if isa(raw, 'triangulation')
        F = raw.ConnectivityList;
        V = raw.Points;
    elseif isstruct(raw) && isfield(raw, 'ConnectivityList') && isfield(raw, 'Points')
        F = raw.ConnectivityList;
        V = raw.Points;
    elseif isstruct(raw) && isfield(raw, 'faces') && isfield(raw, 'vertices')
        F = raw.faces;
        V = raw.vertices;
    else
        error('acsInspectHeadpostGeometry:BadStlreadOutput', ...
            'Could not interpret stlread output.');
    end
end

function [F, V, info] = readBinaryStl(fileName)
    fileInfo = dir(fileName);
    fid = fopen(fileName, 'rb', 'ieee-le');
    if fid == -1
        error('acsInspectHeadpostGeometry:CannotOpenMesh', ...
            'Could not open STL file: %s', fileName);
    end
    cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>

    header = fread(fid, 80, 'uint8=>uint8');
    nTri = fread(fid, 1, 'uint32=>double');
    expectedBytes = 84 + 50 * nTri;
    if isempty(nTri) || expectedBytes > fileInfo.bytes
        error('acsInspectHeadpostGeometry:NotBinaryStl', ...
            ['Local fallback only supports binary STL. MATLAB stlread could ', ...
             'not read this file either: %s'], fileName);
    end

    Vraw = zeros(3 * nTri, 3);
    Fraw = reshape(1:(3 * nTri), 3, [])';
    for i = 1:nTri
        fread(fid, 3, 'float32=>double'); % normal
        verts = fread(fid, [3 3], 'float32=>double')';
        fread(fid, 1, 'uint16=>double'); % attribute byte count
        rows = (3 * (i - 1) + 1):(3 * i);
        Vraw(rows, :) = verts;
    end

    [V, ~, ic] = unique(Vraw, 'rows');
    F = reshape(ic(Fraw), size(Fraw));
    info = struct('triangleCountInFile', nTri, ...
        'headerText', char(header(:)'));
end

function stats = meshStats(TR, fileName)
    V = double(TR.Points);
    F = double(TR.ConnectivityList);
    boundsMin = min(V, [], 1);
    boundsMax = max(V, [], 1);
    range = boundsMax - boundsMin;
    edgeInfo = meshEdgeStats(F);

    stats = struct();
    stats.fileName = fileName;
    stats.fileBytes = dir(fileName).bytes;
    stats.vertexCount = size(V, 1);
    stats.faceCount = size(F, 1);
    stats.boundsMinMm = boundsMin;
    stats.boundsMaxMm = boundsMax;
    stats.rangeMm = range;
    stats.centroidMm = mean(V, 1);
    stats.surfaceAreaMm2 = surfaceArea(F, V);
    stats.signedVolumeMm3 = signedVolume(F, V);
    stats.absoluteVolumeMm3 = abs(stats.signedVolumeMm3);
    stats.edge = edgeInfo;
    stats.isClosedManifoldLike = edgeInfo.boundaryEdgeCount == 0 && ...
        edgeInfo.nonManifoldEdgeCount == 0;
end

function [originMm, info] = resolveOrigin(TR, opts)
    info = struct('mode', opts.originMode, 'method', '');
    switch opts.originMode
        case 'manual'
            originMm = opts.originMm;
            info.method = 'manual originMm';
        case 'stlZero'
            originMm = [0 0 0];
            info.method = 'raw STL coordinate zero';
        case 'autoPostBase'
            [originMm, info] = estimatePostBaseOrigin(TR);
        otherwise
            error('acsInspectHeadpostGeometry:BadOriginMode', ...
                'Unsupported originMode: %s', opts.originMode);
    end
end

function [originMm, info] = estimatePostBaseOrigin(TR)
    V = double(TR.Points);
    z = V(:, 3);
    zMin = min(z);
    zMax = max(z);
    zRange = max(zMax - zMin, eps);

    highThresh = zMin + 0.60 * zRange;
    highRows = z >= highThresh;
    if nnz(highRows) < max(20, round(0.01 * size(V, 1)))
        highThresh = percentileLocal(z, 80);
        highRows = z >= highThresh;
    end
    if nnz(highRows) < 3
        originMm = 0.5 * (min(V, [], 1) + max(V, [], 1));
        originMm(3) = zMin;
        info = struct('mode', 'autoPostBase', ...
            'method', 'fallback bbox center at minimum Z', ...
            'warning', 'Too few high-Z vertices to estimate post axis.');
        return;
    end

    centerXY = median(V(highRows, 1:2), 1);
    highDxy = sqrt(sum((V(highRows, 1:2) - centerXY) .^ 2, 2));
    postRadiusMm = max(percentileLocal(highDxy, 95), eps);
    centralRows = sqrt(sum((V(:, 1:2) - centerXY) .^ 2, 2)) <= ...
        1.25 * postRadiusMm;
    if nnz(centralRows) < 3
        zBase = zMin;
    else
        zBase = percentileLocal(z(centralRows), 1);
    end

    originMm = [centerXY zBase];
    info = struct();
    info.mode = 'autoPostBase';
    info.method = 'median high-Z post center plus lower central-column Z';
    info.highZThresholdMm = highThresh;
    info.highVertexCount = nnz(highRows);
    info.centralVertexCount = nnz(centralRows);
    info.postRadiusEstimateMm = postRadiusMm;
    info.stlZeroOffsetMm = originMm;
end

function edgeInfo = meshEdgeStats(F)
    edges = [F(:, [1 2]); F(:, [2 3]); F(:, [3 1])];
    edges = sort(edges, 2);
    [uniqueEdges, ~, ic] = unique(edges, 'rows');
    counts = accumarray(ic, 1);
    edgeInfo = struct();
    edgeInfo.uniqueEdgeCount = size(uniqueEdges, 1);
    edgeInfo.boundaryEdgeCount = nnz(counts == 1);
    edgeInfo.nonManifoldEdgeCount = nnz(counts > 2);
    edgeInfo.minFacesPerEdge = min(counts);
    edgeInfo.maxFacesPerEdge = max(counts);
end

function area = surfaceArea(F, V)
    A = V(F(:, 2), :) - V(F(:, 1), :);
    B = V(F(:, 3), :) - V(F(:, 1), :);
    C = cross(A, B, 2);
    area = sum(0.5 * sqrt(sum(C .^ 2, 2)));
end

function vol = signedVolume(F, V)
    V1 = V(F(:, 1), :);
    V2 = V(F(:, 2), :);
    V3 = V(F(:, 3), :);
    vol = sum(dot(V1, cross(V2, V3, 2), 2)) / 6;
end

function fig = makeViewerFigure(TR, stats, meshFile, convention, ...
        originMm, originInfo, opts, figVisible)
    [Fd, Vd] = displayMesh(TR, opts.displayMaxFaces);
    fig = figure('Name', 'Headpost CAD geometry inspection', ...
        'Color', 'w', 'Visible', figVisible, ...
        'Units', 'pixels', 'Position', [80 80 1500 900]);
    tl = tiledlayout(fig, 2, 2, 'Padding', 'compact', 'TileSpacing', 'compact');
    title(tl, sprintf('%s | %d faces | bounds [%.1f %.1f %.1f] mm', ...
        getFileName(meshFile), stats.faceCount, stats.rangeMm), ...
        'Interpreter', 'none', 'FontWeight', 'bold');

    ax = nexttile(tl, 1);
    drawMeshPanel(ax, Fd, Vd, opts, '3-D local CAD frame');
    drawLocalAxes(ax, originMm, axisLength(stats, opts), true);
    view(ax, 3);

    ax = nexttile(tl, 2);
    drawMeshPanel(ax, Fd, Vd, opts, 'Dorsal view: +X right, +Y rostral');
    drawLocalAxes(ax, originMm, axisLength(stats, opts), false);
    view(ax, [0 0 1]);

    ax = nexttile(tl, 3);
    drawMeshPanel(ax, Fd, Vd, opts, 'Right-side view: +Y rostral, +Z dorsal');
    drawLocalAxes(ax, originMm, axisLength(stats, opts), false);
    view(ax, [1 0 0]);

    ax = nexttile(tl, 4);
    axis(ax, 'off');
    text(ax, 0.02, 0.92, 'Headpost mesh summary', ...
        'FontWeight', 'bold', 'FontSize', 12, 'Units', 'normalized');
    lines = summaryLines(stats, convention, originMm, originInfo);
    text(ax, 0.02, 0.84, strjoin(lines, newline), ...
        'Interpreter', 'none', 'FontName', 'Consolas', ...
        'FontSize', 10, 'VerticalAlignment', 'top', 'Units', 'normalized');

    try
        rotate3d(fig, 'on');
    catch
    end
end

function [F, V] = displayMesh(TR, maxFaces)
    F = double(TR.ConnectivityList);
    V = double(TR.Points);
    if size(F, 1) > maxFaces && exist('reducepatch', 'file') == 2
        [F, V] = reducepatch(F, V, maxFaces);
    end
end

function drawMeshPanel(ax, F, V, opts, titleText)
    patch(ax, 'Faces', F, 'Vertices', V, ...
        'FaceColor', [0.80 0.83 0.88], ...
        'EdgeColor', 'none', ...
        'FaceAlpha', opts.faceAlpha);
    hold(ax, 'on');
    axis(ax, 'equal');
    grid(ax, 'on');
    xlabel(ax, '+X right (mm)');
    ylabel(ax, '+Y rostral (mm)');
    zlabel(ax, '+Z dorsal (mm)');
    title(ax, titleText, 'Interpreter', 'none');
    if ~strcmp(opts.meshLighting, 'none')
        camlight(ax, 'headlight');
        lighting(ax, opts.meshLighting);
    end
end

function len = axisLength(stats, opts)
    if ~isempty(opts.axisLengthMm)
        len = opts.axisLengthMm;
    else
        len = max(5, 0.25 * max(stats.rangeMm));
    end
end

function drawLocalAxes(ax, origin, len, labelOrigin)
    colors = [0.85 0.05 0.05; 0.05 0.55 0.15; 0.05 0.20 0.85];
    dirs = eye(3);
    labels = {'+X right', '+Y rostral', '+Z dorsal'};
    for i = 1:3
        q = quiver3(ax, origin(1), origin(2), origin(3), ...
            len * dirs(i, 1), len * dirs(i, 2), len * dirs(i, 3), ...
            0, 'LineWidth', 2.5, 'Color', colors(i, :), ...
            'MaxHeadSize', 0.5);
        try
            q.Annotation.LegendInformation.IconDisplayStyle = 'off';
        catch
        end
        tip = origin + len * dirs(i, :);
        text(ax, tip(1), tip(2), tip(3), [' ' labels{i}], ...
            'Color', colors(i, :), 'FontWeight', 'bold', ...
            'Interpreter', 'none');
    end
    scatter3(ax, origin(1), origin(2), origin(3), 60, ...
        [0 0 0], 'filled');
    if labelOrigin
        text(ax, origin(1), origin(2), origin(3), ' origin', ...
            'Color', [0 0 0], 'FontWeight', 'bold', ...
            'Interpreter', 'none');
    end
end

function lines = summaryLines(stats, convention, originMm, originInfo)
    closedText = 'no';
    if stats.isClosedManifoldLike
        closedText = 'yes';
    end
    lines = { ...
        sprintf('file size:          %.3f MB', stats.fileBytes / 1024 / 1024), ...
        sprintf('vertices/faces:     %d / %d', stats.vertexCount, stats.faceCount), ...
        sprintf('bounds min (mm):    [% .3f % .3f % .3f]', stats.boundsMinMm), ...
        sprintf('bounds max (mm):    [% .3f % .3f % .3f]', stats.boundsMaxMm), ...
        sprintf('range (mm):         [% .3f % .3f % .3f]', stats.rangeMm), ...
        sprintf('centroid (mm):      [% .3f % .3f % .3f]', stats.centroidMm), ...
        sprintf('surface area:       %.3f mm^2', stats.surfaceAreaMm2), ...
        sprintf('abs volume:         %.3f mm^3', stats.absoluteVolumeMm3), ...
        sprintf('closed/manifold-ish:%s', closedText), ...
        sprintf('boundary edges:     %d', stats.edge.boundaryEdgeCount), ...
        sprintf('nonmanifold edges:  %d', stats.edge.nonManifoldEdgeCount), ...
        sprintf('local origin (mm):  [% .3f % .3f % .3f]', originMm), ...
        sprintf('origin mode:        %s', originInfo.mode), ...
        sprintf('origin method:      %s', originInfo.method), ...
        '', ...
        convention.xPositive, ...
        convention.yPositive, ...
        convention.zPositive};
end

function saveQcFigure(fig, fileName)
    try
        exportgraphics(fig, fileName, 'Resolution', 160);
    catch
        saveas(fig, fileName);
    end
end

function printSummary(out)
    s = out.stats;
    fprintf('\nHeadpost geometry inspection\n');
    fprintf('  mesh: %s\n', out.meshFile);
    fprintf('  read method: %s\n', out.readInfo.method);
    fprintf('  vertices/faces: %d / %d\n', s.vertexCount, s.faceCount);
    fprintf('  bounds min mm: [% .3f % .3f % .3f]\n', s.boundsMinMm);
    fprintf('  bounds max mm: [% .3f % .3f % .3f]\n', s.boundsMaxMm);
    fprintf('  range mm:      [% .3f % .3f % .3f]\n', s.rangeMm);
    fprintf('  local origin mm: [% .3f % .3f % .3f] (%s)\n', ...
        out.originMm, out.originInfo.method);
    if isfield(out.originInfo, 'postRadiusEstimateMm')
        fprintf('  post radius estimate: %.3f mm\n', ...
            out.originInfo.postRadiusEstimateMm);
    end
    fprintf('  surface area: %.3f mm^2\n', s.surfaceAreaMm2);
    fprintf('  abs volume: %.3f mm^3\n', s.absoluteVolumeMm3);
    fprintf('  boundary/nonmanifold edges: %d / %d\n', ...
        s.edge.boundaryEdgeCount, s.edge.nonManifoldEdgeCount);
    if ~isempty(out.qcFigure)
        fprintf('  QC figure: %s\n', out.qcFigure);
    end
end

function ensureDir(pathIn)
    if ~isempty(pathIn) && exist(pathIn, 'dir') ~= 7
        mkdir(pathIn);
    end
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

function name = getFileName(fileName)
    [~, stem, ext] = fileparts(fileName);
    name = [stem ext];
end

function stem = safeStem(fileName)
    [~, stem] = fileparts(fileName);
    stem = regexprep(stem, '[^A-Za-z0-9_+-]', '_');
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
