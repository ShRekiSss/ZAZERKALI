# Осмотр GLB: печатает сцены/меши/анимации (powershell -File tools\inspect_glb.ps1 <file.glb>)
param([string]$GlbPath)
$bytes = [System.IO.File]::ReadAllBytes($GlbPath)
# GLB: 12 байт заголовок, потом чанки; первый чанк — JSON
$jsonLen = [BitConverter]::ToUInt32($bytes, 12)
$json = [System.Text.Encoding]::UTF8.GetString($bytes, 20, $jsonLen)
$gltf = $json | ConvertFrom-Json
Write-Host "=== $GlbPath ==="
Write-Host ("meshes: " + ($gltf.meshes | ForEach-Object { $_.name }) -join ", ")
if ($gltf.animations) {
    Write-Host "animations:"
    foreach ($a in $gltf.animations) { Write-Host ("  - " + $a.name + " (" + $a.channels.Count + " channels)") }
} else { Write-Host "animations: НЕТ" }
if ($gltf.skins) { Write-Host ("skins(скелеты): " + $gltf.skins.Count) }
$nodes = @($gltf.nodes)
Write-Host ("nodes: " + $nodes.Count + "; корневые: " + (($gltf.scenes[0].nodes | ForEach-Object { $nodes[$_].name }) -join ", "))
