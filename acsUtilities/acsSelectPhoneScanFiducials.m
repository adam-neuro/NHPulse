function out = acsSelectPhoneScanFiducials(phoneCropIn, varargin)
% ACSSELECTPHONESCANFIDUCIALS Pick anatomical fiducials on a phone/LiDAR scan.
%
% out = acsSelectPhoneScanFiducials(phoneCropIn) loads a cropped phone-scan
% product from acsCropPhoneScanToHead, opens a mesh picker, and saves named
% fiducials in phone-scan millimeters. The output is intentionally shaped
% like other fiducial point sets: labels + coordinatesMm, so it can be used
% as the moving/source fiducial set for phone-scan-to-MRI registration.
%
% Name-value options:
%   fiducialLabels : labels, 'ask', or 'anatomical' [{'anatomical'}]
%   outputFile     : MAT file for saved fiducials ['']
%   force          : ignore existing outputFile [false]
%   editMode       : 'auto', 'always', or 'never' ['auto']
%   displayMaxFaces: display mesh decimation target [50000]
%   meshAlpha      : mesh face opacity [1]
%   showFigures    : open picker GUI [true]
%   saveFigures    : save QC PNG [true]
%   verbose        : print progress [true]

    if nargin < 1 || isempty(phoneCropIn)
        error('acsSelectPhoneScanFiducials:MissingInput', ...
            'Provide a cropped phone-scan MAT/PLY product.');
    end

    opts = parseInputs(varargin{:});
    addLocalDependencies();
    opts.fiducialLabels = resolveRequestedFiducialLabels(opts);

    phone = readPhoneCrop(phoneCropIn);
    if isempty(opts.outputFile)
        opts.outputFile = defaultOutputFile(phone, opts.fiducialLabels);
    end

    existingFile = exist(opts.outputFile, 'file') == 2;
    openGui = shouldOpenGui(existingFile, opts);
    if ~existingFile && ~openGui
        error('acsSelectPhoneScanFiducials:NoExistingSelection', ...
            ['No saved phone-scan fiducials exist and the selection GUI ', ...
             'is disabled. Run with showFigures=true.']);
    end
    if existingFile && ~opts.force && ~openGui
        out = loadExisting(opts.outputFile);
        logMsg(opts, 'Reusing saved phone-scan fiducials: %s', opts.outputFile);
        return;
    end

    selection = emptySelection(opts.fiducialLabels);
    if existingFile && ~opts.force
        existing = loadExisting(opts.outputFile);
        selection = mergeExistingSelection(selection, existing);
        logMsg(opts, 'Starting from saved phone-scan fiducials: %s', opts.outputFile);
    end

    accepted = true;
    fig = [];
    if openGui
        [selection, accepted, fig] = selectFiducialsGui( ...
            phone.TRhead, phone, selection, opts);
        if ~accepted
            if isgraphics(fig), delete(fig); end
            error('acsSelectPhoneScanFiducials:SelectionCanceled', ...
                'Phone-scan fiducial selection was canceled.');
        end
    end

    out = buildOutput(selection, phone, opts, fig);
    ensureDir(fileparts(opts.outputFile));
    out.outputFile = opts.outputFile;
    out.jsonFile = replaceExtension(opts.outputFile, '.json');
    outSaved = stripFigure(out);
    saveFiducialReport(opts.outputFile, outSaved);
    writeJson(out.jsonFile, jsonReady(outSaved));
    logMsg(opts, 'Saved phone-scan fiducials: %s', opts.outputFile);

    if opts.saveFigures
        qcFile = replaceExtension(opts.outputFile, '_qc.png');
        saveQcFigure(fig, phone.TRhead, out, qcFile, opts);
        out.qcFile = qcFile;
        outSaved = stripFigure(out);
        saveFiducialReport(opts.outputFile, outSaved);
    end

    if isgraphics(fig) && ~opts.showFigures
        delete(fig);
        out.figure = [];
    end
end

function opts = parseInputs(varargin)
    p = inputParser;
    p.FunctionName = 'acsSelectPhoneScanFiducials';
    addParameter(p, 'fiducialLabels', {'anatomical'}, ...
        @(x) iscell(x) || isstring(x) || ischar(x));
    addParameter(p, 'outputFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'force', false, @isBoolLike);
    addParameter(p, 'editMode', 'auto', @isEditMode);
    addParameter(p, 'displayMaxFaces', 50000, @isPositiveScalar);
    addParameter(p, 'meshAlpha', 1, @isAlphaScalar);
    addParameter(p, 'showFigures', true, @isBoolLike);
    addParameter(p, 'saveFigures', true, @isBoolLike);
    addParameter(p, 'verbose', true, @isBoolLike);
    parse(p, varargin{:});

    opts = p.Results;
    opts.fiducialLabels = normalizeLabelCell(opts.fiducialLabels);
    opts.outputFile = expandUserPath(char(opts.outputFile));
    opts.force = logical(opts.force);
    opts.editMode = lower(char(opts.editMode));
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

function tf = isAlphaScalar(x)
    tf = isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0 && x <= 1;
end

function tf = isEditMode(x)
    if ~(ischar(x) || isstring(x))
        tf = false;
        return;
    end
    tf = any(strcmpi(char(x), {'auto', 'always', 'never'}));
end

function addLocalDependencies()
    repoRoot = fileparts(fileparts(mfilename('fullpath')));
    addpath(fullfile(repoRoot, 'acsUtilities'));
    addpath(fullfile(repoRoot, 'capMaker', 'core'));
end

function labels = resolveRequestedFiducialLabels(opts)
    labels = opts.fiducialLabels;
    if isempty(labels) || isSpecialLabelRequest(labels, {'ask', 'select', 'gui', 'bullpen'})
        labels = selectLandmarksFromBullpen(acsMonkeyLandmarkBullpen('anatomical'));
    elseif isSpecialLabelRequest(labels, {'all'})
        labels = normalizeLabelCell(acsMonkeyLandmarkBullpen('labels'));
    elseif isSpecialLabelRequest(labels, {'anatomical', 'anatomicallandmarks'})
        labels = normalizeLabelCell(acsMonkeyLandmarkBullpen('anatomical'));
    elseif isSpecialLabelRequest(labels, {'sessionreference', 'sessionreferences'})
        labels = normalizeLabelCell(acsMonkeyLandmarkBullpen('sessionReference'));
    else
        labels = cleanLabelList(acsMonkeyLandmarkBullpen('canonical', labels));
    end
end

function tf = isSpecialLabelRequest(labels, names)
    labels = normalizeLabelCell(labels);
    tf = numel(labels) == 1 && any(strcmpi(labels{1}, names));
end

function labels = selectLandmarksFromBullpen(defaultLabels)
    items = acsMonkeyLandmarkBullpen('struct');
    list = arrayfun(@(x) sprintf('%s - %s', x.label, x.displayName), ...
        items, 'UniformOutput', false);
    labelsAll = {items.label};
    defaultCanonical = acsMonkeyLandmarkBullpen('canonical', defaultLabels);
    initial = find(ismember(labelsAll, defaultCanonical));
    if isempty(initial)
        initial = 1:min(3, numel(labelsAll));
    end
    [selection, ok] = listdlg( ...
        'PromptString', {'Select phone-scan fiducials to mark.', ...
                         'These should match labels selected on the MRI/capMaker mesh.'}, ...
        'SelectionMode', 'multiple', ...
        'ListString', list, ...
        'InitialValue', initial, ...
        'Name', 'Phone Scan Fiducials');
    if ~ok || isempty(selection)
        error('acsSelectPhoneScanFiducials:SelectionCanceled', ...
            'Phone-scan fiducial label selection was canceled.');
    end
    labels = labelsAll(selection).';
end

function labels = cleanLabelList(labelsIn)
    labels = normalizeLabelCell(labelsIn);
    labels = labels(~cellfun(@isempty, labels));
    labels = unique(labels, 'stable');
end

function phone = readPhoneCrop(value)
    if isstruct(value)
        S = value;
        sourceFile = '';
    else
        fileName = expandUserPath(char(value));
        if exist(fileName, 'file') ~= 2
            error('acsSelectPhoneScanFiducials:FileNotFound', ...
                'Phone crop file not found: %s', fileName);
        end
        [~, ~, ext] = fileparts(fileName);
        switch lower(ext)
            case '.mat'
                M = load(fileName);
                S = firstStruct(M);
            case '.ply'
                ply = readAsciiPlyMesh(fileName);
                S = struct('vertices', ply.vertices, 'faces', ply.faces, ...
                    'coordinateFrame', 'phoneScanRawMm', ...
                    'type', 'phoneScanHeadCrop');
            otherwise
                error('acsSelectPhoneScanFiducials:BadFileType', ...
                    'Phone crop input must be a MAT or ASCII PLY file.');
        end
        sourceFile = fileName;
    end

    if isfield(S, 'TRhead') && ~isempty(S.TRhead)
        TRhead = ensureTriangulation(S.TRhead);
    elseif isfield(S, 'vertices') && isfield(S, 'faces')
        TRhead = triangulation(double(S.faces), double(S.vertices));
    elseif isfield(S, 'pointCloudMm') && isfield(S, 'faces')
        TRhead = triangulation(double(S.faces), double(S.pointCloudMm));
    else
        error('acsSelectPhoneScanFiducials:BadPhoneCrop', ...
            'Phone crop input must contain TRhead or vertices/faces.');
    end
    coordinateFrame = char(getOptionalField(S, 'coordinateFrame', 'phoneScanRawMm'));
    phone = struct();
    phone.TRhead = TRhead;
    phone.coordinateFrame = coordinateFrame;
    phone.sourceFile = sourceFile;
    phone.type = char(getOptionalField(S, 'type', 'phoneScanHeadCrop'));
    phone.label = sourceLabel(sourceFile);
end

function label = sourceLabel(sourceFile)
    if isempty(sourceFile)
        label = 'phone scan';
    else
        label = getFileStem(sourceFile);
    end
end

function tf = shouldOpenGui(existingFile, opts)
    if ~opts.showFigures
        tf = false;
        return;
    end
    switch opts.editMode
        case 'always'
            tf = true;
        case 'never'
            tf = false;
        otherwise
            tf = opts.force || ~existingFile;
    end
end

function selection = emptySelection(labels)
    n = numel(labels);
    selection = struct();
    selection.labels = labels(:);
    selection.coordinatesMm = nan(n, 3);
    selection.selectedVertex = nan(n, 1);
end

function selection = mergeExistingSelection(selection, existing)
    if ~isfield(existing, 'labels') || ~isfield(existing, 'coordinatesMm')
        return;
    end
    oldLabels = normalizeLabelCell(existing.labels);
    oldCoords = double(existing.coordinatesMm);
    oldVertex = nan(size(oldCoords, 1), 1);
    if isfield(existing, 'selectedVertex') && ~isempty(existing.selectedVertex)
        oldVertex = double(existing.selectedVertex(:));
    end
    for i = 1:numel(selection.labels)
        hit = findLabelAliasMatch(selection.labels{i}, oldLabels);
        if ~isempty(hit) && hit <= size(oldCoords, 1)
            selection.coordinatesMm(i, :) = oldCoords(hit, :);
            selection.selectedVertex(i) = oldVertex(hit);
        end
    end
end

function hit = findLabelAliasMatch(label, candidateLabels)
    hit = [];
    candidateNorm = normalizeLabelKeys(candidateLabels);
    aliases = normalizeLabelKeys(acsMonkeyLandmarkBullpen('aliasesFor', label));
    aliases = unique([normalizeLabelKeys({label}); aliases(:)], 'stable');
    for i = 1:numel(aliases)
        hit = find(strcmp(candidateNorm, aliases{i}), 1);
        if ~isempty(hit)
            return;
        end
    end
end

function labels = normalizeLabelKeys(labelsIn)
    labels = normalizeLabelCell(labelsIn);
    labels = regexprep(labels, '[^A-Za-z0-9]', '');
    labels = cellfun(@lower, labels, 'UniformOutput', false);
end

function [selection, accepted, fig] = selectFiducialsGui(TRhead, phone, selection, opts)
    V = double(TRhead.Points);
    F = double(TRhead.ConnectivityList);
    displayMesh = decimateMeshForDisplay(F, V, opts.displayMaxFaces);
    n = numel(selection.labels);
    active = firstUnset(selection);
    accepted = false;
    dragStart = [];
    isWaiting = false;

    fig = figure( ...
        'Name', 'Select phone scan fiducials', ...
        'NumberTitle', 'off', ...
        'Color', 'w', ...
        'ToolBar', 'figure', ...
        'MenuBar', 'figure', ...
        'CloseRequestFcn', @onCloseRequest);
    ax = axes('Parent', fig, 'Position', [0.03 0.08 0.72 0.86], ...
        'Tag', 'phoneScanFiducialMainAxes');
    hold(ax, 'on');
    patch(ax, ...
        'Faces', displayMesh.faces, ...
        'Vertices', displayMesh.vertices, ...
        'FaceColor', [0.76 0.80 0.84], ...
        'EdgeColor', 'none', ...
        'FaceAlpha', opts.meshAlpha, ...
        'FaceLighting', 'flat', ...
        'BackFaceLighting', 'reverselit', ...
        'AmbientStrength', 0.55, ...
        'DiffuseStrength', 0.45, ...
        'SpecularStrength', 0.05);
    markerHandles = gobjects(n, 1);
    textHandles = gobjects(n, 1);
    for i = 1:n
        markerHandles(i) = scatter3(ax, nan, nan, nan, 115, ...
            [0.90 0.15 0.12], 'filled', 'MarkerEdgeColor', 'k', 'LineWidth', 1.0);
        textHandles(i) = text(ax, nan, nan, nan, '', ...
            'FontWeight', 'bold', 'Color', [0.05 0.05 0.05], ...
            'BackgroundColor', 'w', 'Margin', 1, 'Interpreter', 'none');
    end
    axis(ax, 'vis3d');
    axis(ax, 'equal');
    axis(ax, 'off');
    setInitialView(ax, V);
    cameraLight = camlight(ax, 'headlight');
    lighting(ax, 'flat');

    labelPopup = uicontrol(fig, ...
        'Style', 'popupmenu', ...
        'String', selection.labels, ...
        'Units', 'normalized', ...
        'Position', [0.78 0.86 0.18 0.05], ...
        'Value', active, ...
        'Callback', @onLabelPopup);
    status = uicontrol(fig, ...
        'Style', 'text', ...
        'Units', 'normalized', ...
        'Position', [0.77 0.43 0.21 0.40], ...
        'BackgroundColor', 'w', ...
        'HorizontalAlignment', 'left', ...
        'FontSize', 10);
    uicontrol(fig, 'Style', 'pushbutton', 'String', 'Previous', ...
        'Units', 'normalized', 'Position', [0.78 0.34 0.085 0.055], ...
        'Callback', @onPrevious);
    uicontrol(fig, 'Style', 'pushbutton', 'String', 'Next', ...
        'Units', 'normalized', 'Position', [0.875 0.34 0.085 0.055], ...
        'Callback', @onNext);
    uicontrol(fig, 'Style', 'pushbutton', 'String', 'Clear active', ...
        'Units', 'normalized', 'Position', [0.78 0.27 0.18 0.055], ...
        'Callback', @onClearActive);
    uicontrol(fig, 'Style', 'pushbutton', 'String', 'Done', ...
        'Units', 'normalized', 'Position', [0.78 0.17 0.18 0.07], ...
        'Callback', @onDone);
    uicontrol(fig, 'Style', 'pushbutton', 'String', 'Cancel', ...
        'Units', 'normalized', 'Position', [0.78 0.07 0.18 0.06], ...
        'Callback', @onCancel);

    updateGraphics();
    if opts.verbose
        fprintf('\nPhone-scan fiducial selection controls:\n');
        fprintf('  Shift-click mesh: set active fiducial to nearest scan vertex\n');
        fprintf('  Drag: rotate view\n');
        fprintf('  N/P or right/left arrows: next/previous fiducial\n');
        fprintf('  X/Y/Z: canonical views; Delete/C: clear active fiducial\n');
    end

    set(fig, ...
        'WindowButtonDownFcn', @onMouseDown, ...
        'WindowButtonUpFcn', @onMouseUp, ...
        'WindowKeyPressFcn', @onKeyPress);
    isWaiting = true;
    uiwait(fig);
    isWaiting = false;

    function onLabelPopup(~, ~)
        active = get(labelPopup, 'Value');
        updateGraphics();
    end

    function onPrevious(~, ~)
        active = max(1, active - 1);
        set(labelPopup, 'Value', active);
        updateGraphics();
    end

    function onNext(~, ~)
        active = min(n, active + 1);
        set(labelPopup, 'Value', active);
        updateGraphics();
    end

    function onClearActive(~, ~)
        selection.coordinatesMm(active, :) = nan(1, 3);
        selection.selectedVertex(active) = nan;
        updateGraphics();
    end

    function onMouseDown(~, ~)
        if matlabToolbarModeActive(fig)
            clearCustomDrag();
            return;
        end
        clickedAxes = ancestor(hittest(fig), 'axes');
        if isempty(clickedAxes) || clickedAxes ~= ax
            clearCustomDrag();
            return;
        end
        modifiers = get(fig, 'CurrentModifier');
        if hasAnyModifier(modifiers, {'shift'})
            setActiveFromClick();
            return;
        end
        dragStart = get(fig, 'CurrentPoint');
        set(fig, 'WindowButtonMotionFcn', @onDrag);
    end

    function setActiveFromClick()
        [rayOrigin, rayDirection] = clickRay(ax);
        [point, vertex] = closestVertexToRay(V, rayOrigin, rayDirection);
        selection.coordinatesMm(active, :) = point;
        selection.selectedVertex(active) = vertex;
        if active < n
            active = active + 1;
            set(labelPopup, 'Value', active);
        end
        updateGraphics();
    end

    function onDrag(~, ~)
        if isempty(dragStart) || matlabToolbarModeActive(fig)
            clearCustomDrag();
            return;
        end
        pointer = get(fig, 'CurrentPoint');
        delta = pointer - dragStart;
        dragStart = pointer;
        camorbit(ax, -0.35 * delta(1), -0.35 * delta(2), 'camera');
        camlight(cameraLight, 'headlight');
        drawnow limitrate;
    end

    function onMouseUp(~, ~)
        clearCustomDrag();
    end

    function clearCustomDrag()
        dragStart = [];
        if isgraphics(fig)
            set(fig, 'WindowButtonMotionFcn', '');
        end
    end

    function onKeyPress(~, event)
        switch lower(event.Key)
            case {'n', 'rightarrow'}
                onNext([], []);
            case {'p', 'leftarrow'}
                onPrevious([], []);
            case {'delete', 'backspace', 'c'}
                onClearActive([], []);
            case 'x'
                setCanonicalView([1 0 0], [0 0 1]);
            case 'y'
                setCanonicalView([0 1 0], [0 0 1]);
            case 'z'
                setCanonicalView([0 0 1], [0 1 0]);
            case {'return', 'enter'}
                onDone([], []);
        end
    end

    function setCanonicalView(axisDirection, upDirection)
        anchor = mean(V, 1);
        cameraDistance = norm(campos(ax) - camtarget(ax));
        if ~isfinite(cameraDistance) || cameraDistance <= 0
            cameraDistance = 1.5 * norm(max(V, [], 1) - min(V, [], 1));
        end
        camtarget(ax, anchor);
        campos(ax, anchor + cameraDistance * axisDirection);
        camup(ax, upDirection);
        camlight(cameraLight, 'headlight');
    end

    function onDone(~, ~)
        missing = selection.labels(any(~isfinite(selection.coordinatesMm), 2));
        if ~isempty(missing)
            answer = questdlg(sprintf( ...
                'Missing fiducials: %s\n\nSave anyway?', strjoin(missing, ', ')), ...
                'Missing phone-scan fiducials', 'Save anyway', ...
                'Continue editing', 'Continue editing');
            if ~strcmp(answer, 'Save anyway')
                return;
            end
        end
        accepted = true;
        resumeOrDeleteFigure();
    end

    function onCancel(~, ~)
        accepted = false;
        resumeOrDeleteFigure();
    end

    function onCloseRequest(~, ~)
        accepted = false;
        resumeOrDeleteFigure();
    end

    function resumeOrDeleteFigure()
        if ~isgraphics(fig)
            return;
        end
        if isWaiting
            uiresume(fig);
        else
            delete(fig);
        end
    end

    function updateGraphics()
        for j = 1:n
            p = selection.coordinatesMm(j, :);
            if all(isfinite(p))
                set(markerHandles(j), 'XData', p(1), 'YData', p(2), ...
                    'ZData', p(3), 'SizeData', 115 + 80 * (j == active), ...
                    'MarkerFaceColor', markerColor(j == active));
                set(textHandles(j), 'Position', p + labelOffset(V), ...
                    'String', selection.labels{j}, 'Visible', 'on');
            else
                set(markerHandles(j), 'XData', nan, 'YData', nan, 'ZData', nan);
                set(textHandles(j), 'Visible', 'off');
            end
        end
        set(status, 'String', statusText(phone, selection, active));
        title(ax, sprintf('Shift-click %s on phone scan', ...
            selection.labels{active}), 'Interpreter', 'none');
        drawnow limitrate;
    end
end

function color = markerColor(isActive)
    if isActive
        color = [1.0 0.75 0.05];
    else
        color = [0.90 0.15 0.12];
    end
end

function textOut = statusText(phone, selection, active)
    isSet = all(isfinite(selection.coordinatesMm), 2);
    if isSet(active)
        coordText = sprintf('[%.1f %.1f %.1f] mm', selection.coordinatesMm(active, :));
    else
        coordText = '(not set)';
    end
    textOut = sprintf(['Phone scan: %s\nFrame: %s\n\nActive: %s\n%s\n\n', ...
        'Selected: %d / %d\n\nShift-click places active fiducial.\n', ...
        'Drag rotates view.'], ...
        phone.label, phone.coordinateFrame, selection.labels{active}, ...
        coordText, nnz(isSet), numel(isSet));
end

function idx = firstUnset(selection)
    idx = find(any(~isfinite(selection.coordinatesMm), 2), 1);
    if isempty(idx)
        idx = 1;
    end
end

function out = buildOutput(selection, phone, opts, fig)
    out = struct();
    out.createdOn = char(datetime('now'));
    out.type = 'phoneScanFiducials';
    out.labels = selection.labels(:);
    out.coordinatesMm = double(selection.coordinatesMm);
    out.selectedVertex = double(selection.selectedVertex(:));
    out.coordinateFrame = phone.coordinateFrame;
    out.modelType = 'phoneScanMesh';
    out.source = struct( ...
        'file', phone.sourceFile, ...
        'type', phone.type, ...
        'label', phone.label, ...
        'coordinateFrame', phone.coordinateFrame);
    out.options = opts;
    out.figure = fig;
    out.qcFile = '';
end

function out = loadExisting(fileName)
    S = load(fileName);
    if isfield(S, 'out')
        out = S.out;
    elseif isfield(S, 'outSaved')
        out = S.outSaved;
    elseif isfield(S, 'outForSave')
        out = S.outForSave;
    else
        out = firstStruct(S);
    end
end

function stripped = stripFigure(S)
    stripped = S;
    if isfield(stripped, 'figure')
        stripped.figure = [];
    end
end

function mesh = decimateMeshForDisplay(F, V, maxFaces)
    mesh.faces = double(F);
    mesh.vertices = double(V);
    if maxFaces > 0 && size(mesh.faces, 1) > maxFaces
        [mesh.faces, mesh.vertices] = reducepatch(mesh.faces, mesh.vertices, maxFaces);
        mesh.faces = double(mesh.faces);
        mesh.vertices = double(mesh.vertices);
    end
    mesh.faces = orientFacesForDisplay(mesh.faces, mesh.vertices);
end

function F = orientFacesForDisplay(F, V)
    if isempty(F) || isempty(V)
        return;
    end
    try
        if exist('unifyOutwardNormalsRobust', 'file') == 2
            TR = unifyOutwardNormalsRobust(triangulation(F, V));
            F = double(TR.ConnectivityList);
            return;
        end
    catch
        % Display-only fallback below.
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

function [point, vertex] = closestVertexToRay(V, rayOrigin, rayDirection)
    rel = bsxfun(@minus, V, rayOrigin);
    proj = rel * rayDirection(:);
    closest = bsxfun(@plus, rayOrigin, proj .* rayDirection);
    d2 = sum((V - closest) .^ 2, 2);
    [~, vertex] = min(d2);
    point = V(vertex, :);
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

function setInitialView(ax, V)
    V = double(V);
    anchor = mean(V, 1);
    span = max(V, [], 1) - min(V, [], 1);
    cameraDistance = 2.8 * norm(span);
    if ~isfinite(cameraDistance) || cameraDistance <= 0
        cameraDistance = 250;
    end
    viewDirection = normalizeRow([-1 1 0.65]);
    camtarget(ax, anchor);
    campos(ax, anchor + cameraDistance * viewDirection);
    camup(ax, [0 0 1]);
    camva(ax, 10);
end

function tf = hasAnyModifier(modifiers, names)
    if isempty(modifiers)
        tf = false;
        return;
    end
    if ischar(modifiers)
        modifiers = {modifiers};
    end
    tf = any(ismember(lower(modifiers), lower(names)));
end

function tf = matlabToolbarModeActive(fig)
    tf = false;
    try
        mgr = uigetmodemanager(fig);
        tf = ~isempty(mgr) && ~isempty(mgr.CurrentMode);
    catch
        tf = false;
    end
end

function row = normalizeRow(row)
    row = double(row(:))';
    n = norm(row);
    if n > eps && all(isfinite(row))
        row = row ./ n;
    end
end

function offset = labelOffset(V)
    span = max(V, [], 1) - min(V, [], 1);
    offset = 0.018 * max(norm(span), 1) * normalizeRow([1 1 0.4]);
end

function fileName = defaultOutputFile(phone, labels)
    labelText = strjoin(labels(:)', '_');
    labelText = regexprep(labelText, '[^A-Za-z0-9_]+', '');
    if isempty(labelText)
        labelText = 'fiducials';
    end
    if ~isempty(phone.sourceFile)
        folder = fileparts(phone.sourceFile);
        stem = getFileStem(phone.sourceFile);
    else
        folder = pwd;
        stem = 'phoneScan';
    end
    fileName = fullfile(folder, [stem '_phoneScanFiducials_' labelText '.mat']);
end

function saveQcFigure(fig, TRhead, out, fileName, opts)
    cameraState = captureCameraState(fig);
    figQc = figure('Visible', 'off', 'Color', 'w');
    ax = axes('Parent', figQc);
    V = double(TRhead.Points);
    F = double(TRhead.ConnectivityList);
    displayMesh = decimateMeshForDisplay(F, V, opts.displayMaxFaces);
    patch(ax, 'Faces', displayMesh.faces, 'Vertices', displayMesh.vertices, ...
        'FaceColor', [0.76 0.80 0.84], 'EdgeColor', 'none', ...
        'FaceAlpha', 1, 'FaceLighting', 'flat', ...
        'BackFaceLighting', 'reverselit', 'AmbientStrength', 0.55, ...
        'DiffuseStrength', 0.45, 'SpecularStrength', 0.05);
    hold(ax, 'on');
    axis(ax, 'equal');
    axis(ax, 'vis3d');
    axis(ax, 'off');
    if isempty(cameraState)
        setInitialView(ax, V);
    else
        applyCameraState(ax, cameraState);
    end
    isSet = all(isfinite(out.coordinatesMm), 2);
    coords = out.coordinatesMm(isSet, :);
    labels = out.labels(isSet);
    scatter3(ax, coords(:, 1), coords(:, 2), coords(:, 3), 85, ...
        [0.90 0.15 0.12], 'filled', 'MarkerEdgeColor', 'k', 'LineWidth', 1.0);
    for i = 1:numel(labels)
        p = coords(i, :) + labelOffset(V);
        text(ax, p(1), p(2), p(3), labels{i}, ...
            'FontWeight', 'bold', 'Color', [0.05 0.05 0.05], ...
            'BackgroundColor', 'w', 'Margin', 1, 'Interpreter', 'none');
    end
    title(ax, 'Phone scan fiducials', 'Interpreter', 'none');
    camlight(ax, 'headlight');
    lighting(ax, 'flat');
    ensureDir(fileparts(fileName));
    try
        exportgraphics(figQc, fileName, 'Resolution', 200);
    catch
        saveas(figQc, fileName);
    end
    close(figQc);
end

function state = captureCameraState(fig)
    state = [];
    if ~isgraphics(fig)
        return;
    end
    ax = findobj(fig, 'Type', 'axes', 'Tag', 'phoneScanFiducialMainAxes');
    if isempty(ax) || ~isgraphics(ax(1))
        return;
    end
    ax = ax(1);
    state = struct( ...
        'CameraPosition', get(ax, 'CameraPosition'), ...
        'CameraTarget', get(ax, 'CameraTarget'), ...
        'CameraUpVector', get(ax, 'CameraUpVector'), ...
        'CameraViewAngle', get(ax, 'CameraViewAngle'));
end

function applyCameraState(ax, state)
    set(ax, ...
        'CameraPosition', state.CameraPosition, ...
        'CameraTarget', state.CameraTarget, ...
        'CameraUpVector', state.CameraUpVector, ...
        'CameraViewAngle', state.CameraViewAngle);
end

function saveFiducialReport(fileName, outSaved)
    out = outSaved; %#ok<NASGU>
    outForSave = outSaved; %#ok<NASGU>
    outToSave = outSaved; %#ok<NASGU>
    save(fileName, 'out', 'outSaved', 'outForSave', 'outToSave');
end

function writeJson(fileName, S)
    fid = fopen(fileName, 'wt');
    if fid < 0
        error('acsSelectPhoneScanFiducials:CouldNotWriteJson', ...
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
    elseif isa(S, 'matlab.ui.Figure')
        S = char(class(S));
    elseif isa(S, 'triangulation')
        S = struct('class', 'triangulation');
    end
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
        error('acsSelectPhoneScanFiducials:BadTriangulation', ...
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
    if isstruct(M) && isfield(M, 'outSaved') && isstruct(M.outSaved)
        S = M.outSaved;
        return;
    end
    if isstruct(M)
        fields = fieldnames(M);
        for i = 1:numel(fields)
            value = M.(fields{i});
            if isstruct(value)
                S = value;
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

function ensureDir(folder)
    if isempty(folder), return; end
    if exist(folder, 'dir') ~= 7
        mkdir(folder);
    end
end

function fileName = replaceExtension(fileName, newExt)
    [folder, stem] = fileparts(fileName);
    fileName = fullfile(folder, [stem newExt]);
end

function stem = getFileStem(fileName)
    [~, stem] = fileparts(char(fileName));
end

function logMsg(opts, varargin)
    if opts.verbose
        fprintf([varargin{1} '\n'], varargin{2:end});
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

function ply = readAsciiPlyMesh(fileName)
    fid = fopen(fileName, 'r');
    if fid < 0
        error('acsSelectPhoneScanFiducials:CannotOpenPly', ...
            'Could not open PLY file: %s', fileName);
    end
    cleanup = onCleanup(@() fclose(fid));
    line = fgetl(fid);
    if ~ischar(line) || ~strcmp(strtrim(line), 'ply')
        error('acsSelectPhoneScanFiducials:BadPly', ...
            'File does not start with a PLY header: %s', fileName);
    end
    nVertices = 0;
    nFaces = 0;
    isAscii = false;
    while true
        line = fgetl(fid);
        if ~ischar(line)
            error('acsSelectPhoneScanFiducials:BadPlyHeader', ...
                'PLY header ended unexpectedly.');
        end
        txt = strtrim(line);
        if startsWith(txt, 'format ascii')
            isAscii = true;
        elseif startsWith(txt, 'element vertex')
            parts = strsplit(txt);
            nVertices = str2double(parts{3});
        elseif startsWith(txt, 'element face')
            parts = strsplit(txt);
            nFaces = str2double(parts{3});
        elseif strcmp(txt, 'end_header')
            break;
        end
    end
    if ~isAscii
        error('acsSelectPhoneScanFiducials:BinaryPlyUnsupported', ...
            'Only ASCII PLY files are supported directly. Use the cropped MAT product if needed.');
    end
    V = nan(nVertices, 3);
    for i = 1:nVertices
        parts = sscanf(fgetl(fid), '%f');
        V(i, :) = parts(1:3)';
    end
    F = nan(nFaces, 3);
    keep = true(nFaces, 1);
    for i = 1:nFaces
        parts = sscanf(fgetl(fid), '%d');
        if isempty(parts) || parts(1) < 3
            keep(i) = false;
            continue;
        end
        F(i, :) = double(parts(2:4)' + 1);
    end
    ply = struct('vertices', V, 'faces', F(keep, :));
    clear cleanup;
end
