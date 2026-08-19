function out = acsSegmentAnatomyWithTpm(subjectId, varargin)
% ACSSEGMENTANATOMYWITHTPM Segment an individual anatomy with a macaque TPM.
%
% out = acsSegmentAnatomyWithTpm('M2107') runs SPM unified segmentation on
% the imported subject T1 using a six-channel macaque TPM. Outputs are
% written under the subject's ignored segmentation work directory.
%
% The TPM is assumed to use ROAST/SPM channel order:
%   1 gray matter, 2 white matter, 3 CSF, 4 bone, 5 skin/scalp, 6 air.
%
% Name-value options:
%   t1File                 : explicit subject T1 NIfTI ['']
%   tpmFile                : explicit six-channel TPM NIfTI ['']
%   priorDir               : folder searched for defaultMonkeyTpm.nii ['']
%   outputDir              : subject segmentation output folder ['']
%   segmentationTag        : optional subfolder name for comparison runs ['']
%   defaultTpmName         : default TPM filename ['defaultMonkeyTpm.nii']
%   makeTpmIfMissing       : call templateMaker if no default TPM is found [false]
%   templateMode           : templateMaker mode if building TPM ['atlasPriors']
%   t1Orientation          : raw T1 voxel orientation code or 'ask' ['sar']
%   tpmOrientation         : raw TPM voxel orientation code or 'ask' ['ras']
%   tpmOrientationVolume   : TPM channel inspected when tpmOrientation='ask' [1]
%   makeSubjectMasks       : create T1-derived head/interior masks [true]
%   spmMaskMode            : explicit SPM mask: none/head/inner/brain ['head']
%   subjectMaskFile        : explicit mask file overriding spmMaskMode ['']
%   affineRegularization   : SPM affine regularization ['mni']
%   spmInputOrientation    : legacy/debug option; use t1Orientation instead
%   saveNormalized         : save normalized tissue maps [false]
%   forceCopyInput         : recopy T1 into segmentation folder [false]
%   forceSegmentation      : rerun SPM even if outputs exist [false]
%   runTouchup             : also run ROAST segTouchup to make masks [false]
%   anatomicalAxes         : 'scanner', 'macaqueSphinx', or struct ['scanner']
%   planeVoxelDims         : manual [sagittal coronal axial] voxel dims [[]]
%   qcTissues              : contour tissues shown in QC figure
%   qcContourLevel         : probability contour level [0.5]
%   makeMaxTissueQc        : show winner-take-all tissue QC figure [true]
%   qcMaxTissueAlpha       : transparency for max tissue overlay [0.45]
%   qcMaxTissueMinProbability : hide max labels below this probability [0.35]
%   boneMode               : spm, shellPrior, or shellOnly ['shellPrior']
%   boneShellDilateMm      : cranial-shell dilation from brain mask [5]
%   boneShellSmoothMm      : smoothing for fuzzy shell prior [1.5]
%   boneShellBrainThreshold: threshold on c1+c2+c3 brain probability [0.45]
%   boneShellFloor         : bone multiplier outside shell [0.05]
%   boneShellBoost         : bone multiplier added inside shell [8]
%   boneShellAdd           : additive shell bone prior [0.20]
%   makeRoastLabels        : write hard ROAST label volume [true]
%   roastLabelMinProbability : low-confidence argmax becomes air [0.35]
%   roastLabelConstraintMask : outside this mask becomes air ['head']
%   verbose                : print progress [false]
%   showFigures            : show QC figures [false]
%   saveFigures            : save QC figures [false]
%   configFile             : optional local.paths.json override ['']

    if nargin < 1 || isempty(subjectId)
        subjectId = 'M2107';
    end

    opts = parseInputs(varargin{:});
    originalSubjectId = char(subjectId);
    P = acsPaths('configFile', opts.configFile);

    subjectId = canonicalSubjectId(originalSubjectId, opts);
    subjectLabel = safeName(subjectId);

    if isempty(opts.outputDir)
        opts.outputDir = acsSubjectPath(subjectId, 'segmentationWork', ...
            'configFile', opts.configFile);
    end
    if ~isempty(opts.segmentationTag)
        opts.outputDir = fullfile(opts.outputDir, safeName(opts.segmentationTag));
    end
    ensureDir(opts.outputDir);

    addRoastDependencies(P);
    warnIfLegacyOrientationOptionUsed(opts);

    sourceT1 = resolveSubjectT1(subjectId, subjectLabel, opts);
    sourceTpm = resolveTpmFile(P, opts);

    [t1Orientation, t1OrientationInfo] = resolveInputOrientation( ...
        sourceT1, opts.t1Orientation, 'T1', 1, opts);
    [tpmOrientation, tpmOrientationInfo] = resolveInputOrientation( ...
        sourceTpm, opts.tpmOrientation, 'TPM', opts.tpmOrientationVolume, opts);
    opts.t1Orientation = t1Orientation;
    opts.tpmOrientation = tpmOrientation;
    opts.t1OrientationInfo = t1OrientationInfo;
    opts.tpmOrientationInfo = tpmOrientationInfo;
    opts.preparedInputOrientation = 'ras';

    workT1 = prepareRasSegmentationInput(sourceT1, opts.outputDir, ...
        subjectLabel, t1Orientation, opts);
    workTpm = prepareRasTpmInput(sourceTpm, opts.outputDir, ...
        tpmOrientation, opts);
    tpmInfo = validateTpmFile(workTpm);
    subjectMasks = maybeMakeSubjectMasks(workT1, subjectLabel, opts);
    opts.subjectMasks = subjectMasks;
    opts.spmMaskFile = resolveSpmMaskFile(subjectMasks, workT1, opts);

    spmExpected = expectedSpmOutputs(workT1);
    reportBase = [stripNiftiExtension(getFileName(workT1)) '_spmSegmentation'];
    reportMat = fullfile(opts.outputDir, [reportBase 'Report.mat']);
    reportJson = fullfile(opts.outputDir, [reportBase 'Report.json']);

    logMsg(opts, 'Subject: %s', subjectId);
    logMsg(opts, 'Source T1: %s', sourceT1);
    logMsg(opts, 'Segmentation T1: %s', workT1);
    logMsg(opts, 'Source TPM: %s', sourceTpm);
    logMsg(opts, 'Segmentation TPM: %s', workTpm);
    logMsg(opts, 'Output folder: %s', opts.outputDir);
    logMsg(opts, 'T1 raw orientation: %s -> RAS working copy', t1Orientation);
    logMsg(opts, 'TPM raw orientation: %s -> RAS working copy', tpmOrientation);
    logMsg(opts, 'SPM explicit mask: %s', maskFileLabel(opts.spmMaskFile));
    logMsg(opts, 'SPM affine regularization: %s', affineRegularizationLabel(opts.affineRegularization));
    logMsg(opts, 'Bone correction mode: %s', opts.boneMode);
    logMsg(opts, 'Anatomical axes preset: %s', anatomicalAxesName(opts.anatomicalAxes));

    didRunSpm = false;
    if segmentationOutputsExist(spmExpected) && ~opts.forceSegmentation
        logMsg(opts, 'Existing SPM segmentation found; skipping. Use forceSegmentation=true to rerun.');
    else
        runSpmSegmentation(workT1, workTpm, opts);
        didRunSpm = true;
    end

    [activeT1, activeExpected, boneCorrection] = maybeApplyBoneCorrection( ...
        workT1, spmExpected, subjectMasks, opts);
    opts.boneCorrection = boneCorrection;
    roastLabels = maybeMakeRoastLabels(activeT1, activeExpected, subjectMasks, opts);
    opts.roastLabels = roastLabels;
    roastReady = maybeMakeRoastReadyFiles(activeT1, spmExpected, roastLabels, opts);
    opts.roastReady = roastReady;

    touchup = struct('didRun', false, 'outputFile', '', 'maskFile', '');
    if opts.runTouchup
        touchup = runSegTouchupIfNeeded(activeT1, activeExpected, opts);
    end

    qcFiles = maybeMakeSegmentationQcFigures(activeT1, sourceT1, activeExpected, opts);
    if isfield(roastLabels, 'qcFiles') && ~isempty(roastLabels.qcFiles)
        qcFiles = [qcFiles(:); roastLabels.qcFiles(:)];
    end

    out = buildReport(originalSubjectId, subjectId, sourceT1, workT1, ...
        activeT1, sourceTpm, workTpm, tpmInfo, spmExpected, activeExpected, ...
        opts, didRunSpm, touchup, qcFiles);
    out.reportMat = reportMat;
    out.reportJson = reportJson;

    save(reportMat, 'out');
    writeJsonReport(reportJson, out);

    logMsg(opts, 'Saved segmentation report: %s', reportMat);
    if ~isempty(qcFiles)
        logMsg(opts, 'Saved %d QC figure(s).', numel(qcFiles));
    end
end

function opts = parseInputs(varargin)
    p = inputParser;
    p.FunctionName = 'acsSegmentAnatomyWithTpm';
    addParameter(p, 't1File', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'tpmFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'priorDir', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'outputDir', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'segmentationTag', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'defaultTpmName', 'defaultMonkeyTpm.nii', @(x) ischar(x) || isstring(x));
    addParameter(p, 'templateMode', 'atlasPriors', @(x) ischar(x) || isstring(x));
    addParameter(p, 't1Orientation', 'sar', @(x) ischar(x) || isstring(x));
    addParameter(p, 'tpmOrientation', 'ras', @(x) ischar(x) || isstring(x));
    addParameter(p, 'tpmOrientationVolume', 1, ...
        @(x) isnumeric(x) && isscalar(x) && x >= 1);
    addParameter(p, 'makeSubjectMasks', true, @isBoolLike);
    addParameter(p, 'forceSubjectMasks', false, @isBoolLike);
    addParameter(p, 'spmMaskMode', 'head', @(x) ischar(x) || isstring(x));
    addParameter(p, 'subjectMaskFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'maskHeadThreshold', [], ...
        @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x > 0 && x < 1));
    addParameter(p, 'maskHeadThresholdScale', 0.50, ...
        @(x) isnumeric(x) && isscalar(x) && x > 0);
    addParameter(p, 'maskMinHeadThreshold', 0.08, ...
        @(x) isnumeric(x) && isscalar(x) && x >= 0 && x < 1);
    addParameter(p, 'maskCloseRadiusMm', 1.5, ...
        @(x) isnumeric(x) && isscalar(x) && x >= 0);
    addParameter(p, 'maskMinIslandVox', 2000, ...
        @(x) isnumeric(x) && isscalar(x) && x >= 0);
    addParameter(p, 'maskSkinShellMm', 1.5, ...
        @(x) isnumeric(x) && isscalar(x) && x >= 0);
    addParameter(p, 'maskInnerErodeMm', 3, ...
        @(x) isnumeric(x) && isscalar(x) && x >= 0);
    addParameter(p, 'maskBrainErodeMm', 8, ...
        @(x) isnumeric(x) && isscalar(x) && x >= 0);
    addParameter(p, 'affineRegularization', 'mni', @(x) ischar(x) || isstring(x));
    addParameter(p, 'spmInputOrientation', 'native', @(x) ischar(x) || isstring(x));
    addParameter(p, 'anatomicalAxes', 'scanner', ...
        @(x) ischar(x) || isstring(x) || isstruct(x));
    addParameter(p, 'planeVoxelDims', [], ...
        @(x) isempty(x) || (isnumeric(x) && numel(x) == 3));
    addParameter(p, 'qcTissues', {'gray', 'white', 'csf', 'bone', 'skin'}, ...
        @(x) ischar(x) || isstring(x) || iscell(x));
    addParameter(p, 'qcContourLevel', 0.5, ...
        @(x) isnumeric(x) && isscalar(x) && x > 0 && x < 1);
    addParameter(p, 'makeMaxTissueQc', true, @isBoolLike);
    addParameter(p, 'qcMaxTissueAlpha', 0.45, ...
        @(x) isnumeric(x) && isscalar(x) && x >= 0 && x <= 1);
    addParameter(p, 'qcMaxTissueMinProbability', 0.35, ...
        @(x) isnumeric(x) && isscalar(x) && x >= 0 && x <= 1);
    addParameter(p, 'boneMode', 'shellPrior', @(x) ischar(x) || isstring(x));
    addParameter(p, 'forceBoneCorrection', false, @isBoolLike);
    addParameter(p, 'boneShellDilateMm', 5, ...
        @(x) isnumeric(x) && isscalar(x) && x >= 0);
    addParameter(p, 'boneShellSmoothMm', 1.5, ...
        @(x) isnumeric(x) && isscalar(x) && x >= 0);
    addParameter(p, 'boneShellBrainThreshold', 0.45, ...
        @(x) isnumeric(x) && isscalar(x) && x > 0 && x < 1);
    addParameter(p, 'boneShellFloor', 0.05, ...
        @(x) isnumeric(x) && isscalar(x) && x >= 0);
    addParameter(p, 'boneShellBoost', 8, ...
        @(x) isnumeric(x) && isscalar(x) && x >= 0);
    addParameter(p, 'boneShellAdd', 0.20, ...
        @(x) isnumeric(x) && isscalar(x) && x >= 0);
    addParameter(p, 'boneShellConstraintMask', 'innerHead', ...
        @(x) ischar(x) || isstring(x));
    addParameter(p, 'makeRoastLabels', true, @isBoolLike);
    addParameter(p, 'forceRoastLabels', false, @isBoolLike);
    addParameter(p, 'roastLabelMinProbability', 0.35, ...
        @(x) isnumeric(x) && isscalar(x) && x >= 0 && x <= 1);
    addParameter(p, 'roastLabelConstraintMask', 'head', ...
        @(x) ischar(x) || isstring(x));
    addParameter(p, 'roastLabelOverlayAlpha', 0.45, ...
        @(x) isnumeric(x) && isscalar(x) && x >= 0 && x <= 1);
    addParameter(p, 'configFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'makeTpmIfMissing', false, @isBoolLike);
    addParameter(p, 'saveNormalized', false, @isBoolLike);
    addParameter(p, 'forceCopyInput', false, @isBoolLike);
    addParameter(p, 'forceSegmentation', false, @isBoolLike);
    addParameter(p, 'importIfMissing', true, @isBoolLike);
    addParameter(p, 'runTouchup', false, @isBoolLike);
    addParameter(p, 'verbose', false, @isBoolLike);
    addParameter(p, 'showFigures', false, @isBoolLike);
    addParameter(p, 'saveFigures', false, @isBoolLike);
    addParameter(p, 'ngaus', [1 1 2 3 4 2], @(x) isnumeric(x) && numel(x) == 6);
    addParameter(p, 'warpReg', [0 0.001 0.5 0.05 0.2], @(x) isnumeric(x) && numel(x) == 5);
    addParameter(p, 'samplingDistance', 3, @(x) isnumeric(x) && isscalar(x) && x > 0);
    addParameter(p, 'biasReg', 0.001, @(x) isnumeric(x) && isscalar(x));
    addParameter(p, 'biasFwhm', 60, @(x) isnumeric(x) && isscalar(x));
    parse(p, varargin{:});

    opts = p.Results;
    charFields = {'t1File', 'tpmFile', 'priorDir', 'outputDir', 'segmentationTag', ...
        'defaultTpmName', 'templateMode', 'affineRegularization', ...
        'spmInputOrientation', 't1Orientation', 'tpmOrientation', ...
        'spmMaskMode', 'subjectMaskFile', 'boneMode', ...
        'boneShellConstraintMask', 'roastLabelConstraintMask', 'configFile'};
    for i = 1:numel(charFields)
        f = charFields{i};
        opts.(f) = expandUserPath(char(opts.(f)));
    end

    opts.makeTpmIfMissing = logical(opts.makeTpmIfMissing);
    opts.makeSubjectMasks = logical(opts.makeSubjectMasks);
    opts.forceSubjectMasks = logical(opts.forceSubjectMasks);
    opts.saveNormalized = logical(opts.saveNormalized);
    opts.forceCopyInput = logical(opts.forceCopyInput);
    opts.forceSegmentation = logical(opts.forceSegmentation);
    opts.importIfMissing = logical(opts.importIfMissing);
    opts.runTouchup = logical(opts.runTouchup);
    opts.makeMaxTissueQc = logical(opts.makeMaxTissueQc);
    opts.forceBoneCorrection = logical(opts.forceBoneCorrection);
    opts.makeRoastLabels = logical(opts.makeRoastLabels);
    opts.forceRoastLabels = logical(opts.forceRoastLabels);
    opts.verbose = logical(opts.verbose);
    opts.showFigures = logical(opts.showFigures);
    opts.saveFigures = logical(opts.saveFigures);
    opts.ngaus = double(opts.ngaus(:))';
    opts.warpReg = double(opts.warpReg(:))';
    opts.planeVoxelDims = double(opts.planeVoxelDims(:))';
    opts.tpmOrientationVolume = round(double(opts.tpmOrientationVolume));
    opts.affineRegularization = normalizeAffineRegularization(opts.affineRegularization);
    opts.spmInputOrientation = normalizeSpmInputOrientation(opts.spmInputOrientation);
    opts.spmMaskMode = normalizeSpmMaskMode(opts.spmMaskMode);
    opts.maskHeadThreshold = double(opts.maskHeadThreshold);
    opts.maskHeadThresholdScale = double(opts.maskHeadThresholdScale);
    opts.maskMinHeadThreshold = double(opts.maskMinHeadThreshold);
    opts.maskCloseRadiusMm = double(opts.maskCloseRadiusMm);
    opts.maskMinIslandVox = round(double(opts.maskMinIslandVox));
    opts.maskSkinShellMm = double(opts.maskSkinShellMm);
    opts.maskInnerErodeMm = double(opts.maskInnerErodeMm);
    opts.maskBrainErodeMm = double(opts.maskBrainErodeMm);
    opts.qcTissues = normalizeTissueList(opts.qcTissues);
    opts.qcContourLevel = double(opts.qcContourLevel);
    opts.qcMaxTissueAlpha = double(opts.qcMaxTissueAlpha);
    opts.qcMaxTissueMinProbability = double(opts.qcMaxTissueMinProbability);
    opts.boneMode = normalizeBoneMode(opts.boneMode);
    opts.boneShellConstraintMask = normalizeBoneShellConstraintMask(opts.boneShellConstraintMask);
    opts.boneShellDilateMm = double(opts.boneShellDilateMm);
    opts.boneShellSmoothMm = double(opts.boneShellSmoothMm);
    opts.boneShellBrainThreshold = double(opts.boneShellBrainThreshold);
    opts.boneShellFloor = double(opts.boneShellFloor);
    opts.boneShellBoost = double(opts.boneShellBoost);
    opts.boneShellAdd = double(opts.boneShellAdd);
    opts.roastLabelConstraintMask = normalizeRoastLabelConstraintMask(opts.roastLabelConstraintMask);
    opts.roastLabelMinProbability = double(opts.roastLabelMinProbability);
    opts.roastLabelOverlayAlpha = double(opts.roastLabelOverlayAlpha);
end

function mode = normalizeSpmInputOrientation(mode)
    switch lower(strtrim(char(mode)))
        case {'native', 'none', 'asimported'}
            mode = 'native';
        case {'macaquesphinx', 'sphinx'}
            mode = 'macaqueSphinx';
        case {'swapcoronalaxial', 'swapaxialcoronal', 'swap23'}
            mode = 'swapCoronalAxial';
        otherwise
            error('acsSegmentAnatomyWithTpm:BadSpmInputOrientation', ...
                ['Unknown spmInputOrientation "%s". Use "native", ', ...
                '"macaqueSphinx", or "swapCoronalAxial".'], ...
                char(mode));
    end
end

function mode = normalizeSpmMaskMode(mode)
    switch lower(strtrim(char(mode)))
        case {'', 'none', 'off', 'false', 'no'}
            mode = 'none';
        case {'head', 'headmask', 'outer', 'wholehead'}
            mode = 'head';
        case {'inner', 'innerhead', 'insidehead'}
            mode = 'innerHead';
        case {'brain', 'brainsearch', 'search'}
            mode = 'brainSearch';
        otherwise
            error('acsSegmentAnatomyWithTpm:BadSpmMaskMode', ...
                ['Unknown spmMaskMode "%s". Use "none", "head", ', ...
                 '"innerHead", or "brainSearch".'], char(mode));
    end
end

function mode = normalizeBoneMode(mode)
    switch lower(strtrim(char(mode)))
        case {'spm', 'none', 'off'}
            mode = 'spm';
        case {'shellprior', 'prior', 'craniumshell', 'cranialshell'}
            mode = 'shellPrior';
        case {'shellonly', 'deterministic', 'replace'}
            mode = 'shellOnly';
        otherwise
            error('acsSegmentAnatomyWithTpm:BadBoneMode', ...
                'Unknown boneMode "%s". Use "spm", "shellPrior", or "shellOnly".', ...
                char(mode));
    end
end

function mode = normalizeBoneShellConstraintMask(mode)
    mode = strtrim(char(mode));
    switch lower(mode)
        case {'', 'none', 'off'}
            mode = 'none';
        case {'head', 'headmask'}
            mode = 'head';
        case {'inner', 'innerhead', 'insidehead'}
            mode = 'innerHead';
        case {'brain', 'brainsearch'}
            mode = 'brainSearch';
        otherwise
            if exist(expandUserPath(mode), 'file') == 2
                mode = expandUserPath(mode);
            else
                error('acsSegmentAnatomyWithTpm:BadBoneShellConstraintMask', ...
                    ['Unknown boneShellConstraintMask "%s". Use "none", "head", ', ...
                     '"innerHead", "brainSearch", or an explicit mask file.'], mode);
            end
    end
end

function mode = normalizeRoastLabelConstraintMask(mode)
    mode = strtrim(char(mode));
    switch lower(mode)
        case {'', 'none', 'off'}
            mode = 'none';
        case {'head', 'headmask'}
            mode = 'head';
        case {'inner', 'innerhead', 'insidehead'}
            mode = 'innerHead';
        case {'brain', 'brainsearch'}
            mode = 'brainSearch';
        otherwise
            candidate = expandUserPath(mode);
            if exist(candidate, 'file') == 2
                mode = candidate;
            else
                error('acsSegmentAnatomyWithTpm:BadRoastLabelConstraintMask', ...
                    ['Unknown roastLabelConstraintMask "%s". Use "none", "head", ', ...
                     '"innerHead", "brainSearch", or an explicit mask file.'], mode);
            end
    end
end

function affreg = normalizeAffineRegularization(affreg)
    affreg = strtrim(char(affreg));
    switch lower(affreg)
        case {'', 'noaffine', 'noaffineregistration'}
            affreg = '';
        case {'mni', 'eastern', 'subj', 'none'}
            affreg = lower(affreg);
        otherwise
            error('acsSegmentAnatomyWithTpm:BadAffineRegularization', ...
                ['Unknown affineRegularization "%s". Use "mni", "eastern", ', ...
                '"subj", "none", or "" for no affine registration.'], affreg);
    end
end

function label = affineRegularizationLabel(affreg)
    if isempty(affreg)
        label = '<none: no affine registration>';
    else
        label = affreg;
    end
end

function tf = isBoolLike(x)
    tf = (islogical(x) || isnumeric(x)) && isscalar(x);
end

function tissues = normalizeTissueList(tissues)
    if ischar(tissues) || isstring(tissues)
        tissues = cellstr(string(tissues));
    elseif iscell(tissues)
        tissues = cellfun(@char, tissues(:), 'UniformOutput', false);
    else
        tissues = {'gray', 'white', 'csf', 'bone', 'skin'};
    end
    tissues = tissues(:)';
end

function name = anatomicalAxesName(anatomicalAxes)
    if isstruct(anatomicalAxes)
        if isfield(anatomicalAxes, 'name') && ~isempty(anatomicalAxes.name)
            name = char(anatomicalAxes.name);
        else
            name = 'custom';
        end
    else
        name = char(anatomicalAxes);
    end
end

function subjectId = canonicalSubjectId(requestedSubjectId, opts)
    subjectId = char(requestedSubjectId);
    try
        subjectRoot = acsSubjectPath(subjectId, 'output', ...
            'configFile', opts.configFile);
        [~, resolvedId] = fileparts(subjectRoot);
        if ~isempty(resolvedId)
            subjectId = resolvedId;
        end
    catch
        subjectId = upper(subjectId);
    end
end

function sourceT1 = resolveSubjectT1(subjectId, subjectLabel, opts)
    if ~isempty(opts.t1File)
        sourceT1 = opts.t1File;
    else
        anatomyDir = acsSubjectPath(subjectId, 'anatomyWork', ...
            'configFile', opts.configFile);
        sourceT1 = fullfile(anatomyDir, [subjectLabel '_T1.nii']);
    end

    if exist(sourceT1, 'file') == 2
        return;
    end

    if opts.importIfMissing && isempty(opts.t1File)
        logMsg(opts, 'Subject T1 not found; importing DICOM anatomy first.');
        importOut = acsImportDicomAnatomy(subjectId, ...
            'verbose', opts.verbose, ...
            'showFigures', false, ...
            'saveFigures', false, ...
            'configFile', opts.configFile);
        sourceT1 = importOut.outputFile;
        return;
    end

    error('acsSegmentAnatomyWithTpm:T1NotFound', ...
        'Subject T1 NIfTI not found: %s', sourceT1);
end

function warnIfLegacyOrientationOptionUsed(opts)
    if isfield(opts, 'spmInputOrientation') && ~strcmp(opts.spmInputOrientation, 'native')
        warning('acsSegmentAnatomyWithTpm:DeprecatedSpmInputOrientation', ...
            ['spmInputOrientation is deprecated in this workflow and is not used for ', ...
             'the active RAS-normalized inputs. Use t1Orientation and tpmOrientation instead.']);
    end
end

function [orientationCode, info] = resolveInputOrientation(fileName, request, label, volumeIndex, opts)
    request = lower(strtrim(char(request)));
    askTokens = {'ask', 'gui', 'prompt', 'interactive'};

    info = struct();
    info.file = fileName;
    info.label = label;
    info.volumeIndex = volumeIndex;
    info.source = 'option';
    info.qcFile = '';

    if any(strcmp(request, askTokens))
        qcDir = fullfile(opts.outputDir, 'qc');
        labelSafe = safeName(label);
        orientOut = acsLabelVolumeOrientation(fileName, ...
            'volumeIndex', volumeIndex, ...
            'orientationCode', 'ask', ...
            'showFigures', true, ...
            'saveFigures', opts.saveFigures, ...
            'outputDir', qcDir, ...
            'outputName', [labelSafe '_orientation'], ...
            'allowSkip', false, ...
            'verbose', opts.verbose);
        orientationCode = validateOrientationCode(orientOut.orientationCode);
        info.source = 'userPrompt';
        if isfield(orientOut, 'qcFile')
            info.qcFile = orientOut.qcFile;
        end
    else
        orientationCode = validateOrientationCode(request);
    end
    info.orientationCode = orientationCode;
end

function workT1 = prepareRasSegmentationInput(sourceT1, outputDir, subjectLabel, orientationCode, opts)
    suffix = sprintf('_T1_RAS_from%s.nii', upper(orientationCode));
    workT1 = fullfile(outputDir, [subjectLabel suffix]);
    prepareRasNifti(sourceT1, workT1, orientationCode, 'T1', opts);
end

function workTpm = prepareRasTpmInput(sourceTpm, outputDir, orientationCode, opts)
    tpmStem = stripNiftiExtension(getFileName(sourceTpm));
    workTpm = fullfile(outputDir, [safeName(tpmStem) '_RAS_from' upper(orientationCode) '.nii']);
    prepareRasNifti(sourceTpm, workTpm, orientationCode, 'TPM', opts);
end

function prepareRasNifti(sourceFile, outFile, orientationCode, label, opts)
    orientationCode = validateOrientationCode(orientationCode);

    if strcmpi(canonicalPath(sourceFile), canonicalPath(outFile))
        return;
    end

    if exist(outFile, 'file') == 2 && ~opts.forceCopyInput
        logMsg(opts, '%s RAS working copy already exists; reusing %s', label, outFile);
        return;
    end

    logMsg(opts, 'Writing %s RAS working copy from %s orientation.', label, upper(orientationCode));
    writeRasOrientedNifti(sourceFile, outFile, orientationCode, label);
end

function writeRasOrientedNifti(sourceFile, outFile, orientationCode, label)
    V = spm_vol(sourceFile);
    V = V(:);
    if isempty(V)
        error('acsSegmentAnatomyWithTpm:EmptyNifti', ...
            'No readable volumes found in %s.', sourceFile);
    end

    [order, flips] = orientationTransformToRas(orientationCode);
    oldVoxelSize = voxelSizesFromMat(V(1).mat);
    newVoxelSize = oldVoxelSize(order);

    deleteDerivedNifti(outFile);
    ensureDir(fileparts(outFile));

    for i = 1:numel(V)
        data = spm_read_vols(V(i));
        data = orientVolumeToRas(data, order, flips);

        Vout = V(i);
        Vout.fname = outFile;
        Vout.dim = size(data);
        Vout.mat = canonicalSpmMat(Vout.dim, newVoxelSize);
        Vout.dt = [spm_type('float32') spm_platform('bigend')];
        Vout.n = [i 1];
        Vout.private = [];
        Vout.pinfo = [1; 0; 0];
        Vout.descrip = sprintf('ACS %s RAS working copy from %s', ...
            label, upper(orientationCode));
        spm_write_vol(Vout, single(data));
    end
end

function data = orientVolumeToRas(data, order, flips)
    data = permute(data, order);
    for dim = 1:3
        if flips(dim)
            data = flip(data, dim);
        end
    end
end

function [order, flips] = orientationTransformToRas(orientationCode)
    orientationCode = validateOrientationCode(orientationCode);
    targets = 'ras';
    opposites = 'lpi';
    order = zeros(1, 3);
    flips = false(1, 3);
    for dim = 1:3
        idx = find(orientationCode == targets(dim) | ...
            orientationCode == opposites(dim), 1);
        order(dim) = idx;
        flips(dim) = orientationCode(idx) == opposites(dim);
    end
end

function code = validateOrientationCode(code)
    code = lower(strtrim(char(code)));
    code = regexprep(code, '[\s,;:_-]+', '');
    if numel(code) ~= 3
        error('acsSegmentAnatomyWithTpm:BadOrientationCode', ...
            'Orientation code must have exactly three characters, one per voxel dimension.');
    end
    if any(~ismember(code, 'rlapsi'))
        error('acsSegmentAnatomyWithTpm:BadOrientationCode', ...
            'Orientation codes can only use r, l, a, p, s, and i.');
    end

    classes = cell(1, 3);
    for i = 1:3
        classes{i} = orientationClass(code(i));
    end
    expected = {'left-right', 'anterior-posterior', 'superior-inferior'};
    for i = 1:numel(expected)
        if sum(strcmp(classes, expected{i})) ~= 1
            error('acsSegmentAnatomyWithTpm:BadOrientationCode', ...
                'Use exactly one left/right, one anterior/posterior, and one superior/inferior direction.');
        end
    end
end

function cls = orientationClass(code)
    switch code
        case {'r', 'l'}
            cls = 'left-right';
        case {'a', 'p'}
            cls = 'anterior-posterior';
        case {'s', 'i'}
            cls = 'superior-inferior';
        otherwise
            error('acsSegmentAnatomyWithTpm:BadOrientationCode', ...
                'Unknown orientation code "%s".', code);
    end
end

function deleteDerivedNifti(fileName)
    if exist(fileName, 'file') == 2
        delete(fileName);
    end
    [folder, base] = fileparts(fileName);
    matFile = fullfile(folder, [base '.mat']);
    if exist(matFile, 'file') == 2
        delete(matFile);
    end
end

function vx = voxelSizesFromMat(M)
    vx = sqrt(sum(M(1:3, 1:3) .^ 2, 1));
    if any(~isfinite(vx)) || any(vx == 0)
        vx = [1 1 1];
    end
end

function M = canonicalSpmMat(dim, voxelSize)
    dim = double(dim(1:3));
    voxelSize = double(voxelSize(1:3));
    M = eye(4);
    M(1, 1) = voxelSize(1);
    M(2, 2) = voxelSize(2);
    M(3, 3) = voxelSize(3);
    M(1:3, 4) = -((dim(:) + 1) .* voxelSize(:)) / 2;
end

function tpmFile = resolveTpmFile(P, opts)
    if ~isempty(opts.tpmFile)
        tpmFile = opts.tpmFile;
        if exist(tpmFile, 'file') ~= 2
            error('acsSegmentAnatomyWithTpm:TpmNotFound', ...
                'Specified TPM file not found: %s', tpmFile);
        end
        return;
    end

    priorDir = opts.priorDir;
    if isempty(priorDir)
        priorDir = fullfile(P.dataRoot, 'MRIs', 'atlasfiles');
    end

    defaultCandidates = {
        fullfile(priorDir, opts.defaultTpmName)
        fullfile(P.templateOutputRoot, opts.templateMode, opts.defaultTpmName)
        fullfile(P.templateOutputRoot, opts.templateMode, 'tpm.nii')
        };

    tpmFile = firstExistingFile(defaultCandidates);
    if ~isempty(tpmFile)
        return;
    end

    legacyTpm = fullfile(priorDir, 'myTpm.nii');
    if exist(legacyTpm, 'file') == 2
        warning('acsSegmentAnatomyWithTpm:LegacyTpmName', ...
            ['Using legacy TPM name myTpm.nii. Rename to %s when convenient. ' ...
             'This file is assumed to be in ROAST/SPM order: gray, white, CSF, bone, skin, air.'], ...
            opts.defaultTpmName);
        tpmFile = legacyTpm;
        return;
    end

    if opts.makeTpmIfMissing
        logMsg(opts, 'No default TPM found; building one with templateMaker.');
        tpmOut = templateMaker( ...
            'mode', opts.templateMode, ...
            'priorDir', priorDir, ...
            'outputDir', fullfile(P.templateOutputRoot, opts.templateMode), ...
            'outputName', opts.defaultTpmName);
        tpmFile = tpmOut.outputFile;
        return;
    end

    error('acsSegmentAnatomyWithTpm:TpmNotFound', ...
        ['No TPM found. Expected %s under %s, or pass ''tpmFile'' explicitly. ' ...
         'Set makeTpmIfMissing=true to build one with templateMaker.'], ...
        opts.defaultTpmName, priorDir);
end

function tpmInfo = validateTpmFile(tpmFile)
    if exist(tpmFile, 'file') ~= 2
        error('acsSegmentAnatomyWithTpm:TpmNotFound', 'TPM file not found: %s', tpmFile);
    end

    info = niftiinfo(tpmFile);
    tpmInfo = struct();
    tpmInfo.file = tpmFile;
    tpmInfo.imageSize = info.ImageSize;
    tpmInfo.pixelDimensions = info.PixelDimensions;
    tpmInfo.datatype = info.Datatype;

    channelCount = 1;
    if numel(info.ImageSize) >= 4
        channelCount = info.ImageSize(4);
    end
    tpmInfo.channelCount = channelCount;
    tpmInfo.assumedChannelOrder = {'gray', 'white', 'csf', 'bone', 'skin', 'air'};

    if channelCount < 6
        error('acsSegmentAnatomyWithTpm:BadTpmChannels', ...
            'TPM must contain at least six channels. %s reports %d channel(s).', ...
            tpmFile, channelCount);
    end
end

function subjectMasks = maybeMakeSubjectMasks(workT1, subjectLabel, opts)
    subjectMasks = struct();
    subjectMasks.enabled = opts.makeSubjectMasks;
    subjectMasks.t1File = workT1;
    subjectMasks.outputDir = '';
    subjectMasks.files = struct();
    subjectMasks.qcFiles = {};

    if ~opts.makeSubjectMasks
        return;
    end

    maskDir = fullfile(opts.outputDir, 'subjectMasks');
    prefix = [safeName(subjectLabel) '_' stripNiftiExtension(getFileName(workT1))];
    maskOut = acsMakeSubjectMasks(workT1, ...
        'outputDir', maskDir, ...
        'outputPrefix', prefix, ...
        'force', opts.forceSubjectMasks || opts.forceCopyInput || opts.forceSegmentation, ...
        'showFigures', opts.showFigures, ...
        'saveFigures', opts.saveFigures, ...
        'verbose', opts.verbose, ...
        'configFile', opts.configFile, ...
        'headThreshold', opts.maskHeadThreshold, ...
        'headThresholdScale', opts.maskHeadThresholdScale, ...
        'minHeadThreshold', opts.maskMinHeadThreshold, ...
        'closeRadiusMm', opts.maskCloseRadiusMm, ...
        'minIslandVox', opts.maskMinIslandVox, ...
        'skinShellMm', opts.maskSkinShellMm, ...
        'innerErodeMm', opts.maskInnerErodeMm, ...
        'brainErodeMm', opts.maskBrainErodeMm);

    if isfield(maskOut, 'figure')
        maskOut = rmfield(maskOut, 'figure');
    end
    subjectMasks = maskOut;
    subjectMasks.enabled = true;
end

function maskFile = resolveSpmMaskFile(subjectMasks, workT1, opts)
    if ~isempty(opts.subjectMaskFile)
        maskFile = opts.subjectMaskFile;
        validateSpmMask(workT1, maskFile);
        return;
    end

    if strcmp(opts.spmMaskMode, 'none')
        maskFile = '';
        return;
    end

    if ~opts.makeSubjectMasks || ~isfield(subjectMasks, 'files')
        error('acsSegmentAnatomyWithTpm:MaskUnavailable', ...
            'spmMaskMode=%s requires makeSubjectMasks=true or an explicit subjectMaskFile.', ...
            opts.spmMaskMode);
    end

    switch opts.spmMaskMode
        case 'head'
            maskFile = subjectMasks.files.headMask;
        case 'innerHead'
            maskFile = subjectMasks.files.innerHeadMask;
        case 'brainSearch'
            maskFile = subjectMasks.files.brainSearchMask;
        otherwise
            error('acsSegmentAnatomyWithTpm:BadSpmMaskMode', ...
                'Unsupported spmMaskMode: %s', opts.spmMaskMode);
    end

    validateSpmMask(workT1, maskFile);
end

function [activeT1, activeExpected, correction] = maybeApplyBoneCorrection(workT1, spmExpected, subjectMasks, opts)
    activeT1 = workT1;
    activeExpected = spmExpected;

    correction = struct();
    correction.mode = opts.boneMode;
    correction.didApply = false;
    correction.t1File = workT1;
    correction.tissueFiles = spmExpected.tissueFiles(:);

    if strcmp(opts.boneMode, 'spm')
        return;
    end
    if ~segmentationOutputsExist(spmExpected)
        error('acsSegmentAnatomyWithTpm:MissingSpmOutputsForBoneCorrection', ...
            'Cannot apply bone correction because SPM tissue outputs are incomplete.');
    end

    constraintMask = resolveBoneShellConstraintMask(subjectMasks, opts);
    correction = acsApplyCraniumShellBonePrior(workT1, spmExpected.tissueFiles, ...
        'mode', opts.boneMode, ...
        'outputDir', opts.outputDir, ...
        'outputTag', opts.boneMode, ...
        'force', opts.forceBoneCorrection || opts.forceSegmentation, ...
        'shellDilateMm', opts.boneShellDilateMm, ...
        'shellSmoothMm', opts.boneShellSmoothMm, ...
        'brainThreshold', opts.boneShellBrainThreshold, ...
        'boneFloor', opts.boneShellFloor, ...
        'boneBoost', opts.boneShellBoost, ...
        'boneAdd', opts.boneShellAdd, ...
        'constraintMaskFile', constraintMask, ...
        'verbose', opts.verbose);

    if isfield(correction, 'didApply') && correction.didApply
        activeT1 = correction.t1File;
        activeExpected.tissueFiles = correction.tissueFiles(:)';
    end
end

function maskFile = resolveBoneShellConstraintMask(subjectMasks, opts)
    maskFile = '';
    if strcmp(opts.boneShellConstraintMask, 'none')
        return;
    end

    switch opts.boneShellConstraintMask
        case 'head'
            requireSubjectMaskProducts(subjectMasks, 'boneShellConstraintMask', opts.boneShellConstraintMask);
            maskFile = subjectMasks.files.headMask;
        case 'innerHead'
            requireSubjectMaskProducts(subjectMasks, 'boneShellConstraintMask', opts.boneShellConstraintMask);
            maskFile = subjectMasks.files.innerHeadMask;
        case 'brainSearch'
            requireSubjectMaskProducts(subjectMasks, 'boneShellConstraintMask', opts.boneShellConstraintMask);
            maskFile = subjectMasks.files.brainSearchMask;
        otherwise
            maskFile = opts.boneShellConstraintMask;
    end
    validateExistingMaskFile(maskFile, 'boneShellConstraintMask');
end

function labels = maybeMakeRoastLabels(activeT1, activeExpected, subjectMasks, opts)
    labels = struct();
    labels.enabled = opts.makeRoastLabels;
    labels.didRun = false;
    labels.labelFile = '';
    labels.qcFiles = {};
    if ~opts.makeRoastLabels
        return;
    end
    if ~segmentationOutputsExist(activeExpected)
        error('acsSegmentAnatomyWithTpm:MissingActiveTissuesForLabels', ...
            'Cannot make ROAST labels because active tissue outputs are incomplete.');
    end

    constraintMask = resolveRoastLabelConstraintMask(subjectMasks, opts);
    roastNames = roastExpectedFileNames(activeT1);
    labelOut = acsMakeRoastTissueLabels(activeT1, activeExpected.tissueFiles, ...
        'outputDir', opts.outputDir, ...
        'outputPrefix', stripNiftiExtension(getFileName(roastNames.maskFile)), ...
        'force', opts.forceRoastLabels || opts.forceBoneCorrection || opts.forceSegmentation, ...
        'minWinnerProbability', opts.roastLabelMinProbability, ...
        'constraintMaskFile', constraintMask, ...
        'showFigures', opts.showFigures, ...
        'saveFigures', opts.saveFigures, ...
        'overlayAlpha', opts.roastLabelOverlayAlpha, ...
        'verbose', opts.verbose);

    if isfield(labelOut, 'figure')
        labelOut = rmfield(labelOut, 'figure');
    end
    labels = labelOut;
    labels.enabled = true;
    labels.didRun = true;
end

function roastReady = maybeMakeRoastReadyFiles(activeT1, spmExpected, roastLabels, opts)
    roastReady = roastExpectedFileNames(activeT1);
    roastReady.enabled = opts.makeRoastLabels;
    roastReady.didWriteSeg8Alias = false;
    roastReady.didWriteRmaskAlias = false;
    roastReady.commandHint = sprintf( ...
        'roast(''%s'', recipe, ''resampling'', ''off'')', activeT1);

    if ~opts.makeRoastLabels
        return;
    end
    if ~isfield(roastLabels, 'labelFile') || isempty(roastLabels.labelFile)
        return;
    end
    if ~strcmpi(canonicalPath(roastLabels.labelFile), canonicalPath(roastReady.maskFile))
        error('acsSegmentAnatomyWithTpm:UnexpectedRoastMaskName', ...
            'ROAST label output should be %s but was %s.', ...
            roastReady.maskFile, roastLabels.labelFile);
    end

    writeRoastSeg8Alias(spmExpected.seg8File, roastReady.seg8File, ...
        activeT1, opts.forceRoastLabels || opts.forceSegmentation);
    roastReady.didWriteSeg8Alias = true;

    if exist(spmExpected.rmaskFile, 'file') == 2
        writeSmallAliasFile(spmExpected.rmaskFile, roastReady.rmaskFile, ...
            opts.forceRoastLabels || opts.forceSegmentation);
        roastReady.didWriteRmaskAlias = true;
    end
end

function files = roastExpectedFileNames(activeT1)
    [folder, activeStem] = fileparts(activeT1);
    files = struct();
    files.t1File = activeT1;
    files.spmStem = fullfile(folder, [activeStem '_T1orT2']);
    files.segStem = fullfile(folder, [activeStem '_T1orT2_SPM']);
    files.seg8File = [files.spmStem '_seg8.mat'];
    files.rmaskFile = [files.spmStem '_rmask.mat'];
    files.maskFile = [files.segStem '_masks.nii'];
end

function writeRoastSeg8Alias(sourceSeg8, targetSeg8, activeT1, forceWrite)
    if exist(sourceSeg8, 'file') ~= 2
        error('acsSegmentAnatomyWithTpm:MissingSeg8ForRoast', ...
            'Cannot create ROAST seg8 alias because source is missing: %s', sourceSeg8);
    end
    if exist(targetSeg8, 'file') == 2 && ~forceWrite
        return;
    end

    S = load(sourceSeg8);
    if isfield(S, 'image') && ~isempty(S.image)
        S.image(1).fname = activeT1;
        if isfield(S.image(1), 'private') && isfield(S.image(1).private, 'dat')
            try
                S.image(1).private.dat.fname = activeT1;
            catch
            end
        end
    end

    targetDir = fileparts(targetSeg8);
    ensureDir(targetDir);
    save(targetSeg8, '-struct', 'S');
end

function writeSmallAliasFile(sourceFile, targetFile, forceWrite)
    if exist(targetFile, 'file') == 2 && ~forceWrite
        return;
    end
    targetDir = fileparts(targetFile);
    ensureDir(targetDir);
    copyfile(sourceFile, targetFile, 'f');
end

function maskFile = resolveRoastLabelConstraintMask(subjectMasks, opts)
    maskFile = '';
    if strcmp(opts.roastLabelConstraintMask, 'none')
        return;
    end

    switch opts.roastLabelConstraintMask
        case 'head'
            requireSubjectMaskProducts(subjectMasks, 'roastLabelConstraintMask', opts.roastLabelConstraintMask);
            maskFile = subjectMasks.files.headMask;
        case 'innerHead'
            requireSubjectMaskProducts(subjectMasks, 'roastLabelConstraintMask', opts.roastLabelConstraintMask);
            maskFile = subjectMasks.files.innerHeadMask;
        case 'brainSearch'
            requireSubjectMaskProducts(subjectMasks, 'roastLabelConstraintMask', opts.roastLabelConstraintMask);
            maskFile = subjectMasks.files.brainSearchMask;
        otherwise
            maskFile = opts.roastLabelConstraintMask;
    end
    validateExistingMaskFile(maskFile, 'roastLabelConstraintMask');
end

function requireSubjectMaskProducts(subjectMasks, optionName, optionValue)
    if ~isfield(subjectMasks, 'files') || isempty(fieldnames(subjectMasks.files))
        error('acsSegmentAnatomyWithTpm:SubjectMaskProductsUnavailable', ...
            '%s=%s requires subject mask products.', optionName, optionValue);
    end
end

function validateExistingMaskFile(maskFile, optionName)
    if exist(maskFile, 'file') ~= 2
        error('acsSegmentAnatomyWithTpm:MaskFileNotFound', ...
            '%s resolved to a missing mask file: %s', optionName, maskFile);
    end
end

function validateSpmMask(workT1, maskFile)
    if exist(maskFile, 'file') ~= 2
        error('acsSegmentAnatomyWithTpm:MaskNotFound', ...
            'SPM mask file not found: %s', maskFile);
    end

    Vt1 = spm_vol(workT1);
    Vmask = spm_vol(maskFile);
    Vt1 = Vt1(1);
    Vmask = Vmask(1);

    if any(Vt1.dim(1:3) ~= Vmask.dim(1:3))
        error('acsSegmentAnatomyWithTpm:MaskDimensionMismatch', ...
            'SPM mask dimensions %s do not match T1 dimensions %s.', ...
            mat2str(Vmask.dim(1:3)), mat2str(Vt1.dim(1:3)));
    end

    if max(abs(Vt1.mat(:) - Vmask.mat(:))) > 1e-4
        error('acsSegmentAnatomyWithTpm:MaskAffineMismatch', ...
            'SPM mask affine does not match the segmentation T1 affine: %s', maskFile);
    end
end

function label = maskFileLabel(maskFile)
    if isempty(maskFile)
        label = '<none>';
    else
        label = maskFile;
    end
end

function expected = expectedSpmOutputs(workT1)
    [folder, base] = fileparts(workT1);
    expected = struct();
    expected.tissueFiles = cell(1, 6);
    for i = 1:6
        expected.tissueFiles{i} = fullfile(folder, sprintf('c%d%s.nii', i, base));
    end
    expected.seg8File = fullfile(folder, [base '_seg8.mat']);
    expected.rmaskFile = fullfile(folder, [base '_rmask.mat']);
end

function tf = segmentationOutputsExist(expected)
    tf = exist(expected.seg8File, 'file') == 2;
    for i = 1:numel(expected.tissueFiles)
        tf = tf && exist(expected.tissueFiles{i}, 'file') == 2;
    end
end

function runSpmSegmentation(workT1, tpmFile, opts)
    if opts.saveNormalized
        nativeWrite = [1 1];
        warpedWrite = [1 0];
    else
        nativeWrite = [1 0];
        warpedWrite = [0 0];
    end

    job = struct();
    job.channel.vols = {workT1};
    job.channel.biasreg = opts.biasReg;
    job.channel.biasfwhm = opts.biasFwhm;
    job.channel.write = [0 0];

    for tissue = 1:6
        job.tissue(tissue).tpm = {[tpmFile ',' num2str(tissue)]};
        job.tissue(tissue).ngaus = opts.ngaus(tissue);
        job.tissue(tissue).native = nativeWrite;
        job.tissue(tissue).warped = warpedWrite;
    end

    job.warp.reg = opts.warpReg;
    job.warp.affreg = opts.affineRegularization;
    job.warp.samp = opts.samplingDistance;
    job.warp.write = [0 0];
    job.warp.mrf = 0;
    job.warp.cleanup = 0;
    job.warp.fwhm = 0;

    if ~isempty(opts.spmMaskFile)
        job.msk = opts.spmMaskFile;
    end

    logMsg(opts, 'Running SPM segmentation...');
    spm_jobman('initcfg');
    spm_preproc_run(job);
end

function touchup = runSegTouchupIfNeeded(workT1, expected, opts)
    [folder, base] = fileparts(workT1);
    segOut = fullfile(folder, [base '_SPM.nii']);
    [~, segBase] = fileparts(segOut);
    maskFile = fullfile(folder, [segBase '_masks.nii']);

    touchup = struct('didRun', false, 'outputFile', segOut, 'maskFile', maskFile);
    if exist(maskFile, 'file') == 2 && ~opts.forceSegmentation
        logMsg(opts, 'Existing ROAST mask file found; skipping segTouchup.');
        return;
    end
    if ~segmentationOutputsExist(expected)
        error('acsSegmentAnatomyWithTpm:MissingSpmOutputs', ...
            'Cannot run segTouchup because SPM outputs are incomplete.');
    end

    logMsg(opts, 'Running ROAST segTouchup...');
    segTouchup(workT1, segOut);
    touchup.didRun = true;
end

function styles = selectedTissueStyles(requestedTissues, contourLevel)
    allStyles = struct( ...
        'name', {'gray', 'white', 'csf', 'bone', 'skin', 'air'}, ...
        'label', {'c1 gray', 'c2 white', 'c3 CSF', 'c4 bone', 'c5 skin', 'c6 air'}, ...
        'channel', {1, 2, 3, 4, 5, 6}, ...
        'color', {[1 0.2 0.1], [0 0.85 1], [0.1 0.25 1], [1 0.85 0], [0 0.8 0.25], [1 0 1]}, ...
        'lineWidth', {1.1, 1.1, 1.1, 1.0, 1.2, 0.8}, ...
        'level', {contourLevel, contourLevel, contourLevel, contourLevel, contourLevel, contourLevel});

    if any(strcmpi(requestedTissues, 'all'))
        styles = allStyles;
        return;
    end

    styles = repmat(allStyles(1), 0, 1);
    for i = 1:numel(requestedTissues)
        idx = find(strcmpi(requestedTissues{i}, {allStyles.name}), 1);
        if isempty(idx)
            error('acsSegmentAnatomyWithTpm:UnknownQcTissue', ...
                'Unknown QC tissue "%s". Use gray, white, csf, bone, skin, air, or all.', ...
                requestedTissues{i});
        end
        styles(end + 1) = allStyles(idx); %#ok<AGROW>
    end
end

function qcFiles = maybeMakeSegmentationQcFigures(workT1, sourceT1, expected, opts)
    qcFiles = {};
    if ~opts.showFigures && ~opts.saveFigures
        return;
    end
    if ~segmentationOutputsExist(expected)
        warning('acsSegmentAnatomyWithTpm:MissingQcInputs', ...
            'SPM outputs are incomplete; skipping segmentation QC figure.');
        return;
    end

    Vref = spm_vol(workT1);
    Vref = Vref(1);
    tissueVols = cell(1, 6);
    for i = 1:6
        Vt = spm_vol(expected.tissueFiles{i});
        tissueVols{i} = Vt(1);
    end

    figVisible = 'off';
    if opts.showFigures
        figVisible = 'on';
    end

    dims = Vref.dim(1:3);
    sliceInd = max(1, round(dims ./ 2));
    axisInfo = anatomicalAxisInfo(sourceT1, opts);
    planes = axisInfo.planes;
    clim = robustClim(spm_read_vols(Vref));
    tissueStyles = selectedTissueStyles(opts.qcTissues, opts.qcContourLevel);

    fig = makeSegmentationOverlayFigure(Vref, tissueVols, planes, sliceInd, ...
        clim, tissueStyles, axisInfo, opts, figVisible, 'SPM segmentation QC');

    if opts.saveFigures
        qcDir = fullfile(opts.outputDir, 'qc');
        ensureDir(qcDir);
        qcFile = fullfile(qcDir, [stripNiftiExtension(getFileName(workT1)) '_spmSegmentationQc.png']);
        saveQcFigure(fig, qcFile);
        qcFiles = {qcFile};
    end

    if ~opts.showFigures
        close(fig);
    end

    diagnosticStyles = selectedTissueStyles({'gray', 'white', 'csf', 'bone', 'skin'}, ...
        opts.qcContourLevel);
    diagFig = makeBrainShellDiagnosticFigure(Vref, tissueVols, planes, sliceInd, ...
        clim, diagnosticStyles, axisInfo, opts, figVisible);

    if opts.saveFigures
        qcDir = fullfile(opts.outputDir, 'qc');
        ensureDir(qcDir);
        diagFile = fullfile(qcDir, [stripNiftiExtension(getFileName(workT1)) '_spmBrainShellQc.png']);
        saveQcFigure(diagFig, diagFile);
        qcFiles{end + 1} = diagFile;
    end

    if ~opts.showFigures
        close(diagFig);
    end

    if opts.makeMaxTissueQc
        maxStyles = selectedTissueStyles({'all'}, opts.qcContourLevel);
        maxFig = makeMaxTissueQcFigure(Vref, tissueVols, planes, sliceInd, ...
            clim, maxStyles, axisInfo, opts, figVisible);

        if opts.saveFigures
            qcDir = fullfile(opts.outputDir, 'qc');
            ensureDir(qcDir);
            maxFile = fullfile(qcDir, [stripNiftiExtension(getFileName(workT1)) '_spmMaxTissueQc.png']);
            saveQcFigure(maxFig, maxFile);
            qcFiles{end + 1} = maxFile;
        end

        if ~opts.showFigures
            close(maxFig);
        end
    end
end

function fig = makeSegmentationOverlayFigure(Vref, tissueVols, planes, sliceInd, ...
        clim, tissueStyles, axisInfo, opts, figVisible, figName)
    fig = figure('Name', figName, 'Color', 'w', ...
        'Visible', figVisible, 'Units', 'pixels', 'Position', [80 80 1500 820]);

    addFigureHeader(fig, sprintf('%s | contour %.2f | axes: %s', ...
        getFileName(Vref.fname), opts.qcContourLevel, axisInfo.description));

    axPos = threePanelPositions(0.22, 0.67);
    for i = 1:numel(planes)
        ax = axes(fig, 'Position', axPos(i, :)); %#ok<LAXES>
        plotSegmentationPanel(ax, Vref, tissueVols, planes(i), ...
            sliceInd(planes(i).voxelDim), clim, tissueStyles);
    end

    legendAx = axes(fig, 'Position', [0.05 0.04 0.90 0.11]); %#ok<LAXES>
    drawLegendPanel(legendAx, tissueStyles);
end

function fig = makeBrainShellDiagnosticFigure(Vref, tissueVols, planes, sliceInd, ...
        clim, styles, axisInfo, opts, figVisible)
    fig = figure('Name', 'SPM brain/shell QC', 'Color', 'w', ...
        'Visible', figVisible, 'Units', 'pixels', 'Position', [80 80 1500 960]);

    addFigureHeader(fig, sprintf('%s | brain vs shell contours | contour %.2f | axes: %s', ...
        getFileName(Vref.fname), opts.qcContourLevel, axisInfo.description));

    brainStyles = styles(ismember({styles.name}, {'gray', 'white', 'csf'}));
    shellStyles = styles(ismember({styles.name}, {'bone', 'skin'}));

    topPos = threePanelPositions(0.55, 0.35);
    bottomPos = threePanelPositions(0.18, 0.35);
    for i = 1:numel(planes)
        ax = axes(fig, 'Position', topPos(i, :)); %#ok<LAXES>
        plotSegmentationPanel(ax, Vref, tissueVols, planes(i), ...
            sliceInd(planes(i).voxelDim), clim, brainStyles);
        ylabel(ax, 'brain', 'FontWeight', 'bold');

        ax = axes(fig, 'Position', bottomPos(i, :)); %#ok<LAXES>
        plotSegmentationPanel(ax, Vref, tissueVols, planes(i), ...
            sliceInd(planes(i).voxelDim), clim, shellStyles);
        ylabel(ax, 'shell', 'FontWeight', 'bold');
    end

    legendAx = axes(fig, 'Position', [0.05 0.035 0.90 0.09]); %#ok<LAXES>
    drawLegendPanel(legendAx, styles);
end

function fig = makeMaxTissueQcFigure(Vref, tissueVols, planes, sliceInd, ...
        clim, styles, axisInfo, opts, figVisible)
    fig = figure('Name', 'SPM maximum tissue QC', 'Color', 'w', ...
        'Visible', figVisible, 'Units', 'pixels', 'Position', [80 80 1500 820]);

    addFigureHeader(fig, sprintf('%s | maximum-probability tissue | min p %.2f | axes: %s', ...
        getFileName(Vref.fname), opts.qcMaxTissueMinProbability, axisInfo.description));

    axPos = threePanelPositions(0.22, 0.67);
    for i = 1:numel(planes)
        ax = axes(fig, 'Position', axPos(i, :)); %#ok<LAXES>
        plotMaxTissuePanel(ax, Vref, tissueVols, planes(i), ...
            sliceInd(planes(i).voxelDim), clim, styles, opts);
    end

    legendAx = axes(fig, 'Position', [0.05 0.04 0.90 0.11]); %#ok<LAXES>
    drawMaxTissueLegendPanel(legendAx, styles, opts);
end

function addFigureHeader(fig, headerText)
    annotation(fig, 'textbox', [0.04 0.935 0.92 0.05], ...
        'String', headerText, ...
        'Interpreter', 'none', ...
        'HorizontalAlignment', 'center', ...
        'VerticalAlignment', 'middle', ...
        'FontWeight', 'bold', ...
        'FontSize', 12, ...
        'EdgeColor', 'none');
end

function positions = threePanelPositions(y0, h)
    margin = 0.045;
    gap = 0.035;
    w = (1 - 2 * margin - 2 * gap) / 3;
    positions = zeros(3, 4);
    for i = 1:3
        x0 = margin + (i - 1) * (w + gap);
        positions(i, :) = [x0 y0 w h];
    end
end

function plotSegmentationPanel(ax, Vref, tissueVols, plane, idx, clim, tissueStyles)
    dimToFix = plane.voxelDim;
    t1Slice = sampleSliceInReference(Vref, Vref, dimToFix, idx, 0);
    imagesc(ax, rot90(t1Slice));
    axis(ax, 'image');
    axis(ax, 'off');
    colormap(ax, gray);
    caxis(ax, clim);
    hold(ax, 'on');

    for j = 1:numel(tissueStyles)
        style = tissueStyles(j);
        tissueSlice = sampleSliceInReference(tissueVols{style.channel}, ...
            Vref, dimToFix, idx, 1);
        contourIfPresent(ax, tissueSlice, style.level, style.color, style.lineWidth);
    end

    title(ax, sprintf('%s  dim %d = %d', plane.label, dimToFix, idx), ...
        'Interpreter', 'none', 'FontSize', 11, 'FontWeight', 'bold');
    text(ax, 0.02, 0.03, plane.normal, ...
        'Units', 'normalized', ...
        'Color', [1 1 1], ...
        'BackgroundColor', [0 0 0], ...
        'Margin', 2, ...
        'Interpreter', 'none', ...
        'FontSize', 9);
end

function plotMaxTissuePanel(ax, Vref, tissueVols, plane, idx, clim, styles, opts)
    dimToFix = plane.voxelDim;
    t1Slice = sampleSliceInReference(Vref, Vref, dimToFix, idx, 0);
    imagesc(ax, rot90(t1Slice));
    axis(ax, 'image');
    axis(ax, 'off');
    colormap(ax, gray);
    caxis(ax, clim);
    hold(ax, 'on');

    [labelSlice, maxProbSlice] = maxTissueSlice(tissueVols, Vref, dimToFix, idx);
    rgb = labelSliceRgb(labelSlice, styles);
    overlay = image(ax, rot90Rgb(rgb));
    showMask = labelSlice ~= 6 & maxProbSlice >= opts.qcMaxTissueMinProbability;
    set(overlay, 'AlphaData', rot90(double(showMask) .* opts.qcMaxTissueAlpha));

    title(ax, sprintf('%s  dim %d = %d', plane.label, dimToFix, idx), ...
        'Interpreter', 'none', 'FontSize', 11, 'FontWeight', 'bold');
    text(ax, 0.02, 0.03, plane.normal, ...
        'Units', 'normalized', ...
        'Color', [1 1 1], ...
        'BackgroundColor', [0 0 0], ...
        'Margin', 2, ...
        'Interpreter', 'none', ...
        'FontSize', 9);
end

function [labelSlice, maxProbSlice] = maxTissueSlice(tissueVols, Vref, dimToFix, idx)
    firstSlice = sampleSliceInReference(tissueVols{1}, Vref, dimToFix, idx, 1);
    probStack = zeros([size(firstSlice) numel(tissueVols)], 'single');
    probStack(:, :, 1) = single(firstSlice);
    for k = 2:numel(tissueVols)
        probStack(:, :, k) = single(sampleSliceInReference( ...
            tissueVols{k}, Vref, dimToFix, idx, 1));
    end
    [maxProbSlice, labelSlice] = max(probStack, [], 3);
end

function rgb = labelSliceRgb(labelSlice, styles)
    rgb = zeros([size(labelSlice) 3], 'single');
    for k = 1:numel(styles)
        style = styles(k);
        mask = labelSlice == style.channel;
        for c = 1:3
            channel = rgb(:, :, c);
            channel(mask) = style.color(c);
            rgb(:, :, c) = channel;
        end
    end
end

function out = rot90Rgb(in)
    out = zeros([size(in, 2) size(in, 1) size(in, 3)], 'like', in);
    for c = 1:size(in, 3)
        out(:, :, c) = rot90(in(:, :, c));
    end
end

function drawLegendPanel(ax, tissueStyles)
    cla(ax);
    axis(ax, 'off');
    hold(ax, 'on');
    x = 0.02;
    y = 0.60;
    for i = 1:numel(tissueStyles)
        style = tissueStyles(i);
        plot(ax, [x x + 0.055], [y y], ...
            'Color', style.color, 'LineWidth', max(style.lineWidth, 2));
        text(ax, x + 0.065, y, style.label, ...
            'Interpreter', 'none', ...
            'VerticalAlignment', 'middle', ...
            'FontSize', 11);
        x = x + 0.16;
    end
    text(ax, 0.02, 0.18, ...
        'Contours are SPM tissue probabilities sampled in the displayed T1 grid.', ...
        'Interpreter', 'none', 'FontSize', 9, 'Color', [0.25 0.25 0.25]);
    xlim(ax, [0 1]);
    ylim(ax, [0 1]);
end

function drawMaxTissueLegendPanel(ax, tissueStyles, opts)
    cla(ax);
    axis(ax, 'off');
    hold(ax, 'on');
    x = 0.02;
    y = 0.62;
    for i = 1:numel(tissueStyles)
        style = tissueStyles(i);
        if strcmp(style.name, 'air')
            continue;
        end
        patch(ax, [x x + 0.035 x + 0.035 x], [y - 0.08 y - 0.08 y + 0.08 y + 0.08], ...
            style.color, 'EdgeColor', [0.2 0.2 0.2], 'LineWidth', 0.5);
        text(ax, x + 0.045, y, style.label, ...
            'Interpreter', 'none', ...
            'VerticalAlignment', 'middle', ...
            'FontSize', 11);
        x = x + 0.16;
    end
    text(ax, 0.02, 0.18, ...
        sprintf('Overlay shows argmax(c1..c6) with air hidden; labels below p=%.2f are transparent.', ...
            opts.qcMaxTissueMinProbability), ...
        'Interpreter', 'none', 'FontSize', 9, 'Color', [0.25 0.25 0.25]);
    xlim(ax, [0 1]);
    ylim(ax, [0 1]);
end

function saveQcFigure(fig, qcFile)
    try
        exportgraphics(fig, qcFile, 'Resolution', 150);
    catch
        saveas(fig, qcFile);
    end
end

function axisInfo = anatomicalAxisInfo(sourceT1, opts)
    if isfield(opts, 'preparedInputOrientation') && strcmpi(opts.preparedInputOrientation, 'ras')
        axisInfo = preparedRasInputAxisInfo(opts);
        return;
    end

    if isfield(opts, 'spmInputOrientation') && ~strcmp(opts.spmInputOrientation, 'native')
        axisInfo = preparedSpmInputAxisInfo(opts);
        return;
    end

    importInfo = importOrientationInfo(sourceT1);
    worldAxisVoxelDim = importInfo.worldAxisVoxelDim;
    labels = {'Sagittal', 'Coronal', 'Axial'};
    normals = {'left-right', 'anterior-posterior', 'inferior-superior'};
    axisMode = opts.anatomicalAxes;

    if isstruct(axisMode)
        [voxelDims, normals, description] = planesFromAnatomicalStruct(axisMode, ...
            worldAxisVoxelDim);
    else
        switch lower(char(axisMode))
            case {'scanner', 'dicom', 'human', 'humansupine'}
                voxelDims = worldAxisVoxelDim;
                description = char(axisMode);
            case {'macaquesphinx', 'sphinx'}
                % Assumes the DICOM patient axes are standard-ish LPS and
                % the monkey was placed in sphinx position: left=X,
                % dorsal=Y, rostral=Z. Coronal is normal to rostral-caudal;
                % axial/horizontal is normal to dorsal-ventral.
                voxelDims = [worldAxisVoxelDim(1), ...
                    worldAxisVoxelDim(3), ...
                    worldAxisVoxelDim(2)];
                normals = {'left-right', 'rostral-caudal', 'dorsal-ventral'};
                description = 'macaqueSphinx';
            otherwise
                error('acsSegmentAnatomyWithTpm:UnknownAnatomicalAxes', ...
                    'Unknown anatomicalAxes preset: %s', char(axisMode));
        end
    end

    if ~isempty(opts.planeVoxelDims)
        voxelDims = opts.planeVoxelDims;
        description = [description ' + manual planeVoxelDims'];
    end
    voxelDims = validatePlaneVoxelDims(voxelDims);

    planes = repmat(struct('label', '', 'voxelDim', 1, 'normal', ''), 1, 3);
    for i = 1:3
        planes(i).label = labels{i};
        planes(i).voxelDim = voxelDims(i);
        planes(i).normal = normals{i};
    end

    axisInfo = struct();
    axisInfo.description = description;
    axisInfo.worldAxisVoxelDim = worldAxisVoxelDim;
    axisInfo.planeVoxelDims = voxelDims;
    axisInfo.planes = planes;
end

function axisInfo = preparedRasInputAxisInfo(opts)
    labels = {'Sagittal', 'Coronal', 'Axial'};
    normals = {'left-right', 'anterior-posterior', 'inferior-superior'};
    voxelDims = [1 2 3];
    description = 'RAS working input';

    if ~isempty(opts.planeVoxelDims)
        voxelDims = opts.planeVoxelDims;
        description = [description ' + manual planeVoxelDims'];
    end
    voxelDims = validatePlaneVoxelDims(voxelDims);

    planes = repmat(struct('label', '', 'voxelDim', 1, 'normal', ''), 1, 3);
    for i = 1:3
        planes(i).label = labels{i};
        planes(i).voxelDim = voxelDims(i);
        planes(i).normal = normals{i};
    end

    axisInfo = struct();
    axisInfo.description = description;
    axisInfo.worldAxisVoxelDim = [1 2 3];
    axisInfo.planeVoxelDims = voxelDims;
    axisInfo.planes = planes;
end

function axisInfo = preparedSpmInputAxisInfo(opts)
    labels = {'SPM dim 1', 'SPM dim 2', 'SPM dim 3'};
    normals = {'prepared voxel dim 1', 'prepared voxel dim 2', 'prepared voxel dim 3'};
    voxelDims = [1 2 3];
    description = [opts.spmInputOrientation ' SPM input'];

    if ~isempty(opts.planeVoxelDims)
        voxelDims = opts.planeVoxelDims;
        description = [description ' + manual planeVoxelDims'];
    end
    voxelDims = validatePlaneVoxelDims(voxelDims);

    planes = repmat(struct('label', '', 'voxelDim', 1, 'normal', ''), 1, 3);
    for i = 1:3
        planes(i).label = labels{i};
        planes(i).voxelDim = voxelDims(i);
        planes(i).normal = normals{i};
    end

    axisInfo = struct();
    axisInfo.description = description;
    axisInfo.worldAxisVoxelDim = [1 2 3];
    axisInfo.planeVoxelDims = voxelDims;
    axisInfo.planes = planes;
end

function importInfo = importOrientationInfo(sourceT1)
    importInfo = struct();
    importInfo.worldAxisVoxelDim = [1 2 3];
    reportJson = fullfile(fileparts(sourceT1), ...
        [stripNiftiExtension(getFileName(sourceT1)) '_importReport.json']);
    if exist(reportJson, 'file') ~= 2
        return;
    end

    try
        report = jsondecode(fileread(reportJson));
        if isfield(report, 'nifti') && isfield(report.nifti, 'orientation') && ...
                isfield(report.nifti.orientation, 'worldAxisVoxelDim')
            importInfo.worldAxisVoxelDim = validatePlaneVoxelDims( ...
                double(report.nifti.orientation.worldAxisVoxelDim(:))');
        end
    catch
        importInfo.worldAxisVoxelDim = [1 2 3];
    end
end

function [voxelDims, normals, description] = planesFromAnatomicalStruct(S, worldAxisVoxelDim)
    description = 'custom';
    normals = {'left-right', 'rostral-caudal', 'dorsal-ventral'};

    if isfield(S, 'name') && ~isempty(S.name)
        description = char(S.name);
    end

    if isfield(S, 'planeVoxelDims') && ~isempty(S.planeVoxelDims)
        voxelDims = double(S.planeVoxelDims(:))';
        return;
    end

    required = {'left', 'rostral', 'dorsal'};
    voxelDims = zeros(1, 3);
    for i = 1:numel(required)
        if ~isfield(S, required{i})
            error('acsSegmentAnatomyWithTpm:BadAnatomicalAxesStruct', ...
                'Custom anatomicalAxes must include left, rostral, and dorsal fields.');
        end
        worldAxis = parseWorldAxis(S.(required{i}));
        voxelDims(i) = worldAxisVoxelDim(worldAxis);
    end
end

function worldAxis = parseWorldAxis(axisSpec)
    if isnumeric(axisSpec)
        worldAxis = abs(axisSpec(1));
    else
        s = upper(char(axisSpec));
        s = strrep(s, '+', '');
        s = strrep(s, '-', '');
        switch s
            case {'X', '1', 'WORLDX'}
                worldAxis = 1;
            case {'Y', '2', 'WORLDY'}
                worldAxis = 2;
            case {'Z', '3', 'WORLDZ'}
                worldAxis = 3;
            otherwise
                error('acsSegmentAnatomyWithTpm:BadAxisSpec', ...
                    'Axis spec must be X, Y, Z, 1, 2, or 3.');
        end
    end

    if worldAxis < 1 || worldAxis > 3
        error('acsSegmentAnatomyWithTpm:BadAxisSpec', ...
            'World axis index must be 1, 2, or 3.');
    end
end

function voxelDims = validatePlaneVoxelDims(voxelDims)
    voxelDims = double(voxelDims(:))';
    if numel(voxelDims) ~= 3 || any(voxelDims < 1) || any(voxelDims > 3)
        voxelDims = [1 2 3];
        return;
    end
    voxelDims = round(voxelDims);
end

function S = sampleSliceInReference(Vmoving, Vref, dimToFix, idx, holdOrder)
    dims = Vref.dim(1:3);
    switch dimToFix
        case 1
            [A, B] = ndgrid(1:dims(2), 1:dims(3));
            I = idx .* ones(size(A));
            J = A;
            K = B;
        case 2
            [A, B] = ndgrid(1:dims(1), 1:dims(3));
            I = A;
            J = idx .* ones(size(A));
            K = B;
        case 3
            [A, B] = ndgrid(1:dims(1), 1:dims(2));
            I = A;
            J = B;
            K = idx .* ones(size(A));
        otherwise
            error('acsSegmentAnatomyWithTpm:BadSliceDimension', ...
                'Unsupported slice dimension %d.', dimToFix);
    end

    refVox = [I(:)'; J(:)'; K(:)'; ones(1, numel(I))];
    movingVox = Vmoving.mat \ (Vref.mat * refVox);
    S = spm_sample_vol(Vmoving, ...
        reshape(movingVox(1, :), size(I)), ...
        reshape(movingVox(2, :), size(I)), ...
        reshape(movingVox(3, :), size(I)), ...
        holdOrder);
end

function contourIfPresent(ax, S, level, color, lineWidth)
    if any(S(:) >= level)
        contour(ax, rot90(S), [level level], 'Color', color, 'LineWidth', lineWidth);
    end
end

function clim = robustClim(V)
    vals = V(isfinite(V));
    if isempty(vals)
        clim = [0 1];
        return;
    end
    n = numel(vals);
    if n > 1000000
        vals = vals(round(linspace(1, n, 1000000)));
    end
    clim = prctile(vals(:), [1 99]);
    if clim(1) == clim(2)
        clim = [min(vals(:)) max(vals(:))];
    end
    if clim(1) == clim(2)
        clim = clim + [-1 1];
    end
end

function out = buildReport(originalSubjectId, subjectId, sourceT1, workT1, ...
        activeT1, sourceTpm, workTpm, tpmInfo, spmExpected, activeExpected, ...
        opts, didRunSpm, touchup, qcFiles)
    out = struct();
    out.originalSubjectId = originalSubjectId;
    out.subjectId = subjectId;
    out.createdOn = char(datetime('now'));
    out.sourceT1 = sourceT1;
    out.segmentationT1 = workT1;
    out.activeSegmentationT1 = activeT1;
    out.sourceTpmFile = sourceTpm;
    out.tpmFile = workTpm;
    out.segmentationTpmFile = workTpm;
    out.tpm = tpmInfo;
    out.outputDir = opts.outputDir;
    out.segmentationTag = opts.segmentationTag;
    out.inputOrientations = struct( ...
        't1', opts.t1Orientation, ...
        'tpm', opts.tpmOrientation, ...
        'prepared', opts.preparedInputOrientation, ...
        't1Info', opts.t1OrientationInfo, ...
        'tpmInfo', opts.tpmOrientationInfo);
    out.spmInputOrientation = opts.spmInputOrientation;
    out.affineRegularization = opts.affineRegularization;
    out.affineRegularizationLabel = affineRegularizationLabel(opts.affineRegularization);
    out.anatomicalAxes = opts.anatomicalAxes;
    out.planeVoxelDims = opts.planeVoxelDims;
    out.axisInfo = anatomicalAxisInfo(sourceT1, opts);
    out.subjectMasks = opts.subjectMasks;
    out.spmMaskMode = opts.spmMaskMode;
    out.spmMaskFile = opts.spmMaskFile;
    out.boneCorrection = opts.boneCorrection;
    out.roastLabels = opts.roastLabels;
    out.roastReady = opts.roastReady;
    out.saveNormalized = opts.saveNormalized;
    out.didRunSpm = didRunSpm;
    out.spmTissueFiles = spmExpected.tissueFiles(:);
    out.tissueFiles = activeExpected.tissueFiles(:);
    out.seg8File = spmExpected.seg8File;
    out.rmaskFile = spmExpected.rmaskFile;
    out.spmOutputsComplete = segmentationOutputsExist(spmExpected);
    out.touchup = touchup;
    out.qcFiles = qcFiles(:);
    out.options = struct( ...
        'ngaus', opts.ngaus, ...
        'warpReg', opts.warpReg, ...
        'samplingDistance', opts.samplingDistance, ...
        'biasReg', opts.biasReg, ...
        'biasFwhm', opts.biasFwhm, ...
        'makeSubjectMasks', opts.makeSubjectMasks, ...
        'forceSubjectMasks', opts.forceSubjectMasks, ...
        'spmMaskMode', opts.spmMaskMode, ...
        'subjectMaskFile', opts.subjectMaskFile, ...
        'maskHeadThreshold', opts.maskHeadThreshold, ...
        'maskHeadThresholdScale', opts.maskHeadThresholdScale, ...
        'maskMinHeadThreshold', opts.maskMinHeadThreshold, ...
        'maskCloseRadiusMm', opts.maskCloseRadiusMm, ...
        'maskMinIslandVox', opts.maskMinIslandVox, ...
        'maskSkinShellMm', opts.maskSkinShellMm, ...
        'maskInnerErodeMm', opts.maskInnerErodeMm, ...
        'maskBrainErodeMm', opts.maskBrainErodeMm, ...
        'qcTissues', {opts.qcTissues}, ...
        'qcContourLevel', opts.qcContourLevel, ...
        'makeMaxTissueQc', opts.makeMaxTissueQc, ...
        'qcMaxTissueAlpha', opts.qcMaxTissueAlpha, ...
        'qcMaxTissueMinProbability', opts.qcMaxTissueMinProbability, ...
        'boneMode', opts.boneMode, ...
        'forceBoneCorrection', opts.forceBoneCorrection, ...
        'boneShellConstraintMask', opts.boneShellConstraintMask, ...
        'boneShellDilateMm', opts.boneShellDilateMm, ...
        'boneShellSmoothMm', opts.boneShellSmoothMm, ...
        'boneShellBrainThreshold', opts.boneShellBrainThreshold, ...
        'boneShellFloor', opts.boneShellFloor, ...
        'boneShellBoost', opts.boneShellBoost, ...
        'boneShellAdd', opts.boneShellAdd, ...
        'makeRoastLabels', opts.makeRoastLabels, ...
        'forceRoastLabels', opts.forceRoastLabels, ...
        'roastLabelConstraintMask', opts.roastLabelConstraintMask, ...
        'roastLabelMinProbability', opts.roastLabelMinProbability, ...
        'roastLabelOverlayAlpha', opts.roastLabelOverlayAlpha);
end

function addRoastDependencies(P)
    libDir = fullfile(P.repoRoot, 'lib');
    spmDir = fullfile(libDir, 'spm12');
    if exist(spmDir, 'dir') ~= 7
        error('acsSegmentAnatomyWithTpm:MissingSpm', 'SPM folder not found: %s', spmDir);
    end
    addpath(P.repoRoot);
    if exist('setNHPulsePath', 'file') == 2
        setNHPulsePath('repoRoot', P.repoRoot, 'verbose', false);
    else
        addpath(spmDir, '-begin');
        addOptionalDependencyFolder(libDir, 'spm');
        addOptionalDependencyFolder(libDir, 'iso2mesh');
        addOptionalDependencyFolder(libDir, 'cvx');
        addOptionalDependencyFolder(libDir, 'NIFTI_20110921');
    end
end

function addOptionalDependencyFolder(libDir, folderName)
    folder = fullfile(libDir, folderName);
    if exist(folder, 'dir') == 7
        addpath(folder, '-begin');
    end
end

function ensureDir(pathIn)
    if exist(pathIn, 'dir') ~= 7
        mkdir(pathIn);
    end
end

function pathOut = firstExistingFile(candidates)
    pathOut = '';
    for i = 1:numel(candidates)
        candidate = expandUserPath(candidates{i});
        if exist(candidate, 'file') == 2
            pathOut = candidate;
            return;
        end
    end
end

function writeJsonReport(reportJson, report)
    fid = fopen(reportJson, 'w');
    if fid == -1
        error('acsSegmentAnatomyWithTpm:CannotWriteJson', ...
            'Could not write report JSON: %s', reportJson);
    end
    cleaner = onCleanup(@() fclose(fid));
    fprintf(fid, '%s', jsonencode(report, 'PrettyPrint', true));
    clear cleaner;
end

function base = stripNiftiExtension(fileName)
    [~, base, ext] = fileparts(fileName);
    if strcmpi(ext, '.gz')
        [~, base] = fileparts(base);
    end
end

function name = getFileName(filePath)
    [~, name, ext] = fileparts(filePath);
    name = [name ext];
end

function name = safeName(value)
    name = upper(regexprep(char(value), '[^a-zA-Z0-9_]', '_'));
end

function p = expandUserPath(p)
    if isempty(p)
        return;
    end
    p = char(p);
    if startsWith(p, '~')
        homeDir = getenv('HOME');
        if isempty(homeDir)
            homeDir = getenv('USERPROFILE');
        end
        if numel(p) == 1
            p = homeDir;
        elseif p(2) == filesep || p(2) == '/' || p(2) == '\'
            p = fullfile(homeDir, p(3:end));
        end
    end
end

function p = canonicalPath(p)
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
