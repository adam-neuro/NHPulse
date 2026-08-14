function out = acsGenerateDummyRoastLeadField(roastSource, varargin)
% ACSGENERATEDUMMYROASTLEADFIELD Write development-only fake ROAST lead fields.
%
% out = acsGenerateDummyRoastLeadField(layout) writes the same small set of
% MAT files consumed by ACS lead-field optimization utilities, without
% running ROAST, meshing, or GetDP. The resulting fields are smooth synthetic
% patterns intended only for code-path development.
%
% Name-value options:
%   simulationTag      : dummy lead-field tag ['DUMMY_capMakerLeadField']
%   electrodeNames     : override custom candidate names [layout.names]
%   referenceElectrode : basis-field reference electrode [last candidate]
%   meshSpacingMm      : approximate dummy brain node spacing [1.5]
%   fieldScale         : peak synthetic field scale [1]
%   force              : overwrite existing dummy files [false]
%   saveReport         : save request report beside the T1 [true]
%   verbose            : print generated files [true]

    if nargin < 1 || isempty(roastSource)
        error('acsGenerateDummyRoastLeadField:MissingInput', ...
            'Provide a capMaker layout struct or ROAST-ready T1 file.');
    end

    opts = parseInputs(varargin{:});
    [t1File, layoutNames] = resolveSource(roastSource);
    names = opts.electrodeNames;
    if isempty(names)
        names = layoutNames;
    end
    names = normalizeNames(names);
    validateCustomNames(names);

    referenceElectrode = char(opts.referenceElectrode);
    if isempty(referenceElectrode)
        referenceElectrode = names{end};
    end
    assertMember(referenceElectrode, names);
    stimulusNames = names(~strcmpi(names, referenceElectrode));
    if isempty(stimulusNames)
        error('acsGenerateDummyRoastLeadField:NoStimulusElectrodes', ...
            'At least one non-reference stimulus electrode is required.');
    end

    [folder, stem] = fileparts(t1File);
    files = outputFiles(folder, stem, opts.simulationTag);
    requireNoOverwrite(files, opts.force);

    candidateSnapshot = snapshotCustomLocations(t1File, opts.simulationTag, names, opts.force);
    candidateVox = readCandidateVoxels(candidateSnapshot, names);

    V = spm_vol(t1File);
    V = V(1);
    voxelSize = canonicalVoxelSize(V);
    imageSize = double(V.dim(1:3));
    [node, elem, face, meshInfo] = makeDummyMesh(imageSize, voxelSize, opts.meshSpacingMm);
    A_all = makeDummyFields(node, candidateVox, names, stimulusNames, referenceElectrode, ...
        voxelSize, imageSize, opts.fieldScale);

    opt = makeDummyOptions(names, stimulusNames, referenceElectrode, opts, candidateSnapshot);
    dummyLeadField = makeDummyMetadata(t1File, files, opts, names, stimulusNames, ...
        referenceElectrode, candidateSnapshot, candidateVox, meshInfo);

    save(files.meshMat, 'node', 'elem', 'face', 'dummyLeadField', '-v7.3');
    save(files.roastResultMat, 'A_all', 'dummyLeadField', '-v7.3');
    save(files.roastOptionsMat, 'opt', 'dummyLeadField');

    out = buildReport(t1File, opts, files, names, stimulusNames, referenceElectrode, ...
        candidateSnapshot, candidateVox, meshInfo);
    if opts.saveReport
        save(files.requestMat, 'out');
    end
    if opts.verbose
        fprintf('Wrote DUMMY lead field tag: %s\n', opts.simulationTag);
        fprintf('  result:  %s\n', files.roastResultMat);
        fprintf('  options: %s\n', files.roastOptionsMat);
        fprintf('  mesh:    %s\n', files.meshMat);
        fprintf('  nodes:   %d\n', size(node, 1));
    end
end

function opts = parseInputs(varargin)
    p = inputParser;
    p.FunctionName = 'acsGenerateDummyRoastLeadField';
    addParameter(p, 'simulationTag', 'DUMMY_capMakerLeadField', @(x) ischar(x) || isstring(x));
    addParameter(p, 'electrodeNames', {}, @(x) iscell(x) || ischar(x) || isstring(x));
    addParameter(p, 'referenceElectrode', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'meshSpacingMm', 1.5, @(x) isnumeric(x) && isscalar(x) && x > 0);
    addParameter(p, 'fieldScale', 1, @(x) isnumeric(x) && isscalar(x) && x > 0);
    addParameter(p, 'force', false, @isBoolLike);
    addParameter(p, 'saveReport', true, @isBoolLike);
    addParameter(p, 'verbose', true, @isBoolLike);
    parse(p, varargin{:});

    opts = p.Results;
    opts.simulationTag = char(opts.simulationTag);
    opts.electrodeNames = normalizeNames(opts.electrodeNames);
    opts.referenceElectrode = char(opts.referenceElectrode);
    opts.meshSpacingMm = double(opts.meshSpacingMm);
    opts.fieldScale = double(opts.fieldScale);
    opts.force = logical(opts.force);
    opts.saveReport = logical(opts.saveReport);
    opts.verbose = logical(opts.verbose);
end

function tf = isBoolLike(x)
    tf = (islogical(x) || isnumeric(x)) && isscalar(x);
end

function [t1File, layoutNames] = resolveSource(source)
    layoutNames = {};
    if ischar(source) || isstring(source)
        t1File = char(source);
    elseif isstruct(source)
        if isfield(source, 't1File') && ~isempty(source.t1File)
            t1File = char(source.t1File);
        elseif isfield(source, 'roastReady') && isfield(source.roastReady, 't1File')
            t1File = char(source.roastReady.t1File);
        else
            error('acsGenerateDummyRoastLeadField:MissingT1', ...
                'The input struct does not contain t1File or roastReady.t1File.');
        end
        if isfield(source, 'names')
            layoutNames = normalizeNames(source.names);
        end
    else
        error('acsGenerateDummyRoastLeadField:BadSource', ...
            'Provide a layout struct or a ROAST-ready T1 file.');
    end
    if exist(t1File, 'file') ~= 2
        error('acsGenerateDummyRoastLeadField:MissingT1', ...
            'ROAST-ready T1 file not found: %s', t1File);
    end
end

function names = normalizeNames(names)
    if isempty(names)
        names = {};
    elseif ischar(names)
        names = {names};
    elseif isstring(names)
        names = cellstr(names(:));
    elseif iscell(names)
        names = cellfun(@char, names(:), 'UniformOutput', false);
    else
        error('acsGenerateDummyRoastLeadField:BadNames', ...
            'Electrode names must be a cell array or string array.');
    end
    names = names(:);
end

function validateCustomNames(names)
    if numel(names) < 2
        error('acsGenerateDummyRoastLeadField:TooFewElectrodes', ...
            'At least two candidate electrodes are required.');
    end
    if numel(unique(lower(string(names)))) ~= numel(names)
        error('acsGenerateDummyRoastLeadField:DuplicateElectrodes', ...
            'Candidate electrode names must be unique.');
    end
    for i = 1:numel(names)
        if isempty(strfind(lower(names{i}), 'custom')) %#ok<STREMP>
            error('acsGenerateDummyRoastLeadField:NonCustomName', ...
                'capMaker candidate names must contain "custom": %s', names{i});
        end
    end
end

function assertMember(referenceElectrode, names)
    if ~any(strcmpi(referenceElectrode, names))
        error('acsGenerateDummyRoastLeadField:BadReference', ...
            'Reference electrode "%s" is not in the candidate list.', referenceElectrode);
    end
end

function files = outputFiles(folder, stem, simulationTag)
    prefix = fullfile(folder, [stem '_' simulationTag]);
    files = struct();
    files.meshMat = [prefix '.mat'];
    files.roastResultMat = [prefix '_roastResult.mat'];
    files.roastOptionsMat = [prefix '_roastOptions.mat'];
    files.requestMat = [prefix '_acsLeadFieldRequest.mat'];
end

function requireNoOverwrite(files, force)
    fields = fieldnames(files);
    for i = 1:numel(fields)
        fileName = files.(fields{i});
        if exist(fileName, 'file') == 2 && ~force
            error('acsGenerateDummyRoastLeadField:OutputExists', ...
                'Output exists. Use force=true to overwrite: %s', fileName);
        end
    end
end

function snapshot = snapshotCustomLocations(t1File, simulationTag, names, force)
    [folder, stem] = fileparts(t1File);
    activeFile = fullfile(folder, [stem '_customLocations']);
    if exist(activeFile, 'file') ~= 2
        error('acsGenerateDummyRoastLeadField:MissingCustomLocations', ...
            'Custom locations file not found: %s', activeFile);
    end
    snapshot = fullfile(folder, [stem '_' simulationTag '_customLocations']);
    if exist(snapshot, 'file') == 2 && ~force
        validateSnapshotNames(snapshot, names);
        return;
    end
    validateSnapshotNames(activeFile, names);
    copyfile(activeFile, snapshot, 'f');
end

function validateSnapshotNames(fileName, expectedNames)
    [names, ~] = readCustomLocations(fileName);
    missing = setdiff(lower(string(expectedNames)), lower(string(names)));
    if ~isempty(missing)
        error('acsGenerateDummyRoastLeadField:MissingCandidateLocation', ...
            'Custom locations are missing candidate(s): %s', strjoin(cellstr(missing), ', '));
    end
end

function coords = readCandidateVoxels(fileName, expectedNames)
    [names, fileCoords] = readCustomLocations(fileName);
    coords = nan(numel(expectedNames), 3);
    for i = 1:numel(expectedNames)
        idx = find(strcmpi(expectedNames{i}, names), 1);
        if ~isempty(idx)
            coords(i, :) = fileCoords(idx, :);
        end
    end
    if any(~isfinite(coords(:)))
        error('acsGenerateDummyRoastLeadField:BadCandidateCoordinates', ...
            'Could not resolve all candidate coordinates from %s', fileName);
    end
end

function [names, coords] = readCustomLocations(fileName)
    fid = fopen(fileName, 'r');
    if fid == -1
        error('acsGenerateDummyRoastLeadField:CannotReadCustomLocations', ...
            'Could not read custom locations file: %s', fileName);
    end
    cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
    C = textscan(fid, '%s %f %f %f');
    names = C{1};
    coords = [C{2}, C{3}, C{4}];
end

function voxelSize = canonicalVoxelSize(V)
    voxelSize = [V.mat(1, 1), V.mat(2, 2), V.mat(3, 3)];
    if any(voxelSize <= 0) || any(any(abs(V.mat(1:3, 1:3) - diag(voxelSize)) > 1e-9))
        error('acsGenerateDummyRoastLeadField:NonCanonicalT1', ...
            'Expected a canonical RAS T1 with a positive diagonal voxel transform.');
    end
end

function [node, elem, face, info] = makeDummyMesh(imageSize, voxelSize, spacingMm)
    extentMm = imageSize .* voxelSize;
    centerMm = 0.5 * extentMm;
    radiusMm = 0.43 * extentMm;

    x = 0:spacingMm:extentMm(1);
    y = 0:spacingMm:extentMm(2);
    z = 0:spacingMm:extentMm(3);
    [X, Y, Z] = ndgrid(x, y, z);
    normalized = ((X - centerMm(1)) ./ radiusMm(1)) .^ 2 + ...
        ((Y - centerMm(2)) ./ radiusMm(2)) .^ 2 + ...
        ((Z - centerMm(3)) ./ radiusMm(3)) .^ 2;
    keep = normalized <= 1;
    node = single([X(keep), Y(keep), Z(keep)]);

    nElem = floor(size(node, 1) / 4);
    elem = reshape(uint32(1:(4 * nElem)), 4, [])';
    tissue = uint32(2 * ones(nElem, 1));
    tissue(1:2:end) = uint32(1);
    elem = [elem, tissue];

    hullRows = boundarySampleRows(double(node), centerMm);
    nFace = floor(numel(hullRows) / 3);
    if nFace > 0
        face = reshape(uint32(hullRows(1:(3 * nFace))), 3, [])';
        face = [face, uint32(2 * ones(size(face, 1), 1))];
    else
        face = zeros(0, 4, 'uint32');
    end

    info = struct();
    info.spacingMm = spacingMm;
    info.centerMm = centerMm;
    info.radiusMm = radiusMm;
    info.nodeCount = size(node, 1);
    info.elementCount = size(elem, 1);
    info.faceCount = size(face, 1);
    info.warning = 'Synthetic ellipsoid mesh: not anatomical, not physical, development only.';
end

function rows = boundarySampleRows(node, centerMm)
    delta = bsxfun(@minus, node(:, 1:3), centerMm);
    r = sqrt(sum(delta .^ 2, 2));
    rSorted = sort(r);
    threshold = rSorted(max(1, round(0.92 * numel(rSorted))));
    rows = find(r >= threshold);
    rows = rows(1:min(numel(rows), 6000));
end

function A_all = makeDummyFields(node, candidateVox, names, stimulusNames, referenceElectrode, ...
        voxelSize, imageSize, fieldScale)
    nStim = numel(stimulusNames);
    nNode = size(node, 1);
    A_all = zeros(nNode, 3, nStim, 'single');
    candidateMm = bsxfun(@times, double(candidateVox), voxelSize);
    extentMm = imageSize .* voxelSize;
    centerMm = 0.5 * extentMm;
    radiusMm = 0.43 * extentMm;
    sigmaMm = 0.22 * mean(radiusMm);

    refIdx = find(strcmpi(referenceElectrode, names), 1);
    refMm = candidateMm(refIdx, :);
    for k = 1:nStim
        stimIdx = find(strcmpi(stimulusNames{k}, names), 1);
        stimMm = candidateMm(stimIdx, :);
        inward = centerMm - stimMm;
        if norm(inward) == 0
            inward = [1 0 0];
        end
        inward = inward ./ norm(inward);

        posCenter = centerMm + 0.38 * radiusMm .* inward;
        phase = 2 * pi * (k - 1) / max(nStim, 1);
        transverse = [cos(phase), sin(phase), 0.35 * sin(2 * phase)];
        transverse = transverse ./ max(norm(transverse), eps);
        negCenter = centerMm - 0.30 * radiusMm .* inward + 0.12 * mean(radiusMm) * transverse;

        pos = gaussianRows(node, posCenter, sigmaMm);
        neg = gaussianRows(node, negCenter, 1.15 * sigmaMm);
        amp = fieldScale * (pos - 0.85 * neg);
        direction = stimMm - refMm;
        if norm(direction) == 0
            direction = inward;
        end
        direction = direction ./ norm(direction);
        swirl = cross(repmat(direction, nNode, 1), bsxfun(@minus, double(node), centerMm));
        swirlNorm = sqrt(sum(swirl .^ 2, 2));
        swirlNorm(swirlNorm == 0) = 1;
        swirl = bsxfun(@rdivide, swirl, swirlNorm);
        field = bsxfun(@times, amp, direction) + 0.20 * bsxfun(@times, pos + neg, swirl);
        A_all(:, :, k) = single(field);
    end
end

function g = gaussianRows(node, centerMm, sigmaMm)
    delta = bsxfun(@minus, double(node), centerMm);
    g = exp(-sum(delta .^ 2, 2) ./ (2 * sigmaMm ^ 2));
end

function opt = makeDummyOptions(names, stimulusNames, referenceElectrode, opts, candidateSnapshot)
    leadField = struct();
    leadField.mode = 'custom';
    leadField.dummy = true;
    leadField.dummyWarning = 'Synthetic dummy lead field: do not use for science or interpretation.';
    leadField.includePassiveElectrodes = true;
    leadField.electrodeNames = names(:);
    leadField.stimulusElectrodeNames = stimulusNames(:);
    leadField.referenceElectrode = referenceElectrode;
    leadField.customLocationsFile = candidateSnapshot;

    opt = struct();
    opt.resamp = false;
    opt.simulationTag = opts.simulationTag;
    opt.leadField = leadField;
    opt.dummy = true;
    opt.dummyWarning = leadField.dummyWarning;
end

function dummyLeadField = makeDummyMetadata(t1File, files, opts, names, stimulusNames, ...
        referenceElectrode, candidateSnapshot, candidateVox, meshInfo)
    dummyLeadField = struct();
    dummyLeadField.createdOn = char(datetime('now'));
    dummyLeadField.dummy = true;
    dummyLeadField.warning = 'Synthetic dummy lead field: not anatomical, not physical, development only.';
    dummyLeadField.t1File = t1File;
    dummyLeadField.simulationTag = opts.simulationTag;
    dummyLeadField.electrodeNames = names(:);
    dummyLeadField.stimulusElectrodeNames = stimulusNames(:);
    dummyLeadField.referenceElectrode = referenceElectrode;
    dummyLeadField.customLocationsSnapshot = candidateSnapshot;
    dummyLeadField.candidateVoxelCoordinates = candidateVox;
    dummyLeadField.mesh = meshInfo;
    dummyLeadField.files = files;
end

function out = buildReport(t1File, opts, files, names, stimulusNames, referenceElectrode, ...
        candidateSnapshot, candidateVox, meshInfo)
    out = struct();
    out.createdOn = char(datetime('now'));
    out.dummy = true;
    out.warning = 'Synthetic dummy lead field: do not use for science or interpretation.';
    out.t1File = t1File;
    out.candidateMode = 'capMaker';
    out.electrodeNames = names(:);
    out.stimulusElectrodeNames = stimulusNames(:);
    out.referenceElectrode = referenceElectrode;
    out.candidateLocationsSnapshot = candidateSnapshot;
    out.candidateVoxelCoordinates = candidateVox;
    out.simulationTag = opts.simulationTag;
    out.resampling = 'off';
    out.execute = false;
    out.meshSpacingMm = opts.meshSpacingMm;
    out.fieldScale = opts.fieldScale;
    out.mesh = meshInfo;
    out.leadFieldResultMat = files.roastResultMat;
    out.roastOptionsMat = files.roastOptionsMat;
    out.meshMat = files.meshMat;
    out.reportMat = files.requestMat;
    out.validationRecipe = makeValidationRecipe(names, referenceElectrode);
end

function recipe = makeValidationRecipe(names, referenceElectrode)
    stim = names(~strcmpi(names, referenceElectrode));
    if isempty(stim)
        recipe = {};
    else
        recipe = {stim{1}, 1, referenceElectrode, -1};
    end
end
