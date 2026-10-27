// ----------------------------------------------------------------------
// Copyright 2025 TimingWalker
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// Last Modified : 2025-09-22 11:16:35
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
// ----------------------------------------------------------------------
// Create Date   : 2022-11-03 15:20:49
// Last Modified : 2025-09-22 11:16:35
// Description   : 
// ----------------------------------------------------------------------

package SOPHON_PKG;

    // ----------------------------------------------------------------------
    //  memory map
    // ----------------------------------------------------------------------

    // -----------------------------------
    //  Locol inst/data memory region
    // -----------------------------------
    localparam TCM_BASE       = 32'h8000_0000;
    localparam ITCM_OFFSET    = 32'h0000_0000;
    localparam DTCM_OFFSET    = 32'h0009_0000;
    // localparam ITCM_SIZE      = 32'h0000_1000;
    // localparam DTCM_SIZE      = 32'h0000_1000;
    localparam ITCM_SIZE      = 32'h0002_0000;
    localparam DTCM_SIZE      = 32'h0002_0000;

    // Do Not change
    localparam ITCM_BASE      = TCM_BASE+ITCM_OFFSET;
    localparam ITCM_END       = TCM_BASE+ITCM_OFFSET+ITCM_SIZE -1;
    localparam DTCM_BASE      = TCM_BASE+DTCM_OFFSET;
    localparam DTCM_END       = TCM_BASE+DTCM_OFFSET+DTCM_SIZE -1;

    // -----------------------------------
    //  External inst access region
    // -----------------------------------
    //  region1 DM: 0x000  ~ 0xFFF
    //  region2   : above 0x1000, 
    //              external inst memory
    // -----------------------------------

    localparam EXT_DM_BASE  = 32'h0000_0000;
    // DM Flag Address
    localparam DM_HALT      = EXT_DM_BASE+32'h0000_0800;
    localparam DM_EXCEPTION = DM_HALT + 32'h8;

    // 4KB DM + 64KM EXT INST MEM
    localparam EXT_INST_BASE = EXT_DM_BASE;
    //localparam EXT_INST_END  = 32'h0000_1000+32'h0000_ffff;
    // TODO: workaroud for DebugChangeString
    localparam EXT_INST_END  = 32'h0000_1000+32'h0001_ffff;

    // -----------------------------------
    //  External Data access region
    // -----------------------------------
    //  region1 : DM region
    //  region2 : external data memory
    //  region3 : external I/O region
    // -----------------------------------
    localparam EXT_DATA_BASE     = 32'h0000_0000;
    localparam EXT_DATA_END      = 32'h7fff_ffff;


    // ----------------------------------------------------------------------
    //  Constant define
    // ----------------------------------------------------------------------

    // CSR address
    localparam CSR_MVENDORID    = 12'hF11;
    localparam CSR_MARCHID      = 12'hF12;
    localparam CSR_MIMPID       = 12'hF13;
    localparam CSR_MHARTID      = 12'hF14;
    localparam CSR_MSTATUS      = 12'h300;
    localparam CSR_MISA         = 12'h301;
    // medeleg/mideleg
    localparam CSR_MIE          = 12'h304;
    localparam CSR_MTVEC        = 12'h305;
    localparam CSR_MSCRATCH     = 12'h340;
    localparam CSR_MEPC         = 12'h341;
    localparam CSR_MCAUSE       = 12'h342;
    localparam CSR_MTVAL        = 12'h343;
    localparam CSR_MIP          = 12'h344;
    localparam CSR_MCYCLE       = 12'hb00;
    localparam CSR_MCYCLEH      = 12'hb80;
    localparam CSR_MINSTRET     = 12'hb02;
    localparam CSR_MINSTRETH    = 12'hb82;
`ifdef SOPHON_CLIC
    // CLIC CSR
    localparam CSR_MTVT         = 12'h307;
    localparam CSR_XNXTI        = 12'h345;
    localparam CSR_MINTSTATUS   = 12'h346;
    localparam CSR_MINTTHRESH   = 12'h347;
`endif
`ifdef SOPHON_RVDEBUG
    // debug mode CSR
    localparam CSR_DCSR         = 12'h7b0;
    localparam CSR_DPC          = 12'h7b1;
    localparam CSR_DSCRATCH0    = 12'h7b2;
    localparam CSR_DSCRATCH1    = 12'h7b3;
    localparam CSR_DSCRATCH2    = 12'h7b4;
`endif

    // custom CSR
    // hardware parameter infomation
    localparam CSR_HW_PARAMETER = 12'hcc0;

    localparam BIT_MSI          = 3;
    localparam BIT_MTI          = 7;
    localparam BIT_MEI          = 11;


    // ----------------------------------------------------------------------
    //  structure define
    // ----------------------------------------------------------------------

    // typedef struct packed {
    //     logic           req;
    //     logic [31:0]    addr;
    // } inst_req_t;
    // typedef struct packed {
    //     logic           ack;
    //     logic           error;
    //     logic [31:0]    rdata;
    // } inst_ack_t;

    // typedef struct packed {
    //     logic           req;
    //     logic           we;
    //     logic [31:0]    addr;
    //     logic [31:0]    wdata;
    //     logic [3:0]     amo;
    //     logic [1:0]     size;
    //     logic [3:0]     strb;
    // } lsu_req_t;
    // typedef struct packed {
    //     logic           ack;
    //     logic           error;
    //     logic [31:0]    rdata;
    // } lsu_ack_t;

    typedef struct packed {
        logic           req;
        logic           we;
        logic [31:0]    addr;
        logic [31:0]    wdata;
        logic [3:0]     wstrb;
    } mem_req_t;

    typedef struct packed {
        logic           ack;
        logic           error;
        logic [31:0]    rdata;
    } mem_ack_t;

endpackage

