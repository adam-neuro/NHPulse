function TRlist = makeHoleClearingFrusta(holeTops, holeBottoms, insideDia, varargin)
% makeHoleClearingFrusta  Build flared, capped keepouts for electrode holes.
%
% The cutter is cylindrical through the holder bore, then flares wider past
% the scalp-facing side. This leaves a clean electrode opening plus a small
% gel pocket at the scalp.

p = inputParser;
p.FunctionName = 'makeHoleClearingFrusta';
addParameter(p, 'ClearanceMm', 0.5, @isNonnegativeScalar);
addParameter(p, 'BoreClearanceMm', 0.1, @isNonnegativeScalar);
addParameter(p, 'ScalpClearanceMm', [], @(x) isempty(x) || isNonnegativeScalar(x));
addParameter(p, 'TopExtendMm', 1.5, @isNonnegativeScalar);
addParameter(p, 'ScalpExtendMm', 6, @isNonnegativeScalar);
addParameter(p, 'ScalpFlareDiaMm', [], @(x) isempty(x) || isPositiveScalar(x));
addParameter(p, 'NumSides', 32, @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x >= 8);
parse(p, varargin{:});

holeTops = double(holeTops);
holeBottoms = double(holeBottoms);
if size(holeTops, 2) ~= 3 || size(holeBottoms, 2) ~= 3 || ...
        size(holeTops, 1) ~= size(holeBottoms, 1)
    error('makeHoleClearingFrusta:BadInput', ...
        'holeTops and holeBottoms must be matching N x 3 matrices.');
end

n = size(holeTops, 1);
insideDia = double(insideDia);
if isscalar(insideDia)
    insideDia = repmat(insideDia, n, 1);
else
    insideDia = insideDia(:);
end
if numel(insideDia) ~= n || any(~isfinite(insideDia)) || any(insideDia <= 0)
    error('makeHoleClearingFrusta:BadDiameter', ...
        'insideDia must be a positive scalar or N-element vector.');
end

boreClearanceMm = double(p.Results.BoreClearanceMm);
if isempty(p.Results.ScalpClearanceMm)
    scalpClearanceMm = double(p.Results.ClearanceMm);
else
    scalpClearanceMm = double(p.Results.ScalpClearanceMm);
end
topExtendMm = double(p.Results.TopExtendMm);
scalpExtendMm = double(p.Results.ScalpExtendMm);
numSides = round(double(p.Results.NumSides));

scalpFlareDia = p.Results.ScalpFlareDiaMm;
if isempty(scalpFlareDia)
    scalpFlareDia = max(insideDia + 2, 6);
elseif isscalar(scalpFlareDia)
    scalpFlareDia = repmat(double(scalpFlareDia), n, 1);
else
    scalpFlareDia = double(scalpFlareDia(:));
end
if numel(scalpFlareDia) ~= n || any(~isfinite(scalpFlareDia)) || ...
        any(scalpFlareDia <= 0)
    error('makeHoleClearingFrusta:BadFlareDiameter', ...
        'ScalpFlareDiaMm must be empty, a positive scalar, or N-element vector.');
end

TRlist = cell(n, 1);
theta = linspace(0, 2*pi, numSides + 1);
theta(end) = [];
for i = 1:n
    top = holeTops(i, :);
    bottom = holeBottoms(i, :);
    u = top - bottom;
    len = norm(u);
    if len < 1e-9
        error('makeHoleClearingFrusta:DegenerateAxis', ...
            'Hole %d top and bottom are nearly identical.', i);
    end
    u = u ./ len;
    [v, w] = transverseBasis(u);

    boreRadius = 0.5 * insideDia(i) + boreClearanceMm;
    scalpRadius = max(boreRadius, 0.5 * scalpFlareDia(i) + scalpClearanceMm);

    centers = [
        top + topExtendMm * u
        bottom
        bottom - scalpExtendMm * u
        ];
    radii = [boreRadius; boreRadius; scalpRadius];

    [F, V] = cappedRingMesh(centers, radii, v, w, theta);
    TR = triangulation(F, V);
    if exist('unifyOutwardNormalsRobust', 'file') == 2
        TR = unifyOutwardNormalsRobust(TR);
    elseif exist('unifyOutwardNormals', 'file') == 2
        TR = unifyOutwardNormals(TR);
    end
    TRlist{i} = TR;
end
end

function [F, V] = cappedRingMesh(centers, radii, v, w, theta)
nRings = size(centers, 1);
nSides = numel(theta);
V = zeros(nRings * nSides + 2, 3);
for r = 1:nRings
    rows = (r - 1) * nSides + (1:nSides);
    V(rows, :) = centers(r, :) + ...
        radii(r) * cos(theta(:)) * v + ...
        radii(r) * sin(theta(:)) * w;
end

topCenter = nRings * nSides + 1;
bottomCenter = topCenter + 1;
V(topCenter, :) = centers(1, :);
V(bottomCenter, :) = centers(end, :);

F = zeros((nRings - 1) * nSides * 2 + nSides * 2, 3);
f = 0;
for r = 1:(nRings - 1)
    a0 = (r - 1) * nSides;
    b0 = r * nSides;
    for k = 1:nSides
        kn = 1 + mod(k, nSides);
        f = f + 1;
        F(f, :) = [a0 + k, a0 + kn, b0 + kn];
        f = f + 1;
        F(f, :) = [a0 + k, b0 + kn, b0 + k];
    end
end

for k = 1:nSides
    kn = 1 + mod(k, nSides);
    f = f + 1;
    F(f, :) = [topCenter, kn, k];
end

bottom0 = (nRings - 1) * nSides;
for k = 1:nSides
    kn = 1 + mod(k, nSides);
    f = f + 1;
    F(f, :) = [bottomCenter, bottom0 + k, bottom0 + kn];
end
end

function [v, w] = transverseBasis(u)
u = u(:).';
if abs(dot(u, [0 0 1])) < 0.9
    ref = [0 0 1];
else
    ref = [1 0 0];
end
v = cross(u, ref);
v = v ./ norm(v);
w = cross(u, v);
w = w ./ norm(w);
end

function tf = isPositiveScalar(x)
tf = isnumeric(x) && isscalar(x) && isfinite(x) && x > 0;
end

function tf = isNonnegativeScalar(x)
tf = isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0;
end
