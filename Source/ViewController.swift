import Cocoa
import MetalKit

var device: MTLDevice! = nil
var vc:ViewController! = nil
var camera:float3 = float3(0,0,-50)
var world:World! = nil

class ViewController: NSViewController, NSWindowDelegate {
    @IBOutlet var mtkViewL: MTKView!
    @IBOutlet var mtkViewR: MTKView!
    @IBOutlet var instructions: NSTextField!
    @IBOutlet var stereoButton: NSButton!
    var isStereo:Bool = false
    var paceRotate = CGPoint()

    var rendererL: Renderer!
    var rendererR: Renderer!

    override func viewDidLoad() {
        super.viewDidLoad()
        vc = self
        world = World()
        device = MTLCreateSystemDefaultDevice()
        mtkViewL.device = device
        mtkViewR.device = device
        
        guard let newRenderer = Renderer(metalKitView: mtkViewL, 0) else { fatalError("Renderer cannot be initialized") }
        rendererL = newRenderer
        rendererL.mtkView(mtkViewL, drawableSizeWillChange: mtkViewL.drawableSize)
        mtkViewL.delegate = rendererL
        
        guard let newRenderer2 = Renderer(metalKitView: mtkViewR, 1) else { fatalError("Renderer cannot be initialized") }
        rendererR = newRenderer2
        rendererR.mtkView(mtkViewR, drawableSizeWillChange: mtkViewR.drawableSize)
        mtkViewR.delegate = rendererR
        
        instructions.stringValue =
            "1,2 : Change flux level\n" +
            "Left Mouse Button + Drag : Rotate\n" +
            "Mouse ScrollWheel : Distance\n" +
            "V: Draw Style"
    }
    
    override func viewDidAppear() {
        super.viewWillAppear()
        
        view.window?.delegate = self
        resizeIfNecessary()
        dvrCount = 1 // resize metalviews without delay
        
        layoutViews()
        
        computeShader.initialize()
        
        Timer.scheduledTimer(withTimeInterval:0.05, repeats:true) { timer in self.paceTimerHandler() }
    }

    @IBAction func stereoPressed(_ sender: NSButton) {
        isStereo = !isStereo
        layoutViews()
    }

    //MARK: -
  
    var viewCenter = CGPoint()
    
    func layoutViews() {
        let xs = view.bounds.width
        let ys = view.bounds.height - 80
        
        if isStereo {
            mtkViewR.isHidden = false
            let xs2:CGFloat = xs/2
            mtkViewL.frame = CGRect(x:1, y:1, width:xs2, height:ys)
            mtkViewR.frame = CGRect(x:xs2+2, y:1, width:xs2-3, height:ys)
        }
        else {
            mtkViewR.isHidden = true
            mtkViewL.frame = CGRect(x:1, y:1, width:xs-2, height:ys)
        }
        
        instructions.frame = CGRect(x:10, y:ys+5, width:300, height:70)
        stereoButton.frame = CGRect(x:320, y:ys+5, width:80, height:30)

        viewCenter.x = mtkViewL.frame.width/2
        viewCenter.y = mtkViewL.frame.height/2
        arcBall.initialize(Float(mtkViewL.frame.width),Float(mtkViewL.frame.height))
    }
    
    //MARK: -
    
    func resizeIfNecessary() {
        let minWinSize:CGSize = CGSize(width:600, height:600)
        var r:CGRect = (view.window?.frame)!
        var changed:Bool = false
        
        if r.size.width < minWinSize.width {
            r.size.width = minWinSize.width
            changed = true
        }
        if r.size.height < minWinSize.height {
            r.size.height = minWinSize.height
            changed = true
        }
        
        if changed { view.window?.setFrame(r, display: true) }
        
        layoutViews()
    }
    
    func windowDidResize(_ notification: Notification) {
        resizeIfNecessary()
        resetDelayedViewResizing()
    }
    
    //MARK: -
    
    var isBusy:Bool = false
    
    @objc func paceTimerHandler() {
        if(!isBusy) {
            isBusy = true
            rotate(paceRotate)
            world.update(self)
            isBusy = false
        }
        
        if dvrCount > 0 {
            dvrCount -= 1
            if dvrCount <= 0 {
                layoutViews()
            }
        }
    }
    
    //MARK: -
    
    var dvrCount:Int = 0
    
    // don't alter layout until they have finished resizing the window
    func resetDelayedViewResizing() {
        dvrCount = 10 // 20 = 1 second delay
    }
    
    func rotate(_ pt:CGPoint) {
        arcBall.mouseDown(viewCenter)
        arcBall.mouseMove(CGPoint(x:viewCenter.x + pt.x, y:viewCenter.y + pt.y))
    }
    
    //MARK: -

    var pt = NSPoint()
    
    func flippedYCoord(_ pt:NSPoint) -> NSPoint {
        var npt = pt
        npt.y = view.bounds.size.height - pt.y
        return npt
    }
    
    override func mouseDown(with event: NSEvent) {
        pt = flippedYCoord(event.locationInWindow)
        paceRotate = CGPoint()
    }
    
    override func mouseDragged(with event: NSEvent) {
        var npt = flippedYCoord(event.locationInWindow)
        npt.x -= pt.x
        npt.y -= pt.y
        
        updateRotationSpeedAndDirection(npt)
    }
    
    func fClamp(_ v:Float, _ range:float2) -> Float {
        if v < range.x { return range.x }
        if v > range.y { return range.y }
        return v
    }
    
    override func scrollWheel(with event: NSEvent) {
        camera.z += event.deltaY < 0 ? 5 : -5
        camera.z = fClamp(camera.z, float2(-300,-10))
    }

    //MARK: -
    
    func updateRotationSpeedAndDirection(_ pt:NSPoint) {
        let scale:Float = 0.03
        let rRange = float2(-3,3)
        
        paceRotate.x =  CGFloat(fClamp(Float(pt.x) * scale, rRange))
        paceRotate.y = -CGFloat(fClamp(Float(pt.y) * scale, rRange))
    }
    
    //MARK: -
    let minIsoValue:Float = 0.001
    let maxIsoValue:Float = 2.0

    func changeIsoValue(_ amt:Float) {
        control.isoValue += amt
        if control.isoValue < minIsoValue { control.isoValue = minIsoValue } else if control.isoValue > maxIsoValue { control.isoValue = maxIsoValue }
        //Swift.print("Iso ",control.isoValue)
    }
}
