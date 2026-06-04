#requires -Version 5.1
# Generates IdlePulse-active.ico — same pulse shape but with accent blue background.
# Used as tray icon when the UI window is open.

Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = 'Stop'
$outDir = Join-Path $PSScriptRoot '..\Assets'
$null = New-Item -ItemType Directory -Path $outDir -Force

# Read the default icon script's pipeline output (the cropped+dilated mask)
# Actually simpler: copy generate-icon.ps1 logic but swap background color.

$srcPath = $env:IDLEPULSE_SOURCE
if (-not $srcPath -or -not (Test-Path $srcPath)) {
    $srcPath = Join-Path $env:USERPROFILE 'Downloads\generated-image.png'
}
if (-not (Test-Path $srcPath)) {
    Write-Error "Source PNG not found at $srcPath. Set `$env:IDLEPULSE_SOURCE."
    exit 1
}

$src = [System.Drawing.Image]::FromFile($srcPath)
$srcW = $src.Width
$srcH = $src.Height

# Build alpha mask from source (same logic as generate-icon.ps1)
$mask = New-Object System.Drawing.Bitmap $srcW, $srcH, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
for ($y = 0; $y -lt $srcH; $y++) {
    for ($x = 0; $x -lt $srcW; $x++) {
        $px = $src.GetPixel($x, $y)
        $brightness = ($px.R + $px.G + $px.B) / 3.0
        if ($brightness -lt 180) {
            $alpha = [Math]::Min(255, [int]((180 - $brightness) / 180.0 * 255 * 1.8))
            $mask.SetPixel($x, $y, [System.Drawing.Color]::FromArgb($alpha, 255, 255, 255))
        }
    }
}
$src.Dispose()

# Crop to bounding box
$minX = $srcW; $maxX = 0; $minY = $srcH; $maxY = 0
for ($y = 0; $y -lt $srcH; $y++) {
    for ($x = 0; $x -lt $srcW; $x++) {
        if ($mask.GetPixel($x, $y).A -gt 10) {
            if ($x -lt $minX) { $minX = $x }
            if ($x -gt $maxX) { $maxX = $x }
            if ($y -lt $minY) { $minY = $y }
            if ($y -gt $maxY) { $maxY = $y }
        }
    }
}
$cropX = [Math]::Max(0, $minX - 5)
$cropY = [Math]::Max(0, $minY - 5)
$cropW = [Math]::Min($srcW - $cropX, $maxX - $minX + 11)
$cropH = [Math]::Min($srcH - $cropY, $maxY - $minY + 11)

$cropped = New-Object System.Drawing.Bitmap $cropW, $cropH, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$cg = [System.Drawing.Graphics]::FromImage($cropped)
$cg.DrawImage($mask, (New-Object System.Drawing.Rectangle 0, 0, $cropW, $cropH),
    $cropX, $cropY, $cropW, $cropH, [System.Drawing.GraphicsUnit]::Pixel)
$cg.Dispose()
$mask.Dispose()

# Sizes for ICO
$sizes = @(16, 24, 32, 48, 64, 128, 256)

# Accent blue background color
$bgColor = [System.Drawing.Color]::FromArgb(255, 0, 120, 214)  # #0078D6 Windows accent

function New-IconFrame([int]$size) {
    $bmp = New-Object System.Drawing.Bitmap $size, $size, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.Clear([System.Drawing.Color]::Transparent)

    # Rounded square background (accent blue)
    $radius = [Math]::Max(2, [int]($size * 0.22))
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddArc(0, 0, $radius * 2, $radius * 2, 180, 90)
    $path.AddArc($size - $radius * 2, 0, $radius * 2, $radius * 2, 270, 90)
    $path.AddArc($size - $radius * 2, $size - $radius * 2, $radius * 2, $radius * 2, 0, 90)
    $path.AddArc(0, $size - $radius * 2, $radius * 2, $radius * 2, 90, 90)
    $path.CloseFigure()

    $bgBrush = New-Object System.Drawing.SolidBrush $bgColor
    $g.FillPath($bgBrush, $path)
    $bgBrush.Dispose()
    $path.Dispose()

    # Draw pulse mask scaled to fit with margin
    $margin = [int]($size * 0.10)
    $drawW = $size - $margin * 2
    $drawH = $size - $margin * 2
    $aspect = $cropW / [double]$cropH
    if ($aspect -gt 1) { $drawH = [int]($drawW / $aspect) } else { $drawW = [int]($drawH * $aspect) }
    $ox = [int](($size - $drawW) / 2)
    $oy = [int](($size - $drawH) / 2)
    $g.DrawImage($cropped, $ox, $oy, $drawW, $drawH)
    $g.Dispose()
    return $bmp
}

# Build ICO
$icoPath = Join-Path $outDir 'IdlePulse-active.ico'
$ms = New-Object System.IO.MemoryStream
$bw = New-Object System.IO.BinaryWriter $ms
$bw.Write([uint16]0)
$bw.Write([uint16]1)
$bw.Write([uint16]$sizes.Count)

$pngs = @()
foreach ($size in $sizes) {
    $bmp = New-IconFrame $size
    $pngStream = New-Object System.IO.MemoryStream
    $bmp.Save($pngStream, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    $pngs += , @{ Size = $size; Bytes = $pngStream.ToArray() }
    $pngStream.Dispose()
}

$dirSize = 6 + (16 * $sizes.Count)
$offset = $dirSize
foreach ($p in $pngs) {
    $w = if ($p.Size -ge 256) { 0 } else { [byte]$p.Size }
    $h = if ($p.Size -ge 256) { 0 } else { [byte]$p.Size }
    $bw.Write([byte]$w); $bw.Write([byte]$h)
    $bw.Write([byte]0); $bw.Write([byte]0)
    $bw.Write([uint16]1); $bw.Write([uint16]32)
    $bw.Write([uint32]$p.Bytes.Length)
    $bw.Write([uint32]$offset)
    $offset += $p.Bytes.Length
}
foreach ($p in $pngs) { $bw.Write($p.Bytes) }
$bw.Flush()
[System.IO.File]::WriteAllBytes($icoPath, $ms.ToArray())
$bw.Dispose(); $ms.Dispose(); $cropped.Dispose()

Write-Host "Wrote $icoPath ($((Get-Item $icoPath).Length) bytes, $($sizes.Count) sizes)"
