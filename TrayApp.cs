using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using IdlePulse.Models;
using IdlePulse.Services;
using IdlePulse.Views;
using Hardcodet.Wpf.TaskbarNotification;
using Wpf.Ui.Controls;
using ContextMenu = System.Windows.Controls.ContextMenu;
using MenuItem = System.Windows.Controls.MenuItem;
using TextBlock = System.Windows.Controls.TextBlock;
using StackPanel = System.Windows.Controls.StackPanel;
using Orientation = System.Windows.Controls.Orientation;

namespace IdlePulse;

public sealed class TrayApp : IDisposable
{
    private readonly ConfigStore _store = new();
    private TaskbarIcon? _trayIcon;
    private IdleMonitor? _monitor;
    private AppConfig _config = new();
    private SettingsWindow? _settingsWindow;
    private CountdownWindow? _countdownWindow;

    private MenuItem? _statusHeaderItem;
    private TextBlock? _statusHeaderTitle;
    private TextBlock? _statusHeaderDetail;
    private MenuItem? _toggleItem;
    private TextBlock? _toggleItemText;
    private SymbolIcon? _toggleItemIcon;

    private static readonly Brush ActiveBrush = new SolidColorBrush(Color.FromRgb(0x22, 0xC5, 0x5E));
    private static readonly Brush DisabledBrush = new SolidColorBrush(Color.FromRgb(0x9C, 0xA3, 0xAF));

    public void Start()
    {
        _config = _store.Load();

        _trayIcon = new TaskbarIcon
        {
            ToolTipText = "IdlePulse",
            IconSource = new BitmapImage(new Uri("pack://application:,,,/Assets/IdlePulse.ico", UriKind.Absolute)),
            ContextMenu = BuildContextMenu()
        };
        _trayIcon.TrayMouseDoubleClick += (_, _) => OpenSettings();
        _trayIcon.ContextMenu.Opened += (_, _) => RefreshContextMenu();

        _monitor = new IdleMonitor(_config);
        _monitor.IdleThresholdReached += OnIdleThresholdReached;
        _monitor.Start();

        UpdateTooltip();
    }

    private ContextMenu BuildContextMenu()
    {
        var menu = new ContextMenu();

        // Status header (non-clickable, just info)
        _statusHeaderTitle = new TextBlock
        {
            Text = "Active",
            FontWeight = FontWeights.SemiBold,
            FontSize = 13
        };
        _statusHeaderDetail = new TextBlock
        {
            Text = "Idle 0s · fires in 30m",
            FontSize = 11,
            Opacity = 0.65,
            Margin = new Thickness(0, 2, 0, 0)
        };

        _statusHeaderItem = new MenuItem
        {
            Header = new StackPanel
            {
                Orientation = Orientation.Vertical,
                Margin = new Thickness(2, 4, 2, 4),
                Children = { _statusHeaderTitle, _statusHeaderDetail }
            },
            IsEnabled = false,
            StaysOpenOnClick = true
        };
        menu.Items.Add(_statusHeaderItem);

        menu.Items.Add(new Separator());

        // Enable / Disable
        _toggleItemIcon = new SymbolIcon
        {
            Symbol = SymbolRegular.Pause24,
            FontSize = 14,
            Margin = new Thickness(0, 0, 8, 0)
        };
        _toggleItemText = new TextBlock
        {
            Text = "Disable",
            VerticalAlignment = VerticalAlignment.Center
        };
        _toggleItem = new MenuItem
        {
            Header = new StackPanel
            {
                Orientation = Orientation.Horizontal,
                Children = { _toggleItemIcon, _toggleItemText }
            }
        };
        _toggleItem.Click += (_, _) => ToggleEnabled();
        menu.Items.Add(_toggleItem);

        // Settings
        var settingsItem = new MenuItem
        {
            Header = new StackPanel
            {
                Orientation = Orientation.Horizontal,
                Children =
                {
                    new SymbolIcon { Symbol = SymbolRegular.Settings24, FontSize = 14, Margin = new Thickness(0, 0, 8, 0) },
                    new TextBlock { Text = "Settings…", VerticalAlignment = VerticalAlignment.Center }
                }
            }
        };
        settingsItem.Click += (_, _) => OpenSettings();
        menu.Items.Add(settingsItem);

        menu.Items.Add(new Separator());

        // Exit
        var exitItem = new MenuItem
        {
            Header = new StackPanel
            {
                Orientation = Orientation.Horizontal,
                Children =
                {
                    new SymbolIcon { Symbol = SymbolRegular.SignOut24, FontSize = 14, Margin = new Thickness(0, 0, 8, 0) },
                    new TextBlock { Text = "Exit", VerticalAlignment = VerticalAlignment.Center }
                }
            }
        };
        exitItem.Click += (_, _) => Application.Current.Shutdown();
        menu.Items.Add(exitItem);

        return menu;
    }

    private void RefreshContextMenu()
    {
        if (_statusHeaderTitle == null || _statusHeaderDetail == null
            || _toggleItemText == null || _toggleItemIcon == null) return;

        var thresholdText = FormatDuration(TimeSpan.FromSeconds(_config.IdleSeconds));

        if (_config.Enabled)
        {
            _statusHeaderTitle.Text = "Active";
            _statusHeaderTitle.Foreground = ActiveBrush;
            _statusHeaderDetail.Text = $"{_config.Action} after {thresholdText} idle";

            _toggleItemText.Text = "Disable";
            _toggleItemIcon.Symbol = SymbolRegular.Pause24;
        }
        else
        {
            _statusHeaderTitle.Text = "Paused";
            _statusHeaderTitle.Foreground = DisabledBrush;
            _statusHeaderDetail.Text = $"Would {_config.Action.ToString().ToLowerInvariant()} after {thresholdText}";

            _toggleItemText.Text = "Enable";
            _toggleItemIcon.Symbol = SymbolRegular.Play24;
        }
    }

    private void ToggleEnabled()
    {
        _config.Enabled = !_config.Enabled;
        _store.Save(_config);
        _monitor?.UpdateConfig(_config);
        _monitor?.Reset();
        if (_config.Enabled) _monitor?.Start(); else _monitor?.Stop();
        UpdateTooltip();
        if (_settingsWindow != null)
        {
            _settingsWindow.ApplyExternalConfig(_config);
        }
    }

    public void OpenSettingsForTest() => OpenSettings();

    private void OpenSettings()
    {
        if (_settingsWindow != null)
        {
            _settingsWindow.Activate();
            return;
        }

        _settingsWindow = new SettingsWindow(_store, _config);
        _settingsWindow.ConfigSaved += (_, cfg) =>
        {
            _config = cfg;
            _monitor?.UpdateConfig(_config);
            _monitor?.Reset();
            if (_config.Enabled) _monitor?.Start(); else _monitor?.Stop();
            UpdateTooltip();
        };
        _settingsWindow.Closed += (_, _) => _settingsWindow = null;
        _settingsWindow.Show();
    }

    private void OnIdleThresholdReached(object? sender, EventArgs e)
    {
        if (_countdownWindow != null) return;

        _monitor?.SuspendFor(TimeSpan.FromMinutes(5));

        _countdownWindow = new CountdownWindow(_config.Action, _config.WarningSeconds);
        _countdownWindow.Closed += (_, _) =>
        {
            var fired = _countdownWindow?.Fired ?? false;
            var action = _config.Action;
            _countdownWindow = null;
            _monitor?.Reset();
            if (fired)
            {
                PowerActionExecutor.Execute(action);
            }
        };
        _countdownWindow.Show();
        _countdownWindow.Activate();
    }

    private void UpdateTooltip()
    {
        if (_trayIcon == null) return;
        _trayIcon.ToolTipText = _config.Enabled
            ? $"IdlePulse — {_config.Action} after {FormatDuration(TimeSpan.FromSeconds(_config.IdleSeconds))} idle"
            : "IdlePulse — paused";
    }

    private static string FormatDuration(TimeSpan ts)
    {
        if (ts.TotalSeconds < 1) return "0s";
        var parts = new List<string>();
        if (ts.Hours > 0) parts.Add($"{ts.Hours}h");
        if (ts.Minutes > 0) parts.Add($"{ts.Minutes}m");
        if (ts.Seconds > 0 || parts.Count == 0) parts.Add($"{ts.Seconds}s");
        return string.Join(" ", parts);
    }

    public void Dispose()
    {
        _monitor?.Dispose();
        _trayIcon?.Dispose();
    }
}
