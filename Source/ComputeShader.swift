import Foundation
import Metal
import simd

let computeShader = ComputeShader()

class ComputeShader {
    let gLength = GTOTAL * MemoryLayout.size(ofValue: TVertex())
    let bLength = iBCOUNT * MemoryLayout.size(ofValue: BallData())
    let cLength = MemoryLayout.size(ofValue:control)
    let vLength = 12 * MemoryLayout.size(ofValue: TVertex())
    var threadsPerGroup = MTLSize()
    var numThreadgroups = MTLSize()
    var commandQueue:MTLCommandQueue! = nil

    //MARK: -
    var pipeline:[MTLComputePipelineState] = []
    var vCountBuffer:MTLBuffer! = nil
    var iCountBuffer:MTLBuffer! = nil

    let PIPELINE_UPDATE_GRID = 0
    let PIPELINE_GRID_FLUX = 1
    let PIPELINE_UPDATE_VERTICES = 2
    let PIPELINE_BALL_MOVE = 3
    let shaderNames = [
        "determineGridPositions",
        "determineGridFlux",
        "determineVertices",
        "calcBallMovement" ]
    
    //MARK: initialize ========================
    func initialize() {
        let defaultLibrary = device?.makeDefaultLibrary()

        func buildPipeline(_ shaderFunction:String) -> MTLComputePipelineState {
            var result:MTLComputePipelineState!
            
            do {
                let prg = defaultLibrary?.makeFunction(name:shaderFunction)
                result = try device?.makeComputePipelineState(function: prg!)
            } catch { fatalError("Failed to setup " + shaderFunction) }
            
            return result
        }
        
        commandQueue = device.makeCommandQueue()
        for i in 0 ..< shaderNames.count { pipeline.append(buildPipeline(shaderNames[i])) }

        vCountBuffer = device?.makeBuffer(length:MemoryLayout<Counter>.stride, options:.storageModeShared)
        iCountBuffer = device?.makeBuffer(length:MemoryLayout<Counter>.stride, options:.storageModeShared)

        //----------------------
        var w = pipeline[PIPELINE_UPDATE_GRID].threadExecutionWidth
        var h = pipeline[PIPELINE_UPDATE_GRID].maxTotalThreadsPerThreadgroup / w
        let tg = Int(GSPAN+1)
        
        ////////////////////////////////////
        let kernelthreadgroupsizelimit = 768     // adjust this for your hardware
        if w * h > kernelthreadgroupsizelimit { w /= 2 }
        if w * h > kernelthreadgroupsizelimit { h /= 2 }
        ////////////////////////////////////

        threadsPerGroup = MTLSize(width:w,height:h,depth:1)
        numThreadgroups = MTLSize(width:tg, height:tg, depth:tg)
    }

    //MARK: update ========================

    func update(_ grid:inout [TVertex], _ base:float3, _ rot:float2) {
        control.base = base
        control.rot = rot
        let cBuffer = device?.makeBuffer(bytes: &control, length: cLength, options: [])

        let gBuffer = device?.makeBuffer(bytes: grid, length: gLength, options: [])
        
        let commandBuffer = commandQueue.makeCommandBuffer()!
        let commandEncoder = commandBuffer.makeComputeCommandEncoder()!
        commandEncoder.setComputePipelineState(pipeline[PIPELINE_UPDATE_GRID])
        commandEncoder.setBuffer(gBuffer, offset: 0, index: 0)
        commandEncoder.setBuffer(cBuffer, offset: 0, index: 1)
        commandEncoder.dispatchThreadgroups(numThreadgroups, threadsPerThreadgroup: threadsPerGroup)
        commandEncoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        let data = NSData(bytesNoCopy: gBuffer!.contents(), length: gLength, freeWhenDone: false)
        data.getBytes(&grid, length:gLength)

        let bBuffer = device?.makeBuffer(bytes: &ballData, length: bLength, options: [])

        if true {
            let commandBuffer = commandQueue.makeCommandBuffer()!
            let commandEncoder = commandBuffer.makeComputeCommandEncoder()!
            commandEncoder.setComputePipelineState(pipeline[PIPELINE_GRID_FLUX])
            commandEncoder.setBuffer(gBuffer, offset: 0, index: 0)
            commandEncoder.setBuffer(bBuffer, offset: 0, index: 1)
            commandEncoder.setBuffer(cBuffer, offset: 0, index: 2)
            commandEncoder.dispatchThreadgroups(numThreadgroups, threadsPerThreadgroup:threadsPerGroup)
            commandEncoder.endEncoding()
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
        }
        
        if true {
            memset(vCountBuffer.contents(),0,MemoryLayout<Counter>.stride)
            memset(iCountBuffer.contents(),0,MemoryLayout<Counter>.stride)

            let commandBuffer = commandQueue.makeCommandBuffer()!
            let commandEncoder = commandBuffer.makeComputeCommandEncoder()!
            commandEncoder.setComputePipelineState(pipeline[PIPELINE_UPDATE_VERTICES])
            commandEncoder.setBuffer(gBuffer,     offset: 0, index: 0)
            commandEncoder.setBuffer(bBuffer,     offset: 0, index: 1)
            commandEncoder.setBuffer(cBuffer,     offset: 0, index: 2)
            commandEncoder.setBuffer(vBuffer,     offset: 0, index: 3)
            commandEncoder.setBuffer(vCountBuffer,offset: 0, index: 4)
            commandEncoder.setBuffer(iBuffer,     offset: 0, index: 5)
            commandEncoder.setBuffer(iCountBuffer,offset: 0, index: 6)
            commandEncoder.dispatchThreadgroups(numThreadgroups, threadsPerThreadgroup:threadsPerGroup)
            commandEncoder.endEncoding()
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            
            var result = Counter()
            memcpy(&result,iCountBuffer.contents(),MemoryLayout<Counter>.stride)
            iCount = Int(result.count)
            
            if iCount >= GTMAX {
                print("overflowed index storage")
                exit(-1)
            }
        }
    }
    
    //MARK: -
    // =====================================================================================
    
    func processBallMovement() {
        if commandQueue == nil { return }
        let commandBuffer = commandQueue.makeCommandBuffer()!
        let commandEncoder = commandBuffer.makeComputeCommandEncoder()!

        let bBuffer = device?.makeBuffer(bytes: &ballData, length: bLength, options: [])
        let cBuffer = device?.makeBuffer(bytes: &control, length: cLength, options: [])
        
        let threadsPerGroup = MTLSize(width:16,height:1,depth:1)
        let numThreadgroups = MTLSize(width:32, height:1, depth:1)
        
        commandEncoder.setComputePipelineState(pipeline[PIPELINE_BALL_MOVE])
        commandEncoder.setBuffer(bBuffer, offset: 0, index: 0)
        commandEncoder.setBuffer(cBuffer, offset: 0, index: 1)
        commandEncoder.dispatchThreadgroups(numThreadgroups, threadsPerThreadgroup: threadsPerGroup)
        commandEncoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        let data = NSData(bytesNoCopy: bBuffer!.contents(), length: bLength, freeWhenDone: false)
        data.getBytes(&ballData, length:bLength)
    }
}



