function TRout = enforceFlatBottom(TRin, z0, tolMM, opts)
% ENFORCEFLATBOTTOM  Project near-bed vertices to z=z0; remove tiny/degenerate faces.
%   TRout = enforceFlatBottom(TRin, z0, tolMM)
%   TRout = enforceFlatBottom(TRin, z0, tolMM, struct('areaRelEps',1e-10,'reorient',true))
%
% Inputs
%   TRin    : triangulation (mm, Z up)
%   z0      : bed plane (e.g., 0)
%   tolMM   : project any vertex with z <= z0+tolMM down to z0 (also clamp z<z0 up to z0)
%   opts.areaRelEps : area threshold relative to bbox area to cull sliver faces (default 1e-10)
%   opts.reorient   : run unifyOutwardNormalsRobust at the end (default true)
%
% Output
%   TRout   : triangulation with a perfectly flat underside at z=z0

    if nargin < 4, opts = struct; end
    areaRelEps = getop(opts,'areaRelEps',1e-10);
    doReor     = getop(opts,'reorient',true);

    V = double(TRin.Points);
    F = TRin.ConnectivityList;

    % 1) Project/clamp vertices to the bed
    z = V(:,3);
    bump = (z <= z0 + tolMM);
    V(bump,3) = z0;
    below = (V(:,3) < z0);
    if any(below), V(below,3) = z0; end

    % 2) Remove degenerate/tiny-area faces created by projection
    v1 = V(F(:,1),:); v2 = V(F(:,2),:); v3 = V(F(:,3),:);
    Atri = 0.5 * vecnorm(cross(v2 - v1, v3 - v1, 2), 2, 2);   % absolute area in mm^2
    bb   = [min(V,[],1); max(V,[],1)];
    boxA = max( (bb(2,1)-bb(1,1)) * (bb(2,2)-bb(1,2)), eps );
    areaEps = max(areaRelEps * boxA, 1e-8);                   % robust minimum
    keepF = Atri > areaEps;

    F = F(keepF,:);

    % 3) Remove unreferenced vertices and compact
    used = false(size(V,1),1); used(F(:)) = true;
    map = zeros(size(V,1),1); map(used) = 1:nnz(used);
    V2 = V(used,:);
    F2 = map(F);

    TR = triangulation(F2, V2);

    % 4) Optional consistent outward orientation
    if doReor && exist('unifyOutwardNormalsRobust','file') == 2
        TR = unifyOutwardNormalsRobust(TR);
    end

    TRout = TR;
end

function v = getop(s,f,def)
    if isstruct(s) && isfield(s,f) && ~isempty(s.(f)), v=s.(f); else, v=def; end
end
