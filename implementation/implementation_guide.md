# DE2-115 Implementation Guide
## FPGA-Based RISC-V SoC for Image Processing Applications

This guide describes how to prepare the Quartus project, assign FPGA pins, connect an OV7670 camera module, program the Terasic DE2-115 board, and verify the image-processing pipeline.

> **Important:** The exact OV7670-to-FPGA pin mapping depends on the camera breakout board, the DE2-115 GPIO/HSMC connector used, and the top-level RTL port names. Do not copy arbitrary pin numbers from another project. Confirm every assignment against the DE2-115 user manual, the schematic for your camera adapter, and the actual top-level module. This guide does not claim that an unverified `.qsf` file is ready to program.

## 1. Install a compatible version of Quartus Prime

1. Open Intel/Altera's official FPGA software download page.
2. Choose a Quartus Prime version that supports the Cyclone IV E family and your operating system. The DE2-115 uses the Cyclone IV E `EP4CE115F29C7N` device; check the software/device support notes before installing.
3. Install Quartus Prime and the device support files for Cyclone IV E.
4. If you will program the board over USB-Blaster, install the required USB-Blaster driver and confirm that the computer can detect the programmer.
5. Restart the computer if the installer requests it.

The DE2-115 product documentation lists the board's FPGA as Cyclone IV E, device `EP4CE115F29C7N`. Refer to the board manual and the current Intel/Altera support information for the version appropriate to your environment.

## 2. Prepare the project files

Organize the repository so that the RTL, constraints, and documentation are easy to identify. For example:

```text
riscv-fpga-image-processing/
├── README.md
├── rtl/
│   ├── p1_riscv_image_soc_top_de2115.sv
│   └── ...other required .sv/.v files
├── constraints/
│   └── DE2_115.qsf
└── docs/
    └── implementation_guide.md
```

Use the actual top-level filename and module name from the source you intend to compile. Ensure every instantiated module has its corresponding source file. Do not include duplicate versions of the same module unless you have checked that the duplicates are not compiled together.

## 3. Create a new Quartus project

1. Launch Quartus Prime.
2. Select **File → New Project Wizard**.
3. Choose a project working directory, for example `quartus_project/`.
4. Enter a project name, such as `riscv_image_soc_de2115`.
5. Set the top-level entity to the exact top-level module in your RTL. If using the renamed source bundle, confirm the module declaration in `p1_riscv_image_soc_top_de2115.sv` before entering its name.
6. Add the required Verilog and SystemVerilog source files. Add all files that are instantiated by the top-level design, including the CPU pipeline, instruction/data memory, IPU, camera interface, PSNR calculator, VGA timing/display, and any helper modules used by those modules.
7. Complete the wizard.

You can also add sources after the wizard using **Project → Add/Remove Files in Project**.

## 4. Select the exact FPGA device

1. Open **Assignments → Device**.
2. Select the Cyclone IV E family.
3. Select the exact part fitted to your board: `EP4CE115F29C7N` (verify the marking and board revision against your board documentation).
4. Apply the selection.

Do not select a device merely because its name looks similar. The package and speed grade must match the board.

## 5. Set the top-level entity

1. Open **Project → Settings → General**.
2. Set **Top-level entity** to the module that exposes the board-level ports.
3. Open that module and inspect its port list.
4. Confirm that all board-level ports—clock, reset, camera inputs, VGA outputs, switches, keys, LEDs, and any other used I/O—are accounted for.
5. Confirm that the `.qsf` assignments use exactly the same signal names as the top-level RTL. A port renamed in RTL must also be updated in the constraints.

## 6. Add pin assignments and clock constraints

### Pin assignments

1. Open **Assignments → Pin Planner**.
2. Assign each top-level port to the correct physical FPGA pin using the DE2-115 board manual/schematic and the exact connector wiring.
3. Set each pin's I/O standard to the correct electrical standard for the board connection. DE2-115 user I/O headers are 3.3 V interfaces, but this does **not** mean every signal on every board connector uses 3.3 V. Follow the board documentation and the attached module's electrical requirements.
4. Check that no two unrelated signals share the same FPGA pin.
5. Save the assignments. Quartus stores these project assignments in the `.qsf` file.
6. Keep the final `.qsf` in `constraints/` and add it to the project, or keep the project-generated `.qsf` at the Quartus project root and document its location.

### Clock constraints

1. Identify the clock source used by the RTL. The DE2-115 provides 50 MHz clock inputs; verify the particular clock pin used by your top-level module.
2. Create or edit an `.sdc` file and declare the actual input clock with its measured/board-specified period. For a 50 MHz clock, the period is 20 ns.
3. Add generated-clock constraints only for clocks genuinely generated by clock-generation logic and constrain them according to the implementation.
4. Do not declare a clock frequency that the RTL does not generate.
5. Add the `.sdc` file under **Assignments → Settings → Timing Analyzer** (or the relevant timing-constraint settings for your Quartus version).
6. Run timing analysis and review any unconstrained clock or I/O warnings.

Example for a top-level clock port named `CLOCK_50`:

```tcl
create_clock -name CLOCK_50 -period 20.000 [get_ports {CLOCK_50}]
```

Change `CLOCK_50` to the exact top-level port name. This example is only valid if that port is connected to the board's 50 MHz clock input.

## 7. OV7670 camera connections

### Identify the camera module first

OV7670 boards vary. Some expose a bare sensor interface; others include a regulator, level shifting, or a connector adapter. Read the module's pin labels and its schematic before wiring it. The camera's supply and I/O voltage requirements must be respected. Do not connect a 5 V signal directly to a DE2-115 FPGA input.

### Signal-by-signal connection plan

Connect each camera signal to a compatible FPGA GPIO pin through the chosen DE2-115 expansion connector. Then assign that FPGA pin to the matching top-level RTL port in the `.qsf`.

| OV7670 signal | Direction relative to FPGA | Purpose | RTL/constraint action |
|---|---|---|---|
| `D0`–`D7` | Camera → FPGA | 8-bit pixel data bus | Connect each data bit to its corresponding camera-data input port; preserve bit order |
| `PCLK` | Camera → FPGA | Pixel-data sampling clock | Connect to the pixel-clock input used by the capture module |
| `HREF` | Camera → FPGA | Indicates active pixel data for a row | Connect to the horizontal-reference input |
| `VSYNC` | Camera → FPGA | Frame synchronization | Connect to the vertical-sync input |
| `XCLK` | FPGA → Camera | Clock supplied to the sensor | Connect to the RTL-generated camera clock output, if provided |
| `SIOC`/`SCL` | FPGA → Camera | SCCB serial clock | Connect to the SCCB clock output |
| `SIOD`/`SDA` | Bidirectional | SCCB serial data | Connect to the SCCB data signal using the intended bidirectional/open-drain arrangement |
| `RESET` (if exposed) | Usually FPGA → Camera | Sensor reset | Follow the module's active level and the RTL reset logic |
| `PWDN` (if exposed) | Usually FPGA → Camera | Power-down control | Set according to the sensor/module documentation and RTL |
| `VCC` and `GND` | Power | Sensor power and common reference | Use only the voltage specified by the camera breakout; connect grounds together |

### Wiring procedure

1. Power down the DE2-115 board before connecting the camera.
2. Identify the expansion connector used by the camera adapter (for example, GPIO or HSMC). Do not assume the connector is the same as another design.
3. Connect `D0` through `D7` in the correct bit order. A swapped data bus can produce incorrect colors or unstable pixels.
4. Connect `PCLK`, `HREF`, and `VSYNC` to the corresponding capture inputs.
5. Connect `XCLK` only if your design provides the required camera clock output. Verify its frequency and waveform against the OV7670 module's requirements.
6. Connect SCCB clock and data to the configuration controller. The SCCB data line is normally bidirectional/open-drain; follow the RTL and the module's pull-up requirements. Do not drive it push-pull high if the interface requires open-drain behavior.
7. Connect reset and power-down signals if the module exposes them and the design uses them.
8. Connect camera power and ground according to the breakout board's documentation. Ensure the FPGA I/O voltage is compatible with the module.
9. In Pin Planner, assign the actual physical FPGA pin for every camera signal and verify the assignments against the correct DE2-115 schematic and connector pinout.
10. Check for pin conflicts and I/O-standard mismatches before compilation.

**Do not use the OV7670 signal names alone as physical pin numbers.** The table above describes signal function, not a verified mapping to DE2-115 FPGA pins. The exact `.qsf` values must be generated from your actual wiring and RTL port names.

### Camera bring-up checks

- Confirm the SCCB initialization state machine completes or reports success, if your design exposes that status.
- Verify `XCLK` with an oscilloscope or logic analyzer if available.
- Observe `PCLK`, `HREF`, and `VSYNC` while the camera is active.
- Confirm that the capture logic sees frame and row boundaries.
- Check the RGB565-to-RGB888 conversion and confirm the expected byte order.
- Verify that cropping/downsampling produces the intended 128 × 128 image.
- If the output is black, noisy, or color-swapped, check power, ground, voltage compatibility, data-bit order, synchronization polarity, SCCB initialization, and clocking before changing the image-processing RTL.

## 8. VGA monitor connection

The DE2-115 has an onboard 15-pin VGA connector and an onboard VGA DAC. For the usual board-level VGA output, connect a VGA cable from the DE2-115 VGA connector to a compatible monitor. You do not need to wire separate RGB signals to external FPGA GPIO pins.

The RTL still must drive the board-level VGA signals assigned in the DE2-115 pin file.

### VGA signal functions

| VGA signal | Purpose |
|---|---|
| `VGA_R[7:0]` | Red pixel intensity |
| `VGA_G[7:0]` | Green pixel intensity |
| `VGA_B[7:0]` | Blue pixel intensity |
| `VGA_HS` | Horizontal synchronization |
| `VGA_VS` | Vertical synchronization |
| `VGA_CLK` | Pixel clock to the VGA DAC, if required by the board design |
| `VGA_BLANK_N` | Active-video/blanking control, if used by the design |
| `VGA_SYNC_N` | Composite sync control, if used by the design |

The exact port list depends on the board-level RTL and the DE2-115 reference design. Use the board manual's VGA circuit and the correct DE2-115 pin-assignment reference to verify every signal. Do not copy pin locations from a different board such as DE1-SoC or DE2.

### VGA setup and test

1. Connect the monitor to the board's VGA connector using a suitable cable.
2. Set the monitor input source to VGA.
3. Confirm that the VGA timing module generates the expected horizontal and vertical synchronization signals.
4. Confirm that the pixel clock matches the timing mode configured in the RTL. For a 640 × 480 mode, many designs use approximately 25 MHz; use the exact value and timing parameters in your implementation.
5. Verify that RGB outputs are blanked outside the active display region.
6. Confirm that the frame-buffer reader returns valid source and processed pixel data.
7. Check that the image composition logic places the original and processed images in the intended side-by-side regions.
8. Verify RGB888-to-RGB444 or other output-width conversion, if present in the design.
9. If the monitor reports no signal, check the board VGA pin assignments, pixel clock, `VGA_HS`, `VGA_VS`, blanking, and reset.
10. If sync is present but the image is black, check active-video timing, frame-buffer read addresses, pixel validity, and RGB output data.

## 9. Compile the project

1. Save all RTL and constraints.
2. Run **Processing → Start Compilation**.
3. Fix syntax errors, missing-module errors, multiple-driver errors, and width mismatches.
4. Resolve pin conflicts and incorrect I/O-standard assignments.
5. Review inferred latches and other warnings; determine whether each is intentional.
6. Open the compilation reports and confirm that the intended top-level entity and FPGA device were used.
7. Run timing analysis and review setup/hold timing and unconstrained paths.
8. Do not proceed to hardware testing if compilation fails.
9. Save the successful compilation output, including the generated `.sof` file.

## 10. Program the FPGA

1. Connect the DE2-115 to the computer using the board's USB-Blaster/programming connection.
2. Power the board with the correct board power supply.
3. Open **Tools → Programmer** in Quartus.
4. Select the appropriate hardware setup, usually USB-Blaster.
5. Click **Auto Detect** if needed and verify that the FPGA is detected.
6. Click **Add File** and select the `.sof` generated by your successful compilation.
7. Tick **Program/Configure** for the FPGA device.
8. Click **Start** and wait for the programming operation to complete.
9. Confirm the Programmer reports successful configuration.
10. Remember that a `.sof` configuration is normally volatile; it is lost when the board is powered off unless you separately configure nonvolatile programming.

## 11. Test the full system

Perform tests in stages rather than debugging the entire SoC at once.

### A. Board and clock
- Confirm the board powers on normally.
- Verify the 50 MHz input clock and reset behavior.
- Check that status LEDs or other simple outputs respond as expected.

### B. VGA-only test
- Temporarily use a known color-bar or solid-color test pattern if your design supports it.
- Confirm stable VGA synchronization and correct colors before involving the camera.
- Verify the expected 640 × 480 display timing if that is the configured mode.

### C. Camera capture
- Confirm SCCB initialization and camera clocks.
- Verify `PCLK`, `HREF`, and `VSYNC`.
- Capture a frame and confirm the expected image dimensions and pixel format.
- Confirm the source frame buffer contains changing pixel data as the camera scene changes.

### D. Image-processing operations
Test each supported mode individually:
1. **Grayscale:** output should contain grayscale intensity rather than visible color.
2. **Sobel edge detection:** prominent object boundaries should be highlighted.
3. **Gaussian filtering:** fine noise should be reduced and edges may appear smoother.
4. **Unsharp masking:** edges/details should appear more pronounced than in the corresponding input.

For each mode, verify the operation-selection control, completion/status behavior, output buffer writes, and VGA display.

### E. Image quality and performance metrics
- Verify that PSNR/MSE use the intended reference and processed image buffers.
- Check that metric values update only when the relevant frame/operation has completed.
- Compare hardware results with a software reference using the same pixel format, arithmetic precision, rounding, and border handling.
- Do not report metrics as measured results until they have been reproduced from the actual images.

## 12. Troubleshooting checklist

| Symptom | Checks |
|---|---|
| Quartus cannot find a module | Confirm all source files are added and module names match instantiations |
| Top-level entity not found | Check the module declaration and Quartus top-level setting |
| Pin assignment error | Check signal names, package pins, duplicate pin assignments, and I/O standards |
| Camera output is black | Check camera power, ground, SCCB setup, `XCLK`, `PCLK`, synchronization, and capture enable |
| Camera colors are wrong | Check `D0`–`D7` bit order, RGB565 byte order, and RGB conversion |
| VGA monitor says no signal | Check VGA cable/input selection, pixel clock, sync signals, reset, and pin constraints |
| VGA sync works but screen is black | Check active-video region, frame-buffer read path, RGB data, and memory initialization |
| Processing output does not change | Check algorithm selection, IPU start/done handshake, source/destination addresses, and memory writes |
| Metrics remain zero | Check whether valid pixels reach the metrics module and whether the frame-complete condition occurs |

## References

- Terasic, *DE2-115 Development and Education Board User Manual*: https://www.terasic.com.tw/attachment/archive/502/DE2_115_User_manual.pdf
- Intel/Altera, *DE2-115 FPGA Development and Education Kit*: https://www.altera.com/asap/offering/po-3170/de2-115-fpga-development-and-education-kit

Before publishing this guide as a verified implementation, confirm the pin map against your actual top-level RTL and wiring, compile the project in the selected Quartus version, and complete the hardware tests above.
