function TRscaled = scaleTri(TR, factor)
% scaleTri  Isotropic scaling of a triangulation
%
%   TRscaled = scaleTri(TR, factor)
%
% INPUT
%   TR     : triangulation object
%   factor : scalar scale factor (>0)
%
% OUTPUT
%   TRscaled : new triangulation object with all points scaled

    arguments
        TR triangulation
        factor (1,1) double {mustBePositive}
    end

    % Scale vertex coordinates
    Vscaled = TR.Points * factor;

    % Re-wrap with same connectivity
    TRscaled = triangulation(TR.ConnectivityList, Vscaled);
end
