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

// Diffuse term that the toon bands get picked from.
// LitDiffuse ignores cast shadows, ShadowedDiffuse includes them. Keeping both around
// lets the shadow pattern blend between "what it would look like lit" and "in shadow".
// Additional (point/spot) lights just get added on top of the main light.
void ToonDiffuse_float(float3 WorldPos, float3 WorldNormal, float3 MainLightDir, float DistanceAtten, float ShadowAtten,
                       out float LitDiffuse, out float ShadowedDiffuse)
{
    float3 n = normalize(WorldNormal);
    float mainNdotL = saturate(dot(n, MainLightDir)) * DistanceAtten;

    LitDiffuse = mainNdotL;
    ShadowedDiffuse = mainNdotL * ShadowAtten;

#ifndef SHADERGRAPH_PREVIEW
    uint lightCount = GetAdditionalLightsCount();
    for (uint i = 0; i < lightCount; i++)
    {
        Light light = GetAdditionalLight(i, WorldPos, half4(1, 1, 1, 1));
        float ndotl = saturate(dot(n, light.direction)) * light.distanceAttenuation;
        LitDiffuse += ndotl;
        ShadowedDiffuse += ndotl * light.shadowAttenuation;
    }
#endif

    LitDiffuse = saturate(LitDiffuse);
    ShadowedDiffuse = saturate(ShadowedDiffuse);
}

// Three band version of ChooseColor. Anything below ShadowThreshold is Shadow, between
// the two thresholds is Midtone, above HighlightThreshold is Highlight.
// Smoothness widens the transition at each edge (0 = hard toon edges).
void ChooseColor3_float(float3 Highlight, float3 Midtone, float3 Shadow, float Diffuse,
                        float ShadowThreshold, float HighlightThreshold, float Smoothness, out float3 OUT)
{
    float w = max(Smoothness * 0.5, 0.0001);
    float toMid = smoothstep(ShadowThreshold - w, ShadowThreshold + w, Diffuse);
    float toHigh = smoothstep(HighlightThreshold - w, HighlightThreshold + w, Diffuse);
    OUT = lerp(lerp(Shadow, Midtone, toMid), Highlight, toHigh);
}

// Screen space shadow pattern. The texture is sampled in screen space (aspect corrected so
// the lines don't stretch) and used to mix between the lit color and the shadowed color.
// Dark texels = shadow shows through, white texels = lit color.
// Rotation (degrees) spins the pattern, e.g. 90 turns the vertical stripes horizontal.
// Strength 0 turns the pattern off and just gives the regular shadowed color.
void ShadowPattern_float(UnityTexture2D PatternTex, float4 ScreenPos, float Tiling, float Rotation, float Strength,
                         float3 LitColor, float3 ShadowedColor, out float3 OUT)
{
    float2 uv = ScreenPos.xy;
#ifndef SHADERGRAPH_PREVIEW
    uv.x *= _ScreenParams.x / _ScreenParams.y;
#endif
    float s, c;
    sincos(radians(Rotation), s, c);
    uv = mul(float2x2(c, -s, s, c), uv) * Tiling;

    float pattern = 1.0 - SAMPLE_TEXTURE2D(PatternTex.tex, PatternTex.samplerstate, uv).r;
    float3 patterned = lerp(LitColor, ShadowedColor, pattern);
    OUT = lerp(ShadowedColor, patterned, saturate(Strength));
}
