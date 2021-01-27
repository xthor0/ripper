# start stopwatch
$sw = [Diagnostics.Stopwatch]::StartNew()
$start = Get-Date

$csvrecords = [System.Collections.ArrayList]@()
#$null = $csvrecords.Add("SourceFile,Preset,FPS,SourceSize,OutputSize")
$header = [pscustomobject]@{
    SourceFile = ''
    Encoder = ''
    FPS = ''
    SourceSize = ''
    OutputSize = ''
    Seconds = ''
    Decrease = ''
}
$null = $csvrecords.Add($header)

$myhostname = [System.Net.Dns]::GetHostName()

# create output directories
if(-not(Test-Path -Path .\output)) { New-Item -Path . -ItemType Directory -Name output }
if(-not(Test-Path -Path .\output\log)) { New-Item -Path .\output -ItemType Directory -Name log }

# define array of encoders
# software only = x264, x265
# intel = qsv_h264, qsv_h265
# nvidia = nvenc_h264, nvenc_h265
$encoders = @("nvenc_h264", "nvenc_h265", "x264", "x265")

foreach ($encoder in $encoders) {
    # write the output files to a directory named after the preset, so we can keep track of all this crap
    Write-Host "Encoder: $($encoder)"
    if(-not(Test-Path -Path .\output\$encoder)) { New-Item -Path .\output -ItemType Directory -Name $encoder }

    # there are specific encoder presets that only work with certain types of encoders. We need to decide which to use here.
    switch -Wildcard ($encoder){
        "x26*" {$encoderPreset = "veryfast"}
        "qsv_*" {$encoderPreset = "speed"}
        "nvenc_*" {$encoderPreset = "fast"}
        Default {
            Write-Error "Encoder preset not set."
            exit
        }
    }

    $files = Get-ChildItem .\sources\*.mkv
    foreach ($file in $files) {
        Write-Host "Source file: $($file)"
        $newFile = $file | ForEach-Object {$_.BaseName}
        $newFileName = ".\output\$encoder\$newFile.mkv"
        $log = ".\output\log\$newFile-$encoder.log"
        Write-Host "Encoding to: $($newFileName)"
        $before = [math]::Round($sw.Elapsed.TotalSeconds,0)
        & .\HandBrakeCLI.exe -E ac3 -B 384 -6 5point1 -e $encoder --encoder-preset $encoderPreset -q 21 -i $file -o $newFileName 2> "$log"

        if($LASTEXITCODE -ne 0) {
            Write-Host -NoNewline -ForegroundColor Red "ERROR: "
            Write-Host "HandBrake did not exit successfully."
            exit
        }
        $after = [math]::Round($sw.Elapsed.TotalSeconds,0)
        $elapsed = $after - $before

        Write-Host "HandBrake encode took $($elapsed) seconds."

        # we need some data to collect to benchmark
        $fpsRaw = Select-String -Pattern "average encoding speed" -Path $log
        $fpsArr = $fpsRaw.ToString().Split(" ")
        $fps = $fpsArr[-2]
        $sourceFileSize = Get-Item $file | ForEach-Object {[int]($_.length / 1mb)}
        $outputFileSize = Get-Item $newFileName | ForEach-Object {[int]($_.length / 1mb)}
        $decrease = ((($sourceFileSize - $outputFileSize)/$sourceFileSize) * 100)

        #$record = "$file,$preset_name,$fps,$sourceFileSize,$outputFileSize"
        $record = [pscustomobject]@{
            SourceFile = $file
            Encoder = $encoder
            FPS = $fps
            SourceSize = $sourceFileSize
            OutputSize = $outputFileSize
            Seconds = $elapsed
            Decrease = $decrease
        }
        $null = $csvrecords.Add($record)

        # during testing, exit early
        #$csvrecords | Export-Csv -Path .\output\results.csv
        #exit
    }
}

# write the output to a CSV file
$datestamp = get-date -Format "yyyy.MM.dd.ms"
$csvrecords | Export-Csv -Path .\results-$myhostname-$datestamp.csv

# stop stopwatch
$sw.Stop()

# build messages to tell whoever's looking about how long this took
$message1 = "Script started at $($start), completed at $(Get-Date)"
$message2 = "Elapsed time - $($sw.Elapsed.Hours) hours, $($sw.Elapsed.Minutes) minutes, $($sw.Elapsed.Seconds) seconds."

# output to screen
Write-Host $message1
Write-Host $message2

# send a Pushover message
$ApiKey = "a834zqzrfhxrsyfacgwg6squ7fg2p3"
$UserKey = "uiLUuynXsvF7UCQATr3j6j7pG7dGoh"
$Message = "HandBrakeCLI testing completed on $($myhostname)! $($message1) :: $($message2)"
$data = @{
	token = "$ApiKey";
	user = "$UserKey";
	message = "$Message"
}

<#
# just in case I need these...
if ($Device) { $data.Add("device", "$Device") }
if ($Title) { $data.Add("title", "$Title") }
if ($Url) { $data.Add("url", "$Url") }
if ($UrlTitle) { $data.Add("url_title", "$UrlTitle") }
if ($Priority) { $data.Add("priority", $Priority) }
if ($Sound) { $data.Add("sound", "$Sound") }
#>
Write-Host "Sending Pushover message..."
Invoke-RestMethod -Method Post -Uri "https://api.pushover.net/1/messages.json" -Body $data | Out-Null
Write-Host "Complete!"