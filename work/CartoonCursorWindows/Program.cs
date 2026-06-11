using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
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
    public int CursorSize { get; set; } = 128;
    public CursorEffectStyle EffectStyle { get; set; } = CursorEffectStyle.SparklesTrail;
    public string? CurrentStickerPath { get; set; }
    public List<StickerItem> StickerLibrary { get; set; } = new();
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
            return JsonSerializer.Deserialize<AppSettings>(json, Options) ?? new AppSettings();
        }
        catch
        {
            return new AppSettings();
        }
    }

    public static void Save(AppSettings settings)
    {
        Directory.CreateDirectory(AppPaths.Root);
        File.WriteAllText(AppPaths.SettingsPath, JsonSerializer.Serialize(settings, Options));
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

        menu.Items.Add(BuildStickerManagerMenu());
        menu.Items.Add(BuildSizeMenu());
        menu.Items.Add(BuildEffectMenu());

        menu.Items.Add(new ToolStripMenuItem("Hide Native Cursor (Best Effort)", null, (_, _) =>
        {
            _settings.HideNativeCursor = !_settings.HideNativeCursor;
            SaveAndRefresh();
        })
        {
            Checked = _settings.HideNativeCursor
        });

        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(new ToolStripMenuItem("Quit Cartoon Cursor", null, (_, _) => ExitThread()));

        _notifyIcon.ContextMenuStrip = menu;
        oldMenu?.Dispose();
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

internal sealed class OverlayForm : Form
{
    private readonly List<TrailPoint> _trailPoints = new();
    private readonly List<PulsePoint> _pulses = new();
    private readonly Color[] _effectColors =
    {
        Color.FromArgb(255, 255, 92, 138),
        Color.FromArgb(255, 255, 198, 64),
        Color.FromArgb(255, 78, 178, 255),
        Color.FromArgb(255, 196, 104, 255)
    };

    private Image? _sticker;
    private Stream? _stickerStream;
    private Point _lastCursorPoint;
    private DateTime _lastTrailSample = DateTime.MinValue;
    private bool _hasCursorPoint;

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
        if (_sticker is not null && ImageAnimator.CanAnimate(_sticker))
        {
            ImageAnimator.StopAnimate(_sticker, OnFrameChanged);
        }

        _sticker?.Dispose();
        _stickerStream?.Dispose();
        _sticker = image;
        _stickerStream = backingStream;

        if (_sticker is not null && ImageAnimator.CanAnimate(_sticker))
        {
            ImageAnimator.Animate(_sticker, OnFrameChanged);
        }
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

        if (!settings.Enabled && settings.EffectStyle == CursorEffectStyle.Off)
        {
            Hide();
            return;
        }

        if (!Visible)
        {
            Show();
        }

        PointF localCursor = new(screenCursor.X - bounds.Left, screenCursor.Y - bounds.Top);
        MaybeAddTrail(localCursor, settings);

        using Bitmap canvas = new(Math.Max(1, bounds.Width), Math.Max(1, bounds.Height), PixelFormat.Format32bppArgb);
        using Graphics graphics = Graphics.FromImage(canvas);
        graphics.Clear(Color.Transparent);
        graphics.SmoothingMode = SmoothingMode.AntiAlias;
        graphics.InterpolationMode = InterpolationMode.HighQualityBicubic;

        DrawTrail(graphics, settings);
        DrawPulses(graphics, settings);

        if (settings.Enabled)
        {
            DrawSticker(graphics, localCursor, settings.CursorSize);
        }

        UpdateLayeredWindow(canvas, bounds.Location);
    }

    private void MaybeAddTrail(PointF point, AppSettings settings)
    {
        if (settings.EffectStyle != CursorEffectStyle.Trail && settings.EffectStyle != CursorEffectStyle.SparklesTrail)
        {
            _trailPoints.Clear();
            _hasCursorPoint = false;
            return;
        }

        DateTime now = DateTime.UtcNow;
        if (_hasCursorPoint)
        {
            float dx = point.X - _lastCursorPoint.X;
            float dy = point.Y - _lastCursorPoint.Y;
            double distance = Math.Sqrt(dx * dx + dy * dy);
            if (distance >= 5 || (now - _lastTrailSample).TotalMilliseconds >= 45)
            {
                _trailPoints.Add(new TrailPoint(point, now, Environment.TickCount));
                _lastTrailSample = now;
            }
        }

        _lastCursorPoint = Point.Round(point);
        _hasCursorPoint = true;
        if (_trailPoints.Count > 48)
        {
            _trailPoints.RemoveRange(0, _trailPoints.Count - 48);
        }
    }

    private void DrawSticker(Graphics graphics, PointF cursorPoint, int cursorSize)
    {
        if (_sticker is not null)
        {
            if (ImageAnimator.CanAnimate(_sticker))
            {
                ImageAnimator.UpdateFrames(_sticker);
            }

            float maxEdge = Math.Max(_sticker.Width, _sticker.Height);
            float scale = cursorSize / Math.Max(1, maxEdge);
            float width = _sticker.Width * scale;
            float height = _sticker.Height * scale;
            float x = cursorPoint.X - width * 0.08f;
            float y = cursorPoint.Y - height * 0.92f;
            graphics.DrawImage(_sticker, x, y, width, height);
        }
        else
        {
            float size = cursorSize;
            float x = cursorPoint.X - size * 0.08f;
            float y = cursorPoint.Y - size * 0.92f;
            RectangleF rect = new(x, y, size, size);
            using SolidBrush fill = new(Color.FromArgb(248, 255, 210, 84));
            using Pen pen = new(Color.FromArgb(210, 30, 30, 30), Math.Max(2, size * 0.045f));
            graphics.FillEllipse(fill, rect);
            graphics.DrawEllipse(pen, rect);
            using SolidBrush eye = new(Color.FromArgb(230, 20, 20, 20));
            graphics.FillEllipse(eye, x + size * 0.32f, y + size * 0.40f, size * 0.10f, size * 0.14f);
            graphics.FillEllipse(eye, x + size * 0.58f, y + size * 0.40f, size * 0.10f, size * 0.14f);
        }
    }

    private void DrawTrail(Graphics graphics, AppSettings settings)
    {
        if (settings.EffectStyle != CursorEffectStyle.Trail && settings.EffectStyle != CursorEffectStyle.SparklesTrail)
        {
            _trailPoints.Clear();
            return;
        }

        DateTime now = DateTime.UtcNow;
        List<TrailPoint> active = new();
        foreach (TrailPoint point in _trailPoints)
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
            Color color = WithAlpha(_effectColors[Math.Abs(point.Seed) % _effectColors.Length], (int)(120 * fade));
            using SolidBrush brush = new(color);
            float offset = MathF.Sin(point.Seed * 0.73f) * size * 0.55f;
            graphics.FillEllipse(brush, point.Point.X + offset - size / 2, point.Point.Y - size * 0.70f, size, size);

            if (point.Seed % 4 == 0)
            {
                DrawStar(graphics, point.Point.X + offset + size * 0.35f, point.Point.Y - size * 0.55f, size * 0.42f, color);
            }
        }
        _trailPoints.Clear();
        _trailPoints.AddRange(active);
    }

    private void DrawPulses(Graphics graphics, AppSettings settings)
    {
        if (settings.EffectStyle != CursorEffectStyle.Rings &&
            settings.EffectStyle != CursorEffectStyle.Sparkles &&
            settings.EffectStyle != CursorEffectStyle.SparklesTrail)
        {
            _pulses.Clear();
            return;
        }

        DateTime now = DateTime.UtcNow;
        List<PulsePoint> active = new();
        foreach (PulsePoint pulse in _pulses)
        {
            float age = (float)(now - pulse.StartTime).TotalSeconds;
            if (age > 0.86f)
            {
                continue;
            }

            active.Add(pulse);
            float progress = age / 0.86f;
            float eased = 1f - MathF.Pow(1f - progress, 3f);
            float fade = MathF.Pow(Math.Max(0, 1f - progress), 1.4f);
            float radius = Math.Max(34f, settings.CursorSize * 0.33f) * (0.58f + eased * 1.2f);
            using Pen ring = new(WithAlpha(_effectColors[0], (int)(118 * fade)), Math.Max(2f, settings.CursorSize * 0.020f));
            graphics.DrawEllipse(ring, pulse.Point.X - radius, pulse.Point.Y - radius, radius * 2, radius * 2);

            if (settings.EffectStyle == CursorEffectStyle.Sparkles || settings.EffectStyle == CursorEffectStyle.SparklesTrail)
            {
                DrawPulseParticles(graphics, pulse, settings, eased, fade);
            }
        }
        _pulses.Clear();
        _pulses.AddRange(active);
    }

    private void DrawPulseParticles(Graphics graphics, PulsePoint pulse, AppSettings settings, float eased, float fade)
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
            Color color = WithAlpha(_effectColors[index % _effectColors.Length], (int)(220 * fade));
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

    private void OnFrameChanged(object? sender, EventArgs e)
    {
        // The main timer redraws the layered window.
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
            if (_sticker is not null && ImageAnimator.CanAnimate(_sticker))
            {
                ImageAnimator.StopAnimate(_sticker, OnFrameChanged);
            }
            _sticker?.Dispose();
            _stickerStream?.Dispose();
        }
        base.Dispose(disposing);
    }

    private readonly record struct TrailPoint(PointF Point, DateTime StartTime, int Seed);
    private readonly record struct PulsePoint(PointF Point, DateTime StartTime, int Seed);
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
