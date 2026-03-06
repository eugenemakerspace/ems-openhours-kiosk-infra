# ems-opensign-infra

Ansible provisioning for a Raspberry Pi 4 kiosk that displays the [Eugene Makerspace](https://www.eugenemakerspace.com/) Open Hours dashboard using [Servo](https://servo.org/) browser.

```
systemd
  ├── seatd                 (seat/GPU management)
  ├── ems-openhours         (python3 HTTP server on :8080)
  └── kiosk                 (cage wayland compositor → servo with WebDriver on :4444)
                                ↑
                      kiosk-ctl (remote control via WebDriver)
```

The dashboard web content is a separate repo: [openhours-signage](https://github.com/eugenemakerspace/openhours-signage)

## Prerequisites

**Raspberry Pi:**
- Raspberry Pi 4 with Raspberry Pi OS (Bookworm or later)
- SSH enabled, wifi configured
- The `pi` user can sudo without a password (default on Pi OS)

**Your workstation:**
- Ansible installed (`apt install ansible` or `pip install ansible`)
- SSH access to the Pi

## Setup from scratch

### 1. Build Servo on the Pi

SSH into the Pi and build Servo from source:

```bash
ssh pi@ems-opensign.local
git clone https://github.com/servo/servo.git /home/pi/dashboard/servo
cd /home/pi/dashboard/servo
./mach build --release
```

This takes a long time on the Pi but avoids cross-compilation issues. The binary ends up at `/home/pi/dashboard/servo/target/release/servo`.

### 2. Configure the inventory

Edit `ansible/inventory.ini` with your Pi's address:

```ini
[kiosk]
ems-kiosk ansible_host=ems-opensign.local ansible_user=pi
```

### 3. Run the playbook

```bash
cd ansible
ansible-playbook -i inventory.ini playbook.yml
```

To preview what will change first:

```bash
ansible-playbook -i inventory.ini playbook.yml --check --diff
```

The playbook will:
- Install system packages (cage, seatd, curl, python3, git)
- Create a `kiosk` system user (groups: tty, video, render)
- Disable lightdm (it conflicts with cage for DRM access)
- Disable wifi power management and screen blanking
- Copy the Servo binary and resources to `/opt/servo/`
- Clone the dashboard web content to `/opt/ems-openhours/`
- Install `kiosk-ctl` to `/usr/local/bin/`
- Install and enable the systemd services

## Updating

Update just the web content (pulls latest from git):

```bash
ansible-playbook -i inventory.ini playbook.yml --tags content
```

Redeploy Servo after a rebuild on the Pi:

```bash
ansible-playbook -i inventory.ini playbook.yml --tags servo
```

## Remote control

Control the kiosk over SSH using `kiosk-ctl`:

```bash
kiosk-ctl status              # Check if kiosk is responsive
kiosk-ctl reload              # Reload current page
kiosk-ctl navigate <url>      # Navigate to a URL
kiosk-ctl url                 # Print current URL
kiosk-ctl js <script>         # Execute JavaScript
kiosk-ctl screenshot out.png  # Save a screenshot
```

## Troubleshooting

Check service logs:

```bash
sudo systemctl status kiosk
sudo journalctl -u kiosk -f
```

See [NOTES.md](NOTES.md) for detailed notes on Pi 4-specific issues (GLES rendering, seatd, DRM conflicts, WebDriver quirks).

## Repo layout

```
ansible/              Ansible playbook and supporting files
  playbook.yml        Main provisioning playbook
  inventory.ini       Pi connection details
  files/kiosk-ctl     WebDriver CLI control script
  templates/          Systemd service and config templates
openhours-signage/    Dashboard web content (submodule/clone of openhours-signage repo)
servo/                Servo browser source (built on the Pi)
NOTES.md              Implementation notes and troubleshooting
PLAN.md               Original architecture plan
```
