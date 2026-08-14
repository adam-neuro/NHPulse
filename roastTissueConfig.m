function cfg = roastTissueConfig(extraTissues)
% ROASTTISSUECONFIG Return base and optional passive tissue label metadata.
%
% cfg = roastTissueConfig([]) preserves legacy ROAST behavior:
% labels 1..6 are white, gray, CSF, bone, skin, and air.
%
% Optional extra tissues must start at label 7 and be consecutive. Each
% extra tissue needs a label, name, and conductivityField.

    baseNames = {'WHITE', 'GRAY', 'CSF', 'BONE', 'SKIN', 'AIR'};
    baseConductivityFields = {'white', 'gray', 'csf', 'bone', 'skin', 'air'};

    extras = normalizeExtraTissues(extraTissues);
    cfg = struct();
    cfg.baseCount = numel(baseNames);
    cfg.extraTissues = extras;
    cfg.extraCount = numel(extras);
    cfg.numOfTissue = cfg.baseCount + cfg.extraCount;
    cfg.names = [baseNames, upper({extras.name})];
    cfg.conductivityFields = [baseConductivityFields, {extras.conductivityField}];
    cfg.hasExtraTissues = cfg.extraCount > 0;
end

function extras = normalizeExtraTissues(extraTissues)
    extras = struct('label', {}, 'name', {}, 'conductivityField', {});
    if nargin < 1 || isempty(extraTissues)
        return;
    end
    if isstruct(extraTissues) && isfield(extraTissues, 'extraTissues') && ...
            numel(extraTissues) == 1
        extraTissues = extraTissues.extraTissues;
    end
    if isstruct(extraTissues) && isfield(extraTissues, 'label') && ...
            isfield(extraTissues, 'name') && isfield(extraTissues, 'conductivityField')
        raw = extraTissues(:);
        extras = emptyExtraStruct(numel(raw));
        for i = 1:numel(raw)
            extras(i).label = double(raw(i).label);
            extras(i).name = safeNameLower(raw(i).name);
            extras(i).conductivityField = safeNameLower(raw(i).conductivityField);
        end
    elseif isstruct(extraTissues) && isfield(extraTissues, 'labels') && ...
            isfield(extraTissues, 'names') && isfield(extraTissues, 'conductivityFields')
        labels = double(extraTissues.labels(:));
        names = valuesToCellstr(extraTissues.names);
        fields = valuesToCellstr(extraTissues.conductivityFields);
        if numel(labels) ~= numel(names) || numel(labels) ~= numel(fields)
            error('roastTissueConfig:BadExtraTissues', ...
                'extraTissues labels, names, and conductivityFields must have the same length.');
        end
        extras = emptyExtraStruct(numel(labels));
        for i = 1:numel(labels)
            extras(i).label = labels(i);
            extras(i).name = safeNameLower(names{i});
            extras(i).conductivityField = safeNameLower(fields{i});
        end
    else
        error('roastTissueConfig:BadExtraTissues', ...
            ['extraTissues must be empty, a struct array with label/name/', ...
             'conductivityField, or a struct with labels/names/conductivityFields.']);
    end

    if isempty(extras)
        return;
    end
    labels = [extras.label];
    expected = 7:(6 + numel(extras));
    if any(labels ~= expected)
        error('roastTissueConfig:BadExtraLabels', ...
            'extraTissues labels must be consecutive and start at 7.');
    end
    names = {extras.name};
    fields = {extras.conductivityField};
    if numel(unique(names)) ~= numel(names) || numel(unique(fields)) ~= numel(fields)
        error('roastTissueConfig:DuplicateExtraTissues', ...
            'extraTissues names and conductivity fields must be unique.');
    end
end

function extras = emptyExtraStruct(n)
    extras = repmat(struct('label', [], 'name', '', 'conductivityField', ''), n, 1);
end

function values = valuesToCellstr(values)
    if iscell(values)
        values = cellfun(@char, values(:), 'UniformOutput', false);
    elseif isstring(values)
        values = cellstr(values(:));
    elseif ischar(values)
        values = cellstr(values);
    else
        error('roastTissueConfig:BadExtraTissues', ...
            'extra tissue names and conductivityFields must be text.');
    end
end

function name = safeNameLower(value)
    name = lower(regexprep(char(value), '[^A-Za-z0-9_]', '_'));
    if isempty(name) || ~isletter(name(1))
        error('roastTissueConfig:BadName', ...
            'Extra tissue names and conductivity fields must start with a letter.');
    end
end
