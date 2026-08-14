function [TR, occValidated, meta] = triFromOccGrid(x, y, z, occ, iso, opts)
% triFromOccGrid  Convert occupancy on an ndgrid(x,y,z) lattice into a triangulation.
%
% Convention:
%   occ is size [numel(x) numel(y) numel(z)]
%   occ(i,j,k) corresponds to world point (x(i), y(j), z(k))
%   We extract surface with isosurface(X,Y,Z,occ,iso) where [X,Y,Z]=ndgrid(x,y,z).
%
% Inputs:
%   x,y,z : grid vectors
%   occ   : logical or numeric volume, size [nx ny nz]
%   iso   : isovalue (default 0.5)
%   opts:
%     .clearShellXY (default true)   % clear x/y boundaries to avoid box walls
%     .clearShellZ  (default false)  % leave false if you want caps on z planes
%     .keepLargest  (default false)
%     .closeVox     (default 0)
%     .cleanup      (default true)   % remove unreferenced verts if available
%     .allowPermute (default false)  % legacy [ny nx nz] handling (permutes with warning)
%
% Output:
%   TR : triangulation (may be empty)
%   occValidated : occupancy after any keepLargest/close ops, in canonical layout
%   meta : struct from triFromOccHelper (e.g., .wasPermuted)

    if nargin < 5 || isempty(iso), iso = 0.5; end
    if nargin < 6, opts = struct; end

    clearShellXY = getop(opts,'clearShellXY',true);
    clearShellZ  = getop(opts,'clearShellZ',false);
    keepLargest  = getop(opts,'keepLargest',false);
    closeVox     = max(0, round(getop(opts,'closeVox',0)));
    doCleanup    = getop(opts,'cleanup',true);
    allowPermute = getop(opts,'allowPermute',false);  % opt-in legacy layout

    % Align to canonical ndgrid layout via shared helper; axis swaps only happen here.
    [~, occ] = triFromOccHelper(x, y, z, occ, iso, struct( ...
        'allowPermute', allowPermute, ...
        'validateOnly', true));

    % Boundary clearing (optional)
    if clearShellXY
        occ(1,:,:)   = 0; occ(end,:,:) = 0;
        occ(:,1,:)   = 0; occ(:,end,:) = 0;
    end
    if clearShellZ
        occ(:,:,1)   = 0; occ(:,:,end) = 0;
    end

    % Optional close (on binary interpretation)
    if closeVox > 0
        se = true(3,3,3);
        B = occ > iso; % binarize at iso
        B = imdilateN(B,se,closeVox);
        B = imerodeN(B,se,closeVox);
        occ = double(B);
    end

    if keepLargest
        B = occ > iso;
        B = keepLargest3D(B);
        occ = double(B);
    end
    occValidated = logical(occ);

    % Single authoritative voxel->mesh path
    [TR, occValidated, meta] = triFromOccHelper(x, y, z, occValidated, iso, ...
        struct('allowPermute', allowPermute));

    if doCleanup && exist('remove_unreferenced','file')==2
        [V2,F2] = remove_unreferenced(TR.Points, TR.ConnectivityList);
        TR = triangulation(F2,V2);
    end
end

% ---- helpers ----
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
