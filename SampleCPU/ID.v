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

    reg  flag;
    reg [31:0] buf_inst;

    always @ (posedge clk) begin
        if (rst) begin
            if_to_id_bus_r <= `IF_TO_ID_WD'b0;
            //flag <= 1'b0;    
            //buf_inst <= 32'b0;        
        end
        // else if (flush) begin
        //     ic_to_id_bus <= `IC_TO_ID_WD'b0;
        // end
        else if (stall[1]==`Stop && stall[2]==`NoStop) begin
            if_to_id_bus_r <= `IF_TO_ID_WD'b0;
            //flag <= 1'b0;
        end
        else if (stall[1]==`NoStop) begin
            if_to_id_bus_r <= if_to_id_bus;
            //flag <= 1'b0;
        end
        // else if (stall[1]==`Stop && stall[2]==`Stop && ~flag) begin
        //     flag <= 1'b1;
        //     buf_inst <= inst_sram_rdata;
        // end        
    end

    always @(posedge clk) begin
        if (stall[1]==`Stop) begin
            flag <= 1'b1;
        end
        else begin
            flag <= 1'b0;
        end
    end
    assign inst = (flag) ?inst: inst_sram_rdata;
    
    //assign inst = ce ? flag ? buf_inst : inst_sram_rdata : 32'b0;
    //assign inst = inst_sram_rdata;

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

    //逻辑运算
    wire inst_ori;
    wire inst_or;
    wire inst_xor;
    wire inst_lui;
    wire inst_and;
    wire inst_andi;
    wire inst_nor;
    wire inst_xori;

    //跳转
    wire inst_jal;
    wire inst_j;
    wire inst_jr;
    wire inst_bne;
    wire inst_beq;
    wire inst_jalr;
    wire inst_begz;
    wire inst_bgtz;
    wire inst_blez;
    wire inst_bltz;
    wire inst_bgezal;
    wire inst_bltzal;

    //算术运算
    wire inst_addiu;
    wire inst_addu;
    wire inst_subu;
    wire inst_addi;
    wire inst_add;
    wire inst_sub;
    wire inst_slt;
    wire inst_slti;
    wire inst_sltu;
    wire inst_sltiu;

    //移位指令
    wire inst_sll;
    wire inst_sllv;
    wire inst_sra;
    wire inst_srav;
    wire inst_srlv;
    wire inst_srl;

    //访存
    wire inst_lw;
    wire inst_sw;

    wire inst_lb;
    wire inst_lbu;
    wire inst_lh;
    wire inst_lhu;
    wire inst_sb;
    wire inst_sh;
 


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
    assign inst_lw      = op_d[6'b10_0011];                         //base 寄存器的值加上符号扩展后的立即数 offset 得到访存的虚地址，如果地址不是 4 的整数倍则触发地址错例外，否则据此虚地址从存储器中读取连续 4 个字节的值，写入到 rt 寄存器中。
    assign inst_xor     = op_d[6'b00_0000] && func_d[6'b10_0110];   //寄存器 rs 中的值与寄存器 rt 中的值按位逻辑异或，结果写入寄存器 rd 中。              
    //1.2 updata
    assign inst_sw      = op_d[6'b10_1011]; 
    assign inst_addi    = op_d[6'b00_1000];                         //将寄存器 rs 的值与有符号扩展至 32 位的立即数 imm 相加，结果写入 rt 寄存器中。如果产生溢出，则触发整型溢出例外（IntegerOverflow）。
    assign inst_add     = op_d[6'b00_0000] && func_d[6'b10_0000];   //将寄存器 rs 的值与寄存器 rt 的值相加，结果写入寄存器 rd 中。如果产生溢出，则触发整型溢出例外（IntegerOverflow）。
    assign inst_sub     = op_d[6'b00_0000] && func_d[6'b10_0010];   //将寄存器 rs 的值与寄存器 rt 的值相减，结果写入 rd 寄存器中。如果产生溢出，则触发整型溢出例外（IntegerOverflow）。
    assign inst_slt     = op_d[6'b00_0000] && func_d[6'b10_1010];   //将寄存器 rs 的值与寄存器 rt 中的值进行有符号数比较，如果寄存器 rs 中的值小，则寄存器 rd 置 1；否则寄存器 rd 置 0。
    assign inst_slti    = op_d[6'b00_1010];                         //将寄存器 rs 的值与有符号扩展至 32 位的立即数 imm 进行有符号数比较，如果寄存器 rs 中的值小，则寄存器 rt 置 1；否则寄存器 rt 置 0。
    assign inst_sltu    = op_d[6'b00_0000] && func_d[6'b10_1011];   //将寄存器 rs 的值与寄存器 rt 中的值进行无符号数比较，如果寄存器 rs 中的值小，则寄存器 rd 置 1；否则寄存器 rd 置 0
    assign inst_sltiu   = op_d[6'b00_1011];                         //将寄存器 rs 的值与有符号扩展 ．．．．．至 32 位的立即数 imm 进行无符号数比较，如果寄存器 rs 中的值小，则寄存器 rt 置 1；否则寄存器 rt 置 0。
    assign inst_lb      = op_d[6'b10_0000];                         //将 base 寄存器的值加上符号扩展后的立即数 offset 得到访存的虚地址，据此虚地址从存储器中读取 1 个字节的值并进行符号扩展，写入到 rt 寄存器中。
    assign inst_lbu     = op_d[6'b10_0100];                         //将 base 寄存器的值加上符号扩展后的立即数 offset 得到访存的虚地址，据此虚地址从存储器中读取 1 个字节的值并进行 0 扩展，写入到 rt 寄存器中。
    assign inst_lh      = op_d[6'b10_0001];                         //将 base 寄存器的值加上符号扩展后的立即数 offset 得到访存的虚地址，如果地址不是 2 的整数倍则触发地址错例外，否则据此虚地址从存储器中读取连续 2 个字节的值并进行符号扩展，写入到rt 寄存器中。
    assign inst_lhu     = op_d[6'b10_0101];                         //将 base 寄存器的值加上符号扩展后的立即数 offset 得到访存的虚地址，如果地址不是 2 的整数倍则触发地址错例外，否则据此虚地址从存储器中读取连续 2 个字节的值并进行 0 扩展，写入到 rt寄存器中。
    assign inst_sb      = op_d[6'b10_1000];                         //将 base 寄存器的值加上符号扩展后的立即数 offset 得到访存的虚地址，据此虚地址将 rt 寄存器的最低字节存入存储器中。
    assign inst_sh      = op_d[6'b10_1001];                         //将 base 寄存器的值加上符号扩展后的立即数 offset 得到访存的虚地址，如果地址不是 2 的整数倍则触发地址错例外，否则据此虚地址将 rt 寄存器的低半字存入存储器中。
    //1.3 updata
    assign inst_and     = op_d[6'b00_0000] && func_d[6'b10_0100];   //寄存器 rs 中的值与寄存器 rt 中的值按位逻辑与，结果写入寄存器 rd 中。
    assign inst_andi    = op_d[6'b00_1100];                         //寄存器 rs 中的值与 0 扩展至 32 位的立即数 imm 按位逻辑与，结果写入寄存器 rt 中。
    assign inst_nor     = op_d[6'b00_0000] && func_d[6'b10_0111];   //寄存器 rs 中的值与寄存器 rt 中的值按位逻辑或非，结果写入寄存器 rd 中。
    assign inst_xori    = op_d[6'b00_1110];                         //寄存器 rs 中的值与 0 扩展至 32 位的立即数 imm 按位逻辑异或，结果写入寄存器 rt 中。
    assign inst_sllv    = op_d[6'b00_0000] && func_d[6'b00_0100];   //由寄存器 rs 中的值指定移位量，对寄存器 rt 的值进行逻辑左移，结果写入寄存器 rd 中。
    assign inst_sra     = op_d[6'b00_0000] && func_d[6'b00_0011];   //由立即数 sa 指定移位量，对寄存器 rt 的值进行算术右移，结果写入寄存器 rd 中。
    assign inst_srav    = op_d[6'b00_0000] && func_d[6'b00_0111];   //由寄存器 rs 中的值指定移位量，对寄存器 rt 的值进行算术右移，结果写入寄存器 rd 中
    assign inst_srlv    = op_d[6'b00_0000] && func_d[6'b00_0110];   //由寄存器 rs 中的值指定移位量，对寄存器 rt 的值进行逻辑右移，结果写入寄存器 rd 中。
    assign inst_srl     = op_d[6'b00_0000] && func_d[6'b00_0010];   //由立即数 sa 指定移位量，对寄存器 rt 的值进行逻辑右移，结果写入寄存器 rd 中。
    assign inst_begz    = op_d[6'b00_0001] && rt_d[5'b00001];       //如果寄存器 rs 的值大于等于 0 则转移，否则顺序执行。转移目标由立即数 offset 左移 2 位并进行有符号扩展的值加上该分支指令对应的延迟槽指令的 PC 计算得到。
    assign inst_bgtz    = op_d[6'b00_0111] && rt_d[5'b00000];       //如果寄存器 rs 的值大于 0 则转移，否则顺序执行。转移目标由立即数 offset 左移 2 位并进行有符号扩展的值加上该分支指令对应的延迟槽指令的 PC 计算得到。
    assign inst_blez    = op_d[6'b00_0110] && rt_d[5'b00000];       //如果寄存器 rs 的值小于等于 0 则转移，否则顺序执行。转移目标由立即数 offset 左移 2 位并进行有符号扩展的值加上该分支指令对应的延迟槽指令的 PC 计算得到。
    assign inst_bltz    = op_d[6'b00_0001] && rt_d[5'b00000];       //如果寄存器 rs 的值小于 0 则转移，否则顺序执行。转移目标由立即数 offset 左移 2 位并进行有符号扩展的值加上该分支指令对应的延迟槽指令的 PC 计算得到。
    assign inst_bgezal  = op_d[6'b00_0001] && rt_d[5'b10001];       //GPR[31] ← PC + 8, 如果寄存器 rs 的值大于等于 0 则转移，否则顺序执行。转移目标由立即数 offset 左移 2 位并进行符号扩展的值加上该分支指令对应的延迟槽指令的 PC 计算得到。
    assign inst_bltzal  = op_d[6'b00_0001] && rt_d[5'b10000];       //GPR[31] ← PC + 8, 如果寄存器 rs 的值小于 0 则转移，否则顺序执行。转移目标由立即数 offset 左移 2 位并进行有符号扩展的值加上该分支指令对应的延迟槽指令的 PC 计算得到。




    // rs to reg1
    assign sel_alu_src1[0] = inst_ori | inst_addiu | inst_subu | inst_jr | inst_addu | inst_or | inst_xor | inst_lw | inst_sw | inst_addi 
                            | inst_add | inst_sub | inst_slt | inst_slti | inst_sltu | inst_sltiu | inst_lb | inst_lbu | inst_lh | inst_lhu
                            | inst_sb | inst_sh | inst_and | inst_andi | inst_nor | inst_xori | inst_sllv | inst_srav | inst_srlv | inst_begz
                            | inst_bgtz | inst_blez | inst_bltz ;//| inst_bgezal | inst_bltzal;

    // pc to reg1
    assign sel_alu_src1[1] = inst_jal | inst_jalr | inst_bltzal | inst_bgezal;

    // sa_zero_extend to reg1
    assign sel_alu_src1[2] = inst_sll | inst_sra | inst_srl;

    
    // rt to reg2
    assign sel_alu_src2[0] = inst_subu | inst_addu | inst_sll | inst_or | inst_xor | inst_add | inst_sub | inst_slt | inst_sltu | inst_and | inst_nor
                           | inst_sllv | inst_sra | inst_srav | inst_srlv | inst_srl;
    
    // imm_sign_extend to reg2
    assign sel_alu_src2[1] = inst_lui | inst_addiu | inst_lw | inst_sw | inst_addi | inst_slti | inst_sltiu | inst_lb | inst_lbu | inst_lh | inst_lhu 
                            | inst_sb | inst_sh;

    // 32'b8 to reg2
    assign sel_alu_src2[2] = inst_jal | inst_jalr | inst_bgezal | inst_bltzal;

    // imm_zero_extend to reg2
    assign sel_alu_src2[3] = inst_ori | inst_andi | inst_xori;



    assign op_add = inst_addiu | inst_jal | inst_jalr | inst_addu | inst_lw | inst_sw | inst_addi | inst_add | inst_lb | inst_lbu | inst_lh | inst_lhu 
                    | inst_sb | inst_sh | inst_bgezal | inst_bltzal;
    assign op_sub = inst_subu | inst_sub;
    assign op_slt = inst_slt | inst_slti;           //有符号
    assign op_sltu = inst_sltu | inst_sltiu;        //无符号比较
    assign op_and = inst_and | inst_andi;
    assign op_nor = inst_nor;
    assign op_or = inst_ori | inst_or;
    assign op_xor = inst_xor | inst_xori;
    assign op_sll = inst_sll | inst_sllv;
    assign op_srl = inst_srl | inst_srlv;
    assign op_sra = inst_sra | inst_srav;
    assign op_lui = inst_lui;

    assign alu_op = {op_add, op_sub, op_slt, op_sltu,
                     op_and, op_nor, op_or, op_xor,
                     op_sll, op_srl, op_sra, op_lui};



    // load and store enable
    assign data_ram_en = inst_lw | inst_sw | inst_lb | inst_lbu | inst_lh | inst_lhu | inst_sb | inst_sh;

    // write enable
    assign data_ram_wen = inst_sw ? 4'b1111 : 4'b0000;

    // read enable
    assign data_ram_readen =  inst_lw  ? 4'b1111
                            :inst_lb   ? 4'b0001
                            :inst_lbu  ? 4'b0010
                            :inst_lh   ? 4'b0011
                            :inst_lhu  ? 4'b0100 
                            :inst_sb   ? 4'b0101
                            :inst_sh   ? 4'b0110
                            :4'b0000;

    // regfile store enable
    assign rf_we = inst_ori | inst_lui | inst_addiu | inst_subu | inst_jal | inst_jalr | inst_addu | inst_sll |inst_or | inst_xor 
                  | inst_lw | inst_addi | inst_add | inst_sub | inst_slt | inst_slti | inst_sltu | inst_sltiu | inst_lb | inst_lbu
                  | inst_lh | inst_lhu | inst_and | inst_andi | inst_nor | inst_xori | inst_sllv | inst_sra | inst_srav | inst_srlv
                  | inst_srl | inst_bgezal | inst_bltzal;



    // store in [rd]
    assign sel_rf_dst[0] = inst_subu | inst_jalr | inst_addu | inst_sll | inst_or | inst_xor | inst_add | inst_sub | inst_slt | inst_sltu 
                        |  inst_and| inst_nor | inst_sllv | inst_sra | inst_srav | inst_srlv | inst_srl;
    // store in [rt] 
    assign sel_rf_dst[1] = inst_ori | inst_lui | inst_addiu | inst_lw | inst_addi | inst_slti | inst_sltiu | inst_lb | inst_lbu | inst_lh 
                        |  inst_lhu | inst_andi | inst_xori;
    // store in [31]
    assign sel_rf_dst[2] = inst_jal | inst_bgezal | inst_bltzal;

    // sel for regfile address
    assign rf_waddr = {5{sel_rf_dst[0]}} & rd 
                    | {5{sel_rf_dst[1]}} & rt
                    | {5{sel_rf_dst[2]}} & 32'd31;

    // 0 from alu_res ; 1 from ld_res
    assign sel_rf_res = 1'b0; 


    //1219 update
    //ex forwarding,ex返回id段，ex line96
    wire forwarding_ex_id_we;             
    wire [4:0] forwarding_ex_id_waddr;    
    wire [31:0] forwarding_ex_id_wdata;     

    //mem forwarding，mem返回id段，mem line80
    wire forwarding_mem_id_we;            
    wire [4:0] forwarding_mem_id_waddr;   
    wire [31:0] forwarding_mem_id_wdata;  

    //wb forwarding，wb返回id段，wb line55
    wire forwarding_wb_id_we;            
    wire [4:0] forwarding_wb_id_waddr;   
    wire [31:0] forwarding_wb_id_wdata;  

    wire [31:0] new_rdata1, new_rdata2;

    assign {
        forwarding_ex_id_we,      // 37
        forwarding_ex_id_waddr,   // 36:32
        forwarding_ex_id_wdata     // 31:0
    } = ex_to_id_bus;

    assign {
        forwarding_mem_id_we,     //37
        forwarding_mem_id_waddr,  //36:32
        forwarding_mem_id_wdata   //31:0
    } = mem_to_id_bus;

    assign {
        forwarding_wb_id_we,     //37
        forwarding_wb_id_waddr,  //36:32
        forwarding_wb_id_wdata   //31:0
    } = wb_to_id_bus;

    //判断是否通过forwarding接收上一个指令的计算结果
    assign new_rdata1 = (forwarding_ex_id_we & (forwarding_ex_id_waddr == rs)) ? forwarding_ex_id_wdata
                            :(forwarding_mem_id_we & (forwarding_mem_id_waddr == rs)) ? forwarding_mem_id_wdata
                            :(forwarding_wb_id_we & (forwarding_wb_id_waddr == rs)) ? forwarding_wb_id_wdata
                            :rdata1;

    assign new_rdata2 = (forwarding_ex_id_we & (forwarding_ex_id_waddr == rt)) ? forwarding_ex_id_wdata
                            :(forwarding_mem_id_we & (forwarding_mem_id_waddr == rt)) ? forwarding_mem_id_wdata
                            :(forwarding_wb_id_we & (forwarding_wb_id_waddr == rt)) ? forwarding_wb_id_wdata
                            :rdata2;

    //若上一个流水线操作是lw，而当前流水线操作要对同一个寄存器进行操作，访存冲突。
    assign stallreq_from_id = (ex_is_load  & forwarding_ex_id_waddr == rs) | (ex_is_load & forwarding_ex_id_waddr == rt) ;

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
    assign rs_ge_z  = (new_rdata1[31] == 1'b0); //大于等于0, begz, begzal
    assign rs_gt_z  = (new_rdata1[31] == 1'b0 & new_rdata1 != 32'b0  );  //大于0, bgtz
    assign rs_le_z  = (new_rdata1[31] == 1'b1 | new_rdata1 == 32'b0  );  //小于等于0, blez
    assign rs_lt_z  = (new_rdata1[31] == 1'b1);  //小于0, bltz, bltzal
    assign rs_eq_rt = (new_rdata1 == new_rdata2);

    assign br_e = (inst_beq & rs_eq_rt) | inst_jal | (inst_bne & !rs_eq_rt) | inst_j | inst_jr | inst_jalr 
                | (inst_begz & rs_ge_z) | (inst_blez & rs_le_z) | (inst_bgtz & rs_gt_z) | (inst_bltz & rs_lt_z)
                | (inst_bltzal & rs_lt_z) | (inst_bgezal & rs_ge_z);
    assign br_addr = inst_beq ? (pc_plus_4 + {{14{inst[15]}},inst[15:0],2'b0}) 
                    : inst_jal ? ({pc_plus_4[31:28],inst[25:0],2'b0}) 
                    : inst_j ? ({pc_plus_4[31:28],inst[25:0],2'b0}) 
                    :(inst_jr | inst_jalr)  ? (new_rdata1)
                    : inst_bne ? (pc_plus_4 + {{14{inst[15]}},{inst[15:0],2'b00}})
                    :(inst_begz | inst_bgtz | inst_blez | inst_bltz | inst_bltzal | inst_bgezal) ? (pc_plus_4 + {{14{inst[15]}},{inst[15:0],2'b00}})
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