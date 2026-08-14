function TRlist = makeHoleClearingTetras(holeTops, holeBottoms, insideDia, varargin)
% BATCH BUILDER FOR HOLE-ALIGNED TETRA KEEP-OUTS
% holeTops, holeBottoms: [N x 3]
% insideDia: [N x 1] (mm) – use your holder's inside diameter for each hole
% Optional name-value pairs forwarded to makeTetraKeepout

assert(size(holeTops,2)==3 && size(holeBottoms,2)==3, 'Expect N x 3 inputs.');
assert(size(holeTops,1)==size(holeBottoms,1), 'Size mismatch.');
N = size(holeTops,1);
if isscalar(insideDia), insideDia = insideDia*ones(N,1); end
assert(numel(insideDia)==N, 'insideDia must be scalar or N-vector.');

TRlist = cell(N,1);
for i = 1:N
    % Base radius: start at slightly larger than the hole radius to be robust
    baseR = 0.55 * insideDia(i);   % 10% margin vs. radius (tweak as needed)
    TRlist{i} = makeTetraKeepout(holeTops(i,:).', holeBottoms(i,:).', baseR, varargin{:});
end
end
