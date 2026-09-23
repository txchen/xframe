# Third-Party Notices

## Big Buck Bunny benchmark clip

The built-in post-processing benchmark includes a six-second, silent 1080p30
excerpt of *Big Buck Bunny*, copyright 2008 Blender Foundation / www.bigbuckbunny.org,
licensed under [Creative Commons Attribution 3.0](https://creativecommons.org/licenses/by/3.0/).
It was derived from the [1080p60 sample mirror](https://github.com/bower-media-samples/big-buck-bunny-1080p-60fps-30s)
at commit `c4c7ec6aa5d68944d32faa28f332f999c8866cbc` by trimming seconds
6–12, converting to 30 fps H.264, and removing audio. The included file's
SHA-256 is `5872055dcb979f5d469ede9c575e60418bc9d7731e0528c05ee0817cc0b08633`.

## Optional MLX-DLSS benchmark helper

The release app builds the video-only frame-generation helper from
[iamwavecut/MLX-DLSS](https://github.com/iamwavecut/MLX-DLSS) at commit
`0ca2deab092fe6f3e331bf4f616271dbc64521d0` (Apache 2.0), with
[mlx-swift](https://github.com/ml-explore/mlx-swift) 0.31.6 and matching MLX
Metal 0.31.1 kernels (MIT). Their full license and notice files are included
under `Resources/Licenses/`. Model weights are supplied by the user at runtime
and are not distributed with XFrame.

## XStreaming

XFrame's Microsoft/Xbox/xCloud authentication, catalog, session, and streaming protocol implementations were informed by and adapted from [Geocld/XStreaming](https://github.com/Geocld/XStreaming), commit `383e19d324f2d3029d1c304752f4d38a9360bb95`, particularly `src/xal/msal.ts`, `src/MsalAuthentication.ts`, `src/xCloud/index.ts`, and the `src/webrtc/` channel and packet implementations.

The MIT License (MIT)

Copyright (c) 2024 Geocld (lijiahao5372@gmail.com)

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the “Software”), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

## WebRTC

XFrame links WebRTC 153.0.0, distributed by [stasel/WebRTC](https://github.com/stasel/WebRTC/tree/153.0.0). The downloaded XCFramework's license is included as `WebRTC-LICENSE.txt` in the application's Resources directory.

Copyright (c) 2011, The WebRTC project authors. All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

- Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
- Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
- Neither the name of Google nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
