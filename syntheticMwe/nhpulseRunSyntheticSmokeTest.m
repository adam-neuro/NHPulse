function out = nhpulseRunSyntheticSmokeTest(outputDir, varargin)
% NHPULSERUNSYNTHETICSMOKETEST Run a quick synthetic NHPulse MWE smoke test.
%
% out = nhpulseRunSyntheticSmokeTest() creates synthetic ROAST-ready anatomy,
% builds a ROAST-derived scalp cache, and places a small custom-location
% layout directly on the ROAST label surface. It intentionally stops before
% running ROAST leadfield solves.
%
% Name-value options:
%   nElectrodes : number of toy electrodes [8]
%   force       : overwrite generated products [true]
%   showFigures : show QC figures [true]
%   saveFigures : save QC figures [true]
%   verbose     : print progress [true]

    parameterNames = {'nElectrodes', 'force', 'showFigures', ...
        'saveFigures', 'verbose'};

    if nargin < 1 || isempty(outputDir)
        outputDir = fullfile(defaultRepoRoot(), 'outputs', ...
            'syntheticMwe', 'nhpulseSyntheticSmoke');
    elseif isNameValueKey(outputDir, parameterNames)
        varargin = [{outputDir}, varargin];
        outputDir = fullfile(defaultRepoRoot(), 'outputs', ...
            'syntheticMwe', 'nhpulseSyntheticSmoke');
    end

    opts = parseInputs(parameterNames, varargin{:});
    addLocalDependencies();
    nhpulseEnsureWritableDir(outputDir, 'synthetic smoke-test output');
    restoreFigureWindowStyle = setTemporaryFigureWindowStyle('normal');

    syntheticOut = nhpulseCreateSyntheticRoastReadyData(outputDir, ...
        'subjectId', 'nhpulseSyntheticSmoke', ...
        'force', opts.force, ...
        'showFigure', opts.showFigures, ...
        'saveFigure', opts.saveFigures, ...
        'verbose', opts.verbose);

    scalpCacheFile = fullfile(outputDir, ...
        'nhpulseSyntheticSmoke_roastScalpSkinMesh.mat');
    scalp = acsBuildRoastScalpSkinCache(syntheticOut, ...
        'outputFile', scalpCacheFile, ...
        'force', opts.force, ...
        'maxFaces', 8000, ...
        'showFigures', opts.showFigures, ...
        'saveFigures', opts.saveFigures, ...
        'verbose', opts.verbose);

    customLocationsFile = fullfile(outputDir, ...
        'nhpulseSyntheticSmoke_customLocations');
    layout = acsMakeRoastCapMakerLayout(syntheticOut, ...
        'surfaceSource', 'roastLabels', ...
        'nElectrodes', opts.nElectrodes, ...
        'outputFile', customLocationsFile, ...
        'forceLayout', opts.force, ...
        'showFigures', opts.showFigures, ...
        'saveFigures', opts.saveFigures, ...
        'verbose', opts.verbose);

    out = struct();
    out.createdOn = char(datetime('now'));
    out.type = 'nhpulseSyntheticSmokeTest';
    out.outputDir = char(outputDir);
    out.synthetic = syntheticOut;
    out.scalp = stripFigure(scalp);
    out.layout = stripFigure(layout);
    out.customLocationsFile = customLocationsFile;
    out.nextStepHint = sprintf(['A full ROAST solve would use roast(%s, ', ...
        '''leadField'', %s, ...), but this smoke test intentionally stops ', ...
        'before expensive meshing/solve steps.'], ...
        quoted(syntheticOut.t1File), quoted(customLocationsFile));

    reportFile = fullfile(outputDir, 'nhpulseSyntheticSmoke_smokeTest.mat');
    out.reportFile = reportFile;
    outReturned = out;
    outForSave = stripFigure(out);
    out = outForSave; %#ok<NASGU>
    outSaved = outForSave; %#ok<NASGU>
    outToSave = outForSave; %#ok<NASGU>
    save(reportFile, 'out', 'outForSave', 'outSaved', 'outToSave', '-v7.3');
    out = outReturned;

    if opts.verbose
        fprintf('\nNHPulse synthetic smoke test complete\n');
        fprintf('  output: %s\n', out.outputDir);
        fprintf('  scalp cache: %s\n', scalp.cacheFile);
        fprintf('  custom locations: %s\n', customLocationsFile);
        fprintf('  report: %s\n\n', reportFile);
    end

    clear restoreFigureWindowStyle;
end

function opts = parseInputs(parameterNames, varargin)
    p = inputParser;
    p.FunctionName = 'nhpulseRunSyntheticSmokeTest';
    addParameter(p, 'nElectrodes', 8, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 2);
    addParameter(p, 'force', true, @isBoolLike);
    addParameter(p, 'showFigures', true, @isBoolLike);
    addParameter(p, 'saveFigures', true, @isBoolLike);
    addParameter(p, 'verbose', true, @isBoolLike);
    parse(p, varargin{:});

    opts = p.Results;
    opts.nElectrodes = round(double(opts.nElectrodes));
    opts.force = logical(opts.force);
    opts.showFigures = logical(opts.showFigures);
    opts.saveFigures = logical(opts.saveFigures);
    opts.verbose = logical(opts.verbose);

    unknown = setdiff(fieldnames(opts), parameterNames);
    if ~isempty(unknown)
        error('nhpulseRunSyntheticSmokeTest:BadParser', ...
            'Internal parser mismatch: %s', strjoin(unknown, ', '));
    end
end

function tf = isBoolLike(x)
    tf = (islogical(x) || isnumeric(x)) && isscalar(x);
end

function tf = isNameValueKey(value, parameterNames)
    tf = (ischar(value) || isstring(value)) && ...
        any(strcmpi(char(value), parameterNames));
end

function addLocalDependencies()
    repoRoot = defaultRepoRoot();
    if exist('setNHPulsePath', 'file') ~= 2
        addpath(repoRoot);
    end
    setNHPulsePath('repoRoot', repoRoot, 'verbose', false);
    spmDir = fullfile(repoRoot, 'lib', 'spm12');
    if exist(spmDir, 'dir') == 7
        addpath(spmDir);
    end
end

function repoRoot = defaultRepoRoot()
    repoRoot = fileparts(fileparts(mfilename('fullpath')));
end

function cleaner = setTemporaryFigureWindowStyle(style)
    cleaner = [];
    try
        oldStyle = get(groot, 'defaultFigureWindowStyle');
        set(groot, 'defaultFigureWindowStyle', style);
        cleaner = onCleanup(@() set(groot, 'defaultFigureWindowStyle', oldStyle));
    catch
        cleaner = onCleanup(@() []);
    end
end

function S = stripFigure(S)
    if isstruct(S)
        if isfield(S, 'figure')
            S = rmfield(S, 'figure');
        end
        fields = fieldnames(S);
        for i = 1:numel(S)
            for j = 1:numel(fields)
                if isstruct(S(i).(fields{j}))
                    S(i).(fields{j}) = stripFigure(S(i).(fields{j}));
                end
            end
        end
    end
end

function txt = quoted(value)
    txt = ['''' strrep(char(value), '''', '''''') ''''];
end
