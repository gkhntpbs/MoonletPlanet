#ifndef MoonletPlanetShaderTypes_h
#define MoonletPlanetShaderTypes_h

#include <simd/simd.h>

typedef struct {
    vector_float2 viewportSize;
    float time;
    uint32_t archetype;
    uint32_t seed;
    float rotationSpeed;
    float turbulence;
    float detail;
    float warpStrength;
    float bandCount;
    float bandSharpness;
    float stormCount;
    float stormStrength;
    float cloudCoverage;
    float cloudSpeed;
    float atmosphereDensity;
    float atmosphereGlow;
    float roughness;
    float featureAmount;
    float lightAzimuth;
    float lightElevation;
    float exposure;
    float ringOpacity;
    float axialTilt;
    float ringInnerRadius;
    float ringOuterRadius;
    float ringDetail;
    float iceCoverage;
    float iceAltitude;
    float polarAsymmetry;
    float microDetail;
    float rotationPhase;
    vector_float4 color0;
    vector_float4 color1;
    vector_float4 color2;
    vector_float4 color3;
    vector_float4 atmosphereColor;
    vector_float4 ringColor;
    vector_float4 iceColor;
} MoonletPlanetUniforms;

#endif
