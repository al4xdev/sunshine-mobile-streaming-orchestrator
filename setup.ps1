# Streaming Direct Project Installer
# Automatically configures the low-latency direct streaming environment
# and installs the CLI orchestrator to the system.

# Self-elevation check
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    Exit
}

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "         STREAMING DIRECT ENVIRONMENT INSTALLER     " -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host ""

# 1. Clean up old auto-start scheduled tasks (to prevent PC monitor lockouts)
Write-Host "Cleaning up old startup scheduled tasks..." -ForegroundColor Yellow
try {
    Unregister-ScheduledTask -TaskName "AutoStartStreamingHotspot" -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host " -> Startup scheduled task removed." -ForegroundColor Green
} catch {
    Write-Host " -> No startup task found or failed to remove: $_" -ForegroundColor Gray
}

# 2. Configure physical Wi-Fi adapter to prefer 5GHz band
Write-Host "Configuring physical Wi-Fi adapter to prefer 5GHz..." -ForegroundColor Yellow
try {
    Set-NetAdapterAdvancedProperty -Name "Wi-Fi" -DisplayName "Preferred Band" -DisplayValue "3. Prefer 5GHz band" -ErrorAction Stop
    Write-Host " -> Wi-Fi preferred band set to 5GHz." -ForegroundColor Green
} catch {
    Write-Host " -> [WARNING] Could not set preferred band. Please configure 'Preferred Band: 5GHz' manually in Wi-Fi properties if needed." -ForegroundColor Yellow
}

# 3. Configure Mobile Hotspot default band to 5GHz
Write-Host "Configuring Windows Mobile Hotspot default band to 5GHz..." -ForegroundColor Yellow
try {
    Add-Type -AssemblyName System.Runtime.WindowsRuntime
    $profile = [Windows.Networking.Connectivity.NetworkInformation, Windows.Networking.Connectivity, ContentType = WindowsRuntime]::GetInternetConnectionProfile()
    $tether = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager, Windows.Networking.NetworkOperators, ContentType = WindowsRuntime]::CreateFromConnectionProfile($profile)
    $hotspotConfig = $tether.GetCurrentAccessPointConfiguration()
    if ($hotspotConfig) {
        $hotspotConfig.Band = [Windows.Networking.NetworkOperators.TetheringWiFiBand]::FiveGigahertz
        $asyncOp = $tether.ConfigureAccessPointAsync($hotspotConfig)
        while ($asyncOp.Status -eq "Started") { Start-Sleep -Milliseconds 100 }
        Write-Host " -> Hotspot default band configured to 5GHz." -ForegroundColor Green
    } else {
        Write-Host " -> [WARNING] Mobile Hotspot settings not accessible." -ForegroundColor Yellow
    }
} catch {
    Write-Host " -> [WARNING] Could not configure Hotspot band via API: $_" -ForegroundColor Yellow
}

# 4. Optimize Sunshine configuration for low-latency NVENC encoding
Write-Host "Optimizing Sunshine config (NVENC settings)..." -ForegroundColor Yellow
try {
    $sunshineConfigPath = "C:\Program Files\Sunshine\config\sunshine.conf"
    if (Test-Path "C:\Program Files\Sunshine") {
        # Ensure config folder exists
        if (!(Test-Path "C:\Program Files\Sunshine\config")) {
            New-Item -ItemType Directory -Path "C:\Program Files\Sunshine\config" -Force | Out-Null
        }
        $configContent = @"
# Configured by Stream Orchestrator Installer
encoder = nvenc
nvenc_preset = 5
nvenc_twopass = quarter_resolution
nvenc_spatial_aq = 1
"@
        Set-Content -Path $sunshineConfigPath -Value $configContent -Force
        Write-Host " -> sunshine.conf optimized successfully." -ForegroundColor Green
        
        # Restart service to apply configuration
        Stop-Service -Name "SunshineService" -ErrorAction SilentlyContinue
        Start-Service -Name "SunshineService" -ErrorAction SilentlyContinue
    } else {
        Write-Host " -> [WARNING] Sunshine installation not found at standard path." -ForegroundColor Yellow
    }
} catch {
    Write-Host " -> [WARNING] Failed to optimize Sunshine configuration: $_" -ForegroundColor Yellow
}

# 5. Clean up duplicate virtual displays and install exactly one instance
Write-Host "Configuring Virtual Display Driver (removing duplicates)..." -ForegroundColor Yellow
try {
    # Find Virtual Display Driver package installed via winget
    $vddPkgDir = Get-ChildItem -Path "C:\Users\*\AppData\Local\Microsoft\WinGet\Packages\VirtualDrivers.Virtual-Display-Driver*" | Select-Object -First 1 -ExpandProperty FullName
    if (!$vddPkgDir) {
         # Search standard user profiles if wildcard fails
         $vddPkgDir = Get-ChildItem -Path "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\VirtualDrivers.Virtual-Display-Driver*" | Select-Object -First 1 -ExpandProperty FullName
    }
    
    if ($vddPkgDir) {
        $devcon = Join-Path $vddPkgDir "Dependencies\devcon.exe"
        $infFile = Get-ChildItem -Path $vddPkgDir -Filter "MttVDD.inf" -Recurse | Where-Object { $_.FullName -like "*x86*" } | Select-Object -First 1 -ExpandProperty FullName
        
        if ($infFile -and (Test-Path $devcon)) {
            pnputil.exe /add-driver "$infFile" /install | Out-Null
            
            # Wipe all existing virtual monitors to clear any duplicates
            Write-Host " -> Removing duplicate virtual monitor entries..." -ForegroundColor Yellow
            & $devcon remove "Root\MttVDD" | Out-Null
            
            # Create a single clean virtual display device
            $installResult = & $devcon install "$infFile" "Root\MttVDD"
            Write-Host " -> Configured exactly 1 active virtual display monitor." -ForegroundColor Green
        } else {
            Write-Host " -> [ERROR] devcon.exe or MttVDD.inf missing in winget package." -ForegroundColor Red
        }
    } else {
        Write-Host " -> [ERROR] Virtual Display Driver winget package not found. Please install it first using: winget install VirtualDrivers.Virtual-Display-Driver" -ForegroundColor Red
    }
} catch {
    Write-Host " -> [ERROR] Failed to configure virtual display driver: $_" -ForegroundColor Red
}

# 6. Initialize local configuration files with default landscape resolution
Write-Host "Writing local configuration files..." -ForegroundColor Yellow
try {
    $installDir = "$env:LOCALAPPDATA\StreamingDirect"
    if (!(Test-Path $installDir)) {
        New-Item -ItemType Directory -Path $installDir -Force | Out-Null
    }
    
    # Save default 2400x1080 (Landscape Motorola Edge X30) resolution to config
    $configFile = "$installDir\config.json"
    if (!(Test-Path $configFile)) {
        $defaultConfig = @{
            width        = 2400
            height       = 1080
            refresh_rate = 120
        }
        $defaultConfig | ConvertTo-Json | Set-Content -Path $configFile -Force
        Write-Host " -> config.json initialized to 2400x1080 @ 120Hz." -ForegroundColor Green
    } else {
        Write-Host " -> config.json already exists. Keeping current values." -ForegroundColor Green
    }
    
    # Generate VDD settings file
    $vddDir = "C:\VirtualDisplayDriver"
    if (!(Test-Path $vddDir)) {
        New-Item -ItemType Directory -Path $vddDir -Force | Out-Null
    }
    
    # Load configuration
    $saved = Get-Content $configFile -Raw | ConvertFrom-Json
    $xmlContent = @"
<?xml version="1.0" encoding="utf-8"?>
<vdd_settings>
    <monitors>
        <count>1</count>
    </monitors>
    <resolutions>
        <resolution>
            <width>$($saved.width)</width>
            <height>$($saved.height)</height>
            <refresh_rate>$($saved.refresh_rate)</refresh_rate>
        </resolution>
    </resolutions>
</vdd_settings>
"@
    Set-Content -Path "$vddDir\vdd_settings.xml" -Value $xmlContent -Force
    Write-Host " -> vdd_settings.xml generated successfully." -ForegroundColor Green
} catch {
    Write-Host " -> [ERROR] Failed to initialize configuration files: $_" -ForegroundColor Red
}

# 7. Copy orchestrator script to permanent folder
Write-Host "Installing Orchestrator to permanent folder..." -ForegroundColor Yellow
try {
    $sourceScript = Join-Path $PSScriptRoot "orchestrator.ps1"
    $destScript = Join-Path $installDir "orchestrator.ps1"
    
    if (Test-Path $sourceScript) {
        Copy-Item -Path $sourceScript -Destination $destScript -Force
        Write-Host " -> Orchestrator copied to: $destScript" -ForegroundColor Green
    } else {
        Write-Host " -> [ERROR] Source orchestrator.ps1 not found in installer root." -ForegroundColor Red
    }
} catch {
    Write-Host " -> [ERROR] Failed to copy orchestrator script: $_" -ForegroundColor Red
}

# 8. Create Desktop Shortcut pointing to orchestrator.ps1
Write-Host "Creating Desktop Shortcut..." -ForegroundColor Yellow
try {
    # Fetch current user desktop path dynamically (handles OneDrive redirect)
    $desktopPath = [Environment]::GetFolderPath("Desktop")
    if (!$desktopPath -or !(Test-Path $desktopPath)) {
        # Fallback to standard profile folder if desktop path resolution fails
        $desktopPath = Join-Path $env:USERPROFILE "Desktop"
    }
    
    $shortcutPath = Join-Path $desktopPath "Stream Orchestrator.lnk"
    $wshShell = New-Object -ComObject WScript.Shell
    $shortcut = $wshShell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = "powershell.exe"
    $shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$installDir\orchestrator.ps1`""
    $shortcut.IconLocation = "powershell.exe,0"
    $shortcut.Save()
    
    Write-Host " -> Created desktop shortcut: 'Stream Orchestrator'" -ForegroundColor Green
} catch {
    Write-Host " -> [ERROR] Failed to create Desktop Shortcut: $_" -ForegroundColor Red
}

Write-Host ""
Write-Host "====================================================" -ForegroundColor Green
Write-Host "         INSTALLATION COMPLETED SUCCESSFULLY!       " -ForegroundColor Green
Write-Host "====================================================" -ForegroundColor Green
Write-Host "You can now start and manage your streaming using the" -ForegroundColor Gray
Write-Host "'Stream Orchestrator' shortcut on your Desktop." -ForegroundColor Gray
Write-Host ""
Start-Sleep -Seconds 5
