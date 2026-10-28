# FPGA Implementation of a RISC-V SoC for Image Processing Applications

## Overview

This project implements a RISC-V-based System-on-Chip for image processing on the Terasic DE2-115 FPGA development board.

## Main Features

- Five-stage RV32I processor pipeline
- Dedicated Image Processing Unit (IPU)
- OV7670 camera interface
- Grayscale conversion
- Sobel edge detection
- Gaussian filtering
- Unsharp masking
- PSNR and MSE image-quality evaluation
- VGA display of original and processed images

## Hardware Platform

- FPGA board: Terasic DE2-115
- FPGA family: Cyclone IV E
- Camera: OV7670
- Display: VGA monitor

## Repository Structure

- `rtl/` — SystemVerilog source files
- `constraints/` — Quartus pin assignments and constraints
- `docs/` — Setup and implementation instructions
- `images/` — Architecture diagrams and demonstration images

## Implementation

Refer to `docs/implementation_guide.md` for the Quartus setup, pin configuration, compilation, and FPGA programming procedure.

## Project Status

The source code and implementation instructions are provided for review and further validation. Compilation and hardware results should be documented after testing on the target FPGA board.
