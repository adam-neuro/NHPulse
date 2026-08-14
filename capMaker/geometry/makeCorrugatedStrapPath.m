function TR = makeCorrugatedStrapPath(P, opts)
% MAKECORRUGATEDSTRAPPATH  Watertight corrugated strap swept along 3D path.
% Robust to duplicates / tiny segments; uses parallel-transport frames and
% explicit prism faces (no convhulln). Adds absolute overlap (mm) to "stitch"
% adjacent prisms and prevent voxel boolean pinholes.
%
% Inputs:
%   P      Nx3 path points
%   opts   struct (all optional)
%       widthMM              (10)
%       thickMM              (2)
%       dsMM                 (0.8)
%       corrAmpMM            (0.8)
%       corrPitchMM          (10)
%       corrAxis             ('thickness')   % keep your semantics
%       twistDeg             (90)
%       alignWidthTo         ([] 3-vec or [])
%       overlapFrac          (0.35)          % legacy; see overlapMM
%       overlapMM            ([] -> 0.5*thickMM)  % absolute along-tangent overlap
%       endCap               (true)
%       upVec                ([0 0 1])
%       minSegMM             (1e-3)
%       mergeCollinearTolDeg (0.25)
%
% Output:
%   TR     triangulation

if nargin<2 || isempty(opts), opts = struct; end
W       = getOpt(opts,'widthMM', 10);
T       = max(1e-6, getOpt(opts,'thickMM', 2));   % avoid zero thickness
ds      = getOpt(opts,'dsMM', 0.8);
amp     = getOpt(opts,'corrAmpMM', 0.8);
pitch   = max(1e-6, getOpt(opts,'corrPitchMM', 10));
corrAxis= getOpt(opts,'corrAxis','thickness');
twist   = getOpt(opts,'twistDeg', 90);
alignTo = getOpt(opts,'alignWidthTo', []);
ovFrac  = getOpt(opts,'overlapFrac', 0.35);       % kept for back-compat
ovMM_in = getOpt(opts,'overlapMM', []);           % recommended
doCap   = getOpt(opts,'endCap', true);
upVec   = getOpt(opts,'upVec', [0 0 1]);
minSeg  = getOpt(opts,'minSegMM', 1e-3);
tolDeg  = getOpt(opts,'mergeCollinearTolDeg', 0.25);

% ---- path cleanup & resample ----
P = sanitizePath(P, minSeg, tolDeg);
Q = resamplePolyline3D(P, ds);
nQ = size(Q,1);
if nQ < 2
    TR = triangulation(zeros(0,3), zeros(0,3)); return;
end

% ---- arclength & corrugation phase ----
segL = vecnorm(diff(Q),2,2);
s    = [0; cumsum(segL)];
phi  = 2*pi*s/pitch;

% ---- parallel-transport (Bishop) frames with up-bias init ----
Tdir = diff([Q; Q(end,:)],1,1); Tdir = normalizeRows(Tdir);
Tdir(end,:) = Tdir(end-1,:);

% Seed W0 from upVec projection (stable init), then PT propagate.
u0  = normalizeRows(upVec);
w0  = u0 - dot(u0,Tdir(1,:))*Tdir(1,:); 
if norm(w0)<1e-9, w0 = pickPerp(Tdir(1,:)); else, w0 = w0/norm(w0); end
n0  = cross(Tdir(1,:), w0); n0 = n0/norm(n0);

Wdir = zeros(nQ,3); Ndir = zeros(nQ,3);
Wdir(1,:) = w0; Ndir(1,:) = n0;
for i=2:nQ
    t_prev = Tdir(i-1,:); t_cur = Tdir(i,:);
    axis   = cross(t_prev, t_cur);
    sA     = norm(axis);
    cA     = dot(t_prev, t_cur);
    if sA < 1e-12
        R = eye(3); if cA<0, R = -eye(3); R(3,3)=1; end
    else
        axis = axis / sA;
        ang  = atan2(sA, cA);
        R    = axangRot(axis, ang);
    end
    Wdir(i,:) = (R * Wdir(i-1,:).').';
    Ndir(i,:) = (R * Ndir(i-1,:).').';
end

% Optional alignment of width at start
if ~isempty(alignTo)
    wTarget = alignTo(:).';
    wTarget = wTarget - dot(wTarget,Tdir(1,:))*Tdir(1,:);
    if norm(wTarget) > 1e-9
        wTarget = wTarget / norm(wTarget);
        [Wdir(1,:), Ndir(1,:)] = rotateWNTo(Wdir(1,:), Ndir(1,:), Tdir(1,:), wTarget);
        % smooth blend toward PT frame (single-step set is usually fine)
    end
end

% Apply global twist (around local tangents)
if abs(twist) > 1e-9
    ang = deg2rad(twist);
    ca  = cos(ang); sa = sin(ang);
    for i=1:nQ
        t = Tdir(i,:);
        Wdir(i,:) = ca*Wdir(i,:) + sa*cross(t,Wdir(i,:)) + (1-ca)*dot(t,Wdir(i,:))*t;
        Ndir(i,:) = ca*Ndir(i,:) + sa*cross(t,Ndir(i,:)) + (1-ca)*dot(t,Ndir(i,:))*t;
    end
end

% ---- corrugation offset along thickness-normal (constant thickness) ----
switch lower(corrAxis)
    case 'thickness'
        offs = amp * sin(phi);
    otherwise
        offs = amp * sin(phi);  % keep same semantics
end

% ---- absolute overlap (recommended) or frac fallback ----
if isempty(ovMM_in)
    ovMM = 0.5 * T;           % robust default
else
    ovMM = max(0, ovMM_in);
end
% If users still rely on overlapFrac, blend the two (prefer absolute):
if ~isfinite(ovMM) || ovMM<=0
    ovMM = max(0, ovFrac * ds);
end

% ---- build explicit prisms (8 verts, 12 tris) per segment with overlap ----
halfW = 0.5*W; halfT = 0.5*T;
Vtot = zeros(0,3); Ftot = zeros(0,3); off = 0;

for i=1:nQ-1
    t  = Tdir(i,:);
    w0 = Wdir(i,:);  n0 = Ndir(i,:);
    w1 = Wdir(i+1,:); n1 = Ndir(i+1,:);

    % centerlines with corrugation offset
    C0 = Q(i,:)   + offs(i)   * n0;
    C1 = Q(i+1,:) + offs(i+1) * n1;

    Lseg = norm(Q(i+1,:) - Q(i,:));
    ext  = min([ovMM, 0.49*Lseg, 0.49*ds]);  % conservative clamp

    A = C0 - ext*t;   % near plane center
    B = C1 + ext*t;   % far  plane center

    % near quad (use frame i)
    v1 = A + (-halfW)*w0 + (-halfT)*n0;
    v2 = A + ( halfW)*w0 + (-halfT)*n0;
    v3 = A + ( halfW)*w0 + ( halfT)*n0;
    v4 = A + (-halfW)*w0 + ( halfT)*n0;
    % far quad (use frame i+1)
    v5 = B + (-halfW)*w1 + (-halfT)*n1;
    v6 = B + ( halfW)*w1 + (-halfT)*n1;
    v7 = B + ( halfW)*w1 + ( halfT)*n1;
    v8 = B + (-halfW)*w1 + ( halfT)*n1;

    V = [v1;v2;v3;v4; v5;v6;v7;v8];

    % explicit faces (consistent orientation)
    % near: 1-2-3, 1-3-4
    % far : 5-6-7, 5-7-8
    % sides: stitch rectangles
    F = [1 2 3; 1 3 4; ...
         5 6 7; 5 7 8; ...
         1 5 6; 1 6 2; ...  % bottom (−T)
         2 6 7; 2 7 3; ...  % +W
         3 7 8; 3 8 4; ...  % +T
         4 8 5; 4 5 1];     % −W

    Ftot = [Ftot; F + off]; %#ok<AGROW>
    Vtot = [Vtot; V];       %#ok<AGROW>
    off  = size(Vtot,1);
end

TR = triangulation(Ftot, Vtot);

% ---- end caps (optional) ----
if doCap && nQ>=2
    % start cap (at Q(1))
    [R0, nrm0] = endQuad(Q(1,:), Wdir(1,:), Ndir(1,:), W, T);
    TR = addQuadCapOriented(TR, R0, -Tdir(1,:), nrm0);
    % end cap (at Q(end))
    [R1, nrm1] = endQuad(Q(end,:), Wdir(end,:), Ndir(end,:), W, T);
    TR = addQuadCapOriented(TR, R1, +Tdir(end-1,:), nrm1);
end

% (optional) light de-dup of nearly identical vertices could be added here

end
% ================= helpers =================
function v = getOpt(s,f,def)
    if isstruct(s) && isfield(s,f) && ~isempty(s.(f)), v = s.(f); else, v = def; end
end

function Xn = normalizeRows(X)
    n = vecnorm(X,2,2); n(n==0)=1; Xn = X ./ n;
end

function a = pickPerp(t)
    [~,k] = min(abs(t)); e = zeros(1,3); e(k)=1; a = cross(t,e); a = a/norm(a);
end

function R = axangRot(axis, ang)
    ax = axis(:)/norm(axis);
    K = [  0    -ax(3)  ax(2);
          ax(3)   0    -ax(1);
         -ax(2) ax(1)    0   ];
    R = eye(3) + sin(ang)*K + (1-cos(ang))*(K*K);
end

function [W2, N2] = rotateWNTo(W, N, T, wTarget)
    wTarget = wTarget - dot(wTarget,T)*T;
    if norm(wTarget)<1e-9, W2=W; N2=N; return; end
    wTarget = wTarget/norm(wTarget);
    c = max(-1,min(1,dot(W,wTarget)));
    ang = acos(c);
    sgn = sign(dot(T, cross(W, wTarget)));
    R = axangRot(T, sgn*ang);
    W2 = (R*W.').'; N2 = (R*N.').';
end

function P2 = sanitizePath(P, minSeg, tolDeg)
    P = P(~any(~isfinite(P),2),:);
    if size(P,1)<2, P2=P; return; end
    % remove consecutive duplicates/tiny steps
    keep = true(size(P,1),1);
    d = vecnorm(diff(P),2,2);
    keep([false; d<minSeg]) = false;
    P = P(keep,:);
    if size(P,1)<2, P2=P; return; end
    % merge near-collinear interior points
    tolCos = cosd(tolDeg);
    out = P(1,:);
    for i=2:size(P,1)-1
        a=P(i-1,:); b=P(i,:); c=P(i+1,:);
        u=b-a; v=c-b; nu=norm(u); nv=norm(v);
        if nu<minSeg || nv<minSeg, continue; end
        cu = dot(u,v)/(nu*nv);
        if cu <= tolCos, out(end+1,:)=b; end %#ok<AGROW>
    end
    out(end+1,:) = P(end,:);
    P2 = out;
end

function Q = resamplePolyline3D(P, ds)
    seg = vecnorm(diff(P),2,2);
    L = [0; cumsum(seg)];
    [Luniq, ia] = unique(L, 'stable');
    Puniq = P(ia,:);
    if numel(Luniq)<2
        Q = repmat(Puniq(1,:),2,1); return;
    end
    Lend = Luniq(end);
    t = 0:ds:Lend;
    if t(end) < Lend-1e-9, t(end+1)=Lend; end
    Q = [interp1(Luniq,Puniq(:,1),t,'linear')', ...
         interp1(Luniq,Puniq(:,2),t,'linear')', ...
         interp1(Luniq,Puniq(:,3),t,'linear')'];
end

function [R, nrm] = endQuad(p, w, n, W, T)
    hw=0.5*W; ht=0.5*T;
    R = [p+(-hw)*w+(-ht)*n;
         p+( hw)*w+(-ht)*n;
         p+( hw)*w+( ht)*n;
         p+(-hw)*w+( ht)*n];
    % geometric normal
    nrm = cross(R(2,:)-R(1,:), R(3,:)-R(1,:));
    if norm(nrm)<1e-12, nrm = [0 0 1]; else, nrm = nrm/norm(nrm); end
end

function TR = addQuadCapOriented(TR, R, outward, nrm)
    % choose winding so that face normal points roughly along 'outward'
    if dot(nrm, outward) < 0
        idx = [1 2 3 4];
    else
        idx = [1 4 3 2];
    end
    V = TR.Points; F = TR.ConnectivityList; base = size(V,1);
    V = [V; R];
    Fcap = [base+idx(1) base+idx(2) base+idx(3); ...
            base+idx(1) base+idx(3) base+idx(4)];
    TR = triangulation([F; Fcap], V);
end
