function output = nhpulseServiceBuildFitCheck(context, inputs, config)
% NHPULSESERVICEBUILDFITCHECK Build/register a sparse PLA fit-check STL.

    if nargin < 3, config = struct(); end
    nhpulseServiceInternal('validateContext', context);
    layout = resolveRequired(context, inputs, 'layout', ...
        {'nhpulse.candidateLayout', 'nhpulse.combinedLayout'});
    scalp = resolveRequired(context, inputs, 'scalp', 'nhpulse.scalpModel');
    exclusion = resolveOptional(context, inputs, 'anatomicalExclusion', ...
        'nhpulse.exclusion');
    implants = resolveMany(context, inputs, 'implantExclusions', ...
        'nhpulse.exclusion');
    layoutValue = nhpulseServiceInternal('loadValue', layout);
    outputDir = nhpulseServiceInternal('field', config, 'outputDir', ...
        fileparts(nhpulseServiceInternal('outputPath', context, ...
        'fitCheck', 'placeholder')));
    args = nhpulseServiceInternal('options', ...
        nhpulseServiceInternal('field', config, 'engineOptions', struct()));
    earFile = '';
    if ~isempty(exclusion), earFile = exclusion.path; end
    result = acsBuildCapMakerFitCheckStl(layoutValue, args{:}, ...
        'skinCacheFile', scalp.path, 'outputDir', outputDir, ...
        'fitCheckTag', nhpulseServiceInternal('field', config, ...
        'fitCheckTag', [context.runId '_fitCheck']), ...
        'earExclusionMode', 'never', 'earExclusionFile', earFile, ...
        'implantExclusionFile', {implants.path}, ...
        'force', nhpulseServiceInternal('field', config, 'force', false), ...
        'showFigures', nhpulseServiceInternal('field', config, 'showFigures', true), ...
        'saveFigures', nhpulseServiceInternal('field', config, 'saveFigures', true), ...
        'verbose', nhpulseServiceInternal('field', config, 'verbose', true));
    parentKeys = {layout.artifactKey, scalp.artifactKey};
    parentRoles = {'markerLayout', 'manufacturingSurface'};
    if ~isempty(exclusion)
        parentKeys{end + 1} = exclusion.artifactKey;
        parentRoles{end + 1} = 'anatomicalExclusions';
    end
    for i = 1:numel(implants)
        parentKeys{end + 1} = implants(i).artifactKey; %#ok<AGROW>
        parentRoles{end + 1} = 'implantKeepout'; %#ok<AGROW>
    end
    key = nhpulseServiceInternal('field', config, ...
        'artifactKey', 'fit-check-stl');
    [record, handle] = nhpulseServiceInternal('record', context, key, ...
        'nhpulse.fitCheck', result.stlFile, 'label', 'Sparse PLA fit-check STL', ...
        'parentKeys', parentKeys, 'parentRoles', parentRoles);
    output = nhpulseServiceInternal('result', 'buildFitCheck', context, ...
        result, struct('fitCheck', handle, 'records', record), config);
end

function handle = resolveRequired(context, inputs, name, type)
    if ~isstruct(inputs) || ~isfield(inputs, name) || isempty(inputs.(name))
        error('nhpulseServiceBuildFitCheck:MissingInput', 'inputs.%s is required.', name);
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
    if ~isstruct(inputs) || ~isfield(inputs, name) || isempty(inputs.(name)), return; end
    refs = inputs.(name); if ~iscell(refs), refs = num2cell(refs); end
    for i = 1:numel(refs)
        handles(i, 1) = nhpulseServiceInternal('resolve', context, refs{i}, ...
            'expectedType', type);
    end
end
