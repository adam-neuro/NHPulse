function report = nhpulseCheckDependencies(varargin)
% NHPULSECHECKDEPENDENCIES Report likely NHPulse MATLAB dependencies.
%
% report = nhpulseCheckDependencies() prints a lightweight dependency report
% for the current MATLAB session. This is a convenience check for reviewers
% and users; it does not replace exercising the synthetic walkthrough.
%
% Name-value options:
%   verbose : print the report [true]

    p = inputParser;
    p.FunctionName = 'nhpulseCheckDependencies';
    addParameter(p, 'verbose', true, @(x) (islogical(x) || isnumeric(x)) && isscalar(x));
    parse(p, varargin{:});
    verbose = logical(p.Results.verbose);

    repoRoot = fileparts(mfilename('fullpath'));
    if isempty(repoRoot)
        repoRoot = pwd;
    end
    P = struct();
    if exist('acsPaths', 'file') == 2
        try
            P = acsPaths();
        catch
            P = struct();
        end
    end

    products = ver;
    report = struct();
    report.createdOn = char(datetime('now'));
    report.matlabVersion = version;
    report.repoRoot = repoRoot;
    report.products = {products.Name}';
    report.platform = struct('arch', computer('arch'), 'mexext', mexext);

    iso2mesh = iso2meshStatus(repoRoot, P);

    report.core = [
        dependencyItem('MATLAB', true, hasProduct(products, 'MATLAB'), 'MATLAB', ...
            'Required runtime/development environment.');
        dependencyItem('SPM', true, hasFunction('spm_vol') && hasFunction('spm_write_vol'), 'SPM', ...
            'Required for NIfTI read/write and ROAST/SPM segmentation paths.');
        dependencyItem('Image Processing Toolbox', true, ...
            hasProduct(products, 'Image Processing Toolbox') && hasFunction('bwconncomp'), ...
            'Image Processing Toolbox', ...
            'Required for morphology, connected components, hole filling, and image smoothing.');
        dependencyItem('Statistics and Machine Learning Toolbox', true, ...
            hasProduct(products, 'Statistics and Machine Learning Toolbox') && hasFunction('pdist2'), ...
            'Statistics and Machine Learning Toolbox', ...
            'Required by current electrode layout and nearest-neighbor utilities.');
        dependencyItem('CVX', false, hasFunction('cvx_begin'), 'CVX', ...
            'Required for sparse tES optimization routines.');
        dependencyItem('iso2mesh/TetGen', false, iso2mesh.available, ...
            'iso2mesh/TetGen', ...
            iso2mesh.notes);
        dependencyItem('GetDP', false, hasGetDpExecutable(repoRoot, P), 'GetDP', ...
            'Required for full finite-element solves and lead-field generation.');
        dependencyItem('Gmsh', false, hasGmshExecutable(repoRoot, P), 'Gmsh', ...
            'Used by ROAST/GetDP visualization and mesh workflows.');
        dependencyItem('ROAST NIfTI compatibility', false, ...
            hasFunction('load_untouch_nii') && hasFunction('save_untouch_nii') && ...
            hasFunction('spm_vol') && hasFunction('spm_write_vol'), ...
            'ROAST NIfTI compatibility', ...
            ['Required when running ROAST paths that expect load_untouch_nii/', ...
             'save_untouch_nii. NHPulse includes SPM-backed compatibility wrappers.'])
        ];
    report.iso2mesh = iso2mesh;

    report.keyFunctions = struct( ...
        'spm_vol', hasFunction('spm_vol'), ...
        'spm_write_vol', hasFunction('spm_write_vol'), ...
        'load_untouch_nii', hasFunction('load_untouch_nii'), ...
        'save_untouch_nii', hasFunction('save_untouch_nii'), ...
        'bwconncomp', hasFunction('bwconncomp'), ...
        'imgaussfilt3', hasFunction('imgaussfilt3'), ...
        'pdist2', hasFunction('pdist2'), ...
        'knnsearch', hasFunction('knnsearch'), ...
        'cvx_begin', hasFunction('cvx_begin'), ...
        'inpolyhedron', hasFunction('inpolyhedron'), ...
        'polyshape', hasFunction('polyshape'), ...
        'triangulation', hasFunction('triangulation'));

    report.syntheticSmokeLikely = all([ ...
        report.core(strcmp({report.core.name}, 'SPM')).available, ...
        report.core(strcmp({report.core.name}, 'Image Processing Toolbox')).available, ...
        report.core(strcmp({report.core.name}, 'Statistics and Machine Learning Toolbox')).available]);

    report.fullWorkflowLikely = report.syntheticSmokeLikely && ...
        report.core(strcmp({report.core.name}, 'ROAST NIfTI compatibility')).available && ...
        report.core(strcmp({report.core.name}, 'CVX')).available && ...
        report.core(strcmp({report.core.name}, 'iso2mesh/TetGen')).available && ...
        report.core(strcmp({report.core.name}, 'GetDP')).available;

    if verbose
        printReport(report);
    end
end

function item = dependencyItem(name, requiredForCore, available, dependencyKey, notes)
    info = nhpulseDependencyInfo(dependencyKey);
    item = struct('name', name, ...
        'requiredForCore', logical(requiredForCore), ...
        'available', logical(available), ...
        'projectUrl', info.projectUrl, ...
        'installUrl', info.installUrl, ...
        'configField', info.configField, ...
        'setupHint', info.setupHint, ...
        'notes', notes);
end

function tf = hasProduct(products, productName)
    tf = any(strcmpi({products.Name}, productName));
end

function tf = hasFunction(functionName)
    tf = exist(functionName, 'file') == 2 || exist(functionName, 'builtin') == 5 || ...
        exist(functionName, 'class') == 8;
end

function tf = hasGetDpExecutable(repoRoot, P)
    names = {'getdp', 'getdp.exe', 'getdpMac'};
    tf = hasConfiguredExecutable(P, 'getdpExecutable') || ...
        anyExecutableOnPath(names) || ...
        any(cellfun(@(name) exist(fullfile(repoRoot, 'lib', 'getdp-3.2.0', 'bin', name), 'file') == 2, names));
end

function tf = hasGmshExecutable(repoRoot, P)
    names = {'gmsh', 'gmsh.exe'};
    tf = hasConfiguredExecutable(P, 'gmshExecutable') || ...
        anyExecutableOnPath(names) || ...
        any(cellfun(@(name) exist(fullfile(repoRoot, 'lib', 'gmsh', name), 'file') == 2, names));
end

function tf = hasConfiguredExecutable(P, fieldName)
    tf = isstruct(P) && isfield(P, fieldName) && ...
        ~isempty(P.(fieldName)) && exist(P.(fieldName), 'file') == 2;
end

function tf = anyExecutableOnPath(names)
    tf = false;
    for i = 1:numel(names)
        [status, ~] = system(sprintf('"%s" --version', names{i}));
        if status == 0
            tf = true;
            return;
        end
    end
end

function printReport(report)
    fprintf('\nNHPulse dependency check\n');
    fprintf('  MATLAB: %s\n', report.matlabVersion);
    fprintf('  repo: %s\n\n', report.repoRoot);
    for i = 1:numel(report.core)
        item = report.core(i);
        status = 'missing';
        if item.available
            status = 'available';
        end
        requiredText = 'optional';
        if item.requiredForCore
            requiredText = 'core';
        end
        fprintf('  %-40s %-9s %s\n', item.name, status, requiredText);
    end
    fprintf('\n  synthetic smoke test likely runnable: %s\n', yesNo(report.syntheticSmokeLikely));
    fprintf('  full lead-field workflow likely runnable: %s\n\n', yesNo(report.fullWorkflowLikely));
    missing = report.core(~[report.core.available]);
    if ~isempty(missing)
        fprintf('  Missing dependency help:\n');
        for i = 1:numel(missing)
            item = missing(i);
            fprintf('    %s: %s\n', item.name, ...
                nhpulseCommandWindowLink(item.installUrl, item.installUrl));
            if ~isempty(item.configField)
                fprintf('      local.paths.json field: %s\n', item.configField);
            end
            if ~isempty(item.notes)
                fprintf('      Status: %s\n', item.notes);
            end
            fprintf('      %s\n', item.setupHint);
        end
        fprintf('\n');
    end
end

function status = iso2meshStatus(repoRoot, P)
    folder = resolveIso2meshFolder(repoRoot, P);
    cgalv2mPath = which('cgalv2m');
    hasMatlabFunctions = hasFunction('cgalv2m') || ...
        hasFunction('surf2mesh') || hasFunction('vol2mesh');
    if isempty(folder) && ~isempty(cgalv2mPath)
        folder = inferIso2meshRoot(cgalv2mPath);
    end

    cgalName = ['cgalmesh.' mexext];
    cgalPath = '';
    if ~isempty(folder)
        cgalPath = fullfile(folder, 'bin', cgalName);
    end
    cgalExists = ~isempty(cgalPath) && exist(cgalPath, 'file') == 2;
    cgalExecutable = cgalExists && isExecutableFile(cgalPath);
    available = hasMatlabFunctions && cgalExists && cgalExecutable;

    if ~hasMatlabFunctions
        notes = 'iso2mesh MATLAB functions are not on the MATLAB path.';
    elseif isempty(folder)
        notes = 'iso2mesh functions are on the path, but the iso2mesh root folder could not be resolved.';
    elseif ~cgalExists
        notes = sprintf(['iso2mesh is on the path, but the platform CGAL ', ...
            'mesher is missing: %s. Download the %s binary or a full iso2mesh ', ...
            'release for this MATLAB platform.'], cgalPath, cgalName);
    elseif ~cgalExecutable
        notes = sprintf(['The iso2mesh CGAL mesher exists but is not executable: ', ...
            '%s. On macOS run nhpulseClearMacQuarantine(''iso2mesh'') ', ...
            'or chmod u+x the file.'], cgalPath);
    else
        notes = sprintf('iso2mesh functions and %s are available.', cgalName);
    end

    status = struct();
    status.available = available;
    status.folder = folder;
    status.cgalMeshBinary = cgalPath;
    status.hasMatlabFunctions = hasMatlabFunctions;
    status.cgalMeshExists = cgalExists;
    status.cgalMeshExecutable = cgalExecutable;
    status.notes = notes;
end

function folder = resolveIso2meshFolder(repoRoot, P)
    candidates = {};
    if isstruct(P) && isfield(P, 'iso2meshPath') && ~isempty(P.iso2meshPath)
        candidates{end + 1} = P.iso2meshPath; %#ok<AGROW>
    end
    candidates{end + 1} = fullfile(repoRoot, 'lib', 'iso2mesh'); %#ok<AGROW>
    cgalv2mPath = which('cgalv2m');
    if ~isempty(cgalv2mPath)
        candidates{end + 1} = inferIso2meshRoot(cgalv2mPath); %#ok<AGROW>
    end
    folder = '';
    for i = 1:numel(candidates)
        candidate = char(candidates{i});
        if ~isempty(candidate) && exist(candidate, 'dir') == 7
            folder = candidate;
            return;
        end
    end
end

function folder = inferIso2meshRoot(fileName)
    folder = fileparts(fileName);
end

function tf = isExecutableFile(fileName)
    tf = exist(fileName, 'file') == 2;
    if tf && isunix
        [ok, attrs] = fileattrib(fileName);
        if ok && isstruct(attrs)
            tf = logical(attrs.UserExecute || attrs.GroupExecute || ...
                attrs.OtherExecute);
        else
            tf = false;
        end
    end
end

function value = yesNo(tf)
    if tf
        value = 'yes';
    else
        value = 'no';
    end
end
