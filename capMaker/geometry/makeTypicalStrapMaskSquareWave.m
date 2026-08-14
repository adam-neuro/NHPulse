function mask = makeTypicalStrapMaskSquareWave(X,Y,Z, anchor, outDir, opts)
% MAKETYPICALSTRAPMASKSQUAREWAVE
%   Voxel-native strap with a *square-wave* serpentine centerline:
%       up → over → down → over   (repeated)
%   applied across:
%       - a flat bed-run
%       - a ramp-run with net rise
%   and then a short approach toward the anchor.
%
%   Geometry:
%     - Constant width W and thickness T
%     - Folds in the plane spanned by {dIn, up}, where:
%           dIn = inward direction along the bed (toward the cap)
%           up  = [0 0 1]
%     - Thickness is always vertical (Z)
%     - Width is always in XY, perpendicular to local bed-like direction
%     - No part of the strap goes below z = zBed.

    if nargin < 2 || isempty(outDir)
        error('Need outDir (XY direction).');
    end
    if nargin < 3, opts = struct; end
    g = @(f,def) getOr(opts,f,def);

    % ---------- parameters ----------
    zBed        = g('zBed',0);
    ahead       = g('strapAheadMM',0);
    bedRun      = g('bedRunMM',60);
    rampRun     = g('rampRunMM',20);
    rampRise    = g('rampRiseMM',20);
    approach    = g('approachMM',3);

    W           = g('strapWidthMM',20);
    T           = g('strapThickMM',2.4);

    cAmp        = g('corrAmpMM',2.0);    % half of vertical swing of a "fold"
    cPitch      = g('corrPitchMM',5.0);  % horizontal distance per full cycle

    ringOD      = g('ringOuterDiaMM',20);
    ringTube    = g('ringTubeDiaMM',3.5);
    ringOff     = g('ringOffsetMM',50);
    ringOverlap = g('ringOverlapMM',-15);

    % ---------- directions ----------
    tOut = outDir(:)'; if numel(tOut)<3, tOut(3)=0; end
    tOut(3) = 0;
    if norm(tOut) < 1e-12, tOut = [1 0 0]; end
    tOut = tOut / norm(tOut);

    dIn  = -tOut;             % inward along bed, toward cap
    up   = [0 0 1];

    % ---------- ring center on bed ----------
    r       = ringTube/2;
    ringR   = ringOD/2;
    ringC   = anchor + tOut*ringOff;
    ringC(3)= zBed + r;
    ringC(2)= ringC(2) + ahead;

    % ---------- choose lowest centerline height so bottom ≈ zBed ----------
    % We want:
    %   min_centerline_z = zLow
    %   bottom_z = zLow - T/2 ≥ zBed
    % so pick:
    zLow  = zBed + T/2 + 1e-3;        % "low" level of folds
    zHigh = zLow + 2*cAmp;            % "high" level of folds

    % ---------- initial point at inboard ring tangent ----------
    P0 = ringC - tOut*(ringR - ringOverlap);
    P0(3) = zLow;

    P = P0;
    cur = P0;

    %% ================= BED-RUN: pure square-wave up/over/down/over =================
    if cPitch > 0 && cAmp > 0 && bedRun > 0
        nCyclesBed = floor(bedRun / cPitch);
        LremBed    = max(0, bedRun - nCyclesBed*cPitch);

        for k = 1:nCyclesBed
            % Up to high
            p1 = cur + (zHigh - cur(3)) * up;     % ensures we land exactly at zHigh
            % Over half-pitch at high
            p2 = p1 + dIn*(cPitch/2);
            % Down to low
            p3 = p2 + (zLow - p2(3)) * up;        % go down to zLow
            % Over half-pitch at low
            p4 = p3 + dIn*(cPitch/2);

            P   = [P; p1; p2; p3; p4]; %#ok<AGROW>
            cur = p4;
        end

        % leftover straight bed run at low height
        if LremBed > 1e-6
            pend = cur + dIn*LremBed;
            pend(3) = zLow;
            P   = [P; pend]; %#ok<AGROW>
            cur = pend;
        end
    else
        % no corrugation on bed (fallback)
        if bedRun > 0
            pend = cur + dIn*bedRun;
            pend(3) = zLow;
            P   = [P; pend]; %#ok<AGROW>
            cur = pend;
        end
    end

    %% ================= RAMP-RUN: square-wave with net rise =================
    if rampRun > 0 && cPitch > 0 && cAmp > 0 && rampRise ~= 0
        nCyclesRamp = max(1, floor(rampRun / cPitch));
        LremRamp    = max(0, rampRun - nCyclesRamp*cPitch);

        dZ          = rampRise / nCyclesRamp;   % low level drifts up by this per cycle

        % We'll keep a near-constant amplitude ~2*cAmp while shifting low/high
        lowZ  = zLow;
        highZ = lowZ + 2*cAmp;

        for k = 1:nCyclesRamp
            % high/low for this cycle
            highZ_k = highZ;
            lowZ_k  = lowZ;

            % Up to highZ_k
            p1 = cur + (highZ_k - cur(3)) * up;
            % Over half-pitch at high
            p2 = p1 + dIn*(cPitch/2);
            % Down toward lowZ_k + dZ (so next cycle's low is a bit higher)
            nextLow = lowZ_k + dZ;
            p3 = p2 + (nextLow - p2(3)) * up;
            % Over half-pitch at this new low
            p4 = p3 + dIn*(cPitch/2);

            P   = [P; p1; p2; p3; p4]; %#ok<AGROW>
            cur = p4;

            % Update low/high for next cycle
            lowZ  = nextLow;
            highZ = lowZ + 2*cAmp;
        end

        % leftover run at final lowZ
        if LremRamp > 1e-6
            pend = cur + dIn*LremRamp;
            pend(3) = lowZ;
            P   = [P; pend]; %#ok<AGROW>
            cur = pend;
        end
    elseif rampRun > 0
        % fallback: simple straight ramp (no corrugation) if params degenerate
        P2 = cur + dIn*rampRun + rampRise*up;
        if P2(3) < zLow, P2(3) = zLow; end
        P   = [P; P2]; %#ok<AGROW>
        cur = P2;
    end

    %% ================= APPROACH TO ANCHOR =================
    if approach > 0
        P_rampEnd = cur;
        vTo = anchor - P_rampEnd;
        vTo = vTo ./ max(1e-12, norm(vTo));
        P_app = P_rampEnd + approach * vTo;
        P_app(3) = max(P_app(3), zLow);   % don't dip below low level

        P = [P; P_rampEnd; P_app]; %#ok<AGROW>
    end

    %% ================= VOXEL FILL: rectangular ribbon around P =================
    mask   = false(size(X));
    halfW  = W / 2;
    halfT  = T / 2;

    nSeg = size(P,1) - 1;
    for sIdx = 1:nSeg
        Pstart = P(sIdx,:);
        Pend   = P(sIdx+1,:);
        segVec = Pend - Pstart;
        L      = norm(segVec);
        if L < 1e-6, continue; end

        % Along-strap direction (3D)
        e1 = segVec / L;

        % Bed-like direction in XY: projection of segment into XY plane
        segXY = [segVec(1) segVec(2) 0];
        if norm(segXY) < 1e-6
            % vertical-ish segment: fall back to dIn in XY
            eBed = [dIn(1) dIn(2) 0];
        else
            eBed = segXY;
        end
        eBed = eBed / norm(eBed);

        % Width direction in XY (perp to eBed)
        widthDir = [-eBed(2) eBed(1) 0];  % rotate 90° in XY
        widthDir = widthDir / norm(widthDir);

        % Bounding box in world coords for this segment
        segMin = min(Pstart, Pend);
        segMax = max(Pstart, Pend);
        bbMin  = segMin - [halfW halfW halfT];
        bbMax  = segMax + [halfW halfW halfT];

        inBB = X >= bbMin(1) & X <= bbMax(1) & ...
               Y >= bbMin(2) & Y <= bbMax(2) & ...
               Z >= bbMin(3) & Z <= bbMax(3);

        if ~any(inBB(:)), continue; end

        idx = find(inBB);
        Px  = X(idx); Py = Y(idx); Pz = Z(idx);
        Q   = [Px Py Pz];

        % Along-strap coordinate u (3D)
        rel = bsxfun(@minus, Q, Pstart);
        u   = rel * e1';                 % scalar per voxel

        % Centerline z at each u via linear interpolation
        dz      = Pend(3) - Pstart(3);
        zCenter = Pstart(3) + (u / L) * dz;

        % Width coordinate in XY
        relXY       = rel;
        relXY(:,3)  = 0;
        v           = relXY * widthDir'; % width

        % Thickness coordinate: purely vertical distance from centerline
        w = Pz - zCenter;

        insideSeg   = (u >= 0) & (u <= L);
        insideWidth = abs(v) <= halfW;
        insideThick = abs(w) <= halfT;

        inside = insideSeg & insideWidth & insideThick;
        mask(idx(inside)) = true;
    end

    % Belt & suspenders: never keep anything below the bed
    mask = mask & (Z >= zBed);
end

% ---------- helper ----------
function v = getOr(s,f,def)
    if isstruct(s) && isfield(s,f) && ~isempty(s.(f)), v = s.(f); else, v = def; end
end
