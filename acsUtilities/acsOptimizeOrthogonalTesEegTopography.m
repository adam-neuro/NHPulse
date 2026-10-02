function out = acsOptimizeOrthogonalTesEegTopography(layoutIn, baselineRecipe, varargin)
% ACSOPTIMIZEORTHOGONALTESEEGTOPOGRAPHY Find a discriminable tES control.
%
% out = acsOptimizeOrthogonalTesEegTopography(layout, baselineRecipe)
% finds a balanced tES current pattern whose predicted, referenced EEG
% topography is orthogonal to the baseline topography while making the
% alternate topography as large as possible. The electrode positions remain
% fixed. Current limits default to the envelope used by baselineRecipe.
%
% This is a multi-start, alternating directional optimization. Each inner
% problem is a convex linear program solved by linprog (or CVX as fallback);
% the overall maximum-norm
% problem is nonconvex, so the returned solution is a strong approximate
% optimum rather than a formal global-optimum certificate.
%
% Name-value options:
%   transferMatrix   : cached transfer struct/MAT; empty builds or reuses it
%   transferOptions  : options for acsBuildTesToEegTransferMatrix [{}]
%   totalCurrentMa   : max total source current [baseline positive current]
%   maxCurrentPerElectrodeMa : absolute contact cap [baseline maximum]
%   channelWeights  : nonnegative EEG-channel metric weights [ones]
%   nStarts          : directional restarts [16]
%   maxIterations    : updates per restart [15]
%   randomSeed       : reproducible start seed [1]
%   showFigures/saveFigures : comparison QC [true/false]
%   showTopography/saveTopography : scalp map of alternate [false]
%   outputFile       : MAT report [beside transfer report]
%   verbose          : print solution [true]
%
% The weighted dot product between baseline and alternate predictions is
% constrained to zero. With identity weights this is ordinary topographic
% orthogonality after the selected EEG reference has been applied.
%
% See also acsBuildTesToEegTransferMatrix, acsPredictEegVoltagesFromTes.

    opts = parseInputs(varargin{:});
    layout = readStruct(layoutIn);
    transfer = resolveTransfer(layoutIn, opts);
    requireFields(transfer, {'tesNames', 'eegNames', 'transferMatrixVPerMa'});
    tesNames = normalizeNames(transfer.tesNames);
    eegNames = normalizeNames(transfer.eegNames);
    M = double(transfer.transferMatrixVPerMa);
    if ~isequal(size(M), [numel(eegNames), numel(tesNames)]) || any(~isfinite(M(:)))
        error('acsOptimizeOrthogonalTesEegTopography:BadTransferMatrix', ...
            'Transfer matrix must be finite and sized nEEG-by-nTES.');
    end

    baselineCurrents = recipeCurrents(baselineRecipe, tesNames, layout);
    if abs(sum(baselineCurrents)) > opts.balanceToleranceMa
        error('acsOptimizeOrthogonalTesEegTopography:UnbalancedBaseline', ...
            'Baseline tES currents sum to %.6g mA.', sum(baselineCurrents));
    end
    baselineCurrents = baselineCurrents - sum(baselineCurrents) / numel(baselineCurrents);
    if isempty(opts.totalCurrentMa)
        opts.totalCurrentMa = sum(max(baselineCurrents, 0));
    end
    if isempty(opts.maxCurrentPerElectrodeMa)
        opts.maxCurrentPerElectrodeMa = max(abs(baselineCurrents));
    end
    if opts.totalCurrentMa <= 0 || opts.maxCurrentPerElectrodeMa <= 0
        error('acsOptimizeOrthogonalTesEegTopography:ZeroCurrentEnvelope', ...
            'Baseline recipe has no usable current envelope; specify current limits.');
    end

    weights = resolveWeights(opts.channelWeights, numel(eegNames));
    sqrtW = sqrt(weights(:));
    Z = bsxfun(@times, M, sqrtW);
    baselineVoltage = M * baselineCurrents;
    baselineMetric = Z * baselineCurrents;
    baselineNorm = norm(baselineMetric);
    if baselineNorm <= eps(max(1, norm(Z, 'fro')))
        error('acsOptimizeOrthogonalTesEegTopography:ZeroBaselineTopography', ...
            'Baseline recipe produces a zero or numerically negligible EEG topography.');
    end
    orthogonalityRow = baselineMetric' * Z;
    orthogonalityRow = orthogonalityRow / norm(orthogonalityRow);

    [alternateCurrents, search] = multiStartSearch(Z, baselineMetric, ...
        orthogonalityRow, opts);
    alternateVoltage = M * alternateCurrents;
    alternateMetric = Z * alternateCurrents;
    weightedCorrelation = dot(baselineMetric, alternateMetric) / ...
        (norm(baselineMetric) * norm(alternateMetric));
    ordinaryCorrelation = safeCorrelation(baselineVoltage, alternateVoltage);

    out = struct();
    out.createdOn = char(datetime('now'));
    out.kind = 'nhpulse.orthogonalTesEegStimulus';
    out.layoutSource = sourceLabel(layoutIn);
    out.transferMatrixReport = getField(transfer, 'reportMat', '');
    out.tesNames = tesNames(:);
    out.eegNames = eegNames(:);
    out.baselineRecipe = baselineRecipe;
    out.baselineCurrentsMa = baselineCurrents;
    out.alternateCurrentsMa = alternateCurrents;
    out.alternateRecipe = makeRecipe(tesNames, alternateCurrents);
    out.baselineEegVoltageV = baselineVoltage;
    out.alternateEegVoltageV = alternateVoltage;
    out.baselineEegVoltageMicroV = 1e6 * baselineVoltage;
    out.alternateEegVoltageMicroV = 1e6 * alternateVoltage;
    out.differenceEegVoltageMicroV = 1e6 * (alternateVoltage - baselineVoltage);
    out.weightedTopographyCorrelation = weightedCorrelation;
    out.topographyCorrelation = ordinaryCorrelation;
    out.weightedBaselineNormV = norm(baselineMetric);
    out.weightedAlternateNormV = norm(alternateMetric);
    out.weightedSeparationV = norm(alternateMetric - baselineMetric);
    out.totalCurrentMa = opts.totalCurrentMa;
    out.maxCurrentPerElectrodeMa = opts.maxCurrentPerElectrodeMa;
    out.channelWeights = weights;
    out.search = search;
    out.figure = [];
    out.qcFigure = '';
    out.topography = [];

    outputFile = resolveOutputFile(transfer, layout, opts.outputFile);
    out.reportMat = outputFile;
    if opts.showFigures || opts.saveFigures
        out.figure = makeFigure(out, opts.showFigures);
        if opts.saveFigures
            out.qcFigure = replaceExtension(outputFile, '_qc.png');
            saveFigure(out.figure, out.qcFigure);
        end
        if ~opts.showFigures && isgraphics(out.figure)
            close(out.figure);
            out.figure = [];
        end
    end
    if opts.showTopography || opts.saveTopography
        prediction = struct('eegNames', {eegNames}, ...
            'eegVoltageReferencedV', alternateVoltage, ...
            'eegVoltageReferencedMicroV', 1e6 * alternateVoltage, ...
            'simulationTag', opts.topographyTag, ...
            'reportMat', outputFile);
        out.topography = acsVisualizeEegVoltageTopography(prediction, layout, ...
            'showFigures', opts.showTopography, ...
            'saveFigures', opts.saveTopography, ...
            'showTes', true, ...
            'verbose', opts.verbose, ...
            opts.topographyOptions{:});
    end
    outToSave = stripGraphics(out); %#ok<NASGU>
    ensureParent(outputFile);
    save(outputFile, 'outToSave', '-v7.3');
    if opts.verbose, printSummary(out); end
end

function opts = parseInputs(varargin)
    p = inputParser;
    p.FunctionName = 'acsOptimizeOrthogonalTesEegTopography';
    addParameter(p, 'transferMatrix', [], @(x) isempty(x) || isstruct(x) || ischar(x) || isstring(x));
    addParameter(p, 'transferOptions', {}, @iscell);
    addParameter(p, 'totalCurrentMa', [], @emptyPositiveScalar);
    addParameter(p, 'maxCurrentPerElectrodeMa', [], @emptyPositiveScalar);
    addParameter(p, 'channelWeights', [], @(x) isempty(x) || isnumeric(x));
    addParameter(p, 'nStarts', 16, @(x) isnumeric(x) && isscalar(x) && x >= 2);
    addParameter(p, 'maxIterations', 15, @(x) isnumeric(x) && isscalar(x) && x >= 1);
    addParameter(p, 'convergenceTolerance', 1e-7, @positiveScalar);
    addParameter(p, 'balanceToleranceMa', 1e-6, @positiveScalar);
    addParameter(p, 'randomSeed', 1, @(x) isnumeric(x) && isscalar(x) && isfinite(x));
    addParameter(p, 'outputFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'showFigures', true, @isBoolLike);
    addParameter(p, 'saveFigures', false, @isBoolLike);
    addParameter(p, 'showTopography', false, @isBoolLike);
    addParameter(p, 'saveTopography', false, @isBoolLike);
    addParameter(p, 'topographyTag', 'orthogonalTesEegControl', @(x) ischar(x) || isstring(x));
    addParameter(p, 'topographyOptions', {}, @iscell);
    addParameter(p, 'verbose', true, @isBoolLike);
    parse(p, varargin{:});
    opts = p.Results;
    opts.nStarts = round(double(opts.nStarts));
    opts.maxIterations = round(double(opts.maxIterations));
    opts.randomSeed = double(opts.randomSeed);
    opts.outputFile = char(opts.outputFile);
    opts.topographyTag = char(opts.topographyTag);
    opts.showFigures = logical(opts.showFigures);
    opts.saveFigures = logical(opts.saveFigures);
    opts.showTopography = logical(opts.showTopography);
    opts.saveTopography = logical(opts.saveTopography);
    opts.verbose = logical(opts.verbose);
end

function tf = emptyPositiveScalar(x)
    tf = isempty(x) || positiveScalar(x);
end
function tf = positiveScalar(x)
    tf = isnumeric(x) && isscalar(x) && isfinite(x) && x > 0;
end
function tf = isBoolLike(x)
    tf = (islogical(x) || isnumeric(x)) && isscalar(x);
end

function transfer = resolveTransfer(layoutIn, opts)
    if isempty(opts.transferMatrix)
        transfer = acsBuildTesToEegTransferMatrix(layoutIn, opts.transferOptions{:});
    else
        transfer = readStruct(opts.transferMatrix);
    end
end

function [bestCurrents, info] = multiStartSearch(Z, baseline, orthRow, opts)
    if exist('linprog', 'file') ~= 2 && exist('cvx_begin', 'file') ~= 2
        error('acsOptimizeOrthogonalTesEegTopography:MissingLinearSolver', ...
            'The search requires MATLAB linprog or CVX.');
    end
    projector = eye(size(Z, 1)) - (baseline * baseline') / dot(baseline, baseline);
    projectedZ = projector * Z;
    [U, ~, ~] = svd(projectedZ, 'econ');
    oldRng = rng;
    cleanup = onCleanup(@() rng(oldRng)); %#ok<NASGU>
    rng(opts.randomSeed, 'twister');
    directions = zeros(size(Z, 1), opts.nStarts);
    nSeed = min(size(U, 2), max(1, floor(opts.nStarts / 4)));
    directions(:, 1:nSeed) = U(:, 1:nSeed);
    if 2 * nSeed <= opts.nStarts
        directions(:, nSeed + (1:nSeed)) = -U(:, 1:nSeed);
        firstRandom = 2 * nSeed + 1;
    else
        firstRandom = nSeed + 1;
    end
    directions(:, firstRandom:end) = randn(size(Z, 1), opts.nStarts-firstRandom+1);

    bestScore = -inf;
    bestCurrents = [];
    records = repmat(struct('score', -inf, 'iterations', 0, 'status', ''), opts.nStarts, 1);
    for s = 1:opts.nStarts
        d = projector * directions(:, s);
        if norm(d) <= eps, continue; end
        d = d / norm(d);
        lastScore = -inf;
        currents = [];
        status = '';
        for iter = 1:opts.maxIterations
            [currents, status] = solveDirectionalLp(Z, d, orthRow, opts);
            if ~isSolved(status), break; end
            y = projector * (Z * currents);
            score = norm(y);
            if score <= eps, break; end
            d = y / score;
            if abs(score-lastScore) <= opts.convergenceTolerance * max(1, score)
                break;
            end
            lastScore = score;
        end
        records(s).score = scoreOrMinusInf(currents, projectedZ);
        records(s).iterations = iter;
        records(s).status = status;
        if records(s).score > bestScore
            bestScore = records(s).score;
            bestCurrents = currents;
        end
    end
    if isempty(bestCurrents) || ~isfinite(bestScore)
        error('acsOptimizeOrthogonalTesEegTopography:NoSolution', ...
            'No CVX restart produced a usable orthogonal current pattern.');
    end
    info = struct('method', 'multistartAlternatingDirectionalLp', ...
        'approximateGlobalOptimum', true, 'bestScoreV', bestScore, ...
        'nStarts', opts.nStarts, 'maxIterations', opts.maxIterations, ...
        'randomSeed', opts.randomSeed, 'restartRecords', records);
end

function [currents, status] = solveDirectionalLp(Z, direction, orthRow, opts)
    nTes = size(Z, 2);
    if exist('linprog', 'file') == 2
        % Variables are [current; absCurrentBound]. The auxiliary variables
        % express the L1 current budget while preserving a pure LP.
        objective = [-Z' * direction; zeros(nTes, 1)];
        A = [eye(nTes), -eye(nTes); ...
            -eye(nTes), -eye(nTes); ...
            zeros(1, nTes), ones(1, nTes)];
        b = [zeros(2*nTes, 1); 2*opts.totalCurrentMa];
        Aeq = [ones(1, nTes), zeros(1, nTes); ...
            orthRow, zeros(1, nTes)];
        beq = [0; 0];
        lower = [-opts.maxCurrentPerElectrodeMa*ones(nTes, 1); zeros(nTes, 1)];
        upper = opts.maxCurrentPerElectrodeMa*ones(2*nTes, 1);
        lpOptions = optimoptions('linprog', 'Display', 'none');
        [solution, ~, exitflag] = linprog(objective, A, b, Aeq, beq, ...
            lower, upper, lpOptions);
        if exitflag > 0
            currents = solution(1:nTes);
            status = 'Solved (linprog)';
        else
            currents = [];
            status = sprintf('Failed (linprog exitflag %d)', exitflag);
        end
        return;
    end
    if opts.verbose
        cvx_begin
    else
        cvx_begin quiet
    end
        variable currents(nTes);
        maximize(direction' * Z * currents);
        subject to
            sum(currents) == 0;
            orthRow * currents == 0;
            norm(currents, 1) <= 2 * opts.totalCurrentMa;
            norm(currents, inf) <= opts.maxCurrentPerElectrodeMa;
    cvx_end
    status = cvx_status;
end

function tf = isSolved(status)
    tf = contains(lower(string(status)), 'solved');
end

function value = scoreOrMinusInf(currents, projectedZ)
    if isempty(currents) || any(~isfinite(currents))
        value = -inf;
    else
        value = norm(projectedZ * currents);
    end
end

function weights = resolveWeights(value, n)
    if isempty(value), weights = ones(n, 1); else, weights = double(value(:)); end
    if numel(weights) ~= n || any(~isfinite(weights)) || any(weights < 0) || ~any(weights > 0)
        error('acsOptimizeOrthogonalTesEegTopography:BadWeights', ...
            'channelWeights must contain one nonnegative value per EEG channel.');
    end
end

function currents = recipeCurrents(recipe, tesNames, layout)
    if ~iscell(recipe) || mod(numel(recipe), 2) ~= 0
        error('acsOptimizeOrthogonalTesEegTopography:BadRecipe', ...
            'baselineRecipe must contain electrode-name/current pairs.');
    end
    names = cellfun(@char, recipe(1:2:end), 'UniformOutput', false);
    values = cellfun(@double, recipe(2:2:end));
    if isfield(layout, 'sourceTesNames') && isfield(layout, 'tesNames')
        source = normalizeNames(layout.sourceTesNames);
        target = normalizeNames(layout.tesNames);
        for i = 1:numel(names)
            idx = find(strcmpi(names{i}, source), 1);
            if ~isempty(idx), names{i} = target{idx}; end
        end
    end
    currents = zeros(numel(tesNames), 1);
    for i = 1:numel(names)
        idx = find(strcmpi(names{i}, tesNames), 1);
        if isempty(idx)
            error('acsOptimizeOrthogonalTesEegTopography:UnknownRecipeName', ...
                'Baseline recipe electrode "%s" is not a fixed tES site.', names{i});
        end
        currents(idx) = currents(idx) + values(i);
    end
end

function value = readStruct(value)
    if isstruct(value), return; end
    data = load(char(value));
    fields = fieldnames(data);
    for i = 1:numel(fields)
        if isstruct(data.(fields{i})), value = data.(fields{i}); return; end
    end
    error('acsOptimizeOrthogonalTesEegTopography:NoStruct', ...
        'MAT file did not contain a struct.');
end

function requireFields(S, names)
    for i = 1:numel(names)
        if ~isfield(S, names{i}) || isempty(S.(names{i}))
            error('acsOptimizeOrthogonalTesEegTopography:MissingField', ...
                'Input is missing field "%s".', names{i});
        end
    end
end

function names = normalizeNames(names)
    if ischar(names), names = {names}; elseif isstring(names), names = cellstr(names(:)); end
    names = cellfun(@char, names(:), 'UniformOutput', false);
end

function recipe = makeRecipe(names, currents)
    recipe = reshape([names(:), num2cell(currents(:))]', 1, []);
end

function r = safeCorrelation(a, b)
    denom = norm(a) * norm(b);
    if denom <= eps, r = NaN; else, r = dot(a, b) / denom; end
end

function fig = makeFigure(out, showFigure)
    visibility = 'off'; if showFigure, visibility = 'on'; end
    fig = figure('Name', 'Orthogonal tES EEG control', 'Color', 'w', ...
        'Visible', visibility, 'WindowStyle', 'normal', 'Position', [100 100 1120 700]);
    ax1 = subplot(2, 2, 1, 'Parent', fig);
    bar(ax1, [out.baselineCurrentsMa out.alternateCurrentsMa]);
    set(ax1, 'XTick', 1:numel(out.tesNames), 'XTickLabel', out.tesNames, 'XTickLabelRotation', 35);
    ylabel(ax1, 'current (mA)'); title(ax1, 'tES recipes'); grid(ax1, 'on');
    legend(ax1, {'target-optimized', 'EEG-orthogonal control'}, 'Location', 'best');
    ax2 = subplot(2, 2, 2, 'Parent', fig);
    bar(ax2, [out.baselineEegVoltageMicroV out.alternateEegVoltageMicroV]);
    set(ax2, 'XTick', 1:numel(out.eegNames), 'XTickLabel', out.eegNames, 'XTickLabelRotation', 35);
    ylabel(ax2, 'referenced voltage (microV)'); title(ax2, 'Predicted EEG topographies'); grid(ax2, 'on');
    legend(ax2, {'target-optimized', 'EEG-orthogonal control'}, 'Location', 'best');
    ax3 = subplot(2, 2, 3, 'Parent', fig);
    scatter(ax3, out.baselineEegVoltageMicroV, out.alternateEegVoltageMicroV, 55, 'filled');
    xlabel(ax3, 'target-optimized (microV)'); ylabel(ax3, 'orthogonal control (microV)');
    title(ax3, sprintf('Topography cosine = %.3g', out.topographyCorrelation)); grid(ax3, 'on'); axis(ax3, 'equal');
    ax4 = subplot(2, 2, 4, 'Parent', fig);
    bar(ax4, out.differenceEegVoltageMicroV, 'FaceColor', [0.25 0.55 0.72]);
    set(ax4, 'XTick', 1:numel(out.eegNames), 'XTickLabel', out.eegNames, 'XTickLabelRotation', 35);
    ylabel(ax4, 'alternate - baseline (microV)'); title(ax4, 'Predicted contrast'); grid(ax4, 'on');
end

function fileName = resolveOutputFile(transfer, layout, requested)
    if ~isempty(requested), fileName = requested; return; end
    transferFile = getField(transfer, 'reportMat', '');
    if ~isempty(transferFile)
        [folder, stem] = fileparts(transferFile);
        fileName = fullfile(folder, [stem '_orthogonalControl.mat']);
    else
        [folder, stem] = fileparts(char(layout.t1File));
        fileName = fullfile(folder, [stem '_orthogonalTesEegControl.mat']);
    end
end

function value = getField(S, name, fallback)
    if isfield(S, name) && ~isempty(S.(name)), value = S.(name); else, value = fallback; end
end

function fileName = replaceExtension(fileName, suffix)
    [folder, stem] = fileparts(fileName); fileName = fullfile(folder, [stem suffix]);
end

function saveFigure(fig, fileName)
    ensureParent(fileName);
    try, exportgraphics(fig, fileName, 'Resolution', 200); catch, saveas(fig, fileName); end
end

function ensureParent(fileName)
    folder = fileparts(fileName); if ~isempty(folder) && exist(folder, 'dir') ~= 7, mkdir(folder); end
end

function out = stripGraphics(out)
    out.figure = [];
    if isstruct(out.topography) && isfield(out.topography, 'figure'), out.topography.figure = []; end
end

function label = sourceLabel(value)
    if ischar(value) || isstring(value), label = char(value); else, label = '<struct>'; end
end

function printSummary(out)
    fprintf('\nOrthogonal tES EEG-control stimulus\n');
    fprintf('  total source current limit: %.4g mA\n', out.totalCurrentMa);
    fprintf('  per-contact current limit: %.4g mA\n', out.maxCurrentPerElectrodeMa);
    fprintf('  weighted topography correlation: %.6g\n', out.weightedTopographyCorrelation);
    fprintf('  ordinary topography correlation: %.6g\n', out.topographyCorrelation);
    fprintf('  predicted separation: %.6g microV\n', 1e6*out.weightedSeparationV);
    fprintf('  alternate recipe:\n');
    for i = 1:numel(out.tesNames)
        if abs(out.alternateCurrentsMa(i)) > 1e-6
            fprintf('    %-20s %+9.5f mA\n', out.tesNames{i}, out.alternateCurrentsMa(i));
        end
    end
    fprintf('  report: %s\n\n', out.reportMat);
end
