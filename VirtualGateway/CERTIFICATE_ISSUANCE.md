# 网关证书签发

网关 TLS 私钥由网关用户本机生成，项目 CA 私钥仅由签发管理员持有。App 仅打包项目 CA 的公钥 `DevControl/entry/src/main/resources/rawfile/demo_ca.crt`，并在 HTTPS/WSS 请求中强制使用它验证服务器证书。

| 文件 | 保存位置 | 可提交到 Git |
| --- | --- | --- |
| `project-ca.crt` | App 的 `rawfile/demo_ca.crt` | 可以 |
| `project-ca.key` | 管理员仓库外的受保护目录 | 不可以 |
| `gateway.key` | 对应网关的 `VirtualGateway/certs/` | 不可以 |
| `gateway.csr` / `gateway.crt` | 对应网关 | 不可以 |

## 申请与签发

网关用户执行：

```powershell
python .\scripts\generate_gateway_csr.py `
  --ip 192.168.1.8 `
  --host gateway-alice.local
```

App 实际输入的 IP 或 DNS 名称必须位于 CSR SAN 中。用户仅把 `certs/gateway.csr` 交给管理员。管理员在 [SigningAdmin](../SigningAdmin/README.md) 核对 SAN 后签发 `gateway.crt`；用户将它放入 `certs/gateway.crt` 并正常运行 `scripts/run_gateway.ps1`。

默认证书有效期为 90 天。续期时重复“生成 CSR → 审核 → 签发”即可；项目 CA 未变化时，无需重新构建 App。

## 根 CA 轮换

先创建新项目 CA，然后把旧 App 信任包和新项目 CA 合并为 PEM bundle，发布包含双根的 App。为所有网关换发新 CA 的证书并完成部署后，再发布仅含新根的 App。任何阶段都不得分发 CA 私钥。
