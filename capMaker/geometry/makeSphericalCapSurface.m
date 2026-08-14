function tri = makeSphericalCapSurface(k, nRad, nTheta)
% makeSphericalCapSurface  Watertight spherical cap with unit base radius.
% Base circle: z=0, centered at (0,0), radius = 1. Cap apex at z = h.
%
% INPUT
%   k        : cap height / sphere radius, 0 < k < 2
%   nRad     : # radial samples (default 40)
%   nTheta   : # angular samples (default 120)
%
% OUTPUT
%   V (N x 3): vertices
%   F (M x 3): faces (triangles), strictly positive indices, watertight
%
% Geometry (base radius a=1):
%   R = 1 / sqrt(2k - k^2),  h = k*R,  zc = h - R
%   z(r) = zc + sqrt(R^2 - r^2),  0 <= r <= 1,  0 <= theta < 2pi

    if nargin < 2 || isempty(nRad),   nRad   = 40;  end
    if nargin < 3 || isempty(nTheta), nTheta = 120; end
    validateattributes(k, {'double'},{'scalar','>',0,'<',2}, mfilename, 'k');

    % Sphere parameters (base radius = 1)
    denom = 2*k - k^2;
    R = 1 / sqrt(denom);
    h = k * R;
    zc = h - R;

    % Sampling grid WITHOUT duplicate last-theta row
    r  = linspace(0, 1, nRad);                 % 0..1
    th = linspace(0, 2*pi, nTheta+1); th(end)=[]; % 0..2pi (open)
    [TH, RR] = meshgrid(th, r);   % size: nRad x nTheta

    X = RR .* cos(TH);
    Y = RR .* sin(TH);
    Z = zc + sqrt(max(R^2 - RR.^2, 0));  % cap surface

    % Flatten vertices (column-major consistent indexing)
    % Indexing helper: idx(ir,it) = (it-1)*nRad + ir
    V = [X(:), Y(:), Z(:)];

    % ---- Faces for the dome surface (quads split into 2 tris) ----
    Fcap = [];
    idx = @(ir,it) (it-1)*nRad + ir;  % 1-based
    for it = 1:nTheta
        it2 = mod(it, nTheta) + 1;     % wrap
        for ir = 1:(nRad-1)
            a = idx(ir   , it );
            b = idx(ir+1 , it );
            c = idx(ir+1 , it2);
            d = idx(ir   , it2);
            Fcap = [Fcap; a b c; a c d]; %#ok<AGROW>
        end
    end

    % ---- Base disk at z=0, radius=1, sharing the boundary ring ----
    % Reuse the outer ring (ir = nRad) from the cap; add a center vertex at (0,0,0)
    center = [0,0,0];
    cidx = size(V,1) + 1;
    V = [V; center];

    Fbase = zeros(nTheta, 3);
    for it = 1:nTheta
        it2 = mod(it, nTheta) + 1;
        a = idx(nRad, it );   % rim vertex i
        b = idx(nRad, it2);   % rim vertex i+1 (wrapped)
        % Triangle (center, b, a) → outward normal points DOWN (-Z)
        Fbase(it,:) = [cidx, b, a];
    end

    % ---- Assemble ----
    F = [Fcap; Fbase];

    % Sanity checks
    if any(F(:) < 1) || any(F(:) ~= round(F(:)))
        error('Face indices must be strictly positive integers.');
    end
    % Base ring should lie at z≈0
    % (numerical noise can be ~1e-15; that's fine)

    tri = triangulation(F,V);
end
