# Генератор текстур челика (запускать: powershell -File tools\generate_chelik_textures.ps1)
# Рисуем в стиле Fran Bow: большие глаза, тонкая широкая улыбка, потёртая ткань.
Add-Type -AssemblyName System.Drawing
$outDir = "D:\fff\PROECTS\wizard-clicker\assets\textures"

# ---------- 1. ЛИЦО (накладывается на плоский четырёхугольник перед головой) ----------
$bmp = New-Object System.Drawing.Bitmap 256,256
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = 'AntiAlias'
$g.Clear([System.Drawing.Color]::Transparent)

$ink = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255,22,16,22))

# Большие овальные глаза
$g.FillEllipse($ink, 58, 70, 52, 74)
$g.FillEllipse($ink, 146, 70, 52, 74)
# Белые блики — «жизнь» в глазах
$g.FillEllipse([System.Drawing.Brushes]::White, 72, 86, 15, 20)
$g.FillEllipse([System.Drawing.Brushes]::White, 160, 86, 15, 20)
# Крошечные зрачки
$g.FillEllipse([System.Drawing.Brushes]::White, 82, 116, 6, 8)
$g.FillEllipse([System.Drawing.Brushes]::White, 170, 116, 6, 8)

# Улыбка чуть шире, чем надо
$pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255,22,16,22)), 6
$g.DrawArc($pen, 74, 142, 108, 64, 25, 130)

# Румяные щёки
$cheek = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(110,196,110,112))
$g.FillEllipse($cheek, 34, 140, 36, 22)
$g.FillEllipse($cheek, 186, 140, 36, 22)

$facePath = Join-Path $outDir "chelik_face.png"
$bmp.Save($facePath, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
Write-Host "OK: $facePath"

# ---------- 2. ОДЕЖДА (натягивается на тело-капсулу) ----------
$b2 = New-Object System.Drawing.Bitmap 256,256
$g2 = [System.Drawing.Graphics]::FromImage($b2)
$g2.SmoothingMode = 'AntiAlias'

# Пергаментная основа
$base = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255,201,183,142))
$g2.FillRectangle($base, 0, 0, 256, 256)

# Потёртости и кляксы — ткань «жила долго в замке»
$rnd = New-Object System.Random 42
for ($i = 0; $i -lt 60; $i++) {
    $a = 18 + $rnd.Next(30)
    $stain = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb($a, 120, 100, 70))
    $x = $rnd.Next(256); $y = $rnd.Next(256); $s = 6 + $rnd.Next(30)
    $g2.FillEllipse($stain, $x, $y, $s, [int]($s * 0.7))
}

# Тёмный подол снизу и воротник сверху
$hem = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255,122,104,78))
$g2.FillRectangle($hem, 0, 218, 256, 38)
$collar = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255,110,95,75))
$g2.FillRectangle($collar, 0, 0, 256, 26)

# Торопливые стежки
$pen2 = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(160,60,45,40)), 3
for ($i = 0; $i -lt 14; $i++) {
    $x = $rnd.Next(240); $y = 40 + $rnd.Next(170)
    $g2.DrawLine($pen2, $x, $y, $x + 10, $y + 4)
}

$robePath = Join-Path $outDir "chelik_robe.png"
$b2.Save($robePath, [System.Drawing.Imaging.ImageFormat]::Png)
$g2.Dispose(); $b2.Dispose()
Write-Host "OK: $robePath"
