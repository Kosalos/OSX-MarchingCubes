#include <metal_stdlib>
#include "Shared.h"

using namespace metal;

struct Constants_t
{
    simd::float4x4 mvp;
    simd::float3 light;
    simd::float4 color;
} __attribute__ ((aligned (256)));

struct ColorInOut {
    float4 position [[position]];
    float pointsize [[point_size]];
    float4 texColor;
    float4 lighting;
};

vertex ColorInOut texturedVertexShader
(
 device TVertex* vertex_array    [[ buffer(0) ]],
 constant Constants_t& constants [[ buffer(1) ]],
 unsigned int vid [[ vertex_id ]]
 )
{
    ColorInOut out;
    
    out.pointsize = 12.0;
    out.texColor = vertex_array[vid].texColor;
    
    float4 in_position = float4(vertex_array[vid].pos, 1.0);
    out.position = constants.mvp * in_position;
    
    float3 nrm = vertex_array[vid].nrm;
    float intensity = 1 + dot(nrm.rgb, normalize(constants.light));
    out.lighting = float4(intensity,intensity,intensity,1);
    
    return out;
}

fragment float4 fragmentShader
(
 ColorInOut data [[stage_in]],
 texture2d<float> tex2D [[texture(0)]],
 sampler sampler2D [[sampler(0)]]
 )
{
    if (data.texColor.w == 0) {
        return tex2D.sample(sampler2D, data.texColor.xy) * data.lighting;
    }
    
    return data.texColor;
}

//MARK: -
//----------------------------------------------------------------
// update ball positions
//----------------------------------------------------------------

kernel void calcBallMovement
(
 device BallData *ballData     [[ buffer(0) ]],
 const device ConstantData *cd [[ buffer(1) ]],
 uint id [[ thread_position_in_grid ]]
 )
{
    if(id >= BCOUNT) return; // size not evenly divisible by threads
    
    float fi = float(id);
    float f1 = float(id+12);
    
    ballData[id].pos.x = cos(cd->movement  * (fi + 1)  ) * 1.9 * f1/2;
    ballData[id].pos.y = sin(cd->movement  * (fi + 1.2)) * 2.1 * f1/2;
    ballData[id].pos.z = cos(cd->movement2 * (fi + 1.5)) * 2.4 * f1/3;
}

//MARK: -
//----------------------------------------------------------------
// init grid[] positions according to base position and rotation
//----------------------------------------------------------------

constant int GSPAN2 = GSPAN * GSPAN;    //   Z axis offset
constant int GSPAN3 = GSPAN + GSPAN2;   // Y+Z axis offset
constant int GTOTAL = GSPAN * GSPAN * GSPAN;

kernel void calcGridPositions
(
 device TVertex *grid           [[ buffer(0) ]],
 const device ConstantData &cd  [[ buffer(1) ]],
 uint3 id [[ thread_position_in_grid ]]
 )
{
    if(id.x >= GSPAN) return; // size not evenly divisible by threads
    if(id.y >= GSPAN) return;
    if(id.z >= GSPAN) return;
    
    float centered = -float(GSPAN)/2;
    float3 pt = float3(centered + float(id.x), centered + float(id.y), centered + float(id.z));
    
    float ss = sin(cd.rot.x);
    float cc = cos(cd.rot.x);
    float qt = pt.x;
    pt.x = pt.x * cc - pt.y * ss;
    pt.y =   qt * ss + pt.y * cc;
    
    ss = sin(cd.rot.y);
    cc = cos(cd.rot.y);
    qt = pt.y;
    pt.y = pt.y * cc - pt.x * ss;
    pt.x =   qt * ss + pt.x * cc;
    
    int index = id.x + id.y * GSPAN + id.z * GSPAN * GSPAN;
    grid[index].pos = pt + cd.base - float3(centered);
}

//MARK: -
//----------------------------------------------------------------
// update grid[] flux and 'inside' fields according to current ball positions & isovalue
//----------------------------------------------------------------

kernel void calcGridPower
(
 device TVertex *grid            [[ buffer(0) ]],
 const device BallData *ballData [[ buffer(1) ]],
 const device ConstantData &cd   [[ buffer(2) ]],
 uint3 id [[ thread_position_in_grid ]]
 )
{
    if(id.x >= GSPAN-1) return; // size not evenly divisible by threads
    if(id.y >= GSPAN-1) return; // also don't want to use last row/columns of grid
    if(id.z >= GSPAN-1) return;
    int index = id.x + id.y * GSPAN + id.z * GSPAN * GSPAN;

    grid[index].flux = 0;
    float3 bpos = grid[index].pos;
    
    for(int i=0;i<BCOUNT;++i) {
        float dd = 1 + length_squared(ballData[i].pos - bpos);
        grid[index].flux += ballData[i].power * ballData[i].power / dd;
    }
    
    grid[index].inside = grid[index].flux > cd.isoValue ? 1 : 0;
}

//MARK: -
//----------------------------------------------------------------
// update grid[] normals
//----------------------------------------------------------------

kernel void calcGridPower2
(
 device TVertex *grid [[ buffer(0) ]],
 uint3 id [[ thread_position_in_grid ]]
 )
{
    if(id.x >= GSPAN-1) return; // size not evenly divisible by threads
    if(id.y >= GSPAN-1) return; // also don't want to use last row/columns of grid
    if(id.z >= GSPAN-1) return;
    int index = id.x + id.y * GSPAN + id.z * GSPAN * GSPAN;

    grid[index].nrm.x = (index == 0 || index == GTOTAL-1) ? 0 : grid[index - 1].flux - grid[index + 1].flux;
    grid[index].nrm.y = (index < GSPAN || index > GTOTAL-GSPAN) ? 0 : grid[index - GSPAN].flux - grid[index + GSPAN].flux;
    grid[index].nrm.z = (index < GSPAN2 || index > GTOTAL-GSPAN2) ? 0 : grid[index - GSPAN2].flux - grid[index + GSPAN2].flux;
    
    grid[index].nrm = normalize(grid[index].nrm);
}

//MARK: -
//----------------------------------------------------------------
// generate vertices according to grid flux values
//----------------------------------------------------------------

extern constant int eTable[];
extern constant uchar tTable[][16];

TVertex interpolate(TVertex v1, TVertex v2, float isoValue) {
    float diff = v2.flux - v1.flux;
    if(diff == 0) return v1;
    
    diff = (isoValue - v1.flux) / diff;
    
    TVertex v;
    v.pos = v1.pos + (v2.pos - v1.pos) * diff;
    v.nrm = v1.nrm + (v2.nrm - v1.nrm) * diff * 3;
    v.flux = v1.flux + (v2.flux - v1.flux) * diff;
    return v;
}

//MARK: -

kernel void calcGridPower3
(
 constant TVertex *grid         [[ buffer(0) ]],
 device TVertex *vertices       [[ buffer(1) ]],
 device atomic_uint &vcounter   [[ buffer(2) ]],
 const device ConstantData &cd  [[ buffer(3) ]],
 uint3 id [[ thread_position_in_grid ]]
 )
{
    if(id.x >= GSPAN-1) return; // size not evenly divisible by threads
    if(id.y >= GSPAN-1) return; // -1 = don't want to use last row/columns of grid
    if(id.z >= GSPAN-1) return;
    int index = id.x + id.y * GSPAN + id.z * GSPAN * GSPAN;
    
    int lookup = 0;
    if(grid[index +     GSPAN3].inside > 0) lookup += 1;
    if(grid[index + 1 + GSPAN3].inside > 0) lookup += 2;
    if(grid[index + 1 + GSPAN] .inside > 0) lookup += 4;
    if(grid[index +     GSPAN] .inside > 0) lookup += 8;
    if(grid[index +     GSPAN2].inside > 0) lookup += 16;
    if(grid[index + 1 + GSPAN2].inside > 0) lookup += 32;
    if(grid[index + 1         ].inside > 0) lookup += 64;
    if(grid[index             ].inside > 0) lookup += 128;
    if(lookup == 0 || lookup == 255) return;
    
    int et = eTable[lookup];
    thread TVertex verts[12];
    
    if((et &    1) != 0) verts[ 0] = interpolate(grid[index + GSPAN3],         grid[index + 1 + GSPAN3],    cd.isoValue);
    if((et &    2) != 0) verts[ 1] = interpolate(grid[index + 1 + GSPAN3],     grid[index + 1 + GSPAN],     cd.isoValue);
    if((et &    4) != 0) verts[ 2] = interpolate(grid[index + 1 + GSPAN],      grid[index + GSPAN],         cd.isoValue);
    if((et &    8) != 0) verts[ 3] = interpolate(grid[index + GSPAN],          grid[index + GSPAN3],        cd.isoValue);
    if((et &   16) != 0) verts[ 4] = interpolate(grid[index + GSPAN2],         grid[index + 1 + GSPAN2],    cd.isoValue);
    if((et &   32) != 0) verts[ 5] = interpolate(grid[index + 1 + GSPAN2],     grid[index + 1],             cd.isoValue);
    if((et &   64) != 0) verts[ 6] = interpolate(grid[index + 1],              grid[index],                 cd.isoValue);
    if((et &  128) != 0) verts[ 7] = interpolate(grid[index],                  grid[index + GSPAN2],        cd.isoValue);
    if((et &  256) != 0) verts[ 8] = interpolate(grid[index + GSPAN3],         grid[index + GSPAN2],        cd.isoValue);
    if((et &  512) != 0) verts[ 9] = interpolate(grid[index + 1 + GSPAN3],     grid[index + 1 + GSPAN2],    cd.isoValue);
    if((et & 1024) != 0) verts[10] = interpolate(grid[index + 1 + GSPAN],      grid[index + 1],             cd.isoValue);
    if((et & 2048) != 0) verts[11] = interpolate(grid[index + GSPAN],          grid[index],                 cd.isoValue);
    
    int i = 0;
    for(;;) {
        if(tTable[lookup][i] > 11) break;
        
        TVertex v1 = verts[int(tTable[lookup][i  ])];
        TVertex v2 = verts[int(tTable[lookup][i+1])];
        TVertex v3 = verts[int(tTable[lookup][i+2])];
        i += 3;

        if(cd.drawStyle == 0) {     // line
            v1.texColor = float4(1);
            v2.texColor = float4(1);
            v3.texColor = float4(1);

            int index = atomic_fetch_add_explicit(&vcounter, 6, memory_order_relaxed);
            vertices[index++] = v1;
            vertices[index++] = v2;
            vertices[index++] = v1;
            vertices[index++] = v3;
            vertices[index++] = v2;
            vertices[index++] = v3;
        }
        else {      // triangle
            float den = 20;
            v1.texColor.x = v1.pos.x / den;
            v1.texColor.y = v1.pos.y / den;
            v2.texColor.x = v2.pos.x / den;
            v2.texColor.y = v2.pos.y / den;
            v3.texColor.x = v3.pos.x / den;
            v3.texColor.y = v3.pos.y / den;

            int index = atomic_fetch_add_explicit(&vcounter, 3, memory_order_relaxed);
            vertices[index++] = v1;
            vertices[index++] = v2;
            vertices[index++] = v3;
        }
    }
}

constant int eTable[] = {
    0x0, 0x109, 0x203, 0x30a, 0x406, 0x50f, 0x605, 0x70c,
    0x80c, 0x905, 0xa0f, 0xb06, 0xc0a, 0xd03, 0xe09, 0xf00,
    0x190, 0x99 , 0x393, 0x29a, 0x596, 0x49f, 0x795, 0x69c,
    0x99c, 0x895, 0xb9f, 0xa96, 0xd9a, 0xc93, 0xf99, 0xe90,
    0x230, 0x339, 0x33 , 0x13a, 0x636, 0x73f, 0x435, 0x53c,
    0xa3c, 0xb35, 0x83f, 0x936, 0xe3a, 0xf33, 0xc39, 0xd30,
    0x3a0, 0x2a9, 0x1a3, 0xaa , 0x7a6, 0x6af, 0x5a5, 0x4ac,
    0xbac, 0xaa5, 0x9af, 0x8a6, 0xfaa, 0xea3, 0xda9, 0xca0,
    0x460, 0x569, 0x663, 0x76a, 0x66 , 0x16f, 0x265, 0x36c,
    0xc6c, 0xd65, 0xe6f, 0xf66, 0x86a, 0x963, 0xa69, 0xb60,
    0x5f0, 0x4f9, 0x7f3, 0x6fa, 0x1f6, 0xff , 0x3f5, 0x2fc,
    0xdfc, 0xcf5, 0xfff, 0xef6, 0x9fa, 0x8f3, 0xbf9, 0xaf0,
    0x650, 0x759, 0x453, 0x55a, 0x256, 0x35f, 0x55 , 0x15c,
    0xe5c, 0xf55, 0xc5f, 0xd56, 0xa5a, 0xb53, 0x859, 0x950,
    0x7c0, 0x6c9, 0x5c3, 0x4ca, 0x3c6, 0x2cf, 0x1c5, 0xcc ,
    0xfcc, 0xec5, 0xdcf, 0xcc6, 0xbca, 0xac3, 0x9c9, 0x8c0,
    0x8c0, 0x9c9, 0xac3, 0xbca, 0xcc6, 0xdcf, 0xec5, 0xfcc,
    0xcc , 0x1c5, 0x2cf, 0x3c6, 0x4ca, 0x5c3, 0x6c9, 0x7c0,
    0x950, 0x859, 0xb53, 0xa5a, 0xd56, 0xc5f, 0xf55, 0xe5c,
    0x15c, 0x55 , 0x35f, 0x256, 0x55a, 0x453, 0x759, 0x650,
    0xaf0, 0xbf9, 0x8f3, 0x9fa, 0xef6, 0xfff, 0xcf5, 0xdfc,
    0x2fc, 0x3f5, 0xff , 0x1f6, 0x6fa, 0x7f3, 0x4f9, 0x5f0,
    0xb60, 0xa69, 0x963, 0x86a, 0xf66, 0xe6f, 0xd65, 0xc6c,
    0x36c, 0x265, 0x16f, 0x66 , 0x76a, 0x663, 0x569, 0x460,
    0xca0, 0xda9, 0xea3, 0xfaa, 0x8a6, 0x9af, 0xaa5, 0xbac,
    0x4ac, 0x5a5, 0x6af, 0x7a6, 0xaa , 0x1a3, 0x2a9, 0x3a0,
    0xd30, 0xc39, 0xf33, 0xe3a, 0x936, 0x83f, 0xb35, 0xa3c,
    0x53c, 0x435, 0x73f, 0x636, 0x13a, 0x33 , 0x339, 0x230,
    0xe90, 0xf99, 0xc93, 0xd9a, 0xa96, 0xb9f, 0x895, 0x99c,
    0x69c, 0x795, 0x49f, 0x596, 0x29a, 0x393, 0x99 , 0x190,
    0xf00, 0xe09, 0xd03, 0xc0a, 0xb06, 0xa0f, 0x905, 0x80c,
    0x70c, 0x605, 0x50f, 0x406, 0x30a, 0x203, 0x109, 0x0   };

#define NA uchar(16)

constant uchar tTable[][16] = {
    { NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA },
    {  0,  8,  3, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA },
    {  0,  1,  9, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA },
    {  1,  8,  3,  9,  8,  1, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA },
    {  1,  2, 10, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA },
    {  0,  8,  3,  1,  2, 10, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA },
    {  9,  2, 10,  0,  2,  9, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA },
    {  2,  8,  3,  2, 10,  8, 10,  9,  8, NA, NA, NA, NA, NA, NA, NA },
    {  3, 11,  2, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA },
    {  0, 11,  2,  8, 11,  0, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA },
    {  1,  9,  0,  2,  3, 11, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA },
    {  1, 11,  2,  1,  9, 11,  9,  8, 11, NA, NA, NA, NA, NA, NA, NA },
    {  3, 10,  1, 11, 10,  3, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA },
    {  0, 10,  1,  0,  8, 10,  8, 11, 10, NA, NA, NA, NA, NA, NA, NA },
    {  3,  9,  0,  3, 11,  9, 11, 10,  9, NA, NA, NA, NA, NA, NA, NA },
    {  9,  8, 10, 10,  8, 11, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA },
    {  4,  7,  8, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA },
    {  4,  3,  0,  7,  3,  4, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA },
    {  0,  1,  9,  8,  4,  7, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA },
    {  4,  1,  9,  4,  7,  1,  7,  3,  1, NA, NA, NA, NA, NA, NA, NA },
    {  1,  2, 10,  8,  4,  7, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA },
    {  3,  4,  7,  3,  0,  4,  1,  2, 10, NA, NA, NA, NA, NA, NA, NA },
    {  9,  2, 10,  9,  0,  2,  8,  4,  7, NA, NA, NA, NA, NA, NA, NA },
    {  2, 10,  9,  2,  9,  7,  2,  7,  3,  7,  9,  4, NA, NA, NA, NA },
    {  8,  4,  7,  3, 11,  2, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA },
    { 11,  4,  7, 11,  2,  4,  2,  0,  4, NA, NA, NA, NA, NA, NA, NA },
    {  9,  0,  1,  8,  4,  7,  2,  3, 11, NA, NA, NA, NA, NA, NA, NA },
    {  4,  7, 11,  9,  4, 11,  9, 11,  2,  9,  2,  1, NA, NA, NA, NA },
    {  3, 10,  1,  3, 11, 10,  7,  8,  4, NA, NA, NA, NA, NA, NA, NA },
    {  1, 11, 10,  1,  4, 11,  1,  0,  4,  7, 11,  4, NA, NA, NA, NA },
    {  4,  7,  8,  9,  0, 11,  9, 11, 10, 11,  0,  3, NA, NA, NA, NA },
    {  4,  7, 11,  4, 11,  9,  9, 11, 10, NA, NA, NA, NA, NA, NA, NA },
    {  9,  5,  4, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA },
    {  9,  5,  4,  0,  8,  3, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA },
    {  0,  5,  4,  1,  5,  0, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA },
    {  8,  5,  4,  8,  3,  5,  3,  1,  5, NA, NA, NA, NA, NA, NA, NA },
    {  1,  2, 10,  9,  5,  4, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA },
    {  3,  0,  8,  1,  2, 10,  4,  9,  5, NA, NA, NA, NA, NA, NA, NA },
    {  5,  2, 10,  5,  4,  2,  4,  0,  2, NA, NA, NA, NA, NA, NA, NA },
    {  2, 10,  5,  3,  2,  5,  3,  5,  4,  3,  4,  8, NA, NA, NA, NA },
    {  9,  5,  4,  2,  3, 11, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA },
    {  0, 11,  2,  0,  8, 11,  4,  9,  5, NA, NA, NA, NA, NA, NA, NA },
    {  0,  5,  4,  0,  1,  5,  2,  3, 11, NA, NA, NA, NA, NA, NA, NA },
    {  2,  1,  5,  2,  5,  8,  2,  8, 11,  4,  8,  5, NA, NA, NA, NA },
    { 10,  3, 11, 10,  1,  3,  9,  5,  4, NA, NA, NA, NA, NA, NA, NA },
    {  4,  9,  5,  0,  8,  1,  8, 10,  1,  8, 11, 10, NA, NA, NA, NA },
    {  5,  4,  0,  5,  0, 11,  5, 11, 10, 11,  0,  3, NA, NA, NA, NA },
    {  5,  4,  8,  5,  8, 10, 10,  8, 11, NA, NA, NA, NA, NA, NA, NA },
    {  9,  7,  8,  5,  7,  9, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA },
    {  9,  3,  0,  9,  5,  3,  5,  7,  3, NA, NA, NA, NA, NA, NA, NA },
    {  0,  7,  8,  0,  1,  7,  1,  5,  7, NA, NA, NA, NA, NA, NA, NA },
    {  1,  5,  3,  3,  5,  7, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA },
    {  9,  7,  8,  9,  5,  7, 10,  1,  2, NA, NA, NA, NA, NA, NA, NA },
    { 10,  1,  2,  9,  5,  0,  5,  3,  0,  5,  7,  3, NA, NA, NA, NA },
    {  8,  0,  2,  8,  2,  5,  8,  5,  7, 10,  5,  2, NA, NA, NA, NA },
    {  2, 10,  5,  2,  5,  3,  3,  5,  7, NA, NA, NA, NA, NA, NA, NA },
    {  7,  9,  5,  7,  8,  9,  3, 11,  2, NA, NA, NA, NA, NA, NA, NA },
    {  9,  5,  7,  9,  7,  2,  9,  2,  0,  2,  7, 11, NA, NA, NA, NA },
    {  2,  3, 11,  0,  1,  8,  1,  7,  8,  1,  5,  7, NA, NA, NA, NA },
    { 11,  2,  1, 11,  1,  7,  7,  1,  5, NA, NA, NA, NA, NA, NA, NA },
    {  9,  5,  8,  8,  5,  7, 10,  1,  3, 10,  3, 11, NA, NA, NA, NA },
    {  5,  7,  0,  5,  0,  9,  7, 11,  0,  1,  0, 10, 11, 10,  0, NA },
    { 11, 10,  0, 11,  0,  3, 10,  5,  0,  8,  0,  7,  5,  7,  0, NA },
    { 11, 10,  5,  7, 11,  5, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA },
    { 10,  6,  5, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA },
    {  0,  8,  3,  5, 10,  6, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA },
    {  9,  0,  1,  5, 10,  6, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA },
    {  1,  8,  3,  1,  9,  8,  5, 10,  6, NA, NA, NA, NA, NA, NA, NA },
    {  1,  6,  5,  2,  6,  1, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA },
    {  1,  6,  5,  1,  2,  6,  3,  0,  8, NA, NA, NA, NA, NA, NA, NA },
    {  9,  6,  5,  9,  0,  6,  0,  2,  6, NA, NA, NA, NA, NA, NA, NA },
    {  5,  9,  8,  5,  8,  2,  5,  2,  6,  3,  2,  8, NA, NA, NA, NA },
    {  2,  3, 11, 10,  6,  5, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA },
    { 11,  0,  8, 11,  2,  0, 10,  6,  5, NA, NA, NA, NA, NA, NA, NA },
    {  0,  1,  9,  2,  3, 11,  5, 10,  6, NA, NA, NA, NA, NA, NA, NA },
    {  5, 10,  6,  1,  9,  2,  9, 11,  2,  9,  8, 11, NA, NA, NA, NA },
    {  6,  3, 11,  6,  5,  3,  5,  1,  3, NA, NA, NA, NA, NA, NA, NA },
    {  0,  8, 11,  0, 11,  5,  0,  5,  1,  5, 11,  6, NA, NA, NA, NA },
    {  3, 11,  6,  0,  3,  6,  0,  6,  5,  0,  5,  9, NA, NA, NA, NA },
    {  6,  5,  9,  6,  9, 11, 11,  9,  8, NA, NA, NA, NA, NA, NA, NA },
    {  5, 10,  6,  4,  7,  8, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA },
    {  4,  3,  0,  4,  7,  3,  6,  5, 10, NA, NA, NA, NA, NA, NA, NA },
    {  1,  9,  0,  5, 10,  6,  8,  4,  7, NA, NA, NA, NA, NA, NA, NA },
    { 10,  6,  5,  1,  9,  7,  1,  7,  3,  7,  9,  4, NA, NA, NA, NA },
    {  6,  1,  2,  6,  5,  1,  4,  7,  8, NA, NA, NA, NA, NA, NA, NA },
    {  1,  2,  5,  5,  2,  6,  3,  0,  4,  3,  4,  7, NA, NA, NA, NA },
    {  8,  4,  7,  9,  0,  5,  0,  6,  5,  0,  2,  6, NA, NA, NA, NA },
    {  7,  3,  9,  7,  9,  4,  3,  2,  9,  5,  9,  6,  2,  6,  9, NA },
    {  3, 11,  2,  7,  8,  4, 10,  6,  5, NA, NA, NA, NA, NA, NA, NA },
    {  5, 10,  6,  4,  7,  2,  4,  2,  0,  2,  7, 11, NA, NA, NA, NA },
    {  0,  1,  9,  4,  7,  8,  2,  3, 11,  5, 10,  6, NA, NA, NA, NA },
    {  9,  2,  1,  9, 11,  2,  9,  4, 11,  7, 11,  4,  5, 10,  6, NA },
    {  8,  4,  7,  3, 11,  5,  3,  5,  1,  5, 11,  6, NA, NA, NA, NA },
    {  5,  1, 11,  5, 11,  6,  1,  0, 11,  7, 11,  4,  0,  4, 11, NA },
    {  0,  5,  9,  0,  6,  5,  0,  3,  6, 11,  6,  3,  8,  4,  7, NA },
    {  6,  5,  9,  6,  9, 11,  4,  7,  9,  7, 11,  9, NA, NA, NA, NA },
    { 10,  4,  9,  6,  4, 10, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA },
    {  4, 10,  6,  4,  9, 10,  0,  8,  3, NA, NA, NA, NA, NA, NA, NA },
    { 10,  0,  1, 10,  6,  0,  6,  4,  0, NA, NA, NA, NA, NA, NA, NA },
    {  8,  3,  1,  8,  1,  6,  8,  6,  4,  6,  1, 10, NA, NA, NA, NA },
    {  1,  4,  9,  1,  2,  4,  2,  6,  4, NA, NA, NA, NA, NA, NA, NA },
    {  3,  0,  8,  1,  2,  9,  2,  4,  9,  2,  6,  4, NA, NA, NA, NA },
    {  0,  2,  4,  4,  2,  6, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA },
    {  8,  3,  2,  8,  2,  4,  4,  2,  6, NA, NA, NA, NA, NA, NA, NA },
    { 10,  4,  9, 10,  6,  4, 11,  2,  3, NA, NA, NA, NA, NA, NA, NA },
    {  0,  8,  2,  2,  8, 11,  4,  9, 10,  4, 10,  6, NA, NA, NA, NA },
    {  3, 11,  2,  0,  1,  6,  0,  6,  4,  6,  1, 10, NA, NA, NA, NA },
    {  6,  4,  1,  6,  1, 10,  4,  8,  1,  2,  1, 11,  8, 11,  1, NA },
    {  9,  6,  4,  9,  3,  6,  9,  1,  3, 11,  6,  3, NA, NA, NA, NA },
    {  8, 11,  1,  8,  1,  0, 11,  6,  1,  9,  1,  4,  6,  4,  1, NA },
    {  3, 11,  6,  3,  6,  0,  0,  6,  4, NA, NA, NA, NA, NA, NA, NA },
    {  6,  4,  8, 11,  6,  8, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA },
    {  7, 10,  6,  7,  8, 10,  8,  9, 10, NA, NA, NA, NA, NA, NA, NA },
    {  0,  7,  3,  0, 10,  7,  0,  9, 10,  6,  7, 10, NA, NA, NA, NA },
    { 10,  6,  7,  1, 10,  7,  1,  7,  8,  1,  8,  0, NA, NA, NA, NA },
    { 10,  6,  7, 10,  7,  1,  1,  7,  3, NA, NA, NA, NA, NA, NA, NA },
    {  1,  2,  6,  1,  6,  8,  1,  8,  9,  8,  6,  7, NA, NA, NA, NA },
    {  2,  6,  9,  2,  9,  1,  6,  7,  9,  0,  9,  3,  7,  3,  9, NA },
    {  7,  8,  0,  7,  0,  6,  6,  0,  2, NA, NA, NA, NA, NA, NA, NA },
    {  7,  3,  2,  6,  7,  2, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA },
    {  2,  3, 11, 10,  6,  8, 10,  8,  9,  8,  6,  7, NA, NA, NA, NA },
    {  2,  0,  7,  2,  7, 11,  0,  9,  7,  6,  7, 10,  9, 10,  7, NA },
    {  1,  8,  0,  1,  7,  8,  1, 10,  7,  6,  7, 10,  2,  3, 11, NA },
    { 11,  2,  1, 11,  1,  7, 10,  6,  1,  6,  7,  1, NA, NA, NA, NA },
    {  8,  9,  6,  8,  6,  7,  9,  1,  6, 11,  6,  3,  1,  3,  6, NA },
    {  0,  9,  1, 11,  6,  7, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA },
    {  7,  8,  0,  7,  0,  6,  3, 11,  0, 11,  6,  0, NA, NA, NA, NA },
    {  7, 11,  6, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA },
    {  7,  6, 11, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA },
    {  3,  0,  8, 11,  7,  6, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA },
    {  0,  1,  9, 11,  7,  6, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA },
    {  8,  1,  9,  8,  3,  1, 11,  7,  6, NA, NA, NA, NA, NA, NA, NA },
    { 10,  1,  2,  6, 11,  7, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA },
    {  1,  2, 10,  3,  0,  8,  6, 11,  7, NA, NA, NA, NA, NA, NA, NA },
    {  2,  9,  0,  2, 10,  9,  6, 11,  7, NA, NA, NA, NA, NA, NA, NA },
    {  6, 11,  7,  2, 10,  3, 10,  8,  3, 10,  9,  8, NA, NA, NA, NA },
    {  7,  2,  3,  6,  2,  7, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA },
    {  7,  0,  8,  7,  6,  0,  6,  2,  0, NA, NA, NA, NA, NA, NA, NA },
    {  2,  7,  6,  2,  3,  7,  0,  1,  9, NA, NA, NA, NA, NA, NA, NA },
    {  1,  6,  2,  1,  8,  6,  1,  9,  8,  8,  7,  6, NA, NA, NA, NA },
    { 10,  7,  6, 10,  1,  7,  1,  3,  7, NA, NA, NA, NA, NA, NA, NA },
    { 10,  7,  6,  1,  7, 10,  1,  8,  7,  1,  0,  8, NA, NA, NA, NA },
    {  0,  3,  7,  0,  7, 10,  0, 10,  9,  6, 10,  7, NA, NA, NA, NA },
    {  7,  6, 10,  7, 10,  8,  8, 10,  9, NA, NA, NA, NA, NA, NA, NA },
    {  6,  8,  4, 11,  8,  6, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA },
    {  3,  6, 11,  3,  0,  6,  0,  4,  6, NA, NA, NA, NA, NA, NA, NA },
    {  8,  6, 11,  8,  4,  6,  9,  0,  1, NA, NA, NA, NA, NA, NA, NA },
    {  9,  4,  6,  9,  6,  3,  9,  3,  1, 11,  3,  6, NA, NA, NA, NA },
    {  6,  8,  4,  6, 11,  8,  2, 10,  1, NA, NA, NA, NA, NA, NA, NA },
    {  1,  2, 10,  3,  0, 11,  0,  6, 11,  0,  4,  6, NA, NA, NA, NA },
    {  4, 11,  8,  4,  6, 11,  0,  2,  9,  2, 10,  9, NA, NA, NA, NA },
    { 10,  9,  3, 10,  3,  2,  9,  4,  3, 11,  3,  6,  4,  6,  3, NA },
    {  8,  2,  3,  8,  4,  2,  4,  6,  2, NA, NA, NA, NA, NA, NA, NA },
    {  0,  4,  2,  4,  6,  2, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA },
    {  1,  9,  0,  2,  3,  4,  2,  4,  6,  4,  3,  8, NA, NA, NA, NA },
    {  1,  9,  4,  1,  4,  2,  2,  4,  6, NA, NA, NA, NA, NA, NA, NA },
    {  8,  1,  3,  8,  6,  1,  8,  4,  6,  6, 10,  1, NA, NA, NA, NA },
    { 10,  1,  0, 10,  0,  6,  6,  0,  4, NA, NA, NA, NA, NA, NA, NA },
    {  4,  6,  3,  4,  3,  8,  6, 10,  3,  0,  3,  9, 10,  9,  3, NA },
    { 10,  9,  4,  6, 10,  4, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA },
    {  4,  9,  5,  7,  6, 11, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA },
    {  0,  8,  3,  4,  9,  5, 11,  7,  6, NA, NA, NA, NA, NA, NA, NA },
    {  5,  0,  1,  5,  4,  0,  7,  6, 11, NA, NA, NA, NA, NA, NA, NA },
    { 11,  7,  6,  8,  3,  4,  3,  5,  4,  3,  1,  5, NA, NA, NA, NA },
    {  9,  5,  4, 10,  1,  2,  7,  6, 11, NA, NA, NA, NA, NA, NA, NA },
    {  6, 11,  7,  1,  2, 10,  0,  8,  3,  4,  9,  5, NA, NA, NA, NA },
    {  7,  6, 11,  5,  4, 10,  4,  2, 10,  4,  0,  2, NA, NA, NA, NA },
    {  3,  4,  8,  3,  5,  4,  3,  2,  5, 10,  5,  2, 11,  7,  6, NA },
    {  7,  2,  3,  7,  6,  2,  5,  4,  9, NA, NA, NA, NA, NA, NA, NA },
    {  9,  5,  4,  0,  8,  6,  0,  6,  2,  6,  8,  7, NA, NA, NA, NA },
    {  3,  6,  2,  3,  7,  6,  1,  5,  0,  5,  4,  0, NA, NA, NA, NA },
    {  6,  2,  8,  6,  8,  7,  2,  1,  8,  4,  8,  5,  1,  5,  8, NA },
    {  9,  5,  4, 10,  1,  6,  1,  7,  6,  1,  3,  7, NA, NA, NA, NA },
    {  1,  6, 10,  1,  7,  6,  1,  0,  7,  8,  7,  0,  9,  5,  4, NA },
    {  4,  0, 10,  4, 10,  5,  0,  3, 10,  6, 10,  7,  3,  7, 10, NA },
    {  7,  6, 10,  7, 10,  8,  5,  4, 10,  4,  8, 10, NA, NA, NA, NA },
    {  6,  9,  5,  6, 11,  9, 11,  8,  9, NA, NA, NA, NA, NA, NA, NA },
    {  3,  6, 11,  0,  6,  3,  0,  5,  6,  0,  9,  5, NA, NA, NA, NA },
    {  0, 11,  8,  0,  5, 11,  0,  1,  5,  5,  6, 11, NA, NA, NA, NA },
    {  6, 11,  3,  6,  3,  5,  5,  3,  1, NA, NA, NA, NA, NA, NA, NA },
    {  1,  2, 10,  9,  5, 11,  9, 11,  8, 11,  5,  6, NA, NA, NA, NA },
    {  0, 11,  3,  0,  6, 11,  0,  9,  6,  5,  6,  9,  1,  2, 10, NA },
    { 11,  8,  5, 11,  5,  6,  8,  0,  5, 10,  5,  2,  0,  2,  5, NA },
    {  6, 11,  3,  6,  3,  5,  2, 10,  3, 10,  5,  3, NA, NA, NA, NA },
    {  5,  8,  9,  5,  2,  8,  5,  6,  2,  3,  8,  2, NA, NA, NA, NA },
    {  9,  5,  6,  9,  6,  0,  0,  6,  2, NA, NA, NA, NA, NA, NA, NA },
    {  1,  5,  8,  1,  8,  0,  5,  6,  8,  3,  8,  2,  6,  2,  8, NA },
    {  1,  5,  6,  2,  1,  6, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA },
    {  1,  3,  6,  1,  6, 10,  3,  8,  6,  5,  6,  9,  8,  9,  6, NA },
    { 10,  1,  0, 10,  0,  6,  9,  5,  0,  5,  6,  0, NA, NA, NA, NA },
    {  0,  3,  8,  5,  6, 10, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA },
    { 10,  5,  6, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA },
    { 11,  5, 10,  7,  5, 11, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA },
    { 11,  5, 10, 11,  7,  5,  8,  3,  0, NA, NA, NA, NA, NA, NA, NA },
    {  5, 11,  7,  5, 10, 11,  1,  9,  0, NA, NA, NA, NA, NA, NA, NA },
    { 10,  7,  5, 10, 11,  7,  9,  8,  1,  8,  3,  1, NA, NA, NA, NA },
    { 11,  1,  2, 11,  7,  1,  7,  5,  1, NA, NA, NA, NA, NA, NA, NA },
    {  0,  8,  3,  1,  2,  7,  1,  7,  5,  7,  2, 11, NA, NA, NA, NA },
    {  9,  7,  5,  9,  2,  7,  9,  0,  2,  2, 11,  7, NA, NA, NA, NA },
    {  7,  5,  2,  7,  2, 11,  5,  9,  2,  3,  2,  8,  9,  8,  2, NA },
    {  2,  5, 10,  2,  3,  5,  3,  7,  5, NA, NA, NA, NA, NA, NA, NA },
    {  8,  2,  0,  8,  5,  2,  8,  7,  5, 10,  2,  5, NA, NA, NA, NA },
    {  9,  0,  1,  5, 10,  3,  5,  3,  7,  3, 10,  2, NA, NA, NA, NA },
    {  9,  8,  2,  9,  2,  1,  8,  7,  2, 10,  2,  5,  7,  5,  2, NA },
    {  1,  3,  5,  3,  7,  5, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA },
    {  0,  8,  7,  0,  7,  1,  1,  7,  5, NA, NA, NA, NA, NA, NA, NA },
    {  9,  0,  3,  9,  3,  5,  5,  3,  7, NA, NA, NA, NA, NA, NA, NA },
    {  9,  8,  7,  5,  9,  7, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA },
    {  5,  8,  4,  5, 10,  8, 10, 11,  8, NA, NA, NA, NA, NA, NA, NA },
    {  5,  0,  4,  5, 11,  0,  5, 10, 11, 11,  3,  0, NA, NA, NA, NA },
    {  0,  1,  9,  8,  4, 10,  8, 10, 11, 10,  4,  5, NA, NA, NA, NA },
    { 10, 11,  4, 10,  4,  5, 11,  3,  4,  9,  4,  1,  3,  1,  4, NA },
    {  2,  5,  1,  2,  8,  5,  2, 11,  8,  4,  5,  8, NA, NA, NA, NA },
    {  0,  4, 11,  0, 11,  3,  4,  5, 11,  2, 11,  1,  5,  1, 11, NA },
    {  0,  2,  5,  0,  5,  9,  2, 11,  5,  4,  5,  8, 11,  8,  5, NA },
    {  9,  4,  5,  2, 11,  3, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA },
    {  2,  5, 10,  3,  5,  2,  3,  4,  5,  3,  8,  4, NA, NA, NA, NA },
    {  5, 10,  2,  5,  2,  4,  4,  2,  0, NA, NA, NA, NA, NA, NA, NA },
    {  3, 10,  2,  3,  5, 10,  3,  8,  5,  4,  5,  8,  0,  1,  9, NA },
    {  5, 10,  2,  5,  2,  4,  1,  9,  2,  9,  4,  2, NA, NA, NA, NA },
    {  8,  4,  5,  8,  5,  3,  3,  5,  1, NA, NA, NA, NA, NA, NA, NA },
    {  0,  4,  5,  1,  0,  5, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA },
    {  8,  4,  5,  8,  5,  3,  9,  0,  5,  0,  3,  5, NA, NA, NA, NA },
    {  9,  4,  5, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA },
    {  4, 11,  7,  4,  9, 11,  9, 10, 11, NA, NA, NA, NA, NA, NA, NA },
    {  0,  8,  3,  4,  9,  7,  9, 11,  7,  9, 10, 11, NA, NA, NA, NA },
    {  1, 10, 11,  1, 11,  4,  1,  4,  0,  7,  4, 11, NA, NA, NA, NA },
    {  3,  1,  4,  3,  4,  8,  1, 10,  4,  7,  4, 11, 10, 11,  4, NA },
    {  4, 11,  7,  9, 11,  4,  9,  2, 11,  9,  1,  2, NA, NA, NA, NA },
    {  9,  7,  4,  9, 11,  7,  9,  1, 11,  2, 11,  1,  0,  8,  3, NA },
    { 11,  7,  4, 11,  4,  2,  2,  4,  0, NA, NA, NA, NA, NA, NA, NA },
    { 11,  7,  4, 11,  4,  2,  8,  3,  4,  3,  2,  4, NA, NA, NA, NA },
    {  2,  9, 10,  2,  7,  9,  2,  3,  7,  7,  4,  9, NA, NA, NA, NA },
    {  9, 10,  7,  9,  7,  4, 10,  2,  7,  8,  7,  0,  2,  0,  7, NA },
    {  3,  7, 10,  3, 10,  2,  7,  4, 10,  1, 10,  0,  4,  0, 10, NA },
    {  1, 10,  2,  8,  7,  4, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA },
    {  4,  9,  1,  4,  1,  7,  7,  1,  3, NA, NA, NA, NA, NA, NA, NA },
    {  4,  9,  1,  4,  1,  7,  0,  8,  1,  8,  7,  1, NA, NA, NA, NA },
    {  4,  0,  3,  7,  4,  3, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA },
    {  4,  8,  7, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA },
    {  9, 10,  8, 10, 11,  8, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA },
    {  3,  0,  9,  3,  9, 11, 11,  9, 10, NA, NA, NA, NA, NA, NA, NA },
    {  0,  1, 10,  0, 10,  8,  8, 10, 11, NA, NA, NA, NA, NA, NA, NA },
    {  3,  1, 10, 11,  3, 10, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA },
    {  1,  2, 11,  1, 11,  9,  9, 11,  8, NA, NA, NA, NA, NA, NA, NA },
    {  3,  0,  9,  3,  9, 11,  1,  2,  9,  2, 11,  9, NA, NA, NA, NA },
    {  0,  2, 11,  8,  0, 11, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA },
    {  3,  2, 11, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA },
    {  2,  3,  8,  2,  8, 10, 10,  8,  9, NA, NA, NA, NA, NA, NA, NA },
    {  9, 10,  2,  0,  9,  2, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA },
    {  2,  3,  8,  2,  8, 10,  0,  1,  8,  1, 10,  8, NA, NA, NA, NA },
    {  1, 10,  2, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA },
    {  1,  3,  8,  9,  1,  8, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA },
    {  0,  9,  1, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA },
    {  0,  3,  8, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA },
    { NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA, NA }};


