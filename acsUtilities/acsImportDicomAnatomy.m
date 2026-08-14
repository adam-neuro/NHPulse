function out = acsImportDicomAnatomy(subjectId, varargin)
% ACSIMPORTDICOMANATOMY Convert a subject DICOM anatomy series to NIfTI.
%
% out = acsImportDicomAnatomy('M2107') imports the default M2107 MPRAGE
% DICOM series into an ignored subject anatomy work directory.
%
% This is intentionally only the first preprocessing step: DICOM -> NIfTI
% plus basic QC metadata/figures. Segmentation and registration should run
% in later, separately checked steps.
%
% If the converted NIfTI has no usable affine, QC slice labels fall back to
% the SPM JSON sidecar's DICOM ImageOrientationPatient metadata.
%
% Name-value options:
%   seriesKey   : subject path key for the DICOM folder ['mprageInitial']
%   dicomDir    : explicit DICOM directory override ['']
%   outputDir   : explicit output directory override ['']
%   outputName  : canonical NIfTI filename ['<subject>_T1.nii']
%   force       : overwrite canonical output if present [false]
%   verbose     : print progress to command window [false]
%   showFigures : show QC figure windows [false]
%   saveFigures : save QC figure files [false]
%   qcTitleMode : 'compact' or 'verbose' ['compact']
%   figureExportOptions : struct passed to acsExportFigure [struct()]
%   figureStyle/figureFormats/etc. are retained as backward-compatible
%       aliases for fields in figureExportOptions.
%   configFile  : optional local.paths.json override ['']

    if nargin < 1 || isempty(subjectId)
        subjectId = 'M2107';
    end

    opts = parseInputs(varargin{:});
    subjectId = char(subjectId);
    subjectLabel = safeName(subjectId);

    if isempty(opts.outputName)
        opts.outputName = [subjectLabel '_T1.nii'];
    end

    if isempty(opts.dicomDir)
        opts.dicomDir = acsSubjectPath(subjectId, opts.seriesKey, ...
            'configFile', opts.configFile);
    end

    if isempty(opts.outputDir)
        opts.outputDir = acsSubjectPath(subjectId, 'anatomyWork', ...
            'configFile', opts.configFile);
    end

    if ~exist(opts.outputDir, 'dir')
        mkdir(opts.outputDir);
    end

    outFile = fullfile(opts.outputDir, opts.outputName);
    reportBase = stripNiftiExtension(opts.outputName);
    reportMat = fullfile(opts.outputDir, [reportBase '_importReport.mat']);
    reportJson = fullfile(opts.outputDir, [reportBase '_importReport.json']);

    logMsg(opts, 'Subject: %s', subjectId);
    logMsg(opts, 'DICOM folder: %s', opts.dicomDir);
    logMsg(opts, 'Output NIfTI: %s', outFile);

    if exist(outFile, 'file') && ~opts.force
        logMsg(opts, 'Existing NIfTI found; skipping conversion. Use force=true to rerun.');
        orientationSource = findOrientationSource(opts.outputDir, '');
        report = buildExistingReport(subjectId, opts, outFile, orientationSource);
        report.reportMat = reportMat;
        report.reportJson = reportJson;
        qcFiles = maybeMakeQcFigures(outFile, opts.outputDir, opts, orientationSource);
        report.qcFiles = qcFiles;
        save(reportMat, 'report');
        writeJsonReport(reportJson, report);
        out = report;
        return;
    end

    validateDicomDir(opts.dicomDir);
    dicomFiles = listDicomFiles(opts.dicomDir);
    logMsg(opts, 'Found %d DICOM files.', numel(dicomFiles));

    conversionDir = fullfile(opts.outputDir, 'spm_dicom_convert');
    if ~exist(conversionDir, 'dir')
        mkdir(conversionDir);
    end

    spmOut = convertWithSpm(dicomFiles, conversionDir, opts);
    niftiFiles = usableNiftiFiles(spmOut.files);
    if isempty(niftiFiles)
        error('acsImportDicomAnatomy:NoNiftiCreated', ...
            'SPM did not create any NIfTI files from %s.', opts.dicomDir);
    end

    canonicalSource = chooseCanonicalNifti(niftiFiles);
    if ~strcmpi(canonicalSource, outFile)
        copyfile(canonicalSource, outFile, 'f');
    end

    report = buildReport(subjectId, opts, dicomFiles, conversionDir, ...
        spmOut.files, niftiFiles, canonicalSource, outFile);
    report.reportMat = reportMat;
    report.reportJson = reportJson;

    orientationSource = findOrientationSource(opts.outputDir, canonicalSource);
    report.nifti = niftiSummary(outFile, orientationSource);
    qcFiles = maybeMakeQcFigures(outFile, opts.outputDir, opts, orientationSource);
    report.qcFiles = qcFiles;

    save(reportMat, 'report');
    writeJsonReport(reportJson, report);

    logMsg(opts, 'Saved import report: %s', reportMat);
    if ~isempty(qcFiles)
        logMsg(opts, 'Saved %d QC figure(s).', numel(qcFiles));
    end

    out = report;
end

function opts = parseInputs(varargin)
    p = inputParser;
    p.FunctionName = 'acsImportDicomAnatomy';
    addParameter(p, 'seriesKey', 'mprageInitial', @(x) ischar(x) || isstring(x));
    addParameter(p, 'dicomDir', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'outputDir', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'outputName', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'configFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'force', false, @isBoolLike);
    addParameter(p, 'verbose', false, @isBoolLike);
    addParameter(p, 'showFigures', false, @isBoolLike);
    addParameter(p, 'saveFigures', false, @isBoolLike);
    addParameter(p, 'qcTitleMode', 'compact', @(x) ischar(x) || isstring(x));
    addParameter(p, 'figureExportOptions', struct(), @(x) isempty(x) || isstruct(x));
    addParameter(p, 'figureStyle', 'qc', @(x) ischar(x) || isstring(x));
    addParameter(p, 'figureFormats', {'png'}, @isFormatList);
    addParameter(p, 'figureWidthCm', [], @(x) isempty(x) || isPositiveScalar(x));
    addParameter(p, 'figureHeightCm', [], @(x) isempty(x) || isPositiveScalar(x));
    addParameter(p, 'figureFontSize', [], @(x) isempty(x) || isPositiveScalar(x));
    addParameter(p, 'figureResolution', [], @(x) isempty(x) || isPositiveScalar(x));
    addParameter(p, 'posterText', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'posterLabel', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'writePosterTex', false, @isBoolLike);
    addParameter(p, 'posterTexRootDir', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'posterTexGraphicsWidth', '\linewidth', @(x) ischar(x) || isstring(x));
    addParameter(p, 'posterTexTextSize', '\large', @(x) ischar(x) || isstring(x));
    parse(p, varargin{:});

    usingDefaults = p.UsingDefaults;
    opts = p.Results;
    charFields = {'seriesKey', 'dicomDir', 'outputDir', 'outputName', ...
        'configFile', 'qcTitleMode', 'figureStyle', 'posterText', ...
        'posterLabel', 'posterTexRootDir', 'posterTexGraphicsWidth', ...
        'posterTexTextSize'};
    for i = 1:numel(charFields)
        f = charFields{i};
        opts.(f) = char(opts.(f));
    end
    opts.force = logical(opts.force);
    opts.verbose = logical(opts.verbose);
    opts.showFigures = logical(opts.showFigures);
    opts.saveFigures = logical(opts.saveFigures);
    opts.writePosterTex = logical(opts.writePosterTex);
    opts.qcTitleMode = normalizeTitleMode(opts.qcTitleMode);
    opts.figureFormats = normalizeFormats(opts.figureFormats);
    opts.figureExportOptions = resolveFigureExportOptions(opts, usingDefaults);
end

function tf = isBoolLike(x)
    tf = (islogical(x) || isnumeric(x)) && isscalar(x);
end

function tf = isPositiveScalar(x)
    tf = isnumeric(x) && isscalar(x) && isfinite(x) && x > 0;
end

function tf = isFormatList(x)
    tf = isempty(x) || ischar(x) || isstring(x) || iscellstr(x);
end

function exportOpts = resolveFigureExportOptions(opts, usingDefaults)
    exportOpts = opts.figureExportOptions;
    if isempty(exportOpts)
        exportOpts = struct();
    end

    exportOpts = setIfExplicit(exportOpts, 'style', opts.figureStyle, ...
        'figureStyle', usingDefaults);
    exportOpts = setIfExplicit(exportOpts, 'formats', opts.figureFormats, ...
        'figureFormats', usingDefaults);
    exportOpts = setIfExplicit(exportOpts, 'widthCm', opts.figureWidthCm, ...
        'figureWidthCm', usingDefaults);
    exportOpts = setIfExplicit(exportOpts, 'heightCm', opts.figureHeightCm, ...
        'figureHeightCm', usingDefaults);
    exportOpts = setIfExplicit(exportOpts, 'fontSize', opts.figureFontSize, ...
        'figureFontSize', usingDefaults);
    exportOpts = setIfExplicit(exportOpts, 'resolution', opts.figureResolution, ...
        'figureResolution', usingDefaults);
    exportOpts = setIfExplicit(exportOpts, 'posterText', opts.posterText, ...
        'posterText', usingDefaults);
    exportOpts = setIfExplicit(exportOpts, 'posterLabel', opts.posterLabel, ...
        'posterLabel', usingDefaults);
    exportOpts = setIfExplicit(exportOpts, 'writeTex', opts.writePosterTex, ...
        'writePosterTex', usingDefaults);
    exportOpts = setIfExplicit(exportOpts, 'texRootDir', opts.posterTexRootDir, ...
        'posterTexRootDir', usingDefaults);
    exportOpts = setIfExplicit(exportOpts, 'texGraphicsWidth', ...
        opts.posterTexGraphicsWidth, 'posterTexGraphicsWidth', usingDefaults);
    exportOpts = setIfExplicit(exportOpts, 'texTextSize', opts.posterTexTextSize, ...
        'posterTexTextSize', usingDefaults);

    if ~isfield(exportOpts, 'style') || isempty(exportOpts.style)
        exportOpts.style = opts.figureStyle;
    end
    if ~isfield(exportOpts, 'formats') || isempty(exportOpts.formats)
        exportOpts.formats = opts.figureFormats;
    end
end

function S = setIfExplicit(S, fieldName, value, optionName, usingDefaults)
    if ~any(strcmp(optionName, usingDefaults))
        S.(fieldName) = value;
    end
end

function validateDicomDir(dicomDir)
    if exist(dicomDir, 'dir') ~= 7
        error('acsImportDicomAnatomy:DicomDirNotFound', ...
            ['DICOM directory not found or inaccessible:\n%s\n\n' ...
             'Check local.paths.json or pass ''dicomDir'' explicitly.'], dicomDir);
    end
end

function files = listDicomFiles(dicomDir)
    d = dir(fullfile(dicomDir, '*.dcm'));
    if isempty(d)
        d = dir(dicomDir);
        d = d(~[d.isdir]);
    end
    if isempty(d)
        error('acsImportDicomAnatomy:NoDicomFiles', ...
            'No DICOM-like files found in %s.', dicomDir);
    end

    files = arrayfun(@(x) fullfile(x.folder, x.name), d, 'UniformOutput', false);
    files = sort(files(:));
end

function spmOut = convertWithSpm(dicomFiles, conversionDir, opts)
    repoRoot = fileparts(fileparts(mfilename('fullpath')));
    spmDir = fullfile(repoRoot, 'lib', 'spm12');
    if exist(spmDir, 'dir') ~= 7
        error('acsImportDicomAnatomy:MissingSpm', 'SPM folder not found: %s', spmDir);
    end
    addpath(spmDir);

    logMsg(opts, 'Reading DICOM headers with SPM...');
    hdr = spm_dicom_headers(char(dicomFiles));
    if isempty(hdr)
        error('acsImportDicomAnatomy:NoReadableDicomHeaders', ...
            'SPM could not read DICOM headers from %s.', fileparts(dicomFiles{1}));
    end

    logMsg(opts, 'Converting DICOM series with SPM...');
    spmOut = spm_dicom_convert(hdr, 'all', 'flat', 'nii', conversionDir, true);
end

function niftiFiles = usableNiftiFiles(files)
    if isempty(files)
        niftiFiles = {};
        return;
    end
    files = files(:);
    isUsable = false(size(files));
    for i = 1:numel(files)
        f = files{i};
        isUsable(i) = ~isempty(f) && exist(f, 'file') == 2 && endsWith(lower(f), '.nii');
    end
    niftiFiles = files(isUsable);
end

function niftiFile = chooseCanonicalNifti(niftiFiles)
    if numel(niftiFiles) == 1
        niftiFile = niftiFiles{1};
        return;
    end

    sizes = zeros(numel(niftiFiles), 1);
    for i = 1:numel(niftiFiles)
        d = dir(niftiFiles{i});
        sizes(i) = d.bytes;
    end
    [~, ind] = max(sizes);
    niftiFile = niftiFiles{ind};
end

function report = buildExistingReport(subjectId, opts, outFile, orientationSource)
    report = struct();
    report.subjectId = subjectId;
    report.seriesKey = opts.seriesKey;
    report.dicomDir = opts.dicomDir;
    report.outputDir = opts.outputDir;
    report.outputFile = outFile;
    report.wasConverted = false;
    report.createdOn = char(datetime('now'));
    report.nifti = niftiSummary(outFile, orientationSource);
end

function report = buildReport(subjectId, opts, dicomFiles, conversionDir, ...
        spmFiles, niftiFiles, canonicalSource, outFile)
    report = struct();
    report.subjectId = subjectId;
    report.seriesKey = opts.seriesKey;
    report.dicomDir = opts.dicomDir;
    report.outputDir = opts.outputDir;
    report.outputFile = outFile;
    report.wasConverted = true;
    report.createdOn = char(datetime('now'));
    report.dicomCount = numel(dicomFiles);
    report.firstDicomFiles = dicomFiles(1:min(5, numel(dicomFiles)));
    report.conversionDir = conversionDir;
    report.spmFiles = spmFiles(:);
    report.niftiFiles = niftiFiles(:);
    report.canonicalSource = canonicalSource;
    report.nifti = niftiSummary(outFile, struct());
end

function summary = niftiSummary(niftiFile, orientationSource)
    if nargin < 2
        orientationSource = struct();
    end

    info = niftiinfo(niftiFile);
    summary = struct();
    summary.file = niftiFile;
    summary.imageSize = info.ImageSize;
    summary.pixelDimensions = info.PixelDimensions;
    summary.datatype = info.Datatype;
    if isfield(info, 'Transform') && isfield(info.Transform, 'T')
        summary.transform = info.Transform.T;
    else
        summary.transform = [];
    end
    if isfield(info, 'SpaceUnits')
        summary.spaceUnits = info.SpaceUnits;
    else
        summary.spaceUnits = '';
    end
    if isfield(info, 'TimeUnits')
        summary.timeUnits = info.TimeUnits;
    else
        summary.timeUnits = '';
    end
    summary.orientation = orientationSummary(info, orientationSource);
end

function qcFiles = maybeMakeQcFigures(niftiFile, outputDir, opts, orientationSource)
    qcFiles = {};
    if ~opts.showFigures && ~opts.saveFigures
        return;
    end
    if nargin < 4
        orientationSource = struct();
    end

    info = niftiinfo(niftiFile);
    V = niftiread(niftiFile);
    if ndims(V) > 3
        V = V(:, :, :, 1);
    end
    V = double(V);

    figVisible = 'off';
    if opts.showFigures
        figVisible = 'on';
    end

    fig = figure('Name', 'DICOM import QC', 'Color', 'w', 'Visible', figVisible);
    tiledlayout(fig, 1, 3, 'Padding', 'compact', 'TileSpacing', 'compact');

    dims = size(V);
    if numel(dims) < 3
        dims(3) = 1;
    end
    sliceInd = max(1, round(dims ./ 2));
    clim = robustClim(V);
    orient = orientationSummary(info, orientationSource);
    planeInfo = orientationPlanes(orient);

    for i = 1:numel(planeInfo)
        nexttile;
        dimToFix = planeInfo(i).voxelDim;
        idx = sliceInd(dimToFix);
        imagesc(rot90(extractSlice(V, dimToFix, idx)));
        axis image off;
        colormap gray;
        caxis(clim);
        if strcmp(opts.qcTitleMode, 'verbose')
            title(sprintf('%s | dim %d = %d | normal world %s', ...
                planeInfo(i).label, dimToFix, idx, planeInfo(i).worldAxis), ...
                'Interpreter', 'none');
        else
            title(lower(planeInfo(i).label), ...
                'Interpreter', 'none', 'FontWeight', 'bold');
        end
    end

    if strcmp(opts.qcTitleMode, 'verbose')
        titleText = sprintf('%s | size [%s] | pixdim [%s] | axes %s | source %s', ...
            niftiFile, num2str(info.ImageSize), num2str(info.PixelDimensions), ...
            orient.voxelAxisDescription, orient.source);
    else
        titleText = sprintf('DICOM import QC: %s', ...
            stripNiftiExtension(getFileName(niftiFile)));
    end
    sgtitle(titleText, 'Interpreter', 'none', 'FontWeight', 'bold');

    if opts.saveFigures
        qcDir = fullfile(outputDir, 'qc');
        if ~exist(qcDir, 'dir')
            mkdir(qcDir);
        end
        qcStem = fullfile(qcDir, ...
            [stripNiftiExtension(getFileName(niftiFile)) '_orthogonalSlices']);
        qcFiles = acsExportFigure(fig, qcStem, opts.figureExportOptions);
    end

    if ~opts.showFigures
        close(fig);
    end
end

function orient = orientationSummary(info, orientationSource)
    if nargin < 2
        orientationSource = struct();
    end

    [T, hasAffine] = niftiAffine(info);
    if hasAffine
        voxelDirections = T(1:3, 1:3);
        source = 'niftiTransform';
        sourceFile = '';
        coordinateFrame = 'NIfTI world';
    else
        [voxelDirections, sourceFile] = dicomVoxelDirections(orientationSource);
        if isempty(voxelDirections)
            voxelDirections = eye(3);
            source = 'rawVoxelFallback';
            sourceFile = '';
            coordinateFrame = 'raw voxel axes';
        else
            source = 'dicomImageOrientationPatient';
            coordinateFrame = 'DICOM patient LPS';
        end
    end

    mapping = axisMappingFromVoxelDirections(voxelDirections);

    orient = struct();
    orient.affine = T;
    orient.source = source;
    orient.sourceFile = sourceFile;
    orient.coordinateFrame = coordinateFrame;
    orient.voxelDirections = voxelDirections;
    orient.voxelAxisWorldAxis = mapping.voxelAxisWorldAxis;
    orient.voxelAxisSign = mapping.voxelAxisSign;
    orient.worldAxisVoxelDim = mapping.worldAxisVoxelDim;
    orient.worldAxisLabels = {'world X', 'world Y', 'world Z'};
    orient.voxelAxisDescription = mapping.description;
end

function [T, hasAffine] = niftiAffine(info)
    hasAffine = false;
    T = [];
    if isfield(info, 'Transform') && isfield(info.Transform, 'T') && ~isempty(info.Transform.T)
        T = info.Transform.T;
        hasAffine = true;
    end
end

function source = findOrientationSource(outputDir, canonicalSource)
    source = struct();
    source.spmJsonFile = '';
    source.dicom = [];

    candidates = cell(0, 1);
    if nargin >= 2 && ~isempty(canonicalSource)
        sourceJson = replaceFileExtension(canonicalSource, '.json');
        if exist(sourceJson, 'file') == 2
            candidates{end + 1, 1} = sourceJson; %#ok<AGROW>
        end
    end

    conversionDir = fullfile(outputDir, 'spm_dicom_convert');
    if exist(conversionDir, 'dir') == 7
        d = dir(fullfile(conversionDir, '*.json'));
        [~, order] = sort([d.datenum], 'descend');
        d = d(order);
        for i = 1:numel(d)
            candidates{end + 1, 1} = fullfile(d(i).folder, d(i).name); %#ok<AGROW>
        end
    end

    for i = 1:numel(candidates)
        dicom = readSpmDicomJson(candidates{i});
        if ~isempty(dicom)
            source.spmJsonFile = candidates{i};
            source.dicom = dicom;
            return;
        end
    end
end

function dicom = readSpmDicomJson(jsonFile)
    dicom = [];
    try
        raw = jsondecode(fileread(jsonFile));
    catch
        return;
    end

    if ~isfield(raw, 'acqpar') || isempty(raw.acqpar)
        return;
    end

    acq = raw.acqpar;
    if numel(acq) > 1
        acq = acq(1);
    end
    if ~isfield(acq, 'ImageOrientationPatient')
        return;
    end

    iop = double(acq.ImageOrientationPatient(:))';
    if numel(iop) < 6
        return;
    end

    rowDir = normalizeVector(iop(1:3));
    colDir = normalizeVector(iop(4:6));
    sliceDir = normalizeVector(cross(rowDir, colDir));
    if isempty(rowDir) || isempty(colDir) || isempty(sliceDir)
        return;
    end

    dicom = struct();
    dicom.imageOrientationPatient = iop(1:6);
    dicom.rowDirection = rowDir;
    dicom.columnDirection = colDir;
    dicom.sliceDirection = sliceDir;
    if isfield(acq, 'ImagePositionPatient')
        dicom.imagePositionPatient = double(acq.ImagePositionPatient(:))';
    end
    if isfield(acq, 'PixelSpacing')
        dicom.pixelSpacing = double(acq.PixelSpacing(:))';
    end
    if isfield(acq, 'SliceThickness')
        dicom.sliceThickness = double(acq.SliceThickness);
    end
    if isfield(acq, 'SeriesDescription')
        dicom.seriesDescription = char(acq.SeriesDescription);
    end
end

function [voxelDirections, sourceFile] = dicomVoxelDirections(orientationSource)
    voxelDirections = [];
    sourceFile = '';
    if ~isstruct(orientationSource) || ~isfield(orientationSource, 'dicom') || ...
            isempty(orientationSource.dicom)
        return;
    end

    D = orientationSource.dicom;
    if ~isfield(D, 'columnDirection') || ~isfield(D, 'rowDirection') || ...
            ~isfield(D, 'sliceDirection')
        return;
    end

    % SPM's NIfTI array from this DICOM path follows DICOM column, row,
    % slice order for raw voxel dimensions.
    voxelDirections = [
        D.columnDirection
        D.rowDirection
        D.sliceDirection
    ];

    if isfield(orientationSource, 'spmJsonFile')
        sourceFile = orientationSource.spmJsonFile;
    end
end

function mapping = axisMappingFromVoxelDirections(voxelDirections)
    axisNames = {'X', 'Y', 'Z'};
    voxelAxisWorldAxis = zeros(1, 3);
    voxelAxisSign = zeros(1, 3);

    for dim = 1:3
        [~, worldAxis] = max(abs(voxelDirections(dim, :)));
        voxelAxisWorldAxis(dim) = worldAxis;
        voxelAxisSign(dim) = sign(voxelDirections(dim, worldAxis));
        if voxelAxisSign(dim) == 0
            voxelAxisSign(dim) = 1;
        end
    end

    worldAxisVoxelDim = zeros(1, 3);
    for worldAxis = 1:3
        [~, voxelDim] = max(abs(voxelDirections(:, worldAxis)));
        worldAxisVoxelDim(worldAxis) = voxelDim;
    end

    descParts = cell(1, 3);
    for dim = 1:3
        signStr = '+';
        if voxelAxisSign(dim) < 0
            signStr = '-';
        end
        descParts{dim} = sprintf('dim%d->%s%s', dim, signStr, ...
            axisNames{voxelAxisWorldAxis(dim)});
    end

    mapping = struct();
    mapping.voxelAxisWorldAxis = voxelAxisWorldAxis;
    mapping.voxelAxisSign = voxelAxisSign;
    mapping.worldAxisVoxelDim = worldAxisVoxelDim;
    mapping.description = strjoin(descParts, ', ');
end

function v = normalizeVector(v)
    v = double(v(:))';
    n = norm(v);
    if numel(v) ~= 3 || n == 0 || any(~isfinite(v))
        v = [];
        return;
    end
    v = v ./ n;
end

function planeInfo = orientationPlanes(orient)
    labels = {'Sagittal', 'Coronal', 'Axial'};
    worldAxes = {'X', 'Y', 'Z'};
    planeInfo = repmat(struct('label', '', 'worldAxis', '', 'voxelDim', 1), 1, 3);

    for worldAxis = 1:3
        dimToFix = orient.worldAxisVoxelDim(worldAxis);
        if isempty(dimToFix) || dimToFix < 1 || dimToFix > 3
            dimToFix = worldAxis;
        end
        planeInfo(worldAxis).label = labels{worldAxis};
        planeInfo(worldAxis).worldAxis = worldAxes{worldAxis};
        planeInfo(worldAxis).voxelDim = dimToFix;
    end
end

function img = extractSlice(V, dimToFix, idx)
    switch dimToFix
        case 1
            img = squeeze(V(idx, :, :));
        case 2
            img = squeeze(V(:, idx, :));
        case 3
            img = squeeze(V(:, :, idx));
        otherwise
            error('acsImportDicomAnatomy:BadSliceDimension', ...
                'Unsupported slice dimension %d.', dimToFix);
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

function writeJsonReport(reportJson, report)
    jsonReport = report;
    fieldsToTrim = {'spmFiles', 'niftiFiles'};
    for i = 1:numel(fieldsToTrim)
        f = fieldsToTrim{i};
        if isfield(jsonReport, f) && numel(jsonReport.(f)) > 10
            jsonReport.([f 'Count']) = numel(jsonReport.(f));
            values = jsonReport.(f);
            jsonReport.(f) = values(1:10);
        end
    end

    fid = fopen(reportJson, 'w');
    if fid == -1
        error('acsImportDicomAnatomy:CannotWriteJson', ...
            'Could not write report JSON: %s', reportJson);
    end
    cleaner = onCleanup(@() fclose(fid));
    fprintf(fid, '%s', jsonencode(jsonReport, 'PrettyPrint', true));
    clear cleaner;
end

function base = stripNiftiExtension(fileName)
    [~, base, ext] = fileparts(fileName);
    if strcmpi(ext, '.gz')
        [~, base] = fileparts(base);
    end
end

function filePath = replaceFileExtension(filePath, newExt)
    [folder, name] = fileparts(filePath);
    filePath = fullfile(folder, [name newExt]);
end

function name = getFileName(filePath)
    [~, name, ext] = fileparts(filePath);
    name = [name ext];
end

function name = safeName(value)
    name = upper(regexprep(char(value), '[^a-zA-Z0-9_]', '_'));
end

function mode = normalizeTitleMode(mode)
    mode = lower(strtrim(char(mode)));
    validModes = {'compact', 'verbose'};
    if ~any(strcmp(mode, validModes))
        error('acsImportDicomAnatomy:BadTitleMode', ...
            'qcTitleMode must be compact or verbose.');
    end
end

function formats = normalizeFormats(value)
    if isempty(value)
        formats = {};
    elseif ischar(value) || isstring(value)
        formats = cellstr(value);
    else
        formats = value(:);
    end
    for i = 1:numel(formats)
        formats{i} = stripDot(char(formats{i}));
    end
end

function value = stripDot(value)
    if startsWith(value, '.')
        value = value(2:end);
    end
end

function logMsg(opts, varargin)
    if opts.verbose
        fprintf([varargin{1} '\n'], varargin{2:end});
    end
end
