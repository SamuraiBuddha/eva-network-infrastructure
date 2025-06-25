# Workstation Configurations

This directory contains hardware configurations, benchmarks, and system tuning for EVA Network workstations following the Three Wise Men (Magi) naming scheme.

## 🖥️ System Inventory

### 🏛️ Melchior (Gold) - CAD/3D Processing Station
- **CPU**: Intel Core i9-11900K (11th Gen)
- **RAM**: 64GB DDR4-4600 (G.Skill F4-4600C19-16GTZR x2)
- **GPU**: NVIDIA GeForce RTX 3090 (24GB)
- **Motherboard**: ASUS ROG Strix Z590-E Gaming WiFi
- **PSU**: 1200W ASUS ROG Thor
- **Role**: Digital craftsmanship and precision engineering
- **Gift**: Gold (enduring technical excellence)
- **Focus**: Autodesk Suite, SolidWorks, Point Cloud Processing

### 🔮 Balthazar (Frankincense) - AI Model Host
- **CPU**: Intel Core i9-11900K (11th Gen)
- **RAM**: 128GB DDR4-3600 (G.Skill F4-3600C18-32GTZN)
- **GPU**: NVIDIA RTX A5000 (24GB ECC)
- **Motherboard**: ASUS ROG Maximus XIII Hero
- **PSU**: 1200W ASUS ROG Thor
- **Role**: Intelligence elevation and model serving
- **Gift**: Frankincense (transforming data into insights)
- **Focus**: AI Training, Model Hosting, CUDA Workloads

### ⚗️ Caspar (Myrrh) - Code Generation & Data Processing
- **CPU**: AMD Ryzen 9 5950X (16C/32T)
- **RAM**: 128GB DDR4-3600 (G.Skill F4-3600C18Q-128GTZRS)
- **GPU**: NVIDIA RTX A4000 (16GB)
- **Motherboard**: ASUS ROG Crosshair VIII Formula
- **PSU**: 1600W
- **Role**: Systematic transformation and automation
- **Gift**: Myrrh (preserving and transforming processes)
- **Focus**: Development, Data Processing, Virtualization

## 📂 Directory Structure

```
workstations/
├── melchior/
│   ├── hardware/
│   │   ├── hwinfo-report.csv
│   │   ├── aida64-full.txt
│   │   ├── cpu-z.txt
│   │   └── gpu-z.xml
│   ├── bios/
│   │   ├── current-settings.CMO
│   │   └── profiles/
│   ├── benchmarks/
│   │   ├── aida64/
│   │   ├── 3dmark/
│   │   └── cad-benchmarks/
│   └── docker/
│       ├── docker-info.json
│       └── compose-overrides.yml
│
├── balthazar/
│   ├── hardware/
│   ├── bios/
│   ├── benchmarks/
│   │   └── ml-benchmarks/
│   └── docker/
│
└── caspar/
    ├── hardware/
    ├── bios/
    ├── benchmarks/
    └── docker/
```

## 🔧 Usage

### Collecting System Information

```powershell
# Run from each machine
.\scripts\collect-system-info.ps1 -MachineName "melchior"
.\scripts\collect-system-info.ps1 -MachineName "balthazar"
.\scripts\collect-system-info.ps1 -MachineName "caspar"
```

### BIOS Configuration Export

For ASUS boards:
1. Enter BIOS (DEL key during boot)
2. Press F7 for Advanced Mode
3. Navigate to Tool → ASUS User Profile
4. Save Profile to USB drive
5. Copy .CMO file to `workstations/[magi-name]/bios/`

### Benchmarking

```powershell
# Full benchmark suite
.\scripts\benchmark-suite.ps1 -All

# Specific benchmarks
.\scripts\benchmark-suite.ps1 -GPU -Storage
```

## 🎁 The Three Gifts

Each machine brings its unique computational gift to the homelab, just as the Magi brought their gifts:
- **Melchior's Gold**: Enduring precision in CAD/3D work
- **Balthazar's Frankincense**: Transforming raw data into AI insights
- **Caspar's Myrrh**: Preserving and transforming code and processes

## 📊 Performance Baselines

| Component | Melchior (CAD) | Balthazar (AI) | Caspar (Code) |
|-----------|----------------|----------------|---------------|
| CPU Score | TBD | TBD | TBD |
| GPU Score | TBD | TBD | TBD |
| RAM Latency | TBD | TBD | TBD |
| NVMe Read | TBD | TBD | TBD |
| Network Throughput | TBD | TBD | TBD |

## 🔗 Integration with Docker Compose

In your project repositories (like CORTEX), reference this repo:

```yaml
# docker-compose.yml
x-machine-config:
  melchior: &melchior
    extends:
      file: ${EVA_NETWORK_PATH}/workstations/melchior/docker/compose-overrides.yml
      service: gpu-compute
  
  balthazar: &balthazar
    extends:
      file: ${EVA_NETWORK_PATH}/workstations/balthazar/docker/compose-overrides.yml
      service: ai-inference
  
  caspar: &caspar
    extends:
      file: ${EVA_NETWORK_PATH}/workstations/caspar/docker/compose-overrides.yml
      service: cpu-intensive
```

```bash
# .env
EVA_NETWORK_PATH=../eva-network-infrastructure
MACHINE_ID=melchior  # or balthazar, caspar
```

## 📝 Notes

- All sensitive information (passwords, keys) should be stored in `.env` files (gitignored)
- BIOS profiles are machine-specific and should only be restored to identical hardware
- Benchmark results should include ambient temperature and timestamp
- The Magi naming convention honors the Three Wise Men's gifts of expertise

## 🔒 Security

- This directory contains hardware configurations only
- No credentials, keys, or sensitive data
- BIOS passwords are not stored (document separately)
- Network topology excludes sensitive routing info

---

> **Note**: This content was migrated from the `homelab-infrastructure` repository as part of the infrastructure consolidation effort. The original repository can be archived.
