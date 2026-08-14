function [cropAxis, cropDistance, accepted] = selectCropPlane(A, vox2world, cropAxis, cropDistance, opts)
% SELECTCROPPLANE  Interactively choose a capMaker crop axis and plane.
%
% [cropAxis, cropDistance] = selectCropPlane(A, vox2world, cropAxis, cropDistance)
% displays an isosurface for the logical head mask A. The returned plane is
% expressed in world coordinates:
%
%   dot(point, cropAxis) = cropDistance
%
% Controls:
%   drag                         rotate the 3-D camera
%   Shift-drag                   roll the camera around the view axis
%   scroll wheel                 move the crop plane along the crop axis
%   Ctrl-click or Command-click  point the crop axis toward the click
%   Alt-click or Option-click    move the plane through the picked surface point
%   arrow keys                   nudge the crop-axis direction in screen space
%   x, y, z                      look along the selected world axis
%
% opts.displayMaxFaces limits the rendered surface complexity [12000].
% The full-resolution surface is retained for plane calculations and picking.
%
% The arrow is anchored at the head centroid for display. cropAxis remains a
% direction vector, so the returned values do not depend on that display anchor.

    if nargin < 2 || isempty(vox2world), vox2world = eye(4); end
    if nargin < 3 || isempty(cropAxis), cropAxis = [0 0 1]; end
    if nargin < 5, opts = struct(); end

    validateattributes(A, {'logical', 'numeric'}, {'real', 'nonsparse'});
    validateattributes(vox2world, {'numeric'}, {'size', [4 4], 'real', 'finite'});
    validateattributes(cropAxis, {'numeric'}, {'vector', 'numel', 3, 'real', 'finite'});
    if ndims(A) ~= 3
        error('selectCropPlane expects a 3-D head mask.');
    end
    if ~any(A(:))
        error('selectCropPlane cannot display an empty head mask.');
    end

    cropAxis = double(cropAxis(:));
    if norm(cropAxis) < eps
        error('cropAxis must have nonzero length.');
    end
    cropAxis = cropAxis / norm(cropAxis);

    [Xw, Yw, Zw] = worldGridForMask(A, vox2world);
    smoothSigma = getOpt(opts, 'smoothSigma', 0.7);
    S = isosurface(Xw, Yw, Zw, imgaussfilt3(single(A), smoothSigma), 0.5);
    if isempty(S.vertices)
        error('selectCropPlane could not extract a head isosurface.');
    end

    vertices = double(S.vertices);
    displayMaxFaces = getOpt(opts, 'displayMaxFaces', 12000);
    Sdisplay = decimateSurfaceForDisplay(S, displayMaxFaces);
    anchor = mean(vertices, 1);
    bbMin = min(vertices, [], 1);
    bbMax = max(vertices, [], 1);
    diagMM = norm(bbMax - bbMin);
    arrowLength = getOpt(opts, 'arrowLengthMM', 0.8 * diagMM);
    planeHalfWidth = getOpt(opts, 'planeHalfWidthMM', 0.6 * diagMM);
    scrollStepMM = getOpt(opts, 'scrollStepMM', 1);
    axisNudgeStep = getOpt(opts, 'axisNudgeStep', 0.025);
    cameraRollDegPerPixel = getOpt(opts, 'cameraRollDegPerPixel', 0.45);
    meshAlpha = getOpt(opts, 'meshAlpha', 1.0);
    figName = getOpt(opts, 'title', 'Select cap crop plane');

    if nargin < 4 || isempty(cropDistance)
        cropDistance = quantile(vertices * cropAxis, 0.55);
    end
    validateattributes(cropDistance, {'numeric'}, {'scalar', 'real', 'finite'});
    cropDistance = double(cropDistance);
    accepted = false;
    dragStart = [];
    dragMode = '';

    fig = figure( ...
        'Name', figName, ...
        'NumberTitle', 'off', ...
        'Color', 'w', ...
        'Renderer', 'opengl', ...
        'CloseRequestFcn', @onCancel);
    ax = axes('Parent', fig, 'Position', [0.03 0.12 0.74 0.84]);
    hold(ax, 'on');
    headPatch = patch(ax, Sdisplay);
    set(headPatch, ...
        'FaceColor', [0.85 0.9 0.95], ...
        'EdgeColor', 'none', ...
        'FaceAlpha', meshAlpha, ...
        'BackFaceLighting', 'reverselit');
    axis(ax, 'vis3d');
    axis(ax, 'equal');
    axis(ax, 'off');
    camproj(ax, 'orthographic');
    cameraLight = camlight(ax, 'headlight');
    lighting(ax, 'gouraud');
    view(ax, 3);
    camtarget(ax, anchor);

    axisArrow = quiver3(ax, anchor(1), anchor(2), anchor(3), 0, 0, 0, 0, ...
        'LineWidth', 2.5, 'Color', [0 0.25 0.9], 'MaxHeadSize', 0.6);
    axisLine = plot3(ax, nan, nan, nan, ...
        'LineWidth', 2.0, 'Color', [0 0.25 0.9], 'LineStyle', '-');
    planePatch = patch(ax, ...
        'Vertices', zeros(4, 3), ...
        'Faces', [1 2 3 4], ...
        'FaceColor', [0.95 0.15 0.1], ...
        'FaceAlpha', 0.16, ...
        'EdgeColor', [0.7 0 0], ...
        'LineWidth', 1.5);
    axisLabel = text(ax, anchor(1), anchor(2), anchor(3), ' crop axis', ...
        'Color', [0 0.25 0.9], 'FontWeight', 'bold');
    drawCropContext(ax, opts);

    status = uicontrol(fig, ...
        'Style', 'text', ...
        'Units', 'normalized', ...
        'Position', [0.79 0.48 0.19 0.38], ...
        'BackgroundColor', 'w', ...
        'HorizontalAlignment', 'left', ...
        'FontSize', 10);
    uicontrol(fig, ...
        'Style', 'pushbutton', ...
        'String', 'Done', ...
        'Units', 'normalized', ...
        'Position', [0.80 0.18 0.17 0.09], ...
        'Callback', @onDone);
    uicontrol(fig, ...
        'Style', 'pushbutton', ...
        'String', 'Cancel', ...
        'Units', 'normalized', ...
        'Position', [0.80 0.07 0.17 0.07], ...
        'Callback', @onCancel);

    updateGraphics();
    set(fig, ...
        'WindowButtonDownFcn', @onMouseDown, ...
        'WindowButtonUpFcn', @onMouseUp, ...
        'WindowScrollWheelFcn', @onScroll, ...
        'WindowKeyPressFcn', @onKeyPress);
    uiwait(fig);

    if isgraphics(fig)
        delete(fig);
    end

    function onMouseDown(~, ~)
        clickedAxes = ancestor(hittest(fig), 'axes');
        if isempty(clickedAxes) || clickedAxes ~= ax
            return;
        end
        modifiers = get(fig, 'CurrentModifier');
        if hasAnyModifier(modifiers, {'control', 'command'})
            [rayOrigin, rayDirection] = clickRay(ax);
            clickPoint = rayPlaneIntersection(rayOrigin, rayDirection, anchor, cameraViewDirection(ax));
            newAxis = clickPoint - anchor;
            if norm(newAxis) > eps
                cropAxis = newAxis(:) / norm(newAxis);
                updateGraphics();
            end
        elseif hasAnyModifier(modifiers, {'alt', 'option'})
            [rayOrigin, rayDirection] = clickRay(ax);
            surfacePoint = closestVertexToRay(vertices, rayOrigin, rayDirection);
            cropDistance = dot(surfacePoint, cropAxis);
            updateGraphics();
        else
            dragStart = get(fig, 'CurrentPoint');
            if hasAnyModifier(modifiers, {'shift'})
                dragMode = 'roll';
            else
                dragMode = 'orbit';
            end
            set(fig, 'WindowButtonMotionFcn', @onDrag);
        end
    end

    function onDrag(~, ~)
        pointer = get(fig, 'CurrentPoint');
        delta = pointer - dragStart;
        dragStart = pointer;
        if strcmp(dragMode, 'roll')
            rollCamera(delta(1) * cameraRollDegPerPixel);
        else
            camorbit(ax, -0.35 * delta(1), -0.35 * delta(2), 'camera');
        end
        camlight(cameraLight, 'headlight');
        drawnow limitrate;
    end

    function onMouseUp(~, ~)
        dragStart = [];
        dragMode = '';
        set(fig, 'WindowButtonMotionFcn', '');
    end

    function onScroll(~, event)
        cropDistance = cropDistance - event.VerticalScrollCount * scrollStepMM;
        updateGraphics();
    end

    function onKeyPress(~, event)
        switch lower(event.Key)
            case 'leftarrow'
                nudgeCropAxis([-1 0]);
            case 'rightarrow'
                nudgeCropAxis([1 0]);
            case 'uparrow'
                nudgeCropAxis([0 1]);
            case 'downarrow'
                nudgeCropAxis([0 -1]);
            case 'x'
                setCanonicalView([1 0 0], [0 0 1]);
            case 'y'
                setCanonicalView([0 1 0], [0 0 1]);
            case 'z'
                setCanonicalView([0 0 1], [0 1 0]);
        end
    end

    function setCanonicalView(axisDirection, upDirection)
        cameraDistance = norm(campos(ax) - camtarget(ax));
        if ~isfinite(cameraDistance) || cameraDistance <= 0
            cameraDistance = 1.5 * diagMM;
        end
        camtarget(ax, anchor);
        campos(ax, anchor + cameraDistance * axisDirection);
        camup(ax, upDirection);
        camlight(cameraLight, 'headlight');
        drawnow limitrate;
    end

    function nudgeCropAxis(screenStep)
        stepScale = axisNudgeStep;
        modifiers = get(fig, 'CurrentModifier');
        if hasAnyModifier(modifiers, {'shift'})
            stepScale = 5 * stepScale;
        end
        oldAxis = cropAxis(:) / norm(cropAxis);
        planeCenter = anchor(:) + (cropDistance - dot(anchor(:), oldAxis)) * oldAxis;
        [rightVec, upVec] = cameraScreenBasis(ax);
        deltaAxis = stepScale * (screenStep(1) * rightVec + screenStep(2) * upVec);
        newAxis = oldAxis + deltaAxis(:);
        if norm(newAxis) <= eps
            return;
        end
        cropAxis = newAxis / norm(newAxis);
        cropDistance = dot(planeCenter, cropAxis);
        updateGraphics();
    end

    function rollCamera(angleDeg)
        viewDir = cameraViewDirection(ax);
        upVec = double(camup(ax));
        if norm(upVec) <= eps
            return;
        end
        upVec = upVec(:) / norm(upVec);
        newUp = rotateVectorAroundAxis(upVec, viewDir(:), deg2radLocal(angleDeg));
        if norm(newUp) > eps
            camup(ax, newUp(:)');
        end
    end

    function onDone(~, ~)
        accepted = true;
        uiresume(fig);
    end

    function onCancel(~, ~)
        accepted = false;
        uiresume(fig);
    end

    function updateGraphics()
        arrow = cropAxis(:)' * arrowLength;
        lineHalf = cropAxis(:)' * (0.65 * arrowLength);
        linePoints = [anchor - lineHalf; anchor + lineHalf];
        set(axisLine, ...
            'XData', linePoints(:, 1), ...
            'YData', linePoints(:, 2), ...
            'ZData', linePoints(:, 3));
        set(axisArrow, ...
            'UData', arrow(1), ...
            'VData', arrow(2), ...
            'WData', arrow(3));
        set(axisLabel, ...
            'Position', anchor + arrow, ...
            'String', ' crop axis');
        set(planePatch, 'Vertices', cropPlaneQuad(anchor, cropAxis, cropDistance, planeHalfWidth));
        set(status, 'String', sprintf([ ...
            'Crop axis\n  [% .4f  % .4f  % .4f]\n\n' ...
            'Plane distance\n  %.2f mm\n\n' ...
            'Scroll: move plane\n' ...
            'Ctrl/Cmd-click: axis\n' ...
            'Alt/Option-click: plane\n' ...
            'Shift-drag: camera roll\n' ...
            'Arrows: nudge axis\n' ...
            'X/Y/Z: canonical view'], ...
            cropAxis(1), cropAxis(2), cropAxis(3), cropDistance));
        drawnow limitrate;
    end
end

function Sdisplay = decimateSurfaceForDisplay(S, maxFaces)
    validateattributes(maxFaces, {'numeric'}, {'scalar', 'real', 'finite', 'positive'});
    maxFaces = round(double(maxFaces));
    if size(S.faces, 1) <= maxFaces
        Sdisplay = S;
        return;
    end

    [faces, vertices] = reducepatch(S.faces, S.vertices, maxFaces);
    Sdisplay = struct('faces', faces, 'vertices', vertices);
end

function quad = cropPlaneQuad(anchor, cropAxis, cropDistance, halfWidth)
    dir = cropAxis(:) / norm(cropAxis);
    planeCenter = anchor(:) + (cropDistance - dot(anchor, dir)) * dir;
    aux = [1; 0; 0];
    if abs(dot(aux, dir)) > 0.9, aux = [0; 1; 0]; end
    e1 = cross(dir, aux); e1 = e1 / norm(e1);
    e2 = cross(dir, e1); e2 = e2 / norm(e2);
    quad = [planeCenter - halfWidth * e1 - halfWidth * e2, ...
            planeCenter + halfWidth * e1 - halfWidth * e2, ...
            planeCenter + halfWidth * e1 + halfWidth * e2, ...
            planeCenter - halfWidth * e1 + halfWidth * e2]';
end

function drawCropContext(ax, opts)
    points = getOpt(opts, 'contextPointsWorldMm', []);
    labels = getOpt(opts, 'contextPointLabels', {});
    if ~isempty(points)
        points = double(points);
        if size(points, 2) >= 3
            points = points(:, 1:3);
            scatter3(ax, points(:, 1), points(:, 2), points(:, 3), ...
                34, [0.95 0.20 0.05], 'filled', ...
                'MarkerEdgeColor', 'k');
            drawContextLabels(ax, points, labels);
        end
    end

    curves = getOpt(opts, 'contextCurvesWorldMm', {});
    curveLabels = getOpt(opts, 'contextCurveLabels', {});
    if ~iscell(curves) && ~isempty(curves)
        curves = {curves};
    end
    colors = [ ...
        0.85 0.00 0.05
        0.55 0.00 0.75
        0.00 0.45 0.85
        0.05 0.60 0.20];
    for i = 1:numel(curves)
        C = double(curves{i});
        if isempty(C) || size(C, 2) < 3
            continue;
        end
        C = C(:, 1:3);
        color = colors(1 + mod(i - 1, size(colors, 1)), :);
        plot3(ax, C(:, 1), C(:, 2), C(:, 3), ...
            'Color', color, 'LineWidth', 2.2);
        label = contextLabel(curveLabels, i);
        if ~isempty(label)
            center = mean(C(isfinite(sum(C, 2)), :), 1);
            if all(isfinite(center))
                text(ax, center(1), center(2), center(3), ...
                    [' ' label], 'Color', color, ...
                    'FontWeight', 'bold', 'Interpreter', 'none');
            end
        end
    end
end

function drawContextLabels(ax, points, labels)
    if isempty(labels)
        return;
    end
    if ischar(labels) || isstring(labels)
        labels = cellstr(string(labels(:)));
    end
    n = min(size(points, 1), numel(labels));
    labels = labels(1:n);
    labelStrings = cell(n, 1);
    keep = false(n, 1);
    for i = 1:n
        labelStrings{i} = char(labels{i});
        keep(i) = ~isempty(labelStrings{i}) && all(isfinite(points(i, 1:3)));
    end
    if ~any(keep)
        return;
    end
    uniqueLabels = unique(labelStrings(keep), 'stable');
    for i = 1:numel(uniqueLabels)
        label = uniqueLabels{i};
        if isempty(label)
            continue;
        end
        rows = keep & strcmp(labelStrings, label);
        center = mean(points(rows, 1:3), 1);
        text(ax, center(1), center(2), center(3), ...
            [' ' label], 'Color', [0.70 0.00 0.00], ...
            'FontWeight', 'bold', 'Interpreter', 'none');
    end
end

function [rightVec, upVec] = cameraScreenBasis(ax)
    viewDir = cameraViewDirection(ax);
    upVec = double(camup(ax));
    if norm(upVec) <= eps
        upVec = [0 0 1];
    end
    upVec = upVec(:) / norm(upVec);
    rightVec = cross(viewDir(:), upVec(:));
    if norm(rightVec) <= eps
        rightVec = [1; 0; 0];
    else
        rightVec = rightVec / norm(rightVec);
    end
    upVec = cross(rightVec(:), viewDir(:));
    upVec = upVec / max(norm(upVec), eps);
end

function out = rotateVectorAroundAxis(v, axisDir, theta)
    axisDir = axisDir(:) / max(norm(axisDir), eps);
    v = v(:);
    out = v * cos(theta) + cross(axisDir, v) * sin(theta) + ...
        axisDir * dot(axisDir, v) * (1 - cos(theta));
end

function value = deg2radLocal(value)
    value = value * pi / 180;
end

function label = contextLabel(labels, i)
    label = '';
    if isempty(labels)
        return;
    end
    if ischar(labels) || isstring(labels)
        labels = cellstr(string(labels(:)));
    end
    if i <= numel(labels)
        label = char(labels{i});
    end
end

function [origin, direction] = clickRay(ax)
    points = get(ax, 'CurrentPoint');
    origin = double(points(1, :));
    direction = double(points(2, :) - points(1, :));
    direction = direction / max(norm(direction), eps);
end

function direction = cameraViewDirection(ax)
    direction = double(camtarget(ax) - campos(ax));
    direction = direction / max(norm(direction), eps);
end

function point = rayPlaneIntersection(origin, direction, planePoint, planeNormal)
    denom = dot(direction, planeNormal);
    if abs(denom) < 1e-10
        point = origin;
    else
        point = origin + dot(planePoint - origin, planeNormal) / denom * direction;
    end
end

function point = closestVertexToRay(vertices, origin, direction)
    offsets = vertices - origin;
    rayT = offsets * direction(:);
    rayT(rayT < 0) = 0;
    closestOnRay = origin + rayT .* direction;
    [~, idx] = min(sum((vertices - closestOnRay) .^ 2, 2));
    point = vertices(idx, :);
end

function tf = hasAnyModifier(activeModifiers, choices)
    tf = any(ismember(activeModifiers, choices));
end

function [Xw, Yw, Zw] = worldGridForMask(A, vox2world)
    [X, Y, Z] = ndgrid(0:size(A, 1)-1, 0:size(A, 2)-1, 0:size(A, 3)-1);
    points = [X(:) Y(:) Z(:)] * vox2world(1:3, 1:3)' + vox2world(1:3, 4)';
    Xw = reshape(points(:, 1), size(A));
    Yw = reshape(points(:, 2), size(A));
    Zw = reshape(points(:, 3), size(A));
end

function val = getOpt(opts, field, default)
    if isstruct(opts) && isfield(opts, field) && ~isempty(opts.(field))
        val = opts.(field);
    else
        val = default;
    end
end
