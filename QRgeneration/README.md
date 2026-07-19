# DevControl 设备二维码生成器

本目录独立于 App，用于生成可被 `DevControl` 的“添加设备”页面识别的 PNG 二维码。未传入
`--output` 时，PNG 默认生成到 `deviceQR/device-<设备序列号>.png`。

它**不会**保存、读取或生成私钥。默认情况下，生成器会向本机 `VirtualGateway` 的维护接口申请可长期保存的设备身份证书（紧凑 JWS）；签名私钥始终留在网关被忽略的 `data/` 目录中。二维码不含过期时间或一次性标识，可贴在设备上长期使用。

## 安装

```powershell
cd ..\QRgeneration
python -m pip install -r requirements.txt
```

## 生成

先启动 `VirtualGateway`，并保留启动日志中的 `X-Admin-Token`；随后生成可真实注册的浴室灯二维码：

```powershell
python .\generation_device_qr.py `
  --device-id LIGHT-BATHROOM-QR-001 `
  --device-name "浴室智能灯" `
  --device-type light `
  --category-id lighting `
  --capabilities setPower,setBrightness,setAutomationConfig `
  --admin-token '<VirtualGateway 启动日志中的令牌>'
```

`generation_device_qr.py` 是当前入口；`generate_device_qr.py` 保留为兼容入口。默认会访问 `http://127.0.0.1:18444/admin/v1/devices/provision`，也可用 `--admin-url` 指向其他本机维护端口。仅在迁移旧系统时才使用 `--gateway-proof` 直接传入已签发的 JWS。

默认二维码内容是紧凑 JSON；App 也接受 `--uri-wrapper` 生成的 `devcontrol://register?payload=...` 内容。不要改写或重新格式化生成后的 `payload`，因为 JWS 的声明必须绑定下面的字段。

## 二维码协议（v1.0）

```json
{
  "schema": "devcontrol.device-registration",
  "protocolVersion": "1.0",
  "deviceId": "LIGHT-BATHROOM-QR-001",
  "deviceName": "浴室智能灯",
  "deviceType": "light",
  "categoryId": "lighting",
  "capabilities": ["setPower", "setBrightness", "setAutomationConfig"],
  "gatewayProofFormat": "jws",
  "gatewayProof": "<gateway-issued-compact-jws>"
}
```

字段限制与 App 完全一致：设备序列号为 3–64 位 `[A-Za-z0-9._:-]`；`deviceName` 为 1–64 个非控制字符且不能只含空白；类型、分类与能力为 1–64 位标识符，能力数量为 1–32 且不能重复。整个二维码内容不得超过 8192 字符。

二维码不包含 `roomId`。识别后由用户在 App 的“添加至房间”下拉菜单中选择现有房间；该选择只随已配对的注册请求发送，不写入 JWS 设备身份证书。因此同一张二维码可以在删除设备后重新添加到另一个房间。早期二维码即使仍带有 `roomId`，新 App 也会忽略该字段并使用用户当前选择。

## 网关必须完成的校验

App 只做格式校验；可信性由已配对网关完成。`POST /api/v1/devices/register` 应当：

1. 验证 TLS 会话与 App 的 Bearer credential。
2. 验证静态设备身份证书 JWS 的签名、签发者、受众，并确认 JWS claims 与 `deviceId`、`deviceName`、`deviceType`、`categoryId`、`capabilities` 完全一致。证书没有有效期和一次性 `jti`，重复扫描同一设备是幂等的。
3. 校验 App 选择的目标 `roomId` 是网关当前已有的房间，再将接入验证交给对应设备适配器：适配器必须确认类型、功能分类、全部 capability 均被设备接受且设备在线；失败时不得把设备放入快照。
4. 成功时返回 `{ "deviceId": "...", "accepted": true, "online": true }`，再把设备写入 `/api/v1/devices` 快照。所有二维码注册设备都会标记为可移除，可由 App 调用 `DELETE /api/v1/devices/{deviceId}` 移除。

App 收到成功回执后会拉取最新快照，并再次比对设备序列号、名称、所选房间、类型、功能分类和所有能力接口；任何不一致都会被视为注册失败。

私钥、JWS 签发接口和网关认证材料不得写入本目录或二维码生成命令历史。真实硬件接入时，设备适配器应进一步用设备私钥对网关随机挑战签名；本项目的虚拟灯驱动以本地在线能力探测模拟这一环节。

## 当前可注册的 capability

`capabilities` 是网关与设备共同约定的接口标识；二维码中的集合必须与设备驱动支持的集合完全一致。当前可通过二维码注册的设备如下：

| 设备类型 | 功能分类 | capabilities |
| --- | --- | --- |
| `light` | `lighting` | `setPower`, `setBrightness`, `setAutomationConfig` |
| `environment` | `environment` | `reportTemperature`, `reportHumidity`, `reportIlluminance`, `reportPresence` |
| `airConditioner` | `environment` | `setPower`, `setMode`, `setTemperature`, `setFanSpeed`, `setDehumidify`, `setBrand` |
| `humidifier` | `environment` | `setPower`, `setTargetHumidity` |

环境监测器的四项 capability 都是设备向网关上报的遥测接口，不是 App 下发控制命令；注册成功后，App 会显示温度、湿度、照度及人体存在状态。

```powershell
python .\generation_device_qr.py `
  --device-id ENV-BATHROOM-QR-001 `
  --device-name "浴室环境监测器" `
  --device-type environment `
  --category-id environment `
  --capabilities reportTemperature,reportHumidity,reportIlluminance,reportPresence `
  --admin-token '<VirtualGateway 启动日志中的令牌>'
```

浴室空调和加湿器可分别使用：

```powershell
python .\generation_device_qr.py `
  --device-id AC-BATHROOM-QR-001 `
  --device-name "浴室空调" `
  --device-type airConditioner `
  --category-id environment `
  --capabilities setPower,setMode,setTemperature,setFanSpeed,setDehumidify,setBrand `
  --admin-token '<VirtualGateway 启动日志中的令牌>'

python .\generation_device_qr.py `
  --device-id HUMIDIFIER-BATHROOM-QR-001 `
  --device-name "浴室加湿器" `
  --device-type humidifier `
  --category-id environment `
  --capabilities setPower,setTargetHumidity `
  --admin-token '<VirtualGateway 启动日志中的令牌>'
```
