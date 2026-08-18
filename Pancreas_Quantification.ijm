// ============================================================================
// --- PANCREAS SECTION QUANTIFICATION MACRO (.VSI WORKFLOW) v10 -------------
// --- Channels: C1=DAPI, C2=Insulin, C3=Glucagon, C4=Tomato -----------------
// ============================================================================
//Notes: In the code to change brightness and contrast or threshold put -1 in the number areas at the top. 
//Can change colors in "Open .VSI section" to preferred colors
//Section 1 is series index 17, Section 2 is series index 25, series 3 is 33.
//The outputs folder at the end does not make a new folder every time, so before running again on the same slide make sure to move the contents or change the name
//Used for Insulin in channel 488 and Glucagon in channel 647: FITC = Insulin, TRITC= Tomato, Cy5 = Glucagon
// ============================================================================
// --- USER CONFIGURATION -----------------------------------------------------
// ============================================================================
calibrationScale  = 1.3;
seriesIndex       = 33; // Section 1=17, Section 2=25, Section 3=33

minSizeDebris     = 0;
minSizeNuclei     = 1;
minTissueSize     = 0.05;

// Global: set in Step 3, read by ensureIsletMask(). Empty until then.
isletMaskBackupPath = "";

// Stain thresholds: set to -1 for interactive, or hardcode once validated
fixedThresh_Insulin  = -1;
fixedThresh_Glucagon = -1;
fixedThresh_Tomato   = -1;

// Brightness/contrast: set to -1 for interactive, or hardcode once validated
// To find values: run interactively, note Min/Max shown in B/C window, paste here
fixedBC_DAPI_min     = 0;     fixedBC_DAPI_max     = 1768;
fixedBC_Insulin_min  = -1;    fixedBC_Insulin_max  = -1;
fixedBC_Glucagon_min = -1;    fixedBC_Glucagon_max = -1;
fixedBC_Tomato_min   = -1;   fixedBC_Tomato_max   = -1;

// ============================================================================
// --- CORE SAFETY HELPERS -----------------------------------------------------
// ============================================================================

// Closes a window only if it currently exists. Never errors.
function safeClose(name) {
    if (isOpen(name)) {
        selectWindow(name);
        close();
    }
}

// Closes the currently active image, whatever it is titled.
// Use this right after saveAs(), which silently retitles the active window.
function safeCloseActive() {
    if (nImages > 0) {
        close();
    }
}

// Duplicates sourceWindow into a window guaranteed to be named newName.
// If newName already exists (leftover from a previous run/step) it is
// closed first so "Duplicate..." cannot collide with it or get auto-suffixed.
function safeDuplicate(sourceWindow, newName) {
    safeClose(newName);
    selectWindow(sourceWindow);
    run("Duplicate...", "title=" + newName);
}

// Runs Analyze Particles with show=[Masks] on sourceWindow, sums the Area
// column for sizeRange, then takes ImageJ's auto-named "Mask of <source>"
// result and renames it to destName (closing any stale destName first).
// Returns the summed area. sourceWindow itself is left untouched.
function particleMaskAndArea(sourceWindow, sizeRange, destName) {
    selectWindow(sourceWindow);
    print("=== " + sourceWindow + " diagnostics ===");
    print("bitDepth: " + bitDepth());
    print("selectionType: " + selectionType());
    getStatistics(aX, meanX, minX, maxX);
    print("min:" + minX + " max:" + maxX + " mean:" + meanX);

    // Normalize to clean 0/255 non-inverting binary before analysis.
    // imageCalculator/ROI-derived masks can carry an inverting LUT or a
    // non-255 foreground value, which makes Analyze Particles silently miss them.
    normSrc = "TMP_NormForParticles";
    safeClose(normSrc);
    selectWindow(sourceWindow);
    run("Duplicate...", "title=" + normSrc);
    selectWindow(normSrc);
    if (is("Inverting LUT")) { run("Invert LUT"); }
    setThreshold(1, 255);
    run("Convert to Mask");
    resetThreshold();

    setThreshold(1, 255);
    run("Analyze Particles...", "size=" + sizeRange + " show=[Masks] display clear");
    resetThreshold();

    print("particleMaskAndArea(" + sourceWindow + "): nResults = " + nResults);

    total = 0;
    for (r = 0; r < nResults; r++) { total += getResult("Area", r); }
    run("Clear Results");

    autoName = "Mask of " + normSrc;
    safeClose(normSrc);
    safeClose(destName);
    if (isOpen(autoName)) {
        selectWindow(autoName);
        rename(destName);
    } else {
        selectWindow(sourceWindow);
        getDimensions(w, h, c, s, f);
        newImage(destName, "8-bit black", w, h, 1);
    }

    // force normal (non-inverting) grayscale display
    selectWindow(destName);
    if (is("Inverting LUT")) { run("Invert LUT"); }
    run("Grays");

    return total;
}

// Same as particleMaskAndArea but discards the generated mask window
// (used when only the area total is needed, e.g. tissue/islet totals).
function maskArea(sourceWindow, sizeRange) {
    tmpDest = "TMP_AreaOnly";
    total = particleMaskAndArea(sourceWindow, sizeRange, tmpDest);
    safeClose(tmpDest);
    return total;
}

function interactiveThreshold(windowName, label) {
    tmp = "TMP_ThreshPreview";
    safeDuplicate(windowName, tmp);
    selectWindow(tmp);
    run("Enhance Contrast", "saturated=0.35");
    run("Threshold...");
    waitForUser("SET THRESHOLD: " + label,
        "Adjust the lower slider until only real " + label + " signal\n" +
        "is highlighted red. Background should stay dark.\n\n" +
        "Click OK here when done (do NOT click Apply in the Threshold window).");
    getThreshold(lowerVal, upperVal);
    safeClose("Threshold");
    safeClose(tmp);
    print(label + " threshold: " + lowerVal);
    return lowerVal;
}

function manualCleanup(maskName, label) {
    selectWindow(maskName);
    waitForUser("CLEANUP: " + label,
        "Remove any false-positive regions from the " + label + " mask:\n\n" +
        "  1. Press F for Freehand Selection\n" +
        "  2. Draw around the bad region\n" +
        "  3. Press DELETE to erase it\n" +
        "  4. Press Ctrl+D to deselect, repeat as needed\n\n" +
        "Click OK when finished (or immediately if nothing to remove).");
    run("Select None");
}

// Saves windowName as an 8-bit binary mask TIFF at savePath, via a disposable
// duplicate. Leaves windowName itself untouched.
function saveDarkMask(windowName, savePath) {
    tmp = "TMP_SaveDark";
    safeDuplicate(windowName, tmp);
    selectWindow(tmp);
    run("8-bit");
    getStatistics(area, mean, min, max);
    if (max > 0) {
        setThreshold(1, 255);
        run("Convert to Mask");
        resetThreshold();
    }
    saveAs("Tiff", savePath);
    safeCloseActive(); // saveAs() retitles the window, so close by "active" not by name
}

// forceBinary: ensures a mask window is true 8-bit binary (0 and 255 only)
// Call this before Erode or any morphological operation on a mask
function forceBinary(windowName) {
    selectWindow(windowName);
    run("8-bit");
    setThreshold(1, 255);
    run("Convert to Mask");
    resetThreshold();
}

// Draws an outline of maskWindow onto a contrast-enhanced RGB copy of
// originalWindow and saves/reviews it. Uses only unique TMP_* scratch
// windows so it cannot collide with anything else in the macro, and
// guarantees every scratch window it creates is closed before returning.
function showOverlay(originalWindow, maskWindow, label, outlineColor, savePath) {
    tmpBase    = "TMP_QC_Base";
    tmpMask    = "TMP_QC_Mask";
    tmpEroded  = "TMP_QC_Eroded";
    tmpOutline = "TMP_QC_Outline";

    safeDuplicate(originalWindow, tmpBase);
    selectWindow(tmpBase);
    run("Enhance Contrast", "saturated=0.35");
    run("RGB Color");

    safeDuplicate(maskWindow, tmpMask);
    forceBinary(tmpMask);

    safeDuplicate(tmpMask, tmpEroded);
    selectWindow(tmpEroded);
    run("Erode");

    safeClose(tmpOutline);
    imageCalculator("Subtract create", tmpMask, tmpEroded);
    rename(tmpOutline);
    safeClose(tmpMask);
    safeClose(tmpEroded);

    selectWindow(tmpOutline);
    setThreshold(1, 255);
    run("Create Selection");
    resetThreshold();
    hasSelection = (selectionType() != -1);

    if (hasSelection) {
        selectWindow(tmpBase);
        run("Restore Selection");
setForegroundColor(255, 255, 0);
        run("Draw", "slice");
        run("Select None");
    } else {
        print("WARNING: No outline found for " + label + " — mask may be empty.");
    }
    safeClose(tmpOutline);

    selectWindow(tmpBase);
    saveAs("Tiff", savePath);
    // saveAs() retitled the active window away from tmpBase; re-grab it by title.
    qcTitle = getTitle();

    setBatchMode(false);
    selectWindow(qcTitle);
    run("Scale to Fit");
    waitForUser("QC REVIEW: " + label,
        "The " + outlineColor + " outline shows where the " + label + " mask sits\n" +
        "relative to the original channel signal.\n\n" +
        "Check that the outline tightly follows real positive cells.\n" +
        "If it looks off, note it — you can adjust thresholds and re-run.\n\n" +
        "Press + to zoom, Space+drag to pan.\n" +
        "Click OK to continue.");
    setBatchMode(true);
    safeClose(qcTitle);
}

// Builds a single-channel binary mask window (destName) from every ROI
// currently in the ROI Manager, sized to match referenceWindow.
// Guarantees Islet_Master_Mask exists right before it's used. The ROI
// Manager is visible and editable throughout Steps 4-7 (manualCleanup lets
// the user press Delete while the ROI Manager panel happens to have focus),
// so rebuilding from roiManager() is not reliable. Instead we restore from
// a true pixel backup taken once, right after the mask is first built.
function ensureIsletMask() {
    if (!isOpen("Islet_Master_Mask")) {
        if (isletMaskBackupPath == "" || !File.exists(isletMaskBackupPath)) {
            exit("ERROR: 'Islet_Master_Mask' is missing and no backup file exists to restore from.\n" +
                 "This should not happen — please re-run the macro from the start.");
        }
        open(isletMaskBackupPath);
        rename("Islet_Master_Mask");
        // restored TIFF may carry an inverting LUT / non-255 foreground; normalize
        selectWindow("Islet_Master_Mask");
        if (is("Inverting LUT")) { run("Invert LUT"); }
        setThreshold(1, 255);
        run("Convert to Mask");
        resetThreshold();
        run("Grays");
    }
}

function roisToMask(referenceWindow, destName) {
 safeClose(destName);
    selectWindow(referenceWindow);
    getDimensions(imgW, imgH, ch, sl, fr);
    newImage(destName, "8-bit black", imgW, imgH, 1);
    n = roiManager("count");
    for (i = 0; i < n; i++) {
        selectWindow(destName);
        roiManager("Select", i);
        setColor(255);   // fill with pixel VALUE 255, not the global foreground COLOR
        fill();
    }
    run("Select None");
    // guarantee a clean, non-inverting 0/255 binary mask
    selectWindow(destName);
    if (is("Inverting LUT")) { run("Invert LUT"); }
    setThreshold(1, 255);
    run("Convert to Mask");
    resetThreshold();
    run("Grays");
}


// ============================================================================
// --- OPEN .VSI, SET SCALE, ASSIGN LUTs -------------------------------------
// ============================================================================
vsiPath = File.openDialog("Select your .vsi file:");
slideID = File.getNameWithoutExtension(vsiPath);

run("Bio-Formats Importer",
    "open=[" + vsiPath + "] " +
    "autoscale " +
    "color_mode=Composite " +
    "rois_import=[ROI manager] " +
    "view=Hyperstack " +
    "stack_order=XYCZT " +
    "series_" + seriesIndex);

rawTitle = getTitle();
run("Set Scale...", "distance=" + calibrationScale + " known=1 unit=um global");

Stack.setChannel(1); run("Blue");
Stack.setChannel(2); run("Magenta");
Stack.setChannel(3); run("Green");
Stack.setChannel(4); run("Grays");
for (c = 1; c <= 4; c++) {
    Stack.setChannel(c);
    run("Enhance Contrast", "saturated=0.35");
}
Stack.setChannel(1);

channelNames = newArray("DAPI (Blue)", "Insulin (Magenta)", "Glucagon (Green)", "Tomato (Gray)");
channelCodes = newArray("1000", "0100", "0010", "0001");
bcMins = newArray(fixedBC_DAPI_min, fixedBC_Insulin_min, fixedBC_Glucagon_min, fixedBC_Tomato_min);
bcMaxs = newArray(fixedBC_DAPI_max, fixedBC_Insulin_max, fixedBC_Glucagon_max, fixedBC_Tomato_max);

run("Scale to Fit");

for (c = 1; c <= 4; c++) {
    Stack.setChannel(c);
    Stack.setActiveChannels(channelCodes[c-1]);
    if (bcMins[c-1] == -1) {
        // Interactive mode
        run("Brightness/Contrast...");
        waitForUser("Adjust Brightness: " + channelNames[c-1],
            "Only Channel " + c + " (" + channelNames[c-1] + ") is visible.\n\n" +
            "Adjust the Min/Max sliders until the staining looks right.\n" +
            "Note the Min/Max values to hardcode them later.\n" +
            "Press +/- to zoom in/out, Space+drag to pan.\n\n" +
            "Click OK to move to the next channel.");
    } else {
        // Hardcoded mode
        setMinAndMax(bcMins[c-1], bcMaxs[c-1]);
        print(channelNames[c-1] + " B/C set to: " + bcMins[c-1] + " - " + bcMaxs[c-1]);
    }
}

Stack.setActiveChannels("1111");

run("Split Channels");
selectWindow("C1-" + rawTitle); rename("DAPI");
selectWindow("C2-" + rawTitle); rename("Insulin");
selectWindow("C3-" + rawTitle); rename("Glucagon");
selectWindow("C4-" + rawTitle); rename("Tomato");

vsiDir       = File.getParent(vsiPath) + File.separator;
outputFolder = vsiDir + slideID + "_outputs" + File.separator;
if (!File.exists(outputFolder)) { File.makeDirectory(outputFolder); }

run("Set Measurements...", "area redirect=None decimal=3");
setOption("BlackBackground", true);
roiManager("reset");
setBatchMode(false);

// ============================================================================
// --- STEP 1: TOTAL PANCREAS AREA (manual threshold + heavy blur) -------------
// ============================================================================
print("Step 1: Measuring Total Pancreas Area...");

setBatchMode(false);


// Duplicate DAPI
safeDuplicate("DAPI", "TMP_DAPI_Tissue");

selectWindow("TMP_DAPI_Tissue");


// Heavy blur to create a continuous tissue signal
run("Gaussian Blur...", "sigma=15");


// Improve visualization before thresholding
run("Enhance Contrast", "saturated=0.35");


// Manual threshold
run("Threshold...");

waitForUser("SET PANCREAS TISSUE THRESHOLD",
    "Adjust threshold until the ENTIRE pancreas tissue region is highlighted.\n\n" +
    "The blurred DAPI signal should create one continuous tissue block.\n" +
    "Do not worry about individual nuclei — we are measuring total tissue area.\n\n" +
    "Click OK when satisfied.\n" +
    "Do NOT click Apply in the Threshold window.");

getThreshold(tissueLower, tissueUpper);

print("Tissue threshold = " + tissueLower);


// Convert to binary mask
run("Convert to Mask");
resetThreshold();

rename("Tissue_Mask");


// Fill remaining gaps
selectWindow("Tissue_Mask");
run("Fill Holes");


// Morphological closing to connect small gaps
run("Options...", "iterations=3 count=1 black do=Close");


// Normalize display
if (is("Inverting LUT")) {
    run("Invert LUT");
}

run("Grays");


// Measure total tissue area
totalTissueArea = maskArea("Tissue_Mask", "0-Infinity");

print("Total Tissue Area = " + totalTissueArea + " um^2");


// Save mask
saveDarkMask("Tissue_Mask",
    outputFolder + "Fig1_Total_Tissue_Mask.tif");


// QC
showOverlay("DAPI",
            "Tissue_Mask",
            "Total Pancreas Tissue",
            "yellow",
            outputFolder + "QC1_Tissue_Overlay.tif");


safeClose("TMP_DAPI_Tissue");

// ============================================================================
// --- STEP 2: ISLET ROIs (load saved or draw new) ---------------------------
// ============================================================================
print("Step 2: Setting up islet ROIs...");

// ----------------------------------------------------
// USER SELECTS ISLET ROI ZIP FILE
// ----------------------------------------------------
print("Choose Islet ROI ZIP file");
existingIsletROIs = File.openDialog("Choose Islet ROI ZIP file");

if (existingIsletROIs == "") {
    exit("No islet ROI file selected.");
}


// ----------------------------------------------------
// LOAD SAVED ISLET ROIs
// ----------------------------------------------------

roiManager("reset");
roiManager("Open", existingIsletROIs);

nIslets = roiManager("count");

print("Loaded " + nIslets + " existing islet ROIs.");


// ----------------------------------------------------
// Show on combined Ins+Glu image for review
// ----------------------------------------------------

setBatchMode(false);

safeDuplicate("Insulin", "TMP_ins_review");
safeDuplicate("Glucagon", "TMP_glu_review");

selectWindow("TMP_ins_review");
run("8-bit");
run("Magenta");
run("RGB Color");

selectWindow("TMP_glu_review");
run("8-bit");
run("Green");
run("RGB Color");

safeClose("Combined_For_Review");

imageCalculator(
    "Add create",
    "TMP_ins_review",
    "TMP_glu_review"
);

rename("Combined_For_Review");

safeClose("TMP_ins_review");
safeClose("TMP_glu_review");


selectWindow("Combined_For_Review");

run("Enhance Contrast", "saturated=0.35");
run("Scale to Fit");

roiManager("Show All");


// ----------------------------------------------------
// Allow user to edit ROIs
// ----------------------------------------------------

waitForUser(
    "Review Loaded Islet ROIs",
    "Loaded islet ROIs are shown on the combined Insulin + Glucagon image.\n\n" +
    "To remove an unwanted ROI:\n" +
    "  1. Click it in the ROI Manager list\n" +
    "  2. Click Delete in the ROI Manager\n\n" +
    "To add a missing islet:\n" +
    "  1. Press F for Freehand Selection\n" +
    "  2. Trace around the islet\n" +
    "  3. Press T to add it\n\n" +
    "Click OK when finished."
);


nIslets = roiManager("count");


// ----------------------------------------------------
// Save updated ROIs using normal naming
// ----------------------------------------------------

roiManager("Save", outputFolder + slideID + "_Islet_ROIs.zip");

print(
    "Updated islet ROIs saved: " +
    nIslets +
    " total."
);


safeClose("Combined_For_Review");

// ============================================================================
// --- STEP 3: CONVERT ISLET ROIs TO A SINGLE BINARY MASK -------------------
// ============================================================================
print("Step 3: Building islet master mask...");

setBatchMode(true);
roisToMask("DAPI", "Islet_Master_Mask");

// Backup saved to disk — immune to accidental window closure during
// interactive pauses (setBatchMode(false) makes all hidden windows visible,
// so a window-based backup gets closed by the user as clutter).
safeClose("Islet_Master_Mask_BACKUP");
isletMaskBackupPath = outputFolder + slideID + "_Islet_Master_Mask_BACKUP.tif";
selectWindow("Islet_Master_Mask");
run("Duplicate...", "title=Islet_Master_Mask_BACKUP");
saveAs("Tiff", isletMaskBackupPath);
safeCloseActive();
selectWindow("Islet_Master_Mask");

saveDarkMask("Islet_Master_Mask", outputFolder + "Fig2_Islet_ROI_Mask.tif");
showOverlay("Insulin", "Islet_Master_Mask", "Islet Boundary", "yellow", outputFolder + "QC2_Islet_Overlay.tif");

// ============================================================================
// --- STEP 4: SET STAIN THRESHOLDS ------------------------------------------
// ============================================================================

setBatchMode(false);

// Hide windows not needed for thresholding so they can't be accidentally closed

showMessage("Step 4: Set Stain Thresholds",
    "Now set thresholds for Insulin, Glucagon, and Tomato.\n" +
    "Adjust until only real positive cells are highlighted red.\n\n" +
    "Click OK to begin with Insulin.");

if (fixedThresh_Insulin  == -1) { thresh_Insulin  = interactiveThreshold("Insulin",  "Insulin");  }
else { thresh_Insulin  = fixedThresh_Insulin; }

if (fixedThresh_Glucagon == -1) { thresh_Glucagon = interactiveThreshold("Glucagon", "Glucagon"); }
else { thresh_Glucagon = fixedThresh_Glucagon; }

if (fixedThresh_Tomato   == -1) { thresh_Tomato   = interactiveThreshold("Tomato",   "Tomato");   }
else { thresh_Tomato   = fixedThresh_Tomato; }

showMessage("Thresholds Confirmed",
    "Insulin:  " + thresh_Insulin  + "\n" +
    "Glucagon: " + thresh_Glucagon + "\n" +
    "Tomato:   " + thresh_Tomato   + "\n\n" +
    "Running measurements now. Click OK to continue.");

setBatchMode(true);

// ============================================================================
// --- STEP 5: INSULIN AREA (inside islets) -----------------------------------
// ============================================================================
ensureIsletMask();
print("Step 5: Measuring Insulin Area...");

// Build one composite selection from all islet ROIs
roiManager("Deselect");
if (roiManager("count") > 1)
    roiManager("Combine");
else
    roiManager("Select", 0);

// Create thresholded insulin mask
safeDuplicate("Insulin", "TMP_Insulin_Calc");
selectWindow("TMP_Insulin_Calc");

setThreshold(thresh_Insulin, 65535);
run("Convert to Mask");
resetThreshold();

// Restore islet selection so Analyze Particles is restricted to islets
run("Restore Selection");

run("Set Measurements...", "area redirect=None decimal=3");
run("Analyze Particles...",
    "size=" + minSizeDebris + "-Infinity show=[Masks] clear restrict");

// Sum particle areas
insulinArea = 0;
for (r = 0; r < nResults; r++)
    insulinArea += getResult("Area", r);

run("Clear Results");
print("Insulin area = " + insulinArea);

// Rename generated mask
autoName = "Mask of TMP_Insulin_Calc";
safeClose("Insulin_Clean_Mask");

if (isOpen(autoName)) {
    selectWindow(autoName);
    rename("Insulin_Clean_Mask");
} else {
    selectWindow("TMP_Insulin_Calc");
    getDimensions(w, h, c, s, f);
    newImage("Insulin_Clean_Mask", "8-bit black", w, h, 1);
}

selectWindow("Insulin_Clean_Mask");
if (is("Inverting LUT"))
    run("Invert LUT");
run("Grays");

// Save outputs
setBatchMode(false);

saveDarkMask("Insulin_Clean_Mask",
    outputFolder + "Fig3_Insulin_Mask.tif");

showOverlay("Insulin",
            "Insulin_Clean_Mask",
            "Insulin",
            "yellow",
            outputFolder + "QC3_Insulin_Overlay.tif");

setBatchMode(true);

// Cleanup
safeClose("TMP_Insulin_Calc");
safeClose("Insulin_Clean_Mask");
// ============================================================================
// --- STEP 6: GLUCAGON AREA (inside islets) ----------------------------------
// ============================================================================
ensureIsletMask();
print("Step 6: Measuring Glucagon Area...");

// Build one composite selection from all islet ROIs
roiManager("Deselect");
if (roiManager("count") > 1)
    roiManager("Combine");
else
    roiManager("Select", 0);

// Create thresholded glucagon mask
safeDuplicate("Glucagon", "TMP_Glucagon_Calc");
selectWindow("TMP_Glucagon_Calc");

setThreshold(thresh_Glucagon, 65535);
run("Convert to Mask");
resetThreshold();

// Restrict analysis to islet regions
run("Restore Selection");

run("Set Measurements...", "area redirect=None decimal=3");
run("Analyze Particles...",
    "size=" + minSizeDebris + "-Infinity show=[Masks] clear restrict");

// Sum particle areas
glucagonArea = 0;
for (r = 0; r < nResults; r++)
    glucagonArea += getResult("Area", r);

run("Clear Results");
print("Glucagon area = " + glucagonArea);

// Rename generated mask
autoName = "Mask of TMP_Glucagon_Calc";
safeClose("Glucagon_Clean_Mask");

if (isOpen(autoName)) {
    selectWindow(autoName);
    rename("Glucagon_Clean_Mask");
} else {
    selectWindow("TMP_Glucagon_Calc");
    getDimensions(w, h, c, s, f);
    newImage("Glucagon_Clean_Mask", "8-bit black", w, h, 1);
}

selectWindow("Glucagon_Clean_Mask");
if (is("Inverting LUT"))
    run("Invert LUT");
run("Grays");

setBatchMode(false);

saveDarkMask("Glucagon_Clean_Mask",
    outputFolder + "Fig3_Glucagon_Mask.tif");

showOverlay("Glucagon",
            "Glucagon_Clean_Mask",
            "Glucagon",
            "yellow",
            outputFolder + "QC3_Glucagon_Overlay.tif");

setBatchMode(true);

safeClose("TMP_Glucagon_Calc");
safeClose("Glucagon_Clean_Mask");

// ============================================================================
// --- STEP 7: TOMATO AREA (inside islets) ------------------------------------
// ============================================================================
ensureIsletMask();
print("Step 7: Measuring Tomato Area...");

// Build one composite selection from all islet ROIs
roiManager("Deselect");
if (roiManager("count") > 1)
    roiManager("Combine");
else
    roiManager("Select", 0);

// Create thresholded Tomato mask
safeDuplicate("Tomato", "TMP_Tomato_Calc");
selectWindow("TMP_Tomato_Calc");

setThreshold(thresh_Tomato, 65535);
run("Convert to Mask");
resetThreshold();

// Restrict analysis to islet regions
run("Restore Selection");

run("Set Measurements...", "area redirect=None decimal=3");
run("Analyze Particles...",
    "size=" + minSizeDebris + "-Infinity show=[Masks] clear restrict");

// Sum particle areas
tomatoArea = 0;
for (r = 0; r < nResults; r++)
    tomatoArea += getResult("Area", r);

run("Clear Results");
print("Tomato area = " + tomatoArea);

// Rename generated mask
autoName = "Mask of TMP_Tomato_Calc";
safeClose("Tomato_Clean_Mask");

if (isOpen(autoName)) {
    selectWindow(autoName);
    rename("Tomato_Clean_Mask");
} else {
    selectWindow("TMP_Tomato_Calc");
    getDimensions(w, h, c, s, f);
    newImage("Tomato_Clean_Mask", "8-bit black", w, h, 1);
}

selectWindow("Tomato_Clean_Mask");
if (is("Inverting LUT"))
    run("Invert LUT");
run("Grays");

setBatchMode(false);

saveDarkMask("Tomato_Clean_Mask",
    outputFolder + "Fig3_Tomato_Mask.tif");

showOverlay("Tomato",
            "Tomato_Clean_Mask",
            "Tomato",
            "yellow",
            outputFolder + "QC3_Tomato_Overlay.tif");

setBatchMode(true);

safeClose("TMP_Tomato_Calc");
safeClose("Tomato_Clean_Mask");

// ============================================================================
// --- STEP 8: TOTAL ISLET AREA (Insulin + Glucagon) ---------------------------
// ============================================================================
ensureIsletMask();
print("Step 8: Measuring Total Islet Area...");

// Build one composite selection from all islet ROIs
roiManager("Deselect");
if (roiManager("count") > 1)
    roiManager("Combine");
else
    roiManager("Select", 0);


// -------------------- INSULIN MASK --------------------
safeDuplicate("Insulin", "TMP_Insulin_Islet");
selectWindow("TMP_Insulin_Islet");

run("Gaussian Blur...", "sigma=8");
setThreshold(thresh_Insulin, 65535);
run("Convert to Mask");
resetThreshold();

rename("Insulin_Islet_Mask");


// -------------------- GLUCAGON MASK --------------------
safeDuplicate("Glucagon", "TMP_Glucagon_Islet");
selectWindow("TMP_Glucagon_Islet");

run("Gaussian Blur...", "sigma=8");
setThreshold(thresh_Glucagon, 65535);

run("Convert to Mask");
resetThreshold();

rename("Glucagon_Islet_Mask");


// -------------------- COMBINE MASKS --------------------
imageCalculator("OR create",
    "Insulin_Islet_Mask",
    "Glucagon_Islet_Mask");

rename("Total_Islet_Mask");


// Restore islet ROI restriction
run("Restore Selection");

run("Set Measurements...", "area redirect=None decimal=3");

run("Analyze Particles...",
    "size=" + minSizeDebris + "-Infinity show=[Masks] clear restrict");


// Sum particle areas
isletArea = 0;
for (r = 0; r < nResults; r++)
    isletArea += getResult("Area", r);

run("Clear Results");

print("Total islet area = " + isletArea);


// -------------------- SAVE MASK --------------------
autoName = "Mask of Total_Islet_Mask";
safeClose("Islet_Clean_Mask");

if (isOpen(autoName)) {
    selectWindow(autoName);
    rename("Islet_Clean_Mask");
} else {
    selectWindow("Total_Islet_Mask");
    getDimensions(w, h, c, s, f);
    newImage("Islet_Clean_Mask", "8-bit black", w, h, 1);
}

selectWindow("Islet_Clean_Mask");

if (is("Inverting LUT"))
    run("Invert LUT");

run("Grays");

saveDarkMask("Islet_Clean_Mask",
    outputFolder + "Fig3_Total_Islet_Mask.tif");

showOverlay("Insulin",
            "Islet_Clean_Mask",
            "Insulin",
            "yellow",
            outputFolder + "QC3_Total_Islet_Overlay.tif");


// Cleanup
safeClose("TMP_Insulin_Islet");
safeClose("TMP_Glucagon_Islet");
safeClose("Insulin_Islet_Mask");
safeClose("Glucagon_Islet_Mask");
safeClose("Total_Islet_Mask");
safeClose("Islet_Clean_Mask");
// ============================================================================
// --- STEP 8: DAPI NUCLEI COUNT (inside islets) ------------------------------
// ============================================================================
print("Step 8: Counting DAPI Nuclei...");

safeDuplicate("DAPI", "TMP_DAPI_Calc");
selectWindow("TMP_DAPI_Calc");
setAutoThreshold("Otsu dark");
run("Convert to Mask");
resetThreshold();
run("Watershed");
run("8-bit");

safeClose("TMP_DAPI_Islet_Only");
ensureIsletMask();
imageCalculator("AND create", "TMP_DAPI_Calc", "Islet_Master_Mask");
rename("TMP_DAPI_Islet_Only");
safeClose("TMP_DAPI_Calc");

selectWindow("TMP_DAPI_Islet_Only");
setThreshold(1, 255);
run("Analyze Particles...", "size=" + minSizeNuclei + "-Infinity show=[Masks] clear");
resetThreshold();
totalIsletDapiCells = nResults;
run("Clear Results");

autoDapiMaskName = "Mask of TMP_DAPI_Islet_Only";
safeClose("DAPI_Islet_Nuclei_Mask");
if (isOpen(autoDapiMaskName)) {
    selectWindow(autoDapiMaskName);
    rename("DAPI_Islet_Nuclei_Mask");
    saveDarkMask("DAPI_Islet_Nuclei_Mask", outputFolder + "Fig6_DAPI_Islet_Nuclei_Mask.tif");
    safeClose("DAPI_Islet_Nuclei_Mask");
}
safeClose("TMP_DAPI_Islet_Only");

// ============================================================================
// --- CLEANUP & REPORT -------------------------------------------------------
// ============================================================================
while (nImages > 0) { selectImage(nImages); close(); }
roiManager("reset");

isletFraction    = (isletArea / totalTissueArea) * 100;

insulinFraction  = (insulinArea / isletArea) * 100;
glucagonFraction = (glucagonArea / isletArea) * 100;
tomatoFraction   = (tomatoArea / isletArea) * 100;

insulinOfTissue  = (insulinArea / totalTissueArea) * 100;
glucagonOfTissue = (glucagonArea / totalTissueArea) * 100;
tomatoOfTissue   = (tomatoArea / totalTissueArea) * 100;


// Insulin vs glucagon composition among hormone-positive area
totalHormonePositiveArea = insulinArea + glucagonArea;

insulinOfHormonePositive = 
    (insulinArea / totalHormonePositiveArea) * 100;

glucagonOfHormonePositive = 
    (glucagonArea / totalHormonePositiveArea) * 100;

logFilePath = outputFolder + slideID + "_Pancreas_Metrics.txt";
f = File.open(logFilePath);
print(f, "Slide_ID\t" +
         "Num_Islet_ROIs\t" +
         "Total_Tissue_Area_um2\t" +
         "Total_Islet_Area_um2\t" +
         "Insulin_Area_um2\t" +
         "Glucagon_Area_um2\t" +
         "Tomato_Area_um2\t" +
         "Total_Islet_DAPI_Cells\t" +
         "Islet_pct_of_Tissue\t" +
         "Insulin_pct_of_Islet\t" +
         "Glucagon_pct_of_Islet\t" +
         "Tomato_pct_of_Islet\t" +
         "Insulin_pct_of_Tissue\t" +
         "Glucagon_pct_of_Tissue\t" +
         "Tomato_pct_of_Tissue\t" +
         "Insulin_pct_of_Hormone_Positive\t" +
         "Glucagon_pct_of_Hormone_Positive\t" +
         "Thresh_Insulin\t" +
         "Thresh_Glucagon\t" +
         "Thresh_Tomato");
         
print(f, slideID + "\t" +
         nIslets             + "\t" +
         totalTissueArea     + "\t" +
         isletArea           + "\t" +
         insulinArea         + "\t" +
         glucagonArea        + "\t" +
         tomatoArea          + "\t" +
         totalIsletDapiCells + "\t" +
         isletFraction       + "\t" +
         insulinFraction     + "\t" +
         glucagonFraction    + "\t" +
         tomatoFraction      + "\t" +
         insulinOfTissue     + "\t" +
         glucagonOfTissue    + "\t" +
         tomatoOfTissue      + "\t" +
         insulinOfHormonePositive + "\t" +
         glucagonOfHormonePositive + "\t" +
         thresh_Insulin      + "\t" +
         thresh_Glucagon     + "\t" +
         thresh_Tomato);
         File.close(f);

setBatchMode(false);
print("=== DONE: " + slideID + " ===");
showMessage("Analysis Complete",
    "Results saved to:\n" + outputFolder + "\n\n" +
    "Islets Drawn:     " + nIslets             + "\n" +
    "Tissue Area:      " + totalTissueArea      + " um^2\n" +
    "Islet Area:       " + isletArea       + " um^2  (" + isletFraction    + "% of tissue)\n" +
    "Insulin Area:     " + insulinArea          + " um^2  (" + insulinFraction  + "% of islet)\n" +
    "Glucagon Area:    " + glucagonArea         + " um^2  (" + glucagonFraction + "% of islet)\n" +
    "Tomato Area:      " + tomatoArea           + " um^2  (" + tomatoFraction   + "% of islet)\n" +
    "Insulin % of Ins+Glucagon: " + insulinOfHormonePositive + "%\n" +
    "Glucagon % of Ins+Glucagon: " + glucagonOfHormonePositive + "%\n" +
    "Islet DAPI Cells: " + totalIsletDapiCells);
