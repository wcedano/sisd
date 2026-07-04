`timescale 1ns/1ps

module tb_traffic_pack;
    reg  [7:0] pkt;
    wire [3:0] fine;
    wire [1:0] category;
    wire       alarm;
    wire       parity;

    traffic_pack dut (
        .pkt(pkt),
        .fine(fine),
        .category(category),
        .alarm(alarm),
        .parity(parity)
    );

    task expect;
        input [7:0] t_pkt;
        input [3:0] t_fine;
        input [1:0] t_cat;
        input       t_alarm;
        input       t_parity;
        begin
            pkt = t_pkt;
            #1;
            if (fine !== t_fine) begin
                $display("FAIL pkt=%b fine got=%0d exp=%0d", t_pkt, fine, t_fine);
                $fatal(1);
            end
            if (category !== t_cat) begin
                $display("FAIL pkt=%b category got=%b exp=%b", t_pkt, category, t_cat);
                $fatal(1);
            end
            if (alarm !== t_alarm) begin
                $display("FAIL pkt=%b alarm got=%b exp=%b", t_pkt, alarm, t_alarm);
                $fatal(1);
            end
            if (parity !== t_parity) begin
                $display("FAIL pkt=%b parity got=%b exp=%b", t_pkt, parity, t_parity);
                $fatal(1);
            end
        end
    endtask

    initial begin
        // Minimum cases from the statement:
        expect(8'b000_00_00_0, 4'd0, 2'b11, 1'b0, 1'b1); // invalid => fine=0, HOLD, alarm=0, parity even
        expect(8'b001_01_01_1, 4'd4, 2'b01, 1'b1, 1'b0); // base=2, factor=2 => fine=4
        expect(8'b111_11_10_1, 4'd15, 2'b10, 1'b1, 1'b1); // saturates to 15, bonus keeps 15
        expect(8'b010_10_11_1, 4'd0, 2'b11, 1'b0, 1'b1); // type=11 => HOLD, fine=0, alarm=0

        // Additional coverage:
        expect(8'b000_00_00_1, 4'd0, 2'b00, 1'b0, 1'b1); // valid, OK case
        expect(8'b111_00_00_1, 4'd9, 2'b10, 1'b1, 1'b0); // base=7,factor=1 => 7 + bonus(2)=9

        $display("All tests passed.");
        $finish;
    end
endmodule

