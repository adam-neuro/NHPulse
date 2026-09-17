function report = nhpulseCheckManifest(manifestIn, varargin)
% NHPULSECHECKMANIFEST Run generic existence, fingerprint, and graph checks.
%
% report = nhpulseCheckManifest(manifestOrFile) accepts a manifest struct or
% MAT/JSON manifest file. Unknown artifact types receive generic validation
% and do not fail merely because no type-specific validator exists yet.
%
% Name-value options:
%   verifyContent : recompute artifact fingerprints [true]
%   verbose       : print a concise report [true]

    p = inputParser;
    addParameter(p, 'verifyContent', true, @isBoolLike);
    addParameter(p, 'verbose', true, @isBoolLike);
    parse(p, varargin{:});
    opts = p.Results;
    opts.verifyContent = logical(opts.verifyContent);
    opts.verbose = logical(opts.verbose);

    if ischar(manifestIn) || isstring(manifestIn)
        manifest = nhpulseLoadManifest(manifestIn);
    else
        manifest = manifestIn;
    end
    validateManifest(manifest);
    artifacts = manifest.artifacts;
    n = numel(artifacts);
    ids = cell(n, 1);
    for i = 1:n
        ids{i} = char(artifacts(i).artifactId);
    end
    if numel(unique(ids)) ~= n
        duplicateIds = idsDuplicate(ids);
    else
        duplicateIds = {};
    end

    checks = repmat(emptyCheck(), n, 1);
    parentIndices = cell(n, 1);
    ownPassed = true(n, 1);
    for i = 1:n
        artifact = artifacts(i);
        check = emptyCheck();
        check.artifactId = char(artifact.artifactId);
        check.type = char(artifact.type);
        check.label = char(artifact.label);
        check.path = nhpulseManifestInternal('resolvePath', manifest, artifact);
        check.exists = exist(check.path, 'file') == 2;
        check.fingerprintMatches = ~opts.verifyContent;
        check.parentsResolve = true;
        check.parentFingerprintsMatch = true;
        messages = {};

        if ~check.exists
            messages{end + 1} = 'artifact file is missing'; %#ok<AGROW>
        elseif opts.verifyContent
            current = nhpulseManifestInternal('fingerprint', check.path, ...
                artifact.contentFingerprint.algorithm);
            check.fingerprintMatches = nhpulseManifestInternal( ...
                'fingerprintsEqual', current, artifact.contentFingerprint);
            if ~check.fingerprintMatches
                messages{end + 1} = 'artifact content fingerprint changed'; %#ok<AGROW>
            end
        end

        refs = artifact.parents;
        idxList = zeros(0, 1);
        for j = 1:numel(refs)
            idx = find(strcmp(ids, char(refs(j).artifactId)), 1);
            if isempty(idx)
                check.parentsResolve = false;
                messages{end + 1} = sprintf('missing parent %s', ...
                    char(refs(j).artifactId)); %#ok<AGROW>
                continue;
            end
            idxList(end + 1, 1) = idx; %#ok<AGROW>
            if ~nhpulseManifestInternal('fingerprintsEqual', ...
                    refs(j).recordedFingerprint, ...
                    artifacts(idx).contentFingerprint)
                check.parentFingerprintsMatch = false;
                messages{end + 1} = sprintf('parent %s revision changed', ...
                    char(refs(j).artifactId)); %#ok<AGROW>
            end
        end
        parentIndices{i} = idxList;
        check.messages = messages;
        checks(i) = check;
        ownPassed(i) = check.exists && check.fingerprintMatches && ...
            check.parentsResolve && check.parentFingerprintsMatch;
    end

    cycleAffected = graphCycleAffected(parentIndices, n);
    passed = ownPassed & ~cycleAffected;
    for iteration = 1:max(1, n)
        previous = passed;
        for i = 1:n
            if ~passed(i)
                continue;
            end
            passed(i) = all(previous(parentIndices{i}));
        end
        if isequal(previous, passed)
            break;
        end
    end

    for i = 1:n
        checks(i).cycleAffected = cycleAffected(i);
        checks(i).passed = passed(i);
        if cycleAffected(i)
            checks(i).messages{end + 1} = 'dependency cycle or cycle-dependent artifact';
        elseif ownPassed(i) && ~passed(i)
            checks(i).messages{end + 1} = 'upstream parent is stale or invalid';
        end
        if checks(i).passed
            checks(i).status = 'current';
        elseif ~checks(i).exists
            checks(i).status = 'missing';
        else
            checks(i).status = 'stale';
        end
    end

    report = struct();
    report.schema = 'nhpulse.manifestCheck';
    report.schemaVersion = 1;
    report.createdOn = char(datetime('now', 'TimeZone', 'local', 'Format', ...
        'yyyy-MM-dd''T''HH:mm:ssXXX'));
    report.runId = manifest.runId;
    report.passed = isempty(duplicateIds) && all(passed);
    report.artifactCount = n;
    report.currentCount = nnz(passed);
    report.duplicateArtifactIds = duplicateIds;
    report.checks = checks;
    report.validationScope = 'generic';

    if opts.verbose
        printReport(report);
    end
end

function value = emptyCheck()
    value = struct('artifactId', '', 'type', '', 'label', '', 'path', '', ...
        'exists', false, 'fingerprintMatches', false, ...
        'parentsResolve', false, 'parentFingerprintsMatch', false, ...
        'cycleAffected', false, 'passed', false, 'status', '', ...
        'messages', {{}});
end

function affected = graphCycleAffected(parentIndices, n)
    indegree = zeros(n, 1);
    children = cell(n, 1);
    for child = 1:n
        parents = unique(parentIndices{child});
        indegree(child) = numel(parents);
        for j = 1:numel(parents)
            children{parents(j)}(end + 1) = child;
        end
    end
    queue = find(indegree == 0).';
    processed = false(n, 1);
    while ~isempty(queue)
        node = queue(1);
        queue(1) = [];
        processed(node) = true;
        for child = children{node}
            indegree(child) = indegree(child) - 1;
            if indegree(child) == 0
                queue(end + 1) = child; %#ok<AGROW>
            end
        end
    end
    affected = ~processed;
end

function duplicates = idsDuplicate(ids)
    duplicates = {};
    for i = 1:numel(ids)
        if nnz(strcmp(ids, ids{i})) > 1 && ~any(strcmp(duplicates, ids{i}))
            duplicates{end + 1} = ids{i}; %#ok<AGROW>
        end
    end
end

function validateManifest(manifest)
    if ~isstruct(manifest) || ~isfield(manifest, 'schema') || ...
            ~strcmp(manifest.schema, 'nhpulse.runManifest') || ...
            ~isfield(manifest, 'artifacts') || ~isfield(manifest, 'projectRoot')
        error('nhpulseCheckManifest:BadManifest', ...
            'Input is not an NHPulse run manifest.');
    end
end

function tf = isBoolLike(x)
    tf = (islogical(x) || isnumeric(x)) && isscalar(x);
end

function printReport(report)
    fprintf('\nNHPulse manifest check\n');
    fprintf('  run: %s\n', report.runId);
    fprintf('  current artifacts: %d/%d\n', ...
        report.currentCount, report.artifactCount);
    for i = 1:numel(report.checks)
        item = report.checks(i);
        fprintf('  %-8s %-30s %s\n', upper(item.status), ...
            item.type, item.label);
        for j = 1:numel(item.messages)
            fprintf('           %s\n', item.messages{j});
        end
    end
    if ~isempty(report.duplicateArtifactIds)
        fprintf('  duplicate IDs: %s\n', ...
            strjoin(report.duplicateArtifactIds, ', '));
    end
    fprintf('\n');
end
