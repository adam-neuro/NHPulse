function out = acsMakeRoastLabelsFromSurfaceBundle(bundleIn, varargin)
% ACSMAKEROASTLABELSFROMSURFACEBUNDLE Write ROAST labels from warped surfaces.
%
% out = acsMakeRoastLabelsFromSurfaceBundle(bundle)
% reads an acsBuildRoastSurfaceBundle product, voxelizes the morphed
% whole-skin shell into the bundle's ROAST/T1 label grid, optionally
% voxelizes the titanium headpost surface, and writes a derived ROAST hard
% label volume.
%
% Label convention:
%   0 background, 1 white, 2 gray, 3 CSF, 4 bone, 5 skin, 6 air,
%   7 titanium.
%
% The default composition is conservative:
%   - skin may replace only background or old skin labels;
%   - old skin outside the new skin shell is cleared to background;
%   - titanium may replace background, skin, bone, or air;
%   - white, gray, and CSF are protected and only reported.

    if nargin < 1 || isempty(bundleIn)
        error('acsMakeRoastLabelsFromSurfaceBundle:MissingBundle', ...
            'Provide an acsBuildRoastSurfaceBundle struct or MAT file.');
    end

    opts = parseInputs(varargin{:});
    addLocalDependencies();

    bundle = readBundle(bundleIn);
    if isempty(opts.baseMaskFile)
        opts.baseMaskFile = requiredCharField(bundle, 'maskFile', ...
            'surface bundle mask file');
    end
    if isempty(opts.t1File) && isfield(bundle, 't1File') && ...
            ~isempty(bundle.t1File)
        opts.t1File = char(bundle.t1File);
    end
    requireFile(opts.baseMaskFile, 'base ROAST hard-label mask');
    if isempty(opts.outputFile)
        opts.outputFile = defaultOutputFile(opts.baseMaskFile, opts.outputTag);
    end

    if exist(opts.outputFile, 'file') == 2 && ~opts.force
        out = loadExistingReport(opts.outputFile);
        if isempty(out)
            out = buildExistingReport(bundle, opts);
        end
        logMsg(opts, 'ROAST surface-derived label mask already exists; reusing %s', ...
            opts.outputFile);
        return;
    end

    logMsg(opts, '');
    logMsg(opts, 'Building ROAST hard labels from mesh-native surface bundle.');
    logMsg(opts, '  bundle: %s', optionalCharField(bundle, 'outputFile', ...
        'workspace struct'));
    logMsg(opts, '  base mask: %s', opts.baseMaskFile);

    Vmask = spm_vol(opts.baseMaskFile);
    Vmask = Vmask(1);
    labelsIn = uint8(round(spm_read_vols(Vmask)));
    labelsOut = labelsIn;
    dims = size(labelsIn);

    if numel(dims) < 3
        error('acsMakeRoastLabelsFromSurfaceBundle:BadMask', ...
            'Base ROAST hard-label mask must be 3-D: %s', opts.baseMaskFile);
    end
    dims = dims(1:3);

    skinInfo = emptyVoxelizationInfo('skin');
    skinApply = emptyApplyInfo('skin');
    skinSurface = struct([]);
    if opts.applySkin
        skinSurface = selectSurface(bundle.surfaces, opts.skinSurfaceRole, ...
            opts.skinLabelValue);
        if isempty(skinSurface)
            error('acsMakeRoastLabelsFromSurfaceBundle:MissingSkinSurface', ...
                'Could not find skin surface role "%s" in bundle.', ...
                opts.skinSurfaceRole);
        end
        skinCandidate = ismember(labelsIn, opts.skinWritableLabels);
        [skinMask, skinInfo] = voxelizeSurfaceRecord( ...
            skinSurface, dims, skinCandidate, opts, 'warped skin shell');
        [labelsOut, skinApply] = applySkinLabels( ...
            labelsIn, labelsOut, skinMask, opts);
    end

    titaniumInfo = emptyVoxelizationInfo('titanium');
    titaniumApply = emptyApplyInfo('titanium');
    titaniumSurface = struct([]);
    if opts.applyTitanium
        titaniumSurface = selectSurface(bundle.surfaces, ...
            opts.titaniumSurfaceRole, opts.titaniumLabelValue);
        if isempty(titaniumSurface)
            logMsg(opts, '  no titanium surface found; skipping titanium label.');
        else
            titaniumCandidate = true(dims);
            [titaniumMask, titaniumInfo] = voxelizeSurfaceRecord( ...
                titaniumSurface, dims, titaniumCandidate, opts, ...
                'titanium headpost');
            [labelsOut, titaniumApply] = applyTitaniumLabels( ...
                labelsOut, titaniumMask, opts);
        end
    end

    [labelsOut, skinCleanup] = cleanupSkinLabelComponents(labelsOut, opts);
    boundaryInfo = boundarySolidLabelInfo(labelsOut);
    if boundaryInfo.nBoundarySolidVoxels > 0
        warning('acsMakeRoastLabelsFromSurfaceBundle:SolidBoundaryLabels', ...
            ['Derived ROAST labels have %d solid tissue voxels on the ', ...
             'image boundary. ROAST electrode placement may be fragile unless ', ...
             'the source anatomy is padded.'], boundaryInfo.nBoundarySolidVoxels);
    end

    writeLabelVolume(opts.outputFile, Vmask, labelsOut, ...
        'ACS ROAST labels from morphed surface bundle');

    qcFile = '';
    fig = [];
    if opts.showFigures || opts.saveFigures
        figVisible = 'off';
        if opts.showFigures
            figVisible = 'on';
        end
        fig = makeQcFigure(opts.t1File, Vmask, labelsIn, labelsOut, ...
            skinApply, titaniumApply, opts, figVisible);
        if opts.saveFigures
            qcFile = fullfile(fileparts(opts.outputFile), 'qc', ...
                [stripNiftiExtension(getFileName(opts.outputFile)) '_qc.png']);
            ensureDir(fileparts(qcFile));
            saveQcFigure(fig, qcFile);
        end
        if ~opts.showFigures && isgraphics(fig)
            close(fig);
            fig = [];
        end
    end

    out = struct();
    out.createdOn = char(datetime('now'));
    out.type = 'roastSurfaceBundleLabelMask';
    out.bundleFile = optionalCharField(bundle, 'outputFile', '');
    out.baseMaskFile = opts.baseMaskFile;
    out.maskFile = opts.outputFile;
    out.outputFile = opts.outputFile;
    out.t1File = opts.t1File;
    out.imageSize = dims;
    out.skinSurface = summarizeSurfaceForReport(skinSurface);
    out.titaniumSurface = summarizeSurfaceForReport(titaniumSurface);
    out.skinVoxelization = skinInfo;
    out.titaniumVoxelization = titaniumInfo;
    out.skinApplication = skinApply;
    out.titaniumApplication = titaniumApply;
    out.skinCleanup = skinCleanup;
    out.boundaryInfo = boundaryInfo;
    out.voxelCountsBefore = labelVoxelCounts(labelsIn);
    out.voxelCountsAfter = labelVoxelCounts(labelsOut);
    out.extraTissues = [];
    out.conductivities = struct();
    out.material = struct();
    if opts.applyTitanium && ~isempty(titaniumSurface) && ...
            titaniumApply.writtenVoxelCount > 0
        out.extraTissues = struct( ...
            'label', opts.titaniumLabelValue, ...
            'name', opts.titaniumLabelName, ...
            'conductivityField', opts.titaniumConductivityField);
        out.material = ti6al4vMaterialSummary();
        out.conductivities = struct( ...
            'titanium', out.material.defaultConductivitySPerM);
    end
    out.qcFile = qcFile;
    out.options = opts;
    out.figure = fig;

    outForSave = out;
    if isfield(outForSave, 'figure')
        outForSave = rmfield(outForSave, 'figure');
    end
    reportFile = reportFileForMask(opts.outputFile);
    save(reportFile, 'outForSave', '-v7.3');
    writeJsonReport(strrep(reportFile, '.mat', '.json'), outForSave);
    printSummary(out, opts);
end

function opts = parseInputs(varargin)
    p = inputParser;
    p.FunctionName = 'acsMakeRoastLabelsFromSurfaceBundle';
    addParameter(p, 'baseMaskFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 't1File', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'outputFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'outputTag', 'surfaceBundle', @(x) ischar(x) || isstring(x));
    addParameter(p, 'force', false, @isBoolLike);
    addParameter(p, 'applySkin', true, @isBoolLike);
    addParameter(p, 'skinSurfaceRole', 'roastWarpedSkinShell', ...
        @(x) ischar(x) || isstring(x));
    addParameter(p, 'skinLabelValue', 5, @isLabelScalar);
    addParameter(p, 'skinWritableLabels', [0 5], ...
        @(x) isnumeric(x) && isvector(x));
    addParameter(p, 'clearOldSkinOutsideSurface', true, @isBoolLike);
    addParameter(p, 'cleanupSkinComponents', true, @isBoolLike);
    addParameter(p, 'skinCleanupMode', 'largest', @(x) ischar(x) || isstring(x));
    addParameter(p, 'minSkinComponentVoxels', 1000, @isNonnegativeScalar);
    addParameter(p, 'applyTitanium', true, @isBoolLike);
    addParameter(p, 'titaniumSurfaceRole', 'extraTissueTitanium', ...
        @(x) ischar(x) || isstring(x));
    addParameter(p, 'titaniumLabelValue', 7, @isLabelScalar);
    addParameter(p, 'titaniumLabelName', 'titanium', ...
        @(x) ischar(x) || isstring(x));
    addParameter(p, 'titaniumConductivityField', 'titanium', ...
        @(x) ischar(x) || isstring(x));
    addParameter(p, 'titaniumWritableLabels', [0 4 5 6], ...
        @(x) isnumeric(x) && isvector(x));
    addParameter(p, 'protectedLabels', [1 2 3], ...
        @(x) isnumeric(x) && isvector(x));
    addParameter(p, 'voxelizationPaddingVoxels', 1, @isNonnegativeScalar);
    addParameter(p, 'voxelizationAxes', [1 2 3], ...
        @(x) isnumeric(x) || ischar(x) || isstring(x));
    addParameter(p, 'voxelizationVoteRule', 'majority', ...
        @(x) ischar(x) || isstring(x));
    addParameter(p, 'gridChunkSizeZ', 12, @isPositiveScalar);
    addParameter(p, 'inpolyhedronTol', 0, @isNonnegativeScalar);
    addParameter(p, 'overlayAlpha', 0.45, ...
        @(x) isnumeric(x) && isscalar(x) && x >= 0 && x <= 1);
    addParameter(p, 'showFigures', false, @isBoolLike);
    addParameter(p, 'saveFigures', false, @isBoolLike);
    addParameter(p, 'verbose', true, @isBoolLike);
    parse(p, varargin{:});

    opts = p.Results;
    opts.baseMaskFile = expandUserPath(char(opts.baseMaskFile));
    opts.t1File = expandUserPath(char(opts.t1File));
    opts.outputFile = expandUserPath(char(opts.outputFile));
    opts.outputTag = safeName(char(opts.outputTag));
    opts.force = logical(opts.force);
    opts.applySkin = logical(opts.applySkin);
    opts.skinSurfaceRole = char(opts.skinSurfaceRole);
    opts.skinLabelValue = uint8(round(double(opts.skinLabelValue)));
    opts.skinWritableLabels = unique(uint8(round(double(opts.skinWritableLabels(:)'))));
    opts.clearOldSkinOutsideSurface = logical(opts.clearOldSkinOutsideSurface);
    opts.cleanupSkinComponents = logical(opts.cleanupSkinComponents);
    opts.skinCleanupMode = normalizeSkinCleanupMode(opts.skinCleanupMode);
    opts.minSkinComponentVoxels = round(double(opts.minSkinComponentVoxels));
    opts.applyTitanium = logical(opts.applyTitanium);
    opts.titaniumSurfaceRole = char(opts.titaniumSurfaceRole);
    opts.titaniumLabelValue = uint8(round(double(opts.titaniumLabelValue)));
    opts.titaniumLabelName = safeName(lower(char(opts.titaniumLabelName)));
    opts.titaniumConductivityField = safeName(lower(char( ...
        opts.titaniumConductivityField)));
    opts.titaniumWritableLabels = unique(uint8(round(double( ...
        opts.titaniumWritableLabels(:)'))));
    opts.protectedLabels = unique(uint8(round(double(opts.protectedLabels(:)'))));
    opts.voxelizationPaddingVoxels = round(double(opts.voxelizationPaddingVoxels));
    opts.voxelizationAxes = normalizeVoxelizationAxes(opts.voxelizationAxes);
    opts.voxelizationVoteRule = normalizeVoxelizationVoteRule( ...
        opts.voxelizationVoteRule);
    opts.gridChunkSizeZ = round(double(opts.gridChunkSizeZ));
    opts.inpolyhedronTol = double(opts.inpolyhedronTol);
    opts.overlayAlpha = double(opts.overlayAlpha);
    opts.showFigures = logical(opts.showFigures);
    opts.saveFigures = logical(opts.saveFigures);
    opts.verbose = logical(opts.verbose);
end

function tf = isBoolLike(x)
    tf = (islogical(x) || isnumeric(x)) && isscalar(x);
end

function tf = isLabelScalar(x)
    tf = isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0 && x <= 255;
end

function tf = isNonnegativeScalar(x)
    tf = isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0;
end

function tf = isPositiveScalar(x)
    tf = isnumeric(x) && isscalar(x) && isfinite(x) && x > 0;
end

function axesOut = normalizeVoxelizationAxes(value)
    if ischar(value) || isstring(value)
        txt = lower(regexprep(char(value), '[^xyz123]+', ''));
        if isempty(txt)
            error('acsMakeRoastLabelsFromSurfaceBundle:BadVoxelizationAxes', ...
                'voxelizationAxes must include x/y/z or 1/2/3.');
        end
        axesOut = zeros(1, numel(txt));
        for i = 1:numel(txt)
            switch txt(i)
                case {'x', '1'}
                    axesOut(i) = 1;
                case {'y', '2'}
                    axesOut(i) = 2;
                case {'z', '3'}
                    axesOut(i) = 3;
                otherwise
                    error('acsMakeRoastLabelsFromSurfaceBundle:BadVoxelizationAxes', ...
                        'voxelizationAxes contains unsupported axis "%s".', ...
                        txt(i));
            end
        end
    else
        axesOut = round(double(value(:)'));
    end
    axesOut = unique(axesOut, 'stable');
    if isempty(axesOut) || any(~ismember(axesOut, [1 2 3]))
        error('acsMakeRoastLabelsFromSurfaceBundle:BadVoxelizationAxes', ...
            'voxelizationAxes must be a subset of [1 2 3].');
    end
end

function rule = normalizeVoxelizationVoteRule(value)
    rule = lower(strtrim(char(value)));
    switch regexprep(rule, '[\s_\-]+', '')
        case {'majority', 'vote', 'majorityvote'}
            rule = 'majority';
        case {'any', 'union'}
            rule = 'any';
        case {'all', 'unanimous', 'intersection'}
            rule = 'all';
        otherwise
            error('acsMakeRoastLabelsFromSurfaceBundle:BadVoxelizationVoteRule', ...
                'voxelizationVoteRule must be ''majority'', ''any'', or ''all''.');
    end
end

function threshold = voteThreshold(nAxes, rule)
    switch rule
        case 'majority'
            threshold = floor(double(nAxes) ./ 2) + 1;
        case 'any'
            threshold = 1;
        case 'all'
            threshold = nAxes;
        otherwise
            threshold = floor(double(nAxes) ./ 2) + 1;
    end
end

function perm = rayAxisPermutation(axisId)
    switch axisId
        case 1
            perm = [2 3 1];
        case 2
            perm = [3 1 2];
        case 3
            perm = [1 2 3];
        otherwise
            error('acsMakeRoastLabelsFromSurfaceBundle:BadRayAxis', ...
                'Unsupported ray axis %d.', axisId);
    end
end

function name = axisName(axisId)
    names = {'x', 'y', 'z'};
    name = names{axisId};
end

function txt = axisListText(axisIds)
    names = cell(1, numel(axisIds));
    for i = 1:numel(axisIds)
        names{i} = axisName(axisIds(i));
    end
    txt = strjoin(names, ',');
end

function addLocalDependencies()
    repoRoot = fileparts(fileparts(mfilename('fullpath')));
    addpath(repoRoot);
    addpath(fullfile(repoRoot, 'acsUtilities'));
    spmDir = fullfile(repoRoot, 'lib', 'spm12');
    if exist(spmDir, 'dir') == 7
        addpath(spmDir);
    end
end

function bundle = readBundle(value)
    if isstruct(value)
        bundle = value;
        return;
    end
    fileName = expandUserPath(char(value));
    requireFile(fileName, 'surface bundle MAT file');
    S = load(fileName);
    if isfield(S, 'out')
        bundle = S.out;
    elseif isfield(S, 'outForSave')
        bundle = S.outForSave;
    else
        bundle = firstStruct(S);
    end
end

function surface = selectSurface(surfaces, roleName, labelValue)
    surface = struct([]);
    if isempty(surfaces)
        return;
    end
    idx = find(strcmpi({surfaces.role}, roleName), 1);
    if isempty(idx)
        idx = find(double([surfaces.label]) == double(labelValue), 1, 'last');
    end
    if ~isempty(idx)
        surface = surfaces(idx);
    end
end

function [mask, info] = voxelizeSurfaceRecord(surface, dims, candidateMask, ...
        opts, labelText)
    TR = ensureTri(surface.TR);
    V = double(TR.Points);
    F = double(TR.ConnectivityList);
    if exist('inpolyhedron', 'file') ~= 2
        error('acsMakeRoastLabelsFromSurfaceBundle:MissingInpolyhedron', ...
            'inpolyhedron.m is required for surface-bundle label voxelization.');
    end

    pad = opts.voxelizationPaddingVoxels;
    lo = max([1 1 1], floor(min(V, [], 1)) - pad);
    hi = min(double(dims), ceil(max(V, [], 1)) + pad);
    if any(hi < lo)
        error('acsMakeRoastLabelsFromSurfaceBundle:SurfaceOutsideVolume', ...
            'Surface "%s" does not overlap the label volume.', surface.name);
    end

    mask = false(dims);
    localSize = hi - lo + 1;
    localCandidate = candidateMask(lo(1):hi(1), lo(2):hi(2), lo(3):hi(3));
    nCandidate = nnz(localCandidate);
    info = struct();
    info.surfaceName = surface.name;
    info.surfaceRole = surface.role;
    info.method = 'inpolyhedron multi-axis grid slabs';
    info.surfaceVertices = size(V, 1);
    info.surfaceFaces = size(F, 1);
    info.surfaceBoundsVoxel1 = [min(V, [], 1); max(V, [], 1)];
    info.queryBoundsVoxel1 = [lo; hi];
    info.queryGridSize = localSize;
    info.candidateVoxelCount = nCandidate;
    info.insideVoxelCount = 0;
    info.voxelizationAxes = opts.voxelizationAxes;
    info.voxelizationVoteRule = opts.voxelizationVoteRule;
    info.voteThreshold = voteThreshold(numel(opts.voxelizationAxes), ...
        opts.voxelizationVoteRule);
    info.axisInsideVoxelCount = zeros(numel(opts.voxelizationAxes), 1);
    info.axisElapsedSeconds = zeros(numel(opts.voxelizationAxes), 1);
    info.axisNames = cell(numel(opts.voxelizationAxes), 1);
    info.disagreementVoxelCount = 0;
    info.elapsedSeconds = 0;

    logMsg(opts, '  voxelizing %s from %s (%d vertices, %d faces).', ...
        labelText, surface.name, size(V, 1), size(F, 1));
    logMsg(opts, '    query bounds [%d %d %d] -> [%d %d %d], candidates %d.', ...
        lo(1), lo(2), lo(3), hi(1), hi(2), hi(3), nCandidate);
    logMsg(opts, '    voxelization axes: %s, vote rule: %s.', ...
        axisListText(opts.voxelizationAxes), opts.voxelizationVoteRule);
    if nCandidate == 0
        return;
    end

    stageTimer = tic;
    voteCount = zeros(localSize, 'uint8');
    for a = 1:numel(opts.voxelizationAxes)
        axisId = opts.voxelizationAxes(a);
        axisTimer = tic;
        axisLabel = sprintf('%s %s-ray', labelText, axisName(axisId));
        axisMask = voxelizeSurfaceAlongAxis(F, V, lo, hi, axisId, ...
            opts, axisLabel);
        axisMask = axisMask & localCandidate;
        voteCount = voteCount + uint8(axisMask);
        info.axisInsideVoxelCount(a) = nnz(axisMask);
        info.axisElapsedSeconds(a) = toc(axisTimer);
        info.axisNames{a} = axisName(axisId);
        logMsg(opts, '    %s-ray vote: %d candidate voxels inside in %.1f s.', ...
            axisName(axisId), info.axisInsideVoxelCount(a), ...
            info.axisElapsedSeconds(a));
    end
    localMask = voteCount >= info.voteThreshold;
    localMask = localMask & localCandidate;
    disagreement = voteCount > 0 & voteCount < numel(opts.voxelizationAxes) & ...
        localCandidate;
    info.disagreementVoxelCount = nnz(disagreement);
    mask(lo(1):hi(1), lo(2):hi(2), lo(3):hi(3)) = localMask;
    info.insideVoxelCount = nnz(mask);
    info.elapsedSeconds = toc(stageTimer);
    logMsg(opts, ['    %s voxelization finished in %.1f s; inside voxels %d, ', ...
        'axis-disagreement voxels %d.'], labelText, info.elapsedSeconds, ...
        info.insideVoxelCount, info.disagreementVoxelCount);
end

function maskLocal = voxelizeSurfaceAlongAxis(F, V, lo, hi, axisId, opts, ...
        labelText)
    perm = rayAxisPermutation(axisId);
    Vp = V(:, perm);
    lop = lo(perm);
    hip = hi(perm);
    localSizePerm = hip - lop + 1;
    maskPerm = false(localSizePerm);
    xvec = lop(1):hip(1);
    yvec = lop(2):hip(2);
    zAll = lop(3):hip(3);
    nZ = numel(zAll);
    nextPct = 0;
    stageTimer = tic;
    for zFirst = 1:opts.gridChunkSizeZ:nZ
        zLast = min(nZ, zFirst + opts.gridChunkSizeZ - 1);
        zvec = zAll(zFirst:zLast);
        insideYXZ = inpolyhedron(F, Vp, xvec, yvec, zvec, ...
            'tol', opts.inpolyhedronTol);
        insidePerm = permute(logical(insideYXZ), [2 1 3]);
        maskPerm(:, :, zFirst:zLast) = insidePerm;
        nextPct = maybePrintProgress(opts, labelText, zLast, nZ, ...
            nextPct, stageTimer, 10);
    end
    maskLocal = ipermute(maskPerm, perm);
end

function [labelsOut, info] = applySkinLabels(labelsIn, labelsOut, skinMask, opts)
    oldSkin = labelsIn == opts.skinLabelValue;
    clearOld = oldSkin & ~skinMask & opts.clearOldSkinOutsideSurface;
    writable = skinMask & ismember(labelsIn, opts.skinWritableLabels);
    protected = skinMask & ismember(labelsIn, opts.protectedLabels);
    blocked = skinMask & ~writable & ~protected;

    labelsOut(clearOld) = uint8(0);
    labelsOut(writable) = opts.skinLabelValue;

    info = emptyApplyInfo('skin');
    info.candidateVoxelCount = nnz(skinMask);
    info.writtenVoxelCount = nnz(writable);
    info.clearedOldVoxelCount = nnz(clearOld);
    info.protectedOverlapVoxelCount = nnz(protected);
    info.blockedOverlapVoxelCount = nnz(blocked);
    info.writableLabels = double(opts.skinWritableLabels);
    info.protectedLabels = double(opts.protectedLabels);
    info.writtenByOriginalLabel = labelCountsForMask(labelsIn, writable);
    info.protectedByOriginalLabel = labelCountsForMask(labelsIn, protected);
    info.blockedByOriginalLabel = labelCountsForMask(labelsIn, blocked);

    if info.protectedOverlapVoxelCount > 0
        warning('acsMakeRoastLabelsFromSurfaceBundle:SkinProtectedOverlap', ...
            ['Warped skin shell overlapped %d protected neural voxels. ', ...
             'Those voxels were not overwritten.'], ...
            info.protectedOverlapVoxelCount);
    end
end

function [labelsOut, info] = applyTitaniumLabels(labelsOut, titaniumMask, opts)
    labelsBefore = labelsOut;
    writable = titaniumMask & ismember(labelsBefore, opts.titaniumWritableLabels);
    protected = titaniumMask & ismember(labelsBefore, opts.protectedLabels);
    blocked = titaniumMask & ~writable & ~protected;

    labelsOut(writable) = opts.titaniumLabelValue;

    info = emptyApplyInfo('titanium');
    info.candidateVoxelCount = nnz(titaniumMask);
    info.writtenVoxelCount = nnz(writable);
    info.protectedOverlapVoxelCount = nnz(protected);
    info.blockedOverlapVoxelCount = nnz(blocked);
    info.writableLabels = double(opts.titaniumWritableLabels);
    info.protectedLabels = double(opts.protectedLabels);
    info.writtenByOriginalLabel = labelCountsForMask(labelsBefore, writable);
    info.protectedByOriginalLabel = labelCountsForMask(labelsBefore, protected);
    info.blockedByOriginalLabel = labelCountsForMask(labelsBefore, blocked);

    if info.protectedOverlapVoxelCount > 0
        warning('acsMakeRoastLabelsFromSurfaceBundle:TitaniumProtectedOverlap', ...
            ['Titanium voxelization overlapped %d protected neural voxels. ', ...
             'Those voxels were not overwritten.'], ...
            info.protectedOverlapVoxelCount);
    end
    if info.blockedOverlapVoxelCount > 0
        warning('acsMakeRoastLabelsFromSurfaceBundle:TitaniumBlockedOverlap', ...
            ['Titanium voxelization included %d voxels whose labels were neither ', ...
             'writable nor protected. Those voxels were not overwritten.'], ...
            info.blockedOverlapVoxelCount);
    end
end

function info = emptyVoxelizationInfo(labelText)
    info = struct('surfaceName', '', ...
        'surfaceRole', '', ...
        'method', '', ...
        'labelText', labelText, ...
        'surfaceVertices', 0, ...
        'surfaceFaces', 0, ...
        'surfaceBoundsVoxel1', nan(2, 3), ...
        'queryBoundsVoxel1', nan(2, 3), ...
        'queryGridSize', [0 0 0], ...
        'candidateVoxelCount', 0, ...
        'insideVoxelCount', 0, ...
        'elapsedSeconds', 0);
end

function info = emptyApplyInfo(labelText)
    info = struct('labelText', labelText, ...
        'candidateVoxelCount', 0, ...
        'writtenVoxelCount', 0, ...
        'clearedOldVoxelCount', 0, ...
        'protectedOverlapVoxelCount', 0, ...
        'blockedOverlapVoxelCount', 0, ...
        'writableLabels', [], ...
        'protectedLabels', [], ...
        'writtenByOriginalLabel', struct(), ...
        'protectedByOriginalLabel', struct(), ...
        'blockedByOriginalLabel', struct());
end

function [labelsOut, info] = cleanupSkinLabelComponents(labelsIn, opts)
    labelsOut = labelsIn;
    skin = labelsIn == opts.skinLabelValue;
    info = struct('enabled', opts.cleanupSkinComponents, ...
        'mode', opts.skinCleanupMode, ...
        'componentCountBefore', 0, ...
        'keptComponentCount', 0, ...
        'removedComponentCount', 0, ...
        'largestComponentVoxels', 0, ...
        'removedSkinVoxels', 0, ...
        'reason', '');
    if ~opts.cleanupSkinComponents
        info.reason = 'cleanupSkinComponents=false';
        return;
    end
    if nnz(skin) == 0
        info.reason = 'no skin voxels';
        return;
    end
    if exist('bwconncomp', 'file') ~= 2
        warning('acsMakeRoastLabelsFromSurfaceBundle:MissingBwconncomp', ...
            'bwconncomp is unavailable; disconnected skin cleanup was skipped.');
        info.reason = 'bwconncomp unavailable';
        return;
    end

    CC = bwconncomp(skin, 26);
    sizes = cellfun(@numel, CC.PixelIdxList);
    info.componentCountBefore = CC.NumObjects;
    if isempty(sizes)
        info.reason = 'no connected components';
        return;
    end
    [largestSize, largestIdx] = max(sizes);
    info.largestComponentVoxels = largestSize;
    switch opts.skinCleanupMode
        case 'largest'
            keepComponents = largestIdx;
        case 'minSize'
            keepComponents = find(sizes >= opts.minSkinComponentVoxels);
            if isempty(keepComponents)
                keepComponents = largestIdx;
            end
        otherwise
            keepComponents = largestIdx;
    end

    keep = false(size(skin));
    for i = keepComponents(:)'
        keep(CC.PixelIdxList{i}) = true;
    end
    remove = skin & ~keep;
    labelsOut(remove) = uint8(0);

    info.keptComponentCount = numel(keepComponents);
    info.removedComponentCount = CC.NumObjects - numel(keepComponents);
    info.removedSkinVoxels = nnz(remove);
    if info.removedSkinVoxels == 0
        info.reason = 'no disconnected skin components removed';
    else
        info.reason = 'removed disconnected skin components';
    end
end

function fig = makeQcFigure(t1File, Vref, labelsBefore, labelsAfter, ...
        skinApply, titaniumApply, opts, figVisible)
    if ~isempty(t1File) && exist(t1File, 'file') == 2
        Vt1 = spm_vol(t1File);
        Vt1 = Vt1(1);
        t1 = single(spm_read_vols(Vt1));
    else
        t1 = single(labelsAfter);
    end
    dims = size(labelsAfter);
    sliceInd = chooseSliceIndices(labelsBefore, labelsAfter);
    fig = figure('Name', 'ROAST surface-derived label QC', 'Color', 'w', ...
        'Visible', figVisible, 'Units', 'pixels', 'Position', [80 80 1500 820]);
    addFigureHeader(fig, sprintf(['ROAST surface-derived label QC | skin ', ...
        'written %d, cleared %d | titanium written %d'], ...
        skinApply.writtenVoxelCount, skinApply.clearedOldVoxelCount, ...
        titaniumApply.writtenVoxelCount));

    styles = labelStyles();
    planeLabels = {'Sagittal', 'Coronal', 'Axial'};
    axPos = threePanelPositions(0.23, 0.66);
    clim = robustClim(t1);
    changed = labelsBefore ~= labelsAfter;
    for dimToFix = 1:3
        ax = axes(fig, 'Position', axPos(dimToFix, :)); %#ok<LAXES>
        idx = max(1, min(dims(dimToFix), sliceInd(dimToFix)));
        t1Slice = rawSlice(t1, dimToFix, idx);
        labelSlice = rawSlice(labelsAfter, dimToFix, idx);
        changedSlice = rawSlice(changed, dimToFix, idx);
        imagesc(ax, rot90(t1Slice));
        axis(ax, 'image');
        axis(ax, 'off');
        colormap(ax, gray);
        caxis(ax, clim);
        hold(ax, 'on');
        rgb = labelSliceRgb(labelSlice, styles);
        overlay = image(ax, rot90Rgb(rgb));
        showMask = labelSlice > 0 & labelSlice ~= 6;
        set(overlay, 'AlphaData', rot90(double(showMask) .* opts.overlayAlpha));
        if any(changedSlice(:))
            contour(ax, rot90(double(changedSlice)), [0.5 0.5], ...
                'Color', [1 1 1], 'LineWidth', 0.7);
        end
        title(ax, sprintf('%s %d', planeLabels{dimToFix}, idx), ...
            'Interpreter', 'none', 'FontSize', 11, 'FontWeight', 'bold');
    end

    legendAx = axes(fig, 'Position', [0.05 0.04 0.90 0.12]); %#ok<LAXES>
    drawLegendPanel(legendAx, styles);
    if nargin > 1 && ~isempty(Vref)
        setappdata(fig, 'acsReferenceNifti', Vref.fname);
    end
end

function sliceInd = chooseSliceIndices(labelsBefore, labelsAfter)
    changed = labelsBefore ~= labelsAfter;
    if any(changed(:))
        [i, j, k] = ind2sub(size(changed), find(changed));
        sliceInd = round(median([i j k], 1));
    else
        nonzero = labelsAfter > 0;
        if any(nonzero(:))
            [i, j, k] = ind2sub(size(nonzero), find(nonzero));
            sliceInd = round(median([i j k], 1));
        else
            sliceInd = max(1, round(size(labelsAfter) ./ 2));
        end
    end
end

function styles = labelStyles()
    styles = struct( ...
        'labelId', {1, 2, 3, 4, 5, 6, 7}, ...
        'label', {'1 white', '2 gray', '3 CSF', '4 bone', '5 skin', '6 air', '7 titanium'}, ...
        'color', {[0 0.85 1], [1 0.2 0.1], [0.1 0.25 1], ...
        [1 0.85 0], [0 0.8 0.25], [1 0 1], [0.8 0 0]});
end

function rgb = labelSliceRgb(labelSlice, styles)
    rgb = zeros([size(labelSlice) 3], 'single');
    for k = 1:numel(styles)
        style = styles(k);
        mask = labelSlice == style.labelId;
        for c = 1:3
            channel = rgb(:, :, c);
            channel(mask) = style.color(c);
            rgb(:, :, c) = channel;
        end
    end
end

function drawLegendPanel(ax, styles)
    cla(ax);
    axis(ax, 'off');
    hold(ax, 'on');
    x = 0.02;
    y = 0.70;
    for i = 1:numel(styles)
        style = styles(i);
        if style.labelId == 6
            continue;
        end
        patch(ax, [x x + 0.03 x + 0.03 x], ...
            [y - 0.07 y - 0.07 y + 0.07 y + 0.07], ...
            style.color, 'EdgeColor', [0.2 0.2 0.2], 'LineWidth', 0.5);
        text(ax, x + 0.038, y, style.label, ...
            'Interpreter', 'none', 'VerticalAlignment', 'middle', 'FontSize', 10);
        x = x + 0.13;
    end
    text(ax, 0.02, 0.21, 'white contour: voxels changed from base mask', ...
        'Interpreter', 'none', 'VerticalAlignment', 'middle', 'FontSize', 10);
    xlim(ax, [0 1]);
    ylim(ax, [0 1]);
end

function S = rawSlice(vol, dimToFix, idx)
    switch dimToFix
        case 1
            S = squeeze(vol(idx, :, :));
        case 2
            S = squeeze(vol(:, idx, :));
        case 3
            S = squeeze(vol(:, :, idx));
        otherwise
            error('acsMakeRoastLabelsFromSurfaceBundle:BadSliceDimension', ...
                'Unsupported slice dimension %d.', dimToFix);
    end
end

function out = rot90Rgb(in)
    out = zeros([size(in, 2) size(in, 1) size(in, 3)], 'like', in);
    for c = 1:size(in, 3)
        out(:, :, c) = rot90(in(:, :, c));
    end
end

function clim = robustClim(V)
    vals = double(V(:));
    vals = vals(isfinite(vals));
    if isempty(vals)
        clim = [0 1];
        return;
    end
    if numel(vals) > 1000000
        vals = vals(round(linspace(1, numel(vals), 1000000)));
    end
    clim = prctile(vals(:), [1 99]);
    if clim(1) == clim(2)
        clim = [min(vals(:)) max(vals(:))];
    end
    if clim(1) == clim(2)
        clim = clim + [-1 1];
    end
end

function positions = threePanelPositions(y0, h)
    margin = 0.045;
    gap = 0.035;
    w = (1 - 2 * margin - 2 * gap) / 3;
    positions = zeros(3, 4);
    for i = 1:3
        x0 = margin + (i - 1) * (w + gap);
        positions(i, :) = [x0 y0 w h];
    end
end

function addFigureHeader(fig, headerText)
    annotation(fig, 'textbox', [0.04 0.935 0.92 0.05], ...
        'String', headerText, ...
        'Interpreter', 'none', ...
        'HorizontalAlignment', 'center', ...
        'VerticalAlignment', 'middle', ...
        'FontWeight', 'bold', ...
        'FontSize', 12, ...
        'EdgeColor', 'none');
end

function nextPct = maybePrintProgress(opts, label, doneCount, totalCount, ...
        nextPct, stageTimer, pctStep)
    if ~opts.verbose || totalCount <= 0
        return;
    end
    pct = floor(100 * double(doneCount) / double(totalCount));
    if pct < nextPct && doneCount < totalCount
        return;
    end
    fprintf('    %s: %d%% (%d/%d z-slices), %.1f s elapsed.\n', ...
        label, min(100, pct), doneCount, totalCount, toc(stageTimer));
    while nextPct <= pct
        nextPct = nextPct + pctStep;
    end
    if doneCount >= totalCount && nextPct <= 100
        nextPct = 101;
    end
end

function info = boundarySolidLabelInfo(labels)
    boundary = false(size(labels));
    boundary(1, :, :) = true;
    boundary(end, :, :) = true;
    boundary(:, 1, :) = true;
    boundary(:, end, :) = true;
    boundary(:, :, 1) = true;
    boundary(:, :, end) = true;
    solid = boundary & labels > 0 & labels ~= 6;
    info = struct();
    info.nBoundarySolidVoxels = nnz(solid);
    info.byLabel = labelCountsForMask(labels, solid);
end

function counts = labelCountsForMask(labels, mask)
    ids = 0:max(7, double(max(labels(:))));
    counts = struct();
    for i = 1:numel(ids)
        field = sprintf('label%d', ids(i));
        counts.(field) = nnz(mask & labels == ids(i));
    end
end

function counts = labelVoxelCounts(labels)
    names = {'background', 'white', 'gray', 'csf', 'bone', 'skin', ...
        'air', 'titanium'};
    maxLabel = max(double(labels(:)));
    counts = struct();
    for k = 0:max(maxLabel, numel(names) - 1)
        if k + 1 <= numel(names)
            field = names{k + 1};
        else
            field = sprintf('label%d', k);
        end
        counts.(field) = nnz(labels == k);
    end
end

function summary = summarizeSurfaceForReport(surface)
    summary = struct('present', false, ...
        'name', '', 'role', '', 'label', NaN, ...
        'nVertices', 0, 'nFaces', 0, ...
        'boundsVoxel1', nan(2, 3));
    if isempty(surface) || ~isstruct(surface) || ~isfield(surface, 'TR')
        return;
    end
    TR = ensureTri(surface.TR);
    V = double(TR.Points);
    summary.present = true;
    summary.name = surface.name;
    summary.role = surface.role;
    summary.label = double(surface.label);
    summary.nVertices = size(V, 1);
    summary.nFaces = size(TR.ConnectivityList, 1);
    summary.boundsVoxel1 = [min(V, [], 1); max(V, [], 1)];
end

function material = ti6al4vMaterialSummary()
    resistivityRange = [168 170] * 1e-8;
    material = struct();
    material.name = 'Ti6Al4V Grade 5';
    material.resistivityOhmMRange = resistivityRange;
    material.defaultResistivityOhmM = mean(resistivityRange);
    material.conductivitySPerMRange = 1 ./ fliplr(resistivityRange);
    material.defaultConductivitySPerM = 1 / material.defaultResistivityOhmM;
    material.note = ['Conductivity is the reciprocal of resistivity; ', ...
        'use conductivities.titanium to override for a specific alloy/source.'];
end

function writeLabelVolume(fileName, Vref, labels, description)
    deleteDerivedNifti(fileName);
    Vout = Vref;
    Vout.fname = fileName;
    Vout.dim = size(labels);
    Vout.dt = [spm_type('uint8') spm_platform('bigend')];
    Vout.n = [1 1];
    Vout.private = [];
    Vout.pinfo = [1; 0; 0];
    Vout.descrip = description;
    ensureDir(fileparts(fileName));
    spm_write_vol(Vout, uint8(labels));
end

function fileName = defaultOutputFile(baseMaskFile, outputTag)
    [folder, stem, ext] = fileparts(baseMaskFile);
    if strcmpi(ext, '.gz')
        [~, stem, ext2] = fileparts(stem);
        ext = [ext2 ext];
    end
    if isempty(ext)
        ext = '.nii';
    end
    stem = regexprep(stem, '_T1orT2_SPM_masks.*$', '');
    fileName = fullfile(folder, sprintf('%s_%s_T1orT2_SPM_masks%s', ...
        stem, outputTag, ext));
end

function reportFile = reportFileForMask(maskFile)
    [folder, stem] = fileparts(maskFile);
    reportFile = fullfile(folder, [stem '_report.mat']);
end

function out = loadExistingReport(maskFile)
    out = [];
    reportFile = reportFileForMask(maskFile);
    if exist(reportFile, 'file') ~= 2
        return;
    end
    S = load(reportFile);
    if isfield(S, 'outForSave') && isstruct(S.outForSave)
        out = S.outForSave;
    elseif isfield(S, 'out') && isstruct(S.out)
        out = S.out;
    end
end

function out = buildExistingReport(bundle, opts)
    out = struct();
    out.type = 'roastSurfaceBundleLabelMask';
    out.bundleFile = optionalCharField(bundle, 'outputFile', '');
    out.baseMaskFile = opts.baseMaskFile;
    out.maskFile = opts.outputFile;
    out.outputFile = opts.outputFile;
    out.t1File = opts.t1File;
    out.reusedExisting = true;
    out.options = opts;
end

function saveQcFigure(fig, fileName)
    try
        exportgraphics(fig, fileName, 'Resolution', 150);
    catch
        saveas(fig, fileName);
    end
end

function writeJsonReport(fileName, report)
    try
        fid = fopen(fileName, 'w');
        cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
        fprintf(fid, '%s', jsonencode(report, 'PrettyPrint', true));
    catch ME
        warning('acsMakeRoastLabelsFromSurfaceBundle:CannotWriteJson', ...
            'Could not write report JSON %s: %s', fileName, ME.message);
    end
end

function printSummary(out, opts)
    if ~opts.verbose
        return;
    end
    fprintf('\nROAST surface-derived hard labels\n');
    fprintf('  bundle: %s\n', out.bundleFile);
    fprintf('  base mask: %s\n', out.baseMaskFile);
    fprintf('  output mask: %s\n', out.maskFile);
    fprintf('  skin shell voxels: candidates %d, inside %d, written %d, cleared old %d\n', ...
        out.skinVoxelization.candidateVoxelCount, ...
        out.skinVoxelization.insideVoxelCount, ...
        out.skinApplication.writtenVoxelCount, ...
        out.skinApplication.clearedOldVoxelCount);
    printAxisVoteSummary('skin shell', out.skinVoxelization);
    fprintf('  titanium voxels: candidates %d, inside %d, written %d, protected %d\n', ...
        out.titaniumVoxelization.candidateVoxelCount, ...
        out.titaniumVoxelization.insideVoxelCount, ...
        out.titaniumApplication.writtenVoxelCount, ...
        out.titaniumApplication.protectedOverlapVoxelCount);
    printAxisVoteSummary('titanium', out.titaniumVoxelization);
    fprintf('  skin cleanup: %s, components %d -> %d, removed %d voxels\n', ...
        out.skinCleanup.mode, out.skinCleanup.componentCountBefore, ...
        out.skinCleanup.keptComponentCount, out.skinCleanup.removedSkinVoxels);
    if out.boundaryInfo.nBoundarySolidVoxels > 0
        fprintf('  boundary solid voxels: %d\n', ...
            out.boundaryInfo.nBoundarySolidVoxels);
    end
    if ~isempty(out.qcFile)
        fprintf('  QC figure: %s\n', out.qcFile);
    end
end

function printAxisVoteSummary(label, info)
    if ~isstruct(info) || ~isfield(info, 'axisNames') || ...
            isempty(info.axisNames)
        return;
    end
    counts = double(info.axisInsideVoxelCount(:));
    names = info.axisNames(:);
    parts = cell(numel(names), 1);
    for i = 1:numel(names)
        parts{i} = sprintf('%s=%d', names{i}, counts(i));
    end
    fprintf('    %s ray votes: %s; disagreement %d; threshold %d/%d\n', ...
        label, strjoin(parts, ', '), info.disagreementVoxelCount, ...
        info.voteThreshold, numel(names));
end

function TR = ensureTri(value)
    if isa(value, 'triangulation')
        TR = value;
    elseif isstruct(value) && isfield(value, 'ConnectivityList') && ...
            isfield(value, 'Points')
        TR = triangulation(double(value.ConnectivityList), double(value.Points));
    else
        error('acsMakeRoastLabelsFromSurfaceBundle:BadTriangulation', ...
            'Expected a triangulation or struct with Points and ConnectivityList.');
    end
end

function mode = normalizeSkinCleanupMode(mode)
    mode = lower(strtrim(char(mode)));
    switch regexprep(mode, '[\s_\-]+', '')
        case {'largest', 'largestcomponent', 'main'}
            mode = 'largest';
        case {'minsize', 'minimumsize', 'threshold'}
            mode = 'minSize';
        otherwise
            error('acsMakeRoastLabelsFromSurfaceBundle:BadSkinCleanupMode', ...
                'skinCleanupMode must be ''largest'' or ''minSize''.');
    end
end

function value = requiredCharField(S, fieldName, label)
    value = '';
    if isstruct(S) && isfield(S, fieldName) && ~isempty(S.(fieldName))
        value = char(S.(fieldName));
    end
    if isempty(value)
        error('acsMakeRoastLabelsFromSurfaceBundle:MissingField', ...
            'Missing %s.', label);
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
    error('acsMakeRoastLabelsFromSurfaceBundle:NoStructInMat', ...
        'MAT file does not contain a struct.');
end

function deleteDerivedNifti(fileName)
    if exist(fileName, 'file') == 2
        delete(fileName);
    end
    [folder, stem] = fileparts(fileName);
    matSidecar = fullfile(folder, [stem '.mat']);
    if exist(matSidecar, 'file') == 2
        delete(matSidecar);
    end
end

function ensureDir(folder)
    if ~isempty(folder) && exist(folder, 'dir') ~= 7
        mkdir(folder);
    end
end

function requireFile(fileName, label)
    if isempty(fileName) || exist(fileName, 'file') ~= 2
        error('acsMakeRoastLabelsFromSurfaceBundle:MissingFile', ...
            '%s not found: %s', label, fileName);
    end
end

function fileName = expandUserPath(fileName)
    fileName = char(fileName);
    if startsWith(fileName, '~')
        fileName = fullfile(char(java.lang.System.getProperty('user.home')), ...
            fileName(2:end));
    end
end

function name = getFileName(fileName)
    [~, name, ext] = fileparts(fileName);
    name = [name ext];
end

function stem = stripNiftiExtension(fileName)
    [~, stem, ext] = fileparts(fileName);
    if strcmpi(ext, '.gz')
        [~, stem] = fileparts(stem);
    end
end

function name = safeName(name)
    name = regexprep(char(name), '[^a-zA-Z0-9_]+', '_');
    name = regexprep(name, '_+', '_');
    name = regexprep(name, '^_|_$', '');
    if isempty(name)
        name = 'value';
    end
end

function logMsg(opts, varargin)
    if ~opts.verbose
        return;
    end
    if isempty(varargin)
        fprintf('\n');
    else
        fprintf([varargin{1} '\n'], varargin{2:end});
    end
end
