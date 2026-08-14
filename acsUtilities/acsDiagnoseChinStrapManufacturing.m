function out = acsDiagnoseChinStrapManufacturing(manufacturingIn, varargin)
% ACSDIAGNOSECHINSTRAPMANUFACTURING Visualize strap occupancy through STL stages.
%
% out = acsDiagnoseChinStrapManufacturing(manufacturing) loads the saved
% manufacturing mesh MAT file, reconstructs the intended procedural strap
% occupancy from saved anchors/parameters, and compares it to each raster
% stage saved by acsBuildCapMakerManufacturingStl.
%
% The key diagnostic is the X/Z projection in each strap-local frame:
%   gray   = intended strap voxel, absent in this stage
%   blue   = stage voxel matching intended strap voxel
%   red    = extra stage voxel inside the strap local bounding box
%
% Name-value options:
%   strapIndex    : subset of straps to show [[] = all]
%   padMm         : local/world padding around strap extents [2]
%   outputFile    : PNG file for saveFigures ['']
%   showFigures   : show figure [true]
%   saveFigures   : save figure [false]
%   verbose       : print stage table [true]

    if nargin < 1 || isempty(manufacturingIn)
        error('acsDiagnoseChinStrapManufacturing:MissingInput', ...
            'Provide a manufacturing output/report MAT/mesh MAT file.');
    end

    opts = parseInputs(varargin{:});
    addLocalDependencies();

    [report, meshFile, source] = readInputs(manufacturingIn, opts);
    if isempty(meshFile) || exist(meshFile, 'file') ~= 2
        error('acsDiagnoseChinStrapManufacturing:MissingMeshMat', ...
            'Could not find manufacturing mesh MAT file. Rebuild with saveMeshMat=true.');
    end
    S = load(meshFile, 'meshes');
    if ~isfield(S, 'meshes') || ~isstruct(S.meshes)
        error('acsDiagnoseChinStrapManufacturing:BadMeshMat', ...
            'Mesh MAT file does not contain a meshes struct: %s', meshFile);
    end
    stages = collectStages(S.meshes);
    if isempty(stages)
        error('acsDiagnoseChinStrapManufacturing:NoOccupancyStages', ...
            'No saved occupancy stages found in %s.', meshFile);
    end

    strap = savedStrap(report);
    nStraps = size(strap.anchors, 1);
    rows = opts.strapIndex(:).';
    if isempty(rows)
        rows = 1:nStraps;
    end
    rows = rows(rows >= 1 & rows <= nStraps);
    if isempty(rows)
        error('acsDiagnoseChinStrapManufacturing:BadStrapIndex', ...
            'No valid strapIndex values for %d strap(s).', nStraps);
    end

    diagnostics = struct([]);
    summaries = {};
    for r = 1:numel(rows)
        strapIdx = rows(r);
        for s = 1:numel(stages)
            D = diagnoseStage(stages(s), strap, strapIdx, opts);
            diagnostics(end + 1, 1) = D; %#ok<AGROW>
            summaries(end + 1, :) = {strapIdx, stages(s).name, ...
                D.nIntendedVoxels, D.nStageVoxels, D.nMatchingVoxels, ...
                D.nExtraVoxels, D.nMissingVoxels, D.extraOverIntendedPct, ...
                D.missingOverIntendedPct}; %#ok<AGROW>
        end
    end
    summaryTable = cell2table(summaries, 'VariableNames', { ...
        'strapIndex', 'stage', 'intendedVoxels', 'stageVoxelsInBox', ...
        'matchingVoxels', 'extraVoxels', 'missingVoxels', ...
        'extraPctOfIntended', 'missingPctOfIntended'});

    fig = [];
    pngFile = '';
    if opts.showFigures || opts.saveFigures
        figVisible = 'off';
        if opts.showFigures
            figVisible = 'on';
        end
        fig = makeFigure(rows, stages, diagnostics, opts, figVisible);
        if opts.saveFigures
            pngFile = opts.outputFile;
            if isempty(pngFile)
                pngFile = defaultOutputFile(report, meshFile);
            end
            ensureDir(fileparts(pngFile));
            exportgraphics(fig, pngFile, 'Resolution', 180);
        end
        if ~opts.showFigures && isgraphics(fig)
            close(fig);
            fig = [];
        end
    end

    out = struct();
    out.createdOn = char(datetime('now'));
    out.type = 'chinStrapManufacturingDiagnostics';
    out.source = source;
    out.meshFile = meshFile;
    out.strap = strap;
    out.stages = rmfield(stages, 'occ');
    out.diagnostics = diagnostics;
    out.summaryTable = summaryTable;
    out.qcFigure = pngFile;
    if isgraphics(fig)
        out.figure = fig;
    end

    if opts.verbose
        fprintf('\nChin-strap manufacturing diagnostics\n');
        fprintf('  mesh MAT: %s\n', meshFile);
        disp(summaryTable);
    end
end

function opts = parseInputs(varargin)
    p = inputParser;
    p.FunctionName = 'acsDiagnoseChinStrapManufacturing';
    addParameter(p, 'strapIndex', [], @(x) isempty(x) || isnumeric(x));
    addParameter(p, 'padMm', 2, @isNonnegativeScalar);
    addParameter(p, 'outputFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'showFigures', true, @isBoolLike);
    addParameter(p, 'saveFigures', false, @isBoolLike);
    addParameter(p, 'verbose', true, @isBoolLike);
    parse(p, varargin{:});

    opts = p.Results;
    opts.strapIndex = round(double(opts.strapIndex(:)));
    opts.padMm = double(opts.padMm);
    opts.outputFile = expandUserPath(char(opts.outputFile));
    opts.showFigures = logical(opts.showFigures);
    opts.saveFigures = logical(opts.saveFigures);
    opts.verbose = logical(opts.verbose);
end

function [report, meshFile, source] = readInputs(value, opts)
    report = struct();
    meshFile = '';
    source = struct('file', '', 'type', class(value));
    if isstruct(value)
        report = value;
    else
        fileName = expandUserPath(char(value));
        source.file = fileName;
        if exist(fileName, 'file') ~= 2
            error('acsDiagnoseChinStrapManufacturing:MissingFile', ...
                'File not found: %s', fileName);
        end
        S = load(fileName);
        if isfield(S, 'meshes')
            meshFile = fileName;
            source.type = 'meshMat';
        end
        report = firstReportStruct(S);
    end
    if isempty(meshFile)
        meshFile = char(getOptionalField(report, 'meshMat', ''));
    end
    if isempty(meshFile) && isfield(opts, 'meshMat')
        meshFile = char(opts.meshMat);
    end
end

function report = firstReportStruct(S)
    report = struct();
    preferred = {'out', 'outToSave', 'outSaved', 'manufacturing'};
    for i = 1:numel(preferred)
        if isfield(S, preferred{i}) && isstruct(S.(preferred{i}))
            report = S.(preferred{i});
            return;
        end
    end
    names = fieldnames(S);
    for i = 1:numel(names)
        value = S.(names{i});
        if isstruct(value) && isfield(value, 'strap') && isfield(value, 'meshMat')
            report = value;
            return;
        end
    end
end

function stages = collectStages(meshes)
    specs = { ...
        'occTpeRaw',    'fused TPE'; ...
        'occTpeCarved', 'carved TPE'; ...
        'occTpeCrop',   'final TPE crop'; ...
        'occPlaCrop',   'PLA crop'};
    stages = struct('field', {}, 'name', {}, 'occ', {});
    for i = 1:size(specs, 1)
        field = specs{i, 1};
        if isfield(meshes, field) && isstruct(meshes.(field)) && ...
                isfield(meshes.(field), 'occ')
            stages(end + 1, 1) = struct( ... %#ok<AGROW>
                'field', field, ...
                'name', specs{i, 2}, ...
                'occ', meshes.(field));
        end
    end
end

function strap = savedStrap(report)
    if ~isfield(report, 'strap') || ~isstruct(report.strap)
        error('acsDiagnoseChinStrapManufacturing:MissingStrap', ...
            'Manufacturing report does not contain saved strap parameters.');
    end
    strap = report.strap;
    if ~isfield(strap, 'anchors') || isempty(strap.anchors) || ...
            ~isfield(strap, 'outDirs') || isempty(strap.outDirs) || ...
            ~isfield(strap, 'params') || ~isfield(strap, 'frameOptions')
        error('acsDiagnoseChinStrapManufacturing:BadStrap', ...
            'Saved strap struct lacks anchors, outDirs, params, or frameOptions.');
    end
    strap.anchors = double(strap.anchors);
    strap.outDirs = double(strap.outDirs);
end

function D = diagnoseStage(stage, strap, strapIdx, opts)
    occ = stage.occ;
    x = double(occ.x(:).');
    y = double(occ.y(:).');
    z = double(occ.z(:).');
    B = logical(occ.occ);
    anchor = strap.anchors(strapIdx, :);
    outDir = strap.outDirs(strapIdx, :);
    params = strap.params;
    frameOpts = strap.frameOptions;

    extent = strapExtentPoints(anchor, outDir, params, frameOpts);
    bbMin = min(extent, [], 1) - opts.padMm;
    bbMax = max(extent, [], 1) + opts.padMm;
    ix = find(x >= bbMin(1) & x <= bbMax(1));
    iy = find(y >= bbMin(2) & y <= bbMax(2));
    iz = find(z >= bbMin(3) & z <= bbMax(3));
    if isempty(ix) || isempty(iy) || isempty(iz)
        D = emptyDiagnostic(stage, strapIdx);
        return;
    end

    xs = x(ix);
    ys = y(iy);
    zs = z(iz);
    stageOcc = B(ix, iy, iz);
    [X, Y, Z] = ndgrid(xs, ys, zs);
    intended = logical(strapFn_world(X, Y, Z, anchor, outDir, params, frameOpts));

    [Xu, Yu, Zu] = worldToStrapLocal(X, Y, Z, anchor, outDir, params, frameOpts);
    [extentX, extentY, extentZ] = worldToStrapLocal(extent(:, 1), ...
        extent(:, 2), extent(:, 3), anchor, outDir, params, frameOpts);
    xMin = min(extentX) - opts.padMm;
    xMax = max(extentX) + opts.padMm;
    yMin = min(extentY) - opts.padMm;
    yMax = max(extentY) + opts.padMm;
    zMin = min(extentZ) - opts.padMm;
    zMax = max(extentZ) + opts.padMm;
    domain = Xu >= xMin & Xu <= xMax & ...
        Yu >= yMin & Yu <= yMax & ...
        Zu >= zMin & Zu <= zMax;
    stageOcc = stageOcc & domain;
    intended = intended & domain;

    match = stageOcc & intended;
    extra = stageOcc & ~intended;
    missing = intended & ~stageOcc;
    [img, xCenters, zCenters] = projectionRgb(Xu, Zu, intended, stageOcc, ...
        xMin, xMax, zMin, zMax, gridStepMm(occ));

    nIntended = nnz(intended);
    nExtra = nnz(extra);
    nMissing = nnz(missing);
    D = struct();
    D.strapIndex = strapIdx;
    D.stage = stage.name;
    D.stageField = stage.field;
    D.gridSize = size(stageOcc);
    D.nIntendedVoxels = nIntended;
    D.nStageVoxels = nnz(stageOcc);
    D.nMatchingVoxels = nnz(match);
    D.nExtraVoxels = nExtra;
    D.nMissingVoxels = nMissing;
    D.extraOverIntendedPct = 100 * nExtra / max(1, nIntended);
    D.missingOverIntendedPct = 100 * nMissing / max(1, nIntended);
    D.xCenters = xCenters;
    D.zCenters = zCenters;
    D.rgb = img;
end

function D = emptyDiagnostic(stage, strapIdx)
    D = struct();
    D.strapIndex = strapIdx;
    D.stage = stage.name;
    D.stageField = stage.field;
    D.gridSize = [0 0 0];
    D.nIntendedVoxels = 0;
    D.nStageVoxels = 0;
    D.nMatchingVoxels = 0;
    D.nExtraVoxels = 0;
    D.nMissingVoxels = 0;
    D.extraOverIntendedPct = NaN;
    D.missingOverIntendedPct = NaN;
    D.xCenters = [];
    D.zCenters = [];
    D.rgb = zeros(0, 0, 3);
end

function [rgb, xCenters, zCenters] = projectionRgb(Xu, Zu, intended, stageOcc, ...
        xMin, xMax, zMin, zMax, stepMm)
    xCenters = xMin:stepMm:xMax;
    zCenters = zMin:stepMm:zMax;
    nx = numel(xCenters);
    nz = numel(zCenters);
    intendedImg = false(nz, nx);
    stageImg = false(nz, nx);
    intendedImg = fillProjection(intendedImg, Xu, Zu, intended, ...
        xMin, zMin, stepMm, nx, nz);
    stageImg = fillProjection(stageImg, Xu, Zu, stageOcc, ...
        xMin, zMin, stepMm, nx, nz);

    rgb = ones(nz, nx, 3);
    intendedOnly = intendedImg & ~stageImg;
    matching = intendedImg & stageImg;
    extra = stageImg & ~intendedImg;
    rgb = paintMask(rgb, intendedOnly, [0.78 0.78 0.78]);
    rgb = paintMask(rgb, matching, [0.05 0.30 0.95]);
    rgb = paintMask(rgb, extra, [0.95 0.05 0.05]);
end

function img = fillProjection(img, Xu, Zu, mask, xMin, zMin, stepMm, nx, nz)
    rows = find(mask);
    if isempty(rows)
        return;
    end
    bx = round((Xu(rows) - xMin) ./ stepMm) + 1;
    bz = round((Zu(rows) - zMin) ./ stepMm) + 1;
    keep = bx >= 1 & bx <= nx & bz >= 1 & bz <= nz;
    idx = sub2ind([nz nx], bz(keep), bx(keep));
    img(idx) = true;
end

function rgb = paintMask(rgb, mask, color)
    for c = 1:3
        plane = rgb(:, :, c);
        plane(mask) = color(c);
        rgb(:, :, c) = plane;
    end
end

function fig = makeFigure(rows, stages, diagnostics, opts, figVisible)
    nRows = numel(rows);
    nCols = numel(stages);
    fig = figure('Name', 'Chin strap manufacturing diagnostics', ...
        'NumberTitle', 'off', ...
        'Color', 'w', ...
        'Visible', figVisible, ...
        'Position', [80 80 360 * nCols 260 * nRows]);
    tl = tiledlayout(fig, nRows, nCols, ...
        'TileSpacing', 'compact', 'Padding', 'compact');
    title(tl, 'Chin strap raster through manufacturing stages');

    k = 0;
    for r = 1:nRows
        for c = 1:nCols
            k = k + 1;
            D = diagnostics(k);
            ax = nexttile(tl);
            if isempty(D.rgb)
                text(ax, 0.5, 0.5, 'no overlap', ...
                    'Units', 'normalized', 'HorizontalAlignment', 'center');
                axis(ax, 'off');
            else
                image(ax, D.xCenters, D.zCenters, D.rgb);
                set(ax, 'YDir', 'normal');
                axis(ax, 'equal');
                axis(ax, 'tight');
                xlabel(ax, 'strap local X mm');
                ylabel(ax, 'strap local Z mm');
            end
            title(ax, sprintf('strap %d: %s\nextra %.1f%%, missing %.1f%%', ...
                D.strapIndex, D.stage, D.extraOverIntendedPct, ...
                D.missingOverIntendedPct), 'Interpreter', 'none');
        end
    end
    annotation(fig, 'textbox', [0.01 0.005 0.95 0.035], ...
        'String', 'gray = intended but absent, blue = intended present, red = extra voxel inside strap-local bounding box', ...
        'EdgeColor', 'none', 'Color', [0.25 0.25 0.25]);
end

function [Xu, Yu, Zu] = worldToStrapLocal(X, Y, Z, anchor, outDir, params, frameOpts)
    [O, xuHat, yuHat, zuHat] = strapLocalFrame(anchor, outDir, params, frameOpts);
    dX = X - O(1);
    dY = Y - O(2);
    dZ = Z - O(3);
    Xu = xuHat(1) .* dX + xuHat(2) .* dY + xuHat(3) .* dZ;
    Yu = yuHat(1) .* dX + yuHat(2) .* dY + yuHat(3) .* dZ;
    Zu = zuHat(1) .* dX + zuHat(2) .* dY + zuHat(3) .* dZ;
end

function [O, xuHat, yuHat, zuHat] = strapLocalFrame(anchor, outDir, params, frameOpts)
    tOut = outDir(:).';
    if numel(tOut) < 3
        tOut(3) = 0;
    end
    tOut(3) = 0;
    if norm(tOut) < 1e-12
        tOut = [1 0 0];
    end
    tOut = tOut ./ norm(tOut);
    xuHat = -tOut;
    zuHat = [0 0 1];
    yuHat = cross(zuHat, xuHat);
    if norm(yuHat) < 1e-12
        yuHat = [0 1 0];
    end
    yuHat = yuHat ./ norm(yuHat);

    zBed = getStructField(frameOpts, 'zBed', 0);
    ringOff = getStructField(frameOpts, 'ringOffMM', 50);
    startShift = getStructField(frameOpts, 'startShiftMM', 0);
    ringTubeDia = getStructField(params, 'ringTubeDiaMM', 3.5);
    ringOD = getStructField(params, 'ringOuterDiaMM', 20);
    ringOverlap = getStructField(params, 'ringOverlapMM', 5);
    xStart = getStructField(params, 'xStart', 0);

    r = ringTubeDia / 2;
    ringR = ringOD / 2;
    ringC = anchor + tOut .* ringOff;
    ringC(3) = zBed + r;
    P0 = ringC - tOut .* (ringR - ringOverlap);
    O = P0 - xuHat .* xStart;
    O(3) = 0;
    if startShift ~= 0
        O = O + xuHat .* (-startShift);
    end
end

function stepMm = gridStepMm(occ)
    if isfield(occ, 'vx') && ~isempty(occ.vx) && isfinite(occ.vx)
        stepMm = double(occ.vx);
        return;
    end
    x = double(occ.x(:));
    if numel(x) >= 2
        stepMm = abs(x(2) - x(1));
    else
        stepMm = 0.5;
    end
end

function fileName = defaultOutputFile(report, meshFile)
    outDir = '';
    if isfield(report, 'outputDir') && ~isempty(report.outputDir)
        outDir = char(report.outputDir);
    else
        outDir = fileparts(meshFile);
    end
    tag = 'chinStrapDiagnostics';
    if isfield(report, 'manufacturingTag') && ~isempty(report.manufacturingTag)
        tag = char(report.manufacturingTag);
    end
    fileName = fullfile(outDir, [tag '_chinStrapDiagnostics.png']);
end

function ensureDir(folder)
    if ~isempty(folder) && exist(folder, 'dir') ~= 7
        mkdir(folder);
    end
end

function value = getOptionalField(S, fieldName, defaultValue)
    if isstruct(S) && isfield(S, fieldName) && ~isempty(S.(fieldName))
        value = S.(fieldName);
    else
        value = defaultValue;
    end
end

function value = getStructField(S, fieldName, defaultValue)
    if isstruct(S) && isfield(S, fieldName) && ~isempty(S.(fieldName))
        value = S.(fieldName);
    else
        value = defaultValue;
    end
end

function addLocalDependencies()
    repoRoot = fileparts(fileparts(mfilename('fullpath')));
    addpath(fullfile(repoRoot, 'capMaker', 'geometry'));
end

function pathOut = expandUserPath(pathOut)
    if isempty(pathOut)
        return;
    end
    if startsWith(pathOut, '~')
        homeDir = getenv('HOME');
        if isempty(homeDir)
            homeDir = char(java.lang.System.getProperty('user.home'));
        end
        if numel(pathOut) == 1
            pathOut = homeDir;
        elseif pathOut(2) == filesep || pathOut(2) == '/'
            pathOut = fullfile(homeDir, pathOut(3:end));
        end
    end
end

function tf = isBoolLike(x)
    tf = (islogical(x) || isnumeric(x)) && isscalar(x);
end

function tf = isNonnegativeScalar(x)
    tf = isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0;
end
