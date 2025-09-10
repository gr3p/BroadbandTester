<#
.SYNOPSIS
Scheduler wrapper that runs BroadbandTester.ps1 repeatedly based on configuration.

.DESCRIPTION
Reads settings from script.config (RepeatMinutes, DurationHours) and executes
the broadband test script at specified intervals. Can run once or indefinitely
with optional time limits.
#>

param(
    [string]$ConfigPath=$null
)

$ErrorActionPreference='Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if(-not $ConfigPath){ $ConfigPath = Join-Path $scriptDir 'script.config' }

# Standardinställningar
$settings = [ordered]@{
    RepeatMinutes = 0     # 0 = kör en gång
    DurationHours = 0     # 0 = ingen maxtid
    Args = ''             # extra argument till testskriptet
}

if(Test-Path $ConfigPath){
    Get-Content $ConfigPath | Where-Object {$_ -match '='} | ForEach-Object {
        $kv = $_ -split '=',2
        $key = $kv[0].Trim(); $val = $kv[1].Trim()
        if($settings.Contains($key)) { $settings[$key] = $val }
    }
}

[int]$repeat = $settings.RepeatMinutes
[int]$duration = $settings.DurationHours
[string]$extra = $settings.Args

$testScript = Join-Path $scriptDir 'BroadbandTester.ps1'
if(-not (Test-Path $testScript)){ Write-Error "BroadbandTester.ps1 not found"; exit 1 }

$start = Get-Date
$end   = if($duration -gt 0){ $start.AddHours($duration) } else { $null }
Write-Host "=== SCHEDULE INFO ===" -ForegroundColor Yellow
if($repeat -le 0){
    Write-Host "Script will run ONCE immediately." -ForegroundColor White
} else {
    $stopMsg = if($end){ "and stop at $($end.ToString('s'))" } else { 'and run indefinitely' }
    Write-Host "Script will run every $repeat minutes $stopMsg." -ForegroundColor White
}
if($extra){ Write-Host "Extra args passed to test script: $extra" -ForegroundColor Gray }

function Run-TestOnce{
    param(
        [string]$scriptPath,
        [string]$argLine = ''
    )
    Write-Host "`n===== RUN $(Get-Date -Format s) =====" -ForegroundColor Cyan

    # Build cleaned token array
    $paramHash=@{}
    if(-not [string]::IsNullOrWhiteSpace($argLine)){
        $tokens=($argLine -split '\s+') | Where-Object {$_}
        for($i=0;$i -lt $tokens.Count;$i++){
            $t=$tokens[$i]
            if($t.StartsWith('-')){
                $name=$t.Substring(1)
                $val=$true
                if($i+1 -lt $tokens.Count -and -not $tokens[$i+1].StartsWith('-')){
                    $val=$tokens[$i+1]; $i++
                }
                $paramHash[$name]=$val
            }
        }
    }

    if($paramHash.Count -gt 0){
        & $scriptPath @paramHash
    } else {
        & $scriptPath
    }
}

while($true){
    Run-TestOnce -scriptPath $testScript -argLine $extra
    if($repeat -le 0){ break }
    if($end -and (Get-Date) -ge $end){ break }
    Start-Sleep -Seconds ($repeat*60)
}

Write-Host "All scheduled tests completed." -ForegroundColor Green
