function out = acsVisualizeEegVoltageTopography(eegPredictionIn, layoutIn, varargin)
% ACSVISUALIZEEEGVOLTAGETOPOGRAPHY Visualize predicted EEG voltages on scalp.
%
% out = acsVisualizeEegVoltageTopography(eegPrediction, combinedLayout)
% renders predicted passive EEG voltages from acsPredictEegVoltagesFromTes
% on the capMaker scalp mesh and print-frame footprint.
%
% Name-value options:
%   valueMode       : 'referencedMicroV', 'rawMicroV', 'referencedV', or 'rawV'
%                     ['referencedMicroV']
%   interpolation   : 'rbf' or 'nearest' ['rbf']
%   rbfSigmaMM      : Gaussian RBF sigma; [] chooses from EEG spacing [[]]
%   colorLimit      : symmetric color limit; [] auto from EEG values [[]]
%   showTes         : overlay tES sites as black diamonds [true]
%   figureMode      : 'full' or 'footprintOnly' ['full']
%   labelMode       : 'raw' or 'stripCustom' electrode labels ['raw']
%   footprintTitle  : title for the footprint panel ['']
%   skinCacheFile   : explicit capMaker skin cache ['']
%   meshStage       : 'cap', 'fullHead', or 'auto' ['cap']
%   displayMaxFaces : maximum scalp faces shown [35000]
%   showFigures     : show topography figure [true]
%   saveFigures     : save topography figure [false]
%   closeFigure     : close figure before returning [false]
%   verbose         : print summary [true]

    if nargin < 2
        error('acsVisualizeEegVoltageTopography:MissingInput', ...
            'Provide eegPrediction and combinedLayout.');
    end
    opts = parseInputs(varargin{:});

    prediction = readStruct(eegPredictionIn, 'eegPrediction');
    layout = readStruct(layoutIn, 'layout');
    requireFields(prediction, {'eegNames'});
    requireFields(layout, {'names', 'layoutCoordinatesMm'});

    names = normalizeNames(layout.names);
    eegNames = normalizeNames(prediction.eegNames);
    eegRows = nameRows(eegNames, names, 'EEG');
    eegCoords = double(layout.layoutCoordinatesMm(eegRows, :));
    eegValues = predictionValues(prediction, opts.valueMode);
    if numel(eegValues) ~= numel(eegNames)
        error('acsVisualizeEegVoltageTopography:ValueCountMismatch', ...
            'Prediction has %d EEG values but %d EEG names.', ...
            numel(eegValues), numel(eegNames));
    end

    [TRskin, meshSource] = loadSkinMesh(layout, opts);
    [F, V] = displayMesh(TRskin.ConnectivityList, TRskin.Points, opts.displayMaxFaces);
    surfaceValues = interpolateValues(V, eegCoords, eegValues, opts);
    colorLimit = resolveColorLimit(opts.colorLimit, eegValues, surfaceValues);

    tesNames = {};
    tesCoords = zeros(0, 3);
    if opts.showTes
        [tesNames, tesCoords] = resolveTesSites(layout, names);
    end

    fig = [];
    if opts.showFigures || opts.saveFigures
        figVisible = 'off';
        if opts.showFigures, figVisible = 'on'; end
        fig = makeFigure(F, V, surfaceValues, eegCoords, eegValues, eegNames, ...
            tesCoords, tesNames, colorLimit, opts, figVisible);
    end

    out = struct();
    out.createdOn = char(datetime('now'));
    out.valueMode = opts.valueMode;
    out.units = valueUnits(opts.valueMode);
    out.interpolation = opts.interpolation;
    out.rbfSigmaMM = effectiveSigma(opts, eegCoords);
    out.colorLimit = colorLimit;
    out.eegNames = eegNames(:);
    out.eegCoordinatesMm = eegCoords;
    out.eegValues = eegValues(:);
    out.tesNames = tesNames(:);
    out.tesCoordinatesMm = tesCoords;
    out.meshSource = meshSource;
    out.figure = fig;
    out.qcFigure = '';

    if opts.saveFigures && isgraphics(fig)
        outDir = outputQcDir(prediction, layout);
        ensureDir(outDir);
        tag = getOptionalField(prediction, 'simulationTag', 'eegVoltage');
        out.qcFigure = fullfile(outDir, ...
            [safeFilePart(tag) '_eegVoltageTopography.png']);
        saveQcFigure(fig, out.qcFigure);
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
    p.FunctionName = 'acsVisualizeEegVoltageTopography';
    addParameter(p, 'valueMode', 'referencedMicroV', @(x) ischar(x) || isstring(x));
    addParameter(p, 'interpolation', 'rbf', @(x) ischar(x) || isstring(x));
    addParameter(p, 'rbfSigmaMM', [], ...
        @(x) isempty(x) || (isnumeric(x) && isscalar(x) && isfinite(x) && x > 0));
    addParameter(p, 'colorLimit', [], ...
        @(x) isempty(x) || (isnumeric(x) && isvector(x) && numel(x) <= 2 && all(isfinite(x))));
    addParameter(p, 'showTes', true, @isBoolLike);
    addParameter(p, 'figureMode', 'full', @(x) ischar(x) || isstring(x));
    addParameter(p, 'labelMode', 'raw', @(x) ischar(x) || isstring(x));
    addParameter(p, 'footprintTitle', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'skinCacheFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'meshStage', 'cap', @(x) ischar(x) || isstring(x));
    addParameter(p, 'displayMaxFaces', 35000, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0);
    addParameter(p, 'showFigures', true, @isBoolLike);
    addParameter(p, 'saveFigures', false, @isBoolLike);
    addParameter(p, 'closeFigure', false, @isBoolLike);
    addParameter(p, 'verbose', true, @isBoolLike);
    parse(p, varargin{:});
    opts = p.Results;
    opts.valueMode = normalizeValueMode(opts.valueMode);
    opts.interpolation = normalizeInterpolation(opts.interpolation);
    opts.showTes = logical(opts.showTes);
    opts.figureMode = normalizeFigureMode(opts.figureMode);
    opts.labelMode = normalizeLabelMode(opts.labelMode);
    opts.footprintTitle = char(opts.footprintTitle);
    opts.skinCacheFile = expandUserPath(char(opts.skinCacheFile));
    opts.meshStage = normalizeMeshStage(opts.meshStage);
    opts.displayMaxFaces = round(double(opts.displayMaxFaces));
    opts.showFigures = logical(opts.showFigures);
    opts.saveFigures = logical(opts.saveFigures);
    opts.closeFigure = logical(opts.closeFigure);
    opts.verbose = logical(opts.verbose);
end

function mode = normalizeFigureMode(mode)
    mode = lower(strtrim(char(mode)));
    switch mode
        case {'full', 'diagnostic', 'all', 'threepanel', 'three-panel'}
            mode = 'full';
        case {'footprintonly', 'footprint', 'poster', 'single', 'singlepanel', 'single-panel'}
            mode = 'footprintOnly';
        otherwise
            error('acsVisualizeEegVoltageTopography:BadFigureMode', ...
                'figureMode must be ''full'' or ''footprintOnly''.');
    end
end

function mode = normalizeLabelMode(mode)
    mode = lower(strtrim(char(mode)));
    switch mode
        case {'raw', 'original'}
            mode = 'raw';
        case {'stripcustom', 'clean', 'short', 'poster'}
            mode = 'stripCustom';
        otherwise
            error('acsVisualizeEegVoltageTopography:BadLabelMode', ...
                'labelMode must be ''raw'' or ''stripCustom''.');
    end
end

function stage = normalizeMeshStage(stageIn)
    stage = lower(strtrim(char(stageIn)));
    switch stage
        case {'cap', 'cropped', 'croppedcap'}
            stage = 'cap';
        case {'fullhead', 'full', 'head', 'fiducial'}
            stage = 'fullHead';
        case {'auto'}
            stage = 'auto';
        otherwise
            error('acsVisualizeEegVoltageTopography:BadMeshStage', ...
                'meshStage must be ''cap'', ''fullHead'', or ''auto''.');
    end
end

function tf = isBoolLike(x)
    tf = (islogical(x) || isnumeric(x)) && isscalar(x);
end

function mode = normalizeValueMode(mode)
    mode = lower(strtrim(char(mode)));
    switch mode
        case {'referencedmicrov', 'referenceduv', 'microv', 'uv'}
            mode = 'referencedMicroV';
        case {'rawmicrov', 'rawuv'}
            mode = 'rawMicroV';
        case {'referencedv', 'refv'}
            mode = 'referencedV';
        case {'rawv'}
            mode = 'rawV';
        otherwise
            error('acsVisualizeEegVoltageTopography:BadValueMode', ...
                ['valueMode must be referencedMicroV, rawMicroV, ', ...
                 'referencedV, or rawV.']);
    end
end

function mode = normalizeInterpolation(mode)
    mode = lower(strtrim(char(mode)));
    switch mode
        case {'rbf', 'gaussian', 'smooth'}
            mode = 'rbf';
        case {'nearest', 'nn'}
            mode = 'nearest';
        otherwise
            error('acsVisualizeEegVoltageTopography:BadInterpolation', ...
                'interpolation must be ''rbf'' or ''nearest''.');
    end
end

function S = readStruct(value, label)
    if isstruct(value)
        S = value;
        return;
    end
    if ~(ischar(value) || isstring(value))
        error('acsVisualizeEegVoltageTopography:BadInput', ...
            '%s must be a struct or MAT file.', label);
    end
    fileName = char(value);
    if exist(fileName, 'file') ~= 2
        error('acsVisualizeEegVoltageTopography:MissingFile', ...
            'File not found: %s', fileName);
    end
    data = load(fileName);
    S = firstStruct(data);
end

function value = firstStruct(data)
    names = fieldnames(data);
    for i = 1:numel(names)
        if isstruct(data.(names{i}))
            value = data.(names{i});
            return;
        end
    end
    error('acsVisualizeEegVoltageTopography:NoStructInMat', ...
        'MAT file did not contain a struct.');
end

function requireFields(S, fields)
    for i = 1:numel(fields)
        if ~isfield(S, fields{i}) || isempty(S.(fields{i}))
            error('acsVisualizeEegVoltageTopography:MissingField', ...
                'Input is missing required field "%s".', fields{i});
        end
    end
end

function names = normalizeNames(names)
    if isempty(names)
        names = {};
    elseif ischar(names)
        names = {names};
    elseif isstring(names)
        names = cellstr(names(:));
    elseif iscell(names)
        names = cellfun(@char, names(:), 'UniformOutput', false);
    else
        error('acsVisualizeEegVoltageTopography:BadNames', ...
            'Names must be char, string, or cell array.');
    end
    names = names(:);
end

function rows = nameRows(queryNames, allNames, label)
    rows = zeros(numel(queryNames), 1);
    for i = 1:numel(queryNames)
        idx = find(strcmpi(queryNames{i}, allNames), 1);
        if isempty(idx)
            error('acsVisualizeEegVoltageTopography:MissingName', ...
                '%s channel "%s" was not found in layout.names.', ...
                label, queryNames{i});
        end
        rows(i) = idx;
    end
end

function values = predictionValues(prediction, valueMode)
    switch valueMode
        case 'referencedMicroV'
            fieldName = 'eegVoltageReferencedMicroV';
            scale = 1;
        case 'rawMicroV'
            fieldName = 'eegVoltageRawV';
            scale = 1e6;
        case 'referencedV'
            fieldName = 'eegVoltageReferencedV';
            scale = 1;
        case 'rawV'
            fieldName = 'eegVoltageRawV';
            scale = 1;
        otherwise
            error('acsVisualizeEegVoltageTopography:BadValueMode', ...
                'Unsupported valueMode: %s', valueMode);
    end
    if ~isfield(prediction, fieldName) || isempty(prediction.(fieldName))
        error('acsVisualizeEegVoltageTopography:MissingValues', ...
            'Prediction is missing "%s".', fieldName);
    end
    values = double(prediction.(fieldName)(:)) * scale;
end

function units = valueUnits(valueMode)
    switch valueMode
        case {'referencedMicroV', 'rawMicroV'}
            units = 'microV';
        otherwise
            units = 'V';
    end
end

function [TRskin, source] = loadSkinMesh(layout, opts)
    cacheFile = resolveSkinCacheFile(layout, opts);
    if ~isempty(cacheFile) && exist(cacheFile, 'file') == 2
        raw = load(cacheFile);
        [TRskin, source] = skinMeshFromCache(raw, cacheFile, opts.meshStage);
        return;
    end
    if isfield(layout, 'targetDiagnostics') && ...
            isfield(layout.targetDiagnostics, 'meshEdges')
        % Kept as a future hook; current reports intentionally strip heavy mesh.
    end
    error('acsVisualizeEegVoltageTopography:MissingSkinMesh', ...
        ['Could not find a skin cache with the requested mesh. ', ...
         'Rebuild the combined layout with surfaceSource=''capMaker''.']);
end

function cacheFile = resolveSkinCacheFile(layout, opts)
    cacheFile = opts.skinCacheFile;
    if ~isempty(cacheFile)
        return;
    end
    if isfield(layout, 'layout') && isfield(layout.layout, 'skin') && ...
            isfield(layout.layout.skin, 'cacheFile') && ...
            ~isempty(layout.layout.skin.cacheFile)
        cacheFile = expandUserPath(char(layout.layout.skin.cacheFile));
        return;
    end
    if isfield(layout, 'skin') && isstruct(layout.skin) && ...
            isfield(layout.skin, 'cacheFile') && ~isempty(layout.skin.cacheFile)
        cacheFile = expandUserPath(char(layout.skin.cacheFile));
        return;
    end
    cacheFile = '';
end

function [TRskin, source] = skinMeshFromCache(raw, cacheFile, meshStage)
    switch meshStage
        case 'cap'
            [TRskin, meshStageUsed] = capMeshFromCache(raw, cacheFile);
        case 'fullHead'
            [TRskin, meshStageUsed] = fullHeadMeshFromCache(raw, cacheFile);
        case 'auto'
            try
                [TRskin, meshStageUsed] = fullHeadMeshFromCache(raw, cacheFile);
            catch
                [TRskin, meshStageUsed] = capMeshFromCache(raw, cacheFile);
            end
        otherwise
            error('acsVisualizeEegVoltageTopography:BadMeshStage', ...
                'Unsupported meshStage: %s', meshStage);
    end
    source = struct('cacheFile', cacheFile, 'meshStage', meshStageUsed);
end

function [TRskin, meshStage] = capMeshFromCache(raw, cacheFile)
    if isfield(raw, 'TRskin') && ~isempty(raw.TRskin)
        TRskin = ensureTri(raw.TRskin);
        meshStage = 'cap';
        return;
    end
    error('acsVisualizeEegVoltageTopography:MissingCapMesh', ...
        'Skin cache does not contain TRskin: %s', cacheFile);
end

function [TRskin, meshStage] = fullHeadMeshFromCache(raw, cacheFile)
    if isfield(raw, 'TRfiducialHead') && ~isempty(raw.TRfiducialHead)
        TRskin = ensureTri(raw.TRfiducialHead);
        meshStage = 'fullHead';
        return;
    end
    if isfield(raw, 'meta') && isstruct(raw.meta) && ...
            isfield(raw.meta, 'fiducialHead') && ...
            isstruct(raw.meta.fiducialHead) && ...
            isfield(raw.meta.fiducialHead, 'TR') && ...
            ~isempty(raw.meta.fiducialHead.TR)
        TRskin = ensureTri(raw.meta.fiducialHead.TR);
        meshStage = 'fullHead';
        return;
    end
    if isfield(raw, 'TRstableHead') && ~isempty(raw.TRstableHead) && ...
            isfield(raw, 'meta') && isstruct(raw.meta)
        TRstable = ensureTri(raw.TRstableHead);
        pointsPrint = stableWorldToPrintMm(TRstable.Points, raw.meta);
        TRskin = triangulation(TRstable.ConnectivityList, pointsPrint);
        meshStage = 'fullHead';
        return;
    end
    error('acsVisualizeEegVoltageTopography:MissingFullHeadMesh', ...
        ['Skin cache does not contain a full-head mesh: %s\n', ...
         'Expected TRfiducialHead or TRstableHead.'], cacheFile);
end

function TR = ensureTri(value)
    if isa(value, 'triangulation')
        TR = value;
    elseif isstruct(value) && isfield(value, 'ConnectivityList') && isfield(value, 'Points')
        TR = triangulation(double(value.ConnectivityList), double(value.Points));
    else
        error('acsVisualizeEegVoltageTopography:BadTriangulation', ...
            'Expected a triangulation or struct with Points and ConnectivityList.');
    end
end

function pointsPrint = stableWorldToPrintMm(pointsStable, meta)
    requireCapMakerMeta(meta);
    finalWorldMm = (double(meta.align.R) * double(pointsStable)')';
    pointsPrint = applyAffineToPoints(meta.print.T_world2print, finalWorldMm);
end

function requireCapMakerMeta(meta)
    ok = isstruct(meta) && isfield(meta, 'print') && ...
        isfield(meta.print, 'T_world2print') && ...
        isfield(meta, 'align') && isfield(meta.align, 'R');
    if ~ok
        error('acsVisualizeEegVoltageTopography:MissingCapMakerMeta', ...
            ['Full-head TRstableHead topographies require skin cache metadata ', ...
             'with print.T_world2print and align.R.']);
    end
end

function pointsOut = applyAffineToPoints(M, pointsIn)
    pointsHom = [double(pointsIn), ones(size(pointsIn, 1), 1)];
    pointsHom = (double(M) * pointsHom')';
    pointsOut = pointsHom(:, 1:3);
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

function surfaceValues = interpolateValues(points, electrodeCoords, values, opts)
    finite = all(isfinite(electrodeCoords), 2) & isfinite(values(:));
    electrodeCoords = electrodeCoords(finite, :);
    values = values(finite);
    if isempty(values)
        surfaceValues = nan(size(points, 1), 1);
        return;
    end
    switch opts.interpolation
        case 'nearest'
            D2 = pairwiseDistanceSquared(points, electrodeCoords);
            [~, idx] = min(D2, [], 2);
            surfaceValues = values(idx);
        case 'rbf'
            sigma = effectiveSigma(opts, electrodeCoords);
            D2 = pairwiseDistanceSquared(points, electrodeCoords);
            W = exp(-D2 ./ (2 * sigma ^ 2));
            W(~isfinite(W)) = 0;
            denom = sum(W, 2);
            denom(denom <= eps) = NaN;
            surfaceValues = (W * values(:)) ./ denom;
        otherwise
            error('acsVisualizeEegVoltageTopography:BadInterpolation', ...
                'Unsupported interpolation: %s', opts.interpolation);
    end
end

function sigma = effectiveSigma(opts, electrodeCoords)
    if ~isempty(opts.rbfSigmaMM)
        sigma = double(opts.rbfSigmaMM);
        return;
    end
    if size(electrodeCoords, 1) < 2
        sigma = 20;
        return;
    end
    D = sqrt(pairwiseDistanceSquared(electrodeCoords, electrodeCoords));
    D(1:size(D, 1) + 1:end) = inf;
    nearest = min(D, [], 2);
    nearest = nearest(isfinite(nearest) & nearest > 0);
    if isempty(nearest)
        sigma = 20;
    else
        sigma = max(5, 0.85 * median(nearest));
    end
end

function D2 = pairwiseDistanceSquared(A, B)
    A = double(A);
    B = double(B);
    D2 = bsxfun(@plus, sum(A .^ 2, 2), sum(B .^ 2, 2)') - 2 * (A * B');
    D2(D2 < 0 & D2 > -1e-9) = 0;
end

function colorLimit = resolveColorLimit(requested, eegValues, surfaceValues)
    if isempty(requested)
        finiteValues = [eegValues(:); surfaceValues(:)];
        finiteValues = finiteValues(isfinite(finiteValues));
        if isempty(finiteValues)
            colorLimit = [-1 1];
        else
            maxAbs = max(abs(finiteValues));
            if maxAbs <= 0, maxAbs = 1; end
            colorLimit = [-maxAbs maxAbs];
        end
    else
        requested = double(requested(:)');
        if numel(requested) == 1
            colorLimit = abs(requested) * [-1 1];
        else
            colorLimit = requested;
        end
    end
    if colorLimit(1) == colorLimit(2)
        colorLimit = colorLimit + [-1 1];
    end
end

function [tesNames, tesCoords] = resolveTesSites(layout, allNames)
    if isfield(layout, 'tesNames') && ~isempty(layout.tesNames)
        tesNames = normalizeNames(layout.tesNames);
        tesRows = nameRows(tesNames, allNames, 'tES');
    elseif isfield(layout, 'siteRoles') && ~isempty(layout.siteRoles)
        roles = normalizeNames(layout.siteRoles);
        tesRows = find(strcmpi(roles, 'tES'));
        tesNames = allNames(tesRows);
    else
        tesRows = [];
        tesNames = {};
    end
    if isempty(tesRows)
        tesCoords = zeros(0, 3);
    else
        tesCoords = double(layout.layoutCoordinatesMm(tesRows, :));
    end
end

function fig = makeFigure(F, V, surfaceValues, eegCoords, eegValues, eegNames, ...
        tesCoords, tesNames, colorLimit, opts, figVisible)
    units = valueUnits(opts.valueMode);
    eegDisplayNames = displayElectrodeNames(eegNames, opts.labelMode);
    tesDisplayNames = displayElectrodeNames(tesNames, opts.labelMode);
    fig = figure('Name', 'Predicted EEG Voltage Topography', ...
        'Color', 'w', 'Visible', figVisible, ...
        'WindowStyle', 'normal');
    if strcmp(opts.figureMode, 'footprintOnly')
        set(fig, 'Position', [120 120 760 680]);
        ax = axes('Parent', fig, 'Units', 'normalized', ...
            'Position', [0.11 0.12 0.74 0.78]);
        plotFootprintPanel(ax, F, V, surfaceValues, eegCoords, eegValues, ...
            eegDisplayNames, tesCoords, colorLimit, units, opts);
        drawnow;
        if strcmpi(figVisible, 'on')
            figure(fig);
        end
        return;
    end

    set(fig, 'Position', [80 80 1500 680]);
    tiledlayout(fig, 1, 3, 'Padding', 'compact', 'TileSpacing', 'compact');

    ax1 = nexttile;
    patch(ax1, 'Faces', F, 'Vertices', V, ...
        'FaceVertexCData', surfaceValues, ...
        'FaceColor', 'interp', ...
        'EdgeColor', 'none', ...
        'FaceAlpha', 0.96);
    hold(ax1, 'on');
    scatter3(ax1, eegCoords(:, 1), eegCoords(:, 2), eegCoords(:, 3), ...
        85, eegValues, 'filled', 'MarkerEdgeColor', 'k', 'LineWidth', 0.8);
    addLabels3(ax1, eegCoords, eegDisplayNames, [0 0 0]);
    if ~isempty(tesCoords)
        scatter3(ax1, tesCoords(:, 1), tesCoords(:, 2), tesCoords(:, 3), ...
            75, 'kd', 'filled');
        addLabels3(ax1, tesCoords, tesDisplayNames, [0.05 0.05 0.05]);
    end
    formatSurfaceAxes(ax1, V);
    colormap(ax1, divergingMap(256));
    caxis(ax1, colorLimit);
    cb = colorbar(ax1);
    ylabel(cb, units);
    title(ax1, '3D capMaker scalp topography');

    ax2 = nexttile;
    plotFootprintPanel(ax2, F, V, surfaceValues, eegCoords, eegValues, ...
        eegDisplayNames, tesCoords, colorLimit, units, opts);

    ax3 = nexttile;
    bar(ax3, eegValues, 'FaceColor', [0.25 0.48 0.78]);
    set(ax3, 'XTick', 1:numel(eegNames), ...
        'XTickLabel', eegDisplayNames, 'XTickLabelRotation', 35);
    ylabel(ax3, units);
    grid(ax3, 'on');
    title(ax3, 'EEG channel values');
    drawnow;
    if strcmpi(figVisible, 'on')
        figure(fig);
    end
end

function plotFootprintPanel(ax, F, V, surfaceValues, eegCoords, eegValues, ...
        eegNames, tesCoords, colorLimit, units, opts)
    patch(ax, 'Faces', F, 'Vertices', V(:, 1:2), ...
        'FaceVertexCData', surfaceValues, ...
        'FaceColor', 'interp', ...
        'EdgeColor', 'none');
    hold(ax, 'on');
    scatter(ax, eegCoords(:, 1), eegCoords(:, 2), ...
        75, eegValues, 'filled', 'MarkerEdgeColor', 'k', 'LineWidth', 0.8);
    addLabels2(ax, eegCoords(:, 1:2), eegNames, [0 0 0]);
    tesHandle = [];
    if ~isempty(tesCoords)
        tesHandle = scatter(ax, tesCoords(:, 1), tesCoords(:, 2), ...
            72, 'kd', 'filled');
    end
    axis(ax, 'equal');
    axis(ax, 'tight');
    grid(ax, 'on');
    xlabel(ax, 'print X (mm)');
    ylabel(ax, 'print Y (mm)');
    colormap(ax, divergingMap(256));
    caxis(ax, colorLimit);
    cb = colorbar(ax);
    ylabel(cb, units);
    title(ax, footprintPanelTitle(opts), 'Interpreter', 'none');
    if ~isempty(tesHandle)
        lgd = legend(ax, tesHandle, {'tES electrode location'}, ...
            'Location', 'northeast', ...
            'Interpreter', 'none', ...
            'Box', 'off');
        placeTesLegend(lgd, opts);
    end
end

function placeTesLegend(lgd, opts)
    if ~strcmp(opts.figureMode, 'footprintOnly')
        return;
    end
    set(lgd, ...
        'Units', 'normalized', ...
        'Position', [0.715 0.035 0.255 0.055]);
    try
        lgd.ItemTokenSize = [14 8];
    catch
    end
end

function titleText = footprintPanelTitle(opts)
    if ~isempty(opts.footprintTitle)
        titleText = opts.footprintTitle;
    elseif strcmp(opts.figureMode, 'footprintOnly')
        titleText = 'Predicted EEG topography';
    else
        titleText = 'Print-frame footprint';
    end
end

function formatSurfaceAxes(ax, V)
    boundsMin = min(V, [], 1);
    boundsMax = max(V, [], 1);
    pad = max(1, 0.04 * max(boundsMax - boundsMin));
    axis(ax, 'equal');
    axis(ax, 'vis3d');
    axis(ax, 'off');
    xlim(ax, [boundsMin(1) - pad boundsMax(1) + pad]);
    ylim(ax, [boundsMin(2) - pad boundsMax(2) + pad]);
    zlim(ax, [boundsMin(3) - pad boundsMax(3) + pad]);
    view(ax, 35, 25);
    camlight(ax, 'headlight');
    lighting(ax, 'gouraud');
end

function addLabels3(ax, points, labels, colorValue)
    for i = 1:size(points, 1)
        text(ax, points(i, 1), points(i, 2), points(i, 3), ...
            ['  ' labels{i}], ...
            'Interpreter', 'none', ...
            'FontSize', 8, ...
            'FontWeight', 'bold', ...
            'Color', colorValue);
    end
end

function addLabels2(ax, points, labels, colorValue)
    for i = 1:size(points, 1)
        text(ax, points(i, 1), points(i, 2), ...
            ['  ' labels{i}], ...
            'Interpreter', 'none', ...
            'FontSize', 8, ...
            'FontWeight', 'bold', ...
            'Color', colorValue);
    end
end

function displayNames = displayElectrodeNames(names, labelMode)
    displayNames = names(:);
    if strcmp(labelMode, 'raw')
        return;
    end
    for i = 1:numel(displayNames)
        displayNames{i} = regexprep(displayNames{i}, '^custom', '', 'ignorecase');
    end
end

function cmap = divergingMap(n)
    if nargin < 1, n = 256; end
    anchors = [ ...
        0.09 0.23 0.55
        0.28 0.57 0.78
        0.96 0.96 0.93
        0.90 0.45 0.24
        0.56 0.10 0.18];
    x = linspace(0, 1, size(anchors, 1));
    xi = linspace(0, 1, n);
    cmap = interp1(x, anchors, xi, 'linear');
    cmap = min(max(cmap, 0), 1);
end

function outDir = outputQcDir(prediction, layout)
    outDir = '';
    if isfield(prediction, 't1File') && ~isempty(prediction.t1File)
        outDir = fullfile(fileparts(prediction.t1File), 'qc');
    elseif isfield(layout, 't1File') && ~isempty(layout.t1File)
        outDir = fullfile(fileparts(layout.t1File), 'qc');
    else
        outDir = pwd;
    end
end

function value = getOptionalField(S, fieldName, defaultValue)
    if isfield(S, fieldName) && ~isempty(S.(fieldName))
        value = S.(fieldName);
    else
        value = defaultValue;
    end
end

function ensureDir(folder)
    if exist(folder, 'dir') ~= 7
        mkdir(folder);
    end
end

function saveQcFigure(fig, fileName)
    try
        exportgraphics(fig, fileName, 'Resolution', 150);
    catch
        saveas(fig, fileName);
    end
end

function name = safeFilePart(name)
    name = regexprep(char(name), '[^A-Za-z0-9_+-]', '_');
    if isempty(name)
        name = 'eegVoltage';
    end
end

function pathOut = expandUserPath(pathIn)
    pathOut = char(pathIn);
    if isempty(pathOut)
        return;
    end
    if startsWith(pathOut, '~')
        homeDir = char(java.lang.System.getProperty('user.home'));
        if numel(pathOut) == 1
            pathOut = homeDir;
        elseif any(pathOut(2) == ['/' filesep])
            pathOut = fullfile(homeDir, pathOut(3:end));
        end
    end
end

function printSummary(out)
    finiteValues = out.eegValues(isfinite(out.eegValues));
    fprintf('\nPredicted EEG voltage topography\n');
    fprintf('  EEG channels: %d\n', numel(out.eegNames));
    fprintf('  value mode: %s (%s)\n', out.valueMode, out.units);
    fprintf('  interpolation: %s', out.interpolation);
    if strcmp(out.interpolation, 'rbf')
        fprintf(' (sigma %.3g mm)', out.rbfSigmaMM);
    end
    fprintf('\n');
    if isempty(finiteValues)
        fprintf('  value range: no finite EEG values\n\n');
    else
        fprintf('  value range: %.6g to %.6g %s\n\n', ...
            min(finiteValues), max(finiteValues), out.units);
    end
end
