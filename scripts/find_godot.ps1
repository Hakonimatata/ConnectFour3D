# Finner Godot 4.7 (konsollversjonen) og skriver stien. Brukes av web.cmd og online.ps1.
# Rekkefolge: miljovariabelen GODOT, Nedlastinger, Skrivebord (ogsa OneDrive), Program Files, til slutt "godot" i PATH.
# Skriver ingenting og avslutter med kode 1 hvis Godot ikke finnes.
if ($env:GODOT) {
    if (Test-Path $env:GODOT) { $env:GODOT; exit 0 }
    exit 1
}

$dirs = @(
    "$env:USERPROFILE\Downloads",
    [Environment]::GetFolderPath('Desktop'),
    "$env:USERPROFILE\Desktop",
    "$env:USERPROFILE\Skrivebord",
    "$env:USERPROFILE\OneDrive\Desktop",
    "$env:USERPROFILE\OneDrive\Skrivebord",
    "$env:ProgramFiles",
    "$env:LOCALAPPDATA\Programs"
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique

foreach ($d in $dirs) {
    $exe = Get-ChildItem $d -Filter 'Godot_v4.7*_win64_console.exe' -Recurse -Depth 2 -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | Select-Object -First 1
    if ($exe) { $exe.FullName; exit 0 }
}

$cmd = Get-Command godot -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($cmd) { $cmd.Source; exit 0 }
exit 1
