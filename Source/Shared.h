#pragma once

#include <simd/simd.h>

typedef struct {
	vector_float3 pos;
	vector_float3 nrm;
	vector_float4 texColor;    // alpha = 0 == texture coord,  else color
	
	float flux;
	unsigned char inside;
} TVertex;

typedef struct {
    vector_float3 pos;
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
    int drawStyle;

    vector_float3 base; // for updateMarchingCubes shader
    vector_float2 rot;
} Control;

typedef struct {
    matrix_float4x4 mvp;
    float pointSize;
    vector_float3 light;
} Uniforms;

typedef struct {
    int count;
} Counter;

#define BCOUNT 12 // #flux points
#define GSPAN  30 // #marching cubes x,y,z

