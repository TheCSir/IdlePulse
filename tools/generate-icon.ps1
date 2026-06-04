#requires -Version 5.1
# Generates IdlePulse multi-size .ico
# Design: black rounded-square, white stylized ECG pulse (3 minor blips, 1 large peak, 1 large valley, 1 minor blip).

Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = 'Stop'
$outDir = Join-Path $PSScriptRoot '..\Assets'
$null = New-Item -ItemType Directory -Path $outDir -Force
$icoPath = Join-Path $outDir 'IdlePulse.ico'

$sizes = @(16, 24, 32, 48, 64, 128, 256)

function New-IconBitmap([int]$size) {
    $bmp = New-Object System.Drawing.Bitmap $size, $size, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.Clear([System.Drawing.Color]::Transparent)

    # Rounded-square black background
    $radius = [Math]::Max(2, [int]($size * 0.22))
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddArc(0, 0, $radius * 2, $radius * 2, 180, 90)
    $path.AddArc($size - $radius * 2, 0, $radius * 2, $radius * 2, 270, 90)
    $path.AddArc($size - $radius * 2, $size - $radius * 2, $radius * 2, $radius * 2, 0, 90)
    $path.AddArc(0, $size - $radius * 2, $radius * 2, $radius * 2, 90, 90)
    $path.CloseFigure()

    $bgBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 0, 0, 0))
    $g.FillPath($bgBrush, $path)
    $bgBrush.Dispose()
    $path.Dispose()

    # ECG pulse path — normalized 0..1 then scaled to size
    # Reference points (x, y) where y=0 is bottom, y=1 is top (we'll invert for screen)
    $points = @(
        @(0.06, 0.50),   # left baseline start
        @(0.20, 0.50),
        @(0.24, 0.55),   # tiny blip up
        @(0.28, 0.45),   # tiny blip down
        @(0.32, 0.50),
        @(0.38, 0.50),
        @(0.44, 0.92),   # big peak up
        @(0.50, 0.08),   # big valley down
        @(0.56, 0.62),   # rebound up
        @(0.60, 0.42),   # blip down
        @(0.64, 0.50),
        @(0.80, 0.50),
        @(0.94, 0.50)    # right baseline end
    )

    # Padding so pulse doesn't hit edges
    $padX = $size * 0.10
    $padY = $size * 0.10
    $usable = $size - ($padY * 2)

    $screenPts = @()
    foreach ($p in $points) {
        $x = $padX + $p[0] * ($size - $padX * 2)
        $y = $padY + (1 - $p[1]) * $usable
        $screenPts += , (New-Object System.Drawing.PointF([float]$x, [float]$y))
    }

    # Stroke — thicker on larger sizes, with rounded caps
    $strokeWidth = [Math]::Max(1.5, $size * 0.07)
    $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::White, [float]$strokeWidth)
    $pen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
    $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round

    $g.DrawLines($pen, $screenPts)
    $pen.Dispose()
    $g.Dispose()
    return $bmp
}

# Build the ICO byte stream
$ms = New-Object System.IO.MemoryStream
$bw = New-Object System.IO.BinaryWriter $ms

# ICONDIR header
$bw.Write([uint16]0)
$bw.Write([uint16]1)
$bw.Write([uint16]$sizes.Count)

$pngs = @()
foreach ($size in $sizes) {
    $bmp = New-IconBitmap $size
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
    $bw.Write([byte]$w)
    $bw.Write([byte]$h)
    $bw.Write([byte]0)
    $bw.Write([byte]0)
    $bw.Write([uint16]1)
    $bw.Write([uint16]32)
    $bw.Write([uint32]$p.Bytes.Length)
    $bw.Write([uint32]$offset)
    $offset += $p.Bytes.Length
}

foreach ($p in $pngs) {
    $bw.Write($p.Bytes)
}

$bw.Flush()
[System.IO.File]::WriteAllBytes($icoPath, $ms.ToArray())
$bw.Dispose()
$ms.Dispose()

Write-Host "Wrote $icoPath ($((Get-Item $icoPath).Length) bytes, $($sizes.Count) sizes)"
