function out = acsBuildRoastSurfaceBundle(sourceIn, varargin)
% ACSBUILDROASTSURFACEBUNDLE Collect ROAST tissue surfaces in one audit frame.
%
% out = acsBuildRoastSurfaceBundle(segOut, 'scalpSkinCacheFile', cacheFile)
% reads MRI-derived ROAST hard labels from segOut.roastReady.maskFile,
% extracts tissue boundary surfaces, reads a capMaker scalp cache, maps the
% selected scalp surface into the same T1 voxel frame, and writes a bundle
% MAT file plus optional QC overlay. This is the first, non-solving step of
% the mesh-native ROAST path.
%
% Label 5 (skin) is split into original outer/inner diagnostic interfaces
% by default. For meshing, a supplied warped scalp cache can also be folded
% back into a single morphed whole-skin shell: the original closed skin
% topology is retained, while only outer-facing vertices are displaced
% toward the phone/capMaker warped scalp.
%
% Coordinate convention:
%   All surfaces in out.surfaces are in 1-based T1 voxel coordinates
%   (dim1, dim2, dim3). This is intentionally not a ROAST/GetDP mesh frame
%   yet; it is the simplest frame for checking alignment against the label
%   volume and T1 slices.

    if nargin < 1 || isempty(sourceIn)
        error('acsBuildRoastSurfaceBundle:MissingInput', ...
            'Provide a segmentation output, mask file, or source struct.');
    end

    opts = parseInputs(varargin{:});
    addLocalDependencies();
    [maskFile, t1File, source] = resolveInputs(sourceIn, opts);

    if isempty(opts.outputFile)
        opts.outputFile = defaultOutputFile(maskFile, opts);
    end
    if exist(opts.outputFile, 'file') == 2 && ~opts.force
        out = loadExistingBundle(opts.outputFile);
        if opts.verbose
            fprintf('ROAST surface bundle already exists; reusing %s\n', ...
                opts.outputFile);
        end
        return;
    end

    if opts.verbose
        fprintf('\nBuilding ROAST mesh-native surface bundle.\n');
        fprintf('  mask: %s\n', maskFile);
        if ~isempty(t1File)
            fprintf('  T1: %s\n', t1File);
        end
    end

    Vmask = spm_vol(maskFile);
    Vmask = Vmask(1);
    labels = uint8(round(spm_read_vols(Vmask)));
    dims = size(labels);
    if numel(dims) < 3
        error('acsBuildRoastSurfaceBundle:BadMask', ...
            'ROAST label mask must be 3-D: %s', maskFile);
    end
    if opts.verbose
        fprintf('  label volume size: [%d %d %d]\n', dims(1), dims(2), dims(3));
    end

    stageTimer = tic;
    surfaces = extractLabelSurfaces(labels, opts);
    if opts.verbose
        fprintf('  extracted MRI label surfaces in %.1f s.\n', toc(stageTimer));
    end
    referenceScalpSurface = struct([]);
    referenceScalpInfo = struct();
    if ~isempty(opts.referenceScalpSkinCacheFile)
        stageTimer = tic;
        if opts.verbose
            fprintf('  reading reference scalp cache: %s\n', ...
                opts.referenceScalpSkinCacheFile);
        end
        [referenceScalpSurface, referenceScalpInfo] = ...
            readScalpSurfaceAsVoxel1(opts.referenceScalpSkinCacheFile, ...
            opts.referenceScalpMeshStage, Vmask, ...
            'referenceScalpOuter', 'capMakerScalpReference', ...
            [0.05 0.05 0.05], opts);
        surfaces = appendSurface(surfaces, referenceScalpSurface);
        if opts.verbose
            fprintf('  mapped reference scalp cache in %.1f s.\n', ...
                toc(stageTimer));
        end
    end

    scalpSurface = struct([]);
    scalpInfo = struct();
    if ~isempty(opts.scalpSkinCacheFile)
        stageTimer = tic;
        if opts.verbose
            fprintf('  reading warped scalp cache: %s\n', ...
                opts.scalpSkinCacheFile);
        end
        [scalpSurface, scalpInfo] = readScalpSurfaceAsVoxel1( ...
            opts.scalpSkinCacheFile, opts.scalpMeshStage, Vmask, ...
            'warpedScalpOuter', 'capMakerScalpOuter', ...
            [0.00 0.62 0.28], opts);
        surfaces = appendSurface(surfaces, scalpSurface);
        if opts.verbose
            fprintf('  mapped warped scalp cache in %.1f s.\n', ...
                toc(stageTimer));
        end
    end

    skinShellSurface = struct([]);
    skinShellInfo = struct();
    if opts.buildWarpedSkinShell && ~isempty(referenceScalpSurface) && ...
            ~isempty(scalpSurface)
        stageTimer = tic;
        [skinShellSurface, skinShellInfo] = makeWarpedSkinShellSurface( ...
            labels, surfaces, referenceScalpSurface, scalpSurface, opts);
        if ~isempty(skinShellSurface)
            surfaces = appendSurface(surfaces, skinShellSurface);
        end
        if opts.verbose
            fprintf('  built morphed whole-skin shell in %.1f s.\n', ...
                toc(stageTimer));
        end
    end

    headpostSurface = struct([]);
    headpostInfo = struct();
    if ~isempty(opts.headpostPlacementFile)
        stageTimer = tic;
        if opts.verbose
            fprintf('  reading placed headpost mesh: %s\n', ...
                opts.headpostPlacementFile);
        end
        [headpostSurface, headpostInfo] = readHeadpostSurfaceAsVoxel1( ...
            opts.headpostPlacementFile, opts.headpostSkinCacheFile, Vmask, opts);
        surfaces = appendSurface(surfaces, headpostSurface);
        if opts.verbose
            fprintf('  mapped placed headpost mesh in %.1f s.\n', ...
                toc(stageTimer));
        end
    end

    t1 = [];
    if ~isempty(t1File) && exist(t1File, 'file') == 2
        stageTimer = tic;
        if opts.verbose
            fprintf('  reading T1 for QC overlays.\n');
        end
        Vt1 = spm_vol(t1File);
        Vt1 = Vt1(1);
        t1 = single(spm_read_vols(Vt1));
        if opts.verbose
            fprintf('  read T1 in %.1f s.\n', toc(stageTimer));
        end
    end
    if isempty(t1)
        t1 = single(labels);
    end

    qcFile = '';
    fig = [];
    if opts.showFigures || opts.saveFigures
        stageTimer = tic;
        if opts.verbose
            fprintf('  making surface bundle QC figure.\n');
        end
        figVisible = 'off';
        if opts.showFigures
            figVisible = 'on';
        end
        fig = makeQcFigure(t1, labels, surfaces, source, opts, figVisible);
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
            fprintf('  made surface bundle QC figure in %.1f s.\n', ...
                toc(stageTimer));
        end
    end

    out = struct();
    out.createdOn = char(datetime('now'));
    out.type = 'roastSurfaceBundle';
    out.coordinateFrame = 't1Voxel1';
    out.description = ['MRI-derived tissue surfaces plus optional ', ...
        'capMaker/phone-warped scalp surface in 1-based T1 voxel space.'];
    out.source = source;
    out.maskFile = maskFile;
    out.t1File = t1File;
    out.imageSize = dims(1:3);
    out.surfaces = surfaces;
    out.scalp = scalpInfo;
    out.referenceScalp = referenceScalpInfo;
    out.warpedSkinShell = skinShellInfo;
    out.headpost = headpostInfo;
    out.surfaceSummary = summarizeSurfaces(surfaces);
    out.skinShell = makeSkinShellDiagnostics(surfaces, opts);
    out.implantDiagnostics = makeImplantDiagnostics(surfaces, opts);
    out.alignmentDiagnostics = makeAlignmentDiagnostics(labels, surfaces);
    out.qcFigure = qcFile;
    out.outputFile = opts.outputFile;
    out.options = opts;
    out.figure = fig;

    ensureDir(fileparts(opts.outputFile));
    outForSave = out;
    if isfield(outForSave, 'figure')
        outForSave = rmfield(outForSave, 'figure');
    end
    if opts.verbose
        fprintf('  saving surface bundle MAT/JSON reports.\n');
    end
    stageTimer = tic;
    save(opts.outputFile, 'outForSave', '-v7.3');
    writeJsonReport(strrep(opts.outputFile, '.mat', '.json'), ...
        stripForJson(outForSave));
    if opts.verbose
        fprintf('  saved surface bundle reports in %.1f s.\n', toc(stageTimer));
    end

    if opts.verbose
        printSummary(out);
    end
end

function opts = parseInputs(varargin)
    p = inputParser;
    p.FunctionName = 'acsBuildRoastSurfaceBundle';
    addParameter(p, 'maskFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 't1File', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'scalpSkinCacheFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'scalpMeshStage', 'stableHead', ...
        @(x) ischar(x) || isstring(x));
    addParameter(p, 'referenceScalpSkinCacheFile', '', ...
        @(x) ischar(x) || isstring(x));
    addParameter(p, 'referenceScalpMeshStage', 'stableHead', ...
        @(x) ischar(x) || isstring(x));
    addParameter(p, 'outputFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'outputTag', 'meshNativeSurfaceBundle', ...
        @(x) ischar(x) || isstring(x));
    addParameter(p, 'force', false, @isBoolLike);
    addParameter(p, 'includeLabels', [1 2 3 4 5 6], ...
        @(x) isnumeric(x) && isvector(x));
    addParameter(p, 'splitSkinSurfaces', true, @isBoolLike);
    addParameter(p, 'includeWholeSkinSurface', false, @isBoolLike);
    addParameter(p, 'skinOuterNeighborLabels', 0, ...
        @(x) isnumeric(x) && isvector(x));
    addParameter(p, 'skinInnerNeighborLabels', [1 2 3 4 6 7], ...
        @(x) isnumeric(x) && isvector(x));
    addParameter(p, 'buildWarpedSkinShell', true, @isBoolLike);
    addParameter(p, 'repairWarpedSkinShellWinding', true, @isBoolLike);
    addParameter(p, 'skinShellWindingProbeDistanceVoxel', 0.55, ...
        @isPositiveScalar);
    addParameter(p, 'skinShellMaxFaces', Inf, @isPositiveScalarOrInf);
    addParameter(p, 'skinShellOuterBlendPower', 1.5, @isPositiveScalar);
    addParameter(p, 'headpostPlacementFile', '', ...
        @(x) ischar(x) || isstring(x));
    addParameter(p, 'headpostSkinCacheFile', '', ...
        @(x) ischar(x) || isstring(x));
    addParameter(p, 'shellClearanceSampleCount', 5000, @isPositiveScalar);
    addParameter(p, 'surfaceContactToleranceVoxel', 0.75, @isPositiveScalar);
    addParameter(p, 'maxFacesPerTissue', 12000, @isPositiveScalarOrInf);
    addParameter(p, 'sliceOverlayToleranceVoxel', 0.75, @isPositiveScalar);
    addParameter(p, 'showFigures', false, @isBoolLike);
    addParameter(p, 'saveFigures', false, @isBoolLike);
    addParameter(p, 'verbose', true, @isBoolLike);
    parse(p, varargin{:});

    opts = p.Results;
    opts.maskFile = expandUserPath(char(opts.maskFile));
    opts.t1File = expandUserPath(char(opts.t1File));
    opts.scalpSkinCacheFile = expandUserPath(char(opts.scalpSkinCacheFile));
    opts.scalpMeshStage = normalizeScalpMeshStage(opts.scalpMeshStage);
    opts.referenceScalpSkinCacheFile = expandUserPath( ...
        char(opts.referenceScalpSkinCacheFile));
    opts.referenceScalpMeshStage = normalizeScalpMeshStage( ...
        opts.referenceScalpMeshStage);
    opts.outputFile = expandUserPath(char(opts.outputFile));
    opts.outputTag = safeName(char(opts.outputTag));
    opts.force = logical(opts.force);
    opts.includeLabels = unique(round(double(opts.includeLabels(:))))';
    opts.splitSkinSurfaces = logical(opts.splitSkinSurfaces);
    opts.includeWholeSkinSurface = logical(opts.includeWholeSkinSurface);
    opts.skinOuterNeighborLabels = unique(round(double( ...
        opts.skinOuterNeighborLabels(:))))';
    opts.skinInnerNeighborLabels = unique(round(double( ...
        opts.skinInnerNeighborLabels(:))))';
    opts.buildWarpedSkinShell = logical(opts.buildWarpedSkinShell);
    opts.repairWarpedSkinShellWinding = ...
        logical(opts.repairWarpedSkinShellWinding);
    opts.skinShellWindingProbeDistanceVoxel = ...
        double(opts.skinShellWindingProbeDistanceVoxel);
    opts.skinShellMaxFaces = double(opts.skinShellMaxFaces);
    if isfinite(opts.skinShellMaxFaces)
        opts.skinShellMaxFaces = round(opts.skinShellMaxFaces);
    end
    opts.skinShellOuterBlendPower = double(opts.skinShellOuterBlendPower);
    opts.headpostPlacementFile = expandUserPath(char(opts.headpostPlacementFile));
    opts.headpostSkinCacheFile = expandUserPath(char(opts.headpostSkinCacheFile));
    opts.shellClearanceSampleCount = round(double(opts.shellClearanceSampleCount));
    opts.surfaceContactToleranceVoxel = double(opts.surfaceContactToleranceVoxel);
    opts.maxFacesPerTissue = double(opts.maxFacesPerTissue);
    if isfinite(opts.maxFacesPerTissue)
        opts.maxFacesPerTissue = round(opts.maxFacesPerTissue);
    end
    opts.sliceOverlayToleranceVoxel = double(opts.sliceOverlayToleranceVoxel);
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

function tf = isPositiveScalarOrInf(x)
    tf = isnumeric(x) && isscalar(x) && (isinf(x) || ...
        (isfinite(x) && x > 0));
end

function stage = normalizeScalpMeshStage(stage)
    stage = lower(strtrim(char(stage)));
    stage = regexprep(stage, '[\s_\-]+', '');
    switch stage
        case {'stablehead', 'fullhead', 'precrop'}
            stage = 'stableHead';
        case {'fiducialhead', 'fiducial', 'printfullhead'}
            stage = 'fiducialHead';
        case {'skin', 'trskin', 'cap', 'print'}
            stage = 'skin';
        otherwise
            error('acsBuildRoastSurfaceBundle:BadScalpMeshStage', ...
                'scalpMeshStage must be stableHead, fiducialHead, or skin.');
    end
end

function addLocalDependencies()
    repoRoot = fileparts(fileparts(mfilename('fullpath')));
    addpath(repoRoot);
    addpath(fullfile(repoRoot, 'acsUtilities'));
    addpath(fullfile(repoRoot, 'capMaker', 'core'));
    spmDir = fullfile(repoRoot, 'lib', 'spm12');
    if exist(spmDir, 'dir') == 7
        addpath(spmDir);
    end
end

function [maskFile, t1File, source] = resolveInputs(sourceIn, opts)
    source = struct('type', '', 'inputClass', class(sourceIn));
    maskFile = opts.maskFile;
    t1File = opts.t1File;

    if ischar(sourceIn) || isstring(sourceIn)
        sourceFile = expandUserPath(char(sourceIn));
        if isempty(maskFile)
            maskFile = sourceFile;
        end
        source.type = 'maskFile';
        source.file = sourceFile;
    elseif isstruct(sourceIn)
        source.type = 'struct';
        if isempty(maskFile)
            if isfield(sourceIn, 'roastReady') && isstruct(sourceIn.roastReady) && ...
                    isfield(sourceIn.roastReady, 'maskFile')
                maskFile = expandUserPath(char(sourceIn.roastReady.maskFile));
                source.type = 'segmentationOutput';
            elseif isfield(sourceIn, 'maskFile')
                maskFile = expandUserPath(char(sourceIn.maskFile));
            elseif isfield(sourceIn, 'outputFile')
                maskFile = expandUserPath(char(sourceIn.outputFile));
            end
        end
        if isempty(t1File)
            if isfield(sourceIn, 'roastReady') && isstruct(sourceIn.roastReady) && ...
                    isfield(sourceIn.roastReady, 't1File')
                t1File = expandUserPath(char(sourceIn.roastReady.t1File));
            elseif isfield(sourceIn, 't1File')
                t1File = expandUserPath(char(sourceIn.t1File));
            end
        end
        source.subjectId = optionalCharField(sourceIn, 'subjectId', '');
    else
        error('acsBuildRoastSurfaceBundle:BadSource', ...
            'sourceIn must be a struct or mask filename.');
    end

    requireFile(maskFile, 'ROAST hard-label mask');
    if ~isempty(t1File)
        requireFile(t1File, 'T1 image');
    end
    source.maskFile = maskFile;
    source.t1File = t1File;
    source.scalpSkinCacheFile = opts.scalpSkinCacheFile;
end

function value = optionalCharField(S, fieldName, defaultValue)
    value = defaultValue;
    if isstruct(S) && isfield(S, fieldName) && ~isempty(S.(fieldName))
        value = char(S.(fieldName));
    end
end

function fileName = defaultOutputFile(maskFile, opts)
    folder = fileparts(maskFile);
    [~, stem] = fileparts(maskFile);
    if ~isempty(opts.scalpSkinCacheFile)
        folder = fileparts(opts.scalpSkinCacheFile);
        [~, scalpStem] = fileparts(opts.scalpSkinCacheFile);
        stem = scalpStem;
    end
    fileName = fullfile(folder, [stem '_' opts.outputTag '.mat']);
end

function out = loadExistingBundle(fileName)
    S = load(fileName);
    if isfield(S, 'out')
        out = S.out;
    elseif isfield(S, 'outForSave')
        out = S.outForSave;
    else
        out = firstStruct(S);
    end
end

function surfaces = extractLabelSurfaces(labels, opts)
    surfaces = struct([]);
    styles = labelStyles();
    if opts.verbose
        labelsText = sprintf('%d ', opts.includeLabels(:)');
        fprintf('  extracting hard-label surfaces for labels: %s\n', ...
            strtrim(labelsText));
    end
    for labelValue = opts.includeLabels(:)'
        if labelValue < 0 || labelValue > 255
            continue;
        end
        if labelValue == 5 && opts.splitSkinSurfaces
            surfaces = appendSurfaceList(surfaces, ...
                extractSplitSkinSurfaces(labels, opts));
            if ~opts.includeWholeSkinSurface
                continue;
            end
        end
        mask = labels == uint8(labelValue);
        if nnz(mask) < 4
            if opts.verbose
                fprintf('    label %d skipped: fewer than 4 voxels.\n', ...
                    labelValue);
            end
            continue;
        end
        style = styleForLabel(styles, labelValue);
        progressLabel = sprintf('label %d %s hard surface', ...
            labelValue, style.name);
        [TR, surfInfo] = labelMaskToVoxelSurface( ...
            mask, opts.maxFacesPerTissue, progressLabel, opts);
        if isempty(TR)
            if opts.verbose
                fprintf('    label %d skipped: %s\n', ...
                    labelValue, surfInfo.message);
            end
            continue;
        end
        item = makeSurfaceStruct(style.name, labelValue, TR, ...
            'mriHardLabel', style.color, 0.22, ...
            sprintf('ROAST hard label %d (%s)', labelValue, style.name), ...
            surfInfo);
        surfaces = appendSurface(surfaces, item);
        if opts.verbose
            fprintf('    label %d %s: %d faces retained.\n', ...
                labelValue, style.name, size(TR.ConnectivityList, 1));
        end
    end
end

function skinSurfaces = extractSplitSkinSurfaces(labels, opts)
    skinSurfaces = struct([]);
    styles = labelStyles();
    skinStyle = styleForLabel(styles, 5);

    if opts.verbose
        fprintf('    extracting split skin interfaces.\n');
    end

    [TRouter, outerInfo] = labelInterfaceSurface( ...
        labels, 5, opts.skinOuterNeighborLabels, opts.maxFacesPerTissue, ...
        'skin outer/background interface', opts);
    if ~isempty(TRouter)
        outerInfo.interface = 'skin voxels adjacent to external background';
        item = makeSurfaceStruct('skinOuterOriginal', 5, TRouter, ...
            'roastSkinOuterOriginal', brightenColor(skinStyle.color, 0.25), ...
            0.18, 'Original ROAST outer skin/background interface', ...
            outerInfo);
        skinSurfaces = appendSurface(skinSurfaces, item);
        if opts.verbose
            fprintf('    skin outer interface: %d faces retained.\n', ...
                size(TRouter.ConnectivityList, 1));
        end
    elseif opts.verbose
        fprintf('    skin outer interface skipped: %s\n', outerInfo.message);
    end

    [TRinner, innerInfo] = labelInterfaceSurface( ...
        labels, 5, opts.skinInnerNeighborLabels, opts.maxFacesPerTissue, ...
        'skin inner/tissue interface', opts);
    if ~isempty(TRinner)
        innerInfo.interface = 'skin voxels adjacent to internal labels';
        item = makeSurfaceStruct('skinInnerOriginal', 5, TRinner, ...
            'roastSkinInnerOriginal', darkenColor(skinStyle.color, 0.45), ...
            0.24, 'Original ROAST inner skin/tissue interface', ...
            innerInfo);
        skinSurfaces = appendSurface(skinSurfaces, item);
        if opts.verbose
            fprintf('    skin inner interface: %d faces retained.\n', ...
                size(TRinner.ConnectivityList, 1));
        end
    elseif opts.verbose
        fprintf('    skin inner interface skipped: %s\n', innerInfo.message);
    end
end

function surfaces = appendSurfaceList(surfaces, items)
    for i = 1:numel(items)
        surfaces = appendSurface(surfaces, items(i));
    end
end

function [TR, info] = labelInterfaceSurface(labels, targetLabel, neighborLabels, ...
        maxFaces, progressLabel, opts)
    if nargin < 5 || isempty(progressLabel)
        progressLabel = 'label interface surface';
    end
    if nargin < 6 || ~isstruct(opts)
        opts = struct('verbose', false);
    end
    targetLabel = double(targetLabel);
    neighborLabels = double(neighborLabels(:)');
    targetMask = double(labels) == targetLabel;
    info = struct('targetLabel', targetLabel, ...
        'neighborLabels', neighborLabels, ...
        'voxelFaceCountBeforeReduction', 0, ...
        'faceCountBeforeReduction', 0, ...
        'faceCountAfterReduction', 0, ...
        'maxFacesPerTissue', maxFaces, ...
        'reduced', false, ...
        'directionFaceCounts', zeros(6, 1), ...
        'message', '');
    TR = [];
    if ~any(targetMask(:))
        info.message = 'target label not present';
        return;
    end
    stageTimer = tic;
    if opts.verbose
        fprintf('      %s: scanning voxel-neighbor interfaces.\n', ...
            progressLabel);
    end

    directions = interfaceDirections();
    Vall = zeros(0, 3);
    Fall = zeros(0, 3);
    for d = 1:numel(directions)
        neigh = shiftedLabels(labels, directions(d).offset, uint8(0));
        keep = targetMask & double(neigh) ~= targetLabel & ...
            ismember(double(neigh), neighborLabels);
        idx = find(keep);
        info.directionFaceCounts(d) = numel(idx);
        if isempty(idx)
            if opts.verbose
                fprintf('        %s direction %s: 0 voxel faces.\n', ...
                    progressLabel, directions(d).id);
            end
            continue;
        end
        if opts.verbose
            fprintf('        %s direction %s: %d voxel faces.\n', ...
                progressLabel, directions(d).id, numel(idx));
        end
        [i, j, k] = ind2sub(size(labels), idx);
        [Vq, Fq] = voxelBoundaryTriangles(i, j, k, directions(d).id);
        Fq = Fq + size(Vall, 1);
        Vall = [Vall; Vq]; %#ok<AGROW>
        Fall = [Fall; Fq]; %#ok<AGROW>
    end
    if isempty(Fall)
        info.message = 'no matching label interfaces';
        return;
    end

    info.voxelFaceCountBeforeReduction = sum(info.directionFaceCounts);
    info.faceCountBeforeReduction = size(Fall, 1);
    if opts.verbose
        fprintf('      %s: uniquing %d vertices / %d faces.\n', ...
            progressLabel, size(Vall, 1), size(Fall, 1));
    end
    [Vuniq, ~, vertexMap] = unique(Vall, 'rows');
    Funiq = reshape(vertexMap(Fall), size(Fall));
    fv = struct('faces', double(Funiq), 'vertices', double(Vuniq));
    if size(fv.faces, 1) > maxFaces && exist('reducepatch', 'file') == 2
        try
            if opts.verbose
                fprintf('      %s: reducing %d faces to target %.0f.\n', ...
                    progressLabel, size(fv.faces, 1), maxFaces);
            end
            fv = reducepatch(fv, maxFaces);
            info.reduced = true;
        catch ME
            info.message = ['reducepatch failed: ' ME.message];
        end
    end
    TR = triangulation(double(fv.faces), double(fv.vertices));
    info.faceCountAfterReduction = size(TR.ConnectivityList, 1);
    if opts.verbose
        fprintf('      %s: finished in %.1f s (%d faces).\n', ...
            progressLabel, toc(stageTimer), info.faceCountAfterReduction);
    end
end

function directions = interfaceDirections()
    directions = struct( ...
        'id', {'xMinus', 'xPlus', 'yMinus', 'yPlus', 'zMinus', 'zPlus'}, ...
        'offset', {[-1 0 0], [1 0 0], [0 -1 0], [0 1 0], [0 0 -1], [0 0 1]});
end

function shifted = shiftedLabels(labels, offset, fillValue)
    shifted = repmat(uint8(fillValue), size(labels));
    switch sprintf('%d,%d,%d', offset)
        case '-1,0,0'
            shifted(2:end, :, :) = labels(1:end-1, :, :);
        case '1,0,0'
            shifted(1:end-1, :, :) = labels(2:end, :, :);
        case '0,-1,0'
            shifted(:, 2:end, :) = labels(:, 1:end-1, :);
        case '0,1,0'
            shifted(:, 1:end-1, :) = labels(:, 2:end, :);
        case '0,0,-1'
            shifted(:, :, 2:end) = labels(:, :, 1:end-1);
        case '0,0,1'
            shifted(:, :, 1:end-1) = labels(:, :, 2:end);
        otherwise
            error('acsBuildRoastSurfaceBundle:BadInterfaceOffset', ...
                'Unsupported interface offset.');
    end
end

function [V, F] = voxelBoundaryTriangles(i, j, k, sideId)
    i = double(i(:));
    j = double(j(:));
    k = double(k(:));
    n = numel(i);
    V = zeros(4 * n, 3);
    switch sideId
        case 'xMinus'
            x = i - 0.5;
            V = interleaveQuadVertices( ...
                [x, j - 0.5, k - 0.5], ...
                [x, j - 0.5, k + 0.5], ...
                [x, j + 0.5, k + 0.5], ...
                [x, j + 0.5, k - 0.5]);
        case 'xPlus'
            x = i + 0.5;
            V = interleaveQuadVertices( ...
                [x, j - 0.5, k - 0.5], ...
                [x, j + 0.5, k - 0.5], ...
                [x, j + 0.5, k + 0.5], ...
                [x, j - 0.5, k + 0.5]);
        case 'yMinus'
            y = j - 0.5;
            V = interleaveQuadVertices( ...
                [i - 0.5, y, k - 0.5], ...
                [i + 0.5, y, k - 0.5], ...
                [i + 0.5, y, k + 0.5], ...
                [i - 0.5, y, k + 0.5]);
        case 'yPlus'
            y = j + 0.5;
            V = interleaveQuadVertices( ...
                [i - 0.5, y, k - 0.5], ...
                [i - 0.5, y, k + 0.5], ...
                [i + 0.5, y, k + 0.5], ...
                [i + 0.5, y, k - 0.5]);
        case 'zMinus'
            z = k - 0.5;
            V = interleaveQuadVertices( ...
                [i - 0.5, j - 0.5, z], ...
                [i - 0.5, j + 0.5, z], ...
                [i + 0.5, j + 0.5, z], ...
                [i + 0.5, j - 0.5, z]);
        case 'zPlus'
            z = k + 0.5;
            V = interleaveQuadVertices( ...
                [i - 0.5, j - 0.5, z], ...
                [i + 0.5, j - 0.5, z], ...
                [i + 0.5, j + 0.5, z], ...
                [i - 0.5, j + 0.5, z]);
        otherwise
            error('acsBuildRoastSurfaceBundle:BadVoxelSide', ...
                'Unsupported voxel face side "%s".', sideId);
    end
    base = (0:n-1)' .* 4;
    F = [base + 1, base + 2, base + 3; ...
         base + 1, base + 3, base + 4];
end

function V = interleaveQuadVertices(v1, v2, v3, v4)
    n = size(v1, 1);
    V = zeros(4 * n, 3);
    V(1:4:end, :) = v1;
    V(2:4:end, :) = v2;
    V(3:4:end, :) = v3;
    V(4:4:end, :) = v4;
end

function color = brightenColor(color, amount)
    color = double(color(:)');
    color = color + amount .* (1 - color);
    color = max(0, min(1, color));
end

function color = darkenColor(color, amount)
    color = double(color(:)');
    color = color .* (1 - amount);
    color = max(0, min(1, color));
end

function [TR, info] = labelMaskToVoxelSurface(mask, maxFaces, progressLabel, opts)
    if nargin < 3 || isempty(progressLabel)
        progressLabel = 'label mask surface';
    end
    if nargin < 4 || ~isstruct(opts)
        opts = struct('verbose', false);
    end
    idx = find(mask);
    info = struct('voxelCount', numel(idx), ...
        'boundingBoxVoxel1', nan(2, 3), ...
        'faceCountBeforeReduction', 0, ...
        'faceCountAfterReduction', 0, ...
        'maxFacesPerTissue', maxFaces, ...
        'reduced', false, ...
        'message', '');
    TR = [];
    if isempty(idx)
        info.message = 'empty label mask';
        return;
    end
    stageTimer = tic;
    if opts.verbose
        fprintf('    %s: extracting isosurface from %d voxels.\n', ...
            progressLabel, numel(idx));
    end

    dims = size(mask);
    [i, j, k] = ind2sub(dims, idx);
    lo = max([1 1 1], min([i j k], [], 1) - 1);
    hi = min(double(dims), max([i j k], [], 1) + 1);
    info.boundingBoxVoxel1 = [lo; hi];
    if opts.verbose
        fprintf('      %s: local volume bounds [%d %d %d] -> [%d %d %d].\n', ...
            progressLabel, lo(1), lo(2), lo(3), hi(1), hi(2), hi(3));
    end
    local = mask(lo(1):hi(1), lo(2):hi(2), lo(3):hi(3));
    padded = false(size(local) + 2);
    padded(2:end-1, 2:end-1, 2:end-1) = local;

    try
        fv = isosurface(double(padded), 0.5);
    catch ME
        info.message = ME.message;
        return;
    end
    if isempty(fv) || isempty(fv.faces) || isempty(fv.vertices)
        info.message = 'isosurface returned no faces';
        return;
    end
    info.faceCountBeforeReduction = size(fv.faces, 1);
    if opts.verbose
        fprintf('      %s: isosurface produced %d vertices / %d faces.\n', ...
            progressLabel, size(fv.vertices, 1), size(fv.faces, 1));
    end
    if size(fv.faces, 1) > maxFaces && exist('reducepatch', 'file') == 2
        try
            if opts.verbose
                fprintf('      %s: reducing %d faces to target %.0f.\n', ...
                    progressLabel, size(fv.faces, 1), maxFaces);
            end
            fv = reducepatch(fv, maxFaces);
            info.reduced = true;
        catch ME
            info.message = ['reducepatch failed: ' ME.message];
        end
    end
    vertsVoxel1 = [fv.vertices(:, 2), fv.vertices(:, 1), fv.vertices(:, 3)] - 1;
    vertsVoxel1 = bsxfun(@plus, vertsVoxel1, lo - 1);
    TR = triangulation(double(fv.faces), double(vertsVoxel1));
    info.faceCountAfterReduction = size(TR.ConnectivityList, 1);
    if opts.verbose
        fprintf('      %s: finished in %.1f s (%d faces).\n', ...
            progressLabel, toc(stageTimer), info.faceCountAfterReduction);
    end
end

function [TRout, info] = orientMaskBoundarySurface(TRin, mask, labelText, opts)
    V = double(TRin.Points);
    F = double(TRin.ConnectivityList);
    nFaces = size(F, 1);
    info = struct();
    info.enabled = true;
    info.method = 'nearest-neighbor label probe across each face normal';
    info.labelText = labelText;
    info.probeDistanceVoxel = opts.skinShellWindingProbeDistanceVoxel;
    info.faceCount = nFaces;
    info.flippedFaceCount = 0;
    info.outwardVoteCount = 0;
    info.inwardVoteCount = 0;
    info.ambiguousFaceCount = 0;
    info.zeroAreaFaceCount = 0;
    info.message = '';
    TRout = TRin;

    if isempty(V) || isempty(F)
        info.message = 'empty surface';
        return;
    end

    if opts.verbose
        fprintf('      %s: repairing face winding from source label mask.\n', ...
            labelText);
    end

    [centroids, normals, normalLength] = faceGeometry(V, F);
    validNormal = isfinite(normalLength) & normalLength > eps;
    info.zeroAreaFaceCount = nnz(~validNormal);
    if ~any(validNormal)
        info.message = 'no nonzero face normals';
        return;
    end

    probe = opts.skinShellWindingProbeDistanceVoxel;
    plusInside = false(nFaces, 1);
    minusInside = false(nFaces, 1);
    plusInside(validNormal) = sampleMaskNearest( ...
        mask, centroids(validNormal, :) + probe .* normals(validNormal, :));
    minusInside(validNormal) = sampleMaskNearest( ...
        mask, centroids(validNormal, :) - probe .* normals(validNormal, :));

    outward = validNormal & ~plusInside & minusInside;
    inward = validNormal & plusInside & ~minusInside;
    ambiguous = validNormal & ~(outward | inward);

    F(inward, [2 3]) = F(inward, [3 2]);
    TRout = triangulation(F, V);

    info.flippedFaceCount = nnz(inward);
    info.outwardVoteCount = nnz(outward);
    info.inwardVoteCount = nnz(inward);
    info.ambiguousFaceCount = nnz(ambiguous);
    if info.flippedFaceCount > 0
        info.message = 'flipped faces whose normals pointed into skin';
    else
        info.message = 'no inward-facing mask-probe votes';
    end

    if opts.verbose
        fprintf(['      %s: winding repair flipped %d/%d faces; ', ...
            'outward votes %d, inward votes %d, ambiguous %d, zero-area %d.\n'], ...
            labelText, info.flippedFaceCount, nFaces, ...
            info.outwardVoteCount, info.inwardVoteCount, ...
            info.ambiguousFaceCount, info.zeroAreaFaceCount);
    end
end

function [centroids, normals, normalLength] = faceGeometry(V, F)
    a = V(F(:, 1), :);
    b = V(F(:, 2), :);
    c = V(F(:, 3), :);
    centroids = (a + b + c) ./ 3;
    rawNormals = cross(b - a, c - a, 2);
    normalLength = sqrt(sum(rawNormals .^ 2, 2));
    normals = zeros(size(rawNormals));
    valid = normalLength > eps & isfinite(normalLength);
    normals(valid, :) = bsxfun(@rdivide, rawNormals(valid, :), ...
        normalLength(valid));
end

function inside = sampleMaskNearest(mask, points)
    dims = size(mask);
    subs = round(double(points));
    valid = all(isfinite(subs), 2) & ...
        subs(:, 1) >= 1 & subs(:, 1) <= dims(1) & ...
        subs(:, 2) >= 1 & subs(:, 2) <= dims(2) & ...
        subs(:, 3) >= 1 & subs(:, 3) <= dims(3);
    inside = false(size(points, 1), 1);
    if any(valid)
        lin = sub2ind(dims, subs(valid, 1), subs(valid, 2), ...
            subs(valid, 3));
        inside(valid) = mask(lin);
    end
end

function [surface, info] = makeWarpedSkinShellSurface(labels, surfaces, ...
        referenceScalpSurface, scalpSurface, opts)
    surface = struct([]);
    info = struct();
    skinMask = labels == uint8(5);
    if opts.verbose
        fprintf('  building morphed whole-skin shell.\n');
    end
    [TRshell, shellInfo] = labelMaskToVoxelSurface( ...
        skinMask, opts.skinShellMaxFaces, ...
        'whole skin label shell for morphing', opts);
    info.source = 'morphed whole ROAST skin-label shell';
    info.shell = shellInfo;
    info.method = ['whole skin shell vertices are blended toward the ', ...
        'reference-scalp-to-warped-scalp displacement field according ', ...
        'to their relative distance from original outer and inner skin ', ...
        'interfaces'];
    info.outerBlendPower = opts.skinShellOuterBlendPower;
    if isempty(TRshell)
        info.message = 'whole skin shell extraction returned no surface';
        return;
    end
    if opts.repairWarpedSkinShellWinding
        [TRshell, windingInfo] = orientMaskBoundarySurface( ...
            TRshell, skinMask, 'whole skin label shell', opts);
        shellInfo.maskBoundaryWinding = windingInfo;
    else
        shellInfo.maskBoundaryWinding = struct( ...
            'enabled', false, ...
            'message', 'repairWarpedSkinShellWinding=false');
    end

    V = double(TRshell.Points);
    F = double(TRshell.ConnectivityList);
    Vref = double(referenceScalpSurface.TR.Points);
    Vwarp = double(scalpSurface.TR.Points);
    if opts.verbose
        fprintf(['    whole skin shell: %d vertices / %d faces; ', ...
            'reference scalp: %d vertices; warped scalp: %d vertices.\n'], ...
            size(V, 1), size(F, 1), size(Vref, 1), size(Vwarp, 1));
        fprintf('    whole skin shell: matching shell vertices to reference scalp.\n');
    end
    [distRef, refIdx] = nearestPointIndexChunked( ...
        V, Vref, 4000, 'skin shell -> reference scalp', opts);
    displacement = Vwarp(refIdx, :) - Vref(refIdx, :);

    outerIdx = findSurfaceByRole(surfaces, 'roastSkinOuterOriginal');
    innerIdx = findSurfaceByRole(surfaces, 'roastSkinInnerOriginal');
    if ~isempty(outerIdx) && ~isempty(innerIdx)
        if opts.verbose
            fprintf('    whole skin shell: estimating outer/inner blend weights.\n');
        end
        dOuter = nearestDistancesChunked(V, ...
            double(surfaces(outerIdx).TR.Points), 4000, ...
            'skin shell -> original outer skin', opts);
        dInner = nearestDistancesChunked(V, ...
            double(surfaces(innerIdx).TR.Points), 4000, ...
            'skin shell -> original inner skin', opts);
        denom = dOuter + dInner;
        outerWeight = zeros(size(denom));
        good = denom > eps;
        outerWeight(good) = dInner(good) ./ denom(good);
        outerWeight(~good) = double(dOuter(~good) <= dInner(~good));
        weightSource = 'relative distance to original outer/inner skin interfaces';
    else
        robustScale = max(eps, percentileLocal(distRef, 75));
        outerWeight = exp(-0.5 * (distRef ./ robustScale) .^ 2);
        weightSource = 'distance to reference scalp fallback';
    end
    outerWeight = max(0, min(1, outerWeight));
    outerWeight = outerWeight .^ opts.skinShellOuterBlendPower;
    if opts.verbose
        fprintf('    whole skin shell: applying displacement field.\n');
    end
    VwarpedShell = V + bsxfun(@times, outerWeight, displacement);

    info.weightSource = weightSource;
    info.referenceScalpSurface = referenceScalpSurface.name;
    info.warpedScalpSurface = scalpSurface.name;
    info.nVertices = size(V, 1);
    info.nFaces = size(F, 1);
    info.referenceDistanceVoxel = summarizeVector(distRef);
    info.outerWeight = summarizeVector(outerWeight);
    info.appliedDisplacementVoxel = summarizeVector( ...
        sqrt(sum((VwarpedShell - V) .^ 2, 2)));
    info.boundsBefore = [min(V, [], 1); max(V, [], 1)];
    info.boundsAfter = [min(VwarpedShell, [], 1); max(VwarpedShell, [], 1)];

    TRwarpedShell = triangulation(F, VwarpedShell);
    surface = makeSurfaceStruct('warpedSkinShell', 5, TRwarpedShell, ...
        'roastWarpedSkinShell', [0.00 0.72 0.32], 0.16, ...
        'Single morphed whole-skin shell for mesh-native ROAST', info);
end

function item = makeSurfaceStruct(name, labelValue, TR, role, color, alphaValue, ...
        description, info)
    item = struct();
    item.name = char(name);
    item.label = double(labelValue);
    item.role = char(role);
    item.coordinateFrame = 't1Voxel1';
    item.TR = TR;
    item.color = double(color(:)');
    item.alpha = double(alphaValue);
    item.description = char(description);
    item.info = info;
    item.summary = meshSummary(TR);
end

function surfaces = appendSurface(surfaces, item)
    if isempty(surfaces)
        surfaces = item;
    else
        surfaces(end + 1, 1) = item;
    end
end

function [surface, info] = readScalpSurfaceAsVoxel1(cacheFile, stage, Vmask, ...
        surfaceName, surfaceRole, surfaceColor, opts)
    cacheFile = expandUserPath(char(cacheFile));
    requireFile(cacheFile, 'capMaker scalp cache');
    S = load(cacheFile);
    if ~isfield(S, 'meta')
        error('acsBuildRoastSurfaceBundle:MissingSkinMeta', ...
            'Scalp cache does not contain meta: %s', cacheFile);
    end
    [TR, frame, variableName] = selectScalpTriangulation(S, stage);
    pointsVoxel1 = scalpPointsToVoxel1(double(TR.Points), frame, S.meta, Vmask);
    TRvoxel1 = triangulation(double(TR.ConnectivityList), pointsVoxel1);

    info = struct();
    info.cacheFile = cacheFile;
    info.sourceVariable = variableName;
    info.sourceFrame = frame;
    info.targetFrame = 't1Voxel1';
    info.transformMethod = transformMethodForFrame(frame);
    info.sourceSummary = meshSummary(TR);
    info.targetSummary = meshSummary(TRvoxel1);

    surface = makeSurfaceStruct(surfaceName, 5, TRvoxel1, ...
        surfaceRole, surfaceColor, 0.10, ...
        sprintf('capMaker %s scalp surface mapped from %s', stage, frame), ...
        info);
end

function [surface, info] = readHeadpostSurfaceAsVoxel1( ...
        placementFile, skinCacheFile, Vmask, opts)
    placementFile = expandUserPath(char(placementFile));
    requireFile(placementFile, 'headpost placement');
    placement = loadStructFromMat(placementFile);
    if ~isfield(placement, 'meshes') || ~isstruct(placement.meshes) || ...
            ~isfield(placement.meshes, 'TRplaced')
        error('acsBuildRoastSurfaceBundle:MissingHeadpostMesh', ...
            'Headpost placement does not contain meshes.TRplaced: %s', ...
            placementFile);
    end
    TRplaced = ensureTri(placement.meshes.TRplaced);
    if isempty(skinCacheFile)
        skinCacheFile = placementSkinCacheFile(placement);
    end
    skinCacheFile = expandUserPath(char(skinCacheFile));
    requireFile(skinCacheFile, 'headpost placement skin cache');
    Sskin = load(skinCacheFile, 'meta');
    if ~isfield(Sskin, 'meta') || isempty(Sskin.meta)
        error('acsBuildRoastSurfaceBundle:MissingHeadpostSkinMeta', ...
            'Skin cache lacks meta needed to map headpost mesh: %s', ...
            skinCacheFile);
    end

    pointsVoxel1 = printMmToT1Voxel1(double(TRplaced.Points), Sskin.meta, Vmask);
    TRvoxel1 = triangulation(double(TRplaced.ConnectivityList), pointsVoxel1);

    info = struct();
    info.placementFile = placementFile;
    info.skinCacheFile = skinCacheFile;
    info.sourceFrame = optionalCharField(placement, 'coordinateFrame', ...
        'capMakerPrintMm');
    info.targetFrame = 't1Voxel1';
    info.transformMethod = 'headpost placement print mm -> pre-crop mm -> T1 voxel1';
    info.sourceSummary = meshSummary(TRplaced);
    info.targetSummary = meshSummary(TRvoxel1);
    if isfield(placement, 'headpost') && isstruct(placement.headpost)
        info.materialSource = optionalCharField(placement.headpost, ...
            'meshFile', '');
    else
        info.materialSource = '';
    end

    surface = makeSurfaceStruct('titaniumHeadpost', 7, TRvoxel1, ...
        'extraTissueTitanium', [0.85 0.00 0.00], 0.46, ...
        'Placed titanium headpost mesh mapped into T1 voxel frame', info);
end

function value = loadStructFromMat(fileName)
    S = load(fileName);
    if isfield(S, 'out')
        value = S.out;
    elseif isfield(S, 'outForSave')
        value = S.outForSave;
    else
        value = firstStruct(S);
    end
end

function skinCacheFile = placementSkinCacheFile(placement)
    skinCacheFile = '';
    if isfield(placement, 'surfaceSource') && isstruct(placement.surfaceSource)
        if isfield(placement.surfaceSource, 'cacheFile') && ...
                ~isempty(placement.surfaceSource.cacheFile)
            skinCacheFile = char(placement.surfaceSource.cacheFile);
        elseif isfield(placement.surfaceSource, 'file') && ...
                ~isempty(placement.surfaceSource.file)
            skinCacheFile = char(placement.surfaceSource.file);
        end
    end
    if isempty(skinCacheFile)
        error('acsBuildRoastSurfaceBundle:MissingHeadpostSkinCache', ...
            ['headpostSkinCacheFile was not provided and the placement ', ...
             'does not report surfaceSource.cacheFile.']);
    end
end

function [TR, frame, variableName] = selectScalpTriangulation(S, stage)
    candidates = {};
    switch stage
        case 'stableHead'
            candidates = {'TRstableHead', 'meta.stableHead.TR', ...
                'TRfiducialHead', 'TRskin'};
        case 'fiducialHead'
            candidates = {'TRfiducialHead', 'meta.fiducialHead.TR', ...
                'TRstableHead', 'TRskin'};
        case 'skin'
            candidates = {'TRskin', 'TRfiducialHead', 'TRstableHead'};
    end
    TR = [];
    variableName = '';
    for c = 1:numel(candidates)
        [ok, value] = getNestedField(S, candidates{c});
        if ok && ~isempty(value)
            TR = ensureTri(value);
            variableName = candidates{c};
            break;
        end
    end
    if isempty(TR)
        error('acsBuildRoastSurfaceBundle:MissingScalpMesh', ...
            'Could not find a usable scalp mesh in the supplied cache.');
    end
    frame = frameForScalpVariable(S, variableName);
end

function [ok, value] = getNestedField(S, pathText)
    parts = strsplit(char(pathText), '.');
    value = S;
    ok = true;
    for i = 1:numel(parts)
        if isstruct(value) && isfield(value, parts{i})
            value = value.(parts{i});
        else
            ok = false;
            value = [];
            return;
        end
    end
end

function frame = frameForScalpVariable(S, variableName)
    switch variableName
        case {'TRstableHead', 'meta.stableHead.TR'}
            frame = 'capMakerPreCropWorldMm';
        case {'TRfiducialHead', 'meta.fiducialHead.TR'}
            frame = 'capMakerPrintMm';
        otherwise
            frame = 'capMakerPrintMm';
    end
    if isfield(S, 'meta') && isstruct(S.meta)
        switch variableName
            case {'TRstableHead', 'meta.stableHead.TR'}
                frame = nestedChar(S.meta, {'stableHead', 'coordinateFrame'}, frame);
            case {'TRfiducialHead', 'meta.fiducialHead.TR'}
                frame = nestedChar(S.meta, {'fiducialHead', 'coordinateFrame'}, frame);
        end
    end
end

function value = nestedChar(S, pathParts, defaultValue)
    value = defaultValue;
    cursor = S;
    for i = 1:numel(pathParts)
        if isstruct(cursor) && isfield(cursor, pathParts{i})
            cursor = cursor.(pathParts{i});
        else
            return;
        end
    end
    if ~isempty(cursor)
        value = char(cursor);
    end
end

function pointsVoxel1 = scalpPointsToVoxel1(points, frame, meta, Vmask)
    switch lower(char(frame))
        case lower('capMakerPreCropWorldMm')
            pointsVoxel1 = stableWorldMmToT1ArrayVoxel1(points, Vmask);
        case lower('capMakerPrintMm')
            pointsVoxel1 = printMmToT1Voxel1(points, meta, Vmask);
        otherwise
            error('acsBuildRoastSurfaceBundle:UnsupportedScalpFrame', ...
                'Unsupported scalp coordinate frame "%s".', frame);
    end
end

function method = transformMethodForFrame(frame)
    switch lower(char(frame))
        case lower('capMakerPreCropWorldMm')
            method = 'capMaker pre-crop mm divided by ROAST mask voxel size + 1';
        case lower('capMakerPrintMm')
            method = 'print -> pre-crop mm, then divide by ROAST mask voxel size + 1';
        otherwise
            method = 'unknown';
    end
end

function vox1 = printMmToT1Voxel1(pointsPrintMm, meta, Vref)
    requirePrintTransforms(meta);
    finalWorldMm = applyAffineToPoints(meta.print.T_print2world, pointsPrintMm);
    stableWorldMm = (double(meta.align.R) \ finalWorldMm')';
    vox1 = stableWorldMmToT1ArrayVoxel1(stableWorldMm, Vref);

    refDims = double(Vref.dim(1:3));
    voxelSpan = max(vox1, [], 1) - min(vox1, [], 1);
    if any(voxelSpan > 10 * max(refDims))
        warning('acsBuildRoastSurfaceBundle:SuspiciousVoxelBounds', ...
            ['Mapped print-frame scalp points span far more than the T1 ', ...
             'volume. Check skin-cache transform metadata.']);
    end
end

function vox1 = stableWorldMmToT1ArrayVoxel1(pointsStableMm, Vref)
    voxelSize = voxelSizesFromMat(Vref.mat);
    vox1 = bsxfun(@rdivide, double(pointsStableMm), voxelSize) + 1;
end

function voxelSize = voxelSizesFromMat(M)
    voxelSize = sqrt(sum(double(M(1:3, 1:3)) .^ 2, 1));
    voxelSize(~isfinite(voxelSize) | voxelSize <= 0) = 1;
end

function requirePrintTransforms(meta)
    ok = isstruct(meta) && isfield(meta, 'print') && isstruct(meta.print) && ...
        isfield(meta.print, 'T_print2world') && ...
        isequal(size(meta.print.T_print2world), [4 4]) && ...
        isfield(meta, 'align') && isstruct(meta.align) && ...
        isfield(meta.align, 'R') && isequal(size(meta.align.R), [3 3]);
    if ~ok
        error('acsBuildRoastSurfaceBundle:BadSkinMeta', ...
            'Skin metadata lacks print.T_print2world or align.R.');
    end
end

function pointsOut = applyAffineToPoints(M, pointsIn)
    pointsHom = [double(pointsIn), ones(size(pointsIn, 1), 1)];
    pointsHom = (double(M) * pointsHom')';
    pointsOut = pointsHom(:, 1:3);
end

function TR = ensureTri(value)
    if isa(value, 'triangulation')
        TR = value;
    elseif isstruct(value) && isfield(value, 'ConnectivityList') && ...
            isfield(value, 'Points')
        TR = triangulation(double(value.ConnectivityList), double(value.Points));
    else
        error('acsBuildRoastSurfaceBundle:BadTriangulation', ...
            'Expected a triangulation or struct with Points/ConnectivityList.');
    end
end

function fig = makeQcFigure(t1, labels, surfaces, source, opts, figVisible)
    dims = size(labels);
    sliceInd = chooseSliceIndices(labels, surfaces);
    voxelSize = [1 1 1];
    if isfield(source, 'maskFile') && exist(source.maskFile, 'file') == 2
        try
            Vmask = spm_vol(source.maskFile);
            voxelSize = voxelSizesFromMat(Vmask(1).mat);
        catch
            voxelSize = [1 1 1];
        end
    end
    fig = figure('Name', 'ROAST mesh-native surface bundle QC', ...
        'NumberTitle', 'off', 'Color', 'w', 'Visible', figVisible, ...
        'Units', 'pixels', 'Position', [80 80 1500 840]);
    tl = tiledlayout(fig, 2, 3, 'Padding', 'compact', 'TileSpacing', 'compact');
    title(tl, 'ROAST mesh-native surface bundle QC', ...
        'Interpreter', 'none', 'FontSize', 13, 'FontWeight', 'bold');

    ax3 = nexttile(tl, [1 3]);
    hold(ax3, 'on');
    draw3dSurfaces(ax3, surfaces, voxelSize);
    title(ax3, 'Surfaces in T1 physical frame', ...
        'Interpreter', 'none', 'FontSize', 11);
    axis(ax3, 'equal');
    axis(ax3, 'vis3d');
    grid(ax3, 'on');
    xlabel(ax3, 'dim 1 (mm)');
    ylabel(ax3, 'dim 2 (mm)');
    zlabel(ax3, 'dim 3 (mm)');
    view(ax3, 35, 22);
    camlight(ax3, 'headlight');
    lighting(ax3, 'flat');

    planeNames = {'Sagittal', 'Coronal', 'Axial'};
    for dimToFix = 1:3
        ax = nexttile(tl);
        drawSliceOverlay(ax, t1, labels, surfaces, dimToFix, ...
            sliceInd(dimToFix), opts);
        title(ax, sprintf('%s %d', planeNames{dimToFix}, ...
            sliceInd(dimToFix)), 'Interpreter', 'none', ...
            'FontSize', 10, 'FontWeight', 'bold');
    end

    addSurfaceLegend(fig, surfaces, source);
end

function sliceInd = chooseSliceIndices(labels, surfaces)
    dims = size(labels);
    rows = find(labels > 0 & labels ~= 6);
    if isempty(rows)
        sliceInd = max(1, round(dims(1:3) ./ 2));
    else
        [i, j, k] = ind2sub(dims, rows);
        sliceInd = round(median([i j k], 1));
    end
    scalpIdx = [];
    if ~isempty(surfaces)
        scalpIdx = find(strcmpi({surfaces.role}, 'capMakerScalpOuter'), 1);
    end
    if ~isempty(scalpIdx)
        V = double(surfaces(scalpIdx).TR.Points);
        if ~isempty(V) && all(any(isfinite(V), 1))
            sliceInd = round(0.65 .* sliceInd + 0.35 .* median(V, 1));
        end
    end
    sliceInd = max([1 1 1], min(dims(1:3), sliceInd));
end

function draw3dSurfaces(ax, surfaces, voxelSize)
    for i = 1:numel(surfaces)
        TR = surfaces(i).TR;
        if isempty(TR)
            continue;
        end
        TRplot = surfaceForPhysicalDisplay(TR, voxelSize);
        if strcmpi(surfaces(i).role, 'capMakerScalpOuter')
            h = patch(ax, 'Faces', TRplot.ConnectivityList, 'Vertices', TRplot.Points, ...
                'FaceColor', 'none', 'EdgeColor', surfaces(i).color, ...
                'LineWidth', 0.35);
            try
                set(h, 'EdgeAlpha', 0.28);
            catch
            end
        elseif strcmpi(surfaces(i).role, 'capMakerScalpReference')
            h = patch(ax, 'Faces', TRplot.ConnectivityList, 'Vertices', TRplot.Points, ...
                'FaceColor', 'none', 'EdgeColor', surfaces(i).color, ...
                'LineStyle', ':', 'LineWidth', 0.25);
            try
                set(h, 'EdgeAlpha', 0.20);
            catch
            end
        elseif strcmpi(surfaces(i).role, 'roastSkinInnerOriginal')
            patch(ax, 'Faces', TRplot.ConnectivityList, 'Vertices', TRplot.Points, ...
                'FaceColor', surfaces(i).color, ...
                'FaceAlpha', surfaces(i).alpha, ...
                'EdgeColor', 'none', ...
                'FaceLighting', 'flat', ...
                'AmbientStrength', 0.80, ...
                'DiffuseStrength', 0.25, ...
                'SpecularStrength', 0);
        elseif strcmpi(surfaces(i).role, 'roastSkinOuterOriginal')
            h = patch(ax, 'Faces', TRplot.ConnectivityList, 'Vertices', TRplot.Points, ...
                'FaceColor', 'none', ...
                'EdgeColor', surfaces(i).color, ...
                'LineStyle', '-', ...
                'LineWidth', 0.18);
            try
                set(h, 'EdgeAlpha', 0.18);
            catch
            end
        elseif strcmpi(surfaces(i).role, 'extraTissueTitanium')
            patch(ax, 'Faces', TRplot.ConnectivityList, 'Vertices', TRplot.Points, ...
                'FaceColor', surfaces(i).color, ...
                'FaceAlpha', surfaces(i).alpha, ...
                'EdgeColor', 'none', ...
                'FaceLighting', 'flat', ...
                'AmbientStrength', 0.85, ...
                'DiffuseStrength', 0.20, ...
                'SpecularStrength', 0);
        else
            patch(ax, 'Faces', TRplot.ConnectivityList, 'Vertices', TRplot.Points, ...
                'FaceColor', surfaces(i).color, ...
                'FaceAlpha', surfaces(i).alpha, ...
                'EdgeColor', 'none', ...
                'FaceLighting', 'flat', ...
                'AmbientStrength', 0.75, ...
                'DiffuseStrength', 0.30, ...
                'SpecularStrength', 0);
        end
    end
end

function TRplot = surfaceForPhysicalDisplay(TR, voxelSize)
    voxelSize = double(voxelSize(:)');
    if numel(voxelSize) < 3 || any(~isfinite(voxelSize(1:3))) || ...
            any(voxelSize(1:3) <= 0)
        voxelSize = [1 1 1];
    else
        voxelSize = voxelSize(1:3);
    end
    pointsMm = bsxfun(@times, double(TR.Points) - 1, voxelSize);
    TRplot = triangulation(double(TR.ConnectivityList), pointsMm);
end

function drawSliceOverlay(ax, t1, labels, surfaces, dimToFix, idx, opts)
    dims = size(labels);
    [img, xvec, yvec] = sliceForDisplay(t1, dimToFix, idx);
    imagesc(ax, xvec, yvec, img);
    set(ax, 'YDir', 'normal');
    axis(ax, 'image');
    colormap(ax, gray);
    caxis(ax, robustClim(t1));
    hold(ax, 'on');

    styles = labelStyles();
    contourLabels = [1 2 3 4 5];
    for labelValue = contourLabels
        if isempty(surfaces) || ~any([surfaces.label] == labelValue)
            continue;
        end
        [maskSlice, ~, ~] = sliceForDisplay(labels == uint8(labelValue), ...
            dimToFix, idx);
        if any(maskSlice(:))
            style = styleForLabel(styles, labelValue);
            contour(ax, xvec, yvec, double(maskSlice), [0.5 0.5], ...
                'Color', style.color, 'LineWidth', 0.75);
        end
    end

    for i = 1:numel(surfaces)
        if isempty(surfaces(i).TR)
            continue;
        end
        P = meshPlaneIntersections(surfaces(i).TR, dimToFix, idx, ...
            opts.sliceOverlayToleranceVoxel);
        if isempty(P)
            continue;
        end
        [x, y] = projectPointsToSlice(P, dimToFix);
        if strcmpi(surfaces(i).role, 'capMakerScalpOuter')
            scatter(ax, x, y, 3, surfaces(i).color, 'filled', ...
                'MarkerFaceAlpha', 0.45, 'MarkerEdgeColor', 'none');
        elseif strcmpi(surfaces(i).role, 'capMakerScalpReference')
            scatter(ax, x, y, 3, surfaces(i).color, 'filled', ...
                'MarkerFaceAlpha', 0.22, 'MarkerEdgeColor', 'none');
        elseif any(strcmpi(surfaces(i).role, ...
                {'roastSkinOuterOriginal', 'roastSkinInnerOriginal', ...
                 'extraTissueTitanium'}))
            scatter(ax, x, y, 3, surfaces(i).color, 'filled', ...
                'MarkerFaceAlpha', 0.32, 'MarkerEdgeColor', 'none');
        end
    end
    xlim(ax, [min(xvec) max(xvec)]);
    ylim(ax, [min(yvec) max(yvec)]);
    xlabel(ax, xLabelForDim(dimToFix));
    ylabel(ax, yLabelForDim(dimToFix));
end

function [img, xvec, yvec] = sliceForDisplay(vol, dimToFix, idx)
    dims = size(vol);
    switch dimToFix
        case 1
            raw = squeeze(vol(idx, :, :));
            img = raw';
            xvec = 1:dims(2);
            yvec = 1:dims(3);
        case 2
            raw = squeeze(vol(:, idx, :));
            img = raw';
            xvec = 1:dims(1);
            yvec = 1:dims(3);
        case 3
            raw = squeeze(vol(:, :, idx));
            img = raw';
            xvec = 1:dims(1);
            yvec = 1:dims(2);
        otherwise
            error('acsBuildRoastSurfaceBundle:BadSliceDim', ...
                'Slice dimension must be 1, 2, or 3.');
    end
end

function P = meshPlaneIntersections(TR, dimToFix, idx, tol)
    V = double(TR.Points);
    F = double(TR.ConnectivityList);
    if isempty(V) || isempty(F)
        P = zeros(0, 3);
        return;
    end
    E = unique(sort([F(:, [1 2]); F(:, [2 3]); F(:, [1 3])], 2), 'rows');
    P0 = V(E(:, 1), :);
    P1 = V(E(:, 2), :);
    d0 = P0(:, dimToFix) - idx;
    d1 = P1(:, dimToFix) - idx;
    crosses = (d0 <= 0 & d1 >= 0) | (d0 >= 0 & d1 <= 0);
    sameSideNear = abs(d0) <= tol & abs(d1) <= tol;
    keep = crosses | sameSideNear;
    if ~any(keep)
        nearVertex = abs(V(:, dimToFix) - idx) <= tol;
        P = V(nearVertex, :);
        return;
    end
    P0 = P0(keep, :);
    P1 = P1(keep, :);
    d0 = d0(keep);
    d1 = d1(keep);
    den = d1 - d0;
    t = zeros(size(den));
    nonzero = abs(den) > eps;
    t(nonzero) = -d0(nonzero) ./ den(nonzero);
    t(~nonzero) = 0.5;
    t = max(0, min(1, t));
    P = P0 + t .* (P1 - P0);
    P = unique(round(P .* 1000) ./ 1000, 'rows');
end

function [x, y] = projectPointsToSlice(P, dimToFix)
    switch dimToFix
        case 1
            x = P(:, 2);
            y = P(:, 3);
        case 2
            x = P(:, 1);
            y = P(:, 3);
        case 3
            x = P(:, 1);
            y = P(:, 2);
    end
end

function value = xLabelForDim(dimToFix)
    switch dimToFix
        case 1
            value = 'dim 2';
        case 2
            value = 'dim 1';
        case 3
            value = 'dim 1';
    end
end

function value = yLabelForDim(dimToFix)
    switch dimToFix
        case 1
            value = 'dim 3';
        case 2
            value = 'dim 3';
        case 3
            value = 'dim 2';
    end
end

function addSurfaceLegend(fig, surfaces, source)
    ax = axes(fig, 'Position', [0.69 0.75 0.29 0.22]); %#ok<LAXES>
    axis(ax, 'off');
    entries = surfaceLegendEntries(surfaces);
    y = 0.94;
    text(ax, 0, y, 'Surface bundle', 'FontWeight', 'bold', ...
        'Interpreter', 'none', 'FontSize', 8);
    y = y - 0.14;
    nRows = min(7, max(1, ceil(numel(entries) / 2)));
    colX = [0.00 0.52];
    for i = 1:numel(entries)
        col = 1 + floor((i - 1) / nRows);
        row = mod(i - 1, nRows);
        if col > 2
            break;
        end
        text(ax, colX(col), y - 0.12 * row, entries(i).text, ...
            'Color', entries(i).color, 'Interpreter', 'none', ...
            'FontSize', 7.5, 'FontWeight', 'bold');
    end
    if isfield(source, 'maskFile')
        text(ax, 0, 0.02, getFileName(source.maskFile), ...
            'Interpreter', 'none', 'FontSize', 7, ...
            'Color', [0.25 0.25 0.25]);
    end
end

function entries = surfaceLegendEntries(surfaces)
    entries = struct('text', {}, 'color', {});
    priority = { ...
        'capMakerScalpOuter', ...
        'extraTissueTitanium', ...
        'roastSkinInnerOriginal', ...
        'roastSkinOuterOriginal', ...
        'capMakerScalpReference'};
    for i = 1:numel(priority)
        idx = find(strcmpi({surfaces.role}, priority{i}), 1);
        if ~isempty(idx)
            entries = appendLegendEntry(entries, ...
                legendTextForSurface(surfaces(idx)), surfaces(idx).color);
        end
    end
    for labelValue = [1 2 3 4 6]
        idx = find([surfaces.label] == labelValue & ...
            strcmpi({surfaces.role}, 'mriHardLabel'), 1);
        if ~isempty(idx)
            entries = appendLegendEntry(entries, ...
                legendTextForSurface(surfaces(idx)), surfaces(idx).color);
        end
    end
end

function entries = appendLegendEntry(entries, textValue, color)
    if any(strcmpi({entries.text}, textValue))
        return;
    end
    item = struct('text', char(textValue), 'color', double(color(:)'));
    if isempty(entries)
        entries = item;
    else
        entries(end + 1, 1) = item;
    end
end

function labelText = legendTextForSurface(surface)
    if strcmpi(surface.role, 'capMakerScalpOuter')
        labelText = 'warped outer scalp';
    elseif strcmpi(surface.role, 'roastWarpedSkinShell')
        labelText = 'morphed skin shell';
    elseif strcmpi(surface.role, 'capMakerScalpReference')
        labelText = 'reference scalp';
    elseif strcmpi(surface.role, 'roastSkinOuterOriginal')
        labelText = 'original outer skin';
    elseif strcmpi(surface.role, 'roastSkinInnerOriginal')
        labelText = 'original inner skin';
    elseif strcmpi(surface.role, 'extraTissueTitanium')
        labelText = 'titanium headpost';
    else
        labelText = sprintf('%d %s', surface.label, surface.name);
    end
end

function lim = robustClim(vol)
    values = double(vol(:));
    values = values(isfinite(values));
    if isempty(values)
        lim = [0 1];
        return;
    end
    lo = percentileLocal(values, 1);
    hi = percentileLocal(values, 99);
    if ~isfinite(lo) || ~isfinite(hi) || hi <= lo
        lo = min(values);
        hi = max(values);
    end
    if hi <= lo
        hi = lo + 1;
    end
    lim = [lo hi];
end

function styles = labelStyles()
    styles = struct( ...
        'label', num2cell(0:7), ...
        'name', {'background', 'white', 'gray', 'CSF', 'bone', ...
            'skin', 'air', 'titanium'}, ...
        'color', { ...
            [0.00 0.00 0.00], ...
            [0.00 0.75 0.95], ...
            [1.00 0.20 0.12], ...
            [0.15 0.30 0.95], ...
            [1.00 0.78 0.02], ...
            [0.05 0.75 0.25], ...
            [0.45 0.45 0.45], ...
            [0.85 0.00 0.00]});
end

function style = styleForLabel(styles, labelValue)
    idx = find([styles.label] == labelValue, 1);
    if isempty(idx)
        style = struct('label', labelValue, ...
            'name', sprintf('label%d', labelValue), ...
            'color', [0.20 0.20 0.20]);
    else
        style = styles(idx);
    end
end

function summary = summarizeSurfaces(surfaces)
    summary = struct([]);
    for i = 1:numel(surfaces)
        summary(i, 1).name = surfaces(i).name; %#ok<AGROW>
        summary(i, 1).label = surfaces(i).label;
        summary(i, 1).role = surfaces(i).role;
        summary(i, 1).coordinateFrame = surfaces(i).coordinateFrame;
        summary(i, 1).nVertices = surfaces(i).summary.nVertices;
        summary(i, 1).nFaces = surfaces(i).summary.nFaces;
        summary(i, 1).bounds = surfaces(i).summary.bounds;
    end
end

function shell = makeSkinShellDiagnostics(surfaces, opts)
    shell = struct();
    shell.method = ['diagnostic split skin interfaces plus optional ', ...
        'morphed whole-skin shell for meshing'];
    shell.coordinateFrame = 't1Voxel1';
    shell.originalOuterIndex = findSurfaceByRole(surfaces, ...
        'roastSkinOuterOriginal');
    shell.originalInnerIndex = findSurfaceByRole(surfaces, ...
        'roastSkinInnerOriginal');
    shell.replacementOuterIndex = findSurfaceByRole(surfaces, ...
        'capMakerScalpOuter');
    shell.warpedShellIndex = findSurfaceByRole(surfaces, ...
        'roastWarpedSkinShell');
    shell.hasOriginalOuter = ~isempty(shell.originalOuterIndex);
    shell.hasOriginalInner = ~isempty(shell.originalInnerIndex);
    shell.hasReplacementOuter = ~isempty(shell.replacementOuterIndex);
    shell.hasWarpedShell = ~isempty(shell.warpedShellIndex);

    if shell.hasOriginalOuter
        shell.originalOuter = meshSummary(surfaces(shell.originalOuterIndex).TR);
    else
        shell.originalOuter = struct();
    end
    if shell.hasOriginalInner
        shell.originalInner = meshSummary(surfaces(shell.originalInnerIndex).TR);
    else
        shell.originalInner = struct();
    end
    if shell.hasReplacementOuter
        shell.replacementOuter = meshSummary( ...
            surfaces(shell.replacementOuterIndex).TR);
    else
        shell.replacementOuter = struct();
    end
    if shell.hasWarpedShell
        shell.warpedShell = meshSummary(surfaces(shell.warpedShellIndex).TR);
        shell.warpedShellInfo = surfaces(shell.warpedShellIndex).info;
    else
        shell.warpedShell = struct();
        shell.warpedShellInfo = struct();
    end

    shell.replacementToOriginalOuterDistanceVoxel = struct();
    shell.originalInnerToReplacementOuterDistanceVoxel = struct();
    if shell.hasReplacementOuter && shell.hasOriginalOuter
        shell.replacementToOriginalOuterDistanceVoxel = ...
            sampledNearestSurfaceDistance( ...
            surfaces(shell.replacementOuterIndex).TR, ...
            surfaces(shell.originalOuterIndex).TR, ...
            opts.shellClearanceSampleCount);
    end
    if shell.hasOriginalInner && shell.hasReplacementOuter
        shell.originalInnerToReplacementOuterDistanceVoxel = ...
            sampledNearestSurfaceDistance( ...
            surfaces(shell.originalInnerIndex).TR, ...
            surfaces(shell.replacementOuterIndex).TR, ...
            opts.shellClearanceSampleCount);
    end

    if shell.hasOriginalInner && shell.hasReplacementOuter
        shell.centroidDeltaReplacementOuterMinusInner = ...
            shell.replacementOuter.centroid - shell.originalInner.centroid;
        shell.boundsGapReplacementOuterMinusInner = [ ...
            shell.replacementOuter.bounds(1, :) - shell.originalInner.bounds(1, :); ...
            shell.replacementOuter.bounds(2, :) - shell.originalInner.bounds(2, :)];
    else
        shell.centroidDeltaReplacementOuterMinusInner = [nan nan nan];
        shell.boundsGapReplacementOuterMinusInner = nan(2, 3);
    end
end

function diagnostics = makeImplantDiagnostics(surfaces, opts)
    diagnostics = struct();
    diagnostics.coordinateFrame = 't1Voxel1';
    diagnostics.contactToleranceVoxel = opts.surfaceContactToleranceVoxel;
    diagnostics.policy = struct( ...
        'solidLabel', 7, ...
        'solidName', 'titanium', ...
        'rule', ['titanium is treated as the solid implanted domain; ', ...
                 'intersecting non-titanium tissues must be trimmed or ', ...
                 'made conformal before tetrahedral meshing'], ...
        'replaceableLabels', [0 4 5 6], ...
        'protectedLabels', [1 2 3]);
    diagnostics.hasTitanium = false;
    diagnostics.titaniumIndex = findSurfaceByRole(surfaces, ...
        'extraTissueTitanium');
    diagnostics.surfacePairs = struct([]);
    if isempty(diagnostics.titaniumIndex)
        return;
    end
    diagnostics.hasTitanium = true;
    titanium = surfaces(diagnostics.titaniumIndex);
    targets = implantDiagnosticTargets(surfaces, diagnostics.titaniumIndex);
    for i = 1:numel(targets)
        target = surfaces(targets(i));
        pair = struct();
        pair.titaniumSurface = titanium.name;
        pair.otherSurface = target.name;
        pair.otherRole = target.role;
        pair.otherLabel = target.label;
        pair.distanceVoxel = sampledNearestSurfaceDistance( ...
            titanium.TR, target.TR, opts.shellClearanceSampleCount);
        pair.possibleContactOrIntersection = ...
            isfield(pair.distanceVoxel, 'min') && ...
            isfinite(pair.distanceVoxel.min) && ...
            pair.distanceVoxel.min <= opts.surfaceContactToleranceVoxel;
        pair.actionIfIntersecting = implantIntersectionAction( ...
            target.label, diagnostics.policy);
        diagnostics.surfacePairs = appendDiagnostic( ...
            diagnostics.surfacePairs, pair);
    end
end

function idx = implantDiagnosticTargets(surfaces, titaniumIdx)
    idx = [];
    for i = 1:numel(surfaces)
        if i == titaniumIdx || isempty(surfaces(i).TR)
            continue;
        end
        role = surfaces(i).role;
        if strcmpi(role, 'capMakerScalpReference') || ...
                strcmpi(role, 'roastSkinOuterOriginal')
            continue;
        end
        idx(end + 1, 1) = i; %#ok<AGROW>
    end
end

function action = implantIntersectionAction(labelValue, policy)
    labelValue = double(labelValue);
    if ismember(labelValue, policy.protectedLabels)
        action = ['warning: titanium intersects protected brain/CSF ', ...
            'domain; inspect placement before meshing'];
    elseif ismember(labelValue, policy.replaceableLabels) || labelValue == 5
        action = ['trim non-titanium tissue around titanium and make a ', ...
            'shared conformal interface'];
    else
        action = 'inspect and resolve as a conformal material boundary';
    end
end

function idx = findSurfaceByRole(surfaces, roleName)
    idx = [];
    if isempty(surfaces)
        return;
    end
    idx = find(strcmpi({surfaces.role}, roleName), 1);
end

function stats = sampledNearestSurfaceDistance(TRquery, TRtarget, maxSamples)
    Q = sampleSurfaceVertices(TRquery, maxSamples);
    T = sampleSurfaceVertices(TRtarget, maxSamples);
    stats = struct('nQuery', size(Q, 1), ...
        'nTarget', size(T, 1), ...
        'min', NaN, 'median', NaN, 'p05', NaN, 'p95', NaN, ...
        'max', NaN, 'mean', NaN);
    if isempty(Q) || isempty(T)
        return;
    end
    D = nearestDistancesChunked(Q, T, 2000);
    stats.min = min(D);
    stats.median = percentileLocal(D, 50);
    stats.p05 = percentileLocal(D, 5);
    stats.p95 = percentileLocal(D, 95);
    stats.max = max(D);
    stats.mean = mean(D);
end

function P = sampleSurfaceVertices(TR, maxSamples)
    P = double(TR.Points);
    P = P(all(isfinite(P), 2), :);
    if size(P, 1) <= maxSamples
        return;
    end
    idx = unique(round(linspace(1, size(P, 1), maxSamples)));
    P = P(idx, :);
end

function D = nearestDistancesChunked(Q, T, chunkSize, progressLabel, opts)
    if nargin < 4 || isempty(progressLabel)
        progressLabel = 'nearest distance';
    end
    if nargin < 5 || ~isstruct(opts)
        opts = struct('verbose', false);
    end
    D = inf(size(Q, 1), 1);
    nQuery = size(Q, 1);
    nTarget = size(T, 1);
    doVerbose = isfield(opts, 'verbose') && opts.verbose && nQuery > 0 && ...
        nTarget > 0;
    nextPct = 0;
    stageTimer = tic;
    if doVerbose
        fprintf('      %s: %d query x %d target points.\n', ...
            progressLabel, nQuery, nTarget);
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
            nextPct = maybePrintProgress(progressLabel, last, nQuery, ...
                nextPct, stageTimer, 10);
        end
    end
end

function [D, idx] = nearestPointIndexChunked(Q, T, chunkSize, progressLabel, opts)
    if nargin < 4 || isempty(progressLabel)
        progressLabel = 'nearest point';
    end
    if nargin < 5 || ~isstruct(opts)
        opts = struct('verbose', false);
    end
    D2 = inf(size(Q, 1), 1);
    idx = ones(size(Q, 1), 1);
    if isempty(Q) || isempty(T)
        D = sqrt(D2);
        idx = zeros(size(Q, 1), 1);
        return;
    end
    nQuery = size(Q, 1);
    nTarget = size(T, 1);
    doVerbose = isfield(opts, 'verbose') && opts.verbose;
    nextPct = 0;
    stageTimer = tic;
    if doVerbose
        fprintf('      %s: %d query x %d target points.\n', ...
            progressLabel, nQuery, nTarget);
    end
    for first = 1:chunkSize:size(Q, 1)
        last = min(size(Q, 1), first + chunkSize - 1);
        q = Q(first:last, :);
        best = inf(size(q, 1), 1);
        bestIdx = ones(size(q, 1), 1);
        for tFirst = 1:chunkSize:size(T, 1)
            tLast = min(size(T, 1), tFirst + chunkSize - 1);
            t = T(tFirst:tLast, :);
            dx = q(:, 1) - t(:, 1)';
            dy = q(:, 2) - t(:, 2)';
            dz = q(:, 3) - t(:, 3)';
            dist2 = dx .^ 2 + dy .^ 2 + dz .^ 2;
            [chunkBest, chunkIdx] = min(dist2, [], 2);
            replace = chunkBest < best;
            best(replace) = chunkBest(replace);
            bestIdx(replace) = tFirst + chunkIdx(replace) - 1;
        end
        D2(first:last) = best;
        idx(first:last) = bestIdx;
        if doVerbose
            nextPct = maybePrintProgress(progressLabel, last, nQuery, ...
                nextPct, stageTimer, 10);
        end
    end
    D = sqrt(D2);
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

function stats = summarizeVector(x)
    x = double(x(:));
    x = x(isfinite(x));
    stats = struct('n', numel(x), ...
        'min', NaN, 'p05', NaN, 'median', NaN, 'p95', NaN, ...
        'max', NaN, 'mean', NaN);
    if isempty(x)
        return;
    end
    stats.min = min(x);
    stats.p05 = percentileLocal(x, 5);
    stats.median = percentileLocal(x, 50);
    stats.p95 = percentileLocal(x, 95);
    stats.max = max(x);
    stats.mean = mean(x);
end

function diagnostics = makeAlignmentDiagnostics(labels, surfaces)
    diagnostics = struct();
    diagnostics.referenceFrame = 't1Voxel1';
    diagnostics.roastSkinLabel = maskVoxelSummary(labels == 5);
    diagnostics.surfaces = struct([]);
    for i = 1:numel(surfaces)
        d = struct();
        d.name = surfaces(i).name;
        d.role = surfaces(i).role;
        d.label = surfaces(i).label;
        d.summary = surfaces(i).summary;
        d.deltaCentroidFromRoastSkinVoxel = ...
            surfaces(i).summary.centroid - diagnostics.roastSkinLabel.centroid;
        d.deltaBoundsMinFromRoastSkinVoxel = ...
            surfaces(i).summary.bounds(1, :) - diagnostics.roastSkinLabel.bounds(1, :);
        d.deltaBoundsMaxFromRoastSkinVoxel = ...
            surfaces(i).summary.bounds(2, :) - diagnostics.roastSkinLabel.bounds(2, :);
        diagnostics.surfaces = appendDiagnostic(diagnostics.surfaces, d);
    end
end

function diagnostics = appendDiagnostic(diagnostics, item)
    if isempty(diagnostics)
        diagnostics = item;
    else
        diagnostics(end + 1, 1) = item;
    end
end

function summary = maskVoxelSummary(mask)
    dims = size(mask);
    rows = find(mask);
    if isempty(rows)
        summary = struct('nVoxels', 0, ...
            'bounds', nan(2, 3), ...
            'centroid', [nan nan nan], ...
            'span', [nan nan nan]);
        return;
    end
    [i, j, k] = ind2sub(dims, rows);
    P = double([i(:) j(:) k(:)]);
    summary = struct();
    summary.nVoxels = size(P, 1);
    summary.bounds = [min(P, [], 1); max(P, [], 1)];
    summary.centroid = mean(P, 1);
    summary.span = diff(summary.bounds, 1, 1);
end

function summary = meshSummary(TR)
    if isempty(TR)
        summary = struct('nVertices', 0, 'nFaces', 0, ...
            'bounds', zeros(0, 3), 'centroid', [nan nan nan], ...
            'span', [nan nan nan]);
        return;
    end
    V = double(TR.Points);
    summary = struct();
    summary.nVertices = size(V, 1);
    summary.nFaces = size(TR.ConnectivityList, 1);
    summary.bounds = [min(V, [], 1); max(V, [], 1)];
    summary.centroid = mean(V, 1);
    summary.span = diff(summary.bounds, 1, 1);
end

function report = stripForJson(value)
    report = value;
    if isfield(report, 'surfaces')
        report = rmfield(report, 'surfaces');
    end
    if isfield(report, 'options')
        report.options = rmLargeOptionFields(report.options);
    end
end

function opts = rmLargeOptionFields(opts)
    if ~isstruct(opts)
        return;
    end
end

function printSummary(out)
    fprintf('\nROAST mesh-native surface bundle\n');
    fprintf('  output: %s\n', out.outputFile);
    fprintf('  frame: %s\n', out.coordinateFrame);
    fprintf('  mask: %s\n', out.maskFile);
    if ~isempty(out.t1File)
        fprintf('  T1: %s\n', out.t1File);
    end
    for i = 1:numel(out.surfaceSummary)
        s = out.surfaceSummary(i);
        fprintf('  surface %-18s label %d: %d vertices, %d faces\n', ...
            s.name, s.label, s.nVertices, s.nFaces);
    end
    if isfield(out, 'scalp') && isstruct(out.scalp) && ...
            isfield(out.scalp, 'cacheFile') && ~isempty(out.scalp.cacheFile)
        fprintf('  scalp source: %s (%s -> %s)\n', ...
            out.scalp.cacheFile, out.scalp.sourceFrame, out.scalp.targetFrame);
    end
    if isfield(out, 'referenceScalp') && isstruct(out.referenceScalp) && ...
            isfield(out.referenceScalp, 'cacheFile') && ...
            ~isempty(out.referenceScalp.cacheFile)
        fprintf('  reference scalp: %s (%s -> %s)\n', ...
            out.referenceScalp.cacheFile, ...
            out.referenceScalp.sourceFrame, ...
            out.referenceScalp.targetFrame);
    end
    if isfield(out, 'headpost') && isstruct(out.headpost) && ...
            isfield(out.headpost, 'placementFile') && ...
            ~isempty(out.headpost.placementFile)
        fprintf('  titanium headpost: %s (%s -> %s)\n', ...
            out.headpost.placementFile, ...
            out.headpost.sourceFrame, out.headpost.targetFrame);
    end
    if isfield(out, 'skinShell') && isstruct(out.skinShell)
        printSkinShellDiagnostics(out.skinShell);
    end
    if isfield(out, 'implantDiagnostics') && ...
            isstruct(out.implantDiagnostics)
        printImplantDiagnostics(out.implantDiagnostics);
    end
    if isfield(out, 'alignmentDiagnostics') && ...
            isstruct(out.alignmentDiagnostics)
        printAlignmentDiagnostics(out.alignmentDiagnostics);
    end
    if ~isempty(out.qcFigure)
        fprintf('  QC figure: %s\n', out.qcFigure);
    end
end

function printSkinShellDiagnostics(shell)
    fprintf(['  skin shell surfaces: original outer=%d, original inner=%d, ', ...
        'replacement outer=%d, morphed whole shell=%d\n'], ...
        shell.hasOriginalOuter, shell.hasOriginalInner, ...
        shell.hasReplacementOuter, shell.hasWarpedShell);
    if isfield(shell, 'warpedShellInfo') && ...
            isfield(shell.warpedShellInfo, 'appliedDisplacementVoxel') && ...
            isstruct(shell.warpedShellInfo.appliedDisplacementVoxel)
        d = shell.warpedShellInfo.appliedDisplacementVoxel;
        fprintf('  morphed skin shell displacement: median %.2f vox, p95 %.2f vox, max %.2f vox\n', ...
            d.median, d.p95, d.max);
    end
    if isfield(shell, 'warpedShellInfo') && ...
            isfield(shell.warpedShellInfo, 'shell') && ...
            isstruct(shell.warpedShellInfo.shell) && ...
            isfield(shell.warpedShellInfo.shell, 'maskBoundaryWinding') && ...
            isstruct(shell.warpedShellInfo.shell.maskBoundaryWinding)
        w = shell.warpedShellInfo.shell.maskBoundaryWinding;
        if isfield(w, 'enabled') && w.enabled
            fprintf(['  morphed skin shell winding repair: flipped %d/%d faces ', ...
                '(outward votes %d, inward votes %d, ambiguous %d)\n'], ...
                w.flippedFaceCount, w.faceCount, w.outwardVoteCount, ...
                w.inwardVoteCount, w.ambiguousFaceCount);
        end
    end
    if isfield(shell, 'replacementToOriginalOuterDistanceVoxel') && ...
            isstruct(shell.replacementToOriginalOuterDistanceVoxel) && ...
            isfield(shell.replacementToOriginalOuterDistanceVoxel, 'median') && ...
            isfinite(shell.replacementToOriginalOuterDistanceVoxel.median)
        d = shell.replacementToOriginalOuterDistanceVoxel;
        fprintf('  replacement outer -> original outer distance: median %.2f vox, p95 %.2f vox\n', ...
            d.median, d.p95);
    end
    if isfield(shell, 'originalInnerToReplacementOuterDistanceVoxel') && ...
            isstruct(shell.originalInnerToReplacementOuterDistanceVoxel) && ...
            isfield(shell.originalInnerToReplacementOuterDistanceVoxel, 'median') && ...
            isfinite(shell.originalInnerToReplacementOuterDistanceVoxel.median)
        d = shell.originalInnerToReplacementOuterDistanceVoxel;
        fprintf('  original inner -> replacement outer clearance: median %.2f vox, p05 %.2f vox\n', ...
            d.median, d.p05);
    end
end

function printImplantDiagnostics(diagnostics)
    if ~isfield(diagnostics, 'hasTitanium') || ~diagnostics.hasTitanium
        return;
    end
    fprintf('  implant policy: titanium is solid; trim/make conformal other tissues if intersecting\n');
    if ~isfield(diagnostics, 'surfacePairs') || isempty(diagnostics.surfacePairs)
        return;
    end
    nFlagged = 0;
    for i = 1:numel(diagnostics.surfacePairs)
        pair = diagnostics.surfacePairs(i);
        if ~pair.possibleContactOrIntersection
            continue;
        end
        nFlagged = nFlagged + 1;
        d = pair.distanceVoxel;
        fprintf('    possible titanium contact/intersection with %-22s label %d: min %.2f vox, p05 %.2f vox\n', ...
            pair.otherSurface, pair.otherLabel, d.min, d.p05);
    end
    if nFlagged == 0
        fprintf('    no sampled titanium contacts below %.2f vox tolerance\n', ...
            diagnostics.contactToleranceVoxel);
    end
end

function printAlignmentDiagnostics(diagnostics)
    if ~isfield(diagnostics, 'surfaces') || isempty(diagnostics.surfaces)
        return;
    end
    fprintf('  alignment deltas from ROAST skin-label centroid (voxels):\n');
    for i = 1:numel(diagnostics.surfaces)
        role = diagnostics.surfaces(i).role;
        if ~(strcmpi(role, 'capMakerScalpOuter') || ...
                strcmpi(role, 'capMakerScalpReference'))
            continue;
        end
        d = diagnostics.surfaces(i).deltaCentroidFromRoastSkinVoxel;
        b0 = diagnostics.surfaces(i).deltaBoundsMinFromRoastSkinVoxel;
        b1 = diagnostics.surfaces(i).deltaBoundsMaxFromRoastSkinVoxel;
        fprintf('    %-24s centroid [%+.2f %+.2f %+.2f], bounds min [%+.2f %+.2f %+.2f], max [%+.2f %+.2f %+.2f]\n', ...
            diagnostics.surfaces(i).name, d(1), d(2), d(3), ...
            b0(1), b0(2), b0(3), b1(1), b1(2), b1(3));
    end
end

function saveQcFigure(fig, fileName)
    try
        exportgraphics(fig, fileName, 'Resolution', 220);
    catch
        saveas(fig, fileName);
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

function S = firstStruct(raw)
    names = fieldnames(raw);
    for i = 1:numel(names)
        if isstruct(raw.(names{i}))
            S = raw.(names{i});
            return;
        end
    end
    error('acsBuildRoastSurfaceBundle:NoStructInFile', ...
        'MAT file does not contain a struct.');
end

function requireFile(fileName, description)
    if isempty(fileName) || exist(fileName, 'file') ~= 2
        error('acsBuildRoastSurfaceBundle:MissingFile', ...
            'Could not find %s: %s', description, fileName);
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

function name = safeName(name)
    name = regexprep(char(name), '[^a-zA-Z0-9_]+', '_');
    name = regexprep(name, '_+', '_');
    name = regexprep(name, '^_|_$', '');
    if isempty(name)
        name = 'surfaceBundle';
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
