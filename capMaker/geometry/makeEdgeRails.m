function [TRrails, info] = makeEdgeRails(skullTR, railW, railH, embedFrac, minLen, zThresh, zEps, varargin)
% MAKEEDGERAILS  Build rectangular rails along edges of skullTR.
% New name-value params:
%   'PerimeterFactor'  scalar >=1 (default 1.0) - thickness multiplier on the cap's outer rim
%   'AllBoundaries'    logical (default false) - if true, thicken all boundary components
%   'BoundaryMarginMm' scalar >=0 (default 0) - skip rails close to selected boundary
%   'SphereExcludeCenters' Nx3 centers for 3D exclusion spheres [empty]
%   'SphereExcludeRadii'   Nx1 radii for 3D exclusion spheres [empty]
%   'VertexExcludeInd'     mesh vertex rows that cannot be rail endpoints
%   'VertexExcludePoints'  mesh coordinates that cannot be rail endpoints
%   'VertexExcludeToleranceMm' coordinate matching tolerance [1e-3]
%
% When requested with two outputs, info.builtEdges and
% info.builtFaceRanges map each generated rail back to its source mesh edge.
% This lets downstream code trim small rail islands without guessing from
% STL triangle contacts.
%
% Existing args:
%   skullTR, railW, railH, embedFrac, minLen, zThresh, zEps

    if nargin < 6 || isempty(zThresh), zThresh = 0;     end
    if nargin < 7 || isempty(zEps),    zEps    = 1e-6;  end

    p = inputParser;
    p.addParameter('PerimeterFactor', 1.0, @(x)isnumeric(x)&&isscalar(x)&&x>=1);
    p.addParameter('AllBoundaries',   false, @(x)islogical(x)&&isscalar(x));
    p.addParameter('BoundaryMarginMm', 0, ...
        @(x)isnumeric(x)&&isscalar(x)&&isfinite(x)&&x>=0);
    p.addParameter('EarExcludePolys', {}, @(c) iscell(c));   % cell array of polyshape (XY)
    p.addParameter('SphereExcludeCenters', zeros(0, 3), ...
        @(x) isempty(x) || (isnumeric(x) && size(x, 2) == 3));
    p.addParameter('SphereExcludeRadii', zeros(0, 1), ...
        @(x) isempty(x) || (isnumeric(x) && isvector(x)));
    p.addParameter('VertexExcludeInd', [], ...
        @(x) isempty(x) || (isnumeric(x) && isvector(x)));
    p.addParameter('VertexExcludePoints', zeros(0, 3), ...
        @(x) isempty(x) || (isnumeric(x) && size(x, 2) == 3));
    p.addParameter('VertexExcludeToleranceMm', 1e-3, ...
        @(x)isnumeric(x)&&isscalar(x)&&isfinite(x)&&x>=0);
    p.addParameter('Verbose', false, @(x)(islogical(x)||isnumeric(x))&&isscalar(x));
    p.parse(varargin{:});
    PerimeterFactor = p.Results.PerimeterFactor;
    AllBoundaries   = p.Results.AllBoundaries;
    BoundaryMarginMm = double(p.Results.BoundaryMarginMm);
    EarExcludePolys = p.Results.EarExcludePolys;
    [SphereExcludeCenters, SphereExcludeRadii] = normalizeSphereExclusions( ...
        p.Results.SphereExcludeCenters, p.Results.SphereExcludeRadii);
    VertexExcludeInd = p.Results.VertexExcludeInd;
    VertexExcludePoints = double(p.Results.VertexExcludePoints);
    VertexExcludeToleranceMm = double(p.Results.VertexExcludeToleranceMm);
    Verbose = logical(p.Results.Verbose);

    % --- Basic geometry / trimming mask
    P  = skullTR.Points; 
    F  = skullTR.ConnectivityList;
    z  = P(:,3);
    baseFace    = all(z(F) <= (zThresh + zEps), 2);    % faces entirely below threshold
    capFaceMask = ~baseFace;                           % faces belonging to the cap
    TRcap = triangulation(F(capFaceMask,:), P);        % trimmed cap (same vertex array)

    % --- Detect perimeter edges on the trimmed cap
    % Boundary edges can be open, branched, or non-simple after crop/decimation,
    % so use connected components instead of walking a perfect closed loop.
    B = freeBoundary(TRcap);           % Mx2 boundary edges (vertex indices in TRcap / same P)
    isPerimeterEdge = false(size(edges(skullTR),1),1);
    perimeterBoundaryEdges = zeros(0, 2);
    components = {};
    chosen = [];
    if ~isempty(B)
        logMsg(Verbose, 'makeEdgeRails: finding boundary components from %d boundary edges.', size(B,1));
        components = boundaryComponents(B);
        logMsg(Verbose, 'makeEdgeRails: found %d boundary components.', numel(components));
        if AllBoundaries
            chosen = 1:numel(components);
        else
            % Choose the component with largest projected convex-hull area.
            areas = zeros(numel(components),1);
            if size(P,1) >= 3
                [coeff,~,~] = pca(P); 
                R = coeff(:,1:2);
            else
                R = eye(3,2);
            end
            for i = 1:numel(components)
                Vcomp = P(components{i},:)*R;          % Nx2
                if size(Vcomp, 1) >= 3
                    try
                        kHull = convhull(Vcomp(:,1), Vcomp(:,2));
                        areas(i) = polyarea(Vcomp(kHull,1), Vcomp(kHull,2));
                    catch
                        areas(i) = 0;
                    end
                end
            end
            [~,iMax] = max(areas);
            chosen = iMax;
        end
        % Build a hash of selected boundary edges, then mark in full edge list.
        Eall = edges(skullTR);                     % unique undirected edges of skullTR
        Kall = edgeKeyMat(sort(Eall,2));
        mask = false(size(Eall,1),1);
        for i = chosen
            verts = components{i};
            inComp = ismember(B(:,1), verts) & ismember(B(:,2), verts);
            eComp = sort(B(inComp, :), 2);
            if ~isempty(eComp)
                perimeterBoundaryEdges = [perimeterBoundaryEdges; eComp]; %#ok<AGROW>
                Kcomp = edgeKeyMat(eComp);
                mask = mask | ismember(Kall, Kcomp);
            end
        end
        isPerimeterEdge = mask;
    end

    % --- Normals and edges
    Nv = vertexNormal(skullTR); Nv = Nv ./ max(vecnorm(Nv,2,2),eps);
    Nf = faceNormal(skullTR);
    E  = edges(skullTR);

    Vall = zeros(0,3); 
    Fall = zeros(0,3);
    vertexExcluded = vertexExclusionMask(P, VertexExcludeInd, ...
        VertexExcludePoints, VertexExcludeToleranceMm);
    info = initRailBuildInfo(P, F, E, B, components, chosen, ...
        BoundaryMarginMm, SphereExcludeCenters, EarExcludePolys, ...
        vertexExcluded);

    % --------- MAIN LOOP ----------
    logMsg(Verbose, 'makeEdgeRails: building rail prisms for %d mesh edges.', size(E,1));
    for k = 1:size(E,1)
        if Verbose && (k == 1 || mod(k, 500) == 0)
            logMsg(Verbose, 'makeEdgeRails: edge %d / %d.', k, size(E,1));
        end
        i = E(k,1); j = E(k,2);
        Pi = P(i,:);  Pj = P(j,:);
        if vertexExcluded(i) || vertexExcluded(j)
            info.nSkippedVertexExclusion = info.nSkippedVertexExclusion + 1;
            continue;
        end
        seg = Pj - Pi; 
        L = norm(seg);
        if L <= minLen || L==0
            info.nSkippedShort = info.nSkippedShort + 1;
            continue;
        end

        % Skip rails wholly on the base (below zThresh)
        at = edgeAttachments(skullTR,i,j); at = at{1};
        if ~isempty(at) && all(baseFace(at))
            info.nSkippedBase = info.nSkippedBase + 1;
            continue;
        end

        % Skip rails close to the selected crop/perimeter boundary.
        if BoundaryMarginMm > 0 && ~isempty(perimeterBoundaryEdges) && ...
                edgeTooCloseToBoundary(Pi, Pj, P, perimeterBoundaryEdges, BoundaryMarginMm)
            info.nSkippedBoundaryMargin = info.nSkippedBoundaryMargin + 1;
            continue;
        end

        % --- 3D spherical exclusions: skip if the edge centerline enters a sphere.
        if ~isempty(SphereExcludeCenters) && ...
                edgeIntersectsAnySphere(Pi, Pj, SphereExcludeCenters, SphereExcludeRadii)
            info.nSkippedSphere = info.nSkippedSphere + 1;
            continue;
        end

        % --- Projected exclusions: project this edge to XY and skip if it lies in a region.
        if ~isempty(EarExcludePolys)
            Pi2 = Pi(1:2); Pj2 = Pj(1:2);   % XY
            if edgeInAnyPoly(Pi2, Pj2, EarExcludePolys)
                info.nSkippedProjectedPoly = info.nSkippedProjectedPoly + 1;
                continue;  % skip building this rail
            end
        end

        % Local frame
        t = seg / L;
        n = Nv(i,:) + Nv(j,:);
        if ~isfinite(norm(n)) || norm(n) < 1e-9
            if ~isempty(at)
                n = mean(Nf(at,:),1);
            end
            if ~isfinite(norm(n)) || norm(n) < 1e-9
                n = [0 0 1];
            end
        end
        n = n / norm(n);
        w = cross(n,t);
        if norm(w) < 1e-9
            [~,ax] = max(abs(n)); e = zeros(1,3); e(ax)=1; w = cross(n,e);
        end
        w = w / norm(w);

        % Per-edge width (thicken perimeter rails)
        railWk = railW * (isPerimeterEdge(k)* (PerimeterFactor-1) + 1);
        halfW  = 0.5 * railWk;

        zBot = -embedFrac*railH; 
        zTop = (1-embedFrac)*railH;
        ext  = min(halfW, 0.49*L);         % overrun past vertices

        P1 = Pi - ext*t;  P2 = Pj + ext*t;

        v1 = P1 + (-halfW)*w + zBot*n;  v2 = P1 + ( halfW)*w + zBot*n;
        v3 = P1 + ( halfW)*w + zTop*n;  v4 = P1 + (-halfW)*w + zTop*n;
        v5 = P2 + (-halfW)*w + zBot*n;  v6 = P2 + ( halfW)*w + zBot*n;
        v7 = P2 + ( halfW)*w + zTop*n;  v8 = P2 + (-halfW)*w + zTop*n;

        Vrail = [v1; v2; v3; v4; v5; v6; v7; v8];

        % Faces via convex hull (robust) then orient outward w.r.t. prism centroid
        Frail = convhulln(Vrail);
        Crail = mean(Vrail,1);
        for f = 1:size(Frail,1)
            a = Vrail(Frail(f,1),:);
            b = Vrail(Frail(f,2),:);
            c = Vrail(Frail(f,3),:);
            N = cross(b-a, c-a);
            if any(N)
                N = N / norm(N);
                fc = (a+b+c)/3;
                if dot(N, Crail - fc) > 0
                    Frail(f,[2 3]) = Frail(f,[3 2]);
                end
            end
        end

        off = size(Vall,1);
        faceStart = size(Fall, 1) + 1;
        faceEnd = size(Fall, 1) + size(Frail, 1);
        Vall = [Vall; Vrail]; %#ok<AGROW>
        Fall = [Fall; Frail + off]; %#ok<AGROW>
        info.nBuiltRails = info.nBuiltRails + 1;
        info.builtEdgeRows(end + 1, 1) = k; %#ok<AGROW>
        info.builtEdges(end + 1, :) = [i j]; %#ok<AGROW>
        info.builtFaceRanges(end + 1, :) = [faceStart faceEnd]; %#ok<AGROW>
    end

    TRrails = triangulation(Fall, Vall);
    info.nBuiltFaces = size(Fall, 1);
    logMsg(Verbose, 'makeEdgeRails: built %d rail faces.', size(Fall,1));
    if Verbose
        logMsg(Verbose, ['makeEdgeRails: skipped edges - short %d, ', ...
            'base %d, vertex %d, boundary %d, sphere %d, ', ...
            'projected poly %d; built rails %d.'], ...
            info.nSkippedShort, info.nSkippedBase, ...
            info.nSkippedVertexExclusion, info.nSkippedBoundaryMargin, ...
            info.nSkippedSphere, info.nSkippedProjectedPoly, ...
            info.nBuiltRails);
    end
end

% ---------- helpers ----------
function mask = vertexExclusionMask(P, rows, points, tolMm)
    mask = false(size(P, 1), 1);
    if ~isempty(rows)
        rows = unique(round(double(rows(:))));
        rows = rows(isfinite(rows) & rows >= 1 & rows <= size(P, 1));
        mask(rows) = true;
    end
    if isempty(points)
        return;
    end
    points = double(points);
    points = points(all(isfinite(points), 2), :);
    if isempty(points)
        return;
    end
    tol2 = max(double(tolMm), 0) .^ 2;
    for i = 1:size(points, 1)
        d2 = sum((P - points(i, :)) .^ 2, 2);
        mask = mask | d2 <= tol2;
    end
end

function info = initRailBuildInfo(P, F, E, B, components, chosen, ...
        BoundaryMarginMm, SphereExcludeCenters, EarExcludePolys, ...
        vertexExcluded)
    info = struct();
    info.nInputVertices = size(P, 1);
    info.nInputFaces = size(F, 1);
    info.nCandidateEdges = size(E, 1);
    info.nBoundaryEdges = size(B, 1);
    info.nBoundaryComponents = numel(components);
    info.selectedBoundaryComponents = chosen(:)';
    info.boundaryMarginMm = BoundaryMarginMm;
    info.nSphereExclusions = size(SphereExcludeCenters, 1);
    info.nProjectedExclusionPolys = numel(EarExcludePolys);
    info.nVertexExclusions = nnz(vertexExcluded);
    info.nSkippedShort = 0;
    info.nSkippedBase = 0;
    info.nSkippedVertexExclusion = 0;
    info.nSkippedBoundaryMargin = 0;
    info.nSkippedSphere = 0;
    info.nSkippedProjectedPoly = 0;
    info.nBuiltRails = 0;
    info.nBuiltFaces = 0;
    info.builtEdgeRows = zeros(0, 1);
    info.builtEdges = zeros(0, 2);
    info.builtFaceRanges = zeros(0, 2);
end

function components = boundaryComponents(B)
% Convert boundary edge list B (Mx2) into connected vertex components.
    if isempty(B), components = {}; return; end
    maxv = max(B(:));
    nbr = cell(maxv,1);
    for r = 1:size(B,1)
        a = B(r,1); b = B(r,2);
        nbr{a} = [nbr{a}, b];
        nbr{b} = [nbr{b}, a];
    end
    seen = false(maxv,1);
    components = {};
    starts = unique(B(:))';
    for s = starts
        if seen(s), continue; end
        if isempty(nbr{s}), continue; end
        stack = s;
        comp = zeros(0,1);
        seen(s) = true;
        while ~isempty(stack)
            cur = stack(end);
            stack(end) = [];
            comp(end+1,1) = cur; %#ok<AGROW>
            next = nbr{cur};
            if ~isempty(next)
                next = next(~seen(next));
            end
            if ~isempty(next)
                seen(next) = true;
                stack = [stack, next]; %#ok<AGROW>
            end
        end
        if numel(comp) >= 2
            components{end+1} = comp; %#ok<AGROW>
        end
    end
end

function K = edgeKeyMat(E)
% 64-bit hash (undirected) for edge rows [i j] with i<j
    E = uint64(E);
    K = E(:,1) * uint64(4294967296) + E(:,2);
end

function [centers, radii] = normalizeSphereExclusions(centers, radii)
    centers = double(centers);
    radii = double(radii(:));
    if isempty(centers) || isempty(radii)
        centers = zeros(0, 3);
        radii = zeros(0, 1);
        return;
    end
    if size(centers, 2) ~= 3
        error('makeEdgeRails:BadSphereExclusions', ...
            'SphereExcludeCenters must be an N x 3 numeric matrix.');
    end
    if isscalar(radii) && size(centers, 1) > 1
        radii = repmat(radii, size(centers, 1), 1);
    end
    if numel(radii) ~= size(centers, 1)
        error('makeEdgeRails:BadSphereExclusions', ...
            'SphereExcludeRadii must be scalar or have one value per sphere center.');
    end
    keep = all(isfinite(centers), 2) & isfinite(radii) & radii > 0;
    centers = centers(keep, :);
    radii = radii(keep);
end

function tf = edgeIntersectsAnySphere(Pa, Pb, centers, radii)
    tf = false;
    for k = 1:size(centers, 1)
        if pointSegmentDistance3D(centers(k, :), Pa, Pb) <= radii(k)
            tf = true;
            return;
        end
    end
end

function tf = edgeTooCloseToBoundary(Pa, Pb, V, boundaryEdges, marginMm)
    tf = false;
    if marginMm <= 0 || isempty(boundaryEdges)
        return;
    end
    query = [Pa; Pb; 0.5 * (Pa + Pb)];
    for e = 1:size(boundaryEdges, 1)
        A = V(boundaryEdges(e, 1), :);
        B = V(boundaryEdges(e, 2), :);
        for q = 1:size(query, 1)
            if pointSegmentDistance3D(query(q, :), A, B) <= marginMm
                tf = true;
                return;
            end
        end
        if pointSegmentDistance3D(A, Pa, Pb) <= marginMm || ...
                pointSegmentDistance3D(B, Pa, Pb) <= marginMm
            tf = true;
            return;
        end
    end
end

function d = pointSegmentDistance3D(P, A, B)
    AB = B - A;
    denom = dot(AB, AB);
    if denom <= eps
        d = norm(P - A);
        return;
    end
    t = dot(P - A, AB) / denom;
    t = min(max(t, 0), 1);
    closest = A + t * AB;
    d = norm(P - closest);
end

function tf = edgeInAnyPoly(Pa, Pb, polys)
% Pa, Pb: 1x2 endpoints in XY
% polys : cell array of polyshape (ear exclusion regions)
    tf = false;
    for k = 1:numel(polys)
        pk = polys{k};
        if pk.NumRegions == 0 || area(pk) == 0, continue; end
        % Fast checks: endpoints inside?
        if isinterior(pk, Pa(1), Pa(2)) || isinterior(pk, Pb(1), Pb(2))
            tf = true; return;
        end
        % Segment intersects polygon boundary?
        if segmentIntersectsPoly(Pa, Pb, pk)
            tf = true; return;
        end
        % Segment entirely inside polygon (endpoints might be on boundary):
        % sample mid-point as a cheap extra check
        Pm = 0.5*(Pa+Pb);
        if isinterior(pk, Pm(1), Pm(2))
            tf = true; return;
        end
    end
end

function tf = segmentIntersectsPoly(Pa, Pb, ps)
% Robustly test if segment Pa-Pb intersects any boundary edge of polyshape ps.
    tf = false;
    [xb,yb] = boundary(ps);   % NaN-separated rings
    if isempty(xb), return; end
    i0 = 1;
    for i = 1:numel(xb)
        if i==numel(xb) || isnan(xb(i))
            X = xb(i0:i-1); Y = yb(i0:i-1);
            if numel(X) >= 2
                for j = 1:numel(X)-1
                    Pc = [X(j)   Y(j)];
                    Pd = [X(j+1) Y(j+1)];
                    if segSegIntersect2D(Pa, Pb, Pc, Pd)
                        tf = true; return;
                    end
                end
                % close ring
                if segSegIntersect2D(Pa, Pb, [X(end) Y(end)], [X(1) Y(1)])
                    tf = true; return;
                end
            end
            i0 = i + 1;
        end
    end
end

function tf = segSegIntersect2D(A, B, C, D)
% Proper segment-segment intersection (including touching)
    tf = false;
    o1 = orient2D(A,B,C); o2 = orient2D(A,B,D);
    o3 = orient2D(C,D,A); o4 = orient2D(C,D,B);
    if (o1*o2 < 0) && (o3*o4 < 0), tf = true; return; end
    % collinear / touching cases
    if o1==0 && onSeg(A,B,C), tf=true; return; end
    if o2==0 && onSeg(A,B,D), tf=true; return; end
    if o3==0 && onSeg(C,D,A), tf=true; return; end
    if o4==0 && onSeg(C,D,B), tf=true; return; end
end

function v = orient2D(P, Q, R)
% Cross product sign of (Q-P) x (R-P)
    v = (Q(1)-P(1))*(R(2)-P(2)) - (Q(2)-P(2))*(R(1)-P(1));
    v = sign(v);
end

function tf = onSeg(P, Q, R)
% Is R on closed segment PQ (assuming collinear)?
    tf = (min(P(1),Q(1)) - 1e-12 <= R(1)) && (R(1) <= max(P(1),Q(1)) + 1e-12) && ...
         (min(P(2),Q(2)) - 1e-12 <= R(2)) && (R(2) <= max(P(2),Q(2)) + 1e-12);
end

function logMsg(verbose, varargin)
    if verbose
        fprintf([varargin{1} '\n'], varargin{2:end});
        drawnow('limitrate');
    end
end
