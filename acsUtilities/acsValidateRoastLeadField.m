function out = acsValidateRoastLeadField(t1File, leadFieldTag, directRecipe, varargin)
% ACSVALIDATEROASTLEADFIELD Compare a lead-field sum with a direct GetDP solve.
%
% out = acsValidateRoastLeadField(t1File, leadFieldTag, recipe) reconstructs
% a montage from the ROAST lead-field basis, runs one direct GetDP solve on
% the same mesh, and compares electric-field vectors at mesh nodes.
%
% Name-value options:
%   validationTag         : suffix for temporary direct field ['directCheck']
%   forceDirectSolve      : rerun direct solve if its field exists [false]
%   deleteDirectField     : remove temporary direct field after QC [true]
%   relativeRmseTolerance : pass threshold for relative RMSE [1e-3]
%   showFigures           : show QC scatter and error histogram [false]
%   saveFigures           : save QC figure [false]
%   saveReport            : save MAT report beside the T1 [true]
%   verbose               : print summary [true]

    if nargin < 3
        error('acsValidateRoastLeadField:MissingInputs', ...
            'Provide t1File, leadFieldTag, and directRecipe.');
    end

    opts = parseInputs(varargin{:});
    t1File = char(t1File);
    leadFieldTag = char(leadFieldTag);
    [folder, stem] = fileparts(t1File);

    leadFieldResult = fullfile(folder, [stem '_' leadFieldTag '_roastResult.mat']);
    leadFieldOptions = fullfile(folder, [stem '_' leadFieldTag '_roastOptions.mat']);
    leadFieldMesh = fullfile(folder, [stem '_' leadFieldTag '_ready.msh']);
    usedAreaFile = fullfile(folder, [stem '_' leadFieldTag '_usedElecArea.mat']);
    directFieldFile = fullfile(folder, ...
        [stem '_' leadFieldTag '_e_' opts.validationTag '.pos']);

    requireFile(leadFieldResult);
    requireFile(leadFieldOptions);
    requireFile(leadFieldMesh);
    requireFile(usedAreaFile);

    resultData = load(leadFieldResult, 'A_all');
    if ~isfield(resultData, 'A_all')
        error('acsValidateRoastLeadField:MissingMatrix', ...
            'Lead-field result does not contain A_all: %s', leadFieldResult);
    end
    optionsData = load(leadFieldOptions, 'opt');
    if ~isfield(optionsData, 'opt') || ~isfield(optionsData.opt, 'leadField') || ...
            isempty(optionsData.opt.leadField)
        error('acsValidateRoastLeadField:MissingMetadata', ...
            'Lead-field options do not contain configurable lead-field metadata.');
    end
    leadField = optionsData.opt.leadField;
    if ~isfield(leadField, 'includePassiveElectrodes') || ...
            ~leadField.includePassiveElectrodes
        error('acsValidateRoastLeadField:InconsistentBasisDomain', ...
            ['Strict superposition validation requires a custom lead field ', ...
             'that retains passive candidate electrodes in every basis solve.']);
    end

    [recipeNames, recipeCurrents] = parseRecipe(directRecipe);
    [currentsByElectrode, coefficients] = prepareCurrents( ...
        recipeNames, recipeCurrents, leadField);

    if exist(directFieldFile, 'file') ~= 2 || opts.forceDirectSolve
        if opts.verbose
            fprintf('\nRunning direct GetDP validation solve on the lead-field mesh...\n');
        end
        extraTissues = [];
        if isfield(optionsData.opt, 'extraTissues')
            extraTissues = optionsData.opt.extraTissues;
        end
        solveByGetDP(t1File, currentsByElectrode, optionsData.opt.conductivities, ...
            1:numel(currentsByElectrode), leadFieldTag, ['_' opts.validationTag], ...
            extraTissues);
    end
    requireFile(directFieldFile);

    A_all = resultData.A_all;
    if size(A_all, 3) ~= numel(coefficients)
        error('acsValidateRoastLeadField:BadMatrixSize', ...
            'A_all contains %d basis fields, but metadata lists %d.', ...
            size(A_all, 3), numel(coefficients));
    end
    reconstructedField = sum(bsxfun(@times, A_all, ...
        reshape(coefficients, 1, 1, [])), 3);

    [nodeIds, directField] = readNodeTableField(directFieldFile);
    if any(nodeIds < 1) || any(nodeIds > size(reconstructedField, 1))
        error('acsValidateRoastLeadField:BadNodeIndex', ...
            'Direct field contains mesh-node indices outside the lead-field mesh.');
    end
    predictedField = reconstructedField(nodeIds, :);
    valid = all(isfinite(predictedField), 2) & all(isfinite(directField), 2);
    if ~any(valid)
        error('acsValidateRoastLeadField:NoComparableNodes', ...
            'No finite mesh-node electric-field values were available for comparison.');
    end

    predictedField = predictedField(valid, :);
    directField = directField(valid, :);
    difference = predictedField - directField;
    directVector = directField(:);
    predictedVector = predictedField(:);
    differenceVector = difference(:);
    rmse = sqrt(mean(differenceVector .^ 2));
    directRms = sqrt(mean(directVector .^ 2));
    relativeRmse = rmse / max(directRms, eps);
    maxAbsError = max(abs(differenceVector));
    C = corrcoef(directVector, predictedVector);
    if numel(C) >= 4
        correlation = C(1, 2);
    else
        correlation = NaN;
    end

    out = struct();
    out.createdOn = char(datetime('now'));
    out.t1File = t1File;
    out.leadFieldTag = leadFieldTag;
    out.validationTag = opts.validationTag;
    out.referenceElectrode = leadField.referenceElectrode;
    out.electrodeNames = leadField.electrodeNames;
    out.stimulusElectrodeNames = leadField.stimulusElectrodeNames;
    out.recipe = directRecipe;
    out.currentsByElectrodeMa = currentsByElectrode;
    out.basisCoefficientsMa = coefficients;
    out.comparedNodeCount = nnz(valid);
    out.rmseVm = rmse;
    out.relativeRmse = relativeRmse;
    out.maxAbsErrorVm = maxAbsError;
    out.correlation = correlation;
    out.relativeRmseTolerance = opts.relativeRmseTolerance;
    out.pass = relativeRmse <= opts.relativeRmseTolerance;
    out.reportMat = fullfile(folder, ...
        [stem '_' leadFieldTag '_' opts.validationTag '_leadFieldValidation.mat']);
    out.qcFigure = '';
    out.directFieldFile = directFieldFile;
    out.deletedDirectField = false;

    fig = [];
    if opts.showFigures || opts.saveFigures
        figVisible = 'off';
        if opts.showFigures, figVisible = 'on'; end
        fig = makeQcFigure(directVector, predictedVector, differenceVector, ...
            out, figVisible);
        if opts.saveFigures
            qcDir = fullfile(folder, 'qc');
            ensureDir(qcDir);
            out.qcFigure = fullfile(qcDir, ...
                [stem '_' leadFieldTag '_' opts.validationTag '_leadFieldValidation.png']);
            saveas(fig, out.qcFigure);
        end
        if ~opts.showFigures
            close(fig);
        end
    end

    if opts.deleteDirectField
        delete(directFieldFile);
        out.deletedDirectField = true;
    end
    if opts.saveReport
        save(out.reportMat, 'out');
    end
    if opts.verbose
        printSummary(out);
    end
end

function opts = parseInputs(varargin)
    p = inputParser;
    p.FunctionName = 'acsValidateRoastLeadField';
    addParameter(p, 'validationTag', 'directCheck', @(x) ischar(x) || isstring(x));
    addParameter(p, 'forceDirectSolve', false, @isBoolLike);
    addParameter(p, 'deleteDirectField', true, @isBoolLike);
    addParameter(p, 'relativeRmseTolerance', 1e-3, ...
        @(x) isnumeric(x) && isscalar(x) && x > 0);
    addParameter(p, 'showFigures', false, @isBoolLike);
    addParameter(p, 'saveFigures', false, @isBoolLike);
    addParameter(p, 'saveReport', true, @isBoolLike);
    addParameter(p, 'verbose', true, @isBoolLike);
    parse(p, varargin{:});
    opts = p.Results;
    opts.validationTag = char(opts.validationTag);
    opts.forceDirectSolve = logical(opts.forceDirectSolve);
    opts.deleteDirectField = logical(opts.deleteDirectField);
    opts.showFigures = logical(opts.showFigures);
    opts.saveFigures = logical(opts.saveFigures);
    opts.saveReport = logical(opts.saveReport);
    opts.verbose = logical(opts.verbose);
    if isempty(opts.validationTag) || ~isvarname(opts.validationTag)
        error('acsValidateRoastLeadField:BadValidationTag', ...
            'validationTag must be a non-empty MATLAB-style identifier.');
    end
end

function tf = isBoolLike(x)
    tf = (islogical(x) || isnumeric(x)) && isscalar(x);
end

function requireFile(fileName)
    if exist(fileName, 'file') ~= 2
        error('acsValidateRoastLeadField:MissingFile', ...
            'Required file not found: %s', fileName);
    end
end

function [names, currents] = parseRecipe(recipe)
    if ~iscell(recipe) || mod(numel(recipe), 2) ~= 0
        error('acsValidateRoastLeadField:BadRecipe', ...
            'directRecipe must contain electrode-name/current pairs.');
    end
    names = recipe(1:2:end);
    names = cellfun(@char, names(:), 'UniformOutput', false);
    try
        currents = cell2mat(recipe(2:2:end))';
    catch
        error('acsValidateRoastLeadField:BadRecipe', ...
            'Every directRecipe current must be numeric.');
    end
    currents = double(currents(:));
end

function [currentsByElectrode, coefficients] = prepareCurrents(names, currents, leadField)
    allNames = leadField.electrodeNames(:);
    stimulusNames = leadField.stimulusElectrodeNames(:);
    if abs(sum(currents)) > 1e-12
        error('acsValidateRoastLeadField:UnbalancedRecipe', ...
            'Direct recipe currents must sum to zero.');
    end
    if numel(unique(lower(string(names)))) ~= numel(names)
        error('acsValidateRoastLeadField:DuplicateElectrodes', ...
            'Direct recipe contains duplicated electrode names.');
    end
    if ~all(ismember(lower(string(names)), lower(string(allNames))))
        error('acsValidateRoastLeadField:UnknownElectrode', ...
            'Direct recipe contains electrodes outside the lead-field candidate list.');
    end

    currentsByElectrode = zeros(numel(allNames), 1);
    for i = 1:numel(names)
        idx = find(strcmpi(names{i}, allNames), 1);
        currentsByElectrode(idx) = currents(i);
    end

    coefficients = zeros(numel(stimulusNames), 1);
    for i = 1:numel(stimulusNames)
        idx = find(strcmpi(stimulusNames{i}, allNames), 1);
        coefficients(i) = currentsByElectrode(idx);
    end
    refIdx = find(strcmpi(leadField.referenceElectrode, allNames), 1);
    impliedReferenceCurrent = -sum(coefficients);
    if abs(currentsByElectrode(refIdx) - impliedReferenceCurrent) > 1e-12
        error('acsValidateRoastLeadField:ReferenceMismatch', ...
            ['Direct recipe reference current is %.6g mA, while the basis ', ...
             'combination implies %.6g mA.'], ...
            currentsByElectrode(refIdx), impliedReferenceCurrent);
    end
end

function [nodeIds, field] = readNodeTableField(fileName)
    fid = fopen(fileName, 'r');
    if fid == -1
        error('acsValidateRoastLeadField:CannotReadField', ...
            'Could not open direct field file: %s', fileName);
    end
    cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fgetl(fid);
    C = textscan(fid, '%d %f %f %f');
    nodeIds = double(C{1});
    field = [C{2}, C{3}, C{4}];
end

function fig = makeQcFigure(directField, predictedField, difference, out, visible)
    fig = figure('Name', 'ROAST lead-field superposition QC', ...
        'Color', 'w', 'Visible', visible, 'Position', [100 100 1100 460]);
    ax1 = subplot(1, 2, 1, 'Parent', fig);
    plot(ax1, directField, predictedField, '.', 'MarkerSize', 4);
    hold(ax1, 'on');
    lim = [min([directField; predictedField]), max([directField; predictedField])];
    plot(ax1, lim, lim, 'k-', 'LineWidth', 1);
    axis(ax1, 'equal');
    xlim(ax1, lim);
    ylim(ax1, lim);
    xlabel(ax1, 'Direct GetDP field (V/m)');
    ylabel(ax1, 'Lead-field reconstruction (V/m)');
    title(ax1, sprintf('Node components, r = %.6f', out.correlation));
    grid(ax1, 'on');

    ax2 = subplot(1, 2, 2, 'Parent', fig);
    histogram(ax2, difference, 80);
    xlabel(ax2, 'Reconstruction error (V/m)');
    ylabel(ax2, 'Mesh-node components');
    title(ax2, sprintf('Relative RMSE = %.3g', out.relativeRmse));
    grid(ax2, 'on');
end

function ensureDir(folder)
    if exist(folder, 'dir') ~= 7
        mkdir(folder);
    end
end

function printSummary(out)
    fprintf('\nROAST lead-field superposition validation\n');
    fprintf('  lead field tag: %s\n', out.leadFieldTag);
    fprintf('  validation tag: %s\n', out.validationTag);
    fprintf('  compared nodes: %d\n', out.comparedNodeCount);
    fprintf('  relative RMSE: %.6g\n', out.relativeRmse);
    fprintf('  correlation: %.9f\n', out.correlation);
    fprintf('  maximum absolute error: %.6g V/m\n', out.maxAbsErrorVm);
    if out.pass
        fprintf('  result: PASS\n\n');
    else
        fprintf('  result: CHECK REQUIRED\n\n');
    end
end
