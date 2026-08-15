$flags     = ($args -join '')
$optimized = $flags.Contains('o')
$run       = $flags.Contains('r')

$cfgPath = Join-Path $PSScriptRoot 'cfg/cfg.odin'
$cfgText = Get-Content -Path $cfgPath -Raw

if ($cfgText -notmatch 'EXE_NAME\s*::\s*"([^"]+)"') {
    Write-Host "could not find EXE_NAME in $cfgPath"
    exit 1
}

$exeName = $Matches[1]

$odinArgs = @('build', '.')

if ($optimized) {
    $out = "$exeName.exe"
    $odinArgs += "-out:$out", '-o:speed', '-disable-assert', '-no-bounds-check'
} else {
    $out = "$exeName`_dbg.exe"
    $odinArgs += "-out:$out", '-debug'
}

$odinArgs += '-vet', '-strict-style'

& odin @odinArgs

if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
if ($run) { & (Join-Path $PSScriptRoot $out) }
