function out = acsCropPhoneScanToHead(plyFile, varargin)
% ACSCROPPHONESCANTOHEAD Inspect a phone/LiDAR PLY scan and crop to the head.
%
% out = acsCropPhoneScanToHead(plyFile) reads an ASCII PLY mesh, opens an
% interactive crop-box viewer, and writes a reusable cropped head-scan
% product. The cropped mesh can be treated as either a triangulation or a
% point cloud for later scalp-shape fitting.
%
% Name-value options:
%   outputFile              : MAT report/product file ['']
%   outputPlyFile           : cropped PLY file ['']
%   outputTag               : output stem ['']
%   force                   : overwrite existing output [false]
%   interactive             : open crop GUI [true]
%   cropBounds              : 3 x 2 [min max] bounds in scan units [[]]
%   cropRotationDeg         : initial [pitch yaw roll] crop rotation [0 0 0]
%   rotationStepDeg         : pitch/yaw/roll keyboard step [1]
%   keepLargestComponent    : keep largest connected cropped component [true]
%   minComponentFaces       : discard small components in QC/report [20]
%   displayMaxFaces         : decimate viewer mesh to this many faces [35000]
%   faceAlpha               : scan mesh opacity [1]
%   showOutsideCrop         : render geometry outside crop during GUI [false]
%   showFigures             : show final QC figure [true]
%   saveFigures             : save final QC PNG [true]
%   writeCroppedPly         : write cropped PLY mesh [true]
%   verbose                 : print summary [true]

    if nargin < 1 || isempty(plyFile)
        error('acsCropPhoneScanToHead:MissingInput', ...
            'Provide a PLY file exported from the phone scan.');
    end

    opts = parseInputs(varargin{:});
    plyFile = expandUserPath(char(plyFile));
    if exist(plyFile, 'file') ~= 2
        error('acsCropPhoneScanToHead:FileNotFound', ...
            'PLY file not found: %s', plyFile);
    end

    scan = readAsciiPlyMesh(plyFile);
    opts = resolveOutputFiles(plyFile, opts);
    requireWritableOutputs(opts);

    if isempty(opts.cropBounds)
        cropBox = initialCropBox(scan.vertices, [], opts.cropRotationDeg);
    else
        cropBox = initialCropBox(scan.vertices, opts.cropBounds, ...
            opts.cropRotationDeg);
    end

    accepted = true;
    guiInfo = struct();
    if opts.interactive
        [cropBox, accepted, guiInfo, opts.keepLargestComponent] = ...
            cropScanGui(scan, cropBox, opts);
    end
    if ~accepted
        out = struct('accepted', false, 'sourceFile', plyFile, ...
            'cropBox', cropBox, 'cropBounds', cropBoxAxisAlignedBounds(cropBox), ...
            'guiInfo', guiInfo);
        if opts.verbose
            fprintf('Phone scan crop canceled.\n');
        end
        return;
    end

    crop = cropScanMesh(scan, cropBox, opts);
    if isempty(crop.faces)
        error('acsCropPhoneScanToHead:EmptyCrop', ...
            'The requested crop contains no mesh faces.');
    end

    TRhead = triangulation(crop.faces, crop.vertices);
    componentInfo = meshComponentInfo(crop.faces, size(crop.vertices, 1), ...
        opts.minComponentFaces);

    qcFile = '';
    fig = [];
    if opts.showFigures || opts.saveFigures
        figVisible = 'off';
        if opts.showFigures
            figVisible = 'on';
        end
        fig = makeQcFigure(scan, crop, componentInfo, opts, figVisible);
        if opts.saveFigures
            qcFile = fullfile(fileparts(opts.outputFile), 'qc', ...
                [stripExtension(getFileName(opts.outputFile)) '_qc.png']);
            ensureDir(fileparts(qcFile));
            exportFigure(fig, qcFile);
        end
        if ~opts.showFigures
            close(fig);
            fig = [];
        end
    end

    croppedPlyFile = '';
    if opts.writeCroppedPly
        croppedPlyFile = opts.outputPlyFile;
        writeAsciiPlyMesh(croppedPlyFile, crop);
    end

    out = struct();
    out.createdOn = char(datetime('now'));
    out.accepted = true;
    out.type = 'phoneScanHeadCrop';
    out.sourceFile = plyFile;
    out.outputFile = opts.outputFile;
    out.croppedPlyFile = croppedPlyFile;
    out.qcFigure = qcFile;
    out.coordinateFrame = 'phoneScanRawMm';
    out.unitsAssumption = 'EM3D/PLY scan units; verify scale with known 25.25 mm cylinder';
    out.cropBox = cropBox;
    out.cropBounds = cropBoxAxisAlignedBounds(cropBox);
    out.keepLargestComponent = opts.keepLargestComponent;
    out.TRhead = TRhead;
    out.vertices = crop.vertices;
    out.faces = crop.faces;
    out.normals = crop.normals;
    out.rgb = crop.rgb;
    out.pointCloudMm = crop.vertices;
    out.sourceStats = scanStats(scan.vertices, scan.faces);
    out.cropStats = scanStats(crop.vertices, crop.faces);
    out.componentInfo = componentInfo;
    out.guiInfo = guiInfo;
    out.options = opts;
    if isgraphics(fig)
        out.figure = fig;
    end

    outForSave = out;
    if isfield(outForSave, 'figure')
        outForSave = rmfield(outForSave, 'figure');
    end
    ensureDir(fileparts(opts.outputFile));
    save(opts.outputFile, 'outForSave', 'TRhead', '-v7.3');

    if opts.verbose
        printSummary(out);
    end
end

function opts = parseInputs(varargin)
    p = inputParser;
    p.FunctionName = 'acsCropPhoneScanToHead';
    addParameter(p, 'outputFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'outputPlyFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'outputTag', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'force', false, @isBoolLike);
    addParameter(p, 'interactive', true, @isBoolLike);
    addParameter(p, 'cropBounds', [], @(x) isempty(x) || isnumeric(x));
    addParameter(p, 'cropRotationDeg', [0 0 0], @isRotationVector);
    addParameter(p, 'rotationStepDeg', 1, @isPositiveScalar);
    addParameter(p, 'keepLargestComponent', true, @isBoolLike);
    addParameter(p, 'minComponentFaces', 20, @isNonnegativeScalar);
    addParameter(p, 'displayMaxFaces', 35000, @isPositiveScalar);
    addParameter(p, 'faceAlpha', 1, @isUnitScalar);
    addParameter(p, 'showOutsideCrop', false, @isBoolLike);
    addParameter(p, 'showFigures', true, @isBoolLike);
    addParameter(p, 'saveFigures', true, @isBoolLike);
    addParameter(p, 'writeCroppedPly', true, @isBoolLike);
    addParameter(p, 'verbose', true, @isBoolLike);
    parse(p, varargin{:});

    opts = p.Results;
    opts.outputFile = expandUserPath(char(opts.outputFile));
    opts.outputPlyFile = expandUserPath(char(opts.outputPlyFile));
    opts.outputTag = safeName(char(opts.outputTag));
    opts.force = logical(opts.force);
    opts.interactive = logical(opts.interactive);
    if ~isempty(opts.cropBounds)
        opts.cropBounds = validateCropBounds(opts.cropBounds);
    end
    opts.cropRotationDeg = double(opts.cropRotationDeg(:))';
    opts.rotationStepDeg = double(opts.rotationStepDeg);
    opts.keepLargestComponent = logical(opts.keepLargestComponent);
    opts.minComponentFaces = round(double(opts.minComponentFaces));
    opts.displayMaxFaces = round(double(opts.displayMaxFaces));
    opts.faceAlpha = double(opts.faceAlpha);
    opts.showOutsideCrop = logical(opts.showOutsideCrop);
    opts.showFigures = logical(opts.showFigures);
    opts.saveFigures = logical(opts.saveFigures);
    opts.writeCroppedPly = logical(opts.writeCroppedPly);
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

function tf = isUnitScalar(x)
    tf = isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0 && x <= 1;
end

function tf = isRotationVector(x)
    tf = isnumeric(x) && numel(x) == 3 && all(isfinite(double(x(:))));
end

function opts = resolveOutputFiles(plyFile, opts)
    [folder, stem] = fileparts(plyFile);
    if isempty(opts.outputTag)
        opts.outputTag = safeName([stem '_headCrop']);
    end
    if isempty(opts.outputFile)
        opts.outputFile = fullfile(folder, [opts.outputTag '.mat']);
    end
    if isempty(opts.outputPlyFile)
        opts.outputPlyFile = fullfile(folder, [opts.outputTag '.ply']);
    end
end

function requireWritableOutputs(opts)
    files = {opts.outputFile};
    if opts.writeCroppedPly
        files{end + 1} = opts.outputPlyFile;
    end
    if opts.saveFigures
        qcFile = fullfile(fileparts(opts.outputFile), 'qc', ...
            [stripExtension(getFileName(opts.outputFile)) '_qc.png']);
        files{end + 1} = qcFile;
    end
    for i = 1:numel(files)
        if exist(files{i}, 'file') == 2 && ~opts.force
            error('acsCropPhoneScanToHead:OutputExists', ...
                ['Output already exists: %s\nUse force=true to overwrite, ', ...
                 'or choose a new outputTag/outputFile.'], files{i});
        end
    end
end

function scan = readAsciiPlyMesh(fileName)
    fid = fopen(fileName, 'r');
    if fid == -1
        error('acsCropPhoneScanToHead:CannotOpenPly', ...
            'Could not open PLY file: %s', fileName);
    end
    cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>

    header = {};
    line = fgetl(fid);
    if ~ischar(line) || ~strcmp(strtrim(line), 'ply')
        error('acsCropPhoneScanToHead:BadPly', ...
            'File does not begin with a PLY header: %s', fileName);
    end
    header{end + 1, 1} = line; %#ok<AGROW>
    formatLine = '';
    nVertex = 0;
    nFace = 0;
    vertexProps = {};
    currentElement = '';
    while true
        line = fgetl(fid);
        if ~ischar(line)
            error('acsCropPhoneScanToHead:MissingPlyHeaderEnd', ...
                'PLY file ended before end_header.');
        end
        header{end + 1, 1} = line; %#ok<AGROW>
        clean = strtrim(line);
        tokens = strsplit(clean);
        if isempty(tokens)
            continue;
        end
        switch lower(tokens{1})
            case 'format'
                formatLine = clean;
            case 'element'
                currentElement = lower(tokens{2});
                if strcmp(currentElement, 'vertex')
                    nVertex = str2double(tokens{3});
                elseif strcmp(currentElement, 'face')
                    nFace = str2double(tokens{3});
                end
            case 'property'
                if strcmp(currentElement, 'vertex') && numel(tokens) >= 3
                    vertexProps{end + 1, 1} = tokens{end}; %#ok<AGROW>
                end
            case 'end_header'
                break;
        end
    end
    if isempty(formatLine) || ~contains(lower(formatLine), 'ascii')
        error('acsCropPhoneScanToHead:UnsupportedPlyFormat', ...
            'This first-pass utility currently reads ASCII PLY files only.');
    end
    if nVertex <= 0
        error('acsCropPhoneScanToHead:NoVertices', ...
            'PLY file does not report any vertices.');
    end

    propCount = numel(vertexProps);
    Vraw = zeros(nVertex, propCount);
    for i = 1:nVertex
        line = fgetl(fid);
        vals = sscanf(line, '%f');
        if numel(vals) < propCount
            error('acsCropPhoneScanToHead:BadVertexLine', ...
                'Vertex row %d has fewer fields than the header reports.', i);
        end
        Vraw(i, :) = vals(1:propCount)';
    end

    faces = zeros(nFace, 3);
    faceRows = false(nFace, 1);
    for i = 1:nFace
        line = fgetl(fid);
        vals = sscanf(line, '%d');
        if isempty(vals)
            continue;
        end
        n = vals(1);
        if n == 3 && numel(vals) >= 4
            faces(i, :) = vals(2:4)' + 1;
            faceRows(i) = true;
        elseif n > 3 && numel(vals) >= n + 1
            idx = vals(2:n + 1)' + 1;
            tri = fanTriangulate(idx);
            faces(i, :) = tri(1, :);
            faceRows(i) = true;
            if size(tri, 1) > 1
                faces = [faces; tri(2:end, :)]; %#ok<AGROW>
                faceRows = [faceRows; true(size(tri, 1) - 1, 1)]; %#ok<AGROW>
            end
        end
    end
    faces = faces(faceRows, :);
    validFace = all(isfinite(faces), 2) & all(faces >= 1, 2) & ...
        all(faces <= nVertex, 2);
    faces = faces(validFace, :);

    vertices = propertyColumns(Vraw, vertexProps, {'x', 'y', 'z'}, true);
    normals = propertyColumns(Vraw, vertexProps, {'nx', 'ny', 'nz'}, false);
    rgb = propertyColumns(Vraw, vertexProps, {'red', 'green', 'blue'}, false);
    if ~isempty(rgb)
        rgb = max(0, min(255, rgb)) ./ 255;
    end

    scan = struct();
    scan.sourceFile = fileName;
    scan.header = header;
    scan.vertexProperties = vertexProps;
    scan.vertices = double(vertices);
    scan.faces = double(faces);
    scan.normals = double(normals);
    scan.rgb = double(rgb);
end

function tri = fanTriangulate(idx)
    idx = idx(:)';
    tri = zeros(numel(idx) - 2, 3);
    for k = 2:numel(idx) - 1
        tri(k - 1, :) = [idx(1) idx(k) idx(k + 1)];
    end
end

function values = propertyColumns(Vraw, props, names, required)
    values = [];
    rows = zeros(1, numel(names));
    for i = 1:numel(names)
        row = find(strcmpi(props, names{i}), 1);
        if isempty(row)
            if required
                error('acsCropPhoneScanToHead:MissingPlyProperty', ...
                    'PLY vertex property "%s" was not found.', names{i});
            end
            return;
        end
        rows(i) = row;
    end
    values = Vraw(:, rows);
end

function bounds = initialCropBounds(V)
    lo = min(V, [], 1);
    hi = max(V, [], 1);
    bounds = [lo(:), hi(:)];
end

function cropBox = initialCropBox(V, bounds, rotationDeg)
    if isempty(bounds)
        bounds = initialCropBounds(V);
    else
        bounds = validateCropBounds(bounds);
    end
    center = mean(bounds, 2)';
    halfSize = 0.5 * (bounds(:, 2) - bounds(:, 1))';
    halfSize(halfSize <= 0) = eps;
    cropBox = struct();
    cropBox.center = center;
    cropBox.localBounds = [-halfSize(:), halfSize(:)];
    cropBox.rotationDeg = double(rotationDeg(:))';
    cropBox.R_localToWorld = eulerCropRotation(cropBox.rotationDeg);
    cropBox.coordinateFrame = 'phoneScanRawMm';
    cropBox.rotationConvention = ...
        'row points: local = (world - center) * R_localToWorld';
end

function bounds = validateCropBounds(bounds)
    bounds = double(bounds);
    if isequal(size(bounds), [2 3])
        bounds = bounds';
    end
    if ~isequal(size(bounds), [3 2]) || any(~isfinite(bounds(:))) || ...
            any(bounds(:, 2) <= bounds(:, 1))
        error('acsCropPhoneScanToHead:BadCropBounds', ...
            'cropBounds must be 3 x 2 [min max] with max greater than min.');
    end
end

function bounds = cropBoxAxisAlignedBounds(cropBox)
    corners = cropBoxCornersWorld(cropBox);
    bounds = [min(corners, [], 1)' max(corners, [], 1)'];
end

function local = worldToCropLocal(pointsWorld, cropBox)
    local = (double(pointsWorld) - cropBox.center) * cropBox.R_localToWorld;
end

function world = cropLocalToWorld(pointsLocal, cropBox)
    world = double(pointsLocal) * cropBox.R_localToWorld' + cropBox.center;
end

function corners = cropBoxCornersWorld(cropBox)
    b = cropBox.localBounds;
    local = [ ...
        b(1, 1) b(2, 1) b(3, 1); ...
        b(1, 2) b(2, 1) b(3, 1); ...
        b(1, 2) b(2, 2) b(3, 1); ...
        b(1, 1) b(2, 2) b(3, 1); ...
        b(1, 1) b(2, 1) b(3, 2); ...
        b(1, 2) b(2, 1) b(3, 2); ...
        b(1, 2) b(2, 2) b(3, 2); ...
        b(1, 1) b(2, 2) b(3, 2)];
    corners = cropLocalToWorld(local, cropBox);
end

function R = eulerCropRotation(deg)
    % Convention for display/editing: pitch about local Y, yaw about local Z,
    % roll about local X, composed as yaw * pitch * roll.
    a = deg2rad(double(deg(:)'));
    pitch = a(1);
    yaw = a(2);
    roll = a(3);
    Rx = [1 0 0; 0 cos(roll) -sin(roll); 0 sin(roll) cos(roll)];
    Ry = [cos(pitch) 0 sin(pitch); 0 1 0; -sin(pitch) 0 cos(pitch)];
    Rz = [cos(yaw) -sin(yaw) 0; sin(yaw) cos(yaw) 0; 0 0 1];
    R = Rz * Ry * Rx;
end

function [cropBox, accepted, guiInfo, keepLargestComponent] = cropScanGui(scan, cropBox, opts)
    accepted = false;
    guiInfo = struct();
    keepLargestComponent = opts.keepLargestComponent;
    V = scan.vertices;
    displayScan = decimateForDisplay(scan, opts.displayMaxFaces);
    displayColors = displayScan.rgb;
    if isempty(displayColors)
        displayColors = repmat([0.72 0.74 0.76], size(displayScan.vertices, 1), 1);
    end
    sceneBounds = initialCropBounds(V);
    sceneSpan = sceneBounds(:, 2) - sceneBounds(:, 1);
    sceneSpan(sceneSpan <= 0) = 1;
    localSceneBounds = cropLocalSceneBounds(V, cropBox);
    localSceneSpan = localSceneBounds(:, 2) - localSceneBounds(:, 1);
    localSceneSpan(localSceneSpan <= 0) = 1;
    activeDim = 1;
    dragStart = [];
    isWaiting = false;

    fig = figure('Name', 'Phone scan head crop', ...
        'NumberTitle', 'off', ...
        'Color', 'w', ...
        'Units', 'pixels', ...
        'Position', [80 60 1400 820], ...
        'CloseRequestFcn', @onCancel);
    fileMenu = uimenu(fig, 'Label', 'File');
    uimenu(fileMenu, 'Label', 'Accept crop', 'Callback', @onDone);
    uimenu(fileMenu, 'Label', 'Cancel', 'Callback', @onCancel);
    ax = axes('Parent', fig, 'Units', 'normalized', ...
        'Position', cropGuiAxesPosition(), ...
        'ActivePositionProperty', 'position');
    hold(ax, 'on');
    meshPatch = patch(ax, ...
        'Faces', displayScan.faces, ...
        'Vertices', displayScan.vertices, ...
        'FaceVertexCData', displayColors, ...
        'FaceColor', 'interp', ...
        'FaceAlpha', opts.faceAlpha, ...
        'EdgeColor', 'none', ...
        'FaceLighting', 'flat', ...
        'BackFaceLighting', 'reverselit', ...
        'AmbientStrength', 0.55, ...
        'DiffuseStrength', 0.45, ...
        'SpecularStrength', 0.05, ...
        'HitTest', 'off');
    outsidePatch = patch(ax, ...
        'Faces', displayScan.faces, ...
        'Vertices', displayScan.vertices, ...
        'FaceColor', [0.72 0.72 0.72], ...
        'FaceAlpha', 0.05, ...
        'EdgeColor', 'none', ...
        'FaceLighting', 'flat', ...
        'BackFaceLighting', 'reverselit', ...
        'AmbientStrength', 0.55, ...
        'DiffuseStrength', 0.45, ...
        'SpecularStrength', 0.05, ...
        'HitTest', 'off');
    boxHandles = gobjects(12, 1);
    for i = 1:12
        boxHandles(i) = plot3(ax, nan, nan, nan, 'm-', ...
            'LineWidth', 2.2, 'HitTest', 'off');
    end
    camproj(ax, 'orthographic');
    axis(ax, 'equal');
    axis(ax, 'vis3d');
    axis(ax, 'off');
    title(ax, 'Phone scan crop to head', 'FontWeight', 'bold');
    view(ax, 3);
    frameCropBoxView(ax, cropBox, 1.25);
    fitCameraToCropBoxProjection(ax, cropBox, 1.08);
    cameraLight = camlight(ax, 'headlight');
    lighting(ax, 'flat');

    status = uicontrol(fig, 'Style', 'text', ...
        'Units', 'normalized', ...
        'Position', [0.77 0.67 0.21 0.24], ...
        'BackgroundColor', 'w', ...
        'HorizontalAlignment', 'left', ...
        'FontSize', 10);
    dimPopup = uicontrol(fig, 'Style', 'popupmenu', ...
        'String', {'X bounds', 'Y bounds', 'Z bounds'}, ...
        'Units', 'normalized', ...
        'Position', [0.78 0.60 0.18 0.045], ...
        'Value', activeDim, ...
        'Callback', @onDimPopup);
    minText = uicontrol(fig, 'Style', 'text', ...
        'Units', 'normalized', 'Position', [0.78 0.545 0.18 0.025], ...
        'BackgroundColor', 'w', 'HorizontalAlignment', 'left');
    minSlider = uicontrol(fig, 'Style', 'slider', ...
        'Units', 'normalized', 'Position', [0.78 0.515 0.18 0.03], ...
        'Callback', @onMinSlider);
    maxText = uicontrol(fig, 'Style', 'text', ...
        'Units', 'normalized', 'Position', [0.78 0.465 0.18 0.025], ...
        'BackgroundColor', 'w', 'HorizontalAlignment', 'left');
    maxSlider = uicontrol(fig, 'Style', 'slider', ...
        'Units', 'normalized', 'Position', [0.78 0.435 0.18 0.03], ...
        'Callback', @onMaxSlider);
    keepLargestCheckbox = uicontrol(fig, 'Style', 'checkbox', ...
        'String', 'Keep largest component', ...
        'Units', 'normalized', ...
        'Position', [0.78 0.37 0.18 0.04], ...
        'BackgroundColor', 'w', ...
        'Value', opts.keepLargestComponent, ...
        'Callback', @updateGraphics);
    uicontrol(fig, 'Style', 'pushbutton', ...
        'String', 'Reset full scene', ...
        'Units', 'normalized', ...
        'Position', [0.78 0.29 0.18 0.055], ...
        'Callback', @onReset);
    uicontrol(fig, 'Style', 'pushbutton', ...
        'String', 'Accept crop', ...
        'Units', 'normalized', ...
        'Position', [0.78 0.20 0.18 0.065], ...
        'Callback', @onDone);
    uicontrol(fig, 'Style', 'pushbutton', ...
        'String', 'Cancel', ...
        'Units', 'normalized', ...
        'Position', [0.78 0.12 0.18 0.055], ...
        'Callback', @onCancel);
    help = uicontrol(fig, 'Style', 'text', ...
        'Units', 'normalized', ...
        'Position', [0.77 0.02 0.22 0.08], ...
        'BackgroundColor', 'w', ...
        'HorizontalAlignment', 'left', ...
        'FontSize', 9, ...
        'String', sprintf(['Drag: rotate | Shift-drag: camera roll\n', ...
                           '1-6: fit crop-box face views\n', ...
                           'Shift+1-6: same views, keep zoom\n', ...
                           'P/Y/R rotate box, Shift reverses\n', ...
                           'O/T/E also reverse pitch/yaw/roll\n', ...
                           'Arrows: nudge active local crop bounds\n', ...
                           'Use sliders to crop chair/drapes/stray objects']));

    updateGraphics();
    set(fig, 'WindowButtonDownFcn', @onMouseDown, ...
        'WindowButtonUpFcn', @onMouseUp, ...
        'WindowKeyPressFcn', @onKeyPress);
    isWaiting = true;
    uiwait(fig);
    isWaiting = false;
    guiInfo.displayMeshStats = scanStats(displayScan.vertices, displayScan.faces);
    if isgraphics(help)
        guiInfo.helpText = get(help, 'String');
    else
        guiInfo.helpText = '';
    end
    if isgraphics(fig)
        delete(fig);
    end

    function onDimPopup(~, ~)
        activeDim = get(dimPopup, 'Value');
        updateGraphics();
    end

    function onMinSlider(~, ~)
        value = get(minSlider, 'Value');
        upperLimit = cropBox.localBounds(activeDim, 2) - ...
            1e-6 * localSceneSpan(activeDim);
        cropBox.localBounds(activeDim, 1) = min(value, upperLimit);
        updateGraphics();
    end

    function onMaxSlider(~, ~)
        value = get(maxSlider, 'Value');
        lowerLimit = cropBox.localBounds(activeDim, 1) + ...
            1e-6 * localSceneSpan(activeDim);
        cropBox.localBounds(activeDim, 2) = max(value, lowerLimit);
        updateGraphics();
    end

    function onReset(~, ~)
        cropBox = initialCropBox(V, [], [0 0 0]);
        localSceneBounds = cropLocalSceneBounds(V, cropBox);
        localSceneSpan = localSceneBounds(:, 2) - localSceneBounds(:, 1);
        localSceneSpan(localSceneSpan <= 0) = 1;
        updateGraphics();
    end

    function onDone(~, ~)
        keepLargestComponent = logical(get(keepLargestCheckbox, 'Value'));
        accepted = true;
        resumeOrDelete();
    end

    function onCancel(~, ~)
        accepted = false;
        resumeOrDelete();
    end

    function resumeOrDelete()
        if ~isgraphics(fig)
            return;
        end
        if isWaiting
            uiresume(fig);
        else
            delete(fig);
        end
    end

    function onMouseDown(~, ~)
        if matlabToolbarModeActive(fig)
            clearCustomDrag();
            return;
        end
        clickedAxes = ancestor(hittest(fig), 'axes');
        if isempty(clickedAxes) || clickedAxes ~= ax
            clearCustomDrag();
            return;
        end
        dragStart = get(fig, 'CurrentPoint');
        set(fig, 'WindowButtonMotionFcn', @onDrag);
    end

    function onDrag(~, ~)
        if isempty(dragStart) || matlabToolbarModeActive(fig)
            clearCustomDrag();
            return;
        end
        pointer = get(fig, 'CurrentPoint');
        delta = pointer - dragStart;
        dragStart = pointer;
        modifiers = get(fig, 'CurrentModifier');
        if hasModifier(modifiers, 'shift')
            rollCamera(ax, 0.4 * delta(1));
        else
            camorbit(ax, -0.35 * delta(1), -0.35 * delta(2), 'camera');
        end
        camlight(cameraLight, 'headlight');
        drawnow limitrate;
    end

    function onMouseUp(~, ~)
        clearCustomDrag();
    end

    function onKeyPress(~, event)
        clearCustomDrag();
        key = lower(event.Key);
        switch key
            case {'1', 'numpad1'}
                setCropBoxFaceView(1, eventHasModifier(event, 'shift'));
            case {'exclamation', '!'}
                setCropBoxFaceView(1, true);
            case {'2', 'numpad2'}
                setCropBoxFaceView(2, eventHasModifier(event, 'shift'));
            case {'at', '@'}
                setCropBoxFaceView(2, true);
            case {'3', 'numpad3'}
                setCropBoxFaceView(3, eventHasModifier(event, 'shift'));
            case {'number', 'hash', '#'}
                setCropBoxFaceView(3, true);
            case {'4', 'numpad4'}
                setCropBoxFaceView(4, eventHasModifier(event, 'shift'));
            case {'dollar', '$'}
                setCropBoxFaceView(4, true);
            case {'5', 'numpad5'}
                setCropBoxFaceView(5, eventHasModifier(event, 'shift'));
            case {'percent', '%'}
                setCropBoxFaceView(5, true);
            case {'6', 'numpad6'}
                setCropBoxFaceView(6, eventHasModifier(event, 'shift'));
            case {'caret', '^'}
                setCropBoxFaceView(6, true);
            case 'p'
                rotateCropBox([keyDirection(event) 0 0]);
            case 'o'
                rotateCropBox([-1 0 0]);
            case 'y'
                rotateCropBox([0 keyDirection(event) 0]);
            case 't'
                rotateCropBox([0 -1 0]);
            case 'r'
                rotateCropBox([0 0 keyDirection(event)]);
            case 'e'
                rotateCropBox([0 0 -1]);
            case 'leftarrow'
                nudgeBound(-1);
            case 'rightarrow'
                nudgeBound(1);
            case 'uparrow'
                nudgeActiveDim(1);
            case 'downarrow'
                nudgeActiveDim(-1);
            case {'return', 'enter'}
                onDone([], []);
            case 'escape'
                onCancel([], []);
        end
    end

    function clearCustomDrag()
        dragStart = [];
        if isgraphics(fig)
            set(fig, 'WindowButtonMotionFcn', '');
        end
    end

    function nudgeBound(direction)
        step = 0.01 * localSceneSpan(activeDim);
        modifiers = get(fig, 'CurrentModifier');
        if hasModifier(modifiers, 'shift')
            step = 5 * step;
        end
        if hasModifier(modifiers, 'control') || hasModifier(modifiers, 'command')
            cropBox.localBounds(activeDim, 2) = ...
                cropBox.localBounds(activeDim, 2) + direction * step;
        else
            cropBox.localBounds(activeDim, 1) = ...
                cropBox.localBounds(activeDim, 1) + direction * step;
        end
        cropBox.localBounds(activeDim, :) = clampBoundPair( ...
            cropBox.localBounds(activeDim, :), ...
            localSceneBounds(activeDim, :), localSceneSpan(activeDim));
        updateGraphics();
    end

    function nudgeActiveDim(direction)
        step = 0.01 * localSceneSpan(activeDim);
        modifiers = get(fig, 'CurrentModifier');
        if hasModifier(modifiers, 'shift')
            step = 5 * step;
        end
        cropBox.localBounds(activeDim, :) = ...
            cropBox.localBounds(activeDim, :) + direction * step;
        cropBox.localBounds(activeDim, :) = clampBoundPair( ...
            cropBox.localBounds(activeDim, :), ...
            localSceneBounds(activeDim, :), localSceneSpan(activeDim));
        updateGraphics();
    end

    function rotateCropBox(deltaSigns)
        cropBox.rotationDeg = cropBox.rotationDeg + ...
            opts.rotationStepDeg * double(deltaSigns);
        cropBox.R_localToWorld = eulerCropRotation(cropBox.rotationDeg);
        localSceneBounds = cropLocalSceneBounds(V, cropBox);
        localSceneSpan = localSceneBounds(:, 2) - localSceneBounds(:, 1);
        localSceneSpan(localSceneSpan <= 0) = 1;
        cropBox.localBounds = validateAndClampBounds( ...
            cropBox.localBounds, localSceneBounds);
        updateGraphics();
    end

    function direction = keyDirection(event)
        direction = 1;
        if eventHasModifier(event, 'shift')
            direction = -1;
        end
    end

    function setCropBoxFaceView(faceNumber, preserveZoom)
        if nargin < 2
            preserveZoom = false;
        end
        [axisDirection, upDirection] = cropBoxFaceCamera(faceNumber, cropBox);
        anchor = cropBox.center;
        oldLimits = [xlim(ax); ylim(ax); zlim(ax)];
        cameraDistance = norm(campos(ax) - camtarget(ax));
        if ~isfinite(cameraDistance) || cameraDistance <= 0
            corners = cropBoxCornersWorld(cropBox);
            radius = max(sqrt(sum((corners - cropBox.center) .^ 2, 2)));
            cameraDistance = 10 * max(radius, 1);
        end
        camtarget(ax, anchor);
        campos(ax, anchor + cameraDistance * axisDirection);
        camup(ax, upDirection);
        if preserveZoom
            recenterExistingLimits(ax, anchor, oldLimits);
        else
            setCropBoxLimits(ax, cropBox, 1.06);
            fitCameraToCropBoxProjection(ax, cropBox, 1.06);
        end
        camlight(cameraLight, 'headlight');
        drawnow limitrate;
    end

    function updateGraphics(~, ~)
        cropBox.localBounds = validateAndClampBounds( ...
            cropBox.localBounds, localSceneBounds);
        set(minSlider, 'Min', localSceneBounds(activeDim, 1), ...
            'Max', localSceneBounds(activeDim, 2), ...
            'Value', cropBox.localBounds(activeDim, 1));
        set(maxSlider, 'Min', localSceneBounds(activeDim, 1), ...
            'Max', localSceneBounds(activeDim, 2), ...
            'Value', cropBox.localBounds(activeDim, 2));
        dimNames = {'local X', 'local Y', 'local Z'};
        set(minText, 'String', sprintf('%s min: %.2f', ...
            dimNames{activeDim}, cropBox.localBounds(activeDim, 1)));
        set(maxText, 'String', sprintf('%s max: %.2f', ...
            dimNames{activeDim}, cropBox.localBounds(activeDim, 2)));

        displayKeepV = verticesInCropBox(displayScan.vertices, cropBox);
        displayKeepF = all(displayKeepV(displayScan.faces), 2);
        set(meshPatch, 'Faces', displayScan.faces(displayKeepF, :), ...
            'Vertices', displayScan.vertices);
        if opts.showOutsideCrop
            set(outsidePatch, 'Faces', displayScan.faces(~displayKeepF, :), ...
                'Vertices', displayScan.vertices);
        else
            set(outsidePatch, 'Faces', zeros(0, 3), ...
                'Vertices', displayScan.vertices);
        end
        drawCropBox(boxHandles, cropBox);

        fullKeepV = verticesInCropBox(V, cropBox);
        fullKeepF = all(fullKeepV(scan.faces), 2);
        nFaces = nnz(fullKeepF);
        nVertices = nnz(fullKeepV);
        set(status, 'String', sprintf([ ...
            'Source vertices: %d\nSource faces: %d\n\n', ...
            'Crop vertices: %d\nCrop faces: %d\n\n', ...
            'Local bounds:\nX [%.1f %.1f]\nY [%.1f %.1f]\nZ [%.1f %.1f]\n\n', ...
            'Rotation deg: pitch %.1f, yaw %.1f, roll %.1f\n\n', ...
            'Known scale check: cylinder diameter should be 25.25 mm'], ...
            size(V, 1), size(scan.faces, 1), nVertices, nFaces, ...
            cropBox.localBounds(1, 1), cropBox.localBounds(1, 2), ...
            cropBox.localBounds(2, 1), cropBox.localBounds(2, 2), ...
            cropBox.localBounds(3, 1), cropBox.localBounds(3, 2), ...
            cropBox.rotationDeg(1), cropBox.rotationDeg(2), ...
            cropBox.rotationDeg(3)));
        drawnow limitrate;
    end
end

function scanOut = decimateForDisplay(scan, maxFaces)
    scanOut = scan;
    nFaces = size(scan.faces, 1);
    if nFaces <= maxFaces
        return;
    end
    try
        [F2, V2] = reducepatch(scan.faces, scan.vertices, maxFaces);
        scanOut.vertices = double(V2);
        scanOut.faces = double(F2);
        scanOut.normals = zeros(0, 3);
        scanOut.rgb = zeros(0, 3);
    catch
        step = max(1, ceil(nFaces / maxFaces));
        F = scan.faces(1:step:end, :);
        used = unique(F(:));
        map = zeros(size(scan.vertices, 1), 1);
        map(used) = 1:numel(used);
        scanOut.vertices = scan.vertices(used, :);
        scanOut.faces = map(F);
        if ~isempty(scan.rgb)
            scanOut.rgb = scan.rgb(used, :);
        else
            scanOut.rgb = zeros(0, 3);
        end
        if ~isempty(scan.normals)
            scanOut.normals = scan.normals(used, :);
        else
            scanOut.normals = zeros(0, 3);
        end
    end
end

function crop = cropScanMesh(scan, cropBox, opts)
    keepV = verticesInCropBox(scan.vertices, cropBox);
    keepF = all(keepV(scan.faces), 2);
    faces = scan.faces(keepF, :);
    if isempty(faces)
        crop = emptyCrop(scan);
        return;
    end
    sourceFaceRows = find(keepF);

    if opts.keepLargestComponent
        comp = faceComponents(faces, size(scan.vertices, 1));
        counts = accumarray(comp(:), 1);
        [~, keepComp] = max(counts);
        sourceFaceRows = sourceFaceRows(comp == keepComp);
        faces = faces(comp == keepComp, :);
    end

    used = unique(faces(:));
    map = zeros(size(scan.vertices, 1), 1);
    map(used) = 1:numel(used);
    crop = struct();
    crop.vertices = scan.vertices(used, :);
    crop.faces = map(faces);
    if ~isempty(scan.normals)
        crop.normals = scan.normals(used, :);
    else
        crop.normals = zeros(0, 3);
    end
    if ~isempty(scan.rgb)
        crop.rgb = scan.rgb(used, :);
    else
        crop.rgb = zeros(0, 3);
    end
    crop.sourceVertexRows = used(:);
    crop.sourceFaceRows = sourceFaceRows(:);
    crop.cropBox = cropBox;
    crop.cropBounds = cropBoxAxisAlignedBounds(cropBox);
end

function crop = emptyCrop(scan)
    crop = struct('vertices', zeros(0, 3), 'faces', zeros(0, 3), ...
        'normals', zeros(0, 3), 'rgb', zeros(0, 3), ...
        'sourceVertexRows', zeros(0, 1), 'sourceFaceRows', zeros(0, 1), ...
        'cropBox', struct(), 'cropBounds', zeros(3, 2));
end

function keep = verticesInCropBox(V, cropBox)
    local = worldToCropLocal(V, cropBox);
    bounds = cropBox.localBounds;
    keep = local(:, 1) >= bounds(1, 1) & local(:, 1) <= bounds(1, 2) & ...
           local(:, 2) >= bounds(2, 1) & local(:, 2) <= bounds(2, 2) & ...
           local(:, 3) >= bounds(3, 1) & local(:, 3) <= bounds(3, 2);
end

function bounds = cropLocalSceneBounds(V, cropBox)
    local = worldToCropLocal(V, cropBox);
    bounds = initialCropBounds(local);
end

function bounds = validateAndClampBounds(bounds, sceneBounds)
    for d = 1:3
        bounds(d, :) = clampBoundPair(bounds(d, :), sceneBounds(d, :), ...
            sceneBounds(d, 2) - sceneBounds(d, 1));
    end
end

function pair = clampBoundPair(pair, scenePair, span)
    span = max(span, eps);
    pair(1) = max(scenePair(1), min(scenePair(2), pair(1)));
    pair(2) = max(scenePair(1), min(scenePair(2), pair(2)));
    if pair(2) <= pair(1)
        mid = mean(pair);
        pair = mid + 0.001 * span * [-1 1];
    end
    pair(1) = max(scenePair(1), pair(1));
    pair(2) = min(scenePair(2), pair(2));
    if pair(2) <= pair(1)
        pair = scenePair;
    end
end

function drawCropBox(handles, cropBox)
    P = cropBoxCornersWorld(cropBox);
    E = [1 2; 2 3; 3 4; 4 1; 5 6; 6 7; 7 8; 8 5; 1 5; 2 6; 3 7; 4 8];
    for i = 1:size(E, 1)
        set(handles(i), 'XData', P(E(i, :), 1), ...
            'YData', P(E(i, :), 2), ...
            'ZData', P(E(i, :), 3));
    end
end

function rollCamera(ax, angleDeg)
    target = camtarget(ax);
    pos = campos(ax);
    up = camup(ax);
    viewDir = target - pos;
    if norm(viewDir) <= eps
        return;
    end
    R = axisAngleRotation(viewDir / norm(viewDir), deg2rad(angleDeg));
    camup(ax, (R * up(:))');
end

function R = axisAngleRotation(axisVector, angleRad)
    u = axisVector(:) / norm(axisVector);
    K = [0 -u(3) u(2); u(3) 0 -u(1); -u(2) u(1) 0];
    R = eye(3) + sin(angleRad) * K + (1 - cos(angleRad)) * (K * K);
end

function [viewDirection, upDirection] = cropBoxFaceCamera(faceNumber, cropBox)
    R = cropBox.R_localToWorld;
    localAxesWorld = R';
    xAxis = localAxesWorld(1, :);
    yAxis = localAxesWorld(2, :);
    zAxis = localAxesWorld(3, :);
    switch faceNumber
        case 1
            viewDirection = xAxis;
            upDirection = zAxis;
        case 2
            viewDirection = -xAxis;
            upDirection = zAxis;
        case 3
            viewDirection = yAxis;
            upDirection = zAxis;
        case 4
            viewDirection = -yAxis;
            upDirection = zAxis;
        case 5
            viewDirection = zAxis;
            upDirection = yAxis;
        case 6
            viewDirection = -zAxis;
            upDirection = yAxis;
        otherwise
            viewDirection = zAxis;
            upDirection = yAxis;
    end
    viewDirection = normalizeVector(viewDirection);
    upDirection = normalizeVector(upDirection - ...
        dot(upDirection, viewDirection) * viewDirection);
    if norm(upDirection) < 1e-9
        upDirection = [0 1 0];
    end
end

function v = normalizeVector(v)
    v = double(v(:)');
    n = norm(v);
    if ~isfinite(n) || n < 1e-12
        v = [0 0 1];
    else
        v = v ./ n;
    end
end

function tf = hasModifier(modifiers, key)
    tf = any(strcmpi(modifiers, key));
end

function tf = matlabToolbarModeActive(fig)
    tf = false;
    try
        mgr = uigetmodemanager(fig);
        tf = ~isempty(mgr) && ~isempty(mgr.CurrentMode);
    catch
        tf = false;
    end
end

function tf = eventHasModifier(event, key)
    tf = false;
    modifiers = {};
    if isstruct(event) && isfield(event, 'Modifier')
        modifiers = event.Modifier;
    elseif isobject(event) && isprop(event, 'Modifier')
        modifiers = event.Modifier;
    end
    if ~isempty(modifiers)
        tf = any(strcmpi(modifiers, key));
    end
end

function frameCropBoxView(ax, cropBox, padFactor)
    if nargin < 3 || isempty(padFactor)
        padFactor = 1.25;
    end
    pos = campos(ax);
    target = camtarget(ax);
    viewDir = target - pos;
    if any(~isfinite(viewDir)) || norm(viewDir) < 1e-9
        viewDir = [1 1 1];
    end
    viewDir = normalizeVector(viewDir);
    cameraDistance = cropBoxCameraDistance(ax, cropBox, padFactor);
    center = cropBox.center;

    camtarget(ax, center);
    campos(ax, center - cameraDistance * viewDir);
    setCropBoxLimits(ax, cropBox, padFactor);
    fitCameraToCropBoxProjection(ax, cropBox, padFactor);
end

function setCropBoxLimits(ax, cropBox, padFactor)
    if nargin < 3 || isempty(padFactor)
        padFactor = 1.08;
    end
    corners = cropBoxCornersWorld(cropBox);
    lo = min(corners, [], 1);
    hi = max(corners, [], 1);
    span = hi - lo;
    span(~isfinite(span) | span <= 0) = 1;
    pad = 0.5 * (padFactor - 1) * span;
    pad = max(pad, 1e-3);
    xlim(ax, [lo(1) - pad(1), hi(1) + pad(1)]);
    ylim(ax, [lo(2) - pad(2), hi(2) + pad(2)]);
    zlim(ax, [lo(3) - pad(3), hi(3) + pad(3)]);
    axis(ax, 'off');
    axis(ax, 'vis3d');
    set(ax, 'ActivePositionProperty', 'position');
    set(ax, 'Position', cropGuiAxesPosition());
end

function recenterExistingLimits(ax, center, oldLimits)
    if ~isequal(size(oldLimits), [3 2]) || any(~isfinite(oldLimits(:))) || ...
            any(oldLimits(:, 2) <= oldLimits(:, 1))
        return;
    end
    halfSpan = 0.5 * (oldLimits(:, 2) - oldLimits(:, 1));
    xlim(ax, center(1) + halfSpan(1) * [-1 1]);
    ylim(ax, center(2) + halfSpan(2) * [-1 1]);
    zlim(ax, center(3) + halfSpan(3) * [-1 1]);
    axis(ax, 'off');
    axis(ax, 'vis3d');
    set(ax, 'ActivePositionProperty', 'position');
    set(ax, 'Position', cropGuiAxesPosition());
end

function pos = cropGuiAxesPosition()
    pos = [0.035 0.055 0.705 0.86];
end

function cameraDistance = cropBoxCameraDistance(ax, cropBox, padFactor)
    if nargin < 3 || isempty(padFactor)
        padFactor = 1.35;
    end
    corners = cropBoxCornersWorld(cropBox);
    radius = max(sqrt(sum((corners - cropBox.center) .^ 2, 2)));
    if ~isfinite(radius) || radius <= 0
        radius = 1;
    end
    camvaValue = camva(ax);
    if ~isfinite(camvaValue) || camvaValue <= 0 || camvaValue >= 170
        camvaValue = 10;
    end
    cameraDistance = padFactor * radius / sind(0.5 * camvaValue);
end

function fitCameraToCropBoxProjection(ax, cropBox, padFactor)
    if nargin < 3 || isempty(padFactor)
        padFactor = 1.08;
    end
    corners = cropBoxCornersWorld(cropBox);
    center = cropBox.center;
    pos = campos(ax);
    target = camtarget(ax);
    up = camup(ax);
    viewDir = normalizeVector(target - pos);
    if norm(viewDir) < 1e-9
        viewDir = [0 0 1];
    end
    up = normalizeVector(up - dot(up, viewDir) * viewDir);
    if norm(up) < 1e-9
        up = [0 1 0];
    end
    right = normalizeVector(cross(viewDir, up));
    up = normalizeVector(cross(right, viewDir));

    rel = corners - center;
    halfWidth = max(abs(rel * right(:)));
    halfHeight = max(abs(rel * up(:)));
    if ~isfinite(halfWidth) || halfWidth <= 0
        halfWidth = 1;
    end
    if ~isfinite(halfHeight) || halfHeight <= 0
        halfHeight = 1;
    end
    axPos = getpixelposition(ax, true);
    aspect = axPos(3) / max(1, axPos(4));
    verticalHalfExtent = padFactor * max(halfHeight, halfWidth / max(aspect, eps));
    cameraDistance = norm(pos - target);
    if ~isfinite(cameraDistance) || cameraDistance <= 0
        cameraDistance = cropBoxCameraDistance(ax, cropBox, 1.2);
        campos(ax, center - cameraDistance * viewDir);
        camtarget(ax, center);
    end
    desiredCamva = 2 * atan2d(verticalHalfExtent, cameraDistance);
    desiredCamva = max(0.05, min(60, desiredCamva));
    camva(ax, desiredCamva);
    set(ax, 'CameraViewAngleMode', 'manual');
end

function comp = faceComponents(F, nVertices)
    nFaces = size(F, 1);
    if nFaces == 0
        comp = zeros(0, 1);
        return;
    end
    vertexFaces = accumarray(F(:), repmat((1:nFaces)', 3, 1), ...
        [nVertices 1], @(x) {x});
    comp = zeros(nFaces, 1);
    compId = 0;
    for seed = 1:nFaces
        if comp(seed) ~= 0
            continue;
        end
        compId = compId + 1;
        stack = seed;
        comp(seed) = compId;
        while ~isempty(stack)
            f = stack(end);
            stack(end) = [];
            verts = F(f, :);
            neigh = unique(vertcat(vertexFaces{verts}));
            neigh = neigh(comp(neigh) == 0);
            if ~isempty(neigh)
                comp(neigh) = compId;
                stack = [stack; neigh(:)]; %#ok<AGROW>
            end
        end
    end
end

function info = meshComponentInfo(F, nVertices, minFaces)
    comp = faceComponents(F, nVertices);
    if isempty(comp)
        info = struct('nComponents', 0, 'componentFaceCounts', [], ...
            'largeComponentRows', [], 'largestComponentFaces', 0);
        return;
    end
    counts = accumarray(comp(:), 1);
    info = struct();
    info.nComponents = numel(counts);
    info.componentFaceCounts = counts(:);
    info.largeComponentRows = find(counts >= minFaces);
    info.largestComponentFaces = max(counts);
end

function fig = makeQcFigure(scan, crop, componentInfo, opts, figVisible)
    fig = figure('Name', 'Phone scan head crop QC', ...
        'NumberTitle', 'off', 'Color', 'w', 'Visible', figVisible, ...
        'Position', [120 80 1300 680]);
    tl = tiledlayout(fig, 1, 2, 'Padding', 'compact', 'TileSpacing', 'compact');
    ax1 = nexttile(tl);
    hold(ax1, 'on');
    drawMesh(ax1, scan.vertices, scan.faces, scan.rgb, 0.15);
    drawCropBoxOnAxes(ax1, crop.cropBox);
    title(ax1, 'source scan and crop box');
    formatScanAxes(ax1);

    ax2 = nexttile(tl);
    hold(ax2, 'on');
    drawMesh(ax2, crop.vertices, crop.faces, crop.rgb, opts.faceAlpha);
    title(ax2, sprintf('cropped head mesh (%d components)', ...
        componentInfo.nComponents));
    formatScanAxes(ax2);
    title(tl, 'Phone scan crop QC', 'FontWeight', 'bold');
end

function drawMesh(ax, V, F, rgb, alphaValue)
    if isempty(V) || isempty(F)
        return;
    end
    if isempty(rgb)
        patch(ax, 'Faces', F, 'Vertices', V, ...
            'FaceColor', [0.70 0.72 0.75], ...
            'FaceAlpha', alphaValue, 'EdgeColor', 'none', ...
            'FaceLighting', 'flat', ...
            'BackFaceLighting', 'reverselit', ...
            'AmbientStrength', 0.55, ...
            'DiffuseStrength', 0.45, ...
            'SpecularStrength', 0.05);
    else
        patch(ax, 'Faces', F, 'Vertices', V, ...
            'FaceVertexCData', rgb, 'FaceColor', 'interp', ...
            'FaceAlpha', alphaValue, 'EdgeColor', 'none', ...
            'FaceLighting', 'flat', ...
            'BackFaceLighting', 'reverselit', ...
            'AmbientStrength', 0.55, ...
            'DiffuseStrength', 0.45, ...
            'SpecularStrength', 0.05);
    end
end

function drawCropBoxOnAxes(ax, cropBox)
    h = gobjects(12, 1);
    for i = 1:12
        h(i) = plot3(ax, nan, nan, nan, 'm-', 'LineWidth', 2.0);
    end
    drawCropBox(h, cropBox);
end

function formatScanAxes(ax)
    axis(ax, 'equal');
    axis(ax, 'vis3d');
    grid(ax, 'on');
    xlabel(ax, 'X');
    ylabel(ax, 'Y');
    zlabel(ax, 'Z');
    view(ax, 3);
    camproj(ax, 'orthographic');
    camlight(ax, 'headlight');
    lighting(ax, 'flat');
end

function stats = scanStats(V, F)
    if isempty(V)
        stats = struct('nVertices', 0, 'nFaces', size(F, 1), ...
            'min', [NaN NaN NaN], 'max', [NaN NaN NaN], ...
            'span', [NaN NaN NaN], 'diagonal', NaN);
        return;
    end
    lo = min(V, [], 1);
    hi = max(V, [], 1);
    span = hi - lo;
    stats = struct('nVertices', size(V, 1), ...
        'nFaces', size(F, 1), ...
        'min', lo, 'max', hi, 'span', span, ...
        'diagonal', norm(span));
end

function writeAsciiPlyMesh(fileName, mesh)
    ensureDir(fileparts(fileName));
    fid = fopen(fileName, 'w');
    if fid == -1
        error('acsCropPhoneScanToHead:CannotWritePly', ...
            'Could not write cropped PLY file: %s', fileName);
    end
    cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>

    hasNormals = ~isempty(mesh.normals) && size(mesh.normals, 1) == size(mesh.vertices, 1);
    hasRgb = ~isempty(mesh.rgb) && size(mesh.rgb, 1) == size(mesh.vertices, 1);
    fprintf(fid, 'ply\n');
    fprintf(fid, 'format ascii 1.0\n');
    fprintf(fid, 'comment cropped by acsCropPhoneScanToHead\n');
    fprintf(fid, 'element vertex %d\n', size(mesh.vertices, 1));
    fprintf(fid, 'property float x\nproperty float y\nproperty float z\n');
    if hasNormals
        fprintf(fid, 'property float nx\nproperty float ny\nproperty float nz\n');
    end
    if hasRgb
        fprintf(fid, 'property uchar red\nproperty uchar green\nproperty uchar blue\n');
    end
    fprintf(fid, 'element face %d\n', size(mesh.faces, 1));
    fprintf(fid, 'property list uchar int vertex_indices\n');
    fprintf(fid, 'end_header\n');
    rgb255 = round(max(0, min(1, mesh.rgb)) * 255);
    for i = 1:size(mesh.vertices, 1)
        fprintf(fid, '%.8g %.8g %.8g', mesh.vertices(i, :));
        if hasNormals
            fprintf(fid, ' %.8g %.8g %.8g', mesh.normals(i, :));
        end
        if hasRgb
            fprintf(fid, ' %d %d %d', rgb255(i, :));
        end
        fprintf(fid, '\n');
    end
    for i = 1:size(mesh.faces, 1)
        fprintf(fid, '3 %d %d %d\n', mesh.faces(i, :) - 1);
    end
end

function exportFigure(fig, fileName)
    try
        exportgraphics(fig, fileName, 'Resolution', 220);
    catch
        saveas(fig, fileName);
    end
end

function printSummary(out)
    fprintf('\nPhone scan head crop\n');
    fprintf('  source: %s\n', out.sourceFile);
    fprintf('  source vertices/faces: %d / %d\n', ...
        out.sourceStats.nVertices, out.sourceStats.nFaces);
    fprintf('  cropped vertices/faces: %d / %d\n', ...
        out.cropStats.nVertices, out.cropStats.nFaces);
    fprintf('  cropped span: [%.3g %.3g %.3g]\n', out.cropStats.span);
    fprintf('  crop rotation deg [pitch yaw roll]: [%.3g %.3g %.3g]\n', ...
        out.cropBox.rotationDeg);
    fprintf('  components: %d; largest has %d faces\n', ...
        out.componentInfo.nComponents, out.componentInfo.largestComponentFaces);
    fprintf('  MAT: %s\n', out.outputFile);
    if ~isempty(out.croppedPlyFile)
        fprintf('  cropped PLY: %s\n', out.croppedPlyFile);
    end
    if ~isempty(out.qcFigure)
        fprintf('  QC figure: %s\n', out.qcFigure);
    end
    fprintf('\n');
end

function ensureDir(folder)
    if ~isempty(folder) && exist(folder, 'dir') ~= 7
        mkdir(folder);
    end
end

function fileName = expandUserPath(fileName)
    if isempty(fileName)
        return;
    end
    if startsWith(fileName, '~')
        homeDir = char(java.lang.System.getProperty('user.home'));
        fileName = fullfile(homeDir, fileName(2:end));
    end
end

function name = getFileName(fileName)
    [~, name, ext] = fileparts(char(fileName));
    name = [name ext];
end

function stem = stripExtension(fileName)
    [~, stem, ~] = fileparts(char(fileName));
end

function value = safeName(value)
    value = regexprep(char(value), '[^\w\-]+', '_');
    value = regexprep(value, '_+', '_');
    value = regexprep(value, '^_|_$', '');
    if isempty(value)
        value = 'phoneScanHeadCrop';
    end
end
