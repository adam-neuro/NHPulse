function [targets, nearestInd, infoOut] = autoElectrodeTargets(TRcap, nElectrodes, opts)
% opts.placementMode selects 'footprintCvt' (legacy default),
% 'surfaceGeodesic' (crop-rim-aware mesh sampling), or 'surfaceVoronoi'
% (coverage-aware centroidal Voronoi placement constrained to legal vertices).
%
% surfaceGeodesic options:
%   .edgeMarginMM          geodesic crop-rim exclusion [10]
%   .bedMarginMM           direct printer-bed exclusion [2]
%   .bottomFaceBandMM      fabricated-base detection band [1.5]
%   .normalUpDotMin        optional surface-normal filter [[]]
%   .normalMode            'vertex' or 'smooth' for normalUpDotMin ['vertex']
%   .normalSmoothRadiusMM  radius for smoothed normal filter [6]
%   .visibleFromAbove      optional legacy-style visibility filter [false]
%   .preferSymmetry        place bilateral reflected pairs when possible [true]
%   .mirrorSnapWarnMM      warn when a mirrored partner moves too far [5]
%   .midlineMarginMM       lateral X margin for reflected pairs [edgeMarginMM]
%   .exclusionCenters      additional N x 3 exclusion centers [zeros(0,3)]
%   .exclusionRadiusMM     scalar or N x 1 radii for exclusionCenters [[]]
%   .customExclusionVertexInd mesh vertex rows to exclude [[]]
%   .vizSurfaceGeodesic    show candidate/rim QC [false]
%   .voronoiIterations     surfaceVoronoi refinement iterations [10]
%   .voronoiToleranceMM    stop when seed motion is below this [0.25]
%   .voronoiSnapMode       'spacingAware' or 'centroid' ['spacingAware']
%   .voronoiSpacingWeight  nearest-neighbor spacing penalty weight [4]
%   .voronoiMinSpacingFraction min NN spacing as fraction of equal-area spacing [0.75]
%   .voronoiSpacingIterations coordinate-descent spacing refinement sweeps [3]
%   .voronoiMaxCandidatesPerCell snap candidates kept per cell [80]
%   .vizSurfaceVoronoi     show surface Voronoi QC [vizSurfaceGeodesic]
% AUTOELECTRODETARGETS – Axis-aligned ellipse (constrained grid search) + CVT + projection/snap.
%
% Steps:
%  1) XY convex hull
%  2) Axis-aligned ellipse fit by bounded grid search (RMS Euclidean distance to boundary)
%  3) Ear exclusions via oblique lines (two points each; half-planes)
%  4) Headpost exclusion (disk at [x,y], radius)
%  5) Even electrode distribution via Lloyd CVT on RIGHT-half of allowed region, then mirror
%  6) Project from above (choose max-Z among nearest XY vertices)
%  7) Snap to nearest mesh vertex (done in 6)
%
% Inputs:
%   TRcap         triangulation with Z up
%   nElectrodes   integer
%   opts fields (all optional):
%     .earRightLine     [2x2]  (x,y) points; exclude RIGHT of line
%     .earLeftLine      [2x2]  (x,y) points; exclude LEFT  of line
%     .headpostCenter   [1x2]  default [0 0]
%     .headpostRadius   scalar default 30
%     .viz2D            logical default true
%     .viz3D            logical default false
%     .lloydIters       integer default 30
%     .samplesPerSite   integer default 600
%     .ellipseGrid      struct with fields:
%         .axMin=40, .axMax=75, .axN=15      % semi-axis along x (mm)
%         .ayMin=50, .ayMax=100, .ayN=15     % semi-axis along y (mm)
%         .cxRad=12, .cyRad=12               % center search radius (mm) around centroid
%         .cN=9                               % #grid steps per axis for center offsets
%
% Outputs:
%   targets  [nElectrodes x 3]
%   vidx     [nElectrodes x 1]
%   infoOut  struct with footprint, ellipse, regions, and 2D points

    if nargin < 3, opts = struct; end
    opts = setDefault(opts,'placementMode','footprintCvt');
    placementMode = normalizePlacementMode(opts.placementMode);
    if strcmp(placementMode, 'surfaceGeodesic')
        [targets, nearestInd, infoOut] = surfaceGeodesicTargets( ...
            TRcap, nElectrodes, opts);
        return;
    end
    if strcmp(placementMode, 'surfaceVoronoi')
        [targets, nearestInd, infoOut] = surfaceVoronoiTargets( ...
            TRcap, nElectrodes, opts);
        return;
    end
    opts = setDefault(opts,'headpostCenter',[0 0]);
    opts = setDefault(opts,'headpostRadius',10);
    opts = setDefault(opts,'viz2D',false);
    opts = setDefault(opts,'viz3D',false);
    opts = setDefault(opts,'lloydIters',30);
    opts = setDefault(opts,'samplesPerSite',600);
    opts = setDefault(opts,'acceptanceShrinkPct', 0.1);  % 0.0–0.9 typical
    if ~isfield(opts,'ellipseGrid') || isempty(opts.ellipseGrid)
        eg = struct('axMin',40,'axMax',75,'axN',15, ...
                    'ayMin',50,'ayMax',100,'ayN',15, ...
                    'cxRad',12,'cyRad',12,'cN',9);
        opts.ellipseGrid = eg;
    end

    V = TRcap.Points; X = V(:,1); Y = V(:,2); Z = V(:,3);

    % (1) XY convex hull
    K = convhull(X,Y);
    hullXY = [X(K) Y(K)];

    % (2) Axis-aligned ellipse fit by constrained grid search (RMS Euclidean)
    E = fitEllipseAxisAlignedGrid(hullXY(:,1), hullXY(:,2), opts.ellipseGrid);
    % ellipse curve for viz
    t = linspace(0, 2*pi, 400);
    ellXY = [E.cx + E.ax*cos(t); E.cy + E.ay*sin(t)]';

    % Build ellipse poly (for clipping)
    ellipsePoly = polyshape(ellXY(:,1), ellXY(:,2));

    region = ellipsePoly;

    % ----- Ear exclusions: build a single right triangle for each side -----
    earPolys = {};
    if isfield(opts,'earLeftLine') && ~isempty(opts.earLeftLine)
        earPolys{end+1} = earTrianglePoly(opts.earLeftLine, 'left', ellipsePoly);
    end
    if isfield(opts,'earRightLine') && ~isempty(opts.earRightLine)
        earPolys{end+1} = earTrianglePoly(opts.earRightLine, 'right', ellipsePoly);
    end

    % NEW: shrink toward centroid by a percentage (if requested)
    if opts.acceptanceShrinkPct > 0
        region = shrinkPolyTowardsCentroid(region, opts.acceptanceShrinkPct);
        if region.NumRegions == 0 || area(region) == 0
            warning('acceptanceShrinkPct too large; region collapsed. Reverting to unshrunk region.');
            % fall back to unshrunk region
            region = ellipsePoly;
            for i = 1:numel(earPolys)
                region = subtract(region, earPolys{i});
            end
        end
    end

    % Allowed region
    region = ellipsePoly;
    for i=1:numel(earPolys)
        region = subtract(region, earPolys{i});
    end

    % (4) Headpost exclusion
    th = linspace(0,2*pi,200);
    hpC = opts.headpostCenter(:).';
    hpR = opts.headpostRadius;
    hpXY = hpC + [hpR*cos(th).' hpR*sin(th).'];
    headpostPoly = polyshape(hpXY(:,1), hpXY(:,2));

    % Allowed region
    region = subtract(region, headpostPoly);
    if region.NumRegions == 0 || area(region) == 0
        error('autoElectrodeTargets:EmptyRegion','Allowed region empty after exclusions.');
    end

    % Right-half region (x >= E.cx)
    [xl, yl] = boundingbox(region);
    span = max(diff(xl), diff(yl));
    bigRectR = polyshape([E.cx xl(2)+span xl(2)+span E.cx], [yl(1)-span yl(1)-span yl(2)+span yl(2)+span]);
    regionR = intersect(region, bigRectR);
    if regionR.NumRegions == 0 || area(regionR) == 0
        error('autoElectrodeTargets:EmptyRight','Right-half allowed region empty.');
    end

    % (5) CVT on right-half, mirror for symmetry
    nPairs = floor(nElectrodes/2);
    hasMid = mod(nElectrodes,2) == 1;

    NsR = max(2000, nPairs * opts.samplesPerSite);
    ptsR = randPointsInPolygon(regionR, NsR);

    % Initialize right seeds near uniform
    if nPairs > 0
        Pr = ptsR(randperm(size(ptsR,1), nPairs), :);
    else
        Pr = zeros(0,2);
    end

    % Midline seed (x = E.cx) if odd
    if hasMid
        bandW = max(1.0, 0.01*diff(yl));
        NsM = max(1500, opts.samplesPerSite);
        ptsAll = randPointsInPolygon(region, NsM);
        nearMid = abs(ptsAll(:,1) - E.cx) <= bandW;
        if any(nearMid)
            P0 = [E.cx, mean(ptsAll(nearMid,2))];
            if ~isinterior(region, P0(1), P0(2)), P0 = pullInside(region, P0); end
        else
            cR = centroid(region);
            P0 = [E.cx, cR(2)];
            if ~isinterior(region, P0(1), P0(2)), P0 = pullInside(region, P0); end
        end
    else
        P0 = zeros(0,2);
    end

    for it=1:opts.lloydIters
        P = [Pr; P0; mirrorAcrossX(P0, E.cx); mirrorAcrossX(Pr, E.cx)];
        if ~isempty(ptsR)
            D = pdist2(ptsR, P);
            [~, lab] = min(D, [], 2);
        else
            lab = [];
        end
        % Update right seeds
        for i=1:nPairs
            idxR = i;
            idxL = nPairs + hasMid + 1 + (i-1); % after [Pr; P0; mirror(P0); mirror(Pr)]
            sel = (lab == idxR) | (lab == idxL);
            if any(sel)
                Q = ptsR(sel,:);
                maskL = (lab(sel) == idxL);
                Q(maskL,:) = mirrorAcrossX(Q(maskL,:), E.cx);
                c = mean(Q,1);
                if ~isinterior(regionR, c(1), c(2)), c = pullInside(regionR, c); end
                Pr(i,:) = c;
            else
                Pr(i,:) = ptsR(randi(size(ptsR,1)), :);
            end
        end
        % Update midline seed
        if hasMid
            idxM = nPairs + 1;
            selM = (lab == idxM);
            if any(selM)
                c = mean(ptsR(selM,:), 1); c(1) = E.cx;
                if ~isinterior(region, c(1), c(2)), c = pullInside(region, c); end
                P0 = c;
            else
                cR = centroid(region);
                P0 = 0.5*P0 + 0.5*[E.cx, cR(2)];
                if ~isinterior(region, P0(1), P0(2)), P0 = pullInside(region, P0); end
            end
        end
    end

    P2D = [Pr; P0; mirrorAcrossX(Pr, E.cx)];
    if size(P2D,1) > nElectrodes
        P2D = P2D(1:nElectrodes,:); % paired order preserved
    end

    % (6–7) Project from above & snap to mesh vertices: pick max-Z among K nearest by XY
    XY = V(:,1:2);
    XY(V(:,3)<1,:) = inf;
    d = pdist2(XY,P2D);
    [~,nearestInd] = min(d);
    targets = V(nearestInd,:);

    % Output info (not shadowing built-ins)
    infoOut = struct();
    infoOut.placementMode = placementMode;
    infoOut.hullXY       = hullXY;
    infoOut.ellipseCurve = ellXY;
    infoOut.ellipse      = E;           % cx,cy,ax,ay
    infoOut.region       = region;
    infoOut.regionR      = regionR;
    infoOut.earPolys     = earPolys;
    infoOut.headpostPoly = headpostPoly;
    infoOut.P2D          = P2D;

    % 2D viz
    if opts.viz2D
        figure('Name','autoElectrodeTargets – 2D footprint','Color','w'); hold on;
        plot(hullXY(:,1), hullXY(:,2), 'k-', 'LineWidth',1.1);
        plot(ellXY(:,1),  ellXY(:,2),  'r-', 'LineWidth',1.3);
        plot(region, 'FaceColor',[0.90 0.92 1.00], 'FaceAlpha',0.55, 'EdgeColor','none');
        plot(headpostPoly, 'FaceColor','b', 'FaceAlpha',0.22, 'EdgeColor','none');
        for i=1:numel(earPolys)
            plot(earPolys{i}, 'FaceColor',[1 0 1], 'FaceAlpha',0.15, 'EdgeColor','none');
        end
        scatter(P2D(:,1), P2D(:,2), 60, 'k', 'filled');
        xlim([-80 80]); ylim([-80 80]);
        axis equal; xlabel('X (mm)'); ylabel('Y (mm)');
        title('Ellipse footprint with exclusions and electrode positions');
        hold off;
    end

    % 3D viz
    if opts.viz3D
        figure('Name','autoElectrodeTargets – 3D overlay','Color','w'); hold on;
        trisurf(TRcap,'FaceColor',[0.88 0.90 0.95],'EdgeColor','none'); axis equal off;
        camlight; lighting gouraud;
        plot3(targets(:,1), targets(:,2), targets(:,3), 'k.', 'MarkerSize',22);
        title('Electrodes on scalp mesh');
        hold off;
    end
end

% -------------------- helpers --------------------

function S = setDefault(S, f, v)
    if ~isfield(S,f) || isempty(S.(f)), S.(f) = v; end
end

function E = fitEllipseAxisAlignedGrid(x, y, eg)
% Constrained, axis-aligned ellipse: center near centroid, ax,ay in bounded ranges.
% Score = RMS Euclidean distance to closest boundary point (per-point Newton).
    cx0 = mean(x); cy0 = mean(y);
    axGrid = linspace(eg.axMin, eg.axMax, eg.axN);
    ayGrid = linspace(eg.ayMin, eg.ayMax, eg.ayN);
    cGridX = linspace(cx0 - eg.cxRad, cx0 + eg.cxRad, eg.cN);
    cGridY = linspace(cy0 - eg.cyRad, cy0 + eg.cyRad, eg.cN);

    best = inf; E = struct('cx',cx0,'cy',cy0,'ax',mean(axGrid),'ay',mean(ayGrid));
    P = [x(:), y(:)];
    for cx = cGridX
        for cy = cGridY
            % Fast reject: ensure hull bbox is not wildly outside ellipse bbox
            % (soft check; still compute score).
            for ax = axGrid
                for ay = ayGrid
                    rmsd = rmsDistanceEllipseAxis(P, cx, cy, ax, ay);
                    if rmsd < best
                        best = rmsd;
                        E.cx = cx; E.cy = cy; E.ax = ax; E.ay = ay;
                    end
                end
            end
        end
    end
end

function rmsd = rmsDistanceEllipseAxis(P, cx, cy, ax, ay)
% RMS Euclidean distance from points P(:,1:2) to the closest point on ellipse
% (x-cx)^2/ax^2 + (y-cy)^2/ay^2 = 1, axis-aligned. Newton per point (5–8 iters).
    u = P(:,1) - cx; v = P(:,2) - cy;
    % initial t via Anderson approximation: t0 = atan2(ay*v, ax*u)
    t = atan2(ay*v, ax*u);
    for k = 1:8
        ct = cos(t); st = sin(t);
        Ex = ax*ct; Ey = ay*st;
        dx = Ex - u; dy = Ey - v;
        % derivatives w.r.t t
        Ex_p = -ax*st; Ey_p =  ay*ct;
        Ex_pp = -ax*ct; Ey_pp = -ay*st;
        g  = dx.*Ex_p + dy.*Ey_p;
        gp = Ex_p.^2 + Ey_p.^2 + dx.*Ex_pp + dy.*Ey_pp;
        t  = t - g ./ max(gp, 1e-12);
    end
    ct = cos(t); st = sin(t);
    Ex = ax*ct; Ey = ay*st;
    d2 = (Ex - u).^2 + (Ey - v).^2;
    rmsd = sqrt(mean(d2));
end

function polyHP = earHalfPlanePoly(line2, side, clipTo)
% Half-plane polygon clipped around clipTo’s bbox. side='right' keeps the right-of-line
% excluded region (we subtract it), 'left' keeps the left-of-line excluded region.
    [xl, yl] = boundingbox(clipTo);
    span = max(diff(xl), diff(yl));
    M = 3*span + 10;
    R = [xl(1)-M yl(1)-M;
         xl(2)+M yl(1)-M;
         xl(2)+M yl(2)+M;
         xl(1)-M yl(2)+M];
    P = clipPolygonWithHalfPlane(R, line2, side);
    polyHP = polyshape(P(:,1), P(:,2));
end

function Pout = clipPolygonWithHalfPlane(Pin, line2, side)
% Sutherland–Hodgman clip of polygon Pin by a single half-plane.
    p1 = line2(1,:); p2 = line2(2,:);
    d  = p2 - p1;
    crossVal = @(p) (d(1)*(p(:,2)-p1(2)) - d(2)*(p(:,1)-p1(1)));
    keepFun  = @(p) crossVal(p) < 0; % 'right' side default
    if strcmpi(side,'left'), keepFun = @(p) crossVal(p) > 0; end
    P = Pin; out = zeros(0,2); n = size(P,1);
    for i=1:n
        S = P(i,:); E = P(mod(i,n)+1,:);
        inS = keepFun(S); inE = keepFun(E);
        if inS && inE
            out(end+1,:) = E; %#ok<AGROW>
        elseif inS && ~inE
            I = segmentLineIntersection(S,E,p1,p2);
            if all(isfinite(I)), out(end+1,:) = I; end
        elseif ~inS && inE
            I = segmentLineIntersection(S,E,p1,p2);
            if all(isfinite(I)), out(end+1,:) = I; end
            out(end+1,:) = E;
        end
    end
    if size(out,1) < 3, out = Pin(1:min(3,end),:); end
    Pout = out;
end

function Q = mirrorAcrossX(P, x0)
    Q = P; Q(:,1) = 2*x0 - Q(:,1);
end

function P = randPointsInPolygon(poly, N)
    [xl, yl] = boundingbox(poly);
    P = zeros(0,2); maxTries = N*200; c = 0;
    while size(P,1) < N && c < maxTries
        xr = xl(1) + (xl(2)-xl(1))*rand(N,1);
        yr = yl(1) + (yl(2)-yl(1))*rand(N,1);
        in = isinterior(poly, xr, yr);
        P = [P; [xr(in) yr(in)]]; %#ok<AGROW>
        if size(P,1) > N, P = P(1:N,:); end
        c = c + N;
    end
    if size(P,1) < N
        warning('randPointsInPolygon:FilledOnly %d/%d samples', size(P,1), N);
    end
end

function pIn = pullInside(poly, p)
    c = centroid(poly); pIn = p;
    for k=1:40
        if isinterior(poly, pIn(1), pIn(2)), return; end
        pIn = 0.5*(pIn + c);
    end
    pIn = c;
end

function [xlim, ylim] = polyBounds(ps)
    v = ps.Vertices;
    xlim = [min(v(:,1)), max(v(:,1))];
    ylim = [min(v(:,2)), max(v(:,2))];
end

function rect = bigRectAround(poly, scale)
    if nargin<2 || isempty(scale), scale = 3; end
    [xlim, ylim] = polyBounds(poly);
    span = max(diff(xlim), diff(ylim));
    m = scale*span + 10;
    rect = [xlim(1)-m, ylim(1)-m;
            xlim(2)+m, ylim(1)-m;
            xlim(2)+m, ylim(2)+m;
            xlim(1)-m, ylim(2)+m];
end

function P = earTrianglePoly(line2, side, clipTo)
% Build a RIGHT TRIANGLE whose hypotenuse is exactly the given line,
% and whose legs lie on the vertical and horizontal lines through a chosen
% rectangle corner on the excluded side of the line.
% side='left'  → exclude points LEFT  of p1→p2
% side='right' → exclude points RIGHT of p1→p2

    % Big rectangle around ellipse
    R = bigRectAround(clipTo, 3);
    corners = [R(1,:); R(2,:); R(3,:); R(4,:)];
    p1 = line2(1,:); p2 = line2(2,:);

    % Orientation test (cross > 0 means LEFT of the line)
    d = p2 - p1;
    crossVal = @(p) (d(1)*(p(:,2)-p1(2)) - d(2)*(p(:,1)-p1(1)));
    sgn = crossVal(corners);

    if strcmpi(side,'left')
        mask = sgn > 0;
        if ~any(mask), mask = sgn >= 0; end
        [~,ix] = max(sgn .* (sgn>=0));   % deepest into left half-plane
    else
        mask = sgn < 0;
        if ~any(mask), mask = sgn <= 0; end
        [~,ix] = max((-sgn) .* (sgn<=0)); % deepest into right half-plane
    end

    C = corners(ix,:);                % chosen corner (right angle)
    xc = C(1); yc = C(2);

    % Robust slope/intercepts (nudge near-degenerate lines)
    dx = p2(1)-p1(1); dy = p2(2)-p1(2);
    epsSlope = 1e-9;
    if abs(dx) < epsSlope && abs(dy) < epsSlope
        error('earTrianglePoly: line points are identical.');
    end
    if abs(dx) < epsSlope
        % Nearly vertical: nudge x2 a hair to make slope finite
        dx = sign(dx + (dx==0))*epsSlope;
    end
    m  = dy/dx; 
    b  = p1(2) - m*p1(1);
    if abs(m) < epsSlope
        % Nearly horizontal: nudge slope slightly
        m = epsSlope; b = p1(2) - m*p1(1);
    end

    % Intersections of ear line with the two axis lines through C:
    % 1) with vertical line x = xc  →  y = m*xc + b
    y_v = m*xc + b;
    I_v = [xc, y_v];

    % 2) with horizontal line y = yc → x = (yc - b)/m
    x_h = (yc - b)/m;
    I_h = [x_h, yc];

    % Right-triangle vertices: [corner, vertical-intersection, horizontal-intersection]
    tri = [C; I_v; I_h];

    % Ensure consistent winding (optional)
    P = polyshape(tri(:,1), tri(:,2));
end

function I = segmentLineIntersection(S,E,p1,p2)
% Intersection of segment S->E with the infinite line through p1->p2.
    a = E - S; d = p2 - p1;
    denom = d(1)*a(2) - d(2)*a(1);
    if abs(denom) < 1e-12, I = [NaN NaN]; return; end
    t = ( d(1)*(S(2)-p1(2)) - d(2)*(S(1)-p1(1)) ) / denom;
    I = S + t*a;
end

function psOut = shrinkPolyTowardsCentroid(psIn, pct)
% Pull polygon inward toward its centroid by a percentage of radial distance.
% pct in [0,1). Example: pct=0.1 → 10% shrink.
    pct = max(0,min(0.99,pct));
    if pct == 0 || psIn.NumRegions == 0 || area(psIn) == 0
        psOut = psIn; return;
    end

    % Union centroid (works for multi-region)
    [cx,cy] = centroid(psIn); 
    k = 1 - pct;

    % Extract all boundary paths (NaN-separated)
    [xb, yb] = boundary(psIn);
    if isempty(xb)
        psOut = psIn; return;
    end

    % Scale each contiguous path about centroid
    xi = []; yi = [];
    startIdx = 1;
    for i = 1:numel(xb)+1
        if i==numel(xb)+1 || isnan(xb(i))
            segX = xb(startIdx:i-1);
            segY = yb(startIdx:i-1);
            if ~isempty(segX)
                segX = cx + k*(segX - cx);
                segY = cy + k*(segY - cy);
                % close if not closed
                if segX(1) ~= segX(end) || segY(1) ~= segY(end)
                    segX(end+1) = segX(1); %#ok<AGROW>
                    segY(end+1) = segY(1); %#ok<AGROW>
                end
                xi = [xi; segX; NaN]; %#ok<AGROW>
                yi = [yi; segY; NaN]; %#ok<AGROW>
            end
            startIdx = i + 1;
        end
    end
    % Build new polyshape from the scaled paths
    psOut = polyshape(xi, yi, 'Simplify', true);
    % In degenerate cases Simplify can erase tiny slivers; guard
    if psOut.NumRegions == 0 || area(psOut) == 0
        psOut = psIn; % revert if collapsed
    end
end

function mode = normalizePlacementMode(mode)
    mode = lower(strtrim(char(mode)));
    switch mode
        case {'footprintcvt', 'footprint', 'legacy', 'dropdown', 'projected'}
            mode = 'footprintCvt';
        case {'surfacegeodesic', 'surface', 'geodesic'}
            mode = 'surfaceGeodesic';
        case {'surfacevoronoi', 'voronoi', 'surfacecvt', 'geodesicvoronoi'}
            mode = 'surfaceVoronoi';
        otherwise
            error('autoElectrodeTargets:BadPlacementMode', ...
                ['placementMode must be ''footprintCvt'', ', ...
                 '''surfaceGeodesic'', or ''surfaceVoronoi''.']);
    end
end

function mode = normalizeVoronoiSnapMode(mode)
    mode = lower(strtrim(char(mode)));
    switch mode
        case {'spacingaware', 'spacing', 'regularized', 'regularised'}
            mode = 'spacingAware';
        case {'centroid', 'legacy', 'nearestcentroid'}
            mode = 'centroid';
        otherwise
            error('autoElectrodeTargets:BadVoronoiSnapMode', ...
                'voronoiSnapMode must be ''spacingAware'' or ''centroid''.');
    end
end

function [targets, nearestInd, infoOut] = surfaceGeodesicTargets(TRcap, nElectrodes, opts)
% Sample targets on the anatomical scalp while excluding the fabricated base.
    validateattributes(nElectrodes, {'numeric'}, ...
        {'scalar', 'real', 'finite', 'positive'});
    nElectrodes = round(double(nElectrodes));
    TR = requireTriangulatedSurface(TRcap);
    V = double(TR.Points);
    F = double(TR.ConnectivityList);
    nV = size(V, 1);

    opts = setDefault(opts, 'edgeMarginMM', 10);
    opts = setDefault(opts, 'bedMarginMM', 2);
    opts = setDefault(opts, 'bottomFaceBandMM', 1.5);
    opts = setDefault(opts, 'normalUpDotMin', []);
    opts = setDefault(opts, 'normalMode', 'vertex');
    opts = setDefault(opts, 'normalSmoothRadiusMM', 6);
    opts = setDefault(opts, 'visibleFromAbove', false);
    opts = setDefault(opts, 'visibilityBinMM', 2);
    opts = setDefault(opts, 'visibilityDepthMM', 1.5);
    if isfield(opts, 'symmetric') && ~isfield(opts, 'preferSymmetry')
        opts.preferSymmetry = opts.symmetric;
    end
    opts = setDefault(opts, 'preferSymmetry', true);
    opts = setDefault(opts, 'symmetryPlaneX', 0);
    opts = setDefault(opts, 'symmetryMidlineBandMM', 3);
    opts = setDefault(opts, 'midlineMarginMM', opts.edgeMarginMM);
    opts = setDefault(opts, 'maxMirrorSnapMM', inf);
    opts = setDefault(opts, 'mirrorSnapWarnMM', 5);
    opts = setDefault(opts, 'headpostCenter', [0 0]);
    opts = setDefault(opts, 'headpostRadius', 10);
    opts = setDefault(opts, 'exclusionCenters', zeros(0, 3));
    opts = setDefault(opts, 'exclusionRadiusMM', []);
    opts = setDefault(opts, 'customExclusionVertexInd', []);
    opts = setDefault(opts, 'exclusionPaddingMM', 0);
    opts = setDefault(opts, 'vizSurfaceGeodesic', false);

    validateattributes(opts.edgeMarginMM, {'numeric'}, ...
        {'scalar', 'real', 'finite', 'nonnegative'});
    validateattributes(opts.bedMarginMM, {'numeric'}, ...
        {'scalar', 'real', 'finite', 'nonnegative'});
    validateattributes(opts.bottomFaceBandMM, {'numeric'}, ...
        {'scalar', 'real', 'finite', 'nonnegative'});
    validateattributes(opts.symmetryMidlineBandMM, {'numeric'}, ...
        {'scalar', 'real', 'finite', 'nonnegative'});
    validateattributes(opts.midlineMarginMM, {'numeric'}, ...
        {'scalar', 'real', 'finite', 'nonnegative'});
    validateattributes(opts.maxMirrorSnapMM, {'numeric'}, ...
        {'scalar', 'real', 'nonnegative'});
    if ~isempty(opts.mirrorSnapWarnMM)
        validateattributes(opts.mirrorSnapWarnMM, {'numeric'}, ...
            {'scalar', 'real', 'finite', 'nonnegative'});
    end

    [edges, Gfull] = meshEdgesAndGraph(V, F, true(nV, 1));
    [rimSeeds, bottomVertices, bottomFaces] = findCropRimSeeds( ...
        TR, V, F, opts.bottomFaceBandMM);
    if isempty(rimSeeds)
        warning('autoElectrodeTargets:NoCropRim', ...
            ['Could not detect a crop rim. The surface-geodesic edge margin ', ...
             'will not be applied. Inspect the placement QC carefully.']);
        distRim = inf(nV, 1);
    else
        distRim = multiSourceDijkstra(Gfull, rimSeeds);
    end

    zMin = min(V(:, 3));
    aboveBed = V(:, 3) > zMin + opts.bedMarginMM;
    anatomicalSurface = aboveBed & ~bottomVertices;
    awayFromRim = distRim >= opts.edgeMarginMM;

    normalMask = true(nV, 1);
    upDot = [];
    if ~isempty(opts.normalUpDotMin)
        validateattributes(opts.normalUpDotMin, {'numeric'}, ...
            {'scalar', 'real', 'finite'});
        upDot = normalFilterVectors(TR, opts) * [0; 0; 1];
        normalMask = upDot >= opts.normalUpDotMin;
    end

    visibilityMask = true(nV, 1);
    if logical(opts.visibleFromAbove)
        visibilityMask = visibleFromAboveMask(V, ...
            opts.visibilityBinMM, opts.visibilityDepthMM);
    end

    [earExcluded, earPolys, headpostExcluded, headpostPoly] = ...
        legacySurfaceExclusions(V, opts);
    customExcluded = customSurfaceExclusions(V, opts);
    excluded = earExcluded | headpostExcluded | customExcluded;

    eligible = anatomicalSurface & awayFromRim & normalMask & ...
        visibilityMask & ~excluded;
    [~, Geligible] = meshEdgesAndGraph(V, F, eligible);
    eligible = eligible & (full(sum(spones(Geligible), 2)) > 0);
    candidateVertex = find(eligible);
    if numel(candidateVertex) < nElectrodes
        error('autoElectrodeTargets:SparseSurfaceCandidates', ...
            ['Only %d scalp vertices remain for %d electrodes after crop-rim ', ...
             'and exclusion masks. Reduce edgeMarginMM or relax exclusions.'], ...
            numel(candidateVertex), nElectrodes);
    end

    if logical(opts.preferSymmetry)
        [nearestInd, symmetryPairs, mirrorSnapMM] = symmetricGeodesicSample( ...
            V, Geligible, candidateVertex, nElectrodes, opts);
    else
        nearestInd = geodesicFarthestFill( ...
            V, Geligible, candidateVertex, zeros(0, 1), nElectrodes);
        symmetryPairs = zeros(0, 2);
        mirrorSnapMM = zeros(0, 1);
    end
    nearestInd = nearestInd(:);
    targets = V(nearestInd, :);
    warnIfLargeMirrorSnap(mirrorSnapMM, opts);

    infoOut = struct();
    infoOut.placementMode = 'surfaceGeodesic';
    infoOut.P2D = targets(:, 1:2);
    infoOut.hullXY = footprintHull(V);
    infoOut.earPolys = earPolys;
    infoOut.headpostPoly = headpostPoly;
    infoOut.candidateVertex = candidateVertex;
    infoOut.eligibleMask = eligible;
    infoOut.bottomVertexMask = bottomVertices;
    infoOut.bottomFaceMask = bottomFaces;
    infoOut.rimSeeds = rimSeeds;
    infoOut.distRimMM = distRim;
    infoOut.edgeMarginMM = opts.edgeMarginMM;
    infoOut.bedMarginMM = opts.bedMarginMM;
    infoOut.midlineMarginMM = opts.midlineMarginMM;
    infoOut.distMidlineMM = lateralMidlineDistances(V, opts);
    infoOut.normalMask = normalMask;
    infoOut.visibilityMask = visibilityMask;
    infoOut.exclusionMask = excluded;
    infoOut.earExclusionMask = earExcluded;
    infoOut.headpostExclusionMask = headpostExcluded;
    infoOut.customExclusionMask = customExcluded;
    infoOut.customExclusionCenters = double(opts.exclusionCenters);
    infoOut.customExclusionRadiusMM = expandedExclusionRadii(opts);
    infoOut.customExclusionVertexInd = sanitizedVertexExclusionRows( ...
        opts.customExclusionVertexInd, nV);
    infoOut.preferSymmetry = logical(opts.preferSymmetry);
    infoOut.symmetryPairs = symmetryPairs;
    infoOut.mirrorSnapMM = mirrorSnapMM;
    if isempty(symmetryPairs)
        infoOut.pairMidlineDistanceMM = zeros(0, 1);
        infoOut.pairEuclideanDistanceMM = zeros(0, 1);
    else
        infoOut.pairMidlineDistanceMM = pairMidlineDistances( ...
            V, symmetryPairs, opts);
        infoOut.pairEuclideanDistanceMM = vecnorm( ...
            V(symmetryPairs(:, 1), :) - V(symmetryPairs(:, 2), :), 2, 2);
    end
    infoOut.nearestNeighborGeodesicMM = nearestNeighborGeodesicDistances( ...
        Geligible, nearestInd);
    infoOut.meshEdges = edges;

    if logical(opts.vizSurfaceGeodesic)
        showSurfaceGeodesicQc(TR, infoOut, targets);
    end
end

function [targets, nearestInd, infoOut] = surfaceVoronoiTargets(TRcap, nElectrodes, opts)
% Coverage-aware surface CVT: cells cover anatomical scalp, seeds snap to legal placement vertices.
    validateattributes(nElectrodes, {'numeric'}, ...
        {'scalar', 'real', 'finite', 'positive'});
    nElectrodes = round(double(nElectrodes));
    TR = requireTriangulatedSurface(TRcap);
    V = double(TR.Points);
    F = double(TR.ConnectivityList);
    nV = size(V, 1);

    opts = setDefault(opts, 'edgeMarginMM', 10);
    opts = setDefault(opts, 'bedMarginMM', 2);
    opts = setDefault(opts, 'bottomFaceBandMM', 1.5);
    opts = setDefault(opts, 'normalUpDotMin', []);
    opts = setDefault(opts, 'normalMode', 'vertex');
    opts = setDefault(opts, 'normalSmoothRadiusMM', 6);
    opts = setDefault(opts, 'visibleFromAbove', false);
    opts = setDefault(opts, 'visibilityBinMM', 2);
    opts = setDefault(opts, 'visibilityDepthMM', 1.5);
    opts = setDefault(opts, 'symmetryPlaneX', 0);
    opts = setDefault(opts, 'midlineMarginMM', 0);
    opts = setDefault(opts, 'headpostCenter', [0 0]);
    opts = setDefault(opts, 'headpostRadius', 10);
    opts = setDefault(opts, 'exclusionCenters', zeros(0, 3));
    opts = setDefault(opts, 'exclusionRadiusMM', []);
    opts = setDefault(opts, 'customExclusionVertexInd', []);
    opts = setDefault(opts, 'exclusionPaddingMM', 0);
    opts = setDefault(opts, 'voronoiIterations', 10);
    opts = setDefault(opts, 'voronoiToleranceMM', 0.25);
    opts = setDefault(opts, 'voronoiSnapMode', 'spacingAware');
    opts = setDefault(opts, 'voronoiSpacingWeight', 4);
    opts = setDefault(opts, 'voronoiMinSpacingFraction', 0.75);
    opts = setDefault(opts, 'voronoiSpacingIterations', 3);
    opts = setDefault(opts, 'voronoiMaxCandidatesPerCell', 80);
    opts = setDefault(opts, 'vizSurfaceGeodesic', false);
    if ~isfield(opts, 'vizSurfaceVoronoi') || isempty(opts.vizSurfaceVoronoi)
        opts.vizSurfaceVoronoi = opts.vizSurfaceGeodesic;
    end

    validateattributes(opts.edgeMarginMM, {'numeric'}, ...
        {'scalar', 'real', 'finite', 'nonnegative'});
    validateattributes(opts.bedMarginMM, {'numeric'}, ...
        {'scalar', 'real', 'finite', 'nonnegative'});
    validateattributes(opts.bottomFaceBandMM, {'numeric'}, ...
        {'scalar', 'real', 'finite', 'nonnegative'});
    validateattributes(opts.midlineMarginMM, {'numeric'}, ...
        {'scalar', 'real', 'finite', 'nonnegative'});
    validateattributes(opts.voronoiIterations, {'numeric'}, ...
        {'scalar', 'real', 'finite', 'nonnegative'});
    validateattributes(opts.voronoiToleranceMM, {'numeric'}, ...
        {'scalar', 'real', 'finite', 'nonnegative'});
    opts.voronoiSnapMode = normalizeVoronoiSnapMode(opts.voronoiSnapMode);
    validateattributes(opts.voronoiSpacingWeight, {'numeric'}, ...
        {'scalar', 'real', 'finite', 'nonnegative'});
    validateattributes(opts.voronoiMinSpacingFraction, {'numeric'}, ...
        {'scalar', 'real', 'finite', 'nonnegative'});
    validateattributes(opts.voronoiSpacingIterations, {'numeric'}, ...
        {'scalar', 'real', 'finite', 'nonnegative'});
    validateattributes(opts.voronoiMaxCandidatesPerCell, {'numeric'}, ...
        {'scalar', 'real', 'finite', 'positive'});

    [edges, Gfull] = meshEdgesAndGraph(V, F, true(nV, 1));
    [rimSeeds, bottomVertices, bottomFaces] = findCropRimSeeds( ...
        TR, V, F, opts.bottomFaceBandMM);
    if isempty(rimSeeds)
        warning('autoElectrodeTargets:NoCropRim', ...
            ['Could not detect a crop rim. The surface Voronoi placement ', ...
             'will still cover scalp above the printer bed, but edge ', ...
             'placement exclusion will not be applied.']);
        distRim = inf(nV, 1);
    else
        distRim = multiSourceDijkstra(Gfull, rimSeeds);
    end

    zMin = min(V(:, 3));
    aboveBed = V(:, 3) > zMin + opts.bedMarginMM;
    coverage = aboveBed & ~bottomVertices;
    [~, Gcoverage] = meshEdgesAndGraph(V, F, coverage);
    coverage = coverage & (full(sum(spones(Gcoverage), 2)) > 0);
    [~, Gcoverage] = meshEdgesAndGraph(V, F, coverage);
    coverageVertex = find(coverage);

    awayFromRim = distRim >= opts.edgeMarginMM;
    normalMask = true(nV, 1);
    if ~isempty(opts.normalUpDotMin)
        validateattributes(opts.normalUpDotMin, {'numeric'}, ...
            {'scalar', 'real', 'finite'});
        upDot = normalFilterVectors(TR, opts) * [0; 0; 1];
        normalMask = upDot >= opts.normalUpDotMin;
    end
    visibilityMask = true(nV, 1);
    if logical(opts.visibleFromAbove)
        visibilityMask = visibleFromAboveMask(V, ...
            opts.visibilityBinMM, opts.visibilityDepthMM);
    end

    [earExcluded, earPolys, headpostExcluded, headpostPoly] = ...
        legacySurfaceExclusions(V, opts);
    customExcluded = customSurfaceExclusions(V, opts);
    excluded = earExcluded | headpostExcluded | customExcluded;

    eligible = coverage & awayFromRim & normalMask & visibilityMask & ~excluded;
    [~, Geligible] = meshEdgesAndGraph(V, F, eligible);
    eligible = eligible & (full(sum(spones(Geligible), 2)) > 0);
    candidateVertex = find(eligible);
    if numel(candidateVertex) < nElectrodes
        error('autoElectrodeTargets:SparseSurfaceCandidates', ...
            ['Only %d legal placement vertices remain for %d electrodes ', ...
             'after edge and exclusion masks. Reduce edgeMarginMM or relax exclusions.'], ...
            numel(candidateVertex), nElectrodes);
    end
    if isempty(coverageVertex)
        error('autoElectrodeTargets:NoCoverageSurface', ...
            'No anatomical scalp vertices remain above the printer-bed surface.');
    end

    vertexArea = surfaceVertexAreas(V, F, coverage);
    seeds = geodesicFarthestFill(V, Gcoverage, candidateVertex, zeros(0, 1), nElectrodes);
    seeds = seeds(:);
    maxMotion = inf;
    iter = 0;
    cellLabel = zeros(nV, 1);
    distToSeed = inf(nV, 1);
    cellArea = zeros(nElectrodes, 1);
    centroids = nan(nElectrodes, 3);

    maxIter = round(double(opts.voronoiIterations));
    for iter = 1:maxIter
        oldSeeds = seeds;
        [cellLabel, distToSeed] = geodesicVoronoiAssignments( ...
            Gcoverage, seeds, coverageVertex);
        [centroids, cellArea] = voronoiCellCentroids( ...
            V, coverageVertex, cellLabel, vertexArea, nElectrodes, seeds);
        seeds = snapCentroidsToPlacementVertices( ...
            V, Gcoverage, candidateVertex, cellLabel, centroids, ...
            cellArea, seeds, opts);
        maxMotion = max(vecnorm(V(seeds, :) - V(oldSeeds, :), 2, 2));
        if maxMotion <= double(opts.voronoiToleranceMM)
            break;
        end
    end
    [cellLabel, distToSeed] = geodesicVoronoiAssignments( ...
        Gcoverage, seeds, coverageVertex);
    [centroids, cellArea] = voronoiCellCentroids( ...
        V, coverageVertex, cellLabel, vertexArea, nElectrodes, seeds);

    nearestInd = seeds(:);
    targets = V(nearestInd, :);

    infoOut = struct();
    infoOut.placementMode = 'surfaceVoronoi';
    infoOut.P2D = targets(:, 1:2);
    infoOut.hullXY = footprintHull(V);
    infoOut.earPolys = earPolys;
    infoOut.headpostPoly = headpostPoly;
    infoOut.candidateVertex = candidateVertex;
    infoOut.coverageVertex = coverageVertex;
    infoOut.coverageMask = coverage;
    infoOut.eligibleMask = eligible;
    infoOut.bottomVertexMask = bottomVertices;
    infoOut.bottomFaceMask = bottomFaces;
    infoOut.rimSeeds = rimSeeds;
    infoOut.distRimMM = distRim;
    infoOut.edgeMarginMM = opts.edgeMarginMM;
    infoOut.bedMarginMM = opts.bedMarginMM;
    infoOut.midlineMarginMM = opts.midlineMarginMM;
    infoOut.distMidlineMM = lateralMidlineDistances(V, opts);
    infoOut.normalMask = normalMask;
    infoOut.visibilityMask = visibilityMask;
    infoOut.exclusionMask = excluded;
    infoOut.earExclusionMask = earExcluded;
    infoOut.headpostExclusionMask = headpostExcluded;
    infoOut.customExclusionMask = customExcluded;
    infoOut.customExclusionCenters = double(opts.exclusionCenters);
    infoOut.customExclusionRadiusMM = expandedExclusionRadii(opts);
    infoOut.customExclusionVertexInd = sanitizedVertexExclusionRows( ...
        opts.customExclusionVertexInd, nV);
    infoOut.voronoiCellIndex = cellLabel;
    infoOut.voronoiDistanceMM = distToSeed;
    infoOut.voronoiCellAreaMM2 = cellArea;
    infoOut.voronoiCellCentroidMm = centroids;
    infoOut.voronoiIterations = iter;
    infoOut.voronoiMaxMotionMM = maxMotion;
    infoOut.nearestNeighborGeodesicMM = nearestNeighborGeodesicDistances( ...
        Geligible, nearestInd);
    infoOut.nearestNeighborCoverageGeodesicMM = nearestNeighborGeodesicDistances( ...
        Gcoverage, nearestInd);
    infoOut.voronoiSnapMode = opts.voronoiSnapMode;
    infoOut.voronoiSpacingWeight = double(opts.voronoiSpacingWeight);
    infoOut.voronoiMinSpacingFraction = double(opts.voronoiMinSpacingFraction);
    infoOut.voronoiTargetSpacingMM = equalAreaTargetSpacing(cellArea);
    infoOut.voronoiMinTargetSpacingMM = ...
        double(opts.voronoiMinSpacingFraction) * infoOut.voronoiTargetSpacingMM;
    infoOut.meshEdges = edges;

    if logical(opts.vizSurfaceVoronoi)
        showSurfaceVoronoiQc(TR, infoOut, targets);
    end
end

function vertexArea = surfaceVertexAreas(V, F, coverage)
    vertexArea = zeros(size(V, 1), 1);
    keepFace = coverage(F(:, 1)) & coverage(F(:, 2)) & coverage(F(:, 3));
    Fkeep = F(keepFace, :);
    if isempty(Fkeep)
        vertexArea(coverage) = 1;
        return;
    end
    edge1 = V(Fkeep(:, 2), :) - V(Fkeep(:, 1), :);
    edge2 = V(Fkeep(:, 3), :) - V(Fkeep(:, 1), :);
    faceArea = 0.5 * vecnorm(cross(edge1, edge2, 2), 2, 2);
    for corner = 1:3
        vertexArea = vertexArea + accumarray( ...
            Fkeep(:, corner), faceArea / 3, [size(V, 1), 1], @sum, 0);
    end
    if all(vertexArea(coverage) == 0)
        vertexArea(coverage) = 1;
    end
end

function [cellLabel, distToSeed] = geodesicVoronoiAssignments(G, seeds, coverageVertex)
    seeds = seeds(:);
    coverageVertex = coverageVertex(:);
    K = numel(seeds);
    distMat = seedDistanceMatrix(G, seeds, coverageVertex);
    [distLocal, labelLocal] = min(distMat, [], 2);
    unreachable = ~isfinite(distLocal);
    if any(unreachable)
        labelLocal(unreachable) = 1;
    end
    cellLabel = zeros(size(G, 1), 1);
    distToSeed = inf(size(G, 1), 1);
    cellLabel(coverageVertex) = labelLocal;
    distToSeed(coverageVertex) = distLocal;
    if K == 0
        cellLabel(:) = 0;
    end
end

function distMat = seedDistanceMatrix(G, seeds, query)
    try
        graphObj = graph(G, 'upper');
        distMat = distances(graphObj, seeds(:)', query(:))';
    catch
        distMat = inf(numel(query), numel(seeds));
        for i = 1:numel(seeds)
            dist = multiSourceDijkstra(G, seeds(i));
            distMat(:, i) = dist(query);
        end
    end
end

function [centroids, cellArea] = voronoiCellCentroids( ...
        V, coverageVertex, cellLabel, vertexArea, K, seeds)
    centroids = nan(K, 3);
    cellArea = zeros(K, 1);
    for k = 1:K
        rows = coverageVertex(cellLabel(coverageVertex) == k);
        if isempty(rows)
            centroids(k, :) = V(seeds(k), :);
            continue;
        end
        weights = vertexArea(rows);
        if isempty(weights) || sum(weights) <= 0 || any(~isfinite(weights))
            weights = ones(numel(rows), 1);
        end
        cellArea(k) = sum(weights);
        centroids(k, :) = sum(bsxfun(@times, V(rows, :), weights), 1) ./ ...
            max(sum(weights), eps);
    end
end

function seeds = snapCentroidsToPlacementVertices( ...
        V, Gcoverage, candidateVertex, cellLabel, centroids, cellArea, ...
        previousSeeds, opts)
    K = size(centroids, 1);
    seeds = zeros(K, 1);
    used = false(size(V, 1), 1);
    [~, order] = sort(cellArea(:), 'descend');
    order = order(:)';
    for k = order
        target = centroids(k, :);
        if any(~isfinite(target))
            target = V(previousSeeds(k), :);
        end
        inCell = candidateVertex(cellLabel(candidateVertex) == k & ...
            ~used(candidateVertex));
        if isempty(inCell)
            inCell = candidateVertex(~used(candidateVertex));
        end
        if isempty(inCell)
            error('autoElectrodeTargets:VoronoiSnapFailed', ...
                'Could not find distinct legal placement vertices for all Voronoi cells.');
        end
        [~, row] = min(vecnorm(V(inCell, :) - target, 2, 2));
        seeds(k) = inCell(row);
        used(seeds(k)) = true;
    end
    if strcmp(opts.voronoiSnapMode, 'spacingAware') && ...
            double(opts.voronoiSpacingWeight) > 0 && K > 1
        seeds = refineVoronoiSeedSpacing(V, Gcoverage, candidateVertex, ...
            cellLabel, centroids, cellArea, seeds, opts);
    end
end

function seeds = refineVoronoiSeedSpacing(V, Gcoverage, candidateVertex, ...
        cellLabel, centroids, cellArea, seeds, opts)
    K = numel(seeds);
    targetSpacing = equalAreaTargetSpacing(cellArea);
    if ~isfinite(targetSpacing) || targetSpacing <= 0
        return;
    end
    minSpacing = double(opts.voronoiMinSpacingFraction) * targetSpacing;
    if minSpacing <= 0
        return;
    end
    maxCandidates = max(1, round(double(opts.voronoiMaxCandidatesPerCell)));
    spacingWeight = double(opts.voronoiSpacingWeight);
    spacingIterations = max(0, round(double(opts.voronoiSpacingIterations)));
    candidateLists = voronoiSnapCandidateLists( ...
        V, candidateVertex, cellLabel, centroids, seeds, maxCandidates);
    if isempty(candidateLists)
        return;
    end

    [~, order] = sort(cellArea(:), 'descend');
    order = order(:)';
    for iter = 1:spacingIterations %#ok<NASGU>
        changed = false;
        for k = order
            cand = candidateLists{k};
            if isempty(cand)
                continue;
            end
            otherSeeds = seeds;
            otherSeeds(k) = [];
            cand = cand(~ismember(cand, otherSeeds));
            if isempty(cand)
                continue;
            end
            target = centroids(k, :);
            if any(~isfinite(target))
                target = V(seeds(k), :);
            end
            distToCentroid = vecnorm(V(cand, :) - target, 2, 2);
            compactScore = (distToCentroid ./ max(targetSpacing, eps)) .^ 2;
            distToOther = nearestDistanceToSeedSet(Gcoverage, cand, otherSeeds);
            closePenalty = (max(0, minSpacing - distToOther) ./ ...
                max(minSpacing, eps)) .^ 2;
            consistencyPenalty = 0.10 * ((distToOther - targetSpacing) ./ ...
                max(targetSpacing, eps)) .^ 2;
            totalScore = compactScore + spacingWeight * closePenalty + ...
                spacingWeight * consistencyPenalty;
            totalScore(~isfinite(totalScore)) = inf;
            [~, bestRow] = min(totalScore);
            if ~isempty(bestRow) && isfinite(totalScore(bestRow)) && ...
                    seeds(k) ~= cand(bestRow)
                seeds(k) = cand(bestRow);
                changed = true;
            end
        end
        if ~changed
            break;
        end
    end
end

function candidateLists = voronoiSnapCandidateLists( ...
        V, candidateVertex, cellLabel, centroids, seeds, maxCandidates)
    K = size(centroids, 1);
    candidateLists = cell(K, 1);
    for k = 1:K
        target = centroids(k, :);
        if any(~isfinite(target))
            target = V(seeds(k), :);
        end
        rows = candidateVertex(cellLabel(candidateVertex) == k);
        if isempty(rows)
            rows = candidateVertex;
        end
        rows = unique([rows(:); seeds(k)]);
        distToCentroid = vecnorm(V(rows, :) - target, 2, 2);
        [~, order] = sort(distToCentroid, 'ascend');
        order = order(1:min(numel(order), maxCandidates));
        candidateLists{k} = rows(order);
    end
end

function distToOther = nearestDistanceToSeedSet(G, queryRows, seedRows)
    queryRows = queryRows(:);
    seedRows = seedRows(:);
    if isempty(seedRows)
        distToOther = inf(numel(queryRows), 1);
        return;
    end
    dist = multiSourceDijkstra(G, seedRows);
    distToOther = dist(queryRows);
end

function targetSpacing = equalAreaTargetSpacing(cellArea)
    area = cellArea(:);
    area = area(isfinite(area) & area > 0);
    if isempty(area)
        targetSpacing = NaN;
        return;
    end
    meanArea = mean(area);
    targetSpacing = sqrt(2 * meanArea / sqrt(3));
end

function warnIfLargeMirrorSnap(mirrorSnapMM, opts)
    if isempty(opts.mirrorSnapWarnMM) || isempty(mirrorSnapMM)
        return;
    end
    maxSnap = max(mirrorSnapMM);
    if maxSnap <= opts.mirrorSnapWarnMM
        return;
    end
    warning('autoElectrodeTargets:LargeMirrorSnap', ...
        ['At least one bilateral partner moved %.2f mm from its reflected ', ...
         'location while snapping to eligible scalp (threshold %.2f mm). ', ...
         'This can be intentional near exclusions, but inspect the layout QC.'], ...
        maxSnap, opts.mirrorSnapWarnMM);
end

function TR = requireTriangulatedSurface(surface)
    if isa(surface, 'triangulation')
        TR = surface;
        return;
    end
    if isstruct(surface) && isfield(surface, 'Points') && ...
            isfield(surface, 'ConnectivityList') && ...
            ~isempty(surface.ConnectivityList)
        TR = triangulation(double(surface.ConnectivityList), ...
            double(surface.Points));
        return;
    end
    error('autoElectrodeTargets:SurfaceGeodesicNeedsMesh', ...
        ['placementMode=''surfaceGeodesic'' requires a triangulated scalp ', ...
         'mesh with Points and ConnectivityList.']);
end

function [edges, G] = meshEdgesAndGraph(V, F, allowedVertex)
    edges = [F(:, [1 2]); F(:, [2 3]); F(:, [3 1])];
    edges = unique(sort(edges, 2), 'rows');
    keep = allowedVertex(edges(:, 1)) & allowedVertex(edges(:, 2));
    edges = edges(keep, :);
    lengths = vecnorm(V(edges(:, 1), :) - V(edges(:, 2), :), 2, 2);
    lengths = max(lengths, eps);
    nV = size(V, 1);
    G = sparse([edges(:, 1); edges(:, 2)], ...
        [edges(:, 2); edges(:, 1)], [lengths; lengths], nV, nV);
end

function [seeds, bottomVertices, bottomFaces] = findCropRimSeeds(TR, V, F, bandMM)
    zMin = min(V(:, 3));
    faceZ = [V(F(:, 1), 3), V(F(:, 2), 3), V(F(:, 3), 3)];
    bottomFaces = all(faceZ <= zMin + bandMM, 2);
    bottomVertices = false(size(V, 1), 1);
    seeds = zeros(0, 1);

    if any(bottomFaces)
        bottomFaceVertices = unique(F(bottomFaces, :));
        bottomVertices(bottomFaceVertices) = true;
        E = [F(bottomFaces, [1 2]); F(bottomFaces, [2 3]); ...
            F(bottomFaces, [3 1])];
        E = sort(E, 2);
        [uniqueEdges, ~, edgeGroup] = unique(E, 'rows');
        edgeCount = accumarray(edgeGroup, 1);
        rimEdges = uniqueEdges(edgeCount == 1, :);
        seeds = unique(rimEdges(:));
    end

    if isempty(seeds)
        try
            boundaryEdges = freeBoundary(TR);
            seeds = unique(boundaryEdges(:));
        catch
        end
    end
    if isempty(seeds)
        seeds = find(V(:, 3) <= zMin + max(bandMM, 0.5));
    end
end

function [earExcluded, earPolys, headpostExcluded, headpostPoly] = ...
        legacySurfaceExclusions(V, opts)
    hullXY = footprintHull(V);
    footprintPoly = polyshape(hullXY(:, 1), hullXY(:, 2));
    earPolys = {};
    if isfield(opts, 'earLeftLine') && ~isempty(opts.earLeftLine)
        earPolys{end + 1} = earTrianglePoly( ...
            opts.earLeftLine, 'left', footprintPoly); %#ok<AGROW>
    end
    if isfield(opts, 'earRightLine') && ~isempty(opts.earRightLine)
        earPolys{end + 1} = earTrianglePoly( ...
            opts.earRightLine, 'right', footprintPoly); %#ok<AGROW>
    end
    earExcluded = false(size(V, 1), 1);
    for i = 1:numel(earPolys)
        earExcluded = earExcluded | isinterior( ...
            earPolys{i}, V(:, 1), V(:, 2));
    end

    hpCenter = double(opts.headpostCenter(:)');
    if numel(hpCenter) < 2
        hpCenter = [0 0];
    else
        hpCenter = hpCenter(1:2);
    end
    hpRadius = double(opts.headpostRadius);
    validateattributes(hpRadius, {'numeric'}, ...
        {'scalar', 'real', 'finite', 'nonnegative'});
    th = linspace(0, 2 * pi, 200);
    hpXY = hpCenter + [hpRadius * cos(th).' hpRadius * sin(th).'];
    headpostPoly = polyshape(hpXY(:, 1), hpXY(:, 2));
    headpostExcluded = vecnorm(V(:, 1:2) - hpCenter, 2, 2) < hpRadius;
end

function excluded = customSurfaceExclusions(V, opts)
    centers = double(opts.exclusionCenters);
    excluded = false(size(V, 1), 1);
    vertexRows = sanitizedVertexExclusionRows(opts.customExclusionVertexInd, ...
        size(V, 1));
    excluded(vertexRows) = true;
    if isempty(centers)
        return;
    end
    radius = expandedExclusionRadii(opts);
    for i = 1:size(centers, 1)
        excluded = excluded | vecnorm(V - centers(i, :), 2, 2) < radius(i);
    end
end

function rows = sanitizedVertexExclusionRows(rowsIn, nVertices)
    rows = double(rowsIn(:));
    rows = rows(isfinite(rows) & rows >= 1 & rows <= nVertices);
    rows = unique(round(rows));
end

function radius = expandedExclusionRadii(opts)
    centers = double(opts.exclusionCenters);
    if isempty(centers)
        radius = zeros(0, 1);
        return;
    end
    if size(centers, 2) ~= 3
        error('autoElectrodeTargets:BadExclusionCenters', ...
            'exclusionCenters must be an N x 3 matrix in capMaker print mm.');
    end
    radius = double(opts.exclusionRadiusMM(:));
    if isempty(radius)
        error('autoElectrodeTargets:MissingExclusionRadius', ...
            'Set exclusionRadiusMM when exclusionCenters are provided.');
    end
    if isscalar(radius)
        radius = repmat(radius, size(centers, 1), 1);
    end
    if numel(radius) ~= size(centers, 1) || any(radius < 0)
        error('autoElectrodeTargets:BadExclusionRadius', ...
            'exclusionRadiusMM must be nonnegative and scalar or one value per center.');
    end
    padding = double(opts.exclusionPaddingMM);
    validateattributes(padding, {'numeric'}, ...
        {'scalar', 'real', 'finite', 'nonnegative'});
    radius = radius + padding;
end

function hullXY = footprintHull(V)
    hullRows = convhull(V(:, 1), V(:, 2));
    hullXY = V(hullRows, 1:2);
end

function keep = visibleFromAboveMask(V, binMM, depthMM)
    validateattributes(binMM, {'numeric'}, ...
        {'scalar', 'real', 'finite', 'positive'});
    validateattributes(depthMM, {'numeric'}, ...
        {'scalar', 'real', 'finite', 'nonnegative'});
    xyBin = round((V(:, 1:2) - min(V(:, 1:2), [], 1)) ./ binMM);
    [~, ~, binGroup] = unique(xyBin, 'rows');
    topZ = accumarray(binGroup, V(:, 3), [], @max);
    keep = V(:, 3) >= topZ(binGroup) - depthMM;
end

function [selected, selectedPairs, selectedMirrorSnap] = ...
        symmetricGeodesicSample(V, G, candidates, K, opts)
    x0 = double(opts.symmetryPlaneX);
    band = double(opts.symmetryMidlineBandMM);
    X = V(:, 1);
    distMidline = lateralMidlineDistances(V, opts);
    right = candidates(X(candidates) > x0 + 0.5 * band & ...
        distMidline(candidates) >= opts.midlineMarginMM & ...
        isfinite(distMidline(candidates)));
    left = candidates(X(candidates) < x0 - 0.5 * band & ...
        distMidline(candidates) >= opts.midlineMarginMM & ...
        isfinite(distMidline(candidates)));
    selected = zeros(0, 1);
    selectedPairs = zeros(0, 2);
    selectedMirrorSnap = zeros(0, 1);

    if mod(K, 2) == 1
        midline = candidates(abs(X(candidates) - x0) <= band);
        if isempty(midline)
            [~, order] = sort(abs(X(candidates) - x0));
            midline = candidates(order(1:min(25, numel(order))));
        end
        selected = chooseCenteredVertex(V, midline, candidates);
    end

    if ~isempty(right) && ~isempty(left)
        mirrored = V(right, :);
        mirrored(:, 1) = 2 * x0 - mirrored(:, 1);
        D = pdist2(mirrored, V(left, :));
        [mirrorSnap, leftRow] = min(D, [], 2);
        pairs = [right(:), left(leftRow(:))];
        pairMidlineDistance = distMidline(pairs(:, 1)) + ...
            distMidline(pairs(:, 2));
        keepPair = pairs(:, 1) ~= pairs(:, 2) & ...
            mirrorSnap(:) <= double(opts.maxMirrorSnapMM);
        pairs = pairs(keepPair, :);
        mirrorSnap = mirrorSnap(keepPair);
        pairMidlineDistance = pairMidlineDistance(keepPair);
        [pairs, uniqueRows] = unique(pairs, 'rows', 'stable');
        mirrorSnap = mirrorSnap(uniqueRows);
        pairMidlineDistance = pairMidlineDistance(uniqueRows);
    else
        pairs = zeros(0, 2);
        mirrorSnap = zeros(0, 1);
        pairMidlineDistance = zeros(0, 1);
    end

    nPairs = floor(K / 2);
    scalpCenter = mean(V(candidates, :), 1);
    for pairNumber = 1:nPairs
        available = ~ismember(pairs(:, 1), selected) & ...
            ~ismember(pairs(:, 2), selected);
        availableRows = find(available);
        if isempty(availableRows)
            break;
        end
        if isempty(selected)
            pairCenters = 0.5 * (V(pairs(availableRows, 1), :) + ...
                V(pairs(availableRows, 2), :));
            score = -vecnorm(pairCenters - scalpCenter, 2, 2);
        else
            distFromSelected = multiSourceDijkstra(G, selected);
            score = min([distFromSelected(pairs(availableRows, 1)), ...
                distFromSelected(pairs(availableRows, 2)), ...
                pairMidlineDistance(availableRows)], [], 2);
        end
        [~, bestLocal] = max(score);
        bestRow = availableRows(bestLocal);
        selected = [selected; pairs(bestRow, :).']; %#ok<AGROW>
        selectedPairs(end + 1, :) = pairs(bestRow, :); %#ok<AGROW>
        selectedMirrorSnap(end + 1, 1) = mirrorSnap(bestRow); %#ok<AGROW>
    end

    if numel(selected) < K
        warning('autoElectrodeTargets:SymmetryFallback', ...
            ['Only %d of %d targets were assigned as bilateral pairs. ', ...
             'Filling the remaining targets by geodesic spacing.'], ...
            numel(selected), K);
        fillCandidates = candidates(distMidline(candidates) >= ...
            opts.midlineMarginMM & isfinite(distMidline(candidates)));
        selected = geodesicFarthestFill(V, G, fillCandidates, selected, K);
    end
    selected = selected(1:K);
end

function pairDistance = pairMidlineDistances(V, pairs, opts)
    distMidline = lateralMidlineDistances(V, opts);
    pairDistance = distMidline(pairs(:, 1)) + distMidline(pairs(:, 2));
end

function distMidline = lateralMidlineDistances(V, opts)
    x0 = double(opts.symmetryPlaneX);
    distMidline = abs(V(:, 1) - x0);
end

function selected = geodesicFarthestFill(V, G, candidates, selected, K)
    selected = unique(selected(:), 'stable');
    if isempty(selected)
        selected = chooseCenteredVertex(V, candidates, candidates);
    end
    while numel(selected) < K
        distFromSelected = multiSourceDijkstra(G, selected);
        score = distFromSelected(candidates);
        score(ismember(candidates, selected)) = -inf;
        [bestScore, row] = max(score);
        if isempty(row) || bestScore == -inf
            error('autoElectrodeTargets:CannotFillTargets', ...
                'Could not find %d distinct eligible surface targets.', K);
        end
        selected(end + 1, 1) = candidates(row); %#ok<AGROW>
    end
end

function selected = chooseCenteredVertex(V, choices, candidates)
    center = mean(V(candidates, :), 1);
    [~, row] = min(vecnorm(V(choices, :) - center, 2, 2));
    selected = choices(row);
end

function N = vertexNormalSafe(TR)
    try
        N = vertexNormal(TR);
    catch
        V = TR.Points;
        F = TR.ConnectivityList;
        faceNormal = cross(V(F(:, 2), :) - V(F(:, 1), :), ...
            V(F(:, 3), :) - V(F(:, 1), :), 2);
        N = zeros(size(V));
        for i = 1:size(F, 1)
            N(F(i, :), :) = N(F(i, :), :) + faceNormal(i, :);
        end
        normalLength = vecnorm(N, 2, 2);
        normalLength(normalLength == 0) = 1;
        N = N ./ normalLength;
    end
end

function N = normalFilterVectors(TR, opts)
    N = vertexNormalSafe(TR);
    N = normalizeRows(N);
    mode = 'vertex';
    if isfield(opts, 'normalMode') && ~isempty(opts.normalMode)
        mode = normalizeNormalMode(opts.normalMode);
    end
    if strcmp(mode, 'smooth')
        radiusMm = 6;
        if isfield(opts, 'normalSmoothRadiusMM') && ...
                ~isempty(opts.normalSmoothRadiusMM)
            validateattributes(opts.normalSmoothRadiusMM, {'numeric'}, ...
                {'scalar', 'real', 'finite', 'positive'});
            radiusMm = double(opts.normalSmoothRadiusMM);
        end
        N = smoothNormalsByRadius(TR, N, radiusMm);
    end
end

function mode = normalizeNormalMode(value)
    mode = lower(strtrim(char(value)));
    switch regexprep(mode, '[\s_\-]+', '')
        case {'vertex', 'raw', 'legacy'}
            mode = 'vertex';
        case {'smooth', 'smoothed', 'interpolated'}
            mode = 'smooth';
        otherwise
            error('autoElectrodeTargets:BadNormalMode', ...
                'normalMode must be ''vertex'' or ''smooth''.');
    end
end

function N = smoothNormalsByRadius(TR, rawNormals, radiusMm)
    V = double(TR.Points);
    rawNormals = orientNormalsRadially(V, normalizeRows(rawNormals));
    N = rawNormals;
    r2 = radiusMm ^ 2;
    for i = 1:size(V, 1)
        d2 = sum((V - V(i, :)) .^ 2, 2);
        use = d2 <= r2;
        if nnz(use) < 6
            [~, order] = sort(d2, 'ascend');
            use(order(1:min(12, numel(order)))) = true;
        end
        n = mean(rawNormals(use, :), 1);
        if dot(n, rawNormals(i, :)) < 0
            n = -n;
        end
        if norm(n) > eps
            N(i, :) = n ./ norm(n);
        end
    end
    N = normalizeRows(N);
end

function N = orientNormalsRadially(V, N)
    center = median(V, 1);
    radial = normalizeRows(V - center);
    flip = all(isfinite(radial), 2) & all(isfinite(N), 2) & ...
        sum(N .* radial, 2) < 0;
    N(flip, :) = -N(flip, :);
end

function N = normalizeRows(N)
    normalLength = vecnorm(N, 2, 2);
    normalLength(~isfinite(normalLength) | normalLength == 0) = 1;
    N = N ./ normalLength;
end

function dist = multiSourceDijkstra(G, sources)
    n = size(G, 1);
    dist = inf(n, 1);
    sources = unique(sources(:));
    dist(sources) = 0;
    visited = false(n, 1);
    frontier = false(n, 1);
    frontier(sources) = true;
    while any(frontier)
        candidateDistance = dist;
        candidateDistance(~frontier) = inf;
        [~, u] = min(candidateDistance);
        frontier(u) = false;
        visited(u) = true;
        neighbors = find(G(u, :));
        if isempty(neighbors)
            continue;
        end
        edgeWeight = full(G(u, neighbors)).';
        alternate = dist(u) + edgeWeight;
        better = alternate < dist(neighbors);
        if any(better)
            update = neighbors(better);
            dist(update) = alternate(better);
            frontier(update) = ~visited(update) | frontier(update);
        end
    end
end

function nearestDistance = nearestNeighborGeodesicDistances(G, selected)
    nearestDistance = inf(numel(selected), 1);
    for i = 1:numel(selected)
        dist = multiSourceDijkstra(G, selected(i));
        dist(selected(i)) = inf;
        nearestDistance(i) = min(dist(selected));
    end
end

function showSurfaceGeodesicQc(TR, infoOut, targets)
    V = TR.Points;
    F = TR.ConnectivityList;
    fig = figure('Name', 'autoElectrodeTargets - surface geodesic QC', ...
        'Color', 'w', 'WindowStyle', 'normal', ...
        'Position', [80 80 1500 650]);
    tiledlayout(fig, 1, 3, 'Padding', 'compact', 'TileSpacing', 'compact');

    ax = nexttile;
    patch(ax, 'Faces', F, 'Vertices', V, ...
        'FaceColor', [0.88 0.9 0.94], 'EdgeColor', 'none');
    hold(ax, 'on');
    hEar = scatterMask3(ax, V, infoOut.earExclusionMask, 18, ...
        [0.95 0.45 0.05]);
    hHeadpost = scatterMask3(ax, V, infoOut.headpostExclusionMask, 18, ...
        [0.45 0.15 0.75]);
    hCustom = scatterMask3(ax, V, infoOut.customExclusionMask, 18, ...
        [0.05 0.35 0.95]);
    hEligible = scatter3(ax, V(infoOut.candidateVertex, 1), V(infoOut.candidateVertex, 2), ...
        V(infoOut.candidateVertex, 3), 10, [0.15 0.65 0.2], 'filled');
    hRim = scatter3(ax, V(infoOut.rimSeeds, 1), V(infoOut.rimSeeds, 2), ...
        V(infoOut.rimSeeds, 3), 20, [0.9 0.1 0.1], 'filled');
    midlineBuffer = infoOut.candidateVertex( ...
        infoOut.distMidlineMM(infoOut.candidateVertex) < ...
        infoOut.midlineMarginMM);
    hMidline = scatter3(ax, V(midlineBuffer, 1), V(midlineBuffer, 2), ...
        V(midlineBuffer, 3), 12, [0.75 0.05 0.75], 'filled');
    hTargets = scatter3(ax, targets(:, 1), targets(:, 2), targets(:, 3), ...
        80, [0.05 0.05 0.05], 'filled');
    drawExclusionSpheres(ax, infoOut.customExclusionCenters, ...
        infoOut.customExclusionRadiusMM);
    formatSurfaceQcAxes(ax, V);
    camlight(ax, 'headlight');
    lighting(ax, 'gouraud');
    title(ax, 'Surface candidates and exclusion masks');
    legend(nonemptyHandles([hEligible hRim hMidline hEar hHeadpost hCustom hTargets]), ...
        nonemptyLabels({ ...
            'eligible candidates', 'crop rim', 'midline buffer', ...
            'ear excluded', 'headpost excluded', 'custom/tES excluded', ...
            'targets'}, ...
            [hEligible hRim hMidline hEar hHeadpost hCustom hTargets]), ...
        'Location', 'southoutside', 'Interpreter', 'none');

    ax = nexttile;
    distRim = infoOut.distRimMM;
    finiteDist = distRim(isfinite(distRim));
    if isempty(finiteDist)
        finiteDist = 0;
    end
    colorMax = max([2 * infoOut.edgeMarginMM; finiteDist(:)]);
    patch(ax, 'Faces', F, 'Vertices', V, ...
        'FaceVertexCData', min(distRim, colorMax), ...
        'FaceColor', 'interp', 'EdgeColor', 'none');
    formatSurfaceQcAxes(ax, V);
    camlight(ax, 'headlight');
    lighting(ax, 'gouraud');
    colorbar(ax);
    title(ax, 'Geodesic distance from crop rim (mm)');

    ax = nexttile;
    showFootprintExclusionQc(ax, V, infoOut, targets);
end

function showSurfaceVoronoiQc(TR, infoOut, targets)
    V = double(TR.Points);
    F = double(TR.ConnectivityList);
    K = size(targets, 1);
    fig = figure('Name', 'autoElectrodeTargets - surface Voronoi QC', ...
        'Color', 'w', 'WindowStyle', 'normal', ...
        'Position', [80 80 1500 650]);
    tiledlayout(fig, 1, 3, 'Padding', 'compact', 'TileSpacing', 'compact');

    ax = nexttile;
    cellData = double(infoOut.voronoiCellIndex);
    cellData(~infoOut.coverageMask) = 0;
    patch(ax, 'Faces', F, 'Vertices', V, ...
        'FaceVertexCData', cellData, ...
        'FaceColor', 'flat', ...
        'EdgeColor', 'none', ...
        'FaceAlpha', 0.88);
    hold(ax, 'on');
    scatter3(ax, targets(:, 1), targets(:, 2), targets(:, 3), ...
        85, [0.02 0.02 0.02], 'filled');
    scatter3(ax, infoOut.voronoiCellCentroidMm(:, 1), ...
        infoOut.voronoiCellCentroidMm(:, 2), ...
        infoOut.voronoiCellCentroidMm(:, 3), ...
        70, [1 1 1], 'd', 'filled', 'MarkerEdgeColor', [0 0 0]);
    labelTargets3(ax, targets, 1:K);
    formatSurfaceQcAxes(ax, V);
    camlight(ax, 'headlight');
    lighting(ax, 'gouraud');
    colormap(ax, [[0.78 0.78 0.78]; highContrastCellColors(K)]);
    caxis(ax, [0 K]);
    title(ax, sprintf('Coverage Voronoi cells (%d iterations)', ...
        infoOut.voronoiIterations));

    ax = nexttile;
    patch(ax, 'Faces', F, 'Vertices', V, ...
        'FaceColor', [0.88 0.9 0.94], 'EdgeColor', 'none', ...
        'FaceAlpha', 0.45);
    hold(ax, 'on');
    scatterMask3(ax, V, infoOut.coverageMask, 7, [0.70 0.70 0.70]);
    hEar = scatterMask3(ax, V, infoOut.earExclusionMask, 16, ...
        [0.95 0.45 0.05]);
    hHeadpost = scatterMask3(ax, V, infoOut.headpostExclusionMask, 16, ...
        [0.45 0.15 0.75]);
    hCustom = scatterMask3(ax, V, infoOut.customExclusionMask, 16, ...
        [0.05 0.35 0.95]);
    hEligible = scatter3(ax, V(infoOut.candidateVertex, 1), ...
        V(infoOut.candidateVertex, 2), V(infoOut.candidateVertex, 3), ...
        12, [0.15 0.65 0.2], 'filled');
    hTargets = scatter3(ax, targets(:, 1), targets(:, 2), targets(:, 3), ...
        85, [0.02 0.02 0.02], 'filled');
    drawExclusionSpheres(ax, infoOut.customExclusionCenters, ...
        infoOut.customExclusionRadiusMM);
    formatSurfaceQcAxes(ax, V);
    camlight(ax, 'headlight');
    lighting(ax, 'gouraud');
    title(ax, 'Placement constraints on coverage surface');
    legend(nonemptyHandles([hEligible hEar hHeadpost hCustom hTargets]), ...
        nonemptyLabels({ ...
            'legal placement', 'ear excluded', 'headpost excluded', ...
            'custom/tES excluded', 'targets'}, ...
            [hEligible hEar hHeadpost hCustom hTargets]), ...
        'Location', 'southoutside', 'Interpreter', 'none');

    ax = nexttile;
    areaValues = infoOut.voronoiCellAreaMM2(:);
    spacingValues = infoOut.nearestNeighborCoverageGeodesicMM(:);
    finiteSpacing = spacingValues(isfinite(spacingValues));
    spacingPlot = spacingValues;
    spacingPlot(~isfinite(spacingPlot)) = NaN;
    bar(ax, areaValues, 'FaceColor', [0.25 0.48 0.78]);
    hold(ax, 'on');
    xlim(ax, [0.5 max(numel(areaValues) + 0.5, 1.5)]);
    plot(ax, xlim(ax), mean(areaValues) * [1 1], 'k--');
    xlabel(ax, 'EEG site');
    ylabel(ax, 'coverage cell area (mm^2)');
    if ~isempty(finiteSpacing)
        yyaxis(ax, 'right');
        plot(ax, 1:numel(spacingPlot), spacingPlot, 'o-', ...
            'Color', [0.85 0.24 0.08], ...
            'MarkerFaceColor', [1 1 1], ...
            'LineWidth', 1.2);
        ylabel(ax, 'nearest-neighbor geodesic (mm)');
        if isfield(infoOut, 'voronoiMinTargetSpacingMM') && ...
                isfinite(infoOut.voronoiMinTargetSpacingMM)
            plot(ax, xlim(ax), infoOut.voronoiMinTargetSpacingMM * [1 1], ...
                '--', 'Color', [0.85 0.24 0.08], 'LineWidth', 1);
        end
        yyaxis(ax, 'left');
    end
    title(ax, sprintf('Area balance and spacing (%s snap)', ...
        infoOut.voronoiSnapMode));
    grid(ax, 'on');
end

function colors = highContrastCellColors(K)
    if K <= 0
        colors = zeros(0, 3);
        return;
    end
    hue = mod((0:K - 1)' * 0.618033988749895, 1);
    saturation = 0.78 + 0.10 * mod((0:K - 1)', 2);
    value = 0.84 + 0.10 * mod(floor((0:K - 1)' / 2), 2);
    colors = hsv2rgb([hue saturation value]);
end

function labelTargets3(ax, targets, labels)
    for i = 1:size(targets, 1)
        text(ax, targets(i, 1), targets(i, 2), targets(i, 3), ...
            sprintf(' %d', labels(i)), ...
            'Color', 'w', ...
            'FontWeight', 'bold', ...
            'BackgroundColor', [0 0 0], ...
            'Margin', 1, ...
            'Clipping', 'on', ...
            'Interpreter', 'none');
    end
end

function formatSurfaceQcAxes(ax, V)
    boundsMin = min(V, [], 1);
    boundsMax = max(V, [], 1);
    range = boundsMax - boundsMin;
    pad = max(1, 0.04 * max(range));
    range(range <= 0) = 1;
    axis(ax, 'equal');
    axis(ax, 'vis3d');
    axis(ax, 'off');
    xlim(ax, [boundsMin(1) - pad boundsMax(1) + pad]);
    ylim(ax, [boundsMin(2) - pad boundsMax(2) + pad]);
    zlim(ax, [boundsMin(3) - pad boundsMax(3) + pad]);
    view(ax, 3);
    camtarget(ax, 0.5 * (boundsMin + boundsMax));
    try
        camva(ax, 9);
    catch
    end
end

function h = scatterMask3(ax, V, mask, markerSize, colorValue)
    h = gobjects(1, 1);
    if isempty(mask) || ~any(mask)
        return;
    end
    h = scatter3(ax, V(mask, 1), V(mask, 2), V(mask, 3), ...
        markerSize, colorValue, 'filled');
end

function handles = nonemptyHandles(handles)
    handles = handles(isgraphics(handles));
end

function labels = nonemptyLabels(labelsIn, handlesIn)
    keep = isgraphics(handlesIn);
    labels = labelsIn(keep);
end

function drawExclusionSpheres(ax, centers, radii)
    centers = double(centers);
    radii = double(radii(:));
    if isempty(centers)
        return;
    end
    [sx, sy, sz] = sphere(16);
    for i = 1:size(centers, 1)
        surf(ax, centers(i, 1) + radii(i) * sx, ...
            centers(i, 2) + radii(i) * sy, ...
            centers(i, 3) + radii(i) * sz, ...
            'FaceColor', [0.05 0.35 0.95], ...
            'FaceAlpha', 0.08, ...
            'EdgeColor', [0.05 0.35 0.95], ...
            'EdgeAlpha', 0.15, ...
            'HitTest', 'off');
    end
end

function showFootprintExclusionQc(ax, V, infoOut, targets)
    hold(ax, 'on');
    hullXY = infoOut.hullXY;
    plot(ax, hullXY(:, 1), hullXY(:, 2), 'Color', [0.25 0.25 0.25], ...
        'LineWidth', 1.0);
    for i = 1:numel(infoOut.earPolys)
        hPoly = plot(ax, infoOut.earPolys{i});
        set(hPoly, ...
            'FaceColor', [0.95 0.45 0.05], ...
            'FaceAlpha', 0.18, ...
            'EdgeColor', [0.95 0.45 0.05], ...
            'LineWidth', 1.0);
    end
    if isfield(infoOut, 'headpostPoly') && infoOut.headpostPoly.NumRegions > 0
        hPoly = plot(ax, infoOut.headpostPoly);
        set(hPoly, ...
            'FaceColor', [0.45 0.15 0.75], ...
            'FaceAlpha', 0.18, ...
            'EdgeColor', [0.45 0.15 0.75], ...
            'LineWidth', 1.0);
    end
    drawFootprintCircles(ax, infoOut.customExclusionCenters, ...
        infoOut.customExclusionRadiusMM, [0.05 0.35 0.95]);
    scatter(ax, V(infoOut.candidateVertex, 1), V(infoOut.candidateVertex, 2), ...
        8, [0.15 0.65 0.2], 'filled');
    scatter(ax, targets(:, 1), targets(:, 2), 55, [0.05 0.05 0.05], ...
        'filled');
    axis(ax, 'equal');
    grid(ax, 'on');
    xlabel(ax, 'print X (mm)');
    ylabel(ax, 'print Y (mm)');
    title(ax, 'Top-down footprint exclusions');
end

function drawFootprintCircles(ax, centers, radii, colorValue)
    centers = double(centers);
    radii = double(radii(:));
    if isempty(centers)
        return;
    end
    th = linspace(0, 2 * pi, 100);
    for i = 1:size(centers, 1)
        x = centers(i, 1) + radii(i) * cos(th);
        y = centers(i, 2) + radii(i) * sin(th);
        patch(ax, x, y, colorValue, ...
            'FaceAlpha', 0.12, ...
            'EdgeColor', colorValue, ...
            'LineWidth', 0.8);
    end
end
