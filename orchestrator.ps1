# Streaming Direct Orchestrator
# Manages Windows Mobile Hotspot, Sunshine service, and Virtual Display Driver.
# Automatically elevates to Administrator for hardware operations.

# Self-elevation check
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    Exit
}

# Configuration Paths
$ConfigDir = "$env:LOCALAPPDATA\StreamingDirect"
$ConfigFile = "$ConfigDir\config.json"
$VddDir = "C:\VirtualDisplayDriver"
$VddXmlFile = "$VddDir\vdd_settings.xml"

# Ensures configuration directory exists
if (!(Test-Path $ConfigDir)) {
    New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
}

# Load configuration values (fallback to landscape Motorola Edge X30 defaults)
function Get-Config {
    $width = 2400
    $height = 1080
    $refreshRate = 120

    if (Test-Path $ConfigFile) {
        try {
            $saved = Get-Content $ConfigFile -Raw | ConvertFrom-Json
            if ($saved.width -and $saved.height) {
                $width = $saved.width
                $height = $saved.height
                $refreshRate = $saved.refresh_rate
            }
        } catch {
            # Silent fallback on corrupt config file
        }
    }
    return [PSCustomObject]@{
        width        = $width
        height       = $height
        refresh_rate = $refreshRate
    }
}

# Helper to enable physical Wi-Fi adapter if disabled
function Enable-WifiAdapter {
    Write-Host "[*] Checking Wi-Fi adapter status..." -ForegroundColor Yellow
    $wifi = Get-NetAdapter -Name "Wi-Fi" -ErrorAction SilentlyContinue
    if ($wifi) {
        if ($wifi.Status -eq "Disabled" -or $wifi.Status -eq "Not Present") {
            Write-Host " -> Enabling Wi-Fi adapter..." -ForegroundColor Cyan
            Enable-NetAdapter -Name "Wi-Fi" -Confirm:$false
            Start-Sleep -Seconds 2
        } else {
            Write-Host " -> Wi-Fi adapter is already active." -ForegroundColor Green
        }
    } else {
        Write-Host " -> [WARNING] Wi-Fi adapter named 'Wi-Fi' not found." -ForegroundColor Yellow
    }
}

# Starts Windows Mobile Hotspot
function Start-Hotspot {
    Write-Host "[*] Activating Mobile Hotspot..." -ForegroundColor Yellow
    try {
        Add-Type -AssemblyName System.Runtime.WindowsRuntime
        $profile = [Windows.Networking.Connectivity.NetworkInformation, Windows.Networking.Connectivity, ContentType = WindowsRuntime]::GetInternetConnectionProfile()
        $tether = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager, Windows.Networking.NetworkOperators, ContentType = WindowsRuntime]::CreateFromConnectionProfile($profile)

        if ($tether.TetheringOperationalState -eq "Off") {
            $asyncOp = $tether.StartTetheringAsync()
            while ($asyncOp.Status -eq "Started") { Start-Sleep -Milliseconds 100 }
            $result = $asyncOp.GetResults()
            if ($result.Status -eq "Success" -or $tether.TetheringOperationalState -eq "On") {
                Write-Host " -> Mobile Hotspot successfully activated!" -ForegroundColor Green
            } else {
                Write-Host " -> Failed to activate Hotspot: $($result.Status)" -ForegroundColor Red
            }
        } else {
            Write-Host " -> Mobile Hotspot is already active." -ForegroundColor Green
        }
    } catch {
        Write-Host " -> [ERROR] Failed to start Mobile Hotspot: $_" -ForegroundColor Red
    }
}

# Stops Windows Mobile Hotspot
function Stop-Hotspot {
    Write-Host "[*] Deactivating Mobile Hotspot..." -ForegroundColor Yellow
    try {
        Add-Type -AssemblyName System.Runtime.WindowsRuntime
        $profile = [Windows.Networking.Connectivity.NetworkInformation, Windows.Networking.Connectivity, ContentType = WindowsRuntime]::GetInternetConnectionProfile()
        $tether = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager, Windows.Networking.NetworkOperators, ContentType = WindowsRuntime]::CreateFromConnectionProfile($profile)

        if ($tether.TetheringOperationalState -eq "On") {
            $asyncOp = $tether.StopTetheringAsync()
            while ($asyncOp.Status -eq "Started") { Start-Sleep -Milliseconds 100 }
            Write-Host " -> Mobile Hotspot successfully deactivated." -ForegroundColor Green
        } else {
            Write-Host " -> Mobile Hotspot is already off." -ForegroundColor Green
        }
    } catch {
        Write-Host " -> [ERROR] Failed to stop Mobile Hotspot: $_" -ForegroundColor Red
    }
}

# Starts Sunshine Service
function Start-Sunshine {
    Write-Host "[*] Checking Sunshine service..." -ForegroundColor Yellow
    $service = Get-Service -Name "SunshineService" -ErrorAction SilentlyContinue
    if ($service) {
        if ($service.Status -ne "Running") {
            Write-Host " -> Starting Sunshine service..." -ForegroundColor Cyan
            Start-Service -Name "SunshineService"
            Start-Sleep -Seconds 1
        }
        Write-Host " -> Sunshine service is running." -ForegroundColor Green
    } else {
        Write-Host " -> [ERROR] SunshineService is not installed as a Windows service." -ForegroundColor Red
    }
}

# Stops Sunshine Service
function Stop-Sunshine {
    Write-Host "[*] Stopping Sunshine service..." -ForegroundColor Yellow
    $service = Get-Service -Name "SunshineService" -ErrorAction SilentlyContinue
    if ($service -and $service.Status -eq "Running") {
        Stop-Service -Name "SunshineService" -ErrorAction SilentlyContinue
        Write-Host " -> Sunshine service stopped." -ForegroundColor Green
    }
}

# Enables Virtual Display and switches projection to external only
function Start-VirtualDisplay {
    Write-Host "[*] Enabling Virtual Display..." -ForegroundColor Yellow
    try {
        $cfg = Get-Config
        if (!(Test-Path $VddDir)) {
            New-Item -ItemType Directory -Path $VddDir -Force | Out-Null
        }
        $xmlContent = @"
<?xml version="1.0" encoding="utf-8"?>
<vdd_settings>
    <monitors>
        <count>1</count>
    </monitors>
    <resolutions>
        <resolution>
            <width>$($cfg.width)</width>
            <height>$($cfg.height)</height>
            <refresh_rate>$($cfg.refresh_rate)</refresh_rate>
        </resolution>
    </resolutions>
</vdd_settings>
"@
        Set-Content -Path $VddXmlFile -Value $xmlContent -Force

        $devices = Get-PnpDevice -Class Display | Where-Object { $_.FriendlyName -match "Virtual Display Driver" }
        if ($devices) {
            foreach ($device in $devices) {
                Enable-PnpDevice -InstanceId $device.InstanceId -Confirm:$false
            }
            Start-Sleep -Seconds 1
            # Switch display mode to Second Screen Only (blanks out physical screen)
            displayswitch.exe /external
            Write-Host " -> Virtual Display active ($($cfg.width)x$($cfg.height) @ $($cfg.refresh_rate)Hz). PC Monitor turned off." -ForegroundColor Green
        } else {
            Write-Host " -> [ERROR] Virtual Display Driver device not found in Device Manager." -ForegroundColor Red
        }
    } catch {
        Write-Host " -> [ERROR] Failed to enable Virtual Display: $_" -ForegroundColor Red
    }
}

# Disables Virtual Display and restores internal display
function Stop-VirtualDisplay {
    Write-Host "[*] Disabling Virtual Display..." -ForegroundColor Yellow
    try {
        # Restore internal display mode first (forces PC monitor back on)
        displayswitch.exe /internal
        Start-Sleep -Seconds 1
        $devices = Get-PnpDevice -Class Display | Where-Object { $_.FriendlyName -match "Virtual Display Driver" }
        if ($devices) {
            foreach ($device in $devices) {
                Disable-PnpDevice -InstanceId $device.InstanceId -Confirm:$false
            }
            Write-Host " -> Virtual Display successfully disabled. PC Monitor turned back on." -ForegroundColor Green
        } else {
            Write-Host " -> [WARNING] Virtual Display Driver device not found." -ForegroundColor Yellow
        }
    } catch {
        Write-Host " -> [ERROR] Failed to disable Virtual Display: $_" -ForegroundColor Red
    }
}

# Resolution configuration menu
function Set-Resolution {
    Clear-Host
    Write-Host "====================================================" -ForegroundColor Cyan
    Write-Host "             SELECT DEVICE DISPLAY RESOLUTION       " -ForegroundColor Cyan
    Write-Host "====================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "1. Motorola Edge X30 (2400x1080 @ 120Hz)" -ForegroundColor Green
    Write-Host "2. Motorola Edge X30 (2400x1080 @ 144Hz)" -ForegroundColor Green
    Write-Host "3. Retro Handheld Console (640x480 @ 60Hz)" -ForegroundColor Yellow
    Write-Host "4. Standard Full HD (1920x1080 @ 60Hz)" -ForegroundColor White
    Write-Host "5. Custom Resolution..." -ForegroundColor Cyan
    Write-Host "6. Back" -ForegroundColor White
    Write-Host ""
    
    $choice = Read-Host "Select an option (1-6)"
    $width = 2400
    $height = 1080
    $hz = 120
    $valid = $true

    switch ($choice) {
        "1" { $width = 2400; $height = 1080; $hz = 120 }
        "2" { $width = 2400; $height = 1080; $hz = 144 }
        "3" { $width = 640; $height = 480; $hz = 60 }
        "4" { $width = 1920; $height = 1080; $hz = 60 }
        "5" {
            $w = Read-Host "Enter Width (e.g., 1280)"
            $h = Read-Host "Enter Height (e.g., 800)"
            $r = Read-Host "Enter Refresh Rate in Hz (e.g., 60)"
            if ($w -as [int] -and $h -as [int] -and $r -as [int]) {
                $width = [int]$w
                $height = [int]$h
                $hz = [int]$r
            } else {
                Write-Host "Invalid inputs. Canceled." -ForegroundColor Red
                $valid = $false
                Start-Sleep -Seconds 2
            }
        }
        default { $valid = $false }
    }

    if ($valid) {
        $config = @{
            width        = $width
            height       = $height
            refresh_rate = $hz
        }
        $config | ConvertTo-Json | Set-Content -Path $ConfigFile -Force
        Write-Host "`nResolution saved! Applying settings..." -ForegroundColor Green
        
        # If the virtual display is currently active, restart it to apply changes on-the-fly
        $devices = Get-PnpDevice -Class Display | Where-Object { $_.FriendlyName -match "Virtual Display Driver" }
        if ($devices -and ($devices | Where-Object { $_.Status -eq "OK" })) {
            Start-VirtualDisplay
        } else {
            Start-Sleep -Seconds 1
        }
    }
}

# Shows the live status of all orchestrator components
function Show-Status {
    Clear-Host
    Write-Host "====================================================" -ForegroundColor Cyan
    Write-Host "             STREAMING DIRECT SYSTEM STATUS         " -ForegroundColor Cyan
    Write-Host "====================================================" -ForegroundColor Cyan
    Write-Host ""

    # 1. Wi-Fi Adapter
    $wifi = Get-NetAdapter -Name "Wi-Fi" -ErrorAction SilentlyContinue
    $wifiStatus = if ($wifi) { $wifi.Status } else { "Not Found" }
    $prefBand = Get-NetAdapterAdvancedProperty -Name "Wi-Fi" -DisplayName "Preferred Band" -ErrorAction SilentlyContinue
    $prefBandVal = if ($prefBand) { $prefBand.DisplayValue } else { "N/A" }
    
    $wifiColor = if ($wifiStatus -eq "Up") { "Green" } else { "Red" }
    Write-Host "Wi-Fi Network Adapter:" -ForegroundColor Yellow
    Write-Host "  Adapter Status: $wifiStatus" -ForegroundColor $wifiColor
    Write-Host "  Band Preference: $prefBandVal" -ForegroundColor Gray

    # 2. Virtual Display
    $vds = Get-PnpDevice -Class Display | Where-Object { $_.FriendlyName -match "Virtual Display Driver" }
    $vdStatus = if ($vds) {
        $activeCount = @($vds | Where-Object { $_.Status -eq "OK" }).Count
        if ($vds.Count -gt 1) {
            "Active (Duplicate! $($vds.Count) detected, $($activeCount) enabled)"
        } elseif ($vds.Status -eq "OK") {
            "Active (Enabled)"
        } else {
            "Inactive (Disabled)"
        }
    } else {
        "Not Installed"
    }
    
    $cfg = Get-Config
    $resStr = "$($cfg.width)x$($cfg.height) @ $($cfg.refresh_rate)Hz"
    $vdColor = if ($vdStatus -match "Active") { "Green" } else { "Red" }
    Write-Host "`nVirtual Display:" -ForegroundColor Yellow
    Write-Host "  Adapter State: $vdStatus" -ForegroundColor $vdColor
    Write-Host "  Resolution Configured: $resStr" -ForegroundColor Gray

    # 3. Mobile Hotspot
    Add-Type -AssemblyName System.Runtime.WindowsRuntime
    $profile = [Windows.Networking.Connectivity.NetworkInformation, Windows.Networking.Connectivity, ContentType = WindowsRuntime]::GetInternetConnectionProfile()
    $tether = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager, Windows.Networking.NetworkOperators, ContentType = WindowsRuntime]::CreateFromConnectionProfile($profile)
    $state = $tether.TetheringOperationalState
    $hotspotConfig = $tether.GetCurrentAccessPointConfiguration()
    
    $stateColor = if ($state -eq "On") { "Green" } else { "Red" }
    Write-Host "`nWindows Mobile Hotspot:" -ForegroundColor Yellow
    Write-Host "  State: $state" -ForegroundColor $stateColor
    if ($state -eq "On" -and $hotspotConfig) {
        Write-Host "  Network Name (SSID): $($hotspotConfig.Ssid)" -ForegroundColor Gray
        Write-Host "  Active Band: $($hotspotConfig.Band)" -ForegroundColor Gray
        Write-Host "  PC Hotspot IP Address: 192.168.137.1" -ForegroundColor Green
    }

    # 4. Connected Hotspot Devices
    if ($state -eq "On") {
        $clients = arp -a | Where-Object { $_ -match "192\.168\.137\." -and $_ -notmatch "255" } | ForEach-Object {
            if ($_.trim() -match "^(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})\s+([0-9a-fA-F\-]{17})") {
                [PSCustomObject]@{
                    IP  = $Matches[1]
                    MAC = $Matches[2]
                }
            }
        }
        Write-Host "`nConnected Devices on Hotspot:" -ForegroundColor Yellow
        if ($clients) {
            foreach ($c in $clients) {
                Write-Host "  -> IP: $($c.IP)  (MAC: $($c.MAC))" -ForegroundColor Green
            }
        } else {
            Write-Host "  No devices connected at the moment." -ForegroundColor Gray
        }
    }

    # 5. Sunshine Service
    $sunshine = Get-Service -Name "SunshineService" -ErrorAction SilentlyContinue
    $sunshineStatus = if ($sunshine) { $sunshine.Status } else { "Not Installed" }
    $sunshineColor = if ($sunshineStatus -eq "Running") { "Green" } else { "Red" }
    Write-Host "`nSunshine Service:" -ForegroundColor Yellow
    Write-Host "  Status: $sunshineStatus" -ForegroundColor $sunshineColor

    Write-Host ""
    Write-Host "Press [Q] to return to the menu..." -ForegroundColor Gray
    do {
        $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    } while ($key.Character -ne 'q' -and $key.Character -ne 'Q')
}

# Main Menu Loop
do {
    Clear-Host
    Write-Host "====================================================" -ForegroundColor Cyan
    Write-Host "        STREAMING DIRECT ORCHESTRATOR (5GHZ)        " -ForegroundColor Cyan
    Write-Host "====================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "1. Start Streaming (Enable Hotspot, Sunshine & Virtual Screen)" -ForegroundColor Green
    Write-Host "2. Stop Streaming (Disable Hotspot, Sunshine & Restore Screen)" -ForegroundColor Red
    Write-Host "3. Turn ON Virtual Display (Turn OFF PC Monitor)" -ForegroundColor Green
    Write-Host "4. Turn OFF Virtual Display (Turn ON PC Monitor)" -ForegroundColor Red
    Write-Host "5. Configure Device Resolution" -ForegroundColor Cyan
    Write-Host "6. Check Status and Connected Devices" -ForegroundColor Blue
    Write-Host "7. Exit" -ForegroundColor White
    Write-Host ""
    
    $choice = Read-Host "Select an option (1-7)"
    
    switch ($choice) {
        "1" {
            Write-Host ""
            Enable-WifiAdapter
            Start-Hotspot
            Start-Sunshine
            Start-VirtualDisplay
            Write-Host "`nStream ready! Connect your client to PC IP: 192.168.137.1" -ForegroundColor Yellow
            Start-Sleep -Seconds 4
        }
        "2" {
            Write-Host ""
            Stop-VirtualDisplay
            Stop-Sunshine
            Stop-Hotspot
            Write-Host "`nStreaming environment stopped." -ForegroundColor Yellow
            Start-Sleep -Seconds 3
        }
        "3" {
            Write-Host ""
            Start-VirtualDisplay
            Start-Sleep -Seconds 2
        }
        "4" {
            Write-Host ""
            Stop-VirtualDisplay
            Start-Sleep -Seconds 2
        }
        "5" {
            Set-Resolution
        }
        "6" {
            Show-Status
        }
        "7" {
            break
        }
        default {
            Write-Host "Invalid option. Please try again." -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
} while ($choice -ne "7")
