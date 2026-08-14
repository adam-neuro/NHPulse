function out = acsMonkeyLandmarkBullpen(request, varargin)
% ACSMONKEYLANDMARKBULLPEN Standard macaque digitization landmark candidates.
%
% labels = acsMonkeyLandmarkBullpen('labels') returns a stable ordered label
% list for Polhemus prompts and model-fiducial selection. The default output
% is a struct array with labels, aliases, display names, descriptions, and
% suggested use notes.

if nargin < 1 || isempty(request)
    request = 'struct';
end
request = lower(strtrim(char(request)));

items = [ ...
    item('Nas', {'Nasion'}, ...
        'Nasion', 'Midline nasal/frontal landmark.', 'anatomical'), ...
    item('Lpa', {'LeftPA', 'LeftPreauricular', 'LeftPreauricularNotch'}, ...
        'Left preauricular', 'Left preauricular notch region.', 'anatomical'), ...
    item('Rpa', {'RightPA', 'RightPreauricular', 'RightPreauricularNotch'}, ...
        'Right preauricular', 'Right preauricular notch region.', 'anatomical'), ...
    item('NostrilSeptum', {'Sep', 'Septum', 'Columella'}, ...
        'Nostril septum', 'Septum/columella point between nostrils.', 'anatomical'), ...
    item('LeftOuterCanthus', {'Loc', 'LeftCanthus', 'LeftLateralCanthus'}, ...
        'Left outer canthus', 'Lateral corner of the left eye.', 'anatomical'), ...
    item('RightOuterCanthus', {'Roc', 'RightCanthus', 'RightLateralCanthus'}, ...
        'Right outer canthus', 'Lateral corner of the right eye.', 'anatomical'), ...
    item('Inion', {'Ini'}, ...
        'Inion', 'Midline occipital landmark if identifiable.', 'anatomical'), ...
    item('headpost1', {'HeadPost1', 'HP1'}, ...
        'Headpost point 1', 'Repeatable hole or point on the implanted headpost.', 'sessionReference'), ...
    item('headpost2', {'HeadPost2', 'HP2'}, ...
        'Headpost point 2', 'Second repeatable hole or point on the implanted headpost.', 'sessionReference'), ...
    item('rightChairPoint', {'RightChair', 'RChair'}, ...
        'Right chair point', 'Repeatable point on the right side of the chair.', 'sessionReference'), ...
    item('leftChairPoint', {'LeftChair', 'LChair'}, ...
        'Left chair point', 'Repeatable point on the left side of the chair.', 'sessionReference'), ...
    item('topChairPoint', {'TopChair', 'ChairTop'}, ...
        'Top chair point', 'Repeatable superior point on the chair.', 'sessionReference') ...
    ];

switch request
    case {'struct', 'items', 'all'}
        out = items;
    case {'labels', 'alllabels'}
        out = {items.label};
    case {'display', 'displaylabels', 'displaynames'}
        out = arrayfun(@(x) sprintf('%s - %s', x.label, x.displayName), ...
            items, 'UniformOutput', false);
    case {'aliases', 'aliaspairs', 'aliasmap'}
        out = aliasPairs(items);
    case {'aliasesfor', 'aliasfor'}
        if isempty(varargin)
            error('acsMonkeyLandmarkBullpen:MissingLabel', ...
                'aliasesFor requires a landmark label.');
        end
        out = aliasesFor(varargin{1}, items);
    case {'canonical', 'canonicalize', 'resolve'}
        if isempty(varargin)
            out = {items.label};
        else
            out = canonicalizeLabels(varargin{1}, items);
        end
    case {'anatomical', 'anatomicallabels'}
        keep = strcmp({items.role}, 'anatomical');
        out = {items(keep).label};
    case {'sessionreference', 'sessionreferences', 'referencelabels'}
        keep = strcmp({items.role}, 'sessionReference');
        out = {items(keep).label};
    otherwise
        error('acsMonkeyLandmarkBullpen:BadRequest', ...
            'Unknown request "%s". Use struct, labels, display, anatomical, or sessionReference.', ...
            request);
end
end

function S = item(label, aliases, displayName, description, role)
aliases = normalizeLabelCell(aliases);
aliases = unique([{label}; aliases(:)], 'stable');
S = struct('label', label, ...
    'aliases', {aliases(:)'}, ...
    'displayName', displayName, ...
    'description', description, ...
    'role', role);
end

function pairs = aliasPairs(items)
pairs = cell(0, 2);
for i = 1:numel(items)
    aliases = items(i).aliases;
    for j = 1:numel(aliases)
        pairs(end + 1, :) = {aliases{j}, items(i).label}; %#ok<AGROW>
    end
end
end

function aliases = aliasesFor(labelIn, items)
labels = normalizeLabelCell(labelIn);
aliases = {};
for i = 1:numel(labels)
    idx = itemIndexForLabel(labels{i}, items);
    if isempty(idx)
        aliases = [aliases; labels(i)]; %#ok<AGROW>
    else
        aliases = [aliases; items(idx).aliases(:)]; %#ok<AGROW>
    end
end
aliases = unique(aliases, 'stable');
end

function labelsOut = canonicalizeLabels(labelsIn, items)
labels = normalizeLabelCell(labelsIn);
labelsOut = labels;
for i = 1:numel(labels)
    idx = itemIndexForLabel(labels{i}, items);
    if ~isempty(idx)
        labelsOut{i} = items(idx).label;
    end
end
end

function idx = itemIndexForLabel(label, items)
idx = [];
key = normalizeKey(label);
for i = 1:numel(items)
    aliasKeys = cellfun(@normalizeKey, items(i).aliases, ...
        'UniformOutput', false);
    if any(strcmp(key, aliasKeys))
        idx = i;
        return;
    end
end
end

function key = normalizeKey(label)
key = regexprep(lower(char(label)), '[^a-z0-9]', '');
end

function labels = normalizeLabelCell(labelsIn)
if isempty(labelsIn)
    labels = {};
elseif iscell(labelsIn)
    labels = cellfun(@char, labelsIn(:), 'UniformOutput', false);
elseif isstring(labelsIn)
    labels = cellstr(labelsIn(:));
elseif ischar(labelsIn)
    if size(labelsIn, 1) == 1
        labels = {strtrim(labelsIn)};
    else
        labels = cellstr(labelsIn);
    end
else
    labels = cellstr(labelsIn(:));
end
labels = labels(:);
end
