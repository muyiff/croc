// // ----------------------------------------------------------------------
// // Copyright 2023 TimingWalker
// //
// // Licensed under the Apache License, Version 2.0 (the "License");
// // you may not use this file except in compliance with the License.
// // You may obtain a copy of the License at
// //
// //     http://www.apache.org/licenses/LICENSE-2.0
// //
// // Unless required by applicable law or agreed to in writing, software
// // distributed under the License is distributed on an "AS IS" BASIS,
// // WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// // See the License for the specific language governing permissions and
// // limitations under the License.
// // ----------------------------------------------------------------------
// // Create Date   : 2023-01-12 10:22:46
// // Last Modified : 2024-07-29 11:03:34
// // Description   : snapshot regfile     
// // ----------------------------------------------------------------------

// module SNAPREG(
// `ifdef SOPHON_EEI_SREG
//      input  logic                               clk_i
//     ,input  logic                               rst_ni
//     ,input  logic                               sreg_req     
//     ,input  logic [6:0]                         sreg_funct7  
//     ,input  logic [4:0]                         sreg_batch_start 
//     ,input  logic [4:0]                         sreg_batch_len 
//     ,input  logic [31:0]                        sreg_rs_val[`EEI_RS_MAX-1:0]    
//     ,output logic                               sreg_ack   
//     ,output logic                               sreg_error   
//     ,output logic [31:0]                        sreg_rd_val[`EEI_RD_MAX-1:0] 
// `endif
// );


// `ifdef SOPHON_EEI_SREG

//     logic [31:0]        wr_sreg_bit;
//     logic               sreg_wr;
//     logic [31:0]        snapreg[31:0];

//     assign sreg_ack = sreg_req;

//     always_comb begin
//         sreg_wr    = 1'b0;
//         sreg_error = sreg_req;
//         if ( sreg_req && sreg_funct7 == 7'b0000000 ) begin
//             sreg_wr    = 1'b1;
//             sreg_error = 1'b0;
//         end
//         else if ( sreg_req && sreg_funct7 == 7'b1000000 ) begin
//             sreg_wr    = 1'b0;
//             sreg_error = 1'b0;
//         end
//     end

//     integer j;
//     always_comb begin
//         wr_sreg_bit = 32'd0;
//         for (j=0; j<32; j=j+1)
//             wr_sreg_bit[j] = ( (sreg_batch_start<=6'(j)) && ((sreg_batch_len+sreg_batch_start)>6'(j)) ) ? 1'b1 : 1'b0;
//     end

//     genvar i;
//     generate
//         for (i=1; i<32; i=i+1) begin:gen_snapreg
//             always_ff @(posedge clk_i, negedge rst_ni) begin
//                 if(~rst_ni) begin
//                     snapreg[i] <= 32'd0;
//                 end
//                 else if ( sreg_wr && (wr_sreg_bit[i]==1) ) begin
//                     snapreg[i] <= sreg_rs_val[ i-sreg_batch_start ];
//                 end
//             end
//         end
//     endgenerate
//     assign snapreg[0] = 32'd0;


//     localparam EXT_RF_LEN  = 32 + `EEI_RD_MAX -1;
//     logic  [31:0] ext_snapreg[EXT_RF_LEN-1:0];
//     for (genvar i=0; i<EXT_RF_LEN; i++) begin : gen_ext_snapreg
//         if ( i<32 ) 
//             assign ext_snapreg[i] = snapreg[i];
//         else 
//             assign ext_snapreg[i] = snapreg[i-32];
//     end

//     genvar k;
//     generate
//         for (k=0; k<`EEI_RD_MAX; k=k+1) begin:gen_sreg_rd_val
//             assign sreg_rd_val[k] = ext_snapreg[k+sreg_batch_start];
//         end
//     endgenerate

// `endif

// endmodule

// ----------------------------------------------------------------------
// snapshot regfile (extended to multi-bank stack)
// ----------------------------------------------------------------------

module SNAPREG #(
    parameter int unsigned SNAP_DEPTH = 1,
    // 0: original CLIC nested-interrupt stack; 1: fixed-bank task demo.
    // 2 is reserved for the shared task/interrupt pool introduced later.
    parameter int unsigned CTX_MODE   = 0
)(
`ifdef SOPHON_EEI_SREG
     input  logic                               clk_i
    ,input  logic                               rst_ni
    ,input  logic                               sreg_req
    ,input  logic [6:0]                         sreg_funct7
    ,input  logic [4:0]                         sreg_batch_start
    ,input  logic [4:0]                         sreg_batch_len
    ,input  logic [31:0]                        sreg_rs_val[`EEI_RS_MAX-1:0]
    ,output logic                               sreg_ack
    ,output logic                               sreg_error
    ,output logic [31:0]                        sreg_rd_val[`EEI_RD_MAX-1:0]
    ,output logic                               sreg_nest_allow
`ifdef SOPHON_TASK_WB
    ,output logic                               capture_req
    ,input  logic                               capture_ack
    ,input  logic                               capture_error
    ,output logic                               capture_fire
    ,output logic [31:0]                        capture_frame_base
    ,input  logic                               wb_release_fire
    ,input  logic [4:0]                         wb_reg_index
    ,output logic [31:0]                        wb_reg_data
`endif
`endif
);

`ifdef SOPHON_EEI_SREG

    // legacy:
    //   7'b0000000 : write bank0
    //   7'b1000000 : read  bank0
    // new (nesting):
    //   7'b0000010 : PUSH_SAVE        (write bank[snap_sp], then snap_sp++)
    //   7'b0000011 : PUSH_SAVE_ENABLE (non-SHV; arm MIE restore after vector load)
    //   7'b0000100 : PUSH_SHV_ENABLE  (SHV; enable MIE after PUSH_SAVE)
    //   7'b1000010 : POP_RESTORE      (read bank[snap_sp-1], then snap_sp--)
    // task-switch demo (only used by the NESTSTACK_TASK_DEMO FreeRTOS build):
    //   7'b0010000 : TASK_BIND0       (select fixed task bank 0)
    //   7'b0010001 : TASK_BIND1       (select fixed task bank 1)
    //   7'b0010010 : TASK_SAVE        (save to selected bank, no stack update)
    //   7'b0010011 : TASK_BIND2       (select fixed task bank 2)
    //   7'b1010000 : TASK_RESTORE0    (restore fixed task bank 0)
    //   7'b1010001 : TASK_RESTORE1    (restore fixed task bank 1)
    //   7'b1010010 : TASK_RESTORE2    (restore fixed task bank 2)
    localparam logic [6:0] SREG_WR_LEGACY = 7'b0000000;
    localparam logic [6:0] SREG_RD_LEGACY = 7'b1000000;
    localparam logic [6:0] SREG_PUSH_SAVE = 7'b0000010; // 0x02
    localparam logic [6:0] SREG_PUSH_EN   = 7'b0000011; // 0x03
    localparam logic [6:0] SREG_PUSH_SHV  = 7'b0000100; // 0x04
    localparam logic [6:0] SREG_POP_REST  = 7'b1000010; // 0x42 (bit6=1)
    localparam logic [6:0] SREG_TASK_BIND0 = 7'b0010000; // 0x10
    localparam logic [6:0] SREG_TASK_BIND1 = 7'b0010001; // 0x11
    localparam logic [6:0] SREG_TASK_SAVE  = 7'b0010010; // 0x12
    localparam logic [6:0] SREG_TASK_BIND2 = 7'b0010011; // 0x13
    localparam logic [6:0] SREG_TASK_REST0 = 7'b1010000; // 0x50
    localparam logic [6:0] SREG_TASK_REST1 = 7'b1010001; // 0x51
    localparam logic [6:0] SREG_TASK_REST2 = 7'b1010010; // 0x52

    localparam int unsigned CTX_MODE_LEGACY_IRQ = 0;
    localparam int unsigned CTX_MODE_TASK_ONLY  = 1;
    localparam int unsigned CTX_MODE_MIXED      = 2;
    // Mode 2 shares the existing banks: task frames retain ownership while
    // a logical IRQ stack records the physical bank selected for every PUSH.
    localparam bit TASK_OPS_ENABLED = (CTX_MODE == CTX_MODE_TASK_ONLY) ||
                                      (CTX_MODE == CTX_MODE_MIXED);
    localparam bit IRQ_OPS_ENABLED  = (CTX_MODE == CTX_MODE_LEGACY_IRQ) ||
                                      (CTX_MODE == CTX_MODE_MIXED);

    localparam int unsigned SP_W = (SNAP_DEPTH <= 1) ? 1 : $clog2(SNAP_DEPTH + 1);
`ifdef SOPHON_TASK_WB
    localparam bit TASK_WB_ENABLED = 1'b1;
    logic op_temp_capture, capture_format_ok, capture_address_ok;
    logic [32:0] capture_sp_ext;
    assign op_temp_capture = sreg_req && (sreg_funct7 == 7'h14);
    assign capture_format_ok = (sreg_batch_start == 5'd1) &&
                               (sreg_batch_len == 5'd31);
    assign capture_sp_ext = {1'b0, sreg_rs_val[1]};
    assign capture_address_ok = (sreg_rs_val[1][1:0] == 0) &&
        (capture_sp_ext >= ({1'b0,SOPHON_PKG::DTCM_BASE} + 33'd124)) &&
        (capture_sp_ext <= ({1'b0,SOPHON_PKG::DTCM_END} + 33'd1));
    assign capture_frame_base = 32'(capture_sp_ext - 33'd124);
    assign capture_req = op_temp_capture && capture_format_ok && capture_address_ok;
    assign capture_fire = capture_req && capture_ack && !capture_error;
`else
    localparam bit TASK_WB_ENABLED = 1'b0;
`endif

    logic [31:0] wr_sreg_bit;
    logic        sreg_wr;

    logic [SP_W-1:0] snap_sp;
    logic [SP_W-1:0] wr_bank_sel;
    logic [SP_W-1:0] rd_bank_sel;
    logic [SP_W-1:0] task_bank_sel;
    logic [SNAP_DEPTH-1:0] task_bank_valid;
    logic [SNAP_DEPTH-1:0] irq_bank_valid;
    logic [SP_W-1:0] irq_bank_stack[SNAP_DEPTH-1:0];
    logic [SP_W-1:0] irq_alloc_bank;
    logic irq_bank_available;

    logic push_full, pop_empty;
    logic push_fire, pop_fire;

    logic op_wr_legacy, op_rd_legacy, op_push, op_pop;
    logic op_task_bind0, op_task_bind1, op_task_bind2, op_task_save;
    logic op_task_rest0, op_task_rest1, op_task_rest2, op_task_restore;
    logic task_save_fire, task_restore_fire;
    logic [SNAP_DEPTH-1:0] bank_wr_en;

    // multi-bank snapshot: [bank][reg]
    logic [31:0] snap_bank[SNAP_DEPTH-1:0][31:0];
`ifdef SOPHON_TASK_WB
    assign wb_reg_data = snap_bank[2][wb_reg_index];
`endif

`ifdef SOPHON_TASK_WB
    assign sreg_ack = op_temp_capture && capture_format_ok && capture_address_ok ?
                      capture_ack : sreg_req;
`else
    assign sreg_ack = sreg_req;
`endif

    assign op_wr_legacy = sreg_req && (sreg_funct7 == SREG_WR_LEGACY);
    assign op_rd_legacy = sreg_req && (sreg_funct7 == SREG_RD_LEGACY);
    assign op_push      = sreg_req && ((sreg_funct7 == SREG_PUSH_SAVE) ||
                                       (sreg_funct7 == SREG_PUSH_EN)   ||
                                       (sreg_funct7 == SREG_PUSH_SHV));
    assign op_pop       = sreg_req && (sreg_funct7 == SREG_POP_REST);
    assign op_task_bind0 = sreg_req && (sreg_funct7 == SREG_TASK_BIND0);
    assign op_task_bind1 = sreg_req && (sreg_funct7 == SREG_TASK_BIND1);
    assign op_task_bind2 = sreg_req && (sreg_funct7 == SREG_TASK_BIND2) && !TASK_WB_ENABLED;
    assign op_task_save  = sreg_req && (sreg_funct7 == SREG_TASK_SAVE);
    assign op_task_rest0 = sreg_req && (sreg_funct7 == SREG_TASK_REST0);
    assign op_task_rest1 = sreg_req && (sreg_funct7 == SREG_TASK_REST1);
    assign op_task_rest2 = sreg_req && (sreg_funct7 == SREG_TASK_REST2) && !TASK_WB_ENABLED;
    assign op_task_restore = op_task_rest0 || op_task_rest1 || op_task_rest2;

    // Modes 1 and 2 use the pre-existing banks for fixed task frames.  In
    // Mode 2, an IRQ can borrow only a bank not retained by a saved task.
    assign task_save_fire = TASK_OPS_ENABLED && op_task_save &&
                            (task_bank_sel < SP_W'(3)) &&
                            (!TASK_WB_ENABLED || (task_bank_sel < SP_W'(2))) &&
                            !task_bank_valid[task_bank_sel] &&
                            ((CTX_MODE != CTX_MODE_MIXED) || !irq_bank_valid[task_bank_sel]);
    assign task_restore_fire = TASK_OPS_ENABLED && ((op_task_rest0 && task_bank_valid[0]) ||
                               (op_task_rest1 && task_bank_valid[1]) ||
                               (op_task_rest2 && task_bank_valid[2]));

    // always_ff @(posedge clk_i) begin
    // if (op_push) begin
    //     $display("[SNAP] sp=%0d PUSH wr_bank=%0d start=%0d len=%0d rs0=%h rs1=%h rs2=%h rs3=%h",
    //              snap_sp, wr_bank_sel, sreg_batch_start, sreg_batch_len,
    //              sreg_rs_val[0], sreg_rs_val[1], sreg_rs_val[2], sreg_rs_val[3]);
    // end
    // if (op_pop) begin
    //     $display("[SNAP] sp=%0d POP rd_bank=%0d start=%0d len=%0d rd0=%h rd1=%h rd2=%h rd3=%h",
    //              snap_sp, rd_bank_sel, sreg_batch_start, sreg_batch_len,
    //              sreg_rd_val[0], sreg_rd_val[1], sreg_rd_val[2], sreg_rd_val[3]);
    // end
    // end
    always_ff @(posedge clk_i) begin
    if (op_push && IRQ_OPS_ENABLED) begin
        if (!push_full)
        $display("[SNAP] sp=%0d PUSH_OK wr_bank=%0d start=%0d len=%0d rs0=%h rs1=%h rs2=%h rs3=%h", 
                snap_sp, wr_bank_sel,sreg_batch_start, sreg_batch_len,              
                sreg_rs_val[0], sreg_rs_val[1], sreg_rs_val[2], sreg_rs_val[3]);
        else
        $display("[SNAP][OVF] sp=%0d PUSH_DROPPED depth=%0d", snap_sp, SNAP_DEPTH);
    end
    if (op_pop && IRQ_OPS_ENABLED) begin
        if (!pop_empty)
        $display("[SNAP] sp=%0d POP_OK rd_bank=%0d start=%0d len=%0d rd0=%h rd1=%h rd2=%h rd3=%h", 
                snap_sp, rd_bank_sel, sreg_batch_start, sreg_batch_len,              
                sreg_rd_val[0], sreg_rd_val[1], sreg_rd_val[2], sreg_rd_val[3]);
        else
        $display("[SNAP][UDF] sp=%0d POP_DROPPED", snap_sp);
    end
    end



    // Mode 0 preserves physical-bank==stack-depth.  Mode 2 instead finds
    // the first truly free physical bank, while snap_sp remains a logical
    // LIFO depth and irq_bank_stack retains the depth-to-bank mapping.
    integer alloc_i;
    always_comb begin
        irq_alloc_bank     = snap_sp;
        irq_bank_available = (snap_sp < SP_W'(SNAP_DEPTH));
        if (CTX_MODE == CTX_MODE_MIXED) begin
            irq_alloc_bank     = '0;
            irq_bank_available = 1'b0;
            for (alloc_i=0; alloc_i<SNAP_DEPTH; alloc_i=alloc_i+1) begin
                if (!irq_bank_available && !task_bank_valid[alloc_i] &&
                    !irq_bank_valid[alloc_i]) begin
                    irq_alloc_bank     = SP_W'(alloc_i);
                    irq_bank_available = 1'b1;
                end
            end
        end
    end

    assign push_full = ~irq_bank_available;
    assign pop_empty = (snap_sp == '0);
    assign push_fire = IRQ_OPS_ENABLED && op_push && !push_full;
    assign pop_fire  = IRQ_OPS_ENABLED && op_pop  && !pop_empty;
    assign sreg_nest_allow = IRQ_OPS_ENABLED && ~push_full;

    // error policy:
    // - unknown funct7 => error (保持原行为，便于发现非法指令)
    // - push_full / pop_empty => no-op but NOT error (保证确定性和前进性)
    always_comb begin
        sreg_error = sreg_req;
        if (op_wr_legacy || op_rd_legacy ||
            (IRQ_OPS_ENABLED && (op_push || op_pop)) ||
            (TASK_OPS_ENABLED && (op_task_bind0 || op_task_bind1 ||
                                  op_task_bind2 || task_save_fire ||
                                  task_restore_fire)))
            sreg_error = 1'b0;
`ifdef SOPHON_TASK_WB
        if (op_temp_capture)
            sreg_error = !capture_format_ok || !capture_address_ok || capture_error;
`endif
    end

    // write enable: legacy write OR push-save (if not full)
    always_comb begin
        sreg_wr = 1'b0;
        if (op_wr_legacy) sreg_wr = 1'b1;
        else if (push_fire) sreg_wr = 1'b1;
        else if (task_save_fire) sreg_wr = 1'b1;
`ifdef SOPHON_TASK_WB
        else if (capture_fire) sreg_wr = 1'b1;
`endif
    end

    // bank selection
    always_comb begin
        wr_bank_sel = '0;
        if (push_fire)
            wr_bank_sel = (CTX_MODE == CTX_MODE_MIXED) ? irq_alloc_bank : snap_sp;
        else if (task_save_fire) wr_bank_sel = task_bank_sel;
        else wr_bank_sel = '0; // legacy -> bank0
`ifdef SOPHON_TASK_WB
        if (capture_fire) wr_bank_sel = SP_W'(2);
`endif
    end

    always_comb begin
        rd_bank_sel = '0;
        if (pop_fire)
            rd_bank_sel = (CTX_MODE == CTX_MODE_MIXED) ?
                          irq_bank_stack[snap_sp - SP_W'(1)] :
                          snap_sp - SP_W'(1); // pop reads current logical top
        else if (TASK_OPS_ENABLED && op_task_rest0) rd_bank_sel = '0;
        else if (TASK_OPS_ENABLED && op_task_rest1) rd_bank_sel = SP_W'(1);
        else if (TASK_OPS_ENABLED && op_task_rest2) rd_bank_sel = SP_W'(2);
        else rd_bank_sel = '0; // legacy read or empty pop -> bank0
    end

    // compute batch bitmask
    integer j;
    always_comb begin
        wr_sreg_bit = 32'd0;
        for (j=0; j<32; j=j+1)
            wr_sreg_bit[j] = ((sreg_batch_start <= 6'(j)) &&
                              ((sreg_batch_len + sreg_batch_start) > 6'(j))) ? 1'b1 : 1'b0;
    end

    generate
`ifdef SNAPREG_CG_FRIENDLY
        // Explicit per-bank write enables help DC infer clock gating for idle
        // context banks when the cg synthesis flow is used.
        for (genvar b=0; b<SNAP_DEPTH; b=b+1) begin: gen_bank_wr_en
            assign bank_wr_en[b] = sreg_wr && (wr_bank_sel == SP_W'(b));
        end

        for (genvar b=0; b<SNAP_DEPTH; b=b+1) begin: gen_snap_bank
            for (genvar i=1; i<32; i=i+1) begin: gen_snap_reg
                always_ff @(posedge clk_i, negedge rst_ni) begin
                    if (~rst_ni) begin
                        snap_bank[b][i] <= 32'd0;
                    end
                    else if (bank_wr_en[b] && (wr_sreg_bit[i]==1'b1)) begin
                        snap_bank[b][i] <= sreg_rs_val[i - sreg_batch_start];
                    end
                end
            end
        end
`else
        // Baseline implementation used before the clock-gating optimization.
        // Keep this as the default so nocg area/power matches the old DCout data.
        for (genvar i=1; i<32; i=i+1) begin: gen_snap_bank
            integer b;
            always_ff @(posedge clk_i, negedge rst_ni) begin
                if (~rst_ni) begin
                    for (b=0; b<SNAP_DEPTH; b=b+1) begin
                        snap_bank[b][i] <= 32'd0;
                    end
                end
                else if (sreg_wr && (wr_sreg_bit[i]==1'b1)) begin
                    snap_bank[wr_bank_sel][i] <= sreg_rs_val[i - sreg_batch_start];
                end
            end
        end
`endif
    endgenerate

    // x0 always zero
    generate
        for (genvar b=0; b<SNAP_DEPTH; b=b+1) begin: gen_x0
            assign snap_bank[b][0] = 32'd0;
        end
    endgenerate

    // stack pointer update
    always_ff @(posedge clk_i, negedge rst_ni) begin
        if (~rst_ni) begin
            snap_sp <= '0;
        end
        else begin
            if (push_fire)
                snap_sp <= snap_sp + SP_W'(1);
            else if (pop_fire)
                snap_sp <= snap_sp - SP_W'(1);
        end
    end

    // Physical ownership used only by Mode 2.  irq_bank_stack is distinct
    // from the logical CSR stack in sophon.sv: the latter already stores
    // architectural CSR frames by nesting depth, while this one maps each
    // depth to the borrowed SnapReg bank.
    integer irq_i;
    always_ff @(posedge clk_i, negedge rst_ni) begin
        if (~rst_ni) begin
            irq_bank_valid <= '0;
            for (irq_i=0; irq_i<SNAP_DEPTH; irq_i=irq_i+1)
                irq_bank_stack[irq_i] <= '0;
        end
        else if (CTX_MODE == CTX_MODE_MIXED) begin
            if (push_fire) begin
                irq_bank_valid[irq_alloc_bank] <= 1'b1;
                irq_bank_stack[snap_sp] <= irq_alloc_bank;
            end
            else if (pop_fire) begin
                irq_bank_valid[irq_bank_stack[snap_sp - SP_W'(1)]] <= 1'b0;
            end
        end
    end

    // Fixed-bank task-demo metadata.  This is control metadata only: all GPR
    // values remain in the pre-existing snap_bank array.
    always_ff @(posedge clk_i, negedge rst_ni) begin
        if (~rst_ni) begin
            task_bank_sel   <= '0;
            task_bank_valid <= '0;
        end
        else begin
            if (TASK_OPS_ENABLED && op_task_bind0)
                task_bank_sel <= '0;
            else if (TASK_OPS_ENABLED && op_task_bind1)
                task_bank_sel <= SP_W'(1);
            else if (TASK_OPS_ENABLED && op_task_bind2)
                task_bank_sel <= SP_W'(2);
            else if (TASK_OPS_ENABLED && op_task_rest0)
                task_bank_sel <= '0;
            else if (TASK_OPS_ENABLED && op_task_rest1)
                task_bank_sel <= SP_W'(1);
            else if (TASK_OPS_ENABLED && op_task_rest2)
                task_bank_sel <= SP_W'(2);

            if (task_save_fire)
                task_bank_valid[task_bank_sel] <= 1'b1;
            else if (task_restore_fire && op_task_rest0)
                task_bank_valid[0] <= 1'b0;
            else if (task_restore_fire && op_task_rest1)
                task_bank_valid[1] <= 1'b0;
            else if (task_restore_fire && op_task_rest2)
                task_bank_valid[2] <= 1'b0;
`ifdef SOPHON_TASK_WB
            // Independent from bank 0/1 updates on the same core edge.
            if (capture_fire)
                task_bank_valid[2] <= 1'b1;
            else if (wb_release_fire)
                task_bank_valid[2] <= 1'b0;
`endif
        end
    end

    // readout (same wrap technique as original snapreg.sv)
    localparam int unsigned EXT_RF_LEN = 32 + `EEI_RD_MAX - 1;
    logic [31:0] ext_snapreg[EXT_RF_LEN-1:0];

    for (genvar t=0; t<EXT_RF_LEN; t++) begin : gen_ext_snapreg
        if (t < 32)
            assign ext_snapreg[t] = snap_bank[rd_bank_sel][t];
        else
            assign ext_snapreg[t] = snap_bank[rd_bank_sel][t-32];
    end

    genvar k;
    generate
        for (k=0; k<`EEI_RD_MAX; k=k+1) begin: gen_sreg_rd_val
            // TASK_SAVE returns the selected bank in rd.  The trap handler
            // uses it only to update its software-visible validity flag.
            if (k == 0)
                assign sreg_rd_val[k] = task_save_fire ? task_bank_sel :
                                                       ext_snapreg[k + sreg_batch_start];
            else
                assign sreg_rd_val[k] = ext_snapreg[k + sreg_batch_start];
        end
    endgenerate

`endif

endmodule
