function out = acsInteractivelyRepairSkinDents(skinIn, varargin)
% ACSINTERACTIVELYREPAIRSKINDENTS Manually touch up local skin-mesh dents.
%
% out = acsInteractivelyRepairSkinDents(cacheFile) opens a brush-style GUI
% for selecting vertices on a capMaker/ROAST skin mesh and pulling those
% vertices toward a locally smoothed surface. This is intended as a small
% manual refinement after the automated post-warp dent repair pass.
%
% Name-value options:
%   meshStage        : 'auto', 'stableHead', 'fiducialHead', or 'skin' ['auto']
%   outputFile       : repaired cache MAT file ['*_manualDentRepair.mat']
%   editMode         : 'auto', 'always', or 'never' ['auto']
%   force            : overwrite existing output [false]
%   brushRadiusMm    : initial spherical brush radius [4]
%   dentMetric       : 'localLaplacian', 'radialEnvelope', or 'hybrid' ['localLaplacian']
%   dentRadiusMm     : local diagnostic radius [8]
%   dentMinDepthMm   : minimum dent depth for magenta markers [1]
%   dentNormalAngleDeg : normal roughness threshold for shallow creases [35]
%   repairBlend      : fraction of dent-depth correction per repair [0.85]
%   repairMinMoveMm  : minimum move for selected vertices with shallow depth [0]
%   repairMaxMoveMm  : maximum move per repair [8]
%   repairFairingIterations : selected-neighborhood smoothing after repair [1]
%   repairFairingBlend : selected-neighborhood smoothing blend [0.20]
%   selectOnlyDentFlags : restrict painting to currently flagged vertices [true]
%   selectionDepthMm : camera-depth gate for avoiding back-side selection [3]
%   showFigures      : open GUI/QC figure [true]
%   saveFigures      : save QC PNG [true]
%   verbose          : print summary [true]

    if nargin < 1 || isempty(skinIn)
        error('acsInteractivelyRepairSkinDents:MissingInput', ...
            'Provide a skin cache, triangulation, or struct containing a skin mesh.');
    end

    opts = parseInputs(varargin{:});
    source = readSkinSource(skinIn, opts);
    opts = resolveOutputFile(source, opts);

    existing = struct();
    if ~isempty(opts.outputFile) && exist(opts.outputFile, 'file') == 2
        existing = loadExistingRepair(opts.outputFile);
    end

    existingIsStale = existingRepairIsStale(existing, source.TR);
    openGui = shouldOpenGui(opts.outputFile, opts, existingIsStale);
    if ~openGui
        if ~isempty(fieldnames(existing)) && ~existingIsStale
            repairedSource = readSkinSource(opts.outputFile, opts);
            out = fillRepairOutputDefaults(existing, source, repairedSource, opts);
            out.reused = true;
            if opts.showFigures
                out.figure = makeQcFigure(repairedSource.TR, out, opts, 'on');
            end
            if opts.verbose
                fprintf('Manual skin dent repair already exists; reusing %s\n', ...
                    opts.outputFile);
            end
            return;
        end
        if existingIsStale
            out = noOpOutput(source, opts, ...
                'Saved manual repair does not match the current input mesh.');
            if opts.verbose
                fprintf('Manual skin dent repair skipped: %s\n', out.message);
            end
            return;
        end
        out = noOpOutput(source, opts, ...
            'No saved manual repair exists and editMode/showFigures did not open the GUI.');
        if opts.verbose
            fprintf('Manual skin dent repair skipped: %s\n', out.message);
        end
        return;
    end

    state = initializeRepairState(source.TR, existing, opts);
    [state, accepted] = repairGui(source.TR, state, opts);
    if ~accepted
        out = noOpOutput(source, opts, 'Manual skin dent repair was canceled.');
        if opts.verbose
            fprintf('Manual skin dent repair canceled; using original mesh cache.\n');
        end
        return;
    end

    out = buildOutput(source, state, opts);
    writeRepairedCache(source, state.TR, out, opts);

    fig = [];
    qcFile = '';
    if opts.showFigures || opts.saveFigures
        figVisible = 'off';
        if opts.showFigures
            figVisible = 'on';
        end
        fig = makeQcFigure(state.TR, out, opts, figVisible);
        if opts.saveFigures
            qcFile = fullfile(fileparts(opts.outputFile), 'qc', ...
                [stripMatExtension(getFileName(opts.outputFile)) '_qc.png']);
            ensureDir(fileparts(qcFile));
            saveQcFigure(fig, qcFile);
        end
        if ~opts.showFigures && isgraphics(fig)
            close(fig);
            fig = [];
        end
    end
    out.qcFigure = qcFile;
    if isgraphics(fig)
        out.figure = fig;
    end

    saveRepairReport(out, opts);

    if opts.verbose
        printSummary(out);
    end
end

function opts = parseInputs(varargin)
    p = inputParser;
    p.FunctionName = 'acsInteractivelyRepairSkinDents';
    addParameter(p, 'meshStage', 'auto', @(x) ischar(x) || isstring(x));
    addParameter(p, 'outputFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'outputTag', 'manualDentRepair', @(x) ischar(x) || isstring(x));
    addParameter(p, 'editMode', 'auto', @(x) ischar(x) || isstring(x));
    addParameter(p, 'force', false, @isBoolLike);
    addParameter(p, 'brushRadiusMm', 4, @isPositiveScalar);
    addParameter(p, 'displayMaxFaces', 120000, @isPositiveScalar);
    addParameter(p, 'meshAlpha', 0.82, @isUnitScalar);
    addParameter(p, 'dentMetric', 'localLaplacian', @(x) ischar(x) || isstring(x));
    addParameter(p, 'dentRadiusMm', 8, @isPositiveScalar);
    addParameter(p, 'dentEnvelopePercentile', 75, @isPercentScalar);
    addParameter(p, 'dentMinDepthMm', 1, @isNonnegativeScalar);
    addParameter(p, 'dentNormalAngleDeg', 35, @isNonnegativeScalar);
    addParameter(p, 'dentLocalSmoothingIterations', 3, @isNonnegativeScalar);
    addParameter(p, 'dentDirectionRadialWeight', 0.25, @isUnitScalar);
    addParameter(p, 'dentMaxRings', 8, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 1);
    addParameter(p, 'autoFlagDisplayMax', 600, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 1);
    addParameter(p, 'repairBlend', 0.85, @isUnitScalar);
    addParameter(p, 'repairMinMoveMm', 0, @isNonnegativeScalar);
    addParameter(p, 'repairMaxMoveMm', 8, @isPositiveScalar);
    addParameter(p, 'repairFairingIterations', 1, @isNonnegativeScalar);
    addParameter(p, 'repairFairingBlend', 0.20, @isUnitScalar);
    addParameter(p, 'repairFairingRings', 1, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0);
    addParameter(p, 'selectOnlyDentFlags', true, @isBoolLike);
    addParameter(p, 'selectionDepthMm', 3, @isPositiveScalar);
    addParameter(p, 'showFigures', true, @isBoolLike);
    addParameter(p, 'saveFigures', true, @isBoolLike);
    addParameter(p, 'verbose', true, @isBoolLike);
    parse(p, varargin{:});

    opts = p.Results;
    opts.meshStage = normalizeMeshStage(opts.meshStage);
    opts.outputFile = expandUserPath(char(opts.outputFile));
    opts.outputTag = safeTag(char(opts.outputTag));
    opts.editMode = normalizeEditMode(opts.editMode);
    opts.force = logical(opts.force);
    opts.brushRadiusMm = double(opts.brushRadiusMm);
    opts.displayMaxFaces = round(double(opts.displayMaxFaces));
    opts.meshAlpha = double(opts.meshAlpha);
    opts.dentMetric = normalizeDentMetric(opts.dentMetric);
    opts.dentRadiusMm = double(opts.dentRadiusMm);
    opts.dentEnvelopePercentile = double(opts.dentEnvelopePercentile);
    opts.dentMinDepthMm = double(opts.dentMinDepthMm);
    opts.dentNormalAngleDeg = double(opts.dentNormalAngleDeg);
    opts.dentLocalSmoothingIterations = round(double( ...
        opts.dentLocalSmoothingIterations));
    opts.dentDirectionRadialWeight = double(opts.dentDirectionRadialWeight);
    opts.dentMaxRings = round(double(opts.dentMaxRings));
    opts.autoFlagDisplayMax = round(double(opts.autoFlagDisplayMax));
    opts.repairBlend = double(opts.repairBlend);
    opts.repairMinMoveMm = double(opts.repairMinMoveMm);
    opts.repairMaxMoveMm = double(opts.repairMaxMoveMm);
    opts.repairFairingIterations = round(double(opts.repairFairingIterations));
    opts.repairFairingBlend = double(opts.repairFairingBlend);
    opts.repairFairingRings = round(double(opts.repairFairingRings));
    opts.selectOnlyDentFlags = logical(opts.selectOnlyDentFlags);
    opts.selectionDepthMm = double(opts.selectionDepthMm);
    opts.showFigures = logical(opts.showFigures);
    opts.saveFigures = logical(opts.saveFigures);
    opts.verbose = logical(opts.verbose);
end

function tf = isBoolLike(x)
    tf = (islogical(x) || isnumeric(x)) && isscalar(x);
end

function tf = isPositiveScalar(x)
    tf = isnumeric(x) && isscalar(x) && isfinite(x) && x > 0;
end

function tf = isNonnegativeScalar(x)
    tf = isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0;
end

function tf = isPercentScalar(x)
    tf = isnumeric(x) && isscalar(x) && isfinite(x) && x > 0 && x <= 100;
end

function tf = isUnitScalar(x)
    tf = isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0 && x <= 1;
end

function stage = normalizeMeshStage(stage)
    stage = lower(strtrim(char(stage)));
    switch regexprep(stage, '[\s_\-]+', '')
        case 'auto'
            stage = 'auto';
        case {'stablehead', 'fullhead', 'precrop'}
            stage = 'stableHead';
        case {'fiducialhead', 'printfullhead'}
            stage = 'fiducialHead';
        case {'skin', 'trskin', 'cap', 'cropped'}
            stage = 'skin';
        otherwise
            error('acsInteractivelyRepairSkinDents:BadMeshStage', ...
                'meshStage must be auto, stableHead, fiducialHead, or skin.');
    end
end

function mode = normalizeEditMode(mode)
    mode = lower(strtrim(char(mode)));
    switch mode
        case {'auto', 'always', 'never'}
            return;
        otherwise
            error('acsInteractivelyRepairSkinDents:BadEditMode', ...
                'editMode must be auto, always, or never.');
    end
end

function mode = normalizeDentMetric(mode)
    mode = lower(strtrim(char(mode)));
    mode = regexprep(mode, '[\s_\-]+', '');
    switch mode
        case {'local', 'laplacian', 'locallaplacian', 'localdefect'}
            mode = 'localLaplacian';
        case {'radial', 'radialenvelope', 'envelope', 'legacy'}
            mode = 'radialEnvelope';
        case {'hybrid', 'combined', 'both'}
            mode = 'hybrid';
        otherwise
            error('acsInteractivelyRepairSkinDents:BadDentMetric', ...
                ['dentMetric must be ''localLaplacian'', ', ...
                 '''radialEnvelope'', or ''hybrid''.']);
    end
end

function source = readSkinSource(value, opts)
    source = struct();
    source.file = '';
    source.loadedVariables = struct();
    source.variable = '';
    source.meshStage = opts.meshStage;
    if isa(value, 'triangulation')
        source.TR = value;
        source.variable = 'TRskin';
        source.meshStage = 'triangulation';
        return;
    end
    if isstruct(value)
        [source.TR, source.variable] = selectMeshFromStruct(value, opts.meshStage);
        source.loadedVariables = value;
        source.meshStage = variableNameToStage(source.variable);
        return;
    end
    fileName = expandUserPath(char(value));
    if exist(fileName, 'file') ~= 2
        error('acsInteractivelyRepairSkinDents:MissingFile', ...
            'Skin cache not found: %s', fileName);
    end
    S = load(fileName);
    [source.TR, source.variable] = selectMeshFromStruct(S, opts.meshStage);
    source.file = fileName;
    source.loadedVariables = S;
    source.meshStage = variableNameToStage(source.variable);
end

function [TR, variableName] = selectMeshFromStruct(S, stage)
    switch stage
        case 'stableHead'
            candidates = {'TRstableHead', 'TRskin'};
        case 'fiducialHead'
            candidates = {'TRfiducialHead', 'TRstableHead', 'TRskin'};
        case 'skin'
            candidates = {'TRskin'};
        otherwise
            candidates = {'TRstableHead', 'TRfiducialHead', 'TRskin'};
    end
    for i = 1:numel(candidates)
        name = candidates{i};
        if isfield(S, name) && ~isempty(S.(name))
            TR = ensureTriangulation(S.(name));
            variableName = name;
            return;
        end
    end
    error('acsInteractivelyRepairSkinDents:NoSkinMesh', ...
        'Input did not contain TRstableHead, TRfiducialHead, or TRskin.');
end

function stage = variableNameToStage(name)
    switch char(name)
        case 'TRstableHead'
            stage = 'stableHead';
        case 'TRfiducialHead'
            stage = 'fiducialHead';
        otherwise
            stage = 'skin';
    end
end

function TR = ensureTriangulation(value)
    if isa(value, 'triangulation')
        TR = value;
    elseif isstruct(value) && isfield(value, 'Points') && ...
            isfield(value, 'ConnectivityList')
        TR = triangulation(double(value.ConnectivityList), double(value.Points));
    elseif isstruct(value) && isfield(value, 'vertices') && ...
            isfield(value, 'faces')
        TR = triangulation(double(value.faces), double(value.vertices));
    else
        error('acsInteractivelyRepairSkinDents:BadMesh', ...
            'Skin mesh must be a triangulation or struct with Points/ConnectivityList.');
    end
end

function opts = resolveOutputFile(source, opts)
    if ~isempty(opts.outputFile)
        return;
    end
    if isempty(source.file)
        error('acsInteractivelyRepairSkinDents:MissingOutputFile', ...
            'outputFile is required when the input is not a MAT cache file.');
    end
    [folder, stem] = fileparts(source.file);
    opts.outputFile = fullfile(folder, sprintf('%s_%s.mat', ...
        stem, opts.outputTag));
end

function tf = shouldOpenGui(outputFile, opts, existingIsStale)
    if strcmpi(opts.editMode, 'never') || ~opts.showFigures
        tf = false;
        return;
    end
    if strcmpi(opts.editMode, 'always') || opts.force || existingIsStale
        tf = true;
        return;
    end
    tf = exist(outputFile, 'file') ~= 2;
end

function out = loadExistingRepair(fileName)
    S = load(fileName);
    if isfield(S, 'manualDentRepair') && isstruct(S.manualDentRepair)
        out = S.manualDentRepair;
    elseif isfield(S, 'outForSave') && isstruct(S.outForSave)
        out = S.outForSave;
    else
        out = struct();
    end
    if isempty(fieldnames(out))
        out = struct('createdOn', char(datetime('now')), ...
            'type', 'manualSkinDentRepair', ...
            'outputFile', fileName, ...
            'accepted', true, ...
            'didWrite', true, ...
            'reused', true);
    end
    out.outputFile = fileName;
end

function out = fillRepairOutputDefaults(out, inputSource, repairedSource, opts)
    if ~isfield(out, 'inputFile')
        out.inputFile = inputSource.file;
    end
    if ~isfield(out, 'outputFile') || isempty(out.outputFile)
        out.outputFile = opts.outputFile;
    end
    if ~isfield(out, 'meshStage') || isempty(out.meshStage)
        out.meshStage = repairedSource.meshStage;
    end
    if ~isfield(out, 'meshVariable') || isempty(out.meshVariable)
        out.meshVariable = repairedSource.variable;
    end
    if ~isfield(out, 'accepted')
        out.accepted = true;
    end
    if ~isfield(out, 'didWrite')
        out.didWrite = true;
    end
    if ~isfield(out, 'nMovedVertices')
        out.nMovedVertices = NaN;
    end
    if ~isfield(out, 'medianMoveMm')
        out.medianMoveMm = NaN;
    end
    if ~isfield(out, 'maxMoveMm')
        out.maxMoveMm = NaN;
    end
    if ~isfield(out, 'nRepairActions')
        out.nRepairActions = NaN;
    end
    if ~isfield(out, 'finalDentFlags')
        out.finalDentFlags = NaN;
    end
    if ~isfield(out, 'finalDentP95Mm')
        out.finalDentP95Mm = NaN;
    end
    if ~isfield(out, 'finalDentMaxMm')
        out.finalDentMaxMm = NaN;
    end
end

function tf = existingRepairIsStale(existing, TRinput)
    tf = false;
    if isempty(fieldnames(existing)) || ~isfield(existing, 'inputMeshFingerprint')
        return;
    end
    current = meshFingerprint(TRinput);
    previous = existing.inputMeshFingerprint;
    tf = ~meshFingerprintsMatch(previous, current);
end

function tf = meshFingerprintsMatch(a, b)
    tf = false;
    required = {'nPoints', 'nFaces', 'boundsMin', 'boundsMax', ...
        'pointSum', 'pointSquaredSum', 'faceSum', 'faceSquaredSum'};
    for i = 1:numel(required)
        if ~isfield(a, required{i}) || ~isfield(b, required{i})
            return;
        end
    end
    if a.nPoints ~= b.nPoints || a.nFaces ~= b.nFaces
        return;
    end
    tol = 1e-5;
    tf = max(abs(double(a.boundsMin(:)) - double(b.boundsMin(:)))) <= tol && ...
        max(abs(double(a.boundsMax(:)) - double(b.boundsMax(:)))) <= tol && ...
        max(abs(double(a.pointSum(:)) - double(b.pointSum(:)))) <= tol && ...
        max(abs(double(a.pointSquaredSum(:)) - ...
        double(b.pointSquaredSum(:)))) <= 1e-3 && ...
        max(abs(double(a.faceSum(:)) - double(b.faceSum(:)))) <= 0 && ...
        max(abs(double(a.faceSquaredSum(:)) - ...
        double(b.faceSquaredSum(:)))) <= 0;
end

function state = initializeRepairState(TR, existing, opts)
    state = struct();
    state.TR = TR;
    state.originalTR = TR;
    state.selected = false(size(TR.Points, 1), 1);
    state.brushRadiusMm = opts.brushRadiusMm;
    V = double(TR.Points);
    state.brushCenterMm = median(V(all(isfinite(V), 2), :), 1);
    if isempty(state.brushCenterMm)
        state.brushCenterMm = [0 0 0];
    end
    if isstruct(existing) && isfield(existing, 'brushCenterMm') && ...
            numel(existing.brushCenterMm) == 3
        state.brushCenterMm = double(existing.brushCenterMm(:)');
    end
    if isstruct(existing) && isfield(existing, 'brushRadiusMm') && ...
            isscalar(existing.brushRadiusMm) && isfinite(existing.brushRadiusMm)
        state.brushRadiusMm = double(existing.brushRadiusMm);
    end
    state.history = {};
    state.repairHistory = struct([]);
    state.diagnostics = computeDentDiagnostics( ...
        double(TR.ConnectivityList), double(TR.Points), opts);
    state.initialDiagnostics = state.diagnostics;
    state.cameraState = struct();
    state.brushDepthMm = NaN;
    state.brushRayOriginMm = [NaN NaN NaN];
    state.brushRayDirection = [NaN NaN NaN];
end

function [state, accepted] = repairGui(TRin, state, opts)
    V0 = double(TRin.Points);
    F = double(TRin.ConnectivityList);
    Fdisp = displayFaces(F, opts.displayMaxFaces);
    accepted = false;
    finalState = state;
    paint = struct('active', false, 'mode', 'add');

    fig = figure('Name', 'Manual skin dent repair', ...
        'NumberTitle', 'off', 'Color', 'w', 'Units', 'normalized', ...
        'Position', [0.06 0.07 0.86 0.84], ...
        'CloseRequestFcn', @onCancel);
    ax = axes('Parent', fig, 'Units', 'normalized', ...
        'Position', [0.04 0.08 0.72 0.86]);
    hold(ax, 'on');
    hMesh = patch(ax, 'Faces', Fdisp, 'Vertices', V0, ...
        'FaceVertexCData', state.diagnostics.dentDepthMm, ...
        'FaceColor', 'interp', 'FaceAlpha', opts.meshAlpha, ...
        'EdgeColor', [0.20 0.20 0.20], 'EdgeAlpha', 0.07, ...
        'FaceLighting', 'flat', 'AmbientStrength', 0.62, ...
        'SpecularStrength', 0.04, 'HitTest', 'off');
    colormap(ax, parula(256));
    cb = colorbar(ax);
    ylabel(cb, sprintf('%s dent depth (mm)', opts.dentMetric), ...
        'Interpreter', 'none');
    updateColorLimits(ax, state.diagnostics, opts);

    hAuto = scatter3(ax, NaN, NaN, NaN, 26, [1.00 0.00 0.75], ...
        'filled', 'MarkerEdgeColor', [0.20 0.00 0.16], ...
        'LineWidth', 0.6, 'HitTest', 'off');
    hSelected = scatter3(ax, NaN, NaN, NaN, 42, [1.00 0.85 0.05], ...
        'filled', 'MarkerEdgeColor', [0.15 0.10 0.00], ...
        'LineWidth', 0.9, 'HitTest', 'off');
    hBrush = scatter3(ax, NaN, NaN, NaN, 14, [1.00 0.85 0.05], ...
        'filled', 'MarkerEdgeColor', 'none', 'HitTest', 'off');
    hCenter = scatter3(ax, state.brushCenterMm(1), state.brushCenterMm(2), ...
        state.brushCenterMm(3), 70, [1.00 0.85 0.05], 'filled', ...
        'MarkerEdgeColor', [0.10 0.10 0.10], 'HitTest', 'off');
    hSphere = makeBrushSphere(ax, state.brushCenterMm, state.brushRadiusMm);

    title(ax, 'Manual skin dent repair', 'Interpreter', 'none');
    axis(ax, 'equal');
    axis(ax, 'vis3d');
    axis(ax, 'off');
    view(ax, 3);
    camlight(ax, 'headlight');
    lighting(ax, 'flat');
    rotate3d(fig, 'off');

    status = uicontrol(fig, 'Style', 'text', 'Units', 'normalized', ...
        'Position', [0.79 0.77 0.19 0.18], 'BackgroundColor', 'w', ...
        'HorizontalAlignment', 'left', 'FontSize', 10);
    uicontrol(fig, 'Style', 'text', 'Units', 'normalized', ...
        'Position', [0.79 0.72 0.05 0.03], 'String', 'alpha', ...
        'BackgroundColor', 'w', 'HorizontalAlignment', 'left');
    uicontrol(fig, 'Style', 'slider', 'Units', 'normalized', ...
        'Position', [0.84 0.72 0.13 0.035], 'Min', 0.05, 'Max', 1, ...
        'Value', opts.meshAlpha, ...
        'Callback', @(src, ~) set(hMesh, 'FaceAlpha', get(src, 'Value')));
    uicontrol(fig, 'Style', 'pushbutton', 'Units', 'normalized', ...
        'Position', [0.79 0.64 0.18 0.05], 'String', 'Repair selected', ...
        'Callback', @onRepairSelected);
    uicontrol(fig, 'Style', 'pushbutton', 'Units', 'normalized', ...
        'Position', [0.79 0.58 0.18 0.05], 'String', 'Add brush', ...
        'Callback', @onAddBrush);
    uicontrol(fig, 'Style', 'pushbutton', 'Units', 'normalized', ...
        'Position', [0.79 0.52 0.18 0.05], 'String', 'Undo repair', ...
        'Callback', @onUndo);
    uicontrol(fig, 'Style', 'pushbutton', 'Units', 'normalized', ...
        'Position', [0.79 0.46 0.18 0.05], 'String', 'Clear selection', ...
        'Callback', @onClear);
    uicontrol(fig, 'Style', 'pushbutton', 'Units', 'normalized', ...
        'Position', [0.79 0.36 0.18 0.06], 'String', 'Save and done', ...
        'Callback', @onDone);
    uicontrol(fig, 'Style', 'pushbutton', 'Units', 'normalized', ...
        'Position', [0.79 0.28 0.18 0.06], 'String', 'Cancel', ...
        'Callback', @onCancel);
    helpText = sprintf(['Shift-drag: select vertices\n', ...
        'Ctrl/Alt+Shift-drag: erase vertices\n', ...
        'Brush selects visible magenta flags only\n', ...
        'a/x: add/remove current brush\n', ...
        'i/o: radius in/out\n', ...
        'u: undo | c: clear\n', ...
        'd/Enter: save | Esc: cancel\n', ...
        '1-6: canonical views\n', ...
        'Toolbar rotate/zoom/pan works when not shift-painting']);
    uicontrol(fig, 'Style', 'text', 'Units', 'normalized', ...
        'Position', [0.79 0.05 0.20 0.19], 'BackgroundColor', 'w', ...
        'HorizontalAlignment', 'left', 'FontSize', 9, 'String', helpText);

    set(fig, 'WindowButtonDownFcn', @onMouseDown);
    set(fig, 'WindowButtonMotionFcn', @onMouseMove);
    set(fig, 'WindowButtonUpFcn', @onMouseUp);
    set(fig, 'WindowKeyPressFcn', @onKeyPress);

    refresh();
    uiwait(fig);
    state = finalState;

    function refresh()
        V = double(state.TR.Points);
        set(hMesh, 'Vertices', V, ...
            'FaceVertexCData', state.diagnostics.dentDepthMm);
        updateColorLimits(ax, state.diagnostics, opts);

        autoRows = displayAutoRows(state.diagnostics, opts.autoFlagDisplayMax);
        if isempty(autoRows)
            set(hAuto, 'XData', NaN, 'YData', NaN, 'ZData', NaN);
        else
            set(hAuto, 'XData', V(autoRows, 1), ...
                'YData', V(autoRows, 2), 'ZData', V(autoRows, 3));
        end
        selectedRows = find(state.selected);
        if isempty(selectedRows)
            set(hSelected, 'XData', NaN, 'YData', NaN, 'ZData', NaN);
        else
            set(hSelected, 'XData', V(selectedRows, 1), ...
                'YData', V(selectedRows, 2), ...
                'ZData', V(selectedRows, 3));
        end
        brushRows = currentBrushRows();
        if isempty(brushRows)
            set(hBrush, 'XData', NaN, 'YData', NaN, 'ZData', NaN);
        else
            set(hBrush, 'XData', V(brushRows, 1), ...
                'YData', V(brushRows, 2), 'ZData', V(brushRows, 3));
        end
        set(hCenter, 'XData', state.brushCenterMm(1), ...
            'YData', state.brushCenterMm(2), ...
            'ZData', state.brushCenterMm(3));
        updateBrushSphere(hSphere, state.brushCenterMm, state.brushRadiusMm);
        set(status, 'String', statusText(state));
        drawnow limitrate;
    end

    function onMouseDown(~, event)
        if ~hasModifier(event, 'shift', fig)
            return;
        end
        disableToolbarModes(fig);
        paint.active = true;
        if hasModifier(event, 'control', fig) || hasModifier(event, 'alt', fig)
            paint.mode = 'remove';
        else
            paint.mode = 'add';
        end
        paintAtCursor();
    end

    function onMouseMove(~, ~)
        if paint.active
            paintAtCursor();
        end
    end

    function onMouseUp(~, ~)
        paint.active = false;
    end

    function paintAtCursor()
        V = double(state.TR.Points);
        [origin, direction] = clickRay(ax);
        eligible = true(size(V, 1), 1);
        if opts.selectOnlyDentFlags
            eligible = state.diagnostics.dentMask(:);
        end
        [~, idx, depthMm] = closestVertexToRay(V, origin, direction, eligible);
        if isempty(idx) || ~isfinite(idx)
            return;
        end
        state.brushCenterMm = V(idx, :);
        state.brushDepthMm = depthMm;
        state.brushRayOriginMm = origin;
        state.brushRayDirection = direction;
        if strcmpi(paint.mode, 'remove')
            removeBrush();
        else
            addBrush();
        end
        refresh();
    end

    function onKeyPress(~, event)
        key = lower(char(event.Key));
        switch key
            case 'a'
                addBrush();
            case {'x', 'backspace', 'delete'}
                removeBrush();
            case 'c'
                state.selected(:) = false;
            case 'i'
                state.brushRadiusMm = max(0.5, state.brushRadiusMm / 1.25);
            case 'o'
                state.brushRadiusMm = state.brushRadiusMm * 1.25;
            case 'u'
                undoRepair();
            case {'d', 'return', 'enter'}
                onDone();
                return;
            case 'escape'
                onCancel();
                return;
            case {'1', '2', '3', '4', '5', '6'}
                setCanonicalView(ax, double(state.TR.Points), str2double(key));
        end
        refresh();
    end

    function onRepairSelected(varargin) %#ok<INUSD>
        rows = find(state.selected);
        if isempty(rows)
            return;
        end
        state.history{end + 1} = state.TR; %#ok<AGROW>
        [state.TR, repairInfo] = repairSelectedVertices(state.TR, rows, opts);
        state.diagnostics = computeDentDiagnostics( ...
            double(state.TR.ConnectivityList), double(state.TR.Points), opts);
        state.repairHistory = appendRepairHistory(state.repairHistory, repairInfo);
        state.selected(:) = false;
        refresh();
    end

    function onAddBrush(varargin) %#ok<INUSD>
        addBrush();
        refresh();
    end

    function onUndo(varargin) %#ok<INUSD>
        undoRepair();
        refresh();
    end

    function undoRepair()
        if isempty(state.history)
            return;
        end
        state.TR = state.history{end};
        state.history(end) = [];
        if ~isempty(state.repairHistory)
            state.repairHistory(end) = [];
        end
        state.diagnostics = computeDentDiagnostics( ...
            double(state.TR.ConnectivityList), double(state.TR.Points), opts);
    end

    function onClear(varargin) %#ok<INUSD>
        state.selected(:) = false;
        refresh();
    end

    function onDone(varargin) %#ok<INUSD>
        accepted = true;
        state.cameraState = captureCameraState(ax);
        finalState = state;
        if isgraphics(fig)
            uiresume(fig);
            delete(fig);
        end
    end

    function onCancel(varargin) %#ok<INUSD>
        accepted = false;
        finalState = state;
        if isgraphics(fig)
            uiresume(fig);
            delete(fig);
        end
    end

    function addBrush()
        state.selected(currentBrushRows()) = true;
    end

    function removeBrush()
        state.selected(currentBrushRows()) = false;
    end

    function rows = currentBrushRows()
        V = double(state.TR.Points);
        d2 = sum(bsxfun(@minus, V, state.brushCenterMm) .^ 2, 2);
        rows = find(d2 <= state.brushRadiusMm .^ 2);
        if opts.selectOnlyDentFlags
            rows = rows(state.diagnostics.dentMask(rows));
        end
        if isfinite(state.brushDepthMm) && opts.selectionDepthMm > 0 && ...
                all(isfinite(state.brushRayOriginMm)) && ...
                all(isfinite(state.brushRayDirection))
            depthMm = rayDepthMm(V, state.brushRayOriginMm, ...
                state.brushRayDirection);
            rows = rows(abs(depthMm(rows) - state.brushDepthMm) <= ...
                opts.selectionDepthMm);
        end
    end
end

function rows = displayAutoRows(diagnostics, maxRows)
    rows = find(diagnostics.dentMask(:));
    if isempty(rows)
        return;
    end
    if numel(rows) > maxRows
        [~, order] = sort(diagnostics.dentDepthMm(rows), 'descend');
        rows = rows(order(1:maxRows));
    end
end

function updateColorLimits(ax, diagnostics, opts)
    hi = percentileFinite(diagnostics.dentDepthMm, 99);
    hi = max([opts.dentMinDepthMm, hi, 1]);
    caxis(ax, [0 hi]);
end

function textOut = statusText(state)
    D = state.diagnostics;
    textOut = sprintf(['Selected vertices: %d\n', ...
        'Auto dent flags: %d\n', ...
        'Dent p95/max: %.2f / %.2f mm\n', ...
        'Brush center: [%.1f %.1f %.1f]\n', ...
        'Brush radius: %.1f mm\n', ...
        'Repairs: %d'], ...
        nnz(state.selected), nnz(D.dentMask), ...
        percentileFinite(D.dentDepthMm, 95), maxFinite(D.dentDepthMm), ...
        state.brushCenterMm(1), state.brushCenterMm(2), ...
        state.brushCenterMm(3), state.brushRadiusMm, ...
        numel(state.repairHistory));
end

function h = makeBrushSphere(ax, center, radius)
    [X, Y, Z] = sphere(18);
    h = surf(ax, center(1) + radius * X, ...
        center(2) + radius * Y, center(3) + radius * Z, ...
        'FaceColor', [1.00 0.85 0.05], ...
        'FaceAlpha', 0.08, ...
        'EdgeColor', [1.00 0.85 0.05], ...
        'EdgeAlpha', 0.40, ...
        'HitTest', 'off');
end

function updateBrushSphere(h, center, radius)
    [X, Y, Z] = sphere(18);
    set(h, 'XData', center(1) + radius * X, ...
        'YData', center(2) + radius * Y, ...
        'ZData', center(3) + radius * Z);
end

function [TRout, info] = repairSelectedVertices(TRin, rows, opts)
    F = double(TRin.ConnectivityList);
    V = double(TRin.Points);
    rows = unique(rows(:));
    rows = rows(rows >= 1 & rows <= size(V, 1));
    diagBefore = computeDentDiagnostics(F, V, opts);
    oldV = V(rows, :);
    move = opts.repairBlend .* diagBefore.dentDepthMm(rows);
    if opts.repairMinMoveMm > 0
        move = max(move, opts.repairMinMoveMm);
    end
    move(~isfinite(move)) = 0;
    move = min(move, opts.repairMaxMoveMm);
    direction = diagBefore.repairDirection(rows, :);
    bad = ~all(isfinite(direction), 2) | sqrt(sum(direction .^ 2, 2)) <= eps;
    if any(bad)
        radialAll = radialDirections(V);
        direction(bad, :) = radialAll(rows(bad), :);
    end
    V(rows, :) = V(rows, :) + bsxfun(@times, direction, move);
    [V, fairingRows] = fairSelectedRegion(F, V, rows, opts);
    diagAfter = computeDentDiagnostics(F, V, opts);
    TRout = triangulation(F, V);

    delta = sqrt(sum((V(rows, :) - oldV) .^ 2, 2));
    info = struct();
    info.createdOn = char(datetime('now'));
    info.nSelected = numel(rows);
    info.selectedRows = rows(:);
    info.nFairingRows = numel(fairingRows);
    info.fairingRows = fairingRows(:);
    info.medianMoveMm = medianFinite(delta);
    info.maxMoveMm = maxFinite(delta);
    info.nFlagsBefore = nnz(diagBefore.dentMask);
    info.nFlagsAfter = nnz(diagAfter.dentMask);
    info.maxDentBeforeMm = maxFinite(diagBefore.dentDepthMm);
    info.maxDentAfterMm = maxFinite(diagAfter.dentDepthMm);
end

function [Vout, targetRows] = fairSelectedRegion(F, V, selectedRows, opts)
    Vout = V;
    targetRows = unique(selectedRows(:));
    if opts.repairFairingIterations <= 0 || opts.repairFairingBlend <= 0
        return;
    end
    [A, deg, boundary] = meshAdjacency(F, size(V, 1));
    neighbors = adjacencyListFromSparse(A, size(V, 1));
    if opts.repairFairingRings > 0
        targetRows = expandRowsByRings(neighbors, targetRows, ...
            opts.repairFairingRings);
    end
    targetRows = setdiff(targetRows(:), boundary(:));
    if isempty(targetRows)
        return;
    end
    blend = opts.repairFairingBlend;
    for it = 1:opts.repairFairingIterations
        neighborMean = bsxfun(@rdivide, full(A * Vout), deg);
        Vout(targetRows, :) = (1 - blend) .* Vout(targetRows, :) + ...
            blend .* neighborMean(targetRows, :);
    end
end

function history = appendRepairHistory(history, info)
    if isempty(history)
        history = info;
    else
        history(end + 1, 1) = info;
    end
end

function diagnostics = computeDentDiagnostics(F, V, opts)
    n = size(V, 1);
    [A, deg, boundary] = meshAdjacency(F, n);
    neighbors = adjacencyListFromSparse(A, n);
    medEdge = medianEdgeLengthMm(F, V);
    if ~isfinite(medEdge) || medEdge <= 0
        medEdge = max(1, opts.dentRadiusMm);
    end
    nRings = max(1, ceil(opts.dentRadiusMm / medEdge));
    nRings = min(opts.dentMaxRings, nRings);
    TR = triangulation(F, V);
    Nv = normalizeRows(vertexNormalSafe(TR));
    Nv = orientNormalsRadially(V, Nv);
    Ns = smoothNormalsByAdjacencySparse(Nv, A, deg, ...
        max(1, min(8, nRings)));
    normalRoughnessDeg = vectorAnglesDeg(Nv, Ns);
    [radialUnit, center] = radialDirections(V);
    radialWeight = opts.dentDirectionRadialWeight;
    repairDirection = normalizeRows((1 - radialWeight) .* Ns + ...
        radialWeight .* radialUnit);
    badDir = sqrt(sum(repairDirection .^ 2, 2)) <= eps | ...
        ~all(isfinite(repairDirection), 2);
    repairDirection(badDir, :) = radialUnit(badDir, :);
    Vlocal = smoothPositionsByAdjacencySparse(V, A, deg, ...
        opts.dentLocalSmoothingIterations, 0.65);
    localDelta = Vlocal - V;
    localDentDepth = sum(localDelta .* repairDirection, 2);
    localDentDepth(~isfinite(localDentDepth)) = 0;
    localDentDepth = max(0, localDentDepth);
    radial = bsxfun(@minus, V, center);
    radialDistance = sqrt(sum(radial .^ 2, 2));
    if usesRadialEnvelopeDentMetric(opts.dentMetric)
        localEnvelope = localPercentileByRings(neighbors, radialDistance, ...
            nRings, opts.dentEnvelopePercentile);
        radialDentDepth = localEnvelope - radialDistance;
        radialDentDepth(~isfinite(radialDentDepth)) = 0;
        radialDentDepth = max(0, radialDentDepth);
    else
        localEnvelope = radialDistance;
        radialDentDepth = zeros(size(radialDistance));
    end
    switch opts.dentMetric
        case 'radialEnvelope'
            dentDepth = radialDentDepth;
        case 'hybrid'
            dentDepth = max(localDentDepth, min(radialDentDepth, ...
                localDentDepth + opts.dentMinDepthMm));
        otherwise
            dentDepth = localDentDepth;
    end
    strongDent = dentDepth >= opts.dentMinDepthMm;
    creaseDent = dentDepth >= 0.5 * opts.dentMinDepthMm & ...
        normalRoughnessDeg >= opts.dentNormalAngleDeg;
    dentMask = (strongDent | creaseDent) & all(isfinite(V), 2);
    diagnostics = struct();
    diagnostics.centerMm = center;
    diagnostics.metric = opts.dentMetric;
    diagnostics.radiusMm = opts.dentRadiusMm;
    diagnostics.neighborhoodRings = nRings;
    diagnostics.medianEdgeLengthMm = medEdge;
    diagnostics.envelopePercentile = opts.dentEnvelopePercentile;
    diagnostics.minDentMm = opts.dentMinDepthMm;
    diagnostics.normalAngleDeg = opts.dentNormalAngleDeg;
    diagnostics.boundaryVertices = boundary;
    diagnostics.normalRoughnessDeg = normalRoughnessDeg;
    diagnostics.localSmoothedPointsMm = Vlocal;
    diagnostics.repairDirection = repairDirection;
    diagnostics.radialDistanceMm = radialDistance;
    diagnostics.localEnvelopeRadiusMm = localEnvelope;
    diagnostics.radialEnvelopeDentDepthMm = radialDentDepth;
    diagnostics.localLaplacianDentDepthMm = localDentDepth;
    diagnostics.dentDepthMm = dentDepth;
    diagnostics.dentMask = dentMask;
    diagnostics.nDentVertices = nnz(dentMask);
    diagnostics.p95DentDepthMm = percentileFinite(dentDepth, 95);
    diagnostics.maxDentDepthMm = maxFinite(dentDepth);
end

function tf = usesRadialEnvelopeDentMetric(metric)
    tf = any(strcmpi(metric, {'radialEnvelope', 'hybrid'}));
end

function [A, deg, boundaryVertices] = meshAdjacency(F, n)
    Eall = sort([F(:, [1 2]); F(:, [2 3]); F(:, [1 3])], 2);
    [E, ~, ic] = unique(Eall, 'rows');
    counts = accumarray(ic, 1);
    boundaryEdges = E(counts == 1, :);
    boundaryVertices = unique(boundaryEdges(:));
    A = sparse([E(:, 1); E(:, 2)], [E(:, 2); E(:, 1)], ...
        ones(2 * size(E, 1), 1), n, n);
    A = spones(A);
    deg = full(sum(A, 2));
    deg(deg == 0) = 1;
end

function neighbors = adjacencyListFromSparse(A, n)
    neighbors = cell(n, 1);
    [ii, jj] = find(A);
    for k = 1:numel(ii)
        neighbors{ii(k)}(end + 1, 1) = jj(k); %#ok<AGROW>
    end
end

function medEdge = medianEdgeLengthMm(F, V)
    E = unique(sort([F(:, [1 2]); F(:, [2 3]); F(:, [1 3])], 2), 'rows');
    if isempty(E)
        medEdge = NaN;
        return;
    end
    edgeLen = sqrt(sum((V(E(:, 1), :) - V(E(:, 2), :)) .^ 2, 2));
    medEdge = medianFinite(edgeLen);
end

function values = localPercentileByRings(neighbors, vertexValue, nRings, pct)
    n = numel(vertexValue);
    values = nan(n, 1);
    for i = 1:n
        rows = neighborRowsWithinRings(neighbors, i, nRings);
        x = vertexValue(rows);
        x = x(isfinite(x));
        if isempty(x)
            values(i) = vertexValue(i);
        else
            values(i) = percentileFinite(x, pct);
        end
    end
end

function rows = neighborRowsWithinRings(neighbors, startRow, nRings)
    rows = startRow(:);
    frontier = rows;
    for r = 1:nRings
        newRows = gatherNeighborRows(neighbors, frontier);
        if isempty(newRows)
            break;
        end
        newRows = newRows(~ismember(newRows, rows));
        if isempty(newRows)
            break;
        end
        rows = unique([rows; newRows]); %#ok<AGROW>
        frontier = newRows;
    end
end

function rows = expandRowsByRings(neighbors, rows, nRings)
    rows = unique(rows(:));
    frontier = rows;
    for r = 1:nRings
        newRows = gatherNeighborRows(neighbors, frontier);
        if isempty(newRows)
            break;
        end
        newRows = newRows(~ismember(newRows, rows));
        if isempty(newRows)
            break;
        end
        rows = unique([rows; newRows]); %#ok<AGROW>
        frontier = newRows;
    end
end

function rows = gatherNeighborRows(neighbors, sourceRows)
    buckets = cell(numel(sourceRows), 1);
    for i = 1:numel(sourceRows)
        buckets{i} = neighbors{sourceRows(i)};
    end
    if isempty(buckets)
        rows = [];
    else
        rows = unique(vertcat(buckets{:}));
    end
end

function N = vertexNormalSafe(TR)
    try
        N = vertexNormal(TR);
    catch
        V = double(TR.Points);
        F = double(TR.ConnectivityList);
        Fn = cross(V(F(:, 2), :) - V(F(:, 1), :), ...
            V(F(:, 3), :) - V(F(:, 1), :), 2);
        N = zeros(size(V));
        for f = 1:size(F, 1)
            N(F(f, :), :) = N(F(f, :), :) + Fn(f, :);
        end
    end
end

function N = orientNormalsRadially(V, N)
    [R, ~] = radialDirections(V);
    flip = all(isfinite(R), 2) & all(isfinite(N), 2) & ...
        sum(N .* R, 2) < 0;
    N(flip, :) = -N(flip, :);
end

function [R, center] = radialDirections(V)
    center = median(V, 1);
    radial = bsxfun(@minus, V, center);
    len = sqrt(sum(radial .^ 2, 2));
    R = zeros(size(radial));
    good = isfinite(len) & len > eps;
    R(good, :) = bsxfun(@rdivide, radial(good, :), len(good));
end

function N = smoothNormalsByAdjacencySparse(N, A, deg, nIter)
    N = normalizeRows(N);
    for it = 1:nIter
        neighbor = bsxfun(@rdivide, full(A * N), deg);
        flip = sum(neighbor .* N, 2) < 0;
        neighbor(flip, :) = -neighbor(flip, :);
        N = normalizeRows(0.5 * N + 0.5 * neighbor);
    end
end

function Vout = smoothPositionsByAdjacencySparse(V, A, deg, nIter, blend)
    Vout = double(V);
    if nIter <= 0
        return;
    end
    blend = max(0, min(1, double(blend)));
    for it = 1:nIter
        neighbor = bsxfun(@rdivide, full(A * Vout), deg);
        Vout = (1 - blend) .* Vout + blend .* neighbor;
    end
end

function angleDeg = vectorAnglesDeg(A, B)
    A = normalizeRows(A);
    B = normalizeRows(B);
    c = sum(A .* B, 2);
    c = max(-1, min(1, c));
    angleDeg = acosd(c);
end

function N = normalizeRows(N)
    len = sqrt(sum(N .^ 2, 2));
    len(~isfinite(len) | len <= eps) = 1;
    N = bsxfun(@rdivide, N, len);
end

function [origin, direction] = clickRay(ax)
    cp = get(ax, 'CurrentPoint');
    origin = cp(1, :);
    direction = cp(2, :) - cp(1, :);
    n = norm(direction);
    if n <= eps
        direction = [0 0 1];
    else
        direction = direction ./ n;
    end
end

function [point, idx, depthMm] = closestVertexToRay(V, rayOrigin, rayDirection, eligible)
    if nargin < 4 || isempty(eligible)
        eligible = true(size(V, 1), 1);
    else
        eligible = logical(eligible(:));
        if numel(eligible) ~= size(V, 1)
            eligible = true(size(V, 1), 1);
        end
    end
    d = normalizeRow(rayDirection);
    t = rayDepthMm(V, rayOrigin, d);
    closest = bsxfun(@plus, rayOrigin, t .* d);
    dist2 = sum((V - closest) .^ 2, 2);
    dist2(t < 0 | ~eligible) = inf;
    finiteRows = isfinite(dist2);
    if ~any(finiteRows)
        point = [NaN NaN NaN];
        idx = [];
        depthMm = NaN;
        return;
    end
    minDist = min(dist2);
    candidates = find(dist2 <= minDist + 1.0);
    if isempty(candidates)
        [~, idx] = min(dist2);
    else
        [~, j] = min(t(candidates));
        idx = candidates(j);
    end
    point = V(idx, :);
    depthMm = t(idx);
end

function depthMm = rayDepthMm(V, rayOrigin, rayDirection)
    direction = normalizeRow(rayDirection);
    depthMm = bsxfun(@minus, V, rayOrigin) * direction(:);
end

function setCanonicalView(ax, V, viewNumber)
    good = all(isfinite(V), 2);
    center = mean(V(good, :), 1);
    span = max(max(V(good, :), [], 1) - min(V(good, :), [], 1));
    if ~isfinite(span) || span <= 0
        span = 100;
    end
    directions = [ ...
        1 0 0; ...
       -1 0 0; ...
        0 1 0; ...
        0 -1 0; ...
        0 0 1; ...
        0 0 -1];
    ups = [ ...
        0 0 1; ...
        0 0 1; ...
        0 0 1; ...
        0 0 1; ...
        0 1 0; ...
        0 1 0];
    direction = directions(viewNumber, :);
    camtarget(ax, center);
    campos(ax, center + direction .* (2.2 * span));
    camup(ax, ups(viewNumber, :));
    camproj(ax, 'perspective');
end

function state = captureCameraState(ax)
    state = struct('CameraPosition', get(ax, 'CameraPosition'), ...
        'CameraTarget', get(ax, 'CameraTarget'), ...
        'CameraUpVector', get(ax, 'CameraUpVector'), ...
        'CameraViewAngle', get(ax, 'CameraViewAngle'));
end

function tf = hasModifier(event, name, fig)
    tf = false;
    modifiers = {};
    if isstruct(event) && isfield(event, 'Modifier')
        modifiers = event.Modifier;
    else
        try
            if isprop(event, 'Modifier')
                modifiers = event.Modifier;
            end
        catch
            modifiers = {};
        end
    end
    if isempty(modifiers)
        try
            modifiers = get(fig, 'CurrentModifier');
        catch
            modifiers = {};
        end
    end
    if ischar(modifiers)
        modifiers = {modifiers};
    end
    tf = any(strcmpi(modifiers, name));
end

function disableToolbarModes(fig)
    try
        zoom(fig, 'off');
    catch
    end
    try
        pan(fig, 'off');
    catch
    end
    try
        rotate3d(fig, 'off');
    catch
    end
end

function row = normalizeRow(row)
    row = double(row(:)');
    n = norm(row);
    if n > eps
        row = row ./ n;
    end
end

function out = noOpOutput(source, opts, message)
    out = struct();
    out.createdOn = char(datetime('now'));
    out.type = 'manualSkinDentRepair';
    out.inputFile = source.file;
    out.outputFile = source.file;
    out.requestedOutputFile = opts.outputFile;
    out.meshStage = source.meshStage;
    out.meshVariable = source.variable;
    out.accepted = false;
    out.didWrite = false;
    out.reused = false;
    out.message = message;
end

function out = buildOutput(source, state, opts)
    F = double(state.TR.ConnectivityList);
    V0 = double(state.originalTR.Points);
    V = double(state.TR.Points);
    diag = computeDentDiagnostics(F, V, opts);
    move = sqrt(sum((V - V0) .^ 2, 2));
    out = struct();
    out.createdOn = char(datetime('now'));
    out.type = 'manualSkinDentRepair';
    out.inputFile = source.file;
    out.outputFile = opts.outputFile;
    out.meshStage = source.meshStage;
    out.meshVariable = source.variable;
    out.accepted = true;
    out.didWrite = true;
    out.reused = false;
    out.nVertices = size(V, 1);
    out.nFaces = size(F, 1);
    out.inputMeshFingerprint = meshFingerprint(state.originalTR);
    out.outputMeshFingerprint = meshFingerprint(state.TR);
    out.nMovedVertices = nnz(move > 1e-6);
    out.medianMoveMm = medianFinite(move(move > 1e-6));
    out.maxMoveMm = maxFinite(move);
    out.brushCenterMm = state.brushCenterMm;
    out.brushRadiusMm = state.brushRadiusMm;
    out.repairHistory = state.repairHistory;
    out.nRepairActions = numel(state.repairHistory);
    if isfield(state, 'initialDiagnostics') && ...
            isfield(state.initialDiagnostics, 'dentMask')
        out.initialDentFlags = nnz(state.initialDiagnostics.dentMask);
    else
        out.initialDentFlags = nnz(state.diagnostics.dentMask);
    end
    out.finalDentFlags = nnz(diag.dentMask);
    out.finalDentP95Mm = percentileFinite(diag.dentDepthMm, 95);
    out.finalDentMaxMm = maxFinite(diag.dentDepthMm);
    out.cameraState = state.cameraState;
    out.options = stripRuntimeOptions(opts);
end

function optsOut = stripRuntimeOptions(opts)
    optsOut = opts;
end

function writeRepairedCache(source, TRout, out, opts)
    if isempty(opts.outputFile)
        return;
    end
    ensureDir(fileparts(opts.outputFile));
    S = source.loadedVariables;
    if isempty(fieldnames(S))
        S = struct();
    end
    S.(source.variable) = TRout;
    S.manualDentRepair = rmfieldIfPresent(out, {'figure'});
    if isfield(S, 'cacheInfo') && isstruct(S.cacheInfo)
        S.cacheInfo.manualDentRepair = compactRepairMetadata(out);
    end
    if isfield(S, 'meta') && isstruct(S.meta)
        S.meta.manualDentRepair = compactRepairMetadata(out);
    end
    save(opts.outputFile, '-struct', 'S', '-v7.3');
end

function meta = compactRepairMetadata(out)
    meta = struct();
    meta.createdOn = out.createdOn;
    meta.inputFile = out.inputFile;
    meta.outputFile = out.outputFile;
    meta.meshVariable = out.meshVariable;
    meta.nMovedVertices = out.nMovedVertices;
    meta.maxMoveMm = out.maxMoveMm;
    meta.finalDentFlags = out.finalDentFlags;
end

function saveRepairReport(out, opts)
    if isempty(opts.outputFile)
        return;
    end
    outForSave = rmfieldIfPresent(out, {'figure'}); %#ok<NASGU>
    reportFile = replaceExtension(opts.outputFile, '_report.mat');
    try
        save(reportFile, 'outForSave', '-v7.3');
    catch
    end
end

function fig = makeQcFigure(TR, out, opts, visible)
    V = double(TR.Points);
    F = double(TR.ConnectivityList);
    diagnostics = computeDentDiagnostics(F, V, opts);
    fig = figure('Name', 'Manual skin dent repair QC', ...
        'NumberTitle', 'off', 'Color', 'w', 'Visible', visible, ...
        'Position', [120 90 1050 760]);
    ax = axes('Parent', fig, 'Position', [0.06 0.08 0.78 0.84]);
    hold(ax, 'on');
    patch(ax, 'Faces', displayFaces(F, opts.displayMaxFaces), ...
        'Vertices', V, 'FaceVertexCData', diagnostics.dentDepthMm, ...
        'FaceColor', 'interp', 'FaceAlpha', 0.88, ...
        'EdgeColor', [0.2 0.2 0.2], 'EdgeAlpha', 0.06, ...
        'FaceLighting', 'flat', 'AmbientStrength', 0.62);
    rows = displayAutoRows(diagnostics, opts.autoFlagDisplayMax);
    if ~isempty(rows)
        scatter3(ax, V(rows, 1), V(rows, 2), V(rows, 3), 24, ...
            [1.00 0.00 0.75], 'filled', ...
            'MarkerEdgeColor', [0.20 0.00 0.16], 'LineWidth', 0.6);
    end
    colormap(ax, parula(256));
    colorbar(ax);
    updateColorLimits(ax, diagnostics, opts);
    title(ax, sprintf('Manual repair: %d moved vertices, final flags %d', ...
        getOptionalField(out, 'nMovedVertices', 0), ...
        getOptionalField(out, 'finalDentFlags', nnz(diagnostics.dentMask))), ...
        'Interpreter', 'none');
    axis(ax, 'equal');
    axis(ax, 'vis3d');
    axis(ax, 'off');
    view(ax, 3);
    camlight(ax, 'headlight');
    lighting(ax, 'flat');
    rotate3d(fig, 'on');
end

function Fdisp = displayFaces(F, maxFaces)
    if size(F, 1) <= maxFaces
        Fdisp = F;
        return;
    end
    idx = unique(round(linspace(1, size(F, 1), maxFaces)));
    Fdisp = F(idx(:), :);
end

function printSummary(out)
    fprintf('\nManual skin dent repair\n');
    if ~isempty(out.inputFile)
        fprintf('  input: %s\n', out.inputFile);
    end
    fprintf('  output: %s\n', out.outputFile);
    fprintf('  mesh variable: %s\n', out.meshVariable);
    fprintf('  moved vertices: %d, median/max move %.3g / %.3g mm\n', ...
        out.nMovedVertices, out.medianMoveMm, out.maxMoveMm);
    fprintf('  repair actions: %d\n', out.nRepairActions);
    fprintf('  final dent flags: %d, p95/max %.3g / %.3g mm\n', ...
        out.finalDentFlags, out.finalDentP95Mm, out.finalDentMaxMm);
end

function fp = meshFingerprint(TR)
    V = double(TR.Points);
    F = double(TR.ConnectivityList);
    fp = struct();
    fp.nPoints = size(V, 1);
    fp.nFaces = size(F, 1);
    fp.boundsMin = min(V, [], 1);
    fp.boundsMax = max(V, [], 1);
    fp.centroid = mean(V, 1);
    fp.pointSum = sum(V, 1);
    fp.pointSquaredSum = sum(V .^ 2, 1);
    fp.faceSum = sum(F, 1);
    fp.faceSquaredSum = sum(F .^ 2, 1);
end

function value = getOptionalField(S, fieldName, defaultValue)
    value = defaultValue;
    if isstruct(S) && isfield(S, fieldName) && ~isempty(S.(fieldName))
        value = S.(fieldName);
    end
end

function value = maxFinite(x)
    x = x(isfinite(x));
    if isempty(x)
        value = NaN;
    else
        value = max(x);
    end
end

function value = medianFinite(x)
    x = x(isfinite(x));
    if isempty(x)
        value = NaN;
    else
        value = median(x);
    end
end

function q = percentileFinite(x, p)
    x = x(isfinite(x));
    if isempty(x)
        q = NaN;
        return;
    end
    x = sort(x(:));
    idx = max(1, min(numel(x), round(1 + (p / 100) * (numel(x) - 1))));
    q = x(idx);
end

function out = rmfieldIfPresent(out, fields)
    for i = 1:numel(fields)
        if isfield(out, fields{i})
            out = rmfield(out, fields{i});
        end
    end
end

function saveQcFigure(fig, fileName)
    try
        exportgraphics(fig, fileName, 'Resolution', 200);
    catch
        saveas(fig, fileName);
    end
end

function ensureDir(folder)
    if isempty(folder)
        return;
    end
    if exist(folder, 'dir') ~= 7
        mkdir(folder);
    end
end

function pathOut = expandUserPath(pathOut)
    if isempty(pathOut)
        return;
    end
    if startsWith(pathOut, '~')
        homeDir = getenv('HOME');
        if isempty(homeDir)
            homeDir = char(java.lang.System.getProperty('user.home'));
        end
        if numel(pathOut) == 1
            pathOut = homeDir;
        elseif pathOut(2) == filesep || pathOut(2) == '/'
            pathOut = fullfile(homeDir, pathOut(3:end));
        end
    end
end

function name = getFileName(pathIn)
    [~, name, ext] = fileparts(char(pathIn));
    name = [name ext];
end

function out = stripMatExtension(fileName)
    [~, stem] = fileparts(char(fileName));
    out = stem;
end

function out = replaceExtension(fileName, ext)
    [folder, stem] = fileparts(char(fileName));
    out = fullfile(folder, [stem ext]);
end

function tag = safeTag(tag)
    tag = regexprep(strtrim(tag), '[^\w\-]+', '_');
    if isempty(tag)
        tag = 'manualDentRepair';
    end
end
