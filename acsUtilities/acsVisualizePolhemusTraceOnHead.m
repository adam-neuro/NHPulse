function out = acsVisualizePolhemusTraceOnHead(polhemusIn, modelFiducials, varargin)
% ACSVISUALIZEPOLHEMUSTRACEONHEAD Overlay saved digitizer traces on a head mesh.
%
% out = acsVisualizePolhemusTraceOnHead(polhemusSession, modelFiducials)
% registers a saved digitizer session to modelFiducials with
% acsRegisterPolhemusFiducials, then plots the transformed trace points on
% the uncropped capMaker full-head mesh.
%
% polhemusSession can be a MAT/JSON/TXT point-set report or an existing
% acsRegisterPolhemusFiducials output. modelFiducials is typically the
% acsSelectModelFiducials output made from meshStage='fullHead'.
%
% Name-value options:
%   fiducialLabels         : registration labels [{'Nas','Lpa','Rpa'}]
%   transformType          : 'rigid' or 'similarity' ['rigid']
%   fiducialWeights        : positive weights matching fiducialLabels [ones]
%   registrationOutputFile : optional MAT output for fresh registrations ['']
%   meshStage              : 'fullHead' or 'cap' ['fullHead']
%   displayMaxFaces        : display mesh decimation target [35000]
%   meshAlpha              : head mesh opacity [0.55]
%   meshLighting           : 'flat', 'gouraud', or 'none' ['flat']
%   showLabels             : label fiducials and trace endpoints [true]
%   showPointLabels        : label every trace point [false]
%   showFigures            : show figure [true]
%   saveFigures            : save figure [false]
%   closeFigure            : close figure before returning [false]
%   manualStepMm           : arrow/U/D translation step in mm [0.5]
%   manualRotationStepDeg  : P/R/Y rotation step in degrees [1]
%   manualRefinementFile   : default MAT/JSON manual refinement output ['']
%   verbose                : print summary [true]

    if nargin < 1 || isempty(polhemusIn)
        error('acsVisualizePolhemusTraceOnHead:MissingInput', ...
            'Provide a Polhemus session or registration output.');
    end
    if nargin < 2
        modelFiducials = [];
    end

    opts = parseInputs(varargin{:});
    [registration, meshSeed] = resolveRegistration(polhemusIn, ...
        modelFiducials, opts);
    warnIfLegacyRegistrationConvention(registration);
    if isfield(registration, 'fiducialLabels') && ...
            ~isempty(registration.fiducialLabels)
        opts.fiducialLabels = normalizeLabelCell(registration.fiducialLabels);
        if isfield(registration, 'fiducialWeights') && ...
                ~isempty(registration.fiducialWeights)
            opts.fiducialWeights = double(registration.fiducialWeights(:));
        end
    end
    [TRhead, meshSource] = readHeadMesh(meshSeed, opts);
    modelFiducialsForPlot = resolveModelFiducialsForPlot(modelFiducials, ...
        registration, opts);
    checkRegistrationTargetFiducials(registration, modelFiducialsForPlot);

    points = double(registration.transformedSourcePointsMm);
    labels = normalizeLabelCell(registration.sourceLabels);
    if numel(labels) ~= size(points, 1)
        labels = defaultLabels(size(points, 1));
    end
    fidRows = registrationFiducialRows(registration, labels, ...
        opts.fiducialLabels);
    protectedRows = protectedFiducialRows(registration, labels, fidRows, ...
        opts.fiducialLabels);
    traceSets = buildTraceSets(registration, labels, points, protectedRows, ...
        opts.fiducialLabels);

    distances = nearestVertexDistances(points, double(TRhead.Points));
    traceRows = unique(allTraceRows(traceSets));
    overlappingRows = intersect(traceRows(:), protectedRows(:));
    if ~isempty(overlappingRows)
        warning('acsVisualizePolhemusTraceOnHead:FiducialInTrace', ...
            ['Trace rows include registration fiducial rows: %s. ', ...
             'This should not happen for fallback non-object traces.'], ...
            sprintf('%d ', overlappingRows));
    end
    traceDistances = distances(traceRows);

    fig = [];
    if opts.showFigures || opts.saveFigures
        figVisible = 'off';
        if opts.showFigures, figVisible = 'on'; end
        fig = makeFigure(TRhead, points, labels, fidRows, traceSets, ...
            distances, meshSource, registration, modelFiducialsForPlot, ...
            opts, figVisible);
    end

    out = struct();
    out.createdOn = char(datetime('now'));
    out.registration = registration;
    out.meshSource = meshSource;
    out.modelFiducialsForPlot = modelFiducialsForPlot;
    out.fiducialLabels = opts.fiducialLabels(:);
    out.fiducialRows = fidRows(:);
    out.protectedFiducialRows = protectedRows(:);
    out.labels = labels(:);
    out.coordinatesMm = points;
    out.traceSets = traceSets;
    out.nearestHeadVertexDistanceMm = distances(:);
    out.tracePointRows = traceRows(:);
    out.traceNearestHeadVertexDistanceMm = traceDistances(:);
    out.traceDistanceMedianMm = robustPercentile(traceDistances, 50);
    out.traceDistanceP95Mm = robustPercentile(traceDistances, 95);
    out.traceDistanceMaxMm = robustPercentile(traceDistances, 100);
    if isfield(registration, 'rmseMm')
        out.registrationRmseMm = registration.rmseMm;
    else
        out.registrationRmseMm = NaN;
    end
    if isfield(registration, 'weightedRmseMm')
        out.registrationWeightedRmseMm = registration.weightedRmseMm;
    else
        out.registrationWeightedRmseMm = NaN;
    end
    if isfield(registration, 'maxErrorMm')
        out.registrationMaxErrorMm = registration.maxErrorMm;
    else
        out.registrationMaxErrorMm = NaN;
    end
    if isfield(registration, 'objectiveType')
        out.registrationObjectiveType = registration.objectiveType;
    else
        out.registrationObjectiveType = '';
    end
    out.figure = fig;
    out.qcFigure = '';

    if opts.saveFigures && isgraphics(fig)
        out.qcFigure = defaultFigureFile(registration, meshSource);
        ensureDir(fileparts(out.qcFigure));
        saveas(fig, out.qcFigure);
    end
    if opts.closeFigure && isgraphics(fig)
        close(fig);
        out.figure = [];
    end
    if opts.verbose
        printSummary(out);
    end
end

function opts = parseInputs(varargin)
    p = inputParser;
    p.FunctionName = 'acsVisualizePolhemusTraceOnHead';
    addParameter(p, 'fiducialLabels', {'Nas', 'Lpa', 'Rpa'}, ...
        @(x) iscell(x) || isstring(x) || ischar(x));
    addParameter(p, 'transformType', 'rigid', @(x) ischar(x) || isstring(x));
    addParameter(p, 'fiducialWeights', [], @isFiducialWeightsLike);
    addParameter(p, 'polhemusUnits', 'auto', @(x) ischar(x) || isstring(x));
    addParameter(p, 'modelUnits', 'auto', @(x) ischar(x) || isstring(x));
    addParameter(p, 'registrationOutputFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'meshStage', 'fullHead', @isMeshStage);
    addParameter(p, 'displayMaxFaces', 35000, @isNonnegativeScalar);
    addParameter(p, 'meshAlpha', 0.55, @isAlphaScalar);
    addParameter(p, 'meshLighting', 'flat', @isMeshLighting);
    addParameter(p, 'showLabels', true, @isBoolLike);
    addParameter(p, 'showPointLabels', false, @isBoolLike);
    addParameter(p, 'showFigures', true, @isBoolLike);
    addParameter(p, 'saveFigures', false, @isBoolLike);
    addParameter(p, 'closeFigure', false, @isBoolLike);
    addParameter(p, 'manualStepMm', 0.5, @isPositiveScalar);
    addParameter(p, 'manualRotationStepDeg', 1, @isPositiveScalar);
    addParameter(p, 'manualRefinementFile', '', @(x) ischar(x) || isstring(x));
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
    opts.transformType = char(opts.transformType);
    opts.polhemusUnits = char(opts.polhemusUnits);
    opts.modelUnits = char(opts.modelUnits);
    opts.registrationOutputFile = expandUserPath(char(opts.registrationOutputFile));
    opts.meshStage = normalizeMeshStage(opts.meshStage);
    opts.displayMaxFaces = round(double(opts.displayMaxFaces));
    opts.meshAlpha = double(opts.meshAlpha);
    opts.meshLighting = normalizeMeshLighting(opts.meshLighting);
    opts.showLabels = logical(opts.showLabels);
    opts.showPointLabels = logical(opts.showPointLabels);
    opts.showFigures = logical(opts.showFigures);
    opts.saveFigures = logical(opts.saveFigures);
    opts.closeFigure = logical(opts.closeFigure);
    opts.manualStepMm = double(opts.manualStepMm);
    opts.manualRotationStepDeg = double(opts.manualRotationStepDeg);
    opts.manualRefinementFile = expandUserPath(char(opts.manualRefinementFile));
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
        error('acsVisualizePolhemusTraceOnHead:BadFiducialWeights', ...
            'fiducialWeights must contain one positive value per fiducial label.');
    end
end

function tf = isAutoFiducialRequest(labels)
    labels = normalizeLabelCell(labels);
    tf = numel(labels) == 1 && any(strcmpi(labels{1}, ...
        {'auto', 'common', 'intersection', 'available'}));
end

function tf = isNonnegativeScalar(x)
    tf = isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0;
end

function tf = isPositiveScalar(x)
    tf = isnumeric(x) && isscalar(x) && isfinite(x) && x > 0;
end

function tf = isAlphaScalar(x)
    tf = isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0 && x <= 1;
end

function tf = isMeshStage(x)
    if ~(ischar(x) || isstring(x))
        tf = false;
        return;
    end
    tf = any(strcmpi(char(x), {'fullHead', 'full', 'head', 'fiducial', ...
        'fiducials', 'cap', 'cropped', 'manufacturing'}));
end

function stage = normalizeMeshStage(value)
    value = lower(strtrim(char(value)));
    switch value
        case {'fullhead', 'full', 'head', 'fiducial', 'fiducials'}
            stage = 'fullHead';
        case {'cap', 'cropped', 'manufacturing'}
            stage = 'cap';
        otherwise
            error('acsVisualizePolhemusTraceOnHead:BadMeshStage', ...
                'meshStage must be ''fullHead'' or ''cap''.');
    end
end

function tf = isMeshLighting(x)
    if ~(ischar(x) || isstring(x))
        tf = false;
        return;
    end
    tf = any(strcmpi(char(x), {'flat', 'gouraud', 'none'}));
end

function value = normalizeMeshLighting(value)
    value = lower(strtrim(char(value)));
    if ~any(strcmp(value, {'flat', 'gouraud', 'none'}))
        error('acsVisualizePolhemusTraceOnHead:BadMeshLighting', ...
            'meshLighting must be ''flat'', ''gouraud'', or ''none''.');
    end
end

function [registration, meshSeed] = resolveRegistration(polhemusIn, modelFiducials, opts)
    registration = [];
    meshSeed = modelFiducials;

    if isRegistrationStruct(polhemusIn)
        registration = polhemusIn;
    elseif ischar(polhemusIn) || isstring(polhemusIn)
        candidate = tryReadStructFile(char(polhemusIn));
        if isRegistrationStruct(candidate)
            registration = candidate;
        end
    end

    if isempty(registration)
        if isempty(modelFiducials)
            error('acsVisualizePolhemusTraceOnHead:MissingModelFiducials', ...
                ['Raw Polhemus sessions need model fiducials. Pass the ', ...
                 'acsSelectModelFiducials output as the second input.']);
        end
        registration = acsRegisterPolhemusFiducials(polhemusIn, ...
            modelFiducials, ...
            'fiducialLabels', opts.fiducialLabels, ...
            'polhemusUnits', opts.polhemusUnits, ...
            'modelUnits', opts.modelUnits, ...
            'transformType', opts.transformType, ...
            'fiducialWeights', opts.fiducialWeights, ...
            'outputFile', opts.registrationOutputFile, ...
            'verbose', opts.verbose);
    end

    if isempty(meshSeed)
        meshSeed = meshSeedFromRegistration(registration);
    end
end

function tf = isRegistrationStruct(S)
    tf = isstruct(S) && isfield(S, 'transformedSourcePointsMm') && ...
        isfield(S, 'sourceLabels');
end

function modelFids = resolveModelFiducialsForPlot(modelFiducials, ...
        registration, opts)
    modelFids = emptyModelFiducials();
    candidate = [];
    if ~isempty(modelFiducials)
        candidate = readModelFiducialCandidate(modelFiducials);
    end
    if isempty(candidate) && isfield(registration, 'target') && ...
            isstruct(registration.target)
        candidate = readModelFiducialCandidate(registration.target);
    end
    if isempty(candidate) && isfield(registration, 'targetFiducialsMm') && ...
            ~isempty(registration.targetFiducialsMm)
        candidate = struct( ...
            'labels', {opts.fiducialLabels(:)}, ...
            'coordinatesMm', double(registration.targetFiducialsMm), ...
            'source', 'registration.targetFiducialsMm');
    end
    if isempty(candidate)
        return;
    end
    if ~isfield(candidate, 'labels') || ~isfield(candidate, 'coordinatesMm')
        return;
    end
    labels = normalizeLabelCell(candidate.labels);
    coords = double(candidate.coordinatesMm);
    if isempty(labels) && size(coords, 1) == numel(opts.fiducialLabels)
        labels = opts.fiducialLabels(:);
    end
    if size(coords, 2) ~= 3 || numel(labels) ~= size(coords, 1)
        return;
    end
    rows = fiducialRows(labels, opts.fiducialLabels);
    if any(~isfinite(rows) | rows < 1)
        warning('acsVisualizePolhemusTraceOnHead:MissingModelFiducialForPlot', ...
            'Could not find all requested model fiducials for plotting.');
        rows = rows(isfinite(rows) & rows >= 1 & rows <= size(coords, 1));
    end
    if isempty(rows)
        return;
    end
    modelFids.labels = opts.fiducialLabels(:);
    modelFids.coordinatesMm = coords(rows, :);
    modelFids.rows = rows(:);
    if isfield(candidate, 'selectedVertex') && ~isempty(candidate.selectedVertex)
        sv = double(candidate.selectedVertex(:));
        svRows = nan(numel(rows), 1);
        valid = rows <= numel(sv);
        svRows(valid) = sv(rows(valid));
        modelFids.selectedVertex = svRows;
    end
    if isfield(candidate, 'source')
        modelFids.source = candidate.source;
    end
end

function modelFids = emptyModelFiducials()
    modelFids = struct( ...
        'labels', {{}}, ...
        'coordinatesMm', zeros(0, 3), ...
        'rows', [], ...
        'selectedVertex', [], ...
        'source', []);
end

function candidate = readModelFiducialCandidate(value)
    candidate = [];
    if isempty(value)
        return;
    end
    if isnumeric(value) && size(value, 2) == 3
        candidate = struct('labels', {{}}, 'coordinatesMm', double(value));
        return;
    end
    if isstruct(value)
        if isfield(value, 'labels') && isfield(value, 'coordinatesMm')
            candidate = value;
            return;
        end
        if isfield(value, 'targetFiducialsMm') && ...
                ~isempty(value.targetFiducialsMm)
            labels = {};
            if isfield(value, 'fiducialLabels')
                labels = normalizeLabelCell(value.fiducialLabels);
            end
            candidate = struct( ...
                'labels', {labels}, ...
                'coordinatesMm', double(value.targetFiducialsMm), ...
                'source', 'targetFiducialsMm');
            return;
        end
        if isfield(value, 'source') && isstruct(value.source)
            candidate = readModelFiducialCandidate(value.source);
        end
        return;
    end
    if ~(ischar(value) || isstring(value))
        return;
    end
    fileName = expandUserPath(char(value));
    if exist(fileName, 'file') ~= 2
        return;
    end
    candidate = tryReadStructFile(fileName);
end

function checkRegistrationTargetFiducials(registration, modelFids)
    if isempty(modelFids) || isempty(modelFids.coordinatesMm)
        return;
    end
    if ~isfield(registration, 'targetFiducialsMm') || ...
            isempty(registration.targetFiducialsMm)
        return;
    end
    regTarget = double(registration.targetFiducialsMm);
    modelTarget = double(modelFids.coordinatesMm);
    if ~isequal(size(regTarget), size(modelTarget))
        return;
    end
    delta = sqrt(sum((regTarget - modelTarget) .^ 2, 2));
    if any(delta > 1e-6)
        warning('acsVisualizePolhemusTraceOnHead:TargetFiducialMismatch', ...
            ['Registration target fiducials differ from the model ', ...
             'fiducials used for plotting. Plotting the supplied model ', ...
             'fiducials. Differences by label: %s'], ...
            fiducialDifferenceText(modelFids.labels, delta));
    end
end

function warnIfLegacyRegistrationConvention(registration)
    expected = 'weighted row-vector least-squares rigid/similarity';
    if isfield(registration, 'objectiveType') && ...
            strcmp(char(registration.objectiveType), expected)
        return;
    end
    warning('acsVisualizePolhemusTraceOnHead:LegacyRegistrationConvention', ...
        ['This registration does not advertise the current row-vector ', ...
         'least-squares objective. If it was saved before the registration ', ...
         'fix, recompute it from the raw Polhemus session before judging ', ...
         'manual refinement RMSE.']);
end

function txt = fiducialDifferenceText(labels, delta)
    labels = normalizeLabelCell(labels);
    parts = cell(numel(delta), 1);
    for i = 1:numel(delta)
        if i <= numel(labels)
            label = labels{i};
        else
            label = sprintf('fid%d', i);
        end
        parts{i} = sprintf('%s %.4g mm', label, delta(i));
    end
    txt = strjoin(parts, ', ');
end

function S = tryReadStructFile(fileName)
    S = [];
    fileName = expandUserPath(fileName);
    if exist(fileName, 'file') ~= 2
        return;
    end
    [~, ~, ext] = fileparts(fileName);
    switch lower(ext)
        case '.mat'
            raw = load(fileName);
            S = firstStruct(raw);
        case '.json'
            try
                S = jsondecode(fileread(fileName));
            catch
                S = [];
            end
    end
end

function meshSeed = meshSeedFromRegistration(registration)
    meshSeed = [];
    if isfield(registration, 'target') && isstruct(registration.target)
        if isfield(registration.target, 'source') && ...
                ~isempty(registration.target.source)
            meshSeed = registration.target.source;
            return;
        end
        if isfield(registration.target, 'file') && ...
                ~isempty(registration.target.file)
            meshSeed = registration.target.file;
        end
    end
end

function [TRhead, source] = readHeadMesh(value, opts)
    source = struct('type', '', 'file', '', 'label', '', ...
        'meshStage', opts.meshStage, 'coordinateFrame', 'capMakerPrintMm');
    if isempty(value)
        error('acsVisualizePolhemusTraceOnHead:MissingMeshSource', ...
            ['Could not infer the head mesh. Pass the model fiducials, ', ...
             'combined layout, or skin cache as the second input.']);
    end

    if isa(value, 'triangulation')
        TRhead = value;
        source.type = 'triangulation';
        source.label = 'triangulation';
        source.coordinateFrame = 'modelMm';
        return;
    end
    if isstruct(value) && isfield(value, 'Points') && ...
            isfield(value, 'ConnectivityList')
        TRhead = triangulation(double(value.ConnectivityList), ...
            double(value.Points));
        source.type = 'meshStruct';
        source.label = 'mesh struct';
        source.coordinateFrame = 'modelMm';
        return;
    end
    if isstruct(value) && isfield(value, 'file') && ...
            ~isempty(value.file) && ...
            ~(isfield(value, 'layout') && isfield(value.layout, 'skin'))
        [TRhead, source] = readHeadMesh(value.file, opts);
        if isfield(value, 'label') && ~isempty(value.label)
            source.label = char(value.label);
        end
        if isfield(value, 'coordinateFrame') && ~isempty(value.coordinateFrame)
            source.coordinateFrame = char(value.coordinateFrame);
        end
        return;
    end
    if isstruct(value) && isfield(value, 'source') && ...
            isstruct(value.source) && isfield(value.source, 'file') && ...
            ~isempty(value.source.file)
        [TRhead, source] = readHeadMesh(value.source, opts);
        return;
    end
    if isstruct(value) && isfield(value, 'layout') && ...
            isfield(value.layout, 'skin') && ...
            isfield(value.layout.skin, 'cacheFile') && ...
            ~isempty(value.layout.skin.cacheFile)
        [TRhead, source] = readSkinCache(value.layout.skin.cacheFile, opts);
        source.type = 'layout';
        return;
    end
    if isstruct(value) && isfield(value, 'TRfiducialHead')
        [TRhead, source] = readSkinCacheStruct(value, source, opts);
        return;
    end
    if isstruct(value) && isfield(value, 'TRskin')
        [TRhead, source] = readSkinCacheStruct(value, source, opts);
        return;
    end
    if isstruct(value)
        error('acsVisualizePolhemusTraceOnHead:BadMeshStruct', ...
            ['Could not find a skin cache, layout.skin.cacheFile, or ', ...
             'source.file in the mesh/model input.']);
    end

    if ~(ischar(value) || isstring(value))
        error('acsVisualizePolhemusTraceOnHead:BadMeshInput', ...
            'Mesh/model input must be a layout, fiducial report, skin cache, or triangulation.');
    end
    fileName = expandUserPath(char(value));
    if exist(fileName, 'file') ~= 2
        error('acsVisualizePolhemusTraceOnHead:MeshFileNotFound', ...
            'Mesh/model file not found: %s', fileName);
    end
    [~, ~, ext] = fileparts(fileName);
    switch lower(ext)
        case '.json'
            raw = jsondecode(fileread(fileName));
        otherwise
            raw = load(fileName);
    end
    if isSkinCacheStruct(raw)
        [TRhead, source] = readSkinCacheStruct(raw, source, opts);
        source.file = fileName;
        source.label = fileStem(fileName);
        return;
    end
    if isstruct(raw) && (isfield(raw, 'source') || isfield(raw, 'layout'))
        [TRhead, source] = readHeadMesh(raw, opts);
        if isempty(source.file)
            source.file = fileName;
        end
        if isempty(source.label)
            source.label = fileStem(fileName);
        end
        return;
    end
    S = firstStruct(raw);
    [TRhead, source] = readHeadMesh(S, opts);
    if isempty(source.file)
        source.file = fileName;
    end
    if isempty(source.label)
        source.label = fileStem(fileName);
    end
end

function [TRhead, source] = readSkinCache(fileName, opts)
    fileName = expandUserPath(char(fileName));
    if exist(fileName, 'file') ~= 2
        error('acsVisualizePolhemusTraceOnHead:SkinCacheNotFound', ...
            'Skin cache not found: %s', fileName);
    end
    S = load(fileName);
    source = struct('type', 'skinCache', 'file', fileName, ...
        'label', fileStem(fileName), 'meshStage', opts.meshStage, ...
        'coordinateFrame', skinCacheCoordinateFrame(S, opts.meshStage));
    [TRhead, source] = readSkinCacheStruct(S, source, opts);
end

function tf = isSkinCacheStruct(S)
    tf = isfield(S, 'TRskin') || isfield(S, 'TRfiducialHead') || ...
        (isfield(S, 'meta') && isstruct(S.meta) && ...
         isfield(S.meta, 'fiducialHead') && ...
         isfield(S.meta.fiducialHead, 'TR'));
end

function [TRhead, source] = readSkinCacheStruct(S, source, opts)
    source.meshStage = opts.meshStage;
    source.coordinateFrame = skinCacheCoordinateFrame(S, opts.meshStage);
    switch opts.meshStage
        case 'fullHead'
            if isfield(S, 'TRfiducialHead') && ~isempty(S.TRfiducialHead)
                TRhead = S.TRfiducialHead;
                source.modelType = 'capMakerFullHeadMesh';
                return;
            end
            if isfield(S, 'meta') && isstruct(S.meta) && ...
                    isfield(S.meta, 'fiducialHead') && ...
                    isfield(S.meta.fiducialHead, 'TR') && ...
                    ~isempty(S.meta.fiducialHead.TR)
                TRhead = S.meta.fiducialHead.TR;
                source.modelType = 'capMakerFullHeadMesh';
                return;
            end
            error('acsVisualizePolhemusTraceOnHead:MissingFullHeadMesh', ...
                ['Skin cache does not contain TRfiducialHead. Rerun ', ...
                 'acsMakeRoastCapMakerLayout or call with meshStage=''cap''.']);
        otherwise
            if ~isfield(S, 'TRskin') || isempty(S.TRskin)
                error('acsVisualizePolhemusTraceOnHead:MissingCapMesh', ...
                    'Skin cache does not contain TRskin.');
            end
            TRhead = S.TRskin;
            source.modelType = 'capMakerCroppedCapMesh';
    end
end

function frame = skinCacheCoordinateFrame(S, meshStage)
    frame = 'capMakerPrintMm';
    if ~isfield(S, 'meta') || ~isstruct(S.meta)
        return;
    end
    meta = S.meta;
    if ~strcmp(meshStage, 'fullHead')
        return;
    end
    alignIdentity = true;
    printIdentity = true;
    if isfield(meta, 'align') && isstruct(meta.align) && ...
            isfield(meta.align, 'R') && ~isempty(meta.align.R)
        alignIdentity = max(abs(double(meta.align.R(:)) - eyeVector())) < 1e-8;
    end
    if isfield(meta, 'print') && isstruct(meta.print) && ...
            isfield(meta.print, 'T_world2print') && ~isempty(meta.print.T_world2print)
        printIdentity = max(abs(double(meta.print.T_world2print(:)) - eye4Vector())) < 1e-8;
    end
    if alignIdentity && printIdentity
        frame = 'capMakerPreCropWorldMm';
    end
end

function v = eyeVector()
    v = eye(3);
    v = v(:);
end

function v = eye4Vector()
    v = eye(4);
    v = v(:);
end

function traceSets = buildTraceSets(registration, labels, points, ...
        protectedRows, fiducialLabels)
    traceSets = emptyTraceSets();
    if isfield(registration, 'registeredObjects') && ...
            ~isempty(registration.registeredObjects)
        objects = registration.registeredObjects;
        for i = 1:numel(objects)
            coords = [];
            if isfield(objects(i), 'transformedCoordinatesMm') && ...
                    ~isempty(objects(i).transformedCoordinatesMm)
                coords = double(objects(i).transformedCoordinatesMm);
            elseif isfield(objects(i), 'coordinatesMm') && ...
                    ~isempty(objects(i).coordinatesMm)
                coords = double(objects(i).coordinatesMm);
            end
            if isempty(coords)
                continue;
            end
            row = nan(size(coords, 1), 1);
            if isfield(objects(i), 'rows') && ~isempty(objects(i).rows)
                row = double(objects(i).rows(:));
            end
            objectLabels_i = objectLabels(objects(i), size(coords, 1));
            keep = traceKeepRows(row, objectLabels_i, protectedRows, ...
                fiducialLabels);
            coords = coords(keep, :);
            row = row(keep);
            objectLabels_i = objectLabels_i(keep);
            if isempty(coords)
                continue;
            end
            name = sprintf('trace%d', i);
            if isfield(objects(i), 'name') && ~isempty(objects(i).name)
                name = char(objects(i).name);
            end
            traceSets(end + 1, 1) = struct( ... %#ok<AGROW>
                'name', name, ...
                'rows', row, ...
                'labels', {objectLabels_i}, ...
                'coordinatesMm', coords);
        end
    end

    if ~isempty(traceSets)
        return;
    end

    allRows = (1:size(points, 1))';
    keep = traceKeepRows(allRows, labels, protectedRows, fiducialLabels);
    traceRows = allRows(keep);
    traceSets(1, 1) = struct( ...
        'name', defaultTraceName(registration), ...
        'rows', traceRows, ...
        'labels', {labels(traceRows)}, ...
        'coordinatesMm', points(traceRows, :));
end

function traceSets = emptyTraceSets()
    traceSets = repmat(struct( ...
        'name', '', ...
        'rows', [], ...
        'labels', {{}}, ...
        'coordinatesMm', []), 0, 1);
end

function labels = objectLabels(object, n)
    if isfield(object, 'labels') && ~isempty(object.labels)
        labels = normalizeLabelCell(object.labels);
    else
        labels = defaultLabels(n);
    end
    if numel(labels) ~= n
        labels = defaultLabels(n);
    end
end

function keep = traceKeepRows(rows, labels, protectedRows, fiducialLabels)
    n = numel(labels);
    if isempty(rows)
        rows = nan(n, 1);
    else
        rows = rows(:);
    end
    if numel(rows) ~= n
        rows = nan(n, 1);
    end
    protectedRows = protectedRows(isfinite(protectedRows) & protectedRows > 0);
    keep = true(n, 1);
    keep = keep & ~ismember(rows, protectedRows);
    labelNorm = normalizeLabels(labels);
    fidNorm = normalizeFiducialAliasSet(fiducialLabels);
    keep = keep & ~ismember(labelNorm, fidNorm);
end

function name = defaultTraceName(registration)
    name = 'trace';
    if isfield(registration, 'source') && isstruct(registration.source) && ...
            isfield(registration.source, 'sessionType') && ...
            ~isempty(registration.source.sessionType)
        sessionType = char(registration.source.sessionType);
        switch lower(sessionType)
            case 'scalptrace'
                name = 'scalp trace';
            case 'monkeyimplants'
                name = 'implant trace';
            otherwise
                name = sessionType;
        end
    end
end

function fig = makeFigure(TRhead, points, labels, fidRows, traceSets, ...
        distances, meshSource, registration, modelFiducialsForPlot, opts, ...
        figVisible)
    V = double(TRhead.Points);
    F = orientFacesForDisplay(double(TRhead.ConnectivityList), V);
    [Fd, Vd] = displayMesh(F, V, opts.displayMaxFaces);
    basePoints = double(points);
    sourceFidRows = fidRows(isfinite(fidRows) & fidRows > 0 & ...
        fidRows <= size(basePoints, 1));
    if ~isempty(sourceFidRows)
        rotationOrigin = mean(basePoints(sourceFidRows, :), 1);
    else
        rotationOrigin = mean(basePoints, 1);
    end
    if any(~isfinite(rotationOrigin))
        rotationOrigin = [0 0 0];
    end
    manualR = eye(3);
    manualT = [0 0 0];

    fig = figure('Name', 'Polhemus Trace on Head Mesh', ...
        'Color', 'w', 'Visible', figVisible, ...
        'WindowStyle', 'normal', 'Position', [80 80 1450 720], ...
        'MenuBar', 'none', ...
        'ToolBar', 'figure', ...
        'KeyPressFcn', @manualKeyPress);
    fileMenu = uimenu(fig, 'Label', '&File');
    uimenu(fileMenu, 'Label', 'Save Manual Refinement...', ...
        'Callback', @saveManualRefinementCallback);
    uimenu(fileMenu, 'Label', 'Close', 'Separator', 'on', ...
        'Callback', @(~, ~) close(fig));
    refineMenu = uimenu(fig, 'Label', '&Refine');
    uimenu(refineMenu, 'Label', 'Reset Manual Refinement', ...
        'Callback', @resetManualRefinementCallback);

    tl = tiledlayout(fig, 1, 2, 'Padding', 'loose', ...
        'TileSpacing', 'compact');

    ax = nexttile(tl, 1);
    patch(ax, 'Faces', Fd, 'Vertices', Vd, ...
        'FaceColor', [0.78 0.82 0.88], ...
        'EdgeColor', 'none', ...
        'FaceAlpha', opts.meshAlpha, ...
        'FaceLighting', opts.meshLighting, ...
        'BackFaceLighting', 'reverselit', ...
        'AmbientStrength', 0.5, ...
        'DiffuseStrength', 0.55, ...
        'SpecularStrength', 0.05);
    hold(ax, 'on');

    if ~isempty(modelFiducialsForPlot.coordinatesMm)
        targetFid = double(modelFiducialsForPlot.coordinatesMm);
        scatter3(ax, targetFid(:, 1), targetFid(:, 2), targetFid(:, 3), ...
            130, 's', 'MarkerEdgeColor', [0.65 0 0.85], ...
            'MarkerFaceColor', 'none', 'LineWidth', 1.8, ...
            'DisplayName', 'model fiducials');
        if opts.showLabels
            addLabels3(ax, targetFid, modelFiducialPlotLabels( ...
                modelFiducialsForPlot), [0.35 0 0.5]);
        end
    end
    xlabel(ax, 'capMaker X (mm)');
    ylabel(ax, 'capMaker Y (mm)');
    zlabel(ax, 'capMaker Z (mm)');
    axis(ax, 'equal');
    axis(ax, 'vis3d');
    grid(ax, 'on');
    view(ax, 3);
    if ~strcmp(opts.meshLighting, 'none')
        camlight(ax, 'headlight');
        lighting(ax, opts.meshLighting);
    end

    ax2 = nexttile(tl, 2);
    statusBox = uicontrol(fig, 'Style', 'text', 'Units', 'normalized', ...
        'Position', [0.04 0.005 0.92 0.035], ...
        'String', manualStatusText(), ...
        'HorizontalAlignment', 'left', ...
        'BackgroundColor', get(fig, 'Color'), ...
        'ForegroundColor', [0.12 0.12 0.12]);
    redrawManualOverlay();
    rotate3d(fig, 'on');
    setappdata(fig, 'acsPolhemusManualRefinement', buildManualReport());

    function C = transformCoords(C)
        if isempty(C)
            return;
        end
        C = bsxfun(@plus, bsxfun(@minus, C, rotationOrigin) * manualR', ...
            rotationOrigin + manualT);
    end

    function sets = transformedTraceSets()
        sets = traceSets;
        for si = 1:numel(sets)
            if isfield(sets(si), 'coordinatesMm')
                sets(si).coordinatesMm = transformCoords(sets(si).coordinatesMm);
            end
        end
    end

    function redrawManualOverlay()
        delete(findall(ax, 'Tag', 'acsManualPolhemusOverlay'));
        adjustedPoints = transformCoords(basePoints);
        adjustedTraceSets = transformedTraceSets();
        colors = lines(max(1, numel(adjustedTraceSets)));
        for ti = 1:numel(adjustedTraceSets)
            C = adjustedTraceSets(ti).coordinatesMm;
            if isempty(C), continue; end
            plot3(ax, C(:, 1), C(:, 2), C(:, 3), '-', ...
                'Color', colors(ti, :), 'LineWidth', 1.4, ...
                'DisplayName', adjustedTraceSets(ti).name, ...
                'Tag', 'acsManualPolhemusOverlay');
            scatter3(ax, C(:, 1), C(:, 2), C(:, 3), 24, ...
                colors(ti, :), 'filled', ...
                'MarkerEdgeColor', [0.08 0.08 0.08], ...
                'LineWidth', 0.25, ...
                'HandleVisibility', 'off', ...
                'Tag', 'acsManualPolhemusOverlay');
            if opts.showLabels
                labelTraceEndpointTagged(ax, C(1, :), ...
                    endpointLabel(adjustedTraceSets(ti), 1, 'start'));
                if size(C, 1) > 1
                    labelTraceEndpointTagged(ax, C(end, :), ...
                        endpointLabel(adjustedTraceSets(ti), size(C, 1), 'end'));
                end
            end
            if opts.showPointLabels
                addLabels3Tagged(ax, C, adjustedTraceSets(ti).labels, ...
                    [0.6 0.6 0.6]);
            end
        end
        if ~isempty(sourceFidRows)
            scatter3(ax, adjustedPoints(sourceFidRows, 1), ...
                adjustedPoints(sourceFidRows, 2), ...
                adjustedPoints(sourceFidRows, 3), 86, 'kd', 'filled', ...
                'DisplayName', 'transformed Polhemus fiducials', ...
                'Tag', 'acsManualPolhemusOverlay');
            if opts.showLabels
                addLabels3Tagged(ax, adjustedPoints(sourceFidRows, :), ...
                    prefixLabels('Polhemus ', labels(sourceFidRows)), [0 0 0]);
            end
        end
        title(ax, sprintf('%s\n%s', titleText(registration, meshSource), ...
            manualErrorStatusText()), 'Interpreter', 'none');
        legend(ax, 'Location', 'bestoutside', 'Interpreter', 'none');
        adjustedDistances = nearestVertexDistances(adjustedPoints, V);
        cla(ax2);
        plotDistanceDiagnostics(ax2, adjustedTraceSets, adjustedDistances);
        set(statusBox, 'String', manualStatusText());
        setappdata(fig, 'acsPolhemusManualRefinement', buildManualReport());
        drawnow limitrate;
    end

    function labelTraceEndpointTagged(axIn, point, label)
        h = text(axIn, point(1), point(2), point(3), ['  ' label], ...
            'FontSize', 9, 'FontWeight', 'bold', ...
            'Color', [0.05 0.05 0.05], ...
            'Interpreter', 'none', ...
            'Clipping', 'off');
        set(h, 'Tag', 'acsManualPolhemusOverlay');
    end

    function addLabels3Tagged(axIn, coords, labelsIn, color)
        for li = 1:size(coords, 1)
            if ~all(isfinite(coords(li, :))), continue; end
            h = text(axIn, coords(li, 1), coords(li, 2), coords(li, 3), ...
                ['  ' labelsIn{li}], ...
                'Color', color, ...
                'FontWeight', 'bold', ...
                'Interpreter', 'none', ...
                'Clipping', 'off');
            set(h, 'Tag', 'acsManualPolhemusOverlay');
        end
    end

    function manualKeyPress(~, evt)
        stepMm = opts.manualStepMm;
        rotDeg = opts.manualRotationStepDeg;
        if hasModifier(evt, 'shift')
            stepMm = stepMm * 5;
            rotDeg = rotDeg * 5;
        end
        key = lower(char(evt.Key));
        handled = true;
        switch key
            case 'rightarrow'
                manualT = manualT + [stepMm 0 0];
            case 'leftarrow'
                manualT = manualT + [-stepMm 0 0];
            case 'uparrow'
                manualT = manualT + [0 stepMm 0];
            case 'downarrow'
                manualT = manualT + [0 -stepMm 0];
            case 'u'
                manualT = manualT + [0 0 stepMm];
            case 'd'
                manualT = manualT + [0 0 -stepMm];
            case 'p'
                manualR = axisRotationMatrix('x', rotDeg) * manualR;
            case 'o'
                manualR = axisRotationMatrix('x', -rotDeg) * manualR;
            case 'r'
                manualR = axisRotationMatrix('y', rotDeg) * manualR;
            case 't'
                manualR = axisRotationMatrix('y', -rotDeg) * manualR;
            case 'y'
                manualR = axisRotationMatrix('z', rotDeg) * manualR;
            case 'h'
                manualR = axisRotationMatrix('z', -rotDeg) * manualR;
            case 'escape'
                manualR = eye(3);
                manualT = [0 0 0];
            case 's'
                if hasModifier(evt, 'control')
                    saveManualRefinementCallback([], []);
                else
                    handled = false;
                end
            otherwise
                handled = false;
        end
        if handled
            redrawManualOverlay();
        end
    end

    function tf = hasModifier(evt, name)
        tf = isfield(evt, 'Modifier') && any(strcmpi(evt.Modifier, name));
    end

    function resetManualRefinementCallback(~, ~)
        manualR = eye(3);
        manualT = [0 0 0];
        redrawManualOverlay();
    end

    function saveManualRefinementCallback(~, ~)
        defaultFile = opts.manualRefinementFile;
        if isempty(defaultFile)
            defaultFile = defaultManualRefinementFile(registration, meshSource);
        end
        [folder, stem, ext] = fileparts(defaultFile);
        if isempty(ext), ext = '.mat'; end
        if isempty(folder), folder = pwd; end
        [fname, pathName] = uiputfile( ...
            {'*.mat', 'MAT refinement + JSON sidecar (*.mat)'; ...
             '*.json', 'JSON refinement + MAT sidecar (*.json)'}, ...
            'Save manual Polhemus refinement', fullfile(folder, [stem ext]));
        if isequal(fname, 0)
            return;
        end
        fileName = fullfile(pathName, fname);
        report = buildManualReport();
        report.outputFile = writeManualRefinement(fileName, report);
        setappdata(fig, 'acsPolhemusManualRefinement', report);
        fprintf('\nSaved manual Polhemus refinement: %s\n\n', report.outputFile);
    end

    function report = buildManualReport()
        adjustedPoints = transformCoords(basePoints);
        adjustedTraceSets = transformedTraceSets();
        adjustedDistances = nearestVertexDistances(adjustedPoints, V);
        traceRows = unique(allTraceRows(adjustedTraceSets));
        traceRows = traceRows(traceRows >= 1 & traceRows <= numel(adjustedDistances));
        report = struct();
        report.createdOn = char(datetime('now'));
        report.type = 'manualPolhemusRigidRefinement';
        report.instructions = ['Manual transform is applied after automatic ', ...
            'fiducial registration as pointsManualMm = ', ...
            '(pointsAutoMm - rotationOriginMm) * rotationMatrix'' + ', ...
            'rotationOriginMm + translationMm.'];
        report.rotationOriginMm = rotationOrigin;
        report.rotationMatrix = manualR;
        report.translationMm = manualT;
        report.stepMm = opts.manualStepMm;
        report.rotationStepDeg = opts.manualRotationStepDeg;
        report.sourceFile = registrationSourceFile(registration);
        report.meshSource = meshSource;
        report.registration = registration;
        report.labels = labels(:);
        report.autoCoordinatesMm = basePoints;
        report.manualCoordinatesMm = adjustedPoints;
        report.fiducialRows = sourceFidRows(:);
        report.modelFiducials = modelFiducialsForPlot;
        report.manualTraceSets = adjustedTraceSets;
        report.nearestHeadVertexDistanceMm = adjustedDistances(:);
        if ~isempty(traceRows)
            td = adjustedDistances(traceRows);
            report.traceDistanceMedianMm = robustPercentile(td, 50);
            report.traceDistanceP95Mm = robustPercentile(td, 95);
            report.traceDistanceMaxMm = robustPercentile(td, 100);
        else
            report.traceDistanceMedianMm = NaN;
            report.traceDistanceP95Mm = NaN;
            report.traceDistanceMaxMm = NaN;
        end
        report.fiducialErrorMm = manualFiducialErrors(adjustedPoints);
        report.keyboardControls = ['arrows: X/Y nudge; U/D: Z nudge; ', ...
            'p/o: pitch +/- about X; r/t: roll +/- about Y; y/h: yaw +/- about Z; ', ...
            'Shift uses 5x step; Escape resets; Ctrl+S saves.'];
    end

    function err = manualFiducialErrors(adjustedPoints)
        err = struct('labels', {{}}, 'errorMm', [], 'vectorsMm', [], ...
            'rmseMm', NaN, 'maxErrorMm', NaN);
        if isempty(sourceFidRows) || isempty(modelFiducialsForPlot.coordinatesMm)
            return;
        end
        n = min(numel(sourceFidRows), size(modelFiducialsForPlot.coordinatesMm, 1));
        src = adjustedPoints(sourceFidRows(1:n), :);
        tgt = double(modelFiducialsForPlot.coordinatesMm(1:n, :));
        vectors = src - tgt;
        d = sqrt(sum(vectors .^ 2, 2));
        err.labels = opts.fiducialLabels(1:n);
        err.errorMm = d(:);
        err.vectorsMm = vectors;
        err.rmseMm = sqrt(mean(d .^ 2));
        err.maxErrorMm = max(d);
    end

    function txt = manualStatusText()
        eul = manualEulerApproxDeg(manualR);
        txt = sprintf(['Manual refine: T [%.2f %.2f %.2f] mm, ', ...
            'approx Rxyz [%.2f %.2f %.2f] deg | arrows XY, U/D Z, ', ...
            'p/o pitch, r/t roll, y/h yaw, Shift 5x, Esc reset, Ctrl+S save | %s'], ...
            manualT, eul, manualErrorStatusText());
    end

    function txt = manualErrorStatusText()
        adjustedPoints = transformCoords(basePoints);
        err = manualFiducialErrors(adjustedPoints);
        if isfinite(err.rmseMm)
            txt = sprintf('fid RMSE %.2f mm, max %.2f mm', ...
                err.rmseMm, err.maxErrorMm);
        else
            txt = 'fid RMSE unavailable';
        end
    end
end

function [F, V] = displayMesh(Fin, Vin, maxFaces)
    F = double(Fin);
    V = double(Vin);
    if maxFaces > 0 && size(F, 1) > maxFaces
        [F, V] = reducepatch(F, V, maxFaces);
        F = double(F);
        V = double(V);
    end
end

function F = orientFacesForDisplay(F, V)
    if isempty(F) || isempty(V)
        return;
    end
    center = mean(V, 1);
    v1 = V(F(:, 1), :);
    v2 = V(F(:, 2), :);
    v3 = V(F(:, 3), :);
    normals = cross(v2 - v1, v3 - v1, 2);
    faceCenters = (v1 + v2 + v3) / 3;
    outward = faceCenters - center;
    flip = sum(normals .* outward, 2) < 0;
    F(flip, [2 3]) = F(flip, [3 2]);
end

function labelTraceEndpoint(ax, point, label)
    text(ax, point(1), point(2), point(3), ['  ' label], ...
        'FontSize', 9, 'FontWeight', 'bold', ...
        'Color', [0.05 0.05 0.05], ...
        'Interpreter', 'none', ...
        'Clipping', 'off');
end

function label = endpointLabel(traceSet, index, whichEnd)
    pointLabel = '';
    if isfield(traceSet, 'labels') && numel(traceSet.labels) >= index && ...
            ~isempty(traceSet.labels{index})
        pointLabel = traceSet.labels{index};
    end
    if isempty(pointLabel)
        label = sprintf('%s %s', traceSet.name, whichEnd);
    else
        label = sprintf('%s %s (%s)', traceSet.name, whichEnd, pointLabel);
    end
end

function addLabels3(ax, coords, labels, color)
    for i = 1:size(coords, 1)
        if ~all(isfinite(coords(i, :))), continue; end
        text(ax, coords(i, 1), coords(i, 2), coords(i, 3), ...
            ['  ' labels{i}], ...
            'Color', color, ...
            'FontWeight', 'bold', ...
            'Interpreter', 'none', ...
            'Clipping', 'off');
    end
end

function labelsOut = prefixLabels(prefix, labelsIn)
    labelsIn = normalizeLabelCell(labelsIn);
    labelsOut = labelsIn;
    for i = 1:numel(labelsOut)
        labelsOut{i} = [prefix labelsOut{i}];
    end
end

function labelsOut = modelFiducialPlotLabels(modelFids)
    labelsOut = prefixLabels('model ', modelFids.labels);
    if isfield(modelFids, 'selectedVertex') && ...
            ~isempty(modelFids.selectedVertex)
        for i = 1:min(numel(labelsOut), numel(modelFids.selectedVertex))
            if isfinite(modelFids.selectedVertex(i))
                labelsOut{i} = sprintf('%s (v%d)', labelsOut{i}, ...
                    round(modelFids.selectedVertex(i)));
            end
        end
    end
end

function plotDistanceDiagnostics(ax, traceSets, distances)
    hold(ax, 'on');
    colors = lines(max(1, numel(traceSets)));
    finiteDistances = [];
    for i = 1:numel(traceSets)
        rows = traceSets(i).rows(:);
        rows = rows(isfinite(rows) & rows >= 1 & rows <= numel(distances));
        if isempty(rows)
            continue;
        end
        d = distances(rows);
        finiteDistances = [finiteDistances; d(:)]; %#ok<AGROW>
        plot(ax, 1:numel(d), d(:), '-o', ...
            'Color', colors(i, :), ...
            'MarkerFaceColor', colors(i, :), ...
            'MarkerSize', 4, ...
            'LineWidth', 1.1, ...
            'DisplayName', traceSets(i).name);
    end
    if ~isempty(finiteDistances)
        med = robustPercentile(finiteDistances, 50);
        p95 = robustPercentile(finiteDistances, 95);
        yline(ax, med, '--', sprintf('median %.2f mm', med), ...
            'Color', [0.15 0.15 0.15], 'LabelHorizontalAlignment', 'left');
        yline(ax, p95, ':', sprintf('p95 %.2f mm', p95), ...
            'Color', [0.35 0.35 0.35], 'LabelHorizontalAlignment', 'left');
    end
    xlabel(ax, 'trace sample');
    ylabel(ax, 'nearest head-mesh vertex distance (mm)');
    title(ax, 'Trace-to-head distance');
    grid(ax, 'on');
    legend(ax, 'Location', 'best', 'Interpreter', 'none');
end

function R = axisRotationMatrix(axisName, angleDeg)
    a = angleDeg * pi / 180;
    c = cos(a);
    s = sin(a);
    switch lower(char(axisName))
        case 'x'
            R = [1 0 0; 0 c -s; 0 s c];
        case 'y'
            R = [c 0 s; 0 1 0; -s 0 c];
        case 'z'
            R = [c -s 0; s c 0; 0 0 1];
        otherwise
            error('acsVisualizePolhemusTraceOnHead:BadRotationAxis', ...
                'Unknown rotation axis %s.', char(axisName));
    end
end

function eul = manualEulerApproxDeg(R)
    R = double(R);
    sy = sqrt(R(1, 1) ^ 2 + R(2, 1) ^ 2);
    if sy > 1e-9
        x = atan2(R(3, 2), R(3, 3));
        y = atan2(-R(3, 1), sy);
        z = atan2(R(2, 1), R(1, 1));
    else
        x = atan2(-R(2, 3), R(2, 2));
        y = atan2(-R(3, 1), sy);
        z = 0;
    end
    eul = [x y z] * 180 / pi;
end

function txt = titleText(registration, meshSource)
    txt = 'Polhemus trace on head mesh';
    pieces = {};
    if isfield(registration, 'source') && isstruct(registration.source)
        if isfield(registration.source, 'file') && ~isempty(registration.source.file)
            pieces{end + 1} = fileStem(registration.source.file); %#ok<AGROW>
        elseif isfield(registration.source, 'sessionType') && ...
                ~isempty(registration.source.sessionType)
            pieces{end + 1} = char(registration.source.sessionType); %#ok<AGROW>
        end
    end
    if isstruct(meshSource) && isfield(meshSource, 'meshStage')
        pieces{end + 1} = meshSource.meshStage; %#ok<AGROW>
    end
    if ~isempty(pieces)
        txt = [txt ': ' strjoin(pieces, ' / ')];
    end
end

function d = nearestVertexDistances(points, vertices)
    d = nan(size(points, 1), 1);
    if isempty(points) || isempty(vertices)
        return;
    end
    chunk = 100;
    for i = 1:chunk:size(points, 1)
        rows = i:min(i + chunk - 1, size(points, 1));
        D2 = pairwiseDistanceSquared(points(rows, :), vertices);
        [best, ~] = min(D2, [], 2);
        d(rows) = sqrt(max(best, 0));
    end
end

function D2 = pairwiseDistanceSquared(A, B)
    A = double(A);
    B = double(B);
    D2 = bsxfun(@plus, sum(A .^ 2, 2), sum(B .^ 2, 2)') - 2 * (A * B');
    D2(D2 < 0 & D2 > -1e-9) = 0;
end

function rows = registrationFiducialRows(registration, labels, fiducialLabels)
    labelRows = fiducialRows(labels, fiducialLabels);
    if all(isfinite(labelRows) & labelRows > 0)
        rows = labelRows;
    else
        rows = [];
    end
    if isfield(registration, 'sourceRows') && ~isempty(registration.sourceRows)
        storedRows = double(registration.sourceRows(:));
        storedRows = storedRows(isfinite(storedRows) & storedRows >= 1 & ...
            storedRows <= numel(labels));
        if isempty(rows) && numel(storedRows) >= numel(fiducialLabels)
            rows = storedRows(1:numel(fiducialLabels));
        elseif ~isempty(rows) && numel(storedRows) >= numel(fiducialLabels) && ...
                any(storedRows(1:numel(fiducialLabels)) ~= rows(:))
            warning('acsVisualizePolhemusTraceOnHead:StoredSourceRowsMismatch', ...
                ['Registration sourceRows differ from label-derived ', ...
                 'fiducial rows. Using label-derived rows for plotting ', ...
                 'and trace exclusion. stored=[%s], label=[%s]'], ...
                sprintf('%d ', storedRows(1:numel(fiducialLabels))), ...
                sprintf('%d ', rows));
        end
    end
    if isempty(rows)
        rows = labelRows;
    end
end

function rows = protectedFiducialRows(registration, labels, sourceRows, ...
        fiducialLabels)
    rows = sourceRows(:);
    rows = rows(isfinite(rows) & rows > 0 & rows <= numel(labels));
    labelRows = fiducialRows(labels, fiducialLabels);
    labelRows = labelRows(isfinite(labelRows) & labelRows > 0 & ...
        labelRows <= numel(labels));
    rows = unique([rows; labelRows(:); protocolFiducialRows(registration, ...
        labels, fiducialLabels)], 'stable');
end

function rows = protocolFiducialRows(registration, labels, fiducialLabels)
    rows = zeros(0, 1);
    if numel(labels) < numel(fiducialLabels)
        return;
    end
    if ~looksLikeFiducialLedSession(registration)
        return;
    end
    rows = (1:numel(fiducialLabels))';
end

function tf = looksLikeFiducialLedSession(registration)
    tf = false;
    if isfield(registration, 'source') && isstruct(registration.source) && ...
            isfield(registration.source, 'sessionType') && ...
            ~isempty(registration.source.sessionType)
        sessionType = lower(char(registration.source.sessionType));
        tf = any(strcmp(sessionType, {'monkeyimplants', 'scalptrace', ...
            'electrodeqc', 'legacy32', 'legacy64'}));
        return;
    end
    if isfield(registration, 'sourceRows') && ~isempty(registration.sourceRows)
        sourceRows = double(registration.sourceRows(:));
        tf = numel(sourceRows) >= 3 && all(sourceRows(1:3) == (1:3)');
    end
end

function rows = fiducialRows(labels, fiducialLabels)
    rows = nan(numel(fiducialLabels), 1);
    normalizedLabels = normalizeLabels(labels);
    used = false(numel(normalizedLabels), 1);
    for i = 1:numel(fiducialLabels)
        aliases = requestedFiducialAliases(fiducialLabels{i});
        for j = 1:numel(aliases)
            hit = find(strcmp(normalizedLabels, aliases{j}) & ~used, 1);
            if ~isempty(hit)
                rows(i) = hit;
                used(hit) = true;
                break;
            end
        end
    end
end

function aliases = requestedFiducialAliases(label)
    exact = normalizeLabels({label});
    expanded = normalizeLabels(fiducialAliases(label));
    aliases = [exact(:); expanded(:)];
    aliases = unique(aliases, 'stable');
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
        case {'lpa', 'leftpa', 'leftpreauricular'}
            aliases = {'Lpa', 'LeftPA', 'LeftPreauricular', ...
                'LeftPreauricularNotch'};
        case {'rpa', 'rightpa', 'rightpreauricular'}
            aliases = {'Rpa', 'RightPA', 'RightPreauricular', ...
                'RightPreauricularNotch'};
        otherwise
            aliases = {label};
    end
end

function labels = normalizeLabels(labelsIn)
    labels = cellfun(@lower, normalizeLabelCell(labelsIn), ...
        'UniformOutput', false);
    labels = regexprep(labels, '[^a-z0-9]', '');
end

function aliases = normalizeFiducialAliasSet(fiducialLabels)
    aliases = {};
    for i = 1:numel(fiducialLabels)
        theseAliases = normalizeLabels(fiducialAliases(fiducialLabels{i}));
        aliases = [aliases; theseAliases(:)]; %#ok<AGROW>
    end
    aliases = unique(aliases, 'stable');
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

function labels = defaultLabels(n)
    labels = cell(n, 1);
    for i = 1:n
        labels{i} = sprintf('point%03d', i);
    end
end

function rows = allTraceRows(traceSets)
    rows = [];
    for i = 1:numel(traceSets)
        rows = [rows; traceSets(i).rows(:)]; %#ok<AGROW>
    end
    rows = rows(isfinite(rows) & rows > 0);
end

function p = robustPercentile(values, pct)
    values = values(isfinite(values));
    if isempty(values)
        p = NaN;
        return;
    end
    values = sort(values(:));
    if pct <= 0
        p = values(1);
    elseif pct >= 100
        p = values(end);
    else
        idx = 1 + (numel(values) - 1) * pct / 100;
        lo = floor(idx);
        hi = ceil(idx);
        if lo == hi
            p = values(lo);
        else
            p = values(lo) + (values(hi) - values(lo)) * (idx - lo);
        end
    end
end

function fileName = defaultFigureFile(registration, meshSource)
    folder = '';
    stem = 'polhemusTrace';
    if isfield(registration, 'source') && isstruct(registration.source) && ...
            isfield(registration.source, 'file') && ~isempty(registration.source.file)
        folder = fileparts(registration.source.file);
        stem = fileStem(registration.source.file);
    elseif isstruct(meshSource) && isfield(meshSource, 'file') && ...
            ~isempty(meshSource.file)
        folder = fileparts(meshSource.file);
    end
    if isempty(folder), folder = pwd; end
    fileName = fullfile(folder, 'qc', [safeFilePart(stem) '_traceOnHead.png']);
end

function fileName = defaultManualRefinementFile(registration, meshSource)
    folder = '';
    stem = 'polhemusTrace';
    if isfield(registration, 'source') && isstruct(registration.source) && ...
            isfield(registration.source, 'file') && ~isempty(registration.source.file)
        folder = fileparts(registration.source.file);
        stem = fileStem(registration.source.file);
    elseif isstruct(meshSource) && isfield(meshSource, 'file') && ...
            ~isempty(meshSource.file)
        folder = fileparts(meshSource.file);
    end
    if isempty(folder), folder = pwd; end
    fileName = fullfile(folder, 'qc', ...
        [safeFilePart(stem) '_manualTraceRefinement.mat']);
end

function fileName = writeManualRefinement(fileName, report)
    [folder, stem, ext] = fileparts(fileName);
    if isempty(folder), folder = pwd; end
    if isempty(ext), ext = '.mat'; end
    ensureDir(folder);
    fileName = fullfile(folder, [stem ext]);
    switch lower(ext)
        case '.mat'
            manualRefinement = report; %#ok<NASGU>
            save(fileName, 'manualRefinement');
            writeJson(fullfile(folder, [stem '.json']), jsonReady(report));
        case '.json'
            writeJson(fileName, jsonReady(report));
            manualRefinement = report; %#ok<NASGU>
            save(fullfile(folder, [stem '.mat']), 'manualRefinement');
        otherwise
            error('acsVisualizePolhemusTraceOnHead:BadManualRefinementFile', ...
                'Manual refinement output must be .mat or .json.');
    end
end

function fileName = registrationSourceFile(registration)
    fileName = '';
    if isfield(registration, 'source') && isstruct(registration.source) && ...
            isfield(registration.source, 'file') && ~isempty(registration.source.file)
        fileName = registration.source.file;
    end
end

function printSummary(out)
    fprintf('\nPolhemus trace/head overlay\n');
    fprintf('  transformed points: %d\n', size(out.coordinatesMm, 1));
    fprintf('  trace sets: %d\n', numel(out.traceSets));
    for i = 1:numel(out.traceSets)
        fprintf('    %s: %d points\n', out.traceSets(i).name, ...
            size(out.traceSets(i).coordinatesMm, 1));
        if ~isempty(out.traceSets(i).labels)
            fprintf('      first label: %s\n', out.traceSets(i).labels{1});
        end
    end
    if ~isempty(out.fiducialRows)
        fprintf('  Polhemus fiducial rows: %s\n', ...
            sprintf('%d ', out.fiducialRows));
    end
    if isfield(out, 'protectedFiducialRows') && ...
            ~isempty(out.protectedFiducialRows)
        fprintf('  protected non-trace rows: %s\n', ...
            sprintf('%d ', out.protectedFiducialRows));
    end
    if isfield(out, 'modelFiducialsForPlot') && ...
            ~isempty(out.modelFiducialsForPlot.coordinatesMm)
        fprintf('  plotted model fiducials:\n');
        for i = 1:size(out.modelFiducialsForPlot.coordinatesMm, 1)
            vertexText = '';
            if isfield(out.modelFiducialsForPlot, 'selectedVertex') && ...
                    numel(out.modelFiducialsForPlot.selectedVertex) >= i && ...
                    isfinite(out.modelFiducialsForPlot.selectedVertex(i))
                vertexText = sprintf(' vertex %d,', ...
                    round(out.modelFiducialsForPlot.selectedVertex(i)));
            end
            fprintf('    %s:%s [%.4g %.4g %.4g] mm\n', ...
                out.modelFiducialsForPlot.labels{i}, vertexText, ...
                out.modelFiducialsForPlot.coordinatesMm(i, :));
        end
    end
    if isfinite(out.registrationRmseMm)
        fprintf('  fiducial registration: RMSE %.3g mm, weighted RMSE %.3g mm, max %.3g mm\n', ...
            out.registrationRmseMm, out.registrationWeightedRmseMm, ...
            out.registrationMaxErrorMm);
    end
    if isstruct(out.meshSource) && isfield(out.meshSource, 'file') && ...
            ~isempty(out.meshSource.file)
        fprintf('  mesh: %s\n', out.meshSource.file);
    end
    fprintf('  trace nearest-mesh distance: median %.3g mm, p95 %.3g mm, max %.3g mm\n', ...
        out.traceDistanceMedianMm, out.traceDistanceP95Mm, ...
        out.traceDistanceMaxMm);
    if ~isempty(out.qcFigure)
        fprintf('  QC figure: %s\n', out.qcFigure);
    end
    fprintf('\n');
end

function value = firstStruct(S)
    preferred = {'out', 'outSaved', 'outToSave', 'registration', ...
        'polhemusToCapMaker', 'modelFiducials', 'combinedLayout', 'layout'};
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
    value = [];
end

function fileName = expandUserPath(fileName)
    if isempty(fileName)
        return;
    end
    if startsWith(fileName, '~')
        homeDir = char(java.lang.System.getProperty('user.home'));
        fileName = fullfile(homeDir, fileName(2:end));
    end
end

function ensureDir(folder)
    if isempty(folder), return; end
    if exist(folder, 'dir') ~= 7
        mkdir(folder);
    end
end

function stem = fileStem(fileName)
    [~, stem] = fileparts(char(fileName));
end

function value = safeFilePart(value)
    value = regexprep(char(value), '[^A-Za-z0-9_.-]+', '_');
    value = regexprep(value, '_+', '_');
    value = regexprep(value, '^_+|_+$', '');
    if isempty(value), value = 'polhemusTrace'; end
end

function writeJson(fileName, S)
    fid = fopen(fileName, 'wt');
    if fid < 0
        error('acsVisualizePolhemusTraceOnHead:CouldNotWriteJson', ...
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
    elseif isa(S, 'datetime')
        S = char(S);
    elseif isa(S, 'triangulation') || isa(S, 'matlab.ui.Figure')
        S = char(class(S));
    end
end
