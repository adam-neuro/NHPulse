function TR = makeLivingHingeStrapsWithRings(Pleft, Pright, opts)
% MAKELIVINGHINGESTRAPSWITHRINGS  Two bed straps with slot-based living hinge + ring ends.
%
% Inputs
%   Pleft, Pright : 1x3 anchors on bed-projection line (we'll only use X,Y; Z comes from zBed)
%   opts:
%     zBed               (default 0)
%     strapAheadMM       (default 25)   % +Y nudge (forward) to avoid head
%     strapWidthMM       (default 20)
%     strapThickMM       (default 2.4)
%     bedLenMM           (default 60)   % straight section length beyond hinge zone (per side)
%     % hinge zone (starts at strap root near the head, extends outward along ±X)
%     hingeLenMM         (default 18)
%     hingeSlotsN        (default 5)
%     slotLenMM          (default 10)
%     slotWidthMM        (default 3.2)
%     slotCornerMM       (default 1.6)  % rounded slot corners
%     slotSkewDeg        (default 15)   % alternating +/- skew to emulate S-curves
%     slotEdgeClearMM    (default 2)    % keep material at hinge edges
%     % ring termination
%     ringOuterDiaMM     (default 20)
%     ringTubeDiaMM      (default 3.5)
%     ringNeckLenMM      (default 8)
%
% Output
%   TR : triangulation of both straps + rings (watertight)
%
if nargin<3, opts = struct; end

zBed         = getOpt(opts,'zBed',0);
ahead        = getOpt(opts,'strapAheadMM',25);
strapW       = getOpt(opts,'strapWidthMM',20);
strapT       = getOpt(opts,'strapThickMM',2.4);
bedLen       = getOpt(opts,'bedLenMM',60);

hingeLen     = getOpt(opts,'hingeLenMM',18);
nSlots       = getOpt(opts,'hingeSlotsN',5);
slotLen      = getOpt(opts,'slotLenMM',10);
slotW        = getOpt(opts,'slotWidthMM',3.2);
slotR        = getOpt(opts,'slotCornerMM',1.6);
slotSkewDeg  = getOpt(opts,'slotSkewDeg',15);
slotEdgeClr  = getOpt(opts,'slotEdgeClearMM',2);

ringOD       = getOpt(opts,'ringOuterDiaMM',20);
ringTD       = getOpt(opts,'ringTubeDiaMM',3.5);
neckLen      = getOpt(opts,'ringNeckLenMM',8);

% Place straps on bed, centered at Y = anchorY + ahead
Pleft  = [Pleft(1),  Pleft(2)+ahead,  zBed];
Pright = [Pright(1), Pright(2)+ahead, zBed];

TR = [];

% Left strap extends toward -X
TR = catTri(TR, oneStrap(Pleft, -1, strapW, strapT, hingeLen, nSlots, slotLen, slotW, slotR, slotSkewDeg, slotEdgeClr, bedLen, ringOD, ringTD, neckLen, zBed));
% Right strap extends toward +X
TR = catTri(TR, oneStrap(Pright, +1, strapW, strapT, hingeLen, nSlots, slotLen, slotW, slotR, slotSkewDeg, slotEdgeClr, bedLen, ringOD, ringTD, neckLen, zBed));

% Optional cleanup
if exist('remove_unreferenced','file')==2
    [V2,F2] = remove_unreferenced(TR.Points, TR.ConnectivityList);
    TR = triangulation(F2,V2);
end
end

% ---------- one side ----------
function TR = oneStrap(P0, sideSign, W, T, hingeLen, nSlots, slotLen, slotW, slotR, slotSkewDeg, edgeClr, bedLen, ringOD, ringTD, neckLen, zBed)
% Strap coordinate frame: origin at P0, centerline along sideSign*X, width across Y.
% Build 2D polygon with internal slot holes, then extrude to thickness T.

% Outer rectangle (hinge zone + straight tail up to ring neck)
Ltot = hingeLen + bedLen;
x1 = 0;            x2 = Ltot;
y1 = -W/2;         y2 = +W/2;

% Build in local 2D (u along +X_outward, v along +Y), then flip to world via sideSign
% Hinge zone occupies u in [0, hingeLen]
slots = slotLayout(nSlots, hingeLen, W, slotLen, slotW, slotR, edgeClr, slotSkewDeg);

% Outer polygon (CCW)
outer = [x1 y1; x2 y1; x2 y2; x1 y2];
ps = polyshape(outer(:,1), outer(:,2));
% Subtract hinge slots (as holes)
for k=1:numel(slots)
    h = slots{k};  % struct with fields .xy (rounded-rect poly), already inside [0,hingeLen]
    ps = subtract(ps, polyshape(h.xy(:,1), h.xy(:,2)));
end

% Extrude to watertight prism on [zBed, zBed+T]
TRstrap = polyPrism(ps, zBed, zBed+T);

% Convert local (u,v) to world (x,y) with sideSign and anchored at P0
TRstrap = transformUV(TRstrap, P0, sideSign);

% Add ring termination + neck
TRring = addRingAtEnd(TRstrap, sideSign, ringOD, ringTD, neckLen, W, T, zBed);

TR = catTri(TRstrap, TRring);
end

% ---------- slots in hinge zone ----------
function slots = slotLayout(nSlots, hingeLen, W, slotLen, slotW, slotR, edgeClr, skewDeg)
% Alternating angled rounded-rectangle slots centered across strap width.
% Evenly spaced along hingeLen; each slot stays within [edgeClr, W/2-edgeClr].
slots = cell(nSlots,1);
cx = linspace(slotLen/2, hingeLen - slotLen/2, nSlots);
cy = zeros(1,nSlots);
ang = skewDeg * (-1).^(1:nSlots);  % +θ, −θ, +θ, ...
for i=1:nSlots
    % Rounded rectangle centered at (cx,cy), length slotLen (along local u), width slotW (along v)
    rr = roundedRect2D([cx(i), cy(i)], slotLen, slotW, slotR);
    % rotate by ang(i) about center
    R = [cosd(ang(i)) -sind(ang(i)); sind(ang(i)) cosd(ang(i))];
    rrRot = (R*(rr.' - [cx(i); cy(i)])).'+[cx(i) cy(i)];
    % ensure stays within edgeClr
    if max(abs(rrRot(:,2))) > (W/2 - edgeClr)
        scale = (W/2 - edgeClr) / max(abs(rrRot(:,2))) * 0.98;
        rrRot = (rrRot - [cx(i) cy(i)])*scale + [cx(i) cy(i)];
    end
    slots{i} = struct('xy', rrRot);
end
end

function P = roundedRect2D(center, L, W, R)
% CCW polygon for rounded rectangle centered at 'center' with length L (x) and width W (y),
% corner radius R. Uses 8*nsamp points (approximate).
ns = 10;  % arc samples per corner
cx=center(1); cy=center(2);
hx=L/2-R; hy=W/2-R;
% corner centers
C = [ cx+hx cy+hy;  cx-hx cy+hy;  cx-hx cy-hy;  cx+hx cy-hy ];
angles = {linspace(0,90,ns), linspace(90,180,ns), linspace(180,270,ns), linspace(270,360,ns)};
P = zeros(0,2);
for k=1:4
    theta = angles{k}*pi/180;
    x = C(k,1) + R*cos(theta);
    y = C(k,2) + R*sin(theta);
    P = [P; x(:) y(:)]; %#ok<AGROW>
end
end

% ---------- extrude 2D polyshape to prism ----------
function TR = polyPrism(ps, z0, z1)
% Triangulate 2D polyshape (with holes) into top/bottom and side walls; return watertight TR.
% Bottom/top
TR2 = triangulation(ps);              % 2D triangulation
TF  = TR2.ConnectivityList;
PV  = TR2.Points;
Vbot = [PV, z0*ones(size(PV,1),1)];
Vtop = [PV, z1*ones(size(PV,1),1)];
Fbot = TF;                 % oriented CCW → normal -Z (fine)
Ftop = fliplr(TF) + size(Vbot,1);   % reverse for +Z
% Side walls for outer boundary and holes
V = [Vbot; Vtop]; F = [Fbot; Ftop];
% Outer boundary plus holes:
[bx, by] = boundary(ps);
loops = splitLoops(bx, by);
for m=1:numel(loops)
    L = loops{m};
    ids = map2Idx(PV, L);    % map boundary polyline points back to PV indices
    ids = unique(ids,'stable');
    if ids(1) ~= ids(end), ids(end+1) = ids(1); end
    for j=1:numel(ids)-1
        a = ids(j); b = ids(j+1);
        F = [F; a, b, b+size(PV,1); a, b+size(PV,1), a+size(PV,1)]; %#ok<AGROW>
    end
end
TR = triangulation(F, V);
end

function loops = splitLoops(bx, by)
% bx/by contain NaN separators
nanIdx = isnan(bx) | isnan(by);
starts = [1, find(nanIdx)+1]; starts(starts>numel(bx)) = [];
ends   = [find(nanIdx)-1, numel(bx)];
mask = ends >= starts;
starts = starts(mask); ends = ends(mask);
loops = cell(sum(mask),1);
c=1; 
for k=1:numel(starts)
    L = [bx(starts(k):ends(k)), by(starts(k):ends(k))];
    if ~isempty(L), loops{c}=L; c=c+1; end
end
loops = loops(1:c-1);
end

function idx = map2Idx(PV, L)
% nearest PV rows for polyline points L
K = createns(PV,'NSMethod','kdtree');
idx = knnsearch(K, L);
end

% ---------- local-UV to world XY transform ----------
function TRw = transformUV(TRu, P0, sideSign)
V = TRu.Points;
% local u → world x by sideSign; local v → world y
Vw = [ P0(1) + sideSign*V(:,1),  P0(2) + V(:,2),  V(:,3) ];
TRw = triangulation(TRu.ConnectivityList, Vw);
end

% ---------- ring at distal end ----------
function TR = addRingAtEnd(TRstrap, sideSign, ringOD, ringTD, neckLen, strapW, strapT, zBed)
% Find distal end in X, attach small neck, then torus
V = TRstrap.Points; bb = [min(V,[],1); max(V,[],1)];
if sideSign<0, xFree = bb(1,1); else, xFree = bb(2,1); end
yMid = 0.5*(bb(1,2)+bb(2,2));

% Neck prism
x1N = xFree; x2N = xFree + sideSign*neckLen;
y1N = yMid - strapW/2; y2N = yMid + strapW/2;
z1N = zBed; z2N = zBed + strapT;
Vneck = [x1N y1N z1N; x2N y1N z1N; x2N y2N z1N; x1N y2N z1N; ...
         x1N y1N z2N; x2N y1N z2N; x2N y2N z2N; x1N y2N z2N];
Fneck = convhulln(Vneck);
TRneck = triangulation(Fneck, Vneck);

% Torus flat on bed (axis Z)
R = 0.5*ringOD - 0.5*ringTD;
r = 0.5*ringTD;
cx = x2N + sideSign*R; cy = yMid; cz = zBed + r;
TRtor = torusTri([cx, cy, cz], R, r, 72, 36);

TR = catTri(TRneck, TRtor);
end

% ---------- torus generator ----------
function TR = torusTri(center, R, r, nU, nV)
cx=center(1); cy=center(2); cz=center(3);
u = linspace(0,2*pi,nU+1); u(end)=[];
v = linspace(0,2*pi,nV+1); v(end)=[];
[U,V] = meshgrid(u,v); U=U.'; V=V.'; % nU x nV
X = (R + r.*cos(V)).*cos(U) + cx;
Y = (R + r.*cos(V)).*sin(U) + cy;
Z =  r.*sin(V) + cz;
idx = @(i,j) (j-1)*nU + i;
Vtx=[X(:) Y(:) Z(:)]; Fac=zeros(2*nU*nV,3); f=1;
for j=1:nV
    j2 = mod(j,nV)+1;
    for i=1:nU
        i2 = mod(i,nU)+1;
        a=idx(i,j); b=idx(i2,j); c=idx(i2,j2); d=idx(i,j2);
        Fac(f,:)=[a b c]; f=f+1; Fac(f,:)=[a c d]; f=f+1;
    end
end
TR = triangulation(Fac,Vtx);
end

% ---------- tri utils ----------
function TR = catTri(A,B)
if isempty(A), TR=B; return; end
if isempty(B), TR=A; return; end
VA=A.Points; FA=A.ConnectivityList;
VB=B.Points; FB=B.ConnectivityList;
V=[VA;VB]; F=[FA; FB+size(VA,1)];
TR=triangulation(F,V);
end

function v = iff(cond, a, b), if cond, v=a; else, v=b; end, end


function v = getOpt(opts, f, def)
    if isstruct(opts) && isfield(opts, f)
        v = opts.(f);
        if isempty(v), v = def; end
    else
        v = def;
    end
end
