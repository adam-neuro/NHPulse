function out = nhpulseCropDualMaterialPrint(source, varargin)
% NHPULSECROPDUALMATERIALPRINT Export a local PLA/TPE cap test coupon.
%
% out = nhpulseCropDualMaterialPrint(manufacturingReport, ...) reads the
% coordinated final PLA and TPE STL files from an NHPulse manufacturing
% report and crops both with one axis-aligned box. Cut surfaces are closed by
% voxel remeshing so the outputs can be sliced as a small diagnostic print.
%
% Useful forms:
%   nhpulseCropDualMaterialPrint(reportMat, 'electrodeName','customEEG3')
%   nhpulseCropDualMaterialPrint(reportMat, 'centerMm',[20 -15], ...
%       'sizeMm',[35 35])
%   nhpulseCropDualMaterialPrint(tpeStl, 'plaFile',plaStl, ...
%       'cropBoxMin',[0 0 0], 'cropBoxMax',[35 35 25])
%
% Name-value options:
%   tpeFile       : override/inject source TPE STL ['']
%   plaFile       : override/inject source PLA STL ['']
%   electrodeName : center crop on a report electrode ['']
%   centerMm      : crop center, [x y] or [x y z] [[]]
%   sizeMm        : crop size, [x y] (full Z) or [x y z] [[35 35]]
%   cropBoxMin    : explicit lower crop corner [[]]
%   cropBoxMax    : explicit upper crop corner [[]]
%   voxelSizeMm   : watertight remesh spacing [0.5]
%   keepLargest   : retain only largest component per material [false]
%   centerOutput  : move both cropped parts together to XY=0 and bed Z=0 [true]
%   outputDir     : destination folder [beside report/source]
%   tag           : output filename stem [source stem + '_testCrop']
%   force         : overwrite existing outputs [false]
%   showFigures   : show one-axis QC preview [true]
%   saveFigures   : save QC PNG [true]
%   verbose       : print crop details [true]

    if nargin < 1 || isempty(source)
        [name, folder] = uigetfile({'*.mat;*.stl', ...
            'Manufacturing report or TPE STL (*.mat, *.stl)'}, ...
            'Select an NHPulse manufacturing report or TPE STL');
        if isequal(name, 0)
            error('nhpulseCropDualMaterialPrint:Canceled', ...
                'No manufacturing file was selected.');
        end
        source = fullfile(folder, name);
    end
    opts = parseInputs(varargin{:});
    sourceInfo = resolveSources(source, opts);
    TRtpeSource = readStlTriangulation(sourceInfo.tpeFile);
    TRplaSource = readStlTriangulation(sourceInfo.plaFile);
    [boxMin, boxMax, cropCenter] = resolveCropBox(sourceInfo, ...
        TRtpeSource, TRplaSource, opts);

    cropOpts = struct('voxelSize', opts.voxelSizeMm, 'padVox', 2, ...
        'keepLargest', opts.keepLargest, 'closeVox', 0, 'tol', 1e-9);
    if opts.verbose
        fprintf('Cropping coordinated TPE/PLA meshes to:\n');
        fprintf('  min [%g %g %g] mm\n', boxMin);
        fprintf('  max [%g %g %g] mm\n', boxMax);
    end
    TRtpe = cropTriAABB_watertight(TRtpeSource, boxMin, boxMax, cropOpts);
    TRpla = cropTriAABB_watertight(TRplaSource, boxMin, boxMax, cropOpts);
    requireNonempty(TRtpe, 'TPE');
    requireNonempty(TRpla, 'PLA');

    translationMm = [0 0 0];
    if opts.centerOutput
        allPoints = [TRtpe.Points; TRpla.Points];
        lo = min(allPoints, [], 1); hi = max(allPoints, [], 1);
        translationMm = [-mean([lo(1) hi(1)]), ...
            -mean([lo(2) hi(2)]), -lo(3)];
        TRtpe = translateTri(TRtpe, translationMm);
        TRpla = translateTri(TRpla, translationMm);
    end

    if isempty(opts.outputDir)
        opts.outputDir = fullfile(fileparts(sourceInfo.sourceFile), ...
            [sourceInfo.defaultTag '_testCrop']);
    end
    if isempty(opts.tag)
        opts.tag = [sourceInfo.defaultTag '_testCrop'];
    end
    opts.tag = safeTag(opts.tag);
    ensureDir(opts.outputDir);
    files = outputFiles(opts);
    requireWritable(files, opts.force);
    stlwrite_boxsafe(TRpla, files.plaStl);
    stlwrite_boxsafe(TRtpe, files.tpeStl);

    if opts.showFigures || opts.saveFigures
        fig = previewFigure(TRplaSource, TRtpeSource, TRpla, TRtpe, ...
            boxMin, boxMax, translationMm, opts.showFigures);
        if opts.saveFigures, saveFigure(fig, files.previewPng); end
        if ~opts.showFigures, close(fig); end
    end

    out = struct();
    out.schema = 'nhpulse.printerTest';
    out.schemaVersion = 1;
    out.kind = 'dualMaterialCapCrop';
    out.createdOn = char(datetime('now'));
    out.source = sourceInfo;
    out.cropBoxMinMm = boxMin;
    out.cropBoxMaxMm = boxMax;
    out.cropCenterMm = cropCenter;
    out.outputTranslationMm = translationMm;
    out.outputDir = opts.outputDir;
    out.plaStlFile = files.plaStl;
    out.tpeStlFile = files.tpeStl;
    out.qcFigure = files.previewPng;
    out.reportMat = files.reportMat;
    out.meshes = struct('pla', meshStats(TRpla), 'tpe', meshStats(TRtpe));
    save(files.reportMat, 'out', '-v7.3');

    if opts.verbose
        fprintf('\nNHPulse local dual-material cap crop\n');
        fprintf('  PLA: %s\n', files.plaStl);
        fprintf('  TPE: %s\n', files.tpeStl);
    end
    if nargout == 0, clear out; end
end

function opts = parseInputs(varargin)
    p = inputParser;
    p.FunctionName = mfilename;
    addParameter(p, 'tpeFile', '', @isTextScalar);
    addParameter(p, 'plaFile', '', @isTextScalar);
    addParameter(p, 'electrodeName', '', @isTextScalar);
    addParameter(p, 'centerMm', [], @isCenter);
    addParameter(p, 'sizeMm', [35 35], @isSize);
    addParameter(p, 'cropBoxMin', [], @isCorner);
    addParameter(p, 'cropBoxMax', [], @isCorner);
    addParameter(p, 'voxelSizeMm', 0.5, @isPositiveScalar);
    addParameter(p, 'keepLargest', false, @isBoolLike);
    addParameter(p, 'centerOutput', true, @isBoolLike);
    addParameter(p, 'outputDir', '', @isTextScalar);
    addParameter(p, 'tag', '', @isTextScalar);
    addParameter(p, 'force', false, @isBoolLike);
    addParameter(p, 'showFigures', true, @isBoolLike);
    addParameter(p, 'saveFigures', true, @isBoolLike);
    addParameter(p, 'verbose', true, @isBoolLike);
    parse(p, varargin{:});
    opts = p.Results;
    textFields = {'tpeFile','plaFile','electrodeName','outputDir','tag'};
    for i=1:numel(textFields), opts.(textFields{i})=char(opts.(textFields{i})); end
    opts.centerMm = double(opts.centerMm(:)');
    opts.sizeMm = double(opts.sizeMm(:)');
    opts.cropBoxMin = double(opts.cropBoxMin(:)');
    opts.cropBoxMax = double(opts.cropBoxMax(:)');
    opts.voxelSizeMm = double(opts.voxelSizeMm);
    opts.keepLargest = logical(opts.keepLargest);
    opts.centerOutput = logical(opts.centerOutput);
    opts.force = logical(opts.force);
    opts.showFigures = logical(opts.showFigures);
    opts.saveFigures = logical(opts.saveFigures);
    opts.verbose = logical(opts.verbose);
    if xor(isempty(opts.cropBoxMin), isempty(opts.cropBoxMax))
        error('nhpulseCropDualMaterialPrint:IncompleteCropBox', ...
            'Provide both cropBoxMin and cropBoxMax, or neither.');
    end
end

function info = resolveSources(source, opts)
    sourceFile = canonicalPath(char(source));
    if exist(sourceFile, 'file') ~= 2
        error('nhpulseCropDualMaterialPrint:MissingSource', ...
            'Source file not found: %s', sourceFile);
    end
    info = struct('sourceFile', sourceFile, 'tpeFile', opts.tpeFile, ...
        'plaFile', opts.plaFile, 'names', {{}}, ...
        'layoutCoordinatesMm', zeros(0,3), 'defaultTag', 'nhpulse_cap');
    [folder, stem, ext] = fileparts(sourceFile);
    info.defaultTag = regexprep(stem, '(_manufacturing)?_report$', '');
    if strcmpi(ext, '.mat')
        S = load(sourceFile);
        report = firstReport(S);
        if isempty(report)
            error('nhpulseCropDualMaterialPrint:BadReport', ...
                'No manufacturing report was found in %s.', sourceFile);
        end
        if isempty(info.tpeFile), info.tpeFile = getField(report,'tpeStlFile',''); end
        if isempty(info.plaFile), info.plaFile = getField(report,'plaStlFile',''); end
        if isfield(report,'names'), info.names=cellstr(report.names(:)); end
        if isfield(report,'layoutCoordinatesMm')
            info.layoutCoordinatesMm=double(report.layoutCoordinatesMm);
        end
        if isfield(report,'manufacturingTag') && ~isempty(report.manufacturingTag)
            info.defaultTag = char(report.manufacturingTag);
        end
    elseif strcmpi(ext, '.stl')
        if isempty(info.tpeFile), info.tpeFile = sourceFile; end
        if isempty(info.plaFile)
            info.plaFile = regexprep(sourceFile, '_tpe\.stl$', '_pla.stl', ...
                'ignorecase');
        end
    else
        error('nhpulseCropDualMaterialPrint:BadSourceType', ...
            'Source must be a manufacturing MAT report or TPE STL.');
    end
    info.tpeFile = resolveReportedFile(info.tpeFile, folder);
    info.plaFile = resolveReportedFile(info.plaFile, folder);
    if exist(info.tpeFile,'file')~=2 || exist(info.plaFile,'file')~=2
        error('nhpulseCropDualMaterialPrint:MissingMaterialStl', ...
            'Could not resolve both coordinated material STLs. TPE: %s | PLA: %s', ...
            info.tpeFile, info.plaFile);
    end
end

function report = firstReport(S)
    report = [];
    preferred = {'out','outToSave','outSaved','manufacturing'};
    for i=1:numel(preferred)
        if isfield(S,preferred{i}) && isstruct(S.(preferred{i}))
            report=S.(preferred{i}); return;
        end
    end
end

function fileName = resolveReportedFile(fileName, reportFolder)
    fileName = char(fileName);
    if exist(fileName,'file')==2, fileName=canonicalPath(fileName); return; end
    [~,name,ext]=fileparts(fileName);
    candidate=fullfile(reportFolder,[name ext]);
    if exist(candidate,'file')==2, fileName=canonicalPath(candidate); end
end

function [lo, hi, center] = resolveCropBox(info, TRtpe, TRpla, opts)
    allPoints=[TRtpe.Points; TRpla.Points];
    sourceLo=min(allPoints,[],1); sourceHi=max(allPoints,[],1);
    if ~isempty(opts.cropBoxMin)
        lo=opts.cropBoxMin; hi=opts.cropBoxMax; center=(lo+hi)/2;
        if any(hi<=lo), error('nhpulseCropDualMaterialPrint:BadCropBox','cropBoxMax must exceed cropBoxMin.'); end
        return;
    end
    center=opts.centerMm;
    if ~isempty(opts.electrodeName)
        idx=find(strcmpi(info.names,opts.electrodeName),1);
        if isempty(idx) || idx>size(info.layoutCoordinatesMm,1)
            error('nhpulseCropDualMaterialPrint:ElectrodeNotFound', ...
                'Electrode "%s" was not found in the manufacturing report.', ...
                opts.electrodeName);
        end
        center=info.layoutCoordinatesMm(idx,:);
    end
    if isempty(center), center=(sourceLo+sourceHi)/2; end
    if numel(center)==2, center=[center mean([sourceLo(3) sourceHi(3)])]; end
    if numel(opts.sizeMm)==2
        lo=[center(1:2)-opts.sizeMm/2 sourceLo(3)];
        hi=[center(1:2)+opts.sizeMm/2 sourceHi(3)];
    else
        lo=center-opts.sizeMm/2; hi=center+opts.sizeMm/2;
    end
end

function TR = readStlTriangulation(fileName)
    if exist('stlread','file')~=2
        error('nhpulseCropDualMaterialPrint:MissingStlread','stlread is required.');
    end
    try
        raw=stlread(fileName);
        if isa(raw,'triangulation'), TR=raw; return; end
        if isstruct(raw) && isfield(raw,'ConnectivityList')
            TR=triangulation(double(raw.ConnectivityList),double(raw.Points)); return;
        end
        if isstruct(raw) && isfield(raw,'Faces')
            TR=triangulation(double(raw.Faces),double(raw.Vertices)); return;
        end
    catch
    end
    [F,V]=stlread(fileName); TR=triangulation(double(F),double(V));
end

function TR = translateTri(TR, delta), TR=triangulation(TR.ConnectivityList,TR.Points+delta); end
function requireNonempty(TR,label), if isempty(TR)||isempty(TR.ConnectivityList), error('nhpulseCropDualMaterialPrint:EmptyCrop','The crop contains no %s geometry.',label); end, end

function fig = previewFigure(TRplaSource,TRtpeSource,TRpla,TRtpe,lo,hi,delta,visible)
    fig=figure('Name','NHPulse local cap test crop','Color','w', ...
        'Visible',onOff(visible),'Position',centeredPosition([900 700]));
    ax=axes(fig); hold(ax,'on');
    trisurf(TRplaSource,'Parent',ax,'FaceColor',[.75 .75 .77], ...
        'EdgeColor','none','FaceAlpha',.06);
    trisurf(TRtpeSource,'Parent',ax,'FaceColor',[.15 .35 .75], ...
        'EdgeColor','none','FaceAlpha',.08);
    drawBox(ax,lo,hi,[.85 .15 .20]);
    trisurf(translateTri(TRpla,-delta),'Parent',ax,'FaceColor',[.72 .72 .75], ...
        'EdgeColor','none','FaceAlpha',.85);
    trisurf(translateTri(TRtpe,-delta),'Parent',ax,'FaceColor',[.10 .38 .85], ...
        'EdgeColor',[.05 .15 .35],'FaceAlpha',.95);
    hold(ax,'off'); axis(ax,'equal'); axis(ax,'vis3d'); grid(ax,'on'); view(ax,3);
    xlabel(ax,'X (mm)'); ylabel(ax,'Y (mm)'); zlabel(ax,'Z (mm)');
    title(ax,'Source cap, crop box, and retained dual-material geometry');
    camlight(ax,'headlight'); lighting(ax,'gouraud');
end

function drawBox(ax,lo,hi,color)
    V=[lo(1) lo(2) lo(3); hi(1) lo(2) lo(3); hi(1) hi(2) lo(3); lo(1) hi(2) lo(3); lo(1) lo(2) hi(3); hi(1) lo(2) hi(3); hi(1) hi(2) hi(3); lo(1) hi(2) hi(3)];
    E=[1 2;2 3;3 4;4 1;5 6;6 7;7 8;8 5;1 5;2 6;3 7;4 8];
    for i=1:size(E,1), plot3(ax,V(E(i,:),1),V(E(i,:),2),V(E(i,:),3),'-','Color',color,'LineWidth',1.5); end
end

function files=outputFiles(opts), files=struct('plaStl',fullfile(opts.outputDir,[opts.tag '_pla.stl']),'tpeStl',fullfile(opts.outputDir,[opts.tag '_tpe.stl']),'previewPng',fullfile(opts.outputDir,[opts.tag '_preview.png']),'reportMat',fullfile(opts.outputDir,[opts.tag '_report.mat'])); end
function stats=meshStats(TR), stats=struct('vertices',size(TR.Points,1),'faces',size(TR.ConnectivityList,1),'boundsMin',min(TR.Points,[],1),'boundsMax',max(TR.Points,[],1)); end
function saveFigure(fig,fileName)
    try
        exportgraphics(fig,fileName,'Resolution',180);
    catch
        saveas(fig,fileName);
    end
end
function requireWritable(files,force), names=struct2cell(files); for i=1:numel(names), if exist(names{i},'file')==2&&~force, error('nhpulseCropDualMaterialPrint:OutputExists','Output exists; use force=true to overwrite: %s',names{i}); end, end, end
function ensureDir(folder), if exist(folder,'dir')~=7, mkdir(folder); end, end
function value=getField(S,name,defaultValue), if isfield(S,name)&&~isempty(S.(name)), value=S.(name); else, value=defaultValue; end, end
function value=safeTag(value), value=regexprep(char(value),'[^A-Za-z0-9_.-]+','_'); value=regexprep(value,'(^_+|_+$)',''); if isempty(value),value='nhpulse_cap_testCrop';end,end
function value=canonicalPath(value), value=char(value); if usejava('jvm'), value=char(java.io.File(value).getCanonicalPath()); elseif ~isfolder(fileparts(value)), value=fullfile(pwd,value); end, end
function pos=centeredPosition(sz), screen=get(groot,'ScreenSize'); sz=min(sz,[screen(3)-80 screen(4)-120]); pos=[max(20,screen(1)+(screen(3)-sz(1))/2) max(40,screen(2)+(screen(4)-sz(2))/2) sz]; end
function value=onOff(tf), if tf,value='on';else,value='off';end,end
function tf=isTextScalar(x), tf=ischar(x)||(isstring(x)&&isscalar(x)); end
function tf=isCenter(x), tf=isempty(x)||(isnumeric(x)&&any(numel(x)==[2 3])&&all(isfinite(x))); end
function tf=isSize(x), tf=isnumeric(x)&&any(numel(x)==[2 3])&&all(isfinite(x))&&all(x>0); end
function tf=isCorner(x), tf=isempty(x)||(isnumeric(x)&&numel(x)==3&&all(isfinite(x))); end
function tf=isPositiveScalar(x), tf=isnumeric(x)&&isscalar(x)&&isfinite(x)&&x>0; end
function tf=isBoolLike(x), tf=(islogical(x)||isnumeric(x))&&isscalar(x); end
