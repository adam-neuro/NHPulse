function varargout = nhpulseManifestInternal(action, varargin)
% NHPULSEMANIFESTINTERNAL Shared implementation for manifest public APIs.

    switch lower(char(action))
        case 'emptyartifact'
            varargout{1} = emptyArtifact();
        case 'emptyparent'
            varargout{1} = emptyParent();
        case 'fingerprint'
            varargout{1} = fileFingerprint(varargin{:});
        case 'resolvepath'
            varargout{1} = resolveArtifactPath(varargin{:});
        case 'storepath'
            [varargout{1:nargout}] = storeArtifactPath(varargin{:});
        case 'canonicalpath'
            varargout{1} = canonicalPath(varargin{:});
        case 'newid'
            varargout{1} = newId(varargin{:});
        case 'fingerprintsequal'
            varargout{1} = fingerprintsEqual(varargin{:});
        case 'writejson'
            writeJson(varargin{:});
        otherwise
            error('nhpulseManifestInternal:UnknownAction', ...
                'Unknown manifest helper action "%s".', char(action));
    end
end

function value = emptyArtifact()
    value = struct( ...
        'artifactId', '', ...
        'type', '', ...
        'label', '', ...
        'path', '', ...
        'pathIsRelative', false, ...
        'pathKind', 'file', ...
        'contentFingerprint', emptyFingerprint(), ...
        'parents', repmat(emptyParent(), 0, 1), ...
        'metadata', struct(), ...
        'createdOn', '');
end

function value = emptyParent()
    value = struct( ...
        'artifactId', '', ...
        'role', 'input', ...
        'recordedFingerprint', emptyFingerprint());
end

function value = emptyFingerprint()
    value = struct('algorithm', '', 'value', '', 'bytes', 0, ...
        'modifiedOn', '');
end

function fingerprint = fileFingerprint(fileName, mode)
    if nargin < 2 || isempty(mode)
        mode = 'sha256';
    end
    fileName = canonicalPath(fileName);
    if exist(fileName, 'file') ~= 2
        error('nhpulseManifest:FileNotFound', ...
            'Cannot fingerprint missing file: %s', fileName);
    end
    info = dir(fileName);
    fingerprint = emptyFingerprint();
    fingerprint.bytes = double(info.bytes);
    fingerprint.modifiedOn = char(datetime(info.datenum, ...
        'ConvertFrom', 'datenum', 'Format', 'yyyyMMdd''T''HHmmss'));

    mode = lower(strtrim(char(mode)));
    if strcmp(mode, 'auto')
        if info.bytes <= 256 * 1024 * 1024 && usejava('jvm')
            mode = 'sha256';
        else
            mode = 'metadata';
        end
    end
    if any(strcmp(mode, {'metadata', 'size-mtime'}))
        fingerprint.algorithm = 'size-mtime';
        fingerprint.value = sprintf('%d:%.15g', info.bytes, info.datenum);
        return;
    end
    if ~strcmp(mode, 'sha256')
        error('nhpulseManifest:BadFingerprintMode', ...
            ['fingerprintMode must be ''auto'', ''sha256'', or ', ...
             '''metadata''/''size-mtime''.']);
    end

    if usejava('jvm')
        fingerprint.algorithm = 'sha256';
        fingerprint.value = sha256File(fileName);
    else
        warning('nhpulseManifest:NoJvmForSha256', ...
            ['MATLAB has no JVM, so SHA-256 is unavailable. Falling back ', ...
             'to a size/modified-time fingerprint for %s.'], fileName);
        fingerprint.algorithm = 'size-mtime';
        fingerprint.value = sprintf('%d:%.15g', info.bytes, info.datenum);
    end
end

function value = sha256File(fileName)
    digest = java.security.MessageDigest.getInstance('SHA-256');
    fid = fopen(fileName, 'rb');
    if fid < 0
        error('nhpulseManifest:FileOpenFailed', ...
            'Could not open file for fingerprinting: %s', fileName);
    end
    cleaner = onCleanup(@() fclose(fid));
    while true
        chunk = fread(fid, 1024 * 1024, '*uint8');
        if isempty(chunk)
            break;
        end
        digest.update(chunk);
    end
    bytes = typecast(digest.digest(), 'uint8');
    value = lower(reshape(dec2hex(bytes, 2).', 1, []));
end

function tf = fingerprintsEqual(a, b)
    tf = isstruct(a) && isstruct(b) && ...
        isfield(a, 'algorithm') && isfield(b, 'algorithm') && ...
        isfield(a, 'value') && isfield(b, 'value') && ...
        strcmpi(char(a.algorithm), char(b.algorithm)) && ...
        strcmpi(char(a.value), char(b.value));
end

function [storedPath, isRelative] = storeArtifactPath(fileName, projectRoot)
    fileName = canonicalPath(fileName);
    projectRoot = canonicalPath(projectRoot);
    storedPath = fileName;
    isRelative = false;

    rootPrefix = [projectRoot filesep];
    if ispc
        inside = startsWith(lower(fileName), lower(rootPrefix));
    else
        inside = startsWith(fileName, rootPrefix);
    end
    if inside
        storedPath = fileName((numel(rootPrefix) + 1):end);
        storedPath = strrep(storedPath, '\', '/');
        isRelative = true;
    elseif strcmpi(fileName, projectRoot)
        storedPath = '.';
        isRelative = true;
    end
end

function fileName = resolveArtifactPath(manifest, artifact)
    fileName = char(artifact.path);
    if isfield(artifact, 'pathIsRelative') && artifact.pathIsRelative
        fileName = strrep(fileName, '/', filesep);
        fileName = fullfile(char(manifest.projectRoot), fileName);
    end
    fileName = canonicalPath(fileName);
end

function value = canonicalPath(value)
    value = char(value);
    if isempty(value)
        return;
    end
    if usejava('jvm')
        try
            value = char(java.io.File(value).getCanonicalPath());
            return;
        catch
        end
    end
    if ~isAbsolutePath(value)
        value = fullfile(pwd, value);
    end
end

function tf = isAbsolutePath(value)
    if ispc
        tf = ~isempty(regexp(value, '^[A-Za-z]:[\\/]|^\\\\', 'once'));
    else
        tf = startsWith(value, filesep);
    end
end

function id = newId(prefix)
    if nargin < 1 || isempty(prefix)
        prefix = 'artifact';
    end
    prefix = lower(regexprep(char(prefix), '[^A-Za-z0-9]+', '-'));
    prefix = regexprep(prefix, '(^-+|-+$)', '');
    if isempty(prefix)
        prefix = 'artifact';
    end
    if usejava('jvm')
        suffix = char(java.util.UUID.randomUUID());
        suffix = suffix(1:12);
    else
        [~, suffix] = fileparts(tempname);
        suffix = suffix(1:min(12, numel(suffix)));
    end
    id = sprintf('%s-%s-%s', prefix, ...
        char(datetime('now', 'Format', 'yyyyMMdd-HHmmss')), suffix);
end

function writeJson(fileName, value)
    folder = fileparts(fileName);
    if ~isempty(folder) && exist(folder, 'dir') ~= 7
        mkdir(folder);
    end
    try
        txt = jsonencode(value, 'PrettyPrint', true);
    catch ME
        try
            txt = jsonencode(value);
        catch
            error('nhpulseManifest:JsonEncodingFailed', ...
                ['Manifest metadata must contain JSON-compatible values. ', ...
                 'Original error: %s'], ME.message);
        end
    end
    fid = fopen(fileName, 'w');
    if fid < 0
        error('nhpulseManifest:JsonWriteFailed', ...
            'Could not open manifest JSON for writing: %s', fileName);
    end
    cleaner = onCleanup(@() fclose(fid));
    fprintf(fid, '%s', txt);
end
