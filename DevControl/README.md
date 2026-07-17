# DevControl V1.1

DevControl 是 HarmonyOS 家庭控制端工程，使用 ArkTS + Native C++ 架构。正式运行链路以相邻的独立虚拟网关为唯一设备状态权威，APP 不包含本地设备成功模拟路径。

## 目录

- `entry/`：HarmonyOS 6.1.1 / API 24 ArkTS APP 与 Native C++ 安全核心。
- `scripts/`：APP 构建和安全扫描脚本。
- `../VirtualGateway/`：独立 Python FastAPI HTTPS/WSS 虚拟网关与协议契约。
- `../docs/`：需求、设计、用户、验收矩阵和测试报告。
- `../docs/开发调试指南.md`：DevEco Studio 全链路跑通、设备联调与常见故障排查。

## 快速验证

```powershell
.\scripts\security_scan.ps1
.\scripts\build_app.ps1
```

网关的安装、证书、测试和启动命令在 `../VirtualGateway/README.md` 中维护。启动演示网关：

```powershell
cd ..\VirtualGateway
.\scripts\run_gateway.ps1 -PairingCode 123456
```

APP 配对地址默认使用 `https://<网关主机>:8443`。证书 SAN 必须包含该主机名或 IP；生成证书后必须重新构建 APP，使公开演示 CA 打包进入 HAP。

## 本地签名

仓库中的 `build-profile.json5` 不保存签名路径、密码或私钥。若需要签名，在项目根目录创建被忽略的 `build-profile.signing.local.json`，其中提供 `productSigningConfig` 和 DevEco Studio 格式的 `signingConfigs` 数组，再运行 `scripts/build_app.ps1`。脚本只在构建期间临时合并本地签名信息。

`artifacts/DevControl-1.1.0-demo-signed.hap` 使用开发调试 profile，仅用于本地安装和竞赛演示；正式发布必须替换为有效的发布证书与发布 profile。

## 已知验收边界

自动化覆盖网关、协议、真实 TLS/WSS、安全负向、性能和短时稳定性。HarmonyOS 6.1.1 真机上的 HUKS、Native 互通、前后台切换和 30 分钟稳定性仍必须按 `../docs/测试报告.md` 补充实机证据。
