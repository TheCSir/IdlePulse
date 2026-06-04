#requires -Version 5.1
# Generates IdlePulse multi-size .ico
# Approach: load the brand source PNG, treat teal pulse pixels as "ink",
# render onto a black rounded-square background recolored as white. This
# guarantees a pixel-exact match to the source motif.

Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = 'Stop'
$scriptDir = $PSScriptRoot
$outDir = Join-Path $scriptDir '..\Assets'
$null = New-Item -ItemType Directory -Path $outDir -Force
$icoPath = Join-Path $outDir 'IdlePulse.ico'

# Locate the source brand image (allow override via $env:IDLEPULSE_SOURCE)
$sourcePath = $env:IDLEPULSE_SOURCE
if (-not $sourcePath) {
    $sourcePath = "$env:USERPROFILE\Downloads\generated-image.png"
}
if (-not (Test-Path $sourcePath)) {
    throw "Source image not found at $sourcePath. Set IDLEPULSE_SOURCE env var or place the file at that path."
}

$sizes = @(16, 24, 32, 48, 64, 128, 256)

# --- Load source and build a tightly-cropped white-on-transparent mask of the pulse ---

$srcOriginal = [System.Drawing.Image]::FromFile($sourcePath)
$srcW = $srcOriginal.Width
$srcH = $srcOriginal.Height

# Render the source to a 32bpp ARGB bitmap so we can sample pixels reliably
$src = New-Object System.Drawing.Bitmap $srcW, $srcH, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$srcG = [System.Drawing.Graphics]::FromImage($src)
$srcG.DrawImage($srcOriginal, 0, 0, $srcW, $srcH)
$srcG.Dispose()
$srcOriginal.Dispose()

# Detect pulse pixels: anything noticeably darker than the off-white background
# OR with significant teal saturation. We then write white to a transparent mask.
$mask = New-Object System.Drawing.Bitmap $srcW, $srcH, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$minX = $srcW; $minY = $srcH; $maxX = 0; $maxY = 0
$inkCount = 0

for ($y = 0; $y -lt $srcH; $y++) {
    for ($x = 0; $x -lt $srcW; $x++) {
        $c = $src.GetPixel($x, $y)
        # Background is near-white (~245+ on all channels). Anything meaningfully darker is ink.
        $isInk = ($c.R -lt 220) -or ($c.G -lt 220) -or ($c.B -lt 220)
        if ($isInk) {
            # Compute coverage: how dark vs white. Range ~0..1.
            $brightness = [Math]::Min(1.0, ($c.R + $c.G + $c.B) / (3.0 * 255.0))
            $coverage = 1.0 - $brightness
            $alpha = [int]([Math]::Min(255, [Math]::Round($coverage * 255 * 1.4)))  # boost slightly so anti-aliased edges read as solid
            $alpha = [Math]::Max(0, [Math]::Min(255, $alpha))
            $mask.SetPixel($x, $y, [System.Drawing.Color]::FromArgb($alpha, 255, 255, 255))
            if ($x -lt $minX) { $minX = $x }
            if ($y -lt $minY) { $minY = $y }
            if ($x -gt $maxX) { $maxX = $x }
            if ($y -gt $maxY) { $maxY = $y }
            $inkCount++
        }
    }
}

if ($inkCount -eq 0) { throw "No ink pixels detected in source image." }
$src.Dispose()

# Crop the mask to the pulse bounding box, with a small breathing-room margin
$cropPad = [int]([Math]::Min($srcW, $srcH) * 0.02)
$cropX = [Math]::Max(0, $minX - $cropPad)
$cropY = [Math]::Max(0, $minY - $cropPad)
$cropW = [Math]::Min($srcW - $cropX, ($maxX - $minX + 1) + $cropPad * 2)
$cropH = [Math]::Min($srcH - $cropY, ($maxY - $minY + 1) + $cropPad * 2)

$cropped = New-Object System.Drawing.Bitmap $cropW, $cropH, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$cg = [System.Drawing.Graphics]::FromImage($cropped)
$cg.DrawImage($mask, (New-Object System.Drawing.Rectangle 0, 0, $cropW, $cropH),
    $cropX, $cropY, $cropW, $cropH, [System.Drawing.GraphicsUnit]::Pixel)
$cg.Dispose()
$mask.Dispose()

# Thicken the stroke so it stays readable at small tray sizes (16/24/32 px).
# We dilate the alpha mask: for each pixel, take the maximum alpha of itself and its
# neighbours within a small radius. Radius scales with source resolution.
function Dilate-AlphaMask([System.Drawing.Bitmap]$bmp, [int]$radius) {
    if ($radius -le 0) { return $bmp }

    $w = $bmp.Width
    $h = $bmp.Height
    $rect = New-Object System.Drawing.Rectangle 0, 0, $w, $h
    $fmt = [System.Drawing.Imaging.PixelFormat]::Format32bppArgb

    # Lock source for fast read
    $srcData = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, $fmt)
    $stride = $srcData.Stride
    $byteCount = $stride * $h
    $bytes = New-Object byte[] $byteCount
    [System.Runtime.InteropServices.Marshal]::Copy($srcData.Scan0, $bytes, 0, $byteCount)
    $bmp.UnlockBits($srcData)

    # Extract alpha channel into a 1-byte-per-pixel array
    $alpha = New-Object byte[] ($w * $h)
    for ($y = 0; $y -lt $h; $y++) {
        $srcRow = $y * $stride
        $dstRow = $y * $w
        for ($x = 0; $x -lt $w; $x++) {
            $alpha[$dstRow + $x] = $bytes[$srcRow + $x * 4 + 3]
        }
    }

    # Two-pass separable max filter (horizontal then vertical) — much faster than O(r^2)
    $tmp = New-Object byte[] ($w * $h)
    for ($y = 0; $y -lt $h; $y++) {
        $row = $y * $w
        for ($x = 0; $x -lt $w; $x++) {
            $maxA = 0
            $x0 = [Math]::Max(0, $x - $radius)
            $x1 = [Math]::Min($w - 1, $x + $radius)
            for ($k = $x0; $k -le $x1; $k++) {
                $a = $alpha[$row + $k]
                if ($a -gt $maxA) { $maxA = $a }
            }
            $tmp[$row + $x] = $maxA
        }
    }
    for ($x = 0; $x -lt $w; $x++) {
        for ($y = 0; $y -lt $h; $y++) {
            $maxA = 0
            $y0 = [Math]::Max(0, $y - $radius)
            $y1 = [Math]::Min($h - 1, $y + $radius)
            for ($k = $y0; $k -le $y1; $k++) {
                $a = $tmp[$k * $w + $x]
                if ($a -gt $maxA) { $maxA = $a }
            }
            $alpha[$y * $w + $x] = $maxA
        }
    }

    # Write dilated alpha back, channel = white
    $out = New-Object System.Drawing.Bitmap $w, $h, $fmt
    $outData = $out.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::WriteOnly, $fmt)
    $outBytes = New-Object byte[] $byteCount
    for ($y = 0; $y -lt $h; $y++) {
        $srcRow = $y * $w
        $dstRow = $y * $stride
        for ($x = 0; $x -lt $w; $x++) {
            $a = $alpha[$srcRow + $x]
            $i = $dstRow + $x * 4
            $outBytes[$i]     = 255  # B
            $outBytes[$i + 1] = 255  # G
            $outBytes[$i + 2] = 255  # R
            $outBytes[$i + 3] = $a   # A
        }
    }
    [System.Runtime.InteropServices.Marshal]::Copy($outBytes, 0, $outData.Scan0, $byteCount)
    $out.UnlockBits($outData)
    $bmp.Dispose()
    return $out
}

# Dilation radius scales with the smaller source dimension. ~1.2% of size gives a noticeable
# but not chunky stroke increase. Tuned so 16x16 tray icons still read clearly.
$dilateRadius = [int]([Math]::Round([Math]::Min($cropW, $cropH) * 0.012))
if ($dilateRadius -lt 2) { $dilateRadius = 2 }
Write-Host "Dilating mask by $dilateRadius px to thicken stroke..."
$cropped = Dilate-AlphaMask $cropped $dilateRadius

Write-Host "Source: $srcW x $srcH, pulse bbox $cropW x $cropH (crop offset $cropX,$cropY)"

# --- Render each ICO size: black rounded square + scaled white pulse on top ---

function New-IconBitmap([int]$size, [System.Drawing.Bitmap]$pulseMask) {
    $bmp = New-Object System.Drawing.Bitmap $size, $size, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.Clear([System.Drawing.Color]::Transparent)

    # Black rounded-square background
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

    # Fit the pulse mask into the square with margin (preserve aspect ratio)
    $margin = [int]([Math]::Max(2, $size * 0.10))
    $availW = $size - $margin * 2
    $availH = $size - $margin * 2

    $mw = $pulseMask.Width
    $mh = $pulseMask.Height
    $scale = [Math]::Min($availW / $mw, $availH / $mh)
    $drawW = [int][Math]::Round($mw * $scale)
    $drawH = [int][Math]::Round($mh * $scale)
    $offX = [int](($size - $drawW) / 2)
    $offY = [int](($size - $drawH) / 2)

    $g.DrawImage($pulseMask, $offX, $offY, $drawW, $drawH)

    $g.Dispose()
    return $bmp
}

# --- Build the ICO byte stream ---

$ms = New-Object System.IO.MemoryStream
$bw = New-Object System.IO.BinaryWriter $ms

$bw.Write([uint16]0)
$bw.Write([uint16]1)
$bw.Write([uint16]$sizes.Count)

$pngs = @()
foreach ($size in $sizes) {
    $bmp = New-IconBitmap $size $cropped
    $pngStream = New-Object System.IO.MemoryStream
    $bmp.Save($pngStream, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    $pngs += , @{ Size = $size; Bytes = $pngStream.ToArray() }
    $pngStream.Dispose()
}
$cropped.Dispose()

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
