function TRout = flattenBottomToPlane(TRin, z0, bandMM, opts)
% FLATTENBOTTOMTOPLANE  Replace the entire near-bottom patch by a flat cap at z=z0.
%   TRout = flattenBottomToPlane(TRin, z0, bandMM)
%   TRout = flattenBottomToPlane(TRin, z0, bandMM, struct('reorient',true,'areaRelEps',1e-10))
%
% Inputs
%   TRin     : triangulation (mm, Z up)
%   z0       : target bed plane (e.g., 0)
%   bandMM   : include any face with at least one vertex z <= z0+bandMM in the removable patch
%   opts.reorient   : run unifyOutwardNormalsRobust at end [true]
%   opts.areaRelEps : tiny area culling threshold relative to XY bbox [1e-10]
%
% Output
%   TRout    : triangulation with a perfectly flat underside at z=z0
%
% Rationale
%   This removes any “divots” within bandMM above the bed, then caps the opening with a single
%   planar sheet. It does not rely on triangle–plane intersections and is stable even when all
%   vertices lie slightly above z0.

    if nargin < 4, opts = struct; end
    doReor = getop(opts,'reorient',true);
    areaRelEps = getop(opts,'areaRelEps',1e-10);

    bandMM = max(0, bandMM);

    V = double(TRin.Points);
    F = TRin.ConnectivityList;
    nF = size(F,1);

    % --- Identify near-bottom faces (any vertex within the band) ---
    Z = V(:,3);
    isNear = any( Z(F) <= (z0 + bandMM), 2 );   % nF x 1 logical

    if ~any(isNear)
        % Nothing to flatten; optionally snap very close verts to z0 and return
        TRtmp = enforceFlatBottom(TRin, z0, bandMM, struct('reorient',doReor, 'areaRelEps',areaRelEps));
        TRout = TRtmp;
        return
    end

    % --- Submesh of the near-bottom patch & its boundary loops ---
    Fnear = F(isNear,:);
    TRnear = triangulation(Fnear, V);     % reuse global vertex IDs
    FB = freeBoundary(TRnear);            % Mx2 boundary edges of the patch
    FB = unique(sort(FB,2),'rows');
    if isempty(FB)
        % Entire mesh is near-bottom; cap with full outline of its outer rim
        % Use convex hull in XY as last resort
        warning('flattenBottomToPlane:NoBoundary','Near-bottom patch has no boundary; using XY hull.');
        V2D = V(:,1:2);
        K = convhull(V2D(:,1), V2D(:,2));
        loops = {K(:)};
    else
        loops = traceLoops(FB);
    end
    if isempty(loops)
        % Fallback to enforceFlatBottom (projects near-bed vertices and prunes slivers)
        TRtmp = enforceFlatBottom(TRin, z0, bandMM, struct('reorient',doReor, 'areaRelEps',areaRelEps));
        TRout = TRtmp;
        return
    end

    % --- Remove the near-bottom faces from the original mesh ---
    Fkeep = F(~isNear,:);

    % --- Project loop vertices to exactly z=z0 (to ensure a flat seam) ---
    for L = 1:numel(loops)
        V(loops{L},3) = z0;
    end

    % --- Triangulate each loop in XY and add as a flat cap at z=z0 ---
    Fcap = zeros(0,3);
    for L = 1:numel(loops)
        loop = loops{L};
        if numel(loop) < 3, continue; end
    
        Ploop = V(loop,1:2);             % XY polygon (N×2)
        % Triangulate; keep triangles whose centroids lie inside the polygon
        DT  = delaunayTriangulation(Ploop);
        tri = DT.ConnectivityList;       % m×3 (or 1×3; or empty if degenerate)
    
        if isempty(tri)
            % Collinear / tiny loop: if it’s exactly 3 points, try direct triangle
            if numel(loop) == 3
                tri = 1:3;
            else
                continue
            end
        end
    
        ctr  = (DT.Points(tri(:,1),:) + DT.Points(tri(:,2),:) + DT.Points(tri(:,3),:))/3;
        inside = inpolygon(ctr(:,1), ctr(:,2), Ploop(:,1), Ploop(:,2));
        tri = tri(inside,:);
        if isempty(tri), continue; end
    
        % Map local indices (relative to 'loop') to global vertex IDs as m×3
        idx = loop(tri(:));                      % (m*3)×1
        triGlobal = reshape(idx, size(tri,1), 3);% m×3 row-wise
    
        % Orient cap faces downward (normals toward -Z), then accumulate
        Fcap = [Fcap; fliplr(triGlobal)];        %#ok<AGROW>
    end


    % --- Assemble and clean small/degenerate triangles caused by projection ---
    TRtmp = triangulation([Fkeep; Fcap], V);

    % Cull tiny-area faces (robustness)
    Vt = TRtmp.Points; Ft = TRtmp.ConnectivityList;
    v1 = Vt(Ft(:,1),:); v2 = Vt(Ft(:,2),:); v3 = Vt(Ft(:,3),:);
    Atri = 0.5 * vecnorm(cross(v2 - v1, v3 - v1, 2), 2, 2);
    bb   = [min(Vt,[],1); max(Vt,[],1)];
    boxA = max( (bb(2,1)-bb(1,1)) * (bb(2,2)-bb(1,2)), eps );
    areaEps = max(areaRelEps * boxA, 1e-8);
    keepF = Atri > areaEps;
    Ft = Ft(keepF,:);

    % Remove unreferenced vertices & reindex
    used = false(size(Vt,1),1); used(Ft(:)) = true;
    map = zeros(size(Vt,1),1); map(used) = 1:nnz(used);
    V2 = Vt(used,:); F2 = map(Ft);

    TR = triangulation(F2, V2);

    % --- Optional outward reorientation
    if doReor && exist('unifyOutwardNormalsRobust','file')==2
        TR = unifyOutwardNormalsRobust(TR);
    end

    TRout = TR;
end

% ===== helpers =====
function loops = traceLoops(E)
% TRACELOOPS  Trace simple boundary loops from an undirected edge list E (Mx2).
% Returns a cell array of vertex-index vectors, each ordered around a loop.

    loops = {};
    if isempty(E), return; end

    % --- Deduplicate edges (unordered) ---
    E = sort(E,2);                  % put smaller index first per edge
    E = unique(E,'rows');           % drop duplicates

    % --- Build adjacency (list of neighbors per vertex) ---
    Vs = unique(E(:));
    key = containers.Map('KeyType','uint32','ValueType','any');
    for i = 1:size(E,1)
        a = uint32(E(i,1)); b = uint32(E(i,2));
        if ~isKey(key,a), key(a) = []; end
        if ~isKey(key,b), key(b) = []; end
        key(a) = [key(a) double(b)];
        key(b) = [key(b) double(a)];
    end

    % --- Helper: find edge row index (unordered) ---
    function ei = findEdge(u,v)
        if u>v, tmp=u; u=v; v=tmp; end
        ei = find(E(:,1)==u & E(:,2)==v, 1, 'first');
        if isempty(ei), ei = 0; end
    end

    visitedEdges = false(size(E,1),1);

    % --- Walk loops ---
    for s = Vs.'
        s = uint32(s);
        if ~isKey(key,s), continue; end
        nbs = key(s);
        for nb = nbs
            ei = findEdge(double(s), nb);
            if ei<=0 || visitedEdges(ei), continue; end   % <-- MATLAB indexing ()
            loop = [double(s) nb];
            visitedEdges(ei) = true;

            prev = double(s); cur = nb;
            while true
                if ~isKey(key, uint32(cur)), break; end
                nbrs = key(uint32(cur));
                nextv = [];
                for t = nbrs
                    ei2 = findEdge(cur, t);
                    if ei2>0 && ~visitedEdges(ei2) && t~=prev
                        nextv = t; break;
                    end
                end
                if isempty(nextv)
                    % Close if there is a direct edge back to start
                    ei3 = findEdge(cur, loop(1));
                    if ei3>0 && ~visitedEdges(ei3)
                        visitedEdges(ei3) = true;
                    end
                    break;
                end
                loop(end+1) = nextv; %#ok<AGROW>
                visitedEdges(findEdge(cur,nextv)) = true;
                prev = cur; cur = nextv;
                if cur == loop(1), break; end
            end

            % Clean & accept
            loop = unique(loop,'stable');
            if numel(loop) >= 3
                loops{end+1} = loop(:); %#ok<AGROW>
            end
        end
    end

    % --- Deduplicate loops with identical vertex sets (heuristic) ---
    K = numel(loops);
    keep = true(1,K);
    for i=1:K
        for j=i+1:K
            if numel(loops{i})==numel(loops{j}) && all(ismember(loops{i}, loops{j}))
                keep(j) = false;
            end
        end
    end
    loops = loops(keep);
end


function v = getop(s,f,def)
    if isstruct(s) && isfield(s,f) && ~isempty(s.(f)), v=s.(f); else, v=def; end
end
