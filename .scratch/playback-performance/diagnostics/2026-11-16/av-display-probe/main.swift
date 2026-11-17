import AppKit
import AVFoundation
import IOSurface
import os
import MetalKit
final class MarkerLog:@unchecked Sendable {static let shared=MarkerLog();let lock=NSLock();var rows:[[String:Double]]=[];func add(_ r:[String:Double]){lock.withLock{rows.append(r)}};func save(){let d=lock.withLock{try! JSONSerialization.data(withJSONObject:rows)};try! d.write(to:URL(fileURLWithPath:"/Users/hibiki/code/vibe/xframe/.build/av-display-probe/marker.json"),options:.atomic)}}

@MainActor final class App:NSObject,NSApplicationDelegate {
 let marker=CAMetalLayer();var queue:MTLCommandQueue!;var window:NSWindow!;let video=AVSampleBufferDisplayLayer();var timer:Timer?;var pool:CVPixelBufferPool!;var rows:[[String:Double]]=[];var count=0
 let sign=OSSignposter(subsystem:"local.xframe.avprobe",category:"Presentation")
 func applicationDidFinishLaunching(_ n:Notification) {
  let menu=NSMenu();let top=menu.addItem(withTitle:"Probe",action:nil,keyEquivalent:"");let am=NSMenu();top.submenu=am
  am.addItem(withTitle:"Save",action:#selector(save),keyEquivalent:"s").target=self
  am.addItem(withTitle:"Quit",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
  am.addItem(withTitle:"Fullscreen",action:#selector(NSWindow.toggleFullScreen(_:)),keyEquivalent:"f").keyEquivalentModifierMask=[.control,.command];NSApp.mainMenu=menu
  window=NSWindow(contentRect:NSRect(x:0,y:0,width:960,height:540),styleMask:[.titled,.resizable,.closable],backing:.buffered,defer:false)
  window.title="AV Display Timing Probe";window.collectionBehavior=[.fullScreenPrimary];window.backgroundColor = .black
  let view=NSView(frame:window.contentView!.bounds);view.wantsLayer=true;view.layer=video;window.contentView=view
  marker.device=MTLCreateSystemDefaultDevice();queue=marker.device!.makeCommandQueue();marker.frame=CGRect(x:0,y:0,width:2,height:2);marker.drawableSize=CGSize(width:4,height:4);marker.pixelFormat = .bgra8Unorm;video.addSublayer(marker)
  video.videoGravity = .resizeAspect;video.backgroundColor=NSColor.black.cgColor;video.isOpaque=true
  let attrs:[String:Any]=[kCVPixelBufferWidthKey as String:1920,kCVPixelBufferHeightKey as String:1080,kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,kCVPixelBufferIOSurfacePropertiesKey as String:[:]]
  CVPixelBufferPoolCreate(nil,[kCVPixelBufferPoolMinimumBufferCountKey as String:8] as CFDictionary,attrs as CFDictionary,&pool)
  window.center();window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
  timer=Timer.scheduledTimer(withTimeInterval:1.0/60,repeats:true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
 }
 func tick() {
  autoreleasepool {
   var p:CVPixelBuffer?;guard CVPixelBufferPoolCreatePixelBuffer(nil,pool,&p)==0,let p else{return}
   count+=1
   CVPixelBufferLockBaseAddress(p,[])
   memset(CVPixelBufferGetBaseAddressOfPlane(p,0),Int32(60+(count/30)%90),CVPixelBufferGetBytesPerRowOfPlane(p,0)*1080)
   memset(CVPixelBufferGetBaseAddressOfPlane(p,1),128,CVPixelBufferGetBytesPerRowOfPlane(p,1)*540)
   CVPixelBufferUnlockBaseAddress(p,[])
   var fmt:CMVideoFormatDescription?;CMVideoFormatDescriptionCreateForImageBuffer(allocator:kCFAllocatorDefault,imageBuffer:p,formatDescriptionOut:&fmt)
   var timing=CMSampleTimingInfo(duration:CMTime(value:1,timescale:60),presentationTimeStamp:CMTime(seconds:CACurrentMediaTime(),preferredTimescale:1000000),decodeTimeStamp:.invalid)
   var sample:CMSampleBuffer?;CMSampleBufferCreateReadyWithImageBuffer(allocator:kCFAllocatorDefault,imageBuffer:p,formatDescription:fmt!,sampleTiming:&timing,sampleBufferOut:&sample)
   guard let sample else{return}
   let att=CMSampleBufferGetSampleAttachmentsArray(sample,createIfNecessary:true)! as NSArray
   let dict=att[0] as! NSMutableDictionary;dict[kCMSampleAttachmentKey_DisplayImmediately]=true
   let sid=IOSurfaceGetID(CVPixelBufferGetIOSurface(p)!.takeUnretainedValue())
   let t=CACurrentMediaTime();sign.emitEvent("Enqueue", "frame=\(self.count) surface=\(sid)")
   video.sampleBufferRenderer.enqueue(sample)
   if let d=marker.nextDrawable(),let c=queue.makeCommandBuffer() {
    let pass=MTLRenderPassDescriptor();pass.colorAttachments[0].texture=d.texture;pass.colorAttachments[0].loadAction = .clear;pass.colorAttachments[0].storeAction = .store;pass.colorAttachments[0].clearColor=MTLClearColor(red:0,green:0,blue:0,alpha:1)
    c.makeRenderCommandEncoder(descriptor:pass)?.endEncoding()
    let id=count;let surface=IOSurfaceGetID(d.texture.iosurface!)
    MarkerLog.shared.add(["id":Double(id),"surface":Double(surface),"submit":CACurrentMediaTime()])
    d.addPresentedHandler{d in MarkerLog.shared.add(["id":Double(id),"actual":d.presentedTime])}
    c.present(d);c.commit()
   }
   rows.append(["id":Double(count),"surface":Double(sid),"enqueue":t,"mach":Double(mach_absolute_time()),"fullscreen":window.styleMask.contains(.fullScreen) ? 1:0,"failed":video.sampleBufferRenderer.status == .failed ? 1:0])
  }
 }
 @objc func save(){MarkerLog.shared.save();try! JSONSerialization.data(withJSONObject:rows).write(to:URL(fileURLWithPath:"/Users/hibiki/code/vibe/xframe/.build/av-display-probe/events.json"),options:.atomic)}
 func applicationWillTerminate(_ n:Notification){save()}
}
MainActor.assumeIsolated {let app=NSApplication.shared;let d=App();app.delegate=d;app.setActivationPolicy(.regular);app.run()}
