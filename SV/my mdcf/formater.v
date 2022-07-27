//------------------------------------------------------------------------------------------------------------------------//
//change log 2017-08-20 Move package length select to Arbiter 
//------------------------------------------------------------------------------------------------------------------------//
module formater(
                 input                      clk_i,
                 input                      rstn_i,
					  
                 //connect with arbiter
				         output                     f2a_ack_o,
                 output                     fmt_id_req_o,
                 input                      a2f_val_i,
                 input    [1:0]             a2f_id_i,
                 input    [31:0]            a2f_data_i,
					       input 	  [2:0] 				  pkglen_sel_i,
					  
                //connect with outside
				        input                      fmt_grant_i,
                output   [1:0]             fmt_chid_o,                  
                output   [5:0]             fmt_length_o,                  
                output                     fmt_req_o,
                output   [31:0]            fmt_data_o,
                output                     fmt_start_o,
                output                     fmt_end_o
               );

endmodule 
 
