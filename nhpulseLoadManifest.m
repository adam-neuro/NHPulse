function manifest = nhpulseLoadManifest(fileName)
% NHPULSELOADMANIFEST Load an NHPulse run manifest from MAT or JSON.

    fileName = char(fileName);
    if exist(fileName, 'file') ~= 2
        error('nhpulseLoadManifest:FileNotFound', ...
            'Manifest file not found: %s', fileName);
    end
    [~, ~, ext] = fileparts(fileName);
    switch lower(ext)
        case '.mat'
            S = load(fileName, 'manifest');
            if ~isfield(S, 'manifest')
                error('nhpulseLoadManifest:MissingVariable', ...
                    'MAT file does not contain variable manifest: %s', fileName);
            end
            manifest = S.manifest;
        case '.json'
            manifest = jsondecode(fileread(fileName));
        otherwise
            error('nhpulseLoadManifest:UnsupportedFile', ...
                'Manifest must be a .mat or .json file.');
    end
    manifest = relocateProjectRootIfNeeded(manifest, fileName);
end

function manifest = relocateProjectRootIfNeeded(manifest, manifestFile)
    if ~isstruct(manifest) || ~isfield(manifest, 'projectRoot') || ...
            ~isfield(manifest, 'artifacts') || isempty(manifest.artifacts)
        return;
    end
    if projectRootResolvesArtifacts(manifest, manifest.projectRoot)
        return;
    end

    folder = fileparts(nhpulseManifestInternal('canonicalPath', manifestFile));
    bestRoot = '';
    bestCount = 0;
    while ~isempty(folder)
        count = countResolvedRelativeArtifacts(manifest.artifacts, folder);
        if count > bestCount
            bestCount = count;
            bestRoot = folder;
        end
        parent = fileparts(folder);
        if isempty(parent) || strcmp(parent, folder)
            break;
        end
        folder = parent;
    end
    if bestCount > 0
        manifest.projectRoot = bestRoot;
    end
end

function tf = projectRootResolvesArtifacts(manifest, root)
    tf = exist(char(root), 'dir') == 7 && ...
        countResolvedRelativeArtifacts(manifest.artifacts, root) > 0;
end

function count = countResolvedRelativeArtifacts(artifacts, root)
    count = 0;
    for i = 1:numel(artifacts)
        if ~isfield(artifacts(i), 'pathIsRelative') || ...
                ~artifacts(i).pathIsRelative
            continue;
        end
        relativePath = strrep(char(artifacts(i).path), '/', filesep);
        if exist(fullfile(root, relativePath), 'file') == 2
            count = count + 1;
        end
    end
end
