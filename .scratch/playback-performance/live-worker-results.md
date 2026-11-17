# Live Original / MetalFX worker experiments

Active goal: optimize Original latency by approximately one refresh while preserving smooth actual presentation on M1. User authorized continued unattended experiments, no need to ask to continue. MetalFX improvements are secondary evidence, not a reason to switch the goal.

## Harness and acceptance

Experimental XFrame app, real cloud H.264 1080p60 title-menu stream (A Game About Digging A Hole), Standard/Balanced, same M1 4K60 LG monitor, native fullscreen. Five alternating 18-second blocks per side; analyze after trimming first3/last1 seconds, about840 frames per block. No profiler or build during samples. Source FIFO, expiry50ms, catchup25ms unchanged. Same shaders/conversion/MetalFX code. Worker is an experimental duplicate engine, created on main and exclusively used by its worker thread; never accesses AppKit views. Main normal renderer preserved as A. Both have persistent CADisplayLink. Actual FramePresentation timestamps, not planned presentation. All three full runs had zero packet loss/NACK/decode errors and zero missing presentation timestamps in analyzed samples.

Counter reports and raw events are archived under `diagnostics/2026-11-15/live-worker/{ungated,gated-original,gated-metalfx}`. Reported summaries below are median of five per-block statistics. Do not conflate this with physical input-to-photon delay or player-driven gameplay testing.

## Results

| Experiment | Normal arrival-display median ms | Worker median ms | Normal median p95 ms | Worker median p95 ms | Decision |
|---|---:|---:|---:|---:|---|
| Original, worker using only drawable/GPU backpressure | 38.14 | 49.51 | 46.18 | 59.43 | Reject; all5 total medians worse |
| Original, worker capped at2 actual-present-pending frames | 36.84 | 38.55 | 42.74 | 45.94 | Reject for Original; only1of5 medians improved |
| MetalFX1080p-to4K, worker capped at2 | 51.79 | 38.96 | 58.83 | 48.87 | Candidate benefit for MetalFX; all5 improved, not production-ready |

Ungated Original outstanding submitted-but-not-presented frame count: baseline median2 (first block sometimes3), worker median3. Worker display wait ~39–47ms despite small input waiting. Two-slot actual-present gate is verified max2 in stable worker windows; Original display wait becomes ~31ms rather than baseline~22.5ms, so waiting shifts and does not consistently improve total age.

MetalFX paired total medians:
- 51.79 -> 38.96 ms
- 53.40 -> 40.27 ms
- 52.94 -> 43.96 ms
- 48.15 -> 34.57 ms
- 51.43 -> 38.80 ms

MetalFX normal GPU median~6.54ms vs worker~7.63ms (same shader operations but observed GPU cost differs; do not hide it). Post-GPU wait~33ms vs~24ms. Median actual output59.89 vs59.99fps. Across five14s analysis windows: intervals>25ms5 vs3, none>40ms. This is not an exhaustive smoothness/gameplay acceptance test. Original gated had one>40ms interval on each side; neither candidate is assumed universally faster.

## Session lifecycle

First two sessions manually closed with End Session after full runs. MetalFX full180s capture completed around session229.6s with active outcome and noerrors; data saved and archived. A later attempted visual-only repeat hit cloud inactivity/WebRTC closure around the usual~300s window; screenshot showed library, not candidate frame, so visual acceptance was NOT claimed. This does not invalidate earlier completed capture, but a fresh visual run remains needed for any shipped candidate.

## Code state and experiments

Pre-experiment source backups (preserve prior diagnostic work) live in `.build/live-worker-probe/before/` for MetalRenderer.swift, XFrameApp.swift, FramePresentation.swift, LiveVideo.swift. Added experimental source files: LiveWorkerProbe.swift and WorkerProbeEngine.swift. Do not mistake these duplicated diagnostic classes for a production refactor. Full source snapshots of ungated and gated variants are archived with results. No release issued, no default scheduler changed; experimental menu starts automatic A/B. Before shipping, replace duplication with a single renderer core and verify lifecycle/settings/resize/error handling.

Current next candidate: late drawable acquisition, still capped at2 actual pending presentations; wait for source frame before requesting drawable instead of prefetching it. Build `.build/live-worker-probe/late-acquire/XFrame.app`. Must select Original (last UI setting was MetalFX). Need run same five pairs, archive to late-acquire-original, then decide.

Root test file locations (working logs overwritten each new run): `.build/live-worker-probe/events.json`, block-0..9.json, analyze.py. Always archive completed run BEFORE starting another. `beginWorkerProbe` resets memory logs but does not reset global numeric IDs. Source switches stop/join worker and invalidate timer. Callback semaphore cap is2; the old one-slot policy was previously rejected because it caused30fps.

## Late drawable acquisition result

Completed five pairs. Baseline total medians39.07,36.89,35.09,34.17,35.37ms; worker34.06,38.26,35.31,32.14,29.30ms. Mixed paired outcome; no stable one-refresh improvement. Worker GPU-to-display typically~31ms, last block~28ms. Frame rates baseline59.85–60.02, worker59.63–60.05; analyzed gaps>25ms5vs2, >40ms1vs1. No missing presentation timestamps. This weakens the early-drawable-stamping hypothesis as primary cause. Next: scan display-relative submission phase with original renderer/FIFO, then repeat any promising phase across5pairs.

## Submission phase screening

Original/FIFO, eight20s blocks alternating normal MTK and CADisplayLink target-relative submissions. Actual submit before target was8.64,4.80,0.62,-1.00ms for requested10,6,2,0ms leads. Candidate post-GPU waits24.57,20.79,32.99,31.46ms; total40.90,34.05,45.46,41.72ms. Corresponding baseline total49.80,37.26,35.59,40.06ms. Late submissions cross a latch boundary and add roughly a refresh; no evidence for a universal later-is-better policy. Only one block per offset: screening, not accepted winner. Raw/source archived under diagnostics/2026-11-15/phase-sweep.

## Game Mode eligibility screening

Standalone minimal app with both Game Mode plist flags and games category was launched fullscreen. Last900 matched clear-pass frames had median GPU-to-actual47.33ms, submit-to-actual48.10ms. Runtime Game Mode activation was not verified, so this does not establish Game Mode enabled or disabled effect. Read-only window inventory showed Notification Center full-screen surface and MonitorControl1x1 low-alpha surface above the app; no visible ShowyEdge window. Do not attribute Direct rejection to any of these without controlled isolation. No user applications were stopped or settings changed.

Next candidate: ungated worker using2 drawables (normal MTK stays3), allowing compositor drawable return to pace submissions earlier than actual-presentation callback. No actual-presentation semaphore.

## Two-drawable worker result

Five pairs complete, raw and sources archived under pool2-original. Total medians A33.33,34.87,38.31,38.17,33.55ms; B32.64,36.59,41.60,43.38,29.70ms. Only2/5 improve. Post-GPU still28–30ms. Actual output~60fps, analyzed gaps>25ms6vs1, >40ms1vs1. No missing actual stamps or drawable acquisition failures. Reject as stable Original latency improvement. Session ended manually after completed run.

All temporary worker source edits have now been restored from before/ backups; duplicate worker source files removed. Baseline prior diagnostic work remains. Experiment code and isolated apps remain available in archives/build folders. Next investigation is a separate AVSampleBufferDisplayLayer probe; enqueue timing must not be reported as actual presentation.

## AVSampleBufferDisplayLayer exploratory path

Separate synthetic NV12 probe, DisplayImmediately=true, plus tiny2pt Metal marker. Standard Metal System Trace exported no display-surface-swap rows, including all-process capture; display was awake. Correlation uses marker actual presentedTime only when exactly one WindowServer command reads that marker between its submission and presentation, then matches the first WindowServer read of a video IOSurface to that same command, rejecting reuse ambiguity. This diagnostic marker adds work and may affect compositor timing. Synthetic779 video frames: enqueue-to-actual median24.83ms, p9525.66; enqueue-to-WS13.06ms, WS-to-actual11.80ms. Not a live result.

First live1080p60 Original probe displayed actual title-menu game image (CUA screenshot), no shader conversion, AVDisplay layer receives decodedNV12.779 trace-associated frames: arrival-to-actual median33.55ms,p9538.83; enqueue-to-actual31.10ms. However diagnostic marker nextDrawable ran in the video producer loop and could block subsequent video enqueue. This is not an accepted optimization. Next isolated build moves marker work to an independent thread. HUD hidden duringAV path because Metal-derived stats are not valid for it; restore Compact afterwards.

Artifacts: .build/av-display-probe and .build/av-live-probe, synthetic numeric/source archive under diagnostics/2026-11-16/av-display-probe. Initial live numeric/source snapshot in .build/av-live-probe/coupled-marker. Temporary AVLiveProbe.swift and menu/source-wake edits currently installed for experiment; pre-AV backups in .build/av-live-probe/before. No release or default behavior change.

## AV independent-marker screening and five-pair trace

Independent marker15s trace:776 matched video frames, arrival-to-actual median26.02ms,p9530.52; enqueue-to-actual25.78ms. Real game image verified, then ended manually.

Five15s alternating blocks per side, same1080p60 session,4K60fullscreen, HUD hidden, continuous165s Metal System Trace. Trimming first3/last1s per block. A total medians70.76,36.84,42.60,61.97,65.38ms; B22.79,25.58,33.07,26.37,21.85ms. **Do not treat the large differences as accepted performance gains**: baseline shows anomalous extra queue/phase states, and AV cadence degrades later. A actual FPS59.82–60.00. B trace-associated FPS59.82,59.91,58.19,57.64,58.55. Source video surfaces with no WindowServer read before reuse:2,1,18,24,14 in stable blocks; this is not merely missing marker associations. No network packetloss,NACK,decode errors in final active206.4s report. AV immediate policy likely trades some smoothness for age. Need system video metrics to independently count displayed/dropped frames and calibrate accumulated delay, plus a pacedAV candidate if justified. No production adoption. Numeric/source archive diagnostics/2026-11-16/av-live-alternating; raw trace stayslocal.

## RTP timestamped AV variant (zero added lead)

Five pairs complete in active session. A total medians72.82,48.04,52.76,33.05,39.89ms; B26.70,20.93,27.43,20.82,27.71ms. Baseline again has large compositor phase states, so do not report differences as shipped gain. B stable-window associatedFPS59.45,57.55,58.91,57.83,58.10; noWSread counts5,27,12,23,17. AVVideoPerformanceMetrics dropped counts rise in those same periods, confirming real deadline/replacement losses rather than only unmatched markers. Final per-layer dropped26,31,26,25,26 over~894frames, distributed over varying parts of each block. Reject for smoothness.

RTP-derived PTS (anchor firstarrival, no lead) is typically1–3ms before arrival, occasionally11ms early; observed RTP spacing16/17ms. Next candidate adds16.67ms to RTP anchor, allowing queued frames to be known before their intended display rather than all late. This is an experiment, not a claim that buffering is free.

System accumulated delay metric is NOT a usable arrival-to-display estimate here: standaloneDisplayImmediately and live timestamped runs returned~1e-5seconds aggregate for hundreds of frames, inconsistent with linked actual timestamps. Do not use it in HUD or calculate latency gains from it. Dropped counts independently match trace losses. OptimizedCompositing counter high, but do not equate that alone with Metal Direct eligibility.

Timestamped full150s sampling completed before cloud idle/WebRTC closure during cleanup; finalblock report should establish active outcome. GUI returned to library before EndSession action could be applied; no duplicate termination sent. CompactHUD restored and app quit. Numeric/source archive diagnostics/2026-11-16/av-live-timestamped.

## Window-level isolation screening

Standalone opaque fullscreen minimalMetal, five12s pairs, level0 vslevel1001, no user application stopped. Bothlevels remainedfullscreen, stable540frames per9sanalysiswindow,no>25msgaps. PostGPUmedians A39.600,39.603,22.930,39.599,39.606; B22.971,39.630,39.655,39.644,22.963ms. Mixed2/5gain, oneclearregression. Does not establish overlay occlusion as rootcause or usefulfix; noDirecttracecaptured. App automaticallyrestorednormallevel thenquit. Archive diagnostics/2026-11-16/window-level-probe.

## RTP plus16.67ms lead

Fivepairs, normalbaseline this time mostly33–40ms ratherthan earlier50–70msstates. A total40.11,33.58,40.12,33.04,39.76ms; B27.48,20.84,27.23,20.92,26.99ms. B associatedFPS59.64,58.00,59.46,58.19,59.36; noWSread3,20,4,18,5. AVdroppedcountersfinal22,23,16,20,20. Rejectcurrentvariantforsmoothness. Fullrunfinalreportactive220.83s,0loss/NACK/errors; aftercapture CUA reportedappquit duringcleanup, psconfirmed noXFrame, noXFramecrashreportfound. HUDHidden remains torestore; appwasnotreopened yet.

Boundarycheck CMSampleAttachments true/false confirmedNSMutableDictionary mutationsreachCoreMedia; outputPTSretained. Standalone future100ms+falseDisplayImmediately probe produced776joinedframes enqueue-toactual129.85ms (p95130.71), enqueue-toWS100.99ms, WS-toactual28.90ms. Thus timestampinterpretation DOESwork; previoussmallleadtestdidnotproveignoredparameters.

Specificnewhypothesis: sourceRTPspacingis16/17ms (1msgranularity), which can straddlecompositorrefreshboundaries. Nextscreeningcandidate usesstrict60HzPTS anchoredatfirstframearrival+16.67ms and decodedframeindex, onlyforfixed60fps15sblocks. Notproductionclockhandling: longsessions,differentframerates,loss/driftneedseparatevalidation. Raw/sourcefuture100archive diagnostics/2026-11-16/av-future100; lead16archive av-live-lead16.

## Uniform60Hz AV rejection and return to Metal

Fivepairs complete; AVtotalmedians26.80,27.09,21.18,21.98,25.76ms but actualassociatedFPS58.64,57.46,58.10,58.37,59.60 (lastblock59markerassociationgapsmeanscoverageincomplete). Stable-window noWSread13,26,19,17,4. Finalsystemdropped24,28,19,20,10; rejectsquantizedRTPasmaincause. No stable smoothness acceptance; AVbackend notadopted.

Full numeric/sourcearchive diagnostics/2026-11-16/av-live-uniform60. Sessionendedbycloudidleafterfullcapture; libraryverified, CompactHUDrestored,appquit. AlltemporaryAVsourcechangesrestoredfrombeforebackups andAVLiveProbe.swiftremoved.

Next small standalone-sourceprobe: originalMTK preferredFramesPerSecond120 versus60, same4K60monitor,5x18spairs,noprofiler. Onlyframe-ratepreferencechanges; noCADworker/noAV/noFIFOchanges. TemporaryRefreshProbe.swift plusFramePresentation numericlogger andmenutimer; baselinebeforebackupsstill .build/av-live-probe/before.

## MTK refresh preference120 vs60 (unprofiled)

Five18spairs complete. A120totalmedians42.92,34.10,34.77,37.98,41.20ms; B60 34.03,33.89,36.27,39.30,39.04ms. Displaywaitboth~22.4–22.7ms exceptfirstbaselinehigherstate; no consistentdifference. Rejectpreferencechangeasperformancefix. ActualFPSboth~59.8–60.0, no missingactualstamps. Sessionmanuallyended. Archive diagnostics/2026-11-16/refresh-preference.

Nextcandidate .build/layer-vsync-probe/XFrame.app usesnormalMTK/Original/FIFO withonlyCAMetalLayer.displaySyncEnabled toggledtrue/false in5x18spairs. Defaultresetstrueatendandsourceswitch. Moonlightreference vt_metal.mm1319–1324defaultsYES,allowsNOfullscreenuserrequest; thisisnotanupstreamrecommendationtodisablevsync. Mustcheckactualtimestamps/cadenceandtearing; do notadoptwithoutvalidation.

## Layer displaySyncEnabled A/B — promising, measurement validation pending

Five 18-second alternating pairs, Original 1080p to 4K fullscreen, no Instruments.
On total medians: 35.99,49.69,46.58,43.87,41.22 ms. Off:16.61,14.48,17.65,17.64,21.07 ms. Off post-GPU median4.26–4.45 ms versus22.46–39.11 on. Actual callback rates59.78–60.02 fps; >25ms gaps on2/off6, >40ms on2/off2. One invalid timestamp across transitions.

This is NOT yet a proven display-latency win: async layer presentation may change callback semantics or allow tearing. Must correlate IOSurface reads and physical display swap in system trace, then assess cadence/content. Sources under .build/layer-vsync-probe, numeric archive diagnostics/2026-11-16/layer-vsync. Current Source probe remains temporary.

### Layer sync trace check

55-second Metal System Trace on the same app, separate from performance ranking. Sample windows8–18s (sync),27–37s (async),44–54s (sync). Sync produces600/598 swaps per10s; async only7 despite599 application presentation callbacks and continued60Hz VSync events. Async callbacks span the refresh interval instead of matching VSync. WS reads app surfaces rapidly and uses a different output surface set. Thus 4ms callback display-wait cannot be treated as a verified full-screen scanout boundary equivalent to sync. This supports a changed asynchronous presentation mechanism, not proof of artifact-free display. No production adoption. Apple documents possible tearing for displaySyncEnabled=false: https://developer.apple.com/documentation/quartzcore/cametallayer/displaysyncenabled . Numeric archive layer-vsync-trace; raw trace stays local.

## Phase6 five-pair repetition

Same MTK renderer/FIFO, synchronized layer, B manually draws at CADisplayLink target minus6ms. A totalmedians35.29,32.87,35.89,35.65,35.00; B33.19,34.08,32.49,35.29,35.90. B displaywait~20.8ms vsA22.5ms, but total improves only3/5. Output59.79–60.04, >25ms gaps A6/B6, >40ms A2/B1. No invalid actuals. Not adopted: small downstream reduction is offset by arrivalphase. Next test earlier submission before WS latch, target minus16ms; unlike previous10/6/2/0 sweep, tests preceding compositor budget.

## Phase16 five-pair repetition

A medians43.46,35.85,36.63,41.02,31.32; B48.78,39.88,40.21,42.76,44.59 ms. All five worse. B postGPU~31ms, A~22.5ms. No actualmissing,~60fps. Earlier submission did not catch the preceding compositor cycle; reject the premise that a simple earlier render phase removes its retained refresh. Archive phase16.

## Native color-space minimal probe

Five12-second pairs, fullscreen4K,clear-only GPU. A sRGB postGPU medians22.936,39.590,22.928,39.599,39.596; B NSScreen native colorspace22.952,22.926,22.920,22.927,39.601. All540frames per9secondtrim,no>25msgaps. Native did not eliminate higher39.6ms state, and both show23ms floor. No change to product color management; would require color-correct conversion anyway. Archive native-color.

## Native-resolution drawable minimal probe

Five12s pairs A3840x2160/B1920x1080, same fullscreen4K display, clear-only. Alternating postGPU medians(ms): [22.936, 39.732, 22.929, 23.053, 22.91, 39.721, 39.595, 39.726, 22.934, 39.729]. Native-size drawable does not remove23/40ms delay states. No product change. Archive drawable-size.

## Pixel-format minimal probe

Five12s pairs A BGRA8Unorm/B BGR10_XR, same4Kfullscreen,sRGB clear. Alternating postGPU medians22.929,39.608,39.603,39.596,39.602,22.930,22.933,39.605,39.593,22.926ms. Format does not eliminate extra-refresh state. No product adoption. Archive pixel-format.

## AV display-clock scheduling: unprofiled smoothness screen

New hypothesis: AV arrival-driven enqueue jitter caused its extra downstream drops. Kept same FIFO and marker worker; moved video enqueue to main CADisplayLink callback at60Hz. Immediate attachment remains true, no future PTS buffering. Five15s AV blocks alternating normal MTK, Original1080p/fullscreen4K/hiddenHUD. System final total/dropped:890/0,890/0,886/0,886/0,885/0. Earlier arrival-driven variants had~20–30 AV drops each. This is a material improvement in AV internal drop behavior, but not yet an actual-latency or output cadence win. Enqueue can still miss source/display ticks; trace required. Archive av-clock-unprofiled.

### AV display-clock trace and measurement caveat

Five pairs under Instruments: MTK totals31.85,52.43,54.99,57.69,44.13ms; AV associated totals29.28,32.26,35.75,26.96,26.10ms. AV enqueue-to-associated-display median15.81ms, unlike~25ms earlier arrival-driven path. Marker-associated output59.18–59.36 versusMTK59.82. 4–5 enqueued video surfaces pertrimmedAVblock have no observed WS GPU read before reuse; short submit intervals do not explain most. System AV metrics still zero drops, high optimized-compositing counts.

Important correction: no WS GPU read is not proof of a dropped frame if AV uses a different hardware display path. Display-swap/visible-surface tables contain~5338 baseline events but largely omit AV blocks, while display-surface-queue has9815 events. Thus associated FPS is a lower bound with unresolved display-path coverage, not an accepted actual-FPS comparison. No product adoption yet. Apple describes optimized compositing as a special fullscreen power-efficient path. Official Moonlight reference032529d uses AVSampleBufferDisplayLayer with shouldRasterize=true on AppleSilicon SDR to work around color artifacts (vt_avsamplelayer.mm lines350–380). Next experiment keeps CAD-paced AV and adds this rasterization setting; check coverage and latency.

## AV rasterized display-clock screen

Same CAD-paced AV, shouldRasterize=true and rasterizationScale=2, matching the SDR AppleSilicon workaround in pinned official Moonlight. Unprofiled five15s AV blocks: total/dropped/optimized891/0/0,891/0/0,889/0/0,887/0/0,887/0/0. Optimization disabled as intended. A discrete screenshot in firstAVblock verified realgame menu image; no physical latency/tearing claim from screenshot. Next trace validates full-frame output/latency with reduced optimized-path ambiguity. Archive av-raster-unprofiled.

### Rasterized AV trace validation

165s trace, all5AVblocks systemdrops0/optimized0. Paired MTK totalmedians35.84,39.27,35.95,39.82,65.81ms; AV markerassociated24.25,31.63,24.53,32.10,36.20. Enqueue-display~15.8ms. Crucially9801 display swaps available, including AV. Joined video read -> sameWScommand output -> actual display swap, guarded output overwrite:3263 stableAVframes matched. Marker-versus-swap maxabsolute0.00242ms. Lower latency for matched frames is therefore supported by final display events, not an intermediate completion.

Still26 stable-frame no-read cases and10 overwrite/ambiguous chains; markerassociatedAVFPS58.82–59.46 versusMTK59.72–59.82. Pending smoothness acceptance. Sourcearrival and output paths must not be conflated with AV's zero dropped counter. Inspection of official Moonlight also shows CMSampleTimingInfo.duration=kCMTimeInvalid, while our prototype used1/60. Next causal test is AV fixed duration versus invalid duration, sameCADclock/rasterization/immediateflag, not another broad backend rewrite. Archive av-raster-trace, actualswap join-swaps.py.

## Measurement interference found: periodic probe log serialization

The AV prototype saved all accumulated JSON on the main thread every10s, while holding the logger lock. Duration A/B trace shows exactly one progressively longer CAD tick gap perstableblock at offset10.0s:39.9,36.7,52.3,66.6,59.7,76.8,84.8,96.4,101.7ms. This explains declining enqueue counts and contaminates cadence comparisons (including earlier AV traces using the same logger). Lowlatency joins remain measurements, but AV smoothness rejection from these runs is not valid without removing logging stalls. Next build removes all periodic saves; writes only at block transitions outside trimmedmeasurement windows. Repeat duration A/B before choosing configuration.

### Duration A/B without periodic saves

Removed10s save timer; all ten trimmed blocks had zero CAD tick gaps>25ms. Fixed-duration marker-associated FPS59.727,59.726,59.544,59.727,59.635; invalid-duration59.363,59.453,59.453,59.453,59.179. Both enqueue-display~15.8ms. No improvement from invalidduration. Still35 no-read cases,34 outputambiguous/overwritten across stableblocks;6526 finalswap joins confirm markerwithin0.00384ms. AV systemdropszero. Prior tickstall correctly attributed to logger; remaining no-read problem is separate. Some misses at5s spacing show WS already readingpreviousvideo nearcurrentenqueue, thennextvideo onfollowingcycle. Next test fixed-duration CADmain versus CVDisplayLinkworker wake (officialMoonlightclockmechanism), keeping raster/immediate/marker/FIFO same. Archiveav-duration-clean-trace.

## CAD main vs CV worker AV clock

Fixed1/60/immediate/rasterized/FIFO retained, no periodiclogsave. CV callbacktargetlead~23.95–24.04ms vsCAD~16.03ms. CV stableblock no-WS-read counts0,1,0,0,0 vsCAD9,15,9,4,3. AssociatedFPSCV59.635,59.635,59.908,59.817,59.726; CAD59.187,58.547,58.996,59.544,59.545. Thus earlierCVsubmission mostlyeliminatesdownstreamreplacement, supportingracewithWSacquisition. ButCV enqueue-display~23.6ms vsCAD15.8(or32.5inonephasestate), totalmedians32.46,45.38,33.77,37.17,39.04 vsCAD26.28,33.53,35.12,24.18,37.50. Notacceptedlatencywin. NextisCVcallbackimmediateversuswaitinguntiltarget-18ms(~6mslater), preserving~2msmarginrelativeCAD. Archiveav-cv-trace.

### CV phase experiment

Target-18ms mach_wait_until request actually woke at target-16.50ms median (~1.5ms late), unlike immediateCV~target-23.96. Immediate no-read0,0,1,0,0; delayed1,5,5,19,4. Delayed totalmedians24.05,25.93,28.38,28.57,31.41 vsimmediate52.23,38.62,36.70,40.46,32.56. Lowerlatencybut unstablecompositioncoverage: notadopted. Next comparison uses wider target-20.5ms requestedmargin and removesmarkercompletely. Directswapjoin providesAVactualdisplaywithoutmarker; compareagainstnormalMTKfivepairs. Finalcandidate stillunproven.

## AV CV wider margin, no marker, versus MTK

Requestedtarget-20.5ms, actualworkerlead19.62ms, noMetalmarkercommands. FiveMTKtotalmedians38.71,30.61,33.90,35.53,38.77ms; AV29.18,30.71,33.98,32.67,35.48ms. AVenqueue-display~19.25ms vsMTKpostGPU~22.3–22.5ms. Zero AV no-WS-read frames acrossallstableblocks;3289 AVfinalswapjoins,10ambiguous/overwritten. Thusraceeliminatedwithwider margin but notstableoneframegain (3/5better,2tied). Same-finalswapboundaryMTKjoins3289/4ambiguous;callbackdelta<=0.00413ms forjoinedframes. AVmatchedFPS59.27–59.91,MTK59.72–60.00 atsameboundary;ambiguouscasesmeanlowerbound,notprovenallareactualdrops. Tryingallreadsuntileachsurface'snextreuse recoverednone. Source/networkdecodedhardware,zeroerrors/loss/NACK. No productadoption. Archiveav-no-marker-traceincludesbothboundaryandallreadsanalyses.

One remaining upstream architecture difference: Moonlight sets AV layer as a layer-hosted NSView root before wantsLayer, while ourprototypeaddedAVasasublayerofpausedMTKCAMetalLayer. NextcausaltestcomparescurrentAVchildvsroot-hostedAV, sameCVphase/rasterization/sampletiming.

## Layer-hosted AV versus AV child of MTK

SameCVphase20.5/rasterized/immediate/fixed1/60/no-marker. All10blocksdropped0,optimized0. Enqueue-displaymedians~19.25msboth,exceptonechildblock35.84msstate. Childtotal28.01,29.50,32.42,35.62,39.33 vsroot29.80,30.91,33.99,32.85,35.87. No consistent layerarchitecturegain.6561 finalswapjoins,34ambiguous,2no-read. Nextretestarrival-drivenAVwithoutoldperiodicloggingorMetalmarker, comparingCV20.5childvsarrivalchild toavoidconfoundingpriorcontaminatedsmoothnessresults. Archiveav-hosted-trace.

## Arrival-driven AV retest without logging stalls or marker

CV20.5 vsarrivalworker,samechildAVraster/immediate/fixed1/60. Arrival-to-enqueue~0.25ms. YetarrivalfinalswapmatchedFPS57.36,59.36,57.18,59.54,57.18, total27.77,23.07,28.04,23.19,27.68ms. CVtotals27.15,34.58,26.93,34.76,26.76 with~59.6–59.9FPS.89no-readframes acrossrun,concentratedarrivalbadphaseblocks;12ambiguous. AllAVinternaldropcounters0again. Arrivalpathremainsphase-sensitiveandnotaccepted evenafterloggerfix. NextbacktoMetal: testCADtarget-4ms betweenalreadytestedtarget-6 andtarget-2; alternatepairorder toreduceclockdriftbias, unprofiledactualdrawabletimestamps. Frame-arrivalphaseconditionalanalysisneeded; previousfixedABordercanconfoundsmallgainswithsource/displayclockdrift.

## Metal CAD target-4ms, interleaved pair order

Unprofiled180s, modesA,B,B,A,B,A,A,B,A,B; stable14s/block. MostcustompostGPU18.6–18.8ms vsMTK22.47ms, butblock7startedwith33.35ms actual-minus-target (oneextraqueuecycle) andpostGPU~35ms, thenreturnedto16.7ms actual-minus-target atsec10 aftera gap. Totalmediansbyblock33.89,34.30,34.24,37.52,34.16,38.07,38.11,43.76,33.45,31.01ms. All~59.8–60FPS,zeroactual0/drawablemiss. Arrival-phaseconditionalbins7–8ms show14.9–16.1ms benefit;weightedcommon-phaseavg2.20ms includingbadstate. Notacceptedbecausequeue-stateoutlier.

Concretehandoffbug: blocks1,4,7,9 submit at+0.28–0.55msaftermode markerwithNO precedingcustomtick. TheseareoldautomaticMTKcallbacks stilldeliveredafterview.isPaused=true. Block7firstcustomtick14.17msaftermarker followsunscheduledsubmit0.40ms, leavingextraqueueframe. Otherfirstcustomgaps18.27/29.03/16.13ms. Nextprobeaddsdrawownershipguard:whenphaseLinkactive,draw(in:)mustoriginatefromcurrentcustomtick; staleautomaticcallbackcountedandrejectedbeforeconsumingsource. Noquietperiodorinputdiscardadded. Testsameorder/phase.

## Phase 4 single-owner retest
Unprofiled 180s, order A B B A B A A B A B. Suppress stale automatic MTK draw callbacks while CAD owns drawing, before consuming any source frame. All five B blocks now postGPU median18.00–18.71ms vs A22.31–22.57; no extra-cycle B state. B total medians37.25,34.32,28.49,32.56,32.40; A36.17,37.42,33.10,33.45,34.83. FPS B59.79–60.00/A59.79–60.02; each mode one >40ms gap. Common arrival-phase weighted mean reduction3.725ms, bins7–9ms save10.7–12.7ms, other phases essentially tied. This fixes an experimental scheduler handoff race, not established preexisting default bug. No general full-frame gain. Connection was closed after all ten blocks completed (UI WebRTC closed); all reports/events persisted. Evidence diagnostics/2026-11-16/phase4-owner. Next screen phase2 with same ownership.

## Phase 2 single-owner test: rejected
Same180s/order/trim/FIFO. All five B postGPU32.91–33.40ms; totals48.27,43.27,48.39,46.57,45.55ms, worse than MTK39.41,35.64,32.54,34.04,39.80. Near60fps and zero missing actual/drawable misses. A2ms later requested submit crosses compositor latch and costs one refresh despite eliminating stale automatic callbacks. Do not adopt. Next: exact Moonlight current-host PTS / invalid duration / no DisplayImmediately / cached format, root-hosted AV, CV immediate callback, versus baselineMTK with finalswap trace.

## Moonlight sample timing / hosted AV / immediate CV callback
Pinned upstream current host PTS, invalid duration, cached matching format, no DisplayImmediately, root-hosted rasterizedAV, CV worker immediate(no phase delay). Five15s pairs vsMTK, sameFIFO. AVfinalswap3304frames/4ambiguous/zero no-read. AVtotal32.99,36.53,40.06,40.07,32.59ms; MTK48.18(extraqueuecycle),35.05,38.50,38.50,41.80. AVenqueue-display23.62–23.76ms. No consistentlatencywin. Same-boundary6580joins/18ambiguous, baselinecallback-vsactualswap max0.0085ms. AVmatchedFPS59.73–60.00; ambiguouslimitsmustnotbecalledconfirmedloss. Archiveav-moonlight-time; rawtrace .build/av-moonlight-time-probe. NextcausaltestsameCVtarget-18ms (~actual16.5ms), no/yesDisplayImmediately only; cache/duration/hosted fixed. Test if timestampedqueue avoids earlier late-immediate-overwritebehavior.

## AV DisplayImmediately single-variable test: reject both late modes
CVtarget-18ms, samehostedrasterizedAV/invalidduration/currenthostPTS/cachedformat/FIFO. Only attachment flag differs. Five15s pairs. Finalswap6462joins;113no-WS-read,20ambiguous. Both enqueue-display16.16–16.26ms. ImmediateassociatedFPS58.01,58.27,58.27,58.36,58.73; timestamped58.08,59.36,58.82,59.82,59.00. Timestamped internaldrops22,9,15,7,8 vsimmediateall0. Timestampeddoesnoteliminatelateacquisitionrace; zeroimmediatedropswasmisleading. Bothhavevisiblecadenceloss atthisphase, noadoption. Archiveav-immediate-flag. Nextphase4ownedMetal360s/30blocks/15perside, DetailedHUD, unprofiled; testsrealHUDcostandrepeatability.

## Detailed HUD long run interrupted
Planned30x12s/360s, cloud connectionclosedafter19reports; UI WebRTCfailed/closed. Exact causeunknown (idle timeout onlyhypothesis). Full events notsaved becauseprobeonlysavedatfinalblock, so NOTcompletevalidation. Reports1/9displayWaitmedian~35ms;otherB~19, A~22.5. Single-owner guarddoesnotfullypreventextra-cycle statewithHUD. Preserve19reports, noaggregateclaim. Next180s/12blocks, saveonstop, logALLdrawable submissions(includingredraws) andactualpresents; retainstartup events insteadofreset. Goaltest whetheroldpendingframesatclockhandoffcauseextra-cycle orwhetheroverduecallbackburstsappearsteadystate.

## Detailed HUD full submission audit: late callback creates persistent extra cycle
180s/12x15s, sixA/sixB, DetailedHUD, unprofiled, allsubmissions/actualsloggedinclredraws/startup. Oldqueuehandoff hypothesis REFUTED forbadblocks: allBfirstframes have0oldpending, actual-target16.67ms. Per-block diagnosticreport serialization creates80–120ms transitiongaps, outside3s/1strim; itdrainsqueue, notstableFPS evidence. Extra-cycle starts MIDBLOCK: B4at10.9769s submits2.729msAFTERtarget(GPUend3.448mslate), actual-target jumps16.767→33.435 andremainslate122frames. B7at8.9265s submits1.584mslate, 361lateframes. B9at2.1767s submits2.323mslate,543lateframes. B10at2.8436s submits3.112mslate,142lateframes. Healthy subsequentGPUend1.1–1.4msBEFOREtargetstillactual-target33.4. Thusoneoverduecallbackseeds persistentonecyclequeue. AttributionofmainthreadstalltoHUDlayoutnotyetproven. StartupfirstReadycausedNOnovelredrawhere; only1redrawacross13103submissions,35zeroactualmostlystartup/windowtransitions. Fullrunzeroactualsummarymustnotbeconfusedwithtrimmedsamples. Btotals36.88,27.91,31.43,37.85,41.40,37.20 vsA36.81,30.76,33.05,30.64,33.69,36.94; common-phaseavgREGRESSION2.076ms. DoNOTadoptunguardedphase4withHUD. Nextsinglechange: customcallbackrequires>=2msremainingtotargetbeforedequeue/render; skipOVERDUErenderopportunitywithoutconsuminginput. ExistingFIFO/expiry/catchupunchanged. Testsame12blocks/HUD, countskippeddeadlines/cadence/actualqueue. Main-MTKcap2actualpendingisaseparateuntestedfallback, notsameaspreviousworker gate2.

## Phase4 deadline protection: promising small gain, cadence tradeoff
Same180s/12blocks/DetailedHUD; onlychange skipcustomdrawifremainingtargetlead<2ms beforeconsuminginput. All6pairedtotalmediansimproved: A39.32,33.06,33.53,34.98,37.63,38.80; B30.21,28.82,31.94,32.24,35.87,37.30ms. Common-phaseweightedgain3.847ms. Bdisplay18.52–18.80 vsA22.39–22.62. Noextra-cycleframesorinvalidactualtimestampsintrimmedwindows.7misseddeadlinesin66seffectiveBwindows; B>25msgaps11vsA4, >40ms1vsA2. FPSB59.64–59.96/A59.66–60.01. Thisremovespersistentlatencyatcostof~7additionalshortgaps; notfinalsmoothnesswin. 35zeroactualinWHOLElogarestartup/transition, excludedstablewindowsallvalid. NexttestscheduledworkeratSAMEtarget-4mswithsame2msdeadlineguard, sameCAMetalLayer/shaders/FIFO; mainCADcallbackonlypassesfuturetarget, dedicatedworkerwaitsandrenders, avoidingmainthreadpost-CADstall. Thisisdifferentfrompriorunpacedarrivalworker andnotassumedbeneficial.

## Phase4 worker: rejected timing implementation
SameCAMetalLayer/FIFO/shaders, mainCADpassesfuturetarget, worker mach_wait_until(target-4ms), 2msleadguard beforeandafterdrawableacquire. Planned12x15s; cloudclosedafter11fullblocksandpartial11; stoploggingworked. First10blockscontainfivecompletepairs. WorkerFPS17.73,18.82,19.82,21.00,22.09, with465/451/442/427/415deadline missesinstable11swindows. Display18.2msisNOTawin. Missremainingleadmedian0.978ms, drawableacquiremedian0.08–0.09ms; culpritprimarilytimerwake, notdrawableacquisition. Notsameactualsubmitphaseasmain; cannotconcludeworkerarchitectureuniversallyworse. Needtimerprecision/QoScalibrationifrevived. Deferinvasiveworkerrefactor. Nextminimalmain-MTKactualpendingcap2: keepsoriginalcallback/shaders, noCADphasechanges. Testcontrolledsingleextra repaint5msafteranormalcommit(oneperblock) toseedthirdpresentation, comparecapoff/on; explicitlySTRESSmechanismtest, notordinaryplaybacklatencyclaim. Maincap2hasNOTbeentestedbefore (previouscap1maincut30FPS, previouscap2wasworkerwithdifferentphase).

## Main MTK actual-presentation cap2 stress mechanism: passes queue bound
144s/12x12s, sameMTKclock/shaders/FIFO/DetailedHUD. Injectoneinvalidatedmanualdraw~5msafteranormalcommit at~1s/block. ThisisSTRESS, NOTordinaryplaybackgain. Aoff/Bcap2beforedequeue. All6Bmaxpending2, backpressure2/block(alloutsidestabletrim), stablebackpressure0. Amaxpending3all6; Ablocks5/6stay3instablewindows, display39.55/47.20ms,total57.49/61.75 vsBdisplay22.34–22.60. OtherAselfrecoverto22.4, soitdoesnotuniversallysaveaframe. Aextra-submissionneighborsshow35–41mscommit-displayandpending3; Brejectsextraattemptandnextnormalcommitremains23.5ms/pending2. Actualcallbackdelaymedian~0.50–0.59ms, notlargeenoughtothrottlenormal60. StableFPSA59.63–60.10/B59.64–60.12, no30FPSserialization. Bsixmedians39.22,28.82,36.34,33.12,42.03,30.04; comparisonsconfoundedbyarrivalphaseandintentionalstress, donotquoteaggregateasnormalgain. NextremoveinjectionANDperblockreportserialization; keeponlynumericmarkers/toggleinmemory, saveend/stop. GateenabledbydefaultoutsideA/B tovalidateinitialfullscreenstartup; defaultOriginalonlyeventualproductionifaccepted.

## Main gate2 clean normal-stream A/B: no steady throughput regression
144s/12x12s, DetailedHUD, NO injectedrepaint, NO perblockreportserialization orpausedclock; onlyin-memorymarkers/booleanmodechange. All12fullblocks savedbeforelatercloudclosure. All6gatedblockszero backpressure, allstablemaxpending2. Aoneblock brieflymax3. Bothdisplaymedian22.4–22.7ms, ~59.75–60fps; >25msgapsA5/B4, >40msA0/B1. Phase-conditionedmean difference0.272ms, essentiallynormal-state tie, NOToneframeaveragegain. StartupgateONandnativefullscreenentryHUDdisplaymean22.4/p9523.0; laterrequestedexitfullscreenQA didNOTtestplayerbecausecloudhadalreadyclosed, libraryfullscreenrestoredimmediately. NeedfreshproductionshortQA. Source/callbackcounterprobehasprovedcapbehavior; nowrestorebaselinefilesandimplementsmallactual-presentationreservation queue (trackallmodes, enforce2onlyLiveVideoOriginal, releaseonpresent/error/cancelonce). RemovesallprobeUI/logging/clock/workerclasses.
