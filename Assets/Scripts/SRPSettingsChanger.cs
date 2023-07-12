using UnityEngine;
using UnityEngine.Rendering;

public class SRPSettingsChanger : MonoBehaviour
{
    [SerializeField] private RenderPipelineAsset newSettings;

    private void Start()
    {
        GraphicsSettings.defaultRenderPipeline = newSettings;
        QualitySettings.renderPipeline = newSettings;
    }
}