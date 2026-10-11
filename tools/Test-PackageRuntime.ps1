param([string]$BuiltDll)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$sourceProject = Join-Path $root 'DragoonCapes'
$testRoot = Join-Path $root ('bin\PackageRegression\' + [Guid]::NewGuid().ToString('N'))
$project = Join-Path $testRoot 'Project With Spaces'
$output = Join-Path $testRoot 'Output'
$game = Join-Path $testRoot 'OwnedGame'
$deploy = Join-Path $testRoot 'OwnedPlugins'
$null = New-Item -ItemType Directory -Path $project,$output,$game,$deploy -Force
Copy-Item -LiteralPath (Join-Path $sourceProject 'Assets') -Destination $project -Recurse
$package = Join-Path $project 'Package'
$null = New-Item -ItemType Directory -Path $package
[IO.File]::WriteAllText((Join-Path $package 'README.md'),'Owned package metadata')
[IO.File]::WriteAllText((Join-Path $package 'manifest.json'),'{"name":"OwnedFixture","version_number":"1.0.0"}')
$dll = Join-Path $output 'DragoonCapes.dll'
if ($BuiltDll) {
    Copy-Item -LiteralPath $BuiltDll -Destination $dll
    $builtPdb = [IO.Path]::ChangeExtension($BuiltDll,'.pdb')
    if (Test-Path -LiteralPath $builtPdb) { Copy-Item -LiteralPath $builtPdb -Destination ([IO.Path]::ChangeExtension($dll,'.pdb')) }
} else { [IO.File]::WriteAllBytes($dll,[byte[]](1,2,3,4)) }
$script:checks = 0
function Assert-Case([bool]$condition,[string]$name) {
    if (-not $condition) { throw "FAIL: $name" }
    $script:checks++
}
$publisher = Join-Path $root 'publish.ps1'
$before = (Get-Location).Path
& $publisher -Target Release -TargetPath $output -TargetAssembly 'DragoonCapes.dll' -ValheimPath $game -ProjectPath $project -DeployPath $deploy
Assert-Case ((Get-Location).Path -eq $before) 'Release restores caller location'
Assert-Case ((Get-Content -LiteralPath (Join-Path $package 'README.md') -Raw) -eq 'Owned package metadata') 'Existing package README survives absent project README'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::OpenRead((Join-Path $output 'DragoonCapes.dll.zip'))
try {
    $entries = @($zip.Entries | ForEach-Object { $_.FullName.Replace('\','/') })
    Assert-Case ($entries -contains 'plugins/HappyDragoon-DragoonCapes.dll') 'Original DLL name and package path retained'
    $runtimeFiles = @(Get-ChildItem -LiteralPath (Join-Path $project 'Assets') -File -Recurse)
    foreach ($file in $runtimeFiles) {
        $relative = $file.FullName.Substring((Join-Path $project 'Assets').Length + 1).Replace('\','/')
        Assert-Case ($entries -contains ('plugins/' + $relative)) ('ZIP includes ' + $relative)
        $dest = Join-Path (Join-Path $package 'plugins') $relative
        Assert-Case ((Get-FileHash -LiteralPath $dest).Hash -eq (Get-FileHash -LiteralPath $file.FullName).Hash) ('Runtime hash matches ' + $relative)
    }
    Assert-Case ((@($entries | Where-Object { $_ -match '^plugins/Translations/[^/]+/[^/]+\.json$' })).Count -eq 4) 'All four translations packaged'
    Assert-Case (-not ($entries | Where-Object { $_ -match 'Assets/Assets/|Translations/Translations/' })) 'No duplicated runtime directory nesting'
} finally { $zip.Dispose() }
& $publisher -Target Debug -TargetPath $output -TargetAssembly 'DragoonCapes.dll' -ValheimPath $game -ProjectPath $project -DeployPath $deploy
$debugPlugin = Join-Path $deploy 'HappyDragoon-DragoonCapes'
foreach ($file in $runtimeFiles) {
    $relative = $file.FullName.Substring((Join-Path $project 'Assets').Length + 1)
    Assert-Case ((Get-FileHash -LiteralPath (Join-Path $debugPlugin $relative)).Hash -eq (Get-FileHash -LiteralPath $file.FullName).Hash) ('Debug runtime hash matches ' + $relative)
}
Assert-Case ((Get-FileHash -LiteralPath (Join-Path $debugPlugin 'DragoonCapes.dll')).Hash -eq (Get-FileHash -LiteralPath $dll).Hash) 'Debug DLL preserved'
if (Test-Path -LiteralPath ([IO.Path]::ChangeExtension($dll,'.pdb'))) {
    Assert-Case ((Get-FileHash -LiteralPath (Join-Path $debugPlugin 'DragoonCapes.pdb')).Hash -eq (Get-FileHash -LiteralPath ([IO.Path]::ChangeExtension($dll,'.pdb'))).Hash) 'Native portable PDB is preserved'
    Assert-Case (-not (Test-Path -LiteralPath (Join-Path $debugPlugin 'DragoonCapes.dll.mdb'))) 'Portable PDB does not invoke incompatible legacy MDB conversion'
}
Assert-Case ((Get-Location).Path -eq $before) 'Debug restores caller location'
& $publisher -Target Release -TargetPath $output -TargetAssembly 'DragoonCapes.dll' -ValheimPath $game -ProjectPath $project -DeployPath $deploy
$zip = [IO.Compression.ZipFile]::OpenRead((Join-Path $output 'DragoonCapes.dll.zip'))
try {
    $entries = @($zip.Entries | ForEach-Object { $_.FullName.Replace('\','/') })
    Assert-Case (-not ($entries | Where-Object { $_ -match 'Assets/Assets/|Translations/Translations/' })) 'Repeat packaging does not nest runtime folders'
    Assert-Case ((@($zip.Entries | Where-Object { $_.Name.Length -gt 0 })).Count -eq ($runtimeFiles.Count + 3)) 'Repeat packaging retains exactly DLL runtime files and owned metadata'
} finally { $zip.Dispose() }
$source = [IO.File]::ReadAllText((Join-Path $sourceProject 'DragoonCapes.cs'))
$first = $source.IndexOf('private string GetAssetPath(')
$last = $source.IndexOf('private void Awake()', $first)
if ($first -lt 0 -or $last -lt 0) { throw 'Runtime loading methods could not be extracted' }
$methods = $source.Substring($first,$last-$first).Replace('private string GetAssetPath(', 'public string GetAssetPath(').Replace('private void LoadTranslations()', 'public void LoadTranslations()')
$probeCode = @'
using System;
using System.IO;
using System.Collections.Generic;
public class PackageInfo { public string Location; }
public class LogRecorder { public List<string> Warnings = new List<string>(); public void LogWarning(string s) { Warnings.Add(s); } }
public class TranslationRecorder { public Dictionary<string,string> Files = new Dictionary<string,string>(); public void AddJsonFile(string language,string text) { Files.Add(language,text); } }
public class ActualLoadingMethods { public PackageInfo Info = new PackageInfo(); public LogRecorder Logger = new LogRecorder(); public TranslationRecorder Localization = new TranslationRecorder();
'@
Add-Type -TypeDefinition ($probeCode + $methods + '}')
$probe = New-Object ActualLoadingMethods
$probe.Info.Location = Join-Path (Join-Path $package 'plugins') 'HappyDragoon-DragoonCapes.dll'
$activeSource = [regex]::Replace($source, '(?m)^\s*//.*$', '')
foreach ($match in [regex]::Matches($activeSource, 'GetAssetPath\("([^"]+)"\)')) {
    $expected = Join-Path (Join-Path $package 'plugins\Assets') $match.Groups[1].Value
    Assert-Case ((Test-Path -LiteralPath $probe.GetAssetPath($match.Groups[1].Value)) -and $probe.GetAssetPath($match.Groups[1].Value) -eq $expected) ('Actual loader resolves ' + $match.Groups[1].Value)
}
$probe.LoadTranslations()
foreach ($language in @('English','French','Korean','Chinese')) {
    $expected = [IO.File]::ReadAllText((Join-Path (Join-Path $package 'plugins\Translations') ($language + '\' + $language + '.json')))
    Assert-Case ($probe.Localization.Files[$language] -eq $expected) ('Actual loader reads ' + $language + ' translation')
}
Assert-Case ($probe.Logger.Warnings.Count -eq 0) 'Complete package loads without missing-file warnings'
$flat = Join-Path $testRoot 'OwnedFlatLayout'
$null = New-Item -ItemType Directory -Path $flat
Copy-Item -LiteralPath (Join-Path $sourceProject 'Assets\Assets\neckIcon.png') -Destination $flat
Copy-Item -LiteralPath (Join-Path $sourceProject 'Assets\Translations\English\English.json') -Destination $flat
$flatProbe = New-Object ActualLoadingMethods
$flatProbe.Info.Location = Join-Path $flat 'DragoonCapes.dll'
Assert-Case ($flatProbe.GetAssetPath('neckIcon.png') -eq (Join-Path $flat 'neckIcon.png')) 'Actual loader retains flat asset fallback'
$flatProbe.LoadTranslations()
Assert-Case ($flatProbe.Localization.Files.Count -eq 1 -and $flatProbe.Localization.Files.ContainsKey('English')) 'Actual loader retains flat translation fallback'
Assert-Case ($flatProbe.Logger.Warnings.Count -eq 3) 'Missing translations warn without inventing content'
$missing = $flatProbe.GetAssetPath('missing.png')
Assert-Case ($missing -eq (Join-Path $flat 'Assets\missing.png') -and $flatProbe.Logger.Warnings.Count -eq 4) 'Missing asset retains warning and expected path'
try {
    & $publisher -Target Release -TargetPath $output -TargetAssembly 'Missing.dll' -ValheimPath $game -ProjectPath $project -DeployPath $deploy
    throw 'Missing assembly was accepted'
} catch {
    Assert-Case ($_.Exception.Message -ne 'Missing assembly was accepted') 'Missing assembly stops publishing'
}
Assert-Case ((Get-Location).Path -eq $before) 'Failed publication restores caller location'
[pscustomobject]@{ Checks=$script:checks; TestRoot=$testRoot; RuntimeFiles=$runtimeFiles.Count; BuiltDll=[bool]$BuiltDll; ActiveGameWrites=0 } | ConvertTo-Json
