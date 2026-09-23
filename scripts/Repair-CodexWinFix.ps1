[CmdletBinding()]
param(
    [switch]$Apply,
    [switch]$Force,
    [switch]$StageOnly,
    [switch]$NoEnvironmentChange,
    [switch]$PrepareBundledMarketplace,
    [string]$ProjectPath = (Join-Path $HOME 'Downloads\demo'),
    [string]$CodexHome = (Join-Path $HOME '.codex'),
    [string]$ExpectedModel = 'gpt-5.6-sol',
    [string]$ModelProvider = 'custom',
    [string]$ModelCatalogPath = (Join-Path $HOME '.codex\models_cache.json')
)

$ErrorActionPreference = 'Stop'
$configPath = Join-Path $CodexHome 'config.toml'
$binPath = Join-Path $CodexHome 'bin'
$versionedShimSource = Join-Path $binPath 'codex-cwd-shim-v2.rs'
$versionedShimBinary = Join-Path $binPath 'codex-cwd-shim-v2.exe'
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'

function Write-Check([string]$Name, [bool]$Ok, [string]$Detail) {
    $state = if ($Ok) { 'PASS' } else { 'CHECK' }
    Write-Output ('[{0}] {1}: {2}' -f $state, $Name, $Detail)
}

function Get-LiveCodexProcess {
    $names = @(
        'ChatGPT.exe',
        'codex.exe',
        'codex-cwd-shim.exe',
        'codex-code-mode-host.exe'
    )

    try {
        @(Get-CimInstance Win32_Process -ErrorAction Stop |
            Where-Object { $names -contains $_.Name } |
            Select-Object ProcessId, ParentProcessId, Name, ExecutablePath, CommandLine)
    } catch {
        throw 'Cannot enumerate Codex processes. Refusing to change configuration or environment.'
    }
}

function Find-RealCodex {
    $candidates = @(
        [Environment]::GetEnvironmentVariable('CODEX_REAL_CLI_PATH', 'Process'),
        [Environment]::GetEnvironmentVariable('CODEX_REAL_CLI_PATH', 'User'),
        (Join-Path $env:APPDATA 'npm\node_modules\@openai\codex\node_modules\@openai\codex-win32-x64\vendor\x86_64-pc-windows-msvc\bin\codex.exe')
    ) | Where-Object { $_ } | Select-Object -Unique

    foreach ($candidate in $candidates) {
        if ($candidate -notmatch 'codex-cwd-shim' -and
            (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    $command = Get-Command codex.exe -ErrorAction SilentlyContinue
    if ($command -and $command.Source -notmatch 'codex-cwd-shim' -and
        (Test-Path -LiteralPath $command.Source -PathType Leaf)) {
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
        $root = $root.TrimEnd() + [Environment]::NewLine + $Key + ' = ' + $Value + [Environment]::NewLine
    }

    return $root + $suffix
}

function Quote-TomlBasic([string]$Value) {
    return '"' + $Value.Replace('\', '\\').Replace('"', '\"') + '"'
}

function Quote-TomlLiteral([string]$Value) {
    if ($Value.Contains("'")) {
        throw "Cannot encode a path containing a single quote: $Value"
    }
    return "'" + $Value + "'"
}

function Get-ShimSource([string]$RealCodex) {
    @'
use std::env;
use std::path::{Path, PathBuf};
use std::process::{Command, exit};

#[cfg(windows)]
use std::os::windows::process::CommandExt;

fn is_codex_path(path: &Path) -> bool {
    let value = path.to_string_lossy().to_ascii_lowercase();
    let separator = std::path::MAIN_SEPARATOR;
    let package_marker = format!("{}@openai{}codex", separator, separator);
    let binary_marker = format!("{}codex-win32-x64", separator);
    let tools_marker = format!("{}codex-path", separator);
    value.contains(&package_marker)
        || value.contains(&binary_marker)
        || value.ends_with(&tools_marker)
}

fn main() {
    let real_cli = env::var_os("CODEX_REAL_CLI_PATH")
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            env::var_os("APPDATA")
                .map(PathBuf::from)
                .unwrap_or_else(|| PathBuf::from("."))
                .join("npm\\node_modules\\@openai\\codex\\node_modules\\@openai\\codex-win32-x64\\vendor\\x86_64-pc-windows-msvc\\bin\\codex.exe")
        });

    let install_bin = real_cli
        .parent()
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("."));
    let install_vendor = install_bin
        .parent()
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("."));
    let working_dir = env::var_os("USERPROFILE")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("."));

    let mut path_entries = vec![install_bin.clone()];
    let bundled_tools = install_vendor.join("codex-path");
    if bundled_tools.is_dir() {
        path_entries.push(bundled_tools);
    }
    if let Some(inherited_path) = env::var_os("PATH") {
        for entry in env::split_paths(&inherited_path) {
            if !is_codex_path(&entry) {
                path_entries.push(entry);
            }
        }
    }

    let mut command = Command::new(&real_cli);
    command
        .args(env::args_os().skip(1))
        .current_dir(working_dir)
        .env("PATH", env::join_paths(path_entries).unwrap_or_default())
        .env("CODEX_CLI_PATH", &real_cli)
        .env("CODEX_REAL_CLI_PATH", &real_cli)
        .env("TERM", "xterm-256color");

    let host_path = install_bin.join("codex-code-mode-host.exe");
    if host_path.is_file() {
        command.env("CODEX_CODE_MODE_HOST_PATH", host_path);
    }

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
}

function Copy-FileBytes([string]$Source, [string]$Destination) {
    $inputStream = [System.IO.File]::OpenRead($Source)
    $outputStream = [System.IO.File]::Create($Destination)
    try {
        $inputStream.CopyTo($outputStream)
    } finally {
        $outputStream.Dispose()
        $inputStream.Dispose()
    }
}

function Prepare-BundledMarketplace([string]$Root) {
    $target = Join-Path $Root '.tmp\bundled-marketplaces\openai-bundled'
    $required = @(
        (Join-Path $target '.agents\plugins\marketplace.json'),
        (Join-Path $target 'plugins\codex-app-tools\.codex-plugin\plugin.json')
    )

    if (($required | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) }).Count -eq 0) {
        Write-Check 'bundled marketplace' $true 'complete cache already exists'
        return
    }

    if (Test-Path -LiteralPath $target) {
        Write-Check 'bundled marketplace' $false 'incomplete final cache exists; preserved for review'
        return
    }

    $package = Get-AppxPackage -Name 'OpenAI.Codex' -ErrorAction SilentlyContinue |
        Sort-Object Version -Descending | Select-Object -First 1
    if (-not $package) {
        Write-Check 'bundled marketplace' $false 'OpenAI.Codex Windows package not found'
        return
    }

    $source = Join-Path $package.InstallLocation 'app\resources\plugins\openai-bundled'
    if (-not (Test-Path -LiteralPath $source -PathType Container)) {
        Write-Check 'bundled marketplace' $false 'bundled marketplace source not found'
        return
    }

    $parent = Split-Path -Parent $target
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    $stage = Join-Path $parent ('openai-bundled.repairing-' + [guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Force -Path $stage | Out-Null

    $sourceFiles = @(Get-ChildItem -LiteralPath $source -File -Recurse -Force)
    foreach ($file in $sourceFiles) {
        $relative = [System.IO.Path]::GetRelativePath($source, $file.FullName)
        $destination = Join-Path $stage $relative
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
        Copy-FileBytes $file.FullName $destination
        $destinationItem = Get-Item -LiteralPath $destination
        if ($destinationItem.Attributes -band [IO.FileAttributes]::Encrypted) {
            $destinationItem.Attributes = $destinationItem.Attributes -band (-bnot [IO.FileAttributes]::Encrypted)
        }
    }

    $stageRequired = @(
        (Join-Path $stage '.agents\plugins\marketplace.json'),
        (Join-Path $stage 'plugins\codex-app-tools\.codex-plugin\plugin.json')
    )
    if ($sourceFiles.Count -eq 0 -or ($stageRequired | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) }).Count -gt 0) {
        Write-Check 'bundled marketplace' $false 'staged cache is incomplete; stage preserved for review'
        return
    }

    Move-Item -LiteralPath $stage -Destination $target
    Write-Check 'bundled marketplace' $true ('materialized {0} files without encrypted attributes' -f $sourceFiles.Count)
}

Write-Output 'Codex WinFix diagnosis'
Write-Output ('ProjectPath: {0}' -f $ProjectPath)
Write-Output ('CodexHome: {0}' -f $CodexHome)
Write-Check 'Windows' ($env:OS -eq 'Windows_NT') $env:OS
Write-Check 'Config' (Test-Path -LiteralPath $configPath -PathType Leaf) $configPath
Write-Check 'Project' (Test-Path -LiteralPath $ProjectPath -PathType Container) $ProjectPath

$realCodex = Find-RealCodex
Write-Check 'Real CLI' ($null -ne $realCodex) ($(if ($realCodex) { $realCodex } else { 'codex.exe not found' }))

$live = @(Get-LiveCodexProcess)
if ($live.Count -gt 0) {
    Write-Output ('[INFO] Active Codex processes detected: {0}. No process will be stopped.' -f $live.Count)
    $live | Select-Object ProcessId, ParentProcessId, Name, ExecutablePath | Format-Table -AutoSize | Out-String | Write-Output
}

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
if (-not (Test-Path -LiteralPath $ProjectPath -PathType Container)) { throw 'Cannot apply: project directory was not found.' }
if (-not (Test-Path -LiteralPath $binPath)) { New-Item -ItemType Directory -Path $binPath | Out-Null }

$rustc = Get-Command rustc.exe -ErrorAction SilentlyContinue
if (-not $rustc) { throw 'Cannot build shim: rustc.exe was not found.' }

$activeBeforeBuild = @(Get-LiveCodexProcess)
$targetInUse = $activeBeforeBuild | Where-Object { $_.ExecutablePath -eq $versionedShimBinary }
if ($targetInUse) {
    throw ('Refusing to rebuild the active versioned shim: {0}' -f $versionedShimBinary)
}
if ($Force -and $activeBeforeBuild.Count -gt 0) {
    throw 'Refusing -Force while any Codex process is running. Close Desktop normally before rebuilding an existing versioned shim.'
}

if ($activeBeforeBuild.Count -gt 0 -and -not $StageOnly) {
    throw 'BLOCKED: Codex is running. Re-run with -StageOnly to compile only the versioned shim, or close Desktop normally before -Apply.'
}

if ($StageOnly) {
    $shouldBuild = -not (Test-Path -LiteralPath $versionedShimBinary -PathType Leaf)
    if ($shouldBuild -or $Force) {
        $sourceText = Get-ShimSource $realCodex
        Set-Content -LiteralPath $versionedShimSource -Value $sourceText -Encoding utf8
        $temporaryBinary = Join-Path $binPath ('codex-cwd-shim-v2.build-' + $PID + '.exe')
        & $rustc.Source $versionedShimSource -O -o $temporaryBinary
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $temporaryBinary -PathType Leaf)) {
            throw 'Versioned shim compilation failed.'
        }
        Move-Item -LiteralPath $temporaryBinary -Destination $versionedShimBinary -Force
        Write-Output ('Built versioned shim: {0}' -f $versionedShimBinary)
    } else {
        Write-Output ('Using existing versioned shim: {0}' -f $versionedShimBinary)
    }

    $versionOutput = & $versionedShimBinary --version 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw 'Versioned shim smoke test failed.' }
    Write-Output ('Versioned shim smoke test: {0}' -f $versionOutput.Trim())
    if ($PrepareBundledMarketplace) {
        Prepare-BundledMarketplace $CodexHome
    }
    Write-Output 'StageOnly complete: no config or user environment was changed.'
    exit 0
}

$configBackup = "$configPath.backup-before-codex-winfix-$timestamp"
Copy-Item -LiteralPath $configPath -Destination $configBackup
Write-Output ('Backup: {0}' -f $configBackup)

$configText = Get-Content -Raw -LiteralPath $configPath
$configText = Set-RootTomlValue $configText 'model_provider' (Quote-TomlBasic $ModelProvider)
$configText = Set-RootTomlValue $configText 'model' (Quote-TomlBasic $ExpectedModel)
$configText = Set-RootTomlValue $configText 'sandbox_mode' (Quote-TomlBasic 'workspace-write')
$configText = Set-RootTomlValue $configText 'agents.enabled' 'true'
if (Test-Path -LiteralPath $ModelCatalogPath -PathType Leaf) {
    $configText = Set-RootTomlValue $configText 'model_catalog_json' (Quote-TomlLiteral (Resolve-Path -LiteralPath $ModelCatalogPath).Path)
}
Set-Content -LiteralPath $configPath -Value $configText -Encoding utf8
Write-Output 'Updated root Codex settings for the next app-server start.'

$shouldBuild = -not (Test-Path -LiteralPath $versionedShimBinary -PathType Leaf)

if ($shouldBuild -or $Force) {
    $sourceText = Get-ShimSource $realCodex
    Set-Content -LiteralPath $versionedShimSource -Value $sourceText -Encoding utf8
    $temporaryBinary = Join-Path $binPath ('codex-cwd-shim-v2.build-' + $PID + '.exe')
    & $rustc.Source $versionedShimSource -O -o $temporaryBinary
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $temporaryBinary -PathType Leaf)) {
        throw 'Versioned shim compilation failed.'
    }
    Move-Item -LiteralPath $temporaryBinary -Destination $versionedShimBinary -Force
    Write-Output ('Built versioned shim: {0}' -f $versionedShimBinary)
} else {
    Write-Output ('Using existing versioned shim: {0}' -f $versionedShimBinary)
}

$previousCliPath = [Environment]::GetEnvironmentVariable('CODEX_CLI_PATH', 'User')
$previousRealPath = [Environment]::GetEnvironmentVariable('CODEX_REAL_CLI_PATH', 'User')
if ($NoEnvironmentChange) {
    Write-Output 'Skipped user environment changes because -NoEnvironmentChange was requested.'
} else {
    [Environment]::SetEnvironmentVariable('CODEX_CLI_PATH', $versionedShimBinary, 'User')
    [Environment]::SetEnvironmentVariable('CODEX_REAL_CLI_PATH', $realCodex, 'User')
    Write-Output ('Previous user CODEX_CLI_PATH: {0}' -f $previousCliPath)
    Write-Output ('Previous user CODEX_REAL_CLI_PATH: {0}' -f $previousRealPath)
    Write-Output ('Next user CODEX_CLI_PATH: {0}' -f $versionedShimBinary)
    Write-Output ('Next user CODEX_REAL_CLI_PATH: {0}' -f $realCodex)
}
Write-Output 'No Codex process was stopped or replaced. Restart Desktop normally when active projects are safe to pause.'

$versionOutput = & $versionedShimBinary --version 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) { throw 'Versioned shim smoke test failed.' }
Write-Output ('Versioned shim smoke test: {0}' -f $versionOutput.Trim())

if ($PrepareBundledMarketplace) {
    Prepare-BundledMarketplace $CodexHome
} else {
    Write-Output 'Bundled marketplace preparation was not requested. Use -PrepareBundledMarketplace only when logs show encrypted WindowsApps copy failures.'
}
