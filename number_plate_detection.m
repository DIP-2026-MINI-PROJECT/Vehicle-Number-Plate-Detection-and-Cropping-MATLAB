%% ========================================================================
%  ROBUST VEHICLE NUMBER PLATE DETECTION AND CROPPING
%  ========================================================================
clc; clear; close all;

%% 1. INPUT IMAGE
imageFile = '';   % specify file path or leave empty for file dialog

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
if size(orig, 3) == 1, orig = repmat(orig, [1 1 3]); end
orig = orig(:, :, 1:3);
[origH, origW, ~] = size(orig);

%% 2. PRE-PROCESSING
targetW = 900;
scale   = targetW / origW;
img     = imresize(orig, scale, 'bilinear');
[H, W, ~] = size(img);

hsvImg = rgb2hsv(img);
Hh = hsvImg(:,:,1);  Ss = hsvImg(:,:,2);  Vv = hsvImg(:,:,3);

gray   = medfilt2(rgb2gray(img), [3 3]);
grayEq = im2double(adapthisteq(gray, 'ClipLimit', 0.02));

%% 3. CUE A: ROBUST YELLOW PLATE MASK (HSV)
% Relaxed saturation from 0.40 to 0.22 to handle washed out / sunlit plates
yellowRaw = (Hh >= 0.08 & Hh <= 0.23) & (Ss >= 0.22) & (Vv >= 0.30);
yellowMask = imclose(yellowRaw, strel('rectangle', [3 11]));
yellowMask = imfill(yellowMask, 'holes');
yellowMask = imopen(yellowMask, strel('rectangle', [2 5]));
yellowMask = bwareaopen(yellowMask, 40);

%% 4. CUE B: VERTICAL EDGES & TEXTURE
sobelV  = [-1 0 1; -2 0 2; -1 0 1];
edgeMap = abs(imfilter(grayEq, sobelV, 'replicate'));
edgeMap = edgeMap / max(edgeMap(:));

% Top-hat enhancement to isolate characters and separate from bumper grilles
se_char  = strel('rectangle', [5 15]);
edgeHigh = imtophat(edgeMap, se_char);
bwEdges  = imbinarize(edgeHigh, 'adaptive', 'Sensitivity', 0.55);

% Conservative morphological merge: avoids bleeding into car grilles
edgeMask = imclose(bwEdges,  strel('rectangle', [4 18]));
edgeMask = imopen(edgeMask,   strel('rectangle', [2 8]));
edgeMask = imfill(edgeMask,  'holes');
edgeMask = bwareaopen(edgeMask, 150);

%% 5. CANDIDATE VERIFICATION & SELECTION
masks     = {yellowMask, edgeMask};
cand      = [];
bestScore = -1;  
bestBox   = [];

for mi = 1:numel(masks)
    cc    = bwconncomp(masks{mi}, 8);
    stats = regionprops(cc, 'BoundingBox', 'Area', 'Extent');

    for i = 1:numel(stats)
        bb = stats(i).BoundingBox;
        x1 = max(1, round(bb(1)));          y1 = max(1, round(bb(2)));
        w  = round(bb(3));                  h  = round(bb(4));
        x2 = min(W, x1 + w - 1);            y2 = min(H, y1 + h - 1);
        w  = x2 - x1 + 1;                   h  = y2 - y1 + 1;

        ar   = w / h;
        frac = (w * h) / (H * W);

        % Geometric plate constraints
        if ar < 1.6 || ar > 6.5 || frac < 0.0003 || frac > 0.08 || h < 10 || w < 30
            continue;
        end
        
        % Reject top 20% of image (sky/buildings/street lamps)
        if (y1 / H) < 0.20
            continue;
        end

        % Character transition test
        crop = grayEq(y1:y2, x1:x2);
        sig  = max(1, (h - 1) / 6);
        lm   = imgaussfilt(crop, sig, 'Padding', 'replicate');
        dark = crop < (lm - 0.015);
        
        midRows = floor(0.25*h)+1 : floor(0.75*h);
        if isempty(midRows), continue; end
        
        trans = mean(sum(abs(diff(double(dark(midRows, :)), 1, 2)), 2));
        if trans < 7, continue; end

        % Scoring components
        yelFrac = mean(reshape(yellowRaw(y1:y2, x1:x2), [], 1));
        edgeDen = mean(reshape(edgeMap(y1:y2, x1:x2), [], 1));
        
        % Prioritize vertical lower-half placement (vehicles are on the road)
        posWeight = 0.5 + 0.5 * (y1 / H);
        
        % Score formula strongly rewarding yellow detection when present
        score = min(trans, 25) * edgeDen * (1.0 + 5.0 * yelFrac) * posWeight;

        cand(end+1, :) = [x1 y1 w h score]; %#ok<SAGROW>
        if score > bestScore
            bestScore = score;
            bestBox   = [x1 y1 w h];
        end
    end
end

if isempty(bestBox)
    error('No valid plate candidate found. Check contrast and visibility.');
end
fprintf('Plate successfully located at [%d, %d, %d, %d] with score %.3f\n', ...
        bestBox(1), bestBox(2), bestBox(3), bestBox(4), bestScore);

%% 6. CROP ORIGINAL FULL-RES IMAGE
padX = 0.10 * bestBox(3);   
padY = 0.15 * bestBox(4);
bx1 = max(1, bestBox(1) - padX);
by1 = max(1, bestBox(2) - padY);
bx2 = min(W, bestBox(1) + bestBox(3) - 1 + padX);
by2 = min(H, bestBox(2) + bestBox(4) - 1 + padY);

r1 = max(1, floor(by1 / scale));   r2 = min(origH, ceil(by2 / scale));
c1 = max(1, floor(bx1 / scale));   c2 = min(origW, ceil(bx2 / scale));
plateCrop = orig(r1:r2, c1:c2, :);

imwrite(plateCrop, 'detected_plate.png');

%% 7. DISPLAY RESULTS
figure('Name', 'Number Plate Detection Fix', 'NumberTitle', 'off', ...
       'Units', 'normalized', 'Position', [0.05 0.1 0.9 0.75]);
subplot(2,3,1); imshow(img);        title('1. Input (resized)');
subplot(2,3,2); imshow(yellowMask); title('2. Cue A: Yellow Mask (HSV)');
subplot(2,3,3); imshow(edgeMask);   title('3. Cue B: Edge/Texture Mask');
subplot(2,3,4); imshow(img); hold on;
for k = 1:size(cand, 1)
    rectangle('Position', cand(k,1:4), 'EdgeColor', 'y', 'LineWidth', 1);
end
title('4. All Candidates (yellow)'); hold off;

subplot(2,3,5); imshow(img); hold on;
rectangle('Position', [bx1 by1 bx2-bx1 by2-by1], 'EdgeColor', [0 1 0], 'LineWidth', 2.5);
title('5. Best Plate Box'); hold off;

subplot(2,3,6); imshow(plateCrop);
title('6. Cropped Plate');