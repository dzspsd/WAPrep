# Native Windows only. Persistent mode is allowed only in disposable CI VMs.
param([switch]$MachineConfiguration)
$ErrorActionPreference = 'Stop'
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'Windows required' }
if ($MachineConfiguration -and $env:GITHUB_ACTIONS -ne 'true') { throw 'Machine tests are restricted to disposable GitHub Actions runners.' }
$installer = Join-Path (Split-Path $PSScriptRoot -Parent) 'setup-python-windows.ps1'
$hostExe = (Get-Process -Id $PID).Path
$base = Join-Path ([IO.Path]::GetTempPath()) ("PythonSelector space's " + [guid]::NewGuid().ToString('N'))
$root = Join-Path $base 'managed'
$script:checks = 0
[void][IO.Directory]::CreateDirectory($base)
function Assert-True($Value,[string]$Message) { if (-not $Value) { throw $Message } }
function Pass([string]$Name) { $script:checks++; Write-Host "PASS $Name" }
function Install-Python([string]$Value,[switch]$ExpectFailure) {
    & $hostExe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $installer -Version $Value -Isolated -InstallRoot $root
    $code = $LASTEXITCODE
    if ($ExpectFailure) { Assert-True ($code -ne 0) 'Expected install failure' }
    else { Assert-True ($code -eq 0) "Install failed with $code" }
}
function Read-Selection { Get-Content -LiteralPath (Join-Path $root 'selection.json') -Raw | ConvertFrom-Json }
function Verify-Python([string]$Value) {
    $selected = Read-Selection
    Assert-True ($selected.version -eq $Value) 'Selection mismatch'
    $activation = Join-Path $root 'activate.ps1'
    . $activation
    foreach ($name in @('python','python3')) {
        $output = & $name -c 'import platform,ssl,sqlite3; print(platform.python_version())'
        Assert-True ($LASTEXITCODE -eq 0 -and $output -eq $Value) "$name mismatch: $output"
    }
    foreach ($name in @('pip','pip3')) {
        & $name --version
        Assert-True ($LASTEXITCODE -eq 0) "$name failed"
    }
    $venv = Join-Path $base ('venv-' + [guid]::NewGuid().ToString('N'))
    & python -m venv $venv
    Assert-True ($LASTEXITCODE -eq 0) 'venv creation failed'
    $output = & (Join-Path $venv 'Scripts\python.exe') -c 'import platform;print(platform.python_version())'
    Assert-True ($LASTEXITCODE -eq 0 -and $output -eq $Value) 'venv version mismatch'
    & (Join-Path $venv 'Scripts\python.exe') -m pip --version
    Assert-True ($LASTEXITCODE -eq 0) 'venv pip failed'
    Remove-Item -LiteralPath $venv -Recurse -Force
    $cmdResult = & $env:ComSpec /d /c 'python --version && python3 --version && pip --version && pip3 --version'
    Assert-True ($LASTEXITCODE -eq 0 -and ($cmdResult -join "`n").Contains("Python $Value")) 'cmd.exe command selection failed'
}
$originalPath = $env:PATH
$originalMachinePath = [Environment]::GetEnvironmentVariable('Path','Machine')
$originalUserPath = [Environment]::GetEnvironmentVariable('Path','User')
try {
    Install-Python '3.11.1'
    Verify-Python '3.11.1'
    Pass 'clean install, PowerShell/cmd commands, pip, venv, path spaces and apostrophe'
    Assert-True ([Environment]::GetEnvironmentVariable('Path','Machine') -eq $originalMachinePath) 'Isolated mode modified machine PATH'
    Assert-True ([Environment]::GetEnvironmentVariable('Path','User') -eq $originalUserPath) 'Isolated mode modified user PATH'
    Pass 'isolated install leaves persistent PATH untouched'
    $python = (Read-Selection).python
    $modified = (Get-Item -LiteralPath $python).LastWriteTimeUtc
    Install-Python '3.11.1'
    Assert-True ((Get-Item -LiteralPath $python).LastWriteTimeUtc -eq $modified) 'Healthy runtime was needlessly reinstalled'
    Verify-Python '3.11.1'
    Pass 'idempotent repeat run reuses interpreter'
    Install-Python '3.11.9'
    Verify-Python '3.11.9'
    Install-Python '3.11.1'
    Verify-Python '3.11.1'
    Pass 'upgrade then exact downgrade'
    $env:UV_OFFLINE='1'; $env:UV_PYTHON_INSTALL_DIR='C:\bad'; $env:UV_PYTHON_INSTALL_MIRROR='https://invalid.example'
    $env:PYTHONHOME='C:\bad'; $env:PYTHONPATH='C:\bad'; $env:VIRTUAL_ENV='C:\bad'; $env:CONDA_PREFIX='C:\bad'
    Install-Python '3.11.1'
    Remove-Item Env:UV_OFFLINE,Env:UV_PYTHON_INSTALL_DIR,Env:UV_PYTHON_INSTALL_MIRROR,Env:PYTHONHOME,Env:PYTHONPATH,Env:VIRTUAL_ENV,Env:CONDA_PREFIX
    Verify-Python '3.11.1'
    Pass 'inherited uv, Python and virtual environment settings cannot redirect installation'
    $before = Get-Content -LiteralPath (Join-Path $root 'selection.json') -Raw
    Install-Python '3.99.99' -ExpectFailure
    Assert-True ((Get-Content -LiteralPath (Join-Path $root 'selection.json') -Raw) -ceq $before) 'Unavailable release changed defaults'
    Pass 'unavailable version preserves selection'
    $lock = [IO.File]::Open((Join-Path $root '.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    try { Install-Python '3.11.1' -ExpectFailure } finally { $lock.Dispose() }
    Pass 'concurrent run refused'
    $python = (Read-Selection).python
    Remove-Item -LiteralPath $python -Force
    Install-Python '3.11.1'
    Verify-Python '3.11.1'
    Pass 'missing interpreter repaired'
    $python = (Read-Selection).python
    $pipModule = & $python -c 'import pip,os;print(os.path.dirname(pip.__file__))'
    Remove-Item -LiteralPath $pipModule -Recurse -Force
    Install-Python '3.11.1'
    Verify-Python '3.11.1'
    Pass 'missing pip recovered under native PowerShell'
    if ($MachineConfiguration) {
        foreach ($version in @('3.11.9','3.11.1','3.11.1')) {
            & $hostExe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $installer -Version $version -NoElevate
            Assert-True ($LASTEXITCODE -eq 0) 'Machine installation failed'
            $machine = [Environment]::GetEnvironmentVariable('Path','Machine')
            Assert-True (($machine -split ';')[0] -like "*cpython-$version-*") 'Machine PATH does not prefer exact selected version'
            Assert-True (($machine -split ';')[1] -like '*\Scripts') 'Repeat run lost Scripts PATH entry'
            $env:PATH = $machine + ';' + [Environment]::GetEnvironmentVariable('Path','User')
            $output = & $env:ComSpec /d /c 'python --version'
            Assert-True ($LASTEXITCODE -eq 0 -and $output -eq "Python $version") 'Fresh cmd default is wrong'
            $output = & $hostExe -NoLogo -ExecutionPolicy Bypass -Command 'python -c "import platform; print(platform.python_version())"'
            Assert-True ($LASTEXITCODE -eq 0 -and $output[-1] -ne $null -and ($output -join "`n").Contains($version)) 'Fresh PowerShell default is wrong'
        }
        Pass 'machine PATH, current-user profiles, fresh shells and downgrade/repeat install'
    }
    Write-Host "$script:checks native Windows integration checks passed."
} finally {
    $env:PATH = $originalPath
    if (Test-Path -LiteralPath $base) { Remove-Item -LiteralPath $base -Recurse -Force }
}
