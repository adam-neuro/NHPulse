function h = trimeshNormals(TRorF, VorEmpty, varargin)
% TRIMESHNORMALS  Plot a triangulated surface with face-normal arrows.
% Usage:
%   trimeshNormals(TR)                      % TR is a triangulation
%   trimeshNormals(F, V)                    % F: Nx3, V: Mx3
%   trimeshNormals(..., 'Every', 1)         % plot every face (default)
%   trimeshNormals(..., 'Every', 5)         % plot every 5th face
%   trimeshNormals(..., 'Scale', 5e-1)      % arrow length scale (units of V)
%   trimeshNormals(..., 'ArrowColor', [1 0 0])
%   trimeshNormals(..., 'FaceAlpha', 0.6, 'EdgeAlpha', 0.2)
%
% Returns:
%   h : struct with handles: h.mesh (trisurf), h.quiv (quiver3)

    % ---- Parse inputs ----
    if isa(TRorF, 'triangulation')
        TR = TRorF;
        V  = TR.Points;
        F  = TR.ConnectivityList;
    else
        F = TRorF;
        V = VorEmpty;
        TR = triangulation(F, V);
    end

    p = inputParser;
    p.addParameter('Every',        1,    @(x)isnumeric(x)&&isscalar(x)&&x>=1);
    p.addParameter('Scale',        [],   @(x)isnumeric(x)&&isscalar(x));
    p.addParameter('ArrowColor',   [0 0 1], @(x)isnumeric(x)&&numel(x)==3);
    p.addParameter('FaceColor',    [0.8 0.8 0.85], @(x)isnumeric(x)&&(numel(x)==3||ischar(x)));
    p.addParameter('FaceAlpha',    0.8,  @(x)isnumeric(x)&&isscalar(x));
    p.addParameter('EdgeColor',    [0.2 0.2 0.2], @(x)isnumeric(x)&&(numel(x)==3||ischar(x)));
    p.addParameter('EdgeAlpha',    0.3,  @(x)isnumeric(x)&&isscalar(x));
    p.addParameter('LineWidth',    0.5,  @(x)isnumeric(x)&&isscalar(x));
    p.addParameter('Parent',       [],   @(x)isempty(x)||ishandle(x));
    p.parse(varargin{:});
    opt = p.Results;

    ax = opt.Parent;
    if isempty(ax), ax = gca; end
    hold(ax, 'on');

    % ---- Plot mesh ----
    h.mesh = trisurf(TR, ...
        'Parent', ax, ...
        'FaceColor', opt.FaceColor, ...
        'FaceAlpha', opt.FaceAlpha, ...
        'EdgeColor', opt.EdgeColor, ...
        'EdgeAlpha', opt.EdgeAlpha, ...
        'LineWidth', opt.LineWidth);

    % ---- Compute face centroids and normals (right-hand rule) ----
    f1 = F(:,1); f2 = F(:,2); f3 = F(:,3);
    v1 = V(f1,:); v2 = V(f2,:); v3 = V(f3,:);
    e1 = v2 - v1;
    e2 = v3 - v1;
    N  = cross(e1, e2, 2);                      % unnormalized face normals
    L  = sqrt(sum(N.^2,2)) + eps;
    n  = N ./ L;                                % unit normals
    C  = (v1 + v2 + v3) / 3;                    % face centroids

    % ---- Subsample faces if requested ----
    every = max(1, round(opt.Every));
    idx = 1:every:size(F,1);

    % ---- Choose a default arrow scale if none provided ----
    if isempty(opt.Scale)
        % Heuristic: ~1% of the mesh bounding-box diagonal
        bbmin = min(V,[],1); bbmax = max(V,[],1);
        diagLen = norm(bbmax - bbmin);
        s = 0.01 * diagLen;
    else
        s = opt.Scale;
    end

    % ---- Quiver (face normals) ----
    h.quiv = quiver3(ax, ...
        C(idx,1), C(idx,2), C(idx,3), ...
        n(idx,1), n(idx,2), n(idx,3), ...
        s, 'Color', opt.ArrowColor, 'LineWidth', 1);

    % ---- Niceties ----
    axis(ax, 'equal'); grid(ax, 'on'); box(ax, 'on');
    xlabel(ax,'X'); ylabel(ax,'Y'); zlabel(ax,'Z');
    view(ax, 3);
    hold(ax, 'off');
end
