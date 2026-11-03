`timescale 1ns / 1ns //仿真时间刻度/精度

module hdmi_tx #(parameter CAPTURE_COMPAT = 1) (
    input wire       I_serial_rst, // Serial-clock-domain reset, active high.
    input wire       I_pixel_clk, //像素时钟
    input wire       I_serial_clk,//串行发送时钟
    input wire       I_rst, //异步复位信号，高电平有效

    input wire       I_key_in,
    
    input wire       I_edid_read_trig,//EDID读触发信号
    output wire      O_edid_read_valid,//EDID读有效信号
    output wire[7:0] O_edid_read_data,//EDID读数据
///**********************  video rgb input  *****************************  
    input wire       I_video_rgb_enable,  //是否使能RGB输入接口，设置1使能，否则采用stream video时序接口
    input wire       I_video_in_de, //RGB 输入de有效
    input wire       I_video_in_vs, //RGB 输入VS 帧同步 
///**********************  video stream input  ***************************
    input wire       I_video_in_user,  //视频输入帧起始信号
    input wire       I_video_in_valid, //视频输入有效信号
    input wire       I_video_in_last,  //视频输入行结束信号
    output wire      O_video_in_ready, //视频输入ready信号
    input wire[23:0] I_video_in_data,  //视频输入数据
///*********************  audio stream input  ***************************
    input wire       I_audio_valid,     //音频输入有效信号
    input wire[23:0] I_audio_left_data, //音频左声道数据
    input wire[23:0] I_audio_right_data,//音频左声道数据
    
    input wire       I_i2s_BCLK,
    input wire       I_i2s_LRCK,
    input wire       I_i2s_DOUT,

    output wire      O_ddc_scl,
    inout wire       IO_ddc_sda,

    output           O_hdmi_clk_p, //HDMI输出时钟P端
    output    [2:0]  O_hdmi_tx_p,  //HDMI输出数据P端
    
    output wire      O_tmds_ch0_p, //HDMI数据通道0
    output wire      O_tmds_ch1_p, //HDMI数据通道1
    output wire      O_tmds_ch2_p, //HDMI数据通道2
    output wire      O_tmds_clk_p  //HDMI时钟通道
);

generate if (CAPTURE_COMPAT) begin: gen_capture
    wire [9:0] blue_word, green_word, red_word;
    capture_rgb_tmds rgb_link(
        .clk(I_pixel_clk), .rst(I_rst), .de(I_video_in_de),
        .sof(I_video_in_user), .rgb(I_video_in_data),
        .blue(blue_word), .green(green_word), .red(red_word)
    );
    // Video-only DVI-compatible TMDS over the existing HDMI connector.
    // The application has no HDMI audio source. All blanking is control data.
    hdmi_phy_wrapper #(.DEVICE("PH1P")) phy(
        .I_pixel_clk(I_pixel_clk), .I_serial_clk(I_serial_clk),
        .I_rst(I_rst), .I_serial_rst(I_serial_rst),
        .I_tmds_channel_0(blue_word), .I_tmds_channel_1(green_word),
        .I_tmds_channel_2(red_word), .I_tmds_channel_clk(10'b1111100000),
        .O_tmds_ch0_p(O_tmds_ch0_p), .O_tmds_ch1_p(O_tmds_ch1_p),
        .O_tmds_ch2_p(O_tmds_ch2_p), .O_tmds_clk_p(O_tmds_clk_p)
    );
    assign O_video_in_ready = 1'b1;
    assign O_edid_read_valid = 1'b0;
    assign O_edid_read_data = 8'd0;
    assign O_ddc_scl = 1'b1;
    assign IO_ddc_sda = 1'bz;
    assign O_hdmi_clk_p = O_tmds_clk_p;
    assign O_hdmi_tx_p = {O_tmds_ch2_p,O_tmds_ch1_p,O_tmds_ch0_p};
end else begin: gen_vendor

    wire       S_pll_lock = ~I_rst;
    wire       S_rst;

    wire[9:0]  S_ch0_tmds_data; //synthesis keep; 
    wire[9:0]  S_ch1_tmds_data; //synthesis keep; 
    wire[9:0]  S_ch2_tmds_data; //synthesis keep; 
    wire[9:0]  S_clk_tmds_data; //synthesis keep; 

    wire       S_acr_valid; //synthesis keep; 
    wire[19:0] S_acr_cts;   //synthesis keep; 
    wire[19:0] S_acr_n;     //synthesis keep; 
    wire       S_i2s_audio_valid;
    wire[23:0] S_i2s_audio_left_data;
    wire[23:0] S_i2s_audio_right_data;
    wire       S_key_edid_read_trig;

//**********************  video stream input  ***************************
//如果是输入RGB时序，那么转为stream时序，否则仅对信号打一个节拍
    reg       I_video_in_de_r1;
    reg       I_video_in_vs_r1;
    reg       I_video_in_user_r1,I_video_in_user_r2;
    reg       I_video_in_valid_r1,I_video_in_valid_r2;
    reg       I_video_in_last_r2;
    reg[23:0] I_video_in_data_r1,I_video_in_data_r2;
    reg       O_video_in_ready_r;
    reg       vs_start;
  
    always @(posedge I_pixel_clk)begin
    	I_video_in_de_r1 <= I_video_in_de;
    	I_video_in_vs_r1 <= I_video_in_vs;
    end
      
    always @(posedge I_pixel_clk or posedge I_rst )begin
    	if(I_rst)begin
        	I_video_in_last_r2  <= 1'b0;
            I_video_in_valid_r1 <= 1'b0;
            I_video_in_data_r1  <= 24'd0;
            I_video_in_user_r1  <= 1'b0;
            I_video_in_valid_r2 <= 1'b0;
            I_video_in_data_r2  <= 24'd0;
            I_video_in_user_r2  <= 1'b0;
        end    
    	else if(I_video_rgb_enable == 1'b1)begin
        	I_video_in_last_r2  <= ~I_video_in_de & I_video_in_de_r1; //产生stream video last 延迟于数据输入2拍
            I_video_in_valid_r1 <= I_video_in_de;//I_video_in_valid延迟1拍
            I_video_in_data_r1  <= I_video_in_data;//I_video_in_data延迟1拍
            I_video_in_user_r1  <= ~I_video_in_user_r1 & vs_start & I_video_in_de;//I_video_in_user延迟1拍
            
            I_video_in_valid_r2 <= I_video_in_valid_r1;//I_video_in_valid对输入信号延迟2拍，以和I_video_in_last_r2信号配套同步
            I_video_in_data_r2  <= I_video_in_data_r1; //I_video_in_data 对输入信号延迟2拍，以和I_video_in_last_r2信号配套同步
            I_video_in_user_r2  <= I_video_in_user_r1; //I_video_in_user 对输入信号延迟2拍，以和I_video_in_last_r2信号配套同步 
        end     
        else begin
        	I_video_in_last_r2  <= I_video_in_last; //I_video_in_last对输入信号直接寄存1次
            I_video_in_valid_r2 <= I_video_in_valid;//I_video_in_valid对输入信号直接寄存1次
            I_video_in_data_r2  <= I_video_in_data;//I_video_in_data对输入信号直接寄存1次
            I_video_in_user_r2  <= I_video_in_user;//I_video_in_user对输入信号直接寄存1次      
        end 
    end
    
    always @(posedge I_pixel_clk or posedge I_rst )begin
    	if(I_rst)
        	vs_start <= 1'b0;
    	else if(I_video_in_user_r1)//清除VS帧同步
        	vs_start <= 1'b0;
        else if(I_video_in_vs && I_video_in_vs_r1==1'b0)//当I_video_in_vs发生上升沿跳变代表一帧开始
            vs_start <= 1'b1;
    end    

    I2S_receiver u_I2S_receiver(
        .I_clk              ( I_pixel_clk        ),
        .I_rst              ( I_rst              ),
  
        .I_i2s_BCLK         ( I_i2s_BCLK         ),
        .I_i2s_LRCK         ( I_i2s_LRCK         ),
        .I_i2s_DOUT         ( I_i2s_DOUT         ),
  
        .O_audio_valid      ( S_i2s_audio_valid      ),
        .O_audio_left_data  ( S_i2s_audio_left_data  ),
        .O_audio_right_data ( S_i2s_audio_right_data )
    );


    audio_arc_calculate#(
        .ACR_N         ( 6144 )
    )u_audio_arc_calculate(
        .I_clk         ( I_pixel_clk    ),
        .I_rst         ( I_rst          ),

        .I_audio_valid ( I_audio_valid  ),

        .O_acr_valid   ( S_acr_valid    ),
        .O_acr_cts     ( S_acr_cts      ),
        .O_acr_n       ( S_acr_n        )
    );


    key_remove_shakes u_key_remove_shakes(
        .I_clk          ( I_pixel_clk ),
        .I_rst_n        ( S_pll_lock  ),
        .I_key_in       ( I_key_in    ),
        .O_key_trig_out ( S_key_edid_read_trig )
    );



//   video_source_test#(
//        .HTOTAL        ( 2200 ),
//        .HACTIVE       ( 1920 ),
//        .HFP           ( 88   ),
//        .HSA           ( 44   ),
//        .HBP           ( 148  ),
//        .VTOTAL        ( 1125 ),
//        .VACTIVE       ( 1080 ),
//        .VFP           ( 4    ),
//        .VSA           ( 5    ),
//        .VBP           ( 36   )
//    )U_video_source_test(
//        .I_clk         ( I_pixel_clk    ),
//        .I_rst         ( I_rst          ),

//        .I_tpg_trig_en ( 1'b1           ),

//        .O_video_user  ( I_video_in_user  ),
//        .O_video_valid ( I_video_in_valid ),
//        .O_video_last  ( I_video_in_last  ),
//        .O_video_data  ( I_video_in_data  ),
//        .I_video_ready ( O_video_in_ready )
//    );


    hdmi_1_4b_transmitter_core_wrapper#(
        .DEVICE                 ( "PH1P"   ),

		.HTOTAL                 ( 1650     ),
        .HSA                    ( 40       ),
        .HFP                    ( 110      ),
        .HBP                    ( 220      ),
        .HACTIVE                ( 1280     ),
        .VTOTAL                 ( 750      ),
        .VSA                    ( 5        ),
        .VFP                    ( 5        ),
        .VBP                    ( 20       ),
        .VACTIVE                ( 720      ),

		.VIDEO_VIC              ( 4        ),

        .VIDEO_TPG              ( "Disable" ),
        .VIDEO_FORMAT           ( "RGB"    ),

        .AUDIO_SAMPLE_RATE      ( "48K"    ),
        
        .IIC_SCL_DIV            ( 125      )
    )u_hdmi_1_4b_transmitter_core_wrapper(
        .I_pixel_clk        ( I_pixel_clk        ),
        .I_rst              ( I_rst              ),

        .I_edid_read_trig   ( I_edid_read_trig   ),
        .O_edid_read_valid  ( O_edid_read_valid  ),
        .O_edid_read_data   ( O_edid_read_data   ),

        .I_axis_s_user      ( I_video_in_user_r2      ),
        .I_axis_s_valid     ( I_video_in_valid_r2     ),
        .I_axis_s_last      ( I_video_in_last_r2      ),
        .I_axis_s_data      ( I_video_in_data_r2      ),
        .O_axis_s_ready     ( O_video_in_ready     ),

        .I_audio_valid      ( I_audio_valid      ),
        .I_audio_left_data  ( I_audio_left_data  ),
        .I_audio_right_data ( I_audio_right_data ),

        .I_acr_valid        ( S_acr_valid        ),
        .I_acr_cts          ( S_acr_cts          ),
        .I_acr_n            ( S_acr_n            ),

        .O_video_locked     ( ),

        .O_ddc_scl          ( O_ddc_scl          ),
        .IO_ddc_sda         ( IO_ddc_sda         ),

        .O_ch0_tmds_data    ( S_ch0_tmds_data    ),
        .O_ch1_tmds_data    ( S_ch1_tmds_data    ),
        .O_ch2_tmds_data    ( S_ch2_tmds_data    ),
        .O_clk_tmds_data    ( S_clk_tmds_data    )
    );


    hdmi_phy_wrapper  #(
        .DEVICE ( "PH1P" )  //"EF2","EF3","EF4","SF1","EG","PH1A","PH1P","DR1"
    )u_hdmi2phy_wrapper(
        .I_pixel_clk        ( I_pixel_clk     ),
        .I_serial_clk       ( I_serial_clk    ),
        .I_rst              ( I_rst           ),
        .I_serial_rst       ( I_serial_rst    ),

        .I_tmds_channel_0   ( S_ch0_tmds_data ),
        .I_tmds_channel_1   ( S_ch1_tmds_data ),
        .I_tmds_channel_2   ( S_ch2_tmds_data ),
        .I_tmds_channel_clk ( S_clk_tmds_data ),

        .O_tmds_ch0_p       ( O_tmds_ch0_p    ),
        .O_tmds_ch1_p       ( O_tmds_ch1_p    ),
        .O_tmds_ch2_p       ( O_tmds_ch2_p    ),
        .O_tmds_clk_p       ( O_tmds_clk_p    )
    );


end endgenerate
endmodule

// Standard positive-polarity 720p60 sync, aligned to the final OSD pixel SOF.
// The image stream is never stalled or buffered. Blanking remains continuous.
module capture_rgb_tmds(
    input wire clk, rst, de, sof,
    input wire [23:0] rgb,
    output wire [9:0] blue, green, red
);
    reg [10:0] h_count;
    reg [9:0] v_count;
    reg de_d;
    wire frame_start = de && sof;
    wire line_start = de && !de_d;
    wire [10:0] h = (frame_start || line_start) ? 11'd0 : h_count;
    wire [9:0] v = frame_start ? 10'd0 : v_count;
    wire hs = h >= 1390 && h < 1430;
    wire vs = v >= 725 && v < 730;
    always @(posedge clk or posedge rst) begin
        if (rst) begin h_count<=0; v_count<=0; de_d<=0; end
        else begin
            de_d <= de;
            if (frame_start) begin h_count<=1; v_count<=0; end
            else if (line_start) h_count<=1;
            else if (h_count==1649) begin
                h_count<=0;
                v_count <= v_count==749 ? 10'd0 : v_count+1'b1;
            end else h_count<=h_count+1'b1;
        end
    end
    capture_tmds_encoder b(clk,rst,de,{vs,hs},rgb[7:0],blue);
    capture_tmds_encoder g(clk,rst,de,2'b00,rgb[15:8],green);
    capture_tmds_encoder r(clk,rst,de,2'b00,rgb[23:16],red);
endmodule

// DVI 1.0 section 3.2 / figure 3-5: transition minimization followed by
// signed running-disparity balancing. Control symbols reset disparity.
module capture_tmds_encoder(
    input wire clk, rst, de,
    input wire [1:0] control,
    input wire [7:0] data,
    output reg [9:0] symbol
);
    function [3:0] ones8;
        input [7:0] value;
        integer i;
        begin
            ones8=0;
            for(i=0;i<8;i=i+1) ones8=ones8+value[i];
        end
    endfunction
    wire [3:0] input_ones=ones8(data);
    wire use_xnor=(input_ones>4) || (input_ones==4 && !data[0]);
    reg [8:0] minimized;
    integer j;
    always @* begin
        minimized[0]=data[0];
        for(j=1;j<8;j=j+1)
            minimized[j]=minimized[j-1]^data[j]^use_xnor;
        minimized[8]=!use_xnor;
    end
    reg [8:0] qm;
    reg valid;
    reg [1:0] ctrl;
    reg signed [5:0] disparity;
    wire [3:0] qm_ones=ones8(qm[7:0]);
    wire signed [5:0] balance=$signed({1'b0,qm_ones,1'b0})-6'sd8;
    always @(posedge clk or posedge rst) begin
        if(rst) begin qm<=0; valid<=0; ctrl<=0; end
        else begin qm<=minimized; valid<=de; ctrl<=control; end
    end
    always @(posedge clk or posedge rst) begin
        if(rst) begin symbol<=10'b1101010100; disparity<=0; end
        else if(!valid) begin
            disparity<=0;
            case(ctrl)
                0:symbol<=10'b1101010100;
                1:symbol<=10'b0010101011;
                2:symbol<=10'b0101010100;
                3:symbol<=10'b1010101011;
            endcase
        end else if(disparity==0 || balance==0) begin
            symbol<={!qm[8],qm[8],qm[8]?qm[7:0]:~qm[7:0]};
            disparity<=disparity+(qm[8]?balance:-balance);
        end else if((disparity>0 && balance>0) || (disparity<0 && balance<0)) begin
            symbol<={1'b1,qm[8],~qm[7:0]};
            disparity<=disparity+(qm[8]?6'sd2:6'sd0)-balance;
        end else begin
            symbol<={1'b0,qm[8],qm[7:0]};
            disparity<=disparity+balance-(qm[8]?6'sd0:6'sd2);
        end
    end
endmodule
