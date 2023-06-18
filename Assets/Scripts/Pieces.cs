using UnityEngine;

public class Pieces : MonoBehaviour
{
    public OVRInput.Button scrollButton;
    public OVRHand.HandFinger scrollPinch;
    public OVRHand leftHand;
    public OVRHand rightHand;

    public GameObject[] pieces;
    public float radius;
    public float height;
    public float sensitivity;
    public float pieceScale;

    private float angle;
    private bool left;
    private bool prevScroll;
    private float pivot;

    private void Start()
    {
        var interval = 360 / pieces.Length;
        for (var i = 0; i < pieces.Length; i++)
        {
            pieces[i].transform.localScale = new Vector3(pieceScale, pieceScale, pieceScale);
            var pos = Quaternion.Euler(0, interval * i % 360, 0) * new Vector3(radius, height, 0);
            pieces[i].transform.position = pos;
        }
    }

    private void Update()
    {
        float yAngle;
        if (!ShouldScroll())
        {
            yAngle = (left ? leftHand : rightHand).transform.eulerAngles.y;
            prevScroll = false;
            pivot = yAngle;
            return;
        }

        yAngle = (left ? leftHand : rightHand).transform.eulerAngles.y;
        angle = (angle + yAngle - pivot) % 360;

        var interval = 360 / pieces.Length;
        for (var i = 0; i < pieces.Length; i++)
        {
            var pos = Quaternion.Euler(0, (angle * sensitivity + interval * i) % 360, 0) *
                      new Vector3(radius, height, 0);
            pieces[i].transform.position = pos;
        }

        prevScroll = true;
        pivot = yAngle;
    }

    private bool ShouldScroll()
    {
        if (OVRInput.Get(scrollButton, OVRInput.Controller.LTouch) || leftHand.GetFingerIsPinching(scrollPinch))
        {
            left = true;
            return true;
        }

        if (OVRInput.Get(scrollButton, OVRInput.Controller.RTouch) || rightHand.GetFingerIsPinching(scrollPinch))
        {
            left = false;
            return true;
        }

        return false;
    }
}