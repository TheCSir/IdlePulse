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

## Download / run

Grab the published `IdlePulse.exe` from `publish/` (or build from source — see below). Drop it anywhere and double-click. The tray icon appears bottom-right.

To make it start with Windows: open Settings → enable "Run when Windows starts".

## Build from source

```bash
# Requires .NET 10 SDK
dotnet publish IdlePulse.csproj -c Release -o publish
```

Outputs a single self-contained `IdlePulse.exe` (~75 MB, includes runtime).

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
├── Services/              # IdleMonitor, ConfigStore, PowerActionExecutor, AutostartManager, Dialogs
├── Views/                 # SettingsWindow, AppSettingsWindow, CountdownWindow
├── Assets/IdlePulse.ico   # Multi-size app icon
└── tools/                 # Icon generator, dev probes (excluded from build)
```

## License

MIT — see `LICENSE` (add one if you intend to distribute).
