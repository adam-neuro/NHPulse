function [manifest, artifact] = nhpulseRegisterArtifact( ...
        manifest, artifactType, fileName, varargin)
% NHPULSEREGISTERARTIFACT Register an existing file without moving it.
%
% [manifest, artifact] = nhpulseRegisterArtifact(manifest, type, fileName)
% fingerprints fileName and appends a generic artifact record.
%
% Name-value options:
%   label           : human-readable label [artifactType]
%   artifactId      : explicit unique ID [[] = generated]
%   parents         : refs, artifacts, IDs, or a cell array of these [{}]
%   parentRole      : default role for artifact/ID parent inputs ['input']
%   metadata        : JSON-compatible artifact metadata [struct()]
%   fingerprintMode : 'auto', 'sha256', or 'metadata' ['auto']
%                     auto uses SHA-256 through 256 MB, then size/mtime

    validateManifest(manifest);
    p = inputParser;
    p.FunctionName = 'nhpulseRegisterArtifact';
    addParameter(p, 'label', artifactType, @(x) ischar(x) || isstring(x));
    addParameter(p, 'artifactId', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'parents', {}, @(x) true);
    addParameter(p, 'parentRole', 'input', @(x) ischar(x) || isstring(x));
    addParameter(p, 'metadata', struct(), @isstruct);
    addParameter(p, 'fingerprintMode', 'auto', ...
        @(x) ischar(x) || isstring(x));
    parse(p, varargin{:});

    fileName = nhpulseManifestInternal('canonicalPath', fileName);
    if exist(fileName, 'file') ~= 2
        error('nhpulseRegisterArtifact:FileNotFound', ...
            'Artifact file does not exist: %s', fileName);
    end
    artifactId = char(p.Results.artifactId);
    if isempty(artifactId)
        artifactId = nhpulseManifestInternal('newId', artifactType);
    end
    if any(strcmp({manifest.artifacts.artifactId}, artifactId))
        error('nhpulseRegisterArtifact:DuplicateArtifactId', ...
            'Artifact ID already exists in this manifest: %s', artifactId);
    end

    artifact = nhpulseManifestInternal('emptyArtifact');
    artifact.artifactId = artifactId;
    artifact.type = char(artifactType);
    artifact.label = char(p.Results.label);
    [artifact.path, artifact.pathIsRelative] = ...
        nhpulseManifestInternal('storePath', fileName, manifest.projectRoot);
    artifact.contentFingerprint = nhpulseManifestInternal( ...
        'fingerprint', fileName, char(p.Results.fingerprintMode));
    artifact.parents = normalizeParents(p.Results.parents, manifest, ...
        char(p.Results.parentRole));
    artifact.metadata = p.Results.metadata;
    artifact.createdOn = char(datetime('now', 'TimeZone', 'local', 'Format', ...
        'yyyy-MM-dd''T''HH:mm:ssXXX'));
    manifest.artifacts(end + 1, 1) = artifact;
end

function parents = normalizeParents(value, manifest, defaultRole)
    emptyParent = nhpulseManifestInternal('emptyParent');
    parents = repmat(emptyParent, 0, 1);
    if isempty(value)
        return;
    end
    if ~iscell(value)
        if isstruct(value) && numel(value) > 1
            value = num2cell(value);
        else
            value = {value};
        end
    end
    for i = 1:numel(value)
        item = value{i};
        if isstruct(item) && isfield(item, 'role') && ...
                isfield(item, 'recordedFingerprint') && ...
                isfield(item, 'artifactId')
            ref = item;
        else
            ref = nhpulseArtifactRef(item, defaultRole);
        end
        idx = find(strcmp({manifest.artifacts.artifactId}, ref.artifactId), 1);
        if isempty(idx)
            error('nhpulseRegisterArtifact:UnknownParent', ...
                'Parent artifact is not registered: %s', ref.artifactId);
        end
        if ~isstruct(ref.recordedFingerprint) || ...
                ~isfield(ref.recordedFingerprint, 'value') || ...
                isempty(ref.recordedFingerprint.value)
            ref.recordedFingerprint = ...
                manifest.artifacts(idx).contentFingerprint;
        end
        parents(end + 1, 1) = ref; %#ok<AGROW>
    end
end

function validateManifest(manifest)
    if ~isstruct(manifest) || ~isfield(manifest, 'schema') || ...
            ~strcmp(manifest.schema, 'nhpulse.runManifest') || ...
            ~isfield(manifest, 'artifacts') || ~isfield(manifest, 'projectRoot')
        error('nhpulseRegisterArtifact:BadManifest', ...
            'Input is not an NHPulse run manifest.');
    end
end
