function cfg = nhpulseExampleConfig(preset, varargin)
% NHPULSEEXAMPLECONFIG Return named configuration presets for public examples.
%
% cfg = nhpulseExampleConfig() returns the default reviewer-facing synthetic
% walkthrough configuration.
%
% cfg = nhpulseExampleConfig('syntheticFast') returns a deterministic,
% mostly noninteractive version that uses dummy lead fields.
%
% cfg = nhpulseExampleConfig('syntheticRoast') returns a noninteractive
% configuration that exercises real ROAST/GetDP lead-field solves on the
% synthetic head.
%
% Name-value pairs after the preset override individual cfg fields, for
% example:
%
%   cfg = nhpulseExampleConfig('syntheticFast', 'showFigures', false);
%   cfg = nhpulseExampleConfig('syntheticReviewer', 'leadFieldMode', 'roast');

    if nargin < 1 || isempty(preset)
        preset = 'syntheticReviewer';
    end

    if isNameValuePairStart(preset, varargin)
        varargin = [{preset}, varargin];
        preset = 'syntheticReviewer';
    end

    preset = validatestring(char(preset), { ...
        'syntheticReviewer', ...
        'syntheticInteractive', ...
        'syntheticFast', ...
        'syntheticSmoke', ...
        'syntheticRoast'});

    cfg = baseSyntheticConfig();

    switch lower(preset)
        case {'syntheticreviewer', 'syntheticinteractive'}
            cfg.preset = 'syntheticReviewer';
            cfg.interactiveSelections = true;
            cfg.leadFieldMode = 'dummy';
            cfg.showFigures = true;
            cfg.saveFigures = true;
        case {'syntheticfast', 'syntheticsmoke'}
            cfg.preset = 'syntheticFast';
            cfg.interactiveSelections = false;
            cfg.leadFieldMode = 'dummy';
            cfg.showFigures = true;
            cfg.saveFigures = true;
            cfg.force = true;
        case 'syntheticroast'
            cfg.preset = 'syntheticRoast';
            cfg.interactiveSelections = false;
            cfg.leadFieldMode = 'roast';
            cfg.showFigures = true;
            cfg.saveFigures = true;
            cfg.realLeadFieldShowFigures = false;
            cfg.force = true;
    end

    cfg = applyOverrides(cfg, varargin{:});
    cfg.demoHeadpostRadiusMm = 12.625 * cfg.demoHeadpostScale;
    cfg.outputDir = char(cfg.outputDir);
end

function cfg = baseSyntheticConfig()
    repoRoot = fileparts(mfilename('fullpath'));
    outputRoot = fullfile(repoRoot, 'outputs');
    if exist('acsPaths', 'file') == 2
        try
            P = acsPaths();
            if isfield(P, 'outputRoot') && ~isempty(P.outputRoot)
                outputRoot = P.outputRoot;
            end
        catch
            % Fall back to the repo-local output folder.
        end
    end

    cfg = struct();
    cfg.preset = 'syntheticReviewer';
    cfg.subjectId = 'nhpulseSyntheticDemo';
    cfg.outputDir = fullfile(outputRoot, 'syntheticMwe', cfg.subjectId);
    cfg.force = true;
    cfg.showFigures = true;
    cfg.saveFigures = true;
    cfg.interactiveSelections = true;

    cfg.fitCheckElectrodes = 6;
    cfg.initialTesCandidates = 8;
    cfg.nGrowthSteps = 2;
    cfg.nNewCandidatesPerStep = 2;
    cfg.activeTesChannels = 4;
    cfg.nEegChannels = 4;

    cfg.leadFieldMode = 'dummy';
    cfg.dummyLeadFieldMeshSpacingMm = 3;
    cfg.realLeadFieldResampling = 'off';
    cfg.realLeadFieldElectrodeModel = 'syntheticDemo';
    cfg.realLeadFieldMeshOptions = struct('radbound', 2, ...
        'angbound', 30, 'distbound', 0.2, 'reratio', 3, 'maxvol', 2);
    cfg.realLeadFieldTagSuffix = 'airgel01';
    cfg.realLeadFieldShowFigures = false;

    cfg.targetRadiusMm = 4;
    cfg.targetOrientation = [0 0 1];
    cfg.sparseSearchMode = 'developmentHeuristic';

    cfg.headpostMarginMm = 4;
    cfg.syntheticCropAxis = [-0.112 -0.112 0.987];
    cfg.syntheticCropDistanceMm = 32.60;
    cfg.demoHeadpostScale = 0.60;
    cfg.demoHeadpostRadiusMm = 12.625 * cfg.demoHeadpostScale;

    cfg.layoutEdgeMarginMm = 3;
    cfg.layoutBedMarginMm = 1;
    cfg.layoutNormalUpDotMin = 0;
    cfg.demoElectrodeFootprintDiameterMm = 9;
    cfg.demoElectrodeClearanceMm = 0.5;
    cfg.demoMinDistanceMm = 10;
    cfg.demoEegTesClearanceMm = 10;

    cfg.fitCheckGridSurfaceMaxFaces = 220;
    cfg.finalManufacturingSurfaceMaxFaces = 350;
    cfg.finalRailSurfaceMaxFaces = 350;
    cfg.finalRailEdgeMarginMm = 2;
end

function cfg = applyOverrides(cfg, varargin)
    if isempty(varargin)
        return;
    end
    if mod(numel(varargin), 2) ~= 0
        error('nhpulseExampleConfig:BadInputs', ...
            'Overrides must be supplied as name-value pairs.');
    end
    valid = fieldnames(cfg);
    for i = 1:2:numel(varargin)
        key = char(varargin{i});
        match = find(strcmpi(key, valid), 1);
        if isempty(match)
            error('nhpulseExampleConfig:UnknownField', ...
                ['Unknown NHPulse example config field "%s". ', ...
                 'Run cfg = nhpulseExampleConfig() to inspect supported fields.'], key);
        end
        cfg.(valid{match}) = varargin{i + 1};
    end
end

function tf = isNameValuePairStart(value, rest)
    tf = false;
    if ~(ischar(value) || isstring(value))
        return;
    end
    if isempty(rest) || mod(numel(rest), 2) ~= 1
        return;
    end
    knownPresets = {'syntheticReviewer', 'syntheticInteractive', ...
        'syntheticFast', 'syntheticSmoke', 'syntheticRoast'};
    tf = ~any(strcmpi(char(value), knownPresets));
end
