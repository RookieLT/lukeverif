package chnl_pkg;
	import uvm_pkg::*;
	`include "uvm_macros.svh"

	class chnl_trans extends uvm_sequence_item;
		rand bit[31:0] data[];
    rand int ch_id;
    rand int pkt_id;
    rand int data_nidles;
    rand int pkt_nidles;
    bit rsp;
    constraint cstr{
      soft data.size inside {[4:32]};
      foreach(data[i]) data[i] == 'hC000_0000 + (this.ch_id<<24) + (this.pkt_id<<8) + i;
      soft ch_id == 0;
      soft pkt_id == 0;
      soft data_nidles inside {[0:2]};
      soft pkt_nidles inside {[1:10]};
    };


		`uvm_object_utils_begin(chnl_trans)
			`uvm_field_array_int(data,UVM_ALL_ON)
			`uvm_field_int(ch_id,UVM_ALL_ON)
			`uvm_field_int(pkt_id,UVM_ALL_ON)
			`uvm_field_int(data_nidles,UVM_ALL_ON)
			`uvm_field_int(pkt_nidles,UVM_ALL_ON)
			`uvm_field_int(rsp,UVM_ALL_ON)
		`uvm_object_utils_end

		function new(string name = "chnl_trans");
			super.new(name);
		endfunction

	endclass

	class chnl_driver extends uvm_driver;
		local string name;
		local virtual chnl_intf intf;
		mailbox #(chnl_trans) req_mb;
		mailbox #(chnl_trans) rsp_mb;

		`uvm_component_utils(chnl_driver)

		function new(string name = "chnl_driver", uvm_component parent);
			super.new(name,parent);
		endfunction
		
		function void build_phase(uvm_phase phase);
			super.build_phase(phase);
			if(!`uvm_config_db#(virtual chnl_intf)::get(this,"","intf",intf))
				`uvm_info("no valid interface is assigned",UVM_LOW)
		endfunction

		task run_phase(uvm_phase phase);
			super.run_phase(phase);
			fork
				this.do_drive();
				this.do_reset();
			join
		endtask

		task do_reset();
      forever begin
        @(negedge intf.rstn);
        intf.ch_valid <= 0;
        intf.ch_data <= 0;
      end
    endtask

    task do_drive();
      chnl_trans req, rsp;
      @(posedge intf.rstn);
      forever begin
        this.req_mb.get(req);
        this.chnl_write(req);
        rsp = req.clone();
        rsp.rsp = 1;
        this.rsp_mb.put(rsp);
      end
    endtask
  
    task chnl_write(input chnl_trans t);
      foreach(t.data[i]) begin
        @(posedge intf.clk);
        intf.drv_ck.ch_valid <= 1;
        intf.drv_ck.ch_data <= t.data[i];
        @(negedge intf.clk);
        wait(intf.ch_ready === 'b1);
        $display("%0t channel driver [%s] sent data %x", $time, name, t.data[i]);
        repeat(t.data_nidles) chnl_idle();
      end
      repeat(t.pkt_nidles) chnl_idle();
    endtask
    
    task chnl_idle();
      @(posedge intf.clk);
      intf.drv_ck.ch_valid <= 0;
      intf.drv_ck.ch_data <= 0;
    endtask

	endclass

	class chnl_generator extends uvm_component;
		rand int pkt_id = 0;
    rand int ch_id = -1;
    rand int data_nidles = -1;
    rand int pkt_nidles = -1;
    rand int data_size = -1;
    rand int ntrans = 10;

    mailbox #(chnl_trans) req_mb;
    mailbox #(chnl_trans) rsp_mb;

    constraint cstr{
      soft ch_id == -1;
      soft pkt_id == 0;
      soft data_size == -1;
      soft data_nidles == -1;
      soft pkt_nidles == -1;
      soft ntrans == 10;
    }

		`uvm_component_utils(chnl_generator)
		function new(string name = "chnl_generator", uvm_component parent);
			super.new(name,parent);
		endfunction

		function void build_phase(uvm_phase phase);
			super.build_phase(phase);
			this.req_mb = new();
			this.rsp_bm = new();
		endfunction

		task run_phase(uvm_phase phase);
			super.run_phase(phase);
			this.start();
		endtask
		
		task start();
      repeat(ntrans) send_trans();
    endtask

    task send_trans();
      chnl_trans req, rsp;
      req = new();
      assert(req.randomize with {local::ch_id >= 0 -> ch_id == local::ch_id; 
                                 local::pkt_id >= 0 -> pkt_id == local::pkt_id;
                                 local::data_nidles >= 0 -> data_nidles == local::data_nidles;
                                 local::pkt_nidles >= 0 -> pkt_nidles == local::pkt_nidles;
                                 local::data_size >0 -> data.size() == local::data_size; 
                               })
        else $fatal("[RNDFAIL] channel packet randomization failure!");
      this.pkt_id++;
      $display(req.sprint());
      this.req_mb.put(req);
      this.rsp_mb.get(rsp);
      $display(rsp.sprint());
      assert(rsp.rsp)
        else $error("[RSPERR] %0t error response received!", $time);
    endtask

    function string sprint();
      string s;
      s = {s, $sformatf("=======================================\n")};
      s = {s, $sformatf("chnl_generator object content is as below: \n")};
      s = {s, $sformatf("ntrans = %0d: \n", this.ntrans)};
      s = {s, $sformatf("ch_id = %0d: \n", this.ch_id)};
      s = {s, $sformatf("pkt_id = %0d: \n", this.pkt_id)};
      s = {s, $sformatf("data_nidles = %0d: \n", this.data_nidles)};
      s = {s, $sformatf("pkt_nidles = %0d: \n", this.pkt_nidles)};
      s = {s, $sformatf("data_size = %0d: \n", this.data_size)};
      s = {s, $sformatf("=======================================\n")};
      return s;
    endfunction

    function void post_randomize();
      string s;
      s = {"AFTER RANDOMIZATION \n", this.sprint()};
      $display(s);
    endfunction

	endclass

	class chnl_monitor extends uvm_monitor;
		local string name;
    local virtual chnl_intf intf;
    mailbox #(mon_data_t) mon_mb;

		`uvm_component_utils(chnl_monitor)

		function new(string name = "chnl_monitor", uvm_component parent);
			super.new(name,parent);
		endfunction

		function void build_phase(uvm_phase phase);
			super.build_phase(phase);
			uvm_config_db#(virtual interface chnl_intf)::get(this,"","intf",intf);
		endfunction

		task run_phase(uvm_phase phase);
			super.run_phase(phase);
			this.mon_trans();
		endtask

		task mon_trans();
      mon_data_t m;
      forever begin
        @(posedge intf.clk iff (intf.mon_ck.ch_valid==='b1 && intf.mon_ck.ch_ready==='b1));
        m.data = intf.mon_ck.ch_data;
        mon_mb.put(m);
        $display("%0t %s monitored channle data %8x", $time, this.name, m.data);
      end
    endtask
	endclass

	class chnl_agent extends uvm_agent;
		local string name;
    chnl_driver driver;
    chnl_monitor monitor;
		local virtual chnl_intf vif;

		`uvm_component_utils(chnl_agent)
		function new(string name = "chnl_agent", uvm_component parent);
			super.new(name,parent);
		endfunction

		function void build_phase(uvm_phase phase);
			super.build_phase(phase);
			driver = chnl_driver::type_id::create("chnl_driver",this);
			monitor = chnl_monitor::type_id::create("chnl_monitor",this);
			uvm_config_db#(virtual chnl_intf)::get(this,"","vif",vif);
			uvm_config_db#(virtual chnl_intf)::set(this,"driver","intf",intf);
			uvm_config_db#(virtual chnl_intf)::set(this,"monitor","intf",intf);
		endfunction

		task run_phase(uvm_phase phase);
			super.run_phase(phase);
			fork
				driver.run_phase();
				monitor.run_phase();
			join
		endtask
	endclass

endpackage





		


