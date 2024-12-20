`include "lib/defines.vh"
module ID(
    input wire clk,
    input wire rst,
    // input wire flush,
    input wire [`StallBus-1:0] stall,
    
    output wire stallreq,

    input wire [`IF_TO_ID_WD-1:0] if_to_id_bus,

    input wire [31:0] inst_sram_rdata,

    input wire [`WB_TO_RF_WD-1:0] wb_to_rf_bus,

    output wire [`ID_TO_EX_WD-1:0] id_to_ex_bus,

    output wire [`BR_WD-1:0] br_bus, 
    
    input wire [`EX_TO_ID_FW-1:0] ex_to_id_bus,   //ex返回id

    input wire [`MEM_TO_ID_FW-1:0] mem_to_id_bus,  //mem返回id

    input wire [`WB_TO_ID_FW-1:0] wb_to_id_bus,     //wb返回id

    //debug
    output wire [31:0] debug_rdata1,
    output wire [31:0] debug_rdata2,
    output wire [31:0] debug_new_rdata1,
    output wire [31:0] debug_new_rdata2,

    output wire stallreq_from_id,
    input wire ex_is_load
);

    reg [`IF_TO_ID_WD-1:0] if_to_id_bus_r;
    wire [31:0] inst;
    wire [31:0] id_pc;
    wire ce;

    wire wb_rf_we;
    wire [4:0] wb_rf_waddr;
    wire [31:0] wb_rf_wdata;

    always @ (posedge clk) begin
        if (rst) begin
            if_to_id_bus_r <= `IF_TO_ID_WD'b0;        
        end
        // else if (flush) begin
        //     ic_to_id_bus <= `IC_TO_ID_WD'b0;
        // end
        else if (stall[1]==`Stop && stall[2]==`NoStop) begin
            if_to_id_bus_r <= `IF_TO_ID_WD'b0;
        end
        else if (stall[1]==`NoStop) begin
            if_to_id_bus_r <= if_to_id_bus;
        end
    end
    
    assign inst = inst_sram_rdata;
    assign {
        ce,
        id_pc
    } = if_to_id_bus_r;
    assign {
        wb_rf_we,
        wb_rf_waddr,
        wb_rf_wdata
    } = wb_to_rf_bus;

    wire [5:0] opcode;
    wire [4:0] rs,rt,rd,sa;
    wire [5:0] func;
    wire [15:0] imm;
    wire [25:0] instr_index;
    wire [19:0] code;
    wire [4:0] base;
    wire [15:0] offset;
    wire [2:0] sel;

    wire [63:0] op_d, func_d;
    wire [31:0] rs_d, rt_d, rd_d, sa_d;

    wire [2:0] sel_alu_src1;
    wire [3:0] sel_alu_src2;
    wire [11:0] alu_op;

    wire data_ram_en;
    wire [3:0] data_ram_readen;
    wire [3:0] data_ram_wen;
    
    wire rf_we;
    wire [4:0] rf_waddr;
    wire sel_rf_res;
    wire [2:0] sel_rf_dst;

    wire [31:0] rdata1, rdata2;

    regfile u_regfile(
    	.clk    (clk    ),
        .raddr1 (rs ),
        .rdata1 (rdata1 ),
        .raddr2 (rt ),
        .rdata2 (rdata2 ),
        .we     (wb_rf_we     ),
        .waddr  (wb_rf_waddr  ),
        .wdata  (wb_rf_wdata  )
    );

    assign opcode = inst[31:26];
    assign rs = inst[25:21];
    assign rt = inst[20:16];
    assign rd = inst[15:11];
    assign sa = inst[10:6];
    assign func = inst[5:0];
    assign imm = inst[15:0];
    assign instr_index = inst[25:0];
    assign code = inst[25:6];
    assign base = inst[25:21];
    assign offset = inst[15:0];
    assign sel = inst[2:0];

    wire inst_ori, inst_lui, inst_addiu, inst_beq, inst_subu, inst_jal, inst_bne, inst_j, inst_jr , inst_jalr, inst_addu, inst_sll, inst_or, inst_xor;

    wire op_add, op_sub, op_slt, op_sltu;
    wire op_and, op_nor, op_or, op_xor;
    wire op_sll, op_srl, op_sra, op_lui;

    decoder_6_64 u0_decoder_6_64(
    	.in  (opcode  ),
        .out (op_d )
    );

    decoder_6_64 u1_decoder_6_64(
    	.in  (func  ),
        .out (func_d )
    );
    
    decoder_5_32 u0_decoder_5_32(
    	.in  (rs  ),
        .out (rs_d )
    );

    decoder_5_32 u1_decoder_5_32(
    	.in  (rt  ),
        .out (rt_d )
    );

    
    assign inst_ori     = op_d[6'b00_1101];
    assign inst_lui     = op_d[6'b00_1111];
    assign inst_addiu   = op_d[6'b00_1001];
    assign inst_beq     = op_d[6'b00_0100];
    assign inst_subu    = op_d[6'b00_0000] && func_d[6'b10_0011];   //减法，rs-re->rd
    assign inst_jal     = op_d[6'b00_0011];                         //无条件跳转，jal rd,imm，GPR[31] ← PC + 8,PC ← PC + 4[31:28] || imm || '00'
    assign inst_bne     = op_d[6'b00_0101];                         //rs==rt顺序执行，否则转移target_offset ← Sign_extend(offset||'00')
    assign inst_j       = op_d[6'b00_0010];                         //无条件跳转, GPR[31] ← PC + 8,PC ← PC[31:28] || imm || '00'
    assign inst_jr      = op_d[6'b00_0000] && func_d[6'b00_1000];   //无条件跳转，跳转目标为寄存器 rs 中的值，temp ← GPR[rs]，PC ← temp
    assign inst_jalr    = op_d[6'b00_0000] && func_d[6'b00_1001];   //无条件跳转。temp← GPR[rs],GPR[rd] ← PC + 8,PC ← temp
    assign inst_addu    = op_d[6'b00_0000] && func_d[6'b10_0001];   //将寄存器 rs 的值与寄存器 rt 的值相加，结果写入 rd 寄存器中。GPR[rd] ← GPR[rs] + GPR[rt]
    assign inst_sll     = op_d[6'b00_0000] && func_d[6'b00_0000];   //由立即数 sa 指定移位量，对寄存器 rt 的值进行逻辑左移，结果写入寄存器 rd 中。s ← sa,GPR[rd] ← GPR[rt](31-s)..0||0s
    assign inst_or      = op_d[6'b00_0000] && func_d[6'b10_0101];   //寄存器 rs 中的值与寄存器 rt 中的值按位逻辑或，结果写入寄存器 rd 中。GPR[rd] ← GPR[rs] or GPR[rt]
    //assign inst_lw      = op_d[6'b10_0011];                          //base 寄存器的值加上符号扩展后的立即数 offset 得到访存的虚地址，如果地址不是 4 的整数倍则触发地址错例外，否则据此虚地址从存储器中读取连续 4 个字节的值，写入到 rt 寄存器中。
    assign inst_xor     = op_d[6'b00_1110];                         //寄存器 rs 中的值与 0 扩展至 32 位的立即数 imm 按位逻辑异或，结果写入寄存器 rt 中。              


    // rs to reg1
    assign sel_alu_src1[0] = inst_ori | inst_addiu | inst_subu | inst_jr | inst_addu | inst_or | inst_xor;

    // pc to reg1
    assign sel_alu_src1[1] = inst_jal | inst_jalr;

    // sa_zero_extend to reg1
    assign sel_alu_src1[2] = inst_sll;

    
    // rt to reg2
    assign sel_alu_src2[0] = inst_subu | inst_addu | inst_sll | inst_or | inst_xor;
    
    // imm_sign_extend to reg2
    assign sel_alu_src2[1] = inst_lui | inst_addiu ;

    // 32'b8 to reg2
    assign sel_alu_src2[2] = inst_jal | inst_jalr;

    // imm_zero_extend to reg2
    assign sel_alu_src2[3] = inst_ori;



    assign op_add = inst_addiu | inst_jal | inst_jalr | inst_addu;
    assign op_sub = inst_subu;
    assign op_slt = 1'b0;
    assign op_sltu = 1'b0;
    assign op_and = 1'b0;
    assign op_nor = 1'b0;
    assign op_or = inst_ori | inst_or;
    assign op_xor = inst_xor;
    assign op_sll = inst_sll;
    assign op_srl = 1'b0;
    assign op_sra = 1'b0;
    assign op_lui = inst_lui;

    assign alu_op = {op_add, op_sub, op_slt, op_sltu,
                     op_and, op_nor, op_or, op_xor,
                     op_sll, op_srl, op_sra, op_lui};



    // load and store enable
    assign data_ram_en = 1'b0;

    // write enable
    assign data_ram_wen = 1'b0;

    // // read enable
    // assign data_ram_readen =  inst_lw  ? 4'b1111
    //                         :4'b0000;

    // regfile store enable
    assign rf_we = inst_ori | inst_lui | inst_addiu | inst_subu | inst_jal | inst_jalr | inst_addu | inst_sll |inst_or | inst_xor;



    // store in [rd]
    assign sel_rf_dst[0] = inst_subu | inst_jalr | inst_addu | inst_sll | inst_or;
    // store in [rt] 
    assign sel_rf_dst[1] = inst_ori | inst_lui | inst_addiu | inst_xor;
    // store in [31]
    assign sel_rf_dst[2] = inst_jal;

    // sel for regfile address
    assign rf_waddr = {5{sel_rf_dst[0]}} & rd 
                    | {5{sel_rf_dst[1]}} & rt
                    | {5{sel_rf_dst[2]}} & 32'd31;

    // 0 from alu_res ; 1 from ld_res
    assign sel_rf_res = 1'b0; 


    //1219 update
    //ex forwarding,ex返回id段，ex line96
    wire forwarding_ex_rf_we;             
    wire [4:0] forwarding_ex_rf_waddr;    
    wire [31:0] forwarding_ex_result;     

    //mem forwarding，mem返回id段，mem line80
    wire forwarding_mem_rf_we;            
    wire [4:0] forwarding_mem_rf_waddr;   
    wire [31:0] forwarding_mem_rf_wdata;  

    //wb forwarding，mem返回id段，mem line80
    wire forwarding_wb_rf_we;            
    wire [4:0] forwarding_wb_rf_waddr;   
    wire [31:0] forwarding_wb_rf_wdata;  

    wire [31:0] new_rdata1, new_rdata2;

    assign {
        forwarding_ex_rf_we,      // 37
        forwarding_ex_rf_waddr,   // 36:32
        forwarding_ex_result      // 31:0
    } = ex_to_id_bus;

    assign {
        forwarding_mem_rf_we,     //37
        forwarding_mem_rf_waddr,  //36:32
        forwarding_mem_rf_wdata   //31:0
    } = mem_to_id_bus;

    assign {
        forwarding_wb_rf_we,     //37
        forwarding_wb_rf_waddr,  //36:32
        forwarding_wb_rf_wdata   //31:0
    } = wb_to_id_bus;


    assign new_rdata1 = (forwarding_ex_rf_we & (forwarding_ex_rf_waddr == rs)) ? forwarding_ex_result
                            :(forwarding_mem_rf_we & (forwarding_mem_rf_waddr == rs)) ? forwarding_mem_rf_wdata
                            :(wb_rf_we & (wb_rf_waddr == rs)) ? wb_rf_wdata
                            :rdata1;

    assign new_rdata2 = (forwarding_ex_rf_we & (forwarding_ex_rf_waddr == rt)) ? forwarding_ex_result
                            :(forwarding_mem_rf_we & (forwarding_mem_rf_waddr == rt)) ? forwarding_mem_rf_wdata
                            :(wb_rf_we & (wb_rf_waddr == rt)) ? wb_rf_wdata
                            :rdata2;


    assign stallreq_from_id = (ex_is_load  & forwarding_ex_rf_waddr == rs) | (ex_is_load & forwarding_ex_rf_waddr == rt) ;

    assign id_to_ex_bus = {
        data_ram_readen,// 159:162
        id_pc,          // 158:127
        inst,           // 126:95
        alu_op,         // 94:83
        sel_alu_src1,   // 82:80
        sel_alu_src2,   // 79:76
        data_ram_en,    // 75
        data_ram_wen,   // 74:71
        rf_we,          // 70
        rf_waddr,       // 69:65
        sel_rf_res,     // 64
        new_rdata1,         // 63:32
        new_rdata2          // 31:0 
    };


    wire br_e;
    wire [31:0] br_addr;
    wire rs_eq_rt;
    wire rs_ge_z;
    wire rs_gt_z;
    wire rs_le_z;
    wire rs_lt_z;
    wire [31:0] pc_plus_4;
    assign pc_plus_4 = id_pc + 32'h4;

    assign rs_eq_rt = (new_rdata1 == new_rdata2);

    assign br_e = (inst_beq & rs_eq_rt) | inst_jal | (inst_bne & !rs_eq_rt) | inst_j | inst_jr | inst_jalr;
    assign br_addr = inst_beq ? (pc_plus_4 + {{14{inst[15]}},inst[15:0],2'b0}) 
                    : inst_jal ? ({pc_plus_4[31:28],inst[25:0],2'b0}) 
                    : inst_j ? ({pc_plus_4[31:28],inst[25:0],2'b0}) 
                    :(inst_jr |inst_jalr)  ? (new_rdata1)
                    : inst_bne ? (pc_plus_4 + {{14{inst[15]}},{inst[15:0],2'b00}})
                    : 32'b0;
    assign br_bus = {
        br_e,
        br_addr
    };
    
    assign debug_rdata1 = rdata1;
    assign debug_rdata2 = rdata2;
    assign debug_new_rdata1 = new_rdata1;
    assign debug_new_rdata2 = new_rdata2;
endmodule