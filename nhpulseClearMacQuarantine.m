function out = nhpulseClearMacQuarantine(targets, varargin)
% NHPULSECLEARMACQUARANTINE Clear macOS quarantine and executable-bit issues.
%
% out = nhpulseClearMacQuarantine('cvx') clears extended attributes under
% acsPaths().cvxPath. Common target names are 'spm', 'cvx', 'iso2mesh',
% 'getdp', and 'gmsh'. A direct folder/file path is also accepted.
%
% This is a convenience wrapper around macOS xattr/chmod for cases where
% MATLAB reports "Invalid MEX-file", "library load disallowed by system
% policy", or "Permission denied" after a dependency was downloaded from the
% web.
%
% Name-value options:
%   configFile : optional local.paths.json override ['']
%   mode       : 'all' or 'quarantineOnly' ['all']
%   chmod      : mark MEX/solver helper files executable [true]
%   dryRun     : print commands without running them [false]
%   verbose    : print progress [true]

    opts = parseInputs(varargin{:});
    if nargin < 1 || isempty(targets)
        targets = {'spm', 'cvx'};
    end
    targets = normalizeTargets(targets);

    if ~ismac
        warning('nhpulseClearMacQuarantine:NotMac', ...
            'This helper only applies on macOS. No xattr command was run.');
        out = struct('isMac', false, 'targets', {targets}, ...
            'items', struct([]), 'allSucceeded', false);
        return;
    end

    if isempty(opts.configFile)
        P = acsPaths();
    else
        P = acsPaths('configFile', opts.configFile);
    end

    items = repmat(struct('target', '', 'path', '', 'command', '', ...
        'chmodCommand', '', 'status', NaN, 'chmodStatus', NaN, ...
        'output', '', 'chmodOutput', '', 'skipped', false), numel(targets), 1);
    for i = 1:numel(targets)
        target = targets{i};
        pathToClear = resolveTargetPath(target, P);
        items(i).target = target;
        items(i).path = pathToClear;
        if isempty(pathToClear) || ~(exist(pathToClear, 'dir') == 7 || ...
                isExistingFile(pathToClear))
            items(i).skipped = true;
            items(i).output = ['Path not found or not configured: ' target];
            if opts.verbose
                fprintf('Skipping %s: %s\n', target, items(i).output);
            end
            continue;
        end

        items(i).command = xattrCommand(pathToClear, opts.mode);
        if opts.chmod
            items(i).chmodCommand = chmodCommand(pathToClear);
        end
        if opts.verbose
            fprintf('Clearing macOS attributes for %s:\n  %s\n', ...
                target, pathToClear);
            fprintf('  %s\n', items(i).command);
            if ~isempty(items(i).chmodCommand)
                fprintf('  %s\n', items(i).chmodCommand);
            end
        end
        if opts.dryRun
            items(i).status = 0;
            items(i).output = 'dry run';
            items(i).chmodStatus = 0;
            items(i).chmodOutput = 'dry run';
        else
            [items(i).status, items(i).output] = system(items(i).command);
            if ~isempty(items(i).chmodCommand)
                [items(i).chmodStatus, items(i).chmodOutput] = ...
                    system(items(i).chmodCommand);
            end
        end
        if opts.verbose && items(i).status ~= 0
            fprintf('  xattr returned status %d:\n%s\n', ...
                items(i).status, items(i).output);
        end
        if opts.verbose && ~isnan(items(i).chmodStatus) && ...
                items(i).chmodStatus ~= 0
            fprintf('  chmod returned status %d:\n%s\n', ...
                items(i).chmodStatus, items(i).chmodOutput);
        end
    end

    out = struct();
    out.createdOn = char(datetime('now'));
    out.isMac = true;
    out.mode = opts.mode;
    out.chmod = opts.chmod;
    out.targets = targets;
    out.items = items;
    xattrOk = [items.skipped] | [items.status] == 0;
    chmodStatus = [items.chmodStatus];
    chmodOk = [items.skipped] | isnan(chmodStatus) | chmodStatus == 0;
    out.allSucceeded = all(xattrOk & chmodOk);
end

function opts = parseInputs(varargin)
    p = inputParser;
    p.FunctionName = 'nhpulseClearMacQuarantine';
    addParameter(p, 'configFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'mode', 'all', @(x) ischar(x) || isstring(x));
    addParameter(p, 'chmod', true, @isBoolLike);
    addParameter(p, 'dryRun', false, @isBoolLike);
    addParameter(p, 'verbose', true, @isBoolLike);
    parse(p, varargin{:});

    opts = p.Results;
    opts.configFile = char(opts.configFile);
    opts.mode = normalizeMode(opts.mode);
    opts.chmod = logical(opts.chmod);
    opts.dryRun = logical(opts.dryRun);
    opts.verbose = logical(opts.verbose);
end

function tf = isBoolLike(x)
    tf = (islogical(x) || isnumeric(x)) && isscalar(x);
end

function mode = normalizeMode(mode)
    key = lower(regexprep(strtrim(char(mode)), '[\s_\-]+', ''));
    switch key
        case {'all', 'clearall', 'allattributes', 'xattrrc'}
            mode = 'all';
        case {'quarantine', 'quarantineonly', 'comapplequarantine'}
            mode = 'quarantineOnly';
        otherwise
            error('nhpulseClearMacQuarantine:BadMode', ...
                'mode must be ''all'' or ''quarantineOnly''.');
    end
end

function targets = normalizeTargets(targets)
    if ischar(targets) || isstring(targets)
        targets = cellstr(string(targets));
    elseif iscell(targets)
        targets = cellfun(@char, targets(:), 'UniformOutput', false);
    else
        error('nhpulseClearMacQuarantine:BadTargets', ...
            'targets must be a char, string, or cell array of chars/strings.');
    end
    targets = targets(:);
end

function pathToClear = resolveTargetPath(target, P)
    target = char(target);
    key = lower(regexprep(strtrim(target), '[\s_\-]+', ''));
    switch key
        case {'spm', 'spm12'}
            pathToClear = firstExisting({getField(P, 'spmPath'), ...
                fullfile(getField(P, 'repoRoot'), 'lib', 'spm'), ...
                fullfile(getField(P, 'repoRoot'), 'lib', 'spm12')});
        case {'cvx'}
            pathToClear = firstExisting({getField(P, 'cvxPath'), ...
                fullfile(getField(P, 'repoRoot'), 'lib', 'cvx')});
        case {'iso2mesh', 'tetgen', 'iso2meshtetgen'}
            pathToClear = firstExisting({getField(P, 'iso2meshPath'), ...
                fullfile(getField(P, 'repoRoot'), 'lib', 'iso2mesh')});
        case {'getdp'}
            pathToClear = firstExisting({ ...
                executableParent(getField(P, 'getdpExecutable')), ...
                fullfile(getField(P, 'repoRoot'), 'lib', 'getdp-3.2.0', 'bin'), ...
                fullfile(getField(P, 'repoRoot'), 'lib', 'getdp')});
        case {'gmsh'}
            pathToClear = firstExisting({ ...
                executableParent(getField(P, 'gmshExecutable')), ...
                fullfile(getField(P, 'repoRoot'), 'lib', 'gmsh')});
        otherwise
            pathToClear = expandUserPath(target);
    end
end

function value = firstExisting(candidates)
    value = '';
    for i = 1:numel(candidates)
        candidate = expandUserPath(char(candidates{i}));
        if ~isempty(candidate) && (exist(candidate, 'dir') == 7 || ...
                exist(candidate, 'file') == 2)
            value = candidate;
            return;
        end
    end
end

function value = getField(S, fieldName)
    if isstruct(S) && isfield(S, fieldName)
        value = char(S.(fieldName));
    else
        value = '';
    end
end

function folder = executableParent(fileName)
    fileName = char(fileName);
    if isempty(fileName)
        folder = '';
    elseif exist(fileName, 'dir') == 7
        folder = fileName;
    else
        folder = fileparts(fileName);
    end
end

function cmd = xattrCommand(pathToClear, mode)
    q = shellQuote(pathToClear);
    switch mode
        case 'all'
            cmd = sprintf('xattr -rc %s', q);
        case 'quarantineOnly'
            cmd = sprintf('xattr -r -d com.apple.quarantine %s 2>/dev/null', q);
    end
end

function cmd = chmodCommand(pathToClear)
    q = shellQuote(pathToClear);
    if isExistingFile(pathToClear)
        cmd = sprintf('chmod u+x %s', q);
    else
        cmd = sprintf(['find %s -type f \\( -name ''*.mex*'' -o ', ...
            '-name ''cgalmesh*'' -o -name ''tetgen*'' -o ', ...
            '-name ''getdp*'' -o -name ''gmsh*'' -o -name ''*.sh'' ', ...
            '\\) -exec chmod u+x {} +'], q);
    end
end

function tf = isExistingFile(fileName)
    tf = ~isempty(fileName) && exist(fileName, 'dir') ~= 7 && ...
        exist(fileName, 'file') ~= 0;
end

function q = shellQuote(value)
    value = char(value);
    q = ['''' strrep(value, '''', '''"''"''') ''''];
end

function p = expandUserPath(p)
    p = char(p);
    if isempty(p)
        return;
    end
    if startsWith(p, '~')
        homeDir = getenv('HOME');
        if isempty(homeDir)
            homeDir = char(java.lang.System.getProperty('user.home'));
        end
        if numel(p) == 1
            p = homeDir;
        elseif p(2) == '/' || p(2) == '\'
            p = fullfile(homeDir, p(3:end));
        end
    end
end
