param([string]$BuildRoot=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
$hdl=Join-Path $BuildRoot 'src\user_source\hdl_source'
$tests=Join-Path $BuildRoot 'verification\reference_tests'
$out=Join-Path $BuildRoot 'verification'
New-Item -ItemType Directory -Path $out -Force | Out-Null
function Run-Test([string]$top,[string[]]$sources,[string[]]$defines=@(),[string]$cwd=$tests){
 $args=@('-g2012','-I',$hdl,'-I',(Join-Path $hdl 'SD'),'-s',$top,'-o',(Join-Path $out ($top+'.vvp')))+$defines+$sources
 & 'D:\iverlog\iverilog\bin\iverilog.exe' @args
 if($LASTEXITCODE -ne 0){throw ($top+' compile failed')}
 Push-Location -LiteralPath $cwd
 try{$result=& 'D:\iverlog\iverilog\bin\vvp.exe' (Join-Path $out ($top+'.vvp')) 2>&1;$code=$LASTEXITCODE}finally{Pop-Location}
 $result | Out-File -LiteralPath (Join-Path $out ($top+'.log')) -Encoding UTF8
 if($code -ne 0 -or ($result -join "`n") -match 'ERROR|FATAL' -or ($result -join "`n") -notmatch 'PASS'){throw ($top+' failed: '+$result)}
 $result
}
$scene=Join-Path $hdl 'video_scene_transition.v'
Run-Test 'tb_video_scene_transition' @((Join-Path $tests 'tb_video_scene_transition.v'),$scene)
$sd=@('sd_card_bmp_scene.v','bmp_read.v','sd_card_top.v','sd_card_cmd.v','sd_card_sec_read_write.v','spi_master.v') | ForEach-Object{Join-Path $hdl ('SD\'+$_)}
Run-Test 'tb_scene_pipeline' (@((Join-Path $tests 'tb_scene_pipeline.v'),$scene)+$sd)
Run-Test 'tb_scene_frame_boundary' @((Join-Path $out 'tb_scene_frame_boundary.v'),$scene,(Join-Path $hdl 'SD\video_timing_data.v'),(Join-Path $hdl 'SD\color_bar.v'),(Join-Path $hdl 'SD\frame_fifo_read.v'))
Run-Test 'tb_bottom_osd' @((Join-Path $tests 'tb_bottom_osd.v'),(Join-Path $hdl 'video_bottom_osd.v'),(Join-Path $hdl 'osd\osd_bitmap_rom.v')) @('-DOSD_SIM') $hdl
Run-Test 'tb_scene_audio_chain' @((Join-Path $tests 'tb_scene_audio_chain.v'),(Join-Path $hdl 'scene_audio_i2s.v'),(Join-Path $hdl 'I2S_receiver.v')) @('-DSCENE_AUDIO_SIM')
Run-Test 'tb_scene_audio_i2s' @((Join-Path $tests 'tb_scene_audio_i2s.v'),(Join-Path $hdl 'scene_audio_i2s.v')) @('-DSCENE_AUDIO_SIM')
Run-Test 'tb_bmp_load_done_real' @((Join-Path $tests 'tb_bmp_load_done_real.v'),(Join-Path $hdl 'SD\bmp_read.v'))
Run-Test 'tb_bmp_abort_preserves_scan' @((Join-Path $tests 'tb_bmp_abort_preserves_scan.v'),(Join-Path $hdl 'SD\bmp_read.v'))
Run-Test 'tb_tf_fifo_fullframes_fix' @((Join-Path $out 'tb_tf_fifo_fullframes_fix.v'),(Join-Path $hdl 'SD\frame_fifo_write.v'),(Join-Path $hdl 'IP\afifo_16_32_256.v'))
