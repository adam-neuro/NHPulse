function pts = strapExtentPoints(anchor, outDir, paramsLocal, frameOpts)
    if nargin < 4 || isempty(frameOpts), frameOpts = struct; end
    go = @(f,def) getOr(frameOpts,f,def);
    gp = @(f,def) getOr(paramsLocal,f,def);

    zBed    = go('zBed',0);
    ringOff = go('ringOffMM',50);

    tOut = outDir(:)'; if numel(tOut)<3, tOut(3)=0; end
    tOut(3) = 0;
    if norm(tOut) < 1e-12, tOut = [1 0 0]; end
    tOut = tOut / norm(tOut);

    xu_hat = -tOut;
    zu_hat = [0 0 1];
    yu_hat = cross(zu_hat, xu_hat);
    if norm(yu_hat) < 1e-12, yu_hat = [0 1 0]; end
    yu_hat = yu_hat / norm(yu_hat);

    ringTubeDia = go('ringTubeDiaMM', gp('ringTubeDiaMM',3.5));
    ringOD      = go('ringOuterDiaMM', gp('ringOuterDiaMM',20));
    ringOverlap = go('ringOverlapMM',  gp('ringOverlapMM',5));

    r     = ringTubeDia/2;
    ringR = ringOD/2;

    ringC   = anchor + tOut*ringOff;
    ringC(3)= zBed + r;

    P0_world = ringC - tOut*(ringR - ringOverlap);

    W       = gp('widthMM',10);
    T       = gp('thickMM',2.4);
    amp     = gp('ampMM',1.0);
    pitch   = gp('pitchMM',7.0);
    bedRun  = gp('bedRunMM',0);
    rampRun = gp('rampRunMM',0);
    rampRise= gp('rampRiseMM',0);
    x0      = gp('xStart',0);

    zBedLocal = gp('zBedLocal', zBed);
    bedClearance = max(0, gp('bedClearanceMM',0.2));
    zLowLocal = zBedLocal + T/2 + bedClearance;
    zHighLocal= zLowLocal + 2*amp + rampRise;  % include ramp rise

    halfW = W/2;
    totalLen = bedRun + rampRun;
    if totalLen <= 0
        totalLen = max(1, gp('nCycles',3)*pitch);
    end

    xMin = x0;
    xMax = x0 + totalLen;
    yMin = -halfW; yMax = halfW;
    zMin = zLowLocal - T/2;
    zMax = zHighLocal + T/2;

    O = P0_world - xu_hat*x0;
    O(3) = 0;

        % ---- optional: include gauze loop extents ----
    loop = go('loop', struct());
    if isstruct(loop) && getOr(loop,'enable',false)

        % Loop dimensions (local frame)
        loopXc = getOr(loop,'xCenterMM',0);
        loopYc = getOr(loop,'yCenterMM',0);
        loopZc = getOr(loop,'zCenterMM', zLowLocal + T/2);

        loopOX = getOr(loop,'outerXMM',10);
        loopOY = getOr(loop,'outerYMM',14);
        loopT  = getOr(loop,'thickMM',T);

        % Expand local bounds
        xMin = min(xMin, loopXc - loopOX/2);
        xMax = max(xMax, loopXc + loopOX/2);

        yMin = min(yMin, loopYc - loopOY/2);
        yMax = max(yMax, loopYc + loopOY/2);

        zMin = min(zMin, loopZc - loopT/2);
        zMax = max(zMax, loopZc + loopT/2);
    end


    cornersLocal = [
        xMin yMin zMin;
        xMin yMin zMax;
        xMin yMax zMin;
        xMin yMax zMax;
        xMax yMin zMin;
        xMax yMin zMax;
        xMax yMax zMin;
        xMax yMax zMax];

    pts = zeros(size(cornersLocal));
    for i = 1:size(cornersLocal,1)
        x = cornersLocal(i,1);
        y = cornersLocal(i,2);
        z = cornersLocal(i,3);
        pts(i,:) = O + x*xu_hat + y*yu_hat + z*zu_hat;
    end
end

function v = getOr(s,f,def)
    if isstruct(s) && isfield(s,f) && ~isempty(s.(f))
        v = s.(f);
    else
        v = def;
    end
end
