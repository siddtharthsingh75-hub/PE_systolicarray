`timescale 1ns/1ps

module tb_pe_1;

    parameter WIDTH      = 8;
    parameter ACC_WIDTH  = 20;
    parameter CLK_PERIOD = 10;

    reg                         clk;
    reg                         rst;
    reg                         weight_load;
    reg  signed [WIDTH-1:0]     weight_in;
    reg  signed [WIDTH-1:0]     act_in;
    reg  signed [ACC_WIDTH-1:0] acc_in;

    wire signed [WIDTH-1:0]     act_out;
    wire signed [ACC_WIDTH-1:0] acc_out;

    integer errors = 0;

    pe_1 #(
        .WIDTH(WIDTH),
        .ACC_WIDTH(ACC_WIDTH)
    ) dut (
        .clk(clk), .rst(rst),
        .weight_load(weight_load), .weight_in(weight_in),
        .act_in(act_in), .act_out(act_out),
        .acc_in(acc_in), .acc_out(acc_out)
    );

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    localparam signed [ACC_WIDTH-1:0] ACC_MAX = {1'b0, {(ACC_WIDTH-1){1'b1}}};
    localparam signed [ACC_WIDTH-1:0] ACC_MIN = {1'b1, {(ACC_WIDTH-1){1'b0}}};

    // All stimulus changes happen on negedge -> no race with DUT's posedge sampling
    task drive(input wl, input signed [WIDTH-1:0] w, input signed [WIDTH-1:0] a,
               input signed [ACC_WIDTH-1:0] ac);
        begin
            @(negedge clk);
            weight_load = wl;
            weight_in   = w;
            act_in      = a;
            acc_in      = ac;
        end
    endtask

    // Check acc_out at the following posedge (result of the MAC issued by the last drive())
    task check_acc(input signed [ACC_WIDTH-1:0] expected, input [255:0] tag);
        begin
            @(posedge clk); #1;
            if (acc_out !== expected) begin
                errors = errors + 1;
                $display("[FAIL] %0s : acc_out = %0d, expected = %0d @ t=%0t", tag, acc_out, expected, $time);
            end else begin
                $display("[PASS] %0s : acc_out = %0d @ t=%0t", tag, acc_out, $time);
            end
        end
    endtask

    initial begin
        // ---------------- Reset ----------------
        rst = 1; weight_load = 0; weight_in = 0; act_in = 0; acc_in = 0;
        @(negedge clk); @(negedge clk);
        rst = 0;
        #1;
        if (dut.act_out !== 0 || dut.acc_out !== 0) begin
            errors = errors + 1;
            $display("[FAIL] reset : act_out=%0d acc_out=%0d, expected 0/0", dut.act_out, dut.acc_out);
        end else $display("[PASS] reset : outputs cleared");

        // ---------------- T1: load weight = 5, then single MAC ----------------
        drive(1, 5, 0, 0);      // load weight on this cycle's posedge
        drive(0, 5, 3, 0);      // weight=5 now held; act_in=3, acc_in=0 -> expect 5*3+0=15
        check_acc(15, "T1 single MAC (5*3+0)");

        // ---------------- T2: accumulate across cycles, weight stays 5 (proves it's stationary) ----------------
        drive(0, 5, 2, 15);     // 5*2+15 = 25
        check_acc(25, "T2a accumulate (5*2+15)");

        drive(0, 5, -4, 25);    // 5*-4+25 = 5
        check_acc(5, "T2b accumulate w/ negative act_in (5*-4+25)");

        // ---------------- T3: act_out passthrough ----------------
        drive(0, 5, 9, 5);
        @(posedge clk); #1;
        if (act_out !== 9) begin
            errors = errors + 1;
            $display("[FAIL] T3 act_out passthrough : got %0d, expected 9", act_out);
        end else $display("[PASS] T3 act_out passthrough : act_out = 9");

        // ---------------- T4: reload weight mid-stream ----------------
        drive(1, -10, 1, 0);    // load weight=-10
        drive(0, -10, 2, 0);    // -10*2+0 = -20
        check_acc(-20, "T4 MAC after weight reload (-10*2+0)");

        // ---------------- T5: POSITIVE overflow -> saturate to ACC_MAX ----------------
        drive(1, 127, 0, 0);            // load weight=127 (max INT8)
        drive(0, 127, 127, ACC_MAX-100); // 127*127=16129, acc_in near max -> overflows
        check_acc(ACC_MAX, "T5 POSITIVE OVERFLOW -> clamp to ACC_MAX");

        // ---------------- T6: NEGATIVE overflow -> saturate to ACC_MIN ----------------
        drive(1, -128, 0, 0);            // load weight=-128 (min INT8)
        drive(0, -128, 127, ACC_MIN+100);// -128*127=-16256, acc_in near min -> overflows below
        check_acc(ACC_MIN, "T6 NEGATIVE OVERFLOW -> clamp to ACC_MIN");

        if (errors == 0) $display("\n*** ALL TESTS PASSED ***\n");
        else $display("\n*** %0d TEST(S) FAILED ***\n", errors);

        $finish;
    end

    initial begin
        $dumpfile("tb_pe_1.vcd");
        $dumpvars(0, tb_pe_1);
    end

endmodule
