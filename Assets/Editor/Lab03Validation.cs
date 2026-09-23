using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.Rendering;

/// <summary>Image-based integration checks against the real URP renderer.</summary>
public static class Lab03Validation
{
    static readonly List<Material> temporaryMaterials = new List<Material>();
    static readonly List<string> results = new List<string>();

    [MenuItem("Lab 03/Validate rendering controls")]
    public static void Run()
    {
        if (!Application.isBatchMode && !EditorSceneManager.SaveCurrentModifiedScenesIfUserWantsTo()) return;
        string previous = EditorSceneManager.GetActiveScene().path;
        results.Clear();
        try
        {
            EditorSceneManager.OpenScene("Assets/Scenes/Lab Scene 1.unity");
            var baseline = Lab03Tools.Capture();
            var point = UnityEngine.Object.FindObjectsOfType<Light>().First(l => l.type == LightType.Point);
            point.enabled = false;
            var noPoint = Lab03Tools.Capture();
            MustChange("Additional point light contributes", baseline, noPoint);
            var sun = UnityEngine.Object.FindObjectsOfType<Light>().First(l => l.type == LightType.Directional);
            sun.shadows = LightShadows.None;
            MustChange("Main light casts a received shadow", noPoint, Lab03Tools.Capture());

            EditorSceneManager.OpenScene("Assets/Scenes/Lab Scene 2.unity");
            CloneMaterials();
            baseline = Lab03Tools.Capture();
            Set("_ThreeBands", 0);
            MustChange("Third band is visible", baseline, Lab03Tools.Capture());
            Set("_ThreeBands", 1);
            Set("_ShadowThreshold", 0.1f);
            Set("_HighlightThreshold", 0.4f);
            MustChange("Threshold controls move the bands", baseline, Lab03Tools.Capture());
            Set("_ShadowThreshold", 0.32f);
            Set("_HighlightThreshold", 0.72f);
            Set("_Smoothness", 0.22f);
            MustChange("Smoothness softens the bands", baseline, Lab03Tools.Capture());

            EditorSceneManager.OpenScene("Assets/Scenes/Lab Scene 3.unity");
            CloneMaterials();
            ValidateSonicShadowReceiver();
            baseline = Lab03Tools.Capture();
            Set("_PatternStrength", 0);
            MustChange("Pattern appears in cast shadows", baseline, Lab03Tools.Capture());
            foreach (var light in UnityEngine.Object.FindObjectsOfType<Light>()) light.shadows = LightShadows.None;
            var noShadowNoPattern = Lab03Tools.Capture();
            // Deliberately probe every material here: without occlusion the shader
            // must ignore the pattern even on a receiver where it is enabled.
            Set("_PatternStrength", 1);
            int leaked = Difference(noShadowNoPattern, Lab03Tools.Capture());
            if (leaked > 10) throw new InvalidOperationException("Pattern leaks outside cast shadows: " + leaked + " pixels.");
            results.Add("PASS: Pattern absent without occlusion (" + leaked + " changed pixels)");
            Lab03Tools.CheckShaders();
            results.Add("PASS: Shader compiled and supported by GPU");
            Directory.CreateDirectory("Library/Lab03Validation");
            File.WriteAllLines("Library/Lab03Validation/results.txt", results);
            foreach (string result in results) Debug.Log("LAB03 " + result);
            Debug.Log("LAB03 ALL RENDER CHECKS PASSED");
        }
        finally
        {
            EditorSceneManager.OpenScene(string.IsNullOrEmpty(previous) ? "Assets/Scenes/Lab Scene 1.unity" : previous);
            foreach (var material in temporaryMaterials) UnityEngine.Object.DestroyImmediate(material);
            temporaryMaterials.Clear();
        }
    }

    static void ValidateSonicShadowReceiver()
    {
        var plane = GameObject.Find("Plane").GetComponent<Renderer>();
        var originalPlaneMode = plane.shadowCastingMode;
        var lights = UnityEngine.Object.FindObjectsOfType<Light>();
        var shadowModes = lights.ToDictionary(light => light, light => light.shadows);
        var strengths = UnityEngine.Object.FindObjectsOfType<Renderer>()
            .SelectMany(renderer => renderer.sharedMaterials).Distinct()
            .ToDictionary(material => material, material => material.GetFloat("_PatternStrength"));
        try
        {
            // Hide the receiving floor from the image while preserving any shadow
            // it casts. Differences in these captures therefore belong to Sonic.
            plane.shadowCastingMode = ShadowCastingMode.ShadowsOnly;
            var savedSettings = Lab03Tools.Capture();
            Set("_PatternStrength", 0);
            var noPattern = Lab03Tools.Capture();
            int leaked = Difference(savedSettings, noPattern);
            if (leaked > 10)
                throw new InvalidOperationException("Pattern appears on Sonic: " + leaked + " pixels.");
            results.Add("PASS: Pattern absent on Sonic (" + leaked + " changed pixels)");

            foreach (var light in lights) light.shadows = LightShadows.None;
            MustChange("Sonic retains ordinary self-shadowing", noPattern, Lab03Tools.Capture());
        }
        finally
        {
            plane.shadowCastingMode = originalPlaneMode;
            foreach (var entry in shadowModes) entry.Key.shadows = entry.Value;
            foreach (var entry in strengths) entry.Key.SetFloat("_PatternStrength", entry.Value);
        }
    }

    static void CloneMaterials()
    {
        foreach (var renderer in UnityEngine.Object.FindObjectsOfType<Renderer>())
            renderer.sharedMaterials = renderer.sharedMaterials.Select(source => {
                var copy = new Material(source);
                temporaryMaterials.Add(copy);
                return copy;
            }).ToArray();
    }

    static void Set(string property, float value)
    {
        foreach (var renderer in UnityEngine.Object.FindObjectsOfType<Renderer>())
            foreach (var material in renderer.sharedMaterials) material.SetFloat(property, value);
    }

    static int Difference(Color32[] a, Color32[] b)
    {
        int changed = 0;
        for (int i = 0; i < a.Length; i++)
            if (Math.Abs(a[i].r - b[i].r) + Math.Abs(a[i].g - b[i].g) + Math.Abs(a[i].b - b[i].b) > 6) changed++;
        return changed;
    }

    static void MustChange(string label, Color32[] a, Color32[] b)
    {
        int changed = Difference(a, b);
        if (changed < 100) throw new InvalidOperationException(label + ": only " + changed + " changed pixels.");
        results.Add("PASS: " + label + " (" + changed + " changed pixels)");
    }
}
