classdef CardioFlex_raw_code < matlab.apps.AppBase

    % Properties that correspond to app components
    properties (Access = public)
        UIFigure                        matlab.ui.Figure
        FileFormatMenu                  matlab.ui.container.Menu
        HeaderLinesMenu                 matlab.ui.container.Menu
        SelectDataRangeMenu             matlab.ui.container.Menu
        StartMenu                       matlab.ui.container.Menu
        EndMenu                         matlab.ui.container.Menu
        DataColumnsMenu                 matlab.ui.container.Menu
        TimeMenu                        matlab.ui.container.Menu
        LengthMenu                      matlab.ui.container.Menu
        ForceMenu                       matlab.ui.container.Menu
        StimulusMenu                    matlab.ui.container.Menu
        StimulusValueMenu               matlab.ui.container.Menu
        ManuallyAssignStretchTimepointsMenu  matlab.ui.container.Menu
        InitialLengthL0inmmMenu         matlab.ui.container.Menu
        TabGroup                        matlab.ui.container.TabGroup
        AnalysisTab                     matlab.ui.container.Tab
        SelectedFilesClickonfiletostartanalysisListBoxLabel_2  matlab.ui.control.Label
        ImportantclicktoavoidoverwritingdataLabel  matlab.ui.control.Label
        SelectStretchtoPlotAnalyzeListBox  matlab.ui.control.ListBox
        StretchtoPlotAnalyzeLabel       matlab.ui.control.Label
        SelectedFilesListBox            matlab.ui.control.ListBox
        SelectedFilesListBoxLabel       matlab.ui.control.Label
        NumberofBeatsSpinner            matlab.ui.control.Spinner
        NumberofBeatsSpinnerLabel       matlab.ui.control.Label
        NextFileButton                  matlab.ui.control.Button
        SaveDataandFiguresButton        matlab.ui.control.Button
        CombineSelectedStretchesButton  matlab.ui.control.Button
        SelectFilesButton               matlab.ui.control.Button
        UIAxes                          matlab.ui.control.UIAxes
        SummaryTab                      matlab.ui.container.Tab
        ImportantchangegroupnametoavoidoverwritingdataLabel  matlab.ui.control.Label
        OptionalGraphsListBoxLabel      matlab.ui.control.Label
        OptionalGraphsListBox           matlab.ui.control.ListBox
        StartOverButton                 matlab.ui.control.Button
        EditField                       matlab.ui.control.EditField
        EditField2                      matlab.ui.control.EditField
        EditField3                      matlab.ui.control.EditField
        Group3Button                    matlab.ui.control.Button
        Group2Button                    matlab.ui.control.Button
        Group1Button                    matlab.ui.control.Button
        UIAxes9                         matlab.ui.control.UIAxes
        UIAxes8                         matlab.ui.control.UIAxes
        UIAxes7                         matlab.ui.control.UIAxes
        UIAxes6                         matlab.ui.control.UIAxes
        UIAxes5                         matlab.ui.control.UIAxes
        UIAxes4                         matlab.ui.control.UIAxes
        UIAxes3                         matlab.ui.control.UIAxes
        UIAxes2                         matlab.ui.control.UIAxes
    end

    properties (Access = private)
        time_data % stores complete data for time from start to end 
        force_data % stores complete data for force from start to end 
        length_data % stores complete data for length from start to end 
        stimulus_data % stores complete data for stimulus from start to end 
        trigger % points where stretches occurs; detected by change in length
        NonDataLines % number of of non-data lines or header lines
        Data_Start % line# where you want to start analysis
        Data_End % line# where you want to stop analysis
        TimeColumn % column# containing time data
        LengthColumn % column# containing length data
        ForceColumn % column# containing force data
        StimColumn % column# containing stimulus data
        StimValue % value for stimulus (e.g. 769)
        triggerpts % points where stretches occurs; if needed to be manually assigned
        initial_length % length before stretching starts
        FileMap % stores imported files name and location
        CurrentFileName % file name for file being analyzed from a list of files imported
        freq_stim %determine frequency of stimulation
        InputBeats % number of beats to be selected per stretch for analysis
        total_stretches % number of stretches
        selectedstretch % current stretch being analyzed
        OutputFolder % create output folder to save output files and figures
        avg_selected_beats % average of selected beats per length/stretch
        DataOutput % tab delimited output file
        force_wo_peak % force data with all beats/contractions removed
        dist_beats_all % difference in beat intervals; for Poincare plot       
        excel_tabs % number of columns in output files
        group1value % Control/Group 1 for summary
        group2value % Treatment/Group 2 for summary
        group3value % Mutant/Group 3 for summary
        combined_group1 % combine all files selected for this group
        combined_group2 % combine all files selected for this group
        combined_group3 % combine all files selected for this group
        optional_graph % select to plot contraction/relaxation
    end

    % Callbacks that handle component events
    methods (Access = private)

        % Code that executes after component creation
        function startupFcn(app)
            % Set the default: 5 beats to be selected per length change
            app.InputBeats = 5;
            % Set the default: 265 non data lines
            app.NonDataLines = 265;
            % Set the default:stretching data start
            app.Data_Start = 165265-app.NonDataLines;
            % Set the default: stretching data end
            app.Data_End = 700265-app.NonDataLines;
            % Set the default column for following data
            app.TimeColumn = 1;
            app.LengthColumn = 2;
            app.ForceColumn = 4;
            app.StimColumn = 9;
            %default stimulus value
            app.StimValue=769;
            %Set default Triggers (where length changes in 8-step protocol)
            %app.triggerpts=[5051;65051;125051;185051;245051;305051;365051;425051;515051];
            %Set default initial length value in mm
            %app.initial_length = 6.3;
            %Set Default number of stretches           
            app.total_stretches = 8;
            %Set Default group names for DISPLAY
            app.EditField.Value='Control';
            app.EditField2.Value='Treatment';
            app.EditField3.Value='Mutant';
            %Set Default group names
            app.group1value='Control';
            app.group2value='Treatment';
            app.group3value='Mutant';
            %Default excel tab headers for groups
            app.excel_tabs=["Length(mm)","Passive_Force(mN)","Active_Force(mN)","BPM","Contraction_90pct(ms)","Contraction_75pct(ms)","Contraction_50pct(ms)","Relaxation_90pct(ms)","Relaxation_75pct(ms)","Relaxation_50pct(ms)","Contraction_Velocity(mNperms)","Relaxation_Velocity(mNperms)","Force_Integral(mN)","Work(mN.mm)","SD1","SD2","SD12"];
            %Initialize array for combining data from all files from the groups
            app.combined_group1 = cell(1, length(app.excel_tabs));
            app.combined_group2 = cell(1, length(app.excel_tabs));
            app.combined_group3 = cell(1, length(app.excel_tabs));
        end

        % Menu selected function: HeaderLinesMenu
        function HeaderLinesMenuSelected(app, event)
            %ask user to change number of header lines in file
            headerlines = inputdlg('Enter number of header lines','Header Lines',[1 45],string(265));
            app.NonDataLines=str2double(headerlines);
        end

        % Menu selected function: StartMenu
        function StartMenuSelected(app, event)
            %ask user to input start of stretch protocol data in file
            data_start = inputdlg('Enter Line# where data starts','Data start',[1 45],string(165265));
            app.Data_Start=str2double(data_start)-app.NonDataLines;
        end

        % Menu selected function: EndMenu
        function EndMenuSelected(app, event)
            %ask user to input end of stretch protocol data in file
            data_end = inputdlg('Enter Line# where data ends','Data end',[1 45],string(700265));
            app.Data_End=str2double(data_end)-app.NonDataLines;
        end

        % Menu selected function: TimeMenu
        function TimeMenuSelected(app, event)
            %ask user to to change column containing time in file
            timecolumn = inputdlg('Enter Column# containing Time data','Time',[1 45],string(1));
            app.TimeColumn=str2double(timecolumn);
        end

        % Menu selected function: LengthMenu
        function LengthMenuSelected(app, event)
            %ask user to to change column containing length in file
            lengthcolumn = inputdlg('Enter Column# containing Length data','Length',[1 45],string(2));
            app.LengthColumn=str2double(lengthcolumn);
        end

        % Menu selected function: ForceMenu
        function ForceMenuSelected(app, event)
            %ask user to to change column containing force in file
            forcecolumn = inputdlg('Enter Column# containing Force data','Force',[1 45],string(4));
            app.ForceColumn=str2double(forcecolumn );
        end

        % Menu selected function: StimulusMenu
        function StimulusMenuSelected(app, event)
            %ask user to to change column containing stimulus in file
            stimcolumn = inputdlg('Enter Column# containing Stimulus data','Stimulus',[1 45],string(9));
            app.StimColumn=str2double(stimcolumn);
        end

        % Menu selected function: StimulusValueMenu
        function StimulusValueMenuSelected(app, event)
            %ask user to to change column containing stimulus in file
            stimvalue = inputdlg('Enter Stimulus Value','Stimulus',[1 45],string(769));
            app.StimValue=str2double(stimvalue);
        end

        % Menu selected function: ManuallyAssignStretchTimepointsMenu
        function ManuallyAssignStretchTimepointsMenuSelected(app, event)
            %ask user to manually assign/input info where stretches occur
            %triggerprompt = arrayfun(@(x) ['Enter Trigger', num2str(x)], 1:10, 'UniformOutput', false);
            triggerprompt = {'Enter Stretch 1 Line#', 'Enter Stretch 2 Line#', 'Enter Stretch 3 Line#', 'Enter Stretch 4 Line#', 'Enter Stretch 5 Line#', 'Enter Stretch 6 Line#', 'Enter Stretch 7 Line#', 'Enter Stretch 8 Line#', 'Enter End Line#'};
            triggerinput = [170316;230316;290316;350316;410316;470316;530316;590316;680316];
            settriggers = inputdlg(triggerprompt, 'Stretch Line#:', [1 45], string(triggerinput));
            app.triggerpts = str2double(settriggers)-app.NonDataLines-app.Data_Start;
        end

        % Menu selected function: InitialLengthL0inmmMenu
        function InitialLengthL0inmmMenuSelected(app, event)
            %ask user to input initial length value in mm
            input_length=inputdlg('Enter length value in Millimeters','Initial Length',[1 45],string(6.3));
            app.initial_length=str2double(input_length);
        end

        % Button pushed function: SelectFilesButton
        function SelectFilesButtonPushed(app, event)
            %open and select file/s to analyze
            %data file with preconditioning and stretching protocol
            [file,path] = uigetfile('*.*', 'Select One or More Files', 'MultiSelect', 'on');

            % Check if the user canceled the dialog
            if isequal(file, 0) || isequal(path, 0)
                return;
            end

            %Normalize 'file' into a cell array immediately so loop always works
            if ischar(file) || isstring(file)
                file = {file};
            end

            % Get the true number of selected files
            total = length(file);

            % Initialize structural storage for file paths
            app.FileMap = struct();
            selectedfiles = string.empty(1, 0);

            % Combine file name and path into a single absolute path
            for i = 1:total
                filename=file{i};
                % Build complete file path
                fullPath = fullfile(path, filename);

                % Generate a safe struct field name by removing extensions/spaces
                safeName = matlab.lang.makeValidName(filename);
                app.FileMap.(safeName) = fullPath;

                % Store the display name for the UI List Box
                selectedfiles(i) = string(filename);
            end

            % Populate the List Box 
            app.SelectedFilesListBox.Items = selectedfiles;

            % Display the number of files selected
            fprintf('Number of files selected: %d\n' , total)
        end

        % Value changed function: NumberofBeatsSpinner
        function NumberofBeatsSpinnerValueChanged(app, event)
            app.InputBeats = app.NumberofBeatsSpinner.Value;

            % Display number of beats to be selected per length
            fprintf('Number of Beats /length change: %d\n' , app.InputBeats)
        end

        % Callback function: SelectedFilesListBox, SelectedFilesListBox
        function SelectedFilesListBoxValueChanged(app, event)
            currentfileName = app.SelectedFilesListBox.Value;

            %Exit early if the selection is empty or cleared to prevent crashes
            if isempty(currentfileName)
                return;
            end

            % Convert to a standard character vector if it returns as a cell/string array
            if iscell(currentfileName) || isstring(currentfileName)
                currentfileName = char(currentfileName);
            end

            % Retrieve the full path using the safe struct name
            safeName = matlab.lang.makeValidName(currentfileName);
            fullPath = app.FileMap.(safeName);

            % Extract the clean base name (without extension) for the folder name
            [~, cleanName, ~] = fileparts(currentfileName);
            app.CurrentFileName = cleanName; % Keep full name with extension saved

            disp(['Selected file path: ', fullPath]);

            % Create OUTPUT folder using the clean base name
            app.OutputFolder = fullfile(pwd, [app.CurrentFileName '_Output']);
            if ~exist(app.OutputFolder, 'dir')
                mkdir(app.OutputFolder);
            end

             % Get data
             try
                 % Read from 'fullPath' instead of 'app.CurrentFileName'
                 % so the standalone app can find the file anywhere on the computer.
                 data_8x = readmatrix(fullPath, 'NumHeaderLines', app.NonDataLines);

             catch ME
                 uialert(app.UIFigure, ['Failed to read text data: ' ME.message], 'File Read Error');
             end            

            %line 197 is variable names
            %Header=['Time', "L_In", "L_Out","F_In", "F_Out", "Aux 1","Aux 2", "SL", "Triggers"];

            %extract time(column 1), length(column), force(column 4), stimulus (columns) data only
            %change time to MINUTES in raw data
            app.time_data=data_8x(app.Data_Start:app.Data_End,app.TimeColumn)./60000;
            app.length_data=data_8x(app.Data_Start:app.Data_End,app.LengthColumn);
            app.force_data=data_8x(app.Data_Start:app.Data_End,app.ForceColumn);
            app.stimulus_data=data_8x(app.Data_Start:app.Data_End,app.StimColumn);

            %Determine Initial Length (mm) is manually set or to be auto-detected
            if isempty(app.initial_length)
                app.initial_length=round (mean(app.length_data(100:500)),3);
            end

            %determine if triggers ar manually set or to be detected
            if isempty(app.triggerpts)
                %find points where length changes in the 8-step protocol
                df_length=ischange(smooth(app.length_data,6),'mean','Threshold',100);
                %determine locations of length changes
                app.trigger=find(df_length~=0);              
            else
                % Attempt to access the property
                app.trigger = app.triggerpts;                                   
            end
            
            %determine total number of stretches 
            app.trigger=app.trigger(app.trigger~= 0);
            %-1 as last number is end point
            app.total_stretches=length(app.trigger)-1;

            % Change options displayed in Stretch Listbox in App Designer
            newItems = arrayfun(@(x) ['Stretch_',num2str(x)], 1:app.total_stretches, 'UniformOutput', false);
            app.SelectStretchtoPlotAnalyzeListBox.Items=newItems;

            %plots to visualize the data
            %plot length curve
            figure (1)
            subplot(2,1,1)
            plot(app.time_data,app.length_data,'Color','k','HandleVisibility','off');
            title('Length');
            xlabel('Time (minutes)');
            ylabel('Length (mm)');

            %plot force curve
            subplot(2,1,2)
            plot(app.time_data,app.force_data,'HandleVisibility','off');
            title('Force');
            xlabel('Time (minutes)');
            ylabel('Force (mN)');

            %initialize arrays
            app.dist_beats_all=[];
            %app.avg_selected_beats=NaN(1001,app.total_stretches);
            app.avg_selected_beats=[];
            app.DataOutput=NaN(app.total_stretches,13);
            app.force_wo_peak=NaN(numel(app.force_data),1);
        end

        % Clicked callback: SelectStretchtoPlotAnalyzeListBox
        function SelectStretchtoPlotAnalyzeListBoxClicked(app, event)
            app.selectedstretch = event.InteractionInformation.Item;

            if app.selectedstretch == 1
                current_stretch=1;
            elseif app.selectedstretch == 2
                current_stretch=2;
            elseif app.selectedstretch == 3
                current_stretch=3;
            elseif app.selectedstretch == 4
                current_stretch=4;
            elseif app.selectedstretch == 5
                current_stretch=5;
            elseif app.selectedstretch == 6
                current_stretch=6;
            elseif app.selectedstretch == 7
                current_stretch=7;
            elseif app.selectedstretch == 8
                current_stretch=8;
            end

            %active/passive forces, time for contraction/relaxation, contraction/relaxation velocity, force integral, Poincare plot
            for i=current_stretch
                %current length, force and time data
                length_step=app.length_data(app.trigger(i,:)-100:app.trigger(i+1,:));
                time_step=app.time_data(app.trigger(i,:)-100:app.trigger(i+1,:))*60;
                force_step=app.force_data(app.trigger(i,:)-100:app.trigger(i+1,:));
                stimulus_step=app.stimulus_data(app.trigger(i,:)-100:app.trigger(i+1,:));   

                %find stimulus points where beat starts
                stimulus_locs=find(stimulus_step==app.StimValue);
                % Removes rows, so only one stimulus remains
                true_stim=diff(stimulus_locs)>1;
                stimulus_locs(true_stim == 0) = [];
                stimulus_locs=stimulus_locs(1:end-1);
                %calculate frequency of stimulation
                app.freq_stim=floor(median(diff(stimulus_locs)));

                %peaks
                %[contraction_peak, contraction_peak_locs]=findpeaks(smooth(force_step,25),'MinPeakProminence',0.05,'MinPeakDistance',900);
                %lower threshold
                [contraction_peak, contraction_peak_locs]=findpeaks(smooth(force_step,25),'MinPeakProminence',0.01,'MinPeakDistance',app.freq_stim*0.9);

                %calculate beats per min for current length
                bpm=nearest((numel(contraction_peak)*60000)/numel(time_step));

                                         
                %find equivalent points on y-axis to mark stimulus locations;
                movavg_peaks= movavg(smooth(force_step(1:end-100),25),'linear',app.freq_stim);
                y_match_peaks=movavg_peaks(app.freq_stim:app.freq_stim:end,:);
                y_match_peaks=resize(y_match_peaks, size(stimulus_locs));

                %plot to check for peaks
                plot(app.UIAxes,time_step,smooth(force_step,25),'DisplayName','Raw force data')
                hold(app.UIAxes,"on")
                plot(app.UIAxes,time_step(stimulus_locs),y_match_peaks,'|','MarkerSize',100,'LineWidth',1,'DisplayName','Stimulus location')
                %create a cell array of strings for labeling peak numbers
                labels = arrayfun(@num2str, 1:numel(stimulus_locs), 'UniformOutput', false);
                %label each peak with its corresponding number
                text(app.UIAxes,time_step(stimulus_locs),y_match_peaks,labels,'VerticalAlignment','top','FontSize',10);
                hold(app.UIAxes,"off")
                title(app.UIAxes,['Force vs time at length: ' num2str(round(mean(length_step(100:500))/app.initial_length,3)),'*L_0']);
                legend(app.UIAxes);
                xlabel(app.UIAxes,'Time (seconds)');
                ylabel(app.UIAxes,'Force(mN)');
                xlim(app.UIAxes,[time_step(stimulus_locs(1))-2 time_step(stimulus_locs(end))+2]);
                %xlim([time_step(contraction_peak_locs(1)-100) time_step(contraction_peak_locs(end)+500)]);

                % User selects peaks
                prompt = arrayfun(@(x) ['Enter Peak ', num2str(x)], 1:app.InputBeats, 'UniformOutput', false);
                input = arrayfun(@(x) labels{numel(labels)-x+1}, 1:app.InputBeats, 'UniformOutput', false);
                peak_positions = inputdlg(prompt, 'Choose peaks:', [1 45], string(input));
                peak_no = str2double(peak_positions);

                %force data for last ## peaks
                %initialize arrays to store calculated data
                height_peaks=NaN(app.InputBeats,1);
                valley_peaks=NaN(app.InputBeats,1);
                contraction_90pct_beat=NaN(app.InputBeats,1);
                contraction_75pct_beat=NaN(app.InputBeats,1);
                contraction_50pct_beat=NaN(app.InputBeats,1);
                relaxation_90pct_beat=NaN(app.InputBeats,1);
                relaxation_75pct_beat=NaN(app.InputBeats,1);
                relaxation_50pct_beat=NaN(app.InputBeats,1);
                integral_force_per_beat=NaN(app.InputBeats,1);
                last_n_beats=NaN(app.freq_stim+1,app.InputBeats);

                for k=1:app.InputBeats
                    last_n_peaks=smooth(force_step((stimulus_locs(peak_no(k))-app.freq_stim):(stimulus_locs(peak_no(k))),:),25);
                    last_n_beats(:,k)=last_n_peaks;

                    %TRY to detect peak
                    try
                    
                    %current peak
                    [current_active_peak, current_active_peak_locs]=findpeaks(last_n_peaks,'MinPeakProminence',0.01,'MinPeakDistance',0.9*app.freq_stim);

                    % %contraction duration
                    % peak_base1= 1;
                    % peak_base2= length(last_n_peaks);

                    %for active/passive force
                    %peak height
                    height_peaks(k,:) = current_active_peak;
                    %peak base
                    valley_peaks(k,:) = last_n_peaks(1);

                    %normalize the beat to baseline
                    norm_beat=last_n_peaks-last_n_peaks(1);

                    %calculate time of contraction
                    %time in ms
                    contraction_90pct_beat(k,:) = find(norm_beat(1:current_active_peak_locs)-(norm_beat(current_active_peak_locs)*0.9)>0,1,'first');
                    contraction_75pct_beat(k,:) = find(norm_beat(1:current_active_peak_locs)-(norm_beat(current_active_peak_locs)*0.75)>0,1,'first');
                    contraction_50pct_beat(k,:) = find(norm_beat(1:current_active_peak_locs)-(norm_beat(current_active_peak_locs)*0.5)>0,1,'first');

                    %calculate time of relaxation of last ## beats
                    %time in ms
                    relaxation_90pct_beat(k,:) = current_active_peak_locs+find(norm_beat(current_active_peak_locs:end)-(norm_beat(current_active_peak_locs)*0.1)<0,1,'first');
                    relaxation_75pct_beat(k,:) = current_active_peak_locs+find(norm_beat(current_active_peak_locs:end)-(norm_beat(current_active_peak_locs)*0.25)<0,1,'first');
                    relaxation_50pct_beat(k,:) = current_active_peak_locs+find(norm_beat(current_active_peak_locs:end)-(norm_beat(current_active_peak_locs)*0.5)<0,1,'first');

                    %force integral (in mN)
                    integral_force_per_beat(k,:)=trapz(norm_beat);

                    %plot each selected beat
                    figure(2)
                    subplot(app.total_stretches/2,2,i)
                    hold on
                    plot(last_n_peaks);
                    hold off
                    title(['Active force of selected beats at length: ' num2str(round(mean(length_step(100:500))/app.initial_length,3)), '*L_0']);
                    xlabel('Time (ms)');
                    ylabel('Force (mN)');
                    xlim([0 app.freq_stim]);

                    %if peak not detected
                    catch
                        height_peaks(k,:)=NaN;
                        valley_peaks(k,:)=NaN;
                    end
                end

                %avg selected beats
                avg_last_n_beats=mean(last_n_beats,2);

                %force integral for last ## beats in current step (in mN)
                integral_force_per_step=mean(integral_force_per_beat);

                %calculate time of contraction of last ## beats
                %time in ms
                contraction_90pct = mean(contraction_90pct_beat);
                contraction_75pct = mean(contraction_75pct_beat);
                contraction_50pct = mean(contraction_50pct_beat);

                %calculate time of relaxation of last ## beats
                %time in ms
                relaxation_90pct = mean(relaxation_90pct_beat);
                relaxation_75pct = mean(relaxation_75pct_beat);
                relaxation_50pct = mean(relaxation_50pct_beat);

                %change in contraction/relaxation velocity
                df_dt=sgolayfilt(diff(avg_last_n_beats),2,81);
                %in mN/s
                %peak max/min velocity
                contraction_velocity=max(df_dt)*1000;
                relaxation_velocity=abs(min(df_dt(100:end)))*1000;

                %peak max contraction/velocity
                figure(3)
                hold on
                plot(df_dt,'DisplayName',[num2str(round(mean(length_step(100:500))/app.initial_length,3)),'*L_0']);
                hold off
                title('Average velocity of contraction/relaxation');
                legend;
                xlabel('Time (ms)');
                ylabel('Velocity (mN/ms)');

                %for plot below
                time_beat=(1:numel(avg_last_n_beats)).';
                markers=([contraction_50pct, contraction_75pct, contraction_90pct, relaxation_50pct, relaxation_75pct, relaxation_90pct]).';
                norm_force=avg_last_n_beats-mean(valley_peaks);

                %if no peaks detected, create array with arbitrary value
                %for plotting figure 5 and not showing error
                peak_not_detected = any(isnan(markers));
                if peak_not_detected==1
                    fprintf('ONE OR MORE OF THE PEAKS ARE NOT DETECTED FOR CURRENT STRETCH, ##: %d\n', i-1);
                    markers=[1,1,1,1,1,1];
                end

                %plot average of last ## beats/peaks
                %normalize force to baseline (subtracted passive force force for each length change)
                %mark contraction/relaxation 50,75,90 percent values
                figure(4)
                RGB = orderedcolors("gem");
                hold on            
                plot(time_beat, norm_force,'DisplayName',[num2str(round(mean(length_step(100:500))/app.initial_length, 3)), '*L_0'])                
                %scatter plot for the marker points
                scatter(time_beat(round(markers)),(norm_force(round(markers))),50, 1:6, 'filled','HandleVisibility', 'off')
                colormap(RGB(1:6,:)) 
                hold off 
                %add legend for colors of markers as text on the plot
                ctext={'Contraction 50pct','Contraction 75pct','Contraction 90pct','Relaxation 50pct','Relaxation 75pct','Relaxation 90pct'};          
                x_start = 0.85;
                y_start = 0.60;
                for c = 1:6
                    text(x_start, y_start - (c * 0.05), ctext{c}, 'Units', 'normalized', 'Color', RGB(c, :), 'FontSize', 10);
                end
                title('Average time course of contraction/relaxation'); 
                legend;
                xlabel('Time (ms)');
                ylabel('Force (mN)');
                xlim([0 app.freq_stim]);              

                % POINCARE Plot
                % measure time between two contractions/peaks
                % plot the difference against itself
                % calculate the time between peaks
                dist_beats = diff(contraction_peak_locs);
                app.dist_beats_all = [app.dist_beats_all; dist_beats];
                rr=dist_beats(1:end-1);
                rrp1=dist_beats(2:end);

                % POINCARE plot per length change
                % plot the points
                figure(5);
                subplot(app.total_stretches/2,2,i);
                plot(rrp1,rr,'.');
                xlim([0.9*app.freq_stim 1.1*app.freq_stim]);
                ylim([0.9*app.freq_stim 1.1*app.freq_stim]);
                title(['Poincare plot at length: ' num2str(round(mean(length_step(100:500))/app.initial_length,3)), '*L_0']);
                xlabel('R_{n-1} to R_n Time Interval (ms)');
                ylabel({'R_n to R_{n+1}', 'Time Interval (ms)'});

                %create duplicate force step data array
                force_step_edit=smooth(force_step,25);
                %delete peaks/contractions from force step data with NaN
                %delete data from each stimulus to 50 ms beyond relaxation 90% calculated
                %refill array using median values of force around the peak deleted
                for p=1:numel(contraction_peak)
                    force_step_edit(stimulus_locs(p):stimulus_locs(p)+floor(relaxation_90pct)+50,:)=NaN;
                    force_step_edit = fillmissing(force_step_edit,"movmedian",500);
                end
                %re-create complete force data array without peaks
                app.force_wo_peak(app.trigger(i,:)-100:app.trigger(i+1,:))=force_step_edit;

                %plot force step data with and without peaks
                figure(6)
                subplot(app.total_stretches/2,2,i)
                h1=plot(time_step,smooth(force_step,25),'DisplayName','Raw force data',"HandleVisibility","off");
                hold on
                h2=plot(time_step(stimulus_locs),y_match_peaks,'|','MarkerSize',10,'LineWidth',0.5,'DisplayName','Stimulus location',"HandleVisibility","off");
                %plot data with peaks removed
                h3=plot(time_step,force_step_edit,'DisplayName','Active force removed',"HandleVisibility","off");
                hold off
                title(['Contractions/beats at length: ' num2str(round(mean(length_step(100:500))/app.initial_length,3)), '*L_0']);
                if i == 1
                    legend_handles = [h1, h2, h3];
                    lgd = legend(legend_handles,'FontSize',15);
                    lgd.Orientation = 'horizontal';
                    set(lgd, 'Position', [0.35, 0.01, 0.4, 0.03]);
                end
                xlabel('Time (s)');
                ylabel('Force(mN)');
                xlim(app.UIAxes,[time_step(stimulus_locs(1))-2 time_step(stimulus_locs(end))+2]);
                %xlim([time_step(contraction_peak_locs(1)-100) time_step(contraction_peak_locs(end)+500)]);

                %save average of selected beats 
                app.avg_selected_beats(i,:)=avg_last_n_beats;

                %HEADRERS=['Length','passive force','active force','contraction_90pct','contraction_75pct','contraction_50pct','relaxation_90pct','relaxation_75pct','relaxation_50pct','contraction velocity','relaxation velocity','force integral'];
                app.DataOutput(i,:) = round([mean(length_step(100:500)),mean(valley_peaks),mean(height_peaks-valley_peaks),bpm,contraction_90pct,contraction_75pct,contraction_50pct,relaxation_90pct,relaxation_75pct,relaxation_50pct,contraction_velocity,relaxation_velocity,integral_force_per_step],3);
            end

        end

        % Button pushed function: CombineSelectedStretchesButton
        function CombineSelectedStretchesButtonPushed(app, event)
            %plot force data (only from 8 stretches) with and without peaks
            figure(7)
            plot(app.force_data(app.trigger(1,:):app.trigger(end,:)),'DisplayName', 'Raw force data')
            hold on
            plot(app.force_wo_peak(app.trigger(1,:):app.trigger(end,:)),'DisplayName', 'Active force removed')
            hold off
            title('Force vs time with and without beats');
            legend;
            xlabel('Time (minutes)');
            ylabel('Force (mN)');     

            %work per beat per stretch (mN*ms)
            work=app.DataOutput(:,13).*app.DataOutput(:,1);
            %add to output excel
            app.DataOutput(:, 14) = round(work,3);

            %record change in length for Frank-Starling correction and Work/beat
            length_change=app.DataOutput(:,1)/app.initial_length;

            %active force for Length-Tension Relationship
            passive_force=app.DataOutput(:,2);
            active_force=app.DataOutput(:,3);
            [FSeffect1,FSstruct1]=polyfit(length_change,active_force,2);
            [FSeffect2,FSstruct2]=polyfit(length_change,passive_force,2);
            %Calculate fitted line
            [yfit1,~] = polyval(FSeffect1,length_change,FSstruct1);
            [yfit2,~] = polyval(FSeffect2,length_change,FSstruct2);

            %plot active force vs length
            figure(8);
            plot(length_change,active_force,'o','MarkerFaceColor', 'b', 'MarkerEdgeColor', 'b','DisplayName','Raw data')
            hold on
            plot(length_change, yfit1, '-','DisplayName','Second order polynonomial fit')
            hold off          
            title('Active force vs length');
            legend('Location','best');
            xlabel('Length / Inital Length (L/L_0)');
            ylabel('Active Force (mN)');  

            %plot passive force vs length
            figure(9);
            plot(length_change,passive_force,'o','MarkerFaceColor', 'b', 'MarkerEdgeColor', 'b','DisplayName','Raw data')
            hold on
            plot(length_change, yfit2, '-','DisplayName','Second order polynonomial fit')
            hold off
            title('Passive force vs length');
            legend('Location','best');
            xlabel('Length / Inital Length (L/L_0)');
            ylabel('Passive Force (mN)');    
            
            %POINCARE Plot 2 (for all beats)
            RR=app.dist_beats_all(1:end-1);
            RRp1=app.dist_beats_all(2:end);
            %SD1:short-term variability
            %SD1=round(std(sqrt((((RR-RRp1)/sqrt(2)).^2)/(length(RR)-1))),3);
            SD1=round(std(RR-RRp1)/sqrt(2),3);
            %SD2:long-term variability
            %SD2=round(std(sqrt((((RR+RRp1-(2*mean(dist_beats_all)))/sqrt(2)).^2)/(length(RR)-1))),3);
            SD2=round(std(RR+RRp1)/sqrt(2),3);
            %mean variability in beats
            mean_RR = mean(RR);
            %SD12:ratio short/long variability
            SD12=round(SD1/SD2,3);
            %add to output excel
            app.DataOutput(1, 15:17) = [SD1, SD2, SD12];           
            % Draw the Identity Line (Line of Symmetry, x = y)
            min_val = min([RR; RRp1]) - 50;
            max_val = max([RR; RRp1]) + 50;           
            % Generate Ellipse Coordinates
            % Create an array of angles from 0 to 2*pi
            theta = linspace(0, 2*pi, 200);
            % Standard ellipse equation centered at origin
            x_ellipse = SD2 * cos(theta);
            y_ellipse = SD1 * sin(theta);
            % Rotate ellipse by 45 degrees to align with identity line
            % And translate center to (mean_RR, mean_RR)
            ellipse_matrix = [cos(pi/4), -sin(pi/4); sin(pi/4), cos(pi/4)] * [x_ellipse; y_ellipse];
            rotated_x = ellipse_matrix(1, :) + mean_RR;
            rotated_y = ellipse_matrix(2, :) + mean_RR;           

            %plot
            figure(10);
            hold on
            plot(RRp1,RR,'.');
            % Plot the Identity Line, Ellipse and Center Point
            plot([min_val, max_val], [min_val, max_val], '--', 'Color', [0.5 0.5 0.5], 'LineWidth', 1.5);
            plot(rotated_x, rotated_y, 'r-', 'LineWidth', 2.5);            
            plot(mean_RR, mean_RR, 'ro', 'MarkerFaceColor', 'r', 'MarkerSize', 8);            
            hold off
            xlim([0.9*app.freq_stim 1.1*app.freq_stim]);
            ylim([0.9*app.freq_stim 1.1*app.freq_stim]);
            title('Poincare plot');
            xlabel('R_{n-1} to R_n Time Interval (ms)');
            ylabel({'R_n to R_{n+1} Time Interval (ms)'});
            txt = ['Short-term Variability: ' num2str(SD1) ' & Long-term Variability: ' num2str(SD2)];
            text(920,1080,txt);            
            legend('RR Intervals', 'Identity Line (x=y)', 'HRV Ellipse', 'Center (Mean)', 'Location', 'best');
            axis square; % Ensures geometry isn't visually distorted        
            hold off;
        end

        % Button pushed function: SaveDataandFiguresButton
        function SaveDataandFiguresButtonPushed(app, event)
            %save data
            DataOutput_with_nans = standardizeMissing(app.DataOutput, 0);
            output_data=array2table(DataOutput_with_nans);
            output_data.Properties.VariableNames={'Length(mm)','Passive_Force(mN)','Active_Force(mN)','BPM','Contraction_90pct(ms)','Contraction_75pct(ms)','Contraction_50pct(ms)','Relaxation_90pct(ms)','Relaxation_75pct(ms)','Relaxation_50pct(ms)','Contraction_Velocity(mNperms)','Relaxation_Velocity(mNperms)','Force_Integral(mN)','Work(mN.mm)','SD1','SD2','SD12'};
            %output_data.Properties.RowNames={'L+2.5%L','L+5.0%L','L+7.5%L','L+10.0%L','L+12.5%L','L+15.0%L','L+17.5%L','L+20.0%L'};
            writetable(output_data,[app.CurrentFileName '_output'],'Delimiter','\t');

            %save force data with peaks removed separately
            writematrix(app.force_data(app.trigger(1,:):app.trigger(end,:)),fullfile(app.OutputFolder,[app.CurrentFileName '_force_wo_peaks_data', '.csv']));

            %save average pf selected beats data separately
            writematrix(app.avg_selected_beats,fullfile(app.OutputFolder,[app.CurrentFileName '_average_selected_beats_per_length', '.csv']));

            % Save plots as png
            save_plots = @(fig, name) saveas(fig, fullfile(app.OutputFolder, [app.CurrentFileName, name, '.png']), 'png');
            save_plots(figure(1), '_length_and_force'); 
            save_plots(figure(2), '_selected_beats');
            save_plots(figure(3), '_avg_velocity');
            save_plots(figure(4), '_avg_time_course');
            save_plots(figure(5), '_poincarep_lot_per_length');
            save_plots(figure(6), '_force_step_w and_wo_peaks_per_length');
            save_plots(figure(7), '_force_data_w_and_wo_peaks');
            save_plots(figure(8), '_active_force_vs_length');
            save_plots(figure(9), '_passive_force_vs_length');
            save_plots(figure(10), '_poincare_plot');

            %Save plots as eps
            save_plots = @(fig, name) saveas(fig, fullfile(app.OutputFolder, [app.CurrentFileName, name, '.eps']), 'eps');
            save_plots(figure(1), '_length_and_force'); 
            save_plots(figure(2), '_selected_beats');
            save_plots(figure(3), '_avg_velocity');
            save_plots(figure(4), '_avg_time_course');
            save_plots(figure(5), '_poincarep_lot_per_length');
            save_plots(figure(6), '_force_step_w and_wo_peaks_per_length');
            save_plots(figure(7), '_force_data_w_and_wo_peaks');
            save_plots(figure(8), '_active_force_vs_length');
            save_plots(figure(9), '_passive_force_vs_length');
            save_plots(figure(10), '_poincare_plot');

            uialert(app.UIFigure,'All files and figures saved',"Complete","Icon","success");
        end

        % Button pushed function: NextFileButton
        function NextFileButtonPushed(app, event)
            cla(app.UIAxes,'reset')        
            close all 
            clear global
        end

        % Value changed function: EditField
        function EditFieldValueChanged(app, event)
            app.group1value = app.EditField.Value;            
        end

        % Button pushed function: Group1Button
        function Group1ButtonPushed(app, event)
            % Open and select file(s) to analyze
            [file, path] = uigetfile('*.txt*', 'Select One or More Files', 'MultiSelect', 'on');

            % Check if the user canceled the dialog
            if isequal(file, 0) || isequal(path, 0)
                uialert(app.UIFigure, 'No files were selected.', 'Canceled');
                return;
            end

            % Convert to a cell array if only one file was selected
            if ischar(file) || isstring(file)
                file = {file};
            end

            % Initialize variables
            total = length(file);
            header_name = cell(1, total); % Changed to cell array to properly hold variable names for later table conversion

            % Combine file name and path into a single absolute path
            for i = 1:total
                filename = file{i};

                % Build complete file path
                fullPath = fullfile(path, filename);

                % Read the data
                try
                    data = readtable(fullPath, 'VariableNamingRule', 'preserve');

                    % Extract file name without extension to use as header
                    [~, nameOnly, ~] = fileparts(filename);
                    header_name{i} = nameOnly;

                    % Combine columns
                    for p = 1:length(app.excel_tabs)
                        % Convert table columns to cell arrays if mixing types, or extract raw data
                        currentData = data.(app.excel_tabs{p});
                        if istable(currentData) || isvector(currentData)
                            % Ensure appending works uniformly
                            app.combined_group1{p} = [app.combined_group1{p}, currentData];
                        end
                    end
                catch ME
                    uialert(app.UIFigure, sprintf('Error reading file: %s\n%s', file{i}, ME.message), 'File Error');
                end
            end

            % Save data to Excel
            for i = 1:length(app.excel_tabs)
                % Convert cell array data into a table with proper headers
                outputTable = array2table(app.combined_group1{i}, 'VariableNames', header_name);
                writetable(outputTable, [app.group1value '.xlsx'], 'Sheet', app.excel_tabs{i}, 'WriteMode', 'overwritesheet');
            end


            %fit median of all data to second order polynomial
            y_fit=NaN(length(app.excel_tabs),100);
            for f=2:length(app.combined_group1)
                poly = polyfit(median(app.combined_group1{1},2), median(app.combined_group1{f},2), 2);
                x_fit = linspace(min(median(app.combined_group1{1},2)), max(median(app.combined_group1{1},2)), 100);
                y_fit(f,:) = polyval(poly, x_fit);
            end


            %plot data
            %plot(app.UIAxes2,app.combined_group1{2},"*","Color",'b')
            hold(app.UIAxes2,"on")
            plot(app.UIAxes2,median(app.combined_group1{1},2),median(app.combined_group1{2},2),"*","Color",'b')
            plot(app.UIAxes2,x_fit, y_fit(2,:), '-', 'LineWidth', 2, "Color",'b');
            hold(app.UIAxes2,"off")
            title(app.UIAxes2,'Passive Force');
            xlabel(app.UIAxes2,'Length (mm)');
            ylabel(app.UIAxes2,'Force (mN)');

            %plot(app.UIAxes3,app.combined_group1{3},"*","Color",'b')
            hold(app.UIAxes3,"on")
            plot(app.UIAxes3,median(app.combined_group1{1},2),median(app.combined_group1{3},2),"*","Color",'b')
            plot(app.UIAxes3,x_fit, y_fit(3,:), '-', 'LineWidth', 2, "Color",'b');
            hold(app.UIAxes3,"off")
            title(app.UIAxes3,'Active Force');
            xlabel(app.UIAxes3,'Length (mm)');
            ylabel(app.UIAxes3,'Force (mN)');

            %plot(app.UIAxes4,app.combined_group1{11},"*","Color",'b')
            hold(app.UIAxes4,"on")
            plot(app.UIAxes4,median(app.combined_group1{1},2),median(app.combined_group1{11},2),"*","Color",'b')
            plot(app.UIAxes4,x_fit, y_fit(11,:), '-', 'LineWidth', 2, "Color",'b');
            hold(app.UIAxes4,"off")
            title(app.UIAxes4,'Contraction Velocity');
            xlabel(app.UIAxes4,'Length (mm)');
            ylabel(app.UIAxes4,'Velocity (mN/ms)');

            %plot(app.UIAxes5,app.combined_group1{12},"*","Color",'b')
            hold(app.UIAxes5,"on")
            plot(app.UIAxes5,median(app.combined_group1{1},2),median(app.combined_group1{12},2),"*","Color",'b')
            plot(app.UIAxes5,x_fit, y_fit(12,:), '-', 'LineWidth', 2, "Color",'b');
            hold(app.UIAxes5,"off")
            title(app.UIAxes5,'Relaxation Velocity');
            xlabel(app.UIAxes5,'Length (mm)');
            ylabel(app.UIAxes5,'Velocity (mN/ms)');

            %plot(app.UIAxes6,app.combined_group1{13},"*","Color",'b')
            hold(app.UIAxes6,"on")
            plot(app.UIAxes6,median(app.combined_group1{1},2),median(app.combined_group1{13},2),"*","Color",'b')
            plot(app.UIAxes6,x_fit, y_fit(13,:), '-', 'LineWidth', 2, "Color",'b');
            hold(app.UIAxes6,"off")
            title(app.UIAxes6,'Force Integral');
            xlabel(app.UIAxes6,'Length (mm)');
            ylabel(app.UIAxes6,'Force Integral (mN)');
        end

        % Value changed function: EditField2
        function EditField2ValueChanged(app, event)
            app.group2value = app.EditField2.Value;
        end

        % Button pushed function: Group2Button
        function Group2ButtonPushed(app, event)
            % Open and select file(s) to analyze
            [file, path] = uigetfile('*.txt*', 'Select One or More Files', 'MultiSelect', 'on');

            % Check if the user canceled the dialog
            if isequal(file, 0) || isequal(path, 0)
                uialert(app.UIFigure, 'No files were selected.', 'Canceled');
                return;
            end

            % Convert to a cell array if only one file was selected
            if ischar(file) || isstring(file)
                file = {file};
            end         

            % Initialize variables
            total = length(file);
            header_name = cell(1, total); % Changed to cell array to properly hold variable names for later table conversion

            % Combine file name and path into a single absolute path
            for i = 1:total
                filename = file{i};

                % Build complete file path
                fullPath = fullfile(path, filename);

                % Read the data
                try
                    data = readtable(fullPath, 'VariableNamingRule', 'preserve');

                    % Extract file name without extension to use as header
                    [~, nameOnly, ~] = fileparts(filename);
                    header_name{i} = nameOnly;

                    % Combine columns
                    for p = 1:length(app.excel_tabs)
                        % Convert table columns to cell arrays if mixing types, or extract raw data
                        currentData = data.(app.excel_tabs{p});
                        if istable(currentData) || isvector(currentData)
                            % Ensure appending works uniformly
                            app.combined_group2{p} = [app.combined_group2{p}, currentData];
                        end
                    end
                catch ME
                    uialert(app.UIFigure, sprintf('Error reading file: %s\n%s', file{i}, ME.message), 'File Error');
                end
            end

            % Save data to Excel
            for i = 1:length(app.excel_tabs)
                % Convert cell array data into a table with proper headers
                outputTable = array2table(app.combined_group2{i}, 'VariableNames', header_name);
                writetable(outputTable, [app.group2value '.xlsx'], 'Sheet', app.excel_tabs{i}, 'WriteMode', 'overwritesheet');
            end  

            %fit median of all data to second order polynomial
            y_fit=NaN(length(app.excel_tabs),100);
            for f=2:length(app.combined_group2)
                poly = polyfit(median(app.combined_group2{1},2), median(app.combined_group2{f},2), 2);
                x_fit = linspace(min(median(app.combined_group2{1},2)), max(median(app.combined_group2{1},2)), 100);
                y_fit(f,:) = polyval(poly, x_fit);
            end


            %plot data
            hold(app.UIAxes2, "on")
            %plot(app.UIAxes2,app.combined_group2{2},"+","Color",'g')
            plot(app.UIAxes2,median(app.combined_group2{1},2),median(app.combined_group2{2},2),"+","Color",'g')
            plot(app.UIAxes2,x_fit, y_fit(2,:), '-', 'LineWidth', 2, "Color",'g');
            hold(app.UIAxes2, "off")
            title(app.UIAxes2,'Passive Force');
            xlabel(app.UIAxes2,'Length (mm)');
            ylabel(app.UIAxes2,'Force (mN)');           

            hold(app.UIAxes3, "on")
            %plot(app.UIAxes3,app.combined_group2{3},"+","Color",'g')
            plot(app.UIAxes3,median(app.combined_group2{1},2),median(app.combined_group2{3},2),"+","Color",'g')
            plot(app.UIAxes3,x_fit, y_fit(3,:), '-', 'LineWidth', 2, "Color",'g');
            hold(app.UIAxes3, "off")
            title(app.UIAxes3,'Active Force');
            xlabel(app.UIAxes3,'Length (mm)');
            ylabel(app.UIAxes3,'Force (mN)');           

            hold(app.UIAxes4, "on")
            %plot(app.UIAxes4,app.combined_group2{11},"+","Color",'g')
            plot(app.UIAxes4,median(app.combined_group2{1},2),median(app.combined_group2{11},2),"+","Color",'g')
            plot(app.UIAxes4,x_fit, y_fit(11,:), '-', 'LineWidth', 2, "Color",'g');
            hold(app.UIAxes4, "off")
            title(app.UIAxes4,'Contraction Velocity');
            xlabel(app.UIAxes4,'Length (mm)');
            ylabel(app.UIAxes4,'Velocity (mN/ms)');          

            hold(app.UIAxes5, "on")
            %plot(app.UIAxes5,app.combined_group2{12},"+","Color",'g')
            plot(app.UIAxes5,median(app.combined_group2{1},2),median(app.combined_group2{12},2),"+","Color",'g')
            plot(app.UIAxes5,x_fit, y_fit(12,:), '-', 'LineWidth', 2, "Color",'g');
            hold(app.UIAxes5, "off")
            title(app.UIAxes5,'Relaxation Velocity');
            xlabel(app.UIAxes5,'Length (mm)');
            ylabel(app.UIAxes5,'Velocity (mN/ms)');           

            hold(app.UIAxes6, "on")
            %plot(app.UIAxes6,app.combined_group2{13},"+","Color",'g')
            plot(app.UIAxes6,median(app.combined_group2{1},2),median(app.combined_group2{13},2),"+","Color",'g')
            plot(app.UIAxes6,x_fit, y_fit(13,:), '-', 'LineWidth', 2, "Color",'g');
            hold(app.UIAxes6, "off")
            title(app.UIAxes6,'Force Integral');
            xlabel(app.UIAxes6,'Length (mm)');
            ylabel(app.UIAxes6,'Force Integral (mN)');                        
        end

        % Value changed function: EditField3
        function EditField3ValueChanged(app, event)
            app.group3value = app.EditField3.Value;           
        end

        % Button pushed function: Group3Button
        function Group3ButtonPushed2(app, event)
            % Open and select file(s) to analyze
            [file, path] = uigetfile('*.txt*', 'Select One or More Files', 'MultiSelect', 'on');

            % Check if the user canceled the dialog
            if isequal(file, 0) || isequal(path, 0)
                uialert(app.UIFigure, 'No files were selected.', 'Canceled');
                return;
            end

            % Convert to a cell array if only one file was selected
            if ischar(file) || isstring(file)
                file = {file};
            end
           
            % Initialize variables
            total = length(file);
            header_name = cell(1, total); % Changed to cell array to properly hold variable names for later table conversion

            % Combine file name and path into a single absolute path
            for i = 1:total
                filename = file{i};

                % Build complete file path
                fullPath = fullfile(path, filename);

                % Read the data
                try
                    data = readtable(fullPath, 'VariableNamingRule', 'preserve');

                    % Extract file name without extension to use as header
                    [~, nameOnly, ~] = fileparts(filename);
                    header_name{i} = nameOnly;

                    % Combine columns
                    for p = 1:length(app.excel_tabs)
                        % Convert table columns to cell arrays if mixing types, or extract raw data
                        currentData = data.(app.excel_tabs{p});
                        if istable(currentData) || isvector(currentData)
                            % Ensure appending works uniformly
                            app.combined_group3{p} = [app.combined_group3{p}, currentData];
                        end
                    end
                catch ME
                    uialert(app.UIFigure, sprintf('Error reading file: %s\n%s', file{i}, ME.message), 'File Error');
                end
            end

            % Save data to Excel
            for i = 1:length(app.excel_tabs)
                % Convert cell array data into a table with proper headers
                outputTable = array2table(app.combined_group3{i}, 'VariableNames', header_name);
                writetable(outputTable, [app.group3value '.xlsx'], 'Sheet', app.excel_tabs{i}, 'WriteMode', 'overwritesheet');
            end  

            %fit median of all data to second order polynomial
            y_fit=NaN(length(app.excel_tabs),100);
            for f=2:length(app.combined_group3)
                poly = polyfit(median(app.combined_group3{1},2), median(app.combined_group3{f},2), 2);
                x_fit = linspace(min(median(app.combined_group3{1},2)), max(median(app.combined_group3{1},2)), 100);
                y_fit(f,:) = polyval(poly, x_fit);
            end


            %plot data
            hold(app.UIAxes2, "on")
            %plot(app.UIAxes2,app.combined_group3{2},"x","Color",'r')
            plot(app.UIAxes2,median(app.combined_group3{1},2),median(app.combined_group3{2},2),"x","Color",'m')
            plot(app.UIAxes2,x_fit, y_fit(2,:), '-', 'LineWidth', 2, "Color",'m');
            hold(app.UIAxes2, "off")
            title(app.UIAxes2,'Passive Force');
            xlabel(app.UIAxes2,'Length (mm)');
            ylabel(app.UIAxes2,'Force (mN)');            

            hold(app.UIAxes3, "on")
            % plot(app.UIAxes3,app.combined_group3{3},"x","Color",'r')
            plot(app.UIAxes3,median(app.combined_group3{1},2),median(app.combined_group3{3},2),"x","Color",'m')
            plot(app.UIAxes3,x_fit, y_fit(3,:), '-', 'LineWidth', 2, "Color",'m');
            hold(app.UIAxes3, "off")
            title(app.UIAxes3,'Active Force');
            xlabel(app.UIAxes3,'Length (mm)');
            ylabel(app.UIAxes3,'Force (mN)');         

            hold(app.UIAxes4, "on")
            % plot(app.UIAxes4,app.combined_group3{11},"x","Color",'r')
            plot(app.UIAxes4,median(app.combined_group3{1},2),median(app.combined_group3{11},2),"x","Color",'m')
            plot(app.UIAxes4,x_fit, y_fit(11,:), '-', 'LineWidth', 2, "Color",'m');
            hold(app.UIAxes4, "off")
            title(app.UIAxes4,'Contraction Velocity');
            xlabel(app.UIAxes4,'Length (mm)');
            ylabel(app.UIAxes4,'Velocity (mN/ms)');            

            hold(app.UIAxes5, "on")
            % plot(app.UIAxes5,app.combined_group3{12},"x","Color",'r')
            plot(app.UIAxes5,median(app.combined_group3{1},2),median(app.combined_group3{12},2),"x","Color",'m')
            plot(app.UIAxes5,x_fit, y_fit(12,:), '-', 'LineWidth', 2, "Color",'m');
            hold(app.UIAxes5, "off")
            title(app.UIAxes5,'Relaxation Velocity');
            xlabel(app.UIAxes5,'Length (mm)');
            ylabel(app.UIAxes5,'Velocity (mN/ms)');
            
            hold(app.UIAxes6, "on")
            % plot(app.UIAxes6,app.combined_group3{13},"x","Color",'r')
            plot(app.UIAxes6,median(app.combined_group3{1},2),median(app.combined_group3{13},2),"x","Color",'m')
            plot(app.UIAxes6,x_fit, y_fit(13,:), '-', 'LineWidth', 2, "Color",'m');
            hold(app.UIAxes6, "off")
            title(app.UIAxes6,'Force Integral');
            xlabel(app.UIAxes6,'Length (mm)');
            ylabel(app.UIAxes6,'Force Integral (mN)');   
        end

        % Clicked callback: OptionalGraphsListBox
        function OptionalGraphsListBoxClicked(app, event)
            app.optional_graph = event.InteractionInformation.Item;


            if app.optional_graph == 1
                cla(app.UIAxes7,'reset')
                cla(app.UIAxes8,'reset')
                cla(app.UIAxes9,'reset')

                %fit median of all data to second order polynomial
                y_fit1=NaN(length(app.excel_tabs),100);
                if ~isempty(app.combined_group1) && ~isempty(app.combined_group1{1}) && iscell(app.combined_group1) && length(app.combined_group1) >= 2
                    for f=2:length(app.combined_group1)
                        poly1 = polyfit(median(app.combined_group1{1},2), median(app.combined_group1{f},2), 2);
                        x_fit1 = linspace(min(median(app.combined_group1{1},2)), max(median(app.combined_group1{1},2)), 100);
                        y_fit1(f,:) = polyval(poly1, x_fit1);
                    end

                    hold(app.UIAxes7, "on")
                    %plot(app.UIAxes7,app.combined_group1{5},"*","Color",'b')
                    plot(app.UIAxes7,median(app.combined_group1{1},2),median(app.combined_group1{5},2),"*","Color",'b')
                    plot(app.UIAxes7,x_fit1, y_fit1(5,:), '-', 'LineWidth', 2, "Color",'b');
                    hold(app.UIAxes7, "off")
                    title(app.UIAxes7,'Time for Contraction: 50%');
                    xlabel(app.UIAxes7,'Length (mm)');
                    ylabel(app.UIAxes7,'Time (ms)');

                    hold(app.UIAxes8, "on")
                    % plot(app.UIAxes8,app.combined_group1{6},"*","Color",'b')
                    plot(app.UIAxes8,median(app.combined_group1{1},2),median(app.combined_group1{6},2),"*","Color",'b')
                    plot(app.UIAxes8,x_fit1, y_fit1(6,:), '-', 'LineWidth', 2, "Color",'b');
                    hold(app.UIAxes8, "off")
                    title(app.UIAxes8,'Time for Contraction: 75%');
                    xlabel(app.UIAxes8,'Length (mm)');
                    ylabel(app.UIAxes8,'Time (ms)');

                    hold(app.UIAxes9, "on")
                    % plot(app.UIAxes9,app.combined_group1{7},"*","Color",'b')
                    plot(app.UIAxes9,median(app.combined_group1{1},2),median(app.combined_group1{7},2),"*","Color",'b')
                    plot(app.UIAxes9,x_fit1, y_fit1(7,:), '-', 'LineWidth', 2, "Color",'b');
                    hold(app.UIAxes9, "off")
                    title(app.UIAxes9,'Time for Contraction: 90%');
                    xlabel(app.UIAxes9,'Length (mm)');
                    ylabel(app.UIAxes9,'Time (ms)');
                end

                %fit median of all data to second order polynomial
                y_fit2=NaN(length(app.excel_tabs),100);
                if ~isempty(app.combined_group2) && ~isempty(app.combined_group2{1}) && iscell(app.combined_group2) && length(app.combined_group2) >= 2
                    for f=2:length(app.combined_group2)
                        poly2 = polyfit(median(app.combined_group2{1},2), median(app.combined_group2{f},2), 2);
                        x_fit2 = linspace(min(median(app.combined_group2{1},2)), max(median(app.combined_group2{1},2)), 100);
                        y_fit2(f,:) = polyval(poly2, x_fit2);
                    end

                    hold(app.UIAxes7, "on")
                    %plot(app.UIAxes7,app.combined_group2{5},"+","Color",'g')
                    plot(app.UIAxes7,median(app.combined_group2{1},2),median(app.combined_group2{5},2),"+","Color",'g')
                    plot(app.UIAxes7,x_fit2, y_fit2(5,:), '-', 'LineWidth', 2, "Color",'g');
                    hold(app.UIAxes7, "off")
                    title(app.UIAxes7,'Time for Contraction: 50%');
                    xlabel(app.UIAxes7,'Length (mm)');
                    ylabel(app.UIAxes7,'Time (ms)');

                    hold(app.UIAxes8, "on")
                    % plot(app.UIAxes8,app.combined_group2{6},"+","Color",'g')
                    plot(app.UIAxes8,median(app.combined_group2{1},2),median(app.combined_group2{6},2),"+","Color",'g')
                    plot(app.UIAxes8,x_fit2, y_fit2(6,:), '-', 'LineWidth', 2, "Color",'g');
                    hold(app.UIAxes8, "off")
                    title(app.UIAxes8,'Time for Contraction: 75%');
                    xlabel(app.UIAxes8,'Length (mm)');
                    ylabel(app.UIAxes8,'Time (ms)');

                    hold(app.UIAxes9, "on")
                    % plot(app.UIAxes9,app.combined_group2{7},"+","Color",'g')
                    plot(app.UIAxes9,median(app.combined_group2{1},2),median(app.combined_group2{7},2),"+","Color",'g')
                    plot(app.UIAxes9,x_fit2, y_fit2(7,:), '-', 'LineWidth', 2, "Color",'g');
                    hold(app.UIAxes9, "off")
                    title(app.UIAxes9,'Time for Contraction: 90%');
                    xlabel(app.UIAxes9,'Length (mm)');
                    ylabel(app.UIAxes9,'Time (ms)');
                end

                %fit median of all data to second order polynomial
                y_fit3=NaN(length(app.excel_tabs),100);
                if ~isempty(app.combined_group3) && ~isempty(app.combined_group3{1}) && iscell(app.combined_group3) && length(app.combined_group3) >= 2
                    for f=2:length(app.combined_group3)
                        poly3 = polyfit(median(app.combined_group3{1},2), median(app.combined_group3{f},2), 2);
                        x_fit3 = linspace(min(median(app.combined_group3{1},2)), max(median(app.combined_group3{1},2)), 100);
                        y_fit3(f,:) = polyval(poly3, x_fit3);
                    end

                    hold(app.UIAxes7, "on")
                    %plot(app.UIAxes7,app.combined_group3{5},"x","Color",'r')
                    plot(app.UIAxes7,median(app.combined_group3{1},2),median(app.combined_group3{5},2),"x","Color",'m')
                    plot(app.UIAxes7,x_fit3, y_fit3(5,:), '-', 'LineWidth', 2, "Color",'m');
                    hold(app.UIAxes7, "off")
                    title(app.UIAxes7,'Time for Contraction: 50%');
                    xlabel(app.UIAxes7,'Length (mm)');
                    ylabel(app.UIAxes7,'Time (ms)');

                    hold(app.UIAxes8, "on")
                    % plot(app.UIAxes8,app.combined_group3{6},"x","Color",'r')
                    plot(app.UIAxes8,median(app.combined_group3{1},2),median(app.combined_group3{6},2),"x","Color",'m')
                    plot(app.UIAxes8,x_fit3, y_fit3(6,:), '-', 'LineWidth', 2, "Color",'m');
                    hold(app.UIAxes8, "off")
                    title(app.UIAxes8,'Time for Contraction: 75%');
                    xlabel(app.UIAxes8,'Length (mm)');
                    ylabel(app.UIAxes8,'Time (ms)');

                    hold(app.UIAxes9, "on")
                    % plot(app.UIAxes9,app.combined_group3{7},"x","Color",'r')
                    plot(app.UIAxes9,median(app.combined_group3{1},2),median(app.combined_group3{7},2),"x","Color",'m')
                    plot(app.UIAxes9,x_fit3, y_fit3(7,:), '-', 'LineWidth', 2, "Color",'m');
                    hold(app.UIAxes9, "off")
                    title(app.UIAxes9,'Time for Contraction: 90%');
                    xlabel(app.UIAxes9,'Length (mm)');
                    ylabel(app.UIAxes9,'Time (ms)');
                end

                

            elseif app.optional_graph == 2
                cla(app.UIAxes7,'reset')
                cla(app.UIAxes8,'reset')
                cla(app.UIAxes9,'reset')

                %fit median of all data to second order polynomial
                y_fit1=NaN(length(app.excel_tabs),100);
                if ~isempty(app.combined_group1) && ~isempty(app.combined_group1{1}) && iscell(app.combined_group1) && length(app.combined_group1) >= 2
                    for f=2:length(app.combined_group1)
                        poly1 = polyfit(median(app.combined_group1{1},2), median(app.combined_group1{f},2), 2);
                        x_fit1 = linspace(min(median(app.combined_group1{1},2)), max(median(app.combined_group1{1},2)), 100);
                        y_fit1(f,:) = polyval(poly1, x_fit1);
                    end

                    hold(app.UIAxes7, "on")
                    %plot(app.UIAxes7,app.combined_group1{8},"*","Color",'b')
                    plot(app.UIAxes7,median(app.combined_group1{1},2),median(app.combined_group1{10},2),"*","Color",'b')
                    plot(app.UIAxes7,x_fit1, y_fit1(8,:), '-', 'LineWidth', 2, "Color",'b');
                    hold(app.UIAxes7, "off")
                    title(app.UIAxes7,'Time for Relaxation: 50%');
                    xlabel(app.UIAxes7,'Length (mm)');
                    ylabel(app.UIAxes7,'Time (ms)');

                    hold(app.UIAxes8, "on")
                    %plot(app.UIAxes8,app.combined_group1{9},"*","Color",'b')
                    plot(app.UIAxes8,median(app.combined_group1{1},2),median(app.combined_group1{9},2),"*","Color",'b')
                    plot(app.UIAxes8,x_fit1, y_fit1(9,:), '-', 'LineWidth', 2, "Color",'b');
                    hold(app.UIAxes8, "off")
                    title(app.UIAxes8,'Time for Relaxation: 75%');
                    xlabel(app.UIAxes8,'Length (mm)');
                    ylabel(app.UIAxes8,'Time (ms)');

                    hold(app.UIAxes9, "on")
                    %plot(app.UIAxes9,app.combined_group1{10},"*","Color",'b')
                    plot(app.UIAxes9,median(app.combined_group1{1},2),median(app.combined_group1{8},2),"*","Color",'b')
                    plot(app.UIAxes9,x_fit1, y_fit1(10,:), '-', 'LineWidth', 2, "Color",'b');
                    hold(app.UIAxes9, "off")
                    title(app.UIAxes9,'Time for Relaxation: 90%');
                    xlabel(app.UIAxes9,'Length (mm)');
                    ylabel(app.UIAxes9,'Time (ms)');
                end

                %fit median of all data to second order polynomial
                y_fit2=NaN(length(app.excel_tabs),100);
                if ~isempty(app.combined_group2) && ~isempty(app.combined_group2{1}) && iscell(app.combined_group2) && length(app.combined_group2) >= 2
                    for f=2:length(app.combined_group2)
                        poly2 = polyfit(median(app.combined_group2{1},2), median(app.combined_group2{f},2), 2);
                        x_fit2 = linspace(min(median(app.combined_group2{1},2)), max(median(app.combined_group2{1},2)), 100);
                        y_fit2(f,:) = polyval(poly2, x_fit2);
                    end

                    hold(app.UIAxes7, "on")
                    %plot(app.UIAxes7,app.combined_group2{8},"+","Color",'g')
                    plot(app.UIAxes7,median(app.combined_group2{1},2),median(app.combined_group2{10},2),"+","Color",'g')
                    plot(app.UIAxes7,x_fit2, y_fit2(8,:), '-', 'LineWidth', 2, "Color",'g');
                    hold(app.UIAxes7, "off")
                    title(app.UIAxes7,'Time for Relaxation: 50%');
                    xlabel(app.UIAxes7,'Length (mm)');
                    ylabel(app.UIAxes7,'Time (ms)');

                    hold(app.UIAxes8, "on")
                    %plot(app.UIAxes8,app.combined_group2{9},"+","Color",'g')
                    plot(app.UIAxes8,median(app.combined_group2{1},2),median(app.combined_group2{9},2),"+","Color",'g')
                    plot(app.UIAxes8,x_fit2, y_fit2(9,:), '-', 'LineWidth', 2, "Color",'g');
                    hold(app.UIAxes8, "off")
                    title(app.UIAxes8,'Time for Relaxation: 75%');
                    xlabel(app.UIAxes8,'Length (mm)');
                    ylabel(app.UIAxes8,'Time (ms)');

                    hold(app.UIAxes9, "on")
                    %plot(app.UIAxes9,app.combined_group2{10},"+","Color",'g')
                    plot(app.UIAxes9,median(app.combined_group2{1},2),median(app.combined_group2{8},2),"+","Color",'g')
                    plot(app.UIAxes9,x_fit2, y_fit2(10,:), '-', 'LineWidth', 2, "Color",'g');
                    hold(app.UIAxes9, "off")
                    title(app.UIAxes9,'Time for Relaxation: 90%');
                    xlabel(app.UIAxes9,'Length (mm)');
                    ylabel(app.UIAxes9,'Time (ms)');
                end

                %fit median of all data to second order polynomial
                y_fit3=NaN(length(app.excel_tabs),100);
                if ~isempty(app.combined_group3) && ~isempty(app.combined_group3{1}) && iscell(app.combined_group3) && length(app.combined_group3) >= 2
                    for f=2:length(app.combined_group3)
                        poly3 = polyfit(median(app.combined_group3{1},2), median(app.combined_group3{f},2), 2);
                        x_fit3 = linspace(min(median(app.combined_group3{1},2)), max(median(app.combined_group3{1},2)), 100);
                        y_fit3(f,:) = polyval(poly3, x_fit3);
                    end

                    hold(app.UIAxes7, "on")
                    %plot(app.UIAxes7,app.combined_group3{8},"x","Color",'r')
                    plot(app.UIAxes7,median(app.combined_group3{1},2),median(app.combined_group3{10},2),"x","Color",'m')
                    plot(app.UIAxes7,x_fit3, y_fit3(8,:), '-', 'LineWidth', 2, "Color",'m');
                    hold(app.UIAxes7, "off")
                    title(app.UIAxes7,'Time for Relaxation: 50%');
                    xlabel(app.UIAxes7,'Length (mm)');
                    ylabel(app.UIAxes7,'Time (ms)');

                    hold(app.UIAxes8, "on")
                    %plot(app.UIAxes8,app.combined_group3{9},"x","Color",'r')
                    plot(app.UIAxes8,median(app.combined_group3{1},2),median(app.combined_group3{9},2),"x","Color",'m')
                    plot(app.UIAxes8,x_fit3, y_fit3(9,:), '-', 'LineWidth', 2, "Color",'m');
                    hold(app.UIAxes8, "off")
                    title(app.UIAxes8,'Time for Relaxation: 75%');
                    xlabel(app.UIAxes8,'Length (mm)');
                    ylabel(app.UIAxes8,'Time (ms)');

                    hold(app.UIAxes9, "on")
                    %plot(app.UIAxes9,app.combined_group3{10},"x","Color",'r')
                    plot(app.UIAxes9,median(app.combined_group3{1},2),median(app.combined_group3{8},2),"x","Color",'m')
                    plot(app.UIAxes9,x_fit3, y_fit3(10,:), '-', 'LineWidth', 2, "Color",'m');
                    hold(app.UIAxes9, "off")
                    title(app.UIAxes9,'Time for Relaxation: 90%');
                    xlabel(app.UIAxes9,'Length (mm)');
                    ylabel(app.UIAxes9,'Time (ms)');
                end

            end
        end

        % Button pushed function: StartOverButton
        function StartOverButtonPushed(app, event)
            cla(app.UIAxes2,'reset')
            cla(app.UIAxes3,'reset')
            cla(app.UIAxes4,'reset')
            cla(app.UIAxes5,'reset')
            cla(app.UIAxes6,'reset')
            cla(app.UIAxes7,'reset')
            cla(app.UIAxes8,'reset')
            cla(app.UIAxes9,'reset')            
            clear global
        end
    end

    % Component initialization
    methods (Access = private)

        % Create UIFigure and components
        function createComponents(app)

            % Create UIFigure and hide until all components are created
            app.UIFigure = uifigure('Visible', 'off');
            app.UIFigure.Position = [100 100 940 740];
            app.UIFigure.Name = 'MATLAB App';

            % Create FileFormatMenu
            app.FileFormatMenu = uimenu(app.UIFigure);
            app.FileFormatMenu.Text = 'File Format';

            % Create HeaderLinesMenu
            app.HeaderLinesMenu = uimenu(app.FileFormatMenu);
            app.HeaderLinesMenu.MenuSelectedFcn = createCallbackFcn(app, @HeaderLinesMenuSelected, true);
            app.HeaderLinesMenu.Text = 'Header Lines';

            % Create SelectDataRangeMenu
            app.SelectDataRangeMenu = uimenu(app.FileFormatMenu);
            app.SelectDataRangeMenu.Text = 'Select Data Range';

            % Create StartMenu
            app.StartMenu = uimenu(app.SelectDataRangeMenu);
            app.StartMenu.MenuSelectedFcn = createCallbackFcn(app, @StartMenuSelected, true);
            app.StartMenu.Text = 'Start';

            % Create EndMenu
            app.EndMenu = uimenu(app.SelectDataRangeMenu);
            app.EndMenu.MenuSelectedFcn = createCallbackFcn(app, @EndMenuSelected, true);
            app.EndMenu.Text = 'End';

            % Create DataColumnsMenu
            app.DataColumnsMenu = uimenu(app.FileFormatMenu);
            app.DataColumnsMenu.Text = 'Data Columns';

            % Create TimeMenu
            app.TimeMenu = uimenu(app.DataColumnsMenu);
            app.TimeMenu.MenuSelectedFcn = createCallbackFcn(app, @TimeMenuSelected, true);
            app.TimeMenu.Text = 'Time';

            % Create LengthMenu
            app.LengthMenu = uimenu(app.DataColumnsMenu);
            app.LengthMenu.MenuSelectedFcn = createCallbackFcn(app, @LengthMenuSelected, true);
            app.LengthMenu.Text = 'Length';

            % Create ForceMenu
            app.ForceMenu = uimenu(app.DataColumnsMenu);
            app.ForceMenu.MenuSelectedFcn = createCallbackFcn(app, @ForceMenuSelected, true);
            app.ForceMenu.Text = 'Force';

            % Create StimulusMenu
            app.StimulusMenu = uimenu(app.DataColumnsMenu);
            app.StimulusMenu.MenuSelectedFcn = createCallbackFcn(app, @StimulusMenuSelected, true);
            app.StimulusMenu.Text = 'Stimulus';

            % Create StimulusValueMenu
            app.StimulusValueMenu = uimenu(app.FileFormatMenu);
            app.StimulusValueMenu.MenuSelectedFcn = createCallbackFcn(app, @StimulusValueMenuSelected, true);
            app.StimulusValueMenu.Text = 'Stimulus Value';

            % Create ManuallyAssignStretchTimepointsMenu
            app.ManuallyAssignStretchTimepointsMenu = uimenu(app.FileFormatMenu);
            app.ManuallyAssignStretchTimepointsMenu.MenuSelectedFcn = createCallbackFcn(app, @ManuallyAssignStretchTimepointsMenuSelected, true);
            app.ManuallyAssignStretchTimepointsMenu.Text = 'Manually Assign Stretch Timepoints';

            % Create InitialLengthL0inmmMenu
            app.InitialLengthL0inmmMenu = uimenu(app.FileFormatMenu);
            app.InitialLengthL0inmmMenu.MenuSelectedFcn = createCallbackFcn(app, @InitialLengthL0inmmMenuSelected, true);
            app.InitialLengthL0inmmMenu.Text = 'Initial Length (L0 in mm)';

            % Create TabGroup
            app.TabGroup = uitabgroup(app.UIFigure);
            app.TabGroup.Position = [2 1 939 740];

            % Create AnalysisTab
            app.AnalysisTab = uitab(app.TabGroup);
            app.AnalysisTab.Title = 'Analysis';

            % Create UIAxes
            app.UIAxes = uiaxes(app.AnalysisTab);
            title(app.UIAxes, 'Title')
            xlabel(app.UIAxes, 'X')
            ylabel(app.UIAxes, 'Y')
            zlabel(app.UIAxes, 'Z')
            app.UIAxes.Position = [15 19 913 446];

            % Create SelectFilesButton
            app.SelectFilesButton = uibutton(app.AnalysisTab, 'push');
            app.SelectFilesButton.ButtonPushedFcn = createCallbackFcn(app, @SelectFilesButtonPushed, true);
            app.SelectFilesButton.FontSize = 18;
            app.SelectFilesButton.FontWeight = 'bold';
            app.SelectFilesButton.Position = [36 627 114 30];
            app.SelectFilesButton.Text = 'Select Files';

            % Create CombineSelectedStretchesButton
            app.CombineSelectedStretchesButton = uibutton(app.AnalysisTab, 'push');
            app.CombineSelectedStretchesButton.ButtonPushedFcn = createCallbackFcn(app, @CombineSelectedStretchesButtonPushed, true);
            app.CombineSelectedStretchesButton.FontSize = 14;
            app.CombineSelectedStretchesButton.FontWeight = 'bold';
            app.CombineSelectedStretchesButton.Position = [690 628 205 30];
            app.CombineSelectedStretchesButton.Text = 'Combine Selected Stretches';

            % Create SaveDataandFiguresButton
            app.SaveDataandFiguresButton = uibutton(app.AnalysisTab, 'push');
            app.SaveDataandFiguresButton.ButtonPushedFcn = createCallbackFcn(app, @SaveDataandFiguresButtonPushed, true);
            app.SaveDataandFiguresButton.FontSize = 14;
            app.SaveDataandFiguresButton.FontWeight = 'bold';
            app.SaveDataandFiguresButton.Position = [708 573 174 28];
            app.SaveDataandFiguresButton.Text = 'Save Data and Figures ';

            % Create NextFileButton
            app.NextFileButton = uibutton(app.AnalysisTab, 'push');
            app.NextFileButton.ButtonPushedFcn = createCallbackFcn(app, @NextFileButtonPushed, true);
            app.NextFileButton.FontSize = 14;
            app.NextFileButton.FontWeight = 'bold';
            app.NextFileButton.Position = [743 523 106 27];
            app.NextFileButton.Text = 'Next File';

            % Create NumberofBeatsSpinnerLabel
            app.NumberofBeatsSpinnerLabel = uilabel(app.AnalysisTab);
            app.NumberofBeatsSpinnerLabel.HorizontalAlignment = 'center';
            app.NumberofBeatsSpinnerLabel.FontSize = 14;
            app.NumberofBeatsSpinnerLabel.FontWeight = 'bold';
            app.NumberofBeatsSpinnerLabel.Position = [33 568 117 22];
            app.NumberofBeatsSpinnerLabel.Text = 'Number of Beats';

            % Create NumberofBeatsSpinner
            app.NumberofBeatsSpinner = uispinner(app.AnalysisTab);
            app.NumberofBeatsSpinner.Limits = [1 Inf];
            app.NumberofBeatsSpinner.ValueChangedFcn = createCallbackFcn(app, @NumberofBeatsSpinnerValueChanged, true);
            app.NumberofBeatsSpinner.HorizontalAlignment = 'center';
            app.NumberofBeatsSpinner.FontSize = 14;
            app.NumberofBeatsSpinner.FontWeight = 'bold';
            app.NumberofBeatsSpinner.Position = [40 537 100 22];
            app.NumberofBeatsSpinner.Value = 5;

            % Create SelectedFilesListBoxLabel
            app.SelectedFilesListBoxLabel = uilabel(app.AnalysisTab);
            app.SelectedFilesListBoxLabel.HorizontalAlignment = 'center';
            app.SelectedFilesListBoxLabel.WordWrap = 'on';
            app.SelectedFilesListBoxLabel.FontSize = 18;
            app.SelectedFilesListBoxLabel.FontWeight = 'bold';
            app.SelectedFilesListBoxLabel.Position = [243 684 127 23];
            app.SelectedFilesListBoxLabel.Text = 'Selected Files ';

            % Create SelectedFilesListBox
            app.SelectedFilesListBox = uilistbox(app.AnalysisTab);
            app.SelectedFilesListBox.ValueChangedFcn = createCallbackFcn(app, @SelectedFilesListBoxValueChanged, true);
            app.SelectedFilesListBox.ClickedFcn = createCallbackFcn(app, @SelectedFilesListBoxValueChanged, true);
            app.SelectedFilesListBox.Position = [226 475 161 191];

            % Create StretchtoPlotAnalyzeLabel
            app.StretchtoPlotAnalyzeLabel = uilabel(app.AnalysisTab);
            app.StretchtoPlotAnalyzeLabel.HorizontalAlignment = 'center';
            app.StretchtoPlotAnalyzeLabel.FontSize = 14;
            app.StretchtoPlotAnalyzeLabel.FontWeight = 'bold';
            app.StretchtoPlotAnalyzeLabel.Position = [423 662 215 22];
            app.StretchtoPlotAnalyzeLabel.Text = 'Select Stretch # to Plot/Analyze';

            % Create SelectStretchtoPlotAnalyzeListBox
            app.SelectStretchtoPlotAnalyzeListBox = uilistbox(app.AnalysisTab);
            app.SelectStretchtoPlotAnalyzeListBox.Items = {'Stretch 1', 'Stretch 2', 'Stretch 3', 'Stretch 4', 'Stretch 5', 'Stretch 6', 'Stretch 7', 'Stretch 8'};
            app.SelectStretchtoPlotAnalyzeListBox.FontSize = 14;
            app.SelectStretchtoPlotAnalyzeListBox.FontWeight = 'bold';
            app.SelectStretchtoPlotAnalyzeListBox.ClickedFcn = createCallbackFcn(app, @SelectStretchtoPlotAnalyzeListBoxClicked, true);
            app.SelectStretchtoPlotAnalyzeListBox.Position = [424 486 212 169];
            app.SelectStretchtoPlotAnalyzeListBox.Value = {};

            % Create ImportantclicktoavoidoverwritingdataLabel
            app.ImportantclicktoavoidoverwritingdataLabel = uilabel(app.AnalysisTab);
            app.ImportantclicktoavoidoverwritingdataLabel.HorizontalAlignment = 'center';
            app.ImportantclicktoavoidoverwritingdataLabel.FontColor = [1 0 0];
            app.ImportantclicktoavoidoverwritingdataLabel.Position = [677 505 231 22];
            app.ImportantclicktoavoidoverwritingdataLabel.Text = 'Important: click to avoid overwriting data!!!';

            % Create SelectedFilesClickonfiletostartanalysisListBoxLabel_2
            app.SelectedFilesClickonfiletostartanalysisListBoxLabel_2 = uilabel(app.AnalysisTab);
            app.SelectedFilesClickonfiletostartanalysisListBoxLabel_2.HorizontalAlignment = 'center';
            app.SelectedFilesClickonfiletostartanalysisListBoxLabel_2.WordWrap = 'on';
            app.SelectedFilesClickonfiletostartanalysisListBoxLabel_2.FontWeight = 'bold';
            app.SelectedFilesClickonfiletostartanalysisListBoxLabel_2.FontColor = [1 0 0];
            app.SelectedFilesClickonfiletostartanalysisListBoxLabel_2.Position = [218 662 178 30];
            app.SelectedFilesClickonfiletostartanalysisListBoxLabel_2.Text = 'Click on file to start analysis';

            % Create SummaryTab
            app.SummaryTab = uitab(app.TabGroup);
            app.SummaryTab.Title = 'Summary';

            % Create UIAxes2
            app.UIAxes2 = uiaxes(app.SummaryTab);
            title(app.UIAxes2, 'Title')
            xlabel(app.UIAxes2, 'X')
            ylabel(app.UIAxes2, 'Y')
            zlabel(app.UIAxes2, 'Z')
            app.UIAxes2.Position = [268 494 332 213];

            % Create UIAxes3
            app.UIAxes3 = uiaxes(app.SummaryTab);
            title(app.UIAxes3, 'Title')
            xlabel(app.UIAxes3, 'X')
            ylabel(app.UIAxes3, 'Y')
            zlabel(app.UIAxes3, 'Z')
            app.UIAxes3.Position = [605 494 332 213];

            % Create UIAxes4
            app.UIAxes4 = uiaxes(app.SummaryTab);
            title(app.UIAxes4, 'Title')
            xlabel(app.UIAxes4, 'X')
            ylabel(app.UIAxes4, 'Y')
            zlabel(app.UIAxes4, 'Z')
            app.UIAxes4.Position = [1 251 309 244];

            % Create UIAxes5
            app.UIAxes5 = uiaxes(app.SummaryTab);
            title(app.UIAxes5, 'Title')
            xlabel(app.UIAxes5, 'X')
            ylabel(app.UIAxes5, 'Y')
            zlabel(app.UIAxes5, 'Z')
            app.UIAxes5.Position = [309 251 310 244];

            % Create UIAxes6
            app.UIAxes6 = uiaxes(app.SummaryTab);
            title(app.UIAxes6, 'Title')
            xlabel(app.UIAxes6, 'X')
            ylabel(app.UIAxes6, 'Y')
            zlabel(app.UIAxes6, 'Z')
            app.UIAxes6.Position = [626 251 310 244];

            % Create UIAxes7
            app.UIAxes7 = uiaxes(app.SummaryTab);
            title(app.UIAxes7, 'Title')
            xlabel(app.UIAxes7, 'X')
            ylabel(app.UIAxes7, 'Y')
            zlabel(app.UIAxes7, 'Z')
            app.UIAxes7.Position = [2 19 308 233];

            % Create UIAxes8
            app.UIAxes8 = uiaxes(app.SummaryTab);
            title(app.UIAxes8, 'Title')
            xlabel(app.UIAxes8, 'X')
            ylabel(app.UIAxes8, 'Y')
            zlabel(app.UIAxes8, 'Z')
            app.UIAxes8.Position = [309 19 314 233];

            % Create UIAxes9
            app.UIAxes9 = uiaxes(app.SummaryTab);
            title(app.UIAxes9, 'Title')
            xlabel(app.UIAxes9, 'X')
            ylabel(app.UIAxes9, 'Y')
            zlabel(app.UIAxes9, 'Z')
            app.UIAxes9.Position = [626 19 312 233];

            % Create Group1Button
            app.Group1Button = uibutton(app.SummaryTab, 'push');
            app.Group1Button.ButtonPushedFcn = createCallbackFcn(app, @Group1ButtonPushed, true);
            app.Group1Button.FontWeight = 'bold';
            app.Group1Button.FontColor = [0.0667 0.4431 0.7451];
            app.Group1Button.Position = [22 657 100 23];
            app.Group1Button.Text = 'Group 1';

            % Create Group2Button
            app.Group2Button = uibutton(app.SummaryTab, 'push');
            app.Group2Button.ButtonPushedFcn = createCallbackFcn(app, @Group2ButtonPushed, true);
            app.Group2Button.FontWeight = 'bold';
            app.Group2Button.FontColor = [0.2314 0.6667 0.1961];
            app.Group2Button.Position = [23 617 100 23];
            app.Group2Button.Text = 'Group 2';

            % Create Group3Button
            app.Group3Button = uibutton(app.SummaryTab, 'push');
            app.Group3Button.ButtonPushedFcn = createCallbackFcn(app, @Group3ButtonPushed2, true);
            app.Group3Button.FontWeight = 'bold';
            app.Group3Button.FontColor = [0.5216 0.0863 0.8196];
            app.Group3Button.Position = [22 573 100 23];
            app.Group3Button.Text = 'Group 3';

            % Create EditField3
            app.EditField3 = uieditfield(app.SummaryTab, 'text');
            app.EditField3.ValueChangedFcn = createCallbackFcn(app, @EditField3ValueChanged, true);
            app.EditField3.Position = [146 573 100 22];

            % Create EditField2
            app.EditField2 = uieditfield(app.SummaryTab, 'text');
            app.EditField2.ValueChangedFcn = createCallbackFcn(app, @EditField2ValueChanged, true);
            app.EditField2.Position = [146 617 100 22];

            % Create EditField
            app.EditField = uieditfield(app.SummaryTab, 'text');
            app.EditField.ValueChangedFcn = createCallbackFcn(app, @EditFieldValueChanged, true);
            app.EditField.Position = [146 657 100 22];

            % Create StartOverButton
            app.StartOverButton = uibutton(app.SummaryTab, 'push');
            app.StartOverButton.ButtonPushedFcn = createCallbackFcn(app, @StartOverButtonPushed, true);
            app.StartOverButton.Position = [162 516 67 23];
            app.StartOverButton.Text = 'Start Over';

            % Create OptionalGraphsListBox
            app.OptionalGraphsListBox = uilistbox(app.SummaryTab);
            app.OptionalGraphsListBox.Items = {'Time for Contraction', 'Time for Relaxation'};
            app.OptionalGraphsListBox.ClickedFcn = createCallbackFcn(app, @OptionalGraphsListBoxClicked, true);
            app.OptionalGraphsListBox.Position = [10 506 126 42];
            app.OptionalGraphsListBox.Value = 'Time for Contraction';

            % Create OptionalGraphsListBoxLabel
            app.OptionalGraphsListBoxLabel = uilabel(app.SummaryTab);
            app.OptionalGraphsListBoxLabel.HorizontalAlignment = 'right';
            app.OptionalGraphsListBoxLabel.Position = [23 545 92 22];
            app.OptionalGraphsListBoxLabel.Text = 'Optional Graphs';

            % Create ImportantchangegroupnametoavoidoverwritingdataLabel
            app.ImportantchangegroupnametoavoidoverwritingdataLabel = uilabel(app.SummaryTab);
            app.ImportantchangegroupnametoavoidoverwritingdataLabel.HorizontalAlignment = 'center';
            app.ImportantchangegroupnametoavoidoverwritingdataLabel.WordWrap = 'on';
            app.ImportantchangegroupnametoavoidoverwritingdataLabel.FontColor = [1 0 0];
            app.ImportantchangegroupnametoavoidoverwritingdataLabel.Position = [23 679 217 37];
            app.ImportantchangegroupnametoavoidoverwritingdataLabel.Text = 'Important: change group name to avoid overwriting data!!!';

            % Show the figure after all components are created
            app.UIFigure.Visible = 'on';
        end
    end

    % App creation and deletion
    methods (Access = public)

        % Construct app
        function app = CardioFlex_raw_code

            % Create UIFigure and components
            createComponents(app)

            % Register the app with App Designer
            registerApp(app, app.UIFigure)

            % Execute the startup function
            runStartupFcn(app, @startupFcn)

            if nargout == 0
                clear app
            end
        end

        % Code that executes before app deletion
        function delete(app)

            % Delete UIFigure when app is deleted
            delete(app.UIFigure)
        end
    end
end