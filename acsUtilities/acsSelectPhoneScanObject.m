function out = acsSelectPhoneScanObject(phoneScanIn, varargin)
% ACSSELECTPHONESCANOBJECT Select object vertices on a registered phone scan.
%
% out = acsSelectPhoneScanObject(phoneScanIn) opens a small brush-style GUI
% for marking vertices that belong to a named object, such as the visible
% headpost, in a cropped/registered phone-scan mesh. The saved object can be
% passed to acsWarpScalpSurfaceToPhoneScan so those points do not pull the
% scalp warp upward into non-scalp geometry.
%
% phoneScanIn may be the output struct or MAT file from
% acsRegisterPhoneScanToCapMakerFrame, the output from
% acsCropPhoneScanToHead, a triangulation, or a struct with faces/vertices.
%
% Name-value options:
%   objectName      : object/trace name ['headpost']
%   outputFile      : saved MAT object-selection file ['']
%   outputTag       : output stem suffix ['phoneObject']
%   editMode        : 'auto', 'always', or 'never' ['auto']
%   force           : overwrite existing output [false]
%   brushRadiusMm   : initial spherical brush radius [8]
%   displayMaxFaces : display mesh face cap [60000]
%   meshAlpha       : mesh opacity [1]
%   showFigures     : open GUI / QC figure [true]
%   saveFigures     : save QC PNG [true]
%   verbose         : print summary [true]

    if nargin < 1 || isempty(phoneScanIn)
        error('acsSelectPhoneScanObject:MissingPhoneScan', ...
            'Provide a phone-scan registration/crop product, triangulation, or MAT file.');
    end

    opts = parseInputs(varargin{:});
    addLocalDependencies();

    phone = readPhoneScan(phoneScanIn);
    opts = resolveOutputFile(phone, opts);

    existing = struct();
    if exist(opts.outputFile, 'file') == 2
        existing = loadExistingSelection(opts.outputFile);
    end

    openGui = shouldOpenGui(opts.outputFile, opts);
    if ~openGui
        if isempty(fieldnames(existing))
            error('acsSelectPhoneScanObject:NoExistingSelection', ...
                ['No saved phone object selection exists and editMode/showFigures ', ...
                 'does not permit interactive selection: %s'], opts.outputFile);
        end
        out = existing;
        if opts.showFigures
            out.figure = makeQcFigure(phone.TR, out, opts, 'on');
        end
        if opts.verbose
            fprintf('Phone scan object selection already exists; reusing %s\n', ...
                opts.outputFile);
        end
        return;
    end

    selection = initializeSelection(phone.TR, existing, opts);
    [selection, accepted] = selectObjectGui(phone.TR, selection, opts);
    if ~accepted
        error('acsSelectPhoneScanObject:Canceled', ...
            'Phone scan object selection was canceled.');
    end

    out = buildOutput(phone, selection, opts);
    fig = [];
    qcFile = '';
    if opts.showFigures || opts.saveFigures
        figVisible = 'off';
        if opts.showFigures
            figVisible = 'on';
        end
        fig = makeQcFigure(phone.TR, out, opts, figVisible);
        if opts.saveFigures
            qcFile = fullfile(fileparts(opts.outputFile), 'qc', ...
                [stripMatExtension(getFileName(opts.outputFile)) '_qc.png']);
            ensureDir(fileparts(qcFile));
            saveQcFigure(fig, qcFile);
        end
        if ~opts.showFigures
            close(fig);
            fig = [];
        end
    end
    out.qcFigure = qcFile;
    out.figure = fig;

    outForSave = rmfieldIfPresent(out, {'figure'});
    phoneObject = outForSave; %#ok<NASGU>
    ensureDir(fileparts(opts.outputFile));
    save(opts.outputFile, 'outForSave', 'phoneObject', '-v7.3');
    writeJsonReport(replaceExtension(opts.outputFile, '.json'), outForSave);

    if opts.verbose
        printSummary(out);
    end
end

function opts = parseInputs(varargin)
    p = inputParser;
    p.FunctionName = 'acsSelectPhoneScanObject';
    addParameter(p, 'objectName', 'headpost', @(x) ischar(x) || isstring(x));
    addParameter(p, 'outputFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'outputTag', 'phoneObject', @(x) ischar(x) || isstring(x));
    addParameter(p, 'editMode', 'auto', @(x) ischar(x) || isstring(x));
    addParameter(p, 'force', false, @isBoolLike);
    addParameter(p, 'brushRadiusMm', 8, @isPositiveScalar);
    addParameter(p, 'displayMaxFaces', 60000, @isPositiveScalar);
    addParameter(p, 'meshAlpha', 1, @isUnitScalar);
    addParameter(p, 'showFigures', true, @isBoolLike);
    addParameter(p, 'saveFigures', true, @isBoolLike);
    addParameter(p, 'verbose', true, @isBoolLike);
    parse(p, varargin{:});

    opts = p.Results;
    opts.objectName = safeName(char(opts.objectName));
    opts.outputFile = expandUserPath(char(opts.outputFile));
    opts.outputTag = safeName(char(opts.outputTag));
    opts.editMode = normalizeEditMode(opts.editMode);
    opts.force = logical(opts.force);
    opts.brushRadiusMm = double(opts.brushRadiusMm);
    opts.displayMaxFaces = round(double(opts.displayMaxFaces));
    opts.meshAlpha = double(opts.meshAlpha);
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

function tf = isUnitScalar(x)
    tf = isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0 && x <= 1;
end

function mode = normalizeEditMode(mode)
    mode = lower(strtrim(char(mode)));
    switch mode
        case {'auto', 'always', 'never'}
            return;
        otherwise
            error('acsSelectPhoneScanObject:BadEditMode', ...
                'editMode must be ''auto'', ''always'', or ''never''.');
    end
end

function addLocalDependencies()
    repoRoot = fileparts(fileparts(mfilename('fullpath')));
    addpath(fullfile(repoRoot, 'acsUtilities'));
end

function phone = readPhoneScan(value)
    sourceFile = '';
    if ischar(value) || isstring(value)
        sourceFile = expandUserPath(char(value));
        if exist(sourceFile, 'file') ~= 2
            error('acsSelectPhoneScanObject:PhoneScanNotFound', ...
                'Phone scan file not found: %s', sourceFile);
        end
        raw = load(sourceFile);
        S = firstStruct(raw);
        if isfield(raw, 'TRregisteredPhone') && ~isempty(raw.TRregisteredPhone)
            S.TRregisteredPhone = raw.TRregisteredPhone;
        end
    elseif isstruct(value)
        S = value;
    elseif isa(value, 'triangulation')
        S = struct('TRregisteredPhone', value);
    else
        error('acsSelectPhoneScanObject:BadPhoneScanInput', ...
            'phoneScanIn must be a struct, MAT file, or triangulation.');
    end

    TR = [];
    if isfield(S, 'meshes') && isstruct(S.meshes) && ...
            isfield(S.meshes, 'TRregisteredPhone') && ...
            ~isempty(S.meshes.TRregisteredPhone)
        TR = ensureTriangulation(S.meshes.TRregisteredPhone);
    elseif isfield(S, 'TRregisteredPhone') && ~isempty(S.TRregisteredPhone)
        TR = ensureTriangulation(S.TRregisteredPhone);
    elseif isfield(S, 'TRhead') && ~isempty(S.TRhead)
        TR = ensureTriangulation(S.TRhead);
    elseif isfield(S, 'vertices') && isfield(S, 'faces')
        TR = triangulation(double(S.faces), double(S.vertices));
    elseif isfield(S, 'registeredVertices') && isfield(S, 'faces')
        TR = triangulation(double(S.faces), double(S.registeredVertices));
    end
    if isempty(TR)
        error('acsSelectPhoneScanObject:MissingMesh', ...
            'Could not find a phone-scan mesh in the supplied input.');
    end

    frame = '';
    if isfield(S, 'targetCoordinateFrame') && ~isempty(S.targetCoordinateFrame)
        frame = char(S.targetCoordinateFrame);
    elseif isfield(S, 'coordinateFrame') && ~isempty(S.coordinateFrame)
        frame = char(S.coordinateFrame);
    elseif isfield(S, 'target') && isstruct(S.target) && ...
            isfield(S.target, 'coordinateFrame') && ~isempty(S.target.coordinateFrame)
        frame = char(S.target.coordinateFrame);
    end
    if isempty(frame)
        frame = 'phoneScanRawMm';
    end

    phone = struct();
    phone.TR = TR;
    phone.coordinateFrame = frame;
    phone.source = struct('file', sourceFile, ...
        'label', sourceLabel(sourceFile), ...
        'coordinateFrame', frame, ...
        'nVertices', size(TR.Points, 1), ...
        'nFaces', size(TR.ConnectivityList, 1));
    if isstruct(S) && isfield(S, 'target') && isstruct(S.target)
        phone.source.target = S.target;
    end
    if isstruct(S) && isfield(S, 'outputFile') && ~isempty(S.outputFile)
        phone.source.registrationFile = char(S.outputFile);
    end
end

function opts = resolveOutputFile(phone, opts)
    if ~isempty(opts.outputFile)
        return;
    end
    folder = '';
    stem = '';
    if isfield(phone.source, 'file') && ~isempty(phone.source.file)
        folder = fileparts(phone.source.file);
        stem = stripMatExtension(getFileName(phone.source.file));
    end
    if isempty(folder)
        folder = pwd;
    end
    if isempty(stem)
        stem = 'phoneScan';
    end
    opts.outputFile = fullfile(folder, ...
        sprintf('%s_%s_%s.mat', stem, opts.objectName, opts.outputTag));
end

function tf = shouldOpenGui(outputFile, opts)
    switch opts.editMode
        case 'always'
            tf = true;
        case 'never'
            tf = false;
        otherwise
            tf = opts.showFigures && (opts.force || exist(outputFile, 'file') ~= 2);
    end
end

function selection = initializeSelection(TR, existing, opts)
    n = size(TR.Points, 1);
    selected = false(n, 1);
    if isstruct(existing) && isfield(existing, 'selectedRows') && ...
            ~isempty(existing.selectedRows)
        rows = round(double(existing.selectedRows(:)));
        rows = rows(isfinite(rows) & rows >= 1 & rows <= n);
        selected(rows) = true;
    end
    V = double(TR.Points);
    center = mean(V(all(isfinite(V), 2), :), 1);
    if isstruct(existing) && isfield(existing, 'brushCenterMm') && ...
            numel(existing.brushCenterMm) == 3 && ...
            all(isfinite(existing.brushCenterMm))
        center = double(existing.brushCenterMm(:)');
    elseif any(selected)
        center = mean(V(selected, :), 1);
    end
    selection = struct('selected', selected, ...
        'brushCenterMm', center, ...
        'brushRadiusMm', opts.brushRadiusMm, ...
        'cameraState', struct());
end

function [selection, accepted] = selectObjectGui(TR, selection, opts)
    V = double(TR.Points);
    F = double(TR.ConnectivityList);
    Fdisp = displayFaces(F, opts.displayMaxFaces);

    accepted = false;
    finalSelection = selection;
    paint = struct('active', false, 'mode', 'add');

    fig = figure('Name', sprintf('Select phone scan object: %s', opts.objectName), ...
        'NumberTitle', 'off', 'Color', 'w', ...
        'Position', [90 70 1250 780], ...
        'MenuBar', 'figure', 'ToolBar', 'figure', ...
        'CloseRequestFcn', @onDone);
    ax = axes(fig, 'Units', 'normalized', ...
        'Position', [0.04 0.08 0.70 0.86]); %#ok<LAXES>
    hold(ax, 'on');
    patch(ax, 'Faces', Fdisp, 'Vertices', V, ...
        'FaceColor', [0.72 0.74 0.76], ...
        'FaceAlpha', opts.meshAlpha, ...
        'EdgeColor', 'none', ...
        'HitTest', 'off');
    hBrush = scatter3(ax, NaN, NaN, NaN, 14, [1.00 0.25 0.85], ...
        'filled', 'MarkerEdgeColor', 'none', ...
        'HitTest', 'off');
    hSelected = scatter3(ax, NaN, NaN, NaN, 34, [0.90 0.05 0.05], ...
        'filled', 'MarkerEdgeColor', [0.10 0.10 0.10], ...
        'HitTest', 'off');
    hCenter = scatter3(ax, selection.brushCenterMm(1), ...
        selection.brushCenterMm(2), selection.brushCenterMm(3), ...
        60, [1.00 0.25 0.85], 'filled', ...
        'MarkerEdgeColor', [0.10 0.10 0.10], 'HitTest', 'off');
    hSphere = makeBrushSphere(ax, selection.brushCenterMm, ...
        selection.brushRadiusMm);
    axis(ax, 'equal');
    axis(ax, 'vis3d');
    axis(ax, 'off');
    view(ax, 3);
    camlight(ax, 'headlight');
    lighting(ax, 'flat');
    rotate3d(fig, 'off');

    title(ax, sprintf('Phone scan object: %s', opts.objectName), ...
        'Interpreter', 'none');
    status = uicontrol(fig, 'Style', 'text', 'Units', 'normalized', ...
        'Position', [0.77 0.78 0.20 0.16], 'BackgroundColor', 'w', ...
        'HorizontalAlignment', 'left', 'FontSize', 10);
    uicontrol(fig, 'Style', 'pushbutton', 'Units', 'normalized', ...
        'Position', [0.78 0.70 0.18 0.05], 'String', 'Add brush', ...
        'Callback', @onAdd);
    uicontrol(fig, 'Style', 'pushbutton', 'Units', 'normalized', ...
        'Position', [0.78 0.64 0.18 0.05], 'String', 'Remove brush', ...
        'Callback', @onRemove);
    uicontrol(fig, 'Style', 'pushbutton', 'Units', 'normalized', ...
        'Position', [0.78 0.58 0.18 0.05], 'String', 'Clear selection', ...
        'Callback', @onClear);
    uicontrol(fig, 'Style', 'pushbutton', 'Units', 'normalized', ...
        'Position', [0.78 0.48 0.18 0.06], 'String', 'Done', ...
        'Callback', @onDone);
    uicontrol(fig, 'Style', 'pushbutton', 'Units', 'normalized', ...
        'Position', [0.78 0.40 0.18 0.06], 'String', 'Cancel', ...
        'Callback', @onCancel);
    helpText = sprintf(['Shift-drag: paint object vertices\n', ...
        'Ctrl/Alt+Shift-drag: erase vertices\n', ...
        'a/x: add/remove current brush\n', ...
        'i/o: radius in/out\n', ...
        'c: clear | d: done | Esc: cancel\n', ...
        '1-6: canonical views\n', ...
        'Toolbar rotate/zoom/pan still works when not shift-painting']);
    uicontrol(fig, 'Style', 'text', 'Units', 'normalized', ...
        'Position', [0.77 0.08 0.21 0.24], 'BackgroundColor', 'w', ...
        'HorizontalAlignment', 'left', 'FontSize', 9, 'String', helpText);

    set(fig, 'WindowButtonDownFcn', @onMouseDown);
    set(fig, 'WindowButtonMotionFcn', @onMouseMove);
    set(fig, 'WindowButtonUpFcn', @onMouseUp);
    set(fig, 'WindowKeyPressFcn', @onKeyPress);
    refresh();
    uiwait(fig);

    selection = finalSelection;

    function refresh()
        rows = find(selection.selected);
        if isempty(rows)
            set(hSelected, 'XData', NaN, 'YData', NaN, 'ZData', NaN);
        else
            set(hSelected, 'XData', V(rows, 1), ...
                'YData', V(rows, 2), 'ZData', V(rows, 3));
        end
        set(hCenter, 'XData', selection.brushCenterMm(1), ...
            'YData', selection.brushCenterMm(2), ...
            'ZData', selection.brushCenterMm(3));
        brushRows = currentBrushRows();
        if isempty(brushRows)
            set(hBrush, 'XData', NaN, 'YData', NaN, 'ZData', NaN);
        else
            set(hBrush, 'XData', V(brushRows, 1), ...
                'YData', V(brushRows, 2), ...
                'ZData', V(brushRows, 3));
        end
        updateBrushSphere(hSphere, selection.brushCenterMm, ...
            selection.brushRadiusMm);
        set(status, 'String', statusText(selection));
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
        if ~paint.active
            return;
        end
        paintAtCursor();
    end

    function onMouseUp(~, ~)
        paint.active = false;
    end

    function paintAtCursor()
        [origin, direction] = clickRay(ax);
        [~, idx] = closestVertexToRay(V, origin, direction);
        if isempty(idx) || ~isfinite(idx)
            return;
        end
        selection.brushCenterMm = V(idx, :);
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
                selection.selected(:) = false;
            case 'i'
                selection.brushRadiusMm = max(0.5, ...
                    selection.brushRadiusMm / 1.25);
            case 'o'
                selection.brushRadiusMm = selection.brushRadiusMm * 1.25;
            case {'d', 'return', 'enter'}
                onDone();
                return;
            case 'escape'
                onCancel();
                return;
            case {'1', '2', '3', '4', '5', '6'}
                setCanonicalView(ax, V, str2double(key));
        end
        refresh();
    end

    function onAdd(~, ~)
        addBrush();
        refresh();
    end

    function onRemove(~, ~)
        removeBrush();
        refresh();
    end

    function onClear(~, ~)
        selection.selected(:) = false;
        refresh();
    end

    function onDone(varargin) %#ok<INUSD>
        accepted = true;
        finalSelection = selection;
        finalSelection.cameraState = captureCameraState(ax);
        if isgraphics(fig)
            uiresume(fig);
            delete(fig);
        end
    end

    function onCancel(varargin) %#ok<INUSD>
        accepted = false;
        finalSelection = selection;
        if isgraphics(fig)
            uiresume(fig);
            delete(fig);
        end
    end

    function addBrush()
        selection.selected(currentBrushRows()) = true;
    end

    function removeBrush()
        selection.selected(currentBrushRows()) = false;
    end

    function rows = currentBrushRows()
        d2 = sum((V - selection.brushCenterMm) .^ 2, 2);
        rows = find(d2 <= selection.brushRadiusMm .^ 2);
    end
end

function textOut = statusText(selection)
    textOut = sprintf(['Selected vertices: %d\n', ...
        'Brush center: [%.1f %.1f %.1f] mm\n', ...
        'Brush radius: %.1f mm'], ...
        nnz(selection.selected), ...
        selection.brushCenterMm(1), selection.brushCenterMm(2), ...
        selection.brushCenterMm(3), selection.brushRadiusMm);
end

function h = makeBrushSphere(ax, center, radius)
    [X, Y, Z] = sphere(18);
    h = surf(ax, center(1) + radius * X, ...
        center(2) + radius * Y, center(3) + radius * Z, ...
        'FaceColor', [1.00 0.25 0.85], ...
        'FaceAlpha', 0.08, ...
        'EdgeColor', [1.00 0.25 0.85], ...
        'EdgeAlpha', 0.40, ...
        'HitTest', 'off');
end

function updateBrushSphere(h, center, radius)
    [X, Y, Z] = sphere(18);
    set(h, 'XData', center(1) + radius * X, ...
        'YData', center(2) + radius * Y, ...
        'ZData', center(3) + radius * Z);
end

function out = buildOutput(phone, selection, opts)
    V = double(phone.TR.Points);
    rows = find(selection.selected);
    labels = defaultLabels(numel(rows), opts.objectName);
    selectedCoordinatesMm = V(rows, :);
    remainingRows = find(~selection.selected);
    out = struct();
    out.createdOn = char(datetime('now'));
    out.type = 'phoneScanObjectSelection';
    out.objectName = opts.objectName;
    out.name = opts.objectName;
    out.outputFile = opts.outputFile;
    out.coordinateFrame = phone.coordinateFrame;
    out.source = phone.source;
    out.selectedRows = rows(:);
    out.selectedCoordinatesMm = selectedCoordinatesMm;
    out.coordinatesMm = selectedCoordinatesMm;
    out.selectedLabels = labels;
    out.remainingRows = remainingRows(:);
    out.nSelected = numel(rows);
    out.nRemaining = numel(remainingRows);
    out.brushCenterMm = selection.brushCenterMm;
    out.brushRadiusMm = selection.brushRadiusMm;
    out.cameraState = selection.cameraState;
    out.pointCoordinateFrames = struct( ...
        'selectedCoordinatesMm', phone.coordinateFrame, ...
        'coordinatesMm', phone.coordinateFrame);
    out.traceSets = struct( ...
        'name', opts.objectName, ...
        'coordinatesMm', selectedCoordinatesMm, ...
        'labels', {labels}, ...
        'rows', rows(:));
    out.options = opts;
end

function fig = makeQcFigure(TR, out, opts, visible)
    V = double(TR.Points);
    F = displayFaces(double(TR.ConnectivityList), opts.displayMaxFaces);
    fig = figure('Name', sprintf('Phone object QC: %s', out.objectName), ...
        'NumberTitle', 'off', 'Color', 'w', 'Visible', visible, ...
        'Position', [120 90 1050 760]);
    ax = axes(fig); %#ok<LAXES>
    hold(ax, 'on');
    patch(ax, 'Faces', F, 'Vertices', V, ...
        'FaceColor', [0.72 0.74 0.76], ...
        'FaceAlpha', 0.35, 'EdgeColor', 'none');
    P = double(out.selectedCoordinatesMm);
    if ~isempty(P)
        scatter3(ax, P(:, 1), P(:, 2), P(:, 3), 20, ...
            [0.90 0.05 0.05], 'filled', ...
            'MarkerEdgeColor', [0.10 0.10 0.10]);
    end
    title(ax, sprintf('Selected phone object: %s (%d vertices)', ...
        out.objectName, size(P, 1)), 'Interpreter', 'none');
    axis(ax, 'equal');
    axis(ax, 'vis3d');
    axis(ax, 'off');
    view(ax, 3);
    camlight(ax, 'headlight');
    lighting(ax, 'flat');
end

function Fdisp = displayFaces(F, maxFaces)
    if size(F, 1) <= maxFaces
        Fdisp = F;
        return;
    end
    idx = unique(round(linspace(1, size(F, 1), maxFaces)));
    Fdisp = F(idx(:), :);
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

function [point, idx] = closestVertexToRay(V, rayOrigin, rayDirection)
    d = normalizeRow(rayDirection);
    W = bsxfun(@minus, V, rayOrigin);
    t = W * d(:);
    closest = bsxfun(@plus, rayOrigin, t .* d);
    dist2 = sum((V - closest) .^ 2, 2);
    dist2(t < 0) = inf;
    [~, idx] = min(dist2);
    point = V(idx, :);
end

function setCanonicalView(ax, V, viewNumber)
    center = mean(V(all(isfinite(V), 2), :), 1);
    span = max(max(V, [], 1) - min(V, [], 1));
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
    up = ups(viewNumber, :);
    camtarget(ax, center);
    campos(ax, center + direction .* (2.2 * span));
    camup(ax, up);
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

function tf = matlabToolbarModeActive(fig)
    tf = false;
    try
        tf = ~isempty(get(zoom(fig), 'Enable')) && ...
            strcmpi(get(zoom(fig), 'Enable'), 'on');
        tf = tf || strcmpi(get(pan(fig), 'Enable'), 'on') || ...
            strcmpi(get(rotate3d(fig), 'Enable'), 'on');
    catch
        tf = false;
    end
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

function out = loadExistingSelection(fileName)
    S = load(fileName);
    out = firstStruct(S);
end

function TR = ensureTriangulation(value)
    if isa(value, 'triangulation')
        TR = value;
    elseif isstruct(value) && isfield(value, 'ConnectivityList') && ...
            isfield(value, 'Points')
        TR = triangulation(double(value.ConnectivityList), double(value.Points));
    elseif isstruct(value) && isfield(value, 'faces') && isfield(value, 'vertices')
        TR = triangulation(double(value.faces), double(value.vertices));
    else
        error('acsSelectPhoneScanObject:BadTriangulation', ...
            'Expected a triangulation or faces/vertices structure.');
    end
end

function S = firstStruct(M)
    if isstruct(M) && isfield(M, 'out') && isstruct(M.out)
        S = M.out;
        return;
    end
    if isstruct(M) && isfield(M, 'outForSave') && isstruct(M.outForSave)
        S = M.outForSave;
        return;
    end
    if isstruct(M) && isfield(M, 'phoneObject') && isstruct(M.phoneObject)
        S = M.phoneObject;
        return;
    end
    if isstruct(M)
        fields = fieldnames(M);
        for i = 1:numel(fields)
            if startsWith(fields{i}, '__')
                continue;
            end
            if isstruct(M.(fields{i}))
                S = M.(fields{i});
                return;
            end
        end
    end
    S = M;
end

function value = getOptionalField(S, fieldName, defaultValue)
    value = defaultValue;
    if isstruct(S) && isfield(S, fieldName) && ~isempty(S.(fieldName))
        value = S.(fieldName);
    end
end

function labels = defaultLabels(n, prefix)
    labels = cell(n, 1);
    for i = 1:n
        labels{i} = sprintf('%s_%05d', prefix, i);
    end
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

function writeJsonReport(fileName, out)
    S = rmfieldIfPresent(out, {'selectedCoordinatesMm', 'coordinatesMm', ...
        'traceSets', 'selectedRows', 'remainingRows'});
    try
        fid = fopen(fileName, 'w');
        if fid < 0
            return;
        end
        cleanup = onCleanup(@() fclose(fid));
        fprintf(fid, '%s', jsonencode(S, 'PrettyPrint', true));
    catch
    end
end

function source = sourceLabel(fileName)
    if isempty(fileName)
        source = 'phone scan';
    else
        source = getFileName(fileName);
    end
end

function ensureDir(folder)
    if ~isempty(folder) && exist(folder, 'dir') ~= 7
        mkdir(folder);
    end
end

function fileName = replaceExtension(fileName, newExt)
    [folder, stem] = fileparts(fileName);
    fileName = fullfile(folder, [stem char(newExt)]);
end

function fileName = expandUserPath(fileName)
    fileName = char(fileName);
    if startsWith(fileName, '~')
        homeDir = getenv('HOME');
        if isempty(homeDir)
            homeDir = getenv('USERPROFILE');
        end
        if numel(fileName) == 1
            fileName = homeDir;
        elseif fileName(2) == filesep || fileName(2) == '/' || fileName(2) == '\'
            fileName = fullfile(homeDir, fileName(3:end));
        end
    end
end

function name = getFileName(fileName)
    [~, stem, ext] = fileparts(char(fileName));
    name = [stem ext];
end

function stem = stripMatExtension(fileName)
    [~, stem] = fileparts(char(fileName));
end

function name = safeName(name)
    name = regexprep(char(name), '[^\w\-]+', '_');
    name = regexprep(name, '_+', '_');
    name = regexprep(name, '^_|_$', '');
    if isempty(name)
        name = 'phoneObject';
    end
end

function printSummary(out)
    fprintf('\nPhone scan object selection\n');
    fprintf('  object: %s\n', out.objectName);
    fprintf('  selected vertices: %d\n', out.nSelected);
    fprintf('  frame: %s\n', out.coordinateFrame);
    fprintf('  output: %s\n', out.outputFile);
    if isfield(out, 'qcFigure') && ~isempty(out.qcFigure)
        fprintf('  QC figure: %s\n', out.qcFigure);
    end
end
