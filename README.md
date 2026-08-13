Used to quantify Insulin, Glucagon, Tomato, and tissue area.  
Using FIJI version 21.0.7 (64-bit). 
Use the QuPath-to-FIJI Pipeline First and open the GeoJSON file to convert into a ZIP
Then open FIJI and open the main VSI, then when it opens up the finder again later use the ZIP file made in the last step.
Some notes: 
In the code to change brightness and contrast or threshold put -1 in the number areas at the top.
Can change colors in "Open .VSI section" to preferred colors
Section 1 is series index 17, Section 2 is series index 25, series 3 is 33.
The outputs folder at the end does not make a new folder every time, so before running again on the same slide make sure to move the contents or change the name
Used for Insulin in channel 488 and Glucagon in channel 647
