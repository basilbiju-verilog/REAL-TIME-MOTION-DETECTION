"""
Laptop-camera motion detection using the FPGA (Cmod A7) over UART.

Protocol (matches top_module.v):
  PC -> FPGA : 1 byte per block = average grayscale (0-255) of a 16x16 pixel block
  FPGA -> PC : 1 byte per block = 0xFF (motion) or 0x00 (background)
  Frame      : 640x480 -> 40 x 30 = 1200 blocks, sent row-major (block 0..1199)
  UART       : 921600 baud, 8N1

Install:  pip install opencv-python numpy pyserial
Run:      python motion_detect_pc.py              (uses COM5)
          python motion_detect_pc.py --port COM5 --camera 0
          python motion_detect_pc.py --sim        (no FPGA, software model of it)

Keys: q or ESC = quit
NOTE: the FPGA keeps a running block counter. If a byte is ever lost the PC and
FPGA get out of step - press the reset button on the board and restart the script.
"""

import argparse
import os
import sys
import time

import cv2
import numpy as np

# ----------------------------------------------------------------------------
# Constants (must match the Verilog design)
# ----------------------------------------------------------------------------
FRAME_W, FRAME_H = 640, 480
BLOCK = 16
COLS, ROWS = FRAME_W // BLOCK, FRAME_H // BLOCK      # 40 x 30
NUM_BLOCKS = COLS * ROWS                              # 1200
MOTION_BYTE = 0xFF


# ----------------------------------------------------------------------------
# Image -> 1200 block bytes
# ----------------------------------------------------------------------------
def frame_to_blocks(frame_bgr):
    """Return a (ROWS, COLS) uint8 array of per-block average grayscale."""
    frame = cv2.resize(frame_bgr, (FRAME_W, FRAME_H))
    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    # INTER_AREA down-scaling = exact average over each 16x16 block
    return cv2.resize(gray, (COLS, ROWS), interpolation=cv2.INTER_AREA), frame


# ----------------------------------------------------------------------------
# Software model of the FPGA (for --sim testing without hardware)
# ----------------------------------------------------------------------------
class FpgaModel:
    THRESHOLD = 120

    def __init__(self):
        self.cent = np.zeros((NUM_BLOCKS, 4), dtype=np.int32)
        self.fnum = np.zeros((NUM_BLOCKS, 4), dtype=np.int32)
        self.frame_counter = 1
        self.block = 0

    def process(self, data):
        out = bytearray()
        for v in data:
            c, f, b = self.cent[self.block], self.fnum[self.block], self.block
            match = np.where(np.abs(c - v) < self.THRESHOLD)[0]
            if len(match):
                i = match[0]
                c[i] = (c[i] + v) >> 1
                f[i] = self.frame_counter
                out.append(0x00)
            else:
                i = int(np.argmin(f))          # oldest (first minimum)
                c[i] = v
                f[i] = self.frame_counter
                out.append(MOTION_BYTE)
            self.block += 1
            if self.block == NUM_BLOCKS:
                self.block = 0
                self.frame_counter += 1
        return bytes(out)


# ----------------------------------------------------------------------------
# FPGA link
# ----------------------------------------------------------------------------
class FpgaLink:
    def __init__(self, port, baud, sim=False, stopbits=2):
        self.sim = sim
        if sim:
            self.model = FpgaModel()
            self.ser = None
        else:
            import serial
            # 2 stop bits = 1 extra bit of idle time after every byte. The FPGA
            # needs this: its reply (TX) is slightly slower than 8N1 bytes
            # arriving back-to-back, so with 1 stop bit it misses bytes.
            sb = serial.STOPBITS_TWO if stopbits == 2 else serial.STOPBITS_ONE
            self.ser = serial.Serial(port, baud, bytesize=8, parity="N",
                                     stopbits=sb, timeout=1.0, write_timeout=2.0)
            time.sleep(0.2)
            self.ser.reset_input_buffer()
            self.ser.reset_output_buffer()

    def process_frame(self, blocks):
        """Send 1200 bytes, return a (ROWS, COLS) bool array of motion flags."""
        payload = blocks.astype(np.uint8).tobytes()
        if self.sim:
            resp = self.model.process(payload)
        else:
            self.ser.write(payload)
            self.ser.flush()
            resp = self.ser.read(NUM_BLOCKS)      # waits up to timeout
        if len(resp) != NUM_BLOCKS:
            raise IOError(f"FPGA returned {len(resp)}/{NUM_BLOCKS} bytes "
                          "(press the FPGA reset button and restart)")
        return (np.frombuffer(resp, dtype=np.uint8) == MOTION_BYTE).reshape(ROWS, COLS)

    def close(self):
        if self.ser:
            self.ser.close()


# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------
def open_camera(index):
    cap = cv2.VideoCapture(index, cv2.CAP_DSHOW) if os.name == "nt" else cv2.VideoCapture(index)
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, FRAME_W)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, FRAME_H)
    return cap


def main():
    ap = argparse.ArgumentParser(description="FPGA motion detection with laptop camera")
    ap.add_argument("--port", default="COM5", help="serial port (default COM5)")
    ap.add_argument("--baud", type=int, default=921600)
    ap.add_argument("--camera", type=int, default=0, help="camera index (default 0)")
    ap.add_argument("--stopbits", type=int, choices=(1, 2), default=2,
                    help="UART stop bits sent to FPGA (default 2, avoids lost bytes)")
    ap.add_argument("--sim", action="store_true", help="use software model instead of FPGA")
    ap.add_argument("--min-blocks", type=int, default=10,
                    help="blocks needed to show the MOTION banner (default 10)")
    args = ap.parse_args()

    cap = open_camera(args.camera)
    if not cap.isOpened():
        sys.exit(f"ERROR: cannot open camera {args.camera}")

    try:
        link = FpgaLink(args.port, args.baud, sim=args.sim, stopbits=args.stopbits)
    except Exception as e:
        cap.release()
        sys.exit(f"ERROR: cannot open {args.port}: {e}\n"
                 "Check the COM port in Device Manager and that no other program uses it.")

    print(f"Camera {args.camera} OK. Link: {'SIMULATION' if args.sim else args.port}. Press q to quit.")
    fps, last = 0.0, time.time()
    frame_no = 0

    try:
        while True:
            ok, frame = cap.read()
            if not ok:
                print("Camera read failed")
                break

            blocks, frame = frame_to_blocks(frame)

            try:
                motion = link.process_frame(blocks)
            except IOError as e:
                print("ERROR:", e)
                break

            frame_no += 1
            n_motion = int(motion.sum())

            # Overlay motion blocks in red
            mask = cv2.resize(motion.astype(np.uint8) * 255, (FRAME_W, FRAME_H),
                              interpolation=cv2.INTER_NEAREST)
            overlay = frame.copy()
            overlay[mask > 0] = (0, 0, 255)
            view = cv2.addWeighted(overlay, 0.45, frame, 0.55, 0)

            now = time.time()
            fps = 0.9 * fps + 0.1 * (1.0 / max(now - last, 1e-6))
            last = now

            detected = n_motion >= args.min_blocks
            cv2.putText(view, f"FPS {fps:4.1f}  blocks {n_motion}", (10, 25),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 255, 0), 2)
            if detected:
                cv2.putText(view, "MOTION DETECTED", (10, 55),
                            cv2.FONT_HERSHEY_SIMPLEX, 0.9, (0, 0, 255), 2)

            cv2.imshow("Motion (FPGA)", view)
            cv2.imshow("Motion mask", mask)

            key = cv2.waitKey(1) & 0xFF
            if key in (ord("q"), 27):
                break
    finally:
        link.close()
        cap.release()
        cv2.destroyAllWindows()


if __name__ == "__main__":
    main()
