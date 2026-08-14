function TR = makeTetraKeepout(holeTop, holeBottom, baseRadius, varargin)
% MAKE TETRAHEDRAL KEEP-OUT VOLUME ALIGNED TO A HOLE AXIS
%   TR = makeTetraKeepout(holeTop, holeBottom, baseRadius, ...
%                         'ApexInset', 0.3, 'Flare', 1.6)
%
% Inputs (all in your model units, e.g., mm):
%   holeTop    [3x1] world coords of the hole's top center (electrode entry)
%   holeBottom [3x1] world coords of the hole's bottom center (cap inner face)
%   baseRadius scalar, radius of bottom triangle (usually >= insideDia/2)
%
% Key params:
%   ApexInset  how far the apex is pulled *into* the hole from holeTop (mm)
%   Flare      multiplier on baseRadius to widen the triangular base

p = inputParser;
p.addParameter('ApexInset', 0);   % small inset to ensure clean subtraction at the top
p.addParameter('BaseInset', 3);   % small inset to ensure clean subtraction at the top
p.addParameter('Flare',     1.6);   % base flare factor; increase if rails encroach
p.parse(varargin{:});
apexInset = p.Results.ApexInset;
baseInset = p.Results.BaseInset;
flare     = p.Results.Flare;

% Axis
u = holeTop(:) - holeBottom(:);
L = norm(u);
if L < 1e-9
    error('holeTop and holeBottom are nearly identical.');
end
u = u / L;

% Apex slightly inside the hole (toward bottom) to guarantee a clean cut at the top
apex = holeTop(:) - apexInset * u;

% Base center a hair *below* holeBottom to chew through any voxel fill
baseCenter = holeBottom(:) - baseInset * u;

% Orthonormal basis spanning the base plane
if abs(u(1)) < 0.9
    t = [1;0;0];
else
    t = [0;1;0];
end
v = cross(u, t); v = v / norm(v);
w = cross(u, v); % already unit-length if u,v are

% Base triangle vertices (120° around base circle), flared as requested
r = flare * baseRadius;
ang = [0, 2*pi/3, 4*pi/3];
B = zeros(3,3);
for k = 1:3
    B(:,k) = baseCenter + r*cos(ang(k))*v + r*sin(ang(k))*w;
end

% Assemble vertices (apex first for consistent winding)
V = [apex.'; B.'];

% Tetra faces (outward if base triangle is wound CCW in (v,w) frame)
F = [ 1 2 3
      1 3 4
      1 4 2
      2 3 4 ];

TR = triangulation(F, V);

% Optional: unify outward normals if your downstream expects it
TR = unifyOutwardNormals(TR);
end
