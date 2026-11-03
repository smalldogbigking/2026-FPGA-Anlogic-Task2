

module video_in (
    input wire         I_rst_n,

    input wire         I_camera_clk,
    input wire         I_camera_frame_start,
    input wire         I_camera_valid,
    input wire[127:0]  I_camera_data,
    input wire         I_mipi_rx_error,

    input wire         I_ddr_clk,

    input wire         I_display_pause,
    input wire [1:0] I_fps_preset,I_read_bank,
    output reg [31:0] O_source_ms,O_source_seq,
    output reg O_source_valid,
    output wire [31:0] O_now_gray,
    input wire         I_video_out_rd_busy,
    output wire        O_video_in_wr_busy,
    output reg[1:0]    O_video_out_rp,     ///读指针

    output reg         O_ddr_user_wr_en,
    output reg[24:0]   O_ddr_user_addr,
    output wire[127:0] O_ddr_user_wr_data,
    input wire         I_ddr_user_ready
);

    wire        S_fifo_rst;
    reg pause_meta,pause_sync;
    always @(posedge I_ddr_clk or negedge I_rst_n)begin
      if(!I_rst_n)begin pause_meta<=0;pause_sync<=0;end
      else begin pause_meta<=I_display_pause;pause_sync<=pause_meta;end
    end
    reg         S_camera_frame_start_extend; ///脉冲展宽，同步到ddr_clk时钟域
    reg[3:0]    S_extend_cnt;
    reg         S_camera_frame_start_extend_1d;
    reg         S_camera_frame_start_extend_2d;
    reg         S_camera_frame_start_extend_3d;
    wire        S_frame_start;
    reg[1:0]    S_video_in_wp;       ///写指针
    wire[8:0]   S_fifo_rd_num;      
    wire        S_fifo_rd_en;   
    wire        S_fifo_rd_valid;
    wire[127:0] S_fifo_rd_data; 
    reg         S_ddr_wr_valid;
    reg[9:0]    S_ddr_wr_cnt;

    localparam IMAGE_BASE_ADDR_0 = 25'd0;
    localparam IMAGE_BASE_ADDR_1 = 25'd7000000;
    localparam IMAGE_BASE_ADDR_2 = 25'd14000000;
    localparam IMAGE_BASE_ADDR_3 = 25'd21000000;


    assign S_fifo_rst = S_camera_frame_start_extend_3d;

    // 以完整DDR写突发的占用标志仲裁，避免连续写入长期阻塞视频读取。
    assign O_video_in_wr_busy = S_ddr_wr_valid;

    w128_d512_fifo U_w128_d512_fifo(
        .rst        ( S_fifo_rst         ),   

        .clkw       ( I_camera_clk       ),     
        .we         ( I_camera_valid     ),
        .di         ( I_camera_data      ),
        .afull      (),
        .full_flag  (),
        .wrusedw    (),
 
        .clkr       ( I_ddr_clk          ),
        .re         ( S_fifo_rd_en       ), 
        .dout       ( O_ddr_user_wr_data ),  
        .rdusedw    ( S_fifo_rd_num      ),
        .valid      (), 
        .empty_flag (),
        .aempty     ()
    );


    always @(posedge I_camera_clk or negedge I_rst_n) begin
        if(!I_rst_n)
            S_camera_frame_start_extend <= 1'b0;
        else
            if(I_camera_frame_start)
                S_camera_frame_start_extend <= 1'b1;
            else if(S_extend_cnt == 'd7)
                S_camera_frame_start_extend <= 1'b0;
            else
                S_camera_frame_start_extend <= S_camera_frame_start_extend;
    end

	
    always @ (posedge I_camera_clk) begin
    	if(S_camera_frame_start_extend)
        	S_extend_cnt <= S_extend_cnt + 'd1;
      	else
          	S_extend_cnt <= 'd0;
    end


    always @(posedge I_ddr_clk) begin
        S_camera_frame_start_extend_1d <= S_camera_frame_start_extend;
        S_camera_frame_start_extend_2d <= S_camera_frame_start_extend_1d;
        S_camera_frame_start_extend_3d <= S_camera_frame_start_extend_2d;
    end

    assign S_frame_start = ~S_camera_frame_start_extend_3d & S_camera_frame_start_extend_2d;

    // Four-bank ownership: the writer never overwrites the displayed bank
    // or the newest published bank. Publish only after all 172800 words arrived.
    reg [17:0] frame_words;
    reg [31:0] now_ms,capture_ms;
    reg [16:0] ms_ticks;
    reg [1:0] fps0,fps1,phase,active_preset;
    reg started;
    reg [1:0] next_bank;
    integer bank_i;
    always @*begin
      next_bank=S_video_in_wp;
      for(bank_i=3;bank_i>=0;bank_i=bank_i-1)
        if(bank_i!=I_read_bank && bank_i!=O_video_out_rp && bank_i!=S_video_in_wp) next_bank=bank_i;
    end
    assign O_now_gray=(now_ms>>1)^now_ms;
    always @(posedge I_ddr_clk or negedge I_rst_n)begin
      if(!I_rst_n)begin
        S_video_in_wp<=1;O_video_out_rp<=0;O_source_ms<=0;O_source_seq<=0;O_source_valid<=0;
        frame_words<=0;now_ms<=0;capture_ms<=0;ms_ticks<=0;fps0<=0;fps1<=0;phase<=0;active_preset<=0;started<=0;
      end else begin
        fps0<=I_fps_preset;fps1<=fps0;
        if(ms_ticks==66666)begin ms_ticks<=0;now_ms<=now_ms+1'b1;end else ms_ticks<=ms_ticks+1'b1;
        if(O_ddr_user_wr_en && frame_words<172801)frame_words<=frame_words+1'b1;
        if(S_frame_start)begin
          if(started && frame_words==172800 && !I_mipi_rx_error && !pause_sync)begin
            if(phase==0 || fps1!=active_preset)begin
              O_video_out_rp<=S_video_in_wp;O_source_ms<=capture_ms;O_source_seq<=O_source_seq+1'b1;O_source_valid<=1;
            end
            if(fps1!=active_preset)phase<=(fps1==0)?0:1;
            else phase<=(phase>=((fps1==2)?3:fps1))?0:phase+1'b1;
          end
          active_preset<=fps1;capture_ms<=now_ms;frame_words<=0;started<=1;S_video_in_wp<=next_bank;
        end
      end
    end

    /*
        fifo的深度是512，实际的深度是510，因此需要注意每次读出的长度避免为256，否则连续两次读写会引起fifo读空，丢失数据
    */
    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n)
            S_ddr_wr_valid <= 1'b0;
        else
            if(S_ddr_wr_valid && I_ddr_user_ready && S_ddr_wr_cnt == 'd239)
                S_ddr_wr_valid <= 1'b0;
            else if(S_fifo_rd_num >= 'd240 && (!I_video_out_rd_busy) && (!S_fifo_rst))
                S_ddr_wr_valid <= 1'b1;
            else
                S_ddr_wr_valid <= S_ddr_wr_valid;
    end

    always @(posedge I_ddr_clk) begin
        if(S_ddr_wr_valid)
            begin
                if(I_ddr_user_ready)
                    S_ddr_wr_cnt <= S_ddr_wr_cnt + 'd1;
                else
                    S_ddr_wr_cnt <= S_ddr_wr_cnt;
            end
        else
            S_ddr_wr_cnt <= 'd0;
    end

    assign S_fifo_rd_en = S_ddr_wr_valid & I_ddr_user_ready;

    always @(posedge I_ddr_clk) begin
        O_ddr_user_wr_en <= S_fifo_rd_en;
    end

	/*
		如果前一帧图像有误少行了，那么地址回退为之前的，覆盖有问题的那帧图像
	*/
    always @(posedge I_ddr_clk or negedge I_rst_n)begin
      if(!I_rst_n)O_ddr_user_addr<=0;
      else if(S_frame_start)begin
        case(next_bank)
          0:O_ddr_user_addr<=IMAGE_BASE_ADDR_0;1:O_ddr_user_addr<=IMAGE_BASE_ADDR_1;
          2:O_ddr_user_addr<=IMAGE_BASE_ADDR_2;3:O_ddr_user_addr<=IMAGE_BASE_ADDR_3;
        endcase
      end else if(O_ddr_user_wr_en)O_ddr_user_addr<=O_ddr_user_addr+8;
    end
endmodule
