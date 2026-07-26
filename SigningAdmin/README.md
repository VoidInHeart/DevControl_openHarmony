# DevControl Signing Admin

`SigningAdmin` 是独立于网关运行时的本机签发管理台。它创建受口令保护的项目 CA、签发已审核的网关 CSR，并负责根 CA 的双根过渡。它只监听 `127.0.0.1`，不得部署到服务器或公网。

## 启动

在 `SigningAdmin` 目录执行：

```powershell
python -m pip install -r requirements.txt
.\scripts\run_signing_admin.ps1
```

打开 <http://127.0.0.1:18445>。所有相对路径按仓库根目录解释；签发目录必须在仓库外，例如 `D:\DevControlIssuer`。

## 新项目流程

1. 管理员在“初始化项目 CA”创建 `project-ca.crt` 与受口令保护的 `project-ca.key`。私钥只能位于仓库外的受保护目录。
2. 网关用户在自己的 `VirtualGateway` 目录运行：

   ```powershell
   python .\scripts\generate_gateway_csr.py --ip 192.168.1.8 --host gateway-alice.local
   ```

3. 用户只提交 `certs/gateway.csr`。管理员人工确认 DNS/IP SAN 属于该网关后签发。
4. 管理员只回传 `gateway.crt`；网关用户将其放入 `VirtualGateway/certs/gateway.crt`。不得传送 `gateway.key` 或 `project-ca.key`。
5. 用新的 App CA 公钥重新构建 App，再启动网关。

## 已部署项目的根轮换

不要复用旧 Demo CA 作为新生产根。创建新项目 CA 时，先将其公钥写入临时路径；然后在“过渡根”中把当前 App `demo_ca.crt` 与新 `project-ca.crt` 合并写回 App 路径，发布过渡版本 App。全部网关重新签发并部署新证书后，才“完成轮换”移除旧根。

签发服务会限制网关 CSR 为 ECDSA P-256 且只允许 DNS/IP SAN；管理员仍必须审核 SAN 的归属。当前流程没有 CRL/OCSP 在线吊销服务，密钥泄露时应立即进入根轮换并换发受影响网关证书。
