`timescale 1ns / 1ps

// -----------------------------------------------------------------------------
// Testbench: AXI-Stream Mid-Side Wrapper
// -----------------------------------------------------------------------------
// Purpose:
//    - Validate AXI-Stream + AXI-Lite integration
//    - Verify bypass, encode, and decode modes
//    - Ensure timing alignment across fixed 2-cycle pipeline
//    - Log I/O behavior to CSV for offline inspection
//
// Assumptions:
//    - Fixed latency = 2 cycles
//    - m_axis_tready held high
// -----------------------------------------------------------------------------

module tb_midside_axis_wrapper;

    // -------------------------------------------------------------------------
    // Clock & Reset
    // -------------------------------------------------------------------------
    reg aclk;
    reg aresetn;

    initial aclk = 1'b0;
    always #5 aclk = ~aclk; // 100 MHz

    // -------------------------------------------------------------------------
    // AXI-Lite Signals
    // -------------------------------------------------------------------------
    reg  [3:0]  s_axi_awaddr;
    reg  [2:0]  s_axi_awprot;
    reg         s_axi_awvalid;
    wire        s_axi_awready;

    reg  [31:0] s_axi_wdata;
    reg  [3:0]  s_axi_wstrb;
    reg         s_axi_wvalid;
    wire        s_axi_wready;

    wire [1:0]  s_axi_bresp;
    wire        s_axi_bvalid;
    reg         s_axi_bready;

    reg  [3:0]  s_axi_araddr;
    reg  [2:0]  s_axi_arprot;
    reg         s_axi_arvalid;
    wire        s_axi_arready;

    wire [31:0] s_axi_rdata;
    wire [1:0]  s_axi_rresp;
    wire        s_axi_rvalid;
    reg         s_axi_rready;

    // -------------------------------------------------------------------------
    // AXI-Stream Signals
    // -------------------------------------------------------------------------
    reg  [31:0] s_axis_tdata;
    reg         s_axis_tvalid;
    wire        s_axis_tready;

    wire [31:0] m_axis_tdata;
    wire        m_axis_tvalid;
    wire        m_axis_tlast;

    // -------------------------------------------------------------------------
    // CSV Logging
    // -------------------------------------------------------------------------
    integer f_csv;
    integer current_mode_log;

    // Input delay pipeline (align with 2-cycle DUT latency)
    reg signed [15:0] in_L_d1, in_L_d2;
    reg signed [15:0] in_R_d1, in_R_d2;

    // -------------------------------------------------------------------------
    // DUT Instantiation
    // -------------------------------------------------------------------------
    midside_axis_wrapper dut (
        .aclk(aclk),
        .aresetn(aresetn),

        // AXI-Lite
        .s_axi_awaddr (s_axi_awaddr),
        .s_axi_awprot (s_axi_awprot),
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),

        .s_axi_wdata (s_axi_wdata),
        .s_axi_wstrb (s_axi_wstrb),
        .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready),

        .s_axi_bresp (s_axi_bresp),
        .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(s_axi_bready),

        .s_axi_araddr (s_axi_araddr),
        .s_axi_arprot (s_axi_arprot),
        .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),

        .s_axi_rdata (s_axi_rdata),
        .s_axi_rresp (s_axi_rresp),
        .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready),

        // AXI-Stream
        .s_axis_tdata (s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tlast (1'b0),

        .m_axis_tdata (m_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(1'b1),
        .m_axis_tlast (m_axis_tlast)
    );

    // -------------------------------------------------------------------------
    // CSV Setup
    // -------------------------------------------------------------------------
    initial begin
        f_csv = $fopen("tb_midside_axis.csv", "w");
        $fwrite(f_csv, "Time_ns,Mode,In_L,In_R,Out_L,Out_R\n");
    end

    // -------------------------------------------------------------------------
    // Input Delay Pipeline (2 cycles)
    // -------------------------------------------------------------------------
    always @(posedge aclk) begin
        if (aresetn) begin
            if (s_axis_tready && s_axis_tvalid) begin
                in_L_d1 <= s_axis_tdata[31:16];
                in_R_d1 <= s_axis_tdata[15:0];
                in_L_d2 <= in_L_d1;
                in_R_d2 <= in_R_d1;
            end else if (m_axis_tvalid) begin
                // Drain remaining pipeline data
                in_L_d2 <= in_L_d1;
                in_R_d2 <= in_R_d1;
            end
        end else begin
            in_L_d1 <= 16'sd0;
            in_L_d2 <= 16'sd0;
            in_R_d1 <= 16'sd0;
            in_R_d2 <= 16'sd0;
        end
    end

    // -------------------------------------------------------------------------
    // CSV Logging on Output Valid
    // -------------------------------------------------------------------------
    always @(posedge aclk) begin
        if (aresetn && m_axis_tvalid) begin
            $fwrite(
                f_csv,
                "%0d,%0d,%0d,%0d,%0d,%0d\n",
                $time,
                current_mode_log,
                $signed(in_L_d2),
                $signed(in_R_d2),
                $signed(m_axis_tdata[31:16]),
                $signed(m_axis_tdata[15:0])
            );
        end
    end

    // -------------------------------------------------------------------------
    // AXI-Lite Write Task
    // -------------------------------------------------------------------------
    task write_reg;
        input [3:0]  addr;
        input [31:0] data;
    begin
        @(posedge aclk);
        s_axi_awaddr  <= addr;
        s_axi_awvalid <= 1'b1;
        s_axi_wdata   <= data;
        s_axi_wvalid  <= 1'b1;
        s_axi_bready  <= 1'b1;

        wait (s_axi_awready && s_axi_wready);
        @(posedge aclk);

        s_axi_awvalid <= 1'b0;
        s_axi_wvalid  <= 1'b0;

        wait (s_axi_bvalid);
        @(posedge aclk);
        s_axi_bready <= 1'b0;

        #20;
    end
    endtask

    // -------------------------------------------------------------------------
    // Send one stereo sample
    // -------------------------------------------------------------------------
    task send_audio;
        input signed [15:0] left;
        input signed [15:0] right;
    begin
        @(posedge aclk);
        wait (s_axis_tready);
        s_axis_tdata  <= {left, right};
        s_axis_tvalid <= 1'b1;

        @(posedge aclk);
        s_axis_tvalid <= 1'b0;

        #20;
    end
    endtask

    // -------------------------------------------------------------------------
    // Main Stimulus
    // -------------------------------------------------------------------------
    initial begin
        // Init signals
        aresetn       = 1'b0;
        s_axis_tvalid = 1'b0;
        s_axis_tdata  = 32'd0;
        
        s_axi_awaddr  = 4'd0;
        s_axi_awprot  = 3'b000;
        s_axi_awvalid = 1'b0;
        s_axi_wdata   = 32'd0;
        s_axi_wstrb   = 4'b1111;
        s_axi_wvalid  = 1'b0;
        s_axi_bready  = 1'b0;
        
        s_axi_araddr  = 4'd0;
        s_axi_arprot  = 3'b000;
        s_axi_arvalid = 1'b0;
        s_axi_rready  = 1'b0;

        in_L_d1 = 16'sd0; in_L_d2 = 16'sd0;
        in_R_d1 = 16'sd0; in_R_d2 = 16'sd0;

        current_mode_log = 0;

        #100;
        aresetn = 1'b1;
        #100;

        // ---------------------------------------------------------------------
        // Mode 0: Bypass
        // ---------------------------------------------------------------------
        current_mode_log = 0;
        $display("=== Mode 0: Bypass ===");
        send_audio( 16'sd1000,  16'sd500);
        send_audio(-16'sd500,   16'sd250);

        #50;

        // ---------------------------------------------------------------------
        // Mode 1: Encoder (L/R -> Mid/Side)
        // ---------------------------------------------------------------------
        $display("=== Mode 1: Encoder ===");
        write_reg(4'h0, 32'h0000_0001);
        current_mode_log = 1;

        send_audio( 16'sd2000,  16'sd1000); // mid=1500, side=500
        send_audio(-16'sd2000,  16'sd2000); // mid=0,    side=-2000

        #50;

        // ---------------------------------------------------------------------
        // Mode 2: Decoder (Mid/Side -> L/R)
        // ---------------------------------------------------------------------
        $display("=== Mode 2: Decoder ===");
        write_reg(4'h0, 32'h0000_0002);
        current_mode_log = 2;

        send_audio(16'sd1500,   16'sd500);  // L=2000, R=1000
        send_audio(16'sd0,     -16'sd2000); // L=-2000, R=2000

        #100;

        $fclose(f_csv);
        $display("=== Test Done. CSV saved to tb_midside_axis.csv ===");
        $finish;
    end

endmodule
