using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using MetaEnricher.Models;
using MetadataExtractor;
using MetadataExtractor.Formats.Exif;
using MetadataExtractor.Formats.Iptc;
using MetadataExtractor.Formats.Xmp;

namespace MetaEnricher.Services;

public class ExifService
{
    private static ExifService? _instance;
    public static ExifService Instance => _instance ??= new ExifService();

    public async Task<PhotoMeta> ReadMetaAsync(string filePath)
    {
        return await Task.Run(() =>
        {
            var meta = new PhotoMeta();
            try
            {
                var directories = ImageMetadataReader.ReadMetadata(filePath);

                // ExifIfd0
                var exif0 = directories.OfType<ExifIfd0Directory>().FirstOrDefault();
                if (exif0 != null)
                {
                    meta.Make = exif0.GetString(ExifDirectoryBase.TagMake);
                    meta.Model = exif0.GetString(ExifDirectoryBase.TagModel);
                    meta.Creator = exif0.GetString(ExifDirectoryBase.TagArtist);
                    meta.Copyright = exif0.GetString(ExifDirectoryBase.TagCopyright);
                }

                // ExifSubIfd
                var exifSub = directories.OfType<ExifSubIfdDirectory>().FirstOrDefault();
                if (exifSub != null)
                {
                    meta.DateTimeOriginal = exifSub.GetString(ExifDirectoryBase.TagDateTimeOriginal);
                    if (exifSub.TryGetRational(ExifDirectoryBase.TagFNumber, out var fnum))
                        meta.Aperture = $"f/{fnum.ToDouble():F1}";
                    if (exifSub.TryGetRational(ExifDirectoryBase.TagExposureTime, out var exp))
                        meta.ShutterSpeed = FormatShutter(exp.ToDouble());
                    if (exifSub.TryGetInt32(ExifDirectoryBase.TagIsoEquivalent, out var iso))
                        meta.Iso = iso;
                    if (exifSub.TryGetRational(ExifDirectoryBase.TagFocalLength, out var fl))
                        meta.FocalLength = $"{fl.ToDouble():F0}mm";
                }

                // IPTC
                var iptc = directories.OfType<IptcDirectory>().FirstOrDefault();
                if (iptc != null)
                {
                    var title = iptc.GetString(IptcDirectory.TagObjectName);
                    if (!string.IsNullOrWhiteSpace(title)) meta.Title = title;

                    var caption = iptc.GetString(IptcDirectory.TagCaption);
                    if (!string.IsNullOrWhiteSpace(caption)) meta.Description = caption;

                    var keywords = iptc.GetStringArray(IptcDirectory.TagKeywords);
                    if (keywords != null && keywords.Length > 0)
                        meta.Keywords = new List<string>(keywords);

                    var city = iptc.GetString(IptcDirectory.TagCity);
                    var country = iptc.GetString(IptcDirectory.TagCountryOrPrimaryLocationName);
                    var parts = new List<string>();
                    if (!string.IsNullOrWhiteSpace(city)) parts.Add(city);
                    if (!string.IsNullOrWhiteSpace(country)) parts.Add(country);
                    if (parts.Count > 0) meta.Location = string.Join(", ", parts);
                }

                // GPS
                var gps = directories.OfType<GpsDirectory>().FirstOrDefault();
                if (gps != null)
                {
                    try
                    {
                        var loc = gps.GetGeoLocation();
                        if (loc != null)
                        {
                            meta.GpsLat = loc.Latitude;
                            meta.GpsLon = loc.Longitude;
                            meta.LocationSource = "gps";
                        }
                    }
                    catch { }
                }

                // XMP - Rating
                var xmp = directories.OfType<XmpDirectory>().FirstOrDefault();
                if (xmp?.XmpMeta != null)
                {
                    try
                    {
                        var ratingStr = xmp.XmpMeta.GetPropertyString("http://ns.adobe.com/xap/1.0/", "Rating");
                        if (int.TryParse(ratingStr, out var rating))
                            meta.Rating = rating;

                        // XMP dc:title
                        if (meta.Title == null)
                        {
                            var xmpTitle = xmp.XmpMeta.GetLocalizedText("http://purl.org/dc/elements/1.1/", "title", null, "x-default");
                            if (xmpTitle != null && !string.IsNullOrWhiteSpace(xmpTitle.Value))
                                meta.Title = xmpTitle.Value;
                        }

                        // XMP dc:description
                        if (meta.Description == null)
                        {
                            var xmpDesc = xmp.XmpMeta.GetLocalizedText("http://purl.org/dc/elements/1.1/", "description", null, "x-default");
                            if (xmpDesc != null && !string.IsNullOrWhiteSpace(xmpDesc.Value))
                                meta.Description = xmpDesc.Value;
                        }
                    }
                    catch { }
                }
            }
            catch { }

            return meta;
        });
    }

    public async Task WriteMetaAsync(string filePath, MetaWrite meta)
    {
        var exifTool = FindExifTool()
            ?? throw new InvalidOperationException(ExifToolMissingMessage());

        await RunExifToolAsync(exifTool, BuildExifToolArgs(filePath, meta));
    }

    public async Task RotateOrientationAsync(string filePath, bool clockwise)
    {
        var exifTool = FindExifTool()
            ?? throw new InvalidOperationException(ExifToolMissingMessage());

        // Read current orientation
        var meta = await ReadMetaAsync(filePath);
        // We use raw exiftool rotation via -Orientation#
        // CW: rotate right = orientation value 6; CCW: rotate left = orientation value 8
        // For simplicity, just set to landscape (1) then rotate
        int orientationValue = clockwise ? 6 : 8;

        var args = $"-Orientation#={orientationValue} -overwrite_original \"{filePath}\"";
        await RunExifToolAsync(exifTool, args);
    }

    private string BuildExifToolArgs(string filePath, MetaWrite meta)
    {
        var sb = new StringBuilder();
        sb.Append("-overwrite_original ");

        if (meta.Title != null)
        {
            var escaped = meta.Title.Replace("\"", "\\\"");
            sb.Append($"\"-Title={escaped}\" ");
            sb.Append($"\"-ObjectName={escaped}\" ");
            sb.Append($"\"-XMP-dc:Title={escaped}\" ");
        }

        if (meta.Description != null)
        {
            var escaped = meta.Description.Replace("\"", "\\\"");
            sb.Append($"\"-Description={escaped}\" ");
            sb.Append($"\"-Caption-Abstract={escaped}\" ");
            sb.Append($"\"-XMP-dc:Description={escaped}\" ");
        }

        if (meta.Keywords != null)
        {
            foreach (var kw in meta.Keywords)
            {
                var escaped = kw.Replace("\"", "\\\"");
                sb.Append($"\"-Subject={escaped}\" ");
                sb.Append($"\"-Keywords={escaped}\" ");
            }
        }

        if (meta.City != null)
        {
            var escaped = meta.City.Replace("\"", "\\\"");
            sb.Append($"\"-City={escaped}\" ");
            sb.Append($"\"-XMP-photoshop:City={escaped}\" ");
        }

        if (meta.Country != null)
        {
            var escaped = meta.Country.Replace("\"", "\\\"");
            sb.Append($"\"-Country-PrimaryLocationName={escaped}\" ");
            sb.Append($"\"-XMP-photoshop:Country={escaped}\" ");
        }

        if (meta.Creator != null)
        {
            var escaped = meta.Creator.Replace("\"", "\\\"");
            sb.Append($"\"-Artist={escaped}\" ");
            sb.Append($"\"-XMP-dc:Creator={escaped}\" ");
        }

        if (meta.Copyright != null)
        {
            var escaped = meta.Copyright.Replace("\"", "\\\"");
            sb.Append($"\"-Copyright={escaped}\" ");
            sb.Append($"\"-XMP-dc:Rights={escaped}\" ");
        }

        if (meta.GpsLat.HasValue && meta.GpsLon.HasValue)
        {
            var latRef = meta.GpsLat.Value >= 0 ? "N" : "S";
            var lonRef = meta.GpsLon.Value >= 0 ? "E" : "W";
            sb.Append($"\"-GPSLatitude={Math.Abs(meta.GpsLat.Value)}\" ");
            sb.Append($"\"-GPSLongitude={Math.Abs(meta.GpsLon.Value)}\" ");
            sb.Append($"\"-GPSLatitudeRef={latRef}\" ");
            sb.Append($"\"-GPSLongitudeRef={lonRef}\" ");
        }

        if (meta.Rating.HasValue)
        {
            sb.Append($"\"-Rating={meta.Rating.Value}\" ");
            sb.Append($"\"-XMP:Rating={meta.Rating.Value}\" ");
        }

        sb.Append($"\"{filePath}\"");
        return sb.ToString();
    }

    private async Task RunExifToolAsync(string exifTool, string args)
    {
        var psi = new ProcessStartInfo
        {
            FileName = exifTool,
            Arguments = args,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true
        };

        using var process = Process.Start(psi)
            ?? throw new InvalidOperationException("Failed to start exiftool process.");

        await process.WaitForExitAsync();

        if (process.ExitCode != 0)
        {
            var err = await process.StandardError.ReadToEndAsync();
            throw new InvalidOperationException($"exiftool failed: {err}");
        }
    }

    private string? FindExifTool()
    {
        // 1. Next to the .exe (bundled with the app — preferred)
        var appDir = Path.GetDirectoryName(Environment.ProcessPath) ?? "";
        var local = Path.Combine(appDir, "exiftool.exe");
        if (File.Exists(local)) return local;

        // 2. System PATH
        foreach (var dir in (Environment.GetEnvironmentVariable("PATH") ?? "").Split(';'))
        {
            try
            {
                var p = Path.Combine(dir.Trim(), "exiftool.exe");
                if (File.Exists(p)) return p;
            }
            catch { }
        }
        return null;
    }

    public bool IsExifToolAvailable() => FindExifTool() != null;

    private static string ExifToolMissingMessage()
    {
        var appDir = Path.GetDirectoryName(Environment.ProcessPath) ?? "(app dir)";
        return $"exiftool.exe not found.\n\n" +
               $"Download the Windows standalone executable from https://exiftool.org, " +
               $"rename it from \"exiftool(-k).exe\" to \"exiftool.exe\", " +
               $"and place it in:\n{appDir}";
    }

    private static string FormatShutter(double seconds)
    {
        if (seconds >= 1)
            return $"{seconds:F1}s";
        int denom = (int)Math.Round(1.0 / seconds);
        return $"1/{denom}";
    }
}
