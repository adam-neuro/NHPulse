function [node,elem,face] = meshByIso2mesh(subj,mask,elec,gel,opt,imgHdr,uniTag,extraTissues)
% [node,elem,face] = meshByIso2mesh(subj,mask,elec,gel,opt,imgHdr,uniTag,extraTissues)
%
% Generate volumetric tetrahedral mesh using iso2mesh toolbox
% http://iso2mesh.sourceforge.net/cgi-bin/index.cgi?Download
%
% (c) Yu (Andy) Huang, Parra Lab at CCNY
% yhuang16@citymail.cuny.edu
% October 2017

[dirname,subjName] = fileparts(subj);
if isempty(dirname), dirname = pwd; end

if nargin < 8
    extraTissues = [];
end
tissueCfg = roastTissueConfig(extraTissues);
allMask = mask.img;
numOfTissue = tissueCfg.numOfTissue;
% data = load_untouch_nii([dirname filesep subjName '_' uniTag '_mask_gel.nii']);
% allMask(data.img==255) = 7;
% data = load_untouch_nii([dirname filesep subjName '_' uniTag '_mask_elec.nii']);
% allMask(data.img==255) = 8;

numOfGel = max(gel.img(:));
for i=1:numOfGel
    allMask(gel.img==i) = numOfTissue + i;
end
numOfElec = max(elec.img(:));
validateGelElectrodeMaskPairs(gel.img, elec.img, numOfGel, numOfElec, uniTag);
for i=1:numOfElec
    allMask(elec.img==i) = numOfTissue + numOfGel + i;
end

maxLabelValue = max(allMask(:));
if maxLabelValue > double(intmax('uint8'))
    error('meshByIso2mesh:TooManyDomains', ...
        ['The assembled ROAST domain volume contains label %g, which ', ...
         'exceeds the uint8 range required by cgalv2m.'], maxLabelValue);
end
allMask = uint8(round(allMask));
domainReport = initializeDomainReport(allMask, tissueCfg, numOfGel, ...
    numOfElec);

% opt.radbound = 5; % default 6, maximum surface element size
% opt.angbound = 30; % default 30, miminum angle of a surface triangle
% opt.distbound = 0.4; % default 0.5, maximum distance
% % between the center of the surface bounding circle and center of the element bounding sphere
% opt.reratio = 3; % default 3, maximum radius-edge ratio
% maxvol = 10; %100; % target maximum tetrahedral elem volume

try
    [node,elem,face] = cgalv2m(allMask,opt,opt.maxvol);
catch ME
    if isLikelyIso2meshBinaryFailure(ME)
        error('meshByIso2mesh:Iso2meshCgalFailed', ...
            ['iso2mesh could not run its CGAL mesher binary.\n\n', ...
             'On macOS this commonly means cgalmesh.%s is missing, quarantined, ', ...
             'or not marked executable after download. From MATLAB, run:\n\n', ...
             '    nhpulseClearMacQuarantine(''iso2mesh'')\n\n', ...
             'Then restart MATLAB and rerun the walkthrough cell.\n\n', ...
             'Original error:\n%s'], mexext, ME.message);
    end
    rethrow(ME);
end
domainReport = addMeshDomainCounts(domainReport, elem);
domainReport.meshOptions = opt;
domainReport.reportMat = [dirname filesep subjName '_' uniTag '_domainReport.mat'];
save(domainReport.reportMat, 'domainReport');
printDomainReportSummary(domainReport);
node(:,1:3) = node(:,1:3) + 0.5; % then voxel space

for i=1:3, node(:,i) = node(:,i)*imgHdr(1).mat(i,i); end
% Put mesh coordinates into pseudo-world space (voxel space but scaled properly
% using the scaling factors in the header) to avoid mistakes in
% solving. Putting coordinates into pure-world coordinates causes other
% complications. Units of coordinates are mm here. No need to convert into
% meter as voltage output from solver is mV.
% ANDY 2019-03-13

% figure;
% % plotmesh(node(:,1:3),face,elem)
%
% % visualize tissue by tissue
% for i=1:length(maskName)
%     indElem = find(elem(:,5) == i);
%     indFace = find(face(:,4) == i);
%     plotmesh(node(:,1:3),face(indFace,:),elem(indElem,:))
%     title(maskName{i})
%     pause
% end

disp('saving mesh...')
% maskName = {'WHITE','GRAY','CSF','BONE','SKIN','AIR','GEL','ELEC'};
maskName = cell(1,numOfTissue+numOfGel+numOfElec);
maskName(1:numOfTissue) = tissueCfg.names;
for i=1:numOfGel, maskName{numOfTissue+i} = ['GEL' num2str(i)]; end
for i=1:numOfElec, maskName{numOfTissue+numOfGel+i} = ['ELEC' num2str(i)]; end
savemsh(node(:,1:3),elem,[dirname filesep subjName '_' uniTag '.msh'],maskName);
save([dirname filesep subjName '_' uniTag '.mat'],'node','elem','face');
end

function validateGelElectrodeMaskPairs(gelImg, elecImg, numOfGel, ...
        numOfElec, uniTag)
    gelCounts = labelVoxelCounts(gelImg, max(numOfGel, numOfElec));
    elecCounts = labelVoxelCounts(elecImg, max(numOfGel, numOfElec));
    if numOfGel == numOfElec && all(gelCounts(1:numOfGel) > 0) && ...
            all(elecCounts(1:numOfElec) > 0)
        return;
    end

    missingGel = find(gelCounts(1:max(numOfGel, numOfElec)) == 0);
    missingElec = find(elecCounts(1:max(numOfGel, numOfElec)) == 0);
    error('meshByIso2mesh:MissingGelElectrodeMask', ...
        ['ROAST electrode placement wrote inconsistent gel/electrode ', ...
         'masks for tag "%s". ROAST lead-field setup requires one ', ...
         'nonempty gel and one nonempty electrode label per candidate.\n\n', ...
         '  gel labels present: %d\n', ...
         '  electrode labels present: %d\n', ...
         '  missing/empty gel label(s): %s\n', ...
         '  missing/empty electrode label(s): %s\n\n', ...
         'For the synthetic walkthrough, use electrodeModel=''syntheticDemo'' ', ...
         'from the current NHPulse version so the demo uses ROAST''s ', ...
         'stacked disc geometry.'], ...
        uniTag, numOfGel, numOfElec, labelsToText(missingGel), ...
        labelsToText(missingElec));
end

function counts = labelVoxelCounts(values, nLabels)
    values = double(values(:));
    values = values(isfinite(values) & values > 0);
    if isempty(values)
        counts = zeros(max(nLabels, 0), 1);
        return;
    end
    counts = accumarray(values, 1, [max([values; nLabels]), 1], @sum, 0);
end

function report = initializeDomainReport(allMask, tissueCfg, numOfGel, numOfElec)
    labels = (0:double(max(allMask(:))))';
    voxelCounts = accumarray(double(allMask(:)) + 1, 1, ...
        [numel(labels), 1], @sum, 0);
    names = cell(numel(labels), 1);
    for i = 1:numel(labels)
        label = labels(i);
        if label == 0
            names{i} = 'background';
        elseif label <= tissueCfg.numOfTissue
            names{i} = tissueCfg.names{label};
        elseif label <= tissueCfg.numOfTissue + numOfGel
            names{i} = ['GEL' num2str(label - tissueCfg.numOfTissue)];
        else
            names{i} = ['ELEC' num2str(label - tissueCfg.numOfTissue - numOfGel)];
        end
    end

    report = struct();
    report.createdOn = char(datetime('now'));
    report.numOfTissue = tissueCfg.numOfTissue;
    report.numOfGel = double(numOfGel);
    report.numOfElec = double(numOfElec);
    report.labels = labels;
    report.names = names;
    report.voxelCounts = double(voxelCounts);
    report.meshTetCounts = zeros(numel(labels), 1);
    report.meshLabels = [];
    report.missingGelLabels = [];
    report.missingElectrodeLabels = [];
end

function report = addMeshDomainCounts(report, elem)
    if isempty(elem)
        return;
    end
    meshLabels = double(elem(:, 5));
    report.meshLabels = unique(meshLabels(:));
    maxLabel = max([report.labels(:); meshLabels(:)]);
    if maxLabel > max(report.labels)
        extraLabels = ((max(report.labels) + 1):maxLabel)';
        report.labels = [report.labels; extraLabels];
        report.names = [report.names; arrayfun(@(x) ['label' num2str(x)], ...
            extraLabels, 'UniformOutput', false)];
        report.voxelCounts = [report.voxelCounts; zeros(numel(extraLabels), 1)];
        report.meshTetCounts = [report.meshTetCounts; zeros(numel(extraLabels), 1)];
    end
    report.meshTetCounts = accumarray(meshLabels + 1, 1, ...
        [numel(report.labels), 1], @sum, 0);
    gelLabels = report.numOfTissue + (1:report.numOfGel);
    elecLabels = report.numOfTissue + report.numOfGel + (1:report.numOfElec);
    report.missingGelLabels = gelLabels(~ismember(gelLabels, report.meshLabels));
    report.missingElectrodeLabels = elecLabels(~ismember(elecLabels, ...
        report.meshLabels));
end

function printDomainReportSummary(report)
    if ~isempty(report.missingGelLabels)
        fprintf(['Warning: CGAL mesh did not retain gel domain label(s): ', ...
            '%s\n'], labelsToText(report.missingGelLabels));
    end
    if ~isempty(report.missingElectrodeLabels)
        fprintf(['Warning: CGAL mesh did not retain electrode domain ', ...
            'label(s): %s\n'], labelsToText(report.missingElectrodeLabels));
    end
    if ~isempty(report.missingGelLabels) || ...
            ~isempty(report.missingElectrodeLabels)
        fprintf('  Domain diagnostic report: %s\n', report.reportMat);
    end
end

function txt = labelsToText(labels)
    txt = strjoin(arrayfun(@num2str, labels(:)', 'UniformOutput', false), ', ');
end

function tf = isLikelyIso2meshBinaryFailure(ME)
    message = lower(ME.message);
    tf = ~isempty(strfind(message, 'cgalmesh')) || ...
        ~isempty(strfind(message, 'permission denied')) || ...
        ~isempty(strfind(message, 'output file was not found')) || ...
        ~isempty(strfind(message, 'executable'));
end
