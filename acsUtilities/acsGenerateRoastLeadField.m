function out = acsGenerateRoastLeadField(roastSource, varargin)
% ACSGENERATEROASTLEADFIELD Run ROAST lead-field generation for a cap layout.
%
% out = acsGenerateRoastLeadField(layout) uses the custom electrode names
% written by acsMakeRoastCapMakerLayout. The final electrode is used as the
% mathematical reference unless referenceElectrode is specified.
%
% Name-value options:
%   candidateMode      : 'capMaker' or 'legacy1010' ['capMaker']
%   electrodeNames     : override custom candidate names [layout.names]
%   referenceElectrode : basis-field reference electrode [last candidate]
%   electrodeModel     : 'auto', 'biosemiPin', 'syntheticDemo', or
%                        'roastDefault' ['auto']
%   simulationTag      : ROAST simulation tag ['capMakerLeadField']
%   resampling         : ROAST resampling option ['off']
%   segMaskFile        : optional ROAST hard-label mask override ['']
%   extraTissues       : optional passive ROAST tissue labels [[]]
%   conductivities     : optional ROAST conductivities struct [struct()]
%   titaniumConductivity : Ti6Al4V Grade 5 default [1/(169e-8)]
%   roastOptions       : additional ROAST name-value pairs [{}]
%   showFigures        : show ROAST internal QC viewers [false]
%   execute            : call ROAST immediately [true]
%   saveReport         : save a small request report beside the T1 [true]
%
% The legacy ROAST 10-10 lead-field behavior remains available with:
%   acsGenerateRoastLeadField(t1File, 'candidateMode', 'legacy1010')

    if nargin < 1 || isempty(roastSource)
        error('acsGenerateRoastLeadField:MissingInput', ...
            'Provide a capMaker layout struct or a ROAST-ready T1 file.');
    end

    opts = parseInputs(varargin{:});
    [t1File, layoutNames, layoutMaskFile] = resolveSource(roastSource);
    if isempty(opts.segMaskFile) && ~isempty(layoutMaskFile)
        opts.segMaskFile = layoutMaskFile;
    end
    opts.segMaskFingerprint = fileFingerprint(opts.segMaskFile);
    [opts.roastOptions, opts.effectiveConductivities] = ...
        buildRoastPassThroughOptions(opts);

    switch opts.candidateMode
        case 'capMaker'
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
            electrodeOptions = electrodeModelRoastOptions( ...
                opts.electrodeModel, opts.candidateMode);
            roastLeadFieldArgs = { ...
                'leadFieldElectrodes', names, ...
                'leadFieldReference', referenceElectrode};
            candidateLocationsSnapshot = snapshotCustomLocations( ...
                t1File, opts.simulationTag, names);
        case 'legacy1010'
            names = {};
            referenceElectrode = 'Iz';
            roastLeadFieldArgs = {};
            electrodeOptions = electrodeModelRoastOptions( ...
                opts.electrodeModel, opts.candidateMode);
            candidateLocationsSnapshot = '';
        otherwise
            error('acsGenerateRoastLeadField:BadCandidateMode', ...
                'candidateMode must be ''capMaker'' or ''legacy1010''.');
    end

    out = buildReport(t1File, opts, names, referenceElectrode, ...
        candidateLocationsSnapshot, electrodeOptions);
    if opts.saveReport
        save(out.reportMat, 'out');
    end

    if opts.execute
        roast(t1File, 'leadField', ...
            roastLeadFieldArgs{:}, ...
            electrodeOptions{:}, ...
            'resampling', opts.resampling, ...
            'simulationTag', opts.simulationTag, ...
            'showFigures', onOffText(opts.showFigures), ...
            opts.roastOptions{:});

        out = resolveActualLeadFieldProducts(out, opts, names, ...
            referenceElectrode);
        if opts.saveReport
            save(out.reportMat, 'out');
        end
    end
end

function opts = parseInputs(varargin)
    p = inputParser;
    p.FunctionName = 'acsGenerateRoastLeadField';
    addParameter(p, 'candidateMode', 'capMaker', @(x) ischar(x) || isstring(x));
    addParameter(p, 'electrodeNames', {}, @(x) iscell(x) || ischar(x) || isstring(x));
    addParameter(p, 'referenceElectrode', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'electrodeModel', 'auto', @(x) ischar(x) || isstring(x));
    addParameter(p, 'simulationTag', 'capMakerLeadField', @(x) ischar(x) || isstring(x));
    addParameter(p, 'resampling', 'off', @(x) ischar(x) || isstring(x));
    addParameter(p, 'segMaskFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'extraTissues', [], @(x) isempty(x) || isstruct(x));
    addParameter(p, 'conductivities', struct(), @(x) isempty(x) || isstruct(x));
    addParameter(p, 'titaniumConductivity', 1 / (169e-8), ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x > 0);
    addParameter(p, 'roastOptions', {}, @iscell);
    addParameter(p, 'showFigures', false, @isBoolLike);
    addParameter(p, 'execute', true, @isBoolLike);
    addParameter(p, 'saveReport', true, @isBoolLike);
    parse(p, varargin{:});

    opts = p.Results;
    opts.candidateMode = normalizeCandidateMode(opts.candidateMode);
    opts.electrodeNames = normalizeNames(opts.electrodeNames);
    opts.referenceElectrode = char(opts.referenceElectrode);
    opts.electrodeModel = normalizeElectrodeModel(opts.electrodeModel);
    opts.simulationTag = char(opts.simulationTag);
    opts.resampling = lower(char(opts.resampling));
    opts.segMaskFile = char(opts.segMaskFile);
    if isempty(opts.conductivities)
        opts.conductivities = struct();
    end
    opts.titaniumConductivity = double(opts.titaniumConductivity);
    opts.showFigures = logical(opts.showFigures);
    opts.execute = logical(opts.execute);
    opts.saveReport = logical(opts.saveReport);

    if ~any(strcmp(opts.resampling, {'on', 'off'}))
        error('acsGenerateRoastLeadField:BadResampling', ...
            'resampling must be ''on'' or ''off''.');
    end
    if mod(numel(opts.roastOptions), 2) ~= 0
        error('acsGenerateRoastLeadField:BadRoastOptions', ...
            'roastOptions must contain ROAST name-value pairs.');
    end
end

function [roastOptions, conductivities] = buildRoastPassThroughOptions(opts)
    roastOptions = opts.roastOptions;
    conductivities = opts.conductivities;
    if ~isempty(opts.segMaskFile)
        if exist(opts.segMaskFile, 'file') ~= 2
            error('acsGenerateRoastLeadField:MissingSegMask', ...
                'segMaskFile not found: %s', opts.segMaskFile);
        end
        roastOptions = [roastOptions, {'segMaskFile', opts.segMaskFile}];
    end
    if ~isempty(opts.extraTissues)
        tissueCfg = roastTissueConfig(opts.extraTissues);
        if tissueCfg.hasExtraTissues
            for i = 1:numel(tissueCfg.extraTissues)
                fieldName = tissueCfg.extraTissues(i).conductivityField;
                if strcmpi(fieldName, 'titanium') && ...
                        ~isfield(conductivities, fieldName)
                    conductivities.(fieldName) = opts.titaniumConductivity;
                end
            end
        end
        roastOptions = [roastOptions, {'extraTissues', opts.extraTissues}];
        if ~isempty(fieldnames(conductivities))
            roastOptions = [roastOptions, {'conductivities', conductivities}];
        end
    elseif ~isempty(fieldnames(opts.conductivities))
        roastOptions = [roastOptions, {'conductivities', opts.conductivities}];
    end
end

function tf = isBoolLike(x)
    tf = (islogical(x) || isnumeric(x)) && isscalar(x);
end

function value = onOffText(tf)
    if tf
        value = 'on';
    else
        value = 'off';
    end
end

function mode = normalizeCandidateMode(mode)
    mode = lower(strtrim(char(mode)));
    switch mode
        case {'capmaker', 'custom', 'layout'}
            mode = 'capMaker';
        case {'legacy1010', 'legacy', '1010', 'roast'}
            mode = 'legacy1010';
    end
end

function model = normalizeElectrodeModel(model)
    model = lower(strtrim(char(model)));
    switch model
        case {'auto', ''}
            model = 'auto';
        case {'biosemipin', 'biosemi', 'biosemi-pin', 'biosemi_pin'}
            model = 'biosemiPin';
        case {'syntheticdemo', 'demo', 'demodisc', 'toydisc', ...
                'reviewerdemo', 'robustdemo'}
            model = 'syntheticDemo';
        case {'roastdefault', 'default', 'legacy', 'none'}
            model = 'roastDefault';
        otherwise
            error('acsGenerateRoastLeadField:BadElectrodeModel', ...
                ['electrodeModel must be ''auto'', ''biosemiPin'', ', ...
                 '''syntheticDemo'', or ''roastDefault''.']);
    end
end

function roastOptions = electrodeModelRoastOptions(model, candidateMode)
    if strcmp(model, 'auto')
        if strcmp(candidateMode, 'capMaker')
            model = 'biosemiPin';
        else
            model = 'roastDefault';
        end
    end
    switch model
        case 'biosemiPin'
            % Approximate the conductive Ag/AgCl BioSemi pin as a 2 mm
            % diameter by 5 mm high disc, seated 0.5 mm above scalp in a
            % 5 mm diameter by 2.5 mm high gel pool. The surrounding plastic
            % housing is handled as a physical spacing constraint in the
            % capMaker candidate growth step, not as conductive tissue.
            roastOptions = {'elecType', 'disc', ...
                'elecSize', [1 5], ...
                'elecGelSize', [2.5 2.5], ...
                'elecSkinGap', 0.5};
        case 'syntheticDemo'
            % Enlarged disc used by the public synthetic walkthrough when
            % reviewers opt into actual ROAST/GetDP solves. It is deliberately
            % easier for iso2mesh/CGAL to capture than the 2 mm BioSemi pin,
            % while still exercising ROAST's electrode, gel, mesh, and solve
            % code paths.
            roastOptions = {'elecType', 'disc', ...
                'elecSize', [3 4], ...
                'elecGelSize', [3.5 3], ...
                'elecSkinGap', 0.25};
        case 'roastDefault'
            roastOptions = {};
        otherwise
            error('acsGenerateRoastLeadField:BadElectrodeModel', ...
                'Unsupported electrodeModel "%s".', model);
    end
end

function [t1File, layoutNames, layoutMaskFile] = resolveSource(source)
    layoutNames = {};
    layoutMaskFile = '';
    if ischar(source) || isstring(source)
        t1File = char(source);
    elseif isstruct(source)
        if isfield(source, 't1File') && ~isempty(source.t1File)
            t1File = char(source.t1File);
        elseif isfield(source, 'roastReady') && isfield(source.roastReady, 't1File')
            t1File = char(source.roastReady.t1File);
        else
            error('acsGenerateRoastLeadField:MissingT1', ...
                'The input struct does not contain t1File or roastReady.t1File.');
        end
        if isfield(source, 'names')
            layoutNames = normalizeNames(source.names);
        end
        if isfield(source, 'maskFile') && ~isempty(source.maskFile)
            layoutMaskFile = char(source.maskFile);
        elseif isfield(source, 'roastReady') && ...
                isfield(source.roastReady, 'maskFile') && ...
                ~isempty(source.roastReady.maskFile)
            layoutMaskFile = char(source.roastReady.maskFile);
        end
    else
        error('acsGenerateRoastLeadField:BadSource', ...
            'Provide a layout struct or a ROAST-ready T1 file.');
    end

    if exist(t1File, 'file') ~= 2
        error('acsGenerateRoastLeadField:MissingT1', ...
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
        error('acsGenerateRoastLeadField:BadNames', ...
            'Electrode names must be a cell array or string array.');
    end
    names = names(:);
end

function validateCustomNames(names)
    if numel(names) < 2
        error('acsGenerateRoastLeadField:TooFewElectrodes', ...
            'At least two candidate electrodes are required.');
    end
    if numel(unique(lower(string(names)))) ~= numel(names)
        error('acsGenerateRoastLeadField:DuplicateElectrodes', ...
            'Candidate electrode names must be unique.');
    end
    for i = 1:numel(names)
        if isempty(strfind(lower(names{i}), 'custom')) %#ok<STREMP>
            error('acsGenerateRoastLeadField:NonCustomName', ...
                'capMaker candidate names must contain "custom": %s', names{i});
        end
    end
end

function assertMember(referenceElectrode, names)
    if ~any(strcmpi(referenceElectrode, names))
        error('acsGenerateRoastLeadField:BadReference', ...
            'Reference electrode "%s" is not in the candidate list.', ...
            referenceElectrode);
    end
end

function out = buildReport(t1File, opts, names, referenceElectrode, ...
        candidateLocationsSnapshot, electrodeOptions)
    [folder, stem] = fileparts(t1File);
    out = struct();
    out.createdOn = char(datetime('now'));
    out.t1File = t1File;
    out.candidateMode = opts.candidateMode;
    out.electrodeNames = names(:);
    out.referenceElectrode = referenceElectrode;
    out.electrodeModel = opts.electrodeModel;
    out.electrodeRoastOptions = electrodeOptions(:);
    out.candidateLocationsSnapshot = candidateLocationsSnapshot;
    out.simulationTag = opts.simulationTag;
    out.resampling = opts.resampling;
    out.segMaskFile = opts.segMaskFile;
    out.segMaskFingerprint = opts.segMaskFingerprint;
    out.extraTissues = opts.extraTissues;
    out.conductivities = opts.effectiveConductivities;
    out.titaniumConductivity = opts.titaniumConductivity;
    out.roastOptions = opts.roastOptions(:);
    out.showFigures = opts.showFigures;
    out.execute = opts.execute;
    out.leadFieldResultMat = fullfile(folder, ...
        [stem '_' opts.simulationTag '_roastResult.mat']);
    out.roastOptionsMat = fullfile(folder, ...
        [stem '_' opts.simulationTag '_roastOptions.mat']);
    out.reportMat = fullfile(folder, ...
        [stem '_' opts.simulationTag '_acsLeadFieldRequest.mat']);
    out.validationRecipe = makeValidationRecipe(names, referenceElectrode);
end

function snapshot = snapshotCustomLocations(t1File, simulationTag, names)
    [folder, stem] = fileparts(t1File);
    source = fullfile(folder, [stem '_customLocations']);
    if exist(source, 'file') ~= 2
        error('acsGenerateRoastLeadField:MissingCustomLocations', ...
            'Custom electrode locations file not found: %s', source);
    end
    validateLocationNames(source, names);
    snapshot = fullfile(folder, [stem '_' simulationTag '_customLocations']);
    if exist(snapshot, 'file') == 2
        if ~strcmp(fileread(snapshot), fileread(source))
            error('acsGenerateRoastLeadField:LocationSnapshotConflict', ...
                ['Lead-field tag "%s" already has a different custom-location ', ...
                 'snapshot. Use a new simulationTag for the new layout.'], ...
                simulationTag);
        end
        return;
    end
    [ok, message] = copyfile(source, snapshot);
    if ~ok
        error('acsGenerateRoastLeadField:CannotSnapshotLocations', ...
            'Could not snapshot custom electrode locations: %s', message);
    end
end

function validateLocationNames(fileName, names)
    fid = fopen(fileName, 'r');
    if fid == -1
        error('acsGenerateRoastLeadField:CannotReadCustomLocations', ...
            'Could not read custom electrode locations: %s', fileName);
    end
    cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
    C = textscan(fid, '%s %f %f %f');
    fileNames = C{1};
    if ~all(ismember(lower(string(names)), lower(string(fileNames))))
        error('acsGenerateRoastLeadField:MissingCandidateLocation', ...
            'Custom electrode locations file does not contain every candidate.');
    end
end

function recipe = makeValidationRecipe(names, referenceElectrode)
    recipe = {};
    if isempty(names)
        return;
    end

    currents = zeros(numel(names), 1);
    indRef = find(strcmpi(referenceElectrode, names), 1);
    indStim = setdiff(1:numel(names), indRef);
    if numel(indStim) >= 2
        currents(indStim(1)) = 1;
        currents(indStim(2)) = -1;
    else
        currents(indStim(1)) = 1;
        currents(indRef) = -1;
    end

    recipe = reshape([names(:), num2cell(currents)]', 1, []);
end

function out = resolveActualLeadFieldProducts(out, opts, names, referenceElectrode)
    requestedTag = out.simulationTag;
    out.requestedSimulationTag = requestedTag;
    out.actualSimulationTag = requestedTag;
    out.roastReusedExistingTag = false;

    requestedFiles = leadFieldFiles(out.t1File, requestedTag);
    if leadFieldProductsExist(requestedFiles)
        out = applyResolvedFiles(out, requestedFiles, requestedTag);
        return;
    end

    if ~strcmp(opts.candidateMode, 'capMaker')
        warning('acsGenerateRoastLeadField:MissingRequestedProducts', ...
            ['ROAST did not write expected lead-field products for requested ', ...
             'tag "%s".'], requestedTag);
        return;
    end

    matches = findEquivalentLeadFieldProducts(out.t1File, requestedTag, ...
        names, referenceElectrode, out.candidateLocationsSnapshot, opts);
    if isempty(matches)
        warning('acsGenerateRoastLeadField:CannotResolveActualTag', ...
            ['ROAST did not write expected lead-field products for requested ', ...
             'tag "%s", and no equivalent existing lead-field products could ', ...
             'be identified. Downstream code may fail until this is resolved.'], ...
            requestedTag);
        return;
    end

    [~, newest] = max([matches.datenum]);
    actual = matches(newest);
    out = applyResolvedFiles(out, actual.files, actual.tag);
    out.actualSimulationTag = actual.tag;
    out.roastReusedExistingTag = ~strcmp(actual.tag, requestedTag);
    out.requestedLeadFieldResultMat = requestedFiles.roastResultMat;
    out.requestedRoastOptionsMat = requestedFiles.roastOptionsMat;
    out.requestedMeshMat = requestedFiles.meshMat;
    out.requestedReadyMesh = requestedFiles.readyMesh;
    out.actualCandidateLocationsSnapshot = actual.files.customLocations;

    if out.roastReusedExistingTag
        warning('acsGenerateRoastLeadField:ReusedExistingTag', ...
            ['ROAST reused existing lead-field tag "%s" for requested tag ', ...
             '"%s". Returning the existing tag so downstream targeting uses ', ...
             'the files ROAST actually has on disk.'], ...
            actual.tag, requestedTag);
    end
end

function files = leadFieldFiles(t1File, simulationTag)
    [folder, stem] = fileparts(t1File);
    prefix = fullfile(folder, [stem '_' simulationTag]);
    files = struct();
    files.roastResultMat = [prefix '_roastResult.mat'];
    files.roastOptionsMat = [prefix '_roastOptions.mat'];
    files.meshMat = [prefix '.mat'];
    files.readyMesh = [prefix '_ready.msh'];
    files.usedElecAreaMat = [prefix '_usedElecArea.mat'];
    files.customLocations = [prefix '_customLocations'];
    files.requestMat = [prefix '_acsLeadFieldRequest.mat'];
end

function tf = leadFieldProductsExist(files)
    tf = exist(files.roastResultMat, 'file') == 2 && ...
        exist(files.roastOptionsMat, 'file') == 2 && ...
        exist(files.meshMat, 'file') == 2;
end

function out = applyResolvedFiles(out, files, simulationTag)
    out.simulationTag = simulationTag;
    out.leadFieldResultMat = files.roastResultMat;
    out.roastOptionsMat = files.roastOptionsMat;
    out.meshMat = files.meshMat;
    out.readyMesh = files.readyMesh;
    out.usedElecAreaMat = files.usedElecAreaMat;
end

function matches = findEquivalentLeadFieldProducts(t1File, requestedTag, ...
        names, referenceElectrode, requestedLocations, opts)
    [folder, stem] = fileparts(t1File);
    resultFiles = dir(fullfile(folder, [stem '_*_roastResult.mat']));
    matches = struct('tag', {}, 'files', {}, 'datenum', {});
    for i = 1:numel(resultFiles)
        tag = tagFromResultFile(resultFiles(i).name, stem);
        if isempty(tag) || strcmp(tag, requestedTag)
            continue;
        end
        files = leadFieldFiles(t1File, tag);
        if ~leadFieldProductsExist(files)
            continue;
        end
        if ~leadFieldOptionsMatch(files.roastOptionsMat, names, ...
                referenceElectrode, opts)
            continue;
        end
        if ~customLocationsMatch(requestedLocations, files.customLocations, names)
            continue;
        end
        matches(end + 1) = struct( ... %#ok<AGROW>
            'tag', tag, ...
            'files', files, ...
            'datenum', resultFiles(i).datenum);
    end
end

function tag = tagFromResultFile(fileName, stem)
    prefix = [stem '_'];
    suffix = '_roastResult.mat';
    tag = '';
    if numel(fileName) <= numel(prefix) + numel(suffix)
        return;
    end
    if ~strcmp(fileName(1:numel(prefix)), prefix)
        return;
    end
    if ~strcmp(fileName((end - numel(suffix) + 1):end), suffix)
        return;
    end
    tag = fileName((numel(prefix) + 1):(end - numel(suffix)));
end

function tf = leadFieldOptionsMatch(optionsFile, names, referenceElectrode, opts)
    tf = false;
    try
        data = load(optionsFile, 'opt');
    catch
        return;
    end
    if ~isfield(data, 'opt') || ~isfield(data.opt, 'leadField') || ...
            isempty(data.opt.leadField)
        return;
    end
    if isfield(data.opt, 'dummy') && data.opt.dummy
        return;
    end
    if isfield(data.opt, 'approximateLeadField') && data.opt.approximateLeadField
        return;
    end
    if isfield(data.opt, 'surrogateExpandedLeadField') && ...
            data.opt.surrogateExpandedLeadField
        return;
    end
    leadField = data.opt.leadField;
    if isfield(leadField, 'dummy') && leadField.dummy
        return;
    end
    if isfield(leadField, 'approximate') && leadField.approximate
        return;
    end
    if isfield(leadField, 'surrogateExpanded') && leadField.surrogateExpanded
        return;
    end
    if isfield(leadField, 'mode') && ~strcmpi(char(leadField.mode), 'custom')
        return;
    end
    if ~isfield(leadField, 'includePassiveElectrodes') || ...
            ~leadField.includePassiveElectrodes
        return;
    end
    if ~isfield(leadField, 'electrodeNames') || ...
            ~namesEqual(leadField.electrodeNames, names)
        return;
    end
    if isfield(leadField, 'referenceElectrode') && ...
            ~strcmpi(char(leadField.referenceElectrode), referenceElectrode)
        return;
    end
    savedSegMaskFile = '';
    if isfield(data.opt, 'segMaskFile') && ~isempty(data.opt.segMaskFile)
        savedSegMaskFile = char(data.opt.segMaskFile);
    end
    if ~samePathOrText(savedSegMaskFile, opts.segMaskFile)
        return;
    end
    savedSegMaskFingerprint = [];
    if isfield(data.opt, 'segMaskFingerprint')
        savedSegMaskFingerprint = data.opt.segMaskFingerprint;
    end
    if ~isequal(savedSegMaskFingerprint, opts.segMaskFingerprint)
        return;
    end
    savedExtraTissues = [];
    if isfield(data.opt, 'extraTissues')
        savedExtraTissues = data.opt.extraTissues;
    end
    if ~isequal(savedExtraTissues, opts.extraTissues)
        return;
    end
    if ~conductivitiesMatch(data.opt, opts.effectiveConductivities)
        return;
    end
    tf = true;
end

function fingerprint = fileFingerprint(fileName)
    fingerprint = [];
    if isempty(fileName)
        return;
    end
    info = dir(fileName);
    if isempty(info)
        return;
    end
    fingerprint = struct('file', char(fileName), ...
        'bytes', info.bytes, ...
        'datenum', info.datenum, ...
        'date', info.date);
end

function tf = samePathOrText(a, b)
    a = char(a);
    b = char(b);
    if isempty(a) || isempty(b)
        tf = strcmp(a, b);
        return;
    end
    try
        a = char(java.io.File(a).getCanonicalPath());
        b = char(java.io.File(b).getCanonicalPath());
    catch
    end
    tf = strcmpi(a, b);
end

function tf = conductivitiesMatch(savedOpt, requestedConductivities)
    tf = false;
    if isempty(fieldnames(requestedConductivities))
        tf = true;
        return;
    end
    if ~isfield(savedOpt, 'conductivities') || isempty(savedOpt.conductivities)
        return;
    end
    fields = fieldnames(requestedConductivities);
    for i = 1:numel(fields)
        fieldName = fields{i};
        if ~isfield(savedOpt.conductivities, fieldName)
            return;
        end
        if ~isequaln(savedOpt.conductivities.(fieldName), ...
                requestedConductivities.(fieldName))
            return;
        end
    end
    tf = true;
end

function tf = namesEqual(a, b)
    a = normalizeNames(a);
    b = normalizeNames(b);
    tf = numel(a) == numel(b) && all(strcmpi(a(:), b(:)));
end

function tf = customLocationsMatch(requestedFile, candidateFile, names)
    tf = false;
    if isempty(requestedFile) || exist(requestedFile, 'file') ~= 2
        tf = true;
        return;
    end
    if exist(candidateFile, 'file') ~= 2
        return;
    end
    try
        [requestedNames, requestedCoords] = readCustomLocations(requestedFile);
        [candidateNames, candidateCoords] = readCustomLocations(candidateFile);
    catch
        return;
    end
    expected = normalizeNames(names);
    if isempty(expected)
        expected = requestedNames(:);
    end
    requestedOrdered = coordsByName(requestedNames, requestedCoords, expected);
    candidateOrdered = coordsByName(candidateNames, candidateCoords, expected);
    if isempty(requestedOrdered) || isempty(candidateOrdered)
        return;
    end
    tf = max(abs(requestedOrdered(:) - candidateOrdered(:))) <= 1e-3;
end

function coords = coordsByName(fileNames, fileCoords, expectedNames)
    coords = nan(numel(expectedNames), 3);
    for i = 1:numel(expectedNames)
        idx = find(strcmpi(expectedNames{i}, fileNames), 1);
        if isempty(idx)
            coords = [];
            return;
        end
        coords(i, :) = fileCoords(idx, :);
    end
end

function [names, coords] = readCustomLocations(fileName)
    fid = fopen(fileName, 'r');
    if fid == -1
        error('acsGenerateRoastLeadField:CannotReadCustomLocations', ...
            'Could not read custom electrode locations: %s', fileName);
    end
    cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
    C = textscan(fid, '%s %f %f %f');
    names = C{1};
    coords = [C{2}, C{3}, C{4}];
end
