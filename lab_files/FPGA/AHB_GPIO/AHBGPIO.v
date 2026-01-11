//////////////////////////////////////////////////////////////////////////////////
// AHBGPIO (fixed for SW-in + LED-out use-case)
// - DATA @ 0x00:
//     * READ  : returns GPIOIN[15:0]  (switches)
//     * WRITE : updates GPIOOUT[15:0] masked by DIR (output enable mask)
// - DIR  @ 0x04:
//     * R/W   : output enable mask (1 = allow driving that output bit)
// Notes:
// - This matches your SoC wiring where GPIOIN and GPIOOUT are physically separate.
// - No need to toggle DIR to read switches then drive LEDs.
//////////////////////////////////////////////////////////////////////////////////

module AHBGPIO(
  input  wire        HCLK,
  input  wire        HRESETn,
  input  wire [31:0] HADDR,
  input  wire [1:0]  HTRANS,
  input  wire [31:0] HWDATA,
  input  wire        HWRITE,
  input  wire        HSEL,
  input  wire        HREADY,
  input  wire [15:0] GPIOIN,

  output wire        HREADYOUT,
  output wire [31:0] HRDATA,
  output wire [15:0] GPIOOUT
);

  localparam [7:0] gpio_data_addr = 8'h00;
  localparam [7:0] gpio_dir_addr  = 8'h04;

  // AHB address-phase registers (like your original code)
  reg [31:0] last_HADDR;
  reg [1:0]  last_HTRANS;
  reg        last_HWRITE;
  reg        last_HSEL;

  assign HREADYOUT = 1'b1;

  always @(posedge HCLK) begin
    if (HREADY) begin
      last_HADDR  <= HADDR;
      last_HTRANS <= HTRANS;
      last_HWRITE <= HWRITE;
      last_HSEL   <= HSEL;
    end
  end

  wire trans_valid = last_HSEL & last_HTRANS[1];     // NONSEQ/SEQ
  wire wr_en       = trans_valid & last_HWRITE;
  wire rd_en       = trans_valid & ~last_HWRITE;

  // Registers
  reg [15:0] gpio_dir;      // output enable mask
  reg [15:0] gpio_dataout;  // output data (drives GPIOOUT)

  // DIR register write
  always @(posedge HCLK or negedge HRESETn) begin
    if (!HRESETn) begin
      gpio_dir <= 16'h0000;           // default: outputs disabled
    end else if (wr_en && (last_HADDR[7:0] == gpio_dir_addr)) begin
      gpio_dir <= HWDATA[15:0];
    end
  end

  // DATA register write (masked by DIR)
  // Only bits with gpio_dir=1 are allowed to change output
  always @(posedge HCLK or negedge HRESETn) begin
    if (!HRESETn) begin
      gpio_dataout <= 16'h0000;
    end else if (wr_en && (last_HADDR[7:0] == gpio_data_addr)) begin
      gpio_dataout <= (gpio_dataout & ~gpio_dir) | (HWDATA[15:0] & gpio_dir);
    end
  end

  assign GPIOOUT = gpio_dataout;

  // Read mux
  reg [31:0] rdata;
  always @(*) begin
    rdata = 32'h0000_0000;

    if (rd_en) begin
      case (last_HADDR[7:0])
        gpio_data_addr: rdata = {16'h0000, GPIOIN};     // ALWAYS return GPIOIN (SW)
        gpio_dir_addr : rdata = {16'h0000, gpio_dir};   // read DIR mask
        default       : rdata = 32'h0000_0000;
      endcase
    end
  end

  assign HRDATA = rdata;

endmodule
