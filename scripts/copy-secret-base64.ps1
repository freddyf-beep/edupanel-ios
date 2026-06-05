param(
  [Parameter(Mandatory = $true)]
  [string]$Path
)

$resolvedPath = Resolve-Path -LiteralPath $Path -ErrorAction Stop
$bytes = [IO.File]::ReadAllBytes($resolvedPath)
$base64 = [Convert]::ToBase64String($bytes)
$base64 | Set-Clipboard

Write-Host "Base64 copied to clipboard for: $resolvedPath"
