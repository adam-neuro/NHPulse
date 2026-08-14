function out = acsEvaluateCapMakerManufacturingSites(layoutIn, varargin)
% ACSEVALUATECAPMAKERMANUFACTURINGSITES Audit electrode sites before STL build.
%
% out = acsEvaluateCapMakerManufacturingSites(layout) checks whether placed
% electrode holders would be too close to the printer bed or inside current
% placement exclusions. It is meant as a fast pre-STL validity screen for
% candidate tES layouts and combined tES/EEG layouts.
%
% Name-value options:
%   skinCacheFile              : override layout.layout.skin.cacheFile ['']
%   targetOptions              : override layout target options [auto]
%   holderInsideDiaMm          : holder inner bore diameter [4]
%   holderOutsideDiaMm         : holder outside diameter [12]
%   holderHeightMm             : holder height [7]
%   holderEmbedMm              : holder embed depth [0.3]
%   holderNormalMode           : 'autoSmooth', 'smooth', or 'vertex' ['autoSmooth']
%   holderSmoothNormalRadiusMm : local normal interpolation radius [6]
%   holderNormalDeviationThresholdDeg : autoSmooth threshold [25]
%   holderMinBedClearanceMm    : minimum holder clearance above zBed [1]
%   holderMinAxisZ             : invalid if placed holder axis z is below this [0.25]
%   holderMaxRawToSmoothNormalAngleDeg : invalid if raw normal disagrees more [25]
%   zBedMm                     : printer bed plane [0]
%   strapExclusionMode         : 'auto', 'always', or 'none' ['auto']
%   strapRostralOffsetMm       : strap keepout offset rostral to ear edge [0]
%   strapWidthMm               : nominal chin-strap width for keepout [10]
%   strapMarginMm              : extra strap/electrode placement margin [2]
%   showFigures                : show site-validity QC [false]
%   saveFigures                : save site-validity QC [false]
%   verbose                    : print summary [true]

    if nargin < 1 || isempty(layoutIn)
        error('acsEvaluateCapMakerManufacturingSites:MissingInput', ...
            'Provide a capMaker layout struct or saved MAT report.');
    end

    opts = parseInputs(varargin{:});
    addLocalDependencies();

    layout = readLayout(layoutIn);
    requireFields(layout, {'names', 'layoutCoordinatesMm'});
    names = cellstr(layout.names(:));
    targetsMm = double(layout.layoutCoordinatesMm);
    if numel(names) ~= size(targetsMm, 1)
        error('acsEvaluateCapMakerManufacturingSites:BadLayout', ...
            'layout.names and layout.layoutCoordinatesMm must have matching rows.');
    end

    [TRskin, skinCacheFile] = readSkinMesh(layout, opts);
    targetOptions = resolveTargetOptions(layout, opts);
    [targetOptions, strapExclusion] = acsAddStrapExclusionsToTargetOptions( ...
        targetOptions, [], ...
        'mode', opts.strapExclusionMode, ...
        'zBedMm', opts.zBedMm, ...
        'strapRostralOffsetMm', opts.strapRostralOffsetMm, ...
        'strapWidthMm', opts.strapWidthMm, ...
        'holderOutsideDiaMm', opts.holderOutsideDiaMm, ...
        'strapMarginMm', opts.strapMarginMm, ...
        'strapExclusionRadiusMm', opts.strapExclusionRadiusMm, ...
        'strapLateralLengthMm', opts.strapLateralLengthMm, ...
        'strapSampleSpacingMm', opts.strapSampleSpacingMm, ...
        'verbose', opts.verbose);

    holderTR = makeElectrodeHolderHex(opts.holderInsideDiaMm, ...
        opts.holderOutsideDiaMm, opts.holderHeightMm);
    [~, ~, ~, holderInfo] = placeElectrodeArrayOnSurface( ...
        TRskin, holderTR, targetsMm, opts.holderEmbedMm, ...
        'NormalMode', opts.holderNormalMode, ...
        'SmoothNormalRadiusMm', opts.holderSmoothNormalRadiusMm, ...
        'NormalDeviationThresholdDeg', opts.holderNormalDeviationThresholdDeg);

    siteMm = reshape([holderInfo.surfacePointMm], 3, []).';
    axisMm = reshape([holderInfo.holeAxis], 3, []).';
    axisZ = axisMm(:, 3);
    rawToSmoothNormalAngleDeg = reshape( ...
        [holderInfo.rawToSmoothNormalAngleDeg], [], 1);
    holderMinZ = reshape([holderInfo.minZMm], [], 1);
    bedClearanceMm = holderMinZ - opts.zBedMm;
    bedInvalid = bedClearanceMm < opts.holderMinBedClearanceMm;
    axisInvalid = false(size(axisZ));
    if ~isempty(opts.holderMinAxisZ)
        axisInvalid = axisZ < opts.holderMinAxisZ;
    end
    roughNormalInvalid = false(size(axisZ));
    if ~isempty(opts.holderMaxRawToSmoothNormalAngleDeg)
        roughNormalInvalid = rawToSmoothNormalAngleDeg > ...
            opts.holderMaxRawToSmoothNormalAngleDeg;
    end
    normalInvalid = axisInvalid | roughNormalInvalid;

    [exclusionSignedDistanceMm, nearestExclusionRow] = ...
        signedDistanceToExclusions(siteMm, targetOptions);
    exclusionInvalid = exclusionSignedDistanceMm < 0;
    [strapSignedDistanceMm, nearestStrapRow] = ...
        signedDistanceToStrap(siteMm, strapExclusion);
    strapInvalid = strapSignedDistanceMm < 0;

    invalid = bedInvalid | exclusionInvalid | normalInvalid;
    T = table(names(:), targetsMm(:, 1), targetsMm(:, 2), targetsMm(:, 3), ...
        siteMm(:, 1), siteMm(:, 2), siteMm(:, 3), axisZ, ...
        rawToSmoothNormalAngleDeg, bedClearanceMm, bedInvalid, ...
        exclusionSignedDistanceMm, exclusionInvalid, ...
        strapSignedDistanceMm, strapInvalid, axisInvalid, ...
        roughNormalInvalid, normalInvalid, invalid, ...
        'VariableNames', {'name', 'targetX', 'targetY', 'targetZ', ...
        'surfaceX', 'surfaceY', 'surfaceZ', 'axisZ', ...
        'rawToSmoothNormalAngleDeg', 'bedClearanceMm', 'bedInvalid', ...
        'exclusionSignedDistanceMm', 'exclusionInvalid', ...
        'strapSignedDistanceMm', 'strapInvalid', 'axisInvalid', ...
        'roughNormalInvalid', 'normalInvalid', 'invalid'});

    out = struct();
    out.createdOn = char(datetime('now'));
    out.skinCacheFile = skinCacheFile;
    out.names = names(:);
    out.layoutCoordinatesMm = targetsMm;
    out.surfaceCoordinatesMm = siteMm;
    out.holderInfo = holderInfo;
    out.siteTable = T;
    out.invalidNames = names(invalid);
    out.validNames = names(~invalid);
    out.bedInvalidNames = names(bedInvalid);
    out.exclusionInvalidNames = names(exclusionInvalid);
    out.strapInvalidNames = names(strapInvalid);
    out.normalInvalidNames = names(normalInvalid);
    out.axisInvalidNames = names(axisInvalid);
    out.roughNormalInvalidNames = names(roughNormalInvalid);
    out.nearestExclusionRow = nearestExclusionRow;
    out.nearestStrapRow = nearestStrapRow;
    out.targetOptions = compactTargetOptions(targetOptions);
    out.strapExclusion = compactExclusionStruct(strapExclusion);
    out.options = opts;

    fig = [];
    if opts.showFigures || opts.saveFigures
        figVisible = 'off';
        if opts.showFigures, figVisible = 'on'; end
        fig = makeQcFigure(TRskin, siteMm, names, invalid, out, figVisible);
        out.figure = fig;
        if opts.saveFigures
            out.qcFile = saveQcFigure(fig, layout, opts);
        end
        if ~opts.showFigures && isgraphics(fig)
            close(fig);
            out = rmfield(out, 'figure');
        end
    end

    if opts.verbose
        printSummary(out);
    end
end

function opts = parseInputs(varargin)
    p = inputParser;
    p.FunctionName = 'acsEvaluateCapMakerManufacturingSites';
    addParameter(p, 'skinCacheFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'targetOptions', [], @(x) isempty(x) || isstruct(x));
    addParameter(p, 'holderInsideDiaMm', 4, @isPositiveScalar);
    addParameter(p, 'holderOutsideDiaMm', 12, @isPositiveScalar);
    addParameter(p, 'holderHeightMm', 7, @isPositiveScalar);
    addParameter(p, 'holderEmbedMm', 0.3, @isNonnegativeScalar);
    addParameter(p, 'holderNormalMode', 'autoSmooth', ...
        @(x) ischar(x) || isstring(x));
    addParameter(p, 'holderSmoothNormalRadiusMm', 6, @isPositiveScalar);
    addParameter(p, 'holderNormalDeviationThresholdDeg', 25, ...
        @isNonnegativeScalar);
    addParameter(p, 'holderMinBedClearanceMm', 1, @isNonnegativeScalar);
    addParameter(p, 'holderMinAxisZ', 0.25, ...
        @(x) isempty(x) || (isnumeric(x) && isscalar(x) && isfinite(x)));
    addParameter(p, 'holderMaxRawToSmoothNormalAngleDeg', 25, ...
        @(x) isempty(x) || isNonnegativeScalar(x));
    addParameter(p, 'zBedMm', 0, @(x) isnumeric(x) && isscalar(x) && isfinite(x));
    addParameter(p, 'strapExclusionMode', 'auto', @(x) ischar(x) || isstring(x));
    addParameter(p, 'strapRostralOffsetMm', 0, @isNonnegativeScalar);
    addParameter(p, 'strapWidthMm', 10, @isPositiveScalar);
    addParameter(p, 'strapMarginMm', 2, @isNonnegativeScalar);
    addParameter(p, 'strapExclusionRadiusMm', [], ...
        @(x) isempty(x) || isPositiveScalar(x));
    addParameter(p, 'strapLateralLengthMm', 35, @isPositiveScalar);
    addParameter(p, 'strapSampleSpacingMm', 5, @isPositiveScalar);
    addParameter(p, 'showFigures', false, @isBoolLike);
    addParameter(p, 'saveFigures', false, @isBoolLike);
    addParameter(p, 'verbose', true, @isBoolLike);
    parse(p, varargin{:});

    opts = p.Results;
    opts.skinCacheFile = expandUserPath(char(opts.skinCacheFile));
    opts.holderInsideDiaMm = double(opts.holderInsideDiaMm);
    opts.holderOutsideDiaMm = double(opts.holderOutsideDiaMm);
    opts.holderHeightMm = double(opts.holderHeightMm);
    opts.holderEmbedMm = double(opts.holderEmbedMm);
    opts.holderNormalMode = normalizeHolderNormalMode(opts.holderNormalMode);
    opts.holderSmoothNormalRadiusMm = double(opts.holderSmoothNormalRadiusMm);
    opts.holderNormalDeviationThresholdDeg = double( ...
        opts.holderNormalDeviationThresholdDeg);
    opts.holderMinBedClearanceMm = double(opts.holderMinBedClearanceMm);
    if ~isempty(opts.holderMinAxisZ)
        opts.holderMinAxisZ = double(opts.holderMinAxisZ);
    end
    if ~isempty(opts.holderMaxRawToSmoothNormalAngleDeg)
        opts.holderMaxRawToSmoothNormalAngleDeg = double( ...
            opts.holderMaxRawToSmoothNormalAngleDeg);
    end
    opts.zBedMm = double(opts.zBedMm);
    opts.strapExclusionMode = normalizeStrapExclusionMode(opts.strapExclusionMode);
    opts.strapRostralOffsetMm = double(opts.strapRostralOffsetMm);
    opts.strapWidthMm = double(opts.strapWidthMm);
    opts.strapMarginMm = double(opts.strapMarginMm);
    if ~isempty(opts.strapExclusionRadiusMm)
        opts.strapExclusionRadiusMm = double(opts.strapExclusionRadiusMm);
    end
    opts.strapLateralLengthMm = double(opts.strapLateralLengthMm);
    opts.strapSampleSpacingMm = double(opts.strapSampleSpacingMm);
    opts.showFigures = logical(opts.showFigures);
    opts.saveFigures = logical(opts.saveFigures);
    opts.verbose = logical(opts.verbose);
end

function addLocalDependencies()
    repoRoot = fileparts(fileparts(mfilename('fullpath')));
    addpath(fullfile(repoRoot, 'acsUtilities'));
    addpath(fullfile(repoRoot, 'capMaker', 'geometry'));
    addpath(fullfile(repoRoot, 'capMaker', 'core'));
end

function layout = readLayout(value)
    if isstruct(value)
        layout = value;
        return;
    end
    if ~(ischar(value) || isstring(value))
        error('acsEvaluateCapMakerManufacturingSites:BadLayoutInput', ...
            'layoutIn must be a layout struct or saved MAT report.');
    end
    S = load(char(value));
    layout = firstStructInMat(S);
end

function S = firstStructInMat(M)
    if isfield(M, 'out') && isstruct(M.out)
        S = M.out;
        return;
    end
    fields = fieldnames(M);
    for i = 1:numel(fields)
        if isstruct(M.(fields{i}))
            S = M.(fields{i});
            return;
        end
    end
    error('acsEvaluateCapMakerManufacturingSites:NoStructInMat', ...
        'MAT report did not contain a struct.');
end

function requireFields(S, fields)
    for i = 1:numel(fields)
        if ~isfield(S, fields{i}) || isempty(S.(fields{i}))
            error('acsEvaluateCapMakerManufacturingSites:MissingField', ...
                'Layout is missing required field "%s".', fields{i});
        end
    end
end

function [TRskin, skinCacheFile] = readSkinMesh(layout, opts)
    skinCacheFile = opts.skinCacheFile;
    if isempty(skinCacheFile) && isfield(layout, 'layout') && ...
            isfield(layout.layout, 'skin') && ...
            isfield(layout.layout.skin, 'cacheFile')
        skinCacheFile = char(layout.layout.skin.cacheFile);
    end
    if isempty(skinCacheFile) || exist(skinCacheFile, 'file') ~= 2
        error('acsEvaluateCapMakerManufacturingSites:MissingSkinCache', ...
            'Provide skinCacheFile or a layout with layout.skin.cacheFile.');
    end
    S = load(skinCacheFile, 'TRskin');
    if ~isfield(S, 'TRskin')
        error('acsEvaluateCapMakerManufacturingSites:BadSkinCache', ...
            'Skin cache does not contain TRskin: %s', skinCacheFile);
    end
    TRskin = S.TRskin;
end

function targetOptions = resolveTargetOptions(layout, opts)
    if ~isempty(opts.targetOptions)
        targetOptions = opts.targetOptions;
        return;
    end
    if isfield(layout, 'targetOptions') && isstruct(layout.targetOptions)
        targetOptions = layout.targetOptions;
    elseif isfield(layout, 'eegTargetOptions') && isstruct(layout.eegTargetOptions)
        targetOptions = layout.eegTargetOptions;
    else
        targetOptions = struct();
    end
end

function [signedDistanceMm, nearestRow] = signedDistanceToExclusions(pointsMm, targetOptions)
    centers = zeros(0, 3);
    radii = zeros(0, 1);
    if isfield(targetOptions, 'exclusionCenters') && ...
            ~isempty(targetOptions.exclusionCenters)
        centers = double(targetOptions.exclusionCenters);
        radii = expandRadii(targetOptions.exclusionRadiusMM, size(centers, 1));
    end
    [signedDistanceMm, nearestRow] = signedDistanceToSpheres(pointsMm, centers, radii);
end

function [signedDistanceMm, nearestRow] = signedDistanceToStrap(pointsMm, strapExclusion)
    if isstruct(strapExclusion) && isfield(strapExclusion, 'centersMm')
        centers = double(strapExclusion.centersMm);
        radii = expandRadii(strapExclusion.radiusMm, size(centers, 1));
    else
        centers = zeros(0, 3);
        radii = zeros(0, 1);
    end
    [signedDistanceMm, nearestRow] = signedDistanceToSpheres(pointsMm, centers, radii);
end

function [signedDistanceMm, nearestRow] = signedDistanceToSpheres(pointsMm, centers, radii)
    n = size(pointsMm, 1);
    signedDistanceMm = inf(n, 1);
    nearestRow = nan(n, 1);
    if isempty(centers)
        return;
    end
    for i = 1:n
        d = sqrt(sum((centers - pointsMm(i, :)) .^ 2, 2)) - radii(:);
        [signedDistanceMm(i), nearestRow(i)] = min(d);
    end
end

function radii = expandRadii(value, n)
    if n == 0
        radii = zeros(0, 1);
        return;
    end
    if isempty(value)
        error('acsEvaluateCapMakerManufacturingSites:MissingExclusionRadius', ...
            'Exclusion centers require matching radii.');
    end
    radii = double(value(:));
    if isscalar(radii)
        radii = repmat(radii, n, 1);
    elseif numel(radii) ~= n
        error('acsEvaluateCapMakerManufacturingSites:BadExclusionRadius', ...
            'Exclusion radii must be scalar or match exclusion centers.');
    end
end

function targetOptions = compactTargetOptions(targetOptions)
    fields = {'manualTargetsMm'};
    for i = 1:numel(fields)
        if isfield(targetOptions, fields{i})
            targetOptions = rmfield(targetOptions, fields{i});
        end
    end
end

function compact = compactExclusionStruct(value)
    if ~isstruct(value)
        compact = struct();
        return;
    end
    compact = value;
    heavyFields = {'figure', 'options'};
    for i = 1:numel(heavyFields)
        if isfield(compact, heavyFields{i})
            compact = rmfield(compact, heavyFields{i});
        end
    end
end

function fig = makeQcFigure(TRskin, siteMm, names, invalid, out, figVisible)
    V = double(TRskin.Points);
    rows = sampleRows(size(V, 1), 25000);
    fig = figure('Name', 'CapMaker manufacturing site audit', ...
        'Color', 'w', 'Visible', figVisible, 'Units', 'pixels', ...
        'Position', [120 120 980 720]);
    ax = axes('Parent', fig, 'Position', [0.06 0.08 0.86 0.84]);
    hold(ax, 'on');
    scatter3(ax, V(rows, 1), V(rows, 2), V(rows, 3), 3, ...
        [0.75 0.75 0.75], 'filled', 'MarkerFaceAlpha', 0.22);
    scatter3(ax, siteMm(~invalid, 1), siteMm(~invalid, 2), ...
        siteMm(~invalid, 3), 70, [0.05 0.55 0.18], 'filled', ...
        'MarkerEdgeColor', 'k');
    scatter3(ax, siteMm(invalid, 1), siteMm(invalid, 2), ...
        siteMm(invalid, 3), 90, [0.85 0.05 0.05], 'filled', ...
        'MarkerEdgeColor', 'k');
    for i = 1:size(siteMm, 1)
        text(ax, siteMm(i, 1), siteMm(i, 2), siteMm(i, 3), ...
            [' ' names{i}], 'FontSize', 8, 'Color', [0.05 0.05 0.05]);
    end
    drawStrapPreview(ax, out.strapExclusion);
    axis(ax, 'equal');
    grid(ax, 'on');
    view(ax, 35, 28);
    xlabel(ax, 'capMaker X (mm)');
    ylabel(ax, 'capMaker Y (mm)');
    zlabel(ax, 'capMaker Z (mm)');
    title(ax, sprintf('Manufacturing site audit: %d invalid / %d', ...
        nnz(invalid), numel(invalid)));
end

function drawStrapPreview(ax, strapExclusion)
    if ~isstruct(strapExclusion) || ~isfield(strapExclusion, 'centersMm') || ...
            isempty(strapExclusion.centersMm)
        return;
    end
    C = double(strapExclusion.centersMm);
    scatter3(ax, C(:, 1), C(:, 2), C(:, 3), 24, [0.50 0.00 0.70], ...
        'filled', 'MarkerFaceAlpha', 0.35, 'MarkerEdgeAlpha', 0.35);
end

function rows = sampleRows(nRows, maxRows)
    if nRows <= maxRows
        rows = (1:nRows).';
    else
        rows = unique(round(linspace(1, nRows, maxRows))).';
    end
end

function qcFile = saveQcFigure(fig, layout, opts)
    if isfield(layout, 'customLocationsFile') && ~isempty(layout.customLocationsFile)
        [folder, stem] = fileparts(layout.customLocationsFile);
    elseif isfield(layout, 't1File') && ~isempty(layout.t1File)
        [folder, stem] = fileparts(layout.t1File);
    else
        folder = pwd;
        stem = 'capMakerLayout';
    end
    qcDir = fullfile(folder, 'qc');
    ensureDir(qcDir);
    qcFile = fullfile(qcDir, [stem '_manufacturingSiteAudit.png']);
    try
        exportgraphics(fig, qcFile, 'Resolution', 150);
    catch
        saveas(fig, qcFile);
    end
    if opts.verbose
        fprintf('Saved manufacturing site audit QC: %s\n', qcFile);
    end
end

function printSummary(out)
    fprintf('\nCapMaker manufacturing site audit\n');
    fprintf('  sites: %d\n', numel(out.names));
    fprintf('  invalid: %d\n', numel(out.invalidNames));
    if ~isempty(out.bedInvalidNames)
        fprintf('  bed clearance invalid: %s\n', strjoin(out.bedInvalidNames, ', '));
    end
    if ~isempty(out.exclusionInvalidNames)
        fprintf('  placement exclusion invalid: %s\n', ...
            strjoin(out.exclusionInvalidNames, ', '));
    end
    if ~isempty(out.strapInvalidNames)
        fprintf('  strap keepout invalid: %s\n', strjoin(out.strapInvalidNames, ', '));
    end
    if ~isempty(out.normalInvalidNames)
        fprintf('  holder normal invalid: %s\n', ...
            strjoin(out.normalInvalidNames, ', '));
    end
end

function mode = normalizeStrapExclusionMode(modeIn)
    mode = lower(strtrim(char(modeIn)));
    switch mode
        case {'auto', 'always', 'none'}
            % Accepted as-is.
        case {'off', 'never', 'ignore'}
            mode = 'none';
        case {'on', 'yes'}
            mode = 'auto';
        otherwise
            error('acsEvaluateCapMakerManufacturingSites:BadStrapExclusionMode', ...
                'strapExclusionMode must be ''auto'', ''always'', or ''none''.');
    end
end

function mode = normalizeHolderNormalMode(modeIn)
    mode = lower(strtrim(char(modeIn)));
    switch regexprep(mode, '[\s_\-]+', '')
        case {'vertex', 'raw', 'legacy'}
            mode = 'vertex';
        case {'smooth', 'smoothed', 'interpolated'}
            mode = 'smooth';
        case {'autosmooth', 'auto', 'repair'}
            mode = 'autoSmooth';
        otherwise
            error('acsEvaluateCapMakerManufacturingSites:BadHolderNormalMode', ...
                ['holderNormalMode must be ''autoSmooth'', ', ...
                 '''smooth'', or ''vertex''.']);
    end
end

function ensureDir(folder)
    if ~isempty(folder) && exist(folder, 'dir') ~= 7
        mkdir(folder);
    end
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

function tf = isPositiveScalar(x)
    tf = isnumeric(x) && isscalar(x) && isfinite(x) && x > 0;
end

function tf = isNonnegativeScalar(x)
    tf = isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0;
end
