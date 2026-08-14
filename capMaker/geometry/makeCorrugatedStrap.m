function TR = makeCorrugatedStrap(P0, P1, opts)
% MAKECORRUGATEDSTRAP  Watertight corrugated strap (rectangular section) swept along a centerline.
% Corrugation defaults to the thickness–length plane (along n_hat).
%
% Options (additions):
%   .corrAxis  : 'thickness' (default) or 'width'
%
% Other options same as prior version.

% ---- defaults & inputs ----
if nargin < 1 || isempty(P0), P0 = [0 0 0]; end
if nargin < 2 || isempty(P1), P1 = [100 0 0]; end
if nargin < 3, opts = struct; end

W       = getOpt(opts,'widthMM',10);
T       = getOpt(opts,'thickMM',2);
zBed    = getOpt(opts,'zBed',0); %#ok<NASGU>
up      = getOpt(opts,'upVec',[0 0 1]);
twist   = deg2rad(getOpt(opts,'twistDeg',0));

cAmp    = getOpt(opts,'corrAmpMM',3);
cPitch  = getOpt(opts,'corrPitchMM',12);
ds      = getOpt(opts,'dsMM', max(0.25, cPitch/8));
endCap  = logical(getOpt(opts,'endCap',true));
ovFrac  = getOpt(opts,'overlapFrac',0.35);
corrAxis= getOpt(opts,'corrAxis','thickness'); % 'thickness' or 'width'

% ---- build meandered centerline from P0->P1 ----
dP = P1 - P0;   L = norm(dP);
if L < 1e-9, error('Endpoints are coincident; strap length must be > 0.'); end
t_hat = dP / L;

up = up(:)'; if norm(up)<1e-12, up=[0 0 1]; else, up=up/norm(up); end
w_hat = cross(up, t_hat);
if norm(w_hat) < 1e-9, alt=[1 0 0]; if abs(dot(alt,t_hat))>0.9, alt=[0 1 0]; end, w_hat=cross(alt,t_hat); end
w_hat = w_hat / norm(w_hat);
n_hat = cross(t_hat, w_hat);

s = (0:ds:L)'; if s(end) < L, s(end+1) = L; end
phase = 2*pi * s / max(1e-6, cPitch);

switch lower(corrAxis)
    case 'thickness'  % corrugation in thickness–length plane
        Off = (cAmp * sin(phase)) .* n_hat;
    case 'width'      % (previous behavior)
        Off = (cAmp * sin(phase)) .* w_hat;
    otherwise
        error('corrAxis must be ''thickness'' or ''width''.');
end

P = P0 + s.*t_hat + Off;  % centerline points

% ---- swept rectangular section ----
cosA = cos(twist); sinA = sin(twist);
wR =  cosA.*w_hat + sinA.*n_hat;
nR = -sinA.*w_hat + cosA.*n_hat;

N = size(P,1);
halfW = 0.5*W;  halfT = 0.5*T;

Vall = []; Fall = []; voff = 0;
for k = 1:N-1
    A = P(k,:); B = P(k+1,:);
    seg = B - A; segL = norm(seg); if segL < 1e-9, continue; end
    tloc = seg / segL;

    wloc = wR - dot(wR,tloc).*tloc; if norm(wloc)<1e-9, wloc = w_hat; else, wloc = wloc/norm(wloc); end
    nloc = cross(tloc, wloc); nloc = nloc / max(1e-12, norm(nloc));

    ext = min(halfW*2*ovFrac, 0.35*segL);
    A2 = A - ext*tloc; B2 = B + ext*tloc;

    v1 = A2 + (-halfW)*wloc + (-halfT)*nloc;
    v2 = A2 + ( halfW)*wloc + (-halfT)*nloc;
    v3 = A2 + ( halfW)*wloc + ( halfT)*nloc;
    v4 = A2 + (-halfW)*wloc + ( halfT)*nloc;
    v5 = B2 + (-halfW)*wloc + (-halfT)*nloc;
    v6 = B2 + ( halfW)*wloc + (-halfT)*nloc;
    v7 = B2 + ( halfW)*wloc + ( halfT)*nloc;
    v8 = B2 + (-halfW)*wloc + ( halfT)*nloc;

    Vseg = [v1;v2;v3;v4; v5;v6;v7;v8];
    Fseg = convhulln(Vseg);

    Vall = [Vall; Vseg]; %#ok<AGROW>
    Fall = [Fall; Fseg + voff]; %#ok<AGROW>
    voff = size(Vall,1);
end

TR = triangulation(Fall, Vall);

% ---- optional end caps ----
if endCap && size(P,1) >= 2
    t0 = P(2,:) - P(1,:);  t0 = t0 / norm(t0);
    w0 = wR - dot(wR,t0).*t0; if norm(w0)<1e-9, w0 = w_hat; else, w0 = w0/norm(w0); end
    n0 = cross(t0, w0); n0 = n0 / max(1e-12, norm(n0));
    R0 = ringRect(P(1,:),  w0, n0, halfW, halfT);

    t1 = P(end,:) - P(end-1,:); t1 = t1 / norm(t1);
    w1 = wR - dot(wR,t1).*t1; if norm(w1)<1e-9, w1 = w_hat; else, w1 = w1/norm(w1); end
    n1 = cross(t1, w1); n1 = n1 / max(1e-12, norm(n1));
    R1 = ringRect(P(end,:), w1, n1, halfW, halfT);

    TR = addQuadCap(TR, R0, true);
    TR = addQuadCap(TR, R1, false);
end
end

% ---------------- helpers ----------------
function v = getOpt(s,f,def)
if isstruct(s) && isfield(s,f) && ~isempty(s.(f)), v = s.(f); else, v = def; end
end

function R = ringRect(C, w, n, halfW, halfT)
R = [ C + (-halfW)*w + (-halfT)*n;
      C + ( halfW)*w + (-halfT)*n;
      C + ( halfW)*w + ( halfT)*n;
      C + (-halfW)*w + ( halfT)*n ];
end
