function acsPolhemus
% ACSPOLHEMUS Interactive Polhemus FasTrak digitizer interface.
%
% The GUI supports free digitizing, legacy 32-channel EEG sessions, monkey
% implant traces, scalp traces, and electrode QC sessions. Legacy tab-delimited
% text output is still written, but each save also writes MAT/JSON session
% reports with point labels, units, subject/session metadata, and fiducial
% information.

deleteOpenSerialObjects();

%% Settings
legacyStylusOffsetInches = [2.493, -0.010, 0.030]; % factory default, inches
cmPerIn = 2.54;
cmap = [0, 0, 0; 0, 0, 1; 0.85, 0.2, 0.1; 0.1, 0.6, 0.25];
fiducialLabels = {'Nas', 'Lpa', 'Rpa'};
landmarkBullpen = acsMonkeyLandmarkBullpen();
allLandmarkLabels = {landmarkBullpen.label};
capQcReferenceLabels = [fiducialLabels, ...
    {'headpost1', 'headpost2', ...
     'rightChairPoint', 'leftChairPoint', 'topChairPoint'}];

%% State
portInd = 0;
newOrigin = [0, 0, 0];
isAligned = false;
alignmentW = eye(3);
alignmentOffset = [0, 0, 0];
fiducials = [];
softwareStylusCalibration = [];
softwareStylusCalibrationFile = '';
applySoftwareStylusCalibration = false;
prompt = true;
hasLabels = true;
modelFile = '';
labelSource = '';
selectedLandmarkLabels = fiducialLabels;
sessionDefs = sessionDefinitions(fiducialLabels, capQcReferenceLabels, ...
    allLandmarkLabels);
sessionIndex = find(strcmp({sessionDefs.key}, 'monkeyImplants'), 1);
if isempty(sessionIndex), sessionIndex = 1; end
requestedLabels = sessionDefs(sessionIndex).labels;
pointLabels = {};
objectSegments = struct('name', {}, 'startIndex', {}, 'endIndex', {});
currentObjectName = '';
currentObjectStart = [];
currentObjectPointCount = 0;
data = [];
rawData = [];
cdata = [];
lastSession = [];
droppedSampleCount = 0;

serialPortInfo = getSerialPortInfo();
s = cell(1, numel(serialPortInfo.SerialPorts));
portMenu = {};
isChecked = cell(1, numel(serialPortInfo.SerialPorts));
for px = 1:numel(serialPortInfo.SerialPorts)
    s{px} = serial(serialPortInfo.SerialPorts{px}); %#ok<SERIAL,TNMLP>
    switch get(s{px}, 'status')
        case 'open'
            isChecked{px} = 'on';
            portInd = px;
        otherwise
            isChecked{px} = 'off';
    end
end

%% Figure
fh = figure('Units', 'pixels', ...
    'Position', acsPolhemusFigurePosition(), ...
    'CloseRequestFcn', @winclosefcn, ...
    'Menubar', 'none', ...
    'ToolBar', 'figure', ...
    'KeyPressFcn', @winkeyfcn, ...
    'WindowButtonMotionFcn', @voidFn, ...
    'Name', 'ACS Polhemus digitizer', ...
    'NumberTitle', 'off');

plotArea = axes('parent', fh, ...
    'Units', 'normalized', ...
    'Position', [0.05 0.08 0.68 0.84], ...
    'ButtonDownFcn', @paclickonfcn, ...
    'UserData', []);

panel = uipanel('Parent', fh, ...
    'Units', 'normalized', ...
    'Position', [0.76 0.05 0.21 0.9], ...
    'Title', 'Session');

makeSidebarControls(panel);
makeMenus();
refreshSessionControls();
if prompt, showPrompt(); end

%% Callback helpers
    function makeMenus()
        fileMenu = uimenu(fh, 'label', '&File');
        uimenu(fileMenu, ...
            'label', 'Save Session...', ...
            'accelerator', 'Q', ...
            'userdata', 'return', ...
            'callback', @MenuKeyCallback);
        uimenu(fileMenu, ...
            'label', 'Load Labels...', ...
            'callback', @loadLabelsCallback);
        uimenu(fileMenu, ...
            'label', 'Select Model...', ...
            'callback', @selectModelCallback);
        uimenu(fileMenu, ...
            'label', 'Close', ...
            'separator', 'on', ...
            'callback', @closeWindowCallback);

        calibrationMenu = uimenu(fh, 'label', '&Calibration');
        uimenu(calibrationMenu, ...
            'label', 'Load Stylus Offset Calibration...', ...
            'callback', @loadStylusCalibrationCallback);
        uimenu(calibrationMenu, ...
            'label', 'Fit Stylus Offset From Current Samples...', ...
            'callback', @fitStylusCalibrationCallback);
        uimenu(calibrationMenu, ...
            'label', 'Clear Loaded Stylus Calibration', ...
            'callback', @clearStylusCalibrationCallback);

        connectMenu = uimenu(fh, 'label', '&Connect');
        portMenu = cell(1, numel(serialPortInfo.SerialPorts));
        for pxi = 1:numel(serialPortInfo.SerialPorts)
            portMenu{pxi} = uimenu(connectMenu, ...
                'Label', serialPortInfo.SerialPorts{pxi}, ...
                'checked', isChecked{pxi}, ...
                'callback', @ConnectionCallback, ...
                'userdata', s{pxi});
        end
        uimenu(connectMenu, 'Label', 'Simulator', 'callback', @simulatorCallback, ...
            'tag', 'acsPolhemusSimulatorMenu');

        pointMenu = uimenu(fh, 'label', '&Points');
        uimenu(pointMenu, ...
            'label', 'Align reference frame (A)', ...
            'accelerator', 'a', ...
            'userdata', 'a', ...
            'callback', @MenuKeyCallback);
        uimenu(pointMenu, ...
            'label', 'Collapse selected (C)', ...
            'accelerator', 'c', ...
            'userdata', 'c', ...
            'callback', @MenuKeyCallback);
        uimenu(pointMenu, ...
            'label', 'Delete selected (delete)', ...
            'accelerator', 'd', ...
            'userdata', 'delete', ...
            'callback', @MenuKeyCallback);
        uimenu(pointMenu, ...
            'label', 'Start/next traced object (O)', ...
            'accelerator', 'o', ...
            'userdata', 'o', ...
            'callback', @MenuKeyCallback);
        uimenu(pointMenu, ...
            'label', 'Finish current object (F)', ...
            'accelerator', 'f', ...
            'userdata', 'f', ...
            'callback', @MenuKeyCallback);
        uimenu(pointMenu, ...
            'label', 'Toggle labels (T)', ...
            'accelerator', 't', ...
            'userdata', 't', ...
            'callback', @MenuKeyCallback);

        viewMenu = uimenu(fh, 'label', '&View');
        uimenu(viewMenu, ...
            'label', 'Rotate/orbit mode (R)', ...
            'accelerator', 'r', ...
            'userdata', 'rotate', ...
            'callback', @ViewMenuCallback, ...
            'tag', 'acsPolhemusRotateMenu');
        uimenu(viewMenu, ...
            'label', 'Selection mode', ...
            'userdata', 'select', ...
            'callback', @ViewMenuCallback);
        uimenu(viewMenu, ...
            'label', 'View along X', ...
            'userdata', 'x', ...
            'callback', @ViewMenuCallback);
        uimenu(viewMenu, ...
            'label', 'View along Y', ...
            'userdata', 'y', ...
            'callback', @ViewMenuCallback);
        uimenu(viewMenu, ...
            'label', 'View along Z', ...
            'userdata', 'z', ...
            'callback', @ViewMenuCallback);
        uimenu(viewMenu, ...
            'label', 'Reset 3D view', ...
            'userdata', 'reset', ...
            'callback', @ViewMenuCallback);
    end

    function makeSidebarControls(parent)
        y = 0.94;
        dy = 0.065;
        uicontrol(parent, 'Style', 'text', 'Units', 'normalized', ...
            'Position', [0.08 y 0.84 0.035], 'String', 'Session type', ...
            'HorizontalAlignment', 'left');
        y = y - 0.045;
        uicontrol(parent, 'Style', 'popupmenu', 'Units', 'normalized', ...
            'Position', [0.08 y 0.84 0.05], ...
            'String', {sessionDefs.displayName}, ...
            'Value', sessionIndex, ...
            'Callback', @sessionPopupCallback, ...
            'Tag', 'acsPolhemusSessionPopup');

        y = y - dy;
        uicontrol(parent, 'Style', 'text', 'Units', 'normalized', ...
            'Position', [0.08 y 0.84 0.035], 'String', 'Subject ID', ...
            'HorizontalAlignment', 'left');
        y = y - 0.045;
        uicontrol(parent, 'Style', 'edit', 'Units', 'normalized', ...
            'Position', [0.08 y 0.84 0.05], ...
            'String', '', ...
            'BackgroundColor', 'w', ...
            'Tag', 'acsPolhemusSubjectEdit');

        y = y - dy;
        uicontrol(parent, 'Style', 'checkbox', 'Units', 'normalized', ...
            'Position', [0.08 y 0.84 0.045], ...
            'String', 'Prompt next label', ...
            'Value', prompt, ...
            'Callback', @promptCheckboxCallback, ...
            'Tag', 'acsPolhemusPromptCheckbox');
        y = y - 0.05;
        uicontrol(parent, 'Style', 'checkbox', 'Units', 'normalized', ...
            'Position', [0.08 y 0.84 0.045], ...
            'String', 'Show point labels', ...
            'Value', hasLabels, ...
            'Callback', @labelCheckboxCallback, ...
            'Tag', 'acsPolhemusLabelsCheckbox');
        y = y - 0.05;
        uicontrol(parent, 'Style', 'checkbox', 'Units', 'normalized', ...
            'Position', [0.08 y 0.84 0.045], ...
            'String', 'Model overlay', ...
            'Value', false, ...
            'Callback', @modelOverlayCheckboxCallback, ...
            'Tag', 'acsPolhemusModelCheckbox');

        y = y - dy;
        uicontrol(parent, 'Style', 'pushbutton', 'Units', 'normalized', ...
            'Position', [0.08 y 0.84 0.055], ...
            'String', 'Select Landmarks...', ...
            'Callback', @selectLandmarksCallback);
        y = y - 0.065;
        uicontrol(parent, 'Style', 'pushbutton', 'Units', 'normalized', ...
            'Position', [0.08 y 0.84 0.055], ...
            'String', 'Load Labels...', ...
            'Callback', @loadLabelsCallback);
        y = y - 0.065;
        uicontrol(parent, 'Style', 'pushbutton', 'Units', 'normalized', ...
            'Position', [0.08 y 0.84 0.055], ...
            'String', 'Align Fiducials', ...
            'Callback', @alignButtonCallback);
        y = y - 0.065;
        uicontrol(parent, 'Style', 'pushbutton', 'Units', 'normalized', ...
            'Position', [0.08 y 0.84 0.055], ...
            'String', 'Fit Stylus Offset...', ...
            'Callback', @fitStylusCalibrationCallback);
        y = y - 0.065;
        uicontrol(parent, 'Style', 'pushbutton', 'Units', 'normalized', ...
            'Position', [0.08 y 0.84 0.055], ...
            'String', 'Next Object...', ...
            'Callback', @nextObjectButtonCallback);
        y = y - 0.065;
        uicontrol(parent, 'Style', 'pushbutton', 'Units', 'normalized', ...
            'Position', [0.08 y 0.84 0.055], ...
            'String', 'Done Tracing Object', ...
            'Callback', @finishObjectButtonCallback);

        y = y - 0.085; %#ok<NASGU>
        uicontrol(parent, 'Style', 'text', 'Units', 'normalized', ...
            'Position', [0.08 0.09 0.84 0.13], ...
            'String', '', ...
            'HorizontalAlignment', 'left', ...
            'FontSize', 8, ...
            'Tag', 'acsPolhemusStatusText');

        uicontrol(parent, 'Style', 'pushbutton', 'Units', 'normalized', ...
            'Position', [0.08 0.02 0.84 0.055], ...
            'String', 'Save Session...', ...
            'FontWeight', 'bold', ...
            'Callback', @saveButtonCallback);
    end

    function ConnectionCallback(src, ~)
        p = get(src, 'userdata');
        switch get(src, 'checked')
            case 'on'
                set(src, 'checked', 'off');
                try fclose(p); catch, end
            case 'off'
                set(src, 'checked', 'on');
                set(p, 'BaudRate', 115200);
                set(p, 'BytesAvailableFcnCount', 47);
                set(p, 'BytesAvailableFcnMode', 'byte');
                fopen(p);
                set(p, 'BytesAvailableFcn', @bytefcn);
                fprintf(p, '%s', ['e1,1' char(13)]);
                sendStylusOffsetCommand(p);
        end
        simMenu = findobj(fh, 'tag', 'acsPolhemusSimulatorMenu');
        set(simMenu, 'checked', 'off');
        portStatus = false(size(s));
        for pxi = 1:length(s)
            if strcmp(serialPortInfo.SerialPorts{pxi}, get(src, 'Label'))
                portStatus(pxi) = strcmpi('on', get(src, 'checked'));
            else
                try fclose(s{pxi}); catch, end
                set(portMenu{pxi}, 'checked', 'off');
            end
        end
        portInd = find(portStatus, 1);
        if isempty(portInd), portInd = 0; end
        refreshIsChecked();
        refreshPlot();
    end

    function simulatorCallback(src, ~)
        switch get(src, 'checked')
            case 'on'
                set(src, 'checked', 'off');
            case 'off'
                set(src, 'checked', 'on');
        end
        for pxi = 1:length(portMenu)
            set(portMenu{pxi}, 'checked', 'off');
        end
        refreshIsChecked();
        refreshPlot();
    end

    function bytefcn(src, ~)
        x = fgets(src);
        try
            sample = cell2mat(textscan(x, '%*2d %f %f %f %f %f %f'));
        catch ME
            switch ME.identifier
                case 'MATLAB:subsassigndimmismatch'
                    error('ACSpolhemus:dimensionMismatch', ...
                        ['The configuration might have gotten scrambled. ', ...
                         'Try closing the figure, power cycling the FasTrak, ', ...
                         'and relaunching acsPolhemus.']);
                otherwise
                    rethrow(ME);
            end
        end
        if isempty(sample) || size(sample, 2) < 6 || any(~isfinite(sample(:)))
            droppedSampleCount = droppedSampleCount + 1;
            refreshSessionControls();
            return;
        end
        for row = 1:size(sample, 1)
            appendPoint(sample(row, 1:6));
        end
    end

    function appendPoint(sample)
        if isempty(sample) || size(sample, 1) ~= 1 || size(sample, 2) < 6 || ...
                any(~isfinite(sample(1, 1:6)))
            droppedSampleCount = droppedSampleCount + 1;
            refreshSessionControls();
            return;
        end
        sample = sample(1, 1:6);
        rawSample = sample;
        if shouldApplySoftwareStylusCalibration()
            sample = applySoftwareStylusCorrection(sample);
        end
        if isAligned
            sample = applyAlignmentToSample(sample);
        end
        rawData(end + 1, :) = rawSample;
        data(end + 1, :) = sample;
        cdata(end + 1) = 1;
        pointLabels{end + 1, 1} = nextPointLabel(); %#ok<AGROW>
        refreshPlot();
    end

    function sample = applySoftwareStylusCorrection(sample)
        if isempty(sample) || size(sample, 2) < 6
            return;
        end
        convention = softwareStylusCalibration.bestConvention;
        R = acsPolhemusOrientationMatrix(sample(1, 4:6), convention);
        d = double(softwareStylusCalibration.offsetLocalInches(:));
        sample(1, 1:3) = sample(1, 1:3) + (R(:, :, 1) * d)';
    end

    function sample = applyAlignmentToSample(sample)
        if isempty(sample)
            return;
        end
        sample(1, 1:3) = sample(1, 1:3) * alignmentW - alignmentOffset;
    end

    function label = nextPointLabel()
        nextIndex = numel(pointLabels) + 1;
        if nextIndex <= numel(requestedLabels)
            label = requestedLabels{nextIndex};
            return;
        end

        def = sessionDefs(sessionIndex);
        if ~isempty(currentObjectName)
            currentObjectPointCount = currentObjectPointCount + 1;
            label = sprintf('%s_%03d', matlab.lang.makeValidName(currentObjectName), ...
                currentObjectPointCount);
        elseif ~isempty(def.autoTracePrefix)
            label = sprintf('%s_%03d', def.autoTracePrefix, ...
                nextIndex - numel(requestedLabels));
        else
            label = sprintf('point%03d', nextIndex);
        end
    end

    function winclosefcn(src, ~)
        cleanupSerial();
        assignin('base', 'data', data);
        if ~isempty(lastSession)
            assignin('base', 'acsPolhemusLastSession', lastSession);
        elseif ~isempty(data)
            assignin('base', 'acsPolhemusLastSession', buildSessionStruct(''));
        end
        delete(src);
    end

    function MenuKeyCallback(src, ~)
        evt.Key = get(src, 'userdata');
        winkeyfcn([], evt);
    end

    function ViewMenuCallback(src, ~)
        action = get(src, 'userdata');
        switch lower(char(action))
            case 'rotate'
                rotateMenu = findobj(fh, 'tag', 'acsPolhemusRotateMenu');
                setRotateMode(~strcmpi(get(rotateMenu, 'checked'), 'on'));
            case 'select'
                setRotateMode(false);
            case {'x', 'y', 'z', 'reset'}
                setRotateMode(false);
                setCanonicalView(action);
        end
    end

    function sessionPopupCallback(src, ~)
        newIndex = get(src, 'Value');
        if ~isempty(data)
            answer = questdlg( ...
                'Changing session type resets future prompts but keeps captured points. Continue?', ...
                'Change session type', 'Continue', 'Cancel', 'Continue');
            if ~strcmp(answer, 'Continue')
                set(src, 'Value', sessionIndex);
                return;
            end
        end
        sessionIndex = newIndex;
        applySessionDefaultLandmarks();
        resetRequestedLabelsForSession();
        sendStylusOffsetToOpenPort();
        refreshSessionControls();
        refreshPlot();
    end

    function promptCheckboxCallback(src, ~)
        prompt = logical(get(src, 'Value'));
        refreshPlot();
    end

    function labelCheckboxCallback(src, ~)
        hasLabels = logical(get(src, 'Value'));
        refreshPlot();
    end

    function modelOverlayCheckboxCallback(src, ~)
        if logical(get(src, 'Value')) && isempty(modelFile)
            selectModelCallback(src, []);
        end
        refreshSessionControls();
    end

    function selectLandmarksCallback(~, ~)
        labels = {landmarkBullpen.label};
        display = arrayfun(@(x) sprintf('%s - %s', x.label, x.displayName), ...
            landmarkBullpen, 'UniformOutput', false);
        current = find(ismember(labels, selectedLandmarkLabels));
        if isempty(current)
            current = 1:min(3, numel(labels));
        end
        [selection, ok] = listdlg( ...
            'Name', 'Select Polhemus landmarks', ...
            'PromptString', {'Select landmarks to prompt before tracing/electrodes:', ...
                'Use the same labels later for model fiducial selection/registration.'}, ...
            'ListString', display, ...
            'InitialValue', current, ...
            'SelectionMode', 'multiple', ...
            'ListSize', [340 260]);
        if ~ok
            return;
        end
        selectedLandmarkLabels = labels(selection);
        resetRequestedLabelsForSession();
        labelSource = 'landmark bullpen';
        refreshSessionControls();
        refreshPlot();
    end

    function loadLabelsCallback(~, ~)
        [fname, pathName] = uigetfile( ...
            {'*.mat;*.txt;*.tsv;*.csv', 'Layout or label files (*.mat, *.txt, *.tsv, *.csv)'; ...
             '*.*', 'All files'}, ...
            'Load Polhemus labels');
        if isequal(fname, 0)
            return;
        end
        fileName = fullfile(pathName, fname);
        loadedLabels = readLabelsFile(fileName);
        if isempty(loadedLabels)
            errordlg(sprintf('No labels were found in:\n%s', fileName), ...
                'No labels found');
            return;
        end
        requestedLabels = mergeReferenceLabelsWithLabels(loadedLabels, ...
            activeReferenceLabels());
        labelSource = fileName;
        refreshSessionControls();
        refreshPlot();
    end

    function selectModelCallback(~, ~)
        [fname, pathName] = uigetfile( ...
            {'*.mat;*.nii;*.stl;*.txt', 'Model files (*.mat, *.nii, *.stl, *.txt)'; ...
             '*.*', 'All files'}, ...
            'Select model or layout reference');
        if isequal(fname, 0)
            modelCheckbox = findobj(fh, 'tag', 'acsPolhemusModelCheckbox');
            if isgraphics(modelCheckbox)
                set(modelCheckbox, 'Value', ~isempty(modelFile));
            end
            return;
        end
        modelFile = fullfile(pathName, fname);
        refreshSessionControls();
    end

    function alignButtonCallback(~, ~)
        evt.Key = 'a';
        winkeyfcn([], evt);
    end

    function saveButtonCallback(~, ~)
        evt.Key = 'return';
        winkeyfcn([], evt);
    end

    function closeWindowCallback(~, ~)
        if isgraphics(fh)
            winclosefcn(fh, []);
        end
    end

    function nextObjectButtonCallback(~, ~)
        startNextObject();
    end

    function finishObjectButtonCallback(~, ~)
        finishCurrentObject();
    end

    function loadStylusCalibrationCallback(~, ~)
        [fname, pathName] = uigetfile( ...
            {'*.mat;*.json', 'Stylus calibration (*.mat, *.json)'; '*.*', 'All files'}, ...
            'Load Polhemus stylus offset calibration');
        if isequal(fname, 0)
            return;
        end
        calFile = fullfile(pathName, fname);
        try
            cal = readStylusCalibrationFile(calFile);
            validateStylusCalibration(cal);
        catch ME
            errordlg(ME.message, 'Could not load stylus calibration');
            return;
        end
        softwareStylusCalibration = cal;
        softwareStylusCalibrationFile = calFile;
        applySoftwareStylusCalibration = true;
        sendStylusOffsetToOpenPort();
        assignin('base', 'acsPolhemusStylusCalibration', cal);
        refreshSessionControls();
        refreshPlot();
    end

    function fitStylusCalibrationCallback(~, ~)
        if size(rawData, 1) < 6 && size(data, 1) < 6
            errordlg(['Collect at least six samples with the stylus tip fixed ', ...
                'in one divot while swinging the stylus body through varied ', ...
                'orientations. Twenty or more samples is better.'], ...
                'Need calibration samples');
            return;
        end
        session = buildSessionStruct('');
        defaultName = ['polhemusStylusOffset_' datestr(now, 'yyyymmdd_HHMMSS') '.mat'];
        [fname, pathName] = uiputfile( ...
            {'*.mat', 'MAT calibration + JSON sidecar (*.mat)'; ...
             '*.json', 'JSON calibration + MAT sidecar (*.json)'}, ...
            'Save stylus offset calibration', defaultName);
        if isequal(fname, 0)
            outputFile = '';
        else
            outputFile = fullfile(pathName, fname);
        end
        try
            cal = acsCalibratePolhemusStylusOffset(session, ...
                'outputFile', outputFile, ...
                'showFigures', true, ...
                'saveFigures', ~isempty(outputFile), ...
                'verbose', true);
        catch ME
            errordlg(ME.message, 'Stylus calibration failed');
            return;
        end
        softwareStylusCalibration = cal;
        softwareStylusCalibrationFile = outputFile;
        applySoftwareStylusCalibration = true;
        sendStylusOffsetToOpenPort();
        assignin('base', 'acsPolhemusStylusCalibration', cal);
        refreshSessionControls();
        refreshPlot();
    end

    function clearStylusCalibrationCallback(~, ~)
        softwareStylusCalibration = [];
        softwareStylusCalibrationFile = '';
        applySoftwareStylusCalibration = false;
        sendStylusOffsetToOpenPort();
        refreshSessionControls();
    end

    function winkeyfcn(~, evt)
        isSelected = cdata == size(cmap, 1);
        switch lower(evt.Key)
            case 'a'
                alignReferenceFrame();
            case 'c'
                collapseSelectedPoints(isSelected);
            case 'l'
                hasLabels = ~hasLabels;
                labelBox = findobj(fh, 'tag', 'acsPolhemusLabelsCheckbox');
                if isgraphics(labelBox), set(labelBox, 'Value', hasLabels); end
            case 'r'
                rotateMenu = findobj(fh, 'tag', 'acsPolhemusRotateMenu');
                setRotateMode(~strcmpi(get(rotateMenu, 'checked'), 'on'));
            case 'o'
                startNextObject();
            case 'f'
                finishCurrentObject();
            case 'p'
                simMenu = findobj(fh, 'tag', 'acsPolhemusSimulatorMenu');
                if strcmpi('on', get(simMenu, 'checked'))
                    appendPoint([randn(1, 3) * 2, randn(1, 3)]);
                end
            case 't'
                hasLabels = ~hasLabels;
                labelBox = findobj(fh, 'tag', 'acsPolhemusLabelsCheckbox');
                if isgraphics(labelBox), set(labelBox, 'Value', hasLabels); end
            case 'delete'
                deleteSelectedPoints(isSelected);
            case 'escape'
                cdata(:) = 1;
            case 'return'
                saveSessionAndClose();
                return;
            otherwise
                return;
        end
        refreshPlot();
    end

    function alignReferenceFrame()
        if size(data, 1) < 3
            errordlg('Digitize Nas, Lpa, and Rpa before aligning.', ...
                'Need fiducials');
            return;
        end
        if isAligned
            warndlg(['This session is already fiducial-aligned. ', ...
                'Start a new session to recompute the alignment from raw ', ...
                'device coordinates.'], 'Already aligned');
            return;
        end
        origin = data(2, 1:3);
        xPlus = data(3, 1:3) - origin;
        yPlus = data(1, 1:3) - origin;
        proj = xPlus * dot(yPlus, xPlus) ./ norm(xPlus).^2;
        rawOrigin = proj + origin;
        newOrigin = rawOrigin;
        % Keep the FasTrak stream in device coordinates and apply alignment
        % in software so points captured before and after alignment are saved
        % in one consistent coordinate frame.
        if size(data, 1) > 3 && numel(pointLabels) > size(data, 1)
            pointLabels(size(data, 1) + 1:end) = [];
        end
        xPlus = data(3, 1:3) - rawOrigin;
        xPlus = xPlus ./ norm(xPlus);
        yPlus = data(1, 1:3) - rawOrigin;
        yPlus = yPlus - xPlus .* dot(yPlus, xPlus);
        yPlus = yPlus ./ norm(yPlus);
        zPlus = cross(xPlus, yPlus);
        zPlus = zPlus ./ norm(zPlus);
        W = [xPlus(:), yPlus(:), zPlus(:)];
        data(:, 1:3) = data(:, 1:3) * W;
        alignmentW = W;
        alignmentOffset = rawOrigin * W;
        data(:, 1:3) = bsxfun(@minus, data(:, 1:3), alignmentOffset);
        isAligned = true;
        fiducials = data(1:3, 1:3);
    end

    function collapseSelectedPoints(isSelected)
        if any(isSelected)
            first = find(isSelected, 1, 'first');
            firstLabel = pointLabels{first};
            data(first, :) = mean(data(isSelected, :), 1);
            if ~isempty(rawData)
                rawData(first, :) = mean(rawData(isSelected, :), 1);
            end
            pointLabels{first} = firstLabel;
            notFirst = isSelected;
            notFirst(first) = false;
            data(notFirst, :) = [];
            if ~isempty(rawData)
                rawData(notFirst, :) = [];
            end
            cdata(first) = 1;
            cdata(notFirst) = [];
            pointLabels(notFirst) = [];
        end
    end

    function deleteSelectedPoints(isSelected)
        if isempty(data)
            return;
        end
        if ~any(isSelected), isSelected(end) = true; end
        data(isSelected, :) = [];
        if ~isempty(rawData)
            rawData(isSelected, :) = [];
        end
        cdata(isSelected) = [];
        pointLabels(isSelected) = [];
        updateObjectSegmentsAfterDelete();
    end

    function startNextObject()
        if ~sessionDefs(sessionIndex).allowsObjects
            warndlg('Object tracing is mainly intended for implant sessions.', ...
                'Object tracing');
        end
        finishCurrentObject();
        defaultName = sprintf('implant%03d', numel(objectSegments) + 1);
        answer = inputdlg('Object label:', 'Trace object footprint', 1, {defaultName});
        if isempty(answer)
            return;
        end
        currentObjectName = strtrim(answer{1});
        if isempty(currentObjectName)
            currentObjectName = defaultName;
        end
        currentObjectStart = size(data, 1) + 1;
        currentObjectPointCount = 0;
        refreshSessionControls();
        refreshPlot();
    end

    function finishCurrentObject()
        if isempty(currentObjectName)
            return;
        end
        stopIndex = size(data, 1);
        if stopIndex >= currentObjectStart
            objectSegments(end + 1).name = currentObjectName; %#ok<AGROW>
            objectSegments(end).startIndex = currentObjectStart;
            objectSegments(end).endIndex = stopIndex;
        end
        currentObjectName = '';
        currentObjectStart = [];
        currentObjectPointCount = 0;
        refreshSessionControls();
    end

    function paclickonfcn(src, ~)
        if isempty(data), cla(plotArea); return; end
        if figureExplorationModeIsActive()
            return;
        end
        pnt = get(plotArea, 'CurrentPoint');
        finalRect = rbbox;
        pnt2 = get(plotArea, 'CurrentPoint');
        plotData = data(:, 1:3) * cmPerIn;
        if ~any(finalRect(3:4) > 10)
            v = diff(pnt);
            x = bsxfun(@minus, plotData, pnt(1, :));
            x = mat2cell(x, ones(size(x, 1), 1), size(x, 2));
            prod1 = cellfun(@dot, x, repmat({v}, size(x)));
            prod2 = bsxfun(@dot, v, v);
            quot = (prod1 ./ prod2) * v;
            perp = mat2cell(cell2mat(x) - quot, ones(size(quot, 1), 1), size(quot, 2));
            d = cellfun(@norm, perp);
            [r, ~] = find(d == min(d));
        else
            v = [get(plotArea, 'cameratarget'); get(plotArea, 'cameraposition')];
            W = rotationMatrix(diff(v));
            dataproj = plotData * W;
            dataproj(:, 1) = [];
            pnt1proj = pnt * W;
            pnt1proj = pnt1proj(1, [2, 3]);
            pnt2proj = pnt2 * W;
            pnt2proj = pnt2proj(1, [2, 3]);
            gtMat = bsxfun(@ge, dataproj, pnt1proj);
            gtMat2 = bsxfun(@ge, dataproj, pnt2proj);
            xorMat = xor(gtMat, gtMat2);
            r = all(xorMat, 2);
        end
        switch get(gcf, 'selectiontype')
            case 'normal'
                cdata(:) = 1;
            case 'extended'
                % Keep prior selection.
        end
        cdata(r) = (size(cmap, 1) + 1) - cdata(r);
        refreshPlot();
    end

    function tf = figureExplorationModeIsActive()
        tf = false;
        try
            dcm = datacursormode(fh);
            tf = tf || strcmpi(get(dcm, 'Enable'), 'on');
        catch
        end
        try
            zm = zoom(fh);
            tf = tf || strcmpi(get(zm, 'Enable'), 'on');
        catch
        end
        try
            pn = pan(fh);
            tf = tf || strcmpi(get(pn, 'Enable'), 'on');
        catch
        end
        try
            rt = rotate3d(fh);
            tf = tf || strcmpi(get(rt, 'Enable'), 'on');
        catch
        end
    end

    function W = rotationMatrix(boresightVector)
        b = [0, 0, 1; 1, 0, 0];
        v1 = boresightVector;
        b(2, :) = b(2, :) .* sign(v1(2));
        v2 = b(1, :) - ((dot(v1, b(1, :)) / norm(v1).^2)) * v1;
        v3 = b(2, :) - (dot(v2, b(2, :)) / norm(v2).^2) * v2 - ...
            (dot(v1, b(2, :)) / norm(v1).^2) * v1;
        v1 = v1 ./ norm(v1);
        v2 = v2 ./ norm(v2);
        v3 = v3 ./ norm(v3);
        W = [v1', v2', v3'];
    end

    function refreshPlot()
        delete(findobj(plotArea, 'tag', 'acsPolhemus_textLabels'));
        if isempty(data)
            cla(plotArea);
            xlabel(plotArea, 'x (cm)');
            ylabel(plotArea, 'y (cm)');
            zlabel(plotArea, 'z (cm)');
            grid(plotArea, 'on');
            if prompt, showPrompt(); end
            refreshSessionControls();
            return;
        end
        if isempty(fiducials) || size(data, 1) < 3
            isAligned = false;
        end
        keepProps = {'ButtonDownFcn'};
        if size(data, 1) > 3
            keepProps = {'ButtonDownFcn', 'CameraTarget', 'CameraPosition', ...
                'CameraUpVector', 'CameraViewAngle', 'View'};
        end
        axProps = get(plotArea, keepProps);
        plotData = data(:, 1:3) * cmPerIn;
        cla(plotArea);
        scatter3(plotArea, plotData(:, 1), plotData(:, 2), plotData(:, 3), ...
            42, cmap(cdata(:), :), 'filled', ...
            'hittest', 'on', ...
            'ButtonDownFcn', @paclickonfcn);
        xlabel(plotArea, 'x (cm)');
        ylabel(plotArea, 'y (cm)');
        zlabel(plotArea, 'z (cm)');
        colormap(plotArea, cmap);
        grid(plotArea, 'on');
        hold(plotArea, 'on');
        drawObjectSegments(plotData);
        if isAligned && size(fiducials, 1) == 3
            fidCm = fiducials * cmPerIn;
            line(plotArea, fidCm(2:3, 1), fidCm(2:3, 2), fidCm(2:3, 3), ...
                'color', [0 0 1], 'linewidth', 1.5);
            line(plotArea, [0; fidCm(1, 1)], [0; fidCm(1, 2)], ...
                [0; fidCm(1, 3)], 'color', [1 0 0], 'linewidth', 1.5);
            line(plotArea, [0; 0], [0; 0], [0; norm(fidCm(1, 1:3))], ...
                'color', [0 0.5 0], 'linewidth', 1.5);
        end
        if hasLabels
            labelRows = (cdata(:) == size(cmap, 1));
            if ~any(labelRows)
                labelRows = true(size(cdata(:)));
            end
            th = text(plotArea, plotData(labelRows, 1), plotData(labelRows, 2), ...
                plotData(labelRows, 3), pointLabels(labelRows), ...
                'tag', 'acsPolhemus_textLabels', ...
                'verticalalignment', 'bottom', ...
                'fontsize', 8);
            set(th, 'hittest', 'off');
        end
        hold(plotArea, 'off');
        set(plotArea, cell2struct(axProps, keepProps, 2));
        fitAxesToData(plotArea, plotData);
        if prompt, showPrompt(); end
        refreshSessionControls();
    end

    function setRotateMode(tf)
        rotateMenu = findobj(fh, 'tag', 'acsPolhemusRotateMenu');
        try
            hRotate = rotate3d(fh);
            if tf
                set(hRotate, 'Enable', 'on');
                if isgraphics(rotateMenu), set(rotateMenu, 'checked', 'on'); end
            else
                set(hRotate, 'Enable', 'off');
                if isgraphics(rotateMenu), set(rotateMenu, 'checked', 'off'); end
            end
        catch
            if isgraphics(rotateMenu), set(rotateMenu, 'checked', 'off'); end
        end
    end

    function setCanonicalView(axisName)
        switch lower(char(axisName))
            case 'x'
                view(plotArea, [1 0 0]);
            case 'y'
                view(plotArea, [0 1 0]);
            case 'z'
                view(plotArea, [0 0 1]);
            otherwise
                view(plotArea, 3);
        end
        if ~isempty(data)
            fitAxesToData(plotArea, data(:, 1:3) * cmPerIn);
        end
        grid(plotArea, 'on');
    end

    function fitAxesToData(ax, plotData)
        if isempty(plotData) || any(~isfinite(plotData(:)))
            return;
        end
        lo = min(plotData, [], 1);
        hi = max(plotData, [], 1);
        center = (lo + hi) ./ 2;
        span = hi - lo;
        minSpanCm = 0.5;
        span = max(span, minSpanCm);
        pad = max(0.08 .* span, 0.05);
        halfSpan = span ./ 2 + pad;
        if any(~isfinite(center)) || any(~isfinite(halfSpan)) || ...
                any(halfSpan <= 0)
            return;
        end
        set(ax, ...
            'XLim', center(1) + [-halfSpan(1) halfSpan(1)], ...
            'YLim', center(2) + [-halfSpan(2) halfSpan(2)], ...
            'ZLim', center(3) + [-halfSpan(3) halfSpan(3)], ...
            'DataAspectRatio', [1 1 1], ...
            'PlotBoxAspectRatioMode', 'auto', ...
            'ActivePositionProperty', 'position', ...
            'Units', 'normalized', ...
            'Position', [0.05 0.08 0.68 0.84]);
    end

    function drawObjectSegments(plotData)
        for sx = 1:numel(objectSegments)
            rows = objectSegments(sx).startIndex:objectSegments(sx).endIndex;
            rows = rows(rows >= 1 & rows <= size(plotData, 1));
            if numel(rows) >= 2
                line(plotArea, plotData(rows, 1), plotData(rows, 2), ...
                    plotData(rows, 3), 'color', [0.9 0.4 0.1], ...
                    'linewidth', 1.5);
            end
        end
        if ~isempty(currentObjectName) && ~isempty(currentObjectStart)
            rows = currentObjectStart:size(plotData, 1);
            if numel(rows) >= 2
                line(plotArea, plotData(rows, 1), plotData(rows, 2), ...
                    plotData(rows, 3), 'color', [0.5 0 0.7], ...
                    'linewidth', 1.5, 'linestyle', '--');
            end
        end
    end

    function showPrompt()
        if ~any(strcmpi('on', isChecked)) && ~simulatorIsOn()
            title(plotArea, 'Waiting for connection...');
            return;
        end
        nextIndex = size(data, 1) + 1;
        if nextIndex <= numel(requestedLabels)
            title(plotArea, sprintf('Digitize %s', requestedLabels{nextIndex}), ...
                'fontsize', 22);
        elseif ~isempty(currentObjectName)
            title(plotArea, sprintf('Trace %s point %d', currentObjectName, ...
                currentObjectPointCount + 1), 'fontsize', 22);
        elseif sessionDefs(sessionIndex).allowsObjects
            title(plotArea, 'Click Next Object to trace an implant footprint', ...
                'fontsize', 18);
        elseif strcmp(sessionDefs(sessionIndex).key, 'stylusCalibration')
            title(plotArea, sprintf('Swing stylus in one fixed divot: sample %d', ...
                nextIndex), 'fontsize', 18);
        elseif ~isempty(sessionDefs(sessionIndex).autoTracePrefix)
            title(plotArea, sprintf('Digitize %s point %d', ...
                sessionDefs(sessionIndex).autoTracePrefix, ...
                nextIndex - numel(requestedLabels)), 'fontsize', 22);
        else
            title(plotArea, 'Digitizing free points', 'fontsize', 22);
        end
    end

    function tf = simulatorIsOn()
        simMenu = findobj(fh, 'tag', 'acsPolhemusSimulatorMenu');
        tf = isgraphics(simMenu) && strcmpi('on', get(simMenu, 'checked'));
    end

    function refreshSessionControls()
        statusText = findobj(fh, 'tag', 'acsPolhemusStatusText');
        if ~isgraphics(statusText), return; end
        def = sessionDefs(sessionIndex);
        modelText = modelFile;
        if isempty(modelText), modelText = '(none)'; end
        labelText = labelSource;
        if isempty(labelText), labelText = sprintf('%d built-in labels', numel(requestedLabels)); end
        landmarkText = activeLandmarkSummary();
        if isempty(currentObjectName)
            objectText = '(none)';
        else
            objectText = sprintf('%s (%d pts)', currentObjectName, currentObjectPointCount);
        end
        droppedText = droppedSampleStatusText();
        status = sprintf(['Points: %d%s\nSession: %s\nReferences: %d\n', ...
            'Landmarks: %s\nCurrent object: %s\nStylus: %s\nSelection: %s\n', ...
            'Labels: %s\nModel: %s'], ...
            size(data, 1), droppedText, def.displayName, ...
            numel(activeReferenceLabels()), landmarkText, objectText, ...
            stylusStatusText(), selectionStatusText(), ...
            compactPath(labelText), compactPath(modelText));
        set(statusText, 'String', status);
    end

    function resetRequestedLabelsForSession()
        def = sessionDefs(sessionIndex);
        if sessionUsesLandmarkBullpen(def.key)
            requestedLabels = activeReferenceLabels();
        else
            requestedLabels = def.labels;
        end
        labelSource = '';
    end

    function applySessionDefaultLandmarks()
        def = sessionDefs(sessionIndex);
        if strcmp(def.key, 'landmarkAssessment')
            selectedLandmarkLabels = allLandmarkLabels;
        elseif sessionUsesLandmarkBullpen(def.key) && isempty(selectedLandmarkLabels)
            selectedLandmarkLabels = fiducialLabels;
        end
    end

    function labels = activeReferenceLabels()
        def = sessionDefs(sessionIndex);
        if sessionUsesLandmarkBullpen(def.key)
            labels = selectedLandmarkLabels(:)';
        else
            labels = def.referenceLabels;
        end
    end

    function tf = sessionUsesLandmarkBullpen(key)
        tf = any(strcmp(char(key), {'monkeyImplants', 'scalpTrace', ...
            'electrodeQc', 'landmarkAssessment'}));
    end

    function text = activeLandmarkSummary()
        refs = activeReferenceLabels();
        if isempty(refs)
            text = 'none';
        elseif numel(refs) <= 3
            text = strjoin(refs, ', ');
        else
            text = sprintf('%d selected (%s, ...)', numel(refs), ...
                strjoin(refs(1:3), ', '));
        end
    end

    function text = stylusStatusText()
        hw = currentHardwareStylusOffsetInches();
        if shouldApplySoftwareStylusCalibration()
            text = sprintf('software %.1f mm', ...
                norm(softwareStylusCalibration.offsetLocalMm));
        elseif any(abs(hw) > 1e-9)
            text = sprintf('legacy hardware %.1f mm', norm(hw) * 25.4);
        else
            text = 'zero hardware';
        end
    end

    function text = droppedSampleStatusText()
        if droppedSampleCount > 0
            text = sprintf(' (%d dropped)', droppedSampleCount);
        else
            text = '';
        end
    end

    function text = selectionStatusText()
        rows = find(cdata(:) == size(cmap, 1));
        switch numel(rows)
            case 0
                text = 'none';
            case 1
                text = sprintf('%s selected', pointLabels{rows(1)});
            case 2
                coordsCm = data(rows, 1:3) * cmPerIn;
                dCm = norm(coordsCm(2, :) - coordsCm(1, :));
                text = sprintf('%s - %s: %.2f mm (%.3f cm)', ...
                    pointLabels{rows(1)}, pointLabels{rows(2)}, ...
                    dCm * 10, dCm);
            otherwise
                text = sprintf('%d points selected', numel(rows));
        end
    end

    function tf = shouldApplySoftwareStylusCalibration()
        tf = applySoftwareStylusCalibration && ...
            isstruct(softwareStylusCalibration) && ...
            isfield(softwareStylusCalibration, 'offsetLocalInches') && ...
            isfield(softwareStylusCalibration, 'bestConvention');
        if tf && strcmp(sessionDefs(sessionIndex).key, 'stylusCalibration')
            tf = false;
        end
    end

    function hwOffset = currentHardwareStylusOffsetInches()
        if strcmp(sessionDefs(sessionIndex).key, 'stylusCalibration') || ...
                shouldApplySoftwareStylusCalibration()
            hwOffset = [0 0 0];
        else
            hwOffset = legacyStylusOffsetInches;
        end
    end

    function sendStylusOffsetToOpenPort()
        if portInd <= 0 || portInd > numel(s) || isempty(s{portInd})
            return;
        end
        try
            if strcmpi(get(s{portInd}, 'status'), 'open')
                sendStylusOffsetCommand(s{portInd});
            end
        catch
        end
    end

    function sendStylusOffsetCommand(portObj)
        hwOffset = currentHardwareStylusOffsetInches();
        fprintf(portObj, '%s', ['N1,' num2str(hwOffset(1)) ',' ...
            num2str(hwOffset(2)) ',' num2str(hwOffset(3)) char(13)]);
    end

    function saveSessionAndClose()
        finishCurrentObject();
        if isempty(data)
            warndlg('No points have been digitized.', 'No Polhemus data');
            return;
        end
        [fname, pathName] = uiputfile( ...
            {'*.txt', 'Legacy text + MAT/JSON report (*.txt)'; ...
             '*.mat', 'MAT report + text/JSON sidecars (*.mat)'}, ...
            'Save Polhemus session');
        if isequal(fname, 0)
            return;
        end
        [~, stem] = fileparts(fname);
        baseFile = fullfile(pathName, stem);
        session = buildSessionStruct(baseFile);
        lastSession = session;
        writeLegacyText([baseFile '.txt'], session);
        out = session; %#ok<NASGU>
        save([baseFile '.mat'], 'out');
        writeJson([baseFile '.json'], jsonReady(session));
        assignin('base', 'acsPolhemusLastSession', session);
        winclosefcn(fh, []);
    end

    function session = buildSessionStruct(baseFile)
        subjectEdit = findobj(fh, 'tag', 'acsPolhemusSubjectEdit');
        if isgraphics(subjectEdit)
            subjectId = strtrim(get(subjectEdit, 'String'));
        else
            subjectId = '';
        end
        def = sessionDefs(sessionIndex);
        coordsIn = data(:, 1:3);
        coordsCm = coordsIn * cmPerIn;
        if isempty(rawData)
            rawSessionData = data;
        else
            rawSessionData = rawData;
        end
        referenceLabels = activeReferenceLabels();
        session = struct();
        session.createdOn = char(datetime('now'));
        session.subjectId = subjectId;
        session.sessionType = def.key;
        session.sessionDisplayName = def.displayName;
        session.outputBaseFile = baseFile;
        session.modelFile = modelFile;
        session.labelSource = labelSource;
        session.landmarkBullpen = landmarkBullpen;
        session.selectedLandmarkLabels = selectedLandmarkLabels(:);
        session.activeReferenceLabels = referenceLabels(:);
        session.isAligned = isAligned;
        session.coordinateFrame = ternary(isAligned, 'fiducialAligned', 'device');
        session.alignment = struct( ...
            'appliedToFutureSamples', true, ...
            'rotationColumns', alignmentW, ...
            'offsetInches', alignmentOffset, ...
            'note', ['Aligned coordinates are computed as ', ...
                'alignedInches = rawInches * rotationColumns - offsetInches.']);
        session.units = struct('device', 'in', 'coordinates', 'cm');
        session.labels = pointLabels(:);
        session.coordinatesCm = coordsCm;
        session.coordinatesInches = coordsIn;
        session.correctedTipCoordinatesInches = coordsIn;
        session.deviceCoordinatesInches = rawSessionData(:, 1:3);
        session.rawDeviceCoordinatesInches = rawSessionData(:, 1:3);
        if size(data, 2) >= 6
            session.orientationAngles = data(:, 4:6);
        else
            session.orientationAngles = [];
        end
        if size(rawSessionData, 2) >= 6
            session.rawOrientationAngles = rawSessionData(:, 4:6);
        else
            session.rawOrientationAngles = [];
        end
        session.fiducials = fiducialStruct(coordsCm);
        session.referencePoints = referencePointStruct(coordsCm, referenceLabels);
        session.objects = objectsWithLabels();
        session.device = struct('name', 'Polhemus FasTrak', ...
            'legacyStylusOffsetInches', legacyStylusOffsetInches, ...
            'hardwareStylusOffsetInches', currentHardwareStylusOffsetInches(), ...
            'softwareStylusCalibrationFile', softwareStylusCalibrationFile, ...
            'softwareStylusCalibrationActive', shouldApplySoftwareStylusCalibration());
        session.stylusCorrection = stylusCorrectionStruct();
        if strcmp(def.key, 'stylusCalibration') && size(rawSessionData, 1) >= 6
            try
                session.stylusCalibration = acsCalibratePolhemusStylusOffset(session, ...
                    'showFigures', false, 'saveFigures', false, 'verbose', false);
            catch ME
                session.stylusCalibrationError = ME.message;
            end
        end
        session.notes = ['FasTrak coordinates are saved in cm. For electrode ', ...
            'QC sessions, the stylus tip was intended for the superficial ', ...
            'aspect of the holder hole unless noted otherwise. Headpost and ', ...
            'chair points are repeatable session references, not anatomical ', ...
            'MRI fiducials unless separately localized. Stylus calibration ', ...
            'sessions intentionally set the hardware stylus offset to zero ', ...
            'and save raw sensor positions plus orientation angles.'];
    end

    function S = stylusCorrectionStruct()
        S = struct('applied', shouldApplySoftwareStylusCalibration(), ...
            'calibrationFile', softwareStylusCalibrationFile, ...
            'offsetLocalInches', [], ...
            'offsetLocalMm', [], ...
            'bestConvention', []);
        if shouldApplySoftwareStylusCalibration()
            S.offsetLocalInches = softwareStylusCalibration.offsetLocalInches;
            S.offsetLocalMm = softwareStylusCalibration.offsetLocalMm;
            S.bestConvention = softwareStylusCalibration.bestConvention;
        end
    end

    function F = fiducialStruct(coordsCm)
        F = struct('labels', {{}}, 'coordinatesCm', [], 'rows', []);
        if size(coordsCm, 1) < 3
            return;
        end
        labelsLower = normalizePointLabels(pointLabels(:));
        rows = zeros(1, 3);
        for k = 1:3
            aliases = requestedPointAliases(fiducialLabels{k});
            for a = 1:numel(aliases)
                hit = find(strcmp(labelsLower, aliases{a}), 1);
                if ~isempty(hit)
                    rows(k) = hit;
                    break;
                end
            end
        end
        if any(rows == 0) && numel(pointLabels) >= 3 && ...
                sessionDefs(sessionIndex).requiresFiducials
            rows = 1:3;
        end
        if all(rows > 0)
            F.labels = fiducialLabels;
            F.coordinatesCm = coordsCm(rows, :);
            F.rows = rows;
        end
    end

    function R = referencePointStruct(coordsCm, referenceLabels)
        R = struct('labels', {{}}, 'coordinatesCm', [], 'rows', []);
        if isempty(referenceLabels) || isempty(pointLabels)
            return;
        end
        referenceLabels = referenceLabels(:);
        labelsNorm = normalizePointLabels(pointLabels(:));
        rows = zeros(numel(referenceLabels), 1);
        keep = false(numel(referenceLabels), 1);
        for rx = 1:numel(referenceLabels)
            aliases = requestedPointAliases(referenceLabels{rx});
            for ax = 1:numel(aliases)
                hit = find(strcmp(labelsNorm, aliases{ax}), 1);
                if ~isempty(hit)
                    rows(rx) = hit;
                    keep(rx) = true;
                    break;
                end
            end
        end
        if any(keep)
            R.labels = referenceLabels(keep);
            R.coordinatesCm = coordsCm(rows(keep), :);
            R.rows = rows(keep);
        end
    end

    function aliases = requestedPointAliases(label)
        exact = normalizePointLabels({label});
        try
            expanded = normalizePointLabels( ...
                acsMonkeyLandmarkBullpen('aliasesFor', label));
        catch
            expanded = {};
        end
        aliases = unique([exact(:); expanded(:)], 'stable');
    end

    function objects = objectsWithLabels()
        objects = objectSegments;
        for sx = 1:numel(objects)
            rows = objects(sx).startIndex:objects(sx).endIndex;
            rows = rows(rows >= 1 & rows <= numel(pointLabels));
            objects(sx).labels = pointLabels(rows);
            objects(sx).coordinatesCm = data(rows, 1:3) * cmPerIn;
        end
    end

    function writeLegacyText(fileName, session)
        fid = fopen(fileName, 'wt');
        if fid < 0
            error('acsPolhemus:CouldNotWrite', 'Could not write %s', fileName);
        end
        cleaner = onCleanup(@() fclose(fid));
        for dx = 1:numel(session.labels)
            fprintf(fid, '%s\t%.4f\t%.4f\t%.4f\n', session.labels{dx}, ...
                session.coordinatesCm(dx, :));
        end
        clear cleaner;
    end

    function cleanupSerial()
        try
            for sx = 1:numel(s)
                if ~isempty(s{sx})
                    fclose(s{sx});
                    delete(s{sx});
                end
            end
        catch
        end
    end

    function refreshIsChecked()
        for pxi = 1:numel(serialPortInfo.SerialPorts)
            switch get(s{pxi}, 'status')
                case 'open'
                    isChecked{pxi} = 'on';
                    portInd = pxi;
                otherwise
                    isChecked{pxi} = 'off';
            end
        end
    end

    function updateObjectSegmentsAfterDelete()
        objectSegments = struct('name', {}, 'startIndex', {}, 'endIndex', {});
        currentObjectName = '';
        currentObjectStart = [];
        currentObjectPointCount = 0;
    end

    function voidFn(~, ~)
    end

end

function defs = sessionDefinitions(fiducialLabels, capQcReferenceLabels, ...
        allLandmarkLabels)
standardLabels = [fiducialLabels, cellfun(@num2str, num2cell(1:32), ...
    'UniformOutput', false)];
extendedLabels = [standardLabels, {'headpost', 'chamber', 'pedestal'}];
extendedLabels2 = [extendedLabels, ...
    {'rightChairPoint', 'leftChairPoint', 'topChairPoint'}];

defs = struct( ...
    'key', {}, 'displayName', {}, 'labels', {}, ...
    'requiresFiducials', {}, 'referenceLabels', {}, ...
    'allowsObjects', {}, 'autoTracePrefix', {});
defs(end + 1) = makeDef('other', 'Other free digitizing', {}, ...
    false, {}, false, '');
defs(end + 1) = makeDef('stylusCalibration', 'Stylus offset calibration', {}, ...
    false, {}, false, 'divot');
defs(end + 1) = makeDef('landmarkAssessment', 'Landmark assessment', ...
    allLandmarkLabels, true, allLandmarkLabels, false, '');
defs(end + 1) = makeDef('monkeyImplants', 'Monkey implant trace', ...
    fiducialLabels, true, fiducialLabels, true, '');
defs(end + 1) = makeDef('scalpTrace', 'Monkey scalp trace', ...
    fiducialLabels, true, fiducialLabels, false, 'scalp');
defs(end + 1) = makeDef('electrodeQc', 'Cap electrode QC', ...
    capQcReferenceLabels, true, capQcReferenceLabels, false, '');
defs(end + 1) = makeDef('legacy32', 'Legacy EEG 1-32', ...
    standardLabels, true, fiducialLabels, false, '');
defs(end + 1) = makeDef('legacyHardware', 'Legacy EEG + hardware', ...
    extendedLabels, true, fiducialLabels, false, '');
defs(end + 1) = makeDef('legacyHardwareChair', 'Legacy EEG + hardware + chair', ...
    extendedLabels2, true, fiducialLabels, false, '');
end

function def = makeDef(key, displayName, labels, requiresFiducials, ...
        referenceLabels, allowsObjects, autoTracePrefix)
def = struct('key', key, ...
    'displayName', displayName, ...
    'labels', {labels}, ...
    'requiresFiducials', requiresFiducials, ...
    'referenceLabels', {referenceLabels}, ...
    'allowsObjects', allowsObjects, ...
    'autoTracePrefix', autoTracePrefix);
end

function serialPortInfo = getSerialPortInfo()
try
    serialPortInfo = instrhwinfo('serial');
catch
    serialPortInfo = struct('SerialPorts', {{}});
end
end

function deleteOpenSerialObjects()
try
    oldObjects = instrfind; %#ok<INSTRFND>
    if ~isempty(oldObjects)
        delete(oldObjects);
    end
catch
end
end

function labels = readLabelsFile(fileName)
[~, ~, ext] = fileparts(fileName);
switch lower(ext)
    case '.mat'
        S = load(fileName);
        labels = labelsFromMatStruct(S);
    otherwise
        labels = labelsFromText(fileName);
end
labels = labels(:);
labels = labels(~cellfun(@isempty, labels));
end

function labels = normalizeLabelCell(labelsIn)
if isempty(labelsIn)
    labels = {};
elseif iscell(labelsIn)
    labels = cellstr(labelsIn(:));
elseif isstring(labelsIn)
    labels = cellstr(labelsIn(:));
elseif ischar(labelsIn)
    if size(labelsIn, 1) == 1
        labels = {strtrim(labelsIn)};
    else
        labels = cellstr(labelsIn);
    end
else
    labels = cellstr(labelsIn(:));
end
end

function labels = normalizePointLabels(labelsIn)
labels = normalizeLabelCell(labelsIn);
labels = regexprep(labels, '[^A-Za-z0-9]', '');
labels = cellfun(@lower, labels, 'UniformOutput', false);
end

function labels = labelsFromMatStruct(S)
labels = {};
if isfield(S, 'out') && isstruct(S.out)
    labels = labelsFromLayoutStruct(S.out);
end
if isempty(labels)
    names = fieldnames(S);
    for i = 1:numel(names)
        value = S.(names{i});
        if isstruct(value)
            labels = labelsFromLayoutStruct(value);
        elseif iscell(value) || isstring(value) || ischar(value)
            labels = normalizeLabelCell(value);
        end
        if ~isempty(labels), return; end
    end
end
end

function labels = labelsFromLayoutStruct(S)
labels = {};
if isfield(S, 'names') && ~isempty(S.names)
    labels = normalizeLabelCell(S.names);
elseif isfield(S, 'eegNames') && ~isempty(S.eegNames)
    labels = normalizeLabelCell(S.eegNames);
elseif isfield(S, 'tesNames') && ~isempty(S.tesNames)
    labels = normalizeLabelCell(S.tesNames);
end
end

function labels = labelsFromText(fileName)
raw = strtrim(regexp(fileread(fileName), '\r?\n', 'split'));
raw = raw(~cellfun(@isempty, raw));
labels = cell(size(raw));
for i = 1:numel(raw)
    parts = regexp(raw{i}, '[,\t ]+', 'split');
    labels{i} = parts{1};
end
end

function labels = mergeReferenceLabelsWithLabels(labelsIn, referenceLabels)
labels = normalizeLabelCell(labelsIn);
referenceLabels = normalizeLabelCell(referenceLabels);
if isempty(referenceLabels)
    return;
end
labelNorm = normalizePointLabels(labels);
for i = numel(referenceLabels):-1:1
    refNorm = normalizePointLabels(referenceLabels{i});
    if ~any(strcmp(labelNorm, refNorm{1}))
        labels = [referenceLabels(i); labels]; %#ok<AGROW>
        labelNorm = [refNorm; labelNorm]; %#ok<AGROW>
    end
end
end

function cal = readStylusCalibrationFile(fileName)
[~, ~, ext] = fileparts(fileName);
switch lower(ext)
    case '.mat'
        S = load(fileName);
        if isfield(S, 'calibration')
            cal = S.calibration;
        elseif isfield(S, 'out')
            cal = S.out;
        else
            names = fieldnames(S);
            cal = [];
            for i = 1:numel(names)
                if isstruct(S.(names{i})) && isfield(S.(names{i}), 'offsetLocalInches')
                    cal = S.(names{i});
                    break;
                end
            end
            if isempty(cal)
                error('acsPolhemus:NoCalibrationInFile', ...
                    'No stylus calibration struct was found in %s.', fileName);
            end
        end
    case '.json'
        cal = jsondecode(fileread(fileName));
    otherwise
        error('acsPolhemus:BadCalibrationFile', ...
            'Stylus calibration files must be MAT or JSON.');
end
end

function validateStylusCalibration(cal)
needed = {'offsetLocalInches', 'offsetLocalMm', 'bestConvention'};
for i = 1:numel(needed)
    if ~isstruct(cal) || ~isfield(cal, needed{i})
        error('acsPolhemus:InvalidStylusCalibration', ...
            'Stylus calibration is missing %s.', needed{i});
    end
end
offset = double(cal.offsetLocalInches(:));
if numel(offset) ~= 3 || any(~isfinite(offset))
    error('acsPolhemus:InvalidStylusCalibrationOffset', ...
        'Calibration offsetLocalInches must contain three finite values.');
end
bc = cal.bestConvention;
for f = {'order', 'signs', 'multiplyOrder', 'transpose'}
    if ~isfield(bc, f{1})
        error('acsPolhemus:InvalidStylusCalibrationConvention', ...
            'Calibration bestConvention is missing %s.', f{1});
    end
end
end

function pos = acsPolhemusFigurePosition()
desired = [100 80 1180 650];
try
    oldUnits = get(0, 'Units');
    set(0, 'Units', 'pixels');
    cleaner = onCleanup(@() set(0, 'Units', oldUnits));
    screen = get(0, 'ScreenSize');
    clear cleaner;

    margin = 90;
    screenLeft = screen(1);
    screenBottom = screen(2);
    screenWidth = screen(3);
    screenHeight = screen(4);
    maxWidth = max(760, screenWidth - 2 * margin);
    maxHeight = max(520, screenHeight - 2 * margin);
    width = min(desired(3), maxWidth);
    height = min(desired(4), maxHeight);

    x = screenLeft + max(margin, floor((screenWidth - width) / 2));
    y = screenBottom + max(margin, floor((screenHeight - height) / 2));
    x = min(x, screenLeft + screenWidth - width - margin);
    y = min(y, screenBottom + screenHeight - height - margin);
    x = max(screenLeft + 20, x);
    y = max(screenBottom + 40, y);
    pos = [x y width height];
catch
    pos = desired;
end
end

function writeJson(fileName, S)
fid = fopen(fileName, 'wt');
if fid < 0
    error('acsPolhemus:CouldNotWriteJson', 'Could not write %s', fileName);
end
cleaner = onCleanup(@() fclose(fid));
try
    txt = jsonencode(S, 'PrettyPrint', true);
catch
    txt = jsonencode(S);
end
fprintf(fid, '%s', txt);
clear cleaner;
end

function S = jsonReady(S)
if isstruct(S)
    for k = 1:numel(S)
        names = fieldnames(S(k));
        for i = 1:numel(names)
            S(k).(names{i}) = jsonReady(S(k).(names{i}));
        end
    end
elseif iscell(S)
    for i = 1:numel(S)
        S{i} = jsonReady(S{i});
    end
elseif isa(S, 'datetime')
    S = char(S);
elseif isa(S, 'triangulation') || isa(S, 'matlab.ui.Figure')
    S = char(class(S));
end
end

function textOut = compactPath(textIn)
textOut = char(textIn);
if numel(textOut) > 38
    textOut = ['...' textOut(end-34:end)];
end
end

function value = ternary(tf, a, b)
if tf
    value = a;
else
    value = b;
end
end

function out = yesNo(tf)
if tf
    out = 'yes';
else
    out = 'no';
end
end
