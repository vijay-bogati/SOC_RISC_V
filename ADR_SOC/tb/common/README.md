# tb/common/

`adr_tb_pkg.sv`: every constant used by the Verilator bench top and board (`tb_top.sv`,
`tb_adr_soc.sv`), in one place: clocks and reset, and the settings of the board models. The UVM bench
uses it too. The device models (SPI memory, I2C device, USB host, OTP macro) keep their own constants,
so each can be reused without this package.
