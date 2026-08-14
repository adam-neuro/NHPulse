function out = acsVisualizeCapOnPhoneScan(phoneScanIn, registrationIn, capIn, varargin)
% ACSVISUALIZECAPONPHONESCAN Overlay a saved cap mesh on a colored phone PLY.
%
% out = acsVisualizeCapOnPhoneScan(plyFile, phoneRegistration, fitCheckReport)
% loads a colored phone-scan PLY, applies the phone-to-capMaker registration,
% applies the printer-bed crop transform when needed, and overlays a saved
% cap/fitting scaffold mesh in capMaker print-frame millimeters.
%
% phoneScanIn can be the original PLY, an acsCropPhoneScanToHead MAT file,
% or its output struct. registrationIn should be the saved
% acsRegisterPhoneScanToCapMakerFrame output. capIn can be an
% acsBuildCapMakerFitCheckStl report/output, its output folder, mesh MAT, or
% a triangulation.
%
% Name-value options:
%   skinCacheFile     : cropped printer-bed skin cache used for fabrication ['']
%   useSourcePly      : for crop MAT input, prefer the original full PLY [true]
%   displayMaxFaces   : maximum phone-scan faces rendered [120000]
%   scanAlpha         : phone scan opacity [1]
%   capAlpha          : cap/scaffold opacity [0.82]
%   capColor          : RGB cap color [[0.05 0.22 0.95]]
%   showSkinWire      : overlay capMaker skin wireframe [false]
%   layoutMode        : 'single' or 'fourPanel' ['single']
%   outputFile        : saved PNG path ['']
%   outputTag         : output stem suffix ['capOnPhoneScan']
%   showFigures       : show the figure [true]
%   saveFigures       : save PNG [false]
%   verbose           : print summary [true]

    if nargin < 1 || isempty(phoneScanIn)
        error('acsVisualizeCapOnPhoneScan:MissingPhoneScan', ...
            'Provide a phone PLY/crop product.');
    end
    if nargin < 2 || isempty(registrationIn)
        error('acsVisualizeCapOnPhoneScan:MissingRegistration', ...
            'Provide an acsRegisterPhoneScanToCapMakerFrame output.');
    end
    if nargin < 3 || isempty(capIn)
        error('acsVisualizeCapOnPhoneScan:MissingCap', ...
            'Provide a fit-check report, mesh MAT, output struct, or triangulation.');
    end

    opts = parseInputs(varargin{:});
    addLocalDependencies();

    scan = readPhoneScan(phoneScanIn, opts);
    registration = readRegistration(registrationIn);
    cap = readCap(capIn);
    opts = inferSkinCacheFile(opts, cap);
    skin = readSkinCache(opts.skinCacheFile, registration);

    [scanPrintMm, transformInfo] = phoneScanToPrintFrame(scan.vertices, ...
        registration, skin);
    [scanDraw, capDraw, skinDraw] = prepareDisplayMeshes( ...
        scan, scanPrintMm, cap, skin, opts);

    fig = [];
    qcFile = '';
    if opts.showFigures || opts.saveFigures
        visible = 'off';
        if opts.showFigures
            visible = 'on';
        end
        fig = makeFigure(scanDraw, capDraw, skinDraw, transformInfo, opts, visible);
        if opts.saveFigures
            qcFile = opts.outputFile;
            if isempty(qcFile)
                qcFile = defaultOutputFile(scan, cap, opts);
            end
            ensureDir(fileparts(qcFile));
            exportQcFigure(fig, qcFile);
        end
        if ~opts.showFigures && isgraphics(fig)
            close(fig);
            fig = [];
        end
    end

    out = struct();
    out.createdOn = char(datetime('now'));
    out.type = 'capOnPhoneScanVisualization';
    out.phoneScan = rmfieldIfPresent(scan.info, {'vertices', 'faces', 'rgb'});
    out.registrationFile = registration.sourceFile;
    out.cap = cap.info;
    out.skinCacheFile = opts.skinCacheFile;
    out.coordinateFrame = 'capMakerPrintMm';
    out.transformInfo = transformInfo;
    out.qcFigure = qcFile;
    out.scanDisplayFaceCount = size(scanDraw.faces, 1);
    out.capDisplayFaceCount = size(capDraw.faces, 1);
    if isgraphics(fig)
        out.figure = fig;
    end

    if opts.verbose
        fprintf('\nCap-on-phone-scan QC\n');
        fprintf('  phone scan: %s\n', scan.info.file);
        fprintf('  registration: %s\n', registration.sourceFile);
        fprintf('  cap mesh: %s\n', cap.info.file);
        fprintf('  skin cache: %s\n', opts.skinCacheFile);
        fprintf('  registration target frame: %s\n', transformInfo.registrationTargetFrame);
        fprintf('  display phone faces: %d / %d\n', ...
            size(scanDraw.faces, 1), size(scan.faces, 1));
        fprintf('  display cap faces: %d\n', size(capDraw.faces, 1));
        if ~isempty(qcFile)
            fprintf('  QC figure: %s\n', qcFile);
        end
        fprintf('\n');
    end
end

function opts = parseInputs(varargin)
    p = inputParser;
    p.FunctionName = 'acsVisualizeCapOnPhoneScan';
    addParameter(p, 'skinCacheFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'useSourcePly', true, @isBoolLike);
    addParameter(p, 'displayMaxFaces', 120000, @isPositiveScalar);
    addParameter(p, 'scanAlpha', 1, @isUnitScalar);
    addParameter(p, 'capAlpha', 0.82, @isUnitScalar);
    addParameter(p, 'capColor', [0.05 0.22 0.95], @isRgb);
    addParameter(p, 'showSkinWire', false, @isBoolLike);
    addParameter(p, 'layoutMode', 'single', @(x) ischar(x) || isstring(x));
    addParameter(p, 'outputFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'outputTag', 'capOnPhoneScan', @(x) ischar(x) || isstring(x));
    addParameter(p, 'showFigures', true, @isBoolLike);
    addParameter(p, 'saveFigures', false, @isBoolLike);
    addParameter(p, 'verbose', true, @isBoolLike);
    parse(p, varargin{:});

    opts = p.Results;
    opts.skinCacheFile = expandUserPath(char(opts.skinCacheFile));
    opts.useSourcePly = logical(opts.useSourcePly);
    opts.displayMaxFaces = round(double(opts.displayMaxFaces));
    opts.scanAlpha = double(opts.scanAlpha);
    opts.capAlpha = double(opts.capAlpha);
    opts.capColor = double(opts.capColor(:))';
    opts.showSkinWire = logical(opts.showSkinWire);
    opts.layoutMode = normalizeLayoutMode(opts.layoutMode);
    opts.outputFile = expandUserPath(char(opts.outputFile));
    opts.outputTag = safeName(char(opts.outputTag));
    opts.showFigures = logical(opts.showFigures);
    opts.saveFigures = logical(opts.saveFigures);
    opts.verbose = logical(opts.verbose);
end

function mode = normalizeLayoutMode(value)
    key = lower(regexprep(strtrim(char(value)), '[\s_\-]+', ''));
    switch key
        case {'single', 'one', 'oneaxes', 'oneaxis'}
            mode = 'single';
        case {'fourpanel', 'fourpanels', 'multipanel', 'grid', 'diagnostic'}
            mode = 'fourPanel';
        otherwise
            error('acsVisualizeCapOnPhoneScan:BadLayoutMode', ...
                'layoutMode must be ''single'' or ''fourPanel''.');
    end
end

function tf = isBoolLike(x)
    tf = (islogical(x) || isnumeric(x)) && isscalar(x);
end

function tf = isPositiveScalar(x)
    tf = isnumeric(x) && isscalar(x) && isfinite(x) && x > 0;
end

function tf = isUnitScalar(x)
    tf = isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0 && x <= 1;
end

function tf = isRgb(x)
    tf = isnumeric(x) && numel(x) == 3 && all(isfinite(double(x(:)))) && ...
        all(double(x(:)) >= 0) && all(double(x(:)) <= 1);
end

function addLocalDependencies()
    repoRoot = fileparts(fileparts(mfilename('fullpath')));
    addpath(repoRoot);
    addpath(fullfile(repoRoot, 'acsUtilities'));
    addpath(fullfile(repoRoot, 'capMaker', 'geometry'));
    addpath(fullfile(repoRoot, 'capMaker', 'core'));
end

function scan = readPhoneScan(value, opts)
    sourceFile = '';
    if ischar(value) || isstring(value)
        sourceFile = expandUserPath(char(value));
        if exist(sourceFile, 'file') ~= 2
            error('acsVisualizeCapOnPhoneScan:PhoneScanNotFound', ...
                'Phone scan input not found: %s', sourceFile);
        end
        [~, ~, ext] = fileparts(sourceFile);
        if strcmpi(ext, '.ply')
            scan = readAsciiPlyMesh(sourceFile);
            scan.info.file = sourceFile;
            scan.info.inputType = 'ply';
            return;
        end
        raw = load(sourceFile);
        S = firstStruct(raw);
        if opts.useSourcePly && isfield(S, 'sourceFile') && ...
                exist(expandUserPath(char(S.sourceFile)), 'file') == 2
            scan = readAsciiPlyMesh(expandUserPath(char(S.sourceFile)));
            scan.info.file = expandUserPath(char(S.sourceFile));
            scan.info.inputType = 'sourcePlyFromCrop';
            scan.info.cropFile = sourceFile;
            return;
        end
        scan = scanFromStruct(S, sourceFile);
    elseif isstruct(value)
        if opts.useSourcePly && isfield(value, 'sourceFile') && ...
                exist(expandUserPath(char(value.sourceFile)), 'file') == 2
            scan = readAsciiPlyMesh(expandUserPath(char(value.sourceFile)));
            scan.info.file = expandUserPath(char(value.sourceFile));
            scan.info.inputType = 'sourcePlyFromStruct';
            return;
        end
        scan = scanFromStruct(value, sourceFile);
    else
        error('acsVisualizeCapOnPhoneScan:BadPhoneScanInput', ...
            'phoneScanIn must be a PLY file, crop MAT file, or struct.');
    end
end

function scan = scanFromStruct(S, sourceFile)
    if isfield(S, 'vertices') && isfield(S, 'faces')
        vertices = double(S.vertices);
        faces = double(S.faces);
    elseif isfield(S, 'pointCloudMm') && isfield(S, 'faces')
        vertices = double(S.pointCloudMm);
        faces = double(S.faces);
    elseif isfield(S, 'TRhead') && ~isempty(S.TRhead)
        TR = ensureTriangulation(S.TRhead);
        vertices = double(TR.Points);
        faces = double(TR.ConnectivityList);
    else
        error('acsVisualizeCapOnPhoneScan:BadPhoneScanStruct', ...
            'Phone scan struct must contain vertices/faces or TRhead.');
    end
    rgb = [];
    if isfield(S, 'rgb') && ~isempty(S.rgb)
        rgb = double(S.rgb);
        if max(rgb(:)) > 1
            rgb = rgb ./ 255;
        end
    end
    scan = struct();
    scan.vertices = vertices;
    scan.faces = faces;
    scan.rgb = rgb;
    scan.info = struct('file', sourceFile, 'inputType', 'matOrStruct', ...
        'nVertices', size(vertices, 1), 'nFaces', size(faces, 1));
end

function registration = readRegistration(value)
    if isstruct(value)
        S = value;
        sourceFile = char(getOptionalField(S, 'outputFile', ''));
    else
        sourceFile = expandUserPath(char(value));
        if exist(sourceFile, 'file') ~= 2
            error('acsVisualizeCapOnPhoneScan:RegistrationNotFound', ...
                'Phone registration not found: %s', sourceFile);
        end
        raw = load(sourceFile);
        S = firstStruct(raw);
    end
    required = {'rotation', 'translationMm'};
    for i = 1:numel(required)
        if ~isfield(S, required{i}) || isempty(S.(required{i}))
            error('acsVisualizeCapOnPhoneScan:BadRegistration', ...
                'Registration is missing field "%s".', required{i});
        end
    end
    registration = S;
    registration.sourceFile = sourceFile;
    if ~isfield(registration, 'scale') || isempty(registration.scale)
        registration.scale = 1;
    end
    if ~isfield(registration, 'targetCoordinateFrame') || ...
            isempty(registration.targetCoordinateFrame)
        registration.targetCoordinateFrame = 'capMakerPrintMm';
    end
end

function cap = readCap(value)
    cap = struct('TR', [], 'meshes', struct(), 'report', struct(), ...
        'info', struct('file', '', 'type', ''));
    if isa(value, 'triangulation')
        cap.TR = value;
        cap.info.type = 'triangulation';
        return;
    end
    if isstruct(value)
        cap.report = value;
        cap.meshes = getOptionalField(value, 'meshes', struct());
        if (~isstruct(cap.meshes) || isempty(fieldnames(cap.meshes))) && ...
                isfield(value, 'TRfit')
            cap.meshes.TRfit = value.TRfit;
        end
        if isfield(value, 'meshMat') && ~isempty(value.meshMat)
            cap = mergeCapMeshes(cap, char(value.meshMat));
        end
        cap.TR = firstCapTriangulation(cap.meshes, value);
        cap.info.file = char(getOptionalField(value, 'reportMat', ''));
        cap.info.type = char(getOptionalField(value, 'type', 'struct'));
        if isempty(cap.TR)
            error('acsVisualizeCapOnPhoneScan:BadCapStruct', ...
                'Could not find a cap triangulation in the supplied cap struct.');
        end
        return;
    end

    fileOrFolder = expandUserPath(char(value));
    if exist(fileOrFolder, 'dir') == 7
        replay = acsReplayCapMakerFitCheck(fileOrFolder, ...
            'showFigures', false, 'saveFigures', false, 'verbose', false);
        cap.meshes = replay.meshes;
        cap.report = replay.report;
        cap.TR = firstCapTriangulation(cap.meshes, replay.report);
        cap.info.file = replay.reportMat;
        cap.info.type = 'fitCheckFolder';
        return;
    end
    if exist(fileOrFolder, 'file') ~= 2
        error('acsVisualizeCapOnPhoneScan:CapNotFound', ...
            'Cap input not found: %s', fileOrFolder);
    end
    [~, ~, ext] = fileparts(fileOrFolder);
    switch lower(ext)
        case '.mat'
            raw = load(fileOrFolder);
            if isfield(raw, 'meshes') && isstruct(raw.meshes)
                cap.meshes = raw.meshes;
                cap.report = struct();
                cap.TR = firstCapTriangulation(cap.meshes, struct());
                cap.info.file = fileOrFolder;
                cap.info.type = 'meshMat';
            else
                replay = acsReplayCapMakerFitCheck(fileOrFolder, ...
                    'showFigures', false, 'saveFigures', false, 'verbose', false);
                cap.meshes = replay.meshes;
                cap.report = replay.report;
                cap.TR = firstCapTriangulation(cap.meshes, replay.report);
                cap.info.file = replay.reportMat;
                cap.info.type = 'fitCheckReport';
            end
        case '.stl'
            TR = stlread(fileOrFolder);
            cap.TR = ensureTriangulation(TR);
            cap.info.file = fileOrFolder;
            cap.info.type = 'stl';
        otherwise
            error('acsVisualizeCapOnPhoneScan:BadCapFile', ...
                'Cap file must be a MAT report/mesh or STL.');
    end
    if isempty(cap.TR)
        error('acsVisualizeCapOnPhoneScan:MissingCapMesh', ...
            'Could not find a renderable cap mesh in: %s', fileOrFolder);
    end
end

function cap = mergeCapMeshes(cap, meshFile)
    meshFile = expandUserPath(meshFile);
    if exist(meshFile, 'file') ~= 2
        return;
    end
    raw = load(meshFile);
    if isfield(raw, 'meshes') && isstruct(raw.meshes)
        cap.meshes = raw.meshes;
    end
end

function TR = firstCapTriangulation(meshes, report)
    TR = [];
    preferred = {'TRfit', 'TRtpe', 'TRtpeRaw', 'TRfinal', 'TRrails'};
    if isstruct(meshes)
        for i = 1:numel(preferred)
            if isfield(meshes, preferred{i}) && ~isempty(meshes.(preferred{i}))
                TR = ensureTriangulation(meshes.(preferred{i}));
                if ~isempty(TR)
                    return;
                end
            end
        end
    end
    if isstruct(report)
        for i = 1:numel(preferred)
            if isfield(report, preferred{i}) && ~isempty(report.(preferred{i}))
                TR = ensureTriangulation(report.(preferred{i}));
                if ~isempty(TR)
                    return;
                end
            end
        end
    end
end

function opts = inferSkinCacheFile(opts, cap)
    if ~isempty(opts.skinCacheFile)
        return;
    end
    if isstruct(cap.report) && isfield(cap.report, 'skinSource') && ...
            isstruct(cap.report.skinSource) && ...
            isfield(cap.report.skinSource, 'cacheFile') && ...
            ~isempty(cap.report.skinSource.cacheFile)
        opts.skinCacheFile = expandUserPath(char(cap.report.skinSource.cacheFile));
    end
end

function skin = readSkinCache(fileName, registration)
    skin = struct('TRskin', [], 'meta', struct(), 'sourceFile', fileName);
    frame = normalizeFrame(registration.targetCoordinateFrame);
    if strcmp(frame, 'capmakerprintmm')
        return;
    end
    if isempty(fileName)
        error('acsVisualizeCapOnPhoneScan:MissingSkinCache', ...
            ['Registration target frame is "%s"; provide skinCacheFile so ', ...
             'the phone scan can be transformed into capMakerPrintMm.'], ...
            registration.targetCoordinateFrame);
    end
    if exist(fileName, 'file') ~= 2
        error('acsVisualizeCapOnPhoneScan:SkinCacheNotFound', ...
            'Skin cache not found: %s', fileName);
    end
    S = load(fileName);
    skin.meta = getOptionalField(S, 'meta', struct());
    if isfield(S, 'TRskin') && ~isempty(S.TRskin)
        skin.TRskin = ensureTriangulation(S.TRskin);
    end
end

function [pointsPrint, info] = phoneScanToPrintFrame(pointsPhone, registration, skin)
    R = double(registration.rotation);
    t = double(registration.translationMm(:))';
    s = double(registration.scale);
    pointsTarget = double(pointsPhone) * R * s + t;

    frame = normalizeFrame(registration.targetCoordinateFrame);
    info = struct();
    info.registrationTargetFrame = char(registration.targetCoordinateFrame);
    info.phoneToTarget = 'Ptarget = Pphone * rotation * scale + translationMm';
    info.targetToPrint = 'identity';
    if strcmp(frame, 'capmakerprintmm')
        pointsPrint = pointsTarget;
        return;
    end
    if strcmp(frame, 'capmakerprecropworldmm')
        [Ralign, tPrint] = readPreCropToPrintTransform(skin.meta);
        pointsPrint = pointsTarget * Ralign' + tPrint;
        info.targetToPrint = 'Pprint = PpreCrop * meta.align.R'' + meta.print.translation';
        return;
    end
    if strcmp(frame, 'capmakerpostcropworldmm')
        tPrint = readPrintTranslation(skin.meta);
        pointsPrint = pointsTarget + tPrint;
        info.targetToPrint = 'Pprint = PpostCrop + meta.print.translation';
        return;
    end
    error('acsVisualizeCapOnPhoneScan:UnsupportedFrame', ...
        'Unsupported registration target frame: %s', registration.targetCoordinateFrame);
end

function [Ralign, tPrint] = readPreCropToPrintTransform(meta)
    if ~isstruct(meta) || ~isfield(meta, 'align') || ...
            ~isfield(meta.align, 'R') || isempty(meta.align.R)
        error('acsVisualizeCapOnPhoneScan:MissingAlignTransform', ...
            'Skin cache metadata lacks meta.align.R.');
    end
    Ralign = double(meta.align.R);
    tPrint = readPrintTranslation(meta);
end

function tPrint = readPrintTranslation(meta)
    if ~isstruct(meta) || ~isfield(meta, 'print') || ...
            ~isfield(meta.print, 'T_world2print') || isempty(meta.print.T_world2print)
        error('acsVisualizeCapOnPhoneScan:MissingPrintTransform', ...
            'Skin cache metadata lacks meta.print.T_world2print.');
    end
    T = double(meta.print.T_world2print);
    tPrint = T(1:3, 4)';
end

function [scanDraw, capDraw, skinDraw] = prepareDisplayMeshes(scan, scanPrintMm, ...
        cap, skin, opts)
    [Vscan, Fscan, rgb] = decimateFacesForDisplay(scanPrintMm, scan.faces, ...
        scan.rgb, opts.displayMaxFaces);
    scanDraw = struct('vertices', Vscan, 'faces', Fscan, 'rgb', rgb);
    capDraw = struct('vertices', double(cap.TR.Points), ...
        'faces', double(cap.TR.ConnectivityList));
    skinDraw = struct('vertices', zeros(0, 3), 'faces', zeros(0, 3));
    if opts.showSkinWire && ~isempty(skin.TRskin)
        skinDraw.vertices = double(skin.TRskin.Points);
        skinDraw.faces = double(skin.TRskin.ConnectivityList);
    end
end

function [V2, F2, rgb2] = decimateFacesForDisplay(V, F, rgb, maxFaces)
    V = double(V);
    F = double(F);
    rgb2 = rgb;
    if isempty(F) || size(F, 1) <= maxFaces
        V2 = V;
        F2 = F;
        if isempty(rgb2) || size(rgb2, 1) ~= size(V2, 1)
            rgb2 = [];
        end
        return;
    end
    keepFaces = unique(round(linspace(1, size(F, 1), maxFaces)));
    Fkeep = F(keepFaces, :);
    used = unique(Fkeep(:));
    map = zeros(size(V, 1), 1);
    map(used) = 1:numel(used);
    V2 = V(used, :);
    F2 = map(Fkeep);
    if ~isempty(rgb) && size(rgb, 1) == size(V, 1)
        rgb2 = rgb(used, :);
    else
        rgb2 = [];
    end
end

function fig = makeFigure(scanDraw, capDraw, skinDraw, transformInfo, opts, visible)
    fig = figure('Name', 'PLA cap on colored phone scan', ...
        'NumberTitle', 'off', 'Color', 'w', 'Visible', visible, ...
        'Position', [80 70 1500 880]);
    if strcmp(opts.layoutMode, 'single')
        ax = axes(fig, 'Position', [0.045 0.065 0.92 0.875]);
        hold(ax, 'on');
        drawScan(ax, scanDraw, opts);
        drawCap(ax, capDraw, opts);
        drawSkinWire(ax, skinDraw);
        title(ax, sprintf('PLA fit-check cap over cropped phone scan (%s)', ...
            transformInfo.registrationTargetFrame), ...
            'Interpreter', 'none', 'FontWeight', 'bold');
        view(ax, [38 24]);
        formatAxes(ax);
        rotate3d(fig, 'on');
        return;
    end

    tl = tiledlayout(fig, 2, 2, 'Padding', 'compact', 'TileSpacing', 'compact');

    viewSpecs = { ...
        'Oblique model-on-scan view', [38 24]; ...
        'Dorsal print-frame footprint', [0 90]; ...
        'Rostral/caudal profile', [0 0]; ...
        'Lateral profile', [90 0]};

    for i = 1:4
        ax = nexttile(tl, i);
        hold(ax, 'on');
        drawScan(ax, scanDraw, opts);
        drawCap(ax, capDraw, opts);
        drawSkinWire(ax, skinDraw);
        title(ax, viewSpecs{i, 1});
        view(ax, viewSpecs{i, 2});
        formatAxes(ax);
    end
    title(tl, sprintf('PLA fit-check cap over colored phone scan (%s)', ...
        transformInfo.registrationTargetFrame), ...
        'Interpreter', 'none', 'FontWeight', 'bold');
end

function drawScan(ax, scanDraw, opts)
    if isempty(scanDraw.faces) || isempty(scanDraw.vertices)
        return;
    end
    if ~isempty(scanDraw.rgb) && size(scanDraw.rgb, 1) == size(scanDraw.vertices, 1)
        patch(ax, 'Faces', scanDraw.faces, 'Vertices', scanDraw.vertices, ...
            'FaceVertexCData', scanDraw.rgb, 'FaceColor', 'interp', ...
            'FaceAlpha', opts.scanAlpha, 'EdgeColor', 'none', ...
            'FaceLighting', 'none');
    else
        patch(ax, 'Faces', scanDraw.faces, 'Vertices', scanDraw.vertices, ...
            'FaceColor', [0.74 0.74 0.72], 'FaceAlpha', opts.scanAlpha, ...
            'EdgeColor', 'none', 'FaceLighting', 'flat', ...
            'AmbientStrength', 0.85, 'DiffuseStrength', 0.25);
    end
end

function drawCap(ax, capDraw, opts)
    if isempty(capDraw.faces) || isempty(capDraw.vertices)
        return;
    end
    patch(ax, 'Faces', capDraw.faces, 'Vertices', capDraw.vertices, ...
        'FaceColor', opts.capColor, 'FaceAlpha', opts.capAlpha, ...
        'EdgeColor', 'none', 'FaceLighting', 'flat', ...
        'AmbientStrength', 0.90, 'DiffuseStrength', 0.28, ...
        'SpecularStrength', 0.04);
end

function drawSkinWire(ax, skinDraw)
    if isempty(skinDraw.faces) || isempty(skinDraw.vertices)
        return;
    end
    patch(ax, 'Faces', skinDraw.faces, 'Vertices', skinDraw.vertices, ...
        'FaceColor', 'none', 'EdgeColor', [0 0 0], ...
        'EdgeAlpha', 0.10, 'LineWidth', 0.25);
end

function formatAxes(ax)
    axis(ax, 'equal');
    axis(ax, 'tight');
    axis(ax, 'vis3d');
    grid(ax, 'on');
    xlabel(ax, 'X print mm');
    ylabel(ax, 'Y print mm');
    zlabel(ax, 'Z print mm');
    camlight(ax, 'headlight');
    lighting(ax, 'flat');
    set(ax, 'Box', 'on', 'Projection', 'perspective');
end

function fileName = defaultOutputFile(scan, cap, opts)
    folder = '';
    if isfield(cap.info, 'file') && ~isempty(cap.info.file)
        folder = fileparts(cap.info.file);
    elseif isfield(scan.info, 'file') && ~isempty(scan.info.file)
        folder = fileparts(scan.info.file);
    end
    if isempty(folder)
        folder = pwd;
    end
    scanStem = 'phoneScan';
    if isfield(scan.info, 'file') && ~isempty(scan.info.file)
        scanStem = stripMatExtension(getFileName(scan.info.file));
    end
    fileName = fullfile(folder, sprintf('%s_%s.png', scanStem, opts.outputTag));
end

function exportQcFigure(fig, fileName)
    try
        exportgraphics(fig, fileName, 'Resolution', 220);
    catch
        saveas(fig, fileName);
    end
end

function scan = readAsciiPlyMesh(fileName)
    fid = fopen(fileName, 'r');
    if fid == -1
        error('acsVisualizeCapOnPhoneScan:CannotOpenPly', ...
            'Could not open PLY file: %s', fileName);
    end
    cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>

    line = fgetl(fid);
    if ~ischar(line) || ~strcmp(strtrim(line), 'ply')
        error('acsVisualizeCapOnPhoneScan:BadPly', ...
            'File does not begin with a PLY header: %s', fileName);
    end
    formatLine = '';
    nVertex = 0;
    nFace = 0;
    vertexProps = {};
    currentElement = '';
    while true
        line = fgetl(fid);
        if ~ischar(line)
            error('acsVisualizeCapOnPhoneScan:MissingPlyHeaderEnd', ...
                'PLY file ended before end_header.');
        end
        clean = strtrim(line);
        tokens = strsplit(clean);
        if isempty(tokens)
            continue;
        end
        switch lower(tokens{1})
            case 'format'
                formatLine = lower(clean);
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
    if isempty(formatLine) || ~contains(formatLine, 'ascii')
        error('acsVisualizeCapOnPhoneScan:UnsupportedPlyFormat', ...
            'This utility currently reads ASCII PLY files only.');
    end

    propCount = numel(vertexProps);
    Vraw = zeros(nVertex, propCount);
    for i = 1:nVertex
        line = fgetl(fid);
        vals = sscanf(line, '%f');
        if numel(vals) < propCount
            error('acsVisualizeCapOnPhoneScan:BadVertexLine', ...
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
    rgb = propertyColumns(Vraw, vertexProps, {'red', 'green', 'blue'}, false);
    if ~isempty(rgb)
        rgb = max(0, min(255, double(rgb))) ./ 255;
    end

    scan = struct();
    scan.vertices = double(vertices);
    scan.faces = double(faces);
    scan.rgb = double(rgb);
    scan.info = struct('file', fileName, 'inputType', 'ply', ...
        'nVertices', size(vertices, 1), 'nFaces', size(faces, 1));
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
                error('acsVisualizeCapOnPhoneScan:MissingPlyProperty', ...
                    'PLY vertex property "%s" was not found.', names{i});
            end
            return;
        end
        rows(i) = row;
    end
    values = Vraw(:, rows);
end

function TR = ensureTriangulation(value)
    if isempty(value)
        TR = [];
    elseif isa(value, 'triangulation')
        TR = value;
    elseif isstruct(value) && isfield(value, 'ConnectivityList') && ...
            isfield(value, 'Points')
        TR = triangulation(double(value.ConnectivityList), double(value.Points));
    elseif isstruct(value) && isfield(value, 'faces') && isfield(value, 'vertices')
        TR = triangulation(double(value.faces), double(value.vertices));
    else
        TR = [];
    end
end

function S = firstStruct(raw)
    preferred = {'out', 'outForSave', 'outSaved', 'phoneObject', ...
        'phoneFiducials', 'modelFiducials'};
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
    error('acsVisualizeCapOnPhoneScan:NoStruct', ...
        'MAT file does not contain a readable struct.');
end

function value = getOptionalField(S, fieldName, defaultValue)
    if nargin < 3
        defaultValue = [];
    end
    if isstruct(S) && isfield(S, fieldName) && ~isempty(S.(fieldName))
        value = S.(fieldName);
    else
        value = defaultValue;
    end
end

function frame = normalizeFrame(frame)
    frame = lower(regexprep(strtrim(char(frame)), '[\s_\-]+', ''));
end

function out = rmfieldIfPresent(S, fields)
    out = S;
    if ~isstruct(out)
        return;
    end
    if ischar(fields) || isstring(fields)
        fields = {char(fields)};
    end
    for i = 1:numel(fields)
        if isfield(out, fields{i})
            out = rmfield(out, fields{i});
        end
    end
end

function name = getFileName(fileName)
    [~, stem, ext] = fileparts(fileName);
    name = [stem ext];
end

function stem = stripMatExtension(fileName)
    [~, stem] = fileparts(fileName);
end

function name = safeName(name)
    name = regexprep(strtrim(name), '[^\w\-]+', '_');
    if isempty(name)
        name = 'capOnPhoneScan';
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
