`timescale 1ns / 1ps

////////////////////////////////////////////////////////////////////////////////
// Top-Level Module
////////////////////////////////////////////////////////////////////////////////
module top #(
    parameter [21:0] ONE_SEC_MAX = 22'd3_999_999
)(
    input  wire rst_n,     // External Reset Button (Active-Low)
    input  wire clk,       // 25 MHz Board Input Clock
    output wire led1_out,
    output wire led2_out,    
    inout  wire sda,
    inout  wire scl        
);
    
	 // Array definition: 10 elements, each 8 bits wide
    reg [7:0] data_array [0:9];
    
    // 4-bit index pointer to track which element we are sending (0 to 9)
    reg [3:0] index              = 4'd0;
	 reg [7:0] data               = 8'h0;
	 reg [7:0] counter            = 8'h0;
	 reg       newd               = 1'b0;
    wire      busy;
    wire      done;
    wire      ack_err;
    wire [7:0] dout;
    wire      clk_4m;
    wire      lock;
    wire      sys_rst_n;   
    reg       led1            = 1'b0;
    reg       led2            = 1'b0;

	 // Initialize the array contents
    initial begin
        data_array[0] = 8'd1;
        data_array[1] = 8'd2;
        data_array[2] = 8'd3;
        data_array[3] = 8'd4;
        data_array[4] = 8'd5;
        data_array[5] = 8'd6;
        data_array[6] = 8'd7;
        data_array[7] = 8'd8;
        data_array[8] = 8'd9;
        data_array[9] = 8'd10;
    end
    // 1. PLL Instantiation
    pll clk_pll (
        .areset(!rst_n),   // Standard PLLs usually expect active-high reset
        .inclk0(clk),      
        .c0    (clk_4m),   
        .locked(lock)
    );
    
    // 2. Safe Internal System Reset (Active-Low)
    assign sys_rst_n = rst_n && lock;
    assign led1_out       = led1;
    assign led2_out       = led2;

    // 3. 1.0-Second Interval Timer Configuration
    reg [21:0] clk_count = 22'd0;
    reg       one_second_flag = 1'b0;

    always @(posedge clk_4m or negedge sys_rst_n) begin 
        if (!sys_rst_n) begin 
            clk_count          <= 22'd0;
            one_second_flag <= 1'b0;
        end else begin 
            if (clk_count >= ONE_SEC_MAX) begin 
                clk_count          <= 22'd0;
                one_second_flag    <= 1'b1; 
            end else begin 
                clk_count          <= clk_count + 1'b1;
					 one_second_flag    <= 1'b0;  // Default to 0

            end 
        end
    end

    // 4. Sequential Control State Machine
    localparam [1:0] IDLE      = 2'b00,
                     START_TX  = 2'b01,
                     WAIT_BUSY = 2'b10,
                     WAIT_DONE = 2'b11;

    reg [1:0] state;

    always @(posedge clk_4m or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            state   <= IDLE;
            counter <= 8'b0;
            newd    <= 1'b0;
            led1    <= 1'b0;
            led2    <= 1'b0;
				index   <= 4'd0;   // Reset index to the first element
        end else begin
            case (state)
                IDLE: begin
                    newd <= 1'b0;
                    if (one_second_flag) begin
						      led1  <= ~led1;
                        state <= START_TX;
                    end
                end

                START_TX: begin
                    newd  <= 1'b1; 
						  data  <= data_array[index];
                    state <= WAIT_BUSY;
                end

                WAIT_BUSY: begin
                    newd <= 1'b0; 
                    if (busy) begin
                        state <= WAIT_DONE;
                    end
                end

                WAIT_DONE: begin
                    if (!busy) begin
									 led2  <= ~led2;
									 state <= IDLE;
								//	 if (!ack_err) begin 
			                       counter <= counter +1;
										  if (index == 4'd9) index <= 4'd0;
										  else                index <= index + 1'b1;
									// end
									 // else: stay on same index, retry next second
								end
                  end
                
                default: state <= IDLE;
            endcase
        end
    end  

    localparam [6:0] SLAVE_ADDR = 7'h08; 
    localparam       OP_WRITE   = 1'b0;

    // 5. I2C Master Instantiation
    i2c_master master_inst (
        .clk(clk_4m),
        .rst_n(sys_rst_n),
        .newd(newd),
        .addr(SLAVE_ADDR),
        .op(OP_WRITE),
        .sda(sda),
        .scl(scl),
        .din(counter), 
        .dout(dout),
        .busy(busy),
        .ack_err(ack_err),
        .done(done)
    );
                     
endmodule


////////////////////////////////////////////////////////////////////////////////
// I2C Master Module
////////////////////////////////////////////////////////////////////////////////
module i2c_master ( 
    input  wire       clk, 
    input  wire       rst_n,
    input  wire       newd,
    input  wire [6:0] addr,
    input  wire       op, 
    inout  wire       sda,
    output wire       scl,
    input  wire [7:0] din,
    output wire [7:0] dout,
    output reg        busy, 
    output reg        ack_err, 
    output reg        done
);

    reg scl_t = 1'b1;
    reg sda_t = 1'b1;

    parameter sys_freq = 4000000; // 4 MHz
    parameter i2c_freq = 100000;  // 100 kHz

    localparam clk_count4 = (sys_freq / i2c_freq); // 40
    localparam clk_count1 = clk_count4 / 4;        // 10

    integer count1 = 0;

    // 4x clock pulse generation
    reg [1:0] pulse = 0;
    always @(posedge clk) begin
        if (!rst_n) begin
            pulse  <= 0;
            count1 <= 0;
        end else if (busy == 1'b0) begin 
            pulse  <= 0;
            count1 <= 0;
        end else begin
            if (count1 == clk_count1 - 1) begin
                pulse  <= 2'd1;
                count1 <= count1 + 1;
            end else if (count1 == clk_count1 * 2 - 1) begin
                pulse  <= 2'd2;
                count1 <= count1 + 1;
            end else if (count1 == clk_count1 * 3 - 1) begin
                pulse  <= 2'd3;
                count1 <= count1 + 1;
            end else if (count1 == clk_count1 * 4 - 1) begin
                pulse  <= 2'd0;
                count1 <= 0;
            end else begin
                count1 <= count1 + 1;
            end
        end
    end

    reg [3:0] bitcount  = 0;
    reg [7:0] data_addr = 0;
    reg [7:0] data_tx   = 0;
    reg       r_ack     = 0;
    reg [7:0] rx_data   = 0;
    reg       sda_en    = 0;

    // Pure-Verilog state encoding (replaces SystemVerilog typedef enum)
    localparam [3:0] IDLE_S       = 4'd0,
                     START_S      = 4'd1,
                     WRITE_ADDR_S = 4'd2,
                     ACK1_S       = 4'd3,
                     WRITE_DATA_S = 4'd4,
                     READ_DATA_S  = 4'd5,
                     STOP_S       = 4'd6,
                     ACK2_S       = 4'd7,
                     MASTER_ACK_S = 4'd8;

    reg [3:0] state = IDLE_S;

    always @(posedge clk) begin
        if (!rst_n) begin
            bitcount  <= 0;
            data_addr <= 0;
            data_tx   <= 0;
            scl_t     <= 1'b1;
            sda_t     <= 1'b1;
            state     <= IDLE_S;
            busy      <= 1'b0;
            ack_err   <= 1'b0;
            done      <= 1'b0;
            r_ack     <= 1'b0;
            rx_data   <= 8'h0;
            sda_en    <= 1'b0;
        end else begin
            case (state)
                IDLE_S: begin
                    done <= 1'b0;
                    if (newd == 1'b1) begin
                        data_addr <= {addr, op};
                        data_tx   <= din;
                        busy      <= 1'b1;
                        state     <= START_S;
                        ack_err   <= 1'b0;
                    end else begin
                        data_addr <= 0;
                        data_tx   <= 0;
                        busy      <= 1'b0;
                        state     <= IDLE_S;
                        ack_err   <= 1'b0;
                    end
                end

                START_S: begin
                    sda_en <= 1'b1; 
                    case (pulse)
                        2'd0: begin scl_t <= 1'b1; sda_t <= 1'b1; end
                        2'd1: begin scl_t <= 1'b1; sda_t <= 1'b1; end
                        2'd2: begin scl_t <= 1'b1; sda_t <= 1'b0; end
                        2'd3: begin scl_t <= 1'b1; sda_t <= 1'b0; end
                    endcase
                    
                    if (count1 == clk_count1 * 4 - 1) begin
                        state <= WRITE_ADDR_S;
                        scl_t <= 1'b0;
                    end
                end

                WRITE_ADDR_S: begin
                    sda_en <= 1'b1;  
                    if (bitcount <= 7) begin
                        case (pulse)
                            2'd0: begin scl_t <= 1'b0; sda_t <= 1'b0; end
                            2'd1: begin scl_t <= 1'b0; sda_t <= data_addr[7 - bitcount]; end
                            2'd2: begin scl_t <= 1'b1; end
                            2'd3: begin scl_t <= 1'b1; end
                        endcase
                        
                        if (count1 == clk_count1 * 4 - 1) begin
                            scl_t    <= 1'b0;
                            bitcount <= bitcount + 1;
                        end
                    end else begin
                        state    <= ACK1_S;
                        bitcount <= 0;
                        sda_en   <= 1'b0; 
                    end
                end

                ACK1_S: begin
                    sda_en <= 1'b0; 
                    case (pulse)
                        2'd0: begin scl_t <= 1'b0; sda_t <= 1'b0; end
                        2'd1: begin scl_t <= 1'b0; sda_t <= 1'b0; end
                        2'd2: begin scl_t <= 1'b1; r_ack <= sda;  end 
                        2'd3: begin scl_t <= 1'b1; end
                    endcase

                    if (count1 == clk_count1 * 4 - 1) begin
                        if (r_ack == 1'b0 && data_addr[0] == 1'b0) begin
                            state    <= WRITE_DATA_S;
                            sda_t    <= 1'b0;
                            sda_en   <= 1'b1; 
                            bitcount <= 0;

                        end else if (r_ack == 1'b0 && data_addr[0] == 1'b1) begin
                            state    <= READ_DATA_S;
                            sda_t    <= 1'b1;
                            sda_en   <= 1'b0; 
                            bitcount <= 0;

                        end else begin
                            state   <= STOP_S;
                            sda_en  <= 1'b1; 
                            ack_err <= 1'b1;

                        end
                    end
                end
                    
                WRITE_DATA_S: begin
                    if (bitcount <= 7) begin
                        case (pulse)
                            2'd0: begin scl_t <= 1'b0; end
                            2'd1: begin scl_t <= 1'b0; sda_en <= 1'b1; sda_t <= data_tx[7 - bitcount]; end
                            2'd2: begin scl_t <= 1'b1; end
                            2'd3: begin scl_t <= 1'b1; end
                        endcase
                        
                        if (count1 == clk_count1 * 4 - 1) begin
                            scl_t    <= 1'b0;
                            bitcount <= bitcount + 1;
                        end
                    end else begin
                        state    <= ACK2_S;
                        bitcount <= 0;
                        sda_en   <= 1'b0; 
                    end
                end

                READ_DATA_S: begin
                    sda_en <= 1'b0; 
                    if (bitcount <= 7) begin
                        case (pulse)
                            2'd0: begin scl_t <= 1'b0; sda_t <= 1'b0; end
                            2'd1: begin scl_t <= 1'b0; sda_t <= 1'b0; end
                            2'd2: begin scl_t <= 1'b1; rx_data <= (count1 == clk_count1 * 2 + 5) ? {rx_data[6:0], sda} : rx_data; end
                            2'd3: begin scl_t <= 1'b1; end
                        endcase
                        
                        if (count1 == clk_count1 * 4 - 1) begin
                            scl_t    <= 1'b0;
                            bitcount <= bitcount + 1;
                        end
                    end else begin
                        state    <= MASTER_ACK_S;
                        bitcount <= 0;
                        sda_en   <= 1'b1; 
                    end
                end

                MASTER_ACK_S: begin
                    sda_en <= 1'b1;
                    case (pulse)
                        2'd0: begin scl_t <= 1'b0; sda_t <= 1'b1; end
                        2'd1: begin scl_t <= 1'b0; sda_t <= 1'b1; end
                        2'd2: begin scl_t <= 1'b1; r_ack <= sda;  end 
                        2'd3: begin scl_t <= 1'b1; sda_t <= 1'b1; end
                    endcase
                    
                    if (count1 == clk_count1 * 4 - 1) begin
                        sda_t  <= 1'b0;
                        state  <= STOP_S;
                        sda_en <= 1'b1; 
                    end
                end
                 
                ACK2_S: begin
                    sda_en <= 1'b0; 
                    case (pulse)
                        2'd0: begin scl_t <= 1'b0; sda_t <= 1'b0; end
                        2'd1: begin scl_t <= 1'b0; sda_t <= 1'b0; end
                        2'd2: begin scl_t <= 1'b1; r_ack <= sda;  end 
                        2'd3: begin scl_t <= 1'b1; end
                    endcase
                    
                    if (count1 == clk_count1 * 4 - 1) begin
                        sda_t  <= 1'b0;
                        sda_en <= 1'b1; 
                        state  <= STOP_S;
                        if (r_ack == 1'b0) begin
                            ack_err <= 1'b0;
                        end else begin
                            ack_err <= 1'b1;
                        end
                    end
                end

                STOP_S: begin
                    sda_en <= 1'b1; 
                    case (pulse)
                        2'd0: begin scl_t <= 1'b1; sda_t <= 1'b0; end
                        2'd1: begin scl_t <= 1'b1; sda_t <= 1'b0; end
                        2'd2: begin scl_t <= 1'b1; sda_t <= 1'b1; end
                        2'd3: begin scl_t <= 1'b1; sda_t <= 1'b1; end
                    endcase
                     
                    if (count1 == clk_count1 * 4 - 1) begin
                        state  <= IDLE_S;
                        scl_t  <= 1'b0;
                        busy   <= 1'b0;
                        sda_en <= 1'b1; 
                        done   <= 1'b1;
                    end
                end
                
                default: state <= IDLE_S;
            endcase
        end
    end

    assign sda  = (sda_en == 1'b1) ? ((sda_t == 1'b0) ? 1'b0 : 1'bz) : 1'bz; 
    assign scl  = scl_t;
    assign dout = rx_data;

endmodule
