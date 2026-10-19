param(
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\test_fmc'),
    [string]$Python = 'F:\OliverS\AI_Embedded\stm32-fpga-mcp\.venv\Scripts\python.exe'
)
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$rtl = @(Get-ChildItem (Join-Path $root 'src\rtl') -Recurse -Filter '*.v' -File |
    Select-Object -ExpandProperty FullName)
$exe = Join-Path $OutputDirectory 'dual_fmc.vvp'
& $Python -E (Join-Path $PSScriptRoot 'make_fmc_vectors.py') (Join-Path $OutputDirectory 'vectors')
if ($LASTEXITCODE -ne 0) { throw 'Fixture generation failed.' }
& iverilog -g2012 -s tb_dual_fmc -I (Join-Path $root 'src\rtl\common') `
    -o $exe @rtl (Join-Path $root 'sim\tb_dual_fmc.sv') `
    (Join-Path $root 'sim\two_channel_spi_slave_model.sv')
if ($LASTEXITCODE -ne 0) { throw 'Dual FMC compile failed.' }
& vvp $exe "+MC_GOLDEN_DIR=$OutputDirectory/vectors" "+OUT=$OutputDirectory"
if ($LASTEXITCODE -ne 0) { throw 'Dual FMC test failed.' }
