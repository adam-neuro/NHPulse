function TRout = cropTriAABB_watertight(TRin, boxMin, boxMax, opts)
% cropTriAABB_watertight  Watertight crop of a solid surface mesh by an AABB.
%   Computes (solid(TRin) ∩ box) in voxel space and returns a closed triangulation.
%
% TRin   : triangulation
% boxMin : [x y z] lower corner
% boxMax : [x y z] upper corner
%
% opts:
%   .voxelSize   (default 0.5)
%   .padVox      (default 1)
%   .isoLevel    (default 0.5)
%   .closeVox    (default 0)
%   .keepLargest (default false)
%   .tol         (default 1e-9)
%   .allowPermute(default false)   % opt-in legacy [ny nx nz] tolerance

    if nargin < 4, opts = struct; end
    assert(isa(TRin,'triangulation'), 'TRin must be a triangulation.');
    boxMin = boxMin(:)'; boxMax = boxMax(:)';
    assert(numel(boxMin)==3 && numel(boxMax)==3, 'boxMin/boxMax must be 1x3.');
    assert(all(boxMax > boxMin), 'boxMax must be > boxMin componentwise.');

    vx   = getop(opts,'voxelSize',0.5);
    pv   = max(0, round(getop(opts,'padVox',1)));
    iso  = getop(opts,'isoLevel',0.5);
    cv   = max(0, round(getop(opts,'closeVox',0)));
    tol  = getop(opts,'tol',1e-9);
    keepLargest = getop(opts,'keepLargest',false);
    allowPermute = getop(opts,'allowPermute',false); % opt-in legacy layout

    pad = pv*vx;
    x = (boxMin(1)-pad) : vx : (boxMax(1)+pad);
    y = (boxMin(2)-pad) : vx : (boxMax(2)+pad);
    z = (boxMin(3)-pad) : vx : (boxMax(3)+pad);

    % --- occupancy of TRin on (x,y,z) grid ---
    F = TRin.ConnectivityList;
    V = TRin.Points;
    Nf = faceNormals(F,V);

    [X, Y, Z] = ndgrid(x, y, z);
    occRaw = reshape(inpolyhedron(F, V, [X(:) Y(:) Z(:)], ...
        'facenormals', Nf, 'tol', tol), size(X));
    assert(isequal(size(occRaw), size(X)), ...
        'occFromInpolyhedron: size mismatch (got %s, expected %s)', ...
        mat2str(size(occRaw)), mat2str(size(X)));

    % Canonicalize occupancy layout via shared helper; legacy [ny nx nz] is opt-in.
    [~, occ] = triFromOccHelper(x, y, z, occRaw, iso, struct( ...
        'allowPermute', allowPermute, ...
        'validateOnly', true));

    % --- build inBox in canonical layout (no ndgrid needed) ---
    mx = (x >= boxMin(1)) & (x <= boxMax(1));
    my = (y >= boxMin(2)) & (y <= boxMax(2));
    mz = (z >= boxMin(3)) & (z <= boxMax(3));

    inBox = reshape(mx,[],1,1) & reshape(my,1,[],1) & reshape(mz,1,1,[]);

    occ = occ & inBox;

    % --- optional closing ---
    if cv > 0
        se = true(3,3,3);
        occ = imdilateN(occ,se,cv);
        occ = imerodeN(occ,se,cv);
    end

    if keepLargest
        occ = keepLargest3D(occ);
    end

    % --- isosurface via canonical helper (no axis swaps) ---
    [TRout, ~] = triFromOccHelper(x, y, z, occ, iso, struct( ...
        'allowPermute', allowPermute));

    if exist('remove_unreferenced','file')==2
        [V2,F2] = remove_unreferenced(TRout.Points, TRout.ConnectivityList);
        TRout = triangulation(F2,V2);
    end
end

% ------------ helpers ------------
function val = getop(s,f,def)
    if isstruct(s) && isfield(s,f) && ~isempty(s.(f)), val=s.(f); else, val=def; end
end

function Nf = faceNormals(F,V)
    a=V(F(:,1),:); b=V(F(:,2),:); c=V(F(:,3),:);
    Nf = cross(b-a,c-a); n=vecnorm(Nf,2,2); n(n==0)=1; Nf=Nf./n;
end

function B = imdilateN(A,se,n)
    if nargin<3, n=1; end
    B=A; ker=double(se);
    for i=1:n, B = convn(B,ker,'same')>0; end
end

function B = imerodeN(A,se,n)
    if nargin<3, n=1; end
    B=A; ker=double(se); tsum=sum(ker(:));
    for i=1:n, B = convn(B,ker,'same')>=tsum; end
end

function A = keepLargest3D(A)
    CC = bwconncomp(A,26);
    if CC.NumObjects>0
        [~,k]=max(cellfun(@numel,CC.PixelIdxList));
        A(:)=false; A(CC.PixelIdxList{k})=true;
    end
end
