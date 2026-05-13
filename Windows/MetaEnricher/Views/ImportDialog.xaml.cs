using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using MetaEnricher.Models;
using MetaEnricher.Services;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace MetaEnricher.Views;

public sealed partial class ImportDialog : ContentDialog
{
    public AppState AppState => AppState.Instance;

    private CancellationTokenSource? _cts;
    private string _destPath = "";
    private string? _customSourcePath;
    private List<ImportItem> _newFiles = new();
    private readonly ObservableCollection<Photo> _previewPhotos = new();

    public ImportDialog()
    {
        this.InitializeComponent();
        ThumbRepeater.ItemsSource = _previewPhotos;
        Loaded += ImportDialog_Loaded;
    }

    private void ImportDialog_Loaded(object sender, RoutedEventArgs e)
    {
        var drives = ImportService.Instance.FindDriveRoots();
        CbDrives.Items.Clear();
        foreach (var d in drives)
            CbDrives.Items.Add(d);

        if (CbDrives.Items.Count > 0)
        {
            CbDrives.SelectedIndex = 0;
            SourceModeSelector.SelectedItem = SbiCard;
        }
        else
        {
            // No camera card connected — default to the folder mode so the dialog isn't a dead end.
            SourceModeSelector.SelectedItem = SbiFolder;
            TbCardHint.Text = "No camera card detected. Insert a card, or switch to “From folder”.";
        }
        ApplySourceMode();

        _destPath = AppState.CameraRootPath ?? "";
        TbDestPath.Text = string.IsNullOrEmpty(_destPath) ? "Not set" : _destPath;
    }

    private void SourceModeSelector_SelectionChanged(SelectorBar sender, SelectorBarSelectionChangedEventArgs e)
    {
        ApplySourceMode();

        // Switching mode invalidates any prior scan.
        ScanSummaryPanel.Visibility = Visibility.Collapsed;
        BtnImport.IsEnabled = false;
        _newFiles.Clear();
        _previewPhotos.Clear();
    }

    private void ApplySourceMode()
    {
        bool cardMode = SourceModeSelector.SelectedItem == SbiCard;
        CardModePanel.Visibility = cardMode ? Visibility.Visible : Visibility.Collapsed;
        FolderModePanel.Visibility = cardMode ? Visibility.Collapsed : Visibility.Visible;
    }

    private void CbDrives_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        // Reset scan result when drive changes
        ScanSummaryPanel.Visibility = Visibility.Collapsed;
        BtnImport.IsEnabled = false;
        _newFiles.Clear();
        _previewPhotos.Clear();
    }

    private async void BtnBrowseSource_Click(object sender, RoutedEventArgs e)
    {
        var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(App.CurrentWindow!);
        var picker = new Windows.Storage.Pickers.FolderPicker();
        picker.FileTypeFilter.Add("*");
        WinRT.Interop.InitializeWithWindow.Initialize(picker, hwnd);
        var folder = await picker.PickSingleFolderAsync();
        if (folder == null) return;

        _customSourcePath = folder.Path;
        TbFolderPath.Text = _customSourcePath;

        // Reset prior scan results
        ScanSummaryPanel.Visibility = Visibility.Collapsed;
        BtnImport.IsEnabled = false;
        _newFiles.Clear();
        _previewPhotos.Clear();
    }

    private async void BtnScan_Click(object sender, RoutedEventArgs e)
    {
        string? scanPath;
        if (SourceModeSelector.SelectedItem == SbiFolder)
        {
            if (string.IsNullOrEmpty(_customSourcePath))
            {
                ShowError("Pick a folder first.");
                return;
            }
            // If user picked a parent that has a DCIM child, prefer the DCIM child.
            var dcimChild = Path.Combine(_customSourcePath, "DCIM");
            scanPath = Directory.Exists(dcimChild) ? dcimChild : _customSourcePath;
        }
        else
        {
            if (CbDrives.SelectedItem is not string drive)
            {
                ShowError("Select a drive first.");
                return;
            }
            var dcimPath = Path.Combine(drive, "DCIM");
            if (!Directory.Exists(dcimPath)) { ShowError("DCIM folder not found on selected drive."); return; }
            scanPath = dcimPath;
        }

        if (string.IsNullOrEmpty(_destPath)) { ShowError("Set destination first."); return; }
        if (!Directory.Exists(scanPath)) { ShowError("Source folder does not exist."); return; }

        TbError.Visibility = Visibility.Collapsed;
        ScanSummaryPanel.Visibility = Visibility.Collapsed;
        ScanningPanel.Visibility = Visibility.Visible;
        BtnScanCard.IsEnabled = false;
        BtnScanFolder.IsEnabled = false;
        BtnImport.IsEnabled = false;

        try
        {
            var result = await ImportService.Instance.ScanAsync(scanPath, _destPath);

            _newFiles = result.NewFiles;

            TbNewCount.Text = result.NewFiles.Count.ToString();
            TbAlreadyCount.Text = result.AlreadyCopied.ToString();

            // Destination summary
            var destDirs = result.NewFiles
                .Select(f => Path.GetDirectoryName(f.DestPath)!)
                .Distinct()
                .OrderBy(d => d)
                .Take(3)
                .ToList();
            TbDestPreview.Text = destDirs.Count > 0
                ? "→ " + string.Join("\n→ ", destDirs)
                : "";

            // Thumbnail previews (first 40)
            _previewPhotos.Clear();
            foreach (var item in result.NewFiles.Take(40))
            {
                var photo = new Photo { Id = item.SourcePath, FilePath = item.SourcePath };
                photo.ThumbnailSource = ThumbnailService.Instance.GetThumbnail(item.SourcePath, 72);
                _previewPhotos.Add(photo);
            }

            ScanSummaryPanel.Visibility = Visibility.Visible;
            BtnImport.IsEnabled = result.NewFiles.Count > 0;
        }
        catch (Exception ex)
        {
            ShowError(ex.Message);
        }
        finally
        {
            ScanningPanel.Visibility = Visibility.Collapsed;
            BtnScanCard.IsEnabled = true;
            BtnScanFolder.IsEnabled = true;
        }
    }

    private async void BtnBrowseDest_Click(object sender, RoutedEventArgs e)
    {
        var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(App.CurrentWindow!);
        var picker = new Windows.Storage.Pickers.FolderPicker();
        picker.FileTypeFilter.Add("*");
        WinRT.Interop.InitializeWithWindow.Initialize(picker, hwnd);
        var folder = await picker.PickSingleFolderAsync();
        if (folder != null)
        {
            _destPath = folder.Path;
            TbDestPath.Text = _destPath;
            ScanSummaryPanel.Visibility = Visibility.Collapsed;
            BtnImport.IsEnabled = false;
        }
    }

    private async void BtnImport_Click(object sender, RoutedEventArgs e)
    {
        if (_newFiles.Count == 0) return;

        TbError.Visibility = Visibility.Collapsed;
        ProgressPanel.Visibility = Visibility.Visible;
        BtnImport.IsEnabled = false;
        BtnCancelImport.Visibility = Visibility.Visible;

        _cts = new CancellationTokenSource();

        var progress = new Progress<ImportProgress>(p => DispatcherQueue.TryEnqueue(() =>
        {
            if (p.Total > 0)
            {
                ImportProgressBar.IsIndeterminate = false;
                ImportProgressBar.Value = (double)p.Copied / p.Total;
            }
            else
            {
                ImportProgressBar.IsIndeterminate = true;
            }

            TbImportStatus.Text = p.Done ? "Import complete!" : $"Copying: {p.CurrentFile}";
            TbImportCount.Text = $"{p.Copied} / {p.Total} files";

            if (p.Error != null) ShowError(p.Error);

            if (p.Done)
            {
                BtnImport.IsEnabled = false;
                BtnCancelImport.Visibility = Visibility.Collapsed;
                _ = AppState.LoadSessionsAsync();
            }
        }));

        try
        {
            await ImportService.Instance.ImportAsync(_newFiles, progress, AppState.PicksFolderName, _cts.Token);
        }
        catch (OperationCanceledException)
        {
            TbImportStatus.Text = "Cancelled.";
            BtnImport.IsEnabled = true;
            BtnCancelImport.Visibility = Visibility.Collapsed;
        }
        catch (Exception ex)
        {
            ShowError(ex.Message);
            BtnImport.IsEnabled = true;
            BtnCancelImport.Visibility = Visibility.Collapsed;
        }
    }

    private void BtnCancelImport_Click(object sender, RoutedEventArgs e)
    {
        _cts?.Cancel();
        BtnCancelImport.Visibility = Visibility.Collapsed;
        TbImportStatus.Text = "Cancelling...";
    }

    private void ShowError(string msg)
    {
        TbError.Text = msg;
        TbError.Visibility = Visibility.Visible;
    }
}
