function out = acsSelectStereotaxicLandmarks(volumeIn, varargin)
% ACSSELECTSTEREOTAXICLANDMARKS Pick stereotaxic landmarks in a T1 volume.
%
% out = acsSelectStereotaxicLandmarks(t1File) steps through a small set of
% stereotaxic landmarks in the orthogonal slice viewer, then estimates a
% row-vector stereotaxic frame:
%
%   stereotaxicMm = (worldMm - originWorldMm) * axesWorld
%
% axesWorld columns are [left-right, rostro-caudal, dorso-ventral]. Defaults
% assume right, rostral, and dorsal are positive.
%
% Name-value options:
%   landmarkLabels : labels to pick [{'LeftEarBar','RightEarBar','LeftOrbit','RightOrbit'}]
%   initialVoxel   : first viewer voxel [[] = center]
%   outputFile     : optional MAT output ['']
%   force          : overwrite output [false]
%   showFigures    : show viewer figures [true]
%   saveFigures    : save viewer figures [false]
%   verbose        : print instructions/summary [true]

    if nargin < 1 || isempty(volumeIn)
        error('acsSelectStereotaxicLandmarks:MissingInput', ...
            'Provide a T1/MPRAGE volume filename, SPM volume, or 3-D array.');
    end

    opts = parseInputs(varargin{:});
    addLocalDependencies();

    if ~isempty(opts.outputFile) && exist(opts.outputFile, 'file') == 2 && ~opts.force
        S = load(opts.outputFile);
        out = firstStruct(S);
        if opts.verbose
            fprintf('Stereotaxic landmarks already exist; reusing %s\n', opts.outputFile);
        end
        return;
    end

    [Vref, source] = referenceVolume(volumeIn);
    labels = opts.landmarkLabels(:);
    voxels = nan(numel(labels), 3);
    current = opts.initialVoxel;

    if opts.verbose
        fprintf('\nStereotaxic landmark picking\n');
        fprintf('  Use the slice viewer to place the crosshair for each landmark.\n');
        fprintf('  Press A or Set voxel, then click Accept or press Enter in the viewer.\n');
        fprintf('  Default landmarks: ear-bar contacts and ventral orbital/eye-bar contacts.\n');
    end

    for i = 1:numel(labels)
        if opts.verbose
            fprintf('\nPick landmark %d/%d: %s\n', i, numel(labels), labels{i});
        end
        pick = acsLabelVolumeOrientation(volumeIn, ...
            'orientationCode', 'skip', ...
            'allowSkip', true, ...
            'voxelSelectionMode', 'single', ...
            'initialVoxel', current, ...
            'volumeLabel', sprintf('%s | stereotaxic landmark: %s', ...
                source.label, labels{i}), ...
            'waitForDone', true, ...
            'doneButtonLabel', sprintf('Accept %s', labels{i}), ...
            'cancelButtonLabel', 'Cancel', ...
            'closeFigure', true, ...
            'showFigures', opts.showFigures, ...
            'saveFigures', opts.saveFigures, ...
            'verbose', opts.verbose);
        voxel = double(pick.selectedVoxels(1, :));
        voxels(i, :) = voxel;
        current = voxel;
    end

    worldMm = voxel1ToWorldMm(voxels, Vref.mat);
    frame = stereotaxicFrameFromLandmarks(labels, worldMm, opts);

    out = struct();
    out.createdOn = char(datetime('now'));
    out.source = source;
    out.labels = labels;
    out.voxelCoordinates = voxels;
    out.worldCoordinatesMm = worldMm;
    out.coordinateFrames = struct( ...
        'voxelCoordinates', 'oneBasedVoxel', ...
        'worldCoordinatesMm', 'volumeWorldMm', ...
        'stereotaxicMm', 'estimatedStereotaxicMm');
    out.frame = frame;
    out.options = opts;

    if ~isempty(opts.outputFile)
        ensureDir(fileparts(opts.outputFile));
        save(opts.outputFile, 'out', '-v7.3');
    end
    if opts.verbose
        printSummary(out);
    end
end

function opts = parseInputs(varargin)
    p = inputParser;
    p.FunctionName = 'acsSelectStereotaxicLandmarks';
    addParameter(p, 'landmarkLabels', ...
        {'LeftEarBar', 'RightEarBar', 'LeftOrbit', 'RightOrbit'}, ...
        @(x) iscell(x) || isstring(x) || ischar(x));
    addParameter(p, 'initialVoxel', [], ...
        @(x) isempty(x) || (isnumeric(x) && numel(x) == 3));
    addParameter(p, 'outputFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'force', false, @isBoolLike);
    addParameter(p, 'showFigures', true, @isBoolLike);
    addParameter(p, 'saveFigures', false, @isBoolLike);
    addParameter(p, 'verbose', true, @isBoolLike);
    parse(p, varargin{:});

    opts = p.Results;
    opts.landmarkLabels = normalizeLabelCell(opts.landmarkLabels);
    opts.initialVoxel = double(opts.initialVoxel(:)');
    opts.outputFile = expandUserPath(char(opts.outputFile));
    opts.force = logical(opts.force);
    opts.showFigures = logical(opts.showFigures);
    opts.saveFigures = logical(opts.saveFigures);
    opts.verbose = logical(opts.verbose);
end

function tf = isBoolLike(x)
    tf = (islogical(x) || isnumeric(x)) && isscalar(x);
end

function addLocalDependencies()
    repoRoot = fileparts(fileparts(mfilename('fullpath')));
    addpath(fullfile(repoRoot, 'acsUtilities'));
    spmDir = fullfile(repoRoot, 'lib', 'spm12');
    if exist(spmDir, 'dir') == 7
        addpath(spmDir);
    end
end

function [Vref, source] = referenceVolume(volumeIn)
    source = struct('type', '', 'file', '', 'label', '');
    if isstruct(volumeIn) && isfield(volumeIn, 'fname')
        Vref = volumeIn(1);
        source.type = 'spmVolume';
        source.file = Vref.fname;
        source.label = getFileName(Vref.fname);
        return;
    end
    if ischar(volumeIn) || isstring(volumeIn)
        fileName = expandUserPath(char(volumeIn));
        V = spm_vol(fileName);
        Vref = V(1);
        source.type = 'file';
        source.file = fileName;
        source.label = getFileName(fileName);
        return;
    end
    if isnumeric(volumeIn) || islogical(volumeIn)
        Vref = struct('mat', eye(4), 'dim', size(volumeIn));
        source.type = 'array';
        source.label = 'workspace volume';
        return;
    end
    error('acsSelectStereotaxicLandmarks:BadVolume', ...
        'Unsupported volume input.');
end

function frame = stereotaxicFrameFromLandmarks(labels, worldMm, opts)
    labelsNorm = normalizeKeyCell(labels);
    leftEar = requiredPoint('LeftEarBar', {'leftearbar','leftear','lpa','leftpa'}, labelsNorm, worldMm);
    rightEar = requiredPoint('RightEarBar', {'rightearbar','rightear','rpa','rightpa'}, labelsNorm, worldMm);
    leftOrbit = requiredPoint('LeftOrbit', {'leftorbit','lefteyebar','loc'}, labelsNorm, worldMm);
    rightOrbit = requiredPoint('RightOrbit', {'rightorbit','righteyebar','roc'}, labelsNorm, worldMm);

    origin = 0.5 * (leftEar + rightEar);
    xAxis = normalizeRow(rightEar - leftEar);
    orbitMid = 0.5 * (leftOrbit + rightOrbit);
    yAxis = orbitMid - origin;
    yAxis = yAxis - dot(yAxis, xAxis) * xAxis;
    yAxis = normalizeRow(yAxis);
    zAxis = normalizeRow(cross(xAxis, yAxis));
    yAxis = normalizeRow(cross(zAxis, xAxis));

    frame = struct();
    frame.originWorldMm = origin;
    frame.axesWorld = [xAxis(:), yAxis(:), zAxis(:)];
    frame.axisLabels = {'rightPositive', 'rostralPositive', 'dorsalPositive'};
    frame.landmarkLabelsUsed = {'LeftEarBar', 'RightEarBar', 'LeftOrbit', 'RightOrbit'};
    frame.leftEarBarWorldMm = leftEar;
    frame.rightEarBarWorldMm = rightEar;
    frame.leftOrbitWorldMm = leftOrbit;
    frame.rightOrbitWorldMm = rightOrbit;
    frame.orbitMidpointWorldMm = orbitMid;
    frame.instructions = ...
        'For row-vector points, stereotaxicMm = (worldMm - originWorldMm) * axesWorld.';
    frame.landmarkCoordinatesStereotaxicMm = worldToStereotaxic(worldMm, frame);
    frame.options = opts;
end

function P = requiredPoint(label, aliases, labelsNorm, worldMm)
    row = [];
    for i = 1:numel(aliases)
        row = find(strcmp(labelsNorm, aliases{i}), 1);
        if ~isempty(row)
            break;
        end
    end
    if isempty(row)
        error('acsSelectStereotaxicLandmarks:MissingLandmark', ...
            'Could not find required stereotaxic landmark: %s', label);
    end
    P = worldMm(row, :);
end

function coords = worldToStereotaxic(worldMm, frame)
    coords = bsxfun(@minus, worldMm, frame.originWorldMm) * frame.axesWorld;
end

function worldMm = voxel1ToWorldMm(vox1, M)
    P = [double(vox1), ones(size(vox1, 1), 1)] * double(M)';
    worldMm = P(:, 1:3);
end

function row = normalizeRow(row)
    n = norm(row);
    if n <= eps || ~isfinite(n)
        error('acsSelectStereotaxicLandmarks:DegenerateFrame', ...
            'Stereotaxic landmarks are degenerate; cannot estimate frame.');
    end
    row = row ./ n;
end

function labels = normalizeLabelCell(labelsIn)
    if isempty(labelsIn)
        labels = {};
    elseif iscell(labelsIn)
        labels = cellstr(labelsIn(:));
    elseif isstring(labelsIn)
        labels = cellstr(labelsIn(:));
    elseif ischar(labelsIn)
        if size(labelsIn, 1) == 1
            labels = {char(labelsIn)};
        else
            labels = cellstr(labelsIn);
        end
    else
        labels = cellstr(labelsIn(:));
    end
    labels = labels(:);
end

function keys = normalizeKeyCell(labels)
    keys = normalizeLabelCell(labels);
    keys = cellfun(@(x) regexprep(lower(x), '[^a-z0-9]', ''), ...
        keys, 'UniformOutput', false);
end

function S = firstStruct(raw)
    preferred = {'out', 'landmarks', 'stereotaxicLandmarks'};
    for i = 1:numel(preferred)
        if isfield(raw, preferred{i}) && isstruct(raw.(preferred{i}))
            S = raw.(preferred{i});
            return;
        end
    end
    names = fieldnames(raw);
    for i = 1:numel(names)
        if isstruct(raw.(names{i}))
            S = raw.(names{i});
            return;
        end
    end
    error('acsSelectStereotaxicLandmarks:NoStructInFile', ...
        'MAT file does not contain a readable struct.');
end

function fileName = getFileName(fileName)
    [~, stem, ext] = fileparts(fileName);
    fileName = [stem ext];
end

function fileName = expandUserPath(fileName)
    if isempty(fileName)
        return;
    end
    if startsWith(fileName, '~')
        homeDir = getenv('HOME');
        if isempty(homeDir)
            homeDir = char(java.lang.System.getProperty('user.home'));
        end
        fileName = fullfile(homeDir, fileName(2:end));
    end
end

function ensureDir(folder)
    if isempty(folder)
        return;
    end
    if exist(folder, 'dir') ~= 7
        mkdir(folder);
    end
end

function printSummary(out)
    fprintf('\nStereotaxic landmarks\n');
    fprintf('  source: %s\n', out.source.label);
    for i = 1:numel(out.labels)
        st = out.frame.landmarkCoordinatesStereotaxicMm(i, :);
        fprintf('  %s voxel [%g %g %g], stereo [%.2f %.2f %.2f] mm\n', ...
            out.labels{i}, ...
            out.voxelCoordinates(i, 1), out.voxelCoordinates(i, 2), ...
            out.voxelCoordinates(i, 3), st(1), st(2), st(3));
    end
end
