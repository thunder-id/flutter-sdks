<#
.SYNOPSIS
    Run the Flutter Quickstart E2E suite end to end on Windows, against an Android emulator.

.DESCRIPTION
    Starts a ThunderID server, provisions the test application and user, builds and installs the
    sample, then drives it with Maestro.

    This is the Windows path, and it drives Android. Building for iOS requires Xcode, so
    run-e2e.sh on macOS is the only way to exercise the iOS side. Everything else, the Dart
    layer, the widgets and the Android bridge, is covered here.

    Reaching a local server over its self-signed certificate relies on
    ThunderIDConfig.allowInsecureConnections, which the sample enables for debug builds only and
    the native SDK honours for loopback hosts only.

    Every stage is idempotent, so re-running is safe and is the normal way to iterate.

.PARAMETER SkipServer
    Skip starting and provisioning; the server is already up and provisioned.

.PARAMETER SkipBuild
    Skip building and installing; the sample is already on the device.

.PARAMETER SkipTest
    Set up everything but do not run Maestro.

.PARAMETER MaestroArgs
    Passed through to Maestro, so a specific flow path or extra options both work.

.EXAMPLE
    .\run-e2e.ps1

.EXAMPLE
    .\run-e2e.ps1 -SkipServer -SkipBuild

.NOTES
    Environment variables, all optional:
      THUNDERID_VERSION  Release to run, without the leading "v" (default: latest release)
      SERVER_URL         Where the server is reachable (default https://localhost:8090)
      ADMIN_USERNAME     Admin user to bootstrap (default admin)
      ADMIN_PASSWORD     Admin password (default admin)
      E2E_USERNAME       Test user to create (default e2e_mobile_user)
      E2E_PASSWORD       Test user password (default TestPassword@123)
      INSTALL_DIR        Where to unpack the distribution (default .\.thunderid-server)

    Requires PowerShell 7 or later, plus the Flutter SDK and a running Android emulator.
#>

[CmdletBinding()]
param(
    [switch]$SkipServer,
    [switch]$SkipBuild,
    [switch]$SkipTest,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$MaestroArgs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw "PowerShell 7 or later is required (found $($PSVersionTable.PSVersion)). Install it with: winget install Microsoft.PowerShell"
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

function Get-EnvOrDefault([string]$Name, [string]$Default) {
    $value = [Environment]::GetEnvironmentVariable($Name)
    if ([string]::IsNullOrWhiteSpace($value)) { return $Default }
    return $value
}

$ServerUrl  = Get-EnvOrDefault 'SERVER_URL' 'https://localhost:8090'
$AdminUser  = Get-EnvOrDefault 'ADMIN_USERNAME' 'admin'
$AdminPass  = Get-EnvOrDefault 'ADMIN_PASSWORD' 'admin'
$E2eUser    = Get-EnvOrDefault 'E2E_USERNAME' 'e2e_mobile_user'
$E2ePass    = Get-EnvOrDefault 'E2E_PASSWORD' 'TestPassword@123'
$InstallDir = Get-EnvOrDefault 'INSTALL_DIR' (Join-Path $ScriptDir '.thunderid-server')

# The sample owns its own application config, not the test script.
$ConfigFile = Join-Path $ScriptDir '../../samples/quickstart/thunderid-config/thunderid-config.yaml'

# Must match the `id` in $ConfigFile and the application ID the sample is built with.
$AppId = '019e5b10-1001-7a2b-9c3d-4e5f60718293'

# Every call goes to a host with a self-signed certificate.
$PSDefaultParameterValues['Invoke-RestMethod:SkipCertificateCheck'] = $true
$PSDefaultParameterValues['Invoke-WebRequest:SkipCertificateCheck'] = $true

# -------------------------------------------------------------------------------------------
# Start
# -------------------------------------------------------------------------------------------
function Start-ThunderIDServer {
    # Reuse a server that is already serving. All three mobile SDK suites bind the same port, so
    # failing here would mean tearing down a perfectly good server just to start an identical one.
    # Provisioning runs regardless and is idempotent, so the reused server still ends up correct.
    try {
        Invoke-WebRequest -Uri "$ServerUrl/health/liveness" -TimeoutSec 3 -UseBasicParsing | Out-Null
        Write-Host "==> A server is already serving at $ServerUrl, reusing it"
        return
    } catch {
        # Nothing listening, carry on and start one.
    }

    $arch = switch ($env:PROCESSOR_ARCHITECTURE) {
        'AMD64' { 'x64' }
        'ARM64' { 'arm64' }
        default { throw "Unsupported architecture $($env:PROCESSOR_ARCHITECTURE)." }
    }
    if ($arch -eq 'arm64') {
        # Only win-x64 is published; it runs under emulation on ARM64 Windows.
        Write-Host '==> No win-arm64 build is published, using win-x64 under emulation'
        $arch = 'x64'
    }

    $version = $env:THUNDERID_VERSION
    if ([string]::IsNullOrWhiteSpace($version)) {
        Write-Host '==> Resolving the latest ThunderID release'
        $release = Invoke-RestMethod 'https://api.github.com/repos/thunder-id/thunderid/releases/latest'
        $version = $release.tag_name -replace '^v', ''
        if ([string]::IsNullOrWhiteSpace($version)) {
            throw 'Could not resolve the latest release (rate limited?). Set THUNDERID_VERSION.'
        }
    }

    $archive  = "thunderid-$version-win-$arch.zip"
    $url      = "https://github.com/thunder-id/thunderid/releases/download/v$version/$archive"
    $distHome = Join-Path $InstallDir "thunderid-$version-win-$arch"

    if (-not (Test-Path $distHome)) {
        Write-Host "==> Downloading $archive"
        New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
        $zipPath = Join-Path $InstallDir $archive
        Invoke-WebRequest -Uri $url -OutFile $zipPath
        Expand-Archive -Path $zipPath -DestinationPath $InstallDir -Force
    }

    Write-Host '==> Running first-time setup'
    & (Join-Path $distHome 'setup.ps1') -AdminUsername $AdminUser -AdminPassword $AdminPass
    if ($LASTEXITCODE -ne 0) { throw "setup.ps1 failed with exit code $LASTEXITCODE." }

    Write-Host '==> Starting the server'
    # Start-Process detaches the server from this session, so it outlives the script the same way
    # setsid does on Linux.
    $logPath = Join-Path $InstallDir 'server.log'
    Start-Process -FilePath 'pwsh' `
        -ArgumentList '-NoProfile', '-File', (Join-Path $distHome 'start.ps1') `
        -WorkingDirectory $distHome `
        -RedirectStandardOutput $logPath `
        -RedirectStandardError (Join-Path $InstallDir 'server.err.log') `
        -WindowStyle Hidden | Out-Null

    Write-Host "==> Waiting for $ServerUrl to accept connections"
    foreach ($i in 1..120) {
        try {
            Invoke-WebRequest -Uri "$ServerUrl/health/liveness" -TimeoutSec 3 -UseBasicParsing | Out-Null
            Write-Host '    up'
            return
        } catch {
            Start-Sleep -Seconds 2
        }
    }

    Write-Host 'ERROR: the server did not come up within 240s. Last 50 log lines:' -ForegroundColor Red
    if (Test-Path $logPath) { Get-Content $logPath -Tail 50 }
    throw 'Server did not start.'
}

# -------------------------------------------------------------------------------------------
# Admin token
#
# /applications and /users require a bearer token; the Direct-Auth-Secret header does not apply
# to them (it only gates /auth/, /register/passkey/ and /access/). Mirrors mint_admin_token() in
# the product's tests/e2e/run-e2e.sh: the CONSOLE client runs an authorization-code + PKCE
# exchange, whose credentials step is submitted over the Flow Execution API.
# -------------------------------------------------------------------------------------------
function Get-AdminToken {
    $redirectUri = "$ServerUrl/console"

    $bytes = [byte[]]::new(32)
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    $verifier = (($bytes | ForEach-Object { $_.ToString('x2') }) -join '').Substring(0, 43)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    $hash = $sha.ComputeHash([System.Text.Encoding]::ASCII.GetBytes($verifier))
    $challenge = [Convert]::ToBase64String($hash).Replace('+', '-').Replace('/', '_').TrimEnd('=')

    $query = @(
        'client_id=CONSOLE'
        "redirect_uri=$([uri]::EscapeDataString($redirectUri))"
        'scope=system'
        "resource=$([uri]::EscapeDataString("$ServerUrl/mcp"))"
        'response_type=code'
        "code_challenge=$challenge"
        'code_challenge_method=S256'
    ) -join '&'

    $authorize = Invoke-WebRequest -Uri "$ServerUrl/oauth2/authorize?$query" `
        -MaximumRedirection 0 -SkipHttpErrorCheck -ErrorAction SilentlyContinue
    $location = $authorize.Headers['Location']
    if ($location -is [array]) { $location = $location[0] }
    if ([string]::IsNullOrWhiteSpace($location)) {
        throw 'The authorize request returned no Location header.'
    }

    $authId = [regex]::Match($location, '[?&]authId=([^&]*)').Groups[1].Value
    $execId = [regex]::Match($location, '[?&]executionId=([^&]*)').Groups[1].Value
    if (-not $authId -or -not $execId) {
        throw "Could not parse authId/executionId from the authorize redirect. Location: $location"
    }

    # The console login flow runs an SSO check ahead of the credentials prompt. This is a fresh,
    # cookie-less login, so the first call advances past that check and mints a challenge token;
    # the second submits the admin credentials with it.
    $prompt = Invoke-RestMethod -Method Post -Uri "$ServerUrl/flow/execute" `
        -ContentType 'application/json' -Body (@{executionId = $execId} | ConvertTo-Json)
    if (-not $prompt.challengeToken) { throw 'Flow execution returned no challenge token.' }

    $flow = Invoke-RestMethod -Method Post -Uri "$ServerUrl/flow/execute" `
        -ContentType 'application/json' -Body (@{
            executionId    = $execId
            challengeToken = $prompt.challengeToken
            action         = 'action_001'
            inputs         = @{username = $AdminUser; password = $AdminPass}
        } | ConvertTo-Json)
    if (-not $flow.assertion) { throw 'Admin login returned no assertion.' }

    $callback = Invoke-RestMethod -Method Post -Uri "$ServerUrl/oauth2/auth/callback" `
        -ContentType 'application/json' `
        -Body (@{authId = $authId; assertion = $flow.assertion} | ConvertTo-Json)
    $code = [regex]::Match([string]$callback.redirect_uri, '[?&]code=([^&]*)').Groups[1].Value
    if (-not $code) { throw 'The OAuth2 callback returned no authorization code.' }

    $token = Invoke-RestMethod -Method Post -Uri "$ServerUrl/oauth2/token" `
        -ContentType 'application/x-www-form-urlencoded' -Body @{
            grant_type    = 'authorization_code'
            code          = $code
            redirect_uri  = $redirectUri
            client_id     = 'CONSOLE'
            resource      = "$ServerUrl/mcp"
            code_verifier = $verifier
        }
    if (-not $token.access_token) { throw 'The token endpoint returned no access token.' }
    return $token.access_token
}

# -------------------------------------------------------------------------------------------
# Provision
# -------------------------------------------------------------------------------------------
function Invoke-Provision {
    Write-Host "==> Obtaining admin token from $ServerUrl"
    $adminToken = Get-AdminToken
    $authHeader = @{Authorization = "Bearer $adminToken"}

    Write-Host '==> Importing the E2E application'
    $configYaml = Get-Content $ConfigFile -Raw
    $import = Invoke-RestMethod -Method Post -Uri "$ServerUrl/import" -Headers $authHeader `
        -ContentType 'application/json' `
        -Body (@{content = $configYaml; options = @{upsert = $true}} | ConvertTo-Json)
    if ($import.summary.failed -ne 0) {
        throw "Import failed: $($import | ConvertTo-Json -Depth 5)"
    }

    # POST /import drops the attestation block (see the note in $ConfigFile), so without
    # this the app stores attestation: null and /flow/execute rejects the sample with FES-1016.
    # Re-applying it over PUT is the only way to get devMode persisted today.
    Write-Host '==> Re-applying attestation devMode over PUT (import drops it)'
    $app = Invoke-RestMethod -Uri "$ServerUrl/applications/$AppId" -Headers $authHeader
    $app | Add-Member -NotePropertyName attestation -NotePropertyValue @{devMode = $true} -Force
    $put = Invoke-RestMethod -Method Put -Uri "$ServerUrl/applications/$AppId" -Headers $authHeader `
        -ContentType 'application/json' -Body ($app | ConvertTo-Json -Depth 10)
    if (-not $put.attestation.devMode) {
        throw 'Attestation devMode did not persist.'
    }

    Write-Host "==> Ensuring test user '$E2eUser' exists"
    # The filter grammar accepts exactly one `attribute eq "value"` clause.
    $filter = [uri]::EscapeDataString("username eq ""$E2eUser""")
    $existing = Invoke-RestMethod -Uri "$ServerUrl/users?filter=$filter" -Headers $authHeader
    if ($existing.users -and $existing.users.Count -gt 0) {
        Write-Host '    already present, leaving it as is'
    } else {
        $types = Invoke-RestMethod -Uri "$ServerUrl/user-types" -Headers $authHeader
        $ouId = ($types.types | Where-Object {$_.name -eq 'Person'}).ouId
        if (-not $ouId) { throw 'Could not resolve the ouId of the Person user type.' }

        $created = Invoke-RestMethod -Method Post -Uri "$ServerUrl/users" -Headers $authHeader `
            -ContentType 'application/json' -Body (@{
                ouId       = $ouId
                type       = 'Person'
                attributes = @{
                    username    = $E2eUser
                    password    = $E2ePass
                    email       = "$E2eUser@example.com"
                    given_name  = 'E2E'
                    family_name = 'Mobile'
                }
            } | ConvertTo-Json -Depth 5)
        if (-not $created.id) { throw 'Failed to create the test user.' }
        Write-Host '    created'
    }
}

# -------------------------------------------------------------------------------------------
# Build and install the sample
# -------------------------------------------------------------------------------------------
function Build-Sample {
    $sampleDir = Join-Path $ScriptDir '../../samples/quickstart' | Resolve-Path

    Write-Host '==> Configuring the sample'
    # 10.0.2.2 is the emulator's alias for the host loopback, where the server is listening. It
    # is also one of the loopback hosts the native SDK will relax certificate validation for.
    @(
        'THUNDERID_BASE_URL=https://10.0.2.2:8090'
        "THUNDERID_APP_ID=$AppId"
        'THUNDERID_ATTESTATION_ENABLED=false'
        'THUNDERID_CLOUD_PROJECT_NUMBER='
    ) | Set-Content -Path (Join-Path $sampleDir '.env') -Encoding utf8

    Write-Host '==> Building and installing the sample'
    Push-Location $sampleDir
    try {
        & flutter pub get
        if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed with exit code $LASTEXITCODE." }
        & flutter build apk --debug
        if ($LASTEXITCODE -ne 0) { throw "flutter build apk failed with exit code $LASTEXITCODE." }
        & adb install -r 'build/app/outputs/flutter-apk/app-debug.apk'
        if ($LASTEXITCODE -ne 0) { throw "adb install failed with exit code $LASTEXITCODE." }
    } finally {
        Pop-Location
    }
}

# -------------------------------------------------------------------------------------------
# Run the flows
# -------------------------------------------------------------------------------------------
function Invoke-Flows {
    if (-not (Get-Command maestro -ErrorAction SilentlyContinue)) {
        throw 'maestro is not installed. See https://maestro.mobile.dev/getting-started/installing-maestro'
    }
    # Default to the whole suite when no flow path was passed through.
    $target = if ($MaestroArgs) { $MaestroArgs } else { @('flows/') }

    Write-Host '==> Running Maestro'
    Push-Location $ScriptDir
    try {
        # The JUnit report is what makes a failed run readable without scraping the console log;
        # it sits alongside Maestro's own debug output and CI collects both.
        & maestro --platform android test @target `
            --format=JUNIT --output=report.xml `
            -e "E2E_USERNAME=$E2eUser" -e "E2E_PASSWORD=$E2ePass"
        if ($LASTEXITCODE -ne 0) { throw "Maestro reported failures (exit code $LASTEXITCODE)." }
    } finally {
        Pop-Location
    }
}

if (-not $SkipServer) {
    Start-ThunderIDServer
    Invoke-Provision
    Write-Host ''
    Write-Host "  server         : $ServerUrl"
    Write-Host "  application id : $AppId"
    Write-Host "  test user      : $E2eUser"
    Write-Host ''
}
if (-not $SkipBuild) { Build-Sample }
if (-not $SkipTest) { Invoke-Flows }
