import AppKit
import MetalKit

final class Records: @unchecked Sendable {
    static let shared = Records()
    let lock = NSLock()
    var rows: [[String: Double]] = []
    func add(_ row: [String: Double]) { lock.withLock { if rows.count < 200000 { rows.append(row) } } }
    func save() {
        let data = lock.withLock { try! JSONSerialization.data(withJSONObject: rows) }
        try! data.write(to: URL(fileURLWithPath: "/Users/hibiki/code/vibe/xframe/.build/minimal-metal/bare-events.json"), options: .atomic)
    }
}
@MainActor final class App: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var view: NSView!
    var metal: CAMetalLayer!
    var timer: Timer?
    var queue: (any MTLCommandQueue)!
    var phase = 0
    var frame = 0
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
        modes.addItem(withTitle:"Mark and save sample",action:#selector(mark),keyEquivalent:"s").target=self
        modes.addItem(withTitle:"Toggle Full Screen",action:#selector(NSWindow.toggleFullScreen(_:)),keyEquivalent:"f").keyEquivalentModifierMask=[.control,.command]
        NSApp.mainMenu=menu
        let device=MTLCreateSystemDefaultDevice()!;queue=device.makeCommandQueue()!
        view=NSView(frame:NSRect(x:0,y:0,width:960,height:540))
        view.wantsLayer=true
        metal=CAMetalLayer();metal.device=device;metal.pixelFormat = .bgra8Unorm
        metal.isOpaque=true;metal.framebufferOnly=true;metal.colorspace=nil
        view.layer=metal;view.autoresizingMask=[.width,.height]
        window=NSWindow(contentRect:view.frame,styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        window.title="Bare Metal Probe — Root";window.backgroundColor = .black
        window.collectionBehavior=[.fullScreenPrimary];window.isReleasedWhenClosed=false
        window.contentView=view;window.center();window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps:true)
        timer=Timer(timeInterval:1.0/60.0, target:self, selector:#selector(tick), userInfo:nil, repeats:true)
        RunLoop.main.add(timer!,forMode:.common)
    }
    @objc func mark() {
        let info: [String: String] = ["windowFrame": NSStringFromRect(window.frame), "viewFrame": NSStringFromRect(view.frame), "viewBounds": NSStringFromRect(view.bounds), "screenFrame": NSStringFromRect(window.screen!.frame), "layerFrame": NSStringFromRect(metal.frame), "drawableSize": NSStringFromSize(metal.drawableSize), "windowOpaque": String(window.isOpaque), "layerOpaque": String(metal.isOpaque), "active": String(NSApp.isActive), "onActiveSpace": String(window.isOnActiveSpace), "visible": String(window.occlusionState.contains(.visible)), "fullscreen": String(window.styleMask.contains(.fullScreen)), "colorspace": String(describing: metal.colorspace), "scale": String(describing: window.backingScaleFactor)]
        let data = try! JSONSerialization.data(withJSONObject: info, options: .prettyPrinted)
        try! data.write(to: URL(fileURLWithPath:"/Users/hibiki/code/vibe/xframe/.build/minimal-metal/geometry.json"))
        Records.shared.add(["marker":CACurrentMediaTime(),"phase":Double(phase)]);Records.shared.save() }
    @objc func change(_ item:NSMenuItem) { mark() }
    @objc func tick() {
        guard permits.wait(timeout:.now()) == .success else {return}
        metal.drawableSize=view.convertToBacking(view.bounds).size
        metal.contentsScale=window.backingScaleFactor
        guard let d=metal.nextDrawable(),let c=queue.makeCommandBuffer() else {permits.signal();return}
        let pass=MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture=d.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
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
