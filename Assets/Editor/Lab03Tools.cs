using System;
using System.IO;
using System.Linq;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

/// <summary>Reproducible lab scene setup and real Unity camera captures.</summary>
public static class Lab03Tools
{
    const string GraphPath = "Assets/Shaders/Toon Shader.shadergraph";
    const string MaterialFolder = "Assets/Materials/Toon";
    const string Scene1 = "Assets/Scenes/Lab Scene 1.unity";
    const string Scene2 = "Assets/Scenes/Lab Scene 2.unity";
    const string Scene3 = "Assets/Scenes/Lab Scene 3.unity";
    static Shader toon;
    static Texture2D pattern;

    [MenuItem("Lab 03/Rebuild demonstration materials and scenes")]
    public static void Setup()
    {
        if (!Application.isBatchMode && !EditorSceneManager.SaveCurrentModifiedScenesIfUserWantsTo()) return;
        Directory.CreateDirectory(MaterialFolder);
        AssetDatabase.Refresh();
        toon = AssetDatabase.LoadAssetAtPath<Shader>(GraphPath);
        if (toon == null) throw new InvalidOperationException("Toon Shader graph did not import.");
        foreach (string texturePath in new[] { "Assets/Textures/Shadow 1.png", "Assets/Textures/Shadow 2.jpg" })
        {
            var importer = (TextureImporter)AssetImporter.GetAtPath(texturePath);
            importer.wrapMode = TextureWrapMode.Repeat;
            importer.sRGBTexture = false;
            importer.mipmapEnabled = true;
            importer.filterMode = FilterMode.Trilinear;
            importer.textureCompression = TextureImporterCompression.Uncompressed;
            importer.SaveAndReimport();
        }
        pattern = AssetDatabase.LoadAssetAtPath<Texture2D>("Assets/Textures/Shadow 1.png");

        var pipeline = AssetDatabase.LoadAssetAtPath<UniversalRenderPipelineAsset>("Assets/Render Settings/URP-Custom.asset");
        pipeline.shadowDistance = 25f;
        pipeline.shadowCascadeCount = 2;
        var pipelineSettings = new SerializedObject(pipeline);
        pipelineSettings.FindProperty("m_Cascade2Split").floatValue = 0.3f;
        pipelineSettings.ApplyModifiedPropertiesWithoutUndo();
        EditorUtility.SetDirty(pipeline);

        // Palette sampled from the Puzzle 1 reference screenshot.
        var sphere = MakeMaterial("P1 - Green sphere", "CCE5AF", "0E4F1F", "0E4F1F", false);
        sphere.SetFloat("_ShadowThreshold", 0.704f);
        var floor1 = MakeMaterial("P1 - Sand floor", "EED5A1", "EED5A1", "843106", false);
        EditorSceneManager.OpenScene(Scene1);
        GameObject.Find("Sphere").GetComponent<Renderer>().sharedMaterial = sphere;
        GameObject.Find("Plane").GetComponent<Renderer>().sharedMaterial = floor1;
        ConfigureCamera(new Vector3(0, 0.85f, 0), new Vector3(6, 4.4f, -0.35f), 1.65f);
        ConfigureLights();
        ConfigurePuzzle1ReferenceView();
        EditorSceneManager.SaveScene(EditorSceneManager.GetActiveScene());

        string[] names = { "Blue", "Skin", "White", "Red", "Gold", "Black" };
        string[,] colors = {
            { "71BFFF", "2865C4", "162B62" },
            { "FFE1AA", "DEA66D", "8B5050" },
            { "FFF7EB", "B8CBE2", "60648B" },
            { "FF776D", "D8344E", "6D2346" },
            { "FFF29A", "E8B648", "9C5F37" },
            { "626780", "30384E", "141A2C" }
        };
        var modelImporter = (ModelImporter)AssetImporter.GetAtPath("Assets/Models/Sonic Model.fbx");
        for (int i = 0; i < names.Length; i++)
        {
            var mat = MakeMaterial("P2 - Sonic " + names[i], colors[i, 0], colors[i, 1], colors[i, 2], true);
            modelImporter.AddRemap(new AssetImporter.SourceAssetIdentifier(typeof(Material), names[i]), mat);
        }
        modelImporter.SaveAndReimport();
        var floor2 = MakeMaterial("P2 - Warm floor", "F3E9D7", "C8B9BA", "706681", true);
        EditorSceneManager.OpenScene(Scene2);
        GameObject.Find("Plane").GetComponent<Renderer>().sharedMaterial = floor2;
        var renderers = UnityEngine.Object.FindObjectsOfType<Renderer>().Where(r => r.gameObject.name != "Plane").ToArray();
        if (renderers.Length == 0) throw new InvalidOperationException("Sonic renderers missing.");
        var bounds = renderers[0].bounds;
        foreach (var renderer in renderers)
        {
            bounds.Encapsulate(renderer.bounds);
            // The starter scene overrides several imported mesh materials.
            string fallback = renderer.name.Contains("HeadMain") || renderer.name.Contains("BodyOuter") ? "Blue"
                : renderer.name.Contains("Arm") || renderer.name.Contains("BodyInner") ? "Skin" : "White";
            renderer.sharedMaterials = renderer.sharedMaterials.Select(material =>
                material != null && material.shader == toon ? material
                : AssetDatabase.LoadAssetAtPath<Material>(MaterialFolder + "/P2 - Sonic " + fallback + ".mat")).ToArray();
        }
        Debug.Log("LAB03 Sonic bounds: " + bounds);
        foreach (var renderer in renderers)
            Debug.Log("LAB03 mesh: " + renderer.name + " materials: " + string.Join(", ", renderer.sharedMaterials.Select(m => m == null ? "MISSING" : m.name)));
        ConfigureCamera(bounds.center + Vector3.down * bounds.extents.y * 0.08f + Vector3.forward * 0.5f,
            new Vector3(7, 3.5f, -0.55f), Mathf.Max(1.5f, bounds.extents.y * 1.55f));
        ConfigureLights();
        EditorSceneManager.SaveScene(EditorSceneManager.GetActiveScene());

        // Separate scene and materials keep Puzzles 2 and 3 independently reviewable.
        // Only the ground receives the pattern. Sonic still receives ordinary
        // self-shadows, but its own shadowed surfaces must not turn into stripes.
        var patternReceiver = GameObject.Find("Plane").GetComponent<Renderer>();
        foreach (var renderer in UnityEngine.Object.FindObjectsOfType<Renderer>())
        {
            renderer.sharedMaterials = renderer.sharedMaterials.Select(source => {
                string assetPath = MaterialFolder + "/" + source.name.Replace("P2 -", "P3 -") + ".mat";
                var mat = AssetDatabase.LoadAssetAtPath<Material>(assetPath);
                if (mat == null) { mat = new Material(source); AssetDatabase.CreateAsset(mat, assetPath); }
                else mat.CopyPropertiesFromMaterial(source);
                mat.name = Path.GetFileNameWithoutExtension(assetPath);
                mat.SetFloat("_PatternStrength", renderer == patternReceiver ? 1 : 0);
                mat.SetFloat("_PatternScale", 3.5f);
                EditorUtility.SetDirty(mat);
                return mat;
            }).ToArray();
        }
        EditorSceneManager.SaveScene(EditorSceneManager.GetActiveScene(), Scene3);
        EditorBuildSettings.scenes = new[] { Scene1, Scene2, Scene3 }.Select(s => new EditorBuildSettingsScene(s, true)).ToArray();
        AssetDatabase.SaveAssets();
        EditorSceneManager.OpenScene(Scene1);
        Debug.Log("LAB03 SETUP COMPLETE");
    }

    static Material MakeMaterial(string name, string highlight, string midtone, string shadow, bool three)
    {
        string path = MaterialFolder + "/" + name + ".mat";
        var mat = AssetDatabase.LoadAssetAtPath<Material>(path);
        if (mat == null) { mat = new Material(toon); AssetDatabase.CreateAsset(mat, path); }
        mat.shader = toon;
        mat.SetColor("_Highlight", Hex(highlight));
        mat.SetColor("_Midtone", Hex(midtone));
        mat.SetColor("_Shadow", Hex(shadow));
        mat.SetFloat("_ThreeBands", three ? 1 : 0);
        mat.SetFloat("_ShadowThreshold", 0.32f);
        mat.SetFloat("_HighlightThreshold", 0.72f);
        mat.SetFloat("_Smoothness", 0);
        mat.SetFloat("_PatternStrength", 0);
        mat.SetFloat("_PatternScale", 3.5f);
        mat.SetTexture("_ShadowPattern", pattern);
        EditorUtility.SetDirty(mat);
        return mat;
    }

    static Color Hex(string rgb) { ColorUtility.TryParseHtmlString("#" + rgb, out var color); return color; }

    static void ConfigureCamera(Vector3 target, Vector3 offset, float size)
    {
        var camera = Camera.main;
        camera.transform.position = target + offset;
        camera.transform.LookAt(target);
        camera.orthographic = true;
        camera.orthographicSize = size;
        camera.nearClipPlane = 0.1f;
        camera.farClipPlane = 50;
        camera.clearFlags = CameraClearFlags.SolidColor;
        camera.backgroundColor = Hex("E5DFF4");
        camera.allowHDR = false;
        camera.allowMSAA = true;
        var data = camera.GetUniversalAdditionalCameraData();
        data.renderPostProcessing = false;
        data.renderShadows = true;
        GameObject.Find("Plane").transform.localScale = Vector3.one * 4;
        RenderSettings.fog = false;
    }

    static void ConfigureLights()
    {
        foreach (var light in UnityEngine.Object.FindObjectsOfType<Light>())
        {
            light.lightmapBakeType = LightmapBakeType.Realtime;
            if (light.type == LightType.Directional)
            {
                light.transform.rotation = Quaternion.Euler(50, -30, 0);
                light.shadows = LightShadows.Hard;
                light.shadowBias = 0.035f;
                light.shadowNormalBias = 0.15f;
                light.shadowStrength = 1;
            }
        }
    }

    static void ConfigurePuzzle1ReferenceView()
    {
        // Use the starter's perspective camera and match the reference's
        // upper-right highlight and compact lower-left cast shadow.
        var camera = Camera.main;
        camera.orthographic = false;
        camera.fieldOfView = 60;
        camera.transform.SetPositionAndRotation(new Vector3(3.493f, 2.477f, 0),
            new Quaternion(0.12718117f, -0.7039343f, 0.13040932f, 0.6865092f));
        camera.backgroundColor = Hex("EED5A1");
        GameObject.Find("Directional Light").transform.rotation =
            Quaternion.LookRotation(-new Vector3(0.52f, 0.766f, 0.31f), Vector3.up);
    }

    [MenuItem("Lab 03/Capture all result screenshots")]
    public static void CaptureAll()
    {
        if (!Application.isBatchMode && !EditorSceneManager.SaveCurrentModifiedScenesIfUserWantsTo()) return;
        Directory.CreateDirectory("Screenshots");
        string previous = EditorSceneManager.GetActiveScene().path;
        try
        {
            EditorSceneManager.OpenScene(Scene1);
            Capture("Screenshots/puzzle-1.png", 1440, 810);
            EditorSceneManager.OpenScene(Scene2);
            Capture("Screenshots/puzzle-2.png");
            EditorSceneManager.OpenScene(Scene3);
            Capture("Screenshots/puzzle-3.png");
            EditorSceneManager.OpenScene(Scene2);
            // Temporary material copies demonstrate smoothness without editing assets.
            var copies = new System.Collections.Generic.List<Material>();
            foreach (var renderer in UnityEngine.Object.FindObjectsOfType<Renderer>())
            {
                renderer.sharedMaterials = renderer.sharedMaterials.Select(source => {
                    var copy = new Material(source);
                    copy.SetFloat("_Smoothness", 0.22f);
                    copies.Add(copy);
                    return copy;
                }).ToArray();
            }
            Capture("Screenshots/extra-credit-smoothness.png");
            EditorSceneManager.OpenScene(string.IsNullOrEmpty(previous) ? Scene1 : previous);
            foreach (var copy in copies) UnityEngine.Object.DestroyImmediate(copy);
            CheckShaders();
            Debug.Log("LAB03 CAPTURES COMPLETE");
        }
        finally
        {
            if (EditorSceneManager.GetActiveScene().path != previous && !string.IsNullOrEmpty(previous))
                EditorSceneManager.OpenScene(previous);
        }
    }

    public static Color32[] Capture(string path = null, int width = 1440, int height = 1080)
    {
        var camera = Camera.main;
        var rt = new RenderTexture(width, height, 24, RenderTextureFormat.ARGB32, RenderTextureReadWrite.sRGB) { antiAliasing = 4 };
        var oldTarget = camera.targetTexture;
        var oldActive = RenderTexture.active;
        var image = new Texture2D(width, height, TextureFormat.RGB24, false);
        try
        {
            camera.targetTexture = rt;
            // Warm-up ensures the pipeline and imported shader variants are ready.
            camera.Render();
            camera.Render();
            RenderTexture.active = rt;
            image.ReadPixels(new Rect(0, 0, width, height), 0, 0);
            image.Apply();
            if (path != null)
            {
                File.WriteAllBytes(path, image.EncodeToPNG());
                Debug.Log("LAB03 CAPTURE " + path);
            }
            return image.GetPixels32();
        }
        finally
        {
            camera.targetTexture = oldTarget;
            RenderTexture.active = oldActive;
            rt.Release();
            UnityEngine.Object.DestroyImmediate(rt);
            UnityEngine.Object.DestroyImmediate(image);
        }
    }

    public static void SetupAndCapture() { Setup(); CaptureAll(); }

    public static void CheckShaders()
    {
        var shader = AssetDatabase.LoadAssetAtPath<Shader>(GraphPath);
        foreach (var message in ShaderUtil.GetShaderMessages(shader))
        {
            if (message.severity == UnityEditor.Rendering.ShaderCompilerMessageSeverity.Error)
                throw new InvalidOperationException("Shader error: " + message.message);
            Debug.Log("LAB03 shader message: " + message.message);
        }
        if (!shader.isSupported) throw new InvalidOperationException("Toon shader is unsupported on this GPU.");
        Debug.Log("LAB03 SHADER VALIDATION PASSED");
    }
}
