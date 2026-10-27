// Copyright 2024 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Authors:
// - Philippe Sauter <phsauter@iis.ee.ethz.ch>
//
// This module wraps the processor core and adapts it to the Croc SoC interface.
// The integrated core is Sophon.
//
// Replacing the core:
// The SoC provides two separate OBI master ports (instruction fetch and data access).
// Cores with a single shared memory bus can tie off one of the two and only use the other.
//
// Key interface signals to adapt for other cores:
//   fetch_enable_i - Allows the SoC to gate instruction fetch (e.g. hold core until 
//                    software is loaded). Cores without this signal should ignore it.
//   core_busy_o    - Activity hint; drive 1'b0 if the core does not expose it.
//   irqs_i [15:0]  - Fast interrupts (RISC-V IRQ 16..31). Mapping to a core's interrupt
//                    input depends on the core:
//                      CVE2/Ibex: irq_fast_i[15:0] directly
//                      cv32e40p:  irq_i[31:16]
//                    timer_irq_i and software_irq_i correspond to the standard RISC-V
//                    CLINT timer (IRQ 7) and software (IRQ 3) interrupts.
//   debug_req_i    - Debug module request. Cores without a debug interface should leave
//                    this unconnected and remove the debug module from the address map.
//                    Attention! Think carefully how it will be programmed and started.
//                    CVE2 receives the debug halt/exception addresses as runtime inputs
//                    (dm_halt_addr_i / dm_exception_addr_i). Some cores hardcode these
//                    addresses instead; in that case adjust PeriphDebug's start_addr in
//                    croc_pkg.sv so the debug module ROM base matches what the core
//                    expects to jump to on halt.
// CV-X-IF co-processors: CVE2 supports instruction offloading via the Core-V Extension Interface. 
//   If you want to attach a custom accelerator using CV-X-IF,
//   instantiate it directly inside this wrapper (enable XInterface and connect x_* ports here).
//   Do not route CV-X-IF through the SoC hierarchy; the types are CVE2-specific and the tight
//   coupling belongs at the core boundary, not in user_domain.

module core_wrap import croc_pkg::*; #() (
  input  logic clk_i,
  input  logic rst_ni,
  input  logic test_enable_i,

  // Interrupts
  // irqs_i maps to RISC-V fast interrupts (IRQ 16..31); see header comment for remapping
  input logic [15:0] irqs_i,
  input logic timer_irq_i,
  input logic software_irq_i,

  input  logic [31:0] boot_addr_i,

  // Instruction memory interface (OBI)
  output logic        instr_req_o,
  input  logic        instr_gnt_i,
  input  logic        instr_rvalid_i,
  output logic [31:0] instr_addr_o,
  input  logic [31:0] instr_rdata_i,
  input  logic        instr_err_i,

  // Data memory interface (OBI)
  output logic        data_req_o,
  input  logic        data_gnt_i,
  input  logic        data_rvalid_i,
  output logic        data_we_o,
  output logic [3:0]  data_be_o,
  output logic [31:0] data_addr_o,
  output logic [31:0] data_wdata_o,
  input  logic [31:0] data_rdata_i,
  input  logic        data_err_i,

  // Debug Interface
  input  logic        debug_req_i,

  // CPU Control Signals
  // fetch_enable_i: gates instruction fetch; ignore if core has no such signal
  input  logic        fetch_enable_i,

  // core_busy_o: power-management hint to the SoC; drive 1'b0 if not available
  output logic        core_busy_o
);

  logic sophon_clk_neg;

  logic        sophon_inst_req;
  logic [31:0] sophon_inst_addr;
  logic        sophon_inst_ack;
  logic [31:0] sophon_inst_rdata;
  logic        sophon_inst_error;

  logic        sophon_lsu_req;
  logic        sophon_lsu_we;
  logic [31:0] sophon_lsu_addr;
  logic [31:0] sophon_lsu_wdata;
  logic [3:0]  sophon_lsu_wstrb;
  logic        sophon_lsu_ack;
  logic        sophon_lsu_error;
  logic [31:0] sophon_lsu_rdata;

  tc_clk_inverter i_sophon_clk_inverter (
    .clk_i ( clk_i          ),
    .clk_o ( sophon_clk_neg )
  );

  SOPHON i_sophon (
    .clk_i,
    .clk_neg_i       ( sophon_clk_neg ),
    .rst_ni,
    .bootaddr_i      ( boot_addr_i    ),
    .hart_id_i       ( 32'd0          ),
    .irq_mei_i       ( |irqs_i        ),
    .irq_mti_i       ( timer_irq_i    ),
    .irq_msi_i       ( software_irq_i ),
    .inst_req_o      ( sophon_inst_req   ),
    .inst_addr_o     ( sophon_inst_addr  ),
    .inst_ack_i      ( sophon_inst_ack   ),
    .inst_rdata_i    ( sophon_inst_rdata ),
    .inst_error_i    ( sophon_inst_error ),
    .lsu_req_o       ( sophon_lsu_req   ),
    .lsu_we_o        ( sophon_lsu_we    ),
    .lsu_addr_o      ( sophon_lsu_addr  ),
    .lsu_wdata_o     ( sophon_lsu_wdata ),
    .lsu_wstrb_o     ( sophon_lsu_wstrb ),
    .lsu_ack_i       ( sophon_lsu_ack   ),
    .lsu_error_i     ( sophon_lsu_error ),
    .lsu_rdata_i     ( sophon_lsu_rdata )
  );

  sophon_obi_adapter #(
    .InstructionPort ( 1'b1 )
  ) i_sophon_instr_adapter (
    .clk_i,
    .rst_ni,
    .sophon_req_i    ( sophon_inst_req   ),
    .sophon_we_i     ( 1'b0              ),
    .sophon_addr_i   ( sophon_inst_addr  ),
    .sophon_wdata_i  ( 32'b0             ),
    .sophon_wstrb_i  ( 4'b1111           ),
    .sophon_ack_o    ( sophon_inst_ack   ),
    .sophon_error_o  ( sophon_inst_error ),
    .sophon_rdata_o  ( sophon_inst_rdata ),
    .obi_req_o       ( instr_req_o       ),
    .obi_gnt_i       ( instr_gnt_i       ),
    .obi_rvalid_i    ( instr_rvalid_i    ),
    .obi_we_o        (),
    .obi_be_o        (),
    .obi_addr_o      ( instr_addr_o      ),
    .obi_wdata_o     (),
    .obi_rdata_i     ( instr_rdata_i     ),
    .obi_err_i       ( instr_err_i       )
  );

  sophon_obi_adapter i_sophon_data_adapter (
    .clk_i,
    .rst_ni,
    .sophon_req_i    ( sophon_lsu_req   ),
    .sophon_we_i     ( sophon_lsu_we    ),
    .sophon_addr_i   ( sophon_lsu_addr  ),
    .sophon_wdata_i  ( sophon_lsu_wdata ),
    .sophon_wstrb_i  ( sophon_lsu_wstrb ),
    .sophon_ack_o    ( sophon_lsu_ack   ),
    .sophon_error_o  ( sophon_lsu_error ),
    .sophon_rdata_o  ( sophon_lsu_rdata ),
    .obi_req_o       ( data_req_o       ),
    .obi_gnt_i       ( data_gnt_i       ),
    .obi_rvalid_i    ( data_rvalid_i    ),
    .obi_we_o        ( data_we_o        ),
    .obi_be_o        ( data_be_o        ),
    .obi_addr_o      ( data_addr_o      ),
    .obi_wdata_o     ( data_wdata_o     ),
    .obi_rdata_i     ( data_rdata_i     ),
    .obi_err_i       ( data_err_i       )
  );

  // Sophon has no equivalent fetch-enable or idle indication in this profile.
  // Croc's system-bus debug remains available; CPU halt/resume is deferred.
  assign core_busy_o = 1'b0;

endmodule
