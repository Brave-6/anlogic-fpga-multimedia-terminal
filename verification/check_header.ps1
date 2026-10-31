param([string]$BuildRoot=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
$test=Join-Path $BuildRoot 'verification\tb_bmp_header_validation.v'
$source=Join-Path $BuildRoot 'src\user_source\hdl_source\SD\bmp_read.v'
$binary=Join-Path $BuildRoot 'verification\header.vvp'
& 'D:\iverlog\iverilog\bin\iverilog.exe' -g2012 -s tb_bmp_header_validation -o $binary $test $source
if($LASTEXITCODE -ne 0){throw 'BMP header compile failed'}
$result=& 'D:\iverlog\iverilog\bin\vvp.exe' $binary 2>&1
$code=$LASTEXITCODE
$result | Out-File -LiteralPath (Join-Path $BuildRoot 'verification\header.log') -Encoding UTF8
if($code -ne 0 -or ($result -join "`n") -match 'ERROR|FATAL' -or ($result -join "`n") -notmatch 'PASS'){throw 'BMP header test failed'}
$result
