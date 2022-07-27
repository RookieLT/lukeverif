//------------------------------------------------------------------------------------------------------------------------//
//change log 2017-08-20 fix read pointer and write pointer 
//------------------------------------------------------------------------------------------------------------------------//
module slave_fifo (
input                       clk_i,                  // Clock input 
input                       rstn_i,                 // low level effective 
input [31:0]                chx_data_i,             // Data input                 ---->From outside
input                       a2sx_ack_i,             // Read ack                   ---->From Arbiter
input                       slvx_en_i,              // Write enable To Registers  ---->To Register
input                       chx_valid_i,            // Data is valid From outside ---->From Outside
output reg [31:0]           slvx_data_o,            // Data Output                ---->To Arbiter
output [5:0]                margin_o,               // Data margin                ---->To Registers
output reg                  chx_ready_o,            // Ready to accept data       ---->To outside
output reg                  slvx_val_o,             // read acknowledge Keep to handshake with Arbiter ----> To Arbiter
output reg                  slvx_req_o 
);     
//synchronous fifo
wire empty,full;
reg [5:0] rd_ptr,wr_ptr;
always @(posedge clk_i or negedge rstn_i)begin
	if(!rstn_i)
		wr_ptr <= 0;
	else if(slvx_en_i && chx_valid_i && !full) 
		wr_ptr <= wr_ptr + 1;
end

always @(posedge clk_i or negedge rstn_i) begin
	if(!rstn_i)
		rd_ptr <= 0;
	else if(slvx_en_i && a2sx_ack_i && !empty)
		rd_ptr <= rd_ptr + 1;
end

assign empty = wr_ptr==rd_ptr;
assign full = {!wr_ptr[5],wr_ptr[4:0]}==rd_ptr;

//dual port ram
reg [31 : 0] mem [31 : 0];
reg [31 : 0] slvx_data_reg;
integer i;
always @(posedge clk_i or negedge rstn_i) begin
	if(!rstn_i)
		for(i=0; i<32; i=i+1)
			mem[i] <= 0;
	else if(slvx_en_i && chx_valid_i && !full)
			mem[wr_ptr[4:0]] <= chx_data_i;
end
always @(posedge clk_i or negedge rstn_i) begin
	if(!rstn_i)
		slvx_data_reg <= 'b0;
	else if(slvx_en_i_$$ a2sx_ack_i && !empty)
		slvx_data_reg <= mem[rd_ptr[4:0]];
end


		



always 
endmodule 
