function [TRout, occOut] = carvePVA(baseIn, subtractIn, opts)
% carvePVA  Voxel Boolean difference, base \ subtract.
%
% Historical note: this function began as a mesh-minus-mesh helper. It now
% accepts either side as a triangulation or as an occupancy struct so callers
% can keep voxel-native geometry voxel-native until final STL export.
%
% Usage:
%   [TR, occ] = carvePVA(baseMesh, subtractMesh, opts)
%   [TR, occ] = carvePVA(baseOcc,  subtractMesh, opts)
%   [TR, occ] = carvePVA(baseMesh, subtractOcc,  opts)
%   [TR, occ] = carvePVA(baseOcc,  subtractOcc,  opts)
%
% Occupancy struct convention:
%   .x, .y, .z : row/column vectors defining an ndgrid lattice
%   .occ       : logical/numeric [numel(x) numel(y) numel(z)]
%   .vx        : optional voxel size
%   .zBed      : optional printer-bed plane
%
% Options:
%   voxelSize    : mm/voxel for mesh-only grid creation
%   padVox       : padding voxels for mesh-only grid creation [8]
%   isoLevel     : isosurface level [0.5]
%   closeVox     : post-subtract morphological close radius [1; set 0 for straps]
%   clearanceMM  : dilate subtract occupancy before subtraction [0]
%   keepLargest  : keep largest component only [false]
%   tol          : inpolyhedron tolerance [1e-9]
%   baseOcc      : legacy override for baseIn
%   tpeOcc       : legacy override for subtractIn
%   returnMesh   : convert carved occupancy to triangulation [true]
%   allowPermute : opt-in legacy [ny nx nz] tolerance [false]
%   assertSingleComponent : error if carved volume has >1 component [false]

    if nargin < 3
        opts = struct();
    end
    if isfield(opts, 'baseOcc') && ~isempty(opts.baseOcc)
        baseIn = opts.baseOcc;
    end
    if isfield(opts, 'tpeOcc') && ~isempty(opts.tpeOcc)
        subtractIn = opts.tpeOcc;
    end

    iso = getop(opts, 'isoLevel', 0.5);
    cv = max(0, round(getop(opts, 'closeVox', 1)));
    clr = max(0, getop(opts, 'clearanceMM', 0));
    tol = getop(opts, 'tol', 1e-9);
    keepLargest = getop(opts, 'keepLargest', false);
    allowPermute = getop(opts, 'allowPermute', false);
    assertSingle = getop(opts, 'assertSingleComponent', false);
    returnMesh = getop(opts, 'returnMesh', true);
    trimUncoveredPerimeter = getop(opts, 'trimUncoveredPerimeter', false);
    coverPadMM = max(0, getop(opts, 'coverPadMM', 2.0));

    [x, y, z, vx, zBed] = chooseCarveGrid(baseIn, subtractIn, opts);
    occBase = occupancyOnGrid(baseIn, x, y, z, iso, tol, allowPermute, 'baseIn');
    occSubtract = occupancyOnGrid(subtractIn, x, y, z, iso, tol, ...
        allowPermute, 'subtractIn');

    if clr > 0
        nDil = max(1, round(clr / vx));
        occSubtract = imdilateN(occSubtract, true(3, 3, 3), nDil);
    end

    occ = logical(occBase) & ~logical(occSubtract);

    if trimUncoveredPerimeter
        coverXY = any(occSubtract, 3);
        if coverPadMM > 0
            nDilXY = max(1, round(coverPadMM / vx));
            coverXY = imdilate2(coverXY, nDilXY);
        end
        occ = occ & repmat(coverXY, [1, 1, size(occ, 3)]);
        if ~any(occ(:))
            error('carvePVA:PerimeterTrimEmpty', ...
                'Perimeter trim removed all material. Reduce coverPadMM or disable trimUncoveredPerimeter.');
        end
    end

    % Keep an explicit outside region on the lateral/top bounds. The bottom
    % plane is allowed to contain material so printer-bed support remains flat.
    occ(1,:,:) = false;
    occ(end,:,:) = false;
    occ(:,1,:) = false;
    occ(:,end,:) = false;
    occ(:,:,end) = false;

    if cv > 0
        occ = imdilateN(occ, true(3, 3, 3), cv);
        occ = imerodeN(occ, true(3, 3, 3), cv);
    end

    if keepLargest
        occ = keepLargest3D(occ);
    end

    CC = bwconncomp(occ, 26);
    if CC.NumObjects > 1
        warning('carvePVA:multiComponent', ...
            'Carved volume has %d components (no pruning applied).', ...
            CC.NumObjects);
    end
    if assertSingle
        assert(CC.NumObjects <= 1, ...
            'Carved volume contains %d components.', CC.NumObjects);
    end

    occOut = struct('x', x, 'y', y, 'z', z, 'occ', logical(occ), ...
        'vx', vx, 'zBed', zBed);

    TRout = [];
    if returnMesh
        [TRout, occAligned] = triFromOccHelper(x, y, z, occOut.occ, iso, ...
            struct('allowPermute', allowPermute));
        occOut.occ = logical(occAligned);
        if exist('remove_unreferenced', 'file') == 2 && ~isempty(TRout)
            [V2, F2] = remove_unreferenced(TRout.Points, TRout.ConnectivityList);
            TRout = triangulation(F2, V2);
        end
    end
end

function [x, y, z, vx, zBed] = chooseCarveGrid(baseIn, subtractIn, opts)
    if isOccStruct(baseIn) || isOccStruct(subtractIn)
        [x0, y0, z0, vx, zBed] = firstOccGrid(baseIn, subtractIn, opts);
        [bbMin, bbMax] = inputBounds(baseIn, subtractIn);
        if any(~isfinite(bbMin)) || any(~isfinite(bbMax))
            error('carvePVA:EmptyInputs', ...
                'At least one input must contain mesh vertices or occupancy voxels.');
        end
        x = extendAxisToBounds(x0, bbMin(1), bbMax(1), vx);
        y = extendAxisToBounds(y0, bbMin(2), bbMax(2), vx);
        z = extendAxisToBounds(z0, bbMin(3), bbMax(3), vx);
        return;
    end

    P = [pointsFromInput(baseIn); pointsFromInput(subtractIn)];
    P = P(all(isfinite(P), 2), :);
    if isempty(P)
        error('carvePVA:EmptyInputs', ...
            'At least one input must contain mesh vertices or occupancy voxels.');
    end

    bbMin = min(P, [], 1);
    bbMax = max(P, [], 1);
    bboxDiag = norm(bbMax - bbMin);
    vx = double(getop(opts, 'voxelSize', max(bboxDiag / 250, 0.05)));
    padVox = max(1, round(getop(opts, 'padVox', 8)));
    zBed = double(getop(opts, 'zBed', 0));
    pad = (padVox + 1) * vx;
    x = (bbMin(1) - pad):vx:(bbMax(1) + pad);
    y = (bbMin(2) - pad):vx:(bbMax(2) + pad);
    zMin = bbMin(3) - pad;
    zMax = bbMax(3) + pad;
    k0 = ceil((zBed - zMin) / vx);
    z0 = zMin + k0 * vx;
    z = z0:vx:zMax;
end

function [x, y, z, vx, zBed] = firstOccGrid(baseIn, subtractIn, opts)
    if isOccStruct(baseIn)
        [x, y, z, vx, zBed] = gridFromOcc(baseIn, opts);
    else
        [x, y, z, vx, zBed] = gridFromOcc(subtractIn, opts);
    end
end

function [x, y, z, vx, zBed] = gridFromOcc(occIn, opts)
    x = double(occIn.x(:).');
    y = double(occIn.y(:).');
    z = double(occIn.z(:).');
    if isfield(occIn, 'vx') && ~isempty(occIn.vx) && ...
            isscalar(occIn.vx) && isfinite(occIn.vx)
        vx = double(occIn.vx);
    elseif numel(x) >= 2
        vx = abs(x(2) - x(1));
    else
        vx = double(getop(opts, 'voxelSize', 0.5));
    end
    if isfield(occIn, 'zBed') && ~isempty(occIn.zBed) && ...
            isscalar(occIn.zBed) && isfinite(occIn.zBed)
        zBed = double(occIn.zBed);
    else
        zBed = double(getop(opts, 'zBed', 0));
    end
end

function occ = occupancyOnGrid(value, x, y, z, iso, tol, allowPermute, name)
    if isemptyGeometry(value)
        occ = false(numel(x), numel(y), numel(z));
        return;
    end
    if isOccStruct(value)
        occValue = occStructOnGrid(value, x, y, z, name);
        [~, occ] = triFromOccHelper(x, y, z, occValue, iso, struct( ...
            'allowPermute', allowPermute, ...
            'validateOnly', true));
        occ = logical(occ);
        return;
    end
    if isa(value, 'triangulation')
        occ = occFromInpolyhedron(value, x, y, z, tol, allowPermute);
        return;
    end
    error('carvePVA:BadInput', ...
        '%s must be a triangulation or occupancy struct.', name);
end

function occ = occStructOnGrid(occIn, x, y, z, name)
    x0 = double(occIn.x(:).');
    y0 = double(occIn.y(:).');
    z0 = double(occIn.z(:).');
    validateOccSize(occIn.occ, x0, y0, z0, name);
    if axesEqual(x0, x) && axesEqual(y0, y) && axesEqual(z0, z)
        occ = logical(occIn.occ);
        return;
    end
    ix = axisSubsetIndices(x0, x, name, 'x');
    iy = axisSubsetIndices(y0, y, name, 'y');
    iz = axisSubsetIndices(z0, z, name, 'z');
    occ = false(numel(x), numel(y), numel(z));
    occ(ix, iy, iz) = logical(occIn.occ);
end

function validateOccSize(occ, x, y, z, name)
    if ~isequal(size(occ), [numel(x) numel(y) numel(z)])
        error('carvePVA:GridMismatch', ...
            '%s occupancy must be [%d %d %d]; got [%s].', ...
            name, numel(x), numel(y), numel(z), mat2str(size(occ)));
    end
end

function tf = axesEqual(a, b)
    tf = numel(a) == numel(b) && all(abs(a - b) <= 1e-9);
end

function idx = axisSubsetIndices(srcAxis, dstAxis, name, dimName)
    if isempty(srcAxis)
        idx = [];
        return;
    end
    if numel(dstAxis) < numel(srcAxis)
        error('carvePVA:GridMismatch', ...
            '%s %s grid cannot fit into selected carve grid.', name, dimName);
    end
    if numel(dstAxis) >= 2
        vx = median(diff(dstAxis));
    elseif numel(srcAxis) >= 2
        vx = median(diff(srcAxis));
    else
        vx = 1;
    end
    if abs(vx) < eps
        error('carvePVA:GridMismatch', ...
            '%s %s grid has zero spacing.', name, dimName);
    end
    firstIdx = round((srcAxis(1) - dstAxis(1)) / vx) + 1;
    idx = firstIdx:(firstIdx + numel(srcAxis) - 1);
    if firstIdx < 1 || idx(end) > numel(dstAxis) || ...
            any(abs(dstAxis(idx) - srcAxis) > max(1e-8, abs(vx) * 1e-6))
        error('carvePVA:GridMismatch', ...
            '%s %s occupancy grid is not aligned with the selected carve grid.', ...
            name, dimName);
    end
end

function axisOut = extendAxisToBounds(axisIn, minVal, maxVal, vx)
    axisIn = double(axisIn(:).');
    if isempty(axisIn)
        error('carvePVA:EmptyAxis', ...
            'Occupancy axes must contain at least one coordinate.');
    end
    if ~isfinite(minVal) || ~isfinite(maxVal)
        axisOut = axisIn;
        return;
    end
    nBefore = max(0, ceil((axisIn(1) - minVal) / vx));
    nAfter = max(0, ceil((maxVal - axisIn(end)) / vx));
    offsets = -nBefore:(numel(axisIn) + nAfter - 1);
    axisOut = axisIn(1) + offsets .* vx;
end

function [bbMin, bbMax] = inputBounds(baseIn, subtractIn)
    [bMin, bMax] = boundsForInput(baseIn);
    [sMin, sMax] = boundsForInput(subtractIn);
    bbMin = min([bMin; sMin], [], 1);
    bbMax = max([bMax; sMax], [], 1);
end

function [bbMin, bbMax] = boundsForInput(value)
    if isOccStruct(value)
        x = double(value.x(:));
        y = double(value.y(:));
        z = double(value.z(:));
        bbMin = [min(x) min(y) min(z)];
        bbMax = [max(x) max(y) max(z)];
    else
        P = pointsFromInput(value);
        P = P(all(isfinite(P), 2), :);
        if isempty(P)
            bbMin = [Inf Inf Inf];
            bbMax = [-Inf -Inf -Inf];
        else
            bbMin = min(P, [], 1);
            bbMax = max(P, [], 1);
        end
    end
end

function tf = isOccStruct(value)
    tf = isstruct(value) && isfield(value, 'x') && isfield(value, 'y') && ...
        isfield(value, 'z') && isfield(value, 'occ');
end

function tf = isemptyGeometry(value)
    if isempty(value)
        tf = true;
    elseif isa(value, 'triangulation')
        tf = isempty(value.Points) || isempty(value.ConnectivityList);
    elseif isOccStruct(value)
        tf = isempty(value.occ) || ~any(value.occ(:));
    else
        tf = false;
    end
end

function P = pointsFromInput(value)
    if isempty(value)
        P = zeros(0, 3);
    elseif isa(value, 'triangulation')
        P = double(value.Points);
    elseif isOccStruct(value)
        [ii, jj, kk] = ind2sub(size(value.occ), find(value.occ));
        if isempty(ii)
            P = zeros(0, 3);
        else
            x = double(value.x(:));
            y = double(value.y(:));
            z = double(value.z(:));
            P = [x(ii), y(jj), z(kk)];
        end
    else
        P = zeros(0, 3);
    end
end

function occ = occFromInpolyhedron(TR, x, y, z, tol, allowPermute)
    F = TR.ConnectivityList;
    V = TR.Points;
    Nf = faceNormals(F, V);
    [X, Y, Z] = ndgrid(x, y, z);
    occRaw = reshape(inpolyhedron(F, V, [X(:) Y(:) Z(:)], ...
        'facenormals', Nf, 'tol', tol), size(X));
    assert(isequal(size(occRaw), size(X)), ...
        'occFromInpolyhedron: size mismatch (got %s, expected %s)', ...
        mat2str(size(occRaw)), mat2str(size(X)));
    [~, occ] = triFromOccHelper(x, y, z, occRaw, 0.5, struct( ...
        'allowPermute', allowPermute, ...
        'validateOnly', true));
    occ = logical(occ);
end

function Nf = faceNormals(F, V)
    a = V(F(:,1),:);
    b = V(F(:,2),:);
    c = V(F(:,3),:);
    Nf = cross(b - a, c - a);
    n = vecnorm(Nf, 2, 2);
    n(n == 0) = 1;
    Nf = Nf ./ n;
end

function B = imdilateN(A, se, n)
    B = logical(A);
    ker = double(se);
    for i = 1:n
        B = convn(double(B), ker, 'same') > 0;
    end
end

function B = imerodeN(A, se, n)
    B = logical(A);
    ker = double(se);
    tsum = sum(ker(:));
    for i = 1:n
        B = convn(double(B), ker, 'same') >= tsum;
    end
end

function A = keepLargest3D(A)
    CC = bwconncomp(A, 26);
    if CC.NumObjects > 0
        [~, k] = max(cellfun(@numel, CC.PixelIdxList));
        B = false(size(A));
        B(CC.PixelIdxList{k}) = true;
        A = B;
    end
end

function B = imdilate2(A, n)
    B = logical(A);
    ker = ones(3, 3);
    for i = 1:n
        B = conv2(double(B), ker, 'same') > 0;
    end
end

function val = getop(s, f, def)
    if isstruct(s) && isfield(s, f) && ~isempty(s.(f))
        val = s.(f);
    else
        val = def;
    end
end
