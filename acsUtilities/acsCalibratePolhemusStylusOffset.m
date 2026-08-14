function out = acsCalibratePolhemusStylusOffset(source, varargin)
% ACSCALIBRATEPOLHEMUSSTYLUSOFFSET Estimate FasTrak stylus tip offset.
%
% out = acsCalibratePolhemusStylusOffset(source) fits the local stylus-tip
% offset from samples collected with the stylus tip fixed in one small divot
% while the stylus body is swung through many orientations. Source can be a
% saved acsPolhemus MAT/JSON session, an acsPolhemus session struct, or an
% N-by-6 numeric matrix [x y z az el roll].
%
% The model is:
%
%     fixedTip = reportedPosition + R(orientation) * localTipOffset
%
% where reportedPosition is in inches. Because the FasTrak Euler convention
% is easy to misremember, the utility evaluates a family of candidate
% conventions and stores the one that minimizes the corrected-tip residual.

opts = parseInputs(varargin{:});
[P, anglesDeg, sourceInfo] = readCalibrationSource(source, opts);
validateCalibrationData(P, anglesDeg);

if opts.subtractMeanPosition
    P = bsxfun(@minus, P, mean(P, 1));
end

candidates = makeCandidateConventions(opts);
fits = repmat(emptyFit(), numel(candidates), 1);
for i = 1:numel(candidates)
    fits(i) = fitConvention(P, anglesDeg, candidates(i));
end

[~, bestIdx] = min([fits.rmsInches]);
best = fits(bestIdx);
topFits = sortFits(fits, opts.maxStoredCandidates);
rawSphere = fitSphere(P);

out = struct();
out.createdOn = char(datetime('now'));
out.method = 'divotStylusSwing';
out.source = sourceInfo;
out.coordinateUnits = 'in';
out.nSamples = size(P, 1);
out.rawSensorCoordinatesInches = P;
out.orientationAnglesDeg = anglesDeg;
out.offsetLocalInches = best.offsetLocalInches(:)';
out.offsetLocalMm = out.offsetLocalInches * 25.4;
out.fixedTipPointInches = best.fixedTipPointInches(:)';
out.fixedTipPointMm = out.fixedTipPointInches * 25.4;
out.correctedTipCoordinatesInches = best.correctedTipCoordinatesInches;
out.correctedTipCoordinatesCm = best.correctedTipCoordinatesInches * 2.54;
residualVectorsInches = bsxfun(@minus, best.correctedTipCoordinatesInches, ...
    out.fixedTipPointInches);
out.residualVectorsInches = residualVectorsInches;
out.residualVectorsMm = residualVectorsInches * 25.4;
out.residualsInches = best.residualsInches;
out.residualsMm = best.residualsInches * 25.4;
out.residualAnisotropy = residualAnisotropy(out.residualVectorsMm);
out.rmsInches = best.rmsInches;
out.rmsMm = best.rmsInches * 25.4;
out.p95Inches = percentile(best.residualsInches, 95);
out.p95Mm = out.p95Inches * 25.4;
out.maxInches = max(best.residualsInches);
out.maxMm = out.maxInches * 25.4;
out.bestConvention = best.convention;
out.candidateSummary = topFits;
out.rawPositionSphere = rawSphere;
out.hardwareOffsetDuringAcquisitionInches = sourceInfo.hardwareStylusOffsetInches;
out.recommendedUse = ['Acquire future sessions with FasTrak hardware stylus ', ...
    'offset set to [0 0 0] and apply offsetLocalInches in software using ', ...
    'bestConvention.'];

if any(abs(sourceInfo.hardwareStylusOffsetInches) > 1e-6)
    out.warning = ['Calibration source reports a nonzero hardware stylus ', ...
        'offset during acquisition. The fitted vector may be a residual ', ...
        'correction for that hardware state rather than a clean sensor-to-tip ', ...
        'offset. For the cleanest calibration, collect a stylus calibration ', ...
        'session in acsPolhemus, which sets the hardware offset to zero.'];
else
    out.warning = '';
end

if opts.showFigures || opts.saveFigures
    out.figure = makeCalibrationFigure(out, opts);
end

if ~isempty(opts.outputFile)
    out.outputFile = writeCalibration(out, opts.outputFile);
else
    out.outputFile = '';
end

if opts.verbose
    printSummary(out);
end
end

function opts = parseInputs(varargin)
p = inputParser();
p.addParameter('outputFile', '', @(x) ischar(x) || isstring(x));
p.addParameter('inputUnits', 'auto', @(x) ischar(x) || isstring(x));
p.addParameter('showFigures', true, @(x) islogical(x) || isnumeric(x));
p.addParameter('saveFigures', false, @(x) islogical(x) || isnumeric(x));
p.addParameter('figureFile', '', @(x) ischar(x) || isstring(x));
p.addParameter('verbose', true, @(x) islogical(x) || isnumeric(x));
p.addParameter('orders', {'xyz', 'xzy', 'yxz', 'yzx', 'zxy', 'zyx'}, ...
    @(x) iscell(x) || isstring(x) || ischar(x));
p.addParameter('allowSignFlips', true, @(x) islogical(x) || isnumeric(x));
p.addParameter('allowPreMultiply', true, @(x) islogical(x) || isnumeric(x));
p.addParameter('allowTranspose', true, @(x) islogical(x) || isnumeric(x));
p.addParameter('subtractMeanPosition', false, @(x) islogical(x) || isnumeric(x));
p.addParameter('maxStoredCandidates', 12, @(x) isnumeric(x) && isscalar(x));
p.parse(varargin{:});
opts = p.Results;
opts.outputFile = char(opts.outputFile);
opts.inputUnits = lower(char(opts.inputUnits));
opts.showFigures = logical(opts.showFigures);
opts.saveFigures = logical(opts.saveFigures);
opts.figureFile = char(opts.figureFile);
opts.verbose = logical(opts.verbose);
opts.allowSignFlips = logical(opts.allowSignFlips);
opts.allowPreMultiply = logical(opts.allowPreMultiply);
opts.allowTranspose = logical(opts.allowTranspose);
opts.subtractMeanPosition = logical(opts.subtractMeanPosition);
opts.maxStoredCandidates = max(1, round(double(opts.maxStoredCandidates)));
if ischar(opts.orders)
    opts.orders = {opts.orders};
elseif isstring(opts.orders)
    opts.orders = cellstr(opts.orders(:));
end
end

function [P, anglesDeg, sourceInfo] = readCalibrationSource(source, opts)
sourceInfo = struct('type', class(source), 'file', '', ...
    'hardwareStylusOffsetInches', [NaN NaN NaN]);
if isnumeric(source)
    if size(source, 2) < 6
        error('acsCalibratePolhemusStylusOffset:BadNumericInput', ...
            'Numeric source must be N-by-6 or wider: [x y z angle1 angle2 angle3].');
    end
    P = double(source(:, 1:3));
    anglesDeg = double(source(:, 4:6));
    sourceInfo.type = 'numeric';
    sourceInfo.coordinateSource = 'numeric columns 1:3';
elseif ischar(source) || isstring(source)
    fileName = char(source);
    sourceInfo.file = fileName;
    S = readSessionFile(fileName);
    [P, anglesDeg, sourceInfo] = dataFromSessionStruct(S, opts, sourceInfo);
elseif isstruct(source)
    [P, anglesDeg, sourceInfo] = dataFromSessionStruct(source, opts, sourceInfo);
else
    error('acsCalibratePolhemusStylusOffset:BadSource', ...
        'Source must be a file, session struct, or numeric matrix.');
end

switch opts.inputUnits
    case 'auto'
        % Already handled by the source reader when metadata are available.
    case {'in', 'inch', 'inches'}
        sourceInfo.coordinateUnitsAssumed = 'in';
    case {'cm', 'centimeter', 'centimeters'}
        P = P / 2.54;
        sourceInfo.coordinateUnitsAssumed = 'cm';
    case {'mm', 'millimeter', 'millimeters'}
        P = P / 25.4;
        sourceInfo.coordinateUnitsAssumed = 'mm';
    otherwise
        error('acsCalibratePolhemusStylusOffset:BadUnits', ...
            'inputUnits must be auto, in, cm, or mm.');
end
end

function S = readSessionFile(fileName)
[~, ~, ext] = fileparts(fileName);
switch lower(ext)
    case '.mat'
        raw = load(fileName);
        if isfield(raw, 'out') && isstruct(raw.out)
            S = raw.out;
            return;
        end
        names = fieldnames(raw);
        for i = 1:numel(names)
            if isstruct(raw.(names{i}))
                S = raw.(names{i});
                return;
            end
        end
        error('acsCalibratePolhemusStylusOffset:NoStructInMat', ...
            'No session struct found in %s.', fileName);
    case '.json'
        S = jsondecode(fileread(fileName));
    otherwise
        error('acsCalibratePolhemusStylusOffset:UnsupportedFile', ...
            ['Use a MAT or JSON acsPolhemus session so orientation ', ...
             'angles are available. Legacy TXT files do not contain ', ...
             'orientation angles.']);
end
end

function [P, anglesDeg, sourceInfo] = dataFromSessionStruct(S, opts, sourceInfo)
if isfield(S, 'rawDeviceCoordinatesInches') && ~isempty(S.rawDeviceCoordinatesInches)
    P = double(S.rawDeviceCoordinatesInches(:, 1:3));
    sourceInfo.coordinateSource = 'rawDeviceCoordinatesInches';
elseif isfield(S, 'deviceCoordinatesInches') && ~isempty(S.deviceCoordinatesInches)
    P = double(S.deviceCoordinatesInches(:, 1:3));
    sourceInfo.coordinateSource = 'deviceCoordinatesInches';
elseif isfield(S, 'coordinatesCm') && ~isempty(S.coordinatesCm)
    P = double(S.coordinatesCm(:, 1:3)) / 2.54;
    sourceInfo.coordinateSource = 'coordinatesCm';
    sourceInfo.coordinateUnitsAssumed = 'cm';
elseif isfield(S, 'coordinates') && ~isempty(S.coordinates)
    P = double(S.coordinates(:, 1:3));
    sourceInfo.coordinateSource = 'coordinates';
else
    error('acsCalibratePolhemusStylusOffset:NoCoordinates', ...
        'Session does not contain coordinates.');
end

if isfield(S, 'rawOrientationAngles') && ~isempty(S.rawOrientationAngles)
    anglesDeg = double(S.rawOrientationAngles(:, 1:3));
    sourceInfo.orientationSource = 'rawOrientationAngles';
elseif isfield(S, 'orientationAngles') && ~isempty(S.orientationAngles)
    anglesDeg = double(S.orientationAngles(:, 1:3));
    sourceInfo.orientationSource = 'orientationAngles';
else
    error('acsCalibratePolhemusStylusOffset:NoOrientations', ...
        'Session does not contain FasTrak orientation angles.');
end

if strcmp(opts.inputUnits, 'auto')
    sourceInfo.coordinateUnitsAssumed = 'in';
end

if isfield(S, 'device') && isstruct(S.device)
    if isfield(S.device, 'hardwareStylusOffsetInches')
        sourceInfo.hardwareStylusOffsetInches = row3(S.device.hardwareStylusOffsetInches);
    elseif isfield(S.device, 'stylusOffsetInches')
        sourceInfo.hardwareStylusOffsetInches = row3(S.device.stylusOffsetInches);
    end
end
if isfield(S, 'sessionType')
    sourceInfo.sessionType = S.sessionType;
end
if isfield(S, 'outputBaseFile')
    sourceInfo.outputBaseFile = S.outputBaseFile;
end
end

function validateCalibrationData(P, anglesDeg)
if size(P, 1) ~= size(anglesDeg, 1)
    error('acsCalibratePolhemusStylusOffset:SizeMismatch', ...
        'Coordinate and orientation arrays must have the same number of rows.');
end
if size(P, 1) < 6
    error('acsCalibratePolhemusStylusOffset:TooFewSamples', ...
        'Collect at least six orientations; 20-40 is a better practical target.');
end
if any(~isfinite(P(:))) || any(~isfinite(anglesDeg(:)))
    error('acsCalibratePolhemusStylusOffset:NonfiniteData', ...
        'Calibration coordinates and angles must be finite.');
end
if rank(bsxfun(@minus, anglesDeg, mean(anglesDeg, 1))) < 2
    warning('acsCalibratePolhemusStylusOffset:LimitedOrientationSpread', ...
        ['Orientation samples vary in fewer than two independent directions. ', ...
         'Swing the stylus through a wider cone for a stronger calibration.']);
end
end

function candidates = makeCandidateConventions(opts)
if opts.allowSignFlips
    signRows = dec2bin(0:7) - '0';
    signRows(signRows == 0) = -1;
else
    signRows = [1 1 1];
end
if opts.allowPreMultiply
    multiplyOrders = {'post', 'pre'};
else
    multiplyOrders = {'post'};
end
if opts.allowTranspose
    transposeValues = [false true];
else
    transposeValues = false;
end

candidates = struct('order', {}, 'signs', {}, 'angleColumns', {}, ...
    'multiplyOrder', {}, 'transpose', {});
for oi = 1:numel(opts.orders)
    for si = 1:size(signRows, 1)
        for mi = 1:numel(multiplyOrders)
            for ti = 1:numel(transposeValues)
                candidates(end + 1).order = lower(char(opts.orders{oi})); %#ok<AGROW>
                candidates(end).signs = signRows(si, :);
                candidates(end).angleColumns = [1 2 3];
                candidates(end).multiplyOrder = multiplyOrders{mi};
                candidates(end).transpose = transposeValues(ti);
            end
        end
    end
end
end

function fit = fitConvention(P, anglesDeg, convention)
R = acsPolhemusOrientationMatrix(anglesDeg, convention);
n = size(P, 1);
A = zeros(3 * n, 6);
b = zeros(3 * n, 1);
for i = 1:n
    rows = (i - 1) * 3 + (1:3);
    A(rows, :) = [R(:, :, i), -eye(3)];
    b(rows) = -P(i, :)';
end
x = A \ b;
d = x(1:3);
c = x(4:6);
tip = zeros(n, 3);
for i = 1:n
    tip(i, :) = P(i, :) + (R(:, :, i) * d)';
end
residuals = sqrt(sum(bsxfun(@minus, tip, c').^2, 2));
fit = emptyFit();
fit.convention = convention;
fit.offsetLocalInches = d(:)';
fit.fixedTipPointInches = c(:)';
fit.correctedTipCoordinatesInches = tip;
fit.residualsInches = residuals;
fit.rmsInches = sqrt(mean(residuals.^2));
fit.maxInches = max(residuals);
end

function fit = emptyFit()
fit = struct('convention', struct(), ...
    'offsetLocalInches', [NaN NaN NaN], ...
    'fixedTipPointInches', [NaN NaN NaN], ...
    'correctedTipCoordinatesInches', [], ...
    'residualsInches', [], ...
    'rmsInches', Inf, ...
    'maxInches', Inf);
end

function top = sortFits(fits, nKeep)
[~, ord] = sort([fits.rmsInches], 'ascend');
ord = ord(1:min(nKeep, numel(ord)));
top = repmat(struct( ...
    'rank', [], 'rmsMm', [], 'maxMm', [], 'offsetLocalMm', [], ...
    'order', '', 'signs', [], 'multiplyOrder', '', 'transpose', false), ...
    numel(ord), 1);
for i = 1:numel(ord)
    f = fits(ord(i));
    top(i).rank = i;
    top(i).rmsMm = f.rmsInches * 25.4;
    top(i).maxMm = f.maxInches * 25.4;
    top(i).offsetLocalMm = f.offsetLocalInches * 25.4;
    top(i).order = f.convention.order;
    top(i).signs = f.convention.signs;
    top(i).multiplyOrder = f.convention.multiplyOrder;
    top(i).transpose = f.convention.transpose;
end
end

function sphere = fitSphere(P)
if size(P, 1) < 4
    sphere = struct('centerInches', [NaN NaN NaN], ...
        'radiusInches', NaN, 'rmsResidualInches', NaN, ...
        'centerMm', [NaN NaN NaN], 'radiusMm', NaN, ...
        'rmsResidualMm', NaN);
    return;
end

function A = residualAnisotropy(residualVectorsMm)
if size(residualVectorsMm, 1) < 3
    A = struct('covarianceMm2', nan(3), ...
        'principalRmsMm', [NaN NaN NaN], ...
        'principalAxes', nan(3), ...
        'rmsRatioMaxToMin', NaN);
    return;
end
C = cov(residualVectorsMm);
[V, D] = eig((C + C') ./ 2);
vals = max(0, diag(D));
[vals, ord] = sort(vals, 'descend');
V = V(:, ord);
principalRms = sqrt(vals(:)');
finiteNonzero = principalRms(isfinite(principalRms) & principalRms > eps);
if isempty(finiteNonzero)
    ratio = NaN;
else
    ratio = max(finiteNonzero) / min(finiteNonzero);
end
A = struct('covarianceMm2', C, ...
    'principalRmsMm', principalRms, ...
    'principalAxes', V, ...
    'rmsRatioMaxToMin', ratio);
end
A = [-2 * P, ones(size(P, 1), 1)];
b = -sum(P.^2, 2);
x = A \ b;
center = x(1:3)';
radius = sqrt(max(0, sum(center.^2) - x(4)));
d = sqrt(sum(bsxfun(@minus, P, center).^2, 2));
res = d - radius;
sphere = struct('centerInches', center, ...
    'radiusInches', radius, ...
    'rmsResidualInches', sqrt(mean(res.^2)), ...
    'centerMm', center * 25.4, ...
    'radiusMm', radius * 25.4, ...
    'rmsResidualMm', sqrt(mean(res.^2)) * 25.4);
end

function fig = makeCalibrationFigure(out, opts)
fig = figure('Name', 'Polhemus stylus offset calibration', ...
    'NumberTitle', 'off', 'Color', 'w');
tiledlayout(fig, 1, 2, 'Padding', 'compact', 'TileSpacing', 'compact');

nexttile;
rawMm = out.rawSensorCoordinatesInches * 25.4;
tipMm = out.correctedTipCoordinatesInches * 25.4;
cMm = out.fixedTipPointMm;
plot3(rawMm(:, 1), rawMm(:, 2), rawMm(:, 3), 'o', ...
    'MarkerFaceColor', [0.5 0.5 0.5], 'MarkerEdgeColor', 'none');
hold on;
plot3(tipMm(:, 1), tipMm(:, 2), tipMm(:, 3), 'o', ...
    'MarkerFaceColor', [0.1 0.45 0.9], 'MarkerEdgeColor', 'none');
plot3(cMm(1), cMm(2), cMm(3), 'p', 'MarkerSize', 14, ...
    'MarkerFaceColor', [0.9 0.2 0.1], 'MarkerEdgeColor', 'k');
for i = 1:size(rawMm, 1)
    line([rawMm(i, 1) tipMm(i, 1)], [rawMm(i, 2) tipMm(i, 2)], ...
        [rawMm(i, 3) tipMm(i, 3)], 'Color', [0.7 0.7 0.7]);
end
axis equal;
grid on;
xlabel('x (mm)');
ylabel('y (mm)');
zlabel('z (mm)');
title('Raw sensor positions and corrected tip');
legend({'raw sensor', 'corrected tip', 'fixed divot'}, 'Location', 'best');
view(3);

nexttile;
resMm = out.residualsMm;
plot(resMm, '-o', 'Color', [0.1 0.45 0.9], ...
    'MarkerFaceColor', [0.1 0.45 0.9]);
grid on;
xlabel('sample');
ylabel('tip residual (mm)');
title(sprintf('RMS %.3g mm, p95 %.3g mm', out.rmsMm, out.p95Mm));

if opts.saveFigures
    figFile = opts.figureFile;
    if isempty(figFile)
        if ~isempty(opts.outputFile)
            [p, stem] = fileparts(opts.outputFile);
            figFile = fullfile(p, [stem '_qc.png']);
        else
            figFile = fullfile(pwd, 'polhemusStylusCalibration_qc.png');
        end
    end
    saveas(fig, figFile);
    outFigureFile = figFile; %#ok<NASGU>
end
if ~opts.showFigures
    close(fig);
end
end

function outputFile = writeCalibration(out, outputFile)
[folder, stem, ext] = fileparts(outputFile);
if isempty(folder)
    folder = pwd;
end
if isempty(ext)
    ext = '.mat';
end
if exist(folder, 'dir') ~= 7
    mkdir(folder);
end
outputFile = fullfile(folder, [stem ext]);
switch lower(ext)
    case '.mat'
        calibration = saveReady(out); %#ok<NASGU>
        save(outputFile, 'calibration');
        writeJson(fullfile(folder, [stem '.json']), jsonReady(out));
    case '.json'
        writeJson(outputFile, jsonReady(out));
        calibration = saveReady(out); %#ok<NASGU>
        save(fullfile(folder, [stem '.mat']), 'calibration');
    otherwise
        error('acsCalibratePolhemusStylusOffset:BadOutputExtension', ...
            'outputFile must be .mat or .json.');
end
end

function printSummary(out)
fprintf('\nPolhemus stylus offset calibration\n');
fprintf('  samples: %d\n', out.nSamples);
fprintf('  best convention: order %s, signs [%+d %+d %+d], %s multiply, transpose %s\n', ...
    out.bestConvention.order, out.bestConvention.signs, ...
    out.bestConvention.multiplyOrder, yesNo(out.bestConvention.transpose));
fprintf('  local sensor-to-tip offset: [%.4f %.4f %.4f] mm\n', ...
    out.offsetLocalMm);
fprintf('  offset magnitude: %.4f mm\n', norm(out.offsetLocalMm));
fprintf('  corrected-tip residual RMS / p95 / max: %.4g / %.4g / %.4g mm\n', ...
    out.rmsMm, out.p95Mm, out.maxMm);
fprintf('  residual principal RMS axes: [%.4g %.4g %.4g] mm (max/min %.4g)\n', ...
    out.residualAnisotropy.principalRmsMm, ...
    out.residualAnisotropy.rmsRatioMaxToMin);
fprintf('  raw-position sphere radius: %.4f mm (RMS shell error %.4g mm)\n', ...
    out.rawPositionSphere.radiusMm, out.rawPositionSphere.rmsResidualMm);
if ~isempty(out.warning)
    fprintf('  warning: %s\n', out.warning);
end
if isfield(out, 'outputFile') && ~isempty(out.outputFile)
    fprintf('  saved calibration: %s\n', out.outputFile);
end
fprintf('\n');
end

function S = saveReady(S)
if isstruct(S) && isfield(S, 'figure') && isa(S.figure, 'matlab.ui.Figure')
    S.figure = char(class(S.figure));
end
end

function r = row3(x)
x = double(x);
x = x(:)';
if numel(x) < 3
    r = [NaN NaN NaN];
else
    r = x(1:3);
end
end

function q = percentile(x, p)
x = sort(x(:));
if isempty(x)
    q = NaN;
    return;
end
idx = 1 + (numel(x) - 1) * p / 100;
lo = floor(idx);
hi = ceil(idx);
if lo == hi
    q = x(lo);
else
    q = x(lo) + (x(hi) - x(lo)) * (idx - lo);
end
end

function writeJson(fileName, S)
fid = fopen(fileName, 'wt');
if fid < 0
    error('acsCalibratePolhemusStylusOffset:CouldNotWriteJson', ...
        'Could not write %s', fileName);
end
cleaner = onCleanup(@() fclose(fid));
try
    txt = jsonencode(S, 'PrettyPrint', true);
catch
    txt = jsonencode(S);
end
fprintf(fid, '%s', txt);
clear cleaner;
end

function S = jsonReady(S)
if isstruct(S)
    for k = 1:numel(S)
        names = fieldnames(S(k));
        for i = 1:numel(names)
            S(k).(names{i}) = jsonReady(S(k).(names{i}));
        end
    end
elseif iscell(S)
    for i = 1:numel(S)
        S{i} = jsonReady(S{i});
    end
elseif isa(S, 'datetime')
    S = char(S);
elseif isa(S, 'matlab.ui.Figure')
    S = char(class(S));
end
end

function out = yesNo(tf)
if tf
    out = 'yes';
else
    out = 'no';
end
end
