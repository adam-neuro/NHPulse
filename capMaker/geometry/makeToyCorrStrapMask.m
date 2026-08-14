function mask = makeToyCorrStrapMask(X,Y,Z, params)
% makeToyCorrStrapMask
%   Minimal test: corrugated strap lying on the printer bed.
%   Path is in the X–Z plane, width is in Y, thickness is in Z.
%
%   params:
%     .zBed     (default 0)
%     .widthMM  (W, default 10)
%     .thickMM  (T, default 2.4)
%     .ampMM    (cAmp, default 2)           % half vertical swing
%     .pitchMM  (cPitch, default 20)        % full cycle length (x)
%     .nCycles  (default 3)
%     .xStart   (default 0)
%
%   Usage:
%     [X,Y,Z] = ndgrid(x,y,z);
%     mask = makeToyCorrStrapMask(X,Y,Z, params);

    if nargin < 4 || isempty(params)
        params = struct;
    end

    % safe getter
    g = @(f,def) getOr(params,f,def);

    zBed    = g('zBed',0);
    W       = g('widthMM',5);
    T       = g('thickMM',2.4);
    amp     = g('ampMM',2.0);
    pitch   = g('pitchMM',10.0);
    nCycles = g('nCycles',3);
    x0      = g('xStart',0);

    % Choose low z so bottom is just at/above zBed
    zLow  = zBed + T/2 + 1e-3;
    zHigh = zLow + 2*amp;

    % Build centerline polyline P in X–Z (Y=0)
    P = [];
    cur = [x0, 0, zLow];   % [x y z]
    P = [P; cur];

    for k = 1:nCycles
        % Up
        p1 = [cur(1),          0, zHigh];
        % Over at high
        p2 = [cur(1)+pitch/2,  0, zHigh];
        % Down
        p3 = [p2(1),           0, zLow];
        % Over at low
        p4 = [p3(1)+pitch/2,   0, zLow];

        P   = [P; p1; p2; p3; p4]; %#ok<AGROW>
        cur = p4;
    end

    % ----- voxel fill: rectangular ribbon around P -----
    mask  = false(size(X));
    halfW = W/2;
    halfT = T/2;

    nSeg = size(P,1)-1;
    for sIdx = 1:nSeg
        Pstart = P(sIdx,:);
        Pend   = P(sIdx+1,:);
        segVec = Pend - Pstart;
        L      = norm(segVec);
        if L < 1e-6, continue; end

        % Along-strap direction (3D)
        e1 = segVec / L;

        % Bounding box for this segment
        segMin = min(Pstart, Pend);
        segMax = max(Pstart, Pend);
        bbMin  = segMin + [-0.5 -halfW -halfT];
        bbMax  = segMax + [ 0.5  halfW  halfT];

        inBB = X >= bbMin(1) & X <= bbMax(1) & ...
               Y >= bbMin(2) & Y <= bbMax(2) & ...
               Z >= bbMin(3) & Z <= bbMax(3);

        if ~any(inBB(:)), continue; end

        idx = find(inBB);
        Px  = X(idx); Py = Y(idx); Pz = Z(idx);
        Q   = [Px Py Pz];

        % Along-strap coordinate u along e1
        rel = bsxfun(@minus, Q, Pstart);
        u   = rel * e1';  % scalar

        % Interpolate centerline z at this u
        dz      = Pend(3) - Pstart(3);
        zCenter = Pstart(3) + (u / L) * dz;

        % Width: just |Y| <= W/2
        v = Py;   % Y-coordinate

        % Thickness: vertical distance from centerline
        w = Pz - zCenter;

        insideSeg   = (u >= 0) & (u <= L);
        insideWidth = abs(v) <= halfW;
        insideThick = abs(w) <= halfT;

        inside = insideSeg & insideWidth & insideThick;
        mask(idx(inside)) = true;
    end

    % Nothing below the bed
    mask = mask & (Z >= zBed);
end

function v = getOr(s,f,def)
    if isstruct(s) && isfield(s,f) && ~isempty(s.(f))
        v = s.(f);
    else
        v = def;
    end
end
