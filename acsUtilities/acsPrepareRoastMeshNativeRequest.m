function out = acsPrepareRoastMeshNativeRequest(bundleIn, varargin)
% ACSPREPAREROASTMESHNATIVEREQUEST Prepare surface inputs for ROAST meshing.
%
% out = acsPrepareRoastMeshNativeRequest(bundle)
% converts an acsBuildRoastSurfaceBundle product from T1 voxel coordinates
% into ROAST's pseudo-world millimeter frame, concatenates the selected
% tissue surfaces, and stores region seed points/label metadata for the
% mesh-native ROAST path.
%
% This utility intentionally stops before tetrahedral meshing. It creates a
% reproducible handoff object for the next adapter that will call iso2mesh
% and write ROAST-compatible node/elem/face/.msh files.

    if nargin < 1 || isempty(bundleIn)
        error('acsPrepareRoastMeshNativeRequest:MissingBundle', ...
            'Provide an acsBuildRoastSurfaceBundle struct or MAT file.');
    end
    opts = parseInputs(varargin{:});
    addLocalDependencies();

    bundle = readBundle(bundleIn);
    if isempty(opts.outputFile)
        opts.outputFile = defaultOutputFile(bundle);
    end
    if exist(opts.outputFile, 'file') == 2 && ~opts.force
        out = loadExisting(opts.outputFile);
        if opts.verbose
            fprintf('ROAST mesh-native request already exists; reusing %s\n', ...
                opts.outputFile);
        end
        return;
    end

    requireBundleFields(bundle);
    if opts.verbose
        fprintf('\nPreparing ROAST mesh-native request.\n');
        fprintf('  bundle: %s\n', optionalCharField(bundle, 'outputFile', 'workspace struct'));
        fprintf('  mask: %s\n', bundle.maskFile);
    end
    stageTimer = tic;
    Vmask = spm_vol(bundle.maskFile);
    Vmask = Vmask(1);
    labels = uint8(round(spm_read_vols(Vmask)));
    voxelSize = voxelSizesFromMat(Vmask.mat);
    if opts.verbose
        fprintf('  read label volume in %.1f s; voxel size [%.3g %.3g %.3g] mm.\n', ...
            toc(stageTimer), voxelSize(1), voxelSize(2), voxelSize(3));
    end

    stageTimer = tic;
    surfaceRecords = makeSurfaceRecords(bundle.surfaces, voxelSize, opts);
    if opts.verbose
        fprintf('  selected/mapped %d surface records in %.1f s.\n', ...
            numel(surfaceRecords), toc(stageTimer));
    end
    stageTimer = tic;
    [verticesMm, faces, faceSurfaceIndex, faceLabels] = ...
        concatenateSurfaceRecords(surfaceRecords);
    if opts.verbose
        fprintf('  concatenated request PLC in %.1f s (%d vertices, %d faces).\n', ...
            toc(stageTimer), size(verticesMm, 1), size(faces, 1));
    end
    stageTimer = tic;
    regionSeeds = makeRegionSeeds(labels, surfaceRecords, voxelSize, opts);
    if opts.verbose
        fprintf('  prepared %d region seed(s) in %.1f s.\n', ...
            numel(regionSeeds), toc(stageTimer));
    end
    contract = makeMeshContract(surfaceRecords, regionSeeds, opts);
    quality = makeQualitySummary(surfaceRecords, regionSeeds, verticesMm, faces);

    out = struct();
    out.createdOn = char(datetime('now'));
    out.type = 'roastMeshNativeRequest';
    out.bundleFile = optionalCharField(bundle, 'outputFile', '');
    out.bundleType = optionalCharField(bundle, 'type', '');
    out.maskFile = bundle.maskFile;
    out.t1File = optionalCharField(bundle, 't1File', '');
    out.coordinateFrame = 'roastPseudoWorldMm';
    out.description = ['Surface and region-seed request for the ', ...
        'mesh-native ROAST adapter.'];
    out.voxelSizeMm = voxelSize;
    out.surfaceRecords = surfaceRecords;
    out.combinedSurface = struct( ...
        'verticesMm', verticesMm, ...
        'faces', faces, ...
        'faceSurfaceIndex', faceSurfaceIndex, ...
        'faceLabels', faceLabels);
    out.regionSeeds = regionSeeds;
    out.meshContract = contract;
    out.overlapPolicy = makeOverlapPolicy(surfaceRecords);
    out.quality = quality;
    out.outputFile = opts.outputFile;
    out.options = opts;

    ensureDir(fileparts(opts.outputFile));
    outForSave = out; %#ok<NASGU>
    if opts.verbose
        fprintf('  saving mesh-native request MAT/JSON reports.\n');
    end
    stageTimer = tic;
    save(opts.outputFile, 'out', 'outForSave', '-v7.3');
    writeJsonReport(strrep(opts.outputFile, '.mat', '.json'), stripForJson(out));
    if opts.verbose
        fprintf('  saved mesh-native request reports in %.1f s.\n', toc(stageTimer));
    end

    if opts.verbose
        printSummary(out);
    end
end

function opts = parseInputs(varargin)
    p = inputParser;
    p.FunctionName = 'acsPrepareRoastMeshNativeRequest';
    addParameter(p, 'outputFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'force', false, @isBoolLike);
    addParameter(p, 'includeTitanium', true, @isBoolLike);
    addParameter(p, 'includeReferenceScalp', false, @isBoolLike);
    addParameter(p, 'tissueLabels', [1 2 3 4 5 6], ...
        @(x) isnumeric(x) && isvector(x));
    addParameter(p, 'meshOptions', struct( ...
        'radbound', 5, 'angbound', 30, 'distbound', 0.3, ...
        'reratio', 3, 'maxvol', 10), @isstruct);
    addParameter(p, 'verbose', true, @isBoolLike);
    parse(p, varargin{:});

    opts = p.Results;
    opts.outputFile = expandUserPath(char(opts.outputFile));
    opts.force = logical(opts.force);
    opts.includeTitanium = logical(opts.includeTitanium);
    opts.includeReferenceScalp = logical(opts.includeReferenceScalp);
    opts.tissueLabels = unique(round(double(opts.tissueLabels(:))))';
    opts.meshOptions = opts.meshOptions;
    opts.verbose = logical(opts.verbose);
end

function tf = isBoolLike(x)
    tf = (islogical(x) || isnumeric(x)) && isscalar(x);
end

function addLocalDependencies()
    repoRoot = fileparts(fileparts(mfilename('fullpath')));
    addpath(repoRoot);
    addpath(fullfile(repoRoot, 'acsUtilities'));
    spmDir = fullfile(repoRoot, 'lib', 'spm12');
    isoDir = fullfile(repoRoot, 'lib', 'iso2mesh');
    if exist(spmDir, 'dir') == 7
        addpath(spmDir);
    end
    if exist(isoDir, 'dir') == 7
        addpath(isoDir);
    end
end

function bundle = readBundle(value)
    if ischar(value) || isstring(value)
        fileName = expandUserPath(char(value));
        if exist(fileName, 'file') ~= 2
            error('acsPrepareRoastMeshNativeRequest:MissingFile', ...
                'Bundle file not found: %s', fileName);
        end
        S = load(fileName);
        if isfield(S, 'out')
            bundle = S.out;
        elseif isfield(S, 'outForSave')
            bundle = S.outForSave;
        else
            bundle = firstStruct(S);
        end
    elseif isstruct(value)
        bundle = value;
    else
        error('acsPrepareRoastMeshNativeRequest:BadBundle', ...
            'Bundle input must be a struct or MAT filename.');
    end
end

function requireBundleFields(bundle)
    needed = {'maskFile', 'surfaces'};
    for i = 1:numel(needed)
        if ~isfield(bundle, needed{i}) || isempty(bundle.(needed{i}))
            error('acsPrepareRoastMeshNativeRequest:BadBundle', ...
                'Bundle lacks required field "%s".', needed{i});
        end
    end
    if exist(bundle.maskFile, 'file') ~= 2
        error('acsPrepareRoastMeshNativeRequest:MissingMask', ...
            'Bundle mask file not found: %s', bundle.maskFile);
    end
end

function fileName = defaultOutputFile(bundle)
    if isfield(bundle, 'outputFile') && ~isempty(bundle.outputFile)
        [folder, stem] = fileparts(bundle.outputFile);
    else
        folder = fileparts(bundle.maskFile);
        [~, stem] = fileparts(bundle.maskFile);
    end
    fileName = fullfile(folder, [stem '_meshNativeRequest.mat']);
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

function records = makeSurfaceRecords(surfaces, voxelSize, opts)
    records = struct([]);
    context = struct();
    context.hasWarpedSkinShell = false;
    if ~isempty(surfaces) && isfield(surfaces, 'role')
        context.hasWarpedSkinShell = any(strcmpi({surfaces.role}, ...
            'roastWarpedSkinShell'));
    end
    for i = 1:numel(surfaces)
        if ~surfaceIsMeshingInput(surfaces(i), opts, context)
            continue;
        end
        TR = surfaces(i).TR;
        Vmm = voxel1ToPseudoWorldMm(double(TR.Points), voxelSize);
        record = struct();
        record.name = surfaces(i).name;
        record.role = surfaces(i).role;
        record.label = double(surfaces(i).label);
        record.coordinateFrame = 'roastPseudoWorldMm';
        record.verticesMm = Vmm;
        record.faces = double(TR.ConnectivityList);
        record.nVertices = size(Vmm, 1);
        record.nFaces = size(record.faces, 1);
        record.boundsMm = [min(Vmm, [], 1); max(Vmm, [], 1)];
        record.centroidMm = mean(Vmm, 1);
        record.sourceCoordinateFrame = surfaces(i).coordinateFrame;
        records = appendRecord(records, record);
    end
end

function tf = surfaceIsMeshingInput(surface, opts, context)
    role = char(surface.role);
    label = double(surface.label);
    if nargin < 3 || ~isstruct(context)
        context = struct('hasWarpedSkinShell', false);
    end
    if strcmpi(role, 'capMakerScalpReference')
        tf = opts.includeReferenceScalp;
        return;
    end
    if strcmpi(role, 'roastWarpedSkinShell')
        tf = ismember(5, opts.tissueLabels);
        return;
    end
    if strcmpi(role, 'mriHardLabel') && label == 5
        tf = false;
        return;
    end
    if strcmpi(role, 'roastSkinOuterOriginal')
        tf = false;
        return;
    end
    if strcmpi(role, 'roastSkinInnerOriginal')
        tf = ~context.hasWarpedSkinShell && ismember(5, opts.tissueLabels);
        return;
    end
    if strcmpi(role, 'capMakerScalpOuter')
        tf = ~context.hasWarpedSkinShell && ismember(5, opts.tissueLabels);
        return;
    end
    if strcmpi(role, 'extraTissueTitanium')
        tf = opts.includeTitanium;
        return;
    end
    tf = ismember(label, opts.tissueLabels);
end

function records = appendRecord(records, record)
    if isempty(records)
        records = record;
    else
        records(end + 1, 1) = record;
    end
end

function Pmm = voxel1ToPseudoWorldMm(Pvox1, voxelSize)
    Pmm = bsxfun(@times, double(Pvox1) - 1, double(voxelSize(:)'));
end

function [V, F, faceSurfaceIndex, faceLabels] = concatenateSurfaceRecords(records)
    V = zeros(0, 3);
    F = zeros(0, 3);
    faceSurfaceIndex = zeros(0, 1);
    faceLabels = zeros(0, 1);
    for i = 1:numel(records)
        faces = records(i).faces + size(V, 1);
        V = [V; records(i).verticesMm]; %#ok<AGROW>
        F = [F; faces]; %#ok<AGROW>
        faceSurfaceIndex = [faceSurfaceIndex; ...
            repmat(i, size(faces, 1), 1)]; %#ok<AGROW>
        faceLabels = [faceLabels; ...
            repmat(records(i).label, size(faces, 1), 1)]; %#ok<AGROW>
    end
end

function seeds = makeRegionSeeds(labels, surfaceRecords, voxelSize, opts)
    labelNames = roastLabelNames();
    seedLabels = opts.tissueLabels;
    if opts.includeTitanium && ~isempty(surfaceRecords) && ...
            any([surfaceRecords.label] == 7)
        seedLabels = unique([seedLabels 7]);
    end
    seeds = struct([]);
    for labelValue = seedLabels(:)'
        seed = struct();
        seed.label = double(labelValue);
        seed.name = labelNameForValue(labelNames, labelValue);
        seed.regionId = numel(seeds) + 1;
        seed.pointMm = [];
        seed.source = '';
        if labelValue == 7
            idx = find([surfaceRecords.label] == 7, 1);
            if ~isempty(idx)
                seed.pointMm = surfaceRecords(idx).centroidMm;
                seed.source = 'titanium surface centroid';
            end
        else
            mask = labels == uint8(labelValue);
            if any(mask(:))
                seed.pointMm = robustVoxelSeedMm(mask, voxelSize);
                seed.source = 'ROAST hard-label mask median voxel';
            end
        end
        if isempty(seed.pointMm) || any(~isfinite(seed.pointMm))
            continue;
        end
        seeds = appendSeed(seeds, seed);
    end
end

function seedMm = robustVoxelSeedMm(mask, voxelSize)
    [i, j, k] = ind2sub(size(mask), find(mask));
    seedVoxel1 = median(double([i(:) j(:) k(:)]), 1);
    seedMm = voxel1ToPseudoWorldMm(seedVoxel1, voxelSize);
end

function seeds = appendSeed(seeds, seed)
    if isempty(seeds)
        seeds = seed;
    else
        seeds(end + 1, 1) = seed;
    end
end

function names = roastLabelNames()
    names = struct( ...
        'label', num2cell(1:7), ...
        'name', {'white', 'gray', 'csf', 'bone', 'skin', 'air', 'titanium'});
end

function name = labelNameForValue(names, labelValue)
    idx = find([names.label] == labelValue, 1);
    if isempty(idx)
        name = sprintf('label%d', labelValue);
    else
        name = names(idx).name;
    end
end

function contract = makeMeshContract(surfaceRecords, regionSeeds, opts)
    contract = struct();
    contract.intendedMesher = 'iso2mesh surf2mesh/tetgen';
    contract.status = 'preparedSurfacesOnly';
    contract.nextAdapter = 'acsBuildRoastMeshNativeTetMesh';
    if isempty(regionSeeds)
        contract.regionLabels = [];
        contract.regionIds = [];
        contract.regionNames = {};
        contract.regionSeedPointsMm = zeros(0, 3);
    else
        contract.regionLabels = [regionSeeds.label];
        contract.regionIds = [regionSeeds.regionId];
        contract.regionNames = {regionSeeds.name};
        contract.regionSeedPointsMm = vertcat(regionSeeds.pointMm);
    end
    if isempty(surfaceRecords)
        contract.surfaceNames = {};
        contract.surfaceRoles = {};
        contract.surfaceLabels = [];
    else
        contract.surfaceNames = {surfaceRecords.name};
        contract.surfaceRoles = {surfaceRecords.role};
        contract.surfaceLabels = [surfaceRecords.label];
    end
    contract.meshOptions = opts.meshOptions;
    contract.notes = { ...
        'The replacement outer scalp is capMakerScalpOuter.', ...
        ['If roastWarpedSkinShell is present, it is the preferred label-5 ', ...
         'meshing surface and the split skin interfaces are diagnostic.'], ...
        ['Without roastWarpedSkinShell, the retained provisional skin ', ...
         'inner boundary is roastSkinInnerOriginal.'], ...
        ['The original ROAST outer skin boundary is retained only for ', ...
         'diagnostics, not meshing.'], ...
        ['Titanium is a solid implanted domain; if it overlaps another ', ...
         'domain, the non-titanium domain must be trimmed or made ', ...
         'conformal to titanium, not vice versa.'], ...
        ['Region IDs are sequential in seed order and must be remapped ', ...
         'to ROAST tissue labels after tetrahedralization.']};
end

function policy = makeOverlapPolicy(surfaceRecords)
    policy = struct();
    policy.solidDominates = struct( ...
        'label', 7, ...
        'name', 'titanium', ...
        'surfaceRole', 'extraTissueTitanium', ...
        'replaceableLabels', [0 4 5 6], ...
        'protectedLabels', [1 2 3], ...
        'rule', ['when titanium overlaps or crosses another tissue, ', ...
                 'the other tissue is cleared/trimmed and the titanium ', ...
                 'surface is preserved']);
    policy.hasTitanium = ~isempty(surfaceRecords) && ...
        any(strcmpi({surfaceRecords.role}, 'extraTissueTitanium'));
    policy.nextMeshingRequirement = ['build conformal interfaces before ', ...
        'calling TetGen/iso2mesh; arbitrary intersecting surfaces are not ', ...
        'a valid PLC'];
end

function quality = makeQualitySummary(surfaceRecords, regionSeeds, verticesMm, faces)
    quality = struct();
    quality.nSurfaces = numel(surfaceRecords);
    quality.nVerticesCombined = size(verticesMm, 1);
    quality.nFacesCombined = size(faces, 1);
    if isempty(verticesMm)
        quality.boundsMm = nan(2, 3);
    else
        quality.boundsMm = [min(verticesMm, [], 1); max(verticesMm, [], 1)];
    end
    quality.nRegionSeeds = numel(regionSeeds);
    quality.missingCoreSurfaces = missingCoreSurfaces(surfaceRecords);
end

function missing = missingCoreSurfaces(records)
    if isempty(records)
        missing = {'mriHardLabel'; 'roastSkinInnerOriginal'; ...
            'capMakerScalpOuter'};
        return;
    end
    roles = {records.role};
    required = {'mriHardLabel', 'roastSkinInnerOriginal', 'capMakerScalpOuter'};
    missing = {};
    for i = 1:numel(required)
        if ~any(strcmpi(roles, required{i}))
            missing{end + 1, 1} = required{i}; %#ok<AGROW>
        end
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
        report.combinedSurface = rmfield(report.combinedSurface, ...
            {'verticesMm', 'faces', 'faceSurfaceIndex', 'faceLabels'});
    end
end

function printSummary(out)
    fprintf('\nROAST mesh-native request\n');
    fprintf('  output: %s\n', out.outputFile);
    fprintf('  bundle: %s\n', out.bundleFile);
    fprintf('  surfaces: %d, combined faces: %d\n', ...
        numel(out.surfaceRecords), out.quality.nFacesCombined);
    fprintf('  region seeds: ');
    if isempty(out.regionSeeds)
        fprintf('none\n');
    else
        fprintf('%s\n', strjoin(out.meshContract.regionNames, ', '));
    end
    if ~isempty(out.quality.missingCoreSurfaces)
        warning('acsPrepareRoastMeshNativeRequest:MissingCoreSurfaces', ...
            'Missing expected core surface role(s): %s', ...
            strjoin(out.quality.missingCoreSurfaces, ', '));
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

function voxelSize = voxelSizesFromMat(M)
    voxelSize = sqrt(sum(double(M(1:3, 1:3)) .^ 2, 1));
    voxelSize(~isfinite(voxelSize) | voxelSize <= 0) = 1;
end

function S = firstStruct(raw)
    names = fieldnames(raw);
    for i = 1:numel(names)
        if isstruct(raw.(names{i}))
            S = raw.(names{i});
            return;
        end
    end
    error('acsPrepareRoastMeshNativeRequest:NoStructInFile', ...
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
