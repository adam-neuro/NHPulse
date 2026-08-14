function E = fitEllipseRMS(x, y, opts)
% Robust ellipse fit:
%   1) Halír–Flusser normalized direct fit (stable)
%   2) Proper denormalization via homogeneous transform
%   3) Conic -> geometric params (with sign fix)
%   4) Optional LM refinement on Euclidean orthogonal distance
%
% Returns E with fields: xc,yc,a,b,theta,U,curveXY,rms,iters

if nargin < 3, opts = struct; end
opts = setDefault(opts,'maxLMIter',25);
opts = setDefault(opts,'doLM',true);
opts = setDefault(opts,'curveN',400);

x = x(:); y = y(:);
N = numel(x);
if N < 5, error('Need at least 5 points for ellipse fit.'); end

% --- Normalize points (Hartley style) for conditioning ---
mx = mean(x); my = mean(y);
sx = std(x);  sy = std(y);
if sx==0 || sy==0, error('Degenerate data: zero spread.'); end
T = diag([1/sx, 1/sy, 1]);               % scale
t = [-mx/sx; -my/sy; 1];                 % translate then scale in homog form
H = T * [1 0 mx; 0 1 my; 0 0 1];         % maps [x;y;1] -> [xn;yn;1]
Xh = [x y ones(N,1)]';
Xn = H * Xh;  xn = Xn(1,:)';  yn = Xn(2,:)';

% --- Halír–Flusser direct fit in normalized coords ---
D1 = [xn.^2, xn.*yn, yn.^2];
D2 = [xn, yn, ones(N,1)];
S1 = D1' * D1;
S2 = D1' * D2;
S3 = D2' * D2;
% Constraint matrix for ellipse: 4ac - b^2 = 1 in normalized form
C1 = [0 0 2; 0 -1 0; 2 0 0];
M  = S1 - S2 / S3 * S2';
% Solve M a = lambda C1 a  (generalized eigen)
[vec, val] = eig(M, C1);
% Pick the eigenvector with positive definite ellipse condition
% (Halír–Flusser already enforces ellipse constraint via C1)
[~, ix] = max(real(diag(val)));
a1 = vec(:, ix);
% Recover linear terms
a2 = - S3 \ (S2' * a1);
% Normalized conic parameters (an: ax^2 + bxy + cy^2 + dx + ey + f = 0)
an = [a1; a2];  % [A B C D E F] in normalized coords

% --- Denormalize conic via homogeneous transform ---
Cn = [an(1) an(2)/2 an(4)/2; an(2)/2 an(3) an(5)/2; an(4)/2 an(5)/2 an(6)];
% Conic transforms as: C = H^{-T} * Cn * H^{-1}
Hi = inv(H);
Cw = Hi' * Cn * Hi;

% convert back to 6-vector coefficients in world coords
A = Cw(1,1); B = 2*Cw(1,2); C = Cw(2,2); D = 2*Cw(1,3); E = 2*Cw(2,3); F = Cw(3,3);
c6 = [A B C D E F]';

% --- Convert conic -> geometric, fixing sign if needed ---
[Eok, Eg] = conicToGeom_safe(c6);
if ~Eok
    % Try flipping sign once (common after denorm)
    c6 = -c6;
    [Eok, Eg] = conicToGeom_safe(c6);
end
if ~Eok
    error('Conic->geom failed: points may be degenerate or not elliptical.');
end

% Optional LM refinement to minimize orthogonal distance
if opts.doLM
    q = [Eg.xc, Eg.yc, Eg.a, Eg.b, Eg.theta];
    [q, rmsVal, iters] = refineEllipseLM(q, x, y, opts.maxLMIter);
else
    q = [Eg.xc, Eg.yc, Eg.a, Eg.b, Eg.theta];
    [~, rmsVal, iters] = refineEllipseLM(q, x, y, 0);
end

[xc,yc,aSemi,bSemi,th] = unpack(q);
U = [cos(th) -sin(th); sin(th) cos(th)];
tt = linspace(0,2*pi, opts.curveN);
curveXY = [xc + aSemi*cos(tt)*U(1,1) - bSemi*sin(tt)*U(1,2); ...
           yc + aSemi*cos(tt)*U(2,1) + bSemi*sin(tt)*U(2,2)].';

E = struct('xc',xc,'yc',yc,'a',aSemi,'b',bSemi,'theta',th,'U',U,...
           'curveXY',curveXY,'rms',rmsVal,'iters',iters);
end

% ================= helpers =================

function s = setDefault(s,f,v)
if ~isfield(s,f) || isempty(s.(f)), s.(f)=v; end
end

function [ok, G] = conicToGeom_safe(c)
% ax^2 + bxy + cy^2 + dx + ey + f = 0  -> center, axes, angle
a=c(1); b=c(2); c2=c(3); d=c(4); e=c(5); f=c(6);
Q = [a b/2; b/2 c2];
if ~isfinite(det(Q)) || det(Q) <= 0, ok=false; G=[]; return; end
B = [2*a, b; b, 2*c2];
if abs(det(B)) < 1e-12, ok=false; G=[]; return; end
xy0 = -B \ [d; e];  xc = xy0(1); yc = xy0(2);
F0 = a*xc^2 + b*xc*yc + c2*yc^2 + d*xc + e*yc + f;
[U,D] = eig(Q);
lam = diag(D);
if any(lam <= 0)
    ok=false; G=[]; return;
end
% Interior must satisfy (p-cc)^T Q (p-cc) + F0 < 0  -> require F0 < 0
if F0 >= 0
    ok=false; G=[]; return;
end
% Semi-axes from quadratic form: (x')^T D x' + F0 = 0  => x1'^2/( -F0/lam1 ) + x2'^2/( -F0/lam2 ) = 1
aSemi = sqrt(-F0 / lam(1));
bSemi = sqrt(-F0 / lam(2));
% ensure a >= b
if bSemi > aSemi
    tmp=aSemi; aSemi=bSemi; bSemi=tmp;
    U = U * [0 1; 1 0];
    lam = lam([2,1]);
end
theta = atan2(U(2,1), U(1,1));
G = struct('xc',xc,'yc',yc,'a',aSemi,'b',bSemi,'theta',theta,'U',U);
ok = true;
end

function [q, rmsVal, iters] = refineEllipseLM(q0, x, y, maxIter)
% Levenberg–Marquardt on orthogonal distance (fixed-correspondence per iter)
q = q0;
lambda = 1e-2;
r = computeResiduals(q, x, y);
for it=1:max(1,maxIter)
    [J, r] = jacobianAndResidual(q, x, y);
    H = J.'*J + lambda*eye(5);
    g = J.'*r;
    step = - H \ g;
    qTry = applyStep(q, step);
    rTry = computeResiduals(qTry, x, y);
    if norm(rTry) < norm(r)
        q = qTry; r = rTry; lambda = max(lambda/3, 1e-7);
    else
        lambda = min(lambda*3, 1e6);
    end
    if norm(step) < 1e-6*(1+norm(q)), break; end
end
rmsVal = norm(r)/sqrt(numel(r)/2);
iters = it;
end

function [J, r] = jacobianAndResidual(q, x, y)
ti = closestParams(q, x, y);
[Ex,Ey,Ex_q,Ey_q] = ellipseAndDerivs(q, ti);
dx = Ex - x; dy = Ey - y;
r  = [dx; dy];
N = numel(x);
J = zeros(2*N,5);
J(1:N,:)     = Ex_q;
J(N+1:2*N,:) = Ey_q;
end

function r = computeResiduals(q, x, y)
ti = closestParams(q, x, y);
[Ex,Ey] = ellipseXY(q, ti);
r = [Ex - x; Ey - y];
end

function ti = closestParams(q, x, y)
N = numel(x); ti = zeros(N,1);
[xc,yc,a,b,th] = unpack(q);
R = [cos(th) -sin(th); sin(th) cos(th)];
for i=1:N
    u = R' * ([x(i)-xc; y(i)-yc]);
    t = atan2(a*u(2), b*u(1));   % init
    for k=1:20
        ct=cos(t); st=sin(t);
        E=[a*ct; b*st]; Ep=[-a*st; b*ct]; Epp=[-a*ct; -b*st];
        d=E-u; g=d.'*Ep; gp=Ep.'*Ep + d.'*Epp;
        if abs(gp)<1e-14, break; end
        tNew = t - g/gp;
        if ~isfinite(tNew) || abs(tNew-t)<1e-12, break; end
        t = tNew;
    end
    ti(i)=t;
end
end

function [Ex,Ey] = ellipseXY(q, t)
[xc,yc,a,b,th] = unpack(q);
ct=cos(t); st=sin(t); c=cos(th); s=sin(th);
Ex = xc + a*ct*c - b*st*s;
Ey = yc + a*ct*s + b*st*c;
end

function [Ex,Ey,Ex_q,Ey_q] = ellipseAndDerivs(q, t)
[xc,yc,a,b,th] = unpack(q);
ct=cos(t); st=sin(t); c=cos(th); s=sin(th);
Ex = xc + a*ct*c - b*st*s;
Ey = yc + a*ct*s + b*st*c;
Ex_q = [ones(size(t)), zeros(size(t)),  ct*c,   st*s, (-a*ct*s - b*st*c)];
Ey_q = [zeros(size(t)), ones(size(t)),  ct*s,   st*c, ( a*ct*c - b*st*s)];
end

function qNew = applyStep(q, step)
[xc,yc,a,b,th] = unpack(q);
xc = xc + step(1); yc = yc + step(2);
a  = max(1e-6, a + step(3));
b  = max(1e-6, b + step(4));
th = wrapToPi(th + step(5));
if b > a
    tmp=a; a=b; b=tmp; th = wrapToPi(th + pi/2);
end
qNew = [xc,yc,a,b,th];
end

function [xc,yc,a,b,th] = unpack(q)
xc=q(1); yc=q(2); a=q(3); b=q(4); th=q(5);
end

function ang = wrapToPi(a)
ang = mod(a + pi, 2*pi) - pi;
end
