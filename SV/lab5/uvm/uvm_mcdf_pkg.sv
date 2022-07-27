`include "param_def.v"

package mcdf_pkg;

	import chnl_pkg::*;
	import reg_pkg::*;
  import arb_pkg::*;
  import fmt_pkg::*;
  import rpt_pkg::*;
	
	typedef struct packed {
    bit[2:0] len;
    bit[1:0] prio;
    bit en;
    bit[7:0] avail;
  } mcdf_reg_t;

	typedef enum {RW_LEN, RW_PRIO, RW_EN, RD_AVAIL} mcdf_field_t;

	class mcdf_refmod extends uvm_component;
		local virtual mcdf_intf intf;
    mcdf_reg_t regs[3];
    mailbox #(reg_trans) reg_mb;
    mailbox #(mon_data_t) in_mbs[3];
    mailbox #(fmt_trans) out_mbs[3];

		`uvm_component_utils(mcdf_refmod)

		function new(string name = "mcdf_refmod", uvm_component parent);
			super.new(name,parent);
		endfunction

		function void build_phase(uvm_phase phase);
			foreach(this.out_mbs[i]) this.out_mbs[i] = new();
			uvm_config_db#(mcdf_intf)::get(this,"","intf",intf);
		endfunction

		task run_phase(uvm_phase phase);
			fork
        do_reset();
        this.do_reg_update();
        do_packet(0);
        do_packet(1);
        do_packet(2);
      join
    endtask

		task do_reg_update();
      reg_trans t;
      forever begin
        this.reg_mb.get(t);
        if(t.addr[7:4] == 0 && t.cmd == `WRITE) begin
          this.regs[t.addr[3:2]].en = t.data[0];
          this.regs[t.addr[3:2]].prio = t.data[2:1];
          this.regs[t.addr[3:2]].len = t.data[5:3];
        end
        else if(t.addr[7:4] == 1 && t.cmd == `READ) begin
          this.regs[t.addr[3:2]].avail = t.data[7:0];
        end
      end
    endtask

    task do_packet(int id);
      fmt_trans ot;
      mon_data_t it;
      forever begin
        this.in_mbs[id].peek(it);
        ot = new();
        ot.length = 4 << (this.get_field_value(id, RW_LEN) & 'b11);
        ot.data = new[ot.length];
        ot.ch_id = id;
        foreach(ot.data[m]) begin
          this.in_mbs[id].get(it);
          ot.data[m] = it.data;
        end
        this.out_mbs[id].put(ot);
      end
    endtask

    function int get_field_value(int id, mcdf_field_t f);
      case(f)
        RW_LEN: return regs[id].len;
        RW_PRIO: return regs[id].prio;
        RW_EN: return regs[id].en;
        RD_AVAIL: return regs[id].avail;
      endcase
    endfunction 

    task do_reset();
      forever begin
        @(negedge intf.rstn); 
        foreach(regs[i]) begin
          regs[i].len = 'h0;
          regs[i].prio = 'h3;
          regs[i].en = 'h1;
          regs[i].avail = 'h20;
        end
      end
    endtask

	endclass


	class mcdf_checker extends uvm_scoreboard;
		local string name;
    local int err_count;
    local int total_count;
    local int chnl_count[3];
    local virtual chnl_intf chnl_vifs[3]; 
    local virtual arb_intf arb_vif; 
    local virtual mcdf_intf mcdf_vif;
    local mcdf_refmod refmod;
    mailbox #(mon_data_t) chnl_mbs[3];
    mailbox #(fmt_trans) fmt_mb;
    mailbox #(reg_trans) reg_mb;
    mailbox #(fmt_trans) exp_mbs[3];

		`uvm_component_utils(mcdf_checker)

		function new(string name = "mcdf_checker", uvm_component parent);
			super.new(name,parent);
		endfunction

		function void build_phase(uvm_phase phase);
			foreach(this.chnl_mbs[i]) this.chnl_mbs[i] = new();
      this.fmt_mb = new();
      this.reg_mb = new();
      this.refmod = mcdf_refmod::type_id::create("mcdf_refmod",this);
			this.err_count = 0;
			this.total_count = 0;
      foreach(this.chnl_count[i]) this.chnl_count[i] = 0;
		endfunction

		function void connect_phase(uvm_phase phase);
      foreach(this.refmod.in_mbs[i]) begin
        this.refmod.in_mbs[i] = this.chnl_mbs[i];
        this.exp_mbs[i] = this.refmod.out_mbs[i];
      end
      this.refmod.reg_mb = this.reg_mb;
		endfunction

		task run_phase(uvm_phase phase);
			fork
        this.do_channel_disable_check(0);
        this.do_channel_disable_check(1);
        this.do_channel_disable_check(2);
        this.do_arbiter_priority_check();
        this.do_compare();
        this.refmod.run();
      join
    endtask


		task do_compare();
      fmt_trans expt, mont;
      bit cmp;
      forever begin
        this.fmt_mb.get(mont);
        this.exp_mbs[mont.ch_id].get(expt);
        cmp = mont.compare(expt);   
        this.total_count++;
        this.chnl_count[mont.ch_id]++;
        if(cmp == 0) begin
          this.err_count++;
          rpt_pkg::rpt_msg("[CMPFAIL]", 
            $sformatf("%0t %0dth times comparing but failed! MCDF monitored output packet is different with reference model output", $time, this.total_count),
            rpt_pkg::ERROR,
            rpt_pkg::TOP,
            rpt_pkg::LOG);
        end
        else begin
          rpt_pkg::rpt_msg("[CMPSUCD]",
            $sformatf("%0t %0dth times comparing and succeeded! MCDF monitored output packet is the same with reference model output", $time, this.total_count),
            rpt_pkg::INFO,
            rpt_pkg::HIGH);
        end
      end
    endtask

    task do_channel_disable_check(int id);
      forever begin
        @(posedge this.mcdf_vif.clk iff (this.mcdf_vif.rstn && this.mcdf_vif.mon_ck.chnl_en[id]===0));
        if(this.chnl_vifs[id].mon_ck.ch_valid===1 && this.chnl_vifs[id].mon_ck.ch_ready===1)
          rpt_pkg::rpt_msg("[CHKERR]", 
            $sformatf("ERROR! %0t when channel disabled, ready signal raised when valid high",$time), 
            rpt_pkg::ERROR, 
            rpt_pkg::TOP);
      end
    endtask

    task do_arbiter_priority_check();
      int id;
      forever begin
        @(posedge this.arb_vif.clk iff (this.arb_vif.rstn && this.arb_vif.mon_ck.f2a_id_req===1));
        id = this.get_slave_id_with_prio();
        if(id >= 0) begin
          @(posedge this.arb_vif.clk);
          if(this.arb_vif.mon_ck.a2s_acks[id] !== 1)
            rpt_pkg::rpt_msg("[CHKERR]",
              $sformatf("ERROR! %0t arbiter received f2a_id_req===1 and channel[%0d] raising request with high priority, but is not granted by arbiter", $time, id),
              rpt_pkg::ERROR,
              rpt_pkg::TOP);
        end
      end
    endtask

    function int get_slave_id_with_prio();
      int id=-1;
      int prio=999;
      foreach(this.arb_vif.mon_ck.slv_prios[i]) begin
        if(this.arb_vif.mon_ck.slv_prios[i] < prio && this.arb_vif.mon_ck.slv_reqs[i]===1) begin
          id = i;
          prio = this.arb_vif.mon_ck.slv_prios[i];
        end
      end
      return id;
    endfunction

    function void do_report();
      string s;
      s = "\n---------------------------------------------------------------\n";
      s = {s, "CHECKER SUMMARY \n"}; 
      s = {s, $sformatf("total comparison count: %0d \n", this.total_count)}; 
      foreach(this.chnl_count[i]) s = {s, $sformatf(" channel[%0d] comparison count: %0d \n", i, this.chnl_count[i])};
      s = {s, $sformatf("total error count: %0d \n", this.err_count)}; 
      foreach(this.chnl_mbs[i]) begin
        if(this.chnl_mbs[i].num() != 0)
          s = {s, $sformatf("WARNING:: chnl_mbs[%0d] is not empty! size = %0d \n", i, this.chnl_mbs[i].num())}; 
      end
      if(this.fmt_mb.num() != 0)
          s = {s, $sformatf("WARNING:: fmt_mb is not empty! size = %0d \n", this.fmt_mb.num())}; 
      s = {s, "---------------------------------------------------------------\n"};
      rpt_pkg::rpt_msg($sformatf("[%s]",this.name), s, rpt_pkg::INFO, rpt_pkg::TOP);
    endfunction
  endclass


  class mcdf_coverage extends uvm_component;
    local virtual chnl_intf chnl_vifs[3]; 
    local virtual arb_intf arb_vif; 
    local virtual mcdf_intf mcdf_vif;
    local virtual reg_intf reg_vif;
    local virtual fmt_intf fmt_vif;
    local string name;
    local int delay_req_to_grant;

		`uvm_component_utils(mcdf_coverage)

    covergroup cg_mcdf_reg_write_read;
      addr: coverpoint reg_vif.mon_ck.cmd_addr {
        type_option.weight = 0;
        bins slv0_rw_addr = {`SLV0_RW_ADDR};
        bins slv1_rw_addr = {`SLV1_RW_ADDR};
        bins slv2_rw_addr = {`SLV2_RW_ADDR};
        bins slv0_r_addr  = {`SLV0_R_ADDR };
        bins slv1_r_addr  = {`SLV1_R_ADDR };
        bins slv2_r_addr  = {`SLV2_R_ADDR };
      }
      cmd: coverpoint reg_vif.mon_ck.cmd {
        type_option.weight = 0;
        bins write = {`WRITE};
        bins read  = {`READ};
        bins idle  = {`IDLE};
      }
      cmdXaddr: cross cmd, addr {
        bins slv0_rw_addr = binsof(addr.slv0_rw_addr);
        bins slv1_rw_addr = binsof(addr.slv1_rw_addr);
        bins slv2_rw_addr = binsof(addr.slv2_rw_addr);
        bins slv0_r_addr  = binsof(addr.slv0_r_addr );
        bins slv1_r_addr  = binsof(addr.slv1_r_addr );
        bins slv2_r_addr  = binsof(addr.slv2_r_addr );
        bins write        = binsof(cmd.write);
        bins read         = binsof(cmd.read );
        bins idle         = binsof(cmd.idle );
        bins write_slv0_rw_addr  = binsof(cmd.write) && binsof(addr.slv0_rw_addr);
        bins write_slv1_rw_addr  = binsof(cmd.write) && binsof(addr.slv1_rw_addr);
        bins write_slv2_rw_addr  = binsof(cmd.write) && binsof(addr.slv2_rw_addr);
        bins read_slv0_rw_addr   = binsof(cmd.read) && binsof(addr.slv0_rw_addr);
        bins read_slv1_rw_addr   = binsof(cmd.read) && binsof(addr.slv1_rw_addr);
        bins read_slv2_rw_addr   = binsof(cmd.read) && binsof(addr.slv2_rw_addr);
        bins read_slv0_r_addr    = binsof(cmd.read) && binsof(addr.slv0_r_addr); 
        bins read_slv1_r_addr    = binsof(cmd.read) && binsof(addr.slv1_r_addr); 
        bins read_slv2_r_addr    = binsof(cmd.read) && binsof(addr.slv2_r_addr); 
      }
    endgroup

    covergroup cg_mcdf_reg_illegal_access;
      addr: coverpoint reg_vif.mon_ck.cmd_addr {
        type_option.weight = 0;
        bins legal_rw = {`SLV0_RW_ADDR, `SLV1_RW_ADDR, `SLV2_RW_ADDR};
        bins legal_r = {`SLV0_R_ADDR, `SLV1_R_ADDR, `SLV2_R_ADDR};
        bins illegal = {[8'h20:$], 8'hC, 8'h1C};
      }
      cmd: coverpoint reg_vif.mon_ck.cmd {
        type_option.weight = 0;
        bins write = {`WRITE};
        bins read  = {`READ};
      }
      wdata: coverpoint reg_vif.mon_ck.cmd_data_m2s {
        type_option.weight = 0;
        bins legal = {[0:'h3F]};
        bins illegal = {['h40:$]};
      }
      rdata: coverpoint reg_vif.mon_ck.cmd_data_s2m {
        type_option.weight = 0;
        bins legal = {[0:'hFF]};
        illegal_bins illegal = default;
      }
      cmdXaddrXdata: cross cmd, addr, wdata, rdata {
        bins addr_legal_rw = binsof(addr.legal_rw);
        bins addr_legal_r = binsof(addr.legal_r);
        bins addr_illegal = binsof(addr.illegal);
        bins cmd_write = binsof(cmd.write);
        bins cmd_read = binsof(cmd.read);
        bins wdata_legal = binsof(wdata.legal);
        bins wdata_illegal = binsof(wdata.illegal);
        bins rdata_legal = binsof(rdata.legal);
        bins write_illegal_addr = binsof(cmd.write) && binsof(addr.illegal);
        bins read_illegal_addr  = binsof(cmd.read) && binsof(addr.illegal);
        bins write_illegal_rw_data = binsof(cmd.write) && binsof(addr.legal_rw) && binsof(wdata.illegal);
        bins write_illegal_r_data = binsof(cmd.write) && binsof(addr.legal_r) && binsof(wdata.illegal);
      }
    endgroup

    covergroup cg_channel_disable;
      ch0_en: coverpoint mcdf_vif.mon_ck.chnl_en[0] {
        type_option.weight = 0;
        wildcard bins en  = {1'b1};
        wildcard bins dis = {1'b0};
      }
      ch1_en: coverpoint mcdf_vif.mon_ck.chnl_en[1] {
        type_option.weight = 0;
        wildcard bins en  = {1'b1};
        wildcard bins dis = {1'b0};
      }
      ch2_en: coverpoint mcdf_vif.mon_ck.chnl_en[2] {
        type_option.weight = 0;
        wildcard bins en  = {1'b1};
        wildcard bins dis = {1'b0};
      }
      ch0_vld: coverpoint chnl_vifs[0].mon_ck.ch_valid {
        type_option.weight = 0;
        bins hi = {1'b1};
        bins lo = {1'b0};
      }
      ch1_vld: coverpoint chnl_vifs[1].mon_ck.ch_valid {
        type_option.weight = 0;
        bins hi = {1'b1};
        bins lo = {1'b0};
      }
      ch2_vld: coverpoint chnl_vifs[2].mon_ck.ch_valid {
        type_option.weight = 0;
        bins hi = {1'b1};
        bins lo = {1'b0};
      }
      chenXchvld: cross ch0_en, ch1_en, ch2_en, ch0_vld, ch1_vld, ch2_vld {
        bins ch0_en  = binsof(ch0_en.en);
        bins ch0_dis = binsof(ch0_en.dis);
        bins ch1_en  = binsof(ch1_en.en);
        bins ch1_dis = binsof(ch1_en.dis);
        bins ch2_en  = binsof(ch2_en.en);
        bins ch2_dis = binsof(ch2_en.dis);
        bins ch0_hi  = binsof(ch0_vld.hi);
        bins ch0_lo  = binsof(ch0_vld.lo);
        bins ch1_hi  = binsof(ch1_vld.hi);
        bins ch1_lo  = binsof(ch1_vld.lo);
        bins ch2_hi  = binsof(ch2_vld.hi);
        bins ch2_lo  = binsof(ch2_vld.lo);
        bins ch0_en_vld = binsof(ch0_en.en) && binsof(ch0_vld.hi);
        bins ch0_dis_vld = binsof(ch0_en.dis) && binsof(ch0_vld.hi);
        bins ch1_en_vld = binsof(ch1_en.en) && binsof(ch1_vld.hi);
        bins ch1_dis_vld = binsof(ch1_en.dis) && binsof(ch1_vld.hi);
        bins ch2_en_vld = binsof(ch2_en.en) && binsof(ch2_vld.hi);
        bins ch2_dis_vld = binsof(ch2_en.dis) && binsof(ch2_vld.hi);
      }
    endgroup

    covergroup cg_arbiter_priority;
      ch0_prio: coverpoint arb_vif.mon_ck.slv_prios[0] {
        bins ch_prio0 = {0}; 
        bins ch_prio1 = {1}; 
        bins ch_prio2 = {2}; 
        bins ch_prio3 = {3}; 
      }
      ch1_prio: coverpoint arb_vif.mon_ck.slv_prios[1] {
        bins ch_prio0 = {0}; 
        bins ch_prio1 = {1}; 
        bins ch_prio2 = {2}; 
        bins ch_prio3 = {3}; 
      }
      ch2_prio: coverpoint arb_vif.mon_ck.slv_prios[2] {
        bins ch_prio0 = {0}; 
        bins ch_prio1 = {1}; 
        bins ch_prio2 = {2}; 
        bins ch_prio3 = {3}; 
      }
    endgroup

    covergroup cg_formatter_length;
      id: coverpoint fmt_vif.mon_ck.fmt_chid {
        bins ch0 = {0};
        bins ch1 = {1};
        bins ch2 = {2};
        illegal_bins illegal = default; 
      }
      length: coverpoint fmt_vif.mon_ck.fmt_length {
        bins len4  = {4};
        bins len8  = {8};
        bins len16 = {16};
        bins len32 = {32};
        illegal_bins illegal = default;
      }
    endgroup

    covergroup cg_formatter_grant();
      delay_req_to_grant: coverpoint this.delay_req_to_grant {
        bins delay1 = {1};
        bins delay2 = {2};
        bins delay3_or_more = {[3:10]};
        illegal_bins illegal = {0};
      }
    endgroup

    function new(string name="mcdf_coverage");
      this.name = name;
      this.cg_mcdf_reg_write_read = new();
      this.cg_mcdf_reg_illegal_access = new();
      this.cg_channel_disable = new();
      this.cg_arbiter_priority = new();
      this.cg_formatter_length = new();
      this.cg_formatter_grant = new();
    endfunction

    task run();
      fork 
        this.do_reg_sample();
        this.do_channel_sample();
        this.do_arbiter_sample();
        this.do_formater_sample();
      join
    endtask

    task do_reg_sample();
      forever begin
        @(posedge reg_vif.clk iff reg_vif.rstn);
        this.cg_mcdf_reg_write_read.sample();
        this.cg_mcdf_reg_illegal_access.sample();
      end
    endtask

    task do_channel_sample();
      forever begin
        @(posedge mcdf_vif.clk iff mcdf_vif.rstn);
        if(chnl_vifs[0].mon_ck.ch_valid===1
          || chnl_vifs[1].mon_ck.ch_valid===1
          || chnl_vifs[2].mon_ck.ch_valid===1)
          this.cg_channel_disable.sample();
      end
    endtask

    task do_arbiter_sample();
      forever begin
        @(posedge arb_vif.clk iff arb_vif.rstn);
        if(arb_vif.slv_reqs[0]!==0 || arb_vif.slv_reqs[1]!==0 || arb_vif.slv_reqs[2]!==0)
          this.cg_arbiter_priority.sample();
      end
    endtask

    task do_formater_sample();
      fork
        forever begin
          @(posedge fmt_vif.clk iff fmt_vif.rstn);
          if(fmt_vif.mon_ck.fmt_req === 1)
            this.cg_formatter_length.sample();
        end
        forever begin
          @(posedge fmt_vif.mon_ck.fmt_req);
          this.delay_req_to_grant = 0;
          forever begin
            if(fmt_vif.fmt_grant === 1) begin
              this.cg_formatter_grant.sample();
              break;
            end
            else begin
              @(posedge fmt_vif.clk);
              this.delay_req_to_grant++;
            end
          end
        end
      join
    endtask

    function void do_report();
      string s;
      s = "\n---------------------------------------------------------------\n";
      s = {s, "COVERAGE SUMMARY \n"}; 
      s = {s, $sformatf("total coverage: %.1f \n", $get_coverage())}; 
      s = {s, $sformatf("  cg_mcdf_reg_write_read coverage: %.1f \n", this.cg_mcdf_reg_write_read.get_coverage())}; 
      s = {s, $sformatf("  cg_mcdf_reg_illegal_access coverage: %.1f \n", this.cg_mcdf_reg_illegal_access.get_coverage())}; 
      s = {s, $sformatf("  cg_channel_disable_test coverage: %.1f \n", this.cg_channel_disable.get_coverage())}; 
      s = {s, $sformatf("  cg_arbiter_priority_test coverage: %.1f \n", this.cg_arbiter_priority.get_coverage())}; 
      s = {s, $sformatf("  cg_formatter_length_test coverage: %.1f \n", this.cg_formatter_length.get_coverage())}; 
      s = {s, $sformatf("  cg_formatter_grant_test coverage: %.1f \n", this.cg_formatter_grant.get_coverage())}; 
      s = {s, "---------------------------------------------------------------\n"};
      rpt_pkg::rpt_msg($sformatf("[%s]",this.name), s, rpt_pkg::INFO, rpt_pkg::TOP);
    endfunction

    virtual function void set_interface(virtual chnl_intf ch_vifs[3] 
                                        ,virtual reg_intf reg_vif
                                        ,virtual arb_intf arb_vif
                                        ,virtual fmt_intf fmt_vif
                                        ,virtual mcdf_intf mcdf_vif
                                      );
      this.chnl_vifs = ch_vifs;
      this.arb_vif = arb_vif;
      this.reg_vif = reg_vif;
      this.fmt_vif = fmt_vif;
      this.mcdf_vif = mcdf_vif;
      if(chnl_vifs[0] == null || chnl_vifs[1] == null || chnl_vifs[2] == null)
        $error("chnl interface handle is NULL, please check if target interface has been intantiated");
      if(arb_vif == null)
        $error("arb interface handle is NULL, please check if target interface has been intantiated");
      if(reg_vif == null)
        $error("reg interface handle is NULL, please check if target interface has been intantiated");
      if(fmt_vif == null)
        $error("fmt interface handle is NULL, please check if target interface has been intantiated");
      if(mcdf_vif == null)
        $error("mcdf interface handle is NULL, please check if target interface has been intantiated");
    endfunction
  endclass



	class mcdf_env extends uvm_env;
		chnl_agent chnl_agts[3];
    reg_agent reg_agt;
    fmt_agent fmt_agt;
    mcdf_checker chker;
    mcdf_coverage cvrg;
    protected string name;
		
		`uvm_component_utils(mcdf_env)
		function new(string name = "mcdf_env", uvm_component parent);
			super.new(name,parent);
		endfunction

		function void build_phase(uvm_phase phase);
			this.chker = mcdt_checker::type_id::get("chker",this);
			this.reg_agt = reg_agent::type_id::get("reg_agt",this);
			this.fmt_agent = fmt_agent::type_id::get("ftm_agt",this);
			this.cvrg = mcdf_coverage::type_id::get("cvrg",this);
      foreach(chnl_agts[i]) begin
        this.chnl_agts[i] = new($sformatf("chnl_agts[%0d]",i));
			end
		endfunction

		function void connect_phase(uvm_phsae phase);
      foreach(chnl_agts[i]) begin
        this.chnl_agts[i].monitor.mon_mb = this.chker.chnl_mbs[i];
      end
      this.reg_agt.monitor.mon_mb = this.chker.reg_mb;
      this.fmt_agt.monitor.mon_mb = this.chker.fmt_mb;
		endfunction

		task run_phase(uvm_phase phase);
		endtask

	endclass

	class mcdf_base_test 








