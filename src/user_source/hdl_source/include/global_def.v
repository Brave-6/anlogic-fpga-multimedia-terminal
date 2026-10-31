


`define   DATA_WIDTH                        32
`define   ADDR_WIDTH                        21
`define   DM_WIDTH                          4

`define   ROW_WIDTH                        11
`define   BA_WIDTH                        2

// Keep each macro expression grouped: without parentheses the nested
// division expands left-to-right and truncates the refresh interval to 0.
`define   SDR_CLK_PERIOD                    (1000000000 / 40000000)
// Reserve 1 ms of the SDRAM's 64 ms / 2048-row refresh window for
// arbitration delay. The counter includes both 0 and the terminal count:
// 1229 gives 1230 clocks = 30.75 us at 40 MHz, a nominal 62.976 ms sweep.
`define   SELF_REFRESH_INTERVAL             ((63000000 / `SDR_CLK_PERIOD / (2 ** `ROW_WIDTH)) - 1)

