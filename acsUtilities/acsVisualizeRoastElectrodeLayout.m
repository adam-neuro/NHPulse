function out = acsVisualizeRoastElectrodeLayout(layoutIn, varargin)
% ACSVISUALIZEROASTELECTRODELAYOUT Preflight custom electrode layout geometry.
%
% out = acsVisualizeRoastElectrodeLayout(layout)
% visualizes a ROAST custom electrode layout before ROAST voxelizes the
% electrodes. It is intended to catch candidate collisions early, especially
% for surrogate-grown capMaker layouts.
%
% Name-value options:
%   electrodeModel      : 'biosemiPin', 'roastDefault', or 'custom' ['biosemiPin']
%   contactRadiusMm     : conductive contact radius for custom model [[]]
%   housingRadiusMm     : physical housing radius for custom model [[]]
%   collisionClearanceMm: added warning clearance around contact radius [0.5]
%   maskFile            : explicit ROAST label mask file ['']
%   maxSurfacePoints    : maximum scalp surface points to plot [25000]
%   showFigures         : show preflight figure [true]
%   saveFigures         : save preflight figure [false]
%   closeFigure         : close figure before returning [false]

    if nargin < 1 || isempty(layoutIn)
        error('acsVisualizeRoastElectrodeLayout:MissingInput', ...
            'Provide a capMaker layout struct, grow struct, or customLocations file.');
    end
    opts = parseInputs(varargin{:});
    addDependencies();

    layout = readLayout(layoutIn);
    model = electrodeModel(opts);
    if isempty(opts.maskFile)
        opts.maskFile = getOptionalField(layout, 'maskFile', '');
    end
    if isempty(opts.maskFile) && isfield(layout, 't1File')
        opts.maskFile = inferMaskFile(layout.t1File);
    end

    names = cellstr(layout.names(:));
    voxelCoords = double(layout.voxelCoordinates);
    voxelSize = layoutVoxelSize(layout);
    coordsMm = bsxfun(@times, voxelCoords, voxelSize);
    printCoordsMm = getOptionalField(layout, 'layoutCoordinatesMm', []);

    D = sqrt(pairwiseDistanceSquared(coordsMm, coordsMm));
    D(1:size(D, 1) + 1:end) = inf;
    [nearestDistanceMm, nearestIndex] = min(D, [], 2);
    roastDomainRadiusMm = max(model.contactRadiusMm, model.gelRadiusMm);
    contactThresholdMm = 2 * roastDomainRadiusMm + ...
        opts.collisionClearanceMm;
    housingThresholdMm = 2 * model.housingRadiusMm;
    contactRiskPairs = pairTable(D, names, contactThresholdMm);
    housingRiskPairs = pairTable(D, names, housingThresholdMm);

    surfaceMm = [];
    if ~isempty(opts.maskFile) && exist(opts.maskFile, 'file') == 2
        surfaceMm = readScalpSurfaceMm(opts.maskFile, voxelSize, ...
            opts.maxSurfacePoints);
    end

    fig = [];
    if opts.showFigures || opts.saveFigures
        figVisible = 'off';
        if opts.showFigures
            figVisible = 'on';
        end
        fig = makeFigure(surfaceMm, coordsMm, printCoordsMm, names, ...
            D, contactRiskPairs, housingRiskPairs, nearestDistanceMm, ...
            contactThresholdMm, housingThresholdMm, model, figVisible);
    end

    out = struct();
    out.createdOn = char(datetime('now'));
    out.t1File = getOptionalField(layout, 't1File', '');
    out.maskFile = opts.maskFile;
    out.customLocationsFile = getOptionalField(layout, ...
        'customLocationsFile', '');
    out.names = names(:);
    out.voxelCoordinates = voxelCoords;
    out.scaledCoordinatesMm = coordsMm;
    out.layoutCoordinatesMm = printCoordsMm;
    out.voxelSize = voxelSize;
    out.electrodeModel = model.name;
    out.contactRadiusMm = model.contactRadiusMm;
    out.gelRadiusMm = model.gelRadiusMm;
    out.gelHeightMm = model.gelHeightMm;
    out.skinGapMm = model.skinGapMm;
    out.roastDomainRadiusMm = roastDomainRadiusMm;
    out.housingRadiusMm = model.housingRadiusMm;
    out.contactRiskThresholdMm = contactThresholdMm;
    out.housingRiskThresholdMm = housingThresholdMm;
    out.nearestIndex = nearestIndex(:);
    out.nearestName = names(nearestIndex);
    out.nearestDistanceMm = nearestDistanceMm(:);
    out.contactRiskPairs = contactRiskPairs;
    out.housingRiskPairs = housingRiskPairs;
    out.figure = fig;
    out.qcFigure = '';

    if opts.saveFigures && ishandle(fig)
        qcDir = outputQcDir(layout, opts.maskFile);
        ensureDir(qcDir);
        out.qcFigure = fullfile(qcDir, ...
            [safeName(model.name) '_electrodeLayoutPreflight.png']);
        saveQcFigure(fig, out.qcFigure);
    end
    if opts.closeFigure && ishandle(fig)
        close(fig);
        out.figure = [];
    end

    printSummary(out);
end

function opts = parseInputs(varargin)
    p = inputParser;
    p.FunctionName = 'acsVisualizeRoastElectrodeLayout';
    addParameter(p, 'electrodeModel', 'biosemiPin', @(x) ischar(x) || isstring(x));
    addParameter(p, 'contactRadiusMm', [], ...
        @(x) isempty(x) || (isnumeric(x) && isscalar(x) && isfinite(x) && x > 0));
    addParameter(p, 'housingRadiusMm', [], ...
        @(x) isempty(x) || (isnumeric(x) && isscalar(x) && isfinite(x) && x > 0));
    addParameter(p, 'collisionClearanceMm', 0.5, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0);
    addParameter(p, 'maskFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'maxSurfacePoints', 25000, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0);
    addParameter(p, 'showFigures', true, @isBoolLike);
    addParameter(p, 'saveFigures', false, @isBoolLike);
    addParameter(p, 'closeFigure', false, @isBoolLike);
    parse(p, varargin{:});
    opts = p.Results;
    opts.electrodeModel = lower(strtrim(char(opts.electrodeModel)));
    opts.maskFile = expandUserPath(char(opts.maskFile));
    opts.maxSurfacePoints = round(double(opts.maxSurfacePoints));
    opts.showFigures = logical(opts.showFigures);
    opts.saveFigures = logical(opts.saveFigures);
    opts.closeFigure = logical(opts.closeFigure);
end

function tf = isBoolLike(x)
    tf = (islogical(x) || isnumeric(x)) && isscalar(x);
end

function addDependencies()
    repoRoot = fileparts(fileparts(mfilename('fullpath')));
    addpath(repoRoot);
    spmDir = fullfile(repoRoot, 'lib', 'spm12');
    if exist(spmDir, 'dir') == 7
        addpath(spmDir);
    end
end

function layout = readLayout(layoutIn)
    if isstruct(layoutIn)
        if isfield(layoutIn, 'expandedLayout') && ...
                ~isempty(layoutIn.expandedLayout)
            layout = layoutIn.expandedLayout;
        else
            layout = layoutIn;
        end
    elseif ischar(layoutIn) || isstring(layoutIn)
        layoutIn = char(layoutIn);
        if exist(layoutIn, 'file') ~= 2
            error('acsVisualizeRoastElectrodeLayout:MissingFile', ...
                'Layout file not found: %s', layoutIn);
        end
        [~, ~, ext] = fileparts(layoutIn);
        if strcmpi(ext, '.mat')
            S = load(layoutIn);
            layout = firstStructInMat(S);
        else
            [names, coords] = readCustomLocations(layoutIn);
            layout = struct('names', {names}, ...
                'voxelCoordinates', coords, ...
                'customLocationsFile', layoutIn);
        end
    else
        error('acsVisualizeRoastElectrodeLayout:BadInput', ...
            'Input must be a struct, MAT report, or customLocations file.');
    end
    if ~isfield(layout, 'voxelCoordinates') || isempty(layout.voxelCoordinates)
        if isfield(layout, 'customLocationsFile') && ...
                exist(layout.customLocationsFile, 'file') == 2
            [names, coords] = readCustomLocations(layout.customLocationsFile);
            layout.names = names;
            layout.voxelCoordinates = coords;
        else
            error('acsVisualizeRoastElectrodeLayout:MissingCoordinates', ...
                'Layout does not contain voxelCoordinates or readable customLocationsFile.');
        end
    end
    if ~isfield(layout, 'names') || isempty(layout.names)
        layout.names = arrayfun(@(i) sprintf('custom%d', i), ...
            1:size(layout.voxelCoordinates, 1), 'UniformOutput', false);
    end
end

function S = firstStructInMat(M)
    if isfield(M, 'out')
        S = M.out;
        return;
    end
    if isfield(M, 'outToSave')
        S = M.outToSave;
        return;
    end
    fields = fieldnames(M);
    for i = 1:numel(fields)
        if isstruct(M.(fields{i}))
            S = M.(fields{i});
            return;
        end
    end
    error('acsVisualizeRoastElectrodeLayout:NoStructInMat', ...
        'MAT file did not contain a struct result.');
end

function model = electrodeModel(opts)
    switch opts.electrodeModel
        case {'biosemipin', 'biosemi', 'biosemi-pin', 'biosemi_pin'}
            model = struct('name', 'biosemiPin', ...
                'contactRadiusMm', 1, ...
                'gelRadiusMm', 2.5, ...
                'gelHeightMm', 2.5, ...
                'skinGapMm', 0.5, ...
                'housingRadiusMm', 5);
        case {'roastdefault', 'default'}
            model = struct('name', 'roastDefault', ...
                'contactRadiusMm', 6, ...
                'gelRadiusMm', 6, ...
                'gelHeightMm', 6, ...
                'skinGapMm', 0, ...
                'housingRadiusMm', 6);
        case {'custom'}
            if isempty(opts.contactRadiusMm) || isempty(opts.housingRadiusMm)
                error('acsVisualizeRoastElectrodeLayout:MissingCustomRadii', ...
                    'custom electrodeModel requires contactRadiusMm and housingRadiusMm.');
            end
            model = struct('name', 'custom', ...
                'contactRadiusMm', double(opts.contactRadiusMm), ...
                'gelRadiusMm', double(opts.contactRadiusMm), ...
                'gelHeightMm', double(opts.contactRadiusMm), ...
                'skinGapMm', 0, ...
                'housingRadiusMm', double(opts.housingRadiusMm));
        otherwise
            error('acsVisualizeRoastElectrodeLayout:BadElectrodeModel', ...
                'electrodeModel must be biosemiPin, roastDefault, or custom.');
    end
    if ~isempty(opts.contactRadiusMm)
        model.contactRadiusMm = double(opts.contactRadiusMm);
    end
    if ~isempty(opts.housingRadiusMm)
        model.housingRadiusMm = double(opts.housingRadiusMm);
    end
end

function voxelSize = layoutVoxelSize(layout)
    if isfield(layout, 'voxelSize') && ~isempty(layout.voxelSize)
        voxelSize = double(layout.voxelSize(:)');
        return;
    end
    if isfield(layout, 't1File') && exist(layout.t1File, 'file') == 2
        requireSpm();
        V = spm_vol(layout.t1File);
        voxelSize = sqrt(sum(V.mat(1:3, 1:3) .^ 2, 1));
        return;
    end
    warning('acsVisualizeRoastElectrodeLayout:AssumingUnitVoxels', ...
        'No voxelSize or T1 file available; assuming 1 mm isotropic voxels.');
    voxelSize = [1 1 1];
end

function requireSpm()
    if exist('spm_vol', 'file') ~= 2
        error('acsVisualizeRoastElectrodeLayout:MissingSpm', ...
            'SPM is required to read NIfTI files.');
    end
end

function maskFile = inferMaskFile(t1File)
    [folder, stem] = fileparts(t1File);
    maskFile = fullfile(folder, [stem '_T1orT2_SPM_masks.nii']);
end

function surfaceMm = readScalpSurfaceMm(maskFile, voxelSize, maxSurfacePoints)
    requireSpm();
    V = spm_vol(maskFile);
    labels = spm_read_vols(V);
    solid = labels >= 1 & labels <= 5;
    if exist('mask2EdgePointCloud', 'file') == 2
        surfaceVox = mask2EdgePointCloud(solid, 'erode', ones(3, 3, 3));
    else
        surfaceVox = fallbackSurfaceVoxels(solid);
    end
    if maxSurfacePoints > 0 && size(surfaceVox, 1) > maxSurfacePoints
        rows = unique(round(linspace(1, size(surfaceVox, 1), maxSurfacePoints)));
        surfaceVox = surfaceVox(rows, :);
    end
    surfaceMm = bsxfun(@times, double(surfaceVox), voxelSize);
end

function surfaceVox = fallbackSurfaceVoxels(mask)
    eroded = mask;
    eroded(2:end-1, 2:end-1, 2:end-1) = ...
        mask(2:end-1, 2:end-1, 2:end-1) & ...
        mask(1:end-2, 2:end-1, 2:end-1) & ...
        mask(3:end, 2:end-1, 2:end-1) & ...
        mask(2:end-1, 1:end-2, 2:end-1) & ...
        mask(2:end-1, 3:end, 2:end-1) & ...
        mask(2:end-1, 2:end-1, 1:end-2) & ...
        mask(2:end-1, 2:end-1, 3:end);
    edge = mask & ~eroded;
    [x, y, z] = ind2sub(size(edge), find(edge));
    surfaceVox = [x y z];
end

function [names, coords] = readCustomLocations(fileName)
    fid = fopen(fileName, 'r');
    if fid == -1
        error('acsVisualizeRoastElectrodeLayout:CannotReadCustomLocations', ...
            'Could not read customLocations file: %s', fileName);
    end
    cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
    C = textscan(fid, '%s %f %f %f');
    names = C{1};
    coords = [C{2}, C{3}, C{4}];
end

function pairs = pairTable(D, names, thresholdMm)
    [i, j] = find(triu(D < thresholdMm, 1));
    pairs = struct('indexA', {}, 'indexB', {}, 'nameA', {}, 'nameB', {}, ...
        'distanceMm', {});
    for k = 1:numel(i)
        pairs(k).indexA = i(k); %#ok<AGROW>
        pairs(k).indexB = j(k);
        pairs(k).nameA = names{i(k)};
        pairs(k).nameB = names{j(k)};
        pairs(k).distanceMm = D(i(k), j(k));
    end
end

function fig = makeFigure(surfaceMm, coordsMm, printCoordsMm, names, D, ...
        contactPairs, housingPairs, nearestDistanceMm, contactThresholdMm, ...
        housingThresholdMm, model, figVisible)
    fig = figure('Name', 'ROAST electrode layout preflight', ...
        'Color', 'w', 'Visible', figVisible, 'Units', 'pixels', ...
        'Position', [100 100 1700 560]);

    ax1 = subplot(1, 3, 1, 'Parent', fig);
    hold(ax1, 'on');
    if ~isempty(surfaceMm)
        scatter3(ax1, surfaceMm(:, 1), surfaceMm(:, 2), surfaceMm(:, 3), ...
            2, [0.78 0.78 0.78], 'filled');
    end
    scatter3(ax1, coordsMm(:, 1), coordsMm(:, 2), coordsMm(:, 3), ...
        80, [0.05 0.2 0.9], 'filled', 'MarkerEdgeColor', 'k');
    drawRiskLines(ax1, coordsMm, housingPairs, [0.95 0.55 0.05], 1.5);
    drawRiskLines(ax1, coordsMm, contactPairs, [0.9 0.05 0.05], 2.5);
    drawFootprintSpheres(ax1, coordsMm, model.housingRadiusMm, ...
        [0.95 0.55 0.05], 0.08);
    drawFootprintSpheres(ax1, coordsMm, model.gelRadiusMm, ...
        [0.05 0.75 0.30], 0.10);
    drawFootprintSpheres(ax1, coordsMm, model.contactRadiusMm, ...
        [0.05 0.2 0.9], 0.20);
    addLabels3(ax1, coordsMm, names);
    axis(ax1, 'equal');
    grid(ax1, 'on');
    view(ax1, 35, 25);
    xlabel(ax1, 'ROAST X (mm)');
    ylabel(ax1, 'ROAST Y (mm)');
    zlabel(ax1, 'ROAST Z (mm)');
    title(ax1, sprintf('%s contact/housing preflight', model.name), ...
        'Interpreter', 'none');

    ax2 = subplot(1, 3, 2, 'Parent', fig);
    bar(ax2, nearestDistanceMm, 'FaceColor', [0.2 0.45 0.7]);
    hold(ax2, 'on');
    yline(ax2, contactThresholdMm, 'r-', 'ROAST domain warning');
    yline(ax2, housingThresholdMm, 'Color', [0.95 0.55 0.05], ...
        'LineStyle', '-', 'Label', 'Housing diameter');
    xticks(ax2, 1:numel(names));
    xticklabels(ax2, names);
    xtickangle(ax2, 45);
    ylabel(ax2, 'Nearest neighbor distance (mm)');
    title(ax2, 'Nearest-neighbor spacing');
    grid(ax2, 'on');

    ax3 = subplot(1, 3, 3, 'Parent', fig);
    if ~isempty(printCoordsMm)
        hold(ax3, 'on');
        plot(ax3, printCoordsMm(:, 1), printCoordsMm(:, 2), '.', ...
            'Color', [0.05 0.2 0.9], 'MarkerSize', 18);
        for i = 1:size(printCoordsMm, 1)
            plotCircle(ax3, printCoordsMm(i, 1), printCoordsMm(i, 2), ...
                model.housingRadiusMm, [0.95 0.55 0.05]);
            plotCircle(ax3, printCoordsMm(i, 1), printCoordsMm(i, 2), ...
                model.gelRadiusMm, [0.05 0.75 0.30]);
        end
        addLabels2(ax3, printCoordsMm(:, 1:2), names);
        axis(ax3, 'equal');
        grid(ax3, 'on');
        xlabel(ax3, 'capMaker print X (mm)');
        ylabel(ax3, 'capMaker print Y (mm)');
        title(ax3, 'capMaker print-frame housing footprint');
    else
        axis(ax3, 'off');
        text(ax3, 0.05, 0.75, sprintf('Contact risk pairs: %d', ...
            numel(contactPairs)), 'Units', 'normalized');
        text(ax3, 0.05, 0.62, sprintf('Housing risk pairs: %d', ...
            numel(housingPairs)), 'Units', 'normalized');
        text(ax3, 0.05, 0.49, sprintf('Minimum spacing: %.3g mm', ...
            min(nearestDistanceMm)), 'Units', 'normalized');
        title(ax3, 'Summary');
    end
end

function drawFootprintSpheres(ax, centers, radius, color, alphaValue)
    if radius <= 0
        return;
    end
    [sx, sy, sz] = sphere(12);
    for i = 1:size(centers, 1)
        surf(ax, centers(i, 1) + radius * sx, ...
            centers(i, 2) + radius * sy, ...
            centers(i, 3) + radius * sz, ...
            'FaceColor', color, 'FaceAlpha', alphaValue, ...
            'EdgeColor', 'none');
    end
end

function drawRiskLines(ax, coords, pairs, color, lineWidth)
    for i = 1:numel(pairs)
        a = pairs(i).indexA;
        b = pairs(i).indexB;
        plot3(ax, coords([a b], 1), coords([a b], 2), coords([a b], 3), ...
            '-', 'Color', color, 'LineWidth', lineWidth);
    end
end

function addLabels3(ax, points, names)
    for i = 1:size(points, 1)
        text(ax, points(i, 1), points(i, 2), points(i, 3), ...
            ['  ' names{i}], 'Interpreter', 'none', 'FontSize', 7);
    end
end

function addLabels2(ax, points, names)
    for i = 1:size(points, 1)
        text(ax, points(i, 1), points(i, 2), ['  ' names{i}], ...
            'Interpreter', 'none', 'FontSize', 7);
    end
end

function plotCircle(ax, x, y, r, color)
    t = linspace(0, 2 * pi, 80);
    plot(ax, x + r * cos(t), y + r * sin(t), '-', ...
        'Color', color, 'LineWidth', 1);
end

function printSummary(out)
    fprintf('\nROAST electrode layout preflight\n');
    fprintf('  electrode model: %s\n', out.electrodeModel);
    fprintf('  contact radius: %.6g mm\n', out.contactRadiusMm);
    fprintf('  gel radius/height: %.6g / %.6g mm\n', ...
        out.gelRadiusMm, out.gelHeightMm);
    fprintf('  skin gap: %.6g mm\n', out.skinGapMm);
    fprintf('  housing radius: %.6g mm\n', out.housingRadiusMm);
    fprintf('  minimum nearest-neighbor spacing: %.6g mm\n', ...
        min(out.nearestDistanceMm));
    fprintf('  contact-risk pairs: %d\n', numel(out.contactRiskPairs));
    printPairs(out.contactRiskPairs);
    fprintf('  housing-risk pairs: %d\n', numel(out.housingRiskPairs));
    printPairs(out.housingRiskPairs);
    fprintf('\n');
end

function printPairs(pairs)
    maxRows = min(numel(pairs), 12);
    for i = 1:maxRows
        fprintf('    %s - %s: %.6g mm\n', pairs(i).nameA, ...
            pairs(i).nameB, pairs(i).distanceMm);
    end
    if numel(pairs) > maxRows
        fprintf('    ... %d more\n', numel(pairs) - maxRows);
    end
end

function D2 = pairwiseDistanceSquared(A, B)
    A = double(A);
    B = double(B);
    D2 = bsxfun(@plus, sum(A .^ 2, 2), sum(B .^ 2, 2)') - 2 * (A * B');
    D2 = max(D2, 0);
end

function value = getOptionalField(S, fieldName, defaultValue)
    if isstruct(S) && isfield(S, fieldName) && ~isempty(S.(fieldName))
        value = S.(fieldName);
    else
        value = defaultValue;
    end
end

function qcDir = outputQcDir(layout, maskFile)
    if isfield(layout, 'customLocationsFile') && ...
            ~isempty(layout.customLocationsFile)
        qcDir = fullfile(fileparts(layout.customLocationsFile), 'qc');
    elseif ~isempty(maskFile)
        qcDir = fullfile(fileparts(maskFile), 'qc');
    else
        qcDir = fullfile(pwd, 'qc');
    end
end

function saveQcFigure(fig, qcFile)
    try
        exportgraphics(fig, qcFile, 'Resolution', 150);
    catch
        saveas(fig, qcFile);
    end
end

function ensureDir(pathIn)
    if exist(pathIn, 'dir') ~= 7
        mkdir(pathIn);
    end
end

function name = safeName(name)
    name = regexprep(char(name), '[^A-Za-z0-9_-]+', '_');
end

function p = expandUserPath(p)
    p = char(p);
    if isempty(p)
        return;
    end
    if startsWith(p, '~')
        homeDir = getenv('USERPROFILE');
        if isempty(homeDir)
            homeDir = getenv('HOME');
        end
        p = fullfile(homeDir, extractAfter(p, 1));
    end
end
