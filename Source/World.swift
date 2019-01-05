import AppKit
import Metal
import simd

var cube:Cube!

let iBCOUNT = Int(BCOUNT)

var ballData:[BallData] = []
var cData = ConstantData()

class World {
    var ballPoints:[TVertex] = []
    var ballBuffer: MTLBuffer?
    let bLength = iBCOUNT * MemoryLayout<TVertex>.stride

    init() {
        for _ in 0 ..< iBCOUNT {
            var pt = BallData()
            pt.pos = float3()
            pt.power = 0.5
            
            ballData.append(pt)
            ballPoints.append(TVertex())
        }
        
        cube = Cube.init(float3(Float(1),Float(1),Float(1)))
        
        cData.isoValue = 0.02
        cData.drawStyle = Int32(0)
    }
    
    //MARK: -
    var QQQ:Float = 0.04 // speed
    var rx = Float()
    var ry = Float()

    func update(_ controller: ViewController) {
        cData.movement += 0.01 * QQQ      // move flux points
        cData.movement2 += 0.02 * QQQ
        computeShader.processBallMovement()

        for i in 0 ..< iBCOUNT {
            ballPoints[i].texColor = float4(1,0,0,1)
            ballPoints[i].pos = ballData[i].pos
        }

        cube.update()
        cube.setRotation(rx,ry)
        
        rx += 0.006
        ry += 0.0075
    }
    
    //MARK: -

    func render(_ renderEncoder:MTLRenderCommandEncoder) {
        ballBuffer = gDevice?.makeBuffer(bytes: ballPoints, length: bLength, options: MTLResourceOptions())
        renderEncoder.setVertexBuffer(ballBuffer, offset: 0, index: 0)
        renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount:iBCOUNT)
        
        cube.render(renderEncoder)
    }
    
    func keyCharacter(_ ch:String) {
        switch ch {
        case "1" : changeIsoValue(-0.01)
        case "2" : changeIsoValue(+0.01)
        case "v" : cData.drawStyle = Int32(1 - cData.drawStyle)
        default : break
        }
    }
}
