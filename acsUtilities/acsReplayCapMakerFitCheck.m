function out = acsReplayCapMakerFitCheck(fitCheckIn, varargin)
% ACSREPLAYCAPMAKERFITCHECK Reopen saved PLA fit-check products for inspection.
%
% out = acsReplayCapMakerFitCheck(reportMat) loads the report and mesh MAT
% saved by acsBuildCapMakerFitCheckStl, then redraws the sparse PLA scaffold
% with the cap skin, ear spheres, implant keepout outlines, and simple rail
% vertex diagnostics.
%
% fitCheckIn may be a report MAT file, an output directory, or the struct
% returned by acsBuildCapMakerFitCheckStl.
%
% Name-value options:
%   showFigures              : show replay figure [true]
%   saveFigures              : save replay PNG [false]
%   outputFile               : explicit PNG path ['']
%   skinAlpha                : scalp mesh transparency [0.16]
%   railAlpha                : rail mesh transparency [0.78]
%   showExclusions           : show ear/headpost keepouts [true]
%   highlightLowestRailCount : mark this many lowest rail vertices [30]
%   verbose                  : print loaded product paths [true]

    if nargin < 1 || isempty(fitCheckIn)
        error('acsReplayCapMakerFitCheck:MissingInput', ...
            'Provide a fit-check report MAT, output folder, or output struct.');
    end

    opts = parseInputs(varargin{:});
    [report, reportFile] = readReport(fitCheckIn);
    meshes = readMeshes(report, reportFile);

    fig = [];
    qcFile = '';
    if opts.showFigures || opts.saveFigures
        figVisible = 'off';
        if opts.showFigures
            figVisible = 'on';
        end
        fig = makeReplayFigure(report, meshes, opts, figVisible);
        if opts.saveFigures
            qcFile = opts.outputFile;
            if isempty(qcFile)
                [folder, stem] = fileparts(reportFile);
                qcFile = fullfile(folder, [stem '_replay.png']);
            end
            ensureDir(fileparts(qcFile));
            saveReplayFigure(fig, qcFile);
        end
        if ~opts.showFigures && isgraphics(fig)
            close(fig);
            fig = [];
        end
    end

    out = struct();
    out.createdOn = char(datetime('now'));
    out.type = 'capMakerPlaFitCheckReplay';
    out.reportMat = reportFile;
    out.meshMat = char(getOptionalField(report, 'meshMat', ''));
    out.stlFile = char(getOptionalField(report, 'stlFile', ''));
    out.qcFigure = qcFile;
    out.report = report;
    out.meshes = meshes;
    out.lowRailVertices = lowestRailVertices(meshes, opts.highlightLowestRailCount);
    if isgraphics(fig)
        out.figure = fig;
    end

    if opts.verbose
        fprintf('\nCapMaker PLA fit-check replay\n');
        fprintf('  report: %s\n', out.reportMat);
        fprintf('  mesh:   %s\n', out.meshMat);
        fprintf('  STL:    %s\n', out.stlFile);
        fprintf('  low rail vertices highlighted: %d\n\n', ...
            size(out.lowRailVertices.pointsMm, 1));
    end
end

function opts = parseInputs(varargin)
    p = inputParser;
    p.FunctionName = 'acsReplayCapMakerFitCheck';
    addParameter(p, 'showFigures', true, @isBoolLike);
    addParameter(p, 'saveFigures', false, @isBoolLike);
    addParameter(p, 'outputFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'skinAlpha', 0.16, @isUnitScalar);
    addParameter(p, 'railAlpha', 0.78, @isUnitScalar);
    addParameter(p, 'showExclusions', true, @isBoolLike);
    addParameter(p, 'highlightLowestRailCount', 30, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0);
    addParameter(p, 'verbose', true, @isBoolLike);
    parse(p, varargin{:});

    opts = p.Results;
    opts.showFigures = logical(opts.showFigures);
    opts.saveFigures = logical(opts.saveFigures);
    opts.outputFile = expandUserPath(char(opts.outputFile));
    opts.skinAlpha = double(opts.skinAlpha);
    opts.railAlpha = double(opts.railAlpha);
    opts.showExclusions = logical(opts.showExclusions);
    opts.highlightLowestRailCount = round(double(opts.highlightLowestRailCount));
    opts.verbose = logical(opts.verbose);
end

function tf = isBoolLike(x)
    tf = (islogical(x) || isnumeric(x)) && isscalar(x);
end

function tf = isUnitScalar(x)
    tf = isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0 && x <= 1;
end

function [report, reportFile] = readReport(value)
    reportFile = '';
    if isstruct(value)
        report = value;
        reportFile = char(getOptionalField(report, 'reportMat', ''));
        return;
    end

    fileOrFolder = expandUserPath(char(value));
    if exist(fileOrFolder, 'dir') == 7
        candidates = dir(fullfile(fileOrFolder, '*_report.mat'));
        if isempty(candidates)
            candidates = dir(fullfile(fileOrFolder, '*report*.mat'));
        end
        if isempty(candidates)
            error('acsReplayCapMakerFitCheck:NoReportInFolder', ...
                'No fit-check report MAT found in: %s', fileOrFolder);
        end
        [~, newest] = max([candidates.datenum]);
        reportFile = fullfile(candidates(newest).folder, candidates(newest).name);
    else
        reportFile = fileOrFolder;
    end
    if exist(reportFile, 'file') ~= 2
        error('acsReplayCapMakerFitCheck:ReportNotFound', ...
            'Fit-check report not found: %s', reportFile);
    end
    raw = load(reportFile);
    report = firstStruct(raw);
    if ~isfield(report, 'reportMat') || isempty(report.reportMat)
        report.reportMat = reportFile;
    end
end

function meshes = readMeshes(report, reportFile)
    meshFile = char(getOptionalField(report, 'meshMat', ''));
    if isempty(meshFile)
        [folder, stem] = fileparts(reportFile);
        meshFile = fullfile(folder, strrep(stem, '_report', '_meshes.mat'));
    end
    if exist(meshFile, 'file') ~= 2
        error('acsReplayCapMakerFitCheck:MeshNotFound', ...
            'Fit-check mesh MAT not found: %s', meshFile);
    end
    raw = load(meshFile);
    if isfield(raw, 'meshes') && isstruct(raw.meshes)
        meshes = raw.meshes;
    else
        meshes = raw;
    end
    fields = fieldnames(meshes);
    for i = 1:numel(fields)
        if startsWith(fields{i}, 'TR') && ~isempty(meshes.(fields{i}))
            meshes.(fields{i}) = ensureTriangulation(meshes.(fields{i}));
        end
    end
end

function fig = makeReplayFigure(report, meshes, opts, visible)
    fig = figure('Name', 'CapMaker PLA fit-check replay', ...
        'NumberTitle', 'off', 'Color', 'w', 'Visible', visible, ...
        'Position', [80 70 1400 820]);
    tl = tiledlayout(fig, 2, 2, 'Padding', 'compact', 'TileSpacing', 'compact');

    ax1 = nexttile(tl, 1);
    hold(ax1, 'on');
    drawTri(ax1, getMesh(meshes, 'TRskin'), [0.78 0.80 0.84], opts.skinAlpha, 'none');
    drawTri(ax1, getMesh(meshes, 'TRrails'), [0.05 0.24 0.82], opts.railAlpha, 'none');
    drawTri(ax1, getMesh(meshes, 'TRmarkerSupports'), [0.10 0.50 0.80], 0.85, 'none');
    drawTri(ax1, getMesh(meshes, 'TRmarkers'), [0.95 0.45 0.10], 0.90, 'none');
    if opts.showExclusions
        drawExclusions(ax1, report);
    end
    title(ax1, 'PLA scaffold on cap skin');
    format3d(ax1, 3);

    ax2 = nexttile(tl, 2);
    hold(ax2, 'on');
    drawTri(ax2, getMesh(meshes, 'TRskin'), [0.78 0.80 0.84], 0.08, 'none');
    drawTri(ax2, getMesh(meshes, 'TRrails'), [0.05 0.24 0.82], 0.92, 'none');
    low = lowestRailVertices(meshes, opts.highlightLowestRailCount);
    if ~isempty(low.pointsMm)
        scatter3(ax2, low.pointsMm(:, 1), low.pointsMm(:, 2), low.pointsMm(:, 3), ...
            48, [0.95 0.05 0.05], 'filled', ...
            'MarkerEdgeColor', [0.15 0.15 0.15]);
    end
    title(ax2, sprintf('%d lowest rail vertices highlighted', ...
        size(low.pointsMm, 1)));
    format3d(ax2, 3);

    ax3 = nexttile(tl, 3);
    hold(ax3, 'on');
    drawTri(ax3, getMesh(meshes, 'TRgridSkin'), [0.15 0.45 0.90], 0.24, [0.20 0.28 0.40]);
    drawTri(ax3, getMesh(meshes, 'TRskin'), [0.78 0.80 0.84], 0.08, 'none');
    if opts.showExclusions
        drawExclusions(ax3, report);
    end
    title(ax3, 'Sparse grid source and keepouts');
    format3d(ax3, 3);

    ax4 = nexttile(tl, 4);
    hold(ax4, 'on');
    drawTri(ax4, getMesh(meshes, 'TRrails'), [0.05 0.24 0.82], 0.80, 'none');
    drawTri(ax4, getMesh(meshes, 'TRmarkers'), [0.95 0.45 0.10], 0.90, 'none');
    if opts.showExclusions
        drawExclusions(ax4, report);
    end
    title(ax4, 'Top-down print-frame footprint');
    format3d(ax4, 2);

    title(tl, replayTitle(report), 'FontWeight', 'bold', 'Interpreter', 'none');
end

function drawExclusions(ax, report)
    ears = getOptionalField(report, 'earExclusions', struct());
    if isstruct(ears) && isfield(ears, 'exclusionCenters') && ...
            isfield(ears, 'exclusionRadiusMM') && ~isempty(ears.exclusionCenters)
        centers = double(ears.exclusionCenters);
        radii = double(ears.exclusionRadiusMM(:));
        if isscalar(radii) && size(centers, 1) > 1
            radii = repmat(radii, size(centers, 1), 1);
        end
        for i = 1:min(size(centers, 1), numel(radii))
            drawSphere(ax, centers(i, :), radii(i), [0.75 0.05 0.75], 0.12);
        end
    end

    implants = getOptionalField(report, 'implantExclusions', struct([]));
    for i = 1:numel(implants)
        if isfield(implants(i), 'keepoutBoundaryMm') && ...
                ~isempty(implants(i).keepoutBoundaryMm)
            B = double(implants(i).keepoutBoundaryMm);
            plot3(ax, B(:, 1), B(:, 2), B(:, 3), ...
                '-', 'Color', [0.95 0.05 0.25], 'LineWidth', 2.0);
        elseif isfield(implants(i), 'projectedCoordinatesMm') && ...
                ~isempty(implants(i).projectedCoordinatesMm)
            P = double(implants(i).projectedCoordinatesMm);
            scatter3(ax, P(:, 1), P(:, 2), P(:, 3), ...
                12, [0.95 0.05 0.25], 'filled');
        end
    end
end

function low = lowestRailVertices(meshes, count)
    TRrails = getMesh(meshes, 'TRrails');
    low = struct('indices', [], 'pointsMm', zeros(0, 3));
    if isempty(TRrails) || isempty(TRrails.Points) || count <= 0
        return;
    end
    V = double(TRrails.Points);
    [~, order] = sort(V(:, 3), 'ascend');
    order = order(1:min(count, numel(order)));
    low.indices = order(:);
    low.pointsMm = V(order, :);
end

function titleText = replayTitle(report)
    tag = char(getOptionalField(report, 'fitCheckTag', 'fit check'));
    titleText = sprintf('PLA fit-check replay: %s', tag);
end

function TR = getMesh(meshes, fieldName)
    TR = [];
    if isstruct(meshes) && isfield(meshes, fieldName)
        TR = meshes.(fieldName);
    end
end

function drawTri(ax, TR, color, alphaValue, edgeColor)
    if isempty(TR) || isempty(TR.Points)
        return;
    end
    patch(ax, 'Faces', TR.ConnectivityList, 'Vertices', TR.Points, ...
        'FaceColor', color, 'FaceAlpha', alphaValue, ...
        'EdgeColor', edgeColor, 'FaceLighting', 'flat', ...
        'AmbientStrength', 0.85, 'DiffuseStrength', 0.25, ...
        'SpecularStrength', 0);
end

function drawSphere(ax, center, radius, color, alphaValue)
    [X, Y, Z] = sphere(24);
    surf(ax, center(1) + radius * X, center(2) + radius * Y, ...
        center(3) + radius * Z, ...
        'FaceColor', color, 'FaceAlpha', alphaValue, ...
        'EdgeColor', 'none', 'FaceLighting', 'flat', ...
        'AmbientStrength', 0.85, 'DiffuseStrength', 0.25);
end

function format3d(ax, viewMode)
    axis(ax, 'equal');
    axis(ax, 'vis3d');
    grid(ax, 'on');
    xlabel(ax, 'X print mm');
    ylabel(ax, 'Y print mm');
    zlabel(ax, 'Z print mm');
    if viewMode == 2
        view(ax, 2);
    else
        view(ax, 3);
    end
    camlight(ax, 'headlight');
    lighting(ax, 'flat');
end

function saveReplayFigure(fig, fileName)
    try
        exportgraphics(fig, fileName, 'Resolution', 220);
    catch
        saveas(fig, fileName);
    end
end

function TR = ensureTriangulation(value)
    if isa(value, 'triangulation')
        TR = value;
    elseif isstruct(value) && isfield(value, 'ConnectivityList') && ...
            isfield(value, 'Points')
        TR = triangulation(double(value.ConnectivityList), double(value.Points));
    else
        TR = [];
    end
end

function S = firstStruct(raw)
    preferred = {'outForSave', 'outSaved', 'out'};
    for i = 1:numel(preferred)
        if isfield(raw, preferred{i}) && isstruct(raw.(preferred{i}))
            S = raw.(preferred{i});
            return;
        end
    end
    names = fieldnames(raw);
    for i = 1:numel(names)
        if isstruct(raw.(names{i}))
            S = raw.(names{i});
            return;
        end
    end
    error('acsReplayCapMakerFitCheck:NoStruct', ...
        'MAT file does not contain a readable struct.');
end

function value = getOptionalField(S, fieldName, defaultValue)
    if isstruct(S) && isfield(S, fieldName) && ~isempty(S.(fieldName))
        value = S.(fieldName);
    else
        value = defaultValue;
    end
end

function fileName = expandUserPath(fileName)
    if isempty(fileName)
        return;
    end
    if startsWith(fileName, '~')
        homeDir = getenv('HOME');
        if isempty(homeDir)
            homeDir = char(java.lang.System.getProperty('user.home'));
        end
        fileName = fullfile(homeDir, fileName(2:end));
    end
end

function ensureDir(folder)
    if ~isempty(folder) && exist(folder, 'dir') ~= 7
        mkdir(folder);
    end
end
