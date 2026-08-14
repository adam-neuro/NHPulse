function out = acsRegisterPolhemusFiducials(polhemusIn, modelFiducials, varargin)
% ACSREGISTERPOLHEMUSFIDUCIALS Register Polhemus points to a model frame.
%
% out = acsRegisterPolhemusFiducials(polhemusSession, modelFiducials)
% extracts Nas/Lpa/Rpa from a Polhemus session and a model fiducial set, then
% estimates a rigid row-vector transform:
%
%   modelMm = polhemusMm * out.rotation + out.translationMm
%
% Inputs can be MAT reports from acsPolhemus, legacy Polhemus text files,
% structs with labels/coordinates, or 3-by-3 numeric fiducial matrices.
% The output applies the fitted transform to every labeled Polhemus point,
% not just the registration fiducials.
%
% Name-value options:
%   fiducialLabels : labels to match [{'Nas','Lpa','Rpa'}]
%   polhemusUnits  : 'auto', 'cm', 'mm', or 'in' ['auto']
%   modelUnits     : 'auto', 'mm', 'cm', or 'in' ['auto']
%   transformType  : 'rigid' or 'similarity' ['rigid']
%   fiducialWeights: positive weights matching fiducialLabels [all ones]
%   outputFile     : optional MAT report ['']
%   verbose        : print registration summary [true]

    if nargin < 2
        error('acsRegisterPolhemusFiducials:MissingInput', ...
            'Provide Polhemus and model fiducials.');
    end

    opts = parseInputs(varargin{:});

    source = readPointSet(polhemusIn, opts.polhemusUnits, 'polhemus', opts);
    target = readPointSet(modelFiducials, opts.modelUnits, 'model', opts);
    source = dropInvalidPointRows(source, 'Polhemus', opts);
    target = dropInvalidPointRows(target, 'model', opts);
    [fiducialLabels, fiducialWeights] = resolveFiducialRequest( ...
        opts.fiducialLabels, opts.fiducialWeights, source.labels, ...
        target.labels);

    [sourceFid, sourceRows] = selectFiducials(source, fiducialLabels, ...
        'Polhemus');
    [targetFid, targetRows] = selectFiducials(target, fiducialLabels, ...
        'model');
    validateFiniteFiducials(sourceFid, targetFid, fiducialLabels);

    fit = fitPointTransform(sourceFid, targetFid, opts.transformType, ...
        fiducialWeights);
    transformed = applyRowTransform(sourceFid, fit.rotation, ...
        fit.translationMm, fit.scale);
    transformedAll = applyRowTransform(source.coordinatesMm, fit.rotation, ...
        fit.translationMm, fit.scale);
    transformedObjects = transformObjects(source.objects, fit);
    residuals = transformed - targetFid;
    errors = sqrt(sum(residuals.^2, 2));

    out = struct();
    out.createdOn = char(datetime('now'));
    out.fiducialLabels = fiducialLabels(:);
    out.fiducialWeights = fiducialWeights(:);
    out.transformType = opts.transformType;
    out.objectiveType = fit.objectiveType;
    out.scale = fit.scale;
    out.rotation = fit.rotation;
    out.translationMm = fit.translationMm;
    out.rowTransform = rowHomogeneousTransform(fit.rotation, ...
        fit.translationMm, fit.scale);
    out.source = source.info;
    out.target = target.info;
    out.sourceRows = sourceRows(:);
    out.targetRows = targetRows(:);
    out.sourceLabels = source.labels(:);
    out.sourcePointsMm = source.coordinatesMm;
    out.transformedSourcePointsMm = transformedAll;
    out.transformedPoints = struct( ...
        'labels', {source.labels(:)}, ...
        'coordinatesMm', transformedAll, ...
        'coordinateFrame', target.info.coordinateFrame);
    out.registeredObjects = transformedObjects;
    out.sourceFiducialsMm = sourceFid;
    out.targetFiducialsMm = targetFid;
    out.transformedSourceFiducialsMm = transformed;
    out.residualsMm = residuals;
    out.errorMm = errors;
    out.rmseMm = sqrt(mean(errors.^2));
    out.weightedRmseMm = sqrt(sum(out.fiducialWeights .* errors(:).^2) / ...
        sum(out.fiducialWeights));
    out.maxErrorMm = max(errors);
    out.instructions = ['Apply to row-vector points in Polhemus millimeters ', ...
        'as Pmodel = Ppolhemus * rotation * scale + translationMm.'];

    if ~isempty(opts.outputFile)
        saveRegistration(out, opts.outputFile);
    end
    if opts.verbose
        printSummary(out);
    end
end

function opts = parseInputs(varargin)
    p = inputParser;
    p.FunctionName = 'acsRegisterPolhemusFiducials';
    addParameter(p, 'fiducialLabels', {'Nas', 'Lpa', 'Rpa'}, ...
        @(x) iscell(x) || isstring(x) || ischar(x));
    addParameter(p, 'polhemusUnits', 'auto', @(x) ischar(x) || isstring(x));
    addParameter(p, 'modelUnits', 'auto', @(x) ischar(x) || isstring(x));
    addParameter(p, 'transformType', 'rigid', @(x) ischar(x) || isstring(x));
    addParameter(p, 'fiducialWeights', [], @isFiducialWeightsLike);
    addParameter(p, 'outputFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'verbose', true, @isBoolLike);
    parse(p, varargin{:});

    opts = p.Results;
    opts.fiducialLabels = normalizeLabelCell(opts.fiducialLabels);
    if isAutoFiducialRequest(opts.fiducialLabels)
        opts.fiducialWeights = double(opts.fiducialWeights(:));
    else
        opts.fiducialWeights = normalizeFiducialWeights( ...
            opts.fiducialWeights, numel(opts.fiducialLabels));
    end
    opts.polhemusUnits = normalizeUnits(opts.polhemusUnits, true);
    opts.modelUnits = normalizeUnits(opts.modelUnits, true);
    opts.transformType = normalizeTransformType(opts.transformType);
    opts.outputFile = expandUserPath(char(opts.outputFile));
    opts.verbose = logical(opts.verbose);
end

function tf = isBoolLike(x)
    tf = (islogical(x) || isnumeric(x)) && isscalar(x);
end

function tf = isFiducialWeightsLike(x)
    tf = isempty(x) || (isnumeric(x) && isvector(x) && ...
        all(isfinite(x(:))) && all(x(:) > 0));
end

function weights = normalizeFiducialWeights(weightsIn, n)
    if isempty(weightsIn)
        weights = ones(n, 1);
        return;
    end
    weights = double(weightsIn(:));
    if numel(weights) ~= n
        error('acsRegisterPolhemusFiducials:BadFiducialWeights', ...
            'fiducialWeights must contain one positive value per fiducial label.');
    end
end

function tf = isAutoFiducialRequest(labels)
    labels = normalizeLabelCell(labels);
    tf = numel(labels) == 1 && any(strcmpi(labels{1}, ...
        {'auto', 'common', 'intersection', 'available'}));
end

function labels = normalizeLabelCell(labelsIn)
    if isempty(labelsIn)
        labels = {};
    elseif iscell(labelsIn)
        labels = cellstr(labelsIn(:));
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

function units = normalizeUnits(unitsIn, allowAuto)
    units = lower(strtrim(char(unitsIn)));
    switch units
        case {'auto', ''}
            if allowAuto
                units = 'auto';
            else
                units = 'mm';
            end
        case {'mm', 'millimeter', 'millimeters'}
            units = 'mm';
        case {'cm', 'centimeter', 'centimeters'}
            units = 'cm';
        case {'in', 'inch', 'inches'}
            units = 'in';
        otherwise
            error('acsRegisterPolhemusFiducials:BadUnits', ...
                'Units must be auto, mm, cm, or in.');
    end
end

function transformType = normalizeTransformType(value)
    transformType = lower(strtrim(char(value)));
    switch transformType
        case {'rigid', 'euclidean'}
            transformType = 'rigid';
        case {'similarity', 'scaledrigid', 'scaled'}
            transformType = 'similarity';
        otherwise
            error('acsRegisterPolhemusFiducials:BadTransformType', ...
                'transformType must be rigid or similarity.');
    end
end

function pointSet = readPointSet(value, requestedUnits, role, opts)
    if isnumeric(value)
        coords = double(value);
        if size(coords, 2) ~= 3
            error('acsRegisterPolhemusFiducials:BadNumericInput', ...
                '%s numeric input must be n-by-3.', role);
        end
        labels = defaultLabels(size(coords, 1), opts.fiducialLabels);
        units = autoUnitsForRole(requestedUnits, role);
        pointSet = makePointSet(labels, coords, units, role, 'numeric');
        return;
    end

    if isstruct(value)
        pointSet = readStructPointSet(value, requestedUnits, role, opts);
        return;
    end

    if ~(ischar(value) || isstring(value))
        error('acsRegisterPolhemusFiducials:BadInput', ...
            '%s input must be numeric, struct, or filename.', role);
    end

    fileName = expandUserPath(char(value));
    if exist(fileName, 'file') ~= 2
        error('acsRegisterPolhemusFiducials:FileNotFound', ...
            '%s file not found: %s', role, fileName);
    end
    [~, ~, ext] = fileparts(fileName);
    switch lower(ext)
        case '.mat'
            S = load(fileName);
            pointSet = readStructPointSet(firstStruct(S), requestedUnits, ...
                role, opts);
            pointSet.info.file = fileName;
        case '.json'
            S = jsondecode(fileread(fileName));
            pointSet = readStructPointSet(S, requestedUnits, role, opts);
            pointSet.info.file = fileName;
        otherwise
            [labels, coords] = readLegacyText(fileName);
            units = autoUnitsForRole(requestedUnits, role);
            pointSet = makePointSet(labels, coords, units, role, fileName);
    end
end

function pointSet = readStructPointSet(S, requestedUnits, role, opts)
    labels = {};
    coords = [];
    units = requestedUnits;

    if isfield(S, 'labels') && ~isempty(S.labels)
        labels = normalizeLabelCell(S.labels);
        [coords, units] = firstCoordinateField(S, units);
    end

    if isempty(coords) && isfield(S, 'referencePoints') && ...
            isstruct(S.referencePoints)
        R = S.referencePoints;
        if isfield(R, 'labels'), labels = normalizeLabelCell(R.labels); end
        [coords, units] = firstCoordinateField(R, units);
    end

    if isempty(coords) && isfield(S, 'fiducials') && isstruct(S.fiducials)
        F = S.fiducials;
        if isfield(F, 'labels'), labels = normalizeLabelCell(F.labels); end
        [coords, units] = firstCoordinateField(F, units);
    end

    if isempty(coords)
        [coords, units] = firstCoordinateField(S, units);
    end

    if isempty(coords) && isfield(S, 'names') && isfield(S, 'layoutCoordinatesMm')
        labels = normalizeLabelCell(S.names);
        coords = double(S.layoutCoordinatesMm);
        units = firstNonAuto(units, 'mm');
    end

    if isempty(coords)
        error('acsRegisterPolhemusFiducials:NoCoordinates', ...
            'Could not find coordinates in %s struct.', role);
    end
    if isempty(labels)
        labels = defaultLabels(size(coords, 1), opts.fiducialLabels);
    end
    pointSet = makePointSet(labels, coords, firstNonAuto(units, ...
        autoUnitsForRole('auto', role)), role, 'struct');
    pointSet.info = addStructMetadata(pointSet.info, S);
    pointSet.objects = readObjectPointSets(S, requestedUnits, role);
end

function [coords, units] = firstCoordinateField(S, requestedUnits)
    coords = [];
    units = requestedUnits;
    fields = { ...
        'coordinatesMm', 'mm'; ...
        'targetFiducialsMm', 'mm'; ...
        'coordinatesCm', 'cm'; ...
        'deviceCoordinatesInches', 'in'; ...
        'coordinates', 'auto'};
    for i = 1:size(fields, 1)
        fieldName = fields{i, 1};
        if isfield(S, fieldName) && ~isempty(S.(fieldName))
            coords = double(S.(fieldName));
            if strcmp(units, 'auto')
                units = fields{i, 2};
            end
            return;
        end
    end
end

function pointSet = makePointSet(labels, coords, units, role, sourceType)
    if size(coords, 2) ~= 3
        error('acsRegisterPolhemusFiducials:BadCoordinates', ...
            '%s coordinates must be n-by-3.', role);
    end
    labels = normalizeLabelCell(labels);
    if numel(labels) ~= size(coords, 1)
        labels = defaultLabels(size(coords, 1), labels);
    end
    units = normalizeUnits(firstNonAuto(units, autoUnitsForRole('auto', role)), false);
    pointSet = struct();
    pointSet.labels = labels;
    pointSet.coordinatesOriginal = double(coords);
    pointSet.unitsOriginal = units;
    pointSet.coordinatesMm = convertToMm(coords, units);
    pointSet.objects = emptyObjects();
    pointSet.info = struct('role', role, 'sourceType', sourceType, ...
        'unitsOriginal', units, 'file', '', 'coordinateFrame', '', ...
        'subjectId', '', 'sessionType', '', 'modelType', '', ...
        'source', []);
end

function pointSet = dropInvalidPointRows(pointSet, roleName, opts)
    if isempty(pointSet.coordinatesMm)
        return;
    end
    keep = all(isfinite(pointSet.coordinatesMm), 2);
    if all(keep)
        return;
    end
    dropped = pointSet.labels(~keep);
    pointSet.labels = pointSet.labels(keep);
    pointSet.coordinatesOriginal = pointSet.coordinatesOriginal(keep, :);
    pointSet.coordinatesMm = pointSet.coordinatesMm(keep, :);
    if opts.verbose
        warning('acsRegisterPolhemusFiducials:DroppedInvalidFiducials', ...
            'Ignoring %s fiducial row(s) with non-finite coordinates: %s', ...
            roleName, strjoin(dropped(:)', ', '));
    end
end

function info = addStructMetadata(info, S)
    if isfield(S, 'coordinateFrame') && ~isempty(S.coordinateFrame)
        info.coordinateFrame = char(S.coordinateFrame);
    end
    if isfield(S, 'subjectId') && ~isempty(S.subjectId)
        info.subjectId = char(S.subjectId);
    end
    if isfield(S, 'sessionType') && ~isempty(S.sessionType)
        info.sessionType = char(S.sessionType);
    end
    if isfield(S, 'modelType') && ~isempty(S.modelType)
        info.modelType = char(S.modelType);
    end
    if isfield(S, 'source')
        info.source = S.source;
    end
end

function objects = emptyObjects()
    objects = repmat(struct( ...
        'name', '', ...
        'labels', {{}}, ...
        'rows', [], ...
        'coordinatesMm', [], ...
        'transformedCoordinatesMm', [], ...
        'coordinateFrame', ''), 0, 1);
end

function objects = readObjectPointSets(S, requestedUnits, role)
    objects = emptyObjects();
    if ~isfield(S, 'objects') || isempty(S.objects) || ~isstruct(S.objects)
        return;
    end
    rawObjects = S.objects;
    for i = 1:numel(rawObjects)
        [coords, units] = firstCoordinateField(rawObjects(i), requestedUnits);
        if isempty(coords)
            continue;
        end
        units = firstNonAuto(units, autoUnitsForRole('auto', role));
        obj = emptyObjects();
        obj(1).name = objectName(rawObjects(i), i);
        if isfield(rawObjects(i), 'labels') && ~isempty(rawObjects(i).labels)
            obj(1).labels = normalizeLabelCell(rawObjects(i).labels);
        else
            obj(1).labels = defaultLabels(size(coords, 1), {});
        end
        if isfield(rawObjects(i), 'startIndex') && isfield(rawObjects(i), 'endIndex')
            obj(1).rows = rawObjects(i).startIndex:rawObjects(i).endIndex;
        elseif isfield(rawObjects(i), 'rows')
            obj(1).rows = rawObjects(i).rows;
        end
        obj(1).coordinatesMm = convertToMm(coords, units);
        obj(1).coordinateFrame = '';
        objects(end + 1, 1) = obj; %#ok<AGROW>
    end
end

function name = objectName(S, index)
    candidates = {'name', 'label', 'objectLabel', 'type'};
    name = '';
    for i = 1:numel(candidates)
        if isfield(S, candidates{i}) && ~isempty(S.(candidates{i}))
            name = char(S.(candidates{i}));
            return;
        end
    end
    name = sprintf('object%d', index);
end

function labels = defaultLabels(n, preferred)
    labels = cell(n, 1);
    for i = 1:n
        if i <= numel(preferred)
            labels{i} = preferred{i};
        else
            labels{i} = sprintf('point%d', i);
        end
    end
end

function units = autoUnitsForRole(requestedUnits, role)
    if ~strcmp(requestedUnits, 'auto')
        units = requestedUnits;
    elseif strcmpi(role, 'polhemus')
        units = 'cm';
    else
        units = 'mm';
    end
end

function units = firstNonAuto(units, fallback)
    if isempty(units) || strcmp(units, 'auto')
        units = fallback;
    end
end

function coordsMm = convertToMm(coords, units)
    switch normalizeUnits(units, false)
        case 'mm'
            coordsMm = double(coords);
        case 'cm'
            coordsMm = double(coords) * 10;
        case 'in'
            coordsMm = double(coords) * 25.4;
        otherwise
            error('acsRegisterPolhemusFiducials:BadUnits', ...
                'Unsupported units: %s', units);
    end
end

function [labels, coords] = readLegacyText(fileName)
    lines = regexp(fileread(fileName), '\r?\n', 'split');
    labels = {};
    coords = [];
    for i = 1:numel(lines)
        line = strtrim(lines{i});
        if isempty(line), continue; end
        parts = regexp(line, '[,\t ]+', 'split');
        if numel(parts) < 4, continue; end
        xyz = str2double(parts(2:4));
        if any(~isfinite(xyz)), continue; end
        labels{end + 1, 1} = parts{1}; %#ok<AGROW>
        coords(end + 1, :) = xyz; %#ok<AGROW>
    end
end

function [fid, rows] = selectFiducials(pointSet, fiducialLabels, roleName)
    rows = zeros(numel(fiducialLabels), 1);
    labelNorm = normalizeLabels(pointSet.labels);
    used = false(numel(labelNorm), 1);
    for i = 1:numel(fiducialLabels)
        aliases = requestedFiducialAliases(fiducialLabels{i});
        for a = 1:numel(aliases)
            hit = find(strcmp(labelNorm, aliases{a}) & ~used, 1);
            if ~isempty(hit)
                rows(i) = hit;
                used(hit) = true;
                break;
            end
        end
    end
    if any(rows == 0)
        missing = fiducialLabels(rows == 0);
        error('acsRegisterPolhemusFiducials:MissingFiducials', ...
            '%s fiducial set is missing: %s', roleName, strjoin(missing, ', '));
    end
    fid = pointSet.coordinatesMm(rows, :);
end

function validateFiniteFiducials(sourceFid, targetFid, fiducialLabels)
    badSource = ~all(isfinite(sourceFid), 2);
    badTarget = ~all(isfinite(targetFid), 2);
    if any(badSource) || any(badTarget)
        pieces = {};
        if any(badSource)
            pieces{end + 1} = sprintf('source: %s', ...
                strjoin(fiducialLabels(badSource), ', ')); %#ok<AGROW>
        end
        if any(badTarget)
            pieces{end + 1} = sprintf('target: %s', ...
                strjoin(fiducialLabels(badTarget), ', ')); %#ok<AGROW>
        end
        error('acsRegisterPolhemusFiducials:NonfiniteFiducials', ...
            'Cannot register with non-finite fiducial coordinates (%s).', ...
            strjoin(pieces, '; '));
    end
end

function [labels, weights] = resolveFiducialRequest( ...
        requestedLabels, requestedWeights, sourceLabels, targetLabels)
    if isAutoFiducialRequest(requestedLabels)
        labels = commonFiducialLabels(sourceLabels, targetLabels);
        if numel(labels) < 3
            error('acsRegisterPolhemusFiducials:TooFewCommonFiducials', ...
                ['Auto fiducial matching found only %d common labels; ', ...
                 'at least 3 are required for rigid registration.'], ...
                numel(labels));
        end
        if isempty(requestedWeights)
            weights = ones(numel(labels), 1);
        elseif isscalar(requestedWeights)
            weights = repmat(double(requestedWeights), numel(labels), 1);
        else
            error('acsRegisterPolhemusFiducials:AutoWeightsNeedScalar', ...
                ['When fiducialLabels is auto/common, fiducialWeights ', ...
                 'must be empty or scalar.']);
        end
        return;
    end
    [labels, keep, missingSource, missingTarget] = ...
        availableRequestedFiducials(requestedLabels, sourceLabels, targetLabels);
    if ~isempty(missingSource) || ~isempty(missingTarget)
        if numel(labels) < 3
            error('acsRegisterPolhemusFiducials:TooFewAvailableFiducials', ...
                ['Requested fiducials do not overlap enough for rigid ', ...
                 'registration. Available overlap: %s. Missing from ', ...
                 'Polhemus: %s. Missing from model: %s. Polhemus labels read: %s. ', ...
                 'Model labels read: %s.'], ...
                labelListText(labels), labelListText(missingSource), ...
                labelListText(missingTarget), labelListText(sourceLabels), ...
                labelListText(targetLabels));
        end
        warning('acsRegisterPolhemusFiducials:UsingFiducialOverlap', ...
            ['Using %d overlapping fiducials for registration: %s. ', ...
             'Missing from Polhemus: %s. Missing from model: %s. ', ...
             'Polhemus labels read: %s. Model labels read: %s.'], ...
            numel(labels), labelListText(labels), ...
            labelListText(missingSource), labelListText(missingTarget), ...
            labelListText(sourceLabels), labelListText(targetLabels));
    end
    weights = normalizeSubsetWeights(requestedWeights, numel(requestedLabels), keep);
end

function labels = commonFiducialLabels(sourceLabels, targetLabels)
    try
        candidates = normalizeLabelCell(acsMonkeyLandmarkBullpen('labels'));
    catch
        candidates = {'Nas'; 'Lpa'; 'Rpa'};
    end
    labels = {};
    for i = 1:numel(candidates)
        sourceHit = findLabelAliasMatch(candidates{i}, sourceLabels);
        targetHit = findLabelAliasMatch(candidates{i}, targetLabels);
        if ~isempty(sourceHit) && ~isempty(targetHit)
            labels{end + 1, 1} = candidates{i}; %#ok<AGROW>
        end
    end
end

function [labels, keep, missingSource, missingTarget] = ...
        availableRequestedFiducials(requestedLabels, sourceLabels, targetLabels)
    requestedLabels = requestedLabels(:);
    keep = false(numel(requestedLabels), 1);
    missingSource = {};
    missingTarget = {};
    for i = 1:numel(requestedLabels)
        sourceHit = findLabelAliasMatch(requestedLabels{i}, sourceLabels);
        targetHit = findLabelAliasMatch(requestedLabels{i}, targetLabels);
        if ~isempty(sourceHit) && ~isempty(targetHit)
            keep(i) = true;
        else
            if isempty(sourceHit)
                missingSource{end + 1, 1} = requestedLabels{i}; %#ok<AGROW>
            end
            if isempty(targetHit)
                missingTarget{end + 1, 1} = requestedLabels{i}; %#ok<AGROW>
            end
        end
    end
    labels = requestedLabels(keep);
end

function weights = normalizeSubsetWeights(weightsIn, nRequested, keep)
    if isempty(weightsIn)
        weights = ones(nnz(keep), 1);
        return;
    end
    weightsIn = double(weightsIn(:));
    if isscalar(weightsIn)
        weights = repmat(weightsIn, nnz(keep), 1);
        return;
    end
    if numel(weightsIn) ~= nRequested
        error('acsRegisterPolhemusFiducials:BadFiducialWeights', ...
            'fiducialWeights must be scalar or contain one value per requested fiducial label.');
    end
    weights = weightsIn(keep);
end

function txt = labelListText(labels)
    labels = normalizeLabelCell(labels);
    if isempty(labels)
        txt = '(none)';
    else
        txt = strjoin(labels(:)', ', ');
    end
end

function hit = findLabelAliasMatch(label, candidateLabels)
    hit = [];
    candidateNorm = normalizeLabels(candidateLabels);
    aliases = requestedFiducialAliases(label);
    for i = 1:numel(aliases)
        hit = find(strcmp(candidateNorm, aliases{i}), 1);
        if ~isempty(hit)
            return;
        end
    end
end

function aliases = requestedFiducialAliases(label)
    exact = normalizeLabels({label});
    expanded = normalizeLabels(fiducialAliases(label));
    aliases = [exact(:); expanded(:)];
    aliases = unique(aliases, 'stable');
end

function labels = normalizeLabels(labelsIn)
    labels = cellfun(@lower, normalizeLabelCell(labelsIn), ...
        'UniformOutput', false);
    labels = regexprep(labels, '[^a-z0-9]', '');
end

function aliases = fiducialAliases(label)
    try
        aliases = acsMonkeyLandmarkBullpen('aliasesFor', label);
        if ~isempty(aliases)
            return;
        end
    catch
        % Fall through to built-in essentials if the bullpen is unavailable.
    end
    key = regexprep(lower(char(label)), '[^a-z0-9]', '');
    switch key
        case {'nas', 'nasion'}
            aliases = {'Nas', 'Nasion'};
        case {'lpa', 'leftpreauricular', 'leftpa'}
            aliases = {'Lpa', 'LeftPA', 'LeftPreauricular', ...
                'LeftPreauricularNotch'};
        case {'rpa', 'rightpreauricular', 'rightpa'}
            aliases = {'Rpa', 'RightPA', 'RightPreauricular', ...
                'RightPreauricularNotch'};
        otherwise
            aliases = {label};
    end
end

function fit = fitPointTransform(source, target, transformType, weights)
    weights = double(weights(:));
    weights = weights ./ sum(weights);
    sourceCentroid = sum(bsxfun(@times, source, weights), 1);
    targetCentroid = sum(bsxfun(@times, target, weights), 1);
    X = bsxfun(@minus, source, sourceCentroid);
    Y = bsxfun(@minus, target, targetCentroid);
    H = X' * bsxfun(@times, Y, weights);
    [U, S, V] = svd(H);
    reflectionSign = 1;
    R = U * V';
    if det(R) < 0
        reflectionSign = -1;
        U(:, end) = -U(:, end);
        R = U * V';
    end
    switch transformType
        case 'similarity'
            denom = sum(weights .* sum(X .^ 2, 2));
            if denom <= eps
                error('acsRegisterPolhemusFiducials:DegenerateSourceFiducials', ...
                    'Cannot estimate scale from degenerate source fiducials.');
            end
            scaleTerms = diag(S);
            scaleTerms(end) = scaleTerms(end) * reflectionSign;
            scale = sum(scaleTerms) / denom;
        otherwise
            scale = 1;
    end
    t = targetCentroid - scale * sourceCentroid * R;
    fit = struct( ...
        'rotation', R, ...
        'translationMm', t, ...
        'scale', scale, ...
        'objectiveType', ...
        'weighted row-vector least-squares rigid/similarity');
end

function transformed = applyRowTransform(points, R, t, scale)
    transformed = scale * double(points) * R + t;
end

function objects = transformObjects(objectsIn, fit)
    objects = objectsIn;
    for i = 1:numel(objects)
        if ~isempty(objects(i).coordinatesMm)
            objects(i).transformedCoordinatesMm = applyRowTransform( ...
                objects(i).coordinatesMm, fit.rotation, fit.translationMm, ...
                fit.scale);
            objects(i).coordinateFrame = 'model';
        end
    end
end

function T = rowHomogeneousTransform(R, t, scale)
    T = eye(4);
    T(1:3, 1:3) = scale * R;
    T(4, 1:3) = t;
end

function saveRegistration(out, outputFile)
    ensureDir(fileparts(outputFile));
    save(outputFile, 'out');
    [folder, stem] = fileparts(outputFile);
    jsonFile = fullfile(folder, [stem '.json']);
    writeJson(jsonFile, jsonReady(out));
end

function writeJson(fileName, S)
    fid = fopen(fileName, 'wt');
    if fid < 0
        error('acsRegisterPolhemusFiducials:CouldNotWriteJson', ...
            'Could not write %s', fileName);
    end
    cleaner = onCleanup(@() fclose(fid));
    try
        txt = jsonencode(S, 'PrettyPrint', true);
    catch
        txt = jsonencode(S);
    end
    fprintf(fid, '%s', txt);
    clear cleaner;
end

function S = jsonReady(S)
    if isstruct(S)
        for k = 1:numel(S)
            names = fieldnames(S(k));
            for i = 1:numel(names)
                S(k).(names{i}) = jsonReady(S(k).(names{i}));
            end
        end
    elseif iscell(S)
        for i = 1:numel(S)
            S{i} = jsonReady(S{i});
        end
    end
end

function printSummary(out)
    fprintf('\nPolhemus fiducial registration\n');
    fprintf('  transform: %s', out.transformType);
    if strcmp(out.transformType, 'similarity')
        fprintf(' (scale %.8g)', out.scale);
    end
    fprintf('\n');
    fprintf('  fiducials: %s\n', strjoin(out.fiducialLabels, ', '));
    if any(abs(out.fiducialWeights - out.fiducialWeights(1)) > eps)
        weightText = cell(numel(out.fiducialLabels), 1);
        for i = 1:numel(out.fiducialLabels)
            weightText{i} = sprintf('%s=%.4g', out.fiducialLabels{i}, ...
                out.fiducialWeights(i));
        end
        fprintf('  fiducial weights: %s\n', strjoin(weightText, ', '));
    end
    fprintf('  source rows: %s\n', sprintf('%d ', out.sourceRows));
    fprintf('  target rows: %s\n', sprintf('%d ', out.targetRows));
    fprintf('  transformed points: %d\n', size(out.transformedSourcePointsMm, 1));
    if isfield(out, 'objectiveType') && ~isempty(out.objectiveType)
        fprintf('  objective: %s\n', out.objectiveType);
    end
    if ~isempty(out.target.coordinateFrame)
        fprintf('  target frame: %s\n', out.target.coordinateFrame);
    end
    fprintf('  RMSE: %.4g mm\n', out.rmseMm);
    fprintf('  weighted RMSE: %.4g mm\n', out.weightedRmseMm);
    fprintf('  max error: %.4g mm\n', out.maxErrorMm);
    for i = 1:numel(out.fiducialLabels)
        fprintf('    %s: %.4g mm\n', out.fiducialLabels{i}, out.errorMm(i));
    end
    if ~isempty(out.registeredObjects)
        fprintf('  registered object traces: %d\n', numel(out.registeredObjects));
    end
    fprintf('\n');
end

function value = firstStruct(S)
    preferred = {'out', 'session', 'registration'};
    for i = 1:numel(preferred)
        if isfield(S, preferred{i}) && isstruct(S.(preferred{i}))
            value = S.(preferred{i});
            return;
        end
    end
    names = fieldnames(S);
    for i = 1:numel(names)
        if isstruct(S.(names{i}))
            value = S.(names{i});
            return;
        end
    end
    error('acsRegisterPolhemusFiducials:NoStructInMat', ...
        'MAT file does not contain a readable struct.');
end

function ensureDir(folder)
    if isempty(folder), return; end
    if exist(folder, 'dir') ~= 7
        mkdir(folder);
    end
end

function pathOut = expandUserPath(pathOut)
    if isempty(pathOut)
        return;
    end
    pathOut = char(pathOut);
    if startsWith(pathOut, '~')
        homeDir = getenv('HOME');
        if isempty(homeDir)
            homeDir = getenv('USERPROFILE');
        end
        if numel(pathOut) == 1
            pathOut = homeDir;
        elseif pathOut(2) == filesep || pathOut(2) == '/' || pathOut(2) == '\'
            pathOut = fullfile(homeDir, pathOut(3:end));
        end
    end
end
