$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

param(
    [Alias("c")]
    [string]$Compose = "",
    [Alias("o")]
    [string]$Output = ".\_restored_hypernode-install-env.log",
    [string]$DeployBranch = $(if ([string]::IsNullOrWhiteSpace($env:DEPLOY_BRANCH)) { "main" } else { $env:DEPLOY_BRANCH })
)

$AbsolutePathBase = "https://raw.githubusercontent.com/Arteco-Global/hypernode_deploy/refs/heads"
$DefaultComposeUrl = "$AbsolutePathBase/$DeployBranch/installer_docker/composes/server/docker-compose.yaml"
$Script:TempComposePath = ""

function Cleanup-TempCompose {
    if (-not [string]::IsNullOrWhiteSpace($Script:TempComposePath) -and (Test-Path $Script:TempComposePath)) {
        Remove-Item -Force $Script:TempComposePath
    }
}

function Normalize-String {
    param($Value)

    return [string]$Value
}

function Write-EnvFile {
    param(
        [string]$OutputPath,
        [hashtable]$Values
    )

    $orderedKeys = @(
        "SSL_PORT",
        "DOCKER_TAG",
        "SERIAL_NUMBER",
        "SERVER_TIMEZONE",
        "SERVER_NAME",
        "ARTECO_GLOBAL_EMAIL",
        "ARTECO_GLOBAL_PASSWORD",
        "SERVER_IP_ADDRESS",
        "CERTIFICATE_PROVIDER_URL",
        "DNS_PROVIDER_URL",
        "LICENSE_PROVIDER_URL",
        "RECORDING_PATH",
        "RECORDING_DISK_SPACE",
        "STORAGE_PATH",
        "STORAGE_DISK_SPACE",
        "SNAPSHOT_PATH",
        "SNAPSHOT_DISK_SPACE",
        "DB_PORT",
        "DB_NAME",
        "PROCESS_NAME",
        "DATABASE_URI",
        "RMQ",
        "GRI",
        "INSTALL_OPTION"
    )

    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($key in $orderedKeys) {
        $rawValue = ""
        if ($Values.ContainsKey($key) -and $null -ne $Values[$key]) {
            $rawValue = [string]$Values[$key]
        }

        if ([string]::IsNullOrEmpty($rawValue)) {
            $lines.Add("${key}=")
            continue
        }

        $escapedValue = "'" + ($rawValue -replace "'", "'""'""'") + "'"
        $lines.Add("${key}=${escapedValue}")
    }

    $outputDirectory = Split-Path -Parent $OutputPath
    if (-not [string]::IsNullOrWhiteSpace($outputDirectory) -and -not (Test-Path $outputDirectory)) {
        New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    }

    [System.IO.File]::WriteAllLines($OutputPath, $lines)
}

function Invoke-DockerJson {
    param([string[]]$Arguments)

    $output = & docker @Arguments 2>$null
    if ($LASTEXITCODE -ne 0) {
        return $null
    }

    $rawOutput = (@($output) -join [Environment]::NewLine)
    if ([string]::IsNullOrWhiteSpace($rawOutput)) {
        return $null
    }

    return $rawOutput | ConvertFrom-Json
}

function Get-DockerInspect {
    param([string]$ContainerName)

    if ([string]::IsNullOrWhiteSpace($ContainerName)) {
        return $null
    }

    $inspect = Invoke-DockerJson @("inspect", $ContainerName)
    if ($inspect -is [System.Array]) {
        return $inspect[0]
    }

    return $inspect
}

function Get-ContainerEnvMap {
    param($ContainerInspect)

    $values = @{}
    $envList = @($ContainerInspect.Config.Env)
    foreach ($entry in $envList) {
        if ([string]::IsNullOrWhiteSpace($entry)) {
            continue
        }

        $separatorIndex = $entry.IndexOf("=")
        if ($separatorIndex -lt 0) {
            continue
        }

        $key = $entry.Substring(0, $separatorIndex).Trim()
        if ([string]::IsNullOrWhiteSpace($key)) {
            continue
        }

        $values[$key] = $entry.Substring($separatorIndex + 1)
    }

    return $values
}

function Get-EnvValue {
    param(
        $ContainerInspect,
        [string]$Key
    )

    if ($null -eq $ContainerInspect) {
        return ""
    }

    $envMap = Get-ContainerEnvMap $ContainerInspect
    if ($envMap.ContainsKey($Key) -and $null -ne $envMap[$Key]) {
        return [string]$envMap[$Key]
    }

    return ""
}

function Get-ImageTag {
    param($ContainerInspect)

    if ($null -eq $ContainerInspect) {
        return ""
    }

    $image = Normalize-String $ContainerInspect.Config.Image
    if ([string]::IsNullOrWhiteSpace($image)) {
        return ""
    }

    $withoutDigest = $image.Split("@")[0]
    $separatorIndex = $withoutDigest.LastIndexOf(":")
    if ($separatorIndex -lt 0) {
        return "latest"
    }

    return $withoutDigest.Substring($separatorIndex + 1).Trim()
}

function Get-PortMapping {
    param(
        $ContainerInspect,
        [string]$ContainerPort
    )

    if ($null -eq $ContainerInspect) {
        return ""
    }

    $ports = $ContainerInspect.NetworkSettings.Ports
    if ($null -eq $ports) {
        return ""
    }

    $bindingsProperty = $ports.PSObject.Properties[$ContainerPort]
    $bindings = if ($bindingsProperty) { $bindingsProperty.Value } else { $null }
    if ($null -eq $bindings -or $bindings.Count -eq 0) {
        return ""
    }

    return [string]$bindings[0].HostPort
}

function Get-MountSource {
    param(
        $ContainerInspect,
        [string]$DestinationPath
    )

    if ($null -eq $ContainerInspect) {
        return ""
    }

    foreach ($mount in @($ContainerInspect.Mounts)) {
        if ([string]$mount.Destination -eq $DestinationPath) {
            return [string]$mount.Source
        }
    }

    return ""
}

function Parse-DbPortFromUri {
    param([string]$UriValue)

    if ([string]::IsNullOrWhiteSpace($UriValue)) {
        return ""
    }

    $directMatch = [regex]::Match($UriValue, "mongodb://[^:/]+:(\d+)", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($directMatch.Success) {
        return $directMatch.Groups[1].Value
    }

    $defaultMatch = [regex]::Match($UriValue, "mongodb://[^/]+/", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($defaultMatch.Success) {
        return "27017"
    }

    return ""
}

function Resolve-ComposeSource {
    if ([string]::IsNullOrWhiteSpace($Compose)) {
        return $DefaultComposeUrl
    }

    return $Compose
}

function Get-ComposePath {
    $composeSource = Resolve-ComposeSource
    if ($composeSource -match '^https?://') {
        $Script:TempComposePath = Join-Path ([System.IO.Path]::GetTempPath()) ("recreate-env-{0}.yaml" -f ([guid]::NewGuid().Guid))
        Invoke-WebRequest -UseBasicParsing -Uri $composeSource -OutFile $Script:TempComposePath | Out-Null
        return $Script:TempComposePath
    }

    if (-not (Test-Path $composeSource)) {
        throw "Compose not found: $composeSource"
    }

    return [System.IO.Path]::GetFullPath($composeSource)
}

function Parse-ComposeServices {
    param([string]$ComposePath)

    $serviceContainer = @{}
    $services = New-Object System.Collections.Generic.List[string]
    $inServices = $false
    $currentService = ""
    $currentContainer = ""

    foreach ($line in [System.IO.File]::ReadAllLines($ComposePath)) {
        if ($line -match '^\s*#') {
            continue
        }

        if ($line -match '^services:\s*$') {
            $inServices = $true
            continue
        }

        if (-not $inServices) {
            continue
        }

        if ($line -match '^[A-Za-z0-9_].*') {
            break
        }

        $serviceMatch = [regex]::Match($line, '^\s{2}([A-Za-z0-9._-]+):\s*$')
        if ($serviceMatch.Success) {
            if (-not [string]::IsNullOrWhiteSpace($currentService)) {
                $containerName = if ([string]::IsNullOrWhiteSpace($currentContainer)) { $currentService } else { $currentContainer }
                $serviceContainer[$currentService] = $containerName
                $services.Add($currentService) | Out-Null
            }

            $currentService = $serviceMatch.Groups[1].Value
            $currentContainer = ""
            continue
        }

        if (-not [string]::IsNullOrWhiteSpace($currentService)) {
            $containerMatch = [regex]::Match($line, '^\s{4}container_name:\s*([^\s]+)\s*$')
            if ($containerMatch.Success) {
                $currentContainer = $containerMatch.Groups[1].Value
            }
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($currentService)) {
        $containerName = if ([string]::IsNullOrWhiteSpace($currentContainer)) { $currentService } else { $currentContainer }
        $serviceContainer[$currentService] = $containerName
        $services.Add($currentService) | Out-Null
    }

    return @{
        ServiceContainer = $serviceContainer
        Services = @($services)
    }
}

function Get-RunningContainerForService {
    param(
        [hashtable]$ServiceContainer,
        [string]$ServiceName
    )

    if (-not $ServiceContainer.ContainsKey($ServiceName)) {
        return $null
    }

    $containerName = [string]$ServiceContainer[$ServiceName]
    if ([string]::IsNullOrWhiteSpace($containerName)) {
        return $null
    }

    return Get-DockerInspect $containerName
}

try {
    $composePath = Get-ComposePath

    & docker ps | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Docker is not available."
    }

    $parsedCompose = Parse-ComposeServices -ComposePath $composePath
    if ($parsedCompose.Services.Count -eq 0) {
        throw "No services found in compose."
    }

    $gateway = Get-RunningContainerForService -ServiceContainer $parsedCompose.ServiceContainer -ServiceName "gateway"
    $coretrust = Get-RunningContainerForService -ServiceContainer $parsedCompose.ServiceContainer -ServiceName "coretrust"
    $recording = Get-RunningContainerForService -ServiceContainer $parsedCompose.ServiceContainer -ServiceName "recording"
    $snapshot = Get-RunningContainerForService -ServiceContainer $parsedCompose.ServiceContainer -ServiceName "snapshot"
    $portbroker = Get-RunningContainerForService -ServiceContainer $parsedCompose.ServiceContainer -ServiceName "portbroker"
    $messagebroker = Get-RunningContainerForService -ServiceContainer $parsedCompose.ServiceContainer -ServiceName "messagebroker"
    $storage = Get-RunningContainerForService -ServiceContainer $parsedCompose.ServiceContainer -ServiceName "storage"

    $values = @{}
    $values["SSL_PORT"] = Get-PortMapping $portbroker "443/tcp"
    $values["DOCKER_TAG"] = if ($messagebroker) { Get-ImageTag $messagebroker } elseif ($gateway) { Get-ImageTag $gateway } else { "" }
    $values["SERIAL_NUMBER"] = Get-EnvValue $coretrust "SERIAL_NUMBER"
    $values["SERVER_TIMEZONE"] = Get-EnvValue $gateway "SERVER_TIMEZONE"
    $values["SERVER_NAME"] = Get-EnvValue $gateway "SERVER_NAME"
    $values["ARTECO_GLOBAL_EMAIL"] = Get-EnvValue $coretrust "ARTECO_GLOBAL_EMAIL"
    $values["ARTECO_GLOBAL_PASSWORD"] = Get-EnvValue $coretrust "ARTECO_GLOBAL_PASSWORD"
    $values["SERVER_IP_ADDRESS"] = Get-EnvValue $coretrust "SERVER_IP_ADDRESS"
    $values["CERTIFICATE_PROVIDER_URL"] = Get-EnvValue $coretrust "CERTIFICATE_PROVIDER_URL"
    $values["DNS_PROVIDER_URL"] = Get-EnvValue $coretrust "DNS_PROVIDER_URL"
    $values["LICENSE_PROVIDER_URL"] = Get-EnvValue $coretrust "LICENSE_PROVIDER_URL"
    if ([string]::IsNullOrWhiteSpace($values["LICENSE_PROVIDER_URL"])) {
        $values["LICENSE_PROVIDER_URL"] = Get-EnvValue $gateway "LICENSE_PROVIDER_URL"
    }
    $values["RECORDING_PATH"] = Get-MountSource $recording "/recording_files"
    $values["RECORDING_DISK_SPACE"] = Get-EnvValue $recording "RECORDING_DISK_SPACE"
    $values["STORAGE_PATH"] = Get-MountSource $storage "/storage_files"
    $values["STORAGE_DISK_SPACE"] = Get-EnvValue $storage "STORAGE_DISK_SPACE"
    $values["SNAPSHOT_PATH"] = Get-MountSource $snapshot "/snapshot_files"
    $values["SNAPSHOT_DISK_SPACE"] = Get-EnvValue $snapshot "SNAPSHOT_DISK_SPACE"
    $values["DB_PORT"] = Parse-DbPortFromUri (Get-EnvValue $gateway "DATABASE_URI")
    if ([string]::IsNullOrWhiteSpace($values["DB_PORT"])) {
        $values["DB_PORT"] = Parse-DbPortFromUri (Get-EnvValue $coretrust "DATABASE_URI")
    }
    if ([string]::IsNullOrWhiteSpace($values["DB_PORT"])) {
        $values["DB_PORT"] = "27017"
    }
    $values["DB_NAME"] = "uss_database"
    $values["PROCESS_NAME"] = "--"
    $values["DATABASE_URI"] = ""
    $values["RMQ"] = Get-EnvValue $gateway "RABBITMQ_URI"
    $values["GRI"] = ""
    $values["INSTALL_OPTION"] = "1"

    $outputPath = if ([System.IO.Path]::IsPathRooted($Output)) {
        [System.IO.Path]::GetFullPath($Output)
    } else {
        [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $Output))
    }

    Write-EnvFile -OutputPath $outputPath -Values $values

    Write-Host ("File recreated: {0}" -f $outputPath)
    Write-Host ("Compose used: {0}" -f $composePath)
}
finally {
    Cleanup-TempCompose
}
