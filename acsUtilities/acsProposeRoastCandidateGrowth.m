function out = acsProposeRoastCandidateGrowth(baseLayout, sparseResult, varargin)
% ACSPROPOSEROASTCANDIDATEGROWTH Propose new capMaker electrode candidates.
%
% out = acsProposeRoastCandidateGrowth(layout, sparse)
% uses an existing ROAST custom lead field and sparse-targeting result to
% propose additional electrode locations on the capMaker scalp surface.
%
% The proposal is a fast surrogate only. It does not run ROAST. It predicts
% reduced lead-field features at legal capMaker scalp points using Gaussian
% RBF regression over the existing real leadfield columns, scores those
% points by expected weighted-residual reduction, and returns a candidate
% list that can be validated by generating a new real ROAST lead field.
%
% Name-value options:
%   nNew                         : number of new candidates to propose [8]
%   poolSize                     : number of legal virtual candidates [auto]
%   kernelSigmaMm                : RBF sigma in capMaker print mm ['auto']
%   acquisitionMode              : 'ucb' or 'predictedUtility' ['ucb']
%   ucbBeta                      : exploration weight for UCB [1]
%   ucbUncertaintyMode           : kernelVariance/kernelSupport/nearestDistance ['kernelVariance']
%   ucbNormalizeTerms            : normalize utility/uncertainty before UCB [true]
%   ucbRidge                     : ridge term for kernelVariance uncertainty [1e-6]
%   minDistanceFromExistingMm    : spacing from old electrodes [auto]
%   minDistanceAmongNewMm        : spacing among proposed electrodes [auto]
%   electrodeFootprintDiameterMm : physical housing diameter for spacing [10]
%   electrodeClearanceMm         : added center-spacing clearance [2]
%   excludeBedClippedCandidates  : remove candidates whose holder would hit zBed [true]
%   holderMinBedClearanceMm      : minimum placed-holder clearance above zBed [1]
%   excludeBadNormalCandidates   : remove candidates with bad holder normals [true]
%   holderNormalMode             : 'autoSmooth', 'smooth', or 'vertex' ['autoSmooth']
%   holderSmoothNormalRadiusMm   : local normal interpolation radius [6]
%   holderNormalDeviationThresholdDeg : autoSmooth threshold [25]
%   holderMinAxisZ               : reject candidates below this holder-axis z [0.25]
%   holderMaxRawToSmoothNormalAngleDeg : reject rough normal disagreements [25]
%   targetOptions                : overrides for autoElectrodeTargets [struct()]
%   earExclusionMode             : 'auto', 'always', or 'never' ['auto']
%   earExclusionFile             : explicit saved ear-exclusion MAT file ['']
%   strapExclusionMode           : 'auto', 'always', or 'none' ['auto']
%   strapRostralOffsetMm         : strap keepout offset rostral to ear edge [0]
%   strapWidthMm                 : nominal chin-strap width for keepout [10]
%   strapMarginMm                : extra strap/electrode placement margin [2]
%   makeLayout                   : call acsMakeRoastCapMakerLayout [false]
%   outputFile                   : customLocations path for makeLayout ['']
%   forceLayout                  : overwrite outputFile for makeLayout [true]
%   proposalTag                  : filename/report tag ['surrogateGrowK#']
%   maxFilenameBaseChars         : max basename length for report/QC files [96]
%   showFigures                  : show QC figure [false]
%   saveFigures                  : save QC figure [false]
%   saveReport                   : save MAT report beside T1 [true]
%   verbose                      : print progress [true]

    if nargin < 2
        error('acsProposeRoastCandidateGrowth:MissingInput', ...
            'Provide a base capMaker layout and a sparse targeting result.');
    end
    opts = parseInputs(varargin{:});
    addLocalDependencies();

    layout = readLayout(baseLayout);
    sparse = readSparseResult(sparseResult);
    requireFields(layout, {'t1File', 'maskFile', 'names', ...
        'layoutCoordinatesMm', 'targetOptions', 'layout'});
    requireFields(sparse, {'t1File', 'leadFieldTag', 'targetVoxel', ...
        'orientation', 'targetWeights', 'targetRadiusMm', ...
        'basisCoefficientsMa'});
    if ~strcmpi(canonicalPath(layout.t1File), canonicalPath(sparse.t1File))
        error('acsProposeRoastCandidateGrowth:T1Mismatch', ...
            'The base layout and sparse result refer to different T1 files.');
    end

    [folder, stem] = fileparts(layout.t1File);
    if isempty(opts.proposalTag)
        opts.proposalTag = sprintf('surrogateGrowK%d', opts.nNew);
    end
    opts.proposalTag = safeTag(opts.proposalTag);

    [A_all, meshData, leadField] = loadLeadField(layout.t1File, sparse.leadFieldTag);
    [allNames, stimulusNames] = leadFieldNames(leadField);
    layoutNames = cellstr(layout.names(:));
    existingPrintMm = double(layout.layoutCoordinatesMm);
    validateLayoutLeadFieldMatch(layoutNames, existingPrintMm, allNames);

    [TRskin, skinCacheFile] = loadSkinMeshFromLayout(layout);
    poolTargetOptions = proposalTargetOptions(layout.targetOptions, ...
        opts.targetOptions);
    [poolTargetOptions, earExclusions] = acsApplyEarExclusionsToTargetOptions(poolTargetOptions, skinCacheFile, ...
        'editMode', opts.earExclusionMode, ...
        'outputFile', opts.earExclusionFile, ...
        'showFigures', opts.showFigures, ...
        'saveFigures', opts.saveFigures, ...
        'showStrapPreview', ~strcmp(opts.strapExclusionMode, 'none'), ...
        'zBedMm', opts.zBedMm, ...
        'strapRostralOffsetMm', opts.strapRostralOffsetMm, ...
        'strapWidthMm', opts.strapWidthMm, ...
        'holderOutsideDiaMm', opts.holderOutsideDiaMm, ...
        'strapMarginMm', opts.strapMarginMm, ...
        'strapExclusionRadiusMm', opts.strapExclusionRadiusMm, ...
        'strapLateralLengthMm', opts.strapLateralLengthMm, ...
        'strapSampleSpacingMm', opts.strapSampleSpacingMm, ...
        'verbose', opts.verbose);
    [poolTargetOptions, strapExclusion] = acsAddStrapExclusionsToTargetOptions( ...
        poolTargetOptions, earExclusions, ...
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
    poolSize = opts.poolSize;
    if isempty(poolSize)
        poolSize = max(numel(layoutNames) + opts.nNew * 4, 96);
    end
    poolSize = round(double(poolSize));
    logMsg(opts, 'Finding legal virtual capMaker scalp candidates.');
    [poolPrintMm, poolVertex, poolInfo] = surfaceCandidatePool( ...
        TRskin, poolTargetOptions);
    [bedMask, bedInfo] = candidateBedClearanceMask(TRskin, poolPrintMm, opts);
    if opts.excludeBedClippedCandidates
        poolPrintMm = poolPrintMm(bedMask, :);
        poolVertex = poolVertex(bedMask);
    end
    poolInfo.bedClearance = bedInfo;
    logMsg(opts, 'Found %d legal virtual capMaker scalp candidates.', ...
        size(poolPrintMm, 1));

    [eligiblePool, exclusionInfo] = excludeNearbyPoolPoints(poolPrintMm, ...
        existingPrintMm, opts.minDistanceFromExistingMm);
    candidatePrintMm = poolPrintMm(eligiblePool, :);
    candidateVertex = poolVertex(eligiblePool);
    if size(candidatePrintMm, 1) < opts.nNew
        error('acsProposeRoastCandidateGrowth:TooFewVirtualCandidates', ...
            ['Only %d virtual candidates remain after existing-electrode ', ...
             'spacing. Reduce minDistanceFromExistingMm or increase poolSize.'], ...
            size(candidatePrintMm, 1));
    end
    [queryPrintMm, queryVertex, poolSelectionInfo] = chooseVirtualPool( ...
        candidatePrintMm, candidateVertex, existingPrintMm, poolSize);

    [trainingPrintMm, trainingNames] = trainingPositionsForLeadField( ...
        layoutNames, existingPrintMm, stimulusNames);
    [projection, gram, residualInfo] = residualFeatureStatistics( ...
        A_all, meshData, sparse);
    surrogate = acsKernelRegressLeadFieldFeatures(trainingPrintMm, ...
        queryPrintMm, ...
        'trainingProjection', projection, ...
        'trainingGram', gram, ...
        'sigmaMm', opts.kernelSigmaMm);
    [surrogate, acquisitionInfo] = addAcquisitionScores(surrogate, ...
        trainingPrintMm, queryPrintMm, opts);

    [selectedQueryRows, newSpacingInfo] = greedySelectByScore(queryPrintMm, ...
        surrogate.acquisitionScore, opts.nNew, ...
        opts.minDistanceAmongNewMm, opts);
    proposedNewPrintMm = queryPrintMm(selectedQueryRows, :);
    proposedNewVertex = queryVertex(selectedQueryRows);
    proposedNewScore = surrogate.residualImprovementScore(selectedQueryRows);
    proposedNewAcquisition = surrogate.acquisitionScore(selectedQueryRows);
    proposedNewUncertainty = surrogate.uncertaintyScore(selectedQueryRows);
    proposedNewProjection = surrogate.predictedProjection(selectedQueryRows);
    proposedNewNorm2 = surrogate.predictedNorm2(selectedQueryRows);
    proposedNewSign = surrogate.preferredCurrentSign(selectedQueryRows);

    newNames = nextCustomNames(layoutNames, opts.nNew);
    expandedNames = [layoutNames(:); newNames(:)];
    expandedPrintMm = [existingPrintMm; proposedNewPrintMm];

    expandedLayout = [];
    manualTargetOptions = layout.targetOptions;
    manualTargetOptions.manualTargetsMm = expandedPrintMm;
    manualTargetOptions.placementMode = 'manualTargetsMm';
    if opts.makeLayout
        logMsg(opts, 'Writing expanded custom layout with %d electrodes.', ...
            numel(expandedNames));
        subjectId = getOptionalField(layout.layout, 'subjectId', '');
        layoutArgs = { ...
            'nElectrodes', numel(expandedNames), ...
            'electrodeNames', expandedNames, ...
            'surfaceSource', 'capMaker', ...
            'targetOptions', manualTargetOptions, ...
            'skinCacheFile', skinCacheFile, ...
            'earExclusionMode', opts.earExclusionMode, ...
            'earExclusionFile', opts.earExclusionFile, ...
            'subjectId', subjectId, ...
            'force', opts.forceLayout, ...
            'showFigures', opts.showFigures, ...
            'saveFigures', opts.saveFigures, ...
            'verbose', opts.verbose};
        if ~isempty(opts.outputFile)
            layoutArgs = [layoutArgs, {'outputFile', opts.outputFile}]; %#ok<AGROW>
        end
        expandedLayout = acsMakeRoastCapMakerLayout(layout, layoutArgs{:});
        if isfield(expandedLayout, 'figure')
            expandedLayout = rmfield(expandedLayout, 'figure');
        end
    end

    out = struct();
    out.createdOn = char(datetime('now'));
    out.t1File = layout.t1File;
    out.maskFile = layout.maskFile;
    out.baseCustomLocationsFile = layout.customLocationsFile;
    out.baseLayoutReportMat = getOptionalField(layout, 'reportMat', '');
    out.leadFieldTag = sparse.leadFieldTag;
    out.targetingTag = getOptionalField(sparse, 'targetingTag', '');
    out.proposalTag = opts.proposalTag;
    out.nExisting = numel(layoutNames);
    out.nNew = opts.nNew;
    out.nExpanded = numel(expandedNames);
    out.electrodeFootprintDiameterMm = opts.electrodeFootprintDiameterMm;
    out.electrodeClearanceMm = opts.electrodeClearanceMm;
    out.minDistanceFromExistingMm = opts.minDistanceFromExistingMm;
    out.minDistanceAmongNewMm = opts.minDistanceAmongNewMm;
    out.actualMinDistanceAmongNewMm = newSpacingInfo.actualMinDistanceMm;
    out.newSpacingInfo = newSpacingInfo;
    out.existingNames = layoutNames(:);
    out.newNames = newNames(:);
    out.expandedNames = expandedNames(:);
    out.existingLayoutCoordinatesMm = existingPrintMm;
    out.newLayoutCoordinatesMm = proposedNewPrintMm;
    out.expandedLayoutCoordinatesMm = expandedPrintMm;
    out.newPoolRows = selectedQueryRows(:);
    out.newSkinVertices = proposedNewVertex(:);
    out.newSurrogateScore = proposedNewScore(:);
    out.newAcquisitionScore = proposedNewAcquisition(:);
    out.newUncertaintyScore = proposedNewUncertainty(:);
    out.newPredictedResidualProjection = proposedNewProjection(:);
    out.newPredictedNorm2 = proposedNewNorm2(:);
    out.newPreferredCurrentSign = proposedNewSign(:);
    out.kernel = compactKernelReport(surrogate, trainingNames, ...
        trainingPrintMm, queryPrintMm);
    out.acquisition = acquisitionInfo;
    out.trainingNames = trainingNames(:);
    out.poolSizeRequested = poolSize;
    out.poolSizeAvailable = size(candidatePrintMm, 1);
    out.poolSizeEligible = size(queryPrintMm, 1);
    out.poolLayoutCoordinatesMm = queryPrintMm;
    out.poolSkinVertices = queryVertex(:);
    out.poolSurrogateScore = surrogate.residualImprovementScore;
    out.poolAcquisitionScore = surrogate.acquisitionScore;
    out.poolUncertaintyScore = surrogate.uncertaintyScore;
    out.poolPreferredCurrentSign = surrogate.preferredCurrentSign;
    out.poolInfo = compactPoolInfo(poolInfo);
    out.bedClearanceInfo = bedInfo;
    out.earExclusions = compactExclusionStruct(earExclusions);
    out.strapExclusion = compactExclusionStruct(strapExclusion);
    out.exclusionInfo = exclusionInfo;
    out.poolSelectionInfo = poolSelectionInfo;
    out.residualInfo = residualInfo;
    out.manualTargetOptions = manualTargetOptions;
    out.expandedLayout = expandedLayout;
    [compactStem, fileNameInfo] = compactGrowthFileStem( ...
        stem, sparse.leadFieldTag, opts.proposalTag, out, opts);
    out.fileNameInfo = fileNameInfo;
    out.reportMat = fullfile(folder, [compactStem '.mat']);
    out.qcFigure = '';

    fig = [];
    if opts.showFigures || opts.saveFigures
        figVisible = 'off';
        if opts.showFigures
            figVisible = 'on';
        end
        fig = makeProposalFigure(TRskin, existingPrintMm, queryPrintMm, ...
            proposedNewPrintMm, surrogate, out, figVisible);
        out.figure = fig;
        if opts.saveFigures
            qcDir = fullfile(folder, 'qc');
            ensureDir(qcDir);
            out.qcFigure = fullfile(qcDir, [compactStem '_qc.png']);
            saveQcFigure(fig, out.qcFigure);
        end
        if ~opts.showFigures
            close(fig);
            out = rmfield(out, 'figure');
        end
    end

    if opts.saveReport
        outToSave = out;
        if isfield(outToSave, 'figure')
            outToSave = rmfield(outToSave, 'figure');
        end
        save(out.reportMat, 'outToSave', '-v7.3');
    end
    if opts.verbose
        printSummary(out);
    end
end

function opts = parseInputs(varargin)
    p = inputParser;
    p.FunctionName = 'acsProposeRoastCandidateGrowth';
    addParameter(p, 'nNew', 8, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 1);
    addParameter(p, 'poolSize', [], ...
        @(x) isempty(x) || (isnumeric(x) && isscalar(x) && isfinite(x) && x >= 1));
    addParameter(p, 'kernelSigmaMm', 'auto', ...
        @(x) (ischar(x) || isstring(x)) || ...
        (isnumeric(x) && isscalar(x) && isfinite(x) && x > 0));
    addParameter(p, 'acquisitionMode', 'ucb', @(x) ischar(x) || isstring(x));
    addParameter(p, 'ucbBeta', 1, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0);
    addParameter(p, 'ucbUncertaintyMode', 'kernelVariance', ...
        @(x) ischar(x) || isstring(x));
    addParameter(p, 'ucbNormalizeTerms', true, @isBoolLike);
    addParameter(p, 'ucbRidge', 1e-6, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0);
    addParameter(p, 'minDistanceFromExistingMm', [], ...
        @(x) isempty(x) || (isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0));
    addParameter(p, 'minDistanceAmongNewMm', [], ...
        @(x) isempty(x) || (isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0));
    addParameter(p, 'electrodeFootprintDiameterMm', 10, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x > 0);
    addParameter(p, 'electrodeClearanceMm', 2, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0);
    addParameter(p, 'excludeBedClippedCandidates', true, @isBoolLike);
    addParameter(p, 'excludeBadNormalCandidates', true, @isBoolLike);
    addParameter(p, 'holderInsideDiaMm', 4, @isPositiveScalar);
    addParameter(p, 'holderOutsideDiaMm', 12, @isPositiveScalar);
    addParameter(p, 'holderHeightMm', 7, @isPositiveScalar);
    addParameter(p, 'holderEmbedMm', 0.3, @isNonnegativeScalar);
    addParameter(p, 'holderMinBedClearanceMm', 1, @isNonnegativeScalar);
    addParameter(p, 'holderNormalMode', 'autoSmooth', ...
        @(x) ischar(x) || isstring(x));
    addParameter(p, 'holderSmoothNormalRadiusMm', 6, @isPositiveScalar);
    addParameter(p, 'holderNormalDeviationThresholdDeg', 25, ...
        @isNonnegativeScalar);
    addParameter(p, 'holderMinAxisZ', 0.25, ...
        @(x) isempty(x) || (isnumeric(x) && isscalar(x) && isfinite(x)));
    addParameter(p, 'holderMaxRawToSmoothNormalAngleDeg', 25, ...
        @(x) isempty(x) || isNonnegativeScalar(x));
    addParameter(p, 'zBedMm', 0, @(x) isnumeric(x) && isscalar(x) && isfinite(x));
    addParameter(p, 'targetOptions', struct(), @(x) isempty(x) || isstruct(x));
    addParameter(p, 'earExclusionMode', 'auto', @(x) ischar(x) || isstring(x));
    addParameter(p, 'earExclusionFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'strapExclusionMode', 'auto', @(x) ischar(x) || isstring(x));
    addParameter(p, 'strapRostralOffsetMm', 0, @isNonnegativeScalar);
    addParameter(p, 'strapWidthMm', 10, @isPositiveScalar);
    addParameter(p, 'strapMarginMm', 2, @isNonnegativeScalar);
    addParameter(p, 'strapExclusionRadiusMm', [], ...
        @(x) isempty(x) || isPositiveScalar(x));
    addParameter(p, 'strapLateralLengthMm', 35, @isPositiveScalar);
    addParameter(p, 'strapSampleSpacingMm', 5, @isPositiveScalar);
    addParameter(p, 'makeLayout', false, @isBoolLike);
    addParameter(p, 'outputFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'forceLayout', true, @isBoolLike);
    addParameter(p, 'proposalTag', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'maxFilenameBaseChars', 96, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 32);
    addParameter(p, 'showFigures', false, @isBoolLike);
    addParameter(p, 'saveFigures', false, @isBoolLike);
    addParameter(p, 'saveReport', true, @isBoolLike);
    addParameter(p, 'verbose', true, @isBoolLike);
    parse(p, varargin{:});
    opts = p.Results;
    opts.nNew = round(double(opts.nNew));
    if ~isempty(opts.poolSize)
        opts.poolSize = round(double(opts.poolSize));
    end
    opts.electrodeFootprintDiameterMm = double(opts.electrodeFootprintDiameterMm);
    opts.electrodeClearanceMm = double(opts.electrodeClearanceMm);
    opts.excludeBedClippedCandidates = logical(opts.excludeBedClippedCandidates);
    opts.excludeBadNormalCandidates = logical(opts.excludeBadNormalCandidates);
    opts.holderInsideDiaMm = double(opts.holderInsideDiaMm);
    opts.holderOutsideDiaMm = double(opts.holderOutsideDiaMm);
    opts.holderHeightMm = double(opts.holderHeightMm);
    opts.holderEmbedMm = double(opts.holderEmbedMm);
    opts.holderMinBedClearanceMm = double(opts.holderMinBedClearanceMm);
    opts.holderNormalMode = normalizeHolderNormalMode(opts.holderNormalMode);
    opts.holderSmoothNormalRadiusMm = double(opts.holderSmoothNormalRadiusMm);
    opts.holderNormalDeviationThresholdDeg = double( ...
        opts.holderNormalDeviationThresholdDeg);
    if ~isempty(opts.holderMinAxisZ)
        opts.holderMinAxisZ = double(opts.holderMinAxisZ);
    end
    if ~isempty(opts.holderMaxRawToSmoothNormalAngleDeg)
        opts.holderMaxRawToSmoothNormalAngleDeg = double( ...
            opts.holderMaxRawToSmoothNormalAngleDeg);
    end
    opts.zBedMm = double(opts.zBedMm);
    opts.acquisitionMode = normalizeAcquisitionMode(opts.acquisitionMode);
    opts.ucbBeta = double(opts.ucbBeta);
    opts.ucbUncertaintyMode = normalizeUncertaintyMode(opts.ucbUncertaintyMode);
    opts.ucbNormalizeTerms = logical(opts.ucbNormalizeTerms);
    opts.ucbRidge = double(opts.ucbRidge);
    opts.earExclusionMode = normalizeEarExclusionMode(opts.earExclusionMode);
    opts.earExclusionFile = expandUserPath(char(opts.earExclusionFile));
    opts.strapExclusionMode = normalizeStrapExclusionMode(opts.strapExclusionMode);
    opts.strapRostralOffsetMm = double(opts.strapRostralOffsetMm);
    opts.strapWidthMm = double(opts.strapWidthMm);
    opts.strapMarginMm = double(opts.strapMarginMm);
    if ~isempty(opts.strapExclusionRadiusMm)
        opts.strapExclusionRadiusMm = double(opts.strapExclusionRadiusMm);
    end
    opts.strapLateralLengthMm = double(opts.strapLateralLengthMm);
    opts.strapSampleSpacingMm = double(opts.strapSampleSpacingMm);
    defaultCenterDistance = opts.electrodeFootprintDiameterMm + ...
        opts.electrodeClearanceMm;
    if isempty(opts.minDistanceFromExistingMm)
        opts.minDistanceFromExistingMm = defaultCenterDistance;
    else
        opts.minDistanceFromExistingMm = double(opts.minDistanceFromExistingMm);
    end
    if isempty(opts.minDistanceAmongNewMm)
        opts.minDistanceAmongNewMm = defaultCenterDistance;
    else
        opts.minDistanceAmongNewMm = double(opts.minDistanceAmongNewMm);
    end
    opts.outputFile = expandUserPath(char(opts.outputFile));
    opts.forceLayout = logical(opts.forceLayout);
    opts.makeLayout = logical(opts.makeLayout);
    opts.proposalTag = char(opts.proposalTag);
    opts.maxFilenameBaseChars = round(double(opts.maxFilenameBaseChars));
    opts.showFigures = logical(opts.showFigures);
    opts.saveFigures = logical(opts.saveFigures);
    opts.saveReport = logical(opts.saveReport);
    opts.verbose = logical(opts.verbose);
end

function tf = isBoolLike(x)
    tf = (islogical(x) || isnumeric(x)) && isscalar(x);
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
            error('acsProposeRoastCandidateGrowth:BadStrapExclusionMode', ...
                'strapExclusionMode must be ''auto'', ''always'', or ''none''.');
    end
end

function tf = isPositiveScalar(x)
    tf = isnumeric(x) && isscalar(x) && isfinite(x) && x > 0;
end

function tf = isNonnegativeScalar(x)
    tf = isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0;
end

function mode = normalizeEarExclusionMode(modeIn)
    mode = lower(strtrim(char(modeIn)));
    switch mode
        case {'auto', 'always', 'never'}
            % Accepted as-is.
        case {'reuse', 'load'}
            mode = 'never';
        case {'select', 'edit'}
            mode = 'always';
        otherwise
            error('acsProposeRoastCandidateGrowth:BadEarExclusionMode', ...
                'earExclusionMode must be ''auto'', ''always'', or ''never''.');
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
            error('acsProposeRoastCandidateGrowth:BadHolderNormalMode', ...
                ['holderNormalMode must be ''autoSmooth'', ', ...
                 '''smooth'', or ''vertex''.']);
    end
end

function mode = normalizeAcquisitionMode(modeIn)
    mode = lower(strtrim(char(modeIn)));
    switch mode
        case {'ucb', 'upperconfidencebound', 'upper-confidence-bound'}
            mode = 'ucb';
        case {'predictedutility', 'utility', 'legacy', 'exploit', 'exploitation'}
            mode = 'predictedUtility';
        otherwise
            error('acsProposeRoastCandidateGrowth:BadAcquisitionMode', ...
                'acquisitionMode must be ''ucb'' or ''predictedUtility''.');
    end
end

function mode = normalizeUncertaintyMode(modeIn)
    mode = lower(strtrim(char(modeIn)));
    switch mode
        case {'kernelvariance', 'gpvariance', 'variance'}
            mode = 'kernelVariance';
        case {'kernelsupport', 'support'}
            mode = 'kernelSupport';
        case {'nearestdistance', 'nearest', 'distance'}
            mode = 'nearestDistance';
        otherwise
            error('acsProposeRoastCandidateGrowth:BadUncertaintyMode', ...
                ['ucbUncertaintyMode must be ''kernelVariance'', ', ...
                 '''kernelSupport'', or ''nearestDistance''.']);
    end
end

function addLocalDependencies()
    repoRoot = fileparts(fileparts(mfilename('fullpath')));
    addpath(repoRoot);
    addpath(fullfile(repoRoot, 'acsUtilities'));
    spmDir = fullfile(repoRoot, 'lib', 'spm12');
    if exist(spmDir, 'dir') == 7
        addpath(spmDir);
    end
    capGeometryDir = fullfile(repoRoot, 'capMaker', 'geometry');
    if exist(capGeometryDir, 'dir') == 7
        addpath(capGeometryDir);
    end
end

function layout = readLayout(layoutIn)
    if ischar(layoutIn) || isstring(layoutIn)
        S = load(char(layoutIn));
        layout = firstStructInMat(S);
    elseif isstruct(layoutIn)
        layout = layoutIn;
    else
        error('acsProposeRoastCandidateGrowth:BadLayoutInput', ...
            'baseLayout must be a layout struct or saved MAT report.');
    end
end

function sparse = readSparseResult(sparseIn)
    if ischar(sparseIn) || isstring(sparseIn)
        S = load(char(sparseIn));
        sparse = firstStructInMat(S);
    elseif isstruct(sparseIn)
        sparse = sparseIn;
    else
        error('acsProposeRoastCandidateGrowth:BadSparseInput', ...
            'sparseResult must be a sparse result struct or saved MAT report.');
    end
end

function S = firstStructInMat(M)
    if isfield(M, 'out')
        S = M.out;
        return;
    end
    if isfield(M, 'outToSave')
        S = M.outToSave;
        return;
    end
    fields = fieldnames(M);
    for i = 1:numel(fields)
        if isstruct(M.(fields{i}))
            S = M.(fields{i});
            return;
        end
    end
    error('acsProposeRoastCandidateGrowth:NoStructInMat', ...
        'MAT file did not contain a struct result.');
end

function requireFields(S, fields)
    for i = 1:numel(fields)
        if ~isfield(S, fields{i}) || isempty(S.(fields{i}))
            error('acsProposeRoastCandidateGrowth:MissingField', ...
                'Input struct is missing required field "%s".', fields{i});
        end
    end
end

function [A_all, meshData, leadField] = loadLeadField(t1File, leadFieldTag)
    [folder, stem] = fileparts(t1File);
    resultFile = fullfile(folder, [stem '_' leadFieldTag '_roastResult.mat']);
    optionsFile = fullfile(folder, [stem '_' leadFieldTag '_roastOptions.mat']);
    meshFile = fullfile(folder, [stem '_' leadFieldTag '.mat']);
    requireFile(resultFile);
    requireFile(optionsFile);
    requireFile(meshFile);
    resultData = load(resultFile, 'A_all');
    optionsData = load(optionsFile, 'opt');
    meshData = load(meshFile, 'node', 'elem');
    if ~isfield(resultData, 'A_all')
        error('acsProposeRoastCandidateGrowth:MissingLeadFieldMatrix', ...
            'Lead-field result does not contain A_all: %s', resultFile);
    end
    if ~isfield(optionsData, 'opt') || ...
            ~isfield(optionsData.opt, 'leadField')
        error('acsProposeRoastCandidateGrowth:MissingLeadFieldMetadata', ...
            'Lead-field options do not contain leadField metadata.');
    end
    A_all = resultData.A_all;
    leadField = optionsData.opt.leadField;
end

function requireFile(fileName)
    if exist(fileName, 'file') ~= 2
        error('acsProposeRoastCandidateGrowth:MissingFile', ...
            'Required file not found: %s', fileName);
    end
end

function [allNames, stimulusNames] = leadFieldNames(leadField)
    if ~strcmpi(leadField.mode, 'custom') || ...
            ~isfield(leadField, 'stimulusElectrodeNames')
        error('acsProposeRoastCandidateGrowth:UnsupportedLeadField', ...
            'Candidate growth requires a custom capMaker lead field.');
    end
    allNames = cellstr(leadField.electrodeNames(:));
    stimulusNames = cellstr(leadField.stimulusElectrodeNames(:));
end

function validateLayoutLeadFieldMatch(layoutNames, existingPrintMm, allNames)
    if size(existingPrintMm, 1) ~= numel(layoutNames)
        error('acsProposeRoastCandidateGrowth:BadLayoutCoordinates', ...
            'layoutCoordinatesMm must have one row per layout name.');
    end
    missing = setdiff(lower(string(allNames)), lower(string(layoutNames)));
    if ~isempty(missing)
        error('acsProposeRoastCandidateGrowth:LayoutLeadFieldMismatch', ...
            'Layout is missing lead-field electrode name(s): %s', ...
            strjoin(cellstr(missing), ', '));
    end
end

function [TRskin, cacheFile] = loadSkinMeshFromLayout(layout)
    if ~isfield(layout.layout, 'skin') || ...
            ~isfield(layout.layout.skin, 'cacheFile') || ...
            isempty(layout.layout.skin.cacheFile)
        error('acsProposeRoastCandidateGrowth:MissingSkinCache', ...
            'Base layout does not report a capMaker skin mesh cache file.');
    end
    cacheFile = char(layout.layout.skin.cacheFile);
    requireFile(cacheFile);
    S = load(cacheFile, 'TRskin');
    if ~isfield(S, 'TRskin')
        error('acsProposeRoastCandidateGrowth:BadSkinCache', ...
            'Skin cache does not contain TRskin: %s', cacheFile);
    end
    TRskin = S.TRskin;
end

function targetOpts = proposalTargetOptions(baseOpts, overrideOpts)
    targetOpts = baseOpts;
    if isfield(targetOpts, 'manualTargetsMm')
        targetOpts = rmfield(targetOpts, 'manualTargetsMm');
    end
    targetOpts.placementMode = 'surfaceGeodesic';
    targetOpts.viz2D = false;
    targetOpts.viz3D = false;
    if isfield(targetOpts, 'vizSurfaceGeodesic')
        targetOpts.vizSurfaceGeodesic = false;
    end
    if nargin > 1 && ~isempty(overrideOpts)
        fields = fieldnames(overrideOpts);
        for i = 1:numel(fields)
            targetOpts.(fields{i}) = overrideOpts.(fields{i});
        end
    end
    if isfield(targetOpts, 'manualTargetsMm')
        targetOpts = rmfield(targetOpts, 'manualTargetsMm');
    end
    if isfield(targetOpts, 'placementMode') && ...
            ~strcmpi(targetOpts.placementMode, 'surfaceGeodesic')
        warning('acsProposeRoastCandidateGrowth:ForcingSurfacePool', ...
            ['Surrogate candidate growth needs surface-geodesic eligibility ', ...
             'metadata. Using placementMode=''surfaceGeodesic'' for the ', ...
             'virtual pool.']);
        targetOpts.placementMode = 'surfaceGeodesic';
    end
    targetOpts.viz2D = false;
    targetOpts.viz3D = false;
    if isfield(targetOpts, 'vizSurfaceGeodesic')
        targetOpts.vizSurfaceGeodesic = false;
    end
end

function TRlayout = targetSurfaceAsStruct(surface)
    if isa(surface, 'triangulation')
        TRlayout = struct( ...
            'Points', double(surface.Points), ...
            'ConnectivityList', double(surface.ConnectivityList));
    elseif isstruct(surface) && isfield(surface, 'Points')
        TRlayout = surface;
        TRlayout.Points = double(surface.Points);
    else
        error('acsProposeRoastCandidateGrowth:BadSurface', ...
            'Skin mesh must be a triangulation or struct with Points.');
    end
end

function [poolPrintMm, poolVertex, poolInfo] = surfaceCandidatePool( ...
        TRskin, targetOpts)
    if exist('autoElectrodeTargets', 'file') ~= 2
        error('acsProposeRoastCandidateGrowth:MissingCapMaker', ...
            'capMaker geometry function autoElectrodeTargets was not found on the MATLAB path.');
    end
    probeOpts = targetOpts;
    probeOpts.placementMode = 'surfaceGeodesic';
    probeOpts.preferSymmetry = false;
    probeOpts.vizSurfaceGeodesic = false;
    probeOpts.viz2D = false;
    probeOpts.viz3D = false;
    [~, ~, poolInfo] = autoElectrodeTargets( ...
        targetSurfaceAsStruct(TRskin), 1, probeOpts);
    if ~isfield(poolInfo, 'candidateVertex') || isempty(poolInfo.candidateVertex)
        error('acsProposeRoastCandidateGrowth:NoCandidateVertices', ...
            'surfaceGeodesic did not return any candidate vertices.');
    end
    TRlayout = targetSurfaceAsStruct(TRskin);
    poolVertex = poolInfo.candidateVertex(:);
    poolPrintMm = TRlayout.Points(poolVertex, :);
    [poolPrintMm, poolVertex] = uniquePoolByVertex(poolPrintMm, poolVertex);
end

function [poolPrintMm, poolVertex] = uniquePoolByVertex(poolPrintMm, poolVertex)
    poolVertex = poolVertex(:);
    [~, keep] = unique(poolVertex, 'stable');
    poolPrintMm = double(poolPrintMm(keep, :));
    poolVertex = poolVertex(keep);
end

function [mask, info] = candidateBedClearanceMask(TRskin, poolPrintMm, opts)
    n = size(poolPrintMm, 1);
    mask = true(n, 1);
    info = struct( ...
        'enabled', logical(opts.excludeBedClippedCandidates), ...
        'normalScreenEnabled', logical(opts.excludeBadNormalCandidates), ...
        'zBedMm', opts.zBedMm, ...
        'holderMinBedClearanceMm', opts.holderMinBedClearanceMm, ...
        'holderMinAxisZ', opts.holderMinAxisZ, ...
        'holderMaxRawToSmoothNormalAngleDeg', ...
            opts.holderMaxRawToSmoothNormalAngleDeg, ...
        'nCandidates', n, ...
        'nExcluded', 0, ...
        'nBedExcluded', 0, ...
        'nAxisExcluded', 0, ...
        'nRoughNormalExcluded', 0, ...
        'minClearanceMm', [], ...
        'axisZ', [], ...
        'rawToSmoothNormalAngleDeg', [], ...
        'excludedRows', []);
    if n == 0
        return;
    end
    holderTR = makeElectrodeHolderHex(opts.holderInsideDiaMm, ...
        opts.holderOutsideDiaMm, opts.holderHeightMm);
    [~, ~, ~, holderInfo] = placeElectrodeArrayOnSurface( ...
        TRskin, holderTR, poolPrintMm, opts.holderEmbedMm, ...
        'NormalMode', opts.holderNormalMode, ...
        'SmoothNormalRadiusMm', opts.holderSmoothNormalRadiusMm, ...
        'NormalDeviationThresholdDeg', opts.holderNormalDeviationThresholdDeg);
    minZ = [holderInfo.minZMm].';
    clearance = minZ - opts.zBedMm;
    axis = reshape([holderInfo.holeAxis], 3, []).';
    axisZ = axis(:, 3);
    rawToSmoothDeg = [holderInfo.rawToSmoothNormalAngleDeg].';
    bedMask = clearance >= opts.holderMinBedClearanceMm;
    axisMask = true(n, 1);
    if opts.excludeBadNormalCandidates && ~isempty(opts.holderMinAxisZ)
        axisMask = axisZ >= opts.holderMinAxisZ;
    end
    roughNormalMask = true(n, 1);
    if opts.excludeBadNormalCandidates && ...
            ~isempty(opts.holderMaxRawToSmoothNormalAngleDeg)
        roughNormalMask = rawToSmoothDeg <= ...
            opts.holderMaxRawToSmoothNormalAngleDeg;
    end
    if opts.excludeBedClippedCandidates
        mask = mask & bedMask;
    end
    if opts.excludeBadNormalCandidates
        mask = mask & axisMask & roughNormalMask;
    end
    info.minClearanceMm = clearance;
    info.axisZ = axisZ;
    info.rawToSmoothNormalAngleDeg = rawToSmoothDeg;
    info.excludedRows = find(~mask);
    info.nExcluded = nnz(~mask);
    info.nBedExcluded = nnz(~bedMask);
    info.nAxisExcluded = nnz(~axisMask);
    info.nRoughNormalExcluded = nnz(~roughNormalMask);
    if info.nExcluded > 0
        logMsg(opts, ['Excluded %d virtual candidates by holder geometry ', ...
            'screen (%d bed, %d low-axis, %d rough-normal).'], ...
            info.nExcluded, info.nBedExcluded, info.nAxisExcluded, ...
            info.nRoughNormalExcluded);
    end
end

function [queryPrintMm, queryVertex, info] = chooseVirtualPool( ...
        candidatePrintMm, candidateVertex, existingPrintMm, poolSize)
    nAvailable = size(candidatePrintMm, 1);
    info = struct();
    info.requestedPoolSize = poolSize;
    info.availablePoolSize = nAvailable;
    info.wasReduced = nAvailable < poolSize;
    if nAvailable < poolSize
        warning('acsProposeRoastCandidateGrowth:PoolSizeReduced', ...
            ['Requested poolSize=%d, but only %d eligible candidate vertices ', ...
             'remain after exclusions. Proceeding with all available vertices.'], ...
            poolSize, nAvailable);
        queryPrintMm = candidatePrintMm;
        queryVertex = candidateVertex;
        info.selectedCandidateRows = (1:nAvailable)';
        return;
    end
    if nAvailable == poolSize
        queryPrintMm = candidatePrintMm;
        queryVertex = candidateVertex;
        info.selectedCandidateRows = (1:nAvailable)';
        return;
    end

    selectedRows = farthestPoolSubset(candidatePrintMm, existingPrintMm, poolSize);
    queryPrintMm = candidatePrintMm(selectedRows, :);
    queryVertex = candidateVertex(selectedRows);
    info.selectedCandidateRows = selectedRows(:);
end

function selectedRows = farthestPoolSubset(candidatePrintMm, existingPrintMm, poolSize)
    nAvailable = size(candidatePrintMm, 1);
    selectedRows = zeros(poolSize, 1);
    if isempty(existingPrintMm)
        minDist2 = inf(nAvailable, 1);
    else
        minDist2 = min(pairwiseDistanceSquared(candidatePrintMm, existingPrintMm), [], 2);
    end
    for i = 1:poolSize
        [~, row] = max(minDist2);
        selectedRows(i) = row;
        d2 = pairwiseDistanceSquared(candidatePrintMm, candidatePrintMm(row, :));
        minDist2 = min(minDist2, d2);
        minDist2(selectedRows(1:i)) = -inf;
    end
end

function [eligible, info] = excludeNearbyPoolPoints(poolPrintMm, existingPrintMm, ...
        minDistanceMm)
    D = sqrt(pairwiseDistanceSquared(poolPrintMm, existingPrintMm));
    nearestExisting = min(D, [], 2);
    eligible = nearestExisting >= minDistanceMm;
    info = struct();
    info.minDistanceFromExistingMm = minDistanceMm;
    info.minimumRemainingDistanceMm = min(nearestExisting(eligible));
    info.nearestExistingDistanceMm = nearestExisting;
    info.excludedNearExistingCount = nnz(~eligible);
end

function [trainingPrintMm, trainingNames] = trainingPositionsForLeadField( ...
        layoutNames, existingPrintMm, stimulusNames)
    trainingPrintMm = zeros(numel(stimulusNames), 3);
    trainingNames = stimulusNames(:);
    for i = 1:numel(stimulusNames)
        idx = find(strcmpi(stimulusNames{i}, layoutNames), 1);
        if isempty(idx)
            error('acsProposeRoastCandidateGrowth:MissingStimulusPosition', ...
                'No layout coordinate found for stimulus electrode "%s".', ...
                stimulusNames{i});
        end
        trainingPrintMm(i, :) = existingPrintMm(idx, :);
    end
end

function [projection, gram, info] = residualFeatureStatistics(A_all, meshData, sparse)
    V = spm_vol(sparse.t1File);
    voxelSize = [V.mat(1, 1), V.mat(2, 2), V.mat(3, 3)];
    brainNodes = findBrainNodes(meshData.elem);
    targetNodes = findTargetNodes(meshData.node, brainNodes, sparse.targetVoxel, ...
        voxelSize, sparse.targetRadiusMm);
    desiredIntensityVm = getOptionalField(sparse, 'desiredIntensityVm', 1);
    focalityK = getOptionalField(sparse, 'focalityK', 0.02);
    [weightedDesign, weightedDesired, targetMask] = buildWeightedFocalSystem( ...
        A_all, brainNodes, targetNodes, sparse.orientation, ...
        sparse.targetWeights, desiredIntensityVm, focalityK);
    coefficients = double(sparse.basisCoefficientsMa(:));
    if size(weightedDesign, 2) ~= numel(coefficients)
        error('acsProposeRoastCandidateGrowth:BadCoefficientCount', ...
            'Sparse result has %d basis coefficients, but A_all has %d columns.', ...
            numel(coefficients), size(weightedDesign, 2));
    end
    residual = weightedDesired - weightedDesign * coefficients;
    projection = weightedDesign' * residual;
    gram = weightedDesign' * weightedDesign;

    info = struct();
    info.brainNodeCount = numel(brainNodes);
    info.targetBrainNodeCount = nnz(targetMask);
    info.weightedResidualNorm = norm(residual);
    info.weightedDesiredNorm = norm(weightedDesired);
    info.desiredIntensityVm = desiredIntensityVm;
    info.focalityK = focalityK;
end

function brainNodes = findBrainNodes(elem)
    brainElem = elem(:, 5) == 1 | elem(:, 5) == 2;
    brainNodes = unique(elem(brainElem, 1:4));
    brainNodes = brainNodes(:);
end

function targetNodes = findTargetNodes(node, brainNodes, targetVoxel, voxelSize, radiusMm)
    brainMm = double(node(brainNodes, 1:3));
    targetMm = bsxfun(@times, double(targetVoxel), voxelSize);
    targetNodes = cell(size(targetVoxel, 1), 1);
    for i = 1:size(targetVoxel, 1)
        delta = bsxfun(@minus, brainMm, targetMm(i, :));
        inside = sqrt(sum(delta .^ 2, 2)) < radiusMm;
        targetNodes{i} = brainNodes(inside);
        if isempty(targetNodes{i})
            error('acsProposeRoastCandidateGrowth:NoTargetNodes', ...
                'No brain mesh nodes were found within targetRadiusMm.');
        end
    end
end

function [weightedDesign, weightedDesired, targetMask] = buildWeightedFocalSystem( ...
        A_all, brainNodes, targetNodes, orientation, targetWeights, ...
        desiredIntensityVm, focalityK)
    nBrain = numel(brainNodes);
    nBasis = size(A_all, 3);
    designMatrix = zeros(nBrain * 3, nBasis);
    designMatrix(1:nBrain, :) = reshape(A_all(brainNodes, 1, :), ...
        nBrain, nBasis);
    designMatrix(nBrain + (1:nBrain), :) = reshape(A_all(brainNodes, 2, :), ...
        nBrain, nBasis);
    designMatrix(2 * nBrain + (1:nBrain), :) = reshape(A_all(brainNodes, 3, :), ...
        nBrain, nBasis);

    orientation = normalizeOrientations(orientation, numel(targetNodes));
    targetWeights = normalizeWeights(targetWeights, numel(targetNodes));
    desiredByNode = zeros(nBrain, 3);
    targetPriority = zeros(nBrain, 1);
    for i = 1:numel(targetNodes)
        [tf, localIdx] = ismember(targetNodes{i}, brainNodes);
        localIdx = localIdx(tf);
        desiredByNode(localIdx, :) = desiredByNode(localIdx, :) + ...
            targetWeights(i) * repmat(orientation(i, :), numel(localIdx), 1);
        targetPriority(localIdx) = targetPriority(localIdx) + targetWeights(i);
    end
    targetMask = targetPriority > 0;
    desiredByNode(targetMask, :) = desiredIntensityVm * bsxfun(@rdivide, ...
        desiredByNode(targetMask, :), targetPriority(targetMask));
    desiredField = [desiredByNode(:, 1); desiredByNode(:, 2); ...
        desiredByNode(:, 3)];

    nTarget = nnz(targetMask);
    nNontarget = nBrain - nTarget;
    targetWeight = nBrain / nTarget * (focalityK / (focalityK + 1));
    nontargetWeight = nTarget / nNontarget * (targetWeight / focalityK);
    nodeWeights = nontargetWeight * ones(nBrain, 1);
    nodeWeights(targetMask) = targetWeight;
    weights = [nodeWeights; nodeWeights; nodeWeights];
    sqrtWeights = sqrt(weights(:));
    weightedDesign = bsxfun(@times, designMatrix, sqrtWeights);
    weightedDesired = sqrtWeights .* desiredField;
end

function orientation = normalizeOrientations(orientation, nTargets)
    orientation = double(orientation);
    if size(orientation, 1) == 1 && nTargets > 1
        orientation = repmat(orientation, nTargets, 1);
    end
    lengths = sqrt(sum(orientation .^ 2, 2));
    orientation = bsxfun(@rdivide, orientation, lengths);
end

function weights = normalizeWeights(weights, nTargets)
    weights = double(weights(:));
    if isempty(weights)
        weights = ones(nTargets, 1);
    end
    weights = weights / sum(weights);
end

function [surrogate, info] = addAcquisitionScores(surrogate, ...
        trainingPrintMm, queryPrintMm, opts)
    utility = double(surrogate.residualImprovementScore(:));
    if isempty(utility)
        error('acsProposeRoastCandidateGrowth:MissingSurrogateUtility', ...
            'Kernel surrogate did not return residualImprovementScore.');
    end
    if strcmp(opts.acquisitionMode, 'ucb')
        uncertainty = candidateUncertainty(surrogate, trainingPrintMm, ...
            queryPrintMm, opts);
    else
        uncertainty = zeros(size(utility));
    end

    utilityTerm = utility;
    uncertaintyTerm = uncertainty;
    if strcmp(opts.acquisitionMode, 'ucb') && opts.ucbNormalizeTerms
        utilityTerm = normalizeFiniteUnitInterval(utility);
        uncertaintyTerm = normalizeFiniteUnitInterval(uncertainty);
    end

    switch opts.acquisitionMode
        case 'predictedUtility'
            acquisition = utility;
        case 'ucb'
            acquisition = utilityTerm + opts.ucbBeta * uncertaintyTerm;
        otherwise
            error('acsProposeRoastCandidateGrowth:BadAcquisitionMode', ...
                'Unsupported acquisitionMode "%s".', opts.acquisitionMode);
    end

    surrogate.utilityScore = utility;
    surrogate.uncertaintyScore = uncertainty;
    surrogate.utilityTerm = utilityTerm;
    surrogate.uncertaintyTerm = uncertaintyTerm;
    surrogate.acquisitionScore = acquisition;

    info = struct();
    info.mode = opts.acquisitionMode;
    info.ucbBeta = opts.ucbBeta;
    info.ucbUncertaintyMode = opts.ucbUncertaintyMode;
    info.ucbNormalizeTerms = opts.ucbNormalizeTerms;
    info.ucbRidge = opts.ucbRidge;
    info.utilityRange = finiteRange(utility);
    info.uncertaintyRange = finiteRange(uncertainty);
    info.acquisitionRange = finiteRange(acquisition);
end

function uncertainty = candidateUncertainty(surrogate, trainingPrintMm, ...
        queryPrintMm, opts)
    switch opts.ucbUncertaintyMode
        case 'kernelVariance'
            uncertainty = kernelVarianceUncertainty(surrogate, ...
                trainingPrintMm, opts);
        case 'kernelSupport'
            uncertainty = kernelSupportUncertainty(surrogate);
        case 'nearestDistance'
            uncertainty = nearestDistanceUncertainty(surrogate);
        otherwise
            error('acsProposeRoastCandidateGrowth:BadUncertaintyMode', ...
                'Unsupported uncertainty mode "%s".', opts.ucbUncertaintyMode);
    end
    uncertainty = double(uncertainty(:));
    if numel(uncertainty) ~= size(queryPrintMm, 1)
        error('acsProposeRoastCandidateGrowth:BadUncertaintySize', ...
            'Uncertainty vector does not match the query pool size.');
    end
    uncertainty(~isfinite(uncertainty)) = 0;
end

function uncertainty = kernelVarianceUncertainty(surrogate, trainingPrintMm, opts)
    trainD2 = pairwiseDistanceSquared(trainingPrintMm, trainingPrintMm);
    K = exp(-trainD2 ./ (2 * surrogate.sigmaMm ^ 2));
    K = K + opts.ucbRidge * eye(size(K));
    queryTrainK = double(surrogate.rawWeights);
    try
        alpha = K \ queryTrainK';
        variance = 1 - sum(queryTrainK' .* alpha, 1)';
    catch
        warning('acsProposeRoastCandidateGrowth:KernelVarianceFailed', ...
            'Kernel variance solve failed; falling back to nearest-distance uncertainty.');
        variance = nearestDistanceUncertainty(surrogate);
    end
    uncertainty = sqrt(max(variance, 0));
end

function uncertainty = kernelSupportUncertainty(surrogate)
    support = log1p(max(double(surrogate.weightTotal(:)), 0));
    uncertainty = 1 - normalizeFiniteUnitInterval(support);
end

function uncertainty = nearestDistanceUncertainty(surrogate)
    dMin = min(double(surrogate.distanceMm), [], 2);
    uncertainty = 1 - exp(-(dMin .^ 2) ./ (2 * surrogate.sigmaMm ^ 2));
end

function y = normalizeFiniteUnitInterval(x)
    x = double(x(:));
    y = zeros(size(x));
    finite = isfinite(x);
    if ~any(finite)
        return;
    end
    lo = min(x(finite));
    hi = max(x(finite));
    if hi <= lo
        return;
    end
    y(finite) = (x(finite) - lo) ./ (hi - lo);
end

function r = finiteRange(x)
    x = double(x(:));
    x = x(isfinite(x));
    if isempty(x)
        r = [NaN NaN];
    else
        r = [min(x) max(x)];
    end
end

function [rows, info] = greedySelectByScore(queryPrintMm, score, nNew, minDistanceMm, opts)
    if nargin < 5
        opts = struct('verbose', true);
    end
    score = double(score(:));
    score(~isfinite(score)) = -inf;
    if numel(score) < nNew
        error('acsProposeRoastCandidateGrowth:TooFewScoredCandidates', ...
            'Only %d scored candidates are available for %d requested new sites.', ...
            numel(score), nNew);
    end

    requestedDistanceMm = double(minDistanceMm);
    distanceSchedule = unique([requestedDistanceMm, ...
        0.75 * requestedDistanceMm, ...
        0.5 * requestedDistanceMm, ...
        0.25 * requestedDistanceMm, ...
        0], 'stable');
    distanceSchedule = distanceSchedule(isfinite(distanceSchedule) & ...
        distanceSchedule >= 0);
    if isempty(distanceSchedule)
        distanceSchedule = 0;
    end

    bestRows = zeros(0, 1);
    bestDistance = NaN;
    for k = 1:numel(distanceSchedule)
        [candidateRows, selected] = greedySelectAtDistance( ...
            queryPrintMm, score, nNew, distanceSchedule(k));
        if selected == nNew
            rows = candidateRows;
            info = selectionInfo(rows, queryPrintMm, requestedDistanceMm, ...
                distanceSchedule(k), k);
            if distanceSchedule(k) < requestedDistanceMm && shouldWarn(opts)
                warning('acsProposeRoastCandidateGrowth:RelaxedNewCandidateSpacing', ...
                    ['Only %d candidates satisfied minDistanceAmongNewMm=%.3g mm. ', ...
                     'Relaxed new-new spacing to %.3g mm for this growth step. ', ...
                     'Existing-electrode spacing and exclusion masks were not relaxed.'], ...
                    numel(bestRows), requestedDistanceMm, distanceSchedule(k));
            end
            return;
        end
        if selected > numel(bestRows)
            bestRows = candidateRows(1:selected);
            bestDistance = distanceSchedule(k);
        end
    end

    [~, order] = sort(score, 'descend');
    rows = order(1:nNew);
    info = selectionInfo(rows, queryPrintMm, requestedDistanceMm, 0, ...
        numel(distanceSchedule));
    info.fallback = 'scoreOnly';
    info.bestSpacedCount = numel(bestRows);
    info.bestSpacedDistanceMm = bestDistance;
    if shouldWarn(opts)
        warning('acsProposeRoastCandidateGrowth:ScoreOnlyNewCandidateFill', ...
            ['Could not place %d new candidates with any positive new-new spacing; ', ...
             'using the top %d acquisition-score candidates. Existing-electrode ', ...
             'spacing and exclusion masks were not relaxed.'], nNew, nNew);
    end
end

function tf = shouldWarn(opts)
    tf = true;
    if isstruct(opts) && isfield(opts, 'verbose')
        tf = logical(opts.verbose);
    end
end

function [rows, selected] = greedySelectAtDistance(queryPrintMm, score, nNew, minDistanceMm)
    [~, order] = sort(score, 'descend');
    rows = zeros(nNew, 1);
    selected = 0;
    for i = 1:numel(order)
        row = order(i);
        if selected > 0
            D = sqrt(sum(bsxfun(@minus, queryPrintMm(rows(1:selected), :), ...
                queryPrintMm(row, :)) .^ 2, 2));
            if any(D < minDistanceMm)
                continue;
            end
        end
        selected = selected + 1;
        rows(selected) = row;
        if selected == nNew
            break;
        end
    end
end

function info = selectionInfo(rows, queryPrintMm, requestedDistanceMm, actualDistanceMm, scheduleIndex)
    P = queryPrintMm(rows(:), :);
    d = pairwiseDistances(P);
    info = struct();
    info.requestedMinDistanceMm = requestedDistanceMm;
    info.actualMinDistanceMm = actualDistanceMm;
    info.scheduleIndex = scheduleIndex;
    info.minimumSelectedPairDistanceMm = minFiniteOrInf(d);
    info.meanSelectedPairDistanceMm = meanFiniteOrNaN(d);
    info.fallback = '';
end

function d = pairwiseDistances(P)
    n = size(P, 1);
    d = zeros(0, 1);
    for i = 1:n-1
        delta = bsxfun(@minus, P(i + 1:n, :), P(i, :));
        d = [d; sqrt(sum(delta .^ 2, 2))]; %#ok<AGROW>
    end
end

function value = minFiniteOrInf(x)
    x = x(isfinite(x));
    if isempty(x)
        value = inf;
    else
        value = min(x);
    end
end

function value = meanFiniteOrNaN(x)
    x = x(isfinite(x));
    if isempty(x)
        value = NaN;
    else
        value = mean(x);
    end
end

function names = nextCustomNames(existingNames, nNew)
    nums = nan(numel(existingNames), 1);
    for i = 1:numel(existingNames)
        tok = regexp(existingNames{i}, '^custom(\d+)$', 'tokens', 'once');
        if ~isempty(tok)
            nums(i) = str2double(tok{1});
        end
    end
    startNum = max(nums(isfinite(nums)));
    if isempty(startNum)
        startNum = numel(existingNames);
    end
    names = arrayfun(@(i) sprintf('custom%d', startNum + i), ...
        (1:nNew)', 'UniformOutput', false);
end

function report = compactKernelReport(surrogate, trainingNames, ...
        trainingPrintMm, queryPrintMm)
    report = struct();
    report.sigmaMm = surrogate.sigmaMm;
    report.trainingNames = trainingNames(:);
    report.trainingPositionsMm = trainingPrintMm;
    report.queryCount = size(queryPrintMm, 1);
    report.weightTotalRange = [min(surrogate.weightTotal), ...
        max(surrogate.weightTotal)];
    if isfield(surrogate, 'uncertaintyScore')
        report.uncertaintyRange = finiteRange(surrogate.uncertaintyScore);
    end
    if isfield(surrogate, 'acquisitionScore')
        report.acquisitionRange = finiteRange(surrogate.acquisitionScore);
    end
    if isfield(surrogate, 'leaveOneOut') && ...
            isfield(surrogate.leaveOneOut, 'medianRelativeColumnError')
        report.leaveOneOut = surrogate.leaveOneOut;
    end
end

function info = compactPoolInfo(poolInfo)
    info = poolInfo;
    heavyFields = {'candidateVertex', 'eligibleMask', 'bottomVertexMask', ...
        'bottomFaceMask', 'rimSeeds', 'distRimMM', 'normalMask', ...
        'visibilityMask', 'exclusionMask', 'earExclusionMask', ...
        'headpostExclusionMask', 'customExclusionMask', 'meshEdges', ...
        'distMidlineMM', 'coverageVertex', 'coverageMask', ...
        'voronoiCellIndex', 'voronoiDistanceMM', ...
        'region', 'regionR', 'headpostPoly', 'earPolys'};
    for i = 1:numel(heavyFields)
        if isfield(info, heavyFields{i})
            info = rmfield(info, heavyFields{i});
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

function fig = makeProposalFigure(TRskin, existingPrintMm, queryPrintMm, ...
        newPrintMm, surrogate, out, figVisible)
    V = double(TRskin.Points);
    sampleRows = sampleRowsEvenly(size(V, 1), 25000);
    fig = figure('Name', 'ROAST surrogate candidate growth QC', ...
        'Color', 'w', 'Visible', figVisible, 'Units', 'pixels', ...
        'Position', [100 100 1600 520]);

    ax1 = subplot(1, 3, 1, 'Parent', fig);
    hold(ax1, 'on');
    scatter3(ax1, V(sampleRows, 1), V(sampleRows, 2), V(sampleRows, 3), ...
        2, [0.78 0.78 0.78], 'filled');
    scatter3(ax1, existingPrintMm(:, 1), existingPrintMm(:, 2), ...
        existingPrintMm(:, 3), 48, [0.1 0.1 0.1], 'filled');
    scatter3(ax1, newPrintMm(:, 1), newPrintMm(:, 2), ...
        newPrintMm(:, 3), 70, [0.9 0.1 0.1], 'filled');
    axis(ax1, 'equal');
    grid(ax1, 'on');
    view(ax1, 35, 25);
    xlabel(ax1, 'capMaker X (mm)');
    ylabel(ax1, 'capMaker Y (mm)');
    zlabel(ax1, 'capMaker Z (mm)');
    title(ax1, 'Existing and proposed candidates');

    ax2 = subplot(1, 3, 2, 'Parent', fig);
    score = surrogate.acquisitionScore;
    scatter3(ax2, queryPrintMm(:, 1), queryPrintMm(:, 2), queryPrintMm(:, 3), ...
        18, score, 'filled');
    hold(ax2, 'on');
    scatter3(ax2, newPrintMm(:, 1), newPrintMm(:, 2), newPrintMm(:, 3), ...
        90, [0 0 0], 'o', 'LineWidth', 1.5);
    axis(ax2, 'equal');
    grid(ax2, 'on');
    view(ax2, 35, 25);
    colorbar(ax2);
    xlabel(ax2, 'capMaker X (mm)');
    ylabel(ax2, 'capMaker Y (mm)');
    zlabel(ax2, 'capMaker Z (mm)');
    title(ax2, sprintf('Virtual acquisition score (%s)', out.acquisition.mode));

    ax3 = subplot(1, 3, 3, 'Parent', fig);
    sortedScore = sort(score(isfinite(score)), 'descend');
    plot(ax3, sortedScore, 'k-', 'LineWidth', 1.2);
    hold(ax3, 'on');
    yline(ax3, min(out.newAcquisitionScore), 'r--', 'LineWidth', 1.2);
    xlabel(ax3, 'Virtual candidate rank');
    ylabel(ax3, 'Acquisition score');
    title(ax3, sprintf('Selected %d new candidates, sigma %.3g mm', ...
        out.nNew, out.kernel.sigmaMm));
    grid(ax3, 'on');
end

function rows = sampleRowsEvenly(nRows, maxRows)
    if nRows <= maxRows
        rows = (1:nRows)';
    else
        rows = unique(round(linspace(1, nRows, maxRows)))';
    end
end

function printSummary(out)
    fprintf('\nROAST surrogate candidate growth\n');
    fprintf('  lead field tag: %s\n', out.leadFieldTag);
    fprintf('  existing candidates: %d\n', out.nExisting);
    fprintf('  proposed new candidates: %d\n', out.nNew);
    fprintf('  expanded candidates: %d\n', out.nExpanded);
    fprintf('  virtual pool after spacing: %d\n', out.poolSizeEligible);
    fprintf('  minimum center spacing from existing/new electrodes: %.6g / %.6g mm\n', ...
        out.minDistanceFromExistingMm, out.minDistanceAmongNewMm);
    if isfield(out, 'actualMinDistanceAmongNewMm') && ...
            out.actualMinDistanceAmongNewMm < out.minDistanceAmongNewMm
        fprintf('  relaxed new-new spacing used: %.6g mm; selected pair min %.6g mm\n', ...
            out.actualMinDistanceAmongNewMm, ...
            out.newSpacingInfo.minimumSelectedPairDistanceMm);
    end
    fprintf('  kernel sigma: %.6g mm\n', out.kernel.sigmaMm);
    fprintf('  acquisition mode: %s', out.acquisition.mode);
    if strcmp(out.acquisition.mode, 'ucb')
        fprintf(' (beta %.6g, uncertainty %s)', ...
            out.acquisition.ucbBeta, out.acquisition.ucbUncertaintyMode);
    end
    fprintf('\n');
    if isfield(out.kernel, 'leaveOneOut') && ...
            isfield(out.kernel.leaveOneOut, 'medianRelativeColumnError')
        fprintf('  kernel LOO median relative column error: %.6g\n', ...
            out.kernel.leaveOneOut.medianRelativeColumnError);
    end
    fprintf('  proposed candidates:\n');
    for i = 1:numel(out.newNames)
        fprintf(['    %s: [%.3f %.3f %.3f] acquisition %.6g, ', ...
            'utility %.6g, uncertainty %.6g, sign %+g\n'], ...
            out.newNames{i}, out.newLayoutCoordinatesMm(i, 1), ...
            out.newLayoutCoordinatesMm(i, 2), out.newLayoutCoordinatesMm(i, 3), ...
            out.newAcquisitionScore(i), out.newSurrogateScore(i), ...
            out.newUncertaintyScore(i), out.newPreferredCurrentSign(i));
    end
    if isempty(out.expandedLayout)
        fprintf('  expanded customLocations not written; rerun with makeLayout=true when ready.\n');
    else
        fprintf('  expanded customLocations: %s\n', ...
            out.expandedLayout.customLocationsFile);
    end
    fprintf('\n');
end

function D2 = pairwiseDistanceSquared(A, B)
    A = double(A);
    B = double(B);
    D2 = bsxfun(@plus, sum(A .^ 2, 2), sum(B .^ 2, 2)') - 2 * (A * B');
    D2 = max(D2, 0);
end

function value = getOptionalField(S, fieldName, defaultValue)
    if isstruct(S) && isfield(S, fieldName) && ~isempty(S.(fieldName))
        value = S.(fieldName);
    else
        value = defaultValue;
    end
end

function tag = safeTag(tag)
    tag = regexprep(strtrim(char(tag)), '[^A-Za-z0-9_-]+', '_');
    tag = regexprep(tag, '_+', '_');
    tag = regexprep(tag, '^_+|_+$', '');
    if isempty(tag)
        error('acsProposeRoastCandidateGrowth:BadProposalTag', ...
            'proposalTag must contain at least one filename-safe character.');
    end
end

function [fileStem, info] = compactGrowthFileStem(t1Stem, leadFieldTag, ...
        proposalTag, out, opts)
    subjectTag = getOptionalField(out, 'subjectId', '');
    if isempty(subjectTag)
        subjectTag = parseSubjectTag(t1Stem);
    end
    rangeTag = sprintf('grow%dto%d', out.nExisting, out.nExpanded);
    versionTag = parseVersionTag(proposalTag);
    hashInput = strjoin({t1Stem, leadFieldTag, proposalTag, ...
        sprintf('%d', out.nExisting), sprintf('%d', out.nExpanded)}, '|');
    hashTag = shortHash(hashInput);

    parts = {subjectTag, rangeTag};
    if ~isempty(versionTag)
        parts{end + 1} = versionTag; %#ok<AGROW>
    end
    parts{end + 1} = hashTag;
    fileStem = safeFileStem(strjoin(parts, '_'));

    if numel(fileStem) > opts.maxFilenameBaseChars
        keepN = max(16, opts.maxFilenameBaseChars - numel(hashTag) - 1);
        fileStem = [fileStem(1:keepN) '_' hashTag];
        fileStem = safeFileStem(fileStem);
    end

    info = struct();
    info.mode = 'compactHash';
    info.fileStem = fileStem;
    info.maxFilenameBaseChars = opts.maxFilenameBaseChars;
    info.longStem = safeFileStem([t1Stem '_' leadFieldTag '_' proposalTag]);
    info.hash = hashTag;
    info.subjectTag = subjectTag;
    info.rangeTag = rangeTag;
    info.versionTag = versionTag;
    info.leadFieldTag = leadFieldTag;
    info.proposalTag = proposalTag;
end

function tag = parseSubjectTag(stem)
    stem = char(stem);
    tokens = regexp(stem, '(M\d+)', 'tokens', 'once');
    if ~isempty(tokens)
        tag = tokens{1};
        return;
    end
    parts = regexp(stem, '[_-]+', 'split');
    tag = parts{1};
    if isempty(tag)
        tag = 'subject';
    end
    tag = safeFileStem(tag);
end

function tag = parseVersionTag(proposalTag)
    tag = '';
    token = regexp(char(proposalTag), '(^|[_-])(v\d+)$', 'tokens', 'once');
    if ~isempty(token)
        tag = token{2};
    end
end

function stem = safeFileStem(stem)
    stem = regexprep(strtrim(char(stem)), '[^A-Za-z0-9_-]+', '_');
    stem = regexprep(stem, '_+', '_');
    stem = regexprep(stem, '^_+|_+$', '');
    if isempty(stem)
        stem = 'growth';
    end
end

function h = shortHash(txt)
    txt = uint8(char(txt));
    value = 5381;
    modulus = 2 ^ 32;
    for i = 1:numel(txt)
        value = mod(value * 33 + double(txt(i)), modulus);
    end
    h = lower(dec2hex(round(value), 8));
end

function saveQcFigure(fig, qcFile)
    try
        exportgraphics(fig, qcFile, 'Resolution', 150);
    catch
        saveas(fig, qcFile);
    end
end

function ensureDir(pathIn)
    if isempty(pathIn)
        return;
    end
    if exist(pathIn, 'dir') ~= 7
        mkdir(pathIn);
    end
end

function p = expandUserPath(p)
    p = char(p);
    if isempty(p)
        return;
    end
    if startsWith(p, '~')
        homeDir = getenv('USERPROFILE');
        if isempty(homeDir)
            homeDir = getenv('HOME');
        end
        p = fullfile(homeDir, extractAfter(p, 1));
    end
end

function p = canonicalPath(p)
    p = expandUserPath(p);
    if isempty(p)
        return;
    end
    try
        p = char(java.io.File(p).getCanonicalPath());
    catch
        p = char(p);
    end
end

function logMsg(opts, varargin)
    if opts.verbose
        fprintf([varargin{1} '\n'], varargin{2:end});
    end
end
