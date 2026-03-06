# Implementation Notes

Notes from getting the Servo kiosk running on a Raspberry Pi 4.

## Building Servo on Pi 4

- Build with `./mach build --release` in the servo checkout
- `./mach run` (without `--release`) will fail with "No Servo binary found" because it looks for a debug build — use `./mach run --release`
- Cross-compile config in `config.toml` targets `aarch64-unknown-linux-gnu`

## Rendering: GLES required on Pi 4

The Pi 4 GPU (V3D/Mesa) supports OpenGL ES 3.1 but only desktop OpenGL 2.1. Servo's surfman library defaults to requesting desktop GL 3.2, which fails with:

```
Could not create RenderingContext for Window: ContextCreationFailed(BadMatch)
```

**Fix:** Set `SURFMAN_FORCE_GLES=1`. This is checked in surfman's Wayland connection backend (`surfman-0.11.0/src/platform/unix/wayland/connection.rs` in the `gl_api()` method). It makes surfman report `GLApi::GLES`, so Servo requests GLES 3.0 instead of GL 3.2.

Note: the X11 backend hardcodes `GLApi::GL` with no override — Wayland (cage) is required.

Relevant Servo source: `components/shared/paint/rendering_context.rs` picks GL version based on `connection.gl_api()`.

## Seat management: seatd required

Cage uses libseat to acquire TTY and GPU access. Without a seat manager, it fails with:

```
[libseat] [common/terminal.c:162] Could not open target tty: Permission denied
```

**Fix:** Install and enable `seatd`, set `LIBSEAT_BACKEND=seatd`, and add the kiosk user to the `seat` group. The kiosk user also needs `tty`, `video`, and `render` groups.

## Display manager conflict

If lightdm (or another display manager) is running, it holds the DRM master and cage cannot take control:

```
Failed to open xcb connection. Unable to create the wlroots backend
```

**Fix:** `sudo systemctl disable --now lightdm` before starting the kiosk service.

## XDG_RUNTIME_DIR for system users

Cage needs a writable `XDG_RUNTIME_DIR` to create its Wayland socket. The standard `/run/user/<uid>` is created by logind on login, but the `kiosk` system user never logs in:

```
[../cage.c:568] Unable to open Wayland socket: Invalid argument
```

**Fix:** Use systemd's `RuntimeDirectory=kiosk` which creates `/run/kiosk` owned by the service user, and set `XDG_RUNTIME_DIR=/run/kiosk`.

## Servo resources directory

Servo crashes (SIGSEGV, exit code 139) without its `resources/` directory (fonts, UA stylesheet, etc.). The directory lives at the repo root (`servo/resources/`), not next to the binary in `target/release/`.

**Fix:** Copy `servo/resources/` to `/opt/servo/resources/`. The setup script now checks both locations.

## WebDriver: use 127.0.0.1, not localhost

Servo's WebDriver server (webdriver crate 0.53.0) validates the HTTP `Host` header. IP addresses are always allowed, but domain names must be in an explicit allow list. Servo passes an empty allow list, so `localhost` is rejected:

```json
{"value":{"error":"unknown error","message":"Invalid Host header localhost:4444"}}
```

**Fix:** `kiosk-ctl` uses `http://127.0.0.1:4444` instead of `http://localhost:4444`.

Relevant source: `webdriver-0.53.0/src/server.rs` `is_host_allowed()` — IPs pass unconditionally, domains require `allow_hosts.contains(&host)`.

## Systemd hardening

The initial service file included `ProtectSystem=strict`, `ProtectHome=read-only`, and `NoNewPrivileges=true`. These caused issues:
- `ProtectHome=read-only` → Servo couldn't write shader cache to `~kiosk/.cache`
- `ProtectSystem=strict` → EGL couldn't access GPU device files
- `NoNewPrivileges` → may interfere with DRM access

These were removed to get things working. TODO: re-add targeted hardening.

## EGL warnings (non-fatal)

These appear on every startup and are harmless:

```
[EGL] command: eglQueryDeviceStringEXT, error: EGL_BAD_PARAMETER (0x300c)
```

The Pi 4's Mesa driver doesn't support `EGL_EXT_device_query`. Cage/wlroots logs the error but continues fine.

## TODO: Hide the address bar

Servo has no `--kiosk` or `--fullscreen` CLI flag (unlike Firefox's `--kiosk`). The available flags are:
- `--no-native-titlebar` (`-b`) — removes OS window decorations
- `--window-size WxH` — sets initial window size

Neither hides Servo's built-in toolbar/address bar. The toolbar is still visible in kiosk mode.

**Possible fix:** Use the Fullscreen API via WebDriver after the page loads:

```bash
kiosk-ctl js "document.documentElement.requestFullscreen()"
```

This should make the content fill the entire Servo window, hiding the toolbar. Untested — may require a user gesture depending on Servo's Fullscreen API implementation. Could be automated via a post-start hook in the systemd service or a wrapper script.

Relevant source: `ports/servoshell/prefs.rs` defines all CLI args — no fullscreen/kiosk option exists. Fullscreen is handled internally via `headed_window.rs` `set_fullscreen()`.

I'm sure there's a way to run (or maybe compile and run?) servo to not use the window at all. Maybe I need a windowless wrapper to embed into? 
