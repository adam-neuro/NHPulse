function voxelConventionSanity()
% voxelConventionSanity  Lightweight assertion of canonical voxel→mesh mapping.
%
% Builds a simple scalar field occ = X on an ndgrid(x,y,z) lattice, runs it
% through triFromOccHelper, and checks the resulting mesh aligns with the
% expected world extents without any axis swaps.

    x = [0 1 2];
    y = [-1 0 1];
    z = [5 6];
    [X, ~, ~] = ndgrid(x, y, z);

    isoValue = 1;           % plane x=1 in world space
    occ = X;                % matches canonical occ(i,j,k) -> (x(i), y(j), z(k))

    [TR, occAligned, meta] = triFromOccHelper(x, y, z, occ, isoValue, struct());

    assert(~isempty(TR.ConnectivityList), 'Expected non-empty isosurface for plane x=1.');
    assert(isequal(size(occAligned), [numel(x), numel(y), numel(z)]), 'occAligned size mismatch.');
    assert(~meta.wasPermuted, 'Unexpected permutation detected in canonical input.');

    bbMin = min(TR.Points, [], 1);
    bbMax = max(TR.Points, [], 1);

    expMin = [1, min(y), min(z)];
    expMax = [1, max(y), max(z)];

    tol = 1e-6;
    assert(all(abs(bbMin - expMin) < tol), 'Bounding box min does not match canonical axes.');
    assert(all(abs(bbMax - expMax) < tol), 'Bounding box max does not match canonical axes.');

    fprintf('voxelConventionSanity: PASS (canonical voxel convention enforced)\n');
end
