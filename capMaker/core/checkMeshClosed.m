function info = checkMeshClosed(TR)
% checkMeshClosed  Basic watertightness / manifold check for a surface mesh.
%   info = checkMeshClosed(TR)
%   TR must be a triangulation with 3D vertices.
%
%   info.hasBoundaryEdges    : true if any edge is used by only 1 triangle
%   info.hasNonmanifoldEdges : true if any edge is used by >2 triangles
%   info.nBoundaryEdges      : count of boundary edges
%   info.nNonmanifoldEdges   : count of nonmanifold edges
%   info.isClosedManifold    : true if neither of the above
%
%   info.boundaryEdges       : [nBoundaryEdges x 2] vertex indices
%   info.nonmanifoldEdges    : [nNonmanifoldEdges x 2] vertex indices

    F = TR.ConnectivityList;
    V = TR.Points; %#ok<NASGU> % not used, but handy if you want to inspect

    % Build undirected edge list
    E = [F(:,[1 2]); F(:,[2 3]); F(:,[3 1])];
    E = sort(E,2);

    % Count how many times each edge appears
    [uE,~,idx] = unique(E,'rows');
    counts = accumarray(idx,1);

    boundaryMask    = (counts == 1);
    nonmanifoldMask = (counts > 2);

    info.boundaryEdges    = uE(boundaryMask,:);
    info.nonmanifoldEdges = uE(nonmanifoldMask,:);

    info.nBoundaryEdges    = nnz(boundaryMask);
    info.nNonmanifoldEdges = nnz(nonmanifoldMask);

    info.hasBoundaryEdges    = info.nBoundaryEdges    > 0;
    info.hasNonmanifoldEdges = info.nNonmanifoldEdges > 0;

    info.isClosedManifold = ~(info.hasBoundaryEdges || info.hasNonmanifoldEdges);
end
