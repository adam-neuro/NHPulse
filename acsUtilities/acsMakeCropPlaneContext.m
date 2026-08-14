function context = acsMakeCropPlaneContext(skinCacheFile, varargin)
% ACSMAKECROPPLANECONTEXT Convert capMaker exclusions to crop GUI overlays.
%
% context = acsMakeCropPlaneContext(skinCacheFile, 'exclusionFiles', files)
% reads capMaker print-frame exclusion products and returns fields that can
% be passed as skinMeshFromMPRAGE cropGuiOptions. The output coordinates are
% in the stable capMaker pre-crop world frame used by selectCropPlane.

    if nargin < 1 || isempty(skinCacheFile)
        error('acsMakeCropPlaneContext:MissingSkinCache', ...
            'Provide a capMaker skin cache file.');
    end

    opts = parseInputs(varargin{:});
    skinCacheFile = expandUserPath(char(skinCacheFile));
    if exist(skinCacheFile, 'file') ~= 2
        error('acsMakeCropPlaneContext:SkinCacheNotFound', ...
            'Skin cache file not found: %s', skinCacheFile);
    end
    Sskin = load(skinCacheFile, 'meta');
    if ~isfield(Sskin, 'meta')
        error('acsMakeCropPlaneContext:MissingMeta', ...
            'Skin cache does not contain capMaker metadata: %s', skinCacheFile);
    end

    files = normalizeFileList(opts.exclusionFiles);
    points = zeros(0, 3);
    pointLabels = {};
    curves = {};
    curveLabels = {};
    sources = repmat(struct('file', '', 'name', ''), 0, 1);

    for i = 1:numel(files)
        fileName = files{i};
        if isempty(fileName) || exist(fileName, 'file') ~= 2
            continue;
        end
        S = loadPreferredStructFromMat(fileName, ...
            {'exclusion', 'outForSave', 'outSaved', 'out'});
        if isfield(S, 'exclusion') && isstruct(S.exclusion)
            S = S.exclusion;
        end
        name = char(getOptionalField(S, 'name', stripExtension(getFileName(fileName))));
        frame = char(getOptionalField(S, 'coordinateFrame', ''));
        if ~strcmpi(frame, 'capMakerPrintMm')
            warning('acsMakeCropPlaneContext:SkippingNonPrintFrame', ...
                'Skipping %s because coordinateFrame is "%s".', fileName, frame);
            continue;
        end

        P = optionalPointMatrix(S, {'projectedCoordinatesMm', ...
            'basePerimeterPrintMm'});
        if ~isempty(P)
            Pworld = printMmToPreCropWorld(P, Sskin.meta);
            points = [points; Pworld]; %#ok<AGROW>
        end

        B = optionalPointMatrix(S, {'keepoutBoundaryMm', ...
            'basePerimeterPrintMm'});
        if ~isempty(B)
            curves{end + 1, 1} = printMmToPreCropWorld(B, Sskin.meta); %#ok<AGROW>
            curveLabels{end + 1, 1} = name; %#ok<AGROW>
        end
        sources(end + 1, 1) = struct('file', fileName, 'name', name); %#ok<AGROW>
    end

    context = struct();
    context.contextPointsWorldMm = points;
    context.contextPointLabels = pointLabels;
    context.contextCurvesWorldMm = curves;
    context.contextCurveLabels = curveLabels;
    context.sources = sources;
    context.skinCacheFile = skinCacheFile;
    context.coordinateFrame = 'capMakerPreCropWorldMm';
end

function S = loadPreferredStructFromMat(fileName, preferredNames)
    info = whos('-file', fileName);
    names = {info.name};
    for i = 1:numel(preferredNames)
        hit = find(strcmp(names, preferredNames{i}), 1);
        if isempty(hit) || ~strcmp(info(hit).class, 'struct')
            continue;
        end
        raw = load(fileName, preferredNames{i});
        S = raw.(preferredNames{i});
        return;
    end
    raw = load(fileName);
    S = firstStruct(raw);
end

function opts = parseInputs(varargin)
    p = inputParser;
    p.FunctionName = 'acsMakeCropPlaneContext';
    addParameter(p, 'exclusionFiles', {}, @(x) isempty(x) || ...
        ischar(x) || isstring(x) || iscell(x));
    parse(p, varargin{:});
    opts = p.Results;
end

function files = normalizeFileList(value)
    files = {};
    if isempty(value)
        return;
    end
    if ischar(value) || (isstring(value) && isscalar(value))
        value = {char(value)};
    elseif isstring(value)
        value = cellstr(value(:));
    end
    for i = 1:numel(value)
        if isempty(value{i})
            continue;
        end
        files{end + 1, 1} = expandUserPath(char(value{i})); %#ok<AGROW>
    end
end

function points = optionalPointMatrix(S, names)
    points = zeros(0, 3);
    for i = 1:numel(names)
        name = names{i};
        if isfield(S, name) && ~isempty(S.(name))
            points = double(S.(name));
            if size(points, 2) >= 3
                points = points(:, 1:3);
                return;
            end
        end
    end
end

function pointsWorld = printMmToPreCropWorld(pointsPrint, meta)
    requireCapMakerMeta(meta);
    finalWorld = applyAffineToPoints(meta.print.T_print2world, pointsPrint);
    pointsWorld = (double(meta.align.R) \ finalWorld')';
end

function requireCapMakerMeta(meta)
    ok = isstruct(meta) && isfield(meta, 'print') && ...
        isfield(meta.print, 'T_print2world') && ...
        isfield(meta, 'align') && isfield(meta.align, 'R');
    if ~ok
        error('acsMakeCropPlaneContext:BadSkinMeta', ...
            'Skin metadata lacks print.T_print2world or align.R.');
    end
end

function pointsOut = applyAffineToPoints(M, pointsIn)
    pointsHom = [double(pointsIn), ones(size(pointsIn, 1), 1)];
    pointsHom = (double(M) * pointsHom')';
    pointsOut = pointsHom(:, 1:3);
end

function value = getOptionalField(S, fieldName, defaultValue)
    if isstruct(S) && isfield(S, fieldName) && ~isempty(S.(fieldName))
        value = S.(fieldName);
    else
        value = defaultValue;
    end
end

function S = firstStruct(raw)
    preferred = {'outForSave', 'outSaved', 'exclusion', 'out'};
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
    error('acsMakeCropPlaneContext:NoStructInFile', ...
        'MAT file does not contain a readable struct.');
end

function fileName = getFileName(fileName)
    [~, stem, ext] = fileparts(fileName);
    fileName = [stem ext];
end

function stem = stripExtension(fileName)
    [~, stem] = fileparts(fileName);
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
