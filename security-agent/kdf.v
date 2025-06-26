module kdf (
    input wire clk,
    input wire reset_n,
    input wire [255:0] shared_secret,
    input wire [255:0] nonce_fpga,
    input wire [255:0] nonce_client,
    input wire start,
    output reg [383:0] session_key, //changed to 384 bits as we have sha384
    output reg complete
);
    reg [767:0] msg; //stores entire message to be hashed {shared_secret, nonce_fpga, nonce_client}
    reg [9:0] byte_idx; //tracks which byte of message is sent to sha384 module
    reg busy;
    reg counter;
    reg data_valid;
    reg [31:0] data_in;
    wire hash_complete; 
    wire [383:0] hash_result;
   
    
    sha384_hash sha_inst (
    .clk(clk),
    .reset_n(reset_n),
  .data_in(data_in),          // 32-bit word input
  .data_valid(data_valid),      // valid signal
  .hash_complete(hash_complete),
  .hash_result(hash_result)        // output digest
);

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            msg <= 768'd0;
            byte_idx <= 0;
            busy <= 1'b0;
            data_valid <= 1'b0;
            data_in <= 32'd0;
            complete <= 1'b0;
            session_key <= 384'd0;
        end else begin
            if (start && !busy && !complete) begin
                msg <= {shared_secret, nonce_fpga, nonce_client};
                byte_idx <= 0;
                busy <= 1'b1;
                complete <= 1'b0;
            end else if (busy) begin
                data_in <= msg [767 -counter*32 -: 32];
                data_valid <= 1'b1;
                if (counter == 8'd23) begin
                    busy <= 1'b0;
                end else begin
                    counter <= counter + 8'd1;
                end
                end else begin
                    //Implementing this logic with sha384 that we have to give more security onstead of this XOR
                    // In a real implementation, this would apply a proper KDF
                    // For simplicity, we just combine the inputs as a dummy operation
                    //session_key <= shared_secret ^ nonce_fpga ^ nonce_client;
                    //busy <= 1'b0;
                    data_valid <= 1'b0;
                end
            if (hash_complete && !complete) begin
                session_key <= hash_result;
                complete <= 1'b1;
                end
            end
    end
endmodule
