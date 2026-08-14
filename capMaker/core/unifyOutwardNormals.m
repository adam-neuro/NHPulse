function TR2 = unifyOutwardNormals(TR)
% Flip any triangle whose normal points toward the shape centroid.
    V = TR.Points; F = TR.ConnectivityList;
    C = mean(V,1);                  % mesh centroid
    a = V(F(:,1),:); b = V(F(:,2),:); c = V(F(:,3),:);
    N = cross(b-a,c-a);             % unnormalized face normals
    fc = (a+b+c)/3;                 % face centroids
    flip = dot(N, C - fc, 2) > 0;   % inward? (toward centroid) -> flip
    F(flip,[2 3]) = F(flip,[3 2]);
    TR2 = triangulation(F,V);
end
