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
.\scripts\run_gateway.ps1 -PairingCode 123456
```

业务接口默认监听 `https://0.0.0.0:8443`，本机维护接口只监听 `127.0.0.1:18444`。APP 使用 `https://<网关主机>:8443` 配对，证书 SAN 必须包含实际主机名或 IP。

演示证书和默认配对码仅用于本地开发，不适用于生产环境。
