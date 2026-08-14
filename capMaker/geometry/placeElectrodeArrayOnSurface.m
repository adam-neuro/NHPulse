function [TRout, holeTops, holeBottoms, holderInfo] = placeElectrodeArrayOnSurface(skullTR, holderTR, targets, embed, varargin)
% placeElectrodeArrayOnSurface
%   Build a single triangulation containing copies of 'holderTR' placed on
%   a skull surface 'skullTR' at the nearest vertices to each target point.
%   Also returns world-space coordinates of hole top/bottom centers for each placed holder.
%
% INPUT
%   skullTR : triangulation  (skull/spherical-cap surface)
%   holderTR: triangulation  (reference electrode holder; already scaled.
%                             Axis +Z through the hole; base at z=0; XY centered at 0)
%   targets : N x 3 double   (target 3D positions near the skull surface)
%   embed   : scalar double  (mm to push the base into skull along -normal; default 0.3)
%
%   Name-Value (all optional):
%     'HoleZ'       : [zBottom zTop] in holder frame (mm). Default: [0, max(holderTR.Points(:,3))]
%     'HoleTopZ'    : scalar, overrides zTop
%     'HoleBottomZ' : scalar, overrides zBottom
%     'NormalMode'  : 'vertex', 'smooth', or 'autoSmooth' ['vertex']
%     'SmoothNormalRadiusMm' : radius for local normal interpolation [6]
%     'NormalDeviationThresholdDeg' : autoSmooth threshold [25]
%
% OUTPUT
%   TRout       : triangulation  (all placed holders combined)
%   holeTops    : N x 3 double   (world coords of each hole's top-center)
%   holeBottoms : N x 3 double   (world coords of each hole's bottom-center)
%   holderInfo  : N x 1 struct   (surface vertex, normal, bounds, hole axis)
%
% Dependencies: closestVertex

    arguments
        skullTR triangulation
        holderTR triangulation
        targets (:,3) double {mustBeFinite, mustBeReal}
        embed (1,1) double {mustBeNonnegative} = 0.3
    end
    arguments (Repeating)
        varargin
    end

    % --- Parse optional hole Z parameters in holder frame ---
    Vref = holderTR.Points;
    defaultZBottom = 0.0;                 % by convention: base at z = 0
    defaultZTop    = max(Vref(:,3));      % conservative default if not specified

    zBottom = defaultZBottom;
    zTop    = defaultZTop;

    normalMode = 'vertex';
    smoothNormalRadiusMm = 6;
    normalDeviationThresholdDeg = 25;

    % Accept flexible specification:
    % placeElectrodeArrayOnSurface(..., 'HoleZ', [zB zT], 'HoleTopZ', zT2, 'HoleBottomZ', zB2)
    if ~isempty(varargin)
        for k = 1:2:numel(varargin)
            key = varargin{k};
            val = varargin{k+1};
            switch lower(key)
                case 'holez'
                    validateattributes(val, {'numeric'}, {'vector','numel',2,'real','finite'});
                    zBottom = val(1);
                    zTop    = val(2);
                case 'holetopz'
                    validateattributes(val, {'numeric'}, {'scalar','real','finite'});
                    zTop = val;
                case 'holebottomz'
                    validateattributes(val, {'numeric'}, {'scalar','real','finite'});
                    zBottom = val;
                case 'normalmode'
                    normalMode = normalizeNormalMode(val);
                case 'smoothnormalradiusmm'
                    validateattributes(val, {'numeric'}, ...
                        {'scalar','real','finite','positive'});
                    smoothNormalRadiusMm = double(val);
                case 'normaldeviationthresholddeg'
                    validateattributes(val, {'numeric'}, ...
                        {'scalar','real','finite','nonnegative'});
                    normalDeviationThresholdDeg = double(val);
                otherwise
                    error('Unknown parameter: %s', key);
            end
        end
    end

    % Preallocate outputs
    N = size(targets,1);
    holeTops     = zeros(N,3);
    holeBottoms  = zeros(N,3);
    holderInfo = repmat(struct( ...
        'surfaceVertex', NaN, ...
        'targetMm', [NaN NaN NaN], ...
        'surfacePointMm', [NaN NaN NaN], ...
        'surfaceNormal', [NaN NaN NaN], ...
        'rawSurfaceNormal', [NaN NaN NaN], ...
        'smoothSurfaceNormal', [NaN NaN NaN], ...
        'rawToSmoothNormalAngleDeg', NaN, ...
        'normalMode', normalMode, ...
        'normalModeUsed', normalMode, ...
        'holderCenterMm', [NaN NaN NaN], ...
        'holeTopMm', [NaN NaN NaN], ...
        'holeBottomMm', [NaN NaN NaN], ...
        'holeAxis', [NaN NaN NaN], ...
        'minZMm', NaN, ...
        'maxZMm', NaN), N, 1);

    Vall = zeros(0,3);
    Fall = zeros(0,3);
    Fref = holderTR.ConnectivityList;

    % Canonical hole-center points in holder frame
    holeTop_holder    = [0, 0, zTop];
    holeBottom_holder = [0, 0, zBottom];

    rawVertexNormals = normalizeRows(vertexNormalSafe(skullTR));
    smoothVertexNormals = rawVertexNormals;
    if ~strcmp(normalMode, 'vertex')
        smoothVertexNormals = smoothNormalsByRadius( ...
            skullTR, rawVertexNormals, smoothNormalRadiusMm);
    end

    for i = 1:N
        % 1) Snap to nearest skull vertex
        vidx = closestVertex(skullTR, targets(i,:));

        % 2) Local pose at that vertex
        rawNormal = rawVertexNormals(vidx, :);
        smoothNormal = smoothVertexNormals(vidx, :);
        [surfaceNormal, normalModeUsed, rawToSmoothDeg] = selectPlacementNormal( ...
            rawNormal, smoothNormal, normalMode, normalDeviationThresholdDeg);
        pose = poseFromPointNormal(skullTR.Points(vidx, :), surfaceNormal);

        % 3) Apply pose to the reference holder (no extra scaling)
        Vplaced = pose.apply(Vref, 1.0, 1.0, embed);

        % 3b) Transform hole centerline endpoints
        holeTop_world    = pose.apply(holeTop_holder,    1.0, 1.0, embed);
        holeBottom_world = pose.apply(holeBottom_holder, 1.0, 1.0, embed);

        holeTops(i,:)    = holeTop_world;
        holeBottoms(i,:) = holeBottom_world;
        holeAxis = holeTop_world - holeBottom_world;
        axisNorm = norm(holeAxis);
        if axisNorm > eps
            holeAxis = holeAxis ./ axisNorm;
        end

        holderInfo(i).surfaceVertex = vidx;
        holderInfo(i).targetMm = targets(i,:);
        holderInfo(i).surfacePointMm = pose.p;
        holderInfo(i).surfaceNormal = pose.zhat;
        holderInfo(i).rawSurfaceNormal = rawNormal;
        holderInfo(i).smoothSurfaceNormal = smoothNormal;
        holderInfo(i).rawToSmoothNormalAngleDeg = rawToSmoothDeg;
        holderInfo(i).normalMode = normalMode;
        holderInfo(i).normalModeUsed = normalModeUsed;
        holderInfo(i).holderCenterMm = mean(Vplaced, 1);
        holderInfo(i).holeTopMm = holeTop_world;
        holderInfo(i).holeBottomMm = holeBottom_world;
        holderInfo(i).holeAxis = holeAxis;
        holderInfo(i).minZMm = min(Vplaced(:, 3));
        holderInfo(i).maxZMm = max(Vplaced(:, 3));

        % 4) Append with face index offset
        off = size(Vall,1);
        Vall = [Vall; Vplaced]; %#ok<AGROW>
        Fall = [Fall; Fref + off]; %#ok<AGROW>
    end

    TRout = triangulation(Fall, Vall);
end

function mode = normalizeNormalMode(value)
    mode = lower(strtrim(char(value)));
    switch regexprep(mode, '[\s_\-]+', '')
        case {'vertex', 'raw', 'legacy'}
            mode = 'vertex';
        case {'smooth', 'smoothed', 'interpolated'}
            mode = 'smooth';
        case {'autosmooth', 'auto', 'repair'}
            mode = 'autoSmooth';
        otherwise
            error(['NormalMode must be ''vertex'', ''smooth'', ', ...
                'or ''autoSmooth''.']);
    end
end

function N = vertexNormalSafe(TR)
    try
        N = vertexNormal(TR);
    catch
        V = double(TR.Points);
        F = double(TR.ConnectivityList);
        faceNormal = cross(V(F(:, 2), :) - V(F(:, 1), :), ...
            V(F(:, 3), :) - V(F(:, 1), :), 2);
        N = zeros(size(V));
        for f = 1:size(F, 1)
            N(F(f, :), :) = N(F(f, :), :) + faceNormal(f, :);
        end
    end
end

function N = smoothNormalsByRadius(TR, rawNormals, radiusMm)
    V = double(TR.Points);
    rawNormals = orientNormalsRadially(V, normalizeRows(rawNormals));
    N = rawNormals;
    r2 = radiusMm ^ 2;
    for i = 1:size(V, 1)
        d2 = sum((V - V(i, :)) .^ 2, 2);
        use = d2 <= r2;
        if nnz(use) < 6
            [~, order] = sort(d2, 'ascend');
            use(order(1:min(12, numel(order)))) = true;
        end
        n = mean(rawNormals(use, :), 1);
        if dot(n, rawNormals(i, :)) < 0
            n = -n;
        end
        if norm(n) > eps
            N(i, :) = n ./ norm(n);
        end
    end
    N = normalizeRows(N);
end

function N = orientNormalsRadially(V, N)
    center = median(V, 1);
    radial = V - center;
    radial = normalizeRows(radial);
    flip = all(isfinite(radial), 2) & all(isfinite(N), 2) & ...
        sum(N .* radial, 2) < 0;
    N(flip, :) = -N(flip, :);
end

function [normalOut, modeUsed, rawToSmoothDeg] = selectPlacementNormal( ...
        rawNormal, smoothNormal, mode, thresholdDeg)
    rawNormal = unitVector(rawNormal);
    smoothNormal = unitVector(smoothNormal);
    rawToSmoothDeg = vectorAngleDeg(rawNormal, smoothNormal);
    normalOut = rawNormal;
    modeUsed = 'vertex';
    switch mode
        case 'vertex'
            normalOut = rawNormal;
            modeUsed = 'vertex';
        case 'smooth'
            normalOut = smoothNormal;
            modeUsed = 'smooth';
        case 'autoSmooth'
            if isfinite(rawToSmoothDeg) && rawToSmoothDeg > thresholdDeg
                normalOut = smoothNormal;
                modeUsed = 'smoothRepair';
            else
                normalOut = rawNormal;
                modeUsed = 'vertex';
            end
    end
    if any(~isfinite(normalOut)) || norm(normalOut) <= eps
        normalOut = [0 0 1];
        modeUsed = 'fallbackZ';
    end
end

function pose = poseFromPointNormal(p, zhat)
    zhat = unitVector(zhat);
    ref = [0 0 1];
    if abs(dot(zhat, ref)) > 0.9
        ref = [1 0 0];
    end
    xhat = cross(ref, zhat);
    xhat = xhat ./ norm(xhat);
    yhat = cross(zhat, xhat);
    R = [xhat(:), yhat(:), zhat(:)];

    pose.p = p;
    pose.R = R;
    pose.zhat = zhat;
    pose.xhat = xhat;
    pose.yhat = yhat;
    pose.apply = @(Vunit, sXY, H, embed) applyPlacementLocal( ...
        Vunit, sXY, H, p, R, embed);
end

function Vworld = applyPlacementLocal(Vunit, sXY, H, p, R, embed)
    S = diag([sXY, sXY, H]);
    Vscaled = Vunit * S;
    Hunit = max(Vunit(:, 3)) - min(Vunit(:, 3));
    Hworld = H * Hunit;
    Vrot = Vscaled * R.';
    zhat = R(:, 3).';
    Vworld = bsxfun(@plus, Vrot, p - (embed * Hworld) * zhat);
end

function N = normalizeRows(N)
    len = sqrt(sum(N .^ 2, 2));
    len(~isfinite(len) | len <= eps) = 1;
    N = bsxfun(@rdivide, N, len);
end

function v = unitVector(v)
    v = double(v(:)).';
    if numel(v) ~= 3 || any(~isfinite(v)) || norm(v) <= eps
        v = [NaN NaN NaN];
    else
        v = v ./ norm(v);
    end
end

function angleDeg = vectorAngleDeg(a, b)
    if any(~isfinite(a)) || any(~isfinite(b))
        angleDeg = NaN;
        return;
    end
    c = max(-1, min(1, dot(a, b)));
    angleDeg = acosd(c);
end
