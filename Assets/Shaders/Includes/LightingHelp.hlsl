// Helpers for the toon shader graph. Everything that needs the URP lighting
// API lives here because shader graph has no built-in node for it.

void GetMainLight_float(float3 WorldPos, out float3 Color, out float3 Direction, out float DistanceAtten, out float ShadowAtten) {
#ifdef SHADERGRAPH_PREVIEW
    Direction = normalize(float3(0.5, 0.5, 0));
    Color = 1;
    DistanceAtten = 1;
    ShadowAtten = 1;
#else
    #if SHADOWS_SCREEN
        float4 clipPos = TransformWorldToClip(WorldPos);
        float4 shadowCoord = ComputeScreenPos(clipPos);
    #else
        float4 shadowCoord = TransformWorldToShadowCoord(WorldPos);
    #endif

    Light mainLight = GetMainLight(shadowCoord);
    Direction = mainLight.direction;
    Color = mainLight.color;
    DistanceAtten = mainLight.distanceAttenuation;
    ShadowAtten = mainLight.shadowAttenuation;
#endif
}

// Sums the lambert term of every additional (point / spot) light hitting this
// fragment so they can be fed into the same banding as the main light.
void GetAdditionalLights_float(float3 WorldPos, float3 WorldNormal, out float Diffuse)
{
    Diffuse = 0;
#ifndef SHADERGRAPH_PREVIEW
    uint lightCount = GetAdditionalLightsCount();
    for (uint i = 0u; i < lightCount; ++i)
    {
        Light light = GetAdditionalLight(i, WorldPos, half4(1, 1, 1, 1));
        float nDotL = saturate(dot(WorldNormal, light.direction));
        float atten = light.distanceAttenuation * light.shadowAttenuation;
        Diffuse += nDotL * atten * Luminance(light.color);
    }
#endif
}

// Puzzle 1: hard two tone split.
void ChooseColor_float(float3 Highlight, float3 Shadow, float Diffuse, float Threshold, out float3 OUT)
{
    if (Diffuse < Threshold)
    {
        OUT = Shadow;
    }
    else
    {
        OUT = Highlight;
    }
}

// Puzzle 2 + extra credit: three bands with adjustable thresholds. Smoothness
// widens the transition around each threshold; 0 gives a hard step.
void ToonBands_float(float3 Highlight, float3 Midtone, float3 Shadow, float Diffuse,
                     float HighlightThreshold, float ShadowThreshold, float Smoothness, out float3 OUT)
{
    float halfWidth = max(Smoothness * 0.5, 0.0001);

    float shadowToMid = smoothstep(ShadowThreshold - halfWidth, ShadowThreshold + halfWidth, Diffuse);
    float midToHighlight = smoothstep(HighlightThreshold - halfWidth, HighlightThreshold + halfWidth, Diffuse);

    float3 color = lerp(Shadow, Midtone, shadowToMid);
    OUT = lerp(color, Highlight, midToHighlight);
}
