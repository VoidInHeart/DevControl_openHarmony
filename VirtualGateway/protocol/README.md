# DevControl Protocol 1.0

`protocol-v1.schema.json` 是 APP 与网关共享的协议契约，覆盖四类专用设备、能力描述式通用设备、配对、加密命令、命令结果、状态事件、报警、心跳和设备快照。

## 传输

- HTTPS REST：`POST /api/v1/pair`、`GET /api/v1/health`、`GET /api/v1/devices`、`POST /api/v1/devices/register`、`DELETE /api/v1/devices/{deviceId}`、`GET /api/v1/logs`、`GET /api/v1/history/environment`、`POST /api/v1/commands`
- WSS：`/ws/v1/events`，用于双向命令和实时事件
- HTTPS/SSE：`GET /api/v1/events`，用于只需服务端事件推送的客户端
- MQTT 5 over TLS：可选外部 Broker 桥接，默认关闭；命令、结果、事件和设备状态主题见下节
- 鉴权：`Authorization: Bearer <credential>`
- 协议版本：`1.0`

所有网络方式都禁止明文降级。HTTPS、WSS 和 MQTTS 最低使用 TLS 1.2；命令无论从 HTTPS、WSS 还是 MQTT 进入，都执行相同的鉴权、解密、重放检查、状态版本检查、审计和广播流程。

### MQTT 5 over TLS 主题

MQTT 桥接需要外部 Broker，网关不会启动明文 Broker。启用时必须配置 Broker CA，并提供 mTLS 客户端证书/私钥或非空用户名/密码：

- 订阅 `devcontrol/v1/commands`，QoS 1；
- 发布 `devcontrol/v1/clients/<credential-digest>/results`，QoS 1；其中 digest 为 `SHA-256(base64url_decode(credential))` 的小写十六进制值；
- 发布 `devcontrol/v1/events/<event-type>`，状态/告警为 QoS 1，心跳为 QoS 0；
- 发布并保留 `devcontrol/v1/devices/<device-id>/state`，QoS 1。

命令主题正文格式如下。`command` 必须是本协议定义的 `SecureCommandEnvelope`，Broker 仍需使用 ACL 限制主题权限：

```json
{
  "protocolVersion": "1.0",
  "credential": "<pair-response-credential>",
  "command": {
    "protocolVersion": "1.0",
    "messageId": "mqtt-command-message-0001",
    "deviceId": "light-living-01",
    "timestamp": 1784208000000,
    "type": "command.request",
    "action": "setPower",
    "expectedStateVersion": 1,
    "nonce": "<base64url>",
    "ciphertext": "<base64url>",
    "authTag": "<base64url>"
  }
}
```

配对响应包含 `issuedAt` 和 `expiresAt`（Unix 毫秒）。网关在每次 REST 请求、WSS 命令以及空闲 WSS 等待期间检查有效期；到期后以 `AUTH_FAILED` 拒绝并关闭事件连接。

### 设备二维码注册

设备二维码包含序列号、展示名称、设备类型、功能分类、能力列表和网关签发的 ES256 静态设备身份证书（紧凑 JWS），不包含房间标识。App 识别后由用户选择已有房间，并将该 `roomId` 仅随 `POST /api/v1/devices/register` 的已配对 Bearer 请求发送。`POST /api/v1/rooms` 可先创建空房间，`GET /api/v1/rooms` 返回所有房间及是否可作为设备目标；创建成功会广播 `room.created`。网关会核对证书的签名、签发者、受众及设备固有声明，再校验所选房间存在，并将在线与能力校验交给设备驱动；驱动确认可接入后才写入快照。证书不带有效期或一次性 `jti`，同一设备可重复扫描，删除后也可用原二维码重新加入到任一可选房间。

VirtualGateway 当前支持 `light`、`environment`、`airConditioner` 与 `humidifier` 的二维码注册；完整能力集合见 `QRgeneration/README.md`。成功加入的设备带有 `removable: true`，可由 `DELETE /api/v1/devices/{deviceId}` 移除；删除后网关广播 `device.removed`，App 同步最新快照。

## 加密命令

业务载荷使用 AES-256-GCM。`nonce`、`ciphertext` 和 `authTag` 使用无填充 Base64URL；nonce 为 12 字节，认证标签为 16 字节。

AAD 是下列字段按固定顺序组成的紧凑 JSON UTF-8 字节：

```text
protocolVersion,messageId,deviceId,timestamp,type,action,expectedStateVersion
```

示例头部：

```json
{
  "protocolVersion": "1.0",
  "messageId": "8vMZ2yD5tG8PkBzX4uLr1Q",
  "deviceId": "light-living-01",
  "timestamp": 1784208000000,
  "type": "command.request",
  "action": "setBrightness",
  "expectedStateVersion": 7
}
```

网关处理顺序固定为：鉴权、时间戳、重放检查、解密、状态版本检查、执行、审计、命令结果、状态广播。时间戳允许误差为 ±30 秒；messageId 和 nonce 记录保留 5 分钟。相同 messageId 返回原结果而不重复执行，相同 nonce 配合新 messageId 会被拒绝。

## 状态规则

- 网关是唯一权威状态源。
- 增量事件只有 `stateVersion` 严格大于本地版本时才能覆盖。
- HTTPS 全量快照替换整个本地缓存。
- APP 发送命令后只显示处理中，不乐观改写设备状态。
- 网关重启后内存会话失效，客户端必须重新配对。

## 能力描述式通用设备

协议 1.0 保留灯光、环境、空调和门锁的原有字段，同时允许其他设备使用通用结构：

- `category` 提供功能分组、标题、图标和是否仅在全屋展示；
- `state` 只允许最多 32 个字符串、数字、布尔或空值字段；
- `controls` 最多 32 项，支持 `button`、`toggle`、`slider` 和 `enum`；
- 控件动作、状态键和载荷键必须使用受限标识符，滑块和枚举还必须声明合法范围或选项；
- APP 只按通过校验的描述生成控制入口，网关驱动仍对每条命令执行最终参数校验。

默认通用设备为 `curtain-living-01`。其状态包含当前位置、目标位置和运动方向，支持 `open`、`close`、`stop`、`setPosition`。

## 标准错误码

| 错误码 | 含义 |
| --- | --- |
| `AUTH_FAILED` | 凭据无效、已过期或会话失效 |
| `DEVICE_PROOF_INVALID` | 设备二维码证书签名无效、声明不一致或不属于当前网关 |
| `DEVICE_OFFLINE` | 设备离线 |
| `INVALID_COMMAND` | 格式、动作或参数无效 |
| `COMMAND_TIMEOUT` | 执行超过 5 秒 |
| `STATE_CONFLICT` | 预期状态版本陈旧 |
| `REPLAY_DETECTED` | 时间戳、nonce、密文或 AAD 安全检查失败 |
| `RATE_LIMITED` | 配对失败次数过多 |
| `INTERNAL_ERROR` | 网关或模拟设备内部失败 |
