# VirtualGateway

DevControl 的独立虚拟家庭网关。该工程使用 Python 3.11～3.13、FastAPI、HTTPS/WSS 和 SQLite，负责模拟设备、权威状态、配对鉴权、加密命令、审计与故障注入。

## 目录

- `devcontrol_gateway/`：网关服务与设备状态机。
- `protocol/`：APP 与网关共用的协议 1.0 JSON Schema。
- `tests/`：单元测试与协议契约测试。
- `scripts/`：证书、启动、端到端、性能和稳定性脚本。
- `certs/`：演示 CA 与网关证书；私钥不会被 Git 跟踪。
- `data/`：本地 SQLite 运行数据，不会被 Git 跟踪。
- `reports/`：性能与稳定性报告，不会被 Git 跟踪。

## 准备与验证

在 `VirtualGateway` 目录执行：

```powershell
python -m pip install -r requirements.txt
.\scripts\generate_demo_certs.ps1 -HostName localhost -IpAddress 127.0.0.1
.\scripts\test_gateway.ps1
```

证书脚本会把公开演示 CA 同步到相邻 APP 工程的 `../DevControl/entry/src/main/resources/rawfile/demo_ca.crt`。更换网关证书后需要重新构建 APP。

## 启动

```powershell
.\scripts\run_gateway.ps1
```

业务接口默认监听 `https://0.0.0.0:8443`，本机维护接口只监听 `127.0.0.1:18444`。APP 使用 `https://<网关主机>:8443` 配对，证书 SAN 必须包含实际主机名或 IP。

启动日志会显示随机六位一次性配对码。配对成功或五分钟到期后，该码立即轮换；如确需可重复的首个调试码，可显式传入 `-InitialPairingCode`，不要把固定码写入仓库。客户端凭据默认有效 24 小时，可用 `-CredentialTtlSeconds` 调整；到期后 HTTP 和已建立的 WSS 都会返回认证失败，APP 需要重新配对。

演示证书和调试配对机制仅用于本地开发，不适用于生产环境。

## 二维码注册与移除

VirtualGateway 为本地演示提供受维护令牌保护的签发接口：`POST /admin/v1/devices/provision`。它为设备声明签发可长期保存的 ES256 设备身份证书（紧凑 JWS）；私钥自动保存在被 Git 忽略的 `data/device_provisioning.key`，不会传给 App 或二维码生成器。证书可贴在设备上并重复扫描，不包含有效期或一次性标识。

使用相邻目录的生成器可创建实际可加入 App 的浴室灯二维码：

```powershell
cd ..\QRgeneration
python .\generation_device_qr.py `
  --device-id LIGHT-BATHROOM-QR-001 `
  --device-name "浴室智能灯" `
  --device-type light `
  --category-id lighting `
  --room-id bathroom `
  --capabilities setPower,setBrightness,setAutomationConfig `
  --admin-token '<启动日志中的 X-Admin-Token>'
```

App 配对后调用 `POST /api/v1/devices/register`。网关校验证书签名、签发者、受众和全部声明；随后由对应 `DeviceDriver` 对设备类型、功能分类、能力集合及在线状态执行接入探测，探测通过才写入快照。同一设备二维码可重复扫描（结果幂等）；删除后可用原二维码重新加入。由该链路加入的设备会在快照中标记 `removable: true`，App 可通过 `DELETE /api/v1/devices/{deviceId}` 删除它；预置演示设备不能被删除。

当前二维码注册支持四类虚拟设备：`light` / `lighting` 必须声明 `setPower`、`setBrightness`、`setAutomationConfig`；`environment` / `environment` 必须声明 `reportTemperature`、`reportHumidity`、`reportIlluminance`、`reportPresence`，用于浴室环境监测器；`airConditioner` / `environment` 必须声明 `setPower`、`setMode`、`setTemperature`、`setFanSpeed`、`setDehumidify`、`setBrand`；`humidifier` / `environment` 必须声明 `setPower`、`setTargetHumidity`。

## 新设备驱动扩展

网关通过 `DeviceDriver` 显式注册设备族：

1. 在 `devcontrol_gateway/drivers.py` 实现 `create_devices`、`execute`，需要连续状态变化时再实现 `tick`。
2. 将驱动加入 `default_drivers()`；注册表会拒绝重复设备类型、重复设备编号和类型不一致的初始设备。
3. 通用设备在快照中提供受限的 `category/state/controls` 描述，APP 即可自动分组并生成控制页。
4. 在线检查、状态版本、故障注入、审计、命令幂等和 WSS 状态事件由注册表与服务层统一处理。

智能窗帘是该扩展链路的默认示例。真实厂商设备应通过公开 SDK 或合法协议实现独立驱动，不得把模拟兼容名称用于商用兼容声明。
