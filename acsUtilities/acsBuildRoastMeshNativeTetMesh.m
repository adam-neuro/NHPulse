function out = acsBuildRoastMeshNativeTetMesh(requestIn, varargin)
% ACSBUILDROASTMESHNATIVETETMESH Experimental surface-native ROAST mesher.
%
% out = acsBuildRoastMeshNativeTetMesh(meshNativeRequest)
% loads an acsPrepareRoastMeshNativeRequest product, calls iso2mesh/TetGen
% on the concatenated labeled surfaces, remaps TetGen region IDs back to
% ROAST tissue labels, and writes ROAST-style node/elem/face/.msh outputs.
%
% This is intentionally not called by roast.m yet. It is a development
% adapter for testing whether the mesh-native surface bundle can replace
% the voxel-derived meshing step.

    if nargin < 1 || isempty(requestIn)
        error('acsBuildRoastMeshNativeTetMesh:MissingRequest', ...
            'Provide an acsPrepareRoastMeshNativeRequest struct or MAT file.');
    end
    opts = parseInputs(varargin{:});
    addLocalDependencies();
    request = readRequest(requestIn);
    requireRequestFields(request);
    enforceImplantOverlapResolution(request, opts);

    if isempty(opts.outputPrefix)
        opts.outputPrefix = defaultOutputPrefix(request);
    end
    matFile = [opts.outputPrefix '.mat'];
    if exist(matFile, 'file') == 2 && ~opts.force
        out = loadExisting(matFile);
        if opts.verbose
            fprintf('ROAST mesh-native tet mesh already exists; reusing %s\n', ...
                matFile);
        end
        return;
    end

    V = double(request.combinedSurface.verticesMm);
    F = double(request.combinedSurface.faces);
    faceLabels = double(request.combinedSurface.faceLabels(:));
    if size(F, 1) ~= numel(faceLabels)
        error('acsBuildRoastMeshNativeTetMesh:BadFaceLabels', ...
            'combinedSurface.faceLabels must match the number of faces.');
    end
    FwithLabels = [F, faceLabels];
    regionPoints = double(request.meshContract.regionSeedPointsMm);
    regionMap = makeRegionMap(request);
    topologySummary = makeTopologySummary(request, F);

    if opts.verbose
        fprintf('\nExperimental ROAST mesh-native tetrahedral mesh\n');
        fprintf('  surfaces: %d faces, %d vertices\n', size(F, 1), size(V, 1));
        fprintf('  region seeds: %d\n', size(regionPoints, 1));
        fprintf('  execute TetGen: %d\n', opts.execute);
        fprintf('  output prefix: %s\n', opts.outputPrefix);
        printSurfaceRegionSummary(request, regionMap);
        printTopologySummary(topologySummary);
    end

    if ~opts.execute
        out = makeDryRunOutput(request, opts, V, FwithLabels, regionMap, ...
            topologySummary);
        ensureDir(fileparts(matFile));
        save(matFile, 'out', '-v7.3');
        writeJsonReport([opts.outputPrefix '_dryRun.json'], out);
        if opts.verbose
            fprintf('  dry-run report: %s\n', matFile);
            fprintf('  dry-run JSON: %s\n', [opts.outputPrefix '_dryRun.json']);
        end
        return;
    end
    enforceWatertightForExecution(topologySummary, opts);

    maxvol = double(opts.maxvol);
    if isempty(maxvol)
        maxvol = request.meshContract.meshOptions.maxvol;
    end
    if isempty(maxvol) || ~isfinite(maxvol) || maxvol <= 0
        maxvol = 10;
    end

    [node, elemRaw, face] = surf2mesh(V, FwithLabels, [], [], ...
        opts.keepRatio, maxvol, regionPoints, [], 0);
    elem = remapElementRegions(elemRaw, regionMap);
    meshNames = roastMeshNames(max(elem(:, 5)), regionMap);

    ensureDir(fileparts(matFile));
    savemsh(node(:, 1:3), elem, [opts.outputPrefix '.msh'], meshNames);
    save(matFile, 'node', 'elem', 'face', 'request', 'regionMap', ...
        'opts', '-v7.3');

    out = struct();
    out.createdOn = char(datetime('now'));
    out.type = 'roastMeshNativeTetMesh';
    out.requestFile = optionalCharField(request, 'outputFile', '');
    out.outputPrefix = opts.outputPrefix;
    out.matFile = matFile;
    out.mshFile = [opts.outputPrefix '.msh'];
    out.coordinateFrame = 'roastPseudoWorldMm';
    out.nodeCount = size(node, 1);
    out.elemCount = size(elem, 1);
    out.faceCount = size(face, 1);
    out.regionMap = regionMap;
    out.meshNames = meshNames;
    out.topologySummary = topologySummary;
    out.options = opts;

    outForSave = out; %#ok<NASGU>
    save([opts.outputPrefix '_report.mat'], 'out', 'outForSave', '-v7.3');
    writeJsonReport([opts.outputPrefix '_report.json'], out);

    if opts.verbose
        fprintf('  node/elem/face MAT: %s\n', matFile);
        fprintf('  Gmsh mesh: %s\n', out.mshFile);
    end
end

function opts = parseInputs(varargin)
    p = inputParser;
    p.FunctionName = 'acsBuildRoastMeshNativeTetMesh';
    addParameter(p, 'outputPrefix', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'force', false, @isBoolLike);
    addParameter(p, 'execute', true, @isBoolLike);
    addParameter(p, 'keepRatio', 1, @(x) isnumeric(x) && isscalar(x) && ...
        isfinite(x) && x > 0 && x <= 1);
    addParameter(p, 'maxvol', [], @(x) isempty(x) || ...
        (isnumeric(x) && isscalar(x) && isfinite(x) && x > 0));
    addParameter(p, 'allowUnresolvedImplantOverlaps', false, @isBoolLike);
    addParameter(p, 'allowNonWatertightSurfaces', false, @isBoolLike);
    addParameter(p, 'verbose', true, @isBoolLike);
    parse(p, varargin{:});

    opts = p.Results;
    opts.outputPrefix = expandUserPath(char(opts.outputPrefix));
    opts.force = logical(opts.force);
    opts.execute = logical(opts.execute);
    opts.keepRatio = double(opts.keepRatio);
    if ~isempty(opts.maxvol)
        opts.maxvol = double(opts.maxvol);
    end
    opts.allowUnresolvedImplantOverlaps = logical( ...
        opts.allowUnresolvedImplantOverlaps);
    opts.allowNonWatertightSurfaces = logical( ...
        opts.allowNonWatertightSurfaces);
    opts.verbose = logical(opts.verbose);
end

function tf = isBoolLike(x)
    tf = (islogical(x) || isnumeric(x)) && isscalar(x);
end

function addLocalDependencies()
    repoRoot = fileparts(fileparts(mfilename('fullpath')));
    addpath(repoRoot);
    addpath(fullfile(repoRoot, 'acsUtilities'));
    isoDir = fullfile(repoRoot, 'lib', 'iso2mesh');
    if exist(isoDir, 'dir') == 7
        addpath(isoDir);
    end
end

function request = readRequest(value)
    if ischar(value) || isstring(value)
        fileName = expandUserPath(char(value));
        if exist(fileName, 'file') ~= 2
            error('acsBuildRoastMeshNativeTetMesh:MissingFile', ...
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
        error('acsBuildRoastMeshNativeTetMesh:BadRequest', ...
            'Request input must be a struct or MAT filename.');
    end
end

function requireRequestFields(request)
    needed = {'combinedSurface', 'meshContract'};
    for i = 1:numel(needed)
        if ~isfield(request, needed{i}) || isempty(request.(needed{i}))
            error('acsBuildRoastMeshNativeTetMesh:BadRequest', ...
                'Request lacks required field "%s".', needed{i});
        end
    end
    neededCombined = {'verticesMm', 'faces', 'faceLabels'};
    for i = 1:numel(neededCombined)
        if ~isfield(request.combinedSurface, neededCombined{i}) || ...
                isempty(request.combinedSurface.(neededCombined{i}))
            error('acsBuildRoastMeshNativeTetMesh:BadRequest', ...
                'combinedSurface lacks "%s".', neededCombined{i});
        end
    end
    if ~isfield(request.meshContract, 'regionSeedPointsMm') || ...
            isempty(request.meshContract.regionSeedPointsMm)
        error('acsBuildRoastMeshNativeTetMesh:MissingRegions', ...
            'Mesh-native request has no region seeds.');
    end
end

function enforceImplantOverlapResolution(request, opts)
    hasTitanium = requestHasTitanium(request);
    hasResolution = isfield(request, 'implantOverlapResolution') && ...
        ~isempty(request.implantOverlapResolution);
    if hasTitanium && ~hasResolution && ~opts.allowUnresolvedImplantOverlaps
        error('acsBuildRoastMeshNativeTetMesh:UnresolvedImplantOverlaps', ...
            ['Mesh-native request includes titanium but has not been ', ...
             'passed through acsResolveRoastMeshNativeImplantOverlaps. ', ...
             'Use the resolved request, or set ', ...
             'allowUnresolvedImplantOverlaps=true for a diagnostic-only run.']);
    end
end

function tf = requestHasTitanium(request)
    tf = false;
    if isfield(request, 'surfaceRecords') && ~isempty(request.surfaceRecords)
        labels = [request.surfaceRecords.label];
        roles = {request.surfaceRecords.role};
        tf = any(double(labels) == 7) || ...
            any(strcmpi(roles, 'extraTissueTitanium'));
    elseif isfield(request, 'overlapPolicy') && ...
            isfield(request.overlapPolicy, 'hasTitanium')
        tf = logical(request.overlapPolicy.hasTitanium);
    end
end

function prefix = defaultOutputPrefix(request)
    if isfield(request, 'outputFile') && ~isempty(request.outputFile)
        [folder, stem] = fileparts(request.outputFile);
    elseif isfield(request, 'bundleFile') && ~isempty(request.bundleFile)
        [folder, stem] = fileparts(request.bundleFile);
    else
        folder = pwd;
        stem = 'roastMeshNativeRequest';
    end
    prefix = fullfile(folder, [stem '_tetMesh']);
end

function out = loadExisting(fileName)
    S = load(fileName);
    if isfield(S, 'out')
        out = S.out;
    elseif all(isfield(S, {'node', 'elem', 'face'}))
        out = struct('type', 'roastMeshNativeTetMesh', ...
            'matFile', fileName, ...
            'nodeCount', size(S.node, 1), ...
            'elemCount', size(S.elem, 1), ...
            'faceCount', size(S.face, 1));
    else
        out = firstStruct(S);
    end
end

function regionMap = makeRegionMap(request)
    regionMap = struct();
    regionMap.regionIds = double(request.meshContract.regionIds(:));
    regionMap.labels = double(request.meshContract.regionLabels(:));
    regionMap.names = request.meshContract.regionNames(:);
    if numel(regionMap.regionIds) ~= numel(regionMap.labels)
        error('acsBuildRoastMeshNativeTetMesh:BadRegionMap', ...
            'Region IDs and labels have different lengths.');
    end
end

function elem = remapElementRegions(elemRaw, regionMap)
    elem = double(elemRaw);
    if size(elem, 2) < 5
        error('acsBuildRoastMeshNativeTetMesh:NoRegionAttributes', ...
            'TetGen did not return region attributes on elements.');
    end
    rawRegion = elem(:, 5);
    mapped = nan(size(rawRegion));
    for i = 1:numel(regionMap.regionIds)
        mapped(rawRegion == regionMap.regionIds(i)) = regionMap.labels(i);
    end
    if any(~isfinite(mapped))
        missing = unique(rawRegion(~isfinite(mapped)));
        error('acsBuildRoastMeshNativeTetMesh:UnmappedRegion', ...
            'Tet mesh contains unmapped region ID(s): %s', ...
            mat2str(missing(:)'));
    end
    elem(:, 5) = mapped;
end

function names = roastMeshNames(maxLabel, regionMap)
    base = {'WHITE', 'GRAY', 'CSF', 'BONE', 'SKIN', 'AIR', 'TITANIUM'};
    n = max(maxLabel, numel(base));
    names = cell(1, n);
    for i = 1:n
        if i <= numel(base)
            names{i} = base{i};
        else
            names{i} = sprintf('LABEL%d', i);
        end
    end
    if nargin < 2 || ~isstruct(regionMap) || ...
            ~isfield(regionMap, 'labels') || ~isfield(regionMap, 'names')
        return;
    end
    for i = 1:numel(regionMap.labels)
        label = round(double(regionMap.labels(i)));
        if label >= 1 && label <= numel(names)
            names{label} = upper(char(regionMap.names{i}));
        end
    end
end

function out = makeDryRunOutput(request, opts, V, FwithLabels, regionMap, ...
        topologySummary)
    out = struct();
    out.createdOn = char(datetime('now'));
    out.type = 'roastMeshNativeTetMeshDryRun';
    out.requestFile = optionalCharField(request, 'outputFile', '');
    out.outputPrefix = opts.outputPrefix;
    out.coordinateFrame = 'roastPseudoWorldMm';
    out.inputVertexCount = size(V, 1);
    out.inputFaceCount = size(FwithLabels, 1);
    out.inputBoundsMm = [min(V, [], 1); max(V, [], 1)];
    out.surfaceSummary = summarizeSurfaceRecords(request);
    out.faceLabelCounts = summarizeFaceLabels(FwithLabels(:, 4));
    out.regionMap = regionMap;
    out.regionSeedPointsMm = request.meshContract.regionSeedPointsMm;
    out.topologySummary = topologySummary;
    out.dryRunNote = ['This report validates the surface/region handoff ', ...
        'only. It does not contain gel/electrode domains and is not yet ', ...
        'sufficient for ROAST lead-field generation.'];
    out.options = opts;
end

function topology = makeTopologySummary(request, combinedFaces)
    topology = struct();
    topology.combined = meshTopologyFromFaces(combinedFaces);
    topology.surfaces = struct([]);
    if ~isfield(request, 'surfaceRecords') || isempty(request.surfaceRecords)
        return;
    end
    records = request.surfaceRecords;
    for i = 1:numel(records)
        item = meshTopologyFromFaces(double(records(i).faces));
        item.name = optionalCharField(records(i), 'name', sprintf('surface%d', i));
        item.role = optionalCharField(records(i), 'role', '');
        item.label = double(records(i).label);
        if isempty(topology.surfaces)
            topology.surfaces = item;
        else
            topology.surfaces(end + 1, 1) = item; %#ok<AGROW>
        end
    end
end

function topo = meshTopologyFromFaces(F)
    F = double(F);
    if isempty(F)
        topo = emptyTopology();
        return;
    end
    if size(F, 2) < 3
        error('acsBuildRoastMeshNativeTetMesh:BadTopologyFaces', ...
            'Surface faces must have at least three columns.');
    end
    F = F(:, 1:3);
    usedVertices = unique(F(:));
    edges = [F(:, [1 2]); F(:, [2 3]); F(:, [3 1])];
    edges = sort(edges, 2);
    [uniqueEdges, ~, edgeBin] = unique(edges, 'rows');
    edgeUseCount = accumarray(edgeBin, 1);

    topo = struct();
    topo.nVertices = numel(usedVertices);
    topo.nFaces = size(F, 1);
    topo.nEdges = size(uniqueEdges, 1);
    topo.boundaryEdgeCount = nnz(edgeUseCount == 1);
    topo.nonmanifoldEdgeCount = nnz(edgeUseCount > 2);
    topo.duplicateFaceCount = countDuplicateFaces(F);
    topo.eulerCharacteristic = topo.nVertices - topo.nEdges + topo.nFaces;
    topo.isEdgeClosed = topo.boundaryEdgeCount == 0;
    topo.isEdgeManifold = topo.nonmanifoldEdgeCount == 0;
    topo.isWatertightCandidate = topo.isEdgeClosed && topo.isEdgeManifold && ...
        topo.duplicateFaceCount == 0;
end

function topo = emptyTopology()
    topo = struct( ...
        'nVertices', 0, ...
        'nFaces', 0, ...
        'nEdges', 0, ...
        'boundaryEdgeCount', 0, ...
        'nonmanifoldEdgeCount', 0, ...
        'duplicateFaceCount', 0, ...
        'eulerCharacteristic', 0, ...
        'isEdgeClosed', true, ...
        'isEdgeManifold', true, ...
        'isWatertightCandidate', true);
end

function nDuplicate = countDuplicateFaces(F)
    if isempty(F)
        nDuplicate = 0;
        return;
    end
    sortedFaces = sort(double(F(:, 1:3)), 2);
    [~, uniqueRows] = unique(sortedFaces, 'rows');
    nDuplicate = size(F, 1) - numel(uniqueRows);
end

function printTopologySummary(topology)
    fprintf('  topology checks:\n');
    printOneTopology('combined PLC', topology.combined);
    if ~isfield(topology, 'surfaces') || isempty(topology.surfaces)
        return;
    end
    for i = 1:numel(topology.surfaces)
        item = topology.surfaces(i);
        label = sprintf('%s (%s)', item.name, item.role);
        printOneTopology(label, item);
    end
    openRows = find([topology.surfaces.boundaryEdgeCount] > 0 | ...
        [topology.surfaces.nonmanifoldEdgeCount] > 0 | ...
        [topology.surfaces.duplicateFaceCount] > 0);
    if ~isempty(openRows)
        warning('acsBuildRoastMeshNativeTetMesh:OpenOrNonmanifoldSurface', ...
            ['%d mesh-native surface(s) have boundary, duplicate, or ', ...
             'nonmanifold edges. TetGen may fail or leak material ', ...
             'regions unless these are patched or made conformal.'], ...
            numel(openRows));
    end
end

function enforceWatertightForExecution(topology, opts)
    if opts.allowNonWatertightSurfaces
        return;
    end
    badCombined = ~topology.combined.isWatertightCandidate;
    badSurfaces = false;
    if isfield(topology, 'surfaces') && ~isempty(topology.surfaces)
        badSurfaces = any(~[topology.surfaces.isWatertightCandidate]);
    end
    if badCombined || badSurfaces
        error('acsBuildRoastMeshNativeTetMesh:NonWatertightSurfaces', ...
            ['Mesh-native surfaces are not watertight/manifold. Rerun ', ...
             'with execute=false and inspect topologySummary, or set ', ...
             'allowNonWatertightSurfaces=true only for low-level ', ...
             'TetGen debugging.']);
    end
end

function printOneTopology(name, topo)
    status = 'closed';
    if ~topo.isWatertightCandidate
        status = 'open/nonmanifold';
    end
    fprintf('    %-38s %s: boundary %d, nonmanifold %d, duplicate faces %d\n', ...
        name, status, topo.boundaryEdgeCount, ...
        topo.nonmanifoldEdgeCount, topo.duplicateFaceCount);
end

function printSurfaceRegionSummary(request, regionMap)
    surfaces = summarizeSurfaceRecords(request);
    if ~isempty(surfaces)
        fprintf('  input surfaces:\n');
        for i = 1:numel(surfaces)
            fprintf('    %-24s label %2d role %-24s faces %6d\n', ...
                surfaces(i).name, surfaces(i).label, surfaces(i).role, ...
                surfaces(i).nFaces);
        end
    end
    if ~isempty(regionMap.regionIds)
        fprintf('  region map:\n');
        for i = 1:numel(regionMap.regionIds)
            fprintf('    region %2d -> label %2d %s\n', ...
                regionMap.regionIds(i), regionMap.labels(i), ...
                regionMap.names{i});
        end
    end
end

function summary = summarizeSurfaceRecords(request)
    summary = struct([]);
    if ~isfield(request, 'surfaceRecords') || isempty(request.surfaceRecords)
        return;
    end
    records = request.surfaceRecords;
    for i = 1:numel(records)
        item = struct();
        item.name = optionalCharField(records(i), 'name', sprintf('surface%d', i));
        item.role = optionalCharField(records(i), 'role', '');
        item.label = double(records(i).label);
        if isfield(records(i), 'nVertices') && ~isempty(records(i).nVertices)
            item.nVertices = double(records(i).nVertices);
        else
            item.nVertices = size(records(i).verticesMm, 1);
        end
        if isfield(records(i), 'nFaces') && ~isempty(records(i).nFaces)
            item.nFaces = double(records(i).nFaces);
        else
            item.nFaces = size(records(i).faces, 1);
        end
        if isfield(records(i), 'boundsMm') && ~isempty(records(i).boundsMm)
            item.boundsMm = double(records(i).boundsMm);
        else
            item.boundsMm = [min(records(i).verticesMm, [], 1); ...
                max(records(i).verticesMm, [], 1)];
        end
        if isempty(summary)
            summary = item;
        else
            summary(end + 1, 1) = item; %#ok<AGROW>
        end
    end
end

function counts = summarizeFaceLabels(faceLabels)
    labels = unique(double(faceLabels(:)))';
    counts = repmat(struct('label', [], 'nFaces', []), numel(labels), 1);
    for i = 1:numel(labels)
        counts(i).label = labels(i);
        counts(i).nFaces = nnz(double(faceLabels(:)) == labels(i));
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
    error('acsBuildRoastMeshNativeTetMesh:NoStructInFile', ...
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
