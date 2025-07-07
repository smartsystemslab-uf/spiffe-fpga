`define P256_PRIME 256'hFFFFFFFF00000001000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFF

// This module generates true random values.
module trng_core (
    input  wire        clk,
    input  wire        reset_n,
    input  wire        start,
    output reg [255:0] data_o,
    output reg         valid_o
);
    wire [15:0] ro_raw;
    genvar i;
    generate
        for (i=0;i<16;i=i+1) begin:RO
            (* keep = "true" *) reg r1=1'b0, r2=1'b0;
            always @(r1) r2<=~r1;
            always @(r2) r1<=~r2;
            assign ro_raw[i]=r1;
        end
    endgenerate
    // Von‑Neumann de‑biaser
    reg [1:0] pair; 
    wire vn_valid = (pair==2'b01)||(pair==2'b10);
    wire vn_bit = pair[1] & ~pair[0];
    always @(posedge clk or negedge reset_n) begin
                if(!reset_n) pair<=0; else pair<={pair[0],^ro_raw};
    end
    reg collecting; reg [7:0] cnt;
    always @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin collecting<=0;cnt<=0;data_o<=0;valid_o<=0;end
        else begin
            valid_o<=0;
            if(start && !collecting) begin collecting<=1; cnt<=0; end
            if(collecting && vn_valid) begin
                data_o <= {data_o[254:0], vn_bit};
                cnt    <= cnt + 1'b1;
                if(cnt==8'd255) begin collecting<=0; valid_o<=1; end
            end
        end
    end
endmodule

//Constant-time field helpers

function [255:0] ct_add;
    input [255:0] a, b;
    reg [256:0] sum;
    reg [255:0] tmp;
    reg borrow;
    begin
        sum = a + b;
        // conditional subtract p without branches
        borrow = (sum[256] || (sum[255:224] == 32'hFFFFFFFF));
        tmp = sum[255:0] - (`P256_PRIME & {256{~borrow}});
        ct_add = tmp;
    end
endfunction

function [255:0] ct_sub;
    input [255:0] a, b;
    reg [256:0] diff;
    reg borrow;
    begin
        diff = {1'b0,a} - b;
        borrow = diff[256];
        ct_sub = diff[255:0] + (`P256_PRIME & {256{borrow}});
    end
endfunction

// schoolbook mul + Solinas reduction (256×256 → 512 → 256)
function [511:0] wide_mul;
    input [255:0] x,y;
    integer i;
    reg [511:0] res;
    begin
        res = 0;
        for(i=0;i<256;i=i+1) if(y[i]) res = res + (x << i);
        wide_mul = res;
    end
endfunction

function [255:0] ct_mul;
    input [255:0] a,b;
    reg [511:0] prod;
    reg [255:0] t0,t1,t2,t3;
    begin
        prod = wide_mul(a,b);
        // Solinas reduction: split prod = low + high*2^256
        t0 = prod[255:0];
        t1 = prod[511:256];
        // fold high limbs: 2^256 ≡ 2^224 − 2^192 − 2^96 +1 (mod p)
        t2 = (t1 << 224) | (t1 >> 32);
        t3 = (t1 << 192) | (t1 >> 64);
        ct_mul = ct_add(t0, ct_add(t2, ct_sub(t1, t3))); // one extra reduction inside ct_add
    end
endfunction

module p256_consttime_ladder (
    input  wire         clk,
    input  wire         reset_n,
    input  wire         start,
    input  wire [255:0] d,
    input  wire [255:0] x_in,
    input  wire [255:0] y_in,
    output reg  [255:0] x_out,
    output reg  [255:0] y_out,
    output reg          done
);
    // State
    reg [8:0] idx; reg busy;
    

    // current scalar bit (combinational)
    wire sel = d[idx];
    reg [255:0] X1,Z1,X2,Z2;

    // cswap mask
    function [255:0] cswap;
        input [255:0] a,b; input sel;
        cswap = (a & {256{~sel}}) | (b & {256{sel}});
    endfunction

    // Point doubling and differential addition (placeholders → real formulas)
    function [255:0] f_add(input [255:0] a,b); f_add = ct_add(a,b); endfunction
    function [255:0] f_sub(input [255:0] a,b); f_sub = ct_sub(a,b); endfunction
    function [255:0] f_mul(input [255:0] a,b); f_mul = ct_mul(a,b); endfunction

    always @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin busy<=0;done<=0;x_out<=0;y_out<=0;end
        else begin done<=0;
            if(start && !busy) begin
                busy<=1; idx<=9'd255;
                X1<=1; Z1<=0; // R0 = O
                X2<=x_in; Z2<=1; // R1 = P
            end else if(busy) begin                // conditional swap                X1<=cswap(X1,X2,sel); X2<=cswap(X2,X1,sel);
                Z1<=cswap(Z1,Z2,sel); Z2<=cswap(Z2,Z1,sel);
                // Dummy EC ops (replace with proj formulas for prod)
                X1<=f_mul(X1,X1); Z1<=f_mul(Z1,Z1);
                X2<=f_mul(X2,X2); Z2<=f_mul(Z2,Z2);
                if(idx==0) begin busy<=0; done<=1; x_out<=X1; y_out<=f_sub(X1,Z1); end else idx<=idx-1'b1;
            end
        end
    end
endmodule

module ecc_scalar_mult (
    input  wire         clk,
    input  wire         reset_n,
    input  wire         start,
    input  wire [255:0] scalar_k,
    input  wire [255:0] point_x_in,
    input  wire [255:0] point_y_in,
    output wire [255:0] point_x_o,
    output wire [255:0] point_y_o,
    output wire         done
);
    localparam GX = 256'h6B17D1F2E12C4247F8BCE6E563A440F277037D812DEB33A0F4A13945D898C296;
    localparam GY = 256'h4FE342E2FE1A7F9B8EE7EB4A7C0F9E162BCE33576B315ECECBB6406837BF51F5;

    wire [255:0] px = (point_x_in==0)?GX:point_x_in;
    wire [255:0] py = (point_y_in==0)?GY:point_y_in;

    p256_consttime_ladder u_ladder (
        .clk(clk), .reset_n(reset_n), .start(start), .d(scalar_k),
        .x_in(px), .y_in(py), .x_out(point_x_o), .y_out(point_y_o), .done(done)
    );
endmodule


module ecdhe_keygen (
    input wire clk,
    input wire reset_n,
    input wire start,
    output reg [511:0] public_key,
    output reg [255:0] private_key,
    output reg complete
);
    reg [7:0] counter;
    reg busy;
    localparam [1:0] S_IDLE = 2'd0, S_TRNG = 2'd1, S_ECC = 2'd2, S_DONE = 2'd3;
    reg [1:0] state;
    wire [255:0] rnd; 
    wire rnd_valid;
    
    trng_core u_rng (
        .clk(clk), 
        .reset_n(reset_n), 
        .start(state == S_TRNG), 
        .data_o(rnd), 
        .valid_o(rnd_valid)
    );

    reg ecc_start; 
    wire ecc_done; 
    wire [255:0] px, py;
    ecc_scalar_mult u_ecc (
        .clk(clk), 
        .reset_n(reset_n), 
        .start(ecc_start),
        .scalar_k(private_key), 
        .point_x_in(256'd0), 
        .point_y_in(256'd0),
        .point_x_o(px), 
        .point_y_o(py), 
        .done(ecc_done)
    );
    
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state <= S_IDLE;
            counter <= 8'd0;
            busy <= 1'b0;
            ecc_start <= 1'b0;
            complete <= 1'b0;
            public_key <= 512'd0;
            private_key <= 256'd0;
        end else begin
            ecc_start <= 1'b0; 
            complete <= 1'b0;
            case (state)
                 S_IDLE: begin
                    if (start) state <= S_TRNG;
                end
                S_TRNG: begin
                    if (rnd_valid) begin
                        private_key <= rnd;
                        ecc_start <= 1'b1;
                        state       <= S_ECC;
                    end
                end         
                S_ECC: begin
                    if (ecc_done) begin
                        public_key <= {px, py};        // concat (x||y)
                        state      <= S_DONE;
                    end
                end
                S_DONE: begin
                    complete <= 1'b1;
                    state    <= S_IDLE;           // auto‑return
                end
            endcase
        end
    end
endmodule
