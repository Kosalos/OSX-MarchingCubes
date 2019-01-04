import QuartzCore
import Metal
import AppKit

@objc(VDelegate)
protocol VDelegate: NSObjectProtocol {
    func reshape(_ view: AAPLView)
    func render(_ view: AAPLView)
    func mouseControl(_ dx:Float, _ dy:Float, _ dZoom:Float)
    func keyCharacter(_ ch:String)
}

@objc(AAPLView)
class AAPLView: NSView {
    weak var delegate: VDelegate?
    
    private(set) var device: MTLDevice!
    private var _currentDrawable: CAMetalDrawable?
    private var _renderPassDescriptor: MTLRenderPassDescriptor?

    var depthPixelFormat: MTLPixelFormat = .invalid
    var stencilPixelFormat: MTLPixelFormat = .invalid
    
    private var _metalLayer: CAMetalLayer!
    private var _layerSizeDidUpdate: Bool = false
    private var _depthTex: MTLTexture?
    private var _stencilTex: MTLTexture?
    private var _msaaTex: MTLTexture?
    
    private func initCommon() {
            self.wantsLayer = true
            _metalLayer = CAMetalLayer()
            self.layer = _metalLayer
        
        device = MTLCreateSystemDefaultDevice()!
        _metalLayer.device          = device
        _metalLayer.pixelFormat     = .bgra8Unorm
        _metalLayer.framebufferOnly = true
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        self.initCommon()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.initCommon()
    }
    
    func releaseTextures() {
        _depthTex   = nil
        _stencilTex = nil
        _msaaTex    = nil
    }
    
    private func setupRenderPassDescriptorForTexture(_ txt: MTLTexture) {
        if _renderPassDescriptor == nil {
            _renderPassDescriptor = MTLRenderPassDescriptor()
        }
        
        let colorAttachment = _renderPassDescriptor!.colorAttachments[0]
        colorAttachment?.texture = txt
        colorAttachment?.loadAction = .clear
        colorAttachment?.clearColor = MTLClearColorMake(0,0,0,1)
        colorAttachment?.storeAction = MTLStoreAction.store
        
        if depthPixelFormat != .invalid {
            let doUpdate =     ( _depthTex?.width       != txt.width  )
                ||  ( _depthTex?.height      != txt.height )
                ||  ( _depthTex?.sampleCount != 1 )
            
            if _depthTex == nil || doUpdate {
                //  If we need a depth txt and don't have one, or if the depth txt we have is the wrong size
                //  Then allocate one of the proper size
                let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: depthPixelFormat,
                    width: txt.width,
                    height: txt.height,
                    mipmapped: false)
                
                desc.textureType = .type2D
                desc.sampleCount = 1
                desc.usage = MTLTextureUsage()
                desc.storageMode = .private
                
                _depthTex = device?.makeTexture(descriptor: desc)
                
                if let depthAttachment = _renderPassDescriptor?.depthAttachment {
                    depthAttachment.texture = _depthTex
                    depthAttachment.loadAction = .clear
                    depthAttachment.storeAction = .dontCare
                    depthAttachment.clearDepth = 1.0
                }
            }
        }
        
        if stencilPixelFormat != .invalid {
            let doUpdate  =    ( _stencilTex?.width       != txt.width  )
                ||  ( _stencilTex?.height      != txt.height )
                ||  ( _stencilTex?.sampleCount != 1 )
            
            if _stencilTex == nil || doUpdate {
                //  If we need a stencil txt and don't have one, or if the depth txt we have is the wrong size
                //  Then allocate one of the proper size
                let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: stencilPixelFormat,
                    width: txt.width,
                    height: txt.height,
                    mipmapped: false)
                
                desc.textureType = .type2D
                desc.sampleCount = 1
                
                _stencilTex = device?.makeTexture(descriptor: desc)
                
                if let stencilAttachment = _renderPassDescriptor?.stencilAttachment {
                    stencilAttachment.texture = _stencilTex
                    stencilAttachment.loadAction = .clear
                    stencilAttachment.storeAction = .dontCare
                    stencilAttachment.clearStencil = 0
                }
            }
        }
    }
    
    var renderPassDescriptor: MTLRenderPassDescriptor? {
        if let drawable = self.currentDrawable {
            self.setupRenderPassDescriptorForTexture(drawable.texture)
        } else {
            NSLog(">> ERROR: Failed to get a drawable!")
            _renderPassDescriptor = nil
        }
        
        return _renderPassDescriptor
    }
    
    var currentDrawable: CAMetalDrawable? {
        if _currentDrawable == nil {
            _currentDrawable = _metalLayer.nextDrawable()
        }
        
        if _currentDrawable == nil { return nil } //zorro
        return _currentDrawable!
    }
    
    override func display() {
        self.displayPrivate()
    }

    private func displayPrivate() {
        autoreleasepool{
            if _layerSizeDidUpdate {
                var drawableSize = self.bounds.size
                
                let screen = self.window?.screen ?? NSScreen.main
                    drawableSize.width *= screen?.backingScaleFactor ?? 1.0
                    drawableSize.height *= screen?.backingScaleFactor ?? 1.0
                
                _metalLayer.drawableSize = drawableSize
                
                delegate?.reshape(self)
               
                _layerSizeDidUpdate = false
            }
            
            self.delegate?.render(self)
            _currentDrawable = nil
        }
    }
    
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        _layerSizeDidUpdate = true
    }
    
    override func setBoundsSize(_ newSize: NSSize) {
        super.setBoundsSize(newSize)
        _layerSizeDidUpdate = true
    }
    
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        _layerSizeDidUpdate = true
        
        delegate?.mouseControl(0,1,0)
    }
    
    //============================================================================
    
    var mpt = NSPoint()
    var rmd = false
    
    override func scrollWheel(with event: NSEvent) {
        
        if rmd {
            changeIsoValue(Float(event.deltaY) / 100)
        }
        else {
            alterTranslationAmount(Float(event.deltaY))
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        rmd = true
    }
    override func rightMouseUp(with event: NSEvent) {
        rmd = false
    }
    
    override func mouseDown(with event: NSEvent) {
        mpt = event.locationInWindow
        //Swift.print("MDown ",mpt.x,mpt.y)
    }
    
    override func mouseDragged(with event: NSEvent)    {
        let pt = event.locationInWindow
        //Swift.print("MDrag ",pt.x,pt.y)
        
        let dx = -Float(pt.x - mpt.x)
        let dy = Float(pt.y - mpt.y)
        mpt = pt
        
        delegate?.mouseControl(dx,dy,0)
    }
    
    override var acceptsFirstResponder : Bool { return true }

    override func keyDown(with event: NSEvent) {
        super.keyDown(with: event)
        
        delegate?.keyCharacter(event.characters!.lowercased())

        //Swift.print("key down: \(event.keyCode)")
        
        let Ramount = Float(10)
        
        switch(event.keyCode) {
        case 53 : // esc
            NSApplication.shared.terminate(self)
        case 123 :  // Lt Arrow
            delegate?.mouseControl(-Ramount,0,0)
        case 124 :  // Rt Arrow
            delegate?.mouseControl(+Ramount,0,0)
        case 126 :  // Up Arrow
            delegate?.mouseControl(0,+Ramount,0)
        case 125 :  // Dn Arrow
            delegate?.mouseControl(0,-Ramount,0)
        case 116 :  // Pg Up
            delegate?.mouseControl(0,0,+Ramount)
        case 121 :  // Pg Dn
            delegate?.mouseControl(0,0,-Ramount)
        default:
            break
        
        }
    }
}
