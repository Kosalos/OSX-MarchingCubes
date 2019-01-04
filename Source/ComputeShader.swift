import Foundation
import Metal
import simd

let computeShader = ComputeShader()

class ComputeShader {
    let gLength = GTOTAL * MemoryLayout.size(ofValue: TVertex())
    let bLength = iBCOUNT * MemoryLayout.size(ofValue: BallData())
    let cLength = MemoryLayout.size(ofValue:cData)
    let vLength = 12 * MemoryLayout.size(ofValue: TVertex())
    var cspipeline:MTLComputePipelineState!
    
    func buildPipeline(_ shaderFunction:String) -> MTLComputePipelineState {
        var result:MTLComputePipelineState!
        
        do {
            let defaultLibrary = gDevice?.makeDefaultLibrary()
            let prg = defaultLibrary?.makeFunction(name:shaderFunction)
            result = try gDevice?.makeComputePipelineState(function: prg!)
        } catch { fatalError("Failed to setup " + shaderFunction) }
        
        return result
    }

    func processGridPower(_ grid:inout [TVertex]) {
        let commandBuffer = gQueue!.makeCommandBuffer()
        let encoder = commandBuffer?.makeComputeCommandEncoder()

        let gBuffer = gDevice?.makeBuffer(bytes: grid, length: gLength, options: [])
        let bBuffer = gDevice?.makeBuffer(bytes: &ballData, length: bLength, options: [])
        let cBuffer = gDevice?.makeBuffer(bytes: &cData, length: cLength, options: [])
        
        let threadsPerGroup = MTLSize(width:32,height:1,depth:1)
        let numThreadgroups = MTLSize(width:(GTOTAL + 31)/32, height:1, depth:1)
        
        if cspipeline == nil { cspipeline = buildPipeline("calcGridPower") }
        
        encoder?.setComputePipelineState(cspipeline!)
        encoder?.setBuffer(gBuffer, offset: 0, index: 0)
        encoder?.setBuffer(bBuffer, offset: 0, index: 1)
        encoder?.setBuffer(cBuffer, offset: 0, index: 2)
        encoder?.dispatchThreadgroups(numThreadgroups, threadsPerThreadgroup: threadsPerGroup)
        encoder?.endEncoding()
        
        commandBuffer?.commit()
        commandBuffer?.waitUntilCompleted()
        
        let data = NSData(bytesNoCopy: gBuffer!.contents(), length: gLength, freeWhenDone: false)
        data.getBytes(&grid, length:gLength)
    }

    // =====================================================================================
    var cspipeline2:MTLComputePipelineState!

    func processGridPower2(_ grid:inout [TVertex]) {
        let commandBuffer = gQueue!.makeCommandBuffer()
        let encoder = commandBuffer?.makeComputeCommandEncoder()
        
        let gBuffer = gDevice?.makeBuffer(bytes: grid, length: gLength, options: [])
        let bBuffer = gDevice?.makeBuffer(bytes: &ballData, length: bLength, options: [])
        
        let threadsPerGroup = MTLSize(width:32,height:1,depth:1)
        let numThreadgroups = MTLSize(width:(GTOTAL + 31)/32, height:1, depth:1)
        
        if cspipeline2 == nil { cspipeline2 = buildPipeline("calcGridPower2") }
        
        encoder?.setComputePipelineState(cspipeline2!)
        encoder?.setBuffer(gBuffer, offset: 0, index: 0)
        encoder?.setBuffer(bBuffer, offset: 0, index: 1)
        encoder?.dispatchThreadgroups(numThreadgroups, threadsPerThreadgroup: threadsPerGroup)
        encoder?.endEncoding()
        
        commandBuffer?.commit()
        commandBuffer?.waitUntilCompleted()
        
        let data = NSData(bytesNoCopy: gBuffer!.contents(), length: gLength, freeWhenDone: false)
        data.getBytes(&grid, length:gLength)
    }
    
    // =====================================================================================
    
    var pmPipeline:MTLComputePipelineState!
    
    func processBallMovement() {
        let commandBuffer = gQueue!.makeCommandBuffer()
        let encoder = commandBuffer?.makeComputeCommandEncoder()
        
        let bBuffer = gDevice?.makeBuffer(bytes: &ballData, length: bLength, options: [])
        let cBuffer = gDevice?.makeBuffer(bytes: &cData, length: cLength, options: [])
        
        if pmPipeline == nil { pmPipeline = buildPipeline("calcBallMovement") }

        encoder?.setComputePipelineState(pmPipeline!)

        let threadsPerGroup = MTLSize(width:16,height:1,depth:1)
        let numThreadgroups = MTLSize(width:32, height:1, depth:1)
        
        encoder?.setBuffer(bBuffer, offset: 0, index: 0)
        encoder?.setBuffer(cBuffer, offset: 0, index: 1)
        encoder?.dispatchThreadgroups(numThreadgroups, threadsPerThreadgroup: threadsPerGroup)
        encoder?.endEncoding()
        
        commandBuffer?.commit()
        commandBuffer?.waitUntilCompleted()
        
        let data = NSData(bytesNoCopy: bBuffer!.contents(), length: bLength, freeWhenDone: false)
        data.getBytes(&ballData, length:bLength)
    }
}
