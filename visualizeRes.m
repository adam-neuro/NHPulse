function visualizeRes(subj,mask,mri2mni,node,elem,face,inCurrent,imgHdr,uniTag,varargin)
% visualizeRes(subj,mask,mri2mni,node,elem,face,inCurrent,imgHdr,uniTag,varargin)
%
% Display the simulation results. The 3D rendering is displayed in the
% world space, while the slice view is done in the voxel space.
%
% (c) Yu (Andy) Huang, Parra Lab at CCNY
% yhuang16@citymail.cuny.edu
% April 2018
% August 2019 callable by roast_target()
%
% (c) May 2024, sliceshow improved by Gavin Hsu and Andrew Birnbaum

[extraTissues, visualizationOptions, varargin] = parseOptionalStructs(varargin);

if ndims(varargin{1})==3
    isRoast = 1;
    vol_all = varargin{1}; ef_mag = varargin{2}; ef_all = varargin{3};
else
    isRoast = 0;
    C = varargin{1}; ef_mag = varargin{2}; ef_all = varargin{3}; targetCoord = varargin{4};
    indMonElec = find(abs(inCurrent)>1e-3); % this is not perfect
end

[dirname,subjName] = fileparts(subj);
if isempty(dirname), dirname = pwd; end

tissueCfg = roastTissueConfig(extraTissues);
numOfTissue = tissueCfg.numOfTissue;
numOfGel = length(inCurrent);
    
% node = node + 0.5; already done right after mesh

% scrsz = get(groot,'ScreenSize');

disp('generating 3D renderings...')

for i=1:3, node(:,i) = node(:,i)/imgHdr(1).mat(i,i); end
% convert pseudo-world coordinates back to voxel coordinates so that the
% following conversion to pure-world space is meaningful

voxCoord = [node(:,1:3) ones(size(node,1),1)];
worldCoord = (imgHdr(1).mat*voxCoord')';
% do the 3D rendering in world space, to avoid confusion in left-right;
% sliceshow below is still in voxel space though
node(:,1:3) = worldCoord(:,1:3);

indNode_grayFace = face(find(face(:,4) == 2),1:3);
indNode_grayElm = elem(find(elem(:,5) == 2),1:4);

% node(:,1:3) = sms(node(:,1:3),indNode_grayFace);
% % smooth the surface that's to be displayed
% % just for display, the output data is not smoothed
% % very slow if mesh is big

if isRoast
    
    indNode_elecFace = face(find(face(:,4) > numOfTissue+numOfGel),1:3);
    indNode_elecElm = elem(find(elem(:,5) > numOfTissue+numOfGel),1:4);
    inCurrentRange = [min(inCurrent) max(inCurrent)];
    
    fid = fopen([dirname filesep subjName '_' uniTag '_v.pos']);
    fgetl(fid);
    C = textscan(fid,'%d %f');
    fclose(fid);
    
    C{2} = C{2} - min(C{2}); % re-reference the voltage
    
    % dataShow = [node(C{1},1:3) C{2}];
    color = nan(size(node,1),1);
    color(C{1}) = C{2};
    dataShow = [node(:,1:3) color];
    
    figName = ['Voltage in Simulation: ' uniTag];
    figure('Name',[figName '. Move your mouse to rotate.'],'NumberTitle','off');
    set(gcf,'color','w');
    colormap(jet);
    plotmesh(dataShow,indNode_grayFace,indNode_grayElm,'LineStyle','none');
    dataShowRange = [min(dataShow(unique(indNode_grayElm(:)),4)) max(dataShow(unique(indNode_grayElm(:)),4))];
    dataShowForElec = interp1(inCurrentRange,dataShowRange,inCurrent);
    for i=1:length(inCurrent)
        %     indNodeTemp = indNode_elecElm(find(label_elec==i),:);
        %     dataShow(unique(indNodeTemp(:)),4) = dataShowForElec(i);
        dataShow(unique(elem(find(elem(:,5) == numOfTissue+numOfGel+i),1:4)),4) = dataShowForElec(i);
    end % to show injected current intensities properly
    hold on;
    plotmesh(dataShow,indNode_elecFace,indNode_elecElm,'LineStyle','none');
    axis off; rotate3d on;
    % set(hp1,'SpecularColorReflectance',0,'SpecularExponent',50);
    caxis(dataShowRange);
    lightangle(-90,45)
    lightangle(90,45)
    lightangle(-90,-45)
    hc1 = colorbar; set(hc1,'FontSize',18,'YAxisLocation','right');
    title(hc1,'Voltage (mV)','FontSize',18);
    a1 = gca;
    a2 = axes('Color','none','Position',get(a1,'Position'),'XLim',get(a1,'XLim'),'YLim',get(a1,'YLim'),'ZLim',get(a1,'ZLim'));
    axis off;
    hc2 = colorbar; set(hc2,'FontSize',18,'YAxisLocation','right','Location','westoutside');
    title(hc2,'Injected current (mA)','FontSize',18);
    caxis(inCurrentRange);
    axes(a1);
    drawnow
    
    fid = fopen([dirname filesep subjName '_' uniTag '_e.pos']);
    fgetl(fid);
    C = textscan(fid,'%d %f %f %f');
    fclose(fid);
    
    % dataShow = [node(C{1},1:3), C_ef_mag];
    color = nan(size(node,1),1);
    color(C{1}) = sqrt(C{2}.^2+C{3}.^2+C{4}.^2);
    dataShow = [node(:,1:3) color];
    
    figName = ['Electric field in Simulation: ' uniTag];
    figure('Name',[figName '. Move your mouse to rotate.'],'NumberTitle','off');
    set(gcf,'color','w');
    colormap(jet);
    plotmesh(dataShow,indNode_grayFace,indNode_grayElm,'LineStyle','none');
%     dataShowVal = dataShow(unique(indNode_grayElm(:)),4);
    dataShowRange = electricFieldClim( ...
        dataShow(unique(indNode_grayElm(:)),4), ef_mag, mask, ...
        visualizationOptions);
    dataShowForElec = interp1(inCurrentRange,dataShowRange,inCurrent);
    for i=1:length(inCurrent)
        %     indNodeTemp = indNode_elecElm(find(label_elec==i),:);
        %     dataShow(unique(indNodeTemp(:)),4) = dataShowForElec(i);
        dataShow(unique(elem(find(elem(:,5) == numOfTissue+numOfGel+i),1:4)),4) = dataShowForElec(i);
    end % to show injected current intensities properly
    hold on;
    plotmesh(dataShow,indNode_elecFace,indNode_elecElm,'LineStyle','none');
    axis off; rotate3d on;
    % set(hp2,'SpecularColorReflectance',0,'SpecularExponent',50);
    caxis(dataShowRange);
    lightangle(-90,45)
    lightangle(90,45)
    lightangle(-90,-45)
    hc1 = colorbar; set(hc1,'FontSize',18,'YAxisLocation','right');
    title(hc1,'Electric field (V/m)','FontSize',18);
    a1 = gca;
    a2 = axes('Color','none','Position',get(a1,'Position'),'XLim',get(a1,'XLim'),'YLim',get(a1,'YLim'),'ZLim',get(a1,'ZLim'));
    axis off;
    hc2 = colorbar; set(hc2,'FontSize',18,'YAxisLocation','right','Location','westoutside');
    title(hc2,'Injected current (mA)','FontSize',18);
    caxis(inCurrentRange);
    axes(a1);
    drawnow
    
else
    
    indNode_elecFace = face(ismember(face(:,4),numOfTissue+numOfGel+indMonElec),1:3);
    indNode_elecElm = elem(ismember(elem(:,5),numOfTissue+numOfGel+indMonElec),1:4);
    inCurrentRange = [min(inCurrent) max(inCurrent)];
    
    color = nan(size(node,1),1);
    color(C(:,1)) = sqrt(sum(C(:,2:4).^2,2));
    dataShow = [node(:,1:3) color];
    
    figName = ['Electric field in Targeting: ' uniTag];
    figure('Name',[figName '. Move your mouse to rotate.'],'NumberTitle','off');
    set(gcf,'color','w');
    colormap(jet);
    plotmesh(dataShow,indNode_grayFace,indNode_grayElm,'LineStyle','none');
%     dataShowVal = dataShow(unique(indNode_grayElm(:)),4);
    dataShowRange = electricFieldClim( ...
        dataShow(unique(indNode_grayElm(:)),4), ef_mag, mask, ...
        visualizationOptions);
    dataShowForElec = interp1(inCurrentRange,dataShowRange,inCurrent(indMonElec));
    for i=1:length(indMonElec)
        %     indNodeTemp = indNode_elecElm(find(label_elec==i),:);
        %     dataShow(unique(indNodeTemp(:)),4) = dataShowForElec(i);
        dataShow(unique(elem(find(elem(:,5) == numOfTissue+numOfGel+indMonElec(i)),1:4)),4) = dataShowForElec(i);
    end % to show injected current intensities properly
    hold on;
    plotmesh(dataShow,indNode_elecFace,indNode_elecElm,'LineStyle','none');
    axis off; rotate3d on;
    % set(hp2,'SpecularColorReflectance',0,'SpecularExponent',50);
    caxis(dataShowRange);
    lightangle(-90,45)
    lightangle(90,45)
    lightangle(-90,-45)
    hc1 = colorbar; set(hc1,'FontSize',18,'YAxisLocation','right');
    title(hc1,'Electric field (V/m)','FontSize',18);
    a1 = gca;
    a2 = axes('Color','none','Position',get(a1,'Position'),'XLim',get(a1,'XLim'),'YLim',get(a1,'YLim'),'ZLim',get(a1,'ZLim'));
    axis off;
    hc2 = colorbar; set(hc2,'FontSize',18,'YAxisLocation','right','Location','westoutside');
    title(hc2,'Injected current (mA)','FontSize',18);
    caxis(inCurrentRange);
    axes(a1);
    drawnow
    
end

disp('generating slice views...');

brain = (mask.img==1 | mask.img==2);
nan_mask_brain = nan(size(brain));
nan_mask_brain(find(brain)) = 1;

cm = colormap(jet(2^11)); cm = [1 1 1;cm];
bbox = brainCrop(mask.img);

if isRoast
    figName = ['Voltage in Simulation: ' uniTag];
    sliceshow(vol_all.*nan_mask_brain,round(mean(bbox)),cm,[],'Voltage (mV)',[figName '. Click anywhere to navigate.'],[],mri2mni,bbox); drawnow
end

for i=1:size(ef_all,4), ef_all(:,:,:,i) = ef_all(:,:,:,i).*nan_mask_brain; end
ef_mag = ef_mag.*nan_mask_brain;
dataShowVal = ef_mag(~isnan(ef_mag(:)));
if isRoast
    figName = ['Electric field in Simulation: ' uniTag];
    sliceshow(ef_mag,round(mean(bbox)),cm,electricFieldClim(dataShowVal,ef_mag,mask,visualizationOptions),'Electric field (V/m)',[figName '. Click anywhere to navigate.'],ef_all,mri2mni,bbox); drawnow
else
    
    for i=1:size(targetCoord,1)
        figName = ['Electric field at Target ' num2str(i) ' in Targeting: ' uniTag];
        sliceshow(ef_mag,targetCoord(i,:),cm,electricFieldClim(dataShowVal,ef_mag,mask,visualizationOptions),'Electric field (V/m)',[figName '. Click anywhere to navigate.'],ef_all,mri2mni,bbox); drawnow
    end
end

end

function [extraTissues, visualizationOptions, args] = parseOptionalStructs(args)
extraTissues = [];
visualizationOptions = defaultVisualizationOptions();
while ~isempty(args) && isstruct(args{end})
    value = args{end};
    if isVisualizationOptions(value)
        visualizationOptions = mergeVisualizationOptions( ...
            visualizationOptions, value);
        args = args(1:end-1);
    elseif isExtraTissues(value)
        extraTissues = value;
        args = args(1:end-1);
    else
        break;
    end
end
end

function opts = defaultVisualizationOptions()
opts = struct();
opts.electricFieldClimMode = 'surfacePercentile';
opts.electricFieldClimPercentile = 95;
opts.electricFieldClim = [];
end

function tf = isVisualizationOptions(value)
tf = isfield(value, 'electricFieldClimMode') || ...
    isfield(value, 'electricFieldClimPercentile') || ...
    isfield(value, 'electricFieldClim');
end

function tf = isExtraTissues(value)
tf = isfield(value, 'label') || isfield(value, 'extraTissues');
end

function opts = mergeVisualizationOptions(opts, value)
fields = fieldnames(value);
for i = 1:numel(fields)
    opts.(fields{i}) = value.(fields{i});
end
end

function clim = electricFieldClim(surfaceValues, efMagVolume, mask, opts)
if ~isempty(opts.electricFieldClim)
    clim = validateExplicitClim(opts.electricFieldClim);
    return;
end
pct = double(opts.electricFieldClimPercentile);
if ~isfinite(pct) || pct <= 0 || pct > 100
    error('visualizeRes:BadElectricFieldClimPercentile', ...
        'electricFieldClimPercentile must be in the interval (0, 100].');
end
mode = lower(strtrim(char(opts.electricFieldClimMode)));
switch mode
    case {'surfacepercentile', 'surface', 'legacy', 'legacy95'}
        vals = finiteValues(surfaceValues);
        lo = min(vals);
        hi = prctile(vals, pct);
    case {'brainpercentile', 'brain', 'brainvolume', 'volumepercentile'}
        brain = (mask.img == 1 | mask.img == 2);
        vals = finiteValues(efMagVolume(brain));
        lo = 0;
        hi = prctile(vals, pct);
    otherwise
        error('visualizeRes:BadElectricFieldClimMode', ...
            ['electricFieldClimMode must be ''surfacePercentile'', ', ...
             '''brainPercentile'', or provide electricFieldClim.']);
end
clim = sanitizeClim([lo hi]);
end

function clim = validateExplicitClim(climIn)
clim = double(climIn);
if ~isequal(size(clim), [1 2]) || any(~isfinite(clim)) || clim(2) <= clim(1)
    error('visualizeRes:BadElectricFieldClim', ...
        'electricFieldClim must be a finite 1 x 2 increasing numeric vector.');
end
end

function vals = finiteValues(vals)
vals = double(vals(:));
vals = vals(isfinite(vals));
if isempty(vals)
    vals = [0; 1];
end
end

function clim = sanitizeClim(clim)
if any(~isfinite(clim)) || clim(2) <= clim(1)
    center = clim(1);
    if ~isfinite(center)
        center = 0;
    end
    clim = [center, center + 1];
end
end
