function artifacts = nhpulseDiscoverLegacyArtifacts(projectRoot, varargin)
% NHPULSEDISCOVERLEGACYARTIFACTS Classify unmanifested output files.
%
% artifacts = nhpulseDiscoverLegacyArtifacts(projectRoot) scans the outputs
% subtree when present, otherwise projectRoot. Discovery is read-only. It
% uses filename patterns from nhpulseArtifactTypes and does not infer parent
% relationships.
%
% Name-value options:
%   scanRoots           : folder or cell array of folders [automatic]
%   registeredPaths     : paths to omit [{}]
%   artifactTypes       : additional hierarchy definitions [struct([])]
%   includeUnclassified : include files with no recognized type [false]
%   maxFiles            : safety limit on files examined [100000]


    p = inputParser;
    addParameter(p, 'scanRoots', {}, @(x) ischar(x) || isstring(x) || iscell(x));
    addParameter(p, 'registeredPaths', {}, @(x) ischar(x) || isstring(x) || iscell(x));
    addParameter(p, 'artifactTypes', struct([]), @isstruct);
    addParameter(p, 'includeUnclassified', false, @isBoolLike);
    addParameter(p, 'maxFiles', 100000, @(x) isnumeric(x) && isscalar(x) && x > 0);
    parse(p, varargin{:});
    opts = p.Results;

    projectRoot = canonicalPath(projectRoot);
    roots = normalizeRoots(projectRoot, opts.scanRoots);
    registered = normalizePaths(opts.registeredPaths);
    registry = nhpulseArtifactTypes('additionalTypes', opts.artifactTypes);
    artifacts = repmat(emptyDiscovery(), 0, 1);
    examined = 0;

    for r = 1:numel(roots)
        entries = dir(fullfile(roots{r}, '**', '*'));
        entries = entries(~[entries.isdir]);
        for i = 1:numel(entries)
            examined = examined + 1;
            if examined > opts.maxFiles
                error('nhpulseDiscoverLegacyArtifacts:MaxFilesExceeded', ...
                    'Legacy scan exceeded maxFiles=%d.', opts.maxFiles);
            end
            fileName = canonicalPath(fullfile(entries(i).folder, entries(i).name));
            if isIgnoredPath(fileName, projectRoot) || ...
                    pathIsListed(fileName, registered)
                continue;
            end
            relativePath = makeRelative(fileName, projectRoot);
            [definition, reason] = classifyPath(relativePath, registry);
            if isempty(definition)
                if ~logical(opts.includeUnclassified)
                    continue;
                end
                definition = unclassifiedDefinition();
                confidence = 'unclassified';
                reason = 'no artifact-type filename pattern matched';
            else
                confidence = 'probable';
            end
            item = emptyDiscovery();
            item.discoveryId = sprintf('legacy-%06d', numel(artifacts) + 1);
            item.type = definition.type;
            item.label = entries(i).name;
            item.path = fileName;
            item.relativePath = relativePath;
            item.stage = definition.stage;
            item.stageOrder = definition.stageOrder;
            item.confidence = confidence;
            item.reason = reason;
            item.bytes = double(entries(i).bytes);
            item.modifiedOn = char(datetime(entries(i).datenum, ...
                'ConvertFrom', 'datenum', 'Format', 'yyyy-MM-dd HH:mm:ss'));
            artifacts(end + 1, 1) = item; %#ok<AGROW>
        end
    end

    if ~isempty(artifacts)
        [~, order] = sortrows([[artifacts.stageOrder].', ...
            (1:numel(artifacts)).']);
        artifacts = artifacts(order);
    end
end

function roots = normalizeRoots(projectRoot, value)
    if isempty(value)
        outputRoot = fullfile(projectRoot, 'outputs');
        if exist(outputRoot, 'dir') == 7
            roots = {outputRoot};
        else
            roots = {projectRoot};
        end
    elseif ischar(value) || isstring(value)
        roots = cellstr(value);
    else
        roots = value;
    end
    for i = 1:numel(roots)
        roots{i} = canonicalPath(roots{i});
        if exist(roots{i}, 'dir') ~= 7
            error('nhpulseDiscoverLegacyArtifacts:ScanRootMissing', ...
                'Legacy scan root does not exist: %s', roots{i});
        end
    end
end

function paths = normalizePaths(value)
    if isempty(value)
        paths = {};
    elseif ischar(value) || isstring(value)
        paths = cellstr(value);
    else
        paths = value;
    end
    normalized = cell(size(paths));
    for i = 1:numel(paths)
        normalized{i} = canonicalPath(paths{i});
    end
    paths = normalized;
end

function [definition, reason] = classifyPath(relativePath, registry)
    normalized = lower(strrep(relativePath, '\', '/'));
    scores = -inf(numel(registry), 1);
    matchingPattern = cell(numel(registry), 1);
    for i = 1:numel(registry)
        for j = 1:numel(registry(i).legacyPatterns)
            pattern = registry(i).legacyPatterns{j};
            if ~isempty(regexpi(normalized, pattern, 'once'))
                scores(i) = registry(i).legacyPriority;
                matchingPattern{i} = pattern;
                break;
            end
        end
    end
    best = find(scores == max(scores), 1);
    if isempty(best) || ~isfinite(scores(best))
        definition = [];
        reason = '';
    else
        definition = registry(best);
        reason = sprintf('matched legacy pattern %s', matchingPattern{best});
    end
end

function tf = isIgnoredPath(fileName, projectRoot)
    rel = lower(strrep(makeRelative(fileName, projectRoot), '\', '/'));
    components = strsplit(rel, '/');
    tf = any(ismember(components, {'.git', 'lib', 'manifests'})) || ...
        strcmpi(components{end}, 'nhpulse-manifest.mat') || ...
        strcmpi(components{end}, 'nhpulse-manifest.json');
end

function tf = pathIsListed(fileName, paths)
    if ispc
        tf = any(strcmpi(fileName, paths));
    else
        tf = any(strcmp(fileName, paths));
    end
end

function value = makeRelative(fileName, root)
    prefix = [root filesep];
    if (ispc && startsWith(lower(fileName), lower(prefix))) || ...
            (~ispc && startsWith(fileName, prefix))
        value = fileName((numel(prefix) + 1):end);
    else
        value = fileName;
    end
end

function value = canonicalPath(value)
    value = char(value);
    if usejava('jvm')
        value = char(java.io.File(value).getCanonicalPath());
    elseif ~isfolder(value) && ~isfile(value)
        value = fullfile(pwd, value);
    end
end

function value = emptyDiscovery()
    value = struct('discoveryId', '', 'type', '', 'label', '', ...
        'path', '', 'relativePath', '', 'stage', '', 'stageOrder', 999, ...
        'confidence', '', 'reason', '', 'bytes', 0, 'modifiedOn', '');
end

function value = unclassifiedDefinition()
    value = struct('type', 'unclassified', 'stage', 'unclassified', ...
        'stageOrder', 999);
end

function tf = isBoolLike(x)
    tf = (islogical(x) || isnumeric(x)) && isscalar(x);
end
