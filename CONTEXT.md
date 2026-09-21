# XFrame

XFrame is a native Apple-platform client for Xbox Cloud Gaming and Xbox Console Remote Play, starting with macOS.

## Language

**Aspect Fit**:
A display mode that preserves the entire source image and its aspect ratio, with black bars in any unused area.
_Avoid_: Stretch, crop-to-fill

**Static Test Pattern**:
A generated, nonmoving image containing a grid, circles, color patches, and edge markers for checking image proportions, cropping, and display clarity.
_Avoid_: Test video

**Backing Pixels**:
The pixels of the rendering surface, distinct from the logical points used to lay out the application window.
_Avoid_: Logical window size
