function mask = strapFn_world(X,Y,Z, anchor, outDir, paramsLocal, frameOpts)
% strapFn_world
%   World-frame occupancy for a corrugated strap defined in a local frame.

    if nargin < 7 || isempty(frameOpts), frameOpts = struct; end
    go = @(f,def) getOr(frameOpts,f,def);

    zBed      = go('zBed',0);
    ringOff   = go('ringOffMM',50);
    startShift= go('startShiftMM',0);

    % --- define strap local axes in world ---
    tOut = outDir(:)'; if numel(tOut)<3, tOut(3)=0; end
    tOut(3) = 0;
    if norm(tOut) < 1e-12, tOut = [1 0 0]; end
    tOut = tOut / norm(tOut);

    xu_hat = -tOut;          % strap runs inward from ring toward cap
    zu_hat = [0 0 1];        % corrugation "up" = world Z
    yu_hat = cross(zu_hat, xu_hat);
    if norm(yu_hat) < 1e-12, yu_hat = [0 1 0]; end
    yu_hat = yu_hat / norm(yu_hat);

    % --- ring center on bed ---
    ringTubeDia = getOr(paramsLocal,'ringTubeDiaMM',3.5);
    ringOD      = getOr(paramsLocal,'ringOuterDiaMM',20);
    ringOverlap = getOr(paramsLocal,'ringOverlapMM',5);

    r     = ringTubeDia/2;
    ringR = ringOD/2;

    ringC   = anchor + tOut*ringOff;
    ringC(3)= zBed + r;

    P0_world = ringC - tOut*(ringR - ringOverlap);

    paramsLocal.zBedLocal = zBed;
    x0 = getOr(paramsLocal,'xStart',0);

    T = getOr(paramsLocal,'thickMM',2.4);

    % Keep local Zu in the printer/world Z frame so zBedLocal and
    % bedClearanceMM are physical distances from the support plane. The
    % ring/strap endpoint controls the in-plane start location only.
    O = P0_world - xu_hat*x0;
    O(3) = 0;

    if startShift ~= 0
        O = O + xu_hat * (-startShift);
        paramsLocal.xStart = x0 + startShift;
    end

    % --- map world voxels to local coords ---
    dX = X - O(1); dY = Y - O(2); dZ = Z - O(3);

    Xu = xu_hat(1)*dX + xu_hat(2)*dY + xu_hat(3)*dZ;
    Yu = yu_hat(1)*dX + yu_hat(2)*dY + yu_hat(3)*dZ;
    Zu = zu_hat(1)*dX + zu_hat(2)*dY + zu_hat(3)*dZ;

    % --- base strap ---
    mask = corrStrapLocalMask(Xu,Yu,Zu, paramsLocal);

    % ===================== NEW: rectilinear gauze loop =====================
    loop = getOr(frameOpts,'loop',struct());
    if ~isempty(loop) && getOr(loop,'enable',false)
        loop.zBedLocal = zBed;
        loop.thickMM   = getOr(loop,'thickMM',T);    % default match strap thickness
        mask = mask | rectLoopLocalMask(Xu,Yu,Zu, loop);
    end
end

function v = getOr(s,f,def)
    if isstruct(s) && isfield(s,f) && ~isempty(s.(f)), v = s.(f); else, v = def; end
end

function mask = rectLoopLocalMask(Xu,Yu,Zu, p)
% rectLoopLocalMask
%   A rectangular "frame" (outer box minus inner box) in the strap-local frame.
%
% p fields (all mm unless noted):
%   .enable       true/false
%   .xCenterMM    (default 0)   loop center along Xu
%   .yCenterMM    (default 0)   loop center across width
%   .zCenterMM    (default zBedLocal + thickMM/2)
%   .outerXMM     (default 10)  outer size along Xu
%   .outerYMM     (default 14)  outer size along Yu
%   .thickMM      (default 2.4) thickness along Zu (matches strap)
%   .frameMM      (default 3.0) frame wall thickness in the Xu/Yu plane
%   .zBedLocal    (default 0)   hard floor

    zBed = getOr(p,'zBedLocal',0);
    T    = getOr(p,'thickMM',2.4);

    xC   = getOr(p,'xCenterMM',0);
    yC   = getOr(p,'yCenterMM',0);
    zC   = getOr(p,'zCenterMM', zBed + T/2);

    ox   = getOr(p,'outerXMM',10);
    oy   = getOr(p,'outerYMM',14);
    fw   = getOr(p,'frameMM',3.0);

    % Outer box
    inOuter = abs(Xu - xC) <= ox/2 & abs(Yu - yC) <= oy/2 & abs(Zu - zC) <= T/2;

    % Inner void (subtract)
    ix = max(0, ox - 2*fw);
    iy = max(0, oy - 2*fw);
    inInner = abs(Xu - xC) <= ix/2 & abs(Yu - yC) <= iy/2 & abs(Zu - zC) <= (T/2 + 1e-6);

    mask = inOuter & ~inInner;

    % No material below bed
    mask = mask & (Zu >= zBed);
end
