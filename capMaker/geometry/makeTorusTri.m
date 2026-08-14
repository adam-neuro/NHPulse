function TR = makeTorusTri(varargin)
% MAKETORUSTRI  Watertight triangulation of a torus (O-ring).
%
% TR = makeTorusTri()                          % default: center=[0 0 0], axis=[0 0 1],
%                                              % outerDia=10 mm, tubeDia=3 mm, 64x32 facets
% TR = makeTorusTri(center, axis, outerDia, tubeDia, nTheta, nPhi)
%
% Inputs (all optional; positional):
%   center   : 1x3, torus center (default [0 0 0])
%   axis     : 1x3, torus symmetry axis (default [0 0 1])
%   outerDia : scalar, outer diameter in mm (default 10)
%   tubeDia  : scalar, tube (minor) diameter in mm (default 3)
%   nTheta   : integer, samples around major circle (default 64)
%   nPhi     : integer, samples around tube cross-section (default 32)
%
% Output:
%   TR : triangulation object (watertight)
%
% Example:
%   TR = makeTorusTri([30 0 0], [1 0 0], 20, 4, 96, 40);
%   trisurf(TR,'EdgeColor','none'); axis equal; camlight; lighting gouraud;

% ---- parse inputs & defaults ----
center   = argOr(varargin,1,[0 0 0]);
axisVec  = argOr(varargin,2,[0 0 1]);
outerDia = argOr(varargin,3,10);
tubeDia  = argOr(varargin,4,2);
nTheta   = argOr(varargin,5,64);
nPhi     = argOr(varargin,6,32);

axisVec = axisVec(:)'; 
anorm   = norm(axisVec);
if anorm < 1e-12, axisVec = [0 0 1]; else, axisVec = axisVec / anorm; end

R = max( (outerDia - tubeDia)/2,  eps );     % major radius (to tube centerline)
r = max(  tubeDia/2,              1e-6 );    % minor radius

nTheta = max(3, round(nTheta));
nPhi   = max(3, round(nPhi));

% ---- build torus in canonical frame (axis = +Z) ----
theta = linspace(0, 2*pi, nTheta+1); theta(end) = [];
phi   = linspace(0, 2*pi, nPhi+1);   phi(end)   = [];
[TT, PP] = meshgrid(theta, phi);     % PP: rows, TT: cols

X = (R + r.*cos(PP)) .* cos(TT);
Y = (R + r.*cos(PP)) .* sin(TT);
Z =  r .* sin(PP);

V = [X(:), Y(:), Z(:)];

% ---- rotate to desired axis (Rodrigues: from [0 0 1] to axisVec) ----
zref = [0 0 1];
if norm(cross(zref, axisVec)) < 1e-12
    if dot(zref, axisVec) > 0
        Rmat = eye(3);
    else
        % 180° about any axis orthogonal to z
        Rmat = [-1 0 0; 0 -1 0; 0 0 1];
    end
else
    k = cross(zref, axisVec); k = k / norm(k);
    ang = acos( max(-1,min(1, dot(zref, axisVec))) );
    K = [   0   -k(3)  k(2);
          k(3)   0   -k(1);
         -k(2)  k(1)   0  ];
    Rmat = eye(3) + sin(ang)*K + (1-cos(ang))*(K*K);
end
V = (Rmat * V.').';
V = V + center;

% ---- build watertight faces (wrap in both directions) ----
F = zeros(2*nPhi*nTheta, 3);
idx = @(i,j) (mod(i-1,nPhi)  )*nTheta + mod(j-1,nTheta) + 1; % 1-based wrap
t = 1;
for i = 1:nPhi
    i2 = i+1;
    for j = 1:nTheta
        j2 = j+1;
        a = idx(i , j );
        b = idx(i , j2);
        c = idx(i2, j2);
        d = idx(i2, j );
        F(t,:)   = [a b c]; t = t+1;
        F(t,:)   = [a c d]; t = t+1;
    end
end

TR = triangulation(F, V);
end

% ---- helper: positional argument or default ----
function v = argOr(args, k, def)
if numel(args) >= k && ~isempty(args{k})
    v = args{k};
else
    v = def;
end
end
