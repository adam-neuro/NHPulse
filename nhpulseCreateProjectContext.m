function context = nhpulseCreateProjectContext(projectRoot, runId, varargin)
% NHPULSECREATEPROJECTCONTEXT Create an explicit service/project reference.
%
% context = nhpulseCreateProjectContext(projectRoot, runId) identifies one
% manifest-backed pipeline run. It does not create products or modify a
% manifest until a service records an output.

    p = inputParser;
    addParameter(p, 'runLabel', runId, @(x) ischar(x) || isstring(x));
    addParameter(p, 'metadata', struct(), @isstruct);
    parse(p, varargin{:});
    projectRoot = canonicalPath(projectRoot);
    if exist(projectRoot, 'dir') ~= 7
        error('nhpulseCreateProjectContext:ProjectRootMissing', ...
            'Project root does not exist: %s', projectRoot);
    end
    runId = safeKey(runId);
    context = struct();
    context.schema = 'nhpulse.projectContext';
    context.schemaVersion = 1;
    context.projectRoot = projectRoot;
    context.runId = runId;
    context.runLabel = char(p.Results.runLabel);
    context.metadata = p.Results.metadata;
    context.manifestFile = fullfile(projectRoot, 'manifests', runId, ...
        'nhpulse-manifest.mat');
end

function value = safeKey(value)
    value = lower(regexprep(char(value), '[^A-Za-z0-9_.-]+', '-'));
    value = regexprep(value, '(^-+|-+$)', '');
    if isempty(value)
        error('nhpulseCreateProjectContext:EmptyRunId', ...
            'runId must contain letters or numbers.');
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
