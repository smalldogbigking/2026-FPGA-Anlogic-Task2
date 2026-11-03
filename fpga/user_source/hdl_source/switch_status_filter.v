// Synchronizes the four mechanical switches and accepts a value only after
// the complete vector has remained unchanged for DEBOUNCE_CYCLES clocks.
module switch_status_filter #(
    parameter integer DEBOUNCE_CYCLES = 750000
) (
    input  wire       I_clk,
    input  wire       I_rst_n,
    input  wire [3:0] I_switch_async,
    output reg  [3:0] O_status
);
    reg [3:0] S_sync_1;
    reg [3:0] S_sync_2;
    reg [3:0] S_candidate;
    reg [19:0] S_stable_count;

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_sync_1 <= 0;
            S_sync_2 <= 0;
            S_candidate <= 0;
            S_stable_count <= 0;
            O_status <= 0;
        end
        else begin
            S_sync_1 <= I_switch_async;
            S_sync_2 <= S_sync_1;

            if(S_sync_2 != S_candidate) begin
                S_candidate <= S_sync_2;
                S_stable_count <= 0;
            end
            else if(DEBOUNCE_CYCLES <= 1) begin
                O_status <= S_candidate;
                S_stable_count <= 0;
            end
            else if(S_stable_count < (DEBOUNCE_CYCLES - 1)) begin
                S_stable_count <= S_stable_count + 20'd1;
            end
            else begin
                O_status <= S_candidate;
            end
        end
    end
endmodule

// Physical switches are contiguous 0..12. Existing USB mode IDs remain stable
// so the camera, scene controllers and installed clients keep their protocol.
module local_mode_decode(input wire[3:0] code,output reg[3:0] mode);
 always @*case(code)
  0,1,2:mode=code;
  3:mode=4;4:mode=5;5:mode=6;6:mode=7;
  7:mode=8;8:mode=9;9:mode=10;10:mode=12;11:mode=13;
  default:mode=15; // 12 is REMOTE; 13..15 are compatible REMOTE aliases.
 endcase
endmodule
