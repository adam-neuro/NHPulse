function ref = nhpulseArtifactRef(artifactOrId, role, varargin)
% NHPULSEARTIFACTREF Create a parent reference for manifest registration.
%
% ref = nhpulseArtifactRef(artifact, role) captures both the artifact ID and
% its current recorded fingerprint. Passing an ID alone is also supported;
% nhpulseRegisterArtifact will resolve its fingerprint from the manifest.

    if nargin < 2 || isempty(role)
        role = 'input';
    end
    p = inputParser;
    addParameter(p, 'recordedFingerprint', struct(), @isstruct);
    parse(p, varargin{:});

    ref = nhpulseManifestInternal('emptyParent');
    ref.role = char(role);
    if isstruct(artifactOrId)
        if ~isfield(artifactOrId, 'artifactId')
            error('nhpulseArtifactRef:MissingArtifactId', ...
                'Artifact struct does not contain artifactId.');
        end
        ref.artifactId = char(artifactOrId.artifactId);
        if isfield(artifactOrId, 'contentFingerprint')
            ref.recordedFingerprint = artifactOrId.contentFingerprint;
        end
    else
        ref.artifactId = char(artifactOrId);
        ref.recordedFingerprint = p.Results.recordedFingerprint;
    end
end
