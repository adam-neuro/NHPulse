function project = nhpulseOpenProject(projectRoot, varargin)
% NHPULSEOPENPROJECT Open manifests and legacy outputs as one project index.
%
% project = nhpulseOpenProject(projectRoot) loads each saved run manifest,
% verifies its artifacts, and inventories recognizable files that are not yet
% registered. Existing outputs are never moved or modified.
%
% Name-value options:
%   verifyContent       : recompute registered fingerprints [true]
%   discoverLegacy      : scan outputs for unregistered artifacts [true]
%   includeUnclassified : include every unregistered output file [false]
%   scanRoots           : override legacy scan folder(s) [automatic]
%   artifactTypes       : additional hierarchy definitions [struct([])]
%   verbose             : print project summary [true]

    if nargin < 1 || isempty(projectRoot)
        projectRoot = pwd;
    end
    p = inputParser;
    addParameter(p, 'verifyContent', true, @isBoolLike);
    addParameter(p, 'discoverLegacy', true, @isBoolLike);
    addParameter(p, 'includeUnclassified', false, @isBoolLike);
    addParameter(p, 'scanRoots', {}, @(x) ischar(x) || isstring(x) || iscell(x));
    addParameter(p, 'artifactTypes', struct([]), @isstruct);
    addParameter(p, 'verbose', true, @isBoolLike);
    parse(p, varargin{:});
    opts = p.Results;

    projectRoot = canonicalPath(projectRoot);
    if exist(projectRoot, 'dir') ~= 7
        error('nhpulseOpenProject:ProjectRootMissing', ...
            'Project root does not exist: %s', projectRoot);
    end
    registry = nhpulseArtifactTypes('additionalTypes', opts.artifactTypes);
    manifestFiles = findManifestFiles(projectRoot);
    runs = repmat(emptyRun(), 0, 1);
    artifacts = repmat(emptyProjectArtifact(), 0, 1);
    issues = repmat(emptyIssue(), 0, 1);

    for i = 1:numel(manifestFiles)
        try
            manifest = nhpulseLoadManifest(manifestFiles{i});
            check = nhpulseCheckManifest(manifest, ...
                'verifyContent', opts.verifyContent, ...
                'artifactTypes', opts.artifactTypes, 'verbose', false);
            run = emptyRun();
            run.manifestFile = manifestFiles{i};
            run.runId = char(manifest.runId);
            run.runLabel = char(manifest.runLabel);
            run.manifest = manifest;
            run.check = check;
            run.status = chooseText(check.passed, 'current', 'attention');
            runs(end + 1, 1) = run; %#ok<AGROW>
            artifacts = [artifacts; flattenArtifacts(run, registry)]; %#ok<AGROW>
        catch ME
            issue = emptyIssue();
            issue.severity = 'error';
            issue.code = ME.identifier;
            issue.path = manifestFiles{i};
            issue.message = ME.message;
            issues(end + 1, 1) = issue; %#ok<AGROW>
        end
    end

    issues = [issues; crossManifestIssues(artifacts)];
    registeredPaths = {artifacts.path};
    legacy = repmat(emptyLegacyProjectArtifact(), 0, 1);
    if logical(opts.discoverLegacy)
        discovered = nhpulseDiscoverLegacyArtifacts(projectRoot, ...
            'scanRoots', opts.scanRoots, ...
            'registeredPaths', registeredPaths, ...
            'artifactTypes', opts.artifactTypes, ...
            'includeUnclassified', opts.includeUnclassified);
        legacy = flattenLegacy(discovered);
    end

    project = struct();
    project.schema = 'nhpulse.projectIndex';
    project.schemaVersion = 1;
    project.projectRoot = projectRoot;
    project.openedOn = timestampNow();
    project.registry = registry;
    project.runs = runs;
    project.artifacts = artifacts;
    project.legacyArtifacts = legacy;
    project.issues = issues;
    project.summary = makeSummary(runs, artifacts, legacy, issues);

    if logical(opts.verbose)
        fprintf('\nNHPulse project opened\n');
        fprintf('  root: %s\n', projectRoot);
        fprintf('  manifests: %d\n', numel(runs));
        fprintf('  registered artifacts: %d\n', numel(artifacts));
        fprintf('  unregistered legacy artifacts: %d\n', numel(legacy));
        fprintf('  issues: %d\n\n', numel(issues));
    end
end

function files = findManifestFiles(root)
    entries = dir(fullfile(root, '**', 'nhpulse-manifest.mat'));
    files = cell(numel(entries), 1);
    for i = 1:numel(entries)
        files{i} = canonicalPath(fullfile(entries(i).folder, entries(i).name));
    end
    files = unique(files, 'stable');
end

function values = flattenArtifacts(run, registry)
    n = numel(run.manifest.artifacts);
    values = repmat(emptyProjectArtifact(), n, 1);
    for i = 1:n
        source = run.manifest.artifacts(i);
        check = run.check.checks(i);
        definition = findDefinition(registry, source.type);
        value = emptyProjectArtifact();
        value.source = 'manifest';
        value.runId = run.runId;
        value.manifestFile = run.manifestFile;
        value.artifactId = char(source.artifactId);
        value.type = char(source.type);
        value.label = char(source.label);
        value.path = check.path;
        value.status = check.status;
        value.registered = true;
        value.messages = check.messages;
        if ~isempty(definition)
            value.stage = definition.stage;
            value.stageOrder = definition.stageOrder;
        end
        values(i) = value;
    end
end

function values = flattenLegacy(discovered)
    values = repmat(emptyLegacyProjectArtifact(), numel(discovered), 1);
    for i = 1:numel(discovered)
        value = emptyLegacyProjectArtifact();
        names = fieldnames(discovered(i));
        for j = 1:numel(names)
            value.(names{j}) = discovered(i).(names{j});
        end
        value.status = 'unregistered';
        value.registered = false;
        values(i) = value;
    end
end

function issues = crossManifestIssues(artifacts)
    issues = repmat(emptyIssue(), 0, 1);
    if isempty(artifacts)
        return;
    end
    ids = {artifacts.artifactId};
    uniqueIds = unique(ids);
    for i = 1:numel(uniqueIds)
        idx = find(strcmp(ids, uniqueIds{i}));
        if numel(idx) < 2
            continue;
        end
        paths = unique(normalizeForComparison({artifacts(idx).path}));
        if numel(paths) > 1
            issue = emptyIssue();
            issue.severity = 'error';
            issue.code = 'nhpulseOpenProject:ConflictingArtifactId';
            issue.path = strjoin({artifacts(idx).manifestFile}, '; ');
            issue.message = sprintf( ...
                'Artifact ID %s refers to different paths across manifests.', ...
                uniqueIds{i});
            issues(end + 1, 1) = issue; %#ok<AGROW>
        end
    end
end

function paths = normalizeForComparison(paths)
    if ispc
        paths = cellfun(@lower, paths, 'UniformOutput', false);
    end
end

function definition = findDefinition(registry, type)
    idx = find(strcmp({registry.type}, char(type)), 1);
    if isempty(idx)
        definition = [];
    else
        definition = registry(idx);
    end
end

function summary = makeSummary(runs, artifacts, legacy, issues)
    summary = struct();
    summary.runCount = numel(runs);
    summary.registeredCount = numel(artifacts);
    summary.currentCount = nnz(strcmp({artifacts.status}, 'current'));
    summary.staleCount = nnz(strcmp({artifacts.status}, 'stale'));
    summary.missingCount = nnz(strcmp({artifacts.status}, 'missing'));
    summary.incompatibleCount = nnz(strcmp({artifacts.status}, 'incompatible'));
    summary.unregisteredCount = numel(legacy);
    summary.issueCount = numel(issues);
end

function value = emptyRun()
    value = struct('manifestFile', '', 'runId', '', 'runLabel', '', ...
        'status', '', 'manifest', struct(), 'check', struct());
end

function value = emptyProjectArtifact()
    value = struct('source', '', 'runId', '', 'manifestFile', '', ...
        'artifactId', '', 'type', '', 'label', '', 'path', '', ...
        'stage', 'extension', 'stageOrder', 999, 'status', '', ...
        'registered', true, 'messages', {{}});
end

function value = emptyLegacyProjectArtifact()
    value = struct('discoveryId', '', 'type', '', 'label', '', ...
        'path', '', 'relativePath', '', 'stage', '', 'stageOrder', 999, ...
        'confidence', '', 'reason', '', 'bytes', 0, 'modifiedOn', '', ...
        'status', 'unregistered', 'registered', false);
end

function value = emptyIssue()
    value = struct('severity', '', 'code', '', 'path', '', 'message', '');
end

function value = canonicalPath(value)
    value = char(value);
    if usejava('jvm')
        value = char(java.io.File(value).getCanonicalPath());
    elseif ~startsWith(value, filesep) && isempty(regexp(value, '^[A-Za-z]:', 'once'))
        value = fullfile(pwd, value);
    end
end

function value = timestampNow()
    value = char(datetime('now', 'TimeZone', 'local', ...
        'Format', 'yyyy-MM-dd''T''HH:mm:ssXXX'));
end

function value = chooseText(condition, yesValue, noValue)
    if condition
        value = yesValue;
    else
        value = noValue;
    end
end

function tf = isBoolLike(x)
    tf = (islogical(x) || isnumeric(x)) && isscalar(x);
end
