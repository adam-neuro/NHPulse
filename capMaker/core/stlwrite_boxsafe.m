function stlwrite_boxsafe(TR, outFile)
% STLWRITE_BOXSAFE
%   Write STL in a Box-Drive-safe way that forces upload.
%
%   TR      : triangulation or struct compatible with stlwrite
%   outFile : final STL path inside Box folder

    arguments
        TR
        outFile (1,:) char
    end

    % Ensure folder exists
    outDir = fileparts(outFile);
    if ~isempty(outDir) && ~exist(outDir,'dir')
        mkdir(outDir);
    end

    % Temporary filename (same directory = atomic move)
    [p,n,e] = fileparts(outFile);
    tmpFile = fullfile(p, sprintf('.%s_tmp_%s%s', ...
        n, char(java.util.UUID.randomUUID), e));

    % 1) Write to temp file
    stlwrite(TR, tmpFile);

    % 2) Delete existing target if present
    if exist(outFile,'file')
        delete(outFile);
    end

    % 3) Move temp into place (Box sees CREATE)
    movefile(tmpFile, outFile, 'f');

end
