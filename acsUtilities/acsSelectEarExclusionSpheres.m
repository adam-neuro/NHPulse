function out = acsSelectEarExclusionSpheres(layoutOrMesh, varargin)
% ACSSELECTEAREXCLUSIONSPHERES Select subject-specific ear/face exclusion regions.
%
% out = acsSelectEarExclusionSpheres(layout)
% loads the capMaker scalp mesh associated with a layout report, proposes
% left/right ear exclusion spheres in capMaker print-frame millimeters, lets
% the user optionally paint mesh-specific exclusion vertices, and optionally
% opens a small GUI for adjustment. The returned
% out.exclusionCenters and out.exclusionRadiusMM fields can be assigned
% directly into targetOptions for autoElectrodeTargets. Painted exclusions
% are carried as out.customExclusionVertexInd.
%
% Name-value options:
%   outputFile            : MAT file for saved exclusions ['']
%   force                 : ignore existing outputFile [false]
%   editMode              : 'auto', 'always', or 'never' ['auto']
%   showFigures           : open adjustment GUI [true]
%   saveFigures           : save QC figure [false]
%   caudalFraction        : proposal Y fraction from caudal extent [1/3]
%   heightFraction        : proposal Z fraction from printer bed [1/3]
%   diameterFraction      : proposal sphere diameter as LR range [1/4]
%   yzBandFraction        : proposal Y/Z search band fraction [0.12]
%   displayMaxFaces       : display mesh decimation target [12000]
%   showVertexOverlay     : color scalp vertices by ear-exclusion status [true]
%   vertexOverlayMaxPoints: max vertices shown in adjustment GUI [20000]
%   enablePaintedExclusions: enable mesh-vertex painting for face/other zones [true]
%   paintBrushRadiusMm    : painted-exclusion brush radius [6]
%   showStrapPreview      : preview chin-strap placement keepout [true]
%   strapRostralOffsetMm  : strap root offset rostral to ear edge [0]
%   strapWidthMm          : nominal chin-strap width for keepout [10]
%   strapMarginMm         : extra strap/electrode placement margin [2]
%   strapExclusionRadiusMm: override preview sphere radius [[]]
%   strapLateralLengthMm  : lateral preview length from each ear [35]
%   strapSampleSpacingMm  : preview spacing along strap root [5]
%   holderOutsideDiaMm    : electrode holder diameter used in keepout [12]
%   zBedMm                : printer bed plane used for strap preview [0]
%   nudgeStepMM           : keyboard center nudge step [1]
%   radiusStepMM          : keyboard radius step [1]
%   verbose               : print progress [true]

    if nargin < 1 || isempty(layoutOrMesh)
        error('acsSelectEarExclusionSpheres:MissingInput', ...
            'Provide a layout struct/report, skin mesh cache, or triangulation.');
    end

    opts = parseInputs(varargin{:});
    addLocalDependencies();

    [TRskin, source] = readSkinMesh(layoutOrMesh);
    source.meshFingerprint = meshFingerprint(TRskin);
    if isempty(opts.outputFile)
        opts.outputFile = defaultOutputFile(source);
    end

    existingFile = exist(opts.outputFile, 'file') == 2;
    existingMatches = existingFile && savedEarExclusionsMatchSource(opts.outputFile, source);
    if existingFile && ~existingMatches && ~opts.force
        logMsg(opts, ['Saved ear exclusions do not match the current capMaker ', ...
            'skin mesh/crop; reusing saved coordinates and remapping painted ', ...
            'vertices to the current mesh: %s'], opts.outputFile);
    end
    openGui = shouldOpenGui(existingFile && existingMatches, opts);

    if existingFile && existingMatches && ~opts.force && ~openGui
        out = loadExisting(opts.outputFile);
        logMsg(opts, 'Reusing saved ear exclusions: %s', opts.outputFile);
        return;
    end

    proposal = proposeEarSpheres(TRskin.Points, opts);
    proposal = ensurePaintedExclusionProposal(proposal, size(TRskin.Points, 1), opts);
    if existingFile && ~opts.force
        try
            existing = loadExisting(opts.outputFile);
            proposal.centers = existing.exclusionCenters;
            proposal.radii = existing.exclusionRadiusMM;
            proposal = copySavedPaintedExclusions(proposal, existing, ...
                double(TRskin.Points), opts);
            if existingMatches
                logMsg(opts, 'Starting from saved ear exclusions: %s', opts.outputFile);
            else
                logMsg(opts, 'Starting from saved ear exclusion coordinates: %s', opts.outputFile);
            end
        catch ME
            warning('acsSelectEarExclusionSpheres:SavedLoadFailed', ...
                'Could not load saved ear exclusions from %s (%s). Using automatic proposal.', ...
                opts.outputFile, ME.message);
        end
    end

    accepted = true;
    fig = [];
    if openGui
        [proposal, accepted, fig] = selectEarSpheresGui(TRskin, proposal, opts);
        if ~accepted
            if isgraphics(fig)
                delete(fig);
            end
            error('acsSelectEarExclusionSpheres:SelectionCanceled', ...
                'Ear exclusion sphere selection was canceled.');
        end
    end

    out = buildOutput(proposal, source, opts, [], TRskin);
    ensureDir(fileparts(opts.outputFile));
    out.outputFile = opts.outputFile;
    out.jsonFile = replaceMatExtension(opts.outputFile, '.json');
    outSaved = stripFigure(out);
    saveOutput(opts.outputFile, outSaved);
    writeJsonReport(out.jsonFile, jsonReady(out));
    logMsg(opts, 'Saved ear exclusion spheres: %s', opts.outputFile);

    if opts.saveFigures
        qcFile = replaceMatExtension(opts.outputFile, '_qc.png');
        saveQcFigure(fig, qcFile, TRskin, proposal);
        out.qcFile = qcFile;
        outSaved = stripFigure(out);
        saveOutput(opts.outputFile, outSaved);
    end

    if isgraphics(fig)
        delete(fig);
    end
end

function opts = parseInputs(varargin)
    p = inputParser;
    p.FunctionName = 'acsSelectEarExclusionSpheres';
    addParameter(p, 'outputFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'force', false, @isBoolLike);
    addParameter(p, 'editMode', 'auto', @isEditMode);
    addParameter(p, 'showFigures', true, @isBoolLike);
    addParameter(p, 'saveFigures', false, @isBoolLike);
    addParameter(p, 'caudalFraction', 1/3, @isUnitScalar);
    addParameter(p, 'heightFraction', 1/3, @isUnitScalar);
    addParameter(p, 'diameterFraction', 1/4, @isPositiveScalar);
    addParameter(p, 'yzBandFraction', 0.12, @isPositiveScalar);
    addParameter(p, 'displayMaxFaces', 12000, @isPositiveScalar);
    addParameter(p, 'showVertexOverlay', true, @isBoolLike);
    addParameter(p, 'vertexOverlayMaxPoints', 20000, @isPositiveScalar);
    addParameter(p, 'enablePaintedExclusions', true, @isBoolLike);
    addParameter(p, 'paintBrushRadiusMm', 6, @isPositiveScalar);
    addParameter(p, 'showStrapPreview', true, @isBoolLike);
    addParameter(p, 'strapRostralOffsetMm', 0, @isNonnegativeScalar);
    addParameter(p, 'strapWidthMm', 10, @isPositiveScalar);
    addParameter(p, 'strapMarginMm', 2, @isNonnegativeScalar);
    addParameter(p, 'strapExclusionRadiusMm', [], ...
        @(x) isempty(x) || isPositiveScalar(x));
    addParameter(p, 'strapLateralLengthMm', 35, @isPositiveScalar);
    addParameter(p, 'strapSampleSpacingMm', 5, @isPositiveScalar);
    addParameter(p, 'holderOutsideDiaMm', 12, @isPositiveScalar);
    addParameter(p, 'zBedMm', 0, @(x) isnumeric(x) && isscalar(x) && isfinite(x));
    addParameter(p, 'nudgeStepMM', 1, @isPositiveScalar);
    addParameter(p, 'radiusStepMM', 1, @isPositiveScalar);
    addParameter(p, 'verbose', true, @isBoolLike);
    parse(p, varargin{:});

    opts = p.Results;
    opts.outputFile = expandUserPath(char(opts.outputFile));
    opts.force = logical(opts.force);
    opts.editMode = lower(char(opts.editMode));
    opts.showFigures = logical(opts.showFigures);
    opts.saveFigures = logical(opts.saveFigures);
    opts.caudalFraction = double(opts.caudalFraction);
    opts.heightFraction = double(opts.heightFraction);
    opts.diameterFraction = double(opts.diameterFraction);
    opts.yzBandFraction = double(opts.yzBandFraction);
    opts.displayMaxFaces = round(double(opts.displayMaxFaces));
    opts.showVertexOverlay = logical(opts.showVertexOverlay);
    opts.vertexOverlayMaxPoints = round(double(opts.vertexOverlayMaxPoints));
    opts.enablePaintedExclusions = logical(opts.enablePaintedExclusions);
    opts.paintBrushRadiusMm = double(opts.paintBrushRadiusMm);
    opts.showStrapPreview = logical(opts.showStrapPreview);
    opts.strapRostralOffsetMm = double(opts.strapRostralOffsetMm);
    opts.strapWidthMm = double(opts.strapWidthMm);
    opts.strapMarginMm = double(opts.strapMarginMm);
    if ~isempty(opts.strapExclusionRadiusMm)
        opts.strapExclusionRadiusMm = double(opts.strapExclusionRadiusMm);
    end
    opts.strapLateralLengthMm = double(opts.strapLateralLengthMm);
    opts.strapSampleSpacingMm = double(opts.strapSampleSpacingMm);
    opts.holderOutsideDiaMm = double(opts.holderOutsideDiaMm);
    opts.zBedMm = double(opts.zBedMm);
    opts.nudgeStepMM = double(opts.nudgeStepMM);
    opts.radiusStepMM = double(opts.radiusStepMM);
    opts.verbose = logical(opts.verbose);
end

function tf = isEditMode(x)
    if ~(ischar(x) || isstring(x))
        tf = false;
        return;
    end
    tf = any(strcmpi(char(x), {'auto', 'always', 'never'}));
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

function tf = isBoolLike(x)
    tf = (islogical(x) || isnumeric(x)) && isscalar(x);
end

function tf = isUnitScalar(x)
    tf = isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0 && x <= 1;
end

function tf = isPositiveScalar(x)
    tf = isnumeric(x) && isscalar(x) && isfinite(x) && x > 0;
end

function tf = isNonnegativeScalar(x)
    tf = isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0;
end

function addLocalDependencies()
    repoRoot = fileparts(fileparts(mfilename('fullpath')));
    addpath(fullfile(repoRoot, 'acsUtilities'));
end

function [TRskin, source] = readSkinMesh(value)
    source = struct('type', '', 'file', '', 'layoutFile', '', 'label', '');

    if isa(value, 'triangulation')
        TRskin = value;
        source.type = 'triangulation';
        source.label = 'triangulation';
        return;
    end

    if isstruct(value) && isfield(value, 'Points') && isfield(value, 'ConnectivityList')
        TRskin = triangulation(double(value.ConnectivityList), double(value.Points));
        source.type = 'meshStruct';
        source.label = 'mesh struct';
        return;
    end

    if isstruct(value)
        [TRskin, source] = readSkinMeshFromLayout(value, source);
        return;
    end

    if ~(ischar(value) || isstring(value))
        error('acsSelectEarExclusionSpheres:BadInput', ...
            'Input must be a layout, skin cache, mesh struct, or triangulation.');
    end

    fileName = expandUserPath(char(value));
    if exist(fileName, 'file') ~= 2
        error('acsSelectEarExclusionSpheres:FileNotFound', ...
            'File not found: %s', fileName);
    end
    S = load(fileName);
    if isfield(S, 'TRskin')
        TRskin = S.TRskin;
        source.type = 'skinCache';
        source.file = fileName;
        source.label = getFileStem(fileName);
    else
        layout = firstStruct(S);
        source.layoutFile = fileName;
        [TRskin, source] = readSkinMeshFromLayout(layout, source);
        if isempty(source.label)
            source.label = getFileStem(fileName);
        end
    end
end

function [TRskin, source] = readSkinMeshFromLayout(layout, source)
    if ~isfield(layout, 'layout') || ~isfield(layout.layout, 'skin') || ...
            ~isfield(layout.layout.skin, 'cacheFile') || ...
            isempty(layout.layout.skin.cacheFile)
        error('acsSelectEarExclusionSpheres:MissingSkinCache', ...
            'Layout does not report layout.skin.cacheFile.');
    end
    cacheFile = char(layout.layout.skin.cacheFile);
    if exist(cacheFile, 'file') ~= 2
        error('acsSelectEarExclusionSpheres:SkinCacheNotFound', ...
            'Skin cache not found: %s', cacheFile);
    end
    S = load(cacheFile, 'TRskin');
    if ~isfield(S, 'TRskin')
        error('acsSelectEarExclusionSpheres:BadSkinCache', ...
            'Skin cache does not contain TRskin: %s', cacheFile);
    end
    TRskin = S.TRskin;
    source.type = 'layout';
    source.file = cacheFile;
    if isfield(layout, 't1File') && ~isempty(layout.t1File)
        source.label = getFileStem(layout.t1File);
    else
        source.label = getFileStem(cacheFile);
    end
end

function value = firstStruct(S)
    names = fieldnames(S);
    for i = 1:numel(names)
        if isstruct(S.(names{i}))
            value = S.(names{i});
            return;
        end
    end
    error('acsSelectEarExclusionSpheres:NoStructInMat', ...
        'MAT file does not contain a layout or skin mesh cache.');
end

function proposal = proposeEarSpheres(V, opts)
    V = double(V);
    bounds.min = min(V, [], 1);
    bounds.max = max(V, [], 1);
    range = bounds.max - bounds.min;
    yProbe = bounds.min(2) + opts.caudalFraction * range(2);
    zProbe = bounds.min(3) + opts.heightFraction * range(3);
    radius = 0.5 * opts.diameterFraction * range(1);
    yzBand = opts.yzBandFraction * max(range(2:3));

    yzDist = hypot(V(:, 2) - yProbe, V(:, 3) - zProbe);
    candidate = yzDist <= yzBand;
    if nnz(candidate) < 10
        [~, order] = sort(yzDist, 'ascend');
        candidate = false(size(yzDist));
        candidate(order(1:min(numel(order), max(10, round(0.02 * numel(order)))))) = true;
    end

    candidateRows = find(candidate);
    [~, leftLocal] = min(V(candidateRows, 1));
    [~, rightLocal] = max(V(candidateRows, 1));

    centers = [V(candidateRows(leftLocal), :); V(candidateRows(rightLocal), :)];
    radii = repmat(radius, 2, 1);

    proposal = struct();
    proposal.createdOn = char(datetime('now'));
    proposal.method = 'caudalHeightExtremeLR';
    proposal.sideNames = {'left'; 'right'};
    proposal.centers = centers;
    proposal.radii = radii;
    proposal.bounds = bounds;
    proposal.probePoint = [mean(bounds.min(1) + bounds.max(1)) yProbe zProbe];
    proposal.yProbe = yProbe;
    proposal.zProbe = zProbe;
    proposal.yzBandMM = yzBand;
    proposal.diameterFraction = opts.diameterFraction;
    proposal.caudalFraction = opts.caudalFraction;
    proposal.heightFraction = opts.heightFraction;
end

function proposal = ensurePaintedExclusionProposal(proposal, nVertices, opts)
    if ~opts.enablePaintedExclusions
        proposal.paintedExclusionMask = false(nVertices, 1);
        return;
    end
    if ~isfield(proposal, 'paintedExclusionMask') || ...
            numel(proposal.paintedExclusionMask) ~= nVertices
        proposal.paintedExclusionMask = false(nVertices, 1);
    else
        proposal.paintedExclusionMask = logical(proposal.paintedExclusionMask(:));
    end
end

function proposal = copySavedPaintedExclusions(proposal, existing, V, opts)
    nVertices = size(V, 1);
    proposal = ensurePaintedExclusionProposal(proposal, nVertices, opts);
    if ~opts.enablePaintedExclusions
        return;
    end
    rows = [];
    paintedMm = savedPaintedCoordinates(existing);
    if ~isempty(paintedMm)
        rows = nearestMeshRows(V, paintedMm);
    elseif isfield(existing, 'customExclusionVertexInd') && ...
            ~isempty(existing.customExclusionVertexInd)
        rows = double(existing.customExclusionVertexInd(:));
    elseif isfield(existing, 'paintedExclusionVertex') && ...
            ~isempty(existing.paintedExclusionVertex)
        rows = double(existing.paintedExclusionVertex(:));
    elseif isfield(existing, 'proposal') && isstruct(existing.proposal) && ...
            isfield(existing.proposal, 'paintedExclusionMask') && ...
            numel(existing.proposal.paintedExclusionMask) == nVertices
        proposal.paintedExclusionMask = logical(existing.proposal.paintedExclusionMask(:));
        return;
    end
    rows = rows(isfinite(rows) & rows >= 1 & rows <= nVertices);
    rows = unique(round(rows));
    proposal.paintedExclusionMask(:) = false;
    proposal.paintedExclusionMask(rows) = true;
end

function P = savedPaintedCoordinates(existing)
    P = zeros(0, 3);
    if isfield(existing, 'customExclusionCoordinatesMm') && ...
            ~isempty(existing.customExclusionCoordinatesMm)
        P = double(existing.customExclusionCoordinatesMm);
    elseif isfield(existing, 'paintedExclusionCoordinatesMm') && ...
            ~isempty(existing.paintedExclusionCoordinatesMm)
        P = double(existing.paintedExclusionCoordinatesMm);
    end
    if size(P, 2) == 3
        P = P(all(isfinite(P), 2), :);
    else
        P = zeros(0, 3);
    end
end

function rows = nearestMeshRows(V, P)
    rows = zeros(size(P, 1), 1);
    for i = 1:size(P, 1)
        d2 = sum((V - P(i, :)) .^ 2, 2);
        [~, rows(i)] = min(d2);
    end
    rows = unique(rows(:));
end

function labels = modePopupLabels(opts)
    labels = {'left ear', 'right ear'};
    if opts.enablePaintedExclusions
        labels{end + 1} = 'painted exclusion';
    end
end

function [proposal, accepted, fig] = selectEarSpheresGui(TRskin, proposal, opts)
    V = double(TRskin.Points);
    F = double(TRskin.ConnectivityList);
    displayMesh = decimateMeshForDisplay(F, V, opts.displayMaxFaces);
    activeSide = 1;
    activeTool = 1;
    accepted = false;
    dragStart = [];
    paintDrag = false;
    paintMode = 'add';
    proposal = ensurePaintedExclusionProposal(proposal, size(V, 1), opts);
    paintedRows = find(logical(proposal.paintedExclusionMask(:)));
    if isempty(paintedRows)
        paintBrushCenter = mean(V, 1);
    else
        paintBrushCenter = mean(V(paintedRows, :), 1);
    end
    paintBrushRadius = opts.paintBrushRadiusMm;
    isWaiting = false;

    fig = figure( ...
        'Name', 'Select ear exclusion spheres', ...
        'NumberTitle', 'off', ...
        'Color', 'w', ...
        'CloseRequestFcn', @onCloseRequest);
    ax = axes('Parent', fig, 'Position', [0.03 0.08 0.70 0.86]);
    hold(ax, 'on');
    patch(ax, ...
        'Faces', displayMesh.faces, ...
        'Vertices', displayMesh.vertices, ...
        'FaceColor', [0.86 0.89 0.94], ...
        'EdgeColor', 'none', ...
        'FaceAlpha', 0.82);
    overlayRows = sampleRows(size(V, 1), opts.vertexOverlayMaxPoints);
    overlayVertices = V(overlayRows, :);
    legalVertexHandle = gobjects(1);
    excludedVertexHandle = gobjects(1);
    if opts.showVertexOverlay
        legalVertexHandle = scatter3(ax, nan, nan, nan, 8, ...
            [0.45 0.85 0.42], 'filled', ...
            'MarkerFaceAlpha', 0.35, 'MarkerEdgeAlpha', 0.35);
        excludedVertexHandle = scatter3(ax, nan, nan, nan, 16, ...
            [0.78 0.05 0.58], 'filled', ...
            'MarkerFaceAlpha', 0.90, 'MarkerEdgeAlpha', 0.90);
    end
    paintedVertexHandle = scatter3(ax, nan, nan, nan, 22, ...
        [0.95 0.10 0.10], 'filled', ...
        'MarkerFaceAlpha', 0.90, 'MarkerEdgeAlpha', 0.90, ...
        'MarkerEdgeColor', [0.15 0.02 0.02], 'LineWidth', 0.6);
    paintBrushHandle = scatter3(ax, nan, nan, nan, 10, ...
        [1.00 0.30 0.85], 'filled', ...
        'MarkerFaceAlpha', 0.35, 'MarkerEdgeAlpha', 0.35);
    sphereHandles = gobjects(2, 1);
    centerHandles = gobjects(2, 1);
    textHandles = gobjects(2, 1);
    strapPreviewHandles = gobjects(0);
    colors = [0.95 0.45 0.05; 0.05 0.35 0.95];
    [sx, sy, sz] = sphere(32);
    for i = 1:2
        sphereHandles(i) = surf(ax, sx, sy, sz, ...
            'FaceColor', colors(i, :), ...
            'FaceAlpha', 0.18, ...
            'EdgeColor', colors(i, :), ...
            'EdgeAlpha', 0.20);
        centerHandles(i) = scatter3(ax, nan, nan, nan, 90, colors(i, :), ...
            'filled', 'MarkerEdgeColor', 'k', 'LineWidth', 1.0);
        textHandles(i) = text(ax, nan, nan, nan, '', ...
            'FontWeight', 'bold', 'Color', colors(i, :));
    end
    axis(ax, 'vis3d');
    axis(ax, 'equal');
    axis(ax, 'off');
    view(ax, 3);
    camtarget(ax, mean(V, 1));
    cameraLight = camlight(ax, 'headlight');
    lighting(ax, 'gouraud');

    status = uicontrol(fig, ...
        'Style', 'text', ...
        'Units', 'normalized', ...
        'Position', [0.75 0.43 0.23 0.42], ...
        'BackgroundColor', 'w', ...
        'HorizontalAlignment', 'left', ...
        'FontSize', 9);
    sidePopup = uicontrol(fig, ...
        'Style', 'popupmenu', ...
        'String', modePopupLabels(opts), ...
        'Units', 'normalized', ...
        'Position', [0.76 0.34 0.21 0.05], ...
        'Value', activeTool, ...
        'Callback', @onSidePopup);
    uicontrol(fig, ...
        'Style', 'pushbutton', ...
        'String', 'Done', ...
        'Units', 'normalized', ...
        'Position', [0.76 0.19 0.21 0.07], ...
        'Callback', @onDone);
    uicontrol(fig, ...
        'Style', 'pushbutton', ...
        'String', 'Reset proposal', ...
        'Units', 'normalized', ...
        'Position', [0.76 0.10 0.21 0.06], ...
        'Callback', @onReset);
    uicontrol(fig, ...
        'Style', 'pushbutton', ...
        'String', 'Cancel', ...
        'Units', 'normalized', ...
        'Position', [0.76 0.03 0.21 0.05], ...
        'Callback', @onCancel);

    originalProposal = proposal;
    updateGraphics();
    if opts.verbose
        fprintf('\nEar exclusion sphere controls:\n');
        fprintf('  Shift-click scalp: move active ear sphere center near the clicked point\n');
        if opts.enablePaintedExclusions
            fprintf('  F: painted exclusion mode; Shift-drag paints, Ctrl/Alt+Shift erases\n');
            fprintf('  C in painted mode: clear painted exclusions\n');
        end
        fprintf('  arrow keys: nudge active center in X/Y; U/D: nudge in Z\n');
        fprintf('  I/O or mouse wheel: shrink/grow active sphere or paint brush radius\n');
        fprintf('  L/R/F: select left/right ear sphere or painted exclusion; X/Y/Z: canonical views\n');
        fprintf('  light green vertices: currently legal; magenta vertices: sphere excluded; red vertices: painted excluded\n');
        fprintf('  purple chain: conservative chin-strap placement keepout preview\n');
        fprintf('  drag: rotate view\n');
    end

    set(fig, ...
        'WindowButtonDownFcn', @onMouseDown, ...
        'WindowButtonUpFcn', @onMouseUp, ...
        'WindowScrollWheelFcn', @onScroll, ...
        'WindowKeyPressFcn', @onKeyPress);
    isWaiting = true;
    uiwait(fig);
    isWaiting = false;

    function onSidePopup(~, ~)
        activeTool = get(sidePopup, 'Value');
        activeSide = min(activeTool, 2);
        updateGraphics();
    end

    function onMouseDown(~, ~)
        clickedAxes = ancestor(hittest(fig), 'axes');
        if isempty(clickedAxes) || clickedAxes ~= ax
            return;
        end
        modifiers = get(fig, 'CurrentModifier');
        if hasAnyModifier(modifiers, {'shift'})
            if isPaintToolActive()
                paintDrag = true;
                if hasAnyModifier(modifiers, {'control', 'alt'})
                    paintMode = 'remove';
                else
                    paintMode = 'add';
                end
                paintAtClick();
                set(fig, 'WindowButtonMotionFcn', @onPaintDrag);
            else
                setActiveCenterFromClick();
            end
            return;
        end
        dragStart = get(fig, 'CurrentPoint');
        set(fig, 'WindowButtonMotionFcn', @onDrag);
    end

    function setActiveCenterFromClick()
        [rayOrigin, rayDirection] = clickRay(ax);
        proposal.centers(activeSide, :) = visibleMeshPointFromRay( ...
            F, V, rayOrigin, rayDirection);
        updateGraphics();
    end

    function onDrag(~, ~)
        pointer = get(fig, 'CurrentPoint');
        delta = pointer - dragStart;
        dragStart = pointer;
        camorbit(ax, -0.35 * delta(1), -0.35 * delta(2), 'camera');
        camlight(cameraLight, 'headlight');
        drawnow limitrate;
    end

    function onMouseUp(~, ~)
        dragStart = [];
        paintDrag = false;
        set(fig, 'WindowButtonMotionFcn', '');
    end

    function onScroll(~, event)
        if isPaintToolActive()
            paintBrushRadius = max(0.5, ...
                paintBrushRadius - event.VerticalScrollCount * opts.radiusStepMM);
        else
            proposal.radii(activeSide) = max(1, ...
                proposal.radii(activeSide) - event.VerticalScrollCount * opts.radiusStepMM);
        end
        updateGraphics();
    end

    function onKeyPress(~, event)
        switch lower(event.Key)
            case 'l'
                activeTool = 1;
                activeSide = 1;
                set(sidePopup, 'Value', activeTool);
            case 'r'
                activeTool = 2;
                activeSide = 2;
                set(sidePopup, 'Value', activeTool);
            case 'f'
                if opts.enablePaintedExclusions
                    activeTool = 3;
                    set(sidePopup, 'Value', activeTool);
                end
            case 'leftarrow'
                nudgeActiveCenter([-opts.nudgeStepMM 0 0]);
            case 'rightarrow'
                nudgeActiveCenter([opts.nudgeStepMM 0 0]);
            case 'uparrow'
                nudgeActiveCenter([0 opts.nudgeStepMM 0]);
            case 'downarrow'
                nudgeActiveCenter([0 -opts.nudgeStepMM 0]);
            case 'u'
                nudgeActiveCenter([0 0 opts.nudgeStepMM]);
            case 'd'
                nudgeActiveCenter([0 0 -opts.nudgeStepMM]);
            case {'i', 'hyphen', 'subtract'}
                if isPaintToolActive()
                    paintBrushRadius = max(0.5, paintBrushRadius - opts.radiusStepMM);
                else
                    proposal.radii(activeSide) = max(1, proposal.radii(activeSide) - opts.radiusStepMM);
                end
            case {'o', 'equal', 'add'}
                if isPaintToolActive()
                    paintBrushRadius = paintBrushRadius + opts.radiusStepMM;
                else
                    proposal.radii(activeSide) = proposal.radii(activeSide) + opts.radiusStepMM;
                end
            case 'c'
                if isPaintToolActive()
                    proposal.paintedExclusionMask(:) = false;
                end
            case 'x'
                setCanonicalView([1 0 0], [0 0 1]);
            case 'y'
                setCanonicalView([0 1 0], [0 0 1]);
            case 'z'
                setCanonicalView([0 0 1], [0 1 0]);
        end
        updateGraphics();
    end

    function nudgeActiveCenter(deltaMm)
        if isPaintToolActive()
            paintBrushCenter = paintBrushCenter + deltaMm;
        else
            proposal.centers(activeSide, :) = proposal.centers(activeSide, :) + deltaMm;
        end
    end

    function tf = isPaintToolActive()
        tf = opts.enablePaintedExclusions && activeTool == 3;
    end

    function onPaintDrag(~, ~)
        if ~paintDrag
            return;
        end
        paintAtClick();
    end

    function paintAtClick()
        [rayOrigin, rayDirection] = clickRay(ax);
        paintBrushCenter = visibleMeshPointFromRay(F, V, rayOrigin, rayDirection);
        rows = brushRows();
        if strcmpi(paintMode, 'remove')
            proposal.paintedExclusionMask(rows) = false;
        else
            proposal.paintedExclusionMask(rows) = true;
        end
        updateGraphics();
    end

    function rows = brushRows()
        d2 = sum(bsxfun(@minus, V, paintBrushCenter) .^ 2, 2);
        rows = find(d2 <= paintBrushRadius .^ 2);
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

    function onReset(~, ~)
        proposal = originalProposal;
        proposal = ensurePaintedExclusionProposal(proposal, size(V, 1), opts);
        activeTool = 1;
        activeSide = 1;
        set(sidePopup, 'Value', activeTool);
        updateGraphics();
    end

    function onDone(~, ~)
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
        if opts.showVertexOverlay && all(isgraphics([legalVertexHandle excludedVertexHandle]))
            [~, ~, overlaySphereExcluded] = exclusionSphereMasks(overlayVertices, ...
                proposal.centers, proposal.radii);
            overlayPainted = proposal.paintedExclusionMask(overlayRows);
            overlayExcluded = overlaySphereExcluded | overlayPainted(:);
            setScatterPoints(legalVertexHandle, overlayVertices(~overlayExcluded, :));
            setScatterPoints(excludedVertexHandle, overlayVertices(overlaySphereExcluded, :));
        end
        [leftMask, rightMask, combinedMask] = exclusionSphereMasks(V, ...
            proposal.centers, proposal.radii);
        paintedMask = logical(proposal.paintedExclusionMask(:));
        setScatterPoints(paintedVertexHandle, V(paintedMask, :));
        if isPaintToolActive()
            setScatterPoints(paintBrushHandle, V(brushRows(), :));
        else
            setScatterPoints(paintBrushHandle, zeros(0, 3));
        end
        updateStrapPreview();
        for j = 1:2
            c = proposal.centers(j, :);
            r = proposal.radii(j);
            sphereIsActive = ~isPaintToolActive() && j == activeSide;
            set(sphereHandles(j), ...
                'XData', c(1) + r * sx, ...
                'YData', c(2) + r * sy, ...
                'ZData', c(3) + r * sz, ...
                'LineWidth', 0.8 + 1.2 * sphereIsActive);
            set(centerHandles(j), ...
                'XData', c(1), ...
                'YData', c(2), ...
                'ZData', c(3), ...
                'SizeData', 90 + 50 * sphereIsActive);
            set(textHandles(j), ...
                'Position', c + [r 0 0], ...
                'String', sprintf('%s r=%.1f', proposal.sideNames{j}, r));
        end
        set(status, 'String', sprintf([ ...
            'Active: %s\n\n' ...
            'Left center\n  [% .1f % .1f % .1f]\n  radius %.1f mm\n\n' ...
            'Right center\n  [% .1f % .1f % .1f]\n  radius %.1f mm\n\n' ...
            'Excluded vertices\n  left %d, right %d, either %d / %d\n\n' ...
            'Painted exclusion\n  %d vertices\n  brush %.1f mm\n\n' ...
            'Purple chain: strap keepout preview\n\n' ...
            'Shift-click/drag: set/paint\n' ...
            'Arrows/U/D: nudge\n' ...
            'I/O/wheel: radius'], ...
            activeToolName(), ...
            proposal.centers(1, 1), proposal.centers(1, 2), proposal.centers(1, 3), proposal.radii(1), ...
            proposal.centers(2, 1), proposal.centers(2, 2), proposal.centers(2, 3), proposal.radii(2), ...
            nnz(leftMask), nnz(rightMask), nnz(combinedMask), size(V, 1), ...
            nnz(paintedMask), paintBrushRadius));
        drawnow limitrate;
    end

    function name = activeToolName()
        if isPaintToolActive()
            name = 'painted exclusion';
        else
            name = proposal.sideNames{activeSide};
        end
    end

    function updateStrapPreview()
        if ~isempty(strapPreviewHandles)
            delete(strapPreviewHandles(isgraphics(strapPreviewHandles)));
            strapPreviewHandles = gobjects(0);
        end
        if ~opts.showStrapPreview
            return;
        end
        strapPreview = strapPreviewFromProposal(proposal, opts);
        if isempty(strapPreview.centersMm)
            return;
        end
        previewColor = [0.50 0.00 0.70];
        centers = double(strapPreview.centersMm);
        strapPreviewHandles(end + 1, 1) = scatter3(ax, ...
            centers(:, 1), centers(:, 2), centers(:, 3), 28, previewColor, ...
            'filled', 'MarkerFaceAlpha', 0.42, 'MarkerEdgeAlpha', 0.42);
        anchors = double(strapPreview.anchorCentersMm);
        if ~isempty(anchors)
            strapPreviewHandles(end + 1, 1) = scatter3(ax, ...
                anchors(:, 1), anchors(:, 2), anchors(:, 3), 80, previewColor, ...
                'd', 'filled', 'MarkerEdgeColor', 'k', 'LineWidth', 0.8);
        end
        for side = [-1 1]
            rows = side * centers(:, 1) >= 0;
            if nnz(rows) < 2
                continue;
            end
            [~, order] = sort(side * centers(rows, 1), 'ascend');
            sideCenters = centers(rows, :);
            sideCenters = sideCenters(order, :);
            strapPreviewHandles(end + 1, 1) = plot3(ax, ...
                sideCenters(:, 1), sideCenters(:, 2), sideCenters(:, 3), ...
                '-', 'Color', previewColor, 'LineWidth', 2.0);
        end
        textPos = mean(centers, 1);
        if all(isfinite(textPos))
            strapPreviewHandles(end + 1, 1) = text(ax, ...
                textPos(1), textPos(2), textPos(3) + strapPreview.radiusMm(1), ...
                'strap preview', 'Color', previewColor, ...
                'FontWeight', 'bold', 'HorizontalAlignment', 'center');
        end
    end
end

function displayMesh = decimateMeshForDisplay(F, V, maxFaces)
    if size(F, 1) <= maxFaces
        displayMesh = struct('faces', F, 'vertices', V);
        return;
    end
    [faces, vertices] = reducepatch(F, V, maxFaces);
    displayMesh = struct('faces', faces, 'vertices', vertices);
end

function strapPreview = strapPreviewFromProposal(proposal, opts)
    earExclusions = struct( ...
        'exclusionCenters', double(proposal.centers), ...
        'exclusionRadiusMM', double(proposal.radii(:)));
    args = { ...
        'mode', 'always', ...
        'zBedMm', opts.zBedMm, ...
        'strapRostralOffsetMm', opts.strapRostralOffsetMm, ...
        'strapWidthMm', opts.strapWidthMm, ...
        'holderOutsideDiaMm', opts.holderOutsideDiaMm, ...
        'strapMarginMm', opts.strapMarginMm, ...
        'strapLateralLengthMm', opts.strapLateralLengthMm, ...
        'strapSampleSpacingMm', opts.strapSampleSpacingMm, ...
        'verbose', false};
    if ~isempty(opts.strapExclusionRadiusMm)
        args = [args, {'strapExclusionRadiusMm', opts.strapExclusionRadiusMm}]; %#ok<AGROW>
    end
    [~, strapPreview] = acsAddStrapExclusionsToTargetOptions(struct(), ...
        earExclusions, args{:});
    if isfield(strapPreview, 'options')
        strapPreview = rmfield(strapPreview, 'options');
    end
end

function out = buildOutput(proposal, source, opts, fig, TRskin)
    out = struct();
    V = [];
    paintedMask = logical(proposal.paintedExclusionMask(:));
    paintedRows = find(paintedMask);
    if nargin >= 5 && ~isempty(TRskin)
        V = double(TRskin.Points);
    end
    out.createdOn = char(datetime('now'));
    out.source = source;
    out.method = proposal.method;
    out.sideNames = proposal.sideNames;
    out.leftCenterMm = proposal.centers(1, :);
    out.rightCenterMm = proposal.centers(2, :);
    out.leftRadiusMm = proposal.radii(1);
    out.rightRadiusMm = proposal.radii(2);
    out.exclusionCenters = proposal.centers;
    out.exclusionRadiusMM = proposal.radii(:);
    out.paintedExclusionVertex = paintedRows(:);
    out.customExclusionVertexInd = paintedRows(:);
    if ~isempty(V)
        out.paintedExclusionCoordinatesMm = V(paintedRows, :);
        out.customExclusionCoordinatesMm = out.paintedExclusionCoordinatesMm;
    else
        out.paintedExclusionCoordinatesMm = zeros(0, 3);
        out.customExclusionCoordinatesMm = zeros(0, 3);
    end
    out.targetOptions = struct( ...
        'earLeftLine', [], ...
        'earRightLine', [], ...
        'exclusionCenters', out.exclusionCenters, ...
        'exclusionRadiusMM', out.exclusionRadiusMM, ...
        'customExclusionVertexInd', out.customExclusionVertexInd);
    if opts.showStrapPreview
        out.strapPreview = strapPreviewFromProposal(proposal, opts);
    else
        out.strapPreview = struct( ...
            'source', 'none', ...
            'centersMm', zeros(0, 3), ...
            'radiusMm', zeros(0, 1), ...
            'anchorCentersMm', zeros(0, 3));
    end
    if nargin >= 5 && ~isempty(TRskin)
        [leftMask, rightMask, sphereCombinedMask] = exclusionSphereMasks( ...
            double(TRskin.Points), proposal.centers, proposal.radii);
        combinedMask = sphereCombinedMask | paintedMask;
        out.vertexExclusionSummary = struct( ...
            'nVertices', size(TRskin.Points, 1), ...
            'leftExcluded', nnz(leftMask), ...
            'rightExcluded', nnz(rightMask), ...
            'sphereExcluded', nnz(sphereCombinedMask), ...
            'paintedExcluded', nnz(paintedMask), ...
            'combinedExcluded', nnz(combinedMask), ...
            'combinedFraction', nnz(combinedMask) / max(1, size(TRskin.Points, 1)));
    end
    out.proposal = proposal;
    out.options = opts;
    if ~isempty(fig) && isgraphics(fig)
        out.figure = fig;
    end
end

function tf = savedEarExclusionsMatchSource(fileName, source)
    tf = false;
    try
        existing = loadExisting(fileName);
    catch
        return;
    end
    if ~isfield(existing, 'source') || ~isstruct(existing.source) || ...
            ~isfield(existing.source, 'meshFingerprint')
        return;
    end
    tf = meshFingerprintsMatch(existing.source.meshFingerprint, ...
        source.meshFingerprint);
end

function fingerprint = meshFingerprint(TRskin)
    V = double(TRskin.Points);
    F = double(TRskin.ConnectivityList);
    fingerprint = struct();
    fingerprint.nPoints = size(V, 1);
    fingerprint.nFaces = size(F, 1);
    fingerprint.boundsMin = min(V, [], 1);
    fingerprint.boundsMax = max(V, [], 1);
    fingerprint.centroid = mean(V, 1);
    fingerprint.pointSum = sum(V, 1);
    fingerprint.pointSquaredSum = sum(V .^ 2, 1);
    fingerprint.faceSum = sum(F, 1);
    fingerprint.faceSquaredSum = sum(F .^ 2, 1);
end

function tf = meshFingerprintsMatch(a, b)
    tf = false;
    required = {'nPoints', 'nFaces', 'boundsMin', 'boundsMax', ...
        'centroid', 'pointSum', 'pointSquaredSum', 'faceSum', ...
        'faceSquaredSum'};
    for i = 1:numel(required)
        if ~isfield(a, required{i}) || ~isfield(b, required{i})
            return;
        end
    end
    if double(a.nPoints) ~= double(b.nPoints) || ...
            double(a.nFaces) ~= double(b.nFaces)
        return;
    end
    tol = 1e-6;
    tf = numericFieldMatches(a, b, 'boundsMin', tol) && ...
        numericFieldMatches(a, b, 'boundsMax', tol) && ...
        numericFieldMatches(a, b, 'centroid', tol) && ...
        numericFieldMatches(a, b, 'pointSum', tol) && ...
        numericFieldMatches(a, b, 'pointSquaredSum', tol) && ...
        numericFieldMatches(a, b, 'faceSum', tol) && ...
        numericFieldMatches(a, b, 'faceSquaredSum', tol);
end

function tf = numericFieldMatches(a, b, fieldName, tol)
    va = double(a.(fieldName));
    vb = double(b.(fieldName));
    tf = isequal(size(va), size(vb)) && ...
        all(abs(va(:) - vb(:)) <= tol);
end

function out = loadExisting(fileName)
    S = load(fileName, 'out');
    if ~isfield(S, 'out') || ~isstruct(S.out)
        error('acsSelectEarExclusionSpheres:BadOutputFile', ...
            'Saved ear exclusion file does not contain out: %s', fileName);
    end
    out = S.out;
end

function saveOutput(fileName, out)
    out = stripFigure(out);
    save(fileName, 'out');
end

function out = stripFigure(out)
    if isfield(out, 'figure')
        out = rmfield(out, 'figure');
    end
end

function fileName = defaultOutputFile(source)
    if ~isempty(source.file)
        [folder, stem] = fileparts(source.file);
        if endsWith(lower(stem), '_skinmesh')
            stem = stem(1:end - numel('_skinMesh'));
        end
        fileName = fullfile(folder, [stem '_earExclusions.mat']);
    else
        fileName = fullfile(pwd, 'earExclusions.mat');
    end
end

function saveQcFigure(fig, qcFile, TRskin, proposal)
    createdFigure = false;
    if isempty(fig) || ~isgraphics(fig)
        fig = figure('Visible', 'off', 'Color', 'w');
        createdFigure = true;
        ax = axes(fig);
        patch(ax, 'Faces', TRskin.ConnectivityList, 'Vertices', TRskin.Points, ...
            'FaceColor', [0.86 0.89 0.94], 'EdgeColor', 'none', ...
            'FaceAlpha', 0.82);
        hold(ax, 'on');
        V = double(TRskin.Points);
        [~, ~, excludedMask] = exclusionSphereMasks(V, ...
            proposal.centers, proposal.radii);
        paintedMask = false(size(V, 1), 1);
        if isfield(proposal, 'paintedExclusionMask') && ...
                numel(proposal.paintedExclusionMask) == size(V, 1)
            paintedMask = logical(proposal.paintedExclusionMask(:));
        end
        allExcludedMask = excludedMask | paintedMask;
        scatter3(ax, V(~allExcludedMask, 1), V(~allExcludedMask, 2), ...
            V(~allExcludedMask, 3), 5, [0.45 0.85 0.42], 'filled', ...
            'MarkerFaceAlpha', 0.22, 'MarkerEdgeAlpha', 0.22);
        scatter3(ax, V(excludedMask, 1), V(excludedMask, 2), ...
            V(excludedMask, 3), 9, [0.78 0.05 0.58], 'filled', ...
            'MarkerFaceAlpha', 0.85, 'MarkerEdgeAlpha', 0.85);
        scatter3(ax, V(paintedMask, 1), V(paintedMask, 2), ...
            V(paintedMask, 3), 12, [0.95 0.10 0.10], 'filled', ...
            'MarkerFaceAlpha', 0.90, 'MarkerEdgeAlpha', 0.90);
        if any(allExcludedMask)
            title(ax, sprintf('Ear/painted exclusions: %d vertices', ...
                nnz(allExcludedMask)), 'Interpreter', 'none');
        end
        [sx, sy, sz] = sphere(24);
        colors = [0.95 0.45 0.05; 0.05 0.35 0.95];
        for i = 1:2
            c = proposal.centers(i, :);
            r = proposal.radii(i);
            surf(ax, c(1) + r * sx, c(2) + r * sy, c(3) + r * sz, ...
                'FaceColor', colors(i, :), 'FaceAlpha', 0.18, ...
                'EdgeColor', colors(i, :), 'EdgeAlpha', 0.20);
        end
        axis(ax, 'equal');
        axis(ax, 'off');
        camlight(ax, 'headlight');
        lighting(ax, 'gouraud');
    end
    try
        exportgraphics(fig, qcFile, 'Resolution', 150);
    catch
        saveas(fig, qcFile);
    end
    if createdFigure && isgraphics(fig)
        delete(fig);
    end
end

function rows = sampleRows(nRows, maxRows)
    if nRows <= maxRows
        rows = (1:nRows).';
        return;
    end
    rows = unique(round(linspace(1, nRows, maxRows))).';
end

function [leftMask, rightMask, combinedMask] = exclusionSphereMasks(V, centers, radii)
    V = double(V);
    centers = double(centers);
    radii = double(radii(:));
    leftMask = false(size(V, 1), 1);
    rightMask = false(size(V, 1), 1);
    masks = {leftMask, rightMask};
    for i = 1:min(2, size(centers, 1))
        if i > numel(radii) || ~isfinite(radii(i)) || radii(i) <= 0 || ...
                any(~isfinite(centers(i, :)))
            continue;
        end
        delta = bsxfun(@minus, V, centers(i, :));
        masks{i} = sum(delta .^ 2, 2) <= radii(i) .^ 2;
    end
    leftMask = masks{1};
    rightMask = masks{2};
    combinedMask = leftMask | rightMask;
end

function setScatterPoints(h, points)
    if isempty(points)
        set(h, 'XData', nan, 'YData', nan, 'ZData', nan);
        return;
    end
    set(h, ...
        'XData', points(:, 1), ...
        'YData', points(:, 2), ...
        'ZData', points(:, 3));
end

function json = jsonReady(out)
    json = out;
    if isfield(json, 'figure')
        json = rmfield(json, 'figure');
    end
    if isfield(json, 'options')
        json.options = rmfieldIfPresent(json.options, {'showFigures', 'saveFigures'});
    end
end

function S = rmfieldIfPresent(S, fields)
    for i = 1:numel(fields)
        if isfield(S, fields{i})
            S = rmfield(S, fields{i});
        end
    end
end

function writeJsonReport(fileName, value)
    try
        fid = fopen(fileName, 'w');
        if fid == -1
            return;
        end
        cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
        fprintf(fid, '%s', jsonencode(value, 'PrettyPrint', true));
    catch
    end
end

function [origin, direction] = clickRay(ax)
    points = get(ax, 'CurrentPoint');
    origin = double(points(1, :));
    direction = double(points(2, :) - points(1, :));
    direction = direction / max(norm(direction), eps);
end

function point = closestVertexToRay(vertices, origin, direction)
    offsets = vertices - origin;
    rayT = offsets * direction(:);
    rayT(rayT < 0) = 0;
    closestOnRay = origin + rayT .* direction;
    [~, idx] = min(sum((vertices - closestOnRay) .^ 2, 2));
    point = vertices(idx, :);
end

function point = visibleMeshPointFromRay(F, V, origin, direction)
    point = firstMeshRayIntersection(F, V, origin, direction);
    if isempty(point)
        point = closestVertexToRay(V, origin, direction);
    end
end

function point = firstMeshRayIntersection(F, V, rayOrigin, rayDirection)
    point = [];
    if isempty(F) || isempty(V)
        return;
    end

    F = double(F);
    V = double(V);
    rayOrigin = double(rayOrigin(:))';
    rayDirection = double(rayDirection(:))';
    rayDirection = rayDirection ./ max(norm(rayDirection), eps);

    v0 = V(F(:, 1), :);
    v1 = V(F(:, 2), :);
    v2 = V(F(:, 3), :);
    e1 = v1 - v0;
    e2 = v2 - v0;
    pvec = cross(repmat(rayDirection, size(e2, 1), 1), e2, 2);
    detVal = sum(e1 .* pvec, 2);
    detTol = 1e-10;
    nonparallel = abs(detVal) > detTol;
    if ~any(nonparallel)
        return;
    end

    invDet = zeros(size(detVal));
    invDet(nonparallel) = 1 ./ detVal(nonparallel);
    tvec = bsxfun(@minus, rayOrigin, v0);
    u = sum(tvec .* pvec, 2) .* invDet;
    qvec = cross(tvec, e1, 2);
    v = sum(repmat(rayDirection, size(qvec, 1), 1) .* qvec, 2) .* invDet;
    t = sum(e2 .* qvec, 2) .* invDet;

    epsBary = 1e-8;
    hit = nonparallel & t > detTol & ...
        u >= -epsBary & v >= -epsBary & (u + v) <= 1 + epsBary;
    if ~any(hit)
        return;
    end
    tHit = t;
    tHit(~hit) = Inf;
    [~, faceIdx] = min(tHit);
    point = rayOrigin + t(faceIdx) .* rayDirection;
end

function tf = hasAnyModifier(activeModifiers, choices)
    if isempty(activeModifiers)
        tf = false;
    elseif ischar(activeModifiers)
        tf = any(strcmpi(activeModifiers, choices));
    else
        tf = any(ismember(lower(activeModifiers), lower(choices)));
    end
end

function ensureDir(pathIn)
    if ~isempty(pathIn) && exist(pathIn, 'dir') ~= 7
        mkdir(pathIn);
    end
end

function fileName = replaceMatExtension(fileName, newExtension)
    [folder, stem] = fileparts(fileName);
    fileName = fullfile(folder, [stem newExtension]);
end

function stem = getFileStem(fileName)
    [~, stem, ext] = fileparts(fileName);
    if strcmpi(ext, '.gz')
        [~, stem] = fileparts(stem);
    end
end

function logMsg(opts, varargin)
    if opts.verbose
        fprintf([varargin{1} '\n'], varargin{2:end});
    end
end

function p = expandUserPath(p)
    if isempty(p)
        return;
    end
    p = char(p);
    if startsWith(p, '~')
        homeDir = getenv('HOME');
        if isempty(homeDir)
            homeDir = getenv('USERPROFILE');
        end
        if numel(p) == 1
            p = homeDir;
        elseif p(2) == filesep || p(2) == '/' || p(2) == '\'
            p = fullfile(homeDir, p(3:end));
        end
    end
end
