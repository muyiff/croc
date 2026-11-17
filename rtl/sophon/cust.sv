// ----------------------------------------------------------------------
// Copyright 2023 TimingWalker
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
// ----------------------------------------------------------------------
// Create Date   : 2023-01-11 16:52:34
// Last Modified : 2025-03-14 14:56:10
// Description   : Custom execution units
// ----------------------------------------------------------------------

module CUST(
     input logic                            clk_i
    ,input logic                            clk_neg_i
    ,input logic                            rst_ni
`ifdef SOPHON_TASK_WB
    ,output SOPHON_PKG::mem_req_t            task_wb_req
    ,input logic                            task_wb_commit
`endif
`ifdef SOPHON_EEI
    // eei interface
    ,input  logic                           eei_req
    ,input  logic                           eei_ext
    ,input  logic [2:0]                     eei_funct3
    ,input  logic [6:0]                     eei_funct7
    ,input  logic [4:0]                     eei_batch_start
    ,input  logic [4:0]                     eei_batch_len
    ,output logic [4:0]                     eei_rd_len  // if eei_rd_op=2, indicate write back rd number
    ,input  logic [31:0]                    eei_rs_val[`EEI_RS_MAX-1:0]
    ,output logic                           eei_ack  
    ,output logic [1:0]                     eei_rd_op   // 0: don't write rd
                                                        // 1: write single rd
                                                        // 2: batch write rd
                                                        // TBD: merge this signal with eei_rd_len
    ,output logic                           eei_error
    ,output logic [31:0]                    eei_rd_val[`EEI_RD_MAX-1:0]
`ifdef SOPHON_EEI_SREG
    ,output logic                           sreg_nest_allow_o
`endif
`endif
`ifdef SOPHON_EEI_GPIO
    // gpio interface 
    ,output logic [`FGPIO_NUM-1:0]          gpio_dir
    ,input  logic [`FGPIO_NUM-1:0]          gpio_in_val
    ,output logic [`FGPIO_NUM-1:0]          gpio_out_val
`endif

);

`ifdef SOPHON_TASK_WB
`ifndef SOPHON_EEI
    TASK_WB_REQUIRES_EEI invalid_missing_eei();
`endif
`ifndef SOPHON_EEI_SREG
    TASK_WB_REQUIRES_SREG invalid_missing_sreg();
`endif
`endif


    // ----------------------------------------------------------------------
    //  fast gpio control instruction extention
    // ----------------------------------------------------------------------

    `ifdef SOPHON_EEI_GPIO

        logic               fgpio_req;
        logic               fgpio_ack;
        logic               fgpio_error;
        logic [31:0]        fgpio_rd_val[`EEI_RD_MAX-1:0];

        // fgpio uses both regular EEI and enhanced EEI instructions
        assign fgpio_req = eei_req & ( eei_funct3==3'b000 ) ;

        FGPIO U_FGPIO (
            .clk_i           ( clk_i         ) ,
            .clk_neg_i       ( clk_neg_i     ) ,
            .rst_ni          ( rst_ni        ) ,
            .eei_ext         ( eei_ext       ) ,
            .fgpio_req       ( fgpio_req     ) ,
            .fgpio_funct7    ( eei_funct7    ) ,
            .fgpio_batch_len ( eei_batch_len ) ,
            .fgpio_rs_val    ( eei_rs_val    ) ,
            .fgpio_ack       ( fgpio_ack     ) ,
            .fgpio_error     ( fgpio_error   ) ,
            .fgpio_rd_val    ( fgpio_rd_val  ) ,
            .gpio_dir        ( gpio_dir      ) ,
            .gpio_in_val     ( gpio_in_val   ) ,
            .gpio_out_val    ( gpio_out_val  ) 
        );

    `endif


    // ----------------------------------------------------------------------
    //  snapshot instruction extention
    // ----------------------------------------------------------------------

    `ifdef SOPHON_EEI_SREG

        logic               sreg_req;
        logic               sreg_ack;
        logic               sreg_error;
        logic               sreg_nest_allow;
        logic [31:0]        sreg_rd_val[`EEI_RD_MAX-1:0];
`ifdef SOPHON_TASK_WB
        logic wb_command_req, wb_format_ok, wb_command_ack, wb_command_error;
        logic capture_req, capture_ack, capture_error, capture_fire, wb_release_fire;
        logic [31:0] capture_frame_base, wb_reg_data;
        logic [4:0] wb_reg_index;
        // Invalid builds must fail elaboration, including synthesis, not silently fall back.
        if (`SNAP_CONTEXT_MODE != 1 || `SNAP_DEPTH != 3 ||
            `EEI_RS_MAX != 32 || `EEI_RD_MAX != 32) begin : gen_bad_task_wb_config
            TASK_WB_REQUIRES_MODE1_DEPTH3_EEI32 invalid_configuration();
        end
`ifdef SOPHON_RVE
        TASK_WB_REQUIRES_RV32I invalid_rve();
`endif
`ifdef SOPHON_EEI_NOALIGN
        TASK_WB_REQUIRES_ALIGNED_EEI invalid_noalign();
`endif
`ifdef SOPHON_EEI_RS_LOCK
        TASK_WB_REQUIRES_UNLOCKED_EEI invalid_rs_lock();
`endif
        assign wb_command_req = sreg_req && ((eei_funct7 == 7'h15) ||
                                                           (eei_funct7 == 7'h16));
        assign wb_format_ok = (eei_batch_start == 0) && (eei_batch_len == 0);
        TASK_CONTEXT_WB U_TASK_CONTEXT_WB (
            .clk_i(clk_i), .clk_neg_i(clk_neg_i), .rst_ni(rst_ni),
            .capture_req(capture_req), .capture_ack(capture_ack),
            .capture_error(capture_error), .capture_fire(capture_fire),
            .capture_frame_base(capture_frame_base),
            .start_req(wb_command_req && wb_format_ok && (eei_funct7 == 7'h15)),
            .sync_req(wb_command_req && wb_format_ok && (eei_funct7 == 7'h16)),
            .command_ack(wb_command_ack), .command_error(wb_command_error),
            .wb_reg_index(wb_reg_index), .wb_reg_data(wb_reg_data),
            .wb_req(task_wb_req), .wb_commit(task_wb_commit),
            .release_fire(wb_release_fire)
        );
`endif

        assign sreg_req  = eei_req &  eei_ext & ( eei_funct3==3'b001 ) ;
        //assign sreg_req  = eei_req &  eei_ext & ( eei_funct3==3'b000 ) ;

        SNAPREG #(
            .SNAP_DEPTH (`SNAP_DEPTH),
            .CTX_MODE   (`SNAP_CONTEXT_MODE)
        ) U_SNAPREG (
            .clk_i              ( clk_i           ) ,
            .rst_ni             ( rst_ni          ) ,
            .sreg_req           ( sreg_req
`ifdef SOPHON_TASK_WB
                                  && !wb_command_req
`endif
                                ) ,
            .sreg_funct7        ( eei_funct7      ) ,
            .sreg_batch_start   ( eei_batch_start ) ,
            .sreg_batch_len     ( eei_batch_len   ) ,
            .sreg_rs_val        ( eei_rs_val      ) ,
            .sreg_ack           ( sreg_ack        ) ,
            .sreg_error         ( sreg_error      ) ,
            .sreg_rd_val        ( sreg_rd_val     ) ,
            .sreg_nest_allow    ( sreg_nest_allow )
`ifdef SOPHON_TASK_WB
            ,.capture_req(capture_req), .capture_ack(capture_ack)
            ,.capture_error(capture_error), .capture_fire(capture_fire)
            ,.capture_frame_base(capture_frame_base), .wb_release_fire(wb_release_fire)
            ,.wb_reg_index(wb_reg_index), .wb_reg_data(wb_reg_data)
`endif
        );

    `endif

    `ifdef SOPHON_EEI_SREG
        assign sreg_nest_allow_o = sreg_nest_allow;
    `endif


    // ----------------------------------------------------------------------
    //  EEI response
    // ----------------------------------------------------------------------

	`ifdef SOPHON_EEI
		
		always_comb begin
			eei_ack   = eei_req;
			eei_error = 1'b0;
			`ifdef SOPHON_EEI_GPIO
				if ( fgpio_req ) begin
					eei_ack   = fgpio_ack;
					eei_error = fgpio_error;
				end
			`endif
			`ifdef SOPHON_EEI_SREG
				if ( sreg_req ) begin
					eei_ack   = sreg_ack;
					eei_error = sreg_error;
`ifdef SOPHON_TASK_WB
                    if (wb_command_req) begin
                        eei_ack   = wb_format_ok ? wb_command_ack : 1'b1;
                        eei_error = !wb_format_ok || wb_command_error;
                    end
`endif
				end
			`endif
		end

		for (genvar i=0; i<`EEI_RD_MAX; i++) begin : gen_cust_rd_val
            // // TODO: 
			// `ifdef SOPHON_EEI_GPIO
            //     assign eei_rd_val[i]=fgpio_rd_val[i];
            // `else
            //     assign eei_rd_val[i]='0;
            // `endif
            always_comb begin
                eei_rd_val[i] = 32'd0;
                `ifdef SOPHON_EEI_GPIO
                    if (fgpio_req)
                        eei_rd_val[i] = fgpio_rd_val[i];
                `endif
                `ifdef SOPHON_EEI_SREG
                    if (sreg_req)
                        eei_rd_val[i] = sreg_rd_val[i];
                `endif
            end

			// if ( i==0 ) begin: gen_cust_rd0
			// 	always_comb begin
			// 		eei_rd_val[i] = 32'd0;
			// 		`ifdef SOPHON_EEI_GPIO
			// 			if ( fgpio_req )
			// 				eei_rd_val[i] = fgpio_rd_val[i];
			// 		`endif
			// 		`ifdef SOPHON_EEI_SREG
			// 			if ( sreg_req )
			// 				eei_rd_val[i] = sreg_rd_val[i];
			// 		`endif
			// 	end
			// end
			// else begin: gen_cust_rd_extend
			// 	always_comb begin
			// 		eei_rd_val[i] = 32'd0;
			// 		`ifdef SOPHON_EEI_GPIO
			// 			if ( fgpio_req )
			// 				eei_rd_val[i] = fgpio_rd_val[i];
			// 		`endif
			// 		`ifdef SOPHON_EEI_SREG
			// 			if ( sreg_req )
			// 				eei_rd_val[i] = sreg_rd_val[i];
			// 		`endif
			// 	end
			// end
		end        

		always_comb begin
			eei_rd_op  = 2'd0;
			eei_rd_len = 5'd0;
			`ifdef SOPHON_EEI_GPIO
				if (fgpio_req & ~eei_ext) 
					eei_rd_op = 2'd1;
				else if (fgpio_req & eei_ext) begin
					eei_rd_op = 2'd3;
					eei_rd_len = eei_batch_len;
				end
			`endif
			`ifdef SOPHON_EEI_SREG
				if (sreg_req ) begin
                    if (eei_funct7 >= 7'h14 && eei_funct7 <= 7'h16) begin
                        eei_rd_op  = 2'd0;
                        eei_rd_len = 5'd0;
                    end
					else if (eei_funct7 == 7'h12) begin
						eei_rd_op  = 2'd1;
						eei_rd_len = 5'd1;
					end
					else if (eei_funct7[6]==1'b1) begin
						eei_rd_op = 2'd2;
						eei_rd_len = eei_batch_len;
					end
					else
						eei_rd_op = 2'd0;
				end
			`endif
		end
	`endif

always_ff @(posedge clk_i) begin
    if (eei_req) begin
        $display("[EEI] f3=%0d f7=0x%0h ext=%0d start=%0d len=%0d",
                 eei_funct3, eei_funct7, eei_ext, eei_batch_start, eei_batch_len);
    end
`ifdef SOPHON_EEI_SREG
    if (sreg_req) begin
        $display("[SREG] HIT! f7=0x%0h start=%0d len=%0d rd_op=%0d",
                 eei_funct7, eei_batch_start, eei_batch_len, eei_rd_op);
    end
`endif
end

// always_ff @(posedge clk_i) begin
//     if (sreg_req && eei_funct7[6]) begin
//         $display("[CUST] POP muxed eei_rd_val0=%h eei_rd_val1=%h",
//                  eei_rd_val[0], eei_rd_val[1]);
//     end
// end


endmodule
