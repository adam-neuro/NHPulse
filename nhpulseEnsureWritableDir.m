function nhpulseEnsureWritableDir(folder, context)
% NHPULSEENSUREWRITABLEDIR Create and verify a writable output folder.
%
% nhpulseEnsureWritableDir(folder) creates folder if needed and checks that
% MATLAB can write a tiny temporary file there. The error message is written
% for first-run setup, where a stale local.paths.json can otherwise produce
% opaque operating-system errors such as "Read-only file system".

    if nargin < 2 || isempty(context)
        context = 'NHPulse output';
    end
    folder = char(folder);
    if isempty(folder)
        error('nhpulseEnsureWritableDir:EmptyFolder', ...
            '%s folder is empty. Run nhpulseConfigureLocalPaths or pass an explicit output folder.', ...
            char(context));
    end

    try
        if exist(folder, 'dir') ~= 7
            mkdir(folder);
        end
    catch ME
        error('nhpulseEnsureWritableDir:CannotCreate', ...
            ['Could not create %s folder:\n  %s\n\n%s\n\n', ...
             'Try running:\n  P = nhpulseConfigureLocalPaths(''useGui'', true)\n', ...
             'and choose an outputRoot in a writable location. Original error: %s'], ...
            char(context), folder, pathRootHint(folder), ME.message);
    end

    probe = tempname(folder);
    fid = fopen(probe, 'w');
    if fid < 0
        error('nhpulseEnsureWritableDir:NotWritable', ...
            ['%s folder exists but MATLAB cannot write there:\n  %s\n\n%s\n\n', ...
             'Choose a different outputRoot with:\n  P = nhpulseConfigureLocalPaths(''useGui'', true)'], ...
            char(context), folder, pathRootHint(folder));
    end
    cleaner = onCleanup(@() cleanupProbe(fid, probe)); %#ok<NASGU>
    fprintf(fid, 'NHPulse writable-folder probe\n');
end

function cleanupProbe(fid, probe)
    try
        fclose(fid);
    catch
    end
    try
        if exist(probe, 'file') == 2
            delete(probe);
        end
    catch
    end
end

function msg = pathRootHint(folder)
    folder = char(folder);
    homeDir = getenv('HOME');
    if isempty(homeDir)
        homeDir = getenv('USERPROFILE');
    end
    inHome = ~isempty(homeDir) && startsWith(folder, homeDir);
    inTmp = startsWith(folder, tempdir);
    if startsWith(folder, filesep) && ~inHome && ~inTmp
        msg = ['The folder appears to be rooted near the filesystem top level. ', ...
            'On macOS/Linux, paths like /outputs or /syntheticMwe are often read-only.'];
    elseif ispc && numel(folder) >= 3 && folder(2) == ':' && folder(3) == filesep
        msg = ['The folder is on a drive root. If this is not intentional, ', ...
            'check outputRoot in local.paths.json.'];
    else
        msg = ['Check outputRoot in local.paths.json, ACS_OUTPUT_ROOT, or ', ...
            'the explicit output folder passed to the function.'];
    end
end
