using UnityEngine;

public class ShieldHit : MonoBehaviour
{
    private static readonly int hitPoint = Shader.PropertyToID("_HitPoint");
    private static readonly int hitTime = Shader.PropertyToID("_HitTime");

    private MaterialPropertyBlock materialPropertyBlock;//Object마다 다른 property를 적용해 줄 수 있게 함.
    private MeshRenderer meshRenderer;

    private void OnValidate()
    {
        meshRenderer = GetComponent<MeshRenderer>();
    }

    private void Start()
    {
        materialPropertyBlock = new MaterialPropertyBlock();
        materialPropertyBlock.SetFloat(hitTime, -10);//시작하자마자 파동이 생기지 않게.
        meshRenderer.SetPropertyBlock(materialPropertyBlock);
    }

    private void OnTriggerEnter(Collider other)
    {
        materialPropertyBlock.SetVector(hitPoint, other.transform.position);
        materialPropertyBlock.SetFloat(hitTime, Time.time);
        meshRenderer.SetPropertyBlock(materialPropertyBlock);//값이 바뀔 때 마다 호출해야함.
    }
}