// SPDX-License-Identifier: Apache-2.0
// The deployed core wrapper, with bounded OBI grant/response delays and a
// CLIC interface stimulus. This is not an interrupt-controller implementation.
module tb_sophon_extensions;
  timeunit 1ns;
  timeprecision 1ps;
  localparam logic [31:0] Base = 32'h1000_0000;
  localparam logic [31:0] Mailbox = Base + 32'hf00;
  logic clk = 0;
  always #25ns clk = ~clk;
  logic rst_n = 0;
  logic [15:0] irqs = '0;
  logic timer_irq = 0, software_irq = 0;
  logic clic_req = 0, clic_shv = 0;
  logic [4:0] clic_id = 0, clic_clear_id;
  logic [7:0] clic_level = 0, clic_threshold;
  logic clic_ack, clic_clear;
  logic i_req, i_gnt, i_valid = 0, i_err = 0;
  logic [31:0] i_addr, i_data = 0;
  logic d_req, d_gnt, d_valid = 0, d_err = 0, d_we;
  logic [3:0] d_be;
  logic [31:0] d_addr, d_wdata, d_data = 0;
  logic [7:0] mem [Base:Base+4095];
  string binary_path;
  int wait_cycles = 0;
  bit reset_mid = 0;
  int cycles = 0, push_count = 0, pop_count = 0, overflow_count = 0;
  int illegal_count = 0, max_depth = 0, shv_count = 0, mret_count = 0;
  int ref_depth = 0;
  logic [31:0] reference_gpr [3][32];
  logic [31:0] reference_epc [3], reference_cause [3];
  logic [7:0] reference_level [3];
  bit checked_reset = 0;

  core_wrap dut (
    .clk_i(clk), .rst_ni(rst_n), .test_enable_i(1'b0),
    .irqs_i(irqs), .timer_irq_i(timer_irq), .software_irq_i(software_irq),
    .clic_irq_req_i(clic_req), .clic_irq_shv_i(clic_shv),
    .clic_irq_id_i(clic_id), .clic_irq_level_i(clic_level),
    .clic_irq_ack_o(clic_ack), .clic_irq_intthresh_o(clic_threshold),
    .clic_mnxti_clr_o(clic_clear), .clic_mnxti_id_o(clic_clear_id),
    .boot_addr_i(Base),
    .instr_req_o(i_req), .instr_gnt_i(i_gnt), .instr_rvalid_i(i_valid),
    .instr_addr_o(i_addr), .instr_rdata_i(i_data), .instr_err_i(i_err),
    .data_req_o(d_req), .data_gnt_i(d_gnt), .data_rvalid_i(d_valid),
    .data_we_o(d_we), .data_be_o(d_be), .data_addr_o(d_addr),
    .data_wdata_o(d_wdata), .data_rdata_i(d_data), .data_err_i(d_err),
    .debug_req_i(1'b0), .fetch_enable_i(1'b1), .core_busy_o()
  );

  function automatic bit in_sram(input logic [31:0] addr);
    return addr >= Base && addr <= Base + 4092 && addr[1:0] == 0;
  endfunction

  function automatic logic [31:0] read_word(input logic [31:0] addr);
    if (!in_sram(addr)) return 'x;
    return {mem[addr+3], mem[addr+2], mem[addr+1], mem[addr]};
  endfunction

  bit i_busy = 0, d_busy = 0;
  int i_grant_wait = 0, d_grant_wait = 0, i_rsp_wait = 0, d_rsp_wait = 0;
  logic [31:0] i_saved_addr, d_saved_addr, d_saved_data;
  logic [3:0] d_saved_be;
  bit d_saved_we;
  assign i_gnt = rst_n && i_req && !i_busy && i_grant_wait == 0;
  assign d_gnt = rst_n && d_req && !d_busy && d_grant_wait == 0;

  always @(posedge clk) begin
    cycles <= cycles + 1;
    i_valid <= 0;
    d_valid <= 0;
    if (!rst_n) begin
      i_busy <= 0;
      d_busy <= 0;
      i_grant_wait <= wait_cycles;
      d_grant_wait <= wait_cycles;
    end else begin
      if (i_req && !i_busy && i_grant_wait > 0) i_grant_wait <= i_grant_wait - 1;
      if (d_req && !d_busy && d_grant_wait > 0) d_grant_wait <= d_grant_wait - 1;
      if (i_gnt) begin
        i_busy <= 1;
        i_saved_addr <= i_addr;
        i_rsp_wait <= wait_cycles + 1;
      end
      if (d_gnt) begin
        d_busy <= 1;
        d_saved_addr <= d_addr;
        d_saved_data <= d_wdata;
        d_saved_we <= d_we;
        d_saved_be <= d_be;
        d_rsp_wait <= wait_cycles + 1;
      end
      if (i_busy) begin
        if (i_rsp_wait > 0) i_rsp_wait <= i_rsp_wait - 1;
        else begin
          i_valid <= 1;
          i_data <= read_word(i_saved_addr);
          i_err <= !in_sram(i_saved_addr);
          i_busy <= 0;
          i_grant_wait <= wait_cycles;
        end
      end
      if (d_busy) begin
        if (d_rsp_wait > 0) d_rsp_wait <= d_rsp_wait - 1;
        else begin
          d_valid <= 1;
          d_data <= read_word(d_saved_addr);
          d_err <= !in_sram(d_saved_addr) && d_saved_addr != 32'h03000008;
          d_busy <= 0;
          d_grant_wait <= wait_cycles;
          if (d_saved_we) begin
            if (in_sram(d_saved_addr)) begin
              for (int b=0; b<4; b++)
                if (d_saved_be[b]) mem[d_saved_addr+b] <= d_saved_data[8*b+:8];
            end else if (d_saved_addr == 32'h03000008) begin
              if (d_saved_data !== 1) $fatal(1, "Firmware FAIL pc=%h", dut.i_sophon.pc);
              if (ref_depth != 0 || max_depth != 3 || overflow_count == 0 ||
                  pop_count < 8 || illegal_count == 0 || shv_count == 0 ||
                  mret_count < 10 || read_word(Mailbox+24) != 3)
                $fatal(1, "Incomplete coverage depth=%0d max=%0d pop=%0d shv=%0d mret=%0d",
                       ref_depth, max_depth, pop_count, shv_count, mret_count);
              $display("SOPHON EXTENSIONS PASS wait=%0d reset_mid=%0d cycles=%0d pushes=%0d pops=%0d",
                       wait_cycles, reset_mid, cycles, push_count, pop_count);
              $finish;
            end else $fatal(1, "Unexpected write addr=%h", d_saved_addr);
          end
        end
      end
    end
  end

  // Observe the command boundary and independently retain every GPR image.
  // The SHV snapshot includes the instruction retiring at interrupt entry.
  always begin : check_snapshot
    bit restore_now;
    logic [31:0] expected [32];
    logic [31:0] epc, cause;
    logic [7:0] level;
    @(posedge clk);
    restore_now = 0;
    if (!rst_n) begin
      ref_depth = 0;
      checked_reset = 0;
    end else begin
      if (!checked_reset) begin
        if (dut.i_sophon_cust.U_SNAPREG.snap_sp !== 0 ||
            dut.i_sophon.sreg_csr_sp !== 0)
          $fatal(1, "Stack not reset");
        for (int b=0; b<3; b++)
          for (int r=0; r<32; r++)
            if (dut.i_sophon_cust.U_SNAPREG.snap_bank[b][r] !== 0)
              $fatal(1, "Bank not reset bank=%0d reg=%0d", b, r);
        checked_reset = 1;
      end
      if (dut.eei_req && dut.eei_ack) begin
        if (dut.eei_funct7 == 7'h01) begin
          if (dut.eei_error !== 1 || dut.i_sophon.wr_regfile_eei !== 0)
            $fatal(1, "Invalid SREG operation not rejected");
          illegal_count++;
        end
        if (!dut.eei_error && dut.eei_ext && dut.eei_funct3 == 1) begin
          if (dut.eei_funct7 inside {7'h02, 7'h03, 7'h04}) begin
            if (ref_depth < 3) begin
              for (int r=1; r<32; r++) begin
                reference_gpr[ref_depth][r] = dut.i_sophon.regfile[r];
                if (dut.i_sophon.eei_sreg_shv_auto_push_req &&
                    dut.i_sophon.wr_regfile && dut.i_sophon.rd_idx == r)
                  reference_gpr[ref_depth][r] = dut.i_sophon.rd_val;
              end
              reference_epc[ref_depth] = dut.i_sophon.eei_sreg_shv_auto_push_req ?
                                         dut.i_sophon.pc : dut.i_sophon.mepc;
              reference_cause[ref_depth] = dut.i_sophon.eei_sreg_shv_auto_push_req ?
                {1'b1, dut.i_sophon.mcause[30:5], clic_id} : dut.i_sophon.mcause;
              reference_level[ref_depth] = dut.i_sophon.eei_sreg_shv_auto_push_req ?
                                           clic_level : dut.i_sophon.curr_clic_level;
              ref_depth++;
              push_count++;
              if (ref_depth > max_depth) max_depth = ref_depth;
              if (dut.i_sophon.eei_sreg_shv_auto_push_req) shv_count++;
            end else overflow_count++;
          end
          if (dut.eei_funct7 == 7'h42 && ref_depth > 0) begin
            ref_depth--;
            for (int r=1; r<32; r++) expected[r] = reference_gpr[ref_depth][r];
            epc = reference_epc[ref_depth];
            cause = reference_cause[ref_depth];
            level = reference_level[ref_depth];
            restore_now = 1;
            pop_count++;
          end
        end
      end
      if (dut.i_sophon.is_mret && dut.i_sophon.inst_data_1d_vld) mret_count++;
      @(negedge clk);
      #1ps;
      if (restore_now) begin
        for (int r=1; r<32; r++)
          if (dut.i_sophon.regfile[r] !== expected[r])
            $fatal(1, "GPR restore x%0d actual=%h expected=%h pc=%h",
                   r, dut.i_sophon.regfile[r], expected[r], dut.i_sophon.pc);
        if (dut.i_sophon.mepc !== epc || dut.i_sophon.mcause !== cause ||
            dut.i_sophon.curr_clic_level !== level)
          $fatal(1, "CSR restore mismatch epc=%h/%h cause=%h/%h level=%h/%h",
                 dut.i_sophon.mepc, epc, dut.i_sophon.mcause, cause,
                 dut.i_sophon.curr_clic_level, level);
      end
      if (dut.i_sophon_cust.U_SNAPREG.snap_sp !== ref_depth ||
          dut.i_sophon.sreg_csr_sp !== ref_depth ||
          dut.sreg_nest_allow !== (ref_depth < 3))
        $fatal(1, "GPR/CSR stack depth or nesting allowance mismatch expected=%0d", ref_depth);
    end
  end

  task automatic send_clic(input bit shv, input int id, input int level);
    int started;
    @(negedge clk);
    #2ps;
    clic_req = 1;
    clic_shv = shv;
    clic_id = 5'(id);
    clic_level = 8'(level);
    started = cycles;
    do @(posedge clk); while (!(shv ? clic_ack : clic_clear));
    if (!shv && clic_clear_id !== 5'(id)) $fatal(1, "Wrong claimed ID");
    $display("CLIC serviced id=%0d shv=%0d request_to_handshake=%0d cycles",
             id, shv, cycles-started);
    @(negedge clk);
    #2ps;
    clic_req = 0;
  endtask

  task automatic send_standard(input int cause);
    @(negedge clk);
    #2ps;
    case (cause)
      3: software_irq = 1;
      7: timer_irq = 1;
      11: irqs[0] = 1;
    endcase
    wait(dut.i_sophon.clint_irq_vld);
    @(negedge clk);
    #2ps;
    if (dut.i_sophon.mcause !== (32'h80000000 | cause))
      $fatal(1, "Standard interrupt cause mismatch");
    software_irq = 0;
    timer_irq = 0;
    irqs = 0;
  endtask

  task automatic wait_mailbox(input int offset, input int value);
    do begin
      @(negedge clk);
      #2ps;
    end while (read_word(Mailbox+offset) !== 32'(value));
  endtask

  initial begin : stimulus
    if (!$value$plusargs("binary=%s", binary_path)) $fatal(1, "Missing +binary");
    void'($value$plusargs("wait_cycles=%d", wait_cycles));
    reset_mid = $test$plusargs("reset_mid");
    foreach (mem[a]) mem[a] = 0;
    $readmemh(binary_path, mem);
    repeat (5) @(negedge clk);
    #2ps rst_n = 1;
    for (int epoch=0; epoch<(reset_mid ? 2 : 1); epoch++) begin
      wait_mailbox(0, 1);
      fork
        send_clic(0, 16, 40);
        begin
          repeat (8) begin
            @(posedge clk);
            if (clic_ack) $fatal(1, "Masked interrupt accepted");
          end
        end
      join
      wait_mailbox(0, 2);
      send_clic(0, 17, 80);
      wait_mailbox(0, 3);
      send_clic(1, 20, 60);
      wait_mailbox(0, 4);
      @(negedge clk);
      #2ps;
      clic_req = 1; clic_shv = 0; clic_id = 16; clic_level = 90;
      repeat (40) begin
        @(posedge clk);
        // Source arbitration belongs to the future controller. The core
        // exports the threshold and rejects this non-SHV claim below it.
        if (clic_clear || clic_threshold !== 100 || read_word(Mailbox+4) != 3)
          $fatal(1, "Threshold export or non-SHV claim filter failed");
      end
      @(negedge clk);
      #2ps clic_req = 0;
      send_clic(0, 16, 110);
      wait_mailbox(0, 5);
      send_clic(0, 16, 20);
      wait_mailbox(8, 16);
      @(negedge clk);
      #2ps;
      clic_req = 1; clic_shv = 0; clic_id = 17; clic_level = 20;
      repeat (20) begin
        @(posedge clk);
        if (clic_ack || clic_clear) $fatal(1, "Equal-level interrupt preempted");
      end
      @(negedge clk);
      #2ps clic_req = 0;
      send_clic(0, 17, 40);
      wait_mailbox(8, 17);
      send_clic(0, 18, 60);
      wait_mailbox(8, 18);
      if (ref_depth != 3) $fatal(1, "Three-level nesting not reached");
      @(negedge clk);
      #2ps;
      clic_req = 1; clic_shv = 0; clic_id = 19; clic_level = 80;
      repeat (30) begin
        @(posedge clk);
        if (clic_ack || clic_clear || dut.sreg_nest_allow)
          $fatal(1, "Full stack accepted a fourth interrupt");
      end
      if (reset_mid && epoch == 0) begin
        @(negedge clk);
        #2ps;
        clic_req = 0;
        rst_n = 0;
        repeat (5) @(negedge clk);
        #2ps rst_n = 1;
      end else begin
        do @(posedge clk); while (!clic_clear);
        if (clic_clear_id !== 19) $fatal(1, "Deferred interrupt lost");
        @(negedge clk);
        #2ps clic_req = 0;
        wait_mailbox(0, 6);
        send_standard(3);
        wait_mailbox(0, 7);
        send_standard(7);
        wait_mailbox(0, 8);
        send_standard(11);
      end
    end
  end

  initial begin
    #20ms;
    $fatal(1, "Timeout pc=%h phase=%h count=%h", dut.i_sophon.pc,
           read_word(Mailbox), read_word(Mailbox+4));
  end
endmodule
