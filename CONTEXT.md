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

**Picture Area**:
The region occupied by the source image under Aspect Fit, measured in Backing Pixels and excluding black bars.
_Avoid_: Window size, canvas size

**Integer Scaling**:
An enlargement in which each source-image pixel becomes an equally sized square block of output pixels, with an integer multiplier and no blending between adjacent source-image pixels during enlargement.
_Avoid_: Super resolution, arbitrary nearest-neighbor scaling

**End Session**:
An explicit request to terminate the cloud gaming session and release its cloud resources. It is complete only when the service confirms cleanup; stopping local playback alone does not complete it.
_Avoid_: Pause, hide playback, disconnect locally
