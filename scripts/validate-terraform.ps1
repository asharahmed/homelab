Param(
  [string]$TerraformRoot = "infra/terraform"
)

$ErrorActionPreference = 'Stop'

function Get-TerraformBinary {
  if (Get-Command tofu -ErrorAction SilentlyContinue) {
    return "tofu"
  }
  if (Get-Command terraform -ErrorAction SilentlyContinue) {
    return "terraform"
  }
  throw "Neither OpenTofu nor Terraform is installed."
}

$repoRoot = Split-Path -Parent $PSCommandPath | Split-Path -Parent
$target = Join-Path $repoRoot $TerraformRoot

if (-not (Test-Path -LiteralPath $target)) {
  throw "Terraform root not found: $target"
}

$binary = Get-TerraformBinary
Push-Location $target
try {
  & $binary fmt -check -recursive
  & $binary init -backend=false
  & $binary validate
} finally {
  Pop-Location
}
