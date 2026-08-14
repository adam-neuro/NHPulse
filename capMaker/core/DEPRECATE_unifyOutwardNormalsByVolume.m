function TRout = unifyOutwardNormalsByVolume(TRin)
% UNIFYOUTWARDNORMALSBYVOLUME
% Robustly orient a closed surface mesh so that "outward" normals give
% positive signed volume, even for genus-1 (donut) shapes where centroid
% tests fail.
%
% Usage:
%   TRout = unifyOutwardNormalsByVolume(TRin)
%
% Input:
%   TRin  : triangulation
%
% Output:
%   TRout : triangulation with face windings made (1) consistent within
%           each connected component, then (2) flipped as-needed so the
%           component's signed volume is positive.

V = TRin.Points;
F = TRin.ConnectivityList;

% ---- 1) Build face adjacency via undirected edge map ----
nF = size(F,1);
edgeKey = @(a,b) [min(a,b), max(a,b)];
emap = containers.Map('KeyType','char','ValueType','any');   % key -> list of [face, s, t]
for fi = 1:nF
    e = [F(fi,[1 2]); F(fi,[2 3]); F(fi,[3 1])];
    for k = 1:3
        s = e(k,1); t = e(k,2);
        key = sprintf('%d_%d', edgeKey(s,t));
        if ~isKey(emap, key), emap(key) = []; end
        emap(key) = [emap(key); fi, s, t]; %#ok<AGROW>
    end
end

% Build adjacency: for faces sharing an edge, store neighbor and whether orientations match
adj = cell(nF,1);
for key = emap.keys
    rec = emap(key{1});
    if size(rec,1) == 2
        f1=rec(1,1); s1=rec(1,2); t1=rec(1,3);
        f2=rec(2,1); s2=rec(2,2); t2=rec(2,3);
        % If edges have same direction, one face must be flipped to be consistent
        sameDir = (s1==s2) && (t1==t2);
        adj{f1} = [adj{f1}; f2, sameDir];
        adj{f2} = [adj{f2}; f1, sameDir];
    end
end

% ---- 2) Enforce consistent winding per connected component (BFS) ----
visited = false(nF,1);
for f0 = 1:nF
    if visited(f0), continue; end
    % BFS stack: [face, flipFlag]; flipFlag==1 means flip this face
    stack = [f0, 0];
    toFlip = false(nF,1);
    visited(f0) = true;
    while ~isempty(stack)
        f   = stack(end,1);
        flp = stack(end,2);
        stack(end,:) = [];
        if flp, toFlip(f) = ~toFlip(f); end  % mark flip once

        % For each neighbor, decide if it needs flipping to be consistent
        nbrs = adj{f};
        for r = 1:size(nbrs,1)
            g = nbrs(r,1);
            sameDir = nbrs(r,2)~=0;
            if ~visited(g)
                % If shared edge has same direction, neighbor must be flipped an odd number of times
                needFlip = sameDir;
                stack = [stack; g, needFlip]; %#ok<AGROW>
                visited(g) = true;
            end
        end
    end
    % Apply flips for this component
    flipIdx = find(toFlip);
    if ~isempty(flipIdx)
        F(flipIdx,[2 3]) = F(flipIdx,[3 2]);  % swap to reverse winding
    end
end

% ---- 3) Ensure outward orientation by signed volume per component ----
% Recompute connected components (by vertex sharing) quickly via DFS on faces
% using adj; compute signed volume for each set, flip if negative.
visited = false(nF,1);
for f0 = 1:nF
    if visited(f0), continue; end
    % gather component faces
    comp = f0;
    queue = f0;
    visited(f0) = true;
    while ~isempty(queue)
        f = queue(1); queue(1) = [];
        nbrs = adj{f};
        for r = 1:size(nbrs,1)
            g = nbrs(r,1);
            if ~visited(g)
                visited(g) = true;
                comp(end+1) = g; %#ok<AGROW>
                queue(end+1) = g; %#ok<AGROW>
            end
        end
    end
    % signed volume of component
    Vcomp = meshSignedVolume(V, F(comp,:));
    if Vcomp < 0
        F(comp,[2 3]) = F(comp,[3 2]);  % flip all faces in component
    end
end

TRout = triangulation(F, V);
end

function Vsigned = meshSignedVolume(V, F)
% MESHSIGNEDVOLUME  Oriented volume of a closed triangle mesh.
% Positive if outward normals (right-hand rule) enclose positive volume.
v1 = V(F(:,1),:);
v2 = V(F(:,2),:);
v3 = V(F(:,3),:);
Vsigned = sum(dot(v1, cross(v2, v3, 2), 2)) / 6;
end
