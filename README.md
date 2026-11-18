# Vehicle Number Plate Detection and Cropping (MATLAB)

### Project Description:
#### Summary - 
A MATLAB pipeline that finds the number plate in a car photo and crops it, using only classical digital image processing and no training data. The image is resized to 900 px width, median-filtered and contrast-enhanced with CLAHE. Two cues then search for the plate: a yellow-colour mask in HSV (Cue A) and a vertical-edge / character-texture mask (Cue B). Candidate regions are verified by aspect ratio, area, size and character transitions, then scored. The best box is padded, cropped from the original image and saved as `detected_plate.png`. On 10 test images the plate was located in all 10 and cropped correctly in 9 (90%).

#### Course concepts used - 
1. Digital image fundamentals: bilinear interpolation (resize), RGB to grayscale, RGB to HSV, 8-connected neighbourhood
2. Enhancement and restoration: 3x3 median filter, CLAHE, Sobel vertical-edge convolution, top-hat filtering, adaptive thresholding
3. Morphology and colour: closing, opening, hole filling, small-object removal, connected components and region properties, HSV yellow detection

#### Additional concepts used -
1. Local-contrast character-transition test (Gaussian-smoothed local mean) to reject plate-shaped regions with no text
2. Combined candidate score (transitions x edge density x yellow fraction x position weight)
   
#### Dataset - 
10 vehicle photos collected from Google Images (publicly available images from the web), used for testing only. No training data is used. Inputs are in `data/`.

#### Novelty - 
1. Two independent cues (yellow colour and character texture), so both yellow and white plates can be found
2. Character-transition verification rejects grilles, lamps and signs that have no text
3. One combined score picks the best candidate automatically
   
### Contributors:
1. Keerthana A T (PES1UG24EC100)
2. Manya Manjunatha (PES1UG24EC121)
3. N Navya Mohithe (PES1UG24EC125)

### Steps:
1. Clone Repository
```git clone <repo-url>```

2. Install Dependencies
MATLAB with the Image Processing Toolbox. No other dependencies.

3. Run the Code
Open `number_plate_detection.m` in MATLAB and run it. Pick an image from `data/` in the file dialog (or set `imageFile` at the top of the script). The cropped plate is saved as `detected_plate.png` and a 6-panel figure shows every stage.

### Outputs:
* Important intermediate steps: resized input, yellow mask, edge/texture mask, all candidate boxes, best plate box
* Final output images: cropped plates and the 6-panel figures for all 10 test images are in `outputs/`

| Result | Count |
|---|---|
| Plate found | 10 / 10 |
| Plate cropped correctly | 9 / 10 (90%) |

In image 10 the plate is very small in the frame and only part of it was cropped.

### References:
1. MathWorks, Image Processing Toolbox documentation (imresize, rgb2hsv, medfilt2, adapthisteq, imfilter, imtophat, imbinarize, bwconncomp, regionprops): https://www.mathworks.com/help/images/
2. Digital Image Processing (UE24EC342AC1) course material, PES University
   
### Limitations and Future Work:
* Thresholds are fixed, so very different lighting may need re-tuning.
* Tilted plates, or plate-like regions such as signs and grilles, can mislead the method.
* Future work: perspective correction, Hough lines, or a CNN detector.
