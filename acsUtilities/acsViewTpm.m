function out = acsViewTpm(varargin)
% ACSVIEWTPM Visualize a six-channel macaque tissue probability map.
%
% out = acsViewTpm() opens the default macaque TPM and displays QC figures.
% out = acsViewTpm(tpmFile) displays a specific TPM file.
%
% Name-value options:
%   tpmFile        : explicit TPM NIfTI ['']
%   priorDir       : folder searched for defaultMonkeyTpm.nii ['']
%   outputDir      : QC output folder [outputs/templates/tpm_qc]
%   defaultTpmName : default TPM filename ['defaultMonkeyTpm.nii']
%   showFigures    : show figures [true]
%   saveFigures    : save PNG figures [false]
%   contourLevel   : probability contour level [0.5]
%   sliceIndices   : [dim1 dim2 dim3] slices; central slices if []
%   channelLabels  : channel names in TPM order
%
% The expected ROAST/SPM channel order is:
%   1 gray matter, 2 white matter, 3 CSF, 4 bone, 5 skin/scalp, 6 air.

    [positionalTpm, varargin] = parsePositionalTpm(varargin{:});
    opts = parseInputs(positionalTpm, varargin{:});

    P = acsPaths('configFile', opts.configFile);
    addRoastDependencies(P);

    tpmFile = resolveTpmFile(P, opts);
    vols = spm_vol(tpmFile);
    if numel(vols) < 6
        error('acsViewTpm:BadTpmChannels', ...
            'TPM must contain at least six channels. %s reports %d channel(s).', ...
            tpmFile, numel(vols));
    end

    vols = vols(1:min(numel(vols), numel(opts.channelLabels)));
    dims = vols(1).dim(1:3);
    sliceIndices = opts.sliceIndices;
    if isempty(sliceIndices)
        sliceIndices = max(1, round(dims ./ 2));
    end
    sliceIndices = validateSliceIndices(sliceIndices, dims);
    styles = channelStyles(opts.channelLabels, opts.contourLevel);

    if isempty(opts.outputDir)
        opts.outputDir = fullfile(P.templateOutputRoot, 'tpm_qc');
    end

    qcFiles = {};
    figVisible = 'off';
    if opts.showFigures
        figVisible = 'on';
    end

    gridFig = makeChannelGridFigure(vols, styles, sliceIndices, opts, figVisible);
    contourFig = makeCompositeContourFigure(vols, styles, sliceIndices, opts, figVisible);

    if opts.saveFigures
        ensureDir(opts.outputDir);
        base = stripNiftiExtension(getFileName(tpmFile));

        gridFile = fullfile(opts.outputDir, [base '_channelGrid.png']);
        saveQcFigure(gridFig, gridFile);
        qcFiles{end + 1, 1} = gridFile;

        contourFile = fullfile(opts.outputDir, [base '_compositeContours.png']);
        saveQcFigure(contourFig, contourFile);
        qcFiles{end + 1, 1} = contourFile;
    end

    if ~opts.showFigures
        close(gridFig);
        close(contourFig);
    end

    out = struct();
    out.tpmFile = tpmFile;
    out.imageSize = [vols(1).dim(1:3), numel(vols)];
    out.pixelDimensions = sqrt(sum(vols(1).mat(1:3, 1:3) .^ 2, 1));
    out.channelLabels = {styles.label};
    out.sliceIndices = sliceIndices;
    out.contourLevel = opts.contourLevel;
    out.qcFiles = qcFiles;
end

function [positionalTpm, remaining] = parsePositionalTpm(varargin)
    positionalTpm = '';
    remaining = varargin;
    if isempty(varargin)
        return;
    end

    first = varargin{1};
    if ~(ischar(first) || isstring(first))
        return;
    end

    if isOptionName(first)
        return;
    end

    positionalTpm = char(first);
    remaining = varargin(2:end);
end

function tf = isOptionName(value)
    known = {'tpmfile', 'priordir', 'outputdir', 'defaulttpmname', ...
        'showfigures', 'savefigures', 'contourlevel', 'sliceindices', ...
        'channellabels', 'configfile'};
    tf = any(strcmpi(char(value), known));
end

function opts = parseInputs(positionalTpm, varargin)
    p = inputParser;
    p.FunctionName = 'acsViewTpm';
    addParameter(p, 'tpmFile', positionalTpm, @(x) ischar(x) || isstring(x));
    addParameter(p, 'priorDir', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'outputDir', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'defaultTpmName', 'defaultMonkeyTpm.nii', @(x) ischar(x) || isstring(x));
    addParameter(p, 'configFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'showFigures', true, @isBoolLike);
    addParameter(p, 'saveFigures', false, @isBoolLike);
    addParameter(p, 'contourLevel', 0.5, ...
        @(x) isnumeric(x) && isscalar(x) && x > 0 && x < 1);
    addParameter(p, 'sliceIndices', [], ...
        @(x) isempty(x) || (isnumeric(x) && numel(x) == 3));
    addParameter(p, 'channelLabels', {'gray', 'white', 'CSF', 'bone', 'skin', 'air'}, ...
        @(x) iscell(x) || isstring(x));
    parse(p, varargin{:});

    opts = p.Results;
    charFields = {'tpmFile', 'priorDir', 'outputDir', 'defaultTpmName', 'configFile'};
    for i = 1:numel(charFields)
        f = charFields{i};
        opts.(f) = expandUserPath(char(opts.(f)));
    end

    opts.showFigures = logical(opts.showFigures);
    opts.saveFigures = logical(opts.saveFigures);
    opts.contourLevel = double(opts.contourLevel);
    opts.sliceIndices = double(opts.sliceIndices(:))';
    opts.channelLabels = normalizeChannelLabels(opts.channelLabels);
end

function tf = isBoolLike(x)
    tf = (islogical(x) || isnumeric(x)) && isscalar(x);
end

function labels = normalizeChannelLabels(labels)
    if isstring(labels)
        labels = cellstr(labels(:));
    else
        labels = labels(:);
    end
    labels = cellfun(@char, labels, 'UniformOutput', false);
    labels = labels(:)';
end

function tpmFile = resolveTpmFile(P, opts)
    if ~isempty(opts.tpmFile)
        tpmFile = opts.tpmFile;
        if exist(tpmFile, 'file') ~= 2
            error('acsViewTpm:TpmNotFound', 'Specified TPM file not found: %s', tpmFile);
        end
        return;
    end

    priorDir = opts.priorDir;
    if isempty(priorDir)
        priorDir = fullfile(P.dataRoot, 'MRIs', 'atlasfiles');
    end

    candidates = {
        fullfile(priorDir, opts.defaultTpmName)
        fullfile(P.templateOutputRoot, 'atlasPriors', opts.defaultTpmName)
        fullfile(P.templateOutputRoot, 'atlasPriors', 'tpm.nii')
        };

    tpmFile = firstExistingFile(candidates);
    if ~isempty(tpmFile)
        return;
    end

    legacyTpm = fullfile(priorDir, 'myTpm.nii');
    if exist(legacyTpm, 'file') == 2
        warning('acsViewTpm:LegacyTpmName', ...
            'Using legacy TPM name myTpm.nii. Rename to %s when convenient.', ...
            opts.defaultTpmName);
        tpmFile = legacyTpm;
        return;
    end

    error('acsViewTpm:TpmNotFound', ...
        'No default TPM found under %s. Pass ''tpmFile'' explicitly.', priorDir);
end

function styles = channelStyles(labels, contourLevel)
    baseColors = {
        [1 0.2 0.1]
        [0 0.85 1]
        [0.1 0.25 1]
        [1 0.85 0]
        [0 0.8 0.25]
        [1 0 1]
        };

    n = min(numel(labels), numel(baseColors));
    styles = repmat(struct('label', '', 'channel', 1, 'color', [0 0 0], ...
        'level', contourLevel), 1, n);
    for i = 1:n
        styles(i).label = sprintf('c%d %s', i, labels{i});
        styles(i).channel = i;
        styles(i).color = baseColors{i};
        styles(i).level = contourLevel;
    end
end

function sliceIndices = validateSliceIndices(sliceIndices, dims)
    sliceIndices = round(double(sliceIndices(:))');
    if numel(sliceIndices) ~= 3
        sliceIndices = max(1, round(dims ./ 2));
    end
    sliceIndices = max([1 1 1], min(dims, sliceIndices));
end

function fig = makeChannelGridFigure(vols, styles, sliceIndices, opts, figVisible)
    nRows = numel(styles);
    nCols = 3;
    figHeight = max(960, 210 * nRows + 180);
    fig = figure('Name', 'TPM channel grid', 'Color', 'w', ...
        'Visible', figVisible, 'Units', 'pixels', 'Position', [70 50 1500 figHeight]);

    addHeader(fig, sprintf('%s | TPM channel grid', getFileName(vols(1).fname)));

    left = 0.08;
    right = 0.03;
    top = 0.09;
    bottom = 0.045;
    gapX = 0.025;
    gapY = 0.014;
    w = (1 - left - right - (nCols - 1) * gapX) / nCols;
    h = (1 - top - bottom - (nRows - 1) * gapY) / nRows;
    planeNames = {'dim 1 fixed', 'dim 2 fixed', 'dim 3 fixed'};

    for row = 1:nRows
        for col = 1:nCols
            x0 = left + (col - 1) * (w + gapX);
            y0 = 1 - top - row * h - (row - 1) * gapY;
            ax = axes(fig, 'Position', [x0 y0 w h]); %#ok<LAXES>
            S = sampleSlice(vols(styles(row).channel), col, sliceIndices(col));
            imagesc(ax, rot90(S));
            axis(ax, 'image');
            axis(ax, 'off');
            colormap(ax, gray);
            caxis(ax, [0 1]);
            if row == 1
                title(ax, sprintf('%s | slice %d', planeNames{col}, sliceIndices(col)), ...
                    'Interpreter', 'none', 'FontSize', 10, 'FontWeight', 'bold');
            end
            if col == 1
                text(ax, -0.03, 0.5, styles(row).label, ...
                    'Units', 'normalized', ...
                    'Interpreter', 'none', ...
                    'FontSize', 10, ...
                    'FontWeight', 'bold', ...
                    'HorizontalAlignment', 'right', ...
                    'VerticalAlignment', 'middle', ...
                    'Clipping', 'off');
            end
        end
    end
end

function fig = makeCompositeContourFigure(vols, styles, sliceIndices, opts, figVisible)
    fig = figure('Name', 'TPM composite contours', 'Color', 'w', ...
        'Visible', figVisible, 'Units', 'pixels', 'Position', [80 80 1500 820]);

    addHeader(fig, sprintf('%s | TPM contours at %.2f probability', ...
        getFileName(vols(1).fname), opts.contourLevel));

    axPos = threePanelPositions(0.22, 0.67);
    for dim = 1:3
        ax = axes(fig, 'Position', axPos(dim, :)); %#ok<LAXES>
        slices = cell(1, numel(styles));
        for i = 1:numel(styles)
            slices{i} = sampleSlice(vols(styles(i).channel), dim, sliceIndices(dim));
        end
        underlay = max(cat(3, slices{:}), [], 3);
        imagesc(ax, rot90(underlay));
        axis(ax, 'image');
        axis(ax, 'off');
        colormap(ax, gray);
        caxis(ax, [0 1]);
        hold(ax, 'on');
        for i = 1:numel(styles)
            if any(slices{i}(:) >= styles(i).level)
                contour(ax, rot90(slices{i}), [styles(i).level styles(i).level], ...
                    'Color', styles(i).color, 'LineWidth', 1.1);
            end
        end
        title(ax, sprintf('dim %d fixed | slice %d', dim, sliceIndices(dim)), ...
            'Interpreter', 'none', 'FontSize', 11, 'FontWeight', 'bold');
    end

    legendAx = axes(fig, 'Position', [0.05 0.04 0.90 0.11]); %#ok<LAXES>
    drawLegendPanel(legendAx, styles);
end

function addHeader(fig, headerText)
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

function drawLegendPanel(ax, styles)
    cla(ax);
    axis(ax, 'off');
    hold(ax, 'on');
    x = 0.02;
    y = 0.62;
    for i = 1:numel(styles)
        plot(ax, [x x + 0.055], [y y], ...
            'Color', styles(i).color, 'LineWidth', 2.2);
        text(ax, x + 0.065, y, styles(i).label, ...
            'Interpreter', 'none', ...
            'VerticalAlignment', 'middle', ...
            'FontSize', 11);
        x = x + 0.155;
    end
    text(ax, 0.02, 0.18, ...
        'Underlay is max probability across channels; colored lines are channel probability contours.', ...
        'Interpreter', 'none', 'FontSize', 9, 'Color', [0.25 0.25 0.25]);
    xlim(ax, [0 1]);
    ylim(ax, [0 1]);
end

function S = sampleSlice(V, dimToFix, idx)
    dims = V.dim(1:3);
    switch dimToFix
        case 1
            [A, B] = ndgrid(1:dims(2), 1:dims(3));
            X = idx .* ones(size(A));
            Y = A;
            Z = B;
        case 2
            [A, B] = ndgrid(1:dims(1), 1:dims(3));
            X = A;
            Y = idx .* ones(size(A));
            Z = B;
        case 3
            [A, B] = ndgrid(1:dims(1), 1:dims(2));
            X = A;
            Y = B;
            Z = idx .* ones(size(A));
        otherwise
            error('acsViewTpm:BadSliceDimension', ...
                'Unsupported slice dimension %d.', dimToFix);
    end
    S = spm_sample_vol(V, X, Y, Z, 1);
end

function addRoastDependencies(P)
    libDir = fullfile(P.repoRoot, 'lib');
    spmDir = fullfile(libDir, 'spm12');
    if exist(spmDir, 'dir') ~= 7
        error('acsViewTpm:MissingSpm', 'SPM folder not found: %s', spmDir);
    end
    addpath(P.repoRoot);
    if exist('setNHPulsePath', 'file') == 2
        setNHPulsePath('repoRoot', P.repoRoot, 'verbose', false);
    else
        addpath(spmDir, '-begin');
        addOptionalDependencyFolder(libDir, 'spm');
        addOptionalDependencyFolder(libDir, 'iso2mesh');
        addOptionalDependencyFolder(libDir, 'cvx');
        addOptionalDependencyFolder(libDir, 'NIFTI_20110921');
    end
end

function addOptionalDependencyFolder(libDir, folderName)
    folder = fullfile(libDir, folderName);
    if exist(folder, 'dir') == 7
        addpath(folder, '-begin');
    end
end

function ensureDir(pathIn)
    if exist(pathIn, 'dir') ~= 7
        mkdir(pathIn);
    end
end

function pathOut = firstExistingFile(candidates)
    pathOut = '';
    for i = 1:numel(candidates)
        candidate = expandUserPath(candidates{i});
        if exist(candidate, 'file') == 2
            pathOut = candidate;
            return;
        end
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

function name = getFileName(filePath)
    [~, name, ext] = fileparts(filePath);
    name = [name ext];
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
