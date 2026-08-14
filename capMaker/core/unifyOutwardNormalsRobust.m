function TRout = unifyOutwardNormalsRobust(TRin)
% Robust outward-orientation for closed meshes, including genus-1 shapes
% and non-manifold edges. One pass should suffice.
%
% Usage:
%   TRout = unifyOutwardNormalsRobust(TRin)

V = TRin.Points;
F = TRin.ConnectivityList;
nF = size(F,1);

% --- 1) Build EDGE adjacency that supports >2 faces per edge ---
[edgeNbrs, edgeFlipXor] = buildEdgeAdjacency(F); % cell arrays, per-face lists

% --- 2) Propagate consistent winding across the entire edge graph (BFS) ---
visited = false(nF,1);
needFlip = false(nF,1);
for seed = 1:nF
    if visited(seed), continue; end
    % stack rows: [face, flipFlag]
    stack = [seed, 0];
    while ~isempty(stack)
        f   = stack(end,1);
        flg = logical(stack(end,2));
        stack(end,:) = [];
        if visited(f), continue; end
        visited(f)  = true;
        needFlip(f) = flg;
        nbrs  = edgeNbrs{f};
        xors  = edgeFlipXor{f};
        for k = 1:numel(nbrs)
            g = nbrs(k);
            if ~visited(g)
                % If the shared edge has the SAME direction in both faces,
                % neighbor must be flipped relative to current orientation.
                stack(end+1,:) = [g, xor(flg, xors(k))]; %#ok<AGROW>
            end
        end
    end
end
F(needFlip,[2 3]) = F(needFlip,[3 2]);  % reverse winding where needed

% --- 3) Orient each vertex-connected shell so signed volume is positive ---
faceNbrs = buildFaceVertexAdj(F);
visited = false(nF,1);
for seed = 1:nF
    if visited(seed), continue; end
    % collect component by vertex connectivity
    comp = seed;
    q = seed; visited(seed) = true;
    while ~isempty(q)
        f = q(1); q(1) = [];
        nn = faceNbrs{f}';
        nn = nn(~visited(nn));
        visited(nn) = true;
        comp = [comp; nn]; %#ok<AGROW>
        q = [q; nn]; %#ok<AGROW>
    end
    % flip component if volume negative
    if meshSignedVolume(V, F(comp,:)) < 0
        F(comp,[2 3]) = F(comp,[3 2]);
    end
end

TRout = triangulation(F, V);
end

% ---------- helpers ----------
function [edgeNbrs, edgeFlipXor] = buildEdgeAdjacency(F)
% For each face, list neighbors across each shared EDGE.
% edgeFlipXor==1 means neighbor must be flipped to be consistent along that edge.
nF = size(F,1);
edgeNbrs   = cell(nF,1);
edgeFlipXor= cell(nF,1);

% Collect face-edge records: key = min(i,j)_max(i,j)
emap = containers.Map('KeyType','char','ValueType','any');
addEdge = @(fi,a,b) addEdgeRec(emap, fi, a, b);
for fi = 1:nF
    addEdge(fi, F(fi,1), F(fi,2));
    addEdge(fi, F(fi,2), F(fi,3));
    addEdge(fi, F(fi,3), F(fi,1));
end

keys = emap.keys;
for kk = 1:numel(keys)
    rec = emap(keys{kk});  % rows: [face, dirSign], dirSign=+1 if edge listed a->b follows canonical min->max
    m = size(rec,1);
    if m < 2, continue; end
    % connect all faces incident on this edge (handles non-manifold)
    for i = 1:m
        fi = rec(i,1); si = rec(i,2);
        for j = i+1:m
            fj = rec(j,1); sj = rec(j,2);
            sameDir = (si == sj); % same orientation along the shared edge
            edgeNbrs{fi}(end+1)    = fj; %#ok<AGROW>
            edgeFlipXor{fi}(end+1) = sameDir; %#ok<AGROW>
            edgeNbrs{fj}(end+1)    = fi; %#ok<AGROW>
            edgeFlipXor{fj}(end+1) = sameDir; %#ok<AGROW>
        end
    end
end
end

function addEdgeRec(emap, fi, a, b)
% store (face, dirSign) for edge a->b under canonical key
if a < b
    key = sprintf('%d_%d', a, b);
    sgn = +1;
else
    key = sprintf('%d_%d', b, a);
    sgn = -1;
end
if ~isKey(emap, key), emap(key) = zeros(0,2); end
emap(key) = [emap(key); fi, sgn];
end

function nbrs = buildFaceVertexAdj(F)
% Vertex-connected face adjacency (for component collection)
nF = size(F,1);
nbrs = cell(nF,1);
% map vertex -> faces
maxv = max(F(:));
vf = cell(maxv,1);
for fi = 1:nF
    v = F(fi,:);
    vf{v(1)}(end+1) = fi; %#ok<AGROW>
    vf{v(2)}(end+1) = fi; %#ok<AGROW>
    vf{v(3)}(end+1) = fi; %#ok<AGROW>
end
for fi = 1:nF
    v = F(fi,:);
    nb = [vf{v(1)}, vf{v(2)}, vf{v(3)}];
    nb = unique(nb);
    nb(nb==fi) = [];
    nbrs{fi} = nb;
end
end

function Vsigned = meshSignedVolume(V, F)
% Oriented volume (positive for outward normals)
v1 = V(F(:,1),:); v2 = V(F(:,2),:); v3 = V(F(:,3),:);
Vsigned = sum(dot(v1, cross(v2, v3, 2), 2)) / 6;
end
