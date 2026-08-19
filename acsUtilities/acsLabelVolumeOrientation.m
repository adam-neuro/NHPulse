function out = acsLabelVolumeOrientation(volumeIn, varargin)
% ACSLABELVOLUMEORIENTATION Inspect raw voxel dimensions and label anatomy.
%
% out = acsLabelVolumeOrientation(volumeIn) displays raw voxel slices and
% prompts for the anatomical direction of increasing dimensions 1, 2, and 3.
%
% volumeIn can be a 3-D numeric array, a NIfTI filename, or an SPM volume
% struct. The displayed data are raw voxel-array dimensions; NIfTI/SPM affine
% orientation metadata are not used to reorient the volume.
%
% Name-value options:
%   orientationCode : 'ask', 'gui', explicit code like 'ras', or '' ['ask']
%   showFigures     : show the inspection figure [true]
%   saveFigures     : save the inspection figure [false]
%   outputDir       : figure output folder [acsPaths().outputRoot/orientation_qc]
%   outputName      : saved figure filename stem ['']
%   volumeLabel     : display label ['']
%   volumeIndex     : 4-D/SPM volume index [1]
%   initialVoxel    : initial [dim1 dim2 dim3] voxel; center if [] [[]]
%   voxelSelectionMode : 'single' or 'multiple' target selection ['single']
%   sliceFractions  : fallback initial slice fraction [0.5]
%   intensityLimits : display limits; robust limits if [] [[]]
%   allowSkip       : allow Enter to return an empty orientation code [true]
%   waitForDone     : block until the viewer Done/Cancel control is used [false]
%   doneButtonLabel : label for the blocking Done button ['Done']
%   cancelButtonLabel : label for the blocking Cancel button ['Cancel']
%   closeFigure     : close figure before returning [false]
%
% Orientation codes use one character per voxel dimension:
%   r/l = right/left, a/p = anterior/posterior, s/i = superior/inferior.
% For example, 'ras' means dim 1 increases rightward, dim 2 anteriorly, and
% dim 3 superiorly.

    if nargin < 1 || isempty(volumeIn)
        error('acsLabelVolumeOrientation:MissingVolume', ...
            'Pass a 3-D volume array, NIfTI filename, or SPM volume struct.');
    end

    opts = parseInputs(varargin{:});
    [vol, source] = readVolume(volumeIn, opts);

    dims = size(vol);
    dims = dims(1:3);
    currentVoxel = chooseInitialVoxel(dims, opts.initialVoxel, opts.sliceFractions);
    displayInfo = displayPlanes(opts.orientationCode);
    clim = displayLimits(vol, opts.intensityLimits);

    if isempty(opts.volumeLabel)
        opts.volumeLabel = source.label;
    end

    fig = [];
    qcFile = '';
    if opts.showFigures || opts.saveFigures
        figVisible = 'off';
        if opts.showFigures
            figVisible = 'on';
        end
        fig = makeInspectionFigure(vol, opts.volumeLabel, currentVoxel, ...
            displayInfo, clim, figVisible, opts.voxelSelectionMode, opts);
    end

    if opts.showFigures && ~isempty(fig) && ishandle(fig)
        printViewerUsage(opts.voxelSelectionMode, opts.waitForDone, opts.verbose);
    end

    if opts.waitForDone && ~isempty(fig) && ishandle(fig)
        uiwait(fig);
        if ~ishandle(fig) || isequal(getappdata(fig, 'acsCanceled'), true)
            error('acsLabelVolumeOrientation:Canceled', ...
                'Voxel selection was canceled.');
        end
    end

    orientationCode = resolveOrientationCode(opts.orientationCode, ...
        opts.allowSkip, opts.verbose);
    orientation = orientationSummary(orientationCode);

    if ~isempty(fig) && ishandle(fig)
        storedVoxel = getappdata(fig, 'acsCurrentVoxel');
        if isnumeric(storedVoxel) && numel(storedVoxel) == 3
            currentVoxel = double(storedVoxel(:))';
        end
    end
    [selectedVoxels, explicitSelectedVoxels] = selectedVoxelsFromFigure( ...
        fig, currentVoxel);

    if opts.saveFigures && ~isempty(fig) && ishandle(fig)
        if isempty(opts.outputDir)
            opts.outputDir = defaultOutputDir(opts.configFile);
        end
        ensureDir(opts.outputDir);
        qcFile = fullfile(opts.outputDir, [savedFigureStem(opts, source) '.png']);
        saveQcFigure(fig, qcFile);
    end

    if opts.closeFigure && ~isempty(fig) && ishandle(fig)
        close(fig);
    end

    out = struct();
    out.orientationCode = orientationCode;
    out.orientation = orientation;
    out.imageSize = dims;
    out.currentVoxel = currentVoxel;
    out.sliceIndices = currentVoxel;
    out.selectedVoxels = selectedVoxels;
    out.explicitSelectedVoxels = explicitSelectedVoxels;
    out.voxelSelectionMode = opts.voxelSelectionMode;
    out.display = displayInfo;
    out.source = source;
    out.figure = fig;
    out.qcFile = qcFile;
end

function opts = parseInputs(varargin)
    p = inputParser;
    p.FunctionName = 'acsLabelVolumeOrientation';
    addParameter(p, 'orientationCode', 'ask', ...
        @(x) ischar(x) || isstring(x));
    addParameter(p, 'showFigures', true, @isBoolLike);
    addParameter(p, 'saveFigures', false, @isBoolLike);
    addParameter(p, 'outputDir', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'outputName', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'volumeLabel', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'volumeIndex', 1, ...
        @(x) isnumeric(x) && isscalar(x) && x >= 1);
    addParameter(p, 'initialVoxel', [], ...
        @(x) isempty(x) || (isnumeric(x) && numel(x) == 3));
    addParameter(p, 'voxelSelectionMode', 'single', ...
        @(x) ischar(x) || isstring(x));
    addParameter(p, 'allowMultipleVoxels', [], ...
        @(x) isempty(x) || isBoolLike(x));
    addParameter(p, 'sliceFractions', 0.5, ...
        @(x) isnumeric(x) && isvector(x) && ~isempty(x));
    addParameter(p, 'intensityLimits', [], ...
        @(x) isempty(x) || (isnumeric(x) && numel(x) == 2));
    addParameter(p, 'allowSkip', true, @isBoolLike);
    addParameter(p, 'waitForDone', false, @isBoolLike);
    addParameter(p, 'doneButtonLabel', 'Done', ...
        @(x) ischar(x) || isstring(x));
    addParameter(p, 'cancelButtonLabel', 'Cancel', ...
        @(x) ischar(x) || isstring(x));
    addParameter(p, 'closeFigure', false, @isBoolLike);
    addParameter(p, 'verbose', true, @isBoolLike);
    addParameter(p, 'configFile', '', @(x) ischar(x) || isstring(x));
    parse(p, varargin{:});

    opts = p.Results;
    charFields = {'orientationCode', 'outputDir', 'outputName', ...
        'volumeLabel', 'voxelSelectionMode', 'doneButtonLabel', ...
        'cancelButtonLabel', 'configFile'};
    for i = 1:numel(charFields)
        f = charFields{i};
        opts.(f) = char(opts.(f));
    end
    opts.outputDir = expandUserPath(opts.outputDir);
    opts.configFile = expandUserPath(opts.configFile);
    opts.showFigures = logical(opts.showFigures);
    opts.saveFigures = logical(opts.saveFigures);
    opts.volumeIndex = round(double(opts.volumeIndex));
    opts.initialVoxel = double(opts.initialVoxel(:))';
    opts.voxelSelectionMode = normalizeVoxelSelectionMode( ...
        opts.voxelSelectionMode, opts.allowMultipleVoxels);
    opts.sliceFractions = sort(double(opts.sliceFractions(:))');
    opts.sliceFractions = max(0, min(1, opts.sliceFractions));
    opts.intensityLimits = double(opts.intensityLimits(:))';
    opts.allowSkip = logical(opts.allowSkip);
    opts.waitForDone = logical(opts.waitForDone);
    if opts.waitForDone
        opts.showFigures = true;
    end
    opts.closeFigure = logical(opts.closeFigure);
    opts.verbose = logical(opts.verbose);
end

function mode = normalizeVoxelSelectionMode(mode, allowMultipleVoxels)
    if ~isempty(allowMultipleVoxels)
        if logical(allowMultipleVoxels)
            mode = 'multiple';
        else
            mode = 'single';
        end
    end
    mode = lower(strtrim(char(mode)));
    switch mode
        case {'single', 'one', 'current'}
            mode = 'single';
        case {'multiple', 'multi', 'many', 'targets'}
            mode = 'multiple';
        otherwise
            error('acsLabelVolumeOrientation:BadVoxelSelectionMode', ...
                'voxelSelectionMode must be ''single'' or ''multiple''.');
    end
end

function tf = isBoolLike(x)
    tf = (islogical(x) || isnumeric(x)) && isscalar(x);
end

function printViewerUsage(voxelSelectionMode, waitForDone, verbose)
    if ~verbose
        return;
    end
    fprintf('\nVolume viewer controls:\n');
    fprintf('  click a slice, or use sliders, to move the yellow crosshair/current voxel.\n');
    if strcmp(voxelSelectionMode, 'multiple')
        fprintf('  press A or click Add voxel to append the current voxel to selectedVoxels.\n');
        fprintf('  press Backspace/Delete/U to remove the last selected voxel; press C to clear all.\n');
    else
        fprintf('  press A or click Set voxel to store the current voxel explicitly.\n');
    end
    fprintf('  currentVoxel is always returned; selectedVoxels contains stored targets, or currentVoxel if none were stored.\n');
    if waitForDone
        fprintf('  click Done/Accept, or press Enter, when the selected voxel is correct; press Escape to cancel.\n');
    else
        fprintf('  if you are using this only as a voxel picker, press Enter at the orientation prompt.\n');
    end
end

function [selectedVoxels, explicitSelectedVoxels] = selectedVoxelsFromFigure(fig, currentVoxel)
    explicitSelectedVoxels = zeros(0, 3);
    if ~isempty(fig) && ishandle(fig)
        storedSelected = getappdata(fig, 'acsSelectedVoxels');
        if isnumeric(storedSelected) && size(storedSelected, 2) == 3
            explicitSelectedVoxels = double(round(storedSelected));
            explicitSelectedVoxels = explicitSelectedVoxels( ...
                all(isfinite(explicitSelectedVoxels), 2), :);
        end
    end
    if isempty(explicitSelectedVoxels)
        selectedVoxels = double(round(currentVoxel(:)'));
    else
        selectedVoxels = explicitSelectedVoxels;
    end
end

function [vol, source] = readVolume(volumeIn, opts)
    source = struct('type', '', 'file', '', 'label', '', 'volumeIndex', opts.volumeIndex);

    if isnumeric(volumeIn) || islogical(volumeIn)
        vol = volumeIn;
        source.type = 'array';
        source.label = 'workspace volume';
    elseif isstruct(volumeIn) && isfield(volumeIn, 'fname')
        requireSpm();
        V = volumeIn(:);
        if opts.volumeIndex > numel(V)
            error('acsLabelVolumeOrientation:VolumeIndexOutOfRange', ...
                'Requested volumeIndex %d but SPM volume has %d frame(s).', ...
                opts.volumeIndex, numel(V));
        end
        V = V(opts.volumeIndex);
        vol = spm_read_vols(V);
        source.type = 'spmVolume';
        source.file = V.fname;
        source.label = getFileName(V.fname);
    elseif ischar(volumeIn) || isstring(volumeIn)
        fileName = expandUserPath(char(volumeIn));
        if exist(fileName, 'file') ~= 2
            error('acsLabelVolumeOrientation:FileNotFound', ...
                'Volume file not found: %s', fileName);
        end
        [vol, nFrames] = readVolumeFile(fileName, opts.volumeIndex);
        source.type = 'file';
        source.file = fileName;
        source.label = getFileName(fileName);
        source.nFrames = nFrames;
    else
        error('acsLabelVolumeOrientation:UnsupportedInput', ...
            'Unsupported volume input type: %s.', class(volumeIn));
    end

    vol = selectVolumeFrame(vol, opts.volumeIndex);
    if ndims(vol) ~= 3
        error('acsLabelVolumeOrientation:BadVolumeSize', ...
            'Expected a 3-D volume after selecting volumeIndex; got size [%s].', ...
            num2str(size(vol)));
    end
end

function [vol, nFrames] = readVolumeFile(fileName, volumeIndex)
    nFrames = 1;
    if canUseSpm()
        V = spm_vol(fileName);
        V = V(:);
        nFrames = numel(V);
        if volumeIndex > nFrames
            error('acsLabelVolumeOrientation:VolumeIndexOutOfRange', ...
                'Requested volumeIndex %d but file has %d frame(s).', ...
                volumeIndex, nFrames);
        end
        vol = spm_read_vols(V(volumeIndex));
        return;
    end

    if exist('niftiread', 'file') ~= 2
        error('acsLabelVolumeOrientation:MissingReader', ...
            'No SPM or niftiread function is available to read %s.', fileName);
    end
    vol = niftiread(fileName);
    dims = size(vol);
    if numel(dims) > 3
        nFrames = dims(4);
    end
end

function vol = selectVolumeFrame(vol, volumeIndex)
    dims = size(vol);
    if numel(dims) <= 3
        return;
    end
    if volumeIndex > dims(4)
        error('acsLabelVolumeOrientation:VolumeIndexOutOfRange', ...
            'Requested volumeIndex %d but array has %d frame(s).', ...
            volumeIndex, dims(4));
    end
    subs = repmat({':'}, 1, ndims(vol));
    subs{4} = volumeIndex;
    for i = 5:ndims(vol)
        subs{i} = 1;
    end
    vol = vol(subs{:});
end

function tf = canUseSpm()
    tf = exist('spm_vol', 'file') == 2 && exist('spm_read_vols', 'file') == 2;
    if tf
        return;
    end
    repoRoot = fileparts(fileparts(mfilename('fullpath')));
    spmDir = fullfile(repoRoot, 'lib', 'spm12');
    if exist(spmDir, 'dir') == 7
        addpath(spmDir);
    end
    tf = exist('spm_vol', 'file') == 2 && exist('spm_read_vols', 'file') == 2;
end

function requireSpm()
    if ~canUseSpm()
        error('acsLabelVolumeOrientation:MissingSpm', ...
            'SPM is required to read an SPM volume struct.');
    end
end

function currentVoxel = chooseInitialVoxel(dims, initialVoxel, fractions)
    if ~isempty(initialVoxel)
        currentVoxel = round(double(initialVoxel(:))');
    else
        frac = fractions(max(1, round(numel(fractions) / 2)));
        currentVoxel = round(1 + (dims - 1) .* frac);
    end
    currentVoxel = max([1 1 1], min(dims, currentVoxel));
end

function info = displayPlanes(orientationCode)
    fixedDims = 1:3;
    rowDims = [2 1 1];
    colDims = [3 3 2];
    dimLabels = dimensionDisplayLabels(orientationCode);
    info = repmat(struct( ...
        'fixedDim', 1, ...
        'rowDim', 1, ...
        'colDim', 1, ...
        'screenRight', '', ...
        'screenDown', ''), 1, 3);
    for i = 1:3
        info(i).fixedDim = fixedDims(i);
        info(i).rowDim = rowDims(i);
        info(i).colDim = colDims(i);
        info(i).screenRight = dimLabels{colDims(i)};
        info(i).screenDown = dimLabels{rowDims(i)};
    end
end

function labels = dimensionDisplayLabels(orientationCode)
    labels = arrayfun(@(d) sprintf('+dim %d', d), 1:3, ...
        'UniformOutput', false);
    code = lower(strtrim(char(orientationCode)));
    if numel(code) ~= 3 || any(strcmp(code, {'ask', 'gui', 'prompt'}))
        return;
    end
    try
        code = validateOrientationCode(code);
    catch
        return;
    end
    for dim = 1:3
        labels{dim} = sprintf('%s (+dim %d)', ...
            directionDisplayName(code(dim)), dim);
    end
end

function name = directionDisplayName(code)
    switch code
        case 'r'
            name = 'right';
        case 'l'
            name = 'left';
        case 'a'
            name = 'rostral';
        case 'p'
            name = 'caudal';
        case 's'
            name = 'dorsal';
        case 'i'
            name = 'ventral';
        otherwise
            name = sprintf('+%s', code);
    end
end

function clim = displayLimits(vol, explicitLimits)
    if ~isempty(explicitLimits)
        clim = sort(double(explicitLimits));
        return;
    end

    n = numel(vol);
    if n > 1000000
        step = ceil(n / 1000000);
        vals = double(vol(1:step:end));
    else
        vals = double(vol(:));
    end
    vals = vals(isfinite(vals));
    if isempty(vals)
        clim = [0 1];
        return;
    end

    vals = sort(vals(:));
    lo = vals(max(1, round(0.005 * numel(vals))));
    hi = vals(min(numel(vals), round(0.995 * numel(vals))));
    if hi <= lo
        lo = min(vals);
        hi = max(vals);
    end
    if hi <= lo
        hi = lo + 1;
    end
    clim = [lo hi];
end

function fig = makeInspectionFigure(vol, volumeLabel, currentVoxel, ...
        displayInfo, clim, figVisible, voxelSelectionMode, viewerOpts)
    if nargin < 8 || isempty(viewerOpts)
        viewerOpts = struct();
    end
    if ~isfield(viewerOpts, 'waitForDone')
        viewerOpts.waitForDone = false;
    end
    if ~isfield(viewerOpts, 'doneButtonLabel')
        viewerOpts.doneButtonLabel = 'Done';
    end
    if ~isfield(viewerOpts, 'cancelButtonLabel')
        viewerOpts.cancelButtonLabel = 'Cancel';
    end

    fig = figure('Name', 'Raw volume orientation inspection', ...
        'Color', 'w', ...
        'Visible', figVisible, ...
        'Units', 'pixels', ...
        'Position', [80 80 1420 800], ...
        'WindowKeyPressFcn', @onKeyPress);
    setappdata(fig, 'acsCanceled', false);
    if viewerOpts.waitForDone
        set(fig, 'CloseRequestFcn', @onCloseRequest);
    end

    addHeader(fig, volumeLabel);

    dims = size(vol);
    dims = dims(1:3);
    state.currentVoxel = currentVoxel;
    state.selectedVoxels = zeros(0, 3);
    state.voxelSelectionMode = voxelSelectionMode;

    h = struct();
    h.ax = gobjects(1, 3);
    h.image = gobjects(1, 3);
    h.title = gobjects(1, 3);
    h.crossCol = gobjects(1, 3);
    h.crossRow = gobjects(1, 3);
    h.selectedPoint = gobjects(1, 3);
    h.slider = gobjects(1, 3);
    h.valueLabel = gobjects(1, 3);
    h.selectionLabel = gobjects(1, 1);

    left = 0.065;
    right = 0.035;
    gap = 0.06;
    yAx = 0.27;
    hAx = 0.56;
    wAx = (1 - left - right - 2 * gap) / 3;

    for plane = 1:3
        pos = [left + (plane - 1) * (wAx + gap), yAx, wAx, hAx];
        h.ax(plane) = axes(fig, 'Position', pos); %#ok<LAXES>
        S = rawSlice(vol, displayInfo(plane).fixedDim, state.currentVoxel(displayInfo(plane).fixedDim));
        h.image(plane) = imagesc(h.ax(plane), S);
        set(h.image(plane), 'ButtonDownFcn', @(~, ~) onPlaneClick(plane));
        axis(h.ax(plane), 'image');
        box(h.ax(plane), 'on');
        set(h.ax(plane), ...
            'YDir', 'reverse', ...
            'XTick', [], ...
            'YTick', [], ...
            'ButtonDownFcn', @(~, ~) onPlaneClick(plane));
        colormap(h.ax(plane), gray);
        caxis(h.ax(plane), clim);
        hold(h.ax(plane), 'on');
        h.crossCol(plane) = line(h.ax(plane), [1 1], [1 1], ...
            'Color', [1 0.85 0], 'LineStyle', '-', 'LineWidth', 0.9, ...
            'HitTest', 'off');
        h.crossRow(plane) = line(h.ax(plane), [1 1], [1 1], ...
            'Color', [1 0.85 0], 'LineStyle', '-', 'LineWidth', 0.9, ...
            'HitTest', 'off');
        h.selectedPoint(plane) = line(h.ax(plane), nan, nan, ...
            'LineStyle', 'none', ...
            'Marker', 'o', ...
            'MarkerSize', 8, ...
            'MarkerEdgeColor', [1 1 1], ...
            'MarkerFaceColor', [0.95 0.05 0.75], ...
            'LineWidth', 1.1, ...
            'HitTest', 'off');
        h.title(plane) = title(h.ax(plane), '', ...
            'Interpreter', 'none', ...
            'FontSize', 11, ...
            'FontWeight', 'bold');
        addScreenAxisLabels(fig, h.ax(plane), pos, displayInfo(plane));
    end

    addControls();
    updateViewer();
    drawnow;

    function addControls()
        baseY = 0.145;
        rowGap = 0.047;
        for dim = 1:3
            y = baseY - (dim - 1) * rowGap;
            uicontrol(fig, ...
                'Style', 'text', ...
                'Units', 'normalized', ...
                'Position', [0.075 y 0.10 0.028], ...
                'String', sprintf('dim %d', dim), ...
                'HorizontalAlignment', 'right', ...
                'BackgroundColor', 'w', ...
                'FontWeight', 'bold');
            h.slider(dim) = uicontrol(fig, ...
                'Style', 'slider', ...
                'Units', 'normalized', ...
                'Position', [0.19 y 0.62 0.03], ...
                'Min', 1, ...
                'Max', max(1, dims(dim)), ...
                'Value', state.currentVoxel(dim), ...
                'SliderStep', sliderStep(dims(dim)), ...
                'Callback', @(~, ~) onSlider(dim));
            if dims(dim) <= 1
                set(h.slider(dim), 'Enable', 'off');
            end
            h.valueLabel(dim) = uicontrol(fig, ...
                'Style', 'text', ...
                'Units', 'normalized', ...
                'Position', [0.825 y 0.11 0.028], ...
                'String', '', ...
                'HorizontalAlignment', 'left', ...
                'BackgroundColor', 'w');
        end
        h.selectionLabel = uicontrol(fig, ...
            'Style', 'text', ...
            'Units', 'normalized', ...
            'Position', [0.075 0.010 0.28 0.032], ...
            'String', '', ...
            'HorizontalAlignment', 'left', ...
            'BackgroundColor', 'w', ...
            'FontWeight', 'bold');
        uicontrol(fig, ...
            'Style', 'pushbutton', ...
            'Units', 'normalized', ...
            'Position', [0.375 0.010 0.095 0.036], ...
            'String', selectionButtonLabel(), ...
            'Callback', @(~, ~) addSelectedVoxel());
        uicontrol(fig, ...
            'Style', 'pushbutton', ...
            'Units', 'normalized', ...
            'Position', [0.485 0.010 0.075 0.036], ...
            'String', 'Undo', ...
            'Callback', @(~, ~) undoSelectedVoxel());
        uicontrol(fig, ...
            'Style', 'pushbutton', ...
            'Units', 'normalized', ...
            'Position', [0.575 0.010 0.075 0.036], ...
            'String', 'Clear', ...
            'Callback', @(~, ~) clearSelectedVoxels());
        if viewerOpts.waitForDone
            uicontrol(fig, ...
                'Style', 'pushbutton', ...
                'Units', 'normalized', ...
                'Position', [0.735 0.010 0.120 0.036], ...
                'String', viewerOpts.doneButtonLabel, ...
                'FontWeight', 'bold', ...
                'Callback', @(~, ~) acceptSelection());
            uicontrol(fig, ...
                'Style', 'pushbutton', ...
                'Units', 'normalized', ...
                'Position', [0.870 0.010 0.085 0.036], ...
                'String', viewerOpts.cancelButtonLabel, ...
                'Callback', @(~, ~) cancelSelection(true));
        end
    end

    function onSlider(dim)
        state.currentVoxel(dim) = clampVoxel(dim, get(h.slider(dim), 'Value'));
        updateViewer();
    end

    function onPlaneClick(plane)
        ax = h.ax(plane);
        cp = get(ax, 'CurrentPoint');
        x = cp(1, 1);
        y = cp(1, 2);
        info = displayInfo(plane);
        S = get(h.image(plane), 'CData');
        nRows = size(S, 1);
        nCols = size(S, 2);
        if x < 0.5 || x > nCols + 0.5 || y < 0.5 || y > nRows + 0.5
            return;
        end
        state.currentVoxel(info.colDim) = clampVoxel(info.colDim, x);
        state.currentVoxel(info.rowDim) = clampVoxel(info.rowDim, y);
        updateViewer();
    end

    function onKeyPress(~, event)
        key = lower(event.Key);
        switch key
            case {'a', 'space'}
                addSelectedVoxel();
            case {'backspace', 'delete', 'u'}
                undoSelectedVoxel();
            case 'c'
                clearSelectedVoxels();
            case {'return', 'enter'}
                if viewerOpts.waitForDone
                    acceptSelection();
                end
            case 'escape'
                if viewerOpts.waitForDone
                    cancelSelection(true);
                end
        end
    end

    function acceptSelection()
        if isempty(state.selectedVoxels)
            addSelectedVoxel();
        else
            updateViewer();
        end
        setappdata(fig, 'acsCanceled', false);
        uiresume(fig);
    end

    function cancelSelection(deleteFigure)
        if nargin < 1
            deleteFigure = false;
        end
        if ~ishandle(fig)
            return;
        end
        setappdata(fig, 'acsCanceled', true);
        uiresume(fig);
        if deleteFigure && ishandle(fig)
            delete(fig);
        end
    end

    function onCloseRequest(~, ~)
        cancelSelection(true);
    end

    function addSelectedVoxel()
        voxel = max([1 1 1], min(dims, round(state.currentVoxel)));
        if strcmp(state.voxelSelectionMode, 'multiple')
            if isempty(state.selectedVoxels) || ...
                    ~any(all(bsxfun(@eq, state.selectedVoxels, voxel), 2))
                state.selectedVoxels(end + 1, :) = voxel; %#ok<AGROW>
            end
        else
            state.selectedVoxels = voxel;
        end
        updateViewer();
    end

    function undoSelectedVoxel()
        if isempty(state.selectedVoxels)
            updateViewer();
            return;
        end
        state.selectedVoxels(end, :) = [];
        updateViewer();
    end

    function clearSelectedVoxels()
        state.selectedVoxels = zeros(0, 3);
        updateViewer();
    end

    function updateViewer()
        state.currentVoxel = max([1 1 1], min(dims, round(state.currentVoxel)));
        setappdata(fig, 'acsCurrentVoxel', state.currentVoxel);
        setappdata(fig, 'acsSelectedVoxels', state.selectedVoxels);

        for dim = 1:3
            set(h.slider(dim), 'Value', state.currentVoxel(dim));
            set(h.valueLabel(dim), 'String', ...
                sprintf('%d / %d', state.currentVoxel(dim), dims(dim)));
        end

        for plane = 1:3
            info = displayInfo(plane);
            fixedIdx = state.currentVoxel(info.fixedDim);
            S = rawSlice(vol, info.fixedDim, fixedIdx);
            set(h.image(plane), 'CData', S);
            nRows = size(S, 1);
            nCols = size(S, 2);
            set(h.ax(plane), ...
                'XLim', [0.5 nCols + 0.5], ...
                'YLim', [0.5 nRows + 0.5]);
            x = state.currentVoxel(info.colDim);
            y = state.currentVoxel(info.rowDim);
            set(h.crossCol(plane), 'XData', [x x], 'YData', [0.5 nRows + 0.5]);
            set(h.crossRow(plane), 'XData', [0.5 nCols + 0.5], 'YData', [y y]);
            selectedOnSlice = selectedVoxelsOnSlice(info, fixedIdx);
            set(h.selectedPoint(plane), ...
                'XData', selectedOnSlice(:, 1), ...
                'YData', selectedOnSlice(:, 2));
            set(h.title(plane), 'String', sprintf('dim %d = %d', info.fixedDim, fixedIdx));
        end
        set(h.selectionLabel, 'String', selectionSummaryString());
        drawnow limitrate;
    end

    function selectedXY = selectedVoxelsOnSlice(info, fixedIdx)
        selectedXY = zeros(0, 2);
        if isempty(state.selectedVoxels)
            return;
        end
        onSlice = state.selectedVoxels(:, info.fixedDim) == fixedIdx;
        vox = state.selectedVoxels(onSlice, :);
        if isempty(vox)
            return;
        end
        selectedXY = [vox(:, info.colDim), vox(:, info.rowDim)];
    end

    function val = clampVoxel(dim, val)
        val = round(double(val));
        val = max(1, min(dims(dim), val));
    end

    function label = selectionButtonLabel()
        if strcmp(state.voxelSelectionMode, 'multiple')
            label = 'Add voxel';
        else
            label = 'Set voxel';
        end
    end

    function label = selectionSummaryString()
        n = size(state.selectedVoxels, 1);
        if n == 0
            label = sprintf('Selected voxels: 0 | current [%d %d %d]', ...
                state.currentVoxel(1), state.currentVoxel(2), state.currentVoxel(3));
        elseif n == 1
            label = sprintf('Selected voxel: [%d %d %d]', ...
                state.selectedVoxels(1, 1), state.selectedVoxels(1, 2), ...
                state.selectedVoxels(1, 3));
        else
            label = sprintf('Selected voxels: %d | last [%d %d %d]', ...
                n, state.selectedVoxels(end, 1), state.selectedVoxels(end, 2), ...
                state.selectedVoxels(end, 3));
        end
    end
end

function addHeader(fig, volumeLabel)
    header = sprintf('Raw voxel orientation inspection: %s', volumeLabel);
    annotation(fig, 'textbox', [0.04 0.91 0.92 0.055], ...
        'String', header, ...
        'Interpreter', 'none', ...
        'HorizontalAlignment', 'center', ...
        'VerticalAlignment', 'middle', ...
        'FontWeight', 'bold', ...
        'FontSize', 11, ...
        'EdgeColor', 'none');
end

function addScreenAxisLabels(fig, ax, axPos, info)
    x1 = axPos(1);
    y1 = axPos(2);
    w = axPos(3);
    h = axPos(4);

    annotation(fig, 'arrow', [x1 + 0.10 * w, x1 + 0.90 * w], ...
        [y1 - 0.035, y1 - 0.035], ...
        'LineWidth', 1.1, ...
        'Color', [0.10 0.10 0.10]);
    text(ax, 0.5, -0.10, info.screenRight, ...
        'Units', 'normalized', ...
        'Interpreter', 'none', ...
        'HorizontalAlignment', 'center', ...
        'VerticalAlignment', 'middle', ...
        'FontSize', 9, ...
        'FontWeight', 'bold', ...
        'Clipping', 'off');

    annotation(fig, 'arrow', [x1 - 0.018, x1 - 0.018], ...
        [y1 + 0.90 * h, y1 + 0.10 * h], ...
        'LineWidth', 1.1, ...
        'Color', [0.10 0.10 0.10]);
    text(ax, -0.11, 0.5, info.screenDown, ...
        'Units', 'normalized', ...
        'Interpreter', 'none', ...
        'HorizontalAlignment', 'center', ...
        'VerticalAlignment', 'middle', ...
        'Rotation', 90, ...
        'FontSize', 9, ...
        'FontWeight', 'bold', ...
        'Clipping', 'off');
end

function step = sliderStep(n)
    if n <= 1
        step = [1 1];
    else
        step = [1 / (n - 1), min(1, 10 / (n - 1))];
    end
end

function S = rawSlice(vol, fixedDim, idx)
    switch fixedDim
        case 1
            S = squeeze(vol(idx, :, :));
        case 2
            S = squeeze(vol(:, idx, :));
        case 3
            S = squeeze(vol(:, :, idx));
        otherwise
            error('acsLabelVolumeOrientation:BadSliceDimension', ...
                'Unsupported fixed dimension %d.', fixedDim);
    end
    S = double(S);
end

function orientationCode = resolveOrientationCode(codeIn, allowSkip, verbose)
    codeIn = lower(strtrim(char(codeIn)));
    if isempty(codeIn) || any(strcmp(codeIn, {'none', 'skip', 'inspect'}))
        orientationCode = '';
        return;
    end

    if any(strcmp(codeIn, {'ask', 'gui', 'prompt', 'interactive'}))
        orientationCode = promptForOrientation(allowSkip, verbose);
        return;
    end

    orientationCode = validateOrientationCode(codeIn);
    if verbose
        printOrientationSummary(orientationCode);
    end
end

function code = promptForOrientation(allowSkip, verbose)
    if verbose
        fprintf('\nInspect the orientation figure, then label the increasing anatomical direction of voxel dimensions 1-3.\n');
        fprintf('Use one code per dimension: r/l = right/left, a/p = anterior/posterior, s/i = superior/inferior.\n');
    end

    prompt = 'Increasing anatomical directions for dims 1-3 (e.g., ras)';
    if allowSkip
        prompt = [prompt '; Enter to skip'];
    end
    prompt = [prompt ': '];

    while true
        response = lower(strtrim(input(prompt, 's')));
        response = regexprep(response, '[\s,;:_-]+', '');
        if isempty(response)
            if allowSkip
                code = '';
                return;
            end
            fprintf('Please enter a three-character orientation code.\n');
            continue;
        end

        try
            code = validateOrientationCode(response);
            if verbose
                printOrientationSummary(code);
            end
            return;
        catch ME
            fprintf('Invalid orientation code: %s\n', ME.message);
        end
    end
end

function code = validateOrientationCode(code)
    code = lower(strtrim(char(code)));
    code = regexprep(code, '[\s,;:_-]+', '');
    if numel(code) ~= 3
        error('Expected exactly three characters, one for each voxel dimension.');
    end
    if any(~ismember(code, 'rlapsi'))
        error('Allowed characters are r, l, a, p, s, and i.');
    end

    classes = cell(1, 3);
    for i = 1:3
        classes{i} = orientationClass(code(i));
    end
    expected = {'left-right', 'anterior-posterior', 'superior-inferior'};
    for i = 1:numel(expected)
        if sum(strcmp(classes, expected{i})) ~= 1
            error('Use exactly one left/right, one anterior/posterior, and one superior/inferior direction.');
        end
    end
end

function summary = orientationSummary(code)
    summary = struct('isComplete', false, 'dimensions', []);
    if isempty(code)
        return;
    end

    dim = repmat(struct( ...
        'index', 1, ...
        'code', '', ...
        'direction', '', ...
        'axis', '', ...
        'oppositeCode', '', ...
        'oppositeDirection', ''), 1, 3);
    for i = 1:3
        [direction, axisName, oppositeCode, oppositeDirection] = ...
            orientationDetails(code(i));
        dim(i).index = i;
        dim(i).code = code(i);
        dim(i).direction = direction;
        dim(i).axis = axisName;
        dim(i).oppositeCode = oppositeCode;
        dim(i).oppositeDirection = oppositeDirection;
    end
    summary.isComplete = true;
    summary.dimensions = dim;
end

function printOrientationSummary(code)
    if isempty(code)
        return;
    end
    summary = orientationSummary(code);
    fprintf('Accepted orientation code: %s\n', code);
    for i = 1:3
        d = summary.dimensions(i);
        fprintf('  dim %d increases toward %s\n', d.index, d.direction);
    end
end

function cls = orientationClass(code)
    switch code
        case {'r', 'l'}
            cls = 'left-right';
        case {'a', 'p'}
            cls = 'anterior-posterior';
        case {'s', 'i'}
            cls = 'superior-inferior';
        otherwise
            error('Unknown orientation code "%s".', code);
    end
end

function [direction, axisName, oppositeCode, oppositeDirection] = orientationDetails(code)
    switch code
        case 'r'
            direction = 'right';
            axisName = 'left-right';
            oppositeCode = 'l';
            oppositeDirection = 'left';
        case 'l'
            direction = 'left';
            axisName = 'left-right';
            oppositeCode = 'r';
            oppositeDirection = 'right';
        case 'a'
            direction = 'anterior';
            axisName = 'anterior-posterior';
            oppositeCode = 'p';
            oppositeDirection = 'posterior';
        case 'p'
            direction = 'posterior';
            axisName = 'anterior-posterior';
            oppositeCode = 'a';
            oppositeDirection = 'anterior';
        case 's'
            direction = 'superior';
            axisName = 'superior-inferior';
            oppositeCode = 'i';
            oppositeDirection = 'inferior';
        case 'i'
            direction = 'inferior';
            axisName = 'superior-inferior';
            oppositeCode = 's';
            oppositeDirection = 'superior';
        otherwise
            error('Unknown orientation code "%s".', code);
    end
end

function outputDir = defaultOutputDir(configFile)
    if exist('acsPaths', 'file') == 2
        P = acsPaths('configFile', configFile);
        outputDir = fullfile(P.outputRoot, 'orientation_qc');
    else
        outputDir = fullfile(pwd, 'outputs', 'orientation_qc');
    end
end

function stem = savedFigureStem(opts, source)
    if ~isempty(opts.outputName)
        stem = safeName(stripPngExtension(opts.outputName));
        return;
    end
    if ~isempty(opts.volumeLabel)
        base = opts.volumeLabel;
    elseif ~isempty(source.label)
        base = source.label;
    else
        base = 'volume';
    end
    stem = [safeName(stripNiftiExtension(base)) '_orientationInspection'];
end

function ensureDir(pathIn)
    if exist(pathIn, 'dir') ~= 7
        mkdir(pathIn);
    end
end

function saveQcFigure(fig, qcFile)
    try
        exportgraphics(fig, qcFile, 'Resolution', 150);
    catch
        saveas(fig, qcFile);
    end
end

function base = stripNiftiExtension(fileName)
    [~, base, ext] = fileparts(fileName);
    if strcmpi(ext, '.gz')
        [~, base] = fileparts(base);
    end
end

function base = stripPngExtension(fileName)
    [~, base, ext] = fileparts(fileName);
    if isempty(base)
        base = fileName;
    elseif ~strcmpi(ext, '.png')
        base = [base ext];
    end
end

function name = getFileName(filePath)
    [~, name, ext] = fileparts(filePath);
    name = [name ext];
end

function s = safeName(s)
    s = char(s);
    s = regexprep(s, '[^A-Za-z0-9_-]+', '_');
    s = regexprep(s, '_+', '_');
    s = regexprep(s, '^_|_$', '');
    if isempty(s)
        s = 'volume';
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
