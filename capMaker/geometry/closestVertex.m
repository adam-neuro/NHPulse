function idx = closestVertex(TR, pos)
% closestVertex  Find the index of the vertex in a triangulation closest to a point.
%
%   idx = closestVertex(TR, pos)
%
% INPUT
%   TR  : triangulation object
%   pos : 1x3 position vector
%
% OUTPUT
%   idx : index of the closest vertex in TR.Points

    arguments
        TR triangulation
        pos (1,3) double {mustBeFinite}
    end

    % Compute squared distances to all vertices
    d2 = sum((TR.Points - pos).^2, 2);

    % Find index of minimum
    [~, idx] = min(d2);
end
