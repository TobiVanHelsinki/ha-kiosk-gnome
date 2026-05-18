# A HomeAssistant Kiosk via GNOME

This repo enables an Ubuntu GNOME to be used as a HomeAssistant Kiosk.

## Overview

> This repository contains the technical setup. For background, hardware
> selection, and installation notes see the accompanying [blog post](https://blog.t-imperium.de/it/ha-kiosk-walldisplay/).

### Features

- Firefox in kiosk mode
  - auto-launched on login
  - dock button to restart Firefox
  - dock button to restore fullscreen without restart (GNOME extension)
- Display control via MQTT
  - Home Assistant can turn the screen on and off
  - Bidirectional updates: HA always knows the real display state
- No lock screen
  - display just blanks and wakes via hardware buttons or mqtt
  - without asking for password

### Scope

`ha-kiosk-gnome` is designed for a permanent Home Assistant dashboard on a touchscreen device running Ubuntu 24.04+ with GNOME 46+.

- **Wayland-native** – no X11, no workarounds like `xdotool` or `wmctrl`. Window manipulation runs exclusively through the GNOME Shell Extension API.
- **Minimal dependencies** – only `mosquitto-clients` and GNOME built-ins. No Python, no Node, no venv.
- **Bidirectional display state** – HA knows the real display state regardless of whether the change was triggered by HA, a hardware button, or the automatic screensaver.

### Acknowledgement

All files in this repository were written with the assistance of Claude Sonnet 4.6. The author created them iteratively in a pair-programming style.

## OS Configuration

- Use Battery Limit in the UEFI Configuration
- Autologin: Enabled within the Ubuntu installer

```bash
# Disable screen lock after suspend:
gsettings set org.gnome.desktop.screensaver lock-enabled false
# Disable hot corners:
gsettings set org.gnome.desktop.interface enable-hot-corners false
# Power button behavior:
gsettings set org.gnome.settings-daemon.plugins.power power-button-action 'nothing'
```

## Autostart

The file [`autostart/kiosk.desktop`](autostart/kiosk.desktop) configures how Firefox is launched automatically on login. It also serves as the dock button for manually starting and restarting the kiosk.

- Clone this repo into your home dir

```bash
cd ~/ha-kiosk-gnome
# Copy and edit the configuration file:
cp autostart/kiosk-template.env autostart/kiosk.env
# Adjust `HA_URL` to match your instance:
nano autostart/kiosk.env
# make the underlying script executable
chmod +x autostart/kiosk-restart.sh
# Register the autostart entry:
cp autostart/kiosk.desktop ~/.config/autostart/
# To also pin it to the dock, register it as an application:
cp autostart/kiosk.desktop ~/.local/share/applications/
```

- Then search for `HA-Kiosk` in the app overview → right-click → *Pin to Dash*.

Klick it and after a short time firefox should open at your home assistant webpage. Insert and save the credentials, setup a home dashboard and off you go!

## Remote Display Control

This is the optional but cool part: Control the display (on/off) from a Home Assistant Switch-Entity.

### How it works

Control: The display is controlled via MQTT. Home Assistant publishes to a topic, the tablet listens and executes a corresponding DBus call.

State watcher: The actual display state is independently observed via the DBus signal `org.gnome.ScreenSaver.ActiveChanged` and reported back to the MQTT Topic. This makes independent whether it was triggered by HA, a hardware button, or the automatic screensaver.

```
Control:

  HA
  │  kiosk/display (on/off)
  ▼
  Mosquitto
  │
  ▼
  kiosk-display-control.service
  │  gdbus SetActive
  ▼
  ScreenSaver

State:

  ScreenSaver
  │  ActiveChanged Signal
  ▼
  kiosk-display-watch.service
  │  kiosk/display/state
  ▼
  Mosquitto
  │
  ▼
  HA
```

> **Why not SSH?**
> SSH gives a full shell – too powerful for this purpose. MQTT is minimal: the tablet connects outbound to the broker, no port needs to be opened.

### Files

**[`mqtt-template.conf`](display-control/mqtt-template.conf)**
Central configuration for both scripts – MQTT broker, credentials and topics.

**[`kiosk-display-control.sh`](display-control/kiosk-display-control.sh)**
Receives MQTT messages on `MQTT_TOPIC_CMD` and controls the screensaver via DBus.

**[`kiosk-display-watch.sh`](display-control/kiosk-display-watch.sh)**
Listens to `org.gnome.ScreenSaver.ActiveChanged` and mirrors the state back to MQTT.
Required so HA knows the real display state regardless of who triggered the change.

**[`kiosk-display-control.service`](display-control/kiosk-display-control.service)** / **[`kiosk-display-watch.service`](display-control/kiosk-display-watch.service)**
Systemd user units that automatically start both scripts on login and restart them on failure.

### Installation on the kiosk tablet

Prerequisites:

```bash
sudo apt install mosquitto-clients
```

> The repository must be located at `~/ha-kiosk-gnome/`. The systemd units reference the path via the systemd specifier `%h` (user home directory) and require this location.

```bash
cd ~/ha-kiosk-gnome
```

- Create and edit configuration:

```bash
cp display-control/mqtt-template.conf display-control/mqtt.conf
nano display-control/mqtt.conf
```

- Set up systemd units:

```bash
cp display-control/kiosk-display-control.service ~/.config/systemd/user/
cp display-control/kiosk-display-watch.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable kiosk-display-control.service kiosk-display-watch.service
systemctl --user start kiosk-display-control.service kiosk-display-watch.service
```

Monitor services:

```bash
systemctl --user status kiosk-display-control.service 
systemctl --user status kiosk-display-watch.service

journalctl -t kiosk-display-control -f
journalctl -t kiosk-display-watch -f
```

### Home Assistant

- Add to `configuration.yaml` if not already present:

```yaml
mqtt: !include mqtt.yaml
```

- Edit `mqtt.yaml`:

```yaml
switch:
  - name: "Kiosk Display"
    unique_id: kiosk_display_switch
    state_topic: "kiosk/display/state"
    command_topic: "kiosk/display"
    payload_on: "on"
    payload_off: "off"
    retain: true
```

After changes to the MQTT configuration a full HA restart is required – config reload is not sufficient.

The switch can then be used in any HA automation, for example triggered by a motion sensor.

## Fullscreen Issues

Firefox is launched in `--kiosk` mode and fills the screen. If Firefox leaves fullscreen for any reason, the user has no way to interact with the window system directly.
For example, a swipe from the top edge triggers a Mutter-internal window drag that pulls Firefox out of fullscreen.
This of course can be wanted, for example to see the battery or system notifications.

Two solutions are available — choose one.

### Simple Solution

Restarting Firefox is the simplest recovery method. The autostart entry
doubles as a dock button — tapping it kills and relaunches Firefox in
fullscreen. See [Autostart](#autostart) for installation.

```
User Swipe → Firefox leaves fullscreen

User taps dock button
    │
    ▼
    kiosk.desktop
    │
    ▼
    kiosk-restart.sh
    │
    ▼
    Firefox relaunches in fullscreen
```

### Extended Solution

This Solution provides a Button, that incorporates an GNOME Shell Extension, that remaximes firefox.

```
User Swipe → Firefox leaves fullscreen

User taps button
    │
    ▼
    kiosk-remax.desktop
    │  gdbus call
    ▼
    DBus → Extension → Meta.Window.make_fullscreen()
```

[`extension.js`](fullscreen/extension.js) exposes a DBus method `RemaxFirefox()` which calls `Meta.Window.make_fullscreen()` from within the Shell process – the only way to programmatically manipulate windows under Wayland. [`metadata.json`](fullscreen/metadata.json) is the Extension metadata required by GNOME Shell.
The extension displays a Button in the Title-Bar to trigger the maximization.

[`kiosk-remax.desktop`](fullscreen/kiosk-remax.desktop) additionally provides a button in the desktop overview that triggers `RemaxFirefox()` via `gdbus call`.

#### Installation on the kiosk tablet

```bash
cd ~/ha-kiosk-gnome/
# Installation
mkdir -p ~/.local/share/gnome-shell/extensions/kiosk-remax@local
cp fullscreen/extension.js ~/.local/share/gnome-shell/extensions/kiosk-remax@local/
cp fullscreen/metadata.json ~/.local/share/gnome-shell/extensions/kiosk-remax@local/
```

- Log out and back in so the extension loads cleanly.

```bash

# Enable the app overview button
cp fullscreen/kiosk-remax.desktop ~/.local/share/applications/

# Enable the extension (once, persists afterwards):
gnome-extensions enable kiosk-remax@local
```

`HA-Kiosk Fullscreen` can than be pinned the dock via the app overview, giving the user a visible, tappable button to restore fullscreen at any time.

#### Rationale

The swipe itself cannot be intercepted or suppressed – it is handled entirely by Mutter before any application or script gets a chance to react. The approach here therefore does not try to prevent the swipe, but to recover from it.

Mutter does not allow external window manipulation on Wayland. Tools like `wmctrl`, `xdotool`, or direct `gdbus` calls targeting the window have no effect – only code running *inside* the GNOME Shell process may call `Meta.Window` methods. A Shell Extension is therefore the only viable entry point for restoring fullscreen programmatically.

The Extension exposes its functionality as a DBus method so it can be triggered from outside – by the dock button, via SSH, or by Home Assistant – without any of those callers needing special privileges or knowledge of the window system.

`Gio.DBusExportedObject.wrapJSObject()` in GNOME 46 requires a typed `Gio.DBusInterfaceInfo` object rather than a raw XML string. [`extension.js`](fullscreen/extension.js) therefore parses the interface definition via `Gio.DBusNodeInfo.new_for_xml()` before registering.

One operational quirk: GNOME Shell caches loaded ES modules, so disabling and re-enabling the extension via `gnome-extensions` does **not** reload the JS code. After changes to [`extension.js`](fullscreen/extension.js) a full logout/login is required.

#### Debugging

**Reloading after changes**

1. Edit [`extension.js`](fullscreen/extension.js)
2. Log out and back in

**Check status**

```bash
# is it there?
gnome-extensions list
# check status
gnome-extensions show kiosk-remax@local
```

`State: ACTIVE` = running. The extension logs on startup:

```
[kiosk-remax] enable() called
[kiosk-remax] DBus exported successfully
```

If this output is missing after login, check the full logs:

```bash
sudo journalctl -b 0 --no-pager | grep "kiosk-remax"
```

**Testing the DBus method:**

```bash
DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus \
  gdbus call \
    --session \
    --dest org.gnome.Shell \
    --object-path /org/gnome/Shell/Extensions/KioskRemax \
    --method org.gnome.Shell.Extensions.KioskRemax.RemaxFirefox
```

Expected response: `()` (empty tuple = success)

**Inspecting the DBus object:**

```bash
DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus \
  gdbus introspect \
    --session \
    --dest org.gnome.Shell \
    --object-path /org/gnome/Shell/Extensions/KioskRemax \
    --recurse
```

Should list the `RemaxFirefox` method. Empty node `{ };` = interface not registered, likely a wrong `wrapJSObject` call or extension not reloaded.

## Planned

**Voice Satellite** — the device has a working microphone and speakers, making it a candidate for a Home Assistant voice satellite via the Wyoming protocol. `Not yet implemented`
