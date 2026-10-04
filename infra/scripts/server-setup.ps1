# Sets up and starts the whole TIHE server on this Windows PC (Docker Desktop), with one command:
#
#   powershell -ExecutionPolicy Bypass -File infra\scripts\server-setup.ps1 -AdminPhone 09121234567 -AdminName "Admin"
#
# -HostAddress: the address students use to reach this PC (detected if left out).
# Safe to run again: it keeps the secrets, applies new migrations, rebuilds changed services, and
# only creates the admin when asked to. Same steps as server-setup.sh.
param(
  [string] $HostAddress = '',
  [string] $AdminPhone = '',
  [string] $AdminName = ''
)
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..\..')
$compose = @('compose', '-f', 'infra/docker/compose.server.yml', '--env-file', 'infra/docker/server/.env')

docker compose version *> $null
if ($LASTEXITCODE -ne 0) { throw 'Docker Desktop is required: https://docs.docker.com/desktop/setup/install/windows-install/' }

if (-not $HostAddress) {
  # The address of the network adapter that has the default route: what devices on the same
  # network reach.
  $route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' | Sort-Object RouteMetric | Select-Object -First 1
  $HostAddress = (Get-NetIPAddress -InterfaceIndex $route.InterfaceIndex -AddressFamily IPv4 |
    Select-Object -First 1).IPAddress
  if (-not $HostAddress) { throw "Could not find this PC's address; pass -HostAddress" }
}

Write-Host "> Configuring for $HostAddress"
docker run --rm -v "${PWD}:/w" -w /w node:22-alpine node infra/scripts/server-config.mjs --host $HostAddress
if ($LASTEXITCODE -ne 0) { throw 'Configuration failed' }

Write-Host '> Building and starting (the first build takes several minutes)'
docker @compose up -d --build
if ($LASTEXITCODE -ne 0) { throw 'Starting the server failed' }

Write-Host '> Waiting for the server'
$up = $false
for ($i = 0; $i -lt 90 -and -not $up; $i++) {
  try { Invoke-WebRequest -UseBasicParsing http://localhost:8080/v1/health | Out-Null; $up = $true }
  catch { Start-Sleep -Seconds 2 }
}
if (-not $up) { throw "The server did not come up. See: docker $($compose -join ' ') logs api live" }

if ($AdminPhone) {
  if (-not $AdminName) { $AdminName = 'مدیر' }
  Write-Host '> Creating the admin'
  docker @compose exec -T api node dist/cli/create-admin.js --phone $AdminPhone --name $AdminName
}

# Opens the ports for devices on the network; needs an administrator window, so it is offered,
# not forced.
$rules = @(
  @{ Name = 'TIHE server (TCP)'; Protocol = 'TCP'; Port = @('8080', '9000', '7880-7881') },
  @{ Name = 'TIHE media (UDP)'; Protocol = 'UDP'; Port = @('50000-50100') }
)
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
  [Security.Principal.WindowsBuiltInRole]::Administrator)
if ($admin) {
  foreach ($r in $rules) {
    if (-not (Get-NetFirewallRule -DisplayName $r.Name -ErrorAction SilentlyContinue)) {
      New-NetFirewallRule -DisplayName $r.Name -Direction Inbound -Action Allow -Protocol $r.Protocol `
        -LocalPort $r.Port -Profile Private,Domain | Out-Null
    }
  }
  $firewall = 'Firewall: opened.'
} else {
  $firewall = 'Firewall: run this script once as administrator to open the ports, or allow 8080, 9000, 7880-7881 (TCP) and 50000-50100 (UDP).'
}

Write-Host ''
Write-Host 'TIHE is running.'
Write-Host "  Server address for the app and its installer:  http://${HostAddress}:8080"
Write-Host "  $firewall"
Write-Host '  Back up infra\docker\server\.env somewhere private: without it the videos and accounts are lost.'
