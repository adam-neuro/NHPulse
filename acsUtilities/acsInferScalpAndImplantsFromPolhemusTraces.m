function out = acsInferScalpAndImplantsFromPolhemusTraces(surfaceSource, traceInputs, varargin)
% ACSINFERSCALPANDIMPLANTSFROMPOLHEMUSTRACES Combine multiple Polhemus traces.
%
% out = acsInferScalpAndImplantsFromPolhemusTraces(surfaceSource, traceInputs)
% collects scalp and implant traces from several acsPolhemus sessions or
% acsVisualizePolhemusTraceOnHead outputs, then optionally builds a warped
% scalp cache and implant keepout products. The intent is to treat each
% Polhemus run as a noisy measurement of the same physical head.
%
% surfaceSource may be a capMaker skin cache, layout, triangulation, or MAT
% report accepted by acsWarpScalpSurfaceToPolhemusTrace.
%
% traceInputs may be a cell array of MAT/JSON filenames, Polhemus session
% structs, registration structs, or trace QC structs. Raw Polhemus sessions
% require modelFiducials so they can first be registered into the model frame.
%
% Name-value options:
%   modelFiducials          : acsSelectModelFiducials output/file for raw sessions [[]]
%   fiducialLabels          : labels used for raw session registration ['auto']
%   fiducialWeights         : optional fiducial weights [[]]
%   transformType           : 'rigid' or 'similarity' ['rigid']
%   scalpTracePatterns      : trace-set name patterns used as scalp [{'scalp'}]
%   implantNames            : implant/object names to combine [{'headpost'}]
%   implantTracePatterns    : extra trace-set name patterns for implants [{}]
%   minTracePoints          : minimum points per selected trace set [3]
%   fallbackScalpMode       : 'largestNonImplant' or 'none' ['largestNonImplant']
%   outputDir               : folder for reports and derived products ['']
%   outputTag               : stem tag ['multiTrace']
%   force                   : overwrite derived products [false]
%   makeScalpWarp           : call acsWarpScalpSurfaceToPolhemusTrace [true]
%   scalpWarpOptions        : struct of extra options for scalp warp [struct()]
%   makeImplantExclusions   : call acsMakeImplantExclusionFromPolhemusTrace [true]
%   implantExclusionOptions : struct of extra options for implant keepouts [struct()]
%   makeHeadpostPlacement   : optionally call acsPlanHeadpostPlacement [false]
%   headpostPlacementOptions: struct of extra options for headpost placement [struct()]
%   maskFile                : ROAST mask for optional headpost placement ['']
%   showFigures             : show downstream QC figures [false]
%   saveFigures             : save downstream QC figures [false]
%   verbose                 : print summary [true]

    if nargin < 2 || isempty(traceInputs)
        error('acsInferScalpAndImplantsFromPolhemusTraces:MissingInput', ...
            'Provide a surface source and one or more Polhemus trace inputs.');
    end

    opts = parseInputs(varargin{:});
    addLocalDependencies();

    traceInputs = normalizeTraceInputs(traceInputs);
    opts = resolveOutputOptions(surfaceSource, opts);

    overlays = cell(numel(traceInputs), 1);
    overlayInfo = repmat(emptyOverlayInfo(), numel(traceInputs), 1);
    for i = 1:numel(traceInputs)
        [overlays{i}, overlayInfo(i)] = resolveTraceOverlay( ...
            traceInputs{i}, surfaceSource, opts, i);
    end

    [scalpOverlay, scalpInfo] = combineScalpTraceSets(overlays, opts);
    implantOverlays = combineImplantTraceSets(overlays, opts);

    if ~isempty(scalpOverlay.traceSets)
        saveTraceOverlay(scalpOverlay, opts.scalpTraceQcFile, 'scalpTraceQc');
    end
    for i = 1:numel(implantOverlays)
        saveTraceOverlay(implantOverlays(i).overlay, ...
            implantOverlays(i).traceQcFile, 'implantTraceQc');
    end

    scalpWarp = struct();
    surfaceForImplants = surfaceSource;
    if opts.makeScalpWarp && ~isempty(scalpOverlay.traceSets)
        warpArgs = mergeOptionStruct(opts.scalpWarpOptions, struct( ...
            'outputFile', opts.scalpWarpFile, ...
            'outputTag', [opts.outputTag '_scalpWarp'], ...
            'force', opts.force, ...
            'showFigures', opts.showFigures, ...
            'saveFigures', opts.saveFigures, ...
            'verbose', opts.verbose));
        scalpWarp = acsWarpScalpSurfaceToPolhemusTrace( ...
            surfaceSource, scalpOverlay, warpArgs{:});
        if isfield(scalpWarp, 'outputFile') && ~isempty(scalpWarp.outputFile)
            surfaceForImplants = scalpWarp.outputFile;
        end
    elseif opts.makeScalpWarp
        warning('acsInferScalpAndImplantsFromPolhemusTraces:NoScalpTraces', ...
            'No matching scalp traces were found; skipping scalp warp.');
    end

    implantProducts = repmat(emptyImplantProduct(), numel(implantOverlays), 1);
    for i = 1:numel(implantOverlays)
        item = implantOverlays(i);
        implantProducts(i).name = item.name;
        implantProducts(i).traceQcFile = item.traceQcFile;
        implantProducts(i).nTracePoints = item.nTracePoints;
        if opts.makeImplantExclusions && item.nTracePoints >= opts.minTracePoints
            exArgs = mergeOptionStruct(opts.implantExclusionOptions, struct( ...
                'objectName', item.name, ...
                'outputFile', item.exclusionFile, ...
                'outputTag', [opts.outputTag '_' safeName(item.name) 'Exclusion'], ...
                'force', opts.force, ...
                'showFigures', opts.showFigures, ...
                'saveFigures', opts.saveFigures, ...
                'verbose', opts.verbose));
            implantProducts(i).exclusion = ...
                acsMakeImplantExclusionFromPolhemusTrace( ...
                item.overlay, surfaceForImplants, exArgs{:});
            if isfield(implantProducts(i).exclusion, 'outputFile')
                implantProducts(i).exclusionFile = ...
                    implantProducts(i).exclusion.outputFile;
            else
                implantProducts(i).exclusionFile = item.exclusionFile;
            end
        end
    end

    headpostPlacement = struct();
    if opts.makeHeadpostPlacement
        headpostIdx = find(strcmpi({implantOverlays.name}, 'headpost'), 1);
        if isempty(headpostIdx) && ~isempty(implantOverlays)
            headpostIdx = 1;
            warning('acsInferScalpAndImplantsFromPolhemusTraces:HeadpostFallback', ...
                'No implant named headpost was found; using "%s" for headpost placement.', ...
                implantOverlays(headpostIdx).name);
        end
        if isempty(headpostIdx)
            warning('acsInferScalpAndImplantsFromPolhemusTraces:NoHeadpostTrace', ...
                'No implant trace is available for optional headpost placement.');
        else
            hpArgs = opts.headpostPlacementOptions;
            if ~isempty(opts.maskFile) && ~isfield(hpArgs, 'maskFile')
                hpArgs.maskFile = opts.maskFile;
            end
            hpArgs = mergeOptionStruct(hpArgs, struct( ...
                'objectName', implantOverlays(headpostIdx).name, ...
                'outputFile', opts.headpostPlacementFile, ...
                'force', opts.force, ...
                'showFigures', opts.showFigures, ...
                'saveFigures', opts.saveFigures, ...
                'verbose', opts.verbose));
            headpostPlacement = acsPlanHeadpostPlacement( ...
                implantOverlays(headpostIdx).overlay, surfaceForImplants, ...
                hpArgs{:});
        end
    end

    out = struct();
    out.createdOn = char(datetime('now'));
    out.type = 'multiTraceScalpAndImplantInference';
    out.surfaceSource = surfaceSource;
    out.outputDir = opts.outputDir;
    out.outputTag = opts.outputTag;
    out.traceInputs = {overlayInfo.inputLabel}';
    out.inputSummary = overlayInfo;
    out.scalp = scalpInfo;
    out.scalpTraceQcFile = opts.scalpTraceQcFile;
    out.scalpWarp = scalpWarp;
    out.implants = implantProducts;
    out.headpostPlacement = headpostPlacement;
    out.options = opts;
    out.reportMat = opts.reportMat;

    outForSave = stripLargeFields(out);
    ensureDir(fileparts(opts.reportMat));
    save(opts.reportMat, 'outForSave', '-v7.3');

    if opts.verbose
        printSummary(out);
    end
end

function opts = parseInputs(varargin)
    p = inputParser;
    p.FunctionName = 'acsInferScalpAndImplantsFromPolhemusTraces';
    addParameter(p, 'modelFiducials', [], @(x) true);
    addParameter(p, 'fiducialLabels', {'auto'}, ...
        @(x) iscell(x) || isstring(x) || ischar(x));
    addParameter(p, 'fiducialWeights', [], @(x) isempty(x) || isnumeric(x));
    addParameter(p, 'transformType', 'rigid', @(x) ischar(x) || isstring(x));
    addParameter(p, 'scalpTracePatterns', {'scalp'}, ...
        @(x) iscell(x) || isstring(x) || ischar(x));
    addParameter(p, 'implantNames', {'headpost'}, ...
        @(x) iscell(x) || isstring(x) || ischar(x));
    addParameter(p, 'implantTracePatterns', {}, ...
        @(x) iscell(x) || isstring(x) || ischar(x));
    addParameter(p, 'minTracePoints', 3, @isNonnegativeScalar);
    addParameter(p, 'fallbackScalpMode', 'largestNonImplant', ...
        @(x) ischar(x) || isstring(x));
    addParameter(p, 'outputDir', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'outputTag', 'multiTrace', @(x) ischar(x) || isstring(x));
    addParameter(p, 'force', false, @isBoolLike);
    addParameter(p, 'makeScalpWarp', true, @isBoolLike);
    addParameter(p, 'scalpWarpOptions', struct(), @(x) isempty(x) || isstruct(x));
    addParameter(p, 'makeImplantExclusions', true, @isBoolLike);
    addParameter(p, 'implantExclusionOptions', struct(), @(x) isempty(x) || isstruct(x));
    addParameter(p, 'makeHeadpostPlacement', false, @isBoolLike);
    addParameter(p, 'headpostPlacementOptions', struct(), @(x) isempty(x) || isstruct(x));
    addParameter(p, 'maskFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'showFigures', false, @isBoolLike);
    addParameter(p, 'saveFigures', false, @isBoolLike);
    addParameter(p, 'verbose', true, @isBoolLike);
    parse(p, varargin{:});

    opts = p.Results;
    opts.fiducialLabels = normalizeTextList(opts.fiducialLabels);
    opts.transformType = char(opts.transformType);
    opts.scalpTracePatterns = normalizeTextList(opts.scalpTracePatterns);
    opts.implantNames = normalizeTextList(opts.implantNames);
    opts.implantTracePatterns = normalizeTextList(opts.implantTracePatterns);
    opts.minTracePoints = round(double(opts.minTracePoints));
    opts.fallbackScalpMode = normalizeFallbackScalpMode(opts.fallbackScalpMode);
    opts.outputDir = expandUserPath(char(opts.outputDir));
    opts.outputTag = safeName(char(opts.outputTag));
    opts.force = logical(opts.force);
    opts.makeScalpWarp = logical(opts.makeScalpWarp);
    if isempty(opts.scalpWarpOptions), opts.scalpWarpOptions = struct(); end
    opts.makeImplantExclusions = logical(opts.makeImplantExclusions);
    if isempty(opts.implantExclusionOptions), opts.implantExclusionOptions = struct(); end
    opts.makeHeadpostPlacement = logical(opts.makeHeadpostPlacement);
    if isempty(opts.headpostPlacementOptions), opts.headpostPlacementOptions = struct(); end
    opts.maskFile = expandUserPath(char(opts.maskFile));
    opts.showFigures = logical(opts.showFigures);
    opts.saveFigures = logical(opts.saveFigures);
    opts.verbose = logical(opts.verbose);
end

function mode = normalizeFallbackScalpMode(mode)
    mode = lower(strtrim(char(mode)));
    switch regexprep(mode, '[\s_\-]+', '')
        case {'largestnonimplant', 'largest', 'auto'}
            mode = 'largestNonImplant';
        case {'none', 'off', 'strict'}
            mode = 'none';
        otherwise
            error('acsInferScalpAndImplantsFromPolhemusTraces:BadFallbackMode', ...
                'fallbackScalpMode must be ''largestNonImplant'' or ''none''.');
    end
end

function tf = isBoolLike(x)
    tf = (islogical(x) || isnumeric(x)) && isscalar(x);
end

function tf = isNonnegativeScalar(x)
    tf = isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0;
end

function addLocalDependencies()
    repoRoot = fileparts(fileparts(mfilename('fullpath')));
    addpath(repoRoot);
    addpath(fullfile(repoRoot, 'acsUtilities'));
    addpath(fullfile(repoRoot, 'capMaker', 'core'));
    addpath(fullfile(repoRoot, 'capMaker', 'geometry'));
end

function inputs = normalizeTraceInputs(value)
    if iscell(value)
        inputs = value(:);
    elseif isstring(value)
        inputs = cellstr(value(:));
    elseif ischar(value)
        inputs = {value};
    elseif isstruct(value) && numel(value) > 1
        inputs = num2cell(value(:));
    else
        inputs = {value};
    end
end

function opts = resolveOutputOptions(surfaceSource, opts)
    if isempty(opts.outputDir)
        opts.outputDir = defaultOutputDir(surfaceSource);
    end
    ensureDir(opts.outputDir);
    stem = opts.outputTag;
    opts.reportMat = fullfile(opts.outputDir, [stem '_multiTraceInference.mat']);
    opts.scalpTraceQcFile = fullfile(opts.outputDir, ...
        [stem '_combinedScalpTraceQc.mat']);
    opts.scalpWarpFile = fullfile(opts.outputDir, ...
        [stem '_scalpWarp.mat']);
    opts.headpostPlacementFile = fullfile(opts.outputDir, ...
        [stem '_headpostPlacement.mat']);
end

function folder = defaultOutputDir(surfaceSource)
    folder = pwd;
    fileName = '';
    if ischar(surfaceSource) || isstring(surfaceSource)
        fileName = char(surfaceSource);
    elseif isstruct(surfaceSource)
        if isfield(surfaceSource, 'layout') && isfield(surfaceSource.layout, 'skin') && ...
                isfield(surfaceSource.layout.skin, 'cacheFile')
            fileName = surfaceSource.layout.skin.cacheFile;
        elseif isfield(surfaceSource, 'skin') && isfield(surfaceSource.skin, 'cacheFile')
            fileName = surfaceSource.skin.cacheFile;
        elseif isfield(surfaceSource, 'cacheFile')
            fileName = surfaceSource.cacheFile;
        elseif isfield(surfaceSource, 'file')
            fileName = surfaceSource.file;
        end
    end
    if ~isempty(fileName)
        fileName = expandUserPath(fileName);
        if exist(fileName, 'file') == 2
            folder = fileparts(fileName);
        end
    end
end

function [overlay, info] = resolveTraceOverlay(value, surfaceSource, opts, index)
    info = emptyOverlayInfo();
    info.index = index;
    info.inputLabel = inputLabel(value, index);
    raw = tryReadStruct(value);
    if isTraceOverlay(raw)
        overlay = raw;
        info.kind = 'traceOverlay';
    elseif isRegistration(raw)
        overlay = acsVisualizePolhemusTraceOnHead(raw, opts.modelFiducials, ...
            'fiducialLabels', opts.fiducialLabels, ...
            'fiducialWeights', opts.fiducialWeights, ...
            'transformType', opts.transformType, ...
            'meshStage', 'fullHead', ...
            'showFigures', false, ...
            'saveFigures', false, ...
            'closeFigure', true, ...
            'verbose', false);
        info.kind = 'registration';
    else
        if isempty(opts.modelFiducials)
            error('acsInferScalpAndImplantsFromPolhemusTraces:MissingModelFiducials', ...
                ['Input %d appears to be a raw Polhemus session. Pass ', ...
                 'modelFiducials so it can be registered.'], index);
        end
        overlay = acsVisualizePolhemusTraceOnHead(value, opts.modelFiducials, ...
            'fiducialLabels', opts.fiducialLabels, ...
            'fiducialWeights', opts.fiducialWeights, ...
            'transformType', opts.transformType, ...
            'meshStage', 'fullHead', ...
            'showFigures', false, ...
            'saveFigures', false, ...
            'closeFigure', true, ...
            'verbose', false);
        info.kind = 'rawPolhemusRegistered';
    end
    if ~isfield(overlay, 'meshSource') || isempty(overlay.meshSource)
        overlay.meshSource = meshSourceFromSurface(surfaceSource);
    end
    if ~isfield(overlay, 'traceSets') || isempty(overlay.traceSets)
        overlay.traceSets = fallbackTraceSetsFromOverlay(overlay);
    end
    info.nTraceSets = numel(overlay.traceSets);
    info.traceSetNames = traceSetNames(overlay.traceSets);
    info.traceSetPointCounts = arrayfun(@traceSetPointCount, overlay.traceSets);
    if isfield(overlay, 'registrationRmseMm')
        info.registrationRmseMm = overlay.registrationRmseMm;
    elseif isfield(overlay, 'registration') && isfield(overlay.registration, 'rmseMm')
        info.registrationRmseMm = overlay.registration.rmseMm;
    end
end

function info = emptyOverlayInfo()
    info = struct( ...
        'index', NaN, ...
        'inputLabel', '', ...
        'kind', '', ...
        'nTraceSets', 0, ...
        'traceSetNames', {{}}, ...
        'traceSetPointCounts', [], ...
        'registrationRmseMm', NaN);
end

function tf = isTraceOverlay(value)
    tf = isstruct(value) && isfield(value, 'traceSets');
end

function tf = isRegistration(value)
    tf = isstruct(value) && isfield(value, 'transformedSourcePointsMm') && ...
        isfield(value, 'sourceLabels');
end

function [overlay, info] = combineScalpTraceSets(overlays, opts)
    sets = emptyTraceSetArray();
    selected = struct('inputIndex', {}, 'traceSetIndex', {}, ...
        'traceSetName', {}, 'nPoints', {});
    for i = 1:numel(overlays)
        ts = overlays{i}.traceSets;
        rows = findMatchingTraceRows(ts, opts.scalpTracePatterns, opts.minTracePoints);
        if isempty(rows) && strcmp(opts.fallbackScalpMode, 'largestNonImplant')
            rows = largestNonImplantTraceRow(ts, opts);
        end
        for j = rows(:)'
            sets(end + 1, 1) = copyTraceSet(ts(j), i, j); %#ok<AGROW>
            selected(end + 1, 1) = struct( ... %#ok<AGROW>
                'inputIndex', i, ...
                'traceSetIndex', j, ...
                'traceSetName', char(getOptionalField(ts(j), 'name', sprintf('trace%d', j))), ...
                'nPoints', traceSetPointCount(ts(j)));
        end
    end
    overlay = makeCombinedOverlay(overlays, sets, 'combined scalp traces');
    info = struct();
    info.nTraceSets = numel(sets);
    info.nTracePoints = traceSetArrayPointCount(sets);
    info.selectedTraceSets = selected;
    info.patterns = opts.scalpTracePatterns(:);
    info.fallbackScalpMode = opts.fallbackScalpMode;
end

function implantOverlays = combineImplantTraceSets(overlays, opts)
    names = opts.implantNames(:);
    implantOverlays = repmat(emptyImplantOverlay(), numel(names), 1);
    for n = 1:numel(names)
        implantName = names{n};
        patterns = uniqueTextList([implantName; ...
            implantAliasPatterns(implantName); opts.implantTracePatterns(:)]);
        sets = emptyTraceSetArray();
        for i = 1:numel(overlays)
            ts = overlays{i}.traceSets;
            rows = findMatchingTraceRows(ts, patterns, opts.minTracePoints);
            for j = rows(:)'
                sets(end + 1, 1) = copyTraceSet(ts(j), i, j); %#ok<AGROW>
            end
        end
        overlay = makeCombinedOverlay(overlays, sets, ...
            ['combined ' implantName ' traces']);
        safeImplant = safeName(implantName);
        implantOverlays(n).name = implantName;
        implantOverlays(n).overlay = overlay;
        implantOverlays(n).nTraceSets = numel(sets);
        implantOverlays(n).nTracePoints = traceSetArrayPointCount(sets);
        implantOverlays(n).traceQcFile = fullfile(opts.outputDir, ...
            [opts.outputTag '_' safeImplant '_combinedTraceQc.mat']);
        implantOverlays(n).exclusionFile = fullfile(opts.outputDir, ...
            [opts.outputTag '_' safeImplant '_exclusion.mat']);
    end
end

function item = emptyImplantOverlay()
    item = struct('name', '', 'overlay', struct(), 'nTraceSets', 0, ...
        'nTracePoints', 0, 'traceQcFile', '', 'exclusionFile', '');
end

function item = emptyImplantProduct()
    item = struct('name', '', 'traceQcFile', '', 'nTracePoints', 0, ...
        'exclusion', struct(), 'exclusionFile', '');
end

function rows = findMatchingTraceRows(traceSets, patterns, minPoints)
    rows = [];
    names = traceSetNames(traceSets);
    for i = 1:numel(traceSets)
        if traceSetPointCount(traceSets(i)) < minPoints
            continue;
        end
        if matchesAnyPattern(names{i}, patterns)
            rows(end + 1, 1) = i; %#ok<AGROW>
        end
    end
end

function row = largestNonImplantTraceRow(traceSets, opts)
    row = [];
    if isempty(traceSets)
        return;
    end
    names = traceSetNames(traceSets);
    counts = arrayfun(@traceSetPointCount, traceSets);
    isImplant = false(numel(traceSets), 1);
    implantPatterns = opts.implantTracePatterns(:);
    for n = 1:numel(opts.implantNames)
        implantPatterns = [implantPatterns; opts.implantNames(n); ...
            implantAliasPatterns(opts.implantNames{n})]; %#ok<AGROW>
    end
    implantPatterns = uniqueTextList(implantPatterns);
    for i = 1:numel(names)
        isImplant(i) = matchesAnyPattern(names{i}, implantPatterns);
    end
    usable = find(counts(:) >= opts.minTracePoints & ~isImplant(:));
    if isempty(usable)
        return;
    end
    [~, idx] = max(counts(usable));
    row = usable(idx);
end

function tf = matchesAnyPattern(value, patterns)
    value = normalizeForMatch(value);
    tf = false;
    for i = 1:numel(patterns)
        pat = normalizeForMatch(patterns{i});
        if isempty(pat)
            continue;
        end
        if contains(value, pat)
            tf = true;
            return;
        end
    end
end

function patterns = implantAliasPatterns(implantName)
    key = normalizeForMatch(implantName);
    switch key
        case {'headpost', 'headposttrace'}
            patterns = {'headpost'; 'head post'; 'implant'};
        case {'cilux', 'recordingchamber', 'chamber'}
            patterns = {'cilux'; 'recording chamber'; 'chamber'};
        otherwise
            patterns = {char(implantName)};
    end
end

function value = normalizeForMatch(value)
    value = lower(regexprep(char(value), '[^a-zA-Z0-9]+', ''));
end

function names = traceSetNames(traceSets)
    names = cell(numel(traceSets), 1);
    for i = 1:numel(traceSets)
        names{i} = char(getOptionalField(traceSets(i), ...
            'name', sprintf('trace%d', i)));
    end
end

function n = traceSetPointCount(traceSet)
    n = 0;
    if isfield(traceSet, 'coordinatesMm') && ~isempty(traceSet.coordinatesMm)
        n = size(traceSet.coordinatesMm, 1);
    end
end

function n = traceSetArrayPointCount(traceSets)
    n = 0;
    for i = 1:numel(traceSets)
        n = n + traceSetPointCount(traceSets(i));
    end
end

function out = copyTraceSet(traceSet, inputIndex, traceSetIndex)
    P = double(getOptionalField(traceSet, 'coordinatesMm', zeros(0, 3)));
    if size(P, 2) ~= 3
        P = zeros(0, 3);
    end
    labels = getOptionalLabels(traceSet, size(P, 1), ...
        sprintf('trace%d_%d', inputIndex, traceSetIndex));
    rows = getOptionalField(traceSet, 'rows', (1:size(P, 1))');
    rows = double(rows(:));
    if numel(rows) ~= size(P, 1)
        rows = (1:size(P, 1))';
    end
    name = char(getOptionalField(traceSet, 'name', ...
        sprintf('trace%d_%d', inputIndex, traceSetIndex)));
    out = struct( ...
        'name', sprintf('%s session%d', name, inputIndex), ...
        'coordinatesMm', P, ...
        'labels', {labels(:)}, ...
        'rows', rows(:), ...
        'sourceIndex', inputIndex, ...
        'sourceTraceSetIndex', traceSetIndex, ...
        'sourceTraceSetName', name);
end

function sets = emptyTraceSetArray()
    sets = struct('name', {}, 'coordinatesMm', {}, 'labels', {}, ...
        'rows', {}, 'sourceIndex', {}, 'sourceTraceSetIndex', {}, ...
        'sourceTraceSetName', {});
end

function overlay = makeCombinedOverlay(overlays, traceSets, label)
    overlay = struct();
    overlay.createdOn = char(datetime('now'));
    overlay.type = 'combinedPolhemusTraceOverlay';
    overlay.name = label;
    overlay.meshSource = firstMeshSource(overlays);
    overlay.traceSets = traceSets;
    [coords, labels, rows] = flattenTraceSets(traceSets);
    overlay.coordinatesMm = coords;
    overlay.labels = labels;
    overlay.tracePointRows = rows;
    overlay.nearestHeadVertexDistanceMm = nan(size(coords, 1), 1);
    overlay.traceNearestHeadVertexDistanceMm = overlay.nearestHeadVertexDistanceMm;
end

function source = firstMeshSource(overlays)
    source = struct();
    for i = 1:numel(overlays)
        if isstruct(overlays{i}) && isfield(overlays{i}, 'meshSource') && ...
                ~isempty(overlays{i}.meshSource)
            source = overlays{i}.meshSource;
            return;
        end
    end
end

function [coords, labels, rows] = flattenTraceSets(traceSets)
    coords = zeros(0, 3);
    labels = {};
    rows = zeros(0, 1);
    for i = 1:numel(traceSets)
        P = double(traceSets(i).coordinatesMm);
        n = size(P, 1);
        coords = [coords; P]; %#ok<AGROW>
        labels = [labels; traceSets(i).labels(:)]; %#ok<AGROW>
        rows = [rows; (size(coords, 1) - n + 1:size(coords, 1))']; %#ok<AGROW>
    end
end

function sets = fallbackTraceSetsFromOverlay(overlay)
    sets = emptyTraceSetArray();
    if isfield(overlay, 'coordinatesMm') && ~isempty(overlay.coordinatesMm)
        P = double(overlay.coordinatesMm);
    elseif isfield(overlay, 'transformedSourcePointsMm') && ...
            ~isempty(overlay.transformedSourcePointsMm)
        P = double(overlay.transformedSourcePointsMm);
    else
        return;
    end
    labels = getOptionalLabels(overlay, size(P, 1), 'trace');
    sets(1, 1) = struct('name', 'trace', 'coordinatesMm', P, ...
        'labels', {labels(:)}, 'rows', (1:size(P, 1))', ...
        'sourceIndex', 1, 'sourceTraceSetIndex', 1, ...
        'sourceTraceSetName', 'trace');
end

function labels = getOptionalLabels(S, n, prefix)
    if isfield(S, 'labels') && ~isempty(S.labels)
        labels = normalizeTextList(S.labels);
    elseif isfield(S, 'sourceLabels') && ~isempty(S.sourceLabels)
        labels = normalizeTextList(S.sourceLabels);
    else
        labels = defaultLabels(n, prefix);
    end
    if numel(labels) ~= n
        labels = defaultLabels(n, prefix);
    end
    labels = labels(:);
end

function labels = defaultLabels(n, prefix)
    labels = cell(n, 1);
    for i = 1:n
        labels{i} = sprintf('%s_%03d', prefix, i);
    end
end

function saveTraceOverlay(overlay, fileName, variableName)
    if isempty(fileName)
        return;
    end
    ensureDir(fileparts(fileName));
    switch variableName
        case 'scalpTraceQc'
            scalpTraceQc = overlay; %#ok<NASGU>
            out = overlay; %#ok<NASGU>
            save(fileName, 'scalpTraceQc', 'out', '-v7.3');
        otherwise
            implantTraceQc = overlay; %#ok<NASGU>
            out = overlay; %#ok<NASGU>
            save(fileName, 'implantTraceQc', 'out', '-v7.3');
    end
end

function args = mergeOptionStruct(userOpts, defaults)
    if isempty(userOpts)
        userOpts = struct();
    end
    names = fieldnames(defaults);
    merged = userOpts;
    for i = 1:numel(names)
        if ~isfield(merged, names{i}) || isempty(merged.(names{i}))
            merged.(names{i}) = defaults.(names{i});
        end
    end
    args = structToNameValue(merged);
end

function args = structToNameValue(S)
    names = fieldnames(S);
    args = cell(1, 2 * numel(names));
    for i = 1:numel(names)
        args{2 * i - 1} = names{i};
        args{2 * i} = S.(names{i});
    end
end

function source = meshSourceFromSurface(surfaceSource)
    source = struct('type', '', 'file', '', 'cacheFile', '', 'label', '');
    if ischar(surfaceSource) || isstring(surfaceSource)
        source.file = expandUserPath(char(surfaceSource));
        source.cacheFile = source.file;
        source.type = 'skinCache';
        source.label = fileStem(source.file);
    elseif isstruct(surfaceSource)
        if isfield(surfaceSource, 'layout') && isfield(surfaceSource.layout, 'skin') && ...
                isfield(surfaceSource.layout.skin, 'cacheFile')
            source = meshSourceFromSurface(surfaceSource.layout.skin.cacheFile);
        elseif isfield(surfaceSource, 'cacheFile')
            source = meshSourceFromSurface(surfaceSource.cacheFile);
        elseif isfield(surfaceSource, 'file')
            source = meshSourceFromSurface(surfaceSource.file);
        end
    end
end

function raw = tryReadStruct(value)
    raw = value;
    if ~(ischar(value) || isstring(value))
        return;
    end
    fileName = expandUserPath(char(value));
    if exist(fileName, 'file') ~= 2
        return;
    end
    [~, ~, ext] = fileparts(fileName);
    try
        switch lower(ext)
            case '.mat'
                S = load(fileName);
                raw = firstStruct(S);
            case '.json'
                raw = jsondecode(fileread(fileName));
        end
    catch
        raw = value;
    end
end

function value = firstStruct(S)
    preferred = {'out', 'outForSave', 'scalpTraceQc', 'implantTraceQc', ...
        'registration', 'headpostTraceQc'};
    for i = 1:numel(preferred)
        if isfield(S, preferred{i}) && isstruct(S.(preferred{i}))
            value = S.(preferred{i});
            return;
        end
    end
    names = fieldnames(S);
    for i = 1:numel(names)
        if isstruct(S.(names{i}))
            value = S.(names{i});
            return;
        end
    end
    value = S;
end

function label = inputLabel(value, index)
    if ischar(value) || isstring(value)
        label = char(value);
    elseif isstruct(value) && isfield(value, 'name') && ~isempty(value.name)
        label = char(value.name);
    else
        label = sprintf('input%d', index);
    end
end

function list = normalizeTextList(value)
    if isempty(value)
        list = {};
    elseif iscell(value)
        list = cellstr(value(:));
    elseif isstring(value)
        list = cellstr(value(:));
    elseif ischar(value)
        if size(value, 1) == 1
            list = {char(value)};
        else
            list = cellstr(value);
        end
    else
        list = cellstr(value(:));
    end
    list = list(:);
end

function out = uniqueTextList(list)
    list = normalizeTextList(list);
    [~, idx] = unique(lower(list), 'stable');
    out = list(sort(idx));
end

function out = stripLargeFields(out)
    if isfield(out, 'scalpWarp') && isfield(out.scalpWarp, 'figure')
        out.scalpWarp = rmfield(out.scalpWarp, 'figure');
    end
    if isfield(out, 'headpostPlacement') && ...
            isfield(out.headpostPlacement, 'figure')
        out.headpostPlacement = rmfield(out.headpostPlacement, 'figure');
    end
    if isfield(out, 'implants')
        for i = 1:numel(out.implants)
            if isfield(out.implants(i), 'exclusion') && ...
                    isfield(out.implants(i).exclusion, 'figure')
                out.implants(i).exclusion = rmfield(out.implants(i).exclusion, 'figure');
            end
        end
    end
end

function printSummary(out)
    fprintf('\nMulti-trace scalp/implant inference\n');
    fprintf('  trace inputs: %d\n', numel(out.traceInputs));
    fprintf('  scalp trace sets: %d\n', out.scalp.nTraceSets);
    fprintf('  scalp trace points: %d\n', out.scalp.nTracePoints);
    if isfield(out.scalpWarp, 'outputFile') && ~isempty(out.scalpWarp.outputFile)
        fprintf('  scalp warp: %s\n', out.scalpWarp.outputFile);
    end
    for i = 1:numel(out.implants)
        fprintf('  implant %s: %d trace points\n', ...
            out.implants(i).name, out.implants(i).nTracePoints);
        if isfield(out.implants(i), 'exclusionFile') && ...
                ~isempty(out.implants(i).exclusionFile)
            fprintf('    exclusion: %s\n', out.implants(i).exclusionFile);
        end
    end
    fprintf('  report: %s\n\n', out.reportMat);
end

function ensureDir(folder)
    if ~isempty(folder) && exist(folder, 'dir') ~= 7
        mkdir(folder);
    end
end

function fileName = expandUserPath(fileName)
    if isempty(fileName)
        return;
    end
    if startsWith(fileName, '~')
        homeDir = char(java.lang.System.getProperty('user.home'));
        fileName = fullfile(homeDir, fileName(2:end));
    end
end

function stem = fileStem(fileName)
    [~, stem, ~] = fileparts(char(fileName));
end

function value = safeName(value)
    value = regexprep(char(value), '[^\w\-]+', '_');
    value = regexprep(value, '_+', '_');
    value = regexprep(value, '^_|_$', '');
    if isempty(value)
        value = 'multiTrace';
    end
end

function value = getOptionalField(S, fieldName, defaultValue)
    if isstruct(S) && isfield(S, fieldName) && ~isempty(S.(fieldName))
        value = S.(fieldName);
    else
        value = defaultValue;
    end
end
