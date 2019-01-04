import AppKit
import Metal
import simd

var cube:Cube!
var cube2:Cube!
var cube3:Cube!

let iBCOUNT = Int(BCOUNT)

var ballData:[BallData] = []

enum DrawStyle { case line,triangle }
var drawStyle:DrawStyle = .line

var cData = ConstantData()

class World {
    var ballPoints:[TVertex] = []
    var _vertexBuffer: MTLBuffer?
    let bLength = iBCOUNT * MemoryLayout<TVertex>.size

    init() {
        for _ in 0 ..< iBCOUNT {
            var pt = BallData()
            pt.pos = float3()
            pt.power = 0.5
            
            ballData.append(pt)
            ballPoints.append(TVertex())
        }
        
        cube = Cube.init(float3(Float(1),Float(1),Float(1)))
        cube2 = Cube.init(float3(Float(-11),Float(1),Float(-2)))
        cube3 = Cube.init(float3(0,0,0))
        
        cData.isoValue = 0.5
    }
    
    //MARK: -
    var QQQ:Float = 0.025

    func update(_ controller: ViewController) {
        cData.movement += 0.01 * QQQ      // move flux points
        cData.movement2 += 0.02 * QQQ
        computeShader.processBallMovement()

        for i in 0 ..< iBCOUNT {
            ballPoints[i].texColor = float4(1,0,0,1)
            ballPoints[i].pos = ballData[i].pos
        }
    }
    
    //MARK: -
    var rx = Float()
    var ry = Float()

    func render(_ renderEncoder:MTLRenderCommandEncoder) {
        _vertexBuffer = gDevice?.makeBuffer(bytes: ballPoints, length: bLength, options: MTLResourceOptions())
        renderEncoder.setVertexBuffer(_vertexBuffer, offset: 0, index: 0)
        renderEncoder.drawPrimitives(type: .point,   vertexStart: 0, vertexCount:iBCOUNT)
        
        cube.update()
        cube.render(renderEncoder)
        
        cube2.update()
        cube2.render(renderEncoder)

        cube3.update()
        cube3.render(renderEncoder)

        cube2.setPosition(ballData[8].pos / 2)
        cube2.setRotation(ry,rx*2)
        cube3.setPosition(ballData[iBCOUNT - 1].pos)
        cube3.setRotation(rx,ry)
        
        rx += 0.006
        ry += 0.0075
    }
    
    func keyCharacter(_ ch:String) {
        switch ch {
        case "1" : changeIsoValue(-0.01)
        case "2" : changeIsoValue(+0.01)
        case "v" : drawStyle = (drawStyle == .line) ? .triangle : .line
        default : break
        }
    }
}
