#include <metal_stdlib>
#import <simd/simd.h>

#define SHADER
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

vertex ColorInOut lighting_vertex
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
    float intensity = 2 + saturate(dot(nrm.rgb, normalize(constants.light)));
    out.lighting = float4(intensity,intensity,intensity,1);
    
    return out;
}

fragment float4 textureFragment
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

///////////////////////////////////////

constant int GSPAN2 = GSPAN * GSPAN;
constant int GTOTAL = GSPAN * GSPAN * GSPAN;

kernel void calcGridPower
(
 device TVertex *grid            [[ buffer(0) ]],
 const device BallData *ballData [[ buffer(1) ]],
 const device ConstantData *cd   [[ buffer(2) ]],
 uint id [[ thread_position_in_grid ]]
 )
{
    if(id >= GTOTAL) return; // size not evenly divisible by threads
    
    grid[id].flux = 0;
    
    for(int i=0;i<BCOUNT;++i) {
        float3 d = ballData[i].pos - grid[id].pos;
        
        grid[id].flux += ballData[i].power * ballData[i].power / (d.x * d.x + d.y * d.y + d.z * d.z + 1);
        grid[id].inside = grid[id].flux > cd->isoValue ? 1 : 0;
    }
}

kernel void calcGridPower2
(
 device TVertex *grid            [[ buffer(0) ]],
 const device BallData *ballData [[ buffer(1) ]],
 uint id [[ thread_position_in_grid ]]
 )
{
    if(id >= GTOTAL) return; // size not evenly divisible by threads

    grid[id].nrm.x = (id == 0 || id == GTOTAL-1) ? 0 : grid[id - 1].flux - grid[id + 1].flux;
    grid[id].nrm.y = (id < GSPAN || id > GTOTAL-GSPAN) ? 0 : grid[id - GSPAN].flux - grid[id + GSPAN].flux;
    grid[id].nrm.z = (id < GSPAN2 || id > GTOTAL-GSPAN2) ? 0 : grid[id - GSPAN2].flux - grid[id + GSPAN2].flux;
    
    grid[id].nrm = normalize(grid[id].nrm);
}

///////////////////////////////////////////

kernel void calcBallMovement
(
 device BallData *ballData     [[ buffer(0) ]],
 const device ConstantData *cd [[ buffer(1) ]],
 uint id [[ thread_position_in_grid ]]
 )
{
    if(id >= BCOUNT) return; // size not evenly divisible by threads

    float fi = float(id);
    float f1 = float(id+3);
    
    ballData[id].pos.x = cos(cd->movement  * (fi + 1)  ) * 1.9 * f1/2;
    ballData[id].pos.y = sin(cd->movement  * (fi + 1.2)) * 2.1 * f1/2;
    ballData[id].pos.z = cos(cd->movement2 * (fi + 1.5)) * 2.4 * f1/3;
}

