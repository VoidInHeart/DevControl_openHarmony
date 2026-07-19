# DevControl 设备二维码生成器

本目录独立于 App，用于生成可被 `DevControl` 的“添加设备”页面识别的 PNG 二维码。未传入
`--output` 时，PNG 默认生成到 `deviceQR/device-<设备序列号>.png`。

它**不会**保存、读取或生成私钥。网关/设备注册服务必须先为设备声明签发紧凑 JWS，生成器只把这份签名证明与设备公开声明打包为二维码。

## 安装

```powershell
cd ..\QRgeneration
python -m pip install -r requirements.txt
```

## 生成

```powershell
python .\generate_device_qr.py `
  --device-id CURTAIN-001 `
  --device-name "演示窗帘" `
  --device-type curtain `
  --category-id curtains `
  --room-id living `
  --capabilities setPosition,stop `
  --gateway-proof '<gateway-issued-compact-jws>' `
  --output .\out\CURTAIN-001.png `
  --payload-output .\out\CURTAIN-001.payload.txt
```

默认二维码内容是紧凑 JSON；App 也接受 `--uri-wrapper` 生成的 `devcontrol://register?payload=...` 内容。不要改写或重新格式化生成后的 `payload`，因为 JWS 的声明必须绑定下面的字段。

## 二维码协议（v1.0）

```json
{
  "schema": "devcontrol.device-registration",
  "protocolVersion": "1.0",
  "deviceId": "CURTAIN-001",
  "deviceName": "演示窗帘",
  "deviceType": "curtain",
  "categoryId": "curtains",
  "roomId": "living",
  "capabilities": ["setPosition", "stop"],
  "gatewayProofFormat": "jws",
  "gatewayProof": "<gateway-issued-compact-jws>"
}
```

字段限制与 App 完全一致：设备序列号为 3–64 位 `[A-Za-z0-9._:-]`；`deviceName` 为 1–64 个非控制字符且不能只含空白；`roomId`、类型、分类与能力为 1–64 位标识符，能力数量为 1–32 且不能重复。整个二维码内容不得超过 8192 字符。

`roomId` 是设备归属房间的稳定索引（例如 `living`、`bedroom`）。App 会使用网关快照中的同一 `roomId` 建立房间分组；内置房间会显示中文名称，其他合法标识则直接显示，便于后续扩展自定义房间。

## 网关必须完成的校验

App 只做格式校验；可信性由已配对网关完成。`POST /api/v1/devices/register` 应当：

1. 验证 TLS 会话与 App 的 Bearer credential。
2. 验证 JWS 的签名、签发者、受众、有效期与一次性 `jti`，并确认 JWS claims 与 `deviceId`、`deviceName`、`deviceType`、`categoryId`、`roomId`、`capabilities` 完全一致。
3. 由设备适配器执行每项 capability 的在线探测；失败时返回 `accepted: false` 或 `online: false`，且不得把设备放入快照。
4. 成功时返回 `{ "deviceId": "...", "accepted": true, "online": true }`，再把设备写入 `/api/v1/devices` 快照。

App 收到成功回执后会拉取最新快照，并再次比对设备序列号、名称、所属房间、类型、功能分类和所有能力接口；任何不一致都会被视为注册失败。

私钥、JWS 签发接口和网关认证材料不得写入本目录或二维码生成命令历史。
