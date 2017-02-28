classdef (Sealed) CameraPipelineAPI < handle
    % TODO: consider singleton, due to implementation od loading back into
    % pipeline
    % https://www.mathworks.com/help/matlab/matlab_oop/controlling-the-number-of-instances.html
    properties
        input_filename
        image
        last_stage
        
        cam_pipeline_path
        dng_exe % path to executable file dng_validate.exe
         
        vignette = true % either true or false, default true
        WB_mode = 'AsShot' % 'AsShot' or 'Custom' (currently only 'AsShot is supported)
        RW_mode ='None'% 'None' -not set, 'Read', 'Write'
        CamSettings = 2
        width % of the RAW image 
        height % of the RAW image 

    end  % properties
    
    properties (Constant = true)
        % Pipeline Stages
        STAGE1_READ_RAW = 1;
        STAGE2_LINEARIZE =2;
        STAGE3_CORRECT_LENS = 3;
        STAGE4_DEMOSAIC = 4;
        STAGE5_COLOR_SPACE = 5;
        STAGE6_HUE_SAT = 6;
        STAGE7_EXPOSURE = 7;
        STAGE8_LUT = 8;
        STAGE9_TONE_CURVE = 9;
        STAGE10_FINAL_COLOR = 10;
        STAGE11_GAMMA = 11;
        FINAL_STAGE = 11;
        
        % Read \ Write Modes
        RW_MODE_NONE = 0;
        RW_MODE_READ = 1;
        RW_MODE_WRITE = 2;
    end % prinate properties
    
    methods
        function obj = CameraPipelineAPI(cam_pipeline_path, vignette)
            % Inputs:
            % cam_pipeline_path  - the path of this file
            % vignette - whether to compensate, either true or false
            % WB_mode   - either 'AsShot' or 'Custom' (TBA, currently only
            % the default 'AsShot' is supported
            
            obj.cam_pipeline_path = cam_pipeline_path;
            obj.last_stage = 0;
            
            obj.dng_exe = fullfile('dngOneExeSDK','dng_validate.exe');
            
            % Set Vignette compensation and WB
            if exist('vignette','var')  && ~isempty(vignette)
                obj.vignette = vignette;
            end
            if exist('WB_mode','var') && ~isempty(WB_mode) && ischar(WB_mode)
                obj.WB_mode = WB_mode;
            end            
            SetWBGainSettings(obj)
            
            WriteTxtFileRWmode(obj);
            
            if exist('CamSettings','var') && ~isempty(CamSettings) && CamSettings>=0 && CamSettings<=2
                obj.CamSettings = CamSettings;
            end
            WriteTxtFile(obj, 'cam_settings', obj.CamSettings);
            
        end % constructor CameraPipeLineAPI
        
        function SetInput(obj, filename)
            if ~ischar(filename)
                error('The pipeline expect a DNG filename as input');
            end
            if ~exist(filename,'file')
                error(['Could not find file: ',filename]); 
            end
            obj.input_filename = filename;
            meta_info = imfinfo(obj.input_filename);
            % Crop to only valid pixels
            obj.width = meta_info.SubIFDs{1}.DefaultCropSize(1);
            obj.height = meta_info.SubIFDs{1}.DefaultCropSize(2);
        end
        
        function img = ExecutePipeline(obj, begin_or_cont, final_step, input_filename, output_filename)
            % Inputs:
            % begin_or_cont  - either 'begin' pipeline from scratch or
            %                  'cont' to continue processing from the last stage
            % final_step     - run the pipeline until this stage
            % input_filename - path to image (DNG for 'begin', else TIF)
            % output_filename- if a path is given, the image is written to
            %                  disk (it is the output of the function as well)
            if (final_step~=obj.STAGE4_DEMOSAIC) && (final_step~=obj.FINAL_STAGE)
                warning(['This Pipeline API was not tested on stages other than: ',...
                    num2str(obj.STAGE4_DEMOSAIC),' and ',num2str(obj.FINAL_STAGE)])
            end
            
            if strcmp(begin_or_cont,'begin')
                % start pipeline from scratch, read a new image etc.
                obj.WriteTxtFileRWmode('None');
                obj.last_stage = 0;
                obj.WriteTxtFile('lastStage', obj.last_stage)
                obj.SetInput(input_filename);
            elseif strcmp(begin_or_cont,'cont')
                % continue running pipline after previous step, load a new
                % image from given filename
                obj.WriteTxtFileRWmode('Read');
                obj.Load(input_filename);
            end
            
            if (final_step == obj.STAGE4_DEMOSAIC)
                obj.Demosaic();
                obj.SaveFromTxt(output_filename);
                img = obj.image;
            elseif (final_step > obj.STAGE4_DEMOSAIC)
                obj.RunToStage(final_step);
                obj.Save(output_filename);
            end
        end
        
        function Demosaic(obj) % upto stage 4 in the pipeline
            obj.last_stage = 4; 
            WriteTxtFile(obj, 'stageSettings', obj.last_stage);
            stage4_output_filename = [obj.input_filename(1:end-4) '_stage4.tif'];
            if ~strcmpi(obj.RW_mode,'Read')
                WriteTxtFile(obj, 'lastStage', obj.last_stage);
                RunDngOneExeSDK(obj, 'cs1 -tif', stage4_output_filename, false);
            end
            RunDngOneExeSDK(obj, 3, stage4_output_filename, true)
        end
        
        function RunToStage(obj, stage_num) % upto stage 5/6/7/8/9/10/11 in the pipeline
            if stage_num < obj.STAGE5_COLOR_SPACE || stage_num > obj.FINAL_STAGE
                error(['RunToStage is itnteded for use in stages: ',...
                    num2str(obj.STAGE5_COLOR_SPACE),' - ',obj.FINAL_STAGE]);
            end
            obj.last_stage = stage_num;
            WriteTxtFile(obj, 'stageSettings', obj.last_stage);
            if ~strcmpi(obj.RW_mode,'Read')
                WriteTxtFile(obj, 'lastStage', obj.last_stage);
            end
            stage_output_filename = [obj.input_filename(1:end-4) '_stage',num2str(stage_num),'.tif'];
            RunDngOneExeSDK(obj, 'cs1 -tif', stage_output_filename, true);
        end
        
        function Load(~, input_filename)
            % In order to load images into an intermediate step in the
            % pipeline, they have to be converted into text files and saved
            % in the subdir /image (three different files for r,g,b)
            % The input filename of the class should not change compares to
            % the previously loaded one
            
            if ~exist('input_filename','var') || isempty(input_filename) || ~ischar(input_filename)
                error('Input image filename is not valid')
            end

            intermediate_image = im2double(imread(input_filename));
            
            disp(['Loaded images size: ',num2str(size(intermediate_image,1)),...
                ' x ',num2str(size(intermediate_image,2))])
            
            % save image as binary file for DNG-SDK executable
            fd = fopen(fullfile(pwd,'/image/r.txt'),'w');
            fwrite(fd,intermediate_image(:,:,1)','double');
            fclose(fd);
            fd2 = fopen(fullfile(pwd,'/image/g.txt'),'w');
            fwrite(fd2,intermediate_image(:,:,2)','double');
            fclose(fd2);
            fd3 = fopen(fullfile(pwd,'/image/b.txt'),'w');
            fwrite(fd3,intermediate_image(:,:,3)','double');
            fclose(fd3);
        end
        
        function SaveFromTxt(obj, output_filename)
            fd1 = fopen(fullfile(pwd,'image/r.txt'),'r');
            fd2 = fopen(fullfile(pwd,'image/g.txt'),'r');
            fd3 = fopen(fullfile(pwd,'image/b.txt'),'r');
            if fd1==-1 || fd2==-1 || fd3==-1
                error('Image not written properly to memory');
            end
            r = fread(fd1,[obj.width, obj.height], 'double');
            fclose(fd1);
            g = fread(fd2,[obj.width, obj.height], 'double');
            fclose(fd2);
            b = fread(fd3,[obj.width, obj.height], 'double');
            fclose(fd3);
            delete(fullfile(pwd,'image/r.txt'))
            delete(fullfile(pwd,'image/g.txt'))
            delete(fullfile(pwd,'image/b.txt'))
            
            obj.image = zeros(obj.height, obj.width, 3);
            obj.image(:,:,1) = r';
            obj.image(:,:,2) = g';
            obj.image(:,:,3) = b';
            obj.image = im2double(obj.image);
            
            obj.Save(output_filename);
        end
        
        function Save(obj, output_filename) % save image in current step in the pipline
            if exist('output_filename','var') && ~isempty(output_filename)
                t = Tiff(output_filename,'w');
                
                tagstruct.ImageLength = size(obj.image,1);
                tagstruct.ImageWidth = size(obj.image,2);
                tagstruct.BitsPerSample = 16;
                if obj.last_stage == 1 || obj.last_stage == 2 || obj.last_stage == 3
                    tagstruct.SamplesPerPixel = 1;
                    tagstruct.Photometric = Tiff.Photometric.MinIsBlack;
                else
                    tagstruct.SamplesPerPixel = 3;
                    tagstruct.Photometric = Tiff.Photometric.RGB;
                end
                tagstruct.PlanarConfiguration = Tiff.PlanarConfiguration.Chunky;
                tagstruct.Software = 'MATLAB';
                t.setTag(tagstruct);
                
                t.write(im2uint16(obj.image));
                t.close();
            end
        end
        
        % util methods
        function WriteTxtFile(obj, filename, data_to_file)
            fileID = fopen(fullfile(obj.cam_pipeline_path, [filename,'.txt']),'w');
            fprintf(fileID,'%d\n',data_to_file);
            fclose(fileID);
        end % function WriteTxtFile
        
        function RunDngOneExeSDK(obj, flags, stage_output_filename, readImage)
            if isnumeric(flags), flags = num2str(flags); end;    
            system_command = [fullfile(obj.cam_pipeline_path, obj.dng_exe),' -16 -',flags,' ', stage_output_filename, ' ', obj.input_filename];
            system(system_command);
            if ~exist('readImage','var') || ( exist('readImage','var') && readImage)
                obj.image = imread(stage_output_filename);
                delete(stage_output_filename);
            end
        end % function RunDngOneExeSDK
        
        function SetWBGainSettings(obj, vignette, WBmode)
            if exist('vignette','var') && ~isempty(vignette)
                obj.vignette = vignette;
            end
            if exist('wb','var') && ~isempty(wb) && ischar(wb)
                obj.WB_mode = WBmode;
            end
            % write format for DNG-SDK-one-exe
            wb_gain_settings = [int8(obj.vignette), int8(~obj.vignette), ...
                strcmpi(obj.WB_mode,'AsShot'), strcmpi(obj.WB_mode,'Custom')];
            WriteTxtFile(obj, 'wbAndGainSettings', wb_gain_settings)
        end % function SetWBGainSettings
        
        function WriteTxtFileRWmode(obj, rw_mode)
            if exist('rw_mode','var') && ~isempty(rw_mode) && ischar(rw_mode)
                obj.RW_mode = rw_mode;
            end
            if strcmpi(obj.RW_mode,'None')
                WriteTxtFile(obj, 'rwSettings', obj.RW_MODE_NONE);
            elseif strcmpi(obj.RW_mode,'Read')
                WriteTxtFile(obj, 'rwSettings', obj.RW_MODE_READ);
            elseif strcmpi(obj.RW_mode,'Write')
                WriteTxtFile(obj, 'rwSettings', obj.RW_MODE_WRITE);
            end
        end % function WriteTxtFileRWmode
                
    end  % methods
    
end  % classdef