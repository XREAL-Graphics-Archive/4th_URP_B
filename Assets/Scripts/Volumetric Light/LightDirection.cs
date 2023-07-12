using UnityEngine;

[ExecuteAlways]
public class LightDirection : MonoBehaviour
{
    [SerializeField] private new Light light;
    private static readonly int sunDirection = Shader.PropertyToID("_SunDirection");
    private static readonly int lightColor = Shader.PropertyToID("_LightColor");

    void Start()
    {
        Shader.SetGlobalVector(sunDirection, transform.forward);
        Shader.SetGlobalVector(lightColor, light.color);
    }

    private void Update()
    {
        // material 연결 없이 그냥 전역으로 설정
        Shader.SetGlobalVector(sunDirection, transform.forward);
        Shader.SetGlobalVector(lightColor, light.color);
    }
}