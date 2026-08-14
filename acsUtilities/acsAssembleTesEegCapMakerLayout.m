function out = acsAssembleTesEegCapMakerLayout(baseLayout, sparseResult, varargin)
% ACSASSEMBLETESEEGCAPMAKERLAYOUT Combine optimized tES sites with EEG sites.
%
% out = acsAssembleTesEegCapMakerLayout(layout, sparse)
% selects tES electrode sites from an acsOptimizeSparseRoastLeadField result,
% places additional EEG sites on the same capMaker scalp surface while
% excluding the tES sites, and writes one combined capMaker/ROAST custom
% locations file.
%
% Name-value options:
%   nTes                  : number of active tES electrodes to keep [8]
%   nEeg                  : number of EEG electrodes to add [8]
%   tesPrefix             : combined-layout tES name prefix ['customTES']
%   eegPrefix             : combined-layout EEG name prefix ['customEEG']
%   eegPreferSymmetry     : place EEG sites as bilateral pairs [false]
%   eegMidlineMarginMM    : EEG midline exclusion; [] means 0 when asymmetric
%   eegExclusionRadiusMm  : EEG center exclusion radius around tES [12]
%   eegTargetOptions      : overrides for EEG autoElectrodeTargets [struct()]
%   earExclusionMode      : 'auto', 'always', or 'never' ['auto']
%   earExclusionFile      : explicit saved ear-exclusion MAT file ['']
%   strapExclusionMode    : 'auto', 'always', or 'none' ['auto']
%   strapRostralOffsetMm  : strap keepout offset rostral to ear edge [0]
%   strapWidthMm          : nominal chin-strap width for keepout [10]
%   strapMarginMm         : extra strap/electrode placement margin [2]
%   extraExclusionCenters : additional capMaker print-mm exclusion centers [[]]
%   extraExclusionRadiusMm: scalar or vector radii for extra exclusions [[]]
%   skinCacheFile         : explicit capMaker scalp cache for EEG placement ['']
%   layoutSnapWarnDistanceMm : warn if final sites are this far off skin [1]
%   layoutSnapErrorDistanceMm: error if final sites are this far off skin [3]
%   outputFile            : combined customLocations path ['']
%   forceLayout           : overwrite generated layout files [true]
%   force                 : legacy alias for forceLayout [true]
%   showFigures           : show QC figures [false]
%   saveFigures           : save QC figures [false]
%   verbose               : print progress [true]

    if nargin < 2
        error('acsAssembleTesEegCapMakerLayout:MissingInput', ...
            'Provide a capMaker layout and sparse targeting result.');
    end
    opts = parseInputs(varargin{:});
    addLocalDependencies();

    layout = readLayout(baseLayout);
    sparse = readSparseResult(sparseResult);
    requireFields(layout, {'t1File', 'maskFile', 'names', ...
        'layoutCoordinatesMm', 'targetOptions'});
    requireFields(sparse, {'selectedNames', 'selectedCurrentsMa'});

    [tesNamesSource, tesPrintMm, tesCurrentsMa] = selectTesSites( ...
        layout, sparse, opts.nTes);
    eegTargetOptions = makeEegTargetOptions(layout.targetOptions, ...
        opts.eegTargetOptions, tesPrintMm, opts);
    skinLayoutInput = layout;
    if ~isempty(opts.skinCacheFile)
        skinLayoutInput = opts.skinCacheFile;
    end
    [eegTargetOptions, earExclusions] = acsApplyEarExclusionsToTargetOptions(eegTargetOptions, skinLayoutInput, ...
        'editMode', opts.earExclusionMode, ...
        'outputFile', opts.earExclusionFile, ...
        'showFigures', opts.showFigures, ...
        'saveFigures', opts.saveFigures, ...
        'showStrapPreview', ~strcmp(opts.strapExclusionMode, 'none'), ...
        'zBedMm', opts.zBedMm, ...
        'strapRostralOffsetMm', opts.strapRostralOffsetMm, ...
        'strapWidthMm', opts.strapWidthMm, ...
        'holderOutsideDiaMm', opts.holderOutsideDiaMm, ...
        'strapMarginMm', opts.strapMarginMm, ...
        'strapExclusionRadiusMm', opts.strapExclusionRadiusMm, ...
        'strapLateralLengthMm', opts.strapLateralLengthMm, ...
        'strapSampleSpacingMm', opts.strapSampleSpacingMm, ...
        'verbose', opts.verbose);
    [eegTargetOptions, strapExclusion] = acsAddStrapExclusionsToTargetOptions( ...
        eegTargetOptions, earExclusions, ...
        'mode', opts.strapExclusionMode, ...
        'zBedMm', opts.zBedMm, ...
        'strapRostralOffsetMm', opts.strapRostralOffsetMm, ...
        'strapWidthMm', opts.strapWidthMm, ...
        'holderOutsideDiaMm', opts.holderOutsideDiaMm, ...
        'strapMarginMm', opts.strapMarginMm, ...
        'strapExclusionRadiusMm', opts.strapExclusionRadiusMm, ...
        'strapLateralLengthMm', opts.strapLateralLengthMm, ...
        'strapSampleSpacingMm', opts.strapSampleSpacingMm, ...
        'verbose', opts.verbose);

    [folder, stem] = fileparts(layout.t1File);
    if isempty(opts.outputFile)
        opts.outputFile = fullfile(folder, [stem '_tesEeg_customLocations']);
    end
    eegOutputFile = fullfile(folder, [stem '_eegOnly_customLocations']);

    logMsg(opts, 'Placing %d EEG sites while excluding %d tES sites.', ...
        opts.nEeg, size(tesPrintMm, 1));
    eegLayout = acsMakeRoastCapMakerLayout(layout, ...
        'nElectrodes', opts.nEeg, ...
        'electrodeNames', numberedNames(opts.eegPrefix, opts.nEeg), ...
        'targetOptions', eegTargetOptions, ...
        'surfaceSource', 'capMaker', ...
        'skinCacheFile', opts.skinCacheFile, ...
        'outputFile', eegOutputFile, ...
        'earExclusionMode', opts.earExclusionMode, ...
        'earExclusionFile', opts.earExclusionFile, ...
        'force', opts.forceLayout, ...
        'showFigures', opts.showFigures, ...
        'saveFigures', opts.saveFigures, ...
        'verbose', opts.verbose);

    combinedPrintMm = [tesPrintMm; eegLayout.layoutCoordinatesMm];
    combinedNames = [numberedNames(opts.tesPrefix, size(tesPrintMm, 1)); ...
        numberedNames(opts.eegPrefix, opts.nEeg)];
    manualTargetOptions = layout.targetOptions;
    manualTargetOptions.manualTargetsMm = combinedPrintMm;
    manualTargetOptions.placementMode = 'manualTargetsMm';

    logMsg(opts, 'Writing combined tES+EEG layout with %d sites.', ...
        numel(combinedNames));
    combinedLayout = acsMakeRoastCapMakerLayout(layout, ...
        'nElectrodes', numel(combinedNames), ...
        'electrodeNames', combinedNames, ...
        'targetOptions', manualTargetOptions, ...
        'surfaceSource', 'capMaker', ...
        'skinCacheFile', opts.skinCacheFile, ...
        'outputFile', opts.outputFile, ...
        'earExclusionMode', opts.earExclusionMode, ...
        'earExclusionFile', opts.earExclusionFile, ...
        'force', opts.forceLayout, ...
        'showFigures', opts.showFigures, ...
        'saveFigures', opts.saveFigures, ...
        'verbose', opts.verbose);
    combinedSnap = checkCombinedLayoutSnapDistance(combinedLayout, opts);

    out = combinedLayout;
    out.siteRoles = [repmat({'tES'}, size(tesPrintMm, 1), 1); ...
        repmat({'EEG'}, opts.nEeg, 1)];
    out.tesNames = combinedNames(1:size(tesPrintMm, 1));
    out.eegNames = combinedNames(size(tesPrintMm, 1) + (1:opts.nEeg));
    out.sourceTesNames = tesNamesSource(:);
    out.tesCurrentsMa = tesCurrentsMa(:);
    out.eegExclusionRadiusMm = opts.eegExclusionRadiusMm;
    out.eegTargetOptions = eegTargetOptions;
    out.earExclusions = compactExclusionStruct(earExclusions);
    out.strapExclusion = compactExclusionStruct(strapExclusion);
    out.eegOnlyLayout = stripFigure(eegLayout);
    out.combinedSnapDistanceMm = combinedSnap(:);
    out.assemblyOptions = opts;
    out.reportMat = reportMatFile(opts.outputFile);
    save(out.reportMat, 'out');
end

function opts = parseInputs(varargin)
    p = inputParser;
    p.FunctionName = 'acsAssembleTesEegCapMakerLayout';
    addParameter(p, 'nTes', 8, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 1);
    addParameter(p, 'nEeg', 8, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 1);
    addParameter(p, 'tesPrefix', 'customTES', @(x) ischar(x) || isstring(x));
    addParameter(p, 'eegPrefix', 'customEEG', @(x) ischar(x) || isstring(x));
    addParameter(p, 'eegPreferSymmetry', false, @isBoolLike);
    addParameter(p, 'eegMidlineMarginMM', [], ...
        @(x) isempty(x) || (isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0));
    addParameter(p, 'eegExclusionRadiusMm', 12, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0);
    addParameter(p, 'eegTargetOptions', struct(), @(x) isempty(x) || isstruct(x));
    addParameter(p, 'earExclusionMode', 'auto', @(x) ischar(x) || isstring(x));
    addParameter(p, 'earExclusionFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'strapExclusionMode', 'auto', @(x) ischar(x) || isstring(x));
    addParameter(p, 'strapRostralOffsetMm', 0, @isNonnegativeScalar);
    addParameter(p, 'strapWidthMm', 10, @isPositiveScalar);
    addParameter(p, 'strapMarginMm', 2, @isNonnegativeScalar);
    addParameter(p, 'strapExclusionRadiusMm', [], ...
        @(x) isempty(x) || isPositiveScalar(x));
    addParameter(p, 'strapLateralLengthMm', 35, @isPositiveScalar);
    addParameter(p, 'strapSampleSpacingMm', 5, @isPositiveScalar);
    addParameter(p, 'holderOutsideDiaMm', 12, @isPositiveScalar);
    addParameter(p, 'zBedMm', 0, @(x) isnumeric(x) && isscalar(x) && isfinite(x));
    addParameter(p, 'extraExclusionCenters', [], ...
        @(x) isempty(x) || (isnumeric(x) && size(x, 2) == 3));
    addParameter(p, 'extraExclusionRadiusMm', [], ...
        @(x) isempty(x) || (isnumeric(x) && isvector(x) && all(x >= 0)));
    addParameter(p, 'skinCacheFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'layoutSnapWarnDistanceMm', 1, @isNonnegativeScalar);
    addParameter(p, 'layoutSnapErrorDistanceMm', 3, @isNonnegativeScalar);
    addParameter(p, 'outputFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'forceLayout', [], ...
        @(x) isempty(x) || isBoolLike(x));
    addParameter(p, 'force', true, @isBoolLike);
    addParameter(p, 'showFigures', false, @isBoolLike);
    addParameter(p, 'saveFigures', false, @isBoolLike);
    addParameter(p, 'verbose', true, @isBoolLike);
    parse(p, varargin{:});
    opts = p.Results;
    opts.nTes = round(double(opts.nTes));
    opts.nEeg = round(double(opts.nEeg));
    opts.tesPrefix = validateCustomPrefix(opts.tesPrefix, 'tesPrefix');
    opts.eegPrefix = validateCustomPrefix(opts.eegPrefix, 'eegPrefix');
    opts.eegPreferSymmetry = logical(opts.eegPreferSymmetry);
    if ~isempty(opts.eegMidlineMarginMM)
        opts.eegMidlineMarginMM = double(opts.eegMidlineMarginMM);
    end
    opts.eegExclusionRadiusMm = double(opts.eegExclusionRadiusMm);
    opts.earExclusionMode = normalizeEarExclusionMode(opts.earExclusionMode);
    opts.earExclusionFile = expandUserPath(char(opts.earExclusionFile));
    opts.strapExclusionMode = normalizeStrapExclusionMode(opts.strapExclusionMode);
    opts.strapRostralOffsetMm = double(opts.strapRostralOffsetMm);
    opts.strapWidthMm = double(opts.strapWidthMm);
    opts.strapMarginMm = double(opts.strapMarginMm);
    if ~isempty(opts.strapExclusionRadiusMm)
        opts.strapExclusionRadiusMm = double(opts.strapExclusionRadiusMm);
    end
    opts.strapLateralLengthMm = double(opts.strapLateralLengthMm);
    opts.strapSampleSpacingMm = double(opts.strapSampleSpacingMm);
    opts.holderOutsideDiaMm = double(opts.holderOutsideDiaMm);
    opts.zBedMm = double(opts.zBedMm);
    opts.skinCacheFile = expandUserPath(char(opts.skinCacheFile));
    opts.layoutSnapWarnDistanceMm = double(opts.layoutSnapWarnDistanceMm);
    opts.layoutSnapErrorDistanceMm = double(opts.layoutSnapErrorDistanceMm);
    opts.outputFile = char(opts.outputFile);
    if isempty(opts.forceLayout)
        opts.forceLayout = logical(opts.force);
    else
        opts.forceLayout = logical(opts.forceLayout);
    end
    opts.force = opts.forceLayout;
    opts.showFigures = logical(opts.showFigures);
    opts.saveFigures = logical(opts.saveFigures);
    opts.verbose = logical(opts.verbose);
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

function mode = normalizeEarExclusionMode(modeIn)
    mode = lower(strtrim(char(modeIn)));
    switch mode
        case {'auto', 'always', 'never'}
            % Accepted as-is.
        case {'reuse', 'load'}
            mode = 'never';
        case {'select', 'edit'}
            mode = 'always';
        otherwise
            error('acsAssembleTesEegCapMakerLayout:BadEarExclusionMode', ...
                'earExclusionMode must be ''auto'', ''always'', or ''never''.');
    end
end

function mode = normalizeStrapExclusionMode(modeIn)
    mode = lower(strtrim(char(modeIn)));
    switch mode
        case {'auto', 'always', 'none'}
            % Accepted as-is.
        case {'off', 'never', 'ignore'}
            mode = 'none';
        case {'on', 'yes'}
            mode = 'auto';
        otherwise
            error('acsAssembleTesEegCapMakerLayout:BadStrapExclusionMode', ...
                'strapExclusionMode must be ''auto'', ''always'', or ''none''.');
    end
end

function addLocalDependencies()
    repoRoot = fileparts(fileparts(mfilename('fullpath')));
    capGeom = fullfile(repoRoot, 'capMaker', 'geometry');
    capCore = fullfile(repoRoot, 'capMaker', 'core');
    if exist(capGeom, 'dir') == 7, addpath(capGeom); end
    if exist(capCore, 'dir') == 7, addpath(capCore); end
    addpath(fullfile(repoRoot, 'acsUtilities'));
end

function pathOut = expandUserPath(pathOut)
    if isempty(pathOut)
        return;
    end
    if startsWith(pathOut, '~')
        homeDir = getenv('HOME');
        if isempty(homeDir)
            homeDir = char(java.lang.System.getProperty('user.home'));
        end
        if numel(pathOut) == 1
            pathOut = homeDir;
        elseif pathOut(2) == filesep || pathOut(2) == '/'
            pathOut = fullfile(homeDir, pathOut(3:end));
        end
    end
end

function layout = readLayout(value)
    if isstruct(value)
        layout = value;
        return;
    end
    if ~(ischar(value) || isstring(value))
        error('acsAssembleTesEegCapMakerLayout:BadLayout', ...
            'baseLayout must be a layout struct or MAT report.');
    end
    data = load(char(value));
    layout = firstStruct(data);
end

function sparse = readSparseResult(value)
    if isstruct(value)
        sparse = value;
        return;
    end
    if ~(ischar(value) || isstring(value))
        error('acsAssembleTesEegCapMakerLayout:BadSparse', ...
            'sparseResult must be a sparse struct or MAT report.');
    end
    data = load(char(value), 'out');
    if ~isfield(data, 'out')
        error('acsAssembleTesEegCapMakerLayout:BadSparseReport', ...
            'Sparse report does not contain an output struct.');
    end
    sparse = data.out;
end

function value = firstStruct(data)
    names = fieldnames(data);
    for i = 1:numel(names)
        if isstruct(data.(names{i}))
            value = data.(names{i});
            return;
        end
    end
    error('acsAssembleTesEegCapMakerLayout:NoStructInMat', ...
        'MAT report did not contain a struct.');
end

function requireFields(S, fields)
    for i = 1:numel(fields)
        if ~isfield(S, fields{i}) || isempty(S.(fields{i}))
            error('acsAssembleTesEegCapMakerLayout:MissingField', ...
                'Input is missing required field "%s".', fields{i});
        end
    end
end

function [tesNames, tesPrintMm, tesCurrentsMa] = selectTesSites(layout, sparse, nTes)
    sparseNames = cellstr(sparse.selectedNames(:));
    sparseCurrents = double(sparse.selectedCurrentsMa(:));
    if nTes > numel(sparseNames)
        error('acsAssembleTesEegCapMakerLayout:TooManyTes', ...
            'Requested %d tES sites, but sparse result only has %d active sites.', ...
            nTes, numel(sparseNames));
    end
    [~, order] = sort(abs(sparseCurrents), 'descend');
    keep = sort(order(1:nTes));
    tesNames = sparseNames(keep);
    tesCurrentsMa = sparseCurrents(keep);

    layoutNames = cellstr(layout.names(:));
    tesPrintMm = zeros(numel(tesNames), 3);
    for i = 1:numel(tesNames)
        idx = find(strcmpi(tesNames{i}, layoutNames), 1);
        if isempty(idx)
            error('acsAssembleTesEegCapMakerLayout:MissingTesSite', ...
                'Sparse tES electrode "%s" was not found in the base layout.', ...
                tesNames{i});
        end
        tesPrintMm(i, :) = layout.layoutCoordinatesMm(idx, :);
    end
end

function targetOptions = makeEegTargetOptions(baseOptions, overrides, tesPrintMm, opts)
    if isempty(baseOptions), baseOptions = struct(); end
    if isempty(overrides), overrides = struct(); end
    baseOptions = stripManualTargetOptions(baseOptions);
    warnIfRelaxingEdgeMargin(baseOptions, overrides);
    targetOptions = mergeStructs(baseOptions, overrides);
    hasManualOverride = isfield(overrides, 'manualTargetsMm') && ...
        ~isempty(overrides.manualTargetsMm);
    if ~hasManualOverride
        targetOptions = stripManualTargetOptions(targetOptions);
    end
    if ~isfield(targetOptions, 'placementMode') || ...
            isempty(targetOptions.placementMode) || ...
            strcmpi(char(targetOptions.placementMode), 'manualTargetsMm')
        targetOptions.placementMode = 'surfaceGeodesic';
    end
    if ~isfield(overrides, 'preferSymmetry') && ~isfield(overrides, 'symmetric')
        targetOptions.preferSymmetry = opts.eegPreferSymmetry;
    end
    preferSymmetry = effectivePreferSymmetry(targetOptions);
    if ~isfield(overrides, 'midlineMarginMM')
        if ~isempty(opts.eegMidlineMarginMM)
            targetOptions.midlineMarginMM = opts.eegMidlineMarginMM;
        elseif ~preferSymmetry
            targetOptions.midlineMarginMM = 0;
        end
    end

    [centers, radii] = existingExclusions(targetOptions);
    extraCenters = double(opts.extraExclusionCenters);
    extraRadii = expandRadii(opts.extraExclusionRadiusMm, size(extraCenters, 1), ...
        'extraExclusionRadiusMm');
    tesRadii = repmat(opts.eegExclusionRadiusMm, size(tesPrintMm, 1), 1);

    targetOptions.exclusionCenters = [centers; tesPrintMm; extraCenters];
    targetOptions.exclusionRadiusMM = [radii; tesRadii; extraRadii];
end

function tf = effectivePreferSymmetry(targetOptions)
    if isfield(targetOptions, 'preferSymmetry')
        tf = logical(targetOptions.preferSymmetry);
    elseif isfield(targetOptions, 'symmetric')
        tf = logical(targetOptions.symmetric);
    else
        tf = false;
    end
    tf = isscalar(tf) && tf;
end

function warnIfRelaxingEdgeMargin(baseOptions, overrides)
    if ~isfield(baseOptions, 'edgeMarginMM') || ...
            ~isfield(overrides, 'edgeMarginMM')
        return;
    end
    baseMargin = double(baseOptions.edgeMarginMM);
    overrideMargin = double(overrides.edgeMarginMM);
    if isscalar(baseMargin) && isscalar(overrideMargin) && ...
            isfinite(baseMargin) && isfinite(overrideMargin) && ...
            overrideMargin < baseMargin
        warning('acsAssembleTesEegCapMakerLayout:RelaxedEegEdgeMargin', ...
            ['EEG targetOptions.edgeMarginMM overrides the base cap ', ...
             'edge margin from %.3g to %.3g mm. This relaxes cap-edge ', ...
             'exclusion for EEG placement.'], ...
            baseMargin, overrideMargin);
    end
end

function options = stripManualTargetOptions(options)
    if isfield(options, 'manualTargetsMm')
        options = rmfield(options, 'manualTargetsMm');
    end
end

function out = mergeStructs(a, b)
    out = a;
    if isempty(b), return; end
    names = fieldnames(b);
    for i = 1:numel(names)
        out.(names{i}) = b.(names{i});
    end
end

function [centers, radii] = existingExclusions(targetOptions)
    centers = zeros(0, 3);
    radii = zeros(0, 1);
    if isfield(targetOptions, 'exclusionCenters') && ...
            ~isempty(targetOptions.exclusionCenters)
        centers = double(targetOptions.exclusionCenters);
        radiusValue = [];
        if isfield(targetOptions, 'exclusionRadiusMM')
            radiusValue = targetOptions.exclusionRadiusMM;
        end
        radii = expandRadii(radiusValue, ...
            size(centers, 1), 'targetOptions.exclusionRadiusMM');
    end
end

function radii = expandRadii(value, n, fieldName)
    if n == 0
        radii = zeros(0, 1);
        return;
    end
    if isempty(value)
        error('acsAssembleTesEegCapMakerLayout:MissingExclusionRadius', ...
            'Set %s for %d exclusion centers.', fieldName, n);
    end
    radii = double(value(:));
    if numel(radii) == 1
        radii = repmat(radii, n, 1);
    elseif numel(radii) ~= n
        error('acsAssembleTesEegCapMakerLayout:BadExclusionRadius', ...
            '%s must be scalar or have one value per exclusion center.', ...
            fieldName);
    end
end

function snapDistance = checkCombinedLayoutSnapDistance(layout, opts)
    snapDistance = zeros(numel(layout.names), 1);
    if ~isfield(layout, 'targetDiagnostics') || ...
            ~isfield(layout.targetDiagnostics, 'snapDistanceMm') || ...
            isempty(layout.targetDiagnostics.snapDistanceMm)
        return;
    end
    snapDistance = double(layout.targetDiagnostics.snapDistanceMm(:));
    if opts.verbose
        fprintf('Combined layout skin snap max/median: %.3g / %.3g mm.\n', ...
            max(snapDistance), median(snapDistance));
    end
    if any(snapDistance > opts.layoutSnapErrorDistanceMm)
        txt = snapDistanceSummary(layout.names, snapDistance, ...
            opts.layoutSnapErrorDistanceMm);
        error('acsAssembleTesEegCapMakerLayout:LayoutSnapTooFar', ...
            ['Combined layout contains sites that are too far from the ', ...
             'selected capMaker skin cache: %s. This usually means the ', ...
             'tES candidate layout, EEG layout, or manufacturing skin cache ', ...
             'came from different scalp meshes.'], txt);
    end
    if any(snapDistance > opts.layoutSnapWarnDistanceMm)
        txt = snapDistanceSummary(layout.names, snapDistance, ...
            opts.layoutSnapWarnDistanceMm);
        warning('acsAssembleTesEegCapMakerLayout:LayoutSnapDistance', ...
            'Combined layout sites farther than %.3g mm from skin: %s', ...
            opts.layoutSnapWarnDistanceMm, txt);
    end
end

function txt = snapDistanceSummary(names, d, threshold)
    names = cellstr(names(:));
    rows = find(d > threshold);
    rows = rows(:).';
    maxItems = min(numel(rows), 10);
    parts = cell(1, maxItems);
    for k = 1:maxItems
        i = rows(k);
        parts{k} = sprintf('%s (%.3g mm)', names{i}, d(i));
    end
    txt = strjoin(parts, ', ');
    if numel(rows) > maxItems
        txt = sprintf('%s, ... %d more', txt, numel(rows) - maxItems);
    end
end

function names = numberedNames(prefix, n)
    names = arrayfun(@(i) sprintf('%s%d', prefix, i), ...
        (1:n)', 'UniformOutput', false);
end

function prefix = validateCustomPrefix(prefix, fieldName)
    prefix = char(prefix);
    if isempty(strfind(lower(prefix), 'custom')) %#ok<STREMP>
        error('acsAssembleTesEegCapMakerLayout:BadPrefix', ...
            '%s must contain "custom" so ROAST accepts the names.', fieldName);
    end
end

function fileName = reportMatFile(customLocationsFile)
    fileName = [customLocationsFile '_report.mat'];
end

function out = stripFigure(out)
    if isfield(out, 'figure')
        out = rmfield(out, 'figure');
    end
end

function compact = compactExclusionStruct(value)
    if ~isstruct(value)
        compact = struct();
        return;
    end
    compact = value;
    heavyFields = {'figure', 'options'};
    for i = 1:numel(heavyFields)
        if isfield(compact, heavyFields{i})
            compact = rmfield(compact, heavyFields{i});
        end
    end
end

function logMsg(opts, varargin)
    if opts.verbose
        fprintf([varargin{1} '\n'], varargin{2:end});
    end
end
