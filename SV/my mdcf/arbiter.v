//------------------------------------------------------------------------------------------------------------------------//
//change log 2017-08-20 Arbiter complete package length select and keep Not in Formater
//                      Need to update to configurable round robin arbiter  -----  @@ZS
//------------------------------------------------------------------------------------------------------------------------//
module arbiter(
input                    clk_i,
input                    rstn_i,

//connect with registers
input  [1:0]             slv0_prio_i,
input  [1:0]             slv1_prio_i,
input  [1:0]             slv2_prio_i,
input [2:0] 				 slv0_pkglen_i,
input [2:0]					 slv1_pkglen_i,
input [2:0]					 slv2_pkglen_i,

//connect with slave port
input  [31:0]            slv0_data_i,
input  [31:0]            slv1_data_i,
input  [31:0]            slv2_data_i,
input                    slv0_req_i,
input                    slv1_req_i,
input                    slv2_req_i,
input                    slv0_val_i,
input                    slv1_val_i,
input                    slv2_val_i,
output                   a2s0_ack_o,
output                   a2s1_ack_o,
output                   a2s2_ack_o,

//connect with formater
input                    f2a_id_req_i,
input                    f2a_ack_i,
output                   a2f_val_o,
output [1:0]             a2f_id_o,
output [31:0]            a2f_data_o,
output [2:0] 				 a2f_pkglen_sel_o
);
//////////////////////////////////////////////////////////


endmodule
