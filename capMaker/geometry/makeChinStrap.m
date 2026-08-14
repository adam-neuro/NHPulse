function TRstrap = makeChinStrap(TRcap, rails, opts)
% MAKECHINSTRAP  TPE chin-strap from rail anchors down to Z=0 and out along ±X (interaural).
%
% Key changes:
%   - Straps extend along X (ear-to-ear) away from scalp.
%   - Straps are shifted anterior by strapAheadMM (along +Y).
%   - Connectors drop to the inner strap edge (clean junction).

if nargin<3, opts = struct; end
g = @(f,v) getOr(opts,f,v);

zBed             = g('zBed',0);
anchorYOffsetMM  = g('anchorYOffsetMM',10);
connectorW       = g('connectorWidthMM',10);
connectorT       = g('connectorThickMM',2.5);
connectorDropMM  = g('connectorDropMM',[]);
sagFrac          = g('connectorSagFrac',0.25);

strapLen         = g('bedLenMM',80);        % along X
strapW           = g('strapWidthMM',18);    % along Y
strapT           = g('strapThickMM',2.2);
strapAhead       = g('strapAheadMM',20);    % NEW: anterior shift (+Y) of strap center
headMargin       = g('headMarginMM',8);     % NEW: distance from anchor X to inner strap edge

holeDia          = g('holeDiaMM',4.0);
holePitch        = g('holePitchMM',12);
holeEdgeClr      = g('holeEdgeClearMM',10);

studStemDia      = g('studStemDiaMM',3.5);
studHeadDia      = g('studHeadDiaMM',5);
studHeadThick    = g('studHeadThickMM',1.6);
studPitch        = g('studPitchMM',holePitch);
studEdgeClr      = g('studEdgeClearMM',10);

footprintPoly = g('footprintPoly', []);  % optional polyshape of head footprint in XY
strapAhead    = g('strapAheadMM',20);    % anterior shift (+Y)
outBowMM      = g('connectorOutBowMM',12); % how much to bow outward along ±X on the rise
footprintEpsZ = g('footprintZBandMM',0.6); % band around zBed for auto-footprint

strapYNudge   = g('strapYNudgeMM', 25);   % NEW: push straps anterior (+Y)
edgeMarginMM  = g('edgeMarginMM', 0.5);   % NEW: tiny outward offset from footprint

useConnectors = g('useConnectors', false);  % default off per new plan

useRings          = g('useRings', true);    % enable ring termination
ringOuterDia      = g('ringOuterDiaMM', 20);% requested ~20 mm
ringTubeDia       = g('ringTubeDiaMM', 3.5);
ringNeckLen       = g('ringNeckLenMM', 8);  % short rectangular neck
ringNeckWidth     = g('ringNeckWidthMM', []); % default: strap width
ringNeckThick     = g('ringNeckThickMM', []); % default: strap thickness
ringSidesMajor    = g('ringSidesMajor', 72);  % smoothness
ringSidesMinor    = g('ringSidesMinor', 36);

if useRings
    holeDia = 0;  % no holes
end


% --- Anchors (as before) --------------------------------------------------
if isstruct(rails) && isfield(rails,'left') && isfield(rails,'right') ...
                  && isfield(rails.left,'poly3D') && isfield(rails.right,'poly3D')
    Pa = pickAnchor(rails.left.poly3D,  anchorYOffsetMM);
    Pb = pickAnchor(rails.right.poly3D, anchorYOffsetMM);
elseif isa(rails,'triangulation')
    [Pa, Pb] = inferRailAnchorsFromTR(rails, anchorYOffsetMM);
else
    error('makeChinStrap:BadRails','rails must be rail struct or triangulation.');
end

if isempty(footprintPoly)
    footprintPoly = footprintFromCap(TRcap, zBed, g('footprintZBandMM',0.6));
end


% --- Bed straps (±X), inner edge at scalp footprint at y = anchorY + ahead + nudge
ycL = Pa(2) + strapAhead + strapYNudge;
ycR = Pb(2) + strapAhead + strapYNudge;

[xminL, xmaxL] = xSpanAtY(footprintPoly, ycL);
[xminR, xmaxR] = xSpanAtY(footprintPoly, ycR);

% Inner edges placed just OUTSIDE the footprint by a tiny margin
xInnerL = xminL - abs(edgeMarginMM);      % left side → more negative
xInnerR = xmaxR + abs(edgeMarginMM);      % right side → more positive

% Left strap geometry (inner edge at xInnerL, centered at ycL)
x1L = xInnerL - strapLen;   % extends toward -X
x2L = xInnerL;
y1L = ycL - strapW/2;
y2L = ycL + strapW/2;
ymL = (y1L + y2L)/2;

% Hole centers along X on the midline Y=ymL, with edge clearance
holeCentersL = holeCentersRectX(x1L, x2L, ymL, holeEdgeClr, holePitch, zBed);

% Build perforated left strap
TRa_bed = makePerforatedBedStrapX_innerEdge([xInnerL ycL zBed], -1, ...
                 strapLen, strapW, strapT, holeCentersL, holeDia);

% Right strap (unchanged)
TRb_bed = makeBedStrapX_innerEdge([xInnerR ycR zBed], +1, strapLen, strapW, strapT);

TRrings = [];

if useRings
    % Defaults: neck width/thickness match strap
    if isempty(ringNeckWidth), ringNeckWidth = strapW; end
    if isempty(ringNeckThick), ringNeckThick = strapT; end

    % For each strap: compute distal end center on bed, add neck + torus
    TRrings = catTri(TRrings, addRingToStrapEnd(TRa_bed, -1, ...
        ringOuterDia, ringTubeDia, ringNeckLen, ringNeckWidth, ringNeckThick, ...
        ringSidesMajor, ringSidesMinor, zBed));

    TRrings = catTri(TRrings, addRingToStrapEnd(TRb_bed, +1, ...
        ringOuterDia, ringTubeDia, ringNeckLen, ringNeckWidth, ringNeckThick, ...
        ringSidesMajor, ringSidesMinor, zBed));
end

TRa_conn = []; TRb_conn = [];
if g('useConnectors', false)
    mode = g('connectorMode','prism');
    switch lower(mode)
        case 'prism'
            h = g('connectorHeightMM', 25);
            t = g('connectorThickMM',  2.6);
            leanDeg = g('prismLeanDeg', 0);     % outward tilt, degrees

            segL = innerEdgeSegmentXZ(TRa_bed, -1);   % left inner edge (Z=0)
            segR = innerEdgeSegmentXZ(TRb_bed, +1);   % right inner edge

            TRa_conn = prismConnectorBlock(segL, -1, t, h, leanDeg);
            TRb_conn = prismConnectorBlock(segR, +1, t, h, leanDeg);

        case 'hinge'
            % keep your existing hinge wall path here if you want both modes available
            % (uses hingeConnectorWall)
        otherwise
            error('Unknown connectorMode: %s', mode);
    end
end


% --- Holes (LEFT) and studs (RIGHT) laid out along X ---------------------
holeCentersL = holePatternCentersX(TRa_bed, holePitch, holeEdgeClr);
TRstuds = [];
studCentersR = holePatternCentersX(TRb_bed, studPitch, studEdgeClr);
for i=1:size(studCentersR,1)
    c = studCentersR(i,:);
    TRstud = mushroomAt(c, zBed, strapT, studStemDia, studHeadDia, studHeadThick, 24);
    TRstuds = catTri(TRstuds, TRstud);
end

% --- Assemble -------------------------------------------------------------
TRstrap = [];
TRstrap = catTri(TRstrap, TRa_conn);
TRstrap = catTri(TRstrap, TRb_conn);
TRstrap = catTri(TRstrap, TRa_bed);
TRstrap = catTri(TRstrap, TRb_bed);
if useRings
    TRstrap = catTri(TRstrap, TRrings);
end
if holeDia>0
    TRstrap = catTri(TRstrap, TRstuds);
end



if ~isempty(TRstrap) && exist('remove_unreferenced','file')==2
    [V2,F2] = remove_unreferenced(TRstrap.Points, TRstrap.ConnectivityList);
    TRstrap = triangulation(F2,V2);
end
end

% ==================== helpers ====================

function v = getOr(s,f,def), if isfield(s,f)&&~isempty(s.(f)), v=s.(f); else, v=def; end, end

function P = pickAnchor(poly, yOff)
    [~,i] = min(poly(:,2)); base = poly(i,:);
    tgtY  = base(2) + yOff;
    [~,j] = min(abs(poly(:,2) - tgtY));
    P = poly(j,:);
end

function [Pa, Pb] = inferRailAnchorsFromTR(TRrails, yOff)
    V = TRrails.Points; X = V(:,1); Y = V(:,2);
    midX = median(X);
    Lmask = X < midX - 1e-6; Rmask = X > midX + 1e-6;
    if ~any(Lmask) || ~any(Rmask)
        [lab,~] = kmeans(X,2,'Replicates',3,'MaxIter',200);
        xm = [mean(X(lab==1)), mean(X(lab==2))];
        [~,iL] = min(xm); [~,iR] = max(xm);
        Lmask = (lab==iL); Rmask = (lab==iR);
    end
    YL = Y(Lmask); XL = X(Lmask); iLall = find(Lmask);
    [minYL,~] = min(YL); tgtYL = minYL + yOff; [~,kL] = min(abs(YL - tgtYL));
    Pa = [XL(kL), YL(kL), V(iLall(kL),3)];

    YR = Y(Rmask); XR = X(Rmask); iRall = find(Rmask);
    [minYR,~] = min(YR); tgtYR = minYR + yOff; [~,kR] = min(abs(YR - tgtYR));
    Pb = [XR(kR), YR(kR), V(iRall(kR),3)];
end

function L = dropPathToXY(P, XYend, zBed, dropMM, sagFrac)
% 3-pt polyline: P -> bowed mid -> [XYend, zTouch]
    if isempty(dropMM), zTouch = zBed; else, zTouch = max(zBed, P(3)-dropMM); end
    A = P;
    C = [XYend(1), XYend(2), zTouch];
    % Bow slightly anterior (+Y) to avoid vertical overhang
    dy = max(8, 15);
    B = [ (P(1)+C(1))/2, (P(2)+C(2))/2 + sagFrac*dy, 0.5*(P(3)+zTouch) ];
    L = [A; B; C];
end

function TR = sweepRibbon(P, W, T)
    if size(P,1) < 2, TR = []; return; end
    Vtot = []; Ftot = []; off = 0;
    for k=1:size(P,1)-1
        a = P(k,:); b = P(k+1,:);
        seg = b - a; L = norm(seg); if L==0, continue; end
        t = seg / L;
        n = [0 0 1];
        w = cross(n,t); if norm(w)<1e-9, n=[1 0 0]; w=cross(n,t); end
        w = w/norm(w); n = cross(t,w); n=n/norm(n);
        halfW = 0.5*W; halfT = 0.5*T;
        ext = min(halfW, 0.25*L); a2 = a - ext*t; b2 = b + ext*t;
        v1 = a2 + (-halfW)*w + (-halfT)*n;
        v2 = a2 + ( halfW)*w + (-halfT)*n;
        v3 = a2 + ( halfW)*w + ( halfT)*n;
        v4 = a2 + (-halfW)*w + ( halfT)*n;
        v5 = b2 + (-halfW)*w + (-halfT)*n;
        v6 = b2 + ( halfW)*w + (-halfT)*n;
        v7 = b2 + ( halfW)*w + ( halfT)*n;
        v8 = b2 + (-halfW)*w + ( halfT)*n;
        V = [v1;v2;v3;v4;v5;v6;v7;v8];
        F = convhulln(V);
        Ftot = [Ftot; F+off]; Vtot = [Vtot; V]; off = size(Vtot,1);
    end
    TR = triangulation(Ftot, Vtot);
end

function TR = makeBedStrapX(P, zBed, sideSign, Lx, Wy, T, aheadY, marginX)
% Rectangular slab on bed oriented ALONG X.
% Centered anteriorly at y = P.y + aheadY; inner edge is marginX from anchor along ±X.
    yc = P(2) + aheadY;
    if sideSign < 0
        % Left strap extends toward -X; inner edge just left of anchor
        xInner = P(1) - abs(marginX);
        x1 = xInner - Lx;      % outer end
        x2 = xInner;           % inner edge (meets connector)
    else
        % Right strap extends toward +X; inner edge just right of anchor
        xInner = P(1) + abs(marginX);
        x1 = xInner;           % inner edge
        x2 = xInner + Lx;      % outer end
    end
    y1 = yc - Wy/2; y2 = yc + Wy/2;
    z1 = zBed;     z2 = zBed + T;

    V = [x1 y1 z1; x2 y1 z1; x2 y2 z1; x1 y2 z1; ...
         x1 y1 z2; x2 y1 z2; x2 y2 z2; x1 y2 z2];
    F = convhulln(V);
    TR = triangulation(F,V);
end

function [iaXY, ibXY] = innerEdgeCenters(TRa_bed, TRb_bed, sA, sB)
% Return inner-edge XY center for left/right bed straps (where connectors land).
    iaXY = edgeCenterXY(TRa_bed, sA);
    ibXY = edgeCenterXY(TRb_bed, sB);
end

function c = edgeCenterXY(TRslab, sideSign)
    V = TRslab.Points; bb = [min(V); max(V)];
    if sideSign < 0
        xInner = max(V(:,1));  % for left strap, inner edge at larger X
    else
        xInner = min(V(:,1));  % for right strap, inner edge at smaller X
    end
    yMid = 0.5*(bb(1,2)+bb(2,2));
    c = [xInner, yMid];
end

function C = holePatternCentersX(TRslab, pitch, edgeClr)
% Centers along the LONG axis X of the slab, on its midline in Y.
    V = TRslab.Points; bb = [min(V); max(V)];
    ymid = 0.5*(bb(1,2)+bb(2,2));
    x1   = bb(1,1) + edgeClr;
    x2   = bb(2,1) - edgeClr;
    if x2 <= x1, C = zeros(0,3); return; end
    xs = (x1:pitch:x2).';
    C  = [xs, repmat(ymid,numel(xs),1), repmat(bb(1,3),numel(xs),1)];
end

function TR = mushroomAt(c, zBed, baseT, stemDia, headDia, headThick, nSides)
    z0 = zBed + baseT;
    stemH = max(1.2*headThick, 1.8);
    TRstem = cylinderTri([c(1),c(2),z0], [c(1),c(2),z0+stemH], stemDia/2, nSides);
    TRhead = cylinderTri([c(1),c(2),z0+stemH], [c(1),c(2),z0+stemH+headThick], headDia/2, nSides);
    TR = catTri(TRstem, TRhead);
end

function TR = cylinderTri(p0, p1, r, n)
% Watertight cylinder with top/bottom caps, n-gon approximation.
    t = p1-p0; L = norm(t); if L==0, TR=[]; return; end
    t = t/L;
    a = [0 0 1]; if abs(dot(a,t))>0.9, a=[1 0 0]; end
    u = cross(t,a); u=u/norm(u); v = cross(t,u);

    ang = linspace(0,2*pi,n+1); ang(end)=[];
    ring0 = p0 + r*(u.*cos(ang)' + v.*sin(ang)');
    ring1 = p1 + r*(u.*cos(ang)' + v.*sin(ang)');

    V = [ring0; ring1; p0; p1];    % last two are centers
    iC0 = 2*n+1; iC1 = 2*n+2;

    F = [];

    % side faces
    for i=1:n
        i2 = mod(i,n)+1;
        F = [F; i, i2, n+i2;  i, n+i2, n+i]; %#ok<AGROW>
    end
    % bottom cap (fan, oriented outward)
    for i=1:n
        i2 = mod(i,n)+1;
        F = [F; iC0, i2, i]; %#ok<AGROW>
    end
    % top cap (fan)
    for i=1:n
        i2 = mod(i,n)+1;
        F = [F; iC1, n+i, n+i2]; %#ok<AGROW>
    end

    TR = triangulation(F,V);
end

function TR = catTri(A,B)
    if isempty(A), TR = B; return; end
    if isempty(B), TR = A; return; end
    VA = A.Points;  FA = A.ConnectivityList;
    VB = B.Points;  FB = B.ConnectivityList;
    if isempty(FA), TR = B; return; end
    if isempty(FB), TR = A; return; end
    V = [VA; VB];
    F = [FA; FB + size(VA,1)];
    TR = triangulation(F, V);
end

function ps = footprintFromCap(TRcap, zBed, band)
% Project the cap's intersection band with the bed plane to a robust XY footprint.
    V = TRcap.Points; Z = V(:,3);
    band = max(band, 0.2);
    I = abs(Z - zBed) <= band;
    if ~any(I), I = Z <= (min(Z)+band); end
    XY = V(I,1:2);
    if size(XY,1) < 3, error('footprintFromCap: not enough points near bed'); end
    K = convhull(XY(:,1), XY(:,2));
    ps = polyshape(XY(K,1), XY(K,2), 'Simplify', true);
end

function [xmin, xmax] = xSpanAtY(ps, yq)
% Intersect polygon boundary with the horizontal line y=yq; return min/max X.
    [xb,yb] = boundary(ps);  % NaN-separated
    xs = [];
    i0 = 1;
    for i = 1:numel(xb)
        if i==numel(xb) || isnan(xb(i))
            X = xb(i0:i-1); Y = yb(i0:i-1);
            n = numel(X);
            for j=1:n
                j2 = (j<n) * (j+1) + (j==n) * 1;
                y1 = Y(j); y2 = Y(j2);
                if (yq>=min(y1,y2)-1e-9) && (yq<=max(y1,y2)+1e-9) && abs(y2-y1)>1e-12
                    t = (yq - y1) / (y2 - y1);
                    if t>=-1e-12 && t<=1+1e-12
                        xs(end+1,1) = X(j) + t*(X(j2)-X(j)); %#ok<AGROW>
                    end
                end
            end
            i0 = i + 1;
        end
    end
    if isempty(xs)
        % if the scanline misses (e.g., just outside extent), clamp to bbox
        bb = ps.boundingbox; xmin = bb(1); xmax = bb(2);
    else
        xmin = min(xs); xmax = max(xs);
    end
end

function TR = makeBedStrapX_innerEdge(innerP, sideSign, Lx, Wy, T)
% Rectangle on Z=0, long axis along X, starting at innerP (touching head), extending outward.
    x0 = innerP(1); y0 = innerP(2); z0 = innerP(3);
    if sideSign < 0
        x1 = x0 - Lx; x2 = x0;
    else
        x1 = x0;      x2 = x0 + Lx;
    end
    y1 = y0 - Wy/2; y2 = y0 + Wy/2; z1 = z0; z2 = z0 + T;
    V = [x1 y1 z1; x2 y1 z1; x2 y2 z1; x1 y2 z1; ...
         x1 y1 z2; x2 y1 z2; x2 y2 z2; x1 y2 z2];
    F = convhulln(V);
    TR = triangulation(F,V);
end

function L = dropPathToXY_outward(P, XYend, zBed, dropMM, bowMM, sideSign)
% Polyline: anchor P -> bowed midpoint (outward in ±X) -> inner strap edge at zTouch.
    if isempty(dropMM), zTouch = zBed; else, zTouch = max(zBed, P(3)-dropMM); end
    A = P;
    C = [XYend(1), XYend(2), zTouch];
    mid = 0.5*(A + [C(1) C(2) zTouch]);
    B = [ mid(1) + sideSign*abs(bowMM), mid(2), mid(3) ];
    L = [A; B; C];
end

function seg = innerEdgeSegmentXZ(TRslab, sideSign)
% Return the inner-edge segment endpoints [x y z; x y z] on the bed.
    V = TRslab.Points;
    X = V(:,1); Y = V(:,2); Z = V(:,3);
    zBed = min(Z);                              % slab sits on bed
    tol = 1e-8;
    onBed = abs(Z - zBed) < tol;
    Vb = V(onBed,:); Xb = Vb(:,1); Yb = Vb(:,2);

    if sideSign < 0
        % LEFT strap: inner edge is at max X among bed verts
        xi = max(Xb);
    else
        % RIGHT strap: inner edge is at min X among bed verts
        xi = min(Xb);
    end
    % Collect near that X (form a vertical segment across the strap width)
    I = abs(Xb - xi) < 1e-6;
    yLo = min(Yb(I)); yHi = max(Yb(I));
    seg = [xi yLo zBed; xi yHi zBed];           % two endpoints on bed
end

function TR = hingeConnectorWall(TRcap, seg, sideSign, thick, stepMM, zCut, maxRise, zBed)
% Build a thin wall along 'seg' (on bed), rising outside the head.
% 'sideSign' = -1 (left → outward -X), +1 (right → outward +X)

    % --- sample along inner edge on the bed
    P0 = seg(1,:); P1 = seg(2,:);
    L  = hypot(P1(1)-P0(1), P1(2)-P0(2));
    nS = max(2, ceil(L / max(stepMM, 1e-6)));
    t  = linspace(0,1,nS).';
    XY = (1-t).*P0(1:2) + t.*P1(1:2);

    % --- snap upward to scalp (nearest-in-XY, excluding underside)
    [top3D, ~] = snapXY_to_mesh_nonbottom(TRcap, XY, zCut);

    % clamp rise to maxRise
    zTop = min(top3D(:,3), zBed + maxRise);
    top3D(:,3) = zTop;

    % --- build bottom/top polylines and outward offset
    bot_in  = [XY, zBed*ones(nS,1)];
    top_in  = top3D;

    eOut = [sideSign, 0, 0];                   % outward along ±X
    eOut = eOut / norm(eOut);
    bot_out = bot_in + thick * eOut;
    top_out = top_in + thick * eOut;

    V = []; F = [];

    % helper to append a quad strip (A→B) as two triangles per span
    function [V,F] = appendStrip(V,F,A,B)
        for i = 1:size(A,1)-1
            a1 = A(i,:);   a2 = A(i+1,:);
            b1 = B(i,:);   b2 = B(i+1,:);
            base = size(V,1);
            V = [V; a1; a2; b2; b1];        % 4 verts
            % two tris: (a1,a2,b2) and (a1,b2,b1)
            F = [F; base+(1) base+(2) base+(3); ...
                     base+(1) base+(3) base+(4)];
        end
    end

    % inner face (against scalp), outer face, bottom (bed), top (cap-side)
    [V,F] = appendStrip(V,F, bot_in,  top_in);
    [V,F] = appendStrip(V,F, bot_out, top_out);
    [V,F] = appendStrip(V,F, bot_in,  bot_out);
    [V,F] = appendStrip(V,F, top_in,  top_out);

    % end caps to close the wall (two quads → two tris each)
    function [V,F] = appendCap(V,F,p1,p2,p3,p4)
        base = size(V,1);
        V = [V; p1; p2; p3; p4];
        F = [F; base+(1) base+(2) base+(3); ...
                 base+(1) base+(3) base+(4)];
    end

    % first cap (index 1), last cap (index end)
    [V,F] = appendCap(V,F, bot_in(1,:), bot_out(1,:), top_out(1,:), top_in(1,:));
    [V,F] = appendCap(V,F, bot_in(end,:), bot_out(end,:), top_out(end,:), top_in(end,:));

    TR = triangulation(F,V);
end


function [P3, vidx] = snapXY_to_mesh_nonbottom(TR, P2, zCutMM)
% Nearest-in-XY among vertices with Z >= minZ + zCutMM
    V = TR.Points; XY = V(:,1:2); Z = V(:,3);
    mask = Z >= (min(Z) + zCutMM);
    XYf  = XY(mask,:);
    idxKeep = find(mask);
    kdt = createns(XYf,'NSMethod','kdtree');
    iLocal = knnsearch(kdt, P2);
    vidx   = idxKeep(iLocal);
    P3     = V(vidx,:);
end

function TR = prismConnectorBlock(seg, sideSign, thick, height, leanDeg)
% Build a single rectangular prism attached to the strap's inner edge on Z=0.
% seg: [2x3] endpoints of inner edge on the bed plane
% sideSign: -1 (left → outward -X), +1 (right → outward +X)
% thick: prism thickness (outward along ±X)
% height: prism height (up from bed)
% leanDeg: small outward tilt (degrees), optional

    P0 = seg(1,:); P1 = seg(2,:);
    % Edge direction along strap short side (roughly ±Y)
    eY = P1 - P0; eY(3) = 0;
    if norm(eY) < 1e-12
        TR = []; return;
    end
    eY = eY / norm(eY);

    % Outward direction ±X (world frame); if you prefer to derive from normals, swap here
    eOut = [sideSign, 0, 0];
    eOut = eOut / norm(eOut);

    % Vertical
    eZ = [0, 0, 1];

    % Lean: shift TOP face outward by tan(leanDeg) * height
    outShift = tan(deg2rad(leanDeg)) * height;

    % Corner points (8 verts)
    % Bottom inner edge (on bed)
    v1 = P0;                           % (inner, one end)
    v2 = P1;                           % (inner, other end)
    % Bottom outer edge
    v3 = v2 + thick*eOut;
    v4 = v1 + thick*eOut;

    % Top inner edge (rise straight up + optional outward lean)
    v5 = v1 + height*eZ + outShift*eOut;
    v6 = v2 + height*eZ + outShift*eOut;
    % Top outer edge
    v7 = v6 + thick*eOut;
    v8 = v5 + thick*eOut;

    V = [v1; v2; v3; v4; v5; v6; v7; v8];

    % Faces (two triangles per face)
    F = [ ...
        1 2 3; 1 3 4;     % bottom
        5 8 7; 5 7 6;     % top
        1 5 6; 1 6 2;     % inner face
        4 3 7; 4 7 8;     % outer face
        1 4 8; 1 8 5;     % side cap 1
        2 6 7; 2 7 3];    % side cap 2

    TR = triangulation(F,V);
end

function TR = makePerforatedBedStrapX_innerEdge(innerP, sideSign, Lx, Wy, T, holeCenters, holeDia)
% Rectangle along X with circular holes, extruded from z to z+T.

    % Build the outer rectangle corners on Z = innerP(3)
    x0 = innerP(1); y0 = innerP(2); z0 = innerP(3);
    if sideSign < 0, x1 = x0 - Lx; x2 = x0; else, x1 = x0; x2 = x0 + Lx; end
    y1 = y0 - Wy/2; y2 = y0 + Wy/2;

    outer = [x1 y1; x2 y1; x2 y2; x1 y2];
    ps = polyshape(outer,'Simplify',true);

    % Subtract circular holes (as n-gon approximations)
    r = holeDia/2; n = 36;
    if ~isempty(holeCenters)
        for i=1:size(holeCenters,1)
            cx = holeCenters(i,1); cy = holeCenters(i,2);
            ang = linspace(0,2*pi,n+1)'; ang(end)=[];
            circ = [cx + r*cos(ang), cy + r*sin(ang)];
            ps = subtract(ps, polyshape(circ,'Simplify',true));
        end
    end

    % Triangulate the 2D region
    TR2 = triangulation(ps);         % OK: single output
    TF  = TR2.ConnectivityList;      % 2D faces
    PV  = TR2.Points(:,1:2);         % 2D vertices

    % Build 3D prism: bottom/top triangles + side walls along all boundaries
    VB = [PV, z0*ones(size(PV,1),1)];
    VT = [PV, (z0+T)*ones(size(PV,1),1)];

    % Bottom faces (as triangles), oriented downward; top faces oriented upward
    Fbot = TF;                 % uses VB
    Ftop = fliplr(TF) + size(VB,1);  % uses VT

    % Side walls: walk each boundary ring (outer + holes)
    [xb,yb] = boundary(ps);  % NaN-separated loops
    V = [VB; VT];
    F = [Fbot; Ftop];
    function addWallLoop(xloop,yloop)
        idx2D = map2DVerts(PV, xloop, yloop);
        % connect segment i->i+1 into two quads (bottom-top)
        for k=1:numel(idx2D)-1
            a = idx2D(k); b = idx2D(k+1);
            aT = a + size(VB,1); bT = b + size(VB,1);
            % quad (a,b,bT,aT) → two triangles
            F = [F; a b bT; a bT aT]; %#ok<AGROW>
        end
    end
    i0 = 1;
    for i=1:numel(xb)
        if i==numel(xb) || isnan(xb(i))
            if i-1 >= i0
                addWallLoop(xb(i0:i-1), yb(i0:i-1));
            end
            i0 = i+1;
        end
    end

    TR = triangulation(F, V);
end

function idx = map2DVerts(PV, xloop, yloop)
% Map polyline vertices to PV rows (exact coords)
    idx = zeros(numel(xloop),1);
    for k=1:numel(xloop)
        i = find(abs(PV(:,1)-xloop(k))<1e-10 & abs(PV(:,2)-yloop(k))<1e-10, 1);
        if isempty(i)
            % fallback: nearest (robust to floating point)
            [~,i] = min(hypot(PV(:,1)-xloop(k), PV(:,2)-yloop(k)));
        end
        idx(k) = i;
    end
    % close loop explicitly for wall stitching
    if idx(end)~=idx(1), idx(end+1)=idx(1); end
end

function TRtmp = TRa_bed_placeholder(xInner, yC, zBed, Lx, Wy, T, sideSign)
    % Just a rectangular slab (no holes); used only to compute hole centers.
    innerP = [xInner yC zBed];
    TRtmp = makeBedStrapX_innerEdge(innerP, sideSign, Lx, Wy, T);
end

function C = holeCentersRectX(x1, x2, ymid, edgeClr, pitch, z)
    % Centers along X on the midline y=ymid within [x1,x2], honoring edge clearance.
    xa = min(x1,x2) + edgeClr;
    xb = max(x1,x2) - edgeClr;
    if xb <= xa
        C = zeros(0,3);
        return;
    end
    xs = (xa:pitch:xb).';
    C  = [xs, repmat(ymid,numel(xs),1), repmat(z,numel(xs),1)];
end

function TR = addRingToStrapEnd(TRslab, sideSign, outerDia, tubeDia, neckLen, neckW, neckT, nU, nV, zBed)
% Place a torus (flat on bed) at the distal end of a rectangular strap,
% joined by a short rectangular neck. sideSign = -1 (left strap extends -X), +1 (right extends +X).

    V = TRslab.Points; bb = [min(V,[],1); max(V,[],1)];
    % Strap runs along X, free/distal end is minX for left, maxX for right
    if sideSign<0
        xFree = bb(1,1);
    else
        xFree = bb(2,1);
    end
    yMid = 0.5*(bb(1,2)+bb(2,2));

    % Neck: rectangular prism from strap end outward along ±X
    x1N = xFree;
    x2N = xFree + sideSign*neckLen;
    y1N = yMid - neckW/2;
    y2N = yMid + neckW/2;
    z1N = zBed;
    z2N = zBed + neckT;
    Vneck = [x1N y1N z1N; x2N y1N z1N; x2N y2N z1N; x1N y2N z1N; ...
             x1N y1N z2N; x2N y1N z2N; x2N y2N z2N; x1N y2N z2N];
    Fneck = convhulln(Vneck);
    TRneck = triangulation(Fneck, Vneck);

    ringOverlapMM = 3;                 % how much ring intrudes over the strap

    % Torus (flat on bed; axis = +Z); place center just beyond neck end
    R = 0.5*outerDia - 0.5*tubeDia;    % major radius (center to tube center)
    r = 0.5*tubeDia;                   % minor radius (tube radius)
    cx = x2N + sideSign*(R - ringOverlapMM);  % was: cx = x2N + sideSign*R
    cy = yMid;
    cz = zBed + r;                     % torus just touches bed
    TRtor = torusTri([cx, cy, cz], R, r, nU, nV);

    TR = catTri(TRneck, TRtor);
end

function TR = torusTri(center, R, r, nU, nV)
% Watertight torus centered at 'center' with major radius R and minor r.
% Axis along +Z (lies flat on bed). nU (major), nV (minor) segments.

    if nargin<4, nU=72; end
    if nargin<5, nV=36; end
    cx=center(1); cy=center(2); cz=center(3);

    u = linspace(0, 2*pi, nU+1); u(end)=[];
    v = linspace(0, 2*pi, nV+1); v(end)=[];
    [U,V] = meshgrid(u,v); U=U.'; V=V.'; % size nU x nV

    % Parametric surface (Z-axis torus)
    X = (R + r.*cos(V)) .* cos(U) + cx;
    Y = (R + r.*cos(V)) .* sin(U) + cy;
    Z =  r .* sin(V) + cz;

    % Build faces with wrap-around (quad split into two tris)
    % index helper
    idx = @(i,j) (j-1)*nU + i;
    Vtx = [X(:) Y(:) Z(:)];
    Fac = zeros(2*nU*nV, 3);
    f = 1;
    for j=1:nV
        j2 = (mod(j,nV))+1;
        for i=1:nU
            i2 = (mod(i,nU))+1;
            a = idx(i ,j );
            b = idx(i2,j );
            c = idx(i2,j2);
            d = idx(i ,j2);
            Fac(f,:)   = [a b c]; f=f+1;
            Fac(f,:)   = [a c d]; f=f+1;
        end
    end
    TR = triangulation(Fac, Vtx);
end
