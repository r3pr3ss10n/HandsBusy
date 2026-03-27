# HandsBusy

Prevents macOS from hijacking your microphone when Bluetooth headphones connect.

# The problem

Every time you connect your Bluetooth headphones, macOS silently sets them as the default microphone. This automatically activates the **Hands-Free** profile, which kills ANC and makes your audio sound... terrible. 

Nobody wants to manually switch the microphone back every single time.

# What it does

`handsbusy` is a lightweight daemon that monitors CoreAudio for input device changes. When macOS switches the input to any Bluetooth device, it instantly switches it back to your preferred wired/built-in microphone.

You can still manually select the Bluetooth microphone anytime you want — tool only intervenes on that automatic switch right after connection.

# Quick start

1. Download the latest release
2. Unzip and run `./install.sh`

Installer will ask for your password (`sudo`) to place the binary in `/usr/local/bin` and set up the launch agent.

# Uninstall

```bash
launchctl bootout gui/$(id -u)/eu.r3pr3ss10n.handsbusy
rm ~/Library/LaunchAgents/eu.r3pr3ss10n.handsbusy.plist
sudo rm /usr/local/bin/HandsBusy
```
