function report = nhpulseVerifySyntheticWalkthrough(outputDir, varargin)
% NHPULSEVERIFYSYNTHETICWALKTHROUGH Check products from exampleWalkthrough.m.
%
% report = nhpulseVerifySyntheticWalkthrough() checks the default synthetic
% walkthrough output folder.
%
% report = nhpulseVerifySyntheticWalkthrough(outputDir) checks a specific
% folder. The function does not rerun expensive steps; it only verifies that
% expected product classes exist and that key MAT files can be loaded.
%
% Name-value options:
%   subjectId            : synthetic subject id ['nhpulseSyntheticDemo']
%   requireFinalCap      : require final dual-material STL products [true]
%   requireRealLeadField : require at least one ROAST lead-field result [false]
%   verbose              : print a reviewer-friendly report [true]

    parameterNames = {'subjectId', 'requireFinalCap', ...
        'requireRealLeadField', 'verbose'};

    if nargin < 1 || isempty(outputDir)
        cfg = nhpulseExampleConfig('syntheticReviewer');
        outputDir = cfg.outputDir;
    elseif isNameValueKey(outputDir, parameterNames)
        varargin = [{outputDir}, varargin];
        cfg = nhpulseExampleConfig('syntheticReviewer');
        outputDir = cfg.outputDir;
    end

    opts = parseInputs(varargin{:});
    outputDir = char(outputDir);

    checks = repmat(emptyCheck(), 0, 1);
    checks(end + 1) = checkFile('Synthetic T1 NIfTI', ...
        fullfile(outputDir, [opts.subjectId '_T1.nii']), true);
    checks(end + 1) = checkFile('Synthetic ROAST hard-label mask', ...
        fullfile(outputDir, [opts.subjectId '_T1_T1orT2_SPM_masks.nii']), true);
    checks(end + 1) = checkFile('Synthetic data report JSON', ...
        fullfile(outputDir, [opts.subjectId '_syntheticReport.json']), true);
    checks(end + 1) = checkMatFile('ROAST scalp skin cache', ...
        fullfile(outputDir, [opts.subjectId '_roastScalpSkinMesh.mat']), true, ...
        {'TRstableHead'});
    checks(end + 1) = checkMatFile('Printer-bed scalp cache', ...
        fullfile(outputDir, [opts.subjectId '_printerBedSkinMesh.mat']), true, ...
        {'TRskin'});
    checks(end + 1) = checkMatFile('Ear/painted exclusion file', ...
        fullfile(outputDir, [opts.subjectId '_printerBedEarExclusions.mat']), true, ...
        {});
    checks(end + 1) = checkMatFile('Headpost placement file', ...
        fullfile(outputDir, [opts.subjectId '_headpostPlacement.mat']), true, ...
        {});
    checks(end + 1) = checkMatFile('Headpost keepout file', ...
        fullfile(outputDir, [opts.subjectId '_headpostKeepout.mat']), true, ...
        {});
    checks(end + 1) = checkMatFile('Target voxel selection', ...
        fullfile(outputDir, [opts.subjectId '_demoTargetVoxel.mat']), true, ...
        {'targetSelection'});
    checks(end + 1) = checkPattern('Fit-check PLA STL', outputDir, ...
        fullfile('fitChecks', '**', '*.stl'), true);
    checks(end + 1) = checkPattern('Initial/custom location report', outputDir, ...
        ['**' filesep '*customLocations*_report.mat'], true);
    checks(end + 1) = checkPattern('tES/EEG combined layout report', outputDir, ...
        ['**' filesep '*tesEeg*customLocations*_report.mat'], true);
    checks(end + 1) = checkPattern('Manufacturing report MAT', outputDir, ...
        fullfile('manufacturing', '**', '*_report.mat'), opts.requireFinalCap);
    checks(end + 1) = checkPattern('Final TPE STL', outputDir, ...
        fullfile('manufacturing', '**', '*tpe*.stl'), opts.requireFinalCap);
    checks(end + 1) = checkPattern('Final PLA STL', outputDir, ...
        fullfile('manufacturing', '**', '*pla*.stl'), opts.requireFinalCap);
    checks(end + 1) = checkPattern('ROAST lead-field result', outputDir, ...
        ['**' filesep '*roastResult.mat'], opts.requireRealLeadField);

    required = [checks.required];
    passed = [checks.passed];

    report = struct();
    report.createdOn = char(datetime('now'));
    report.type = 'nhpulseSyntheticWalkthroughVerification';
    report.outputDir = outputDir;
    report.subjectId = opts.subjectId;
    report.passed = all(passed(required));
    report.nRequired = nnz(required);
    report.nRequiredPassed = nnz(required & passed);
    report.nOptionalPassed = nnz(~required & passed);
    report.checks = checks;

    if opts.verbose
        printReport(report);
    end

    if ~report.passed
        missing = checks(required & ~passed);
        names = strjoin({missing.name}, ', ');
        error('nhpulseVerifySyntheticWalkthrough:MissingProducts', ...
            'Synthetic walkthrough verification failed. Missing required product(s): %s', names);
    end
end

function opts = parseInputs(varargin)
    p = inputParser;
    p.FunctionName = 'nhpulseVerifySyntheticWalkthrough';
    addParameter(p, 'subjectId', 'nhpulseSyntheticDemo', ...
        @(x) ischar(x) || isstring(x));
    addParameter(p, 'requireFinalCap', true, @isBoolLike);
    addParameter(p, 'requireRealLeadField', false, @isBoolLike);
    addParameter(p, 'verbose', true, @isBoolLike);
    parse(p, varargin{:});
    opts = p.Results;
    opts.subjectId = char(opts.subjectId);
    opts.requireFinalCap = logical(opts.requireFinalCap);
    opts.requireRealLeadField = logical(opts.requireRealLeadField);
    opts.verbose = logical(opts.verbose);
end

function check = emptyCheck()
    check = struct('name', '', 'required', false, 'passed', false, ...
        'path', '', 'pattern', '', 'count', 0, 'message', '');
end

function check = checkFile(name, fileName, required)
    check = emptyCheck();
    check.name = name;
    check.required = logical(required);
    check.path = char(fileName);
    check.passed = exist(fileName, 'file') == 2;
    if check.passed
        info = dir(fileName);
        check.count = 1;
        check.message = sprintf('found (%s)', formatBytes(info.bytes));
    else
        check.message = 'not found';
    end
end

function check = checkMatFile(name, fileName, required, expectedVariables)
    check = checkFile(name, fileName, required);
    if ~check.passed
        return;
    end
    try
        info = whos('-file', fileName);
        present = {info.name};
        missing = setdiff(expectedVariables, present);
        if isempty(missing)
            check.message = sprintf('loadable MAT file; variables: %s', ...
                strjoin(present, ', '));
        else
            check.passed = false;
            check.message = sprintf('MAT file is missing variable(s): %s', ...
                strjoin(missing, ', '));
        end
    catch ME
        check.passed = false;
        check.message = sprintf('MAT file could not be inspected: %s', ME.message);
    end
end

function check = checkPattern(name, rootDir, pattern, required)
    check = emptyCheck();
    check.name = name;
    check.required = logical(required);
    check.path = char(rootDir);
    check.pattern = pattern;
    files = dir(fullfile(rootDir, pattern));
    files = files(~[files.isdir]);
    check.count = numel(files);
    check.passed = check.count > 0;
    if check.passed
        [~, idx] = max([files.datenum]);
        check.path = fullfile(files(idx).folder, files(idx).name);
        check.message = sprintf('found %d file(s); newest: %s', ...
            check.count, check.path);
    else
        check.message = sprintf('no files matched %s', fullfile(rootDir, pattern));
    end
end

function tf = isBoolLike(x)
    tf = (islogical(x) || isnumeric(x)) && isscalar(x);
end

function tf = isNameValueKey(value, parameterNames)
    tf = (ischar(value) || isstring(value)) && ...
        any(strcmpi(char(value), parameterNames));
end

function txt = formatBytes(nBytes)
    nBytes = double(nBytes);
    units = {'B', 'KB', 'MB', 'GB'};
    idx = 1;
    while nBytes >= 1024 && idx < numel(units)
        nBytes = nBytes / 1024;
        idx = idx + 1;
    end
    txt = sprintf('%.3g %s', nBytes, units{idx});
end

function printReport(report)
    fprintf('\nNHPulse synthetic walkthrough verification\n');
    fprintf('  output: %s\n', report.outputDir);
    fprintf('  required checks: %d/%d passed\n\n', ...
        report.nRequiredPassed, report.nRequired);

    for i = 1:numel(report.checks)
        item = report.checks(i);
        status = 'FAIL';
        if item.passed
            status = 'OK';
        elseif ~item.required
            status = 'skip';
        end
        req = 'optional';
        if item.required
            req = 'required';
        end
        fprintf('  %-8s %-9s %s\n', status, req, item.name);
        fprintf('           %s\n', item.message);
    end
    fprintf('\n');
end
