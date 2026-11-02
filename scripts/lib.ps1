# Shared helpers for the wowps PowerShell scripts. Dot-sourced, not run directly.
# Works with Windows PowerShell 5.1 and PowerShell 7+. Keep this file ASCII-only
# (Windows PowerShell 5.1 misreads UTF-8 files without a BOM).

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:Root = Split-Path -Parent $PSScriptRoot
$script:EnvFile = Join-Path $script:Root '.env'
$script:EnvExample = Join-Path $script:Root '.env.example'
$script:VersionsFile = Join-Path $script:Root 'versions.env'
$script:SourceDir = Join-Path $script:Root 'source'
$script:AcDir = Join-Path $script:SourceDir 'azerothcore-wotlk'
$script:PbDir = Join-Path (Join-Path $script:AcDir 'modules') 'mod-playerbots'
$script:DbVolume = 'wowps_ac-database'
$script:Images = @('wowps-ac-worldserver:local', 'wowps-ac-authserver:local', 'wowps-ac-db-import:local', 'wowps-ac-client-data:local')
$script:BuildServices = @('ac-client-data-init', 'ac-db-import', 'ac-authserver', 'ac-worldserver')
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------
function Write-Info([string]$Message) { Write-Host "==> $Message" -ForegroundColor Cyan }
function Write-Ok([string]$Message) { Write-Host "OK: $Message" -ForegroundColor Green }
function Write-Warn([string]$Message) { Write-Host "WARNING: $Message" -ForegroundColor Yellow }

# Stop with an error. Invoke-Main prints it.
function Fail([string]$Message) { throw $Message }

# Runs the body of an entry script: works in the repo folder, prints errors
# nicely and sets the exit code.
function Invoke-Main([scriptblock]$Body) {
    $code = 0
    Push-Location $script:Root
    try {
        & $Body
    }
    catch {
        Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
        $code = 1
    }
    finally {
        Pop-Location
    }
    exit $code
}

# ---------------------------------------------------------------------------
# Running programs (git, docker)
# ---------------------------------------------------------------------------

# Run a program, showing its output. Throws if it fails.
function Invoke-Native {
    param([string]$File, [string[]]$Arguments, [string]$ErrorMessage = '')
    & $File @Arguments | Out-Host
    if ($LASTEXITCODE -ne 0) {
        if ($ErrorMessage) { Fail $ErrorMessage }
        Fail "'$File $($Arguments -join ' ')' failed (exit code $LASTEXITCODE)."
    }
}

# Run a program and return its output as one string (errors hidden).
function Get-NativeOutput {
    param([string]$File, [string[]]$Arguments)
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $out = & $File @Arguments 2>$null } finally { $ErrorActionPreference = $old }
    if ($null -eq $out) { return '' }
    return ((@($out) | ForEach-Object { "$_" }) -join "`n").Trim()
}

# Run a program quietly; return $true if it succeeded.
function Test-Native {
    param([string]$File, [string[]]$Arguments)
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { & $File @Arguments *> $null } catch { return $false } finally { $ErrorActionPreference = $old }
    return ($LASTEXITCODE -eq 0)
}

function Invoke-Compose {
    param([string[]]$Arguments, [string]$ErrorMessage = '')
    Invoke-Native -File 'docker' -Arguments (@('compose') + $Arguments) -ErrorMessage $ErrorMessage
}

# ---------------------------------------------------------------------------
# .env / versions.env (read as data, never executed)
# ---------------------------------------------------------------------------
function Get-EnvValue {
    param([string]$Key, [string]$File = $script:EnvFile, [string]$Default = '')
    if (-not (Test-Path -LiteralPath $File)) { return $Default }
    $value = $null
    $pattern = '^\s*' + [regex]::Escape($Key) + '\s*=(.*)$'
    foreach ($line in [System.IO.File]::ReadAllLines($File)) {
        if ($line -match $pattern) { $value = $Matches[1] }
    }
    if ($null -eq $value) { return $Default }
    $value = $value.Trim()
    $quoted = $value.Length -ge 2 -and (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'")))
    if ($quoted) {
        $value = $value.Substring(1, $value.Length - 2)
    }
    else {
        $value = ($value -replace '\s+#.*$', '').Trim()
    }
    if ($value -eq '') { return $Default }
    return $value
}

function Write-LfFile([string]$Path, [string[]]$Lines) {
    # LF line endings and no BOM, so Docker Compose and bash read it correctly.
    $text = ($Lines -join "`n") + "`n"
    [System.IO.File]::WriteAllText($Path, $text, $script:Utf8NoBom)
}

function Set-EnvValue {
    param([string]$Key, [string]$Value, [string]$File = $script:EnvFile)
    $pattern = '^\s*' + [regex]::Escape($Key) + '\s*='
    $lines = New-Object System.Collections.Generic.List[string]
    $done = $false
    foreach ($line in [System.IO.File]::ReadAllLines($File)) {
        if (-not $done -and $line -match $pattern) {
            $lines.Add("$Key=$Value")
            $done = $true
        }
        else {
            $lines.Add($line)
        }
    }
    if (-not $done) { $lines.Add("$Key=$Value") }
    Write-LfFile -Path $File -Lines $lines.ToArray()
}

function Read-Versions {
    if (-not (Test-Path -LiteralPath $script:VersionsFile)) { Fail 'versions.env is missing. Re-download this repository.' }
    $v = @{}
    foreach ($key in @('AC_REPO', 'AC_BRANCH', 'AC_COMMIT', 'PLAYERBOTS_REPO', 'PLAYERBOTS_BRANCH', 'PLAYERBOTS_COMMIT')) {
        $v[$key] = Get-EnvValue -Key $key -File $script:VersionsFile
    }
    foreach ($key in @('AC_REPO', 'AC_COMMIT', 'PLAYERBOTS_REPO', 'PLAYERBOTS_COMMIT')) {
        if (-not $v[$key]) { Fail "$key is missing from versions.env." }
    }
    return $v
}

function Get-Short([string]$Commit) {
    if ($Commit.Length -gt 12) { return $Commit.Substring(0, 12) }
    return $Commit
}

# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------
function Assert-Docker {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Fail 'Docker is not installed. Install Docker Desktop, see README.'
    }
    if (-not (Test-Native -File 'docker' -Arguments @('info'))) {
        Fail 'Docker is installed but not running. Start Docker Desktop, wait until it says "running", and try again.'
    }
    if (-not (Test-Native -File 'docker' -Arguments @('compose', 'version'))) {
        Fail "'docker compose' (Compose v2) is missing. Update Docker Desktop."
    }
}

function Assert-Git {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Fail 'git is not installed. Install it from https://git-scm.com/download/win (see README).'
    }
}

function Assert-EnvFile {
    if (-not (Test-Path -LiteralPath $script:EnvFile)) { Fail 'No .env file. Run .\setup.ps1 first.' }
}

function Test-ImagesExist {
    return (Test-Native -File 'docker' -Arguments (@('image', 'inspect') + $script:Images))
}

function Assert-Images {
    if (-not (Test-ImagesExist)) { Fail 'Server images are not built yet. Run .\setup.ps1 first.' }
}

function Test-ContainerRunning([string]$Name) {
    return ((Get-NativeOutput -File 'docker' -Arguments @('inspect', '-f', '{{.State.Running}}', $Name)) -eq 'true')
}

function Test-DbVolume {
    return (Test-Native -File 'docker' -Arguments @('volume', 'inspect', $script:DbVolume))
}

function Test-IsLinux {
    $v = Get-Variable -Name IsLinux -ValueOnly -ErrorAction SilentlyContinue
    return [bool]$v
}

# ---------------------------------------------------------------------------
# Setup helpers
# ---------------------------------------------------------------------------
function New-RandomPassword([int]$Length = 24) {
    # Letters and digits only: safe in .env, in the DB connection strings and in SQL.
    $chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'.ToCharArray()
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $sb = New-Object System.Text.StringBuilder
    $buffer = New-Object byte[] 64
    while ($sb.Length -lt $Length) {
        $rng.GetBytes($buffer)
        foreach ($b in $buffer) {
            # 248 = 4 * 62, so every character is equally likely.
            if ($b -lt 248 -and $sb.Length -lt $Length) { [void]$sb.Append($chars[$b % 62]) }
        }
    }
    return $sb.ToString()
}

function Initialize-EnvFile {
    $created = $false
    if (-not (Test-Path -LiteralPath $script:EnvFile)) {
        if (-not (Test-Path -LiteralPath $script:EnvExample)) { Fail '.env.example is missing. Re-download this repository.' }
        Write-LfFile -Path $script:EnvFile -Lines ([System.IO.File]::ReadAllLines($script:EnvExample))
        $created = $true
        Write-Ok 'Created .env from .env.example'
    }

    $pw = Get-EnvValue -Key 'DB_ROOT_PASSWORD'
    if ($pw -eq '' -or $pw -eq 'change-me') {
        if (Test-DbVolume) {
            Fail ("A database from an earlier install already exists (Docker volume $script:DbVolume), but .env has no password for it.`n" +
                "       Put the old password into .env as DB_ROOT_PASSWORD=...`n" +
                "       or, to throw the old database away (deletes all accounts and characters!):`n" +
                "         docker volume rm $script:DbVolume")
        }
        Set-EnvValue -Key 'DB_ROOT_PASSWORD' -Value (New-RandomPassword)
        Write-Ok 'Generated a random database password (saved in .env)'
    }
    elseif ($pw -notmatch '^[A-Za-z0-9._-]+$') {
        Fail "DB_ROOT_PASSWORD in .env may only contain letters, numbers, '.', '_' and '-'."
    }

    # Only matters when running PowerShell on Linux; Windows uses 1000.
    if (Test-IsLinux) {
        $uid = [int](Get-NativeOutput -File 'id' -Arguments @('-u'))
        $gid = [int](Get-NativeOutput -File 'id' -Arguments @('-g'))
        if ($uid -lt 1000) { $uid = 1000 }
        if ($gid -lt 1000) { $gid = 1000 }
        if ($created -or (Get-EnvValue -Key 'DOCKER_USER_ID') -eq '1000') {
            Set-EnvValue -Key 'DOCKER_USER_ID' -Value "$uid"
            Set-EnvValue -Key 'DOCKER_GROUP_ID' -Value "$gid"
        }
    }
}

function Initialize-Dirs {
    foreach ($name in @('config', 'logs', 'backups')) {
        $path = Join-Path $script:Root $name
        if (-not (Test-Path -LiteralPath $path)) { New-Item -ItemType Directory -Path $path | Out-Null }
    }
    if ((Test-IsLinux) -and (Get-NativeOutput -File 'id' -Arguments @('-u')) -eq '0') {
        $owner = (Get-EnvValue -Key 'DOCKER_USER_ID' -Default '1000') + ':' + (Get-EnvValue -Key 'DOCKER_GROUP_ID' -Default '1000')
        Invoke-Native -File 'chown' -Arguments @('-R', $owner, 'config', 'logs', 'backups')
    }
}

# ---------------------------------------------------------------------------
# Source checkout (pinned commits)
# ---------------------------------------------------------------------------
function Get-SourceCommit([string]$Dir) {
    if (-not (Test-Path -LiteralPath (Join-Path $Dir '.git'))) { return '' }
    return (Get-NativeOutput -File 'git' -Arguments @('-C', $Dir, 'rev-parse', '-q', '--verify', 'HEAD'))
}

# Make $Dir a shallow checkout of exactly $Commit.
function Sync-Repo {
    param([string]$Dir, [string]$Url, [string]$Commit)
    if (-not (Test-Path -LiteralPath (Join-Path $Dir '.git'))) {
        New-Item -ItemType Directory -Path $Dir -Force | Out-Null
        Invoke-Native -File 'git' -Arguments @('-C', $Dir, 'init', '-q')
        # The server scripts inside must keep Linux (LF) line endings.
        Invoke-Native -File 'git' -Arguments @('-C', $Dir, 'config', 'core.autocrlf', 'false')
        Invoke-Native -File 'git' -Arguments @('-C', $Dir, 'remote', 'add', 'origin', $Url)
    }
    else {
        Invoke-Native -File 'git' -Arguments @('-C', $Dir, 'remote', 'set-url', 'origin', $Url)
    }

    if ((Get-SourceCommit $Dir) -ne $Commit) {
        Write-Info "Downloading $(Split-Path -Leaf $Dir) @ $(Get-Short $Commit) ..."
        Invoke-Native -File 'git' -Arguments @('-C', $Dir, 'fetch', '--depth', '1', 'origin', $Commit) `
            -ErrorMessage "Could not download commit $Commit from $Url. Check your internet connection and the commit in versions.env."
    }
    # --force also undoes any local edits to tracked files in the checkout.
    Invoke-Native -File 'git' -Arguments @('-C', $Dir, '-c', 'advice.detachedHead=false', 'checkout', '-q', '--force', $Commit) `
        -ErrorMessage "Could not check out $Commit in $Dir."
}

function Sync-Sources {
    $v = Read-Versions
    if (-not (Test-Path -LiteralPath $script:SourceDir)) { New-Item -ItemType Directory -Path $script:SourceDir | Out-Null }
    Sync-Repo -Dir $script:AcDir -Url $v['AC_REPO'] -Commit $v['AC_COMMIT']
    Sync-Repo -Dir $script:PbDir -Url $v['PLAYERBOTS_REPO'] -Commit $v['PLAYERBOTS_COMMIT']
    Write-Ok "Source is at AzerothCore $(Get-Short $v['AC_COMMIT']) + mod-playerbots $(Get-Short $v['PLAYERBOTS_COMMIT'])"
}

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

# Parallel compile jobs: BUILD_JOBS from .env, or derived from what Docker has
# (CPUs, and ~2 GB of memory per job so the compiler doesn't run out of RAM).
function Get-BuildJobs {
    $jobs = Get-EnvValue -Key 'BUILD_JOBS'
    if ($jobs -match '^[1-9][0-9]*$') { return [int]$jobs }
    $cpus = 2
    $mem = [int64]4294967296
    $c = Get-NativeOutput -File 'docker' -Arguments @('info', '--format', '{{.NCPU}}')
    $m = Get-NativeOutput -File 'docker' -Arguments @('info', '--format', '{{.MemTotal}}')
    if ($c -match '^[0-9]+$') { $cpus = [int]$c }
    if ($m -match '^[0-9]+$') { $mem = [int64]$m }
    $byMem = [int][math]::Floor($mem / 2147483648)
    $result = [math]::Min($cpus, $byMem)
    if ($result -lt 1) { $result = 1 }
    return [int]$result
}

# Copy upstream's Dockerfile to Dockerfile.wowps with a fixed number of compile
# jobs (upstream always uses all CPUs + 1, which can run out of memory).
function New-WowpsDockerfile([int]$Jobs) {
    $dockerDir = Join-Path (Join-Path $script:AcDir 'apps') 'docker'
    $src = Join-Path $dockerDir 'Dockerfile'
    $dst = Join-Path $dockerDir 'Dockerfile.wowps'
    if (-not (Test-Path -LiteralPath $src)) { Fail "$src not found. Is the source checkout complete? Run .\setup.ps1 again." }
    $content = [System.IO.File]::ReadAllText($src)
    $pattern = '-j $(($(nproc) + 1))'
    if ($content.Contains($pattern)) {
        $content = $content.Replace($pattern, "-j $Jobs")
    }
    else {
        Write-Warn "Upstream Dockerfile changed; can't set BUILD_JOBS. Building with upstream's default."
    }
    [System.IO.File]::WriteAllText($dst, $content, $script:Utf8NoBom)
}

# Returns $true if the build worked.
function Invoke-BuildImages {
    $jobs = Get-BuildJobs
    New-WowpsDockerfile -Jobs $jobs
    Write-Info "Building server images with $jobs parallel jobs. The first build takes 30-90 minutes..."
    & docker @(@('compose', 'build') + $script:BuildServices) | Out-Host
    return ($LASTEXITCODE -eq 0)
}

function Invoke-DownloadClientData {
    Write-Info 'Downloading map data (dbc/maps/vmaps/mmaps, ~1.2 GB) if needed...'
    Invoke-Compose -Arguments @('run', '--rm', '-T', 'ac-client-data-init') -ErrorMessage 'Downloading the map data failed. Check your internet connection and run the script again.'
}

# ---------------------------------------------------------------------------
# Runtime
# ---------------------------------------------------------------------------
function Show-FailedOneshots {
    foreach ($svc in @('ac-client-data-init', 'ac-db-import', 'ac-realmlist')) {
        $code = Get-NativeOutput -File 'docker' -Arguments @('inspect', '-f', '{{.State.ExitCode}}', $svc)
        if ($code -ne '' -and $code -ne '0') {
            Write-Warn "$svc failed (exit code $code). Last log lines:"
            Write-Host (Get-NativeOutput -File 'docker' -Arguments @('logs', '--tail', '40', $svc))
        }
    }
}

# Wait until the worldserver logs "ready", printing progress. Returns $false if
# it stops or crashes, or after $TimeoutSeconds.
function Wait-Worldserver([int]$TimeoutSeconds = 1800) {
    $started = Get-NativeOutput -File 'docker' -Arguments @('inspect', '-f', '{{.State.StartedAt}}', 'ac-worldserver')
    $restarts = Get-NativeOutput -File 'docker' -Arguments @('inspect', '-f', '{{.RestartCount}}', 'ac-worldserver')
    $waited = 0
    while ($true) {
        $logs = Get-NativeOutput -File 'docker' -Arguments @('logs', '--since', $started, 'ac-worldserver')
        if ($logs.Contains('(worldserver-daemon) ready')) { return $true }

        $status = Get-NativeOutput -File 'docker' -Arguments @('inspect', '-f', '{{.State.Status}}', 'ac-worldserver')
        $nowRestarts = Get-NativeOutput -File 'docker' -Arguments @('inspect', '-f', '{{.RestartCount}}', 'ac-worldserver')
        if ($status -ne 'running' -or $nowRestarts -ne $restarts) {
            Write-Warn "The worldserver stopped while starting (status: $status). Last log lines:"
            Write-Host (Get-NativeOutput -File 'docker' -Arguments @('logs', '--tail', '60', 'ac-worldserver'))
            return $false
        }
        if ($waited -ge $TimeoutSeconds) {
            Write-Warn "The worldserver is still not ready after $([int]($TimeoutSeconds / 60)) minutes."
            return $false
        }
        if ($waited % 20 -eq 0) {
            $last = Get-NativeOutput -File 'docker' -Arguments @('logs', '--tail', '1', 'ac-worldserver')
            if ($last.Length -gt 100) { $last = $last.Substring(0, 100) }
            if (-not $last) { $last = 'starting' }
            Write-Host "   ... $last"
        }
        Start-Sleep -Seconds 5
        $waited += 5
    }
}

function Write-ConnectInfo {
    $address = Get-EnvValue -Key 'REALM_ADDRESS' -Default '127.0.0.1'
    $port = Get-EnvValue -Key 'AUTH_PORT' -Default '3724'
    $name = Get-EnvValue -Key 'REALM_NAME' -Default 'AzerothCore Playerbots'
    $realmlist = $address
    if ($port -ne '3724') { $realmlist = "${address}:$port" }
    Write-Host ''
    Write-Ok "Server is running: realm '$name' at $address"
    Write-Host '   In your WoW 3.3.5a folder, open Data\<your language, e.g. enUS>\realmlist.wtf'
    Write-Host "   and make it contain exactly:  set realmlist $realmlist"
    Write-Host "   No account yet? See 'Create your game account' in the README."
    Write-Host '   Server console: docker attach ac-worldserver  (leave it with Ctrl+P then Ctrl+Q)'
}

function Get-LanIp {
    # Asks the OS which local address it would use to reach the internet.
    # Nothing is actually sent.
    try {
        $s = New-Object System.Net.Sockets.Socket([System.Net.Sockets.AddressFamily]::InterNetwork, [System.Net.Sockets.SocketType]::Dgram, [System.Net.Sockets.ProtocolType]::Udp)
        try {
            $s.Connect('1.1.1.1', 53)
            return $s.LocalEndPoint.Address.ToString()
        }
        finally { $s.Close() }
    }
    catch { return '' }
}

# Run ac-db-tools (backup / restore) inside Docker.
function Invoke-DbTools([string[]]$Arguments) {
    Invoke-Compose -Arguments (@('--profile', 'tools', 'run', '--rm', '-T', 'ac-db-tools') + $Arguments)
}
