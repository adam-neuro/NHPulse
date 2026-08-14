function pathOut = acsSubjectPath(subjectId, key, varargin)
% ACSSUBJECTPATH Resolve subject-specific source and generated-data paths.
%
% pathOut = acsSubjectPath('M2107', 'mprageInitial') returns the DICOM
% folder currently used by capMaker for the M2107 test subject.
%
% Local overrides can be supplied in local.paths.json. Those values always
% take precedence over built-in lab defaults:
%   {
%     "subjects": {
%       "M2107": {
%         "aliases": ["2107", "21-07", "M21-07", "reeses"],
%         "root": "...",
%         "mprageInitial": "..."
%       }
%     }
%   }

    if nargin < 2 || isempty(key)
        key = 'root';
    end

    P = acsPaths(varargin{:});
    subjectId = normalizeSubjectId(subjectId, P);
    key = normalizeKey(key);

    override = subjectOverride(P, subjectId, key);
    if ~isempty(override)
        pathOut = override;
        return;
    end

    pathOut = subjectDefault(P, subjectId, key);
end

function subjectId = normalizeSubjectId(subjectId, P)
    requestedId = char(subjectId);

    canonicalId = findCanonicalSubjectId(requestedId, P);
    if ~isempty(canonicalId)
        subjectId = canonicalId;
        return;
    end

    aliases = subjectAliasPairs(P);
    idx = find(strcmpi(requestedId, aliases(:, 1)), 1);
    if ~isempty(idx)
        subjectId = aliases{idx, 2};
    else
        subjectId = upper(requestedId);
    end
end

function pathOut = subjectOverride(P, subjectId, key)
    pathOut = '';
    if ~isfield(P, 'subjects') || ~isstruct(P.subjects)
        return;
    end
    if isfield(P.subjects, subjectId)
        S = P.subjects.(subjectId);
    elseif isfield(P.subjects, lower(subjectId))
        S = P.subjects.(lower(subjectId));
    else
        return;
    end
    if isfield(S, key) && ~isempty(S.(key))
        pathOut = char(S.(key));
    end
end

function pathOut = subjectDefault(P, subjectId, key)
    defaults = defaultSubjects(P);
    if ~isfield(defaults, subjectId)
        error('acsSubjectPath:UnknownSubject', ...
            'No path defaults are defined for subject "%s". Add it to local.paths.json.', subjectId);
    end

    S = defaults.(subjectId);
    key = normalizeKey(key);
    if ~isfield(S, key)
        error('acsSubjectPath:UnknownKey', ...
            'No path key "%s" is defined for subject "%s".', key, subjectId);
    end

    pathOut = S.(key);
end

function defaults = defaultSubjects(P)
    defaults = struct();

    subjectId = 'M2107';
    subjectRoot = fullfile(P.dataRoot, 'MRIs', '2107_reeses');
    initialScan = fullfile(subjectRoot, 'initialScan');
    subjectOutput = fullfile(P.subjectOutputRoot, subjectId);

    defaults.(subjectId) = struct( ...
        'aliases', {{'2107', '21-07', 'M21-07', '2107_reeses', 'reeses'}}, ...
        'root', subjectRoot, ...
        'initialScan', initialScan, ...
        'mprageInitial', fullfile(initialScan, ...
            '21_07-T1_MPRAGE_sag_0.5mmiso-1.3.12.2.1107.5.2.43.167029.2022072014194281041410404.0.0.0'), ...
        'output', subjectOutput, ...
        'anatomyWork', fullfile(subjectOutput, 'anatomy'), ...
        'roastWork', fullfile(subjectOutput, 'roast'), ...
        'capWork', fullfile(subjectOutput, 'capMaker'), ...
        'segmentationWork', fullfile(subjectOutput, 'segmentation'));
end

function canonicalId = findCanonicalSubjectId(requestedId, P)
    canonicalId = '';
    candidates = cell(0, 1);

    if isfield(P, 'subjects') && isstruct(P.subjects)
        candidates = [candidates; fieldnames(P.subjects)]; %#ok<AGROW>
    end

    defaults = defaultSubjects(P);
    candidates = [candidates; fieldnames(defaults)];

    idx = find(strcmpi(requestedId, candidates), 1);
    if ~isempty(idx)
        canonicalId = candidates{idx};
    end
end

function pairs = subjectAliasPairs(P)
    pairs = cell(0, 2);

    defaults = defaultSubjects(P);
    pairs = [pairs; aliasPairsFromSubjects(defaults)]; %#ok<AGROW>

    if isfield(P, 'subjects') && isstruct(P.subjects)
        pairs = [pairs; aliasPairsFromSubjects(P.subjects)]; %#ok<AGROW>
    end
end

function pairs = aliasPairsFromSubjects(subjects)
    pairs = cell(0, 2);
    ids = fieldnames(subjects);
    for i = 1:numel(ids)
        subjectId = ids{i};
        aliases = aliasesFromSubject(subjects.(subjectId));
        for j = 1:numel(aliases)
            pairs(end + 1, :) = {aliases{j}, subjectId}; %#ok<AGROW>
        end
    end
end

function aliases = aliasesFromSubject(S)
    aliases = {};
    if ~isstruct(S) || ~isfield(S, 'aliases') || isempty(S.aliases)
        return;
    end

    rawAliases = S.aliases;
    if ischar(rawAliases)
        aliases = {rawAliases};
    elseif isstring(rawAliases)
        aliases = cellstr(rawAliases(:));
    elseif iscell(rawAliases)
        aliases = cellfun(@char, rawAliases(:), 'UniformOutput', false);
    end
end

function key = normalizeKey(key)
    switch lower(char(key))
        case {'root', 'subjectroot'}
            key = 'root';
        case {'initialscan', 'initialscanroot'}
            key = 'initialScan';
        case {'mprageinitial', 'initialmprage', 'scanlocation'}
            key = 'mprageInitial';
        case {'output', 'outputroot', 'work'}
            key = 'output';
        case {'anatomywork', 'anatomy', 'anatomyroot'}
            key = 'anatomyWork';
        case {'roastwork', 'roast'}
            key = 'roastWork';
        case {'capwork', 'capmaker'}
            key = 'capWork';
        case {'segmentationwork', 'segmentation'}
            key = 'segmentationWork';
        otherwise
            key = char(key);
    end
end
