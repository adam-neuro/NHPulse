function out = acsMakeRoastTissueLabels(t1File, tissueFiles, varargin)
% ACSMAKEROASTTISSUELABELS Convert tissue probabilities to ROAST labels.
%
% out = acsMakeRoastTissueLabels(t1File, tissueFiles) reads SPM-style
% probability maps c1..c6 and writes a single hard-label NIfTI in ROAST's
% tissue order:
%   0 background, 1 white, 2 gray, 3 CSF, 4 bone, 5 skin, 6 air.
%
% Name-value options:
%   outputDir             : destination folder [same as t1File]
%   outputPrefix          : output filename stem [<T1 stem>_roastLabels]
%   force                 : overwrite existing output [false]
%   minWinnerProbability  : below this, label as air inside mask [0.35]
%   constraintMaskFile    : optional head mask; outside is background ['']
%   showFigures           : show QC figure [false]
%   saveFigures           : save QC figure [false]
%   overlayAlpha          : label overlay transparency [0.45]
%   verbose               : print progress [false]

    if nargin < 2
        error('acsMakeRoastTissueLabels:NotEnoughInputs', ...
            'Provide a T1 file and a 1x6 cell array of tissue files.');
    end

    opts = parseInputs(varargin{:});
    tissueFiles = normalizeTissueFiles(tissueFiles);

    Vt1 = spm_vol(t1File);
    Vt1 = Vt1(1);
    if isempty(opts.outputDir)
        opts.outputDir = fileparts(t1File);
    end
    ensureDir(opts.outputDir);

    if isempty(opts.outputPrefix)
        opts.outputPrefix = [stripNiftiExtension(getFileName(t1File)) '_roastLabels'];
    end
    opts.outputPrefix = safeName(opts.outputPrefix);

    files = outputFiles(opts.outputDir, opts.outputPrefix);
    if outputsExist(files) && ~opts.force
        logMsg(opts, 'ROAST label volume already exists; reusing %s', files.labelFile);
        out = buildExistingReport(t1File, tissueFiles, Vt1, files, opts);
        return;
    end

    logMsg(opts, 'Reading active tissue probabilities for ROAST label volume.');
    [spmWinner, maxProb] = maxSpmTissueLabel(Vt1, tissueFiles);
    constraintMask = readConstraintMask(opts.constraintMaskFile, Vt1);
    lowConfidence = maxProb < opts.minWinnerProbability;
    lowConfidenceInMask = lowConfidence & constraintMask;
    spmWinner(lowConfidenceInMask) = 6;
    spmWinner(~constraintMask) = 0;

    roastLabels = spmToRoastLabels(spmWinner);
    roastLabels = clearBoundaryConnectedAir(roastLabels);
    writeLabelVolume(files.labelFile, Vt1, roastLabels, ...
        'ACS ROAST hard tissue labels: 0 background, 1 white, 2 gray, 3 CSF, 4 bone, 5 skin, 6 air');

    qcFiles = {};
    fig = [];
    if opts.showFigures || opts.saveFigures
        figVisible = 'off';
        if opts.showFigures
            figVisible = 'on';
        end
        fig = makeLabelQcFigure(t1File, Vt1, roastLabels, opts, figVisible);
        if opts.saveFigures
            qcDir = fullfile(opts.outputDir, 'qc');
            ensureDir(qcDir);
            qcFile = fullfile(qcDir, [opts.outputPrefix '_qc.png']);
            saveQcFigure(fig, qcFile);
            qcFiles = {qcFile};
        end
        if ~opts.showFigures
            close(fig);
            fig = [];
        end
    end

    out = buildReport(t1File, tissueFiles, Vt1, files, opts, roastLabels, ...
        maxProb, lowConfidenceInMask, qcFiles);
    out.figure = fig;
    outForReturn = out;
    out = removeFigureHandle(out);
    save(files.reportMat, 'out');
    writeJsonReport(files.reportJson, out);
    out = outForReturn;
end

function opts = parseInputs(varargin)
    p = inputParser;
    p.FunctionName = 'acsMakeRoastTissueLabels';
    addParameter(p, 'outputDir', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'outputPrefix', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'force', false, @isBoolLike);
    addParameter(p, 'minWinnerProbability', 0.35, ...
        @(x) isnumeric(x) && isscalar(x) && x >= 0 && x <= 1);
    addParameter(p, 'constraintMaskFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'showFigures', false, @isBoolLike);
    addParameter(p, 'saveFigures', false, @isBoolLike);
    addParameter(p, 'overlayAlpha', 0.45, ...
        @(x) isnumeric(x) && isscalar(x) && x >= 0 && x <= 1);
    addParameter(p, 'verbose', false, @isBoolLike);
    parse(p, varargin{:});

    opts = p.Results;
    opts.outputDir = expandUserPath(char(opts.outputDir));
    opts.outputPrefix = char(opts.outputPrefix);
    opts.constraintMaskFile = expandUserPath(char(opts.constraintMaskFile));
    opts.force = logical(opts.force);
    opts.showFigures = logical(opts.showFigures);
    opts.saveFigures = logical(opts.saveFigures);
    opts.verbose = logical(opts.verbose);
    opts.minWinnerProbability = double(opts.minWinnerProbability);
    opts.overlayAlpha = double(opts.overlayAlpha);
end

function tf = isBoolLike(x)
    tf = (islogical(x) || isnumeric(x)) && isscalar(x);
end

function tissueFiles = normalizeTissueFiles(tissueFiles)
    if ischar(tissueFiles) || isstring(tissueFiles)
        tissueFiles = cellstr(string(tissueFiles));
    end
    if ~iscell(tissueFiles) || numel(tissueFiles) ~= 6
        error('acsMakeRoastTissueLabels:BadTissueFiles', ...
            'tissueFiles must be a 1x6 cell array of c1..c6 filenames.');
    end
    tissueFiles = cellfun(@char, tissueFiles(:)', 'UniformOutput', false);
    for k = 1:6
        if exist(tissueFiles{k}, 'file') ~= 2
            error('acsMakeRoastTissueLabels:TissueFileNotFound', ...
                'Tissue file not found: %s', tissueFiles{k});
        end
    end
end

function files = outputFiles(outputDir, prefix)
    files = struct();
    files.labelFile = fullfile(outputDir, [prefix '.nii']);
    files.reportMat = fullfile(outputDir, [prefix '_report.mat']);
    files.reportJson = fullfile(outputDir, [prefix '_report.json']);
end

function tf = outputsExist(files)
    tf = exist(files.labelFile, 'file') == 2;
end

function [winner, maxProb] = maxSpmTissueLabel(Vref, tissueFiles)
    winner = ones(Vref.dim(1:3), 'uint8');
    V = spm_vol(tissueFiles{1});
    V = V(1);
    validateSameGrid(Vref, V, tissueFiles{1});
    maxProb = single(spm_read_vols(V));
    maxProb(~isfinite(maxProb) | maxProb < 0) = 0;

    for k = 2:6
        V = spm_vol(tissueFiles{k});
        V = V(1);
        validateSameGrid(Vref, V, tissueFiles{k});
        P = single(spm_read_vols(V));
        P(~isfinite(P) | P < 0) = 0;
        replace = P > maxProb;
        winner(replace) = uint8(k);
        maxProb(replace) = P(replace);
    end
end

function labels = spmToRoastLabels(spmWinner)
    labels = uint8(zeros(size(spmWinner)));
    labels(spmWinner == 0) = 0;
    labels(spmWinner == 1) = 2; % SPM c1 gray -> ROAST 2 gray
    labels(spmWinner == 2) = 1; % SPM c2 white -> ROAST 1 white
    labels(spmWinner == 3) = 3;
    labels(spmWinner == 4) = 4;
    labels(spmWinner == 5) = 5;
    labels(spmWinner == 6) = 6;
end

function labels = clearBoundaryConnectedAir(labels)
    air = labels == 6;
    if ~any(air(:))
        return;
    end

    boundary = false(size(labels));
    boundary(1, :, :) = true;
    boundary(end, :, :) = true;
    boundary(:, 1, :) = true;
    boundary(:, end, :) = true;
    boundary(:, :, 1) = true;
    boundary(:, :, end) = true;

    boundaryAir = air & boundary;
    if ~any(boundaryAir(:))
        return;
    end

    exteriorAir = connectedFromSeed(air, boundaryAir);
    labels(exteriorAir) = 0;
end

function reached = connectedFromSeed(mask, seed)
    if exist('imreconstruct', 'file') == 2
        reached = imreconstruct(seed, mask) > 0;
        return;
    end

    reached = false(size(mask));
    frontier = seed & mask;
    se = false(3, 3, 3);
    se(2, 2, 1) = true;
    se(2, 2, 3) = true;
    se(2, 1, 2) = true;
    se(2, 3, 2) = true;
    se(1, 2, 2) = true;
    se(3, 2, 2) = true;

    while any(frontier(:))
        reached = reached | frontier;
        grown = imdilate(frontier, se) & mask & ~reached;
        frontier = grown;
    end
end

function mask = readConstraintMask(maskFile, Vref)
    if isempty(maskFile)
        mask = true(Vref.dim(1:3));
        return;
    end
    if exist(maskFile, 'file') ~= 2
        error('acsMakeRoastTissueLabels:ConstraintMaskNotFound', ...
            'Constraint mask file not found: %s', maskFile);
    end
    Vm = spm_vol(maskFile);
    Vm = Vm(1);
    validateSameGrid(Vref, Vm, maskFile);
    mask = spm_read_vols(Vm) > 0.5;
end

function validateSameGrid(Vref, V, fileName)
    if any(Vref.dim(1:3) ~= V.dim(1:3))
        error('acsMakeRoastTissueLabels:DimensionMismatch', ...
            '%s has dimensions %s but expected %s.', ...
            fileName, mat2str(V.dim(1:3)), mat2str(Vref.dim(1:3)));
    end
    if max(abs(Vref.mat(:) - V.mat(:))) > 1e-4
        error('acsMakeRoastTissueLabels:AffineMismatch', ...
            '%s is not in the same affine space as %s.', fileName, Vref.fname);
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
    spm_write_vol(Vout, labels);
end

function fig = makeLabelQcFigure(t1File, Vref, labels, opts, figVisible)
    t1 = single(spm_read_vols(Vref));
    fig = figure('Name', 'ROAST hard label QC', 'Color', 'w', ...
        'Visible', figVisible, 'Units', 'pixels', 'Position', [80 80 1500 820]);
    addFigureHeader(fig, sprintf('%s | ROAST hard labels | min p %.2f', ...
        getFileName(t1File), opts.minWinnerProbability));

    dims = Vref.dim(1:3);
    sliceInd = max(1, round(dims ./ 2));
    planeLabels = {'Sagittal dim 1', 'Coronal dim 2', 'Axial dim 3'};
    clim = robustClim(t1);
    axPos = threePanelPositions(0.22, 0.67);
    styles = labelStyles();

    for dimToFix = 1:3
        ax = axes(fig, 'Position', axPos(dimToFix, :)); %#ok<LAXES>
        idx = sliceInd(dimToFix);
        t1Slice = rawSlice(t1, dimToFix, idx);
        labelSlice = rawSlice(labels, dimToFix, idx);
        imagesc(ax, rot90(t1Slice));
        axis(ax, 'image');
        axis(ax, 'off');
        colormap(ax, gray);
        caxis(ax, clim);
        hold(ax, 'on');
        rgb = labelSliceRgb(labelSlice, styles);
        overlay = image(ax, rot90Rgb(rgb));
        showMask = labelSlice > 0 & labelSlice ~= 6;
        set(overlay, 'AlphaData', rot90(double(showMask) .* opts.overlayAlpha));
        title(ax, sprintf('%s = %d', planeLabels{dimToFix}, idx), ...
            'Interpreter', 'none', 'FontSize', 11, 'FontWeight', 'bold');
    end

    legendAx = axes(fig, 'Position', [0.05 0.04 0.90 0.11]); %#ok<LAXES>
    drawLegendPanel(legendAx, styles);
end

function styles = labelStyles()
    styles = struct( ...
        'labelId', {1, 2, 3, 4, 5, 6}, ...
        'label', {'1 white', '2 gray', '3 CSF', '4 bone', '5 skin', '6 air'}, ...
        'color', {[0 0.85 1], [1 0.2 0.1], [0.1 0.25 1], [1 0.85 0], [0 0.8 0.25], [1 0 1]});
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
            error('acsMakeRoastTissueLabels:BadSliceDimension', ...
                'Unsupported slice dimension %d.', dimToFix);
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

function drawLegendPanel(ax, styles)
    cla(ax);
    axis(ax, 'off');
    hold(ax, 'on');
    x = 0.02;
    y = 0.62;
    for i = 1:numel(styles)
        style = styles(i);
        if style.labelId == 6
            continue;
        end
        patch(ax, [x x + 0.035 x + 0.035 x], [y - 0.08 y - 0.08 y + 0.08 y + 0.08], ...
            style.color, 'EdgeColor', [0.2 0.2 0.2], 'LineWidth', 0.5);
        text(ax, x + 0.045, y, style.label, ...
            'Interpreter', 'none', ...
            'VerticalAlignment', 'middle', ...
            'FontSize', 11);
        x = x + 0.15;
    end
    text(ax, 0.02, 0.18, ...
        'Background and air are hidden in the overlay; low-confidence voxels inside the head are assigned to air.', ...
        'Interpreter', 'none', 'FontSize', 9, 'Color', [0.25 0.25 0.25]);
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

function out = buildExistingReport(t1File, tissueFiles, Vref, files, opts)
    out = struct();
    out.t1File = t1File;
    out.tissueFiles = tissueFiles(:);
    out.labelFile = files.labelFile;
    out.files = files;
    out.imageSize = Vref.dim(1:3);
    out.reusedExisting = true;
    out.qcFiles = {};
    out.parameters = reportParameters(opts);
end

function out = buildReport(t1File, tissueFiles, Vref, files, opts, labels, ...
        maxProb, lowConfidence, qcFiles)
    out = struct();
    out.createdOn = char(datetime('now'));
    out.t1File = t1File;
    out.tissueFiles = tissueFiles(:);
    out.labelFile = files.labelFile;
    out.files = files;
    out.imageSize = Vref.dim(1:3);
    out.voxelCounts = labelVoxelCounts(labels);
    out.lowConfidenceVoxelCount = nnz(lowConfidence);
    out.maxProbabilityStats = scalarStats(maxProb);
    out.qcFiles = qcFiles(:);
    out.parameters = reportParameters(opts);
end

function params = reportParameters(opts)
    params = struct( ...
        'minWinnerProbability', opts.minWinnerProbability, ...
        'constraintMaskFile', opts.constraintMaskFile, ...
        'overlayAlpha', opts.overlayAlpha);
end

function counts = labelVoxelCounts(labels)
    names = {'white', 'gray', 'csf', 'bone', 'skin', 'air'};
    counts = struct();
    counts.background = nnz(labels == 0);
    for k = 1:numel(names)
        counts.(names{k}) = nnz(labels == k);
    end
end

function stats = scalarStats(V)
    vals = double(V(:));
    vals = vals(isfinite(vals));
    stats = struct();
    stats.min = min(vals);
    stats.max = max(vals);
    stats.mean = mean(vals);
    stats.median = median(vals);
end

function report = removeFigureHandle(report)
    if isfield(report, 'figure')
        report = rmfield(report, 'figure');
    end
end

function saveQcFigure(fig, qcFile)
    try
        exportgraphics(fig, qcFile, 'Resolution', 150);
    catch
        saveas(fig, qcFile);
    end
end

function writeJsonReport(reportJson, report)
    fid = fopen(reportJson, 'w');
    if fid == -1
        error('acsMakeRoastTissueLabels:CannotWriteJson', ...
            'Could not write report JSON: %s', reportJson);
    end
    cleaner = onCleanup(@() fclose(fid));
    fprintf(fid, '%s', jsonencode(report, 'PrettyPrint', true));
    clear cleaner;
end

function deleteDerivedNifti(fileName)
    if exist(fileName, 'file') == 2
        delete(fileName);
    end
    [folder, base] = fileparts(fileName);
    matFile = fullfile(folder, [base '.mat']);
    if exist(matFile, 'file') == 2
        delete(matFile);
    end
end

function ensureDir(pathIn)
    if exist(pathIn, 'dir') ~= 7
        mkdir(pathIn);
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

function name = safeName(value)
    name = regexprep(char(value), '[^a-zA-Z0-9_]', '_');
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

function logMsg(opts, varargin)
    if opts.verbose
        fprintf([varargin{1} '\n'], varargin{2:end});
    end
end
