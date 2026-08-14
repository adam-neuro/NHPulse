function TR = accordionRampAtStrapRoot(TRstrap, sideSign, rampLen, rampAngleDeg, ribThick, gap, strapW, strapT, edgeClr, zBed)
% Builds a pre-bent accordion ramp at the strap root (near the head side).
% The ramp rises off the bed at rampAngleDeg, length rampLen along its centerline.
% Ribs span the strap width (leaving edgeClr on each side).

V = TRstrap.Points;
bb = [min(V,[],1); max(V,[],1)];

% Strap axis in X; root is the side *toward* the head:
xRoot = (sideSign<0) * bb(2,1) + (sideSign>0) * bb(1,1);
y1 = bb(1,2) + edgeClr; y2 = bb(2,2) - edgeClr;

% Ramp direction: toward the head (opposite of the strap's outward axis)
dir = -sideSign;  % if strap extends +X, ramp goes −X from root
theta = deg2rad(rampAngleDeg);

% Number of ribs
period = ribThick + gap;
nRibs = max(1, floor(rampLen/period));

TR = [];
for k = 0:nRibs-1
    s0 = k*period; s1 = s0 + ribThick;  % distance along ramp centerline

    % centerline param → 3D coords of rib's two longitudinal ends (at mid-width)
    % local frame: u along ramp, v across strap width, w thickness normal
    % Start point on bed at (xRoot, yMid, zBed), then rise by theta
    yMid = 0.5*(y1+y2);
    p0 = [xRoot + dir*s0*cos(theta), yMid, zBed + s0*sin(theta)];
    p1 = [xRoot + dir*s1*cos(theta), yMid, zBed + s1*sin(theta)];

    u = p1 - p0; Lu = norm(u); if Lu==0, continue; end; u = u/Lu;
    w = [0 0 1];                    % thickness normal roughly vertical
    v = cross(w,u); nv = norm(v); if nv<1e-9, w=[1 0 0]; v=cross(w,u); nv=norm(v); end; v=v/nv;
    w = cross(u,v); w = w/norm(w);

    halfW = 0.5*(y2 - y1);
    % four long edge rails of the rib (prism corners sweep)
    a0 = p0 + (-halfW)*v - 0.5*strapT*w;
    b0 = p0 + ( halfW)*v - 0.5*strapT*w;
    a1 = p1 + (-halfW)*v + 0.5*strapT*w;
    b1 = p1 + ( halfW)*v + 0.5*strapT*w;

    Vrib = [a0; b0; b1; a1; ...
            a0 + strapT*w; b0 + strapT*w; b1 - strapT*w; a1 - strapT*w]; % 8 corners; mild "twist" prevention
    Frib = convhulln(Vrib);
    TRrib = triangulation(Frib, Vrib);
    TR = catTri(TR, TRrib);
end
end
