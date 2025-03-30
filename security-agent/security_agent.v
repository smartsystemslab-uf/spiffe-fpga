module security_agent (
    input wire clk,
    input wire reset_n,

    // Firmware interface
    input wire agent_enable,

    // Key Management Interface
    input wire [2047:0] ek_priv,
    input wire ek_priv_valid,
    input wire [2047:0] aik_pub,
    input wire [2047:0] aik_priv,
    input wire aik_valid,
    input wire [4095:0] aik_cert,
    input wire aik_cert_valid,

    // External Communication Interface
    input wire [31:0] rx_data,
    input wire rx_valid,
    output reg [31:0] tx_data,
    output reg tx_valid,

    // NVRAM interface for certificate storage
    output reg [31:0] nvram_addr,
    output reg nvram_rd_en,
    input wire [31:0] nvram_rd_data,
    input wire nvram_rd_valid,
    output reg nvram_wr_en,
    output reg [31:0] nvram_wr_data,

    // Configuration interface
    output reg [31:0] config_addr,
    output reg config_wr_en,
    output reg [31:0] config_data
);

    // Protocol state machine states
    localparam IDLE                    = 4'h0;
    localparam WAIT_FOR_KEYS           = 4'h1;
    localparam WAIT_FOR_AUTH_REQUEST   = 4'h2;
    localparam GENERATE_ECDHE_KEYPAIR  = 4'h3;
    localparam SEND_CERTIFICATES       = 4'h4;
    localparam WAIT_FOR_CLIENT_KEY     = 4'h5;
    localparam VERIFY_CLIENT_SIGNATURE = 4'h6;
    localparam COMPUTE_SHARED_SECRET   = 4'h7;
    localparam RECEIVE_ENCRYPTED_BITSTREAM = 4'h8;
    localparam DECRYPT_BITSTREAM       = 4'h9;
    localparam VERIFY_BITSTREAM_HASH   = 4'hA;
    localparam CONFIGURE_FPGA          = 4'hB;
    localparam AUTHENTICATION_COMPLETE = 4'hC;
    localparam ERROR                   = 4'hF;

    reg [3:0] state, next_state;

    // Message types for protocol communication
    localparam MSG_AUTH_REQUEST        = 32'h00000001;
    localparam MSG_CERT_RESPONSE       = 32'h00000002;
    localparam MSG_CLIENT_KEY          = 32'h00000003;
    localparam MSG_ENCRYPTED_BITSTREAM = 32'h00000004;
    localparam MSG_AUTH_COMPLETE       = 32'h00000005;
    localparam MSG_ERROR               = 32'hFFFFFFFF;

    // Internal registers
    reg [31:0] message_type;
    reg [31:0] message_length;
    reg [31:0] bytes_received;
    reg [31:0] bytes_to_send;

    // ECDHE parameters
    reg [255:0] ecdhe_private_key;
    reg [511:0] ecdhe_public_key;
    reg [255:0] client_public_key;
    reg [255:0] nonce_fpga;
    reg [255:0] nonce_client;
    reg [255:0] shared_secret;
    reg [255:0] session_key;

    // Bitstream parameters
    reg [31:0] bitstream_size;
    reg [255:0] bitstream_hash;
    reg [255:0] received_hash;

    // ECDHE key generation module instance
    wire ecdhe_keygen_complete;
    wire [511:0] generated_public_key;
    wire [255:0] generated_private_key;

    ecdhe_keygen ecdhe_gen (
        .clk(clk),
        .reset_n(reset_n),
        .start(state == GENERATE_ECDHE_KEYPAIR),
        .public_key(generated_public_key),
        .private_key(generated_private_key),
        .complete(ecdhe_keygen_complete)
    );

    // ECDHE shared secret computation module
    wire ecdhe_compute_complete;
    wire [255:0] computed_shared_secret;

    ecdhe_compute ecdhe_comp (
        .clk(clk),
        .reset_n(reset_n),
        .private_key(ecdhe_private_key),
        .peer_public_key(client_public_key),
        .start(state == COMPUTE_SHARED_SECRET),
        .shared_secret(computed_shared_secret),
        .complete(ecdhe_compute_complete)
    );

    // Key Derivation Function for session key
    wire kdf_complete;
    wire [255:0] derived_key;

    kdf key_derivation (
        .clk(clk),
        .reset_n(reset_n),
        .shared_secret(shared_secret),
        .nonce_fpga(nonce_fpga),
        .nonce_client(nonce_client),
        .start(ecdhe_compute_complete),
        .session_key(derived_key),
        .complete(kdf_complete)
    );

    // AES-GCM decryption for bitstream
    wire aes_gcm_complete;
    wire [31:0] decrypted_data;
    wire decrypted_data_valid;
    wire authentication_tag_valid;

    aes_gcm_decrypt bitstream_decrypt (
        .clk(clk),
        .reset_n(reset_n),
        .key(session_key),
        .iv(nonce_fpga),
        .ciphertext(rx_data),
        .ciphertext_valid(rx_valid && state == RECEIVE_ENCRYPTED_BITSTREAM),
        .plaintext(decrypted_data),
        .plaintext_valid(decrypted_data_valid),
        .tag_valid(authentication_tag_valid),
        .complete(aes_gcm_complete)
    );

    // SHA-384 hash calculation for bitstream verification
    wire hash_complete;
    wire [383:0] hash_result;

    sha384_hash hash_calculator (
        .clk(clk),
        .reset_n(reset_n),
        .data_in(decrypted_data),
        .data_valid(decrypted_data_valid),
        .hash_complete(hash_complete),
        .hash_result(hash_result)
    );

    // Signature verification for client authentication
    wire signature_verify_complete;
    wire signature_valid;

    signature_verify client_verify (
        .clk(clk),
        .reset_n(reset_n),
        .message(ecdhe_public_key),
        .signature(rx_data),
        .start(state == VERIFY_CLIENT_SIGNATURE),
        .complete(signature_verify_complete),
        .valid(signature_valid)
    );

    // State machine process
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state <= IDLE;
            tx_valid <= 1'b0;
            nvram_rd_en <= 1'b0;
            nvram_wr_en <= 1'b0;
            config_wr_en <= 1'b0;
        end else begin
            state <= next_state;

            case (state)
                IDLE: begin
                    tx_valid <= 1'b0;
                    nvram_rd_en <= 1'b0;
                    nvram_wr_en <= 1'b0;
                    config_wr_en <= 1'b0;
                end

                WAIT_FOR_KEYS: begin
                    // Wait for key management module to provide keys
                end

                WAIT_FOR_AUTH_REQUEST: begin
                    if (rx_valid) begin
                        message_type <= rx_data;
                        if (rx_data == MSG_AUTH_REQUEST) begin
                            bytes_received <= 4; // We've received the message type
                        end
                    end
                end

                GENERATE_ECDHE_KEYPAIR: begin
                    if (ecdhe_keygen_complete) begin
                        ecdhe_private_key <= generated_private_key;
                        ecdhe_public_key <= generated_public_key;

                        // Generate a random nonce
                        nonce_fpga <= 256'h1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF; // Random nonce (simplified)
                    end
                end

                SEND_CERTIFICATES: begin
                    // Send AIK certificate and ECDHE public key with signature
                    if (bytes_to_send == 0) begin
                        // Start sending message type
                        tx_data <= MSG_CERT_RESPONSE;
                        tx_valid <= 1'b1;
                        bytes_to_send <= 4 + 256 + 512 + 256 + 4096; // Message type + nonce + public key + signature + certificate
                    end else if (bytes_to_send > 4096) begin
                        // Send nonce, public key and signature
                        tx_data <= bytes_to_send[11:0] == 12'h001 ? nonce_fpga[31:0] :
                                  bytes_to_send[11:0] == 12'h002 ? nonce_fpga[63:32] :
                                  // ... more nonce words
                                  bytes_to_send[11:0] == 12'h009 ? ecdhe_public_key[31:0] :
                                  // ... more public key words
                                  32'h0; // Simplified: actual implementation would send all words
                        tx_valid <= 1'b1;
                        bytes_to_send <= bytes_to_send - 4;
                    end else begin
                        // Send AIK certificate
                        nvram_addr <= 32'h5000 + (4096 - bytes_to_send); // AIK_CERT_ADDR
                        nvram_rd_en <= 1'b1;

                        if (nvram_rd_valid) begin
                            tx_data <= nvram_rd_data;
                            tx_valid <= 1'b1;
                            bytes_to_send <= bytes_to_send - 4;
                        end else begin
                            tx_valid <= 1'b0;
                        end
                    end
                end

                WAIT_FOR_CLIENT_KEY: begin
                    if (rx_valid) begin
                        if (bytes_received == 4) begin
                            message_type <= rx_data;
                            bytes_received <= bytes_received + 4;
                        end else if (bytes_received < 4 + 256) begin
                            // Receive client nonce
                            nonce_client[(bytes_received-4)*8 +: 32] <= rx_data;
                            bytes_received <= bytes_received + 4;
                        end else if (bytes_received < 4 + 256 + 512) begin
                            // Receive client public key
                            client_public_key[(bytes_received-4-256)*8 +: 32] <= rx_data;
                            bytes_received <= bytes_received + 4;
                        end else begin
                            // Receive client signature (collected by signature verification module)
                            bytes_received <= bytes_received + 4;
                        end
                    end
                end

                VERIFY_CLIENT_SIGNATURE: begin
                    // Verification is handled by the signature_verify module
                end

                COMPUTE_SHARED_SECRET: begin
                    if (ecdhe_compute_complete) begin
                        shared_secret <= computed_shared_secret;
                    end

                    if (kdf_complete) begin
                        session_key <= derived_key;
                    end
                end

                RECEIVE_ENCRYPTED_BITSTREAM: begin
                    if (rx_valid) begin
                        if (bytes_received == 0) begin
                            message_type <= rx_data;
                            bytes_received <= 4;
                        end else if (bytes_received == 4) begin
                            bitstream_size <= rx_data;
                            bytes_received <= 8;
                        end else if (bytes_received == 8) begin
                            // First 32 bits of expected hash
                            received_hash[31:0] <= rx_data;
                            bytes_received <= 12;
                        end else if (bytes_received < 8 + 32) begin
                            // Rest of the expected hash (simplified - would be more words for SHA-384)
                            received_hash[(bytes_received-8)*8 +: 32] <= rx_data;
                            bytes_received <= bytes_received + 4;
                        end else begin
                            // Encrypted bitstream data processed by AES-GCM module
                            bytes_received <= bytes_received + 4;
                        end
                    end
                end

                DECRYPT_BITSTREAM: begin
                    // Decryption handled by AES-GCM module
                    // Configuration data is written to config memory as it's decrypted
                    if (decrypted_data_valid) begin
                        config_addr <= (bytes_received - 8 - 32 - 16) / 4; // Start after header, hash and IV
                        config_data <= decrypted_data;
                        config_wr_en <= 1'b1;
                    end else begin
                        config_wr_en <= 1'b0;
                    end
                end

                VERIFY_BITSTREAM_HASH: begin
                    // Hash verification
                    if (hash_complete) begin
                        // Compare the calculated hash with the received hash
                        // Simplified comparison - would need to compare full 384 bits
                        if (hash_result[255:0] == received_hash) begin
                            // Hash matched, bitstream is authentic
                        end else begin
                            // Hash mismatch, reject bitstream
                        end
                    end
                end

                CONFIGURE_FPGA: begin
                    // Send configuration complete message
                    tx_data <= MSG_AUTH_COMPLETE;
                    tx_valid <= 1'b1;
                end

                AUTHENTICATION_COMPLETE: begin
                    tx_valid <= 1'b0;
                end

                ERROR: begin
                    // Send error message
                    tx_data <= MSG_ERROR;
                    tx_valid <= 1'b1;
                end
            endcase
        end
    end

    // Next state logic
    always @(*) begin
        next_state = state;

        case (state)
            IDLE: begin
                if (agent_enable)
                    next_state = WAIT_FOR_KEYS;
            end

            WAIT_FOR_KEYS: begin
                if (ek_priv_valid && aik_valid && aik_cert_valid)
                    next_state = WAIT_FOR_AUTH_REQUEST;
            end

            WAIT_FOR_AUTH_REQUEST: begin
                if (rx_valid && rx_data == MSG_AUTH_REQUEST)
                    next_state = GENERATE_ECDHE_KEYPAIR;
            end

            GENERATE_ECDHE_KEYPAIR: begin
                if (ecdhe_keygen_complete)
                    next_state = SEND_CERTIFICATES;
            end

            SEND_CERTIFICATES: begin
                if (bytes_to_send == 0)
                    next_state = WAIT_FOR_CLIENT_KEY;
            end

            WAIT_FOR_CLIENT_KEY: begin
                if (message_type == MSG_CLIENT_KEY && bytes_received >= 4 + 256 + 512 + 256)
                    next_state = VERIFY_CLIENT_SIGNATURE;
            end

            VERIFY_CLIENT_SIGNATURE: begin
                if (signature_verify_complete) begin
                    if (signature_valid)
                        next_state = COMPUTE_SHARED_SECRET;
                    else
                        next_state = ERROR;
                end
            end

            COMPUTE_SHARED_SECRET: begin
                if (kdf_complete)
                    next_state = RECEIVE_ENCRYPTED_BITSTREAM;
            end

            RECEIVE_ENCRYPTED_BITSTREAM: begin
                if (message_type == MSG_ENCRYPTED_BITSTREAM && bytes_received >= 8 + 32 + 16 + bitstream_size)
                    next_state = DECRYPT_BITSTREAM;
            end

            DECRYPT_BITSTREAM: begin
                if (aes_gcm_complete) begin
                    if (authentication_tag_valid)
                        next_state = VERIFY_BITSTREAM_HASH;
                    else
                        next_state = ERROR;
                end
            end

            VERIFY_BITSTREAM_HASH: begin
                if (hash_complete) begin
                    if (hash_result[255:0] == received_hash)
                        next_state = CONFIGURE_FPGA;
                    else
                        next_state = ERROR;
                end
            end

            CONFIGURE_FPGA: begin
                next_state = AUTHENTICATION_COMPLETE;
            end

            AUTHENTICATION_COMPLETE: begin
                // Stay in this state until reset
            end

            ERROR: begin
                // Stay in this state until reset
            end
        endcase
    end

endmodule