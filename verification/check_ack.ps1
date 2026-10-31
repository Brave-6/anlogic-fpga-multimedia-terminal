param([string]$BuildRoot=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
$h=Join-Path $BuildRoot 'src/user_source/hdl_source'
$sd=@('sd_card_bmp_scene.v','bmp_read.v','sd_card_top.v','sd_card_cmd.v','sd_card_sec_read_write.v','spi_master.v') | ForEach-Object { $h+'/SD/'+$_ }
$binary=Join-Path $BuildRoot 'verification/ack.vvp'
$test=Join-Path $BuildRoot 'verification/tb_sd_write_req_ack_cdc.v'
& 'D:/iverlog/iverilog/bin/iverilog.exe' -g2012 -s tb_sd_write_req_ack_cdc -o $binary $test @sd
if($LASTEXITCODE -ne 0){throw 'ACK compile failed'}
$result=& 'D:/iverlog/iverilog/bin/vvp.exe' $binary 2>&1
$code=$LASTEXITCODE
$result | Out-File -LiteralPath (Join-Path $BuildRoot 'verification/ack.log') -Encoding UTF8
if($code -ne 0 -or ($result -join "`n") -match 'ERROR|FATAL' -or ($result -join "`n") -notmatch 'PASS'){throw 'ACK test failed'}
$result
