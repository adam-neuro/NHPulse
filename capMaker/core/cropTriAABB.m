function TRout = cropTriAABB(TRin, boxMin, boxMax, opts)
% cropTriAABB  Crop a triangulation to an axis-aligned bounding box (AABB).
%
%   TRout = cropTriAABB(TRin, boxMin, boxMax)
%   TRout = cropTriAABB(TRin, boxMin, boxMax, opts)
%
% Inputs
%   TRin   : triangulation
%   boxMin : [x y z] lower corner
%   boxMax : [x y z] upper corner
%
% Options (all optional)
%   opts.keepMode : 'intersect' (default) or 'inside'
%       'intersect' keeps triangles that intersect the AABB
%       'inside'    keeps triangles whose ALL vertices are inside the AABB
%   opts.capPlanes : false (default). If true, attempts to cap cut faces (simple).
%
% Output
%   TRout : cropped triangulation

    if nargin < 4, opts = struct; end
    keepMode = getop(opts,'keepMode','intersect');
    capPlanes = getop(opts,'capPlanes',false);

    assert(isa(TRin,'triangulation'), 'TRin must be a triangulation.');
    boxMin = boxMin(:)'; boxMax = boxMax(:)';
    assert(numel(boxMin)==3 && numel(boxMax)==3, 'boxMin/boxMax must be 1x3.');
    assert(all(boxMax > boxMin), 'boxMax must be > boxMin componentwise.');

    V = TRin.Points;
    F = TRin.ConnectivityList;

    % Vertex inside test
    inV =  V(:,1) >= boxMin(1) & V(:,1) <= boxMax(1) & ...
           V(:,2) >= boxMin(2) & V(:,2) <= boxMax(2) & ...
           V(:,3) >= boxMin(3) & V(:,3) <= boxMax(3);

    switch lower(keepMode)
        case 'inside'
            keepF = all(inV(F), 2);

        case 'intersect'
            % Fast reject: triangle AABB vs box overlap
            v1 = V(F(:,1),:); v2 = V(F(:,2),:); v3 = V(F(:,3),:);
            triMin = min(min(v1,v2),v3);
            triMax = max(max(v1,v2),v3);

            overlap = triMax(:,1) >= boxMin(1) & triMin(:,1) <= boxMax(1) & ...
                      triMax(:,2) >= boxMin(2) & triMin(:,2) <= boxMax(2) & ...
                      triMax(:,3) >= boxMin(3) & triMin(:,3) <= boxMax(3);

            % Keep triangles that either have a vertex inside OR their AABB overlaps
            % (AABB overlap is a conservative intersect test and is typically
            % what you want for print coupons; it won't miss skinny triangles.)
            keepF = overlap;

        otherwise
            error('Unknown keepMode: %s', keepMode);
    end

    Fk = F(keepF,:);
    if isempty(Fk)
        TRout = triangulation([], zeros(0,3));
        return;
    end

    % Remove unreferenced vertices
    [V2, F2] = removeUnref(V, Fk);
    TRout = triangulation(F2, V2);

    % Optional: attempt simple capping (off by default; nontrivial to do perfectly)
    if capPlanes
        TRout = capAABB(TRout, boxMin, boxMax);
    end
end

% ---------------- helpers ----------------
function val = getop(s,f,def)
    if isstruct(s) && isfield(s,f) && ~isempty(s.(f)), val = s.(f); else, val = def; end
end

function [V2,F2] = removeUnref(V,F)
    used = false(size(V,1),1);
    used(F(:)) = true;
    map = zeros(size(V,1),1);
    map(used) = 1:nnz(used);
    V2 = V(used,:);
    F2 = map(F);
end

function TRc = capAABB(TR, boxMin, boxMax)
% Very simple cap attempt:
% - Find boundary edges (edges used once)
% - Drop boundary vertices onto the nearest box plane (snap)
% This is intentionally crude; use only for quick test prints if needed.
    F = TR.ConnectivityList;
    V = TR.Points;

    E = [F(:,[1 2]); F(:,[2 3]); F(:,[3 1])];
    E = sort(E,2);
    [uE,~,idx] = unique(E,'rows');
    counts = accumarray(idx,1);
    bE = uE(counts==1,:);
    if isempty(bE), TRc = TR; return; end

    bIdx = unique(bE(:));
    Vb = V(bIdx,:);

    % Snap each boundary vertex to closest of the 6 planes
    planes = [ ...
        boxMin(1)*ones(size(Vb,1),1), Vb(:,2), Vb(:,3);  % x=min
        boxMax(1)*ones(size(Vb,1),1), Vb(:,2), Vb(:,3);  % x=max
        Vb(:,1), boxMin(2)*ones(size(Vb,1),1), Vb(:,3);  % y=min
        Vb(:,1), boxMax(2)*ones(size(Vb,1),1), Vb(:,3);  % y=max
        Vb(:,1), Vb(:,2), boxMin(3)*ones(size(Vb,1),1);  % z=min
        Vb(:,1), Vb(:,2), boxMax(3)*ones(size(Vb,1),1)]; % z=max

    % Choose nearest snap plane per vertex
    P = reshape(planes, [size(Vb,1), 3, 6]);   % [n x 3 x 6]
    d2 = squeeze(sum((P - reshape(Vb,[size(Vb,1),3,1])).^2, 2)); % [n x 6]
    [~,k] = min(d2,[],2);
    for i = 1:size(Vb,1)
        V(bIdx(i),:) = P(i,:,k(i));
    end

    TRc = triangulation(F, V);
end
