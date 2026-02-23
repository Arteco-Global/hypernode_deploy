$ErrorActionPreference = "Stop"

# Cartella per gli shim
$binDir = "C:\Tools\bin"

# Crea la cartella se non esiste
if (!(Test-Path $binDir)) {
    New-Item -ItemType Directory -Path $binDir | Out-Null
}

# docker.cmd
$dockerCmd = @"
@echo off
wsl.exe docker %*
"@
Set-Content -Path "$binDir\docker.cmd" -Value $dockerCmd -Encoding ASCII

# docker-compose.cmd (compatibilità legacy)
$dockerComposeCmd = @"
@echo off
wsl.exe docker compose %*
"@
Set-Content -Path "$binDir\docker-compose.cmd" -Value $dockerComposeCmd -Encoding ASCII

# Aggiunge C:\Tools\bin al PATH di sistema se non già presente
$machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
if ($machinePath -notlike "*$binDir*") {
    [Environment]::SetEnvironmentVariable(
        "Path",
        "$machinePath;$binDir",
        "Machine"
    )
    Write-Host "PATH di sistema aggiornato."
} else {
    Write-Host "PATH già configurato."
}

Write-Host ""
Write-Host "✔ Alias docker configurato correttamente."
Write-Host "⚠ Aprire un nuovo terminale per usarlo."
