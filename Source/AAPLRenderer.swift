import AppKit
import Metal
import MetalKit
import simd

struct Constants_t {
    var mvp:float4x4
    var light:float3
    var color:float4
    var h1:float4x4 // pad to 256 bytes
    var h2:float3x3
    var h3:float3x3
}

let world = World()

var gDevice: MTLDevice?
var gQueue: MTLCommandQueue?

var _projectionMatrix = float4x4()
var translationAmount = Float(15)

var constants: [MTLBuffer] = []
var constantsSize: Int = MemoryLayout<Constants_t>.stride
var constantsIndex: Int = 0

func alterTranslationAmount(_ amt:Float) {
    translationAmount += amt
    if translationAmount < 2 { translationAmount = 2 } else if translationAmount > 80 { translationAmount = 80 }
}

func changeIsoValue(_ amt:Float) {
    cData.isoValue += amt
    if cData.isoValue < 0.01 { cData.isoValue = 0.01 } else if cData.isoValue > 0.5 { cData.isoValue = 0.5 }
    //   Swift.print("Iso ",isoValue)
}

class Renderer: NSObject, VCDelegate, VDelegate {
    private let kInFlightCommandBuffers = 3
    private var semaphore:DispatchSemaphore!
    private var _pipelineState: MTLRenderPipelineState?
    private var _depthState: MTLDepthStencilState?
    
    var png1:MTLTexture!
    var png2:MTLTexture!
    var samplerState:MTLSamplerState!
    
    override init() {
        super.init()
        semaphore = DispatchSemaphore(value: kInFlightCommandBuffers)
    }
    
    //MARK: - Configure
    
    func configure(_ view: AAPLView) {
        
        // let hk = constantsSize
        
        gDevice = view.device
        guard let gDevice = gDevice else {  fatalError("MTL device not found")  }
        
        view.depthPixelFormat   = .depth32Float
        view.stencilPixelFormat = .invalid
        
        do {
            if #available(OSX 10.12, *) {
                let tLoad = MTKTextureLoader(device:gDevice)
                try png1 = tLoad.newTexture(name:"p10", scaleFactor:1, bundle: Bundle.main, options:nil)
                try png2 = tLoad.newTexture(name:"p19", scaleFactor:1, bundle: Bundle.main, options:nil)
            }
        } catch {
            fatalError("\n\nload txt failed\n\n")
        }
        
        gQueue = gDevice.makeCommandQueue()
        
        preparePipelineState(view)
        
        let depthStateDesc = MTLDepthStencilDescriptor()
        depthStateDesc.depthCompareFunction = .less
        depthStateDesc.isDepthWriteEnabled = true
        _depthState = gDevice.makeDepthStencilState(descriptor: depthStateDesc)
        
        constants = []
        for _ in 0..<kInFlightCommandBuffers {
            constants.append(gDevice.makeBuffer(length: constantsSize, options: [])!)
        }
        
        let sampler = MTLSamplerDescriptor()
        sampler.minFilter             = MTLSamplerMinMagFilter.nearest
        sampler.magFilter             = MTLSamplerMinMagFilter.nearest
        sampler.mipFilter             = MTLSamplerMipFilter.nearest
        sampler.maxAnisotropy         = 1
        sampler.sAddressMode          = MTLSamplerAddressMode.repeat
        sampler.tAddressMode          = MTLSamplerAddressMode.repeat
        sampler.rAddressMode          = MTLSamplerAddressMode.repeat
        sampler.normalizedCoordinates = true
        sampler.lodMinClamp           = 0
        sampler.lodMaxClamp           = .greatestFiniteMagnitude
        samplerState = gDevice.makeSamplerState(descriptor: sampler)
    }
    
    func preparePipelineState(_ view: AAPLView) {
        guard let _defaultLibrary = gDevice!.makeDefaultLibrary() else {  NSLog(">> ERROR: Couldnt create a default shader library"); fatalError() }
        guard let vertexProgram = _defaultLibrary.makeFunction(name: "lighting_vertex") else {  NSLog("V shader load"); fatalError() }
        guard let fragmentProgram = _defaultLibrary.makeFunction(name: "textureFragment") else {  NSLog("F shader load"); fatalError() }
        
        let pipelineStateDescriptor = MTLRenderPipelineDescriptor()
        pipelineStateDescriptor.label  = "MyPipeline"
        pipelineStateDescriptor.sampleCount = 1
        pipelineStateDescriptor.vertexFunction = vertexProgram
        pipelineStateDescriptor.fragmentFunction = fragmentProgram
        pipelineStateDescriptor.depthAttachmentPixelFormat = view.depthPixelFormat
        
        let psd = pipelineStateDescriptor.colorAttachments[0]!
        psd.pixelFormat = .bgra8Unorm

//        // alpha blending enable
//        psd.isBlendingEnabled = true
//        psd.alphaBlendOperation = .add
//        psd.rgbBlendOperation = .add
//        psd.sourceRGBBlendFactor = .sourceAlpha
//        psd.sourceAlphaBlendFactor = .sourceAlpha
//        psd.destinationRGBBlendFactor = .oneMinusSourceAlpha
//        psd.destinationAlphaBlendFactor = .oneMinusSourceAlpha

        do {  _pipelineState = try gDevice?.makeRenderPipelineState(descriptor: pipelineStateDescriptor)
        } catch let error as NSError {  NSLog(">> ERROR: Failed Aquiring pipeline state: \(error)"); fatalError() }
    }
    
    //MARK: - Render
    
    var lightpos = float3()
    var lAngle = Float(0)

    func render(_ view: AAPLView) {
        _ = semaphore.wait(timeout: DispatchTime.now()+1) // zorro   .distantFuture)

        if gQueue == nil { return } // zorro

        let commandBuffer = gQueue?.makeCommandBuffer()
        if commandBuffer == nil { return } // zorro

        let renderPassDescriptor = view.renderPassDescriptor
        if renderPassDescriptor == nil { return }
        
        let renderEncoder = commandBuffer?.makeRenderCommandEncoder(descriptor: renderPassDescriptor!)
        if renderEncoder == nil { return } // zorro
        
        if _pipelineState == nil { return } // zorro
        if _depthState == nil { return } // zorro

        renderEncoder?.setDepthStencilState(_depthState)
        renderEncoder?.setRenderPipelineState(_pipelineState!)
        if let samplerState = samplerState { renderEncoder?.setFragmentSamplerState(samplerState, index: 0) } else { return } // zorro
    
        // -----------------------------
        let constant_buffer = constants[constantsIndex].contents().assumingMemoryBound(to: Constants_t.self)
        constant_buffer[0].mvp =
            _projectionMatrix
            * translate(0,0,translationAmount)
            * arcBall.transformMatrix

        lightpos.x = sinf(lAngle) * 15
        lightpos.y = 15
        lightpos.z = cosf(lAngle) * 15
        lAngle += 0.03
        constant_buffer[0].light = lightpos
    
        if drawStyle == .line {
            constant_buffer[0].color = float4(1,1,0,1)
        }
        else {
            constant_buffer[0].color = float4(0,0,0,0)
        }

        renderEncoder?.setVertexBuffer(constants[constantsIndex], offset:0, index: 1)
        // -----------------------------

        renderEncoder?.setFragmentTexture(png2, index: 0)
    
        ///////////////////////////////////////////////
        world.render(renderEncoder!)
        ///////////////////////////////////////////////

        renderEncoder?.endEncoding()
        commandBuffer?.present(view.currentDrawable!)
    
        let block_sema = semaphore!
        commandBuffer?.addCompletedHandler{ buffer in block_sema.signal() }
    
        commandBuffer?.commit()
        constantsIndex = (constantsIndex + 1) % kInFlightCommandBuffers
    }
    
    func reshape(_ view: AAPLView) {
        let kFOVY: Float = 65.0
        let aspect = Float(abs(view.bounds.size.width / view.bounds.size.height))
        _projectionMatrix = perspective_fov(kFOVY, aspect, 0.1, 100.0)
        
        arcBall.initialize(Float(view.bounds.size.width),Float(view.bounds.size.height))
    }
    
    func viewController(_ viewController: ViewController, willPause pause: Bool) {
    }
    
    //MARK: - Update
    
    func mouseControl(_ dx:Float, _ dy:Float, _ dZoom:Float) {
        alterTranslationAmount(dZoom/10)
        arcBall.mouseDown(CGPoint(x:CGFloat(500), y:CGFloat(500)))
        arcBall.mouseMove(CGPoint(x:CGFloat(500+dx), y:CGFloat(500-dy)))
    }
    
    func keyCharacter(_ ch:String) {
        world.keyCharacter(ch)
    }
    
    func update(_ controller: ViewController) {
        world.update(controller)
    }
}
