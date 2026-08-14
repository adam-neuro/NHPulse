function out = acsApplyCraniumShellBonePrior(t1File, tissueFiles, varargin)
% ACSAPPLYCRANIUMSHELLBONEPRIOR Reweight SPM bone probabilities with a shell prior.
%
% out = acsApplyCraniumShellBonePrior(t1File, tissueFiles) reads SPM tissue
% probability maps c1..c6, builds a subject-specific cranial shell from the
% merged brain classes c1+c2+c3, and writes a corrected set of probability
% maps. The original SPM files are not modified.
%
% Name-value options:
%   mode                  : spm, shellPrior, or shellOnly ['shellPrior']
%   outputDir             : destination folder [same as t1File]
%   outputTag             : suffix for corrected T1/tissue stem ['boneShellPrior']
%   force                 : overwrite existing outputs [false]
%   shellDilateMm         : brain dilation radius in mm [5]
%   shellSmoothMm         : fuzzy shell smoothing radius in mm [1.5]
%   brainThreshold        : threshold for c1+c2+c3 brain mask [0.45]
%   boneFloor             : c4 multiplier outside shell [0.05]
%   boneBoost             : c4 multiplier added inside shell [8]
%   boneAdd               : additive c4 shell prior before renormalization [0.20]
%   constraintMaskFile    : optional mask limiting the shell ['']
%   verbose               : print progress [false]

    if nargin < 2
        error('acsApplyCraniumShellBonePrior:NotEnoughInputs', ...
            'Provide a T1 file and a 1x6 cell array of tissue files.');
    end

    opts = parseInputs(varargin{:});
    opts.mode = normalizeBoneMode(opts.mode);
    tissueFiles = normalizeTissueFiles(tissueFiles);

    Vt1 = spm_vol(t1File);
    Vt1 = Vt1(1);
    if isempty(opts.outputDir)
        opts.outputDir = fileparts(t1File);
    end
    ensureDir(opts.outputDir);

    [~, t1Stem] = fileparts(t1File);
    outputStem = safeName([t1Stem '_' opts.outputTag]);
    files = outputFiles(opts.outputDir, outputStem);

    out = baseReport(t1File, tissueFiles, files, opts);
    if strcmp(opts.mode, 'spm')
        out.didApply = false;
        out.reason = 'mode=spm';
        out.t1File = t1File;
        out.tissueFiles = tissueFiles(:);
        return;
    end

    if outputsExist(files) && ~opts.force
        logMsg(opts, 'Cranium shell bone prior products already exist; reusing %s', opts.outputDir);
        out.didApply = true;
        out.reusedExisting = true;
        out.t1File = files.t1File;
        out.tissueFiles = files.tissueFiles(:);
        out.brainMaskFile = files.brainMask;
        out.shellPriorFile = files.shellPrior;
        return;
    end

    logMsg(opts, 'Reading tissue probabilities for cranium shell bone prior.');
    Vt = cell(1, 6);
    P = cell(1, 6);
    for k = 1:6
        Vt{k} = spm_vol(tissueFiles{k});
        Vt{k} = Vt{k}(1);
        validateSameGrid(Vt1, Vt{k}, tissueFiles{k});
        P{k} = single(spm_read_vols(Vt{k}));
        P{k}(~isfinite(P{k}) | P{k} < 0) = 0;
    end

    constraintMask = readConstraintMask(opts.constraintMaskFile, Vt1);
    [brainMask, shellPrior] = buildCraniumShell(P, Vt1, constraintMask, opts);
    Pout = applyBoneReweighting(P, shellPrior, opts);

    writeReferenceCopy(files.t1File, Vt1, t1File, ...
        sprintf('ACS T1 copy for %s bone correction', opts.mode));
    for k = 1:6
        writeScalarVolume(files.tissueFiles{k}, Vt{k}, Pout{k}, ...
            sprintf('ACS %s c%d with cranium shell bone prior', opts.mode, k));
    end
    writeMaskVolume(files.brainMask, Vt1, brainMask, 'ACS brain mask for cranium shell prior');
    writeScalarVolume(files.shellPrior, Vt1, shellPrior, 'ACS fuzzy cranium shell bone prior');

    out.didApply = true;
    out.t1File = files.t1File;
    out.tissueFiles = files.tissueFiles(:);
    out.brainMaskFile = files.brainMask;
    out.shellPriorFile = files.shellPrior;
    out.voxelCounts = struct( ...
        'brainMask', nnz(brainMask), ...
        'shellPriorPositive', nnz(shellPrior > 0.01));
    out.shellPriorStats = scalarStats(shellPrior);
    out.reusedExisting = false;

    save(files.reportMat, 'out');
    writeJsonReport(files.reportJson, out);
end

function opts = parseInputs(varargin)
    p = inputParser;
    p.FunctionName = 'acsApplyCraniumShellBonePrior';
    addParameter(p, 'mode', 'shellPrior', @(x) ischar(x) || isstring(x));
    addParameter(p, 'outputDir', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'outputTag', 'boneShellPrior', @(x) ischar(x) || isstring(x));
    addParameter(p, 'force', false, @isBoolLike);
    addParameter(p, 'shellDilateMm', 5, @(x) isnumeric(x) && isscalar(x) && x >= 0);
    addParameter(p, 'shellSmoothMm', 1.5, @(x) isnumeric(x) && isscalar(x) && x >= 0);
    addParameter(p, 'brainThreshold', 0.45, @(x) isnumeric(x) && isscalar(x) && x > 0 && x < 1);
    addParameter(p, 'boneFloor', 0.05, @(x) isnumeric(x) && isscalar(x) && x >= 0);
    addParameter(p, 'boneBoost', 8, @(x) isnumeric(x) && isscalar(x) && x >= 0);
    addParameter(p, 'boneAdd', 0.20, @(x) isnumeric(x) && isscalar(x) && x >= 0);
    addParameter(p, 'constraintMaskFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'verbose', false, @isBoolLike);
    parse(p, varargin{:});

    opts = p.Results;
    opts.outputDir = expandUserPath(char(opts.outputDir));
    opts.outputTag = safeName(char(opts.outputTag));
    opts.constraintMaskFile = expandUserPath(char(opts.constraintMaskFile));
    opts.force = logical(opts.force);
    opts.verbose = logical(opts.verbose);
    opts.shellDilateMm = double(opts.shellDilateMm);
    opts.shellSmoothMm = double(opts.shellSmoothMm);
    opts.brainThreshold = double(opts.brainThreshold);
    opts.boneFloor = double(opts.boneFloor);
    opts.boneBoost = double(opts.boneBoost);
    opts.boneAdd = double(opts.boneAdd);
end

function tf = isBoolLike(x)
    tf = (islogical(x) || isnumeric(x)) && isscalar(x);
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
            error('acsApplyCraniumShellBonePrior:BadBoneMode', ...
                'Unknown mode "%s". Use spm, shellPrior, or shellOnly.', char(mode));
    end
end

function tissueFiles = normalizeTissueFiles(tissueFiles)
    if ischar(tissueFiles) || isstring(tissueFiles)
        tissueFiles = cellstr(string(tissueFiles));
    end
    if ~iscell(tissueFiles) || numel(tissueFiles) ~= 6
        error('acsApplyCraniumShellBonePrior:BadTissueFiles', ...
            'tissueFiles must be a 1x6 cell array of c1..c6 filenames.');
    end
    tissueFiles = cellfun(@char, tissueFiles(:)', 'UniformOutput', false);
    for k = 1:6
        if exist(tissueFiles{k}, 'file') ~= 2
            error('acsApplyCraniumShellBonePrior:TissueFileNotFound', ...
                'Tissue file not found: %s', tissueFiles{k});
        end
    end
end

function files = outputFiles(outputDir, outputStem)
    files = struct();
    files.t1File = fullfile(outputDir, [outputStem '.nii']);
    files.tissueFiles = cell(1, 6);
    for k = 1:6
        files.tissueFiles{k} = fullfile(outputDir, sprintf('c%d%s.nii', k, outputStem));
    end
    files.brainMask = fullfile(outputDir, [outputStem '_brainMask.nii']);
    files.shellPrior = fullfile(outputDir, [outputStem '_craniumShellPrior.nii']);
    files.reportMat = fullfile(outputDir, [outputStem '_bonePriorReport.mat']);
    files.reportJson = fullfile(outputDir, [outputStem '_bonePriorReport.json']);
end

function tf = outputsExist(files)
    tf = exist(files.t1File, 'file') == 2 && ...
        exist(files.brainMask, 'file') == 2 && ...
        exist(files.shellPrior, 'file') == 2;
    for k = 1:6
        tf = tf && exist(files.tissueFiles{k}, 'file') == 2;
    end
end

function out = baseReport(t1File, tissueFiles, files, opts)
    out = struct();
    out.createdOn = char(datetime('now'));
    out.mode = opts.mode;
    out.sourceT1File = t1File;
    out.sourceTissueFiles = tissueFiles(:);
    out.files = files;
    out.parameters = struct( ...
        'shellDilateMm', opts.shellDilateMm, ...
        'shellSmoothMm', opts.shellSmoothMm, ...
        'brainThreshold', opts.brainThreshold, ...
        'boneFloor', opts.boneFloor, ...
        'boneBoost', opts.boneBoost, ...
        'boneAdd', opts.boneAdd, ...
        'constraintMaskFile', opts.constraintMaskFile);
end

function validateSameGrid(Vref, V, fileName)
    if any(Vref.dim(1:3) ~= V.dim(1:3))
        error('acsApplyCraniumShellBonePrior:DimensionMismatch', ...
            '%s has dimensions %s but expected %s.', ...
            fileName, mat2str(V.dim(1:3)), mat2str(Vref.dim(1:3)));
    end
    if max(abs(Vref.mat(:) - V.mat(:))) > 1e-4
        error('acsApplyCraniumShellBonePrior:AffineMismatch', ...
            '%s is not in the same affine space as %s.', fileName, Vref.fname);
    end
end

function mask = readConstraintMask(maskFile, Vref)
    if isempty(maskFile)
        mask = true(Vref.dim(1:3));
        return;
    end
    Vm = spm_vol(maskFile);
    Vm = Vm(1);
    validateSameGrid(Vref, Vm, maskFile);
    mask = spm_read_vols(Vm) > 0.5;
end

function [brainMask, shellPrior] = buildCraniumShell(P, Vref, constraintMask, opts)
    brainProb = min(1, P{1} + P{2} + P{3});
    brainMask = brainProb >= opts.brainThreshold;
    brainMask = keepLargest3D(brainMask);
    brainMask = fillHoles3D(brainMask);
    brainMask = keepLargest3D(brainMask);

    voxelSize = voxelSizesFromMat(Vref.mat);
    dilatedBrain = dilateMask(brainMask, opts.shellDilateMm, voxelSize);
    shell = dilatedBrain & ~brainMask & constraintMask;

    if opts.shellSmoothMm > 0
        sigmaVox = max(opts.shellSmoothMm ./ voxelSize, 0.01);
        shellPrior = imgaussfilt3(single(shell), sigmaVox);
    else
        shellPrior = single(shell);
    end
    shellPrior(~constraintMask) = 0;
    shellPrior(brainMask) = 0;
    if max(shellPrior(:)) > 0
        shellPrior = shellPrior ./ max(shellPrior(:));
    end
    shellPrior = max(0, min(1, single(shellPrior)));
end

function Pout = applyBoneReweighting(P, shellPrior, opts)
    Pout = P;
    switch opts.mode
        case 'shellPrior'
            gate = single(opts.boneFloor + opts.boneBoost .* shellPrior);
            Pout{4} = P{4} .* gate + single(opts.boneAdd) .* shellPrior;
        case 'shellOnly'
            Pout{4} = shellPrior;
        otherwise
            error('acsApplyCraniumShellBonePrior:UnsupportedMode', ...
                'Unsupported bone mode: %s', opts.mode);
    end

    total = zeros(size(Pout{1}), 'single');
    for k = 1:numel(Pout)
        Pout{k}(~isfinite(Pout{k}) | Pout{k} < 0) = 0;
        total = total + Pout{k};
    end

    valid = total > 0;
    for k = 1:numel(Pout)
        tmp = zeros(size(Pout{k}), 'single');
        tmp(valid) = Pout{k}(valid) ./ total(valid);
        Pout{k} = tmp;
    end
end

function A = dilateMask(A, radiusMm, voxelSize)
    if radiusMm <= 0
        return;
    end
    se = ellipsoidStrel(radiusMm, voxelSize);
    A = imdilate(A, se);
end

function se = ellipsoidStrel(radiusMm, voxelSize)
    rad = max(1, round(radiusMm ./ voxelSize));
    [x, y, z] = ndgrid(-rad(1):rad(1), -rad(2):rad(2), -rad(3):rad(3));
    se = (x ./ max(rad(1), 1)).^2 + ...
        (y ./ max(rad(2), 1)).^2 + ...
        (z ./ max(rad(3), 1)).^2 <= 1;
end

function Afilled = fillHoles3D(A)
    A = logical(A);
    sz = size(A);
    B = ~A;
    boundary = false(sz);
    boundary(1,:,:) = true;
    boundary(end,:,:) = true;
    boundary(:,1,:) = true;
    boundary(:,end,:) = true;
    boundary(:,:,1) = true;
    boundary(:,:,end) = true;

    CC = bwconncomp(B, 6);
    exterior = false(numel(A), 1);
    b = boundary(:);
    for i = 1:CC.NumObjects
        idx = CC.PixelIdxList{i};
        if any(b(idx))
            exterior(idx) = true;
        end
    end
    Afilled = ~reshape(exterior, sz);
end

function A = keepLargest3D(A)
    A = logical(A);
    CC = bwconncomp(A, 26);
    if CC.NumObjects < 1
        return;
    end
    [~, idx] = max(cellfun(@numel, CC.PixelIdxList));
    A(:) = false;
    A(CC.PixelIdxList{idx}) = true;
end

function writeReferenceCopy(fileName, Vref, sourceFile, description)
    deleteDerivedNifti(fileName);
    data = spm_read_vols(Vref);
    writeScalarVolume(fileName, Vref, data, description);

    [sourceFolder, sourceBase] = fileparts(sourceFile);
    sourceMat = fullfile(sourceFolder, [sourceBase '.mat']);
    [targetFolder, targetBase] = fileparts(fileName);
    targetMat = fullfile(targetFolder, [targetBase '.mat']);
    if exist(sourceMat, 'file') == 2 && exist(targetMat, 'file') ~= 2
        copyfile(sourceMat, targetMat);
    end
end

function writeMaskVolume(fileName, Vref, mask, description)
    writeScalarVolume(fileName, Vref, single(mask), description);
end

function writeScalarVolume(fileName, Vref, data, description)
    deleteDerivedNifti(fileName);
    Vout = Vref;
    Vout.fname = fileName;
    Vout.dim = size(data);
    Vout.dt = [spm_type('float32') spm_platform('bigend')];
    Vout.n = [1 1];
    Vout.private = [];
    Vout.pinfo = [1; 0; 0];
    Vout.descrip = description;
    spm_write_vol(Vout, single(data));
end

function stats = scalarStats(V)
    vals = double(V(:));
    vals = vals(isfinite(vals));
    stats = struct();
    stats.min = min(vals);
    stats.max = max(vals);
    stats.mean = mean(vals);
    stats.nonzeroFraction = mean(vals > 0);
end

function vx = voxelSizesFromMat(M)
    vx = sqrt(sum(M(1:3, 1:3) .^ 2, 1));
    if any(~isfinite(vx)) || any(vx == 0)
        vx = [1 1 1];
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

function ensureDir(pathIn)
    if exist(pathIn, 'dir') ~= 7
        mkdir(pathIn);
    end
end

function writeJsonReport(reportJson, report)
    fid = fopen(reportJson, 'w');
    if fid == -1
        error('acsApplyCraniumShellBonePrior:CannotWriteJson', ...
            'Could not write report JSON: %s', reportJson);
    end
    cleaner = onCleanup(@() fclose(fid));
    fprintf(fid, '%s', jsonencode(report, 'PrettyPrint', true));
    clear cleaner;
end

function name = safeName(value)
    name = regexprep(char(value), '[^a-zA-Z0-9_]', '_');
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

function logMsg(opts, varargin)
    if opts.verbose
        fprintf([varargin{1} '\n'], varargin{2:end});
    end
end
