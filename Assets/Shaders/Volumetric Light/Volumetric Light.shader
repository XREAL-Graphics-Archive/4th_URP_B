Shader "VolumetricLight"
{
    Properties
    {
        // 정확히 이름이 _MainTex여야 Unity가 source render texture 자동으로 전달됨 
        _MainTex ("Texture", 2D) = "white"
    }
    SubShader
    {
        // No culling or depth
        Cull Off
        ZWrite Off
        ZTest Always

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile _  _MAIN_LIGHT_SHADOWS_CASCADE
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            // 아주 기본적인 기능만 한난 vertex shader
            struct appdata
            {
                real4 vertex : POSITION;
                real2 uv : TEXCOORD0;
            };

            struct v2f
            {
                real2 uv : TEXCOORD0;
                real4 vertex : SV_POSITION;
            };

            v2f vert(appdata v)
            {
                v2f o;
                o.vertex = TransformWorldToHClip(v.vertex);
                o.uv = v.uv;
                return o;
            }

            // 원본 렌더링
            sampler2D _MainTex;
            // ray marching용 변수들
            real _Scattering;
            real3 _SunDirection;
            real _Steps;
            real _JitterVolumetric;
            real _MaxDistance;

            // World space 좌표계의 특정 지점이 main light에 의한 그림자의 세기를 반환
            real SampleShadow(real3 worldPosition)
            {
                return MainLightRealtimeShadow(TransformWorldToShadowCoord(worldPosition));
            }

            // 원본 렌더링의 Depth texture상 값으로부터 World space 좌표를 재구성
            real3 GetWorldPos(real2 uv)
            {
                // 왼손 좌표계 오른손 좌표계 처리 용 조건부 컴파일
                #if UNITY_REVERSED_Z
                real depth = SampleSceneDepth(uv);
                #else
                real depth = lerp(UNITY_NEAR_CLIP_VALUE, 1, SampleSceneDepth(uv));
                #endif

                return ComputeWorldSpacePosition(uv, depth, UNITY_MATRIX_I_VP);
            }

            // Mie scattering approximated with Henyey-Greenstein phase function.
            // _Scattering 값이 -이면, 값이 빛 중심으로 진해지고, +면 값이 전체적으로 퍼짐
            real ComputeScattering(real lightDotView)
            {
                real result = 1.0f - _Scattering * _Scattering;
                result /= 4.0f * PI * pow(1.0f + _Scattering * _Scattering - 2.0f * _Scattering * lightDotView, 1.5f);
                return result;
            }

            // 쉐이더용 유사 랜덤 함수 (0~1)
            real random(real2 p)
            {
                return frac(sin(dot(p, real2(41, 289))) * 45758.5453);
            }

            //this implementation is loosely based on http://www.alexandre-pestana.com/volumetric-lights/ and https://fr.slideshare.net/BenjaminGlatzel/volumetric-lighting-for-many-lights-in-lords-of-the-fallen
            real frag(v2f i) : SV_Target
            {
                real3 world_pos = GetWorldPos(i.uv);

                // ray marching을 위한 ray 구성
                // 카메라로부터 ray 출발
                real3 start_position = _WorldSpaceCameraPos;
                // 각 pixel로 ray 발사
                real3 ray_vector = world_pos - start_position;
                real3 ray_direction = normalize(ray_vector);
                real ray_length = length(ray_vector);

                if (ray_length > _MaxDistance)
                {
                    ray_length = _MaxDistance;
                }

                // 광선의 구간을 쪼갠다
                real step_length = ray_length / _Steps;
                real3 step = ray_direction * step_length;

                // 광선이 너무 패턴화되서 구간의 경개선이 드러나지 않게 랜덤 offset부여 
                real ray_start_offset = random(i.uv) * step_length * _JitterVolumetric / 100;
                real3 current_position = start_position + ray_start_offset * ray_direction;

                real accum_fog = 0;
                for (real j = 0; j < _Steps - 1; j++)
                {
                    // 광선의 각 구간에서 그림자 값을 가져옮
                    real shadow_map_value = SampleShadow(current_position);

                    // 0 이상이면 빛 안에 있는 것 (완전히 그림자안에 있는 광선은 보이면 안됨)
                    [branch]
                    if (shadow_map_value > 0)
                    {
                        // Scattering을 통해 빛이 번져보이게
                        real kernel_color = ComputeScattering(dot(ray_direction, _SunDirection));
                        kernel_color = saturate(kernel_color);
                        accum_fog += kernel_color;
                    }
                    // 다음 구간
                    current_position += step;
                }

                // 각 구간별 평균을 구해서 픽셀에 반영
                return accum_fog / _Steps;
            }
            ENDHLSL
        }

        Pass
        {
            Name "Gaussian Blur"

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"


            struct appdata
            {
                real4 vertex : POSITION;
                real2 uv : TEXCOORD0;
            };

            struct v2f
            {
                real2 uv : TEXCOORD0;
                real4 vertex : SV_POSITION;
            };

            v2f vert(appdata v)
            {
                v2f o;
                o.vertex = TransformWorldToHClip(v.vertex);
                o.uv = v.uv;
                return o;
            }

            // ray marching 된 결과물
            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);

            // 가우스 가중치 (가운데 즉 인덱스가 0에 가까울 수록 높다)
            static const real gauss_filter_weights[] = {
                0.14446445, 0.13543542, 0.11153505, 0.08055309, 0.05087564, 0.02798160, 0.01332457, 0.00545096, 0, 0, 0,
                0, 0, 0, 0, 0, 0
            };

            #define BLUR_DEPTH_FALLOFF 100.0

            real frag(v2f i) : SV_Target
            {
                // 원본 렌더링의 Depth texture상 값을 가져옴
                // 왼손 좌표계 오른손 좌표계 처리 용 조건부 컴파일
                #if UNITY_REVERSED_Z
                real depth_center = SampleSceneDepth(i.uv);
                #else
                real depth_center = lerp(UNITY_NEAR_CLIP_VALUE, 1, SampleSceneDepth(i.uv));
                #endif

                const int2 x_axis = int2(1, 0);
                real accum_result = 0;
                real accum_weights = 0;
                // x축 양옆 5픽셀 샘플링
                const int number = 5;
                // 컴파일 할 때는 반복문을 펼쳐주는 기능
                UNITY_FLATTEN
                for (real index = -number; index <= number; index++)
                {
                    // 원본 렌더링의 Depth texture상 양옆 픽셀에서 Depth값을 가져옴
                    // 왼손 좌표계 오른손 좌표계 처리 용 조건부 컴파일
                    #if UNITY_REVERSED_Z
                    real depth_kernel = _CameraDepthTexture.SampleLevel(sampler_MainTex, i.uv, 0, x_axis * index);
                    #else
                    real depth_kernel = lerp(UNITY_NEAR_CLIP_VALUE, 1, _CameraDepthTexture.SampleLevel(sampler_MainTex, i.uv, 0, _Axis * index));
                    #endif

                    // 원본 Depth에서 양옆과의 차이를 이용해 blur 가중치 계산
                    // 가파른 Depth변화(물체간의 경계선)를 현실적으로 반영
                    real depth_diff = abs(depth_kernel - depth_center);
                    real r2 = depth_diff * BLUR_DEPTH_FALLOFF;
                    real g = exp(-r2 * r2);
                    real weight = g * gauss_filter_weights[abs(index)];

                    // Ray marching의 양옆 픽셀 결과를 가져옴
                    real kernel_sample = _MainTex.SampleLevel(sampler_MainTex, i.uv, 0, x_axis * index);
                    // blur 가중치 적용 및 누적
                    accum_result += weight * kernel_sample;
                    accum_weights += weight;
                }

                // 평균 반환
                return accum_result / accum_weights;
            }
            ENDHLSL
        }

        Pass
        {
            Name "Gaussian Blur 2"

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"


            struct appdata
            {
                real4 vertex : POSITION;
                real2 uv : TEXCOORD0;
            };

            struct v2f
            {
                real2 uv : TEXCOORD0;
                real4 vertex : SV_POSITION;
            };

            v2f vert(appdata v)
            {
                v2f o;
                o.vertex = TransformWorldToHClip(v.vertex);
                o.uv = v.uv;
                return o;
            }

            // ray marching에 x축 blur 적용된 결과물
            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);

            // 가우스 가중치 (가운데 즉 인덱스가 0에 가까울 수록 높다)
            static const real gauss_filter_weights[] = {
                0.14446445, 0.13543542, 0.11153505, 0.08055309, 0.05087564, 0.02798160, 0.01332457, 0.00545096, 0, 0, 0,
                0, 0, 0, 0, 0, 0
            };

            #define BLUR_DEPTH_FALLOFF 100.0

            real frag(v2f i) : SV_Target
            {
                // 원본 렌더링의 Depth texture상 값을 가져옴
                // 왼손 좌표계 오른손 좌표계 처리 용 조건부 컴파일
                #if UNITY_REVERSED_Z
                real depth_center = SampleSceneDepth(i.uv);
                #else
                real depth_center = lerp(UNITY_NEAR_CLIP_VALUE, 1, SampleSceneDepth(i.uv));
                #endif

                const int2 y_axis = int2(0, 1);
                real accum_result = 0;
                real accum_weights = 0;
                // y축 양옆 5픽셀 샘플링
                const int number = 5;
                // 컴파일 할 때는 반복문을 펼쳐주는 기능
                UNITY_FLATTEN
                for (real index = -number; index <= number; index++)
                {
                    // 원본 렌더링의 Depth texture상 양옆 픽셀에서 Depth값을 가져옴
                    // 왼손 좌표계 오른손 좌표계 처리 용 조건부 컴파일
                    #if UNITY_REVERSED_Z
                    real depth_kernel = _CameraDepthTexture.SampleLevel(sampler_MainTex, i.uv, 0, y_axis * index);
                    #else
                    real depth_kernel = lerp(UNITY_NEAR_CLIP_VALUE, 1, _CameraDepthTexture.SampleLevel(sampler_MainTex, i.uv, 0, _Axis * index));
                    #endif

                    // 원본 Depth에서 양옆과의 차이를 이용해 blur 가중치 계산
                    // 가파른 Depth변화(물체간의 경계선)를 현실적으로 반영
                    real depth_diff = abs(depth_kernel - depth_center);
                    real r2 = depth_diff * BLUR_DEPTH_FALLOFF;
                    real g = exp(-r2 * r2);
                    real weight = g * gauss_filter_weights[abs(index)];

                    // Ray marching의 양옆 픽셀 결과를 가져옴
                    real kernel_sample = _MainTex.SampleLevel(sampler_MainTex, i.uv, 0, y_axis * index);
                    // blur 가중치 적용 및 누적
                    accum_result += weight * kernel_sample;
                    accum_weights += weight;
                }

                // 평균 반환
                return accum_result / accum_weights;
            }
            ENDHLSL
        }

        Pass
        {
            Name "SampleDepth"

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

            struct appdata
            {
                real4 vertex : POSITION;
                real2 uv : TEXCOORD0;
            };

            struct v2f
            {
                real2 uv : TEXCOORD0;
                real4 vertex : SV_POSITION;
            };

            v2f vert(appdata v)
            {
                v2f o;
                o.vertex = TransformWorldToHClip(v.vertex);
                o.uv = v.uv;
                return o;
            }


            real frag(v2f i) : SV_Target
            {
                // 원본 렌더링의 Depth texture상 값을 가져옴
                // 왼손 좌표계 오른손 좌표계 처리 용 조건부 컴파일
                #if UNITY_REVERSED_Z
                real depth = SampleSceneDepth(i.uv);
                #else
                real depth = lerp(UNITY_NEAR_CLIP_VALUE, 1, SampleSceneDepth(i.uv));
                #endif
                return depth;
            }
            ENDHLSL
        }

        Pass
        {
            Name "Compositing"

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

            struct appdata
            {
                real4 vertex : POSITION;
                real2 uv : TEXCOORD0;
            };

            struct v2f
            {
                real2 uv : TEXCOORD0;
                real4 vertex : SV_POSITION;
            };

            v2f vert(appdata v)
            {
                v2f o;
                o.vertex = TransformWorldToHClip(v.vertex);
                o.uv = v.uv;
                return o;
            }

            // 원본 렌더링
            sampler2D _MainTex;
            // blur처리까지 완료된 ray marching
            TEXTURE2D(_VolumetricTexture);
            SAMPLER(sampler_VolumetricTexture);
            // 원본 렌더링의 저해상도 샘플링된 Depth
            TEXTURE2D(_LowResolutionDepthTexture);
            SAMPLER(sampler_LowResolutionDepthTexture);

            real4 _LightColor;
            real _Intensity;

            // 최종적으로 지금까지 pass들의 결과물을 종합하는 단계
            //based on https://eleni.mutantstargoat.com/hikiko/on-depth-aware-upsampling/ 
            real3 frag(v2f i) : SV_Target
            {
                // Ray marching과 해상도를 맞춘 depth texture를 써서 최종 결과물을 위해 해상도를 높일 때 최적의 선택을 함
                
                // 원본 렌더링의 픽셀 Depth값 가져옴
                real d0 = SampleSceneDepth(i.uv);
                // 일부로 ray marching이랑 해상도를 맞춘 원본 렌더링의 Depth Texture에서 상하좌우 Depth값을 가져옴
                real d1 = _LowResolutionDepthTexture.Sample(sampler_LowResolutionDepthTexture, i.uv, int2(0, 1)).x;
                real d2 = _LowResolutionDepthTexture.Sample(sampler_LowResolutionDepthTexture, i.uv, int2(0, -1)).x;
                real d3 = _LowResolutionDepthTexture.Sample(sampler_LowResolutionDepthTexture, i.uv, int2(1, 0)).x;
                real d4 = _LowResolutionDepthTexture.Sample(sampler_LowResolutionDepthTexture, i.uv, int2(-1, 0)).x;

                // 원본 렌더링과 비교
                d1 = abs(d0 - d1);
                d2 = abs(d0 - d2);
                d3 = abs(d0 - d3);
                d4 = abs(d0 - d4);

                // 차이가 가장 작은걸 선택, 가장자리를 부드럽게 하기 위한 목적
                real d_min = min(min(d1, d2), min(d3, d4));

                int offset = 0;
                if (d_min == d1) offset = 0;
                else if (d_min == d2) offset = 1;
                else if (d_min == d3) offset = 2;
                else if (d_min == d4) offset = 3;

                // 상하좌우 중 선택된거로 blur된 ray marching 샘플 
                real col;
                switch (offset)
                {
                case 0:
                    col = _VolumetricTexture.Sample(sampler_VolumetricTexture, i.uv, int2(0, 1));
                    break;
                case 1:
                    col = _VolumetricTexture.Sample(sampler_VolumetricTexture, i.uv, int2(0, -1));
                    break;
                case 2:
                    col = _VolumetricTexture.Sample(sampler_VolumetricTexture, i.uv, int2(1, 0));
                    break;
                case 3:
                    col = _VolumetricTexture.Sample(sampler_VolumetricTexture, i.uv, int2(-1, 0));
                    break;
                default:
                    col = _VolumetricTexture.Sample(sampler_VolumetricTexture, i.uv);
                    break;
                }

                // 최종적으로 ray marching의 결과물을 빛과 합쳐서 적용
                real3 final_shaft = col * _Intensity * _LightColor;
                return tex2D(_MainTex, i.uv) + final_shaft;
            }
            ENDHLSL
        }
    }
}