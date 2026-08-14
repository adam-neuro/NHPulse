function [centers, radii, info] = acsPlacementExclusionsFromImplantFiles(filesIn, varargin)
% ACSPLACEMENTEXCLUSIONSFROMIMPLANTFILES Summarize implant keepouts for placement.
%
% [centers, radii] = acsPlacementExclusionsFromImplantFiles(files) reads saved
% implant/chamber/headpost exclusion MAT files and returns conservative
% circular exclusion regions in capMaker print-frame millimeters. These are
% intended for electrode placement targetOptions.exclusionCenters and
% targetOptions.exclusionRadiusMM. Manufacturing should still consume the
% richer polygon exclusion files directly.
%
% Name-value options:
%   extraMarginMm : added radius margin [0]
%   verbose       : print warnings/progress [true]

    opts = parseInputs(varargin{:});
    files = normalizeFiles(filesIn);

    centers = zeros(0, 3);
    radii = zeros(0, 1);
    info = struct('files', {files}, ...
        'usedFiles', {{}}, ...
        'skippedFiles', {{}}, ...
        'extraMarginMm', opts.extraMarginMm);

    for i = 1:numel(files)
        fileName = files{i};
        if exist(fileName, 'file') ~= 2
            info.skippedFiles{end + 1, 1} = fileName; %#ok<AGROW>
            if opts.verbose
                warning('acsPlacementExclusionsFromImplantFiles:MissingFile', ...
                    'Implant exclusion file not found: %s', fileName);
            end
            continue;
        end
        try
            exclusion = readExclusion(fileName);
            [center, radius, sourceField] = circularPlacementExclusion(exclusion);
        catch ME
            center = [];
            radius = [];
            sourceField = '';
            if opts.verbose
                warning('acsPlacementExclusionsFromImplantFiles:ReadFailed', ...
                    'Could not read placement exclusion from %s: %s', ...
                    fileName, ME.message);
            end
        end
        if isempty(center)
            info.skippedFiles{end + 1, 1} = fileName; %#ok<AGROW>
            if opts.verbose
                warning('acsPlacementExclusionsFromImplantFiles:NoGeometry', ...
                    'No capMaker print-frame keepout geometry found in %s.', fileName);
            end
            continue;
        end
        centers(end + 1, :) = center; %#ok<AGROW>
        radii(end + 1, 1) = radius + opts.extraMarginMm; %#ok<AGROW>
        info.usedFiles{end + 1, 1} = fileName; %#ok<AGROW>
        info.items(numel(info.usedFiles), 1) = struct( ... %#ok<AGROW>
            'file', fileName, ...
            'sourceField', sourceField, ...
            'centerMm', center, ...
            'radiusMm', radius + opts.extraMarginMm);
    end
end

function opts = parseInputs(varargin)
    p = inputParser;
    p.FunctionName = 'acsPlacementExclusionsFromImplantFiles';
    addParameter(p, 'extraMarginMm', 0, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0);
    addParameter(p, 'verbose', true, @isBoolLike);
    parse(p, varargin{:});

    opts = p.Results;
    opts.extraMarginMm = double(opts.extraMarginMm);
    opts.verbose = logical(opts.verbose);
end

function tf = isBoolLike(x)
    tf = (islogical(x) || isnumeric(x)) && isscalar(x);
end

function files = normalizeFiles(filesIn)
    if isempty(filesIn)
        files = {};
    elseif iscell(filesIn)
        files = cellfun(@char, filesIn(:), 'UniformOutput', false);
    elseif isstring(filesIn)
        files = cellstr(filesIn(:));
    elseif ischar(filesIn)
        files = cellstr(filesIn);
    else
        error('acsPlacementExclusionsFromImplantFiles:BadFiles', ...
            'files must be a filename, string array, or cell array of filenames.');
    end
    keep = ~cellfun(@isempty, files);
    files = files(keep);
end

function exclusion = readExclusion(fileName)
    S = loadPreferredStructFromMat(fileName, ...
        {'exclusion', 'outForSave', 'outSaved', 'out'});
    if isfield(S, 'exclusion') && isstruct(S.exclusion)
        exclusion = S.exclusion;
    else
        exclusion = S;
    end
    exclusion.sourceFile = fileName;
end

function value = loadPreferredStructFromMat(fileName, preferredNames)
    info = whos('-file', fileName);
    names = {info.name};
    for i = 1:numel(preferredNames)
        hit = find(strcmp(names, preferredNames{i}), 1);
        if isempty(hit) || ~strcmp(info(hit).class, 'struct')
            continue;
        end
        raw = load(fileName, preferredNames{i});
        value = raw.(preferredNames{i});
        return;
    end
    raw = load(fileName);
    value = firstStructInLoadedMat(raw, fileName);
end

function value = firstStructInLoadedMat(raw, fileName)
    names = fieldnames(raw);
    for i = 1:numel(names)
        if isstruct(raw.(names{i}))
            value = raw.(names{i});
            return;
        end
    end
    error('acsPlacementExclusionsFromImplantFiles:NoStructInMat', ...
        'MAT file does not contain a readable struct: %s', fileName);
end

function [center, radius, sourceField] = circularPlacementExclusion(exclusion)
    center = [];
    radius = [];
    sourceField = '';
    points = zeros(0, 3);

    frame = '';
    if isfield(exclusion, 'coordinateFrame') && ~isempty(exclusion.coordinateFrame)
        frame = char(exclusion.coordinateFrame);
    end
    if ~isempty(frame) && ~strcmpi(frame, 'capMakerPrintMm')
        return;
    end
    hasPrintFrame = strcmpi(frame, 'capMakerPrintMm');

    if isfield(exclusion, 'basePerimeterPrintMm') && ...
            ~isempty(exclusion.basePerimeterPrintMm)
        points = double(exclusion.basePerimeterPrintMm);
        sourceField = 'basePerimeterPrintMm';
    elseif ~hasPrintFrame
        return;
    elseif isfield(exclusion, 'keepoutBoundaryMm') && ~isempty(exclusion.keepoutBoundaryMm)
        points = double(exclusion.keepoutBoundaryMm);
        sourceField = 'keepoutBoundaryMm';
    elseif isfield(exclusion, 'keepoutPolyX') && isfield(exclusion, 'keepoutPolyY') && ...
            ~isempty(exclusion.keepoutPolyX)
        x = double(exclusion.keepoutPolyX(:));
        y = double(exclusion.keepoutPolyY(:));
        points = [x, y, zeros(size(x))];
        sourceField = 'keepoutPolyX/Y';
    elseif isfield(exclusion, 'projectedCoordinatesMm') && ...
            ~isempty(exclusion.projectedCoordinatesMm)
        points = double(exclusion.projectedCoordinatesMm);
        sourceField = 'projectedCoordinatesMm';
    end

    if isempty(points) || size(points, 2) < 2
        return;
    end
    points = points(all(isfinite(points(:, 1:2)), 2), :);
    if isempty(points)
        return;
    end
    if size(points, 2) < 3
        points(:, 3) = 0;
    end

    center = [mean(points(:, 1:2), 1), median(points(:, 3))];
    radius = max(sqrt(sum((points(:, 1:2) - center(1:2)) .^ 2, 2)));
    if isfield(exclusion, 'keepoutRadiusMm') && ...
            isnumeric(exclusion.keepoutRadiusMm) && ...
            isscalar(exclusion.keepoutRadiusMm) && ...
            isfinite(exclusion.keepoutRadiusMm)
        radius = max(radius, double(exclusion.keepoutRadiusMm));
    end
end
