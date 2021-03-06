function Wheelrunning_ada


global BpodSystem
PulsePal;
load('D:\Bpod_r0_5-master\Protocols\Wheelrunning_ada\SoundPulse_1ms.mat');
ProgramPulsePal(ParameterMatrix);

% Training Level
TrainingLevel = 1; % option 1, 2 ,3, 4

switch TrainingLevel
    case 1 
        airpuff_dur = 0;
        TrialTypeProbs = [1 0];   % Go A only
    case 2 
        airpuff_dur = 0.1;
        TrialTypeProbs = [0 1];  % Go B only
    case 3 % task without air puff
        airpuff_dur = 0.04;
        TrialTypeProbs = [0.5 0.5];  % trial types --- Go A, Go B,
end

%% Define parameters
S = BpodSystem.ProtocolSettings; % Load settings chosen in launch manager into current workspace as a struct called S
if isempty(fieldnames(S))  % If settings file was an empty struct, populate struct with default settings
S.SoundDuration=1;          %sec
S.SoundRamping=0.4;         %sec
S.MeanSoundFrequencyA = 500;   %Hz
S.MeanSoundFrequencyB = 50000;  %Hz
%     for ii=1:20
%     S.MeanSoundFrequency(ii)=1000+(ii-1)*(20000-1000)/20;  %Hz
%     end
S.WidthOfFrequencies=2;
S.NumberOfFrequencies=5;
end
BpodSystem.Data.Sequence = [];

%% Define stimuli and send to sound server
SF = 192000; % Sound card sampling rate
Noise=randn(1,SF);
Sound1=SoundGenerator(SF, S.MeanSoundFrequencyA, S.WidthOfFrequencies, S.NumberOfFrequencies, S.SoundDuration, S.SoundRamping);
Sound2=SoundGenerator(SF, S.MeanSoundFrequencyB, S.WidthOfFrequencies, S.NumberOfFrequencies, S.SoundDuration, S.SoundRamping);
% for ii=1:20
% Sound_run(ii,:)= GenerateSineWave(SF, S.MeanSoundFrequency(ii), 0.5); % Sampling freq (hz), Sine frequency (hz), duration (s)
% end
% SoundID=1:20;
% Program sound server
PsychToolboxSoundServer('init');
% for i=1:20
% PsychToolboxSoundServer('Load', i, Sound_run(i,:)); %PsychToolboxSoundServer('load', SoundID, Waveform)
% end

PsychToolboxSoundServer('Load', 1, Sound1); %PsychToolboxSoundServer('load', SoundID, Waveform)
PsychToolboxSoundServer('Load', 2, Sound2); %Sounds are triggered by sending a soft code back to the governing computer 
                                             %from a trial's state matrix, and calling PsychToolboxSoundServer from a predetermined 
                                             %soft code handler function.
                                             % Set soft code handler to trigger sounds
PsychToolboxSoundServer('Load', 3, Noise);
BpodSystem.SoftCodeHandlerFunction = 'SoftCodeHandler_PlaySound';

%%  Waterscaled
MinRew =GetValveTimes(1, [1]);
MaxRew =GetValveTimes(15, [1]);
reward_valve_times = linspace(MinRew,MaxRew,500);

%% Define trials
maxTrials = 5000;
S.TrialSequence = zeros(1,maxTrials);
for x = 1:maxTrials
    P = rand;
    Cutoffs = cumsum(TrialTypeProbs);
    Found = 0;
    for y = 1:length(TrialTypeProbs)
        if P<Cutoffs(y) && Found == 0
            Found = 1;
            S.TrialSequence(x) = y;
        end
    end
end
TrialSequence=S.TrialSequence;

%% Initialize plots
BpodSystem.ProtocolFigures.OutcomePlotFig = figure('Position', [50 800 900 200],'Name','Outcome plot','numbertitle','off', 'MenuBar', 'none', 'Resize', 'off');   %[400 800 1000 200]
BpodSystem.GUIHandles.OutcomePlot = axes('Position', [.075 .3 .89 .6]); % [.075 .3 .89 .6]
OutcomePlot_WheelRunning(BpodSystem.GUIHandles.OutcomePlot,'init',2-S.TrialSequence);
FigAction=Online_WheelRunningPlot('ini'); 

%% Main loop
for currentTrial = 1:maxTrials
    disp(['Trial # ' num2str(currentTrial) ': trial type ' num2str(S.TrialSequence(currentTrial))]);
    
    switch S.TrialSequence(currentTrial)
        case 1  % Go A; 
            OutputActionArgument = {'SoftCode', 1,'BNCState', 1};  % generate sound
        case 2  % Go B; 
            OutputActionArgument = {'SoftCode', 2,'BNCState', 2};

    end
    
    sma = NewStateMatrix();
    sma = SetGlobalTimer(sma, 1, 10); 
    if currentTrial>1
        if S.TrialSequence(currentTrial-1)==1
            if   ~isnan(PA.RawEvents.Trial{end}.States.DeliverReward(1))
                temp_reward=length(PA.RawEvents.Trial{end}.Events.BNC1High);
                if  temp_reward < 500
                this_reward_valve_time = reward_valve_times(temp_reward);
                else
                this_reward_valve_time = reward_valve_times(500);  
                end 
            else
              this_reward_valve_time =0;
            end
        elseif S.TrialSequence(currentTrial-1)==2  
             if   ~isnan(PA.RawEvents.Trial{end}.States.DeliverReward(1))
                       this_reward_valve_time =reward_valve_times(300); 
             else
                  this_reward_valve_time =0;
            end
        end
    else
        this_reward_valve_time = 0;
    end
      
    sma = AddState(sma,'Name', 'Dummy1', ...
        'Timer',0, ...
        'StateChangeConditions', {'Tup', 'RewardScale'}, ...
        'OutputActions', {});
    sma = AddState(sma,'Name', 'RewardScale', ...
        'Timer',this_reward_valve_time, ...
        'StateChangeConditions', {'Tup', 'ITI'},...
        'OutputActions', {'ValveState', 1});
    sma = AddState(sma,'Name', 'ITI', ...
        'Timer',5, ...
        'StateChangeConditions', {'Tup', 'Time1_Reset'}, ...
        'OutputActions', {'PWM3', 255,'WireState',8});
    sma = AddState(sma,'Name', 'Time1_Reset', ...
        'Timer',0.5, ...
        'StateChangeConditions', {'Tup', 'SpeedCheck'}, ...
        'OutputActions', {'GlobalTimerTrig', 1});
    sma = AddState(sma, 'Name', 'SpeedCheck', ...
        'Timer',1, ...
        'StateChangeConditions',{ 'BNC1High','DeliverNoise','Tup','DeliverStimulus'}, ...
        'OutputActions', {});  
    sma = AddState(sma, 'Name', 'DeliverStimulus', ...
        'Timer',1, ...
        'StateChangeConditions',{'Tup','WaitForRun'}, ...
        'OutputActions', OutputActionArgument);  
                 
    if S.TrialSequence(currentTrial)==1     
         sma = AddState(sma, 'Name', 'WaitForRun', ...
                    'Timer',10,...
                    'StateChangeConditions', {'GlobalTimer1_End','TimeOut','BNC1High','FeedBack'},...
                    'OutputActions', {});  
         sma = AddState(sma, 'Name', 'FeedBack', ...
                    'Timer',0.01,...
                    'StateChangeConditions', {'GlobalTimer1_End','DeliverReward','Tup','SpeedSample'},...
                    'OutputActions', {'BNCState',1});
         sma = AddState(sma, 'Name', 'SpeedSample', ...
                    'Timer',10,...
                    'StateChangeConditions', {'GlobalTimer1_End','DeliverReward','BNC1High','FeedBack'},...
                    'OutputActions', {});          
   elseif S.TrialSequence(currentTrial)==2
           sma = AddState(sma, 'Name', 'WaitForRun', ...
            'Timer',5,...
            'StateChangeConditions', {'Tup', 'DeliverReward', 'BNC2High', 'DeliverPunish'},...
            'OutputActions', {});
            
    end   
  
    sma = AddState(sma,'Name', 'DeliverReward', ...
        'Timer',0, ...
        'StateChangeConditions', {'Tup', 'exit'},...
        'OutputActions', {});
    sma = AddState(sma,'Name', 'DeliverPunish', ...
        'Timer',airpuff_dur, ...
        'StateChangeConditions', {'Tup', 'exit'},...
        'OutputActions', {'ValveState', 2});
    sma = AddState(sma,'Name', 'TimeOut', ...
        'Timer',0.5, ...
        'StateChangeConditions', {'Tup', 'exit'},...
        'OutputActions', {});
    sma = AddState(sma,'Name', 'DeliverNoise', ...
        'Timer',1, ...
        'StateChangeConditions', {'Tup', 'exit'},...
        'OutputActions', {'SoftCode', 3});
  
    SendStateMatrix(sma);  
    
    RawEvents = RunStateMatrix;
    if ~isempty(fieldnames(RawEvents)) % If trial data was returned
    BpodSystem.Data = AddTrialEvents(BpodSystem.Data,RawEvents);
    PA=BpodSystem.Data; 
    BpodSystem.Data.TrialSettings(currentTrial) = S; % Adds the settings used for the current trial to the Data struct (to be saved after the trial ends)
    BpodSystem.Data.TrialSequence(currentTrial) = TrialSequence(currentTrial); % Adds the trial type of the current trial to data
    UpdateOutcomePlot(S.TrialSequence, BpodSystem.Data);
    SaveBpodSessionData; % Saves the field BpodSystem.Data to the current data file
    end
   [TrialType,Response_events]=UpdateOnlineEvent(S.TrialSequence,BpodSystem.Data,currentTrial);
    FigAction=Online_WheelRunningPlot('update',FigAction,TrialType,Response_events); 
    HandlePauseCondition; % Checks to see if the protocol is paused. If so, waits until user resumes.
   if BpodSystem.BeingUsed == 0
    return
   end
   
end



%---------------------------------------- /MAIN LOOP

%% sub-functions

function UpdateOutcomePlot(TrialSequence, Data)
global BpodSystem
Outcomes = zeros(1,Data.nTrials);
for x = 1:Data.nTrials
    if ~isnan(Data.RawEvents.Trial{x}.States.DeliverPunish(1))
         Outcomes(x) = 0;
    elseif ~isnan(Data.RawEvents.Trial{x}.States.DeliverNoise(1))
         Outcomes(x) = 2;
    elseif ~isnan(Data.RawEvents.Trial{x}.States.TimeOut(1))
         Outcomes(x) = 3;
    else
        Outcomes(x) =  1;
    end
end
OutcomePlot_WheelRunning(BpodSystem.GUIHandles.OutcomePlot,'update',Data.nTrials+1,2-TrialSequence,Outcomes);

function [TrialType,Response_events]=UpdateOnlineEvent(TrialSequence,Data,currentTrial)
switch TrialSequence(currentTrial)
        case 1
        if ~isnan(Data.RawEvents.Trial{end}.States.DeliverNoise(1))
            TrialType= 5;
            Response_events=Data.RawEvents.Trial{end}.Events.BNC1High-Data.RawEvents.Trial{end}.States.SpeedCheck(1,2);
        elseif ~isnan(Data.RawEvents.Trial{end}.States.TimeOut(1))
            TrialType= 3;
            Response_events=[66];
        else
            TrialType= 1;
            Response_events=Data.RawEvents.Trial{end}.Events.BNC1High-Data.RawEvents.Trial{end}.States.DeliverStimulus(1,1);
        end
    case 2
        if ~isnan(Data.RawEvents.Trial{end}.States.DeliverReward(1))
            TrialType= 2;
            Response_events=[66];
        elseif ~isnan(Data.RawEvents.Trial{end}.States.DeliverPunish(1))
            TrialType= 4;
            Response_events=Data.RawEvents.Trial{end}.Events.BNC1High-Data.RawEvents.Trial{end}.States.DeliverStimulus(1,1);
        else
            TrialType= 6;
            Response_events=Data.RawEvents.Trial{end}.Events.BNC2High-Data.RawEvents.Trial{end}.States.SpeedCheck(1,2);
        end
end
