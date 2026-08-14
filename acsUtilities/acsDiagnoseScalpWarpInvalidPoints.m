function out = acsDiagnoseScalpWarpInvalidPoints(warpReportIn, varargin)
% ACSDIAGNOSESCALPWARPINVALIDPOINTS Inspect why phone/trace points were rejected.
%
% out = acsDiagnoseScalpWarpInvalidPoints(warpReportFile) loads the saved
% acsWarpScalpSurfaceToPhoneScan / acsWarpScalpSurfaceToPolhemusTrace report
% and plots accepted and rejected trace points over the model surface. Data
% tips report each point's rejection reason, nearest-surface distance, signed
% outward offset, and nearest model vertex.
%
% Name-value options:
%   surfaceCacheFile  : skin cache used for the warp ['' = report source]
%   outputCacheFile   : warped skin cache ['' = report outputFile]
%   showWarpedWire    : overlay warped surface wireframe [true]
%   showExcluded      : show pre-excluded points if saved [true]
%   showOnlyRejected  : hide usable points [false]
%   focusTraceRows    : trace row(s) to inspect in a local neighborhood [[]]
%   focusNearestVertices : source-surface vertex row(s) to inspect [[]]
%   focusRadiusMm     : radius for local neighborhood diagnostic [12]
%   showNeighborhoodFigure : show local neighborhood figure when focused [true]
%   zeroOffsetToleranceMm : diagnostic tolerance for near-zero offsets [0.05]
%   displayMaxFaces   : maximum surface faces to draw [50000]
%   pointSize         : trace marker size [18]
%   showFigures       : show interactive figure [true]
%   verbose           : print rejection counts [true]

    if nargin < 1 || isempty(warpReportIn)
        error('acsDiagnoseScalpWarpInvalidPoints:MissingInput', ...
            'Provide a saved warp report MAT file or output struct.');
    end

    opts = parseInputs(varargin{:});
    report = readWarpReport(warpReportIn);
    opts = inferFiles(opts, report);
    sourceSurface = readSurfaceForTraceFrame(opts.surfaceCacheFile, ...
        traceFrame(report));
    warpedSurface = [];
    needsWarpedSurface = opts.showWarpedWire || hasFocusRequest(opts);
    if needsWarpedSurface && ~isempty(opts.outputCacheFile) && ...
            exist(opts.outputCacheFile, 'file') == 2
        warpedSurface = readSurfaceForTraceFrame(opts.outputCacheFile, ...
            traceFrame(report));
    end

    pointInfo = classifyTracePoints(report, opts);
    focus = makeFocusNeighborhood(sourceSurface, warpedSurface, pointInfo, opts);

    fig = [];
    localFig = [];
    if opts.showFigures
        fig = makeFigure(sourceSurface, warpedSurface, pointInfo, report, opts);
        if opts.showNeighborhoodFigure && focus.hasFocus
            localFig = makeNeighborhoodFigure(focus, pointInfo, opts);
        end
    end

    out = struct();
    out.createdOn = char(datetime('now'));
    out.type = 'scalpWarpInvalidPointDiagnostic';
    out.report = stripLargeFields(report);
    out.surfaceCacheFile = opts.surfaceCacheFile;
    out.outputCacheFile = opts.outputCacheFile;
    out.pointInfo = pointInfo;
    out.focus = focus;
    out.counts = pointInfo.counts;
    if isgraphics(fig)
        out.figure = fig;
    end
    if isgraphics(localFig)
        out.neighborhoodFigure = localFig;
    end

    if opts.verbose
        printSummary(out);
    end
end

function opts = parseInputs(varargin)
    p = inputParser;
    p.FunctionName = 'acsDiagnoseScalpWarpInvalidPoints';
    addParameter(p, 'surfaceCacheFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'outputCacheFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'showWarpedWire', true, @isBoolLike);
    addParameter(p, 'showExcluded', true, @isBoolLike);
    addParameter(p, 'showOnlyRejected', false, @isBoolLike);
    addParameter(p, 'focusTraceRows', [], @(x) isempty(x) || isnumeric(x));
    addParameter(p, 'focusNearestVertices', [], @(x) isempty(x) || isnumeric(x));
    addParameter(p, 'focusRadiusMm', 12, @isPositiveScalar);
    addParameter(p, 'showNeighborhoodFigure', true, @isBoolLike);
    addParameter(p, 'zeroOffsetToleranceMm', 0.05, @isNonnegativeScalar);
    addParameter(p, 'displayMaxFaces', 50000, @isPositiveScalar);
    addParameter(p, 'pointSize', 18, @isPositiveScalar);
    addParameter(p, 'showFigures', true, @isBoolLike);
    addParameter(p, 'verbose', true, @isBoolLike);
    parse(p, varargin{:});

    opts = p.Results;
    opts.surfaceCacheFile = expandUserPath(char(opts.surfaceCacheFile));
    opts.outputCacheFile = expandUserPath(char(opts.outputCacheFile));
    opts.showWarpedWire = logical(opts.showWarpedWire);
    opts.showExcluded = logical(opts.showExcluded);
    opts.showOnlyRejected = logical(opts.showOnlyRejected);
    opts.focusTraceRows = unique(round(double(opts.focusTraceRows(:))));
    opts.focusTraceRows = opts.focusTraceRows(isfinite(opts.focusTraceRows) & ...
        opts.focusTraceRows > 0);
    opts.focusNearestVertices = unique(round(double(opts.focusNearestVertices(:))));
    opts.focusNearestVertices = opts.focusNearestVertices( ...
        isfinite(opts.focusNearestVertices) & opts.focusNearestVertices > 0);
    opts.focusRadiusMm = double(opts.focusRadiusMm);
    opts.showNeighborhoodFigure = logical(opts.showNeighborhoodFigure);
    opts.zeroOffsetToleranceMm = double(opts.zeroOffsetToleranceMm);
    opts.displayMaxFaces = round(double(opts.displayMaxFaces));
    opts.pointSize = double(opts.pointSize);
    opts.showFigures = logical(opts.showFigures);
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

function tf = hasFocusRequest(opts)
    tf = ~isempty(opts.focusTraceRows) || ~isempty(opts.focusNearestVertices);
end

function report = readWarpReport(value)
    if isstruct(value)
        report = value;
        return;
    end
    fileName = expandUserPath(char(value));
    if exist(fileName, 'file') ~= 2
        error('acsDiagnoseScalpWarpInvalidPoints:ReportNotFound', ...
            'Warp report not found: %s', fileName);
    end
    raw = load(fileName);
    report = firstStruct(raw);
    report.reportFile = fileName;
end

function opts = inferFiles(opts, report)
    if isempty(opts.surfaceCacheFile)
        if isfield(report, 'source') && isstruct(report.source) && ...
                isfield(report.source, 'cacheFile') && ~isempty(report.source.cacheFile)
            opts.surfaceCacheFile = expandUserPath(char(report.source.cacheFile));
        elseif isfield(report, 'source') && isstruct(report.source) && ...
                isfield(report.source, 'file') && ~isempty(report.source.file)
            opts.surfaceCacheFile = expandUserPath(char(report.source.file));
        end
    end
    if isempty(opts.surfaceCacheFile) || exist(opts.surfaceCacheFile, 'file') ~= 2
        error('acsDiagnoseScalpWarpInvalidPoints:SurfaceNotFound', ...
            ['Could not resolve the source skin cache. Provide ', ...
             'surfaceCacheFile explicitly.']);
    end
    if isempty(opts.outputCacheFile) && isfield(report, 'outputFile') && ...
            ~isempty(report.outputFile)
        opts.outputCacheFile = expandUserPath(char(report.outputFile));
    end
end

function frame = traceFrame(report)
    frame = 'capMakerPrintMm';
    if isfield(report, 'trace') && isstruct(report.trace) && ...
            isfield(report.trace, 'coordinateFrame') && ...
            ~isempty(report.trace.coordinateFrame)
        frame = char(report.trace.coordinateFrame);
    elseif isfield(report, 'mesh') && isstruct(report.mesh) && ...
            isfield(report.mesh, 'fitCoordinateFrame') && ...
            ~isempty(report.mesh.fitCoordinateFrame)
        frame = char(report.mesh.fitCoordinateFrame);
    end
end

function TR = readSurfaceForTraceFrame(fileName, frame)
    S = load(fileName);
    frameKey = normalizeFrame(frame);
    if strcmp(frameKey, 'capmakerprecropworldmm')
        if isfield(S, 'TRstableHead') && ~isempty(S.TRstableHead)
            TR = ensureTriangulation(S.TRstableHead);
            return;
        end
        if isfield(S, 'meta') && isstruct(S.meta) && ...
                isfield(S.meta, 'stableHead') && ...
                isstruct(S.meta.stableHead) && ...
                isfield(S.meta.stableHead, 'TR') && ...
                ~isempty(S.meta.stableHead.TR)
            TR = ensureTriangulation(S.meta.stableHead.TR);
            return;
        end
    end
    if isfield(S, 'TRfiducialHead') && ~isempty(S.TRfiducialHead)
        TR = ensureTriangulation(S.TRfiducialHead);
    elseif isfield(S, 'TRskin') && ~isempty(S.TRskin)
        TR = ensureTriangulation(S.TRskin);
    elseif isfield(S, 'TRstableHead') && ~isempty(S.TRstableHead)
        TR = ensureTriangulation(S.TRstableHead);
    else
        error('acsDiagnoseScalpWarpInvalidPoints:NoSurfaceInCache', ...
            'Could not find a surface mesh in: %s', fileName);
    end
end

function pointInfo = classifyTracePoints(report, opts)
    if ~isfield(report, 'trace') || ~isstruct(report.trace) || ...
            ~isfield(report.trace, 'coordinatesMm') || ...
            isempty(report.trace.coordinatesMm)
        error('acsDiagnoseScalpWarpInvalidPoints:MissingTraceCoordinates', ...
            'Warp report does not contain trace.coordinatesMm.');
    end
    if ~isfield(report, 'warp') || ~isstruct(report.warp)
        error('acsDiagnoseScalpWarpInvalidPoints:MissingWarpInfo', ...
            'Warp report does not contain warp diagnostics.');
    end

    P = double(report.trace.coordinatesMm);
    n = size(P, 1);
    usable = false(n, 1);
    if isfield(report.warp, 'traceUsable') && ~isempty(report.warp.traceUsable)
        m = min(n, numel(report.warp.traceUsable));
        usable(1:m) = logical(report.warp.traceUsable(1:m));
    end
    coverageUsed = false(n, 1);
    if isfield(report.warp, 'traceCoverageUsed') && ...
            ~isempty(report.warp.traceCoverageUsed)
        m = min(n, numel(report.warp.traceCoverageUsed));
        coverageUsed(1:m) = logical(report.warp.traceCoverageUsed(1:m));
    end
    dist = nan(n, 1);
    if isfield(report.warp, 'traceNearestDistanceMm') && ...
            ~isempty(report.warp.traceNearestDistanceMm)
        m = min(n, numel(report.warp.traceNearestDistanceMm));
        dist(1:m) = double(report.warp.traceNearestDistanceMm(1:m));
    end
    signedOffset = nan(n, 1);
    if isfield(report.warp, 'traceSignedOffsetMm') && ...
            ~isempty(report.warp.traceSignedOffsetMm)
        m = min(n, numel(report.warp.traceSignedOffsetMm));
        signedOffset(1:m) = double(report.warp.traceSignedOffsetMm(1:m));
    end
    signedOffsetWarp = readTraceVector(report.warp, 'traceSignedOffsetWarpMm', n);
    signedOffsetNormal = readTraceVector(report.warp, 'traceSignedOffsetNormalMm', n);
    signedOffsetRadial = readTraceVector(report.warp, 'traceSignedOffsetRadialMm', n);
    nearestVertex = nan(n, 1);
    if isfield(report.warp, 'nearestTraceVertex') && ...
            ~isempty(report.warp.nearestTraceVertex)
        m = min(n, numel(report.warp.nearestTraceVertex));
        nearestVertex(1:m) = double(report.warp.nearestTraceVertex(1:m));
    end

    maxTraceDistanceMm = optionScalar(report, 'maxTraceDistanceMm', 35);
    reason = repmat({'usable'}, n, 1);
    nonfiniteDistance = ~usable & ~isfinite(dist);
    nonfiniteOffset = ~usable & isfinite(dist) & ~isfinite(signedOffset);
    tooFar = ~usable & isfinite(dist) & dist > maxTraceDistanceMm;
    nearZero = ~usable & isfinite(dist) & dist <= maxTraceDistanceMm & ...
        isfinite(signedOffset) & abs(signedOffset) <= opts.zeroOffsetToleranceMm;
    inward = ~usable & isfinite(dist) & dist <= maxTraceDistanceMm & ...
        isfinite(signedOffset) & signedOffset < -opts.zeroOffsetToleranceMm;
    coverageOnly = ~usable & coverageUsed;
    other = ~usable & ~(nonfiniteDistance | nonfiniteOffset | tooFar | ...
        nearZero | inward | coverageOnly);
    reason(nonfiniteDistance) = {'nonfinite nearest distance'};
    reason(nonfiniteOffset) = {'nonfinite signed offset'};
    reason(tooFar) = {'too far from model'};
    reason(nearZero) = {'near-zero offset'};
    reason(inward) = {'inward offset'};
    reason(coverageOnly & nearZero) = {'coverage-only near-zero'};
    reason(coverageOnly & inward) = {'coverage-only inward'};
    reason(coverageOnly & ~(nearZero | inward)) = {'coverage-only'};
    reason(other) = {'other rejected'};

    labels = defaultLabels(n, 'trace');
    if isfield(report.trace, 'labels') && numel(report.trace.labels) >= n
        labels = normalizeLabelCell(report.trace.labels);
        labels = labels(1:n);
    end

    excluded = zeros(0, 3);
    if isfield(report.trace, 'excludedCoordinatesMm') && ...
            ~isempty(report.trace.excludedCoordinatesMm)
        excluded = double(report.trace.excludedCoordinatesMm);
    end

    pointInfo = struct();
    pointInfo.coordinatesMm = P;
    pointInfo.labels = labels(:);
    pointInfo.usable = usable;
    pointInfo.coverageUsed = coverageUsed;
    pointInfo.reason = reason;
    pointInfo.nearestDistanceMm = dist;
    pointInfo.signedOffsetMm = signedOffset;
    pointInfo.signedOffsetWarpMm = signedOffsetWarp;
    pointInfo.signedOffsetNormalMm = signedOffsetNormal;
    pointInfo.signedOffsetRadialMm = signedOffsetRadial;
    pointInfo.nearestVertex = nearestVertex;
    pointInfo.maxTraceDistanceMm = maxTraceDistanceMm;
    pointInfo.zeroOffsetToleranceMm = opts.zeroOffsetToleranceMm;
    pointInfo.excludedCoordinatesMm = excluded;
    pointInfo.counts = countReasons(reason, excluded);
end

function value = readTraceVector(S, fieldName, n)
    value = nan(n, 1);
    if isstruct(S) && isfield(S, fieldName) && ~isempty(S.(fieldName))
        m = min(n, numel(S.(fieldName)));
        value(1:m) = double(S.(fieldName)(1:m));
    end
end

function value = optionScalar(report, fieldName, defaultValue)
    value = defaultValue;
    if isfield(report, 'options') && isstruct(report.options)
        if isfield(report.options, fieldName) && ...
                isnumeric(report.options.(fieldName)) && ...
                isscalar(report.options.(fieldName))
            value = double(report.options.(fieldName));
            return;
        end
        if isfield(report.options, 'phoneScanWarp') && ...
                isstruct(report.options.phoneScanWarp) && ...
                isfield(report.options.phoneScanWarp, fieldName) && ...
                isnumeric(report.options.phoneScanWarp.(fieldName)) && ...
                isscalar(report.options.phoneScanWarp.(fieldName))
            value = double(report.options.phoneScanWarp.(fieldName));
        end
    end
end

function counts = countReasons(reason, excluded)
    names = unique(reason(:), 'stable');
    counts = struct();
    counts.reason = names(:);
    counts.n = zeros(numel(names), 1);
    for i = 1:numel(names)
        counts.n(i) = nnz(strcmp(reason, names{i}));
    end
    counts.nPreExcluded = size(excluded, 1);
end

function focus = makeFocusNeighborhood(sourceSurface, warpedSurface, pointInfo, opts)
    focus = struct('hasFocus', false, ...
        'traceRows', [], 'nearestVertices', [], 'centerMm', [NaN NaN NaN], ...
        'focusTraceMm', zeros(0, 3), 'focusVertexMm', zeros(0, 3), ...
        'radiusMm', opts.focusRadiusMm, ...
        'localVertexRows', [], 'localTraceRows', [], ...
        'localRejectedRows', [], 'localUsableRows', [], ...
        'localReasonCounts', struct('reason', {{}}, 'n', []), ...
        'sourceTR', [], 'warpedTR', [], ...
        'deltaMm', zeros(0, 3), 'deltaMagnitudeMm', [], ...
        'focusVertexDeltaMagnitudeMm', [], ...
        'notes', '');
    if ~hasFocusRequest(opts)
        return;
    end

    V = double(sourceSurface.Points);
    F = double(sourceSurface.ConnectivityList);
    nTrace = size(pointInfo.coordinatesMm, 1);
    nVertex = size(V, 1);

    traceRows = opts.focusTraceRows(:);
    traceRows = traceRows(traceRows >= 1 & traceRows <= nTrace);
    nearestVertices = opts.focusNearestVertices(:);
    nearestVertices = nearestVertices(nearestVertices >= 1 & nearestVertices <= nVertex);
    if ~isempty(traceRows)
        tv = pointInfo.nearestVertex(traceRows);
        tv = tv(isfinite(tv) & tv >= 1 & tv <= nVertex);
        nearestVertices = unique([nearestVertices; round(tv(:))]);
    end

    centers = zeros(0, 3);
    if ~isempty(traceRows)
        centers = [centers; pointInfo.coordinatesMm(traceRows, :)]; %#ok<AGROW>
    end
    if ~isempty(nearestVertices)
        centers = [centers; V(nearestVertices, :)]; %#ok<AGROW>
    end
    centers = centers(all(isfinite(centers), 2), :);
    if isempty(centers)
        focus.notes = 'No valid trace rows or nearest vertices were supplied.';
        return;
    end

    center = mean(centers, 1);
    vertexDist = sqrt(sum((V - center) .^ 2, 2));
    localVertexRows = find(vertexDist <= opts.focusRadiusMm);
    if isempty(localVertexRows) && ~isempty(nearestVertices)
        localVertexRows = nearestVertices(:);
    end
    localFaceRows = find(any(ismember(F, localVertexRows), 2));
    if ~isempty(localFaceRows)
        localVertexRows = unique(F(localFaceRows, :));
    end
    localTraceRows = find(sqrt(sum((pointInfo.coordinatesMm - center) .^ 2, 2)) <= ...
        opts.focusRadiusMm);

    delta = zeros(nVertex, 3);
    deltaMag = nan(nVertex, 1);
    warpedTR = [];
    if ~isempty(warpedSurface) && ...
            size(warpedSurface.Points, 1) == nVertex && ...
            size(warpedSurface.ConnectivityList, 1) == size(F, 1)
        W = double(warpedSurface.Points);
        delta = W - V;
        deltaMag = sqrt(sum(delta .^ 2, 2));
        warpedTR = localTriangulation(W, F, localFaceRows);
    end

    localReasons = pointInfo.reason(localTraceRows);
    focus.hasFocus = true;
    focus.traceRows = traceRows(:);
    focus.nearestVertices = nearestVertices(:);
    focus.centerMm = center;
    focus.focusTraceMm = pointInfo.coordinatesMm(traceRows, :);
    focus.focusVertexMm = V(nearestVertices, :);
    focus.radiusMm = opts.focusRadiusMm;
    focus.localVertexRows = localVertexRows(:);
    focus.localTraceRows = localTraceRows(:);
    focus.localRejectedRows = localTraceRows(~pointInfo.usable(localTraceRows));
    focus.localUsableRows = localTraceRows(pointInfo.usable(localTraceRows));
    focus.localReasonCounts = countReasons(localReasons, zeros(0, 3));
    focus.sourceTR = localTriangulation(V, F, localFaceRows);
    focus.warpedTR = warpedTR;
    focus.deltaMm = delta(localVertexRows, :);
    focus.deltaMagnitudeMm = deltaMag(localVertexRows);
    focus.focusVertexDeltaMagnitudeMm = deltaMag(nearestVertices);
end

function TRlocal = localTriangulation(V, F, faceRows)
    TRlocal = [];
    if isempty(faceRows)
        return;
    end
    Fkeep = F(faceRows, :);
    used = unique(Fkeep(:));
    map = zeros(size(V, 1), 1);
    map(used) = 1:numel(used);
    TRlocal = triangulation(map(Fkeep), V(used, :));
end

function fig = makeFigure(sourceSurface, warpedSurface, pointInfo, report, opts)
    fig = figure('Name', 'Scalp warp invalid point diagnostic', ...
        'NumberTitle', 'off', 'Color', 'w', ...
        'Position', [90 70 1450 860]);
    ax = axes(fig, 'Position', [0.055 0.075 0.90 0.84]);
    hold(ax, 'on');

    TRdraw = decimateTri(sourceSurface, opts.displayMaxFaces);
    drawTri(ax, TRdraw, [0.72 0.74 0.78], 0.18);
    if ~isempty(warpedSurface)
        TRw = decimateTri(warpedSurface, opts.displayMaxFaces);
        drawTriWire(ax, TRw, [0.02 0.02 0.02], 0.18);
    end

    drawTraceGroups(ax, pointInfo, opts);
    title(ax, sprintf('Phone-scan warp point validity: %s', traceName(report)), ...
        'Interpreter', 'none', 'FontWeight', 'bold');
    axis(ax, 'equal');
    axis(ax, 'vis3d');
    grid(ax, 'on');
    xlabel(ax, 'X mm');
    ylabel(ax, 'Y mm');
    zlabel(ax, 'Z mm');
    view(ax, 3);
    rotate3d(fig, 'on');
    camlight(ax, 'headlight');
    lighting(ax, 'flat');
    legend(ax, 'Location', 'northeastoutside');
    installDataCursor(fig, pointInfo);
end

function fig = makeNeighborhoodFigure(focus, pointInfo, opts)
    fig = figure('Name', 'Scalp warp focused neighborhood diagnostic', ...
        'NumberTitle', 'off', 'Color', 'w', ...
        'Position', [120 90 1500 760]);
    tl = tiledlayout(fig, 1, 2, 'Padding', 'compact', 'TileSpacing', 'compact');

    ax1 = nexttile(tl, 1);
    hold(ax1, 'on');
    drawTri(ax1, focus.sourceTR, [0.72 0.74 0.78], 0.28);
    drawTriWire(ax1, focus.warpedTR, [0.02 0.02 0.02], 0.28);
    drawLocalTraceGroups(ax1, pointInfo, focus.localTraceRows, opts);
    drawFocusMarkers(ax1, focus, pointInfo);
    drawLocalDisplacementVectors(ax1, focus);
    title(ax1, 'Focused local geometry and trace validity', ...
        'Interpreter', 'none', 'FontWeight', 'bold');
    formatNeighborhoodAxes(ax1);

    ax2 = nexttile(tl, 2);
    hold(ax2, 'on');
    drawTriColoredLocal(ax2, focus.sourceTR, focus.deltaMagnitudeMm);
    drawLocalTraceGroups(ax2, pointInfo, focus.localTraceRows, opts);
    drawFocusMarkers(ax2, focus, pointInfo);
    cb = colorbar(ax2);
    cb.Label.String = 'Source-to-warped displacement (mm)';
    title(ax2, 'Local displacement magnitude', ...
        'Interpreter', 'none', 'FontWeight', 'bold');
    formatNeighborhoodAxes(ax2);

    title(tl, sprintf('Warp neighborhood around trace rows [%s], vertices [%s], radius %.1f mm', ...
        sprintf('%d ', focus.traceRows), sprintf('%d ', focus.nearestVertices), ...
        focus.radiusMm), 'Interpreter', 'none', 'FontWeight', 'bold');
    installDataCursor(fig, pointInfo);
end

function drawLocalTraceGroups(ax, pointInfo, rows, opts)
    if isempty(rows)
        return;
    end
    P = pointInfo.coordinatesMm;
    groups = { ...
        'usable', [0.85 0.10 0.10], 'o'; ...
        'coverage-only near-zero', [0.00 0.72 0.72], 'd'; ...
        'coverage-only inward', [0.00 0.38 0.95], 'd'; ...
        'coverage-only', [0.15 0.55 0.90], 'd'; ...
        'near-zero offset', [0.00 0.62 0.82], 'o'; ...
        'inward offset', [0.00 0.20 0.85], 'o'; ...
        'too far from model', [0.45 0.45 0.45], 'o'; ...
        'nonfinite nearest distance', [0.05 0.05 0.05], 'x'; ...
        'nonfinite signed offset', [0.25 0.05 0.50], 'x'; ...
        'other rejected', [0.05 0.05 0.05], 'o'};
    for i = 1:size(groups, 1)
        keep = rows(strcmp(pointInfo.reason(rows), groups{i, 1}));
        keep = keep(all(isfinite(P(keep, :)), 2));
        if isempty(keep)
            continue;
        end
        h = scatter3(ax, P(keep, 1), P(keep, 2), P(keep, 3), ...
            max(opts.pointSize, 26), groups{i, 2}, groups{i, 3}, ...
            'filled', 'MarkerEdgeColor', 'none', ...
            'DisplayName', groups{i, 1});
        h.UserData = struct('rows', keep);
    end
end

function drawFocusMarkers(ax, focus, pointInfo)
    if all(isfinite(focus.centerMm))
        scatter3(ax, focus.centerMm(1), focus.centerMm(2), focus.centerMm(3), ...
            95, [1.00 0.00 1.00], 'p', 'filled', ...
            'MarkerEdgeColor', [0.25 0.00 0.25], 'LineWidth', 1.2, ...
            'DisplayName', 'focus center');
    end
    if ~isempty(focus.focusVertexMm)
        P = focus.focusVertexMm;
        scatter3(ax, P(:, 1), P(:, 2), P(:, 3), ...
            100, [0.00 0.00 0.00], 's', 'filled', ...
            'MarkerEdgeColor', [1.00 1.00 1.00], 'LineWidth', 1.0, ...
            'DisplayName', 'focus nearest vertex');
    end
    rows = focus.traceRows(:);
    rows = rows(rows >= 1 & rows <= size(pointInfo.coordinatesMm, 1));
    if ~isempty(rows)
        P = pointInfo.coordinatesMm(rows, :);
        h = scatter3(ax, P(:, 1), P(:, 2), P(:, 3), ...
            115, [1.00 0.00 1.00], 'd', 'filled', ...
            'MarkerEdgeColor', [0.20 0.00 0.20], 'LineWidth', 1.4, ...
            'DisplayName', 'focus trace row');
        h.UserData = struct('rows', rows);
    end
end

function drawLocalDisplacementVectors(ax, focus)
    if isempty(focus.localVertexRows) || isempty(focus.deltaMm)
        return;
    end
    TR = focus.sourceTR;
    if isempty(TR)
        return;
    end
    Vlocal = double(TR.Points);
    Dlocal = focus.deltaMm;
    if size(Dlocal, 1) ~= size(Vlocal, 1)
        return;
    end
    step = max(1, ceil(size(Vlocal, 1) / 160));
    rows = 1:step:size(Vlocal, 1);
    quiver3(ax, Vlocal(rows, 1), Vlocal(rows, 2), Vlocal(rows, 3), ...
        Dlocal(rows, 1), Dlocal(rows, 2), Dlocal(rows, 3), ...
        0, 'Color', [0.05 0.30 0.95], 'LineWidth', 0.75, ...
        'DisplayName', 'source-to-warp vector');
end

function drawTriColoredLocal(ax, TR, values)
    if isempty(TR)
        return;
    end
    values = double(values(:));
    if numel(values) ~= size(TR.Points, 1)
        values = zeros(size(TR.Points, 1), 1);
    end
    patch(ax, 'Faces', TR.ConnectivityList, 'Vertices', TR.Points, ...
        'FaceVertexCData', values, 'FaceColor', 'interp', ...
        'FaceAlpha', 1.0, 'EdgeColor', 'none', ...
        'FaceLighting', 'flat', 'AmbientStrength', 0.85, ...
        'DiffuseStrength', 0.25, 'SpecularStrength', 0, ...
        'HandleVisibility', 'off');
    colormap(ax, parula(256));
end

function formatNeighborhoodAxes(ax)
    axis(ax, 'equal');
    axis(ax, 'vis3d');
    grid(ax, 'on');
    xlabel(ax, 'X mm');
    ylabel(ax, 'Y mm');
    zlabel(ax, 'Z mm');
    view(ax, 3);
    camlight(ax, 'headlight');
    lighting(ax, 'flat');
end

function drawTraceGroups(ax, pointInfo, opts)
    P = pointInfo.coordinatesMm;
    reason = pointInfo.reason;
    groups = { ...
        'usable', [0.85 0.10 0.10], 'o'; ...
        'coverage-only near-zero', [0.00 0.72 0.72], 'd'; ...
        'coverage-only inward', [0.00 0.38 0.95], 'd'; ...
        'coverage-only', [0.15 0.55 0.90], 'd'; ...
        'near-zero offset', [0.00 0.62 0.82], 'o'; ...
        'inward offset', [0.00 0.20 0.85], 'o'; ...
        'too far from model', [0.45 0.45 0.45], 'o'; ...
        'nonfinite nearest distance', [0.05 0.05 0.05], 'x'; ...
        'nonfinite signed offset', [0.25 0.05 0.50], 'x'; ...
        'other rejected', [0.05 0.05 0.05], 'o'};
    for i = 1:size(groups, 1)
        if opts.showOnlyRejected && strcmp(groups{i, 1}, 'usable')
            continue;
        end
        rows = find(strcmp(reason, groups{i, 1}) & all(isfinite(P), 2));
        if isempty(rows)
            continue;
        end
        h = scatter3(ax, P(rows, 1), P(rows, 2), P(rows, 3), ...
            opts.pointSize, groups{i, 2}, groups{i, 3}, 'filled', ...
            'MarkerEdgeColor', 'none', 'DisplayName', groups{i, 1});
        h.UserData = struct('rows', rows);
    end
    if opts.showExcluded && ~isempty(pointInfo.excludedCoordinatesMm)
        E = pointInfo.excludedCoordinatesMm;
        E = E(all(isfinite(E), 2), :);
        if ~isempty(E)
            h = scatter3(ax, E(:, 1), E(:, 2), E(:, 3), ...
                opts.pointSize, [1.00 0.55 0.05], 'o', 'filled', ...
                'MarkerEdgeColor', 'none', 'DisplayName', 'pre-excluded');
            h.UserData = struct('rows', [], 'preExcluded', true);
        end
    end
end

function installDataCursor(fig, pointInfo)
    try
        dcm = datacursormode(fig);
        dcm.UpdateFcn = @(~, evt) dataTipText(evt, pointInfo);
    catch
        % Datacursormode is optional; the plot is still useful without it.
    end
end

function txt = dataTipText(evt, pointInfo)
    pos = evt.Position;
    target = evt.Target;
    rows = [];
    isPreExcluded = false;
    if isprop(target, 'UserData') && isstruct(target.UserData)
        if isfield(target.UserData, 'preExcluded')
            isPreExcluded = logical(target.UserData.preExcluded);
        end
        if isfield(target.UserData, 'rows')
            rows = target.UserData.rows;
        end
    end
    if isPreExcluded
        txt = { ...
            'Reason: pre-excluded before warp', ...
            sprintf('X: %.3f', pos(1)), ...
            sprintf('Y: %.3f', pos(2)), ...
            sprintf('Z: %.3f', pos(3))};
        return;
    end
    if isempty(rows)
        P = pointInfo.coordinatesMm;
        rows = (1:size(P, 1))';
    else
        P = pointInfo.coordinatesMm(rows, :);
    end
    [~, local] = min(sum((P - pos) .^ 2, 2));
    row = rows(local);
    txt = { ...
        sprintf('Row: %d', row), ...
        sprintf('Label: %s', pointInfo.labels{row}), ...
        sprintf('Reason: %s', pointInfo.reason{row}), ...
        sprintf('Nearest dist: %.3f mm', pointInfo.nearestDistanceMm(row)), ...
        sprintf('Signed offset: %.3f mm', pointInfo.signedOffsetMm(row)), ...
        sprintf('Warp offset: %.3f mm', pointInfo.signedOffsetWarpMm(row)), ...
        sprintf('Normal offset: %.3f mm', pointInfo.signedOffsetNormalMm(row)), ...
        sprintf('Radial offset: %.3f mm', pointInfo.signedOffsetRadialMm(row)), ...
        sprintf('Nearest vertex: %.0f', pointInfo.nearestVertex(row)), ...
        sprintf('X: %.3f', pointInfo.coordinatesMm(row, 1)), ...
        sprintf('Y: %.3f', pointInfo.coordinatesMm(row, 2)), ...
        sprintf('Z: %.3f', pointInfo.coordinatesMm(row, 3))};
end

function drawTri(ax, TR, color, alphaValue)
    if isempty(TR)
        return;
    end
    patch(ax, 'Faces', TR.ConnectivityList, 'Vertices', TR.Points, ...
        'FaceColor', color, 'FaceAlpha', alphaValue, ...
        'EdgeColor', 'none', 'FaceLighting', 'flat', ...
        'AmbientStrength', 0.82, 'DiffuseStrength', 0.25, ...
        'SpecularStrength', 0, 'HandleVisibility', 'off');
end

function drawTriWire(ax, TR, color, alphaValue)
    if isempty(TR)
        return;
    end
    h = patch(ax, 'Faces', TR.ConnectivityList, 'Vertices', TR.Points, ...
        'FaceColor', 'none', 'EdgeColor', color, ...
        'LineWidth', 0.25, 'DisplayName', 'warped surface wire', ...
        'HandleVisibility', 'off');
    try
        h.EdgeAlpha = alphaValue;
    catch
    end
end

function TRout = decimateTri(TR, maxFaces)
    TRout = TR;
    F = double(TR.ConnectivityList);
    V = double(TR.Points);
    if isempty(F) || size(F, 1) <= maxFaces
        return;
    end
    keepFaces = unique(round(linspace(1, size(F, 1), maxFaces)));
    Fkeep = F(keepFaces, :);
    used = unique(Fkeep(:));
    map = zeros(size(V, 1), 1);
    map(used) = 1:numel(used);
    TRout = triangulation(map(Fkeep), V(used, :));
end

function TR = ensureTriangulation(value)
    if isa(value, 'triangulation')
        TR = value;
    elseif isstruct(value) && isfield(value, 'ConnectivityList') && ...
            isfield(value, 'Points')
        TR = triangulation(double(value.ConnectivityList), double(value.Points));
    else
        TR = [];
    end
end

function name = traceName(report)
    name = 'trace';
    if isfield(report, 'trace') && isstruct(report.trace) && ...
            isfield(report.trace, 'name') && ~isempty(report.trace.name)
        name = char(report.trace.name);
    end
end

function printSummary(out)
    fprintf('\nScalp warp invalid-point diagnostic\n');
    fprintf('  source surface: %s\n', out.surfaceCacheFile);
    fprintf('  warped surface: %s\n', out.outputCacheFile);
    fprintf('  trace points: %d\n', numel(out.pointInfo.reason));
    for i = 1:numel(out.counts.reason)
        fprintf('    %-28s %d\n', out.counts.reason{i}, out.counts.n(i));
    end
    if out.counts.nPreExcluded > 0
        fprintf('    %-28s %d\n', 'pre-excluded before warp', ...
            out.counts.nPreExcluded);
    end
    fprintf('  maxTraceDistanceMm: %.3g\n\n', ...
        out.pointInfo.maxTraceDistanceMm);
end

function labels = defaultLabels(n, prefix)
    labels = cell(n, 1);
    for i = 1:n
        labels{i} = sprintf('%s_%04d', prefix, i);
    end
end

function labels = normalizeLabelCell(value)
    if isstring(value)
        value = cellstr(value(:));
    elseif ischar(value)
        value = {value};
    end
    labels = cell(numel(value), 1);
    for i = 1:numel(value)
        labels{i} = char(value{i});
    end
end

function S = firstStruct(raw)
    preferred = {'outForSave', 'out', 'outSaved'};
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
    error('acsDiagnoseScalpWarpInvalidPoints:NoStruct', ...
        'MAT file does not contain a readable struct.');
end

function out = stripLargeFields(report)
    out = report;
    if isfield(out, 'trace') && isstruct(out.trace) && ...
            isfield(out.trace, 'coordinatesMm')
        out.trace = rmfield(out.trace, 'coordinatesMm');
    end
end

function frame = normalizeFrame(frame)
    frame = lower(regexprep(strtrim(char(frame)), '[\s_\-]+', ''));
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
        fileName = fullfile(homeDir, fileName(2:end));
    end
end
