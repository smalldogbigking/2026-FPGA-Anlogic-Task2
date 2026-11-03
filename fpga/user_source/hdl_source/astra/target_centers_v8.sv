// Frame-stable center coordinates. Only SLOTS targets are converted/stored;
// unused high output slots are zero. Default eight preserves the legacy API.
module target_centers_v8 #(parameter SLOTS=8)(input wire clk,rst_n,start,input wire[7:0] valid,
 input wire[383:0] boxes,output reg[255:0] bcd,output reg[3:0] count);
 reg busy;reg[3:0] index,bitcount;reg[11:0] binary;reg[15:0] work,adjusted;
 reg[SLOTS*48-1:0] captured;reg[SLOTS*32-1:0] pending;integer j;
 reg[3:0] valid_count;
 wire[47:0] boxvalue=captured[(index>>1)*48 +:48];
 wire[12:0] sumx={1'b0,boxvalue[47:36]}+boxvalue[35:24];
 wire[12:0] sumy={1'b0,boxvalue[23:12]}+boxvalue[11:0];
 always @*begin
  adjusted=work;for(j=0;j<4;j=j+1)if(work[j*4 +:4]>=5)adjusted[j*4 +:4]=work[j*4 +:4]+3;
  valid_count=0;for(j=0;j<SLOTS;j=j+1)valid_count=valid_count+valid[j];
 end
 always @(posedge clk or negedge rst_n)begin
 if(!rst_n)begin busy<=0;index<=0;bitcount<=0;binary<=0;work<=0;bcd<=0;count<=0;captured<=0;pending<=0;end
 else if(start)begin
 captured<=boxes[SLOTS*48-1:0];index<=0;bitcount<=0;busy<=1;work<=0;count<=valid_count;
 end else if(busy)begin
 if(bitcount==0)begin binary<=index[0]?sumy[12:1]:sumx[12:1];work<=0;bitcount<=1;end
 else begin
 work<={adjusted[14:0],binary[11]};binary<=binary<<1;
 if(bitcount==12)begin
 pending[(index>>1)*32+(index[0]?0:16) +:16]<={adjusted[14:0],binary[11]};
 if(index==SLOTS*2-1)begin busy<=0;
 bcd<=0;bcd[SLOTS*32-1:0]<=pending;bcd[(SLOTS-1)*32 +:16]<={adjusted[14:0],binary[11]};
 end else begin index<=index+1'b1;bitcount<=0;end
 end else bitcount<=bitcount+1'b1;
 end
 end
 end
endmodule
