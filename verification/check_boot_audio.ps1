param([string]$BuildRoot=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
$hdl=Join-Path $BuildRoot 'src\user_source\hdl_source'
$v=Join-Path $BuildRoot 'verification'
foreach($test in @('tb_boot_audio_delay','tb_boot_audio_real_pcm')){
 $binary=Join-Path $v ($test+'.vvp')
 & 'D:\iverlog\iverilog\bin\iverilog.exe' -g2012 -DSCENE_AUDIO_SIM -s $test -o $binary (Join-Path $v ($test+'.v')) (Join-Path $hdl 'scene_audio_i2s.v') (Join-Path $hdl 'I2S_receiver.v')
 if($LASTEXITCODE -ne 0){throw ('Compile failed: '+$test)}
 $cwd=if($test -eq 'tb_boot_audio_delay'){Join-Path $v 'reference_tests'}else{$BuildRoot}
 Push-Location -LiteralPath $cwd
 try{$result=& 'D:\iverlog\iverilog\bin\vvp.exe' $binary 2>&1;$code=$LASTEXITCODE}finally{Pop-Location}
 $result | Out-File -LiteralPath (Join-Path $v ($test+'.log')) -Encoding UTF8
 if($code -ne 0 -or ($result -join "`n") -match 'ERROR|FATAL' -or ($result -join "`n") -notmatch 'PASS'){throw ('Test failed: '+$test+' '+$result)}
 $result
}
