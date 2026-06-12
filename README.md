# Streaming Direct Orchestrator

> [!WARNING]
> This is a personal utility developed for my own custom streaming setup. **Use it at your own risk.** The author takes no responsibility for display configurations, monitor lockouts, registry settings, or driver behaviors resulting from the execution of these scripts.


A lightweight, low-latency, 5GHz direct-streaming orchestration suite for Windows, built specifically to stream gameplay using [Sunshine](https://github.com/LizardByte/Sunshine) + [Moonlight](https://moonlight-stream.org/) via a direct Wi-Fi Mobile Hotspot and a Virtual Display Driver.

This suite automates net-adapter properties tuning, sets up a dedicated 5GHz Hotspot, manages Sunshine configurations for NVIDIA graphics encoders, and controls virtual screen projection, ensuring you can stream directly from your PC to high-resolution mobile devices or handheld consoles without monitor lockouts.

---

## Features

- **Direct 5GHz Connection:** Forces Windows Mobile Hotspot and the physical Intel Wi-Fi card to operate exclusively in the 5GHz band to minimize latency.
- **Virtual Display Integration:** Manages the [Virtual Display Driver](https://github.com/itsmikethetech/Virtual-Display-Driver) to dynamically create and toggle custom landscape resolutions (e.g., Motorola Edge X30 2400x1080 @ 120Hz/144Hz, retro console 640x480).
- **Interactive CLI Orchestrator:** Provides a single, clean terminal interface to start/stop the streaming ecosystem, toggle the virtual screen (blanking out the PC monitor), customize display resolutions, and monitor active connections.
- **Robust Multi-Adapter Safety:** Automatically cleans up duplicate virtual displays and operates defensively when managing devices to prevent black-screen lockouts.

---

## Prerequisites

Before running the installer, make sure your system meets the following requirements:

1. **Operating System:** Windows 10 or Windows 11.
2. **Wi-Fi Card:** A 5GHz-capable network adapter (e.g., Intel AX210) that supports Windows Mobile Hotspot.
3. **Graphics Card:** NVIDIA GPU (optimized for NVENC encoding).
4. **Sunshine Host:** [Sunshine](https://github.com/LizardByte/Sunshine) installed as a Windows Service.
5. **Virtual Display Driver:** [Virtual Display Driver (VDD)](https://github.com/itsmikethetech/Virtual-Display-Driver) installed via Winget:
   ```powershell
   winget install VirtualDrivers.Virtual-Display-Driver
   ```

---

## Installation

To set up the direct streaming environment, run the installer:

1. Clone or download this repository.
2. Open **PowerShell as Administrator**.
3. Navigate to the project directory and execute:
   ```powershell
   Set-ExecutionPolicy Bypass -Scope Process -Force
   .\setup.ps1
   ```

### What the installer does:
- Requests Administrator elevation automatically.
- Sets the physical Wi-Fi adapter's preferred band to 5GHz.
- Configures the default Mobile Hotspot frequency to 5GHz.
- Optimizes `sunshine.conf` with low-latency NVENC parameters (preset P5, quarter-resolution, spatial AQ).
- Performs a hardware cleanup to remove duplicate virtual display device instances.
- Installs the script components permanently to `%LOCALAPPDATA%\StreamingDirect\`.
- Generates a **Stream Orchestrator** shortcut on your Desktop.

---

## Usage

Double-click the **Stream Orchestrator** shortcut on your Desktop to open the CLI menu. 

### CLI Menu Options

1. **Start Streaming:** Enables Wi-Fi, starts the Mobile Hotspot, starts Sunshine, enables the Virtual Display, and switches Windows projection to "Second Screen Only" (blanking out your physical monitor and streaming the virtual screen).
2. **Stop Streaming:** Disables the Virtual Display, restores the Windows projection to "Internal Screen Only" (turning your PC monitor back on), and stops the Hotspot/Sunshine services.
3. **Turn ON Virtual Display:** Manually enables the virtual monitor and switches projection (turning off the PC screen).
4. **Turn OFF Virtual Display:** Manually disables the virtual monitor and restores the physical screen.
5. **Configure Device Resolution:** Allows choosing from preconfigured presets (Motorola Edge X30 2400x1080 @ 120Hz/144Hz, Retro Handheld 640x480, Full HD 1920x1080) or defining a custom screen layout.
6. **Check Status and Connected Devices:** Displays real-time connectivity status, current resolution, active hotspot client IPs/MACs, and service states.
7. **Exit:** Closes the menu.

---

## Safety & Troubleshooting

### Lost Display / Screen Lockout Recovery
If you quit the orchestrator unexpectedly or lose your physical monitor connection, Windows might remain in "Second Screen Only" projection mode with the virtual display disabled. 
- To immediately force your physical monitor back on, press **Win + P** on your keyboard and select **PC screen only**, or run the following command:
  ```powershell
  displayswitch.exe /internal
  ```

### Duplicate Monitors Cache Reset
If your system displays multiple virtual monitors, open PowerShell as Administrator and run the installer again to automatically wipe and reinstall a single clean instance:
```powershell
& "$env:LOCALAPPDATA\StreamingDirect\setup.ps1"
```
