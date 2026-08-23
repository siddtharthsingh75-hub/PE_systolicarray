// Processing Element (PE) for a systolic array MAC
// Each cycle it multiplies the incoming values and accumulates the result,
// with proper bit-growth sizing and saturation on overflow.

module pe_1 #(
    parameter integer WIDTH      = 8,
    parameter integer ACC_WIDTH  = 20   // sized for worst-case accumulation depth
                                         // (2*WIDTH=16 for the product + margin bits
                                         //  for however many MACs you'll chain; e.g.
                                         //  4 extra bits covers up to 16 accumulations
                                         //  before overflow. Set this from your actual
                                         //  systolic array depth N: ACC_WIDTH >= 2*WIDTH + $clog2(N))
)(
    input  wire                       clk,
    input  wire                       rst,
    input  wire signed [WIDTH-1:0]    a_in,
    input  wire signed [WIDTH-1:0]    b_in,
    input  wire signed [ACC_WIDTH-1:0] acc_in,

    output reg  signed [WIDTH-1:0]     a_out,
    output reg  signed [WIDTH-1:0]     b_out,
    output reg  signed [ACC_WIDTH-1:0] acc_out
);

    // Product needs 2*WIDTH bits, sign-extended into ACC_WIDTH before adding
    wire signed [2*WIDTH-1:0]  mult_result;
    wire signed [ACC_WIDTH-1:0] mult_ext;
    wire signed [ACC_WIDTH:0]  sum_ext;   // one extra bit to catch overflow

    assign mult_result = a_in * b_in;
    assign mult_ext     = {{(ACC_WIDTH-2*WIDTH){mult_result[2*WIDTH-1]}}, mult_result};
    assign sum_ext       = acc_in + mult_ext;

    // Saturation: if sum_ext overflows ACC_WIDTH range, clamp to max/min
    localparam signed [ACC_WIDTH-1:0] ACC_MAX = {1'b0, {(ACC_WIDTH-1){1'b1}}};
    localparam signed [ACC_WIDTH-1:0] ACC_MIN = {1'b1, {(ACC_WIDTH-1){1'b0}}};

    wire overflow_pos = (~sum_ext[ACC_WIDTH]) & sum_ext[ACC_WIDTH-1] & ~acc_in[ACC_WIDTH-1];
    wire overflow_neg = sum_ext[ACC_WIDTH] & ~sum_ext[ACC_WIDTH-1] & acc_in[ACC_WIDTH-1];
    wire signed [ACC_WIDTH-1:0] acc_next =
        overflow_pos ? ACC_MAX :
        overflow_neg ? ACC_MIN :
                        sum_ext[ACC_WIDTH-1:0];

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            a_out   <= {WIDTH{1'b0}};
            b_out   <= {WIDTH{1'b0}};
            acc_out <= {ACC_WIDTH{1'b0}};
        end else begin
            a_out   <= a_in;
            b_out   <= b_in;
            acc_out <= acc_next;
        end
    end

endmodule