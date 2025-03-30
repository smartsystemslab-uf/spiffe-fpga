module civic_fpga_tb;
    // Testbench signals
    reg clk;
    reg reset_n;

    // External interface signals
    reg [31:0] rx_data;
    reg rx_valid;
    wire [31:0] tx_data;
    wire tx_valid;

    // NVRAM signals
    wire [31:0] nvram_rd_addr;
    wire nvram_rd_en;
    reg [31:0] nvram_rd_data;
    reg nvram_rd_valid;
    wire [31:0] nvram_wr_addr;
    wire nvram_wr_en;
    wire [31:0] nvram_wr_data;

    // eFUSE signals
    reg efuse_key_ready;
    reg [255:0] efuse_key;

    // Configuration signals
    wire [31:0] config_addr;
    wire config_wr_en;
    wire [31:0] config_data;

    // Status signals
    wire boot_complete;
    wire boot_authentic;
    wire root_of_trust_established;

    // Instantiate the top module
    civic_fpga_top dut (
        .clk(clk),
        .reset_n(reset_n),
        .rx_data(rx_data),
        .rx_valid(rx_valid),
        .tx_data(tx_data),
        .tx_valid(tx_valid),
        .nvram_rd_addr(nvram_rd_addr),
        .nvram_rd_en(nvram_rd_en),
        .nvram_rd_data(nvram_rd_data),
        .nvram_rd_valid(nvram_rd_valid),
        .nvram_wr_addr(nvram_wr_addr),
        .nvram_wr_en(nvram_wr_en),
        .nvram_wr_data(nvram_wr_data),
        .efuse_key_ready(efuse_key_ready),
        .efuse_key(efuse_key),
        .config_addr(config_addr),
        .config_wr_en(config_wr_en),
        .config_data(config_data),
        .boot_complete(boot_complete),
        .boot_authentic(boot_authentic),
        .root_of_trust_established(root_of_trust_established)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // NVRAM simulation - simplified memory model
    reg [31:0] nvram [0:16383]; // 64KB NVRAM

    // NVRAM read response
    always @(posedge clk) begin
        if (reset_n && nvram_rd_en) begin
            nvram_rd_data <= nvram[nvram_rd_addr[13:2]]; // Word-aligned addressing
            nvram_rd_valid <= 1'b1;
        end else begin
            nvram_rd_valid <= 1'b0;
        end
    end

    // NVRAM write
    always @(posedge clk) begin
        if (reset_n && nvram_wr_en) begin
            nvram[nvram_wr_addr[13:2]] <= nvram_wr_data; // Word-aligned addressing
        end
    end

    // Test sequence
    initial begin
        // Initialize signals
        reset_n = 0;
        rx_data = 0;
        rx_valid = 0;
        efuse_key_ready = 0;
        efuse_key = 0;

        // Initialize NVRAM with some test data
        // EK private key (encrypted)
        nvram[32'h00001000 >> 2] = 32'hDEADBEEF;
        // More EK private key data would be initialized here

        // EK public key
        nvram[32'h00002000 >> 2] = 32'h01000100;
        // More EK public key data would be initialized here

        // EK certificate
        nvram[32'h00003000 >> 2] = 32'hCERT0001;
        // More EK certificate data would be initialized here

        // Release reset
        #100;
        reset_n = 1;

        // Provide eFUSE key
        #50;
        efuse_key = 256'hABCDEF1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF1234567890;
        efuse_key_ready = 1;

        // Wait for boot to complete and root of trust to establish
        wait(root_of_trust_established);
        $display("Root of Trust established!");

        // Simulate tenant authentication request
        #100;
        rx_data = 32'h00000001; // MSG_AUTH_REQUEST
        rx_valid = 1;
        #10;
        rx_valid = 0;

        // Wait for certificate response
        wait(tx_valid && tx_data == 32'h00000002); // MSG_CERT_RESPONSE
        $display("Certificate response received!");

        // Simulate more of the protocol - sending client ECDHE key, etc.
        // This would be a more elaborate sequence in a real test

        // End simulation
        #1000;
        $finish;
    end

    // Monitor important signals
    initial begin
        $monitor("Time=%0t, Boot Complete=%b, Boot Authentic=%b, RoT Established=%b",
                 $time, boot_complete, boot_authentic, root_of_trust_established);
    end

endmodule