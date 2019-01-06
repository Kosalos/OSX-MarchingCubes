import AppKit
import Metal
import simd

var cube:Cube!
var ballData:[BallData] = []
var control = Control()

let iBCOUNT = Int(BCOUNT)

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
        
        cube = Cube.init(float3(Float(10),Float(10),Float(-5)))
        
        control.isoValue = 0.02
        control.drawStyle = Int32(0)
    }
    
    //MARK: -
    var QQQ:Float = 0.04 // speed
    
    func update(_ controller: ViewController) {
        control.movement += 0.01 * QQQ      // move flux points
        control.movement2 += 0.02 * QQQ
        computeShader.processBallMovement()

        for i in 0 ..< iBCOUNT {
            ballPoints[i].texColor = float4(1,0,0,1)
            ballPoints[i].pos = ballData[i].pos
        }

        cube.update()
    }
    
    //MARK: -

    func render(_ renderEncoder:MTLRenderCommandEncoder) {
        ballBuffer = device?.makeBuffer(bytes: ballPoints, length: bLength, options: MTLResourceOptions())
        renderEncoder.setVertexBuffer(ballBuffer, offset: 0, index: 0)
        renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount:iBCOUNT)
        
        cube.render(renderEncoder)
    }
}
