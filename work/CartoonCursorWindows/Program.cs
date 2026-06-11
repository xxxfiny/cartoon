using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Windows.Forms;

namespace CartoonCursorWindows;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        ApplicationConfiguration.Initialize();
        Application.Run(new CursorAppContext());
    }
}

internal enum CursorEffectStyle
{
    Off = 0,
    Rings = 1,
    Sparkles = 2,
    Trail = 3,
    SparklesTrail = 4
}

internal enum EffectColorMode
{
    Auto = 0,
    Custom = 1
}

internal enum EffectColorRole
{
    Trail = 0,
    Click = 1,
    Particle = 2
}

internal enum EffectColorTarget
{
    Sticker = 0,
    Native = 1
}

internal sealed class StickerItem
{
    public string Id { get; set; } = Guid.NewGuid().ToString("N");
    public string Name { get; set; } = "Sticker";
    public string Path { get; set; } = "";
}

internal sealed class AppSettings
{
    public bool Enabled { get; set; } = true;
    public bool HideNativeCursor { get; set; }
    public bool NativeCursorEffectsEnabled { get; set; }
    public bool StickerWalkFollowEnabled { get; set; }
    public bool StickerFrameAnimationEnabled { get; set; }
    public double StickerWalkSpeedMultiplier { get; set; } = 1.0;
    public double StickerWalkAmplitudeMultiplier { get; set; } = 1.0;
    public int CursorSize { get; set; } = 128;
    public CursorEffectStyle EffectStyle { get; set; } = CursorEffectStyle.SparklesTrail;
    public EffectColorMode EffectColorMode { get; set; } = EffectColorMode.Auto;
    public EffectColorMode NativeEffectColorMode { get; set; } = EffectColorMode.Auto;
    public string[] CustomTrailColors { get; set; } = ColorPalettes.DefaultHexes();
    public string[] CustomClickColors { get; set; } = ColorPalettes.DefaultHexes();
    public string[] CustomParticleColors { get; set; } = ColorPalettes.DefaultHexes();
    public string[] CustomNativeTrailColors { get; set; } = ColorPalettes.DefaultHexes();
    public string[] CustomNativeClickColors { get; set; } = ColorPalettes.DefaultHexes();
    public string[] CustomNativeParticleColors { get; set; } = ColorPalettes.DefaultHexes();
    public string? CurrentStickerPath { get; set; }
    public List<StickerItem> StickerLibrary { get; set; } = new();
}

internal static class ColorPalettes
{
    private static readonly string[] Defaults =
    {
        "#FF5C8A",
        "#FFC640",
        "#4EB2FF",
        "#C468FF"
    };

    private static readonly string[] Presets =
    {
        "#000000",
        "#FFFFFF",
        "#7A7A7A",
        "#FF5A8A",
        "#FF3B30",
        "#FF9500",
        "#FFD60A",
        "#34C759",
        "#00C7BE",
        "#32ADE6",
        "#007AFF",
        "#5856D6",
        "#AF52DE",
        "#FF9FCE",
        "#B5E7FF",
        "#C8F7C5"
    };

    public static string[] DefaultHexes() => Defaults.ToArray();

    public static string[] PresetHexes() => Presets.ToArray();

    public static Color[] DefaultColors() => Defaults.Select(HexToColorOrDefault).ToArray();

    public static string[] NormalizeHexes(IEnumerable<string>? values)
    {
        List<string> normalized = new();
        if (values is not null)
        {
            foreach (string value in values)
            {
                if (TryParseHex(value, out Color color))
                {
                    normalized.Add(HexFromColor(color));
                    if (normalized.Count >= 4)
                    {
                        break;
                    }
                }
            }
        }

        foreach (string fallback in Defaults)
        {
            if (normalized.Count >= 4)
            {
                break;
            }
            normalized.Add(fallback);
        }

        return normalized.ToArray();
    }

    public static Color[] NormalizeColors(IEnumerable<string>? values)
    {
        return NormalizeHexes(values).Select(HexToColorOrDefault).ToArray();
    }

    public static string HexFromColor(Color color) => $"#{color.R:X2}{color.G:X2}{color.B:X2}";

    public static bool TryParseHex(string? value, out Color color)
    {
        color = Color.Empty;
        if (string.IsNullOrWhiteSpace(value))
        {
            return false;
        }

        string hex = value.Trim();
        if (hex.StartsWith("#", StringComparison.Ordinal))
        {
            hex = hex[1..];
        }

        if (hex.Length == 3)
        {
            hex = string.Concat(hex.Select(character => new string(character, 2)));
        }

        if (hex.Length != 6 ||
            !int.TryParse(hex, NumberStyles.HexNumber, CultureInfo.InvariantCulture, out int rgb))
        {
            return false;
        }

        color = Color.FromArgb(255, (rgb >> 16) & 0xFF, (rgb >> 8) & 0xFF, rgb & 0xFF);
        return true;
    }

    private static Color HexToColorOrDefault(string value)
    {
        return TryParseHex(value, out Color color) ? color : Color.FromArgb(255, 255, 92, 138);
    }
}

internal static class AppPaths
{
    public static string Root =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "CartoonCursor");

    public static string SettingsPath => Path.Combine(Root, "settings.json");

    public static string StickerDirectory => Path.Combine(Root, "Stickers");
}

internal static class SettingsStore
{
    private static readonly JsonSerializerOptions Options = new()
    {
        WriteIndented = true
    };

    public static AppSettings Load()
    {
        try
        {
            if (!File.Exists(AppPaths.SettingsPath))
            {
                return new AppSettings();
            }

            string json = File.ReadAllText(AppPaths.SettingsPath);
            AppSettings settings = JsonSerializer.Deserialize<AppSettings>(json, Options) ?? new AppSettings();
            Normalize(settings);
            return settings;
        }
        catch
        {
            return new AppSettings();
        }
    }

    public static void Save(AppSettings settings)
    {
        Directory.CreateDirectory(AppPaths.Root);
        Normalize(settings);
        File.WriteAllText(AppPaths.SettingsPath, JsonSerializer.Serialize(settings, Options));
    }

    private static void Normalize(AppSettings settings)
    {
        settings.StickerLibrary ??= new List<StickerItem>();
        settings.CursorSize = Math.Clamp(settings.CursorSize, 24, 320);
        settings.StickerWalkSpeedMultiplier = Math.Clamp(settings.StickerWalkSpeedMultiplier, 0.2, 3.0);
        settings.StickerWalkAmplitudeMultiplier = Math.Clamp(settings.StickerWalkAmplitudeMultiplier, 0.1, 2.0);
        settings.CustomTrailColors = ColorPalettes.NormalizeHexes(settings.CustomTrailColors);
        settings.CustomClickColors = ColorPalettes.NormalizeHexes(settings.CustomClickColors);
        settings.CustomParticleColors = ColorPalettes.NormalizeHexes(settings.CustomParticleColors);
        settings.CustomNativeTrailColors = ColorPalettes.NormalizeHexes(settings.CustomNativeTrailColors);
        settings.CustomNativeClickColors = ColorPalettes.NormalizeHexes(settings.CustomNativeClickColors);
        settings.CustomNativeParticleColors = ColorPalettes.NormalizeHexes(settings.CustomNativeParticleColors);
    }
}

internal sealed class CursorAppContext : ApplicationContext
{
    private readonly AppSettings _settings;
    private readonly NotifyIcon _notifyIcon;
    private readonly OverlayForm _overlay;
    private readonly System.Windows.Forms.Timer _timer;
    private readonly MouseHook _mouseHook;
    private bool _nativeCursorHidden;

    public CursorAppContext()
    {
        Directory.CreateDirectory(AppPaths.StickerDirectory);
        _settings = SettingsStore.Load();
        _settings.StickerLibrary = _settings.StickerLibrary
            .Where(item => !string.IsNullOrWhiteSpace(item.Path) && File.Exists(item.Path))
            .ToList();

        _overlay = new OverlayForm();
        LoadCurrentSticker();

        _notifyIcon = new NotifyIcon
        {
            Icon = SystemIcons.Application,
            Text = "Cartoon Cursor",
            Visible = true
        };
        RebuildMenu();

        _mouseHook = new MouseHook();
        _mouseHook.Clicked += (_, _) => _overlay.AddPulse(Cursor.Position);
        _mouseHook.Start();

        _timer = new System.Windows.Forms.Timer { Interval = 16 };
        _timer.Tick += (_, _) => Tick();
        _timer.Start();

        ApplyNativeCursorVisibility();
    }

    private void Tick()
    {
        _overlay.Render(_settings, Cursor.Position);
    }

    private void RebuildMenu()
    {
        ContextMenuStrip? oldMenu = _notifyIcon.ContextMenuStrip;
        ContextMenuStrip menu = new();

        menu.Items.Add(new ToolStripMenuItem("Enabled", null, (_, _) =>
        {
            _settings.Enabled = !_settings.Enabled;
            SaveAndRefresh();
        })
        {
            Checked = _settings.Enabled
        });

        menu.Items.Add(new ToolStripMenuItem("Sticker Walk Follow", null, (_, _) =>
        {
            _settings.StickerWalkFollowEnabled = !_settings.StickerWalkFollowEnabled;
            SaveAndRefresh();
        })
        {
            Checked = _settings.StickerWalkFollowEnabled
        });

        menu.Items.Add(new ToolStripMenuItem("Sticker Frame Animation", null, (_, _) =>
        {
            _settings.StickerFrameAnimationEnabled = !_settings.StickerFrameAnimationEnabled;
            SaveAndRefresh();
        })
        {
            Checked = _settings.StickerFrameAnimationEnabled
        });

        menu.Items.Add(BuildStickerWalkSpeedMenu());
        menu.Items.Add(BuildStickerWalkAmplitudeMenu());

        menu.Items.Add(new ToolStripMenuItem("Native Cursor Effects", null, (_, _) =>
        {
            _settings.NativeCursorEffectsEnabled = !_settings.NativeCursorEffectsEnabled;
            SaveAndRefresh();
        })
        {
            Checked = _settings.NativeCursorEffectsEnabled
        });

        menu.Items.Add(new ToolStripMenuItem("Hide Native Cursor (Best Effort)", null, (_, _) =>
        {
            _settings.HideNativeCursor = !_settings.HideNativeCursor;
            SaveAndRefresh();
        })
        {
            Checked = _settings.HideNativeCursor
        });

        menu.Items.Add(new ToolStripSeparator());

        menu.Items.Add(BuildStickerManagerMenu());
        menu.Items.Add(BuildSizeMenu());
        menu.Items.Add(BuildEffectMenu());
        menu.Items.Add(BuildEffectColorsMenu());

        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(new ToolStripMenuItem("Quit Cartoon Cursor", null, (_, _) => ExitThread()));

        _notifyIcon.ContextMenuStrip = menu;
        oldMenu?.Dispose();
    }

    private ToolStripMenuItem BuildStickerWalkSpeedMenu()
    {
        ToolStripMenuItem root = new("Sticker Walk Speed");
        foreach ((string Title, double Value) option in new[]
        {
            ("Very Slow", 0.35),
            ("Slow", 0.65),
            ("Normal", 1.0),
            ("Fast", 1.45),
            ("Very Fast", 2.0)
        })
        {
            root.DropDownItems.Add(new ToolStripMenuItem(option.Title, null, (_, _) =>
            {
                _settings.StickerWalkSpeedMultiplier = option.Value;
                SaveAndRefresh();
            })
            {
                Checked = Math.Abs(_settings.StickerWalkSpeedMultiplier - option.Value) < 0.01
            });
        }
        return root;
    }

    private ToolStripMenuItem BuildStickerWalkAmplitudeMenu()
    {
        ToolStripMenuItem root = new("Sticker Walk Amplitude");
        foreach ((string Title, double Value) option in new[]
        {
            ("Tiny", 0.35),
            ("Small", 0.65),
            ("Normal", 1.0),
            ("Bouncy", 1.35)
        })
        {
            root.DropDownItems.Add(new ToolStripMenuItem(option.Title, null, (_, _) =>
            {
                _settings.StickerWalkAmplitudeMultiplier = option.Value;
                SaveAndRefresh();
            })
            {
                Checked = Math.Abs(_settings.StickerWalkAmplitudeMultiplier - option.Value) < 0.01
            });
        }
        return root;
    }

    private ToolStripMenuItem BuildEffectColorsMenu()
    {
        ToolStripMenuItem root = new("Effect Colors");
        root.DropDownItems.Add(BuildEffectColorTargetMenu(EffectColorTarget.Sticker));
        root.DropDownItems.Add(BuildEffectColorTargetMenu(EffectColorTarget.Native));
        root.DropDownItems.Add(new ToolStripSeparator());
        root.DropDownItems.Add(new ToolStripMenuItem("Reset All Custom Palettes", null, (_, _) =>
        {
            string[] defaults = ColorPalettes.DefaultHexes();
            _settings.EffectColorMode = EffectColorMode.Custom;
            _settings.NativeEffectColorMode = EffectColorMode.Custom;
            _settings.CustomTrailColors = defaults.ToArray();
            _settings.CustomClickColors = defaults.ToArray();
            _settings.CustomParticleColors = defaults.ToArray();
            _settings.CustomNativeTrailColors = defaults.ToArray();
            _settings.CustomNativeClickColors = defaults.ToArray();
            _settings.CustomNativeParticleColors = defaults.ToArray();
            SaveAndRefresh();
        }));
        return root;
    }

    private ToolStripMenuItem BuildEffectColorTargetMenu(EffectColorTarget target)
    {
        ToolStripMenuItem root = new(target == EffectColorTarget.Sticker ? "Sticker Colors" : "Native Cursor Colors");
        EffectColorMode currentMode = target == EffectColorTarget.Sticker ? _settings.EffectColorMode : _settings.NativeEffectColorMode;
        foreach ((EffectColorMode Mode, string Title) option in new[]
        {
            (EffectColorMode.Auto, target == EffectColorTarget.Sticker ? "Auto From Sticker" : "Auto Default Colors"),
            (EffectColorMode.Custom, "Custom Palettes")
        })
        {
            root.DropDownItems.Add(new ToolStripMenuItem(option.Title, null, (_, _) =>
            {
                if (target == EffectColorTarget.Sticker)
                {
                    _settings.EffectColorMode = option.Mode;
                }
                else
                {
                    _settings.NativeEffectColorMode = option.Mode;
                }
                SaveAndRefresh();
            })
            {
                Checked = currentMode == option.Mode
            });
        }

        root.DropDownItems.Add(new ToolStripSeparator());
        root.DropDownItems.Add(BuildPaletteEditorItem(target, EffectColorRole.Trail, "Trail Colors..."));
        root.DropDownItems.Add(BuildPaletteEditorItem(target, EffectColorRole.Click, "Click Colors..."));
        root.DropDownItems.Add(BuildPaletteEditorItem(target, EffectColorRole.Particle, "Sparkle Colors..."));
        return root;
    }

    private ToolStripMenuItem BuildPaletteEditorItem(EffectColorTarget target, EffectColorRole role, string title)
    {
        return new ToolStripMenuItem(title, null, (_, _) => ShowPaletteEditor(target, role));
    }

    private void ShowPaletteEditor(EffectColorTarget target, EffectColorRole role)
    {
        string targetTitle = target == EffectColorTarget.Sticker ? "Sticker Colors" : "Native Cursor Colors";
        string roleTitle = role switch
        {
            EffectColorRole.Trail => "Trail Colors",
            EffectColorRole.Click => "Click Colors",
            EffectColorRole.Particle => "Sparkle Colors",
            _ => "Colors"
        };

        using PaletteEditorForm form = new($"{targetTitle} - {roleTitle}", GetCustomPalette(target, role));
        if (form.ShowDialog() != DialogResult.OK)
        {
            return;
        }

        if (target == EffectColorTarget.Sticker)
        {
            _settings.EffectColorMode = EffectColorMode.Custom;
        }
        else
        {
            _settings.NativeEffectColorMode = EffectColorMode.Custom;
        }

        SetCustomPalette(target, role, form.PaletteHexes);
        SaveAndRefresh();
    }

    private string[] GetCustomPalette(EffectColorTarget target, EffectColorRole role)
    {
        return (target, role) switch
        {
            (EffectColorTarget.Sticker, EffectColorRole.Trail) => _settings.CustomTrailColors,
            (EffectColorTarget.Sticker, EffectColorRole.Click) => _settings.CustomClickColors,
            (EffectColorTarget.Sticker, EffectColorRole.Particle) => _settings.CustomParticleColors,
            (EffectColorTarget.Native, EffectColorRole.Trail) => _settings.CustomNativeTrailColors,
            (EffectColorTarget.Native, EffectColorRole.Click) => _settings.CustomNativeClickColors,
            (EffectColorTarget.Native, EffectColorRole.Particle) => _settings.CustomNativeParticleColors,
            _ => ColorPalettes.DefaultHexes()
        };
    }

    private void SetCustomPalette(EffectColorTarget target, EffectColorRole role, string[] colors)
    {
        string[] normalized = ColorPalettes.NormalizeHexes(colors);
        switch (target, role)
        {
            case (EffectColorTarget.Sticker, EffectColorRole.Trail):
                _settings.CustomTrailColors = normalized;
                break;
            case (EffectColorTarget.Sticker, EffectColorRole.Click):
                _settings.CustomClickColors = normalized;
                break;
            case (EffectColorTarget.Sticker, EffectColorRole.Particle):
                _settings.CustomParticleColors = normalized;
                break;
            case (EffectColorTarget.Native, EffectColorRole.Trail):
                _settings.CustomNativeTrailColors = normalized;
                break;
            case (EffectColorTarget.Native, EffectColorRole.Click):
                _settings.CustomNativeClickColors = normalized;
                break;
            case (EffectColorTarget.Native, EffectColorRole.Particle):
                _settings.CustomNativeParticleColors = normalized;
                break;
        }
    }

    private ToolStripMenuItem BuildStickerManagerMenu()
    {
        ToolStripMenuItem root = new("Sticker Manager");

        root.DropDownItems.Add(new ToolStripMenuItem("Import Stickers...", null, (_, _) => ImportStickers()));
        root.DropDownItems.Add(new ToolStripMenuItem("Use Default Cartoon", null, (_, _) =>
        {
            _settings.CurrentStickerPath = null;
            LoadCurrentSticker();
            SaveAndRefresh();
        })
        {
            Checked = string.IsNullOrWhiteSpace(_settings.CurrentStickerPath)
        });

        root.DropDownItems.Add(new ToolStripSeparator());

        if (_settings.StickerLibrary.Count == 0)
        {
            root.DropDownItems.Add(new ToolStripMenuItem("No Imported Stickers") { Enabled = false });
        }
        else
        {
            foreach (StickerItem item in _settings.StickerLibrary)
            {
                ToolStripMenuItem stickerItem = new(item.Name, LoadMenuThumbnail(item.Path), (_, _) =>
                {
                    _settings.CurrentStickerPath = item.Path;
                    LoadCurrentSticker();
                    SaveAndRefresh();
                })
                {
                    Checked = IsCurrentSticker(item)
                };
                root.DropDownItems.Add(stickerItem);
            }
        }

        root.DropDownItems.Add(new ToolStripSeparator());
        root.DropDownItems.Add(new ToolStripMenuItem("Delete Current Sticker", null, (_, _) => DeleteCurrentSticker())
        {
            Enabled = CurrentStickerItem() is not null
        });

        ToolStripMenuItem deleteSpecific = new("Delete Sticker");
        if (_settings.StickerLibrary.Count == 0)
        {
            deleteSpecific.DropDownItems.Add(new ToolStripMenuItem("No Imported Stickers") { Enabled = false });
        }
        else
        {
            foreach (StickerItem item in _settings.StickerLibrary)
            {
                deleteSpecific.DropDownItems.Add(new ToolStripMenuItem(item.Name, LoadMenuThumbnail(item.Path), (_, _) => DeleteSticker(item))
                {
                    Checked = IsCurrentSticker(item)
                });
            }
        }
        root.DropDownItems.Add(deleteSpecific);

        root.DropDownItems.Add(new ToolStripMenuItem("Reveal Sticker Folder", null, (_, _) =>
        {
            Directory.CreateDirectory(AppPaths.StickerDirectory);
            Process.Start(new ProcessStartInfo(AppPaths.StickerDirectory) { UseShellExecute = true });
        }));

        return root;
    }

    private ToolStripMenuItem BuildSizeMenu()
    {
        ToolStripMenuItem root = new("Size");
        foreach (int size in new[] { 32, 48, 64, 80, 96, 128, 160, 192, 256 })
        {
            root.DropDownItems.Add(new ToolStripMenuItem($"{size} px", null, (_, _) =>
            {
                _settings.CursorSize = size;
                SaveAndRefresh();
            })
            {
                Checked = _settings.CursorSize == size
            });
        }
        return root;
    }

    private ToolStripMenuItem BuildEffectMenu()
    {
        ToolStripMenuItem root = new("Effect");
        foreach ((CursorEffectStyle Style, string Title) option in new[]
        {
            (CursorEffectStyle.SparklesTrail, "Sparkles + Trail"),
            (CursorEffectStyle.Sparkles, "Sparkles"),
            (CursorEffectStyle.Trail, "Trail"),
            (CursorEffectStyle.Rings, "Rings"),
            (CursorEffectStyle.Off, "Off")
        })
        {
            root.DropDownItems.Add(new ToolStripMenuItem(option.Title, null, (_, _) =>
            {
                _settings.EffectStyle = option.Style;
                SaveAndRefresh();
            })
            {
                Checked = _settings.EffectStyle == option.Style
            });
        }
        return root;
    }

    private void ImportStickers()
    {
        using OpenFileDialog dialog = new()
        {
            Title = "Import Stickers",
            Filter = "Images|*.png;*.apng;*.gif;*.jpg;*.jpeg;*.bmp;*.webp|All files|*.*",
            Multiselect = true
        };

        if (dialog.ShowDialog() != DialogResult.OK)
        {
            return;
        }

        StickerItem? lastImported = null;
        foreach (string sourcePath in dialog.FileNames)
        {
            string extension = Path.GetExtension(sourcePath);
            if (string.IsNullOrWhiteSpace(extension))
            {
                extension = ".png";
            }

            string id = Guid.NewGuid().ToString("N");
            string targetPath = Path.Combine(AppPaths.StickerDirectory, id + extension.ToLowerInvariant());
            File.Copy(sourcePath, targetPath, overwrite: false);

            StickerItem item = new()
            {
                Id = id,
                Name = Path.GetFileNameWithoutExtension(sourcePath),
                Path = targetPath
            };
            _settings.StickerLibrary.Add(item);
            lastImported = item;
        }

        if (lastImported is not null)
        {
            _settings.CurrentStickerPath = lastImported.Path;
            LoadCurrentSticker();
        }
        SaveAndRefresh();
    }

    private void DeleteCurrentSticker()
    {
        StickerItem? current = CurrentStickerItem();
        if (current is null)
        {
            return;
        }

        DeleteSticker(current);
    }

    private void DeleteSticker(StickerItem item)
    {
        bool wasCurrent = IsCurrentSticker(item);
        _settings.StickerLibrary.RemoveAll(candidate => candidate.Id == item.Id);
        TryDeleteFile(item.Path);

        if (wasCurrent)
        {
            _settings.CurrentStickerPath = null;
            LoadCurrentSticker();
        }

        SaveAndRefresh();
    }

    private StickerItem? CurrentStickerItem()
    {
        return _settings.StickerLibrary.FirstOrDefault(IsCurrentSticker);
    }

    private bool IsCurrentSticker(StickerItem item)
    {
        return !string.IsNullOrWhiteSpace(_settings.CurrentStickerPath) &&
            string.Equals(Path.GetFullPath(item.Path), Path.GetFullPath(_settings.CurrentStickerPath!), StringComparison.OrdinalIgnoreCase);
    }

    private static Image? LoadMenuThumbnail(string path)
    {
        try
        {
            using FileStream stream = File.OpenRead(path);
            using Image source = Image.FromStream(stream);
            Bitmap thumbnail = new(24, 24, PixelFormat.Format32bppArgb);
            using Graphics graphics = Graphics.FromImage(thumbnail);
            graphics.Clear(Color.Transparent);
            graphics.InterpolationMode = InterpolationMode.HighQualityBicubic;
            SizeF fit = FitSize(source.Size, new SizeF(22, 22));
            graphics.DrawImage(source, 1 + (22 - fit.Width) / 2, 1 + (22 - fit.Height) / 2, fit.Width, fit.Height);
            return thumbnail;
        }
        catch
        {
            return null;
        }
    }

    private void LoadCurrentSticker()
    {
        if (string.IsNullOrWhiteSpace(_settings.CurrentStickerPath) || !File.Exists(_settings.CurrentStickerPath))
        {
            _overlay.SetSticker(null, null);
            return;
        }

        try
        {
            byte[] bytes = File.ReadAllBytes(_settings.CurrentStickerPath);
            MemoryStream stream = new(bytes);
            Image image = Image.FromStream(stream);
            _overlay.SetSticker(image, stream);
        }
        catch
        {
            _settings.CurrentStickerPath = null;
            _overlay.SetSticker(null, null);
        }
    }

    private void SaveAndRefresh()
    {
        SettingsStore.Save(_settings);
        ApplyNativeCursorVisibility();
        RebuildMenu();
        _overlay.Render(_settings, Cursor.Position);
    }

    private void ApplyNativeCursorVisibility()
    {
        bool shouldHide = _settings.Enabled && _settings.HideNativeCursor;
        if (shouldHide == _nativeCursorHidden)
        {
            return;
        }

        if (shouldHide)
        {
            while (NativeMethods.ShowCursor(false) >= 0)
            {
            }
        }
        else
        {
            while (NativeMethods.ShowCursor(true) < 0)
            {
            }
        }
        _nativeCursorHidden = shouldHide;
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _timer.Stop();
            _timer.Dispose();
            _mouseHook.Dispose();
            _overlay.Dispose();
            _notifyIcon.Visible = false;
            _notifyIcon.Dispose();
            if (_nativeCursorHidden)
            {
                while (NativeMethods.ShowCursor(true) < 0)
                {
                }
            }
        }
        base.Dispose(disposing);
    }

    private static void TryDeleteFile(string path)
    {
        try
        {
            if (File.Exists(path))
            {
                File.Delete(path);
            }
        }
        catch
        {
            // Leave the file on disk if Windows has it locked.
        }
    }

    private static SizeF FitSize(Size source, SizeF maxSize)
    {
        if (source.Width <= 0 || source.Height <= 0)
        {
            return maxSize;
        }

        float scale = Math.Min(maxSize.Width / source.Width, maxSize.Height / source.Height);
        return new SizeF(source.Width * scale, source.Height * scale);
    }
}

internal sealed class PaletteEditorForm : Form
{
    private readonly List<RowControls> _rows = new();
    private bool _updating;
    private string[] _draftHexes;

    public string[] PaletteHexes { get; private set; }

    public PaletteEditorForm(string title, IEnumerable<string> initialHexes)
    {
        Text = title;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;
        ShowIcon = false;
        ShowInTaskbar = false;
        StartPosition = FormStartPosition.CenterScreen;
        ClientSize = new Size(820, 370);
        PaletteHexes = ColorPalettes.NormalizeHexes(initialHexes);
        _draftHexes = PaletteHexes.ToArray();

        Label hint = new()
        {
            Text = "Edit all four colors, then Apply.",
            AutoSize = true,
            Location = new Point(16, 14)
        };
        Controls.Add(hint);

        TableLayoutPanel table = new()
        {
            Location = new Point(16, 44),
            Size = new Size(790, 244),
            ColumnCount = 7,
            RowCount = 4
        };
        table.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 70));
        table.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 54));
        table.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 96));
        table.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 52));
        table.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 52));
        table.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 52));
        table.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));

        for (int index = 0; index < 4; index++)
        {
            ColorPalettes.TryParseHex(_draftHexes[index], out Color color);
            AddRow(table, index, color);
        }
        Controls.Add(table);

        Button reset = new()
        {
            Text = "Reset",
            Location = new Point(16, 310),
            Size = new Size(92, 34)
        };
        reset.Click += (_, _) => SetDraftPalette(ColorPalettes.DefaultHexes());
        Controls.Add(reset);

        Button cancel = new()
        {
            Text = "Cancel",
            DialogResult = DialogResult.Cancel,
            Location = new Point(596, 310),
            Size = new Size(92, 34)
        };
        Controls.Add(cancel);

        Button apply = new()
        {
            Text = "Apply",
            DialogResult = DialogResult.OK,
            Location = new Point(704, 310),
            Size = new Size(92, 34)
        };
        apply.Click += (_, _) =>
        {
            PaletteHexes = ColorPalettes.NormalizeHexes(_draftHexes);
        };
        Controls.Add(apply);

        AcceptButton = apply;
        CancelButton = cancel;
    }

    private void AddRow(TableLayoutPanel table, int rowIndex, Color color)
    {
        Label label = new()
        {
            Text = $"Color {rowIndex + 1}",
            AutoSize = true,
            Anchor = AnchorStyles.Left
        };
        table.Controls.Add(label, 0, rowIndex);

        Button swatch = new()
        {
            BackColor = color,
            FlatStyle = FlatStyle.Popup,
            Margin = new Padding(4, 8, 4, 8),
            Size = new Size(40, 34)
        };
        swatch.Click += (_, _) => ChooseColor(rowIndex);
        table.Controls.Add(swatch, 1, rowIndex);

        TextBox hex = new()
        {
            Text = ColorPalettes.HexFromColor(color),
            CharacterCasing = CharacterCasing.Upper,
            Margin = new Padding(4, 10, 4, 8),
            Width = 86
        };
        hex.Leave += (_, _) => ApplyHex(rowIndex);
        hex.KeyDown += (_, args) =>
        {
            if (args.KeyCode == Keys.Enter)
            {
                ApplyHex(rowIndex);
                args.SuppressKeyPress = true;
            }
        };
        table.Controls.Add(hex, 2, rowIndex);

        NumericUpDown red = BuildChannelInput(color.R);
        NumericUpDown green = BuildChannelInput(color.G);
        NumericUpDown blue = BuildChannelInput(color.B);
        red.ValueChanged += (_, _) => ApplyChannels(rowIndex);
        green.ValueChanged += (_, _) => ApplyChannels(rowIndex);
        blue.ValueChanged += (_, _) => ApplyChannels(rowIndex);
        table.Controls.Add(red, 3, rowIndex);
        table.Controls.Add(green, 4, rowIndex);
        table.Controls.Add(blue, 5, rowIndex);

        FlowLayoutPanel presets = new()
        {
            FlowDirection = FlowDirection.LeftToRight,
            Margin = new Padding(6, 8, 0, 4),
            WrapContents = true,
            AutoSize = false,
            Size = new Size(402, 46)
        };
        foreach (string preset in ColorPalettes.PresetHexes())
        {
            Button chip = new()
            {
                BackColor = ColorPalettes.TryParseHex(preset, out Color presetColor) ? presetColor : Color.White,
                FlatStyle = FlatStyle.Popup,
                Size = new Size(20, 20),
                Margin = new Padding(2),
                Tag = preset
            };
            chip.Click += (_, _) => SetDraftColor(rowIndex, (string)chip.Tag);
            presets.Controls.Add(chip);
        }
        table.Controls.Add(presets, 6, rowIndex);

        _rows.Add(new RowControls(swatch, hex, red, green, blue));
    }

    private static NumericUpDown BuildChannelInput(int value)
    {
        return new NumericUpDown
        {
            Minimum = 0,
            Maximum = 255,
            Value = value,
            Margin = new Padding(4, 9, 4, 8),
            Width = 46
        };
    }

    private void ChooseColor(int rowIndex)
    {
        if (!ColorPalettes.TryParseHex(_draftHexes[rowIndex], out Color currentColor))
        {
            currentColor = ColorPalettes.DefaultColors()[rowIndex];
        }

        using ColorDialog dialog = new()
        {
            AllowFullOpen = true,
            FullOpen = true,
            Color = currentColor
        };
        if (dialog.ShowDialog(this) == DialogResult.OK)
        {
            SetDraftColor(rowIndex, ColorPalettes.HexFromColor(dialog.Color));
        }
    }

    private void ApplyHex(int rowIndex)
    {
        if (_updating)
        {
            return;
        }

        if (ColorPalettes.TryParseHex(_rows[rowIndex].Hex.Text, out Color color))
        {
            SetDraftColor(rowIndex, ColorPalettes.HexFromColor(color));
        }
        else
        {
            UpdateRow(rowIndex, _draftHexes[rowIndex]);
        }
    }

    private void ApplyChannels(int rowIndex)
    {
        if (_updating)
        {
            return;
        }

        RowControls row = _rows[rowIndex];
        Color color = Color.FromArgb(255, (int)row.Red.Value, (int)row.Green.Value, (int)row.Blue.Value);
        SetDraftColor(rowIndex, ColorPalettes.HexFromColor(color));
    }

    private void SetDraftPalette(IEnumerable<string> hexes)
    {
        string[] normalized = ColorPalettes.NormalizeHexes(hexes);
        for (int index = 0; index < 4; index++)
        {
            SetDraftColor(index, normalized[index]);
        }
    }

    private void SetDraftColor(int rowIndex, string hex)
    {
        if (!ColorPalettes.TryParseHex(hex, out Color color))
        {
            return;
        }

        _draftHexes[rowIndex] = ColorPalettes.HexFromColor(color);
        UpdateRow(rowIndex, _draftHexes[rowIndex]);
    }

    private void UpdateRow(int rowIndex, string hex)
    {
        if (!ColorPalettes.TryParseHex(hex, out Color color))
        {
            return;
        }

        _updating = true;
        RowControls row = _rows[rowIndex];
        row.Swatch.BackColor = color;
        row.Hex.Text = ColorPalettes.HexFromColor(color);
        row.Red.Value = color.R;
        row.Green.Value = color.G;
        row.Blue.Value = color.B;
        _updating = false;
    }

    private sealed record RowControls(Button Swatch, TextBox Hex, NumericUpDown Red, NumericUpDown Green, NumericUpDown Blue);
}

internal sealed class OverlayForm : Form
{
    private readonly List<TrailPoint> _stickerTrailPoints = new();
    private readonly List<TrailPoint> _nativeTrailPoints = new();
    private readonly List<PulsePoint> _pulses = new();

    private Image? _sticker;
    private Stream? _stickerStream;
    private Color[] _autoStickerColors = ColorPalettes.DefaultColors();
    private FrameDimension? _stickerFrameDimension;
    private int[] _stickerFrameDelaysMs = Array.Empty<int>();
    private int _stickerFrameCount = 1;
    private int _stickerFrameIndex;
    private PointF _lastStickerTrailPoint;
    private PointF _lastNativeTrailPoint;
    private PointF _stickerDrawPoint;
    private DateTime _lastStickerTrailSample = DateTime.MinValue;
    private DateTime _lastNativeTrailSample = DateTime.MinValue;
    private DateTime _lastStickerAnimationTime = DateTime.MinValue;
    private DateTime _lastStickerFrameUpdate = DateTime.MinValue;
    private bool _hasStickerTrailPoint;
    private bool _hasNativeTrailPoint;
    private bool _hasStickerDrawPoint;
    private float _stickerWalkPhase;
    private float _stickerWalkSpeed;
    private float _stickerWalkTilt;

    public OverlayForm()
    {
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        TopMost = true;
        StartPosition = FormStartPosition.Manual;
        Bounds = SystemInformation.VirtualScreen;
        MinimumSize = new Size(1, 1);
    }

    protected override bool ShowWithoutActivation => true;

    protected override CreateParams CreateParams
    {
        get
        {
            CreateParams cp = base.CreateParams;
            cp.ExStyle |= NativeMethods.WS_EX_LAYERED |
                NativeMethods.WS_EX_TRANSPARENT |
                NativeMethods.WS_EX_TOOLWINDOW |
                NativeMethods.WS_EX_NOACTIVATE;
            return cp;
        }
    }

    public void SetSticker(Image? image, Stream? backingStream)
    {
        _sticker?.Dispose();
        _stickerStream?.Dispose();
        _sticker = image;
        _stickerStream = backingStream;
        _autoStickerColors = _sticker is not null ? ExtractEffectColors(_sticker) : ColorPalettes.DefaultColors();
        ResetStickerFrameState();
        _hasStickerDrawPoint = false;
        _hasStickerTrailPoint = false;
        _stickerTrailPoints.Clear();
    }

    public void AddPulse(Point screenPoint)
    {
        Rectangle bounds = SystemInformation.VirtualScreen;
        _pulses.Add(new PulsePoint(new PointF(screenPoint.X - bounds.Left, screenPoint.Y - bounds.Top), DateTime.UtcNow, Environment.TickCount));
    }

    public void Render(AppSettings settings, Point screenCursor)
    {
        Rectangle bounds = SystemInformation.VirtualScreen;
        if (Bounds != bounds)
        {
            Bounds = bounds;
        }

        bool shouldRender = settings.Enabled ||
            (settings.NativeCursorEffectsEnabled && settings.EffectStyle != CursorEffectStyle.Off);
        if (!shouldRender)
        {
            Hide();
            return;
        }

        if (!Visible)
        {
            Show();
        }

        PointF localCursor = new(screenCursor.X - bounds.Left, screenCursor.Y - bounds.Top);
        PointF stickerPoint = ResolveStickerPoint(localCursor, settings);
        bool stickerTrailEnabled = settings.Enabled && ShouldDrawTrail(settings.EffectStyle);
        bool nativeTrailEnabled = settings.NativeCursorEffectsEnabled && ShouldDrawTrail(settings.EffectStyle);
        MaybeAddTrail(stickerPoint, stickerTrailEnabled, _stickerTrailPoints, ref _hasStickerTrailPoint, ref _lastStickerTrailPoint, ref _lastStickerTrailSample, settings);
        MaybeAddTrail(localCursor, nativeTrailEnabled, _nativeTrailPoints, ref _hasNativeTrailPoint, ref _lastNativeTrailPoint, ref _lastNativeTrailSample, settings);

        using Bitmap canvas = new(Math.Max(1, bounds.Width), Math.Max(1, bounds.Height), PixelFormat.Format32bppArgb);
        using Graphics graphics = Graphics.FromImage(canvas);
        graphics.Clear(Color.Transparent);
        graphics.SmoothingMode = SmoothingMode.AntiAlias;
        graphics.InterpolationMode = InterpolationMode.HighQualityBicubic;

        DrawTrail(graphics, _stickerTrailPoints, ColorsForRole(settings, EffectColorRole.Trail, EffectColorTarget.Sticker), settings);
        DrawTrail(graphics, _nativeTrailPoints, ColorsForRole(settings, EffectColorRole.Trail, EffectColorTarget.Native), settings);

        bool stickerPulseEnabled = settings.Enabled && ShouldDrawClick(settings.EffectStyle);
        bool nativePulseEnabled = settings.NativeCursorEffectsEnabled && ShouldDrawClick(settings.EffectStyle);
        if (stickerPulseEnabled)
        {
            DrawPulses(
                graphics,
                settings,
                ColorsForRole(settings, EffectColorRole.Click, EffectColorTarget.Sticker),
                ColorsForRole(settings, EffectColorRole.Particle, EffectColorTarget.Sticker));
        }
        if (nativePulseEnabled)
        {
            DrawPulses(
                graphics,
                settings,
                ColorsForRole(settings, EffectColorRole.Click, EffectColorTarget.Native),
                ColorsForRole(settings, EffectColorRole.Particle, EffectColorTarget.Native));
        }
        CleanupPulses(stickerPulseEnabled || nativePulseEnabled);

        if (settings.Enabled)
        {
            DrawSticker(graphics, stickerPoint, settings);
        }

        UpdateLayeredWindow(canvas, bounds.Location);
    }

    private PointF ResolveStickerPoint(PointF cursorPoint, AppSettings settings)
    {
        if (!settings.Enabled || !settings.StickerWalkFollowEnabled)
        {
            _hasStickerDrawPoint = false;
            _lastStickerAnimationTime = DateTime.UtcNow;
            _stickerWalkSpeed = 0;
            _stickerWalkTilt *= 0.72f;
            return cursorPoint;
        }

        DateTime now = DateTime.UtcNow;
        if (!_hasStickerDrawPoint || _lastStickerAnimationTime == DateTime.MinValue)
        {
            _stickerDrawPoint = cursorPoint;
            _hasStickerDrawPoint = true;
            _lastStickerAnimationTime = now;
            _stickerWalkSpeed = 0;
            _stickerWalkTilt = 0;
            return _stickerDrawPoint;
        }

        double deltaSeconds = Math.Clamp((now - _lastStickerAnimationTime).TotalSeconds, 1.0 / 240.0, 1.0 / 20.0);
        _lastStickerAnimationTime = now;

        float dx = cursorPoint.X - _stickerDrawPoint.X;
        float dy = cursorPoint.Y - _stickerDrawPoint.Y;
        float distance = MathF.Sqrt(dx * dx + dy * dy);
        if (distance > Math.Max(420f, settings.CursorSize * 5f))
        {
            _stickerDrawPoint = cursorPoint;
            _stickerWalkSpeed = 0;
            _stickerWalkTilt = 0;
            return _stickerDrawPoint;
        }

        float followAmount = 1f - (float)Math.Exp(-deltaSeconds * 9.5 * settings.StickerWalkSpeedMultiplier);
        PointF previousPoint = _stickerDrawPoint;
        _stickerDrawPoint = new PointF(
            _stickerDrawPoint.X + dx * followAmount,
            _stickerDrawPoint.Y + dy * followAmount);

        float moveX = _stickerDrawPoint.X - previousPoint.X;
        float moveY = _stickerDrawPoint.Y - previousPoint.Y;
        float moveDistance = MathF.Sqrt(moveX * moveX + moveY * moveY);
        _stickerWalkSpeed = moveDistance / Math.Max(0.001f, (float)deltaSeconds);
        _stickerWalkPhase += moveDistance / Math.Max(18f, settings.CursorSize * 0.42f) * MathF.PI;
        if (_stickerWalkPhase > MathF.PI * 200f)
        {
            _stickerWalkPhase %= MathF.PI * 2f;
        }

        float targetTilt = Math.Clamp(moveX / Math.Max(1f, settings.CursorSize), -1f, 1f) * 0.26f;
        _stickerWalkTilt = _stickerWalkTilt * 0.72f + targetTilt * 0.28f;
        return _stickerDrawPoint;
    }

    private void MaybeAddTrail(
        PointF point,
        bool enabled,
        List<TrailPoint> trailPoints,
        ref bool hasTrailPoint,
        ref PointF lastTrailPoint,
        ref DateTime lastTrailSample,
        AppSettings settings)
    {
        if (!enabled)
        {
            trailPoints.Clear();
            hasTrailPoint = false;
            return;
        }

        DateTime now = DateTime.UtcNow;
        if (hasTrailPoint)
        {
            float dx = point.X - lastTrailPoint.X;
            float dy = point.Y - lastTrailPoint.Y;
            double distance = Math.Sqrt(dx * dx + dy * dy);
            if (distance >= 5 || (now - lastTrailSample).TotalMilliseconds >= 45)
            {
                trailPoints.Add(new TrailPoint(point, now, Environment.TickCount));
                lastTrailSample = now;
            }
        }

        lastTrailPoint = point;
        hasTrailPoint = true;
        if (trailPoints.Count > 48)
        {
            trailPoints.RemoveRange(0, trailPoints.Count - 48);
        }
    }

    private void DrawSticker(Graphics graphics, PointF cursorPoint, AppSettings settings)
    {
        int cursorSize = settings.CursorSize;
        float anchorX = settings.StickerWalkFollowEnabled ? 0.18f : 0.08f;
        float anchorY = settings.StickerWalkFollowEnabled ? 0.82f : 0.92f;
        RectangleF drawRect;
        if (_sticker is not null)
        {
            UpdateStickerFrame(settings);

            float maxEdge = Math.Max(_sticker.Width, _sticker.Height);
            float scale = cursorSize / Math.Max(1, maxEdge);
            float width = _sticker.Width * scale;
            float height = _sticker.Height * scale;
            drawRect = new RectangleF(cursorPoint.X - width * anchorX, cursorPoint.Y - height * anchorY, width, height);
            using GraphicsStateScope state = new(graphics);
            ApplyStickerPose(graphics, drawRect, settings);
            graphics.DrawImage(_sticker, drawRect);
        }
        else
        {
            float size = cursorSize;
            float x = cursorPoint.X - size * anchorX;
            float y = cursorPoint.Y - size * anchorY;
            drawRect = new RectangleF(x, y, size, size);
            using GraphicsStateScope state = new(graphics);
            ApplyStickerPose(graphics, drawRect, settings);
            using SolidBrush fill = new(Color.FromArgb(248, 255, 210, 84));
            using Pen pen = new(Color.FromArgb(210, 30, 30, 30), Math.Max(2, size * 0.045f));
            graphics.FillEllipse(fill, drawRect);
            graphics.DrawEllipse(pen, drawRect);
            using SolidBrush eye = new(Color.FromArgb(230, 20, 20, 20));
            graphics.FillEllipse(eye, x + size * 0.32f, y + size * 0.40f, size * 0.10f, size * 0.14f);
            graphics.FillEllipse(eye, x + size * 0.58f, y + size * 0.40f, size * 0.10f, size * 0.14f);
        }
    }

    private void ApplyStickerPose(Graphics graphics, RectangleF rect, AppSettings settings)
    {
        if (!settings.StickerWalkFollowEnabled && !settings.StickerFrameAnimationEnabled)
        {
            return;
        }

        float motionIntensity = Math.Min(1f, _stickerWalkSpeed / Math.Max(260f, settings.CursorSize * 5f));
        float phase = _stickerWalkPhase;
        float tilt = _stickerWalkTilt;
        bool useFramePose = settings.StickerFrameAnimationEnabled;
        if (settings.StickerFrameAnimationEnabled)
        {
            float seconds = Environment.TickCount64 / 1000f;
            float timePhase = seconds * MathF.PI * 2f * Math.Max(0.2f, (float)settings.StickerWalkSpeedMultiplier * 0.82f);
            if (settings.StickerWalkFollowEnabled)
            {
                float movementBlend = Math.Clamp(motionIntensity * 1.6f, 0f, 1f);
                phase = timePhase + _stickerWalkPhase * (0.35f + movementBlend * 0.65f);
                motionIntensity = Math.Max(motionIntensity, 0.78f);
                tilt = _stickerWalkTilt * 0.45f + MathF.Sin(timePhase * 0.7f) * 0.12f;
            }
            else
            {
                phase = timePhase;
                motionIntensity = 0.92f;
                tilt = MathF.Sin(timePhase * 0.7f) * 0.16f;
            }
        }

        if (motionIntensity < 0.015f)
        {
            return;
        }

        float amplitude = (float)settings.StickerWalkAmplitudeMultiplier;
        float step = MathF.Sin(phase);
        float landing = MathF.Abs(MathF.Cos(phase));
        float sideStep = MathF.Sin(phase * 0.5f);
        if (useFramePose)
        {
            int frame = (int)MathF.Floor((phase / (MathF.PI * 2f) % 1f + 1f) % 1f * 6f);
            float carriedTilt = tilt;
            float[] stepFrames = { 0.00f, 0.92f, 0.48f, -0.24f, -0.86f, 0.38f };
            float[] landingFrames = { 1.00f, 0.22f, 0.52f, 0.96f, 0.30f, 0.62f };
            float[] tiltFrames = { -0.22f, -0.12f, 0.12f, 0.24f, 0.10f, -0.14f };
            float[] sideFrames = { -0.52f, -0.24f, 0.38f, 0.56f, 0.20f, -0.36f };
            step = stepFrames[frame];
            landing = landingFrames[frame];
            tilt = tiltFrames[frame] + carriedTilt * 0.35f;
            sideStep = sideFrames[frame];
        }

        float bob = -step * settings.CursorSize * 0.085f * motionIntensity * amplitude;
        float side = sideStep * settings.CursorSize * 0.045f * motionIntensity * amplitude;
        float squash = 1f + (landing - 0.5f) * 0.070f * motionIntensity * amplitude;
        float stretch = 1f - (landing - 0.5f) * 0.055f * motionIntensity * amplitude;
        float centerX = rect.Left + rect.Width / 2f;
        float centerY = rect.Top + rect.Height / 2f;

        graphics.TranslateTransform(centerX + side, centerY + bob);
        graphics.RotateTransform(tilt * 22f);
        graphics.ScaleTransform(squash, stretch);
        graphics.TranslateTransform(-centerX, -centerY);
    }

    private void DrawTrail(Graphics graphics, List<TrailPoint> trailPoints, Color[] colors, AppSettings settings)
    {
        DateTime now = DateTime.UtcNow;
        List<TrailPoint> active = new();
        foreach (TrailPoint point in trailPoints)
        {
            float age = (float)(now - point.StartTime).TotalSeconds;
            if (age > 0.62f)
            {
                continue;
            }

            active.Add(point);
            float progress = age / 0.62f;
            float fade = MathF.Pow(1f - progress, 1.55f);
            float size = Math.Max(5f, settings.CursorSize * (0.105f - progress * 0.045f));
            Color color = WithAlpha(colors[Math.Abs(point.Seed) % colors.Length], (int)(120 * fade));
            using SolidBrush brush = new(color);
            float offset = MathF.Sin(point.Seed * 0.73f) * size * 0.55f;
            graphics.FillEllipse(brush, point.Point.X + offset - size / 2, point.Point.Y - size * 0.70f, size, size);

            if (point.Seed % 4 == 0)
            {
                DrawStar(graphics, point.Point.X + offset + size * 0.35f, point.Point.Y - size * 0.55f, size * 0.42f, color);
            }
        }
        trailPoints.Clear();
        trailPoints.AddRange(active);
    }

    private void DrawPulses(Graphics graphics, AppSettings settings, Color[] clickColors, Color[] particleColors)
    {
        DateTime now = DateTime.UtcNow;
        foreach (PulsePoint pulse in _pulses)
        {
            float age = (float)(now - pulse.StartTime).TotalSeconds;
            if (age > 0.86f)
            {
                continue;
            }

            float progress = age / 0.86f;
            float eased = 1f - MathF.Pow(1f - progress, 3f);
            float fade = MathF.Pow(Math.Max(0, 1f - progress), 1.4f);
            float radius = Math.Max(34f, settings.CursorSize * 0.33f) * (0.58f + eased * 1.2f);
            Color ringColor = WithAlpha(clickColors[Math.Abs(pulse.Seed) % clickColors.Length], (int)(118 * fade));
            using Pen ring = new(ringColor, Math.Max(2f, settings.CursorSize * 0.020f));
            graphics.DrawEllipse(ring, pulse.Point.X - radius, pulse.Point.Y - radius, radius * 2, radius * 2);

            if (settings.EffectStyle == CursorEffectStyle.Sparkles || settings.EffectStyle == CursorEffectStyle.SparklesTrail)
            {
                DrawPulseParticles(graphics, pulse, settings, eased, fade, particleColors);
            }
        }
    }

    private void CleanupPulses(bool keepActive)
    {
        if (!keepActive)
        {
            _pulses.Clear();
            return;
        }

        DateTime now = DateTime.UtcNow;
        _pulses.RemoveAll(pulse => (now - pulse.StartTime).TotalSeconds > 0.86);
    }

    private void DrawPulseParticles(Graphics graphics, PulsePoint pulse, AppSettings settings, float eased, float fade, Color[] colors)
    {
        int count = 10;
        float baseRadius = Math.Max(34f, settings.CursorSize * 0.33f);
        float phase = (pulse.Seed % 31) * 0.09f;
        for (int index = 0; index < count; index++)
        {
            float angle = phase + index / (float)count * MathF.PI * 2f;
            float travel = baseRadius * (0.32f + eased * (1.15f + 0.12f * (index % 3)));
            PointF particle = new(
                pulse.Point.X + MathF.Cos(angle) * travel,
                pulse.Point.Y + MathF.Sin(angle) * travel);
            Color color = WithAlpha(colors[index % colors.Length], (int)(220 * fade));
            if (index % 2 == 0)
            {
                DrawStar(graphics, particle.X, particle.Y, Math.Max(5, baseRadius * 0.12f), color);
            }
            else
            {
                using SolidBrush brush = new(color);
                float size = Math.Max(4, baseRadius * 0.08f);
                graphics.FillEllipse(brush, particle.X - size / 2, particle.Y - size / 2, size, size);
            }
        }
    }

    private Color[] ColorsForRole(AppSettings settings, EffectColorRole role, EffectColorTarget target)
    {
        if (target == EffectColorTarget.Native)
        {
            if (settings.NativeEffectColorMode != EffectColorMode.Custom)
            {
                return ColorPalettes.DefaultColors();
            }

            return role switch
            {
                EffectColorRole.Trail => ColorPalettes.NormalizeColors(settings.CustomNativeTrailColors),
                EffectColorRole.Click => ColorPalettes.NormalizeColors(settings.CustomNativeClickColors),
                EffectColorRole.Particle => ColorPalettes.NormalizeColors(settings.CustomNativeParticleColors),
                _ => ColorPalettes.DefaultColors()
            };
        }

        if (settings.EffectColorMode != EffectColorMode.Custom)
        {
            return _autoStickerColors.Length >= 4 ? _autoStickerColors : ColorPalettes.DefaultColors();
        }

        return role switch
        {
            EffectColorRole.Trail => ColorPalettes.NormalizeColors(settings.CustomTrailColors),
            EffectColorRole.Click => ColorPalettes.NormalizeColors(settings.CustomClickColors),
            EffectColorRole.Particle => ColorPalettes.NormalizeColors(settings.CustomParticleColors),
            _ => ColorPalettes.DefaultColors()
        };
    }

    private static bool ShouldDrawTrail(CursorEffectStyle style)
    {
        return style == CursorEffectStyle.Trail || style == CursorEffectStyle.SparklesTrail;
    }

    private static bool ShouldDrawClick(CursorEffectStyle style)
    {
        return style == CursorEffectStyle.Rings ||
            style == CursorEffectStyle.Sparkles ||
            style == CursorEffectStyle.SparklesTrail;
    }

    private static void DrawStar(Graphics graphics, float centerX, float centerY, float radius, Color color)
    {
        PointF[] points = new PointF[8];
        for (int i = 0; i < points.Length; i++)
        {
            float angle = i * MathF.PI / 4f - MathF.PI / 2f;
            float distance = i % 2 == 0 ? radius : radius * 0.42f;
            points[i] = new PointF(centerX + MathF.Cos(angle) * distance, centerY + MathF.Sin(angle) * distance);
        }

        using SolidBrush brush = new(color);
        graphics.FillPolygon(brush, points);
    }

    private static Color WithAlpha(Color color, int alpha)
    {
        return Color.FromArgb(Math.Clamp(alpha, 0, 255), color.R, color.G, color.B);
    }

    private static Color[] ExtractEffectColors(Image image)
    {
        try
        {
            int sampleWidth = Math.Clamp(image.Width, 1, 140);
            int sampleHeight = Math.Clamp(image.Height, 1, 140);
            using Bitmap sample = new(sampleWidth, sampleHeight, PixelFormat.Format32bppArgb);
            using (Graphics graphics = Graphics.FromImage(sample))
            {
                graphics.Clear(Color.Transparent);
                graphics.InterpolationMode = InterpolationMode.HighQualityBicubic;
                graphics.DrawImage(image, 0, 0, sampleWidth, sampleHeight);
            }

            Dictionary<int, ColorBucket> buckets = new();
            for (int y = 0; y < sample.Height; y += 2)
            {
                for (int x = 0; x < sample.Width; x += 2)
                {
                    Color pixel = sample.GetPixel(x, y);
                    if (pixel.A < 128)
                    {
                        continue;
                    }

                    bool nearWhite = pixel.R > 242 && pixel.G > 242 && pixel.B > 242;
                    if (nearWhite)
                    {
                        continue;
                    }

                    int key = (pixel.R / 32) << 10 | (pixel.G / 32) << 5 | (pixel.B / 32);
                    if (!buckets.TryGetValue(key, out ColorBucket? bucket))
                    {
                        bucket = new ColorBucket();
                        buckets[key] = bucket;
                    }
                    bucket.Add(pixel);
                }
            }

            List<ColorBucket> ranked = buckets.Values
                .OrderByDescending(bucket => bucket.Score)
                .ToList();
            List<Color> selected = new();
            int darkCount = 0;
            foreach (ColorBucket bucket in ranked)
            {
                Color color = bucket.AverageColor;
                bool isDark = color.GetBrightness() < 0.20f;
                if (isDark && darkCount >= 1)
                {
                    continue;
                }

                bool tooClose = selected.Any(existing => ColorDistance(existing, color) < 46);
                if (tooClose)
                {
                    continue;
                }

                selected.Add(color);
                if (isDark)
                {
                    darkCount++;
                }
                if (selected.Count >= 4)
                {
                    break;
                }
            }

            foreach (Color fallback in ColorPalettes.DefaultColors())
            {
                if (selected.Count >= 4)
                {
                    break;
                }
                selected.Add(fallback);
            }

            return selected.ToArray();
        }
        catch
        {
            return ColorPalettes.DefaultColors();
        }
    }

    private static double ColorDistance(Color a, Color b)
    {
        int dr = a.R - b.R;
        int dg = a.G - b.G;
        int db = a.B - b.B;
        return Math.Sqrt(dr * dr + dg * dg + db * db);
    }

    private void ResetStickerFrameState()
    {
        _stickerFrameDimension = null;
        _stickerFrameDelaysMs = Array.Empty<int>();
        _stickerFrameCount = 1;
        _stickerFrameIndex = 0;
        _lastStickerFrameUpdate = DateTime.UtcNow;

        if (_sticker is null)
        {
            return;
        }

        try
        {
            Guid[] frameDimensions = _sticker.FrameDimensionsList;
            if (frameDimensions.Length == 0)
            {
                return;
            }

            FrameDimension dimension = new(frameDimensions[0]);
            int frameCount = _sticker.GetFrameCount(dimension);
            if (frameCount <= 1)
            {
                return;
            }

            _stickerFrameDimension = dimension;
            _stickerFrameCount = frameCount;
            _stickerFrameDelaysMs = ReadFrameDelays(_sticker, frameCount);
            _sticker.SelectActiveFrame(dimension, 0);
        }
        catch
        {
            _stickerFrameDimension = null;
            _stickerFrameDelaysMs = Array.Empty<int>();
            _stickerFrameCount = 1;
            _stickerFrameIndex = 0;
        }
    }

    private void UpdateStickerFrame(AppSettings settings)
    {
        if (_sticker is null || _stickerFrameDimension is null || _stickerFrameCount <= 1)
        {
            return;
        }

        if (!settings.StickerFrameAnimationEnabled)
        {
            if (_stickerFrameIndex != 0)
            {
                _stickerFrameIndex = 0;
                TrySelectStickerFrame(0);
            }
            _lastStickerFrameUpdate = DateTime.UtcNow;
            return;
        }

        DateTime now = DateTime.UtcNow;
        int delay = _stickerFrameDelaysMs.Length > _stickerFrameIndex
            ? _stickerFrameDelaysMs[_stickerFrameIndex]
            : 90;
        double speed = Math.Clamp(settings.StickerWalkSpeedMultiplier, 0.35, 2.0);
        double scaledDelay = Math.Max(24, delay / speed);
        double elapsed = (now - _lastStickerFrameUpdate).TotalMilliseconds;
        if (elapsed < scaledDelay)
        {
            return;
        }

        int steps = Math.Max(1, (int)Math.Floor(elapsed / scaledDelay));
        _stickerFrameIndex = (_stickerFrameIndex + steps) % _stickerFrameCount;
        TrySelectStickerFrame(_stickerFrameIndex);
        _lastStickerFrameUpdate = now;
    }

    private void TrySelectStickerFrame(int index)
    {
        if (_sticker is null || _stickerFrameDimension is null)
        {
            return;
        }

        try
        {
            _sticker.SelectActiveFrame(_stickerFrameDimension, index);
        }
        catch
        {
            _stickerFrameDimension = null;
            _stickerFrameCount = 1;
            _stickerFrameIndex = 0;
            _stickerFrameDelaysMs = Array.Empty<int>();
        }
    }

    private static int[] ReadFrameDelays(Image image, int frameCount)
    {
        int[] delays = Enumerable.Repeat(90, frameCount).ToArray();
        try
        {
            const int frameDelayPropertyId = 0x5100;
            PropertyItem property = image.GetPropertyItem(frameDelayPropertyId);
            byte[] bytes = property.Value;
            for (int index = 0; index < frameCount && index * 4 + 3 < bytes.Length; index++)
            {
                int hundredths = BitConverter.ToInt32(bytes, index * 4);
                delays[index] = Math.Clamp(hundredths * 10, 24, 800);
            }
        }
        catch
        {
            // Static images and some runtimes do not expose GIF frame delays.
        }
        return delays;
    }

    private void UpdateLayeredWindow(Bitmap bitmap, Point screenLocation)
    {
        IntPtr screenDc = NativeMethods.GetDC(IntPtr.Zero);
        IntPtr memoryDc = NativeMethods.CreateCompatibleDC(screenDc);
        IntPtr bitmapHandle = bitmap.GetHbitmap(Color.FromArgb(0));
        IntPtr oldBitmap = NativeMethods.SelectObject(memoryDc, bitmapHandle);

        try
        {
            NativeMethods.Point destination = new(screenLocation.X, screenLocation.Y);
            NativeMethods.Size size = new(bitmap.Width, bitmap.Height);
            NativeMethods.Point source = new(0, 0);
            NativeMethods.BlendFunction blend = new()
            {
                BlendOp = NativeMethods.AC_SRC_OVER,
                SourceConstantAlpha = 255,
                AlphaFormat = NativeMethods.AC_SRC_ALPHA
            };

            NativeMethods.UpdateLayeredWindow(
                Handle,
                screenDc,
                ref destination,
                ref size,
                memoryDc,
                ref source,
                0,
                ref blend,
                NativeMethods.ULW_ALPHA);
        }
        finally
        {
            NativeMethods.SelectObject(memoryDc, oldBitmap);
            NativeMethods.DeleteObject(bitmapHandle);
            NativeMethods.DeleteDC(memoryDc);
            NativeMethods.ReleaseDC(IntPtr.Zero, screenDc);
        }
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _sticker?.Dispose();
            _stickerStream?.Dispose();
        }
        base.Dispose(disposing);
    }

    private readonly record struct TrailPoint(PointF Point, DateTime StartTime, int Seed);
    private readonly record struct PulsePoint(PointF Point, DateTime StartTime, int Seed);

    private sealed class GraphicsStateScope : IDisposable
    {
        private readonly Graphics _graphics;
        private readonly GraphicsState _state;

        public GraphicsStateScope(Graphics graphics)
        {
            _graphics = graphics;
            _state = graphics.Save();
        }

        public void Dispose()
        {
            _graphics.Restore(_state);
        }
    }

    private sealed class ColorBucket
    {
        private long _red;
        private long _green;
        private long _blue;

        public int Count { get; private set; }

        public Color AverageColor => Count <= 0
            ? Color.Black
            : Color.FromArgb(255, (int)(_red / Count), (int)(_green / Count), (int)(_blue / Count));

        public double Score
        {
            get
            {
                Color color = AverageColor;
                double saturation = color.GetSaturation();
                double brightness = color.GetBrightness();
                double darkPenalty = brightness < 0.16 ? 0.36 : 1.0;
                return Count * (0.42 + saturation) * darkPenalty;
            }
        }

        public void Add(Color color)
        {
            _red += color.R;
            _green += color.G;
            _blue += color.B;
            Count++;
        }
    }
}

internal sealed class MouseHook : IDisposable
{
    private const int WH_MOUSE_LL = 14;
    private const int WM_LBUTTONDOWN = 0x0201;
    private const int WM_RBUTTONDOWN = 0x0204;
    private const int WM_MBUTTONDOWN = 0x0207;
    private readonly NativeMethods.HookProc _hookProc;
    private IntPtr _hookHandle;

    public event EventHandler? Clicked;

    public MouseHook()
    {
        _hookProc = HookCallback;
    }

    public void Start()
    {
        if (_hookHandle != IntPtr.Zero)
        {
            return;
        }

        _hookHandle = NativeMethods.SetWindowsHookEx(WH_MOUSE_LL, _hookProc, NativeMethods.GetModuleHandle(null), 0);
    }

    private IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0 &&
            (wParam == (IntPtr)WM_LBUTTONDOWN ||
             wParam == (IntPtr)WM_RBUTTONDOWN ||
             wParam == (IntPtr)WM_MBUTTONDOWN))
        {
            Clicked?.Invoke(this, EventArgs.Empty);
        }

        return NativeMethods.CallNextHookEx(_hookHandle, nCode, wParam, lParam);
    }

    public void Dispose()
    {
        if (_hookHandle != IntPtr.Zero)
        {
            NativeMethods.UnhookWindowsHookEx(_hookHandle);
            _hookHandle = IntPtr.Zero;
        }
    }
}

internal static class NativeMethods
{
    public const int WS_EX_LAYERED = 0x00080000;
    public const int WS_EX_TRANSPARENT = 0x00000020;
    public const int WS_EX_TOOLWINDOW = 0x00000080;
    public const int WS_EX_NOACTIVATE = 0x08000000;
    public const int ULW_ALPHA = 0x00000002;
    public const byte AC_SRC_OVER = 0x00;
    public const byte AC_SRC_ALPHA = 0x01;

    public delegate IntPtr HookProc(int nCode, IntPtr wParam, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    public struct Point
    {
        public int X;
        public int Y;

        public Point(int x, int y)
        {
            X = x;
            Y = y;
        }
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct Size
    {
        public int Cx;
        public int Cy;

        public Size(int cx, int cy)
        {
            Cx = cx;
            Cy = cy;
        }
    }

    [StructLayout(LayoutKind.Sequential, Pack = 1)]
    public struct BlendFunction
    {
        public byte BlendOp;
        public byte BlendFlags;
        public byte SourceConstantAlpha;
        public byte AlphaFormat;
    }

    [DllImport("user32.dll", ExactSpelling = true, SetLastError = true)]
    public static extern IntPtr GetDC(IntPtr hWnd);

    [DllImport("user32.dll", ExactSpelling = true)]
    public static extern int ReleaseDC(IntPtr hWnd, IntPtr hDc);

    [DllImport("gdi32.dll", ExactSpelling = true, SetLastError = true)]
    public static extern IntPtr CreateCompatibleDC(IntPtr hDc);

    [DllImport("gdi32.dll", ExactSpelling = true)]
    public static extern bool DeleteDC(IntPtr hdc);

    [DllImport("gdi32.dll", ExactSpelling = true)]
    public static extern IntPtr SelectObject(IntPtr hdc, IntPtr hgdiobj);

    [DllImport("gdi32.dll", ExactSpelling = true)]
    public static extern bool DeleteObject(IntPtr hObject);

    [DllImport("user32.dll", ExactSpelling = true, SetLastError = true)]
    public static extern bool UpdateLayeredWindow(
        IntPtr hwnd,
        IntPtr hdcDst,
        ref Point pptDst,
        ref Size psize,
        IntPtr hdcSrc,
        ref Point pptSrc,
        int crKey,
        ref BlendFunction pblend,
        int dwFlags);

    [DllImport("user32.dll")]
    public static extern int ShowCursor(bool bShow);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern IntPtr SetWindowsHookEx(int idHook, HookProc lpfn, IntPtr hMod, uint dwThreadId);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool UnhookWindowsHookEx(IntPtr hhk);

    [DllImport("user32.dll")]
    public static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);

    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    public static extern IntPtr GetModuleHandle(string? lpModuleName);
}
