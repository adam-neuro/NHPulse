function files = nhpulseSaveManifest(manifest, outputBase)
% NHPULSESAVEMANIFEST Save a run manifest as MAT and readable JSON files.
%
% files = nhpulseSaveManifest(manifest) writes beneath:
%   <projectRoot>/manifests/<runId>/nhpulse-manifest.{mat,json}
%
% outputBase may be a filename stem or a manifest output directory.

    if nargin < 2 || isempty(outputBase)
        outputBase = fullfile(manifest.projectRoot, 'manifests', ...
            manifest.runId, 'nhpulse-manifest');
    else
        outputBase = char(outputBase);
        if exist(outputBase, 'dir') == 7 || endsWith(outputBase, filesep)
            outputBase = fullfile(outputBase, 'nhpulse-manifest');
        else
            [folder, stem, ext] = fileparts(outputBase);
            if any(strcmpi(ext, {'.mat', '.json'}))
                outputBase = fullfile(folder, stem);
            end
        end
    end
    outputBase = nhpulseManifestInternal('canonicalPath', outputBase);
    folder = fileparts(outputBase);
    if exist(folder, 'dir') ~= 7
        mkdir(folder);
    end

    files = struct('mat', [outputBase '.mat'], 'json', [outputBase '.json']);
    save(files.mat, 'manifest', '-v7.3');
    nhpulseManifestInternal('writeJson', files.json, manifest);
end
