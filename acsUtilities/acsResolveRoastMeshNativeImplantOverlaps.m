function out = acsResolveRoastMeshNativeImplantOverlaps(requestIn, varargin)
% ACSRESOLVEROASTMESHNATIVEIMPLANTOVERLAPS Clear tissue faces around implants.
%
% out = acsResolveRoastMeshNativeImplantOverlaps(request)
% applies the mesh-native overlap policy used for implanted hardware:
% titanium is preserved as the solid domain, and replaceable tissue
% surfaces are cleared where they intrude into or touch the titanium mesh.
%
% This is a meshing-preflight step. It does not deform titanium and does
% not yet build a mathematically exact conformal interface; it produces a
% cleaned request plus diagnostics so the next TetGen adapter has a better
% chance of receiving a valid, non-intersecting PLC.

    if nargin < 1 || isempty(requestIn)
        error('acsResolveRoastMeshNativeImplantOverlaps:MissingRequest', ...
            'Provide an acsPrepareRoastMeshNativeRequest struct or MAT file.');
    end
    opts = parseInputs(varargin{:});
    addLocalDependencies();

    request = readRequest(requestIn);
    requireRequestFields(request);
    if isempty(opts.outputFile)
        opts.outputFile = defaultOutputFile(request);
    end
    if exist(opts.outputFile, 'file') == 2 && ~opts.force
        out = loadExisting(opts.outputFile);
        if opts.verbose
            fprintf('ROAST mesh-native implant-resolved request already exists; reusing %s\n', ...
                opts.outputFile);
        end
        return;
    end

    [titaniumRecord, titaniumIndex] = findTitaniumRecord(request.surfaceRecords);
    if isempty(titaniumIndex)
        if opts.verbose
            fprintf('\nROAST mesh-native implant overlap resolution\n');
            fprintf('  no titanium surface present; preserving request as-is.\n');
        end
        out = request;
        out.type = 'roastMeshNativeRequestImplantResolved';
        out.sourceRequestFile = optionalCharField(request, 'outputFile', '');
        out.implantOverlapResolution = noTitaniumResolution(opts);
        out.outputFile = opts.outputFile;
        saveResolvedRequest(out, opts);
        printSummary(out, opts);
        return;
    end

    if opts.verbose
        fprintf('\nResolving ROAST mesh-native implant overlaps.\n');
        fprintf('  request: %s\n', optionalCharField(request, 'outputFile', 'workspace struct'));
        fprintf('  titanium surface: %s\n', titaniumRecord.name);
    end
    stageTimer = tic;
    titanium = prepareTitaniumMesh(titaniumRecord, opts);
    if opts.verbose
        fprintf('  prepared titanium mesh in %.1f s (%d vertices, %d faces).\n', ...
            toc(stageTimer), size(titanium.V, 1), size(titanium.F, 1));
    end
    stageTimer = tic;
    [surfaceRecords, resolution] = clearReplaceableSurfaces( ...
        request.surfaceRecords, titanium, titaniumIndex, opts);
    if opts.verbose
        fprintf('  cleared replaceable surfaces in %.1f s.\n', toc(stageTimer));
    end
    stageTimer = tic;
    [verticesMm, faces, faceSurfaceIndex, faceLabels] = ...
        concatenateSurfaceRecords(surfaceRecords);
    if opts.verbose
        fprintf('  concatenated resolved surfaces in %.1f s (%d vertices, %d faces).\n', ...
            toc(stageTimer), size(verticesMm, 1), size(faces, 1));
    end

    out = request;
    out.type = 'roastMeshNativeRequestImplantResolved';
    out.sourceRequestFile = optionalCharField(request, 'outputFile', '');
    out.surfaceRecords = surfaceRecords;
    out.combinedSurface = struct( ...
        'verticesMm', verticesMm, ...
        'faces', faces, ...
        'faceSurfaceIndex', faceSurfaceIndex, ...
        'faceLabels', faceLabels);
    out.implantOverlapResolution = resolution;
    out.quality = updateQuality(request.quality, surfaceRecords, ...
        verticesMm, faces, resolution);
    out.outputFile = opts.outputFile;
    out.options.implantOverlapResolution = opts;

    qcFile = '';
    fig = [];
    if opts.showFigures || opts.saveFigures
        stageTimer = tic;
        if opts.verbose
            fprintf('  making implant-overlap QC figure.\n');
        end
        figVisible = 'off';
        if opts.showFigures
            figVisible = 'on';
        end
        fig = makeQcFigure(request.surfaceRecords, surfaceRecords, ...
            titaniumIndex, resolution, opts, figVisible);
        if opts.saveFigures
            qcFile = fullfile(fileparts(opts.outputFile), 'qc', ...
                [stripMatExtension(getFileName(opts.outputFile)) '_qc.png']);
            ensureDir(fileparts(qcFile));
            saveQcFigure(fig, qcFile);
        end
        if ~opts.showFigures && isgraphics(fig)
            close(fig);
            fig = [];
        end
        if opts.verbose
            fprintf('  made implant-overlap QC figure in %.1f s.\n', ...
                toc(stageTimer));
        end
    end
    out.implantOverlapResolution.qcFigure = qcFile;
    out.figure = fig;

    saveResolvedRequest(out, opts);
    printSummary(out, opts);
end

function opts = parseInputs(varargin)
    p = inputParser;
    p.FunctionName = 'acsResolveRoastMeshNativeImplantOverlaps';
    addParameter(p, 'outputFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'force', false, @isBoolLike);
    addParameter(p, 'replaceableLabels', [4 5 6], ...
        @(x) isnumeric(x) && isvector(x));
    addParameter(p, 'protectedLabels', [1 2 3], ...
        @(x) isnumeric(x) && isvector(x));
    addParameter(p, 'clearanceMm', 0.25, @isNonnegativeScalar);
    addParameter(p, 'partialFacePolicy', 'removeAnyVertex', ...
        @(x) ischar(x) || isstring(x));
    addParameter(p, 'errorOnProtectedOverlap', false, @isBoolLike);
    addParameter(p, 'inpolyhedronTol', 1e-9, @isPositiveScalar);
    addParameter(p, 'chunkSize', 4000, @isPositiveScalar);
    addParameter(p, 'showFigures', false, @isBoolLike);
    addParameter(p, 'saveFigures', false, @isBoolLike);
    addParameter(p, 'verbose', true, @isBoolLike);
    parse(p, varargin{:});

    opts = p.Results;
    opts.outputFile = expandUserPath(char(opts.outputFile));
    opts.force = logical(opts.force);
    opts.replaceableLabels = unique(round(double(opts.replaceableLabels(:))))';
    opts.protectedLabels = unique(round(double(opts.protectedLabels(:))))';
    opts.clearanceMm = double(opts.clearanceMm);
    opts.partialFacePolicy = normalizePartialFacePolicy(opts.partialFacePolicy);
    opts.errorOnProtectedOverlap = logical(opts.errorOnProtectedOverlap);
    opts.inpolyhedronTol = double(opts.inpolyhedronTol);
    opts.chunkSize = round(double(opts.chunkSize));
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

function policy = normalizePartialFacePolicy(policy)
    policy = lower(strtrim(char(policy)));
    policy = regexprep(policy, '[\s_\-]+', '');
    switch policy
        case {'removeanyvertex', 'anyvertex', 'conservative'}
            policy = 'removeAnyVertex';
        case {'removecentroid', 'centroid', 'centroidonly'}
            policy = 'removeCentroid';
        case {'reportonly', 'none'}
            policy = 'reportOnly';
        otherwise
            error('acsResolveRoastMeshNativeImplantOverlaps:BadPolicy', ...
                'partialFacePolicy must be removeAnyVertex, removeCentroid, or reportOnly.');
    end
end

function addLocalDependencies()
    repoRoot = fileparts(fileparts(mfilename('fullpath')));
    addpath(repoRoot);
    addpath(fullfile(repoRoot, 'acsUtilities'));
    addpath(fullfile(repoRoot, 'capMaker', 'core'));
end

function request = readRequest(value)
    if ischar(value) || isstring(value)
        fileName = expandUserPath(char(value));
        if exist(fileName, 'file') ~= 2
            error('acsResolveRoastMeshNativeImplantOverlaps:MissingFile', ...
                'Request file not found: %s', fileName);
        end
        S = load(fileName);
        if isfield(S, 'out')
            request = S.out;
        elseif isfield(S, 'outForSave')
            request = S.outForSave;
        else
            request = firstStruct(S);
        end
    elseif isstruct(value)
        request = value;
    else
        error('acsResolveRoastMeshNativeImplantOverlaps:BadRequest', ...
            'Request input must be a struct or MAT filename.');
    end
end

function requireRequestFields(request)
    if ~isfield(request, 'surfaceRecords') || isempty(request.surfaceRecords)
        error('acsResolveRoastMeshNativeImplantOverlaps:BadRequest', ...
            'Request lacks surfaceRecords.');
    end
    if ~isfield(request, 'combinedSurface') || ...
            ~isfield(request.combinedSurface, 'verticesMm')
        error('acsResolveRoastMeshNativeImplantOverlaps:BadRequest', ...
            'Request lacks combinedSurface vertices.');
    end
end

function fileName = defaultOutputFile(request)
    if isfield(request, 'outputFile') && ~isempty(request.outputFile)
        [folder, stem] = fileparts(request.outputFile);
    else
        folder = pwd;
        stem = 'roastMeshNativeRequest';
    end
    fileName = fullfile(folder, [stem '_implantResolved.mat']);
end

function out = loadExisting(fileName)
    S = load(fileName);
    if isfield(S, 'out')
        out = S.out;
    elseif isfield(S, 'outForSave')
        out = S.outForSave;
    else
        out = firstStruct(S);
    end
end

function [record, idx] = findTitaniumRecord(records)
    idx = [];
    record = [];
    for i = 1:numel(records)
        if strcmpi(records(i).role, 'extraTissueTitanium') || ...
                double(records(i).label) == 7
            idx = i;
            record = records(i);
            return;
        end
    end
end

function titanium = prepareTitaniumMesh(record, opts)
    titanium = struct();
    titanium.record = record;
    titanium.V = double(record.verticesMm);
    titanium.F = double(record.faces);
    titanium.TR = triangulation(titanium.F, titanium.V);
    titanium.normalRepair = 'not attempted';
    if exist('unifyOutwardNormalsRobust', 'file') == 2
        try
            titanium.TR = unifyOutwardNormalsRobust(titanium.TR);
            titanium.V = double(titanium.TR.Points);
            titanium.F = double(titanium.TR.ConnectivityList);
            titanium.normalRepair = 'unifyOutwardNormalsRobust';
        catch ME
            titanium.normalRepair = ['failed: ' ME.message];
        end
    end
    if exist('inpolyhedron', 'file') ~= 2
        error('acsResolveRoastMeshNativeImplantOverlaps:MissingInpolyhedron', ...
            'inpolyhedron.m is required for titanium overlap resolution.');
    end
    titanium.tol = opts.inpolyhedronTol;
    titanium.boundsMm = [min(titanium.V, [], 1); max(titanium.V, [], 1)];
end

function [recordsOut, resolution] = clearReplaceableSurfaces( ...
        recordsIn, titanium, titaniumIndex, opts)
    recordsOut = recordsIn;
    resolution = struct();
    resolution.status = 'completed';
    resolution.method = 'remove non-titanium faces inside/near preserved titanium mesh';
    resolution.coordinateFrame = 'roastPseudoWorldMm';
    resolution.titaniumSurfaceIndex = titaniumIndex;
    resolution.titaniumSurfaceName = recordsIn(titaniumIndex).name;
    resolution.clearanceMm = opts.clearanceMm;
    resolution.partialFacePolicy = opts.partialFacePolicy;
    resolution.titaniumNormalRepair = titanium.normalRepair;
    resolution.conformalInterfaceBuilt = false;
    resolution.nextRequirement = ['Build exact conformal material ', ...
        'interfaces or verify TetGen accepts the cleaned PLC.'];
    resolution.surfaceReports = struct([]);
    resolution.totalRemovedFaces = 0;
    resolution.totalProtectedFlags = 0;

    for i = 1:numel(recordsIn)
        if i == titaniumIndex
            if opts.verbose
                fprintf('  overlap %d/%d %-24s: titanium preserved.\n', ...
                    i, numel(recordsIn), recordsIn(i).name);
            end
            report = preservedTitaniumReport(recordsIn(i));
            resolution.surfaceReports = appendReport( ...
                resolution.surfaceReports, report);
            continue;
        end
        record = recordsIn(i);
        if opts.verbose
            fprintf('  overlap %d/%d %-24s: checking %d vertices / %d faces.\n', ...
                i, numel(recordsIn), record.name, ...
                size(record.verticesMm, 1), size(record.faces, 1));
        end
        stageTimer = tic;
        report = inspectSurfaceAgainstTitanium(record, titanium, opts);
        if report.isReplaceable && ~strcmpi(opts.partialFacePolicy, 'reportOnly')
            [record, compactInfo] = removeFacesFromRecord(record, ...
                report.facesToRemove);
            report.compaction = compactInfo;
            report.nOutputFaces = size(record.faces, 1);
            recordsOut(i) = record;
            resolution.totalRemovedFaces = resolution.totalRemovedFaces + ...
                report.nFacesRemoved;
        elseif report.isProtected && report.nFacesToClear > 0
            resolution.totalProtectedFlags = resolution.totalProtectedFlags + ...
                report.nFacesToClear;
        end
        resolution.surfaceReports = appendReport( ...
            resolution.surfaceReports, report);
        if opts.verbose
            fprintf(['    %s: %d faces flagged, %d removed, ', ...
                '%.1f s.\n'], record.name, report.nFacesToClear, ...
                report.nFacesRemoved, toc(stageTimer));
        end
    end

    if opts.errorOnProtectedOverlap && resolution.totalProtectedFlags > 0
        error('acsResolveRoastMeshNativeImplantOverlaps:ProtectedOverlap', ...
            ['Titanium overlaps/touches protected labels. Inspect ', ...
             'implantOverlapResolution.surfaceReports.']);
    end
end

function report = preservedTitaniumReport(record)
    report = emptySurfaceReport(record);
    report.action = 'preserved titanium surface';
    report.isTitanium = true;
end

function report = inspectSurfaceAgainstTitanium(record, titanium, opts)
    report = emptySurfaceReport(record);
    V = double(record.verticesMm);
    F = double(record.faces);
    report.isReplaceable = ismember(double(record.label), opts.replaceableLabels);
    report.isProtected = ismember(double(record.label), opts.protectedLabels);
    if isempty(V) || isempty(F)
        report.action = 'empty surface';
        return;
    end

    boundsPad = max(opts.clearanceMm, 0) + max(titanium.tol, eps);
    titaniumQueryBounds = titanium.boundsMm + [-boundsPad -boundsPad -boundsPad; ...
        boundsPad boundsPad boundsPad];
    vertexQuery = pointsInBounds(V, titaniumQueryBounds);
    C = faceCentroids(V, F);
    centroidQuery = pointsInBounds(C, titaniumQueryBounds);
    report.nVerticesInTitaniumRoi = nnz(vertexQuery);
    report.nCentroidsInTitaniumRoi = nnz(centroidQuery);
    if opts.verbose
        fprintf('    %s: titanium ROI keeps %d/%d vertices and %d/%d centroids.\n', ...
            record.name, report.nVerticesInTitaniumRoi, size(V, 1), ...
            report.nCentroidsInTitaniumRoi, size(C, 1));
    end

    if opts.verbose
        fprintf('    %s: testing vertices inside titanium.\n', record.name);
    end
    vertexInside = false(size(V, 1), 1);
    if any(vertexQuery)
        vertexInside(vertexQuery) = pointsInsideTitanium(V(vertexQuery, :), ...
            titanium, opts, [record.name ' vertices in titanium']);
    end
    if opts.verbose
        fprintf('    %s: testing face centroids inside titanium.\n', record.name);
    end
    centroidInside = false(size(C, 1), 1);
    if any(centroidQuery)
        centroidInside(centroidQuery) = pointsInsideTitanium(C(centroidQuery, :), ...
            titanium, opts, [record.name ' centroids in titanium']);
    end
    if opts.verbose
        fprintf('    %s: measuring centroid clearance to titanium.\n', record.name);
    end
    centroidDistance = inf(size(C, 1), 1);
    if any(centroidQuery)
        centroidDistance(centroidQuery) = nearestDistancesChunked( ...
            C(centroidQuery, :), titanium.V, opts.chunkSize, ...
            [record.name ' centroid -> titanium'], opts);
    end
    centroidNear = centroidDistance <= opts.clearanceMm;
    anyVertexInside = any(vertexInside(F), 2);

    switch opts.partialFacePolicy
        case 'removeAnyVertex'
            facesToClear = centroidInside | centroidNear | anyVertexInside;
        case 'removeCentroid'
            facesToClear = centroidInside | centroidNear;
        case 'reportOnly'
            facesToClear = centroidInside | centroidNear | anyVertexInside;
    end

    report.nVerticesInside = nnz(vertexInside);
    report.nCentroidsInside = nnz(centroidInside);
    report.nCentroidsNear = nnz(centroidNear);
    report.minCentroidDistanceMm = minOrNan(centroidDistance);
    report.p05CentroidDistanceMm = percentileLocal( ...
        centroidDistance(isfinite(centroidDistance)), 5);
    report.facesToRemove = facesToClear(:);
    report.nFacesToClear = nnz(facesToClear);
    report.nFacesRemoved = 0;
    report.removedFaceCentroidsMm = zeros(0, 3);
    if report.isReplaceable && ~strcmpi(opts.partialFacePolicy, 'reportOnly')
        report.nFacesRemoved = report.nFacesToClear;
        report.removedFaceCentroidsMm = sampleRows(C(facesToClear, :), 2000);
        report.action = 'cleared replaceable tissue faces';
    elseif report.isProtected && report.nFacesToClear > 0
        report.action = 'flagged protected tissue overlap/contact';
    elseif report.nFacesToClear > 0
        report.action = 'reported non-replaceable overlap/contact';
    else
        report.action = 'no action';
    end
end

function report = emptySurfaceReport(record)
    report = struct();
    report.name = record.name;
    report.role = record.role;
    report.label = double(record.label);
    report.isTitanium = false;
    report.isReplaceable = false;
    report.isProtected = false;
    report.nInputFaces = size(record.faces, 1);
    report.nOutputFaces = size(record.faces, 1);
    report.nVerticesInside = 0;
    report.nCentroidsInside = 0;
    report.nCentroidsNear = 0;
    report.nVerticesInTitaniumRoi = 0;
    report.nCentroidsInTitaniumRoi = 0;
    report.minCentroidDistanceMm = NaN;
    report.p05CentroidDistanceMm = NaN;
    report.nFacesToClear = 0;
    report.nFacesRemoved = 0;
    report.facesToRemove = false(size(record.faces, 1), 1);
    report.removedFaceCentroidsMm = zeros(0, 3);
    report.compaction = emptyCompactionInfo(record);
    report.action = '';
end

function info = emptyCompactionInfo(record)
    info = struct( ...
        'nInputFaces', size(record.faces, 1), ...
        'nRemovedFaces', 0, ...
        'nOutputFaces', size(record.faces, 1), ...
        'nInputVertices', size(record.verticesMm, 1), ...
        'nOutputVertices', size(record.verticesMm, 1));
end

function inside = pointsInsideTitanium(points, titanium, opts, progressLabel)
    if nargin < 4 || isempty(progressLabel)
        progressLabel = 'points inside titanium';
    end
    points = double(points);
    inside = false(size(points, 1), 1);
    if isempty(points)
        return;
    end
    doVerbose = opts.verbose && size(points, 1) > opts.chunkSize;
    nextPct = 0;
    stageTimer = tic;
    if doVerbose
        fprintf('      %s: %d query points.\n', ...
            progressLabel, size(points, 1));
    end
    for first = 1:opts.chunkSize:size(points, 1)
        last = min(size(points, 1), first + opts.chunkSize - 1);
        inside(first:last) = inpolyhedron(titanium.F, titanium.V, ...
            points(first:last, :), 'tol', titanium.tol);
        if doVerbose
            nextPct = maybePrintProgress(progressLabel, last, ...
                size(points, 1), nextPct, stageTimer, 10);
        end
    end
end

function C = faceCentroids(V, F)
    C = (V(F(:, 1), :) + V(F(:, 2), :) + V(F(:, 3), :)) ./ 3;
end

function tf = pointsInBounds(P, bounds)
    if isempty(P)
        tf = false(size(P, 1), 1);
        return;
    end
    tf = P(:, 1) >= bounds(1, 1) & P(:, 1) <= bounds(2, 1) & ...
         P(:, 2) >= bounds(1, 2) & P(:, 2) <= bounds(2, 2) & ...
         P(:, 3) >= bounds(1, 3) & P(:, 3) <= bounds(2, 3);
end

function [recordOut, info] = removeFacesFromRecord(record, removeFace)
    F = double(record.faces);
    V = double(record.verticesMm);
    keepFace = ~removeFace(:);
    Fkeep = F(keepFace, :);
    info = struct('nInputFaces', size(F, 1), ...
        'nRemovedFaces', nnz(removeFace), ...
        'nOutputFaces', size(Fkeep, 1), ...
        'nInputVertices', size(V, 1), ...
        'nOutputVertices', 0);
    recordOut = record;
    if isempty(Fkeep)
        recordOut.verticesMm = zeros(0, 3);
        recordOut.faces = zeros(0, 3);
        recordOut.nVertices = 0;
        recordOut.nFaces = 0;
        recordOut.boundsMm = nan(2, 3);
        recordOut.centroidMm = [nan nan nan];
        info.nOutputVertices = 0;
        return;
    end
    used = unique(Fkeep(:));
    map = zeros(size(V, 1), 1);
    map(used) = 1:numel(used);
    recordOut.verticesMm = V(used, :);
    recordOut.faces = reshape(map(Fkeep), size(Fkeep));
    recordOut.nVertices = size(recordOut.verticesMm, 1);
    recordOut.nFaces = size(recordOut.faces, 1);
    recordOut.boundsMm = [min(recordOut.verticesMm, [], 1); ...
        max(recordOut.verticesMm, [], 1)];
    recordOut.centroidMm = mean(recordOut.verticesMm, 1);
    info.nOutputVertices = recordOut.nVertices;
end

function reports = appendReport(reports, report)
    if isempty(reports)
        reports = report;
    else
        reports(end + 1, 1) = report;
    end
end

function [V, F, faceSurfaceIndex, faceLabels] = concatenateSurfaceRecords(records)
    V = zeros(0, 3);
    F = zeros(0, 3);
    faceSurfaceIndex = zeros(0, 1);
    faceLabels = zeros(0, 1);
    for i = 1:numel(records)
        if isempty(records(i).faces)
            continue;
        end
        faces = double(records(i).faces) + size(V, 1);
        V = [V; double(records(i).verticesMm)]; %#ok<AGROW>
        F = [F; faces]; %#ok<AGROW>
        faceSurfaceIndex = [faceSurfaceIndex; ...
            repmat(i, size(faces, 1), 1)]; %#ok<AGROW>
        faceLabels = [faceLabels; ...
            repmat(double(records(i).label), size(faces, 1), 1)]; %#ok<AGROW>
    end
end

function quality = updateQuality(qualityIn, records, verticesMm, faces, resolution)
    quality = qualityIn;
    quality.nSurfaces = numel(records);
    quality.nVerticesCombined = size(verticesMm, 1);
    quality.nFacesCombined = size(faces, 1);
    if isempty(verticesMm)
        quality.boundsMm = nan(2, 3);
    else
        quality.boundsMm = [min(verticesMm, [], 1); max(verticesMm, [], 1)];
    end
    quality.implantOverlapResolution = struct( ...
        'totalRemovedFaces', resolution.totalRemovedFaces, ...
        'totalProtectedFlags', resolution.totalProtectedFlags, ...
        'conformalInterfaceBuilt', resolution.conformalInterfaceBuilt);
end

function resolution = noTitaniumResolution(opts)
    resolution = struct();
    resolution.status = 'skippedNoTitanium';
    resolution.method = 'none';
    resolution.coordinateFrame = 'roastPseudoWorldMm';
    resolution.clearanceMm = opts.clearanceMm;
    resolution.partialFacePolicy = opts.partialFacePolicy;
    resolution.conformalInterfaceBuilt = false;
    resolution.totalRemovedFaces = 0;
    resolution.totalProtectedFlags = 0;
    resolution.surfaceReports = struct([]);
end

function fig = makeQcFigure(recordsBefore, recordsAfter, titaniumIndex, ...
        resolution, opts, figVisible)
    fig = figure('Name', 'ROAST mesh-native implant overlap resolution QC', ...
        'NumberTitle', 'off', 'Color', 'w', 'Visible', figVisible, ...
        'Units', 'pixels', 'Position', [100 100 1400 720]);
    tl = tiledlayout(fig, 1, 2, 'Padding', 'compact', 'TileSpacing', 'compact');
    title(tl, 'ROAST mesh-native implant overlap resolution QC', ...
        'Interpreter', 'none', 'FontSize', 12, 'FontWeight', 'bold');
    ax1 = nexttile(tl);
    drawRecords(ax1, recordsBefore, titaniumIndex, true);
    title(ax1, 'Before clearing', 'Interpreter', 'none');
    ax2 = nexttile(tl);
    drawRecords(ax2, recordsAfter, titaniumIndex, false);
    drawRemovedCentroids(ax2, resolution);
    title(ax2, sprintf('After clearing: %d faces removed', ...
        resolution.totalRemovedFaces), 'Interpreter', 'none');
    annotation(fig, 'textbox', [0.02 0.01 0.96 0.055], ...
        'String', sprintf(['Titanium is preserved. Replaceable surfaces ', ...
        'clear faces inside/within %.2f mm of titanium. Magenta dots show ', ...
        'sampled removed-face centroids.'], opts.clearanceMm), ...
        'EdgeColor', 'none', 'Interpreter', 'none', 'FontSize', 9);
end

function drawRecords(ax, records, titaniumIndex, faintNonTitanium)
    hold(ax, 'on');
    for i = 1:numel(records)
        if isempty(records(i).faces)
            continue;
        end
        isTi = i == titaniumIndex || double(records(i).label) == 7;
        if isTi
            faceColor = [0.85 0 0];
            alphaValue = 0.80;
            edgeColor = 'none';
        else
            faceColor = colorForLabel(records(i).label);
            if faintNonTitanium
                alphaValue = 0.10;
            else
                alphaValue = 0.18;
            end
            edgeColor = 'none';
        end
        patch(ax, 'Faces', records(i).faces, ...
            'Vertices', records(i).verticesMm, ...
            'FaceColor', faceColor, ...
            'FaceAlpha', alphaValue, ...
            'EdgeColor', edgeColor, ...
            'FaceLighting', 'flat', ...
            'AmbientStrength', 0.75, ...
            'DiffuseStrength', 0.25, ...
            'SpecularStrength', 0);
    end
    axis(ax, 'equal');
    axis(ax, 'vis3d');
    grid(ax, 'on');
    xlabel(ax, 'x (mm)');
    ylabel(ax, 'y (mm)');
    zlabel(ax, 'z (mm)');
    view(ax, 35, 24);
    camlight(ax, 'headlight');
    lighting(ax, 'flat');
end

function drawRemovedCentroids(ax, resolution)
    if ~isfield(resolution, 'surfaceReports') || isempty(resolution.surfaceReports)
        return;
    end
    P = zeros(0, 3);
    for i = 1:numel(resolution.surfaceReports)
        if isfield(resolution.surfaceReports(i), 'removedFaceCentroidsMm') && ...
                ~isempty(resolution.surfaceReports(i).removedFaceCentroidsMm)
            P = [P; resolution.surfaceReports(i).removedFaceCentroidsMm]; %#ok<AGROW>
        end
    end
    if ~isempty(P)
        scatter3(ax, P(:, 1), P(:, 2), P(:, 3), 8, ...
            [1 0 1], 'filled', 'MarkerFaceAlpha', 0.45, ...
            'MarkerEdgeColor', 'none');
    end
end

function color = colorForLabel(labelValue)
    switch double(labelValue)
        case 1
            color = [0.00 0.75 0.95];
        case 2
            color = [1.00 0.20 0.12];
        case 3
            color = [0.15 0.30 0.95];
        case 4
            color = [1.00 0.78 0.02];
        case 5
            color = [0.05 0.75 0.25];
        case 6
            color = [0.45 0.45 0.45];
        otherwise
            color = [0.5 0.5 0.5];
    end
end

function saveResolvedRequest(out, opts)
    ensureDir(fileparts(opts.outputFile));
    outForSave = out;
    if isfield(outForSave, 'figure')
        outForSave = rmfield(outForSave, 'figure');
    end
    save(opts.outputFile, 'out', 'outForSave', '-v7.3');
    writeJsonReport(strrep(opts.outputFile, '.mat', '.json'), ...
        stripForJson(outForSave));
end

function printSummary(out, opts)
    if ~opts.verbose
        return;
    end
    fprintf('\nROAST mesh-native implant overlap resolution\n');
    fprintf('  output: %s\n', out.outputFile);
    r = out.implantOverlapResolution;
    fprintf('  status: %s\n', r.status);
    fprintf('  titanium policy: preserve titanium, clear replaceable tissue\n');
    fprintf('  removed faces: %d\n', r.totalRemovedFaces);
    fprintf('  protected flags: %d\n', r.totalProtectedFlags);
    if r.totalProtectedFlags > 0
        warning('acsResolveRoastMeshNativeImplantOverlaps:ProtectedFlags', ...
            ['Titanium touched/overlapped protected tissue samples. ', ...
             'Inspect implantOverlapResolution.surfaceReports.']);
    end
    if isfield(r, 'qcFigure') && ~isempty(r.qcFigure)
        fprintf('  QC figure: %s\n', r.qcFigure);
    end
end

function report = stripForJson(out)
    report = out;
    if isfield(report, 'surfaceRecords')
        for i = 1:numel(report.surfaceRecords)
            report.surfaceRecords(i).verticesMm = [];
            report.surfaceRecords(i).faces = [];
        end
    end
    if isfield(report, 'combinedSurface')
        fields = {'verticesMm', 'faces', 'faceSurfaceIndex', 'faceLabels'};
        for i = 1:numel(fields)
            if isfield(report.combinedSurface, fields{i})
                report.combinedSurface = rmfield(report.combinedSurface, fields{i});
            end
        end
    end
    if isfield(report, 'implantOverlapResolution') && ...
            isfield(report.implantOverlapResolution, 'surfaceReports')
        for i = 1:numel(report.implantOverlapResolution.surfaceReports)
            report.implantOverlapResolution.surfaceReports(i).facesToRemove = [];
            report.implantOverlapResolution.surfaceReports(i).removedFaceCentroidsMm = [];
        end
    end
end

function D = nearestDistancesChunked(Q, T, chunkSize, progressLabel, opts)
    if nargin < 4 || isempty(progressLabel)
        progressLabel = 'nearest distance';
    end
    if nargin < 5 || ~isstruct(opts)
        opts = struct('verbose', false);
    end
    if isempty(Q) || isempty(T)
        D = nan(size(Q, 1), 1);
        return;
    end
    D = inf(size(Q, 1), 1);
    doVerbose = isfield(opts, 'verbose') && opts.verbose && ...
        size(Q, 1) > chunkSize;
    nextPct = 0;
    stageTimer = tic;
    if doVerbose
        fprintf('      %s: %d query x %d target points.\n', ...
            progressLabel, size(Q, 1), size(T, 1));
    end
    for first = 1:chunkSize:size(Q, 1)
        last = min(size(Q, 1), first + chunkSize - 1);
        q = Q(first:last, :);
        best = inf(size(q, 1), 1);
        for tFirst = 1:chunkSize:size(T, 1)
            tLast = min(size(T, 1), tFirst + chunkSize - 1);
            t = T(tFirst:tLast, :);
            dx = q(:, 1) - t(:, 1)';
            dy = q(:, 2) - t(:, 2)';
            dz = q(:, 3) - t(:, 3)';
            best = min(best, min(dx .^ 2 + dy .^ 2 + dz .^ 2, [], 2));
        end
        D(first:last) = sqrt(best);
        if doVerbose
            nextPct = maybePrintProgress(progressLabel, last, size(Q, 1), ...
                nextPct, stageTimer, 10);
        end
    end
end

function nextPct = maybePrintProgress(label, doneCount, totalCount, nextPct, ...
        stageTimer, pctStep)
    if totalCount <= 0
        return;
    end
    pct = floor(100 * double(doneCount) / double(totalCount));
    if pct < nextPct && doneCount < totalCount
        return;
    end
    fprintf('      %s: %d%% (%d/%d), %.1f s elapsed.\n', ...
        label, min(100, pct), doneCount, totalCount, toc(stageTimer));
    while nextPct <= pct
        nextPct = nextPct + pctStep;
    end
    if doneCount >= totalCount && nextPct <= 100
        nextPct = 101;
    end
end

function rows = sampleRows(rows, maxRows)
    if size(rows, 1) <= maxRows
        return;
    end
    idx = unique(round(linspace(1, size(rows, 1), maxRows)));
    rows = rows(idx, :);
end

function value = minOrNan(x)
    x = x(isfinite(x));
    if isempty(x)
        value = NaN;
    else
        value = min(x);
    end
end

function p = percentileLocal(x, pct)
    x = sort(double(x(:)));
    x = x(isfinite(x));
    if isempty(x)
        p = NaN;
        return;
    end
    pct = max(0, min(100, pct));
    pos = 1 + (numel(x) - 1) * pct / 100;
    lo = floor(pos);
    hi = ceil(pos);
    if lo == hi
        p = x(lo);
    else
        p = x(lo) + (pos - lo) * (x(hi) - x(lo));
    end
end

function writeJsonReport(fileName, report)
    try
        fid = fopen(fileName, 'w');
        if fid < 0
            return;
        end
        cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
        fprintf(fid, '%s', jsonencode(report, 'PrettyPrint', true));
    catch
    end
end

function saveQcFigure(fig, fileName)
    try
        exportgraphics(fig, fileName, 'Resolution', 220);
    catch
        saveas(fig, fileName);
    end
end

function value = optionalCharField(S, fieldName, defaultValue)
    value = defaultValue;
    if isstruct(S) && isfield(S, fieldName) && ~isempty(S.(fieldName))
        value = char(S.(fieldName));
    end
end

function S = firstStruct(raw)
    names = fieldnames(raw);
    for i = 1:numel(names)
        if isstruct(raw.(names{i}))
            S = raw.(names{i});
            return;
        end
    end
    error('acsResolveRoastMeshNativeImplantOverlaps:NoStructInFile', ...
        'MAT file does not contain a struct.');
end

function ensureDir(folder)
    if isempty(folder)
        return;
    end
    if exist(folder, 'dir') ~= 7
        mkdir(folder);
    end
end

function fileName = expandUserPath(fileName)
    if isempty(fileName)
        return;
    end
    fileName = char(fileName);
    if startsWith(fileName, '~')
        fileName = fullfile(char(java.lang.System.getProperty('user.home')), ...
            fileName(2:end));
    end
end

function name = getFileName(fileName)
    [~, stem, ext] = fileparts(fileName);
    name = [stem ext];
end

function stem = stripMatExtension(fileName)
    [~, stem, ext] = fileparts(fileName);
    if strcmpi(ext, '.mat')
        return;
    end
    stem = [stem ext];
end
