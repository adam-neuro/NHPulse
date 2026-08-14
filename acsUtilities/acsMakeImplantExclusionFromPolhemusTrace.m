function out = acsMakeImplantExclusionFromPolhemusTrace(traceIn, surfaceSource, varargin)
% ACSMAKEIMPLANTEXCLUSIONFROMPOLHEMUSTRACE Build cap keepout zones from Polhemus traces.
%
% out = acsMakeImplantExclusionFromPolhemusTrace(headpostTraceQc) reads the
% registered trace points and mesh source from an acsVisualizePolhemusTraceOnHead
% output. Trace points are projected to the scalp mesh, converted to a buffered
% projected footprint, and saved as a manufacturing exclusion product.
%
% The traced object does not need to lie on the model surface. By default the
% registered trace is first reconciled from its source skin-cache frame into
% the target cap/manufacturing skin-cache frame. The cap surface is then used
% only to assign a local printable Z coordinate for QC/manufacturing geometry.
%
% Name-value options:
%   objectName        : trace/object name to use ['headpost']
%   marginMm          : no-print buffer around projected footprint [5]
%   boundaryShrink    : boundary shrink factor for footprint [0.75]
%   outputFile        : saved MAT exclusion file ['']
%   outputTag         : file/report tag ['headpostExclusion']
%   projectionMode    : 'traceXY', 'auto', or 'nearest3d' ['traceXY']
%   frameTransformMode: 'auto', 'always', or 'never' ['auto']
%   force             : overwrite existing output [false]
%   showFigures       : show QC figure [false]
%   saveFigures       : save QC figure [false]
%   verbose           : print summary [true]

    if nargin < 1 || isempty(traceIn)
        error('acsMakeImplantExclusionFromPolhemusTrace:MissingInput', ...
            'Provide a Polhemus trace QC or registration output.');
    end
    if nargin < 2
        surfaceSource = [];
    elseif isNameValueStart(surfaceSource)
        varargin = [{surfaceSource}, varargin];
        surfaceSource = [];
    end

    opts = parseInputs(varargin{:});
    addLocalDependencies();

    trace = readTrace(traceIn, opts);
    if isempty(trace.coordinatesMm)
        error('acsMakeImplantExclusionFromPolhemusTrace:NoTracePoints', ...
            'No trace points were found for objectName "%s".', opts.objectName);
    end

    if isempty(surfaceSource)
        surfaceSource = traceIn;
    end
    [TRskin, source] = readSkinMesh(surfaceSource);
    opts = resolveOutputFile(source, trace, opts);
    if exist(opts.outputFile, 'file') == 2 && ~opts.force
        S = load(opts.outputFile);
        out = firstStruct(S);
        if opts.verbose
            fprintf('Implant exclusion already exists; reusing %s\n', opts.outputFile);
        end
        return;
    end

    V = double(TRskin.Points);
    [trace, frameInfo] = reconcileTraceToSurfaceFrame(trace, source, V, opts);
    [projectedMm, nearestVertex, projectionDistance, projectionInfo] = ...
        projectTraceToSurfaceFootprint(V, trace.coordinatesMm, opts);
    [footprintPoly, keepoutPoly] = makeFootprintPolys(projectedMm(:, 1:2), opts);
    border = polyBoundary3(keepoutPoly, projectedMm, TRskin);

    fig = [];
    qcFile = '';
    if opts.showFigures || opts.saveFigures
        figVisible = 'off';
        if opts.showFigures
            figVisible = 'on';
        end
        fig = makeQcFigure(TRskin, trace, projectedMm, footprintPoly, ...
            keepoutPoly, border, source, opts, figVisible);
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
    out.method = 'cap surface projection with buffered projected footprint';
    out.projectionMethod = projectionInfo.method;
    out.projectionInfo = projectionInfo;
    out.frameTransformInfo = frameInfo;
    out.marginMm = opts.marginMm;
    out.trace = trace;
    out.surfaceSource = source;
    out.traceCoordinatesMm = trace.coordinatesMm;
    out.projectedCoordinatesMm = projectedMm;
    out.coordinateFrame = 'capMakerPrintMm';
    out.pointCoordinateFrames = struct( ...
        'rawTraceCoordinatesMm', frameInfo.inputFrame, ...
        'traceCoordinatesMm', 'capMakerPrintMm', ...
        'projectedCoordinatesMm', 'capMakerPrintMm', ...
        'keepoutBoundaryMm', 'capMakerPrintMm');
    out.rawTraceCoordinatesMm = frameInfo.inputCoordinatesMm;
    out.nearestVertex = nearestVertex(:);
    out.projectionDistanceMm = projectionDistance(:);
    out.projectionDistanceSummaryMm = struct( ...
        'median', medianFinite(projectionDistance), ...
        'p95', percentileLocal(projectionDistance, 95), ...
        'max', max(projectionDistance));
    out.footprintPoly = footprintPoly;
    out.keepoutPoly = keepoutPoly;
    out.railExclusionPolys = {keepoutPoly};
    out.keepoutBoundaryMm = border;
    out.keepoutBoundaryProjectionMethod = ...
        'top print-Z ray through triangulated cap surface';
    out.keepoutPolyX = border(:, 1);
    out.keepoutPolyY = border(:, 2);
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
    p.FunctionName = 'acsMakeImplantExclusionFromPolhemusTrace';
    addParameter(p, 'objectName', 'headpost', @(x) ischar(x) || isstring(x));
    addParameter(p, 'marginMm', 5, @isNonnegativeScalar);
    addParameter(p, 'boundaryShrink', 0.75, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0 && x <= 1);
    addParameter(p, 'outputFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'outputTag', 'headpostExclusion', @(x) ischar(x) || isstring(x));
    addParameter(p, 'projectionMode', 'traceXY', @(x) ischar(x) || isstring(x));
    addParameter(p, 'frameTransformMode', 'auto', @(x) ischar(x) || isstring(x));
    addParameter(p, 'force', false, @isBoolLike);
    addParameter(p, 'showFigures', false, @isBoolLike);
    addParameter(p, 'saveFigures', false, @isBoolLike);
    addParameter(p, 'verbose', true, @isBoolLike);
    parse(p, varargin{:});

    opts = p.Results;
    opts.objectName = char(opts.objectName);
    opts.marginMm = double(opts.marginMm);
    opts.boundaryShrink = double(opts.boundaryShrink);
    opts.outputFile = expandUserPath(char(opts.outputFile));
    opts.outputTag = safeName(char(opts.outputTag));
    opts.projectionMode = normalizeProjectionMode(opts.projectionMode);
    opts.frameTransformMode = normalizeFrameTransformMode(opts.frameTransformMode);
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
        'boundaryShrink', 'outputFile', 'outputTag', ...
        'projectionMode', 'frameTransformMode', 'force'}));
end

function value = normalizeProjectionMode(value)
    value = lower(strtrim(char(value)));
    switch value
        case {'tracexy', 'trace', 'xy', 'direct'}
            value = 'traceXY';
        case {'auto', 'fallback'}
            value = 'auto';
        case {'nearest3d', 'nearest', 'mesh', 'vertex'}
            value = 'nearest3d';
        otherwise
            error('acsMakeImplantExclusionFromPolhemusTrace:BadProjectionMode', ...
                'projectionMode must be ''traceXY'', ''auto'', or ''nearest3d''.');
    end
end

function value = normalizeFrameTransformMode(value)
    value = lower(strtrim(char(value)));
    switch value
        case {'auto', 'choose'}
            value = 'auto';
        case {'always', 'on', 'transform'}
            value = 'always';
        case {'never', 'off', 'none', 'raw'}
            value = 'never';
        otherwise
            error('acsMakeImplantExclusionFromPolhemusTrace:BadFrameTransformMode', ...
                'frameTransformMode must be ''auto'', ''always'', or ''never''.');
    end
end

function tf = isBoolLike(x)
    tf = (islogical(x) || isnumeric(x)) && isscalar(x);
end

function tf = isNonnegativeScalar(x)
    tf = isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0;
end

function addLocalDependencies()
    repoRoot = fileparts(fileparts(mfilename('fullpath')));
    addpath(repoRoot);
    capCore = fullfile(repoRoot, 'capMaker', 'core');
    if exist(capCore, 'dir') == 7
        addpath(capCore);
    end
end

function trace = readTrace(value, opts)
    trace = struct('name', opts.objectName, 'coordinatesMm', zeros(0, 3), ...
        'labels', {{}}, 'rows', [], 'source', struct());
    if ischar(value) || isstring(value)
        S = loadStructFile(char(value));
        trace = readTrace(S, opts);
        return;
    end
    if isstruct(value) && isfield(value, 'traceSets') && ~isempty(value.traceSets)
        traceSets = value.traceSets;
        names = traceSetNames(traceSets);
        row = chooseTraceRow(traceSets, names, opts.objectName);
        ts = traceSets(row);
        trace.name = char(ts.name);
        trace.coordinatesMm = double(ts.coordinatesMm);
        trace.labels = getOptionalLabels(ts, size(trace.coordinatesMm, 1));
        trace.rows = getOptionalField(ts, 'rows', nan(size(trace.coordinatesMm, 1), 1));
        trace.source = getOptionalField(value, 'meshSource', struct());
        trace = maybeFallbackToAllNonfiducialPoints(trace, value, opts);
        return;
    end
    if isstruct(value) && isfield(value, 'registration')
        trace = readTrace(value.registration, opts);
        return;
    end
    if isstruct(value) && isfield(value, 'registeredObjects') && ...
            ~isempty(value.registeredObjects)
        objects = value.registeredObjects;
        names = objectNames(objects);
        row = findTraceName(names, opts.objectName);
        if isempty(row)
            row = 1;
            warning('acsMakeImplantExclusionFromPolhemusTrace:ObjectNameFallback', ...
                'Could not find object "%s"; using "%s".', ...
                opts.objectName, names{row});
        end
        obj = objects(row);
        if isfield(obj, 'transformedCoordinatesMm') && ~isempty(obj.transformedCoordinatesMm)
            coords = double(obj.transformedCoordinatesMm);
        elseif isfield(obj, 'coordinatesMm') && ~isempty(obj.coordinatesMm)
            coords = double(obj.coordinatesMm);
        else
            coords = zeros(0, 3);
        end
        trace.name = names{row};
        trace.coordinatesMm = coords;
        trace.labels = getOptionalLabels(obj, size(coords, 1));
        trace.rows = getOptionalField(obj, 'rows', nan(size(coords, 1), 1));
        trace = maybeFallbackToAllNonfiducialPoints(trace, value, opts);
        return;
    end
    if isnumeric(value) && size(value, 2) == 3
        trace.coordinatesMm = double(value);
        trace.labels = defaultLabels(size(value, 1), 'implant');
        trace.rows = (1:size(value, 1))';
    end
end

function names = traceSetNames(traceSets)
    names = cell(numel(traceSets), 1);
    for i = 1:numel(traceSets)
        names{i} = char(getOptionalField(traceSets(i), 'name', sprintf('trace%d', i)));
    end
end

function names = objectNames(objects)
    names = cell(numel(objects), 1);
    for i = 1:numel(objects)
        names{i} = char(getOptionalField(objects(i), 'name', sprintf('object%d', i)));
    end
end

function row = findTraceName(names, requested)
    row = find(strcmpi(names, requested), 1);
    if isempty(row)
        row = find(contains(lower(names), lower(requested)), 1);
    end
    if isempty(row)
        requestedLower = lower(char(requested));
        namesLower = lower(names);
        if contains(requestedLower, 'headpost') || contains(requestedLower, 'head post')
            row = find(contains(namesLower, 'implant') | ...
                contains(namesLower, 'headpost') | ...
                contains(namesLower, 'head post'), 1);
        elseif contains(requestedLower, 'implant')
            row = find(contains(namesLower, 'headpost') | ...
                contains(namesLower, 'head post'), 1);
        end
    end
end

function row = chooseTraceRow(traceSets, names, requested)
    minPoints = 3;
    row = findTraceName(names, requested);
    if isempty(row)
        row = [];
    elseif tracePointCount(traceSets(row)) < minPoints
        warning('acsMakeImplantExclusionFromPolhemusTrace:TraceTooSmall', ...
            ['Trace "%s" has only %d point(s), but at least %d are ', ...
             'needed to make an exclusion footprint. Looking for another ', ...
             'usable trace set.'], ...
            names{row}, tracePointCount(traceSets(row)), minPoints);
        row = [];
    end
    if isempty(row)
        counts = arrayfun(@tracePointCount, traceSets);
        usable = find(counts >= minPoints);
        if ~isempty(usable)
            [~, bestLocal] = max(counts(usable));
            row = usable(bestLocal);
            warning('acsMakeImplantExclusionFromPolhemusTrace:TraceNameFallback', ...
                'Could not find usable trace "%s"; using "%s" (%d points).', ...
                requested, names{row}, counts(row));
        else
            [~, row] = max(counts);
            warning('acsMakeImplantExclusionFromPolhemusTrace:TraceNameFallbackTooSmall', ...
                ['Could not find a trace with at least %d points for "%s"; ', ...
                 'using "%s" (%d points) before trying whole-session fallback.'], ...
                minPoints, requested, names{row}, counts(row));
        end
    end
end

function n = tracePointCount(traceSet)
    if isfield(traceSet, 'coordinatesMm') && ~isempty(traceSet.coordinatesMm)
        n = size(traceSet.coordinatesMm, 1);
    else
        n = 0;
    end
end

function trace = maybeFallbackToAllNonfiducialPoints(trace, sourceValue, opts)
    if size(trace.coordinatesMm, 1) >= 3
        return;
    end
    fallback = allNonfiducialTrace(sourceValue, opts);
    if size(fallback.coordinatesMm, 1) < 3
        return;
    end
    warning('acsMakeImplantExclusionFromPolhemusTrace:UsingWholeSessionTrace', ...
        ['Selected trace "%s" has only %d point(s). Using all %d ', ...
         'non-fiducial transformed session points for the "%s" footprint.'], ...
        trace.name, size(trace.coordinatesMm, 1), ...
        size(fallback.coordinatesMm, 1), opts.objectName);
    trace = fallback;
end

function trace = allNonfiducialTrace(value, opts)
    trace = struct('name', [opts.objectName ' all non-fiducial points'], ...
        'coordinatesMm', zeros(0, 3), 'labels', {{}}, 'rows', [], ...
        'source', struct());

    coords = [];
    labels = {};
    if isfield(value, 'coordinatesMm') && ~isempty(value.coordinatesMm)
        coords = double(value.coordinatesMm);
        labels = getOptionalLabels(value, size(coords, 1));
    elseif isfield(value, 'transformedSourcePointsMm') && ...
            ~isempty(value.transformedSourcePointsMm)
        coords = double(value.transformedSourcePointsMm);
        if isfield(value, 'sourceLabels')
            labels = getOptionalLabels( ...
                struct('labels', {value.sourceLabels}), size(coords, 1));
        end
    end
    if isempty(coords)
        return;
    end
    if isempty(labels)
        labels = defaultLabels(size(coords, 1), 'point');
    end

    rows = [];
    if isfield(value, 'tracePointRows') && numel(value.tracePointRows) >= 3
        rows = double(value.tracePointRows(:));
        rows = rows(isfinite(rows) & rows >= 1 & rows <= size(coords, 1));
    end
    if numel(rows) < 3
        rows = (1:size(coords, 1))';
        protected = [];
        if isfield(value, 'protectedFiducialRows')
            protected = [protected; double(value.protectedFiducialRows(:))]; %#ok<AGROW>
        end
        if isfield(value, 'fiducialRows')
            protected = [protected; double(value.fiducialRows(:))]; %#ok<AGROW>
        end
        protected = protected(isfinite(protected) & protected >= 1 & ...
            protected <= size(coords, 1));
        rows = setdiff(rows, protected, 'stable');
    end

    trace.coordinatesMm = coords(rows, :);
    trace.labels = labels(rows);
    trace.rows = rows(:);
    if isfield(value, 'meshSource')
        trace.source = value.meshSource;
    end
end

function labels = getOptionalLabels(S, n)
    if isfield(S, 'labels') && ~isempty(S.labels)
        labels = normalizeLabelCell(S.labels);
    else
        labels = defaultLabels(n, 'point');
    end
    if numel(labels) ~= n
        labels = defaultLabels(n, 'point');
    end
end

function [TRskin, source] = readSkinMesh(value)
    if isstruct(value) && isfield(value, 'meshSource')
        value = value.meshSource;
    end
    [S, source] = loadSkinCacheStruct(value);
    if isfield(S, 'TRskin') && ~isempty(S.TRskin)
        TRskin = ensureTri(S.TRskin);
        source.meshStage = 'cap';
    elseif isfield(S, 'TRfiducialHead') && ~isempty(S.TRfiducialHead)
        TRskin = ensureTri(S.TRfiducialHead);
        source.meshStage = 'fullHead';
        warning('acsMakeImplantExclusionFromPolhemusTrace:UsingFiducialHeadMesh', ...
            ['Surface source does not contain TRskin; projecting implant ', ...
             'trace to TRfiducialHead. This is usually not appropriate ', ...
             'for cap manufacturing keepouts.']);
    else
        error('acsMakeImplantExclusionFromPolhemusTrace:MissingSkinMesh', ...
            'Could not find TRskin or TRfiducialHead in surface source.');
    end
end

function [S, source] = loadSkinCacheStruct(value)
    source = struct('type', '', 'file', '', 'cacheFile', '', ...
        'label', '', 'meshStage', '', 'coordinateFrame', 'capMakerPrintMm');
    if isa(value, 'triangulation')
        S = struct('TRskin', value);
        source.type = 'triangulation';
        source.label = 'triangulation';
        return;
    end
    if isstruct(value) && isfield(value, 'TRskin')
        S = value;
        source.type = 'skinStruct';
        source.label = 'skin struct';
        return;
    end
    if isstruct(value) && isfield(value, 'file') && ~isempty(value.file)
        value = value.file;
    elseif isstruct(value) && isfield(value, 'source') && ...
            isstruct(value.source) && isfield(value.source, 'file') && ...
            ~isempty(value.source.file)
        value = value.source.file;
    elseif isstruct(value) && isfield(value, 'layout') && ...
            isfield(value.layout, 'skin') && isfield(value.layout.skin, 'cacheFile')
        value = value.layout.skin.cacheFile;
    end
    if ~(ischar(value) || isstring(value))
        error('acsMakeImplantExclusionFromPolhemusTrace:BadSurfaceSource', ...
            'Could not resolve a skin cache from the surface source.');
    end
    fileName = expandUserPath(char(value));
    if exist(fileName, 'file') ~= 2
        error('acsMakeImplantExclusionFromPolhemusTrace:SkinCacheNotFound', ...
            'Skin cache not found: %s', fileName);
    end
    raw = load(fileName);
    if isfield(raw, 'TRskin') || isfield(raw, 'TRfiducialHead')
        S = raw;
    else
        S = firstStruct(raw);
    end
    source.type = 'skinCache';
    source.file = fileName;
    source.cacheFile = fileName;
    source.label = stripMatExtension(getFileName(fileName));
end

function TR = ensureTri(value)
    if isa(value, 'triangulation')
        TR = value;
    elseif isstruct(value) && isfield(value, 'ConnectivityList') && isfield(value, 'Points')
        TR = triangulation(double(value.ConnectivityList), double(value.Points));
    else
        error('acsMakeImplantExclusionFromPolhemusTrace:BadTriangulation', ...
            'Expected a triangulation or struct with Points and ConnectivityList.');
    end
end

function [footprintPoly, keepoutPoly] = makeFootprintPolys(xy, opts)
    xy = unique(double(xy), 'rows');
    if size(xy, 1) < 3
        error('acsMakeImplantExclusionFromPolhemusTrace:TooFewTracePoints', ...
            'At least three projected trace points are needed to make a footprint.');
    end
    try
        k = boundary(xy(:, 1), xy(:, 2), opts.boundaryShrink);
    catch
        k = convhull(xy(:, 1), xy(:, 2));
    end
    footprintPoly = polyshape(xy(k, 1), xy(k, 2), 'Simplify', true);
    try
        keepoutPoly = polybuffer(footprintPoly, opts.marginMm);
    catch
        keepoutPoly = fallbackBufferedPoly(xy, opts.marginMm);
    end
end

function [trace, info] = reconcileTraceToSurfaceFrame(trace, targetSource, ...
        targetSurfacePoints, opts)
    rawPoints = double(trace.coordinatesMm);
    rawScore = surfaceDistanceSummary(targetSurfacePoints, rawPoints);

    info = struct();
    info.mode = opts.frameTransformMode;
    info.method = 'raw';
    info.inputFrame = traceCoordinateFrame(trace);
    info.outputFrame = 'capMakerPrintMm';
    info.inputCoordinatesMm = rawPoints;
    info.outputCoordinatesMm = rawPoints;
    info.sourceCacheFile = '';
    info.targetCacheFile = '';
    info.rawDistanceSummaryMm = rawScore;
    info.transformedDistanceSummaryMm = emptyDistanceSummary();
    info.outputDistanceSummaryMm = rawScore;
    info.transformAvailable = false;
    info.transformApplied = false;
    info.reason = '';

    if strcmp(opts.frameTransformMode, 'never')
        info.reason = 'frameTransformMode=never';
        trace.coordinateFrame = info.outputFrame;
        return;
    end

    [sourceMeta, sourceFile] = readSkinMetaOptional(trace.source);
    [targetMeta, targetFile] = readSkinMetaOptional(targetSource);
    info.sourceCacheFile = sourceFile;
    info.targetCacheFile = targetFile;
    sameFrame = sameCacheFile(sourceFile, targetFile);

    if isempty(sourceMeta) || isempty(targetMeta)
        info.reason = 'source or target skin metadata unavailable';
        sourceKnownDifferent = ~isempty(sourceFile) && ~isempty(targetFile) && ...
            ~sameFrame;
        if strcmp(opts.frameTransformMode, 'always') || sourceKnownDifferent
            error('acsMakeImplantExclusionFromPolhemusTrace:MissingFrameMetadata', ...
                ['Could not transform trace into cap frame because source ', ...
                 'or target skin metadata is unavailable. Source: %s Target: %s'], ...
                sourceFile, targetFile);
        end
        trace.coordinateFrame = info.outputFrame;
        return;
    end

    if sameFrame && ~strcmp(opts.frameTransformMode, 'always')
        info.reason = 'trace source cache matches target surface cache';
    else
        transformedPoints = transformBetweenSkinPrintFrames(rawPoints, ...
            sourceMeta, targetMeta);
        transformedScore = surfaceDistanceSummary(targetSurfacePoints, ...
            transformedPoints);
        info.transformAvailable = true;
        info.transformedDistanceSummaryMm = transformedScore;
        trace.coordinatesMm = transformedPoints;
        info.method = 'sourceSkinPrintToTargetSkinPrint';
        info.outputCoordinatesMm = transformedPoints;
        info.outputDistanceSummaryMm = transformedScore;
        info.transformApplied = true;
        if strcmp(opts.frameTransformMode, 'always')
            info.reason = 'frameTransformMode=always';
        else
            info.reason = 'trace source cache differs from target surface cache';
        end
    end
    if isfinite(info.outputDistanceSummaryMm.median) && ...
            info.outputDistanceSummaryMm.median > 20
        warning('acsMakeImplantExclusionFromPolhemusTrace:TraceFarFromSurface', ...
            ['Chosen headpost trace frame is still far from the target ', ...
             'cap surface (median %.3g mm, p95 %.3g mm). Check source ', ...
             'and target skin-cache files.'], ...
            info.outputDistanceSummaryMm.median, ...
            info.outputDistanceSummaryMm.p95);
    end
    trace.coordinateFrame = info.outputFrame;
end

function tf = sameCacheFile(sourceFile, targetFile)
    if isempty(sourceFile) || isempty(targetFile)
        tf = false;
        return;
    end
    tf = strcmpi(canonicalPath(sourceFile), canonicalPath(targetFile));
end

function frame = traceCoordinateFrame(trace)
    frame = 'unknown';
    if isfield(trace, 'source') && isstruct(trace.source) && ...
            isfield(trace.source, 'coordinateFrame') && ...
            ~isempty(trace.source.coordinateFrame)
        frame = char(trace.source.coordinateFrame);
    end
end

function [meta, cacheFile] = readSkinMetaOptional(value)
    meta = [];
    cacheFile = resolveSkinCacheFile(value);
    if isempty(cacheFile) || exist(cacheFile, 'file') ~= 2
        return;
    end
    try
        S = load(cacheFile, 'meta');
        if isfield(S, 'meta') && isstruct(S.meta)
            meta = S.meta;
        end
    catch
        meta = [];
    end
end

function cacheFile = resolveSkinCacheFile(value)
    cacheFile = '';
    if isempty(value)
        return;
    end
    if ischar(value) || isstring(value)
        cacheFile = expandUserPath(char(value));
        return;
    end
    if ~isstruct(value)
        return;
    end
    if isfield(value, 'cacheFile') && ~isempty(value.cacheFile)
        cacheFile = char(value.cacheFile);
    elseif isfield(value, 'file') && ~isempty(value.file)
        cacheFile = char(value.file);
    elseif isfield(value, 'source') && isstruct(value.source)
        cacheFile = resolveSkinCacheFile(value.source);
    elseif isfield(value, 'meshSource') && isstruct(value.meshSource)
        cacheFile = resolveSkinCacheFile(value.meshSource);
    elseif isfield(value, 'skin') && isstruct(value.skin) && ...
            isfield(value.skin, 'cacheFile') && ~isempty(value.skin.cacheFile)
        cacheFile = char(value.skin.cacheFile);
    elseif isfield(value, 'layout') && isstruct(value.layout) && ...
            isfield(value.layout, 'skin') && ...
            isfield(value.layout.skin, 'cacheFile') && ...
            ~isempty(value.layout.skin.cacheFile)
        cacheFile = char(value.layout.skin.cacheFile);
    end
    cacheFile = expandUserPath(cacheFile);
end

function pointsTargetPrint = transformBetweenSkinPrintFrames( ...
        pointsSourcePrint, sourceMeta, targetMeta)
    sourceWorld = printMmToOriginalWorldMm(pointsSourcePrint, sourceMeta);
    pointsTargetPrint = originalWorldMmToPrintMm(sourceWorld, targetMeta);
end

function worldMm = printMmToOriginalWorldMm(printMm, meta)
    validateSkinMetaForTransform(meta);
    finalWorldMm = applyAffineToPoints(meta.print.T_print2world, printMm);
    worldMm = (double(meta.align.R) \ finalWorldMm')';
end

function printMm = originalWorldMmToPrintMm(worldMm, meta)
    validateSkinMetaForTransform(meta);
    finalWorldMm = (double(meta.align.R) * double(worldMm)')';
    printMm = applyAffineToPoints(meta.print.T_world2print, finalWorldMm);
end

function validateSkinMetaForTransform(meta)
    if ~isstruct(meta) || ~isfield(meta, 'align') || ...
            ~isfield(meta.align, 'R') || ~isfield(meta, 'print') || ...
            ~isfield(meta.print, 'T_world2print') || ...
            ~isfield(meta.print, 'T_print2world')
        error('acsMakeImplantExclusionFromPolhemusTrace:BadSkinMeta', ...
            'Skin metadata is missing align.R or print transform fields.');
    end
end

function summary = surfaceDistanceSummary(surfacePoints, queryPoints)
    if isempty(surfacePoints) || isempty(queryPoints)
        summary = emptyDistanceSummary();
        return;
    end
    [~, distance] = nearestRows(surfacePoints, queryPoints, 2500);
    summary = struct( ...
        'median', medianFinite(distance), ...
        'p95', percentileLocal(distance, 95), ...
        'max', max(distance), ...
        'n', numel(distance));
end

function summary = emptyDistanceSummary()
    summary = struct('median', NaN, 'p95', NaN, 'max', NaN, 'n', 0);
end

function [projectedMm, nearestVertex, projectionDistance, info] = ...
        projectTraceToSurfaceFootprint(surfacePoints, tracePoints, opts)
    tracePoints = double(tracePoints);
    traceUniqueXy = uniqueXyCount(tracePoints(:, 1:2));
    if traceUniqueXy < 3
        error('acsMakeImplantExclusionFromPolhemusTrace:TooFewTraceXyPoints', ...
            'At least three unique trace XY points are needed to make a footprint.');
    end

    if strcmp(opts.projectionMode, 'traceXY')
        [projectedMm, nearestVertex, projectionDistance, info] = ...
            projectTraceXyToSurfaceZ(surfacePoints, tracePoints);
        return;
    end

    [nearestVertex, projectionDistance] = nearestRows(surfacePoints, tracePoints, 2500);
    projectedMm = surfacePoints(nearestVertex, :);

    nearestUniqueXy = uniqueXyCount(projectedMm(:, 1:2));
    info = struct( ...
        'method', 'nearest3dSurfaceVertex', ...
        'fallbackUsed', false, ...
        'reason', '', ...
        'nearest3dUniqueXy', nearestUniqueXy, ...
        'traceUniqueXy', traceUniqueXy, ...
        'fallbackUniqueXy', nearestUniqueXy, ...
        'nearestXyDistanceSummaryMm', struct( ...
            'median', NaN, 'p95', NaN, 'max', NaN));

    if nearestUniqueXy >= 3 || strcmp(opts.projectionMode, 'nearest3d')
        return;
    end

    [projectedMm, nearestVertex, projectionDistance, info] = ...
        projectTraceXyToSurfaceZ(surfacePoints, tracePoints);
    info.method = 'traceXYWithUpperSurfaceZ';
    info.fallbackUsed = true;
    info.reason = 'nearest 3-D surface projection collapsed the footprint';
    info.nearest3dUniqueXy = nearestUniqueXy;
    warning('acsMakeImplantExclusionFromPolhemusTrace:ProjectionCollapsed', ...
        ['Nearest 3-D projection of "%s" collapsed to %d unique XY ', ...
         'point(s). Preserving registered trace XY and assigning Z from ', ...
         'the local upper cap surface in XY.'], ...
        opts.objectName, nearestUniqueXy);
end

function [projectedMm, nearestVertex, projectionDistance, info] = ...
        projectTraceXyToSurfaceZ(surfacePoints, tracePoints)
    [surfaceZ, nearestVertex, xyDistance] = upperSurfaceZAtXy( ...
        surfacePoints, tracePoints(:, 1:2), 2500);
    projectedMm = [tracePoints(:, 1:2), surfaceZ(:)];
    projectionDistance = sqrt(sum((tracePoints - projectedMm) .^ 2, 2));
    info = struct( ...
        'method', 'traceXYWithUpperSurfaceZ', ...
        'fallbackUsed', false, ...
        'reason', '', ...
        'nearest3dUniqueXy', NaN, ...
        'traceUniqueXy', uniqueXyCount(tracePoints(:, 1:2)), ...
        'fallbackUniqueXy', uniqueXyCount(projectedMm(:, 1:2)), ...
        'surfaceZMode', 'local upper envelope', ...
        'nearestXyDistanceSummaryMm', struct( ...
            'median', medianFinite(xyDistance), ...
            'p95', percentileLocal(xyDistance, 95), ...
            'max', max(xyDistance)));
end

function n = uniqueXyCount(xy)
    if isempty(xy)
        n = 0;
        return;
    end
    tol = 1e-6;
    xy = round(double(xy) ./ tol) .* tol;
    n = size(unique(xy, 'rows'), 1);
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

function border = polyBoundary3(ps, projectedMm, surfaceSource)
    [xRaw, yRaw] = boundary(ps);
    segments = finitePolylineSegments(xRaw(:), yRaw(:));
    if isempty(segments)
        border = zeros(0, 3);
        return;
    end

    border = zeros(0, 3);
    for i = 1:numel(segments)
        xy = segments{i};
        [x, y] = densifyPolyline(xy(:, 1), xy(:, 2), 0.75);
        if nargin >= 3 && ~isempty(surfaceSource)
            z = upperSurfaceZAtXy(surfaceSource, [x(:), y(:)], 2500);
        else
            z = repmat(medianFinite(projectedMm(:, 3)), numel(x), 1);
        end
        border = [border; x(:), y(:), z(:); NaN NaN NaN]; %#ok<AGROW>
    end
    if ~isempty(border)
        border(end, :) = [];
    end
end

function segments = finitePolylineSegments(x, y)
    finiteRow = isfinite(x) & isfinite(y);
    segments = {};
    startRow = [];
    for i = 1:numel(finiteRow)
        if finiteRow(i) && isempty(startRow)
            startRow = i;
        elseif ~finiteRow(i) && ~isempty(startRow)
            if i - startRow >= 2
                segmentX = x(startRow:(i - 1));
                segmentY = y(startRow:(i - 1));
                segments{end + 1} = [segmentX, segmentY]; %#ok<AGROW>
            end
            startRow = [];
        end
    end
    if ~isempty(startRow) && numel(finiteRow) - startRow + 1 >= 2
        segmentX = x(startRow:end);
        segmentY = y(startRow:end);
        segments{end + 1} = [segmentX, segmentY]; %#ok<AGROW>
    end
end

function [xd, yd] = densifyPolyline(x, y, maxStepMm)
    x = x(:);
    y = y(:);
    if numel(x) < 2
        xd = x;
        yd = y;
        return;
    end
    if nargin < 3 || isempty(maxStepMm) || maxStepMm <= 0
        maxStepMm = 1;
    end

    xd = zeros(0, 1);
    yd = zeros(0, 1);
    for i = 1:(numel(x) - 1)
        segmentLength = hypot(x(i + 1) - x(i), y(i + 1) - y(i));
        nStep = max(1, ceil(segmentLength / maxStepMm));
        t = (0:(nStep - 1))' ./ nStep;
        xd = [xd; x(i) + t .* (x(i + 1) - x(i))]; %#ok<AGROW>
        yd = [yd; y(i) + t .* (y(i + 1) - y(i))]; %#ok<AGROW>
    end
    xd = [xd; x(end)];
    yd = [yd; y(end)];
end

function opts = resolveOutputFile(source, trace, opts)
    if ~isempty(opts.outputFile)
        return;
    end
    folder = pwd;
    stem = safeName(trace.name);
    if isfield(source, 'cacheFile') && ~isempty(source.cacheFile)
        folder = fileparts(source.cacheFile);
        stem = [stripMatExtension(getFileName(source.cacheFile)) '_' stem];
    elseif isfield(source, 'file') && ~isempty(source.file)
        folder = fileparts(source.file);
        stem = [stripMatExtension(getFileName(source.file)) '_' stem];
    end
    opts.outputFile = fullfile(folder, [stem '_' opts.outputTag '.mat']);
end

function fig = makeQcFigure(TRskin, trace, projectedMm, footprintPoly, ...
        keepoutPoly, border, source, opts, figVisible)
    fig = figure('Name', 'Implant exclusion QC', ...
        'NumberTitle', 'off', 'Color', 'w', 'Visible', figVisible, ...
        'Position', [60 50 1500 950]);
    tiledlayout(fig, 2, 2, 'Padding', 'loose', 'TileSpacing', 'loose');

    ax1 = nexttile;
    hold(ax1, 'on');
    hMesh = drawTri(ax1, TRskin, [0.74 0.76 0.80], 0.24);
    hTrace = scatter3(ax1, trace.coordinatesMm(:, 1), trace.coordinatesMm(:, 2), ...
        trace.coordinatesMm(:, 3), 16, [0.85 0.10 0.10], 'filled', ...
        'Clipping', 'off');
    hProjected = scatter3(ax1, projectedMm(:, 1), projectedMm(:, 2), projectedMm(:, 3), ...
        16, [0.05 0.30 0.85], 'filled', 'Clipping', 'off');
    hBorder = plot3(ax1, border(:, 1), border(:, 2), border(:, 3), ...
        'm-', 'LineWidth', 2, 'Clipping', 'off');
    title(ax1, 'Overall');
    legend(ax1, [hMesh hTrace hProjected hBorder], ...
        {'head mesh', 'trace', 'projected', 'keepout'}, ...
        'Location', 'northwest', 'Box', 'off', 'FontSize', 8);
    format3d(ax1);

    ax2 = nexttile;
    hold(ax2, 'on');
    drawTri(ax2, TRskin, [0.78 0.79 0.82], 0.36);
    scatter3(ax2, trace.coordinatesMm(:, 1), trace.coordinatesMm(:, 2), ...
        trace.coordinatesMm(:, 3), 20, [0.85 0.10 0.10], 'filled', ...
        'Clipping', 'off');
    scatter3(ax2, projectedMm(:, 1), projectedMm(:, 2), projectedMm(:, 3), ...
        20, [0.05 0.30 0.85], 'filled', 'Clipping', 'off');
    plot3(ax2, border(:, 1), border(:, 2), border(:, 3), ...
        'm-', 'LineWidth', 2.5, 'Clipping', 'off');
    scatter3(ax2, border(:, 1), border(:, 2), border(:, 3), ...
        8, [0.95 0.05 0.85], 'filled', 'Clipping', 'off');
    title(ax2, 'Detail');
    format3d(ax2);
    fitLocalAxes(ax2, [trace.coordinatesMm; projectedMm; border], ...
        TRskin.Points, 12);

    ax3 = nexttile;
    hold(ax3, 'on');
    hFootprint = plot(ax3, footprintPoly, 'FaceColor', [0.25 0.50 0.95], ...
        'FaceAlpha', 0.25, 'EdgeColor', [0.15 0.30 0.85]);
    hKeepout = plot(ax3, keepoutPoly, 'FaceColor', [0.95 0.15 0.45], ...
        'FaceAlpha', 0.20, 'EdgeColor', [0.80 0.05 0.30]);
    hTrace2d = scatter(ax3, trace.coordinatesMm(:, 1), trace.coordinatesMm(:, 2), ...
        12, [0.85 0.10 0.10], 'filled');
    hProjected2d = scatter(ax3, projectedMm(:, 1), projectedMm(:, 2), ...
        12, [0.05 0.30 0.85], 'filled');
    axis(ax3, 'equal');
    grid(ax3, 'on');
    xlabel(ax3, 'X (mm)');
    ylabel(ax3, 'Y (mm)');
    title(ax3, sprintf('Footprint + %.1f mm', opts.marginMm));
    legend(ax3, [hFootprint hKeepout hTrace2d hProjected2d], ...
        {'footprint', 'keepout', 'trace', 'projected'}, ...
        'Location', 'northwest', 'Box', 'off', 'FontSize', 8);

    ax4 = nexttile;
    plot(ax4, border(:, 3), 'm-', 'LineWidth', 1.5);
    grid(ax4, 'on');
    xlabel(ax4, 'Border sample');
    ylabel(ax4, 'Z (mm)');
    title(ax4, 'Border Z');

    compactFigureText(fig);
    sgtitle(fig, sprintf('Implant exclusion QC: %s', opts.objectName), ...
        'Interpreter', 'none', 'FontWeight', 'bold');
    try
        rotate3d(fig, 'on');
    catch
    end
end

function h = drawTri(ax, TR, color, alphaValue)
    h = patch(ax, 'Faces', TR.ConnectivityList, 'Vertices', TR.Points, ...
        'FaceColor', color, 'FaceAlpha', alphaValue, 'EdgeColor', 'none', ...
        'Clipping', 'on');
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

function fitLocalAxes(ax, focusPoints, surfacePoints, marginMm)
    if nargin < 4 || isempty(marginMm)
        marginMm = 10;
    end
    focusPoints = double(focusPoints);
    focusPoints = focusPoints(all(isfinite(focusPoints), 2), :);
    if isempty(focusPoints)
        return;
    end

    lo = min(focusPoints, [], 1) - marginMm;
    hi = max(focusPoints, [], 1) + marginMm;
    surfacePoints = double(surfacePoints);
    inXy = surfacePoints(:, 1) >= lo(1) & surfacePoints(:, 1) <= hi(1) & ...
        surfacePoints(:, 2) >= lo(2) & surfacePoints(:, 2) <= hi(2);
    zPool = [focusPoints(:, 3); surfacePoints(inXy, 3)];
    zPool = zPool(isfinite(zPool));
    if ~isempty(zPool)
        lo(3) = min(zPool) - marginMm * 0.5;
        hi(3) = max(zPool) + marginMm * 0.5;
    end
    for dim = 1:3
        if hi(dim) <= lo(dim)
            lo(dim) = lo(dim) - 1;
            hi(dim) = hi(dim) + 1;
        end
    end

    set(ax, 'XLim', [lo(1) hi(1)], ...
        'YLim', [lo(2) hi(2)], ...
        'ZLim', [lo(3) hi(3)]);
end

function saveQcFigure(fig, fileName)
    try
        exportgraphics(fig, fileName, 'Resolution', 200);
    catch
        saveas(fig, fileName);
    end
end

function [idx, dist] = nearestRows(reference, query, chunk)
    idx = zeros(size(query, 1), 1);
    dist = zeros(size(query, 1), 1);
    for a = 1:chunk:size(query, 1)
        b = min(size(query, 1), a + chunk - 1);
        D = squaredDistanceRows(query(a:b, :), reference);
        [d2, idxLocal] = min(D, [], 2);
        idx(a:b) = idxLocal;
        dist(a:b) = sqrt(d2);
    end
end

function [z, idx, xyDist] = upperSurfaceZAtXy(surfaceSource, queryXY, chunk)
    if nargin < 3 || isempty(chunk)
        chunk = 2500;
    end

    if isTriangulationLike(surfaceSource)
        [z, idx, xyDist] = upperSurfaceTriangleZAtXy( ...
            ensureTri(surfaceSource), queryXY, chunk);
        return;
    end

    surfacePoints = double(surfaceSource);
    queryXY = double(queryXY);
    z = nan(size(queryXY, 1), 1);
    try
        [envelopeXY, envelopeZ] = upperSurfaceEnvelopeSamples(surfacePoints, 1.0);
        if size(envelopeXY, 1) >= 3
            F = scatteredInterpolant(envelopeXY(:, 1), envelopeXY(:, 2), ...
                envelopeZ(:), 'natural', 'nearest');
            z = F(queryXY(:, 1), queryXY(:, 2));
        end
    catch
        z(:) = NaN;
    end

    bad = ~isfinite(z);
    if any(bad)
        z(bad) = localUpperSurfaceZAtXy(surfacePoints, queryXY(bad, :), chunk);
    end

    [idx, ~] = nearestRows(surfacePoints, [queryXY, z], chunk);
    xyDist = sqrt(sum((surfacePoints(idx, 1:2) - queryXY) .^ 2, 2));
end

function tf = isTriangulationLike(value)
    tf = isa(value, 'triangulation') || ...
        (isstruct(value) && isfield(value, 'ConnectivityList') && ...
        isfield(value, 'Points'));
end

function [z, idx, xyDist] = upperSurfaceTriangleZAtXy(TR, queryXY, chunk)
    if nargin < 3 || isempty(chunk)
        chunk = 2500;
    end

    V = double(TR.Points);
    F = double(TR.ConnectivityList);
    queryXY = double(queryXY);
    nQuery = size(queryXY, 1);
    z = nan(nQuery, 1);
    triIdx = nan(nQuery, 1);

    vx = V(:, 1);
    vy = V(:, 2);
    vz = V(:, 3);
    triX = vx(F);
    triY = vy(F);
    triZ = vz(F);
    minX = min(triX, [], 2);
    maxX = max(triX, [], 2);
    minY = min(triY, [], 2);
    maxY = max(triY, [], 2);

    tol = 1e-7;
    for a = 1:chunk:nQuery
        b = min(nQuery, a + chunk - 1);
        for row = a:b
            x = queryXY(row, 1);
            y = queryXY(row, 2);
            candidate = x >= (minX - tol) & x <= (maxX + tol) & ...
                y >= (minY - tol) & y <= (maxY + tol);
            candidateRows = find(candidate);
            if isempty(candidateRows)
                continue;
            end

            zBest = -Inf;
            triBest = NaN;
            for c = reshape(candidateRows, 1, [])
                x1 = triX(c, 1); x2 = triX(c, 2); x3 = triX(c, 3);
                y1 = triY(c, 1); y2 = triY(c, 2); y3 = triY(c, 3);
                denom = (y2 - y3) * (x1 - x3) + ...
                    (x3 - x2) * (y1 - y3);
                if abs(denom) < eps
                    continue;
                end

                w1 = ((y2 - y3) * (x - x3) + ...
                    (x3 - x2) * (y - y3)) / denom;
                w2 = ((y3 - y1) * (x - x3) + ...
                    (x1 - x3) * (y - y3)) / denom;
                w3 = 1 - w1 - w2;
                if w1 < -1e-6 || w2 < -1e-6 || w3 < -1e-6
                    continue;
                end

                zCandidate = w1 * triZ(c, 1) + w2 * triZ(c, 2) + ...
                    w3 * triZ(c, 3);
                if zCandidate > zBest
                    zBest = zCandidate;
                    triBest = c;
                end
            end

            if isfinite(zBest)
                z(row) = zBest;
                triIdx(row) = triBest;
            end
        end
    end

    bad = ~isfinite(z);
    if any(bad)
        z(bad) = localUpperSurfaceZAtXy(V, queryXY(bad, :), chunk);
    end

    [idx, ~] = nearestRows(V, [queryXY, z], chunk);
    xyDist = sqrt(sum((V(idx, 1:2) - queryXY) .^ 2, 2));
    if any(isfinite(triIdx))
        xyDist(isfinite(triIdx)) = 0;
    end
end

function [envelopeXY, envelopeZ] = upperSurfaceEnvelopeSamples(surfacePoints, binMm)
    if nargin < 2 || isempty(binMm) || binMm <= 0
        binMm = 1.0;
    end

    surfacePoints = double(surfacePoints);
    binXY = round(surfacePoints(:, 1:2) ./ binMm) .* binMm;
    [envelopeXY, ~, group] = unique(binXY, 'rows');
    envelopeZ = accumarray(group, surfacePoints(:, 3), [], @max);
end

function z = localUpperSurfaceZAtXy(surfacePoints, queryXY, chunk)
    if nargin < 3 || isempty(chunk)
        chunk = 2500;
    end

    surfaceXY = double(surfacePoints(:, 1:2));
    surfaceZ = double(surfacePoints(:, 3));
    queryXY = double(queryXY);
    nQuery = size(queryXY, 1);
    z = zeros(nQuery, 1);

    % A cropped cap mesh can have dorsal and crop-plane vertices with similar
    % XY positions. Use the upper local envelope so implant keepouts stay on
    % the scalp side instead of occasionally snapping to the crop rim.
    minRadiusMm = 2.0;
    padRadiusMm = 2.0;
    for a = 1:chunk:nQuery
        b = min(nQuery, a + chunk - 1);
        D = squaredDistanceRows(queryXY(a:b, :), surfaceXY);
        [d2Min, nearestLocal] = min(D, [], 2);
        for ii = 1:(b - a + 1)
            row = a + ii - 1;
            nearestDist = sqrt(d2Min(ii));
            searchRadius = max(minRadiusMm, nearestDist + padRadiusMm);
            candidateMask = D(ii, :) <= searchRadius^2;
            if ~any(candidateMask)
                candidateMask(nearestLocal(ii)) = true;
            end

            candidateRows = find(candidateMask);
            [~, zLocal] = max(surfaceZ(candidateRows));
            z(row) = surfaceZ(candidateRows(zLocal));
        end
    end
end

function D = squaredDistanceRows(A, B)
    D = bsxfun(@plus, sum(A .^ 2, 2), sum(B .^ 2, 2)') - 2 * (A * B');
    D(D < 0) = 0;
end

function S = loadStructFile(fileName)
    fileName = expandUserPath(fileName);
    [~, ~, ext] = fileparts(fileName);
    switch lower(ext)
        case '.mat'
            raw = load(fileName);
            S = firstStruct(raw);
        case '.json'
            S = jsondecode(fileread(fileName));
        otherwise
            error('acsMakeImplantExclusionFromPolhemusTrace:UnsupportedFile', ...
                'Trace file must be MAT or JSON: %s', fileName);
    end
end

function S = firstStruct(raw)
    preferred = {'out', 'outForSave', 'registration', 'modelFiducials'};
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
    error('acsMakeImplantExclusionFromPolhemusTrace:NoStructInFile', ...
        'Could not find a readable struct.');
end

function labels = normalizeLabelCell(labelsIn)
    if isempty(labelsIn)
        labels = {};
    elseif iscell(labelsIn)
        labels = cellstr(labelsIn(:));
    elseif isstring(labelsIn)
        labels = cellstr(labelsIn(:));
    elseif ischar(labelsIn)
        if size(labelsIn, 1) == 1
            labels = {char(labelsIn)};
        else
            labels = cellstr(labelsIn);
        end
    else
        labels = cellstr(labelsIn(:));
    end
    labels = labels(:);
end

function labels = defaultLabels(n, prefix)
    labels = cell(n, 1);
    for i = 1:n
        labels{i} = sprintf('%s%d', prefix, i);
    end
end

function value = getOptionalField(S, fieldName, defaultValue)
    if isstruct(S) && isfield(S, fieldName) && ~isempty(S.(fieldName))
        value = S.(fieldName);
    else
        value = defaultValue;
    end
end

function name = getFileName(fileName)
    [~, stem, ext] = fileparts(fileName);
    name = [stem ext];
end

function stem = stripMatExtension(fileName)
    [~, stem, ext] = fileparts(fileName);
    if ~strcmpi(ext, '.mat')
        stem = [stem ext];
    end
end

function value = safeName(value)
    value = regexprep(char(value), '[^\w\-]+', '_');
    value = regexprep(value, '_+', '_');
    value = regexprep(value, '^_|_$', '');
    if isempty(value)
        value = 'implantExclusion';
    end
end

function pointsOut = applyAffineToPoints(M, pointsIn)
    pointsHom = [double(pointsIn), ones(size(pointsIn, 1), 1)];
    pointsHom = (double(M) * pointsHom')';
    pointsOut = pointsHom(:, 1:3);
end

function value = canonicalPath(value)
    value = expandUserPath(char(value));
    if isempty(value)
        return;
    end
    try
        value = char(java.io.File(value).getCanonicalPath());
    catch
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

function ensureDir(folder)
    if isempty(folder)
        return;
    end
    if exist(folder, 'dir') ~= 7
        mkdir(folder);
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

function value = percentileLocal(x, pct)
    x = sort(x(isfinite(x)));
    if isempty(x)
        value = NaN;
        return;
    end
    pos = 1 + (numel(x) - 1) * pct / 100;
    lo = floor(pos);
    hi = ceil(pos);
    if lo == hi
        value = x(lo);
    else
        value = x(lo) + (pos - lo) * (x(hi) - x(lo));
    end
end

function printSummary(out)
    fprintf('\nImplant exclusion from Polhemus trace\n');
    fprintf('  object: %s (%d trace points)\n', out.name, ...
        size(out.traceCoordinatesMm, 1));
    fprintf('  frame transform: %s', out.frameTransformInfo.method);
    if isfield(out.frameTransformInfo, 'reason') && ...
            ~isempty(out.frameTransformInfo.reason)
        fprintf(' (%s)', out.frameTransformInfo.reason);
    end
    fprintf('\n');
    fprintf('  raw trace distance median/p95/max: %.3g / %.3g / %.3g mm\n', ...
        out.frameTransformInfo.rawDistanceSummaryMm.median, ...
        out.frameTransformInfo.rawDistanceSummaryMm.p95, ...
        out.frameTransformInfo.rawDistanceSummaryMm.max);
    if out.frameTransformInfo.transformAvailable
        fprintf('  transformed trace distance median/p95/max: %.3g / %.3g / %.3g mm\n', ...
            out.frameTransformInfo.transformedDistanceSummaryMm.median, ...
            out.frameTransformInfo.transformedDistanceSummaryMm.p95, ...
            out.frameTransformInfo.transformedDistanceSummaryMm.max);
    end
    fprintf('  chosen trace distance median/p95/max: %.3g / %.3g / %.3g mm\n', ...
        out.frameTransformInfo.outputDistanceSummaryMm.median, ...
        out.frameTransformInfo.outputDistanceSummaryMm.p95, ...
        out.frameTransformInfo.outputDistanceSummaryMm.max);
    fprintf('  projection method: %s\n', out.projectionMethod);
    fprintf('  margin: %.3g mm\n', out.marginMm);
    fprintf('  output: %s\n', out.outputFile);
    fprintf('  projection distance median/p95/max: %.3g / %.3g / %.3g mm\n', ...
        out.projectionDistanceSummaryMm.median, ...
        out.projectionDistanceSummaryMm.p95, ...
        out.projectionDistanceSummaryMm.max);
    if ~isempty(out.qcFigure)
        fprintf('  QC figure: %s\n', out.qcFigure);
    end
end
