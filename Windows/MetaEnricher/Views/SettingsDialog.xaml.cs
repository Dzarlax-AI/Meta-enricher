using System;
using System.Collections.Generic;
using MetaEnricher.Models;
using MetaEnricher.Services;
using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.UI;

namespace MetaEnricher.Views;

public sealed partial class SettingsDialog : ContentDialog
{
    public AppState AppState => AppState.Instance;

    public SettingsDialog()
    {
        this.InitializeComponent();
        LoadCurrentSettings();
        Loaded += SettingsDialog_Loaded;
        PrimaryButtonClick += SettingsDialog_PrimaryButtonClick;
    }

    private void LoadCurrentSettings()
    {
        TbLibraryPath.Text = AppState.CameraRootPath ?? "Not set";
        TbPicksFolder.Text = AppState.PicksFolderName;
        TbOllamaUrl.Text = AppState.OllamaUrl;
        TbDefaultCreator.Text = AppState.DefaultCreator;
        TbDefaultCopyright.Text = AppState.DefaultCopyright;
        TbPullModel.Text = AppState.OllamaModel;
    }

    private async void SettingsDialog_Loaded(object sender, RoutedEventArgs e)
    {
        await RefreshModels();
        await CheckOllamaStatus();
        CheckExifToolStatus();
    }

    private void CheckExifToolStatus()
    {
        if (ExifService.Instance.IsExifToolAvailable())
        {
            ExifToolDot.Fill = new SolidColorBrush(Color.FromArgb(255, 34, 197, 94)); // green
            TbExifToolStatus.Text = "exiftool.exe found — metadata writing enabled";
        }
        else
        {
            ExifToolDot.Fill = new SolidColorBrush(Color.FromArgb(255, 239, 68, 68)); // red
            TbExifToolStatus.Text =
                "exiftool.exe not found. Download the Windows standalone from exiftool.org, " +
                "rename to exiftool.exe and place it next to MetaEnricher.exe.";
        }
    }

    private async System.Threading.Tasks.Task RefreshModels()
    {
        var models = await OllamaService.Instance.ListModelsAsync(TbOllamaUrl.Text);
        CbModel.Items.Clear();
        foreach (var m in models)
            CbModel.Items.Add(m);

        if (CbModel.Items.Contains(AppState.OllamaModel))
            CbModel.SelectedItem = AppState.OllamaModel;
        else if (CbModel.Items.Count > 0)
            CbModel.SelectedIndex = 0;
    }

    private async System.Threading.Tasks.Task CheckOllamaStatus()
    {
        bool ok = await OllamaService.Instance.CheckOllamaAsync(TbOllamaUrl.Text);
        OllamaStatusDot.Fill = new SolidColorBrush(ok
            ? Color.FromArgb(255, 34, 197, 94)
            : Color.FromArgb(255, 239, 68, 68));
        TbOllamaStatus.Text = ok ? "Connected" : "Not reachable";
    }

    private async void BtnTestOllama_Click(object sender, RoutedEventArgs e)
    {
        await CheckOllamaStatus();
    }

    private async void BtnRefreshModels_Click(object sender, RoutedEventArgs e)
    {
        await RefreshModels();
    }

    private async void BtnPullModel_Click(object sender, RoutedEventArgs e)
    {
        var modelName = TbPullModel.Text.Trim();
        if (string.IsNullOrWhiteSpace(modelName)) return;

        PullProgress.Visibility = Visibility.Visible;
        TbPullStatus.Visibility = Visibility.Visible;
        PullProgress.IsIndeterminate = true;

        try
        {
            var progress = new Progress<MetaEnricher.Services.PullProgress>(p =>
            {
                DispatcherQueue.TryEnqueue(() =>
                {
                    TbPullStatus.Text = p.Status;
                    if (p.Fraction >= 0)
                    {
                        PullProgress.IsIndeterminate = false;
                        PullProgress.Value = p.Fraction;
                    }
                    else
                    {
                        PullProgress.IsIndeterminate = true;
                    }
                });
            });

            await OllamaService.Instance.PullModelAsync(modelName, TbOllamaUrl.Text, progress);
            await RefreshModels();
            TbPullStatus.Text = "Pull complete!";
        }
        catch (Exception ex)
        {
            TbPullStatus.Text = $"Error: {ex.Message}";
        }
    }

    private async void BtnBrowseLibrary_Click(object sender, RoutedEventArgs e)
    {
        var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(App.CurrentWindow!);
        var picker = new Windows.Storage.Pickers.FolderPicker();
        picker.FileTypeFilter.Add("*");
        WinRT.Interop.InitializeWithWindow.Initialize(picker, hwnd);
        var folder = await picker.PickSingleFolderAsync();
        if (folder != null)
            TbLibraryPath.Text = folder.Path;
    }

    private void BtnClearCache_Click(object sender, RoutedEventArgs e)
    {
        ThumbnailService.Instance.PurgeAll();
        TbPullStatus.Text = "Thumbnail cache cleared.";
        TbPullStatus.Visibility = Visibility.Visible;
    }

    private void SettingsDialog_PrimaryButtonClick(ContentDialog sender, ContentDialogButtonClickEventArgs args)
    {
        // Save settings
        if (TbLibraryPath.Text != "Not set")
            AppState.CameraRootPath = TbLibraryPath.Text;
        AppState.PicksFolderName = string.IsNullOrWhiteSpace(TbPicksFolder.Text) ? "Edited export" : TbPicksFolder.Text;
        AppState.OllamaUrl = TbOllamaUrl.Text;
        if (CbModel.SelectedItem is string model)
            AppState.OllamaModel = model;
        AppState.DefaultCreator = TbDefaultCreator.Text;
        AppState.DefaultCopyright = TbDefaultCopyright.Text;
        AppState.SaveSettings();
    }
}
