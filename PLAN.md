# Servo Kiosk Setup Plan

## Context

Goal: A kiosk system that boots into a fullscreen Servo browser displaying a local static web page, with an external script able to send commands (navigate, reload) at runtime. Target hardware is a Raspberry Pi 4.

The approach uses **no modifications to Servo source code**. We use:
- Servo's built-in `--webdriver` flag for external control
- `cage` Wayland compositor for fullscreen kiosk display
- `seatd` for unprivileged TTY/GPU access
- A helper script (`kiosk-ctl`) for sending commands via WebDriver protocol
- Two systemd services: one for the browser, one for the local web server
- An Ansible playbook to provision and configure everything

## Architecture

```
[boot] → systemd
            ├── seatd.service (seat management)
            ├── ems-openhours.service (python3 HTTP server on 127.0.0.1:8080)
            └── kiosk.service (depends on both above)
                  └── cage → servo --webdriver=4444 --no-native-titlebar http://127.0.0.1:8080
                                      ↑
                            [kiosk-ctl] → HTTP → 127.0.0.1:4444 (WebDriver)
```

## Services

### ems-openhours.service
Serves the static site from `/opt/ems-openhours` using Python's built-in HTTP server on `127.0.0.1:8080`.

### kiosk.service
Runs `cage` (Wayland kiosk compositor) which launches Servo fullscreen with WebDriver enabled. Depends on `seatd` and `ems-openhours`.

Key environment variables:
- `SURFMAN_FORCE_GLES=1` — Pi 4 only supports GLES, not desktop GL 3.2
- `LIBSEAT_BACKEND=seatd` — TTY/GPU access for the unprivileged kiosk user
- `RuntimeDirectory=kiosk` — creates `/run/kiosk` for the Wayland socket
- `WLR_LIBINPUT_NO_DEVICES=1` — allows cage to start without input devices
- `WLR_NO_HARDWARE_CURSORS=1` — avoids hardware cursor issues on Pi

## Prerequisites

- `lightdm` (or any display manager) must be disabled — it holds DRM master
- `seatd` must be installed and enabled
- `kiosk` user must be in groups: `tty`, `video`, `render`
- Servo `resources/` directory must be at `/opt/servo/resources/`
- Servo built on the Pi at `/home/pi/dashboard/servo/`

## Files

| File | Purpose |
|------|---------|
| `ansible/playbook.yml` | Ansible playbook — provisions the entire kiosk |
| `ansible/inventory.ini` | Pi connection details |
| `ansible/files/kiosk-ctl` | WebDriver CLI wrapper (navigate, reload, js, screenshot, etc.) |
| `ansible/templates/*.j2` | Systemd service and config templates |

## Provisioning

```bash
cd ansible
ansible-playbook -i inventory.ini playbook.yml
```

Partial updates:
```bash
ansible-playbook -i inventory.ini playbook.yml --tags content   # web content only
ansible-playbook -i inventory.ini playbook.yml --tags servo     # servo binary only
ansible-playbook -i inventory.ini playbook.yml --tags wifi      # wifi config only
```

## Control (via SSH)

```bash
kiosk-ctl status              # Check if kiosk is responsive
kiosk-ctl navigate <url>      # Navigate to a URL
kiosk-ctl reload              # Reload current page
kiosk-ctl url                 # Print current URL
kiosk-ctl title               # Print page title
kiosk-ctl js <script>         # Execute JavaScript
kiosk-ctl screenshot <file>   # Save screenshot as PNG
kiosk-ctl back / forward      # History navigation
```
