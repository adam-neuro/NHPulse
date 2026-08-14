function R = acsPolhemusOrientationMatrix(anglesDeg, convention)
% ACSPOLHEMUSORIENTATIONMATRIX Build candidate FasTrak orientation matrices.
%
% R = acsPolhemusOrientationMatrix(anglesDeg, convention) returns one
% 3-by-3 local-to-tracker rotation matrix per row of anglesDeg. The exact
% FasTrak Euler convention can differ across configurations, so calibration
% routines store the convention that best explains the calibration data.

if nargin < 2 || isempty(convention)
    convention = struct();
end
if ~isfield(convention, 'order') || isempty(convention.order)
    convention.order = 'xyz';
end
if ~isfield(convention, 'signs') || isempty(convention.signs)
    convention.signs = [1 1 1];
end
if ~isfield(convention, 'angleColumns') || isempty(convention.angleColumns)
    convention.angleColumns = [1 2 3];
end
if ~isfield(convention, 'multiplyOrder') || isempty(convention.multiplyOrder)
    convention.multiplyOrder = 'post';
end
if ~isfield(convention, 'transpose') || isempty(convention.transpose)
    convention.transpose = false;
end

anglesDeg = double(anglesDeg);
if size(anglesDeg, 2) < 3
    error('acsPolhemusOrientationMatrix:BadAngles', ...
        'anglesDeg must have at least three columns.');
end

order = lower(char(convention.order));
if numel(order) ~= 3 || any(~ismember(order, 'xyz'))
    error('acsPolhemusOrientationMatrix:BadOrder', ...
        'convention.order must be a three-character sequence using x, y, and z.');
end
if numel(unique(order)) ~= 3
    error('acsPolhemusOrientationMatrix:RepeatedAxis', ...
        'convention.order must use each axis once.');
end

signs = double(convention.signs(:))';
if numel(signs) ~= 3 || any(~ismember(sign(signs), [-1 1]))
    error('acsPolhemusOrientationMatrix:BadSigns', ...
        'convention.signs must contain three nonzero values.');
end
signs = sign(signs);

angleColumns = double(convention.angleColumns(:))';
if numel(angleColumns) ~= 3 || any(angleColumns < 1) || any(angleColumns > size(anglesDeg, 2))
    error('acsPolhemusOrientationMatrix:BadColumns', ...
        'convention.angleColumns must select three columns from anglesDeg.');
end

angles = anglesDeg(:, angleColumns);
angles = bsxfun(@times, angles, signs);
angles = angles * pi / 180;
n = size(angles, 1);
R = zeros(3, 3, n);

for i = 1:n
    Ri = eye(3);
    for j = 1:3
        A = axisRotation(order(j), angles(i, j));
        switch lower(char(convention.multiplyOrder))
            case 'post'
                Ri = Ri * A;
            case 'pre'
                Ri = A * Ri;
            otherwise
                error('acsPolhemusOrientationMatrix:BadMultiplyOrder', ...
                    'convention.multiplyOrder must be post or pre.');
        end
    end
    if convention.transpose
        Ri = Ri';
    end
    R(:, :, i) = Ri;
end
end

function R = axisRotation(axisName, theta)
c = cos(theta);
s = sin(theta);
switch lower(axisName)
    case 'x'
        R = [1 0 0; 0 c -s; 0 s c];
    case 'y'
        R = [c 0 s; 0 1 0; -s 0 c];
    case 'z'
        R = [c -s 0; s c 0; 0 0 1];
    otherwise
        error('acsPolhemusOrientationMatrix:BadAxis', 'Unknown axis %s.', axisName);
end
end
