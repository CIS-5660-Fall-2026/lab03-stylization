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

void ChooseColor3_float(float3 Highlight, float3 Midtone, float3 Shadow, float Diffuse, float ThresholdHigh, float ThresholdLow, float Smoothness, out float3 OUT)
{
    float edge = max(Smoothness * 0.5, 0.0001);
    float low = smoothstep(ThresholdLow - edge, ThresholdLow + edge, Diffuse);
    float high = smoothstep(ThresholdHigh - edge, ThresholdHigh + edge, Diffuse);
    OUT = lerp(lerp(Shadow, Midtone, low), Highlight, high);
}
