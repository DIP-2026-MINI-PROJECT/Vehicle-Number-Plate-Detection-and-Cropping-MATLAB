%% ========================================================================
%  VEHICLE NUMBER PLATE DETECTION AND CROPPING
%  VERSION 3 - IMPROVED EDGE / TEXTURE DETECTION
%  ========================================================================

clc;
clear;
close all;

%% 1. INPUT IMAGE

imageFile = '';

if isempty(imageFile)

    [fname, fpath] = uigetfile( ...
        {'*.jpg;*.jpeg;*.png;*.bmp;*.tif;*.tiff', 'Image files'}, ...
        'Select a vehicle image');

    if isequal(fname, 0)
        error('No image selected.');
    end

    imageFile = fullfile(fpath, fname);

end

orig = imread(imageFile);

if size(orig,3) == 1
    orig = repmat(orig,[1 1 3]);
end

orig = orig(:,:,1:3);

[origH,origW,~] = size(orig);


%% 2. PRE-PROCESSING

targetW = 900;

scale = targetW / origW;

img = imresize(orig,scale,'bilinear');

[H,W,~] = size(img);

% HSV conversion

hsvImg = rgb2hsv(img);

Hh = hsvImg(:,:,1);
Ss = hsvImg(:,:,2);
Vv = hsvImg(:,:,3);

% Grayscale conversion

gray = rgb2gray(img);

% Median filtering

gray = medfilt2(gray,[3 3]);

% Contrast enhancement

grayEq = im2double(adapthisteq(gray,'ClipLimit',0.02));


%% 3. CUE A: YELLOW PLATE MASK (HSV)

yellowRaw = ...
    (Hh >= 0.08 & Hh <= 0.23) & ...
    (Ss >= 0.22) & ...
    (Vv >= 0.30);

% Join nearby yellow pixels

yellowMask = imclose(yellowRaw, ...
    strel('rectangle',[3 11]));

% Fill holes

yellowMask = imfill(yellowMask,'holes');

% Remove small regions

yellowMask = imopen(yellowMask, ...
    strel('rectangle',[2 5]));

yellowMask = bwareaopen(yellowMask,40);


%% 4. CUE B: IMPROVED EDGE / TEXTURE MASK

% Step 1: Detect vertical intensity changes

verticalFilter = [-1 0 1];

verticalStrength = abs(imfilter( ...
    grayEq,verticalFilter,'replicate'));

verticalStrength = mat2gray(verticalStrength);


% Step 2: Detect strong vertical edges

verticalThreshold = max(0.06, ...
    graythresh(verticalStrength));

verticalEdges = verticalStrength > verticalThreshold;


% Step 3: Detect character-like dark regions

T = adaptthresh(grayEq,0.45, ...
    'ForegroundPolarity','dark');

darkText = imbinarize(grayEq,T);


% Step 4: Combine vertical edges and dark text

characterFeatures = verticalEdges & darkText;


% Step 5: Calculate local texture density

densityKernel = ones(9,31)/(9*31);

edgeDensity = imfilter( ...
    double(characterFeatures), ...
    densityKernel,'replicate');


% Step 6: Adaptive threshold

densityThreshold = max(0.008, ...
    0.30 * max(edgeDensity(:)));

edgeMask = edgeDensity > densityThreshold;


% Step 7: Join character regions horizontally

edgeMask = imclose(edgeMask, ...
    strel('rectangle',[7 31]));


% Step 8: Expand regions slightly

edgeMask = imdilate(edgeMask, ...
    strel('rectangle',[3 7]));


% Step 9: Remove small regions

edgeMask = bwareaopen(edgeMask,80);


% Step 10: Calculate Sobel edge map for scoring

sobelV = [-1 0 1; -2 0 2; -1 0 1];

edgeMap = abs(imfilter( ...
    grayEq,sobelV,'replicate'));

edgeMap = mat2gray(edgeMap);


%% 5. CANDIDATE DETECTION AND SELECTION

masks = {yellowMask,edgeMask};

cand = [];

bestScore = -1;

bestBox = [];

for mi = 1:numel(masks)

    cc = bwconncomp(masks{mi},8);

    stats = regionprops(cc, ...
        'BoundingBox','Area','Extent');

    for i = 1:numel(stats)

        bb = stats(i).BoundingBox;

        x1 = max(1,round(bb(1)));
        y1 = max(1,round(bb(2)));

        w = round(bb(3));
        h = round(bb(4));

        x2 = min(W,x1+w-1);
        y2 = min(H,y1+h-1);

        w = x2-x1+1;
        h = y2-y1+1;


        % Aspect ratio

        ar = w/h;

        % Percentage of image occupied

        frac = (w*h)/(H*W);


        % Plate shape constraints

        if ar < 1.6 || ar > 6.5 || ...
           frac < 0.0003 || frac > 0.08 || ...
           h < 10 || w < 30

            continue;

        end


        % Reject top 20% of image

        if y1/H < 0.20
            continue;
        end


        %% CHARACTER TRANSITION TEST

        crop = grayEq(y1:y2,x1:x2);

        sig = max(1,(h-1)/6);

        lm = imgaussfilt(crop,sig, ...
            'Padding','replicate');

        dark = crop < (lm-0.015);

        midRows = floor(0.25*h)+1:floor(0.75*h);

        if isempty(midRows)
            continue;
        end

        trans = mean(sum( ...
            abs(diff(double(dark(midRows,:)),1,2)),2));


        if trans < 7
            continue;
        end


        %% SCORING

        % Yellow percentage

        yelFrac = mean( ...
            double(yellowRaw(y1:y2,x1:x2)),'all');


        % Edge strength

        edgeDen = mean( ...
            edgeMap(y1:y2,x1:x2),'all');


        % Position weight

        posWeight = 0.5+0.5*(y1/H);


        % Texture contribution

        if mi == 2
            textureWeight = 1.5;
        else
            textureWeight = 1.0;
        end


        % Final score

        score = min(trans,25)*edgeDen * ...
            (1+5*yelFrac)*posWeight*textureWeight;


        %% SAVE CANDIDATE

        cand(end+1,:) = [x1 y1 w h score]; %#ok<SAGROW>

        if score > bestScore

            bestScore = score;

            bestBox = [x1 y1 w h];

        end

    end

end


%% 6. CHECK DETECTION

if isempty(bestBox)

    error('No valid plate found. Try adjusting thresholds.');

end

fprintf('\nNumber plate successfully detected!\n');

fprintf('Bounding Box: [%d %d %d %d]\n', ...
    bestBox(1),bestBox(2),bestBox(3),bestBox(4));

fprintf('Detection Score: %.3f\n',bestScore);


%% 7. CROP ORIGINAL IMAGE

padX = round(0.10*bestBox(3));

padY = round(0.15*bestBox(4));

bx1 = max(1,bestBox(1)-padX);

by1 = max(1,bestBox(2)-padY);

bx2 = min(W,bestBox(1)+bestBox(3)-1+padX);

by2 = min(H,bestBox(2)+bestBox(4)-1+padY);


% Convert resized coordinates to original coordinates

r1 = max(1,floor(by1/scale));

r2 = min(origH,ceil(by2/scale));

c1 = max(1,floor(bx1/scale));

c2 = min(origW,ceil(bx2/scale));


% Crop plate

plateCrop = orig(r1:r2,c1:c2,:);

imwrite(plateCrop,'detected_plate.png');


%% 8. DISPLAY RESULTS

figure('Name','Number Plate Detection - Version 3', ...
    'NumberTitle','off', ...
    'Units','normalized', ...
    'Position',[0.05 0.1 0.9 0.75]);


% 1. Input image

subplot(2,3,1);

imshow(img);

title('1. Input (resized)');


% 2. Yellow mask

subplot(2,3,2);

imshow(yellowMask);

title('2. Cue A: Yellow Mask (HSV)');


% 3. Edge / texture mask

subplot(2,3,3);

imshow(edgeMask);

title('3. Cue B: Character Texture Mask');


% 4. All candidates

subplot(2,3,4);

imshow(img);

hold on;

for k = 1:size(cand,1)

    rectangle('Position',cand(k,1:4), ...
        'EdgeColor','y','LineWidth',1);

end

title('4. All Candidates (yellow)');

hold off;


% 5. Best plate box

subplot(2,3,5);

imshow(img);

hold on;

rectangle('Position', ...
    [bx1 by1 bx2-bx1 by2-by1], ...
    'EdgeColor',[0 1 0], ...
    'LineWidth',2.5);

title('5. Best Plate Box');

hold off;


% 6. Cropped plate

subplot(2,3,6);

imshow(plateCrop);

title('6. Cropped Plate');


fprintf('\nCropped plate saved as detected_plate.png\n');