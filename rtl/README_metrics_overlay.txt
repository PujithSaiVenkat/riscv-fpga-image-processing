RISC-V SoC VGA metrics overlay patch

Contents: one selected copy of each uploaded RTL module, plus the modified top-level and VGA display module and new image_metrics_fpga.sv. Add image_metrics_fpga.sv to your Quartus project.

VGA overlay lines: FRAME, PSNR, MSE, IE, AG, RMS, TIME, MP/S, FPS.

Metrics:
- IE: histogram entropy estimate in bits/pixel, displayed to 2 decimal places. Uses a compact Q4 log2 lookup, so it is approximate.
- AG: mean absolute intensity difference over valid horizontal and vertical grayscale neighbors, displayed to 2 decimal places. Use this exact definition if reporting the metric.
- RMS: grayscale standard deviation, displayed to 2 decimal places, using integer/fixed-point arithmetic.
- TIME: last_process_cycles / 500 gives centi-milliseconds at 50 MHz.
- MP/S: 81,920,000 / last_process_cycles gives throughput in hundredths of Mpixel/s for a 128x128 frame at 50 MHz.
- FPS: count of completed IPU transactions in a one-second window, displayed to one decimal place. This is processing completion rate, not VGA refresh rate.

The statistics monitor observes sequential RGB888 writes to DST_BASE and assumes R,G,B byte order and IMG_W x IMG_H dimensions. The bundle was not compiled or timing-closed with Quartus in this environment. Compile, inspect warnings, verify the address/data stream, and check resource use and timing before programming the FPGA.
