function app = nhpulseApp(varargin)
% NHPULSEAPP Open the manifest-backed NHPulse application shell.
%
% app = nhpulseApp() opens the current folder. nhpulseApp(projectRoot)
% opens a specific output/project root. The shell does not replace existing
% specialized tools; it selects a run, reports artifact state, and launches
% those tools with explicit manifest-backed inputs.
%
% Name-value options:
%   projectRoot   : project/output root [pwd]
%   verifyContent : recompute artifact fingerprints while refreshing [true]
%   visible       : 'on' or 'off' ['on']

% The returned struct exposes UI handles for testing and automation. Runtime
% state is stored on app.Figure.UserData rather than in the base workspace.

    [projectRoot, opts] = parseInputs(varargin{:});
    workflow = workflowDefinitions();

    fig = uifigure('Name', 'NHPulse Project', 'Color', [0.97 0.97 0.97], ...
        'Position', centeredPosition([1240 760]), 'Visible', opts.visible);
    root = uigridlayout(fig, [3 2]);
    root.RowHeight = {48, '1x', 34};
    root.ColumnWidth = {300, '1x'};
    root.Padding = [12 12 12 10];
    root.RowSpacing = 8;
    root.ColumnSpacing = 10;

    projectBar = uigridlayout(root, [1 6]);
    projectBar.Layout.Row = 1;
    projectBar.Layout.Column = [1 2];
    projectBar.ColumnWidth = {58, '1x', 78, 86, 82, 104};
    projectBar.Padding = [0 0 0 0];
    projectBar.ColumnSpacing = 6;
    uilabel(projectBar, 'Text', 'Project', 'FontWeight', 'bold');
    projectField = uieditfield(projectBar, 'text', 'Value', projectRoot, ...
        'Tooltip', 'Folder containing manifests and NHPulse outputs');
    browseButton = uibutton(projectBar, 'push', 'Text', 'Browse...', ...
        'ButtonPushedFcn', @onBrowseProject);
    openButton = uibutton(projectBar, 'push', 'Text', 'Open', ...
        'ButtonPushedFcn', @onOpenProject);
    refreshButton = uibutton(projectBar, 'push', 'Text', 'Refresh', ...
        'ButtonPushedFcn', @onRefresh);
    folderButton = uibutton(projectBar, 'push', 'Text', 'Open folder', ...
        'ButtonPushedFcn', @onOpenProjectFolder);

    navigationPanel = uipanel(root, 'Title', 'Workflow');
    navigationPanel.Layout.Row = 2;
    navigationPanel.Layout.Column = 1;
    navigation = uigridlayout(navigationPanel, [8 1]);
    navigation.RowHeight = {20, 30, 20, 30, 20, '1x', 112, 36};
    navigation.Padding = [10 8 10 10];
    navigation.RowSpacing = 5;
    uilabel(navigation, 'Text', 'Subject', 'FontWeight', 'bold');
    subjectDropDown = uidropdown(navigation, 'Items', {'All subjects'}, ...
        'ValueChangedFcn', @onSubjectChanged);
    uilabel(navigation, 'Text', 'Run', 'FontWeight', 'bold');
    runDropDown = uidropdown(navigation, 'Items', {'No registered runs'}, ...
        'ValueChangedFcn', @onRunChanged);
    uilabel(navigation, 'Text', 'Stage', 'FontWeight', 'bold');
    workflowList = uilistbox(navigation, ...
        'Items', {workflow.name}, 'Value', workflow(1).name, ...
        'ValueChangedFcn', @onWorkflowChanged);
    objectiveArea = uitextarea(navigation, 'Editable', 'off', ...
        'Value', {workflow(1).description}, ...
        'BackgroundColor', [0.98 0.98 0.98]);
    launchButton = uibutton(navigation, 'push', 'Text', 'Select a run', ...
        'Enable', 'off', 'ButtonPushedFcn', @onLaunchStage);

    artifactPanel = uipanel(root, 'Title', 'Artifacts');
    artifactPanel.Layout.Row = 2;
    artifactPanel.Layout.Column = 2;
    artifactGrid = uigridlayout(artifactPanel, [3 1]);
    artifactGrid.RowHeight = {30, '1x', 38};
    artifactGrid.Padding = [10 8 10 10];
    summaryLabel = uilabel(artifactGrid, 'Text', 'Open a project to begin.', ...
        'FontWeight', 'bold');
    artifactTable = uitable(artifactGrid, 'Data', emptyArtifactTable(), ...
        'ColumnEditable', false, ...
        'ColumnWidth', {105, 155, 230, 100, 'auto'}, ...
        'CellSelectionCallback', @onArtifactSelected);
    artifactActions = uigridlayout(artifactGrid, [1 4]);
    artifactActions.ColumnWidth = {150, 150, 180, '1x'};
    artifactActions.Padding = [0 0 0 0];
    inspectButton = uibutton(artifactActions, 'push', ...
        'Text', 'Inspect selected', 'Enable', 'off', ...
        'ButtonPushedFcn', @onInspectArtifact);
    artifactFolderButton = uibutton(artifactActions, 'push', ...
        'Text', 'Open file folder', 'Enable', 'off', ...
        'ButtonPushedFcn', @onOpenArtifactFolder);
    importButton = uibutton(artifactActions, 'push', ...
        'Text', 'Import existing outputs', 'Enable', 'off', ...
        'ButtonPushedFcn', @onImportLegacy);
    selectedPathLabel = uilabel(artifactActions, 'Text', '', ...
        'HorizontalAlignment', 'right');

    statusLabel = uilabel(root, 'Text', 'Ready', ...
        'FontColor', [0.25 0.25 0.25]);
    statusLabel.Layout.Row = 3;
    statusLabel.Layout.Column = [1 2];

    state = struct('options', opts, 'project', [], 'workflow', workflow, ...
        'runMap', zeros(0, 1), 'selectedArtifactRow', [], ...
        'artifactRows', repmat(emptyArtifact(), 0, 1));
    fig.UserData = state;

    app = struct('Figure', fig, 'ProjectField', projectField, ...
        'SubjectDropDown', subjectDropDown, 'RunDropDown', runDropDown, ...
        'WorkflowList', workflowList, 'ArtifactTable', artifactTable, ...
        'LaunchButton', launchButton, 'RefreshButton', refreshButton, ...
        'ImportButton', importButton, 'StatusLabel', statusLabel);
    refreshProject(false);

    function onBrowseProject(~, ~)
        selected = uigetdir(projectField.Value, 'Select NHPulse project root');
        if isequal(selected, 0), return; end
        projectField.Value = selected;
        refreshProject(true);
    end

    function onOpenProject(~, ~)
        refreshProject(true);
    end

    function onRefresh(~, ~)
        refreshProject(false);
    end

    function refreshProject(showErrors)
        setBusy(true, 'Reading project manifests and artifact status...');
        cleanup = onCleanup(@() setBusy(false, 'Ready'));
        try
            project = nhpulseOpenProject(projectField.Value, ...
                'verifyContent', opts.verifyContent, ...
                'discoverLegacy', true, 'verbose', false);
            projectField.Value = project.projectRoot;
            state = fig.UserData;
            state.project = project;
            state.selectedArtifactRow = [];
            fig.UserData = state;
            updateSubjectSelector();
            updateRunSelector();
            updateArtifactTable();
            updateWorkflow();
            updateSummary();
            setStatus(sprintf('Opened %s', project.projectRoot));
        catch ME
            clearProjectDisplay();
            if showErrors && strcmp(fig.Visible, 'on')
                uialert(fig, ME.message, 'Could not open project');
            else
                setStatus(['Open failed: ' ME.message]);
            end
        end
        clear cleanup
    end

    function updateSubjectSelector()
        state = fig.UserData;
        subjects = cell(numel(state.project.runs), 1);
        for i = 1:numel(state.project.runs)
            subjects{i} = runSubject(state.project.runs(i));
        end
        legacySubjects = arrayfun(@legacySubject, ...
            state.project.legacyArtifacts, 'UniformOutput', false);
        subjects = [subjects; legacySubjects(:)];
        subjects = subjects(~strcmp(subjects, 'Unspecified'));
        subjects = unique(subjects, 'stable');
        subjectDropDown.Items = [{'All subjects'}; subjects(:)];
        subjectDropDown.Value = 'All subjects';
    end

    function onSubjectChanged(~, ~)
        updateRunSelector();
        updateArtifactTable();
        updateWorkflow();
        updateSummary();
    end

    function updateRunSelector()
        state = fig.UserData;
        indices = (1:numel(state.project.runs)).';
        if ~strcmp(subjectDropDown.Value, 'All subjects')
            keep = arrayfun(@(x) strcmp(runSubject(x), ...
                subjectDropDown.Value), state.project.runs);
            indices = indices(keep(:));
        end
        legacy = filteredLegacyArtifacts();
        if ~isempty(legacy)
            indices(end + 1, 1) = 0;
        end
        state.runMap = indices;
        fig.UserData = state;
        if isempty(indices)
            runDropDown.Items = {'No registered runs'};
            runDropDown.Value = 'No registered runs';
            runDropDown.Enable = 'off';
            return;
        end
        labels = cell(numel(indices), 1);
        for i = 1:numel(indices)
            if indices(i) == 0
                labels{i} = sprintf('Unregistered outputs  [%d files]', ...
                    numel(legacy));
            else
                run = state.project.runs(indices(i));
                labels{i} = sprintf('%s  [%s]', run.runLabel, run.runId);
            end
        end
        runDropDown.Items = labels;
        runDropDown.Value = labels{1};
        runDropDown.Enable = 'on';
    end

    function onRunChanged(~, ~)
        state = fig.UserData;
        state.selectedArtifactRow = [];
        fig.UserData = state;
        updateArtifactTable();
        updateWorkflow();
        updateSummary();
    end

    function run = selectedRun()
        state = fig.UserData;
        run = [];
        if isempty(state.project) || isempty(state.runMap) || ...
                strcmp(runDropDown.Value, 'No registered runs')
            return;
        end
        item = find(strcmp(runDropDown.Items, runDropDown.Value), 1);
        if isempty(item) || item > numel(state.runMap), return; end
        if state.runMap(item) == 0, return; end
        run = state.project.runs(state.runMap(item));
    end

    function tf = isLegacySelection()
        state = fig.UserData;
        tf = false;
        if isempty(state.runMap), return; end
        item = find(strcmp(runDropDown.Items, runDropDown.Value), 1);
        tf = ~isempty(item) && item <= numel(state.runMap) && ...
            state.runMap(item) == 0;
    end

    function context = selectedContext()
        run = selectedRun();
        if isempty(run)
            error('nhpulseApp:NoRunSelected', ...
                'Select a registered run before launching a stage.');
        end
        context = nhpulseCreateProjectContext(run.manifest.projectRoot, run.runId, ...
            'runLabel', run.runLabel, 'metadata', run.manifest.metadata);
    end

    function updateArtifactTable()
        state = fig.UserData;
        run = selectedRun();
        rows = repmat(emptyArtifact(), 0, 1);
        if ~isempty(run)
            mask = strcmp({state.project.artifacts.runId}, run.runId) & ...
                pathMask({state.project.artifacts.manifestFile}, ...
                run.manifestFile);
            rows = state.project.artifacts(mask);
        elseif isLegacySelection()
            rows = legacyRows(filteredLegacyArtifacts());
        end
        state.artifactRows = rows;
        state.selectedArtifactRow = [];
        fig.UserData = state;
        if isempty(rows)
            artifactTable.Data = emptyArtifactTable();
        else
            data = cell(numel(rows), 5);
            for i = 1:numel(rows)
                data(i, :) = {rows(i).stage, shortType(rows(i).type), ...
                    rows(i).label, rows(i).status, rows(i).path};
            end
            artifactTable.Data = cell2table(data, 'VariableNames', ...
                {'Stage', 'Type', 'Label', 'Status', 'Path'});
        end
        inspectButton.Enable = 'off';
        artifactFolderButton.Enable = 'off';
        importButton.Enable = onOff(isLegacySelection() && ~isempty(rows));
        selectedPathLabel.Text = '';
        styleArtifactRows(rows);
    end

    function styleArtifactRows(rows)
        removeStyle(artifactTable);
        for i = 1:numel(rows)
            switch rows(i).status
                case 'current'
                    color = [0.90 0.97 0.91];
                case {'stale', 'incompatible'}
                    color = [1.00 0.94 0.82];
                case 'missing'
                    color = [1.00 0.88 0.88];
                case 'unregistered'
                    color = [0.91 0.94 0.98];
                otherwise
                    continue;
            end
            addStyle(artifactTable, uistyle('BackgroundColor', color), ...
                'row', i);
        end
    end

    function onArtifactSelected(~, event)
        state = fig.UserData;
        if isempty(event.Indices)
            state.selectedArtifactRow = [];
            inspectButton.Enable = 'off';
            artifactFolderButton.Enable = 'off';
            selectedPathLabel.Text = '';
        else
            state.selectedArtifactRow = event.Indices(1, 1);
            artifact = state.artifactRows(state.selectedArtifactRow);
            inspectButton.Enable = onOff(canInspect(artifact.type));
            artifactFolderButton.Enable = 'on';
            selectedPathLabel.Text = artifact.artifactId;
        end
        fig.UserData = state;
    end

    function updateWorkflow()
        state = fig.UserData;
        run = selectedRun();
        displays = cell(numel(workflow), 1);
        for i = 1:numel(workflow)
            if isLegacySelection()
                status = legacyStageStatus(filteredLegacyArtifacts(), workflow(i));
            else
                status = stageStatus(run, state.project, workflow(i));
            end
            displays{i} = sprintf('%s  [%s]', workflow(i).name, status);
        end
        previous = selectedWorkflowIndex();
        workflowList.Items = displays;
        workflowList.Value = displays{min(previous, numel(displays))};
        updateWorkflowSelection();
    end

    function onWorkflowChanged(~, ~)
        updateWorkflowSelection();
    end

    function updateWorkflowSelection()
        idx = selectedWorkflowIndex();
        item = workflow(idx);
        objectiveArea.Value = splitlines(string(item.description));
        hasRun = ~isempty(selectedRun());
        launchButton.Text = item.buttonLabel;
        launchButton.Enable = onOff(hasRun && ~isempty(item.action));
        if ~hasRun
            if isLegacySelection()
                launchButton.Text = 'Import outputs first';
            else
                launchButton.Text = 'Select a run';
            end
        end
    end

    function idx = selectedWorkflowIndex()
        idx = 1;
        value = workflowList.Value;
        if isempty(value), return; end
        for j = 1:numel(workflow)
            if startsWith(value, [workflow(j).name '  [']) || ...
                    strcmp(value, workflow(j).name)
                idx = j;
                return;
            end
        end
    end

    function updateSummary()
        state = fig.UserData;
        run = selectedRun();
        if isempty(run)
            legacy = filteredLegacyArtifacts();
            if isLegacySelection()
                summaryLabel.Text = sprintf(['No registered run selected | ', ...
                    '%d unregistered artifact(s) found'], numel(legacy));
            else
                summaryLabel.Text = sprintf('%d run(s), %d unregistered file(s)', ...
                    numel(state.project.runs), ...
                    numel(state.project.legacyArtifacts));
            end
            return;
        end
        mask = strcmp({state.project.artifacts.runId}, run.runId) & ...
            pathMask({state.project.artifacts.manifestFile}, run.manifestFile);
        artifacts = state.project.artifacts(mask);
        current = nnz(strcmp({artifacts.status}, 'current'));
        attention = numel(artifacts) - current;
        summaryLabel.Text = sprintf('%s | %d current artifact(s), %d needing attention', ...
            runSubject(run), current, attention);
    end

    function onLaunchStage(~, ~)
        idx = selectedWorkflowIndex();
        item = workflow(idx);
        if isempty(item.action), return; end
        if item.modifiesArtifacts && strcmp(fig.Visible, 'on')
            answer = uiconfirm(fig, [item.confirmation newline newline ...
                'Downstream artifacts may become stale and will be marked accordingly.'], ...
                item.name, 'Options', {'Continue', 'Cancel'}, ...
                'DefaultOption', 2, 'CancelOption', 2);
            if ~strcmp(answer, 'Continue'), return; end
        end
        setBusy(true, ['Launching ' item.name '...']);
        cleanup = onCleanup(@() setBusy(false, 'Ready'));
        try
            launchAction(item.action);
            refreshProject(false);
        catch ME
            if strcmp(fig.Visible, 'on')
                uialert(fig, ME.message, [item.name ' failed']);
            else
                rethrow(ME);
            end
        end
        clear cleanup
    end

    function launchAction(action)
        context = selectedContext();
        switch action
            case 'crop'
                scalp = requireArtifact(context, {'full-head-scalp'}, ...
                    {'nhpulse.scalpModel'});
                nhpulseServiceCropScalp(context, struct('scalp', scalp), ...
                    struct('cropPlaneMode', 'select', 'force', true, ...
                    'showFigures', true, 'saveFigures', true));
            case 'exclusions'
                scalp = requireArtifact(context, {'printable-scalp'}, ...
                    {'nhpulse.scalpModel'});
                nhpulseServiceDefineExclusions(context, struct('scalp', scalp), ...
                    struct('editMode', 'always', 'force', true, ...
                    'showFigures', true, 'saveFigures', true));
            case 'fiducials'
                scalp = requireArtifact(context, {'full-head-scalp'}, ...
                    {'nhpulse.scalpModel'});
                nhpulseServiceDefineFiducials(context, struct('scalp', scalp), ...
                    struct('editMode', 'always', 'force', true, ...
                    'showFigures', true, 'saveFigures', true));
            case 'target'
                anatomy = requireArtifact(context, {'anatomy'}, {'nhpulse.anatomy'});
                segmentation = requireArtifact(context, {'segmentation'}, ...
                    {'nhpulse.segmentation'});
                nhpulseServiceSelectTarget(context, struct('anatomy', anatomy, ...
                    'segmentation', segmentation), struct('showFigures', true, ...
                    'saveFigures', true));
            case 'headpost'
                trace = requireArtifact(context, {'implant-trace'}, ...
                    {'nhpulse.implantTrace'});
                scalp = requireArtifact(context, {'printable-scalp'}, ...
                    {'nhpulse.scalpModel'});
                segmentation = requireArtifact(context, {'segmentation'}, ...
                    {'nhpulse.segmentation'});
                nhpulseServicePlaceHeadpost(context, struct('source', trace, ...
                    'scalp', scalp, 'segmentation', segmentation), ...
                    struct('interactive', true, 'force', true, ...
                    'showFigures', true, 'saveFigures', true, ...
                    'placementOptions', struct('reuseExistingPose', true)));
            case 'retention'
                layout = requireArtifact(context, {'combined-layout'}, ...
                    {'nhpulse.combinedLayout'});
                scalp = requireArtifact(context, {'printable-scalp'}, ...
                    {'nhpulse.scalpModel'});
                exclusion = optionalArtifact(context, ...
                    {'anatomical-exclusions'}, {'nhpulse.exclusion'});
                implants = optionalArtifacts(context, {'implant-keepout'}, ...
                    {'nhpulse.exclusion'});
                inputs = struct('layout', layout, 'scalp', scalp, ...
                    'anatomicalExclusion', exclusion, ...
                    'implantExclusions', {implants});
                nhpulseServicePlanRetention(context, inputs, ...
                    struct('editMode', 'always', 'force', true, ...
                    'showFigures', true, 'saveFigures', true));
            case 'manufacturingInspector'
                design = requireArtifact(context, {'manufacturing-design'}, ...
                    {'nhpulse.manufacturingGeometry'});
                acsInspectCapMakerManufacturingGeometry(design.path, ...
                    'showFigures', true, 'saveFigures', false);
            otherwise
                error('nhpulseApp:UnknownAction', ...
                    'Unknown workflow action: %s', action);
        end
    end

    function handle = requireArtifact(context, keys, types)
        handle = findArtifact(context, keys, types, true);
    end

    function handle = optionalArtifact(context, keys, types)
        handle = findArtifact(context, keys, types, false);
    end

    function handles = optionalArtifacts(context, keys, types)
        state = fig.UserData;
        mask = strcmp({state.project.artifacts.runId}, context.runId) & ...
            pathMask({state.project.artifacts.manifestFile}, ...
            context.manifestFile) & ...
            strcmp({state.project.artifacts.status}, 'current');
        candidates = state.project.artifacts(mask);
        keep = ismember({candidates.artifactId}, keys) & ...
            ismember({candidates.type}, types);
        candidates = candidates(keep);
        handles = cell(numel(candidates), 1);
        for j = 1:numel(candidates)
            handles{j} = nhpulseResolveArtifact(context, ...
                candidates(j).artifactId, 'expectedType', types);
        end
    end

    function handle = findArtifact(context, keys, types, required)
        state = fig.UserData;
        mask = strcmp({state.project.artifacts.runId}, context.runId) & ...
            pathMask({state.project.artifacts.manifestFile}, ...
            context.manifestFile) & ...
            strcmp({state.project.artifacts.status}, 'current');
        candidates = state.project.artifacts(mask);
        idx = [];
        for j = 1:numel(keys)
            idx = find(strcmp({candidates.artifactId}, keys{j}), 1);
            if ~isempty(idx), break; end
        end
        if isempty(idx)
            idx = find(ismember({candidates.type}, types), 1, 'last');
        end
        if isempty(idx)
            if required
                error('nhpulseApp:RequiredArtifactMissing', ...
                    'This stage requires a current %s artifact.', ...
                    strjoin(types, ' or '));
            end
            handle = [];
            return;
        end
        handle = nhpulseResolveArtifact(context, candidates(idx).artifactId, ...
            'expectedType', types);
    end

    function onInspectArtifact(~, ~)
        artifact = selectedArtifact();
        if isempty(artifact), return; end
        setBusy(true, ['Opening ' artifact.label '...']);
        cleanup = onCleanup(@() setBusy(false, 'Ready'));
        try
            switch artifact.type
                case 'nhpulse.scalpModel'
                    acsInspectCapMakerSkinMesh(artifact.path, ...
                        'showFigures', true, 'verbose', true);
                case 'nhpulse.manufacturingGeometry'
                    acsInspectCapMakerManufacturingGeometry(artifact.path, ...
                        'showFigures', true, 'saveFigures', false);
                case {'nhpulse.optimizedMontage', 'nhpulse.combinedLayout', ...
                        'nhpulse.stimulationProtocol'}
                    reviewArgs = {'showParameterFigure', true, 'verbose', true};
                    if artifact.registered
                        reviewArgs = [reviewArgs, ...
                            {'projectContext', selectedContext()}]; %#ok<AGROW>
                    end
                    acsShowTesStimulationParameters(artifact.path, reviewArgs{:});
                otherwise
                    error('nhpulseApp:NoInspector', ...
                        'No specialized inspector is registered for %s.', ...
                        artifact.type);
            end
        catch ME
            if strcmp(fig.Visible, 'on')
                uialert(fig, ME.message, 'Inspection failed');
            else
                rethrow(ME);
            end
        end
        clear cleanup
    end

    function artifact = selectedArtifact()
        state = fig.UserData;
        artifact = [];
        row = state.selectedArtifactRow;
        if ~isempty(row) && row >= 1 && row <= numel(state.artifactRows)
            artifact = state.artifactRows(row);
        end
    end

    function onOpenProjectFolder(~, ~)
        openFolder(projectField.Value);
    end

    function onOpenArtifactFolder(~, ~)
        artifact = selectedArtifact();
        if isempty(artifact), return; end
        openFolder(fileparts(artifact.path));
    end

    function onImportLegacy(~, ~)
        state = fig.UserData;
        legacy = filteredLegacyArtifacts();
        if isempty(legacy), return; end
        subjects = unique(arrayfun(@legacySubject, legacy, ...
            'UniformOutput', false), 'stable');
        subjects = subjects(~strcmp(subjects, 'Unspecified'));
        if strcmp(subjectDropDown.Value, 'All subjects') && numel(subjects) > 1
            message = ['Select one subject before importing so files from ', ...
                'different subjects are not combined into one run.'];
            if strcmp(fig.Visible, 'on')
                uialert(fig, message, 'Select a subject');
                return;
            end
            error('nhpulseApp:LegacySubjectAmbiguous', message);
        end
        if strcmp(subjectDropDown.Value, 'All subjects')
            if isempty(subjects), subject = 'Unspecified'; else, subject = subjects{1}; end
        else
            subject = subjectDropDown.Value;
        end
        if strcmp(fig.Visible, 'on')
            answer = uiconfirm(fig, sprintf([ ...
                'Register %d existing artifact(s) for %s?\n\n', ...
                'Files will not be moved or modified. Parent relationships ', ...
                'will remain explicitly unknown.'], numel(legacy), subject), ...
                'Import existing outputs', ...
                'Options', {'Import', 'Cancel'}, ...
                'DefaultOption', 1, 'CancelOption', 2);
            if ~strcmp(answer, 'Import'), return; end
        end
        setBusy(true, 'Registering existing outputs...');
        cleanup = onCleanup(@() setBusy(false, 'Ready'));
        try
            nhpulseImportLegacyArtifacts(state.project, ...
                'selection', {legacy.path}, 'dryRun', false, ...
                'runLabel', [subject ' imported outputs'], ...
                'metadata', struct('subjectId', subject), 'verbose', true);
            refreshProject(false);
        catch ME
            if strcmp(fig.Visible, 'on')
                uialert(fig, ME.message, 'Import failed');
            else
                rethrow(ME);
            end
        end
        clear cleanup
    end

    function legacy = filteredLegacyArtifacts()
        state = fig.UserData;
        legacy = state.project.legacyArtifacts;
        if strcmp(subjectDropDown.Value, 'All subjects') || isempty(legacy)
            return;
        end
        keep = false(numel(legacy), 1);
        for i = 1:numel(legacy)
            keep(i) = strcmp(legacySubject(legacy(i)), subjectDropDown.Value);
        end
        legacy = legacy(keep);
    end

    function clearProjectDisplay()
        state = fig.UserData;
        state.project = [];
        state.runMap = zeros(0, 1);
        state.artifactRows = repmat(emptyArtifact(), 0, 1);
        state.selectedArtifactRow = [];
        fig.UserData = state;
        subjectDropDown.Items = {'All subjects'};
        subjectDropDown.Value = 'All subjects';
        runDropDown.Items = {'No registered runs'};
        runDropDown.Value = 'No registered runs';
        runDropDown.Enable = 'off';
        artifactTable.Data = emptyArtifactTable();
        summaryLabel.Text = 'Project unavailable.';
        launchButton.Enable = 'off';
        inspectButton.Enable = 'off';
        artifactFolderButton.Enable = 'off';
        importButton.Enable = 'off';
    end

    function setBusy(tf, message)
        if ~isgraphics(fig), return; end
        controls = {browseButton, openButton, refreshButton, folderButton, ...
            subjectDropDown, runDropDown, workflowList, launchButton, ...
            inspectButton, artifactFolderButton, importButton};
        if tf
            fig.Pointer = 'watch';
            for i = 1:numel(controls), controls{i}.Enable = 'off'; end
        else
            fig.Pointer = 'arrow';
            refreshButton.Enable = 'on';
            browseButton.Enable = 'on';
            openButton.Enable = 'on';
            folderButton.Enable = 'on';
            if ~isempty(fig.UserData.project)
                subjectDropDown.Enable = 'on';
                workflowList.Enable = 'on';
                if ~isempty(fig.UserData.runMap), runDropDown.Enable = 'on'; end
                updateWorkflowSelection();
                artifact = selectedArtifact();
                if ~isempty(artifact)
                    inspectButton.Enable = onOff(canInspect(artifact.type));
                    artifactFolderButton.Enable = 'on';
                end
                importButton.Enable = onOff(isLegacySelection() && ...
                    ~isempty(filteredLegacyArtifacts()));
            end
        end
        setStatus(message);
        drawnow limitrate;
    end

    function setStatus(message)
        if isgraphics(statusLabel), statusLabel.Text = message; end
    end
end

function [projectRoot, opts] = parseInputs(varargin)
    projectRoot = pwd;
    if ~isempty(varargin) && (ischar(varargin{1}) || isstring(varargin{1})) && ...
            ~any(strcmpi(char(varargin{1}), {'projectRoot', 'verifyContent', 'visible'}))
        projectRoot = char(varargin{1});
        varargin(1) = [];
    end
    p = inputParser;
    addParameter(p, 'projectRoot', projectRoot, @(x) ischar(x) || isstring(x));
    addParameter(p, 'verifyContent', true, @isBoolLike);
    addParameter(p, 'visible', 'on', @(x) any(strcmpi(char(x), {'on', 'off'})));
    parse(p, varargin{:});
    projectRoot = char(p.Results.projectRoot);
    opts = p.Results;
    opts.verifyContent = logical(opts.verifyContent);
    opts.visible = lower(char(opts.visible));
end

function workflow = workflowDefinitions()
    workflow = repmat(struct('key', '', 'name', '', 'description', '', ...
        'artifactKeys', {{}}, 'outputTypes', {{}}, 'action', '', ...
        'buttonLabel', '', 'modifiesArtifacts', false, ...
        'confirmation', ''), 0, 1);
    workflow(end + 1) = stage('inputs', 'Inputs', ...
        'Register the anatomical image and tissue segmentation used by this run.', ...
        {'anatomy', 'segmentation'}, {'nhpulse.anatomy', 'nhpulse.segmentation'});
    workflow(end + 1) = stage('scalp', 'Scalp model', ...
        'Build the canonical full-head scalp shared by modeling and cap design.', ...
        {'full-head-scalp'}, {'nhpulse.scalpModel'});
    workflow(end + 1) = stageAction('crop', 'Printable crop', ...
        'Choose the scalp footprint and printer-bed plane for the cap.', ...
        {'crop-plane', 'printable-scalp'}, ...
        {'nhpulse.cropPlane', 'nhpulse.scalpModel'}, 'crop', 'Open crop tool');
    workflow(end + 1) = stageAction('exclusions', 'Anatomical exclusions', ...
        'Mark ears, face, and other scalp regions that must not receive cap material.', ...
        {'anatomical-exclusions'}, {'nhpulse.exclusion'}, ...
        'exclusions', 'Open exclusion tool');
    workflow(end + 1) = stageAction('fiducials', 'Fiducials', ...
        'Select landmarks used to align MRI, digitizer, and scan measurements.', ...
        {'model-fiducials'}, {'nhpulse.fiducials'}, ...
        'fiducials', 'Open fiducial picker');
    workflow(end + 1) = stageAction('target', 'Stimulation target', ...
        'Select the brain location used by montage optimization.', ...
        {'stimulation-target'}, {'nhpulse.target'}, ...
        'target', 'Open target picker');
    workflow(end + 1) = stageAction('implant', 'Implants', ...
        'Place the headpost or implant model and derive its cap keepout.', ...
        {'implant-placement', 'implant-keepout'}, ...
        {'nhpulse.implantPlacement', 'nhpulse.exclusion'}, ...
        'headpost', 'Open headpost planner');
    workflow(end + 1) = stage('fitcheck', 'PLA fit check', ...
        'Build a sparse, quick-print scaffold for checking gross scalp fit.', ...
        {'fit-check-stl'}, {'nhpulse.fitCheck'});
    workflow(end + 1) = stage('layout', 'Candidate layout', ...
        'Place and iteratively expand candidate tES electrode locations.', ...
        {'candidate-layout'}, {'nhpulse.candidateLayout'});
    workflow(end + 1) = stage('modeling', 'Lead field and optimization', ...
        'Generate electrical lead fields and optimize currents for the target.', ...
        {'final-lead-field', 'optimized-montage'}, ...
        {'nhpulse.leadField', 'nhpulse.optimizedMontage'});
    workflow(end + 1) = stage('combined', 'Combined tES/EEG layout', ...
        'Add EEG sites around the selected tES montage.', ...
        {'combined-layout'}, {'nhpulse.combinedLayout'});
    workflow(end + 1) = stageAction('retention', 'Velcro retention', ...
        'Place and refine the six attachment loops used for external straps.', ...
        {'retention-plan'}, {'nhpulse.retentionPlan'}, ...
        'retention', 'Open anchor planner');
    item = stageAction('manufacturing', 'Manufacturing', ...
        'Inspect the assembled cap geometry and final dual-material STL products.', ...
        {'manufacturing-design', 'tpe-stl', 'pla-stl'}, ...
        {'nhpulse.manufacturingGeometry', 'nhpulse.manufacturingStl'}, ...
        'manufacturingInspector', 'Inspect cap geometry');
    item.modifiesArtifacts = false;
    workflow(end + 1) = item;
end

function value = stage(key, name, description, artifactKeys, outputTypes)
    value = struct('key', key, 'name', name, 'description', description, ...
        'artifactKeys', {artifactKeys}, 'outputTypes', {outputTypes}, ...
        'action', '', 'buttonLabel', 'No interactive tool', ...
        'modifiesArtifacts', false, 'confirmation', '');
end

function value = stageAction(key, name, description, artifactKeys, ...
        outputTypes, action, buttonLabel)
    value = stage(key, name, description, artifactKeys, outputTypes);
    value.action = action;
    value.buttonLabel = buttonLabel;
    value.modifiesArtifacts = true;
    value.confirmation = ['This opens the existing specialized tool and ', ...
        'records its accepted output in the selected run.'];
end

function status = stageStatus(run, project, definition)
    if isempty(run)
        status = 'No run';
        return;
    end
    mask = strcmp({project.artifacts.runId}, run.runId);
    artifacts = project.artifacts(mask);
    matched = false(size(artifacts));
    for i = 1:numel(definition.artifactKeys)
        matched = matched | strcmp({artifacts.artifactId}, ...
            definition.artifactKeys{i});
    end
    if ~any(matched)
        matched = ismember({artifacts.type}, definition.outputTypes);
    end
    artifacts = artifacts(matched);
    if isempty(artifacts)
        status = 'Not started';
        return;
    end
    values = {artifacts.status};
    if all(strcmp(values, 'current')) && ...
            numel(unique({artifacts.artifactId})) >= ...
            max(1, numel(definition.artifactKeys))
        status = 'Current';
    elseif any(strcmp(values, 'stale'))
        status = 'Stale';
    elseif any(strcmp(values, 'missing'))
        status = 'Missing';
    elseif any(strcmp(values, 'incompatible'))
        status = 'Incompatible';
    else
        status = 'Partial';
    end
end

function status = legacyStageStatus(legacy, definition)
    if isempty(legacy)
        status = 'Not started';
        return;
    end
    matched = ismember({legacy.type}, definition.outputTypes);
    if any(matched)
        status = 'Unregistered';
    else
        status = 'Not started';
    end
end

function rows = legacyRows(legacy)
    rows = repmat(emptyArtifact(), numel(legacy), 1);
    for i = 1:numel(legacy)
        rows(i).source = 'legacy';
        rows(i).artifactId = legacy(i).discoveryId;
        rows(i).type = legacy(i).type;
        rows(i).label = legacy(i).label;
        rows(i).path = legacy(i).path;
        rows(i).stage = legacy(i).stage;
        rows(i).stageOrder = legacy(i).stageOrder;
        rows(i).status = 'unregistered';
        rows(i).registered = false;
        rows(i).messages = {legacy(i).reason};
    end
end

function subject = legacySubject(item)
    subject = 'Unspecified';
    relativePath = strrep(char(item.relativePath), '\', '/');
    parts = strsplit(relativePath, '/');
    parts = parts(~cellfun(@isempty, parts));
    if numel(parts) < 2, return; end
    subjectsIndex = find(strcmpi(parts, 'subjects'), 1);
    if ~isempty(subjectsIndex) && subjectsIndex < numel(parts)
        subject = parts{subjectsIndex + 1};
        return;
    end
    syntheticIndex = find(strcmpi(parts, 'syntheticMwe'), 1);
    if ~isempty(syntheticIndex) && syntheticIndex < numel(parts)
        subject = parts{syntheticIndex + 1};
        return;
    end
    ignored = {'outputs', 'capMaker', 'segmentation', 'qc', 'manifests'};
    directoryParts = parts(1:(end - 1));
    normalized = cellfun(@lower, directoryParts, 'UniformOutput', false);
    idx = find(~ismember(normalized, ignored), 1);
    if ~isempty(idx), subject = directoryParts{idx}; end
end

function subject = runSubject(run)
    subject = 'Unspecified';
    metadata = run.manifest.metadata;
    if isstruct(metadata) && isfield(metadata, 'subjectId') && ...
            ~isempty(metadata.subjectId)
        subject = char(metadata.subjectId);
    end
end

function value = shortType(value)
    value = char(value);
    if startsWith(value, 'nhpulse.'), value = value(9:end); end
end

function mask = pathMask(paths, target)
    if ispc
        mask = strcmpi(paths, target);
    else
        mask = strcmp(paths, target);
    end
end

function tf = canInspect(type)
    tf = any(strcmp(type, {'nhpulse.scalpModel', ...
        'nhpulse.manufacturingGeometry', 'nhpulse.optimizedMontage', ...
        'nhpulse.combinedLayout', 'nhpulse.stimulationProtocol'}));
end

function tableValue = emptyArtifactTable()
    tableValue = cell2table(cell(0, 5), 'VariableNames', ...
        {'Stage', 'Type', 'Label', 'Status', 'Path'});
end

function value = emptyArtifact()
    value = struct('source', '', 'runId', '', 'manifestFile', '', ...
        'artifactId', '', 'type', '', 'label', '', 'path', '', ...
        'stage', '', 'stageOrder', 999, 'status', '', ...
        'registered', true, 'messages', {{}});
end

function value = centeredPosition(sizePx)
    screen = get(groot, 'ScreenSize');
    width = min(sizePx(1), max(900, screen(3) - 80));
    height = min(sizePx(2), max(620, screen(4) - 100));
    value = [max(20, screen(1) + (screen(3) - width) / 2), ...
        max(40, screen(2) + (screen(4) - height) / 2), width, height];
end

function openFolder(folder)
    if exist(folder, 'dir') ~= 7
        error('nhpulseApp:FolderMissing', 'Folder does not exist: %s', folder);
    end
    if ispc
        winopen(folder);
    elseif ismac
        system(sprintf('open "%s"', strrep(folder, '"', '\"')));
    else
        system(sprintf('xdg-open "%s" >/dev/null 2>&1 &', ...
            strrep(folder, '"', '\"')));
    end
end

function value = onOff(tf)
    if tf, value = 'on'; else, value = 'off'; end
end

function tf = isBoolLike(x)
    tf = (islogical(x) || isnumeric(x)) && isscalar(x);
end
