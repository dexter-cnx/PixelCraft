$ErrorActionPreference = 'Stop'

$root = (git rev-parse --show-toplevel 2>$null)
if (-not $root) {
  Write-Error '[Pixel Craft] hooks-install: run this inside the PixelCraft repository'
  exit 1
}

Push-Location $root
try {
  git config --local core.hooksPath .githooks
  if ($LASTEXITCODE -ne 0) { throw 'git config failed' }

  $configured = git config --local --get core.hooksPath
  if ($configured -ne '.githooks') { throw 'failed to activate .githooks' }

  Write-Host '[Pixel Craft] repository Git hooks are active (.githooks); git push now runs the pre-push formatting guard.'
}
finally {
  Pop-Location
}
