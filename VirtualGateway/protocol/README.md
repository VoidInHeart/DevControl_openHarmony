# DevControl Protocol 1.0

`protocol-v1.schema.json` 是 APP 与网关共享的协议契约，覆盖四类设备、配对、加密命令、命令结果、状态事件、报警、心跳和设备快照。

## 传输

- REST：`POST /api/v1/pair`、`GET /api/v1/health`、`GET /api/v1/devices`、`GET /api/v1/logs`、`GET /api/v1/history/environment`
- WSS：`/ws/v1/events`
- 鉴权：`Authorization: Bearer <credential>`
- 协议版本：`1.0`

配对响应包含 `issuedAt` 和 `expiresAt`（Unix 毫秒）。网关在每次 REST 请求、WSS 命令以及空闲 WSS 等待期间检查有效期；到期后以 `AUTH_FAILED` 拒绝并关闭事件连接。

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

## 标准错误码

| 错误码 | 含义 |
| --- | --- |
| `AUTH_FAILED` | 凭据无效、已过期或会话失效 |
| `DEVICE_OFFLINE` | 设备离线 |
| `INVALID_COMMAND` | 格式、动作或参数无效 |
| `COMMAND_TIMEOUT` | 执行超过 5 秒 |
| `STATE_CONFLICT` | 预期状态版本陈旧 |
| `REPLAY_DETECTED` | 时间戳、nonce、密文或 AAD 安全检查失败 |
| `RATE_LIMITED` | 配对失败次数过多 |
| `INTERNAL_ERROR` | 网关或模拟设备内部失败 |
