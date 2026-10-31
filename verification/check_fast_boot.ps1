param([string]$BuildRoot=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
$h=Join-Path $BuildRoot 'src\user_source\hdl_source'
$v=Join-Path $BuildRoot 'verification'
$binary=Join-Path $v 'fast_boot.vvp'
& 'D:\iverlog\iverilog\bin\iverilog.exe' -g2012 -s tb_fast_boot_scan -o $binary (Join-Path $v 'tb_fast_boot_scan.v') (Join-Path $h 'SD\bmp_read.v')
if($LASTEXITCODE -ne 0){throw 'Fast boot compile failed'}
Push-Location -LiteralPath $BuildRoot
try{$result=& 'D:\iverlog\iverilog\bin\vvp.exe' $binary 2>&1;$code=$LASTEXITCODE}finally{Pop-Location}
$result | Out-File -LiteralPath (Join-Path $v 'fast_boot.log') -Encoding UTF8
if($code -ne 0 -or ($result -join "`n") -match 'ERROR|FATAL' -or ($result -join "`n") -notmatch 'PASS recovery'){throw ('Fast boot failed: '+$result)}
$result
$binary=Join-Path $v 'fast_boot_pipeline.vvp'
$sd=@('sd_card_bmp_scene.v','bmp_read.v','sd_card_top.v','sd_card_cmd.v','sd_card_sec_read_write.v','spi_master.v') | ForEach-Object{Join-Path $h ('SD\'+$_)}
& 'D:\iverlog\iverilog\bin\iverilog.exe' -g2012 -s tb_fast_boot_pipeline -o $binary (Join-Path $v 'tb_fast_boot_pipeline.v') (Join-Path $h 'video_scene_transition.v') @sd
if($LASTEXITCODE -ne 0){throw 'Fast boot integration compile failed'}
Push-Location -LiteralPath $BuildRoot
try{$result=& 'D:\iverlog\iverilog\bin\vvp.exe' $binary 2>&1;$code=$LASTEXITCODE}finally{Pop-Location}
$result | Out-File -LiteralPath (Join-Path $v 'fast_boot_pipeline.log') -Encoding UTF8
if($code -ne 0 -or ($result -join "`n") -match 'ERROR|FATAL' -or ($result -join "`n") -notmatch 'PASS recovery integration'){throw ('Fast boot integration failed: '+$result)}
$result
