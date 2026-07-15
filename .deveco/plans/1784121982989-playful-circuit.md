---
name: DevControl Smart Home System Implementation
overview: Implement a complete smart home control system based on the design document, building on the bare Native C++ project template. The system includes 4 core modules (Control Center, Lighting Center, Temperature/Humidity Center, Smart Door Lock), Native C++ layer (TLS, crypto, protocol parser, device simulator), and full UI with ArkTS.
todos:
  - Set up project configuration (module.json5 permissions, main_pages.json, resources)
  - Create ArkTS data models and interfaces (DeviceModel, DeviceStatus, SceneRule, BrandAdapter)
  - Create Native C++ layer (device_simulator, crypto_engine, protocol_parser, tls_client, updated napi_init)
  - Update Native type definitions (Index.d.ts) and oh-package.json5
  - Update CMakeLists.txt for new C++ source files
  - Create DeviceManager business logic (ArkTS)
  - Create common UI components (DeviceCard, GaugeComponent, etc.)
  - Implement Index.ets as Control Center with Tabs navigation
  - Implement LightingPage.ets
  - Implement TemperaturePage.ets
  - Implement DoorLockPage.ets
  - Implement SettingsPage.ets
  - Wire up EntryAbility lifecycle with DeviceManager initialization
  - Verification: arkts_check + build
---

# DevControl Smart Home System — Implementation Plan

## Goal

Transform the bare Native C++ project template into a fully functional smart home control system per the design document, with 4 core modules, Native C++ security/simulation layer, and polished ArkUI.

## Scope / Non-goals

**In scope:**
- 4 core UI pages: Control Center, Lighting Center, Temperature/Humidity Center, Smart Door Lock
- Settings page (basic)
- Native C++ device simulator, crypto engine, protocol parser, TLS client (simulated — no real server)
- NAPI bindings for all Native functions
- ArkTS business logic: DeviceManager, scene management, brand adapters
- Data persistence with Preferences
- INTERNET permission in module.json5
- Resource files (strings, colors)

**Out of scope:**
- Real hardware integration (simulation only)
- Real TLS server / CA certificate management
- RelationalStore for access logs (use Preferences for simplicity in MVP)
- Canvas gauge drawing (use Slider + Text visualization instead for reliability)
- "我的" page deep features (only basic settings skeleton)

## Current State And Constraints

- **Project root**: `C:\Users\RoyCai\Desktop\openHarmonyProject\DevControl\`
- **SDK**: HarmonyOS 6.1.1(24), stage model, BiSheng native compiler
- **Current state**: Bare template with `Index.ets` (Hello World), single NAPI `add()` function
- **ArkTS strictness**: No `any`, no `unknown`, no `as`, no structural typing, no dynamic property access, no template literals. Use named classes/interfaces with `implements`.
- **State management**: V1 decorators (`@State`, `@Prop`, `@Link`, `@Provide`/`@Consume`)
- **Navigation**: Use `Tabs` component on the main page (4 tabs for 4 modules) — simpler and more natural for this mobile app layout than `Navigation` router-based approach.

## Design

### Navigation Architecture

Use `Tabs` as the main navigation on `Index.ets`:
- Tab 1: Control Center (device overview, quick actions)
- Tab 2: Lighting Center (lights control)
- Tab 3: Temperature/Humidity Center (sensor + AC control)
- Tab 4: Smart Door Lock (door status + controls)

Each tab content is a separate `@Component` rendered inline or via `@Builder`. Pages are NOT separate route pages — they are tab contents within the single `Index.ets` entry, which avoids router complexity and enables shared `@Provide`/`@Consume` state.

### State Management

- `DeviceManager` class holds the central device list and operations, decorated with `@Provide` in `Index.ets`
- Child tab components use `@Consume` to access `DeviceManager`
- Individual device state changes use `@State` within each tab component
- `AppStorage` for global app-level state (e.g., TLS connection status)

### Data Flow

```
UI (ArkTS) → DeviceManager (ArkTS) → libentry.so (NAPI) → C++ DeviceSimulator / CryptoEngine / TLSClient
```

- `DeviceManager` calls Native functions to get/set device state
- Device simulator runs tick updates in C++; ArkTS polls via NAPI or uses a timer

### Native C++ Design

Since there's no real TLS server, the TLS client will be **simulated** — it demonstrates the API surface and encryption flow but connects to a mock endpoint. The crypto engine uses a simple AES-like implementation for demonstration. The device simulator manages in-memory device states with tick-based sensor simulation.

**Key C++ classes:**
1. `DeviceSimulator` — manages all simulated devices, tick updates for sensor data
2. `CryptoEngine` — encrypt/decrypt with AES-256 (simplified), HMAC signing, PBKDF2 key derivation
3. `ProtocolParser` — parse/serialize JSON-like device commands
4. `TLSClient` — simulated TLS connection lifecycle

### Brand Adapter Pattern (ArkTS)

Strategy pattern for AC brands:
```typescript
interface BrandAdapter {
  turnOn(): Command;
  turnOff(): Command;
  setTemperature(temp: number): Command;
}
class HaierAdapter implements BrandAdapter { ... }
class GreeAdapter implements BrandAdapter { ... }
class MideaAdapter implements BrandAdapter { ... }
```

### Data Persistence

- `Preferences` for: device list configuration, user settings
- AppStorage + PersistentStorage for: theme, last connected status

## Key Files

### New/Modified ETS Files
- [entry/src/main/ets/pages/Index.ets](entry/src/main/ets/pages/Index.ets) — **Rewrite**: Main page with Tabs navigation
- [entry/src/main/ets/model/DeviceModel.ets](entry/src/main/ets/model/DeviceModel.ets) — **New**: Device/DeviceStatus/DeviceType/SceneRule data models
- [entry/src/main/ets/model/DeviceManager.ets](entry/src/main/ets/model/DeviceManager.ets) — **New**: Central device management logic
- [entry/src/main/ets/model/SceneManager.ets](entry/src/main/ets/model/SceneManager.ets) — **New**: Scene/automation management
- [entry/src/main/ets/model/BrandAdapter.ets](entry/src/main/ets/model/BrandAdapter.ets) — **New**: AC brand adapter interface + implementations
- [entry/src/main/ets/components/ControlCenterTab.ets](entry/src/main/ets/components/ControlCenterTab.ets) — **New**: Tab 1 content
- [entry/src/main/ets/components/LightingTab.ets](entry/src/main/ets/components/LightingTab.ets) — **New**: Tab 2 content
- [entry/src/main/ets/components/TemperatureTab.ets](entry/src/main/ets/components/TemperatureTab.ets) — **New**: Tab 3 content
- [entry/src/main/ets/components/DoorLockTab.ets](entry/src/main/ets/components/DoorLockTab.ets) — **New**: Tab 4 content
- [entry/src/main/ets/components/DeviceCard.ets](entry/src/main/ets/components/DeviceCard.ets) — **New**: Reusable device card component
- [entry/src/main/ets/common/Constants.ets](entry/src/main/ets/common/Constants.ets) — **New**: App constants
- [entry/src/main/ets/entryability/EntryAbility.ets](entry/src/main/ets/entryability/EntryAbility.ets) — **Modify**: Add DeviceManager init in onCreate

### New/Modified C++ Files
- [entry/src/main/cpp/napi_init.cpp](entry/src/main/cpp/napi_init.cpp) — **Rewrite**: Register all NAPI functions
- [entry/src/main/cpp/include/device_simulator.h](entry/src/main/cpp/include/device_simulator.h) — **New**: Device simulator header
- [entry/src/main/cpp/src/device_simulator.cpp](entry/src/main/cpp/src/device_simulator.cpp) — **New**: Device simulator implementation
- [entry/src/main/cpp/include/crypto_engine.h](entry/src/main/cpp/include/crypto_engine.h) — **New**: Crypto engine header
- [entry/src/main/cpp/src/crypto_engine.cpp](entry/src/main/cpp/src/crypto_engine.cpp) — **New**: Crypto engine implementation
- [entry/src/main/cpp/include/protocol_parser.h](entry/src/main/cpp/include/protocol_parser.h) — **New**: Protocol parser header
- [entry/src/main/cpp/src/protocol_parser.cpp](entry/src/main/cpp/src/protocol_parser.cpp) — **New**: Protocol parser implementation
- [entry/src/main/cpp/include/tls_client.h](entry/src/main/cpp/include/tls_client.h) — **New**: TLS client header
- [entry/src/main/cpp/src/tls_client.cpp](entry/src/main/cpp/src/tls_client.cpp) — **New**: TLS client implementation (simulated)
- [entry/src/main/cpp/CMakeLists.txt](entry/src/main/cpp/CMakeLists.txt) — **Modify**: Add new source files

### Configuration/Resource Files
- [entry/src/main/cpp/types/libentry/Index.d.ts](entry/src/main/cpp/types/libentry/Index.d.ts) — **Rewrite**: Full NAPI type definitions
- [entry/src/main/module.json5](entry/src/main/module.json5) — **Modify**: Add INTERNET permission
- [entry/src/main/resources/base/profile/main_pages.json](entry/src/main/resources/base/profile/main_pages.json) — **Keep**: Only Index page needed (Tabs approach)
- [entry/src/main/resources/base/element/string.json](entry/src/main/resources/base/element/string.json) — **Modify**: Add all UI strings
- [entry/src/main/resources/base/element/color.json](entry/src/main/resources/base/element/color.json) — **Modify**: Add theme colors
- [entry/src/main/resources/base/element/float.json](entry/src/main/resources/base/element/float.json) — **Modify**: Add dimension constants

## Execution Sequence

### Step 1: Project Configuration
1. Update `module.json5` — add `ohos.permission.INTERNET` to `requestPermissions`
2. Update `string.json` — add all UI string resources (tab labels, button texts, page titles)
3. Update `color.json` — add theme colors (primary, accent, status colors)
4. Update `float.json` — add dimension constants

### Step 2: Native C++ Layer
1. Create `cpp/include/device_simulator.h` — DeviceSimulator class with registerDevice, updateDevice, getDeviceState, listDevices, tick
2. Create `cpp/src/device_simulator.cpp` — Full implementation with in-memory device map, sensor data simulation formulas
3. Create `cpp/include/crypto_engine.h` — CryptoEngine class with encryptData, decryptData, hmacSign, deriveKey
4. Create `cpp/src/crypto_engine.cpp` — Simplified AES + HMAC implementation using OpenSSL-compatible logic (or simple XOR-based for demo)
5. Create `cpp/include/protocol_parser.h` — ProtocolParser with parseDeviceCommand, serializeCommand
6. Create `cpp/src/protocol_parser.cpp` — JSON-like command parse/serialize
7. Create `cpp/include/tls_client.h` — TLSClient with connect, send, close
8. Create `cpp/src/tls_client.cpp` — Simulated TLS connection (no real SSL, mock the flow)
9. Rewrite `cpp/napi_init.cpp` — Register all NAPI functions: simulateDevice, getDeviceState, updateDevice, listDevices, encryptData, decryptData, parseDeviceCommand, tlsConnect, tlsSend, tlsClose, tick
10. Update `cpp/CMakeLists.txt` — Add all new .cpp sources and include paths
11. Rewrite `cpp/types/libentry/Index.d.ts` — Full type definitions for all exported NAPI functions

### Step 3: ArkTS Data Models & Business Logic
1. Create `ets/common/Constants.ets` — DeviceType enum, brand names, default config values
2. Create `ets/model/DeviceModel.ets` — Device class, DeviceStatus class, SceneRule class, Command class (all using `class` not `interface` for ArkTS compliance)
3. Create `ets/model/BrandAdapter.ets` — BrandAdapter interface + HaierAdapter, GreeAdapter, MideaAdapter classes
4. Create `ets/model/DeviceManager.ets` — Central manager: init default devices, call NAPI for state, manage device list, handle scenes
5. Create `ets/model/SceneManager.ets` — Scene rules management

### Step 4: Common UI Components
1. Create `ets/components/DeviceCard.ets` — Reusable card showing device icon, name, status, quick toggle
2. Create `ets/components/ControlCenterTab.ets` — Device overview grid, online/offline count, quick scene buttons
3. Create `ets/components/LightingTab.ets` — Light list with Toggle switches, Slider for brightness, auto-motion toggle
4. Create `ets/components/TemperatureTab.ets` — Current temp/humidity display, AC control panel (power toggle, temp slider, mode select, brand select)
5. Create `ets/components/DoorLockTab.ets` — Large lock icon, lock/unlock button, access log list, alert list

### Step 5: Main Page & Wiring
1. Rewrite `ets/pages/Index.ets` — Tabs with 4 TabContent items, each using the tab components above. `@Provide` DeviceManager.
2. Modify `ets/entryability/EntryAbility.ets` — Initialize DeviceManager and call Native init in onCreate, set up periodic tick timer

### Step 6: Verification
1. Run `arkts_check` on all `.ets` files
2. Build the project

## Verification

| Check | Method | Pass Criteria |
|-------|--------|---------------|
| ArkTS syntax | `arkts_check` on all .ets files | Zero errors |
| C++ compilation | `build_project` | Build succeeds |
| NAPI binding | Build + runtime | No "module not found" crash |
| UI render | Manual / preview | 4 tabs visible, device cards render |
| Device simulation | Runtime | Toggle switches change device state, sensor values update |

## Risks And Compatibility

- **SDK version**: Targeting 6.1.1(24). All APIs used must be available in this SDK version.
- **OpenSSL in C++**: The BiSheng compiler may not ship OpenSSL headers. If AES/crypto compilation fails, fall back to a simple XOR-based demo encryption.
- **ArkTS strictness**: No `any`, no template literals — all string concatenation uses `+`. All data structures use named `class` with explicit fields.
- **Tabs component**: Must use `TabContent` directly inside `Tabs`, not custom builders wrapping `TabContent`. Tab bar uses built-in `.tabBar()` modifier.
- **NAPI async**: `tlsConnect` returns `Promise<boolean>` — implement with `napi_create_promise` pattern.

## Rollback

If the implementation fails:
1. Git revert all changes — the project is already a git repo
2. The original `Index.ets` (Hello World) and `napi_init.cpp` (add function) are in git history
3. No external dependencies were added — only project-internal files changed
