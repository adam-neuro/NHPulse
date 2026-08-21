function [P, cfg] = nhpulseConfigureLocalPaths(varargin)
% NHPULSECONFIGURELOCALPATHS Create a local NHPulse path config file.
%
% [P, cfg] = nhpulseConfigureLocalPaths() creates or updates
% local.paths.json in the repository root using sensible defaults for the
% synthetic walkthrough. Existing nonempty values are preserved unless
% 'force' is true.
%
% Name-value options:
%   repoRoot    : top-level NHPulse folder [folder containing this file]
%   configFile  : JSON file to write [repoRoot/local.paths.json]
%   profile     : 'syntheticMwe' or 'research' ['syntheticMwe']
%   subjectId   : demo subject key ['nhpulseSyntheticDemo']
%   useGui      : offer file/folder picker dialogs [false]
%   force       : replace existing values with defaults [false]
%   writeFile   : write JSON config to disk [true]
%   verbose     : print paths and field descriptions [true]
%
% The generated JSON is ignored by git. It stores machine-specific roots and
% optional external MATLAB/tool paths, while generated data should live under
% outputRoot or another user-chosen folder outside version control.

    opts = parseInputs(varargin{:});
    repoRoot = opts.repoRoot;
    if isempty(repoRoot)
        repoRoot = fileparts(mfilename('fullpath'));
    end
    opts.repoRoot = repoRoot;

    if isempty(opts.configFile)
        opts.configFile = fullfile(repoRoot, 'local.paths.json');
    end

    setNHPulsePath('repoRoot', repoRoot, 'includeExternal', false, ...
        'verbose', false);

    defaults = makeDefaultConfig(opts);
    existing = loadExistingConfig(opts.configFile);
    if opts.force || isempty(fieldnames(existing))
        cfg = defaults;
    else
        cfg = mergeMissingOrEmpty(existing, defaults);
    end

    if opts.useGui
        cfg = editConfigWithDialogs(cfg, opts);
    end
    cfg = normalizeExecutableFields(cfg);

    if opts.writeFile
        ensureDir(fileparts(opts.configFile));
        writeJson(opts.configFile, cfg);
        setenv('ACS_PATHS_CONFIG', opts.configFile);
    end

    setNHPulsePath('repoRoot', repoRoot, 'configFile', opts.configFile, ...
        'includeExternal', true, 'verbose', false);

    if opts.writeFile
        P = acsPaths('configFile', opts.configFile);
    else
        P = acsPaths();
    end

    if opts.verbose
        printSummary(opts.configFile, cfg, opts.writeFile);
    end
end

function opts = parseInputs(varargin)
    p = inputParser;
    p.FunctionName = 'nhpulseConfigureLocalPaths';
    addParameter(p, 'repoRoot', fileparts(mfilename('fullpath')), ...
        @(x) ischar(x) || isstring(x));
    addParameter(p, 'configFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'profile', 'syntheticMwe', @(x) ischar(x) || isstring(x));
    addParameter(p, 'subjectId', 'nhpulseSyntheticDemo', @(x) ischar(x) || isstring(x));
    addParameter(p, 'useGui', false, @(x) (islogical(x) || isnumeric(x)) && isscalar(x));
    addParameter(p, 'force', false, @(x) (islogical(x) || isnumeric(x)) && isscalar(x));
    addParameter(p, 'writeFile', true, @(x) (islogical(x) || isnumeric(x)) && isscalar(x));
    addParameter(p, 'verbose', true, @(x) (islogical(x) || isnumeric(x)) && isscalar(x));
    parse(p, varargin{:});

    opts = p.Results;
    opts.repoRoot = normalizePath(opts.repoRoot);
    opts.configFile = normalizePath(opts.configFile);
    opts.profile = validatestring(char(opts.profile), {'syntheticMwe', 'research'});
    opts.subjectId = char(opts.subjectId);
    opts.useGui = logical(opts.useGui);
    opts.force = logical(opts.force);
    opts.writeFile = logical(opts.writeFile);
    opts.verbose = logical(opts.verbose);
end

function cfg = makeDefaultConfig(opts)
    outputRoot = fullfile(opts.repoRoot, 'outputs');
    dataRoot = fullfile(opts.repoRoot, 'data');
    demoRoot = fullfile(outputRoot, 'syntheticMwe', opts.subjectId);
    subjectKey = matlab.lang.makeValidName(opts.subjectId);

    cfg = struct();
    cfg.profile = opts.profile;
    cfg.repoRoot = opts.repoRoot;
    cfg.boxRoot = '';
    cfg.dataRoot = dataRoot;
    cfg.outputRoot = outputRoot;
    cfg.roastWorkRoot = fullfile(outputRoot, 'roast_work');
    cfg.inpolyhedronPath = fullfile(opts.repoRoot, 'acsUtilities', 'inpolyhedron.m');
    cfg.spmPath = firstExistingFolder({ ...
        fullfile(opts.repoRoot, 'lib', 'spm'), ...
        fullfile(opts.repoRoot, 'lib', 'spm12'), ...
        functionFolder('spm_vol')});
    cfg.iso2meshPath = firstExistingFolder({ ...
        fullfile(opts.repoRoot, 'lib', 'iso2mesh'), ...
        functionFolder('vol2mesh'), ...
        functionFolder('surf2mesh')});
    cfg.cvxPath = firstExistingFolder({ ...
        fullfile(opts.repoRoot, 'lib', 'cvx'), ...
        functionFolder('cvx_setup'), ...
        cvxRootFromKeyword(functionFolder('cvx_begin')), ...
        functionFolder('cvx_begin')});
    cfg.niftiPath = firstExistingFolder({ ...
        fullfile(opts.repoRoot, 'lib', 'NIFTI_20110921'), ...
        functionFolder('load_nii')});
    cfg.getdpExecutable = firstExistingFile({ ...
        fullfile(opts.repoRoot, 'lib', 'getdp-3.2.0', 'bin', executableName('getdp')), ...
        whichOnPath(executableName('getdp'))});
    cfg.gmshExecutable = firstExistingFile({ ...
        fullfile(opts.repoRoot, 'lib', 'gmsh', executableName('gmsh')), ...
        fullfile(opts.repoRoot, 'lib', 'gmsh', 'Gmsh.app', 'Contents', 'MacOS', 'gmsh'), ...
        fullfile(opts.repoRoot, 'lib', 'gmsh', 'Gmsh.app', 'Contents', 'MacOS', 'Gmsh'), ...
        whichOnPath(executableName('gmsh'))});
    cfg.extraMatlabPaths = {};

    demo = struct();
    demo.aliases = {'demo', 'synthetic'};
    demo.root = demoRoot;
    demo.mprageInitial = fullfile(demoRoot, [opts.subjectId '_T1.nii']);
    demo.anatomyWork = fullfile(demoRoot, 'anatomy');
    demo.segmentationWork = fullfile(demoRoot, 'segmentation');

    cfg.subjects = struct();
    cfg.subjects.(subjectKey) = demo;
end

function cfg = editConfigWithDialogs(cfg, opts)
    if ~usejava('desktop')
        warning('nhpulseConfigureLocalPaths:NoDesktop', ...
            'MATLAB desktop UI is not available; using automatic defaults.');
        return;
    end

    answer = questdlg( ...
        ['NHPulse can write a local.paths.json file using demo defaults, ', ...
         'or you can review common folders with pickers.'], ...
        'NHPulse local setup', ...
        'Use defaults', 'Review folders', 'Cancel', 'Use defaults');
    if isempty(answer) || strcmp(answer, 'Cancel')
        error('nhpulseConfigureLocalPaths:Cancelled', ...
            'NHPulse local path setup was cancelled.');
    end
    if strcmp(answer, 'Use defaults')
        return;
    end

    cfg.outputRoot = chooseFolder(cfg.outputRoot, ...
        'Generated output root', ...
        ['Where NHPulse should write generated demo files, QC figures, ', ...
         'lead fields, and manufacturing products.']);
    cfg.dataRoot = chooseFolder(cfg.dataRoot, ...
        'External/source data root', ...
        ['Optional root for raw source data that should not be committed ', ...
         'to git, such as real subject MRI or scan exports.']);
    cfg.roastWorkRoot = chooseFolder(cfg.roastWorkRoot, ...
        'ROAST work root', ...
        'Scratch/work folder for longer ROAST meshing and solver products.');
    cfg.spmPath = chooseFolder(cfg.spmPath, ...
        'SPM MATLAB folder', ...
        'Optional folder containing SPM functions such as spm_vol.');
    cfg.iso2meshPath = chooseFolder(cfg.iso2meshPath, ...
        'iso2mesh MATLAB folder', ...
        'Optional folder containing iso2mesh functions such as vol2mesh.');
    cfg.cvxPath = chooseFolder(cfg.cvxPath, ...
        'CVX MATLAB folder', ...
        'Optional folder containing CVX for sparse tES optimization.');
    cfg.niftiPath = chooseFolder(cfg.niftiPath, ...
        'NIfTI utility folder', ...
        'Optional folder containing load_nii/save_nii fallback utilities.');
    cfg.inpolyhedronPath = chooseFile(cfg.inpolyhedronPath, ...
        'inpolyhedron.m', ...
        'Select bundled or external inpolyhedron.m for mesh voxelization.');
    cfg.getdpExecutable = chooseExecutable(cfg.getdpExecutable, ...
        'GetDP executable', ...
        ['Optional executable used by full ROAST finite-element solves. ', ...
         'This is not needed for the synthetic smoke test.']);
    cfg.gmshExecutable = chooseExecutable(cfg.gmshExecutable, ...
        'Gmsh executable', ...
        ['Optional executable used by ROAST/Gmsh mesh visualization and ', ...
         'support workflows. This is not needed for the synthetic smoke test.']);

    subjectKey = matlab.lang.makeValidName(opts.subjectId);
    if isfield(cfg, 'subjects') && isfield(cfg.subjects, subjectKey)
        cfg.subjects.(subjectKey).root = fullfile(cfg.outputRoot, ...
            'syntheticMwe', opts.subjectId);
        cfg.subjects.(subjectKey).mprageInitial = fullfile( ...
            cfg.subjects.(subjectKey).root, [opts.subjectId '_T1.nii']);
        cfg.subjects.(subjectKey).anatomyWork = fullfile( ...
            cfg.subjects.(subjectKey).root, 'anatomy');
        cfg.subjects.(subjectKey).segmentationWork = fullfile( ...
            cfg.subjects.(subjectKey).root, 'segmentation');
    end
end

function folderName = chooseFolder(currentValue, titleText, helpText)
    currentValue = normalizePath(currentValue);
    startFolder = currentValue;
    displayValue = currentValue;
    if isempty(currentValue)
        startFolder = pwd;
        displayValue = '<blank>';
    end
    answer = questdlg(sprintf('%s\n\nCurrent/default:\n%s', helpText, displayValue), ...
        titleText, 'Keep', 'Choose...', 'Blank', 'Keep');
    if isempty(answer) || strcmp(answer, 'Keep')
        folderName = currentValue;
    elseif strcmp(answer, 'Blank')
        folderName = '';
    else
        selected = uigetdir(startFolder, titleText);
        if isequal(selected, 0)
            folderName = currentValue;
        else
            folderName = char(selected);
        end
    end
end

function fileName = chooseFile(currentValue, titleText, helpText)
    currentValue = normalizePath(currentValue);
    startFolder = pwd;
    displayValue = currentValue;
    if ~isempty(currentValue)
        if exist(currentValue, 'dir') == 7
            startFolder = currentValue;
        elseif exist(fileparts(currentValue), 'dir') == 7
            startFolder = fileparts(currentValue);
        end
    else
        displayValue = '<blank>';
    end
    answer = questdlg(sprintf('%s\n\nCurrent/default:\n%s', helpText, displayValue), ...
        titleText, 'Keep', 'Choose...', 'Blank', 'Keep');
    if isempty(answer) || strcmp(answer, 'Keep')
        fileName = currentValue;
    elseif strcmp(answer, 'Blank')
        fileName = '';
    else
        [f, p] = uigetfile({'*.m', 'MATLAB files (*.m)'; '*.*', 'All files'}, ...
            titleText, startFolder);
        if isequal(f, 0)
            fileName = currentValue;
        else
            fileName = fullfile(p, f);
        end
    end
end

function fileName = chooseExecutable(currentValue, titleText, helpText)
    currentValue = normalizePath(currentValue);
    startFolder = pwd;
    displayValue = currentValue;
    if ~isempty(currentValue)
        if exist(currentValue, 'dir') == 7
            startFolder = currentValue;
        elseif exist(fileparts(currentValue), 'dir') == 7
            startFolder = fileparts(currentValue);
        end
    else
        displayValue = '<blank>';
    end
    answer = questdlg(sprintf('%s\n\nCurrent/default:\n%s', helpText, displayValue), ...
        titleText, 'Keep', 'Choose...', 'Blank', 'Keep');
    if isempty(answer) || strcmp(answer, 'Keep')
        fileName = currentValue;
    elseif strcmp(answer, 'Blank')
        fileName = '';
    else
        if ispc
            filterSpec = {'*.exe', 'Executables (*.exe)'; '*.*', 'All files'};
        else
            filterSpec = {'*', 'All files'};
        end
        [f, p] = uigetfile(filterSpec, titleText, startFolder);
        if isequal(f, 0)
            fileName = currentValue;
        else
            fileName = fullfile(p, f);
        end
    end
    fileName = normalizeExecutablePath(fileName);
end

function cfg = normalizeExecutableFields(cfg)
    if isfield(cfg, 'getdpExecutable')
        cfg.getdpExecutable = normalizeExecutablePath(cfg.getdpExecutable);
    end
    if isfield(cfg, 'gmshExecutable')
        cfg.gmshExecutable = normalizeExecutablePath(cfg.gmshExecutable);
    end
end

function fileName = normalizeExecutablePath(fileName)
    fileName = normalizePath(fileName);
    if isempty(fileName)
        return;
    end
    if ismac && endsWith(fileName, '.app') && exist(fileName, 'dir') == 7
        candidates = { ...
            fullfile(fileName, 'Contents', 'MacOS', 'gmsh'), ...
            fullfile(fileName, 'Contents', 'MacOS', 'Gmsh')};
        for i = 1:numel(candidates)
            if isExistingFile(candidates{i})
                fileName = candidates{i};
                return;
            end
        end
    end
end

function existing = loadExistingConfig(configFile)
    existing = struct();
    if exist(configFile, 'file') ~= 2
        return;
    end
    try
        existing = jsondecode(fileread(configFile));
    catch ME
        warning('nhpulseConfigureLocalPaths:ConfigReadFailed', ...
            'Could not read existing config "%s": %s', configFile, ME.message);
        existing = struct();
    end
end

function out = mergeMissingOrEmpty(existing, defaults)
    out = existing;
    names = fieldnames(defaults);
    for i = 1:numel(names)
        name = names{i};
        if ~isfield(out, name) || isempty(out.(name))
            out.(name) = defaults.(name);
        elseif isstruct(out.(name)) && isstruct(defaults.(name))
            out.(name) = mergeMissingOrEmpty(out.(name), defaults.(name));
        end
    end
end

function writeJson(fileName, S)
    try
        txt = jsonencode(S, 'PrettyPrint', true);
    catch
        txt = jsonencode(S);
    end
    fid = fopen(fileName, 'w');
    if fid < 0
        error('nhpulseConfigureLocalPaths:WriteFailed', ...
            'Could not open "%s" for writing.', fileName);
    end
    cleaner = onCleanup(@() fclose(fid));
    fprintf(fid, '%s\n', txt);
    clear cleaner
end

function printSummary(configFile, cfg, wroteFile)
    fprintf('\nNHPulse local path configuration\n');
    if wroteFile
        fprintf('  config: %s\n', configFile);
    else
        fprintf('  config: not written; returning defaults for this session\n');
    end
    fprintf('  outputRoot      generated files and QC products: %s\n', cfg.outputRoot);
    fprintf('  dataRoot        optional private/source data:    %s\n', cfg.dataRoot);
    fprintf('  roastWorkRoot   ROAST scratch/work products:     %s\n', cfg.roastWorkRoot);
    fprintf('  inpolyhedron    bundled voxelization helper:     %s\n', cfg.inpolyhedronPath);
    fprintf('  spmPath         SPM MATLAB folder, if external:  %s\n', cfg.spmPath);
    fprintf('  iso2meshPath    iso2mesh folder, if external:    %s\n', cfg.iso2meshPath);
    fprintf('  cvxPath         CVX folder, for sparse solves:   %s\n', cfg.cvxPath);
    fprintf('  niftiPath       optional NIfTI helper folder:     %s\n', cfg.niftiPath);
    fprintf('  getdpExecutable full ROAST solve executable:      %s\n', cfg.getdpExecutable);
    fprintf('  gmshExecutable  ROAST/Gmsh executable:            %s\n\n', cfg.gmshExecutable);
end

function folderName = functionFolder(functionName)
    fileName = which(functionName);
    if isempty(fileName)
        folderName = '';
    else
        folderName = fileparts(fileName);
    end
end

function folderName = cvxRootFromKeyword(folderName)
    if isempty(folderName)
        return;
    end
    [parentFolder, leaf] = fileparts(folderName);
    if strcmpi(leaf, 'keywords')
        folderName = parentFolder;
    end
end

function fileName = whichOnPath(programName)
    fileName = '';
    if ispc
        [status, txt] = system(sprintf('where "%s"', programName));
    else
        [status, txt] = system(sprintf('command -v "%s"', programName));
    end
    if status == 0
        lines = regexp(strtrim(txt), '\r\n|\r|\n', 'split');
        if ~isempty(lines)
            fileName = strtrim(lines{1});
        end
    end
end

function name = executableName(baseName)
    if ispc
        name = [baseName '.exe'];
    else
        name = baseName;
    end
end

function pathOut = firstExistingFolder(candidates)
    pathOut = '';
    for i = 1:numel(candidates)
        candidate = normalizePath(candidates{i});
        if ~isempty(candidate) && exist(candidate, 'dir') == 7
            pathOut = candidate;
            return;
        end
    end
end

function pathOut = firstExistingFile(candidates)
    pathOut = '';
    for i = 1:numel(candidates)
        candidate = normalizePath(candidates{i});
        if ~isempty(candidate) && exist(candidate, 'file') == 2
            pathOut = candidate;
            return;
        end
    end
end

function tf = isExistingFile(fileName)
    tf = ~isempty(fileName) && exist(fileName, 'dir') ~= 7 && ...
        exist(fileName, 'file') ~= 0;
end

function ensureDir(pathIn)
    if ~isempty(pathIn) && exist(pathIn, 'dir') ~= 7
        mkdir(pathIn);
    end
end

function pathOut = normalizePath(pathOut)
    if isempty(pathOut)
        pathOut = '';
        return;
    end
    pathOut = char(pathOut);
    if startsWith(pathOut, '~')
        homeDir = getenv('HOME');
        if isempty(homeDir)
            homeDir = getenv('USERPROFILE');
        end
        if numel(pathOut) == 1
            pathOut = homeDir;
        elseif pathOut(2) == '/' || pathOut(2) == '\' || pathOut(2) == filesep
            pathOut = fullfile(homeDir, pathOut(3:end));
        end
    end
end
