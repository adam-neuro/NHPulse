function TRout = concatTriList(TRlist)
% CONCATTRILIST  Concatenate multiple triangulations into one.
% Assumes meshes do not overlap and no boolean ops are needed.
%
% Usage:
%   TRout = concatTriList({TR1, TR2, ...});

    V = zeros(0,3);
    F = zeros(0,3);

    for i = 1:numel(TRlist)
        TR = TRlist{i};
        v0 = size(V,1);
        V  = [V; TR.Points]; %#ok<AGROW>
        F  = [F; TR.ConnectivityList + v0]; %#ok<AGROW>
    end

    TRout = triangulation(F,V);
end
