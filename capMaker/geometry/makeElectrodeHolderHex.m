function TR = makeElectrodeHolderHex(insideDia, outsideDia, heightMM)
% makeElectrodeHolderHex  Hexagonal prism w/ hex hole by physical dims.
% Inputs (mm): insideDia = inner V–V diameter, outsideDia = outer V–V diameter,
%              heightMM = overall height.
% Returns: triangulation object, base on z=0, centered at (0,0).

    arguments
        insideDia   (1,1) double {mustBePositive}
        outsideDia  (1,1) double {mustBePositive}
        heightMM    (1,1) double {mustBePositive}
    end
    assert(insideDia < outsideDia, 'insideDia must be < outsideDia.');

    % Your generator expects:
    %   R1 = (height / outer side length),  R2 = (outer side length / inner side length).
    % For a regular hexagon: vertex–to–vertex diameter = 2 * sideLength.
    R1 = heightMM / outsideDia;     % height : s_out
    R2 =  outsideDia   / insideDia;     % s_out : s_in

    % 1) Build canonical holder (unit-ish), using your existing function:
    tri0 = makeHexPrismWithHole(R1, R2);   % assumes this returns triangulation

    % 2) Isotropic scale so outer V–V diameter equals outsideDia exactly.
    V   = tri0.Points;
    rMax = max(vecnorm(V(:,1:2),2,2));     % max radial distance in XY
    currDia = 2*rMax;                      % current outer V–V diameter
    s   = outsideDia / currDia;
    TR  = scaleTri(tri0, s);               % your existing isotropic scaler

    % Optional: enforce outward normals (robust downstream)
    if exist('unifyOutwardNormals','file')==2
        TR = unifyOutwardNormals(TR);
    end
end
