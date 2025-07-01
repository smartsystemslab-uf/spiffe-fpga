module hardware_bootloader (
    input wire clk,
    input wire reset_n,
    input wire [255:0] signature,
    input wire signature_valid,
    input wire [31:0] firmware_addr,
    input wire [31:0] firmware_data,
    input wire firmware_data_valid,
    output reg firmware_load_complete,
    output reg firmware_authentic,
    output reg [31:0] firmware_addr_req,
    output reg firmware_req_valid,
    output reg sec_agent_enable
);

    // States for bootloader FSM
    localparam IDLE = 3'b000;
    localparam FETCH_FIRMWARE = 3'b001;
    localparam VERIFY_SIGNATURE = 3'b010;
    localparam LOAD_FIRMWARE = 3'b011;
    localparam BOOT_COMPLETE = 3'b100;
    localparam BOOT_ERROR = 3'b101;

    reg [2:0] state, next_state;
    reg [31:0] firmware_bytes_received;
    reg [31:0] firmware_size;
    reg [255:0] computed_hash;

    // Hash calculation module instance
    wire hash_complete;
    wire [255:0] hash_result;

    sha256_hash hash_module (
        .clk(clk),
        .reset_n(reset_n),
        .data_in(firmware_data),
        .data_valid(firmware_data_valid && (state == FETCH_FIRMWARE)),
        .hash_complete(hash_complete),
        .hash_result(hash_result)
    );

    // Public key verification logic would be implemented here
    // For simplicity, we're assuming the signature verification module exists
    wire signature_match;

    signature_verify sig_verify (
        .clk(clk),
        .reset_n(reset_n),
        .signature(signature),
        .hash(hash_result),
        .verify_enable(state == VERIFY_SIGNATURE),
        .signature_match(signature_match)
    );

    // State machine for bootloader
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state <= IDLE;
            firmware_bytes_received <= 32'h0;
            firmware_addr_req <= 32'd0;
            firmware_load_complete <= 1'b0;
            firmware_authentic <= 1'b0;
            sec_agent_enable <= 1'b0;
            firmware_req_valid <= 1'b0;
            firmware_size <= 32'd0;
            firmware_bytes_received <= 32'd0;
        end else begin
            state <= next_state;
            firmware_req_valid <= 1'b0;

            case (state)

                 IDLE: begin
                bytes_received <= 32'd0;
                header_done <= 1'b0;
                if (signature_valid) begin
                    firmware_addr_req <= 32'd0;   // start of flash
                    firmware_req_valid<= 1'b1;
                end
            end
                 FETCH_FIRMWARE: begin
                if (firmware_data_valid && !header_done) begin
                    firmware_size    <= firmware_data;      // first word
                    header_done      <= 1'b1;
                    firmware_addr_req <= firmware_addr_req + 4;
                    firmware_req_valid <= 1'b1;
                end
            end
                VERIFY_SIGNATURE: begin
                    if (firmware_data_valid) begin
                        firmware_bytes_received <= firmware_bytes_received + 4; // Assuming 32-bit data bus
                        firmware_addr_req  <= firmware_addr_req + 4;
                        firmware_req_valid <= 1'b1;
                    end
                end

                BOOT_COMPLETE: begin
                    firmware_load_complete <= 1'b1;
                    firmware_authentic <= 1'b1;
                    sec_agent_enable <= 1'b1;
                end

                BOOT_ERROR: begin
                    firmware_load_complete <= 1'b1;
                    firmware_authentic <= 1'b0;
                    sec_agent_enable <= 1'b0;
                end
                default: ;
            endcase
        end
    end

    always @(*) begin
        next_state = state;

        case (state)
            IDLE: begin
                if (signature_valid) begin
                    next_state = FETCH_FIRMWARE;
                    firmware_addr_req = 32'h0; // Start at address 0
                    firmware_req_valid = 1'b1;
                end
            end

            FETCH_FIRMWARE: begin
                if (firmware_bytes_received >= firmware_size && hash_complete) begin
                    next_state = VERIFY_SIGNATURE;
                    firmware_req_valid = 1'b0;
                end else if (firmware_data_valid) begin
                    firmware_addr_req = firmware_addr_req + 4; // Next address
                    firmware_req_valid = 1'b1;
                end
            end

            VERIFY_SIGNATURE: begin
                if (signature_match) begin
                    next_state = LOAD_FIRMWARE;
                end else begin
                    next_state = BOOT_ERROR;
                end
            end

            LOAD_FIRMWARE: begin
                // In a real implementation, we would load the firmware to the execution memory
                // For simplicity, we assume it's already loaded during fetch
                next_state = BOOT_COMPLETE;
            end

            BOOT_COMPLETE: begin
                // Stay in this state
            end

            BOOT_ERROR: begin
                // Stay in this state
            end
        endcase
    end

endmodule
