# Lab 4-2 FIR Accelerator Implementation

## Directory Structure
```
Lab4-2/
├─ src/                     # All source code
│  ├─ cvc-pdk/             # PDK related files
│  ├─ firmware/           # Firmware code (C implementation)
│  ├─ rtl/                # RTL design files
│  ├─ testbench/          
│  │  └─ counter_la_fir/  # Testbench (optimized version)
│  ├─ vip/                # Verification IP components
│  └─ vivado/             # Vivado project files
├─ waveform/              # Reference waveforms (debugging only)
└─ README.md
```

## Execute FIR Code in User BRAM

### Simulation for FIR

To simulate the FIR design, follow these steps:

```sh
cd testbench/counter_la_fir
source run_clean
source run_sim
```


## TODO List
### 1. C Firmware Code
  Implement C firmware to transmit input data and receive output data
  
  This differs from Lab 4.1 where the firmware ran independently

### 2. Wishbone Handshake for BRAM Access
  Design hardware that manages Wishbone handshake to access BRAM
    
  Can reuse implementation from Lab 4.1

### 3. Wishbone to AXI Interface Conversion
  Develop hardware that converts the Wishbone interface to both AXI-Lite and AXI-Stream interfaces

### 4. Wishbone Decoder Design
  Create a Wishbone decoder module to route signals between Wishbone bus and modules (point 2 and point 3)

### 5. FIR Execution Control
  Ensure the FIR filter runs 2 to 3 times per activation
