function TRstrap = makeAccordionStrapWithRings(Pleft, Pright, opts)
% MAKEACCORDIONSTRAPWITHRINGS
% Two flexible (accordion) straps on the bed, each with a short angled “ramp”
% up toward the cap, plus a smooth O-ring at the free end.
%
% Usage:
%   TRstrap = makeAccordionStrapWithRings(Pleft, Pright, opts)
%   % Pleft/Pright are 1x3 roots on the bed plane (Z==zBed), e.g. [-60 0 0], [60 0 0]
%
% Key options (all optional):
%   .zBed = 0
%   .strapAheadMM   = 25     % +Y nudge of both roots
%   .strapWidthMM   = 20
%   .strapThickMM   = 2.4
%   .bedLenMM       = 40     % length of the bed portion (from root outward ±X)
%   .rampLenMM      = 20     % length of the angled up portion
%   .rampAngleDeg   = 80     % steepness of the ramp
%   .overlapMM      = 0.6    % small longitudinal overlap where ramp meets bed
%
%   % Accordion (meander) parameters (applied ONLY to strap, not ring)
%   .corrAmpMM      = 3.0    % lateral meander amplitude (Y)
%   .corrPitchMM    = 8.0    % meander pitch along strap length
%
%   % O-ring geometry (smooth; no accordion)
%   .ringOuterDiaMM = 20
%   .ringTubeDiaMM  = 3.5
%   .ringNeckLenMM  = 8
%   .ringThetaN     = 48
%   .ringPhiN       = 20
%
% Output:
%   TRstrap : triangulation of both straps (left/right) including ramp and rings.

C.zBed       = g(opts,'zBed',0);
C.ahead      = g(opts,'strapAheadMM',25);
C.W          = g(opts,'strapWidthMM',20);
C.T          = g(opts,'strapThickMM',2.4);
C.Lbed       = g(opts,'bedLenMM',40);
C.Lramp      = g(opts,'rampLenMM',20);
C.rampAngDeg = g(opts,'rampAngleDeg',80);
C.overlap    = g(opts,'overlapMM',0.6);

C.cAmp       = g(opts,'corrAmpMM',3.0);
C.cPitch     = max(1e-3, g(opts,'corrPitchMM',8.0));

C.ringOD     = g(opts,'ringOuterDiaMM',20);
C.ringTD     = g(opts,'ringTubeDiaMM',3.5);
C.ringNeck   = g(opts,'ringNeckLenMM',8);
C.ringNT     = max(16, g(opts,'ringThetaN',48));
C.ringNP     = max( 8, g(opts,'ringPhiN',20));

% adjust roots anterior (+Y)
rootL = [Pleft(1),  Pleft(2)+C.ahead,  C.zBed];
rootR = [Pright(1), Pright(2)+C.ahead, C.zBed];

TRL = buildSide(rootL, -1, C);   % left grows toward −X
TRR = buildSide(rootR, +1, C);   % right grows toward +X
TRstrap = catTri(TRL, TRR);

% optional cleanup (if you have it)
if exist('remove_unreferenced','file')==2
  [V2,F2] = remove_unreferenced(TRstrap.Points, TRstrap.ConnectivityList);
  TRstrap = triangulation(F2,V2);
end
end

% ===================== side builder =====================
function TR = buildSide(root, sideSign, C)
% 1) Corrugated centerline on the bed (meander in Y), running ±X.
Pbed = corrugatedPath(root, sideSign, C.Lbed, 0, C);   % z = zBed

% 2) Corrugated ramp: same meander, but centerline pitched up by ramp angle.
Pramp = corrugatedPath(endPoint(Pbed), sideSign, C.Lramp, C.rampAngDeg, C, C.overlap);

% 3) Sweep strap ribbon (same width/thickness) along combined centerline.
P = [Pbed; Pramp(2:end,:)];   % avoid duplicate join point
TRstrap = sweepRibbon(P, C.W, C.T);

% 4) Add smooth O-ring: short neck along ±X, then torus.
pend  = P(end,:);
neck0 = pend + sideSign * unitX() * max(0,C.overlap);   % tiny push past end
neck1 = neck0 + sideSign * unitX() * C.ringNeck;

TRneck = cylinderTri(neck0, neck1, C.T/2, 24);  % neck ~ strap thickness wide

Rmajor = (C.ringOD - C.ringTD)/2; rminor = C.ringTD/2;
Tring  = torusTri(neck1, sideSign*unitX(), Rmajor, rminor, C.ringNT, C.ringNP);

TR = catTri(TRstrap, TRneck);
TR = catTri(TR, Tring);
end

% ===================== corrugated centerlines =====================
function P = corrugatedPath(P0, sideSign, L, angDeg, C, overlap)
% Build a polyline starting from P0 that:
%  - advances in ±X by projected length L*cos(theta)
%  - rises in Z by L*sin(theta)
%  - meanders in Y with amplitude C.cAmp and pitch C.cPitch
% If overlap is provided, initial segment extends backward by that amount
% (to give small overlap with the previous piece).
if nargin < 6, overlap = 0; end
theta = deg2rad(angDeg);

% Total longitudinal projection in X and Z
dX = sideSign * L * cos(theta);
dZ = L * sin(theta);

% Parameterize by arc-length s ∈ [−overlap, L]
ds = max(C.cPitch/8, 0.5);   % sample reasonably
s  = (-overlap : ds : L).';
if s(end) < L, s(end+1) = L; end

% Centerline
X = P0(1) + sideSign * s * cos(theta);
Y = P0(2) + C.cAmp * sin(2*pi * s / C.cPitch);
Z = P0(3) +           s * sin(theta);

P = [X Y Z];
end

function p = endPoint(P), p = P(end,:); end

% ===================== sweeping & primitives =====================
function TR = sweepRibbon(P, W, T)
% Sweep a rectangular ribbon (width W across local 'w', thickness T across 'n')
% along polyline P, building a watertight mesh by convex hull per segment.
if size(P,1) < 2
    TR = triangulation(zeros(0,3), zeros(0,3)); return;
end
Vtot = []; Ftot = []; off = 0;
for k = 1:size(P,1)-1
    a = P(k,:); b = P(k+1,:);
    seg = b - a; L = norm(seg); if L==0, continue; end
    t = seg / L;
    up = [0 0 1];
    w = cross(up,t); if norm(w)<1e-9, up=[1 0 0]; w=cross(up,t); end
    w = w/norm(w); n = cross(t,w); n=normc(n);

    halfW = 0.5*W; halfT = 0.5*T;
    ext = min(halfW, 0.35*L);    % slight longitudinal overlap to hide seams
    A = a - ext*t; B = b + ext*t;

    v1 = A + (-halfW)*w + (-halfT)*n;  v2 = A + ( halfW)*w + (-halfT)*n;
    v3 = A + ( halfW)*w + ( halfT)*n;  v4 = A + (-halfW)*w + ( halfT)*n;
    v5 = B + (-halfW)*w + (-halfT)*n;  v6 = B + ( halfW)*w + (-halfT)*n;
    v7 = B + ( halfW)*w + ( halfT)*n;  v8 = B + (-halfW)*w + ( halfT)*n;

    V = [v1;v2;v3;v4; v5;v6;v7;v8];
    F = convhulln(V);

    Vtot = [Vtot; V]; %#ok<AGROW>
    Ftot = [Ftot; F+off]; %#ok<AGROW>
    off  = size(Vtot,1);
end
TR = triangulation(Ftot, Vtot);
end

function u = normc(v)
n = norm(v); if n<1e-12, u=[0 0 1]; else, u=v/n; end
end

function x = unitX(), x = [1 0 0]; end

function TR = cylinderTri(p0, p1, r, n)
t = p1-p0; L = norm(t); if L==0, TR=[]; return; end
t = t/L;
% Orthonormal frame
a = [0 0 1]; if abs(dot(a,t))>0.9, a=[1 0 0]; end
u = cross(t,a); u=u/norm(u); v = cross(t,u);
ang = linspace(0,2*pi,n+1); ang(end)=[];
ring0 = p0 + r*(u.*cos(ang)' + v.*sin(ang)');
ring1 = p1 + r*(u.*cos(ang)' + v.*sin(ang)');

% Side faces
V = [ring0; ring1];
F = [];
for i=1:n
    i2 = mod(i,n)+1;
    F = [F; i, i2, n+i; i2, n+i2, n+i]; %#ok<AGROW>
end

% Cap both ends for watertightness
Fcap0 = fanFaces(1:n, fliplr(1:n));        % bottom cap
Fcap1 = fanFaces(n+(1:n), n+fliplr(1:n));  % top cap
F = [F; Fcap0; Fcap1];
TR = triangulation(F,V);
end

function F = fanFaces(idx, idxRev)
% Make a triangular fan (idx(1) as center) — robust simple cap
c = idx(1);
F = [];
for k=2:numel(idx)-1
    F = [F; c, idx(k), idx(k+1)]; %#ok<AGROW>
end
% If a reversed fan was requested, mirror triangles
if nargin>1 && ~isempty(idxRev) %#ok<DEFNU>
    % no-op here; caps already oriented by construction
end
end

function TR = torusTri(center, axisVec, Rmajor, rminor, nTheta, nPhi)
axisVec = axisVec(:)'; axisVec = axisVec / max(norm(axisVec), eps);
theta = linspace(0,2*pi,nTheta+1); theta(end)=[];
phi   = linspace(0,2*pi,nPhi+1);   phi(end)  =[];
[TT, PP] = meshgrid(theta, phi);
x = (Rmajor + rminor.*cos(PP)) .* cos(TT);
y = (Rmajor + rminor.*cos(PP)) .* sin(TT);
z =  rminor .* sin(PP);
V = [x(:), y(:), z(:)];

ref = [1 0 0];
if norm(cross(ref,axisVec)) < 1e-9
    R = eye(3); if dot(ref,axisVec) < 0, R = diag([1 -1 -1]); end
else
    k = cross(ref, axisVec); k = k / norm(k);
    ang = acos(max(-1,min(1,dot(ref,axisVec))));
    K = [  0   -k(3)  k(2);  k(3)  0  -k(1);  -k(2)  k(1)  0 ];
    R = eye(3) + sin(ang)*K + (1-cos(ang))*(K*K);
end
V = (R * V.').' + center;

F = [];
for i=1:nPhi
    for j=1:nTheta
        i2 = mod(i, nPhi) + 1;
        j2 = mod(j, nTheta) + 1;
        a = (i-1)*nTheta + j;
        b = (i-1)*nTheta + j2;
        c = (i2-1)*nTheta + j2;
        d = (i2-1)*nTheta + j;
        F = [F; a b c; a c d]; %#ok<AGROW>
    end
end
TR = triangulation(F,V);
end

function v = g(s,f,def)
if isstruct(s) && isfield(s,f) && ~isempty(s.(f)), v=s.(f); else, v=def; end
end

function TR = catTri(A,B)
if isempty(A), TR=B; return; end
if isempty(B), TR=A; return; end
VA=A.Points; FA=A.ConnectivityList; VB=B.Points; FB=B.ConnectivityList;
TR = triangulation([FA; FB+size(VA,1)], [VA; VB]);
end
