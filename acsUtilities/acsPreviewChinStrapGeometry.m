function out = acsPreviewChinStrapGeometry(varargin)
% ACSPREVIEWCHINSTRAPGEOMETRY Preview/debug chin-strap voxel geometry only.
%
% out = acsPreviewChinStrapGeometry(...) voxelizes the same procedural strap
% occupancy used by acsBuildCapMakerManufacturingStl, without building the
% rest of the cap. Use this as a fast diagnostic loop for strap parameters.
%
% Name-value options:
%   anchorMm                 : cap-side anchor point in print mm [[0 0 12]]
%   outDir                   : outward direction in XY [[1 0 0]]
%   voxelSizeMm              : preview voxel size [0.5]
%   zBedMm                   : printer bed plane [0]
%   strapWidthMm             : strap width [10]
%   strapThickMm             : strap thickness [2.4]
%   strapBedClearanceMm      : low-strap underside above bed [0.2]
%   strapCorrAmpMm           : square-wave half-height [3]
%   strapCorrPitchMm         : requested square-wave pitch [8]
%   strapCorrStyle           : 'rectilinear' or 'swept' ['rectilinear']
%   strapCorrFitIntegerCycles: force whole cycles per section [true]
%   bedRunMm                 : bed-parallel section length [28]
%   rampRunMm                : ramp section length [14]
%   rampRiseMm               : ramp net rise [10]
%   ringOffsetMm             : ring/strap frame offset [43]
%   ringOuterDiaMm           : nominal ring outer diameter [20]
%   ringTubeDiaMm            : nominal ring tube diameter [3.5]
%   ringOverlapMm            : strap overlap into ring frame [5]
%   includeLoop              : include rectangular loop occupancy [true]
%   outputDir                : optional folder for STL/PNG ['']
%   previewTag               : output stem ['chinStrapPreview']
%   interactive              : open parameter-tuning GUI [true]
%   parameterFile            : MAT file written on Done ['']
%   saveStl                  : write strap-only STL [false]
%   showFigures              : show preview figure [true]
%   saveFigures              : save preview PNG [false]
%   returnOccupancy          : include occupancy grid in output [false]
%   verbose                  : print summary [true]

    opts = parseInputs(varargin{:});
    addLocalDependencies();
    if opts.interactive
        out = interactivePreview(opts);
        return;
    end

    params = strapParams(opts);
    frameOpts = strapFrameOptions(opts);
    extentPts = strapExtentPoints(opts.anchorMm, opts.outDir, params, frameOpts);
    pad = max(4 * opts.voxelSizeMm, opts.padMm);
    bbMin = min(extentPts, [], 1) - pad;
    bbMax = max(extentPts, [], 1) + pad;
    bbMin(3) = min(bbMin(3), opts.zBedMm);
    bbMax(3) = max(bbMax(3), opts.zBedMm + opts.voxelSizeMm);

    x = bbMin(1):opts.voxelSizeMm:bbMax(1);
    y = bbMin(2):opts.voxelSizeMm:bbMax(2);
    z = bbMin(3):opts.voxelSizeMm:bbMax(3);
    [X, Y, Z] = ndgrid(x, y, z);

    if opts.verbose
        fprintf('Previewing chin strap only.\n');
        fprintf('  style: %s, pitch %.3g mm, amp %.3g mm\n', ...
            opts.strapCorrStyle, opts.strapCorrPitchMm, opts.strapCorrAmpMm);
        fprintf('  voxel size: %.3g mm, grid: [%d %d %d]\n', ...
            opts.voxelSizeMm, numel(x), numel(y), numel(z));
    end

    occ = strapFn_world(X, Y, Z, opts.anchorMm, opts.outDir, params, frameOpts);
    occ = logical(occ) & Z >= opts.zBedMm;

    triOpts = struct( ...
        'clearShellXY', true, ...
        'clearShellZ', false, ...
        'keepLargest', false, ...
        'closeVox', 0, ...
        'cleanup', true, ...
        'allowPermute', false);
    [TR, occValidated] = triFromOccGrid(x, y, z, occ, 0.5, triOpts);

    components = componentSummary(occValidated);
    fig = [];
    if opts.showFigures || opts.saveFigures
        fig = makePreviewFigure(TR, x, y, z, occValidated, opts);
    end

    stlFile = '';
    pngFile = '';
    if opts.saveStl
        ensureOutputDir(opts.outputDir);
        stlFile = fullfile(opts.outputDir, [opts.previewTag '.stl']);
        stlwrite_boxsafe(TR, stlFile);
    end
    if opts.saveFigures && isgraphics(fig)
        ensureOutputDir(opts.outputDir);
        pngFile = fullfile(opts.outputDir, [opts.previewTag '_preview.png']);
        exportgraphics(fig, pngFile, 'Resolution', 200);
    end

    out = struct();
    out.createdOn = char(datetime('now'));
    out.anchorMm = opts.anchorMm;
    out.outDir = opts.outDir;
    out.params = params;
    out.frameOptions = frameOpts;
    out.voxelSizeMm = opts.voxelSizeMm;
    out.gridSize = [numel(x), numel(y), numel(z)];
    out.nOccupiedVoxels = nnz(occValidated);
    out.components = components;
    out.mesh = meshStats(TR);
    out.stlFile = stlFile;
    out.pngFile = pngFile;
    out.parameterFile = opts.parameterFile;
    out.manufacturingNameValuePairs = makeManufacturingNameValuePairs(opts);
    if opts.returnOccupancy
        out.occupancy = struct('x', x, 'y', y, 'z', z, 'occ', occValidated);
    end
    if isgraphics(fig)
        out.figure = fig;
    end

    if opts.verbose
        fprintf('  occupied voxels: %d\n', out.nOccupiedVoxels);
        fprintf('  components: %d\n', components.nComponents);
        fprintf('  mesh faces/vertices: %d / %d\n', ...
            out.mesh.nFaces, out.mesh.nVertices);
        if ~isempty(stlFile)
            fprintf('  STL: %s\n', stlFile);
        end
    end
end

function opts = parseInputs(varargin)
    p = inputParser;
    p.FunctionName = 'acsPreviewChinStrapGeometry';
    addParameter(p, 'anchorMm', [0 0 12], @isPoint3);
    addParameter(p, 'outDir', [1 0 0], @isPoint3);
    addParameter(p, 'voxelSizeMm', 0.5, @isPositiveScalar);
    addParameter(p, 'padMm', 3, @isNonnegativeScalar);
    addParameter(p, 'zBedMm', 0, @isFiniteScalar);
    addParameter(p, 'strapWidthMm', 10, @isPositiveScalar);
    addParameter(p, 'strapThickMm', 2.4, @isPositiveScalar);
    addParameter(p, 'strapBedClearanceMm', 0.2, @isNonnegativeScalar);
    addParameter(p, 'strapCorrAmpMm', 3, @isNonnegativeScalar);
    addParameter(p, 'strapCorrPitchMm', 8, @isPositiveScalar);
    addParameter(p, 'strapCorrStyle', 'rectilinear', @(x) ischar(x) || isstring(x));
    addParameter(p, 'strapCorrFitIntegerCycles', true, @isBoolLike);
    addParameter(p, 'bedRunMm', 28, @isNonnegativeScalar);
    addParameter(p, 'rampRunMm', 14, @isNonnegativeScalar);
    addParameter(p, 'rampRiseMm', 10, @isFiniteScalar);
    addParameter(p, 'ringOffsetMm', 43, @isNonnegativeScalar);
    addParameter(p, 'ringOuterDiaMm', 20, @isPositiveScalar);
    addParameter(p, 'ringTubeDiaMm', 3.5, @isPositiveScalar);
    addParameter(p, 'ringOverlapMm', 5, @isFiniteScalar);
    addParameter(p, 'includeLoop', true, @isBoolLike);
    addParameter(p, 'loopOuterXMm', 12, @isPositiveScalar);
    addParameter(p, 'loopOuterYMm', 18, @isPositiveScalar);
    addParameter(p, 'loopFrameMm', 3.5, @isPositiveScalar);
    addParameter(p, 'outputDir', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'previewTag', 'chinStrapPreview', @(x) ischar(x) || isstring(x));
    addParameter(p, 'interactive', true, @isBoolLike);
    addParameter(p, 'parameterFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'saveStl', false, @isBoolLike);
    addParameter(p, 'showFigures', true, @isBoolLike);
    addParameter(p, 'saveFigures', false, @isBoolLike);
    addParameter(p, 'returnOccupancy', false, @isBoolLike);
    addParameter(p, 'verbose', true, @isBoolLike);
    parse(p, varargin{:});

    opts = p.Results;
    opts.anchorMm = double(opts.anchorMm(:).');
    opts.outDir = double(opts.outDir(:).');
    opts.voxelSizeMm = double(opts.voxelSizeMm);
    opts.padMm = double(opts.padMm);
    opts.zBedMm = double(opts.zBedMm);
    opts.strapWidthMm = double(opts.strapWidthMm);
    opts.strapThickMm = double(opts.strapThickMm);
    opts.strapBedClearanceMm = double(opts.strapBedClearanceMm);
    opts.strapCorrAmpMm = double(opts.strapCorrAmpMm);
    opts.strapCorrPitchMm = double(opts.strapCorrPitchMm);
    opts.strapCorrStyle = normalizeStrapCorrStyle(opts.strapCorrStyle);
    opts.strapCorrFitIntegerCycles = logical(opts.strapCorrFitIntegerCycles);
    opts.bedRunMm = double(opts.bedRunMm);
    opts.rampRunMm = double(opts.rampRunMm);
    opts.rampRiseMm = double(opts.rampRiseMm);
    opts.ringOffsetMm = double(opts.ringOffsetMm);
    opts.ringOuterDiaMm = double(opts.ringOuterDiaMm);
    opts.ringTubeDiaMm = double(opts.ringTubeDiaMm);
    opts.ringOverlapMm = double(opts.ringOverlapMm);
    opts.includeLoop = logical(opts.includeLoop);
    opts.loopOuterXMm = double(opts.loopOuterXMm);
    opts.loopOuterYMm = double(opts.loopOuterYMm);
    opts.loopFrameMm = double(opts.loopFrameMm);
    opts.outputDir = char(opts.outputDir);
    opts.previewTag = char(opts.previewTag);
    opts.interactive = logical(opts.interactive);
    opts.parameterFile = char(opts.parameterFile);
    opts.saveStl = logical(opts.saveStl);
    opts.showFigures = logical(opts.showFigures);
    opts.saveFigures = logical(opts.saveFigures);
    opts.returnOccupancy = logical(opts.returnOccupancy);
    opts.verbose = logical(opts.verbose);
end

function out = interactivePreview(opts)
    opts.showFigures = true;
    opts.verbose = false;
    state = struct();
    state.opts = opts;
    state.data = [];
    state.accepted = false;
    state.parameterFile = '';

    fig = figure('Name', 'Chin strap parameter tuner', ...
        'NumberTitle', 'off', ...
        'Color', 'w', ...
        'MenuBar', 'figure', ...
        'ToolBar', 'figure', ...
        'Position', [80 80 1320 760], ...
        'CloseRequestFcn', @onCancel);

    axSurface = axes('Parent', fig, 'Units', 'normalized', ...
        'Position', [0.04 0.52 0.27 0.40]);
    axVoxel = axes('Parent', fig, 'Units', 'normalized', ...
        'Position', [0.34 0.52 0.27 0.40]);
    axSlice = axes('Parent', fig, 'Units', 'normalized', ...
        'Position', [0.04 0.09 0.57 0.30]);

    controls = makeControls(fig);
    rotate3d(fig, 'on');
    updatePreview(false);
    uiwait(fig);

    if isgraphics(fig) && state.accepted
        state.opts.showFigures = true;
        state.opts.verbose = true;
        state.opts.parameterFile = state.parameterFile;
        out = buildOutputFromData(state.opts, state.data, fig);
    else
        out = struct('canceled', true);
    end

    function controls = makeControls(parent)
        controls = struct();
        x0 = 0.66;
        w = 0.30;
        y = 0.90;
        dy = 0.052;

        uicontrol(parent, 'Style', 'text', 'Units', 'normalized', ...
            'Position', [x0 y w 0.035], ...
            'String', 'Chin strap parameters', ...
            'FontWeight', 'bold', 'BackgroundColor', 'w', ...
            'HorizontalAlignment', 'left');
        y = y - dy;

        [controls.stylePopup, y] = popupControl(parent, x0, y, w, ...
            'style', {'rectilinear', 'swept'}, state.opts.strapCorrStyle, ...
            @onStyleChanged);
        [controls.fitCheck, y] = checkboxControl(parent, x0, y, w, ...
            'integer cycles', state.opts.strapCorrFitIntegerCycles, ...
            @onFitChanged);
        [controls.loopCheck, y] = checkboxControl(parent, x0, y, w, ...
            'include loop', state.opts.includeLoop, @onLoopChanged);

        specs = {
            'strapCorrAmpMm',      'amp',        0,    10;
            'strapCorrPitchMm',    'pitch',      2,    24;
            'strapWidthMm',        'width',      4,    24;
            'strapThickMm',        'thickness',  0.8,   8;
            'strapBedClearanceMm', 'bed clear',  0,     3;
            'bedRunMm',            'bed run',    0,    80;
            'rampRunMm',           'ramp run',   0,    50;
            'rampRiseMm',          'ramp rise', -10,   35;
            'ringOffsetMm',        'ring off',   0,    80;
            'voxelSizeMm',         'voxel',      0.25,  1.5};
        controls.numeric = struct();
        for i = 1:size(specs, 1)
            field = specs{i, 1};
            label = specs{i, 2};
            minVal = specs{i, 3};
            maxVal = specs{i, 4};
            [controls.numeric.(field), y] = numericControl(parent, x0, y, w, ...
                field, label, minVal, maxVal);
        end

        controls.status = uicontrol(parent, 'Style', 'text', ...
            'Units', 'normalized', ...
            'Position', [x0 0.19 w 0.12], ...
            'String', '', ...
            'BackgroundColor', 'w', ...
            'HorizontalAlignment', 'left');

        uicontrol(parent, 'Style', 'pushbutton', 'Units', 'normalized', ...
            'Position', [x0 0.13 0.09 0.045], ...
            'String', 'Update', ...
            'Callback', @(~, ~) updatePreview(true));
        uicontrol(parent, 'Style', 'pushbutton', 'Units', 'normalized', ...
            'Position', [x0 + 0.105 0.13 0.09 0.045], ...
            'String', 'Done', ...
            'Callback', @onDone);
        uicontrol(parent, 'Style', 'pushbutton', 'Units', 'normalized', ...
            'Position', [x0 + 0.210 0.13 0.09 0.045], ...
            'String', 'Cancel', ...
            'Callback', @onCancel);

        uicontrol(parent, 'Style', 'text', 'Units', 'normalized', ...
            'Position', [x0 0.05 w 0.06], ...
            'String', ['Surface and voxel-raster previews are regenerated ', ...
                       'from the same occupancy used by manufacturing.'], ...
            'BackgroundColor', 'w', ...
            'HorizontalAlignment', 'left');
    end

    function [h, yNext] = numericControl(parent, x0, y, w, field, label, minVal, maxVal)
        value = state.opts.(field);
        uicontrol(parent, 'Style', 'text', 'Units', 'normalized', ...
            'Position', [x0 y 0.085 0.028], ...
            'String', label, 'BackgroundColor', 'w', ...
            'HorizontalAlignment', 'left');
        slider = uicontrol(parent, 'Style', 'slider', 'Units', 'normalized', ...
            'Position', [x0 + 0.087 y 0.145 0.028], ...
            'Min', minVal, 'Max', maxVal, ...
            'Value', clamp(value, minVal, maxVal));
        edit = uicontrol(parent, 'Style', 'edit', 'Units', 'normalized', ...
            'Position', [x0 + 0.240 y 0.055 0.030], ...
            'String', sprintf('%.4g', value), ...
            'BackgroundColor', 'w');
        set(slider, 'Callback', @(src, ~) onSliderChanged(src, edit, field));
        set(edit, 'Callback', @(src, ~) onEditChanged(src, slider, field, minVal, maxVal));
        h = struct('slider', slider, 'edit', edit, ...
            'min', minVal, 'max', maxVal);
        yNext = y - 0.043;
    end

    function [h, yNext] = popupControl(parent, x0, y, w, label, values, current, cb)
        uicontrol(parent, 'Style', 'text', 'Units', 'normalized', ...
            'Position', [x0 y 0.085 0.030], 'String', label, ...
            'BackgroundColor', 'w', 'HorizontalAlignment', 'left');
        idx = find(strcmpi(values, current), 1);
        if isempty(idx), idx = 1; end
        h = uicontrol(parent, 'Style', 'popupmenu', 'Units', 'normalized', ...
            'Position', [x0 + 0.087 y 0.205 0.032], ...
            'String', values, 'Value', idx, 'Callback', cb);
        yNext = y - 0.042;
    end

    function [h, yNext] = checkboxControl(parent, x0, y, w, label, value, cb)
        h = uicontrol(parent, 'Style', 'checkbox', 'Units', 'normalized', ...
            'Position', [x0 y w 0.030], 'String', label, ...
            'Value', logical(value), 'BackgroundColor', 'w', ...
            'Callback', cb);
        yNext = y - 0.038;
    end

    function onSliderChanged(src, edit, field)
        value = get(src, 'Value');
        state.opts.(field) = value;
        set(edit, 'String', sprintf('%.4g', value));
        updatePreview(true);
    end

    function onEditChanged(src, slider, field, minVal, maxVal)
        value = str2double(get(src, 'String'));
        if ~isfinite(value)
            value = state.opts.(field);
        end
        state.opts.(field) = value;
        set(src, 'String', sprintf('%.4g', value));
        set(slider, 'Value', clamp(value, minVal, maxVal));
        updatePreview(true);
    end

    function onStyleChanged(src, ~)
        values = get(src, 'String');
        state.opts.strapCorrStyle = values{get(src, 'Value')};
        updatePreview(true);
    end

    function onFitChanged(src, ~)
        state.opts.strapCorrFitIntegerCycles = logical(get(src, 'Value'));
        updatePreview(true);
    end

    function onLoopChanged(src, ~)
        state.opts.includeLoop = logical(get(src, 'Value'));
        updatePreview(true);
    end

    function updatePreview(preserveCamera)
        surfCam = captureCamera(axSurface);
        voxCam = captureCamera(axVoxel);
        try
            data = renderStrapData(state.opts);
            state.data = data;
            drawSurfacePreview(axSurface, data, state.opts);
            drawVoxelPreview(axVoxel, data, state.opts);
            drawSlicePreview(axSlice, data, state.opts);
            if preserveCamera
                restoreCamera(axSurface, surfCam);
                restoreCamera(axVoxel, voxCam);
            end
            set(controls.status, 'String', sprintf([ ...
                'voxels: %d\ncomponents: %d\nfaces: %d\npitch eff: %s'], ...
                nnz(data.occ), data.components.nComponents, ...
                size(data.TR.ConnectivityList, 1), ...
                effectivePitchText(state.opts)));
        catch ME
            set(controls.status, 'String', sprintf('Preview error:\n%s', ME.message));
        end
        drawnow;
    end

    function onDone(~, ~)
        if isempty(state.data)
            state.data = renderStrapData(state.opts);
        end
        state.parameterFile = saveInteractiveParameters(state.opts, state.data);
        state.accepted = true;
        if isgraphics(fig)
            uiresume(fig);
        end
    end

    function onCancel(~, ~)
        state.accepted = false;
        if isgraphics(fig)
            uiresume(fig);
            delete(fig);
        end
    end
end

function data = renderStrapData(opts)
    params = strapParams(opts);
    frameOpts = strapFrameOptions(opts);
    extentPts = strapExtentPoints(opts.anchorMm, opts.outDir, params, frameOpts);
    pad = max(4 * opts.voxelSizeMm, opts.padMm);
    bbMin = min(extentPts, [], 1) - pad;
    bbMax = max(extentPts, [], 1) + pad;
    bbMin(3) = min(bbMin(3), opts.zBedMm);
    bbMax(3) = max(bbMax(3), opts.zBedMm + opts.voxelSizeMm);

    x = bbMin(1):opts.voxelSizeMm:bbMax(1);
    y = bbMin(2):opts.voxelSizeMm:bbMax(2);
    z = bbMin(3):opts.voxelSizeMm:bbMax(3);
    [X, Y, Z] = ndgrid(x, y, z);
    occ = strapFn_world(X, Y, Z, opts.anchorMm, opts.outDir, params, frameOpts);
    occ = logical(occ) & Z >= opts.zBedMm;

    [TR, occValidated] = triFromOccGrid(x, y, z, occ, 0.5, struct( ...
        'clearShellXY', true, ...
        'clearShellZ', false, ...
        'keepLargest', false, ...
        'closeVox', 0, ...
        'cleanup', true, ...
        'allowPermute', false));

    data = struct();
    data.params = params;
    data.frameOptions = frameOpts;
    data.x = x;
    data.y = y;
    data.z = z;
    data.occ = occValidated;
    data.TR = TR;
    data.components = componentSummary(occValidated);
end

function out = buildOutputFromData(opts, data, fig)
    out = struct();
    out.createdOn = char(datetime('now'));
    out.anchorMm = opts.anchorMm;
    out.outDir = opts.outDir;
    out.params = data.params;
    out.frameOptions = data.frameOptions;
    out.voxelSizeMm = opts.voxelSizeMm;
    out.gridSize = [numel(data.x), numel(data.y), numel(data.z)];
    out.nOccupiedVoxels = nnz(data.occ);
    out.components = data.components;
    out.mesh = meshStats(data.TR);
    out.parameterFile = opts.parameterFile;
    out.manufacturingNameValuePairs = makeManufacturingNameValuePairs(opts);
    if opts.returnOccupancy
        out.occupancy = struct('x', data.x, 'y', data.y, 'z', data.z, ...
            'occ', data.occ);
    end
    if isgraphics(fig)
        out.figure = fig;
    end
end

function fileName = saveInteractiveParameters(opts, data)
    fileName = opts.parameterFile;
    if isempty(fileName)
        outputDir = opts.outputDir;
        if isempty(outputDir)
            outputDir = fullfile(pwd, 'outputs', 'debug', 'chinStrapPreview');
        end
        fileName = fullfile(outputDir, [opts.previewTag '_params.mat']);
    end
    folder = fileparts(fileName);
    if ~isempty(folder)
        ensureOutputDir(folder);
    end
    strapPreviewOptions = opts; %#ok<NASGU>
    strapOptions = data.params; %#ok<NASGU>
    strapFrameOptions = data.frameOptions; %#ok<NASGU>
    manufacturingNameValuePairs = makeManufacturingNameValuePairs(opts); %#ok<NASGU>
    previewMeshStats = meshStats(data.TR); %#ok<NASGU>
    previewVoxelSummary = struct( ...
        'voxelSizeMm', opts.voxelSizeMm, ...
        'gridSize', [numel(data.x), numel(data.y), numel(data.z)], ...
        'nOccupiedVoxels', nnz(data.occ), ...
        'components', data.components); %#ok<NASGU>
    save(fileName, 'strapPreviewOptions', 'strapOptions', ...
        'strapFrameOptions', 'manufacturingNameValuePairs', ...
        'previewMeshStats', 'previewVoxelSummary');
    fprintf('Saved chin strap parameters: %s\n', fileName);
end

function pairs = makeManufacturingNameValuePairs(opts)
    pairs = { ...
        'strapCorrAmpMm', opts.strapCorrAmpMm, ...
        'strapCorrPitchMm', opts.strapCorrPitchMm, ...
        'strapCorrStyle', opts.strapCorrStyle, ...
        'strapCorrFitIntegerCycles', opts.strapCorrFitIntegerCycles, ...
        'strapOptions', strapParams(opts), ...
        'strapFrameOptions', strapFrameOptions(opts)};
end

function params = strapParams(opts)
    params = struct( ...
        'widthMM', opts.strapWidthMm, ...
        'thickMM', opts.strapThickMm, ...
        'bedClearanceMM', opts.strapBedClearanceMm, ...
        'ampMM', opts.strapCorrAmpMm, ...
        'pitchMM', opts.strapCorrPitchMm, ...
        'style', opts.strapCorrStyle, ...
        'fitIntegerCycles', opts.strapCorrFitIntegerCycles, ...
        'bedRunMM', opts.bedRunMm, ...
        'rampRunMM', opts.rampRunMm, ...
        'rampRiseMM', opts.rampRiseMm, ...
        'nCycles', 0, ...
        'xStart', 0, ...
        'ringTubeDiaMM', opts.ringTubeDiaMm, ...
        'ringOuterDiaMM', opts.ringOuterDiaMm, ...
        'ringOverlapMM', opts.ringOverlapMm);
end

function frameOpts = strapFrameOptions(opts)
    loop = struct( ...
        'enable', opts.includeLoop, ...
        'xCenterMM', -4, ...
        'outerXMM', opts.loopOuterXMm, ...
        'outerYMM', opts.loopOuterYMm, ...
        'frameMM', opts.loopFrameMm, ...
        'thickMM', opts.strapThickMm);
    frameOpts = struct( ...
        'zBed', opts.zBedMm, ...
        'ringOffMM', opts.ringOffsetMm, ...
        'startShiftMM', 0, ...
        'loop', loop);
end

function fig = makePreviewFigure(TR, x, y, z, occ, opts)
    data = struct('TR', TR, 'x', x, 'y', y, 'z', z, 'occ', occ, ...
        'components', componentSummary(occ));
    fig = figure('Name', 'Chin strap geometry preview', ...
        'NumberTitle', 'off', ...
        'Color', 'w', ...
        'Visible', onOff(opts.showFigures), ...
        'Position', [120 120 1320 560]);
    tl = tiledlayout(fig, 1, 3, 'TileSpacing', 'compact', 'Padding', 'compact');

    ax3 = nexttile(tl, 1);
    drawSurfacePreview(ax3, data, opts);

    axVoxel = nexttile(tl, 2);
    drawVoxelPreview(axVoxel, data, opts);

    ax2 = nexttile(tl, 3);
    drawSlicePreview(ax2, data, opts);
    rotate3d(fig, 'on');
end

function drawSurfacePreview(ax, data, opts)
    cla(ax);
    hold(ax, 'on');
    TR = data.TR;
    if ~isempty(TR.Points)
        patch(ax, 'Faces', TR.ConnectivityList, 'Vertices', TR.Points, ...
            'FaceColor', [0.05 0.35 0.95], ...
            'FaceAlpha', 0.82, ...
            'EdgeColor', [0.08 0.08 0.08], ...
            'EdgeAlpha', 0.12);
    end
    plotLocalFrame(ax, opts);
    format3dAxis(ax, 'surface mesh');
    camlight(ax, 'headlight');
    lighting(ax, 'flat');
end

function drawVoxelPreview(ax, data, opts)
    cla(ax);
    hold(ax, 'on');
    [ii, jj, kk] = ind2sub(size(data.occ), find(data.occ));
    maxMarkers = 30000;
    wasDecimated = false;
    if numel(ii) > maxMarkers
        pick = round(linspace(1, numel(ii), maxMarkers));
        ii = ii(pick);
        jj = jj(pick);
        kk = kk(pick);
        wasDecimated = true;
    end
    if ~isempty(ii)
        scatter3(ax, data.x(ii), data.y(jj), data.z(kk), ...
            10, [0.05 0.35 0.95], 's', 'filled', ...
            'MarkerFaceAlpha', 0.42, 'MarkerEdgeAlpha', 0.08);
    end
    plotLocalFrame(ax, opts);
    if wasDecimated
        titleText = 'voxel raster (sampled)';
    else
        titleText = 'voxel raster';
    end
    format3dAxis(ax, titleText);
end

function drawSlicePreview(ax, data, opts)
    cla(ax);
    side = squeeze(max(data.occ, [], 2)).';
    imagesc(ax, data.x, data.z, side);
    axis(ax, 'xy');
    axis(ax, 'equal');
    colormap(ax, [1 1 1; 0.05 0.35 0.95]);
    xlabel(ax, 'X mm');
    ylabel(ax, 'Z mm');
    title(ax, sprintf('X/Z voxel projection, pitch %.3g, amp %.3g', ...
        opts.strapCorrPitchMm, opts.strapCorrAmpMm));
end

function format3dAxis(ax, titleText)
    axis(ax, 'equal');
    grid(ax, 'on');
    view(ax, [38 22]);
    xlabel(ax, 'X mm');
    ylabel(ax, 'Y mm');
    zlabel(ax, 'Z mm');
    title(ax, titleText);
end

function plotLocalFrame(ax, opts)
    a = opts.anchorMm;
    d = opts.outDir(:).';
    d(3) = 0;
    if norm(d) < 1e-12
        d = [1 0 0];
    end
    d = d / norm(d);
    inward = -d;
    quiver3(ax, a(1), a(2), a(3), ...
        10 * inward(1), 10 * inward(2), 0, ...
        'Color', [0.05 0.55 0.05], 'LineWidth', 1.4, ...
        'MaxHeadSize', 0.7);
    text(ax, a(1), a(2), a(3), ' anchor', ...
        'Color', [0.05 0.55 0.05], 'FontWeight', 'bold');
end

function stats = componentSummary(occ)
    stats = struct('nComponents', 0, 'componentVoxelCounts', []);
    if ~any(occ(:)) || exist('bwconncomp', 'file') ~= 2
        stats.nComponents = double(any(occ(:)));
        stats.componentVoxelCounts = nnz(occ);
        return;
    end
    CC = bwconncomp(occ, 26);
    stats.nComponents = CC.NumObjects;
    stats.componentVoxelCounts = sort(cellfun(@numel, CC.PixelIdxList), 'descend');
end

function stats = meshStats(TR)
    stats = struct('nVertices', 0, 'nFaces', 0, ...
        'boundsMin', [NaN NaN NaN], 'boundsMax', [NaN NaN NaN]);
    if isempty(TR) || isempty(TR.Points)
        return;
    end
    V = double(TR.Points);
    stats.nVertices = size(V, 1);
    stats.nFaces = size(TR.ConnectivityList, 1);
    stats.boundsMin = min(V, [], 1);
    stats.boundsMax = max(V, [], 1);
end

function ensureOutputDir(folder)
    if isempty(folder)
        error('acsPreviewChinStrapGeometry:MissingOutputDir', ...
            'Set outputDir when saveStl or saveFigures is true.');
    end
    if exist(folder, 'dir') ~= 7
        mkdir(folder);
    end
end

function addLocalDependencies()
    repoRoot = fileparts(fileparts(mfilename('fullpath')));
    addpath(fullfile(repoRoot, 'capMaker', 'geometry'));
    addpath(fullfile(repoRoot, 'capMaker', 'core'));
end

function style = normalizeStrapCorrStyle(styleIn)
    key = lower(regexprep(strtrim(char(styleIn)), '[\s_\-]+', ''));
    switch key
        case {'rectilinear', 'rect', 'square', 'squarewave', ...
                'voxel', 'voxelnative'}
            style = 'rectilinear';
        case {'swept', 'legacy', 'continuous'}
            style = 'swept';
        otherwise
            error('acsPreviewChinStrapGeometry:BadStrapCorrStyle', ...
                'strapCorrStyle must be ''rectilinear'' or ''swept''.');
    end
end

function tf = isPoint3(x)
    tf = isnumeric(x) && numel(x) == 3 && all(isfinite(x(:)));
end

function tf = isPositiveScalar(x)
    tf = isnumeric(x) && isscalar(x) && isfinite(x) && x > 0;
end

function tf = isNonnegativeScalar(x)
    tf = isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0;
end

function tf = isFiniteScalar(x)
    tf = isnumeric(x) && isscalar(x) && isfinite(x);
end

function tf = isBoolLike(x)
    tf = (islogical(x) || isnumeric(x)) && isscalar(x);
end

function value = onOff(tf)
    if tf
        value = 'on';
    else
        value = 'off';
    end
end

function value = clamp(value, minVal, maxVal)
    value = max(minVal, min(maxVal, value));
end

function cam = captureCamera(ax)
    cam = struct();
    if ~isgraphics(ax)
        return;
    end
    cam.CameraPosition = get(ax, 'CameraPosition');
    cam.CameraTarget = get(ax, 'CameraTarget');
    cam.CameraUpVector = get(ax, 'CameraUpVector');
    cam.CameraViewAngle = get(ax, 'CameraViewAngle');
end

function restoreCamera(ax, cam)
    if ~isgraphics(ax) || ~isfield(cam, 'CameraPosition')
        return;
    end
    try
        set(ax, ...
            'CameraPosition', cam.CameraPosition, ...
            'CameraTarget', cam.CameraTarget, ...
            'CameraUpVector', cam.CameraUpVector, ...
            'CameraViewAngle', cam.CameraViewAngle);
    catch
    end
end

function txt = effectivePitchText(opts)
    if ~opts.strapCorrFitIntegerCycles
        txt = 'requested';
        return;
    end
    bed = effectiveSectionPitch(opts.bedRunMm, opts.strapCorrPitchMm);
    ramp = effectiveSectionPitch(opts.rampRunMm, opts.strapCorrPitchMm);
    txt = sprintf('bed %.3g, ramp %.3g mm', bed, ramp);
end

function value = effectiveSectionPitch(runLength, requestedPitch)
    if runLength <= 0
        value = NaN;
        return;
    end
    nCycles = max(1, round(runLength / requestedPitch));
    value = runLength / nCycles;
end
