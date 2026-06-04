# Generates a high-resolution 512x512 PNG using the same pipeline as generate-icon.ps1.
# Used for in-window icon display (better than scaling the 256px ICO frame).
Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = 'Stop'

$sourcePath = $env:IDLEPULSE_SOURCE
if (-not $sourcePath) { $sourcePath = "$env:USERPROFILE\Downloads\generated-image.png" }

$outPath = Join-Path $PSScriptRoot '..\Assets\IdlePulse-512.png'
$size = 512

# Build pulse mask (same as generate-icon.ps1)
$srcOriginal = [System.Drawing.Image]::FromFile($sourcePath)
$srcW = $srcOriginal.Width; $srcH = $srcOriginal.Height
$src = New-Object System.Drawing.Bitmap $srcW, $srcH, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$srcG = [System.Drawing.Graphics]::FromImage($src)
$srcG.DrawImage($srcOriginal, 0, 0, $srcW, $srcH)
$srcG.Dispose(); $srcOriginal.Dispose()

$mask = New-Object System.Drawing.Bitmap $srcW, $srcH, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$minX = $srcW; $minY = $srcH; $maxX = 0; $maxY = 0
for ($y = 0; $y -lt $srcH; $y++) {
    for ($x = 0; $x -lt $srcW; $x++) {
        $c = $src.GetPixel($x, $y)
        if (($c.R -lt 220) -or ($c.G -lt 220) -or ($c.B -lt 220)) {
            $brightness = ($c.R + $c.G + $c.B) / 765.0
            $a = [Math]::Max(0, [Math]::Min(255, [int][Math]::Round((1.0 - $brightness) * 255 * 1.4)))
            $mask.SetPixel($x, $y, [System.Drawing.Color]::FromArgb($a, 255, 255, 255))
            if ($x -lt $minX) { $minX = $x }
            if ($y -lt $minY) { $minY = $y }
            if ($x -gt $maxX) { $maxX = $x }
            if ($y -gt $maxY) { $maxY = $y }
        }
    }
}
$src.Dispose()

$cropPad = [int]([Math]::Min($srcW, $srcH) * 0.02)
$cropX = [Math]::Max(0, $minX - $cropPad); $cropY = [Math]::Max(0, $minY - $cropPad)
$cropW = [Math]::Min($srcW - $cropX, ($maxX - $minX + 1) + $cropPad * 2)
$cropH = [Math]::Min($srcH - $cropY, ($maxY - $minY + 1) + $cropPad * 2)
$cropped = New-Object System.Drawing.Bitmap $cropW, $cropH, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$cg = [System.Drawing.Graphics]::FromImage($cropped)
$cg.DrawImage($mask, (New-Object System.Drawing.Rectangle 0, 0, $cropW, $cropH), $cropX, $cropY, $cropW, $cropH, [System.Drawing.GraphicsUnit]::Pixel)
$cg.Dispose(); $mask.Dispose()

# Dilate alpha mask (same as generate-icon.ps1)
function Dilate-AlphaMask([System.Drawing.Bitmap]$bmp, [int]$radius) {
    if ($radius -le 0) { return $bmp }
    $w = $bmp.Width; $h = $bmp.Height
    $rect = New-Object System.Drawing.Rectangle 0, 0, $w, $h
    $fmt = [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
    $srcData = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, $fmt)
    $stride = $srcData.Stride; $byteCount = $stride * $h
    $bytes = New-Object byte[] $byteCount
    [System.Runtime.InteropServices.Marshal]::Copy($srcData.Scan0, $bytes, 0, $byteCount)
    $bmp.UnlockBits($srcData)
    $alpha = New-Object byte[] ($w * $h)
    for ($y = 0; $y -lt $h; $y++) {
        $sr = $y * $stride; $dr = $y * $w
        for ($x = 0; $x -lt $w; $x++) { $alpha[$dr + $x] = $bytes[$sr + $x * 4 + 3] }
    }
    $tmp = New-Object byte[] ($w * $h)
    for ($y = 0; $y -lt $h; $y++) {
        $row = $y * $w
        for ($x = 0; $x -lt $w; $x++) {
            $maxA = 0
            $x0 = [Math]::Max(0, $x - $radius); $x1 = [Math]::Min($w - 1, $x + $radius)
            for ($k = $x0; $k -le $x1; $k++) { $a = $alpha[$row + $k]; if ($a -gt $maxA) { $maxA = $a } }
            $tmp[$row + $x] = $maxA
        }
    }
    for ($x = 0; $x -lt $w; $x++) {
        for ($y = 0; $y -lt $h; $y++) {
            $maxA = 0
            $y0 = [Math]::Max(0, $y - $radius); $y1 = [Math]::Min($h - 1, $y + $radius)
            for ($k = $y0; $k -le $y1; $k++) { $a = $tmp[$k * $w + $x]; if ($a -gt $maxA) { $maxA = $a } }
            $alpha[$y * $w + $x] = $maxA
        }
    }
    $out = New-Object System.Drawing.Bitmap $w, $h, $fmt
    $outData = $out.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::WriteOnly, $fmt)
    $outBytes = New-Object byte[] $byteCount
    for ($y = 0; $y -lt $h; $y++) {
        $sr = $y * $w; $dr = $y * $stride
        for ($x = 0; $x -lt $w; $x++) {
            $a = $alpha[$sr + $x]; $i = $dr + $x * 4
            $outBytes[$i] = 255; $outBytes[$i + 1] = 255; $outBytes[$i + 2] = 255; $outBytes[$i + 3] = $a
        }
    }
    [System.Runtime.InteropServices.Marshal]::Copy($outBytes, 0, $outData.Scan0, $byteCount)
    $out.UnlockBits($outData); $bmp.Dispose()
    return $out
}
$dilateRadius = [int]([Math]::Round([Math]::Min($cropW, $cropH) * 0.012))
if ($dilateRadius -lt 2) { $dilateRadius = 2 }
$cropped = Dilate-AlphaMask $cropped $dilateRadius

# Render at native 512px (no upscaling)
$bmp = New-Object System.Drawing.Bitmap $size, $size, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$g.Clear([System.Drawing.Color]::Transparent)

$radius = [int]($size * 0.22)
$path = New-Object System.Drawing.Drawing2D.GraphicsPath
$path.AddArc(0, 0, $radius * 2, $radius * 2, 180, 90)
$path.AddArc($size - $radius * 2, 0, $radius * 2, $radius * 2, 270, 90)
$path.AddArc($size - $radius * 2, $size - $radius * 2, $radius * 2, $radius * 2, 0, 90)
$path.AddArc(0, $size - $radius * 2, $radius * 2, $radius * 2, 90, 90)
$path.CloseFigure()
$bgBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 0, 0, 0))
$g.FillPath($bgBrush, $path)

$margin = [int]([Math]::Max(2, $size * 0.10))
$availW = $size - $margin * 2; $availH = $size - $margin * 2
$scale = [Math]::Min($availW / $cropped.Width, $availH / $cropped.Height)
$drawW = [int][Math]::Round($cropped.Width * $scale)
$drawH = [int][Math]::Round($cropped.Height * $scale)
$offX = [int](($size - $drawW) / 2); $offY = [int](($size - $drawH) / 2)
$g.DrawImage($cropped, $offX, $offY, $drawW, $drawH)

$bmp.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose(); $bgBrush.Dispose(); $path.Dispose(); $cropped.Dispose()

Write-Host "Wrote $outPath"
