function out = acsInspectHeadpostVoxelizationMesh(headpostIn, varargin)
% ACSINSPECTHEADPOSTVOXELIZATIONMESH Inspect the placed headpost mesh used for voxelization.
%
% out = acsInspectHeadpostVoxelizationMesh(headpostRoastMask) displays the
% raw placed mesh, the normal-repaired mesh, and the transformed T1 voxel-space
% mesh saved by acsVoxelizeHeadpostForRoast.
%
% out = acsInspectHeadpostVoxelizationMesh(headpostPlacement) displays the
% placed mesh from acsPlanHeadpostPlacement and a robustly reoriented copy.
%
% Name-value options:
%   showNormals : draw sampled face normals [true]
%   normalEvery : plot every Nth face normal [[] = automatic]
%   showSkull   : show placement skull mesh when available [true]
%   visible     : figure visibility ['on']

    if nargin < 1 || isempty(headpostIn)
        error('acsInspectHeadpostVoxelizationMesh:MissingInput', ...
            'Provide headpostRoastMask or headpostPlacement.');
    end

    opts = parseInputs(varargin{:});
    addLocalDependencies();
    S = readStructInput(headpostIn);
    meshes = resolveMeshes(S);

    fig = figure('Name', 'Headpost voxelization mesh inspection', ...
        'NumberTitle', 'off', 'Color', 'w', 'Visible', opts.visible, ...
        'Position', [70 60 1500 850]);
    nPanels = 2 + ~isempty(meshes.TRvoxel);
    tiledlayout(fig, 1, nPanels, 'Padding', 'loose', 'TileSpacing', 'loose');

    ax = nexttile;
    drawMeshPanel(ax, meshes.TRraw, meshes.TRskull, ...
        'Placed mesh', 'capMaker print mm', opts, [0.50 0.52 0.58]);

    ax = nexttile;
    drawMeshPanel(ax, meshes.TRprepared, meshes.TRskull, ...
        'Voxelization mesh', 'capMaker print mm', opts, [0.30 0.46 0.78]);

    if ~isempty(meshes.TRvoxel)
        ax = nexttile;
        drawMeshPanel(ax, meshes.TRvoxel, [], ...
            'Voxel-space mesh', 'T1 voxel coordinates', opts, [0.34 0.62 0.42]);
    end

    sgtitle(fig, 'Headpost voxelization mesh inspection', ...
        'Interpreter', 'none', 'FontWeight', 'bold');

    out = struct();
    out.figure = fig;
    out.meshes = meshes;
    out.topology = struct( ...
        'raw', meshTopologySummary(meshes.TRraw), ...
        'prepared', meshTopologySummary(meshes.TRprepared));
    if ~isempty(meshes.TRvoxel)
        out.topology.voxel = meshTopologySummary(meshes.TRvoxel);
    end

    printSummary(out);
end

function opts = parseInputs(varargin)
    p = inputParser;
    p.FunctionName = 'acsInspectHeadpostVoxelizationMesh';
    addParameter(p, 'showNormals', true, @isBoolLike);
    addParameter(p, 'normalEvery', [], ...
        @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x >= 1));
    addParameter(p, 'showSkull', true, @isBoolLike);
    addParameter(p, 'visible', 'on', @(x) ischar(x) || isstring(x));
    parse(p, varargin{:});

    opts = p.Results;
    opts.showNormals = logical(opts.showNormals);
    if ~isempty(opts.normalEvery)
        opts.normalEvery = round(double(opts.normalEvery));
    end
    opts.showSkull = logical(opts.showSkull);
    opts.visible = char(opts.visible);
end

function tf = isBoolLike(x)
    tf = (islogical(x) || isnumeric(x)) && isscalar(x);
end

function addLocalDependencies()
    repoRoot = fileparts(fileparts(mfilename('fullpath')));
    addpath(repoRoot);
    addpath(fullfile(repoRoot, 'acsUtilities'));
    addpath(fullfile(repoRoot, 'capMaker', 'core'));
end

function S = readStructInput(value)
    if isstruct(value)
        S = value;
        return;
    end
    fileName = expandUserPath(char(value));
    if exist(fileName, 'file') ~= 2
        error('acsInspectHeadpostVoxelizationMesh:FileNotFound', ...
            'Input file not found: %s', fileName);
    end
    raw = load(fileName);
    S = firstStruct(raw);
end

function S = firstStruct(raw)
    preferred = {'out', 'outForSave', 'headpostRoastMask', ...
        'headpostPlacement', 'placement'};
    for i = 1:numel(preferred)
        if isfield(raw, preferred{i}) && isstruct(raw.(preferred{i}))
            S = raw.(preferred{i});
            return;
        end
    end
    names = fieldnames(raw);
    for i = 1:numel(names)
        if isstruct(raw.(names{i}))
            S = raw.(names{i});
            return;
        end
    end
    error('acsInspectHeadpostVoxelizationMesh:NoStructInFile', ...
        'MAT file does not contain a readable struct.');
end

function meshes = resolveMeshes(S)
    meshes = struct('TRraw', [], 'TRprepared', [], 'TRvoxel', [], ...
        'TRskull', [], 'source', class(S));

    if isfield(S, 'voxelizationMeshes') && isstruct(S.voxelizationMeshes)
        V = S.voxelizationMeshes;
        meshes.TRraw = ensureTri(V.TRplacedRawPrintMm);
        meshes.TRprepared = ensureTri(V.TRplacedPreparedPrintMm);
        if isfield(V, 'TRplacedPreparedT1Voxel1')
            meshes.TRvoxel = ensureTri(V.TRplacedPreparedT1Voxel1);
        end
    elseif isfield(S, 'meshes') && isstruct(S.meshes) && ...
            isfield(S.meshes, 'TRplaced')
        meshes.TRraw = ensureTri(S.meshes.TRplaced);
        meshes.TRprepared = robustlyOrientMesh(meshes.TRraw);
        if isfield(S.meshes, 'TRskull')
            meshes.TRskull = ensureTri(S.meshes.TRskull);
        end
    elseif isfield(S, 'TRplaced')
        meshes.TRraw = ensureTri(S.TRplaced);
        meshes.TRprepared = robustlyOrientMesh(meshes.TRraw);
    else
        error('acsInspectHeadpostVoxelizationMesh:NoMeshFound', ...
            ['Input does not contain voxelizationMeshes, meshes.TRplaced, ', ...
             'or TRplaced. Rerun acsVoxelizeHeadpostForRoast to create ', ...
             'voxelizationMeshes.']);
    end

    if isempty(meshes.TRskull) && isfield(S, 'meshes') && ...
            isstruct(S.meshes) && isfield(S.meshes, 'TRskull')
        meshes.TRskull = ensureTri(S.meshes.TRskull);
    end
    if isempty(meshes.TRprepared)
        meshes.TRprepared = meshes.TRraw;
    end
end

function TRout = robustlyOrientMesh(TRin)
    TRout = TRin;
    if exist('unifyOutwardNormalsRobust', 'file') == 2
        try
            TRout = unifyOutwardNormalsRobust(TRin);
        catch
            TRout = TRin;
        end
    end
end

function TR = ensureTri(value)
    if isempty(value)
        TR = [];
    elseif isa(value, 'triangulation')
        TR = value;
    elseif isstruct(value) && isfield(value, 'ConnectivityList') && ...
            isfield(value, 'Points')
        TR = triangulation(double(value.ConnectivityList), double(value.Points));
    else
        error('acsInspectHeadpostVoxelizationMesh:BadTriangulation', ...
            'Expected a triangulation or struct with Points and ConnectivityList.');
    end
end

function drawMeshPanel(ax, TR, TRskull, titleText, frameText, opts, color)
    hold(ax, 'on');
    if opts.showSkull && ~isempty(TRskull)
        patch(ax, 'Faces', TRskull.ConnectivityList, 'Vertices', TRskull.Points, ...
            'FaceColor', [0.78 0.78 0.72], 'FaceAlpha', 0.12, ...
            'EdgeColor', 'none', 'HandleVisibility', 'off');
    end
    patch(ax, 'Faces', TR.ConnectivityList, 'Vertices', TR.Points, ...
        'FaceColor', color, 'FaceAlpha', 0.82, ...
        'EdgeColor', [0.08 0.08 0.08], 'EdgeAlpha', 0.18, ...
        'LineWidth', 0.25);
    if opts.showNormals
        drawFaceNormals(ax, TR, opts.normalEvery);
    end
    axis(ax, 'equal');
    axis(ax, 'vis3d');
    grid(ax, 'on');
    xlabel(ax, 'X');
    ylabel(ax, 'Y');
    zlabel(ax, 'Z');
    title(ax, sprintf('%s\n%s', titleText, frameText), ...
        'Interpreter', 'none');
    view(ax, 3);
    camproj(ax, 'orthographic');
    camlight(ax, 'headlight');
    lighting(ax, 'gouraud');
end

function drawFaceNormals(ax, TR, normalEvery)
    F = double(TR.ConnectivityList);
    V = double(TR.Points);
    if isempty(normalEvery)
        normalEvery = max(1, round(size(F, 1) / 350));
    end
    f1 = F(:, 1);
    f2 = F(:, 2);
    f3 = F(:, 3);
    v1 = V(f1, :);
    v2 = V(f2, :);
    v3 = V(f3, :);
    N = cross(v2 - v1, v3 - v1, 2);
    n = sqrt(sum(N .^ 2, 2));
    keep = n > eps;
    N(keep, :) = N(keep, :) ./ n(keep);
    C = (v1 + v2 + v3) ./ 3;
    rows = 1:normalEvery:size(F, 1);
    rows = rows(keep(rows));
    scale = 0.015 * norm(max(V, [], 1) - min(V, [], 1));
    quiver3(ax, C(rows, 1), C(rows, 2), C(rows, 3), ...
        N(rows, 1), N(rows, 2), N(rows, 3), scale, ...
        'Color', [0.95 0.10 0.10], 'LineWidth', 0.8, ...
        'HandleVisibility', 'off');
end

function info = meshTopologySummary(TR)
    V = double(TR.Points);
    F = double(TR.ConnectivityList);
    edges = [F(:, [1 2]); F(:, [2 3]); F(:, [3 1])];
    edges = sort(edges, 2);
    [~, ~, edgeGroup] = unique(edges, 'rows');
    edgeUseCount = accumarray(edgeGroup, 1);
    info = struct();
    info.vertexCount = size(V, 1);
    info.faceCount = size(F, 1);
    info.boundaryEdgeCount = nnz(edgeUseCount == 1);
    info.nonmanifoldEdgeCount = nnz(edgeUseCount > 2);
    info.isEdgeWatertight = info.boundaryEdgeCount == 0 && ...
        info.nonmanifoldEdgeCount == 0;
    info.signedVolume = meshSignedVolumeLocal(V, F);
    info.boundingBox = [min(V, [], 1); max(V, [], 1)];
end

function value = meshSignedVolumeLocal(V, F)
    if isempty(V) || isempty(F)
        value = 0;
        return;
    end
    v1 = V(F(:, 1), :);
    v2 = V(F(:, 2), :);
    v3 = V(F(:, 3), :);
    value = sum(dot(v1, cross(v2, v3, 2), 2)) / 6;
end

function printSummary(out)
    fprintf('Headpost voxelization mesh inspection\n');
    fprintf('  raw:      %d faces, watertight=%d, signed volume=%.3g\n', ...
        out.topology.raw.faceCount, out.topology.raw.isEdgeWatertight, ...
        out.topology.raw.signedVolume);
    fprintf('  prepared: %d faces, watertight=%d, signed volume=%.3g\n', ...
        out.topology.prepared.faceCount, ...
        out.topology.prepared.isEdgeWatertight, ...
        out.topology.prepared.signedVolume);
    if isfield(out.topology, 'voxel')
        fprintf('  voxel:    %d faces, watertight=%d, signed volume=%.3g\n', ...
            out.topology.voxel.faceCount, ...
            out.topology.voxel.isEdgeWatertight, ...
            out.topology.voxel.signedVolume);
    end
end

function pathOut = expandUserPath(pathIn)
    pathOut = char(pathIn);
    if isempty(pathOut)
        return;
    end
    if startsWith(pathOut, '~')
        pathOut = fullfile(char(java.lang.System.getProperty('user.home')), ...
            pathOut(2:end));
    end
end
