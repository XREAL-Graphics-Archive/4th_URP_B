using System;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

// 설정값을 가지고 Renderer가 실행할 Pass를 등록해준다 
public class VolumetricLightFeature : ScriptableRendererFeature
{
    // SRP에 쓰일 값들을 설정하는 용도
    // Pass에 넘겨져서 직접 쓰인다
    [Serializable]
    public class VolumetricLightSettings
    {
        public bool enableVolumetricLighting;

        public enum DownSample
        {
            off = 1,
            half = 2,
            third = 3,
            quarter = 4
        }

        // 성능을 위한 옵션. 값이 높을수록 성능은 좋아지나, Volumetric light 효과 품질이 낮아진다.
        public DownSample downSampling;

        public float samples;

        public float intensity = 1;

        [Range(-1, 1)] public float scattering;

        public float maxDistance;
        public float jitter = 1;

        public Material material;
        public RenderPassEvent renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing;
    }

    public VolumetricLightSettings volumetricLightSettings = new();

    // 실질적으로 SRP를 실행시켜주는 주체
    private VolumetricLightPass pass;

    // material property설정용 id cache
    private static readonly int Scattering = Shader.PropertyToID("_Scattering");
    private static readonly int Steps = Shader.PropertyToID("_Steps");
    private static readonly int JitterVolumetric = Shader.PropertyToID("_JitterVolumetric");
    private static readonly int MaxDistance = Shader.PropertyToID("_MaxDistance");
    private static readonly int Intensity = Shader.PropertyToID("_Intensity");

    // Pass를 생성하고 초기화하기 위해 URP에서 호출하는 함수
    public override void Create()
    {
        pass = new VolumetricLightPass();
        name = "Volumetric Light";

        pass.settings = volumetricLightSettings;
        pass.renderPassEvent = volumetricLightSettings.renderPassEvent;
    }

    // Renderer Feature에서 자율적으로 Pass를 등록하도록 URP에서 호출하는 함수
    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        try
        {
            if (!volumetricLightSettings.enableVolumetricLighting)
                return;
            if (renderingData.cameraData.cameraType == CameraType.Game ||
                renderingData.cameraData.cameraType == CameraType.SceneView)
            {
                var cameraColorTargetIdent = renderer.cameraColorTarget;
                pass.Setup(cameraColorTargetIdent);
                // 이제 Renderer에서 Pass를 실행해준다
                renderer.EnqueuePass(pass);
            }
        }
        catch (Exception e)
        {
            Debug.LogError(e);
        }
    }

    // Renderer가 실행하는 동작이 정의되고 실행되는 일종의 단위
    class VolumetricLightPass : ScriptableRenderPass
    {
        // Renderer feature가 넘겨준 설정값들
        public VolumetricLightSettings settings;
        private RenderTargetIdentifier source;
        private RenderTargetHandle tempTexture;
        private RenderTargetHandle lowResolutionDepthTexture;
        private RenderTargetHandle upsampleTexture;

        public VolumetricLightPass()
        {
            profilingSampler = new ProfilingSampler("Volumetric Lighting");
        }

        // 본격적으로 Renderer에 넘어가기 전에 설정
        public void Setup(RenderTargetIdentifier source)
        {
            this.source = source;
        }

        // Renderer에서 Rendering하기 전에 준비 설정을 위해 호출될 함수
        // CommandBuffer: Renderer에 내릴 명령을 저장
        // RenderTextureDescriptor: 현재 메인 카메라 출력 Texture 형식 정보 보유
        public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraTextureDescriptor)
        {
            var downSampleTextureDescriptor = cameraTextureDescriptor;
            int divider = (int)settings.downSampling;

            // Render Texture를 쓰는것 자체가 성능을 많이 잡아먹으므로
            // 낮은 해상도로 설정해서 절약. 대신 효과 품질도 떨어짐
            if (Camera.current != null)
            {
                // Scene View에서는 해상도가 다르므로 조정
                var pixelRect = Camera.current.pixelRect;
                cameraTextureDescriptor.width = (int)pixelRect.width;
                cameraTextureDescriptor.height = (int)pixelRect.height;

                downSampleTextureDescriptor.width = cameraTextureDescriptor.width / divider;
                downSampleTextureDescriptor.height = cameraTextureDescriptor.height / divider;
            }
            else
            {
                // 정상 Game Window
                downSampleTextureDescriptor.width /= divider;
                downSampleTextureDescriptor.height /= divider;
            }

            // Depth Texture만 가져올 것이기 때문에 Red채널만 사용하여 절약
            downSampleTextureDescriptor.colorFormat = RenderTextureFormat.R16;
            // 이 Texture 자체가 Depth Texture기 때문에 추가로 Depth bit를 만들 필요는 없다
            downSampleTextureDescriptor.depthBufferBits = 0;
            // 이미 anti-aliasing이 적용된 결과물을 가져오므로 켤 필요가 없다
            downSampleTextureDescriptor.msaaSamples = 1;
            // 서로 다른 id 부여
            lowResolutionDepthTexture.id = 1;
            upsampleTexture.id = 2;

            // Render Texture 요청 명령
            cmd.GetTemporaryRT(tempTexture.id, downSampleTextureDescriptor);
            cmd.GetTemporaryRT(lowResolutionDepthTexture.id, downSampleTextureDescriptor);
            cmd.GetTemporaryRT(upsampleTexture.id, cameraTextureDescriptor);
        }

        // 본격적인 Pass의 그리기 실행
        // ScriptableRenderContext: 현재 진행중인 Rendering에서 외부 graphics Api와의 연결점
        // RenderingData: 현재 진행중인 Rendering 관련 정보
        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            var camera = renderingData.cameraData.camera;
            if (camera.cameraType is not (CameraType.Game or CameraType.SceneView))
                return;

            // 이번에는 자율적으로 CommandBuffer를 가져옴
            var cmd = CommandBufferPool.Get();

            // 디버깅용
            using (new ProfilingScope(cmd, profilingSampler))
            {
                // Try/Catch 블럭으로 무슨일이 있어도 CommandBufferPool.Release(cmd)를 실행할 수 있게
                // graphics Api는 외부이기 때문에 어떤 memory leak이 일어날지 알 수 없음
                try
                {
                    // Material property들 설정
                    settings.material.SetFloat(Scattering, settings.scattering);
                    settings.material.SetFloat(Steps, settings.samples);
                    settings.material.SetFloat(JitterVolumetric, settings.jitter);
                    settings.material.SetFloat(MaxDistance, settings.maxDistance);
                    settings.material.SetFloat(Intensity, settings.intensity);

                    // 원본에서 Shader pass 0번(Ray marching)을 적용하면서 복사 
                    cmd.Blit(source, tempTexture.Identifier(), settings.material, 0);

                    // 이전까지의 결과물에서 Shader pass 1번(blur X축)을 적용하면서 복사 
                    cmd.Blit(tempTexture.Identifier(), lowResolutionDepthTexture.Identifier(),
                        settings.material, 1);

                    // 이전까지의 결과물에서 Shader pass 2번(blur Y축)을 적용하면서 복사 
                    cmd.Blit(lowResolutionDepthTexture.Identifier(), tempTexture.Identifier(),
                        settings.material, 2);

                    // 원본에서 Shader pass 3번(Sample Depth)을 적용하면서 복사
                    cmd.Blit(source, lowResolutionDepthTexture.Identifier(), settings.material, 3);

                    // Shader에서 쓸 수 있게 Texture와 property 연결
                    cmd.SetGlobalTexture("_VolumetricTexture", tempTexture.Identifier());
                    cmd.SetGlobalTexture("_LowResolutionDepthTexture", lowResolutionDepthTexture.Identifier());

                    // 이전까지의 결과물에서 Shader pass 4번(Composition)을 적용하면서 복사 
                    cmd.Blit(source, upsampleTexture.Identifier(), settings.material, 4);

                    // 최종 결과물을 다시 원본에 덮어씌움
                    cmd.Blit(upsampleTexture.Identifier(), source);

                    // ~라는 명령들을 실행 요청
                    context.ExecuteCommandBuffer(cmd);
                }
                catch (Exception e)
                {
                    Debug.LogError($"Command execution failed! {e}");
                }

                // 메모리 마무리
                cmd.Clear();
                CommandBufferPool.Release(cmd);
            }
        }
    }
}