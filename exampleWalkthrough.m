%% NHPulse Synthetic Example Walkthrough
% This is the public-facing minimal working example for NHPulse. It creates a
% tiny synthetic, ROAST-ready anatomy and exercises the first practical pieces
% of the NHPulse workflow without requiring private MRI, DICOM, phone-scan, or
% lead-field data.
%
% The synthetic head is intentionally cartoon-like. It is useful for checking
% installation, file formats, coordinate plumbing, and cap-layout code paths;
% it is not anatomically realistic and should not be used for scientific
% simulation claims.
%
% ROAST credit: NHPulse builds on ROAST. Please cite ROAST and the relevant
% papers listed in CITATION.md when using this code.
%
% Safety note: this is research software, not a medical device.

%% 00 - Configure MATLAB Path And Demo Settings
% Run this cell from the repository root.

% clear;  % Uncomment when intentionally starting a clean MATLAB session.
% clc;

repoRoot = fileparts(mfilename('fullpath'));
if isempty(repoRoot)
    repoRoot = pwd;
end

setNHPulsePath('repoRoot', repoRoot);
P = acsPaths();
if isempty(P.configFile)
    fprintf(['No local.paths.json found; using default repo-local outputs.\n', ...
        'Run nhpulseConfigureLocalPaths if you want to save machine-specific paths.\n']);
end

cfg = struct();
cfg.subjectId = 'nhpulseSyntheticDemo';
cfg.outputDir = fullfile(P.outputRoot, 'syntheticMwe', cfg.subjectId);
cfg.nElectrodes = 8;
cfg.force = true;
cfg.showFigures = true;
cfg.saveFigures = true;

fprintf('NHPulse synthetic walkthrough output:\n  %s\n', cfg.outputDir);

%% 01 - Create Synthetic ROAST-Ready Anatomy
% This creates:
%   *_T1.nii
%   *_T1_T1orT2_SPM_masks.nii
%   synthetic model/phone fiducials
%   a synthetic phone-scan-like PLY/MAT surface
%
% The returned struct has syntheticOut.roastReady, which is the smallest
% useful public entry point into the NHPulse pipeline.

syntheticOut = nhpulseCreateSyntheticRoastReadyData(cfg.outputDir, ...
    'subjectId', cfg.subjectId, ...
    'force', cfg.force, ...
    'showFigure', cfg.showFigures, ...
    'saveFigure', cfg.saveFigures);

disp(syntheticOut.roastReady)

%% 02 - Build A ROAST-Derived Scalp Mesh Cache
% This mirrors the real workflow's move toward one shared scalp surface for
% ROAST/capMaker integration. The cache is stored under outputs/, so it is not
% meant to be committed to git.

scalpCacheFile = fullfile(cfg.outputDir, ...
    sprintf('%s_roastScalpSkinMesh.mat', cfg.subjectId));

scalpCache = acsBuildRoastScalpSkinCache(syntheticOut, ...
    'outputFile', scalpCacheFile, ...
    'force', cfg.force, ...
    'maxFaces', 8000, ...
    'showFigures', cfg.showFigures, ...
    'saveFigures', cfg.saveFigures, ...
    'verbose', true);

fprintf('Scalp cache mesh: %d vertices, %d faces\n', ...
    scalpCache.meshStats.nVertices, scalpCache.meshStats.nFaces);

%% 03 - Place A Toy Custom Electrode Layout
% This places electrodes on the synthetic ROAST label surface and writes the
% ROAST customLocations file. It does not run a ROAST solve.

customLocationsFile = fullfile(cfg.outputDir, ...
    sprintf('%s_customLocations', cfg.subjectId));

layout = acsMakeRoastCapMakerLayout(syntheticOut, ...
    'surfaceSource', 'roastLabels', ...
    'nElectrodes', cfg.nElectrodes, ...
    'outputFile', customLocationsFile, ...
    'forceLayout', cfg.force, ...
    'showFigures', cfg.showFigures, ...
    'saveFigures', cfg.saveFigures, ...
    'verbose', true);

disp(table(layout.names(:), layout.voxelCoordinates(:, 1), ...
    layout.voxelCoordinates(:, 2), layout.voxelCoordinates(:, 3), ...
    'VariableNames', {'Name', 'VoxelX', 'VoxelY', 'VoxelZ'}));

%% 04 - One-Call Smoke Test Alternative
% The three cells above are written out for readability. For installation
% checks, the same lightweight path can be run with one command.

smokeOut = nhpulseRunSyntheticSmokeTest( ...
    fullfile(repoRoot, 'outputs', 'syntheticMwe', 'nhpulseSyntheticSmoke'), ...
    'force', true, ...
    'showFigures', cfg.showFigures, ...
    'saveFigures', cfg.saveFigures);

fprintf('Smoke test report:\n  %s\n', smokeOut.reportFile);

%% 05 - Where A Full Workflow Would Continue
% A full subject workflow would next generate ROAST lead fields, optimize a
% sparse tES montage, optionally add EEG sites, and export manufacturing STLs.
% Those steps are intentionally outside this minimal example because they
% require heavier external dependencies and much longer runtimes.
%
% For real data, use this synthetic walkthrough as an installation check, then
% adapt the documented private/research workflow to your subject-specific MRI,
% phone scan, implants, and targeting choices.

fprintf('Synthetic MWE complete. Generated files live under:\n  %s\n', cfg.outputDir);
