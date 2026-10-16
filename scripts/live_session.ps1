# Windows version of live_session.sh: DOSBox Staging (web API on) plus Evi/gama checkpoints.
# See docs/reference/live-ram-map.md and docs/reference/windows-setup.md.
#   powershell -File scripts\live_session.ps1 start              # open DOSBox (Kevin runs this)
#   powershell -File scripts\live_session.ps1 cp "new map 1"     # checkpoint now (memory + screenshot + registers)
#   powershell -File scripts\live_session.ps1 status             # is the API up, how many checkpoints so far
#
# Settings (environment variables; the defaults suit a standard checkout under %USERPROFILE%\repo):
#   MIRROR_DOSBOX            path to dosbox.exe (default: the released 0.83.0 unzipped in %USERPROFILE%\dosbox-staging-0.83.0)
#   MIRROR_DOSBOX_RESEARCH=1 the dosbox.exe is the research fork: turns writes on and logs file calls
#   MIRROR_GAME_DIR          the game's folder, mounted as C: (default %USERPROFILE%\DOS)
#   GAMA_DIR, EVI_HOME       the gama checkout and the evidence vault
#   MIRROR_DRY_RUN=1         print the DOSBox command instead of running it
param(
    [Parameter(Position = 0)][string]$Command = "",
    [Parameter(Position = 1)][string]$Name = "",
    [Parameter(Position = 2)][string]$Note = ""
)
$ErrorActionPreference = "Stop"

function Setting($name, $default) {
    $v = [Environment]::GetEnvironmentVariable($name)
    if ($v) { $v } else { $default }
}

$Home_ = $env:USERPROFILE
$Dosbox = Setting "MIRROR_DOSBOX" "$Home_\dosbox-staging-0.83.0\x\dosbox-staging-v0.83.0\dosbox.exe"
$GameDir = Setting "MIRROR_GAME_DIR" "$Home_\DOS"
$GamaDir = Setting "GAMA_DIR" "$Home_\repo\gama"
$env:EVI_HOME = Setting "EVI_HOME" "$Home_\repo\mom-evi-vault"
$Api = "http://127.0.0.1:8086/api/v1"
$LogDir = "$Home_\.mirror\dev\DOSbox"

function Gama {
    # uv, or the gama checkout's own virtualenv when uv is not on the PATH (mise users: `mise exec uv -- ...`)
    Push-Location $GamaDir
    try {
        if (Get-Command uv -ErrorAction SilentlyContinue) { & uv run gama @args }
        elseif (Test-Path ".venv\Scripts\gama.exe") { & ".venv\Scripts\gama.exe" @args }
        else { throw "Neither uv nor $GamaDir\.venv\Scripts\gama.exe found (run uv sync in $GamaDir)" }
    }
    finally { Pop-Location }
}

switch ($Command) {
    "start" {
        if (-not (Test-Path $Dosbox)) { throw "No DOSBox at $Dosbox (set MIRROR_DOSBOX; see live-ram-map.md, Build)" }
        if (-not (Test-Path $GameDir)) { throw "No game folder at $GameDir (set MIRROR_GAME_DIR)" }
        New-Item -ItemType Directory -Force $LogDir | Out-Null
        # The game folder is mounted as C:. Then in DOSBox: cd MAGIC (if needed), then the game.
        # 6500 cycles: the config's default of 3000 is painfully slow for the game.
        $argv = @("--set", "cpu_cycles=6500", "--set", "webserver_enabled=true")
        if ($env:MIRROR_DOSBOX_RESEARCH -eq "1") {
            # Writes on: the research fork refuses every write (403) without it. The released DOSBox has no such setting.
            $argv += @("--set", "webserver_allow_writes=true",
                "--set", "webserver_file_log=$LogDir\files-$(Get-Date -Format yyyyMMdd-HHmm).jsonl")
        }
        $argv += $GameDir
        if ($env:MIRROR_DRY_RUN -eq "1") { Write-Host "$Dosbox $($argv -join ' ')"; break }
        & $Dosbox @argv
    }
    "cp" {
        if (-not $Name) { throw 'usage: live_session.ps1 cp "name" [note]' }
        if ($Note) { Gama checkpoint $Name --note $Note } else { Gama checkpoint $Name }
    }
    "status" {
        try { Invoke-WebRequest "$Api/cpu/state" -TimeoutSec 3 -UseBasicParsing | Out-Null; "DOSBox API: up" }
        catch { "DOSBox API: down" }
        Gama sql "SELECT id, name, taken_at FROM checkpoints ORDER BY taken_at DESC LIMIT 10"
    }
    default {
        Get-Content $PSCommandPath | Select-Object -Skip 1 -First 5
        exit 1
    }
}
