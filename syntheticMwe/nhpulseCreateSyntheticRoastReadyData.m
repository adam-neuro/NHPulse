function out = nhpulseCreateSyntheticRoastReadyData(outputDir, varargin)
% NHPULSECREATESYNTHETICROASTREADYDATA Create tiny synthetic NHPulse demo data.
%
% out = nhpulseCreateSyntheticRoastReadyData() writes a small, cartoon-like
% macaque-head T1 NIfTI and matching ROAST hard-label mask into
% outputs/syntheticMwe/nhpulseSynthetic01. This is intended for minimal
% working examples and installer checks, not scientific modeling.
%
% out = nhpulseCreateSyntheticRoastReadyData(outputDir, ...) writes to a
% custom output folder.
%
% The generated label mask follows ROAST's convention:
%   1 white, 2 gray, 3 CSF, 4 bone, 5 skin, 6 air
%
% Name-value options:
%   subjectId        : output stem prefix ['nhpulseSynthetic01']
%   dims             : volume dimensions in voxels [[96 120 96]]
%   voxelSizeMm      : isotropic voxel size [1]
%   includePhoneScan : write a synthetic phone-scan-like PLY/MAT [true]
%   includeFiducials : write paired model/phone fiducial MAT files [true]
%   force            : overwrite existing files [false]
%   showFigure       : show QC figure [true]
%   saveFigure       : save QC PNG [true]
%   verbose          : print summary [true]

    parameterNames = {'subjectId', 'dims', 'voxelSizeMm', ...
        'includePhoneScan', 'includeFiducials', 'force', ...
        'showFigure', 'saveFigure', 'verbose', 'rngSeed', ...
        'phoneScanInflationMm', 'phoneScanScale', 'phoneScanRotationDeg', ...
        'phoneScanTranslationMm', 'phoneScanMaxFaces'};

    if nargin < 1 || isempty(outputDir)
        outputDir = defaultOutputDir();
    elseif isNameValueKey(outputDir, parameterNames)
        varargin = [{outputDir}, varargin];
        outputDir = defaultOutputDir();
    end

    opts = parseInputs(parameterNames, varargin{:});
    outputDir = char(outputDir);
    addLocalDependencies();
    requireSpmWrite();

    ensureDir(outputDir);
    paths = outputPaths(outputDir, opts.subjectId);
    guardOverwrite(paths, opts.force);

    rng(opts.rngSeed);
    [labels, t1, geometry] = makeSyntheticVolume(opts);

    mat = makeSpmVoxelMatrix(opts.voxelSizeMm);
    writeNifti(paths.t1File, t1, mat, 'float32', ...
        'NHPulse synthetic T1-like volume');
    writeNifti(paths.maskFile, labels, mat, 'uint8', ...
        'NHPulse synthetic ROAST hard-label mask');

    modelFiducials = [];
    phone = [];
    phoneFiducials = [];
    if opts.includeFiducials
        modelFiducials = makeModelFiducials(geometry, paths, opts);
        savePointSet(paths.modelFiducialsFile, modelFiducials);
    end

    if opts.includePhoneScan
        phone = makeSyntheticPhoneScan(labels, geometry, opts);
        writeAsciiPly(paths.phoneScanPlyFile, phone.vertices, phone.faces, phone.rgb);
        phoneOut = makePhoneCropLikeOutput(phone, paths, opts);
        savePhoneScanMat(paths.phoneScanMatFile, phoneOut);

        if opts.includeFiducials
            phoneFiducials = makePhoneFiducials(modelFiducials, phone.transform, paths, opts);
            savePointSet(paths.phoneFiducialsFile, phoneFiducials);
        end
    end

    out = buildOutput(outputDir, paths, geometry, modelFiducials, phone, ...
        phoneFiducials, opts);

    fig = [];
    if opts.showFigure || opts.saveFigure
        figVisible = 'off';
        if opts.showFigure
            figVisible = 'on';
        end
        fig = makeQcFigure(labels, t1, geometry, out, figVisible);
        if opts.saveFigure
            saveas(fig, paths.qcPngFile);
            out.qcFigure = paths.qcPngFile;
        end
        if ~opts.showFigure && isgraphics(fig)
            close(fig);
            fig = [];
        end
    end
    out.figure = fig;

    outForSave = out;
    if isfield(outForSave, 'figure')
        outForSave = rmfield(outForSave, 'figure');
    end
    outReturned = out;
    out = outForSave; %#ok<NASGU>
    outSaved = outForSave; %#ok<NASGU>
    outToSave = outForSave; %#ok<NASGU>
    save(paths.reportMatFile, 'out', 'outForSave', 'outSaved', ...
        'outToSave', '-v7.3');
    out = outReturned;
    writeJson(paths.reportJsonFile, jsonReady(outForSave));

    if opts.verbose
        printSummary(out);
    end
end

function opts = parseInputs(parameterNames, varargin)
    p = inputParser;
    p.FunctionName = 'nhpulseCreateSyntheticRoastReadyData';
    addParameter(p, 'subjectId', 'nhpulseSynthetic01', ...
        @(x) ischar(x) || isstring(x));
    addParameter(p, 'dims', [96 120 96], ...
        @(x) isnumeric(x) && numel(x) == 3 && all(x >= 48));
    addParameter(p, 'voxelSizeMm', 1, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x > 0);
    addParameter(p, 'includePhoneScan', true, @isBoolLike);
    addParameter(p, 'includeFiducials', true, @isBoolLike);
    addParameter(p, 'force', false, @isBoolLike);
    addParameter(p, 'showFigure', true, @isBoolLike);
    addParameter(p, 'saveFigure', true, @isBoolLike);
    addParameter(p, 'verbose', true, @isBoolLike);
    addParameter(p, 'rngSeed', 1, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x));
    addParameter(p, 'phoneScanInflationMm', 3, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x));
    addParameter(p, 'phoneScanScale', 1.03, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x > 0);
    addParameter(p, 'phoneScanRotationDeg', [0 0 0], ...
        @(x) isnumeric(x) && numel(x) == 3 && all(isfinite(x)));
    addParameter(p, 'phoneScanTranslationMm', [18 -12 22], ...
        @(x) isnumeric(x) && numel(x) == 3 && all(isfinite(x)));
    addParameter(p, 'phoneScanMaxFaces', 5000, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 500);
    parse(p, varargin{:});

    opts = p.Results;
    opts.subjectId = safeName(char(opts.subjectId));
    opts.dims = round(double(opts.dims(:)'));
    opts.voxelSizeMm = double(opts.voxelSizeMm);
    opts.includePhoneScan = logical(opts.includePhoneScan);
    opts.includeFiducials = logical(opts.includeFiducials);
    opts.force = logical(opts.force);
    opts.showFigure = logical(opts.showFigure);
    opts.saveFigure = logical(opts.saveFigure);
    opts.verbose = logical(opts.verbose);
    opts.rngSeed = double(opts.rngSeed);
    opts.phoneScanInflationMm = double(opts.phoneScanInflationMm);
    opts.phoneScanScale = double(opts.phoneScanScale);
    opts.phoneScanRotationDeg = double(opts.phoneScanRotationDeg(:)');
    opts.phoneScanTranslationMm = double(opts.phoneScanTranslationMm(:)');
    opts.phoneScanMaxFaces = round(double(opts.phoneScanMaxFaces));

    unknown = setdiff(fieldnames(opts), parameterNames);
    if ~isempty(unknown)
        error('nhpulseCreateSyntheticRoastReadyData:BadParser', ...
            'Internal parser mismatch: %s', strjoin(unknown, ', '));
    end
end

function tf = isBoolLike(x)
    tf = (islogical(x) || isnumeric(x)) && isscalar(x);
end

function tf = isNameValueKey(value, parameterNames)
    tf = (ischar(value) || isstring(value)) && ...
        any(strcmpi(char(value), parameterNames));
end

function addLocalDependencies()
    repoRoot = fileparts(fileparts(mfilename('fullpath')));
    if exist('setNHPulsePath', 'file') ~= 2
        addpath(repoRoot);
    end
    setNHPulsePath('repoRoot', repoRoot, 'verbose', false);
    spmDir = fullfile(repoRoot, 'lib', 'spm12');
    if exist(spmDir, 'dir') == 7
        addpath(spmDir);
    end
end

function requireSpmWrite()
    if exist('spm_write_vol', 'file') ~= 2 || ...
            exist('spm_type', 'file') ~= 2
        error('nhpulseCreateSyntheticRoastReadyData:MissingSpm', ...
            '%s', nhpulseMissingDependencyMessage('SPM', ...
            'SPM is required to write the synthetic NIfTI files.', ...
            {'spm_write_vol', 'spm_type'}));
    end
end

function outputDir = defaultOutputDir()
    repoRoot = fileparts(fileparts(mfilename('fullpath')));
    outputDir = fullfile(repoRoot, 'outputs', 'syntheticMwe', ...
        'nhpulseSynthetic01');
end

function paths = outputPaths(outputDir, subjectId)
    t1Stem = [subjectId '_T1'];
    paths = struct();
    paths.outputDir = outputDir;
    paths.t1File = fullfile(outputDir, [t1Stem '.nii']);
    paths.maskFile = fullfile(outputDir, [t1Stem '_T1orT2_SPM_masks.nii']);
    paths.reportMatFile = fullfile(outputDir, [subjectId '_syntheticReport.mat']);
    paths.reportJsonFile = fullfile(outputDir, [subjectId '_syntheticReport.json']);
    paths.qcPngFile = fullfile(outputDir, [subjectId '_syntheticQc.png']);
    paths.modelFiducialsFile = fullfile(outputDir, ...
        [subjectId '_modelFiducials.mat']);
    paths.phoneScanPlyFile = fullfile(outputDir, ...
        [subjectId '_phoneScanSynthetic.ply']);
    paths.phoneScanMatFile = fullfile(outputDir, ...
        [subjectId '_phoneScanSynthetic.mat']);
    paths.phoneFiducialsFile = fullfile(outputDir, ...
        [subjectId '_phoneFiducials.mat']);
end

function guardOverwrite(paths, force)
    if force
        return;
    end
    files = struct2cell(paths);
    files = files(cellfun(@(x) ischar(x) || isstring(x), files));
    keep = cellfun(@(x) any(endsWith(char(x), ...
        {'.nii', '.mat', '.json', '.png', '.ply'}, 'IgnoreCase', true)), ...
        files);
    files = files(keep);
    hits = files(cellfun(@(x) exist(char(x), 'file') == 2, files));
    if ~isempty(hits)
        error('nhpulseCreateSyntheticRoastReadyData:OutputExists', ...
            ['Synthetic output already exists. Re-run with force=true, ', ...
             'or choose a new output folder. First existing file: %s'], hits{1});
    end
end

function [labels, t1, geometry] = makeSyntheticVolume(opts)
    dims = opts.dims;
    vox = opts.voxelSizeMm;
    [I, J, K] = ndgrid(1:dims(1), 1:dims(2), 1:dims(3));
    P = cat(4, I .* vox, J .* vox, K .* vox);
    centerMm = ((dims + 1) ./ 2) .* vox;

    X = P(:, :, :, 1) - centerMm(1);
    Y = P(:, :, :, 2) - centerMm(2);
    Z = P(:, :, :, 3) - centerMm(3);

    headAxes = [32 42 30];
    head = ellipsoidValue(X, Y + 4, Z + 1, headAxes) <= 1;
    nose = ellipsoidValue(X, Y - 35, Z + 3, [9 15 8]) <= 1 & Y > 21;
    leftEar = ellipsoidValue(X + 32, Y + 2, Z + 1, [6 10 12]) <= 1;
    rightEar = ellipsoidValue(X - 32, Y + 2, Z + 1, [6 10 12]) <= 1;
    outerHead = head | nose | leftEar | rightEar;

    labels = uint8(6 .* ones(dims));
    labels(outerHead) = uint8(5);

    bone = ellipsoidValue(X, Y + 4, Z + 1, [27 35 24]) <= 1;
    noseBone = ellipsoidValue(X, Y - 31, Z + 3, [5.5 8 4.5]) <= 1 & Y > 21;
    labels(bone | noseBone) = uint8(4);

    csf = ellipsoidValue(X, Y + 4, Z + 1, [21 27 19]) <= 1;
    gray = ellipsoidValue(X, Y + 4, Z + 1, [19 24 17]) <= 1;
    white = ellipsoidValue(X, Y + 4, Z + 1, [15.5 19 13.5]) <= 1;
    labels(csf) = uint8(3);
    labels(gray) = uint8(2);
    labels(white) = uint8(1);

    t1 = single(8 .* ones(dims));
    t1(labels == 6) = 6;
    t1(labels == 5) = 85;
    t1(labels == 4) = 55;
    t1(labels == 3) = 32;
    t1(labels == 2) = 112;
    t1(labels == 1) = 148;
    bias = 1 + 0.06 .* (X ./ max(abs(X(:)))) - 0.04 .* (Y ./ max(abs(Y(:))));
    t1 = single(double(t1) .* bias + 2 .* randn(dims));
    t1(t1 < 0) = 0;

    geometry = struct();
    geometry.dims = dims;
    geometry.voxelSizeMm = vox;
    geometry.centerMm = centerMm;
    geometry.coordinateFrame = 'roastVoxelScaledMm';
    geometry.headAxesMm = headAxes;
    geometry.labelNames = {'white', 'gray', 'CSF', 'bone', 'skin', 'air'};
    geometry.demoTargetMm = centerMm + [8 8 9];
    geometry.demoTargetVoxel = max([1 1 1], ...
        min(dims, round(geometry.demoTargetMm ./ vox)));
end

function value = ellipsoidValue(X, Y, Z, axesMm)
    value = (X ./ axesMm(1)) .^ 2 + (Y ./ axesMm(2)) .^ 2 + ...
        (Z ./ axesMm(3)) .^ 2;
end

function mat = makeSpmVoxelMatrix(voxelSizeMm)
    mat = diag([voxelSizeMm voxelSizeMm voxelSizeMm 1]);
end

function writeNifti(fileName, data, mat, spmTypeName, description)
    V = struct();
    V.fname = fileName;
    V.dim = size(data);
    V.dt = [spm_type(spmTypeName) 0];
    V.mat = mat;
    V.pinfo = [1; 0; 0];
    V.descrip = description;
    spm_write_vol(V, data);
end

function fiducials = makeModelFiducials(geometry, paths, opts)
    c = geometry.centerMm;
    labels = {'Nas'; 'Lpa'; 'Rpa'; 'Ini'};
    coords = [ ...
        c + [0 38 -2]; ...
        c + [-32 -3 -1]; ...
        c + [32 -3 -1]; ...
        c + [0 -43 4]];

    fiducials = pointSetStruct(labels, coords, paths.maskFile, ...
        'syntheticModelFiducials', opts);
    fiducials.source.file = '';
    fiducials.source.maskFile = paths.maskFile;
    fiducials.coordinateFrame = 'capMakerPreCropWorldMm';
    fiducials.meshStage = 'syntheticRoastReadyMask';
end

function phone = makeSyntheticPhoneScan(labels, geometry, opts)
    outerMask = labels ~= uint8(6);
    fv = surfaceFromMask(outerMask, opts.phoneScanMaxFaces, geometry.voxelSizeMm);
    V = double(fv.vertices);
    F = double(fv.faces);
    center = geometry.centerMm;
    radial = V - center;
    normRadial = sqrt(sum(radial .^ 2, 2));
    unitRadial = radial ./ max(normRadial, eps);
    V = V + opts.phoneScanInflationMm .* unitRadial;

    R = eulRowRotationDeg(opts.phoneScanRotationDeg);
    T = opts.phoneScanTranslationMm;
    scale = opts.phoneScanScale;
    Vphone = (V - center) .* scale * R + center + T;
    rgb = syntheticVertexColors(Vphone, center + T);

    phone = struct();
    phone.vertices = Vphone;
    phone.faces = F;
    phone.rgb = rgb;
    phone.transform = struct('sourceFrame', 'capMakerPreCropWorldMm', ...
        'targetFrame', 'syntheticPhoneScanMm', ...
        'rotation', R, ...
        'translationMm', T, ...
        'scale', scale, ...
        'centerMm', center);
    phone.surfaceVertexCount = size(Vphone, 1);
    phone.surfaceFaceCount = size(F, 1);
end

function fv = surfaceFromMask(mask, maxFaces, voxelSizeMm)
    rows = find(mask);
    [i, j, k] = ind2sub(size(mask), rows);
    lo = max([1 1 1], min([i j k], [], 1) - 2);
    hi = min(size(mask), max([i j k], [], 1) + 2);
    local = mask(lo(1):hi(1), lo(2):hi(2), lo(3):hi(3));
    padded = false(size(local) + 2);
    padded(2:end - 1, 2:end - 1, 2:end - 1) = local;
    [X, Y, Z] = ndgrid( ...
        ((lo(1) - 2):(lo(1) + size(padded, 1) - 3)) .* voxelSizeMm, ...
        ((lo(2) - 2):(lo(2) + size(padded, 2) - 3)) .* voxelSizeMm, ...
        ((lo(3) - 2):(lo(3) + size(padded, 3) - 3)) .* voxelSizeMm);
    fv = isosurface(X, Y, Z, single(padded), 0.5);
    if size(fv.faces, 1) > maxFaces && exist('reducepatch', 'file') == 2
        fv = reducepatch(fv, maxFaces);
    end
end

function R = eulRowRotationDeg(deg)
    a = deg2rad(double(deg));
    Rx = [1 0 0; 0 cos(a(1)) -sin(a(1)); 0 sin(a(1)) cos(a(1))];
    Ry = [cos(a(2)) 0 sin(a(2)); 0 1 0; -sin(a(2)) 0 cos(a(2))];
    Rz = [cos(a(3)) -sin(a(3)) 0; sin(a(3)) cos(a(3)) 0; 0 0 1];
    R = Rx * Ry * Rz;
end

function rgb = syntheticVertexColors(V, center)
    zNorm = normalize01(V(:, 3));
    xShade = normalize01(V(:, 1) - center(1));
    skin = [190 168 145];
    darker = [118 111 104];
    rgb = uint8(round((1 - 0.35 .* zNorm) .* skin + ...
        (0.20 .* xShade) .* darker));
    rgb = max(uint8(0), min(uint8(255), rgb));
end

function x = normalize01(x)
    x = double(x);
    lo = min(x);
    hi = max(x);
    if hi <= lo
        x = zeros(size(x));
    else
        x = (x - lo) ./ (hi - lo);
    end
end

function phoneOut = makePhoneCropLikeOutput(phone, paths, opts)
    TRhead = triangulation(phone.faces, phone.vertices);
    phoneOut = struct();
    phoneOut.createdOn = char(datetime('now'));
    phoneOut.type = 'syntheticPhoneScanCrop';
    phoneOut.sourceFile = paths.phoneScanPlyFile;
    phoneOut.outputFile = paths.phoneScanMatFile;
    phoneOut.croppedPlyFile = paths.phoneScanPlyFile;
    phoneOut.TRhead = TRhead;
    phoneOut.vertices = phone.vertices;
    phoneOut.faces = phone.faces;
    phoneOut.rgb = phone.rgb;
    phoneOut.pointCloudMm = phone.vertices;
    phoneOut.unitsAssumption = 'synthetic millimeters';
    phoneOut.coordinateFrame = 'syntheticPhoneScanMm';
    phoneOut.syntheticTransform = phone.transform;
    phoneOut.options = opts;
end

function savePhoneScanMat(fileName, phoneOut)
    outForSave = phoneOut;
    TRhead = phoneOut.TRhead; %#ok<NASGU>
    save(fileName, 'outForSave', 'TRhead', '-v7.3');
end

function phoneFiducials = makePhoneFiducials(modelFiducials, transform, paths, opts)
    coords = applySyntheticPhoneTransform(modelFiducials.coordinatesMm, transform);
    phoneFiducials = pointSetStruct(modelFiducials.labels, coords, ...
        paths.phoneScanMatFile, 'syntheticPhoneFiducials', opts);
    phoneFiducials.coordinateFrame = 'syntheticPhoneScanMm';
    phoneFiducials.syntheticTransform = transform;
end

function P2 = applySyntheticPhoneTransform(P, transform)
    center = transform.centerMm;
    P2 = (double(P) - center) .* transform.scale * transform.rotation + ...
        center + transform.translationMm;
end

function pointSet = pointSetStruct(labels, coords, sourceFile, typeName, opts)
    pointSet = struct();
    pointSet.createdOn = char(datetime('now'));
    pointSet.type = typeName;
    pointSet.source = struct('file', sourceFile, ...
        'type', 'syntheticMwe', ...
        'subjectId', opts.subjectId);
    pointSet.labels = labels(:);
    pointSet.coordinatesMm = double(coords);
    pointSet.options = opts;
end

function savePointSet(fileName, pointSet)
    out = pointSet; %#ok<NASGU>
    outSaved = pointSet; %#ok<NASGU>
    outForSave = pointSet; %#ok<NASGU>
    outToSave = pointSet; %#ok<NASGU>
    save(fileName, 'out', 'outSaved', 'outForSave', 'outToSave', '-v7.3');
    writeJson(replaceExtension(fileName, '.json'), jsonReady(pointSet));
end

function out = buildOutput(outputDir, paths, geometry, modelFiducials, phone, ...
        phoneFiducials, opts)
    out = struct();
    out.createdOn = char(datetime('now'));
    out.type = 'nhpulseSyntheticRoastReadyData';
    out.subjectId = opts.subjectId;
    out.outputDir = outputDir;
    out.t1File = paths.t1File;
    out.maskFile = paths.maskFile;
    out.roastReady = struct('t1File', paths.t1File, ...
        'maskFile', paths.maskFile, ...
        'subjectId', opts.subjectId, ...
        'type', 'syntheticRoastReadyAnatomy');
    out.demoTargets = struct('targetVoxel', geometry.demoTargetVoxel, ...
        'targetMm', geometry.demoTargetMm, ...
        'description', 'toy right-dorsal frontal point');
    out.geometry = geometry;
    out.options = opts;
    out.reportMatFile = paths.reportMatFile;
    out.reportJsonFile = paths.reportJsonFile;
    out.qcFigure = '';

    if ~isempty(modelFiducials)
        out.modelFiducialsFile = paths.modelFiducialsFile;
        out.modelFiducials = stripOptions(modelFiducials);
    end
    if ~isempty(phone)
        out.phoneScanPlyFile = paths.phoneScanPlyFile;
        out.phoneScanMatFile = paths.phoneScanMatFile;
        out.phoneScan = rmfieldIfPresent(phone, {'vertices', 'faces', 'rgb'});
    end
    if ~isempty(phoneFiducials)
        out.phoneFiducialsFile = paths.phoneFiducialsFile;
        out.phoneFiducials = stripOptions(phoneFiducials);
    end
end

function S = stripOptions(S)
    S = rmfieldIfPresent(S, {'options'});
end

function S = rmfieldIfPresent(S, fields)
    for i = 1:numel(fields)
        if isfield(S, fields{i})
            S = rmfield(S, fields{i});
        end
    end
end

function fig = makeQcFigure(labels, t1, geometry, out, figVisible)
    fig = figure('Name', 'NHPulse synthetic MWE QC', ...
        'Color', 'w', 'Visible', figVisible, ...
        'WindowStyle', 'normal', ...
        'Position', [100 100 1100 620]);
    cmap = labelColormap();
    target = geometry.demoTargetVoxel;
    sliceSpec = { ...
        'Sagittal', target(1), squeeze(t1(target(1), :, :))', ...
            squeeze(labels(target(1), :, :))'; ...
        'Coronal', target(2), squeeze(t1(:, target(2), :))', ...
            squeeze(labels(:, target(2), :))'; ...
        'Axial', target(3), squeeze(t1(:, :, target(3)))', ...
            squeeze(labels(:, :, target(3)))'};

    for i = 1:3
        ax = subplot(2, 3, i, 'Parent', fig);
        imagesc(ax, sliceSpec{i, 3});
        colormap(ax, gray(256));
        axis(ax, 'image');
        axis(ax, 'off');
        title(ax, sprintf('%s %d', sliceSpec{i, 1}, sliceSpec{i, 2}), ...
            'FontWeight', 'bold');
        hold(ax, 'on');
        overlay = ind2rgb(double(sliceSpec{i, 4}) + 1, cmap);
        h = image(ax, overlay);
        set(h, 'AlphaData', double(sliceSpec{i, 4} > 0) .* 0.38);
    end

    ax4 = subplot(2, 3, 4:6, 'Parent', fig);
    head = labels ~= uint8(6);
    fv = surfaceFromMask(head, 5000, geometry.voxelSizeMm);
    patch(ax4, 'Faces', fv.faces, 'Vertices', fv.vertices, ...
        'FaceColor', [0.72 0.74 0.76], 'EdgeColor', 'none', ...
        'FaceAlpha', 1);
    hold(ax4, 'on');
    p = geometry.demoTargetMm;
    scatter3(ax4, p(1), p(2), p(3), 150, 'm', 'filled', ...
        'MarkerEdgeColor', [0.25 0 0.25], 'LineWidth', 1.5);
    if isfield(out, 'modelFiducials')
        C = out.modelFiducials.coordinatesMm ./ geometry.voxelSizeMm;
        scatter3(ax4, C(:, 1), C(:, 2), C(:, 3), 60, 'k', 'filled');
        for i = 1:numel(out.modelFiducials.labels)
            text(ax4, C(i, 1), C(i, 2), C(i, 3), ...
                [' ' out.modelFiducials.labels{i}], ...
                'FontSize', 9, 'Color', 'k');
        end
    end
    axis(ax4, 'equal');
    axis(ax4, 'off');
    view(ax4, [40 24]);
    camlight(ax4, 'headlight');
    lighting(ax4, 'gouraud');
    title(ax4, 'Synthetic head surface, fiducials, and demo target', ...
        'FontWeight', 'bold');
    sgtitle(fig, 'Synthetic ROAST-ready anatomy for NHPulse MWE', ...
        'FontWeight', 'bold');
end

function cmap = labelColormap()
    cmap = [ ...
        0.00 0.00 0.00; ...
        0.00 0.75 0.95; ...
        0.95 0.22 0.15; ...
        0.16 0.30 0.95; ...
        1.00 0.80 0.00; ...
        0.00 0.75 0.26; ...
        0.85 0.85 0.85];
end

function writeAsciiPly(fileName, V, F, rgb)
    fid = fopen(fileName, 'w');
    if fid < 0
        error('nhpulseCreateSyntheticRoastReadyData:CannotWritePly', ...
            'Could not write PLY file: %s', fileName);
    end
    cleaner = onCleanup(@() fclose(fid));
    fprintf(fid, 'ply\n');
    fprintf(fid, 'format ascii 1.0\n');
    fprintf(fid, 'comment NHPulse synthetic phone scan mesh\n');
    fprintf(fid, 'element vertex %d\n', size(V, 1));
    fprintf(fid, 'property float x\n');
    fprintf(fid, 'property float y\n');
    fprintf(fid, 'property float z\n');
    fprintf(fid, 'property uchar red\n');
    fprintf(fid, 'property uchar green\n');
    fprintf(fid, 'property uchar blue\n');
    fprintf(fid, 'element face %d\n', size(F, 1));
    fprintf(fid, 'property list uchar int vertex_indices\n');
    fprintf(fid, 'end_header\n');
    for i = 1:size(V, 1)
        fprintf(fid, '%.8g %.8g %.8g %d %d %d\n', ...
            V(i, 1), V(i, 2), V(i, 3), rgb(i, 1), rgb(i, 2), rgb(i, 3));
    end
    F0 = F - 1;
    for i = 1:size(F, 1)
        fprintf(fid, '3 %d %d %d\n', F0(i, 1), F0(i, 2), F0(i, 3));
    end
    clear cleaner;
end

function writeJson(fileName, S)
    fid = fopen(fileName, 'w');
    if fid < 0
        warning('nhpulseCreateSyntheticRoastReadyData:CannotWriteJson', ...
            'Could not write JSON report: %s', fileName);
        return;
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
    if isa(S, 'triangulation')
        S = struct('nVertices', size(S.Points, 1), ...
            'nFaces', size(S.ConnectivityList, 1));
    elseif isstruct(S)
        names = fieldnames(S);
        for i = 1:numel(S)
            for j = 1:numel(names)
                S(i).(names{j}) = jsonReady(S(i).(names{j}));
            end
        end
    elseif iscell(S)
        for i = 1:numel(S)
            S{i} = jsonReady(S{i});
        end
    elseif isa(S, 'function_handle')
        S = func2str(S);
    end
end

function fileName = replaceExtension(fileName, newExt)
    [folder, stem] = fileparts(fileName);
    fileName = fullfile(folder, [stem newExt]);
end

function ensureDir(folder)
    nhpulseEnsureWritableDir(folder, 'synthetic MWE output');
end

function name = safeName(name)
    name = regexprep(name, '[^\w.-]', '_');
    name = regexprep(name, '_+', '_');
    if isempty(name)
        name = 'nhpulseSynthetic01';
    end
end

function printSummary(out)
    fprintf('\nNHPulse synthetic MWE data\n');
    fprintf('  subject: %s\n', out.subjectId);
    fprintf('  output: %s\n', out.outputDir);
    fprintf('  T1: %s\n', out.t1File);
    fprintf('  ROAST labels: %s\n', out.maskFile);
    fprintf('  demo target voxel: [%g %g %g]\n', out.demoTargets.targetVoxel);
    if isfield(out, 'modelFiducialsFile')
        fprintf('  model fiducials: %s\n', out.modelFiducialsFile);
    end
    if isfield(out, 'phoneScanMatFile')
        fprintf('  synthetic phone scan MAT: %s\n', out.phoneScanMatFile);
        fprintf('  synthetic phone scan PLY: %s\n', out.phoneScanPlyFile);
    end
    if isfield(out, 'phoneFiducialsFile')
        fprintf('  phone fiducials: %s\n', out.phoneFiducialsFile);
    end
    if isfield(out, 'qcFigure') && ~isempty(out.qcFigure)
        fprintf('  QC figure: %s\n', out.qcFigure);
    end
    fprintf('  report: %s\n\n', out.reportMatFile);
end
