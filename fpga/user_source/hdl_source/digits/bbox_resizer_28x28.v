// Exact 24x24 aspect-preserving crop centered in a 28x28 binary image.
// One shared DSP and narrow serial divider calculate coordinates on demand.
// Source rows are cached; no X/Y map arrays or dual-axis DDA state remain.
// Sampling stays floor(index*span/destination), with one outstanding read.
module bbox_resizer_28x28 #(
 parameter integer IMAGE_WIDTH=1280, IMAGE_HEIGHT=720,
 parameter integer COORD_WIDTH=12, ADDR_WIDTH=20, INNER_SIZE=24
)(
 input wire clk,rst_n,start,bbox_valid,
 input wire[COORD_WIDTH-1:0] bbox_x_min,bbox_y_min,bbox_x_max,bbox_y_max,
 output wire busy,output reg done,src_req,
 output reg[ADDR_WIDTH-1:0] src_addr,input wire src_valid,src_pixel,
 output reg out_we,output reg[9:0] out_addr,output reg out_pixel
);
 localparam IDLE=0,DIM_START=1,DIM_WAIT=2,ROW_START=3,ROW_WAIT=4,
            ROW_ADDR=5,OUTPUT=6,X_START=7,X_WAIT=8,REQUEST=9,MEM_WAIT=10,DONE=11;
 localparam DIV_BITS=COORD_WIDTH+$clog2(INNER_SIZE+1);
 localparam FACTOR_BITS=($clog2(IMAGE_WIDTH+1)>6)?$clog2(IMAGE_WIDTH+1):6;
 localparam PRODUCT_BITS=(ADDR_WIDTH>DIV_BITS)?ADDR_WIDTH:DIV_BITS;
 reg[3:0] state;
 reg[COORD_WIDTH-1:0] x_min,y_min,box_width,box_height,x_current,row_y;
 reg[5:0] dst_width,dst_height,x_offset,y_offset,x_end,y_end;
 reg[4:0] out_x,out_y;
 reg[ADDR_WIDTH-1:0] row_base;
 reg box_is_wide,row_ready;
 wire div_start=state==DIM_START || state==ROW_START || state==X_START;
 wire[COORD_WIDTH-1:0] multiply_span=state==DIM_START?(box_is_wide?box_height:box_width):
                                   state==ROW_ADDR?row_y:state==ROW_START?box_height:box_width;
 wire[5:0] local_x={1'b0,out_x}-x_offset,local_y={1'b0,out_y}-y_offset;
 wire[FACTOR_BITS-1:0] multiply_factor=state==DIM_START?INNER_SIZE:
                   state==ROW_ADDR?IMAGE_WIDTH:state==ROW_START?local_y:local_x;
 (* dsp_style="yes" *) wire[PRODUCT_BITS-1:0] coordinate_product=multiply_span*multiply_factor;
 wire[DIV_BITS-1:0] denominator=state==DIM_START?(box_is_wide?box_width:box_height):
                                              state==ROW_START?dst_height:dst_width;
 wire div_done;wire[DIV_BITS-1:0] quotient;
 resize_udiv #(.WIDTH(DIV_BITS)) divider(.clk(clk),.rst_n(rst_n),.start(div_start),
  .numerator(coordinate_product[DIV_BITS-1:0]),.denominator(denominator),
  .done(div_done),.quotient(quotient),.remainder());
 wire in_content=out_x>=x_offset && out_x<x_end && out_y>=y_offset && out_y<y_end && dst_width!=0 && dst_height!=0;
 wire emit=(state==OUTPUT && !in_content) || (state==MEM_WAIT && src_valid);
 assign busy=state!=IDLE;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=IDLE;done<=0;src_req<=0;src_addr<=0;out_we<=0;out_addr<=0;out_pixel<=0;
   x_min<=0;y_min<=0;box_width<=0;box_height<=0;box_is_wide<=0;
   dst_width<=0;dst_height<=0;x_offset<=0;y_offset<=0;x_end<=0;y_end<=0;
   out_x<=0;out_y<=0;x_current<=0;row_y<=0;row_base<=0;row_ready<=0;
  end else begin
   done<=0;src_req<=0;out_we<=0;
   case(state)
    IDLE:if(start)begin
     out_x<=0;out_y<=0;out_addr<=10'd1023;row_ready<=0;
     if(!bbox_valid || bbox_x_max<bbox_x_min || bbox_y_max<bbox_y_min ||
        bbox_x_max>=IMAGE_WIDTH || bbox_y_max>=IMAGE_HEIGHT)begin
      dst_width<=0;dst_height<=0;x_offset<=0;y_offset<=0;x_end<=0;y_end<=0;state<=OUTPUT;
     end else begin
      x_min<=bbox_x_min;y_min<=bbox_y_min;
      box_width<=bbox_x_max-bbox_x_min+1'b1;box_height<=bbox_y_max-bbox_y_min+1'b1;
      box_is_wide<=bbox_x_max-bbox_x_min>=bbox_y_max-bbox_y_min;
      state<=DIM_START;
     end
    end
    DIM_START:state<=DIM_WAIT;
    DIM_WAIT:if(div_done)begin
     if(box_is_wide)begin
      dst_width<=INNER_SIZE;dst_height<=quotient==0?1:quotient[5:0];
      x_offset<=(28-INNER_SIZE)/2;y_offset<=(28-(quotient==0?1:quotient[5:0]))/2;
      x_end<=(28-INNER_SIZE)/2+INNER_SIZE;
      y_end<=(28-(quotient==0?1:quotient[5:0]))/2+(quotient==0?1:quotient[5:0]);
     end else begin
      dst_height<=INNER_SIZE;dst_width<=quotient==0?1:quotient[5:0];
      y_offset<=(28-INNER_SIZE)/2;x_offset<=(28-(quotient==0?1:quotient[5:0]))/2;
      y_end<=(28-INNER_SIZE)/2+INNER_SIZE;
      x_end<=(28-(quotient==0?1:quotient[5:0]))/2+(quotient==0?1:quotient[5:0]);
     end
     state<=OUTPUT;
    end
    OUTPUT:if(in_content)state<=row_ready?X_START:ROW_START;
    ROW_START:state<=ROW_WAIT;
    ROW_WAIT:if(div_done)begin row_y<=y_min+quotient[COORD_WIDTH-1:0];state<=ROW_ADDR;end
    ROW_ADDR:begin row_base<=coordinate_product[ADDR_WIDTH-1:0];row_ready<=1;state<=X_START;end
    X_START:state<=X_WAIT;
    X_WAIT:if(div_done)begin x_current<=x_min+quotient[COORD_WIDTH-1:0];state<=REQUEST;end
    REQUEST:begin src_addr<=row_base+x_current;src_req<=1;state<=MEM_WAIT;end
    DONE:begin done<=1;state<=IDLE;end
    default:begin end
   endcase
   if(emit)begin
    out_we<=1;out_pixel<=state==MEM_WAIT?src_pixel:1'b0;out_addr<=out_addr+1'b1;
    if(out_x==27 && out_y==27)state<=DONE;
    else begin
     state<=OUTPUT;
     if(out_x==27)begin out_x<=0;out_y<=out_y+1'b1;row_ready<=0;end else out_x<=out_x+1'b1;
    end
   end
  end
 end
endmodule

// Narrow serial divider used only by the resizer; existing 24-cycle users
// below keep their original interface and timing. The remainder port is
// retained for compatibility with the earlier exact-coordinate implementation.
module resize_udiv #(parameter WIDTH=17)(
 input wire clk,rst_n,start,input wire[WIDTH-1:0] numerator,denominator,
 output reg done,output reg[WIDTH-1:0] quotient,output wire[WIDTH-1:0] remainder
);
 localparam COUNT_BITS=$clog2(WIDTH);
 reg active;reg[COUNT_BITS-1:0] count;
 reg[WIDTH-1:0] dividend,divisor;reg[WIDTH:0] rem;
 wire[WIDTH:0] shifted={rem[WIDTH-1:0],dividend[WIDTH-1]};
 wire subtract=shifted>={1'b0,divisor};
 assign remainder=rem[WIDTH-1:0];
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin active<=0;count<=0;dividend<=0;divisor<=0;rem<=0;quotient<=0;done<=0;end
  else begin
   done<=0;
   if(start&&!active)begin active<=1;count<=0;dividend<=numerator;divisor<=denominator;rem<=0;quotient<=0;end
   else if(active)begin
    dividend<={dividend[WIDTH-2:0],1'b0};rem<=subtract?shifted-{1'b0,divisor}:shifted;
    quotient<={quotient[WIDTH-2:0],subtract};
    if(count==WIDTH-1)begin active<=0;done<=1;end else count<=count+1'b1;
   end
  end
 end
endmodule

// 24-bit unsigned restoring divider, one quotient bit per clock.
module udiv24 (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [23:0] numerator,
    input  wire [23:0] denominator,
    output reg         done,
    output reg  [23:0] quotient
);
    reg active;
    reg [4:0] count;
    reg [23:0] dividend;
    reg [23:0] divisor;
    reg [24:0] remainder;
    wire [24:0] shifted_remainder = {remainder[23:0], dividend[23]};
    wire subtract = shifted_remainder >= {1'b0, divisor};
    wire [24:0] next_remainder = subtract ?
                                  shifted_remainder - {1'b0, divisor} :
                                  shifted_remainder;
    wire [23:0] next_quotient = {quotient[22:0], subtract};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active <= 1'b0; count <= 0; dividend <= 0; divisor <= 0;
            remainder <= 0; quotient <= 0; done <= 1'b0;
        end else begin
            done <= 1'b0;
            if (start && !active) begin
                active <= 1'b1;
                count <= 0;
                dividend <= numerator;
                divisor <= denominator;
                remainder <= 0;
                quotient <= 0;
            end else if (active) begin
                dividend <= {dividend[22:0], 1'b0};
                remainder <= next_remainder;
                quotient <= next_quotient;
                if (count == 23) begin
                    active <= 1'b0;
                    done <= 1'b1;
                end else begin
                    count <= count + 1'b1;
                end
            end
        end
    end
endmodule
