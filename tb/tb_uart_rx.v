`timescale 1ns/1ps
// Testbench de uart_rx: inyecta tramas 8N1 y verifica el byte recibido.
module tb_uart_rx;

    localparam integer CLK_FREQ = 1_000_000;   // valores pequenos para sim rapida
    localparam integer BAUD     = 100_000;     // -> CLKS = 10
    localparam integer BIT_NS   = 1_000_000_000 / BAUD;  // 10000 ns/bit

    reg        clk = 0;
    reg        rst = 1;
    reg        rx  = 1;
    wire [7:0] o_data;
    wire       o_valid;

    integer errors = 0;

    uart_rx #(.CLK_FREQ(CLK_FREQ), .BAUD(BAUD)) dut (
        .clk(clk), .rst(rst), .rx(rx), .o_data(o_data), .o_valid(o_valid)
    );

    always #500 clk = ~clk;   // 1 MHz (periodo 1000 ns)

    // Envia un byte serie 8N1, LSB primero
    task send_byte(input [7:0] b);
        integer i;
        begin
            rx = 1'b0; #(BIT_NS);            // start
            for (i = 0; i < 8; i = i + 1) begin
                rx = b[i]; #(BIT_NS);        // datos LSB->MSB
            end
            rx = 1'b1; #(BIT_NS);            // stop
        end
    endtask

    // Espera o_valid y compara
    task expect_byte(input [7:0] b);
        begin
            @(posedge o_valid);
            #1;
            if (o_data === b)
                $display("  OK   recibido 0x%02h", o_data);
            else begin
                $display("  FAIL esperaba 0x%02h, recibido 0x%02h", b, o_data);
                errors = errors + 1;
            end
        end
    endtask

    // Disparador y comprobador en paralelo
    reg [7:0] test_vec [0:3];
    integer n;

    initial begin
        test_vec[0] = 8'h41;  // 'A'
        test_vec[1] = 8'h55;  // patron alternado
        test_vec[2] = 8'h7E;  // '~'
        test_vec[3] = 8'h00;  // todos ceros

        repeat (5) @(posedge clk);
        rst = 1'b0;
        repeat (5) @(posedge clk);

        for (n = 0; n < 4; n = n + 1) begin
            fork
                send_byte(test_vec[n]);
                expect_byte(test_vec[n]);
            join
            #(BIT_NS);  // separacion entre tramas
        end

        if (errors == 0) $display("tb_uart_rx: TODOS OK");
        else             $display("tb_uart_rx: %0d ERRORES", errors);
        $finish;
    end

    initial begin
        $dumpfile("build/wave.vcd");
        $dumpvars(0, tb_uart_rx);
        #5_000_000 $display("TIMEOUT"); $finish;
    end

endmodule
