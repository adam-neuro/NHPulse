function roots = nhpulseFindLocalDependencyRoots(repoRoot, diagnosticNames)
% NHPULSEFINDLOCALDEPENDENCYROOTS Find dependency folders under repo lib/.
%
% roots = nhpulseFindLocalDependencyRoots(repoRoot, diagnosticNames) searches
% only under repoRoot/lib for diagnostic filenames such as spm_vol.m,
% cvx_setup.m, or vol2mesh.m. It returns the immediate child folder of lib/
% that contains each match, so downloads named spm12-main or iso2mesh-1.9.9
% can be detected without forcing reviewers to rename folders.

    repoRoot = normalizePath(repoRoot);
    if isempty(repoRoot)
        repoRoot = fileparts(mfilename('fullpath'));
    end
    if ischar(diagnosticNames) || isstring(diagnosticNames)
        diagnosticNames = cellstr(diagnosticNames);
    end
    diagnosticNames = cellfun(@char, diagnosticNames(:), ...
        'UniformOutput', false);

    libRoot = fullfile(repoRoot, 'lib');
    roots = {};
    if exist(libRoot, 'dir') ~= 7 || isempty(diagnosticNames)
        return;
    end

    stack = {libRoot};
    seenFolders = {};
    seenRoots = {};
    while ~isempty(stack)
        folderName = stack{end};
        stack(end) = [];
        folderKey = canonicalizeLight(folderName);
        if isempty(folderKey) || any(strcmpi(folderKey, seenFolders))
            continue;
        end
        seenFolders{end + 1} = folderKey; %#ok<AGROW>

        try
            listing = dir(folderName);
        catch
            continue;
        end

        for i = 1:numel(listing)
            item = listing(i);
            if item.isdir
                if shouldSkipFolderName(item.name)
                    continue;
                end
                stack{end + 1} = fullfile(item.folder, item.name); %#ok<AGROW>
            elseif any(strcmpi(item.name, diagnosticNames))
                root = immediateChildUnderRoot(item.folder, libRoot);
                rootKey = canonicalizeLight(root);
                if ~isempty(rootKey) && ~any(strcmpi(rootKey, seenRoots))
                    seenRoots{end + 1} = rootKey; %#ok<AGROW>
                    roots{end + 1, 1} = root; %#ok<AGROW>
                end
            end
        end
    end
end

function root = immediateChildUnderRoot(folderName, libRoot)
    folderName = canonicalizeLight(folderName);
    libRoot = canonicalizeLight(libRoot);
    root = '';
    if isempty(folderName) || isempty(libRoot)
        return;
    end
    folderNorm = strrep(folderName, '\', '/');
    libNorm = strrep(libRoot, '\', '/');
    if strcmpi(folderNorm, libNorm)
        root = libRoot;
        return;
    end
    prefix = [libNorm '/'];
    if ~startsWith(lower(folderNorm), lower(prefix))
        return;
    end
    rel = folderNorm(numel(prefix) + 1:end);
    parts = regexp(rel, '/', 'split');
    if isempty(parts) || isempty(parts{1})
        root = libRoot;
    else
        root = fullfile(libRoot, parts{1});
    end
end

function tf = shouldSkipFolderName(name)
    name = char(name);
    lowerName = lower(name);
    tf = isempty(name) || any(strcmp(name, {'.', '..'})) || ...
        startsWith(name, '.') || strcmpi(name, 'private') || ...
        startsWith(name, '@') || startsWith(name, '+') || ...
        endsWith(lowerName, '.app') || endsWith(lowerName, '.framework') || ...
        endsWith(lowerName, '.dSYM') || strcmpi(name, '__MACOSX');
end

function pathOut = canonicalizeLight(pathOut)
    pathOut = normalizePath(pathOut);
    if isempty(pathOut)
        return;
    end
    pathOut = char(pathOut);
    while numel(pathOut) > 1 && any(pathOut(end) == ['/' '\'])
        pathOut(end) = [];
    end
end

function pathOut = normalizePath(pathOut)
    if isempty(pathOut)
        pathOut = '';
        return;
    end
    pathOut = char(pathOut);
    if startsWith(pathOut, '~')
        homeDir = getenv('HOME');
        if isempty(homeDir)
            homeDir = getenv('USERPROFILE');
        end
        if numel(pathOut) == 1
            pathOut = homeDir;
        elseif pathOut(2) == '/' || pathOut(2) == '\' || pathOut(2) == filesep
            pathOut = fullfile(homeDir, pathOut(3:end));
        end
    end
end
