function output = nhpulseServiceBuildCandidateLayout(context, inputs, config)
% NHPULSESERVICEBUILDCANDIDATELAYOUT Build/register a candidate tES layout.

    if nargin < 3, config = struct(); end
    nhpulseServiceInternal('validateContext', context);
    anatomy = resolveRequired(context, inputs, 'anatomy', 'nhpulse.anatomy');
    segmentation = resolveRequired(context, inputs, 'segmentation', ...
        'nhpulse.segmentation');
    scalp = resolveRequired(context, inputs, 'scalp', 'nhpulse.scalpModel');
    exclusion = resolveOptional(context, inputs, 'anatomicalExclusion', ...
        'nhpulse.exclusion');
    implants = resolveMany(context, inputs, 'implantExclusions', ...
        'nhpulse.exclusion');
    key = nhpulseServiceInternal('field', config, ...
        'artifactKey', 'candidate-layout');
    outputFile = nhpulseServiceInternal('field', config, 'outputFile', ...
        nhpulseServiceInternal('outputPath', context, 'layout', ...
        'candidate_customLocations'));
    targetOptions = nhpulseServiceInternal('field', config, ...
        'targetOptions', struct());
    if ~isempty(implants)
        files = {implants.path};
        [centers, radii] = acsPlacementExclusionsFromImplantFiles(files, ...
            'verbose', false);
        targetOptions.exclusionCenters = centers;
        targetOptions.exclusionRadiusMM = radii;
    end
    args = nhpulseServiceInternal('options', ...
        nhpulseServiceInternal('field', config, 'engineOptions', struct()));
    earFile = '';
    earMode = 'never';
    if ~isempty(exclusion)
        earFile = exclusion.path;
    end
    result = acsMakeRoastCapMakerLayout(anatomy.path, args{:}, ...
        'maskFile', segmentation.path, 'surfaceSource', 'capMaker', ...
        'skinCacheFile', scalp.path, ...
        'nElectrodes', nhpulseServiceInternal('field', config, 'nElectrodes', 16), ...
        'outputFile', outputFile, 'targetOptions', targetOptions, ...
        'earExclusionMode', earMode, 'earExclusionFile', earFile, ...
        'forceLayout', nhpulseServiceInternal('field', config, 'force', false), ...
        'showFigures', nhpulseServiceInternal('field', config, 'showFigures', true), ...
        'saveFigures', nhpulseServiceInternal('field', config, 'saveFigures', true), ...
        'verbose', nhpulseServiceInternal('field', config, 'verbose', true));
    parentHandles = [{scalp}, {segmentation}, wrapOptional(exclusion), ...
        num2cell(implants)];
    [parentKeys, parentRoles] = parentInfo(parentHandles);
    [record, handle] = nhpulseServiceInternal('record', context, key, ...
        'nhpulse.candidateLayout', result.reportMat, ...
        'label', 'Candidate tES layout', 'parentKeys', parentKeys, ...
        'parentRoles', parentRoles);
    output = nhpulseServiceInternal('result', 'buildCandidateLayout', context, ...
        result, struct('layout', handle, 'records', record), config);
end

function handle = resolveRequired(context, inputs, name, type)
    if ~isstruct(inputs) || ~isfield(inputs, name) || isempty(inputs.(name))
        error('nhpulseServiceBuildCandidateLayout:MissingInput', ...
            'inputs.%s is required.', name);
    end
    handle = nhpulseServiceInternal('resolve', context, inputs.(name), ...
        'expectedType', type);
end

function handle = resolveOptional(context, inputs, name, type)
    handle = [];
    if isstruct(inputs) && isfield(inputs, name) && ~isempty(inputs.(name))
        handle = nhpulseServiceInternal('resolve', context, inputs.(name), ...
            'expectedType', type);
    end
end

function handles = resolveMany(context, inputs, name, type)
    handles = repmat(struct(), 0, 1);
    if ~isstruct(inputs) || ~isfield(inputs, name) || isempty(inputs.(name))
        return;
    end
    refs = inputs.(name);
    if ~iscell(refs), refs = num2cell(refs); end
    for i = 1:numel(refs)
        handles(i, 1) = nhpulseServiceInternal('resolve', context, refs{i}, ...
            'expectedType', type);
    end
end

function value = wrapOptional(value)
    if isempty(value), value = {}; else, value = {value}; end
end

function [keys, roles] = parentInfo(handles)
    handles = handles(~cellfun(@isempty, handles));
    keys = cellfun(@(x) x.artifactKey, handles, 'UniformOutput', false);
    roles = cell(size(keys));
    for i = 1:numel(handles)
        switch handles{i}.type
            case 'nhpulse.scalpModel', roles{i} = 'placementSurface';
            case 'nhpulse.segmentation', roles{i} = 'tissueSegmentation';
            otherwise, roles{i} = 'exclusion';
        end
    end
end
