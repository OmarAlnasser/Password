# CI only. Fails if any shipped PE file is unsigned or invalid, or if a WinRing0 binary is present.
# The app itself never runs PowerShell; this script runs on the build agent.
param([Parameter(Mandatory)] [string] $Path, [switch] $RequireSigned)

$ErrorActionPreference = 'Stop'
$files = Get-ChildItem -Path $Path -Recurse -Include *.exe, *.dll, *.sys
$winring0 = $files | Where-Object { $_.Name -like 'WinRing0*' }
if ($winring0) { throw "WinRing0 must never ship: $($winring0.FullName -join ', ')" }

$bad = @()
foreach ($f in $files) {
    $sig = Get-AuthenticodeSignature -FilePath $f.FullName
    if ($sig.Status -ne 'Valid') { $bad += "$($f.Name): $($sig.Status)" }
}
if ($bad.Count -gt 0) {
    if ($RequireSigned) { throw "Unsigned or invalid:`n$($bad -join "`n")" }
    Write-Host "::warning::Unsigned build (no signing identity configured). Not for distribution: Smart App Control and SmartScreen will block it."
}
