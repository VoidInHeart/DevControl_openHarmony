import { AccessLogEntry, AlertEntry } from '../model/DeviceModel';
import { DeviceManager } from '../model/DeviceManager';

@Component
export struct SettingsTab {
  @Consume deviceManager: DeviceManager;
  @State showSecurityDetails: boolean = false;
  @State detailKey: string = '';

  build() {
    if (this.detailKey.length > 0) {
      this.DetailPage()
    } else {
      this.SettingsHome()
    }
  }

  @Builder
  SettingsHome() {
    Scroll() {
      Column() {
        Text('设置')
          .fontSize(30)
          .fontWeight(FontWeight.Bold)
          .fontColor('#14263A')
          .width('100%')
          .margin({ bottom: 18 })

        this.ProfileCard()
        this.ConnectionCard()
        this.SettingsGroup('家庭管理')
        this.SettingRow('⌂', '家庭名称', 'DevControl 的家', 'home')
        this.SettingRow('□', '房间与设备', this.deviceManager.devices.length.toFixed(0) + ' 台设备', 'rooms')
        this.SettingRow('○', '家庭成员', '1 位成员', 'members')

        this.SettingsGroup('安全与通知')
        this.SettingRow('✓', '连接保护', 'HTTPS / WSS 已开启', 'protection')
        this.SettingRow('◇', '告警通知', this.alertSummary(), 'alerts')
        this.SecurityEntryRow()
        if (this.showSecurityDetails) {
          this.SecurityLogCard()
        }

        this.SettingsGroup('应用')
        this.SettingRow('↻', '同步状态', this.syncSummary(), 'sync')
        this.SettingRow('?', '关于 DevControl', '版本 1.0', 'about')

        Button('重新连接')
          .width('100%')
          .height(46)
          .fontColor(Color.White)
          .backgroundColor('#1769C2')
          .borderRadius(18)
          .margin({ top: 16 })
          .onClick(() => {
            this.deviceManager.reconnect();
          })

        Button('重新配对网关')
          .width('100%')
          .height(46)
          .fontColor('#D64545')
          .backgroundColor(Color.Transparent)
          .margin({ top: 8, bottom: 28 })
          .onClick(() => {
            this.confirmForgetGateway();
          })
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 42, bottom: 18 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#DCEAF2')
    .scrollBar(BarState.Off)
  }

  @Builder
  ProfileCard() {
    Row() {
      Column() {
        Text('D')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
      }
      .width(58)
      .height(58)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor('#1769C2')
      .borderRadius(22)

      Column() {
        Text('DevControl 用户')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#14263A')
        Text('管理 DevControl 的家')
          .fontSize(13)
          .fontColor('#748294')
          .margin({ top: 5 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 14 })

      Text('›')
        .fontSize(28)
        .fontColor('#AEB9C6')
    }
    .width('100%')
    .padding(18)
    .backgroundColor(Color.White)
    .borderRadius(24)
    .margin({ bottom: 14 })
    .onClick(() => {
      this.detailKey = 'profile';
    })
  }

  @Builder
  ConnectionCard() {
    Column() {
      Row() {
        Column() {
          Text('网关连接')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor('#14263A')
          Text(this.deviceManager.gatewayAddress.length > 0 ? this.deviceManager.gatewayAddress : '尚未连接')
            .fontSize(12)
            .fontColor('#748294')
            .margin({ top: 6 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Text(this.deviceManager.getConnectionLabel())
          .fontSize(12)
          .fontColor(this.deviceManager.isOnline() ? '#0F8F66' : '#D64545')
          .padding({ left: 11, right: 11, top: 6, bottom: 6 })
          .backgroundColor(this.deviceManager.isOnline() ? '#EAF8F1' : '#FFF0F0')
          .borderRadius(14)
      }
      .width('100%')

      Row() {
        this.MetricTile('在线设备', this.deviceManager.getOnlineCount().toFixed(0))
        this.MetricTile('离线设备', this.deviceManager.getOfflineCount().toFixed(0))
        this.MetricTile('最后同步', this.formatTimestamp(this.deviceManager.lastSyncAt))
      }
      .width('100%')
      .margin({ top: 16 })

      if (this.deviceManager.lastError.length > 0) {
        Text(this.deviceManager.lastError)
          .fontSize(12)
          .fontColor('#D64545')
          .width('100%')
          .padding({ top: 10 })
      }
    }
    .width('100%')
    .padding(18)
    .backgroundColor(Color.White)
    .borderRadius(24)
    .margin({ bottom: 14 })
    .onClick(() => {
      this.detailKey = 'connection';
    })
  }

  @Builder
  MetricTile(label: string, value: string) {
    Column() {
      Text(value)
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor('#14263A')
        .maxLines(1)
      Text(label)
        .fontSize(11)
        .fontColor('#748294')
        .margin({ top: 5 })
    }
    .layoutWeight(1)
    .height(68)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('#F7FBFF')
    .borderRadius(18)
    .margin({ right: 8 })
  }

  @Builder
  SettingsGroup(title: string) {
    Text(title)
      .fontSize(16)
      .fontWeight(FontWeight.Bold)
      .fontColor('#14263A')
      .width('100%')
      .margin({ top: 10, bottom: 10 })
  }

  @Builder
  SettingRow(icon: string, title: string, value: string, key: string) {
    Row() {
      Text(icon)
        .fontSize(18)
        .fontColor('#1769C2')
        .width(40)
        .height(40)
        .textAlign(TextAlign.Center)
        .backgroundColor('#EAF4FF')
        .borderRadius(15)
      Text(title)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor('#14263A')
        .layoutWeight(1)
        .margin({ left: 12 })
      Text(value)
        .fontSize(12)
        .fontColor('#748294')
        .maxLines(1)
        .textAlign(TextAlign.End)
      Text('›')
        .fontSize(22)
        .fontColor('#AEB9C6')
        .margin({ left: 6 })
    }
    .width('100%')
    .height(62)
    .padding({ left: 14, right: 12 })
    .backgroundColor(Color.White)
    .borderRadius(18)
    .margin({ bottom: 8 })
    .onClick(() => {
      this.detailKey = key;
    })
  }

  @Builder
  SecurityEntryRow() {
    Row() {
      Text('≡')
        .fontSize(18)
        .fontColor('#1769C2')
        .width(40)
        .height(40)
        .textAlign(TextAlign.Center)
        .backgroundColor('#EAF4FF')
        .borderRadius(15)
      Text('安全与日志')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor('#14263A')
        .layoutWeight(1)
        .margin({ left: 12 })
      Text(this.logSummary())
        .fontSize(12)
        .fontColor('#748294')
      Text(this.showSecurityDetails ? '⌃' : '›')
        .fontSize(22)
        .fontColor('#AEB9C6')
        .margin({ left: 6 })
    }
    .width('100%')
    .height(62)
    .padding({ left: 14, right: 12 })
    .backgroundColor(Color.White)
    .borderRadius(18)
    .margin({ bottom: 8 })
    .onClick(() => {
      this.detailKey = 'security';
    })
  }

  @Builder
  DetailPage() {
    Scroll() {
      Column() {
        Row() {
          Text('‹')
            .fontSize(38)
            .fontColor('#14263A')
            .width(46)
            .height(46)
            .onClick(() => {
              this.detailKey = '';
            })
          Text(this.detailTitle())
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor('#14263A')
            .layoutWeight(1)
        }
        .width('100%')
        .margin({ bottom: 18 })

        if (this.detailKey === 'profile') {
          this.ProfileDetail()
        } else if (this.detailKey === 'connection') {
          this.ConnectionDetail()
        } else if (this.detailKey === 'home') {
          this.HomeDetail()
        } else if (this.detailKey === 'rooms') {
          this.RoomsDetail()
        } else if (this.detailKey === 'members') {
          this.MembersDetail()
        } else if (this.detailKey === 'protection') {
          this.ProtectionDetail()
        } else if (this.detailKey === 'alerts') {
          this.AlertsDetail()
        } else if (this.detailKey === 'security') {
          this.SecurityDetail()
        } else if (this.detailKey === 'sync') {
          this.SyncDetail()
        } else {
          this.AboutDetail()
        }
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 42, bottom: 24 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#DCEAF2')
    .scrollBar(BarState.Off)
  }

  @Builder
  ProfileDetail() {
    this.DetailCard('账号', 'DevControl 用户', '当前账号用于本机演示，不绑定云端账号。')
    this.DetailCard('家庭', 'DevControl 的家', '这里展示 App 侧家庭身份，设备状态仍由网关作为权威来源。')
  }

  @Builder
  ConnectionDetail() {
    this.DetailCard('连接状态', this.deviceManager.getConnectionLabel(), this.deviceManager.gatewayAddress)
    this.DetailCard('最后同步', this.formatTimestamp(this.deviceManager.lastSyncAt),
      '同步设备列表、告警和审计记录。')
    this.DetailCard('最后心跳', this.formatTimestamp(this.deviceManager.lastHeartbeatAt),
      '用于判断 WebSocket 长连接是否仍然健康。')
    if (this.deviceManager.lastError.length > 0) {
      this.DetailCard('最近错误', this.deviceManager.lastErrorCode, this.deviceManager.lastError)
    }
  }

  @Builder
  HomeDetail() {
    this.DetailCard('家庭名称', 'DevControl 的家', '当前为演示家庭，后续可以扩展成可编辑名称。')
    this.DetailCard('家庭概况', this.deviceManager.devices.length.toFixed(0) + ' 台设备',
      this.deviceManager.getOnlineCount().toFixed(0) + ' 台在线，' +
        this.deviceManager.getOfflineCount().toFixed(0) + ' 台离线。')
  }

  @Builder
  RoomsDetail() {
    this.DetailCard('房间数量', this.roomCount().toFixed(0) + ' 个房间', '设备按房间和品类管理。')
    this.RoomSummaryRow('客厅', 'living')
    this.RoomSummaryRow('主卧', 'masterBedroom')
    this.RoomSummaryRow('次卧', 'bedroom')
    this.RoomSummaryRow('浴室', 'bathroom')
  }

  @Builder
  MembersDetail() {
    this.DetailCard('家庭成员', '1 位成员', '当前版本以本机演示账号为主。')
    this.DetailCard('权限说明', '管理员', '可配对网关、控制设备、查看安全日志。')
  }

  @Builder
  ProtectionDetail() {
    this.DetailCard('传输安全', 'HTTPS / WSS', 'App 与网关之间使用加密连接。')
    this.DetailCard('证书信任', 'DevControl Demo CA', '演示环境内置 CA，并进行证书校验。')
    this.DetailCard('命令保护', 'AES-256-GCM', '控制命令带有时间戳、nonce 和消息编号，便于防重放和审计。')
    this.ErrorCodeSection()
  }

  @Builder
  AlertsDetail() {
    if (this.deviceManager.alerts.length === 0) {
      this.DetailCard('告警通知', '无新告警', '设备异常、锁体故障等事件会在这里显示。')
    } else {
      ForEach(this.deviceManager.alerts.slice(0, 8), (alert: AlertEntry) => {
        this.DetailCard(alert.code, alert.level, alert.time + ' · ' + alert.message)
      }, (alert: AlertEntry) => alert.time + alert.code)
    }
  }

  @Builder
  SecurityDetail() {
    this.DetailCard('安全与日志', this.logSummary(), '这里保留答辩和排查需要的脱敏诊断信息。')
    this.SecurityLogCard()
    this.ErrorCodeSection()
  }

  @Builder
  SyncDetail() {
    this.DetailCard('同步状态', this.syncSummary(), 'App 会从网关获取设备快照，并通过长连接接收状态变化。')
    this.DetailCard('设备快照', this.deviceManager.devices.length.toFixed(0) + ' 台设备',
      '在线 ' + this.deviceManager.getOnlineCount().toFixed(0) + ' 台，离线 ' +
        this.deviceManager.getOfflineCount().toFixed(0) + ' 台。')
  }

  @Builder
  AboutDetail() {
    this.DetailCard('DevControl', '版本 1.0', '家庭设备控制与虚拟网关演示 App。')
    this.DetailCard('适配说明', '模拟品牌适配器',
      '海尔、格力、美的均为模拟适配器，不代表真实厂商协议兼容或认证。')
    this.DetailCard('项目定位', '软件侧严格模拟',
      '当前重点展示 App、网关、安全协议、设备模型和联动控制流程。')
  }

  @Builder
  DetailCard(title: string, value: string, description: string) {
    Column() {
      Text(title)
        .fontSize(13)
        .fontColor('#748294')
        .width('100%')
      Text(value.length > 0 ? value : '—')
        .fontSize(19)
        .fontWeight(FontWeight.Bold)
        .fontColor('#14263A')
        .width('100%')
        .margin({ top: 7 })
      Text(description.length > 0 ? description : '暂无详情')
        .fontSize(12)
        .fontColor('#748294')
        .width('100%')
        .margin({ top: 8 })
    }
    .width('100%')
    .padding(18)
    .backgroundColor(Color.White)
    .borderRadius(22)
    .margin({ bottom: 12 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  RoomSummaryRow(label: string, roomId: string) {
    Row() {
      Text(label)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor('#14263A')
        .layoutWeight(1)
      Text(this.roomDeviceCount(roomId).toFixed(0) + ' 台设备')
        .fontSize(12)
        .fontColor('#748294')
    }
    .width('100%')
    .height(54)
    .padding({ left: 16, right: 16 })
    .backgroundColor(Color.White)
    .borderRadius(18)
    .margin({ bottom: 8 })
  }

  @Builder
  SecurityLogCard() {
    Column() {
      Text('最近操作')
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor('#14263A')
        .width('100%')
      if (this.deviceManager.accessLogs.length === 0) {
        Text('暂无操作记录')
          .fontSize(12)
          .fontColor('#748294')
          .width('100%')
          .margin({ top: 8 })
      } else {
        ForEach(this.deviceManager.accessLogs.slice(0, 3), (item: AccessLogEntry) => {
          Row() {
            Column() {
              Text(item.action)
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor('#14263A')
              Text(item.time + ' · ' + item.deviceId)
                .fontSize(11)
                .fontColor('#748294')
                .margin({ top: 3 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Text(item.result === 'success' ? '成功' : '失败')
              .fontSize(12)
              .fontColor(item.result === 'success' ? '#0F8F66' : '#D64545')
          }
          .width('100%')
          .margin({ top: 12 })
        }, (item: AccessLogEntry) => item.time + item.deviceId + item.action)
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(Color.White)
    .borderRadius(20)
    .margin({ bottom: 8 })
  }

  @Builder
  ErrorCodeSection() {
    Column() {
      Text('错误码说明')
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor('#14263A')
        .width('100%')
      this.ErrorCodeRow('AUTH_FAILED', '会话失效，需要重新配对')
      this.ErrorCodeRow('DEVICE_PROOF_INVALID', '设备二维码证书无效或不属于当前网关')
      this.ErrorCodeRow('DEVICE_OFFLINE', '目标设备或网关离线')
      this.ErrorCodeRow('INVALID_COMMAND', '命令参数或消息格式无效')
      this.ErrorCodeRow('COMMAND_TIMEOUT', '命令响应超过5秒')
      this.ErrorCodeRow('STATE_CONFLICT', '本地状态版本已过期')
      this.ErrorCodeRow('REPLAY_DETECTED', '安全校验、时间戳或重放检查失败')
      this.ErrorCodeRow('RATE_LIMITED', '配对或请求触发限流')
    }
    .width('100%')
    .padding(16)
    .backgroundColor(Color.White)
    .borderRadius(20)
    .margin({ bottom: 12 })
  }

  @Builder
  ErrorCodeRow(code: string, description: string) {
    Row() {
      Text(code)
        .fontSize(10)
        .fontColor('#1769C2')
        .width(112)
      Text(description)
        .fontSize(11)
        .fontColor('#748294')
        .layoutWeight(1)
    }
    .width('100%')
    .margin({ top: 8 })
  }

  private confirmForgetGateway(): void {
    AlertDialog.show({
      title: '重新配对网关？',
      message: '当前 App 会清除本地会话，之后需要输入网关地址和六位配对码。',
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '重新配对',
        fontColor: '#D64545',
        action: () => {
          this.deviceManager.forgetGateway();
        }
      }
    });
  }

  private alertSummary(): string {
    if (this.deviceManager.alerts.length === 0) {
      return '无新告警';
    }
    const latest = this.deviceManager.alerts[0] as AlertEntry;
    return latest.code.length > 0 ? latest.code : this.deviceManager.alerts.length.toFixed(0) + ' 条告警';
  }

  private detailTitle(): string {
    if (this.detailKey === 'profile') {
      return '账号资料';
    }
    if (this.detailKey === 'connection') {
      return '网关连接';
    }
    if (this.detailKey === 'home') {
      return '家庭名称';
    }
    if (this.detailKey === 'rooms') {
      return '房间与设备';
    }
    if (this.detailKey === 'members') {
      return '家庭成员';
    }
    if (this.detailKey === 'protection') {
      return '连接保护';
    }
    if (this.detailKey === 'alerts') {
      return '告警通知';
    }
    if (this.detailKey === 'security') {
      return '安全与日志';
    }
    if (this.detailKey === 'sync') {
      return '同步状态';
    }
    return '关于 DevControl';
  }

  private logSummary(): string {
    if (this.deviceManager.accessLogs.length === 0) {
      return '暂无记录';
    }
    return this.deviceManager.accessLogs.length.toFixed(0) + ' 条记录';
  }

  private syncSummary(): string {
    if (this.deviceManager.isOnline()) {
      return '已连接 · ' + this.formatTimestamp(this.deviceManager.lastSyncAt);
    }
    return '等待连接';
  }

  private roomCount(): number {
    const rooms: string[] = [];
    for (let index = 0; index < this.deviceManager.devices.length; index++) {
      const roomId = this.deviceManager.devices[index].roomId;
      if (roomId.length > 0 && rooms.indexOf(roomId) < 0) {
        rooms.push(roomId);
      }
    }
    return rooms.length;
  }

  private roomDeviceCount(roomId: string): number {
    let count = 0;
    for (let index = 0; index < this.deviceManager.devices.length; index++) {
      if (this.deviceManager.devices[index].roomId === roomId) {
        count += 1;
      }
    }
    return count;
  }

  private formatTimestamp(timestamp: number): string {
    if (timestamp <= 0) {
      return '未同步';
    }
    const date = new Date(timestamp);
    return date.getHours().toString().padStart(2, '0') + ':' +
      date.getMinutes().toString().padStart(2, '0');
  }
}
