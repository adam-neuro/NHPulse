function out = templateMaker(varargin)
% TEMPLATEMAKER Build macaque tissue probability maps in an external folder.
%
% out = templateMaker('mode', 'atlasPriors') builds a six-channel TPM from
% gm/wm/csf prior volumes. This preserves the first section of the original
% exploratory script.
%
% out = templateMaker('mode', 'nmt2') builds a six-channel TPM from the
% NMT2 full-head anatomical image and segmentation. This preserves the
% second section of the original exploratory script.
%
% Name-value options:
%   mode       : 'atlasPriors' (default), 'nmt2', or 'all'
%   priorDir   : folder containing gm/wm/csf prior files
%   atlasDir   : folder containing NMT2 full-head files
%   outputDir  : destination folder; defaults under acsPaths().outputRoot
%   outputName : output filename for single-mode calls
%
% Generated NIfTI files should stay outside git. The default outputDir is
% under the ignored outputs/templates folder.
%
% Output channels follow ROAST/SPM order:
%   1 gray matter, 2 white matter, 3 CSF, 4 bone, 5 skin/scalp, 6 air.

    opts = parseTemplateMakerInputs(varargin{:});
    P = opts.paths;
    if isempty(P)
        P = acsPaths();
    end

    mode = validatestring(opts.mode, {'atlasPriors', 'nmt2', 'all'});

    if isempty(opts.outputDir)
        opts.outputDir = fullfile(P.templateOutputRoot, mode);
    end

    switch mode
        case 'atlasPriors'
            out = buildAtlasPriorTpm(P, opts);
        case 'nmt2'
            out = buildNmt2Tpm(P, opts);
        case 'all'
            out = struct();
            atlasOpts = opts;
            atlasOpts.mode = 'atlasPriors';
            atlasOpts.outputDir = fullfile(opts.outputDir, 'atlasPriors');
            atlasOpts.outputName = '';
            out.atlasPriors = buildAtlasPriorTpm(P, atlasOpts);

            nmtOpts = opts;
            nmtOpts.mode = 'nmt2';
            nmtOpts.outputDir = fullfile(opts.outputDir, 'nmt2');
            nmtOpts.outputName = '';
            out.nmt2 = buildNmt2Tpm(P, nmtOpts);
    end
end

function opts = parseTemplateMakerInputs(varargin)
    p = inputParser;
    p.FunctionName = 'templateMaker';
    addParameter(p, 'mode', 'atlasPriors', @(x) ischar(x) || isstring(x));
    addParameter(p, 'priorDir', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'atlasDir', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'outputDir', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'outputName', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'paths', [], @(x) isempty(x) || isstruct(x));
    addParameter(p, 'gmPrior', 'gm_priors_ohsu+uw.nii', @(x) ischar(x) || isstring(x));
    addParameter(p, 'wmPrior', 'wm_priors_ohsu+uw.nii', @(x) ischar(x) || isstring(x));
    addParameter(p, 'csfPrior', 'csf_priors_ohsu+uw.nii', @(x) ischar(x) || isstring(x));
    addParameter(p, 'nmtSegFile', 'NMT_v2.0_sym_fh_segmentation.nii', @(x) ischar(x) || isstring(x));
    addParameter(p, 'nmtMriFile', 'NMT_v2.0_sym_fh.nii', @(x) ischar(x) || isstring(x));
    parse(p, varargin{:});
    opts = p.Results;

    charFields = {'mode', 'priorDir', 'atlasDir', 'outputDir', 'outputName', ...
        'gmPrior', 'wmPrior', 'csfPrior', 'nmtSegFile', 'nmtMriFile'};
    for i = 1:numel(charFields)
        f = charFields{i};
        opts.(f) = char(opts.(f));
    end
end

function out = buildAtlasPriorTpm(P, opts)
    priorDir = opts.priorDir;
    if isempty(priorDir)
        priorDir = fullfile(P.dataRoot, 'MRIs', 'atlasfiles');
    end
    outputName = opts.outputName;
    if isempty(outputName)
        outputName = 'tpm.nii';
    end

    [Vg, infoG] = readScaledNifti(fullfile(priorDir, opts.gmPrior));
    Vw = readScaledNifti(fullfile(priorDir, opts.wmPrior));
    Vc = readScaledNifti(fullfile(priorDir, opts.csfPrior));

    % Merge the internal tissue priors, then grow shells for bone/skin/air.
    Vt = 1 - ((1 - Vg) .* (1 - Vw) .* (1 - Vc));
    Vt = Vt > 0.1;

    h = fspecial3('ellipsoid', 5);
    h = double(h > 0);
    Vf = imfilter(Vt, h, 'replicate');

    Vd = double(Vf & ~Vt);
    Vb = imgaussfilt3(Vd, 10);
    Vb = 0.4 .* Vb + 0.1;

    Vh = Vb > 0.1 | Vt;
    h = fspecial3('ellipsoid', 15);
    h = double(h > 0);
    Vs = imfilter(Vh, h, 'replicate');
    Vs = double(Vs & ~Vh);
    Vs = imgaussfilt3(Vs, 8);
    Vs = 0.3 .* Vs + 0.1;

    Vx = Vs > 0.1 | Vh;
    Vn = double(~Vx);
    Vn = imgaussfilt3(Vn, 8);
    if max(Vn(:)) > 0
        Vn = 0.5 .* max(Vg(:)) .* Vn ./ max(Vn(:)) + 0.1;
    end

    Vall = single(cat(4, Vg, Vw, Vc, Vb, Vs, Vn));
    outFile = writeTpm(Vall, infoG, opts.outputDir, outputName);

    out = struct( ...
        'mode', 'atlasPriors', ...
        'priorDir', priorDir, ...
        'outputFile', outFile, ...
        'channels', {{'gray', 'white', 'csf', 'bone', 'skin', 'air'}});
end

function out = buildNmt2Tpm(P, opts)
    atlasDir = opts.atlasDir;
    if isempty(atlasDir)
        atlasDir = fullfile(P.boxRoot, 'NMT_v2.0_sym', 'NMT_v2.0_sym_fh');
    end
    outputName = opts.outputName;
    if isempty(outputName)
        outputName = 'nmt2_tpm.nii';
    end

    segPath = fullfile(atlasDir, opts.nmtSegFile);
    mriPath = fullfile(atlasDir, opts.nmtMriFile);

    Vs = niftiread(segPath);
    [Vh, info] = readScaledNifti(mriPath);

    Vg = Vs == 2 | Vs == 3;      % cortex or basal nuclei
    Vw = Vs == 4;
    Vc = Vs == 1 | Vs == 5;      % csf or blood

    Vg = imgaussfilt3(double(Vg), 2) .* 0.99;
    Vw = imgaussfilt3(double(Vw), 2) .* 0.99;
    Vc = imgaussfilt3(double(Vc), 2) .* 0.99;

    Vg(Vg < 0) = 0;
    Vw(Vw < 0) = 0;
    Vc(Vc < 0) = 0;

    boneRange = [45 100];
    rightRange = Vh > min(boneRange) & Vh < max(boneRange);

    brain = Vs > 0;
    h = fspecial3('ellipsoid', 8);
    h = double(h > 0);
    brainPlus = imfilter(brain, h, 'replicate');

    rightPlace = brainPlus - brain;
    rightPlace = imgaussfilt3(double(rightPlace), 5);
    rightRange = imgaussfilt3(double(rightRange), 3);

    bone = 2 * rightPlace + rightRange;
    bone = bone ./ 3;

    tissueRange = [150 1000];
    tissue = Vh > min(tissueRange) & Vh < max(tissueRange);
    tissue(brainPlus > 0) = 0;
    tissue = imgaussfilt3(double(tissue), 5) .* 0.99;

    other = Vh < 100;
    other(brainPlus > 0 | bone > 0.2 | tissue > 0.1) = 0;

    h = fspecial3('ellipsoid', 8);
    h = double(h > 0);
    other = imfilter(other, h, 'replicate');
    other = imgaussfilt3(double(other), 5);

    bone(tissue > 0.1 | other > 0) = 0;
    bone = imgaussfilt3(bone, 3) .^ 2;
    if max(bone(:)) > 0
        bone = 0.6 .* bone ./ max(bone(:));
    end

    Vall = single(cat(4, Vg, Vw, Vc, bone, tissue, other));
    outFile = writeTpm(Vall, info, opts.outputDir, outputName);

    out = struct( ...
        'mode', 'nmt2', ...
        'atlasDir', atlasDir, ...
        'outputFile', outFile, ...
        'channels', {{'gray', 'white', 'csf', 'bone', 'skin', 'air'}});
end

function [V, info] = readScaledNifti(filePath)
    if exist(filePath, 'file') ~= 2
        error('templateMaker:MissingInput', 'Input NIfTI not found: %s', filePath);
    end
    info = niftiinfo(filePath);
    V = double(niftiread(filePath));

    scale = 1;
    offset = 0;
    if isfield(info, 'MultiplicativeScaling') && ~isempty(info.MultiplicativeScaling)
        scale = double(info.MultiplicativeScaling);
    end
    if isfield(info, 'AdditiveOffset') && ~isempty(info.AdditiveOffset)
        offset = double(info.AdditiveOffset);
    end
    V = V .* scale + offset;
end

function outFile = writeTpm(Vall, infoIn, outputDir, outputName)
    if ~exist(outputDir, 'dir')
        mkdir(outputDir);
    end

    infoOut = infoIn;
    infoOut.Datatype = 'single';
    infoOut.ImageSize = size(Vall);
    infoOut.PixelDimensions = normalizePixelDimensions(infoOut.PixelDimensions, ndims(Vall));
    if isfield(infoOut, 'MultiplicativeScaling')
        infoOut.MultiplicativeScaling = 1;
    end
    if isfield(infoOut, 'AdditiveOffset')
        infoOut.AdditiveOffset = 0;
    end

    outFile = fullfile(outputDir, outputName);
    niftiwrite(Vall, outFile, infoOut);
end

function pixelDimensions = normalizePixelDimensions(pixelDimensions, nDims)
    pixelDimensions = double(pixelDimensions(:)');
    if numel(pixelDimensions) < nDims
        pixelDimensions = [pixelDimensions, ones(1, nDims - numel(pixelDimensions))];
    end
    pixelDimensions = pixelDimensions(1:nDims);
end
