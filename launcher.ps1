# Tesla SS Tools - remote one-command launcher for the isolated startup prototype

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$runId = [Guid]::NewGuid().ToString('N')
$zipPath = Join-Path ([IO.Path]::GetTempPath()) ("TeslaStartup-$runId.zip")
$extractRoot = Join-Path ([IO.Path]::GetTempPath()) ("TeslaStartup-$runId")
$packageUrl = 'https://raw.githubusercontent.com/TeslaPros/TeslaUpdateTesting/refs/heads/main/TeslaStartupAnimationTest.zip'

try {
    New-Item -Path $extractRoot -ItemType Directory -Force | Out-Null
    Invoke-WebRequest -UseBasicParsing -Uri $packageUrl -OutFile $zipPath
    Expand-Archive -LiteralPath $zipPath -DestinationPath $extractRoot -Force

    $prototypePath = Join-Path $extractRoot 'TeslaStartupAnimationTest\TeslaStartupTest.ps1'
    if (-not (Test-Path -LiteralPath $prototypePath -PathType Leaf)) {
        throw 'TeslaStartupTest.ps1 was not found in the downloaded package.'
    }

    & $prototypePath
}
catch {
    try {
        Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
        [System.Windows.MessageBox]::Show(
            "Tesla SS Tools could not start the animation.`r`n`r`n$($_.Exception.Message)",
            'Tesla SS Tools - Launcher error',
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        ) | Out-Null
    }
    catch {
        Write-Error $_.Exception.Message
    }
    exit 1
}
finally {
    if (Test-Path -LiteralPath $zipPath) {
        Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $extractRoot) {
        Remove-Item -LiteralPath $extractRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
