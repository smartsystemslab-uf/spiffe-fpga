module civic_fpga_top (
    input wire clk,
    input wire reset_n,

    // External interfaces
    input wire [31:0] rx_data,
    input wire rx_valid,
    output wire [31:0] tx_data,
    output wire tx_valid,

    // NVRAM interface
    output wire [31:0] nvram_rd_addr,
    output wire nvram_rd_en,
    input wire [31:0] nvram_rd_data,
    input wire nvram_rd_valid,
    output wire [31:0] nvram_wr_addr,
    output wire nvram_wr_en,
    output wire [31:0] nvram_wr_data,

    // eFUSE interface
    input wire efuse_key_ready,
    input wire [255:0] efuse_key,

    // Configuration interface
    output wire [31:0] config_addr,
    output wire config_wr_en,
    output wire [31:0] config_data,

    // Status outputs
    output wire boot_complete,
    output wire boot_authentic,
    output wire root_of_trust_established
);

    // Internal signals for connecting modules
    wire firmware_load_complete;
    wire firmware_authentic;
    wire [31:0] firmware_addr_req;
    wire firmware_req_valid;
    wire sec_agent_enable;

    wire [2047:0] ek_priv_decrypted;
    wire ek_priv_valid;
    wire [2047:0] aik_pub;
    wire [2047:0] aik_priv;
    wire aik_valid;
    wire [4095:0] aik_cert;
    wire aik_cert_valid;

    // NVRAM arbitration - multiple modules may need access
    wire [31:0] bootloader_nvram_rd_addr;
    wire bootloader_nvram_rd_en;
    wire [31:0] key_mgmt_nvram_rd_addr;
    wire key_mgmt_nvram_rd_en;
    wire [31:0] key_mgmt_nvram_wr_addr;
    wire key_mgmt_nvram_wr_en;
    wire [31:0] key_mgmt_nvram_wr_data;
    wire [31:0] sec_agent_nvram_addr;
    wire sec_agent_nvram_rd_en;
    wire sec_agent_nvram_wr_en;
    wire [31:0] sec_agent_nvram_wr_data;

    // Simple NVRAM access arbitration
    assign nvram_rd_addr = sec_agent_nvram_rd_en ? sec_agent_nvram_addr :
                          key_mgmt_nvram_rd_en ? key_mgmt_nvram_rd_addr :
                          bootloader_nvram_rd_en ? bootloader_nvram_rd_addr :
                          32'h0;

    assign nvram_rd_en = sec_agent_nvram_rd_en | key_mgmt_nvram_rd_en | bootloader_nvram_rd_en;

    assign nvram_wr_addr = sec_agent_nvram_wr_en ? sec_agent_nvram_addr :
                          key_mgmt_nvram_wr_en ? key_mgmt_nvram_wr_addr :
                          32'h0;

    assign nvram_wr_en = sec_agent_nvram_wr_en | key_mgmt_nvram_wr_en;

    assign nvram_wr_data = sec_agent_nvram_wr_en ? sec_agent_nvram_wr_data :
                          key_mgmt_nvram_wr_en ? key_mgmt_nvram_wr_data :
                          32'h0;

    // Status outputs
    assign boot_complete = firmware_load_complete;
    assign boot_authentic = firmware_authentic;
    assign root_of_trust_established = firmware_authentic && aik_valid && aik_cert_valid;

    // Instance of hardware bootloader
    hardware_bootloader bootloader (
        .clk(clk),
        .reset_n(reset_n),
        .signature(256'h0), // Would be loaded from flash memory in real implementation
        .signature_valid(1'b1), // Simplified - would validate signature from flash
        .firmware_addr(firmware_addr_req),
        .firmware_data(nvram_rd_data),
        .firmware_data_valid(nvram_rd_valid && bootloader_nvram_rd_en),
        .firmware_load_complete(firmware_load_complete),
        .firmware_authentic(firmware_authentic),
        .firmware_addr_req(bootloader_nvram_rd_addr),
        .firmware_req_valid(bootloader_nvram_rd_en),
        .sec_agent_enable(sec_agent_enable)
    );

    // Instance of key management system
    key_management_system key_mgmt (
        .clk(clk),
        .reset_n(reset_n),
        .boot_complete(firmware_load_complete),
        .boot_authentic(firmware_authentic),
        .efuse_key_ready(efuse_key_ready),
        .efuse_key(efuse_key),
        .nvram_rd_addr(key_mgmt_nvram_rd_addr),
        .nvram_rd_en(key_mgmt_nvram_rd_en),
        .nvram_rd_data(nvram_rd_data),
        .nvram_rd_valid(nvram_rd_valid && key_mgmt_nvram_rd_en),
        .nvram_wr_addr(key_mgmt_nvram_wr_addr),
        .nvram_wr_en(key_mgmt_nvram_wr_en),
        .nvram_wr_data(key_mgmt_nvram_wr_data),
        .ek_priv_decrypted(ek_priv_decrypted),
        .ek_priv_valid(ek_priv_valid),
        .aik_pub(aik_pub),
        .aik_priv(aik_priv),
        .aik_valid(aik_valid),
        .aik_cert(aik_cert),
        .aik_cert_valid(aik_cert_valid)
    );

    // Instance of security agent
    security_agent sec_agent (
        .clk(clk),
        .reset_n(reset_n),
        .agent_enable(sec_agent_enable),
        .ek_priv(ek_priv_decrypted),
        .ek_priv_valid(ek_priv_valid),
        .aik_pub(aik_pub),
        .aik_priv(aik_priv),
        .aik_valid(aik_valid),
        .aik_cert(aik_cert),
        .aik_cert_valid(aik_cert_valid),
        .rx_data(rx_data),
        .rx_valid(rx_valid),
        .tx_data(tx_data),
        .tx_valid(tx_valid),
        .nvram_addr(sec_agent_nvram_addr),
        .nvram_rd_en(sec_agent_nvram_rd_en),
        .nvram_rd_data(nvram_rd_data),
        .nvram_rd_valid(nvram_rd_valid && sec_agent_nvram_rd_en),
        .nvram_wr_en(sec_agent_nvram_wr_en),
        .nvram_wr_data(sec_agent_nvram_wr_data),
        .config_addr(config_addr),
        .config_wr_en(config_wr_en),
        .config_data(config_data)
    );

endmodule