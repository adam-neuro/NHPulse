function report = nhpulseTestStageSettings()
% NHPULSETESTSTAGESETTINGS Fast non-GUI test of stage setting resolution.

    crop = nhpulseResolveStageSettings('crop', 'preset', 'detailed', ...
        'overrides', struct('showFigures', false), ...
        'advancedOptions', struct('displayMaxFaces', 8000));
    assert(crop.skinMaxFaces == 3000);
    assert(~crop.showFigures);
    assert(crop.engineOptions.displayMaxFaces == 8000);
    reuse = nhpulseResolveStageSettings('retention', 'preset', 'reuse');
    assert(strcmp(reuse.editMode, 'auto'));
    stages = {'crop', 'exclusions', 'fiducials', 'target', 'implant', 'retention'};
    for i = 1:numel(stages)
        definition = nhpulseStageSettings(stages{i});
        resolved = nhpulseResolveStageSettings(stages{i});
        assert(strcmp(definition.stageKey, stages{i}));
        assert(isstruct(resolved));
    end
    report = struct('passed', true, 'testedStages', {stages});
    fprintf('NHPulse stage settings test: PASS (%d stages)\n', numel(stages));
end
