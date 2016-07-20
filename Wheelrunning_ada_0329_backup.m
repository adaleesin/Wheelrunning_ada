function Wheelrunning_ada
% AudGonogo_3
% Hyun-Jae Pi, May30 2016

global BpodSystem

%% Program PulsePal
%load(fullfile(BpodSystem.ProtocolPath, 'AudGonogo_PulsePalProgram.mat'));
%ProgramPulsePal(ParameterMatrix);

%% ******************************************
% Training Level
TrainingLevel = 1; % option 1, 2 ,3, 4

switch TrainingLevel
    case 1 
        airpuff_dur = 0;
        TrialTypeProbs = [1 0];   % Go A only
    case 2 
        airpuff_dur = 0;
        TrialTypeProbs = [0 1];  % Go B only
    case 3 % task without air puff
        airpuff_dur = 0.2;
        TrialTypeProbs = [0.5 0.5];  % trial types --- Go A, Go B,
end

%% Define parameters
S = BpodSystem.ProtocolSettings; % Load settings chosen in launch manager into current workspace as a struct called S
if isempty(fieldnames(S))  % If settings file was an empty struct, populate struct with default settings

    S.SoundDuration=1;          %sec
    S.SoundRamping=0.4;         %sec
    S.GUI.MeanSoundFrequencyA = 1000;   %Hz
    S.GUI.MeanSoundFrequencyB = 20000;  %Hz
    for i=1:9
    S.GUI.MeanSoundFrequency(i)=2000+i*8000/9;  %Hz
    end
        
    WidthOfFrequencies=4;
    NumberOfFrequencies=5;
    S.GUI.RewardAmount = 20; % defalut 5, amount of reward delivered to the mouse in microliters
    S.TrialTypeProbs = TrialTypeProbs; %Probability of trial types 1(go) & 2(nogo) in the session
%     S.ITI = 1;
    S.WaitForRunDur =10;
    
end

%% Define trials
maxTrials = 5000;
S.TrialTypes = zeros(1,maxTrials);
for x = 1:maxTrials
    P = rand;
    Cutoffs = cumsum(S.TrialTypeProbs);
    Found = 0;
    for y = 1:length(S.TrialTypeProbs)
        if P<Cutoffs(y) && Found == 0
            Found = 1;
            S.TrialTypes(x) = y;
        end
    end
end


%% Initialize parameter GUI plugin
BpodParameterGUI('init', S);
BpodSystem.Data.TrialTypes = []; % The trial type of each trial completed will be added here.
%% Initialize plots
BpodSystem.ProtocolFigures.OutcomePlotFig = figure('Position', [400 600 1000 200],'Name','Outcome plot','numbertitle','off', 'MenuBar', 'none', 'Resize', 'off');
BpodSystem.GUIHandles.OutcomePlot = axes('Position', [.075 .3 .89 .6]);
OutcomePlot_AudGonogo(BpodSystem.GUIHandles.OutcomePlot,'init',2-S.TrialTypes);
BpodNotebook('init');

%% Define stimuli and send to sound server
SF = 192000; % Sound card sampling rate
Sound1=SoundGenerator(SF, S.GUI.MeanSoundFrequencyA, WidthOfFrequencies, NumberOfFrequencies, S.SoundDuration, S.SoundRamping);
Sound2=SoundGenerator(SF, S.GUI.MeanSoundFrequencyB, WidthOfFrequencies, NumberOfFrequencies, S.SoundDuration, S.SoundRamping);
for i=1:9
Sound_run(i,:)= GenerateSineWave(SF, S.GUI.MeanSoundFrequency(i), 0.2); % Sampling freq (hz), Sine frequency (hz), duration (s)
end


% Program sound server
PsychToolboxSoundServer('init')
PsychToolboxSoundServer('Load', 10, Sound1); %PsychToolboxSoundServer('load', SoundID, Waveform)
PsychToolboxSoundServer('Load', 11, Sound2); %Sounds are triggered by sending a soft code back to the governing computer 
                                            %from a trial's state matrix, and calling PsychToolboxSoundServer from a predetermined 
                                            %soft code handler function.
for i=1:9
PsychToolboxSoundServer('Load', i, Sound_run(i,:)); %PsychToolboxSoundServer('load', SoundID, Waveform)
end
% Set soft code handler to trigger sounds
BpodSystem.SoftCodeHandlerFunction = 'SoftCodeHandler_PlaySound';


%% Main loop
for currentTrial = 1:maxTrials
    disp(['Trial # ' num2str(currentTrial) ': trial type ' num2str(S.TrialTypes(currentTrial))]);
    S = BpodParameterGUI('sync', S); % Sync parameters with BpodParameterGUI plugin
    
    switch S.TrialTypes(currentTrial)
        case 1  % Go A; 
            %ParameterMatrix{5,2} = 0.0001; % Set PulsePal to 100us pulse width on output channel 1
            %ParameterMatrix{8,2} = 0.0001; % Set PulsePal to 100us pulse interval on output channel 1
%             StateReinforcer = 'TriggerReward_A';
            OutputActionArgument = {'SoftCode', 1,'BNCState', 10};  % generate sound
        case 2  % Go B; 
            %ParameterMatrix{5,2} = 0.001; % Set PulsePal to 100us pulse width on output channel 1
            %ParameterMatrix{8,2} = 0.001; % Set PulsePal to 100us pulse interval on output channel 1
%             StateReinforcer = 'TriggerReward_B';
            OutputActionArgument = {'SoftCode', 2,'BNCState', 11};

    end
    %ProgramPulsePal(ParameterMatrix);
    WaterTime = GetValveTimes(S.GUI.RewardAmount,[1]); % This code gets the time valves 2 (valve code)must be open to deliver liquid being set. 

%     S.ReinforcementDelays(currentTrial) = random('Normal',1,1);
        S.ReinforcementDelays(currentTrial) = 1+rand();
    %     Assemble state matrix
    sma = NewStateMatrix();
    sma = SetGlobalCounter(sma, 1, 'BNC1High', 2);
    sma = SetGlobalCounter(sma, 2, 'BNC1High', 20);

    sma = AddState(sma, 'Name', 'DeliverStimulus',...
        'Timer',0.5,...
        'StateChangeConditions',{'Tup','ControlRunDelay'},...
        'OutputActions', OutputActionArgument);
    sma = AddState(sma, 'Name', 'ControlRunDelay', ...
        'Timer',S.ReinforcementDelays(currentTrial),...
        'StateChangeConditions', {'GlobalCounter1_End', 'Timeout','Tup','WaitForRun'},...
        'OutputActions', {});
%     sma = AddState(sma, 'Name', 'CueDelivery', ...
%         'Timer', 0.5,...
%         'StateChangeConditions',{'Tup', 'WaitForRun'},...%waiting for trigger in input 1
%         'OutputActions', {'PWM3', 255});  %led light up, send ttl to ni analog acquisition 
   if S.TrialTypes(currentTrial)==1
            for i=1:30
            if i<10
            Counterstate(i,:)=['Counter_Reset0' num2str(i) ''];
            Feedbackstate(i,:)=['Feedback_Reset0' num2str(i) '']; 
            elseif i>=10
            Counterstate(i,:)=['Counter_Reset' num2str(i) ''];    
            Feedbackstate(i,:)=['Feedback_Reset' num2str(i) '']; 
            end
            end
        j=1;
    sma = AddState(sma, 'Name', 'WaitForRun', ...
            'Timer',10,...
            'StateChangeConditions', {'Tup', 'Timeout', 'GlobalCounter1_End', 'Counterstate(j,:)','GlobalCounter2_End', 'DeliverReward'},...
            'OutputActions', {'PWM3', 255}); 
   sma = AddState(sma, 'Name', 'Counterstate(j,:)', ...
            'Timer',0,...
            'StateChangeConditions', {'Tup', 'Feedbackstate(j,:)','GlobalCounter2_End', 'DeliverReward'},...
            'OutputActions', {'GlobalCounterReset', 1});
   sma = AddState(sma, 'Name', 'Feedbackstate(j,:)', ...
            'Timer',0,...
            'StateChangeConditions', {'Tup', 'Counterstate(j+1,:)'},...
            'OutputActions', {'SoftCode', j}); 

   elseif S.TrialTypes(currentTrial)==2
           sma = AddState(sma, 'Name', 'WaitForRun', ...
            'Timer',10,...
            'StateChangeConditions', {'Tup', 'DeliverReward', 'GlobalCounter1_End', 'DeliverPunish'},...
            'OutputActions', {'PWM3', 255});
   end
       
    sma = AddState(sma, 'Name', 'ITI', ...
        'Timer',5,...
        'StateChangeConditions', {'Tup', 'exit'}, ...
        'OutputActions', {}); 
    sma = AddState(sma,'Name', 'DeliverReward', ...
        'Timer',0.1, ...
        'StateChangeConditions', {'Tup', 'ITI'},...
        'OutputActions', {'ValveState', 1});
    sma = AddState(sma,'Name', 'DeliverPunish', ...
        'Timer',airpuff_dur, ...
        'StateChangeConditions', {'Tup', 'ITI'},...
        'OutputActions', {'ValveState', 2});
    sma = AddState(sma,'Name', 'Timeout', ...
        'Timer',1, ...
        'StateChangeConditions', {'Tup', 'ITI'},...
        'OutputActions', {'PWM3', 255});
    
    
    SendStateMatrix(sma);
    RawEvents = RunStateMatrix;
    if ~isempty(fieldnames(RawEvents)) % If trial data was returned
    BpodSystem.Data = AddTrialEvents(BpodSystem.Data,RawEvents);
    BpodSystem.Data = BpodNotebook('sync',BpodSystem.Data);
    BpodSystem.Data.TrialSettings(currentTrial) = S; % Adds the settings used for the current trial to the Data struct (to be saved after the trial ends)
    BpodSystem.Data.S.TrialTypes(currentTrial) = S.TrialTypes(currentTrial); % Adds the trial type of the current trial to data
    UpdateOutcomePlot(S.TrialTypes, BpodSystem.Data);
    SaveBpodSessionData; % Saves the field BpodSystem.Data to the current data file
    end
    HandlePauseCondition; % Checks to see if the protocol is paused. If so, waits until user resumes.
if BpodSystem.BeingUsed == 0
    return
  end
end



%---------------------------------------- /MAIN LOOP

%% sub-functions
function UpdateOutcomePlot(TrialTypes, Data)
global BpodSystem
Outcomes = zeros(1,Data.nTrials);
for x = 1:Data.nTrials
    if ~isnan(Data.RawEvents.Trial{x}.States.DeliverReward(1))
        Outcomes(x) = 1;
%     elseif ~isnan(Data.RawEvents.Trial{x}.States.DeliverPunish(1))
%         Outcomes(x) = 0;
    else
        Outcomes(x) = 3;
    end
end
OutcomePlot_AudGonogo(BpodSystem.GUIHandles.OutcomePlot,'update',Data.nTrials+1,2-TrialTypes,Outcomes);
