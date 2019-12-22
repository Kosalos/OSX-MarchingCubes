#pragma once

#include <simd/simd.h>

typedef struct {
	vector_float3 pos;          // position
	vector_float3 nrm;          // normal vector
	vector_float4 texColor;     // tringle texture coord,  else line color
	float flux;                 
	unsigned char inside;
} TVertex;

typedef struct {
    vector_float3 pos;
    float power;
} BallData;

typedef struct {
    float isoValue;
    float movement;
    float movement2;
    int drawStyle;

    vector_float3 base; // for determineGridPositions shader
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
#define GSPAN  50 // #marching cubes x,y,z

