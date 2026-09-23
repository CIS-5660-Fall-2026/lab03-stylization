Shader "CustomShaders/TwoToneCelShader"
{
    Properties
    {
        _MainColor("Surface Color", Color) = (1, 1, 1, 1)
        _Smoothness("Smoothness Coefficient", Range(0.0, 1.0)) = 1.0

        _SpecularThreshold("Specular Threshold",  Range(0.0, 1.0)) = 0.5
        _ShadowThreshold("Shadow Threshold",  Range(0.0, 1.0)) = 0.5
        _AmbientStrength("Ambient Strength",  Range(0.0, 10.0)) = 1

        _OutlineWidth("Outline Width",  Range(0.0, 0.02)) = 0.01
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" }

        // Cel shader
        Pass
        {
            Cull Back ZWrite On

            Tags
            {
                "LightMode" = "UniversalForward"
            }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            
            #pragma multi_compile_fwdbase nolightmap nodirlightmap nodynlightmap novertexlight

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            struct a2v
            {
                float4 vertexOS : POSITION;
                float3 normalOS : NORMAL;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float4 vertexCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float4 vertexSS : TEXCOORD1;
                float4 vertexWS : TEXCOORD2;
                float3 normalWS : TEXCOORD3;
            };

            float3 _MainColor;
            float _Smoothness;

            float _SpecularThreshold;
            float _ShadowThreshold;
            float _AmbientStrength;

            v2f vert(a2v v)
            {
                v2f o;
                o.uv = v.uv;
                o.vertexWS = mul(UNITY_MATRIX_M, v.vertexOS);
                o.vertexCS = mul(UNITY_MATRIX_VP, o.vertexWS);
                o.vertexSS = ComputeScreenPos(o.vertexCS);
                o.normalWS = TransformObjectToWorldNormal(v.normalOS);

                return o;
            }

            float4 frag(v2f i) : SV_Target
            {
                // Get light
                Light l = GetMainLight(TransformWorldToShadowCoord(i.vertexWS.xyz));

                // Calculate shadow
                float shadow = step(_ShadowThreshold, saturate(l.shadowAttenuation));

                // Calculate diffuse
                float diffuse = saturate(dot(i.normalWS, l.direction));
                diffuse *= shadow;

                // Get view direction
                float3 viewDirWS = normalize(_WorldSpaceCameraPos.xyz - i.vertexWS.xyz);
                float3 h = normalize(l.direction + viewDirWS);
                // Calculate specular
                float specular = pow(saturate(dot(i.normalWS, h)), exp2(10 * _Smoothness + 1));
                specular *= diffuse * _Smoothness;
                specular = step(_SpecularThreshold, specular);

                // // Calculate rim light
                // float rim = 1 - dot(viewDirWS, i.normalWS);
                // rim *= pow(diffuse, _RimCoe);
                // rim = step(_RimThreshold, rim);

                // Get ambient
                //float3 ambient = UNITY_LIGHTMODEL_AMBIENT.xyz;
                float3 ambient = float3(unity_SHAr.w, unity_SHAg.w, unity_SHAb.w);

                // float4 outColor = float4(l.color.rgb * (diffuse * _DiffuseStrength + max(specular, rim)) + ambient, 1);
                float4 outColor = float4((l.color.rgb * specular + ambient * _AmbientStrength) * _MainColor, 1);

                return outColor;
            }

            ENDHLSL
        }

        // Outline
        Pass
        {
            Name "OutlinePass"

            Cull Front

            HLSLPROGRAM
            #pragma vertex vert_outline
            #pragma fragment frag_outline

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct a2v
            {
                float4 vertexOS : POSITION;
                float3 normal : NORMAL;
            };

            struct v2f
            {
                float4 vertexCS : SV_POSITION;
            };

            float _OutlineWidth;

            v2f vert_outline(a2v v)
            {
                v2f o;
                o.vertexCS = mul(UNITY_MATRIX_MVP, v.vertexOS);
                o.vertexCS += float4(normalize(TransformWorldToHClipDir(v.normal)) * _OutlineWidth * o.vertexCS.w, 0);

                return o;
            }

            float4 frag_outline(v2f i) : SV_Target
            {
                return float4(0, 0, 0, 1);
            }
            ENDHLSL

        }

        //// Shadow
        //UsePass "VertexLit/SHADOWCASTER"

        Pass
        {
            Name "ShadowCaster"
            Tags{ "LightMode" = "ShadowCaster" }

            HLSLPROGRAM

            #pragma vertex vert_shadow
            #pragma fragment frag_shadow
            #pragma target 3.0
            #include "UnityCG.cginc"

            struct v2f { 
                V2F_SHADOW_CASTER;
            };

            v2f vert_shadow(appdata_base v)
            {
                v2f o;
                TRANSFER_SHADOW_CASTER_NORMALOFFSET(o)
                return o;
            }

            float4 frag_shadow(v2f i) : SV_Target
            {
                SHADOW_CASTER_FRAGMENT(i)
            }
            ENDHLSL
        }
    }
}
