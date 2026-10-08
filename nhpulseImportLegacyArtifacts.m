function result = nhpulseImportLegacyArtifacts(projectIn, varargin)
% NHPULSEIMPORTLEGACYARTIFACTS Explicitly register discovered legacy files.
%
% result = nhpulseImportLegacyArtifacts(projectOrRoot) prepares a dry run for
% every recognized, unregistered legacy artifact. No files are moved, renamed,
% or modified. Set 'dryRun', false to write a new inventory manifest.
%
% Name-value options:
%   selection       : discovery IDs, types, or paths [{} = all]
%   dryRun          : preview without writing a manifest [true]
%   runLabel        : label for the new manifest ['Legacy output import']
%   runId           : explicit run identifier [[] = generated]
%   metadata        : additional run metadata [struct()]
%   fingerprintMode : register mode ['auto']
%   artifactTypes   : additional hierarchy definitions [struct([])]
%   verbose         : print planned/imported files [true]
%
% Parent links are intentionally not guessed. They can be added explicitly in
% a later run manifest once the provenance of a legacy product is known.

    p = inputParser;
    addParameter(p, 'selection', {}, @(x) ischar(x) || isstring(x) || iscell(x));
    addParameter(p, 'dryRun', true, @isBoolLike);
    addParameter(p, 'runLabel', 'Legacy output import', ...
        @(x) ischar(x) || isstring(x));
    addParameter(p, 'runId', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'metadata', struct(), @isstruct);
    addParameter(p, 'fingerprintMode', 'auto', ...
        @(x) ischar(x) || isstring(x));
    addParameter(p, 'artifactTypes', struct([]), @isstruct);
    addParameter(p, 'verbose', true, @isBoolLike);
    parse(p, varargin{:});
    opts = p.Results;

    if ischar(projectIn) || isstring(projectIn)
        project = nhpulseOpenProject(projectIn, ...
            'verifyContent', false, 'artifactTypes', opts.artifactTypes, ...
            'verbose', false);
    else
        project = projectIn;
    end
    validateProject(project);
    selected = selectArtifacts(project.legacyArtifacts, opts.selection);

    result = struct();
    result.schema = 'nhpulse.legacyImport';
    result.schemaVersion = 1;
    result.projectRoot = project.projectRoot;
    result.dryRun = logical(opts.dryRun);
    result.selectedArtifacts = selected;
    result.manifest = struct();
    result.manifestFiles = struct('mat', '', 'json', '');

    if logical(opts.verbose)
        fprintf('\nNHPulse legacy artifact import%s\n', ...
            chooseText(opts.dryRun, ' (dry run)', ''));
        fprintf('  selected: %d\n', numel(selected));
        for i = 1:numel(selected)
            fprintf('  %-28s %s\n', selected(i).type, selected(i).relativePath);
        end
    end
    if logical(opts.dryRun) || isempty(selected)
        return;
    end

    metadata = opts.metadata;
    metadata.importedLegacyOutputs = true;
    metadata.parentInference = 'none';
    metadata.sourceProjectOpenedOn = project.openedOn;
    manifest = nhpulseCreateManifest(project.projectRoot, opts.runLabel, ...
        'runId', opts.runId, 'metadata', metadata);
    for i = 1:numel(selected)
        itemMetadata = struct('legacyDiscoveryId', selected(i).discoveryId, ...
            'classificationConfidence', selected(i).confidence, ...
            'classificationReason', selected(i).reason);
        [manifest, ~] = nhpulseRegisterArtifact(manifest, ...
            selected(i).type, selected(i).path, 'label', selected(i).label, ...
            'metadata', itemMetadata, ...
            'fingerprintMode', opts.fingerprintMode);
    end
    result.manifest = manifest;
    result.manifestFiles = nhpulseSaveManifest(manifest);
    if logical(opts.verbose)
        fprintf('  manifest: %s\n\n', result.manifestFiles.mat);
    end
end

function selected = selectArtifacts(artifacts, selection)
    if isempty(selection)
        selected = artifacts;
        return;
    end
    if ischar(selection) || isstring(selection)
        selection = cellstr(selection);
    end
    keep = false(numel(artifacts), 1);
    for i = 1:numel(artifacts)
        candidates = {artifacts(i).discoveryId, artifacts(i).type, ...
            artifacts(i).path, artifacts(i).relativePath};
        for j = 1:numel(selection)
            if any(strcmpi(char(selection{j}), candidates))
                keep(i) = true;
                break;
            end
        end
    end
    selected = artifacts(keep);
    if isempty(selected)
        error('nhpulseImportLegacyArtifacts:SelectionEmpty', ...
            'selection did not match any discovered legacy artifact.');
    end
end

function validateProject(project)
    if ~isstruct(project) || ~isfield(project, 'schema') || ...
            ~strcmp(project.schema, 'nhpulse.projectIndex') || ...
            ~isfield(project, 'legacyArtifacts')
        error('nhpulseImportLegacyArtifacts:BadProject', ...
            'Input is not an NHPulse project index.');
    end
end

function value = chooseText(condition, yesValue, noValue)
    if condition
        value = yesValue;
    else
        value = noValue;
    end
end

function tf = isBoolLike(x)
    tf = (islogical(x) || isnumeric(x)) && isscalar(x);
end
