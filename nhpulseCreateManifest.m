function manifest = nhpulseCreateManifest(projectRoot, runLabel, varargin)
% NHPULSECREATEMANIFEST Create an empty, non-invasive NHPulse run manifest.
%
% manifest = nhpulseCreateManifest(projectRoot, runLabel) records where an
% existing pipeline writes its products. It does not move or rename files.
%
% Name-value options:
%   runId    : explicit run identifier [[] = generated]
%   metadata : JSON-compatible run metadata [struct()]

    if nargin < 1 || isempty(projectRoot)
        projectRoot = pwd;
    end
    if nargin < 2 || isempty(runLabel)
        runLabel = 'NHPulse run';
    end
    p = inputParser;
    p.FunctionName = 'nhpulseCreateManifest';
    addParameter(p, 'runId', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'metadata', struct(), @isstruct);
    parse(p, varargin{:});

    projectRoot = nhpulseManifestInternal('canonicalPath', projectRoot);
    if exist(projectRoot, 'dir') ~= 7
        error('nhpulseCreateManifest:ProjectRootMissing', ...
            'Project/output root does not exist: %s', projectRoot);
    end
    runId = char(p.Results.runId);
    if isempty(runId)
        runId = nhpulseManifestInternal('newId', 'run');
    end

    manifest = struct();
    manifest.schema = 'nhpulse.runManifest';
    manifest.schemaVersion = 1;
    manifest.runId = runId;
    manifest.runLabel = char(runLabel);
    manifest.createdOn = char(datetime('now', 'TimeZone', 'local', 'Format', ...
        'yyyy-MM-dd''T''HH:mm:ssXXX'));
    manifest.projectRoot = projectRoot;
    manifest.metadata = p.Results.metadata;
    manifest.environment = localEnvironment();
    emptyArtifact = nhpulseManifestInternal('emptyArtifact');
    manifest.artifacts = repmat(emptyArtifact, 0, 1);
end

function value = localEnvironment()
    value = struct();
    value.matlabVersion = version;
    value.matlabRelease = version('-release');
    value.computer = computer;
    value.operatingSystem = system_dependent('getos');
    value.nhpulseRoot = fileparts(mfilename('fullpath'));
    value.gitCommit = '';
    value.gitDirty = [];
    value.gitDirtyScope = 'not-checked-no-subprocess';
    value.gitCommit = readGitCommitWithoutProcess(value.nhpulseRoot);
end

function commit = readGitCommitWithoutProcess(repoRoot)
% Read Git metadata directly so manifest checkpoints cannot block on Git.
    commit = '';
    gitPath = fullfile(repoRoot, '.git');
    if exist(gitPath, 'file') == 2
        pointer = strtrim(readSmallTextFile(gitPath));
        prefix = 'gitdir:';
        if ~startsWith(lower(pointer), prefix)
            return;
        end
        gitPath = strtrim(pointer((numel(prefix) + 1):end));
        if ~isAbsolutePath(gitPath)
            gitPath = fullfile(repoRoot, gitPath);
        end
    elseif exist(gitPath, 'dir') ~= 7
        return;
    end

    headFile = fullfile(gitPath, 'HEAD');
    if exist(headFile, 'file') ~= 2
        return;
    end
    head = strtrim(readSmallTextFile(headFile));
    if ~startsWith(head, 'ref:')
        commit = head;
        return;
    end

    refName = strtrim(head(5:end));
    refFile = fullfile(gitPath, strrep(refName, '/', filesep));
    if exist(refFile, 'file') == 2
        commit = strtrim(readSmallTextFile(refFile));
        return;
    end

    packedFile = fullfile(gitPath, 'packed-refs');
    if exist(packedFile, 'file') ~= 2
        return;
    end
    lines = regexp(readSmallTextFile(packedFile), '\r?\n', 'split');
    suffix = [' ' refName];
    for i = 1:numel(lines)
        line = strtrim(lines{i});
        if ~isempty(line) && line(1) ~= '#' && endsWith(line, suffix)
            commit = strtrim(line(1:(end - numel(suffix))));
            return;
        end
    end
end

function text = readSmallTextFile(fileName)
    fid = fopen(fileName, 'rt');
    if fid < 0
        text = '';
        return;
    end
    cleaner = onCleanup(@() fclose(fid));
    text = fread(fid, 64 * 1024, '*char')';
end

function tf = isAbsolutePath(value)
    if ispc
        tf = ~isempty(regexp(value, '^[A-Za-z]:[\\/]|^\\\\', 'once'));
    else
        tf = startsWith(value, filesep);
    end
end
