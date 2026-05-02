using System.Collections.Generic;
using CommunityToolkit.Mvvm.ComponentModel;
using Microsoft.UI.Xaml.Media;

namespace MetaEnricher.Models;

public enum ViewMode { Edited, Originals }
public enum LibrarySchema { MetaEnricher, Custom }
public enum SessionEnrichmentStatus { Unknown, Pending, Partial, Enriched }
public enum EnrichField { Title, Description, Keywords, Location }

public class PhotoSession
{
    public string Id { get; init; } = "";
    public string FolderPath { get; init; } = "";
    public string DateString { get; init; } = "";
    public string? Label { get; init; }
    public int EditedCount { get; set; }
    public int OriginalsCount { get; set; }
    public int EnrichedCount { get; set; }
    public string? ThumbnailPath { get; set; }
    public string DisplayName => Label != null ? $"{DateString} {Label}" : DateString;
    public SessionEnrichmentStatus EnrichmentStatus { get; set; } = SessionEnrichmentStatus.Unknown;
}

public class PhotoMeta
{
    public string? Title { get; set; }
    public string? Description { get; set; }
    public List<string> Keywords { get; set; } = new();
    public string? Location { get; set; }
    public string? LocationSource { get; set; }
    public string? DateTimeOriginal { get; set; }
    public string? Make { get; set; }
    public string? Model { get; set; }
    public string? FocalLength { get; set; }
    public string? Aperture { get; set; }
    public string? ShutterSpeed { get; set; }
    public int? Iso { get; set; }
    public int? Rating { get; set; }
    public string? Creator { get; set; }
    public string? Copyright { get; set; }
    public double? GpsLat { get; set; }
    public double? GpsLon { get; set; }
}

public partial class Photo : ObservableObject
{
    public string Id { get; init; } = "";
    public string FilePath { get; init; } = "";
    public string FileName => System.IO.Path.GetFileName(FilePath);

    [ObservableProperty]
    private PhotoMeta _meta = new();

    // Notify dependent computed properties when Meta is replaced.
    partial void OnMetaChanged(PhotoMeta value)
    {
        OnPropertyChanged(nameof(IsEnriched));
        OnPropertyChanged(nameof(HasPartialMeta));
    }

    public bool IsEnriched =>
        !string.IsNullOrWhiteSpace(Meta.Title) &&
        !string.IsNullOrWhiteSpace(Meta.Description);

    public bool HasPartialMeta =>
        !string.IsNullOrWhiteSpace(Meta.Title) ||
        Meta.Keywords.Count > 0;

    // Bound directly in ItemsRepeater DataTemplate — avoids TryGetElement(index) race.
    [ObservableProperty]
    private ImageSource? _thumbnailSource;
}

public class MetaWrite
{
    public string? Title { get; set; }
    public string? Description { get; set; }
    public List<string>? Keywords { get; set; }
    public string? City { get; set; }
    public string? Country { get; set; }
    public int? Rating { get; set; }
    public string? Creator { get; set; }
    public string? Copyright { get; set; }
    public double? GpsLat { get; set; }
    public double? GpsLon { get; set; }
}
