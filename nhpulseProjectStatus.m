function report = nhpulseProjectStatus(projectIn, varargin)
% NHPULSEPROJECTSTATUS Summarize current and legacy project artifacts.
%
% report = nhpulseProjectStatus(projectOrRoot) accepts a project struct from
% nhpulseOpenProject or a project-root folder. The returned table includes
% current, stale, missing, incompatible, and unregistered artifacts.
%
% Name-value options:
%   verbose       : print the table and summary [true]
%   verifyContent : used when opening a folder [true]
%   artifactTypes : additional hierarchy definitions [struct([])]

    p = inputParser;
    addParameter(p, 'verbose', true, @isBoolLike);
    addParameter(p, 'verifyContent', true, @isBoolLike);
    addParameter(p, 'artifactTypes', struct([]), @isstruct);
    parse(p, varargin{:});
    opts = p.Results;

    if ischar(projectIn) || isstring(projectIn)
        project = nhpulseOpenProject(projectIn, ...
            'verifyContent', opts.verifyContent, ...
            'artifactTypes', opts.artifactTypes, 'verbose', false);
    else
        project = projectIn;
    end
    validateProject(project);

    rows = repmat(emptyRow(), 0, 1);
    for i = 1:numel(project.artifacts)
        item = project.artifacts(i);
        row = emptyRow();
        row.Source = item.source;
        row.RunId = item.runId;
        row.ArtifactId = item.artifactId;
        row.Type = item.type;
        row.Stage = item.stage;
        row.StageOrder = item.stageOrder;
        row.Label = item.label;
        row.Status = item.status;
        row.Path = item.path;
        row.Messages = strjoin(item.messages, '; ');
        rows(end + 1, 1) = row; %#ok<AGROW>
    end
    for i = 1:numel(project.legacyArtifacts)
        item = project.legacyArtifacts(i);
        row = emptyRow();
        row.Source = 'legacy';
        row.ArtifactId = item.discoveryId;
        row.Type = item.type;
        row.Stage = item.stage;
        row.StageOrder = item.stageOrder;
        row.Label = item.label;
        row.Status = 'unregistered';
        row.Path = item.path;
        row.Messages = item.reason;
        rows(end + 1, 1) = row; %#ok<AGROW>
    end
    if isempty(rows)
        artifactTable = struct2table(repmat(emptyRow(), 0, 1));
    else
        [~, order] = sortrows([[rows.StageOrder].', (1:numel(rows)).']);
        artifactTable = struct2table(rows(order));
    end
    artifactTable.StageOrder = [];

    statuses = {'current', 'stale', 'missing', 'incompatible', 'unregistered'};
    counts = zeros(numel(statuses), 1);
    for i = 1:numel(statuses)
        counts(i) = nnz(strcmp(artifactTable.Status, statuses{i}));
    end
    report = struct();
    report.schema = 'nhpulse.projectStatus';
    report.schemaVersion = 1;
    report.createdOn = char(datetime('now', 'TimeZone', 'local', ...
        'Format', 'yyyy-MM-dd''T''HH:mm:ssXXX'));
    report.projectRoot = project.projectRoot;
    report.artifacts = artifactTable;
    report.counts = table(statuses(:), counts, ...
        'VariableNames', {'Status', 'Count'});
    report.issues = project.issues;
    report.passed = counts(2) == 0 && counts(3) == 0 && ...
        counts(4) == 0 && isempty(project.issues);

    if logical(opts.verbose)
        fprintf('\nNHPulse project status\n');
        fprintf('  root: %s\n', project.projectRoot);
        disp(artifactTable(:, {'Stage', 'Type', 'Label', 'Status'}));
        disp(report.counts);
        if ~isempty(report.issues)
            fprintf('Project-level issues:\n');
            for i = 1:numel(report.issues)
                fprintf('  %s: %s\n', upper(report.issues(i).severity), ...
                    report.issues(i).message);
            end
        end
    end
end

function value = emptyRow()
    value = struct('Source', '', 'RunId', '', 'ArtifactId', '', ...
        'Type', '', 'Stage', '', 'StageOrder', 999, 'Label', '', ...
        'Status', '', 'Path', '', 'Messages', '');
end

function validateProject(project)
    if ~isstruct(project) || ~isfield(project, 'schema') || ...
            ~strcmp(project.schema, 'nhpulse.projectIndex') || ...
            ~isfield(project, 'artifacts') || ...
            ~isfield(project, 'legacyArtifacts')
        error('nhpulseProjectStatus:BadProject', ...
            'Input is not an NHPulse project index.');
    end
end

function tf = isBoolLike(x)
    tf = (islogical(x) || isnumeric(x)) && isscalar(x);
end
