/***************************************************************
 Project name                  : ADR SoC
 File Name                     : adr_tb_spi_mem.sv
 Module/class Name             : adr_tb_spi_mem
 Author                        : Vijay Bogati
 Description                   : Testbench model of a small SPI memory, for simulation only
***************************************************************/

// Commands, each followed by what the master sends or reads:
//   0x9F  read 3-byte device ID
//   0x03  3-byte address, then read data
//   0x02  3-byte address, then write data
// quad_i selects four data lines for all phases, otherwise one line.
// SPI mode 0: inputs are sampled on the rising edge of sclk, outputs change on the falling edge.
// The model samples sclk with the system clock, so sclk must be slow enough to see each edge.

module adr_tb_spi_mem #(
  parameter logic [23:0] DeviceId = 24'h000000
) (
  input  logic       clk_i,
  input  logic       rst_ni,
  input  logic       csn_i,
  input  logic       sclk_i,
  input  logic       quad_i,
  input  logic [3:0] sdo_i,  // from the master
  output logic [3:0] sdi_o   // to the master
);

  typedef enum logic [2:0] { Command, Address, WriteData, ReadData, ReadId, Ignore } phase_e;

  localparam int unsigned MemBytes = 256;

  phase_e      phase;
  logic [7:0]  mem [MemBytes];
  logic [7:0]  shift_in, shift_out;
  int unsigned bit_count;
  logic [23:0] addr;
  int unsigned addr_bytes, id_index;
  logic [7:0]  command;
  logic        sclk_d;
  logic [3:0]  sdi_q;

  logic rise, fall;
  assign rise = sclk_i && !sclk_d;
  assign fall = !sclk_i && sclk_d;

  // Value of the input byte once this edge's bits are included.
  int unsigned step;
  logic [7:0]  next_in;
  assign step    = quad_i ? 4 : 1;
  assign next_in = quad_i ? {shift_in[3:0], sdo_i} : {shift_in[6:0], sdo_i[0]};

  assign sdi_o = csn_i ? 4'b0000 : sdi_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      sclk_d <= 1'b0;
    end else begin
      sclk_d <= sclk_i;
    end
  end

  always_ff @(posedge clk_i) begin
    if (!rst_ni || csn_i) begin
      phase      <= Command;
      bit_count  <= 0;
      addr_bytes <= 0;
      id_index   <= 0;
      sdi_q      <= 4'b0000;
    end else begin
      if (rise && (phase == Command || phase == Address || phase == WriteData)) begin
        shift_in <= next_in;
        if (bit_count + step == 8) begin
          bit_count <= 0;
          unique case (phase)
            Command: begin
              command <= next_in;
              unique case (next_in)
                8'h9F:         phase <= ReadId;
                8'h03, 8'h02:  phase <= Address;
                default:       phase <= Ignore;
              endcase
            end
            Address: begin
              addr <= {addr[15:0], next_in};
              addr_bytes <= addr_bytes + 1;
              if (addr_bytes == 2) phase <= (command == 8'h02) ? WriteData : ReadData;
            end
            WriteData: begin
              mem[addr[7:0]] <= next_in;
              addr <= addr + 24'd1;
            end
            default: ;
          endcase
        end else begin
          bit_count <= bit_count + step;
        end
      end

      if (fall && (phase == ReadData || phase == ReadId)) begin
        logic [7:0] out;
        if (bit_count == 0) begin
          if (phase == ReadId) begin
            out = DeviceId[23 - 8*id_index[1:0] -: 8];
            id_index <= id_index + 1;
          end else begin
            out = mem[addr[7:0]];
            addr <= addr + 24'd1;
          end
        end else begin
          out = shift_out;
        end
        if (quad_i) begin
          sdi_q     <= out[7:4];
          shift_out <= {out[3:0], 4'b0000};
        end else begin
          sdi_q     <= {2'b00, out[7], 1'b0};  // single-line data is on line 1
          shift_out <= {out[6:0], 1'b0};
        end
        bit_count <= (bit_count + step == 8) ? 0 : bit_count + step;
      end
    end
  end

endmodule
