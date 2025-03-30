module aes_gcm_decrypt (
    input wire clk,
    input wire reset_n,
    input wire [255:0] key,
    input wire [255:0] iv,
    input wire [31:0] ciphertext,
    input wire ciphertext_valid,
    output reg [31:0] plaintext,
    output reg plaintext_valid,
    output reg tag_valid,
    output reg complete
);
    reg [31:0] counter;
    reg [31:0] data_count;
    reg busy;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            counter <= 32'd0;
            data_count <= 32'd0;
            busy <= 1'b0;
            complete <= 1'b0;
            plaintext <= 32'd0;
            plaintext_valid <= 1'b0;
            tag_valid <= 1'b0;
        end else begin
            plaintext_valid <= 1'b0;

            if (ciphertext_valid && !busy) begin
                busy <= 1'b1;
                data_count <= 32'd1;
                counter <= 32'd0;
                complete <= 1'b0;
            end else if (ciphertext_valid && busy) begin
                data_count <= data_count + 32'd1;

                // In a real implementation, this would decrypt using AES-GCM
                // For simplicity, we just XOR with a derived key byte
                plaintext <= ciphertext ^ key[31:0] ^ iv[31:0] ^ data_count;
                plaintext_valid <= 1'b1;
            end else if (busy && !ciphertext_valid && counter < 32'd100) begin
                counter <= counter + 32'd1;
            end else if (busy && counter >= 32'd100) begin
                tag_valid <= 1'b1;  // Simplified - would verify authentication tag
                complete <= 1'b1;
                busy <= 1'b0;
            end
        end
    end
endmodule