function out = acsCompareRoastLeadFieldModels(t1File, leadFieldTagA, leadFieldTagB, varargin)
% ACSCOMPAREROASTLEADFIELDMODELS Compare two ROAST lead-field models.
%
% out = acsCompareRoastLeadFieldModels(t1File, tagA, tagB, 'recipe', recipe)
% reconstructs the electric field produced by the same current recipe in two
% lead-field models, samples model B at the nearest brain nodes to model A's
% sampled brain nodes, and summarizes target and whole-brain differences.
%
% This is intended for comparisons such as warped scalp without titanium vs.
% warped scalp with a titanium headpost, where the meshes may not share node
% indices.
%
% Name-value options:
%   recipe                    : alternating electrode/current cell array [[]]
%   sparseResult              : sparse optimizer output/file used as recipe [[]]
%   recipeName                : label for the recipe ['recipe']
%   modelNames                : two labels for model A/B [{'modelA','modelB'}]
%   targetVoxel               : N x 3 target voxel coordinates [[]]
%   orientation               : N x 3 target field directions [[0 0 1]]
%   targetRadiusMm            : target ROI radius [2]
%   maxSampleNodes            : max brain nodes sampled from model A [50000]
%   nearestChunk              : fallback nearest-neighbor chunk size [64]
%   currentBalanceToleranceMa : tolerated recipe imbalance [1e-6]
%   compareTag                : report/figure tag ['']
%   showFigures               : show comparison figure [true]
%   saveFigures               : save QC PNG [false]
%   saveReport                : save MAT report [true]
%   verbose                   : print summary [true]

    if nargin < 3
        error('acsCompareRoastLeadFieldModels:MissingInputs', ...
            'Provide t1File, leadFieldTagA, and leadFieldTagB.');
    end

    addDependencies();
    opts = parseInputs(varargin{:});
    t1File = char(t1File);
    leadFieldTagA = char(leadFieldTagA);
    leadFieldTagB = char(leadFieldTagB);
    sparse = readSparseResult(opts.sparseResult);
    opts = fillOptionsFromSparse(opts, sparse);
    if isempty(opts.recipe)
        error('acsCompareRoastLeadFieldModels:MissingRecipe', ...
            'Provide a recipe or sparseResult with a recipe field.');
    end

    [folder, stem] = fileparts(t1File);
    if isempty(opts.compareTag)
        opts.compareTag = compactDefaultCompareTag( ...
            leadFieldTagA, leadFieldTagB, opts.recipeName);
    else
        opts.compareTag = safeTag(opts.compareTag);
    end

    modelA = reconstructModel(t1File, leadFieldTagA, opts.recipe, opts);
    modelB = reconstructModel(t1File, leadFieldTagB, opts.recipe, opts);
    validateCandidateMatch(modelA, modelB);

    sample = compareOnCommonBrainSamples(modelA, modelB, opts);
    target = compareTargets(t1File, modelA, modelB, opts);
    recipeSummary = summarizeRecipe(opts.recipe, modelA.leadField);
    metrics = summarizeSampleDifferences(sample);

    fig = [];
    qcFigure = '';
    if opts.showFigures || opts.saveFigures
        figVisible = 'off';
        if opts.showFigures
            figVisible = 'on';
        end
        fig = makeFigure(sample, target, metrics, recipeSummary, modelA, modelB, opts, figVisible);
        if opts.saveFigures
            qcDir = fullfile(folder, 'qc');
            ensureDir(qcDir);
            qcFigure = fullfile(qcDir, sprintf('%s_%s.png', stem, opts.compareTag));
            saveQcFigure(fig, qcFigure);
        end
        if ~opts.showFigures && isgraphics(fig)
            close(fig);
            fig = [];
        end
    end

    out = struct();
    out.createdOn = char(datetime('now'));
    out.t1File = t1File;
    out.leadFieldTags = {leadFieldTagA, leadFieldTagB};
    out.modelNames = opts.modelNames;
    out.recipeName = opts.recipeName;
    out.recipe = opts.recipe;
    out.recipeSummary = recipeSummary;
    out.target = target;
    out.sample = rmfieldIfPresent(sample, {'fieldA', 'fieldB'});
    out.metrics = metrics;
    out.modelA = stripModelForOutput(modelA);
    out.modelB = stripModelForOutput(modelB);
    out.compareTag = opts.compareTag;
    out.reportMat = fullfile(folder, sprintf('%s_%s.mat', stem, opts.compareTag));
    out.qcFigure = qcFigure;
    out.figure = fig;

    if opts.saveReport
        outForSave = out;
        if isfield(outForSave, 'figure')
            outForSave = rmfield(outForSave, 'figure');
        end
        try
            save(out.reportMat, 'outForSave', '-v7.3');
        catch ME
            warning('acsCompareRoastLeadFieldModels:SaveFailed', ...
                ['Could not save comparison report to "%s". Returning ', ...
                 'the output struct in memory. Original error: %s'], ...
                out.reportMat, ME.message);
            out.reportSaveError = ME.message;
        end
    end
    if opts.verbose
        printSummary(out);
    end
end

function opts = parseInputs(varargin)
    p = inputParser;
    p.FunctionName = 'acsCompareRoastLeadFieldModels';
    addParameter(p, 'recipe', {}, @(x) isempty(x) || iscell(x));
    addParameter(p, 'sparseResult', [], @(x) isempty(x) || isstruct(x) || ischar(x) || isstring(x));
    addParameter(p, 'recipeName', 'recipe', @(x) ischar(x) || isstring(x));
    addParameter(p, 'modelNames', {'modelA', 'modelB'}, @(x) iscell(x) || isstring(x));
    addParameter(p, 'targetVoxel', [], @(x) isempty(x) || isnumeric(x));
    addParameter(p, 'orientation', [0 0 1], @(x) isnumeric(x) && size(x, 2) == 3);
    addParameter(p, 'targetRadiusMm', 2, @isPositiveScalar);
    addParameter(p, 'maxSampleNodes', 50000, @isPositiveScalar);
    addParameter(p, 'nearestChunk', 64, @isPositiveScalar);
    addParameter(p, 'currentBalanceToleranceMa', 1e-6, @isPositiveScalar);
    addParameter(p, 'compareTag', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'showFigures', true, @isBoolLike);
    addParameter(p, 'saveFigures', false, @isBoolLike);
    addParameter(p, 'saveReport', true, @isBoolLike);
    addParameter(p, 'verbose', true, @isBoolLike);
    parse(p, varargin{:});

    opts = p.Results;
    opts.recipeName = safeTag(opts.recipeName);
    opts.modelNames = cellstr(opts.modelNames(:));
    if numel(opts.modelNames) ~= 2
        error('acsCompareRoastLeadFieldModels:BadModelNames', ...
            'modelNames must contain exactly two labels.');
    end
    opts.targetVoxel = validateTargetVoxel(opts.targetVoxel);
    opts.orientation = double(opts.orientation);
    opts.targetRadiusMm = double(opts.targetRadiusMm);
    opts.maxSampleNodes = round(double(opts.maxSampleNodes));
    opts.nearestChunk = round(double(opts.nearestChunk));
    opts.currentBalanceToleranceMa = double(opts.currentBalanceToleranceMa);
    opts.compareTag = char(opts.compareTag);
    opts.showFigures = logical(opts.showFigures);
    opts.saveFigures = logical(opts.saveFigures);
    opts.saveReport = logical(opts.saveReport);
    opts.verbose = logical(opts.verbose);
end

function tf = isBoolLike(x)
    tf = (islogical(x) || isnumeric(x)) && isscalar(x);
end

function tf = isPositiveScalar(x)
    tf = isnumeric(x) && isscalar(x) && isfinite(x) && x > 0;
end

function addDependencies()
    repoRoot = fileparts(fileparts(mfilename('fullpath')));
    addpath(repoRoot);
    addpath(fullfile(repoRoot, 'acsUtilities'));
    spmDir = fullfile(repoRoot, 'lib', 'spm12');
    if exist(spmDir, 'dir') == 7
        addpath(spmDir);
    end
end

function sparse = readSparseResult(value)
    sparse = struct();
    if isempty(value)
        return;
    end
    if ischar(value) || isstring(value)
        raw = load(char(value));
        sparse = firstStruct(raw);
    elseif isstruct(value)
        sparse = value;
        if isfield(sparse, 'out') && isstruct(sparse.out)
            sparse = sparse.out;
        elseif isfield(sparse, 'outForSave') && isstruct(sparse.outForSave)
            sparse = sparse.outForSave;
        end
    else
        error('acsCompareRoastLeadFieldModels:BadSparseResult', ...
            'sparseResult must be a struct or MAT file.');
    end
end

function opts = fillOptionsFromSparse(opts, sparse)
    if isempty(fieldnames(sparse))
        return;
    end
    if isempty(opts.recipe) && isfield(sparse, 'recipe') && ~isempty(sparse.recipe)
        opts.recipe = sparse.recipe;
    end
    if isempty(opts.targetVoxel) && isfield(sparse, 'targetVoxel')
        opts.targetVoxel = validateTargetVoxel(sparse.targetVoxel);
    end
    if isfield(sparse, 'orientation') && ~isempty(sparse.orientation) && ...
            isequal(opts.orientation, [0 0 1])
        opts.orientation = double(sparse.orientation);
    end
    if isfield(sparse, 'targetRadiusMm') && ~isempty(sparse.targetRadiusMm) && ...
            opts.targetRadiusMm == 2
        opts.targetRadiusMm = double(sparse.targetRadiusMm);
    end
    if strcmp(opts.recipeName, 'recipe') && isfield(sparse, 'targetingTag')
        opts.recipeName = safeTag(sparse.targetingTag);
    end
end

function model = reconstructModel(t1File, leadFieldTag, recipe, opts)
    [folder, stem] = fileparts(t1File);
    resultFile = fullfile(folder, [stem '_' leadFieldTag '_roastResult.mat']);
    optionsFile = fullfile(folder, [stem '_' leadFieldTag '_roastOptions.mat']);
    meshFile = fullfile(folder, [stem '_' leadFieldTag '.mat']);
    requireFile(resultFile);
    requireFile(optionsFile);
    requireFile(meshFile);

    optionsData = load(optionsFile, 'opt');
    if ~isfield(optionsData, 'opt') || ~isfield(optionsData.opt, 'leadField')
        error('acsCompareRoastLeadFieldModels:MissingLeadFieldMetadata', ...
            'Missing leadField metadata in %s.', optionsFile);
    end
    leadField = optionsData.opt.leadField;
    meshData = load(meshFile, 'node', 'elem');
    if ~isfield(meshData, 'node') || ~isfield(meshData, 'elem')
        error('acsCompareRoastLeadFieldModels:MissingMeshData', ...
            'Mesh file must contain node and elem: %s', meshFile);
    end
    brainNodes = findBrainNodes(meshData.elem);
    [currentsByElectrode, coefficients] = prepareCurrents(recipe, leadField, opts);

    resultData = load(resultFile, 'A_all');
    if ~isfield(resultData, 'A_all')
        error('acsCompareRoastLeadFieldModels:MissingLeadFieldMatrix', ...
            'Missing A_all in %s.', resultFile);
    end
    if size(resultData.A_all, 3) ~= numel(leadField.stimulusElectrodeNames)
        error('acsCompareRoastLeadFieldModels:BadMatrixSize', ...
            'A_all basis count does not match lead-field metadata for %s.', leadFieldTag);
    end
    field = reconstructMeshField(resultData.A_all, coefficients);

    model = struct();
    model.tag = leadFieldTag;
    model.resultFile = resultFile;
    model.optionsFile = optionsFile;
    model.meshFile = meshFile;
    model.leadField = leadField;
    model.options = optionsData.opt;
    model.node = double(meshData.node(:, 1:3));
    model.brainNodes = brainNodes(:);
    model.brainNodeCount = numel(brainNodes);
    model.nodeCount = size(model.node, 1);
    model.elemCount = size(meshData.elem, 1);
    model.currentsByElectrodeMa = currentsByElectrode;
    model.basisCoefficientsMa = coefficients;
    model.fieldVm = field;
end

function brainNodes = findBrainNodes(elem)
    if size(elem, 2) < 5
        error('acsCompareRoastLeadFieldModels:BadElem', ...
            'Mesh elem array must have tissue labels in column 5.');
    end
    brainElem = elem(elem(:, 5) == 1 | elem(:, 5) == 2, 1:4);
    if isempty(brainElem)
        error('acsCompareRoastLeadFieldModels:NoBrainNodes', ...
            'Mesh contains no white/gray matter elements.');
    end
    brainNodes = unique(brainElem(:));
end

function [currentsByElectrode, coefficients] = prepareCurrents(recipe, leadField, opts)
    [names, currents] = parseRecipe(recipe);
    allNames = cellstr(leadField.electrodeNames(:));
    stimulusNames = cellstr(leadField.stimulusElectrodeNames(:));
    if abs(sum(currents)) > opts.currentBalanceToleranceMa
        error('acsCompareRoastLeadFieldModels:UnbalancedRecipe', ...
            'Recipe currents sum to %.6g mA.', sum(currents));
    elseif abs(sum(currents)) > 0
        currents(end) = currents(end) - sum(currents);
    end
    if numel(unique(lower(string(names)))) ~= numel(names)
        error('acsCompareRoastLeadFieldModels:DuplicateElectrodes', ...
            'Recipe contains duplicated electrode names.');
    end
    if ~all(ismember(lower(string(names)), lower(string(allNames))))
        error('acsCompareRoastLeadFieldModels:UnknownElectrode', ...
            'Recipe contains electrodes outside the lead-field candidate list.');
    end

    currentsByElectrode = zeros(numel(allNames), 1);
    for i = 1:numel(names)
        idx = find(strcmpi(names{i}, allNames), 1);
        currentsByElectrode(idx) = currents(i);
    end

    coefficients = zeros(numel(stimulusNames), 1);
    for i = 1:numel(stimulusNames)
        idx = find(strcmpi(stimulusNames{i}, allNames), 1);
        coefficients(i) = currentsByElectrode(idx);
    end
    refIdx = find(strcmpi(leadField.referenceElectrode, allNames), 1);
    impliedReferenceCurrent = -sum(coefficients);
    if abs(currentsByElectrode(refIdx) - impliedReferenceCurrent) > ...
            opts.currentBalanceToleranceMa
        error('acsCompareRoastLeadFieldModels:ReferenceMismatch', ...
            ['Recipe reference current is %.6g mA, while the lead-field ', ...
             'basis implies %.6g mA.'], ...
            currentsByElectrode(refIdx), impliedReferenceCurrent);
    end
end

function [names, currents] = parseRecipe(recipe)
    if ~iscell(recipe) || mod(numel(recipe), 2) ~= 0
        error('acsCompareRoastLeadFieldModels:BadRecipe', ...
            'recipe must be an alternating electrode/current cell array.');
    end
    names = recipe(1:2:end);
    names = cellfun(@char, names(:), 'UniformOutput', false);
    try
        currents = cell2mat(recipe(2:2:end));
    catch
        error('acsCompareRoastLeadFieldModels:BadRecipeCurrents', ...
            'Recipe currents must be numeric scalars.');
    end
    currents = double(currents(:));
    if numel(currents) ~= numel(names) || any(~isfinite(currents))
        error('acsCompareRoastLeadFieldModels:BadRecipeCurrents', ...
            'Recipe currents must be finite numeric scalars.');
    end
end

function field = reconstructMeshField(A, coefficients)
    field = zeros(size(A, 1), 3);
    for i = 1:numel(coefficients)
        if coefficients(i) ~= 0
            field = field + double(A(:, :, i)) * coefficients(i);
        end
    end
end

function validateCandidateMatch(modelA, modelB)
    namesA = cellstr(modelA.leadField.electrodeNames(:));
    namesB = cellstr(modelB.leadField.electrodeNames(:));
    if numel(namesA) ~= numel(namesB) || any(~strcmpi(namesA, namesB))
        error('acsCompareRoastLeadFieldModels:CandidateMismatch', ...
            'Lead-field models do not report the same electrode candidate names.');
    end
end

function sample = compareOnCommonBrainSamples(modelA, modelB, opts)
    sampleNodesA = deterministicSample(modelA.brainNodes, opts.maxSampleNodes);
    samplePoints = modelA.node(sampleNodesA, :);
    brainPointsB = modelB.node(modelB.brainNodes, :);
    [idxBLocal, nearestDistance] = nearestRows(brainPointsB, samplePoints, opts.nearestChunk);
    sampleNodesB = modelB.brainNodes(idxBLocal);

    fieldA = modelA.fieldVm(sampleNodesA, :);
    fieldB = modelB.fieldVm(sampleNodesB, :);
    sample = struct();
    sample.nodeA = sampleNodesA(:);
    sample.nodeB = sampleNodesB(:);
    sample.pointsMm = samplePoints;
    sample.nearestDistanceMm = nearestDistance(:);
    sample.fieldA = fieldA;
    sample.fieldB = fieldB;
    sample.magnitudeA = sqrt(sum(fieldA .^ 2, 2));
    sample.magnitudeB = sqrt(sum(fieldB .^ 2, 2));
    sample.vectorDifference = fieldB - fieldA;
    sample.vectorErrorMagnitude = sqrt(sum(sample.vectorDifference .^ 2, 2));
    sample.magnitudeDifference = sample.magnitudeB - sample.magnitudeA;
    sample.sampleCount = numel(sampleNodesA);
    sample.maxSampleNodes = opts.maxSampleNodes;
end

function rows = deterministicSample(rows, maxRows)
    rows = rows(:);
    if numel(rows) <= maxRows
        return;
    end
    idx = unique(round(linspace(1, numel(rows), maxRows)));
    rows = rows(idx);
end

function [idx, dist] = nearestRows(reference, query, chunk)
    if exist('knnsearch', 'file') == 2
        [idx, dist] = knnsearch(reference, query);
        return;
    end
    chunk = max(1, round(chunk));
    idx = zeros(size(query, 1), 1);
    dist2 = zeros(size(query, 1), 1);
    for a = 1:chunk:size(query, 1)
        b = min(size(query, 1), a + chunk - 1);
        D = squaredDistanceRows(query(a:b, :), reference);
        [dist2Local, idxLocal] = min(D, [], 2);
        idx(a:b) = idxLocal;
        dist2(a:b) = dist2Local;
    end
    dist = sqrt(max(dist2, 0));
end

function D = squaredDistanceRows(A, B)
    D = bsxfun(@plus, sum(A .^ 2, 2), sum(B .^ 2, 2)') - 2 * (A * B');
    D(D < 0) = 0;
end

function target = compareTargets(t1File, modelA, modelB, opts)
    target = struct('available', false);
    if isempty(opts.targetVoxel)
        return;
    end
    V = spm_vol(t1File);
    voxelSize = [V.mat(1, 1), V.mat(2, 2), V.mat(3, 3)];
    targetVoxel = validateTargetVoxel(opts.targetVoxel);
    orientation = normalizeOrientations(opts.orientation, size(targetVoxel, 1));
    targetMm = bsxfun(@times, targetVoxel, voxelSize);

    target.available = true;
    target.targetVoxel = targetVoxel;
    target.targetMm = targetMm;
    target.orientation = orientation;
    target.radiusMm = opts.targetRadiusMm;
    target.modelA = targetMetricsForModel(modelA, targetMm, orientation, opts);
    target.modelB = targetMetricsForModel(modelB, targetMm, orientation, opts);
    target.projectedDifferenceVm = ...
        target.modelB.projectedFieldVm - target.modelA.projectedFieldVm;
    target.projectedPercentChange = percentChange( ...
        target.modelA.projectedFieldVm, target.modelB.projectedFieldVm);
    target.magnitudeDifferenceVm = ...
        target.modelB.meanMagnitudeVm - target.modelA.meanMagnitudeVm;
    target.magnitudePercentChange = percentChange( ...
        target.modelA.meanMagnitudeVm, target.modelB.meanMagnitudeVm);
end

function metrics = targetMetricsForModel(model, targetMm, orientation, opts)
    nTargets = size(targetMm, 1);
    metrics = struct();
    metrics.nodeCounts = zeros(nTargets, 1);
    metrics.meanFieldVm = zeros(nTargets, 3);
    metrics.projectedFieldVm = zeros(nTargets, 1);
    metrics.meanMagnitudeVm = zeros(nTargets, 1);
    metrics.closestNodeDistanceMm = zeros(nTargets, 1);
    for i = 1:nTargets
        brainPoints = model.node(model.brainNodes, :);
        delta = bsxfun(@minus, brainPoints, targetMm(i, :));
        d = sqrt(sum(delta .^ 2, 2));
        rowsLocal = find(d <= opts.targetRadiusMm);
        if isempty(rowsLocal)
            [~, closest] = min(d);
            rowsLocal = closest;
        end
        rows = model.brainNodes(rowsLocal);
        field = model.fieldVm(rows, :);
        metrics.nodeCounts(i) = numel(rows);
        metrics.meanFieldVm(i, :) = mean(field, 1);
        metrics.projectedFieldVm(i) = dot(metrics.meanFieldVm(i, :), orientation(i, :));
        metrics.meanMagnitudeVm(i) = mean(sqrt(sum(field .^ 2, 2)));
        metrics.closestNodeDistanceMm(i) = min(d);
    end
end

function metrics = summarizeSampleDifferences(sample)
    magA = sample.magnitudeA;
    magB = sample.magnitudeB;
    err = sample.vectorErrorMagnitude;
    magDiff = sample.magnitudeDifference;
    metrics = struct();
    metrics.sampleCount = sample.sampleCount;
    metrics.vectorRmseVm = sqrt(mean(err .^ 2));
    metrics.relativeVectorRmse = metrics.vectorRmseVm / rmsSafe(magA);
    metrics.vectorErrorMedianVm = median(err);
    metrics.vectorErrorP95Vm = percentileLocal(err, 95);
    metrics.vectorErrorMaxVm = max(err);
    metrics.magnitudeRmseVm = sqrt(mean(magDiff .^ 2));
    metrics.relativeMagnitudeRmse = metrics.magnitudeRmseVm / rmsSafe(magA);
    metrics.magnitudeDifferenceMedianVm = median(magDiff);
    metrics.magnitudeDifferenceP95AbsVm = percentileLocal(abs(magDiff), 95);
    metrics.magnitudeCorrelation = corrSafe(magA, magB);
    metrics.vectorComponentCorrelation = corrSafe(sample.fieldA(:), sample.fieldB(:));
    metrics.nearestDistanceMedianMm = median(sample.nearestDistanceMm);
    metrics.nearestDistanceP95Mm = percentileLocal(sample.nearestDistanceMm, 95);
    metrics.nearestDistanceMaxMm = max(sample.nearestDistanceMm);
end

function recipeSummary = summarizeRecipe(recipe, leadField)
    [names, currents] = parseRecipe(recipe);
    recipeSummary = struct();
    recipeSummary.names = names;
    recipeSummary.currentsMa = currents;
    recipeSummary.totalAnodalCurrentMa = sum(currents(currents > 0));
    recipeSummary.totalCathodalCurrentMa = -sum(currents(currents < 0));
    recipeSummary.netCurrentMa = sum(currents);
    recipeSummary.referenceElectrode = leadField.referenceElectrode;
end

function fig = makeFigure(sample, target, metrics, recipeSummary, modelA, modelB, opts, visible)
    fig = figure('Name', ['Lead-field model comparison: ' opts.recipeName], ...
        'Color', 'w', 'Visible', visible, 'Position', [80 80 1250 760]);
    tiledlayout(fig, 2, 2, 'Padding', 'compact', 'TileSpacing', 'compact');

    ax1 = nexttile;
    if isfield(target, 'available') && target.available
        bar(ax1, [target.modelA.projectedFieldVm(:), target.modelB.projectedFieldVm(:)]);
        legend(ax1, opts.modelNames, 'Location', 'best', 'Interpreter', 'none');
        xlabel(ax1, 'Target');
        ylabel(ax1, 'Projected field (V/m)');
        title(ax1, 'Target directional field');
        grid(ax1, 'on');
    else
        axis(ax1, 'off');
        text(ax1, 0.5, 0.5, 'No targetVoxel supplied', ...
            'HorizontalAlignment', 'center');
    end

    ax2 = nexttile;
    scatterCount = min(5000, numel(sample.magnitudeA));
    rows = deterministicSample((1:numel(sample.magnitudeA))', scatterCount);
    scatter(ax2, sample.magnitudeA(rows), sample.magnitudeB(rows), 8, ...
        sample.nearestDistanceMm(rows), 'filled');
    hold(ax2, 'on');
    lim = [0 max([sample.magnitudeA(rows); sample.magnitudeB(rows); eps])];
    plot(ax2, lim, lim, 'k--');
    xlim(ax2, lim);
    ylim(ax2, lim);
    xlabel(ax2, [opts.modelNames{1} ' |E| (V/m)'], 'Interpreter', 'none');
    ylabel(ax2, [opts.modelNames{2} ' |E| (V/m)'], 'Interpreter', 'none');
    title(ax2, 'Sampled brain field magnitudes');
    colorbar(ax2);
    grid(ax2, 'on');

    ax3 = nexttile;
    histogram(ax3, sample.vectorErrorMagnitude, 80);
    xlabel(ax3, 'Vector |difference| (V/m)');
    ylabel(ax3, 'Sampled brain nodes');
    title(ax3, 'Field-vector differences');
    grid(ax3, 'on');

    ax4 = nexttile;
    axis(ax4, 'off');
    lines = { ...
        sprintf('%s vs %s', opts.modelNames{1}, opts.modelNames{2}), ...
        sprintf('Recipe: %s (%d electrodes)', opts.recipeName, numel(recipeSummary.names)), ...
        sprintf('Model A: %s', modelA.tag), ...
        sprintf('Model B: %s', modelB.tag), ...
        '', ...
        sprintf('Samples: %d brain nodes', metrics.sampleCount), ...
        sprintf('Vector RMSE: %.5g V/m', metrics.vectorRmseVm), ...
        sprintf('Relative vector RMSE: %.5g', metrics.relativeVectorRmse), ...
        sprintf('Magnitude RMSE: %.5g V/m', metrics.magnitudeRmseVm), ...
        sprintf('Magnitude corr: %.6f', metrics.magnitudeCorrelation), ...
        sprintf('Vector-component corr: %.6f', metrics.vectorComponentCorrelation), ...
        sprintf('NN distance median/p95/max: %.3g / %.3g / %.3g mm', ...
        metrics.nearestDistanceMedianMm, metrics.nearestDistanceP95Mm, ...
        metrics.nearestDistanceMaxMm)};
    if isfield(target, 'available') && target.available
        lines{end + 1} = ''; %#ok<AGROW>
        lines{end + 1} = sprintf('Target projected delta mean: %.5g V/m', ...
            mean(target.projectedDifferenceVm)); %#ok<AGROW>
        lines{end + 1} = sprintf('Target projected %% change mean: %.3g %%', ...
            mean(target.projectedPercentChange)); %#ok<AGROW>
    end
    text(ax4, 0, 1, strjoin(lines, newline), ...
        'Units', 'normalized', 'VerticalAlignment', 'top', ...
        'Interpreter', 'none', 'FontName', 'Consolas');

    sgtitle(fig, ['ROAST lead-field model comparison: ' opts.recipeName], ...
        'Interpreter', 'none');
end

function out = stripModelForOutput(model)
    out = rmfieldIfPresent(model, {'node', 'fieldVm'});
    if isfield(out, 'options')
        out.options = rmfieldIfPresent(out.options, {'leadField'});
    end
end

function targetVoxel = validateTargetVoxel(targetVoxel)
    if isempty(targetVoxel)
        return;
    end
    if size(targetVoxel, 2) ~= 3
        error('acsCompareRoastLeadFieldModels:BadTargetVoxel', ...
            'targetVoxel must be N x 3.');
    end
    targetVoxel = double(targetVoxel);
    if any(~isfinite(targetVoxel(:)))
        error('acsCompareRoastLeadFieldModels:BadTargetVoxel', ...
            'targetVoxel must contain finite coordinates.');
    end
end

function orientation = normalizeOrientations(orientation, nTargets)
    orientation = double(orientation);
    if size(orientation, 1) == 1 && nTargets > 1
        orientation = repmat(orientation, nTargets, 1);
    end
    if size(orientation, 1) ~= nTargets || size(orientation, 2) ~= 3
        error('acsCompareRoastLeadFieldModels:BadOrientation', ...
            'orientation must be 1 x 3 or N x 3.');
    end
    n = sqrt(sum(orientation .^ 2, 2));
    if any(n <= eps)
        error('acsCompareRoastLeadFieldModels:BadOrientation', ...
            'orientation rows must be nonzero.');
    end
    orientation = bsxfun(@rdivide, orientation, n);
end

function pc = percentChange(a, b)
    pc = 100 * (b - a) ./ max(abs(a), eps);
end

function r = corrSafe(a, b)
    a = double(a(:));
    b = double(b(:));
    keep = isfinite(a) & isfinite(b);
    a = a(keep);
    b = b(keep);
    if numel(a) < 2 || std(a) <= eps || std(b) <= eps
        r = NaN;
        return;
    end
    C = corrcoef(a, b);
    r = C(1, 2);
end

function value = rmsSafe(x)
    x = double(x(:));
    x = x(isfinite(x));
    if isempty(x)
        value = NaN;
    else
        value = sqrt(mean(x .^ 2));
    end
    if value <= eps
        value = eps;
    end
end

function value = percentileLocal(x, pct)
    x = sort(double(x(:)));
    x = x(isfinite(x));
    if isempty(x)
        value = NaN;
        return;
    end
    pct = max(0, min(100, double(pct)));
    pos = 1 + (numel(x) - 1) * pct / 100;
    lo = floor(pos);
    hi = ceil(pos);
    if lo == hi
        value = x(lo);
    else
        value = x(lo) + (pos - lo) * (x(hi) - x(lo));
    end
end

function tag = safeTag(tag)
    tag = regexprep(strtrim(char(tag)), '[^A-Za-z0-9_-]+', '_');
    tag = regexprep(tag, '_+', '_');
    tag = regexprep(tag, '^_+|_+$', '');
    if isempty(tag)
        tag = 'leadFieldCompare';
    end
end

function tag = compactDefaultCompareTag(tagA, tagB, recipeName)
    tagA = compactModelTag(tagA);
    tagB = compactModelTag(tagB);
    recipeName = safeTag(recipeName);
    tag = safeTag(sprintf('lfcmp_%s_vs_%s_%s', tagA, tagB, recipeName));
    maxChars = 90;
    if numel(tag) > maxChars
        tag = tag(1:maxChars);
        tag = regexprep(tag, '_+$', '');
    end
end

function tag = compactModelTag(tag)
    tag = safeTag(tag);
    if ~isempty(regexpi(tag, 'noTi', 'once'))
        tag = 'noTi';
    elseif ~isempty(regexpi(tag, 'withTi', 'once')) || ...
            ~isempty(regexpi(tag, 'headpostTi', 'once'))
        tag = 'withTi';
    elseif numel(tag) > 28
        tag = tag(max(1, end - 27):end);
    end
end

function saveQcFigure(fig, fileName)
    try
        exportgraphics(fig, fileName, 'Resolution', 180);
    catch
        saveas(fig, fileName);
    end
end

function ensureDir(folder)
    if exist(folder, 'dir') ~= 7
        mkdir(folder);
    end
end

function requireFile(fileName)
    if exist(fileName, 'file') ~= 2
        error('acsCompareRoastLeadFieldModels:MissingFile', ...
            'Required file not found: %s', fileName);
    end
end

function S = firstStruct(raw)
    preferred = {'out', 'outForSave'};
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
    error('acsCompareRoastLeadFieldModels:NoStructInFile', ...
        'Could not find a struct in the supplied MAT file.');
end

function S = rmfieldIfPresent(S, fields)
    for i = 1:numel(fields)
        if isfield(S, fields{i})
            S = rmfield(S, fields{i});
        end
    end
end

function printSummary(out)
    fprintf('\nROAST lead-field model comparison\n');
    fprintf('  recipe: %s\n', out.recipeName);
    fprintf('  %s: %s\n', out.modelNames{1}, out.leadFieldTags{1});
    fprintf('  %s: %s\n', out.modelNames{2}, out.leadFieldTags{2});
    fprintf('  sampled brain nodes: %d\n', out.metrics.sampleCount);
    fprintf('  vector RMSE: %.6g V/m (relative %.6g)\n', ...
        out.metrics.vectorRmseVm, out.metrics.relativeVectorRmse);
    fprintf('  magnitude RMSE: %.6g V/m (relative %.6g)\n', ...
        out.metrics.magnitudeRmseVm, out.metrics.relativeMagnitudeRmse);
    fprintf('  magnitude correlation: %.9f\n', out.metrics.magnitudeCorrelation);
    fprintf('  nearest-node distance median/p95/max: %.3g / %.3g / %.3g mm\n', ...
        out.metrics.nearestDistanceMedianMm, ...
        out.metrics.nearestDistanceP95Mm, ...
        out.metrics.nearestDistanceMaxMm);
    if isfield(out.target, 'available') && out.target.available
        fprintf('  target projected field %s -> %s: ', ...
            out.modelNames{1}, out.modelNames{2});
        fprintf('%.6g -> %.6g V/m\n', ...
            mean(out.target.modelA.projectedFieldVm), ...
            mean(out.target.modelB.projectedFieldVm));
        fprintf('  target projected percent change: %.3g %%\n', ...
            mean(out.target.projectedPercentChange));
    end
    fprintf('  report: %s\n', out.reportMat);
    if ~isempty(out.qcFigure)
        fprintf('  QC figure: %s\n', out.qcFigure);
    end
end
