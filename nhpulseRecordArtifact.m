function [manifest, artifact, files] = nhpulseRecordArtifact( ...
        projectRoot, runId, artifactKey, artifactType, fileName, varargin)
% NHPULSERECORDARTIFACT Persist one pipeline artifact and its dependencies.
%
% [manifest, artifact, files] = nhpulseRecordArtifact(projectRoot, runId,
% key, type, fileName) creates or updates a stable run manifest and saves it
% immediately. Reusing artifactKey replaces that record in place. Existing
% children retain their recorded parent fingerprint and therefore become stale
% until their own pipeline stages are rerun.
%
% Name-value options:
%   runLabel        : used when creating the run [runId]
%   runMetadata     : merged into manifest metadata [struct()]
%   label           : artifact display label [artifactKey]
%   parentKeys      : earlier artifact keys in this run [{}]
%   parentRoles     : one role or one role per parent ['input']
%   metadata        : artifact metadata [struct()]
%   fingerprintMode : auto, sha256, or metadata ['auto']
%   verbose         : print checkpoint information [false]

    p = inputParser;
    p.FunctionName = 'nhpulseRecordArtifact';
    addParameter(p, 'runLabel', runId, @(x) ischar(x) || isstring(x));
    addParameter(p, 'runMetadata', struct(), @isstruct);
    addParameter(p, 'label', artifactKey, @(x) ischar(x) || isstring(x));
    addParameter(p, 'parentKeys', {}, ...
        @(x) isempty(x) || ischar(x) || isstring(x) || iscell(x));
    addParameter(p, 'parentRoles', 'input', ...
        @(x) ischar(x) || isstring(x) || iscell(x));
    addParameter(p, 'metadata', struct(), @isstruct);
    addParameter(p, 'fingerprintMode', 'auto', ...
        @(x) ischar(x) || isstring(x));
    addParameter(p, 'verbose', false, @isBoolLike);
    parse(p, varargin{:});
    opts = p.Results;

    projectRoot = canonicalPath(projectRoot);
    runId = safeKey(runId);
    artifactKey = safeKey(artifactKey);
    fileName = resolveArtifactFile(fileName);
    manifestBase = fullfile(projectRoot, 'manifests', runId, ...
        'nhpulse-manifest');
    manifestFile = [manifestBase '.mat'];
    if exist(manifestFile, 'file') == 2
        manifest = nhpulseLoadManifest(manifestFile);
    else
        manifest = nhpulseCreateManifest(projectRoot, opts.runLabel, ...
            'runId', runId, 'metadata', opts.runMetadata);
    end
    manifest.projectRoot = projectRoot;
    manifest.metadata = mergeStructs(manifest.metadata, opts.runMetadata);

    parentKeys = normalizeCellstr(opts.parentKeys);
    parentRoles = normalizeRoles(opts.parentRoles, numel(parentKeys));
    parents = cell(numel(parentKeys), 1);
    for i = 1:numel(parentKeys)
        parent = findArtifactByKey(manifest, safeKey(parentKeys{i}));
        if isempty(parent)
            error('nhpulseRecordArtifact:ParentNotRecorded', ...
                ['Cannot record "%s" because parent key "%s" is absent ', ...
                 'from run %s. Run or record that upstream stage first.'], ...
                artifactKey, parentKeys{i}, runId);
        end
        parents{i} = nhpulseArtifactRef(parent, parentRoles{i});
    end

    existing = findArtifactIndexByKey(manifest, artifactKey);
    if ~isempty(existing)
        manifest.artifacts(existing) = [];
    end
    metadata = opts.metadata;
    metadata.artifactKey = artifactKey;
    metadata.recordedBy = 'nhpulseRecordArtifact';
    [manifest, artifact] = nhpulseRegisterArtifact(manifest, ...
        artifactType, fileName, 'artifactId', artifactKey, ...
        'label', opts.label, 'parents', parents, 'metadata', metadata, ...
        'fingerprintMode', opts.fingerprintMode);
    files = nhpulseSaveManifest(manifest, manifestBase);

    if logical(opts.verbose)
        fprintf('Recorded %-24s %-28s %s\n', ...
            artifactKey, char(artifactType), fileName);
    end
end

function fileName = resolveArtifactFile(value)
    if isstruct(value)
        candidates = {'reportMat', 'outputFile', 'cacheFile', ...
            'leadFieldResultMat', 'requestedLeadFieldResultMat', ...
            'customLocationsFile', 'stlFile', 'tpeStlFile', 'plaStlFile'};
        fileName = '';
        for i = 1:numel(candidates)
            if isfield(value, candidates{i}) && ...
                    (ischar(value.(candidates{i})) || isstring(value.(candidates{i}))) && ...
                    ~isempty(value.(candidates{i})) && ...
                    exist(char(value.(candidates{i})), 'file') == 2
                fileName = char(value.(candidates{i}));
                break;
            end
        end
        if isempty(fileName)
            error('nhpulseRecordArtifact:NoArtifactFileInStruct', ...
                'No existing primary artifact file was found in the input struct.');
        end
    else
        fileName = char(value);
    end
    fileName = canonicalPath(fileName);
    if exist(fileName, 'file') ~= 2
        error('nhpulseRecordArtifact:FileNotFound', ...
            'Artifact file does not exist: %s', fileName);
    end
end

function artifact = findArtifactByKey(manifest, key)
    idx = findArtifactIndexByKey(manifest, key);
    if isempty(idx)
        artifact = [];
    else
        artifact = manifest.artifacts(idx);
    end
end

function idx = findArtifactIndexByKey(manifest, key)
    idx = find(strcmp({manifest.artifacts.artifactId}, key), 1);
    if ~isempty(idx)
        return;
    end
    for i = 1:numel(manifest.artifacts)
        metadata = manifest.artifacts(i).metadata;
        if isstruct(metadata) && isfield(metadata, 'artifactKey') && ...
                strcmp(char(metadata.artifactKey), key)
            idx = i;
            return;
        end
    end
end

function roles = normalizeRoles(value, count)
    roles = normalizeCellstr(value);
    if count == 0
        roles = {};
    elseif numel(roles) == 1
        roles = repmat(roles, count, 1);
    elseif numel(roles) ~= count
        error('nhpulseRecordArtifact:ParentRoleCount', ...
            'parentRoles must contain one role or one role per parent key.');
    end
end

function values = normalizeCellstr(value)
    if isempty(value)
        values = {};
    elseif ischar(value) || isstring(value)
        values = cellstr(value);
    else
        values = value(:);
        for i = 1:numel(values)
            values{i} = char(values{i});
        end
    end
end

function output = mergeStructs(output, updates)
    names = fieldnames(updates);
    for i = 1:numel(names)
        output.(names{i}) = updates.(names{i});
    end
end

function value = safeKey(value)
    value = lower(regexprep(char(value), '[^A-Za-z0-9_.-]+', '-'));
    value = regexprep(value, '(^-+|-+$)', '');
    if isempty(value)
        error('nhpulseRecordArtifact:EmptyKey', ...
            'runId and artifactKey must contain letters or numbers.');
    end
end

function value = canonicalPath(value)
    value = char(value);
    if usejava('jvm')
        value = char(java.io.File(value).getCanonicalPath());
    elseif isempty(regexp(value, '^[A-Za-z]:[\\/]|^/', 'once'))
        value = fullfile(pwd, value);
    end
end

function tf = isBoolLike(x)
    tf = (islogical(x) || isnumeric(x)) && isscalar(x);
end
