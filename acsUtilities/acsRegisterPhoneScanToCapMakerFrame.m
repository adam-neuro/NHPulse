function out = acsRegisterPhoneScanToCapMakerFrame(phoneCropIn, targetSurfaceIn, varargin)
% ACSREGISTERPHONESCANTOCAPMAKERFRAME Register a phone/LiDAR head scan to capMaker space.
%
% out = acsRegisterPhoneScanToCapMakerFrame(phoneCropIn, targetSurfaceIn)
% reads a cropped phone/EM3D PLY product from acsCropPhoneScanToHead and
% registers it to a capMaker/MRI full-head surface using a rigid, trimmed
% ICP fit. The output transform maps row-vector phone-scan millimeters into
% capMaker print-frame millimeters:
%
%   PcapMaker = Pphone * out.rotation + out.translationMm
%
% The function assumes the phone scan units are already millimeters. A
% placed headpost mesh can optionally be added to the target point cloud so
% the visible post helps registration.
%
% Name-value options:
%   headpostPlacementFile : acsPlanHeadpostPlacement output MAT ['']
%   phoneFiducialsFile    : acsSelectPhoneScanFiducials output MAT ['']
%   modelFiducialsFile    : acsSelectModelFiducials output MAT ['']
%   fiducialLabels        : fiducial labels for initial transform ['auto']
%   initializationMode    : 'auto', 'fiducial', 'geometry', or 'all' ['auto']
%   targetFrame           : 'auto', 'modelFiducials', 'print', or 'preCrop' ['auto']
%   allowTargetFiducialMismatch : permit target mesh != model fiducial mesh [false]
%   outputFile            : saved registration MAT ['']
%   outputTag             : output stem suffix ['phoneScanRegistration']
%   force                 : overwrite existing output [false]
%   transformType         : 'rigid' or 'similarity' ['rigid']
%   useHeadpostTarget     : include placed headpost in ICP target [true]
%   maxSourcePoints       : source sample count for ICP [12000]
%   maxTargetPoints       : target skin sample count for ICP [16000]
%   maxHeadpostPoints     : target headpost sample count [4000]
%   trimFraction          : closest source points used each ICP step [0.70]
%   icpIterations         : ICP iterations per initial transform [45]; use 0 for fiducial-only
%   pcaInitializations    : try PCA signed-axis starts [true]
%   distanceClipMm        : color/histogram clipping distance [20]
%   showFigures           : show QC overlay [true]
%   saveFigures           : save QC PNG [true]
%   verbose               : print summary [true]

    if nargin < 1 || isempty(phoneCropIn)
        error('acsRegisterPhoneScanToCapMakerFrame:MissingPhoneCrop', ...
            'Provide a cropped phone-scan MAT/PLY product.');
    end
    if nargin < 2
        targetSurfaceIn = [];
    end

    opts = parseInputs(varargin{:});
    addLocalDependencies();

    phone = readPhoneCrop(phoneCropIn);
    modelFiducialSource = modelFiducialSurfaceInfo(opts.modelFiducialsFile);
    targetSurfaceIn = reconcileTargetSurfaceWithModelFiducials( ...
        targetSurfaceIn, modelFiducialSource, opts);
    preferredTargetFrame = preferredTargetFrameFromOptions(opts, modelFiducialSource);
    target = readTargetSurface(targetSurfaceIn, phone, preferredTargetFrame);
    headpost = readHeadpostPlacement(opts.headpostPlacementFile);
    opts = resolveOutputFile(opts, phone);

    if exist(opts.outputFile, 'file') == 2 && ~opts.force
        S = load(opts.outputFile);
        out = firstStruct(S);
        reuseBlocker = registrationReuseBlocker(out);
        if isempty(reuseBlocker)
            if opts.showFigures
                out.figure = makeQcFigure(out, opts, 'on');
            end
            if opts.verbose
                fprintf('Phone scan registration already exists; reusing %s\n', opts.outputFile);
            end
            return;
        end
        if opts.verbose
            warning('acsRegisterPhoneScanToCapMakerFrame:BadCachedRegistration', ...
                ['Existing phone scan registration is not reusable (%s). ', ...
                 'Recomputing %s.'], reuseBlocker, opts.outputFile);
        end
    end

    sourcePoints = double(phone.TRhead.Points);
    targetPoints = double(target.TRhead.Points);
    headpostPoints = [];
    if opts.useHeadpostTarget && ~isempty(headpost.TRplaced) && ...
            strcmpi(target.coordinateFrame, 'capMakerPrintMm')
        headpostPoints = double(headpost.TRplaced.Points);
    elseif opts.useHeadpostTarget && ~isempty(headpost.TRplaced) && opts.verbose
        fprintf(['Skipping headpost target points because target surface is ', ...
            'in %s, while the placed headpost is in capMakerPrintMm.\n'], ...
            target.coordinateFrame);
    end

    sourceSample = deterministicSampleRows(sourcePoints, opts.maxSourcePoints);
    targetSample = deterministicSampleRows(targetPoints, opts.maxTargetPoints);
    if ~isempty(headpostPoints)
        targetSample = [targetSample; ...
            deterministicSampleRows(headpostPoints, opts.maxHeadpostPoints)]; %#ok<AGROW>
    end

    fiducialCandidates = fiducialInitialTransformCandidates(opts);
    geometryCandidates = initialTransformCandidates(sourceSample, targetSample, opts);
    [candidates, initializationInfo] = chooseTransformCandidates( ...
        fiducialCandidates, geometryCandidates, opts);
    bestFit = emptyFit();
    haveFiniteFit = false;
    bestTrace = struct();
    candidateFits = repmat(emptyFit(), numel(candidates), 1);
    for i = 1:numel(candidates)
        [fit, trace] = runTrimmedIcp(sourceSample, targetSample, ...
            candidates(i), opts);
        candidateFits(i) = fit;
        if isFiniteScoredFit(fit) && (~haveFiniteFit || fit.score < bestFit.score)
            bestFit = fit;
            bestTrace = trace;
            haveFiniteFit = true;
        end
    end
    if ~haveFiniteFit
        error('acsRegisterPhoneScanToCapMakerFrame:NoFiniteCandidateFit', ...
            ['No phone-scan registration candidate produced a finite fit. ', ...
             'Check paired fiducials and coordinate units before reusing ', ...
             'this registration output. Candidate summaries: %s'], ...
            candidateFitSummary(candidateFits));
    end

    registeredVertices = applyPointTransform(sourcePoints, ...
        bestFit.rotation, bestFit.translationMm, bestFit.scale);
    TRregisteredPhone = triangulation(phone.TRhead.ConnectivityList, ...
        registeredVertices);

    metrics = registrationMetrics(registeredVertices, targetPoints, opts);

    out = struct();
    out.createdOn = char(datetime('now'));
    out.type = 'phoneScanToCapMakerRegistration';
    out.outputFile = opts.outputFile;
    out.qcFigure = '';
    out.source = phone.info;
    out.target = target.info;
    out.headpostTarget = headpost.info;
    out.sourceCoordinateFrame = phone.coordinateFrame;
    out.targetCoordinateFrame = target.coordinateFrame;
    out.unitsAssumption = 'phone scan units treated as millimeters';
    out.transformType = opts.transformType;
    out.scale = bestFit.scale;
    out.rotation = bestFit.rotation;
    out.translationMm = bestFit.translationMm;
    out.rowTransform = rowHomogeneousTransform(bestFit.rotation, ...
        bestFit.translationMm, bestFit.scale);
    out.instructions = ['Apply to row-vector phone scan points as ', ...
        'PcapMaker = Pphone * rotation * scale + translationMm.'];
    out.fit = rmfield(bestFit, {'rotation', 'translationMm'});
    out.initialization = initializationInfo;
    out.candidateFits = stripCandidateFits(candidateFits);
    out.icpTrace = bestTrace;
    out.metrics = metrics;
    out.meshes = struct( ...
        'TRregisteredPhone', TRregisteredPhone, ...
        'TRtargetHead', target.TRhead, ...
        'TRtargetHeadpost', headpost.TRplaced);
    out.options = opts;

    fig = [];
    if opts.showFigures || opts.saveFigures
        figVisible = 'off';
        if opts.showFigures
            figVisible = 'on';
        end
        fig = makeQcFigure(out, opts, figVisible);
        if opts.saveFigures
            qcFile = fullfile(fileparts(opts.outputFile), 'qc', ...
                [stripMatExtension(getFileName(opts.outputFile)) '_qc.png']);
            ensureDir(fileparts(qcFile));
            saveQcFigure(fig, qcFile);
            out.qcFigure = qcFile;
        end
        if ~opts.showFigures && isgraphics(fig)
            close(fig);
            fig = [];
        end
    end
    out.figure = fig;

    outForSave = out;
    if isfield(outForSave, 'figure')
        outForSave = rmfield(outForSave, 'figure');
    end
    ensureDir(fileparts(opts.outputFile));
    save(opts.outputFile, 'out', 'outForSave', 'TRregisteredPhone', '-v7.3');

    if opts.verbose
        printSummary(out);
    end
end

function opts = parseInputs(varargin)
    p = inputParser;
    p.FunctionName = 'acsRegisterPhoneScanToCapMakerFrame';
    addParameter(p, 'headpostPlacementFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'phoneFiducialsFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'modelFiducialsFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'fiducialLabels', {'auto'}, ...
        @(x) iscell(x) || isstring(x) || ischar(x));
    addParameter(p, 'initializationMode', 'auto', @isInitializationMode);
    addParameter(p, 'targetFrame', 'auto', @isTargetFrameMode);
    addParameter(p, 'allowTargetFiducialMismatch', false, @isBoolLike);
    addParameter(p, 'outputFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'outputTag', 'phoneScanRegistration', @(x) ischar(x) || isstring(x));
    addParameter(p, 'force', false, @isBoolLike);
    addParameter(p, 'transformType', 'rigid', @(x) ischar(x) || isstring(x));
    addParameter(p, 'useHeadpostTarget', true, @isBoolLike);
    addParameter(p, 'maxSourcePoints', 12000, @isPositiveScalar);
    addParameter(p, 'maxTargetPoints', 16000, @isPositiveScalar);
    addParameter(p, 'maxHeadpostPoints', 4000, @isPositiveScalar);
    addParameter(p, 'trimFraction', 0.70, @isUnitOpenScalar);
    addParameter(p, 'icpIterations', 45, @isNonnegativeScalar);
    addParameter(p, 'pcaInitializations', true, @isBoolLike);
    addParameter(p, 'distanceClipMm', 20, @isPositiveScalar);
    addParameter(p, 'showFigures', true, @isBoolLike);
    addParameter(p, 'saveFigures', true, @isBoolLike);
    addParameter(p, 'verbose', true, @isBoolLike);
    parse(p, varargin{:});

    opts = p.Results;
    opts.headpostPlacementFile = expandUserPath(char(opts.headpostPlacementFile));
    opts.phoneFiducialsFile = expandUserPath(char(opts.phoneFiducialsFile));
    opts.modelFiducialsFile = expandUserPath(char(opts.modelFiducialsFile));
    opts.fiducialLabels = normalizeLabelCell(opts.fiducialLabels);
    opts.initializationMode = normalizeInitializationMode(opts.initializationMode);
    opts.targetFrame = normalizeTargetFrameMode(opts.targetFrame);
    opts.allowTargetFiducialMismatch = logical(opts.allowTargetFiducialMismatch);
    opts.outputFile = expandUserPath(char(opts.outputFile));
    opts.outputTag = safeName(char(opts.outputTag));
    opts.force = logical(opts.force);
    opts.transformType = normalizeTransformType(opts.transformType);
    opts.useHeadpostTarget = logical(opts.useHeadpostTarget);
    opts.maxSourcePoints = round(double(opts.maxSourcePoints));
    opts.maxTargetPoints = round(double(opts.maxTargetPoints));
    opts.maxHeadpostPoints = round(double(opts.maxHeadpostPoints));
    opts.trimFraction = double(opts.trimFraction);
    opts.icpIterations = round(double(opts.icpIterations));
    opts.pcaInitializations = logical(opts.pcaInitializations);
    opts.distanceClipMm = double(opts.distanceClipMm);
    opts.showFigures = logical(opts.showFigures);
    opts.saveFigures = logical(opts.saveFigures);
    opts.verbose = logical(opts.verbose);
end

function reason = registrationReuseBlocker(out)
    reason = '';
    if ~isstruct(out)
        reason = 'saved output is not a struct';
        return;
    end
    if ~isfield(out, 'rotation') || ~all(isfinite(double(out.rotation(:))))
        reason = 'rotation is missing or non-finite';
        return;
    end
    if ~isfield(out, 'translationMm') || ...
            ~all(isfinite(double(out.translationMm(:))))
        reason = 'translation is missing or non-finite';
        return;
    end
    if ~isfield(out, 'scale') || ~isfinite(double(out.scale))
        reason = 'scale is missing or non-finite';
        return;
    end
    if ~isfield(out, 'fit') || ~isstruct(out.fit)
        reason = 'fit summary is missing';
        return;
    end
    if ~isfield(out.fit, 'initialization') || isempty(out.fit.initialization)
        reason = 'fit initialization label is empty';
        return;
    end
    if ~isfield(out.fit, 'score') || ~isfinite(double(out.fit.score))
        reason = 'fit score is non-finite';
        return;
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

function tf = isUnitOpenScalar(x)
    tf = isnumeric(x) && isscalar(x) && isfinite(x) && x > 0 && x <= 1;
end

function tf = isInitializationMode(x)
    if ~(ischar(x) || isstring(x))
        tf = false;
        return;
    end
    tf = any(strcmpi(char(x), {'auto', 'fiducial', 'fiducials', ...
        'landmark', 'landmarks', 'geometry', 'pca', 'all'}));
end

function mode = normalizeInitializationMode(value)
    value = lower(strtrim(char(value)));
    switch value
        case 'auto'
            mode = 'auto';
        case {'fiducial', 'fiducials', 'landmark', 'landmarks'}
            mode = 'fiducial';
        case {'geometry', 'pca'}
            mode = 'geometry';
        case 'all'
            mode = 'all';
        otherwise
            error('acsRegisterPhoneScanToCapMakerFrame:BadInitializationMode', ...
                'initializationMode must be auto, fiducial, geometry, or all.');
    end
end

function tf = isTargetFrameMode(x)
    if ~(ischar(x) || isstring(x))
        tf = false;
        return;
    end
    tf = any(strcmpi(char(x), {'auto', 'modelFiducials', ...
        'model', 'fiducials', 'print', 'capMakerPrintMm', ...
        'preCrop', 'stable', 'capMakerPreCropWorldMm'}));
end

function mode = normalizeTargetFrameMode(value)
    value = lower(strtrim(char(value)));
    switch value
        case 'auto'
            mode = 'auto';
        case {'modelfiducials', 'model', 'fiducials'}
            mode = 'modelFiducials';
        case {'print', 'capmakerprintmm'}
            mode = 'print';
        case {'precrop', 'stable', 'capmakerprecropworldmm'}
            mode = 'preCrop';
        otherwise
            error('acsRegisterPhoneScanToCapMakerFrame:BadTargetFrame', ...
                'targetFrame must be auto, modelFiducials, print, or preCrop.');
    end
end

function transformType = normalizeTransformType(value)
    value = lower(strtrim(char(value)));
    switch value
        case {'rigid', 'euclidean'}
            transformType = 'rigid';
        case {'similarity', 'scaledrigid', 'scaled'}
            transformType = 'similarity';
        otherwise
            error('acsRegisterPhoneScanToCapMakerFrame:BadTransformType', ...
                'transformType must be ''rigid'' or ''similarity''.');
    end
end

function addLocalDependencies()
    repoRoot = fileparts(fileparts(mfilename('fullpath')));
    addpath(repoRoot);
    addpath(fullfile(repoRoot, 'acsUtilities'));
    addpath(fullfile(repoRoot, 'capMaker', 'core'));
    addpath(fullfile(repoRoot, 'capMaker', 'geometry'));
end

function opts = resolveOutputFile(opts, phone)
    if ~isempty(opts.outputFile)
        return;
    end
    sourceFile = getOptionalField(phone.info, 'file', '');
    if isempty(sourceFile)
        folder = pwd;
        stem = 'phoneScan';
    else
        folder = fileparts(sourceFile);
        stem = stripMatExtension(getFileName(sourceFile));
    end
    opts.outputFile = fullfile(folder, [stem '_' opts.outputTag '.mat']);
end

function phone = readPhoneCrop(value)
    if isstruct(value)
        S = value;
        infoFile = '';
    else
        fileName = expandUserPath(char(value));
        if exist(fileName, 'file') ~= 2
            error('acsRegisterPhoneScanToCapMakerFrame:PhoneCropNotFound', ...
                'Phone crop file not found: %s', fileName);
        end
        [~, ~, ext] = fileparts(fileName);
        switch lower(ext)
            case '.mat'
                M = load(fileName);
                S = firstStruct(M);
            case '.ply'
                ply = readAsciiPlyMesh(fileName);
                S = struct('vertices', ply.vertices, 'faces', ply.faces, ...
                    'coordinateFrame', 'phoneScanRawMm');
            otherwise
                error('acsRegisterPhoneScanToCapMakerFrame:BadPhoneCropFile', ...
                    'Phone crop input must be a MAT or ASCII PLY file.');
        end
        infoFile = fileName;
    end

    if isfield(S, 'TRhead') && ~isempty(S.TRhead)
        TRhead = ensureTriangulation(S.TRhead);
    elseif isfield(S, 'vertices') && isfield(S, 'faces')
        TRhead = triangulation(double(S.faces), double(S.vertices));
    elseif isfield(S, 'pointCloudMm') && isfield(S, 'faces')
        TRhead = triangulation(double(S.faces), double(S.pointCloudMm));
    else
        error('acsRegisterPhoneScanToCapMakerFrame:BadPhoneCropStruct', ...
            'Phone crop input must contain TRhead or vertices/faces.');
    end

    frame = char(getOptionalField(S, 'coordinateFrame', 'phoneScanRawMm'));
    phone = struct();
    phone.TRhead = TRhead;
    phone.coordinateFrame = frame;
    phone.info = struct( ...
        'file', infoFile, ...
        'type', char(getOptionalField(S, 'type', 'phoneScanHeadCrop')), ...
        'coordinateFrame', frame, ...
        'nVertices', size(TRhead.Points, 1), ...
        'nFaces', size(TRhead.ConnectivityList, 1));
end

function preferredFrame = preferredTargetFrameFromOptions(opts, modelFiducialSource)
    preferredFrame = opts.targetFrame;
    if strcmp(preferredFrame, 'modelFiducials')
        preferredFrame = modelFiducialSource.preferredFrame;
    elseif strcmp(preferredFrame, 'auto')
        if ~isempty(modelFiducialSource.file)
            preferredFrame = modelFiducialSource.preferredFrame;
        else
            preferredFrame = 'print';
        end
    end
end

function info = modelFiducialSurfaceInfo(fileName)
    info = struct('file', '', 'coordinateFrame', '', ...
        'preferredFrame', 'print', 'fiducialsFile', fileName);
    if isempty(fileName) || exist(fileName, 'file') ~= 2
        return;
    end
    try
        S = load(fileName);
        C = firstStruct(S);
        if isfield(C, 'source') && isstruct(C.source)
            if isfield(C.source, 'file') && ~isempty(C.source.file)
                info.file = expandUserPath(char(C.source.file));
            end
            if isempty(info.file) && isfield(C.source, 'layoutFile') && ...
                    ~isempty(C.source.layoutFile)
                info.file = expandUserPath(char(C.source.layoutFile));
            end
            if isempty(info.coordinateFrame) && ...
                    isfield(C.source, 'coordinateFrame') && ...
                    ~isempty(C.source.coordinateFrame)
                info.coordinateFrame = char(C.source.coordinateFrame);
            end
        end
        if isfield(C, 'coordinateFrame') && ~isempty(C.coordinateFrame)
            info.coordinateFrame = char(C.coordinateFrame);
        end
        info.preferredFrame = targetFrameFromCoordinateFrame(info.coordinateFrame);
    catch
        info = struct('file', '', 'coordinateFrame', '', ...
            'preferredFrame', 'print', 'fiducialsFile', fileName);
    end
end

function frame = targetFrameFromCoordinateFrame(coordinateFrame)
    value = lower(strtrim(char(coordinateFrame)));
    switch value
        case 'capmakerprecropworldmm'
            frame = 'preCrop';
        case 'capmakerprintmm'
            frame = 'print';
        otherwise
            frame = 'print';
    end
end

function targetSurfaceIn = reconcileTargetSurfaceWithModelFiducials( ...
        targetSurfaceIn, modelFiducialSource, opts)
    if isempty(modelFiducialSource.file)
        return;
    end
    if isempty(targetSurfaceIn)
        targetSurfaceIn = modelFiducialSource.file;
        return;
    end

    if ischar(targetSurfaceIn) || isstring(targetSurfaceIn)
        targetFile = expandUserPath(char(targetSurfaceIn));
        if sameFilePath(targetFile, modelFiducialSource.file)
            return;
        end
        mismatchText = sprintf([ ...
            'Model fiducials were picked on:\n  %s\n\n', ...
            'but targetSurfaceIn was:\n  %s\n\n', ...
            'Pick model fiducials on that target surface, or call with ', ...
            'targetSurfaceIn=[] so the fiducial source mesh is used.'], ...
            modelFiducialSource.file, targetFile);
    else
        mismatchText = sprintf([ ...
            'Model fiducials were picked on:\n  %s\n\n', ...
            'but targetSurfaceIn was supplied as an in-memory object whose ', ...
            'provenance cannot be verified. Use the fiducial source mesh ', ...
            'or set allowTargetFiducialMismatch=true explicitly.'], ...
            modelFiducialSource.file);
    end

    if opts.allowTargetFiducialMismatch
        warning('acsRegisterPhoneScanToCapMakerFrame:TargetFiducialMismatch', ...
            '%s', mismatchText);
    else
        error('acsRegisterPhoneScanToCapMakerFrame:TargetFiducialMismatch', ...
            '%s', mismatchText);
    end
end

function tf = sameFilePath(a, b)
    tf = strcmpi(normalizePath(a), normalizePath(b));
end

function value = normalizePath(value)
    value = expandUserPath(char(value));
    try
        if exist(value, 'file') == 2 || exist(value, 'dir') == 7
            value = char(java.io.File(value).getCanonicalPath());
        end
    catch
        value = char(value);
    end
    value = lower(strrep(value, '/', filesep));
end

function target = readTargetSurface(value, phone, preferredFrame)
    if nargin < 1 || isempty(value)
        value = defaultTargetSurfaceFile(phone);
    end
    if nargin < 3 || isempty(preferredFrame)
        preferredFrame = 'print';
    end

    if isa(value, 'triangulation')
        TRhead = value;
        sourceFile = '';
        frame = 'capMakerPrintMm';
    elseif isstruct(value)
        [TRhead, frame] = targetSurfaceFromStruct(value, preferredFrame);
        sourceFile = '';
    else
        sourceFile = expandUserPath(char(value));
        if exist(sourceFile, 'file') ~= 2
            error('acsRegisterPhoneScanToCapMakerFrame:TargetNotFound', ...
                'Target surface file not found: %s', sourceFile);
        end
        S = load(sourceFile);
        [TRhead, frame] = targetSurfaceFromStruct(S, preferredFrame);
    end

    target = struct();
    target.TRhead = ensureTriangulation(TRhead);
    target.coordinateFrame = frame;
    target.info = struct( ...
        'file', sourceFile, ...
        'coordinateFrame', frame, ...
        'preferredFrame', preferredFrame, ...
        'nVertices', size(target.TRhead.Points, 1), ...
        'nFaces', size(target.TRhead.ConnectivityList, 1));
end

function fileName = defaultTargetSurfaceFile(phone)
    sourceFile = getOptionalField(phone.info, 'file', '');
    folder = '';
    if ~isempty(sourceFile)
        folder = fileparts(sourceFile);
    end
    candidates = {};
    if ~isempty(folder) && exist(folder, 'dir') == 7
        candidates = [candidates; listMatchingFiles(folder, '*_skinMesh_scalpTraceWarp*.mat')]; %#ok<AGROW>
        candidates = [candidates; listMatchingFiles(folder, '*_fullHeadSkinMesh.mat')]; %#ok<AGROW>
        candidates = [candidates; listMatchingFiles(folder, '*_skinMesh.mat')]; %#ok<AGROW>
    end
    candidates = rejectNonSurfaceMatFiles(candidates);
    if isempty(candidates)
        error('acsRegisterPhoneScanToCapMakerFrame:NoDefaultTarget', ...
            ['No target skin cache was supplied, and no *_skinMesh*.mat ', ...
             'candidate was found beside the phone crop.']);
    end
    fileName = candidates{1};
end

function files = rejectNonSurfaceMatFiles(files)
    if isempty(files)
        return;
    end
    keep = true(size(files));
    rejectPieces = {'_report', '_earExclusions', '_cropPlane'};
    for i = 1:numel(files)
        [~, stem] = fileparts(files{i});
        stemLower = lower(stem);
        for j = 1:numel(rejectPieces)
            if ~isempty(strfind(stemLower, lower(rejectPieces{j}))) %#ok<STREMP>
                keep(i) = false;
            end
        end
    end
    files = files(keep);
end

function files = listMatchingFiles(folder, pattern)
    D = dir(fullfile(folder, pattern));
    if isempty(D)
        files = {};
        return;
    end
    [~, order] = sort([D.datenum], 'descend');
    D = D(order);
    files = arrayfun(@(d) fullfile(d.folder, d.name), D, ...
        'UniformOutput', false);
    files = files(:);
end

function [TRhead, frame] = targetSurfaceFromStruct(S, preferredFrame)
    frame = 'capMakerPrintMm';
    if nargin < 2 || isempty(preferredFrame)
        preferredFrame = 'print';
    end

    if strcmpi(preferredFrame, 'preCrop') && ...
            isfield(S, 'TRstableHead') && ~isempty(S.TRstableHead)
        TRhead = ensureTriangulation(S.TRstableHead);
        frame = 'capMakerPreCropWorldMm';
    elseif isfield(S, 'TRfiducialHead') && ~isempty(S.TRfiducialHead)
        TRhead = ensureTriangulation(S.TRfiducialHead);
    elseif isfield(S, 'TRstableHead') && ~isempty(S.TRstableHead)
        TRhead = ensureTriangulation(S.TRstableHead);
        frame = 'capMakerPreCropWorldMm';
    elseif isfield(S, 'TRskin') && ~isempty(S.TRskin)
        TRhead = ensureTriangulation(S.TRskin);
    elseif isfield(S, 'meta') && isstruct(S.meta) && ...
            isfield(S.meta, 'fiducialHead') && ...
            isfield(S.meta.fiducialHead, 'TR') && ...
            ~isempty(S.meta.fiducialHead.TR)
        TRhead = ensureTriangulation(S.meta.fiducialHead.TR);
    elseif isfield(S, 'meta') && isstruct(S.meta) && ...
            isfield(S.meta, 'stableHead') && ...
            isfield(S.meta.stableHead, 'TR') && ...
            ~isempty(S.meta.stableHead.TR)
        TRhead = ensureTriangulation(S.meta.stableHead.TR);
        frame = 'capMakerPreCropWorldMm';
    elseif isfield(S, 'mesh') && isstruct(S.mesh) && ...
            isfield(S.mesh, 'TRfiducialHead') && ~isempty(S.mesh.TRfiducialHead)
        TRhead = ensureTriangulation(S.mesh.TRfiducialHead);
    else
        T = firstStruct(S);
        if ~isequal(T, S)
            [TRhead, frame] = targetSurfaceFromStruct(T, preferredFrame);
        else
            error('acsRegisterPhoneScanToCapMakerFrame:BadTargetSurface', ...
                'Could not find TRfiducialHead, TRstableHead, or TRskin in target input.');
        end
    end
end

function headpost = readHeadpostPlacement(fileName)
    headpost = struct('TRplaced', [], 'info', struct());
    if isempty(fileName)
        headpost.info = struct('file', '', 'available', false);
        return;
    end
    fileName = expandUserPath(char(fileName));
    if exist(fileName, 'file') ~= 2
        warning('acsRegisterPhoneScanToCapMakerFrame:HeadpostNotFound', ...
            'Headpost placement file not found: %s', fileName);
        headpost.info = struct('file', fileName, 'available', false);
        return;
    end
    S = load(fileName);
    C = firstStruct(S);
    TRplaced = [];
    if isfield(C, 'meshes') && isstruct(C.meshes) && ...
            isfield(C.meshes, 'TRplaced') && ~isempty(C.meshes.TRplaced)
        TRplaced = ensureTriangulation(C.meshes.TRplaced);
    elseif isfield(C, 'TRplaced') && ~isempty(C.TRplaced)
        TRplaced = ensureTriangulation(C.TRplaced);
    end
    headpost.TRplaced = TRplaced;
    headpost.info = struct( ...
        'file', fileName, ...
        'available', ~isempty(TRplaced), ...
        'coordinateFrame', char(getOptionalField(C, 'coordinateFrame', 'capMakerPrintMm')));
end

function candidates = fiducialInitialTransformCandidates(opts)
    candidates = emptyTransform();
    if isempty(opts.phoneFiducialsFile) && isempty(opts.modelFiducialsFile)
        return;
    end
    if isempty(opts.phoneFiducialsFile) || isempty(opts.modelFiducialsFile)
        warning('acsRegisterPhoneScanToCapMakerFrame:IncompleteFiducials', ...
            ['phoneFiducialsFile and modelFiducialsFile must both be ', ...
             'provided to seed registration from landmarks. Falling back ', ...
             'to geometry-only initialization.']);
        return;
    end
    if exist(opts.phoneFiducialsFile, 'file') ~= 2
        warning('acsRegisterPhoneScanToCapMakerFrame:PhoneFiducialsNotFound', ...
            'Phone fiducials file not found: %s', opts.phoneFiducialsFile);
        return;
    end
    if exist(opts.modelFiducialsFile, 'file') ~= 2
        warning('acsRegisterPhoneScanToCapMakerFrame:ModelFiducialsNotFound', ...
            'Model fiducials file not found: %s', opts.modelFiducialsFile);
        return;
    end
    try
        reg = acsRegisterPolhemusFiducials(opts.phoneFiducialsFile, ...
            opts.modelFiducialsFile, ...
            'fiducialLabels', opts.fiducialLabels, ...
            'polhemusUnits', 'mm', ...
            'modelUnits', 'mm', ...
            'transformType', opts.transformType, ...
            'verbose', false);
        if ~isFiniteRegistrationSeed(reg)
            warning('acsRegisterPhoneScanToCapMakerFrame:BadFiducialSeed', ...
                ['Fiducial seed was non-finite. This usually means an ', ...
                 'omitted landmark was saved with NaN coordinates or the ', ...
                 'paired fiducials are degenerate.']);
            return;
        end
    catch ME
        warning('acsRegisterPhoneScanToCapMakerFrame:FiducialSeedFailed', ...
            'Could not seed phone registration from fiducials: %s', ME.message);
        return;
    end
    candidates(1).rotation = double(reg.rotation);
    candidates(1).translationMm = double(reg.translationMm);
    candidates(1).scale = double(reg.scale);
    candidates(1).label = sprintf('fiducials_%s_rmse%.3gmm', ...
        char(reg.transformType), double(reg.rmseMm));
end

function candidates = initialTransformCandidates(sourcePoints, targetPoints, opts)
    sourceCenter = medianRowsFinite(sourcePoints);
    targetCenter = medianRowsFinite(targetPoints);
    candidates = emptyTransform();
    candidates(1).rotation = eye(3);
    candidates(1).translationMm = targetCenter - sourceCenter;
    candidates(1).scale = 1;
    candidates(1).label = 'centeredIdentity';

    if ~opts.pcaInitializations
        return;
    end

    Es = pcaFrame(sourcePoints);
    Et = pcaFrame(targetPoints);
    signedPerms = signedPermutationMatrices();
    for i = 1:numel(signedPerms)
        R = Es * signedPerms(i).M * Et';
        if det(R) < 0
            continue;
        end
        candidates(end + 1).rotation = R; %#ok<AGROW>
        candidates(end).translationMm = targetCenter - sourceCenter * R;
        candidates(end).scale = 1;
        candidates(end).label = ['pca_' signedPerms(i).label];
    end
end

function T = emptyTransform()
    T = struct('rotation', {}, 'translationMm', {}, 'scale', {}, 'label', {});
end

function candidates = concatenateTransformCandidates(varargin)
    candidates = emptyTransform();
    for i = 1:nargin
        item = varargin{i};
        if isempty(item)
            continue;
        end
        candidates = [candidates(:); item(:)]; %#ok<AGROW>
    end
end

function [candidates, info] = chooseTransformCandidates( ...
        fiducialCandidates, geometryCandidates, opts)
    haveFiducials = ~isempty(fiducialCandidates);
    haveGeometry = ~isempty(geometryCandidates);
    info = struct( ...
        'requestedMode', opts.initializationMode, ...
        'resolvedMode', '', ...
        'nFiducialCandidates', numel(fiducialCandidates), ...
        'nGeometryCandidates', numel(geometryCandidates), ...
        'note', '');

    switch opts.initializationMode
        case 'fiducial'
            if ~haveFiducials
                error('acsRegisterPhoneScanToCapMakerFrame:NoFiducialCandidates', ...
                    ['initializationMode=''fiducial'' was requested, but no ', ...
                     'usable paired phone/model fiducials were available.']);
            end
            candidates = fiducialCandidates(:);
            info.resolvedMode = 'fiducial';
        case 'geometry'
            if ~haveGeometry
                error('acsRegisterPhoneScanToCapMakerFrame:NoGeometryCandidates', ...
                    'No geometry initialization candidates were available.');
            end
            candidates = geometryCandidates(:);
            info.resolvedMode = 'geometry';
        case 'all'
            candidates = concatenateTransformCandidates( ...
                fiducialCandidates, geometryCandidates);
            info.resolvedMode = 'all';
        otherwise
            if haveFiducials
                candidates = fiducialCandidates(:);
                info.resolvedMode = 'fiducial';
                info.note = ['Fiducial candidates were available, so auto ', ...
                    'mode did not let PCA/geometry candidates compete. Use ', ...
                    'initializationMode=''all'' to compare them.'];
            elseif haveGeometry
                candidates = geometryCandidates(:);
                info.resolvedMode = 'geometry';
            else
                error('acsRegisterPhoneScanToCapMakerFrame:NoCandidates', ...
                    'No initialization candidates were available.');
            end
    end
end

function public = stripCandidateFits(candidateFits)
    public = rmfieldIfPresent(candidateFits, {'rotation', 'translationMm'});
end

function S = rmfieldIfPresent(S, fields)
    for i = 1:numel(fields)
        if isfield(S, fields{i})
            S = rmfield(S, fields{i});
        end
    end
end

function E = pcaFrame(P)
    P = double(P);
    P = P(all(isfinite(P), 2), :);
    C = bsxfun(@minus, P, mean(P, 1));
    [V, D] = eig((C' * C) ./ max(1, size(C, 1) - 1));
    [~, order] = sort(diag(D), 'descend');
    E = V(:, order);
    if det(E) < 0
        E(:, 3) = -E(:, 3);
    end
end

function out = signedPermutationMatrices()
    perms3 = perms(1:3);
    out = struct('M', {}, 'label', {});
    signs = [-1 1];
    for pi = 1:size(perms3, 1)
        P = zeros(3);
        for r = 1:3
            P(r, perms3(pi, r)) = 1;
        end
        for sx = signs
            for sy = signs
                for sz = signs
                    S = diag([sx sy sz]);
                    M = P * S;
                    if det(M) > 0
                        out(end + 1).M = M; %#ok<AGROW>
                        out(end).label = sprintf('p%d%d%d_s%+d%+d%+d', ...
                            perms3(pi, 1), perms3(pi, 2), perms3(pi, 3), ...
                            sx, sy, sz);
                    end
                end
            end
        end
    end
end

function [fit, trace] = runTrimmedIcp(sourcePoints, targetPoints, initial, opts)
    fit = emptyFit();
    fit.rotation = initial.rotation;
    fit.translationMm = initial.translationMm;
    fit.scale = initial.scale;
    fit.initialization = initial.label;
    trace = struct('rmse', nan(opts.icpIterations, 1), ...
        'medianDistanceMm', nan(opts.icpIterations, 1), ...
        'keptPoints', nan(opts.icpIterations, 1));

    minKeep = max(12, min(size(sourcePoints, 1), round(0.05 * size(sourcePoints, 1))));
    for iter = 1:opts.icpIterations
        moved = applyPointTransform(sourcePoints, fit.rotation, ...
            fit.translationMm, fit.scale);
        [idx, dist] = nearestRows(targetPoints, moved, 2500);
        valid = isfinite(dist);
        if nnz(valid) < minKeep
            break;
        end
        threshold = percentileLocal(dist(valid), 100 * opts.trimFraction);
        keep = valid & dist <= threshold;
        if nnz(keep) < minKeep
            [~, order] = sort(dist(valid), 'ascend');
            validRows = find(valid);
            keepRows = validRows(order(1:minKeep));
            keep = false(size(dist));
            keep(keepRows) = true;
        end
        matched = targetPoints(idx(keep), :);
        fitNow = fitPointTransform(sourcePoints(keep, :), matched, ...
            opts.transformType);
        fit.rotation = fitNow.rotation;
        fit.translationMm = fitNow.translationMm;
        fit.scale = fitNow.scale;
        fit.iterations = iter;
        trace.rmse(iter) = sqrt(mean(dist(keep) .^ 2));
        trace.medianDistanceMm(iter) = median(dist(keep));
        trace.keptPoints(iter) = nnz(keep);
    end

    moved = applyPointTransform(sourcePoints, fit.rotation, ...
        fit.translationMm, fit.scale);
    [~, dist] = nearestRows(targetPoints, moved, 2500);
    valid = isfinite(dist);
    if nnz(valid) >= minKeep
        threshold = percentileLocal(dist(valid), 100 * opts.trimFraction);
        keep = valid & dist <= threshold;
    else
        keep = valid;
    end
    if ~any(keep)
        fit.score = inf;
        fit.trimmedRmseMm = inf;
        fit.trimmedMedianDistanceMm = inf;
        fit.trimmedP95DistanceMm = inf;
    else
        fit.score = median(dist(keep));
        fit.trimmedRmseMm = sqrt(mean(dist(keep) .^ 2));
        fit.trimmedMedianDistanceMm = median(dist(keep));
        fit.trimmedP95DistanceMm = percentileLocal(dist(keep), 95);
    end
    fit.keptPoints = nnz(keep);
end

function fit = emptyFit()
    fit = struct( ...
        'rotation', eye(3), ...
        'translationMm', [0 0 0], ...
        'scale', 1, ...
        'score', inf, ...
        'trimmedRmseMm', inf, ...
        'trimmedMedianDistanceMm', inf, ...
        'trimmedP95DistanceMm', inf, ...
        'keptPoints', 0, ...
        'iterations', 0, ...
        'initialization', '');
end

function tf = isFiniteRegistrationSeed(reg)
    tf = isfield(reg, 'rotation') && isfield(reg, 'translationMm') && ...
        isfield(reg, 'scale') && ...
        all(isfinite(double(reg.rotation(:)))) && ...
        all(isfinite(double(reg.translationMm(:)))) && ...
        isfinite(double(reg.scale));
    if tf && isfield(reg, 'rmseMm')
        tf = isfinite(double(reg.rmseMm));
    end
end

function tf = isFiniteScoredFit(fit)
    tf = isfield(fit, 'rotation') && isfield(fit, 'translationMm') && ...
        isfield(fit, 'scale') && isfield(fit, 'score') && ...
        all(isfinite(double(fit.rotation(:)))) && ...
        all(isfinite(double(fit.translationMm(:)))) && ...
        isfinite(double(fit.scale)) && isfinite(double(fit.score));
end

function txt = candidateFitSummary(candidateFits)
    if isempty(candidateFits)
        txt = '(none)';
        return;
    end
    pieces = cell(numel(candidateFits), 1);
    for i = 1:numel(candidateFits)
        label = char(getOptionalField(candidateFits(i), 'initialization', ''));
        if isempty(label)
            label = sprintf('candidate%d', i);
        end
        score = double(getOptionalField(candidateFits(i), 'score', inf));
        med = double(getOptionalField(candidateFits(i), ...
            'trimmedMedianDistanceMm', inf));
        pieces{i} = sprintf('%s score=%.4g median=%.4g', label, score, med);
    end
    txt = strjoin(pieces(:)', '; ');
end

function fit = fitPointTransform(source, target, transformType)
    source = double(source);
    target = double(target);
    sourceCenter = mean(source, 1);
    targetCenter = mean(target, 1);
    X = bsxfun(@minus, source, sourceCenter);
    Y = bsxfun(@minus, target, targetCenter);
    [U, S, V] = svd(X' * Y, 'econ'); %#ok<ASGLU>
    R = U * V';
    if det(R) < 0
        U(:, end) = -U(:, end);
        R = U * V';
    end
    if strcmpi(transformType, 'similarity')
        scale = sum(diag(S)) / max(eps, sum(X(:) .^ 2));
    else
        scale = 1;
    end
    t = targetCenter - sourceCenter * R * scale;
    fit = struct('rotation', R, 'translationMm', t, 'scale', scale);
end

function pointsOut = applyPointTransform(pointsIn, R, t, scale)
    pointsOut = double(pointsIn) * double(R) * double(scale) + double(t);
end

function H = rowHomogeneousTransform(R, t, scale)
    H = eye(4);
    H(1:3, 1:3) = double(R) * double(scale);
    H(4, 1:3) = double(t);
end

function metrics = registrationMetrics(sourceRegistered, targetPoints, opts)
    sourceSample = deterministicSampleRows(sourceRegistered, opts.maxSourcePoints);
    targetSample = deterministicSampleRows(targetPoints, opts.maxTargetPoints);
    [~, dSourceToTarget] = nearestRows(targetSample, sourceSample, 2500);
    [~, dTargetToSource] = nearestRows(sourceSample, targetSample, 2500);
    metrics = struct();
    metrics.sourceToTargetMedianMm = medianFinite(dSourceToTarget);
    metrics.sourceToTargetP95Mm = percentileLocal(dSourceToTarget, 95);
    metrics.sourceToTargetTrimmedRmseMm = trimmedRmse(dSourceToTarget, opts.trimFraction);
    metrics.targetToSourceMedianMm = medianFinite(dTargetToSource);
    metrics.targetToSourceP95Mm = percentileLocal(dTargetToSource, 95);
    metrics.targetToSourceTrimmedRmseMm = trimmedRmse(dTargetToSource, opts.trimFraction);
end

function value = trimmedRmse(d, trimFraction)
    d = d(isfinite(d));
    if isempty(d)
        value = NaN;
        return;
    end
    keep = d <= percentileLocal(d, 100 * trimFraction);
    value = sqrt(mean(d(keep) .^ 2));
end

function fig = makeQcFigure(out, opts, visible)
    if nargin < 3 || isempty(visible)
        visible = 'on';
    end
    TRphone = out.meshes.TRregisteredPhone;
    TRtarget = out.meshes.TRtargetHead;
    TRheadpost = out.meshes.TRtargetHeadpost;
    phonePts = double(TRphone.Points);
    targetPts = double(TRtarget.Points);
    [~, sourceDistance] = nearestRows( ...
        deterministicSampleRows(targetPts, opts.maxTargetPoints), ...
        phonePts, 2500);
    cData = min(sourceDistance, opts.distanceClipMm);

    fig = figure('Name', 'Phone scan registration QC', ...
        'NumberTitle', 'off', ...
        'Color', 'w', ...
        'Visible', visible, ...
        'Units', 'pixels', ...
        'Position', [80 80 1400 850]);
    tl = tiledlayout(fig, 2, 2, 'TileSpacing', 'compact', ...
        'Padding', 'compact');
    title(tl, 'Phone scan registered to capMaker/MRI frame', ...
        'Interpreter', 'none');

    ax1 = nexttile(tl, 1);
    drawOverlayAxes(ax1, TRtarget, TRheadpost, TRphone, [], opts);
    title(ax1, 'overlay');

    ax2 = nexttile(tl, 2);
    drawOverlayAxes(ax2, TRtarget, TRheadpost, TRphone, cData, opts);
    title(ax2, 'phone scan nearest-target distance');
    cb = colorbar(ax2);
    cb.Label.String = sprintf('distance clipped at %.1f mm', opts.distanceClipMm);

    ax3 = nexttile(tl, 3);
    histogram(ax3, sourceDistance(isfinite(sourceDistance)), 60, ...
        'FaceColor', [0.22 0.45 0.70], 'EdgeColor', 'none');
    xline(ax3, out.metrics.sourceToTargetMedianMm, 'k-', 'median');
    xline(ax3, out.metrics.sourceToTargetP95Mm, 'r-', 'p95');
    xlabel(ax3, 'registered phone scan to target distance (mm)');
    ylabel(ax3, 'vertices');
    title(ax3, 'source-to-target residuals');
    box(ax3, 'off');

    ax4 = nexttile(tl, 4);
    drawOverlayAxes(ax4, TRtarget, TRheadpost, TRphone, [], opts);
    title(ax4, 'top view');
    view(ax4, 2);
end

function drawOverlayAxes(ax, TRtarget, TRheadpost, TRphone, cData, opts)
    hold(ax, 'on');
    targetDisplay = decimateTriangulation(TRtarget, 35000);
    patch(ax, 'Faces', targetDisplay.ConnectivityList, ...
        'Vertices', targetDisplay.Points, ...
        'FaceColor', [0.70 0.70 0.70], ...
        'FaceAlpha', 0.28, ...
        'EdgeColor', 'none', ...
        'FaceLighting', 'gouraud', ...
        'AmbientStrength', 0.55);
    if ~isempty(TRheadpost)
        hpDisplay = decimateTriangulation(TRheadpost, 15000);
        patch(ax, 'Faces', hpDisplay.ConnectivityList, ...
            'Vertices', hpDisplay.Points, ...
            'FaceColor', [0.10 0.10 0.10], ...
            'FaceAlpha', 0.25, ...
            'EdgeColor', 'none', ...
            'FaceLighting', 'gouraud');
    end
    phoneDisplay = decimateTriangulation(TRphone, 40000);
    if isempty(cData)
        patch(ax, 'Faces', phoneDisplay.ConnectivityList, ...
            'Vertices', phoneDisplay.Points, ...
            'FaceColor', [0.00 0.58 0.82], ...
            'FaceAlpha', 0.42, ...
            'EdgeColor', 'none', ...
            'FaceLighting', 'gouraud');
    else
        cDataDisplay = interpolateCDataForDisplay(TRphone, phoneDisplay, cData);
        patch(ax, 'Faces', phoneDisplay.ConnectivityList, ...
            'Vertices', phoneDisplay.Points, ...
            'FaceVertexCData', cDataDisplay, ...
            'FaceColor', 'interp', ...
            'FaceAlpha', 0.92, ...
            'EdgeColor', 'none', ...
            'FaceLighting', 'none');
        colormap(ax, parula(256));
        caxis(ax, [0 opts.distanceClipMm]);
    end
    axis(ax, 'equal');
    axis(ax, 'vis3d');
    grid(ax, 'on');
    xlabel(ax, 'X (mm)');
    ylabel(ax, 'Y (mm)');
    zlabel(ax, 'Z (mm)');
    view(ax, 3);
    camlight(ax, 'headlight');
    lighting(ax, 'gouraud');
end

function cSmall = interpolateCDataForDisplay(TRfull, TRsmall, cFull)
    if size(TRfull.Points, 1) == size(TRsmall.Points, 1) && ...
            max(abs(TRfull.Points(:) - TRsmall.Points(:))) < 1e-9
        cSmall = cFull;
        return;
    end
    idx = nearestRows(double(TRfull.Points), double(TRsmall.Points), 2500);
    cSmall = cFull(idx);
end

function TRout = decimateTriangulation(TRin, maxFaces)
    TRin = ensureTriangulation(TRin);
    if isempty(maxFaces) || size(TRin.ConnectivityList, 1) <= maxFaces
        TRout = TRin;
        return;
    end
    try
        fv = reducepatch(struct('faces', TRin.ConnectivityList, ...
            'vertices', TRin.Points), maxFaces);
        TRout = triangulation(double(fv.faces), double(fv.vertices));
    catch
        TRout = TRin;
    end
end

function rows = deterministicSampleRows(points, maxRows)
    n = size(points, 1);
    if n <= maxRows
        rows = double(points);
        return;
    end
    idx = unique(round(linspace(1, n, maxRows)));
    rows = double(points(idx(:), :));
end

function [idx, dist] = nearestRows(reference, query, chunk)
    if nargin < 3 || isempty(chunk)
        chunk = 2500;
    end
    reference = double(reference);
    query = double(query);
    if exist('knnsearch', 'file') == 2
        [idx, dist] = knnsearch(reference, query);
        return;
    end
    n = size(query, 1);
    idx = nan(n, 1);
    dist = nan(n, 1);
    for startRow = 1:chunk:n
        stopRow = min(n, startRow + chunk - 1);
        Q = query(startRow:stopRow, :);
        D = pdist2Fallback(Q, reference);
        [d2, ii] = min(D, [], 2);
        idx(startRow:stopRow) = ii;
        dist(startRow:stopRow) = sqrt(max(d2, 0));
    end
end

function D = pdist2Fallback(A, B)
    aa = sum(A .^ 2, 2);
    bb = sum(B .^ 2, 2)';
    D = bsxfun(@plus, aa, bb) - 2 * (A * B');
    D(D < 0) = 0;
end

function p = percentileLocal(x, pct)
    x = x(isfinite(x));
    if isempty(x)
        p = NaN;
        return;
    end
    x = sort(x(:));
    pct = max(0, min(100, pct));
    pos = 1 + (numel(x) - 1) * pct / 100;
    lo = floor(pos);
    hi = ceil(pos);
    if lo == hi
        p = x(lo);
    else
        p = x(lo) + (pos - lo) * (x(hi) - x(lo));
    end
end

function m = medianFinite(x)
    x = x(isfinite(x));
    if isempty(x)
        m = NaN;
    else
        m = median(x);
    end
end

function m = medianRowsFinite(P)
    P = double(P);
    m = nan(1, size(P, 2));
    for j = 1:size(P, 2)
        x = P(:, j);
        x = x(isfinite(x));
        if isempty(x)
            m(j) = 0;
        else
            m(j) = median(x);
        end
    end
end

function TR = ensureTriangulation(value)
    if isa(value, 'triangulation')
        TR = value;
    elseif isstruct(value) && isfield(value, 'ConnectivityList') && ...
            isfield(value, 'Points')
        TR = triangulation(double(value.ConnectivityList), double(value.Points));
    elseif isstruct(value) && isfield(value, 'faces') && isfield(value, 'vertices')
        TR = triangulation(double(value.faces), double(value.vertices));
    else
        error('acsRegisterPhoneScanToCapMakerFrame:BadTriangulation', ...
            'Expected a triangulation or faces/vertices structure.');
    end
end

function S = firstStruct(M)
    if isstruct(M) && isfield(M, 'out') && isstruct(M.out)
        S = M.out;
        return;
    end
    if isstruct(M) && isfield(M, 'outForSave') && isstruct(M.outForSave)
        S = M.outForSave;
        return;
    end
    if isstruct(M) && isfield(M, 'outSaved') && isstruct(M.outSaved)
        S = M.outSaved;
        return;
    end
    if isstruct(M)
        fields = fieldnames(M);
        for i = 1:numel(fields)
            if startsWith(fields{i}, '__')
                continue;
            end
            value = M.(fields{i});
            if isstruct(value)
                S = value;
                return;
            end
        end
    end
    S = M;
end

function value = getOptionalField(S, fieldName, defaultValue)
    value = defaultValue;
    if isstruct(S) && isfield(S, fieldName) && ~isempty(S.(fieldName))
        value = S.(fieldName);
    end
end

function labels = normalizeLabelCell(labelsIn)
    if isempty(labelsIn)
        labels = {};
    elseif iscell(labelsIn)
        labels = cellfun(@char, labelsIn(:), 'UniformOutput', false);
    elseif isstring(labelsIn)
        labels = cellstr(labelsIn(:));
    elseif ischar(labelsIn)
        if size(labelsIn, 1) == 1
            labels = {strtrim(labelsIn)};
        else
            labels = cellstr(labelsIn);
        end
    else
        labels = cellstr(labelsIn(:));
    end
    labels = labels(:);
end

function fileName = expandUserPath(fileName)
    fileName = char(fileName);
    if startsWith(fileName, '~')
        fileName = fullfile(char(java.lang.System.getProperty('user.home')), ...
            fileName(2:end));
    end
end

function name = getFileName(fileName)
    [~, stem, ext] = fileparts(char(fileName));
    name = [stem ext];
end

function stem = stripMatExtension(fileName)
    [~, stem, ~] = fileparts(char(fileName));
end

function name = safeName(name)
    name = regexprep(char(name), '[^\w\-]+', '_');
    name = regexprep(name, '_+', '_');
    name = regexprep(name, '^_|_$', '');
    if isempty(name)
        name = 'phoneScanRegistration';
    end
end

function ensureDir(folder)
    if ~isempty(folder) && exist(folder, 'dir') ~= 7
        mkdir(folder);
    end
end

function saveQcFigure(fig, fileName)
    try
        exportgraphics(fig, fileName, 'Resolution', 200);
    catch
        saveas(fig, fileName);
    end
end

function ply = readAsciiPlyMesh(fileName)
    fid = fopen(fileName, 'r');
    if fid < 0
        error('acsRegisterPhoneScanToCapMakerFrame:CannotOpenPly', ...
            'Could not open PLY file: %s', fileName);
    end
    cleanup = onCleanup(@() fclose(fid));
    line = fgetl(fid);
    if ~ischar(line) || ~strcmp(strtrim(line), 'ply')
        error('acsRegisterPhoneScanToCapMakerFrame:BadPly', ...
            'File does not start with a PLY header: %s', fileName);
    end
    nVertices = 0;
    nFaces = 0;
    isAscii = false;
    while true
        line = fgetl(fid);
        if ~ischar(line)
            error('acsRegisterPhoneScanToCapMakerFrame:BadPlyHeader', ...
                'PLY header ended unexpectedly.');
        end
        txt = strtrim(line);
        if startsWith(txt, 'format ascii')
            isAscii = true;
        elseif startsWith(txt, 'element vertex')
            parts = strsplit(txt);
            nVertices = str2double(parts{3});
        elseif startsWith(txt, 'element face')
            parts = strsplit(txt);
            nFaces = str2double(parts{3});
        elseif strcmp(txt, 'end_header')
            break;
        end
    end
    if ~isAscii
        error('acsRegisterPhoneScanToCapMakerFrame:BinaryPlyUnsupported', ...
            'Only ASCII PLY files are supported directly. Use the cropped MAT product if needed.');
    end
    V = nan(nVertices, 3);
    for i = 1:nVertices
        parts = sscanf(fgetl(fid), '%f');
        V(i, :) = parts(1:3)';
    end
    F = nan(nFaces, 3);
    keep = true(nFaces, 1);
    for i = 1:nFaces
        parts = sscanf(fgetl(fid), '%d');
        if isempty(parts) || parts(1) < 3
            keep(i) = false;
            continue;
        end
        F(i, :) = double(parts(2:4)' + 1);
    end
    ply = struct('vertices', V, 'faces', F(keep, :));
end

function printSummary(out)
    fprintf('\nPhone scan to capMaker/MRI registration\n');
    fprintf('  source: %s\n', char(getOptionalField(out.source, 'file', '')));
    fprintf('  target: %s\n', char(getOptionalField(out.target, 'file', '')));
    fprintf('  target frame: %s\n', out.targetCoordinateFrame);
    fprintf('  transform: %s, scale %.6g\n', out.transformType, out.scale);
    if isfield(out, 'initialization') && isfield(out.initialization, 'resolvedMode')
        fprintf('  initialization mode: %s\n', out.initialization.resolvedMode);
    end
    fprintf('  ICP init: %s\n', out.fit.initialization);
    fprintf('  trimmed RMSE / median / p95: %.3g / %.3g / %.3g mm\n', ...
        out.fit.trimmedRmseMm, out.fit.trimmedMedianDistanceMm, ...
        out.fit.trimmedP95DistanceMm);
    fprintf('  source->target median / p95: %.3g / %.3g mm\n', ...
        out.metrics.sourceToTargetMedianMm, out.metrics.sourceToTargetP95Mm);
    fprintf('  target->source median / p95: %.3g / %.3g mm\n', ...
        out.metrics.targetToSourceMedianMm, out.metrics.targetToSourceP95Mm);
    fprintf('  output: %s\n', out.outputFile);
    if ~isempty(out.qcFigure)
        fprintf('  QC figure: %s\n', out.qcFigure);
    end
end
