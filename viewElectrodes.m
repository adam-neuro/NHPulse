function viewElectrodes(mask,elec,gel,landmarks,imgHdr,uniTag)
% viewElectrodes(mask,elec,gel,landmarks,imgHdr,uniTag)
%
% 3D Visualization of skin, brain, electrodes, gel, and anatomical landmarks
% from segmented MRI data. Displays a rendered volume with overlaid surfaces
% and points for interactive inspection of electrode placement.
%
% USAGE NOTES:
% - This function assumes the tissue labels in the segmentation:
%     Label 5 = Skin
%     Label 2 = Brain
% - Landmarks will be displayed in red with text labels for Nasion, Inion,
%   Right Ear, and Left Ear.
%
% See also: getLandmarksManual, checkLandmarks
%
% (c) Andrew Birnbaum, Parra Lab at CCNY
%     Yu (Andy) Huang
% June 2025

% nii_mask = flip(nii_mask, 2);      % Flip x-axis (left-right)
% nii_elec = flip(nii_elec, 2);
% nii_gel  = flip(nii_gel, 2);

mask_skin = imgaussfilt3(single(mask.img == 5), 1);
mask_brain = imgaussfilt3(single(mask.img == 2), 1);

elec = imgaussfilt3(single(elec.img>0), 1);
gel = imgaussfilt3(single(gel.img>0), 1);

% Create figure
fh=figure('Name', 'ROAST electrode/gel placement viewer', ...
       'NumberTitle', 'off', ...
       'Position', [100, 100, 1200, 800], ...
       'Color', 'white');
hold on;
voxelSize = sqrt(sum(imgHdr(1).mat(1:3, 1:3) .^ 2, 1));

% Plot skin (semi-transparent)
if any(mask_skin(:))
    p1 = patch(scaleIsoSurfaceToMm(isosurface(mask_skin, 0.5,'noshare'), voxelSize));
    p1.FaceColor = [229/255, 181/255, 161/255]; % light skin
    p1.EdgeColor = 'none';
    p1.FaceAlpha = 0.2;
end

% Plot brain (pink)
if any(mask_brain(:))
    p2 = patch(scaleIsoSurfaceToMm(isosurface(mask_brain, 0.5,'noshare'), voxelSize));
    p2.FaceColor = [1, 0.6, 0.8]; % pink
    p2.EdgeColor = 'none';
    p2.FaceAlpha = 1;
end

% Plot electrodes (blue)
if any(elec(:))
    p3 = patch(scaleIsoSurfaceToMm(isosurface(elec, 0.5,'noshare'), voxelSize));
    p3.FaceColor = 'blue';
    p3.EdgeColor = 'none';
    p3.FaceAlpha = .8;
end

% Plot gel (green)
if any(gel(:))
    p4 = patch(scaleIsoSurfaceToMm(isosurface(gel, 0.5,'noshare'), voxelSize));
    p4.FaceColor = 'green';
    p4.EdgeColor = 'none';
    p4.FaceAlpha = .8;
end

% Plot landmarks if provided
if ~isempty(landmarks)
    keepIdx = [1, 2, 3, 4];
    landmarksMm = voxelPointsToPlotMm(landmarks, voxelSize);
    scatter3(landmarksMm(keepIdx, 1), landmarksMm(keepIdx, 2), landmarksMm(keepIdx, 3), ...
        200, 'red', 'filled');
    labels = {'     Nasion', '     Inion', '     Right Ear', '     Left Ear'};
    for i = 1:length(keepIdx)
        text(landmarksMm(keepIdx(i), 1), landmarksMm(keepIdx(i), 2), landmarksMm(keepIdx(i), 3), ...
            labels{i}, 'FontSize', 14, 'Color', 'red', 'FontWeight', 'bold');
    end
end

view(3);
daspect([1 1 1]);
axis ij; % use axis ij, so that we can LR flip the axis from patch command, without flipping the data or hacking the order of labels
axis off;
grid off;
light('Position', [-1, 0, 0], 'Style', 'infinite');
light('Position', [1, 0, 1], 'Style', 'infinite');
lighting phong;
rotate3d on;
title('ROAST electrode and gel placement', 'Interpreter', 'none');
addColorWordLegend(fh);
movegui(fh,'center')
drawnow
%     % Save figure (optional — change path as needed)
%     saveas(gcf, fullfile(dirname, [subjName '_3DView.fig']));

function surface = scaleIsoSurfaceToMm(surface, voxelSize)
% isosurface vertices use plotting coordinates [dim2, dim1, dim3].
surface.vertices = bsxfun(@times, double(surface.vertices), ...
    double(voxelSize([2 1 3])));

function pointsMm = voxelPointsToPlotMm(pointsVoxel, voxelSize)
% Return plotting coordinates [dim2, dim1, dim3] in physical millimeters.
pointsMm = bsxfun(@times, double(pointsVoxel(:, [2 1 3])), ...
    double(voxelSize([2 1 3])));

function addColorWordLegend(figHandle)
annotation(figHandle, 'textbox', [0.82 0.91 0.12 0.035], ...
    'String', 'electrode', 'Color', [0 0 1], ...
    'FontWeight', 'bold', 'FontSize', 13, ...
    'EdgeColor', 'none', 'HorizontalAlignment', 'left', ...
    'VerticalAlignment', 'middle', 'Interpreter', 'none');
annotation(figHandle, 'textbox', [0.82 0.875 0.12 0.035], ...
    'String', 'gel', 'Color', [0 0.55 0], ...
    'FontWeight', 'bold', 'FontSize', 13, ...
    'EdgeColor', 'none', 'HorizontalAlignment', 'left', ...
    'VerticalAlignment', 'middle', 'Interpreter', 'none');
