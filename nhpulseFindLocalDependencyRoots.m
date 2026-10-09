function roots = nhpulseFindLocalDependencyRoots(repoRoot, diagnosticNames)
% NHPULSEFINDLOCALDEPENDENCYROOTS Find dependency folders under repo lib/.
%
% roots = nhpulseFindLocalDependencyRoots(repoRoot, diagnosticNames) searches
% only under repoRoot/lib for diagnostic filenames such as spm_vol.m,
% cvx_setup.m, or vol2mesh.m. Dependency entry-point files are expected at
% the root of an immediate lib/ child (or one wrapper folder below it). This
% bounded search recognizes names such as spm12-main or iso2mesh-1.9.9
% without repeatedly crawling every file in large dependency installations.

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

    seenRoots = {};
    candidates = childFolders(libRoot);
    if folderHasMarker(libRoot, diagnosticNames)
        roots{end + 1, 1} = libRoot;
        seenRoots{end + 1} = canonicalizeLight(libRoot);
    end
    for i = 1:numel(candidates)
        root = candidates{i};
        matchedRoot = root;
        found = folderHasMarker(root, diagnosticNames);
        if ~found
            wrappers = childFolders(root);
            for j = 1:numel(wrappers)
                if folderHasMarker(wrappers{j}, diagnosticNames)
                    found = true;
                    matchedRoot = wrappers{j};
                    break;
                end
            end
        end
        rootKey = canonicalizeLight(matchedRoot);
        if found && ~any(strcmpi(rootKey, seenRoots))
            seenRoots{end + 1} = rootKey; %#ok<AGROW>
            roots{end + 1, 1} = matchedRoot; %#ok<AGROW>
        end
    end
end

function folders = childFolders(parent)
    folders = {};
    try
        listing = dir(parent);
    catch
        return;
    end
    for i = 1:numel(listing)
        if listing(i).isdir && ~shouldSkipFolderName(listing(i).name)
            folders{end + 1, 1} = fullfile( ...
                listing(i).folder, listing(i).name); %#ok<AGROW>
        end
    end
end

function tf = folderHasMarker(folderName, diagnosticNames)
    tf = false;
    for i = 1:numel(diagnosticNames)
        if exist(fullfile(folderName, diagnosticNames{i}), 'file') == 2
            tf = true;
            return;
        end
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
