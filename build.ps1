# Builds release\CA-Tool.exe from CATool.ps1.
# Needs nothing beyond Windows: uses the C# compiler that ships with .NET Framework 4
# and the PowerShell engine built into Windows. Run:
#   powershell -NoProfile -ExecutionPolicy Bypass -File build.ps1

$ErrorActionPreference = 'Stop'
$root   = $PSScriptRoot
$outDir = Join-Path $root 'release'
$work   = Join-Path $outDir 'build-temp'
New-Item -ItemType Directory -Path $work -Force | Out-Null

$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path $csc)) { $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe' }
$sma = [psobject].Assembly.Location   # System.Management.Automation.dll (Windows PowerShell 5.1)

$script  = Join-Path $root 'CATool.ps1'
$version = [regex]::Match((Get-Content $script -Raw), "\`$script:Version = '([\d.]+)'").Groups[1].Value
if (-not $version) { throw 'Could not find $script:Version in CATool.ps1' }

# --- Icon: two overlapping circles (C and A), drawn here so no image file is needed ---
Add-Type -AssemblyName System.Drawing
$ico = Join-Path $work 'CATool.ico'
$sizes = 256, 48, 32, 16
$pngs = foreach ($n in $sizes) {
    $bmp = New-Object System.Drawing.Bitmap $n, $n
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.Clear([System.Drawing.Color]::Transparent)
    $w = [math]::Max(1.5, $n / 14)
    $bg = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 32, 36, 44))
    $g.FillEllipse($bg, 0, 0, $n - 1, $n - 1)
    $penC = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 0, 229, 255)), $w
    $penA = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 255, 152, 0)), $w
    $g.DrawEllipse($penC, [single]($n * 0.14), [single]($n * 0.22), [single]($n * 0.48), [single]($n * 0.48))
    $g.DrawEllipse($penA, [single]($n * 0.42), [single]($n * 0.34), [single]($n * 0.40), [single]($n * 0.40))
    $g.Dispose()
    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    , $ms.ToArray()
}
$fs = [System.IO.File]::Create($ico)
$bw = New-Object System.IO.BinaryWriter $fs
$bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
    $n = $sizes[$i]; $d = if ($n -ge 256) { 0 } else { $n }
    $bw.Write([byte]$d); $bw.Write([byte]$d); $bw.Write([byte]0); $bw.Write([byte]0)
    $bw.Write([uint16]1); $bw.Write([uint16]32)
    $bw.Write([uint32]$pngs[$i].Length); $bw.Write([uint32]$offset)
    $offset += $pngs[$i].Length
}
foreach ($p in $pngs) { $bw.Write($p) }
$bw.Close()

# --- Compile ---
$cs = Join-Path $work 'Launcher.cs'
(Get-Content (Join-Path $root 'launcher\Launcher.cs') -Raw).Replace('{VERSION}', $version) |
    Set-Content -Path $cs -Encoding UTF8
$exe = Join-Path $outDir 'CA-Tool.exe'
& $csc /nologo /target:winexe /optimize+ "/out:$exe" "/win32icon:$ico" `
    "/resource:$script,CATool.ps1" "/reference:$sma" /reference:System.Windows.Forms.dll $cs
if ($LASTEXITCODE -ne 0) { throw "Compile failed (exit $LASTEXITCODE)" }

Remove-Item $work -Recurse -Force
"Built $exe (version $version)"
