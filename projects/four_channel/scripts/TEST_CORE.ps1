param([string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'test_output'))
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if (Test-Path -LiteralPath $OutputDirectory) { throw 'Test output must be a new directory.' }
New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
$rtl = @(Get-ChildItem (Join-Path $root 'src\rtl') -Recurse -File -Filter '*.v' | Select-Object -ExpandProperty FullName)
$tests = @('tb_four_channel_record_mux','tb_record_fifo_bram','tb_block_pingpong_bram',
    'tb_four_channel_capture_core','tb_four_channel_bridge_core')
foreach ($test in $tests) {
    $exe = Join-Path $OutputDirectory "$test.vvp"
    & iverilog -g2012 -s $test -I (Join-Path $root 'src\rtl\common') -o $exe @rtl `
        (Join-Path $root "sim\$test.sv") (Join-Path $root 'sim\two_channel_spi_slave_model.sv')
    if ($LASTEXITCODE -ne 0) { throw "Compile failed: $test" }
    & vvp $exe "+MC_GOLDEN_DIR=$root/sim/vectors" `
        "+MC_CAPTURE=$OutputDirectory/capture.csv" "+MC_BLOCK_CAPTURE=$OutputDirectory/blocks.csv"
    if ($LASTEXITCODE -ne 0) { throw "Test failed: $test" }
}
Write-Host 'CORE_RTL_TESTS_OK'
