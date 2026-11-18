/***************************************************************
 Project name                  : ADR SoC
 File Name                     : adr_tb_usb_host.sv
 Module/class Name             : adr_tb_usb_host
 Author                        : Vijay Bogati
 Description                   : Simple USB full-speed host for simulation. Not for synthesis
***************************************************************/

// ADR SoC - simple USB full-speed host for simulation. Not for synthesis.
// It runs one fixed sequence when the device connects: bus reset, start of frame, a SETUP
// transaction, an OUT transaction, then IN tokens until the device answers. It ACKs the IN data
// only if the CRC and the bytes are right, so software learns the result from the "sent" status.
// One bit lasts four clocks of clk_i. It works on the falling edge, so it can't race the device.

module adr_tb_usb_host (
  input  logic clk_i,
  input  logic rst_ni,
  input  logic connect_i,   // device pull-up on D+
  input  logic dp_i,        // bus state
  input  logic dn_i,
  input  logic dev_drive_i, // the device is driving the bus
  output logic drive_o,
  output logic dp_o,
  output logic dn_o
);

  localparam logic [7:0] PidOut = 8'hE1, PidIn = 8'h69, PidSof = 8'hA5, PidSetup = 8'h2D;
  localparam logic [7:0] PidData0 = 8'hC3, PidData1 = 8'h4B, PidAck = 8'hD2, PidNak = 8'h5A;

  int   ones;
  logic level;  // NRZI level: 1 is J

  task automatic idle(input int bits);
    drive_o = 1'b0;
    repeat (bits * 4) @(negedge clk_i);
  endtask

  task automatic line(input logic dp, input logic dn);
    drive_o = 1'b1;
    dp_o    = dp;
    dn_o    = dn;
    repeat (4) @(negedge clk_i);
  endtask

  task automatic send_bit(input logic b);
    if (!b) level = ~level;
    line(level, ~level);
    if (b) begin
      ones = ones + 1;
      if (ones == 6) begin
        ones  = 0;
        level = ~level;
        line(level, ~level);
      end
    end else begin
      ones = 0;
    end
  endtask

  task automatic send_byte(input logic [7:0] value);
    for (int i = 0; i < 8; i++) send_bit(value[i]);
  endtask

  task automatic start_packet(input logic [7:0] pid);
    level = 1'b1;
    ones  = 0;
    send_byte(8'h80);  // sync
    send_byte(pid);
  endtask

  task automatic end_packet();
    line(1'b0, 1'b0);
    line(1'b0, 1'b0);
    line(1'b1, 1'b0);
    drive_o = 1'b0;
  endtask

  function automatic logic [4:0] crc5(input logic [10:0] value);
    logic [4:0] crc = 5'h1F;
    for (int i = 0; i < 11; i++) begin
      logic feedback = value[i] ^ crc[4];
      crc = {crc[3:0], 1'b0};
      if (feedback) crc ^= 5'h05;
    end
    return ~crc;
  endfunction

  function automatic logic [15:0] crc16_add(input logic [15:0] crc_in, input logic [7:0] value);
    logic [15:0] crc = crc_in;
    for (int i = 0; i < 8; i++) begin
      logic feedback = value[i] ^ crc[15];
      crc = {crc[14:0], 1'b0};
      if (feedback) crc ^= 16'h8005;
    end
    return crc;
  endfunction

  task automatic send_token(input logic [7:0] pid, input logic [10:0] value);
    logic [4:0] crc = crc5(value);
    start_packet(pid);
    for (int i = 0; i < 11; i++) send_bit(value[i]);
    for (int i = 4; i >= 0; i--) send_bit(crc[i]);
    end_packet();
  endtask

  task automatic send_data(input logic [7:0] pid, input logic [7:0] first, input int len);
    logic [15:0] crc = 16'hFFFF;
    start_packet(pid);
    for (int i = 0; i < len; i++) begin
      logic [7:0] value = first + 8'(i);
      send_byte(value);
      crc = crc16_add(crc, value);
    end
    crc = ~crc;
    for (int i = 15; i >= 0; i--) send_bit(crc[i]);
    end_packet();
  endtask

  // Receives one packet from the device into rx_bytes. Returns 0 bytes if none arrives in time.
  logic [7:0] rx_bytes [0:80];
  int         rx_len;

  task automatic receive_packet();
    int   wait_count = 0;
    logic last       = 1'b0;
    int   rx_ones    = 0;
    int   bit_count  = 1;  // the first sync bit is the K that the wait below sees
    logic now, decoded, done;
    logic [7:0] shift = '0;
    rx_len = 0;
    while (!(dev_drive_i && !dp_i && dn_i) && wait_count <= 400) begin
      @(negedge clk_i);
      wait_count = wait_count + 1;
    end
    done = wait_count > 400;               // no answer
    if (!done) repeat (2) @(negedge clk_i);  // to the middle of the bit
    while (!done) begin
      repeat (4) @(negedge clk_i);
      if (!dp_i && !dn_i) begin            // end of packet
        done = 1'b1;
      end else begin
        now     = dp_i;
        decoded = (now == last);
        last    = now;
        if (rx_ones == 6) begin            // stuffed bit
          rx_ones = 0;
        end else begin
          rx_ones   = decoded ? rx_ones + 1 : 0;
          shift     = {decoded, shift[7:1]};
          bit_count = bit_count + 1;
          if (bit_count == 8) begin
            bit_count = 0;
            if (rx_len < 80) rx_bytes[rx_len] = shift;
            rx_len = rx_len + 1;
          end
        end
      end
    end
    while (dev_drive_i) @(negedge clk_i);
  endtask

  // Received byte 0 is sync and byte 1 is the PID, then the data and two CRC bytes.
  function automatic logic in_data_good(input logic [7:0] first, input int len);
    logic [15:0] crc = 16'hFFFF;
    if (rx_len != len + 4) return 1'b0;
    if (rx_bytes[1] != PidData0 && rx_bytes[1] != PidData1) return 1'b0;
    for (int i = 0; i < len; i++) begin
      if (rx_bytes[2 + i] != first + 8'(i)) return 1'b0;
      crc = crc16_add(crc, rx_bytes[2 + i]);
    end
    crc = ~crc;
    for (int i = 0; i < 8; i++) begin
      if (rx_bytes[2 + len][i]     != crc[15 - i]) return 1'b0;
      if (rx_bytes[2 + len + 1][i] != crc[7 - i])  return 1'b0;
    end
    return 1'b1;
  endfunction

  initial begin
    drive_o = 1'b0;
    dp_o    = 1'b1;
    dn_o    = 1'b0;
    wait (rst_ni);
    @(posedge connect_i);
    idle(200);

    // Bus reset: SE0 for 5 us, at 12 bits per us.
    repeat (60) line(1'b0, 1'b0);
    idle(200);

    send_token(PidSof, 11'h123);
    idle(100);

    // SETUP to endpoint 0, address 0.
    send_token(PidSetup, 11'h000);
    idle(4);
    send_data(PidData0, 8'h40, 8);
    receive_packet();
    idle(100);

    // OUT to endpoint 1.
    send_token(PidOut, 11'h080);
    idle(4);
    send_data(PidData0, 8'h60, 4);
    receive_packet();
    idle(100);

    // IN from endpoint 1, repeated until the device has data.
    for (int attempt = 0; attempt < 2000; attempt++) begin
      send_token(PidIn, 11'h080);
      receive_packet();
      if (rx_len > 1 && in_data_good(8'h10, 8)) begin
        idle(4);
        start_packet(PidAck);
        end_packet();
        break;
      end
      idle(200);
    end
    drive_o = 1'b0;
  end

endmodule
