function [TR,occOut] = fuseTriListVoxel(TRlist, opts)
% fuseTriListVoxel
%   Voxel union of meshes in TRlist, plus optional extra occupancy
%   functions in opts.extraOccFns.
%
%   Inputs:
%     TRlist : cell array of triangulation objects (can include [])
%     opts   : struct with fields
%         .voxelSize   (default 0.5 mm)
%         .padVox      (default 8)
%         .zBed        (default 0)
%         .tol         (default 1e-9)
%         .extraOccFns (optional cell array of @(X,Y,Z)->logical)
%         .protectExtraOccFns (default false)
%             If true, close/manifoldize cleanup is applied only to the
%             triangulated mesh occupancy, then extra occupancy is ORed back
%             in. This keeps procedural thin/corrugated structures from
%             being flattened by cleanup intended for rail pinholes.
%         .manifoldize (default false) % enable topology-smoothing filter
%         .closeVox    (default 0) % pre-manifoldize morphological close radius
%         .manifoldizeMinThicknessMM (default 2*voxelSize) % feature-preserving target thickness
%         .manifoldizeMethod ('majority'|'closeopen', default 'majority')
%         .manifoldizeProtect6 (default true) % preserve 6-connected backbone voxels from original occ
%         .allowPermute(default false) % opt-in legacy [ny nx nz] tolerance
%
%   Output:
%     TR : triangulation of fused object

    if nargin < 2, opts = struct; end
    vx   = getop(opts,'voxelSize',0.5);
    pv   = max(1, round(getop(opts,'padVox',8)));
    zBed = getop(opts,'zBed',0);
    tol  = getop(opts,'tol',1e-9);
    allowPermute = getop(opts,'allowPermute',false); % opt-in legacy layout

    extraFns = {};
    if isfield(opts,'extraOccFns') && ~isempty(opts.extraOccFns)
        extraFns = opts.extraOccFns;
        if ~iscell(extraFns), extraFns = {extraFns}; end
    end
    protectExtra = getop(opts, 'protectExtraOccFns', false);

    % --- bounds from existing triangulations ---
    Vall = [];
    for i = 1:numel(TRlist)
        TRi = TRlist{i};
        if ~isempty(TRi)
            Vall = [Vall; TRi.Points]; %#ok<AGROW>
        end
    end

    % --- include any extra bounding points (e.g., strap extents) ---
    extraPoints = getop(opts,'extraPoints',[]);
    if ~isempty(extraPoints)
        % ensure it's an N×3 numeric array
        if ~isnumeric(extraPoints) || size(extraPoints,2) ~= 3
            error('fuseTriListVoxel:extraPoints','extraPoints must be N×3 numeric.');
        end
        Vall = [Vall; extraPoints]; %#ok<AGROW>
    end

    if isempty(Vall) && isempty(extraFns)
        TR = triangulation([],[]);
        return;
    end

    if isempty(Vall)
        % no meshes, but extraOccFns exist: define a default region
        bbMin = [-50 -50 zBed];
        bbMax = [ 50  50 zBed+50];
    else
        bbMin = min(Vall,[],1);
        bbMax = max(Vall,[],1);
    end

    pad   = (pv+1)*vx;
    x = bbMin(1)-pad : vx : bbMax(1)+pad;
    y = bbMin(2)-pad : vx : bbMax(2)+pad;

    zMin = bbMin(3)-pad; zMax = bbMax(3)+pad;
    k0   = ceil( (zBed - zMin) / vx );
    z0   = zMin + k0*vx;
    z    = z0 : vx : zMax;

    [X,Y,Z] = ndgrid(x,y,z);

    occMesh = false(size(X));

    % --- union of triangulations ---
    for i = 1:numel(TRlist)
        TRi = TRlist{i};
        if isempty(TRi), continue; end
        occ_i = occFromInpolyhedron(TRi, x, y, z, tol, allowPermute);
        occMesh = occMesh | occ_i;
    end

    % --- occupancy from extra functions (e.g., straps in voxel space) ---
    occExtra = false(size(X));
    for k = 1:numel(extraFns)
        fn = extraFns{k};
        try
            extraMask = fn(X,Y,Z);
            if ~isempty(extraMask)
                [~, extraMaskAligned] = triFromOccHelper(x, y, z, extraMask, 0.5, struct( ...
                    'allowPermute', allowPermute, ...
                    'validateOnly', true));
                occExtra = occExtra | logical(extraMaskAligned);
            end
        catch ME
            warning('fuseTriListVoxel:extraOccFnError', ...
                'Error in extraOccFn %d: %s', k, ME.message);
        end
    end
    occ = occMesh | occExtra;

    % --- hard floor at bed ---
    occ(Z < zBed) = false;
    occMesh(Z < zBed) = false;
    occExtra(Z < zBed) = false;

    % --- clear bounding box shell ---
    occ(1,:,:) = false; occ(end,:,:) = false;
    occ(:,1,:) = false; occ(:,end,:) = false;
    occMesh(1,:,:) = false; occMesh(end,:,:) = false;
    occMesh(:,1,:) = false; occMesh(:,end,:) = false;
    occExtra(1,:,:) = false; occExtra(end,:,:) = false;
    occExtra(:,1,:) = false; occExtra(:,end,:) = false;

    % Diagnostics: component count after fusion/cleanup
    closeVox = max(0, round(getop(opts, 'closeVox', 0)));
    if closeVox > 0
        se = true(3,3,3);
        if protectExtra
            occMesh = imdilateN(occMesh, se, closeVox);
            occMesh = imerodeN(occMesh, se, closeVox);
            occ = occMesh | occExtra;
        else
            occ = imdilateN(occ, se, closeVox);
            occ = imerodeN(occ, se, closeVox);
        end
        occ(Z < zBed) = false;
        occMesh(Z < zBed) = false;
        occExtra(Z < zBed) = false;
        occ(1,:,:) = false; occ(end,:,:) = false;
        occ(:,1,:) = false; occ(:,end,:) = false;
        occMesh(1,:,:) = false; occMesh(end,:,:) = false;
        occMesh(:,1,:) = false; occMesh(:,end,:) = false;
        occExtra(1,:,:) = false; occExtra(end,:,:) = false;
        occExtra(:,1,:) = false; occExtra(:,end,:) = false;
    end

    % Diagnostics: component count after fusion/cleanup
    CCpre = bwconncomp(occ, 26);
    nCompPre = CCpre.NumObjects;
    if nCompPre > 1
        warning('fuseTriListVoxel:multiComponentPre', ...
            'Fused occupancy contains %d components before manifoldize.', nCompPre);
    end

    % --- optional: make occupancy friendlier for isosurface topology ---
    if isfield(opts,'manifoldize') && opts.manifoldize
        nIter = getop(opts,'manifoldizeIters',1);
        minThickMM = getop(opts,'manifoldizeMinThicknessMM', 2*vx); % rails survive
        thrDefault = max(4, min(14, round((minThickMM / vx) * 6))); % gentler for thin rails
        thr  = getop(opts,'manifoldizeThr',thrDefault);
        method = getop(opts,'manifoldizeMethod','majority');
        protect6 = getop(opts,'manifoldizeProtect6', true);

        switch lower(method)
            case 'majority'
                if protectExtra
                    occMesh = manifoldizeOccMajority(occMesh, nIter, thr, protect6);
                    occ = occMesh | occExtra;
                else
                    occ  = manifoldizeOccMajority(occ, nIter, thr, protect6);
                end
            case 'closeopen'
                if protectExtra
                    occMesh = manifoldizeCloseOpen(occMesh, nIter);
                    occ = occMesh | occExtra;
                else
                    occ  = manifoldizeCloseOpen(occ, nIter);
                end
            otherwise
                error('fuseTriListVoxel:badMethod', 'Unknown manifoldizeMethod %s', method);
        end
        occ(Z < zBed) = false;
        occ(1,:,:) = false; occ(end,:,:) = false;
        occ(:,1,:) = false; occ(:,end,:) = false;

        CCpost = bwconncomp(occ, 26);
        nCompPost = CCpost.NumObjects;
        if nCompPost ~= nCompPre
            warning('fuseTriListVoxel:componentChange', ...
                'Component count changed during manifoldize: %d -> %d.', nCompPre, nCompPost);
        end
    end

    % --- isosurface (shared helper; canonical voxel→mesh path) ---
    [TR, occValidated] = triFromOccGrid(x, y, z, occ, 0.5, struct( ...
        'clearShellXY', true, ...
        'clearShellZ',  false, ...   % keep caps on z if you ever crop
        'cleanup',      true, ...
        'allowPermute', allowPermute));


    % snap to bed
    TR = snapTriZ(TR, zBed);

    %package occupancy mask for output
    occOut = struct();
    occOut.x = x;
    occOut.y = y;
    occOut.z = z;
    occOut.occ = occValidated; % logical [nx ny nz] canonical layout
    occOut.vx = vx;
    occOut.zBed = zBed;


    % cleanup
    if exist('remove_unreferenced','file')==2
        [V2,F2] = remove_unreferenced(TR.Points, TR.ConnectivityList);
        TR = triangulation(F2,V2);
    end
end

% ---------- helpers ----------
function val = getop(s,f,def)
    if isstruct(s) & isfield(s,f)
        if isempty(s.(f))
            val = def;
        else
            val = s.(f);
        end
    else
        val = def;
    end
end

function occ = occFromInpolyhedron(TR, x, y, z, tol, allowPermute)
    F = TR.ConnectivityList; V = TR.Points;
    Nf = faceNormals(F,V);
    [X, Y, Z] = ndgrid(x, y, z);
    occRaw = reshape(inpolyhedron(F, V, [X(:) Y(:) Z(:)], ...
        'facenormals', Nf, 'tol', tol), size(X));
    assert(isequal(size(occRaw), size(X)), ...
        'occFromInpolyhedron: size mismatch (got %s, expected %s)', ...
        mat2str(size(occRaw)), mat2str(size(X)));
    [~, occAligned] = triFromOccHelper(x, y, z, occRaw, 0.5, struct( ...
        'allowPermute', allowPermute, ...
        'validateOnly', true));
    occ = logical(occAligned);
end

function B = imdilateN(A,se,n)
    B = A;
    ker = double(se);
    for i = 1:n
        B = convn(B, ker, 'same') > 0;
    end
end

function B = imerodeN(A,se,n)
    B = A;
    ker = double(se);
    tsum = sum(ker(:));
    for i = 1:n
        B = convn(B, ker, 'same') >= tsum;
    end
end

function Nf = faceNormals(F,V)
    a = V(F(:,1),:); b = V(F(:,2),:); c = V(F(:,3),:);
    Nf = cross(b-a,c-a); n = vecnorm(Nf,2,2); n(n==0)=1; Nf = Nf./n;
end

function TR = snapTriZ(TR, zBed)
    if isempty(TR), return; end
    dz = zBed - min(TR.Points(:,3));
    if abs(dz) > 0
        V = TR.Points; V(:,3) = V(:,3) + dz;
        TR = triangulation(TR.ConnectivityList, V);
    end
end

function occ2 = manifoldizeOccMajority(occ, nIter, thr, protect6)
% manifoldizeOccMajority
% A conservative 3D majority filter to reduce voxel-scale kissing that
% causes marching-cubes nonmanifold edges.
%
% occ  : logical 3D
% nIter: iterations (1–3 typical)
% thr  : threshold in [0..27]; 14 is weak-majority
% protect6 : keep voxels that had a 6-connected neighbor in the original occ

    if nargin<2, nIter = 1; end
    if nargin<3, thr = 14; end
    if nargin<4, protect6 = true; end
    occ2 = logical(occ);
    occOrig = logical(occ);
    K = ones(3,3,3);
    K6 = zeros(3,3,3); % 6-connected backbone kernel (center + axes)
    K6(2,2,2) = 1;
    K6(1,2,2) = 1; K6(3,2,2) = 1;
    K6(2,1,2) = 1; K6(2,3,2) = 1;
    K6(2,2,1) = 1; K6(2,2,3) = 1;
    for i = 1:nIter
        n = convn(double(occ2), K, 'same');
        occ2 = n >= thr;
        if protect6
            nb6 = convn(double(occOrig), K6, 'same');
            backbone = occOrig & (nb6 >= 2); % center + at least one neighbor
            occ2 = occ2 | backbone;
        end
    end
    occ2 = logical(occ2);
end

function occ2 = manifoldizeCloseOpen(occ, nIter)
% manifoldizeCloseOpen
% Light close/open sequence to smooth while preserving thin rails.
    if nargin<2, nIter = 1; end
    occ2 = logical(occ);
    se = true(3,3,3);
    for i = 1:nIter
        occ2 = imdilate(occ2, se);
        occ2 = imerode(occ2, se);
        occ2 = imerode(occ2, se);
        occ2 = imdilate(occ2, se);
    end
end
