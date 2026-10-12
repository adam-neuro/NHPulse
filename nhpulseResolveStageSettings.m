function [config, info] = nhpulseResolveStageSettings(stageKey, varargin)
% NHPULSERESOLVESTAGESETTINGS Resolve defaults, a preset, and overrides.
%
% [config, info] = nhpulseResolveStageSettings(stageKey, ...
%     'preset', presetKey, 'overrides', settingsStruct, ...
%     'advancedOptions', engineStruct)

    definition = nhpulseStageSettings(stageKey);
    p = inputParser;
    addParameter(p, 'preset', definition.defaultPreset, ...
        @(x) ischar(x) || isstring(x));
    addParameter(p, 'overrides', struct(), @isstruct);
    addParameter(p, 'advancedOptions', struct(), @isstruct);
    parse(p, varargin{:});

    presetKey = lower(char(p.Results.preset));
    presetIndex = find(strcmpi({definition.presets.key}, presetKey), 1);
    if isempty(presetIndex)
        error('nhpulseResolveStageSettings:UnknownPreset', ...
            'Unknown preset "%s" for stage "%s".', presetKey, stageKey);
    end

    config = struct();
    for i = 1:numel(definition.fields)
        field = definition.fields(i);
        config.(field.name) = field.defaultValue;
    end
    config = mergeStruct(config, definition.presets(presetIndex).values);
    config = mergeStruct(config, p.Results.overrides);
    config = validateConfig(config, definition);
    advancedField = definition.advancedOptionField;
    if ~isempty(fieldnames(p.Results.advancedOptions))
        config.(advancedField) = p.Results.advancedOptions;
    elseif isfield(config, advancedField) && ~isstruct(config.(advancedField))
        error('nhpulseResolveStageSettings:BadAdvancedOptions', ...
            '%s must be a structure.', advancedField);
    end
    info = struct('stageKey', definition.stageKey, ...
        'preset', definition.presets(presetIndex).key, ...
        'presetLabel', definition.presets(presetIndex).label, ...
        'definition', definition);
end

function config = validateConfig(config, definition)
    for i = 1:numel(definition.fields)
        field = definition.fields(i);
        if ~isfield(config, field.name), continue; end
        value = config.(field.name);
        switch field.type
            case 'logical'
                if ~(islogical(value) && isscalar(value)) && ...
                        ~(isnumeric(value) && isscalar(value) && any(value == [0 1]))
                    error('nhpulseResolveStageSettings:BadLogical', ...
                        '%s must be true or false.', field.label);
                end
                config.(field.name) = logical(value);
            case 'number'
                if ~(isnumeric(value) && isscalar(value) && isfinite(value))
                    error('nhpulseResolveStageSettings:BadNumber', ...
                        '%s must be one finite number.', field.label);
                end
            case 'choice'
                if ~any(strcmpi(char(value), field.choices))
                    error('nhpulseResolveStageSettings:BadChoice', ...
                        '%s must be one of: %s.', field.label, ...
                        strjoin(field.choices, ', '));
                end
            case 'text'
                if ~(ischar(value) || isstring(value))
                    error('nhpulseResolveStageSettings:BadText', ...
                        '%s must be text.', field.label);
                end
        end
    end
end

function output = mergeStruct(base, additions)
    output = base;
    names = fieldnames(additions);
    for i = 1:numel(names)
        output.(names{i}) = additions.(names{i});
    end
end
