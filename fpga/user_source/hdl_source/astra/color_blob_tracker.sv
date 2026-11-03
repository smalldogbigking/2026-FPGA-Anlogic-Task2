// Bounded row-run targets; pixel-rate association never stalls the stream.
// The EOF geometry uses the available DSP multipliers. Explicit coordinate
// and slot widths avoid oversized muxes. Hu first invariant distinguishes
// disk/square/triangle independently of rotation; rough perimeter is unused.
// Shape labels are heuristic; unknown regions remain valid tracking targets.
module color_blob_tracker #(parameter SLOTS=4,RUN_MIN=3,MIN_AREA=64,MIN_SIZE=8,OUTPUTS=SLOTS,FILL_HOLES=1,X_BITS=12,Y_BITS=12)(
 input wire clk,rst_n,sof,eof,valid,eol,hit,input wire[4:0] edge_cost,
 input wire[11:0] x,y,
 output reg box_valid,busy,overflow,output reg[11:0] min_x,max_x,min_y,max_y,
 output reg[31:0] area,output reg[1:0] shape,
 output reg[OUTPUTS-1:0] target_valid,output reg[OUTPUTS*48-1:0] target_boxes,
 output reg[OUTPUTS*2-1:0] target_shapes
);
 // Configured raster bounds remove unused bits from every parallel
 // slot comparator and stored box. Default twelve-bit coordinates preserve
 // the generic module; the 720p instance uses eleven X and ten Y bits.
 wire[11:0] bounded_x={{(12-X_BITS){1'b0}},x[X_BITS-1:0]};
 wire[11:0] bounded_y={{(12-Y_BITS){1'b0}},y[Y_BITS-1:0]};
 localparam INDEX_BITS=SLOTS>1?$clog2(SLOTS):1;
 localparam OUTPUT_BITS=OUTPUTS>1?$clog2(OUTPUTS):1;
 reg used[0:SLOTS-1];
 // These flags are exact functions of the committed slot registers. Derive
 // them from those registers instead of routing the current run through slot
 // selection, min/max merging, width subtraction and a second register.
 wire small_region[0:SLOTS-1];
 reg[X_BITS-1:0] xmin[0:SLOTS-1],xmax[0:SLOTS-1];
 reg[Y_BITS-1:0] ymin[0:SLOTS-1],ymax[0:SLOTS-1];
 reg[19:0] hits[0:SLOTS-1];
 genvar region;
 generate for(region=0;region<SLOTS;region=region+1)begin: region_size
  assign small_region[region]=hits[region]<MIN_AREA ||
   ({1'b0,xmax[region]}-{1'b0,xmin[region]}+13'd1)<MIN_SIZE ||
   ({1'b0,ymax[region]}-{1'b0,ymin[region]}+13'd1)<MIN_SIZE;
 end endgenerate
 // Integrate area moments rather than noisy boundary length. A 2x2 grid
 // is sampled; bounded_x/bounded_y are halved to bound multiplier widths.
 (* ram_style="distributed" *) reg[17:0] samples[0:SLOTS-1];
 (* ram_style="distributed" *) reg[27:0] mxsum[0:SLOTS-1],mysum[0:SLOTS-1];
 (* ram_style="distributed" *) reg[36:0] m2sum[0:SLOTS-1];
 reg moment_write;reg[INDEX_BITS-1:0] moment_slot;
 reg[17:0] write_n;reg[27:0] write_x,write_y;reg[36:0] write_q;
 always @(posedge clk)if(moment_write)begin
  samples[moment_slot]<=write_n;mxsum[moment_slot]<=write_x;
  mysum[moment_slot]<=write_y;m2sum[moment_slot]<=write_q;
 end
 reg[10:0] rn;reg[21:0] rx,ry;reg[31:0] rq;
 wire take=hit && !bounded_x[0] && !bounded_y[0];
 wire[10:0] half_x=bounded_x[11:1],half_y=bounded_y[11:1];
 wire[22:0] pixel_q=half_x*half_x+half_y*half_y;
 wire[11:0] next_rn={1'b0,rn}+take;
 wire[22:0] next_rx={1'b0,rx}+(take?half_x:11'd0),next_ry={1'b0,ry}+(take?half_y:11'd0);
 wire[32:0] next_rq={1'b0,rq}+(take?pixel_q:23'd0);
 // A printed glyph removes red pixels, but must not remove silhouette mass.
 // Integrate the complete horizontal span since the last accepted run. Only
 // bridge it when that next run belongs to the SAME slot on the SAME row.
 // Different objects keep their own moments; RGB and detection hit area are
 // untouched. The existing bounded_x/bounded_y square products are reused (no new DSP).
 reg[10:0] span_n;reg[21:0] span_x,span_y_sum;reg[31:0] span_q;
 reg[Y_BITS-1:0] span_row,last_run_row;reg last_run_valid;
 reg[INDEX_BITS-1:0] last_run_slot;reg use_bridge;
 wire whole_take=!bounded_x[0]&&!bounded_y[0];wire new_row=sof || bounded_y!=span_row;
 wire[11:0] span_next_n=new_row?whole_take:({1'b0,span_n}+whole_take);
 wire[22:0] span_next_x=(new_row?23'd0:{1'b0,span_x})+(whole_take?half_x:11'd0);
 wire[22:0] span_next_y=(new_row?23'd0:{1'b0,span_y_sum})+(whole_take?half_y:11'd0);
 wire[32:0] span_next_q=(new_row?33'd0:{1'b0,span_q})+(whole_take?pixel_q:23'd0);
 wire[11:0] span_end_n=hit?span_next_n:{1'b0,span_n};
 wire[22:0] span_end_x=hit?span_next_x:{1'b0,span_x},span_end_y=hit?span_next_y:{1'b0,span_y_sum};
 wire[32:0] span_end_q=hit?span_next_q:{1'b0,span_q};
 reg[X_BITS-1:0] run_start,length;reg[12:0] run_n;
 integer i,j;reg signed[OUTPUT_BITS:0] out_slot;reg signed[INDEX_BITS:0] slot,free_slot;reg[INDEX_BITS-1:0] scan;
 reg[19:0] output_area[0:OUTPUTS-1];
 reg[OUTPUT_BITS-1:0] sort_index,sort_pass;
 wire[OUTPUT_BITS-1:0] sort_next=sort_index+1'b1;
 reg[X_BITS-1:0] run_end,w;reg[Y_BITS-1:0] h;reg[23:0] rect_area;
 reg candidate_reg;reg[4:0] phase;reg[1:0] shape_calc;reg[2:0] multiply_wait;
 reg[OUTPUT_BITS-1:0] admission_scan;
 reg[19:0] admission_area;
 // One time-shared multiply datapath in frame blanking, not 5 parallel wide
 // multipliers. Stage waits allow an explicit registered DSP product.
 reg[53:0] op_a;reg[27:0] op_b;wire[81:0] product;
 reg[54:0] central;reg[53:0] cube;reg[35:0] n2;
 wire[64:0] central_scaled={central,10'd0};
 // One 18x28 DSP pair, reused for the three limbs. Horner accumulation
 // has fixed shifts, no 82-bit barrel selector and only one carry chain.
 // Exact 82-bit products preserve all Hu moments and classification limits.
 wire multiply_start=busy && phase<16 && phase[0] && multiply_wait==0;
 tracker_mul54x28 hu_product(clk,rst_n,multiply_start,op_a,op_b,product,);
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   box_valid<=0;busy<=0;overflow<=0;min_x<=0;max_x<=0;min_y<=0;max_y<=0;area<=0;shape<=0;
   target_valid<=0;target_boxes<=0;target_shapes<=0;run_start<=0;length<=0;rn<=0;rx<=0;ry<=0;rq<=0;scan<=0;
   span_n<=0;span_x<=0;span_y_sum<=0;span_q<=0;span_row<=0;last_run_row<=0;last_run_slot<=0;last_run_valid<=0;
   phase<=0;multiply_wait<=0;candidate_reg<=0;moment_write<=0;moment_slot<=0;write_n<=0;write_x<=0;write_y<=0;write_q<=0;op_a<=0;op_b<=0;central<=0;cube<=0;n2<=0;shape_calc<=0;rn<=0;rx<=0;ry<=0;rq<=0;
   for(i=0;i<SLOTS;i=i+1)begin used[i]<=0;xmin[i]<=0;xmax[i]<=0;ymin[i]<=0;ymax[i]<=0;hits[i]<=0;end
   for(i=0;i<OUTPUTS;i=i+1)output_area[i]<=0;
   sort_index<=0;sort_pass<=0;admission_scan<=0;admission_area<=0;out_slot<=0;
  end else begin
   moment_write<=0;
   if(valid)begin
    span_row<=bounded_y;span_n<=span_next_n;span_x<=span_next_x;span_y_sum<=span_next_y;span_q<=span_next_q;
   end
   if(sof)begin
   last_run_valid<=0;
   for(i=0;i<SLOTS;i=i+1)begin used[i]<=0;hits[i]<=0;end
   overflow<=busy;busy<=0;phase<=0;rn<=take?1:0;rx<=take?half_x:0;ry<=take?half_y:0;rq<=take?pixel_q:0;length<=(valid&&hit)?1:0;run_start<=bounded_x;
  end else if(eof)begin busy<=1;scan<=0;phase<=0;area<=0;box_valid<=0;target_valid<=0;
  end else if(busy)begin
   if(!phase[0])multiply_wait<=0;else multiply_wait<=multiply_wait+1'b1;
   case(phase)
   0:begin
    w=xmax[scan]-xmin[scan]+12'd1;h=ymax[scan]-ymin[scan]+12'd1;rect_area=w*h;
    // No aspect-ratio gate: large arbitrary red regions may be TRACK targets.
    // Retain minimum size/area and sparse-noise rejection.
    candidate_reg<=used[scan]&&w>=MIN_SIZE&&h>=MIN_SIZE&&hits[scan]>=MIN_AREA&&
      samples[scan]>=16&&hits[scan]>=(rect_area>>3)&&hits[scan]<=rect_area;
    op_a<=m2sum[scan];op_b<=samples[scan];phase<=1;
   end
   1:if(multiply_wait==4)phase<=2;
   2:begin central<=product[54:0];op_a<=mxsum[scan];op_b<=mxsum[scan];phase<=3;end
   3:if(multiply_wait==4)phase<=4;
   4:begin central<=central-product[54:0];op_a<=mysum[scan];op_b<=mysum[scan];phase<=5;end
   5:if(multiply_wait==4)phase<=6;
   6:begin central<=central-product[54:0];op_a<=samples[scan];op_b<=samples[scan];phase<=7;end
   7:if(multiply_wait==4)phase<=8;
   8:begin n2<=product[35:0];op_a<=product[35:0];op_b<=samples[scan];phase<=9;end
   9:if(multiply_wait==4)phase<=10;
   10:begin cube<=product[53:0];op_a<=product[53:0];op_b<=167;phase<=11;end
   11:if(multiply_wait==4)phase<=12;
   12:begin shape_calc<=central_scaled<product?1:3;op_a<=cube;op_b<=186;phase<=13;end
   13:if(multiply_wait==4)phase<=14;
   14:begin if(central_scaled>=product)shape_calc<=2;op_a<=cube;op_b<=256;phase<=15;end
   15:if(multiply_wait==4)phase<=16;
   16:begin
    // Unknown elongated/irregular shape is still a valid tracking target.
    if(central_scaled>=product)shape_calc<=0;
    phase<=17;
   end
   17:begin
    if(candidate_reg)begin
     // Select a vacant output immediately. A full set is scanned across
     // blanking clocks with one comparator instead of a priority mux tree.
     out_slot=-1;
     for(j=0;j<OUTPUTS;j=j+1)if(!target_valid[j] && out_slot<0)out_slot=j;
     if(out_slot<0)begin
      out_slot=0;admission_area<=output_area[0];admission_scan<=1;
      phase<=OUTPUTS>1?20:19;
     end else begin admission_area<=0;phase<=19;end
    end else phase<=21;
   end
   20:begin
    if(output_area[admission_scan]<admission_area)begin
     admission_area<=output_area[admission_scan];out_slot=admission_scan;
    end
    if(admission_scan==OUTPUTS-1)phase<=19;
    else admission_scan<=admission_scan+1'b1;
   end
   19:begin
    // Constant write lanes avoid a variable 48-bit output crossbar.
    if(hits[scan]>admission_area)for(j=0;j<OUTPUTS;j=j+1)if(out_slot==j)begin
     target_valid[j]<=1;output_area[j]<=hits[scan];
     target_boxes[j*48+:48]<={{(12-X_BITS){1'b0}},xmin[scan],{(12-X_BITS){1'b0}},xmax[scan],{(12-Y_BITS){1'b0}},ymin[scan],{(12-Y_BITS){1'b0}},ymax[scan]};
     target_shapes[j*2+:2]<=shape_calc;
    end
    if(hits[scan]>area)begin shape<=shape_calc;box_valid<=1;area<=hits[scan];min_x<=xmin[scan];max_x<=xmax[scan];min_y<=ymin[scan];max_y<=ymax[scan];end
    phase<=21;
   end
   21:begin
    phase<=0;if(scan==SLOTS-1)begin
     if(OUTPUTS>1)begin phase<=18;sort_index<=0;sort_pass<=0;end
     else busy<=0;
    end else scan<=scan+1'b1;
   end
   18:begin
    // Stable left-to-right display slots. Size ranking alone can permute
    // slots with one noisy pixel and reset cross-frame confirmation forever.
    // Elaborate adjacent swap lanes with CONSTANT slices. Variable 48-bit
    // reads/writes made a wide crossbar even though only neighbours swap.
    // Only the selected lane changes; bubble-sort order/ties/cycles are exact.
    for(j=0;j<OUTPUTS-1;j=j+1)begin
     if(sort_index==j && target_valid[j+1] && (!target_valid[j] ||
        target_boxes[(j+1)*48+36+:12]<target_boxes[j*48+36+:12]))begin
      target_valid[j]<=target_valid[j+1];target_valid[j+1]<=target_valid[j];
      target_boxes[j*48+:48]<=target_boxes[(j+1)*48+:48];target_boxes[(j+1)*48+:48]<=target_boxes[j*48+:48];
      target_shapes[j*2+:2]<=target_shapes[(j+1)*2+:2];target_shapes[(j+1)*2+:2]<=target_shapes[j*2+:2];
     end
    end
    // output_area is only an admission key before sorting (phase 17).
    // It need not travel with a displayed box. EOF clears target_valid;
    // each slot's key is overwritten before the next full-set comparison.
    if(sort_index==OUTPUTS-2)begin
     sort_index<=0;
     if(sort_pass==OUTPUTS-2)begin phase<=0;busy<=0;end
     else sort_pass<=sort_pass+1'b1;
    end else sort_index<=sort_index+1'b1;
   end
   default:phase<=0;
   endcase
  end else if(valid)begin
   run_n={1'b0,length}+hit;run_end=hit?bounded_x:bounded_x-12'd1;
   if(hit&&length==0)run_start<=bounded_x;
   if(!hit||eol)begin
    if(run_n>=RUN_MIN)begin
     slot=-1;free_slot=-1;
     for(j=0;j<SLOTS;j=j+1)begin
      if((!used[j]||({1'b0,bounded_y}>{1'b0,ymax[j]}+13'd2&&
        small_region[j]))&&free_slot<0)free_slot=j;
      if(used[j]&&slot<0&&{1'b0,bounded_y}<={1'b0,ymax[j]}+13'd2&&bounded_y>=ymax[j]&&
        {1'b0,run_start}<={1'b0,xmax[j]}+13'd2&&{1'b0,run_end}+13'd2>={1'b0,xmin[j]})slot=j;
     end
     if(slot<0)begin
      if(free_slot<0)begin overflow<=1;last_run_valid<=0;end
      else begin
       used[free_slot]<=1;xmin[free_slot]<=run_start;xmax[free_slot]<=run_end;ymin[free_slot]<=bounded_y;ymax[free_slot]<=bounded_y;hits[free_slot]<=run_n;moment_write<=1;moment_slot<=free_slot;write_n<=next_rn;write_x<=next_rx;write_y<=next_ry;write_q<=next_rq;end
     end else begin
      if(run_start<xmin[slot])xmin[slot]<=run_start;if(run_end>xmax[slot])xmax[slot]<=run_end;
      use_bridge=FILL_HOLES && last_run_valid && last_run_row==bounded_y && last_run_slot==slot;
      ymax[slot]<=bounded_y;hits[slot]<=hits[slot]+run_n;moment_write<=1;moment_slot<=slot;
      write_n<=samples[slot]+(use_bridge?span_end_n:next_rn);
      write_x<=mxsum[slot]+(use_bridge?span_end_x:next_rx);
      write_y<=mysum[slot]+(use_bridge?span_end_y:next_ry);
      write_q<=m2sum[slot]+(use_bridge?span_end_q:next_rq);
     end
     if(slot>=0 || free_slot>=0)begin
      last_run_valid<=1;last_run_slot<=slot>=0?slot:free_slot;last_run_row<=bounded_y;
      // The first black pixel ended the previous run; it is already the
      // first pixel of the following gap, so retain its contribution.
      span_n<=(!hit&&whole_take)?1:0;span_x<=(!hit&&whole_take)?half_x:0;
      span_y_sum<=(!hit&&whole_take)?half_y:0;span_q<=(!hit&&whole_take)?pixel_q:0;
     end
    end
    length<=0;rn<=0;rx<=0;ry<=0;rq<=0;
   end else begin length<=run_n;rn<=next_rn;rx<=next_rx;ry<=next_ry;rq<=next_rq;end
  end
  end
 end
endmodule

// The caller holds a/b until done. Three base-2^18 limbs are multiplied
// high-to-low through one 18x28 multiplier; the unsigned result is exact.
module tracker_mul54x28(input wire clk,rst_n,start,input wire[53:0] a,
 input wire[27:0] b,output reg[81:0] product,output reg done);
 reg[1:0] stage;
 reg[45:0] partial;
 wire[17:0] limb=start?a[53:36]:(stage==1?a[35:18]:a[17:0]);
 always @(posedge clk)begin
  partial<=limb*b;
  if(stage==1)product<={36'd0,partial};
  else if(stage==2 || stage==3)product<={product[63:0],18'd0}+{36'd0,partial};
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin stage<=0;done<=0;end
  else begin
   done<=0;
   if(start)stage<=1;
   else if(stage!=0)begin
    if(stage==3)begin stage<=0;done<=1;end else stage<=stage+1'b1;
   end
  end
 end
endmodule
