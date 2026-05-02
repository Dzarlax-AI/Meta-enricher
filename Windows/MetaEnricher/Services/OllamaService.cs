using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Runtime.InteropServices.WindowsRuntime;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using MetaEnricher.Models;
using Windows.Graphics.Imaging;
using Windows.Storage;
using Windows.Storage.Streams;

namespace MetaEnricher.Services;

public record PullProgress(string Status, long Total, long Completed)
{
    public double Fraction => Total > 0 ? (double)Completed / Total : -1;
    public bool IsDone => Status == "success";
}

public class OllamaService
{
    private static OllamaService? _instance;
    public static OllamaService Instance => _instance ??= new OllamaService();

    private readonly HttpClient _http;

    public OllamaService()
    {
        _http = new HttpClient { Timeout = TimeSpan.FromSeconds(300) };
        _http.DefaultRequestHeaders.Add("User-Agent", "MetaEnricher/1.0");
    }

    public async Task<bool> CheckOllamaAsync(string baseUrl)
    {
        try
        {
            var resp = await _http.GetAsync($"{baseUrl.TrimEnd('/')}/api/tags");
            return resp.IsSuccessStatusCode;
        }
        catch { return false; }
    }

    public async Task<List<string>> ListModelsAsync(string baseUrl)
    {
        try
        {
            var resp = await _http.GetStringAsync($"{baseUrl.TrimEnd('/')}/api/tags");
            using var doc = JsonDocument.Parse(resp);
            var models = new List<string>();
            if (doc.RootElement.TryGetProperty("models", out var arr))
            {
                foreach (var m in arr.EnumerateArray())
                {
                    if (m.TryGetProperty("name", out var name))
                        models.Add(name.GetString() ?? "");
                }
            }
            models.Sort();
            return models;
        }
        catch { return new List<string>(); }
    }

    public async Task PullModelAsync(string name, string baseUrl, IProgress<PullProgress> progress)
    {
        var body = JsonSerializer.Serialize(new { name, stream = true });
        var content = new StringContent(body, Encoding.UTF8, "application/json");

        using var resp = await _http.PostAsync($"{baseUrl.TrimEnd('/')}/api/pull", content);
        resp.EnsureSuccessStatusCode();

        using var stream = await resp.Content.ReadAsStreamAsync();
        using var reader = new StreamReader(stream);

        while (!reader.EndOfStream)
        {
            var line = await reader.ReadLineAsync();
            if (string.IsNullOrWhiteSpace(line)) continue;
            try
            {
                using var doc = JsonDocument.Parse(line);
                var status = doc.RootElement.TryGetProperty("status", out var s) ? s.GetString() ?? "" : "";
                long total = doc.RootElement.TryGetProperty("total", out var t) ? t.GetInt64() : 0;
                long completed = doc.RootElement.TryGetProperty("completed", out var c) ? c.GetInt64() : 0;
                progress.Report(new PullProgress(status, total, completed));
                if (status == "success") break;
            }
            catch { }
        }
    }

    public async Task<PhotoMeta> EnrichPhotoAsync(
        string imagePath,
        string baseUrl,
        string model,
        string sessionNotes,
        PhotoMeta existingMeta,
        HashSet<EnrichField> fields)
    {
        // Resize and encode image
        var imageBytes = await ResizeAndEncodeAsync(imagePath, 1280);
        var base64 = Convert.ToBase64String(imageBytes);

        // Build prompt
        var prompt = BuildPrompt(sessionNotes, existingMeta, fields);

        // Call Ollama
        var requestBody = new
        {
            model,
            prompt,
            images = new[] { base64 },
            stream = false,
            format = "json",
            options = new { think = false }
        };

        var json = JsonSerializer.Serialize(requestBody);
        var httpContent = new StringContent(json, Encoding.UTF8, "application/json");

        using var cts = new System.Threading.CancellationTokenSource(TimeSpan.FromSeconds(120));
        var resp = await _http.PostAsync($"{baseUrl.TrimEnd('/')}/api/generate", httpContent, cts.Token);
        resp.EnsureSuccessStatusCode();

        var responseText = await resp.Content.ReadAsStringAsync();
        using var doc = JsonDocument.Parse(responseText);
        var responseContent = doc.RootElement.TryGetProperty("response", out var r) ? r.GetString() ?? "" : "";

        return ParseResponse(responseContent, existingMeta, fields);
    }

    private string BuildPrompt(string sessionNotes, PhotoMeta existingMeta, HashSet<EnrichField> fields)
    {
        var sb = new StringBuilder();
        sb.AppendLine("Analyze this photo and respond ONLY with a JSON object (no markdown fences, no extra text).");

        if (!string.IsNullOrWhiteSpace(sessionNotes))
            sb.AppendLine($"Context: {sessionNotes}");

        // Include existing metadata for fields NOT being regenerated
        var contextParts = new List<string>();
        if (!fields.Contains(EnrichField.Title) && existingMeta.Title != null)
            contextParts.Add($"existing title: \"{existingMeta.Title}\"");
        if (!fields.Contains(EnrichField.Description) && existingMeta.Description != null)
            contextParts.Add($"existing description: \"{existingMeta.Description}\"");
        if (!fields.Contains(EnrichField.Keywords) && existingMeta.Keywords.Count > 0)
            contextParts.Add($"existing keywords: {string.Join(", ", existingMeta.Keywords)}");
        if (!fields.Contains(EnrichField.Location) && existingMeta.Location != null)
            contextParts.Add($"existing location: \"{existingMeta.Location}\"");

        if (contextParts.Count > 0)
            sb.AppendLine($"Known metadata — {string.Join("; ", contextParts)}");

        sb.AppendLine();
        sb.AppendLine("Respond with exactly this structure:");
        sb.AppendLine("{ \"title\": \"...\", \"description\": \"...\", \"keywords\": [...], \"city\": \"...\", \"country\": \"...\" }");
        sb.AppendLine();
        sb.AppendLine("Rules:");
        sb.AppendLine("- title: concise, evocative, max 80 chars");
        sb.AppendLine("- description: describe subject, mood, composition");
        sb.AppendLine("- keywords: 5-10 relevant tags as JSON array");
        sb.AppendLine("- city/country: best guess from visual cues, null if uncertain");

        return sb.ToString();
    }

    private PhotoMeta ParseResponse(string responseText, PhotoMeta existingMeta, HashSet<EnrichField> fields)
    {
        // Strip <think>...</think> blocks
        responseText = Regex.Replace(responseText, @"<think>.*?</think>", "", RegexOptions.Singleline);

        // Strip markdown fences
        responseText = Regex.Replace(responseText, @"```[a-z]*\n?", "");

        // Extract {} bounds
        var start = responseText.IndexOf('{');
        var end = responseText.LastIndexOf('}');
        if (start >= 0 && end > start)
            responseText = responseText[start..(end + 1)];

        var meta = new PhotoMeta
        {
            Title = existingMeta.Title,
            Description = existingMeta.Description,
            Keywords = new List<string>(existingMeta.Keywords),
            Location = existingMeta.Location,
            LocationSource = existingMeta.LocationSource,
            DateTimeOriginal = existingMeta.DateTimeOriginal,
            Make = existingMeta.Make,
            Model = existingMeta.Model,
            FocalLength = existingMeta.FocalLength,
            Aperture = existingMeta.Aperture,
            ShutterSpeed = existingMeta.ShutterSpeed,
            Iso = existingMeta.Iso,
            Rating = existingMeta.Rating,
            Creator = existingMeta.Creator,
            Copyright = existingMeta.Copyright,
            GpsLat = existingMeta.GpsLat,
            GpsLon = existingMeta.GpsLon,
        };

        try
        {
            using var doc = JsonDocument.Parse(responseText);
            var root = doc.RootElement;

            if (fields.Contains(EnrichField.Title) && root.TryGetProperty("title", out var title))
                meta.Title = NullIfEmpty(title.GetString());

            if (fields.Contains(EnrichField.Description) && root.TryGetProperty("description", out var desc))
                meta.Description = NullIfEmpty(desc.GetString());

            if (fields.Contains(EnrichField.Keywords) && root.TryGetProperty("keywords", out var kws))
            {
                meta.Keywords = new List<string>();
                foreach (var kw in kws.EnumerateArray())
                {
                    var s = kw.GetString();
                    if (!string.IsNullOrWhiteSpace(s))
                        meta.Keywords.Add(s);
                }
            }

            if (fields.Contains(EnrichField.Location))
            {
                string? city = null, country = null;
                if (root.TryGetProperty("city", out var c) && c.ValueKind != JsonValueKind.Null)
                    city = c.GetString();
                if (root.TryGetProperty("country", out var co) && co.ValueKind != JsonValueKind.Null)
                    country = co.GetString();

                var parts = new List<string>();
                if (!string.IsNullOrWhiteSpace(city)) parts.Add(city!);
                if (!string.IsNullOrWhiteSpace(country)) parts.Add(country!);
                if (parts.Count > 0)
                {
                    meta.Location = string.Join(", ", parts);
                    meta.LocationSource = "ai";
                }
            }
        }
        catch { }

        return meta;
    }

    private static string? NullIfEmpty(string? s) =>
        string.IsNullOrWhiteSpace(s) ? null : s;

    private static async Task<byte[]> ResizeAndEncodeAsync(string filePath, int maxSize)
    {
        try
        {
            var file = await StorageFile.GetFileFromPathAsync(filePath);
            using var stream = await file.OpenReadAsync();
            var decoder = await BitmapDecoder.CreateAsync(stream);

            uint origW = decoder.PixelWidth;
            uint origH = decoder.PixelHeight;

            double scale = Math.Min((double)maxSize / origW, (double)maxSize / origH);
            if (scale > 1) scale = 1;

            uint newW = (uint)(origW * scale);
            uint newH = (uint)(origH * scale);

            var transform = new BitmapTransform
            {
                ScaledWidth = newW,
                ScaledHeight = newH,
                InterpolationMode = BitmapInterpolationMode.Fant
            };

            var bitmapData = await decoder.GetSoftwareBitmapAsync(
                BitmapPixelFormat.Bgra8,
                BitmapAlphaMode.Premultiplied,
                transform,
                ExifOrientationMode.RespectExifOrientation,
                ColorManagementMode.ColorManageToSRgb);

            var outStream = new InMemoryRandomAccessStream();
            // Set JPEG quality to 85%
            var propertySet = new BitmapPropertySet();
            propertySet.Add("ImageQuality", new BitmapTypedValue(0.85, Windows.Foundation.PropertyType.Single));
            var encoder = await BitmapEncoder.CreateAsync(BitmapEncoder.JpegEncoderId, outStream, propertySet);
            encoder.SetSoftwareBitmap(bitmapData);
            await encoder.FlushAsync();

            outStream.Seek(0);
            var bytes = new byte[outStream.Size];
            await outStream.ReadAsync(bytes.AsBuffer(), (uint)outStream.Size, InputStreamOptions.None);
            return bytes;
        }
        catch
        {
            // Fallback: read raw file bytes
            return await File.ReadAllBytesAsync(filePath);
        }
    }
}
