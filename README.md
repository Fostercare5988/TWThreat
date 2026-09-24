# TWThreat

[![Interface: 1.12.1](https://img.shields.io/badge/Interface-1.12.1%20(5875)-orange.svg)](https://github.com/Fostercare5988/TWThreat)
[![Version: 1.4.0](https://img.shields.io/badge/Version-1.4.0-blue.svg)](https://github.com/Fostercare5988/TWThreat/releases)
[![ClassicAPI: v1.14.0+](https://img.shields.io/badge/ClassicAPI-v1.14.0+-green.svg)](https://github.com/brues-code/ClassicAPI)
[![SuperWoW: v2.2+](https://img.shields.io/badge/SuperWoW-v2.2+-brightgreen.svg)](https://github.com/balakethelock/SuperWoW)
[![NamPower: v4.6.3+](https://img.shields.io/badge/NamPower-v4.6.3+-blueviolet.svg)](https://github.com/Emyrk/nampower)
[![UnitXP: SP3](https://img.shields.io/badge/UnitXP-SP3-teal.svg)](https://github.com/brues-code/UnitXP_SP3)
[![DXVK: Vulkan](https://img.shields.io/badge/DXVK-Vulkan-red.svg)](https://github.com/doitsujin/dxvk)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

**TWThreat v1.4.0** is an enterprise-grade, real-time threat metering engine engineered natively for **World of Warcraft 1.12.1 (Build 5875)** running on the **Enhanced Client Extension Stack** (**ClassicAPI v1.14.0+**, **SuperWoW v2.2+**, **NamPower 4.6.3+**, **UnitXP SP3**, and **DXVK**).

TWThreat provides instantaneous server-authoritative threat tracking, eliminates combat garbage collection stutter, delivers smooth bar animations, and provides direct SuperWoW GUID targeting.

Created and actively maintained by **[Fostercare5988](https://github.com/Fostercare5988)**.

---

## 🚀 Engine Architecture & Performance

TWThreat is engineered around strict low-level system integration:

| Engine Component | Minimum Version | Architectural Role & Implementation |
| :--- | :--- | :--- |
| **ClassicAPI** | `v1.14.0+` | C++ hardware timers, native `table.wipe` memory recycling, and source-rewritten Lua 5.1 syntax. |
| **SuperWoW** | `v2.2+` | Direct memory state access, `TargetUnit(guid)` instant mob targeting, and zero-latency threat synchronization. |
| **NamPower** | `v4.6.3+` | Microsecond-precision combat pipeline and frame-0 event dispatching. |
| **UnitXP** | `SP3` | High-precision unit inspection and exact threat percentage calculation. |
| **DXVK** | `Latest` | Decoupled high-refresh rendering with zero garbage collection heap churn and normalized delta-time bar animations. |

### Elimination of 2006 Legacy Techniques
- **Zero Combat GC Churn**: Eradicated dynamic table allocations during combat. Employs pre-allocated recycling pools (`threatPool`, `tankModePool`, `sortList`) and single-pass string parsing, eliminating frame drops in 40-man raids.
- **Delta-Time Decoupled Frame Smoothing**: Bar animations and glow transitions use normalized delta-time (`dt`) exponential smoothing, guaranteeing stutter-free rendering under DXVK and Vulkan.
- **SuperWoW Direct GUID Targeting**: Tank Mode utilizes SuperWoW's `TargetUnit(guid)` API for instant, 100% reliable targeting of specific mobs in multi-mob packs without fuzzy targeting errors.
- **Zero pfUI Bloat & Clean XML**: Completely eliminated legacy pfUI dependencies, unresolved frame anchors (`pfTarget`), and dead texture assets, ensuring zero errors in `FrameXML.log`.

---

## ⚡ Key Features

### 1. Threat Tracking & Target Frame Integration
- **Server-Authoritative Threat Tracking**: Direct integration with the server-side threat protocol (`TWT_UDTSv4` / `TWTv4=`), providing 100% accurate threat values without legacy KTM combat log desync.
- **Target Frame Threat Integration**:
  - **Threat Glow**: Visual threat border aura on your target frame (Green -> Yellow -> Red).
  - **Numeric Percentage Badge**: Real-time numerical threat percentage displayed directly on the target frame.
  - **Optional Target Anchor**: Uses `FostercareTweaks.GetActiveTargetFrame()` when available; otherwise anchors to Blizzard's `TargetFrame`.

### 2. Multi-Target Tank Mode & Alerts
- **Multi-Target Tank Mode**: Companion HUD displaying real-time threat status across all active tanked mobs, with direct GUID targeting.
- **Threat Alerts & Warnings**:
  - **Full Screen Glow**: Fullscreen vignette pulse when nearing or exceeding threat threshold.
  - **Audio Warnings**: Configurable audio alarm when reaching critical aggro transition percentages.

---

## ⌨️ Slash Commands & Configuration Matrix

Use `/twt` or `/twtshow`:

| Command / Action | Description |
| :--- | :--- |
| `/twt` or `/twt show` | Shows / hides the main threat window |
| `/twtshow` | Toggles visibility of the threat window |
| `/twt tankmode` | Toggles the Tank Mode companion window |
| `/twt who` | Inspects addon versions across party and raid members |
| `/twt debug` | Toggles debug traffic monitor |
| `Gear Icon` | Opens frame settings (bar height, scale, font, alpha, columns, thresholds) |
| `Padlock Icon` | Toggles window movement lock |
| `Tank Mode Bar Click` | Targets that specific creature directly via `TargetUnit(guid)` |

---

## 📦 Installation & Engine Prerequisites

### Prerequisites
1. **World of Warcraft 1.12.1** (Build 5875).
2. [**ClassicAPI v1.14.0+**](https://github.com/brues-code/ClassicAPI) (`ClassicAPI.dll`).
3. [**SuperWoW v2.2+**](https://github.com/balakethelock/SuperWoW) (`SuperWoW.dll`).
4. [**NamPower v4.6.3+**](https://github.com/Emyrk/nampower) (`nampower.dll`).
5. [**UnitXP SP3**](https://codeberg.org/konaka/UnitXP_SP3) (`UnitXP_SP3.dll`).
6. [**DXVK**](https://github.com/doitsujin/dxvk) & [**VanillaFixes**](https://github.com/hannesmann/vanillafixes).

### Step-by-Step Installation
1. Clone or download the repository into your WoW AddOns directory:
   ```text
   World of Warcraft/Interface/AddOns/TWThreat/
   ```
2. Verify that `TWThreat.toc` is located directly at:
   ```text
   World of Warcraft/Interface/AddOns/TWThreat/TWThreat.toc
   ```
3. Launch the game using your DLL loader or launcher with ClassicAPI and SuperWoW enabled.
4. Ensure **TWThreat** is checked in the character selection AddOn screen.

---

## 📜 Changelog

### v1.4.0
- **Numeric Engine Startup Guard**: Upgraded initialization guard with strict numeric boundary validation (`MIN_CLASSIC_API = 11400` and `SUPERWOW_VERSION`).
- **Modern Lua 5.1 Syntax & Table Operations**: Eradicated legacy `table.getn` and `table.setn` constructs in favor of native `#` length operator and active-range sorting.
- **Enhanced Memory Recycling**: Integrated native C++ `table.wipe` into `TWT.queryWho`, `TWT.spec`, and `barAnimator` lifecycle resets.
- **Clean TOC Metadata**: Removed legacy high-refresh marketing notations from `.toc` notes in compliance with clean DXVK standards.

### v1.3.0
- **Universal Engine Guard**: Enforced strict dependency check for ClassicAPI v1.14.0+ and SuperWoW v2.2+ at initialization.
- **Unconditional C++ Memory Operations**: Simplified `TWT.combatEnd` to unconditionally invoke native C++ `table.wipe(TWT.history)`.
- **Single Branch Git Standardization**: Consolidated repository to strictly maintain 1 branch (`main`).
- **Updated Documentation**: Fully aligned README with ClassicAPI v1.14.0+ and SuperWoW v2.2+ standards.

### v1.2.0
- Upgraded startup dependency guard to inspect `CLASSIC_API_VERSION` and `SUPERWOW_VERSION` globals directly.
- Normalized TOC metadata and title to clean standard naming (`TWThreat`).
- Updated documentation with DXVK engine badge and direct repository hyperlinks for all DLL prerequisites.

### v1.1.0
- Verified zero-GC threat recycling pools and delta-time animation smoothing.
- Updated TOC metadata and published comprehensive technical README documentation.

---

## 📄 License & Community

- **Original Authors**: **Xerron**, **Er**, **CosminPOP**
- **Author & Maintainer**: **[Fostercare5988](https://github.com/Fostercare5988)**
- **GitHub Repository**: [https://github.com/Fostercare5988/TWThreat](https://github.com/Fostercare5988/TWThreat)
- **License**: MIT License - See [LICENSE](LICENSE) for details.
