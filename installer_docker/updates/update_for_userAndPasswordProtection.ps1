param(
    [string]$DeployBranch = $(if ([string]::IsNullOrWhiteSpace($env:DEPLOY_BRANCH)) { "feature/userAndPasswordProtection" } else { $env:DEPLOY_BRANCH }),
    [string]$EnvFile = "",
    [Alias("h")]
    [switch]$Help
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if ($Help) {
    Write-Host @"
Usage: $(Split-Path -Leaf $PSCommandPath) [options]

Options:
  -DeployBranch <name>   Branch da usare per scaricare/avviare native_update.sh
                         (default: feature/userAndPasswordProtection)
  -EnvFile <path>        Path dell'env file (default: .hypernode-install-env.log nella cwd,
                         fallback: root repo)
  -Help                  Mostra questo help
"@
    exit 0
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$InstallerDir = Split-Path -Parent $ScriptDir
$DeployDir = Split-Path -Parent $InstallerDir

$AbsolutePathBase = "https://raw.githubusercontent.com/Arteco-Global/hypernode_deploy/refs/heads"
$NativeUpdateUrl = "$AbsolutePathBase/$DeployBranch/installer_docker/native_update.sh"
$DbComposeUrl = "$AbsolutePathBase/$DeployBranch/installer_docker/composes/database/docker-compose.yaml"

$defaultEnv = Join-Path (Get-Location).Path ".hypernode-install-env.log"
if (-not (Test-Path $defaultEnv)) {
    $fallbackEnv = Join-Path $DeployDir ".hypernode-install-env.log"
    if (Test-Path $fallbackEnv) {
        $defaultEnv = $fallbackEnv
    }
}
if ([string]::IsNullOrWhiteSpace($EnvFile)) {
    $EnvFile = $defaultEnv
}

$NewUser = "hypernode"
$Script:NewPassword = ""
$Script:OldDbUser = if ([string]::IsNullOrWhiteSpace($env:OLD_DB_USER)) { "" } else { $env:OLD_DB_USER }
$Script:OldDbPass = if ([string]::IsNullOrWhiteSpace($env:OLD_DB_PASS)) { "" } else { $env:OLD_DB_PASS }
$NativeUpdatePath = Join-Path (Get-Location).Path "native_update.sh"

function Log {
    param([string]$Message)
    Write-Host $Message
}

function Log-Db {
    param([string]$Message)
    Write-Host "[DB] $Message"
}

function Warn {
    param([string]$Message)
    Write-Host "[WARN] $Message"
}

function Die {
    param([string]$Message)
    Write-Error $Message
    exit 1
}

function Strip-Quotes {
    param([string]$Value)

    if ([string]::IsNullOrEmpty($Value)) {
        return ""
    }

    $v = $Value.Trim()
    if ($v.Length -ge 2) {
        if (($v.StartsWith("\"") -and $v.EndsWith("\"")) -or ($v.StartsWith("'") -and $v.EndsWith("'"))) {
            return $v.Substring(1, $v.Length - 2)
        }
    }

    return $v
}

function Get-EnvRawValue {
    param([string]$Key)

    if (-not (Test-Path $EnvFile)) {
        return ""
    }

    $value = ""
    foreach ($line in [System.IO.File]::ReadAllLines($EnvFile)) {
        if ($line -match "^\s*$([regex]::Escape($Key))=(.*)$") {
            $value = $Matches[1]
        }
    }

    return $value
}

function Upsert-EnvKey {
    param(
        [string]$Key,
        [string]$Value
    )

    $escapedValue = $Value.Replace("'", "'\"'\"'")
    $newLine = "$Key='$escapedValue'"

    $lines = New-Object System.Collections.Generic.List[string]
    if (Test-Path $EnvFile) {
        $lines.AddRange([System.IO.File]::ReadAllLines($EnvFile))
    }

    $newLines = New-Object System.Collections.Generic.List[string]
    $found = $false

    foreach ($line in $lines) {
        if ($line -match "^\s*$([regex]::Escape($Key))=") {
            if (-not $found) {
                $newLines.Add($newLine)
                $found = $true
            }
            continue
        }
        $newLines.Add($line)
    }

    if (-not $found) {
        $newLines.Add($newLine)
    }

    [System.IO.File]::WriteAllLines($EnvFile, $newLines)
}

function Update-UriCredentials {
    param(
        [string]$Key,
        [string]$SchemeRegex,
        [string]$DefaultValue
    )

    $cleaned = Strip-Quotes (Get-EnvRawValue -Key $Key)
    $newValue = $DefaultValue

    if (-not [string]::IsNullOrWhiteSpace($cleaned)) {
        $rxWithCreds = "^($SchemeRegex)://[^@]+@(.+)$"
        $rxNoCreds = "^($SchemeRegex)://(.+)$"

        if ($cleaned -match $rxWithCreds) {
            $newValue = "$($Matches[1])://$NewUser:$Script:NewPassword@$($Matches[2])"
        } elseif ($cleaned -match $rxNoCreds) {
            $newValue = "$($Matches[1])://$NewUser:$Script:NewPassword@$($Matches[2])"
        }
    }

    Upsert-EnvKey -Key $Key -Value $newValue
}

function Ensure-EnvUpdates {
    if (-not (Test-Path $EnvFile)) {
        New-Item -ItemType File -Path $EnvFile -Force | Out-Null
    }

    Upsert-EnvKey -Key "DOCKER_TAG" -Value "userAndPasswordProtection"
    Upsert-EnvKey -Key "RABBITMQ_DEFAULT_USER" -Value $NewUser
    Upsert-EnvKey -Key "RABBITMQ_DEFAULT_PASS" -Value $Script:NewPassword
    Upsert-EnvKey -Key "DB_USERNAME" -Value $NewUser
    Upsert-EnvKey -Key "DB_PASSWORD" -Value $Script:NewPassword

    Update-UriCredentials -Key "RMQ" -SchemeRegex "amqp|amqps" -DefaultValue "amqp://$NewUser:$Script:NewPassword@messagebroker:5672"

    $currentDbName = "gateway-db"
    $currentDbUri = Strip-Quotes (Get-EnvRawValue -Key "DATABASE_URI")
    if ($currentDbUri -match "^mongodb://[^@]+@[^/]+/([^?]+)(\?.*)?$") {
        $currentDbName = $Matches[1]
    }

    Update-UriCredentials -Key "DATABASE_URI" -SchemeRegex "mongodb" -DefaultValue "mongodb://$NewUser:$Script:NewPassword@127.0.0.1:27017/$currentDbName?authSource=admin"
    Update-UriCredentials -Key "LOCAL_DB_CONNECTION" -SchemeRegex "mongodb" -DefaultValue "mongodb://$NewUser:$Script:NewPassword@127.0.0.1:27017/exports?authSource=admin"
}

function Generate-Password {
    $chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789".ToCharArray()
    $bytes = New-Object byte[] 24
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)

    $result = New-Object System.Text.StringBuilder
    for ($i = 0; $i -lt $bytes.Length -and $result.Length -lt 12; $i++) {
        [void]$result.Append($chars[$bytes[$i] % $chars.Length])
    }

    while ($result.Length -lt 12) {
        $b = New-Object byte[] 1
        [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b)
        [void]$result.Append($chars[$b[0] % $chars.Length])
    }

    return $result.ToString()
}

function Init-OldDbCredentialsFromEnv {
    if (-not [string]::IsNullOrWhiteSpace($Script:OldDbUser) -and -not [string]::IsNullOrWhiteSpace($Script:OldDbPass)) {
        Log-Db "Credenziali OLD_DB_* fornite via env, uso quelle"
        return
    }

    $envDbUser = Strip-Quotes (Get-EnvRawValue -Key "DB_USERNAME")
    $envDbPass = Strip-Quotes (Get-EnvRawValue -Key "DB_PASSWORD")

    if (-not [string]::IsNullOrWhiteSpace($envDbUser) -and -not [string]::IsNullOrWhiteSpace($envDbPass)) {
        $Script:OldDbUser = $envDbUser
        $Script:OldDbPass = $envDbPass
        Log-Db "Credenziali fallback lette da .env: $Script:OldDbUser/********"
    } else {
        Log-Db "Nessuna credenziale DB trovata in .env: fallback autenticato disabilitato"
    }
}

function Find-MongoContainers {
    $rows = & docker ps --format "{{.Names}}|{{.Image}}|{{.Ports}}" 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "Errore durante docker ps"
    }

    $set = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($row in @($rows)) {
        if ([string]::IsNullOrWhiteSpace($row)) {
            continue
        }

        $parts = $row.Split("|", 3)
        if ($parts.Count -lt 3) {
            continue
        }

        $name = [string]$parts[0]
        $image = [string]$parts[1]
        $ports = [string]$parts[2]

        $n = $name.ToLowerInvariant()
        $i = $image.ToLowerInvariant()
        $p = $ports.ToLowerInvariant()

        if ($i -match "mongo|database|usee_database" -or
            $n -match "mongo|database|uss_database" -or
            $p -match "27017") {
            [void]$set.Add($name)
        }
    }

    return @($set)
}

function Detect-ComposeCmd {
    & docker compose version *> $null
    if ($LASTEXITCODE -eq 0) {
        return "docker_compose_v2"
    }

    & docker-compose version *> $null
    if ($LASTEXITCODE -eq 0) {
        return "docker_compose_v1"
    }

    return $null
}

function Export-EnvFileToProcess {
    if (-not (Test-Path $EnvFile)) {
        return
    }

    foreach ($line in [System.IO.File]::ReadAllLines($EnvFile)) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }
        if ($line -match '^\s*#') {
            continue
        }
        if ($line -notmatch '^\s*([^=]+)=(.*)$') {
            continue
        }

        $key = $Matches[1].Trim()
        $rawValue = $Matches[2]
        if ([string]::IsNullOrWhiteSpace($key)) {
            continue
        }

        $cleanValue = Strip-Quotes $rawValue
        [System.Environment]::SetEnvironmentVariable($key, $cleanValue, [System.EnvironmentVariableTarget]::Process)
    }
}

function Get-ContainerShell {
    param([string]$Container)

    & docker exec $Container sh -lc "command -v sh >/dev/null 2>&1" *> $null
    if ($LASTEXITCODE -eq 0) {
        return "sh"
    }

    & docker exec $Container bash -lc "command -v bash >/dev/null 2>&1" *> $null
    if ($LASTEXITCODE -eq 0) {
        return "bash"
    }

    return ""
}

function Db-IsProtected {
    param(
        [string]$Container,
        [string]$ShellBin
    )

    $script = @'
if command -v mongosh >/dev/null 2>&1; then
  mongosh --quiet --host 127.0.0.1 --port 27017 --eval "db.getSiblingDB(\"admin\").runCommand({usersInfo:1}); print(\"UNAUTH_OK\")"
else
  mongo --quiet --host 127.0.0.1 --port 27017 --eval "db.getSiblingDB(\"admin\").runCommand({usersInfo:1}); print(\"UNAUTH_OK\")"
fi
'@

    $out = & docker exec $Container $ShellBin -lc $script 2>&1
    $text = (@($out) -join [Environment]::NewLine)

    if ($text -match "UNAUTH_OK") {
        return $false
    }

    if ($text -match "requires authentication|Authentication failed|Unauthorized|not authorized|command .* requires authentication") {
        return $true
    }

    return $false
}

function Recreate-DatabaseServiceForContainer {
    param([string]$Container)

    $composeCmd = Detect-ComposeCmd
    if ($null -eq $composeCmd) {
        Warn "Né docker compose né docker-compose disponibili per il force-recreate DB"
        return $false
    }

    $projectName = (& docker inspect -f "{{ index .Config.Labels \"com.docker.compose.project\" }}" $Container 2>$null)
    if ($LASTEXITCODE -ne 0) {
        $projectName = ""
    }

    $tmpDbCompose = Join-Path ([System.IO.Path]::GetTempPath()) ("db-compose-{0}.yaml" -f ([guid]::NewGuid().Guid))
    try {
        Invoke-WebRequest -Uri $DbComposeUrl -OutFile $tmpDbCompose | Out-Null
    } catch {
        Warn "Impossibile scaricare compose DB: $DbComposeUrl"
        if (Test-Path $tmpDbCompose) { Remove-Item -Force $tmpDbCompose }
        return $false
    }

    Log-Db "Force-recreate servizio database per applicare auth"
    Export-EnvFileToProcess

    if (-not [string]::IsNullOrWhiteSpace($projectName) -and $projectName -ne "<no value>") {
        if ($composeCmd -eq "docker_compose_v2") {
            $cmd = @("compose", "--project-name", $projectName, "-f", $tmpDbCompose, "up", "-d", "--force-recreate", "--remove-orphans")
            & docker @cmd
        } else {
            $cmd = @("--project-name", $projectName, "-f", $tmpDbCompose, "up", "-d", "--force-recreate", "--remove-orphans")
            & docker-compose @cmd
        }
    } else {
        $cmd = if ($composeCmd -eq "docker_compose_v2") {
            @("compose", "-f", $tmpDbCompose, "up", "-d", "--force-recreate", "--remove-orphans")
        } else {
            @("-f", $tmpDbCompose, "up", "-d", "--force-recreate", "--remove-orphans")
        }

        if ($composeCmd -eq "docker_compose_v2") {
            & docker @cmd
        } else {
            & docker-compose @cmd
        }
    }

    $ok = ($LASTEXITCODE -eq 0)
    Remove-Item -Force $tmpDbCompose -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 4
    return $ok
}

function Invoke-DbCredentialUpdate {
    param(
        [string]$Container,
        [string]$ShellBin,
        [switch]$UseAuth
    )

    $shellScript = @'
set -e
cat > /tmp/hn_update_users.js <<'JS'
var adminDb=db.getSiblingDB("admin");
var user=process.env.HN_NEW_USER;
var pass=process.env.HN_NEW_PASS;
var exists=adminDb.getUser(user);
if (exists) { adminDb.updateUser(user,{pwd:pass,roles:[{role:"root",db:"admin"}]}); }
else { adminDb.createUser({user:user,pwd:pass,roles:[{role:"root",db:"admin"}]}); }
var adminUser=adminDb.getUser("admin");
if (adminUser) { adminDb.updateUser("admin",{pwd:pass,roles:[{role:"root",db:"admin"}]}); }
else { adminDb.createUser({user:"admin",pwd:pass,roles:[{role:"root",db:"admin"}]}); }
var dbNames=adminDb.getMongo().getDBNames();
for (var i=0;i<dbNames.length;i++) {
  var dbName=dbNames[i];
  if (dbName === "admin" || dbName === "local" || dbName === "config") { continue; }
  try {
    var targetDb=db.getSiblingDB(dbName);
    var colls=targetDb.getCollectionNames();
    if (colls.indexOf("microservicesInstanceConfiguration") === -1) {
      print("broker_update db=" + dbName + " updated=0 (collection_missing)");
      continue;
    }
    var coll=targetDb.getCollection("microservicesInstanceConfiguration");
    var cursor=coll.find({ broker: { $type: "string" } }, { broker: 1 });
    var updated=0;
    while (cursor.hasNext()) {
      var doc=cursor.next();
      var broker=doc.broker;
      var newBroker=broker;
      if (/^(amqps?):\/\/[^@]+@(.+)$/.test(broker)) {
        newBroker=broker.replace(/^(amqps?):\/\/[^@]+@(.+)$/, "$1://" + user + ":" + pass + "@$2");
      } else if (/^(amqps?):\/\/(.+)$/.test(broker)) {
        newBroker=broker.replace(/^(amqps?):\/\/(.+)$/, "$1://" + user + ":" + pass + "@$2");
      }
      if (newBroker !== broker) {
        coll.updateOne({ _id: doc._id }, { $set: { broker: newBroker } });
        updated++;
      }
    }
    print("broker_update db=" + dbName + " updated=" + updated);
  } catch (e) {
    print("broker_update db=" + dbName + " error=" + e);
  }
}
print("ok");
JS

if command -v mongosh >/dev/null 2>&1; then
  if [ -n "$HN_OLD_USER" ] && [ -n "$HN_OLD_PASS" ]; then
    mongosh --quiet --host 127.0.0.1 --port 27017 -u "$HN_OLD_USER" -p "$HN_OLD_PASS" --authenticationDatabase admin --file /tmp/hn_update_users.js
  else
    mongosh --quiet --host 127.0.0.1 --port 27017 --file /tmp/hn_update_users.js
  fi
else
  if [ -n "$HN_OLD_USER" ] && [ -n "$HN_OLD_PASS" ]; then
    mongo --quiet --host 127.0.0.1 --port 27017 -u "$HN_OLD_USER" -p "$HN_OLD_PASS" --authenticationDatabase admin --file /tmp/hn_update_users.js
  else
    mongo --quiet --host 127.0.0.1 --port 27017 --file /tmp/hn_update_users.js
  fi
fi
rm -f /tmp/hn_update_users.js
'@

    $args = @("exec", "-e", "HN_NEW_USER=$NewUser", "-e", "HN_NEW_PASS=$Script:NewPassword")

    if ($UseAuth) {
        $args += @("-e", "HN_OLD_USER=$Script:OldDbUser", "-e", "HN_OLD_PASS=$Script:OldDbPass")
    } else {
        $args += @("-e", "HN_OLD_USER=", "-e", "HN_OLD_PASS=")
    }

    $args += @($Container, $ShellBin, "-lc", $shellScript)

    $out = & docker @args 2>&1
    $exitCode = $LASTEXITCODE

    return @{
        ExitCode = $exitCode
        Output = (@($out) -join [Environment]::NewLine)
    }
}

function Update-CredentialsInDbContainer {
    param([string]$Container)

    $inspectImage = (& docker inspect -f "{{.Config.Image}}" $Container 2>$null)
    $inspectStatus = (& docker inspect -f "{{.State.Status}}" $Container 2>$null)

    Log-Db "Container: $Container | image: $(if ([string]::IsNullOrWhiteSpace($inspectImage)) { 'unknown' } else { $inspectImage }) | status: $(if ([string]::IsNullOrWhiteSpace($inspectStatus)) { 'unknown' } else { $inspectStatus })"

    $shellBin = Get-ContainerShell -Container $Container
    if ([string]::IsNullOrWhiteSpace($shellBin)) {
        Warn "Container $Container senza shell supportata: skip"
        return $false
    }

    Log-Db "Shell rilevata in $Container: $shellBin"
    Log-Db "Tentativo update utenti su DB admin senza autenticazione"

    $firstTry = Invoke-DbCredentialUpdate -Container $Container -ShellBin $shellBin
    $firstOut = [string]$firstTry.Output

    if ($firstTry.ExitCode -eq 0 -and $firstOut -notmatch "Authentication failed|MongoServerError|Error:") {
        if ($firstOut -match "(^|\s)ok($|\s)") {
            Log-Db "Update credenziali completato su $Container"
            foreach ($line in @($firstOut -split "`r?`n")) {
                if (-not [string]::IsNullOrWhiteSpace($line)) {
                    Log-Db "Output ${Container}: $line"
                }
            }

            if (Db-IsProtected -Container $Container -ShellBin $shellBin) {
                Log-Db "Protezione DB attiva su $Container (accesso anonimo bloccato)"
                return $true
            }

            Warn "DB ancora non protetto su $Container dopo update utenti"
            if (Recreate-DatabaseServiceForContainer -Container $Container) {
                if (Db-IsProtected -Container $Container -ShellBin $shellBin) {
                    Log-Db "Protezione DB attivata su $Container dopo force-recreate"
                    return $true
                }
            }

            Warn "DB ancora non protetto su $Container anche dopo force-recreate"
            return $false
        }

        Warn "Output inatteso dal comando DB su $Container"
    }

    if (-not [string]::IsNullOrWhiteSpace($firstOut)) {
        foreach ($line in @($firstOut -split "`r?`n")) {
            if (-not [string]::IsNullOrWhiteSpace($line)) {
                Warn "[DB:$Container] $line"
            }
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($Script:OldDbUser) -and -not [string]::IsNullOrWhiteSpace($Script:OldDbPass)) {
        Log-Db "Retry su $Container con autenticazione $Script:OldDbUser/********"
        $retry = Invoke-DbCredentialUpdate -Container $Container -ShellBin $shellBin -UseAuth
        $retryOut = [string]$retry.Output

        if ($retry.ExitCode -eq 0 -and $retryOut -notmatch "Authentication failed|MongoServerError|Error:" -and $retryOut -match "(^|\s)ok($|\s)") {
            Log-Db "Update credenziali completato su $Container (retry autenticato)"
            foreach ($line in @($retryOut -split "`r?`n")) {
                if (-not [string]::IsNullOrWhiteSpace($line)) {
                    Log-Db "Output ${Container}: $line"
                }
            }

            if (Db-IsProtected -Container $Container -ShellBin $shellBin) {
                Log-Db "Protezione DB attiva su $Container (accesso anonimo bloccato)"
                return $true
            }

            Warn "DB ancora non protetto su $Container dopo retry autenticato"
            if (Recreate-DatabaseServiceForContainer -Container $Container) {
                if (Db-IsProtected -Container $Container -ShellBin $shellBin) {
                    Log-Db "Protezione DB attivata su $Container dopo force-recreate"
                    return $true
                }
            }

            Warn "DB ancora non protetto su $Container anche dopo force-recreate"
            return $false
        }

        if (-not [string]::IsNullOrWhiteSpace($retryOut)) {
            foreach ($line in @($retryOut -split "`r?`n")) {
                if (-not [string]::IsNullOrWhiteSpace($line)) {
                    Warn "[DB:$Container] $line"
                }
            }
        }
    } else {
        Log-Db "Fallback autenticato disabilitato (OLD_DB_USER/OLD_DB_PASS non impostati)"
    }

    Warn "Update credenziali fallito su $Container"
    return $false
}

function Update-AllDatabases {
    $containers = @()
    try {
        $containers = @(Find-MongoContainers)
    } catch {
        Warn "Errore durante la ricerca dei container MongoDB"
        return $false
    }

    if ($containers.Count -eq 0) {
        Warn "Nessun container MongoDB rilevato in esecuzione"
        return $true
    }

    $total = $containers.Count
    $okCount = 0
    $failCount = 0

    Log "Aggiornamento credenziali DB su $total container MongoDB"
    foreach ($c in $containers) {
        Log-Db "-----"
        if (Update-CredentialsInDbContainer -Container $c) {
            $okCount++
        } else {
            $failCount++
        }
    }

    Log-Db "Riepilogo update DB: total=$total, ok=$okCount, fail=$failCount"
    if ($failCount -gt 0) {
        Warn "Alcuni database non sono stati aggiornati correttamente ($failCount/$total)"
        return $false
    }

    return $true
}

function Remove-MessagebrokerAndVolumes {
    $ids = @(& docker ps -aq --filter "name=(^|[-_])messagebroker($|[-_])" 2>$null)
    if ($LASTEXITCODE -ne 0) {
        Warn "Impossibile enumerare container messagebroker"
        return
    }

    $ids = @($ids | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($ids.Count -eq 0) {
        Log "Nessun container messagebroker trovato"
        return
    }

    foreach ($id in $ids) {
        $volumes = @(& docker inspect $id --format '{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}}{{println}}{{end}}{{end}}' 2>$null)
        $volumes = @($volumes | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

        Log "Rimozione container messagebroker: $id"
        & docker rm -f $id *> $null

        foreach ($v in $volumes) {
            Log "  Rimozione volume: $v"
            & docker volume rm $v *> $null
            if ($LASTEXITCODE -ne 0) {
                Warn "Volume $v non rimosso (forse già assente/in uso)"
            }
        }
    }
}

function Download-NativeUpdate {
    Log "Download native_update.sh da: $NativeUpdateUrl"

    try {
        Invoke-WebRequest -Uri $NativeUpdateUrl -OutFile $NativeUpdatePath | Out-Null
    } catch {
        Die "Download fallito: $NativeUpdateUrl"
    }
}

function Prompt-AndRunUpdate {
    Write-Host ""
    Write-Host "Preparazione completata."
    Write-Host "Nuova password generata: $Script:NewPassword"

    $answer = Read-Host "Procedere ora con native_update.sh? [y/N]"
    if ($answer -match '^(y|yes)$') {
        $bash = Get-Command bash -ErrorAction SilentlyContinue
        if ($null -eq $bash) {
            Warn "bash non trovato su Windows. Esegui manualmente: bash $NativeUpdatePath --env-file $EnvFile --deploy-branch $DeployBranch"
            return
        }

        Log "Avvio $NativeUpdatePath"
        & $bash.Source $NativeUpdatePath --env-file $EnvFile --deploy-branch $DeployBranch
        if ($LASTEXITCODE -ne 0) {
            Die "native_update.sh terminato con errore"
        }
    } else {
        Log "Update non avviato. Esegui manualmente: bash $NativeUpdatePath --env-file $EnvFile --deploy-branch $DeployBranch"
    }
}

if (-not (Test-Path $EnvFile)) {
    Warn "Env file non trovato: $EnvFile (verrà creato)"
}

& docker --version *> $null
if ($LASTEXITCODE -ne 0) {
    Die "Docker non disponibile"
}

$Script:NewPassword = if ([string]::IsNullOrWhiteSpace($env:NEW_PASSWORD)) { Generate-Password } else { $env:NEW_PASSWORD }
if ([string]::IsNullOrWhiteSpace($Script:NewPassword)) {
    Die "Impossibile generare password dinamica"
}

Log "Password dinamica generata"
Init-OldDbCredentialsFromEnv

if (-not (Update-AllDatabases)) {
    Die "Update DB fallito: interrompo per evitare disallineamento credenziali tra DB e .env"
}

Remove-MessagebrokerAndVolumes
Ensure-EnvUpdates
Download-NativeUpdate
Prompt-AndRunUpdate
