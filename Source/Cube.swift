import AppKit
import Metal
import simd

let iGSPAN = Int(GSPAN)
let GTOTAL:Int = iGSPAN * iGSPAN * iGSPAN
let GTMAX:Int = GTOTAL*10

var grid = Array(repeating:TVertex(), count:GTOTAL)
var vBuffer: MTLBuffer! = nil
var vCount = Int()

class Cube {
    var base = float3()
    var rot = float2()
    
    init(_ gBase:float3) {
        setPosition(gBase)
    }
    
    func setPosition(_ pos:float3) {
        let offset = Float(GSPAN)/2
        base = pos
        base.x -= offset
        base.y -= offset
        base.z -= offset
    }
    
    func setRotation(_ rx:Float, _ ry:Float) {
        rot.x = rx
        rot.y = ry
    }
    
    //MARK: -

    func update() {
        if vBuffer == nil { vBuffer = device?.makeBuffer(length:MemoryLayout<TVertex>.stride * GTMAX, options:.storageModeShared) }
            
        computeShader.updateMarchingCubes(&grid,base,rot)
    }
    
    //MARK: -

    func drawCage(_ renderEncoder:MTLRenderCommandEncoder) {
        let HOP = 5
        var chop = Float(GSPAN-1) / Float(HOP)
        var v1 = float3()
        var v2 = float3()
        var cageData:[TVertex] = []

        let dx = iGSPAN-1
        let dy = dx * iGSPAN
        let dz = dy * iGSPAN
        
        let p1 = grid[0].pos
        let p2 = grid[dx].pos
        let p3 = grid[dx+dy].pos
        let p4 = grid[dy].pos
        let p5 = grid[0+dz].pos
        let p6 = grid[dx+dz].pos
        let p7 = grid[dx+dy+dz].pos
        let p8 = grid[dy+dz].pos

        let color = float4(0.4,0.5,0.4,1)
        
        var v = TVertex()
        v.texColor = color

        func addLine(_ v1:float3, _ v2:float3) {
            v.pos = v1
            cageData.append(v)
            
            v.pos = v2
            cageData.append(v)
        }

        addLine(p1,p2)
        addLine(p2,p3)
        addLine(p3,p4)
        addLine(p4,p1)
        addLine(p5,p6)
        addLine(p6,p7)
        addLine(p7,p8)
        addLine(p8,p5)
        addLine(p1,p5)
        addLine(p2,p6)
        addLine(p3,p7)
        addLine(p4,p8)
        
        addLine((p1+p2)/2,(p3+p4)/2)
        addLine((p2+p3)/2,(p4+p1)/2)
        
        addLine((p5+p6)/2,(p7+p8)/2)
        addLine((p6+p7)/2,(p8+p5)/2)

        let cageBuffer:MTLBuffer! = device?.makeBuffer(bytes: cageData, length:cageData.count * MemoryLayout<TVertex>.stride, options: MTLResourceOptions())
        renderEncoder.setVertexBuffer(cageBuffer, offset: 0, index: 0)
        renderEncoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount:cageData.count)
    }
    
    //MARK: -

    func render(_ renderEncoder:MTLRenderCommandEncoder) {
        drawCage(renderEncoder)

        if vCount > 0 {
            renderEncoder.setVertexBuffer(vBuffer, offset: 0, index: 0)
        
            switch control.drawStyle {
            case 1  : renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount:vCount)
            default : renderEncoder.drawPrimitives(type: .line,     vertexStart: 0, vertexCount:vCount)
            }
        }
    }
}
