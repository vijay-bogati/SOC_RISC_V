/***************************************************************
 Project name                  : ADR SoC
 File Name                     : adr_tb_i2c_dev.sv
 Module/class Name             : adr_tb_i2c_dev
 Author                        : Vijay Bogati
 Description                   : Testbench model of an I2C device with a one-byte register, for simulation only
***************************************************************/

// ADR SoC - testbench model of an I2C device with a one-byte register, for simulation only.
// A write stores the byte, and a read returns it. Other addresses get no acknowledge.
// The model samples the bus with the system clock, so SCL must be much slower than clk_i.
// sda_low_o pulls the line low; otherwise the line is released.

module adr_tb_i2c_dev #(
  parameter logic [6:0] DeviceAddr = 7'h50
) (
  input  logic clk_i,
  input  logic rst_ni,
  input  logic scl_i,
  input  logic sda_i,
  output logic sda_low_o
);

  typedef enum logic [2:0] { Idle, Address, AckDrive, AckHold, WriteByte, ReadByte, ReadAck, ReadNext }
    state_e;

  state_e     state;
  logic [7:0] data, shift;
  logic [3:0] count;
  logic       is_read;

  logic scl_q, scl_d, sda_q, sda_d;
  logic scl_rise, scl_fall, start_bit, stop_bit;
  assign scl_rise  = scl_q && !scl_d;
  assign scl_fall  = !scl_q && scl_d;
  assign start_bit = scl_q && scl_d && !sda_q && sda_d;
  assign stop_bit  = scl_q && scl_d && sda_q && !sda_d;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      scl_q     <= 1'b1;
      scl_d     <= 1'b1;
      sda_q     <= 1'b1;
      sda_d     <= 1'b1;
      state     <= Idle;
      sda_low_o <= 1'b0;
      data      <= 8'h00;
      shift     <= 8'h00;
      count     <= '0;
      is_read   <= 1'b0;
    end else begin
      scl_q <= scl_i;
      scl_d <= scl_q;
      sda_q <= sda_i;
      sda_d <= sda_q;

      if (start_bit) begin
        state     <= Address;
        count     <= '0;
        sda_low_o <= 1'b0;
      end else if (stop_bit) begin
        state     <= Idle;
        sda_low_o <= 1'b0;
      end else begin
        unique case (state)
          Idle: ;
          Address: if (scl_rise) begin
            shift <= {shift[6:0], sda_q};
            count <= count + 4'd1;
            if (count == 4'd7) begin
              is_read <= sda_q;
              state   <= (shift[6:0] == DeviceAddr) ? AckDrive : Idle;
            end
          end
          AckDrive: if (scl_fall) begin
            sda_low_o <= 1'b1;
            state     <= AckHold;
          end
          AckHold: if (scl_fall) begin
            if (is_read) begin
              sda_low_o <= !data[7];
              shift     <= {data[6:0], 1'b0};
              count     <= 4'd1;
              state     <= ReadByte;
            end else begin
              sda_low_o <= 1'b0;
              count     <= '0;
              state     <= WriteByte;
            end
          end
          WriteByte: if (scl_rise) begin
            shift <= {shift[6:0], sda_q};
            count <= count + 4'd1;
            if (count == 4'd7) begin
              data    <= {shift[6:0], sda_q};
              is_read <= 1'b0;
              state   <= AckDrive;
            end
          end
          ReadByte: if (scl_fall) begin
            if (count == 4'd8) begin
              sda_low_o <= 1'b0;  // release for the master's acknowledge
              state     <= ReadAck;
            end else begin
              sda_low_o <= !shift[7];
              shift     <= {shift[6:0], 1'b0};
              count     <= count + 4'd1;
            end
          end
          ReadAck: if (scl_rise) begin
            state <= sda_q ? Idle : ReadNext;  // a high level means no acknowledge
          end
          ReadNext: if (scl_fall) begin
            sda_low_o <= !data[7];
            shift     <= {data[6:0], 1'b0};
            count     <= 4'd1;
            state     <= ReadByte;
          end
          default: state <= Idle;
        endcase
      end
    end
  end

endmodule
