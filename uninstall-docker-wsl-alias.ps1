$ErrorActionPreference = "Stop"

$binDir = "C:\Tools\bin"

# Costruisci i path con stringhe semplici (più compatibile)
$shimFiles = @(
  "$binDir\docker.cmd"
  "$binDir\docker-compose.cmd"
)

Write-Host "== Rimozione shim docker =="

# 1) Cancella i file shim se esistono
foreach ($f in $shimFiles) {
  if (Test-Path $f) {
    Remove-Item -Force $f
    Write-Host "Rimosso: $f"
  } else {
    Write-Host "Non trovato: $f"
  }
}

# 2) Se la cartella è vuota, opzionalmente rimuovila
if (Test-Path $binDir) {
  $remaining = Get-ChildItem -Path $binDir -Force -ErrorAction SilentlyContinue
  if (-not $remaining -or $remaining.Count -eq 0) {
    try {
      Remove-Item -Force -Recurse $binDir
      Write-Host "Rimossa cartella vuota: $binDir"
    } catch {
      Write-Host "Nota: non riesco a rimuovere la cartella (forse in uso): $binDir"
    }
  } else {
    Write-Host "Cartella non vuota, non rimossa: $binDir"
  }
}

function Remove-PathEntry {
  param(
    [Parameter(Mandatory=$true)][ValidateSet("Machine","User")] [string] $scope,
    [Parameter(Mandatory=$true)][string] $entry
  )

  $path = [Environment]::GetEnvironmentVariable("Path", $scope)
  if (-not $path) { return $false }

  $parts = $path.Split(';') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }

  # confronto case-insensitive
  $newParts = $parts | Where-Object { $_.ToLower() -ne $entry.ToLower() }

  if ($newParts.Count -eq $parts.Count) {
    return $false
  }

  [Environment]::SetEnvironmentVariable("Path", ($newParts -join ';'), $scope)
  return $true
}

Write-Host ""
Write-Host "== Rimozione C:\Tools\bin dal PATH =="

$removedMachine = $false
try { $removedMachine = Remove-PathEntry -scope "Machine" -entry $binDir } catch { $removedMachine = $false }

$removedUser = Remove-PathEntry -scope "User" -entry $binDir

if ($removedMachine) { Write-Host "Rimosso dal PATH di sistema (Machine)." } else { Write-Host "Non presente (o non permesso) nel PATH di sistema (Machine)." }
if ($removedUser)    { Write-Host "Rimosso dal PATH utente (User)." } else { Write-Host "Non presente nel PATH utente (User)." }

Write-Host ""
Write-Host "✔ Ripristino completato."
Write-Host "⚠ Chiudi e riapri i terminali (o fai logoff/login) per applicare il PATH aggiornato."
Write-Host ""
Write-Host "Verifica (in un NUOVO terminale):"
Write-Host "  where docker"
Write-Host "  where docker-compose"
