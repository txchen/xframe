import AppKit
import MetalKit

final class Records: @unchecked Sendable {
    static let shared = Records()
    let lock = NSLock()
    var rows: [[String: Double]] = []
    func add(_ row: [String: Double]) { lock.withLock { if rows.count < 200000 { rows.append(row) } } }
    func save() {
        let data = lock.withLock { try! JSONSerialization.data(withJSONObject: rows) }
        try! data.write(to: URL(fileURLWithPath: "/Users/hibiki/code/vibe/xframe/.build/drawable-size-probe/events.json"), options: .atomic)
    }
}
@MainActor final class App: NSObject, NSApplicationDelegate, MTKViewDelegate {
    var window: NSWindow!
    var view: MTKView!
    var queue: (any MTLCommandQueue)!
    var phase = 0
    var frame = 0
    var levelTimer:Timer?
    var block=0
    let permits = DispatchSemaphore(value: 3)
    func applicationDidFinishLaunching(_ note: Notification) {
        let menu = NSMenu(); let appItem = menu.addItem(withTitle:"Probe",action:nil,keyEquivalent:"")
        let am = NSMenu(); appItem.submenu=am
        am.addItem(withTitle:"Quit",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
        let modeItem=menu.addItem(withTitle:"Experiment",action:nil,keyEquivalent:"")
        let modes=NSMenu();modeItem.submenu=modes
        for (tag,title) in ["Root Metal view", "Nested Metal view", "Nested with overlay"].enumerated() {
            let i=modes.addItem(withTitle:title,action:#selector(change(_:)),keyEquivalent:"");i.tag=tag;i.target=self
        }
        modes.addItem(withTitle:"Begin drawable size A/B",action:#selector(beginLevels),keyEquivalent:"b").target=self
        modes.addItem(withTitle:"Mark and save sample",action:#selector(mark),keyEquivalent:"s").target=self
        modes.addItem(withTitle:"Toggle Full Screen",action:#selector(NSWindow.toggleFullScreen(_:)),keyEquivalent:"f").keyEquivalentModifierMask=[.control,.command]
        NSApp.mainMenu=menu
        let device=MTLCreateSystemDefaultDevice()!;queue=device.makeCommandQueue()!
        view=MTKView(frame:NSRect(x:0,y:0,width:960,height:540),device:device)
        view.colorPixelFormat = .bgra8Unorm
        view.colorspace=CGColorSpace(name:CGColorSpace.sRGB)
        view.framebufferOnly=true;view.autoResizeDrawable=false;view.preferredFramesPerSecond=120
        view.autoresizingMask=[.width,.height];view.delegate=self
        view.layer!.isOpaque=true
        window=NSWindow(contentRect:view.frame,styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        window.title="Metal Timing Probe — Root";window.backgroundColor = .black
        window.collectionBehavior=[.fullScreenPrimary];window.isReleasedWhenClosed=false
        window.contentView=view;window.center();window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps:true)
    }
    @objc func beginLevels(){
        guard levelTimer==nil else{return}
        block=0;phase=0;Records.shared.add(["marker":CACurrentMediaTime(),"block":0]);view.drawableSize=CGSize(width:3840,height:2160)
        levelTimer=Timer.scheduledTimer(withTimeInterval:12,repeats:true){[weak self] _ in MainActor.assumeIsolated{
            guard let self else{return};self.block+=1;self.phase=self.block%2
            self.view.drawableSize=self.phase==1 ? CGSize(width:1920,height:1080) : CGSize(width:3840,height:2160)
            Records.shared.add(["marker":CACurrentMediaTime(),"block":Double(self.block)]);Records.shared.save()
            if self.block>=10 {self.levelTimer?.invalidate();self.levelTimer=nil;self.view.drawableSize=CGSize(width:3840,height:2160)}
        }}
    }
    @objc func mark() { Records.shared.add(["marker":CACurrentMediaTime(),"phase":Double(phase)]);Records.shared.save() }
    @objc func change(_ item:NSMenuItem) {
        Records.shared.save();phase=item.tag
        view.isPaused=true
        let bounds=window.contentView!.bounds
        view.removeFromSuperview()
        view.frame=bounds
        if phase==0 {window.contentView=view} else {
            let content=NSView(frame:bounds);content.wantsLayer=true;content.layer!.backgroundColor=NSColor.black.cgColor
            content.addSubview(view)
            if phase==2 {
                let label=NSTextField(labelWithString:"Metal Timing Probe — overlay")
                label.frame=NSRect(x:24,y:24,width:500,height:70);label.font=NSFont.systemFont(ofSize:24)
                label.textColor = .white;label.drawsBackground=true;label.backgroundColor=NSColor.black.withAlphaComponent(0.7)
                content.addSubview(label)
            }
            window.contentView=content
        }
        window.title="Metal Timing Probe — Mode \(phase)";view.isPaused=false
        Records.shared.add(["marker":CACurrentMediaTime(),"phase":Double(phase)])
    }
    func mtkView(_ view:MTKView,drawableSizeWillChange size:CGSize) {}
    func draw(in view:MTKView) {
        guard permits.wait(timeout:.now()) == .success else {return}
        guard let pass=view.currentRenderPassDescriptor,let d=view.currentDrawable,let c=queue.makeCommandBuffer() else { permits.signal();return }
        frame+=1;let id=frame;let t=CACurrentMediaTime();let p=phase
        pass.colorAttachments[0].clearColor=MTLClearColor(red:0.10+0.05*sin(t),green:0.19,blue:0.27,alpha:1)
        guard let e=c.makeRenderCommandEncoder(descriptor:pass) else {permits.signal();return};e.endEncoding()
        Records.shared.add(["id":Double(id),"phase":Double(p),"submit":CACurrentMediaTime(),"width":Double(d.texture.width),"height":Double(d.texture.height),"fullscreen":window.styleMask.contains(.fullScreen) ? 1:0])
        let semaphore=permits
        c.addCompletedHandler { b in
            Records.shared.add(["id":Double(id),"gpuStart":b.gpuStartTime,"gpuEnd":b.gpuEndTime,"error":b.status == .completed ? 0:1]);semaphore.signal()
        }
        d.addPresentedHandler { drawable in Records.shared.add(["id":Double(id),"actual":drawable.presentedTime]) }
        c.present(d);c.commit()
    }
    func applicationWillTerminate(_ n:Notification) { Records.shared.save() }
}
MainActor.assumeIsolated {
let app=NSApplication.shared
let delegate=App();app.delegate=delegate
app.setActivationPolicy(.regular);app.run()
}
