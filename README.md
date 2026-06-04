# IdlePulse

A small Windows tray utility that **shuts down, sleeps, hibernates, or locks your PC after a period of inactivity** — with a configurable warning countdown so you can cancel.

Windows has a built-in idle-*sleep* option, but no clean built-in *idle-shutdown* option. IdlePulse fills that gap with a Fluent UI, real idle detection (`GetLastInputInfo`), and smart skips for fullscreen / presentation modes.

## Features

### Idle action
- Trigger **Shutdown / Sleep / Hibernate / Lock** after no keyboard or mouse input for a configurable threshold
- Threshold expressed as hours + minutes + seconds (default 30 minutes)
- **Warning countdown** with a centered progress ring and big Cancel button — set the warning to 5–300s; the action only fires if you don't cancel
- **Graceful shutdown** via `shutdown.exe /s /t 0` (also covers privilege handling automatically)
- Sleep / Hibernate via `SetSuspendState`, Lock via `LockWorkStation`

### Smart skips
- **Skip when a fullscreen app is running** (games, video) — uses `SHQueryUserNotificationState`
- **Skip during presentation mode** (PowerPoint, Zoom screen-share, etc.)
- **Auto-pause on session lock** and re-enable on unlock with a 10-second grace period
- **Cooldown after wake** — after resuming from sleep, idle monitoring is paused for 1 minute so the device doesn't immediately re-trigger

### Tray UI
- Right-click menu shows live state (Active / Paused), the configured action, and threshold
- One-click **Enable / Disable** toggle directly in the tray menu
- Settings… and Exit entries with Fluent symbol icons
- **Single-instance** enforced via a named Mutex; second launch is rejected with a Fluent dialog

### Settings window (main)
- Live status banner with state icon, headline, action summary, and a progress bar that fills as idle approaches threshold
- Action picker (Combo with icons), idle threshold (hr/min/sec inputs), warning seconds, smart-skip toggles, autostart toggle
- **Save button gated on dirty state** — your edits are only applied when you click Save (no live drift)
- "Click Save to apply" footer summarises the new config in plain English (e.g. *"Lock after 10s idle, with a 30s warning"*)
- Gear button opens the Settings (App-level) dialog

### Settings (App-level)
- **Idle scan interval** (1–60s) — how often `GetLastInputInfo` is polled
- **Configuration file** — read-only path display + Open folder + Copy path
- **Crash log** — last-modified timestamp, size, Open log, Clear log
- **Clear startup entries** — safely scans `HKCU\...\Run` and the Startup folder for IdlePulse entries and removes them
- **Reset app settings** — restores scan interval to default; preserves your idle-trigger settings
- **About** — version, runtime, executable path

## Requirements

- Windows 10 (1809+) or Windows 11
- x64

The published binary is **self-contained** — no .NET install needed on the target machine.

## Install

### Option A — Installer (recommended)

Download `IdlePulse-Setup-<version>.exe` from the [Releases page](https://github.com/TheCSir/IdlePulse/releases) and run it. The installer:

- Lets you pick **per-user** (no admin) or **per-machine** (admin) install at runtime
- Always creates a Start Menu shortcut
- Optional **Desktop shortcut**
- Optional **Run at Windows startup** (sets the per-user `HKCU\...\Run` registry value)
- Optional **Launch IdlePulse after install**
- Registers an entry in **Settings → Apps** for clean uninstall (also kills any running instance and removes autostart entries)

### Option B — Portable

Grab `IdlePulse.exe` from `publish/` after building (see below) or attach it from a release. Drop it anywhere and double-click — the tray icon appears bottom-right.

To make the portable build start with Windows: open Settings → enable "Run when Windows starts" (writes `HKCU\Software\Microsoft\Windows\CurrentVersion\Run\IdlePulse`).

## Build from source

```powershell
# Requires .NET 10 SDK (https://dotnet.microsoft.com/download/dotnet/10.0)
dotnet publish IdlePulse.csproj -c Release -o publish
```

Outputs a single self-contained `IdlePulse.exe` (~75 MB, includes the .NET runtime).

### Building the installer

Requires [Inno Setup 6.x or 7.x](https://jrsoftware.org/isinfo.php) (`ISCC.exe`). The script auto-discovers `ISCC.exe` from common paths or `$env:ISCC`.

```powershell
# Publishes the app then compiles the installer
powershell -ExecutionPolicy Bypass -File tools\build-installer.ps1
```

Output: `installer\dist\IdlePulse-Setup-<version>.exe` (~70 MB)

### Regenerating the icon

The `.ico` is built from the brand source PNG (`%USERPROFILE%\Downloads\generated-image.png` by default; override via `$env:IDLEPULSE_SOURCE`). Re-run if the source changes:

```powershell
powershell -ExecutionPolicy Bypass -File tools\generate-icon.ps1   # writes Assets\IdlePulse.ico
powershell -ExecutionPolicy Bypass -File tools\generate-png.ps1    # writes Assets\IdlePulse-512.png
```

## Tech stack

- **.NET 10** + **WPF** with [WPF-UI](https://github.com/lepoco/wpfui) for Fluent design (Mica backdrop, dark theme, rounded corners)
- **[Hardcodet.NotifyIcon.Wpf](https://github.com/hardcodet/wpf-notifyicon)** for the tray icon
- **P/Invoke** to Win32 (`GetLastInputInfo`, `SetSuspendState`, `LockWorkStation`, `SHQueryUserNotificationState`)
- **Single-file, self-contained publish** for portable / installer distribution
- **[Inno Setup](https://jrsoftware.org/isinfo.php)** for the installer

## Configuration

Settings are saved as JSON at `%APPDATA%\IdlePulse\config.json`. Crash logs (if any) at `%APPDATA%\IdlePulse\crash.log`. The App Settings dialog has buttons to open these locations or copy the path.

If you previously used the older `AutoShutdown` build, IdlePulse will:
- Auto-import `%APPDATA%\AutoShutdown\config.json` on first launch
- Remove the legacy `HKCU\...\Run\AutoShutdown` registry value

so your old settings carry over and the old build doesn't keep starting alongside the new one.

## How idle is detected

Polls `GetLastInputInfo` (Win32) every N seconds (configurable, default 5). This is the same API Windows itself uses for idle-sleep — millisecond-precise, keyboard + mouse only, doesn't watch CPU/disk (which is what makes Task Scheduler's idle trigger unreliable). Polling cost is effectively zero — one Win32 call + integer compare.

Before firing, IdlePulse also calls `SHQueryUserNotificationState` to skip when the user is presenting, in fullscreen, or otherwise marked busy by Windows.

## Performance

- **CPU:** effectively 0% at rest (one P/Invoke every 5s by default)
- **RAM:** ~150 MB working set — typical for a Fluent-themed WPF app on .NET 10
- **Disk:** zero I/O after startup; config is loaded once into memory
- **Battery:** the app does not prevent sleep — it cooperates with Windows' power management

The 1 Hz live status banner in Settings is paused while the window is minimized or hidden.

## Project layout

```
IdlePulse/
├── App.xaml(.cs)          # App entry, single-instance mutex, crash logger
├── TrayApp.cs             # Tray icon, context menu, lifecycle
├── Models/AppConfig.cs    # JSON-serializable config
├── Native/                # Win32 P/Invoke
├── Services/              # IdleMonitor, ConfigStore, PowerActionExecutor,
│                          # AutostartManager, Dialogs, Format
├── Views/                 # SettingsWindow, AppSettingsWindow, CountdownWindow
├── Assets/                # Icon (.ico) + 512px PNG for in-window display
├── installer/             # Inno Setup script (IdlePulse.iss)
└── tools/                 # generate-icon.ps1, generate-png.ps1,
                           # build-installer.ps1
```

## License

MIT — see [LICENSE](LICENSE).
