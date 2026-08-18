function P = acsPaths(varargin)
% ACSPATHS Resolve local data/output roots for this project.
%
% P = acsPaths() returns a struct with project, data/output roots, and
% optional external dependency paths.
%
% Resolution order:
%   1. Name-value overrides passed to this function
%   2. Environment variables such as ACS_BOX_ROOT and ACS_OUTPUT_ROOT
%   3. local.paths.json in the repo root or acsUtilities folder
%   4. Common Box locations for the current operating system
%
% local.paths.json is intentionally ignored by git. See
% acsUtilities/local.paths.example.json for a template.

    opts = parseInputs(varargin{:});

    repoRoot = fileparts(fileparts(mfilename('fullpath')));
    utilRoot = fileparts(mfilename('fullpath'));

    cfg = struct();
    cfgPath = opts.configFile;
    if isempty(cfgPath)
        envCfg = getenv('ACS_PATHS_CONFIG');
        if ~isempty(envCfg)
            cfgPath = envCfg;
        else
            candidates = { ...
                fullfile(repoRoot, 'local.paths.json'), ...
                fullfile(utilRoot, 'local.paths.json')};
            cfgPath = firstExistingFile(candidates);
        end
    end

    if ~isempty(cfgPath) && exist(cfgPath, 'file')
        cfg = jsondecode(fileread(cfgPath));
    end

    P = struct();
    P.repoRoot = repoRoot;
    P.acsUtilitiesRoot = utilRoot;
    P.configFile = cfgPath;

    P.boxRoot = firstNonempty( ...
        opts.boxRoot, ...
        getenv('ACS_BOX_ROOT'), ...
        getCfg(cfg, 'boxRoot', ''), ...
        firstExistingDir(defaultBoxCandidates()));

    P.dataRoot = firstNonempty( ...
        opts.dataRoot, ...
        getenv('ACS_DATA_ROOT'), ...
        getCfg(cfg, 'dataRoot', ''), ...
        defaultDataRoot(P.boxRoot));

    P.outputRoot = firstNonempty( ...
        opts.outputRoot, ...
        getenv('ACS_OUTPUT_ROOT'), ...
        getCfg(cfg, 'outputRoot', ''), ...
        fullfile(repoRoot, 'outputs'));

    P.roastWorkRoot = firstNonempty( ...
        opts.roastWorkRoot, ...
        getenv('ACS_ROAST_WORK_ROOT'), ...
        getCfg(cfg, 'roastWorkRoot', ''), ...
        fullfile(P.outputRoot, 'roast_work'));

    P.inpolyhedronPath = firstNonempty( ...
        opts.inpolyhedronPath, ...
        getenv('ACS_INPOLYHEDRON_PATH'), ...
        getCfg(cfg, 'inpolyhedronPath', ''), ...
        fullfile(utilRoot, 'inpolyhedron.m'));

    P.spmPath = firstNonempty( ...
        opts.spmPath, ...
        getenv('ACS_SPM_PATH'), ...
        getCfg(cfg, 'spmPath', ''));

    P.iso2meshPath = firstNonempty( ...
        opts.iso2meshPath, ...
        getenv('ACS_ISO2MESH_PATH'), ...
        getCfg(cfg, 'iso2meshPath', ''));

    P.cvxPath = firstNonempty( ...
        opts.cvxPath, ...
        getenv('ACS_CVX_PATH'), ...
        getCfg(cfg, 'cvxPath', ''));

    P.niftiPath = firstNonempty( ...
        opts.niftiPath, ...
        getenv('ACS_NIFTI_PATH'), ...
        getCfg(cfg, 'niftiPath', ''));

    P.getdpExecutable = firstNonempty( ...
        opts.getdpExecutable, ...
        getenv('ACS_GETDP_EXECUTABLE'), ...
        getCfg(cfg, 'getdpExecutable', ''));

    P.gmshExecutable = firstNonempty( ...
        opts.gmshExecutable, ...
        getenv('ACS_GMSH_EXECUTABLE'), ...
        getCfg(cfg, 'gmshExecutable', ''));

    P.extraMatlabPaths = firstNonemptyCell( ...
        opts.extraMatlabPaths, ...
        getCfgCell(cfg, 'extraMatlabPaths', {}));

    P.subjectOutputRoot = fullfile(P.outputRoot, 'subjects');
    P.templateOutputRoot = fullfile(P.outputRoot, 'templates');

    if isfield(cfg, 'subjects')
        P.subjects = cfg.subjects;
    else
        P.subjects = struct();
    end
end

function opts = parseInputs(varargin)
    opts = struct( ...
        'configFile', '', ...
        'boxRoot', '', ...
        'dataRoot', '', ...
        'outputRoot', '', ...
        'roastWorkRoot', '', ...
        'inpolyhedronPath', '', ...
        'spmPath', '', ...
        'iso2meshPath', '', ...
        'cvxPath', '', ...
        'niftiPath', '', ...
        'getdpExecutable', '', ...
        'gmshExecutable', '', ...
        'extraMatlabPaths', {{}});

    if mod(numel(varargin), 2) ~= 0
        error('acsPaths:BadInputs', 'Use name-value pairs.');
    end

    for i = 1:2:numel(varargin)
        key = char(varargin{i});
        rawVal = varargin{i + 1};
        switch lower(key)
            case 'configfile'
                opts.configFile = expandUserPath(rawVal);
            case 'boxroot'
                opts.boxRoot = expandUserPath(rawVal);
            case 'dataroot'
                opts.dataRoot = expandUserPath(rawVal);
            case 'outputroot'
                opts.outputRoot = expandUserPath(rawVal);
            case 'roastworkroot'
                opts.roastWorkRoot = expandUserPath(rawVal);
            case 'inpolyhedronpath'
                opts.inpolyhedronPath = expandUserPath(rawVal);
            case 'spmpath'
                opts.spmPath = expandUserPath(rawVal);
            case 'iso2meshpath'
                opts.iso2meshPath = expandUserPath(rawVal);
            case 'cvxpath'
                opts.cvxPath = expandUserPath(rawVal);
            case 'niftipath'
                opts.niftiPath = expandUserPath(rawVal);
            case 'getdpexecutable'
                opts.getdpExecutable = expandUserPath(rawVal);
            case 'gmshexecutable'
                opts.gmshExecutable = expandUserPath(rawVal);
            case 'extramatlabpaths'
                opts.extraMatlabPaths = normalizePathList(rawVal);
            otherwise
                error('acsPaths:UnknownOption', 'Unknown option: %s', key);
        end
    end
end

function val = getCfgCell(cfg, fieldName, defaultVal)
    if isstruct(cfg) && isfield(cfg, fieldName) && ~isempty(cfg.(fieldName))
        val = normalizePathList(cfg.(fieldName));
    else
        val = defaultVal;
    end
end

function val = getCfg(cfg, fieldName, defaultVal)
    if isstruct(cfg) && isfield(cfg, fieldName) && ~isempty(cfg.(fieldName))
        val = char(cfg.(fieldName));
        val = expandUserPath(val);
    else
        val = defaultVal;
    end
end

function root = defaultDataRoot(boxRoot)
    if isempty(boxRoot)
        root = '';
    else
        root = fullfile(boxRoot, 'SnyderLab', 'Data');
    end
end

function candidates = defaultBoxCandidates()
    homeDir = localHomeDir();
    userProfile = getenv('USERPROFILE');
    candidates = {};

    if ~isempty(userProfile)
        candidates{end + 1} = fullfile(userProfile, 'Box'); %#ok<AGROW>
        candidates{end + 1} = fullfile(userProfile, 'Library', 'CloudStorage', 'Box-Box'); %#ok<AGROW>
    end

    if ~isempty(homeDir)
        candidates{end + 1} = fullfile(homeDir, 'Box'); %#ok<AGROW>
        candidates{end + 1} = fullfile(homeDir, 'Library', 'CloudStorage', 'Box-Box'); %#ok<AGROW>
    end

    candidates{end + 1} = fullfile(filesep, 'data', 'box'); %#ok<AGROW>
end

function pathOut = firstExistingDir(candidates)
    pathOut = '';
    for i = 1:numel(candidates)
        candidate = expandUserPath(candidates{i});
        if ~isempty(candidate) && exist(candidate, 'dir')
            pathOut = candidate;
            return;
        end
    end
end

function pathOut = firstExistingFile(candidates)
    pathOut = '';
    for i = 1:numel(candidates)
        candidate = expandUserPath(candidates{i});
        if ~isempty(candidate) && exist(candidate, 'file')
            pathOut = candidate;
            return;
        end
    end
end

function val = firstNonempty(varargin)
    val = '';
    for i = 1:nargin
        item = varargin{i};
        if ~isempty(item)
            val = char(item);
            val = expandUserPath(val);
            return;
        end
    end
end

function val = firstNonemptyCell(varargin)
    val = {};
    for i = 1:nargin
        item = varargin{i};
        if ~isempty(item)
            val = normalizePathList(item);
            return;
        end
    end
end

function paths = normalizePathList(paths)
    if isempty(paths)
        paths = {};
        return;
    end
    if ischar(paths) || isstring(paths)
        paths = cellstr(paths);
    end
    if ~iscell(paths)
        error('acsPaths:BadPathList', ...
            'extraMatlabPaths must be a character vector, string array, or cell array.');
    end
    for i = 1:numel(paths)
        paths{i} = expandUserPath(paths{i});
    end
end

function p = expandUserPath(p)
    if isempty(p)
        return;
    end
    p = char(p);
    if startsWith(p, '~')
        homeDir = localHomeDir();
        if numel(p) == 1
            p = homeDir;
        elseif p(2) == filesep || p(2) == '/' || p(2) == '\'
            p = fullfile(homeDir, p(3:end));
        end
    end
end

function homeDir = localHomeDir()
    homeDir = getenv('HOME');
    if isempty(homeDir)
        homeDir = getenv('USERPROFILE');
    end
end
