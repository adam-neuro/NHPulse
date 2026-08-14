function fingerprint = roastCustomLocationFingerprint(fileName, elecNames)
% ROASTCUSTOMLOCATIONFINGERPRINT Deterministic summary of custom locations.
%
% The ROAST run log compares saved option structs to decide whether a
% simulationTag can reuse existing model products. For custom lead fields,
% electrode names alone are not enough because different candidate layouts
% can use the same custom1/custom2/... labels. This fingerprint lets ROAST
% distinguish those layouts without changing the legacy 10-10 behavior.

    if isstring(fileName) && isscalar(fileName)
        fileName = char(fileName);
    end
    if exist(fileName, 'file') ~= 2
        error('roastCustomLocationFingerprint:MissingFile', ...
            'Custom electrode locations file not found: %s', fileName);
    end

    if ischar(elecNames)
        elecNames = {elecNames};
    elseif isstring(elecNames)
        elecNames = cellstr(elecNames(:));
    else
        elecNames = elecNames(:);
    end

    [fileNames, fileCoords] = readCustomLocations(fileName);
    coords = nan(numel(elecNames), 3);
    for i = 1:numel(elecNames)
        idx = find(strcmpi(elecNames{i}, fileNames), 1);
        if isempty(idx)
            error('roastCustomLocationFingerprint:MissingElectrode', ...
                'Custom electrode locations file is missing %s.', elecNames{i});
        end
        coords(i, :) = fileCoords(idx, :);
    end

    parts = cell(numel(elecNames), 1);
    for i = 1:numel(elecNames)
        parts{i} = sprintf('%s:%.6f,%.6f,%.6f', ...
            lower(elecNames{i}), coords(i, 1), coords(i, 2), coords(i, 3));
    end
    fingerprint = strjoin(parts, ';');
end

function [names, coords] = readCustomLocations(fileName)
    fid = fopen(fileName, 'r');
    if fid == -1
        error('roastCustomLocationFingerprint:CannotReadFile', ...
            'Could not read custom electrode locations: %s', fileName);
    end
    cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
    C = textscan(fid, '%s %f %f %f');
    names = C{1};
    coords = [C{2}, C{3}, C{4}];
end
