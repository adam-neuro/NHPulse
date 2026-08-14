function pose = placeOnSurface(tri, vertexIndex)
% placeOnSurface  Build a local pose at a skull-surface vertex for placing an object.
%
% pose = placeOnSurface(tri, vertexIndex)
%   tri          : triangulation for the skull surface
%   vertexIndex  : index of the vertex on tri where you want the holder centered
%
% Returns struct 'pose' with fields:
%   p    : 1x3 position (the chosen skull vertex, world coords)
%   R    : 3x3 rotation matrix; columns are [xhat, yhat, zhat]
%   zhat : 1x3 surface normal at that vertex (unit, outward)
%   xhat : 1x3 tangent basis vector (unit)
%   yhat : 1x3 tangent basis vector (unit)
%   apply(Vunit, sXY, H, embed) : function handle to transform unit vertices
%
% EXPECTED ELECTRODE-HOLDER CONVENTION (unit space):
%   - Axis along +Z (hole axis)
%   - Base plane at z=0
%   - Centered at (x,y) = (0,0) in its own coordinates
%   - X/Y extent around 0 (e.g., [-0.5, 0.5] if you normalized that way)

    arguments
        tri triangulation
        vertexIndex (1,1) {mustBeInteger, mustBePositive}
    end

    %--- Position at the chosen skull vertex
    p = tri.Points(vertexIndex, :);

    %--- Vertex normal (unit)
    Nv = vertexNormal(tri);
    zhat = Nv(vertexIndex, :);
    zhat = zhat ./ norm(zhat);

    %--- Build a stable tangent frame (xhat, yhat) orthonormal to zhat
    ref = [0 0 1];
    if abs(dot(zhat, ref)) > 0.9
        ref = [1 0 0]; % avoid near-parallel reference
    end
    xhat = cross(ref, zhat);  xhat = xhat ./ norm(xhat);
    yhat = cross(zhat, xhat); % already unit if xhat,zhat are orthonormal

    R = [xhat(:), yhat(:), zhat(:)]; % columns form a rotation matrix

    %--- Package pose and an application helper
    pose.p    = p;
    pose.R    = R;
    pose.zhat = zhat;
    pose.xhat = xhat;
    pose.yhat = yhat;

    % apply(): transform unit-geometry vertices to world, with scaling + embed.
    % Vunit : Nx3 vertices in UNIT coordinates (axis +Z, base at z=0, centered XY at 0)
    % sXY   : in-plane scale (mm) applied to X and Y of the unit model
    % H     : height scale (mm) applied along +Z of the unit model
    % embed : mm to push INTO the skull along -normal so base is fully inside
    pose.apply = @(Vunit, sXY, H, embed) applyPlacement(Vunit, sXY, H, p, R, embed);

end

% ===== Local helper =====
function Vworld = applyPlacement(Vunit, sXY, H, p, R, embed)
    arguments
        Vunit double {mustBeFinite, mustBeReal, mustBeNonempty}
        sXY   (1,1) double {mustBePositive}
        H     (1,1) double {mustBePositive}
        p     (1,3) double
        R     (3,3) double
        embed (1,1) double {mustBeNonnegative} = 0.3
    end
    % 1) scale in local (holder) coords
    S = diag([sXY, sXY, H]);
    Vscaled = Vunit * S;

    % 2) compute holder height AFTER scaling
    H_unit  = max(Vunit(:,3)) - min(Vunit(:,3));   % height in Vunit coords
    H_world = H * H_unit;                          % height in output units (mm)

    % 3) rotate and translate; push inward along -normal by embed*height
    Vrot = Vscaled * R.';
    zhat = R(:,3).';                               % unit normal
    Vworld = bsxfun(@plus, Vrot, p - (embed * H_world) * zhat);
end
