function out = acsPredictEegVoltagesFromTes(layoutIn, tesRecipe, varargin)
% ACSPREDICTEEGVOLTAGESFROMTES Predict EEG channel voltages for a tES montage.
%
% out = acsPredictEegVoltagesFromTes(combinedLayout, tesRecipe)
% runs or reuses a direct ROAST solve with the optimized tES electrodes
% carrying tesRecipe currents and the EEG electrodes included as passive
% zero-current electrodes. It then samples nodal voltage over each EEG
% electrode body in the ROAST mesh.
%
% Name-value options:
%   eegNames          : EEG channel names [layout.eegNames or siteRoles]
%   simulationTag     : direct ROAST tag ['tesEegVoltagePrediction']
%   electrodeModel    : 'auto', 'biosemiPin', or 'roastDefault' ['auto']
%   resampling        : ROAST resampling option ['off']
%   roastOptions      : additional ROAST name-value pairs [{}]
%   sampleDomain      : 'electrode' or 'gel' ['electrode']
%   referenceMode     : 'meanEeg', 'none', EEG name, or numeric scalar ['meanEeg']
%   updateCustomLocations : copy layout customLocations to ROAST filename [true]
%   forceDirectSolve  : rerun solve/post products, keeping mesh if compatible [false]
%   forceModel        : delete tag-specific mesh/electrode products first [false]
%   execute           : call ROAST when needed [true]
%   currentBalanceToleranceMa : tolerated roundoff in current sum [1e-6]
%   showFigures       : show EEG voltage QC [false]
%   saveFigures       : save EEG voltage QC [false]
%   showTopography    : show scalp topography QC [showFigures]
%   saveTopography    : save scalp topography QC [saveFigures]
%   topographyOptions : extra options for acsVisualizeEegVoltageTopography [{}]
%   saveReport        : save MAT report beside the T1 [true]
%   verbose           : print summary [true]

    if nargin < 2
        error('acsPredictEegVoltagesFromTes:MissingInput', ...
            'Provide a combined layout and a tES recipe.');
    end

    opts = parseInputs(varargin{:});
    addLocalDependencies();

    layout = readLayout(layoutIn);
    requireFields(layout, {'t1File', 'customLocationsFile', 'names'});
    t1File = char(layout.t1File);
    allNames = normalizeNames(layout.names);
    eegNames = resolveEegNames(layout, opts.eegNames, allNames);
    [folder, stem] = fileparts(t1File);

    [recipeNames, recipeCurrents] = parseRecipe(tesRecipe);
    mappedRecipeNames = mapRecipeNames(recipeNames, layout, allNames);
    currentsByElectrodeMa = currentsByLayoutName( ...
        allNames, mappedRecipeNames, recipeCurrents);
    [currentsByElectrodeMa, balanceInfo] = enforceBalancedCurrents( ...
        currentsByElectrodeMa, allNames, opts.currentBalanceToleranceMa);
    fullRecipe = makeRecipe(allNames, currentsByElectrodeMa);
    activeTes = abs(currentsByElectrodeMa) > opts.currentThresholdMa;
    activeTesNames = allNames(activeTes);

    activeCustomLocations = ensureRoastCustomLocations(layout, allNames, opts);
    customSnapshot = snapshotCustomLocations( ...
        activeCustomLocations, folder, stem, opts.simulationTag, opts);

    electrodeOptions = electrodeModelRoastOptions(opts.electrodeModel);
    solveRequest = buildSolveRequest( ...
        fullRecipe, electrodeOptions, opts.resampling, opts.roastOptions);
    files = runFiles(folder, stem, opts.simulationTag);
    if opts.forceModel
        deleteRunProducts(files, true);
        if exist(customSnapshot, 'file') == 2
            delete(customSnapshot);
        end
        customSnapshot = snapshotCustomLocations( ...
            activeCustomLocations, folder, stem, opts.simulationTag, opts);
    elseif snapshotDiffers(customSnapshot, activeCustomLocations)
        error('acsPredictEegVoltagesFromTes:SnapshotConflict', ...
            ['Existing simulationTag "%s" was built with different custom ', ...
             'locations. Use a new simulationTag, or set forceModel=true ', ...
             'to regenerate tag-specific model products.'], opts.simulationTag);
    elseif solveRequestMeshDiffers(files.requestMat, solveRequest)
        error('acsPredictEegVoltagesFromTes:MeshRequestConflict', ...
            ['Existing simulationTag "%s" used a different electrode model, ', ...
             'resampling setting, or ROAST option set. Use a new ', ...
             'simulationTag, or set forceModel=true to regenerate the mesh.'], ...
            opts.simulationTag);
    elseif ~opts.forceDirectSolve && solveRequestRecipeDiffers(files.requestMat, solveRequest)
        error('acsPredictEegVoltagesFromTes:RecipeRequestConflict', ...
            ['Existing simulationTag "%s" was solved with a different ', ...
             'current recipe. Use a new simulationTag, or set ', ...
             'forceDirectSolve=true to rerun on the existing compatible mesh.'], ...
            opts.simulationTag);
    elseif opts.forceDirectSolve
        deleteRunProducts(files, false);
    end

    shouldSolve = exist(files.voltagePos, 'file') ~= 2 || ...
        exist(files.meshMat, 'file') ~= 2 || ...
        exist(files.roastOptions, 'file') ~= 2;
    if shouldSolve
        if ~opts.execute
            error('acsPredictEegVoltagesFromTes:MissingSolve', ...
                ['Direct ROAST products do not exist for tag "%s" and ', ...
                 'execute=false.'], opts.simulationTag);
        end
        if opts.verbose
            fprintf('\nRunning direct ROAST solve for EEG voltage prediction...\n');
        end
        roast(t1File, fullRecipe, ...
            electrodeOptions{:}, ...
            'resampling', opts.resampling, ...
            'simulationTag', opts.simulationTag, ...
            opts.roastOptions{:});
    elseif opts.verbose
        fprintf('\nReusing direct ROAST voltage solve: %s\n', files.voltagePos);
    end

    requireFile(files.voltagePos);
    requireFile(files.meshMat);
    saveSolveRequest(files.requestMat, solveRequest);
    mesh = load(files.meshMat, 'node', 'elem');
    if ~all(isfield(mesh, {'node', 'elem'}))
        error('acsPredictEegVoltagesFromTes:BadMesh', ...
            'ROAST mesh MAT file must contain node and elem arrays: %s', ...
            files.meshMat);
    end
    [nodeIds, nodeVoltage] = readNodeVoltages(files.voltagePos);
    voltageByNode = nan(size(mesh.node, 1), 1);
    validNode = nodeIds >= 1 & nodeIds <= size(mesh.node, 1);
    voltageByNode(nodeIds(validNode)) = nodeVoltage(validNode);

    electrodeSamples = sampleElectrodeVoltages( ...
        mesh.elem, voltageByNode, allNames, eegNames, 'electrode');
    gelSamples = sampleElectrodeVoltages( ...
        mesh.elem, voltageByNode, allNames, eegNames, 'gel');
    switch opts.sampleDomain
        case 'electrode'
            samples = electrodeSamples;
        case 'gel'
            samples = gelSamples;
        otherwise
            error('acsPredictEegVoltagesFromTes:BadSampleDomain', ...
                'Unsupported sampleDomain: %s', opts.sampleDomain);
    end

    sampleQc = summarizeSamples(samples);
    warnIfBadSamples(samples, opts.sampleDomain);
    rawVoltage = [samples.meanVoltage]';
    [referenceValue, referenceLabel] = referenceVoltage(rawVoltage, eegNames, opts.referenceMode);
    referencedVoltage = rawVoltage - referenceValue;

    out = struct();
    out.createdOn = char(datetime('now'));
    out.t1File = t1File;
    out.simulationTag = opts.simulationTag;
    out.fullRecipe = fullRecipe;
    out.inputTesRecipe = tesRecipe;
    out.mappedTesRecipe = makeRecipe(mappedRecipeNames, recipeCurrents);
    out.electrodeNames = allNames;
    out.eegNames = eegNames(:);
    out.activeTesNames = activeTesNames(:);
    out.currentsByElectrodeMa = currentsByElectrodeMa;
    out.currentBalance = balanceInfo;
    out.eegVoltageRawV = rawVoltage;
    out.eegVoltageReferencedV = referencedVoltage;
    out.eegVoltageReferencedMicroV = 1e6 * referencedVoltage;
    out.referenceMode = opts.referenceMode;
    out.referenceLabel = referenceLabel;
    out.referenceValueV = referenceValue;
    out.sampleDomain = opts.sampleDomain;
    out.electrodeSamples = electrodeSamples;
    out.gelSamples = gelSamples;
    out.sampleQc = sampleQc;
    out.eegTable = makeEegTable(eegNames, rawVoltage, referencedVoltage, samples);
    out.activeCustomLocationsFile = activeCustomLocations;
    out.customLocationsSnapshot = customSnapshot;
    out.voltagePosFile = files.voltagePos;
    out.meshFile = files.meshMat;
    out.roastOptionsFile = files.roastOptions;
    out.topography = [];
    out.reportMat = fullfile(folder, ...
        [stem '_' opts.simulationTag '_eegVoltagePrediction.mat']);
    out.qcFigure = '';

    fig = [];
    if opts.showFigures || opts.saveFigures
        figVisible = 'off';
        if opts.showFigures, figVisible = 'on'; end
        fig = makeQcFigure(out, figVisible);
        if opts.saveFigures
            qcDir = fullfile(folder, 'qc');
            ensureDir(qcDir);
            out.qcFigure = fullfile(qcDir, ...
                [stem '_' opts.simulationTag '_eegVoltagePrediction.png']);
            saveas(fig, out.qcFigure);
        end
        if ~opts.showFigures
            close(fig);
        end
    end

    if opts.showTopography || opts.saveTopography
        out.topography = acsVisualizeEegVoltageTopography(out, layout, ...
            'showFigures', opts.showTopography, ...
            'saveFigures', opts.saveTopography, ...
            'verbose', opts.verbose, ...
            opts.topographyOptions{:});
    end

    if opts.saveReport
        outSaved = stripFigureHandles(out);
        saveReportStruct(out.reportMat, outSaved);
    end
    if opts.verbose
        printSummary(out);
    end
end

function opts = parseInputs(varargin)
    p = inputParser;
    p.FunctionName = 'acsPredictEegVoltagesFromTes';
    addParameter(p, 'eegNames', {}, @(x) isempty(x) || iscell(x) || ischar(x) || isstring(x));
    addParameter(p, 'simulationTag', 'tesEegVoltagePrediction', @(x) ischar(x) || isstring(x));
    addParameter(p, 'electrodeModel', 'auto', @(x) ischar(x) || isstring(x));
    addParameter(p, 'resampling', 'off', @(x) ischar(x) || isstring(x));
    addParameter(p, 'roastOptions', {}, @iscell);
    addParameter(p, 'sampleDomain', 'electrode', @(x) ischar(x) || isstring(x));
    addParameter(p, 'referenceMode', 'meanEeg', @(x) isnumeric(x) || ischar(x) || isstring(x));
    addParameter(p, 'updateCustomLocations', true, @isBoolLike);
    addParameter(p, 'forceDirectSolve', false, @isBoolLike);
    addParameter(p, 'forceModel', false, @isBoolLike);
    addParameter(p, 'execute', true, @isBoolLike);
    addParameter(p, 'currentThresholdMa', 1e-9, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0);
    addParameter(p, 'currentBalanceToleranceMa', 1e-6, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0);
    addParameter(p, 'showFigures', false, @isBoolLike);
    addParameter(p, 'saveFigures', false, @isBoolLike);
    addParameter(p, 'showTopography', [], ...
        @(x) isempty(x) || isBoolLike(x));
    addParameter(p, 'saveTopography', [], ...
        @(x) isempty(x) || isBoolLike(x));
    addParameter(p, 'topographyOptions', {}, @iscell);
    addParameter(p, 'saveReport', true, @isBoolLike);
    addParameter(p, 'verbose', true, @isBoolLike);
    parse(p, varargin{:});
    opts = p.Results;
    opts.eegNames = normalizeNames(opts.eegNames);
    opts.simulationTag = safeTag(opts.simulationTag);
    opts.electrodeModel = normalizeElectrodeModel(opts.electrodeModel);
    opts.resampling = lower(char(opts.resampling));
    opts.sampleDomain = normalizeSampleDomain(opts.sampleDomain);
    opts.updateCustomLocations = logical(opts.updateCustomLocations);
    opts.forceDirectSolve = logical(opts.forceDirectSolve);
    opts.forceModel = logical(opts.forceModel);
    opts.execute = logical(opts.execute);
    opts.currentThresholdMa = double(opts.currentThresholdMa);
    opts.currentBalanceToleranceMa = double(opts.currentBalanceToleranceMa);
    opts.showFigures = logical(opts.showFigures);
    opts.saveFigures = logical(opts.saveFigures);
    if isempty(opts.showTopography)
        opts.showTopography = opts.showFigures;
    else
        opts.showTopography = logical(opts.showTopography);
    end
    if isempty(opts.saveTopography)
        opts.saveTopography = opts.saveFigures;
    else
        opts.saveTopography = logical(opts.saveTopography);
    end
    opts.saveReport = logical(opts.saveReport);
    opts.verbose = logical(opts.verbose);
    if ~any(strcmp(opts.resampling, {'on', 'off'}))
        error('acsPredictEegVoltagesFromTes:BadResampling', ...
            'resampling must be ''on'' or ''off''.');
    end
    if mod(numel(opts.roastOptions), 2) ~= 0
        error('acsPredictEegVoltagesFromTes:BadRoastOptions', ...
            'roastOptions must contain ROAST name-value pairs.');
    end
end

function tf = isBoolLike(x)
    tf = (islogical(x) || isnumeric(x)) && isscalar(x);
end

function addLocalDependencies()
    repoRoot = fileparts(fileparts(mfilename('fullpath')));
    addpath(repoRoot);
    spmDir = fullfile(repoRoot, 'lib', 'spm12');
    if exist(spmDir, 'dir') == 7
        addpath(spmDir);
    end
end

function layout = readLayout(value)
    if isstruct(value)
        layout = value;
        return;
    end
    if ~(ischar(value) || isstring(value))
        error('acsPredictEegVoltagesFromTes:BadLayout', ...
            'layoutIn must be a layout struct or MAT report.');
    end
    data = load(char(value));
    layout = firstStruct(data);
end

function value = firstStruct(data)
    names = fieldnames(data);
    for i = 1:numel(names)
        if isstruct(data.(names{i}))
            value = data.(names{i});
            return;
        end
    end
    error('acsPredictEegVoltagesFromTes:NoStructInMat', ...
        'MAT report did not contain a struct.');
end

function requireFields(S, fields)
    for i = 1:numel(fields)
        if ~isfield(S, fields{i}) || isempty(S.(fields{i}))
            error('acsPredictEegVoltagesFromTes:MissingField', ...
                'Input is missing required field "%s".', fields{i});
        end
    end
end

function requireFile(fileName)
    if exist(fileName, 'file') ~= 2
        error('acsPredictEegVoltagesFromTes:MissingFile', ...
            'Required file not found: %s', fileName);
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
        error('acsPredictEegVoltagesFromTes:BadNames', ...
            'Names must be a cell array, char, or string array.');
    end
    names = names(:);
end

function tag = safeTag(tag)
    tag = char(tag);
    tag = regexprep(tag, '[^A-Za-z0-9_]', '_');
    if isempty(tag)
        tag = 'tesEegVoltagePrediction';
    end
    if ~isletter(tag(1))
        tag = ['pred_' tag];
    end
end

function model = normalizeElectrodeModel(model)
    model = lower(strtrim(char(model)));
    switch model
        case {'auto', ''}
            model = 'auto';
        case {'biosemipin', 'biosemi', 'biosemi-pin', 'biosemi_pin'}
            model = 'biosemiPin';
        case {'roastdefault', 'default', 'legacy', 'none'}
            model = 'roastDefault';
        otherwise
            error('acsPredictEegVoltagesFromTes:BadElectrodeModel', ...
                'electrodeModel must be ''auto'', ''biosemiPin'', or ''roastDefault''.');
    end
end

function mode = normalizeSampleDomain(mode)
    mode = lower(strtrim(char(mode)));
    switch mode
        case {'electrode', 'elec', 'contact'}
            mode = 'electrode';
        case {'gel', 'gelpool'}
            mode = 'gel';
        otherwise
            error('acsPredictEegVoltagesFromTes:BadSampleDomain', ...
                'sampleDomain must be ''electrode'' or ''gel''.');
    end
end

function roastOptions = electrodeModelRoastOptions(model)
    if strcmp(model, 'auto')
        model = 'biosemiPin';
    end
    switch model
        case 'biosemiPin'
            roastOptions = {'elecType', 'disc', ...
                'elecSize', [1 5], ...
                'elecGelSize', [2.5 2.5], ...
                'elecSkinGap', 0.5};
        case 'roastDefault'
            roastOptions = {};
        otherwise
            error('acsPredictEegVoltagesFromTes:BadElectrodeModel', ...
                'Unsupported electrodeModel "%s".', model);
    end
end

function request = buildSolveRequest(fullRecipe, electrodeOptions, resampling, roastOptions)
    request = struct();
    request.fullRecipe = fullRecipe;
    request.electrodeOptions = electrodeOptions;
    request.resampling = resampling;
    request.roastOptions = roastOptions;
    request.segMaskFingerprint = segMaskFingerprintFromRoastOptions(roastOptions);
end

function tf = solveRequestRecipeDiffers(requestFile, request)
    tf = false;
    oldRequest = loadSolveRequest(requestFile);
    if isempty(oldRequest)
        return;
    end
    tf = ~isequaln(requestField(oldRequest, 'fullRecipe'), request.fullRecipe);
end

function tf = solveRequestMeshDiffers(requestFile, request)
    tf = false;
    oldRequest = loadSolveRequest(requestFile);
    if isempty(oldRequest)
        return;
    end
    tf = ~isequaln(requestField(oldRequest, 'electrodeOptions'), request.electrodeOptions) || ...
        ~isequaln(requestField(oldRequest, 'resampling'), request.resampling) || ...
        ~isequaln(requestField(oldRequest, 'roastOptions'), request.roastOptions) || ...
        ~isequaln(requestField(oldRequest, 'segMaskFingerprint'), request.segMaskFingerprint);
end

function request = loadSolveRequest(requestFile)
    request = [];
    if exist(requestFile, 'file') ~= 2
        return;
    end
    S = load(requestFile, 'request');
    if isfield(S, 'request') && isstruct(S.request)
        request = S.request;
    else
        request = struct();
    end
end

function value = requestField(request, fieldName)
    if isfield(request, fieldName)
        value = request.(fieldName);
    else
        value = [];
    end
end

function fingerprint = segMaskFingerprintFromRoastOptions(roastOptions)
    fingerprint = [];
    if isempty(roastOptions)
        return;
    end
    names = roastOptions(1:2:end);
    values = roastOptions(2:2:end);
    names = cellfun(@char, names(:), 'UniformOutput', false);
    idx = find(strcmpi(names, 'segMaskFile'), 1);
    if isempty(idx)
        return;
    end
    fileName = char(values{idx});
    if exist(fileName, 'file') ~= 2
        return;
    end
    info = dir(fileName);
    fingerprint = struct('file', fileName, ...
        'bytes', info.bytes, ...
        'datenum', info.datenum, ...
        'date', info.date);
end

function saveSolveRequest(requestFile, request)
    save(requestFile, 'request');
end

function eegNames = resolveEegNames(layout, eegNames, allNames)
    if ~isempty(eegNames)
        assertKnownNames(eegNames, allNames, 'eegNames');
        return;
    end
    if isfield(layout, 'eegNames') && ~isempty(layout.eegNames)
        eegNames = normalizeNames(layout.eegNames);
    elseif isfield(layout, 'siteRoles') && ~isempty(layout.siteRoles)
        roles = normalizeNames(layout.siteRoles);
        eegNames = allNames(strcmpi(roles, 'EEG'));
    else
        eegNames = allNames(startsWith(lower(string(allNames)), 'customeeg'));
    end
    if isempty(eegNames)
        error('acsPredictEegVoltagesFromTes:NoEegNames', ...
            ['Could not infer EEG names from the layout. Provide ', ...
             '''eegNames'' explicitly.']);
    end
    assertKnownNames(eegNames, allNames, 'eegNames');
end

function assertKnownNames(names, allNames, fieldName)
    if ~all(ismember(lower(string(names)), lower(string(allNames))))
        error('acsPredictEegVoltagesFromTes:UnknownName', ...
            '%s contains names that are not in layout.names.', fieldName);
    end
end

function [names, currents] = parseRecipe(recipe)
    if ~iscell(recipe) || mod(numel(recipe), 2) ~= 0
        error('acsPredictEegVoltagesFromTes:BadRecipe', ...
            'tesRecipe must contain electrode-name/current pairs.');
    end
    names = recipe(1:2:end);
    names = cellfun(@char, names(:), 'UniformOutput', false);
    try
        currents = cell2mat(recipe(2:2:end))';
    catch
        error('acsPredictEegVoltagesFromTes:BadRecipe', ...
            'Every recipe current must be numeric.');
    end
    currents = double(currents(:));
end

function mapped = mapRecipeNames(names, layout, allNames)
    mapped = names(:);
    layoutLower = lower(string(allNames));
    hasSourceMap = isfield(layout, 'sourceTesNames') && ...
        isfield(layout, 'tesNames') && ~isempty(layout.sourceTesNames) && ...
        ~isempty(layout.tesNames);
    if hasSourceMap
        sourceNames = normalizeNames(layout.sourceTesNames);
        targetNames = normalizeNames(layout.tesNames);
        sourceLower = lower(string(sourceNames));
    end
    for i = 1:numel(names)
        nameLower = lower(string(names{i}));
        if any(strcmp(nameLower, layoutLower))
            continue;
        end
        if hasSourceMap
            idx = find(strcmp(nameLower, sourceLower), 1);
            if ~isempty(idx)
                mapped{i} = targetNames{idx};
                continue;
            end
        end
        error('acsPredictEegVoltagesFromTes:UnknownRecipeName', ...
            ['Recipe electrode "%s" is neither a combined-layout name ', ...
             'nor a source tES name recorded in the layout.'], names{i});
    end
end

function currents = currentsByLayoutName(allNames, recipeNames, recipeCurrents)
    if numel(unique(lower(string(recipeNames)))) ~= numel(recipeNames)
        error('acsPredictEegVoltagesFromTes:DuplicateRecipeName', ...
            'Recipe contains duplicated electrodes after name mapping.');
    end
    currents = zeros(numel(allNames), 1);
    for i = 1:numel(recipeNames)
        idx = find(strcmpi(recipeNames{i}, allNames), 1);
        if isempty(idx)
            error('acsPredictEegVoltagesFromTes:UnknownRecipeName', ...
                'Mapped recipe electrode "%s" is not in layout.names.', ...
                recipeNames{i});
        end
        currents(idx) = recipeCurrents(i);
    end
end

function [currents, balanceInfo] = enforceBalancedCurrents(currents, allNames, toleranceMa)
    residual = sum(currents);
    balanceInfo = struct( ...
        'originalSumMa', residual, ...
        'toleranceMa', toleranceMa, ...
        'corrected', false, ...
        'correctionElectrode', '', ...
        'correctionMa', 0, ...
        'finalSumMa', residual);
    if abs(residual) > toleranceMa
        error('acsPredictEegVoltagesFromTes:UnbalancedRecipe', ...
            ['tES recipe currents must sum to zero within %.6g mA. ', ...
             'Current sum was %.6g mA.'], toleranceMa, residual);
    end
    if residual == 0
        return;
    end
    active = find(abs(currents) > 0);
    if isempty(active)
        active = find(isfinite(currents), 1);
    end
    if isempty(active)
        error('acsPredictEegVoltagesFromTes:NoFiniteCurrents', ...
            'No finite currents were available to balance.');
    end
    [~, localIdx] = max(abs(currents(active)));
    correctionIdx = active(localIdx);
    correction = -residual;
    currents(correctionIdx) = currents(correctionIdx) + correction;
    balanceInfo.corrected = true;
    balanceInfo.correctionElectrode = allNames{correctionIdx};
    balanceInfo.correctionMa = correction;
    balanceInfo.finalSumMa = sum(currents);
end

function recipe = makeRecipe(names, currents)
    names = names(:);
    currents = num2cell(double(currents(:)));
    recipe = reshape([names currents]', 1, []);
end

function activeFile = ensureRoastCustomLocations(layout, allNames, opts)
    [folder, stem] = fileparts(layout.t1File);
    activeFile = fullfile(folder, [stem '_customLocations']);
    sourceFile = char(layout.customLocationsFile);
    if exist(sourceFile, 'file') ~= 2
        error('acsPredictEegVoltagesFromTes:MissingCustomLocations', ...
            'Layout custom locations file not found: %s', sourceFile);
    end
    validateLocationNames(sourceFile, allNames);
    if strcmpi(sourceFile, activeFile)
        return;
    end
    if exist(activeFile, 'file') == 2 && filesEqual(activeFile, sourceFile)
        return;
    end
    if ~opts.updateCustomLocations
        error('acsPredictEegVoltagesFromTes:ActiveCustomLocationsMismatch', ...
            ['ROAST expects custom locations at %s, but the layout reports ', ...
             '%s. Set updateCustomLocations=true to copy the layout file ', ...
             'into ROAST''s expected location.'], activeFile, sourceFile);
    end
    [ok, message] = copyfile(sourceFile, activeFile);
    if ~ok
        error('acsPredictEegVoltagesFromTes:CannotCopyCustomLocations', ...
            'Could not update ROAST custom locations: %s', message);
    end
end

function validateLocationNames(fileName, names)
    [fileNames, ~] = readCustomLocations(fileName);
    if ~all(ismember(lower(string(names)), lower(string(fileNames))))
        error('acsPredictEegVoltagesFromTes:BadCustomLocations', ...
            'Custom locations file does not contain every layout electrode: %s', ...
            fileName);
    end
end

function [names, coords] = readCustomLocations(fileName)
    fid = fopen(fileName, 'r');
    if fid == -1
        error('acsPredictEegVoltagesFromTes:CannotReadCustomLocations', ...
            'Could not read custom locations: %s', fileName);
    end
    cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
    C = textscan(fid, '%s %f %f %f');
    names = C{1};
    coords = [C{2}, C{3}, C{4}];
end

function tf = filesEqual(fileA, fileB)
    if exist(fileA, 'file') ~= 2 || exist(fileB, 'file') ~= 2
        tf = false;
        return;
    end
    tf = strcmp(fileread(fileA), fileread(fileB));
end

function snapshot = snapshotCustomLocations(activeFile, folder, stem, simulationTag, opts)
    snapshot = fullfile(folder, [stem '_' simulationTag '_customLocations']);
    if exist(snapshot, 'file') == 2
        return;
    end
    if ~opts.updateCustomLocations
        return;
    end
    [ok, message] = copyfile(activeFile, snapshot);
    if ~ok
        error('acsPredictEegVoltagesFromTes:CannotSnapshotCustomLocations', ...
            'Could not snapshot custom locations: %s', message);
    end
end

function tf = snapshotDiffers(snapshot, activeFile)
    tf = exist(snapshot, 'file') == 2 && ...
        exist(activeFile, 'file') == 2 && ...
        ~filesEqual(snapshot, activeFile);
end

function files = runFiles(folder, stem, simulationTag)
    prefix = fullfile(folder, [stem '_' simulationTag]);
    files.prefix = prefix;
    files.voltagePos = [prefix '_v.pos'];
    files.fieldPos = [prefix '_e.pos'];
    files.meshMat = [prefix '.mat'];
    files.meshMsh = [prefix '.msh'];
    files.readyMsh = [prefix '_ready.msh'];
    files.usedArea = [prefix '_usedElecArea.mat'];
    files.elecMask = [prefix '_mask_elec.nii'];
    files.gelMask = [prefix '_mask_gel.nii'];
    files.roastOptions = [prefix '_roastOptions.mat'];
    files.roastResult = [prefix '_roastResult.mat'];
    files.requestMat = [prefix '_eegVoltageRequest.mat'];
    files.voltageNii = [prefix '_v.nii'];
    files.fieldNii = [prefix '_e.nii'];
    files.fieldMagNii = [prefix '_emag.nii'];
    files.pro = [prefix '.pro'];
    files.pre = [prefix '.pre'];
    files.res = [prefix '.res'];
end

function deleteRunProducts(files, includeModel)
    solveFiles = {files.voltagePos, files.fieldPos, files.roastResult, ...
        files.voltageNii, files.fieldNii, files.fieldMagNii, ...
        files.requestMat, files.pro, files.pre, files.res};
    modelFiles = {files.meshMat, files.meshMsh, files.readyMsh, ...
        files.usedArea, files.elecMask, files.gelMask, files.roastOptions};
    if includeModel
        deleteFiles([solveFiles modelFiles]);
    else
        deleteFiles(solveFiles);
    end
end

function deleteFiles(files)
    for i = 1:numel(files)
        if exist(files{i}, 'file') == 2
            delete(files{i});
        end
    end
end

function [nodeIds, voltage] = readNodeVoltages(fileName)
    fid = fopen(fileName, 'r');
    if fid == -1
        error('acsPredictEegVoltagesFromTes:CannotReadVoltage', ...
            'Could not open voltage file: %s', fileName);
    end
    cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fgetl(fid);
    C = textscan(fid, '%d %f');
    nodeIds = double(C{1});
    voltage = double(C{2});
end

function samples = sampleElectrodeVoltages(elem, voltageByNode, allNames, names, domain)
    nElec = numel(allNames);
    samples = repmat(struct( ...
        'name', '', ...
        'domain', domain, ...
        'meshLabel', NaN, ...
        'nodeCount', 0, ...
        'meanVoltage', NaN, ...
        'medianVoltage', NaN, ...
        'stdVoltage', NaN, ...
        'minVoltage', NaN, ...
        'maxVoltage', NaN), numel(names), 1);
    for i = 1:numel(names)
        idx = find(strcmpi(names{i}, allNames), 1);
        if isempty(idx)
            error('acsPredictEegVoltagesFromTes:UnknownSampleName', ...
                'Cannot sample unknown electrode "%s".', names{i});
        end
        switch domain
            case 'gel'
                label = 6 + idx;
            otherwise
                label = 6 + nElec + idx;
        end
        nodeIdx = unique(elem(elem(:, 5) == label, 1:4));
        nodeIdx = nodeIdx(:);
        nodeIdx = nodeIdx(nodeIdx >= 1 & nodeIdx <= numel(voltageByNode));
        values = voltageByNode(nodeIdx);
        values = values(isfinite(values));
        samples(i).name = names{i};
        samples(i).meshLabel = label;
        samples(i).nodeCount = numel(values);
        if isempty(values)
            continue;
        end
        samples(i).meanVoltage = mean(values);
        samples(i).medianVoltage = median(values);
        samples(i).stdVoltage = std(values);
        samples(i).minVoltage = min(values);
        samples(i).maxVoltage = max(values);
    end
end

function sampleQc = summarizeSamples(samples)
    nodeCounts = [samples.nodeCount]';
    meanVoltage = [samples.meanVoltage]';
    sampleQc = struct();
    sampleQc.nodeCount = nodeCounts;
    sampleQc.minNodeCount = min(nodeCounts);
    sampleQc.maxNodeCount = max(nodeCounts);
    sampleQc.emptyChannels = {samples(nodeCounts == 0).name}';
    sampleQc.nanChannels = {samples(~isfinite(meanVoltage)).name}';
end

function warnIfBadSamples(samples, sampleDomain)
    nodeCounts = [samples.nodeCount]';
    meanVoltage = [samples.meanVoltage]';
    bad = nodeCounts == 0 | ~isfinite(meanVoltage);
    if ~any(bad)
        return;
    end
    badNames = {samples(bad).name};
    warning('acsPredictEegVoltagesFromTes:BadEegVoltageSamples', ...
        ['%d EEG %s channels had no finite voltage samples: %s. ', ...
         'Inspect electrode meshing and consider sampleDomain=''gel''.'], ...
        nnz(bad), sampleDomain, strjoin(badNames, ', '));
end

function [referenceValue, referenceLabel] = referenceVoltage(rawVoltage, eegNames, mode)
    if isnumeric(mode)
        validateattributes(mode, {'numeric'}, {'scalar', 'real', 'finite'});
        referenceValue = double(mode);
        referenceLabel = 'numeric';
        return;
    end
    mode = char(mode);
    switch lower(strtrim(mode))
        case {'none', 'raw', 'absolute'}
            referenceValue = 0;
            referenceLabel = 'none';
        case {'meaneeg', 'mean', 'average', 'avg'}
            referenceValue = mean(rawVoltage(isfinite(rawVoltage)));
            referenceLabel = 'meanEeg';
        otherwise
            idx = find(strcmpi(mode, eegNames), 1);
            if isempty(idx)
                error('acsPredictEegVoltagesFromTes:BadReferenceMode', ...
                    ['referenceMode must be ''meanEeg'', ''none'', a numeric ', ...
                     'scalar, or one EEG channel name.']);
            end
            referenceValue = rawVoltage(idx);
            referenceLabel = eegNames{idx};
    end
end

function T = makeEegTable(eegNames, rawVoltage, referencedVoltage, samples)
    nodeCount = [samples.nodeCount]';
    stdVoltage = [samples.stdVoltage]';
    try
        T = table(eegNames(:), rawVoltage(:), referencedVoltage(:), ...
            1e6 * referencedVoltage(:), nodeCount(:), stdVoltage(:), ...
            'VariableNames', {'Name', 'RawV', 'ReferencedV', ...
            'ReferencedMicroV', 'NodeCount', 'WithinElectrodeStdV'});
    catch
        T = struct();
        T.Name = eegNames(:);
        T.RawV = rawVoltage(:);
        T.ReferencedV = referencedVoltage(:);
        T.ReferencedMicroV = 1e6 * referencedVoltage(:);
        T.NodeCount = nodeCount(:);
        T.WithinElectrodeStdV = stdVoltage(:);
    end
end

function fig = makeQcFigure(out, visible)
    fig = figure('Name', 'tES-predicted EEG voltages', ...
        'Color', 'w', 'Visible', visible, ...
        'WindowStyle', 'normal', 'Position', [120 120 980 460]);
    ax1 = subplot(1, 2, 1, 'Parent', fig);
    values = out.eegVoltageReferencedMicroV(:);
    bar(ax1, values, 'FaceColor', [0.25 0.48 0.78]);
    set(ax1, 'XTick', 1:numel(out.eegNames), ...
        'XTickLabel', out.eegNames, 'XTickLabelRotation', 35);
    ylabel(ax1, 'referenced voltage (microV)');
    title(ax1, sprintf('EEG prediction (%s reference)', out.referenceLabel), ...
        'Interpreter', 'none');
    grid(ax1, 'on');

    ax2 = subplot(1, 2, 2, 'Parent', fig);
    nodeCount = [out.electrodeSamples.nodeCount]';
    elecStdUv = 1e6 * [out.electrodeSamples.stdVoltage]';
    yyaxis(ax2, 'left');
    plot(ax2, nodeCount, 'o-', 'LineWidth', 1.2);
    ylabel(ax2, 'sampled electrode nodes');
    yyaxis(ax2, 'right');
    plot(ax2, elecStdUv, 's-', 'LineWidth', 1.2);
    ylabel(ax2, 'within-electrode SD (microV)');
    set(ax2, 'XTick', 1:numel(out.eegNames), ...
        'XTickLabel', out.eegNames, 'XTickLabelRotation', 35);
    title(ax2, 'Sampling QC');
    grid(ax2, 'on');
end

function ensureDir(folder)
    if exist(folder, 'dir') ~= 7
        mkdir(folder);
    end
end

function printSummary(out)
    fprintf('\ntES-predicted EEG voltages\n');
    fprintf('  simulation tag: %s\n', out.simulationTag);
    fprintf('  active tES channels: %d\n', numel(out.activeTesNames));
    fprintf('  EEG channels sampled: %d\n', numel(out.eegNames));
    fprintf('  sample domain: %s\n', out.sampleDomain);
    fprintf('  EEG sample nodes: %d to %d per channel\n', ...
        out.sampleQc.minNodeCount, out.sampleQc.maxNodeCount);
    fprintf('  reference: %s (%.6g V)\n', out.referenceLabel, out.referenceValueV);
    finiteVoltage = out.eegVoltageReferencedMicroV( ...
        isfinite(out.eegVoltageReferencedMicroV));
    if isempty(finiteVoltage)
        fprintf('  voltage range: no finite EEG samples\n\n');
    else
        fprintf('  voltage range: %.6g to %.6g microV\n\n', ...
            min(finiteVoltage), max(finiteVoltage));
    end
end

function out = stripFigureHandles(out)
    if isfield(out, 'figure')
        out = rmfield(out, 'figure');
    end
    if isfield(out, 'topography') && isstruct(out.topography) && ...
            isfield(out.topography, 'figure')
        out.topography = rmfield(out.topography, 'figure');
    end
end

function saveReportStruct(fileName, report)
    out = report; %#ok<NASGU>
    save(fileName, 'out');
end
