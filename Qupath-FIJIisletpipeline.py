# QuPath GeoJSON MultiPolygon to Fiji ROI ZIP Converter
# Compatible with Fiji Jython

#@ File(label="Choose QuPath GeoJSON file", style="file") geojsonFile
#@ String(label="Scale factor", value="0.25") scaleFactor
#@ File(label="Choose output folder", style="directory") outputFolder


from ij.plugin.frame import RoiManager
from ij.gui import PolygonRoi, Roi
from java.awt import Polygon
from ij import IJ

import json
import os


# -----------------------------
# Load GeoJSON
# -----------------------------

with open(geojsonFile.getAbsolutePath(), 'r') as f:
    data = json.load(f)


# QuPath FeatureCollection
features = data["features"]


# -----------------------------
# Scale
# -----------------------------

scale = float(scaleFactor)


# -----------------------------
# ROI Manager
# -----------------------------

rm = RoiManager.getInstance()

if rm is None:
    rm = RoiManager()
else:
    rm.reset()


count = 0


# -----------------------------
# Convert annotations
# -----------------------------

for feature in features:

    geometry = feature.get("geometry", {})

    geom_type = geometry.get("type")


    # Only handle polygons
    if geom_type == "Polygon":

        polygon_list = [
            geometry["coordinates"][0]
        ]


    elif geom_type == "MultiPolygon":

        polygon_list = []

        for poly in geometry["coordinates"]:
            polygon_list.append(poly[0])


    else:
        continue



    for coords in polygon_list:

        xpoints = []
        ypoints = []


        for point in coords:

            x = int(round(point[0] * scale))
            y = int(round(point[1] * scale))

            xpoints.append(x)
            ypoints.append(y)



        if len(xpoints) < 3:
            continue


        poly = Polygon(
            xpoints,
            ypoints,
            len(xpoints)
        )


        roi = PolygonRoi(
            poly,
            Roi.POLYGON
        )


        rm.addRoi(roi)

        count += 1



# -----------------------------
# Save ROI ZIP
# -----------------------------

filename = os.path.splitext(
    os.path.basename(
        geojsonFile.getAbsolutePath()
    )
)[0]


# Cleaner filename
filename = filename.replace(
    ".geojson",
    ""
)


savePath = os.path.join(
    outputFolder.getAbsolutePath(),
    filename + "_Islet_ROIs.zip"
)


rm.runCommand(
    "Save",
    savePath
)


print("-------------------------")
print("Converted ROIs:", count)
print("Saved:")
print(savePath)
print("-------------------------")


IJ.showMessage(
    "Finished",
    str(count) + " islet ROIs created.\n\nSaved:\n" + savePath
)