# VirtualGateway

DevControl 的独立虚拟家庭网关。该工程使用 Python 3.11～3.13、FastAPI、HTTPS/WSS/SSE、可选 MQTT 5 over TLS 和 SQLite，负责模拟设备、权威状态、配对鉴权、加密命令、审计与故障注入。

默认组合入口注册 13 台设备：5 盏灯、3 个环境传感器、2 台空调、1 把门锁、1 套智能窗帘和 1 台扩展风扇。离家场景会关闭全部灯光和空调并锁门，返回 8 个逐设备结果；回家默认场景调整两盏客厅灯、客厅空调和门锁，返回 4 个结果。

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

## 新设备驱动扩展

网关通过 `DeviceDriver` 显式注册设备族：

1. 在 `devcontrol_gateway/extensions/` 新增一个驱动文件，实现 `create_devices`、`execute`，需要连续状态变化时再实现 `tick`。
2. 只在 `devcontrol_gateway/composition.py` 的 `default_drivers()` 中显式注册；注册表会拒绝重复设备类型、重复设备编号和类型不一致的初始设备。
3. 通用设备在快照中提供受限的 `category/state/controls` 描述，APP 即可自动分组并生成控制页。
4. 在线检查、状态版本、故障注入、审计、命令幂等和 WSS 状态事件由注册表与服务层统一处理。

智能窗帘是渐进状态设备示例；`extensions/virtual_fan.py` 是一次完整的新增设备演练。它注册后自动出现在卧室和“风扇”功能分组，APP 无需新增类型、解析或页面分支。

空调驱动支持电源、模式、16～30℃ 目标温度和自动/低/中/高四档风速；`haierSim`、`greeSim`、`mideaSim` 会把统一命令编码为各自的演示格式。

新增空调品牌目前仍需同步修改 `adapters.py`、协议 Schema 品牌枚举、ArkTS `DeviceBrand` 和空调页面选项，尚未达到单点注册。真实厂商设备应通过公开 SDK 或合法协议实现独立驱动，不得把模拟兼容名称用于商用兼容声明。
