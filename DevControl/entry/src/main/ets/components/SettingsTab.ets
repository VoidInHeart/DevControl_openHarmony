import { AccessLogEntry } from '../model/DeviceModel';
import { DeviceManager } from '../model/DeviceManager';

@Component
export struct SettingsTab {
  @Consume deviceManager: DeviceManager;

  build() {
    Scroll() {
      Column() {
        Text('设置与诊断')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
          .margin({ bottom: 16 })

        this.InfoRow('网关地址', this.deviceManager.gatewayAddress)
        this.InfoRow('连接状态', this.deviceManager.getConnectionLabel())
        this.InfoRow('协议版本', '1.0')
        this.InfoRow('传输安全', 'HTTPS / WSS · 证书验证开启')
        this.InfoRow('证书信任', '内置 DevControl Demo CA · SAN 校验')
        this.InfoRow('数据保护', 'Native AES-256-GCM')
        this.InfoRow('会话保护', 'HUKS AES-256-GCM + Preferences 密文')
        this.InfoRow('最后同步', this.formatTimestamp(this.deviceManager.lastSyncAt))
        this.InfoRow('最后心跳', this.formatTimestamp(this.deviceManager.lastHeartbeatAt))

        if (this.deviceManager.lastError.length > 0) {
          Column() {
            Text('最近错误')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.status_alert'))
              .width('100%')
            Text(this.deviceManager.lastErrorCode + ' · ' + this.deviceManager.lastError)
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
              .margin({ top: 6 })
          }
          .width('100%')
          .padding(16)
          .borderRadius(12)
          .backgroundColor($r('app.color.card_background'))
          .margin({ top: 12 })
        }

        this.DiagnosticLogSection()
        this.ErrorCodeSection()

        Button('重新连接并同步')
          .width('100%')
          .margin({ top: 18 })
          .onClick(() => {
            this.deviceManager.reconnect();
          })

        Button('重新配对')
          .width('100%')
          .fontColor($r('app.color.status_alert'))
          .backgroundColor(Color.Transparent)
          .margin({ top: 8 })
          .onClick(() => {
            AlertDialog.show({
              title: '清除当前安全会话？',
              message: '清除后需要使用网关新生成的六位配对码重新连接。',
              primaryButton: {
                value: '取消',
                action: () => {
                }
              },
              secondaryButton: {
                value: '清除并重新配对',
                fontColor: $r('app.color.status_alert'),
                action: () => {
                  this.deviceManager.forgetGateway();
                }
              }
            });
          })

        Text('本项目中的海尔、格力、美的均为模拟适配器，不代表真实厂商协议兼容或认证。')
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .textAlign(TextAlign.Center)
          .margin({ top: 24, bottom: 32 })
      }
      .width('100%')
      .padding(16)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  DiagnosticLogSection() {
    Column() {
      Text('脱敏诊断日志')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      if (this.deviceManager.accessLogs.length === 0) {
        Text('暂无命令审计记录')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .margin({ top: 8 })
      } else {
        ForEach(this.deviceManager.accessLogs.slice(0, 5), (item: AccessLogEntry) => {
          Column() {
            Text(item.time + ' · ' + item.deviceId + ' · ' + item.action)
              .fontSize(11)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
            Text(item.result +
              (item.errorCode.length > 0 ? ' · ' + item.errorCode : '') +
              (item.messageIdSuffix.length > 0 ? ' · …' + item.messageIdSuffix : ''))
              .fontSize(11)
              .fontColor(item.result === 'success' ?
                $r('app.color.status_online') : $r('app.color.status_alert'))
              .width('100%')
              .margin({ top: 2 })
          }
          .width('100%')
          .margin({ top: 8 })
        }, (item: AccessLogEntry) => item.time + item.deviceId + item.action)
      }
    }
    .width('100%')
    .padding(16)
    .borderRadius(12)
    .backgroundColor($r('app.color.card_background'))
    .margin({ top: 12 })
  }

  @Builder
  ErrorCodeSection() {
    Column() {
      Text('错误码说明')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      this.ErrorCodeRow('AUTH_FAILED', '会话失效，需要重新配对')
      this.ErrorCodeRow('DEVICE_OFFLINE', '目标设备或网关离线')
      this.ErrorCodeRow('INVALID_COMMAND', '命令参数或消息格式无效')
      this.ErrorCodeRow('COMMAND_TIMEOUT', '命令响应超过5秒')
      this.ErrorCodeRow('STATE_CONFLICT', '本地状态版本已过期')
      this.ErrorCodeRow('REPLAY_DETECTED', '安全校验、时间戳或重放检查失败')
      this.ErrorCodeRow('RATE_LIMITED', '配对或请求触发限流')
    }
    .width('100%')
    .padding(16)
    .borderRadius(12)
    .backgroundColor($r('app.color.card_background'))
    .margin({ top: 12 })
  }

  @Builder
  ErrorCodeRow(code: string, description: string) {
    Row() {
      Text(code)
        .fontSize(10)
        .fontColor($r('app.color.primary'))
        .width(110)
      Text(description)
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
        .layoutWeight(1)
    }
    .width('100%')
    .margin({ top: 8 })
  }

  @Builder
  InfoRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .width(88)
      Text(value.length > 0 ? value : '—')
        .fontSize(13)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
        .textAlign(TextAlign.End)
    }
    .width('100%')
    .padding({ top: 13, bottom: 13, left: 16, right: 16 })
    .backgroundColor($r('app.color.card_background'))
    .border({ width: { bottom: 1 }, color: $r('app.color.divider') })
  }

  private formatTimestamp(timestamp: number): string {
    if (timestamp <= 0) {
      return '尚未同步';
    }
    const date = new Date(timestamp);
    return date.getHours().toString().padStart(2, '0') + ':' +
      date.getMinutes().toString().padStart(2, '0') + ':' +
      date.getSeconds().toString().padStart(2, '0');
  }
}
