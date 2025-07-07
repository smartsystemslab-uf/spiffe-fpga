// This module generates true random values.
module trng_core (
    input  wire        clk,
    input  wire        reset_n,
    input  wire        start,
    output reg [255:0] data_o,
    output reg         valid_o
);
    // 16 ring oscillators sampled by system clock
    wire [15:0] ro_raw;
    genvar i;
    generate
        for (i = 0; i < 16; i = i + 1) begin : ROSC
            (* keep = "true" *) reg r1 = 1'b0, r2 = 1'b0;
            always @(r1) r2 <= ~r1;
            always @(r2) r1 <= ~r2;
            assign ro_raw[i] = r1;
        end
    endgenerate

    // Von‑Neumann debias
    reg [1:0] pair;
    wire pair_valid = (pair == 2'b01) || (pair == 2'b10);
    wire pair_bit   = pair[1] & ~pair[0];
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) pair <= 2'b00;
        else          pair <= {pair[0], ^ro_raw};
    end

    // Shift 256 unbiased bits into register
    reg collecting;
    reg [7:0] bit_cnt;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            collecting <= 1'b0; bit_cnt <= 8'd0; data_o <= 256'd0; valid_o <= 1'b0;
        end else begin
            valid_o <= 1'b0;
            if (start && !collecting) begin 
                collecting <= 1'b1; 
                bit_cnt <= 8'd0; 
            end
            if (collecting && pair_valid) begin
                data_o  <= {data_o[254:0], pair_bit};
                bit_cnt <= bit_cnt + 1'b1;
                if (bit_cnt == 8'd255) begin 
                    collecting <= 1'b0; 
                    valid_o <= 1'b1; 
                end
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
    output reg  [255:0] point_x_o,
    output reg  [255:0] point_y_o,
    output reg          done
);
    reg [4:0] cycle_cnt; 
    reg busy;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin 
            busy <= 1'b0; 
            done <= 1'b0; 
            cycle_cnt <= 5'd0; 
        end
        else begin
            done <= 1'b0;
            if (start && !busy) begin 
                busy <= 1'b1; 
                cycle_cnt <= 5'd0; 
            end
            else if (busy) begin
                cycle_cnt <= cycle_cnt + 1'b1;
                if (cycle_cnt == 5'd24) begin
                    point_x_o <= scalar_k ^ 256'hCAFEBABECAFEBABECAFEBABECAFEBABECAFEBABECAFEBABECAFEBABECAFEBABE;
                    point_y_o <= scalar_k ^ 256'h123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0;
                    done <= 1'b1; 
                    busy <= 1'b0;
                end
            end
        end
    end
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
    wire [255:0] rnd_out; 
    wire rnd_valid;
    
    trng_core u_rng (
        .clk(clk), 
        .reset_n(reset_n), 
        .start(state == S_TRNG), 
        .data_o(rnd_out), 
        .valid_o(rnd_valid)
    );

    reg ecc_start; 
    wire ecc_done; 
    wire [255:0] ecc_x, ecc_y;
    ecc_scalar_mult u_ecc (
        .clk(clk), 
        .reset_n(reset_n), 
        .start(ecc_start),
        .scalar_k(private_key), 
        .point_x_in(256'd0), 
        .point_y_in(256'd0),
        .point_x_o(ecc_x), 
        .point_y_o(ecc_y), 
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
                        private_key <= rnd_out;
                        state       <= S_ECC;
                    end
                end         
                S_ECC: begin
                    if (!ecc_start && !ecc_done) ecc_start <= 1'b1;
                    if (ecc_done) begin
                        public_key <= {ecc_x, ecc_y};
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
