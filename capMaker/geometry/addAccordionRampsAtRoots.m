function [TRrampL, TRrampR] = addAccordionRampsAtRoots(TRstrap, Pleft, Pright, strapOpts, rampOpts)
% Build short accordion ramps at the strap roots (toward the head).
zBed   = getOpt(strapOpts,'zBed',0);
ahead  = getOpt(strapOpts,'strapAheadMM',25);
W      = getOpt(strapOpts,'strapWidthMM',20);
T      = getOpt(strapOpts,'strapThickMM',2.4);

% Strap roots (in world coords): same XY used by the strap generator
rootL = [Pleft(1),  Pleft(2)+ahead,  zBed];
rootR = [Pright(1), Pright(2)+ahead, zBed];

TRrampL = accordionRampFromRoot(rootL, -1, W, T, rampOpts);
TRrampR = accordionRampFromRoot(rootR, +1, W, T, rampOpts);

    function TR = accordionRampFromRoot(root, sideSign, strapW, strapT, r)
        % Short pre-bent ramp made from "ribs" that rise at a steep angle.
        % sideSign: -1 (left strap extends -X; ramp points +X toward head), +1 mirror.
        rampLen   = getOpt(r,'rampLenMM',20);
        rampAng   = deg2rad(getOpt(r,'rampAngleDeg',80));
        ribThick  = getOpt(r,'ribThickMM',1.4);
        gap       = getOpt(r,'ribGapMM',0.7);
        edgeClr   = getOpt(r,'edgeClearMM',1.0);

        % Ramp heads toward the scalp: opposite of strap's outward axis
        dir = -sideSign;    % +X toward head for left strap; -X toward head for right

        period = ribThick + gap;
        nRibs  = max(1, floor(rampLen/period));
        y1 = root(2) - (strapW/2) + edgeClr;
        y2 = root(2) + (strapW/2) - edgeClr;

        TR = [];
        for k = 0:nRibs-1
            s0 = k*period; s1 = s0 + ribThick;

            p0 = [root(1) + dir*s0*cos(rampAng), root(2), root(3) + s0*sin(rampAng)];
            p1 = [root(1) + dir*s1*cos(rampAng), root(2), root(3) + s1*sin(rampAng)];

            u = p1 - p0; Lu = norm(u); if Lu==0, continue; end; u = u/Lu;
            w = [0 0 1]; v = cross(w,u); nv = norm(v); if nv<1e-9, w=[1 0 0]; v=cross(w,u); nv=norm(v); end; v=v/nv; w=cross(u,v); w=w/norm(w);

            halfW = (y2 - y1)/2;
            % midline is root(2); span across width with thickness strapT
            a0 = p0 + (-halfW)*v - 0.5*strapT*w;
            b0 = p0 + ( halfW)*v - 0.5*strapT*w;
            a1 = p1 + (-halfW)*v + 0.5*strapT*w;
            b1 = p1 + ( halfW)*v + 0.5*strapT*w;

            Vrib = [a0; b0; b1; a1; ...
                a0 + strapT*w; b0 + strapT*w; b1 - strapT*w; a1 - strapT*w]; % 8 verts
            Frib = convhulln(Vrib);
            TRrib = triangulation(Frib, Vrib);
            TR = catTri(TR, TRrib);
        end
    end

end