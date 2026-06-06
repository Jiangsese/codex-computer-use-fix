param(
  [switch]$Force,
  [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'

function Write-Step {
  param([string]$Message)
  Write-Host "[codex-repair] $Message"
}

function Get-CodexHome {
  if ($env:CODEX_HOME) {
    return $env:CODEX_HOME
  }
  return (Join-Path $env:USERPROFILE '.codex')
}

function Get-CodexPackage {
  $pkg = Get-AppxPackage -Name OpenAI.Codex | Select-Object -First 1
  if (-not $pkg) {
    throw 'OpenAI.Codex Windows Store package was not found.'
  }
  return $pkg
}

function Get-InstalledBundledMarketplace {
  $pkg = Get-CodexPackage
  $root = Join-Path $pkg.InstallLocation 'app\resources\plugins\openai-bundled'
  $manifest = Join-Path $root '.agents\plugins\marketplace.json'
  if (-not (Test-Path -LiteralPath $manifest)) {
    throw "The installed Codex package does not contain openai-bundled marketplace metadata: $manifest"
  }
  return $root
}

function Read-Utf8Lines {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    return [string[]]@()
  }
  $encoding = [System.Text.UTF8Encoding]::new($false)
  return [string[]]([System.IO.File]::ReadAllLines($Path, $encoding))
}

function Write-Utf8Lines {
  param(
    [string]$Path,
    [string[]]$Lines
  )
  $encoding = [System.Text.UTF8Encoding]::new($false)
  [System.IO.File]::WriteAllLines($Path, $Lines, $encoding)
}

function Format-TomlValue {
  param($Value)
  if ($Value -is [bool]) {
    if ($Value) { return 'true' }
    return 'false'
  }
  $text = [string]$Value
  return "'" + $text.Replace("'", "''") + "'"
}

function Set-TomlTable {
  param(
    [string]$ConfigPath,
    [string]$Header,
    [System.Collections.Specialized.OrderedDictionary]$Values
  )

  $lines = [System.Collections.Generic.List[string]]::new()
  foreach ($line in (Read-Utf8Lines $ConfigPath)) {
    $lines.Add($line)
  }

  $block = [System.Collections.Generic.List[string]]::new()
  $block.Add($Header)
  foreach ($key in $Values.Keys) {
    $block.Add("$key = $(Format-TomlValue $Values[$key])")
  }
  $block.Add('')

  $start = -1
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i].Trim() -eq $Header) {
      $start = $i
      break
    }
  }

  if ($start -ge 0) {
    $end = $start + 1
    while ($end -lt $lines.Count -and -not $lines[$end].TrimStart().StartsWith('[')) {
      $end++
    }
    $lines.RemoveRange($start, $end - $start)
    $lines.InsertRange($start, $block)
  } else {
    if ($lines.Count -gt 0 -and $lines[$lines.Count - 1].Trim() -ne '') {
      $lines.Add('')
    }
    $lines.AddRange($block)
  }

  if (-not $WhatIf) {
    Write-Utf8Lines $ConfigPath $lines.ToArray()
  }
}

function Set-TomlKeyInTable {
  param(
    [string]$ConfigPath,
    [string]$Header,
    [string]$Key,
    $Value
  )

  $lines = [System.Collections.Generic.List[string]]::new()
  foreach ($line in (Read-Utf8Lines $ConfigPath)) {
    $lines.Add($line)
  }

  $start = -1
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i].Trim() -eq $Header) {
      $start = $i
      break
    }
  }

  if ($start -lt 0) {
    if ($lines.Count -gt 0 -and $lines[$lines.Count - 1].Trim() -ne '') {
      $lines.Add('')
    }
    $lines.Add($Header)
    $lines.Add("$Key = $(Format-TomlValue $Value)")
    $lines.Add('')
    if (-not $WhatIf) {
      Write-Utf8Lines $ConfigPath $lines.ToArray()
    }
    return
  }

  $end = $start + 1
  while ($end -lt $lines.Count -and -not $lines[$end].TrimStart().StartsWith('[')) {
    $end++
  }

  $found = $false
  for ($i = $start + 1; $i -lt $end; $i++) {
    if ($lines[$i] -match "^\s*$([regex]::Escape($Key))\s*=") {
      $lines[$i] = "$Key = $(Format-TomlValue $Value)"
      $found = $true
      break
    }
  }
  if (-not $found) {
    $lines.Insert($end, "$Key = $(Format-TomlValue $Value)")
  }

  if (-not $WhatIf) {
    Write-Utf8Lines $ConfigPath $lines.ToArray()
  }
}

function Set-TopLevelNotify {
  param(
    [string]$ConfigPath,
    [string]$HelperExe
  )

  $lines = [System.Collections.Generic.List[string]]::new()
  foreach ($line in (Read-Utf8Lines $ConfigPath)) {
    $lines.Add($line)
  }

  $escaped = $HelperExe.Replace('\', '\\')
  $notifyLine = "notify = [ ""$escaped"", ""turn-ended"" ]"

  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i].TrimStart().StartsWith('[')) {
      $lines.Insert($i, $notifyLine)
      if (-not $WhatIf) { Write-Utf8Lines $ConfigPath $lines.ToArray() }
      return
    }
    if ($lines[$i] -match '^\s*notify\s*=') {
      $lines[$i] = $notifyLine
      if (-not $WhatIf) { Write-Utf8Lines $ConfigPath $lines.ToArray() }
      return
    }
  }

  $lines.Add($notifyLine)
  if (-not $WhatIf) {
    Write-Utf8Lines $ConfigPath $lines.ToArray()
  }
}

function Copy-Tree {
  param(
    [string]$Source,
    [string]$Destination
  )
  if ($WhatIf) {
    Write-Step "would copy $Source -> $Destination"
    return
  }
  New-Item -ItemType Directory -Force -Path $Destination | Out-Null
  $output = & robocopy $Source $Destination /E /R:0 /W:0 /NFL /NDL /NP 2>&1
  foreach ($line in $output) {
    if ([string]$line) { Write-Host $line }
  }
  if ($LASTEXITCODE -ge 8) {
    throw "robocopy failed with exit code $LASTEXITCODE"
  }
}

function Set-LatestJunction {
  param(
    [string]$LatestPath,
    [string]$TargetPath
  )
  if ($WhatIf) {
    Write-Step "would point latest junction $LatestPath -> $TargetPath"
    return
  }
  if (Test-Path -LiteralPath $LatestPath) {
    $item = Get-Item -LiteralPath $LatestPath -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
      [System.IO.Directory]::Delete($LatestPath, $false)
    } else {
      $backup = "$LatestPath.backup-" + (Get-Date -Format 'yyyyMMdd-HHmmss')
      Rename-Item -LiteralPath $LatestPath -NewName (Split-Path -Leaf $backup)
    }
  }
  New-Item -ItemType Junction -Path $LatestPath -Target $TargetPath | Out-Null
}

function Find-ComputerUseHelper {
  param([string]$StableMarketplaceRoot)

  $computerUseRoot = Join-Path $StableMarketplaceRoot 'plugins\computer-use'
  $candidate = Join-Path $computerUseRoot 'node_modules\@oai\sky\bin\windows\codex-computer-use.exe'

  $helper = Get-ChildItem -LiteralPath $computerUseRoot -Recurse -Force -Filter 'codex-computer-use.exe' -ErrorAction SilentlyContinue |
    Select-Object -First 1
  if ($helper) {
    return $helper.FullName
  }

  # Some WindowsApps/pnpm-style plugin trees are launchable but unreliable with
  # Test-Path/Get-ChildItem. Keep the conventional helper path as a best-effort
  # notify value; the Desktop app will still validate it at startup.
  return $candidate
}

function Test-RepairedState {
  param(
    [string]$CodexHome,
    [string]$StableMarketplaceRoot
  )
  $required = @(
    (Join-Path $StableMarketplaceRoot '.agents\plugins\marketplace.json'),
    (Join-Path $StableMarketplaceRoot 'plugins\computer-use\.codex-plugin\plugin.json'),
    (Join-Path $StableMarketplaceRoot 'plugins\computer-use\scripts\computer-use-client.mjs')
  )
  foreach ($path in $required) {
    if (-not (Test-Path -LiteralPath $path)) {
      return $false
    }
  }

  $configPath = Join-Path $CodexHome 'config.toml'
  if (-not (Test-Path -LiteralPath $configPath)) {
    return $false
  }
  $config = [System.IO.File]::ReadAllText($configPath, [System.Text.UTF8Encoding]::new($false))
  if ($config -notmatch [regex]::Escape('marketplaces\openai-bundled')) {
    return $false
  }
  if ($config -notmatch '(?ms)^\[plugins\."computer-use@openai-bundled"\]\s*\r?\n(?:(?!^\[).)*enabled\s*=\s*true') {
    return $false
  }

  return $true
}

if ([Environment]::OSVersion.Platform -ne 'Win32NT') {
  throw 'This repair script is for Windows only.'
}

$codexHome = Get-CodexHome
$stableMarketplace = Join-Path $codexHome 'marketplaces\openai-bundled'
$cacheRoot = Join-Path $codexHome 'plugins\cache\openai-bundled'
$configPath = Join-Path $codexHome 'config.toml'
$installedMarketplace = Get-InstalledBundledMarketplace

if (-not $Force -and (Test-RepairedState $codexHome $stableMarketplace)) {
  Write-Step 'state already looks repaired; use -Force to refresh files anyway'
  exit 0
}

Write-Step "Codex home: $codexHome"
Write-Step "installed bundled marketplace: $installedMarketplace"
Write-Step "stable bundled marketplace: $stableMarketplace"

Copy-Tree $installedMarketplace $stableMarketplace

$pluginsRoot = Join-Path $stableMarketplace 'plugins'
foreach ($pluginDir in Get-ChildItem -LiteralPath $pluginsRoot -Directory) {
  $pluginJson = Join-Path $pluginDir.FullName '.codex-plugin\plugin.json'
  if (-not (Test-Path -LiteralPath $pluginJson)) {
    continue
  }
  $plugin = Get-Content -LiteralPath $pluginJson -Raw | ConvertFrom-Json
  $pluginName = [string]$plugin.name
  $version = [string]$plugin.version
  if (-not $pluginName -or -not $version) {
    continue
  }

  $versionDest = Join-Path (Join-Path $cacheRoot $pluginName) $version
  Copy-Tree $pluginDir.FullName $versionDest
  Set-LatestJunction (Join-Path (Join-Path $cacheRoot $pluginName) 'latest') $versionDest
  Write-Step "cached $pluginName@$version"
}

if ((Test-Path -LiteralPath $configPath) -and -not $WhatIf) {
  $backupPath = "$configPath.before-computer-use-repair-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.bak'
  Copy-Item -LiteralPath $configPath -Destination $backupPath -Force
  Write-Step "backed up config.toml to $backupPath"
}

if (-not (Test-Path -LiteralPath $configPath) -and -not $WhatIf) {
  New-Item -ItemType File -Force -Path $configPath | Out-Null
}

Set-TomlTable $configPath '[marketplaces.openai-bundled]' ([ordered]@{
  source = '\\?\' + $stableMarketplace
  last_updated = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
  source_type = 'local'
})

foreach ($pluginName in @('computer-use', 'latex', 'browser', 'chrome', 'sites')) {
  Set-TomlTable $configPath "[plugins.""$pluginName@openai-bundled""]" ([ordered]@{
    enabled = $true
  })
}

Set-TomlKeyInTable $configPath '[features]' 'computer_use' $true
Set-TomlKeyInTable $configPath '[windows]' 'sandbox' 'unelevated'

$helperExe = Find-ComputerUseHelper $stableMarketplace
if ($helperExe) {
  Set-TopLevelNotify $configPath $helperExe
}

if (-not $WhatIf) {
  [Environment]::SetEnvironmentVariable('CODEX_ELECTRON_ENABLE_WINDOWS_COMPUTER_USE', '1', 'User')
  $env:CODEX_ELECTRON_ENABLE_WINDOWS_COMPUTER_USE = '1'
}

if (-not (Test-RepairedState $codexHome $stableMarketplace)) {
  throw 'repair finished, but required Computer Use files or config entries are still missing'
}

Write-Step 'repair complete'
Write-Step 'fully quit and reopen Codex Desktop; create a new conversation if Computer Use is not injected into the current one'
