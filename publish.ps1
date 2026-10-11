param(
    [Parameter(Mandatory)]
    [ValidateSet('Debug','Release')]
    [System.String]$Target,
    
    [Parameter(Mandatory)]
    [System.String]$TargetPath,
    
    [Parameter(Mandatory)]
    [System.String]$TargetAssembly,

    [Parameter(Mandatory)]
    [System.String]$ValheimPath,

    [Parameter(Mandatory)]
    [System.String]$ProjectPath,
    
    [System.String]$DeployPath
)

# Make sure Get-Location is the script path
$ErrorActionPreference = 'Stop'
Push-Location -Path (Split-Path -Parent $MyInvocation.MyCommand.Path)
try {

# Test some preliminaries
("$TargetPath",
 "$ValheimPath",
 "$(Get-Location)\libraries"
) | % {
    if (!(Test-Path "$_")) {Write-Error -ErrorAction Stop -Message "$_ folder is missing"}
}

# Plugin name without ".dll"
$name = [System.IO.Path]::GetFileNameWithoutExtension($TargetAssembly)

# Create the mdb file
$pdb = "$TargetPath\$name.pdb"
if ($Target.Equals('Debug') -and (Test-Path -LiteralPath $pdb)) {
    $pdbStream = [System.IO.File]::OpenRead($pdb)
    try {
        $header = New-Object byte[] 4
        $read = $pdbStream.Read($header, 0, $header.Length)
        $portablePdb = ($read -eq 4 -and [System.BitConverter]::ToString($header) -eq '42-53-4A-42')
    } finally { $pdbStream.Dispose() }
    $converter = Join-Path (Get-Location).Path 'libraries\Debug\pdb2mdb.exe'
    if (-not $portablePdb -and (Test-Path -LiteralPath $converter)) {
        Write-Host "Create mdb file for plugin $name"
        & $converter (Join-Path $TargetPath $TargetAssembly)
        if ($LASTEXITCODE -ne 0) { throw 'Debug symbol conversion failed' }
    }
}

# Main Script
Write-Host "Publishing for $Target from $TargetPath"

if ($Target.Equals("Debug")) {
    if ($DeployPath.Equals("")){
      $DeployPath = "$ValheimPath\BepInEx\plugins"
    }
    
    $plug = New-Item -Type Directory -Path "$DeployPath\HappyDragoon-$name" -Force
    Write-Host "Copy $TargetAssembly to $plug"
    Copy-Item -LiteralPath (Join-Path $TargetPath $TargetAssembly) -Destination $plug.FullName -Force
    foreach ($symbol in @("$name.pdb", "$name.dll.mdb")) {
        $symbolPath = Join-Path $TargetPath $symbol
        if (Test-Path -LiteralPath $symbolPath) { Copy-Item -LiteralPath $symbolPath -Destination $plug.FullName -Force }
    }
    Copy-Item -Path "$ProjectPath\Assets\*" -Destination $plug.FullName -Recurse -Force
}

if($Target.Equals("Release")) {
    Write-Host "Packaging for ThunderStore..."
    $Package="Package"
    $PackagePath="$ProjectPath\$Package"

    Write-Host "$PackagePath\$TargetAssembly"
    $null = New-Item -Type Directory -Path "$PackagePath\plugins" -Force
    Copy-Item -Path "$TargetPath\$TargetAssembly" -Destination "$PackagePath\plugins\HappyDragoon-$TargetAssembly" -Force
    Copy-Item -Path "$ProjectPath\Assets\*" -Destination "$PackagePath\plugins" -Recurse -Force
    if (Test-Path -LiteralPath "$ProjectPath\README.md") {
        Copy-Item -LiteralPath "$ProjectPath\README.md" -Destination "$PackagePath\README.md" -Force
    }
    Compress-Archive -Path "$PackagePath\*" -DestinationPath "$TargetPath\$TargetAssembly.zip" -Force
}

# Pop Location
} finally { Pop-Location }
