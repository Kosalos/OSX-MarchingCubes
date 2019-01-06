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
    // =====================================================================================
    var pipeline:[MTLComputePipelineState] = []
    var vCountBuffer:MTLBuffer! = nil

    let PIPELINE_UPDATECUBES = 0
    let PIPELINE_GRID_POWER  = 1
    let PIPELINE_GRID_POWER2 = 2
    let PIPELINE_GRID_POWER3 = 3
    let PIPELINE_BALL_MOVE   = 4
    let shaderNames = [
        "updateMarchingCubes",
        "calcGridPower",
        "calcGridPower2",
        "calcGridPower3",
        "calcBallMovement" ]

    func updateMarchingCubes(_ grid:inout [TVertex], _ base:float3, _ rot:float2) {
        if pipeline.count == 0 {
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
        }
        
        control.base = base
        control.rot = rot
        let cBuffer = device?.makeBuffer(bytes: &control, length: cLength, options: [])
        let gBuffer = device?.makeBuffer(bytes: grid, length: gLength, options: [])
        
        let w = pipeline[PIPELINE_UPDATECUBES].threadExecutionWidth
        let h = pipeline[PIPELINE_UPDATECUBES].maxTotalThreadsPerThreadgroup / w
        let tg = Int(GSPAN+1)
        threadsPerGroup = MTLSize(width:w,height:h,depth:1)
        numThreadgroups = MTLSize(width:tg, height:tg, depth:tg)
        
        let commandBuffer = commandQueue.makeCommandBuffer()!
        let commandEncoder = commandBuffer.makeComputeCommandEncoder()!
        commandEncoder.setComputePipelineState(pipeline[PIPELINE_UPDATECUBES])
        commandEncoder.setBuffer(gBuffer, offset: 0, index: 0)
        commandEncoder.setBuffer(cBuffer, offset: 0, index: 1)
        commandEncoder.dispatchThreadgroups(numThreadgroups, threadsPerThreadgroup: threadsPerGroup)
        commandEncoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        if true {
            let bBuffer = device?.makeBuffer(bytes: &ballData, length: bLength, options: [])

            let commandBuffer = commandQueue.makeCommandBuffer()!
            let commandEncoder = commandBuffer.makeComputeCommandEncoder()!
            commandEncoder.setComputePipelineState(pipeline[PIPELINE_GRID_POWER])
            commandEncoder.setBuffer(gBuffer, offset: 0, index: 0)
            commandEncoder.setBuffer(bBuffer, offset: 0, index: 1)
            commandEncoder.setBuffer(cBuffer, offset: 0, index: 2)
            commandEncoder.dispatchThreadgroups(numThreadgroups, threadsPerThreadgroup:threadsPerGroup)
            commandEncoder.endEncoding()
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
        }
        
        if true {
            let commandBuffer = commandQueue.makeCommandBuffer()!
            let commandEncoder = commandBuffer.makeComputeCommandEncoder()!
            commandEncoder.setComputePipelineState(pipeline[PIPELINE_GRID_POWER2])
            commandEncoder.setBuffer(gBuffer, offset: 0, index: 0)
            commandEncoder.dispatchThreadgroups(numThreadgroups, threadsPerThreadgroup:threadsPerGroup)
            commandEncoder.endEncoding()
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            
            let data = NSData(bytesNoCopy: gBuffer!.contents(), length: gLength, freeWhenDone: false)
            data.getBytes(&grid, length:gLength)
        }
        
        if true {
            memset(vCountBuffer.contents(),0,MemoryLayout<Counter>.stride)
            
            let commandBuffer = commandQueue.makeCommandBuffer()!
            let commandEncoder = commandBuffer.makeComputeCommandEncoder()!
            commandEncoder.setComputePipelineState(pipeline[PIPELINE_GRID_POWER3])
            commandEncoder.setBuffer(gBuffer,     offset: 0, index: 0)
            commandEncoder.setBuffer(vBuffer,     offset: 0, index: 1)
            commandEncoder.setBuffer(vCountBuffer,offset: 0, index: 2)
            commandEncoder.setBuffer(cBuffer,     offset: 0, index: 3)
            commandEncoder.dispatchThreadgroups(numThreadgroups, threadsPerThreadgroup:threadsPerGroup)
            commandEncoder.endEncoding()
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            
            var result = Counter()
            memcpy(&result,vCountBuffer.contents(),MemoryLayout<Counter>.stride)
            vCount = Int(result.count)
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



