function out = acsKernelRegressLeadFieldFeatures(trainPositionsMm, queryPositionsMm, varargin)
% ACSKERNELREGRESSLEADFIELDFEATURES Gaussian RBF regression for lead-field features.
%
% out = acsKernelRegressLeadFieldFeatures(trainPositionsMm, queryPositionsMm)
% returns Gaussian radial-basis interpolation weights from training electrode
% positions to query electrode positions.
%
% For fast surrogate electrode growth, pass reduced lead-field statistics
% instead of full lead-field columns:
%
%   trainingProjection : M x 1 vector, such as Aw' * residual
%   trainingGram       : M x M matrix, such as Aw' * Aw
%
% The predicted query projection is W * trainingProjection, and the predicted
% squared norm is diag(W * trainingGram * W'). These are enough to score the
% one-contact residual improvement expected from a virtual electrode without
% materializing full predicted lead-field columns.
%
% Name-value options:
%   sigmaMm            : Gaussian kernel sigma in mm, or 'auto' ['auto']
%   normalizeWeights   : normalize each query's kernel weights [true]
%   minWeightTotal     : minimum unnormalized weight before warning [eps]
%   leaveOneOut        : compute training leave-one-out diagnostics [true]

    if nargin < 2
        error('acsKernelRegressLeadFieldFeatures:MissingInput', ...
            'Provide training and query positions.');
    end
    opts = parseInputs(varargin{:});
    trainPositionsMm = validatePositions(trainPositionsMm, 'trainPositionsMm');
    queryPositionsMm = validatePositions(queryPositionsMm, 'queryPositionsMm');
    if isempty(trainPositionsMm)
        error('acsKernelRegressLeadFieldFeatures:NoTrainingPoints', ...
            'At least one training position is required.');
    end

    nTrain = size(trainPositionsMm, 1);
    projection = normalizeProjection(opts.trainingProjection, nTrain);
    gram = normalizeGram(opts.trainingGram, nTrain);
    sigmaMm = normalizeSigma(opts.sigmaMm, trainPositionsMm);

    dist2 = pairwiseDistanceSquared(queryPositionsMm, trainPositionsMm);
    rawWeights = exp(-dist2 ./ (2 * sigmaMm ^ 2));
    weightTotal = sum(rawWeights, 2);
    weakRows = weightTotal <= opts.minWeightTotal;
    if any(weakRows)
        warning('acsKernelRegressLeadFieldFeatures:WeakKernelSupport', ...
            '%d query points have very low total kernel support.', nnz(weakRows));
    end
    weights = rawWeights;
    if opts.normalizeWeights
        denom = max(weightTotal, eps);
        weights = bsxfun(@rdivide, rawWeights, denom);
    end

    out = struct();
    out.createdOn = char(datetime('now'));
    out.sigmaMm = sigmaMm;
    out.trainPositionsMm = trainPositionsMm;
    out.queryPositionsMm = queryPositionsMm;
    out.distanceMm = sqrt(dist2);
    out.rawWeights = rawWeights;
    out.weights = weights;
    out.weightTotal = weightTotal;
    out.predictedProjection = [];
    out.predictedNorm2 = [];
    out.residualImprovementScore = [];
    out.preferredCurrentSign = [];
    out.leaveOneOut = struct();

    if ~isempty(projection)
        out.predictedProjection = weights * projection;
        out.preferredCurrentSign = sign(out.predictedProjection);
    end
    if ~isempty(gram)
        out.predictedNorm2 = sum((weights * gram) .* weights, 2);
        out.predictedNorm2 = max(out.predictedNorm2, 0);
    end
    if ~isempty(out.predictedProjection) && ~isempty(out.predictedNorm2)
        denom = max(out.predictedNorm2, eps);
        out.residualImprovementScore = (out.predictedProjection .^ 2) ./ denom;
    end
    if opts.leaveOneOut && ~isempty(gram)
        out.leaveOneOut = leaveOneOutDiagnostics( ...
            trainPositionsMm, projection, gram, sigmaMm, opts);
    end
end

function opts = parseInputs(varargin)
    p = inputParser;
    p.FunctionName = 'acsKernelRegressLeadFieldFeatures';
    addParameter(p, 'trainingProjection', [], ...
        @(x) isempty(x) || (isnumeric(x) && isvector(x) && all(isfinite(x))));
    addParameter(p, 'trainingGram', [], ...
        @(x) isempty(x) || (isnumeric(x) && ismatrix(x) && all(isfinite(x(:)))));
    addParameter(p, 'sigmaMm', 'auto', ...
        @(x) (ischar(x) || isstring(x)) || ...
        (isnumeric(x) && isscalar(x) && isfinite(x) && x > 0));
    addParameter(p, 'normalizeWeights', true, @isBoolLike);
    addParameter(p, 'minWeightTotal', eps, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0);
    addParameter(p, 'leaveOneOut', true, @isBoolLike);
    parse(p, varargin{:});
    opts = p.Results;
    opts.normalizeWeights = logical(opts.normalizeWeights);
    opts.leaveOneOut = logical(opts.leaveOneOut);
end

function tf = isBoolLike(x)
    tf = (islogical(x) || isnumeric(x)) && isscalar(x);
end

function P = validatePositions(P, name)
    validateattributes(P, {'numeric'}, {'2d', 'real', 'finite'}, ...
        mfilename, name);
    P = double(P);
    if size(P, 2) ~= 3
        error('acsKernelRegressLeadFieldFeatures:BadPositions', ...
            '%s must have three columns.', name);
    end
end

function projection = normalizeProjection(projection, nTrain)
    if isempty(projection)
        return;
    end
    projection = double(projection(:));
    if numel(projection) ~= nTrain
        error('acsKernelRegressLeadFieldFeatures:BadProjection', ...
            'trainingProjection must contain one value per training position.');
    end
end

function gram = normalizeGram(gram, nTrain)
    if isempty(gram)
        return;
    end
    gram = double(gram);
    if ~isequal(size(gram), [nTrain nTrain])
        error('acsKernelRegressLeadFieldFeatures:BadGram', ...
            'trainingGram must be M x M for M training positions.');
    end
    gram = (gram + gram') ./ 2;
end

function sigmaMm = normalizeSigma(sigmaIn, trainPositionsMm)
    if isnumeric(sigmaIn)
        sigmaMm = double(sigmaIn);
        return;
    end
    sigmaIn = lower(strtrim(char(sigmaIn)));
    if ~strcmp(sigmaIn, 'auto')
        error('acsKernelRegressLeadFieldFeatures:BadSigma', ...
            'sigmaMm must be positive numeric or ''auto''.');
    end
    if size(trainPositionsMm, 1) == 1
        sigmaMm = 20;
        return;
    end
    D = sqrt(pairwiseDistanceSquared(trainPositionsMm, trainPositionsMm));
    D(D == 0) = inf;
    nearest = min(D, [], 2);
    nearest = nearest(isfinite(nearest) & nearest > 0);
    if isempty(nearest)
        sigmaMm = 20;
    else
        sigmaMm = 1.5 * median(nearest);
    end
    sigmaMm = max(sigmaMm, eps);
end

function D2 = pairwiseDistanceSquared(A, B)
    D2 = bsxfun(@plus, sum(A .^ 2, 2), sum(B .^ 2, 2)') - 2 * (A * B');
    D2 = max(D2, 0);
end

function loo = leaveOneOutDiagnostics(trainPositionsMm, projection, gram, ...
        sigmaMm, opts)
    nTrain = size(trainPositionsMm, 1);
    if nTrain < 3
        loo = struct('relativeColumnError', [], 'medianRelativeColumnError', NaN);
        return;
    end
    D2 = pairwiseDistanceSquared(trainPositionsMm, trainPositionsMm);
    rawWeights = exp(-D2 ./ (2 * sigmaMm ^ 2));
    rawWeights(1:nTrain + 1:end) = 0;
    weights = rawWeights;
    if opts.normalizeWeights
        weights = bsxfun(@rdivide, weights, max(sum(weights, 2), eps));
    end

    colNorm2 = max(diag(gram), eps);
    predNorm2 = sum((weights * gram) .* weights, 2);
    crossTerm = zeros(nTrain, 1);
    for i = 1:nTrain
        crossTerm(i) = weights(i, :) * gram(:, i);
    end
    err2 = max(colNorm2 - 2 * crossTerm + predNorm2, 0);
    relErr = sqrt(err2 ./ colNorm2);

    loo = struct();
    loo.relativeColumnError = relErr;
    loo.medianRelativeColumnError = median(relErr(isfinite(relErr)));
    if ~isempty(projection)
        predProjection = weights * projection;
        loo.projectionError = predProjection - projection;
        loo.medianAbsProjectionError = median(abs(loo.projectionError));
    end
end
