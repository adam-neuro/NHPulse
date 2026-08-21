function out = nhpulseInspectRoastLeadFieldDomains(t1FileOrLayout, simulationTag)
% NHPULSEINSPECTROASTLEADFIELDDOMAINS Summarize ROAST gel/electrode domains.
%
% out = nhpulseInspectRoastLeadFieldDomains(t1File, simulationTag) reports
% whether each custom electrode has voxels in ROAST's placed gel/electrode
% masks and tetrahedra in the final iso2mesh/CGAL mesh. This is mainly a
% diagnostic for errors such as "Electrode custom1 was not meshed properly."

    if nargin < 2 || isempty(simulationTag)
        error('nhpulseInspectRoastLeadFieldDomains:MissingInput', ...
            'Provide a T1 file or layout struct and a ROAST simulation tag.');
    end
    [t1File, names] = resolveSource(t1FileOrLayout);
    simulationTag = char(simulationTag);
    [folder, stem] = fileparts(t1File);
    prefix = fullfile(folder, [stem '_' simulationTag]);

    elecFile = [prefix '_mask_elec.nii'];
    gelFile = [prefix '_mask_gel.nii'];
    meshFile = [prefix '.mat'];
    reportFile = [prefix '_domainReport.mat'];

    elecCounts = [];
    gelCounts = [];
    if exist(elecFile, 'file') == 2
        elec = load_untouch_nii(elecFile);
        elecCounts = labelCounts(elec.img);
    end
    if exist(gelFile, 'file') == 2
        gel = load_untouch_nii(gelFile);
        gelCounts = labelCounts(gel.img);
    end

    domainReport = [];
    if exist(reportFile, 'file') == 2
        S = load(reportFile, 'domainReport');
        if isfield(S, 'domainReport')
            domainReport = S.domainReport;
        end
    end

    meshRegionCounts = [];
    if exist(meshFile, 'file') == 2
        M = load(meshFile, 'elem');
        if isfield(M, 'elem') && ~isempty(M.elem)
            meshRegionCounts = labelCounts(M.elem(:, 5));
        end
    end

    numOfTissue = 6;
    numElec = max([numel(elecCounts), numel(gelCounts), numel(names)]);
    if ~isempty(domainReport)
        numOfTissue = domainReport.numOfTissue;
        numElec = max([numElec, domainReport.numOfElec]);
    end
    if isempty(names)
        names = arrayfun(@(i) sprintf('custom%d', i), 1:numElec, ...
            'UniformOutput', false)';
    end
    if numel(names) < numElec
        extra = arrayfun(@(i) sprintf('custom%d', i), ...
            (numel(names) + 1):numElec, 'UniformOutput', false)';
        names = [names(:); extra(:)];
    end

    rows = cell(numElec, 1);
    gelVoxels = zeros(numElec, 1);
    elecVoxels = zeros(numElec, 1);
    gelTets = zeros(numElec, 1);
    elecTets = zeros(numElec, 1);
    for i = 1:numElec
        rows{i} = names{i};
        gelVoxels(i) = countAt(gelCounts, i);
        elecVoxels(i) = countAt(elecCounts, i);
        gelTets(i) = countAt(meshRegionCounts, numOfTissue + i);
        elecTets(i) = countAt(meshRegionCounts, numOfTissue + numElec + i);
        if ~isempty(domainReport)
            gelTets(i) = reportCountAt(domainReport, numOfTissue + i, gelTets(i));
            elecTets(i) = reportCountAt(domainReport, ...
                numOfTissue + numElec + i, elecTets(i));
        end
    end

    out = struct();
    out.t1File = t1File;
    out.simulationTag = simulationTag;
    out.elecFile = elecFile;
    out.gelFile = gelFile;
    out.meshFile = meshFile;
    out.domainReportFile = reportFile;
    out.table = table(rows, gelVoxels, elecVoxels, gelTets, elecTets, ...
        'VariableNames', {'name', 'gelVoxels', 'electrodeVoxels', ...
        'gelTets', 'electrodeTets'});
    out.missingElectrodeVoxelRows = find(elecVoxels == 0);
    out.missingElectrodeTetRows = find(elecTets == 0);
    out.missingGelVoxelRows = find(gelVoxels == 0);
    out.missingGelTetRows = find(gelTets == 0);

    fprintf('\nROAST lead-field domain diagnostic\n');
    fprintf('  tag: %s\n', simulationTag);
    fprintf('  electrode mask: %s\n', existenceText(elecFile));
    fprintf('  gel mask:       %s\n', existenceText(gelFile));
    fprintf('  mesh:           %s\n', existenceText(meshFile));
    fprintf('  domain report:  %s\n', existenceText(reportFile));
    disp(out.table);
    if ~isempty(out.missingElectrodeTetRows)
        fprintf('  Missing electrode tetrahedra: %s\n', ...
            strjoin(rows(out.missingElectrodeTetRows), ', '));
    end
    if ~isempty(out.missingGelTetRows)
        fprintf('  Missing gel tetrahedra: %s\n', ...
            strjoin(rows(out.missingGelTetRows), ', '));
    end
end

function [t1File, names] = resolveSource(source)
    names = {};
    if ischar(source) || isstring(source)
        t1File = char(source);
    elseif isstruct(source)
        if isfield(source, 't1File')
            t1File = char(source.t1File);
        elseif isfield(source, 'roastReady') && isfield(source.roastReady, 't1File')
            t1File = char(source.roastReady.t1File);
        else
            error('nhpulseInspectRoastLeadFieldDomains:BadSource', ...
                'Input struct does not contain t1File or roastReady.t1File.');
        end
        if isfield(source, 'names')
            names = valuesToCellstr(source.names);
        end
    else
        error('nhpulseInspectRoastLeadFieldDomains:BadSource', ...
            'Provide a T1 file or layout struct.');
    end
end

function counts = labelCounts(values)
    values = double(values(:));
    values = values(isfinite(values) & values > 0);
    if isempty(values)
        counts = zeros(0, 1);
        return;
    end
    counts = accumarray(values, 1, [max(values), 1], @sum, 0);
end

function value = countAt(counts, label)
    if isempty(counts) || label < 1 || label > numel(counts)
        value = 0;
    else
        value = counts(label);
    end
end

function value = reportCountAt(report, label, fallback)
    idx = find(report.labels == label, 1);
    if isempty(idx)
        value = fallback;
    else
        value = report.meshTetCounts(idx);
    end
end

function values = valuesToCellstr(values)
    if isempty(values)
        values = {};
    elseif ischar(values)
        values = {values};
    elseif isstring(values)
        values = cellstr(values(:));
    elseif iscell(values)
        values = cellfun(@char, values(:), 'UniformOutput', false);
    else
        error('nhpulseInspectRoastLeadFieldDomains:BadNames', ...
            'Electrode names must be char, string, or cellstr.');
    end
    values = values(:);
end

function txt = existenceText(fileName)
    if exist(fileName, 'file') == 2
        txt = fileName;
    else
        txt = ['missing: ' fileName];
    end
end
