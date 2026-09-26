# Генератор 2D-персонажей для кликера (powershell -File tools\generate_2d_characters.ps1)
# Стиль Fran Bow: большие глаза, тонкие линии, «жутко-мило», приглушённые цвета.
Add-Type -AssemblyName System.Drawing
$outDir = "D:\fff\PROECTS\wizard-clicker\assets\textures"

$ink = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255,22,16,22))
$skin = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255,224,205,172))
$robe = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255,201,183,142))
$hem = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255,122,104,78))
$cheek = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(110,196,110,112))

function Face([System.Drawing.Graphics]$g, [int]$cx, [int]$cy, [double]$scale) {
    # Глаза — огромные, с бликами
    $ew = [int](34 * $scale); $eh = [int](48 * $scale)
    $g.FillEllipse($ink, $cx - $ew - [int](6*$scale), $cy - [int](20*$scale), $ew, $eh)
    $g.FillEllipse($ink, $cx + [int](6*$scale), $cy - [int](20*$scale), $ew, $eh)
    $g.FillEllipse([System.Drawing.Brushes]::White, $cx - $ew - [int](2*$scale), $cy - [int](10*$scale), [int](10*$scale), [int](13*$scale))
    $g.FillEllipse([System.Drawing.Brushes]::White, $cx + [int](9*$scale), $cy - [int](10*$scale), [int](10*$scale), [int](13*$scale))
    # Улыбка чуть шире, чем надо
    $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255,22,16,22)), ([single](5*$scale))
    $mw = [int](64 * $scale)
    $g.DrawArc($pen, $cx - [int]($mw/2), $cy + [int](34*$scale), $mw, [int](34*$scale), 25, 130)
    # Щёки
    $g.FillEllipse($cheek, $cx - $ew - [int](16*$scale), $cy + [int](22*$scale), [int](22*$scale), [int](13*$scale))
    $g.FillEllipse($cheek, $cx + $ew - [int](6*$scale), $cy + [int](22*$scale), [int](22*$scale), [int](13*$scale))
}

# ---------- 1. ЧЕЛИК (256x384) — кланяющийся ----------
$b = New-Object System.Drawing.Bitmap 256,384
$g = [System.Drawing.Graphics]::FromImage($b)
$g.SmoothingMode = 'AntiAlias'
$g.Clear([System.Drawing.Color]::Transparent)

# Ноги-ботинки
$shoe = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255,70,55,50))
$g.FillEllipse($shoe, 92, 344, 32, 24)
$g.FillEllipse($shoe, 132, 344, 32, 24)

# Мантия-трапеция
$pts = @(
    (New-Object System.Drawing.Point 96,150), (New-Object System.Drawing.Point 160,150),
    (New-Object System.Drawing.Point 208,340), (New-Object System.Drawing.Point 48,340)
)
$g.FillPolygon($robe, $pts)
# Подол
$ptsHem = @(
    (New-Object System.Drawing.Point 52,312), (New-Object System.Drawing.Point 204,312),
    (New-Object System.Drawing.Point 208,340), (New-Object System.Drawing.Point 48,340)
)
$g.FillPolygon($hem, $ptsHem)
# Потёртости на ткани
$rnd = New-Object System.Random 7
for ($i = 0; $i -lt 26; $i++) {
    $a = 14 + $rnd.Next(26)
    $stain = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb($a,110,92,66))
    $x = 70 + $rnd.Next(120); $y = 160 + $rnd.Next(140); $s = 5 + $rnd.Next(18)
    $g.FillEllipse($stain, $x, $y, $s, [int]($s*0.7))
}
# Воротник
$g.FillRectangle((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255,110,95,75))), 100, 146, 56, 14)

# Голова
$g.FillEllipse($skin, 68, 30, 120, 112)
Face $g 128 78 1.0

$b.Save((Join-Path $outDir "chelik_2d.png"), [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $b.Dispose()
Write-Host "OK: chelik_2d.png"

# ---------- 2. ВОЛШЕБНИК (256x448) — великий и жутковатый ----------
$b2 = New-Object System.Drawing.Bitmap 256,448
$g2 = [System.Drawing.Graphics]::FromImage($b2)
$g2.SmoothingMode = 'AntiAlias'
$g2.Clear([System.Drawing.Color]::Transparent)

$robeP = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255,74,46,84))
$robeD = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255,58,35,68))

# Посох с тусклым зелёным камнем
$staffPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255,86,62,52)), 8
$g2.DrawLine($staffPen, 206, 70, 220, 420)
$orb = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255,148,180,142))
$g2.FillEllipse($orb, 192, 42, 34, 34)
$g2.FillEllipse([System.Drawing.Brushes]::White, 200, 50, 8, 8)

# Мантия
$ptsW = @(
    (New-Object System.Drawing.Point 108,150), (New-Object System.Drawing.Point 148,150),
    (New-Object System.Drawing.Point 228,430), (New-Object System.Drawing.Point 28,430)
)
$g2.FillPolygon($robeP, $ptsW)
# Тень-складка по центру
$ptsFold = @(
    (New-Object System.Drawing.Point 122,160), (New-Object System.Drawing.Point 134,160),
    (New-Object System.Drawing.Point 150,425), (New-Object System.Drawing.Point 106,425)
)
$g2.FillPolygon($robeD, $ptsFold)
# Бледные руки
$pale = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255,216,201,176))
$g2.FillEllipse($pale, 62, 232, 28, 22)
$g2.FillEllipse($pale, 166, 232, 28, 22)

# Борода
$beard = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255,196,190,196))
$g2.FillEllipse($beard, 100, 128, 56, 96)

# Лицо: светящиеся бледные глаза + тонкая улыбка
$eye = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255,232,217,138))
$g2.FillEllipse($eye, 102, 100, 18, 24)
$g2.FillEllipse($eye, 136, 100, 18, 24)
$penW = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255,40,28,40)), 4
$g2.DrawArc($penW, 108, 122, 40, 20, 20, 140)

# Шляпа: поля + конус
$brim = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255,52,30,62))
$g2.FillEllipse($brim, 44, 84, 168, 30)
$ptsHat = @(
    (New-Object System.Drawing.Point 152,6), (New-Object System.Drawing.Point 78,102),
    (New-Object System.Drawing.Point 182,102)
)
$g2.FillPolygon($brim, $ptsHat)
# Изгиб конуса — «ведьминский»
$g2.FillPolygon($robeD, @(
    (New-Object System.Drawing.Point 152,6), (New-Object System.Drawing.Point 132,44),
    (New-Object System.Drawing.Point 162,58)
))

$b2.Save((Join-Path $outDir "wizard_2d.png"), [System.Drawing.Imaging.ImageFormat]::Png)
$g2.Dispose(); $b2.Dispose()
Write-Host "OK: wizard_2d.png"
