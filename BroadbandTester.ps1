<#
.SYNOPSIS
Comprehensive broadband performance testing tool.

.DESCRIPTION
Tests internet connection speed (download/upload) against multiple Ookla servers,
measures ping and packet loss to various targets (gateway, public IPs, server IPs),
and traces network routes with detailed hop information. Results are displayed
in a color-coded summary and logged to CSV files.
Author: gr3p 2025
#>

param(
    [int]$PingCount = 20,
    [int]$TraceEveryMinutes=60,
    [string]$OutRoot=$null,
    [string]$SpeedtestExe=$null
)

Import-Module NetAdapter -ErrorAction SilentlyContinue
Import-Module NetTCPIP -ErrorAction SilentlyContinue

if(-not $SpeedtestExe){
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $SpeedtestExe = Join-Path $scriptDir "speedtest.exe"
}

if(-not (Test-Path $SpeedtestExe)){
    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
    Write-Host "║  Ookla Speedtest CLI (speedtest.exe) not found!              ║" -ForegroundColor Yellow
    Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "This script requires Ookla's official Speedtest CLI." -ForegroundColor White
    Write-Host "Download URL: https://www.speedtest.net/apps/cli" -ForegroundColor Cyan
    Write-Host ""
    
    $response = Read-Host "Would you like to download it automatically? (y/n)"
    
    if($response -match '^[yY]'){
        Write-Host ""
        Write-Host "Downloading Speedtest CLI..." -ForegroundColor Cyan
        
        try {
            $downloadUrl = "https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-win64.zip"
            $zipPath = Join-Path $scriptDir "speedtest.zip"
            $extractPath = $scriptDir
            
            # Download
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath -UseBasicParsing
            
            # Extract
            Write-Host "Extracting..." -ForegroundColor Cyan
            Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force
            
            # Cleanup zip
            Remove-Item $zipPath -Force
            
            if(Test-Path $SpeedtestExe){
                Write-Host "✓ Speedtest CLI installed successfully!" -ForegroundColor Green
                Write-Host ""
                Write-Host "NOTE: First run will require accepting Ookla's license agreement." -ForegroundColor Yellow
                Write-Host ""
            } else {
                Write-Error "Download completed but speedtest.exe not found. Please download manually."
                exit 1
            }
        } catch {
            Write-Host ""
            Write-Host "✗ Download failed: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host ""
            Write-Host "Please download manually from: https://www.speedtest.net/apps/cli" -ForegroundColor Yellow
            Write-Host "Extract speedtest.exe to: $scriptDir" -ForegroundColor Yellow
            exit 1
        }
    } else {
        Write-Host ""
        Write-Host "Please download speedtest.exe manually from:" -ForegroundColor Yellow
        Write-Host "  https://www.speedtest.net/apps/cli" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Extract and place speedtest.exe in:" -ForegroundColor Yellow
        Write-Host "  $scriptDir" -ForegroundColor White
        exit 1
    }
}

$ErrorActionPreference="Stop"

$script:TestAborted = $false
$script:speedResults = @()
$script:allPingResults = @()

$null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
    $script:TestAborted = $true
}

trap {
    if($_ -match 'PipelineStoppedException|OperationCanceledException'){
        $script:TestAborted = $true
        Write-Host "`n`n⚠️  TEST INTERRUPTED - Showing partial results..." -ForegroundColor Yellow
        Show-FinalSummary -Partial
        exit 0
    }
}

$CsvEnabled = $false

function Write-CsvContent{
    param(
        [Parameter(Mandatory=$true,Position=0)]$Path,
        [Parameter(Position=1)]$Value
    )
    if(-not $CsvEnabled -and $Path -like '*.csv'){ return }
    Add-Content -Path $Path -Value $Value
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if(-not $OutRoot){
    $OutRoot = Join-Path $scriptDir "logs"
}
$null=New-Item -ItemType Directory -Path $OutRoot -Force

$SpeedCsv=Join-Path $OutRoot "speed.csv"
$PingCsv=Join-Path $OutRoot "ping.csv"
$TraceCsv=Join-Path $OutRoot "trace.csv"
$RunLog=Join-Path $OutRoot "run.log"

$bundle = 0
function Start-Bundle($serverName){
    $script:bundle++
    Write-Info "`n=== TEST TOWARDS : $serverName ===" 'Yellow'
}

function Write-Log($msg){
    try{
        $ts=(Get-Date).ToString("s")
        [System.IO.File]::AppendAllText($RunLog, "`n$ts,$msg")
    }catch{
        Write-Host "[LOGGING ERROR] $_" -ForegroundColor Red
    }
}

function Write-Info{
    param(
        [string]$Text,
        [string]$Color='White'
    )
    Write-Host $Text -ForegroundColor $Color
    Write-Log "INFO,$Text"
}

function Ensure-CsvHeader{
    param($Path,$Header)
    if(-not $CsvEnabled){ return }
    if(-not (Test-Path $Path)){
        $Header -join "," | Out-File -FilePath $Path -Encoding UTF8
    }
}

$script:SpinnerChars = @('⣾','⣽','⣻','⢿','⡿','⣟','⣯','⣷')
$script:SpinnerRunning = $false
$script:SpinnerMessage = ""

function Invoke-WithSpinner{
    param(
        [scriptblock]$ScriptBlock,
        [string]$Message = "Working...",
        [string]$CompletedMessage = "Done",
        [array]$ArgumentList = @()
    )
    
    $frames = @('⣾','⣽','⣻','⢿','⡿','⣟','⣯','⣷')
    $frameIdx = 0
    
    $job = Start-Job -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList
    
    while($job.State -eq 'Running'){
        $spinner = $frames[$frameIdx % $frames.Count]
        Write-Host "`r$spinner $Message   " -NoNewline -ForegroundColor Cyan
        $frameIdx++
        Start-Sleep -Milliseconds 80
    }
    
    $result = Receive-Job -Job $job
    Remove-Job -Job $job
    
    Write-Host "`r$(' ' * 70)" -NoNewline
    if($CompletedMessage){
        Write-Host "`r✓ $CompletedMessage" -ForegroundColor Green
    } else {
        Write-Host "`r" -NoNewline
    }
    
    return $result
}

function Write-SpinnerFrame{
    param([string]$Message, [int]$Frame = 0)
    $frames = @('⣾','⣽','⣻','⢿','⡿','⣟','⣯','⣷')
    $spinner = $frames[$Frame % $frames.Count]
    Write-Host "`r$spinner $Message" -NoNewline -ForegroundColor Cyan
}

function Clear-SpinnerLine{
    param([string]$FinalMessage = "", [string]$Color = "Green")
    Write-Host "`r$(' ' * 70)" -NoNewline
    if($FinalMessage){
        Write-Host "`r✓ $FinalMessage" -ForegroundColor $Color
    } else {
        Write-Host "`r" -NoNewline
    }
}

function Show-Progress{
    param(
        [string]$Activity,
        [string]$Status,
        [int]$PercentComplete = -1,
        [switch]$Completed
    )
    if($Completed){
        Write-Progress -Activity $Activity -Completed
    } elseif($PercentComplete -ge 0){
        Write-Progress -Activity $Activity -Status $Status -PercentComplete $PercentComplete
    } else {
        Write-Progress -Activity $Activity -Status $Status
    }
}

function Format-BoxLine{
    param(
        [string]$Text,
        [int]$Width = 62,
        [switch]$HasEmoji
    )
    $emojiAdjust = if($HasEmoji){ 1 } else { 0 }
    $padding = $Width - $Text.Length + $emojiAdjust
    if($padding -lt 0){ $padding = 0 }
    return $Text + (' ' * $padding)
}

function Show-FinalSummary{
    param([switch]$Partial)
    
    $results = $script:speedResults
    $pings = $script:allPingResults
    $boxWidth = 62
    
    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    if($Partial){
        Write-Host "║  ⚠ PARTIAL TEST RESULTS (Interrupted)                        ║" -ForegroundColor Yellow
    } else {
        Write-Host "║  FINAL TEST RESULTS                                          ║" -ForegroundColor Cyan
    }
    Write-Host "╠══════════════════════════════════════════════════════════════╣" -ForegroundColor Cyan
    
    if($results.Count -gt 0){
        $avgDown   = [math]::Round(($results | Measure-Object Download_Mbps -Average).Average,1)
        $avgUp     = [math]::Round(($results | Measure-Object Upload_Mbps -Average).Average,1)
        $avgPing   = [math]::Round(($results | Measure-Object PingMs -Average).Average,1)
        $avgJitter = [math]::Round(($results | Measure-Object JitterMs -Average).Average,1)
        
        $grade = 'A'; $gradeColor = 'Green'
        if($avgDown -lt 25 -or $avgUp -lt 10 -or $avgPing -gt 50){ $grade='B'; $gradeColor='Green' }
        if($avgDown -lt 10 -or $avgUp -lt 5 -or $avgPing -gt 100){ $grade='C'; $gradeColor='Yellow' }
        if($avgDown -lt 5 -or $avgUp -lt 2 -or $avgPing -gt 200){ $grade='D'; $gradeColor='Red' }
        
        $dlColor = if($avgDown -ge 100){'Green'}elseif($avgDown -ge 25){'Yellow'}else{'Red'}
        $ulColor = if($avgUp -ge 50){'Green'}elseif($avgUp -ge 10){'Yellow'}else{'Red'}
        $pingColor = if($avgPing -le 20){'Green'}elseif($avgPing -le 50){'Yellow'}else{'Red'}
        
        $dlStatus = if($avgDown -ge 100){'[Excellent]'}elseif($avgDown -ge 25){'[Good]'}else{'[Slow]'}
        $ulStatus = if($avgUp -ge 50){'[Excellent]'}elseif($avgUp -ge 10){'[Good]'}else{'[Slow]'}
        $pingStatus = if($avgPing -le 20){'[Excellent]'}elseif($avgPing -le 50){'[Good]'}else{'[High]'}
        
        $dlText = "  DOWNLOAD:  $avgDown Mbps".PadRight(30) + $dlStatus.PadRight(30)
        Write-Host "║" -ForegroundColor Cyan -NoNewline
        Write-Host $dlText -ForegroundColor $dlColor -NoNewline
        Write-Host "║" -ForegroundColor Cyan
        
        $ulText = "  UPLOAD:    $avgUp Mbps".PadRight(30) + $ulStatus.PadRight(30)
        Write-Host "║" -ForegroundColor Cyan -NoNewline
        Write-Host $ulText -ForegroundColor $ulColor -NoNewline
        Write-Host "║" -ForegroundColor Cyan
        
        $pingText = "  PING:      $avgPing ms".PadRight(30) + $pingStatus.PadRight(30)
        Write-Host "║" -ForegroundColor Cyan -NoNewline
        Write-Host $pingText -ForegroundColor $pingColor -NoNewline
        Write-Host "║" -ForegroundColor Cyan
        
        $jitterText = "  JITTER:    $avgJitter ms".PadRight(60)
        Write-Host "║" -ForegroundColor Cyan -NoNewline
        Write-Host $jitterText -NoNewline
        Write-Host "║" -ForegroundColor Cyan
        
        Write-Host "╠══════════════════════════════════════════════════════════════╣" -ForegroundColor Cyan
        
        $gradeSymbol = if($grade -eq 'A'){'[A]'}elseif($grade -eq 'B'){'[B]'}elseif($grade -eq 'C'){'[C]'}else{'[D]'}
        $overallText = "  OVERALL:   Grade $grade $gradeSymbol".PadRight(60)
        Write-Host "║" -ForegroundColor Cyan -NoNewline
        Write-Host $overallText -ForegroundColor $gradeColor -NoNewline
        Write-Host "║" -ForegroundColor Cyan
    } else {
        Write-Host "║  No speed test results collected.                            ║" -ForegroundColor Yellow
    }
    
    if($pings.Count -gt 0){
        $avgLoss = [math]::Round(($pings | Measure-Object LossPct -Average).Average,1)
        $lossColor = if($avgLoss -eq 0){'Green'}elseif($avgLoss -lt 2){'Yellow'}else{'Red'}
        $lossStatus = if($avgLoss -eq 0){'[Perfect]'}elseif($avgLoss -lt 2){'[Minor]'}else{'[Issues]'}
        $lossText = "  PKT LOSS:  $avgLoss %".PadRight(30) + $lossStatus.PadRight(30)
        Write-Host "║" -ForegroundColor Cyan -NoNewline
        Write-Host $lossText -ForegroundColor $lossColor -NoNewline
        Write-Host "║" -ForegroundColor Cyan
    }
    
    Write-Host "╠══════════════════════════════════════════════════════════════╣" -ForegroundColor Cyan
    $statsText = "  Servers tested: $($results.Count)    Ping targets: $($pings.Count)".PadRight(60)
    Write-Host "║" -ForegroundColor Cyan -NoNewline
    Write-Host $statsText -NoNewline
    Write-Host "║" -ForegroundColor Cyan
    $timeText = "  Completed: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')".PadRight(60)
    Write-Host "║" -ForegroundColor Cyan -NoNewline
    Write-Host $timeText -NoNewline
    Write-Host "║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
}

function Run-Speedtest{
    param(
        [string]$Exe,
        [string]$ServerId=$null
    )
    $serverLabel = if($ServerId){ "server $ServerId" } else { "auto-selected server" }
    try {
        $jsonText = Invoke-WithSpinner -Message "Running speedtest against $serverLabel..." -CompletedMessage "Speedtest complete" -ArgumentList @($Exe, $ServerId) -ScriptBlock {
            param($exePath, $srvId)
            if($srvId){
                $result = & $exePath --accept-license --accept-gdpr --format=json --server-id $srvId 2>&1
            } else {
                $result = & $exePath --accept-license --accept-gdpr --format=json 2>&1
            }
            return ($result | Out-String)
        }
        
        $json = $jsonText | ConvertFrom-Json

        $downMbps=[math]::Round(($json.download.bandwidth*8)/1MB,1)
        $upMbps=[math]::Round(($json.upload.bandwidth*8)/1MB,1)
        
        $row=[pscustomobject]@{
            Timestamp=(Get-Date).ToString("s")
            ISP=$json.isp
            ExternalIp=$json.interface.externalIp
            NicInternalIp=$json.interface.internalIp
            NicName=$json.interface.name
            NicMac=$json.interface.macAddr
            NicIsVpn=$json.interface.isVpn
            ServerName=$json.server.name
            ServerLocation="$($json.server.location), $($json.server.country)"
            ServerId=$json.server.id
            ServerIp=$json.server.ip
            PingMs=[math]::Round($json.ping.latency,2)
            JitterMs=[math]::Round($json.ping.jitter,2)
            PacketLoss=$json.packetLoss
            Download_Mbps=$downMbps
            Upload_Mbps=$upMbps
        }
        return $row
    } catch {
        Write-Host "ERROR: Speedtest failed - $($_.Exception.Message)" -ForegroundColor Red
        throw
    }
}

function Get-DefaultGateway{
    try{
        $route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction Stop | Sort-Object RouteMetric | Select-Object -First 1
        return $route.NextHop
    }catch{
        try{
            $cim = Get-CimInstance -ClassName Win32_IP4RouteTable -ErrorAction Stop | Where-Object { $_.Destination -eq '0.0.0.0' -and $_.Mask -eq '0.0.0.0' } | Sort-Object Metric1, PathMetric | Select-Object -First 1
            if($cim){ return $cim.NextHop }
        }catch{}
        try{
            $rp = & route print 0.0.0.0
            $m = $rp | Select-String -Pattern '0\.0\.0\.0\s+0\.0\.0\.0\s+(\d+\.\d+\.\d+\.\d+)' -AllMatches | Select-Object -First 1
            if($m -and $m.Matches.Count -gt 0){ return $m.Matches[0].Groups[1].Value }
        }catch{}
        return $null
    }
}

function Get-ActiveNicInfo{
    try{
        $nic=Get-NetAdapter -ErrorAction Stop | Where-Object Status -eq Up | Sort-Object -Property LinkSpeed -Descending | Select-Object -First 1
        if($nic){ return $nic }
    }catch{}
    try{
        $adapters = Get-CimInstance -ClassName Win32_NetworkAdapter -ErrorAction Stop | Where-Object { $_.NetEnabled -eq $true -and $_.Speed -ne $null }
        $best = $adapters | Sort-Object -Property Speed -Descending | Select-Object -First 1
        if($best){
            $speedBps = [double]$best.Speed
            $linkStr = if($speedBps -ge 1000000000){ ('{0} Gbps' -f [math]::Round($speedBps/1000000000,0)) } else { ('{0} Mbps' -f [math]::Round($speedBps/1000000,0)) }
            return [pscustomobject]@{
                Name = $best.Name
                LinkSpeed = $linkStr
            }
        }
    }catch{}
    return $null
}

function Get-FirstPublicHop{
    try{
        $raw = Invoke-WithSpinner -Message "Finding first public hop..." -CompletedMessage "First public hop found" -ScriptBlock {
            & tracert -d -h 6 1.1.1.1 2>&1 | Out-String
        }
        $ips=($raw | Select-String -Pattern '(\d{1,3}\.){3}\d{1,3}' -AllMatches | ForEach-Object {$_.Matches.Value})
        $pub=$ips | Where-Object {$_ -notmatch '^10\.|^192\.168\.|^172\.(1[6-9]|2[0-9]|3[0-1])\.'} | Select-Object -First 1
        return $pub
    }catch{
        Clear-SpinnerLine "Failed to find public hop" 'Red'
        return $null
    }
}

function Measure-Ping{
    param($Target,$Count)
    $start=Get-Date
    $replies=@()
    for($i=1; $i -le $Count; $i++){
        Write-SpinnerFrame -Message "Pinging $Target ($i/$Count)..." -Frame $i
        $reply = Test-Connection -TargetName $Target -Count 1 -ErrorAction SilentlyContinue
        if($reply){ $replies += $reply }
    }
    Clear-SpinnerLine
    $ok=$replies.Count
    $loss=[math]::Round((1-($ok/[double]$Count))*100,1)
    $avg=[double]::NaN; $min=[double]::NaN; $max=[double]::NaN
    if($ok -gt 0){
        $avg=[math]::Round(($replies | Measure-Object ResponseTime -Average).Average,2)
        $min=[math]::Round(($replies | Measure-Object ResponseTime -Minimum).Minimum,2)
        $max=[math]::Round(($replies | Measure-Object ResponseTime -Maximum).Maximum,2)
    }
    [pscustomobject]@{
        Timestamp=$start.ToString("s")
        Target=$Target
        Sent=$Count
        Received=$ok
        LossPct=$loss
        MinMs=$min
        AvgMs=$avg
        MaxMs=$max
    }
}

function Invoke-Traceroute{
    param($Target)
    $ts=(Get-Date).ToString("s")
    
    
    $traceResult = Invoke-WithSpinner -Message "Tracing route to $Target..." -CompletedMessage "Trace to $Target complete" -ArgumentList @($Target) -ScriptBlock {
        param($tgt)
        $raw = & tracert -d $tgt 2>&1
        return ($raw | Out-String)
    }
    
    
    $hops = @()
    $lines = $traceResult -split "`n"
    foreach($line in $lines){
        # Match lines like: "  1    <1 ms    <1 ms    <1 ms  192.168.1.1"
        if($line -match '^\s*(\d+)\s+([\d<]+\s*ms|\*)\s+([\d<]+\s*ms|\*)\s+([\d<]+\s*ms|\*)\s+(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})'){
            $hopNum = [int]$matches[1]
            $latency = $matches[4] -replace '\s*ms','' -replace '<',''
            $ip = $matches[5]
            if($latency -eq '*'){ $latency = 'timeout' }
            $hops += [pscustomobject]@{
                Hop = $hopNum
                IP = $ip
                Latency = $latency
            }
        }
        elseif($line -match '^\s*(\d+)\s+\*\s+\*\s+\*'){
            $hopNum = [int]$matches[1]
            $hops += [pscustomobject]@{
                Hop = $hopNum
                IP = '*'
                Latency = 'timeout'
            }
        }
    }
    
    $hopList = ($hops | ForEach-Object { $_.IP }) -join ' > '
    
    [pscustomobject]@{
        Timestamp = $ts
        Target = $Target
        HopCount = $hops.Count
        Hops = $hopList
        HopDetails = $hops
    }
}

Write-Info "=== BROADBAND PERFORMANCE TEST (v2) ===" 'Magenta'
Write-Info "Test started at: $(Get-Date)" 'White'
Write-Info "Output directory: $OutRoot" 'White'

Ensure-CsvHeader -Path $RunLog -Header "Timestamp,Type,Detail1,Detail2,Detail3,Detail4,Detail5,Detail6,Detail7"

try{
    $nic=Get-ActiveNicInfo
    $gw=Get-DefaultGateway
    $firstPub=Get-FirstPublicHop
    $nicSpeed=if($nic){$nic.LinkSpeed.ToString()}else{"Unknown"}
    $nicMbps=$null
    if($nic){
        $ls=$nic.LinkSpeed.ToString()
        if($ls -match '(\d+)\s*Gbps'){ $nicMbps=[int]$matches[1]*1000 }
        elseif($ls -match '(\d+)\s*Mbps'){ $nicMbps=[int]$matches[1] }
    }

    Write-Info "`n--- NETWORK CONFIGURATION ---" 'Yellow'
    if($nic) { Write-Info "Active NIC: $($nic.Name) ($($nic.LinkSpeed))" 'White' }
    Write-Info "Default Gateway: $gw" 'White'
    Write-Info "First Public Hop: $firstPub" 'White'

    Write-Host "`n--- SPEED TEST (up to 3 nearest servers) ---" -ForegroundColor Yellow

    $serverIds = @()
    try {
        $listJson = & "$SpeedtestExe" --accept-license --accept-gdpr --format=json --servers | ConvertFrom-Json
        $serverIds = $listJson.servers | Sort-Object distance | Select-Object -First 3 -ExpandProperty id
    } catch {
Write-Log "ERROR,Could not retrieve server list: $($_.Exception.Message)"
    }
    if(-not $serverIds){ $serverIds = @($null) }

    $script:speedResults = @()
    $serverIdx = 0
    foreach($sid in $serverIds){
        $serverIdx++
        Show-Progress -Activity "Speed Tests" -Status "Testing server $serverIdx of $($serverIds.Count)..." -PercentComplete ([int](($serverIdx/$serverIds.Count)*100))
        $rowSingle = Run-Speedtest -Exe $SpeedtestExe -ServerId $sid
        if(-not $rowSingle){ continue }
        Start-Bundle $rowSingle.ServerName
        $serverIp=$rowSingle.ServerIp
        if(-not $serverIp){
            try {
                $serverIp=[System.Net.Dns]::GetHostAddresses($rowSingle.ServerName) | Where-Object {$_.AddressFamily -eq 'InterNetwork'} | Select-Object -First 1 | ForEach-Object { $_.ToString() }
            }catch{}
        }
        $script:speedResults += $rowSingle
        Write-Host "-> Result: $($rowSingle.Download_Mbps)↓ / $($rowSingle.Upload_Mbps)↑ Mbps, Ping $($rowSingle.PingMs)ms" -ForegroundColor Green
        $dlUtil = if($nicMbps){ [math]::Round(($rowSingle.Download_Mbps / $nicMbps)*100,1) } else { '' }
        $ulUtil = if($nicMbps){ [math]::Round(($rowSingle.Upload_Mbps / $nicMbps)*100,1) } else { '' }
        Write-Log "SPEED,Server=$($rowSingle.ServerName),ServerIp=$serverIp,DL_Mbps=$($rowSingle.Download_Mbps),UL_Mbps=$($rowSingle.Upload_Mbps),Ping_ms=$($rowSingle.PingMs),Jitter_ms=$($rowSingle.JitterMs),Loss_pct=$($rowSingle.PacketLoss),Link_Mbps=$nicMbps,Util_DL=$dlUtil,Util_UL=$ulUtil"
        $srvTargets=@()
        if($gw){$srvTargets+=$gw}
        if($firstPub){$srvTargets+=$firstPub}
        $srvTargets+=@("1.1.1.1","8.8.8.8")
        if($serverIp){ $srvTargets+=$serverIp }
        $srvTargets=$srvTargets | Select-Object -Unique
        $pingResults = @()
        $pingIdx = 0
        foreach($t in $srvTargets){
            $pingIdx++
            Show-Progress -Activity "Ping Tests" -Status "Pinging $t ($pingIdx/$($srvTargets.Count))" -PercentComplete ([int](($pingIdx/$srvTargets.Count)*100))
            try{
                $p=Measure-Ping -Target $t -Count $PingCount
                Write-CsvContent -Path $PingCsv -Value (($p.Timestamp,$p.Target,$p.Sent,$p.Received,$p.LossPct,$p.MinMs,$p.AvgMs,$p.MaxMs) -join ",")
                $pingResults += $p
                $script:allPingResults += $p
                $lossColor = if($p.LossPct -eq 0){'Green'}elseif($p.LossPct -lt 5){'Yellow'}else{'Red'}
                $avgColor = if($p.AvgMs -lt 30){'Green'}elseif($p.AvgMs -lt 100){'Yellow'}else{'Red'}
                Write-Host "-> ${t}: Avg=$($p.AvgMs)ms, Loss=$($p.LossPct)%, Min/Max=$($p.MinMs)/$($p.MaxMs)ms" -ForegroundColor $avgColor
                Write-Log "PING,Target=$($p.Target),Avg_ms=$($p.AvgMs),Loss_pct=$($p.LossPct),Min_ms=$($p.MinMs),Max_ms=$($p.MaxMs)"
            }catch{
                Write-Log "ERROR,Ping failed target $t $_"
            }
        }
        Show-Progress -Activity "Ping Tests" -Completed
        $traceTarget=$serverIp
        if(-not $traceTarget){ $traceTarget=$rowSingle.ServerName }
        try{
            $tr=Invoke-Traceroute -Target $traceTarget
            Write-Log "TRACE,Target=$($tr.Target),HopCount=$($tr.HopCount),Hops=$($tr.Hops)"
        }catch{
            Write-Log "ERROR,Trace failed $($rowSingle.ServerName) $_"
        }

        $statusIcon = '✅'
        if(($pingResults | Where-Object LossPct -gt 5)) { $statusIcon = '❌' }
        elseif(($pingResults | Where-Object LossPct -gt 1)) { $statusIcon = '⚠️' }
        $summary="SUMMARY,Server=$($rowSingle.ServerName),DL_Mbps=$($rowSingle.Download_Mbps),UL_Mbps=$($rowSingle.Upload_Mbps),Ping_ms=$($rowSingle.PingMs),Jitter_ms=$($rowSingle.JitterMs),Loss_pct=$($rowSingle.PacketLoss),Status=$statusIcon"
        Write-Log $summary
    }

    $avgDown   = [math]::Round(($speedResults | Measure-Object Download_Mbps -Average).Average,2)
    $avgUp     = [math]::Round(($speedResults | Measure-Object Upload_Mbps -Average).Average,2)
    $avgPing   = [math]::Round(($speedResults | Measure-Object PingMs -Average).Average,2)
    $avgJitter = [math]::Round(($speedResults | Measure-Object JitterMs -Average).Average,2)
    $avgLoss   = [math]::Round(($speedResults | Measure-Object PacketLoss -Average).Average,2)

    Write-Host "`n*** AVERAGE OF $($speedResults.Count) SERVERS ***" -ForegroundColor Black -BackgroundColor Green
    Write-Host "DOWNLOAD AVG: $avgDown Mbps" -ForegroundColor Green
    Write-Host "UPLOAD   AVG: $avgUp Mbps"   -ForegroundColor Green
    Write-Host "PING     AVG: $avgPing ms (Jitter $avgJitter ms)" -ForegroundColor White
    Write-Host "PACKET LOSS AVG: $avgLoss %" -ForegroundColor $(if($avgLoss -eq 0){'Green'}else{'Red'})

    if($speedResults.Count -gt 1) {
        $avgRow = $speedResults[0] | Select-Object *
        $avgRow.Timestamp = (Get-Date).ToString("s")
        $avgRow.ServerName = "AVG_OF_$($speedResults.Count)"
        $avgRow.ServerId = "MULTI"
        $avgRow.Download_Mbps = $avgDown
        $avgRow.Upload_Mbps = $avgUp
        $avgRow.PingMs = $avgPing
        $avgRow.JitterMs = $avgJitter
        $avgRow.PacketLoss = $avgLoss
        $avgLine = ($avgRow.Timestamp,$avgRow.ISP,$avgRow.ExternalIp,$avgRow.NicInternalIp,$avgRow.NicName,$avgRow.NicMac,$avgRow.NicIsVpn,$avgRow.ServerName,$avgRow.ServerLocation,$avgRow.ServerId,$avgRow.PingMs,$avgRow.JitterMs,$avgRow.PacketLoss,$avgRow.Download_Mbps,$avgRow.Upload_Mbps,$nicSpeed,$gw,$firstPub) -join ","
        Write-CsvContent -Path $SpeedCsv -Value $avgLine
        $dlUtilAvg = if($nicMbps){ [math]::Round(($avgDown / $nicMbps)*100,1) } else { '' }
        $ulUtilAvg = if($nicMbps){ [math]::Round(($avgUp / $nicMbps)*100,1) } else { '' }

        $bundle = 0
        Write-Log "SPEED_AVG,Servers=$($speedResults.Count),DL_Mbps=$avgDown,UL_Mbps=$avgUp,Ping_ms=$avgPing,Jitter_ms=$avgJitter,Loss_pct=$avgLoss,Link_Mbps=$nicMbps,Util_DL=$dlUtilAvg,Util_UL=$ulUtilAvg"
    }
    
    
    $traceStamp=Join-Path $OutRoot "trace.last"
    $doTrace=$true
    if(Test-Path $traceStamp){
        $last=(Get-Content $traceStamp | Select-Object -First 1) -as [datetime]
        if($last -and ((Get-Date)-$last).TotalMinutes -lt $TraceEveryMinutes){$doTrace=$false}
    }
    
    $script:traceResults = @()
    if($doTrace){
        Write-Host "`n--- TRACEROUTE TESTS ---" -ForegroundColor Yellow
        Ensure-CsvHeader -Path $TraceCsv -Header "Timestamp,Target,HopCount,Hops"
        
        $traceTargets = @("1.1.1.1")
        if($speedResults.Count -gt 0 -and $speedResults[0].ServerIp) {
            $traceTargets += $speedResults[0].ServerIp
        }

        $uniqueTargets = $traceTargets | Select-Object -Unique
        foreach($tt in $uniqueTargets){
            try{
                $tr=Invoke-Traceroute -Target $tt
                $script:traceResults += $tr
                Write-CsvContent -Path $TraceCsv -Value (($tr.Timestamp,$tr.Target,$tr.HopCount,$tr.Hops) -join ",")
                Write-Log "TRACE,Target=$($tr.Target),HopCount=$($tr.HopCount),Hops=$($tr.Hops)"
            }catch{
                Write-Log "ERROR,Traceroute failed for target ${tt}: $($_.Exception.Message)"
                Write-Host "Traceroute to ${tt}: FAILED" -ForegroundColor Red
            }
        }
        
        (Get-Date).ToString("s") | Out-File -FilePath $traceStamp -Encoding ASCII -Force
    } else {
        Write-Host "`nSkipping traceroute (last run was less than $TraceEveryMinutes minutes ago)" -ForegroundColor Gray
    }
    
    Show-FinalSummary
    
    if($script:traceResults.Count -gt 0){
        Write-Host ""
        Write-Host "TRACEROUTE DETAILS:" -ForegroundColor Yellow
        foreach($tr in $script:traceResults){
            Write-Host "  Route to $($tr.Target) ($($tr.HopCount) hops):" -ForegroundColor Cyan
            if($tr.HopDetails -and $tr.HopDetails.Count -gt 0){
                foreach($hop in $tr.HopDetails){
                    $latencyDisplay = if($hop.Latency -eq 'timeout'){'  *  '}else{('{0,3}ms' -f $hop.Latency)}
                    $ipDisplay = $hop.IP.PadRight(16)
                   
                    $label = ''
                    if($hop.Hop -eq 1){ $label = '(Gateway)' }
                    elseif($hop.IP -eq $tr.Target){ $label = '(Destination)' }
                    elseif($hop.IP -match '^10\.|^192\.168\.|^172\.(1[6-9]|2[0-9]|3[0-1])\.'){ $label = '(Private)' }
                    
                    $hopColor = if($hop.Latency -eq 'timeout'){'DarkGray'}elseif([int]$hop.Latency -gt 50){'Yellow'}else{'White'}
                    Write-Host "    $($hop.Hop.ToString().PadLeft(2)). $ipDisplay $latencyDisplay  $label" -ForegroundColor $hopColor
                }
            } else {
                Write-Host "    $($tr.Hops)" -ForegroundColor Gray
            }
        }
    }
    
    Write-Host "`nData saved to: $OutRoot" -ForegroundColor Gray
    
}catch{
    Write-Host "`nERROR: Test failed - $($_.Exception.Message)" -ForegroundColor Red -BackgroundColor Black
    Write-Log "FATAL,$($_.Exception.Message)"
    throw
}

exit 0
