`timescale 1ns / 1ps

// -----------------------------------------------------------------------------
// Testbench: Mid-Side Inverse Core
// -----------------------------------------------------------------------------
// Purpose:
//    - Functional verification of mid_side_inverse
//    - Validate bypass, reconstruction, and saturation behavior
//    - Capture results in CSV for offline analysis
//
// Assumptions:
//    - Fixed 1-cycle latency
//    - ce is held high
// -----------------------------------------------------------------------------

module tb_mid_side_inverse;

    // -------------------------------------------------------------------------
    // DUT Interface
    // -------------------------------------------------------------------------
    reg         clk;
    reg         ce;
    reg         enable;
    reg  signed [15:0] mid;
    reg  signed [15:0] side;

    wire signed [15:0] L;
    wire signed [15:0] R;

    // CSV file handle
    integer f;

    // -------------------------------------------------------------------------
    // DUT Instantiation
    // -------------------------------------------------------------------------
    mid_side_inverse dut (
        .clk   (clk),
        .ce    (ce),
        .enable(enable),
        .mid   (mid),
        .side  (side),
        .L     (L),
        .R     (R)
    );

    // -------------------------------------------------------------------------
    // Clock generation (100 MHz)
    // -------------------------------------------------------------------------
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // -------------------------------------------------------------------------
    // Apply one test vector
    // -------------------------------------------------------------------------
    task apply_vector;
        input signed [15:0] in_mid;
        input signed [15:0] in_side;
        input               en;
    begin
        mid    <= in_mid;
        side   <= in_side;
        enable <= en;

        // Wait exactly one pipeline latency
        @(posedge clk);
        #1;

        // Log result
        $fwrite(
            f,
            "%0d,%0d,%0d,%0d,%0d,%0d\n",
            $time, enable, $signed(in_mid), $signed(in_side), $signed(L), $signed(R)
        );
    end
    endtask

    // -------------------------------------------------------------------------
    // Test sequence
    // -------------------------------------------------------------------------
    initial begin
        // Open CSV file
        f = $fopen("tb_mid_side_inverse.csv", "w");
        $fwrite(f, "Time,Enable,In_Mid,In_Side,Out_L,Out_R\n");

        // Initial conditions
        ce     = 1'b1;
        enable = 1'b0;
        mid    = 16'sd0;
        side   = 16'sd0;

        #20;
        $display("=== Mid/Side Inverse Core Test Start ===");

        // ---------------------------------------------------------------------
        // Test Case 1: Bypass mode
        // Expect: L = mid, R = side
        // ---------------------------------------------------------------------
        apply_vector(16'sd1234, 16'sd5678, 1'b0);

        // ---------------------------------------------------------------------
        // Test Case 2: Normal reconstruction (no saturation)
        // L = mid + side
        // R = mid - side
        // ---------------------------------------------------------------------
        apply_vector(16'sd1000, 16'sd500, 1'b1);  // L=1500, R=500
        apply_vector(-16'sd100, -16'sd50, 1'b1);  // L=-150, R=-50

        // ---------------------------------------------------------------------
        // Test Case 3: Saturation behavior
        // ---------------------------------------------------------------------
        // Positive overflow on L
        apply_vector(16'sd20000, 16'sd15000, 1'b1); // L->32767, R=5000

        // Negative overflow on L
        apply_vector(-16'sd20000, -16'sd20000, 1'b1); // L->-32768, R=0

        // Positive overflow on R
        apply_vector(16'sd20000, -16'sd20000, 1'b1); // L=0, R->32767

        #20;
        $fclose(f);

        $display("=== Test Done. Results written to tb_mid_side_inverse.csv ===");
        $finish;
    end

endmodule
