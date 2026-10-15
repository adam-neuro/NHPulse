function out = nhpulseMakeDualMaterialPrintCoupon(varargin)
% NHPULSEMAKEDUALMATERIALPRINTCOUPON Make a quick PLA-to-TPE test print.
%
% out = nhpulseMakeDualMaterialPrintCoupon() writes coordinated PLA and TPE
% STL files. The coupon places a few millimeters of TPE directly on a PLA
% base so users can test dual-extruder assignment, material switching, bed
% adhesion, inter-material adhesion, and flexible-filament feeding before a
% longer cap print.
%
% Name-value options:
%   outputDir    : destination folder [outputs/printerTests/...]
%   tag          : output filename stem ['nhpulse_dual_material_coupon']
%   footprintMm  : PLA X/Y dimensions [[25 25]]
%   plaHeightMm  : PLA base height [2]
%   tpeHeightMm  : TPE top height [2]
%   tpeInsetMm   : inset from each PLA edge [1]
%   force        : overwrite existing outputs [false]
%   showFigures  : show preview [true]
%   saveFigures  : save preview PNG [true]
%   verbose      : print output paths [true]

% Import both STL files into the slicer without changing their relative
% coordinates, assign PLA and TPE to their respective extruders, then merge.

    opts = parseInputs(varargin{:});
    ensureDir(opts.outputDir);
    files = outputFiles(opts);
    requireWritable(files, opts.force);

    half = opts.footprintMm / 2;
    TRpla = boxTriangulation([-half(1), -half(2), 0], ...
        [half(1), half(2), opts.plaHeightMm]);
    tpeHalf = half - opts.tpeInsetMm;
    TRtpe = boxTriangulation([-tpeHalf(1), -tpeHalf(2), opts.plaHeightMm], ...
        [tpeHalf(1), tpeHalf(2), opts.plaHeightMm + opts.tpeHeightMm]);

    stlwrite_boxsafe(TRpla, files.plaStl);
    stlwrite_boxsafe(TRtpe, files.tpeStl);

    if opts.showFigures || opts.saveFigures
        fig = previewFigure(TRpla, TRtpe, opts.showFigures);
        if opts.saveFigures
            saveFigure(fig, files.previewPng);
        end
        if ~opts.showFigures
            close(fig);
        end
    end

    out = struct();
    out.schema = 'nhpulse.printerTest';
    out.schemaVersion = 1;
    out.kind = 'dualMaterialCoupon';
    out.createdOn = char(datetime('now'));
    out.outputDir = opts.outputDir;
    out.plaStlFile = files.plaStl;
    out.tpeStlFile = files.tpeStl;
    out.qcFigure = files.previewPng;
    out.reportMat = files.reportMat;
    out.dimensions = struct('footprintMm', opts.footprintMm, ...
        'plaHeightMm', opts.plaHeightMm, 'tpeHeightMm', opts.tpeHeightMm, ...
        'tpeInsetMm', opts.tpeInsetMm);
    out.meshes = struct('pla', meshStats(TRpla), 'tpe', meshStats(TRtpe));
    save(files.reportMat, 'out');

    if opts.verbose
        fprintf('\nNHPulse dual-material printer coupon\n');
        fprintf('  PLA: %s\n', files.plaStl);
        fprintf('  TPE: %s\n', files.tpeStl);
        fprintf('  footprint: %.1f x %.1f mm; PLA/TPE heights: %.1f / %.1f mm\n', ...
            opts.footprintMm(1), opts.footprintMm(2), ...
            opts.plaHeightMm, opts.tpeHeightMm);
    end
    if nargout == 0
        clear out
    end
end

function opts = parseInputs(varargin)
    defaultDir = fullfile(pwd, 'outputs', 'printerTests', ...
        'dualMaterialCoupon');
    p = inputParser;
    p.FunctionName = mfilename;
    addParameter(p, 'outputDir', defaultDir, @isTextScalar);
    addParameter(p, 'tag', 'nhpulse_dual_material_coupon', @isTextScalar);
    addParameter(p, 'footprintMm', [25 25], @isPositivePair);
    addParameter(p, 'plaHeightMm', 2, @isPositiveScalar);
    addParameter(p, 'tpeHeightMm', 2, @isPositiveScalar);
    addParameter(p, 'tpeInsetMm', 1, @isNonnegativeScalar);
    addParameter(p, 'force', false, @isBoolLike);
    addParameter(p, 'showFigures', true, @isBoolLike);
    addParameter(p, 'saveFigures', true, @isBoolLike);
    addParameter(p, 'verbose', true, @isBoolLike);
    parse(p, varargin{:});
    opts = p.Results;
    opts.outputDir = char(opts.outputDir);
    opts.tag = safeTag(opts.tag);
    opts.footprintMm = double(opts.footprintMm(:)');
    opts.plaHeightMm = double(opts.plaHeightMm);
    opts.tpeHeightMm = double(opts.tpeHeightMm);
    opts.tpeInsetMm = double(opts.tpeInsetMm);
    opts.force = logical(opts.force);
    opts.showFigures = logical(opts.showFigures);
    opts.saveFigures = logical(opts.saveFigures);
    opts.verbose = logical(opts.verbose);
    if any(opts.footprintMm <= 2 * opts.tpeInsetMm)
        error('nhpulseMakeDualMaterialPrintCoupon:InsetTooLarge', ...
            'tpeInsetMm must be smaller than half of each footprint dimension.');
    end
end

function files = outputFiles(opts)
    files = struct();
    files.plaStl = fullfile(opts.outputDir, [opts.tag '_pla.stl']);
    files.tpeStl = fullfile(opts.outputDir, [opts.tag '_tpe.stl']);
    files.previewPng = fullfile(opts.outputDir, [opts.tag '_preview.png']);
    files.reportMat = fullfile(opts.outputDir, [opts.tag '_report.mat']);
end

function TR = boxTriangulation(lo, hi)
    x0 = lo(1); y0 = lo(2); z0 = lo(3);
    x1 = hi(1); y1 = hi(2); z1 = hi(3);
    V = [x0 y0 z0; x1 y0 z0; x1 y1 z0; x0 y1 z0; ...
         x0 y0 z1; x1 y0 z1; x1 y1 z1; x0 y1 z1];
    F = [1 3 2; 1 4 3; 5 6 7; 5 7 8; ...
         1 2 6; 1 6 5; 2 3 7; 2 7 6; ...
         3 4 8; 3 8 7; 4 1 5; 4 5 8];
    TR = triangulation(F, V);
end

function fig = previewFigure(TRpla, TRtpe, visible)
    fig = figure('Name', 'NHPulse dual-material printer coupon', ...
        'Color', 'w', 'Visible', onOff(visible), ...
        'Position', centeredPosition([760 620]));
    ax = axes(fig);
    hold(ax, 'on');
    trisurf(TRpla, 'Parent', ax, 'FaceColor', [0.82 0.82 0.84], ...
        'EdgeColor', [0.35 0.35 0.38], 'FaceAlpha', 0.9);
    trisurf(TRtpe, 'Parent', ax, 'FaceColor', [0.15 0.42 0.82], ...
        'EdgeColor', [0.05 0.18 0.40], 'FaceAlpha', 0.9);
    hold(ax, 'off');
    axis(ax, 'equal'); axis(ax, 'vis3d'); grid(ax, 'on'); view(ax, 35, 25);
    xlabel(ax, 'X (mm)'); ylabel(ax, 'Y (mm)'); zlabel(ax, 'Z (mm)');
    title(ax, 'PLA base with TPE adhesion layer');
    legend(ax, {'PLA', 'TPE'}, 'Location', 'best');
    camlight(ax, 'headlight'); lighting(ax, 'gouraud');
end

function saveFigure(fig, fileName)
    try
        exportgraphics(fig, fileName, 'Resolution', 180);
    catch
        saveas(fig, fileName);
    end
end

function stats = meshStats(TR)
    stats = struct('vertices', size(TR.Points, 1), ...
        'faces', size(TR.ConnectivityList, 1), ...
        'boundsMin', min(TR.Points, [], 1), ...
        'boundsMax', max(TR.Points, [], 1));
end

function requireWritable(files, force)
    names = struct2cell(files);
    for i = 1:numel(names)
        if exist(names{i}, 'file') == 2 && ~force
            error('nhpulseMakeDualMaterialPrintCoupon:OutputExists', ...
                'Output exists; use force=true to overwrite: %s', names{i});
        end
    end
end

function ensureDir(folder)
    if exist(folder, 'dir') ~= 7, mkdir(folder); end
end

function value = safeTag(value)
    value = regexprep(char(value), '[^A-Za-z0-9_.-]+', '_');
    value = regexprep(value, '(^_+|_+$)', '');
    if isempty(value), value = 'nhpulse_dual_material_coupon'; end
end

function pos = centeredPosition(sz)
    screen = get(groot, 'ScreenSize');
    sz = min(sz, [screen(3)-80, screen(4)-120]);
    pos = [max(20, screen(1)+(screen(3)-sz(1))/2), ...
        max(40, screen(2)+(screen(4)-sz(2))/2), sz];
end

function value = onOff(tf)
    if tf, value = 'on'; else, value = 'off'; end
end

function tf = isTextScalar(x), tf = ischar(x) || (isstring(x) && isscalar(x)); end
function tf = isPositivePair(x), tf = isnumeric(x) && numel(x)==2 && all(isfinite(x)) && all(x>0); end
function tf = isPositiveScalar(x), tf = isnumeric(x) && isscalar(x) && isfinite(x) && x>0; end
function tf = isNonnegativeScalar(x), tf = isnumeric(x) && isscalar(x) && isfinite(x) && x>=0; end
function tf = isBoolLike(x), tf = (islogical(x)||isnumeric(x)) && isscalar(x); end
