function out = acsVisualizeSparseRoastLeadField(sparseResult, varargin)
% ACSVISUALIZESPARSEROASTLEADFIELD Visualize a sparse montage from its lead field.
%
% out = acsVisualizeSparseRoastLeadField(sparse) reconstructs the optimized
% electric field from an acsOptimizeSparseRoastLeadField result and displays
% a gray-matter surface plus three target-centered mesh cuts. It does not run
% meshing or GetDP.
%
% sparseResult can be an optimizer output struct or its saved MAT report.
%
% Name-value options:
%   targetIndex       : target to mark and use for the mesh cuts [1]
%   colorLimitVm      : upper electric-field color limit [brain percentile]
%   colorLimitPercentile : brain percentile for auto color limit [99.5]
%   showElectrodeLabels : show selected electrode name/current text [false]
%   cameraMode        : 'targetNormal' or 'default' ['targetNormal']
%   targetNormalRadiusMm : neighborhood used to estimate target normal [8]
%   cameraDistanceScale  : margin on target-centered gray-matter view radius [0.8]
%   cameraViewAngleDeg   : 3D view angle; larger is less zoomed [9]
%   targetMarkerSize3d : target marker size in the main 3D panel [260]
%   targetMarkerSizeSlice : target marker size in slice panels [180]
%   showFigures       : show the QC figure [true]
%   saveFigures       : save a PNG beside other QC products [false]
%   closeFigure       : close the figure before returning [false]

    opts = parseInputs(varargin{:});
    sparse = readSparseResult(sparseResult);
    requireFields(sparse, {'t1File', 'leadFieldTag', 'targetingTag', ...
        'targetVoxel', 'basisCoefficientsMa', 'electrodeNames', ...
        'selectedIndices', 'currentsMa'});
    targetIndex = validateTargetIndex(opts.targetIndex, size(sparse.targetVoxel, 1));
    [folder, stem] = fileparts(sparse.t1File);
    addDependencies();

    resultFile = fullfile(folder, ...
        [stem '_' sparse.leadFieldTag '_roastResult.mat']);
    meshFile = fullfile(folder, [stem '_' sparse.leadFieldTag '.mat']);
    requireFile(resultFile);
    requireFile(meshFile);
    resultData = load(resultFile, 'A_all');
    meshData = load(meshFile, 'node', 'elem', 'face');
    if ~isfield(resultData, 'A_all')
        error('acsVisualizeSparseRoastLeadField:MissingMatrix', ...
            'Lead-field result does not contain A_all: %s', resultFile);
    end
    if ~all(isfield(meshData, {'node', 'elem', 'face'}))
        error('acsVisualizeSparseRoastLeadField:MissingMesh', ...
            'Lead-field mesh MAT file must contain node, elem, and face arrays.');
    end
    coefficients = double(sparse.basisCoefficientsMa(:));
    if size(resultData.A_all, 3) ~= numel(coefficients)
        error('acsVisualizeSparseRoastLeadField:BadMatrixSize', ...
            'A_all contains %d basis fields, but the montage has %d coefficients.', ...
            size(resultData.A_all, 3), numel(coefficients));
    end

    V = spm_vol(sparse.t1File);
    voxelSize = [V.mat(1, 1), V.mat(2, 2), V.mat(3, 3)];
    if any(voxelSize <= 0) || ...
            any(any(abs(V.mat(1:3, 1:3) - diag(voxelSize)) > 1e-9))
        error('acsVisualizeSparseRoastLeadField:NonCanonicalT1', ...
            'Expected a canonical RAS T1 with a positive diagonal voxel transform.');
    end

    field = reconstructMeshField(resultData.A_all, coefficients);
    fieldMagnitude = sqrt(sum(field .^ 2, 2));
    targetMm = bsxfun(@times, double(sparse.targetVoxel), voxelSize);
    [selectedVoxel, selectedMm] = selectedElectrodeCoordinates(sparse, voxelSize);
    brainElem = meshData.elem(meshData.elem(:, 5) == 1 | ...
        meshData.elem(:, 5) == 2, 1:4);
    grayFaces = meshData.face(meshData.face(:, 4) == 2, 1:3);
    if isempty(brainElem) || isempty(grayFaces)
        error('acsVisualizeSparseRoastLeadField:MissingBrainMesh', ...
            'Lead-field mesh does not contain brain elements and gray-matter faces.');
    end
    meshExtentInfo = summarizeMeshExtents(meshData.node(:, 1:3), ...
        meshData.elem, brainElem, grayFaces);
    warnIfMeshExtentLooksSuspicious(meshExtentInfo);
    brainNodes = unique(brainElem(:));
    colorLimitVm = chooseColorLimit(fieldMagnitude(brainNodes), ...
        opts.colorLimitVm, opts.colorLimitPercentile);

    figVisible = 'off';
    if opts.showFigures
        figVisible = 'on';
    end
    [fig, cameraInfo] = makeFigure(meshData.node(:, 1:3), brainElem, grayFaces, ...
        fieldMagnitude, targetMm, targetIndex, sparse, selectedMm, colorLimitVm, ...
        opts, figVisible);

    out = struct();
    out.createdOn = char(datetime('now'));
    out.t1File = sparse.t1File;
    out.leadFieldTag = sparse.leadFieldTag;
    out.targetingTag = sparse.targetingTag;
    out.targetIndex = targetIndex;
    out.targetVoxel = sparse.targetVoxel(targetIndex, :);
    out.targetMm = targetMm(targetIndex, :);
    out.targetFieldVm = fieldAtClosestNode(meshData.node(:, 1:3), ...
        field, targetMm(targetIndex, :), brainNodes);
    out.targetMagnitudeVm = norm(out.targetFieldVm);
    out.colorLimitVm = colorLimitVm;
    out.meshExtentInfo = meshExtentInfo;
    out.selectedIndices = sparse.selectedIndices(:);
    out.selectedNames = sparse.electrodeNames(sparse.selectedIndices);
    out.selectedCurrentsMa = sparse.currentsMa(sparse.selectedIndices);
    out.selectedVoxelCoordinates = selectedVoxel;
    out.selectedCoordinatesMm = selectedMm;
    out.cameraInfo = cameraInfo;
    out.figure = fig;
    out.qcFigure = '';

    if opts.saveFigures
        qcDir = fullfile(folder, 'qc');
        ensureDir(qcDir);
        out.qcFigure = fullfile(qcDir, ...
            [stem '_' sparse.leadFieldTag '_' sparse.targetingTag '_fieldQC.png']);
        saveQcFigure(fig, out.qcFigure);
    end
    if opts.closeFigure && ishandle(fig)
        close(fig);
    end
end

function opts = parseInputs(varargin)
    p = inputParser;
    p.FunctionName = 'acsVisualizeSparseRoastLeadField';
    addParameter(p, 'targetIndex', 1, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 1 && x == round(x));
    addParameter(p, 'colorLimitVm', [], ...
        @(x) isempty(x) || (isnumeric(x) && isscalar(x) && isfinite(x) && x > 0));
    addParameter(p, 'colorLimitPercentile', 99.5, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x > 0 && x <= 100);
    addParameter(p, 'showElectrodeLabels', false, @isBoolLike);
    addParameter(p, 'cameraMode', 'targetNormal', @(x) ischar(x) || isstring(x));
    addParameter(p, 'targetNormalRadiusMm', 8, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x > 0);
    addParameter(p, 'cameraDistanceScale', 0.8, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x > 0);
    addParameter(p, 'cameraViewAngleDeg', 9, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x > 0 && x < 180);
    addParameter(p, 'targetMarkerSize3d', 260, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x > 0);
    addParameter(p, 'targetMarkerSizeSlice', 180, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x > 0);
    addParameter(p, 'showFigures', true, @isBoolLike);
    addParameter(p, 'saveFigures', false, @isBoolLike);
    addParameter(p, 'closeFigure', false, @isBoolLike);
    parse(p, varargin{:});
    opts = p.Results;
    opts.targetIndex = double(opts.targetIndex);
    opts.colorLimitVm = double(opts.colorLimitVm);
    opts.colorLimitPercentile = double(opts.colorLimitPercentile);
    opts.showElectrodeLabels = logical(opts.showElectrodeLabels);
    opts.cameraMode = normalizeCameraMode(opts.cameraMode);
    opts.targetNormalRadiusMm = double(opts.targetNormalRadiusMm);
    opts.cameraDistanceScale = double(opts.cameraDistanceScale);
    opts.cameraViewAngleDeg = double(opts.cameraViewAngleDeg);
    opts.targetMarkerSize3d = double(opts.targetMarkerSize3d);
    opts.targetMarkerSizeSlice = double(opts.targetMarkerSizeSlice);
    opts.showFigures = logical(opts.showFigures);
    opts.saveFigures = logical(opts.saveFigures);
    opts.closeFigure = logical(opts.closeFigure);
end

function tf = isBoolLike(x)
    tf = (islogical(x) || isnumeric(x)) && isscalar(x);
end

function mode = normalizeCameraMode(mode)
    mode = lower(strtrim(char(mode)));
    switch mode
        case {'targetnormal', 'target-normal', 'normal', 'auto'}
            mode = 'targetNormal';
        case {'default', 'view3', 'legacy'}
            mode = 'default';
        otherwise
            error('acsVisualizeSparseRoastLeadField:BadCameraMode', ...
                'cameraMode must be ''targetNormal'' or ''default''.');
    end
end

function sparse = readSparseResult(value)
    if isstruct(value)
        sparse = value;
        return;
    end
    if ~(ischar(value) || isstring(value))
        error('acsVisualizeSparseRoastLeadField:BadInput', ...
            'Pass an optimizer result struct or saved MAT report filename.');
    end
    fileName = char(value);
    requireFile(fileName);
    data = load(fileName, 'out');
    if ~isfield(data, 'out') || ~isstruct(data.out)
        error('acsVisualizeSparseRoastLeadField:BadReport', ...
            'Sparse targeting report does not contain an output struct: %s', fileName);
    end
    sparse = data.out;
end

function requireFields(s, fields)
    missing = fields(~isfield(s, fields));
    if ~isempty(missing)
        error('acsVisualizeSparseRoastLeadField:MissingFields', ...
            'Sparse targeting result is missing field: %s', missing{1});
    end
end

function index = validateTargetIndex(index, nTargets)
    if index > nTargets
        error('acsVisualizeSparseRoastLeadField:BadTargetIndex', ...
            'Requested targetIndex %d, but the montage has %d target(s).', ...
            index, nTargets);
    end
end

function addDependencies()
    repoRoot = fileparts(fileparts(mfilename('fullpath')));
    if exist('qmeshcut', 'file') ~= 2 || exist('spm_vol', 'file') ~= 2
        addKnownDependencyPaths(repoRoot);
    end
end

function addKnownDependencyPaths(repoRoot)
    if exist('setNHPulsePath', 'file') ~= 2
        addpath(repoRoot);
    end
    if exist('setNHPulsePath', 'file') == 2
        setNHPulsePath('repoRoot', repoRoot, 'verbose', false);
        return;
    end
    libRoot = fullfile(repoRoot, 'lib');
    knownFolders = {'spm12', 'spm', 'cvx', 'iso2mesh', 'NIFTI_20110921'};
    for k = 1:numel(knownFolders)
        folder = fullfile(libRoot, knownFolders{k});
        if exist(folder, 'dir') == 7
            addpath(folder, '-begin');
        end
    end
end

function requireFile(fileName)
    if exist(fileName, 'file') ~= 2
        error('acsVisualizeSparseRoastLeadField:MissingFile', ...
            'Required file not found: %s', fileName);
    end
end

function info = summarizeMeshExtents(node, elem, brainElem, grayFaces)
    node = double(node(:, 1:3));
    allRows = (1:size(node, 1))';
    elemNodeRows = unique(elem(:, 1:min(4, size(elem, 2))));
    elemNodeRows = elemNodeRows(elemNodeRows > 0 & elemNodeRows <= size(node, 1));
    unusedRows = setdiff(allRows, elemNodeRows);
    brainRows = unique(brainElem(:));
    brainRows = brainRows(brainRows > 0 & brainRows <= size(node, 1));
    grayRows = unique(grayFaces(:));
    grayRows = grayRows(grayRows > 0 & grayRows <= size(node, 1));

    info = struct();
    info.allNodes = pointSetExtent(node, allRows);
    info.elementNodes = pointSetExtent(node, elemNodeRows);
    info.unusedNodes = pointSetExtent(node, unusedRows);
    info.brainElementNodes = pointSetExtent(node, brainRows);
    info.graySurfaceNodes = pointSetExtent(node, grayRows);
    info.elementLabels = elementLabelExtents(node, elem);
    info.allVsGrayDiagonalRatio = safeRatio( ...
        info.allNodes.diagonalMm, info.graySurfaceNodes.diagonalMm);
    info.elementVsGrayDiagonalRatio = safeRatio( ...
        info.elementNodes.diagonalMm, info.graySurfaceNodes.diagonalMm);
    info.brainVsGrayDiagonalRatio = safeRatio( ...
        info.brainElementNodes.diagonalMm, info.graySurfaceNodes.diagonalMm);
    info.farthestAllNodesFromGrayCenter = farthestRowsFromPoint( ...
        node, allRows, info.graySurfaceNodes.centerMm, 8);
    info.farthestBrainNodesFromGrayCenter = farthestRowsFromPoint( ...
        node, brainRows, info.graySurfaceNodes.centerMm, 8);
end

function labelInfo = elementLabelExtents(node, elem)
    labelInfo = struct('label', {}, ...
        'nElements', {}, ...
        'nNodes', {}, ...
        'minMm', {}, ...
        'maxMm', {}, ...
        'spanMm', {}, ...
        'diagonalMm', {}, ...
        'centerMm', {});
    if size(elem, 2) < 5
        return;
    end
    labels = unique(elem(:, 5));
    labels = labels(isfinite(labels));
    for i = 1:numel(labels)
        label = labels(i);
        elemRows = elem(:, 5) == label;
        nodeRows = unique(elem(elemRows, 1:4));
        extent = pointSetExtent(node, nodeRows);
        labelInfo(i, 1).label = label; %#ok<AGROW>
        labelInfo(i, 1).nElements = nnz(elemRows);
        labelInfo(i, 1).nNodes = extent.n;
        labelInfo(i, 1).minMm = extent.minMm;
        labelInfo(i, 1).maxMm = extent.maxMm;
        labelInfo(i, 1).spanMm = extent.spanMm;
        labelInfo(i, 1).diagonalMm = extent.diagonalMm;
        labelInfo(i, 1).centerMm = extent.centerMm;
    end
end

function value = pointSetExtent(node, rows)
    rows = rows(:);
    rows = rows(rows > 0 & rows <= size(node, 1));
    coords = node(rows, :);
    finiteRows = all(isfinite(coords), 2);
    rows = rows(finiteRows);
    coords = coords(finiteRows, :);

    value = struct('n', numel(rows), ...
        'minMm', [NaN NaN NaN], ...
        'maxMm', [NaN NaN NaN], ...
        'spanMm', [NaN NaN NaN], ...
        'diagonalMm', NaN, ...
        'centerMm', [NaN NaN NaN]);
    if isempty(coords)
        return;
    end

    value.minMm = min(coords, [], 1);
    value.maxMm = max(coords, [], 1);
    value.spanMm = value.maxMm - value.minMm;
    value.diagonalMm = norm(value.spanMm);
    value.centerMm = 0.5 * (value.minMm + value.maxMm);
end

function ratio = safeRatio(numerator, denominator)
    if ~isfinite(numerator) || ~isfinite(denominator) || denominator <= 0
        ratio = NaN;
    else
        ratio = numerator / denominator;
    end
end

function farthest = farthestRowsFromPoint(node, rows, pointMm, nRows)
    farthest = struct('rows', [], ...
        'coordinatesMm', zeros(0, 3), ...
        'distanceMm', []);
    if isempty(rows) || any(~isfinite(pointMm))
        return;
    end
    coords = node(rows, :);
    keep = all(isfinite(coords), 2);
    rows = rows(keep);
    coords = coords(keep, :);
    if isempty(rows)
        return;
    end
    distanceMm = sqrt(sum(bsxfun(@minus, coords, pointMm) .^ 2, 2));
    [distanceMm, order] = sort(distanceMm, 'descend');
    order = order(1:min(numel(order), nRows));
    farthest.rows = rows(order);
    farthest.coordinatesMm = coords(order, :);
    farthest.distanceMm = distanceMm(1:numel(order));
end

function warnIfMeshExtentLooksSuspicious(info)
    allSuspicious = isfinite(info.allVsGrayDiagonalRatio) && ...
        info.allVsGrayDiagonalRatio > 5;
    elementSuspicious = isfinite(info.elementVsGrayDiagonalRatio) && ...
        info.elementVsGrayDiagonalRatio > 5;
    brainSuspicious = isfinite(info.brainVsGrayDiagonalRatio) && ...
        info.brainVsGrayDiagonalRatio > 3;
    if ~allSuspicious && ~elementSuspicious && ~brainSuspicious
        return;
    end
    warning('acsVisualizeSparseRoastLeadField:SuspiciousMeshExtent', ...
        ['ROAST mesh extents look suspicious: all nodes %.1f mm, ', ...
         'element-used nodes %.1f mm, brain-element nodes %.1f mm, ', ...
         'gray surface %.1f mm. Inspect out.meshExtentInfo for candidate ', ...
         'outlier rows and element-label extents.'], ...
        info.allNodes.diagonalMm, info.elementNodes.diagonalMm, ...
        info.brainElementNodes.diagonalMm, ...
        info.graySurfaceNodes.diagonalMm);
end

function field = reconstructMeshField(A, coefficients)
    field = sum(bsxfun(@times, A, reshape(coefficients, 1, 1, [])), 3);
end

function [selectedVoxel, selectedMm] = selectedElectrodeCoordinates(sparse, voxelSize)
    selectedVoxel = [];
    selectedMm = [];
    if ~isfield(sparse, 'selectedVoxelCoordinates') || ...
            isempty(sparse.selectedVoxelCoordinates)
        return;
    end
    selectedVoxel = double(sparse.selectedVoxelCoordinates);
    selectedMm = bsxfun(@times, selectedVoxel, voxelSize);
end

function limit = chooseColorLimit(values, explicitLimit, percentile)
    if ~isempty(explicitLimit)
        limit = explicitLimit;
        return;
    end
    values = sort(values(isfinite(values)));
    if isempty(values)
        error('acsVisualizeSparseRoastLeadField:NoFiniteField', ...
            'No finite brain electric-field values were available to display.');
    end
    index = max(1, min(numel(values), ...
        round((double(percentile) / 100) * numel(values))));
    limit = values(index);
    if limit <= 0
        limit = max(values);
    end
    if limit <= 0
        limit = 1;
    end
end

function fieldValue = fieldAtClosestNode(node, field, targetMm, brainNodes)
    delta = bsxfun(@minus, double(node(brainNodes, 1:3)), targetMm);
    [~, localIndex] = min(sum(delta .^ 2, 2));
    fieldValue = field(brainNodes(localIndex), :);
end

function [fig, cameraInfo] = makeFigure(node, brainElem, grayFaces, fieldMagnitude, ...
        targetMm, targetIndex, sparse, selectedMm, colorLimitVm, opts, visible)
    fig = figure('Name', ['Sparse ROAST field: ' sparse.targetingTag], ...
        'NumberTitle', 'off', 'Color', 'w', 'Visible', visible);
    setPosterFieldFigureSize(fig);
    cameraInfo = struct('mode', opts.cameraMode, ...
        'targetMm', targetMm(targetIndex, :), ...
        'normalMm', [], ...
        'surfaceAnchorMm', [], ...
        'cameraPositionMm', [], ...
        'cameraUpVector', [], ...
        'cameraDistanceMm', [], ...
        'viewRadiusMm', []);

    layout = sparseFieldAxesLayout();
    markerEdgeColor = [0.88 0.88 0.88];
    targetFillColor = [1.00 0.00 0.78];
    targetEdgeColor = [0.42 0.00 0.32];

    ax = axes('Parent', fig, 'Units', 'normalized', ...
        'Position', layout.mainAxes);
    patch(ax, 'Faces', grayFaces, 'Vertices', node, ...
        'FaceVertexCData', fieldMagnitude, ...
        'FaceColor', 'interp', 'EdgeColor', 'none', ...
        'FaceLighting', 'none');
    hold(ax, 'on');
    scatter3(ax, targetMm(:, 1), targetMm(:, 2), targetMm(:, 3), ...
        opts.targetMarkerSize3d, targetFillColor, 'p', 'filled', ...
        'MarkerEdgeColor', targetEdgeColor, 'LineWidth', 2.1);
    addElectrodeMarkers(ax, selectedMm, sparse, opts.showElectrodeLabels, ...
        markerEdgeColor);
    axis(ax, 'equal');
    axis(ax, 'tight');
    axis(ax, 'off');
    cameraInfo = applyTargetCamera(ax, node, brainElem, grayFaces, ...
        targetMm(targetIndex, :), opts, cameraInfo);
    rotate3d(fig, 'on');
    title(ax, 'Gray matter field magnitude');
    colormap(ax, jet(256));
    caxis(ax, [0 colorLimitVm]);
    cb = colorbar(ax, 'Location', 'eastoutside');
    set(ax, 'Units', 'normalized', 'Position', layout.mainAxes);
    set(cb, 'Units', 'normalized', 'Position', layout.colorbar);
    ylabel(cb, 'Electric field (V/m)');
    saveInteractiveView(ax);

    % qmeshcut's expression form avoids a bundled iso2mesh bug in its
    % four-coefficient plane-vector parser.
    cuts = { ...
        sprintf('x=%.17g', targetMm(targetIndex, 1)), 'Sagittal cut', [1 0 0]; ...
        sprintf('y=%.17g', targetMm(targetIndex, 2)), 'Coronal cut', [0 -1 0]; ...
        sprintf('z=%.17g', targetMm(targetIndex, 3)), 'Axial cut', [0 0 1]};
    for i = 1:3
        ax = axes('Parent', fig, 'Units', 'normalized', ...
            'Position', layout.sliceAxes(i, :));
        try
            [cutpos, cutvalue, facedata] = qmeshcut( ...
                brainElem, node, fieldMagnitude, cuts{i, 1});
        catch ME
            warning('acsVisualizeSparseRoastLeadField:MeshCutFallback', ...
                ['Could not slice mesh with qmeshcut (%s). Showing ', ...
                 'nearest-node scatter cut instead.'], ME.message);
            [cutpos, cutvalue, facedata] = nearestNodeCut( ...
                node, fieldMagnitude, targetMm(targetIndex, :), i);
        end
        if isempty(facedata)
            plotScatterCut(ax, cutpos, cutvalue, targetMm(targetIndex, :), ...
                targetFillColor, targetEdgeColor, opts.targetMarkerSizeSlice);
        else
            patch(ax, 'Vertices', cutpos, 'Faces', facedata, ...
                'FaceVertexCData', cutvalue, ...
                'FaceColor', 'interp', 'EdgeColor', 'none', ...
                'FaceLighting', 'none');
        end
        hold(ax, 'on');
        scatter3(ax, targetMm(targetIndex, 1), targetMm(targetIndex, 2), ...
            targetMm(targetIndex, 3), opts.targetMarkerSizeSlice, targetFillColor, ...
            'p', 'filled', 'MarkerEdgeColor', targetEdgeColor, 'LineWidth', 1.85);
        axis(ax, 'equal');
        axis(ax, 'tight');
        axis(ax, 'off');
        view(ax, cuts{i, 3});
        title(ax, cuts{i, 2});
        colormap(ax, jet(256));
        caxis(ax, [0 colorLimitVm]);
    end
end

function setPosterFieldFigureSize(fig)
    try
        if strcmp(get(fig, 'WindowStyle'), 'docked')
            return;
        end
        oldUnits = get(fig, 'Units');
        set(fig, 'Units', 'pixels');
        pos = get(fig, 'Position');
        pos(3) = max(pos(3), 1180);
        pos(4) = max(pos(4), 820);
        set(fig, 'Position', pos);
        set(fig, 'Units', oldUnits);
    catch
    end
end

function layout = sparseFieldAxesLayout()
    layout = struct();
    layout.mainAxes = [0.035 0.335 0.845 0.595];
    layout.colorbar = [0.875 0.405 0.016 0.43];
    layout.sliceAxes = [ ...
        0.055 0.055 0.255 0.235; ...
        0.375 0.055 0.255 0.235; ...
        0.695 0.055 0.255 0.235];
end

function saveInteractiveView(ax)
    drawnow;
    try
        resetplotview(ax, 'SaveCurrentView');
    catch
    end
end

function [cutpos, cutvalue, facedata] = nearestNodeCut(node, fieldMagnitude, targetMm, cutIndex)
    cutDim = cutIndex;
    distances = abs(double(node(:, cutDim)) - targetMm(cutDim));
    if isempty(distances)
        cutpos = zeros(0, 3);
        cutvalue = [];
        facedata = [];
        return;
    end
    bandWidth = max(1, prctileFallback(distances, 3));
    keep = distances <= bandWidth;
    if nnz(keep) < 20
        [~, order] = sort(distances, 'ascend');
        keep = false(size(distances));
        keep(order(1:min(numel(order), 500))) = true;
    end
    cutpos = node(keep, :);
    cutvalue = fieldMagnitude(keep);
    facedata = [];
end

function cameraInfo = applyTargetCamera(ax, node, brainElem, grayFaces, targetMm, opts, cameraInfo)
    if strcmp(opts.cameraMode, 'default')
        view(ax, 3);
        return;
    end

    [normal, anchor] = estimateTargetSurfaceNormal( ...
        node, brainElem, grayFaces, targetMm, opts.targetNormalRadiusMm);
    if isempty(normal)
        warning('acsVisualizeSparseRoastLeadField:CameraNormalFallback', ...
            'Could not estimate a local target normal for the 3D view. Using view(3).');
        view(ax, 3);
        return;
    end

    viewRadius = targetCenteredViewRadius(node, grayFaces, targetMm, normal);
    halfAngle = opts.cameraViewAngleDeg * pi / 360;
    cameraDistance = opts.cameraDistanceScale * viewRadius / max(tan(halfAngle), 1e-3);
    if ~isfinite(cameraDistance) || cameraDistance <= 0
        cameraDistance = 150;
    end

    upVector = cameraUpVector(normal);
    cameraPosition = targetMm + cameraDistance * normal;
    camtarget(ax, targetMm);
    campos(ax, cameraPosition);
    camup(ax, upVector);
    camproj(ax, 'perspective');
    camva(ax, opts.cameraViewAngleDeg);

    cameraInfo.normalMm = normal;
    cameraInfo.surfaceAnchorMm = anchor;
    cameraInfo.cameraPositionMm = cameraPosition;
    cameraInfo.cameraUpVector = upVector;
    cameraInfo.cameraDistanceMm = cameraDistance;
    cameraInfo.viewRadiusMm = viewRadius;
end

function viewRadius = targetCenteredViewRadius(node, grayFaces, targetMm, viewNormal)
    grayVertexIds = unique(grayFaces(:));
    grayVertexIds = grayVertexIds(grayVertexIds > 0 & grayVertexIds <= size(node, 1));
    if isempty(grayVertexIds)
        coords = double(node(:, 1:3));
    else
        coords = double(node(grayVertexIds, 1:3));
    end
    coords = coords(all(isfinite(coords), 2), :);
    if isempty(coords)
        viewRadius = 80;
        return;
    end

    delta = bsxfun(@minus, coords, targetMm);
    if nargin >= 4 && ~isempty(viewNormal) && all(isfinite(viewNormal)) && ...
            norm(viewNormal) > 0
        viewNormal = viewNormal(:)' ./ norm(viewNormal);
        delta = delta - bsxfun(@times, delta * viewNormal', viewNormal);
    end
    distances = sqrt(sum(delta .^ 2, 2));
    distances = distances(isfinite(distances) & distances > 0);
    if isempty(distances)
        bounds = max(coords, [], 1) - min(coords, [], 1);
        viewRadius = max(1, 0.5 * norm(bounds));
        return;
    end

    % Base the poster camera on the displayed gray-matter surface. The full
    % ROAST node table can include distant non-gray nodes, which makes the
    % target-centered camera land absurdly far away.
    viewRadius = max(1, prctileFallback(distances, 99.8));
end

function [normal, anchor] = estimateTargetSurfaceNormal(node, brainElem, grayFaces, targetMm, radiusMm)
    normal = [];
    anchor = [];
    if isempty(grayFaces)
        return;
    end

    grayVertexIds = unique(grayFaces(:));
    grayVertexIds = grayVertexIds(grayVertexIds > 0 & grayVertexIds <= size(node, 1));
    if numel(grayVertexIds) < 3
        return;
    end
    grayVertices = double(node(grayVertexIds, 1:3));
    deltaTarget = bsxfun(@minus, grayVertices, targetMm);
    [~, nearestLocal] = min(sum(deltaTarget .^ 2, 2));
    anchor = grayVertices(nearestLocal, :);

    deltaAnchor = bsxfun(@minus, grayVertices, anchor);
    distance2 = sum(deltaAnchor .^ 2, 2);
    local = grayVertices(distance2 <= radiusMm ^ 2, :);
    if size(local, 1) < 20
        [~, order] = sort(distance2, 'ascend');
        local = grayVertices(order(1:min(numel(order), 80)), :);
    end
    if size(local, 1) < 3
        return;
    end

    localMean = mean(local, 1);
    centered = bsxfun(@minus, local, localMean);
    if all(abs(centered(:)) < eps)
        return;
    end
    [~, ~, coeff] = svd(centered, 0);
    normal = coeff(:, end)';
    normal = normal ./ norm(normal);

    brainNodes = unique(brainElem(:));
    brainNodes = brainNodes(brainNodes > 0 & brainNodes <= size(node, 1));
    if isempty(brainNodes)
        brainCenter = mean(double(node(:, 1:3)), 1);
    else
        brainCenter = mean(double(node(brainNodes, 1:3)), 1);
    end
    outwardReference = anchor - brainCenter;
    if dot(normal, outwardReference) < 0
        normal = -normal;
    end
end

function upVector = cameraUpVector(normal)
    normal = normal ./ norm(normal);
    upReference = [0 0 1];
    if abs(dot(normal, upReference)) > 0.85
        upReference = [0 1 0];
    end
    upVector = upReference - dot(upReference, normal) * normal;
    if norm(upVector) < 1e-9
        upVector = [0 1 0];
    end
    upVector = upVector ./ norm(upVector);
end

function plotScatterCut(ax, cutpos, cutvalue, targetMm, targetFillColor, ...
        targetEdgeColor, targetMarkerSize)
    if isempty(cutpos)
        text(ax, 0.5, 0.5, 'No brain mesh at target plane', ...
            'Units', 'normalized', 'HorizontalAlignment', 'center');
        return;
    end
    scatter3(ax, cutpos(:, 1), cutpos(:, 2), cutpos(:, 3), ...
        12, cutvalue, 'filled');
    hold(ax, 'on');
    scatter3(ax, targetMm(1), targetMm(2), targetMm(3), ...
        targetMarkerSize, targetFillColor, 'p', 'filled', ...
        'MarkerEdgeColor', targetEdgeColor, 'LineWidth', 1.85);
end

function value = prctileFallback(values, pct)
    values = sort(values(isfinite(values)));
    if isempty(values)
        value = 1;
        return;
    end
    idx = max(1, min(numel(values), round((pct / 100) * numel(values))));
    value = values(idx);
end

function addElectrodeMarkers(ax, selectedMm, sparse, showLabels, markerEdgeColor)
    if isempty(selectedMm)
        return;
    end
    selected = sparse.selectedIndices(:);
    currents = sparse.currentsMa(selected);
    names = {};
    if showLabels
        names = sparse.electrodeNames(selected);
    end
    for i = 1:numel(selected)
        if currents(i) >= 0
            color = [0.85 0.20 0.15];
        else
            color = [0.15 0.35 0.85];
        end
        scatter3(ax, selectedMm(i, 1), selectedMm(i, 2), selectedMm(i, 3), ...
            94, color, 'o', 'filled', ...
            'MarkerEdgeColor', markerEdgeColor, 'LineWidth', 1.55);
        if showLabels
            text(ax, selectedMm(i, 1), selectedMm(i, 2), selectedMm(i, 3), ...
                sprintf('  %s (%+.3g mA)', names{i}, currents(i)), ...
                'Interpreter', 'none', 'FontSize', 8, 'Color', color);
        end
    end
end

function saveQcFigure(fig, fileName)
    try
        exportgraphics(fig, fileName, 'Resolution', 160);
    catch
        saveas(fig, fileName);
    end
end

function ensureDir(folder)
    if exist(folder, 'dir') ~= 7
        mkdir(folder);
    end
end
