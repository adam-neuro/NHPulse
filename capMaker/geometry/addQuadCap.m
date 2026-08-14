function TR = addQuadCap(TR, R, flipNormal)
% ADDQUADCAP  Append a quad (as two triangles) to close an end face.
% R is 4x3 rectangle corners in order.

V = TR.Points; 
F = TR.ConnectivityList;
i0 = size(V,1);
V2 = [V; R];

if flipNormal
    Fcap = [i0+1 i0+2 i0+3;  i0+1 i0+3 i0+4];
else
    Fcap = [i0+1 i0+3 i0+2;  i0+1 i0+4 i0+3];
end

TR = triangulation([F; Fcap], V2);
end
