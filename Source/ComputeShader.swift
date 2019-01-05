import Foundation
import Metal
import simd

let computeShader = ComputeShader()

class ComputeShader {
    let gLength = GTOTAL * MemoryLayout.size(ofValue: TVertex())
    let bLength = iBCOUNT * MemoryLayout.size(ofValue: BallData())
    let cLength = MemoryLayout.size(ofValue:cData)
    let vLength = 12 * MemoryLayout.size(ofValue: TVertex())
    var threadsPerGroup = MTLSize()
    var numThreadgroups = MTLSize()

    func buildPipeline(_ shaderFunction:String) -> MTLComputePipelineState {
        var result:MTLComputePipelineState!
        
        do {
            let defaultLibrary = gDevice?.makeDefaultLibrary()
            let prg = defaultLibrary?.makeFunction(name:shaderFunction)
            result = try gDevice?.makeComputePipelineState(function: prg!)
        } catch { fatalError("Failed to setup " + shaderFunction) }
        
        return result
    }

    //MARK: -
    // =====================================================================================
    var csGridPositions:MTLComputePipelineState!
    
    func calcGridPositions(_ grid:inout [TVertex], _ base:float3, _ rot:float2) {
        let commandBuffer = gQueue!.makeCommandBuffer()!
        let encoder = commandBuffer.makeComputeCommandEncoder()!
        
        cData.base = base
        cData.rot = rot
        let cBuffer = gDevice?.makeBuffer(bytes: &cData, length: cLength, options: [])
        let gBuffer = gDevice?.makeBuffer(bytes: grid, length: gLength, options: [])
        
        if csGridPositions == nil { csGridPositions = buildPipeline("calcGridPositions") }
        
        let w = csGridPositions.threadExecutionWidth
        let h = csGridPositions.maxTotalThreadsPerThreadgroup / w
        let tg = Int(GSPAN+1)
        threadsPerGroup = MTLSize(width:w,height:h,depth:1)
        numThreadgroups = MTLSize(width:tg, height:tg, depth:tg)
        
        encoder.setComputePipelineState(csGridPositions!)
        encoder.setBuffer(gBuffer, offset: 0, index: 0)
        encoder.setBuffer(cBuffer, offset: 0, index: 1)
        encoder.dispatchThreadgroups(numThreadgroups, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        let data = NSData(bytesNoCopy: gBuffer!.contents(), length: gLength, freeWhenDone: false)
        data.getBytes(&grid, length:gLength)
    }
    
    //MARK: -
    // =====================================================================================
    var cspipeline:MTLComputePipelineState!

    func processGridPower(_ grid:inout [TVertex]) {
        let commandBuffer = gQueue!.makeCommandBuffer()
        let encoder = commandBuffer?.makeComputeCommandEncoder()

        let gBuffer = gDevice?.makeBuffer(bytes: grid, length: gLength, options: [])
        let bBuffer = gDevice?.makeBuffer(bytes: &ballData, length: bLength, options: [])
        let cBuffer = gDevice?.makeBuffer(bytes: &cData, length: cLength, options: [])
        
        if cspipeline == nil { cspipeline = buildPipeline("calcGridPower") }
        
        encoder?.setComputePipelineState(cspipeline!)
        encoder?.setBuffer(gBuffer, offset: 0, index: 0)
        encoder?.setBuffer(bBuffer, offset: 0, index: 1)
        encoder?.setBuffer(cBuffer, offset: 0, index: 2)
        encoder?.dispatchThreadgroups(numThreadgroups, threadsPerThreadgroup:threadsPerGroup)
        encoder?.endEncoding()
        
        commandBuffer?.commit()
        commandBuffer?.waitUntilCompleted()
        
        let data = NSData(bytesNoCopy: gBuffer!.contents(), length: gLength, freeWhenDone: false)
        data.getBytes(&grid, length:gLength)
    }

    //MARK: -
    // =====================================================================================
    var cspipeline2:MTLComputePipelineState!

    func processGridPower2(_ grid:inout [TVertex]) {
        let commandBuffer = gQueue!.makeCommandBuffer()
        let encoder = commandBuffer?.makeComputeCommandEncoder()
        
        let gBuffer = gDevice?.makeBuffer(bytes: grid, length: gLength, options: [])

        if cspipeline2 == nil { cspipeline2 = buildPipeline("calcGridPower2") }
        
        encoder?.setComputePipelineState(cspipeline2!)
        encoder?.setBuffer(gBuffer, offset: 0, index: 0)
        encoder?.dispatchThreadgroups(numThreadgroups, threadsPerThreadgroup:threadsPerGroup)
        encoder?.endEncoding()
        
        commandBuffer?.commit()
        commandBuffer?.waitUntilCompleted()
        
        let data = NSData(bytesNoCopy: gBuffer!.contents(), length: gLength, freeWhenDone: false)
        data.getBytes(&grid, length:gLength)
    }

    //MARK: -
    // =====================================================================================
    var cspipeline3:MTLComputePipelineState!
    var vCountBuffer:MTLBuffer! = nil

    func processGridPower3(_ grid:[TVertex], _ vBuffer:MTLBuffer) {
        let commandBuffer = gQueue!.makeCommandBuffer()
        let encoder = commandBuffer?.makeComputeCommandEncoder()
        
        let gBuffer = gDevice?.makeBuffer(bytes: grid, length: gLength, options: [])
        let cBuffer = gDevice?.makeBuffer(bytes: &cData, length: cLength, options: [])

        if cspipeline3 == nil {
            cspipeline3 = buildPipeline("calcGridPower3")
            vCountBuffer = gDevice?.makeBuffer(length:MemoryLayout<Counter>.stride, options:.storageModeShared)
        }
        
        memset(vCountBuffer.contents(),0,MemoryLayout<Counter>.stride)

        encoder?.setComputePipelineState(cspipeline3!)
        encoder?.setBuffer(gBuffer,     offset: 0, index: 0)
        encoder?.setBuffer(vBuffer,     offset: 0, index: 1)
        encoder?.setBuffer(vCountBuffer,offset: 0, index: 2)
        encoder?.setBuffer(cBuffer,     offset: 0, index: 3)
        encoder?.dispatchThreadgroups(numThreadgroups, threadsPerThreadgroup:threadsPerGroup)
        encoder?.endEncoding()
        
        commandBuffer?.commit()
        commandBuffer?.waitUntilCompleted()
        
        var result = Counter()
        memcpy(&result,vCountBuffer.contents(),MemoryLayout<Counter>.stride)
        vCount = Int(result.count)
    }

    //MARK: -
    // =====================================================================================
    var pmPipeline:MTLComputePipelineState!
    
    func processBallMovement() {
        let commandBuffer = gQueue!.makeCommandBuffer()!
        let encoder = commandBuffer.makeComputeCommandEncoder()!

        let bBuffer = gDevice?.makeBuffer(bytes: &ballData, length: bLength, options: [])
        let cBuffer = gDevice?.makeBuffer(bytes: &cData, length: cLength, options: [])
        
        if pmPipeline == nil { pmPipeline = buildPipeline("calcBallMovement") }

        encoder.setComputePipelineState(pmPipeline!)

        let threadsPerGroup = MTLSize(width:16,height:1,depth:1)
        let numThreadgroups = MTLSize(width:32, height:1, depth:1)
        
        encoder.setBuffer(bBuffer, offset: 0, index: 0)
        encoder.setBuffer(cBuffer, offset: 0, index: 1)
        encoder.dispatchThreadgroups(numThreadgroups, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        let data = NSData(bytesNoCopy: bBuffer!.contents(), length: bLength, freeWhenDone: false)
        data.getBytes(&ballData, length:bLength)
    }
}



