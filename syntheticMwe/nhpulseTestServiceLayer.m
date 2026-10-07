function report = nhpulseTestServiceLayer(varargin)
% NHPULSETESTSERVICELAYER Test explicit context/artifact service contracts.

    p = inputParser;
    addParameter(p, 'verbose', true, @isBoolLike);
    parse(p, varargin{:});
    verbose = logical(p.Results.verbose);
    root = tempname;
    mkdir(root);
    cleaner = onCleanup(@() removeTestRoot(root));
    anatomyFile = fullfile(root, 'toy_T1.nii');
    segmentationFile = fullfile(root, 'toy_masks.nii');
    writeBytes(anatomyFile, uint8(1:16));
    writeBytes(segmentationFile, uint8(17:32));

    context = nhpulseCreateProjectContext(root, 'service-test', ...
        'runLabel', 'Service layer self-test', ...
        'metadata', struct('subjectId', 'toy'));
    nhpulseRecordArtifact(root, context.runId, 'anatomy', ...
        'nhpulse.anatomy', anatomyFile, 'runLabel', context.runLabel, ...
        'runMetadata', context.metadata, 'fingerprintMode', 'metadata');
    nhpulseRecordArtifact(root, context.runId, 'segmentation', ...
        'nhpulse.segmentation', segmentationFile, ...
        'parentKeys', {'anatomy'}, 'parentRoles', {'sourceAnatomy'}, ...
        'fingerprintMode', 'metadata');
    anatomy = resolveWithoutWorkspace(context, 'anatomy');
    segmentation = resolveWithoutWorkspace(context, 'segmentation');

    writeBytes(anatomyFile, uint8(41:60));
    nhpulseRecordArtifact(root, context.runId, 'anatomy', ...
        'nhpulse.anatomy', anatomyFile, 'runLabel', context.runLabel, ...
        'runMetadata', context.metadata, 'fingerprintMode', 'metadata');
    rejectedStale = false;
    try
        nhpulseResolveArtifact(context, 'segmentation', 'verifyContent', false);
    catch ME
        rejectedStale = strcmp(ME.identifier, ...
            'nhpulseResolveArtifact:ArtifactNotCurrent');
    end
    nhpulseRecordArtifact(root, context.runId, 'segmentation', ...
        'nhpulse.segmentation', segmentationFile, ...
        'parentKeys', {'anatomy'}, 'parentRoles', {'sourceAnatomy'}, ...
        'fingerprintMode', 'metadata');
    refreshed = nhpulseResolveArtifact(context, 'segmentation', ...
        'verifyContent', true);

    scalpFile = fullfile(root, 'toyScalp.mat');
    out = struct('TRskin', struct('Points', zeros(3), ...
        'ConnectivityList', [1 2 3]));
    save(scalpFile, 'out');
    nhpulseRecordArtifact(root, context.runId, 'scalp', ...
        'nhpulse.scalpModel', scalpFile, ...
        'parentKeys', {'segmentation'}, ...
        'parentRoles', {'sourceSegmentation'}, ...
        'fingerprintMode', 'metadata');
    fiducialStage = nhpulseServiceDefineFiducials(context, ...
        struct('scalp', 'scalp'), struct('coordinatesMm', ...
        [0 1 2; -3 0 0; 3 0 0; 0 -2 1], ...
        'showFigures', false, 'saveFigures', false));
    targetStage = nhpulseServiceSelectTarget(context, ...
        struct('anatomy', 'anatomy', 'segmentation', 'segmentation'), ...
        struct('targetVoxel', [4 5 6], 'voxelSizeMm', [1 1 1], ...
        'showFigures', false, 'saveFigures', false));

    report = struct();
    report.contextExplicit = strcmp(context.schema, 'nhpulse.projectContext');
    report.resolvedWithoutBaseWorkspace = ...
        strcmp(anatomy.type, 'nhpulse.anatomy') && ...
        strcmp(segmentation.type, 'nhpulse.segmentation');
    report.rejectedStaleDependency = rejectedStale;
    report.refreshedDependency = strcmp(refreshed.status, 'current');
    report.fiducialServiceRegistered = ...
        strcmp(fiducialStage.artifacts.fiducials.status, 'current');
    report.targetServiceRegistered = ...
        strcmp(targetStage.artifacts.target.status, 'current');
    report.passed = all(cell2mat(struct2cell(report)));
    if verbose
        fprintf('NHPulse service layer self-test: %s\n', ...
            chooseText(report.passed, 'PASS', 'FAIL'));
    end
    if ~report.passed
        error('nhpulseTestServiceLayer:Failed', ...
            'Service layer self-test failed.');
    end
end

function handle = resolveWithoutWorkspace(context, key)
% A function workspace proves resolution does not consume caller variables.
    handle = nhpulseResolveArtifact(context, key, 'verifyContent', true);
end

function writeBytes(fileName, bytes)
    fid = fopen(fileName, 'wb');
    if fid < 0
        error('nhpulseTestServiceLayer:FileOpenFailed', ...
            'Could not write %s.', fileName);
    end
    cleaner = onCleanup(@() fclose(fid));
    fwrite(fid, bytes, 'uint8');
end

function removeTestRoot(folder)
    if exist(folder, 'dir') == 7 && ...
            startsWith(lower(char(folder)), lower(char(tempdir)))
        rmdir(folder, 's');
    end
end

function value = chooseText(condition, yesValue, noValue)
    if condition, value = yesValue; else, value = noValue; end
end

function tf = isBoolLike(x)
    tf = (islogical(x) || isnumeric(x)) && isscalar(x);
end
