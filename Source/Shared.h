#pragma once

#include <simd/simd.h>

#ifdef SHADER
    #define CC constant
    typedef simd::float3 simd_float3;
    typedef simd::float4 simd_float4;
    typedef metal::uchar u_char;
#else
    #define CC
#endif

typedef struct {
	simd_float3 pos;
	simd_float3 nrm;
	simd_float4 texColor;    // alpha = 0 == texture coord,  else color
	
	float flux;
	u_char inside;
	
	int unused1;
	int unused2;
} TVertex;

typedef struct {
    simd_float3 pos;
    float power;
    
    int unused1;
    int unused2;
    int unused3;
} BallData;

typedef struct {
    float isoValue;
    float movement;
    float movement2;
    int index;
    int lookup;
} ConstantData;

#define BCOUNT 12 // #flux points
#define GSPAN  10 // #marching cubes x,y,z

