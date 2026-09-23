//UNITY_SHADER_NO_UPGRADE
#ifndef LAB03_LIGHTING_HELP_INCLUDED
#define LAB03_LIGHTING_HELP_INCLUDED

#ifndef SHADERGRAPH_PREVIEW
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
#endif

// Keep the entry point supplied with the lab available for experimentation.
void GetMainLight_float(float3 WorldPos, out float3 Color, out float3 Direction,
    out float DistanceAtten, out float ShadowAtten)
{
#ifdef SHADERGRAPH_PREVIEW
    Direction = normalize(float3(0.5, 0.7, -0.4));
    Color = 1;
    DistanceAtten = 1;
    ShadowAtten = 1;
#else
    #if defined(_MAIN_LIGHT_SHADOWS_SCREEN)
        float4 shadowCoord = ComputeScreenPos(TransformWorldToHClip(WorldPos));
    #else
        float4 shadowCoord = TransformWorldToShadowCoord(WorldPos);
    #endif
    Light mainLight = GetMainLight(shadowCoord, WorldPos, half4(1, 1, 1, 1));
    Direction = mainLight.direction;
    Color = mainLight.color;
    DistanceAtten = mainLight.distanceAttenuation;
    ShadowAtten = mainLight.shadowAttenuation;
#endif
}

// Quantize combined illumination once so overlapping lights retain the palette.
void ToonLighting_float(float3 WorldPos, float3 WorldNormal,
    out float Diffuse, out float Unshadowed, out float ShadowMask)
{
    float3 normal = normalize(WorldNormal);
    float3 color, direction;
    float distanceAtten, shadowAtten;
    GetMainLight_float(WorldPos, color, direction, distanceAtten, shadowAtten);
    float contribution = saturate(dot(normal, direction)) * distanceAtten
        * dot(color, float3(0.2126, 0.7152, 0.0722));
    float total = contribution;
    float visible = contribution * shadowAtten;

#if !defined(SHADERGRAPH_PREVIEW) && defined(_ADDITIONAL_LIGHTS)
    // The supplied renderer uses URP Forward with per-pixel additional lights.
    uint count = GetAdditionalLightsCount();
    for (uint i = 0u; i < count; ++i)
    {
        Light light = GetAdditionalLight(i, WorldPos, half4(1, 1, 1, 1));
        contribution = saturate(dot(normal, light.direction))
            * light.distanceAttenuation
            * dot(light.color, float3(0.2126, 0.7152, 0.0722));
        total += contribution;
        visible += contribution * light.shadowAttenuation;
    }
#endif

    // Use unsaturated sums for the ratio. Back-facing alone is not occlusion.
    ShadowMask = total > 0.0001 ? saturate(1.0 - visible / total) : 0.0;
    Diffuse = saturate(visible);
    Unshadowed = saturate(total);
}

float ToonStep(float value, float threshold, float smoothness)
{
    // Zero is a hard step; smoothstep with coincident edges is undefined.
    if (smoothness <= 0.00001)
        return step(threshold, value);
    float halfWidth = 0.5 * smoothness;
    return smoothstep(threshold - halfWidth, threshold + halfWidth, value);
}

float3 ToonPalette(float diffuse, float3 highlight, float3 midtone, float3 shadow,
    float shadowThreshold, float highlightThreshold, float threeBands, float smoothness)
{
    float lo = clamp(shadowThreshold, 0.001, 0.999);
    float hi = clamp(max(highlightThreshold, lo + 0.001), lo + 0.001, 1.0);
    float width = max(smoothness, 0.0);
    if (threeBands < 0.5)
        return lerp(shadow, highlight, ToonStep(diffuse, lo, width));

    // Limit overlap, preserving a midtone plateau with wide transitions.
    width = min(width, hi - lo);
    float3 lowerBand = lerp(shadow, midtone, ToonStep(diffuse, lo, width));
    return lerp(lowerBand, highlight, ToonStep(diffuse, hi, width));
}

void ToonBands_float(float Diffuse, float Unshadowed, float3 Highlight,
    float3 Midtone, float3 Shadow, float ShadowThreshold, float HighlightThreshold,
    float ThreeBands, float Smoothness, out float3 Color, out float3 UnshadowedColor)
{
    Color = ToonPalette(Diffuse, Highlight, Midtone, Shadow, ShadowThreshold,
        HighlightThreshold, ThreeBands, Smoothness);
    UnshadowedColor = ToonPalette(Unshadowed, Highlight, Midtone, Shadow,
        ShadowThreshold, HighlightThreshold, ThreeBands, Smoothness);
}

// Default Screen Position is already divided by clip-space W. Aspect correction
// gives square tiles, independent of the model's UVs.
void ScreenPatternUV_float(float4 ScreenPosition, float PatternScale, out float2 UV)
{
#ifdef SHADERGRAPH_PREVIEW
    float aspect = 1.0;
#else
    float aspect = _ScreenParams.x / max(_ScreenParams.y, 1.0);
#endif
    UV = ScreenPosition.xy * float2(aspect, 1.0) * max(PatternScale, 0.01);
}

void PatternShadow_float(float3 Color, float3 UnshadowedColor, float3 Shadow,
    float Pattern, float ShadowMask, float PatternStrength, out float3 Out)
{
    // Textures: black = ink, white = paper. Attenuation masks actual occlusion.
    float3 patterned = lerp(Shadow, UnshadowedColor, saturate(Pattern));
    Out = lerp(Color, patterned, saturate(ShadowMask) * saturate(PatternStrength));
}

void ChooseColor_float(float3 Highlight, float3 Shadow, float Diffuse,
    float Threshold, out float3 OUT)
{
    OUT = lerp(Shadow, Highlight, step(Threshold, Diffuse));
}

#endif
