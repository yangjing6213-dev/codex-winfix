[CmdletBinding()]
param(
    [switch]$Apply,
    [switch]$Force,
    [string]$ProjectPath = (Join-Path $HOME 'Downloads\demo'),
    [string]$CodexHome = (Join-Path $HOME '.codex'),
    [string]$ExpectedModel = 'gpt-5.6-sol',
    [string]$ModelProvider = 'custom',
    [string]$ModelCatalogPath = (Join-Path $HOME '.codex\models_cache.json')
)

$ErrorActionPreference = 'Stop'
$configPath = Join-Path $CodexHome 'config.toml'
$binPath = Join-Path $CodexHome 'bin'
$shimSource = Join-Path $binPath 'codex-cwd-shim.rs'
$shimBinary = Join-Path $binPath 'codex-cwd-shim.exe'
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'

function Write-Check([string]$Name, [bool]$Ok, [string]$Detail) {
    $state = if ($Ok) { 'PASS' } else { 'CHECK' }
    Write-Output ("[{0}] {1}: {2}" -f $state, $Name, $Detail)
}

function Find-RealCodex {
    $candidates = @(
        (Join-Path $env:APPDATA 'npm\node_modules\@openai\codex\node_modules\@openai\codex-win32-x64\vendor\x86_64-pc-windows-msvc\bin\codex.exe')
    ) | Select-Object -Unique

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return (Resolve-Path -LiteralPath $candidate).Path }
    }

    $command = Get-Command codex.exe -ErrorAction SilentlyContinue
    if ($command -and (Test-Path -LiteralPath $command.Source -PathType Leaf)) {
        return (Resolve-Path -LiteralPath $command.Source).Path
    }
    return $null
}

function Set-RootTomlValue([string]$Text, [string]$Key, [string]$Value) {
    $tableMatch = [regex]::Match($Text, '(?m)^\s*\[')
    $firstTable = if ($tableMatch.Success) { $tableMatch.Index } else { $Text.Length }
    $root = $Text.Substring(0, $firstTable)
    $suffix = $Text.Substring($firstTable)
    $pattern = '(?m)^(\s*)' + [regex]::Escape($Key) + '\s*=\s*.*$'
    if ([regex]::IsMatch($root, $pattern)) {
        $root = [regex]::Replace($root, $pattern, ('$1' + $Key + ' = ' + $Value), 1)
    } else {
        $root = $root.TrimEnd() + "`r`n" + $Key + ' = ' + $Value + "`r`n"
    }
    return $root + $suffix
}

function Quote-TomlBasic([string]$Value) {
    return '"' + $Value.Replace('\', '\\').Replace('"', '\"') + '"'
}

function Quote-TomlLiteral([string]$Value) {
    if ($Value.Contains("'")) { throw "Cannot encode a path containing a single quote: $Value" }
    return "'" + $Value + "'"
}

Write-Output 'Codex WinFix diagnosis'
Write-Output ("ProjectPath: {0}" -f $ProjectPath)
Write-Output ("CodexHome: {0}" -f $CodexHome)
Write-Check 'Windows' ($env:OS -eq 'Windows_NT') $env:OS
Write-Check 'Config' (Test-Path -LiteralPath $configPath -PathType Leaf) $configPath
Write-Check 'Project' (Test-Path -LiteralPath $ProjectPath -PathType Container) $ProjectPath

$realCodex = Find-RealCodex
Write-Check 'Real CLI' ($null -ne $realCodex) ($(if ($realCodex) { $realCodex } else { 'codex.exe not found' }))

if (Test-Path -LiteralPath $configPath -PathType Leaf) {
    $configText = Get-Content -Raw -LiteralPath $configPath
    Write-Check 'sandbox_mode' ($configText -match '(?m)^\s*sandbox_mode\s*=\s*["'']workspace-write["'']') 'workspace-write required'
    $modelPattern = '(?m)^\s*model\s*=\s*["'']' + [regex]::Escape($ExpectedModel) + '["'']'
    Write-Check 'model' ($configText -match $modelPattern) ($ExpectedModel + ' expected by this recovery')
    Write-Check 'provider wire API' ($configText -match '(?m)^\s*wire_api\s*=\s*["'']responses["'']') 'responses required'
    Write-Check 'subagents' ($configText -match '(?m)^\s*agents\.enabled\s*=\s*true\s*$' -or $configText -match '(?ms)^\s*\[agents\].*?^\s*enabled\s*=\s*true\s*$') 'agents must be enabled'
}

if (-not $Apply) {
    Write-Output 'Diagnosis only. Re-run with -Apply after reviewing the checks.'
    exit 0
}

if (-not $realCodex) { throw 'Cannot apply: real codex.exe was not found.' }
if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) { throw 'Cannot apply: config.toml was not found.' }
if (-not (Test-Path -LiteralPath $binPath)) { New-Item -ItemType Directory -Path $binPath | Out-Null }
if ((Test-Path -LiteralPath $shimSource) -and -not $Force) {
    throw "Refusing to overwrite existing shim source: $shimSource. Re-run with -Force only after review."
}
$rustc = Get-Command rustc.exe -ErrorAction SilentlyContinue
if (-not $rustc) { throw 'Cannot build shim: rustc.exe was not found.' }

$backupPath = "$configPath.backup-before-codex-winfix-$timestamp"
Copy-Item -LiteralPath $configPath -Destination $backupPath
Write-Output ("Backup: {0}" -f $backupPath)

$configText = Get-Content -Raw -LiteralPath $configPath
$configText = Set-RootTomlValue $configText 'model_provider' (Quote-TomlBasic $ModelProvider)
$configText = Set-RootTomlValue $configText 'model' (Quote-TomlBasic $ExpectedModel)
$configText = Set-RootTomlValue $configText 'sandbox_mode' (Quote-TomlBasic 'workspace-write')
$configText = Set-RootTomlValue $configText 'agents.enabled' 'true'
if (Test-Path -LiteralPath $ModelCatalogPath -PathType Leaf) {
    $configText = Set-RootTomlValue $configText 'model_catalog_json' (Quote-TomlLiteral (Resolve-Path -LiteralPath $ModelCatalogPath).Path)
}
Set-Content -LiteralPath $configPath -Value $configText -Encoding utf8
Write-Output 'Updated root Codex settings: model, provider, sandbox, agents, and local model catalog when present.'

$source = @'
use std::env;
use std::process::{Command, exit};

#[cfg(windows)]
use std::os::windows::process::CommandExt;

fn main() {
    let real_cli = env::var_os("CODEX_REAL_CLI_PATH")
        .map(std::path::PathBuf::from)
        .expect("CODEX_REAL_CLI_PATH must point to the real codex.exe");
    let working_dir = env::var_os("USERPROFILE")
        .map(std::path::PathBuf::from)
        .unwrap_or_else(|| std::path::PathBuf::from("."));
    let mut command = Command::new(&real_cli);
    command.args(env::args_os().skip(1))
        .current_dir(working_dir)
        .env("CODEX_CLI_PATH", &real_cli)
        .env("CODEX_REAL_CLI_PATH", &real_cli);
    #[cfg(windows)]
    command.creation_flags(0x08000000);
    match command.status() {
        Ok(status) => exit(status.code().unwrap_or(1)),
        Err(error) => {
            eprintln!("codex-cwd-shim: failed to start {}: {}", real_cli.display(), error);
            exit(1);
        }
    }
}
'@

Set-Content -LiteralPath $shimSource -Value $source -Encoding utf8
& $rustc.Source $shimSource -O -o $shimBinary
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $shimBinary -PathType Leaf)) { throw 'Shim compilation failed.' }

[Environment]::SetEnvironmentVariable('CODEX_CLI_PATH', $shimBinary, 'User')
[Environment]::SetEnvironmentVariable('CODEX_REAL_CLI_PATH', $realCodex, 'User')
Write-Output ("User CODEX_CLI_PATH -> {0}" -f $shimBinary)
Write-Output ("User CODEX_REAL_CLI_PATH -> {0}" -f $realCodex)
Write-Output 'Restart Codex Desktop before runtime verification.'
