function files = acsExportFigure(fig, fileStem, varargin)
% ACSEXPORTFIGURE Save a MATLAB figure with reusable QC/poster defaults.
%
% files = acsExportFigure(fig, fileStem) writes fileStem.png.
%
% Name-value options:
%   style      : 'qc' or 'poster' ['qc']
%   formats    : extension or cell array of extensions [{'png'}]
%   widthCm    : figure width in centimeters []
%   heightCm   : figure height in centimeters []
%   fontSize   : base font size []
%   lineWidth  : base line width []
%   resolution : raster export DPI []
%   writeTex   : write a sidecar TeX include snippet [auto]
%   posterText : medium-length poster text; LaTeX markup is allowed ['']
%   posterLabel: optional LaTeX label ['']
%   texRootDir : root for relative graphics paths; absolute paths if empty ['']

    if nargin < 1 || isempty(fig) || ~ishandle(fig)
        error('acsExportFigure:InvalidFigure', ...
            'Provide a valid MATLAB figure handle.');
    end
    if nargin < 2 || isempty(fileStem)
        error('acsExportFigure:MissingFileStem', ...
            'Provide an output file stem or filename.');
    end

    opts = parseInputs(varargin{:});
    opts = applyFigureUserDataDefaults(fig, opts);
    style = lower(opts.style);
    if isempty(opts.resolution)
        if strcmp(style, 'poster')
            opts.resolution = 300;
        else
            opts.resolution = 180;
        end
    end
    if isempty(opts.fontSize) && strcmp(style, 'poster')
        opts.fontSize = 11;
    end
    if isempty(opts.lineWidth) && strcmp(style, 'poster')
        opts.lineWidth = 1.1;
    end

    [folder, stem, ext] = fileparts(char(fileStem));
    if isempty(folder)
        folder = pwd;
    end
    if ~isempty(ext) && isempty(opts.formats)
        opts.formats = {ext(2:end)};
    end
    if isempty(opts.formats)
        opts.formats = {'png'};
    end
    ensureDir(folder);

    applyFigureStyle(fig, opts);

    files = cell(numel(opts.formats), 1);
    for i = 1:numel(opts.formats)
        fmt = lower(stripDot(opts.formats{i}));
        outFile = fullfile(folder, [stem '.' fmt]);
        switch fmt
            case {'png', 'tif', 'tiff', 'jpg', 'jpeg'}
                exportgraphics(fig, outFile, ...
                    'Resolution', opts.resolution, ...
                    'BackgroundColor', 'white');
            case 'pdf'
                exportgraphics(fig, outFile, ...
                    'ContentType', 'vector', ...
                    'BackgroundColor', 'white');
            case 'fig'
                savefig(fig, outFile, 'compact');
            otherwise
                saveas(fig, outFile);
        end
        files{i} = outFile;
    end

    texFile = maybeWriteTexSnippet(files, folder, stem, opts);
    if ~isempty(texFile)
        files{end + 1, 1} = texFile;
    end
end

function opts = parseInputs(varargin)
    if numel(varargin) == 1 && isstruct(varargin{1})
        varargin = structToNameValue(varargin{1});
    elseif numel(varargin) >= 1 && isstruct(varargin{1})
        varargin = [structToNameValue(varargin{1}) varargin(2:end)];
    end

    p = inputParser;
    p.FunctionName = 'acsExportFigure';
    addParameter(p, 'style', 'qc', @(x) ischar(x) || isstring(x));
    addParameter(p, 'formats', {'png'}, @isFormatList);
    addParameter(p, 'widthCm', [], @(x) isempty(x) || isPositiveScalar(x));
    addParameter(p, 'heightCm', [], @(x) isempty(x) || isPositiveScalar(x));
    addParameter(p, 'fontSize', [], @(x) isempty(x) || isPositiveScalar(x));
    addParameter(p, 'lineWidth', [], @(x) isempty(x) || isPositiveScalar(x));
    addParameter(p, 'resolution', [], @(x) isempty(x) || isPositiveScalar(x));
    addParameter(p, 'writeTex', [], @(x) isempty(x) || isBoolLike(x));
    addParameter(p, 'posterText', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'posterLabel', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'texFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'texRootDir', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'texGraphicsFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'texGraphicsWidth', '\linewidth', @(x) ischar(x) || isstring(x));
    addParameter(p, 'texTextSize', '\large', @(x) ischar(x) || isstring(x));
    addParameter(p, 'texUseFigureEnv', true, @isBoolLike);
    parse(p, varargin{:});
    opts = p.Results;
    opts.style = char(opts.style);
    opts.formats = normalizeFormats(opts.formats);
    opts.posterText = char(opts.posterText);
    opts.posterLabel = char(opts.posterLabel);
    opts.texFile = char(opts.texFile);
    opts.texRootDir = char(opts.texRootDir);
    opts.texGraphicsFile = char(opts.texGraphicsFile);
    opts.texGraphicsWidth = char(opts.texGraphicsWidth);
    opts.texTextSize = char(opts.texTextSize);
    opts.texUseFigureEnv = logical(opts.texUseFigureEnv);
end

function applyFigureStyle(fig, opts)
    set(fig, 'Color', 'w', 'InvertHardcopy', 'off');
    if ~isempty(opts.widthCm) || ~isempty(opts.heightCm)
        oldUnits = get(fig, 'Units');
        set(fig, 'Units', 'centimeters');
        pos = get(fig, 'Position');
        if ~isempty(opts.widthCm)
            pos(3) = opts.widthCm;
        end
        if ~isempty(opts.heightCm)
            pos(4) = opts.heightCm;
        end
        set(fig, 'Position', pos);
        set(fig, 'Units', oldUnits);
    end
    set(fig, 'PaperPositionMode', 'auto');

    if ~isempty(opts.fontSize)
        h = findall(fig, '-property', 'FontSize');
        for i = 1:numel(h)
            try
                set(h(i), 'FontSize', opts.fontSize);
            catch
            end
        end
    end
    if ~isempty(opts.lineWidth)
        h = findall(fig, '-property', 'LineWidth');
        for i = 1:numel(h)
            try
                set(h(i), 'LineWidth', opts.lineWidth);
            catch
            end
        end
    end
end

function opts = applyFigureUserDataDefaults(fig, opts)
    try
        ud = get(fig, 'UserData');
    catch
        ud = [];
    end
    if ~isstruct(ud)
        return;
    end

    poster = ud;
    if isfield(ud, 'poster') && isstruct(ud.poster)
        poster = ud.poster;
    end

    opts.posterText = defaultFromStruct(opts.posterText, poster, 'posterText');
    opts.posterLabel = defaultFromStruct(opts.posterLabel, poster, 'posterLabel');
    opts.texFile = defaultFromStruct(opts.texFile, poster, 'texFile');
    opts.texRootDir = defaultFromStruct(opts.texRootDir, poster, 'texRootDir');
    opts.texGraphicsFile = defaultFromStruct( ...
        opts.texGraphicsFile, poster, 'texGraphicsFile');
    opts.texGraphicsWidth = defaultFromStruct( ...
        opts.texGraphicsWidth, poster, 'texGraphicsWidth');
    opts.texTextSize = defaultFromStruct(opts.texTextSize, poster, 'texTextSize');
    if isempty(opts.writeTex) && isfield(poster, 'writeTex')
        opts.writeTex = logical(poster.writeTex);
    end
end

function value = defaultFromStruct(value, S, fieldName)
    if isempty(value) && isfield(S, fieldName) && ~isempty(S.(fieldName))
        value = char(S.(fieldName));
    end
end

function texFile = maybeWriteTexSnippet(files, folder, stem, opts)
    texFile = '';
    writeTex = opts.writeTex;
    if isempty(writeTex)
        writeTex = strcmpi(opts.style, 'poster') && ~isempty(opts.posterText);
    end
    if ~writeTex
        return;
    end

    graphicFile = opts.texGraphicsFile;
    if isempty(graphicFile)
        graphicFile = chooseGraphicsFile(files);
    end
    if isempty(graphicFile)
        warning('acsExportFigure:NoTexGraphic', ...
            'Could not write TeX snippet because no exported graphics file was available.');
        return;
    end

    texFile = opts.texFile;
    if isempty(texFile)
        texFile = fullfile(folder, [stem '.tex']);
    end
    ensureDir(fileparts(texFile));

    texGraphicPath = texPath(graphicFile, opts.texRootDir);
    fid = fopen(texFile, 'w');
    if fid == -1
        error('acsExportFigure:CannotWriteTex', ...
            'Could not write TeX figure snippet: %s', texFile);
    end
    cleaner = onCleanup(@() fclose(fid));

    fprintf(fid, '%% Auto-generated by acsExportFigure. Edit posterText in the MATLAB caller and rerun.\n');
    if opts.texUseFigureEnv
        fprintf(fid, '\\begin{figure}\n');
        fprintf(fid, '  \\centering\n');
    else
        fprintf(fid, '\\centering\n');
    end
    fprintf(fid, '  \\includegraphics[width=%s]{%s}\n', ...
        opts.texGraphicsWidth, texGraphicPath);
    if ~isempty(opts.posterText)
        fprintf(fid, '  \\par\\vspace{0.35em}\n');
        fprintf(fid, '  {%s %s}\n', opts.texTextSize, opts.posterText);
    end
    if ~isempty(opts.posterLabel)
        fprintf(fid, '  \\label{%s}\n', opts.posterLabel);
    end
    if opts.texUseFigureEnv
        fprintf(fid, '\\end{figure}\n');
    end
    clear cleaner;
end

function graphicFile = chooseGraphicsFile(files)
    graphicFile = '';
    if isempty(files)
        return;
    end
    preferred = {'pdf', 'png', 'jpg', 'jpeg', 'tif', 'tiff'};
    exts = cell(size(files));
    for i = 1:numel(files)
        [~, ~, ext] = fileparts(files{i});
        exts{i} = lower(stripDot(ext));
    end
    for p = 1:numel(preferred)
        idx = find(strcmp(exts, preferred{p}), 1, 'first');
        if ~isempty(idx)
            graphicFile = files{idx};
            return;
        end
    end
end

function pathOut = texPath(fileName, rootDir)
    fileName = char(fileName);
    rootDir = char(rootDir);
    if ~isempty(rootDir)
        rel = relativePath(fileName, rootDir);
        if ~isempty(rel)
            fileName = rel;
        end
    end
    pathOut = strrep(fileName, '\', '/');
end

function rel = relativePath(fileName, rootDir)
    rel = '';
    fileName = char(fileName);
    rootDir = char(rootDir);
    if isempty(fileName) || isempty(rootDir)
        return;
    end
    try
        rootDir = char(java.io.File(rootDir).getCanonicalPath());
        fileName = char(java.io.File(fileName).getCanonicalPath());
    catch
        rootDir = char(rootDir);
        fileName = char(fileName);
    end
    rootWithSep = rootDir;
    if ~endsWith(rootWithSep, filesep)
        rootWithSep = [rootWithSep filesep];
    end
    if startsWith(lower(fileName), lower(rootWithSep))
        rel = fileName(numel(rootWithSep) + 1:end);
    end
end

function tf = isFormatList(x)
    tf = ischar(x) || isstring(x) || iscellstr(x);
end

function args = structToNameValue(S)
    names = fieldnames(S);
    args = cell(1, 2 * numel(names));
    for i = 1:numel(names)
        args{2 * i - 1} = names{i};
        args{2 * i} = S.(names{i});
    end
end

function tf = isBoolLike(x)
    tf = (islogical(x) || isnumeric(x)) && isscalar(x);
end

function formats = normalizeFormats(value)
    if isempty(value)
        formats = {};
    elseif ischar(value) || isstring(value)
        formats = cellstr(value);
    else
        formats = value(:);
    end
    for i = 1:numel(formats)
        formats{i} = char(formats{i});
    end
end

function value = stripDot(value)
    value = char(value);
    if startsWith(value, '.')
        value = value(2:end);
    end
end

function tf = isPositiveScalar(x)
    tf = isnumeric(x) && isscalar(x) && isfinite(x) && x > 0;
end

function ensureDir(folder)
    if ~isempty(folder) && exist(folder, 'dir') ~= 7
        mkdir(folder);
    end
end
