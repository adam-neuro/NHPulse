function handle = nhpulseResolveArtifact(context, reference, varargin)
% NHPULSERESOLVEARTIFACT Resolve one explicit artifact in a project run.
%
% handle = nhpulseResolveArtifact(context, keyOrArtifact) accepts an artifact
% key/ID, a registered manifest artifact, or a prior artifact handle.
%
% Name-value options:
%   expectedType  : accepted type or cell array [{}]
%   requireCurrent: reject stale/missing/incompatible inputs [true]
%   verifyContent : recompute fingerprints [true]

    validateContext(context);
    p = inputParser;
    addParameter(p, 'expectedType', {}, ...
        @(x) isempty(x) || ischar(x) || isstring(x) || iscell(x));
    addParameter(p, 'requireCurrent', true, @isBoolLike);
    addParameter(p, 'verifyContent', true, @isBoolLike);
    parse(p, varargin{:});
    if exist(context.manifestFile, 'file') ~= 2
        error('nhpulseResolveArtifact:ManifestMissing', ...
            'Run manifest does not exist yet: %s', context.manifestFile);
    end
    manifest = nhpulseLoadManifest(context.manifestFile);
    report = nhpulseCheckManifest(manifest, ...
        'verifyContent', p.Results.verifyContent, 'verbose', false);
    idx = resolveIndex(manifest, reference);
    artifact = manifest.artifacts(idx);
    check = report.checks(idx);
    expected = normalizeCellstr(p.Results.expectedType);
    if ~isempty(expected) && ~any(strcmp(expected, char(artifact.type)))
        error('nhpulseResolveArtifact:UnexpectedType', ...
            'Artifact %s has type %s; expected %s.', artifact.artifactId, ...
            artifact.type, strjoin(expected, ' or '));
    end
    if logical(p.Results.requireCurrent) && ~strcmp(check.status, 'current')
        error('nhpulseResolveArtifact:ArtifactNotCurrent', ...
            'Artifact %s is %s: %s', artifact.artifactId, check.status, ...
            strjoin(check.messages, '; '));
    end
    handle = struct('schema', 'nhpulse.artifactHandle', ...
        'schemaVersion', 1, 'projectRoot', context.projectRoot, ...
        'runId', context.runId, 'artifactId', artifact.artifactId, ...
        'artifactKey', artifactKey(artifact), 'type', artifact.type, ...
        'label', artifact.label, 'path', check.path, ...
        'status', check.status, 'artifact', artifact);
end

function idx = resolveIndex(manifest, reference)
    if ischar(reference) || isstring(reference)
        key = char(reference);
    elseif isstruct(reference) && isfield(reference, 'artifactId')
        key = char(reference.artifactId);
    elseif isstruct(reference) && isfield(reference, 'artifactKey')
        key = char(reference.artifactKey);
    else
        error('nhpulseResolveArtifact:BadReference', ...
            'Artifact reference must be a key/ID, artifact, or artifact handle.');
    end
    idx = find(strcmp({manifest.artifacts.artifactId}, key), 1);
    if isempty(idx)
        for i = 1:numel(manifest.artifacts)
            if strcmp(artifactKey(manifest.artifacts(i)), key)
                idx = i;
                break;
            end
        end
    end
    if isempty(idx)
        error('nhpulseResolveArtifact:NotFound', ...
            'Artifact key/ID "%s" was not found in run %s.', key, manifest.runId);
    end
end

function value = artifactKey(artifact)
    value = char(artifact.artifactId);
    if isstruct(artifact.metadata) && isfield(artifact.metadata, 'artifactKey')
        value = char(artifact.metadata.artifactKey);
    end
end

function values = normalizeCellstr(value)
    if isempty(value)
        values = {};
    elseif ischar(value) || isstring(value)
        values = cellstr(value);
    else
        values = value(:).';
    end
end

function validateContext(context)
    if ~isstruct(context) || ~isfield(context, 'schema') || ...
            ~strcmp(context.schema, 'nhpulse.projectContext') || ...
            ~isfield(context, 'manifestFile')
        error('nhpulseResolveArtifact:BadContext', ...
            'Use nhpulseCreateProjectContext to create the project context.');
    end
end

function tf = isBoolLike(x)
    tf = (islogical(x) || isnumeric(x)) && isscalar(x);
end
