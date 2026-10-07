function varargout = nhpulseServiceInternal(action, varargin)
% NHPULSESERVICEINTERNAL Shared implementation for stable stage services.

    switch lower(char(action))
        case 'validatecontext'
            validateContext(varargin{1});
        case 'resolve'
            varargout{1} = nhpulseResolveArtifact(varargin{:});
        case 'loadvalue'
            varargout{1} = loadValue(varargin{1});
        case 'options'
            varargout{1} = optionCell(varargin{1});
        case 'outputpath'
            varargout{1} = outputPath(varargin{:});
        case 'record'
            [varargout{1:nargout}] = recordOutput(varargin{:});
        case 'result'
            varargout{1} = makeResult(varargin{:});
        case 'field'
            varargout{1} = getField(varargin{:});
        case 'targetvoxel'
            varargout{1} = targetVoxel(varargin{1});
        otherwise
            error('nhpulseServiceInternal:UnknownAction', ...
                'Unknown service action "%s".', char(action));
    end
end

function validateContext(context)
    if ~isstruct(context) || ~isfield(context, 'schema') || ...
            ~strcmp(context.schema, 'nhpulse.projectContext') || ...
            ~all(isfield(context, {'projectRoot', 'runId', 'runLabel', 'metadata'}))
        error('nhpulseService:BadContext', ...
            'Use nhpulseCreateProjectContext to create the project context.');
    end
end

function value = loadValue(handle)
    if ~isstruct(handle) || ~isfield(handle, 'path')
        error('nhpulseService:BadArtifactHandle', ...
            'Resolve the artifact before loading its value.');
    end
    [~, ~, ext] = fileparts(handle.path);
    if ~strcmpi(ext, '.mat')
        value = handle.path;
        return;
    end
    S = load(handle.path);
    preferred = {'out', 'outForSave', 'outToSave', 'report', ...
        'targetSelection', 'manifest'};
    for i = 1:numel(preferred)
        if isfield(S, preferred{i})
            value = S.(preferred{i});
            return;
        end
    end
    names = fieldnames(S);
    if isscalar(names)
        value = S.(names{1});
    else
        value = S;
    end
end

function options = optionCell(value)
    if isempty(value)
        options = {};
    elseif iscell(value)
        options = value;
    elseif isstruct(value) && isscalar(value)
        names = fieldnames(value);
        options = cell(1, 2 * numel(names));
        for i = 1:numel(names)
            options{2 * i - 1} = names{i};
            options{2 * i} = value.(names{i});
        end
    else
        error('nhpulseService:BadEngineOptions', ...
            'engineOptions must be a scalar struct or name-value cell array.');
    end
end

function fileName = outputPath(context, category, fileName)
    folder = fullfile(context.projectRoot, 'artifacts', context.runId, category);
    if exist(folder, 'dir') ~= 7
        mkdir(folder);
    end
    fileName = fullfile(folder, fileName);
end

function [artifact, handle, files] = recordOutput(context, key, type, fileName, varargin)
    [~, artifact, files] = nhpulseRecordArtifact( ...
        context.projectRoot, context.runId, key, type, fileName, ...
        'runLabel', context.runLabel, 'runMetadata', context.metadata, varargin{:});
    handle = nhpulseResolveArtifact(context, artifact, ...
        'verifyContent', false, 'requireCurrent', true);
end

function output = makeResult(stage, context, result, artifacts, config)
    output = struct('schema', 'nhpulse.serviceResult', 'schemaVersion', 1, ...
        'stage', stage, 'completedOn', char(datetime('now')), ...
        'context', context, 'result', result, 'artifacts', artifacts, ...
        'config', config);
end

function value = getField(S, name, defaultValue)
    if isstruct(S) && isfield(S, name) && ~isempty(S.(name))
        value = S.(name);
    else
        value = defaultValue;
    end
end

function voxel = targetVoxel(value)
    candidates = {'targetVoxel', 'selectedVoxel', 'selectedVoxels'};
    voxel = [];
    for i = 1:numel(candidates)
        if isstruct(value) && isfield(value, candidates{i}) && ...
                ~isempty(value.(candidates{i}))
            voxel = double(value.(candidates{i}));
            voxel = voxel(1, :);
            break;
        end
    end
    if isempty(voxel) || numel(voxel) ~= 3
        error('nhpulseService:TargetVoxelMissing', ...
            'Target artifact does not contain a three-element target voxel.');
    end
end
