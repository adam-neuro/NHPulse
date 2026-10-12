function [config, selection] = nhpulseEditStageSettings(stageKey, currentConfig, varargin)
% NHPULSEEDITSTAGESETTINGS Edit common stage settings in a shared GUI.
%
% [config, selection] = nhpulseEditStageSettings(stageKey, currentConfig)
% returns selection.accepted=false when the dialog is cancelled. Advanced
% engine options are edited as a JSON object so uncommon options remain
% available without dedicating permanent controls to each one.

    if nargin < 2 || isempty(currentConfig), currentConfig = struct(); end
    definition = nhpulseStageSettings(stageKey);
    p = inputParser;
    addParameter(p, 'preset', definition.defaultPreset, ...
        @(x) ischar(x) || isstring(x));
    parse(p, varargin{:});
    [config, resolved] = nhpulseResolveStageSettings(stageKey, ...
        'preset', p.Results.preset, 'overrides', currentConfig);
    selection = struct('accepted', false, 'stageKey', definition.stageKey, ...
        'preset', resolved.preset, 'presetLabel', resolved.presetLabel);

    width = 650;
    height = min(760, 300 + 55 * numel(definition.fields));
    screen = get(groot, 'ScreenSize');
    position = [max(20, screen(3) / 2 - width / 2), ...
        max(40, screen(4) / 2 - height / 2), width, height];
    fig = uifigure('Name', definition.title, 'Position', position, ...
        'WindowStyle', 'modal', 'CloseRequestFcn', @onCancel);
    root = uigridlayout(fig, [5 1]);
    root.RowHeight = {48, 58, 'fit', '1x', 42};
    root.Padding = [14 12 14 12];
    root.RowSpacing = 8;
    description = uitextarea(root, 'Editable', 'off', ...
        'Value', splitlines(string(definition.description)), ...
        'BackgroundColor', [0.97 0.97 0.97]);
    description.Layout.Row = 1;

    presetGrid = uigridlayout(root, [2 2]);
    presetGrid.Layout.Row = 2;
    presetGrid.RowHeight = {22, 26};
    presetGrid.ColumnWidth = {120, '1x'};
    presetGrid.Padding = [0 0 0 0];
    uilabel(presetGrid, 'Text', 'Preset', 'FontWeight', 'bold');
    presetPopup = uidropdown(presetGrid, ...
        'Items', {definition.presets.label}, ...
        'ItemsData', {definition.presets.key}, ...
        'Value', resolved.preset, 'ValueChangedFcn', @onPresetChanged);
    presetHelp = uilabel(presetGrid, 'Text', presetDescription(resolved.preset), ...
        'FontColor', [0.3 0.3 0.3]);
    presetHelp.Layout.Row = 2;
    presetHelp.Layout.Column = [1 2];

    settingsPanel = uipanel(root, 'Title', 'Common settings');
    settingsPanel.Layout.Row = 3;
    settingsGrid = uigridlayout(settingsPanel, [numel(definition.fields), 3]);
    settingsGrid.ColumnWidth = {205, '1x', 55};
    settingsGrid.RowHeight = repmat({30}, 1, numel(definition.fields));
    settingsGrid.Padding = [10 8 10 8];
    controls = struct();
    for i = 1:numel(definition.fields)
        field = definition.fields(i);
        label = uilabel(settingsGrid, 'Text', field.label, ...
            'Tooltip', field.help);
        label.Layout.Row = i; label.Layout.Column = 1;
        control = makeControl(settingsGrid, field, config.(field.name));
        control.Layout.Row = i; control.Layout.Column = 2;
        units = uilabel(settingsGrid, 'Text', field.units, ...
            'FontColor', [0.35 0.35 0.35]);
        units.Layout.Row = i; units.Layout.Column = 3;
        controls.(field.name) = control;
    end

    advancedPanel = uipanel(root, 'Title', ...
        sprintf('Advanced %s (JSON object)', definition.advancedOptionField));
    advancedPanel.Layout.Row = 4;
    advancedGrid = uigridlayout(advancedPanel, [2 1]);
    advancedGrid.RowHeight = {34, '1x'};
    advancedGrid.Padding = [10 8 10 8];
    uilabel(advancedGrid, 'Text', ...
        ['Optional low-level overrides. Leave as {} unless a documented ', ...
        'engine option is needed.']);
    advancedValue = struct();
    if isfield(config, definition.advancedOptionField)
        advancedValue = config.(definition.advancedOptionField);
    end
    advancedArea = uitextarea(advancedGrid, 'Value', ...
        splitlines(string(prettyJson(advancedValue))), ...
        'FontName', 'Courier New');

    buttons = uigridlayout(root, [1 4]);
    buttons.Layout.Row = 5;
    buttons.ColumnWidth = {'1x', 110, 90, 90};
    buttons.Padding = [0 0 0 0];
    uilabel(buttons, 'Text', 'Settings apply to the next stage launch.');
    uibutton(buttons, 'push', 'Text', 'Reset preset', ...
        'ButtonPushedFcn', @onResetPreset);
    uibutton(buttons, 'push', 'Text', 'Cancel', ...
        'ButtonPushedFcn', @onCancel);
    uibutton(buttons, 'push', 'Text', 'Apply', ...
        'ButtonPushedFcn', @onApply);

    uiwait(fig);
    if isgraphics(fig), delete(fig); end

    function onPresetChanged(~, ~)
        presetHelp.Text = presetDescription(presetPopup.Value);
        applyPreset(presetPopup.Value);
    end

    function onResetPreset(~, ~)
        applyPreset(presetPopup.Value);
        advancedArea.Value = {'{}'};
    end

    function applyPreset(presetKey)
        values = nhpulseResolveStageSettings(stageKey, 'preset', presetKey);
        for j = 1:numel(definition.fields)
            field = definition.fields(j);
            setControlValue(controls.(field.name), field, values.(field.name));
        end
    end

    function onApply(~, ~)
        overrides = struct();
        for j = 1:numel(definition.fields)
            field = definition.fields(j);
            overrides.(field.name) = getControlValue(controls.(field.name), field);
        end
        try
            advanced = jsondecode(strjoin(cellstr(advancedArea.Value), newline));
            if ~isstruct(advanced) || numel(advanced) ~= 1
                error('Advanced options must be one JSON object.');
            end
            [config, info] = nhpulseResolveStageSettings(stageKey, ...
                'preset', presetPopup.Value, 'overrides', overrides, ...
                'advancedOptions', advanced);
            selection.accepted = true;
            selection.preset = info.preset;
            selection.presetLabel = info.presetLabel;
            uiresume(fig);
        catch ME
            uialert(fig, ME.message, 'Invalid settings');
        end
    end

    function onCancel(~, ~)
        if isgraphics(fig), uiresume(fig); end
    end

    function textValue = presetDescription(key)
        idx = find(strcmp({definition.presets.key}, key), 1);
        textValue = definition.presets(idx).description;
    end
end

function control = makeControl(parent, field, value)
    switch field.type
        case 'logical'
            control = uicheckbox(parent, 'Text', '', 'Value', logical(value));
        case 'number'
            control = uieditfield(parent, 'numeric', 'Value', double(value));
        case 'choice'
            control = uidropdown(parent, 'Items', field.choices, ...
                'Value', char(value));
        otherwise
            control = uieditfield(parent, 'text', 'Value', char(value));
    end
    control.Tooltip = field.help;
end

function value = getControlValue(control, field)
    value = control.Value;
    if strcmp(field.type, 'logical'), value = logical(value); end
end

function setControlValue(control, field, value)
    if strcmp(field.type, 'logical')
        control.Value = logical(value);
    elseif strcmp(field.type, 'number')
        control.Value = double(value);
    else
        control.Value = char(value);
    end
end

function value = prettyJson(input)
    try
        value = jsonencode(input, 'PrettyPrint', true);
    catch
        value = jsonencode(input);
    end
end
