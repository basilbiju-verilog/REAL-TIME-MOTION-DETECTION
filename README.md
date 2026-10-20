# FPGA Motion Detection over UART

Real-time motion detection using a **Digilent Cmod A7** FPGA and a laptop webcam. The PC captures video and reduces each frame to a 40×30 grid of block brightness values. The FPGA runs the motion-detection algorithm in hardware and returns a per-block motion map, which the PC overlays on the live video.

<img width="1211" height="507" alt="Screenshot 2026-04-03 143245" src="https://github.com/user-attachments/assets/e76e779a-baaf-4a09-b587-4804ff65d014" />


---

## Table of Contents

- [Overview](#overview)
- [How It Works](#how-it-works)
- [System Architecture](#system-architecture)
- [UART Protocol](#uart-protocol)
- [Repository Structure](#repository-structure)
- [Hardware Requirements](#hardware-requirements)
- [Getting Started](#getting-started)
- [Configuration](#configuration)
- [Simulation](#simulation)
- [Troubleshooting](#troubleshooting)
- [Known Limitations](#known-limitations)
- [Future Work](#future-work)
---

## Overview

| Item | Detail |
|---|---|
| Board | Digilent Cmod A7 (12 MHz system clock) |
| HDL | Verilog |
| PC software | Python (OpenCV, NumPy, PySerial) |
| Link | USB-UART, 921600 baud, 8 data bits, no parity |
| Resolution | 640×480 input, reduced to 40×30 blocks (16×16 pixels each) |
| Algorithm | Per-block background model with 4 clusters (running average + oldest-cluster replacement) |
| Storage | Block RAM: 1200 entries × (4 × 8-bit centroids + 4 × 16-bit frame numbers) |

The design offloads the per-block classification to the FPGA, while the PC handles camera capture, pre-processing, and visualisation.

## How It Works

1. **Capture and reduce (PC).** Each webcam frame is resized to 640×480, converted to grayscale, and averaged over 16×16 pixel blocks, producing 1200 values (one byte per block) in row-major order.
2. **Stream to FPGA.** The 1200 bytes are sent over UART.
3. **Classify (FPGA).** For every incoming block the FPGA:
   - reads that block's 4 stored background clusters from BRAM,
   - computes the absolute difference between the new value and each cluster centroid,
   - **if any difference is below the threshold:** the block is *background*. The matching cluster is updated with `(old + new) / 2` and its frame number is refreshed,
   - **otherwise:** the block is *motion*. The oldest cluster (lowest frame number) is replaced with the new value,
   - writes the updated clusters back to BRAM.
4. **Reply.** The FPGA sends one byte per block: `0xFF` = motion, `0x00` = background.
5. **Display (PC).** Motion blocks are highlighted in red over the live video, with a separate binary motion-mask window, FPS counter, and a "MOTION DETECTED" banner.

Using several clusters per block lets the model learn repeating background states (for example a flickering light or a swaying object) instead of flagging them as motion forever.

## System Architecture

```
 ┌────────────────────┐      UART 921600 8N1       ┌───────────────────────────────────────┐
 │  Laptop (Python)   │ ─────── 1200 bytes ──────► │             Cmod A7 FPGA              │
 │                    │                            │                                       │
 │  Webcam → resize → │                            │  uart_rx ─► top_module FSM            │
 │  grayscale → 16x16 │                            │                │                      │
 │  block average     │                            │      ┌─────────┴─────────┐            │
 │                    │                            │      ▼                   ▼            │
 │  Overlay + mask  ◄─┼──── 1200 bytes (FF / 00) ──┤  bram_controller ◄► motion_detect_core│
 │  display           │                            │      (1200 blocks)    (4-cluster model)│
 └────────────────────┘                            │                │                      │
                                                   │             uart_tx ──► reply byte    │
                                                   └───────────────────────────────────────┘
```

### Verilog Modules

| Module | File | Purpose |
|---|---|---|
| `top_module` | `top_module.v` | Top level and control FSM (`IDLE → READ_RAM → PROCESS → WRITE_RAM → SEND_UART`), block and frame counters, status LEDs |
| `motion_detect_core` | `motion_detect_core.v` | Combinational difference/match logic and synchronous cluster update |
| `bram_controller` | `bram_controller.v` | Inferred block RAM holding centroids and frame numbers for 1200 blocks |
| `uart_rx` | `uart_rx.v` | UART receiver with 2-flop input synchroniser and mid-bit sampling |
| `uart_tx` | `uart_tx.v` | UART transmitter with busy flag |

**Status LEDs:** `led[0]` shows the latest motion result; `led[1]` is a heartbeat that toggles every 16 frames.

## UART Protocol

| Direction | Payload | Meaning |
|---|---|---|
| PC → FPGA | 1 byte per block | Average grayscale value (0–255) of a 16×16 block |
| FPGA → PC | 1 byte per block | `0xFF` = motion, `0x00` = background |

- A frame is exactly **1200 blocks**, sent in row-major order (block 0 = top-left, block 1199 = bottom-right).
- The FPGA keeps its own running block counter that wraps from 1199 to 0 and increments the frame number. There is no explicit frame-start marker, so the PC and FPGA must stay in step (see [Known Limitations](#known-limitations)).
- The PC sends **2 stop bits** (8N2). This gives the FPGA enough time between bytes to finish transmitting each reply. See [Troubleshooting](#troubleshooting).

## Repository Structure

> Adjust to match your repository layout.

```
.
├── rtl/
│   ├── top_module.v
│   ├── motion_detect_core.v
│   ├── bram_controller.v
│   ├── uart_rx.v
│   └── uart_tx.v
├── tb/
│   ├── top_module_tb.v
│   ├── motion_detect_core_tb.v
│   ├── bram_controller_tb.v
│   ├── uart_rx_tb.v
│   └── uart_tx_tb.v
├── constraints/
│   └── cmod_a7_motion.xdc
├── python/
│   └── motion_detect_pc.py
└── README.md
```

## Hardware Requirements

- Digilent **Cmod A7** (micro-USB cable, no extra wiring needed. The on-board USB-UART bridge is used)
- Laptop or PC with a webcam
- Xilinx **Vivado** (to synthesise and program the board)

## Getting Started

### 1. Build and program the FPGA

1. Create a new Vivado project for your Cmod A7 part.
2. Add all files from `rtl/` as design sources and `constraints/cmod_a7_motion.xdc` as the constraints file.
3. Set `top_module` as the top module.
4. Run synthesis, implementation, and generate the bitstream.
5. Program the device through Hardware Manager.

### 2. Install the Python dependencies

```bash
pip install opencv-python numpy pyserial
```

### 3. Find your COM port

- **Windows:** Device Manager → *Ports (COM & LPT)* (this project's default is `COM5`)
- **Linux/macOS:** typically `/dev/ttyUSB*` or `/dev/tty.usbserial-*`

Close any other program using the port (serial terminals, Vivado terminal, old Python windows).

### 4. Run

```bash
python python/motion_detect_pc.py                    # COM5, camera 0
python python/motion_detect_pc.py --port COM4 --camera 1
python python/motion_detect_pc.py --sim              # software model, no FPGA needed
```

Press **q** or **Esc** to quit.

### Command-line options

| Option | Default | Description |
|---|---|---|
| `--port` | `COM5` | Serial port of the Cmod A7 |
| `--baud` | `921600` | Baud rate (must match `BAUD_RATE` in `top_module.v`) |
| `--camera` | `0` | Camera index |
| `--stopbits` | `2` | UART stop bits sent to the FPGA (1 or 2) |
| `--min-blocks` | `10` | Number of motion blocks required to show the on-screen banner |
| `--sim` | off | Use a Python model of the FPGA instead of real hardware |

## Configuration

| Parameter | Location | Default | Effect |
|---|---|---|---|
| `CLK_FREQ` | `top_module.v` | `12000000` | System clock in Hz |
| `BAUD_RATE` | `top_module.v` | `921600` | UART speed. Change the Python `--baud` to match |
| `THRESHOLD` | `motion_detect_core.v` | `120` | Max brightness difference still treated as background. **Lower = more sensitive** |

> **Tip:** `120` is fairly insensitive. Values around 30–40 respond to smaller movements. If you change `THRESHOLD` in the Verilog, update `FpgaModel.THRESHOLD` in the Python script as well so `--sim` stays consistent.

## Simulation

A testbench is provided for each module in `tb/`. Run them in the Vivado simulator (or any Verilog simulator such as Icarus Verilog).

| Testbench | Verifies |
|---|---|
| `uart_rx_tb.v` | Byte reception |
| `uart_tx_tb.v` | Byte transmission |
| `bram_controller_tb.v` | Read/write behaviour |
| `motion_detect_core_tb.v` | Match, update, and replace logic |
| `top_module_tb.v` | End-to-end: bytes in over UART, motion/background byte out |

## Troubleshooting

**`PermissionError(13, 'Access is denied.')` on COM5**
Another program already has the port open. Close serial terminals and old Python windows, unplug and replug the board, and confirm the port number in Device Manager.

**`FPGA returned N/1200 bytes`**
Bytes were lost, so the PC and FPGA are now out of step. Press the **reset button** on the Cmod A7 and restart the script. The script sends 2 stop bits by default to prevent this. Because the FPGA's reply takes slightly longer than a back-to-back 8N1 byte, it can otherwise miss incoming bytes.

**Nothing detected / everything flagged as motion**
Check `THRESHOLD`. Camera auto-exposure and auto-white-balance can also shift brightness across the whole frame, so give the camera a second or two to settle.

**Camera will not open**
Try another index with `--camera 1`, and make sure no other application is using the webcam.

## Known Limitations

- **No resynchronisation.** The protocol has no frame-start marker. If a byte is ever lost, the FPGA must be reset.
- **Frame counter wraps.** The frame number is 16 bits, so it wraps after 65,535 frames (roughly 36 minutes at 30 FPS). The "oldest cluster" comparison does not account for wrap-around, which could cause a brief period of odd cluster replacement.
- **First-frame behaviour.** BRAM starts at zero, so blocks brighter than the threshold in the very first frame are reported as motion until the model has learned the scene.
- **Global brightness changes** (lights switching, auto-exposure) can flag large regions as motion.
- **Throughput** is bounded by UART speed and USB latency, not by the FPGA logic.

## Future Work

- Add a frame-start / sync byte so the link can recover from dropped bytes automatically
- Allow the main FSM to accept the next byte while the previous reply is still transmitting
- Make `THRESHOLD` adjustable at runtime over UART
- Wrap-safe frame-number comparison
- Higher-throughput interface (for example a faster USB-UART or SPI) and higher resolution
