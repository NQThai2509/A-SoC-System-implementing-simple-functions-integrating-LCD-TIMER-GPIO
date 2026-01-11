module AHBLCD(
    input   wire            HCLK        ,
    input   wire            HRESETn     ,
    input   wire [31:0]     HADDR       ,
    input   wire [1:0]      HTRANS      ,
    input   wire [31:0]     HWDATA      ,
    input   wire            HWRITE      ,
    input   wire            HSEL        ,
    input   wire            HREADY      ,
    
    output  reg  [3:0]      LCD_DATA    ,
    output  reg             LCD_RW      ,
    output  reg             LCD_RS      ,
    output  reg             LCD_E       ,
  
    output  wire            HREADYOUT   ,
    output  reg  [31:0]     HRDATA
);

    // ===========================================================================
    // Clock & delay constants (156.25 MHz tr n AC701   oversize cho ch?c)
    // ===========================================================================
    localparam integer CLOCK_FREQ  = 156_250_000;
    localparam integer US          = CLOCK_FREQ / 1_000_000;  // ?156 cycles

    localparam integer DL_SEND1  = 6_000_000;
    localparam integer DL_SEND2 = 6_500;
    localparam integer DL_100US = 1_500_000;
    localparam integer DL_CMD   = 150_000;   
    localparam integer DL_CLR = 150_000;   
    localparam integer PULSE_WIDTH    = 15_000; 

    // AHB always single-cycle response
    assign HREADYOUT = 1'b1;

    // ===========================================================================
    // AHB-Lite signal registering
    // ===========================================================================
    reg         rHSEL;
    reg [31:0]  rHADDR;
    reg [1:0]   rHTRANS;
    reg         rHWRITE;

    wire ahb_active = rHSEL && rHTRANS[1];  // NONSEQ/SEQ & selected
    wire ahb_write  = ahb_active && rHWRITE;
    wire ahb_read   = ahb_active && !rHWRITE;

    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            rHSEL   <= 1'b0;
            rHADDR  <= 32'b0;
            rHTRANS <= 2'b0;
            rHWRITE <= 1'b0;
        end else if (HREADY) begin
            rHSEL   <= HSEL;
            rHADDR  <= HADDR;
            rHTRANS <= HTRANS;
            rHWRITE <= HWRITE;
        end
    end

    // ===========================================================================
    // 32-byte display RAM (0..15 line1, 16..31 line2)
    // ===========================================================================
    reg [7:0] disp_ram [0:31];
    integer i;

    initial begin
        for (i = 0; i < 32; i = i + 1)
            disp_ram[i] = 8'h20; // space
    end

    // CTRL register (ch? y?u ?? readback/debug)
    // bit0: START, bit1: CLEAR
    reg [31:0] ctrl_reg;

    // Request latch cho START/CLEAR (C ch 1)
    reg start_req;
    reg clear_req;

    integer base;
    integer base_r;

    // ===========================================================================
    // Request handshake wires: FSM ? L_IDLE + request ?ang 1 => "?n" request
    // ===========================================================================
    // ??nh ngh?a lstate ph a d??i, nh?ng Verilog cho ph p d ng tr??c
    wire do_clear;
    wire do_start;

    // ===========================================================================
    // CTRL + request latch + request consume  (DUY NH?T 1 ALWAYS g n start_req/clear_req)
    // ===========================================================================
    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            ctrl_reg  <= 32'd0;
            start_req <= 1'b0;
            clear_req <= 1'b0;
        end else begin
            // 1) CPU ghi CTRL
            if (ahb_write && (rHADDR[7:0] == 8'h00)) begin
                ctrl_reg <= HWDATA;
                if (HWDATA[0])
                    start_req <= 1'b1;   // set request START
                if (HWDATA[1])
                    clear_req <= 1'b1;   // set request CLEAR
            end

            // 2) FSM ?  consume request t?i L_IDLE
            if (do_clear)
                clear_req <= 1'b0;
            if (do_start)
                start_req <= 1'b0;
        end
    end

    // ===========================================================================
    // Display RAM write (m?i l?n ghi 1 byte v o disp_ram[base])
    // ===========================================================================
    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            // gi? nguy n n?i dung kh?i t?o (space)
        end else if (ahb_write) begin
            if ((rHADDR[7:0] >= 8'h10) && (rHADDR[7:0] <= 8'h2F)) begin
                base = rHADDR[7:0] - 8'h10;   // 0..31
                if (base <= 31)
                    disp_ram[base] <= HWDATA[7:0];  // lu n l?y byte th?p
            end
        end
    end

    // Busy flag
    reg busy_flag;

    // AHB read mux
    always @(*) begin
        HRDATA = 32'h0000_0000;
        if (ahb_read) begin
            case (rHADDR[7:0])
                8'h00: HRDATA = ctrl_reg;
                8'h04: HRDATA = {31'b0, busy_flag};
                default: begin
                    if ((rHADDR[7:0] >= 8'h10) && (rHADDR[7:0] <= 8'h2F)) begin
                        base_r = rHADDR[7:0] - 8'h10;
                        // 32-bit aligned read: pack up to 4 chars (little endian)
                        if (rHADDR[1:0] == 2'b00) begin
                            HRDATA[7:0]   = (base_r + 0 <= 31) ? disp_ram[base_r + 0] : 8'h20;
                            HRDATA[15:8]  = (base_r + 1 <= 31) ? disp_ram[base_r + 1] : 8'h20;
                            HRDATA[23:16] = (base_r + 2 <= 31) ? disp_ram[base_r + 2] : 8'h20;
                            HRDATA[31:24] = (base_r + 3 <= 31) ? disp_ram[base_r + 3] : 8'h20;
                        end else begin
                            HRDATA[7:0] = (base_r <= 31) ? disp_ram[base_r] : 8'h20;
                        end
                    end
                end
            endcase
            end
    end

    // ===========================================================================
    // LCD driver FSM
    // ===========================================================================
    localparam [3:0]
        L_RESET           = 4'd0,
        L_POW_WAIT        = 4'd1,
        L_SEND_3       	  = 4'd2,
        L_WAIT_3          = 4'd3,
        L_SEND_2          = 4'd4,
        L_CMD_SETUP		  = 4'd5,
        //L_CMD_FUNC        = 5'd5,
        //L_CMD_DISP_ON     = 5'd6,
        //L_CMD_CLEAR_INIT  = 5'd7,
        //L_CMD_ENTRY_INIT  = 5'd8,
        L_IDLE            = 4'd6,
        // Sequence for CLEAR request
        //L_CLEAR_CMD       = 5'd7,
        // Sequence for START (write 2 lines)
        L_SET_DDRAM1      = 4'd7,
        L_WRITE_CHARS1    = 4'd8,
        L_SET_DDRAM2      = 4'd9,
        L_WRITE_CHARS2    = 4'd10,
        // Byte send sub-FSM
        L_SEND_BYTE_SETUP = 4'd11,
        L_SEND_HIGH_PULSE = 4'd12,
        L_SEND_HIGH_HOLD  = 4'd13,
        L_SEND_LOW_PULSE  = 4'd14,
        L_POST_BYTE_DELAY = 4'd15;

    reg [3:0]  lstate;
    reg [31:0] clkcnt;
    reg [7:0]  byte_to_send;
    reg        byte_is_data;
    reg [3:0]  return_state;
    reg [5:0]  char_ptr;
	reg [1:0]  init_phase;
	reg [1:0]  init_setup;
	
    // ch nh th?c ??nh ngh?a handshake:
    assign do_clear = (lstate == L_IDLE) && clear_req;
    assign do_start = (lstate == L_IDLE) && !clear_req && start_req; // CLEAR ?u ti n h?n START

    wire [3:0] high_nibble = byte_to_send[7:4];
    wire [3:0] low_nibble  = byte_to_send[3:0];

    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            lstate       <= L_RESET;
            clkcnt       <= 32'd0;
            LCD_DATA       <= 4'b0000;
            LCD_RS       <= 1'b0;
            LCD_RW       <= 1'b0;
            LCD_E        <= 1'b0;
            byte_to_send <= 8'h00;
            byte_is_data <= 1'b0;
            return_state <= L_IDLE;
            char_ptr     <= 6'd0;
            busy_flag    <= 1'b1;
            init_phase <= 2'd0;
            init_setup <= 2'd0;
        end else begin
            case (lstate)
                //-----------------------------------------------------------------
                // Power-up init sequence (gi?ng datasheet: 3x0x3, 0x2, 0x28, 0x0C, 0x01, 0x06)
                //-----------------------------------------------------------------
                L_RESET: begin
                    clkcnt    <= 32'd0;
                    busy_flag <= 1'b1;
                    LCD_E     <= 1'b0;
                    LCD_RS    <= 1'b0;
                    LCD_RW    <= 1'b0;
                    LCD_DATA    <= 4'b0000;
                    init_phase <= 2'd0;
                    init_setup <= 2'd0;
                    lstate    <= L_POW_WAIT;
                end

                L_POW_WAIT: begin
                    if (clkcnt < DL_SEND1)
                        clkcnt <= clkcnt + 1;
                    else begin
                    clkcnt <= 0;
                        lstate <= L_SEND_3;
                    end
                end

                // 1st 0x3 nibble
                L_SEND_3: begin
                    LCD_RS <= 1'b0;
                    LCD_RW <= 1'b0;
                    LCD_DATA <= 4'b0011;
                    if (clkcnt == 0) begin
                        LCD_E  <= 1'b1;
                        clkcnt <= clkcnt + 1;
                    end else if (clkcnt < PULSE_WIDTH) begin
                        clkcnt <= clkcnt + 1;
                    end else begin
                        LCD_E  <= 1'b0;
                        clkcnt <= 0;
                        lstate <= L_WAIT_3;
                    end
                end

                L_WAIT_3: begin
	                if (init_phase == 2'd0) begin
	                    if (clkcnt < DL_SEND2) begin
	                        clkcnt <= clkcnt + 1;
	                    end else begin 
	                        clkcnt <= 0;
	                        init_phase <= init_phase + 1;
	                        lstate <= L_SEND_3;
	                    end
					end else begin 
						if (clkcnt < DL_100US) begin
	                        clkcnt <= clkcnt + 1;
	                    end else begin 
	                        clkcnt <= 0;
	                        init_phase <= init_phase + 1;
	                        if (init_phase < 2) begin
	                        	lstate <= L_SEND_3;
	                        end else begin
	                        	init_phase <= 2'd0;
								lstate <= L_SEND_2;
	                    	end
						end
                    end
                end
                
                L_SEND_2: begin
                    LCD_RS <= 1'b0;
                    LCD_RW <= 1'b0;
                    LCD_DATA <= 4'b0010;
                    if (clkcnt == 0) begin
                        LCD_E  <= 1'b1;
                        clkcnt <= clkcnt + 1;
                    end else if (clkcnt < PULSE_WIDTH) begin
                        clkcnt <= clkcnt + 1;
                    end else begin
                        LCD_E  <= 1'b0;
                        clkcnt <= 0;
                        lstate <= L_CMD_SETUP;
                    end
                end

				L_CMD_SETUP: begin
					if (init_setup <= 2) begin
						return_state <= L_CMD_SETUP;
                    end else begin
                    	return_state <= L_IDLE;
                    end
					if (init_setup == 0) begin
						init_setup <= init_setup + 1;
						byte_to_send <= 8'h28;
                    end else if (init_setup == 1) begin 
                    	init_setup <= init_setup + 1;
						byte_to_send <= 8'h0C;
                    end else if (init_setup == 2) begin 
                    	init_setup <= init_setup + 1;
						byte_to_send <= 8'h01;
                    end else begin
						byte_to_send <= 8'h06;
                    end
                    byte_is_data <= 1'b0;
                    lstate <= L_SEND_BYTE_SETUP;
                end
                //-----------------------------------------------------------------
                // IDLE: ch? do_clear ho?c do_start (?  ?u ti n CLEAR)
                //-----------------------------------------------------------------
                L_IDLE: begin
                    busy_flag <= 1'b0;
                    LCD_E     <= 1'b0;

                    if (do_clear) begin
                        busy_flag    <= 1'b1;
                        byte_to_send <= 8'h01;
                        byte_is_data <= 1'b0;
                        return_state <= L_IDLE;
                        lstate       <= L_SEND_BYTE_SETUP;
                        clkcnt       <= 0;
                    end
                    else if (do_start) begin
                        busy_flag    <= 1'b1;
                        char_ptr     <= 6'd0;
                        // set DDRAM line 1
                        byte_to_send <= 8'h80;   // 0x80 | 0x00
                        byte_is_data <= 1'b0;
                        return_state <= L_SET_DDRAM1;
                        lstate       <= L_SEND_BYTE_SETUP;
                        clkcnt       <= 0;
                    end
                end

                //-----------------------------------------------------------------
                // START sequence: set addr + ghi line1 + set addr line2 + ghi line2
                //-----------------------------------------------------------------
                L_SET_DDRAM1: begin
                    char_ptr <= 6'd0;
                    lstate   <= L_WRITE_CHARS1;
                end

                // ghi 16 k  t? line 1 (0..15)
                L_WRITE_CHARS1: begin
                    if (char_ptr < 6'd16) begin
                        byte_to_send <= disp_ram[char_ptr];
                        byte_is_data <= 1'b1;
                        return_state <= L_WRITE_CHARS1;
                        char_ptr     <= char_ptr + 1;
                        lstate       <= L_SEND_BYTE_SETUP;
                    end else begin
                        // xong line1, set DDRAM line2
                        byte_to_send <= 8'hC0; // 0x80 | 0x40
                        byte_is_data <= 1'b0;
                        return_state <= L_SET_DDRAM2;
                        lstate       <= L_SEND_BYTE_SETUP;
                    end
                end

                L_SET_DDRAM2: begin
                    char_ptr <= 6'd16;
                    lstate   <= L_WRITE_CHARS2;
                end

                // ghi 16 k  t? line 2 (16..31)
                L_WRITE_CHARS2: begin
                    if (char_ptr < 6'd32) begin
                        byte_to_send <= disp_ram[char_ptr];
                        byte_is_data <= 1'b1;
                        return_state <= L_WRITE_CHARS2;
                        char_ptr     <= char_ptr + 1;
                        lstate       <= L_SEND_BYTE_SETUP;
                    end else begin
                        lstate <= L_IDLE;
                    end
                    end

                //-----------------------------------------------------------------
                // Sub-FSM: g?i 1 byte (2 nibble) v?i timing E
                //-----------------------------------------------------------------
                L_SEND_BYTE_SETUP: begin
                    LCD_RS <= byte_is_data ? 1'b1 : 1'b0;
                    LCD_RW <= 1'b0;
                    LCD_DATA <= high_nibble;
                    LCD_E  <= 1'b0;
                    clkcnt <= 0;
                    lstate <= L_SEND_HIGH_PULSE;
                end

                L_SEND_HIGH_PULSE: begin
                    if (clkcnt == 0) begin
                        LCD_E  <= 1'b1;
                        clkcnt <= clkcnt + 1;
                    end else if (clkcnt < PULSE_WIDTH) begin
                        clkcnt <= clkcnt + 1;
                    end else begin
                        LCD_E  <= 1'b0;
                        clkcnt <= 0;
                        lstate <= L_SEND_HIGH_HOLD;
                    end
                end

                L_SEND_HIGH_HOLD: begin
                    if (clkcnt < US) begin
                        clkcnt <= clkcnt + 1;
                    end else begin
                        clkcnt <= 0;
                        LCD_DATA <= low_nibble;
                        lstate <= L_SEND_LOW_PULSE;
                    end
                end

                L_SEND_LOW_PULSE: begin
                    if (clkcnt == 0) begin
                        LCD_E  <= 1'b1;
                        clkcnt <= clkcnt + 1;
                    end else if (clkcnt < PULSE_WIDTH) begin
                        clkcnt <= clkcnt + 1;
                    end else begin
                        LCD_E  <= 1'b0;
                        clkcnt <= 0;
                        lstate <= L_POST_BYTE_DELAY;
                    end
                end

                L_POST_BYTE_DELAY: begin
                    if (byte_to_send == 8'h01 || byte_to_send == 8'h02) begin
                        if (clkcnt < DL_CLR)
                            clkcnt <= clkcnt + 1;
                        else begin
                            clkcnt <= 0;
                            lstate <= return_state;
                        end
                    end else begin
                        if (clkcnt < DL_CMD)
                            clkcnt <= clkcnt + 1;
                        else begin
                            clkcnt <= 0;
                            lstate <= return_state;
                        end
                    end
                end

                default: begin
                    lstate <= L_RESET;
                end
            endcase
        end
    end

endmodule