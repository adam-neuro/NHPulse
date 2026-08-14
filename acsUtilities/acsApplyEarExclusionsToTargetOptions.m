function [targetOptions, earExclusions] = acsApplyEarExclusionsToTargetOptions( ...
        targetOptions, layoutOrMesh, varargin)
% ACSAPPLYEAREXCLUSIONSTOTARGETOPTIONS Add mesh-specific ear exclusions.
%
% [targetOptions, earExclusions] = acsApplyEarExclusionsToTargetOptions(opts, layout)
% removes legacy line-based ear exclusions, loads or prompts for saved
% acsSelectEarExclusionSpheres output, and appends the resulting sphere
% exclusions to opts.exclusionCenters/exclusionRadiusMM. Mesh-specific
% painted exclusions are appended to opts.customExclusionVertexInd.
%
% Name-value options:
%   editMode    : 'auto', 'always', or 'never' ['auto']
%   outputFile  : explicit ear exclusion MAT file ['']
%   showFigures : open selector when editMode requires it [true]
%   saveFigures : save selector QC [false]
%   showStrapPreview      : preview chin-strap keepout in selector [true]
%   strapRostralOffsetMm  : strap root offset rostral to ear edge [0]
%   strapWidthMm          : nominal chin-strap width for keepout [10]
%   strapMarginMm         : extra strap/electrode placement margin [2]
%   strapExclusionRadiusMm: override preview sphere radius [[]]
%   strapLateralLengthMm  : lateral preview length from each ear [35]
%   strapSampleSpacingMm  : preview spacing along strap root [5]
%   holderOutsideDiaMm    : electrode holder diameter used in keepout [12]
%   zBedMm                : printer bed plane used for strap preview [0]
%   verbose     : print progress [true]

    if nargin < 1 || isempty(targetOptions)
        targetOptions = struct();
    end
    opts = parseInputs(varargin{:});

    targetOptions = stripLegacyEarLineOptions(targetOptions);
    if isfield(targetOptions, 'earExclusionsApplied') && ...
            logical(targetOptions.earExclusionsApplied)
        if strcmp(opts.editMode, 'always') || ~isempty(opts.outputFile)
            targetOptions = removePriorEarExclusions(targetOptions);
        else
            earExclusions = getOptionalField(targetOptions, 'earExclusions', struct());
            return;
        end
    end

    shouldLoadSaved = ~isempty(opts.outputFile) && ...
        ~strcmp(opts.editMode, 'always') && ...
        (strcmp(opts.editMode, 'never') || exist(opts.outputFile, 'file') == 2);
    if shouldLoadSaved
        earExclusions = loadSavedEarExclusionsForCurrentMesh( ...
            opts.outputFile, layoutOrMesh, opts);
    else
        earArgs = { ...
            'editMode', opts.editMode, ...
            'outputFile', opts.outputFile, ...
            'showFigures', opts.showFigures, ...
            'saveFigures', opts.saveFigures, ...
            'showStrapPreview', opts.showStrapPreview, ...
            'strapRostralOffsetMm', opts.strapRostralOffsetMm, ...
            'strapWidthMm', opts.strapWidthMm, ...
            'holderOutsideDiaMm', opts.holderOutsideDiaMm, ...
            'strapMarginMm', opts.strapMarginMm, ...
            'strapExclusionRadiusMm', opts.strapExclusionRadiusMm, ...
            'strapLateralLengthMm', opts.strapLateralLengthMm, ...
            'strapSampleSpacingMm', opts.strapSampleSpacingMm, ...
            'zBedMm', opts.zBedMm, ...
            'verbose', opts.verbose};
        earExclusions = acsSelectEarExclusionSpheres(layoutOrMesh, earArgs{:});
    end
    [centers, radii] = existingExclusions(targetOptions);
    targetOptions.exclusionCenters = [centers; double(earExclusions.exclusionCenters)];
    targetOptions.exclusionRadiusMM = [radii; double(earExclusions.exclusionRadiusMM(:))];
    targetOptions.customExclusionVertexInd = unique([ ...
        existingVertexExclusions(targetOptions); ...
        paintedVertexExclusions(earExclusions)]);
    targetOptions.earExclusionsApplied = true;
    targetOptions.earExclusions = compactEarExclusions(earExclusions);
end

function earExclusions = loadSavedEarExclusionsForCurrentMesh(fileName, layoutOrMesh, opts)
    if exist(fileName, 'file') ~= 2
        error('acsApplyEarExclusionsToTargetOptions:MissingEarExclusionFile', ...
            'Saved ear exclusion file not found: %s', fileName);
    end
    S = load(fileName);
    earExclusions = firstStruct(S);
    requireSavedEarExclusionFields(earExclusions, fileName);
    [V, sourceFile] = readSkinMeshPoints(layoutOrMesh);
    paintedRows = paintedRowsForCurrentMesh(earExclusions, V);
    earExclusions.customExclusionVertexInd = paintedRows(:);
    earExclusions.paintedExclusionVertex = paintedRows(:);
    earExclusions.outputFile = fileName;
    if ~isempty(sourceFile)
        earExclusions.appliedToSkinCacheFile = sourceFile;
    end
    if opts.verbose
        fprintf('Loaded saved ear/painted exclusions: %s\n', fileName);
        fprintf('  painted exclusions remapped to %d current mesh vertices.\n', ...
            numel(paintedRows));
    end
end

function requireSavedEarExclusionFields(earExclusions, fileName)
    if ~isstruct(earExclusions) || ...
            ~isfield(earExclusions, 'exclusionCenters') || ...
            ~isfield(earExclusions, 'exclusionRadiusMM')
        error('acsApplyEarExclusionsToTargetOptions:BadEarExclusionFile', ...
            ['Saved ear exclusion file does not contain exclusionCenters ', ...
             'and exclusionRadiusMM: %s'], fileName);
    end
end

function rows = paintedRowsForCurrentMesh(earExclusions, V)
    P = zeros(0, 3);
    if isfield(earExclusions, 'customExclusionCoordinatesMm') && ...
            ~isempty(earExclusions.customExclusionCoordinatesMm)
        P = double(earExclusions.customExclusionCoordinatesMm);
    elseif isfield(earExclusions, 'paintedExclusionCoordinatesMm') && ...
            ~isempty(earExclusions.paintedExclusionCoordinatesMm)
        P = double(earExclusions.paintedExclusionCoordinatesMm);
    end
    if size(P, 2) ~= 3
        P = zeros(0, 3);
    else
        P = P(all(isfinite(P), 2), :);
    end
    if ~isempty(P)
        [~, rows] = nearestPointRows(P, V);
        rows = unique(rows(:));
        return;
    end
    rows = paintedVertexExclusions(earExclusions);
    rows = rows(rows <= size(V, 1));
end

function value = firstStruct(S)
    names = fieldnames(S);
    for i = 1:numel(names)
        if isstruct(S.(names{i}))
            value = S.(names{i});
            return;
        end
    end
    error('acsApplyEarExclusionsToTargetOptions:NoStructInMat', ...
        'MAT file does not contain a saved ear exclusion struct.');
end

function [V, sourceFile] = readSkinMeshPoints(value)
    sourceFile = '';
    if isa(value, 'triangulation')
        V = double(value.Points);
        return;
    end
    if isstruct(value) && isfield(value, 'Points')
        V = double(value.Points);
        return;
    end
    if isstruct(value)
        cacheFile = layoutSkinCacheFile(value);
        S = load(cacheFile, 'TRskin');
        if ~isfield(S, 'TRskin')
            error('acsApplyEarExclusionsToTargetOptions:BadSkinCache', ...
                'Skin cache does not contain TRskin: %s', cacheFile);
        end
        V = double(S.TRskin.Points);
        sourceFile = cacheFile;
        return;
    end
    if ~(ischar(value) || isstring(value))
        error('acsApplyEarExclusionsToTargetOptions:BadMeshInput', ...
            'layoutOrMesh must be a layout, skin cache, mesh struct, or triangulation.');
    end
    fileName = expandUserPath(char(value));
    if exist(fileName, 'file') ~= 2
        error('acsApplyEarExclusionsToTargetOptions:MeshFileNotFound', ...
            'Skin/layout file not found: %s', fileName);
    end
    S = load(fileName);
    if isfield(S, 'TRskin')
        V = double(S.TRskin.Points);
        sourceFile = fileName;
        return;
    end
    layout = firstStruct(S);
    cacheFile = layoutSkinCacheFile(layout);
    T = load(cacheFile, 'TRskin');
    if ~isfield(T, 'TRskin')
        error('acsApplyEarExclusionsToTargetOptions:BadSkinCache', ...
            'Skin cache does not contain TRskin: %s', cacheFile);
    end
    V = double(T.TRskin.Points);
    sourceFile = cacheFile;
end

function cacheFile = layoutSkinCacheFile(layout)
    if ~isfield(layout, 'layout') || ~isfield(layout.layout, 'skin') || ...
            ~isfield(layout.layout.skin, 'cacheFile') || ...
            isempty(layout.layout.skin.cacheFile)
        error('acsApplyEarExclusionsToTargetOptions:MissingSkinCache', ...
            'Layout does not report layout.skin.cacheFile.');
    end
    cacheFile = expandUserPath(char(layout.layout.skin.cacheFile));
    if exist(cacheFile, 'file') ~= 2
        error('acsApplyEarExclusionsToTargetOptions:SkinCacheNotFound', ...
            'Skin cache not found: %s', cacheFile);
    end
end

function [dist, idx] = nearestPointRows(queryPoints, referencePoints)
    queryPoints = double(queryPoints);
    referencePoints = double(referencePoints);
    idx = zeros(size(queryPoints, 1), 1);
    dist = zeros(size(queryPoints, 1), 1);
    for i = 1:size(queryPoints, 1)
        delta = bsxfun(@minus, referencePoints, queryPoints(i, :));
        d2 = sum(delta .^ 2, 2);
        [best, idx(i)] = min(d2);
        dist(i) = sqrt(best);
    end
end

function opts = parseInputs(varargin)
    p = inputParser;
    p.FunctionName = 'acsApplyEarExclusionsToTargetOptions';
    addParameter(p, 'editMode', 'auto', @isEditMode);
    addParameter(p, 'outputFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'showFigures', true, @isBoolLike);
    addParameter(p, 'saveFigures', false, @isBoolLike);
    addParameter(p, 'showStrapPreview', true, @isBoolLike);
    addParameter(p, 'strapRostralOffsetMm', 0, @isNonnegativeScalar);
    addParameter(p, 'strapWidthMm', 10, @isPositiveScalar);
    addParameter(p, 'holderOutsideDiaMm', 12, @isPositiveScalar);
    addParameter(p, 'strapMarginMm', 2, @isNonnegativeScalar);
    addParameter(p, 'strapExclusionRadiusMm', [], ...
        @(x) isempty(x) || isPositiveScalar(x));
    addParameter(p, 'strapLateralLengthMm', 35, @isPositiveScalar);
    addParameter(p, 'strapSampleSpacingMm', 5, @isPositiveScalar);
    addParameter(p, 'zBedMm', 0, @(x) isnumeric(x) && isscalar(x) && isfinite(x));
    addParameter(p, 'verbose', true, @isBoolLike);
    parse(p, varargin{:});

    opts = p.Results;
    opts.editMode = lower(char(opts.editMode));
    opts.outputFile = expandUserPath(char(opts.outputFile));
    opts.showFigures = logical(opts.showFigures);
    opts.saveFigures = logical(opts.saveFigures);
    opts.showStrapPreview = logical(opts.showStrapPreview);
    opts.strapRostralOffsetMm = double(opts.strapRostralOffsetMm);
    opts.strapWidthMm = double(opts.strapWidthMm);
    opts.holderOutsideDiaMm = double(opts.holderOutsideDiaMm);
    opts.strapMarginMm = double(opts.strapMarginMm);
    if ~isempty(opts.strapExclusionRadiusMm)
        opts.strapExclusionRadiusMm = double(opts.strapExclusionRadiusMm);
    end
    opts.strapLateralLengthMm = double(opts.strapLateralLengthMm);
    opts.strapSampleSpacingMm = double(opts.strapSampleSpacingMm);
    opts.zBedMm = double(opts.zBedMm);
    opts.verbose = logical(opts.verbose);
end

function tf = isEditMode(x)
    if ~(ischar(x) || isstring(x))
        tf = false;
        return;
    end
    tf = any(strcmpi(char(x), {'auto', 'always', 'never'}));
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

function options = stripLegacyEarLineOptions(options)
    if isfield(options, 'earLeftLine')
        options = rmfield(options, 'earLeftLine');
    end
    if isfield(options, 'earRightLine')
        options = rmfield(options, 'earRightLine');
    end
end

function [centers, radii] = existingExclusions(targetOptions)
    centers = zeros(0, 3);
    radii = zeros(0, 1);
    if isfield(targetOptions, 'exclusionCenters') && ...
            ~isempty(targetOptions.exclusionCenters)
        centers = double(targetOptions.exclusionCenters);
        if size(centers, 2) ~= 3
            error('acsApplyEarExclusionsToTargetOptions:BadExclusionCenters', ...
                'exclusionCenters must be N x 3.');
        end
        if isfield(targetOptions, 'exclusionRadiusMM')
            radii = expandRadii(targetOptions.exclusionRadiusMM, size(centers, 1));
        else
            error('acsApplyEarExclusionsToTargetOptions:MissingExclusionRadius', ...
                'Set exclusionRadiusMM for existing exclusion centers.');
        end
    end
end

function targetOptions = removePriorEarExclusions(targetOptions)
    prior = getOptionalField(targetOptions, 'earExclusions', struct());
    if isfield(prior, 'exclusionCenters') && isfield(targetOptions, 'exclusionCenters')
        centers = double(targetOptions.exclusionCenters);
        radii = expandRadii(targetOptions.exclusionRadiusMM, size(centers, 1));
        priorCenters = double(prior.exclusionCenters);
        keep = true(size(centers, 1), 1);
        for i = 1:size(priorCenters, 1)
            d = sqrt(sum(bsxfun(@minus, centers, priorCenters(i, :)) .^ 2, 2));
            idx = find(d < 1e-6, 1);
            if ~isempty(idx)
                keep(idx) = false;
            end
        end
        targetOptions.exclusionCenters = centers(keep, :);
        targetOptions.exclusionRadiusMM = radii(keep);
    end
    if isfield(targetOptions, 'earExclusions')
        targetOptions = rmfield(targetOptions, 'earExclusions');
    end
    priorVertices = paintedVertexExclusions(prior);
    if ~isempty(priorVertices) && isfield(targetOptions, 'customExclusionVertexInd')
        current = existingVertexExclusions(targetOptions);
        targetOptions.customExclusionVertexInd = setdiff(current, priorVertices);
    end
    if isfield(targetOptions, 'earExclusionsApplied')
        targetOptions = rmfield(targetOptions, 'earExclusionsApplied');
    end
end

function rows = existingVertexExclusions(targetOptions)
    rows = [];
    if isfield(targetOptions, 'customExclusionVertexInd') && ...
            ~isempty(targetOptions.customExclusionVertexInd)
        rows = double(targetOptions.customExclusionVertexInd(:));
    end
    rows = rows(isfinite(rows) & rows >= 1);
    rows = unique(round(rows));
end

function rows = paintedVertexExclusions(earExclusions)
    rows = [];
    if isstruct(earExclusions) && isfield(earExclusions, 'customExclusionVertexInd') && ...
            ~isempty(earExclusions.customExclusionVertexInd)
        rows = double(earExclusions.customExclusionVertexInd(:));
    elseif isstruct(earExclusions) && isfield(earExclusions, 'paintedExclusionVertex') && ...
            ~isempty(earExclusions.paintedExclusionVertex)
        rows = double(earExclusions.paintedExclusionVertex(:));
    end
    rows = rows(isfinite(rows) & rows >= 1);
    rows = unique(round(rows));
end

function radii = expandRadii(value, n)
    radii = double(value(:));
    if isempty(radii) && n == 0
        radii = zeros(0, 1);
    elseif isscalar(radii)
        radii = repmat(radii, n, 1);
    elseif numel(radii) ~= n
        error('acsApplyEarExclusionsToTargetOptions:BadExclusionRadius', ...
            'exclusionRadiusMM must be scalar or have one value per center.');
    end
end

function compact = compactEarExclusions(earExclusions)
    compact = struct();
    fields = {'outputFile', 'jsonFile', 'exclusionCenters', 'exclusionRadiusMM', ...
        'leftCenterMm', 'rightCenterMm', 'leftRadiusMm', 'rightRadiusMm', ...
        'paintedExclusionVertex', 'paintedExclusionCoordinatesMm', ...
        'customExclusionVertexInd', 'customExclusionCoordinatesMm', ...
        'method', 'source', 'vertexExclusionSummary', 'strapPreview'};
    for i = 1:numel(fields)
        if isfield(earExclusions, fields{i})
            compact.(fields{i}) = earExclusions.(fields{i});
        end
    end
end

function value = getOptionalField(S, fieldName, defaultValue)
    if isstruct(S) && isfield(S, fieldName)
        value = S.(fieldName);
    else
        value = defaultValue;
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
