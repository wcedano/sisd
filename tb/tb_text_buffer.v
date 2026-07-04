`timescale 1ns/1ps
// Testbench de text_buffer: protocolo de escritura, longitudes y lectura.
module tb_text_buffer;

    localparam integer LINE_MAX = 40;

    reg        clk = 0;
    reg        rst = 1;
    reg  [7:0] i_data = 0;
    reg        i_valid = 0;
    reg  [6:0] i_rd_addr = 0;
    wire [7:0] o_rd_data;
    wire [6:0] o_len1;
    wire [6:0] o_len2;

    integer errors = 0;

    text_buffer #(.LINE_MAX(LINE_MAX)) dut (
        .clk(clk), .rst(rst),
        .i_data(i_data), .i_valid(i_valid),
        .i_rd_addr(i_rd_addr), .o_rd_data(o_rd_data),
        .o_len1(o_len1), .o_len2(o_len2)
    );

    always #5 clk = ~clk;

    task write_byte(input [7:0] b);
        begin
            @(negedge clk); i_data = b; i_valid = 1'b1;
            @(negedge clk); i_valid = 1'b0;
        end
    endtask

    task check_len(input [6:0] got, input [6:0] exp, input [127:0] name);
        begin
            if (got === exp) $display("  OK   %0s = %0d", name, got);
            else begin
                $display("  FAIL %0s esperaba %0d, obtuvo %0d", name, exp, got);
                errors = errors + 1;
            end
        end
    endtask

    task check_char(input [6:0] addr, input [7:0] exp);
        begin
            i_rd_addr = addr; #1;
            if (o_rd_data === exp)
                $display("  OK   vram[%0d] = '%c' (0x%02h)", addr, o_rd_data, o_rd_data);
            else begin
                $display("  FAIL vram[%0d] esperaba 0x%02h, obtuvo 0x%02h", addr, exp, o_rd_data);
                errors = errors + 1;
            end
        end
    endtask

    integer i;

    initial begin
        repeat (3) @(negedge clk);
        rst = 1'b0;
        @(negedge clk);

        $display("-- Estado por defecto --");
        check_len(o_len1, 7'd12, "len1");
        check_len(o_len2, 7'd16, "len2");

        $display("-- Clear (0x0C) --");
        write_byte(8'h0C);
        check_len(o_len1, 7'd0, "len1");
        check_len(o_len2, 7'd0, "len2");

        $display("-- Escribir \"Hi\" en linea 1 --");
        write_byte("H");
        write_byte("i");
        check_len(o_len1, 7'd2, "len1");
        check_char(7'd0, "H");
        check_char(7'd1, "i");
        check_char(7'd2, 8'h20);   // relleno con espacio mas alla de len

        $display("-- Newline + linea 2 larga (scroll) --");
        write_byte(8'h0A);
        check_len(o_len2, 7'd0, "len2");
        for (i = 0; i < 19; i = i + 1)
            write_byte("A" + i[7:0]);   // 'A'..'S' = 19 chars
        check_len(o_len2, 7'd19, "len2");
        check_char(LINE_MAX + 0, "A");
        check_char(LINE_MAX + 18, "S");
        if (o_len2 > 16) $display("  OK   linea 2 requiere scroll (len2=%0d>16)", o_len2);
        else begin $display("  FAIL linea 2 deberia requerir scroll"); errors = errors + 1; end

        if (errors == 0) $display("tb_text_buffer: TODOS OK");
        else             $display("tb_text_buffer: %0d ERRORES", errors);
        $finish;
    end

    initial begin
        $dumpfile("build/wave.vcd");
        $dumpvars(0, tb_text_buffer);
        #200000; $display("TIMEOUT"); $finish;
    end

endmodule
