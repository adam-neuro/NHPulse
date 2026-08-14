function out = acsMakeSubjectMasks(t1Input, varargin)
% ACSMAKESUBJECTMASKS Create subject-derived masks from a T1 anatomy.
%
% out = acsMakeSubjectMasks(t1File) estimates a head mask from a T1 NIfTI
% without using tissue priors. It writes ignored preprocessing products that
% can be used for QC, masking SPM segmentation, and later brain-focused
% registration experiments.
%
% Masks are written in the same voxel grid and affine as the input T1:
%   headMask        : largest filled foreground object
%   skinShellMask   : outer shell of the head mask
%   innerHeadMask   : head mask eroded inward from the skin
%   brainSearchMask : loose, further-eroded interior mask for registration
%   brainSearchT1   : T1 with voxels outside brainSearchMask set to zero
%
% Name-value options:
%   outputDir          : destination folder [same as T1]
%   outputPrefix       : output filename stem [<T1 stem>]
%   force              : overwrite existing outputs [false]
%   showFigures        : show QC figure [false]
%   saveFigures        : save QC figure [false]
%   verbose            : print progress [false]
%   headThreshold      : explicit normalized intensity threshold [[]]
%   headThresholdScale : multiplier for Otsu threshold [0.50]
%   minHeadThreshold   : lower bound for threshold [0.08]
%   closeRadiusMm      : head mask closing radius in mm [1.5]
%   minIslandVox       : remove components smaller than this [2000]
%   skinShellMm        : outer shell thickness in mm [1.5]
%   innerErodeMm       : inner-head erosion radius in mm [3]
%   brainErodeMm       : loose brain-search erosion radius in mm [8]

    if nargin < 1 || isempty(t1Input)
        t1Input = 'M2107';
    end

    opts = parseInputs(varargin{:});
    P = acsPaths('configFile', opts.configFile);
    addRoastDependencies(P);

    t1File = resolveT1Input(t1Input, opts);
    V = spm_vol(t1File);
    if numel(V) ~= 1
        error('acsMakeSubjectMasks:MultiVolumeT1', ...
            'Expected a single-volume T1 NIfTI: %s', t1File);
    end

    if isempty(opts.outputDir)
        opts.outputDir = fileparts(t1File);
    end
    ensureDir(opts.outputDir);

    if isempty(opts.outputPrefix)
        opts.outputPrefix = stripNiftiExtension(getFileName(t1File));
    end
    opts.outputPrefix = safeName(opts.outputPrefix);

    files = maskOutputFiles(opts.outputDir, opts.outputPrefix);
    if outputsExist(files) && ~opts.force
        logMsg(opts, 'Subject mask products already exist; reusing %s', opts.outputDir);
        out = buildExistingReport(t1File, V, files, opts);
        return;
    end

    logMsg(opts, 'Reading T1 for mask generation: %s', t1File);
    t1 = single(spm_read_vols(V));
    [t1Norm, intensity] = normalizeIntensity(t1);

    [headMask, thresholdInfo] = estimateHeadMask(t1Norm, V, opts);
    skinShellMask = headMask & ~erodeMask(headMask, opts.skinShellMm, voxelSizesFromMat(V.mat));
    innerHeadMask = erodeMask(headMask, opts.innerErodeMm, voxelSizesFromMat(V.mat));
    innerHeadMask = keepLargest3D(innerHeadMask);
    brainSearchMask = erodeMask(headMask, opts.brainErodeMm, voxelSizesFromMat(V.mat));
    brainSearchMask = keepLargest3D(brainSearchMask);
    brainSearchT1 = t1;
    brainSearchT1(~brainSearchMask) = 0;

    writeMaskVolume(files.headMask, V, headMask, 'ACS subject head mask');
    writeMaskVolume(files.skinShellMask, V, skinShellMask, 'ACS subject skin shell mask');
    writeMaskVolume(files.innerHeadMask, V, innerHeadMask, 'ACS subject inner head mask');
    writeMaskVolume(files.brainSearchMask, V, brainSearchMask, 'ACS loose brain search mask');
    writeScalarVolume(files.brainSearchT1, V, brainSearchT1, 'ACS T1 masked by loose brain search mask');

    qcFiles = {};
    fig = [];
    if opts.showFigures || opts.saveFigures
        figVisible = 'off';
        if opts.showFigures
            figVisible = 'on';
        end
        fig = makeMaskQcFigure(t1, headMask, skinShellMask, innerHeadMask, ...
            brainSearchMask, V, opts, figVisible);
        if opts.saveFigures
            qcDir = fullfile(opts.outputDir, 'qc');
            ensureDir(qcDir);
            qcFile = fullfile(qcDir, [opts.outputPrefix '_subjectMasksQc.png']);
            saveQcFigure(fig, qcFile);
            qcFiles = {qcFile};
        end
        if ~opts.showFigures
            close(fig);
            fig = [];
        end
    end

    out = buildReport(t1File, V, files, opts, intensity, thresholdInfo, headMask, ...
        skinShellMask, innerHeadMask, brainSearchMask, qcFiles);
    out.figure = fig;
    save(files.reportMat, 'out');
    writeJsonReport(files.reportJson, removeFigureHandle(out));
end

function opts = parseInputs(varargin)
    p = inputParser;
    p.FunctionName = 'acsMakeSubjectMasks';
    addParameter(p, 't1File', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'outputDir', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'outputPrefix', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'configFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'force', false, @isBoolLike);
    addParameter(p, 'showFigures', false, @isBoolLike);
    addParameter(p, 'saveFigures', false, @isBoolLike);
    addParameter(p, 'verbose', false, @isBoolLike);
    addParameter(p, 'headThreshold', [], ...
        @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x > 0 && x < 1));
    addParameter(p, 'headThresholdScale', 0.50, ...
        @(x) isnumeric(x) && isscalar(x) && x > 0);
    addParameter(p, 'minHeadThreshold', 0.08, ...
        @(x) isnumeric(x) && isscalar(x) && x >= 0 && x < 1);
    addParameter(p, 'closeRadiusMm', 1.5, ...
        @(x) isnumeric(x) && isscalar(x) && x >= 0);
    addParameter(p, 'minIslandVox', 2000, ...
        @(x) isnumeric(x) && isscalar(x) && x >= 0);
    addParameter(p, 'skinShellMm', 1.5, ...
        @(x) isnumeric(x) && isscalar(x) && x >= 0);
    addParameter(p, 'innerErodeMm', 3, ...
        @(x) isnumeric(x) && isscalar(x) && x >= 0);
    addParameter(p, 'brainErodeMm', 8, ...
        @(x) isnumeric(x) && isscalar(x) && x >= 0);
    parse(p, varargin{:});

    opts = p.Results;
    charFields = {'t1File', 'outputDir', 'outputPrefix', 'configFile'};
    for i = 1:numel(charFields)
        f = charFields{i};
        opts.(f) = expandUserPath(char(opts.(f)));
    end
    opts.force = logical(opts.force);
    opts.showFigures = logical(opts.showFigures);
    opts.saveFigures = logical(opts.saveFigures);
    opts.verbose = logical(opts.verbose);
    opts.headThreshold = double(opts.headThreshold);
    opts.headThresholdScale = double(opts.headThresholdScale);
    opts.minHeadThreshold = double(opts.minHeadThreshold);
    opts.closeRadiusMm = double(opts.closeRadiusMm);
    opts.minIslandVox = round(double(opts.minIslandVox));
    opts.skinShellMm = double(opts.skinShellMm);
    opts.innerErodeMm = double(opts.innerErodeMm);
    opts.brainErodeMm = double(opts.brainErodeMm);
end

function tf = isBoolLike(x)
    tf = (islogical(x) || isnumeric(x)) && isscalar(x);
end

function t1File = resolveT1Input(t1Input, opts)
    if ~isempty(opts.t1File)
        t1File = opts.t1File;
    else
        candidate = expandUserPath(char(t1Input));
        if exist(candidate, 'file') == 2
            t1File = candidate;
        else
            subjectId = char(t1Input);
            subjectRoot = acsSubjectPath(subjectId, 'output', ...
                'configFile', opts.configFile);
            [~, subjectLabel] = fileparts(subjectRoot);
            anatomyDir = acsSubjectPath(subjectLabel, 'anatomyWork', ...
                'configFile', opts.configFile);
            t1File = fullfile(anatomyDir, [safeName(subjectLabel) '_T1.nii']);
        end
    end

    if exist(t1File, 'file') ~= 2
        error('acsMakeSubjectMasks:T1NotFound', 'T1 NIfTI not found: %s', t1File);
    end
end

function files = maskOutputFiles(outputDir, prefix)
    files = struct();
    files.headMask = fullfile(outputDir, [prefix '_headMask.nii']);
    files.skinShellMask = fullfile(outputDir, [prefix '_skinShellMask.nii']);
    files.innerHeadMask = fullfile(outputDir, [prefix '_innerHeadMask.nii']);
    files.brainSearchMask = fullfile(outputDir, [prefix '_brainSearchMask.nii']);
    files.brainSearchT1 = fullfile(outputDir, [prefix '_brainSearchT1.nii']);
    files.reportMat = fullfile(outputDir, [prefix '_subjectMasksReport.mat']);
    files.reportJson = fullfile(outputDir, [prefix '_subjectMasksReport.json']);
end

function tf = outputsExist(files)
    tf = exist(files.headMask, 'file') == 2 && ...
        exist(files.skinShellMask, 'file') == 2 && ...
        exist(files.innerHeadMask, 'file') == 2 && ...
        exist(files.brainSearchMask, 'file') == 2 && ...
        exist(files.brainSearchT1, 'file') == 2;
end

function [t1Norm, intensity] = normalizeIntensity(t1)
    vals = double(t1(:));
    vals = vals(isfinite(vals) & vals > 0);
    if isempty(vals)
        error('acsMakeSubjectMasks:EmptyIntensity', ...
            'T1 volume has no positive finite voxels.');
    end
    if numel(vals) > 1000000
        vals = vals(round(linspace(1, numel(vals), 1000000)));
    end

    pLow = prctile(vals, 0.5);
    pHigh = prctile(vals, 99.5);
    if pHigh <= pLow
        pLow = min(vals);
        pHigh = max(vals);
    end
    if pHigh <= pLow
        pHigh = pLow + 1;
    end

    t1Norm = (single(t1) - single(pLow)) ./ single(pHigh - pLow);
    t1Norm(~isfinite(t1Norm)) = 0;
    t1Norm = max(0, min(1, t1Norm));

    intensity = struct();
    intensity.pLow = pLow;
    intensity.pHigh = pHigh;
end

function [headMask, thresholdInfo] = estimateHeadMask(t1Norm, V, opts)
    vals = double(t1Norm(:));
    vals = vals(isfinite(vals) & vals > 0);
    if isempty(opts.headThreshold)
        if exist('graythresh', 'file') == 2
            otsuThreshold = graythresh(vals);
        else
            otsuThreshold = prctile(vals, 35);
        end
        threshold = max(opts.minHeadThreshold, opts.headThresholdScale * otsuThreshold);
    else
        otsuThreshold = NaN;
        threshold = opts.headThreshold;
    end

    headMask = t1Norm > threshold;
    headMask = removeSmall3D(headMask, opts.minIslandVox);
    headMask = keepLargest3D(headMask);
    headMask = closeMask(headMask, opts.closeRadiusMm, voxelSizesFromMat(V.mat));
    headMask = fillHoles3D(headMask);
    headMask = keepLargest3D(headMask);

    if nnz(headMask) == 0
        error('acsMakeSubjectMasks:EmptyHeadMask', ...
            'Head mask is empty. Try lowering headThreshold.');
    end

    thresholdInfo = struct();
    thresholdInfo.threshold = threshold;
    thresholdInfo.otsuThreshold = otsuThreshold;
    thresholdInfo.headThresholdWasSpecified = ~isempty(opts.headThreshold);
end

function A = closeMask(A, radiusMm, voxelSize)
    if radiusMm <= 0
        return;
    end
    se = ellipsoidStrel(radiusMm, voxelSize);
    A = imdilate(A, se);
    A = imerode(A, se);
end

function A = erodeMask(A, radiusMm, voxelSize)
    if radiusMm <= 0
        return;
    end
    se = ellipsoidStrel(radiusMm, voxelSize);
    A = imerode(A, se);
end

function se = ellipsoidStrel(radiusMm, voxelSize)
    rad = max(1, round(radiusMm ./ voxelSize));
    [x, y, z] = ndgrid(-rad(1):rad(1), -rad(2):rad(2), -rad(3):rad(3));
    se = (x ./ max(rad(1), 1)).^2 + ...
        (y ./ max(rad(2), 1)).^2 + ...
        (z ./ max(rad(3), 1)).^2 <= 1;
end

function Afilled = fillHoles3D(A)
    A = logical(A);
    sz = size(A);
    B = ~A;
    boundary = false(sz);
    boundary(1,:,:) = true;
    boundary(end,:,:) = true;
    boundary(:,1,:) = true;
    boundary(:,end,:) = true;
    boundary(:,:,1) = true;
    boundary(:,:,end) = true;

    CC = bwconncomp(B, 6);
    exterior = false(numel(A), 1);
    b = boundary(:);
    for i = 1:CC.NumObjects
        idx = CC.PixelIdxList{i};
        if any(b(idx))
            exterior(idx) = true;
        end
    end
    Afilled = ~reshape(exterior, sz);
end

function A = keepLargest3D(A)
    A = logical(A);
    CC = bwconncomp(A, 26);
    if CC.NumObjects < 1
        return;
    end
    [~, idx] = max(cellfun(@numel, CC.PixelIdxList));
    A(:) = false;
    A(CC.PixelIdxList{idx}) = true;
end

function A = removeSmall3D(A, minVox)
    A = logical(A);
    if minVox <= 0
        return;
    end
    CC = bwconncomp(A, 26);
    for i = 1:CC.NumObjects
        if numel(CC.PixelIdxList{i}) < minVox
            A(CC.PixelIdxList{i}) = false;
        end
    end
end

function writeMaskVolume(fileName, Vref, mask, description)
    writeScalarVolume(fileName, Vref, single(mask), description);
end

function writeScalarVolume(fileName, Vref, data, description)
    deleteDerivedNifti(fileName);
    Vout = Vref;
    Vout.fname = fileName;
    Vout.dim = size(data);
    Vout.dt = [spm_type('float32') spm_platform('bigend')];
    Vout.n = [1 1];
    Vout.private = [];
    Vout.pinfo = [1; 0; 0];
    Vout.descrip = description;
    spm_write_vol(Vout, single(data));
end

function fig = makeMaskQcFigure(t1, headMask, skinShellMask, innerHeadMask, ...
        brainSearchMask, V, opts, figVisible)
    fig = figure('Name', 'Subject mask QC', 'Color', 'w', ...
        'Visible', figVisible, 'Units', 'pixels', 'Position', [80 80 1500 820]);
    addFigureHeader(fig, sprintf('%s | subject-derived masks', getFileName(V.fname)));

    dims = V.dim(1:3);
    sliceInd = max(1, round(dims ./ 2));
    labels = {'Sagittal dim 1', 'Coronal dim 2', 'Axial dim 3'};
    clim = robustClim(t1);
    axPos = threePanelPositions(0.22, 0.67);
    styles = maskStyles();

    for dimToFix = 1:3
        ax = axes(fig, 'Position', axPos(dimToFix, :)); %#ok<LAXES>
        idx = sliceInd(dimToFix);
        S = rawSlice(t1, dimToFix, idx);
        imagesc(ax, rot90(S));
        axis(ax, 'image');
        axis(ax, 'off');
        colormap(ax, gray);
        caxis(ax, clim);
        hold(ax, 'on');
        contourMask(ax, rawSlice(headMask, dimToFix, idx), styles(1));
        contourMask(ax, rawSlice(skinShellMask, dimToFix, idx), styles(2));
        contourMask(ax, rawSlice(innerHeadMask, dimToFix, idx), styles(3));
        contourMask(ax, rawSlice(brainSearchMask, dimToFix, idx), styles(4));
        title(ax, sprintf('%s = %d', labels{dimToFix}, idx), ...
            'Interpreter', 'none', 'FontSize', 11, 'FontWeight', 'bold');
    end

    legendAx = axes(fig, 'Position', [0.05 0.04 0.90 0.11]); %#ok<LAXES>
    drawLegendPanel(legendAx, styles);
end

function styles = maskStyles()
    styles = struct( ...
        'label', {'head', 'skin shell', 'inner head', 'brain search'}, ...
        'color', {[0 0.8 0.25], [1 0.85 0], [0 0.85 1], [1 0.15 0.1]}, ...
        'lineWidth', {1.4, 1.2, 1.2, 1.3});
end

function contourMask(ax, maskSlice, style)
    if any(maskSlice(:))
        contour(ax, rot90(double(maskSlice)), [0.5 0.5], ...
            'Color', style.color, 'LineWidth', style.lineWidth);
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
            error('acsMakeSubjectMasks:BadSliceDimension', ...
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
    y = 0.60;
    for i = 1:numel(styles)
        style = styles(i);
        plot(ax, [x x + 0.055], [y y], ...
            'Color', style.color, 'LineWidth', max(style.lineWidth, 2));
        text(ax, x + 0.065, y, style.label, ...
            'Interpreter', 'none', ...
            'VerticalAlignment', 'middle', ...
            'FontSize', 11);
        x = x + 0.18;
    end
    text(ax, 0.02, 0.18, ...
        'Masks are subject-derived from T1 intensity and morphology; no TPM priors are used here.', ...
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

function report = buildExistingReport(t1File, V, files, opts)
    report = struct();
    report.t1File = t1File;
    report.outputDir = opts.outputDir;
    report.files = files;
    report.imageSize = V.dim(1:3);
    report.voxelSize = voxelSizesFromMat(V.mat);
    report.reusedExisting = true;
    report.qcFiles = {};
end

function out = buildReport(t1File, V, files, opts, intensity, thresholdInfo, headMask, ...
        skinShellMask, innerHeadMask, brainSearchMask, qcFiles)
    out = struct();
    out.t1File = t1File;
    out.createdOn = char(datetime('now'));
    out.outputDir = opts.outputDir;
    out.files = files;
    out.imageSize = V.dim(1:3);
    out.voxelSize = voxelSizesFromMat(V.mat);
    out.intensity = intensity;
    out.threshold = thresholdInfo;
    out.parameters = struct( ...
        'headThreshold', opts.headThreshold, ...
        'headThresholdScale', opts.headThresholdScale, ...
        'minHeadThreshold', opts.minHeadThreshold, ...
        'closeRadiusMm', opts.closeRadiusMm, ...
        'minIslandVox', opts.minIslandVox, ...
        'skinShellMm', opts.skinShellMm, ...
        'innerErodeMm', opts.innerErodeMm, ...
        'brainErodeMm', opts.brainErodeMm);
    out.voxelCounts = struct( ...
        'headMask', nnz(headMask), ...
        'skinShellMask', nnz(skinShellMask), ...
        'innerHeadMask', nnz(innerHeadMask), ...
        'brainSearchMask', nnz(brainSearchMask));
    out.qcFiles = qcFiles(:);
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
        error('acsMakeSubjectMasks:CannotWriteJson', ...
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

function vx = voxelSizesFromMat(M)
    vx = sqrt(sum(M(1:3, 1:3) .^ 2, 1));
    if any(~isfinite(vx)) || any(vx == 0)
        vx = [1 1 1];
    end
end

function addRoastDependencies(P)
    libDir = fullfile(P.repoRoot, 'lib');
    spmDir = fullfile(libDir, 'spm12');
    if exist(spmDir, 'dir') ~= 7
        error('acsMakeSubjectMasks:MissingSpm', 'SPM folder not found: %s', spmDir);
    end
    addpath(genpath(libDir));
    addpath(P.repoRoot);
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
