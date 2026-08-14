function [TRout, occCrop] = cropOccOutAABB_watertight(occOut, boxMin, boxMax, opts)
% cropOccOutAABB_watertight
%   Crop an occupancy volume to an AABB and remesh as a watertight surface.
%
% Key idea:
%   - DO NOT clear boundary voxels (that deletes real material).
%   - Instead, pad the cropped occupancy with an *empty* 1-voxel border on all
%     sides before isosurface. This guarantees an "outside" region everywhere
%     so isosurface closes properly (including the bottom plane).
%
% Inputs:
%   occOut : struct with fields x,y,z,occ (ndgrid(x,y,z) layout)
%   boxMin, boxMax : [x y z] crop corners (world coords)
%   opts:
%     .isoLevel    (default 0.5)
%     .closeVox    (default 0)       % morphological close radius (vox)
%     .keepLargest (default false)
%     .minComponentVoxels (default 0) % prune smaller connected components
%     .padEmptyVox (default 1)       % empty border thickness (vox), >=1 recommended
%     .allowPermute(default false)   % opt-in legacy [ny nx nz] tolerance
%     .assertSingleComponent (default false) % optional guard on multi-component crops
%
% Outputs:
%   TRout   : triangulation (closed surface)
%   occCrop : struct like occOut but cropped (NOT padded): x,y,z,occ

    if nargin < 4, opts = struct; end
    iso        = getop(opts,'isoLevel',0.5);
    cv         = max(0, round(getop(opts,'closeVox',0)));
    keepLargest= getop(opts,'keepLargest',false);
    minCompVox = max(0, round(getop(opts,'minComponentVoxels',0)));
    padV       = max(0, round(getop(opts,'padEmptyVox',1)));
    allowPermute = getop(opts,'allowPermute',false); % opt-in legacy layout
    assertSingle = getop(opts,'assertSingleComponent',false);

    x   = occOut.x(:)'; 
    y   = occOut.y(:)'; 
    z   = occOut.z(:)'; 
    occ = logical(occOut.occ);
    [~, occ] = triFromOccHelper(x, y, z, occ, iso, struct( ...
        'allowPermute', allowPermute, ...
        'validateOnly', true));

    boxMin = boxMin(:)'; boxMax = boxMax(:)';
    assert(all(boxMax > boxMin), 'boxMax must be > boxMin.');

    % Indices inside crop box
    ix = find(x >= boxMin(1) & x <= boxMax(1));
    iy = find(y >= boxMin(2) & y <= boxMax(2));
    iz = find(z >= boxMin(3) & z <= boxMax(3));

    if isempty(ix) || isempty(iy) || isempty(iz)
        TRout   = triangulation([], zeros(0,3));
        occCrop = struct('x',[],'y',[],'z',[],'occ',[], 'vx',[], 'zBed',[]);
        return;
    end

    % Crop occupancy and coords
    xC   = x(ix); 
    yC   = y(iy); 
    zC   = z(iz);
    occC = occ(ix, iy, iz);

    % Optional close / keep-largest on the CROPPED volume
    if cv > 0
        se = true(3,3,3);
        occC = imdilateN(occC,se,cv);
        occC = imerodeN(occC,se,cv);
    end
    if keepLargest
        occC = keepLargest3D(occC);
    end
    if minCompVox > 0
        occC = removeSmallComponents3D(occC, minCompVox);
    end

    % Diagnostics: component count after crop/ops
    CC = bwconncomp(occC,26);
    nComp = CC.NumObjects;
    if nComp > 1
        warning('cropOccOutAABB:multiComponent', ...
            'Cropped volume has %d components after crop/pruning.', nComp);
    end
    if assertSingle
        assert(nComp <= 1, 'Cropped volume contains %d components.', nComp);
    end

    % Package the (un-padded) cropped occOut for downstream logic
    occCrop = struct('x',xC,'y',yC,'z',zC,'occ',occC, ...
                     'vx', occOut.vx, 'zBed', occOut.zBed);

    % If empty after ops, return empty mesh
    if ~any(occC(:))
        TRout = triangulation([], zeros(0,3));
        return;
    end

    % ---- Empty padding border for watertight isosurface ----
    % Determine voxel steps from coordinate vectors (assume uniform)
    if numel(xC) >= 2, dx = xC(2) - xC(1); else, dx = occOut.vx; end
    if numel(yC) >= 2, dy = yC(2) - yC(1); else, dy = occOut.vx; end
    if numel(zC) >= 2, dz = zC(2) - zC(1); else, dz = occOut.vx; end

    if padV > 0
        % pad occ with empty border
        [nx,ny,nz] = size(occC);
        occP = false(nx+2*padV, ny+2*padV, nz+2*padV);
        occP(1+padV:padV+nx, 1+padV:padV+ny, 1+padV:padV+nz) = occC;

        % extend coordinate vectors outward by padV voxels (no shifting)
        xP = [xC(1) + (-padV:-1)*dx, xC, xC(end) + (1:padV)*dx];
        yP = [yC(1) + (-padV:-1)*dy, yC, yC(end) + (1:padV)*dy];
        zP = [zC(1) + (-padV:-1)*dz, zC, zC(end) + (1:padV)*dz];
    else
        occP = occC; xP = xC; yP = yC; zP = zC;
    end

    % Remesh via canonical voxel→mesh helper (ndgrid convention).
    [TRout, ~] = triFromOccHelper(xP, yP, zP, occP, iso, struct( ...
        'allowPermute', allowPermute));

    if exist('remove_unreferenced','file')==2
        [V2,F2] = remove_unreferenced(TRout.Points, TRout.ConnectivityList);
        TRout = triangulation(F2,V2);
    end
end

% --- helpers ---
function val = getop(s,f,def)
    if isstruct(s) && isfield(s,f) && ~isempty(s.(f)), val=s.(f); else, val=def; end
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

function A = removeSmallComponents3D(A, minVoxels)
    CC = bwconncomp(A, 26);
    if CC.NumObjects == 0
        return;
    end
    sizes = cellfun(@numel, CC.PixelIdxList);
    keep = sizes >= minVoxels;
    if all(keep)
        return;
    end
    B = false(size(A));
    keepRows = find(keep);
    for i = 1:numel(keepRows)
        B(CC.PixelIdxList{keepRows(i)}) = true;
    end
    A = B;
end
