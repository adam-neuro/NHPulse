function out = nhpulseMakeDomeRailPrintCoupon(varargin)
% NHPULSEMAKEDOMERAILPRINTCOUPON Make a cap-like PLA/TPE printer test.
%
% out = nhpulseMakeDomeRailPrintCoupon() builds a small curved triangular
% TPE rail network and the same column-wise PLA underfill used by capMaker.
% It is a more demanding follow-up to nhpulseMakeDualMaterialPrintCoupon:
% curvature, rail junctions, material switching, support contact, and PLA
% removal are exercised without printing a complete subject-specific cap.
%
% Name-value options:
%   outputDir       : destination folder [outputs/printerTests/...]
%   tag             : output filename stem ['nhpulse_dome_rail_coupon']
%   domeRadiusMm    : dome base radius [25]
%   domeRiseMm      : dome height above printer bed [10]
%   radialDivisions : radial surface rings [4]
%   angularDivisions: sectors around dome [12]
%   railWidthMm     : TPE rail width [2]
%   railHeightMm    : TPE rail height [2.4]
%   voxelSizeMm     : fusion/underfill raster spacing [0.5]
%   plaMarginMm     : PLA footprint margin around rails [1]
%   force           : overwrite existing outputs [false]
%   showFigures     : show preview [true]
%   saveFigures     : save preview PNG [true]
%   verbose         : print progress and paths [true]

    opts = parseInputs(varargin{:});
    ensureDir(opts.outputDir);
    files = outputFiles(opts);
    requireWritable(files, opts.force);

    TRsurface = sphericalCapTriangulation(opts.domeRadiusMm, ...
        opts.domeRiseMm, opts.radialDivisions, opts.angularDivisions);
    [TRrailSource, railInfo] = makeEdgeRails(TRsurface, ...
        opts.railWidthMm, opts.railHeightMm, 0, 0, 0, [], ...
        'PerimeterFactor', 1.25, 'Verbose', opts.verbose);

    fuseOpts = struct('voxelSize', opts.voxelSizeMm, 'padVox', 4, ...
        'zBed', 0, 'tol', 1e-9, 'manifoldize', false, 'closeVox', 0);
    if opts.verbose
        fprintf('Voxel-fusing dome TPE rails at %.3g mm resolution.\n', ...
            opts.voxelSizeMm);
    end
    [TRtpe, occTpe] = fuseTriListVoxel({TRrailSource}, fuseOpts);
    occPla = plaUnderfillFromTPE(occTpe, [], struct( ...
        'marginMM', opts.plaMarginMm, 'closeXYVox', 1, ...
        'keepLargestXY', true, 'padBottomEmpty', false));
    boundsMin = [min(occPla.x), min(occPla.y), min(occPla.z)];
    boundsMax = [max(occPla.x), max(occPla.y), max(occPla.z)];
    [TRpla, ~] = cropOccOutAABB_watertight(occPla, boundsMin, boundsMax, ...
        struct('keepLargest', true, 'padEmptyVox', 1, 'closeVox', 0));
    requireNonempty(TRtpe, 'TPE rail');
    requireNonempty(TRpla, 'PLA underfill');

    stlwrite_boxsafe(TRpla, files.plaStl);
    stlwrite_boxsafe(TRtpe, files.tpeStl);

    if opts.showFigures || opts.saveFigures
        fig = previewFigure(TRpla, TRtpe, opts.showFigures);
        if opts.saveFigures, saveFigure(fig, files.previewPng); end
        if ~opts.showFigures, close(fig); end
    end

    out = struct();
    out.schema = 'nhpulse.printerTest';
    out.schemaVersion = 1;
    out.kind = 'domeRailCoupon';
    out.createdOn = char(datetime('now'));
    out.outputDir = opts.outputDir;
    out.plaStlFile = files.plaStl;
    out.tpeStlFile = files.tpeStl;
    out.qcFigure = files.previewPng;
    out.reportMat = files.reportMat;
    out.options = optsForSave(opts);
    out.meshes = struct('pla', meshStats(TRpla), 'tpe', meshStats(TRtpe), ...
        'sourceSurface', meshStats(TRsurface), ...
        'sourceRails', meshStats(TRrailSource));
    out.railInfo = railInfo;
    save(files.reportMat, 'out', '-v7.3');

    if opts.verbose
        fprintf('\nNHPulse dome-and-rail printer coupon\n');
        fprintf('  PLA: %s\n', files.plaStl);
        fprintf('  TPE: %s\n', files.tpeStl);
        fprintf('  dome: %.1f mm radius x %.1f mm rise; %d TPE rail faces\n', ...
            opts.domeRadiusMm, opts.domeRiseMm, ...
            size(TRtpe.ConnectivityList, 1));
    end
    if nargout == 0, clear out; end
end

function opts = parseInputs(varargin)
    defaultDir = fullfile(pwd, 'outputs', 'printerTests', 'domeRailCoupon');
    p = inputParser;
    p.FunctionName = mfilename;
    addParameter(p, 'outputDir', defaultDir, @isTextScalar);
    addParameter(p, 'tag', 'nhpulse_dome_rail_coupon', @isTextScalar);
    addParameter(p, 'domeRadiusMm', 25, @isPositiveScalar);
    addParameter(p, 'domeRiseMm', 10, @isPositiveScalar);
    addParameter(p, 'radialDivisions', 4, @isIntegerAtLeastTwo);
    addParameter(p, 'angularDivisions', 12, @isIntegerAtLeastSix);
    addParameter(p, 'railWidthMm', 2, @isPositiveScalar);
    addParameter(p, 'railHeightMm', 2.4, @isPositiveScalar);
    addParameter(p, 'voxelSizeMm', 0.5, @isPositiveScalar);
    addParameter(p, 'plaMarginMm', 1, @isNonnegativeScalar);
    addParameter(p, 'force', false, @isBoolLike);
    addParameter(p, 'showFigures', true, @isBoolLike);
    addParameter(p, 'saveFigures', true, @isBoolLike);
    addParameter(p, 'verbose', true, @isBoolLike);
    parse(p, varargin{:});
    opts = p.Results;
    opts.outputDir = char(opts.outputDir);
    opts.tag = safeTag(opts.tag);
    numericFields = {'domeRadiusMm','domeRiseMm','railWidthMm', ...
        'railHeightMm','voxelSizeMm','plaMarginMm'};
    for i = 1:numel(numericFields)
        opts.(numericFields{i}) = double(opts.(numericFields{i}));
    end
    opts.radialDivisions = round(double(opts.radialDivisions));
    opts.angularDivisions = round(double(opts.angularDivisions));
    opts.force = logical(opts.force);
    opts.showFigures = logical(opts.showFigures);
    opts.saveFigures = logical(opts.saveFigures);
    opts.verbose = logical(opts.verbose);
    if opts.domeRiseMm >= 2 * opts.domeRadiusMm
        error('nhpulseMakeDomeRailPrintCoupon:BadDomeShape', ...
            'domeRiseMm must be less than twice domeRadiusMm.');
    end
end

function TR = sphericalCapTriangulation(radius, rise, nRadial, nAngular)
    sphereRadius = (radius^2 + rise^2) / (2 * rise);
    zCenter = rise - sphereRadius;
    V = [0 0 rise];
    for ring = 1:nRadial
        r = radius * ring / nRadial;
        z = zCenter + sqrt(max(sphereRadius^2 - r^2, 0));
        theta = (0:(nAngular-1))' * (2*pi/nAngular);
        V = [V; r*cos(theta), r*sin(theta), repmat(z, nAngular, 1)]; %#ok<AGROW>
    end
    F = zeros(0, 3);
    firstRing = 2:(nAngular+1);
    for j = 1:nAngular
        j2 = mod(j, nAngular) + 1;
        F(end+1, :) = [1 firstRing(j2) firstRing(j)]; %#ok<AGROW>
    end
    for ring = 1:(nRadial-1)
        a0 = 2 + (ring-1)*nAngular;
        b0 = a0 + nAngular;
        for j = 1:nAngular
            j2 = mod(j, nAngular) + 1;
            a = a0+j-1; a2 = a0+j2-1;
            b = b0+j-1; b2 = b0+j2-1;
            F(end+1, :) = [a a2 b2]; %#ok<AGROW>
            F(end+1, :) = [a b2 b]; %#ok<AGROW>
        end
    end
    TR = triangulation(F, V);
end

function files = outputFiles(opts)
    files = struct('plaStl', fullfile(opts.outputDir, [opts.tag '_pla.stl']), ...
        'tpeStl', fullfile(opts.outputDir, [opts.tag '_tpe.stl']), ...
        'previewPng', fullfile(opts.outputDir, [opts.tag '_preview.png']), ...
        'reportMat', fullfile(opts.outputDir, [opts.tag '_report.mat']));
end

function fig = previewFigure(TRpla, TRtpe, visible)
    fig = figure('Name', 'NHPulse dome-and-rail printer coupon', ...
        'Color', 'w', 'Visible', onOff(visible), ...
        'Position', centeredPosition([820 680]));
    ax = axes(fig); hold(ax, 'on');
    trisurf(TRpla, 'Parent', ax, 'FaceColor', [0.82 0.82 0.84], ...
        'EdgeColor', 'none', 'FaceAlpha', 0.85);
    trisurf(TRtpe, 'Parent', ax, 'FaceColor', [0.12 0.38 0.82], ...
        'EdgeColor', [0.04 0.12 0.30], 'FaceAlpha', 0.95);
    hold(ax, 'off'); axis(ax, 'equal'); axis(ax, 'vis3d'); grid(ax, 'on');
    view(ax, 40, 28); xlabel(ax, 'X (mm)'); ylabel(ax, 'Y (mm)');
    zlabel(ax, 'Z (mm)'); title(ax, 'Cap-like TPE rails with PLA underfill');
    legend(ax, {'PLA underfill', 'TPE rails'}, 'Location', 'best');
    camlight(ax, 'headlight'); lighting(ax, 'gouraud');
end

function saveFigure(fig, fileName)
    try
        exportgraphics(fig, fileName, 'Resolution', 180);
    catch
        saveas(fig, fileName);
    end
end

function requireNonempty(TR, label)
    if isempty(TR) || isempty(TR.ConnectivityList)
        error('nhpulseMakeDomeRailPrintCoupon:EmptyGeometry', ...
            '%s geometry is empty.', label);
    end
end

function stats = meshStats(TR)
    stats = struct('vertices', size(TR.Points,1), ...
        'faces', size(TR.ConnectivityList,1), ...
        'boundsMin', min(TR.Points,[],1), 'boundsMax', max(TR.Points,[],1));
end

function value = optsForSave(opts)
    value = opts;
end

function requireWritable(files, force)
    names = struct2cell(files);
    for i = 1:numel(names)
        if exist(names{i}, 'file') == 2 && ~force
            error('nhpulseMakeDomeRailPrintCoupon:OutputExists', ...
                'Output exists; use force=true to overwrite: %s', names{i});
        end
    end
end

function ensureDir(folder), if exist(folder,'dir')~=7, mkdir(folder); end, end
function value = safeTag(value), value=regexprep(char(value),'[^A-Za-z0-9_.-]+','_'); value=regexprep(value,'(^_+|_+$)',''); if isempty(value), value='nhpulse_dome_rail_coupon'; end, end
function pos = centeredPosition(sz), screen=get(groot,'ScreenSize'); sz=min(sz,[screen(3)-80 screen(4)-120]); pos=[max(20,screen(1)+(screen(3)-sz(1))/2) max(40,screen(2)+(screen(4)-sz(2))/2) sz]; end
function value = onOff(tf), if tf, value='on'; else, value='off'; end, end
function tf = isTextScalar(x), tf=ischar(x)||(isstring(x)&&isscalar(x)); end
function tf = isPositiveScalar(x), tf=isnumeric(x)&&isscalar(x)&&isfinite(x)&&x>0; end
function tf = isNonnegativeScalar(x), tf=isnumeric(x)&&isscalar(x)&&isfinite(x)&&x>=0; end
function tf = isIntegerAtLeastTwo(x), tf=isnumeric(x)&&isscalar(x)&&isfinite(x)&&x>=2&&x==round(x); end
function tf = isIntegerAtLeastSix(x), tf=isnumeric(x)&&isscalar(x)&&isfinite(x)&&x>=6&&x==round(x); end
function tf = isBoolLike(x), tf=(islogical(x)||isnumeric(x))&&isscalar(x); end
