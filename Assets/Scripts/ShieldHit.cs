using System;
using UnityEngine;

public class ShieldHit : MonoBehaviour
{
    private static readonly int hitPoint = Shader.PropertyToID("_HitPoint");
    private static readonly int hitTime = Shader.PropertyToID("_HitTime");

    private MaterialPropertyBlock materialPropertyBlock;
    private MeshRenderer meshRenderer;

    private void OnValidate()
    {
        meshRenderer = GetComponent<MeshRenderer>();
    }

    private void Start()
    {
        materialPropertyBlock = new MaterialPropertyBlock();
        materialPropertyBlock.SetFloat(hitTime, -10);
        meshRenderer.SetPropertyBlock(materialPropertyBlock);
    }

    private void OnTriggerEnter(Collider other)
    {
        materialPropertyBlock.SetVector(hitPoint, other.transform.position);
        materialPropertyBlock.SetFloat(hitTime, Time.time);
        meshRenderer.SetPropertyBlock(materialPropertyBlock);
    }
}