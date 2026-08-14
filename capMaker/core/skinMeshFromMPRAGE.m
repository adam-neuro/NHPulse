function [TRskin, meta] = skinMeshFromMPRAGE(dicomInput, opts)
% SKINMESHFROMMPRAGE  DICOM (MPRAGE) -> scalp triangulation cropped to cap region.
%
% Usage:
%   [TRskin, meta] = skinMeshFromMPRAGE(dicomFolder)
%   [TRskin, meta] = skinMeshFromMPRAGE({file1.dcm, file2.dcm, ...})
%   [TRskin, meta] = skinMeshFromMPRAGE(..., opts)
%
% Key opts (all optional; defaults in brackets):
%   .targetIsoMM     : isotropic resample [0.6]
%   .biasCorrect     : simple bias mitigation (divide by coarse local mean) [true]
%   .smoothIters     : Laplacian smoothing iterations on mesh [10]
%   .decimate        : target fraction in reducepatch (0..1; 1=no decim) [0.5]
%   .capTopFrac      : keep top fraction along head PC3 axis [0.35]
%   .cropAxis        : crop-plane normal in world coordinates [input-specific]
%   .cropDistance    : plane distance in dot(point,cropAxis) coordinates [fraction-derived]
%   .interactiveCrop : open selectCropPlane GUI before cropping [false]
%   .closeRadiusMM   : 3D close radius in mm (0=off) [1.5]
%   .minIslandVox    : remove components smaller than N voxels [2000]
%   .cropMarginMM    : extra bbox margin for meshing [3]
%   .isoLevel        : isosurface level after binarization [0.5]
%   .makeFullHeadMesh: also cache uncropped full-head mesh for fiducials [true]
%   .fullHeadDecimate: reducepatch target/fraction for full-head mesh [auto]
%
% Output:
%   TRskin : triangulation in patient/world mm coordinates
%   meta   : struct with fields:
%              voxelSize, vox2world (4x4), pca.R (3x3), bboxWorld, keptFrac, files
%
% Requires: Image Processing Toolbox (for bwconncomp), Statistics (for pca).

    if nargin < 2, opts = struct; end

    niftiInput = isNiftiInput(dicomInput);

    targetIso = getOpt(opts,'targetIsoMM',   0.6);
    doBias    = getOpt(opts,'biasCorrect',   false);
    smIters   = getOpt(opts,'smoothIters',   0);
    decimF    = getOpt(opts,'decimate',      500);
    capFrac   = getOpt(opts,'capTopFrac',    0.45);
    radClose  = getOpt(opts,'closeRadiusMM', 1.5);
    minVox    = getOpt(opts,'minIslandVox',  2000);
    marginMM  = getOpt(opts,'cropMarginMM',  3);
    isoLevel  = getOpt(opts,'isoLevel',      0.5);
    viz      = getOpt(opts,'viz',false);
    vizTitle = getOpt(opts,'vizTitle','skinMeshFromMPRAGE');
    permuteDims = getOpt(opts,'permuteDims',defaultPermuteDims(niftiInput));   % e.g. [3 1 2]
    flipDims = getOpt(opts,'flipDims',defaultFlipDims(niftiInput));  % e.g. [false true false]
    inputOrientation = getOpt(opts,'inputOrientation',defaultInputOrientation(niftiInput));
    cropAxis = getOpt(opts,'cropAxis',defaultCropAxis(niftiInput));   % 'auto' or [ax ay az] in world coords
    cropDistance = getOpt(opts,'cropDistance',[]);
    interactiveCrop = getOpt(opts,'interactiveCrop',false);
    cropSide = getOpt(opts,'cropSide','top');    % 'top' or 'bottom'
    alignCrop   = getOpt(opts,'alignCrop',true);     % rotate so cropAxis -> +Z
    autoUnitScale = getOpt(opts,'autoUnitScale',true);
    centerXY = getOpt(opts,'centerXY',true);
    dropToZ0 = getOpt(opts,'dropToZ0',true);
    bottomBandMM = getOpt(opts,'bottomBandMM',1.0);  % voxels within this band above z=0 become solid
    doClose      = getOpt(opts,'closeVox',1);        % morphological close radius (voxels); 0 = off
    makeFullHeadMesh = getOpt(opts,'makeFullHeadMesh', true);
    fullHeadDecimF = getOpt(opts,'fullHeadDecimate', defaultFullHeadDecimate(decimF));
    fullHeadSmoothIters = getOpt(opts,'fullHeadSmoothIters', smIters);


    % ---- Load DICOM volume + geometry ----
    [V, vox2world, voxelSize, files] = loadInputVolume(dicomInput);

    % ---- Optional hard-coded reorientation (permute voxel axes) ----
    % permuteDims maps old axes -> new axes, e.g. [3 1 2] means:
    %   newDim1 = oldDim3, newDim2 = oldDim1, newDim3 = oldDim2
    if ~isequal(permuteDims, [1 2 3])
        % Permute the volume
        V = permute(V, permuteDims);
    
        % Permute voxel size and the affine's column directions to stay correct in world
        voxelSize = voxelSize(permuteDims);
        R = vox2world(1:3,1:3);              % columns are axis directions (scaled by voxel size)
        R = R(:, permuteDims);               % reorder columns to match permuted axes
        vox2world(1:3,1:3) = R;
        % Origin stays the same; only how indices map to world changes
    end

    if any(flipDims)
        sz = size(V);
        for d = 1:3
            if ~flipDims(d), continue; end
            V = flip(V, d);
            % Update affine so voxel indices still map to correct world mm:
            % world = A*[i;j;k] + t, flipping dim d: i_d -> (sz(d)-1) - i_d
            % => A(:,d) := -A(:,d);  t := t + A(:,d)*(sz(d)-1)  (use pre-negated A(:,d))
            Ad = vox2world(1:3,d);
            vox2world(1:3,4) = vox2world(1:3,4) + Ad * (sz(d)-1);
            vox2world(1:3,d) = -Ad;
        end
    end

    if getOpt(opts, 'vizRawVolume', false)
        vizVolSlices(V, vox2world, vizTitle, 'Raw volume');
    end

    % ---- Resample to isotropic ----
    if any(abs(voxelSize - targetIso) > 1e-3)
        szV   = size(V);                        % [rows cols slices]
        scale = voxelSize ./ targetIso;         % 1x3 elementwise scale
        newSize = max(1, round(szV .* scale));  % 1x3 output size for imresize3
        V = imresize3(single(V), newSize, 'linear');
    
        voxelSize = [targetIso targetIso targetIso];
        vox2world = adjustVox2World(vox2world, size(V), voxelSize);
    else
        V = single(V);
    end

    % --- Save original DICOM frames for round-tripping later ---
    vox2world_raw   = vox2world;       % 4x4 affine: original DICOM world (pre-rotation, pre-crop)
    size_raw        = size(V);         % [nx ny nz] at this stage
    voxelSize_raw   = voxelSize;       % 1x3 voxel size (mm) at this stage


    % ---- Bias mitigation (light, robust) ----
    if doBias
        bg = imgaussfilt3(V, 15);     % very coarse "bias field"
        bg(bg < eps) = eps;
        V = V ./ bg;
        V = V ./ prctile(V(:), 99);   % normalize
        if getOpt(opts, 'vizBiasCorrection', false)
            vizVolSlices(V, vox2world, vizTitle, 'After bias correction');
        end
    else
        V = V ./ max(eps, prctile(V(:), 99));
    end

    % ---- Head mask via Otsu & cleanup ----
    t = graythresh(V(V>0));           % Otsu on nonzero voxels
    A = V > max(0.1, 0.5*t);          % conservative threshold
    A = imfill3(A);                   % fill interior holes
    A = keepLargest3D(A);             % keep largest component
    if radClose > 0
        A = morphClose3D(A, radClose, voxelSize);
    end
    A = removeSmall3D(A, minVox);
    if getOpt(opts, 'vizHeadMask', false)
        vizMaskSlices(A, vox2world, vizTitle, 'Head mask A');
    end

    TRstableHead = [];
    if makeFullHeadMesh
        TRstableHead = maskToSurfaceTR(A, vox2world, ...
            isoLevel, fullHeadSmoothIters, fullHeadDecimF, ...
            'stable pre-crop full-head mesh');
    end

   % ---- Compute crop direction (world) ----
    [X,Y,Z] = ndgrid(0:size(V,1)-1, 0:size(V,2)-1, 0:size(V,3)-1);
    Pvox    = [X(A), Y(A), Z(A)];
    Pworld  = vox2worldPts(Pvox, vox2world);
    
    usePCA = (ischar(cropAxis) || isstring(cropAxis)) && strcmpi(cropAxis,'auto');
    if usePCA
        coeff = pca(Pworld);              % world-space
        dir = coeff(:,3);                 % PC3
        methodStr = 'PCA';
    else
        dir = double(cropAxis(:)); dir = dir / norm(dir);
        methodStr = 'user';
    end
    s = Pworld * dir;                     % plane coordinate: dot(point, dir)

    if isempty(cropDistance)
        qTop = quantile(s, 1 - capFrac);
        qBot = quantile(s, capFrac);
        if strcmpi(cropSide,'top')
            cropDistance = qTop;
        else
            cropDistance = qBot;
        end
    end

    if interactiveCrop
        cropGuiOpts = getOpt(opts, 'cropGuiOptions', struct());
        [selectedAxis, selectedDistance, accepted] = selectCropPlane( ...
            A, vox2world, dir, cropDistance, cropGuiOpts);
        if ~accepted
            error('skinMeshFromMPRAGE:CropSelectionCanceled', ...
                'Interactive crop-plane selection was canceled.');
        end
        dir = selectedAxis;
        cropDistance = selectedDistance;
        s = Pworld * dir;
        methodStr = 'interactive';
    end

    % --- Pre-rotation visualization: full head iso + crop axis + plane ---
    if getOpt(opts,'viz',false)
        % PCA mean for nicer arrow anchoring; otherwise use centroid
        mu = mean(Pworld,1);
        vizIsoWithAxis(A, vox2world, dir, mu, cropDistance, ...
            getOpt(opts,'vizTitle','skinMesh'), ...
            sprintf('Uncropped + crop axis (%s, distance=%.2f mm, side=%s)', ...
                methodStr, cropDistance, cropSide));
    end


    % ---- Optionally rotate volume so dir aligns with +Z, then crop along Z ----
    if alignCrop
        % Rotate the HEAD MASK for cropping (nearest) and (optionally) the scalar volume V (linear)
        [Arot, vox2world_rot, R_used] = reorientVolume3D(A, vox2world, dir, 'nearest');
        % If you also want V reoriented for later visualization/isosurface, do:
        % [V, vox2world] = reorientVolume3D(V, vox2world, dir, 'linear');
        % Otherwise keep V, vox2world as-is; we only need Arot to compute crop.
    
        fullHeadMask = Arot;
        fullHeadVox2world = vox2world_rot;

        % Keep the selected half-space along Z after rotation.
        [A2, bbMin, bbMax] = cropAlongZDistance(Arot, vox2world_rot, cropDistance, cropSide, getOpt(opts,'cropMarginMM',3));
    
        % Use rotated frame from here for cropping bbox and surface extraction
        A  = Arot;                 % replace mask
        vox2world = vox2world_rot; % replace affine
    else
        % Original, unrotated path: crop by projecting onto dir
        fullHeadMask = A;
        fullHeadVox2world = vox2world;
        [A2, bbMin, bbMax] = cropAlongAxisDistance(A, vox2world, dir, cropDistance, cropSide, getOpt(opts,'cropMarginMM',3));
    end
    
    % ---- Debug viz (optional): show cropped-isosurface only ----
    if getOpt(opts,'viz',false)
        [Xc,Yc,Zc] = worldGridForMask(A2, vox2world);   % uses current affine (rotated if alignCrop)
        Scrop = isosurface(Xc,Yc,Zc, imgaussfilt3(single(A2),0.7), 0.5);
        vizIsoPreview(Scrop, getOpt(opts,'vizTitle','skinMesh'), 'Cropped mask (isosurface)');
    end

    % ---- Seal the bottom footprint (2D) + solidify (3D) ----
    % World grid (for robust bottom selection)
    [Xw,Yw,Zw] = worldGridForMask(A2, vox2world);
    nz = size(A2,3);
    
    % Choose the bottom slice index in world-Z
    zline = squeeze(mean(mean(Zw,1,'omitnan'),2,'omitnan'));  % 1×nz
    [~,kBottom] = min(zline);
    
    % If the geometric bottom slice has no mask voxels, walk upward until it does
    k = kBottom;
    step = 1;                       % search upward
    while k>=1 && k<=nz && ~any(A2(:,:,k),'all')
        k = k + step;
    end
    if k<1 || k>nz
        % fallback: first slice (from bottom) that has any foreground
        k = find(arrayfun(@(kk) any(A2(:,:,kk),'all'), 1:nz), 1, 'first');
        if isempty(k), error('No foreground found in cropped mask.'); end
    end
    kBottom = k;
    
    % 2D fill on the bottom slice only (seal the interior footprint)
    B0  = A2(:,:,kBottom);
    B0f = imfill(B0, 'holes');
    
    % Optional: small 2D closing to bridge sub-voxel nicks at the rim
    close2D = getOpt(opts,'bottomClose2D',1);  % 0=off, 1–2 typical
    if close2D>0
        se2 = strel('square',3);
        for t=1:close2D, B0f = imdilate(B0f,se2); end
        for t=1:close2D, B0f = imerode(B0f,se2);  end
    end
    
    A2_sealed = A2;
    A2_sealed(:,:,kBottom) = B0f;    % only modify the selected bottom slice
    
    % 3D cavity fill to eliminate internal voids now that the base is sealed
    A2_filled = fillHollow3D(A2_sealed);
    
    % Optional: light 3D closing to seal hairline tunnels
    closeVox = getOpt(opts,'closeVox',1);      % 0=off; 1–2 typical
    if closeVox>0
        se3 = true(3,3,3);
        A2_filled = imdilateN(A2_filled, se3, closeVox);
        A2_filled = imerodeN(A2_filled, se3, closeVox);
    end
    
    % Keep single connected body (robustness)
    A2_filled = keepLargest3D(A2_filled);
    
    % ---- Extract surface (unchanged) ----
    A2s = imgaussfilt3(single(A2_filled), 0.7);
    S   = isosurface(Xw, Yw, Zw, A2s, isoLevel);
    if isempty(S.vertices) || isempty(S.faces)
        error('Empty surface after bottom seal + solidify. Tune bottomClose2D/closeVox.');
    end
    TR  = triangulation(S.faces, S.vertices);

    % ---- Mesh smoothing & decimation ----
    if smIters > 0
        TR = laplacianSmoothTR(TR, smIters, 0.5);
    end
    if decimF ~= 1
        [F2, V2] = reducepatch(TR.ConnectivityList, TR.Points, decimF);
        TR = triangulation(F2, V2);
    end

    % ---- Fix orientation (outward normals) robustly ----
    TR = unifyOutwardNormalsRobust(TR);

    % --- Sanity: physical extent from current world coordinates
    bbMinTR = min(TR.Points,[],1);
    bbMaxTR = max(TR.Points,[],1);
    extentMM = bbMaxTR - bbMinTR;
    
    % --- Optional auto unit correction (guarded)
    % If extent is implausible for a macaque head (e.g., > 1000 mm) but becomes
    % plausible when divided by 1000, assume meters→mm mix-up and rescale.
    unitScale = 1.0;
    if autoUnitScale
        ext = max(extentMM);
        if ext > 1000 && (ext/1000) >= 60 && (ext/1000) <= 300
            warning('implausible scale detected')
            unitScale = 1/1000;   % convert m->mm
        end
    end
    
    if unitScale ~= 1
        % Rescale mesh AND affine into millimeters
        TR = triangulation(TR.ConnectivityList, TR.Points * unitScale);
        vox2world(1:3,1:3) = vox2world(1:3,1:3) * unitScale;
        vox2world(1:3,4)   = vox2world(1:3,4)   * unitScale;
        fullHeadVox2world(1:3,1:3) = fullHeadVox2world(1:3,1:3) * unitScale;
        fullHeadVox2world(1:3,4)   = fullHeadVox2world(1:3,4)   * unitScale;
        % Also fix the bbox you computed earlier for mask
        bbMin = bbMin * unitScale;  %#ok<*NASGU>
        bbMax = bbMax * unitScale;
        % Recompute extent (for meta)
        bbMinTR = min(TR.Points,[],1);
        bbMaxTR = max(TR.Points,[],1);
        extentMM = bbMaxTR - bbMinTR;
    end
    
    % --- Printer-friendly placement: center XY and drop to Z=0 (pure translation)
    t = [0 0 0];
    if centerXY
        t(1) = -0.5*(bbMinTR(1)+bbMaxTR(1));
        t(2) = -0.5*(bbMinTR(2)+bbMaxTR(2));
    end
    if dropToZ0
        t(3) = -bbMinTR(3);
    end
    
    T_world2print = eye(4); T_world2print(1:3,4) = t(:);
    Vprint = TR.Points + t;
    TRprint = triangulation(TR.ConnectivityList, Vprint);

    TRfiducialHead = [];
    if makeFullHeadMesh
        TRfullWorld = maskToSurfaceTR(fullHeadMask, fullHeadVox2world, ...
            isoLevel, fullHeadSmoothIters, fullHeadDecimF, 'full-head fiducial mesh');
        VfullPrint = TRfullWorld.Points + t;
        TRfiducialHead = triangulation(TRfullWorld.ConnectivityList, VfullPrint);
    end

    if viz
        vizMesh(TRprint, vizTitle, 'TR (post-smooth/decimate)');
    end

    % ---- Outputs ----
    TRskin = TRprint;                         % print-frame mesh (mm), XY-centered & Z=0
    
    meta = struct();
    
    % Final WORLD frame (after crop/rotation, before print translation)
    meta.vox2world       = vox2world;         % 4x4 voxel->world (mm) for final volume frame
    meta.bboxWorld       = [bbMin; bbMax];    % 2x3 bbox (mm) in final world
    meta.voxelSize       = voxelSize;         % mm/voxel in final frame
    meta.units           = 'mm';
    meta.extentWorldMM   = extentMM;          % size along X/Y/Z (mm)
    meta.unitScale       = unitScale;         % 1 or 1/1000 if auto-corrected
    
    % Print-frame (pure translation applied to mesh)
    meta.print.used          = true;
    meta.print.T_world2print = T_world2print;            % P_print = T_world2print * [P_world;1]
    meta.print.T_print2world = inv(T_world2print);

    % Fiducial full-head mesh in the same print frame as TRskin.
    meta.fiducialHead.available = ~isempty(TRfiducialHead);
    meta.fiducialHead.cacheVariable = 'TRfiducialHead';
    meta.fiducialHead.coordinateFrame = 'capMakerPrintMm';
    meta.fiducialHead.sourceFrame = 'capMakerPostCropWorldMm';
    meta.fiducialHead.description = ['Uncropped full-head surface for ', ...
        'anatomical fiducial selection; do not use for manufacturing rails.'];
    meta.fiducialHead.decimate = fullHeadDecimF;
    meta.fiducialHead.smoothIters = fullHeadSmoothIters;
    if ~isempty(TRfiducialHead)
        meta.fiducialHead.pointCount = size(TRfiducialHead.Points, 1);
        meta.fiducialHead.faceCount = size(TRfiducialHead.ConnectivityList, 1);
        meta.fiducialHead.boundsPrintMM = [ ...
            min(TRfiducialHead.Points, [], 1); ...
            max(TRfiducialHead.Points, [], 1)];
        meta.fiducialHead.TR = TRfiducialHead;
    end

    % Stable full-head mesh before align/crop/print transforms. This is the
    % frame in which scalp warp products can be crop-plane independent.
    meta.stableHead.available = ~isempty(TRstableHead);
    meta.stableHead.cacheVariable = 'TRstableHead';
    meta.stableHead.coordinateFrame = 'capMakerPreCropWorldMm';
    meta.stableHead.description = ['Uncropped full-head surface in the ', ...
        'post-orientation/pre-crop anatomical frame.'];
    meta.stableHead.decimate = fullHeadDecimF;
    meta.stableHead.smoothIters = fullHeadSmoothIters;
    if ~isempty(TRstableHead)
        meta.stableHead.pointCount = size(TRstableHead.Points, 1);
        meta.stableHead.faceCount = size(TRstableHead.ConnectivityList, 1);
        meta.stableHead.boundsWorldMM = [ ...
            min(TRstableHead.Points, [], 1); ...
            max(TRstableHead.Points, [], 1)];
        meta.stableHead.TR = TRstableHead;
    end
    
    % Original DICOM frame (after your permute/flip/resample; before alignCrop)
    meta.original.size        = size_raw;
    meta.original.voxelSize   = voxelSize_raw;           % as mm (if unitScale~=1, these are pre-scale values)
    meta.original.vox2world   = vox2world_raw * blkdiag(unitScale*eye(3),1); % ensure consistency in mm
    meta.original.permuteDims = permuteDims;
    meta.original.flipDims    = logical(flipDims);
    meta.original.targetIsoMM = targetIso;
    meta.original.orientation = char(inputOrientation);
    
    % Align-crop rotation (world-space)
    if exist('R_used','var')
        meta.align.used = true;
        meta.align.R    = R_used;                         % P_finalWorld = R * P_dicomWorld
    else
        meta.align.used = false;
        meta.align.R    = eye(3);
    end
    meta.align.dir  = dir(:);
    meta.align.side = cropSide;
    meta.align.frac = capFrac;
    meta.align.distance = cropDistance;
    
    % PCA info (if used)
    if exist('coeff','var'), meta.pca.R = coeff; else, meta.pca.R = []; end
    
    % Provenance
    meta.files = files;



end

% ===================== helpers =====================
function val = getOpt(s,f,def)
    if isstruct(s) && isfield(s,f) && ~isempty(s.(f))
        val = s.(f);
    else
        val = def;
    end
end

function decimF = defaultFullHeadDecimate(capDecimF)
    if isnumeric(capDecimF) && isscalar(capDecimF) && isfinite(capDecimF) && capDecimF > 1
        decimF = max(double(capDecimF), 5000);
    else
        decimF = capDecimF;
    end
end

function tf = isNiftiInput(inputArg)
    tf = false;
    if ~(ischar(inputArg) || isstring(inputArg))
        return;
    end
    pathIn = lower(char(inputArg));
    tf = endsWith(pathIn, '.nii') || endsWith(pathIn, '.nii.gz');
end

function TR = maskToSurfaceTR(A, vox2world, isoLevel, smIters, decimF, label)
    [Xw, Yw, Zw] = worldGridForMask(A, vox2world);
    As = imgaussfilt3(single(A), 0.7);
    S = isosurface(Xw, Yw, Zw, As, isoLevel);
    if isempty(S.vertices) || isempty(S.faces)
        error('skinMeshFromMPRAGE:EmptySurface', ...
            'Empty surface while building %s.', label);
    end
    TR = triangulation(S.faces, S.vertices);
    if smIters > 0
        TR = laplacianSmoothTR(TR, smIters, 0.5);
    end
    if ~isempty(decimF) && decimF ~= 1
        [F2, V2] = reducepatch(TR.ConnectivityList, TR.Points, decimF);
        TR = triangulation(F2, V2);
    end
    TR = unifyOutwardNormalsRobust(TR);
end

function dims = defaultPermuteDims(niftiInput)
    if niftiInput
        dims = [1 2 3];
    else
        dims = [3 1 2];
    end
end

function flips = defaultFlipDims(niftiInput)
    if niftiInput
        flips = [false false false];
    else
        flips = [false false true];
    end
end

function axis = defaultCropAxis(niftiInput)
    if niftiInput
        axis = [0 0.3 1];
    else
        axis = [0 0.3 -1];
    end
end

function orientation = defaultInputOrientation(niftiInput)
    if niftiInput
        orientation = 'ras';
    else
        orientation = '';
    end
end

function [V, vox2world, voxelSize, files] = loadInputVolume(inputArg)
    if isNiftiInput(inputArg)
        [V, vox2world, voxelSize, files] = loadNiftiVolume(char(inputArg));
    else
        [V, vox2world, voxelSize, files] = loadDicomVolume(inputArg);
    end
end

function [V, vox2world, voxelSize, files] = loadNiftiVolume(fileName)
    if exist(fileName, 'file') ~= 2
        error('NIfTI file not found: %s', fileName);
    end

    if exist('spm_vol', 'file') == 2 && exist('spm_read_vols', 'file') == 2
        Vhdr = spm_vol(fileName);
        Vhdr = Vhdr(1);
        V = single(spm_read_vols(Vhdr));
        voxelSize = sqrt(sum(Vhdr.mat(1:3, 1:3) .^ 2, 1));
    else
        info = niftiinfo(fileName);
        V = single(niftiread(info));
        voxelSize = double(info.PixelDimensions(1:3));
    end

    % The integration passes a ROAST-ready RAS working copy. Use a simple
    % zero-based voxel-to-mm frame so capMaker's inverse print/crop transform
    % returns directly to that image lattice.
    vox2world = eye(4);
    vox2world(1:3, 1:3) = diag(voxelSize);
    files = {fileName};
end

function [V, vox2world, voxelSize, files] = loadDicomVolume(inputArg)
    if ischar(inputArg) || isstring(inputArg)
        folder = char(inputArg);
        files = listDicomFiles(folder);
    elseif iscell(inputArg)
        files = inputArg;
    else
        error('dicomInput must be a folder path or a cell array of filenames.');
    end
    % Sort by InstanceNumber if available
    infos = cellfun(@dicominfo, files, 'uni', 0);
    inst = cellfun(@(s) getfield_safe(s,'InstanceNumber',NaN), infos);
    [~,ord] = sort(inst);
    files = files(ord);

    % Stack slices into volume
    I0 = dicomread(infos{1});
    sz2 = [size(I0,1), size(I0,2)];
    V = zeros([sz2 numel(files)], 'like', I0);
    V(:,:,1) = I0;
    for k=2:numel(files)
        V(:,:,k) = dicomread(infos{k});
    end
    V = single(V);

    % Geometry: PixelSpacing, SliceThickness, ImageOrientationPatient, ImagePositionPatient
    ps = double(getfield_safe(infos{1}, 'PixelSpacing', [1;1]));
    st = double(getfield_safe(infos{1}, 'SliceThickness', 1));
    voxelSize = [ps(1) ps(2) st];

    IOP = double(getfield_safe(infos{1}, 'ImageOrientationPatient', [1 0 0 0 1 0]));
    dirX = IOP(1:3); dirY = IOP(4:6);
    dirZ = cross(dirX, dirY);
    R = [dirX(:), dirY(:), dirZ(:)];            % columns are axes
    origin = double(getfield_safe(infos{1}, 'ImagePositionPatient', [0 0 0]));
    origin = origin(:)';   % row vector [1×3]

    % Build 4x4 vox->world affine: world = origin + R*diag(voxelSize)*[i;j;k]
    vox2world = eye(4);
    vox2world(1:3,1:3) = R .* voxelSize;        % scale each axis
    vox2world(1:3,4)   = origin(:);
end

function files = listDicomFiles(folder)
    d = dir(fullfile(folder,'**','*.dcm'));
    if isempty(d)
        d = dir(fullfile(folder,'**','*'));
        d = d(~[d.isdir]);
    end
    if isempty(d)
        error('No DICOM files found in %s', folder);
    end
    files = arrayfun(@(x) fullfile(x.folder, x.name), d, 'uni', 0);
end

function v = getfield_safe(s, f, def)
    if isfield(s,f), v = s.(f); else, v = def; end
end

function vox2world = adjustVox2World(vox2world_in, szV, voxSz)
    Rscaled = normalizeCols(vox2world_in(1:3,1:3));
    vox2world = eye(4);
    vox2world(1:3,1:3) = Rscaled .* voxSz;  % re-scale along axes
    vox2world(1:3,4)   = vox2world_in(1:3,4);
end

function Rn = normalizeCols(R)
    Rn = R;
    for i=1:3
        n = norm(R(:,i));
        if n>0, Rn(:,i) = R(:,i)/n; end
    end
end

function P = vox2worldPts(Pvox, vox2world)
    % Pvox: [N x 3] in 0-based voxel indices
    A = vox2world(1:3,1:3);
    t = vox2world(1:3,4).';
    P = Pvox * A.' + t;   % world mm
end

function [bbMin, bbMax] = bboxWithMargin(P, margin)
    bbMin = min(P,[],1) - margin;
    bbMax = max(P,[],1) + margin;
end

function Aout = cropWorldMask(A, vox2world, bbMin, bbMax)
    % Construct a logical subvolume by world-space bbox mask
    [X,Y,Z] = ndgrid(0:size(A,1)-1, 0:size(A,2)-1, 0:size(A,3)-1);
    Pw = vox2worldPts([X(:) Y(:) Z(:)], vox2world);
    in = Pw(:,1) >= bbMin(1) & Pw(:,1) <= bbMax(1) & ...
         Pw(:,2) >= bbMin(2) & Pw(:,2) <= bbMax(2) & ...
         Pw(:,3) >= bbMin(3) & Pw(:,3) <= bbMax(3);
    Aout = false(size(A),'like',A);
    Aout(in) = A(in);
end

function [Xw,Yw,Zw] = worldGridForMask(A, vox2world)
    % Generate world-space ndgrid (mm) matching A's voxel lattice
    [X,Y,Z] = ndgrid(0:size(A,1)-1, 0:size(A,2)-1, 0:size(A,3)-1);
    Pw = vox2worldPts([X(:) Y(:) Z(:)], vox2world);
    Xw = reshape(Pw(:,1), size(A));
    Yw = reshape(Pw(:,2), size(A));
    Zw = reshape(Pw(:,3), size(A));
end

function Afilled = imfill3(A)
%IMFILL3  Fill internal cavities in a 3-D binary volume.
%   Afilled = imfill3(A)
% Fills holes that are enclosed in 3D (not just per-slice).
%
% Method: label connected components in the complement (~A) with 6-connectivity.
% Components that touch any volume boundary are "exterior air".
% Everything else is interior cavity and gets filled.

    validateattributes(A, {'logical','numeric'}, {'nonsparse','real'});
    A = logical(A);
    sz = size(A);
    if numel(sz) ~= 3
        error('imfill3 expects a 3-D array.');
    end

    % Complement (air)
    B = ~A;

    % Boundary mask (linear indices) for any voxel on the volume boundary
    bm = false(sz);
    bm(1,:,:)   = true;
    bm(end,:,:) = true;
    bm(:,1,:)   = true;
    bm(:,end,:) = true;
    bm(:,:,1)   = true;
    bm(:,:,end) = true;

    % Connected components of air with 6-connectivity
    CC = bwconncomp(B, 6);

    % Mark exterior air: any component that touches the boundary
    exterior = false(numel(A),1);
    if CC.NumObjects > 0
        bm_lin = bm(:);
        for i = 1:CC.NumObjects
            idx = CC.PixelIdxList{i};
            if any(bm_lin(idx))
                exterior(idx) = true;
            end
        end
    end

    % Fill: interior cavities = air minus exterior → set to solid
    Afilled = ~reshape(exterior, sz);
end


function A = keepLargest3D(A)
    CC = bwconncomp(A, 26);
    if CC.NumObjects < 1, return; end
    [~,k] = max(cellfun(@numel, CC.PixelIdxList));
    A(:) = false; A(CC.PixelIdxList{k}) = true;
end

function A = removeSmall3D(A, minVox)
    if minVox<=0, return; end
    CC = bwconncomp(A, 26);
    for i = 1:CC.NumObjects
        if numel(CC.PixelIdxList{i}) < minVox
            A(CC.PixelIdxList{i}) = false;
        end
    end
end

function A = morphClose3D(A, radMM, voxSz)
    rad = max(1, round(radMM ./ voxSz));
    se = true(2*rad(1)+1, 2*rad(2)+1, 2*rad(3)+1);
    A = imdilate(A, se);
    A = imerode(A, se);
end

function TR = laplacianSmoothTR(TR, iters, lambda)
% LAPLACIANSMOOTHTR  Simple umbrella smoothing with correct update.
% Usage: TR = laplacianSmoothTR(TR, iters, lambda)
% Notes:
%   - lambda in (0,1); e.g., 0.5 is strong, 0.2 is gentle
%   - fixed boundary: vertices on the free boundary are held in place
% -this used to change the units of the model, but we think we fixed it
% although it hasn't been tested yet. -acs27sep2025

    V = double(TR.Points);
    F = TR.ConnectivityList;

    % Build 1-ring adjacency (umbrella)
    n = size(V,1);
    A = sparse(n,n);
    for i=1:size(F,1)
        f = F(i,:);
        A(f(1),f(2)) = 1; A(f(2),f(1)) = 1;
        A(f(2),f(3)) = 1; A(f(3),f(2)) = 1;
        A(f(3),f(1)) = 1; A(f(1),f(3)) = 1;
    end
    deg = full(sum(A,2)); deg(deg==0) = 1;

    % Fixed boundary vertices (don’t move the rim)
    bvidx = unique(freeBoundary(TR));
    isFixed = false(n,1);
    isFixed(bvidx) = true;

    for k = 1:iters
        avgNbr = (A * V) ./ deg;           % 1-ring average
        Vnew   = V + lambda * (avgNbr - V);% CORRECT update
        V(~isFixed,:) = Vnew(~isFixed,:);  % keep boundary fixed
    end

    TR = triangulation(F, V);
end


function A = cotmatrix_lumped(V,F)
    % quick-and-dirty umbrella (1-hop) if cot weights unavailable
    n = size(V,1);
    A = sparse(n,n);
    for i=1:size(F,1)
        f = F(i,:);
        A(f(1),f(2)) = 1; A(f(2),f(1)) = 1;
        A(f(2),f(3)) = 1; A(f(3),f(2)) = 1;
        A(f(3),f(1)) = 1; A(f(1),f(3)) = 1;
    end
end

function [edgeNbrs, edgeFlipXor] = buildEdgeAdjacency(F)
    nF = size(F,1);
    edgeNbrs = cell(nF,1); edgeFlipXor = cell(nF,1);
    emap = containers.Map('KeyType','char','ValueType','any');
    addEdge = @(fi,a,b) addEdgeRec(emap, fi, a, b);
    for fi=1:nF
        addEdge(fi,F(fi,1),F(fi,2));
        addEdge(fi,F(fi,2),F(fi,3));
        addEdge(fi,F(fi,3),F(fi,1));
    end
    keys = emap.keys;
    for kk = 1:numel(keys)
        rec = emap(keys{kk}); m = size(rec,1);
        if m < 2, continue; end
        for i=1:m
            fi = rec(i,1); si = rec(i,2);
            for j=i+1:m
                fj = rec(j,1); sj = rec(j,2);
                sameDir = (si == sj);
                edgeNbrs{fi}(end+1)    = fj; %#ok<AGROW>
                edgeFlipXor{fi}(end+1) = sameDir; %#ok<AGROW>
                edgeNbrs{fj}(end+1)    = fi; %#ok<AGROW>
                edgeFlipXor{fj}(end+1) = sameDir; %#ok<AGROW>
            end
        end
    end
end

function addEdgeRec(emap, fi, a, b)
    if a < b, key = sprintf('%d_%d', a,b); sgn = +1; else, key = sprintf('%d_%d', b,a); sgn = -1; end
    if ~isKey(emap, key), emap(key) = zeros(0,2); end
    emap(key) = [emap(key); fi, sgn];
end

function nbrs = buildFaceVertexAdj(F)
    nF = size(F,1); nbrs = cell(nF,1);
    maxv = max(F(:)); vf = cell(maxv,1);
    for fi=1:nF
        v = F(fi,:);
        vf{v(1)}(end+1) = fi; %#ok<AGROW>
        vf{v(2)}(end+1) = fi; %#ok<AGROW>
        vf{v(3)}(end+1) = fi; %#ok<AGROW>
    end
    for fi=1:nF
        v = F(fi,:);
        nb = unique([vf{v(1)}, vf{v(2)}, vf{v(3)}]); nb(nb==fi) = [];
        nbrs{fi} = nb;
    end
end

function Vsigned = meshSignedVolume(V, F)
    v1 = V(F(:,1),:); v2 = V(F(:,2),:); v3 = V(F(:,3),:);
    Vsigned = sum(dot(v1, cross(v2, v3, 2), 2)) / 6;
end
function vizVolSlices(V, vox2world, figName, panelName)
    % Show mid-slices of a scalar volume in world frame
    figure('Name',sprintf('%s - %s',figName,panelName),'Color','w'); 
    t = tiledlayout(2,2,'Padding','compact','TileSpacing','compact');
    title(t, panelName);
    % axial
    ax1 = nexttile; imagesc(squeeze(V(:,:,round(end/2)))'); axis(ax1,'image','off'); title(ax1,'Axial'); colormap(ax1, gray);
    % sagittal
    ax2 = nexttile; imagesc(squeeze(permute(V(round(end/2),:,:),[2 3 1]))'); axis(ax2,'image','off'); title(ax2,'Sagittal'); colormap(ax2, gray);
    % coronal
    ax3 = nexttile; imagesc(squeeze(permute(V(:,round(end/2),:),[1 3 2]))'); axis(ax3,'image','off'); title(ax3,'Coronal'); colormap(ax3, gray);
    % MIP (quick sanity)
    ax4 = nexttile; imagesc(max(V,[],3)'); axis(ax4,'image','off'); title(ax4,'Axial MIP'); colormap(ax4, gray);
end

function vizMaskSlices(A, vox2world, figName, panelName)
    % Show mid-slices of a binary mask
    figure('Name',sprintf('%s - %s',figName,panelName),'Color','w'); 
    t = tiledlayout(2,2,'Padding','compact','TileSpacing','compact');
    title(t, panelName);
    % axial
    ax1 = nexttile; imagesc(squeeze(A(:,:,round(end/2)))'); axis(ax1,'image','off'); title(ax1,'Axial'); colormap(ax1, gray);
    % sagittal
    ax2 = nexttile; imagesc(squeeze(permute(A(round(end/2),:,:),[2 3 1]))'); axis(ax2,'image','off'); title(ax2,'Sagittal'); colormap(ax2, gray);
    % coronal
    ax3 = nexttile; imagesc(squeeze(permute(A(:,round(end/2),:),[1 3 2]))'); axis(ax3,'image','off'); title(ax3,'Coronal'); colormap(ax3, gray);
    % 3D voxel count
    ax4 = nexttile; text(ax4,0.1,0.5,sprintf('voxels: %d',nnz(A)),'FontSize',12); axis(ax4,'off');
end

function vizIsoPreview(S, figName, panelName)
    % Quick isosurface preview
    figure('Name',sprintf('%s - %s',figName,panelName),'Color','w');
    p = patch(S); p.FaceColor=[0.8 0.85 0.95]; p.EdgeColor='none';
    daspect([1 1 1]); camlight headlight; lighting gouraud;
    axis vis3d off; title(panelName);
end

function vizMesh(TR, figName, panelName)
    % Mesh visualization with normals (sparse)
    figure('Name',sprintf('%s - %s',figName,panelName),'Color','w');
    if length(TR.ConnectivityList)>1e3
        trisurf(TR,'FaceColor',[0.85 0.9 0.95],'EdgeColor','none'); 
        axis equal off; camlight headlight; lighting gouraud; title(panelName);
    else
        trisurf(TR,'FaceColor',[0.85 0.9 0.95],'EdgeColor',[0.5 0.5 0.5]); 
        axis equal off; camlight headlight; lighting flat; title(panelName);
    end
end

function vizIsoWithPCA(A, vox2world, coeff, mu, th_pc3, figName, panelTitle)
% Visualize uncropped mask isosurface with PCA axes and PC3 crop plane.
% A        : logical 3D mask (uncropped)
% vox2world: 4x4 affine (voxel->world mm)
% coeff    : 3x3 PCA axes (columns), in world coords
% mu       : 1x3 PCA mean (world)
% th_pc3   : scalar threshold along PC3 (in PCA score units)
% figName  : figure base name
% panelTitle: title string

    % World grid for A
    [Xw,Yw,Zw] = worldGridForMask(A, vox2world);
    Smask = isosurface(Xw, Yw, Zw, imgaussfilt3(single(A),0.7), 0.5);
    if isempty(Smask.vertices), warning('vizIsoWithPCA: empty isosurface'); return; end

    % Bounding-box diag for arrow/plane scale
    bbMin = min(Smask.vertices,[],1);
    bbMax = max(Smask.vertices,[],1);
    d = norm(bbMax - bbMin);
    L = 0.25 * d;                 % arrow length
    pad = 0.6 * d;                % plane half-width

    % Build PC arrows (world)
    p1 = mu; v1 = coeff(:,1)'*L;
    p2 = mu; v2 = coeff(:,2)'*L;
    p3 = mu; v3 = coeff(:,3)'*L;

    % Plane at pc3 = th_pc3 (in world): point = mu + th*PC3_dir, spanning PC1/PC2
    P0 = mu + (th_pc3) * coeff(:,3)';      % plane point (world)
    e1 = coeff(:,1)'; e2 = coeff(:,2)';    % spanning directions
    quad = [ P0 - pad*e1 - pad*e2;
             P0 + pad*e1 - pad*e2;
             P0 + pad*e1 + pad*e2;
             P0 - pad*e1 + pad*e2 ];

    % Plot
    figure('Name',sprintf('%s - %s',figName,panelTitle), 'Color','w'); hold on;
    p = patch(Smask); p.FaceColor=[0.85 0.9 0.95]; p.EdgeColor='none'; p.FaceAlpha=0.9;

    % PCA arrows
    quiver3(p1(1),p1(2),p1(3), v1(1),v1(2),v1(3), 0, 'LineWidth',2, 'Color',[1 0 0]); % PC1
    quiver3(p2(1),p2(2),p2(3), v2(1),v2(2),v2(3), 0, 'LineWidth',2, 'Color',[0 0.7 0]); % PC2
    quiver3(p3(1),p3(2),p3(3), v3(1),v3(2),v3(3), 0, 'LineWidth',2, 'Color',[0 0 1]); % PC3

    % Crop plane
    patch('Vertices',quad, 'Faces',[1 2 3 4], 'FaceColor',[1 0 0], ...
          'FaceAlpha',0.15, 'EdgeColor',[0.6 0 0], 'LineStyle','-');

    % Labels
    text(p1(1)+v1(1), p1(2)+v1(2), p1(3)+v1(3), 'PC1','Color',[1 0 0],'FontWeight','bold');
    text(p2(1)+v2(1), p2(2)+v2(2), p2(3)+v2(3), 'PC2','Color',[0 0.7 0],'FontWeight','bold');
    text(p3(1)+v3(1), p3(2)+v3(2), p3(3)+v3(3), 'PC3','Color',[0 0 1],'FontWeight','bold');

    daspect([1 1 1]); axis vis3d off;
    camlight headlight; lighting gouraud;
    title(panelTitle);
    hold off;
end

function vizIsoWithAxis(A, vox2world, dir, mu, th_s, figName, panelTitle)
% Visualize mask isosurface with a world-space axis and the crop plane.
    [Xw,Yw,Zw] = worldGridForMask(A, vox2world);
    Smask = isosurface(Xw, Yw, Zw, imgaussfilt3(single(A),0.7), 0.5);
    if isempty(Smask.vertices), warning('vizIsoWithAxis: empty iso'); return; end

    bbMin = min(Smask.vertices,[],1); bbMax = max(Smask.vertices,[],1);
    d = norm(bbMax - bbMin);
    L = 0.25*d; pad = 0.6*d;

    p0 = mu(:)'; v  = (dir(:)'/norm(dir))*L;

    % plane point: p = mu + th*dir  (since s = (p - mu)·dir for PCA; here we used s = p·dir)
    % For user axis (s = p·dir), a consistent plane point is P0 = th*dir (shift so it passes near the cloud)
    % To keep it centered visually, anchor at mu projected onto plane:
    P0 = mu + (th_s - dot(mu,dir))*dir(:)';  % world point on plane
    % span two orthonormal vectors perpendicular to dir
    aux = [1;0;0]; if abs(dot(aux,dir))>0.9, aux=[0;1;0]; end
    e1 = cross(dir, aux); e1 = e1/norm(e1);
    e2 = cross(dir, e1);  e2 = e2/norm(e2);
    quad = [ P0 - pad*e1' - pad*e2';
             P0 + pad*e1' - pad*e2';
             P0 + pad*e1' + pad*e2';
             P0 - pad*e1' + pad*e2' ];

    figure('Name',sprintf('%s - %s',figName,panelTitle),'Color','w'); hold on;
    p = patch(Smask); p.FaceColor=[0.85 0.9 0.95]; p.EdgeColor='none'; p.FaceAlpha=0.9;

    quiver3(p0(1),p0(2),p0(3), v(1),v(2),v(3), 0, 'LineWidth',2, 'Color',[0 0 1]); % axis
    patch('Vertices',quad,'Faces',[1 2 3 4],'FaceColor',[1 0 0], ...
          'FaceAlpha',0.15,'EdgeColor',[0.6 0 0]);

    text(p0(1)+v(1), p0(2)+v(2), p0(3)+v(3), 'crop axis','Color',[0 0 1],'FontWeight','bold');
    daspect([1 1 1]); axis vis3d off; camlight headlight; lighting gouraud;
    title(panelTitle); hold off;
end

function [Vout, vox2world_out, R] = reorientVolume3D(Vin, vox2world_in, dir_world, interp)
% Rotate a 3-D volume so dir_world aligns with +Z in OUTPUT world.
% Vin: 3D array (logical or numeric). interp: 'nearest' | 'linear'.

    dir = dir_world(:); dir = dir / norm(dir + eps);
    ez  = [0;0;1];

    % Rodrigues rotation: R * dir = ez
    if norm(cross(dir, ez)) < 1e-12
        R = eye(3);
        if dot(dir,ez) < 0, R = diag([1 1 -1]); end  % 180° flip around XY
    else
        v = cross(dir, ez); c = dot(dir, ez); s = norm(v);
        vx = [  0   -v(3)  v(2);
               v(3)   0   -v(1);
              -v(2) v(1)   0  ];
        R = eye(3) + vx + vx*vx*((1-c)/(s^2));
    end

    % Compute output world bounds by rotating input-world corners with R
    sz = size(Vin);
    corners_ijk = [0 0 0;
                   sz(1)-1 0 0;
                   0 sz(2)-1 0;
                   0 0 sz(3)-1;
                   sz(1)-1 sz(2)-1 0;
                   sz(1)-1 0 sz(3)-1;
                   0 sz(2)-1 sz(3)-1;
                   sz(1)-1 sz(2)-1 sz(3)-1];
    Pin = vox2worldPts(corners_ijk, vox2world_in);      % input world corners
    Pout = (R * Pin.').';                               % rotate to output world

    xlim = [min(Pout(:,1)) max(Pout(:,1))];
    ylim = [min(Pout(:,2)) max(Pout(:,2))];
    zlim = [min(Pout(:,3)) max(Pout(:,3))];

    % Choose output voxel size ~ mean input voxel size (isotropic for simplicity)
    A = vox2world_in(1:3,1:3);
    inVoxSz = [norm(A(:,1)) norm(A(:,2)) norm(A(:,3))];
    voxSzOut = mean(inVoxSz);

    nx = max(1, round( (xlim(2)-xlim(1)) / voxSzOut ));
    ny = max(1, round( (ylim(2)-ylim(1)) / voxSzOut ));
    nz = max(1, round( (zlim(2)-zlim(1)) / voxSzOut ));

    % Resample onto the output world grid using the CORRECT pullback (R')
    Vout = worldResample3D(Vin, vox2world_in, [nx ny nz], xlim, ylim, zlim, R, interp);

    % Output affine corresponding to this regular output world grid
    vox2world_out = eye(4);
    vox2world_out(1:3,1:3) = diag([ (xlim(2)-xlim(1))/max(nx-1,1), ...
                                     (ylim(2)-ylim(1))/max(ny-1,1), ...
                                     (zlim(2)-zlim(1))/max(nz-1,1) ]);
    vox2world_out(1:3,4)   = [xlim(1); ylim(1); zlim(1)];
end

function Vout = worldResample3D(Vin, vox2world_in, outSize, xlim, ylim, zlim, R, interp)
% Sample Vin (defined by vox2world_in) on an OUTPUT world grid (xlim/ylim/zlim, outSize).
% R maps INPUT world -> OUTPUT world. Use R' to pull OUTPUT world -> INPUT world.

    nx = outSize(1); ny = outSize(2); nz = outSize(3);

    % Build OUTPUT world grid
    xs = linspace(xlim(1), xlim(2), nx);
    ys = linspace(ylim(1), ylim(2), ny);
    zs = linspace(zlim(1), zlim(2), nz);
    [Xw,Yw,Zw] = ndgrid(xs, ys, zs);                          % ndgrid order

    % Pull back each output world point to INPUT world: Pin = R' * Pout
    Pout = [Xw(:) Yw(:) Zw(:)];                               % N x 3
    Pin  = (R.' * Pout.').';                                  % N x 3

    % Convert INPUT world -> INPUT voxel (fractional indices)
    A = vox2world_in(1:3,1:3); t = vox2world_in(1:3,4).';     % world = i*A.' + t
    uvw = (Pin - t) / A.';                                    % row-wise solve
    I = reshape(uvw(:,1) + 1, size(Xw));                      % 1-based
    J = reshape(uvw(:,2) + 1, size(Xw));
    K = reshape(uvw(:,3) + 1, size(Xw));

    % Interpolate (careful: interp3 expects (Y,X,Z) order)
    if strcmpi(interp,'nearest')
        Vout = interp3(Vin, J, I, K, 'nearest', 0);
    else
        Vout = interp3(Vin, J, I, K, 'linear', 0);
    end
end

function vox2world = worldRefToAffine(R)
% Convert imref3d world limits to a 4x4 affine (diagonal scale + min corner).
    sx = (R.XWorldLimits(2)-R.XWorldLimits(1)) / max(R.ImageSize(1)-1,1);
    sy = (R.YWorldLimits(2)-R.YWorldLimits(1)) / max(R.ImageSize(2)-1,1);
    sz = (R.ZWorldLimits(2)-R.ZWorldLimits(1)) / max(R.ImageSize(3)-1,1);
    vox2world = eye(4);
    vox2world(1:3,1:3) = diag([sx sy sz]);
    vox2world(1:3,4)   = [R.XWorldLimits(1); R.YWorldLimits(1); R.ZWorldLimits(1)];
end

function [Aout, bbMin, bbMax] = cropAlongZDistance(Ain, vox2world, distance, side, marginMM)
% Keep the selected half-space along Z of the rotated volume.
    sz = size(Ain);
    [X,Y,Z] = ndgrid(0:sz(1)-1, 0:sz(2)-1, 0:sz(3)-1);
    Pw = vox2worldPts([X(:) Y(:) Z(:)], vox2world);
    zvals = Pw(:,3);
    if strcmpi(side,'top')
        keep = zvals >= distance;
    else
        keep = zvals <= distance;
    end
    keep = keep & Ain(:);
    if ~any(keep)
        error('Crop plane removed the entire head mask. Adjust cropDistance or cropSide.');
    end
    Pw_keep = Pw(keep, :);
    [bbMin, bbMax] = bboxWithMargin(Pw_keep, marginMM);
    Ahalf = false(size(Ain), 'like', Ain);
    Ahalf(keep) = Ain(keep);
    Aout = cropWorldMask(Ahalf, vox2world, bbMin, bbMax);
end

function [Aout, bbMin, bbMax] = cropAlongAxisDistance(Ain, vox2world, dir, distance, side, marginMM)
% Keep the selected world-space half-space without first rotating the mask.
    sz = size(Ain);
    [X,Y,Z] = ndgrid(0:sz(1)-1, 0:sz(2)-1, 0:sz(3)-1);
    Pw = vox2worldPts([X(:) Y(:) Z(:)], vox2world);
    projection = Pw * dir(:);
    if strcmpi(side,'top')
        keep = projection >= distance;
    else
        keep = projection <= distance;
    end
    keep = keep & Ain(:);
    if ~any(keep)
        error('Crop plane removed the entire head mask. Adjust cropDistance or cropSide.');
    end
    Pw_keep = Pw(keep, :);
    [bbMin, bbMax] = bboxWithMargin(Pw_keep, marginMM);
    Ahalf = false(size(Ain), 'like', Ain);
    Ahalf(keep) = Ain(keep);
    Aout = cropWorldMask(Ahalf, vox2world, bbMin, bbMax);
end

function Afilled = fillHollow3D(A)
%FILLHOLLOW3D  Fill interior cavities in a 3-D binary volume.
%   Afilled = fillHollow3D(A)
% Fills holes that are enclosed in 3D (not just per-slice).
%
% Method:
%   - Take the complement (~A).
%   - Label connected components (6-connectivity).
%   - Any component touching the boundary is "outside air".
%   - Everything else is interior cavity → mark solid.

    validateattributes(A, {'logical','numeric'}, {'nonsparse','real'});
    A = logical(A);
    sz = size(A);
    if numel(sz) ~= 3
        error('fillHollow3D expects a 3-D array.');
    end

    % Complement volume
    B = ~A;

    % Build mask of all boundary voxels
    boundary = false(sz);
    boundary(1,:,:)   = true;
    boundary(end,:,:) = true;
    boundary(:,1,:)   = true;
    boundary(:,end,:) = true;
    boundary(:,:,1)   = true;
    boundary(:,:,end) = true;

    % Connected components in complement
    CC = bwconncomp(B, 6);

    % Mark exterior air (components touching boundary)
    exterior = false(numel(A),1);
    for i = 1:CC.NumObjects
        idx = CC.PixelIdxList{i};
        if any(boundary(idx))
            exterior(idx) = true;
        end
    end

    % Fill: interior cavities = ~exterior
    Afilled = ~reshape(exterior, sz);
end

function B = imdilateN(A,se,n)
%IMDILATEN  Apply 3D dilation n times with structuring element se.
%   B = imdilateN(A,se,n)
% A : logical/numeric 3D volume
% se: logical 3D structuring element (e.g., true(3,3,3))
% n : number of iterations (default = 1)

    if nargin < 3, n = 1; end
    B = logical(A);
    for k = 1:n
        B = imdilate(B, se);
    end
end

function B = imerodeN(A,se,n)
%IMERODEN  Apply 3D erosion n times with structuring element se.
%   B = imerodeN(A,se,n)
% A : logical/numeric 3D volume
% se: logical 3D structuring element (e.g., true(3,3,3))
% n : number of iterations (default = 1)

    if nargin < 3, n = 1; end
    B = logical(A);
    for k = 1:n
        B = imerode(B, se);
    end
end
