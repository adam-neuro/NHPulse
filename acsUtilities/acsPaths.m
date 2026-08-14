function P = acsPaths(varargin)
% ACSPATHS Resolve local data/output roots for this project.
%
% P = acsPaths() returns a struct with project, Box, data, and output roots.
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
        'roastWorkRoot', '');

    if mod(numel(varargin), 2) ~= 0
        error('acsPaths:BadInputs', 'Use name-value pairs.');
    end

    for i = 1:2:numel(varargin)
        key = char(varargin{i});
        val = char(varargin{i + 1});
        switch lower(key)
            case 'configfile'
                opts.configFile = expandUserPath(val);
            case 'boxroot'
                opts.boxRoot = expandUserPath(val);
            case 'dataroot'
                opts.dataRoot = expandUserPath(val);
            case 'outputroot'
                opts.outputRoot = expandUserPath(val);
            case 'roastworkroot'
                opts.roastWorkRoot = expandUserPath(val);
            otherwise
                error('acsPaths:UnknownOption', 'Unknown option: %s', key);
        end
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
