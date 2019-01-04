import AppKit
import Metal
import simd

let iGSPAN = Int(GSPAN)
let GSPAN2:Int = iGSPAN * iGSPAN
let GSPAN3:Int = iGSPAN + GSPAN2
let GTOTAL:Int = iGSPAN * iGSPAN * iGSPAN
let GTMAX:Int = GTOTAL*10

var tCount:Int = 0
var tData: [TVertex] = [] // shared by all cubes

//MARK: -

class Cube {
    var grid:[TVertex] = []
    var verts:[TVertex] = []
    var base = float3()
    var rot = float2()

    var _vertexBuffer: MTLBuffer?
    
    init(_ gBase:float3) {
        if tData.count == 0 { for _ in 0 ..< GTMAX { tData.append(TVertex()) }}
        for _ in 0 ..< 12 { verts.append(TVertex()) }
        for _ in 0 ..< GTOTAL { grid.append(TVertex()) }

        //Swift.print("\nTVertex size = ",MemoryLayout<TVertex>.size,", BallData = ",MemoryLayout<BallData>.size)

        setPosition(gBase)
    }
    
    func calcGridPositions() {        
        let hop = Float(1)
        let centered = -Float(GSPAN)/2
        var index:Int = 0
        
        for z in 0 ..< GSPAN {
            for y in 0 ..< GSPAN {
                for x in 0 ..< GSPAN {
                    var pt = float3(centered + hop * Float(x), centered + hop * Float(y), centered + hop * Float(z))

                    var qt = pt.x
                    pt.x = pt.x * cosf(rot.x) - pt.y * sinf(rot.x)
                    pt.y = qt * sinf(rot.x) + pt.y * cosf(rot.x)
                    
                    qt = pt.y
                    pt.y = pt.y * cosf(rot.y) - pt.x * sinf(rot.y)
                    pt.x = qt * sinf(rot.y) + pt.x * cosf(rot.y)

                    pt += base - float3(centered,centered,centered)
                    
                    grid[index].pos = pt
                    index += 1
                }
            }
        }
    }
    
    func setPosition(_ pos:float3) {
        let offset = Float(GSPAN)/2
        base = pos
        base.x -= offset
        base.y -= offset
        base.z -= offset
        
        calcGridPositions()
    }
    
    func setRotation(_ rx:Float, _ ry:Float) {
        rot.x = rx
        rot.y = ry
        
        calcGridPositions()
    }
    
    //MARK: -

    func closestDistance(_ x:Int, _ y:Int, _ z:Int) -> Float {
        let pt = float3( Float(x),Float(y),Float(z))
        var closest:Float = 30000
        for i in 0 ..< iBCOUNT {
            let v = pt - ballData[i].pos
            let dist = v.x * v.x + v.y * v.y + v.z * v.z
            if dist < closest { closest = dist }
        }
        
        return closest
    }
    
    func update() {
        func addTriangle( _ v1:TVertex, _ v2:TVertex, _ v3:TVertex) {
            func newVertex(_ newV:TVertex) {
                var v = newV
                
                if drawStyle == .line {
                    v.texColor = float4(1,1,1,1)
                }
                else {
                    v.texColor.x = v.pos.x / 10
                    v.texColor.y = v.pos.y / 10
                    v.texColor.z = 0
                }
                
                tData[tCount] = v
                tCount += 1
            }
            
            if drawStyle == .triangle {
                newVertex(v1)
                newVertex(v2)
                newVertex(v3)
            }
            else {
                newVertex(v1); newVertex(v2)
                newVertex(v1); newVertex(v3)
                newVertex(v2); newVertex(v3)
            }
        }

        func interpolate(_ v1:TVertex, _ v2:TVertex) -> TVertex {
            var v = TVertex()
            var diff:Float = v2.flux - v1.flux
            if diff == 0 { return v1 }
            
            diff = (cData.isoValue - v1.flux) / diff
            
            v.pos = v1.pos + (v2.pos - v1.pos) * diff
            v.nrm = v1.nrm + (v2.nrm - v1.nrm) * diff * 3
            v.flux = v1.flux + (v2.flux - v1.flux) * diff
            return v
        }
        
        if grid.count == 0 { return }
        
        computeShader.processGridPower(&grid)
        computeShader.processGridPower2(&grid)

        if verts.count == 0 { for _ in 0 ..< 12 { verts.append(TVertex()) }}
        
        tCount = 0
        
        for z in 0 ..< iGSPAN - 1 {
            for y in 0 ..< iGSPAN - 1 {
                for x in 0 ..< iGSPAN - 1 {
                    
                    let index = x + y * iGSPAN + z * iGSPAN * iGSPAN

                    var lookup:Int = 0
                    if grid[index +     GSPAN3].inside > 0 { lookup += 1 }
                    if grid[index + 1 + GSPAN3].inside > 0 { lookup += 2 }
                    if grid[index + 1 + iGSPAN].inside > 0 { lookup += 4 }
                    if grid[index +     iGSPAN].inside > 0 { lookup += 8 }
                    if grid[index +     GSPAN2].inside > 0 { lookup += 16 }
                    if grid[index + 1 + GSPAN2].inside > 0 { lookup += 32 }
                    if grid[index + 1         ].inside > 0 { lookup += 64 }
                    if grid[index             ].inside > 0 { lookup += 128 }
                    if lookup == 0 || lookup == 255 { continue }
                    
                    let et = edgeTable[lookup]
                    if (et &    1) != 0 { verts[ 0] = interpolate(grid[index + GSPAN3],         grid[index + 1 + GSPAN3]) }
                    if (et &    2) != 0 { verts[ 1] = interpolate(grid[index + 1 + GSPAN3],     grid[index + 1 + iGSPAN]) }
                    if (et &    4) != 0 { verts[ 2] = interpolate(grid[index + 1 + iGSPAN],     grid[index + iGSPAN]) }
                    if (et &    8) != 0 { verts[ 3] = interpolate(grid[index + iGSPAN],         grid[index + GSPAN3]) }
                    if (et &   16) != 0 { verts[ 4] = interpolate(grid[index + GSPAN2],         grid[index + 1 + GSPAN2]) }
                    if (et &   32) != 0 { verts[ 5] = interpolate(grid[index + 1 + GSPAN2],     grid[index + 1]) }
                    if (et &   64) != 0 { verts[ 6] = interpolate(grid[index + 1],              grid[index]) }
                    if (et &  128) != 0 { verts[ 7] = interpolate(grid[index],                  grid[index + GSPAN2]) }
                    if (et &  256) != 0 { verts[ 8] = interpolate(grid[index + GSPAN3],         grid[index + GSPAN2]) }
                    if (et &  512) != 0 { verts[ 9] = interpolate(grid[index + 1 + GSPAN3],     grid[index + 1 + GSPAN2]) }
                    if (et & 1024) != 0 { verts[10] = interpolate(grid[index + 1 + iGSPAN],     grid[index + 1]) }
                    if (et & 2048) != 0 { verts[11] = interpolate(grid[index + iGSPAN],         grid[index]) }
                    
                    var i:Int = 0
                    while true {
                        if triTable[lookup][i] == NA { break }
                        addTriangle(verts[Int(triTable[lookup][i  ])],
                                    verts[Int(triTable[lookup][i+1])],
                                    verts[Int(triTable[lookup][i+2])])
                        i += 3
                        
                        if tCount > GTMAX - 4 { return }
                    }
                }
            }
        }
    }
    
    //MARK: -

    func drawCage(_ renderEncoder:MTLRenderCommandEncoder) {
        let HOP = 5
        var chop = Float(GSPAN-1) / Float(HOP)
        var v1 = float3()
        var v2 = float3()
        
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
        
        tCount = 0
        
        func addLine(_ v1:float3, _ v2:float3) {
            tData[tCount].texColor = color
            tData[tCount].pos = v1
            tCount += 1
            
            tData[tCount].texColor = color
            tData[tCount].pos = v2
            tCount += 1
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

        _vertexBuffer = gDevice?.makeBuffer(bytes: tData, length: tData.count * MemoryLayout<TVertex>.size, options: MTLResourceOptions())
        renderEncoder.setVertexBuffer(_vertexBuffer, offset: 0, index: 0)
        renderEncoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount:tCount)
    }
    
    func render(_ renderEncoder:MTLRenderCommandEncoder) {
        if tData.count == 0 { return }
        
        _vertexBuffer = gDevice?.makeBuffer(bytes: tData, length: tData.count * MemoryLayout<TVertex>.size, options: MTLResourceOptions())
        renderEncoder.setVertexBuffer(_vertexBuffer, offset: 0, index: 0)
        
        switch drawStyle {
        case .line :
            renderEncoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount:tCount)
        case .triangle :
            renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount:tCount)
        }
        
        drawCage(renderEncoder)
    }
}
