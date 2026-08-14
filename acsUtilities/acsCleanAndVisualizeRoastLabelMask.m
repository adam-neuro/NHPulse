function out = acsCleanAndVisualizeRoastLabelMask(maskFile, varargin)
% ACSCLEANANDVISUALIZEROASTLABELMASK Clean and QC a ROAST hard-label mask.
%
% out = acsCleanAndVisualizeRoastLabelMask(maskFile) reads a ROAST label
% volume, removes disconnected skin-label islands, writes a derived mask,
% and optionally shows/saves a compact three-plane QC figure.
%
% Mesh-first workflows can pass surfaceOverlayFile to draw the warped scalp
% mesh as slice contours over the still-voxelized ROAST labels. This is a
% visualization overlay only; it does not revoxelize or edit the label mask.

    if nargin < 1 || isempty(maskFile)
        error('acsCleanAndVisualizeRoastLabelMask:MissingMask', ...
            'Provide a ROAST hard-label mask file.');
    end

    opts = parseInputs(varargin{:});
    addLocalDependencies();

    maskFile = expandUserPath(char(maskFile));
    requireFile(maskFile, 'ROAST hard-label mask');
    if isempty(opts.outputFile)
        opts.outputFile = defaultOutputFile(maskFile, opts.outputTag);
    end

    if exist(opts.outputFile, 'file') == 2 && ~opts.force
        out = loadExistingReport(opts.outputFile);
        if isempty(out)
            out = struct('maskFile', opts.outputFile, ...
                'inputMaskFile', maskFile, 'reusedExisting', true);
        end
        logMsg(opts, 'Reusing cleaned/QC ROAST label mask: %s', opts.outputFile);
        return;
    end

    Vmask = spm_vol(maskFile);
    Vmask = Vmask(1);
    labels = uint8(round(spm_read_vols(Vmask)));
    labelsIn = labels;
    [labels, skinCleanup] = cleanupSkinLabelComponents(labels, opts);

    writeLabelVolume(opts.outputFile, Vmask, labels, ...
        'ACS cleaned ROAST hard-label mask');

    qcFile = '';
    fig = [];
    if opts.showFigures || opts.saveFigures
        figVisible = 'off';
        if opts.showFigures
            figVisible = 'on';
        end
        fig = makeQcFigure(opts.t1File, Vmask, labelsIn, labels, ...
            skinCleanup, opts, figVisible);
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

    out = struct();
    out.createdOn = char(datetime('now'));
    out.type = 'cleanedRoastLabelMask';
    out.inputMaskFile = maskFile;
    out.maskFile = opts.outputFile;
    out.outputFile = opts.outputFile;
    out.t1File = opts.t1File;
    out.imageSize = Vmask.dim(1:3);
    out.skinCleanup = skinCleanup;
    out.voxelCountsBefore = labelVoxelCounts(labelsIn);
    out.voxelCountsAfter = labelVoxelCounts(labels);
    out.qcFile = qcFile;
    out.options = opts;
    out.figure = fig;

    outForSave = out;
    if isfield(outForSave, 'figure')
        outForSave = rmfield(outForSave, 'figure');
    end
    reportFile = reportFileForMask(opts.outputFile);
    save(reportFile, 'outForSave', '-v7.3');
    writeJsonReport(strrep(reportFile, '.mat', '.json'), outForSave);

    if opts.verbose
        fprintf('\nROAST label mask QC/cleanup\n');
        fprintf('  input: %s\n', maskFile);
        fprintf('  output: %s\n', opts.outputFile);
        fprintf('  skin cleanup: %s, components %d -> %d, removed %d voxels\n', ...
            skinCleanup.mode, skinCleanup.componentCountBefore, ...
            skinCleanup.keptComponentCount, skinCleanup.removedSkinVoxels);
    end
end

function opts = parseInputs(varargin)
    p = inputParser;
    p.FunctionName = 'acsCleanAndVisualizeRoastLabelMask';
    addParameter(p, 't1File', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'outputFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'outputTag', 'skinClean', @(x) ischar(x) || isstring(x));
    addParameter(p, 'force', false, @isBoolLike);
    addParameter(p, 'cleanupSkinComponents', true, @isBoolLike);
    addParameter(p, 'skinCleanupMode', 'largest', @(x) ischar(x) || isstring(x));
    addParameter(p, 'minSkinComponentVoxels', 1000, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0);
    addParameter(p, 'overlayAlpha', 0.45, ...
        @(x) isnumeric(x) && isscalar(x) && x >= 0 && x <= 1);
    addParameter(p, 'surfaceOverlayFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'surfaceOverlayStage', 'stableHead', ...
        @(x) ischar(x) || isstring(x));
    addParameter(p, 'surfaceOverlayColor', [1 1 1], @isRgbTriplet);
    addParameter(p, 'surfaceOverlayLineWidth', 1.25, @isPositiveScalar);
    addParameter(p, 'surfaceOverlaySliceToleranceVoxels', 0.75, ...
        @isPositiveScalar);
    addParameter(p, 'enableSlicePaging', false, @isBoolLike);
    addParameter(p, 'showFigures', false, @isBoolLike);
    addParameter(p, 'saveFigures', false, @isBoolLike);
    addParameter(p, 'verbose', true, @isBoolLike);
    parse(p, varargin{:});

    opts = p.Results;
    opts.t1File = expandUserPath(char(opts.t1File));
    opts.outputFile = expandUserPath(char(opts.outputFile));
    opts.outputTag = safeName(char(opts.outputTag));
    opts.force = logical(opts.force);
    opts.cleanupSkinComponents = logical(opts.cleanupSkinComponents);
    opts.skinCleanupMode = normalizeSkinCleanupMode(opts.skinCleanupMode);
    opts.minSkinComponentVoxels = round(double(opts.minSkinComponentVoxels));
    opts.overlayAlpha = double(opts.overlayAlpha);
    opts.surfaceOverlayFile = expandUserPath(char(opts.surfaceOverlayFile));
    opts.surfaceOverlayStage = normalizeSurfaceOverlayStage( ...
        opts.surfaceOverlayStage);
    opts.surfaceOverlayColor = double(opts.surfaceOverlayColor(:))';
    opts.surfaceOverlayLineWidth = double(opts.surfaceOverlayLineWidth);
    opts.surfaceOverlaySliceToleranceVoxels = double( ...
        opts.surfaceOverlaySliceToleranceVoxels);
    opts.enableSlicePaging = logical(opts.enableSlicePaging);
    opts.showFigures = logical(opts.showFigures);
    opts.saveFigures = logical(opts.saveFigures);
    opts.verbose = logical(opts.verbose);
end

function tf = isBoolLike(x)
    tf = (islogical(x) || isnumeric(x)) && isscalar(x);
end

function tf = isRgbTriplet(x)
    tf = isnumeric(x) && numel(x) == 3 && all(isfinite(x(:))) && ...
        all(x(:) >= 0) && all(x(:) <= 1);
end

function tf = isPositiveScalar(x)
    tf = isnumeric(x) && isscalar(x) && isfinite(x) && x > 0;
end

function addLocalDependencies()
    repoRoot = fileparts(fileparts(mfilename('fullpath')));
    addpath(repoRoot);
    addpath(fullfile(repoRoot, 'acsUtilities'));
    spmDir = fullfile(repoRoot, 'lib', 'spm12');
    if exist(spmDir, 'dir') == 7
        addpath(spmDir);
    end
end

function mode = normalizeSkinCleanupMode(mode)
    mode = lower(strtrim(char(mode)));
    switch regexprep(mode, '[\s_\-]+', '')
        case {'largest', 'largestcomponent', 'main'}
            mode = 'largest';
        case {'minsize', 'minimumsize', 'threshold'}
            mode = 'minSize';
        otherwise
            error('acsCleanAndVisualizeRoastLabelMask:BadSkinCleanupMode', ...
                'skinCleanupMode must be ''largest'' or ''minSize''.');
    end
end

function stage = normalizeSurfaceOverlayStage(stage)
    stage = lower(strtrim(char(stage)));
    stage = regexprep(stage, '[\s_\-]+', '');
    switch stage
        case {'stablehead', 'fullhead', 'precrop'}
            stage = 'stableHead';
        case {'fiducialhead', 'fiducial', 'printfullhead'}
            stage = 'fiducialHead';
        case {'skin', 'trskin', 'cap', 'print'}
            stage = 'skin';
        otherwise
            error('acsCleanAndVisualizeRoastLabelMask:BadSurfaceOverlayStage', ...
                ['surfaceOverlayStage must be ''stableHead'', ', ...
                 '''fiducialHead'', or ''skin''.']);
    end
end

function [labelsOut, info] = cleanupSkinLabelComponents(labelsIn, opts)
    labelsOut = labelsIn;
    skin = labelsIn == 5;
    info = struct('enabled', opts.cleanupSkinComponents, ...
        'mode', opts.skinCleanupMode, ...
        'componentCountBefore', 0, ...
        'keptComponentCount', 0, ...
        'removedComponentCount', 0, ...
        'largestComponentVoxels', 0, ...
        'removedSkinVoxels', 0, ...
        'reason', '');
    if ~opts.cleanupSkinComponents
        info.reason = 'cleanupSkinComponents=false';
        return;
    end
    if nnz(skin) == 0
        info.reason = 'no skin voxels';
        return;
    end
    if exist('bwconncomp', 'file') ~= 2
        warning('acsCleanAndVisualizeRoastLabelMask:MissingBwconncomp', ...
            'bwconncomp is unavailable; disconnected skin cleanup was skipped.');
        info.reason = 'bwconncomp unavailable';
        return;
    end

    CC = bwconncomp(skin, 26);
    sizes = cellfun(@numel, CC.PixelIdxList);
    info.componentCountBefore = CC.NumObjects;
    if isempty(sizes)
        info.reason = 'no connected components';
        return;
    end
    [largestSize, largestIdx] = max(sizes);
    info.largestComponentVoxels = largestSize;
    switch opts.skinCleanupMode
        case 'largest'
            keepComponents = largestIdx;
        case 'minSize'
            keepComponents = find(sizes >= opts.minSkinComponentVoxels);
            if isempty(keepComponents)
                keepComponents = largestIdx;
            end
        otherwise
            keepComponents = largestIdx;
    end

    keep = false(size(skin));
    for i = keepComponents(:)'
        keep(CC.PixelIdxList{i}) = true;
    end
    remove = skin & ~keep;
    labelsOut(remove) = uint8(0);

    info.keptComponentCount = numel(keepComponents);
    info.removedComponentCount = CC.NumObjects - numel(keepComponents);
    info.removedSkinVoxels = nnz(remove);
    if info.removedSkinVoxels == 0
        info.reason = 'no disconnected skin components removed';
    else
        info.reason = 'removed disconnected skin components';
    end
end

function fig = makeQcFigure(t1File, Vref, labelsBefore, labelsAfter, ...
        skinCleanup, opts, figVisible)
    if ~isempty(t1File) && exist(t1File, 'file') == 2
        Vt1 = spm_vol(t1File);
        Vt1 = Vt1(1);
        t1 = single(spm_read_vols(Vt1));
    else
        t1 = single(labelsAfter);
    end
    dims = size(labelsAfter);
    sliceInd = chooseSliceIndices(labelsBefore, labelsAfter);
    fig = figure('Name', 'ROAST active label mask QC', 'Color', 'w', ...
        'Visible', figVisible, 'Units', 'pixels', 'Position', [80 80 1500 820]);
    addFigureHeader(fig, sprintf(['ROAST active label mask QC | skin ', ...
        'components %d -> %d | removed %d voxels'], ...
        skinCleanup.componentCountBefore, skinCleanup.keptComponentCount, ...
        skinCleanup.removedSkinVoxels));

    styles = labelStyles();
    planeLabels = {'Sagittal', 'Coronal', 'Axial'};
    axPos = threePanelPositions(0.23, 0.66);
    clim = robustClim(t1);
    removedSkin = labelsBefore == 5 & labelsAfter ~= 5;
    surfaceOverlay = readSurfaceOverlayAsVoxel1(Vref, opts);
    axesHandles = gobjects(3, 1);
    for dimToFix = 1:3
        ax = axes(fig, 'Position', axPos(dimToFix, :)); %#ok<LAXES>
        axesHandles(dimToFix) = ax;
        idx = max(1, min(dims(dimToFix), sliceInd(dimToFix)));
        drawSlicePanel(ax, t1, labelsAfter, removedSkin, surfaceOverlay, ...
            dims, styles, clim, planeLabels, dimToFix, idx, opts);
        if opts.enableSlicePaging && strcmpi(figVisible, 'on')
            addSlicePager(fig, axPos(dimToFix, :), dimToFix, idx, dims, ...
                @(newIdx) drawSlicePanel(ax, t1, labelsAfter, ...
                removedSkin, surfaceOverlay, dims, styles, clim, ...
                planeLabels, dimToFix, newIdx, opts));
        end
    end

    legendAx = axes(fig, 'Position', [0.05 0.04 0.90 0.12]); %#ok<LAXES>
    drawLegendPanel(legendAx, styles, surfaceOverlay);
    outInfo = struct('axes', axesHandles, ...
        'initialSliceIndices', sliceInd, ...
        'surfaceOverlay', surfaceOverlay);
    setappdata(fig, 'acsCleanAndVisualizeRoastLabelMask', outInfo);
end

function sliceInd = chooseSliceIndices(labelsBefore, labelsAfter)
    changed = labelsBefore ~= labelsAfter;
    if any(changed(:))
        [i, j, k] = ind2sub(size(changed), find(changed));
        sliceInd = round(median([i j k], 1));
    else
        skin = labelsAfter == 5;
        if any(skin(:))
            [i, j, k] = ind2sub(size(skin), find(skin));
            sliceInd = round(median([i j k], 1));
        else
            sliceInd = max(1, round(size(labelsAfter) ./ 2));
        end
    end
end

function styles = labelStyles()
    styles = struct( ...
        'labelId', {1, 2, 3, 4, 5, 6, 7}, ...
        'label', {'1 white', '2 gray', '3 CSF', '4 bone', '5 skin', '6 air', '7 titanium'}, ...
        'color', {[0 0.85 1], [1 0.2 0.1], [0.1 0.25 1], ...
        [1 0.85 0], [0 0.8 0.25], [1 0 1], [0.8 0 0]});
end

function rgb = labelSliceRgb(labelSlice, styles)
    rgb = zeros([size(labelSlice) 3], 'single');
    for k = 1:numel(styles)
        style = styles(k);
        mask = labelSlice == style.labelId;
        for c = 1:3
            channel = rgb(:, :, c);
            channel(mask) = style.color(c);
            rgb(:, :, c) = channel;
        end
    end
end

function rgb = addRemovedSkinToRgb(rgb, removedSlice)
    if ~any(removedSlice(:))
        return;
    end
    color = single([1.0 0.45 0.0]);
    for c = 1:3
        channel = rgb(:, :, c);
        channel(removedSlice) = color(c);
        rgb(:, :, c) = channel;
    end
end

function out = rot90Rgb(in)
    out = zeros([size(in, 2) size(in, 1) size(in, 3)], 'like', in);
    for c = 1:size(in, 3)
        out(:, :, c) = rot90(in(:, :, c));
    end
end

function S = rawSlice(vol, dimToFix, idx)
    switch dimToFix
        case 1
            S = squeeze(vol(idx, :, :));
        case 2
            S = squeeze(vol(:, idx, :));
        case 3
            S = squeeze(vol(:, :, idx));
        otherwise
            error('acsCleanAndVisualizeRoastLabelMask:BadSliceDimension', ...
                'Unsupported slice dimension %d.', dimToFix);
    end
end

function drawSlicePanel(ax, t1, labelsAfter, removedSkin, surfaceOverlay, ...
        dims, styles, clim, planeLabels, dimToFix, idx, opts)
    cla(ax);
    idx = max(1, min(dims(dimToFix), round(double(idx))));
    t1Slice = rawSlice(t1, dimToFix, idx);
    labelSlice = rawSlice(labelsAfter, dimToFix, idx);
    removedSlice = rawSlice(removedSkin, dimToFix, idx);
    imagesc(ax, rot90(t1Slice));
    axis(ax, 'image');
    axis(ax, 'off');
    colormap(ax, gray);
    caxis(ax, clim);
    hold(ax, 'on');
    rgb = labelSliceRgb(labelSlice, styles);
    rgb = addRemovedSkinToRgb(rgb, removedSlice);
    overlay = image(ax, rot90Rgb(rgb));
    showMask = (labelSlice > 0 & labelSlice ~= 6) | removedSlice;
    set(overlay, 'AlphaData', rot90(double(showMask) .* opts.overlayAlpha));
    drawSurfaceSliceContour(ax, surfaceOverlay, dimToFix, idx, dims, opts);
    title(ax, sprintf('%s %d', planeLabels{dimToFix}, idx), ...
        'Interpreter', 'none', 'FontSize', 11, 'FontWeight', 'bold');
end

function addSlicePager(fig, axPos, dimToFix, idx, dims, drawFcn)
    planeLabels = {'Sagittal', 'Coronal', 'Axial'};
    maxIdx = dims(dimToFix);
    if maxIdx <= 1
        return;
    end
    labelPos = [axPos(1) + 0.03, axPos(2) - 0.030, ...
        max(0.05, axPos(3) - 0.06), 0.020];
    sliderPos = [axPos(1) + 0.03, axPos(2) - 0.058, ...
        max(0.05, axPos(3) - 0.06), 0.024];
    txt = uicontrol(fig, 'Style', 'text', 'Units', 'normalized', ...
        'Position', labelPos, 'BackgroundColor', 'w', ...
        'HorizontalAlignment', 'center', 'FontSize', 8, ...
        'String', sprintf('%s slice %d', planeLabels{dimToFix}, idx));
    stepSmall = 1 / max(1, maxIdx - 1);
    stepLarge = min(1, 10 / max(1, maxIdx - 1));
    slider = uicontrol(fig, 'Style', 'slider', 'Units', 'normalized', ...
        'Position', sliderPos, 'Min', 1, 'Max', maxIdx, ...
        'Value', idx, 'SliderStep', [stepSmall stepLarge]);
    slider.Callback = @(src, ~) updateSliceFromSlider( ...
        src, txt, planeLabels{dimToFix}, drawFcn);
end

function updateSliceFromSlider(src, txt, planeLabel, drawFcn)
    idx = round(double(src.Value));
    src.Value = idx;
    txt.String = sprintf('%s slice %d', planeLabel, idx);
    drawFcn(idx);
end

function surfaceOverlay = readSurfaceOverlayAsVoxel1(Vref, opts)
    surfaceOverlay = struct( ...
        'enabled', false, ...
        'file', opts.surfaceOverlayFile, ...
        'stage', opts.surfaceOverlayStage, ...
        'sourceVariable', '', ...
        'sourceFrame', '', ...
        'label', 'warped scalp mesh', ...
        'TR', [], ...
        'color', opts.surfaceOverlayColor, ...
        'lineWidth', opts.surfaceOverlayLineWidth);
    if isempty(opts.surfaceOverlayFile)
        return;
    end
    if exist(opts.surfaceOverlayFile, 'file') ~= 2
        warning('acsCleanAndVisualizeRoastLabelMask:MissingSurfaceOverlay', ...
            'surfaceOverlayFile not found; skipping overlay: %s', ...
            opts.surfaceOverlayFile);
        return;
    end
    S = load(opts.surfaceOverlayFile);
    if ~isfield(S, 'meta')
        warning('acsCleanAndVisualizeRoastLabelMask:MissingSurfaceMeta', ...
            ['surfaceOverlayFile does not contain skin-cache metadata; ', ...
             'skipping overlay: %s'], opts.surfaceOverlayFile);
        return;
    end
    [TR, frame, variableName] = selectSurfaceOverlayTriangulation( ...
        S, opts.surfaceOverlayStage);
    pointsVoxel1 = scalpPointsToVoxel1(double(TR.Points), frame, S.meta, Vref);
    surfaceOverlay.enabled = true;
    surfaceOverlay.sourceVariable = variableName;
    surfaceOverlay.sourceFrame = frame;
    surfaceOverlay.TR = triangulation(double(TR.ConnectivityList), pointsVoxel1);
end

function [TR, frame, variableName] = selectSurfaceOverlayTriangulation(S, stage)
    switch stage
        case 'stableHead'
            candidates = {'TRstableHead', 'meta.stableHead.TR', ...
                'TRfiducialHead', 'TRskin'};
        case 'fiducialHead'
            candidates = {'TRfiducialHead', 'meta.fiducialHead.TR', ...
                'TRstableHead', 'TRskin'};
        case 'skin'
            candidates = {'TRskin', 'TRfiducialHead', 'TRstableHead'};
        otherwise
            candidates = {'TRstableHead', 'TRskin'};
    end
    TR = [];
    variableName = '';
    for i = 1:numel(candidates)
        [ok, value] = getNestedField(S, candidates{i});
        if ok && ~isempty(value)
            TR = ensureTri(value);
            variableName = candidates{i};
            break;
        end
    end
    if isempty(TR)
        error('acsCleanAndVisualizeRoastLabelMask:MissingSurfaceMesh', ...
            'surfaceOverlayFile does not contain a usable skin mesh.');
    end
    frame = frameForSurfaceVariable(S, variableName);
end

function drawSurfaceSliceContour(ax, surfaceOverlay, dimToFix, idx, dims, opts)
    if ~isstruct(surfaceOverlay) || ~surfaceOverlay.enabled || ...
            isempty(surfaceOverlay.TR)
        return;
    end
    V = double(surfaceOverlay.TR.Points);
    F = double(surfaceOverlay.TR.ConnectivityList);
    [x, y] = sliceSegmentsDisplayCoordinates(V, F, dimToFix, idx, ...
        dims, opts.surfaceOverlaySliceToleranceVoxels);
    if isempty(x)
        return;
    end
    line(ax, x, y, 'Color', surfaceOverlay.color, ...
        'LineWidth', surfaceOverlay.lineWidth, 'HitTest', 'off', ...
        'PickableParts', 'none');
end

function [x, y] = sliceSegmentsDisplayCoordinates(V, F, dimToFix, idx, dims, tol)
    planeValue = double(idx);
    edgePairs = [1 2; 2 3; 3 1];
    segA = zeros(0, 3);
    segB = zeros(0, 3);
    for fi = 1:size(F, 1)
        tri = V(F(fi, :), :);
        coord = tri(:, dimToFix) - planeValue;
        Q = zeros(0, 3);
        for ei = 1:3
            a = edgePairs(ei, 1);
            b = edgePairs(ei, 2);
            ca = coord(a);
            cb = coord(b);
            pa = tri(a, :);
            pb = tri(b, :);
            if abs(ca) <= tol && abs(cb) <= tol
                Q = [Q; pa; pb]; %#ok<AGROW>
            elseif abs(ca) <= tol
                Q = [Q; pa]; %#ok<AGROW>
            elseif abs(cb) <= tol
                Q = [Q; pb]; %#ok<AGROW>
            elseif ca * cb < 0
                t = ca / (ca - cb);
                Q = [Q; pa + t .* (pb - pa)]; %#ok<AGROW>
            end
        end
        Q = uniqueRoundedRows(Q, 1e-4);
        if size(Q, 1) >= 2
            if size(Q, 1) > 2
                D = squareformDistanceLocal(Q);
                [~, ind] = max(D(:));
                [r, c] = ind2sub(size(D), ind);
                q1 = Q(r, :);
                q2 = Q(c, :);
            else
                q1 = Q(1, :);
                q2 = Q(2, :);
            end
            segA(end + 1, :) = q1; %#ok<AGROW>
            segB(end + 1, :) = q2; %#ok<AGROW>
        end
    end
    if isempty(segA)
        x = [];
        y = [];
        return;
    end
    [x1, y1] = voxelPointsToDisplay(segA, dimToFix, dims);
    [x2, y2] = voxelPointsToDisplay(segB, dimToFix, dims);
    x = reshape([x1(:) x2(:) nan(size(x1(:)))]', [], 1);
    y = reshape([y1(:) y2(:) nan(size(y1(:)))]', [], 1);
end

function [x, y] = voxelPointsToDisplay(P, dimToFix, dims)
    switch dimToFix
        case 1
            x = P(:, 2);
            y = dims(3) - P(:, 3) + 1;
        case 2
            x = P(:, 1);
            y = dims(3) - P(:, 3) + 1;
        case 3
            x = P(:, 1);
            y = dims(2) - P(:, 2) + 1;
        otherwise
            x = [];
            y = [];
    end
end

function Q = uniqueRoundedRows(Q, tol)
    if isempty(Q)
        return;
    end
    key = round(Q ./ tol) .* tol;
    [~, ia] = unique(key, 'rows', 'stable');
    Q = Q(ia, :);
end

function D = squareformDistanceLocal(P)
    n = size(P, 1);
    D = zeros(n, n);
    for i = 1:n
        d = bsxfun(@minus, P, P(i, :));
        D(i, :) = sqrt(sum(d .^ 2, 2));
    end
end

function [ok, value] = getNestedField(S, pathText)
    parts = strsplit(char(pathText), '.');
    value = S;
    ok = true;
    for i = 1:numel(parts)
        if isstruct(value) && isfield(value, parts{i})
            value = value.(parts{i});
        else
            ok = false;
            value = [];
            return;
        end
    end
end

function frame = frameForSurfaceVariable(S, variableName)
    switch variableName
        case {'TRstableHead', 'meta.stableHead.TR'}
            frame = 'capMakerPreCropWorldMm';
        case {'TRfiducialHead', 'meta.fiducialHead.TR'}
            frame = 'capMakerPrintMm';
        otherwise
            frame = 'capMakerPrintMm';
    end
    if isfield(S, 'meta') && isstruct(S.meta)
        switch variableName
            case {'TRstableHead', 'meta.stableHead.TR'}
                frame = nestedChar(S.meta, {'stableHead', 'coordinateFrame'}, frame);
            case {'TRfiducialHead', 'meta.fiducialHead.TR'}
                frame = nestedChar(S.meta, {'fiducialHead', 'coordinateFrame'}, frame);
        end
    end
end

function value = nestedChar(S, pathParts, defaultValue)
    value = defaultValue;
    cursor = S;
    for i = 1:numel(pathParts)
        if isstruct(cursor) && isfield(cursor, pathParts{i})
            cursor = cursor.(pathParts{i});
        else
            return;
        end
    end
    if ~isempty(cursor)
        value = char(cursor);
    end
end

function pointsVoxel1 = scalpPointsToVoxel1(points, frame, meta, Vref)
    switch lower(char(frame))
        case lower('capMakerPreCropWorldMm')
            pointsVoxel1 = stableWorldMmToT1ArrayVoxel1(points, Vref);
        case lower('capMakerPrintMm')
            pointsVoxel1 = printMmToT1Voxel1(points, meta, Vref);
        otherwise
            error('acsCleanAndVisualizeRoastLabelMask:UnsupportedOverlayFrame', ...
                'Unsupported scalp overlay coordinate frame "%s".', frame);
    end
end

function vox1 = printMmToT1Voxel1(pointsPrintMm, meta, Vref)
    requirePrintTransforms(meta);
    finalWorldMm = applyAffineToPoints(meta.print.T_print2world, pointsPrintMm);
    stableWorldMm = (double(meta.align.R) \ finalWorldMm')';
    vox1 = stableWorldMmToT1ArrayVoxel1(stableWorldMm, Vref);
end

function vox1 = stableWorldMmToT1ArrayVoxel1(pointsStableMm, Vref)
    voxelSize = voxelSizesFromMat(Vref.mat);
    vox1 = bsxfun(@rdivide, double(pointsStableMm), voxelSize) + 1;
end

function voxelSize = voxelSizesFromMat(M)
    voxelSize = sqrt(sum(double(M(1:3, 1:3)) .^ 2, 1));
    voxelSize(~isfinite(voxelSize) | voxelSize <= 0) = 1;
end

function requirePrintTransforms(meta)
    ok = isstruct(meta) && isfield(meta, 'print') && isstruct(meta.print) && ...
        isfield(meta.print, 'T_print2world') && ...
        isequal(size(meta.print.T_print2world), [4 4]) && ...
        isfield(meta, 'align') && isstruct(meta.align) && ...
        isfield(meta.align, 'R') && isequal(size(meta.align.R), [3 3]);
    if ~ok
        error('acsCleanAndVisualizeRoastLabelMask:BadSkinMeta', ...
            'Skin metadata lacks print.T_print2world or align.R.');
    end
end

function pointsOut = applyAffineToPoints(M, pointsIn)
    pointsHom = [double(pointsIn), ones(size(pointsIn, 1), 1)];
    pointsHom = (double(M) * pointsHom')';
    pointsOut = pointsHom(:, 1:3);
end

function TR = ensureTri(value)
    if isa(value, 'triangulation')
        TR = value;
    elseif isstruct(value) && isfield(value, 'ConnectivityList') && ...
            isfield(value, 'Points')
        TR = triangulation(double(value.ConnectivityList), double(value.Points));
    else
        error('acsCleanAndVisualizeRoastLabelMask:BadTriangulation', ...
            'Expected a triangulation or struct with ConnectivityList/Points.');
    end
end

function addFigureHeader(fig, headerText)
    annotation(fig, 'textbox', [0.04 0.935 0.92 0.05], ...
        'String', headerText, ...
        'Interpreter', 'none', ...
        'HorizontalAlignment', 'center', ...
        'VerticalAlignment', 'middle', ...
        'FontWeight', 'bold', ...
        'FontSize', 12, ...
        'EdgeColor', 'none');
end

function positions = threePanelPositions(y0, h)
    margin = 0.045;
    gap = 0.035;
    w = (1 - 2 * margin - 2 * gap) / 3;
    positions = zeros(3, 4);
    for i = 1:3
        x0 = margin + (i - 1) * (w + gap);
        positions(i, :) = [x0 y0 w h];
    end
end

function drawLegendPanel(ax, styles, surfaceOverlay)
    cla(ax);
    axis(ax, 'off');
    hold(ax, 'on');
    x = 0.02;
    y = 0.70;
    for i = 1:numel(styles)
        style = styles(i);
        if style.labelId == 6
            continue;
        end
        patch(ax, [x x + 0.03 x + 0.03 x], ...
            [y - 0.07 y - 0.07 y + 0.07 y + 0.07], ...
            style.color, 'EdgeColor', [0.2 0.2 0.2], 'LineWidth', 0.5);
        text(ax, x + 0.038, y, style.label, ...
            'Interpreter', 'none', 'VerticalAlignment', 'middle', 'FontSize', 10);
        x = x + 0.13;
    end
    patch(ax, [0.02 0.05 0.05 0.02], [0.14 0.14 0.28 0.28], ...
        [1.0 0.45 0.0], 'EdgeColor', [0.2 0.2 0.2], 'LineWidth', 0.5);
    text(ax, 0.058, 0.21, 'removed skin island(s)', ...
        'Interpreter', 'none', 'VerticalAlignment', 'middle', 'FontSize', 10);
    if isstruct(surfaceOverlay) && surfaceOverlay.enabled
        line(ax, [0.34 0.39], [0.21 0.21], ...
            'Color', surfaceOverlay.color, ...
            'LineWidth', max(1.5, surfaceOverlay.lineWidth));
        text(ax, 0.40, 0.21, surfaceOverlay.label, ...
            'Interpreter', 'none', 'VerticalAlignment', 'middle', ...
            'FontSize', 10);
    end
    xlim(ax, [0 1]);
    ylim(ax, [0 1]);
end

function clim = robustClim(V)
    vals = double(V(:));
    vals = vals(isfinite(vals));
    if isempty(vals)
        clim = [0 1];
        return;
    end
    if numel(vals) > 1000000
        vals = vals(round(linspace(1, numel(vals), 1000000)));
    end
    clim = prctile(vals(:), [1 99]);
    if clim(1) == clim(2)
        clim = [min(vals(:)) max(vals(:))];
    end
    if clim(1) == clim(2)
        clim = clim + [-1 1];
    end
end

function counts = labelVoxelCounts(labels)
    names = {'background', 'white', 'gray', 'csf', 'bone', 'skin', 'air', 'titanium'};
    maxLabel = max(double(labels(:)));
    counts = struct();
    for k = 0:max(maxLabel, numel(names) - 1)
        if k + 1 <= numel(names)
            field = names{k + 1};
        else
            field = sprintf('label%d', k);
        end
        counts.(field) = nnz(labels == k);
    end
end

function writeLabelVolume(fileName, Vref, labels, description)
    deleteDerivedNifti(fileName);
    Vout = Vref;
    Vout.fname = fileName;
    Vout.dim = size(labels);
    Vout.dt = [spm_type('uint8') spm_platform('bigend')];
    Vout.n = [1 1];
    Vout.private = [];
    Vout.pinfo = [1; 0; 0];
    Vout.descrip = description;
    ensureDir(fileparts(fileName));
    spm_write_vol(Vout, uint8(labels));
end

function fileName = defaultOutputFile(maskFile, outputTag)
    [folder, stem, ext] = fileparts(maskFile);
    if strcmpi(ext, '.gz')
        [~, stem, ext2] = fileparts(stem);
        ext = [ext2 ext];
    end
    fileName = fullfile(folder, [stem '_' outputTag ext]);
end

function fileName = reportFileForMask(maskFile)
    [folder, stem] = fileparts(maskFile);
    fileName = fullfile(folder, [stem '_report.mat']);
end

function out = loadExistingReport(maskFile)
    out = [];
    reportFile = reportFileForMask(maskFile);
    if exist(reportFile, 'file') ~= 2
        return;
    end
    S = load(reportFile);
    if isfield(S, 'outForSave') && isstruct(S.outForSave)
        out = S.outForSave;
    elseif isfield(S, 'out') && isstruct(S.out)
        out = S.out;
    end
end

function saveQcFigure(fig, fileName)
    try
        exportgraphics(fig, fileName, 'Resolution', 150);
    catch
        saveas(fig, fileName);
    end
end

function deleteDerivedNifti(fileName)
    if exist(fileName, 'file') == 2
        delete(fileName);
    end
    [folder, stem] = fileparts(fileName);
    matSidecar = fullfile(folder, [stem '.mat']);
    if exist(matSidecar, 'file') == 2
        delete(matSidecar);
    end
end

function ensureDir(folder)
    if ~isempty(folder) && exist(folder, 'dir') ~= 7
        mkdir(folder);
    end
end

function requireFile(fileName, label)
    if isempty(fileName) || exist(fileName, 'file') ~= 2
        error('acsCleanAndVisualizeRoastLabelMask:MissingFile', ...
            '%s not found: %s', label, fileName);
    end
end

function fileName = expandUserPath(fileName)
    fileName = char(fileName);
    if startsWith(fileName, '~')
        fileName = fullfile(char(java.lang.System.getProperty('user.home')), ...
            fileName(2:end));
    end
end

function name = getFileName(fileName)
    [~, name, ext] = fileparts(fileName);
    name = [name ext];
end

function stem = stripMatExtension(fileName)
    [~, stem] = fileparts(fileName);
end

function name = safeName(name)
    name = regexprep(char(name), '[^a-zA-Z0-9_]+', '_');
    name = regexprep(name, '_+', '_');
    name = regexprep(name, '^_|_$', '');
    if isempty(name)
        name = 'mask';
    end
end

function writeJsonReport(fileName, report)
    try
        fid = fopen(fileName, 'w');
        cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
        fprintf(fid, '%s', jsonencode(report, 'PrettyPrint', true));
    catch
    end
end

function logMsg(opts, varargin)
    if opts.verbose
        fprintf([varargin{1} '\n'], varargin{2:end});
    end
end
