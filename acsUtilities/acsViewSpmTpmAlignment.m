function out = acsViewSpmTpmAlignment(subjectId, varargin)
% ACSVIEWSPMTPMALIGNMENT Visualize SPM's TPM-to-subject alignment.
%
% out = acsViewSpmTpmAlignment('M2107') loads the subject's SPM
% segmentation outputs, samples the macaque TPM into the subject T1 grid,
% and displays QC figures for the affine-only and final-warped priors.
%
% This diagnostic sits between "the TPM looks right by itself" and
% "native c1/c2/c3 outputs look right". It asks whether SPM is presenting
% the tissue priors to the individual anatomy in the expected orientation.
%
% Name-value options:
%   segmentationTag      : segmentation output subfolder ['']
%   outputDir            : explicit segmentation output folder ['']
%   seg8File             : explicit SPM *_seg8.mat file ['']
%   t1File               : explicit segmentation T1 NIfTI ['']
%   tpmFile              : explicit TPM NIfTI fallback ['']
%   stages               : 'affine', 'final', or {'affine','final'}
%   planeMode            : 'spm' raw voxel dims or 'anatomical' ['spm']
%   anatomicalAxes       : 'scanner', 'macaqueSphinx', or struct ['scanner']
%   planeVoxelDims       : manual [sagittal coronal axial] voxel dims [[]]
%   sliceIndices         : [dim1 dim2 dim3] slices; central slices if []
%   qcTissues            : TPM tissues to contour [{'gray','white','csf','bone','skin'}]
%   contourLevel         : probability contour level [0.5]
%   showFigures          : show QC figures [true]
%   saveFigures          : save PNG figures [false]
%   configFile           : optional local.paths.json override ['']

    if nargin < 1 || isempty(subjectId)
        subjectId = 'M2107';
    end

    opts = parseInputs(varargin{:});
    P = acsPaths('configFile', opts.configFile);
    addRoastDependencies(P);

    [seg8File, workT1, outputDir, sourceT1, tpmFileFromReport] = ...
        resolveSegmentationInputs(subjectId, opts);
    Vref = spm_vol(workT1);
    Vref = Vref(1);

    res = load(seg8File);
    tpm = resolveSegmentationTpm(res, opts, tpmFileFromReport);

    dims = Vref.dim(1:3);
    sliceInd = opts.sliceIndices;
    if isempty(sliceInd)
        sliceInd = max(1, round(dims ./ 2));
    end
    sliceInd = validateSliceIndices(sliceInd, dims);

    axisInfo = displayAxisInfo(sourceT1, opts);
    planes = axisInfo.planes;
    styles = selectedTissueStyles(opts.qcTissues, opts.contourLevel);
    clim = robustClim(spm_read_vols(Vref));

    figVisible = 'off';
    if opts.showFigures
        figVisible = 'on';
    end

    qcFiles = {};
    figs = {};
    for i = 1:numel(opts.stages)
        stage = opts.stages(i);
        transform = buildTpmTransform(res, tpm, Vref, stage);
        fig = makeAlignmentFigure(Vref, tpm, transform, planes, ...
            sliceInd, clim, styles, axisInfo, opts, figVisible);
        figs{end + 1, 1} = fig; %#ok<AGROW>

        if opts.saveFigures
            qcDir = fullfile(outputDir, 'qc');
            ensureDir(qcDir);
            qcFile = fullfile(qcDir, sprintf('%s_spmTpmAlignment_%s.png', ...
                stripNiftiExtension(getFileName(workT1)), stage.name));
            saveQcFigure(fig, qcFile);
            qcFiles{end + 1, 1} = qcFile; %#ok<AGROW>
        end
    end

    if ~opts.showFigures
        for i = 1:numel(figs)
            close(figs{i});
        end
    end

    out = struct();
    out.subjectId = char(subjectId);
    out.seg8File = seg8File;
    out.t1File = workT1;
    out.sourceT1 = sourceT1;
    out.outputDir = outputDir;
    out.tpmFile = tpmFileFromReport;
    out.planeMode = opts.planeMode;
    out.stages = {opts.stages.name};
    out.sliceIndices = sliceInd;
    out.axisInfo = axisInfo;
    out.qcTissues = {styles.label};
    out.contourLevel = opts.contourLevel;
    out.qcFiles = qcFiles;
end

function opts = parseInputs(varargin)
    p = inputParser;
    p.FunctionName = 'acsViewSpmTpmAlignment';
    addParameter(p, 'segmentationTag', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'outputDir', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'seg8File', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 't1File', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'tpmFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'stages', {'affine', 'final'}, ...
        @(x) ischar(x) || isstring(x) || iscell(x));
    addParameter(p, 'planeMode', 'spm', @(x) ischar(x) || isstring(x));
    addParameter(p, 'anatomicalAxes', 'scanner', ...
        @(x) ischar(x) || isstring(x) || isstruct(x));
    addParameter(p, 'planeVoxelDims', [], ...
        @(x) isempty(x) || (isnumeric(x) && numel(x) == 3));
    addParameter(p, 'sliceIndices', [], ...
        @(x) isempty(x) || (isnumeric(x) && numel(x) == 3));
    addParameter(p, 'qcTissues', {'gray', 'white', 'csf', 'bone', 'skin'}, ...
        @(x) ischar(x) || isstring(x) || iscell(x));
    addParameter(p, 'contourLevel', 0.5, ...
        @(x) isnumeric(x) && isscalar(x) && x > 0 && x < 1);
    addParameter(p, 'showFigures', true, @isBoolLike);
    addParameter(p, 'saveFigures', false, @isBoolLike);
    addParameter(p, 'configFile', '', @(x) ischar(x) || isstring(x));
    parse(p, varargin{:});

    opts = p.Results;
    charFields = {'segmentationTag', 'outputDir', 'seg8File', 't1File', ...
        'tpmFile', 'configFile'};
    for i = 1:numel(charFields)
        f = charFields{i};
        opts.(f) = expandUserPath(char(opts.(f)));
    end

    opts.stages = normalizeStages(opts.stages);
    opts.planeMode = normalizePlaneMode(opts.planeMode);
    opts.planeVoxelDims = double(opts.planeVoxelDims(:))';
    opts.sliceIndices = double(opts.sliceIndices(:))';
    opts.qcTissues = normalizeTissueList(opts.qcTissues);
    opts.contourLevel = double(opts.contourLevel);
    opts.showFigures = logical(opts.showFigures);
    opts.saveFigures = logical(opts.saveFigures);
end

function planeMode = normalizePlaneMode(planeMode)
    switch lower(strtrim(char(planeMode)))
        case {'spm', 'voxel', 'raw', 'rawvoxel'}
            planeMode = 'spm';
        case {'anatomical', 'anatomy', 'display'}
            planeMode = 'anatomical';
        otherwise
            error('acsViewSpmTpmAlignment:UnknownPlaneMode', ...
                'Unknown planeMode "%s". Use "spm" or "anatomical".', ...
                char(planeMode));
    end
end

function tf = isBoolLike(x)
    tf = (islogical(x) || isnumeric(x)) && isscalar(x);
end

function stages = normalizeStages(stages)
    if ischar(stages) || isstring(stages)
        stages = cellstr(string(stages));
    else
        stages = cellfun(@char, stages(:), 'UniformOutput', false);
    end

    if any(strcmpi(stages, 'all'))
        stages = {'affine', 'final'};
    end

    base = struct( ...
        'name', {'affine', 'final'}, ...
        'label', {'Initial affine TPM', 'Final SPM-warped TPM'}, ...
        'useWarp', {false, true});

    out = repmat(base(1), 0, 1);
    for i = 1:numel(stages)
        idx = find(strcmpi(stages{i}, {base.name}), 1);
        if isempty(idx)
            error('acsViewSpmTpmAlignment:UnknownStage', ...
                'Unknown stage "%s". Use affine, final, or all.', stages{i});
        end
        out(end + 1) = base(idx); %#ok<AGROW>
    end
    stages = out;
end

function tissues = normalizeTissueList(tissues)
    if ischar(tissues) || isstring(tissues)
        tissues = cellstr(string(tissues));
    elseif iscell(tissues)
        tissues = cellfun(@char, tissues(:), 'UniformOutput', false);
    else
        tissues = {'gray', 'white', 'csf', 'bone', 'skin'};
    end
    tissues = tissues(:)';
end

function [seg8File, workT1, outputDir, sourceT1, tpmFileFromReport] = ...
        resolveSegmentationInputs(subjectId, opts)
    outputDir = opts.outputDir;
    if isempty(outputDir)
        outputDir = acsSubjectPath(subjectId, 'segmentationWork', ...
            'configFile', opts.configFile);
    end
    if ~isempty(opts.segmentationTag)
        outputDir = fullfile(outputDir, safeName(opts.segmentationTag));
    end

    seg8File = opts.seg8File;
    if isempty(seg8File)
        matches = dir(fullfile(outputDir, '*_seg8.mat'));
        if isempty(matches)
            error('acsViewSpmTpmAlignment:MissingSeg8', ...
                'No *_seg8.mat file found in %s. Run acsSegmentAnatomyWithTpm first.', ...
                outputDir);
        elseif numel(matches) > 1
            error('acsViewSpmTpmAlignment:AmbiguousSeg8', ...
                'Multiple *_seg8.mat files found in %s. Pass seg8File explicitly.', ...
                outputDir);
        end
        seg8File = fullfile(outputDir, matches(1).name);
    elseif exist(seg8File, 'file') ~= 2
        error('acsViewSpmTpmAlignment:Seg8NotFound', ...
            'Specified seg8File not found: %s', seg8File);
    end

    workT1 = opts.t1File;
    if isempty(workT1)
        workT1 = t1FromSeg8File(seg8File);
    end
    if exist(workT1, 'file') ~= 2
        error('acsViewSpmTpmAlignment:T1NotFound', ...
            'Could not find segmentation T1 NIfTI: %s', workT1);
    end

    [sourceT1, tpmFileFromReport] = readSegmentationReport(outputDir, workT1);
    if isempty(sourceT1)
        sourceT1 = workT1;
    end
    if ~isempty(opts.tpmFile)
        tpmFileFromReport = opts.tpmFile;
    end
end

function workT1 = t1FromSeg8File(seg8File)
    [folder, base] = fileparts(seg8File);
    suffix = '_seg8';
    if endsWith(base, suffix)
        base = base(1:end - numel(suffix));
    end
    workT1 = fullfile(folder, [base '.nii']);
end

function [sourceT1, tpmFile] = readSegmentationReport(outputDir, workT1)
    sourceT1 = '';
    tpmFile = '';
    reportJson = fullfile(outputDir, sprintf('%s_spmSegmentationReport.json', ...
        stripNiftiExtension(getFileName(workT1))));
    if exist(reportJson, 'file') ~= 2
        return;
    end

    try
        report = jsondecode(fileread(reportJson));
        if isfield(report, 'sourceT1') && ~isempty(report.sourceT1)
            sourceT1 = char(report.sourceT1);
        end
        if isfield(report, 'tpmFile') && ~isempty(report.tpmFile)
            tpmFile = char(report.tpmFile);
        end
    catch
        sourceT1 = '';
        tpmFile = '';
    end
end

function tpm = resolveSegmentationTpm(res, opts, tpmFileFromReport)
    if isfield(res, 'tpm') && isstruct(res.tpm) && isfield(res.tpm, 'bg1')
        tpm = res.tpm;
        return;
    end

    tpmFile = opts.tpmFile;
    if isempty(tpmFile)
        tpmFile = tpmFileFromReport;
    end
    if isempty(tpmFile)
        if isfield(res, 'tpm')
            tpm = spm_load_priors8(res.tpm);
            return;
        end
        error('acsViewSpmTpmAlignment:MissingTpm', ...
            'No TPM was saved in seg8File. Pass tpmFile explicitly.');
    end
    if exist(tpmFile, 'file') ~= 2
        error('acsViewSpmTpmAlignment:TpmNotFound', ...
            'TPM file not found: %s', tpmFile);
    end
    tpm = spm_load_priors8(spm_vol(tpmFile));
end

function transform = buildTpmTransform(res, tpm, Vref, stage)
    required = {'Affine'};
    for i = 1:numel(required)
        if ~isfield(res, required{i})
            error('acsViewSpmTpmAlignment:BadSeg8', ...
                'The seg8 file is missing required field "%s".', required{i});
        end
    end

    transform = stage;
    transform.M = tpm.M \ res.Affine * Vref.mat;
    transform.MT = eye(4);
    if isfield(res, 'MT') && ~isempty(res.MT)
        transform.MT = res.MT;
    end
    transform.prm = [3 3 3 0 0 0];
    transform.Coef = {};

    if transform.useWarp
        if ~isfield(res, 'Twarp') || isempty(res.Twarp)
            error('acsViewSpmTpmAlignment:MissingTwarp', ...
                'Final alignment requires Twarp in the seg8 file.');
        end
        transform.Coef = cell(1, 3);
        for dim = 1:3
            transform.Coef{dim} = spm_bsplinc(res.Twarp(:, :, :, dim), transform.prm);
        end
    end
end

function fig = makeAlignmentFigure(Vref, tpm, transform, planes, ...
        sliceInd, clim, styles, axisInfo, opts, figVisible)
    fig = figure('Name', ['SPM TPM alignment - ' transform.name], ...
        'Color', 'w', 'Visible', figVisible, ...
        'Units', 'pixels', 'Position', [60 40 1600 1100]);

    addFigureHeader(fig, sprintf('%s | %s | contours %.2f | axes: %s', ...
        getFileName(Vref.fname), transform.label, opts.contourLevel, ...
        axisInfo.description));

    rowLabels = {planes.label};
    colLabels = {'T1', 'Aligned TPM', 'T1 + TPM contours'};
    positions = panelGridPositions(3, 3, 0.055, 0.05, 0.115, 0.12, 0.025, 0.035);

    for row = 1:3
        plane = planes(row);
        idx = sliceInd(plane.voxelDim);
        t1Slice = sampleSliceInReference(Vref, Vref, plane.voxelDim, idx, 0);
        priorSlices = sampleAlignedPriors(tpm, transform, plane.voxelDim, ...
            idx, Vref.dim(1:3), styles);
        tpmUnderlay = max(cat(3, priorSlices{:}), [], 3);

        for col = 1:3
            pos = squeeze(positions(row, col, :))';
            ax = axes(fig, 'Position', pos); %#ok<LAXES>
            switch col
                case 1
                    plotImagePanel(ax, t1Slice, clim, rowLabels{row}, colLabels{col}, ...
                        sprintf('%s dim %d = %d', plane.normal, plane.voxelDim, idx));
                case 2
                    plotImagePanel(ax, tpmUnderlay, [0 1], rowLabels{row}, colLabels{col}, ...
                        sprintf('%s dim %d = %d', plane.normal, plane.voxelDim, idx));
                    contourPriors(ax, priorSlices, styles);
                case 3
                    plotImagePanel(ax, t1Slice, clim, rowLabels{row}, colLabels{col}, ...
                        sprintf('%s dim %d = %d', plane.normal, plane.voxelDim, idx));
                    contourPriors(ax, priorSlices, styles);
            end
        end
    end

    legendAx = axes(fig, 'Position', [0.06 0.035 0.88 0.075]); %#ok<LAXES>
    drawLegendPanel(legendAx, styles);
end

function positions = panelGridPositions(nRows, nCols, left, right, top, bottom, gapX, gapY)
    w = (1 - left - right - (nCols - 1) * gapX) / nCols;
    h = (1 - top - bottom - (nRows - 1) * gapY) / nRows;
    positions = zeros(nRows, nCols, 4);
    for row = 1:nRows
        for col = 1:nCols
            x0 = left + (col - 1) * (w + gapX);
            y0 = 1 - top - row * h - (row - 1) * gapY;
            positions(row, col, :) = [x0 y0 w h];
        end
    end
end

function plotImagePanel(ax, S, clim, rowLabel, colLabel, note)
    imagesc(ax, rot90(S));
    axis(ax, 'image');
    axis(ax, 'off');
    colormap(ax, gray);
    caxis(ax, clim);
    title(ax, sprintf('%s | %s', rowLabel, colLabel), ...
        'Interpreter', 'none', 'FontSize', 10, 'FontWeight', 'bold');
    text(ax, 0.02, 0.03, note, ...
        'Units', 'normalized', ...
        'Color', [1 1 1], ...
        'BackgroundColor', [0 0 0], ...
        'Margin', 2, ...
        'Interpreter', 'none', ...
        'FontSize', 8);
end

function contourPriors(ax, priorSlices, styles)
    hold(ax, 'on');
    for i = 1:numel(styles)
        S = priorSlices{i};
        if any(S(:) >= styles(i).level)
            contour(ax, rot90(S), [styles(i).level styles(i).level], ...
                'Color', styles(i).color, 'LineWidth', styles(i).lineWidth);
        end
    end
end

function priorSlices = sampleAlignedPriors(tpm, transform, dimToFix, ...
        idx, dims, styles)
    [X, Y, Z] = sliceGrid(dims, dimToFix, idx);
    [t1, t2, t3] = subjectVoxelsToTpmVoxels(transform, X, Y, Z);
    priors = spm_sample_priors8(tpm, t1, t2, t3);

    n = numel(styles);
    priorSlices = cell(1, n);
    for i = 1:n
        channel = styles(i).channel;
        if channel > numel(priors)
            priorSlices{i} = zeros(size(X));
        else
            priorSlices{i} = priors{channel};
        end
    end

end

function [t1, t2, t3] = subjectVoxelsToTpmVoxels(transform, X, Y, Z)
    if transform.useWarp
        iMT = inv(transform.MT);
        [Xs, Ys, Zs] = applyAffine(iMT, X, Y, Z);
        Xw = X + spm_bsplins(transform.Coef{1}, Xs, Ys, Zs, transform.prm);
        Yw = Y + spm_bsplins(transform.Coef{2}, Xs, Ys, Zs, transform.prm);
        Zw = Z + spm_bsplins(transform.Coef{3}, Xs, Ys, Zs, transform.prm);
        [t1, t2, t3] = applyAffine(transform.M, Xw, Yw, Zw);
    else
        [t1, t2, t3] = applyAffine(transform.M, X, Y, Z);
    end
end

function [Xo, Yo, Zo] = applyAffine(M, X, Y, Z)
    Xo = M(1, 1) * X + M(1, 2) * Y + M(1, 3) * Z + M(1, 4);
    Yo = M(2, 1) * X + M(2, 2) * Y + M(2, 3) * Z + M(2, 4);
    Zo = M(3, 1) * X + M(3, 2) * Y + M(3, 3) * Z + M(3, 4);
end

function [X, Y, Z] = sliceGrid(dims, dimToFix, idx)
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
            error('acsViewSpmTpmAlignment:BadSliceDimension', ...
                'Unsupported slice dimension %d.', dimToFix);
    end
end

function S = sampleSliceInReference(Vmoving, Vref, dimToFix, idx, holdOrder)
    [X, Y, Z] = sliceGrid(Vref.dim(1:3), dimToFix, idx);
    M = inv(Vmoving.mat) * Vref.mat;
    [Xm, Ym, Zm] = applyAffine(M, X, Y, Z);
    S = spm_sample_vol(Vmoving, Xm, Ym, Zm, holdOrder);
end

function styles = selectedTissueStyles(requestedTissues, contourLevel)
    allStyles = struct( ...
        'name', {'gray', 'white', 'csf', 'bone', 'skin', 'air'}, ...
        'label', {'c1 gray', 'c2 white', 'c3 CSF', 'c4 bone', 'c5 skin', 'c6 air'}, ...
        'channel', {1, 2, 3, 4, 5, 6}, ...
        'color', {[1 0.2 0.1], [0 0.85 1], [0.1 0.25 1], [1 0.85 0], [0 0.8 0.25], [1 0 1]}, ...
        'lineWidth', {1.1, 1.1, 1.1, 1.0, 1.2, 0.8}, ...
        'level', {contourLevel, contourLevel, contourLevel, contourLevel, contourLevel, contourLevel});

    if any(strcmpi(requestedTissues, 'all'))
        styles = allStyles;
        return;
    end

    styles = repmat(allStyles(1), 0, 1);
    for i = 1:numel(requestedTissues)
        idx = find(strcmpi(requestedTissues{i}, {allStyles.name}), 1);
        if isempty(idx)
            error('acsViewSpmTpmAlignment:UnknownQcTissue', ...
                'Unknown QC tissue "%s". Use gray, white, csf, bone, skin, air, or all.', ...
                requestedTissues{i});
        end
        styles(end + 1) = allStyles(idx); %#ok<AGROW>
    end
end

function drawLegendPanel(ax, tissueStyles)
    cla(ax);
    axis(ax, 'off');
    hold(ax, 'on');
    x = 0.02;
    y = 0.62;
    for i = 1:numel(tissueStyles)
        style = tissueStyles(i);
        plot(ax, [x x + 0.055], [y y], ...
            'Color', style.color, 'LineWidth', max(style.lineWidth, 2));
        text(ax, x + 0.065, y, style.label, ...
            'Interpreter', 'none', ...
            'VerticalAlignment', 'middle', ...
            'FontSize', 10);
        x = x + 0.155;
    end
    text(ax, 0.02, 0.18, ...
        'Aligned TPM panels sample SPM tissue priors in the subject T1 grid before intensity likelihoods are applied.', ...
        'Interpreter', 'none', 'FontSize', 9, 'Color', [0.25 0.25 0.25]);
    xlim(ax, [0 1]);
    ylim(ax, [0 1]);
end

function addFigureHeader(fig, headerText)
    annotation(fig, 'textbox', [0.04 0.94 0.92 0.045], ...
        'String', headerText, ...
        'Interpreter', 'none', ...
        'HorizontalAlignment', 'center', ...
        'VerticalAlignment', 'middle', ...
        'FontWeight', 'bold', ...
        'FontSize', 12, ...
        'EdgeColor', 'none');
end

function axisInfo = displayAxisInfo(sourceT1, opts)
    switch opts.planeMode
        case 'spm'
            axisInfo = spmVoxelAxisInfo();
        case 'anatomical'
            axisInfo = anatomicalAxisInfo(sourceT1, opts);
        otherwise
            error('acsViewSpmTpmAlignment:UnknownPlaneMode', ...
                'Unknown planeMode "%s".', opts.planeMode);
    end
end

function axisInfo = spmVoxelAxisInfo()
    planes = repmat(struct('label', '', 'voxelDim', 1, 'normal', ''), 1, 3);
    for dim = 1:3
        planes(dim).label = sprintf('Subject dim %d', dim);
        planes(dim).voxelDim = dim;
        planes(dim).normal = sprintf('SPM voxel dim %d', dim);
    end

    axisInfo = struct();
    axisInfo.description = 'SPM subject voxel dimensions';
    axisInfo.worldAxisVoxelDim = [1 2 3];
    axisInfo.planeVoxelDims = [1 2 3];
    axisInfo.planes = planes;
end

function axisInfo = anatomicalAxisInfo(sourceT1, opts)
    importInfo = importOrientationInfo(sourceT1);
    worldAxisVoxelDim = importInfo.worldAxisVoxelDim;
    labels = {'Sagittal', 'Coronal', 'Axial'};
    normals = {'left-right', 'anterior-posterior', 'inferior-superior'};
    axisMode = opts.anatomicalAxes;

    if isstruct(axisMode)
        [voxelDims, normals, description] = planesFromAnatomicalStruct(axisMode, ...
            worldAxisVoxelDim);
    else
        switch lower(char(axisMode))
            case {'scanner', 'dicom', 'human', 'humansupine'}
                voxelDims = worldAxisVoxelDim;
                description = char(axisMode);
            case {'macaquesphinx', 'sphinx'}
                voxelDims = [worldAxisVoxelDim(1), ...
                    worldAxisVoxelDim(3), ...
                    worldAxisVoxelDim(2)];
                normals = {'left-right', 'rostral-caudal', 'dorsal-ventral'};
                description = 'macaqueSphinx';
            otherwise
                error('acsViewSpmTpmAlignment:UnknownAnatomicalAxes', ...
                    'Unknown anatomicalAxes preset: %s', char(axisMode));
        end
    end

    if ~isempty(opts.planeVoxelDims)
        voxelDims = opts.planeVoxelDims;
        description = [description ' + manual planeVoxelDims'];
    end
    voxelDims = validatePlaneVoxelDims(voxelDims);

    planes = repmat(struct('label', '', 'voxelDim', 1, 'normal', ''), 1, 3);
    for i = 1:3
        planes(i).label = labels{i};
        planes(i).voxelDim = voxelDims(i);
        planes(i).normal = normals{i};
    end

    axisInfo = struct();
    axisInfo.description = description;
    axisInfo.worldAxisVoxelDim = worldAxisVoxelDim;
    axisInfo.planeVoxelDims = voxelDims;
    axisInfo.planes = planes;
end

function importInfo = importOrientationInfo(sourceT1)
    importInfo = struct();
    importInfo.worldAxisVoxelDim = [1 2 3];
    reportJson = fullfile(fileparts(sourceT1), ...
        [stripNiftiExtension(getFileName(sourceT1)) '_importReport.json']);
    if exist(reportJson, 'file') ~= 2
        return;
    end

    try
        report = jsondecode(fileread(reportJson));
        if isfield(report, 'nifti') && isfield(report.nifti, 'orientation') && ...
                isfield(report.nifti.orientation, 'worldAxisVoxelDim')
            importInfo.worldAxisVoxelDim = validatePlaneVoxelDims( ...
                double(report.nifti.orientation.worldAxisVoxelDim(:))');
        end
    catch
        importInfo.worldAxisVoxelDim = [1 2 3];
    end
end

function [voxelDims, normals, description] = planesFromAnatomicalStruct(S, worldAxisVoxelDim)
    description = 'custom';
    normals = {'left-right', 'rostral-caudal', 'dorsal-ventral'};

    if isfield(S, 'name') && ~isempty(S.name)
        description = char(S.name);
    end

    if isfield(S, 'planeVoxelDims') && ~isempty(S.planeVoxelDims)
        voxelDims = double(S.planeVoxelDims(:))';
        return;
    end

    required = {'left', 'rostral', 'dorsal'};
    voxelDims = zeros(1, 3);
    for i = 1:numel(required)
        if ~isfield(S, required{i})
            error('acsViewSpmTpmAlignment:BadAnatomicalAxesStruct', ...
                'Custom anatomicalAxes must include left, rostral, and dorsal fields.');
        end
        worldAxis = parseWorldAxis(S.(required{i}));
        voxelDims(i) = worldAxisVoxelDim(worldAxis);
    end
end

function worldAxis = parseWorldAxis(axisSpec)
    if isnumeric(axisSpec)
        worldAxis = abs(axisSpec(1));
    else
        s = upper(char(axisSpec));
        s = strrep(s, '+', '');
        s = strrep(s, '-', '');
        switch s
            case {'X', '1', 'WORLDX'}
                worldAxis = 1;
            case {'Y', '2', 'WORLDY'}
                worldAxis = 2;
            case {'Z', '3', 'WORLDZ'}
                worldAxis = 3;
            otherwise
                error('acsViewSpmTpmAlignment:BadAxisSpec', ...
                    'Axis spec must be X, Y, Z, 1, 2, or 3.');
        end
    end

    if worldAxis < 1 || worldAxis > 3
        error('acsViewSpmTpmAlignment:BadAxisSpec', ...
            'World axis index must be 1, 2, or 3.');
    end
end

function voxelDims = validatePlaneVoxelDims(voxelDims)
    voxelDims = double(voxelDims(:))';
    if numel(voxelDims) ~= 3 || any(voxelDims < 1) || any(voxelDims > 3)
        voxelDims = [1 2 3];
        return;
    end
    voxelDims = round(voxelDims);
end

function sliceIndices = validateSliceIndices(sliceIndices, dims)
    sliceIndices = round(double(sliceIndices(:))');
    if numel(sliceIndices) ~= 3
        sliceIndices = max(1, round(dims ./ 2));
    end
    sliceIndices = max([1 1 1], min(dims, sliceIndices));
end

function clim = robustClim(V)
    vals = V(isfinite(V));
    if isempty(vals)
        clim = [0 1];
        return;
    end
    n = numel(vals);
    if n > 1000000
        vals = vals(round(linspace(1, n, 1000000)));
    end
    clim = prctile(vals(:), [1 99]);
    if clim(1) == clim(2)
        clim = [min(vals(:)) max(vals(:))];
    end
    if clim(1) == clim(2)
        clim = clim + [-1 1];
    end
end

function addRoastDependencies(P)
    libDir = fullfile(P.repoRoot, 'lib');
    spmDir = fullfile(libDir, 'spm12');
    if exist(spmDir, 'dir') ~= 7
        error('acsViewSpmTpmAlignment:MissingSpm', 'SPM folder not found: %s', spmDir);
    end
    addpath(genpath(libDir));
    addpath(P.repoRoot);
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

function name = getFileName(filePath)
    [~, name, ext] = fileparts(filePath);
    name = [name ext];
end

function name = safeName(value)
    name = regexprep(char(value), '[^A-Za-z0-9_-]', '_');
end

function p = expandUserPath(p)
    if isempty(p)
        return;
    end
    p = char(p);
    if startsWith(p, "~")
        homeDir = char(java.lang.System.getProperty('user.home'));
        if strlength(string(p)) == 1
            p = homeDir;
        elseif any(p(2) == ['/' filesep])
            p = fullfile(homeDir, p(3:end));
        end
    end
end
