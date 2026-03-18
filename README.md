# Model Dashboard

A native macOS monitoring dashboard for local AI model infrastructure. See all your running models, system metrics, and hardware status in one glance.

![macOS](https://img.shields.io/badge/macOS-15%2B-blue) ![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-required-green) ![Swift 6](https://img.shields.io/badge/Swift-6.0-orange)

## Features

### Model Discovery
- **Automatic process detection** — keyword-driven classifier recognizes 40+ AI frameworks: Ollama, MLX LM, LM Studio, llama.cpp, vLLM, KoboldCPP, ComfyUI, Stable Diffusion, and more
- **Ollama integration** — shows model names, quantization, VRAM usage, and expiry countdown via the Ollama API
- **Service health checks** — HTTP health monitoring for detected services with ports
- **Unknown large process alerts** — flags any process using >1GB memory that isn't classified

### System Metrics (1-2s refresh)
- **CPU** — per-core utilization grid with P-core/E-core separation
- **GPU** — utilization %, power draw (W), P-state distribution via IOReport
- **Unified Memory** — segmented bar showing Models / Apps / System / Cache / Free
- **Temperature** — CPU/GPU die temps (avg/P90/max) via SMC, SSD and ambient via HID
- **Throttle detection** — thermal state, GPU frequency ratio, CLTM, CPU cluster throttling
- **Network I/O** — upload/download throughput with sparklines
- **Disk I/O** — read/write throughput with sparklines

### Design
- Full-screen dark monitoring panel with monospace typography
- Color-coded status indicators (green/yellow/red)
- 60-point sparkline history graphs
- Graceful degradation when hardware APIs are unavailable

## Requirements

- **macOS 15.0+** (Sequoia)
- **Apple Silicon** (M1/M2/M3/M4 family)
- Non-sandboxed (uses private IOReport and HID APIs for GPU/temperature metrics)

## Build from Source

```bash
# Clone
git clone https://github.com/kyle1492/model-dashboard.git
cd model-dashboard

# Generate Xcode project (requires XcodeGen)
brew install xcodegen
xcodegen generate

# Build and run
open ModelDashboard.xcodeproj
# Press Cmd+R in Xcode
```

Or build from command line:
```bash
xcodebuild -project ModelDashboard.xcodeproj -scheme ModelDashboard -configuration Release build
```

## Architecture

```
ModelDashboard/
├── Discovery/          # Process scanning, classification, port mapping
├── Metrics/            # CPU, GPU (IOReport), temperature (SMC/HID), network, disk, throttle
├── Models/             # Data types (process, system, Ollama)
├── Services/           # Ollama HTTP client, health checker
├── ViewModels/         # SystemMonitor (polling scheduler + state)
└── Views/              # SwiftUI views (dashboard, cards, grids, sparklines)
```

**Polling cadence:**
- 1s: CPU, GPU, network
- 2s: processes, memory, disk, temperature, throttle
- 5s: Ollama API, port mapping, service enrichment

## Notes

- This app uses **private Apple APIs** (IOReport for GPU metrics, HID for temperature sensors). These work without sudo but are not part of the public SDK.
- GPU metrics require IOReport framework (`-lIOReport`), available on Apple Silicon Macs.
- Temperature reading uses SMC for CPU/GPU die temps and HID for SSD/ambient.
- The app runs **outside the sandbox** to access system-level APIs (`proc_pidinfo`, `host_processor_info`, etc.).

## License

MIT
