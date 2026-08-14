function [targetOptions, strapExclusion] = acsAddStrapExclusionsToTargetOptions( ...
        targetOptions, earExclusions, varargin)
% ACSADDSTRAPEXCLUSIONSTOTARGETOPTIONS Append conservative chin-strap keepouts.
%
% [targetOptions, strapExclusion] = acsAddStrapExclusionsToTargetOptions(opts, ears)
% adds a chain of spherical exclusions near the anticipated chin-strap roots.
% The spheres are intentionally conservative and are meant for electrode
% placement, not for final STL geometry.

    if nargin < 1 || isempty(targetOptions)
        targetOptions = struct();
    end
    if nargin < 2
        earExclusions = [];
    end
    opts = parseInputs(varargin{:});

    if strcmp(opts.mode, 'none')
        targetOptions = removePriorStrapExclusions(targetOptions);
        strapExclusion = emptyStrapExclusion();
        return;
    end

    if isfield(targetOptions, 'strapExclusionsApplied') && ...
            logical(targetOptions.strapExclusionsApplied)
        if strcmp(opts.mode, 'always')
            targetOptions = removePriorStrapExclusions(targetOptions);
        else
            strapExclusion = getOptionalField(targetOptions, ...
                'strapExclusions', emptyStrapExclusion());
            return;
        end
    end

    earExclusions = resolveEarExclusions(targetOptions, earExclusions);
    strapExclusion = makeStrapExclusion(earExclusions, opts);
    if isempty(strapExclusion.centersMm)
        return;
    end

    [centers, radii] = existingExclusions(targetOptions);
    targetOptions.exclusionCenters = [centers; strapExclusion.centersMm];
    targetOptions.exclusionRadiusMM = [radii; strapExclusion.radiusMm(:)];
    targetOptions.strapExclusionsApplied = true;
    targetOptions.strapExclusions = compactStrapExclusion(strapExclusion);
end

function opts = parseInputs(varargin)
    p = inputParser;
    p.FunctionName = 'acsAddStrapExclusionsToTargetOptions';
    addParameter(p, 'mode', 'auto', @(x) ischar(x) || isstring(x));
    addParameter(p, 'strapMode', 'earRostral', @(x) ischar(x) || isstring(x));
    addParameter(p, 'zBedMm', 0, @(x) isnumeric(x) && isscalar(x) && isfinite(x));
    addParameter(p, 'strapRostralOffsetMm', 0, @isNonnegativeScalar);
    addParameter(p, 'strapWidthMm', 10, @isPositiveScalar);
    addParameter(p, 'holderOutsideDiaMm', 12, @isPositiveScalar);
    addParameter(p, 'strapMarginMm', 2, @isNonnegativeScalar);
    addParameter(p, 'strapExclusionRadiusMm', [], ...
        @(x) isempty(x) || isPositiveScalar(x));
    addParameter(p, 'strapLateralLengthMm', 35, @isPositiveScalar);
    addParameter(p, 'strapSampleSpacingMm', 5, @isPositiveScalar);
    addParameter(p, 'strapZCenterMm', [], @(x) isempty(x) || ...
        (isnumeric(x) && isscalar(x) && isfinite(x)));
    addParameter(p, 'verbose', true, @isBoolLike);
    parse(p, varargin{:});

    opts = p.Results;
    opts.mode = normalizeMode(opts.mode);
    opts.strapMode = char(opts.strapMode);
    opts.zBedMm = double(opts.zBedMm);
    opts.strapRostralOffsetMm = double(opts.strapRostralOffsetMm);
    opts.strapWidthMm = double(opts.strapWidthMm);
    opts.holderOutsideDiaMm = double(opts.holderOutsideDiaMm);
    opts.strapMarginMm = double(opts.strapMarginMm);
    if isempty(opts.strapExclusionRadiusMm)
        opts.strapExclusionRadiusMm = 0.5 * opts.strapWidthMm + ...
            0.5 * opts.holderOutsideDiaMm + opts.strapMarginMm;
    else
        opts.strapExclusionRadiusMm = double(opts.strapExclusionRadiusMm);
    end
    opts.strapLateralLengthMm = double(opts.strapLateralLengthMm);
    opts.strapSampleSpacingMm = double(opts.strapSampleSpacingMm);
    if isempty(opts.strapZCenterMm)
        opts.strapZCenterMm = opts.zBedMm + 0.5 * opts.strapExclusionRadiusMm;
    else
        opts.strapZCenterMm = double(opts.strapZCenterMm);
    end
    opts.verbose = logical(opts.verbose);
end

function mode = normalizeMode(mode)
    mode = lower(strtrim(char(mode)));
    switch mode
        case {'auto', 'always', 'none'}
            return;
        case {'off', 'never', 'ignore'}
            mode = 'none';
        case {'on', 'yes'}
            mode = 'auto';
        otherwise
            error('acsAddStrapExclusionsToTargetOptions:BadMode', ...
                'mode must be ''auto'', ''always'', or ''none''.');
    end
end

function earExclusions = resolveEarExclusions(targetOptions, earExclusions)
    if isempty(earExclusions) && isfield(targetOptions, 'earExclusions')
        earExclusions = targetOptions.earExclusions;
    end
    if isempty(earExclusions)
        earExclusions = struct();
    end
end

function strapExclusion = emptyStrapExclusion()
    strapExclusion = struct( ...
        'source', 'none', ...
        'centersMm', zeros(0, 3), ...
        'radiusMm', zeros(0, 1), ...
        'anchorCentersMm', zeros(0, 3), ...
        'options', struct());
end

function strapExclusion = makeStrapExclusion(earExclusions, opts)
    strapExclusion = emptyStrapExclusion();
    strapExclusion.source = opts.strapMode;
    strapExclusion.options = opts;

    if ~isfield(earExclusions, 'exclusionCenters') || ...
            ~isfield(earExclusions, 'exclusionRadiusMM') || ...
            isempty(earExclusions.exclusionCenters)
        if opts.verbose
            warning('acsAddStrapExclusionsToTargetOptions:NoEarExclusions', ...
                'No ear exclusions were available; strap exclusions were not added.');
        end
        return;
    end

    centers = double(earExclusions.exclusionCenters);
    radii = double(earExclusions.exclusionRadiusMM(:));
    if isscalar(radii) && size(centers, 1) > 1
        radii = repmat(radii, size(centers, 1), 1);
    end
    if numel(radii) ~= size(centers, 1)
        warning('acsAddStrapExclusionsToTargetOptions:BadEarRadii', ...
            'Ear exclusion radii do not match centers; strap exclusions were not added.');
        return;
    end

    [~, leftRow] = min(centers(:, 1));
    [~, rightRow] = max(centers(:, 1));
    rows = unique([leftRow; rightRow], 'stable');
    lateralOffsets = 0:opts.strapSampleSpacingMm:opts.strapLateralLengthMm;
    if lateralOffsets(end) < opts.strapLateralLengthMm
        lateralOffsets(end + 1) = opts.strapLateralLengthMm; %#ok<AGROW>
    end

    allCenters = zeros(0, 3);
    anchors = zeros(numel(rows), 3);
    for i = 1:numel(rows)
        row = rows(i);
        sideSign = sign(centers(row, 1));
        if sideSign == 0
            sideSign = (-1) ^ i;
        end
        anchor = [
            centers(row, 1), ...
            centers(row, 2) + radii(row) + opts.strapRostralOffsetMm, ...
            opts.strapZCenterMm];
        anchors(i, :) = anchor;
        P = repmat(anchor, numel(lateralOffsets), 1);
        P(:, 1) = P(:, 1) + sideSign * lateralOffsets(:);
        allCenters = [allCenters; P]; %#ok<AGROW>
    end

    strapExclusion.centersMm = uniqueRoundedRows(allCenters, 1e-6);
    strapExclusion.radiusMm = repmat(opts.strapExclusionRadiusMm, ...
        size(strapExclusion.centersMm, 1), 1);
    strapExclusion.anchorCentersMm = anchors;
end

function [centers, radii] = existingExclusions(targetOptions)
    centers = zeros(0, 3);
    radii = zeros(0, 1);
    if isfield(targetOptions, 'exclusionCenters') && ...
            ~isempty(targetOptions.exclusionCenters)
        centers = double(targetOptions.exclusionCenters);
        if size(centers, 2) ~= 3
            error('acsAddStrapExclusionsToTargetOptions:BadExclusionCenters', ...
                'exclusionCenters must be N x 3.');
        end
        if ~isfield(targetOptions, 'exclusionRadiusMM')
            error('acsAddStrapExclusionsToTargetOptions:MissingExclusionRadius', ...
                'Set exclusionRadiusMM for existing exclusion centers.');
        end
        radii = expandRadii(targetOptions.exclusionRadiusMM, size(centers, 1));
    end
end

function radii = expandRadii(value, n)
    radii = double(value(:));
    if isempty(radii) && n == 0
        radii = zeros(0, 1);
    elseif isscalar(radii)
        radii = repmat(radii, n, 1);
    elseif numel(radii) ~= n
        error('acsAddStrapExclusionsToTargetOptions:BadExclusionRadius', ...
            'exclusionRadiusMM must be scalar or have one value per center.');
    end
end

function targetOptions = removePriorStrapExclusions(targetOptions)
    prior = getOptionalField(targetOptions, 'strapExclusions', emptyStrapExclusion());
    if isfield(prior, 'centersMm') && isfield(targetOptions, 'exclusionCenters')
        centers = double(targetOptions.exclusionCenters);
        radii = expandRadii(targetOptions.exclusionRadiusMM, size(centers, 1));
        priorCenters = double(prior.centersMm);
        keep = true(size(centers, 1), 1);
        for i = 1:size(priorCenters, 1)
            d = sqrt(sum((centers - priorCenters(i, :)) .^ 2, 2));
            idx = find(d < 1e-6, 1);
            if ~isempty(idx)
                keep(idx) = false;
            end
        end
        targetOptions.exclusionCenters = centers(keep, :);
        targetOptions.exclusionRadiusMM = radii(keep);
    end
    fields = {'strapExclusions', 'strapExclusionsApplied'};
    for i = 1:numel(fields)
        if isfield(targetOptions, fields{i})
            targetOptions = rmfield(targetOptions, fields{i});
        end
    end
end

function compact = compactStrapExclusion(strapExclusion)
    compact = strapExclusion;
    if isfield(compact, 'options')
        compact = rmfield(compact, 'options');
    end
end

function rows = uniqueRoundedRows(P, tol)
    if isempty(P)
        rows = P;
        return;
    end
    scale = 1 / tol;
    [~, idx] = unique(round(P * scale), 'rows', 'stable');
    rows = P(idx, :);
end

function value = getOptionalField(S, fieldName, defaultValue)
    if isstruct(S) && isfield(S, fieldName)
        value = S.(fieldName);
    else
        value = defaultValue;
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
