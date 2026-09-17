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
    [status, commit] = system(sprintf('git -C "%s" rev-parse HEAD', ...
        value.nhpulseRoot));
    if status == 0
        value.gitCommit = strtrim(commit);
        [dirtyStatus, dirtyText] = system(sprintf( ...
            'git -C "%s" status --porcelain', value.nhpulseRoot));
        if dirtyStatus == 0
            value.gitDirty = ~isempty(strtrim(dirtyText));
        end
    end
end
