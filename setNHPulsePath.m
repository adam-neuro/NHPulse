function addedPaths = setNHPulsePath(varargin)
% SETNHPULSEPATH Add NHPulse folders to the MATLAB path.
%
% addedPaths = setNHPulsePath() should be run from the top-level NHPulse
% repository directory, or from any session where this file is already on the
% MATLAB path. It adds the repository, NHPulse utilities, capMaker helpers,
% and synthetic MWE utilities.
%
% Name-value options:
%   repoRoot        : top-level NHPulse folder [folder containing this file]
%   configFile      : optional local.paths.json file ['']
%   includeExternal : add MATLAB folders listed in local.paths.json [true]
%   savePath        : persist the path with savepath [false]
%   verbose         : print a short summary [true]

    opts = parseInputs(varargin{:});
    repoRoot = normalizePath(opts.repoRoot);
    if isempty(repoRoot)
        repoRoot = fileparts(mfilename('fullpath'));
    end

    candidatePaths = { ...
        repoRoot, ...
        fullfile(repoRoot, 'acsUtilities'), ...
        fullfile(repoRoot, 'capMaker'), ...
        fullfile(repoRoot, 'capMaker', 'core'), ...
        fullfile(repoRoot, 'capMaker', 'geometry'), ...
        fullfile(repoRoot, 'capMaker', 'wrappers'), ...
        fullfile(repoRoot, 'syntheticMwe'), ...
        fullfile(repoRoot, 'lib', 'spm'), ...
        fullfile(repoRoot, 'lib', 'spm12')};

    recursiveCandidatePaths = { ...
        fullfile(repoRoot, 'lib', 'cvx'), ...
        fullfile(repoRoot, 'lib', 'iso2mesh'), ...
        fullfile(repoRoot, 'lib', 'NIFTI_20110921')};

    addedPaths = {};
    for i = 1:numel(candidatePaths)
        addedPaths = addExistingFolder(candidatePaths{i}, addedPaths);
    end
    for i = 1:numel(recursiveCandidatePaths)
        addedPaths = addExistingFolderTree( ...
            recursiveCandidatePaths{i}, addedPaths);
    end

    if opts.includeExternal && exist('acsPaths', 'file') == 2
        try
            if isempty(opts.configFile)
                P = acsPaths();
            else
                P = acsPaths('configFile', opts.configFile);
            end
            addedPaths = addExternalMatlabPaths(P, addedPaths);
        catch ME
            warning('setNHPulsePath:ExternalPathConfig', ...
                'Could not read local path config for external paths: %s', ME.message);
        end
    end

    if opts.savePath
        saveStatus = savepath;
        if saveStatus ~= 0
            warning('setNHPulsePath:SavePathFailed', ...
                'MATLAB could not save the updated path permanently.');
        end
    end

    if opts.verbose
        fprintf('\nNHPulse path configured\n');
        fprintf('  repo: %s\n', repoRoot);
        fprintf('  folders added/confirmed: %d\n\n', numel(addedPaths));
    end
end

function opts = parseInputs(varargin)
    p = inputParser;
    p.FunctionName = 'setNHPulsePath';
    addParameter(p, 'repoRoot', fileparts(mfilename('fullpath')), ...
        @(x) ischar(x) || isstring(x));
    addParameter(p, 'configFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'includeExternal', true, ...
        @(x) (islogical(x) || isnumeric(x)) && isscalar(x));
    addParameter(p, 'savePath', false, ...
        @(x) (islogical(x) || isnumeric(x)) && isscalar(x));
    addParameter(p, 'verbose', true, ...
        @(x) (islogical(x) || isnumeric(x)) && isscalar(x));
    parse(p, varargin{:});

    opts = p.Results;
    opts.repoRoot = normalizePath(opts.repoRoot);
    opts.configFile = normalizePath(opts.configFile);
    opts.includeExternal = logical(opts.includeExternal);
    opts.savePath = logical(opts.savePath);
    opts.verbose = logical(opts.verbose);
end

function addedPaths = addExternalMatlabPaths(P, addedPaths)
    topLevelFields = {'spmPath', 'inpolyhedronPath'};
    for i = 1:numel(topLevelFields)
        fieldName = topLevelFields{i};
        if isfield(P, fieldName)
            addedPaths = addPathOrContainingFolder(P.(fieldName), addedPaths);
        end
    end

    recursiveFields = {'iso2meshPath', 'cvxPath', 'niftiPath'};
    for i = 1:numel(recursiveFields)
        fieldName = recursiveFields{i};
        if isfield(P, fieldName)
            addedPaths = addFolderOrContainingFolderTree( ...
                P.(fieldName), addedPaths);
        end
    end

    if isfield(P, 'extraMatlabPaths')
        extraPaths = P.extraMatlabPaths;
        if ischar(extraPaths) || isstring(extraPaths)
            extraPaths = cellstr(extraPaths);
        end
        if iscell(extraPaths)
            for i = 1:numel(extraPaths)
                addedPaths = addPathOrContainingFolder(extraPaths{i}, addedPaths);
            end
        end
    end
end

function addedPaths = addFolderOrContainingFolderTree(pathIn, addedPaths)
    pathIn = normalizePath(pathIn);
    if isempty(pathIn)
        return;
    end
    if exist(pathIn, 'dir') == 7
        addedPaths = addExistingFolderTree(pathIn, addedPaths);
    elseif exist(pathIn, 'file') == 2
        addedPaths = addExistingFolderTree(fileparts(pathIn), addedPaths);
    end
end

function addedPaths = addPathOrContainingFolder(pathIn, addedPaths)
    pathIn = normalizePath(pathIn);
    if isempty(pathIn)
        return;
    end
    if exist(pathIn, 'dir') == 7
        addedPaths = addExistingFolder(pathIn, addedPaths);
    elseif exist(pathIn, 'file') == 2
        addedPaths = addExistingFolder(fileparts(pathIn), addedPaths);
    end
end

function addedPaths = addExistingFolder(folderName, addedPaths)
    folderName = normalizePath(folderName);
    if isempty(folderName) || exist(folderName, 'dir') ~= 7
        return;
    end
    if ~isOnPath(folderName)
        addpath(folderName, '-begin');
    end
    addedPaths{end + 1, 1} = folderName; %#ok<AGROW>
end

function addedPaths = addExistingFolderTree(rootFolder, addedPaths)
    rootFolder = normalizePath(rootFolder);
    if isempty(rootFolder) || exist(rootFolder, 'dir') ~= 7
        return;
    end
    stack = {rootFolder};
    seen = {};
    while ~isempty(stack)
        folderName = stack{end};
        stack(end) = [];
        folderKey = canonicalizeLight(folderName);
        if isempty(folderKey) || any(strcmpi(folderKey, seen))
            continue;
        end
        seen{end + 1, 1} = folderKey; %#ok<AGROW>
        if exist(folderName, 'dir') ~= 7
            continue;
        end
        addedPaths = addExistingFolder(folderName, addedPaths);
        try
            kids = dir(folderName);
        catch
            continue;
        end
        for i = 1:numel(kids)
            if ~kids(i).isdir || shouldSkipFolderName(kids(i).name)
                continue;
            end
            stack{end + 1, 1} = fullfile(folderName, kids(i).name); %#ok<AGROW>
        end
    end
end

function tf = shouldSkipFolderName(name)
    name = char(name);
    lowerName = lower(name);
    tf = isempty(name) || any(strcmp(name, {'.', '..'})) || ...
        startsWith(name, '.') || strcmpi(name, 'private') || ...
        endsWith(lowerName, '.app') || endsWith(lowerName, '.framework') || ...
        endsWith(lowerName, '.dSYM') || strcmpi(name, '__MACOSX');
end

function tf = isOnPath(folderName)
    folderName = canonicalizeLight(folderName);
    pathParts = strsplit(path, pathsep);
    tf = false;
    for i = 1:numel(pathParts)
        thisPath = canonicalizeLight(pathParts{i});
        if isempty(thisPath)
            continue;
        end
        if strcmpi(folderName, thisPath)
            tf = true;
            return;
        end
    end
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
