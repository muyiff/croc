// Copyright 2026 Yangfei
// SPDX-License-Identifier: Apache-2.0
//
// Converts Sophon's blocking req/ack memory interface to one OBI manager port.

module sophon_obi_adapter #(
  parameter bit InstructionPort = 1'b0
) (
  input  logic        clk_i,
  input  logic        rst_ni,

  input  logic        sophon_req_i,
  input  logic        sophon_we_i,
  input  logic [31:0] sophon_addr_i,
  input  logic [31:0] sophon_wdata_i,
  input  logic [3:0]  sophon_wstrb_i,
  output logic        sophon_ack_o,
  output logic        sophon_error_o,
  output logic [31:0] sophon_rdata_o,

  output logic        obi_req_o,
  input  logic        obi_gnt_i,
  input  logic        obi_rvalid_i,
  output logic        obi_we_o,
  output logic [3:0]  obi_be_o,
  output logic [31:0] obi_addr_o,
  output logic [31:0] obi_wdata_o,
  input  logic [31:0] obi_rdata_i,
  input  logic        obi_err_i
);

  typedef enum logic [2:0] {
    Idle,
    WaitResponse,
    Acknowledge,
    AckSetup,
    AckActive
  } state_t;

  state_t state_q;
  logic [31:0] rdata_q;
  logic        error_q;
  logic        req_we_q;
  logic [3:0]  req_be_q;
  logic [31:0] req_addr_q;
  logic [31:0] req_wdata_q;
  logic        inst_ack_q;

  // Sophon keeps its request signals stable until ack.  An OBI response is
  // first latched, then acknowledged to Sophon in the following cycle so the
  // core always observes stable response data at its sampling edge.
  assign obi_req_o   = sophon_req_i & (state_q == Idle);
  assign obi_we_o    = (state_q == Idle) ? (InstructionPort ? 1'b0 : sophon_we_i)
                                         : req_we_q;
  assign obi_be_o    = (state_q == Idle) ? (InstructionPort ? 4'b1111 : sophon_wstrb_i)
                                         : req_be_q;
  assign obi_addr_o  = (state_q == Idle) ? sophon_addr_i : req_addr_q;
  assign obi_wdata_o = (state_q == Idle) ? (InstructionPort ? 32'b0 : sophon_wdata_i)
                                         : req_wdata_q;

  assign sophon_ack_o   = InstructionPort ? inst_ack_q : (state_q == Acknowledge);
  // Sophon consumes instruction/data response information in subsequent
  // pipeline phases.  OBI only guarantees rdata/err while rvalid is high, so
  // retain the response after the OBI transaction has completed.
  assign sophon_error_o = error_q;
  assign sophon_rdata_o = rdata_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q       <= Idle;
      rdata_q       <= 32'b0;
      error_q       <= 1'b0;
      req_we_q      <= 1'b0;
      req_be_q      <= 4'b0;
      req_addr_q    <= 32'b0;
      req_wdata_q   <= 32'b0;
    end else begin
      unique case (state_q)
        Idle: begin
          if (sophon_req_i & obi_gnt_i) begin
            rdata_q <= 32'b0;
            error_q <= 1'b0;
            req_we_q    <= InstructionPort ? 1'b0 : sophon_we_i;
            req_be_q    <= InstructionPort ? 4'b1111 : sophon_wstrb_i;
            req_addr_q  <= sophon_addr_i;
            req_wdata_q <= InstructionPort ? 32'b0 : sophon_wdata_i;
            if (obi_rvalid_i) begin
              state_q <= Acknowledge;
              rdata_q <= obi_rdata_i;
              error_q <= obi_err_i;
            end else begin
              state_q <= WaitResponse;
            end
          end
        end
        WaitResponse: begin
          if (obi_rvalid_i) begin
            state_q <= InstructionPort ? AckSetup : Acknowledge;
            rdata_q <= obi_rdata_i;
            error_q <= obi_err_i;
          end
        end
        Acknowledge: begin
          state_q <= Idle;
        end
        AckSetup: begin
          state_q <= AckActive;
        end
        AckActive: begin
          state_q <= Idle;
        end
        default: begin
          state_q <= Idle;
        end
      endcase
    end
  end

  // Sophon's external instruction channel returns data at a posedge and
  // presents its acknowledgement on the following negedge.  Keep the ack
  // asserted for one full negedge-to-negedge interval, matching the original
  // INST_ITF_DEMUX timing contract.
  always_ff @(negedge clk_i or negedge rst_ni) begin
    if (!rst_ni)
      inst_ack_q <= 1'b0;
    else
      inst_ack_q <= (state_q == AckSetup);
  end

endmodule
