function TR = makeTypicalStrapAssembly(anchor, outDir, opts)
% MAKETYPICALSTRAPASSEMBLY  Ring + corrugated strap (bed → ramp → cap anchor).
%   TR = makeTypicalStrapAssembly([x y z], [dx dy (dz)], opts)
%
% Requires:
%   makeCorrugatedStrapPath.m  (your finalized version)
%   (Optional) makeTorusTri.m  (fallback provided if absent)

    if nargin < 2 || isempty(outDir)
        error('makeTypicalStrapAssembly:NeedOutDir','You must provide outDir (XY direction).');
    end
    if nargin < 3, opts = struct; end
    g = @(f,def) getOr(opts,f,def);

    % ---------- parameters ----------
    zBed        = g('zBed',0);
    ahead       = g('strapAheadMM',0);
    bedRun      = g('bedRunMM',60);
    rampRun     = g('rampRunMM',20);
    rampRise    = g('rampRiseMM',20);
    approach    = g('approachMM',3);

    W           = g('strapWidthMM',20);
    T           = g('strapThickMM',2.4);
    ds          = g('dsMM',1.0);
    cAmp        = g('corrAmpMM',0.8);
    cPitch      = g('corrPitchMM',10);
    cAxis       = g('corrAxis','thickness');
    twistDeg    = g('twistDeg',90);
    alignTo     = g('alignWidthTo',[]);
    ovFrac      = g('overlapFrac',0.35);
    ovMM        = g('overlapMM',1.2);

    ringOD      = g('ringOuterDiaMM',20);
    ringTube    = g('ringTubeDiaMM',3.5);
    ringOff     = g('ringOffsetMM',50);
    ringOverlap = g('ringOverlapMM',-15);     % neg = deeper into strap
    nMaj        = g('ringMajorSegs',96);
    nTube       = g('ringTubeSegs',24);

    % ---------- outward direction in XY ----------
    tOut = outDir(:)'; if numel(tOut)<3, tOut(3)=0; end
    tOut(3) = 0;
    if norm(tOut)<1e-12, tOut=[1 0 0]; end
    tOut = tOut / norm(tOut);

    % ---------- ring center (flat on bed, z = zBed) ----------
    r       = ringTube./2;
    ringR   = ringOD/2;
    ringC   = anchor + tOut*ringOff;
    ringC(3)= zBed + r;                 % ring on the bed plane
    ringC(2)= ringC(2) + ahead;
    ringAxis= [0 0 1];
    TRring  = safeMakeTorus(ringOD, ringTube, nMaj, nTube, ringC, ringAxis);

    % ---------- strap path starts at inboard tangent point on ring ----------
    % Attach point is toward the cap, i.e., opposite tOut
    P0 = ringC - tOut*(ringR - ringOverlap);

    % Bed run inward (toward cap) along -tOut
    P1 = P0 - tOut * bedRun;

    % Ramp inward + up
    P2 = P1;
    P3 = P2 - tOut * rampRun + [0 0 rampRise];

    % Short approach toward the anchor
    vTo = anchor - P3; vTo = vTo ./ max(1e-12,norm(vTo));
    P4 = P3 + approach * vTo;

    P  = [P0; P1; P2; P3; P4];

    % --- Keep strap's *bottom* on bed during bed-run: centerline at zBed+T/2 ---
    bedZcenter = zBed + T/2 + cAmp + 1e-3;
    P(1:3,3)   = bedZcenter;                 % P0,P1,P2 are bed-run/hinge points
    P(4:5,3)   = max(P(4:5,3), bedZcenter);  % don't dip below the bed as we ramp


    % ---------- corrugated strap ----------
    strapOpts = struct('widthMM',W,'thickMM',T,'dsMM',ds, ...
                       'corrAmpMM',cAmp,'corrPitchMM',cPitch, ...
                       'corrAxis',cAxis,'twistDeg',twistDeg, ...
                       'alignWidthTo',alignTo,'overlapFrac',ovFrac, ...
                       'overlapMM',ovMM,...
                       'endCap',true,'upVec',[0 0 1]);
    TRstrap = makeCorrugatedStrapPath(P, strapOpts);

    % ---------- assemble (no neck block) ----------
    TR = catTri(TRring, TRstrap);

    if exist('remove_unreferenced','file')==2
        [V2,F2] = remove_unreferenced(TR.Points, TR.ConnectivityList);
        TR = triangulation(F2,V2);
    end

    TR = unifyOutwardNormalsRobust(TR);
    
end

% ================= helpers =================
function v = getOr(s,f,def)
    if isstruct(s) && isfield(s,f) && ~isempty(s.(f)), v=s.(f); else, v=def; end
end

function TR = catTri(A,B)
    if isempty(A), TR=B; return; end
    if isempty(B), TR=A; return; end
    VA=A.Points; FA=A.ConnectivityList;
    VB=B.Points; FB=B.ConnectivityList;
    V=[VA;VB]; F=[FA; FB+size(VA,1)];
    TR = triangulation(F,V);
end

function TR = safeMakeTorus(outerDia, tubeDia, nMaj, nTube, center, axisVec)
    ok = false; TR = [];
    if exist('makeTorusTri','file')==2
        sigs = { ...
            {@() makeTorusTri(outerDia, tubeDia, nMaj, nTube, center, axisVec)}, ...
            {@() makeTorusTri(outerDia, tubeDia, center, axisVec, nMaj, nTube)} ...
        };
        for k=1:numel(sigs)
            try
                TRtry = sigs{k}{1}();
                if isa(TRtry,'triangulation')
                    TR = TRtry; ok = true; break;
                end
            catch %#ok<CTCH>
            end
        end
    end
    if ~ok
        TR = inlineTorus(outerDia, tubeDia, nMaj, nTube, center, axisVec);
    end
end

function TR = inlineTorus(outerDia, tubeDia, nMaj, nTube, center, axisVec)
    R = outerDia/2; r = tubeDia/2;
    u = linspace(0,2*pi,nMaj+1); u(end)=[];
    v = linspace(0,2*pi,nTube+1); v(end)=[];
    [U,V] = ndgrid(u,v);
    X = (R + r.*cos(V)) .* cos(U);
    Y = (R + r.*cos(V)) .* sin(U);
    Z =  r .* sin(V);
    P = [X(:) Y(:) Z(:)];
    % Rotate Z-axis to axisVec
    a = axisVec(:)'; if norm(a)<1e-12, a=[0 0 1]; end; a = a/norm(a);
    Rm = rotz_to_axis(a); P = (Rm*P.').'; P = P + center;
    nm = numel(u); nt = numel(v);
    idx=@(i,j)sub2ind([nm,nt],mod(i-1,nm)+1,mod(j-1,nt)+1);
    F = zeros(nm*nt*2,3); f=0;
    for i=1:nm
        for j=1:nt
            i2=i+1; j2=j+1;
            a1=idx(i,j); b1=idx(i2,j); c1=idx(i2,j2); d1=idx(i,j2);
            F(f+1,:)=[a1 b1 c1]; F(f+2,:)=[a1 c1 d1]; f=f+2;
        end
    end
    TR = triangulation(F,P);
end

function R = rotz_to_axis(a)
    z=[0 0 1]; v=cross(z,a); s=norm(v); c=dot(z,a);
    if s<1e-12, R = (c>0)*eye(3) + (c<=0)*diag([-1 -1 1]); return; end
    vx=[0 -v(3) v(2); v(3) 0 -v(1); -v(2) v(1) 0];
    R = eye(3)+vx+vx*vx*((1-c)/(s^2));
end
