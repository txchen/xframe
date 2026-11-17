import AVFoundation
import MetalKit
import IOSurface

final class AVProbeLog:@unchecked Sendable {
 static let shared=AVProbeLog();private let lock=NSLock();private var rows:[[String:Double]]=[];private var markerID=0
 func nextMarkerID()->Int{lock.withLock{markerID-=1;return markerID}}
 func add(_ r:[String:Double]){lock.withLock {if rows.count<100000{rows.append(r)}}}
 func save(){let data=lock.withLock{try! JSONSerialization.data(withJSONObject:rows)};try! data.write(to:URL(fileURLWithPath:"/Users/hibiki/code/vibe/xframe/.build/av-raster-probe/events.json"),options:.atomic)}
}
@MainActor final class AVLiveProbe: NSObject {
 private var displayLink: CADisplayLink?
 private let source: LiveVideo
 let layer=AVSampleBufferDisplayLayer();let marker=CAMetalLayer();private var worker:AVProbeWorker?;private var timer:Timer?;private var metricsTimer:Timer?;private let epoch=CACurrentMediaTime()
 init(view:MTKView,source:LiveVideo){
  self.source=source
  super.init()
  view.isPaused=true;view.releaseDrawables()
  layer.frame=view.bounds;layer.autoresizingMask=[.layerWidthSizable,.layerHeightSizable];layer.videoGravity = .resizeAspect;layer.backgroundColor=NSColor.black.cgColor;layer.isOpaque=true
  layer.shouldRasterize=true;layer.rasterizationScale=view.window?.backingScaleFactor ?? 2
  marker.device=view.device;marker.pixelFormat = .bgra8Unorm;marker.frame=CGRect(x:0,y:0,width:2,height:2);marker.drawableSize=CGSize(width:4,height:4)
  layer.addSublayer(marker);view.layer!.addSublayer(layer)
  worker=AVProbeWorker(source:source,renderer:layer.sampleBufferRenderer,marker:marker);worker?.start()
  let link=view.displayLink(target:self,selector:#selector(tick(_:)));link.preferredFrameRateRange=CAFrameRateRange(minimum:60,maximum:60,preferred:60);displayLink=link;link.add(to:.main,forMode:.common)
  metricsTimer=Timer.scheduledTimer(withTimeInterval:1,repeats:true){[weak self] _ in MainActor.assumeIsolated{self?.collectMetrics()}}
  timer=Timer.scheduledTimer(withTimeInterval:10,repeats:true){_ in AVProbeLog.shared.save()}
 }
 @objc private func tick(_ link:CADisplayLink){
  let now=CACurrentMediaTime();AVProbeLog.shared.add(["tick":now,"target":link.targetTimestamp])
  if let frame=source.nextFrame(at:now){worker?.enqueue(frame)}
 }
 func collectMetrics(){let epoch=self.epoch;layer.sampleBufferRenderer.loadVideoPerformanceMetrics{m in guard let m else{return};AVProbeLog.shared.add(["metricEpoch":epoch,"metricTime":CACurrentMediaTime(),"total":Double(m.totalNumberOfFrames),"dropped":Double(m.numberOfDroppedFrames),"optimized":Double(m.numberOfFramesDisplayedUsingOptimizedCompositing),"delay":m.totalAccumulatedFrameDelay])}}
 func stop(){displayLink?.invalidate();displayLink=nil;collectMetrics();metricsTimer?.invalidate();metricsTimer=nil;timer?.invalidate();timer=nil;worker?.stop();worker=nil;layer.removeFromSuperlayer();AVProbeLog.shared.save()}
}
final class AVProbeWorker:@unchecked Sendable {
 let source:LiveVideo;let renderer:AVSampleBufferVideoRenderer;let marker:CAMetalLayer;let queue:MTLCommandQueue
 private let condition=NSCondition();private var stopped=false;private var notified=true;private let finished=DispatchSemaphore(value:0);private let markerFinished=DispatchSemaphore(value:0);private var markerID=0;private var anchorRTP:UInt32?;private var anchorHost=0.0;private var anchorFrame:Int?
 init(source:LiveVideo,renderer:AVSampleBufferVideoRenderer,marker:CAMetalLayer){self.source=source;self.renderer=renderer;self.marker=marker;queue=marker.device!.makeCommandQueue()!}
 func wake(){condition.lock();notified=true;condition.signal();condition.unlock()}
 func start(){Thread.detachNewThread{[self] in
  Thread.current.name="XFrame AV probe marker";Thread.current.qualityOfService = .userInteractive
  defer{markerFinished.signal()}
  while !condition.withLock({stopped}) {autoreleasepool{renderMarker()}}
 }}
 func stop(){condition.lock();stopped=true;condition.broadcast();condition.unlock();_=markerFinished.wait(timeout:.now()+2)}
 func enqueue(_ frame:VideoFrame){
  var fmt:CMVideoFormatDescription?;guard CMVideoFormatDescriptionCreateForImageBuffer(allocator:kCFAllocatorDefault,imageBuffer:frame.buffer,formatDescriptionOut:&fmt)==0,let fmt else{return}
  let pts=CACurrentMediaTime()
  var timing=CMSampleTimingInfo(duration:CMTime(value:1,timescale:60),presentationTimeStamp:CMTime(seconds:pts,preferredTimescale:1000000),decodeTimeStamp:.invalid);var sample:CMSampleBuffer?
  guard CMSampleBufferCreateReadyWithImageBuffer(allocator:kCFAllocatorDefault,imageBuffer:frame.buffer,formatDescription:fmt,sampleTiming:&timing,sampleBufferOut:&sample)==0,let sample else{return}
  let a=CMSampleBufferGetSampleAttachmentsArray(sample,createIfNecessary:true)! as NSArray;(a[0] as! NSMutableDictionary)[kCMSampleAttachmentKey_DisplayImmediately]=true
  let sid=IOSurfaceGetID(CVPixelBufferGetIOSurface(frame.buffer)!.takeUnretainedValue());let t=CACurrentMediaTime();renderer.enqueue(sample)
  AVProbeLog.shared.add(["id":Double(frame.id),"videoSurface":Double(sid),"enqueue":t,"pts":pts,"arrival":frame.arrivedAt,"failed":renderer.status == .failed ? 1:0])
 }
 func renderMarker(){
  let id=AVProbeLog.shared.nextMarkerID()
  guard let d=marker.nextDrawable(),let c=queue.makeCommandBuffer() else{return}
  let p=MTLRenderPassDescriptor();p.colorAttachments[0].texture=d.texture;p.colorAttachments[0].loadAction = .clear;p.colorAttachments[0].storeAction = .store;p.colorAttachments[0].clearColor=MTLClearColor(red:0,green:0,blue:0,alpha:1);c.makeRenderCommandEncoder(descriptor:p)?.endEncoding()
  AVProbeLog.shared.add(["id":Double(id),"markerSurface":Double(IOSurfaceGetID(d.texture.iosurface!)),"submit":CACurrentMediaTime()])
  d.addPresentedHandler{drawable in AVProbeLog.shared.add(["id":Double(id),"actual":drawable.presentedTime])};c.present(d);c.commit()
 }
}
