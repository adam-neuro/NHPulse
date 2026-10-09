function report = nhpulseTestApplicationShell(varargin)
% NHPULSETESTAPPLICATIONSHELL Smoke-test the hidden application shell.

    p = inputParser;
    addParameter(p, 'verbose', true, @isBoolLike);
    parse(p, varargin{:});
    root = tempname;
    mkdir(root);
    cleaner = onCleanup(@() removeTestRoot(root));
    runRoot = fullfile(root, 'outputs', 'SubjectA');
    mkdir(runRoot);
    anatomyFile = fullfile(runRoot, 'toy_T1.nii');
    writeBytes(anatomyFile, uint8(1:24));
    nhpulseRecordArtifact(runRoot, 'subject-a-run', 'anatomy', ...
        'nhpulse.anatomy', anatomyFile, ...
        'runLabel', 'Subject A test run', ...
        'runMetadata', struct('subjectId', 'SubjectA'), ...
        'fingerprintMode', 'metadata');
    segmentationFile = fullfile(runRoot, 'toy_masks.nii');
    writeBytes(segmentationFile, uint8(25:30));
    nhpulseRecordArtifact(runRoot, 'subject-a-run', 'segmentation', ...
        'nhpulse.segmentation', segmentationFile, ...
        'parentKeys', {'anatomy'}, 'fingerprintMode', 'metadata');
    legacyRoot = fullfile(root, 'outputs', 'LegacySubject');
    mkdir(legacyRoot);
    legacyFile = fullfile(legacyRoot, 'LegacySubject_T1.nii');
    writeBytes(legacyFile, uint8(31:54));

    app = nhpulseApp(root, 'verifyContent', false, ...
        'discoverLegacy', 'always', 'visible', 'off');
    figureCleaner = onCleanup(@() closeIfValid(app.Figure));
    drawnow;
    data = app.ArtifactTable.Data;
    report = struct();
    report.figureCreated = isgraphics(app.Figure, 'figure');
    report.projectSelected = strcmp(app.ProjectField.Value, root);
    report.nestedManifestRootPreserved = strcmp( ...
        app.Figure.UserData.project.runs(1).manifest.projectRoot, runRoot);
    report.subjectListed = any(strcmp(app.SubjectDropDown.Items, 'SubjectA'));
    report.legacySubjectListed = any(strcmp(app.SubjectDropDown.Items, ...
        'LegacySubject'));
    report.runListed = any(contains(app.RunDropDown.Items, 'subject-a-run'));
    report.workflowPresent = numel(app.WorkflowList.Items) >= 10;
    report.artifactShown = height(data) == 2 && ...
        all(strcmp(data.Status, 'current'));
    app.SubjectDropDown.Value = 'LegacySubject';
    app.SubjectDropDown.ValueChangedFcn(app.SubjectDropDown, []);
    legacyData = app.ArtifactTable.Data;
    report.legacyArtifactShown = height(legacyData) == 1 && ...
        strcmp(legacyData.Status{1}, 'unregistered');
    report.importEnabled = strcmp(app.ImportButton.Enable, 'on');
    app.ImportButton.ButtonPushedFcn(app.ImportButton, []);
    report.legacyImportCreatedRun = ...
        numel(app.Figure.UserData.project.runs) == 2 && ...
        isempty(app.Figure.UserData.project.legacyArtifacts);
    report.passed = all(cell2mat(struct2cell(report)));
    if logical(p.Results.verbose)
        fprintf('NHPulse application shell self-test: %s\n', ...
            chooseText(report.passed, 'PASS', 'FAIL'));
    end
    if ~report.passed
        error('nhpulseTestApplicationShell:Failed', ...
            'Application shell self-test failed.');
    end
    clear figureCleaner cleaner
end

function writeBytes(fileName, bytes)
    fid = fopen(fileName, 'wb');
    if fid < 0
        error('nhpulseTestApplicationShell:FileOpenFailed', ...
            'Could not write %s.', fileName);
    end
    cleaner = onCleanup(@() fclose(fid));
    fwrite(fid, bytes, 'uint8');
end

function closeIfValid(fig)
    if isgraphics(fig), close(fig); end
end

function removeTestRoot(folder)
    if exist(folder, 'dir') == 7 && startsWith(lower(folder), lower(tempdir))
        rmdir(folder, 's');
    end
end

function value = chooseText(condition, yesValue, noValue)
    if condition, value = yesValue; else, value = noValue; end
end

function tf = isBoolLike(x)
    tf = (islogical(x) || isnumeric(x)) && isscalar(x);
end
