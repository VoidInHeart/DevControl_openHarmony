# DevControl 独立虚拟网关

虚拟网关必须与 APP 分进程运行，并仅通过 HTTPS/WSS 暴露业务接口。启动时会在终端显示一个有效期 5 分钟的一次性 6 位配对码；配对成功后该码立即失效。

## 启动

1. 创建 Python 3.11 以上虚拟环境并安装 `requirements.txt`。
2. 将网关证书和私钥分别放到 `certs/gateway.crt` 与 `certs/gateway.key`，或通过 `DEVCONTROL_TLS_CERT`、`DEVCONTROL_TLS_KEY` 指定路径。
3. 在 `gateway` 目录执行 `python -m devcontrol_gateway`。
4. 在 APP 输入 `https://<gateway-ip>:8443` 和终端显示的配对码。

网关不会在证书缺失时降级到明文 HTTP/WS。数据库默认保存在 `gateway/data/gateway.db`，凭据明文和数据密钥不会写入数据库或日志。

命令载荷使用 APP Native C++ 层生成的 AES-256-GCM 安全信封，网关会校验 AAD、96 位 nonce 和 128 位认证标签；篡改后的载荷不会进入设备执行层。APP 使用 HUKS 内生成的 AES-256-GCM 包装密钥保护配对凭据和会话数据密钥，Preferences 只保存版本化密文封装。APP 重启后会恢复未过期会话；当前网关会话仍保存在进程内，因此网关进程重启后需要重新配对。

## 验证

```powershell
$env:PYTHONPATH = '.'
python -m unittest discover -s tests -v
```
