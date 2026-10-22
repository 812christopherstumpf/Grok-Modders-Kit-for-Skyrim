# Skyrim Modding Assistant – PC setup

Sets up a Windows 10/11 modding PC so the Skyrim Modding Assistant bot can help you over a private Tailscale connection. MIT licensed, version 1.0.0 (2026-10-22).

## What it installs
- **Tailscale** (private network) and **Git for Windows** (includes Git Bash) – via winget, or the official download if winget is missing
- **Windows OpenSSH Server** – started automatically; port 22 is allowed **only** from Tailscale addresses (`100.64.0.0/10`). The broad default Windows "OpenSSH-Server-In-TCP" rule is disabled.
- **Git Bash as the default SSH shell** (registry `HKLM\SOFTWARE\OpenSSH\DefaultShell` = `C:\Program Files\Git\bin\bash.exe`). To undo: `Remove-ItemProperty HKLM:\SOFTWARE\OpenSSH -Name DefaultShell`
- **Bot SSH public key (optional)** – paste the bot's public key when asked. It's added once (no duplicates) to `C:\ProgramData\ssh\administrators_authorized_keys` if you're an admin, otherwise `%USERPROFILE%\.ssh\authorized_keys`. Permissions are locked down (admin file: `icacls /inheritance:r`, Administrators:F, SYSTEM:F) and sshd is restarted.
- **.NET 10 Runtime** (Spriggit needs it)
- **Spriggit CLI** and **Caprica** (Papyrus compiler), latest GitHub releases, into `%USERPROFILE%\SkyrimModdingTools\` and added to your PATH

It never touches your Skyrim Data folder, never downloads from Nexus or Steam, and never asks for passwords. Running it again skips anything already installed.

## Steps
1. Download `install.bat` and `install-skyrim-modding-tools.ps1` into the **same folder** (e.g. your Downloads folder).
2. Double-click **install.bat**. Click **Yes** when Windows asks for permission.
3. Read the list, type **Y**, press **Enter**.
4. **Optional, needed for the bot to log in:** when asked, paste the bot's SSH **public key** and press Enter (or press Enter to skip).
   - It's a single line starting with `ssh-ed25519` or `ssh-rsa`. A public key is safe to share; anything else is rejected.
   - **It's never a password.** Never paste a password.
5. When it finishes, sign in to Tailscale (Tailscale icon near the clock → Log in).
6. Open PowerShell and copy-paste:
   ```
   tailscale status
   ```
7. Tell the bot the machine name shown there and your Windows username (shown at the end of the installer). **Never send a password.**

Alternative to step 2 – copy-paste into PowerShell from the folder with the files:
```
powershell -ExecutionPolicy Bypass -File .\install-skyrim-modding-tools.ps1
```

Add the key without the prompt (also works later, safe to re-run):
```
powershell -ExecutionPolicy Bypass -File .\install-skyrim-modding-tools.ps1 -BotPublicKey "ssh-ed25519 AAAA...your-bot-key..."
```

Log: `%USERPROFILE%\SkyrimModdingTools\install.log`

## Install these yourself
- Mod Organizer 2: https://github.com/ModOrganizer2/modorganizer/releases
- SSEEdit (xEdit): https://www.nexusmods.com/skyrimspecialedition/mods/164
- SKSE64: https://skse.silverlock.org/
- Creation Kit (Steam): https://store.steampowered.com/app/1946180/Skyrim_Special_Edition_Creation_Kit/

Install every mod through your mod manager.

## Credits and licenses
| Tool | Authors | License |
|---|---|---|
| Tailscale | Tailscale Inc. | https://github.com/tailscale/tailscale/blob/main/LICENSE |
| Git for Windows | Git for Windows project | https://github.com/git-for-windows/git/blob/main/COPYING |
| Win32-OpenSSH | Microsoft / OpenBSD | https://github.com/PowerShell/openssh-portable/blob/latestw_all/LICENCE |
| Spriggit | Mutagen-Modding (Noggog) | GPL-3.0 – https://github.com/Mutagen-Modding/Spriggit/blob/dev/LICENSE |
| Caprica | Orvid & contributors | MIT – https://github.com/Orvid/Caprica/blob/master/LICENSE |
| .NET | Microsoft / .NET Foundation | MIT – https://github.com/dotnet/runtime/blob/main/LICENSE.TXT |
| 7-Zip (7zr.exe, used to unpack Caprica) | Igor Pavlov | https://www.7-zip.org/license.txt |
