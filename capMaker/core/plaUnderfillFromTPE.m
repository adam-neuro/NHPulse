function occPLAout = plaUnderfillFromTPE(occTPEin, occPLAin, opts)
% plaUnderfillFromTPE
%   Build/augment a PLA occupancy mask so that PLA fills everywhere "under"
%   the *lowest* TPE voxel at each (x,y), with NO gap (touching).
%
%   Core behavior:
%     - For each (x,y), find first occupied TPE voxel index k0 along z.
%     - Add PLA at (x,y,1:k0-1). This touches TPE at k0 (no gap).
%     - Never adds PLA above the first TPE voxel in that column.
%     - Optional XY margin: dilate the TPE footprint in XY; margin columns
%       take the k0 of the nearest true-TPE column (via bwdist).
%
%   Optional "bottom empty pad" for watertight meshing:
%     - If output is a struct with grid metadata, you can add one *empty*
%       z-slice below (false everywhere) while extending z downward by one
%       voxel step. This does NOT move the model in printer coordinates.
%       It only makes the occupancy volume have an explicit "outside" layer
%       below, which helps isosurface close the bottom.
%
% Usage:
%   occPLAout = plaUnderfillFromTPE(occTPE);                   % PLA only from TPE
%   occPLAout = plaUnderfillFromTPE(occTPE, occPLA);           % augment existing PLA
%   occPLAout = plaUnderfillFromTPE(occTPE, [], opts);         % with opts
%
% Inputs:
%   occTPEin : logical [nx ny nz] OR struct with field .occ (+ optional x,y,z,vx,zBed)
%   occPLAin : (optional) logical [nx ny nz] OR struct with field .occ
%   opts:
%     .marginMM        (default 0)      XY dilation margin around TPE footprint
%     .closeXYVox      (default 0)      XY close radius in vox (dilate then erode)
%     .keepLargestXY   (default false)  keep largest 2D footprint component
%     .voxelSize       (default 0.5)    used if occTPEin has no .vx
%     .padBottomEmpty  (default false)  (struct outputs only) add empty z-slice below
%
% Output:
%   - If occPLAin is a struct: returns that struct with .occ updated (and z padded if enabled)
%   - Else if occTPEin is a struct and occPLAin omitted/[]: returns occOut-like struct
%   - Else: returns logical [nx ny nz]

    if nargin < 2, occPLAin = []; end
    if nargin < 3, opts = struct; end

    marginMM        = getop(opts,'marginMM',0);
    closeXYVox      = max(0, round(getop(opts,'closeXYVox',0)));
    keepLargestXY   = getop(opts,'keepLargestXY',false);
    padBottomEmpty  = getop(opts,'padBottomEmpty',false);

    % ---- unwrap inputs ----
    [occTPE, metaTPE, tpeIsStruct] = unwrapOcc(occTPEin, 'occTPEin');
    [nx,ny,nz] = size(occTPE);

    if isempty(occPLAin)
        occPLA = false(nx,ny,nz);
        metaPLA = struct();
        plaIsStruct = false;
    else
        [occPLA, metaPLA, plaIsStruct] = unwrapOcc(occPLAin, 'occPLAin');
        if ~isequal(size(occPLA), [nx ny nz])
            error('plaUnderfillFromTPE:sizeMismatch', ...
                'occPLAin must match occTPEin size. Got %s vs %s.', ...
                mat2str(size(occPLA)), mat2str(size(occTPE)));
        end
    end

    % ---- voxel size for mm->vox conversion ----
    if isfield(metaTPE,'vx') && ~isempty(metaTPE.vx)
        vx = metaTPE.vx;
    else
        vx = getop(opts,'voxelSize',0.5);
    end
    nDil = max(0, round(marginMM / vx));

    % ---- footprints ----
    cover0  = any(occTPE, 3);    % true TPE footprint (no margin) [nx ny]
    coverXY = cover0;

    if nDil > 0
        coverXY = imdilate2(coverXY, nDil);
    end
    if closeXYVox > 0
        coverXY = imdilate2(coverXY, closeXYVox);
        coverXY = imerode2(coverXY, closeXYVox);
    end
    if keepLargestXY
        coverXY = keepLargest2D(coverXY);
        cover0  = cover0 & coverXY;   % keep NN seeds inside kept component
    end

    % ---- first TPE index per (x,y) on true footprint ----
    firstIdx0 = zeros(nx,ny,'int32');  % k0, or 0 if none
    for i = 1:nx
        for j = 1:ny
            if ~cover0(i,j), continue; end
            k0 = find(occTPE(i,j,:), 1, 'first');
            if ~isempty(k0)
                firstIdx0(i,j) = int32(k0);
            end
        end
    end

    % ---- extend k0 into margin footprint via nearest-neighbor in XY ----
    firstIdx = firstIdx0;
    marginPix = coverXY & ~cover0;
    if any(marginPix(:)) && any(cover0(:))
        [~, idxNN] = bwdist(cover0); % linear index of nearest cover0 pixel
        firstIdx(marginPix) = firstIdx0(idxNN(marginPix));
    end
    % (If cover0 is empty, firstIdx stays all zeros => no underfill.)

    % ---- build underfill volume ----
    occUnder = false(nx,ny,nz);
    for i = 1:nx
        for j = 1:ny
            k0 = firstIdx(i,j);
            if k0 > 1
                occUnder(i,j,1:(k0-1)) = true;
            end
        end
    end

    occPLAnew = occPLA | occUnder;

    % ---- rewrap output ----
    if plaIsStruct
        occPLAout = metaPLA;
        occPLAout.occ = occPLAnew;
        if padBottomEmpty
            occPLAout = padBottomEmptySliceIfPossible(occPLAout);
        end
        return;
    end

    if isempty(occPLAin) && tpeIsStruct
        occPLAout = metaTPE;
        occPLAout.occ = occPLAnew;
        if padBottomEmpty
            occPLAout = padBottomEmptySliceIfPossible(occPLAout);
        end
        return;
    end

    % raw array output (no grid metadata): do not pad, would change implied coordinates
    occPLAout = occPLAnew;
end

% ================= helpers =================

function v = getop(s,f,def)
    if isstruct(s) && isfield(s,f) && ~isempty(s.(f)), v=s.(f); else, v=def; end
end

function [occ, meta, isStruct] = unwrapOcc(in, name)
    isStruct = isstruct(in);
    if isStruct
        if ~isfield(in,'occ')
            error('plaUnderfillFromTPE:badStruct', '%s is struct but missing field .occ', name);
        end
        occ  = in.occ;
        meta = in;  % preserve metadata (x,y,z,vx,zBed,...)
    else
        occ  = in;
        meta = struct();
    end

    if ~islogical(occ)
        if isnumeric(occ)
            occ = logical(occ);
        else
            error('plaUnderfillFromTPE:badOccType', ...
                '%s occupancy must be logical/numeric; got %s', name, class(occ));
        end
    end
    if ndims(occ) ~= 3
        error('plaUnderfillFromTPE:badOccDims', ...
            '%s occupancy must be 3D; ndims=%d', name, ndims(occ));
    end
end

function out = padBottomEmptySliceIfPossible(out)
% Adds an empty slice below WITHOUT changing world coordinates:
% - extends out.z downward by one step
% - shifts occ up one index so the solid stays in the same physical place
    if ~isfield(out,'z') || isempty(out.z) || numel(out.z) < 2
        return; % can't pad safely without a usable z grid
    end
    z = out.z(:)';               % row
    vz = z(2) - z(1);            % assume uniform
    z2 = [z(1)-vz, z];

    occ = out.occ;
    [nx,ny,nz] = size(occ);

    occ2 = false(nx,ny,nz+1);
    occ2(:,:,2:end) = occ;       % bottom is empty

    out.z   = z2;
    out.occ = occ2;
end

function B = imdilate2(A, n)
    if nargin<2, n=1; end
    B = logical(A);
    ker = ones(3,3);
    for i = 1:n
        B = conv2(double(B), ker, 'same') > 0;
    end
    B = logical(B);
end

function B = imerode2(A, n)
    if nargin<2, n=1; end
    B = logical(A);
    ker = ones(3,3);
    tsum = sum(ker(:));
    for i = 1:n
        B = conv2(double(B), ker, 'same') >= tsum;
    end
    B = logical(B);
end

function A = keepLargest2D(A)
    CC = bwconncomp(A, 8);
    if CC.NumObjects > 0
        [~,k] = max(cellfun(@numel, CC.PixelIdxList));
        A(:) = false;
        A(CC.PixelIdxList{k}) = true;
    end
end
