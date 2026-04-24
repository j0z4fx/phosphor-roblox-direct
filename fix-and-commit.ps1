$ErrorActionPreference = "Stop"

$repo = "D:\Downloads\phosphor-roblox-direct"
Set-Location $repo

Write-Host "=== Fix + Commit ===" -ForegroundColor Cyan

if (!(Test-Path (Join-Path $repo ".git"))) {
    throw "Not a git repo: $repo"
}

$branch = git rev-parse --abbrev-ref HEAD
Write-Host "Branch: $branch"

$utf8NoBom = New-Object System.Text.UTF8Encoding $false

$updatePath = Join-Path $repo "scripts\update.sh"
$updateSh = @"
#!/usr/bin/env bash
set -euo pipefail

if [ -f ".env" ]; then
  set -a
  source .env
  set +a
fi

lune run scripts/main.luau
"@

if (Test-Path $updatePath) {
    [System.IO.File]::WriteAllText($updatePath, $updateSh, $utf8NoBom)
    Write-Host "Fixed scripts/update.sh"
}

$templatePath = Join-Path $repo "scripts\assets\template.luau"
if (Test-Path $templatePath) {
    $c = Get-Content $templatePath -Raw
    $c = $c -replace "/refs/heads/main/", "/refs/heads/$branch/"
    $c = $c -replace "/refs/heads/master/", "/refs/heads/$branch/"
    [System.IO.File]::WriteAllText($templatePath, $c, $utf8NoBom)
    Write-Host "Fixed scripts/assets/template.luau"
}

$gitignorePath = Join-Path $repo ".gitignore"
if (!(Test-Path $gitignorePath)) {
    New-Item $gitignorePath -ItemType File | Out-Null
}

$gitignore = Get-Content $gitignorePath -Raw
if ($gitignore -notmatch "(?m)^\.env$") {
    Add-Content $gitignorePath "`n.env"
    Write-Host "Ensured .env is ignored"
}

git add .

if (git status --porcelain) {
    git commit -m "fix: repair pipeline scripts"
    git push origin $branch
    Write-Host "Committed + pushed" -ForegroundColor Green
} else {
    Write-Host "No changes to commit"
}

Write-Host "Done"
