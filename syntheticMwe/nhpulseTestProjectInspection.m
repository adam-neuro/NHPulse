function report = nhpulseTestProjectInspection(varargin)
% NHPULSETESTPROJECTINSPECTION Fast project hierarchy/inspection self-test.

    p = inputParser;
    addParameter(p, 'verbose', true, @isBoolLike);
    parse(p, varargin{:});
    verbose = logical(p.Results.verbose);

    testRoot = tempname;
    mkdir(testRoot);
    mkdir(fullfile(testRoot, 'outputs'));
    cleaner = onCleanup(@() removeTestRoot(testRoot));
    anatomyFile = fullfile(testRoot, 'outputs', 'toy_T1.nii');
    segmentationFile = fullfile(testRoot, 'outputs', 'toy_masks.nii');
    stlFile = fullfile(testRoot, 'outputs', 'toy_TPE.stl');
    writeBytes(anatomyFile, uint8(1:16));
    writeBytes(segmentationFile, uint8(17:32));
    writeBytes(stlFile, uint8(33:48));

    manifest = nhpulseCreateManifest(testRoot, 'Project inspection test');
    [manifest, anatomy] = nhpulseRegisterArtifact(manifest, ...
        'nhpulse.anatomy', anatomyFile, 'fingerprintMode', 'metadata');
    [manifest, ~] = nhpulseRegisterArtifact(manifest, ...
        'nhpulse.segmentation', segmentationFile, ...
        'parents', nhpulseArtifactRef(anatomy, 'sourceAnatomy'), ...
        'fingerprintMode', 'metadata');
    nhpulseSaveManifest(manifest);

    project = nhpulseOpenProject(testRoot, 'verbose', false);
    status = nhpulseProjectStatus(project, 'verbose', false);
    dryRun = nhpulseImportLegacyArtifacts(project, ...
        'dryRun', true, 'verbose', false);
    imported = nhpulseImportLegacyArtifacts(project, ...
        'selection', {'nhpulse.manufacturingStl'}, ...
        'dryRun', false, 'fingerprintMode', 'metadata', 'verbose', false);
    importedProject = nhpulseOpenProject(testRoot, 'verbose', false);

    fid = fopen(anatomyFile, 'ab');
    if fid < 0
        error('nhpulseTestProjectInspection:FileOpenFailed', ...
            'Could not reopen temporary anatomy artifact.');
    end
    fileCleaner = onCleanup(@() fclose(fid));
    fwrite(fid, uint8(99), 'uint8');
    clear fileCleaner;
    staleProject = nhpulseOpenProject(testRoot, 'verbose', false);
    staleStatus = nhpulseProjectStatus(staleProject, 'verbose', false);

    incompatibleRoot = fullfile(testRoot, 'incompatible');
    mkdir(incompatibleRoot);
    parentFile = fullfile(incompatibleRoot, 'parent_masks.nii');
    childFile = fullfile(incompatibleRoot, 'child_T1.nii');
    writeBytes(parentFile, uint8(1));
    writeBytes(childFile, uint8(2));
    badManifest = nhpulseCreateManifest(incompatibleRoot, 'Bad hierarchy');
    [badManifest, parent] = nhpulseRegisterArtifact(badManifest, ...
        'nhpulse.segmentation', parentFile, 'fingerprintMode', 'metadata');
    [badManifest, ~] = nhpulseRegisterArtifact(badManifest, ...
        'nhpulse.anatomy', childFile, ...
        'parents', nhpulseArtifactRef(parent, 'invalidParent'), ...
        'fingerprintMode', 'metadata');
    badCheck = nhpulseCheckManifest(badManifest, ...
        'verifyContent', true, 'verbose', false);

    report = struct();
    report.openedManifest = project.summary.runCount == 1;
    report.currentArtifacts = nnz(strcmp(status.artifacts.Status, 'current')) == 2;
    report.foundLegacyStl = isscalar(project.legacyArtifacts) && ...
        strcmp(project.legacyArtifacts(1).type, 'nhpulse.manufacturingStl');
    report.importDryRun = dryRun.dryRun && isempty(fieldnames(dryRun.manifest));
    report.importWroteManifest = exist(imported.manifestFiles.mat, 'file') == 2 && ...
        importedProject.summary.registeredCount == 3 && ...
        importedProject.summary.unregisteredCount == 0;
    report.detectedStaleChain = ...
        nnz(strcmp(staleStatus.artifacts.Status, 'stale')) == 2;
    report.detectedIncompatibleParent = ...
        strcmp(badCheck.checks(2).status, 'incompatible');
    report.passed = all(cell2mat(struct2cell(report)));
    if verbose
        fprintf('NHPulse project inspection self-test: %s\n', ...
            chooseText(report.passed, 'PASS', 'FAIL'));
    end
    if ~report.passed
        error('nhpulseTestProjectInspection:Failed', ...
            'Project inspection self-test failed.');
    end
end

function writeBytes(fileName, bytes)
    fid = fopen(fileName, 'wb');
    if fid < 0
        error('nhpulseTestProjectInspection:FileOpenFailed', ...
            'Could not create temporary artifact: %s', fileName);
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
    if condition
        value = yesValue;
    else
        value = noValue;
    end
end

function tf = isBoolLike(x)
    tf = (islogical(x) || isnumeric(x)) && isscalar(x);
end
