# Run with either Windows PowerShell 5.1 or PowerShell 7 (including on macOS).
$ErrorActionPreference = 'Stop'
$installer = Join-Path (Split-Path $PSScriptRoot -Parent) 'setup-python-windows.ps1'
if (-not (Test-Path $installer)) { throw 'Windows installer must exist' }
. $installer
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("python selector ' " + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($testRoot)
$script:passed = 0
function Assert-True($Value, [string]$Message) { if (-not $Value) { throw $Message } }
function Test-Case([string]$Name, [scriptblock]$Body) {
    & $Body
    $script:passed++
    Write-Host "PASS $Name"
}
function Assert-Throws([scriptblock]$Body) {
    $thrown = $false
    try { & $Body } catch { $thrown = $true }
    Assert-True $thrown 'Expected a terminating error'
}
try {
    Test-Case 'exact version input' {
        foreach ($value in @('3.11.1','3.13.12','3.9.0')) { Assert-PythonVersion $value }
        foreach ($value in @('3.1.1','3.11','latest','3.11.1;id','03.11.1','3.11.01','2.7.18','3.14.0rc1','','3.999.999')) {
            Assert-Throws { Assert-PythonVersion $value }
        }
    }
    Test-Case 'PATH precedence, case and trailing slash deduplication' {
        $value = Get-SelectedPath 'C:\Selected\bin' 'C:\Other;C:\SELECTED\bin\;C:\Windows;;C:\Other'
        Assert-True ($value -ceq 'C:\Selected\bin;C:\Other;C:\Windows;C:\Other') $value
    }
    Test-Case 'profile text preserved and one block moved to end' {
        $path = Join-Path $testRoot 'profile.ps1'
        [IO.File]::WriteAllText($path, "# keep café`r`n", [Text.UnicodeEncoding]::new($false,$true))
        Set-ManagedProfile $path 'Write-Output first'
        [IO.File]::AppendAllText($path, "Write-Output later`r`n", [Text.UnicodeEncoding]::new($false,$true))
        Set-ManagedProfile $path 'Write-Output second'
        $text = [IO.File]::ReadAllText($path)
        Assert-True ($text.Contains('café')) 'Unicode lost'
        Assert-True (-not $text.Contains('Write-Output first')) 'Old block retained'
        Assert-True (([regex]::Matches($text, '# >>> PythonSelector >>>')).Count -eq 1) 'Duplicate blocks'
        Assert-True ($text.IndexOf('Write-Output second') -gt $text.IndexOf('Write-Output later')) 'Block must be last'
        $bytes = [IO.File]::ReadAllBytes($path)
        Assert-True ($bytes[0] -eq 255 -and $bytes[1] -eq 254) 'UTF16 BOM changed'
    }
    Test-Case 'malformed block fails without changing bytes' {
        foreach ($text in @("# >>> PythonSelector >>>`nunfinished", "# <<< PythonSelector <<<`n", "# >>> PythonSelector >>>`n# >>> PythonSelector >>>`n# <<< PythonSelector <<<`n")) {
            $path = Join-Path $testRoot 'broken.ps1'
            [IO.File]::WriteAllText($path,$text)
            Assert-Throws { Set-ManagedProfile $path 'new' }
            Assert-True ([IO.File]::ReadAllText($path) -ceq $text) 'Malformed profile changed'
        }
    }
    Test-Case 'invalid UTF8 BOM-less profile is refused without corrupting bytes' {
        $path = Join-Path $testRoot 'ansi.ps1'
        $original = [byte[]]@(35,32,99,97,102,233,13,10)
        [IO.File]::WriteAllBytes($path,$original)
        Assert-Throws { Set-ManagedProfile $path 'new' }
        Assert-True (([Convert]::ToBase64String([IO.File]::ReadAllBytes($path))) -eq [Convert]::ToBase64String($original)) 'ANSI bytes changed'
    }
    Test-Case 'activation removes aliases/functions, quotes paths, clears contamination and deduplicates' {
        $path = Join-Path $testRoot 'activate.ps1'
        $bin = Join-Path $testRoot 'current/bin'
        [IO.File]::WriteAllText($path, (Get-ActivationText $bin))
        $beforePath = $env:PATH
        try {
            Set-Alias python Write-Output
            function global:python3 { 'wrong' }
            $env:PYTHONHOME = '/bad'
            $env:VIRTUAL_ENV = '/bad'
            . $path
            . $path
            Assert-True (-not (Test-Path Alias:python)) 'Alias survived'
            Assert-True (-not (Test-Path Function:python3)) 'Function survived'
            Assert-True (-not $env:PYTHONHOME) 'PYTHONHOME survived'
            Assert-True (-not $env:VIRTUAL_ENV) 'Virtualenv survived'
            Assert-True ($env:PATH.StartsWith($bin + ';')) 'PATH not prepended'
            Assert-True (@($env:PATH -split ';' | Where-Object { $_ -ceq $bin }).Count -eq 1) 'Duplicate bin'
        } finally { $env:PATH = $beforePath }
    }
    Test-Case 'architecture mapping' {
        Assert-True ((Get-UvPlatform 'AMD64') -eq 'x86_64') 'AMD64 mismatch'
        Assert-True ((Get-UvPlatform 'ARM64') -eq 'aarch64') 'ARM64 mismatch'
        Assert-True ((Get-UvPlatform 'x86') -eq 'i686') 'x86 mismatch'
        Assert-Throws { Get-UvPlatform 'unknown' }
    }
    Test-Case 'corrupted bootstrap rejected' {
        $file = Join-Path $testRoot 'bad.zip'
        [IO.File]::WriteAllText($file, 'corrupt archive')
        Assert-Throws { Assert-DownloadHash $file ('0' * 64) }
    }
    Test-Case 'environment isolation restores inherited values after failure' {
        $env:UV_OFFLINE = '1'
        $env:UV_PYTHON_INSTALL_MIRROR = 'https://invalid.example'
        $env:PYTHONHOME = '/bad'
        Assert-Throws {
            Invoke-CleanEnvironment {
                Assert-True (-not $env:UV_OFFLINE) 'UV_OFFLINE leaked'
                Assert-True (-not $env:UV_PYTHON_INSTALL_MIRROR) 'mirror leaked'
                Assert-True (-not $env:PYTHONHOME) 'PYTHONHOME leaked'
                throw 'synthetic failure'
            }
        }
        Assert-True ($env:UV_OFFLINE -eq '1') 'UV_OFFLINE not restored'
        Assert-True ($env:PYTHONHOME -eq '/bad') 'PYTHONHOME not restored'
        Remove-Item Env:UV_OFFLINE,Env:UV_PYTHON_INSTALL_MIRROR,Env:PYTHONHOME
    }
    Test-Case 'backup restores original files and removes new ones' {
        $folder = Join-Path $testRoot 'backup'
        [void][IO.Directory]::CreateDirectory($folder)
        $old = Join-Path $testRoot 'old.txt'
        $new = Join-Path $testRoot 'new.txt'
        [IO.File]::WriteAllText($old, 'original')
        $items = @((Save-ConfigFile $old $folder 0), (Save-ConfigFile $new $folder 1))
        [IO.File]::WriteAllText($old, 'modified')
        [IO.File]::WriteAllText($new, 'created')
        Restore-ConfigFiles $items
        Assert-True ([IO.File]::ReadAllText($old) -eq 'original') 'Old file not restored'
        Assert-True (-not (Test-Path $new)) 'New file not removed'
    }
    Write-Host "$script:passed PowerShell tests passed."
} finally {
    Remove-Item -LiteralPath $testRoot -Recurse -Force
}
