function [TR, occAligned, meta] = triFromOccHelper(x, y, z, occ, isoValue, opts)
% triFromOccHelper  Canonical voxel→mesh bridge (ndgrid convention only).
%
% Canonical convention (project-wide):
%   occ(i,j,k) corresponds to world point (x(i), y(j), z(k))
%   Coordinate grids MUST be built with [X, Y, Z] = ndgrid(x, y, z);
%   size(occ) must equal [numel(x), numel(y), numel(z)]
%   isosurface MUST be called as isosurface(X, Y, Z, occ, isoValue)
%
% This helper is the ONLY allowed path from voxel grids to meshes.
% Any legacy [ny nx nz] layouts are opt-in only via opts.allowPermute.
%
% Inputs:
%   x,y,z     : grid vectors
%   occ       : occupancy volume (logical or numeric)
%   isoValue  : isosurface level (default 0.5)
%   opts:
%       .allowPermute (default false) : permit [ny nx nz] → [nx ny nz] with warning
%       .validateOnly (default false) : align/layout-check only; skip isosurface
%
% Outputs:
%   TR         : triangulation (empty if no faces)
%   occAligned : validated occupancy in canonical layout
%   meta       : struct with field .wasPermuted (logical)

    if nargin < 6, opts = struct; end
    if nargin < 5 || isempty(isoValue), isoValue = 0.5; end

    allowPermute = getop(opts, 'allowPermute', false);
    validateOnly = getop(opts, 'validateOnly', false);

    [occAligned, wasPermuted] = alignOccToCanonical(x, y, z, occ, allowPermute);
    meta = struct('wasPermuted', wasPermuted);

    if validateOnly
        TR = []; ...triangulation([], zeros(0, 3));
        return;
    end

    % Canonical ndgrid -> isosurface path; no vertex swaps allowed.
    [X, Y, Z] = ndgrid(x, y, z);
    S = isosurface(X, Y, Z, double(occAligned), isoValue);

    if isempty(S.faces) || isempty(S.vertices)
        TR = triangulation([], zeros(0, 3));
        return;
    end

    TR = triangulation(S.faces, S.vertices);
end

% ---- helper ----
function val = getop(s, f, def)
    if isstruct(s) && isfield(s, f) && ~isempty(s.(f))
        val = s.(f);
    else
        val = def;
    end
end

function [occAligned, wasPermuted] = alignOccToCanonical(x, y, z, occ, allowPermute)
% Validate occupancy layout, optionally permitting [ny nx nz] with a warning.
    expectedSize = [numel(x), numel(y), numel(z)];
    wasPermuted = false;

    if isvector(occ) && numel(occ) == prod(expectedSize)
        occ = reshape(occ, expectedSize);
    end

    sz = size(occ);
    if isequal(sz, expectedSize)
        occAligned = occ;
        return;
    end

    if allowPermute && isequal(sz, [expectedSize(2), expectedSize(1), expectedSize(3)])
        warning('triFromOccHelper:permute', ...
            'Received occ in [ny nx nz]; permuting to canonical [nx ny nz].');
        occAligned = permute(occ, [2 1 3]);
        wasPermuted = true;
        return;
    end

    error('triFromOccHelper:shapeMismatch', ...
        'occ must be [%d %d %d]; got [%s]. Set opts.allowPermute=true to permute [ny nx nz].', ...
        expectedSize(1), expectedSize(2), expectedSize(3), num2str(sz));
end
