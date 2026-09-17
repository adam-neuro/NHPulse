function report = nhpulseTestManifestRecorder(varargin)
% NHPULSETESTMANIFESTRECORDER Fast self-test for generic manifest behavior.
%
% The test creates two tiny artifacts, records their dependency, saves and
% reloads MAT/JSON manifests, and confirms that changing the parent marks both
% the parent and child stale. All files are created under a temporary folder.

    p = inputParser;
    addParameter(p, 'verbose', true, @isBoolLike);
    parse(p, varargin{:});
    verbose = logical(p.Results.verbose);

    testRoot = tempname;
    mkdir(testRoot);
    cleaner = onCleanup(@() removeTestRoot(testRoot));
    parentFile = fullfile(testRoot, 'anatomy.bin');
    childFile = fullfile(testRoot, 'segmentation.bin');
    writeBytes(parentFile, uint8(1:16));
    writeBytes(childFile, uint8(17:32));

    manifest = nhpulseCreateManifest(testRoot, 'Manifest recorder self-test');
    [manifest, parent] = nhpulseRegisterArtifact(manifest, ...
        'nhpulse.testParent', parentFile, 'fingerprintMode', 'metadata');
    [manifest, ~] = nhpulseRegisterArtifact(manifest, ...
        'extension.exampleChild', childFile, ...
        'parents', nhpulseArtifactRef(parent, 'testInput'), ...
        'fingerprintMode', 'metadata');
    files = nhpulseSaveManifest(manifest);

    loadedMat = nhpulseLoadManifest(files.mat);
    loadedJson = nhpulseLoadManifest(files.json);
    beforeMat = nhpulseCheckManifest(loadedMat, ...
        'verifyContent', true, 'verbose', false);
    beforeJson = nhpulseCheckManifest(loadedJson, ...
        'verifyContent', true, 'verbose', false);

    fid = fopen(parentFile, 'ab');
    if fid < 0
        error('nhpulseTestManifestRecorder:FileOpenFailed', ...
            'Could not reopen temporary parent artifact.');
    end
    fileCleaner = onCleanup(@() fclose(fid));
    fwrite(fid, uint8(99), 'uint8');
    clear fileCleaner;
    after = nhpulseCheckManifest(loadedMat, ...
        'verifyContent', true, 'verbose', false);

    report = struct();
    report.passedBeforeMat = beforeMat.passed;
    report.passedBeforeJson = beforeJson.passed;
    report.detectedChangedParent = ~after.checks(1).passed;
    report.propagatedStaleChild = ~after.checks(2).passed;
    report.passed = report.passedBeforeMat && report.passedBeforeJson && ...
        report.detectedChangedParent && report.propagatedStaleChild;
    if verbose
        fprintf('NHPulse manifest recorder self-test: %s\n', ...
            chooseText(report.passed, 'PASS', 'FAIL'));
    end
    if ~report.passed
        error('nhpulseTestManifestRecorder:Failed', ...
            'Manifest recorder self-test failed.');
    end
end

function writeBytes(fileName, bytes)
    fid = fopen(fileName, 'wb');
    if fid < 0
        error('nhpulseTestManifestRecorder:FileOpenFailed', ...
            'Could not create temporary artifact: %s', fileName);
    end
    cleaner = onCleanup(@() fclose(fid));
    fwrite(fid, bytes, 'uint8');
end

function removeTestRoot(folder)
    folder = char(folder);
    tempRoot = char(tempdir);
    if exist(folder, 'dir') == 7 && startsWith(lower(folder), lower(tempRoot))
        rmdir(folder, 's');
    end
end

function tf = isBoolLike(x)
    tf = (islogical(x) || isnumeric(x)) && isscalar(x);
end

function value = chooseText(condition, yesValue, noValue)
    if condition
        value = yesValue;
    else
        value = noValue;
    end
end
