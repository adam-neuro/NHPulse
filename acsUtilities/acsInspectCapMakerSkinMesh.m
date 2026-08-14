function out = acsInspectCapMakerSkinMesh(skinIn, varargin)
% ACSINSPECTCAPMAKERSKINMESH Inspect a capMaker/ROAST skin mesh cache.
%
% out = acsInspectCapMakerSkinMesh(cacheFile) opens one orbitable 3-D view
% of a saved skin mesh cache. Use this to inspect full-head warped skin
% surfaces, cropped printer-bed skin, or manufacturing skin caches without
% rerunning upstream steps.
%
% Name-value options:
%   meshStage        : 'auto', 'stableHead', 'fiducialHead', or 'skin' ['auto']
%   colorMode        : 'component', 'dent', 'roughness', 'normalZ', or 'height' ['component']
%   normalSmoothIterations : adjacency normal smoothing iterations [4]
%   dentMetric       : 'localLaplacian', 'radialEnvelope', or 'hybrid' ['localLaplacian']
%   dentRadiusMm     : neighborhood radius for local radial-envelope dents [8]
%   dentEnvelopePercentile : local radial envelope percentile [75]
%   dentMinDepthMm   : minimum inward dent depth [2]
%   dentNormalAngleDeg : normal roughness threshold for shallow creases [35]
%   dentLocalSmoothingIterations : local surface smoothing scale [3]
%   dentDirectionRadialWeight : radial contribution to repair direction [0.25]
%   dentMaxRings     : cap adjacency rings for dent neighborhood search [8]
%   alpha            : mesh opacity [0.85]
%   showNormals      : show sampled vertex normals [false]
%   normalStride     : stride for normal arrows [40]
%   displayMaxFaces  : decimate display mesh above this many faces [120000]
%   showFigures      : open the inspector figure [true]
%   verbose          : print component/normal summary [true]

    if nargin < 1 || isempty(skinIn)
        error('acsInspectCapMakerSkinMesh:MissingInput', ...
            'Provide a skin cache, triangulation, or struct containing TRskin.');
    end

    opts = parseInputs(varargin{:});
    [TR, source] = readSkinMesh(skinIn, opts);
    TRdisplay = decimateForDisplay(TR, opts.displayMaxFaces);
    diagnostics = meshDiagnostics(TRdisplay, opts);

    fig = [];
    if opts.showFigures
        fig = makeFigure(TRdisplay, diagnostics, source, opts);
    end

    out = struct();
    out.createdOn = char(datetime('now'));
    out.type = 'capMakerSkinMeshInspection';
    out.source = source;
    out.meshStats = meshStats(TR);
    out.displayMeshStats = meshStats(TRdisplay);
    out.diagnostics = diagnostics;
    if isgraphics(fig)
        out.figure = fig;
    end

    if opts.verbose
        printSummary(out);
    end
end

function opts = parseInputs(varargin)
    p = inputParser;
    p.FunctionName = 'acsInspectCapMakerSkinMesh';
    addParameter(p, 'meshStage', 'auto', @(x) ischar(x) || isstring(x));
    addParameter(p, 'colorMode', 'component', @(x) ischar(x) || isstring(x));
    addParameter(p, 'normalSmoothIterations', 4, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0);
    addParameter(p, 'dentMetric', 'localLaplacian', ...
        @(x) ischar(x) || isstring(x));
    addParameter(p, 'dentRadiusMm', 8, @isPositiveScalar);
    addParameter(p, 'dentEnvelopePercentile', 75, @isPercentScalar);
    addParameter(p, 'dentMinDepthMm', 2, @isNonnegativeScalar);
    addParameter(p, 'dentNormalAngleDeg', 35, @isNonnegativeScalar);
    addParameter(p, 'dentLocalSmoothingIterations', 3, ...
        @isNonnegativeScalar);
    addParameter(p, 'dentDirectionRadialWeight', 0.25, @isUnitScalar);
    addParameter(p, 'dentMaxRings', 8, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 1);
    addParameter(p, 'alpha', 0.85, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0 && x <= 1);
    addParameter(p, 'showNormals', false, @isBoolLike);
    addParameter(p, 'normalStride', 40, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 1);
    addParameter(p, 'displayMaxFaces', 120000, ...
        @(x) isempty(x) || (isnumeric(x) && isscalar(x) && isfinite(x) && x > 0));
    addParameter(p, 'showFigures', true, @isBoolLike);
    addParameter(p, 'verbose', true, @isBoolLike);
    parse(p, varargin{:});

    opts = p.Results;
    opts.meshStage = normalizeMeshStage(opts.meshStage);
    opts.colorMode = normalizeColorMode(opts.colorMode);
    opts.normalSmoothIterations = round(double(opts.normalSmoothIterations));
    opts.dentMetric = normalizeDentMetric(opts.dentMetric);
    opts.dentRadiusMm = double(opts.dentRadiusMm);
    opts.dentEnvelopePercentile = double(opts.dentEnvelopePercentile);
    opts.dentMinDepthMm = double(opts.dentMinDepthMm);
    opts.dentNormalAngleDeg = double(opts.dentNormalAngleDeg);
    opts.dentLocalSmoothingIterations = round(double( ...
        opts.dentLocalSmoothingIterations));
    opts.dentDirectionRadialWeight = double(opts.dentDirectionRadialWeight);
    opts.dentMaxRings = round(double(opts.dentMaxRings));
    opts.alpha = double(opts.alpha);
    opts.showNormals = logical(opts.showNormals);
    opts.normalStride = round(double(opts.normalStride));
    if ~isempty(opts.displayMaxFaces)
        opts.displayMaxFaces = round(double(opts.displayMaxFaces));
    end
    opts.showFigures = logical(opts.showFigures);
    opts.verbose = logical(opts.verbose);
end

function tf = isBoolLike(x)
    tf = (islogical(x) || isnumeric(x)) && isscalar(x);
end

function stage = normalizeMeshStage(stage)
    stage = lower(strtrim(char(stage)));
    switch regexprep(stage, '[\s_\-]+', '')
        case {'auto'}
            stage = 'auto';
        case {'stablehead', 'fullhead', 'precrop'}
            stage = 'stableHead';
        case {'fiducialhead', 'printfullhead'}
            stage = 'fiducialHead';
        case {'skin', 'trskin', 'cap', 'cropped'}
            stage = 'skin';
        otherwise
            error('acsInspectCapMakerSkinMesh:BadMeshStage', ...
                'meshStage must be auto, stableHead, fiducialHead, or skin.');
    end
end

function mode = normalizeColorMode(mode)
    mode = lower(strtrim(char(mode)));
    switch regexprep(mode, '[\s_\-]+', '')
        case {'component', 'components', 'connectedcomponent'}
            mode = 'component';
        case {'dent', 'dents', 'dentdepth', 'radialdent', 'dentrepair'}
            mode = 'dent';
        case {'roughness', 'normalroughness', 'normalangle'}
            mode = 'roughness';
        case {'normalz', 'znormal', 'axisz'}
            mode = 'normalZ';
        case {'height', 'z'}
            mode = 'height';
        otherwise
            error('acsInspectCapMakerSkinMesh:BadColorMode', ...
                ['colorMode must be component, dent, roughness, normalZ, ', ...
                 'or height.']);
    end
end

function tf = isPositiveScalar(x)
    tf = isnumeric(x) && isscalar(x) && isfinite(x) && x > 0;
end

function tf = isNonnegativeScalar(x)
    tf = isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0;
end

function tf = isPercentScalar(x)
    tf = isnumeric(x) && isscalar(x) && isfinite(x) && x > 0 && x <= 100;
end

function tf = isUnitScalar(x)
    tf = isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0 && x <= 1;
end

function mode = normalizeDentMetric(mode)
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
            error('acsInspectCapMakerSkinMesh:BadDentMetric', ...
                ['dentMetric must be ''localLaplacian'', ', ...
                 '''radialEnvelope'', or ''hybrid''.']);
    end
end

function [TR, source] = readSkinMesh(value, opts)
    source = struct('file', '', 'meshStage', opts.meshStage, 'variable', '');
    if isa(value, 'triangulation')
        TR = value;
        source.meshStage = 'triangulation';
        source.variable = 'input';
        return;
    end
    if isstruct(value)
        [TR, variableName] = selectMeshFromStruct(value, opts.meshStage);
        source.variable = variableName;
        return;
    end
    fileName = expandUserPath(char(value));
    if exist(fileName, 'file') ~= 2
        error('acsInspectCapMakerSkinMesh:MissingFile', ...
            'Skin cache not found: %s', fileName);
    end
    S = load(fileName);
    [TR, variableName] = selectMeshFromStruct(S, opts.meshStage);
    source.file = fileName;
    source.variable = variableName;
    source.meshStage = variableNameToStage(variableName);
end

function [TR, variableName] = selectMeshFromStruct(S, stage)
    switch stage
        case 'stableHead'
            candidates = {'TRstableHead', 'TRskin'};
        case 'fiducialHead'
            candidates = {'TRfiducialHead', 'TRstableHead', 'TRskin'};
        case 'skin'
            candidates = {'TRskin'};
        otherwise
            candidates = {'TRstableHead', 'TRfiducialHead', 'TRskin'};
    end
    for i = 1:numel(candidates)
        name = candidates{i};
        if isfield(S, name) && ~isempty(S.(name))
            TR = ensureTriangulation(S.(name));
            variableName = name;
            return;
        end
    end
    error('acsInspectCapMakerSkinMesh:NoSkinMesh', ...
        'Input did not contain TRstableHead, TRfiducialHead, or TRskin.');
end

function stage = variableNameToStage(name)
    switch char(name)
        case 'TRstableHead'
            stage = 'stableHead';
        case 'TRfiducialHead'
            stage = 'fiducialHead';
        otherwise
            stage = 'skin';
    end
end

function TR = ensureTriangulation(value)
    if isa(value, 'triangulation')
        TR = value;
    elseif isstruct(value) && isfield(value, 'Points') && ...
            isfield(value, 'ConnectivityList')
        TR = triangulation(double(value.ConnectivityList), double(value.Points));
    else
        error('acsInspectCapMakerSkinMesh:BadMesh', ...
            'Skin mesh must be a triangulation or struct with Points/ConnectivityList.');
    end
end

function TRout = decimateForDisplay(TRin, maxFaces)
    TRout = TRin;
    if isempty(maxFaces)
        return;
    end
    if size(TRin.ConnectivityList, 1) <= maxFaces
        return;
    end
    try
        [F, V] = reducepatch(TRin.ConnectivityList, TRin.Points, maxFaces);
        TRout = triangulation(double(F), double(V));
    catch
        TRout = TRin;
    end
end

function diagnostics = meshDiagnostics(TR, opts)
    V = double(TR.Points);
    F = double(TR.ConnectivityList);
    faceComponent = connectedFaceComponents(F);
    componentTable = componentStats(V, F, faceComponent);
    Nv = normalizeRows(vertexNormalSafe(TR));
    Nv = orientNormalsRadially(V, Nv);
    Ns = smoothNormalsByAdjacency(F, Nv, opts.normalSmoothIterations);
    roughnessDeg = vectorAnglesDeg(Nv, Ns);
    normalZ = Nv(:, 3);
    dent = dentDiagnosticsForInspector(F, V, roughnessDeg, opts);

    switch opts.colorMode
        case 'component'
            vertexColor = faceComponentToVertexColor(F, faceComponent, size(V, 1));
            colorLabel = 'connected component';
        case 'dent'
            vertexColor = dent.dentDepthMm;
            colorLabel = sprintf('%s inward dent depth (mm)', dent.metric);
        case 'roughness'
            vertexColor = roughnessDeg;
            colorLabel = 'raw-to-smoothed normal angle (deg)';
        case 'normalZ'
            vertexColor = normalZ;
            colorLabel = 'oriented normal Z';
        otherwise
            vertexColor = V(:, 3);
            colorLabel = 'Z (mm)';
    end

    diagnostics = struct();
    diagnostics.componentTable = componentTable;
    diagnostics.faceComponent = faceComponent;
    diagnostics.vertexNormal = Nv;
    diagnostics.smoothedVertexNormal = Ns;
    diagnostics.normalRoughnessDeg = roughnessDeg;
    diagnostics.normalZ = normalZ;
    diagnostics.dent = dent;
    diagnostics.dentDepthMm = dent.dentDepthMm;
    diagnostics.dentMask = dent.dentMask;
    diagnostics.vertexColor = vertexColor;
    diagnostics.colorLabel = colorLabel;
    diagnostics.colorMode = opts.colorMode;
end

function component = connectedFaceComponents(F)
    nF = size(F, 1);
    E = [F(:, [1 2]); F(:, [2 3]); F(:, [3 1])];
    E = sort(E, 2);
    faceId = repmat((1:nF)', 3, 1);
    [Euniq, ~, edgeGroup] = unique(E, 'rows');
    counts = accumarray(edgeGroup, 1, [size(Euniq, 1), 1]);
    shared = find(counts > 1);
    ii = [];
    jj = [];
    for k = shared(:)'
        faces = faceId(edgeGroup == k);
        faces = unique(faces(:));
        if numel(faces) < 2
            continue;
        end
        [a, b] = ndgrid(faces, faces);
        keep = a(:) ~= b(:);
        ii = [ii; a(keep)]; %#ok<AGROW>
        jj = [jj; b(keep)]; %#ok<AGROW>
    end
    if isempty(ii)
        component = (1:nF)';
        return;
    end
    G = graph(sparse(ii, jj, true(size(ii)), nF, nF));
    component = conncomp(G).';
end

function T = componentStats(V, F, faceComponent)
    ids = unique(faceComponent(:));
    rows = repmat(struct('component', 0, 'nFaces', 0, 'nVertices', 0, ...
        'minX', NaN, 'maxX', NaN, 'minY', NaN, 'maxY', NaN, ...
        'minZ', NaN, 'maxZ', NaN, 'centroidX', NaN, ...
        'centroidY', NaN, 'centroidZ', NaN), numel(ids), 1);
    for i = 1:numel(ids)
        useFaces = faceComponent == ids(i);
        vertices = unique(F(useFaces, :));
        P = V(vertices, :);
        rows(i).component = ids(i);
        rows(i).nFaces = nnz(useFaces);
        rows(i).nVertices = numel(vertices);
        rows(i).minX = min(P(:, 1));
        rows(i).maxX = max(P(:, 1));
        rows(i).minY = min(P(:, 2));
        rows(i).maxY = max(P(:, 2));
        rows(i).minZ = min(P(:, 3));
        rows(i).maxZ = max(P(:, 3));
        rows(i).centroidX = mean(P(:, 1));
        rows(i).centroidY = mean(P(:, 2));
        rows(i).centroidZ = mean(P(:, 3));
    end
    T = struct2table(rows);
    T = sortrows(T, 'nFaces', 'descend');
end

function C = faceComponentToVertexColor(F, faceComponent, nV)
    C = nan(nV, 1);
    for f = 1:size(F, 1)
        rows = F(f, :);
        unset = isnan(C(rows));
        C(rows(unset)) = faceComponent(f);
    end
    C(isnan(C)) = 0;
end

function N = vertexNormalSafe(TR)
    try
        N = vertexNormal(TR);
    catch
        V = double(TR.Points);
        F = double(TR.ConnectivityList);
        Fn = cross(V(F(:, 2), :) - V(F(:, 1), :), ...
            V(F(:, 3), :) - V(F(:, 1), :), 2);
        N = zeros(size(V));
        for f = 1:size(F, 1)
            N(F(f, :), :) = N(F(f, :), :) + Fn(f, :);
        end
    end
end

function N = orientNormalsRadially(V, N)
    center = median(V, 1);
    R = normalizeRows(V - center);
    flip = all(isfinite(R), 2) & all(isfinite(N), 2) & ...
        sum(N .* R, 2) < 0;
    N(flip, :) = -N(flip, :);
end

function N = smoothNormalsByAdjacency(F, N, nIter)
    E = unique(sort([F(:, [1 2]); F(:, [2 3]); F(:, [1 3])], 2), 'rows');
    rows = [E(:, 1); E(:, 2)];
    cols = [E(:, 2); E(:, 1)];
    A = sparse(rows, cols, ones(size(rows)), size(N, 1), size(N, 1));
    deg = full(sum(A, 2));
    deg(deg == 0) = 1;
    for it = 1:nIter
        neighbor = full(A * N) ./ deg;
        flip = sum(neighbor .* N, 2) < 0;
        neighbor(flip, :) = -neighbor(flip, :);
        N = normalizeRows(0.5 * N + 0.5 * neighbor);
    end
end

function angleDeg = vectorAnglesDeg(A, B)
    A = normalizeRows(A);
    B = normalizeRows(B);
    c = sum(A .* B, 2);
    c = max(-1, min(1, c));
    angleDeg = acosd(c);
end

function N = normalizeRows(N)
    len = sqrt(sum(N .^ 2, 2));
    len(~isfinite(len) | len <= eps) = 1;
    N = bsxfun(@rdivide, N, len);
end

function dent = dentDiagnosticsForInspector(F, V, normalRoughnessDeg, opts)
    n = size(V, 1);
    [A, deg, boundary] = meshAdjacency(F, n);
    neighbors = adjacencyListFromSparse(A, n);
    medEdge = medianEdgeLengthMm(F, V);
    if ~isfinite(medEdge) || medEdge <= 0
        medEdge = max(1, opts.dentRadiusMm);
    end
    nRings = max(1, ceil(opts.dentRadiusMm / medEdge));
    nRings = min(opts.dentMaxRings, nRings);
    center = median(V, 1);
    radialUnit = normalizeRows(bsxfun(@minus, V, center));
    Ns = smoothNormalsByAdjacency(F, orientNormalsRadially(V, ...
        vertexNormalSafe(triangulation(F, V))), ...
        max(1, min(8, nRings)));
    radialWeight = opts.dentDirectionRadialWeight;
    repairDirection = normalizeRows((1 - radialWeight) .* Ns + ...
        radialWeight .* radialUnit);
    badDir = sqrt(sum(repairDirection .^ 2, 2)) <= eps | ...
        ~all(isfinite(repairDirection), 2);
    repairDirection(badDir, :) = radialUnit(badDir, :);
    Vlocal = smoothPositionsByAdjacencySparse(V, A, deg, ...
        opts.dentLocalSmoothingIterations, 0.65);
    localDelta = Vlocal - V;
    localDentDepth = sum(localDelta .* repairDirection, 2);
    localDentDepth(~isfinite(localDentDepth)) = 0;
    localDentDepth = max(0, localDentDepth);
    radial = bsxfun(@minus, V, center);
    radialDistance = sqrt(sum(radial .^ 2, 2));
    if usesRadialEnvelopeDentMetric(opts.dentMetric)
        localEnvelope = localPercentileByRings(neighbors, radialDistance, ...
            nRings, opts.dentEnvelopePercentile);
        radialDentDepth = localEnvelope - radialDistance;
        radialDentDepth(~isfinite(radialDentDepth)) = 0;
        radialDentDepth = max(0, radialDentDepth);
    else
        localEnvelope = radialDistance;
        radialDentDepth = zeros(size(radialDistance));
    end
    switch opts.dentMetric
        case 'radialEnvelope'
            dentDepth = radialDentDepth;
        case 'hybrid'
            dentDepth = max(localDentDepth, min(radialDentDepth, ...
                localDentDepth + opts.dentMinDepthMm));
        otherwise
            dentDepth = localDentDepth;
    end
    strongDent = dentDepth >= opts.dentMinDepthMm;
    creaseDent = dentDepth >= 0.5 * opts.dentMinDepthMm & ...
        normalRoughnessDeg >= opts.dentNormalAngleDeg;
    dentMask = (strongDent | creaseDent) & all(isfinite(V), 2);
    worstRows = selectWorstRows(dentMask, dentDepth, 200);
    dent = struct( ...
        'centerMm', center, ...
        'metric', opts.dentMetric, ...
        'radiusMm', opts.dentRadiusMm, ...
        'neighborhoodRings', nRings, ...
        'medianEdgeLengthMm', medEdge, ...
        'envelopePercentile', opts.dentEnvelopePercentile, ...
        'minDentMm', opts.dentMinDepthMm, ...
        'normalAngleDeg', opts.dentNormalAngleDeg, ...
        'boundaryVertices', boundary, ...
        'radialDistanceMm', radialDistance, ...
        'localEnvelopeRadiusMm', localEnvelope, ...
        'radialEnvelopeDentDepthMm', radialDentDepth, ...
        'localLaplacianDentDepthMm', localDentDepth, ...
        'localSmoothedPointsMm', Vlocal, ...
        'repairDirection', repairDirection, ...
        'dentDepthMm', dentDepth, ...
        'dentMask', dentMask, ...
        'worstDentVertexRows', worstRows, ...
        'nDentVertices', nnz(dentMask), ...
        'p95DentDepthMm', percentileFinite(dentDepth, 95), ...
        'maxDentDepthMm', maxFinite(dentDepth));
end

function rows = selectWorstRows(mask, values, maxRows)
    rows = find(mask(:));
    if isempty(rows) || numel(rows) <= maxRows
        return;
    end
    [~, order] = sort(values(rows), 'descend');
    rows = rows(order(1:maxRows));
end

function tf = usesRadialEnvelopeDentMetric(metric)
    tf = any(strcmpi(metric, {'radialEnvelope', 'hybrid'}));
end

function [A, deg, boundaryVertices] = meshAdjacency(F, n)
    Eall = sort([F(:, [1 2]); F(:, [2 3]); F(:, [1 3])], 2);
    [E, ~, ic] = unique(Eall, 'rows');
    counts = accumarray(ic, 1);
    boundaryEdges = E(counts == 1, :);
    boundaryVertices = unique(boundaryEdges(:));
    A = sparse([E(:, 1); E(:, 2)], [E(:, 2); E(:, 1)], ...
        ones(2 * size(E, 1), 1), n, n);
    A = spones(A);
    deg = full(sum(A, 2));
    deg(deg == 0) = 1;
end

function neighbors = adjacencyListFromSparse(A, n)
    neighbors = cell(n, 1);
    [ii, jj] = find(A);
    for k = 1:numel(ii)
        neighbors{ii(k)}(end + 1, 1) = jj(k); %#ok<AGROW>
    end
end

function medEdge = medianEdgeLengthMm(F, V)
    E = unique(sort([F(:, [1 2]); F(:, [2 3]); F(:, [1 3])], 2), 'rows');
    if isempty(E)
        medEdge = NaN;
        return;
    end
    edgeLen = sqrt(sum((V(E(:, 1), :) - V(E(:, 2), :)) .^ 2, 2));
    medEdge = median(edgeLen(isfinite(edgeLen)));
end

function values = localPercentileByRings(neighbors, vertexValue, nRings, pct)
    n = numel(vertexValue);
    values = nan(n, 1);
    for i = 1:n
        rows = neighborRowsWithinRings(neighbors, i, nRings);
        x = vertexValue(rows);
        x = x(isfinite(x));
        if isempty(x)
            values(i) = vertexValue(i);
        else
            values(i) = percentileFinite(x, pct);
        end
    end
end

function Vout = smoothPositionsByAdjacencySparse(V, A, deg, nIter, blend)
    Vout = double(V);
    if nIter <= 0
        return;
    end
    blend = max(0, min(1, double(blend)));
    for it = 1:nIter
        neighbor = bsxfun(@rdivide, full(A * Vout), deg);
        Vout = (1 - blend) .* Vout + blend .* neighbor;
    end
end

function rows = neighborRowsWithinRings(neighbors, startRow, nRings)
    rows = startRow(:);
    frontier = rows;
    for r = 1:nRings
        newRows = gatherNeighborRows(neighbors, frontier);
        if isempty(newRows)
            break;
        end
        newRows = newRows(~ismember(newRows, rows));
        if isempty(newRows)
            break;
        end
        rows = unique([rows; newRows]); %#ok<AGROW>
        frontier = newRows;
    end
end

function rows = gatherNeighborRows(neighbors, sourceRows)
    buckets = cell(numel(sourceRows), 1);
    for i = 1:numel(sourceRows)
        buckets{i} = neighbors{sourceRows(i)};
    end
    if isempty(buckets)
        rows = [];
    else
        rows = unique(vertcat(buckets{:}));
    end
end

function fig = makeFigure(TR, diagnostics, source, opts)
    fig = figure('Name', 'CapMaker skin mesh inspector', ...
        'NumberTitle', 'off', 'Color', 'w', 'Units', 'normalized', ...
        'Position', [0.08 0.08 0.80 0.82]);
    ax = axes('Parent', fig, 'Units', 'normalized', ...
        'Position', [0.06 0.10 0.78 0.82]);
    hold(ax, 'on');
    h = patch(ax, 'Faces', TR.ConnectivityList, 'Vertices', TR.Points, ...
        'FaceVertexCData', diagnostics.vertexColor, ...
        'FaceColor', 'interp', 'FaceAlpha', opts.alpha, ...
        'EdgeColor', [0.25 0.25 0.25], 'EdgeAlpha', 0.08, ...
        'FaceLighting', 'flat', 'AmbientStrength', 0.60, ...
        'SpecularStrength', 0.05);
    cb = colorbar(ax);
    ylabel(cb, diagnostics.colorLabel, 'Interpreter', 'none');
    if strcmp(opts.colorMode, 'component')
        colormap(ax, lines(max(1, numel(unique(diagnostics.faceComponent)))));
    else
        colormap(ax, parula(256));
    end
    if strcmp(opts.colorMode, 'dent')
        dentHi = percentileFinite(diagnostics.dentDepthMm, 99);
        dentHi = max([opts.dentMinDepthMm, dentHi, 1]);
        caxis(ax, [0 dentHi]);
        drawDentMarkers(ax, TR.Points, diagnostics);
    end
    if opts.showNormals
        rows = 1:opts.normalStride:size(TR.Points, 1);
        P = TR.Points(rows, :);
        N = diagnostics.vertexNormal(rows, :);
        quiver3(ax, P(:, 1), P(:, 2), P(:, 3), ...
            5 * N(:, 1), 5 * N(:, 2), 5 * N(:, 3), ...
            0, 'Color', [0.05 0.05 0.05], 'LineWidth', 0.7);
    end
    title(ax, sprintf('Skin mesh: %s | %s', source.variable, opts.colorMode), ...
        'Interpreter', 'none');
    xlabel(ax, 'X mm');
    ylabel(ax, 'Y mm');
    zlabel(ax, 'Z mm');
    axis(ax, 'equal');
    axis(ax, 'vis3d');
    grid(ax, 'on');
    view(ax, 3);
    rotate3d(fig, 'on');
    camlight(ax, 'headlight');
    lighting(ax, 'flat');
    uicontrol(fig, 'Style', 'text', 'Units', 'normalized', ...
        'Position', [0.86 0.78 0.10 0.03], 'String', 'alpha', ...
        'BackgroundColor', 'w', 'HorizontalAlignment', 'left');
    uicontrol(fig, 'Style', 'slider', 'Units', 'normalized', ...
        'Position', [0.86 0.74 0.10 0.04], ...
        'Min', 0, 'Max', 1, 'Value', opts.alpha, ...
        'Callback', @(src, ~) set(h, 'FaceAlpha', get(src, 'Value')));
    addInfoText(fig, diagnostics);
end

function drawDentMarkers(ax, V, diagnostics)
    rows = find(diagnostics.dentMask(:));
    if isempty(rows)
        return;
    end
    if numel(rows) > 500
        [~, order] = sort(diagnostics.dentDepthMm(rows), 'descend');
        rows = rows(order(1:500));
    end
    scatter3(ax, V(rows, 1), V(rows, 2), V(rows, 3), ...
        24, [1.00 0.00 0.75], 'filled', ...
        'MarkerEdgeColor', [0.20 0.00 0.16], ...
        'LineWidth', 0.6);
end

function addInfoText(fig, diagnostics)
    T = diagnostics.componentTable;
    largestFaces = 0;
    if height(T) > 0
        largestFaces = T.nFaces(1);
    end
    msg = sprintf(['components: %d\nlargest faces: %d\n', ...
        'rough p95: %.1f deg\ndent metric: %s\ndent flags: %d\n', ...
        'dent p95/max: %.2f / %.2f mm'], ...
        height(T), largestFaces, percentileFinite( ...
        diagnostics.normalRoughnessDeg, 95), ...
        diagnostics.dent.metric, ...
        diagnostics.dent.nDentVertices, ...
        diagnostics.dent.p95DentDepthMm, diagnostics.dent.maxDentDepthMm);
    uicontrol(fig, 'Style', 'text', 'Units', 'normalized', ...
        'Position', [0.86 0.55 0.12 0.15], ...
        'String', msg, 'BackgroundColor', 'w', ...
        'HorizontalAlignment', 'left');
end

function stats = meshStats(TR)
    V = double(TR.Points);
    stats = struct('nVertices', size(V, 1), ...
        'nFaces', size(TR.ConnectivityList, 1), ...
        'boundsMin', min(V, [], 1), ...
        'boundsMax', max(V, [], 1), ...
        'centroid', mean(V, 1));
end

function printSummary(out)
    fprintf('\nCapMaker skin mesh inspection\n');
    if ~isempty(out.source.file)
        fprintf('  file: %s\n', out.source.file);
    end
    fprintf('  mesh variable: %s\n', out.source.variable);
    fprintf('  vertices/faces: %d / %d\n', ...
        out.meshStats.nVertices, out.meshStats.nFaces);
    fprintf('  display vertices/faces: %d / %d\n', ...
        out.displayMeshStats.nVertices, out.displayMeshStats.nFaces);
    fprintf('  connected components: %d\n', ...
        height(out.diagnostics.componentTable));
    roughMax = NaN;
    if ~isempty(out.diagnostics.normalRoughnessDeg)
        roughMax = max(out.diagnostics.normalRoughnessDeg);
    end
    fprintf('  normal roughness p95/max: %.2f / %.2f deg\n', ...
        percentileFinite(out.diagnostics.normalRoughnessDeg, 95), ...
        roughMax);
    fprintf('  dent metric: %s\n', out.diagnostics.dent.metric);
    fprintf('  dent flags: %d vertices, p95/max depth %.2f / %.2f mm\n', ...
        out.diagnostics.dent.nDentVertices, ...
        out.diagnostics.dent.p95DentDepthMm, ...
        out.diagnostics.dent.maxDentDepthMm);
end

function value = maxFinite(x)
    x = x(isfinite(x));
    if isempty(x)
        value = NaN;
    else
        value = max(x);
    end
end

function q = percentileFinite(x, p)
    x = x(isfinite(x));
    if isempty(x)
        q = NaN;
        return;
    end
    x = sort(x(:));
    idx = max(1, min(numel(x), round(1 + (p / 100) * (numel(x) - 1))));
    q = x(idx);
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
