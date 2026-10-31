param([string]$TdExe='D:\FPGA\bin\td_commands_prompt.exe')
$ErrorActionPreference='Stop'
$projectRoot=Split-Path -Parent $PSScriptRoot
if(!(Test-Path -LiteralPath $TdExe)){throw ('TD executable not found: '+$TdExe)}
foreach($stage in @('syn_1','phy_1')){
    $stageDir=Join-Path $projectRoot ('src\td_project\HDMI1.4b_Transmitter_v1.0_Runs\'+$stage)
    Push-Location -LiteralPath $stageDir
    try{
        & $TdExe 'HDMI1.4b_Transmitter_v1.0.tcl'
        if($LASTEXITCODE -ne 0){throw ('TD stage failed: '+$stage)}
        if($stage -eq 'syn_1' -and !(Test-Path -LiteralPath '.opt_gate.end.f')){throw 'Synthesis completion marker missing'}
        if($stage -eq 'phy_1' -and !(Test-Path -LiteralPath '.bitgen.end.f')){throw 'Bit generation completion marker missing'}
    }finally{Pop-Location}
}
Write-Output 'Rebuilt bit is in src/td_project/HDMI1.4b_Transmitter_v1.0_Runs/phy_1. Existing release bit was not replaced. Revalidate each new build.'
