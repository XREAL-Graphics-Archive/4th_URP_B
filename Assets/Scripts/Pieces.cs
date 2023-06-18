using UnityEngine;

public class Pieces : MonoBehaviour
{
    public GameObject[] pieces;
    public float radius;
    public float initialAngle;
    public float angularSpeed;
    public float pieceScale;

    private float elapsed;

    private void Awake()
    {
        enabled = pieces != null;
    }

    private void Start()
    {
        for (var i = 0; i < pieces.Length; i++)
            pieces[i].transform.localScale = new Vector3(pieceScale, pieceScale, pieceScale);
    }

    private void Update()
    {
        var interval = 360 / pieces.Length;

        for (var i = 0; i < pieces.Length; i++)
        {
            var angle = (initialAngle + angularSpeed * elapsed + interval * i) % 360;
            var pos = Quaternion.Euler(0, angle, 0) * new Vector3(radius, 0, 0);
            pieces[i].transform.position = pos;
        }

        elapsed += Time.deltaTime;
    }
}