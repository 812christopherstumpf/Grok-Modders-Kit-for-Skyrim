<#
    Skyrim Modding Assistant - Windows setup script
    Version : 1.0.0
    Date    : 2026-10-22

    MIT License

    Copyright (c) 2026 Skyrim Modding Assistant contributors

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.

    This script only downloads third-party tools from their official sources.
    It does not bundle or redistribute them. Credits and licenses:
      - Tailscale ......... Tailscale Inc.            https://github.com/tailscale/tailscale/blob/main/LICENSE (BSD-3-Clause client)
      - Git for Windows ... Git for Windows project    https://github.com/git-for-windows/git/blob/main/COPYING (GPL-2.0)
      - OpenSSH (Windows) . Microsoft / OpenBSD team   https://github.com/PowerShell/openssh-portable/blob/latestw_all/LICENCE
      - Spriggit .......... Mutagen-Modding (Noggog)   https://github.com/Mutagen-Modding/Spriggit/blob/dev/LICENSE (GPL-3.0)
      - Caprica ........... Orvid and contributors     https://github.com/Orvid/Caprica/blob/master/LICENSE (MIT)
      - .NET Runtime ...... Microsoft / .NET Foundation https://github.com/dotnet/runtime/blob/main/LICENSE.TXT (MIT)
      - 7-Zip (7zr.exe) ... Igor Pavlov                https://www.7-zip.org/license.txt (LGPL-2.1 + unRAR restriction)

    What it never does: touch your Skyrim Data folder, download anything from
    Nexus Mods or Steam, or ask for / store / print any password.
#>

[CmdletBinding()]
param(
    [switch]$Yes,          # skip the Y/N prompt (for advanced users)
    [string]$BotPublicKey  # optional: the bot's SSH PUBLIC key (one line, ssh-ed25519 or ssh-rsa)
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'   # makes Invoke-WebRequest much faster on PS 5.1
$ScriptVersion = '1.0.0'

# ---------------------------------------------------------------- elevation
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host 'Administrator rights are needed. Asking Windows for permission...' -ForegroundColor Yellow
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
    if ($Yes) { $argList += '-Yes' }
    if ($BotPublicKey) { $argList += @('-BotPublicKey', "`"$BotPublicKey`"") }
    try {
        Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -Verb RunAs | Out-Null
    } catch {
        Write-Host 'Permission was not granted. Nothing was changed.' -ForegroundColor Red
    }
    exit
}

# Use TLS 1.2+ for downloads on older Windows PowerShell
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }

# ---------------------------------------------------------------- paths and logging
# When elevated with a different admin account, USERPROFILE is that account's profile.
$ToolsRoot = Join-Path $env:USERPROFILE 'SkyrimModdingTools'
$LogFile   = Join-Path $ToolsRoot 'install.log'
New-Item -ItemType Directory -Path $ToolsRoot -Force | Out-Null

$Summary = New-Object System.Collections.Generic.List[string]

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
    switch ($Level) {
        'ERROR' { Write-Host $Message -ForegroundColor Red }
        'WARN'  { Write-Host $Message -ForegroundColor Yellow }
        'OK'    { Write-Host $Message -ForegroundColor Green }
        default { Write-Host $Message }
    }
}

function Add-Summary {
    param([string]$Item, [string]$Result)
    $Summary.Add(('{0,-28} {1}' -f $Item, $Result))
    Write-Log "$Item -> $Result" 'OK'
}

function Test-Command { param([string]$Name) return [bool](Get-Command $Name -ErrorAction SilentlyContinue) }

function Update-SessionPath {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user    = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = (@($machine, $user) | Where-Object { $_ }) -join ';'
}

function Add-ToUserPath {
    param([string]$Dir)
    $current = [Environment]::GetEnvironmentVariable('Path', 'User')
    $parts = @()
    if ($current) { $parts = $current.Split(';') | Where-Object { $_ -ne '' } }
    if ($parts -contains $Dir) {
        Write-Log "Already on user PATH: $Dir"
        return
    }
    $parts += $Dir
    [Environment]::SetEnvironmentVariable('Path', ($parts -join ';'), 'User')
    Update-SessionPath
    Write-Log "Added to user PATH: $Dir"
}

function Test-Winget { return (Test-Command 'winget') }

function Install-WithWinget {
    param([string]$Id)
    if (-not (Test-Winget)) { return $false }
    Write-Log "Installing $Id with winget..."
    $out = & winget install --id $Id --exact --silent --accept-package-agreements --accept-source-agreements --disable-interactivity 2>&1
    $out | ForEach-Object { Add-Content -Path $LogFile -Value "    winget: $_" -Encoding UTF8 }
    # 0 = installed; -1978335189 (0x8A15002B) = already installed / no upgrade available
    if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq -1978335189) { return $true }
    Write-Log "winget returned exit code $LASTEXITCODE for $Id" 'WARN'
    return $false
}

function Get-File {
    param([string]$Url, [string]$OutFile)
    Write-Log "Downloading $Url"
    Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing -Headers @{ 'User-Agent' = 'SkyrimModdingAssistant-Installer' }
}

function Install-FromUrl {
    param([string]$Url, [string]$FileName, [string[]]$InstallerArgs)
    $tmp = Join-Path $env:TEMP $FileName
    Get-File -Url $Url -OutFile $tmp
    Write-Log "Running $FileName $($InstallerArgs -join ' ')"
    $p = Start-Process -FilePath $tmp -ArgumentList $InstallerArgs -Wait -PassThru
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) { throw "$FileName exited with code $($p.ExitCode)" }
}

function Get-LatestRelease {
    param([string]$Repo)
    $api = "https://api.github.com/repos/$Repo/releases/latest"
    Write-Log "Asking GitHub for the latest release: $api"
    return Invoke-RestMethod -Uri $api -UseBasicParsing -Headers @{ 'User-Agent' = 'SkyrimModdingAssistant-Installer'; 'Accept' = 'application/vnd.github+json' }
}

# ---------------------------------------------------------------- explain and confirm
Clear-Host
Write-Host '=================================================================' -ForegroundColor Cyan
Write-Host "  Skyrim Modding Assistant - PC setup (version $ScriptVersion)"    -ForegroundColor Cyan
Write-Host '=================================================================' -ForegroundColor Cyan
Write-Host @"

This will set up your PC so the Skyrim Modding Assistant bot can help you
over a private Tailscale connection. It will:

  1. Install Tailscale (private network) and Git for Windows (includes Git Bash)
  2. Turn on the built-in Windows OpenSSH Server, start it automatically, and
     allow port 22 ONLY from Tailscale addresses (100.64.0.0/10)
  3. Make Git Bash the default shell for SSH logins (if Git Bash is installed)
     and (optionally) add the bot's SSH PUBLIC key so it can log in
  4. Download Spriggit CLI and the Caprica Papyrus compiler from GitHub into
     $ToolsRoot and add them to your PATH
  5. Install the Microsoft .NET 10 Runtime (needed by Spriggit CLI)

It will NOT touch your Skyrim Data folder, will NOT download anything from
Nexus Mods or Steam, and will NEVER ask for or show any password.
Anything already installed is skipped. A log is written to:
  $LogFile

"@

Write-Log "=== Installer $ScriptVersion started by $env:USERNAME on $env:COMPUTERNAME ==="

if (-not $Yes) {
    $answer = Read-Host 'Continue? Type Y and press Enter (anything else cancels)'
    if ($answer -notmatch '^\s*[Yy]') {
        Write-Log 'User cancelled. Nothing was changed.' 'WARN'
        Read-Host 'Press Enter to close'
        exit 0
    }
}
Write-Log 'User confirmed. Starting.'

if (-not (Test-Winget)) {
    Write-Log 'winget was not found. Using official download links instead (that is fine).' 'WARN'
}

# ---------------------------------------------------------------- 1. Tailscale
try {
    $tsExe = Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe'
    if ((Test-Path $tsExe) -or (Test-Command 'tailscale')) {
        Add-Summary 'Tailscale' 'already installed (skipped)'
    } else {
        if (-not (Install-WithWinget 'Tailscale.Tailscale')) {
            Install-FromUrl -Url 'https://pkgs.tailscale.com/stable/tailscale-setup-latest.exe' -FileName 'tailscale-setup-latest.exe' -InstallerArgs @('/quiet')
        }
        Update-SessionPath
        Add-Summary 'Tailscale' 'installed'
    }
} catch { Write-Log "Tailscale install failed: $($_.Exception.Message)" 'ERROR'; Add-Summary 'Tailscale' 'FAILED - see log' }

# ---------------------------------------------------------------- 2. Git for Windows
function Get-GitBashPath {
    foreach ($p in @("$env:ProgramFiles\Git\bin\bash.exe", "${env:ProgramFiles(x86)}\Git\bin\bash.exe", "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe")) {
        if ($p -and (Test-Path $p)) { return $p }
    }
    return $null
}
try {
    if ((Get-GitBashPath) -or (Test-Command 'git')) {
        Add-Summary 'Git for Windows' 'already installed (skipped)'
    } else {
        if (-not (Install-WithWinget 'Git.Git')) {
            $rel = Get-LatestRelease 'git-for-windows/git'
            $asset = $rel.assets | Where-Object { $_.name -match '^Git-.*-64-bit\.exe$' } | Select-Object -First 1
            if (-not $asset) { throw 'Could not find the 64-bit Git installer in the latest release.' }
            Install-FromUrl -Url $asset.browser_download_url -FileName $asset.name -InstallerArgs @('/VERYSILENT', '/NORESTART', '/NOCANCEL', '/SP-')
        }
        Update-SessionPath
        Add-Summary 'Git for Windows' 'installed'
    }
} catch { Write-Log "Git install failed: $($_.Exception.Message)" 'ERROR'; Add-Summary 'Git for Windows' 'FAILED - see log' }

# ---------------------------------------------------------------- 3. OpenSSH Server
try {
    $cap = Get-WindowsCapability -Online | Where-Object { $_.Name -like 'OpenSSH.Server*' } | Select-Object -First 1
    if (-not $cap) { throw 'OpenSSH Server capability not offered by this Windows build.' }
    if ($cap.State -eq 'Installed') {
        Add-Summary 'OpenSSH Server' 'already installed (skipped)'
    } else {
        Write-Log 'Enabling OpenSSH Server (this can take a few minutes)...'
        Add-WindowsCapability -Online -Name $cap.Name | Out-Null
        Add-Summary 'OpenSSH Server' 'installed'
    }

    Set-Service -Name sshd -StartupType Automatic
    if ((Get-Service sshd).Status -ne 'Running') { Start-Service sshd }
    Add-Summary 'sshd service' 'running, startup Automatic'

    # Firewall: allow 22 from Tailscale CGNAT range only.
    $ruleName = 'SkyrimModdingAssistant-SSH-Tailscale'
    $existing = Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue
    if ($existing) {
        Add-Summary 'Firewall rule (port 22)' 'already present (skipped)'
    } else {
        $ruleArgs = @{
            Name          = $ruleName
            DisplayName   = 'Skyrim Modding Assistant - SSH over Tailscale only'
            Direction     = 'Inbound'
            Protocol      = 'TCP'
            LocalPort     = 22
            RemoteAddress = '100.64.0.0/10'
            Action        = 'Allow'
            Profile       = 'Any'
        }
        $tsAdapter = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.InterfaceDescription -like '*Tailscale*' -or $_.Name -like '*Tailscale*' } | Select-Object -First 1
        if ($tsAdapter) { $ruleArgs['InterfaceAlias'] = $tsAdapter.Name }
        New-NetFirewallRule @ruleArgs | Out-Null
        $how = if ($tsAdapter) { "100.64.0.0/10 on adapter '$($tsAdapter.Name)'" } else { '100.64.0.0/10 (any adapter)' }
        Add-Summary 'Firewall rule (port 22)' "added, limited to $how"
    }
    # Windows creates a broad "OpenSSH-Server-In-TCP" rule (any address). Disable it so only our narrow rule applies.
    $broad = Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue
    if ($broad -and $broad.Enabled -eq 'True') {
        Disable-NetFirewallRule -Name 'OpenSSH-Server-In-TCP'
        Add-Summary 'Default OpenSSH rule' 'disabled (was open to all addresses)'
    }

    # Default SSH shell -> Git Bash
    $bash = Get-GitBashPath
    if ($bash) {
        $regPath = 'HKLM:\SOFTWARE\OpenSSH'
        if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
        $cur = (Get-ItemProperty -Path $regPath -Name DefaultShell -ErrorAction SilentlyContinue).DefaultShell
        if ($cur -eq $bash) {
            Add-Summary 'Default SSH shell' 'already Git Bash (skipped)'
        } else {
            New-ItemProperty -Path $regPath -Name DefaultShell -Value $bash -PropertyType String -Force | Out-Null
            Add-Summary 'Default SSH shell' "set to $bash"
        }
    } else {
        Add-Summary 'Default SSH shell' 'Git Bash not found, left as Windows default'
    }
} catch { Write-Log "OpenSSH setup failed: $($_.Exception.Message)" 'ERROR'; Add-Summary 'OpenSSH Server' 'FAILED - see log' }

# ---------------------------------------------------------------- 3b. Bot SSH public key (optional)
function Test-PublicKeyLine {
    param([string]$Key)
    if (-not $Key) { return $false }
    if ($Key -match "[\r\n]") { return $false }
    # type, base64 body, optional comment. Private keys / passwords never match this.
    return ($Key -match '^(ssh-ed25519|ssh-rsa) [A-Za-z0-9+/]+={0,3}( [^\s].*)?$')
}

function Test-UserIsAdmin {
    # The script itself is elevated; check whether the signed-in Windows user is in the local Administrators group.
    try {
        $members = Get-LocalGroupMember -SID 'S-1-5-32-544' -ErrorAction Stop
        $me = "$env:USERDOMAIN\$env:USERNAME"
        return [bool]($members | Where-Object { $_.Name -ieq $me -or $_.Name -like "*\$env:USERNAME" })
    } catch {
        return $true   # running elevated as this user implies admin rights
    }
}

try {
    $key = $null
    if ($BotPublicKey) {
        $key = $BotPublicKey.Trim()
    } elseif (-not $Yes) {
        Write-Host @'

OPTIONAL: add the bot's SSH PUBLIC key so it can log in.
  - A public key is safe to share. It is ONE line starting with
    "ssh-ed25519" or "ssh-rsa", given to you by the bot.
  - It is NOT a password. Never paste a password here (or anywhere for the bot).
  - Press Enter on an empty line to skip this step.
'@ -ForegroundColor Cyan
        $key = (Read-Host 'Paste the bot public key (or press Enter to skip)')
        if ($key) { $key = $key.Trim() }
    }

    if (-not $key) {
        Add-Summary 'Bot SSH public key' 'skipped (none provided)'
    } else {
        while (-not (Test-PublicKeyLine $key)) {
            # Never echo rejected input: it might be a secret pasted by mistake.
            Write-Log 'That does not look like a public key (must be one line starting with ssh-ed25519 or ssh-rsa). It was rejected and not saved.' 'WARN'
            if ($BotPublicKey -or $Yes) { $key = $null; break }
            $key = Read-Host 'Paste the bot public key again (or press Enter to skip)'
            if ($key) { $key = $key.Trim() } else { break }
        }

        if (-not $key) {
            Add-Summary 'Bot SSH public key' 'skipped (no valid key)'
        } else {
            $isAdmin = Test-UserIsAdmin
            if ($isAdmin) {
                $keyFile = Join-Path $env:ProgramData 'ssh\administrators_authorized_keys'
            } else {
                $keyFile = Join-Path $env:USERPROFILE '.ssh\authorized_keys'
            }
            $keyDir = Split-Path $keyFile -Parent
            if (-not (Test-Path $keyDir)) { New-Item -ItemType Directory -Path $keyDir -Force | Out-Null }

            # Deduplicate on type + key body (ignore the comment).
            $body = ($key -split ' ')[0..1] -join ' '
            $existingLines = @()
            if (Test-Path $keyFile) { $existingLines = @(Get-Content -Path $keyFile -ErrorAction SilentlyContinue) }
            $already = $existingLines | Where-Object { $_.Trim() -and ((($_.Trim() -split ' ')[0..1] -join ' ') -eq $body) }

            if ($already) {
                Add-Summary 'Bot SSH public key' "already in $keyFile (skipped)"
            } else {
                # Write ASCII with no BOM; OpenSSH on Windows can reject UTF-16/BOM files.
                $prefix = ''
                if ((Test-Path $keyFile) -and (Get-Item $keyFile).Length -gt 0) {
                    $raw = [IO.File]::ReadAllText($keyFile)
                    if (-not $raw.EndsWith("`n")) { $prefix = "`r`n" }
                }
                [IO.File]::AppendAllText($keyFile, "$prefix$key`r`n", (New-Object Text.ASCIIEncoding))
                Add-Summary 'Bot SSH public key' "added to $keyFile"
            }

            if ($isAdmin) {
                & icacls.exe $keyFile /inheritance:r /grant 'Administrators:F' /grant 'SYSTEM:F' | ForEach-Object { Add-Content -Path $LogFile -Value "    icacls: $_" -Encoding UTF8 }
                if ($LASTEXITCODE -ne 0) { throw "icacls failed with exit code $LASTEXITCODE" }
                Write-Log "Permissions set on $keyFile (Administrators and SYSTEM only)."
            } else {
                & icacls.exe $keyFile /inheritance:r /grant "$($env:USERNAME):F" /grant 'SYSTEM:F' /grant 'Administrators:F' | ForEach-Object { Add-Content -Path $LogFile -Value "    icacls: $_" -Encoding UTF8 }
                if ($LASTEXITCODE -ne 0) { throw "icacls failed with exit code $LASTEXITCODE" }
                Write-Log "Permissions set on $keyFile (you, Administrators and SYSTEM only)."
            }

            Restart-Service sshd
            Add-Summary 'sshd service' 'restarted to load the key'
        }
    }
} catch { Write-Log "Adding the bot key failed: $($_.Exception.Message)" 'ERROR'; Add-Summary 'Bot SSH public key' 'FAILED - see log' }

# ---------------------------------------------------------------- 4. .NET 10 Runtime (for Spriggit)
try {
    $hasNet10 = $false
    if (Test-Command 'dotnet') {
        $rt = & dotnet --list-runtimes 2>$null
        if ($rt -match 'Microsoft\.NETCore\.App 10\.') { $hasNet10 = $true }
    }
    if ($hasNet10) {
        Add-Summary '.NET 10 Runtime' 'already installed (skipped)'
    } else {
        if (-not (Install-WithWinget 'Microsoft.DotNet.Runtime.10')) {
            $dotnetScript = Join-Path $env:TEMP 'dotnet-install.ps1'
            Get-File -Url 'https://dot.net/v1/dotnet-install.ps1' -OutFile $dotnetScript
            & $dotnetScript -Channel 10.0 -Runtime dotnet -InstallDir "$env:ProgramFiles\dotnet"
            Remove-Item $dotnetScript -Force -ErrorAction SilentlyContinue
        }
        Update-SessionPath
        Add-Summary '.NET 10 Runtime' 'installed'
    }
} catch { Write-Log ".NET install failed: $($_.Exception.Message)" 'ERROR'; Add-Summary '.NET 10 Runtime' 'FAILED - see log' }

# ---------------------------------------------------------------- 5. Spriggit CLI
try {
    $spDir = Join-Path $ToolsRoot 'Spriggit'
    $spExe = Get-ChildItem -Path $spDir -Filter 'Spriggit.CLI.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($spExe) {
        Add-Summary 'Spriggit CLI' 'already present (skipped)'
    } else {
        $rel = Get-LatestRelease 'Mutagen-Modding/Spriggit'
        $asset = $rel.assets | Where-Object { $_.name -eq 'SpriggitCLI.zip' } | Select-Object -First 1
        if (-not $asset) { throw 'SpriggitCLI.zip not found in the latest Spriggit release.' }
        $zip = Join-Path $env:TEMP 'SpriggitCLI.zip'
        Get-File -Url $asset.browser_download_url -OutFile $zip
        New-Item -ItemType Directory -Path $spDir -Force | Out-Null
        Expand-Archive -Path $zip -DestinationPath $spDir -Force
        Remove-Item $zip -Force -ErrorAction SilentlyContinue
        $spExe = Get-ChildItem -Path $spDir -Filter 'Spriggit.CLI.exe' -Recurse | Select-Object -First 1
        if (-not $spExe) { throw 'Spriggit.CLI.exe not found after unpacking.' }
        Add-Summary 'Spriggit CLI' "installed $($rel.tag_name)"
    }
    Add-ToUserPath $spExe.DirectoryName
} catch { Write-Log "Spriggit install failed: $($_.Exception.Message)" 'ERROR'; Add-Summary 'Spriggit CLI' 'FAILED - see log' }

# ---------------------------------------------------------------- 6. Caprica
try {
    $capDir = Join-Path $ToolsRoot 'Caprica'
    $capExe = Get-ChildItem -Path $capDir -Filter 'Caprica.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($capExe) {
        Add-Summary 'Caprica' 'already present (skipped)'
    } else {
        $rel = Get-LatestRelease 'Orvid/Caprica'
        $asset = $rel.assets | Where-Object { $_.name -match '\.(zip|7z)$' } | Select-Object -First 1
        if (-not $asset) { throw 'No Caprica archive found in the latest release.' }
        $archive = Join-Path $env:TEMP $asset.name
        Get-File -Url $asset.browser_download_url -OutFile $archive
        New-Item -ItemType Directory -Path $capDir -Force | Out-Null
        if ($asset.name -like '*.zip') {
            Expand-Archive -Path $archive -DestinationPath $capDir -Force
        } else {
            # .7z needs 7-Zip. Use an installed copy, or the official standalone 7zr.exe.
            $sevenZip = @("$env:ProgramFiles\7-Zip\7z.exe", "${env:ProgramFiles(x86)}\7-Zip\7z.exe") | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
            if (-not $sevenZip) {
                $sevenZip = Join-Path $ToolsRoot '7zr.exe'
                if (-not (Test-Path $sevenZip)) { Get-File -Url 'https://www.7-zip.org/a/7zr.exe' -OutFile $sevenZip }
            }
            & $sevenZip x $archive "-o$capDir" -y | ForEach-Object { Add-Content -Path $LogFile -Value "    7z: $_" -Encoding UTF8 }
            if ($LASTEXITCODE -ne 0) { throw "7-Zip failed with exit code $LASTEXITCODE" }
        }
        Remove-Item $archive -Force -ErrorAction SilentlyContinue
        $capExe = Get-ChildItem -Path $capDir -Filter 'Caprica.exe' -Recurse | Select-Object -First 1
        if (-not $capExe) { throw 'Caprica.exe not found after unpacking.' }
        Add-Summary 'Caprica' "installed $($rel.tag_name)"
    }
    Add-ToUserPath $capExe.DirectoryName
} catch { Write-Log "Caprica install failed: $($_.Exception.Message)" 'ERROR'; Add-Summary 'Caprica' 'FAILED - see log' }

# ---------------------------------------------------------------- 7. Manual tools (never downloaded here)
Write-Host ''
Write-Host '-----------------------------------------------------------------' -ForegroundColor Cyan
Write-Host ' Install these yourself (this script does not download them):'     -ForegroundColor Cyan
Write-Host '-----------------------------------------------------------------' -ForegroundColor Cyan
Write-Host @'
  Mod Organizer 2 (mod manager)  https://github.com/ModOrganizer2/modorganizer/releases
  SSEEdit (xEdit)                https://www.nexusmods.com/skyrimspecialedition/mods/164
  SKSE64                         https://skse.silverlock.org/
  Creation Kit (Steam)           https://store.steampowered.com/app/1946180/Skyrim_Special_Edition_Creation_Kit/

  Install every mod through your mod manager (MO2), not by copying files
  into the Skyrim Data folder.
'@
Write-Log 'Printed manual-install links for MO2, SSEEdit, SKSE64, Creation Kit.'

# ---------------------------------------------------------------- summary
Write-Host ''
Write-Host '=================================================================' -ForegroundColor Cyan
Write-Host ' Summary' -ForegroundColor Cyan
Write-Host '=================================================================' -ForegroundColor Cyan
$Summary | ForEach-Object { Write-Host "  $_" }

Write-Host @"

NEXT STEPS
  1. Sign in to Tailscale: click the Tailscale icon near the clock and choose
     "Log in" (or run:  tailscale up ). Use the same Tailscale account the
     bot was invited to.
  2. Open a new PowerShell window and run:   tailscale status
     The first line shows this PC's Tailscale machine name.
  3. If you skipped the bot key, run this installer again and paste it
     (or use:  install-skyrim-modding-tools.ps1 -BotPublicKey "ssh-ed25519 AAAA...").
  4. Tell the bot two things:
       - the Tailscale machine name from step 2
       - your Windows username:  $env:USERNAME
     (Never send the bot a password. Only its PUBLIC key goes on this PC.)

Log file: $LogFile
"@ -ForegroundColor Green
Write-Log '=== Installer finished ==='
Read-Host 'Press Enter to close'
