function TRout = capBottomAtPlaneZ(TRin, z0, opts)
% CAPBOTTOMATPLANEZ  Clip a mesh to z>=z0 and add a flat cap at z=z0.
%   TRout = capBottomAtPlaneZ(TRin, z0)
%   TRout = capBottomAtPlaneZ(TRin, z0, struct('eps',1e-6,'reorient',true))
%
% Notes:
%   - Keeps the portion with z >= z0.
%   - Adds a planar cap (triangulated in XY) along the intersection rim.
%   - Robust to “divots”/hollows intersecting the plane.
%   - Assumes coordinates are in mm and +Z is “up”.
%
% Dependencies: none beyond base MATLAB.

    if nargin < 3, opts = struct; end
    epsZ   = getop(opts,'eps',1e-3);
    doReor = getop(opts,'reorient',true);

    V  = double(TRin.Points);
    F  = TRin.ConnectivityList;

    % --- Classify vertices relative to plane
    z  = V(:,3);
    above = (z >= z0 - epsZ);

    % --- Clip each face against z>=z0 (Sutherland–Hodgman for triangles)
    Vnew = V;  % will append intersection vertices
    Fkeep = zeros(0,3);
    planeEdges = [];    % intersections along z=z0 to later build the rim

    for i = 1:size(F,1)
        f = F(i,:);
        vid = f(:);
        A  = vid(1); B = vid(2); C = vid(3);
        keepA = above(A); keepB = above(B); keepC = above(C);
        keepMask = [keepA keepB keepC];
        if all(keepMask)
            Fkeep(end+1,:) = [A B C]; %#ok<AGROW>
            continue
        elseif ~any(keepMask)
            continue
        end

        % Collect the polygon resulting from clipping this triangle
        poly = [];  ids = [];
        cyc = [A B C A; keepA keepB keepC keepA];
        for e = 1:3
            P = cyc(1,e);   Q = cyc(1,e+1);
            inP = logical(cyc(2,e));
            inQ = logical(cyc(2,e+1));
            p = V(P,:); q = V(Q,:);

            if inP && inQ
                poly(end+1,:) = q; ids(end+1,1) = Q; %#ok<AGROW>
            elseif inP && ~inQ
                t = edgePlaneT(p,q,z0,epsZ);
                x = p + t*(q-p);
                Vnew(end+1,:) = x; xID = size(Vnew,1);
                poly(end+1,:) = x; ids(end+1,1) = xID; %#ok<AGROW>
                planeEdges(end+1,:) = [ids(max(end-1,1)) xID]; %#ok<AGROW>
            elseif ~inP && inQ
                t = edgePlaneT(p,q,z0,epsZ);
                x = p + t*(q-p);
                Vnew(end+1,:) = x; xID = size(Vnew,1);
                poly(end+1,:) = x; ids(end+1,1) = xID; %#ok<AGROW>
                poly(end+1,:) = q; ids(end+1,1) = Q;   %#ok<AGROW>
                planeEdges(end+1,:) = [xID Q];         %#ok<AGROW>
            else
                % both out: possible coplanar pass-through; ignore
            end
        end

        % Triangulate the kept polygon (triangle or quad) by fan
        if size(ids,1) >= 3
            i0 = ids(1);
            for k = 2:size(ids,1)-1
                Fkeep(end+1,:) = [i0 ids(k) ids(k+1)]; %#ok<AGROW>
            end
        end
    end

    % --- Build rim loops along z=z0 from intersection edges
    if isempty(planeEdges)
        % No intersection → either fully above (nothing to cap) or fully below (empty)
        TRtmp = triangulation(Fkeep, Vnew);
        if doReor, TRtmp = unifyOutwardNormalsRobust(TRtmp); end
        TRout = TRtmp;
        return
    end

    % Deduplicate vertices that lie on z0 (within eps) to reduce tiny cracks
    onPlane = abs(Vnew(:,3) - z0) <= max(epsZ, 1e-8);
    % simple rounding snap in XY to fuse near-duplicates
    snapXY = round(Vnew(:,1:2), 6);
    [~,~,repIdx] = unique([snapXY onPlane], 'rows'); % identical XY & on-plane status
    remap = (1:size(Vnew,1))';
    for ii=1:numel(remap), remap(ii) = find(repIdx==repIdx(ii), 1, 'first'); end
    Fkeep = remap(Fkeep);
    planeEdges = remap(planeEdges);
    keepVerts = unique(remap, 'stable');
    compactMap = zeros(size(remap));
    compactMap(keepVerts) = 1:numel(keepVerts);
    Vnew = Vnew(keepVerts,:);  % compact while preserving remapped indices
    Fkeep = compactMap(Fkeep);
    planeEdges = compactMap(planeEdges);

    % Recompute edges after compaction
    [Vnew,Fkeep,planeEdges] = reindexCompact(Vnew,Fkeep,planeEdges);

    % Trace edge loops
    loops = traceLoops(planeEdges);

    % --- Cap each loop with a planar triangulation at z=z0
    Fcap = zeros(0,3);
    for L = 1:numel(loops)
        loop = loops{L};
        P2  = Vnew(loop,1:2);              % XY
        % Delaunay triangulate and keep triangles inside polygon
        DT  = delaunayTriangulation(P2);
        tri = DT.ConnectivityList;
        cc  = inpolygon( mean(P2(tri,1),2), mean(P2(tri,2),2), P2(:,1), P2(:,2) );
        tri = tri(cc,:);
        % Map local dt indices to global vertex IDs (loop indices)
        triGlobal = loop(tri);
        % Ensure cap faces oriented downward (normals toward -Z)
        Fcap = [Fcap; fliplr(triGlobal)]; %#ok<AGROW>
    end

    % --- Combine and (optionally) reorient outward
    TRtmp = triangulation([Fkeep; Fcap], Vnew);
    if doReor, TRtmp = unifyOutwardNormalsRobust(TRtmp); end
    TRout = TRtmp;
end

% ---------- helpers ----------
function t = edgePlaneT(p,q,z0,epsZ)
    % Parameter t in [0,1] where p + t*(q-p) crosses z=z0
    dz = q(3)-p(3);
    if abs(dz) < epsZ, t = 0.5; else, t = (z0 - p(3)) / dz; end
    t = min(max(t,0),1);
end

function [V2,F2,E2] = reindexCompact(V,F,E)
    used = false(size(V,1),1);
    used(F(:)) = true;
    used(E(:)) = true;
    map = zeros(size(V,1),1);
    map(used) = 1:nnz(used);
    V2 = V(used,:);
    F2 = map(F);
    E2 = map(E);
end

function loops = traceLoops(E)
    % E: Mx2 undirected edges forming one or more simple loops
    if isempty(E), loops = {}; return; end
    % Build adjacency
    G = accumarray([E(:), repmat((1:size(E,1))',2,1)], 1); %#ok<NASGU>
    adj = containers.Map('KeyType','uint32','ValueType','any');
    for i=1:size(E,1)
        a=uint32(E(i,1)); b=uint32(E(i,2));
        if ~isKey(adj,a), adj(a)=[]; end
        if ~isKey(adj,b), adj(b)=[]; end
        adj(a) = [adj(a) double(b)];
        adj(b) = [adj(b) double(a)];
    end
    % Trace
    loops = {};
    usedEdge = false(size(E,1),1);
    % helper to find edge index (unordered)
    function idx = findEdge(u,v)
        idx = find( (E(:,1)==u & E(:,2)==v) | (E(:,1)==v & E(:,2)==u), 1, 'first');
    end
    for start = unique(E(:))'
        if ~isKey(adj, uint32(start)), continue; end
        for nb = adj(uint32(start))
            ei = findEdge(start, nb);
            if ei<=0 || usedEdge(ei), continue; end
            % walk loop
            loop = [start nb];
            usedEdge(ei) = true;
            prev = start; cur = nb;
            while true
                nbs = adj(uint32(cur));
                % choose next != prev that uses an unused edge
                nxt = [];
                for t = nbs
                    ei2 = findEdge(cur,t);
                    if ei2>0 && ~usedEdge(ei2) && t~=prev
                        nxt = t; break;
                    end
                end
                if isempty(nxt) || nxt==loop(1)
                    break
                end
                loop(end+1) = nxt; %#ok<AGROW>
                usedEdge(findEdge(cur,nxt)) = true;
                prev = cur; cur = nxt;
            end
            % close if last connects to first
            if loop(end) ~= loop(1)
                % try to close explicitly if edge exists
                ei3 = findEdge(loop(end), loop(1));
                if ei3>0 && ~usedEdge(ei3), usedEdge(ei3)=true; end
            end
            % remove immediate duplicates
            loop = unique(loop,'stable');
            if numel(loop) >= 3
                loops{end+1} = loop(:); %#ok<AGROW>
            end
        end
    end
    % Deduplicate loops that are the same set
    % (simple heuristic)
    K = numel(loops);
    keep = true(1,K);
    for i=1:K
        for j=i+1:K
            if numel(loops{i})==numel(loops{j}) && all(ismember(loops{i}, loops{j}))
                keep(j)=false;
            end
        end
    end
    loops = loops(keep);
end

function v = getop(s,f,def)
    if isstruct(s) && isfield(s,f) && ~isempty(s.(f)), v=s.(f); else, v=def; end
end
