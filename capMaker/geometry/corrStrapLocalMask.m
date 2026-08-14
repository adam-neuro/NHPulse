function mask = corrStrapLocalMask(Xu,Yu,Zu, params)
% corrStrapLocalMask
%   Corrugated strap in its own local frame:
%     - along +Xu
%     - width along Yu (|Yu| <= W/2)
%     - thickness along Zu around a corrugated centerline
%   Now supports:
%     - bedRunMM: corrugated bed section (square-wave up/over/down/over)
%     - rampRunMM, rampRiseMM: corrugated ramp that climbs in Zu
%
%   params:
%     .zBedLocal   (default 0)
%     .widthMM     (W, default 10)
%     .thickMM     (T, default 2.4)
%     .ampMM       (amp, default 1)
%     .pitchMM     (pitch, default 7)
%     .bedClearanceMM (default 0.2)
%     .bedRunMM    (default 0)   % bed segment length along Xu
%     .rampRunMM   (default 0)   % ramp segment length along Xu
%     .rampRiseMM  (default 0)   % net rise in Zu over rampRun
%     .nCycles     (fallback if bed/ramp not given)
%     .xStart      (default 0)

    if nargin < 4 || isempty(params)
        params = struct;
    end
    g = @(f,def) getOr(params,f,def);

    zBed    = g('zBedLocal',0);
    W       = g('widthMM',10);
    T       = g('thickMM',2.4);
    amp     = g('ampMM',1.0);
    pitch   = g('pitchMM',7.0);
    bedClearance = max(0, g('bedClearanceMM',0.2));

    bedRun  = g('bedRunMM',0);
    rampRun = g('rampRunMM',0);
    rampRise= g('rampRiseMM',0);

    nCyclesFallback = g('nCycles',3);
    x0      = g('xStart',0);

    style = lower(regexprep(char(g('style','swept')), '[\s_\-]+', ''));
    if any(strcmp(style, {'rectilinear', 'rect', 'square', 'squarewave', ...
            'voxel', 'voxelnative'}))
        mask = rectilinearSquareWaveLocalMask(Xu, Yu, Zu, params);
        return;
    end

    % Keep the TPE strap itself corrugated; PLA underfill can support the
    % lowest TPE voxel in each XY column later.
    zLow0  = zBed + T/2 + bedClearance;
    zHigh0 = zLow0 + 2*amp;

    P = [];
    cur = [x0, 0, zLow0];   % [Xu Yu Zu]
    P = [P; cur];

    %% ==== 1) BED-RUN: pure square-wave at fixed low/high ====
    zLow  = zLow0;
    zHigh = zHigh0;

    if bedRun > 0 && pitch > 0
        nBed   = floor(bedRun / pitch);
        Lrem   = max(0, bedRun - nBed*pitch);

        for k = 1:nBed
            % Up
            p1 = [cur(1),        0, zHigh];
            % Over at high
            p2 = [cur(1)+pitch/2,0, zHigh];
            % Down
            p3 = [p2(1),        0, zLow];
            % Over at low
            p4 = [p3(1)+pitch/2,0, zLow];

            P   = [P; p1; p2; p3; p4]; %#ok<AGROW>
            cur = p4;
        end

        % leftover bed at low
        if Lrem > 1e-6
            pend = [cur(1)+Lrem, 0, zLow];
            P    = [P; pend]; %#ok<AGROW>
            cur  = pend;
        end
    elseif bedRun <= 0 && rampRun <= 0
        % fallback: just nCycles square-wave with no ramp
        nCycles = max(1,nCyclesFallback);
        for k = 1:nCycles
            p1 = [cur(1),          0, zHigh];
            p2 = [cur(1)+pitch/2,  0, zHigh];
            p3 = [p2(1),           0, zLow];
            p4 = [p3(1)+pitch/2,   0, zLow];

            P   = [P; p1; p2; p3; p4]; %#ok<AGROW>
            cur = p4;
        end
        % no ramp in this fallback
        zLow0  = zLow;
        zHigh0 = zHigh;
    end

    %% ==== 2) RAMP-RUN: square-wave whose baseline rises ====
    if rampRun > 0 && pitch > 0 && rampRise ~= 0
        nRamp  = max(1, floor(rampRun / pitch));
        LremR  = max(0, rampRun - nRamp*pitch);

        dZ      = rampRise / nRamp;  % rise per full cycle
        lowZ    = zLow;              % start from end-of-bed low
        highZ   = lowZ + 2*amp;

        for k = 1:nRamp
            thisLow  = lowZ;
            thisHigh = highZ;

            % Up to thisHigh
            p1 = [cur(1),        0, thisHigh];
            % Over at high
            p2 = [cur(1)+pitch/2,0, thisHigh];
            % Down to next low (thisLow + dZ)
            nextLow = thisLow + dZ;
            p3 = [p2(1),        0, nextLow];
            % Over at new low
            p4 = [p3(1)+pitch/2,0, nextLow];

            P   = [P; p1; p2; p3; p4]; %#ok<AGROW>
            cur = p4;

            % update low/high for next cycle
            lowZ  = nextLow;
            highZ = lowZ + 2*amp;
        end

        % leftover ramp at final lowZ
        if LremR > 1e-6
            pend = [cur(1)+LremR, 0, lowZ];
            P    = [P; pend]; %#ok<AGROW>
            cur  = pend;
        end
    end

    %% ==== 3) Fill voxels as a constant-thickness square-wave solid ====
    mask  = false(size(Xu));
    halfW = W/2;
    halfT = T/2;

    nSeg = size(P,1)-1;
    for sIdx = 1:nSeg
        Pstart = P(sIdx,:);
        Pend   = P(sIdx+1,:);
        segVec = Pend - Pstart;
        L      = norm(segVec);
        if L < 1e-6, continue; end

        e1 = segVec / L;
        e3 = [-e1(3), 0, e1(1)];
        e3Norm = norm(e3);
        if e3Norm < 1e-12
            e3 = [0 0 1];
        else
            e3 = e3 / e3Norm;
        end

        segMin = min(Pstart, Pend);
        segMax = max(Pstart, Pend);
        bbPad  = [halfT halfW halfT] + 1e-6;
        bbMin  = segMin - bbPad;
        bbMax  = segMax + bbPad;

        inBB = Xu >= bbMin(1) & Xu <= bbMax(1) & ...
               Yu >= bbMin(2) & Yu <= bbMax(2) & ...
               Zu >= bbMin(3) & Zu <= bbMax(3);

        if ~any(inBB(:)), continue; end

        idx = find(inBB);
        Xu_i = Xu(idx); Yu_i = Yu(idx); Zu_i = Zu(idx);
        Qloc = [Xu_i Yu_i Zu_i];

        rel = bsxfun(@minus, Qloc, Pstart);
        u   = rel * e1';  % along-strap coord

        v = Yu_i;       % width in Yu
        w = rel * e3';  % thickness normal to the Xu-Zu square-wave segment

        insideSeg   = (u >= 0) & (u <= L);
        insideWidth = abs(v) <= halfW;
        insideThick = abs(w) <= halfT;

        inside = insideSeg & insideWidth & insideThick;
        mask(idx(inside)) = true;
    end

    mask = mask & (Zu >= zBed);   % no material below local bed
end

function mask = rectilinearSquareWaveLocalMask(Xu, Yu, Zu, params)
% Mark a square-wave strap as axis-aligned local boxes, not swept prisms.
% This keeps the negative spaces between vertical walls open on the voxel grid.
    g = @(f,def) getOr(params,f,def);

    zBed = g('zBedLocal', 0);
    W = g('widthMM', 10);
    T = g('thickMM', 2.4);
    amp = g('ampMM', 1.0);
    pitch = g('pitchMM', 7.0);
    bedClearance = max(0, g('bedClearanceMM', 0.2));
    bedRun = g('bedRunMM', 0);
    rampRun = g('rampRunMM', 0);
    rampRise = g('rampRiseMM', 0);
    nCyclesFallback = g('nCycles', 3);
    x0 = g('xStart', 0);
    fitIntegerCycles = logical(g('fitIntegerCycles', true));

    zLow = zBed + T/2 + bedClearance;
    mask = false(size(Xu));

    if pitch <= 0 || amp <= 0
        totalRun = bedRun + rampRun;
        if totalRun <= 0
            totalRun = max(1, nCyclesFallback) * max(pitch, T);
        end
        mask = addHorizontalBar(mask, Xu, Yu, Zu, x0, x0 + totalRun, ...
            zLow + rampRise/2, W, T);
        mask = mask & (Zu >= zBed);
        return;
    end

    curX = x0;
    [mask, curX, zLow] = addRectWaveSection(mask, Xu, Yu, Zu, curX, ...
        zLow, bedRun, 0, pitch, amp, W, T, fitIntegerCycles);

    if rampRun > 0
        [mask, curX, zLow] = addRectWaveSection(mask, Xu, Yu, Zu, curX, ...
            zLow, rampRun, rampRise, pitch, amp, W, T, fitIntegerCycles);
    elseif bedRun <= 0
        run = max(1, nCyclesFallback) * pitch;
        [mask, curX, zLow] = addRectWaveSection(mask, Xu, Yu, Zu, curX, ...
            zLow, run, 0, pitch, amp, W, T, true); %#ok<ASGLU>
    end

    mask = mask & (Zu >= zBed);
end

function [mask, xEnd, zEnd] = addRectWaveSection(mask, Xu, Yu, Zu, ...
        xStart, zStart, runLength, rise, pitch, amp, W, T, fitIntegerCycles)
    xEnd = xStart;
    zEnd = zStart;
    if runLength <= 0
        return;
    end

    if fitIntegerCycles
        nCycles = max(1, round(runLength / pitch));
        pitchEff = runLength / nCycles;
        leftover = 0;
    else
        nCycles = floor(runLength / pitch);
        if nCycles < 1
            nCycles = 1;
            pitchEff = runLength;
            leftover = 0;
        else
            pitchEff = pitch;
            leftover = max(0, runLength - nCycles * pitchEff);
        end
    end

    for k = 1:nCycles
        x0 = xStart + (k - 1) * pitchEff;
        xMid = x0 + 0.5 * pitchEff;
        x1 = x0 + pitchEff;
        low0 = zStart + rise * (k - 1) / nCycles;
        low1 = zStart + rise * k / nCycles;
        high0 = max(low0, low1) + 2 * amp;

        mask = addVerticalBar(mask, Xu, Yu, Zu, x0, low0, high0, W, T);
        mask = addHorizontalBar(mask, Xu, Yu, Zu, x0, xMid, high0, W, T);
        mask = addVerticalBar(mask, Xu, Yu, Zu, xMid, low1, high0, W, T);
        mask = addHorizontalBar(mask, Xu, Yu, Zu, xMid, x1, low1, W, T);
    end

    xEnd = xStart + nCycles * pitchEff;
    zEnd = zStart + rise;
    if leftover > 1e-6
        mask = addHorizontalBar(mask, Xu, Yu, Zu, xEnd, ...
            xStart + runLength, zEnd, W, T);
        xEnd = xStart + runLength;
    end
end

function mask = addHorizontalBar(mask, Xu, Yu, Zu, xA, xB, zCenter, W, T)
    xMin = min(xA, xB);
    xMax = max(xA, xB);
    if xMax <= xMin
        return;
    end
    halfW = 0.5 * W;
    halfT = 0.5 * T;
    inBar = Xu >= xMin & Xu <= xMax & ...
        abs(Yu) <= halfW & abs(Zu - zCenter) <= halfT;
    mask = mask | inBar;
end

function mask = addVerticalBar(mask, Xu, Yu, Zu, xCenter, zA, zB, W, T)
    zMin = min(zA, zB) - 0.5 * T;
    zMax = max(zA, zB) + 0.5 * T;
    halfW = 0.5 * W;
    halfT = 0.5 * T;
    inBar = abs(Xu - xCenter) <= halfT & ...
        abs(Yu) <= halfW & Zu >= zMin & Zu <= zMax;
    mask = mask | inBar;
end

function v = getOr(s,f,def)
    if isstruct(s) && isfield(s,f) && ~isempty(s.(f))
        v = s.(f);
    else
        v = def;
    end
end
