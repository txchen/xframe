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

**Local Console Session**:
A play session with an Xbox console on the same local network as XFrame. Game video, audio, and controller input travel over that local network.
_Avoid_: Cloud Gaming Session, Internet Remote Play

**Xbox Sign-in**:
A verified Microsoft account with an Xbox profile in XFrame. It is distinct from authorization for Cloud Gaming or a particular console.
_Avoid_: Cloud Gaming Access

**Cloud Gaming Access**:
Authorization to use an Xbox Cloud Gaming offering for the signed-in profile. It does not establish access to a console.
_Avoid_: Xbox Sign-in, Console Access

**Console Access**:
Authorization for the signed-in profile to start a Local Console Session on a particular Xbox. It does not require Cloud Gaming Access.
_Avoid_: Cloud Gaming Access

**Associated Console**:
An Xbox listed for the signed-in profile, regardless of whether it is reachable from the current local network.
_Avoid_: Locally Available Console

**Locally Available Console**:
An Associated Console that XFrame can reach on the current local network. Being listed for the account alone does not make a console locally available.
_Avoid_: Online Console

**Wake Console**:
An explicit user request to bring an Associated Console out of standby. Waking the console does not start a Local Console Session.
_Avoid_: Connect, Start Session

**Disconnect Local Console Session**:
An explicit request to end XFrame's stream and controller connection to the console while leaving the console powered on and its game unchanged.
_Avoid_: End Session, Power Off

**Active Streaming Session**:
The one cloud or local console stream currently being started, played, or cleaned up by XFrame. A second stream cannot start until the current session's cleanup is complete.
_Avoid_: Playback Window

**Local Session Recovery**:
An attempt to restore a temporarily interrupted Local Console Session without waking the console, launching a game, or starting a replacement session.
_Avoid_: New Session, Wake Console
