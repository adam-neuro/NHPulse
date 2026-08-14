function tri = makeHexPrismWithHole(heightToSide, outerToInner)
% makeHexPrismWithHole  Regular hexagonal prism with concentric hex hole.
%
% [V,F] = makeHexPrismWithHole(heightToSide, outerToInner)
%   heightToSide : ratio H/s_out (H = prism height, s_out = outer side length)
%   outerToInner : ratio s_out / s_in  (s_in = inner side length)
%
% Output:
%   V : (4*6) x 3 vertex array, normalized to [0,1]^3, base at z=0
%   F : (#faces) x 3 triangle indices, watertight, outward normals
%
% Notes:
% - Internally builds a canonical shape centered at (0,0) in XY:
%     outer side length s_out = 1 (so outer circumradius R_out = 1)
%     height H = heightToSide * s_out
%     inner side length s_in = s_out / outerToInner
%   Then maps XY from [-R_out, +R_out] to [0,1] and Z from [0,H] to [0,1].
%
% - Orientation: "flat-top" hex (one edge parallel to X), rotation = 0 deg.

    arguments
        heightToSide (1,1) double {mustBePositive}
        outerToInner (1,1) double {mustBeGreaterThan(outerToInner,1)}
    end

    % Canonical dimensions
    s_out = 1.0;                 % outer side length
    R_out = s_out;               % for a regular hex, circumradius = s_out
    H     = heightToSide * s_out;

    s_in  = s_out / outerToInner;
    R_in  = s_in;                % same relation

    n = 6;                       % hexagon
    rotDeg = 0;                  % flat-top orientation
    th0 = deg2rad(rotDeg);
    th  = th0 + (0:n-1)'*(2*pi/n);

    % Outer & inner polygon vertices at bottom (z=0) and top (z=H)
    xo = R_out*cos(th);  yo = R_out*sin(th);
    xi = R_in *cos(th);  yi = R_in *sin(th);

    % Vertex blocks (order: TopOuter A, TopInner B, BotOuter C, BotInner D)
    A = [xo, yo, H*ones(n,1)];   % top outer
    B = [xi, yi, H*ones(n,1)];   % top inner
    C = [xo, yo, zeros(n,1)];    % bottom outer
    D = [xi, yi, zeros(n,1)];    % bottom inner (hole)

    Vc = [A; B; C; D];           % canonical (centered at (0,0), z in [0,H])

    % Face indexing helpers
    iA = @(i) i;                 % 1..n
    iB = @(i) n + i;             % n+1..2n
    iC = @(i) 2*n + i;           % 2n+1..3n
    iD = @(i) 3*n + i;           % 3n+1..4n
    nxt = @(i) mod(i,n)+1;

    % Faces: top annulus, bottom annulus, outer wall, inner wall
    F = zeros( (2+2+2+2)*n, 3);
    t = 0;

    % Top annulus (outer→inner), CCW when viewed from +Z
    for i=1:n
        ip = nxt(i);
        F(t+1,:) = [iA(i)  iA(ip) iB(ip)]; t=t+1;
        F(t+1,:) = [iA(i)  iB(ip) iB(i) ]; t=t+1;
    end

    % Bottom annulus (flip winding so outward normal points down)
    for i=1:n
        ip = nxt(i);
        % quad: C_i, C_ip, D_ip, D_i  → triangles with flipped order
        F(t+1,:) = [iC(ip) iC(i)  iD(ip)]; t=t+1;
        F(t+1,:) = [iC(i)  iD(i)  iD(ip)]; t=t+1;
    end

    % Outer wall: connect bottom outer C to top outer A
    for i=1:n
        ip = nxt(i);
        % quad: C_i, C_ip, A_ip, A_i
        F(t+1,:) = [iC(i)  iC(ip) iA(i) ]; t=t+1;
        F(t+1,:) = [iC(ip) iA(ip) iA(i) ]; t=t+1;
    end

    % Inner wall: connect bottom inner D to top inner B (hole → reverse)
    for i=1:n
        ip = nxt(i);
        % quad: D_i, D_ip, B_ip, B_i  (reverse winding)
        F(t+1,:) = [iD(ip) iD(i)  iB(i) ]; t=t+1;
        F(t+1,:) = [iD(ip) iB(i)  iB(ip)]; t=t+1;
    end

    % Normalize coordinates to [0,1]^3:
    %   X,Y: map from [-R_out, +R_out] → [0,1]
    %   Z  : map from [0, H] → [0,1]
    V = Vc;
    V(:,1) = ((Vc(:,1) + R_out) / (2*R_out))-0.5;
    V(:,2) = ((Vc(:,2) + R_out) / (2*R_out))-0.5;
    % V(:,3) =  Vc(:,3) / H;

    % Sanity check
    if any(F(:) < 1) || any(F(:) > size(V,1))
        error('Face indices out of range.');
    end
    % V in [0,1], base lies on z=0 plane.

    tri = triangulation(F,V);
end
