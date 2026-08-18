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

    report.core = [
        dependencyItem('MATLAB', true, hasProduct(products, 'MATLAB'), ...
            'Required runtime/development environment.');
        dependencyItem('SPM', true, hasFunction('spm_vol') && hasFunction('spm_write_vol'), ...
            'Required for NIfTI read/write and ROAST/SPM segmentation paths.');
        dependencyItem('Image Processing Toolbox', true, ...
            hasProduct(products, 'Image Processing Toolbox') && hasFunction('bwconncomp'), ...
            'Required for morphology, connected components, hole filling, and image smoothing.');
        dependencyItem('Statistics and Machine Learning Toolbox', true, ...
            hasProduct(products, 'Statistics and Machine Learning Toolbox') && hasFunction('pdist2'), ...
            'Required by current electrode layout and nearest-neighbor utilities.');
        dependencyItem('CVX', true, hasFunction('cvx_begin'), ...
            'Required for sparse tES optimization routines.');
        dependencyItem('iso2mesh/TetGen', false, hasFunction('surf2mesh') || hasFunction('vol2mesh'), ...
            'Required for full ROAST mesh generation; often bundled/managed through ROAST.');
        dependencyItem('GetDP', false, hasGetDpExecutable(repoRoot, P), ...
            'Required for full finite-element solves and lead-field generation.');
        dependencyItem('Gmsh', false, hasGmshExecutable(repoRoot, P), ...
            'Used by ROAST/GetDP visualization and mesh workflows.');
        dependencyItem('NIfTI utilities', false, hasFunction('niftiread') || hasFunction('load_nii'), ...
            'Helpful fallback utilities; most active paths use SPM for NIfTI I/O.')
        ];

    report.keyFunctions = struct( ...
        'spm_vol', hasFunction('spm_vol'), ...
        'spm_write_vol', hasFunction('spm_write_vol'), ...
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
        report.core(strcmp({report.core.name}, 'CVX')).available && ...
        report.core(strcmp({report.core.name}, 'iso2mesh/TetGen')).available && ...
        report.core(strcmp({report.core.name}, 'GetDP')).available;

    if verbose
        printReport(report);
    end
end

function item = dependencyItem(name, requiredForCore, available, notes)
    item = struct('name', name, ...
        'requiredForCore', logical(requiredForCore), ...
        'available', logical(available), ...
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
    names = {'getdp', 'getdp.exe'};
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
end

function value = yesNo(tf)
    if tf
        value = 'yes';
    else
        value = 'no';
    end
end
