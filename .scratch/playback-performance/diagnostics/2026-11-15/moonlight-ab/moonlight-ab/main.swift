import AppKit
import MetalKit

final class Rig: @unchecked Sendable {
    let condition = NSCondition()
    let logs = NSLock()
    var rows: [[String:Double]] = []
    var frames: [(Int,Double)] = []
    var block = -1
    var sequence = 0
    var submission = 0
    var layer: CAMetalLayer!
    var queue: MTLCommandQueue!
    var producer: DispatchSourceTimer!
    let permit = DispatchSemaphore(value:3)
    func log(_ row:[String:Double]) { logs.withLock { rows.append(row) } }
    func save() {
        let data=logs.withLock { try! JSONSerialization.data(withJSONObject:rows) }
        try! data.write(to:URL(fileURLWithPath:"/Users/hibiki/code/vibe/xframe/.build/moonlight-ab/events.json"),options:.atomic)
    }
    func change(_ b:Int) {
        condition.lock();block=b;frames.removeAll();condition.broadcast();condition.unlock()
        log(["marker":CACurrentMediaTime(),"block":Double(b)])
    }
    func start() {
        producer=DispatchSource.makeTimerSource(queue:DispatchQueue(label:"frame-source",qos:.userInteractive))
        producer.schedule(deadline:.now(),repeating:1.0/60.0,leeway:.microseconds(50))
        producer.setEventHandler { [self] in
            let t=CACurrentMediaTime()
            condition.lock();sequence+=1
            let id=sequence, b=block
            if b>=0 {
                if frames.count>=2 {let old=frames.removeFirst(); log(["drop":Double(old.0),"block":Double(b),"time":t])}
                frames.append((id,t));condition.signal()
            }
            condition.unlock()
        }
        producer.resume()
        Thread.detachNewThread { [self] in
            Thread.current.name="Moonlight-like renderer";Thread.current.qualityOfService = .userInteractive
            while true { autoreleasepool {
                condition.lock()
                while block<0 || block%2==0 {condition.wait()}
                let b=block;condition.unlock()
                let acquire=CACurrentMediaTime()
                guard let d=layer.nextDrawable() else {log(["acquireFailure":1]);return}
                let ready=CACurrentMediaTime()
                condition.lock()
                while frames.isEmpty && block==b {condition.wait()}
                guard block==b, !frames.isEmpty else {condition.unlock();return}
                let f=frames.removeFirst();condition.unlock()
                render(d,f,b,acquire,ready)
            }}
        }
    }
    func automatic(_ view:MTKView) {
        guard permit.wait(timeout:.now()) == .success else {log(["busy":1]);return}
        condition.lock()
        guard block>=0,block%2==0,!frames.isEmpty else {condition.unlock();permit.signal();return}
        let b=block,f=frames.removeFirst();condition.unlock()
        let acquire=CACurrentMediaTime()
        guard let d=view.currentDrawable else {permit.signal();log(["acquireFailure":1]);return}
        render(d,f,b,acquire,CACurrentMediaTime(),releasePermit:true)
    }
    func render(_ d:CAMetalDrawable,_ f:(Int,Double),_ b:Int,_ acquire:Double,_ ready:Double,releasePermit:Bool=false) {
        let picked=CACurrentMediaTime()
        let id=logs.withLock { submission+=1;return submission }
        let c=queue.makeCommandBuffer()!
        let pass=MTLRenderPassDescriptor();pass.colorAttachments[0].texture=d.texture
        pass.colorAttachments[0].loadAction = .clear;pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor=MTLClearColor(red:0.12+0.05*sin(Double(f.0)/60),green:0.2,blue:0.3,alpha:1)
        let e=c.makeRenderCommandEncoder(descriptor:pass)!;e.endEncoding()
        log(["id":Double(id),"frame":Double(f.0),"block":Double(b),"arrival":f.1,"picked":picked,"acquire":acquire,"ready":ready,"submit":CACurrentMediaTime(),"width":Double(d.texture.width),"height":Double(d.texture.height)])
        c.addCompletedHandler { [self] cb in
            log(["id":Double(id),"gpuStart":cb.gpuStartTime,"gpuEnd":cb.gpuEndTime,"error":cb.status == .completed ? 0:1])
            if releasePermit {permit.signal()}
        }
        d.addPresentedHandler { [self] drawable in log(["id":Double(id),"actual":drawable.presentedTime]) }
        c.present(d);c.commit()
    }
}
final class App:NSObject,NSApplicationDelegate,MTKViewDelegate {
    var window:NSWindow!;var view:MTKView!;let rig=Rig();var timer:Timer?;var block=0
    func applicationDidFinishLaunching(_ n:Notification) {
        let menu=NSMenu();let item=menu.addItem(withTitle:"Probe",action:nil,keyEquivalent:"");let sub=NSMenu();item.submenu=sub
        sub.addItem(withTitle:"Start 5 pairs",action:#selector(start),keyEquivalent:"s").target=self
        sub.addItem(withTitle:"Full Screen",action:#selector(NSWindow.toggleFullScreen(_:)),keyEquivalent:"f").keyEquivalentModifierMask=[.command,.control]
        sub.addItem(withTitle:"Quit",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q");NSApp.mainMenu=menu
        let device=MTLCreateSystemDefaultDevice()!
        view=MTKView(frame:NSRect(x:0,y:0,width:960,height:540),device:device)
        view.colorPixelFormat = .bgra8Unorm;view.colorspace=CGColorSpace(name:CGColorSpace.sRGB)
        view.framebufferOnly=true;view.preferredFramesPerSecond=120;view.delegate=self;view.isPaused=true
        view.autoresizingMask=[.width,.height];view.layer!.isOpaque=true
        rig.layer=view.layer as? CAMetalLayer;rig.layer.maximumDrawableCount=3;rig.layer.displaySyncEnabled=true;rig.queue=device.makeCommandQueue()!
        window=NSWindow(contentRect:view.frame,styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        window.title="Moonlight scheduling A/B — ready";window.isReleasedWhenClosed=false;window.backgroundColor = .black;window.collectionBehavior=[.fullScreenPrimary];window.contentView=view
        window.center();window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true);rig.start()
    }
    @objc func start() {
        guard timer==nil else{return};block=0;rig.change(0);view.isPaused=false
        rig.log(["fullscreen":window.styleMask.contains(.fullScreen) ? 1:0,"start":CACurrentMediaTime(),"hz":Double(window.screen!.maximumFramesPerSecond)])
        timer=Timer.scheduledTimer(withTimeInterval:15,repeats:true) { [self] t in
            block+=1;view.isPaused=true;view.releaseDrawables();rig.change(block<10 ? block:-1)
            if block>=10 {t.invalidate();timer=nil;rig.save();window.title="Moonlight scheduling A/B — complete"}
            else {view.isPaused=block%2==1}
        }
    }
    func draw(in view:MTKView) {rig.automatic(view)}
    func mtkView(_ view:MTKView,drawableSizeWillChange size:CGSize) {}
    func applicationWillTerminate(_ n:Notification) {rig.save()}
}
let app=NSApplication.shared;let delegate=App();app.delegate=delegate;app.setActivationPolicy(.regular);app.run()
