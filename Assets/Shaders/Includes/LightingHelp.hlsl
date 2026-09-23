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

float3 ToonBand(float3 Highlight, float3 Midtone, float3 Shadow, float Diffuse, float ShadowThreshold, float HighlightThreshold)
{
    if (Diffuse < ShadowThreshold)
    {
        return Shadow;
    }
    else if (Diffuse < HighlightThreshold)
    {
        return Midtone;
    }
    else
    {
        return Highlight;
    }
}

// Diffuse includes the main light's ShadowAtten; LitDiffuse is the same N.L without it, so the two only differ
// inside cast shadows. There, a screen-space Pattern (white = gap, black = line) picks between the shadowed tone
// and the tone the surface would have in the light. A black (unassigned) Pattern leaves plain toon shadows.
void ChooseColor_float(float3 Highlight, float3 Midtone, float3 Shadow, float Diffuse, float ShadowThreshold, float HighlightThreshold,
                       float LitDiffuse, float4 ScreenPos, UnityTexture2D Pattern, float PatternScale, out float3 OUT)
{
    float3 shadowed = ToonBand(Highlight, Midtone, Shadow, Diffuse, ShadowThreshold, HighlightThreshold);
    float3 lit = ToonBand(Highlight, Midtone, Shadow, LitDiffuse, ShadowThreshold, HighlightThreshold);

    // Aspect-correct so the pattern isn't stretched, then swap axes so vertical stripes read as horizontal hatching.
    float2 uv = float2(ScreenPos.x * _ScreenParams.x / _ScreenParams.y, ScreenPos.y) * PatternScale;
    float gap = SAMPLE_TEXTURE2D(Pattern.tex, Pattern.samplerstate, uv.yx).r;

    OUT = lerp(shadowed, lit, gap);
}