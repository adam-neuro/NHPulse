function out = acsInspectCapMakerManufacturingGeometry(manufacturingIn, varargin)
% ACSINSPECTCAPMAKERMANUFACTURINGGEOMETRY Interactive cap/scalp holder QC.
%
% out = acsInspectCapMakerManufacturingGeometry(manufacturing)
% overlays the manufacturing scalp mesh, final/pre-fuse cap mesh, electrode
% holders, and holder bore axes in one large orbitable 3-D view. The input can
% be an in-memory acsBuildCapMakerManufacturingStl output, a saved
% *_manufacturing_report.mat, or a saved *_manufacturing_meshes.mat.
%
% Name-value options:
%   skinAlpha               : initial scalp opacity [0.28]
%   capAlpha                : initial cap/rail opacity [0.42]
%   plaAlpha                : initial PLA support opacity [0]
%   holderAlpha             : initial holder opacity [0.92]
%   vectorLengthMm          : bore vector display length [14]
%   smoothNormalRadiusMm    : local scalp normal averaging radius [6]
%   warnNormalAngleDeg      : warn if bore differs from smooth normal [25]
%   badNormalAngleDeg       : severe if bore differs from smooth normal [45]
%   undersideAxisZThreshold : severe if bore Z component is below this [0.25]
%   displayMaxFaces         : max faces per large displayed mesh [120000]
%   showExclusions          : draw exclusion overlays initially [true]
%   showLabels              : show electrode names [true]
%   showFigures             : show interactive figure [true]
%   saveFigures             : save PNG snapshot [false]
%   outputFile              : PNG path when saveFigures=true ['']
%   verbose                 : print diagnostic table [true]

    if nargin < 1 || isempty(manufacturingIn)
        error('acsInspectCapMakerManufacturingGeometry:MissingInput', ...
            'Provide a manufacturing output/report/mesh MAT file.');
    end

    opts = parseInputs(varargin{:});
    addLocalDependencies();

    data = readManufacturingInput(manufacturingIn);
    data = completeManufacturingMeshes(data, opts);
    diagnostics = holderDiagnostics(data, opts);

    fig = [];
    qcFile = '';
    if opts.showFigures || opts.saveFigures
        visible = 'off';
        if opts.showFigures
            visible = 'on';
        end
        fig = makeFigure(data, diagnostics, opts, visible);
        if opts.saveFigures
            qcFile = opts.outputFile;
            if isempty(qcFile)
                qcFile = defaultOutputFile(data);
            end
            ensureDir(fileparts(qcFile));
            exportgraphics(fig, qcFile, 'Resolution', 180);
        end
        if ~opts.showFigures && isgraphics(fig)
            close(fig);
            fig = [];
        end
    end

    out = struct();
    out.createdOn = char(datetime('now'));
    out.type = 'capMakerManufacturingGeometryInspection';
    out.source = data.source;
    out.names = data.names;
    out.diagnostics = diagnostics;
    out.qcFigure = qcFile;
    if isgraphics(fig)
        out.figure = fig;
    end

    if opts.verbose
        printSummary(out);
    end
end

function opts = parseInputs(varargin)
    p = inputParser;
    p.FunctionName = 'acsInspectCapMakerManufacturingGeometry';
    addParameter(p, 'skinAlpha', 0.28, @isUnitScalar);
    addParameter(p, 'capAlpha', 0.42, @isUnitScalar);
    addParameter(p, 'plaAlpha', 0, @isUnitScalar);
    addParameter(p, 'holderAlpha', 0.92, @isUnitScalar);
    addParameter(p, 'vectorLengthMm', 14, @isPositiveScalar);
    addParameter(p, 'smoothNormalRadiusMm', 6, @isPositiveScalar);
    addParameter(p, 'warnNormalAngleDeg', 25, @isPositiveScalar);
    addParameter(p, 'badNormalAngleDeg', 45, @isPositiveScalar);
    addParameter(p, 'undersideAxisZThreshold', 0.25, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x));
    addParameter(p, 'displayMaxFaces', 120000, @isPositiveScalar);
    addParameter(p, 'showExclusions', true, @isBoolLike);
    addParameter(p, 'showLabels', true, @isBoolLike);
    addParameter(p, 'showFigures', true, @isBoolLike);
    addParameter(p, 'saveFigures', false, @isBoolLike);
    addParameter(p, 'outputFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'verbose', true, @isBoolLike);
    parse(p, varargin{:});

    opts = p.Results;
    opts.skinAlpha = double(opts.skinAlpha);
    opts.capAlpha = double(opts.capAlpha);
    opts.plaAlpha = double(opts.plaAlpha);
    opts.holderAlpha = double(opts.holderAlpha);
    opts.vectorLengthMm = double(opts.vectorLengthMm);
    opts.smoothNormalRadiusMm = double(opts.smoothNormalRadiusMm);
    opts.warnNormalAngleDeg = double(opts.warnNormalAngleDeg);
    opts.badNormalAngleDeg = double(opts.badNormalAngleDeg);
    opts.undersideAxisZThreshold = double(opts.undersideAxisZThreshold);
    opts.displayMaxFaces = round(double(opts.displayMaxFaces));
    opts.showExclusions = logical(opts.showExclusions);
    opts.showLabels = logical(opts.showLabels);
    opts.showFigures = logical(opts.showFigures);
    opts.saveFigures = logical(opts.saveFigures);
    opts.outputFile = expandUserPath(char(opts.outputFile));
    opts.verbose = logical(opts.verbose);
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

function addLocalDependencies()
    repoRoot = fileparts(fileparts(mfilename('fullpath')));
    addpath(fullfile(repoRoot, 'acsUtilities'));
    addpath(fullfile(repoRoot, 'capMaker', 'geometry'));
    addpath(fullfile(repoRoot, 'capMaker', 'core'));
end

function data = readManufacturingInput(value)
    data = emptyData();
    if isstruct(value)
        data.report = value;
        data.source.file = '';
        data.source.type = 'struct';
        data = absorbReport(data, value);
        return;
    end

    fileName = expandUserPath(char(value));
    if exist(fileName, 'file') ~= 2
        error('acsInspectCapMakerManufacturingGeometry:MissingFile', ...
            'File not found: %s', fileName);
    end
    [~, ~, ext] = fileparts(fileName);
    switch lower(ext)
        case '.mat'
            S = load(fileName);
            data.source.file = fileName;
            data.source.type = 'mat';
            if isfield(S, 'meshes') && isstruct(S.meshes)
                data.meshes = normalizeMeshes(S.meshes);
                data.source.type = 'meshMat';
            end
            report = firstReportStruct(S);
            if ~isempty(report)
                data.report = report;
                data = absorbReport(data, report);
            end
        case '.stl'
            data.meshes.cap = readStlTriangulation(fileName);
            data.source.file = fileName;
            data.source.type = 'stl';
        otherwise
            error('acsInspectCapMakerManufacturingGeometry:BadInputFile', ...
                'Input file must be a MAT report/mesh file or STL.');
    end
end

function data = emptyData()
    data = struct();
    data.source = struct('file', '', 'type', '');
    data.report = struct();
    data.meshes = struct();
    data.names = {};
    data.roles = {};
    data.layoutCoordinatesMm = zeros(0, 3);
    data.holderInfo = struct([]);
    data.earExclusions = struct();
    data.implantExclusions = struct([]);
    data.strap = struct();
    data.options = struct();
end

function report = firstReportStruct(S)
    report = [];
    preferred = {'out', 'outToSave', 'outSaved', 'manufacturing', ...
        'manufacturingPreflight'};
    for i = 1:numel(preferred)
        if isfield(S, preferred{i}) && isstruct(S.(preferred{i}))
            report = S.(preferred{i});
            return;
        end
    end
    fields = fieldnames(S);
    for i = 1:numel(fields)
        value = S.(fields{i});
        if isstruct(value) && (isfield(value, 'manufacturingTag') || ...
                isfield(value, 'holderInfo') || isfield(value, 'tpeStlFile'))
            report = value;
            return;
        end
    end
end

function data = absorbReport(data, report)
    if isfield(report, 'meshes') && isstruct(report.meshes)
        data.meshes = mergeStructs(data.meshes, normalizeMeshes(report.meshes));
    end
    if isfield(report, 'names')
        data.names = cellstr(report.names(:));
    end
    if isfield(report, 'siteRoles')
        data.roles = cellstr(report.siteRoles(:));
    end
    if isfield(report, 'layoutCoordinatesMm')
        data.layoutCoordinatesMm = double(report.layoutCoordinatesMm);
    end
    if isfield(report, 'holderInfo')
        data.holderInfo = report.holderInfo(:);
    end
    if isfield(report, 'earExclusions') && isstruct(report.earExclusions)
        data.earExclusions = report.earExclusions;
    end
    if isfield(report, 'implantExclusions') && isstruct(report.implantExclusions)
        data.implantExclusions = report.implantExclusions;
    end
    if isfield(report, 'strap') && isstruct(report.strap)
        data.strap = report.strap;
    end
    if isfield(report, 'options') && isstruct(report.options)
        data.options = report.options;
    end
end

function meshes = normalizeMeshes(meshesIn)
    meshes = struct();
    names = fieldnames(meshesIn);
    for i = 1:numel(names)
        TR = ensureTriangulation(meshesIn.(names{i}));
        if isempty(TR)
            continue;
        end
        key = normalizeMeshKey(names{i});
        meshes.(key) = TR;
    end
end

function key = normalizeMeshKey(name)
    key = lower(regexprep(char(name), '^TR', ''));
    switch key
        case {'skin'}
            key = 'skin';
        case {'railsource'}
            key = 'railSource';
        case {'holders', 'holder'}
            key = 'holders';
        case {'rails', 'rail'}
            key = 'rails';
        case {'tpe', 'tperaw', 'fit', 'final'}
            key = 'cap';
        case {'pla'}
            key = 'pla';
        otherwise
            key = matlab.lang.makeValidName(key);
    end
end

function data = completeManufacturingMeshes(data, opts)
    report = data.report;
    meshFile = getOptionalField(report, 'meshMat', '');
    if isempty(meshFile) && isfield(data.options, 'meshMat')
        meshFile = data.options.meshMat;
    end
    if ~isempty(meshFile) && exist(char(meshFile), 'file') == 2
        S = load(char(meshFile));
        if isfield(S, 'meshes') && isstruct(S.meshes)
            data.meshes = mergeStructs(data.meshes, normalizeMeshes(S.meshes));
        end
    end

    if ~isfield(data.meshes, 'skin') || isempty(data.meshes.skin)
        skinFile = inferSkinCacheFile(report, data.options);
        if ~isempty(skinFile) && exist(skinFile, 'file') == 2
            S = load(skinFile, 'TRskin');
            if isfield(S, 'TRskin')
                data.meshes.skin = ensureTriangulation(S.TRskin);
            end
        end
    end

    if ~isfield(data.meshes, 'cap') || isempty(data.meshes.cap)
        capFile = getOptionalField(report, 'tpeStlFile', '');
        if ~isempty(capFile) && exist(char(capFile), 'file') == 2
            data.meshes.cap = readStlTriangulation(char(capFile));
        elseif isfield(data.meshes, 'rails')
            data.meshes.cap = data.meshes.rails;
        end
    end

    if (~isfield(data.meshes, 'holders') || isempty(data.meshes.holders)) && ...
            isfield(data.meshes, 'skin') && ~isempty(data.layoutCoordinatesMm)
        data.meshes.holders = reconstructHolders(data.meshes.skin, ...
            data.layoutCoordinatesMm, data.options);
    end

    if isempty(data.holderInfo) && isfield(data.meshes, 'skin') && ...
            ~isempty(data.layoutCoordinatesMm)
        [~, ~, ~, data.holderInfo] = placeElectrodeArrayOnSurface( ...
            data.meshes.skin, holderTemplateFromOptions(data.options), ...
            data.layoutCoordinatesMm, holderEmbedFromOptions(data.options), ...
            'NormalMode', holderNormalModeFromOptions(data.options), ...
            'SmoothNormalRadiusMm', holderSmoothRadiusFromOptions(data.options), ...
            'NormalDeviationThresholdDeg', ...
                holderNormalThresholdFromOptions(data.options));
    end

    if isempty(data.names) && ~isempty(data.holderInfo)
        data.names = arrayfun(@(i) sprintf('site%d', i), ...
            (1:numel(data.holderInfo)).', 'UniformOutput', false);
    end
    data = decimateDisplayMeshes(data, opts);
end

function skinFile = inferSkinCacheFile(report, options)
    skinFile = '';
    if isfield(report, 'manufacturingSurface') && ...
            isstruct(report.manufacturingSurface) && ...
            isfield(report.manufacturingSurface, 'cacheFile')
        skinFile = report.manufacturingSurface.cacheFile;
    end
    if isempty(skinFile) && isfield(options, 'manufacturingSurfaceCacheFile')
        skinFile = options.manufacturingSurfaceCacheFile;
    end
    if isempty(skinFile) && isfield(options, 'skinSourceCacheFile')
        skinFile = options.skinSourceCacheFile;
    end
    skinFile = char(skinFile);
end

function TRholders = reconstructHolders(TRskin, targetsMm, options)
    [TRholders, ~, ~, ~] = placeElectrodeArrayOnSurface( ...
        TRskin, holderTemplateFromOptions(options), ...
        double(targetsMm), holderEmbedFromOptions(options), ...
        'NormalMode', holderNormalModeFromOptions(options), ...
        'SmoothNormalRadiusMm', holderSmoothRadiusFromOptions(options), ...
        'NormalDeviationThresholdDeg', holderNormalThresholdFromOptions(options));
end

function holderTR = holderTemplateFromOptions(options)
    insideDia = getNumericOption(options, 'holderInsideDiaMm', 4);
    outsideDia = getNumericOption(options, 'holderOutsideDiaMm', 12);
    heightMm = getNumericOption(options, 'holderHeightMm', 7);
    holderTR = makeElectrodeHolderHex(insideDia, outsideDia, heightMm);
    holderTR = unifyOutwardNormalsRobust(holderTR);
end

function embed = holderEmbedFromOptions(options)
    embed = getNumericOption(options, 'holderEmbedMm', 0.3);
end

function mode = holderNormalModeFromOptions(options)
    mode = 'vertex';
    if isstruct(options) && isfield(options, 'holderNormalMode') && ...
            ~isempty(options.holderNormalMode)
        mode = char(options.holderNormalMode);
    end
end

function radiusMm = holderSmoothRadiusFromOptions(options)
    radiusMm = getNumericOption(options, 'holderSmoothNormalRadiusMm', 6);
end

function thresholdDeg = holderNormalThresholdFromOptions(options)
    thresholdDeg = getNumericOption(options, ...
        'holderNormalDeviationThresholdDeg', 25);
end

function value = getNumericOption(S, fieldName, defaultValue)
    value = defaultValue;
    if isstruct(S) && isfield(S, fieldName) && ~isempty(S.(fieldName))
        value = double(S.(fieldName));
    end
end

function data = decimateDisplayMeshes(data, opts)
    fields = fieldnames(data.meshes);
    for i = 1:numel(fields)
        displayField = [fields{i} 'Display'];
        data.meshes.(displayField) = decimateTri( ...
            data.meshes.(fields{i}), opts.displayMaxFaces);
    end
end

function diagnostics = holderDiagnostics(data, opts)
    n = numel(data.holderInfo);
    names = data.names(:);
    if numel(names) < n
        names(end + 1:n, 1) = arrayfun(@(i) sprintf('site%d', i), ...
            (numel(names) + 1:n).', 'UniformOutput', false);
    end
    surfacePoint = nan(n, 3);
    axisVec = nan(n, 3);
    surfaceNormal = nan(n, 3);
    rawToSmoothNormalDeg = nan(n, 1);
    minZ = nan(n, 1);
    maxZ = nan(n, 1);
    targetDistance = nan(n, 1);
    for i = 1:n
        h = data.holderInfo(i);
        surfacePoint(i, :) = getVectorField(h, 'surfacePointMm');
        axisVec(i, :) = unitVector(getVectorField(h, 'holeAxis'));
        surfaceNormal(i, :) = unitVector(getVectorField(h, 'surfaceNormal'));
        rawToSmoothNormalDeg(i) = getScalarField(h, ...
            'rawToSmoothNormalAngleDeg');
        minZ(i) = getScalarField(h, 'minZMm');
        maxZ(i) = getScalarField(h, 'maxZMm');
        target = getVectorField(h, 'targetMm');
        if all(isfinite(target)) && all(isfinite(surfacePoint(i, :)))
            targetDistance(i) = norm(target - surfacePoint(i, :));
        end
    end

    smoothNormal = nan(n, 3);
    smoothAngleDeg = nan(n, 1);
    if isfield(data.meshes, 'skin') && ~isempty(data.meshes.skin) && n > 0
        smoothNormal = localSmoothNormals(data.meshes.skin, surfacePoint, ...
            opts.smoothNormalRadiusMm);
        smoothAngleDeg = vectorAngleDeg(axisVec, smoothNormal);
    end
    missingRough = ~isfinite(rawToSmoothNormalDeg);
    if any(missingRough)
        rawToSmoothNormalDeg(missingRough) = vectorAngleDeg( ...
            surfaceNormal(missingRough, :), smoothNormal(missingRough, :));
    end
    normalAngleDeg = vectorAngleDeg(axisVec, surfaceNormal);
    axisZ = axisVec(:, 3);
    zBed = getNumericOption(data.options, 'zBedMm', 0);
    bedClearance = minZ - zBed;
    holderMinBedClearance = getNumericOption(data.options, ...
        'holderMinBedClearanceMm', 1);
    lowBed = bedClearance < holderMinBedClearance;
    badTilt = smoothAngleDeg >= opts.badNormalAngleDeg | ...
        rawToSmoothNormalDeg >= opts.badNormalAngleDeg;
    warnTilt = (smoothAngleDeg >= opts.warnNormalAngleDeg | ...
        rawToSmoothNormalDeg >= opts.warnNormalAngleDeg) & ~badTilt;
    underside = axisZ < opts.undersideAxisZThreshold;
    severity = zeros(n, 1);
    severity(warnTilt | lowBed) = 1;
    severity(badTilt | underside) = 2;

    tableOut = table(names(1:n), surfacePoint(:, 1), surfacePoint(:, 2), ...
        surfacePoint(:, 3), axisZ, smoothAngleDeg, normalAngleDeg, ...
        rawToSmoothNormalDeg, bedClearance, targetDistance, severity, ...
        'VariableNames', {'name', 'surfaceX', 'surfaceY', 'surfaceZ', ...
        'axisZ', 'axisToSmoothNormalDeg', 'axisToVertexNormalDeg', ...
        'rawToSmoothNormalAngleDeg', 'bedClearanceMm', ...
        'targetSnapDistanceMm', 'severity'});

    diagnostics = struct();
    diagnostics.table = tableOut;
    diagnostics.names = names(1:n);
    diagnostics.surfacePointMm = surfacePoint;
    diagnostics.axis = axisVec;
    diagnostics.surfaceNormal = surfaceNormal;
    diagnostics.smoothNormal = smoothNormal;
    diagnostics.axisToSmoothNormalDeg = smoothAngleDeg;
    diagnostics.axisToVertexNormalDeg = normalAngleDeg;
    diagnostics.rawToSmoothNormalAngleDeg = rawToSmoothNormalDeg;
    diagnostics.axisZ = axisZ;
    diagnostics.bedClearanceMm = bedClearance;
    diagnostics.targetSnapDistanceMm = targetDistance;
    diagnostics.severity = severity;
    diagnostics.lowBed = lowBed;
    diagnostics.warnTilt = warnTilt;
    diagnostics.badTilt = badTilt;
    diagnostics.underside = underside;
end

function value = getVectorField(S, fieldName)
    value = [NaN NaN NaN];
    if isstruct(S) && isfield(S, fieldName) && numel(S.(fieldName)) == 3
        raw = S.(fieldName);
        value = double(raw(:)).';
    end
end

function value = getScalarField(S, fieldName)
    value = NaN;
    if isstruct(S) && isfield(S, fieldName) && isscalar(S.(fieldName))
        value = double(S.(fieldName));
    end
end

function Nlocal = localSmoothNormals(TR, points, radiusMm)
    V = double(TR.Points);
    Nv = vertexNormal(TR);
    Nv = bsxfun(@rdivide, Nv, max(sqrt(sum(Nv .^ 2, 2)), eps));
    Nlocal = nan(size(points));
    r2 = radiusMm ^ 2;
    for i = 1:size(points, 1)
        if ~all(isfinite(points(i, :)))
            continue;
        end
        d2 = sum((V - points(i, :)) .^ 2, 2);
        use = d2 <= r2;
        if nnz(use) < 6
            [~, order] = sort(d2, 'ascend');
            use(order(1:min(12, numel(order)))) = true;
        end
        n = mean(Nv(use, :), 1);
        if norm(n) > eps
            Nlocal(i, :) = n ./ norm(n);
        end
    end
end

function angleDeg = vectorAngleDeg(A, B)
    angleDeg = nan(size(A, 1), 1);
    for i = 1:size(A, 1)
        a = unitVector(A(i, :));
        b = unitVector(B(i, :));
        if all(isfinite(a)) && all(isfinite(b))
            c = max(-1, min(1, dot(a, b)));
            angleDeg(i) = acosd(c);
        end
    end
end

function v = unitVector(v)
    v = double(v(:)).';
    if numel(v) ~= 3 || any(~isfinite(v)) || norm(v) <= eps
        v = [NaN NaN NaN];
    else
        v = v ./ norm(v);
    end
end

function fig = makeFigure(data, diagnostics, opts, visible)
    fig = figure('Name', 'CapMaker manufacturing geometry inspector', ...
        'NumberTitle', 'off', 'Color', 'w', 'Visible', visible, ...
        'Units', 'normalized', 'Position', [0.08 0.08 0.82 0.82]);
    ax = axes('Parent', fig, 'Units', 'normalized', ...
        'Position', [0.05 0.12 0.78 0.82]);
    hold(ax, 'on');

    patches = struct();
    if isfield(data.meshes, 'skinDisplay')
        patches.skin = drawTri(ax, data.meshes.skinDisplay, ...
            [0.72 0.74 0.76], opts.skinAlpha, [0.45 0.45 0.45], 0.08);
    end
    if isfield(data.meshes, 'plaDisplay')
        patches.pla = drawTri(ax, data.meshes.plaDisplay, ...
            [0.78 0.78 0.78], opts.plaAlpha, 'none', 0);
    end
    if isfield(data.meshes, 'capDisplay')
        patches.cap = drawTri(ax, data.meshes.capDisplay, ...
            [0.05 0.25 0.85], opts.capAlpha, 'none', 0);
    elseif isfield(data.meshes, 'railsDisplay')
        patches.cap = drawTri(ax, data.meshes.railsDisplay, ...
            [0.05 0.25 0.85], opts.capAlpha, 'none', 0);
    end
    if isfield(data.meshes, 'holdersDisplay')
        patches.holders = drawTri(ax, data.meshes.holdersDisplay, ...
            [1.00 0.78 0.05], opts.holderAlpha, [0.12 0.08 0.00], 0.12);
    end
    overlays = struct();
    overlays.ears = drawEarExclusions(ax, data.earExclusions, opts);
    overlays.implants = drawImplantExclusions(ax, data.implantExclusions, opts);
    overlays.strap = drawStrapContext(ax, data.strap, opts);

    drawHolderVectors(ax, diagnostics, opts);
    drawHolderCenters(ax, diagnostics);
    if opts.showLabels
        drawLabels(ax, diagnostics);
    end

    title(ax, 'CapMaker manufacturing geometry inspector', 'Interpreter', 'none');
    xlabel(ax, 'X print mm');
    ylabel(ax, 'Y print mm');
    zlabel(ax, 'Z print mm');
    axis(ax, 'equal');
    axis(ax, 'vis3d');
    grid(ax, 'on');
    view(ax, 3);
    rotate3d(fig, 'on');
    camlight(ax, 'headlight');
    lighting(ax, 'flat');
    set(ax, 'Clipping', 'off');

    addAlphaSlider(fig, 0.86, 0.78, 'scalp', opts.skinAlpha, patches, 'skin');
    addAlphaSlider(fig, 0.86, 0.68, 'cap', opts.capAlpha, patches, 'cap');
    addAlphaSlider(fig, 0.86, 0.58, 'PLA support', opts.plaAlpha, patches, 'pla');
    addAlphaSlider(fig, 0.86, 0.48, 'holders', opts.holderAlpha, patches, 'holders');
    addVisibilityCheckbox(fig, 0.86, 0.40, 'ear zones', ...
        opts.showExclusions, overlays, 'ears');
    addVisibilityCheckbox(fig, 0.86, 0.36, 'implant zones', ...
        opts.showExclusions, overlays, 'implants');
    addVisibilityCheckbox(fig, 0.86, 0.32, 'strap anchors', ...
        opts.showExclusions, overlays, 'strap');
    addInfoText(fig, diagnostics);
end

function h = drawTri(ax, TR, colorValue, alphaValue, edgeColor, edgeAlpha)
    h = [];
    if isempty(TR) || isempty(TR.Points) || isempty(TR.ConnectivityList)
        return;
    end
    h = patch(ax, 'Faces', TR.ConnectivityList, 'Vertices', TR.Points, ...
        'FaceColor', colorValue, 'FaceAlpha', alphaValue, ...
        'EdgeColor', edgeColor, 'FaceLighting', 'flat', ...
        'SpecularStrength', 0.08, 'AmbientStrength', 0.55);
    if isnumeric(edgeColor) || ischar(edgeColor)
        try
            set(h, 'EdgeAlpha', edgeAlpha);
        catch
        end
    end
end

function drawHolderVectors(ax, diagnostics, opts)
    P = diagnostics.surfacePointMm;
    A = diagnostics.axis;
    sev = diagnostics.severity;
    colors = [0.05 0.65 0.18; 1.00 0.55 0.00; 0.90 0.05 0.05];
    for level = 0:2
        use = sev == level & all(isfinite(P), 2) & all(isfinite(A), 2);
        if ~any(use)
            continue;
        end
        c = colors(level + 1, :);
        quiver3(ax, P(use, 1), P(use, 2), P(use, 3), ...
            opts.vectorLengthMm * A(use, 1), ...
            opts.vectorLengthMm * A(use, 2), ...
            opts.vectorLengthMm * A(use, 3), ...
            0, 'Color', c, 'LineWidth', 2.4, 'MaxHeadSize', 0.7);
    end
end

function group = drawEarExclusions(ax, earExclusions, opts)
    group = hggroup('Parent', ax, 'Visible', onOff(opts.showExclusions));
    if isempty(earExclusions) || ~isstruct(earExclusions)
        return;
    end
    if isfield(earExclusions, 'exclusionCenters') && ...
            isfield(earExclusions, 'exclusionRadiusMM') && ...
            ~isempty(earExclusions.exclusionCenters)
        centers = double(earExclusions.exclusionCenters);
        radii = double(earExclusions.exclusionRadiusMM(:));
        if isscalar(radii) && size(centers, 1) > 1
            radii = repmat(radii, size(centers, 1), 1);
        end
        colors = [0.88 0.00 0.85; 0.00 0.55 0.95; 0.80 0.35 0.00];
        [sx, sy, sz] = sphere(32);
        n = min(size(centers, 1), numel(radii));
        for i = 1:n
            if any(~isfinite(centers(i, :))) || ~isfinite(radii(i)) || radii(i) <= 0
                continue;
            end
            color = colors(1 + mod(i - 1, size(colors, 1)), :);
            h = surf(ax, centers(i, 1) + radii(i) * sx, ...
                centers(i, 2) + radii(i) * sy, ...
                centers(i, 3) + radii(i) * sz, ...
                'FaceColor', color, ...
                'FaceAlpha', 0.14, ...
                'EdgeColor', color, ...
                'EdgeAlpha', 0.18);
            parentToGroup(h, group);
            h = scatter3(ax, centers(i, 1), centers(i, 2), centers(i, 3), ...
                80, color, 'filled', ...
                'MarkerEdgeColor', 'k', 'LineWidth', 0.8);
            parentToGroup(h, group);
        end
    end
    if isfield(earExclusions, 'paintedExclusionCoordinatesMm') && ...
            ~isempty(earExclusions.paintedExclusionCoordinatesMm)
        P = double(earExclusions.paintedExclusionCoordinatesMm);
        P = P(all(isfinite(P), 2), :);
        if ~isempty(P)
            h = scatter3(ax, P(:, 1), P(:, 2), P(:, 3), 24, ...
                [0.95 0.05 0.05], 'filled', ...
                'MarkerEdgeColor', [0.15 0 0], 'LineWidth', 0.4);
            parentToGroup(h, group);
        end
    end
end

function group = drawImplantExclusions(ax, implantExclusions, opts)
    group = hggroup('Parent', ax, 'Visible', onOff(opts.showExclusions));
    if isempty(implantExclusions) || ~isstruct(implantExclusions)
        return;
    end
    for i = 1:numel(implantExclusions)
        if isfield(implantExclusions(i), 'projectedCoordinatesMm') && ...
                ~isempty(implantExclusions(i).projectedCoordinatesMm)
            P = double(implantExclusions(i).projectedCoordinatesMm);
            P = P(all(isfinite(P), 2), :);
            if ~isempty(P)
                h = scatter3(ax, P(:, 1), P(:, 2), P(:, 3), 18, ...
                    [1.00 0.10 0.55], 'filled', ...
                    'MarkerEdgeColor', 'k', 'LineWidth', 0.3);
                parentToGroup(h, group);
            end
        end
        if isfield(implantExclusions(i), 'keepoutBoundaryMm') && ...
                ~isempty(implantExclusions(i).keepoutBoundaryMm)
            B = double(implantExclusions(i).keepoutBoundaryMm);
            B = B(all(isfinite(B), 2), :);
            if size(B, 1) >= 2
                if norm(B(1, :) - B(end, :)) > eps
                    B = [B; B(1, :)]; %#ok<AGROW>
                end
                h = plot3(ax, B(:, 1), B(:, 2), B(:, 3), ...
                    'Color', [0.85 0.00 0.40], ...
                    'LineWidth', 2.4);
                parentToGroup(h, group);
                label = char(getOptionalField(implantExclusions(i), ...
                    'name', 'implant'));
                center = mean(B, 1);
                if all(isfinite(center))
                    h = text(ax, center(1), center(2), center(3), label, ...
                        'Color', [0.60 0.00 0.30], ...
                        'FontWeight', 'bold', 'Interpreter', 'none', ...
                        'Parent', ax);
                    parentToGroup(h, group);
                end
            end
        end
    end
end

function group = drawStrapContext(ax, strap, opts)
    group = hggroup('Parent', ax, 'Visible', onOff(opts.showExclusions));
    if isempty(strap) || ~isstruct(strap) || ~isfield(strap, 'anchors') || ...
            isempty(strap.anchors)
        return;
    end
    A = double(strap.anchors);
    A = A(all(isfinite(A), 2), :);
    if isempty(A)
        return;
    end
    h = scatter3(ax, A(:, 1), A(:, 2), A(:, 3), 90, ...
        'm', 'filled', ...
        'MarkerEdgeColor', 'k', 'LineWidth', 0.8);
    parentToGroup(h, group);
    if isfield(strap, 'outDirs') && size(strap.outDirs, 1) == size(A, 1)
        D = double(strap.outDirs);
        h = quiver3(ax, A(:, 1), A(:, 2), A(:, 3), ...
            15 * D(:, 1), 15 * D(:, 2), 15 * D(:, 3), ...
            0, 'Color', 'm', 'LineWidth', 2);
        parentToGroup(h, group);
    end
end

function parentToGroup(h, group)
    if all(isgraphics(h)) && isgraphics(group)
        try
            set(h, 'Parent', group);
        catch
        end
    end
end

function drawHolderCenters(ax, diagnostics)
    P = diagnostics.surfacePointMm;
    sev = diagnostics.severity;
    markerColors = [0.05 0.65 0.18; 1.00 0.55 0.00; 0.90 0.05 0.05];
    for level = 0:2
        use = sev == level & all(isfinite(P), 2);
        if any(use)
            scatter3(ax, P(use, 1), P(use, 2), P(use, 3), 70, ...
                markerColors(level + 1, :), 'filled', ...
                'MarkerEdgeColor', 'k', 'LineWidth', 0.8);
        end
    end
end

function value = onOff(tf)
    if tf
        value = 'on';
    else
        value = 'off';
    end
end

function drawLabels(ax, diagnostics)
    P = diagnostics.surfacePointMm;
    names = diagnostics.names;
    for i = 1:size(P, 1)
        if all(isfinite(P(i, :)))
            text(ax, P(i, 1), P(i, 2), P(i, 3), [' ' names{i}], ...
                'FontSize', 8, 'Color', [0.05 0.05 0.05], ...
                'FontWeight', 'bold', 'Interpreter', 'none');
        end
    end
end

function addAlphaSlider(fig, x, y, labelText, value, patches, fieldName)
    uicontrol(fig, 'Style', 'text', 'Units', 'normalized', ...
        'Position', [x y + 0.035 0.10 0.025], ...
        'String', labelText, 'BackgroundColor', 'w', ...
        'HorizontalAlignment', 'left');
    slider = uicontrol(fig, 'Style', 'slider', 'Units', 'normalized', ...
        'Position', [x y 0.10 0.035], ...
        'Min', 0, 'Max', 1, 'Value', value);
    if isfield(patches, fieldName) && isgraphics(patches.(fieldName))
        set(slider, 'Callback', @(src, ~) set(patches.(fieldName), ...
            'FaceAlpha', get(src, 'Value')));
    else
        set(slider, 'Enable', 'off');
    end
end

function addVisibilityCheckbox(fig, x, y, labelText, value, overlays, fieldName)
    cb = uicontrol(fig, 'Style', 'checkbox', 'Units', 'normalized', ...
        'Position', [x y 0.12 0.035], ...
        'String', labelText, ...
        'BackgroundColor', 'w', ...
        'Value', double(value));
    if isfield(overlays, fieldName) && isgraphics(overlays.(fieldName))
        set(cb, 'Callback', @(src, ~) set(overlays.(fieldName), ...
            'Visible', onOff(get(src, 'Value') > 0)));
    else
        set(cb, 'Enable', 'off');
    end
end

function addInfoText(fig, diagnostics)
    T = diagnostics.table;
    nBad = nnz(T.severity == 2);
    nWarn = nnz(T.severity == 1);
    msg = sprintf(['green: OK\norange: rough/low\nred: low-axis/severe\n\n', ...
        'severe: %d\nwarning: %d\n\n', ...
        'Inspect table in output.diagnostics.table'], nBad, nWarn);
    uicontrol(fig, 'Style', 'text', 'Units', 'normalized', ...
        'Position', [0.85 0.05 0.13 0.22], ...
        'String', msg, 'BackgroundColor', 'w', ...
        'HorizontalAlignment', 'left');
end

function TRout = decimateTri(TRin, maxFaces)
    TRout = TRin;
    if isempty(TRin) || isempty(TRin.Points) || isempty(maxFaces)
        return;
    end
    nFaces = size(TRin.ConnectivityList, 1);
    if nFaces <= maxFaces
        return;
    end
    try
        [F, V] = reducepatch(TRin.ConnectivityList, TRin.Points, maxFaces);
        TRout = triangulation(double(F), double(V));
    catch
        TRout = TRin;
    end
end

function TR = ensureTriangulation(value)
    TR = [];
    if isempty(value)
        return;
    end
    if isa(value, 'triangulation')
        TR = triangulation(double(value.ConnectivityList), double(value.Points));
    elseif isstruct(value) && isfield(value, 'ConnectivityList') && ...
            isfield(value, 'Points')
        TR = triangulation(double(value.ConnectivityList), double(value.Points));
    elseif isstruct(value) && isfield(value, 'faces') && isfield(value, 'vertices')
        TR = triangulation(double(value.faces), double(value.vertices));
    elseif isstruct(value) && isfield(value, 'Faces') && isfield(value, 'Vertices')
        TR = triangulation(double(value.Faces), double(value.Vertices));
    end
end

function TR = readStlTriangulation(fileName)
    if exist('stlread', 'file') ~= 2
        error('acsInspectCapMakerManufacturingGeometry:MissingStlread', ...
            'stlread is required to read STL files: %s', fileName);
    end
    TR = [];
    try
        raw = stlread(fileName);
        TR = ensureTriangulation(raw);
    catch
    end
    if ~isempty(TR)
        return;
    end
    try
        [F, V] = stlread(fileName);
        TR = triangulation(double(F), double(V));
    catch ME
        error('acsInspectCapMakerManufacturingGeometry:BadStl', ...
            'Could not interpret STL "%s": %s', fileName, ME.message);
    end
end

function out = mergeStructs(a, b)
    out = a;
    if isempty(b)
        return;
    end
    names = fieldnames(b);
    for i = 1:numel(names)
        out.(names{i}) = b.(names{i});
    end
end

function value = getOptionalField(S, fieldName, defaultValue)
    if isstruct(S) && isfield(S, fieldName) && ~isempty(S.(fieldName))
        value = S.(fieldName);
    else
        value = defaultValue;
    end
end

function pathOut = expandUserPath(pathIn)
    pathOut = char(pathIn);
    if isempty(pathOut)
        return;
    end
    if startsWith(pathOut, '~')
        pathOut = fullfile(char(java.lang.System.getProperty('user.home')), ...
            pathOut(2:end));
    end
end

function ensureDir(folder)
    if isempty(folder)
        return;
    end
    if exist(folder, 'dir') ~= 7
        mkdir(folder);
    end
end

function qcFile = defaultOutputFile(data)
    baseDir = pwd;
    tag = 'capMakerManufacturingGeometryInspector';
    if isstruct(data.report)
        if isfield(data.report, 'outputDir') && ~isempty(data.report.outputDir)
            baseDir = char(data.report.outputDir);
        end
        if isfield(data.report, 'manufacturingTag') && ...
                ~isempty(data.report.manufacturingTag)
            tag = char(data.report.manufacturingTag);
        end
    end
    qcFile = fullfile(baseDir, [tag '_geometry_inspector.png']);
end

function printSummary(out)
    T = out.diagnostics.table;
    fprintf('\nCapMaker manufacturing geometry inspector\n');
    fprintf('  sites: %d\n', height(T));
    fprintf('  severe holders: %d\n', nnz(T.severity == 2));
    fprintf('  warning holders: %d\n', nnz(T.severity == 1));
    if any(T.severity > 0)
        fprintf('  flagged sites:\n');
        flagged = T(T.severity > 0, :);
        disp(flagged(:, {'name', 'axisZ', 'axisToSmoothNormalDeg', ...
            'bedClearanceMm', 'targetSnapDistanceMm', 'severity'}));
    end
    if ~isempty(out.qcFigure)
        fprintf('  QC figure: %s\n', out.qcFigure);
    end
    fprintf('\n');
end
