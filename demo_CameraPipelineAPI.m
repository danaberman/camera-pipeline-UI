% This demo file shows two use-cases of the command-line API
% The input is a DNG file, see the readme for conversion preferences
% The output is a 16-bit TIF file
% The demo does not have to reside in the same folder as the rest of the files

%% User definitions

% Define the folder of the rest of the files in this repository are saved to:
SDK_path = ['.']; 

% Define the image you want to work on
input_image = fullfile(SDK_path, 'sample_image', 'NIKOND40_0008_dng_converted.dng');
intermediate_image = fullfile('.','intermediate.tif');
output_image = fullfile('.','result.tif');
correct_vignette = true;

%% Use-case 1: stop the pipeline at stage 4 (after demosaic) and process the linear TIF
cp = CameraPipelineAPI(SDK_path, correct_vignette);
cp.ExecutePipeline('begin', cp.STAGE4_DEMOSAIC, input_image, intermediate_image);
% insert processing code here, process intermediate_image
cp.ExecutePipeline('cont', cp.FINAL_STAGE, intermediate_image, output_image);

%% Use-case 2: Convert a DNG image to TIF
cp = CameraPipelineAPI(SDK_path, correct_vignette);
cp.ExecutePipeline('begin', cp.FINAL_STAGE, input_image, output_image);
