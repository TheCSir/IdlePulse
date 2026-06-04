# IdlePulse — Technical reference

This file is the in-depth companion to the [README](README.md). It covers architecture decisions, every Win32 API used, performance characteristics, configuration schema, edge-case handling, migration logic, and the full feature surface.

---

## Table of contents

1. [Architecture overview](#architecture-overview)
2. [Project layout](#project-layout)
3. [Configuration model](#configuration-model)
4. [Idle detection — how it actually works](#idle-detection--how-it-actually-works)
5. [Power actions](#power-actions)
6. [Smart skips](#smart-skips)
7. [Lifecycle and state machine](#lifecycle-and-state-machine)
8. [Settings UI design](#settings-ui-design)
9. [Validation rules](#validation-rules)
10. [Tray context menu](#tray-context-menu)
11. [Single-instance enforcement](#single-instance-enforcement)
12. [Crash logging](#crash-logging)
13. [Autostart](#autostart)
14. [Migration from AutoShutdown](#migration-from-autoshutdown)
15. [Performance characteristics](#performance-characteristics)
16. [Build, publish, installer](#build-publish-installer)
17. [Files written by IdlePulse](#files-written-by-idlepulse)
18. [Win32 API surface](#win32-api-surface)
19. [Known limitations](#known-limitations)

---

## Architecture overview

IdlePulse is a tray-resident WPF app structured around four singletons coordinated by `TrayApp`:

```
┌──────────────────────────────────────────────────────────┐
│  App.xaml.cs                                             │
│  ├─ Single-instance Mutex (Global\IdlePulse_…)           │
│  ├─ Crash handler (AppDomain + Dispatcher + Task)        │
│  └─ TrayApp.Start()                                      │
└──────────────────────────────────────────────────────────┘
                          │
                          ▼
┌──────────────────────────────────────────────────────────┐
│  TrayApp                                                 │
│  ├─ TaskbarIcon (Hardcodet.NotifyIcon.Wpf)               │
│  ├─ ContextMenu (refreshed on every Open)                │
│  ├─ ConfigStore  ◄── %APPDATA%\IdlePulse\config.json     │
│  ├─ IdleMonitor  ◄── DispatcherTimer @ scan interval     │
│  └─ Owns:  SettingsWindow, CountdownWindow (lazy)        │
└──────────────────────────────────────────────────────────┘
                          │
                          ▼
┌──────────────────────────────────────────────────────────┐
│  IdleMonitor.Tick (every N seconds)                      │
│  ├─ NativeMethods.GetIdleTime()                          │
│  ├─ skip if SHQueryUserNotificationState says busy       │
│  ├─ skip if SuspendUntil hasn't elapsed                  │
│  └─ raise IdleThresholdReached → CountdownWindow         │
└──────────────────────────────────────────────────────────┘
```

### Why this shape

- **Single-window-of-each-type** — `_settingsWindow` and `_countdownWindow` are nullable fields. Closing either nulls the field; the next open creates a fresh instance. WPF can GC the old visual tree because nothing references it.
- **Tray menu is rebuilt only once** — refreshes happen via direct `TextBlock.Text` mutation on the existing `MenuItem` headers; no allocations per open.
- **Config is the single source of truth** — `IdleMonitor`, `TrayApp`, and `SettingsWindow` all hold their own `AppConfig` reference but treat it as read-only. The only writer is `ConfigStore.Save`, called on Save / Enable-toggle / external apply.

---

## Project layout

```
IdlePulse/
├── App.xaml(.cs)                  WPF Application entry, mutex, crash logging
├── TrayApp.cs                     Lifecycle owner; tray icon + menu + window glue
├── Models/
│   └── AppConfig.cs               PowerAction enum + AppConfig (Clone, ValueEquals)
├── Native/
│   └── NativeMethods.cs           [LibraryImport]-generated P/Invoke (.NET 7+ style)
├── Services/
│   ├── IdleMonitor.cs             DispatcherTimer-driven idle threshold detector
│   ├── ConfigStore.cs             JSON load/save + AutoShutdown migration
│   ├── PowerActionExecutor.cs     Sleep / Shutdown / Hibernate / Lock dispatch
│   ├── AutostartManager.cs        HKCU\…\Run R/W + ClearAll() scanner
│   ├── Dialogs.cs                 Fluent MessageBox helpers (ConfirmAsync, NotifyAsync)
│   └── Format.cs                  FormatDuration shared helper
├── Views/
│   ├── SettingsWindow.xaml(.cs)   Hero header + status banner + setting cards
│   ├── AppSettingsWindow.xaml(.cs) Scan interval, file paths, crash log, reset
│   └── CountdownWindow.xaml(.cs)  Topmost progress-ring countdown with Cancel
├── Assets/
│   ├── IdlePulse.ico              7 sizes (16/24/32/48/64/128/256), embedded
│   └── IdlePulse-512.png          High-res for in-window hero icon
├── installer/
│   └── IdlePulse.iss              Inno Setup script (per-user/per-machine)
└── tools/
    ├── build-installer.ps1        Publish + ISCC orchestration
    ├── generate-icon.ps1          Build .ico from brand source PNG
    └── generate-png.ps1           Build 512px PNG from brand source PNG
```

---

## Configuration model

```csharp
public sealed class AppConfig
{
    public bool Enabled              { get; set; } = true;
    public int  IdleSeconds          { get; set; } = 1800;   // 30 min default
    public PowerAction Action        { get; set; } = PowerAction.Shutdown;
    public int  WarningSeconds       { get; set; } = 30;
    public bool RunAtStartup         { get; set; } = false;
    public bool SkipWhenFullscreen   { get; set; } = true;
    public bool SkipWhenPresenting   { get; set; } = true;
    public int  ScanIntervalSeconds  { get; set; } = 5;
}
```

`Clone()` returns a deep-enough copy (all primitives + enum, no reference fields). `ValueEquals(other)` is used by the SettingsWindow dirty-check to gate the Save button.

Persistence: `System.Text.Json` with `WriteIndented = true` and `JsonStringEnumConverter` so the file is human-readable:

```json
{
  "Enabled": true,
  "IdleSeconds": 1800,
  "Action": "Shutdown",
  "WarningSeconds": 30,
  "RunAtStartup": false,
  "SkipWhenFullscreen": true,
  "SkipWhenPresenting": true,
  "ScanIntervalSeconds": 5
}
```

Path: `%APPDATA%\IdlePulse\config.json`

---

## Idle detection — how it actually works

```csharp
public static TimeSpan GetIdleTime()
{
    var info = new LASTINPUTINFO { cbSize = (uint)Marshal.SizeOf<LASTINPUTINFO>() };
    if (!GetLastInputInfo(ref info)) return TimeSpan.Zero;

    uint idleMs = unchecked(GetTickCount() - info.dwTime);
    return TimeSpan.FromMilliseconds(idleMs);
}
```

`GetLastInputInfo` returns the system tick count (`GetTickCount`) of the most recent keyboard or mouse input. Subtracting from the current tick count gives idle time in milliseconds. The `unchecked` subtraction handles the 49.7-day tick wrap correctly via uint arithmetic.

### Why this is more reliable than Task Scheduler's idle trigger

| | Task Scheduler "On idle" | IdlePulse |
|---|---|---|
| Sample frequency | Every **15 minutes** | Every **5 seconds** (configurable 1–3600s) |
| Idle definition | input + CPU < 10% + disk activity AND-ed | **input only** |
| "Stop on no longer idle" | Buggy — often misses | N/A — we re-evaluate on every tick |
| UI to configure | Buried in admin tools | Tray + Fluent settings |

### The `IdleMonitor` tick

```csharp
private void OnTick(object? sender, EventArgs e)
{
    if (!_config.Enabled) return;
    if (_paused) return;
    if (DateTime.UtcNow < _suspendedUntil) return;
    if (NativeMethods.GetIdleTime() < TimeSpan.FromSeconds(_config.IdleSeconds)) return;
    if (_config.SkipWhenFullscreen || _config.SkipWhenPresenting) {
        var state = QueryNotificationState();
        if (ShouldSkip(state)) return;
    }
    IdleThresholdReached?.Invoke(this, EventArgs.Empty);
}
```

The handler in `TrayApp` then opens the `CountdownWindow` and calls `_monitor.SuspendFor(TimeSpan.FromMinutes(5))` so the same threshold doesn't immediately re-fire while the user is staring at the countdown.

---

## Power actions

```csharp
public static void Execute(PowerAction action)
{
    switch (action)
    {
        case PowerAction.Sleep:     SetSuspendState(false, false, false); break;
        case PowerAction.Hibernate: SetSuspendState(true,  false, false); break;
        case PowerAction.Lock:      LockWorkStation();                    break;
        case PowerAction.Shutdown:  ShellOutShutdown();                   break;
    }
}

private static void ShellOutShutdown()
    => Process.Start(new ProcessStartInfo("shutdown.exe", "/s /t 0")
        { CreateNoWindow = true, UseShellExecute = false });
```

We shell out to `shutdown.exe` rather than P/Invoke `ExitWindowsEx` because:
- `ExitWindowsEx` requires `SE_SHUTDOWN_NAME` privilege adjustment (extra code path)
- `shutdown.exe` is a Microsoft-signed binary that handles privilege internally
- The `/s /t 0` is graceful — sends WM_QUERYENDSESSION so apps can save

---

## Smart skips

Before firing, IdlePulse calls `SHQueryUserNotificationState` and skips when the user is busy:

| State | Meaning | Skipped? |
|---|---|---|
| `NotPresent` (1) | Screensaver active or workstation locked | No (already idle by design) |
| `Busy` (2) | "Do not disturb" or full-screen Metro/UWP | If skip-fullscreen is on |
| `RunningDirect3DFullScreen` (3) | Game / fullscreen video | If skip-fullscreen is on |
| `PresentationMode` (4) | PowerPoint, Zoom share | If skip-presenting is on |
| `AcceptsNotifications` (5) | Normal | No |
| `QuietTime` (6) | Quiet hours | No |
| `RunningWindowsStoreApp` (7) | UWP app focused | No |

This is the same API Windows uses to decide when to suppress its own toast notifications.

---

## Lifecycle and state machine

```
              ┌──────────┐
              │  Paused  │  (Enabled=false, or _paused=true)
              └─────┬────┘
                    │ Enable
                    ▼
              ┌──────────┐
   ┌──────────│  Active  │◄──── Cooldown 60s after wake-from-sleep
   │          └────┬─────┘
   │               │ idle ≥ threshold + not busy
   │               ▼
   │       ┌──────────────┐
   │       │  Countdown   │ (warning seconds remaining)
   │       └──┬────────┬──┘
   │  Cancel  │        │  Timer expires
   │          ▼        ▼
   │   Suspend 5min   Action fires
   │          │        │
   └──────────┴────────┘
```

System events that affect state:
- `SystemEvents.PowerModeChanged → Resume`: 60-second cooldown to avoid immediate re-fire
- `SystemEvents.SessionSwitch → SessionLock/SessionLogoff`: Pause monitor
- `SystemEvents.SessionSwitch → SessionUnlock/SessionLogon/RemoteConnect/ConsoleConnect`: Resume + 10s grace

---

## Settings UI design

### Two-state model (sandboxed editing)

Edits in the form **never affect runtime behavior** until Save is clicked. The window holds two `AppConfig` snapshots:

- `_savedConfig` — what's currently persisted and running
- A live computed `BuildConfigFromUi()` — what would be saved if Save were clicked now

The status banner reads `_savedConfig` only. The Save button enables only when `BuildConfigFromUi() != _savedConfig` AND the configuration validates.

### Live status banner

Updates every 1 second via a `DispatcherTimer` that auto-pauses when the window is minimized or hidden (`StateChanged` / `IsVisibleChanged`).

```
┌──────────────────────────────────────────────────────────┐
│  ✓  Active                            [⏸ Disable]        │
│     Shutdown when idle for 30m                            │
│     Idle 12s · Fires in 29m 48s                           │
│     ███▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒     │
│     ⚡ Scanning every 5s                                  │
└──────────────────────────────────────────────────────────┘
```

When `ScanIntervalSeconds < 5`, an amber **"High frequency monitoring"** chip appears next to the scan-frequency line.

### Pending-changes summary

Below the cards, a footer always shows the configuration that **would** be saved:

- _No pending changes_ → `Shutdown after 30m idle, with a 30s warning`
- _Click Save to apply_ → `Lock after 10s idle, with a 60s warning`
- _Can't save — fix the highlighted field_ → `Idle threshold must be at least 5 seconds.`

---

## Validation rules

| Field | Min | Max | Default |
|---|---|---|---|
| Hours | 0 | 23 | 0 |
| Minutes | 0 | 59 | 30 |
| Seconds | 0 | 59 | 0 |
| **Total idle threshold** | **5 sec** (Save blocked below this) | 23h 59m 59s | 30 min |
| Warning seconds | 5 | 1800 (30 min) | 30 |
| Scan interval | 1 | 3600 (1 hr) | 5 |

The Save button is disabled if any rule fails, and the footer states which.

---

## Tray context menu

Built **once** and refreshed in place on every open. Layout:

```
┌────────────────────────────────────┐
│  Active                  (header)  │   ← color: green when active, gray when paused
│  Shutdown after 30m idle           │
├────────────────────────────────────┤
│  ⏸  Disable    (or  ▶  Enable)     │   ← single click toggles + persists + restarts monitor
│  ⚙  Settings…                      │
├────────────────────────────────────┤
│  ⏻  Exit                           │
└────────────────────────────────────┘
```

The status header is non-clickable (`IsEnabled = false`, `StaysOpenOnClick = true`) and only updates strings — no menu rebuild, no allocation per open.

Toggling Enable from the tray:
1. Flips `_config.Enabled`
2. Saves to disk via `ConfigStore.Save`
3. Calls `_monitor.UpdateConfig(_config)` and `_monitor.Reset()` to clear cooldowns
4. Starts or stops the monitor
5. Updates the tooltip
6. If the SettingsWindow is open, calls `ApplyExternalConfig(_config)` so the banner reflects the new state immediately

---

## Single-instance enforcement

```csharp
private const string MutexName = "Global\\IdlePulse_SingleInstance_8F3C2A";
_mutex = new Mutex(initiallyOwned: true, MutexName, out bool createdNew);
if (!createdNew) {
    ShowAlreadyRunningDialog();
    Shutdown();
}
```

The hex suffix avoids accidental collision with any other app named "IdlePulse". The `Global\` prefix scopes to the session.

`OnExit` releases the mutex inside a try/catch — necessary because a second instance never owned the mutex and `ReleaseMutex()` would otherwise throw `ApplicationException`.

---

## Crash logging

Three handlers wired in `App.OnStartup`:

```csharp
AppDomain.CurrentDomain.UnhandledException  → LogCrash("AppDomain", …)
DispatcherUnhandledException                 → LogCrash("Dispatcher", …); args.Handled = true
TaskScheduler.UnobservedTaskException        → LogCrash("Task", …); args.SetObserved()
```

`LogCrash`:
1. Appends a timestamped block with `ex.ToString()` to `%APPDATA%\IdlePulse\crash.log`
2. Shows a Fluent MessageBox with the brief message + log path
3. Falls back to `System.Windows.MessageBox` if the Fluent dialog itself fails (last-resort safety net)

Dispatcher exceptions are swallowed so a single XAML resolution error doesn't take the whole app down — it surfaces to the user instead.

---

## Autostart

Per-user, no admin needed. Writes:

```
HKCU\Software\Microsoft\Windows\CurrentVersion\Run
  IdlePulse = "C:\path\to\IdlePulse.exe"
```

`AutostartManager.ClearAll()` scans this key plus `%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\*IdlePulse*.lnk` and removes any matches. It returns a `StartupClearReport` listing what was found, removed, and any errors — surfaced in the Fluent results dialog.

Per the security model, this never touches `HKLM`, scheduled tasks, or anything outside the per-user surface.

---

## Migration from AutoShutdown

The app was previously named `AutoShutdown`. On every launch, `ConfigStore.Load` runs a one-shot migration:

```csharp
private static void MigrateLegacyDataOnce()
{
    if (!File.Exists(ConfigPath) && File.Exists(LegacyConfigPath)) {
        Directory.CreateDirectory(ConfigDir);
        File.Copy(LegacyConfigPath, ConfigPath, overwrite: false);
    }
    using var key = Registry.CurrentUser.OpenSubKey(RunKey, writable: true);
    if (key?.GetValue("AutoShutdown") != null) {
        key.DeleteValue("AutoShutdown", throwOnMissingValue: false);
    }
}
```

This:
1. Auto-imports `%APPDATA%\AutoShutdown\config.json` if no IdlePulse config exists yet
2. Removes the leftover `HKCU\…\Run\AutoShutdown` value so the old build doesn't co-launch

After first launch, the migration becomes a no-op (config already exists, registry value already gone).

---

## Performance characteristics

### CPU

- **At rest:** effectively 0%. One `GetLastInputInfo` Win32 call every 5s by default. The call itself is ~1 µs.
- **During the 1Hz banner update** (only while the SettingsWindow is open and visible): ~10 µs per tick, including string formatting and a `SHQueryUserNotificationState` call.

### Memory

| Component | Approx working set |
|---|---|
| .NET 10 runtime baseline | 30–40 MB |
| WPF | 40–60 MB |
| WPF-UI | 15–25 MB |
| Single-file extraction overhead | 15–25 MB |
| Application visual tree (when SettingsWindow open) | +10–15 MB |
| **Idle total** | **~120–160 MB** |

This is typical for a Fluent-themed WPF app on .NET 10. PowerToys' Settings, Microsoft's own WinUI utilities, and similar tools sit in the same range. The OS reclaims pages under memory pressure, so the working set shrinks if other apps need RAM.

### Allocations

The hot 1 Hz banner path uses `Format.Duration(TimeSpan)` which avoids `List<string>` / `string.Join` allocations:

```csharp
public static string Duration(TimeSpan ts)
{
    if (ts.TotalSeconds < 1) return "0s";
    if (ts.Hours > 0)   return $"{ts.Hours}h {ts.Minutes}m {ts.Seconds}s";
    if (ts.Minutes > 0) return $"{ts.Minutes}m {ts.Seconds}s";
    return $"{ts.Seconds}s";
}
```

One string allocation per call instead of three plus a list.

### Startup

- Cold start: ~600–900 ms (single-file extraction is the dominant cost)
- Warm start: ~250–400 ms
- Tray icon visible by ~start + 1s

---

## Build, publish, installer

### Publish

```powershell
dotnet publish IdlePulse.csproj -c Release -o publish
```

`csproj` knobs in `Release`:
- `PublishSingleFile = true`
- `SelfContained = true`
- `RuntimeIdentifier = win-x64`
- `IncludeNativeLibrariesForSelfExtract = true`
- `EnableCompressionInSingleFile = true`
- `DebugType = embedded`

Result: `publish\IdlePulse.exe`, ~75 MB, no .NET install required on target.

### Installer

`tools\build-installer.ps1`:
1. Locates a real `.NET SDK` install (prefers `E:\SDKs\dotnet`, falls back to PATH)
2. Locates `ISCC.exe` (env override, common install paths)
3. Kills any running `IdlePulse.exe` so publish can overwrite the locked file
4. `dotnet publish` → `publish\IdlePulse.exe`
5. `iscc /Qp installer\IdlePulse.iss` → `installer\dist\IdlePulse-Setup-<version>.exe`

`installer\IdlePulse.iss` highlights:
- `PrivilegesRequiredOverridesAllowed = dialog` — user picks per-user vs per-machine at runtime
- Optional desktop shortcut, optional run-at-startup, optional launch-after-install
- Uninstaller kills running instance + removes the `HKCU\…\Run\IdlePulse` value
- Installer version is read from the published exe via `GetVersionNumbersString()`

---

## Files written by IdlePulse

| Path | Written when | Purpose |
|---|---|---|
| `%APPDATA%\IdlePulse\config.json` | Save / Enable toggle | App config |
| `%APPDATA%\IdlePulse\crash.log` | Unhandled exception | Append-only crash trace |
| `HKCU\Software\Microsoft\Windows\CurrentVersion\Run\IdlePulse` | Run-at-startup toggled on | Per-user autostart |

Nothing else is written. No machine-wide registry, no temp files, no telemetry, no network.

---

## Win32 API surface

All declarations are source-generated `[LibraryImport]` (modern .NET 7+ replacement for `[DllImport]`):

```csharp
[LibraryImport("user32.dll")]    GetLastInputInfo
[LibraryImport("kernel32.dll")]  GetTickCount
[LibraryImport("powrprof.dll")]  SetSuspendState
[LibraryImport("user32.dll")]    LockWorkStation
[LibraryImport("shell32.dll")]   SHQueryUserNotificationState
```

Plus shelling out:
- `shutdown.exe /s /t 0` for graceful shutdown

Plus managed APIs:
- `Microsoft.Win32.SystemEvents` for `PowerModeChanged` and `SessionSwitch`
- `Microsoft.Win32.Registry` for autostart R/W

---

## Known limitations

1. **`GetLastInputInfo` is per-session.** Logged-out sessions don't fire idle events for that user. If you log out, IdlePulse stops monitoring (and re-launches via autostart on next login).
2. **Modern Standby (S0) laptops** — `SetSuspendState` may behave differently on devices using Connected Standby. Sleep still works, just via a different OS path; the app doesn't notice.
3. **Shutdown can be vetoed** — apps with unsaved work can intercept `WM_QUERYENDSESSION` and prompt the user, halting shutdown. This is by design (`/s` is graceful, not `/f` forced). The user can interrupt via those dialogs if they're at the keyboard.
4. **Corporate / managed machines** — Group Policy can block shutdown for non-admin users. The action will silently fail; the crash log will record the failure but the user sees no error. (Future improvement: surface a Fluent dialog when the action API returns an error.)
5. **Tray icon hidden by Windows** — Windows 11 hides icons by default in the overflow menu. Right-click the up-arrow ▲ next to the system tray and pin IdlePulse if you want it always visible.
