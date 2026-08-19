function out = nhpulseCreateSyntheticHeadpostTrace(surfaceSource, varargin)
% NHPULSECREATESYNTHETICHEADPOSTTRACE Create a toy headpost trace in print mm.
%
% out = nhpulseCreateSyntheticHeadpostTrace(skinCacheFile) samples a circular
% trace above a capMaker scalp mesh. The result mimics the subset of an
% implant/Polhemus trace product needed by acsPlanHeadpostPlacement.
%
% This is a synthetic demonstration helper only. It is not intended to model
% the exact geometry of any real implant or digitizer trace.

    if nargin < 1 || isempty(surfaceSource)
        error('nhpulseCreateSyntheticHeadpostTrace:MissingSurface', ...
            'Provide a capMaker skin cache, triangulation, or point matrix.');
    end

    opts = parseInputs(varargin{:});
    TRskin = readSkinSurface(surfaceSource);
    V = double(TRskin.Points);
    if size(V, 1) < 3
        error('nhpulseCreateSyntheticHeadpostTrace:EmptySurface', ...
            'The supplied skin surface has fewer than three vertices.');
    end

    centerXY = opts.centerXYMm;
    if isempty(centerXY)
        centerXY = defaultHeadpostCenterXY(V);
    else
        centerXY = double(centerXY(:)');
    end

    theta = linspace(0, 2*pi, opts.nPoints + 1)';
    theta(end) = [];
    xy = centerXY + opts.radiusMm .* [cos(theta), sin(theta)];
    z = surfaceZAtXY(V, xy) + opts.heightAboveSurfaceMm;
    coords = [xy, z(:)];
    labels = arrayfun(@(i) sprintf('headpost_%03d', i), ...
        (1:size(coords, 1))', 'UniformOutput', false);

    out = struct();
    out.createdOn = char(datetime('now'));
    out.type = 'syntheticHeadpostTrace';
    out.name = 'headpost';
    out.coordinateFrame = 'capMakerPrintMm';
    out.traceCoordinatesMm = coords;
    out.coordinatesMm = coords;
    out.labels = labels(:);
    out.traceSets = struct( ...
        'name', 'headpost', ...
        'rows', (1:size(coords, 1))', ...
        'labels', {labels(:)}, ...
        'coordinatesMm', coords);
    out.centerXYMm = centerXY;
    out.radiusMm = opts.radiusMm;
    out.heightAboveSurfaceMm = opts.heightAboveSurfaceMm;
    out.source = sourceInfo(surfaceSource);
    out.options = opts;

    fig = [];
    qcFile = '';
    if opts.showFigure || opts.saveFigure
        figVisible = 'off';
        if opts.showFigure
            figVisible = 'on';
        end
        fig = makeQcFigure(TRskin, coords, centerXY, figVisible);
        if opts.saveFigure
            if isempty(opts.outputFile)
                qcFile = fullfile(pwd, 'syntheticHeadpostTrace_qc.png');
            else
                qcFile = replaceExtension(opts.outputFile, '_qc.png');
            end
            ensureDir(fileparts(qcFile));
            exportgraphics(fig, qcFile, 'Resolution', 180);
        end
        if ~opts.showFigure && isgraphics(fig)
            close(fig);
            fig = [];
        end
    end
    out.qcFigure = qcFile;
    if isgraphics(fig)
        out.figure = fig;
    end

    if ~isempty(opts.outputFile)
        ensureDir(fileparts(opts.outputFile));
        outForSave = out;
        if isfield(outForSave, 'figure')
            outForSave = rmfield(outForSave, 'figure');
        end
        out = outForSave; %#ok<NASGU>
        outSaved = outForSave; %#ok<NASGU>
        outToSave = outForSave; %#ok<NASGU>
        save(opts.outputFile, 'out', 'outForSave', 'outSaved', ...
            'outToSave', '-v7.3');
        out = outForSave;
    end

    if opts.verbose
        fprintf('\nSynthetic headpost trace\n');
        fprintf('  points: %d\n', size(coords, 1));
        fprintf('  center XY: [%.2f %.2f] mm\n', centerXY(1), centerXY(2));
        if ~isempty(opts.outputFile)
            fprintf('  output: %s\n', opts.outputFile);
        end
    end
end

function opts = parseInputs(varargin)
    p = inputParser;
    p.FunctionName = 'nhpulseCreateSyntheticHeadpostTrace';
    addParameter(p, 'outputFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'centerXYMm', [], ...
        @(x) isempty(x) || (isnumeric(x) && numel(x) == 2));
    addParameter(p, 'radiusMm', 12.625, @isPositiveScalar);
    addParameter(p, 'nPoints', 96, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 8);
    addParameter(p, 'heightAboveSurfaceMm', 5, @isNonnegativeScalar);
    addParameter(p, 'showFigure', false, @isBoolLike);
    addParameter(p, 'saveFigure', false, @isBoolLike);
    addParameter(p, 'verbose', true, @isBoolLike);
    parse(p, varargin{:});

    opts = p.Results;
    opts.outputFile = expandUserPath(char(opts.outputFile));
    if ~isempty(opts.centerXYMm)
        opts.centerXYMm = double(opts.centerXYMm(:)');
    end
    opts.radiusMm = double(opts.radiusMm);
    opts.nPoints = round(double(opts.nPoints));
    opts.heightAboveSurfaceMm = double(opts.heightAboveSurfaceMm);
    opts.showFigure = logical(opts.showFigure);
    opts.saveFigure = logical(opts.saveFigure);
    opts.verbose = logical(opts.verbose);
end

function tf = isBoolLike(x)
    tf = (islogical(x) || isnumeric(x)) && isscalar(x);
end

function tf = isPositiveScalar(x)
    tf = isnumeric(x) && isscalar(x) && isfinite(x) && x > 0;
end

function tf = isNonnegativeScalar(x)
    tf = isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0;
end

function TRskin = readSkinSurface(source)
    if isa(source, 'triangulation')
        TRskin = source;
        return;
    end
    if isnumeric(source)
        TRskin = triangulation(zeros(0, 3), double(source));
        return;
    end
    if isstruct(source)
        if isfield(source, 'TRskin') && ~isempty(source.TRskin)
            TRskin = source.TRskin;
            return;
        elseif isfield(source, 'cacheFile') && ~isempty(source.cacheFile)
            TRskin = readSkinSurface(char(source.cacheFile));
            return;
        elseif isfield(source, 'outputFile') && ~isempty(source.outputFile)
            TRskin = readSkinSurface(char(source.outputFile));
            return;
        end
    end
    if ischar(source) || isstring(source)
        fileName = expandUserPath(char(source));
        if exist(fileName, 'file') ~= 2
            error('nhpulseCreateSyntheticHeadpostTrace:SurfaceNotFound', ...
                'Skin surface file not found: %s', fileName);
        end
        S = load(fileName, 'TRskin');
        if ~isfield(S, 'TRskin') || isempty(S.TRskin)
            error('nhpulseCreateSyntheticHeadpostTrace:BadSkinCache', ...
                'Skin cache does not contain TRskin: %s', fileName);
        end
        TRskin = S.TRskin;
        return;
    end
    error('nhpulseCreateSyntheticHeadpostTrace:BadSurface', ...
        'Unsupported skin surface input.');
end

function info = sourceInfo(source)
    info = struct('type', class(source), 'file', '');
    if ischar(source) || isstring(source)
        info.file = expandUserPath(char(source));
    elseif isstruct(source) && isfield(source, 'cacheFile')
        info.file = char(source.cacheFile);
    elseif isstruct(source) && isfield(source, 'outputFile')
        info.file = char(source.outputFile);
    end
end

function centerXY = defaultHeadpostCenterXY(V)
    boundsMin = min(V, [], 1);
    boundsMax = max(V, [], 1);
    span = boundsMax - boundsMin;
    midX = 0.5 * (boundsMin(1) + boundsMax(1));
    midY = 0.5 * (boundsMin(2) + boundsMax(2));
    rows = abs(V(:, 1) - midX) <= 0.20 * span(1) & ...
        abs(V(:, 2) - midY) <= 0.30 * span(2);
    if nnz(rows) < 3
        rows = true(size(V, 1), 1);
    end
    idx = find(rows);
    [~, local] = max(V(idx, 3));
    centerXY = V(idx(local), 1:2);
end

function z = surfaceZAtXY(V, xy)
    z = zeros(size(xy, 1), 1);
    for i = 1:size(xy, 1)
        d2 = sum((V(:, 1:2) - xy(i, :)) .^ 2, 2);
        [~, order] = sort(d2, 'ascend');
        rows = order(1:min(12, numel(order)));
        z(i) = max(V(rows, 3));
    end
end

function fig = makeQcFigure(TRskin, coords, centerXY, figVisible)
    fig = figure('Name', 'Synthetic headpost trace QC', ...
        'NumberTitle', 'off', 'Color', 'w', 'Visible', figVisible, ...
        'Position', [100 100 850 650]);
    ax = axes(fig); %#ok<LAXES>
    hold(ax, 'on');
    trisurf(TRskin.ConnectivityList, TRskin.Points(:, 1), ...
        TRskin.Points(:, 2), TRskin.Points(:, 3), ...
        'Parent', ax, 'FaceColor', [0.80 0.82 0.84], ...
        'FaceAlpha', 0.35, 'EdgeColor', 'none');
    scatter3(ax, coords(:, 1), coords(:, 2), coords(:, 3), ...
        28, [0.88 0.10 0.12], 'filled');
    plot3(ax, centerXY(1), centerXY(2), mean(coords(:, 3)), ...
        'kp', 'MarkerFaceColor', [1 0.9 0.2], 'MarkerSize', 12);
    axis(ax, 'equal');
    grid(ax, 'on');
    xlabel(ax, 'X print mm');
    ylabel(ax, 'Y print mm');
    zlabel(ax, 'Z print mm');
    view(ax, 40, 24);
    camlight(ax, 'headlight');
    lighting(ax, 'flat');
    title(ax, 'Synthetic headpost trace');
end

function ensureDir(folder)
    if isempty(folder)
        return;
    end
    if exist(folder, 'dir') ~= 7
        mkdir(folder);
    end
end

function fileName = replaceExtension(fileName, suffix)
    [folder, stem] = fileparts(fileName);
    fileName = fullfile(folder, [stem suffix]);
end

function pathOut = expandUserPath(pathOut)
    if isempty(pathOut)
        return;
    end
    pathOut = char(pathOut);
    if startsWith(pathOut, '~')
        homeDir = char(java.lang.System.getProperty('user.home'));
        if numel(pathOut) == 1
            pathOut = homeDir;
        elseif any(pathOut(2) == ['/' filesep])
            pathOut = fullfile(homeDir, pathOut(3:end));
        end
    end
end
