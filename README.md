# IdlePulse

A small Windows tray utility that **shuts down, sleeps, hibernates, or locks your PC after a period of inactivity** — with a configurable warning countdown so you can cancel.

Windows has a built-in idle-sleep option, but no clean built-in "shut down on idle" option. IdlePulse fills that gap with a Fluent UI, real idle detection (`GetLastInputInfo`), and smart skips for fullscreen / presentation modes.

## Features

- **Idle-triggered actions** — Shutdown, Sleep, Hibernate, or Lock when no keyboard / mouse input for a configurable threshold (hours / minutes / seconds)
- **Warning countdown** — Topmost cancellable notification before the action fires, so accidental idle never costs you unsaved work
- **Smart skips** — Optionally skip while a fullscreen app is running (games, video) or presentation mode is active
- **Tray-resident** — Minimal tray icon with right-click menu, live status header, and quick Enable/Disable
- **Run at startup** — One-click toggle that adds the app to the per-user `HKCU\...\Run` registry key
- **Live status banner** — Shows current state (Active / Paused), action + threshold, and a progress bar of how close to firing
- **App settings** — Adjustable scan interval, config-file location, crash log access, autostart cleanup
- **Single-instance** — Can't be launched twice; second launch focuses the existing tray icon

## Requirements

- Windows 10 (1809+) or Windows 11
- x64

The published binary is **self-contained** — no .NET install needed on the target machine.

## Install

**Option A — Installer (recommended)**
Run `IdlePulse-Setup-<version>.exe` from the [Releases page](https://github.com/TheCSir/IdlePulse/releases). It will:
- Let you pick per-user (no admin) or per-machine install
- Add Start Menu (and optionally Desktop) shortcuts
- Optionally add IdlePulse to Windows startup
- Register an entry in Settings → Apps so you can uninstall cleanly

**Option B — Portable**
Grab `IdlePulse.exe` from `publish/` after building (see below) and drop it anywhere. Double-click to run; the tray icon appears bottom-right. Toggle autostart from inside the app's Settings.

## Build from source

```bash
# Requires .NET 10 SDK
dotnet publish IdlePulse.csproj -c Release -o publish
```

Outputs a single self-contained `IdlePulse.exe` (~75 MB, includes runtime).

### Building the installer

Requires [Inno Setup 6.x or 7.x](https://jrsoftware.org/isinfo.php) (`ISCC.exe`).

```powershell
# Publishes the app then compiles the installer
powershell -ExecutionPolicy Bypass -File tools\build-installer.ps1
```

Output: `installer\dist\IdlePulse-Setup-<version>.exe`

## Tech stack

- **.NET 10** + **WPF** with [WPF-UI](https://github.com/lepoco/wpfui) for Fluent design (Mica backdrop, dark theme, rounded corners)
- **[Hardcodet.NotifyIcon.Wpf](https://github.com/hardcodet/wpf-notifyicon)** for the tray icon
- **P/Invoke** for Win32 idle / power APIs (`GetLastInputInfo`, `SetSuspendState`, `LockWorkStation`, `SHQueryUserNotificationState`)
- **Single-file publish** for a clean drop-in distribution

## Configuration

Settings are saved as JSON at `%APPDATA%\IdlePulse\config.json`. Crash logs (if any) at `%APPDATA%\IdlePulse\crash.log`. The App Settings dialog has buttons to open these locations or copy the path.

## How idle is detected

Polls `GetLastInputInfo` (Win32) every N seconds (configurable, default 5). This is the same API Windows itself uses for idle-sleep — millisecond-precise, keyboard + mouse only, doesn't watch CPU/disk (which is what makes Task Scheduler's idle trigger unreliable). Polling cost is effectively zero (one Win32 call + integer compare).

Before firing, IdlePulse also calls `SHQueryUserNotificationState` to skip when the user is presenting, in fullscreen, or otherwise marked busy by Windows.

## Project layout

```
IdlePulse/
├── App.xaml(.cs)          # Application entry, single-instance mutex, crash logger
├── TrayApp.cs             # Tray icon, context menu, lifecycle
├── Models/AppConfig.cs    # JSON-serializable config
├── Native/                # Win32 P/Invoke
├── Services/              # IdleMonitor, ConfigStore, PowerActionExecutor, AutostartManager, Dialogs, Format
├── Views/                 # SettingsWindow, AppSettingsWindow, CountdownWindow
├── Assets/                # Icon (.ico) + 512px PNG for in-window display
├── installer/             # Inno Setup script (IdlePulse.iss)
└── tools/                 # Icon generators, build-installer.ps1
```

## License

MIT — see `LICENSE` (add one if you intend to distribute).
