
void ChooseColor_float(float3 Highlight, float3 Midtone, float3 Shadow, float Diffuse, float ShadowThreshold, float HighlightThreshold, out float3 OUT)
{
    if (Diffuse < ShadowThreshold)
    {
        OUT = Shadow;
    }
    else if (Diffuse < HighlightThreshold)
    {
        OUT = Midtone;
    }
    else
    {
        OUT = Highlight;
    }
}