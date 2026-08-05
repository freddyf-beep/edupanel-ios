[CmdletBinding()]
param(
  [switch]$Smoke,
  [switch]$Unsigned,
  [ValidateSet("Debug", "Release")]
  [string]$Configuration = "Release",
  [ValidateRange(1, 90)]
  [int]$RetentionDays = 14,
  [long]$DownloadRun = 0,
  [string]$Branch = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$selectedActions = @()
if ($Smoke) { $selectedActions += "Smoke" }
if ($Unsigned) { $selectedActions += "Unsigned" }
if ($DownloadRun -gt 0) { $selectedActions += "Download" }

if ($selectedActions.Count -gt 1) {
  throw "Usa solo una acción por ejecución: -Smoke, -Unsigned o -DownloadRun."
}

function Assert-Command {
  param([Parameter(Mandatory = $true)][string]$Name)

  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    throw "Falta '$Name'. Instálalo y vuelve a ejecutar este script."
  }
}

function Invoke-GhText {
  param([Parameter(Mandatory = $true)][string[]]$Arguments)

  $output = & gh @Arguments 2>&1
  if ($LASTEXITCODE -ne 0) {
    $message = ($output | Out-String).Trim()
    throw "Falló 'gh $($Arguments -join ' ')': $message"
  }
  return ($output | Out-String).Trim()
}

function Get-DispatchedRun {
  param(
    [Parameter(Mandatory = $true)][string]$Workflow,
    [Parameter(Mandatory = $true)][string]$HeadBranch,
    [Parameter(Mandatory = $true)][datetime]$StartedAt,
    [long[]]$ExistingRunIds = @()
  )

  for ($attempt = 1; $attempt -le 15; $attempt++) {
    $json = Invoke-GhText @(
      "run", "list",
      "--workflow", $Workflow,
      "--branch", $HeadBranch,
      "--event", "workflow_dispatch",
      "--user", "@me",
      "--limit", "20",
      "--json", "databaseId,createdAt,status,conclusion,url"
    )
    $runs = @($json | ConvertFrom-Json)
    $candidate = $runs |
      Where-Object {
        ([datetime]$_.createdAt) -ge $StartedAt.AddSeconds(-3) -and
        ([long]$_.databaseId) -notin $ExistingRunIds
      } |
      Sort-Object { [datetime]$_.createdAt } -Descending |
      Select-Object -First 1

    if ($null -ne $candidate) { return $candidate }
    Start-Sleep -Seconds 2
  }

  throw "GitHub aceptó el dispatch, pero no apareció una ejecución nueva. Revísala en Actions."
}

Assert-Command "git"
Assert-Command "gh"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Push-Location $repoRoot

try {
  $insideWorkTree = (& git rev-parse --is-inside-work-tree 2>$null).Trim()
  if ($LASTEXITCODE -ne 0 -or $insideWorkTree -ne "true") {
    throw "Este script debe ejecutarse dentro del repositorio EduPanel iOS."
  }

  $authOutput = & gh auth status 2>&1
  if ($LASTEXITCODE -ne 0) {
    throw "GitHub CLI no está autenticado. Ejecuta: gh auth login -h github.com -s repo,workflow"
  }

  $origin = (& git remote get-url origin 2>$null).Trim()
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($origin)) {
    throw "El repositorio no tiene un remote 'origin'."
  }

  $currentBranch = (& git branch --show-current).Trim()
  if ([string]::IsNullOrWhiteSpace($Branch)) { $Branch = $currentBranch }
  if ([string]::IsNullOrWhiteSpace($Branch)) {
    throw "No se pudo determinar la rama. Usa -Branch <nombre>."
  }

  $repository = Invoke-GhText @("repo", "view", "--json", "nameWithOwner", "--jq", ".nameWithOwner")
  Write-Host "Repositorio: $repository"
  Write-Host "Origin:      $origin"
  Write-Host "Rama CI:     $Branch"

  $workflowDefinitions = @(
    @{ Name = "iOS 26 smoke test"; Path = ".github/workflows/ios26-smoke.yml"; Selector = "ios26-smoke.yml" },
    @{ Name = "Build IPA for verification (unsigned)"; Path = ".github/workflows/unsigned-ipa.yml"; Selector = "unsigned-ipa.yml" },
    @{ Name = "Build iOS and Upload to TestFlight"; Path = ".github/workflows/testflight.yml"; Selector = "testflight.yml" }
  )
  $workflowJson = Invoke-GhText @("workflow", "list", "--all", "--json", "name,path,state")
  $remoteWorkflows = @($workflowJson | ConvertFrom-Json)

  foreach ($definition in $workflowDefinitions) {
    $match = $remoteWorkflows | Where-Object { $_.path -eq $definition.Path } | Select-Object -First 1
    if ($null -eq $match) {
      throw "No existe el workflow remoto '$($definition.Path)' en la rama por defecto."
    }
    Write-Host "Workflow:   $($match.name) [$($match.state)]"
  }

  $secretText = Invoke-GhText @("secret", "list", "--json", "name", "--jq", ".[].name")
  $secretNames = @($secretText -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
  $smokeSecrets = @(
    "GOOGLE_SERVICE_INFO_PLIST_BASE64"
  )
  $unsignedSecrets = @(
    "GOOGLE_SERVICE_INFO_PLIST_BASE64",
    "EDUPANEL_API_BASE_URL",
    "GOOGLE_REVERSED_CLIENT_ID"
  )
  $missingSmokeSecrets = @($smokeSecrets | Where-Object { $_ -notin $secretNames })
  $missingUnsignedSecrets = @($unsignedSecrets | Where-Object { $_ -notin $secretNames })

  if ($missingSmokeSecrets.Count -eq 0) {
    Write-Host "Secrets de smoke: completos (1/1)."
  } else {
    Write-Warning "Faltan secrets de smoke: $($missingSmokeSecrets -join ', ')"
  }
  if ($missingUnsignedSecrets.Count -eq 0) {
    Write-Host "Secrets de IPA sin firma: completos (3/3)."
  } else {
    Write-Warning "Faltan secrets de IPA sin firma: $($missingUnsignedSecrets -join ', ')"
  }

  if ($DownloadRun -gt 0) {
    $runJson = Invoke-GhText @(
      "run", "view", "$DownloadRun",
      "--json", "conclusion,headBranch,url,workflowName"
    )
    $run = $runJson | ConvertFrom-Json
    if ($run.workflowName -ne "Build IPA for verification (unsigned)") {
      throw "La ejecución $DownloadRun pertenece a '$($run.workflowName)', no al workflow de IPA sin firma."
    }
    if ($run.conclusion -ne "success") {
      throw "La ejecución $DownloadRun no terminó correctamente (estado: $($run.conclusion))."
    }

    $downloadRoot = Join-Path $repoRoot "artifacts"
    $target = Join-Path $downloadRoot "$DownloadRun"
    if ((Test-Path $target) -and (Get-ChildItem -LiteralPath $target -Force | Select-Object -First 1)) {
      throw "El destino '$target' ya contiene archivos; no se sobrescribirá."
    }
    New-Item -ItemType Directory -Path $target -Force | Out-Null
    Invoke-GhText @(
      "run", "download", "$DownloadRun",
      "--name", "EduPanel-unsigned-ipa",
      "--dir", $target
    ) | Out-Null

    $ipas = @(Get-ChildItem -LiteralPath $target -Filter "*.ipa" -File -Recurse)
    if ($ipas.Count -ne 1) {
      throw "El artifact debe contener exactamente una IPA; contiene $($ipas.Count)."
    }
    $ipa = $ipas[0]

    $actualHash = (Get-FileHash -LiteralPath $ipa.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    $checksumFiles = @(Get-ChildItem -LiteralPath $target -Filter "*.sha256" -File -Recurse)
    if ($checksumFiles.Count -ne 1) {
      throw "El artifact debe contener exactamente un checksum; contiene $($checksumFiles.Count)."
    }
    $checksumText = (Get-Content -LiteralPath $checksumFiles[0].FullName -Raw).Trim()
    if ($checksumText -notmatch '^(?<hash>[0-9a-fA-F]{64})(?:\s+.+)?$') {
      throw "El archivo .sha256 no contiene un SHA-256 válido."
    }
    $expectedHash = $Matches["hash"].ToLowerInvariant()
    if ($actualHash -ne $expectedHash) {
      throw "El SHA-256 descargado no coincide. Esperado: $expectedHash; obtenido: $actualHash"
    }

    Write-Host "Artifact verificado: $($ipa.FullName)"
    Write-Host "SHA-256:            $actualHash"
    Write-Warning "Esta IPA no está firmada y no es instalable directamente en un iPhone."
    return
  }

  if ($selectedActions.Count -eq 0) {
    Write-Host "Entorno Windows listo para editar y operar la CI."
    Write-Host "Usa -Smoke o -Unsigned para iniciar explícitamente un workflow."
    return
  }

  if ($currentBranch -ne $Branch) {
    throw "La rama local es '$currentBranch', pero se solicitó '$Branch'. Cámbiala antes de ejecutar CI."
  }
  $worktreeStatus = (& git status --porcelain 2>$null | Out-String).Trim()
  if ($LASTEXITCODE -ne 0) { throw "No se pudo leer git status." }
  if (-not [string]::IsNullOrWhiteSpace($worktreeStatus)) {
    throw "Hay cambios locales sin publicar. Haz commit y push antes de ejecutar CI."
  }

  & git fetch --quiet origin $Branch
  if ($LASTEXITCODE -ne 0) { throw "No se pudo actualizar origin/$Branch." }
  $localHead = (& git rev-parse HEAD).Trim()
  $remoteHead = (& git rev-parse FETCH_HEAD).Trim()
  if ($LASTEXITCODE -ne 0 -or $localHead -ne $remoteHead) {
    throw "HEAD local ($localHead) no coincide con origin/$Branch ($remoteHead). Haz push antes de ejecutar CI."
  }
  Write-Host "Commit publicado: $localHead"

  if ($Smoke) {
    $workflowSelector = "ios26-smoke.yml"
    $requiredSecrets = $smokeSecrets
    $dispatchArguments = @("workflow", "run", $workflowSelector, "--ref", $Branch)
  } else {
    $workflowSelector = "unsigned-ipa.yml"
    $requiredSecrets = $unsignedSecrets
    $dispatchArguments = @(
      "workflow", "run", $workflowSelector,
      "--ref", $Branch,
      "--field", "configuration=$Configuration",
      "--field", "retention_days=$RetentionDays"
    )
  }

  $missingRequiredSecrets = @($requiredSecrets | Where-Object { $_ -notin $secretNames })
  if ($missingRequiredSecrets.Count -gt 0) {
    throw "No se iniciará CI; faltan: $($missingRequiredSecrets -join ', ')"
  }

  $existingJson = Invoke-GhText @(
    "run", "list",
    "--workflow", $workflowSelector,
    "--branch", $Branch,
    "--event", "workflow_dispatch",
    "--user", "@me",
    "--limit", "20",
    "--json", "databaseId"
  )
  $existingRunIds = @($existingJson | ConvertFrom-Json | ForEach-Object { [long]$_.databaseId })
  $dispatchStarted = [datetime]::UtcNow
  $dispatchOutput = Invoke-GhText $dispatchArguments
  $runUrlMatch = [regex]::Match($dispatchOutput, "https://github\.com/[^\s]+/actions/runs/(?<id>\d+)")
  if ($runUrlMatch.Success) {
    $runId = [long]$runUrlMatch.Groups["id"].Value
    $runJson = Invoke-GhText @(
      "run", "view", "$runId",
      "--json", "databaseId,createdAt,status,conclusion,url"
    )
    $dispatchedRun = $runJson | ConvertFrom-Json
  } else {
    $dispatchedRun = Get-DispatchedRun `
      -Workflow $workflowSelector `
      -HeadBranch $Branch `
      -StartedAt $dispatchStarted `
      -ExistingRunIds $existingRunIds
  }

  Write-Host "Ejecución: $($dispatchedRun.url)"
  & gh run watch "$($dispatchedRun.databaseId)" --exit-status
  if ($LASTEXITCODE -ne 0) {
    throw "La ejecución $($dispatchedRun.databaseId) falló. Abre sus logs antes de reintentar."
  }

  if ($Unsigned) {
    Write-Host "Descarga y verifica la IPA con:"
    Write-Host ".\scripts\windows-ci.ps1 -DownloadRun $($dispatchedRun.databaseId)"
  }
} finally {
  Pop-Location
}
