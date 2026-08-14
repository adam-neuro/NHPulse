function out = acsPlanChamberPlacement(sourceIn, varargin)
% ACSPLANCHAMBERPLACEMENT Plan a cylindrical recording chamber from MRI anatomy.
%
% out = acsPlanChamberPlacement(segOut) uses a ROAST/ACS segmentation output
% with roastReady.t1File and roastReady.maskFile. If targetVoxel is empty,
% the user picks the brain target in the orthogonal slice viewer. The utility
% extracts the skull/bone surface, finds an initial chamber placement whose
% local skull normal passes near the target, and optionally opens a simple
% refinement GUI.
%
% The default chamber is a cylindrical CILUX-style chamber:
%   outside diameter 25 mm, inside diameter 19 mm, height 19 mm.
%
% Name-value options:
%   t1File              : explicit T1/MPRAGE NIfTI ['']
%   maskFile            : explicit ROAST hard-label mask ['']
%   targetVoxel         : target in one-based T1 voxel coordinates [[]]
%   targetWorldMm       : target in T1/SPM world mm [[]]
%   targetVoxelFile     : MAT file to reuse/save picked target voxel ['']
%   forceTargetPick     : ignore targetVoxelFile and pick again [false]
%   skinCacheFile       : capMaker skin cache for print-frame exclusion ['']
%   contextExclusionFile: print-frame exclusion file(s) to show/warn ['']
%   chamberOuterDiameterMm : outside chamber diameter [25]
%   chamberInnerDiameterMm : inside chamber diameter [19]
%   chamberHeightMm     : chamber height [19]
%   exclusionMarginMm   : margin outside chamber perimeter [5]
%   skullLabel          : ROAST hard-label value for bone [4]
%   skullSurfaceMaxFaces: decimate skull surface for search/QC [60000]
%   displaySkullSurfaceMaxFaces: decimate skull surface for GUI display [15000]
%   outerSkullOnly      : restrict chamber contact search to outer skull [true]
%   outerSurfaceNeighborhoodVox: voxel neighborhood for outer-skull labels [2]
%   checkChamberSkullIntersection: reject candidate chambers crossing skull [true]
%   collisionCheckTopCandidates: scored candidates to collision-check [2000]
%   collisionSampleStepMm: spacing along chamber wall for collision check [2]
%   collisionClearanceMm: first sampled height above chamber base [1]
%   localPlaneRadiusMm  : local skull contact patch radius [8]
%   depthWeight         : shortest-distance weight in candidate score [0.12]
%   interactive         : open placement refinement GUI [true]
%   reviewExisting      : reopen saved placement for review/refinement [false]
%   readOnlyReview      : review saved placement without saving changes [false]
%   qcCameraMode        : QC camera, 'default' or 'chamberBore' ['default']
%   qcBoreCameraViewAngle: chamberBore zoom/camera view angle in degrees [26]
%   targetSliceMode     : add target-centered MRI slices, 'none'/'orthogonal' ['none']
%   targetSlicePlanes   : slice panels for targetSliceMode, e.g. {'sagittal','coronal'}
%   nudgeMm             : GUI nudge step in world mm [1]
%   stereotaxicLandmarks: acsSelectStereotaxicLandmarks output or file [[]]
%   outputFile          : optional MAT output ['']
%   force               : overwrite output [false]
%   showFigures         : show QC/refinement figure [true]
%   saveFigures         : save QC figure [false]
%   verbose             : print summary [true]

    if nargin < 1 || isempty(sourceIn)
        error('acsPlanChamberPlacement:MissingInput', ...
            'Provide a segmentation output, T1 filename, or source struct.');
    end

    opts = parseInputs(varargin{:});
    addLocalDependencies();
    [t1File, maskFile, source] = resolveSource(sourceIn, opts);

    if ~isempty(opts.outputFile) && exist(opts.outputFile, 'file') == 2 && ~opts.force
        out = loadSavedOutput(opts.outputFile);
        if needsPrintFrameExclusionRefresh(out, opts)
            Vt1Refresh = spm_vol(t1File);
            Vt1Refresh = Vt1Refresh(1);
            contextExclusions = resolveContextExclusions( ...
                opts.contextExclusionFile, opts.skinCacheFile, Vt1Refresh, opts);
            out.exclusion = addPrintFrameExclusion(out.exclusion, ...
                opts.skinCacheFile, Vt1Refresh, opts);
            out.exclusion.contextCollision = summarizeContextCollision( ...
                out.exclusion, contextExclusions, opts);
            out.contextExclusions = contextExclusions;
            out.options = opts;
            if ~opts.readOnlyReview
                outForSave = stripFigure(out);
                outReturn = out;
                out = outForSave; %#ok<NASGU>
                save(opts.outputFile, 'out', 'outForSave', '-v7.3');
                out = outReturn;
            end
            if opts.verbose
                if opts.readOnlyReview
                    fprintf(['Computed chamber print-frame exclusion for current ', ...
                        'skin cache without saving: %s\n'], opts.skinCacheFile);
                else
                    fprintf('Updated chamber print-frame exclusion for current skin cache: %s\n', ...
                        opts.skinCacheFile);
                end
            end
        end
        if opts.verbose
            fprintf('Chamber placement already exists; reusing %s\n', opts.outputFile);
        end
        if opts.reviewExisting && opts.showFigures
            out = reviewExistingChamberPlacement(out, t1File, maskFile, source, opts);
        end
        return;
    end

    Vt1 = spm_vol(t1File);
    Vt1 = Vt1(1);
    [targetVoxel, targetWorldMm, targetInfo] = resolveTarget(t1File, Vt1, opts);
    opts = addQcAnatomyInfo(opts, t1File, targetVoxel);
    contextExclusions = resolveContextExclusions( ...
        opts.contextExclusionFile, opts.skinCacheFile, Vt1, opts);

    if opts.verbose
        fprintf('Extracting and classifying skull surface for chamber planning...\n');
        tSkull = tic;
    end
    [TRskull, skullInfo] = skullSurfaceFromMask(maskFile, opts);
    if opts.verbose
        fprintf('  skull surface: %d vertices, %d faces, %d outer-skull vertices (%.1f s)\n', ...
            skullInfo.nVertices, skullInfo.nFaces, skullInfo.nOuterVertices, toc(tSkull));
        fprintf('Searching for an outer-skull chamber contact candidate...\n');
        tPlacement = tic;
    end
    candidate = initialPlacement(TRskull, targetWorldMm, opts, skullInfo);
    if opts.verbose
        fprintf('  initial candidate: miss %.2f mm, depth %.1f mm', ...
            candidate.targetLineMissMm, candidate.depthToTargetMm);
        if isfield(candidate, 'skullIntersection')
            fprintf(', skull-intersection samples %d/%d', ...
                candidate.skullIntersection.nInside, ...
                candidate.skullIntersection.nSamples);
        end
        fprintf(' (%.1f s)\n', toc(tPlacement));
    end

    accepted = true;
    fig = [];
    if opts.interactive && opts.showFigures
        [candidate, accepted, fig] = refinePlacementGui( ...
            TRskull, targetWorldMm, candidate, opts, skullInfo, ...
            contextExclusions);
        if ~accepted
            error('acsPlanChamberPlacement:Canceled', ...
                'Chamber placement was canceled.');
        end
    elseif opts.showFigures || opts.saveFigures
        fig = makeQcFigure(TRskull, targetWorldMm, candidate, opts, ...
            contextExclusions, 'on');
    end

    chamberMesh = makeChamberMesh(candidate.contactWorldMm, ...
        candidate.axisOutWorld, opts);
    exclusion = makeExclusionProduct(candidate, opts);
    if ~isempty(opts.skinCacheFile)
        exclusion = addPrintFrameExclusion(exclusion, opts.skinCacheFile, Vt1, opts);
    end
    exclusion.contextCollision = summarizeContextCollision( ...
        exclusion, contextExclusions, opts);

    stereo = struct();
    if ~isempty(opts.stereotaxicLandmarks)
        landmarks = readLandmarks(opts.stereotaxicLandmarks);
        stereo = chamberStereotaxicSummary(candidate, targetWorldMm, landmarks);
    end

    qcFile = '';
    if opts.saveFigures
        if isempty(fig) || ~isgraphics(fig)
            fig = makeQcFigure(TRskull, targetWorldMm, candidate, opts, ...
                contextExclusions, 'off');
        end
        qcFile = defaultQcFile(opts.outputFile, t1File);
        ensureDir(fileparts(qcFile));
        saveQcFigure(fig, qcFile);
    end

    out = struct();
    out.createdOn = char(datetime('now'));
    out.source = source;
    out.t1File = t1File;
    out.maskFile = maskFile;
    out.targetVoxel = targetVoxel;
    out.targetWorldMm = targetWorldMm;
    out.targetInfo = targetInfo;
    out.placement = candidate;
    out.chamber = struct( ...
        'outerDiameterMm', opts.chamberOuterDiameterMm, ...
        'innerDiameterMm', opts.chamberInnerDiameterMm, ...
        'heightMm', opts.chamberHeightMm, ...
        'mesh', chamberMesh);
    out.exclusion = exclusion;
    out.contextExclusions = contextExclusions;
    out.stereotaxic = stereo;
    out.skullSurfaceInfo = publicSkullInfo(skullInfo);
    out.outputFile = opts.outputFile;
    out.qcFigure = qcFile;
    out.options = opts;
    out.figure = fig;

    if ~isempty(opts.outputFile)
        outForSave = stripFigure(out);
        ensureDir(fileparts(opts.outputFile));
        outReturn = out;
        out = outForSave; %#ok<NASGU>
        save(opts.outputFile, 'out', 'outForSave', '-v7.3');
        out = outReturn;
    end
    if opts.verbose
        printSummary(out);
    end
end

function out = loadSavedOutput(fileName)
    info = whos('-file', fileName);
    names = {info.name};
    preferred = {'outForSave', 'outSaved', 'out'};
    for i = 1:numel(preferred)
        hit = find(strcmp(names, preferred{i}), 1);
        if isempty(hit) || ~strcmp(info(hit).class, 'struct')
            continue;
        end
        S = load(fileName, preferred{i});
        out = S.(preferred{i});
        return;
    end
    S = load(fileName);
    out = firstStruct(S);
end

function out = reviewExistingChamberPlacement(out, t1File, maskFile, source, opts)
    if ~isfield(out, 'placement') || ~isstruct(out.placement)
        warning('acsPlanChamberPlacement:CannotReviewExisting', ...
            'Saved chamber output does not contain a placement struct.');
        return;
    end
    if ~isfield(out, 'targetWorldMm') || isempty(out.targetWorldMm)
        warning('acsPlanChamberPlacement:CannotReviewExisting', ...
            'Saved chamber output does not contain targetWorldMm.');
        return;
    end

    Vt1 = spm_vol(t1File);
    Vt1 = Vt1(1);
    targetWorldMm = double(out.targetWorldMm(:)');
    if isfield(out, 'targetVoxel') && ~isempty(out.targetVoxel)
        targetVoxel = double(out.targetVoxel(:)');
    else
        targetVoxel = worldMmToVoxel1(targetWorldMm, Vt1.mat);
    end
    opts = addQcAnatomyInfo(opts, t1File, targetVoxel);
    contextExclusions = resolveContextExclusions( ...
        opts.contextExclusionFile, opts.skinCacheFile, Vt1, opts);

    if opts.verbose
        fprintf('Opening saved chamber placement for review: %s\n', opts.outputFile);
        fprintf('Extracting skull surface for chamber review...\n');
    end
    [TRskull, skullInfo] = skullSurfaceFromMask(maskFile, opts);
    plan = out.placement;
    plan = addPlanCollisionInfo(plan, opts, skullInfo);

    accepted = true;
    fig = [];
    if opts.interactive
        [plan, accepted, fig] = refinePlacementGui( ...
            TRskull, targetWorldMm, plan, opts, skullInfo, contextExclusions);
        if ~accepted
            error('acsPlanChamberPlacement:Canceled', ...
                'Chamber placement review was canceled.');
        end
    else
        fig = makeQcFigure(TRskull, targetWorldMm, plan, opts, ...
            contextExclusions, 'on');
    end

    chamberMesh = makeChamberMesh(plan.contactWorldMm, ...
        plan.axisOutWorld, opts);
    exclusion = makeExclusionProduct(plan, opts);
    if ~isempty(opts.skinCacheFile)
        exclusion = addPrintFrameExclusion(exclusion, opts.skinCacheFile, Vt1, opts);
    end
    exclusion.contextCollision = summarizeContextCollision( ...
        exclusion, contextExclusions, opts);

    stereo = struct();
    if ~isempty(opts.stereotaxicLandmarks)
        landmarks = readLandmarks(opts.stereotaxicLandmarks);
        stereo = chamberStereotaxicSummary(plan, targetWorldMm, landmarks);
    elseif isfield(out, 'stereotaxic')
        stereo = out.stereotaxic;
    end

    qcFile = '';
    if opts.saveFigures
        qcFile = defaultQcFile(opts.outputFile, t1File);
        ensureDir(fileparts(qcFile));
        saveQcFigure(fig, qcFile);
    elseif isfield(out, 'qcFigure')
        qcFile = out.qcFigure;
    end

    out.reviewedOn = char(datetime('now'));
    out.source = source;
    out.t1File = t1File;
    out.maskFile = maskFile;
    out.targetWorldMm = targetWorldMm;
    out.placement = plan;
    out.chamber = struct( ...
        'outerDiameterMm', opts.chamberOuterDiameterMm, ...
        'innerDiameterMm', opts.chamberInnerDiameterMm, ...
        'heightMm', opts.chamberHeightMm, ...
        'mesh', chamberMesh);
    out.exclusion = exclusion;
    out.contextExclusions = contextExclusions;
    out.stereotaxic = stereo;
    out.skullSurfaceInfo = publicSkullInfo(skullInfo);
    out.outputFile = opts.outputFile;
    out.qcFigure = qcFile;
    out.options = opts;
    out.figure = fig;

    if ~opts.readOnlyReview
        outForSave = stripFigure(out);
        outReturn = out;
        out = outForSave; %#ok<NASGU>
        save(opts.outputFile, 'out', 'outForSave', '-v7.3');
        out = outReturn;
    end
    if opts.verbose
        printSummary(out);
    end
end

function value = stripFigure(value)
    if isfield(value, 'figure')
        value = rmfield(value, 'figure');
    end
end

function opts = parseInputs(varargin)
    p = inputParser;
    p.FunctionName = 'acsPlanChamberPlacement';
    addParameter(p, 't1File', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'maskFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'targetVoxel', [], ...
        @(x) isempty(x) || (isnumeric(x) && numel(x) == 3));
    addParameter(p, 'targetWorldMm', [], ...
        @(x) isempty(x) || (isnumeric(x) && numel(x) == 3));
    addParameter(p, 'targetVoxelFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'forceTargetPick', false, @isBoolLike);
    addParameter(p, 'skinCacheFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'contextExclusionFile', {}, @isFileListLike);
    addParameter(p, 'chamberOuterDiameterMm', 25, @isPositiveScalar);
    addParameter(p, 'chamberInnerDiameterMm', 19, @isPositiveScalar);
    addParameter(p, 'chamberHeightMm', 19, @isPositiveScalar);
    addParameter(p, 'exclusionMarginMm', 5, @isNonnegativeScalar);
    addParameter(p, 'skullLabel', 4, @(x) isnumeric(x) && isscalar(x));
    addParameter(p, 'skullSurfaceMaxFaces', 60000, ...
        @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x > 0));
    addParameter(p, 'displaySkullSurfaceMaxFaces', 15000, ...
        @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x > 0));
    addParameter(p, 'outerSkullOnly', true, @isBoolLike);
    addParameter(p, 'outerSurfaceNeighborhoodVox', 2, ...
        @(x) isnumeric(x) && isscalar(x) && x >= 0);
    addParameter(p, 'checkChamberSkullIntersection', true, @isBoolLike);
    addParameter(p, 'collisionCheckTopCandidates', 2000, ...
        @(x) isnumeric(x) && isscalar(x) && x >= 1);
    addParameter(p, 'collisionSampleStepMm', 2, @isPositiveScalar);
    addParameter(p, 'collisionClearanceMm', 1, @isNonnegativeScalar);
    addParameter(p, 'localPlaneRadiusMm', 8, @isPositiveScalar);
    addParameter(p, 'depthWeight', 0.12, @isNonnegativeScalar);
    addParameter(p, 'interactive', true, @isBoolLike);
    addParameter(p, 'reviewExisting', false, @isBoolLike);
    addParameter(p, 'readOnlyReview', false, @isBoolLike);
    addParameter(p, 'qcCameraMode', 'default', @isTextScalar);
    addParameter(p, 'qcBoreCameraViewAngle', 26, @isPositiveScalar);
    addParameter(p, 'targetSliceMode', 'none', @isTextScalar);
    addParameter(p, 'targetSlicePlanes', {'sagittal', 'coronal'}, ...
        @isSlicePlaneListLike);
    addParameter(p, 'nudgeMm', 1, @isPositiveScalar);
    addParameter(p, 'stereotaxicLandmarks', [], ...
        @(x) isempty(x) || isstruct(x) || ischar(x) || isstring(x));
    addParameter(p, 'outputFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'force', false, @isBoolLike);
    addParameter(p, 'showFigures', true, @isBoolLike);
    addParameter(p, 'saveFigures', false, @isBoolLike);
    addParameter(p, 'verbose', true, @isBoolLike);
    parse(p, varargin{:});

    opts = p.Results;
    opts.t1File = expandUserPath(char(opts.t1File));
    opts.maskFile = expandUserPath(char(opts.maskFile));
    opts.targetVoxel = double(opts.targetVoxel(:)');
    opts.targetWorldMm = double(opts.targetWorldMm(:)');
    opts.targetVoxelFile = expandUserPath(char(opts.targetVoxelFile));
    opts.forceTargetPick = logical(opts.forceTargetPick);
    opts.skinCacheFile = expandUserPath(char(opts.skinCacheFile));
    opts.contextExclusionFile = normalizeFileList(opts.contextExclusionFile);
    opts.chamberOuterDiameterMm = double(opts.chamberOuterDiameterMm);
    opts.chamberInnerDiameterMm = double(opts.chamberInnerDiameterMm);
    opts.chamberHeightMm = double(opts.chamberHeightMm);
    opts.exclusionMarginMm = double(opts.exclusionMarginMm);
    opts.skullLabel = round(double(opts.skullLabel));
    if isempty(opts.skullSurfaceMaxFaces)
        opts.skullSurfaceMaxFaces = [];
    else
        opts.skullSurfaceMaxFaces = round(double(opts.skullSurfaceMaxFaces));
    end
    if isempty(opts.displaySkullSurfaceMaxFaces)
        opts.displaySkullSurfaceMaxFaces = [];
    else
        opts.displaySkullSurfaceMaxFaces = round(double(opts.displaySkullSurfaceMaxFaces));
    end
    opts.outerSkullOnly = logical(opts.outerSkullOnly);
    opts.outerSurfaceNeighborhoodVox = round(double(opts.outerSurfaceNeighborhoodVox));
    opts.checkChamberSkullIntersection = logical(opts.checkChamberSkullIntersection);
    opts.collisionCheckTopCandidates = round(double(opts.collisionCheckTopCandidates));
    opts.collisionSampleStepMm = double(opts.collisionSampleStepMm);
    opts.collisionClearanceMm = double(opts.collisionClearanceMm);
    opts.localPlaneRadiusMm = double(opts.localPlaneRadiusMm);
    opts.depthWeight = double(opts.depthWeight);
    opts.interactive = logical(opts.interactive);
    opts.reviewExisting = logical(opts.reviewExisting);
    opts.readOnlyReview = logical(opts.readOnlyReview);
    if opts.readOnlyReview
        opts.interactive = false;
    end
    opts.qcCameraMode = validatestring(lower(char(opts.qcCameraMode)), ...
        {'default', 'chamberbore'}, p.FunctionName, 'qcCameraMode');
    opts.qcBoreCameraViewAngle = double(opts.qcBoreCameraViewAngle);
    opts.targetSliceMode = validatestring(lower(char(opts.targetSliceMode)), ...
        {'none', 'orthogonal'}, p.FunctionName, 'targetSliceMode');
    opts.targetSlicePlanes = normalizeSlicePlanes(opts.targetSlicePlanes);
    opts.nudgeMm = double(opts.nudgeMm);
    if ischar(opts.stereotaxicLandmarks) || isstring(opts.stereotaxicLandmarks)
        opts.stereotaxicLandmarks = expandUserPath(char(opts.stereotaxicLandmarks));
    end
    opts.outputFile = expandUserPath(char(opts.outputFile));
    opts.force = logical(opts.force);
    opts.showFigures = logical(opts.showFigures);
    opts.saveFigures = logical(opts.saveFigures);
    opts.verbose = logical(opts.verbose);

    if opts.chamberInnerDiameterMm >= opts.chamberOuterDiameterMm
        error('acsPlanChamberPlacement:BadChamberGeometry', ...
            'chamberInnerDiameterMm must be smaller than chamberOuterDiameterMm.');
    end
end

function tf = isBoolLike(x)
    tf = (islogical(x) || isnumeric(x)) && isscalar(x);
end

function tf = isTextScalar(x)
    tf = ischar(x) || (isstring(x) && isscalar(x));
end

function tf = isFileListLike(x)
    tf = isempty(x) || ischar(x) || isstring(x) || iscell(x);
end

function tf = isSlicePlaneListLike(x)
    tf = ischar(x) || isstring(x) || iscell(x);
end

function files = normalizeFileList(value)
    files = {};
    if isempty(value)
        return;
    end
    if ischar(value) || (isstring(value) && isscalar(value))
        fileName = expandUserPath(char(value));
        if ~isempty(fileName)
            files = {fileName};
        end
        return;
    end
    if isstring(value)
        value = cellstr(value(:));
    end
    if ~iscell(value)
        error('acsPlanChamberPlacement:BadFileList', ...
            'File list options must be a filename, string array, or cell array.');
    end
    for i = 1:numel(value)
        if isempty(value{i})
            continue;
        end
        fileName = expandUserPath(char(value{i}));
        if ~isempty(fileName)
            files{end + 1, 1} = fileName; %#ok<AGROW>
        end
    end
end

function planes = normalizeSlicePlanes(value)
    if ischar(value)
        planes = {char(value)};
    elseif isstring(value)
        planes = cellstr(value(:));
    elseif iscell(value)
        planes = value(:);
    else
        planes = {'sagittal'; 'coronal'};
    end
    if isempty(planes)
        planes = {'sagittal'; 'coronal'};
    end
    planes = planes(:);
    for i = 1:numel(planes)
        planes{i} = validatestring(lower(strtrim(char(planes{i}))), ...
            {'sagittal', 'coronal', 'axial'}, ...
            'acsPlanChamberPlacement', 'targetSlicePlanes');
    end
    [~, ia] = unique(planes, 'stable');
    planes = planes(sort(ia));
    if numel(planes) > 2
        planes = planes(1:2);
    end
end

function opts = addQcAnatomyInfo(opts, t1File, targetVoxel)
    opts.qcT1File = expandUserPath(char(t1File));
    opts.qcTargetVoxel = double(targetVoxel(:)');
end

function tf = isPositiveScalar(x)
    tf = isnumeric(x) && isscalar(x) && isfinite(x) && x > 0;
end

function tf = isNonnegativeScalar(x)
    tf = isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0;
end

function addLocalDependencies()
    repoRoot = fileparts(fileparts(mfilename('fullpath')));
    addpath(fullfile(repoRoot, 'acsUtilities'));
    addpath(fullfile(repoRoot, 'capMaker', 'core'));
    spmDir = fullfile(repoRoot, 'lib', 'spm12');
    if exist(spmDir, 'dir') == 7
        addpath(spmDir);
    end
end

function [t1File, maskFile, source] = resolveSource(sourceIn, opts)
    source = struct('type', class(sourceIn), 'label', '', 'file', '');
    t1File = opts.t1File;
    maskFile = opts.maskFile;
    if isstruct(sourceIn)
        if isempty(t1File) && isfield(sourceIn, 'roastReady') && ...
                isfield(sourceIn.roastReady, 't1File')
            t1File = char(sourceIn.roastReady.t1File);
        end
        if isempty(maskFile) && isfield(sourceIn, 'roastReady') && ...
                isfield(sourceIn.roastReady, 'maskFile')
            maskFile = char(sourceIn.roastReady.maskFile);
        end
        if isempty(t1File) && isfield(sourceIn, 't1File')
            t1File = char(sourceIn.t1File);
        end
        if isempty(maskFile) && isfield(sourceIn, 'maskFile')
            maskFile = char(sourceIn.maskFile);
        end
        source.label = 'source struct';
    elseif ischar(sourceIn) || isstring(sourceIn)
        if isempty(t1File)
            t1File = expandUserPath(char(sourceIn));
        end
        source.file = t1File;
        source.label = getFileName(t1File);
    end
    t1File = expandUserPath(t1File);
    maskFile = expandUserPath(maskFile);
    requireFile(t1File, 'T1 file');
    requireFile(maskFile, 'ROAST hard-label mask file');
    if isempty(source.label)
        source.label = getFileName(t1File);
    end
end

function [targetVoxel, targetWorldMm, info] = resolveTarget(t1File, Vt1, opts)
    info = struct('source', '', ...
        'targetVoxelFile', opts.targetVoxelFile, ...
        'savedTargetVoxelFile', '', ...
        'loadedTargetVoxelFile', '', ...
        't1File', t1File);
    if ~isempty(opts.targetWorldMm)
        targetWorldMm = opts.targetWorldMm;
        targetVoxel = worldMmToVoxel1(targetWorldMm, Vt1.mat);
        info.source = 'targetWorldMm argument';
        info.savedTargetVoxelFile = maybeSaveTargetVoxelFile( ...
            opts.targetVoxelFile, targetVoxel, ...
            targetWorldMm, t1File, info.source, opts);
        return;
    end
    if ~isempty(opts.targetVoxel)
        targetVoxel = opts.targetVoxel;
        targetWorldMm = voxel1ToWorldMm(targetVoxel, Vt1.mat);
        info.source = 'targetVoxel argument';
        info.savedTargetVoxelFile = maybeSaveTargetVoxelFile( ...
            opts.targetVoxelFile, targetVoxel, ...
            targetWorldMm, t1File, info.source, opts);
        return;
    end
    if ~isempty(opts.targetVoxelFile) && ...
            exist(opts.targetVoxelFile, 'file') == 2 && ~opts.forceTargetPick
        [targetVoxel, targetWorldMm, loaded] = loadTargetVoxelFile( ...
            opts.targetVoxelFile, Vt1);
        info.source = 'targetVoxelFile';
        info.loadedTargetVoxelFile = opts.targetVoxelFile;
        info.loadedTarget = loaded;
        if opts.verbose
            fprintf('Reusing saved chamber target voxel: %s\n', ...
                opts.targetVoxelFile);
            fprintf('  target voxel: [%.1f %.1f %.1f]\n', ...
                targetVoxel(1), targetVoxel(2), targetVoxel(3));
        end
        return;
    end
    pick = acsLabelVolumeOrientation(t1File, ...
        'orientationCode', 'skip', ...
        'allowSkip', true, ...
        'voxelSelectionMode', 'single', ...
        'volumeLabel', [getFileName(t1File) ' | chamber brain target'], ...
        'waitForDone', true, ...
        'doneButtonLabel', 'Accept target', ...
        'cancelButtonLabel', 'Cancel', ...
        'closeFigure', true, ...
        'showFigures', true, ...
        'saveFigures', false, ...
        'verbose', opts.verbose);
    targetVoxel = double(pick.selectedVoxels(1, :));
    targetWorldMm = voxel1ToWorldMm(targetVoxel, Vt1.mat);
    info.source = 'picked in volume viewer';
    savedFile = maybeSaveTargetVoxelFile(opts.targetVoxelFile, targetVoxel, ...
        targetWorldMm, t1File, info.source, opts);
    info.savedTargetVoxelFile = savedFile;
end

function savedFile = maybeSaveTargetVoxelFile(fileName, targetVoxel, ...
        targetWorldMm, t1File, sourceLabel, opts)
    savedFile = '';
    if isempty(fileName)
        return;
    end
    if exist(fileName, 'file') == 2 && ~opts.forceTargetPick
        return;
    end
    target = struct();
    target.createdOn = char(datetime('now'));
    target.source = sourceLabel;
    target.t1File = t1File;
    target.targetVoxel = double(targetVoxel(:)');
    target.targetWorldMm = double(targetWorldMm(:)');
    target.coordinateFrames = struct( ...
        'targetVoxel', 'oneBasedVoxel', ...
        'targetWorldMm', 'T1WorldMm');
    ensureDir(fileparts(fileName));
    save(fileName, 'target', '-v7.3');
    savedFile = fileName;
    if opts.verbose
        fprintf('Saved chamber target voxel: %s\n', fileName);
    end
end

function [targetVoxel, targetWorldMm, target] = loadTargetVoxelFile(fileName, Vt1)
    S = load(fileName);
    target = firstTargetStruct(S);
    if isfield(target, 'targetVoxel') && ~isempty(target.targetVoxel)
        targetVoxel = double(target.targetVoxel(:)');
        if numel(targetVoxel) ~= 3 || any(~isfinite(targetVoxel))
            error('acsPlanChamberPlacement:BadTargetVoxelFile', ...
                'targetVoxelFile has an invalid targetVoxel: %s', fileName);
        end
        targetWorldMm = voxel1ToWorldMm(targetVoxel, Vt1.mat);
        return;
    end
    if isfield(target, 'targetWorldMm') && ~isempty(target.targetWorldMm)
        targetWorldMm = double(target.targetWorldMm(:)');
        if numel(targetWorldMm) ~= 3 || any(~isfinite(targetWorldMm))
            error('acsPlanChamberPlacement:BadTargetVoxelFile', ...
                'targetVoxelFile has an invalid targetWorldMm: %s', fileName);
        end
        targetVoxel = worldMmToVoxel1(targetWorldMm, Vt1.mat);
        return;
    end
    error('acsPlanChamberPlacement:BadTargetVoxelFile', ...
        'targetVoxelFile must contain target.targetVoxel or target.targetWorldMm: %s', ...
        fileName);
end

function target = firstTargetStruct(raw)
    preferred = {'target', 'chamberTarget', 'out', 'outForSave'};
    for i = 1:numel(preferred)
        name = preferred{i};
        if isfield(raw, name) && isstruct(raw.(name))
            candidate = raw.(name);
            if isfield(candidate, 'targetVoxel') || isfield(candidate, 'targetWorldMm')
                target = candidate;
                return;
            end
        end
    end
    if isfield(raw, 'targetVoxel') || isfield(raw, 'targetWorldMm')
        target = raw;
        return;
    end
    names = fieldnames(raw);
    for i = 1:numel(names)
        candidate = raw.(names{i});
        if isstruct(candidate) && ...
                (isfield(candidate, 'targetVoxel') || isfield(candidate, 'targetWorldMm'))
            target = candidate;
            return;
        end
    end
    error('acsPlanChamberPlacement:BadTargetVoxelFile', ...
        'MAT file does not contain a readable chamber target struct.');
end

function [TRskull, info] = skullSurfaceFromMask(maskFile, opts)
    Vmask = spm_vol(maskFile);
    Vmask = Vmask(1);
    labels = round(spm_read_vols(Vmask));
    bone = labels == opts.skullLabel;
    if nnz(bone) < 10
        error('acsPlanChamberPlacement:NoSkullLabel', ...
            'Mask does not contain enough voxels with skullLabel=%d.', opts.skullLabel);
    end
    bone = smooth3(single(bone), 'box', 3) > 0.20;
    exteriorAir = exteriorConnectedMask(~bone);
    outerBone = bone & neighbor6Mask(exteriorAir);
    dims = size(bone);
    [x, y, z] = ndgrid(1:dims(1), 1:dims(2), 1:dims(3));
    fv = isosurface(x, y, z, bone, 0.5);
    if isempty(fv.vertices) || isempty(fv.faces)
        error('acsPlanChamberPlacement:NoSkullSurface', ...
            'Could not extract skull surface from %s.', maskFile);
    end
    verticesWorld = voxel1ToWorldMm(fv.vertices, Vmask.mat);
    TRskull = triangulation(double(fv.faces), verticesWorld);
    TRskull = decimateTri(TRskull, opts.skullSurfaceMaxFaces);
    try
        TRskull = unifyOutwardNormalsRobust(TRskull);
    catch
        % Non-closed skull shells are still useful for placement; normals
        % are reoriented relative to the target during candidate scoring.
    end
    outerVertexMask = classifyOuterSurfaceVertices(TRskull.Points, ...
        Vmask.mat, dims, outerBone, opts.outerSurfaceNeighborhoodVox);
    if nnz(outerVertexMask) < 10
        warning('acsPlanChamberPlacement:SparseOuterSkull', ...
            ['Only %d skull vertices were classified as outer skull. ' ...
            'Falling back to all skull vertices for chamber planning.'], ...
            nnz(outerVertexMask));
        outerVertexMask = true(size(TRskull.Points, 1), 1);
    end
    info = struct('maskFile', maskFile, ...
        'skullLabel', opts.skullLabel, ...
        'nBoneVoxels', nnz(bone), ...
        'nOuterBoneVoxels', nnz(outerBone), ...
        'nVertices', size(TRskull.Points, 1), ...
        'nFaces', size(TRskull.ConnectivityList, 1), ...
        'nOuterVertices', nnz(outerVertexMask), ...
        'outerVertexMask', outerVertexMask(:), ...
        'outerSurfaceDefinition', ...
        'bone adjacent to exterior 6-connected non-bone');
    info.runtime = struct('boneMask', bone, ...
        'maskMat', Vmask.mat, ...
        'maskDims', dims);
end

function TRout = decimateTri(TRin, maxFaces)
    TRout = TRin;
    if isempty(maxFaces) || size(TRin.ConnectivityList, 1) <= maxFaces
        return;
    end
    try
        [F2, V2] = reducepatch(TRin.ConnectivityList, TRin.Points, maxFaces);
        TRout = triangulation(F2, V2);
    catch
        TRout = TRin;
    end
end

function exterior = exteriorConnectedMask(nonBone)
    nonBone = logical(nonBone);
    dims = size(nonBone);
    boundary = false(dims);
    boundary(1, :, :) = true;
    boundary(end, :, :) = true;
    boundary(:, 1, :) = true;
    boundary(:, end, :) = true;
    boundary(:, :, 1) = true;
    boundary(:, :, end) = true;
    if exist('bwconncomp', 'file') == 2
        CC = bwconncomp(nonBone, 6);
        boundaryLinear = find(boundary);
        isBoundary = false(numel(nonBone), 1);
        isBoundary(boundaryLinear) = true;
        exterior = false(dims);
        for i = 1:CC.NumObjects
            pix = CC.PixelIdxList{i};
            if any(isBoundary(pix))
                exterior(pix) = true;
            end
        end
        return;
    end

    exterior = boundary & nonBone;
    frontier = exterior;
    while any(frontier(:))
        grown = neighbor6Mask(frontier) & nonBone & ~exterior;
        exterior = exterior | grown;
        frontier = grown;
    end
end

function B = neighbor6Mask(A)
    K = zeros(3, 3, 3);
    K(1, 2, 2) = 1;
    K(3, 2, 2) = 1;
    K(2, 1, 2) = 1;
    K(2, 3, 2) = 1;
    K(2, 2, 1) = 1;
    K(2, 2, 3) = 1;
    B = convn(double(A), K, 'same') > 0;
end

function outerMask = classifyOuterSurfaceVertices(pointsWorld, M, dims, outerBone, radiusVox)
    vox = round(worldMmToVoxel1(pointsWorld, M));
    n = size(vox, 1);
    outerMask = false(n, 1);
    radiusVox = max(0, round(radiusVox));
    [dx, dy, dz] = ndgrid(-radiusVox:radiusVox, ...
        -radiusVox:radiusVox, -radiusVox:radiusVox);
    offsets = [dx(:), dy(:), dz(:)];
    offsets = offsets(sum(abs(offsets), 2) <= max(1, radiusVox), :);
    if radiusVox == 0
        offsets = [0 0 0];
    end
    for k = 1:size(offsets, 1)
        vv = bsxfun(@plus, vox, offsets(k, :));
        inside = vv(:, 1) >= 1 & vv(:, 1) <= dims(1) & ...
            vv(:, 2) >= 1 & vv(:, 2) <= dims(2) & ...
            vv(:, 3) >= 1 & vv(:, 3) <= dims(3);
        if ~any(inside)
            continue;
        end
        idx = sub2ind(dims, vv(inside, 1), vv(inside, 2), vv(inside, 3));
        hit = false(n, 1);
        hit(inside) = outerBone(idx);
        outerMask = outerMask | hit;
    end
end

function eligible = eligibleSkullVertices(TRskull, skullInfo, opts)
    n = size(TRskull.Points, 1);
    eligible = true(n, 1);
    if opts.outerSkullOnly && isfield(skullInfo, 'outerVertexMask') && ...
            numel(skullInfo.outerVertexMask) == n
        eligible = logical(skullInfo.outerVertexMask(:));
    end
    if nnz(eligible) < 10
        warning('acsPlanChamberPlacement:TooFewEligibleVertices', ...
            'Only %d skull vertices are eligible. Falling back to all skull vertices.', ...
            nnz(eligible));
        eligible = true(n, 1);
    end
end

function plan = initialPlacement(TRskull, targetWorldMm, opts, skullInfo)
    V = double(TRskull.Points);
    N = vertexNormal(TRskull);
    N = normalizeRows(N);
    eligible = eligibleSkullVertices(TRskull, skullInfo, opts);
    outwardRef = bsxfun(@minus, V, targetWorldMm);
    flip = sum(N .* outwardRef, 2) < 0;
    N(flip, :) = -N(flip, :);

    depth = sum(outwardRef .* N, 2);
    closest = outwardRef - bsxfun(@times, depth, N);
    lineDistance = sqrt(sum(closest .^ 2, 2));
    valid = depth > 0 & all(isfinite(N), 2) & eligible(:);
    score = lineDistance .^ 2 + (opts.depthWeight * depth) .^ 2;
    score(~valid) = inf;
    rows = find(isfinite(score));
    if isempty(rows)
        error('acsPlanChamberPlacement:NoEligibleSkullVertex', ...
            'No eligible outer skull vertices were available for chamber placement.');
    end
    [~, order] = sort(score(rows), 'ascend');
    rows = rows(order);
    plan = [];
    nCheck = min(numel(rows), opts.collisionCheckTopCandidates);
    for i = 1:max(1, nCheck)
        idx = rows(i);
        candidate = makePlanFromVertex(TRskull, targetWorldMm, idx, opts, ...
            score(idx), lineDistance(idx));
        candidate = addPlanCollisionInfo(candidate, opts, skullInfo);
        if ~opts.checkChamberSkullIntersection || ...
                ~isfield(candidate, 'skullIntersection') || ...
                ~candidate.skullIntersection.hasIntersection
            plan = candidate;
            break;
        end
    end
    if isempty(plan)
        idx = rows(1);
        plan = makePlanFromVertex(TRskull, targetWorldMm, idx, opts, ...
            score(idx), lineDistance(idx));
        plan = addPlanCollisionInfo(plan, opts, skullInfo);
        warning('acsPlanChamberPlacement:NoCollisionFreeCandidate', ...
            ['No collision-free chamber candidate was found among the top %d ' ...
            'outer-skull candidates. Returning the best-scoring candidate.'], nCheck);
    end
end

function plan = makePlanFromVertex(TRskull, targetWorldMm, idx, opts, score, lineDistance)
    V = double(TRskull.Points);
    P = V(idx, :);
    [axisOut, contactInfo] = localSkullAxis(TRskull, idx, targetWorldMm, opts);
    depth = dot(P - targetWorldMm, axisOut);
    closestPoint = P - depth * axisOut;
    targetMiss = norm(targetWorldMm - closestPoint);
    plan = struct();
    plan.contactVertex = idx;
    plan.contactWorldMm = P;
    plan.axisOutWorld = axisOut;
    plan.trackDirectionInWorld = -axisOut;
    plan.depthToTargetMm = depth;
    plan.targetLineMissMm = targetMiss;
    plan.initialSearchScore = score;
    plan.initialLineDistanceMm = lineDistance;
    plan.localContact = contactInfo;
    plan.trackLineWorldMm = [P + opts.chamberHeightMm * axisOut; ...
        P - max(depth + 10, opts.chamberHeightMm) * axisOut];
    plan.basePerimeterWorldMm = chamberBasePerimeter(P, axisOut, ...
        opts.chamberOuterDiameterMm / 2, 96);
end

function [axisOut, info] = localSkullAxis(TRskull, idx, targetWorldMm, opts)
    V = double(TRskull.Points);
    P = V(idx, :);
    d = sqrt(sum((V - P) .^ 2, 2));
    rows = find(d <= opts.localPlaneRadiusMm);
    if numel(rows) < 6
        [~, order] = sort(d, 'ascend');
        rows = order(1:min(20, numel(order)));
    end
    Q = V(rows, :);
    C = mean(Q, 1);
    X = bsxfun(@minus, Q, C);
    [~, ~, coeff] = svd(X, 'econ');
    axisOut = coeff(:, end)';
    if dot(axisOut, P - targetWorldMm) < 0
        axisOut = -axisOut;
    end
    residual = abs(X * axisOut');
    info = struct('neighborRows', rows(:), ...
        'planeCenterWorldMm', C, ...
        'planeResidualMedianMm', median(residual), ...
        'planeResidualMaxMm', max(residual));
end

function plan = addPlanCollisionInfo(plan, opts, skullInfo)
    if ~opts.checkChamberSkullIntersection
        return;
    end
    if ~isfield(skullInfo, 'runtime') || ...
            ~isfield(skullInfo.runtime, 'boneMask') || ...
            ~isfield(skullInfo.runtime, 'maskMat')
        return;
    end
    [hasIntersection, summary] = chamberSkullIntersection(plan, opts, skullInfo);
    summary.hasIntersection = hasIntersection;
    plan.skullIntersection = summary;
end

function [hasIntersection, summary] = chamberSkullIntersection(plan, opts, skullInfo)
    points = sampleChamberWallPoints(plan, opts);
    boneMask = skullInfo.runtime.boneMask;
    vox = round(worldMmToVoxel1(points, skullInfo.runtime.maskMat));
    insideVolume = vox(:, 1) >= 1 & vox(:, 1) <= size(boneMask, 1) & ...
        vox(:, 2) >= 1 & vox(:, 2) <= size(boneMask, 2) & ...
        vox(:, 3) >= 1 & vox(:, 3) <= size(boneMask, 3);
    insideBone = false(size(points, 1), 1);
    if any(insideVolume)
        idx = sub2ind(size(boneMask), vox(insideVolume, 1), ...
            vox(insideVolume, 2), vox(insideVolume, 3));
        insideBone(insideVolume) = boneMask(idx);
    end
    hasIntersection = any(insideBone);
    summary = struct('nSamples', size(points, 1), ...
        'nInside', nnz(insideBone), ...
        'insideFraction', nnz(insideBone) / max(1, size(points, 1)), ...
        'clearanceMm', opts.collisionClearanceMm, ...
        'sampleStepMm', opts.collisionSampleStepMm);
end

function points = sampleChamberWallPoints(plan, opts)
    outerR = opts.chamberOuterDiameterMm / 2;
    innerR = opts.chamberInnerDiameterMm / 2;
    radii = unique([innerR, 0.5 * (innerR + outerR), outerR]);
    heights = opts.collisionClearanceMm:opts.collisionSampleStepMm:opts.chamberHeightMm;
    if isempty(heights) || heights(end) < opts.chamberHeightMm
        heights = unique([heights, opts.chamberHeightMm]);
    end
    nTheta = 32;
    theta = linspace(0, 2*pi, nTheta + 1)';
    theta(end) = [];
    [u, v] = perpendicularBasis(plan.axisOutWorld);
    ring = cos(theta) .* u + sin(theta) .* v;
    points = zeros(numel(heights) * numel(radii) * nTheta, 3);
    row = 0;
    for h = heights(:)'
        base = plan.contactWorldMm + h * plan.axisOutWorld;
        for r = radii(:)'
            rows = row + (1:nTheta);
            points(rows, :) = base + r * ring;
            row = row + nTheta;
        end
    end
    points = points(1:row, :);
end

function [plan, accepted, fig] = refinePlacementGui( ...
        TRskull, targetWorldMm, plan, opts, skullInfo, contextExclusions)
    accepted = false;
    V = double(TRskull.Points);
    eligibleRows = find(eligibleSkullVertices(TRskull, skullInfo, opts));
    Veligible = V(eligibleRows, :);
    TRdisplay = decimateTri(TRskull, opts.displaySkullSurfaceMaxFaces);
    plan = addPlanCollisionInfo(plan, opts, skullInfo);
    state.plan = plan;
    state.desired = plan.contactWorldMm;

    fig = figure('Name', 'Chamber placement refinement', ...
        'NumberTitle', 'off', 'Color', 'w', 'Visible', 'on', ...
        'Position', [70 60 1450 860], ...
        'WindowKeyPressFcn', @onKey);
    if opts.verbose
        fprintf(['Chamber refinement GUI is waiting for Done. MATLAB may ' ...
            'show the command window as busy while the figure remains interactive.\n']);
    end
    drawInteractive();
    uiwait(fig);
    if isgraphics(fig)
        plan = state.plan;
    end

    function onKey(~, event)
        mult = 1;
        if any(strcmpi(event.Modifier, 'shift'))
            mult = 5;
        end
        step = opts.nudgeMm * mult;
        delta = [0 0 0];
        switch lower(event.Key)
            case 'leftarrow'
                delta = [-step 0 0];
            case 'rightarrow'
                delta = [step 0 0];
            case 'uparrow'
                delta = [0 step 0];
            case 'downarrow'
                delta = [0 -step 0];
            case 'u'
                delta = [0 0 step];
            case 'd'
                delta = [0 0 -step];
            case {'return', 'enter'}
                done();
                return;
            case 'escape'
                cancel();
                return;
            otherwise
                return;
        end
        state.desired = state.desired + delta;
        [~, localIdx] = min(sum((Veligible - state.desired) .^ 2, 2));
        idx = eligibleRows(localIdx);
        state.plan = makePlanFromVertex(TRskull, targetWorldMm, idx, opts, NaN, NaN);
        state.plan = addPlanCollisionInfo(state.plan, opts, skullInfo);
        drawInteractive();
    end

    function drawInteractive()
        cameraState = captureChamberCamera(fig);
        redrawQcFigure(fig, TRdisplay, targetWorldMm, state.plan, opts, ...
            contextExclusions, cameraState);
        uicontrol(fig, 'Style', 'pushbutton', 'String', 'Done', ...
            'Units', 'normalized', 'Position', [0.80 0.02 0.08 0.045], ...
            'Callback', @(~, ~) done());
        uicontrol(fig, 'Style', 'pushbutton', 'String', 'Cancel', ...
            'Units', 'normalized', 'Position', [0.89 0.02 0.08 0.045], ...
            'Callback', @(~, ~) cancel());
        annotation(fig, 'textbox', [0.04 0.005 0.72 0.055], ...
            'String', 'Nudge skull contact: arrows = X/Y, U/D = Z, Shift = 5x. Enter = done.', ...
            'EdgeColor', 'none', 'Interpreter', 'none', 'FontSize', 9);
        set(fig, 'WindowKeyPressFcn', @onKey);
    end

    function done()
        accepted = true;
        if isgraphics(fig)
            uiresume(fig);
        end
    end

    function cancel()
        accepted = false;
        if isgraphics(fig)
            uiresume(fig);
        end
    end
end

function fig = makeQcFigure(TRskull, targetWorldMm, plan, opts, ...
        contextExclusions, visible)
    TRplot = decimateTri(TRskull, opts.displaySkullSurfaceMaxFaces);
    figPos = [70 60 1450 860];
    if shouldShowTargetSlices(opts)
        figPos = [70 60 1650 860];
    end
    fig = figure('Name', 'Chamber placement QC', ...
        'NumberTitle', 'off', 'Color', 'w', 'Visible', visible, ...
        'Position', figPos);
    redrawQcFigure(fig, TRplot, targetWorldMm, plan, opts, contextExclusions, []);
end

function redrawQcFigure(fig, TRskull, targetWorldMm, plan, opts, ...
        contextExclusions, cameraState)
    if nargin < 7
        cameraState = [];
    end
    clf(fig);
    showSlices = shouldShowTargetSlices(opts);
    mainPos = [0.075 0.20 0.74 0.66];
    if showSlices
        mainPos = [0.169 0.17 0.47 0.72];
    end
    ax = axes(fig, 'Position', mainPos, ...
        'Tag', 'chamberPlacementMainAxes'); %#ok<LAXES>
    hold(ax, 'on');
    patch(ax, 'Faces', TRskull.ConnectivityList, 'Vertices', TRskull.Points, ...
        'FaceColor', [0.78 0.78 0.74], 'FaceAlpha', 0.22, 'EdgeColor', 'none');
    chamber = makeChamberMesh(plan.contactWorldMm, plan.axisOutWorld, opts);
    patch(ax, 'Faces', chamber.faces, 'Vertices', chamber.vertices, ...
        'FaceColor', [0.05 0.35 0.90], 'FaceAlpha', 0.30, 'EdgeColor', 'none');
    plot3(ax, plan.basePerimeterWorldMm(:, 1), plan.basePerimeterWorldMm(:, 2), ...
        plan.basePerimeterWorldMm(:, 3), 'm-', 'LineWidth', 2);
    plot3(ax, plan.trackLineWorldMm(:, 1), plan.trackLineWorldMm(:, 2), ...
        plan.trackLineWorldMm(:, 3), 'r-', 'LineWidth', 2.4);
    scatter3(ax, targetWorldMm(1), targetWorldMm(2), targetWorldMm(3), ...
        90, [0.95 0.05 0.55], 'p', 'filled', 'MarkerEdgeColor', 'k');
    scatter3(ax, plan.contactWorldMm(1), plan.contactWorldMm(2), ...
        plan.contactWorldMm(3), 70, [0.05 0.05 0.05], 'filled');
    drawContextExclusions(ax, contextExclusions, TRskull);
    fitChamberAxes(ax, TRskull, targetWorldMm, plan, contextExclusions);
    daspect(ax, [1 1 1]);
    axis(ax, 'vis3d');
    grid(ax, 'on');
    xlabel(ax, 'X world mm');
    ylabel(ax, 'Y world mm');
    zlabel(ax, 'Z world mm');
    camproj(ax, 'orthographic');
    applyChamberQcCamera(ax, targetWorldMm, plan, opts, cameraState);
    camlight(ax, 'headlight');
    lighting(ax, 'gouraud');
    collisionText = '';
    if isfield(plan, 'skullIntersection') && ...
            isfield(plan.skullIntersection, 'hasIntersection')
        if plan.skullIntersection.hasIntersection
            collisionText = sprintf(' | skull intersection %d/%d samples', ...
                plan.skullIntersection.nInside, plan.skullIntersection.nSamples);
        else
            collisionText = ' | no sampled skull intersection';
        end
    end
    title(ax, sprintf('Chamber placement | miss %.2f mm | depth %.1f mm%s', ...
        plan.targetLineMissMm, plan.depthToTargetMm, collisionText), ...
        'Interpreter', 'none');
    leg = legend(ax, {'skull', 'chamber', 'outer perimeter', ...
        'center track', 'target', 'skull contact'}, ...
        'Box', 'off', 'FontSize', 8);
    if showSlices
        set(leg, 'Units', 'normalized', 'Position', [0.70 0.035 0.24 0.08]);
        drawTargetSlicePanels(fig, opts, targetWorldMm);
    else
        set(leg, 'Units', 'normalized', 'Position', [0.835 0.48 0.145 0.18]);
    end
    compactFigureText(fig);
    drawnow;
end

function tf = shouldShowTargetSlices(opts)
    tf = isfield(opts, 'targetSliceMode') && ...
        strcmpi(char(opts.targetSliceMode), 'orthogonal');
    tf = tf && isfield(opts, 'qcT1File') && ~isempty(opts.qcT1File) && ...
        exist(opts.qcT1File, 'file') == 2;
end

function applyChamberQcCamera(ax, targetWorldMm, plan, opts, cameraState)
    if ~isempty(cameraState) && isstruct(cameraState)
        restoreChamberCamera(ax, cameraState);
        return;
    end
    if ~isfield(opts, 'qcCameraMode') || ...
            ~strcmpi(char(opts.qcCameraMode), 'chamberbore')
        view(ax, 3);
        return;
    end
    axisOut = normalizeRow(plan.axisOutWorld);
    contact = double(plan.contactWorldMm(:)');
    target = double(targetWorldMm(:)');
    depth = max(0, dot(contact - target, axisOut));
    distance = max([60, opts.chamberHeightMm + depth + 35, ...
        4 * opts.chamberOuterDiameterMm]);
    cameraPosition = contact + distance * axisOut;
    cameraTarget = contact - max(depth, opts.chamberHeightMm) * axisOut;
    viewDirection = normalizeRow(cameraTarget - cameraPosition);
    cameraUp = preferredCameraUpVector(viewDirection, [0 0 1]);
    if norm(cameraUp) <= eps
        [u, ~] = perpendicularBasis(axisOut);
        cameraUp = u;
    end
    set(ax, ...
        'CameraPosition', cameraPosition, ...
        'CameraTarget', cameraTarget, ...
        'CameraUpVector', cameraUp);
    try
        camva(ax, opts.qcBoreCameraViewAngle);
    catch
    end
end

function cameraUp = preferredCameraUpVector(viewDirection, preferredUp)
    viewDirection = normalizeRow(viewDirection);
    preferredUp = normalizeRow(preferredUp);
    cameraUp = preferredUp - dot(preferredUp, viewDirection) * viewDirection;
    n = norm(cameraUp);
    if n <= eps || ~isfinite(n)
        cameraUp = [0 0 0];
    else
        cameraUp = cameraUp ./ n;
    end
end

function drawTargetSlicePanels(fig, opts, targetWorldMm)
    planes = opts.targetSlicePlanes;
    if isempty(planes)
        return;
    end
    nPanels = min(2, numel(planes));
    positions = targetSlicePanelPositions(nPanels);
    try
        Vt1 = spm_vol(opts.qcT1File);
        Vt1 = Vt1(1);
        vol = spm_read_vols(Vt1);
    catch ME
        warning('acsPlanChamberPlacement:TargetSliceReadFailed', ...
            'Could not read target-slice anatomy from %s: %s', ...
            opts.qcT1File, ME.message);
        return;
    end
    if ndims(vol) > 3
        vol = vol(:, :, :, 1);
    end
    if isfield(opts, 'qcTargetVoxel') && ~isempty(opts.qcTargetVoxel)
        targetVoxel = double(opts.qcTargetVoxel(:)');
    else
        targetVoxel = worldMmToVoxel1(double(targetWorldMm(:)'), Vt1.mat);
    end
    targetVoxel = clampVoxel(round(targetVoxel), size(vol));
    for i = 1:nPanels
        plane = planes{i};
        ax = axes(fig, 'Position', positions(i, :), ...
            'Tag', ['chamberTargetSlice_' plane]); %#ok<LAXES>
        [img, targetXY, titleText] = targetSliceImage(vol, targetVoxel, plane);
        imagesc(ax, img);
        colormap(ax, gray(256));
        axis(ax, 'image');
        axis(ax, 'off');
        set(ax, 'YDir', 'normal');
        setRobustGrayLimits(ax, img);
        hold(ax, 'on');
        drawSliceCrosshair(ax, targetXY);
        title(ax, titleText, 'Interpreter', 'none', 'FontWeight', 'normal');
    end
end

function positions = targetSlicePanelPositions(nPanels)
    if nPanels <= 1
        positions = [0.68 0.293 0.27 0.46];
    else
        positions = [0.68 0.547 0.27 0.34; ...
                     0.68 0.147 0.27 0.34];
    end
end

function vox = clampVoxel(vox, sz)
    sz = double(sz(1:3));
    vox = double(vox(:)');
    vox = max([1 1 1], min(sz, vox));
end

function [img, targetXY, titleText] = targetSliceImage(vol, targetVoxel, plane)
    switch lower(char(plane))
        case 'sagittal'
            img = squeeze(vol(targetVoxel(1), :, :))';
            targetXY = [targetVoxel(2), targetVoxel(3)];
            titleText = 'Sagittal target slice';
        case 'coronal'
            img = squeeze(vol(:, targetVoxel(2), :))';
            targetXY = [targetVoxel(1), targetVoxel(3)];
            titleText = 'Coronal target slice';
        case 'axial'
            img = squeeze(vol(:, :, targetVoxel(3)))';
            targetXY = [targetVoxel(1), targetVoxel(2)];
            titleText = 'Axial target slice';
        otherwise
            error('acsPlanChamberPlacement:BadSlicePlane', ...
                'Unknown target slice plane: %s', char(plane));
    end
    img = double(img);
end

function setRobustGrayLimits(ax, img)
    values = img(isfinite(img));
    if isempty(values)
        return;
    end
    try
        lim = prctile(values, [1 99.5]);
    catch
        lim = [min(values), max(values)];
    end
    if ~all(isfinite(lim)) || lim(2) <= lim(1)
        lim = [min(values), max(values)];
    end
    if all(isfinite(lim)) && lim(2) > lim(1)
        caxis(ax, lim);
    end
end

function drawSliceCrosshair(ax, targetXY)
    xl = xlim(ax);
    yl = ylim(ax);
    c = [0.95 0.00 0.65];
    plot(ax, [targetXY(1) targetXY(1)], yl, '-', 'Color', c, 'LineWidth', 1.4);
    plot(ax, xl, [targetXY(2) targetXY(2)], '-', 'Color', c, 'LineWidth', 1.4);
    scatter(ax, targetXY(1), targetXY(2), 85, c, 'p', 'filled', ...
        'MarkerEdgeColor', [0.30 0.00 0.20], 'LineWidth', 1.0);
end

function drawContextExclusions(ax, contextExclusions, TRsurface)
    if isempty(contextExclusions)
        return;
    end
    for i = 1:numel(contextExclusions)
        if isfield(contextExclusions(i), 'pointsWorldMm') && ...
                ~isempty(contextExclusions(i).pointsWorldMm)
            P = double(contextExclusions(i).pointsWorldMm);
            scatter3(ax, P(:, 1), P(:, 2), P(:, 3), 22, ...
                [0.95 0.20 0.05], 'filled', ...
                'MarkerEdgeColor', 'k', 'HandleVisibility', 'off');
        end
        if isfield(contextExclusions(i), 'keepoutBoundaryWorldMm') && ...
                ~isempty(contextExclusions(i).keepoutBoundaryWorldMm)
            B = double(contextExclusions(i).keepoutBoundaryWorldMm);
            B = surfaceFollowBoundaryWorld(B, TRsurface);
            plot3(ax, B(:, 1), B(:, 2), B(:, 3), '--', ...
                'Color', [0.85 0.00 0.05], ...
                'LineWidth', 2.4, 'HandleVisibility', 'off');
            center = mean(B(isfinite(sum(B, 2)), :), 1);
            if all(isfinite(center))
                text(ax, center(1), center(2), center(3), ...
                    char(contextExclusions(i).name), ...
                    'Color', [0.70 0.00 0.00], ...
                    'FontWeight', 'bold', ...
                    'Interpreter', 'none', ...
                    'HandleVisibility', 'off');
            end
        end
    end
end

function fitChamberAxes(ax, TRskull, targetWorldMm, plan, contextExclusions)
    points = double(TRskull.Points);
    points = [points; targetWorldMm(:)']; %#ok<AGROW>
    fields = {'basePerimeterWorldMm', 'trackLineWorldMm', 'contactWorldMm'};
    for i = 1:numel(fields)
        if isfield(plan, fields{i}) && ~isempty(plan.(fields{i}))
            value = double(plan.(fields{i}));
            points = [points; reshape(value, [], 3)]; %#ok<AGROW>
        end
    end
    if ~isempty(contextExclusions)
        for i = 1:numel(contextExclusions)
            if isfield(contextExclusions(i), 'pointsWorldMm') && ...
                    ~isempty(contextExclusions(i).pointsWorldMm)
                points = [points; double(contextExclusions(i).pointsWorldMm)]; %#ok<AGROW>
            end
            if isfield(contextExclusions(i), 'keepoutBoundaryWorldMm') && ...
                    ~isempty(contextExclusions(i).keepoutBoundaryWorldMm)
                B = surfaceFollowBoundaryWorld( ...
                    double(contextExclusions(i).keepoutBoundaryWorldMm), TRskull);
                points = [points; B]; %#ok<AGROW>
            end
        end
    end
    points = points(all(isfinite(points), 2), :);
    if isempty(points)
        return;
    end
    lo = min(points, [], 1);
    hi = max(points, [], 1);
    span = hi - lo;
    pad = max(2, 0.04 * max(span));
    bad = ~isfinite(span) | span <= 0;
    span(bad) = 1;
    lo = lo - pad;
    hi = hi + pad;
    xlim(ax, [lo(1), hi(1)]);
    ylim(ax, [lo(2), hi(2)]);
    zlim(ax, [lo(3), hi(3)]);
end

function B = surfaceFollowBoundaryWorld(B, TRsurface)
    if isempty(B) || ~isa(TRsurface, 'triangulation') || isempty(TRsurface.Points)
        return;
    end
    finiteRows = find(all(isfinite(B(:, 1:3)), 2));
    if isempty(finiteRows)
        return;
    end
    V = double(TRsurface.Points);
    span = max(V, [], 1) - min(V, [], 1);
    searchRadius = max(2, 0.04 * max(span(1:2)));
    B(finiteRows, 3) = topSurfaceZAtXY(V, B(finiteRows, 1:2), searchRadius);
    B(finiteRows, 3) = smoothBoundaryCoordinate(B(:, 3), finiteRows, 5);
end

function z = topSurfaceZAtXY(V, queryXY, searchRadius)
    z = nan(size(queryXY, 1), 1);
    Vxy = V(:, 1:2);
    for i = 1:size(queryXY, 1)
        d2 = sum(bsxfun(@minus, Vxy, queryXY(i, :)) .^ 2, 2);
        rows = find(d2 <= searchRadius ^ 2);
        if isempty(rows)
            [~, row] = min(d2);
            z(i) = V(row, 3);
        else
            z(i) = max(V(rows, 3));
        end
    end
end

function zOut = smoothBoundaryCoordinate(zIn, finiteRows, windowSize)
    zOut = zIn(finiteRows);
    if numel(zOut) < windowSize || any(~isfinite(zOut))
        return;
    end
    halfWindow = floor(windowSize / 2);
    zSmooth = zOut;
    closedLoop = norm(zOut(1) - zOut(end)) < 1e-9;
    for i = 1:numel(zOut)
        if closedLoop
            rows = mod((i - halfWindow):(i + halfWindow) - 1, numel(zOut)) + 1;
        else
            rows = max(1, i - halfWindow):min(numel(zOut), i + halfWindow);
        end
        zSmooth(i) = median(zOut(rows));
    end
    zOut = zSmooth;
end

function cameraState = captureChamberCamera(fig)
    cameraState = [];
    if isempty(fig) || ~isgraphics(fig)
        return;
    end
    ax = findobj(fig, 'Type', 'axes', 'Tag', 'chamberPlacementMainAxes');
    if isempty(ax) || ~isgraphics(ax(1))
        return;
    end
    ax = ax(1);
    props = {'CameraPosition', 'CameraTarget', 'CameraUpVector', ...
        'CameraViewAngle', 'XLim', 'YLim', 'ZLim'};
    cameraState = struct();
    for i = 1:numel(props)
        cameraState.(props{i}) = get(ax, props{i});
    end
end

function restoreChamberCamera(ax, cameraState)
    if isempty(cameraState) || ~isstruct(cameraState)
        return;
    end
    props = {'CameraPosition', 'CameraTarget', 'CameraUpVector', ...
        'CameraViewAngle', 'XLim', 'YLim', 'ZLim'};
    for i = 1:numel(props)
        if isfield(cameraState, props{i}) && ...
                all(isfinite(double(cameraState.(props{i})(:))))
            try
                set(ax, props{i}, cameraState.(props{i}));
            catch
            end
        end
    end
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

function chamber = makeChamberMesh(contactWorldMm, axisOut, opts)
    outerR = opts.chamberOuterDiameterMm / 2;
    innerR = opts.chamberInnerDiameterMm / 2;
    height = opts.chamberHeightMm;
    n = 96;
    [u, v] = perpendicularBasis(axisOut);
    theta = linspace(0, 2*pi, n + 1)';
    theta(end) = [];
    ring = cos(theta) .* u + sin(theta) .* v;
    outer0 = contactWorldMm + outerR * ring;
    outer1 = contactWorldMm + height * axisOut + outerR * ring;
    inner0 = contactWorldMm + innerR * ring;
    inner1 = contactWorldMm + height * axisOut + innerR * ring;
    vertices = [outer0; outer1; inner0; inner1];
    faces = zeros(0, 3);
    for i = 1:n
        j = i + 1;
        if j > n, j = 1; end
        o0i = i; o0j = j; o1i = n + i; o1j = n + j;
        in0i = 2*n + i; in0j = 2*n + j; in1i = 3*n + i; in1j = 3*n + j;
        faces = [faces; ...
            o0i o0j o1j; o0i o1j o1i; ...
            in0j in0i in1j; in0i in1i in1j; ...
            o1i o1j in1j; o1i in1j in1i; ...
            o0j o0i in0j; o0i in0i in0j]; %#ok<AGROW>
    end
    chamber = struct('vertices', vertices, 'faces', faces);
end

function perimeter = chamberBasePerimeter(contactWorldMm, axisOut, radiusMm, n)
    [u, v] = perpendicularBasis(axisOut);
    theta = linspace(0, 2*pi, n + 1)';
    theta(end) = [];
    perimeter = contactWorldMm + radiusMm * (cos(theta) .* u + sin(theta) .* v);
end

function [u, v] = perpendicularBasis(axisOut)
    axisOut = normalizeRow(axisOut);
    ref = [0 0 1];
    if abs(dot(axisOut, ref)) > 0.9
        ref = [0 1 0];
    end
    u = normalizeRow(cross(axisOut, ref));
    v = normalizeRow(cross(axisOut, u));
end

function exclusion = makeExclusionProduct(plan, opts)
    exclusion = struct();
    exclusion.type = 'chamberExclusion';
    exclusion.name = 'recordingChamber';
    exclusion.marginMm = opts.exclusionMarginMm;
    exclusion.outerDiameterMm = opts.chamberOuterDiameterMm;
    exclusion.basePerimeterWorldMm = plan.basePerimeterWorldMm;
    exclusion.keepoutRadiusMm = opts.chamberOuterDiameterMm / 2 + opts.exclusionMarginMm;
end

function exclusion = addPrintFrameExclusion(exclusion, skinCacheFile, Vref, opts)
    S = load(skinCacheFile, 'meta', 'TRskin');
    if ~isfield(S, 'meta')
        warning('acsPlanChamberPlacement:MissingSkinMeta', ...
            'Skin cache does not contain meta; capMaker print-frame exclusion not written.');
        return;
    end
    [basePrint, transformInfo] = t1WorldMmToPrintMm( ...
        exclusion.basePerimeterWorldMm, Vref, S.meta);
    try
        basePoly = polyshape(basePrint(:, 1), basePrint(:, 2), 'Simplify', true);
        keepoutPoly = polybuffer(basePoly, opts.exclusionMarginMm);
    catch
        keepoutPoly = fallbackCirclePoly(mean(basePrint(:, 1:2), 1), ...
            exclusion.keepoutRadiusMm);
    end
    [x, y] = boundary(keepoutPoly);
    keep = isfinite(x) & isfinite(y);
    z = boundaryZOnSkin([x(keep), y(keep)], S, median(basePrint(:, 3)));
    exclusion.skinCacheFile = skinCacheFile;
    exclusion.basePerimeterPrintMm = basePrint;
    exclusion.keepoutPoly = keepoutPoly;
    exclusion.railExclusionPolys = {keepoutPoly};
    exclusion.keepoutBoundaryMm = [x(keep), y(keep), z(:)];
    exclusion.keepoutPolyX = x(keep);
    exclusion.keepoutPolyY = y(keep);
    exclusion.coordinateFrame = 'capMakerPrintMm';
    exclusion.printFrameMethod = printFrameMethodVersion();
    exclusion.printFrameTransform = transformInfo;
    exclusion.volumeWorldReference = Vref.fname;
end

function method = printFrameMethodVersion()
    method = 't1WorldToCapMakerPrint_v2';
end

function tf = needsPrintFrameExclusionRefresh(out, opts)
    tf = false;
    if isempty(opts.skinCacheFile) || ~isstruct(out) || ...
            ~isfield(out, 'exclusion') || ~isstruct(out.exclusion)
        return;
    end
    exclusion = out.exclusion;
    if ~isfield(exclusion, 'basePerimeterWorldMm') || ...
            isempty(exclusion.basePerimeterWorldMm)
        return;
    end
    if ~isfield(exclusion, 'coordinateFrame') || ...
            ~strcmpi(char(exclusion.coordinateFrame), 'capMakerPrintMm')
        tf = true;
        return;
    end
    if ~isfield(exclusion, 'keepoutBoundaryMm') || ...
            isempty(exclusion.keepoutBoundaryMm)
        tf = true;
        return;
    end
    if ~isfield(exclusion, 'skinCacheFile') || ...
            isempty(exclusion.skinCacheFile) || ...
            ~sameFilePath(exclusion.skinCacheFile, opts.skinCacheFile)
        tf = true;
        return;
    end
    if ~isfield(exclusion, 'printFrameMethod') || ...
            ~strcmpi(char(exclusion.printFrameMethod), printFrameMethodVersion())
        tf = true;
    end
end

function contextExclusions = resolveContextExclusions( ...
        files, skinCacheFile, Vref, opts)
    contextExclusions = emptyContextExclusion();
    contextExclusions(:) = [];
    files = normalizeFileList(files);
    if isempty(files)
        return;
    end
    if isempty(skinCacheFile) || exist(skinCacheFile, 'file') ~= 2
        warning('acsPlanChamberPlacement:MissingContextSkinCache', ...
            ['Context exclusions were requested, but no readable skin ', ...
             'cache was provided for print-to-T1 visualization.']);
        return;
    end
    Sskin = load(skinCacheFile, 'meta');
    if ~isfield(Sskin, 'meta')
        warning('acsPlanChamberPlacement:MissingContextSkinMeta', ...
            ['Context exclusions were requested, but the skin cache does ', ...
             'not contain capMaker transform metadata.']);
        return;
    end
    for i = 1:numel(files)
        fileName = files{i};
        if isempty(fileName)
            continue;
        end
        if exist(fileName, 'file') ~= 2
            warning('acsPlanChamberPlacement:MissingContextExclusion', ...
                'Context exclusion file not found: %s', fileName);
            continue;
        end
        try
            S = loadSavedOutput(fileName);
            if isfield(S, 'exclusion') && isstruct(S.exclusion)
                S = S.exclusion;
            end
            contextExclusions(end + 1, 1) = contextExclusionFromStruct( ...
                S, fileName, Vref, Sskin.meta); %#ok<AGROW>
        catch ME
            warning('acsPlanChamberPlacement:BadContextExclusion', ...
                'Could not use context exclusion %s: %s', fileName, ME.message);
        end
    end
    if opts.verbose && ~isempty(contextExclusions)
        fprintf('Loaded %d context exclusion(s) for chamber planning.\n', ...
            numel(contextExclusions));
    end
end

function value = emptyContextExclusion()
    value = struct( ...
        'name', '', ...
        'file', '', ...
        'coordinateFrame', '', ...
        'pointsPrintMm', zeros(0, 3), ...
        'keepoutBoundaryPrintMm', zeros(0, 3), ...
        'pointsWorldMm', zeros(0, 3), ...
        'keepoutBoundaryWorldMm', zeros(0, 3), ...
        'keepoutPoly', [], ...
        'transform', struct());
end

function value = contextExclusionFromStruct(S, fileName, Vref, skinMeta)
    value = emptyContextExclusion();
    value.file = fileName;
    value.name = char(optionalField(S, 'name', stripExtension(getFileName(fileName))));
    value.coordinateFrame = char(optionalField(S, 'coordinateFrame', ''));
    if isempty(value.coordinateFrame)
        error('Context exclusion "%s" does not report coordinateFrame.', ...
            value.name);
    end
    if ~strcmpi(value.coordinateFrame, 'capMakerPrintMm')
        error('Context exclusion "%s" is in %s, not capMakerPrintMm.', ...
            value.name, value.coordinateFrame);
    end

    value.pointsPrintMm = optionalPointMatrix(S, ...
        {'projectedCoordinatesMm', 'coordinatesMm'});
    value.keepoutBoundaryPrintMm = optionalPointMatrix(S, ...
        {'keepoutBoundaryMm'});
    if isempty(value.keepoutBoundaryPrintMm) && ...
            isfield(S, 'keepoutPolyX') && isfield(S, 'keepoutPolyY')
        x = double(S.keepoutPolyX(:));
        y = double(S.keepoutPolyY(:));
        validZ = value.pointsPrintMm(:, 3);
        validZ = validZ(isfinite(validZ));
        if isempty(validZ)
            z0 = 0;
        else
            z0 = median(validZ);
        end
        z = repmat(z0, numel(x), 1);
        value.keepoutBoundaryPrintMm = [x, y, z];
    end
    value.keepoutPoly = contextKeepoutPoly(S, value.keepoutBoundaryPrintMm);

    if ~isempty(value.pointsPrintMm)
        [value.pointsWorldMm, value.transform] = printMmToT1WorldMm( ...
            value.pointsPrintMm, Vref, skinMeta);
    end
    if ~isempty(value.keepoutBoundaryPrintMm)
        [value.keepoutBoundaryWorldMm, value.transform] = printMmToT1WorldMm( ...
            value.keepoutBoundaryPrintMm, Vref, skinMeta);
    end
end

function points = optionalPointMatrix(S, names)
    points = zeros(0, 3);
    for i = 1:numel(names)
        name = names{i};
        if isfield(S, name) && ~isempty(S.(name))
            points = double(S.(name));
            if size(points, 2) >= 3
                points = points(:, 1:3);
                return;
            end
        end
    end
    points = zeros(0, 3);
end

function ps = contextKeepoutPoly(S, boundaryMm)
    ps = [];
    if isfield(S, 'keepoutPoly') && ~isempty(S.keepoutPoly)
        ps = S.keepoutPoly;
        return;
    end
    if isfield(S, 'keepoutPolyX') && isfield(S, 'keepoutPolyY') && ...
            ~isempty(S.keepoutPolyX) && ~isempty(S.keepoutPolyY)
        ps = polyshape(double(S.keepoutPolyX(:)), ...
            double(S.keepoutPolyY(:)), 'Simplify', true);
        return;
    end
    if ~isempty(boundaryMm)
        ps = polyshape(boundaryMm(:, 1), boundaryMm(:, 2), ...
            'Simplify', true);
    end
end

function collision = summarizeContextCollision(exclusion, contextExclusions, opts)
    collision = struct( ...
        'name', {}, ...
        'overlapAreaMm2', {}, ...
        'hasOverlap', {});
    if isempty(contextExclusions) || ~isfield(exclusion, 'keepoutPoly') || ...
            isempty(exclusion.keepoutPoly)
        return;
    end
    for i = 1:numel(contextExclusions)
        value = struct( ...
            'name', char(contextExclusions(i).name), ...
            'overlapAreaMm2', 0, ...
            'hasOverlap', false);
        if isfield(contextExclusions(i), 'keepoutPoly') && ...
                ~isempty(contextExclusions(i).keepoutPoly)
            try
                overlapPoly = intersect(exclusion.keepoutPoly, ...
                    contextExclusions(i).keepoutPoly);
                value.overlapAreaMm2 = area(overlapPoly);
                value.hasOverlap = value.overlapAreaMm2 > 1e-6;
            catch
                value.overlapAreaMm2 = NaN;
                value.hasOverlap = false;
            end
        end
        collision(end + 1, 1) = value; %#ok<AGROW>
        if value.hasOverlap
            warning('acsPlanChamberPlacement:ContextExclusionOverlap', ...
                ['Chamber keepout overlaps context exclusion "%s" by ', ...
                 '%.1f mm^2. Review chamber placement before surgery/cap ', ...
                 'manufacturing.'], value.name, value.overlapAreaMm2);
        elseif opts.verbose
            fprintf('Chamber keepout has no overlap with context exclusion "%s".\n', ...
                value.name);
        end
    end
end

function tf = sameFilePath(a, b)
    tf = strcmpi(char(expandUserPath(char(a))), char(expandUserPath(char(b))));
end

function value = optionalField(S, fieldName, defaultValue)
    if isstruct(S) && isfield(S, fieldName) && ~isempty(S.(fieldName))
        value = S.(fieldName);
    else
        value = defaultValue;
    end
end

function z = boundaryZOnSkin(xy, skinCache, fallbackZ)
    z = repmat(fallbackZ, size(xy, 1), 1);
    if ~isfield(skinCache, 'TRskin') || isempty(skinCache.TRskin) || isempty(xy)
        return;
    end
    TRskin = skinCache.TRskin;
    if isa(TRskin, 'triangulation')
        V = double(TRskin.Points);
    elseif isstruct(TRskin) && isfield(TRskin, 'Points')
        V = double(TRskin.Points);
    else
        return;
    end
    if size(V, 2) < 3 || isempty(V)
        return;
    end
    idx = nearestRows2d(V(:, 1:2), double(xy), 2500);
    z = V(idx, 3);
end

function idx = nearestRows2d(referenceXY, queryXY, chunkSize)
    referenceXY = double(referenceXY);
    queryXY = double(queryXY);
    idx = ones(size(queryXY, 1), 1);
    for a = 1:chunkSize:size(queryXY, 1)
        b = min(size(queryXY, 1), a + chunkSize - 1);
        D = squaredDistanceRows(queryXY(a:b, :), referenceXY);
        [~, localIdx] = min(D, [], 2);
        idx(a:b) = localIdx;
    end
end

function D = squaredDistanceRows(A, B)
    D = bsxfun(@plus, sum(A .^ 2, 2), sum(B .^ 2, 2)') - 2 * (A * B');
    D(D < 0) = 0;
end

function ps = fallbackCirclePoly(centerXY, radiusMm)
    theta = linspace(0, 2*pi, 96);
    theta(end) = [];
    ps = polyshape(centerXY(1) + radiusMm*cos(theta), ...
        centerXY(2) + radiusMm*sin(theta), 'Simplify', true);
end

function [printMm, info] = t1WorldMmToPrintMm(t1WorldMm, Vref, meta)
    requireSkinMetaTransforms(meta);
    orientation = capMakerVoxelOrientationFromMeta(meta);
    t1VoxelSize = voxelSizesFromMat(Vref.mat);
    rasVoxel1 = worldMmToVoxel1(t1WorldMm, Vref.mat);
    capVoxel0 = rasVoxel1ToCapMakerVoxel0(rasVoxel1, ...
        orientation.capMakerVoxelOrientation, orientation.size, ...
        orientation.voxelSize, t1VoxelSize);
    capWorldMm = applyAffineToPoints(meta.original.vox2world, capVoxel0);
    alignedWorldMm = (double(meta.align.R) * capWorldMm')';
    printMm = applyAffineToPoints(meta.print.T_world2print, alignedWorldMm);

    info = orientation;
    info.method = printFrameMethodVersion();
    info.t1VoxelSize = t1VoxelSize;
    info.t1WorldReference = Vref.fname;
end

function [t1WorldMm, info] = printMmToT1WorldMm(printMm, Vref, meta)
    requireSkinMetaTransforms(meta);
    orientation = capMakerVoxelOrientationFromMeta(meta);
    t1VoxelSize = voxelSizesFromMat(Vref.mat);
    capVoxel0 = capMakerPrintToCapVoxel(printMm, meta);
    rasVoxel1 = orientVoxelPointsToRas(capVoxel0, ...
        orientation.capMakerVoxelOrientation, orientation.size, ...
        orientation.voxelSize, t1VoxelSize);
    t1WorldMm = voxel1ToWorldMm(rasVoxel1, Vref.mat);

    info = orientation;
    info.method = 'capMakerPrintToT1World_v1';
    info.t1VoxelSize = t1VoxelSize;
    info.t1WorldReference = Vref.fname;
end

function capVoxel0 = capMakerPrintToCapVoxel(pointsPrint, meta)
    requireSkinMetaTransforms(meta);
    alignedWorldMm = applyAffineToPoints(meta.print.T_print2world, pointsPrint);
    capWorldMm = (double(meta.align.R) \ alignedWorldMm')';
    capVoxel0 = applyAffineToPoints(inv(double(meta.original.vox2world)), ...
        capWorldMm);
end

function rasVoxel1 = orientVoxelPointsToRas( ...
        voxel0, orientationCode, dims, srcVoxelSize, dstVoxelSize)
    orientationCode = validateOrientationCode(orientationCode);
    dims = double(dims(:)');
    srcVoxelSize = double(srcVoxelSize(:)');
    dstVoxelSize = double(dstVoxelSize(:)');

    targets = 'ras';
    opposites = 'lpi';
    rasMm = zeros(size(voxel0, 1), 3);
    for rasDim = 1:3
        srcDim = find(orientationCode == targets(rasDim) | ...
            orientationCode == opposites(rasDim), 1);
        if orientationCode(srcDim) == opposites(rasDim)
            coord0 = (dims(srcDim) - 1) - voxel0(:, srcDim);
        else
            coord0 = voxel0(:, srcDim);
        end
        rasMm(:, rasDim) = coord0 .* srcVoxelSize(srcDim);
    end

    rasVoxel1 = bsxfun(@rdivide, rasMm, dstVoxelSize) + 1;
end

function capVoxel0 = rasVoxel1ToCapMakerVoxel0( ...
        rasVoxel1, orientationCode, dims, srcVoxelSize, dstVoxelSize)
    orientationCode = validateOrientationCode(orientationCode);
    dims = double(dims(:)');
    srcVoxelSize = double(srcVoxelSize(:)');
    dstVoxelSize = double(dstVoxelSize(:)');
    rasMm = bsxfun(@times, double(rasVoxel1) - 1, dstVoxelSize);

    targets = 'ras';
    opposites = 'lpi';
    capVoxel0 = zeros(size(rasVoxel1, 1), 3);
    for rasDim = 1:3
        srcDim = find(orientationCode == targets(rasDim) | ...
            orientationCode == opposites(rasDim), 1);
        coord0 = rasMm(:, rasDim) ./ srcVoxelSize(srcDim);
        if orientationCode(srcDim) == opposites(rasDim)
            coord0 = (dims(srcDim) - 1) - coord0;
        end
        capVoxel0(:, srcDim) = coord0;
    end
end

function voxelSize = voxelSizesFromMat(M)
    voxelSize = sqrt(sum(double(M(1:3, 1:3)) .^ 2, 1));
    voxelSize(~isfinite(voxelSize) | voxelSize <= 0) = 1;
end

function info = capMakerVoxelOrientationFromMeta(meta)
    requireSkinMetaTransforms(meta);
    info = struct();
    info.t1Orientation = 'ras';
    info.permuteDims = [1 2 3];
    info.flipDims = [false false false];
    if isfield(meta.original, 'orientation') && ...
            ~isempty(meta.original.orientation)
        info.t1Orientation = validateOrientationCode(meta.original.orientation);
    end
    if isfield(meta.original, 'permuteDims') && ...
            ~isempty(meta.original.permuteDims)
        info.permuteDims = validatePermuteDims(meta.original.permuteDims);
    end
    if isfield(meta.original, 'flipDims') && ...
            ~isempty(meta.original.flipDims)
        info.flipDims = validateFlipDims(meta.original.flipDims);
    end
    info.size = double(meta.original.size(:)');
    info.voxelSize = double(meta.original.voxelSize(:)');
    if numel(info.size) ~= 3 || numel(info.voxelSize) ~= 3
        error('acsPlanChamberPlacement:BadSkinMeta', ...
            'Skin meta original.size and original.voxelSize must be length 3.');
    end
    info.capMakerVoxelOrientation = transformOrientationCode( ...
        info.t1Orientation, info.permuteDims, info.flipDims);
end

function requireSkinMetaTransforms(meta)
    ok = isstruct(meta) && isfield(meta, 'print') && ...
        isfield(meta, 'align') && isfield(meta, 'original') && ...
        isfield(meta.print, 'T_world2print') && ...
        isfield(meta.print, 'T_print2world') && ...
        isfield(meta.align, 'R') && ...
        isfield(meta.original, 'vox2world') && ...
        isfield(meta.original, 'voxelSize') && ...
        isfield(meta.original, 'size');
    if ~ok
        error('acsPlanChamberPlacement:BadSkinMeta', ...
            ['Skin meta lacks the capMaker print/original-volume ', ...
             'transform fields needed for chamber exclusions.']);
    end
end

function codeOut = transformOrientationCode(codeIn, permuteDims, flipDims)
    codeIn = validateOrientationCode(codeIn);
    permuteDims = validatePermuteDims(permuteDims);
    flipDims = validateFlipDims(flipDims);

    codeOut = codeIn(permuteDims);
    for dim = 1:3
        if flipDims(dim)
            codeOut(dim) = oppositeOrientationCode(codeOut(dim));
        end
    end
    codeOut = validateOrientationCode(codeOut);
end

function code = oppositeOrientationCode(code)
    switch code
        case 'r'
            code = 'l';
        case 'l'
            code = 'r';
        case 'a'
            code = 'p';
        case 'p'
            code = 'a';
        case 's'
            code = 'i';
        case 'i'
            code = 's';
        otherwise
            error('acsPlanChamberPlacement:BadOrientationCode', ...
                'Unknown orientation code "%s".', code);
    end
end

function code = validateOrientationCode(code)
    code = lower(strtrim(char(code)));
    code = regexprep(code, '[\s,;:_-]+', '');
    if numel(code) ~= 3
        error('acsPlanChamberPlacement:BadOrientationCode', ...
            'Orientation code must have exactly three characters.');
    end
    if any(~ismember(code, 'rlapsi'))
        error('acsPlanChamberPlacement:BadOrientationCode', ...
            'Orientation codes can only use r, l, a, p, s, and i.');
    end

    classes = cell(1, 3);
    for i = 1:3
        classes{i} = orientationClass(code(i));
    end
    expected = {'left-right', 'anterior-posterior', 'superior-inferior'};
    for i = 1:numel(expected)
        if sum(strcmp(classes, expected{i})) ~= 1
            error('acsPlanChamberPlacement:BadOrientationCode', ...
                'Use exactly one left/right, one anterior/posterior, and one superior/inferior direction.');
        end
    end
end

function permuteDims = validatePermuteDims(permuteDims)
    permuteDims = double(permuteDims(:)');
    if numel(permuteDims) ~= 3 || any(sort(permuteDims) ~= [1 2 3])
        error('acsPlanChamberPlacement:BadPermuteDims', ...
            'permuteDims must be a permutation of [1 2 3].');
    end
end

function flipDims = validateFlipDims(flipDims)
    flipDims = logical(flipDims(:)');
    if numel(flipDims) ~= 3
        error('acsPlanChamberPlacement:BadFlipDims', ...
            'flipDims must have three logical values.');
    end
end

function cls = orientationClass(code)
    switch code
        case {'r', 'l'}
            cls = 'left-right';
        case {'a', 'p'}
            cls = 'anterior-posterior';
        case {'s', 'i'}
            cls = 'superior-inferior';
        otherwise
            error('acsPlanChamberPlacement:BadOrientationCode', ...
                'Unknown orientation code "%s".', code);
    end
end

function landmarks = readLandmarks(value)
    if isstruct(value)
        landmarks = value;
        return;
    end
    S = load(char(value));
    landmarks = firstStruct(S);
end

function stereo = chamberStereotaxicSummary(plan, targetWorldMm, landmarks)
    if ~isfield(landmarks, 'frame')
        error('acsPlanChamberPlacement:BadStereotaxicLandmarks', ...
            'stereotaxicLandmarks must contain a frame field.');
    end
    frame = landmarks.frame;
    stereo = struct();
    stereo.frame = frame;
    stereo.contactStereotaxicMm = worldToStereotaxic(plan.contactWorldMm, frame);
    stereo.targetStereotaxicMm = worldToStereotaxic(targetWorldMm, frame);
    stereo.trackDirectionStereotaxic = plan.trackDirectionInWorld * frame.axesWorld;
    stereo.axisOutStereotaxic = plan.axisOutWorld * frame.axesWorld;
end

function coords = worldToStereotaxic(worldMm, frame)
    coords = bsxfun(@minus, worldMm, frame.originWorldMm) * frame.axesWorld;
end

function info = publicSkullInfo(info)
    if isfield(info, 'runtime')
        info = rmfield(info, 'runtime');
    end
end

function saveQcFigure(fig, fileName)
    try
        exportgraphics(fig, fileName, 'Resolution', 200);
    catch
        saveas(fig, fileName);
    end
end

function fileName = defaultQcFile(outputFile, t1File)
    if ~isempty(outputFile)
        [folder, stem] = fileparts(outputFile);
        fileName = fullfile(folder, 'qc', [stem '_qc.png']);
    else
        folder = fileparts(t1File);
        stem = [stripNiftiExtension(getFileName(t1File)) '_chamberPlacement'];
        fileName = fullfile(folder, 'qc', [stem '_qc.png']);
    end
end

function worldMm = voxel1ToWorldMm(vox1, M)
    P = [double(vox1), ones(size(vox1, 1), 1)] * double(M)';
    worldMm = P(:, 1:3);
end

function vox1 = worldMmToVoxel1(worldMm, M)
    P = [double(worldMm), ones(size(worldMm, 1), 1)] / double(M)';
    vox1 = P(:, 1:3);
end

function pointsOut = applyAffineToPoints(M, pointsIn)
    pointsHom = [double(pointsIn), ones(size(pointsIn, 1), 1)];
    pointsHom = (double(M) * pointsHom')';
    pointsOut = pointsHom(:, 1:3);
end

function N = normalizeRows(N)
    mag = sqrt(sum(N .^ 2, 2));
    mag(mag == 0 | ~isfinite(mag)) = 1;
    N = bsxfun(@rdivide, N, mag);
end

function row = normalizeRow(row)
    n = norm(row);
    if n <= eps || ~isfinite(n)
        row = [0 0 1];
    else
        row = row ./ n;
    end
end

function requireFile(fileName, label)
    if isempty(fileName) || exist(fileName, 'file') ~= 2
        error('acsPlanChamberPlacement:MissingFile', ...
            '%s not found: %s', label, fileName);
    end
end

function S = firstStruct(raw)
    preferred = {'outForSave', 'outSaved', 'out', 'landmarks', 'placement'};
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
    error('acsPlanChamberPlacement:NoStructInFile', ...
        'MAT file does not contain a readable struct.');
end

function fileName = getFileName(fileName)
    [~, stem, ext] = fileparts(fileName);
    fileName = [stem ext];
end

function stem = stripExtension(fileName)
    [~, stem] = fileparts(fileName);
end

function stem = stripNiftiExtension(fileName)
    stem = regexprep(fileName, '\.nii(\.gz)?$', '', 'ignorecase');
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

function ensureDir(folder)
    if isempty(folder)
        return;
    end
    if exist(folder, 'dir') ~= 7
        mkdir(folder);
    end
end

function printSummary(out)
    fprintf('\nChamber placement\n');
    fprintf('  target voxel: [%.1f %.1f %.1f]\n', ...
        out.targetVoxel(1), out.targetVoxel(2), out.targetVoxel(3));
    fprintf('  skull contact world mm: [%.2f %.2f %.2f]\n', ...
        out.placement.contactWorldMm(1), out.placement.contactWorldMm(2), ...
        out.placement.contactWorldMm(3));
    fprintf('  target miss from center track: %.3g mm\n', ...
        out.placement.targetLineMissMm);
    fprintf('  track depth to target: %.3g mm\n', ...
        out.placement.depthToTargetMm);
    if isfield(out.placement, 'skullIntersection')
        fprintf('  sampled chamber/skull intersection: %d / %d samples\n', ...
            out.placement.skullIntersection.nInside, ...
            out.placement.skullIntersection.nSamples);
    end
    if isfield(out.exclusion, 'coordinateFrame')
        fprintf('  cap exclusion frame: %s\n', out.exclusion.coordinateFrame);
    end
    if isfield(out.exclusion, 'printFrameMethod')
        fprintf('  cap exclusion transform: %s\n', out.exclusion.printFrameMethod);
    end
    if isfield(out.exclusion, 'contextCollision') && ...
            ~isempty(out.exclusion.contextCollision)
        for i = 1:numel(out.exclusion.contextCollision)
            fprintf('  context overlap %s: %.3g mm^2\n', ...
                out.exclusion.contextCollision(i).name, ...
                out.exclusion.contextCollision(i).overlapAreaMm2);
        end
    end
    if isfield(out.stereotaxic, 'contactStereotaxicMm')
        fprintf('  contact stereotaxic mm: [%.2f %.2f %.2f]\n', ...
            out.stereotaxic.contactStereotaxicMm(1), ...
            out.stereotaxic.contactStereotaxicMm(2), ...
            out.stereotaxic.contactStereotaxicMm(3));
    end
    if ~isempty(out.outputFile)
        fprintf('  output: %s\n', out.outputFile);
    end
end
