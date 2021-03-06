// Copyright (c) 2014-2015, Intel Corporation
//
// Redistribution  and  use  in source  and  binary  forms,  with  or  without
// modification, are permitted provided that the following conditions are met:
//
// * Redistributions of  source code  must retain the  above copyright notice,
//   this list of conditions and the following disclaimer.
// * Redistributions in binary form must reproduce the above copyright notice,
//   this list of conditions and the following disclaimer in the documentation
//   and/or other materials provided with the distribution.
// * Neither the name  of Intel Corporation  nor the names of its contributors
//   may be used to  endorse or promote  products derived  from this  software
//   without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING,  BUT NOT LIMITED TO,  THE
// IMPLIED WARRANTIES OF  MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED.  IN NO EVENT  SHALL THE COPYRIGHT OWNER  OR CONTRIBUTORS BE
// LIABLE  FOR  ANY  DIRECT,  INDIRECT,  INCIDENTAL,  SPECIAL,  EXEMPLARY,  OR
// CONSEQUENTIAL  DAMAGES  (INCLUDING,  BUT  NOT LIMITED  TO,  PROCUREMENT  OF
// SUBSTITUTE GOODS OR SERVICES;  LOSS OF USE,  DATA, OR PROFITS;  OR BUSINESS
// INTERRUPTION)  HOWEVER CAUSED  AND ON ANY THEORY  OF LIABILITY,  WHETHER IN
// CONTRACT,  STRICT LIABILITY,  OR TORT  (INCLUDING NEGLIGENCE  OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,  EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.

module afu_user #(ADDR_LMT = 20, MDATA = 14, CACHE_WIDTH = 512) 
(
   input 		    clk, 
   input 		    reset_n, 
   
   // Read Request
   output [ADDR_LMT-1:0]    rd_req_addr, 
   output [MDATA-1:0] 	    rd_req_mdata, 
   output 		    rd_req_en, 
   input 		    rd_req_almostfull, 
   
   // Read Response
   input 		    rd_rsp_valid, 
   input [MDATA-1:0] 	    rd_rsp_mdata, 
   input [CACHE_WIDTH-1:0]  rd_rsp_data, 

   // Write Request 
   output [ADDR_LMT-1:0]    wr_req_addr, 
   output [MDATA-1:0] 	    wr_req_mdata, 
   output [CACHE_WIDTH-1:0] wr_req_data, 
   output 		    wr_req_en, 
   input 		    wr_req_almostfull, 
   
   // Write Response 
   input 		    wr_rsp0_valid, 
   input [MDATA-1:0] 	    wr_rsp0_mdata, 
   input 		    wr_rsp1_valid, 
   input [MDATA-1:0] 	    wr_rsp1_mdata, 
   
   // Start input signal
   input 		    start, 

   // Done output signal 
   output  		    done, 

   // Control info from software
   input [511:0] 	    afu_context
);
   /* DBS's favorite polarity */
   wire 		   rst = ~reset_n;
      
   /* read base address from ctx register */
   wire [63:0]     w_base_ptr = afu_context[(256+64+-1):256]; 
   reg [63:0] 	   r_base_ptr, n_base_ptr;
   reg [63:0] 	   r_head_ptr, n_head_ptr;
   
   /* read port */ 
   reg [ADDR_LMT-1:0] r_rd_req_addr, n_rd_req_addr;  
   reg [MDATA-1:0] r_rd_req_mdata, n_rd_req_mdata;
   reg 		   r_rd_req_en, n_rd_req_en;
   assign rd_req_addr = r_rd_req_addr;
   assign rd_req_mdata = r_rd_req_mdata;
   assign rd_req_en = r_rd_req_en;

   /* write port */
   reg [ADDR_LMT-1:0] r_wr_req_addr, n_wr_req_addr; 
   reg [MDATA-1:0] r_wr_req_mdata, n_wr_req_mdata;
   reg 		   r_wr_req_en, n_wr_req_en;
   reg [511:0] 	   r_wr_req_data,n_wr_req_data;
   assign wr_req_addr = r_wr_req_addr;
   assign wr_req_mdata = r_wr_req_mdata;
   assign wr_req_en = r_wr_req_en;
   assign wr_req_data = r_wr_req_data;

   reg [2:0] 		   r_state, n_state;
   reg 			   r_done,n_done;

   /* added: counter stuff */
   reg [63:0] r_counter;
   
   assign done = r_done;

   /* combinational signal to pop address from pe */
   reg 			   t_pop_addr;

   /* padding for metadata */
   wire [MDATA-6-1:0]  w_meta_pad = 'd0;

   /* we use the reply metadata to find the proper offset in
    * the cacheline to return to the PE */
   wire [63:0] 	       w_reply_data = 
		       (rd_rsp_mdata == 'd0) ? rd_rsp_data[63:0] :
		       (rd_rsp_mdata == 'd8) ? rd_rsp_data[127:64] :
		       (rd_rsp_mdata == 'd16) ? rd_rsp_data[191:128] :
		       (rd_rsp_mdata == 'd24) ? rd_rsp_data[255:192] :
		       (rd_rsp_mdata == 'd32) ? rd_rsp_data[319:256] :
		       (rd_rsp_mdata == 'd40) ? rd_rsp_data[383:320] :
		       (rd_rsp_mdata == 'd48) ? rd_rsp_data[447:384] :
		       rd_rsp_data[511:448];
   

      
   always@(posedge clk)
     begin
	r_state <= rst ? 'd0 : n_state;
	r_done <= rst ? 1'b0 : n_done;   
	r_rd_req_addr <= rst ? 'd0 : n_rd_req_addr;  
	r_rd_req_mdata <= rst ? 'd0 : n_rd_req_mdata;
	r_rd_req_en <= rst ? 1'b0 : n_rd_req_en;
	r_wr_req_addr <= rst ? 'd0 : n_wr_req_addr;  
	r_wr_req_mdata <= rst ? 'd0 : n_wr_req_mdata;
	r_wr_req_en <= rst ? 1'b0 : n_wr_req_en;
	r_wr_req_data <= rst ? 'd0 : n_wr_req_data;
	r_base_ptr <= rst ? 'd0 : n_base_ptr;
	r_head_ptr <= rst ? 'd0 : n_head_ptr;
        if(rst) begin
            r_counter <= 'd0;
        end
     end

   /* read request FSM */
   always@(*)
     begin
	n_state = r_state;
	n_done = r_done;
	/* read port signals */
	n_rd_req_addr = r_rd_req_addr;  
	n_rd_req_mdata = r_rd_req_mdata;
	n_rd_req_en = 1'b0;
	/* write port signals */
	n_wr_req_addr = r_wr_req_addr;  
	n_wr_req_mdata = r_wr_req_mdata;
	n_wr_req_en = 1'b0;
	n_wr_req_data = r_wr_req_data;
	
	n_base_ptr = r_base_ptr;
	n_head_ptr = r_head_ptr;
	t_pop_addr = 1'b0;
	
	case(r_state)
	  'd0:
	    begin
	       /* we've got the go signal, configuration data should be valid */
	       if(start)
		 begin
		    n_base_ptr = w_base_ptr;
		    n_head_ptr = w_base_ptr + 'd64;
		    n_state = 'd1;
		 end
	    end
	  'd1:
	    begin
               $display("counter value: %d", r_counter);
               r_counter = r_counter + 1;
               if(r_counter == 'd100) begin
	         n_state = 'd2;
               end
	    end
	  'd2:
	    begin
	       /* write back the value of counter*/
	       if(!wr_req_almostfull)
		 begin
		    n_wr_req_addr = 'd0;
		    n_wr_req_data = r_counter;
		    n_wr_req_en = 1'b1;
		    n_state = 'd3;
		 end
	    end
	  'd3:
	    begin
	       if(wr_rsp0_valid || wr_rsp1_valid)
		 begin
		    n_state = 'd4;
		 end
	    end
	  'd4:
	    begin
	       n_done = 1'b1;
	    end
	  default:
	    begin
	       n_state = 'd0;
	    end
	endcase // case (r_state)
     end // always@ (*)
     
endmodule // afu_user





