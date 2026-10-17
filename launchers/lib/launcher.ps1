# DeCodeDNA launcher for Windows (started by DeCodeDNA.bat).
# Starts the DeCodeDNA container with your workspace + database folders and
# opens the interface in your browser.
#
#   -ChangeFolders   pick the workspace / database folders again
#   -Stop            stop a running DeCodeDNA
#   $env:DECODEDNA_IMAGE overrides the image (default ghcr.io/piedna/decodedna:latest)
param([switch]$ChangeFolders, [switch]$Stop)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Windows.Forms

$Image = if ($env:DECODEDNA_IMAGE) { $env:DECODEDNA_IMAGE } else { "ghcr.io/piedna/decodedna:latest" }
$Name = "decodedna-gui"
$ConfigDir = Join-Path $env:USERPROFILE ".decodedna"
$Config = Join-Path $ConfigDir "launcher.json"
$RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

function Show-Info([string]$Text) {
    Write-Host $Text
    [void][System.Windows.Forms.MessageBox]::Show($Text, "DeCodeDNA", "OK", "Information")
}

function Fail([string]$Text) {
    Write-Host $Text -ForegroundColor Red
    [void][System.Windows.Forms.MessageBox]::Show($Text, "DeCodeDNA", "OK", "Error")
    exit 1
}

function Ask-YesNo([string]$Text) {
    return [System.Windows.Forms.MessageBox]::Show($Text, "DeCodeDNA", "YesNo", "Question") -eq "Yes"
}

function Choose-Folder([string]$Prompt) {
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = $Prompt
    $dlg.ShowNewFolderButton = $true
    if ($dlg.ShowDialog() -eq "OK") { return $dlg.SelectedPath }
    return $null
}

# Run docker without PowerShell turning its stderr into terminating errors
function Invoke-Docker {
    $old = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try { $out = & docker @args 2>&1; $code = $LASTEXITCODE }
    finally { $ErrorActionPreference = $old }
    return [pscustomobject]@{ Code = $code; Output = ($out | Out-String).Trim() }
}

function Test-Running {
    $r = Invoke-Docker inspect -f "{{.State.Running}}" $Name
    return ($r.Code -eq 0 -and $r.Output -eq "true")
}

function Get-Port {
    $r = Invoke-Docker port $Name 8080/tcp
    if ($r.Code -ne 0 -or -not $r.Output) { return $null }
    return ($r.Output -split "`r?`n")[0].Split(":")[-1].Trim()
}

# --- docker -----------------------------------------------------------------
Write-Host "DeCodeDNA launcher"
Write-Host "------------------"

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Show-Info "DeCodeDNA needs Docker Desktop, which is not installed.`n`nThe download page will open now. Install Docker Desktop (use the WSL 2 option), start it once, then open DeCodeDNA again."
    Start-Process "https://docs.docker.com/desktop/setup/install/windows-install/"
    exit 1
}

if ((Invoke-Docker info).Code -ne 0) {
    Write-Host "Starting Docker Desktop..."
    $exe = Join-Path $env:ProgramFiles "Docker\Docker\Docker Desktop.exe"
    if (Test-Path $exe) { Start-Process $exe }
    $ok = $false
    for ($i = 0; $i -lt 90; $i++) {
        Start-Sleep -Seconds 2
        if ((Invoke-Docker info).Code -eq 0) { $ok = $true; break }
    }
    if (-not $ok) { Fail "Docker is not running. Start Docker Desktop, wait until it says 'Engine running', then open DeCodeDNA again." }
}

if ($Stop) {
    [void](Invoke-Docker stop $Name)
    Write-Host "DeCodeDNA stopped."
    exit 0
}

if (Test-Running) {
    Write-Host "DeCodeDNA is already running."
    Start-Process "http://localhost:$(Get-Port)"
    exit 0
}
[void](Invoke-Docker rm -f $Name)

# --- folders ----------------------------------------------------------------
function Pick-Folders {
    Show-Info "Choose your DeCodeDNA workspace folder.`n`nPut your FASTQ/FASTA folders here; results are saved in a 'results' folder inside it."
    $ws = Choose-Folder "Choose your DeCodeDNA workspace folder"
    if (-not $ws) { Fail "No workspace folder chosen." }
    Show-Info "Now choose your reference database folder (the one that contains 'kraken2_db' and 'blast_db').`n`nNo databases yet? Choose an empty folder with ~200 GB free; you can build them from the app."
    $db = Choose-Folder "Choose the DeCodeDNA database folder"
    if (-not $db) { Fail "No database folder chosen." }
    New-Item -ItemType Directory -Force -Path $ConfigDir | Out-Null
    @{ workspace = $ws; databases = $db } | ConvertTo-Json | Set-Content -Path $Config -Encoding UTF8
    return @{ workspace = $ws; databases = $db }
}

$cfg = $null
if (-not $ChangeFolders -and (Test-Path $Config)) {
    $j = Get-Content $Config -Raw | ConvertFrom-Json
    if ((Test-Path $j.workspace) -and (Test-Path $j.databases)) { $cfg = @{ workspace = $j.workspace; databases = $j.databases } }
}
if ($cfg) {
    if (-not (Ask-YesNo "Start DeCodeDNA with these folders?`n`nWorkspace:  $($cfg.workspace)`nDatabases:  $($cfg.databases)`n`nChoose 'No' to pick different folders.")) {
        $cfg = Pick-Folders
    }
} else {
    $cfg = Pick-Folders
}

# --- image ------------------------------------------------------------------
if ((Invoke-Docker image inspect $Image).Code -ne 0) {
    Write-Host "Downloading DeCodeDNA ($Image). This happens once and can take a few minutes..."
    & docker pull $Image
    if ($LASTEXITCODE -ne 0) {
        $dockerfile = Join-Path $RepoRoot "docker\Dockerfile"
        if ((Test-Path $dockerfile) -and (Ask-YesNo "Could not download $Image.`n`nBuild it from this copy of the DeCodeDNA repository instead? This takes about 10-20 minutes.")) {
            & docker build -f $dockerfile -t $Image $RepoRoot
            if ($LASTEXITCODE -ne 0) { Fail "Building the DeCodeDNA image failed. See the messages in this window." }
        } else {
            Fail "Could not download the DeCodeDNA image ($Image). Check your internet connection and try again."
        }
    }
}

$mem = (Invoke-Docker info --format "{{.MemTotal}}").Output
if ($mem -match '^\d+$' -and [int64]$mem -lt 7500000000) {
    Write-Host ("Note: Docker may use only {0:N0} GB of memory. DeCodeDNA will read databases from disk (slower)." -f ([int64]$mem / 1GB))
    Write-Host "      To give it more: Docker Desktop > Settings > Resources > Memory."
}

# --- start ------------------------------------------------------------------
Write-Host "Starting DeCodeDNA..."
$run = Invoke-Docker run -d --rm --name $Name -p "127.0.0.1:0:8080" `
    -v "$($cfg.workspace):/work" -v "$($cfg.databases):/databases" `
    -e "HOST_WORKSPACE=$($cfg.workspace)" -e "HOST_DATABASES=$($cfg.databases)" `
    $Image gui
if ($run.Code -ne 0) {
    Fail "DeCodeDNA could not start.`n`n$($run.Output)`n`nIf Docker asks for permission to share these folders, allow it and try again."
}

$port = $null
for ($i = 0; $i -lt 60; $i++) {
    $port = Get-Port
    if ($port) {
        try { Invoke-WebRequest -UseBasicParsing -TimeoutSec 2 "http://127.0.0.1:$port/api/state" | Out-Null; break } catch { }
    }
    if (-not (Test-Running)) {
        Write-Host (Invoke-Docker logs $Name).Output
        Fail "DeCodeDNA stopped while starting. See the messages in this window."
    }
    Start-Sleep -Seconds 1
}
if (-not $port) { Fail "DeCodeDNA did not start in time." }

$url = "http://localhost:$port"
Start-Process $url
Write-Host ""
Write-Host "DeCodeDNA is running at $url" -ForegroundColor Green
Write-Host "   Workspace: $($cfg.workspace)"
Write-Host "   Databases: $($cfg.databases)"
Write-Host ""
Write-Host "Keep this window open while you work. Press Enter here (or Quit in the app) to stop DeCodeDNA."

while (Test-Running) {
    if ([Console]::KeyAvailable) {
        $k = [Console]::ReadKey($true)
        if ($k.Key -eq "Enter") {
            Write-Host "Stopping DeCodeDNA..."
            [void](Invoke-Docker stop $Name)
            break
        }
    }
    Start-Sleep -Milliseconds 500
}
Write-Host "DeCodeDNA has stopped. You can close this window."
