/***************************************************************
 Project name                  : ADR SoC
 File Name                     : adr_aes.sv
 Module/class Name             : adr_aes
 Author                        : Vijay Bogati
 Description                   : AES block cipher with an APB register interface, written from FIPS-197
***************************************************************/

// ADR SoC - AES block cipher with an APB register interface, written from FIPS-197.
// Encrypts and decrypts one 128-bit block with a 128, 192 or 256-bit key.
// One round takes one clock. The key schedule is rebuilt at each start, one word per clock.
//
// Registers (32-bit). Key and data words are in FIPS-197 byte order: the first byte of a
// word is its most significant byte, and word 0 comes first.
//   0x00 CTRL     [0] start (write 1), [1] decrypt, [3:2] key size: 0 = 128, 1 = 192, 2 = 256
//   0x04 STATUS   [0] busy, [1] done (write 1 to clear)
//   0x08 IRQ_EN   [0] interrupt when done
//   0x10-0x2C KEY[0-7], write-only
//   0x30-0x3C IN[0-3]
//   0x40-0x4C OUT[0-3], read-only

module adr_aes (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic        psel_i,
  input  logic        penable_i,
  input  logic        pwrite_i,
  input  logic [6:0]  paddr_i,
  input  logic [31:0] pwdata_i,
  output logic [31:0] prdata_o,
  output logic        pready_o,
  output logic        pslverr_o,
  output logic        irq_o
);

  typedef enum logic [1:0] { Idle, Expand, Rounds } state_e;

  state_e       state_q;
  logic [31:0]  key_q [8];
  logic [31:0]  in_q [4];
  logic [127:0] state_block_q;
  logic [31:0]  schedule_q [60];
  logic [5:0]   word_q;      // next key schedule word
  logic [3:0]   round_q;
  logic [7:0]   rcon_q;
  logic         decrypt_q;
  logic [1:0]   key_size_q;
  logic         done_q, irq_en_q;

  logic write;
  assign write     = psel_i && penable_i && pwrite_i;
  assign pready_o  = 1'b1;
  assign pslverr_o = 1'b0;
  assign irq_o     = done_q && irq_en_q;

  // Key size: Nk words of key, Nr rounds.
  logic [3:0] nk, nr;
  always_comb begin
    unique case (key_size_q)
      2'd1:    begin nk = 4'd6; nr = 4'd12; end
      2'd2:    begin nk = 4'd8; nr = 4'd14; end
      default: begin nk = 4'd4; nr = 4'd10; end
    endcase
  end
  logic [5:0] schedule_words;
  assign schedule_words = 6'(4 * (int'(nr) + 1));

  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  // Byte functions
  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  function automatic logic [7:0] xtime(input logic [7:0] b);
    return {b[6:0], 1'b0} ^ (b[7] ? 8'h1B : 8'h00);
  endfunction

  function automatic logic [7:0] mul(input logic [7:0] b, input logic [3:0] factor);
    logic [7:0] x2 = xtime(b);
    logic [7:0] x4 = xtime(x2);
    logic [7:0] x8 = xtime(x4);
    return (factor[0] ? b : 8'h00) ^ (factor[1] ? x2 : 8'h00) ^
           (factor[2] ? x4 : 8'h00) ^ (factor[3] ? x8 : 8'h00);
  endfunction

  function automatic logic [31:0] mix_column(input logic [31:0] c);
    logic [7:0] a = c[31:24], b = c[23:16], d = c[15:8], e = c[7:0];
    return { mul(a, 4'd2) ^ mul(b, 4'd3) ^ d ^ e,
             a ^ mul(b, 4'd2) ^ mul(d, 4'd3) ^ e,
             a ^ b ^ mul(d, 4'd2) ^ mul(e, 4'd3),
             mul(a, 4'd3) ^ b ^ d ^ mul(e, 4'd2) };
  endfunction

  function automatic logic [31:0] inv_mix_column(input logic [31:0] c);
    logic [7:0] a = c[31:24], b = c[23:16], d = c[15:8], e = c[7:0];
    return { mul(a, 4'd14) ^ mul(b, 4'd11) ^ mul(d, 4'd13) ^ mul(e, 4'd9),
             mul(a, 4'd9)  ^ mul(b, 4'd14) ^ mul(d, 4'd11) ^ mul(e, 4'd13),
             mul(a, 4'd13) ^ mul(b, 4'd9)  ^ mul(d, 4'd14) ^ mul(e, 4'd11),
             mul(a, 4'd11) ^ mul(b, 4'd13) ^ mul(d, 4'd9)  ^ mul(e, 4'd14) };
  endfunction

  // A block is columns 0-3 from the most significant word; each column holds rows 0-3.
  function automatic logic [127:0] shift_rows(input logic [127:0] s);
    return {s[127:120], s[87:80],   s[47:40],   s[7:0],
            s[95:88],   s[55:48],   s[15:8],    s[103:96],
            s[63:56],   s[23:16],   s[111:104], s[71:64],
            s[31:24],   s[119:112], s[79:72],   s[39:32]};
  endfunction

  function automatic logic [127:0] inv_shift_rows(input logic [127:0] s);
    return {s[127:120], s[23:16],   s[47:40],   s[71:64],
            s[95:88],   s[119:112], s[15:8],    s[39:32],
            s[63:56],   s[87:80],   s[111:104], s[7:0],
            s[31:24],   s[55:48],   s[79:72],   s[103:96]};
  endfunction

  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  // S-boxes: four for the block in each direction, one for the key schedule
  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  logic [127:0] sub_bytes_out, inv_sub_bytes_in, inv_sub_bytes_out;
  logic [31:0]  key_sbox_in, key_sbox_out;

  for (genvar c = 0; c < 4; c++) begin : gen_block_sbox
    aes_sbox i_sbox (
      .sboxw     ( state_block_q[32*c +: 32] ),
      .new_sboxw ( sub_bytes_out[32*c +: 32] )
    );
    aes_inv_sbox i_inv_sbox (
      .sboxw     ( inv_sub_bytes_in[32*c +: 32]  ),
      .new_sboxw ( inv_sub_bytes_out[32*c +: 32] )
    );
  end

  aes_sbox i_key_sbox (
    .sboxw     ( key_sbox_in  ),
    .new_sboxw ( key_sbox_out )
  );

  assign inv_sub_bytes_in = inv_shift_rows(state_block_q);

  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  // Key schedule, FIPS-197 section 5.2
  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  logic [31:0] previous_word, next_key_word;
  logic [5:0]  words_since_rcon;
  logic        rcon_step, extra_sub;

  assign previous_word    = schedule_q[word_q - 6'd1];
  assign words_since_rcon = 6'(int'(word_q) % int'(nk));
  assign rcon_step        = (words_since_rcon == 6'd0);
  assign extra_sub        = (nk == 4'd8) && (words_since_rcon == 6'd4);
  assign key_sbox_in      = rcon_step ? {previous_word[23:0], previous_word[31:24]} : previous_word;

  always_comb begin
    logic [31:0] temp;
    if (rcon_step)      temp = key_sbox_out ^ {rcon_q, 24'h0};
    else if (extra_sub) temp = key_sbox_out;
    else                temp = previous_word;
    next_key_word = schedule_q[word_q - 6'(nk)] ^ temp;
  end

  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  // Rounds. round_q counts from 1 to Nr in both directions.
  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  function automatic logic [127:0] round_key(input logic [5:0] round_index);
    logic [5:0] w = 6'(4 * int'(round_index));
    return {schedule_q[w], schedule_q[w + 6'd1], schedule_q[w + 6'd2], schedule_q[w + 6'd3]};
  endfunction

  // always_comb, not assign, wherever round_key() is used: it reads schedule_q, and an assign
  // would not re-evaluate when only schedule_q changes.
  logic         last_round;
  logic [127:0] enc_shifted, enc_mixed, enc_next, dec_keyed, dec_next;
  logic [5:0]   dec_key_index;

  assign last_round    = (round_q == nr);
  assign enc_shifted   = shift_rows(sub_bytes_out);
  assign enc_mixed     = {mix_column(enc_shifted[127:96]), mix_column(enc_shifted[95:64]),
                          mix_column(enc_shifted[63:32]), mix_column(enc_shifted[31:0])};
  always_comb enc_next = (last_round ? enc_shifted : enc_mixed) ^ round_key(6'(round_q));
  assign dec_key_index = 6'(int'(nr) - int'(round_q));
  always_comb dec_keyed = inv_sub_bytes_out ^ round_key(dec_key_index);
  assign dec_next      = last_round ? dec_keyed :
                         {inv_mix_column(dec_keyed[127:96]), inv_mix_column(dec_keyed[95:64]),
                          inv_mix_column(dec_keyed[63:32]), inv_mix_column(dec_keyed[31:0])};

  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  // Control and registers
  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  logic [127:0] first_key;
  always_comb first_key = decrypt_q ? round_key(6'(nr)) : round_key(6'd0);

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q       <= Idle;
      state_block_q <= '0;
      word_q        <= '0;
      round_q       <= '0;
      rcon_q        <= 8'h01;
      decrypt_q     <= 1'b0;
      key_size_q    <= '0;
      done_q        <= 1'b0;
      irq_en_q      <= 1'b0;
      for (int i = 0; i < 8; i++)  key_q[i] <= '0;
      for (int i = 0; i < 4; i++)  in_q[i] <= '0;
      for (int i = 0; i < 60; i++) schedule_q[i] <= '0;
    end else begin
      // Register writes. A start is ignored while busy.
      if (write) begin
        if (paddr_i == 7'h04 && pwdata_i[1]) done_q <= 1'b0;
        if (paddr_i == 7'h08) irq_en_q <= pwdata_i[0];
        if (paddr_i >= 7'h10 && paddr_i <= 7'h2C) key_q[3'(paddr_i[4:2] - 3'd4)] <= pwdata_i;
        if (paddr_i >= 7'h30 && paddr_i <= 7'h3C) in_q[paddr_i[3:2]] <= pwdata_i;
      end

      unique case (state_q)
        Idle: if (write && paddr_i == 7'h00 && pwdata_i[0]) begin
          decrypt_q  <= pwdata_i[1];
          key_size_q <= (pwdata_i[3:2] == 2'd3) ? 2'd0 : pwdata_i[3:2];
          for (int i = 0; i < 8; i++) schedule_q[i] <= key_q[i];
          word_q  <= (pwdata_i[3:2] == 2'd1) ? 6'd6 : (pwdata_i[3:2] == 2'd2) ? 6'd8 : 6'd4;
          rcon_q  <= 8'h01;
          done_q  <= 1'b0;
          state_q <= Expand;
        end
        Expand: begin
          if (word_q == schedule_words) begin
            state_block_q <= {in_q[0], in_q[1], in_q[2], in_q[3]} ^ first_key;
            round_q       <= 4'd1;
            state_q       <= Rounds;
          end else begin
            schedule_q[word_q] <= next_key_word;
            word_q             <= word_q + 6'd1;
            if (rcon_step) rcon_q <= xtime(rcon_q);
          end
        end
        Rounds: begin
          state_block_q <= decrypt_q ? dec_next : enc_next;
          round_q       <= round_q + 4'd1;
          if (last_round) begin
            done_q  <= 1'b1;
            state_q <= Idle;
          end
        end
        default: state_q <= Idle;
      endcase
    end
  end

  always_comb begin
    prdata_o = '0;
    unique case (paddr_i)
      7'h04:   prdata_o = {30'b0, done_q, state_q != Idle};
      7'h08:   prdata_o = {31'b0, irq_en_q};
      7'h30:   prdata_o = in_q[0];
      7'h34:   prdata_o = in_q[1];
      7'h38:   prdata_o = in_q[2];
      7'h3C:   prdata_o = in_q[3];
      7'h40:   prdata_o = state_block_q[127:96];
      7'h44:   prdata_o = state_block_q[95:64];
      7'h48:   prdata_o = state_block_q[63:32];
      7'h4C:   prdata_o = state_block_q[31:0];
      default: prdata_o = '0;
    endcase
  end

endmodule
