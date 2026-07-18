import { router } from '@kit.ArkUI';
import {
  AirConditionerDevice,
  DeviceInfo,
  DeviceType,
  DoorLockDevice,
  EnvironmentDevice,
  LightDevice
} from '../model/DeviceModel';
import { DeviceFeature, DeviceRegistry } from '../model/DeviceRegistry';
import { DeviceManager } from '../model/DeviceManager';

@Component
export struct ControlCenterTab {
  @Consume deviceManager: DeviceManager;
  @State selectedRoom: string = 'all';

  build() {
    Scroll() {
      Column() {
        this.HomeHeader()
        this.RoomSegments()
        this.StatusStrip()
        if (this.selectedRoom === 'all') {
          this.FeatureSection()
        }
        this.DeviceSection()
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 42, bottom: 18 })
    }
    .width('100%')
    .layoutWeight(1)
    .backgroundColor('#DCEAF2')
    .scrollBar(BarState.Off)
  }

  @Builder
  HomeHeader() {
    Row() {
      Column() {
        Text('DevControl 的家')
          .fontSize(30)
          .fontWeight(FontWeight.Bold)
          .fontColor('#14263A')
        Text(this.headerSubtitle())
          .fontSize(13)
          .fontColor('#748294')
          .margin({ top: 6 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text('⌂')
        .fontSize(28)
        .fontColor('#1769C2')
        .width(46)
        .height(46)
        .textAlign(TextAlign.Center)
        .backgroundColor('#E4F0FF')
        .borderRadius(23)
    }
    .width('100%')
    .margin({ bottom: 10 })
  }

  @Builder
  StatusStrip() {
    Row() {
      this.StatusPill('室温', this.averageTemperature(), '│', '#EAF4FF')
      this.StatusPill('湿度', this.averageHumidity(), '●', '#EEF9F4')
      this.StatusPill('亮灯', this.lightsOnCount().toString(), '○', '#FFF7E8')
      this.StatusPill('在线', this.deviceManager.getOnlineCount().toString(), '●', '#F0EEFF')
    }
    .width('100%')
    .justifyContent(FlexAlign.SpaceBetween)
    .margin({ bottom: 16 })
  }

  @Builder
  StatusPill(label: string, value: string, icon: string, color: string) {
    Column() {
      Text(icon)
        .fontSize(20)
        .opacity(0.85)
      Text(value)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1769C2')
        .margin({ top: 3 })
      Text(label)
        .fontSize(11)
        .fontColor('#748294')
        .margin({ top: 3 })
    }
    .width('23%')
    .height(86)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(color)
    .borderRadius(20)
  }

  @Builder
  RoomSegments() {
    Scroll() {
      Row() {
        this.RoomButton('all', '全屋')
        ForEach(this.displayRoomIds(), (roomId: string) => {
          this.RoomButton(roomId, this.roomLabel(roomId))
        }, (roomId: string) => roomId)
      }
    }
    .width('100%')
    .height(48)
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .margin({ bottom: 14 })
  }

  @Builder
  RoomButton(roomId: string, label: string) {
    Column() {
      Text(label)
        .fontSize(16)
        .fontWeight(this.selectedRoom === roomId ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.selectedRoom === roomId ? '#14263A' : '#8A98A8')
        .textAlign(TextAlign.Center)
      Text('')
        .width(this.selectedRoom === roomId ? 30 : 0)
        .height(3)
        .backgroundColor('#1769C2')
        .borderRadius(2)
        .margin({ top: 7 })
    }
      .width(78)
      .height(44)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .onClick(() => {
        this.selectedRoom = roomId;
      })
  }

  @Builder
  SceneCard() {
    Row() {
      Column() {
        Text('快捷场景')
          .fontSize(19)
          .fontWeight(FontWeight.Bold)
          .fontColor('#14263A')
        Text('一键切换回家和离家状态')
          .fontSize(13)
          .fontColor('#748294')
          .margin({ top: 6, bottom: 14 })
        Row() {
          Button('回家')
            .height(40)
            .layoutWeight(1)
            .borderRadius(20)
            .backgroundColor('#1769C2')
            .onClick(() => {
              this.deviceManager.executeHomeScene();
            })
          Button('离家')
            .height(40)
            .layoutWeight(1)
            .fontColor('#1769C2')
            .borderRadius(20)
            .backgroundColor('#EAF4FF')
            .margin({ left: 10 })
            .onClick(() => {
              this.deviceManager.executeAwayScene();
            })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text('↯')
        .fontSize(34)
        .fontColor('#1769C2')
        .width(64)
        .height(64)
        .textAlign(TextAlign.Center)
        .backgroundColor('#F4F8FF')
        .borderRadius(24)
        .margin({ left: 12 })
    }
    .width('100%')
    .padding(18)
    .backgroundColor(Color.White)
    .borderRadius(24)
    .margin({ bottom: 18 })
  }

  @Builder
  FeatureSection() {
    Column() {
      this.SectionTitle('功能分类')
      Row() {
        ForEach(DeviceRegistry.getHomeFeatures(), (feature: DeviceFeature) => {
          if (feature.id !== 'curtains') {
            this.FeatureCard(feature)
          }
        }, (feature: DeviceFeature) => feature.id)
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .width('100%')
    .margin({ bottom: 6 })
  }

  @Builder
  FeatureCard(feature: DeviceFeature) {
    Column() {
      Text(this.featureTitle(feature.id))
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor('#14263A')
        .width('100%')
      Text(this.featureSummary(feature))
        .fontSize(10)
        .fontColor('#748294')
        .width('100%')
        .margin({ top: 4 })
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Blank()
      Row() {
        Blank()
        Text(this.featureIcon(feature.id))
          .fontSize(34)
          .width(54)
          .height(54)
          .textAlign(TextAlign.Center)
          .backgroundColor(this.featureTint(feature.id))
          .borderRadius(18)
      }
      .width('100%')
    }
    .width('31.8%')
    .height(118)
    .padding(12)
    .margin({ bottom: 12 })
    .borderRadius(22)
    .backgroundColor('#F7FBFF')
    .onClick(() => {
      this.openFeature(feature.id);
    })
  }

  @Builder
  DeviceSection() {
    Column() {
      this.SectionTitle(this.selectedRoom === 'all' ? '全部设备' : this.roomLabel(this.selectedRoom))
      ForEach(this.visibleDevices(), (device: DeviceInfo) => {
        this.DeviceRow(device)
      }, (device: DeviceInfo) => device.id + ':' + device.stateVersion.toString())
    }
    .width('100%')
  }

  @Builder
  DeviceRow(device: DeviceInfo) {
    Row() {
      Text(this.deviceIcon(device))
        .fontSize(23)
        .width(50)
        .height(50)
        .textAlign(TextAlign.Center)
        .backgroundColor(this.deviceTint(device))
        .borderRadius(18)
      Column() {
        Text(device.name)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor('#14263A')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.deviceSummary(device))
          .fontSize(12)
          .fontColor(device.online ? '#748294' : '#D64545')
          .margin({ top: 5 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 12 })
      Text(device.online ? '在线' : '离线')
        .fontSize(11)
        .fontColor(device.online ? '#0F8F66' : '#D64545')
        .padding({ left: 10, right: 10, top: 5, bottom: 5 })
        .backgroundColor(device.online ? '#EAF8F1' : '#FFF1F1')
        .borderRadius(12)
    }
    .width('100%')
    .padding(14)
    .margin({ bottom: 10 })
    .borderRadius(24)
    .backgroundColor('#F7FBFF')
    .onClick(() => {
      router.pushUrl({
        url: 'pages/DeviceDetail',
        params: { deviceId: device.id }
      });
    })
  }

  @Builder
  SectionTitle(title: string) {
    Row() {
      Column() {
        Text(title)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#14263A')
      }
      .alignItems(HorizontalAlign.Start)
      Blank()
    }
    .width('100%')
    .margin({ bottom: 12 })
  }

  private openFeature(featureId: string): void {
    router.pushUrl({
      url: 'pages/FeatureDevices',
      params: { featureId: featureId }
    });
  }

  private visibleDevices(): DeviceInfo[] {
    if (this.selectedRoom === 'all') {
      return this.deviceManager.devices;
    }
    return this.deviceManager.getDevicesByRoom(this.selectedRoom);
  }

  private availableRoomIds(): string[] {
    const allRoomIds = this.deviceManager.getRoomIds();
    const result: string[] = [];
    for (let index = 0; index < allRoomIds.length; index++) {
      if (this.deviceManager.getDevicesByRoom(allRoomIds[index]).length > 0) {
        result.push(allRoomIds[index]);
      }
    }
    return result;
  }

  private displayRoomIds(): string[] {
    return ['living', 'bedroom', 'masterBedroom', 'bathroom'];
  }

  private roomLabel(roomId: string): string {
    if (roomId === 'living') {
      return '客厅';
    }
    if (roomId === 'bedroom') {
      return '卧室';
    }
    if (roomId === 'masterBedroom') {
      return '主卧';
    }
    if (roomId === 'bathroom') {
      return '浴室';
    }
    return roomId;
  }

  private featureTitle(featureId: string): string {
    if (featureId === 'lighting') {
      return '灯光';
    }
    if (featureId === 'environment') {
      return '环境';
    }
    if (featureId === 'locks') {
      return '门锁';
    }
    return featureId;
  }

  private featureIcon(featureId: string): string {
    if (featureId === 'lighting') {
      return '○';
    }
    if (featureId === 'environment') {
      return '≈';
    }
    if (featureId === 'locks') {
      return '⌂';
    }
    return '·';
  }

  private featureTint(featureId: string): string {
    if (featureId === 'lighting') {
      return '#FFF4D8';
    }
    if (featureId === 'environment') {
      return '#E8F8F3';
    }
    if (featureId === 'locks') {
      return '#EEF1FF';
    }
    return '#F2F5F9';
  }

  private featureSummary(feature: DeviceFeature): string {
    const devices = DeviceRegistry.getDevicesByFeature(this.deviceManager.devices, feature.id);
    if (feature.id === 'lighting') {
      return this.lightsOnCount().toString() + ' 盏开启 · 共 ' + devices.length.toString() + ' 盏';
    }
    if (feature.id === 'locks') {
      return devices.length.toString() + ' 把门锁 · 家庭安全入口';
    }
    return devices.length.toString() + ' 台设备 · 温湿度与空调';
  }

  private deviceIcon(device: DeviceInfo): string {
    if (device.type === DeviceType.LIGHT) {
      return '○';
    }
    if (device.type === DeviceType.ENVIRONMENT) {
      return '≈';
    }
    if (device.type === DeviceType.AIR_CONDITIONER) {
      return '❄';
    }
    return '⌂';
  }

  private deviceTint(device: DeviceInfo): string {
    if (device.type === DeviceType.LIGHT) {
      return '#FFF4D8';
    }
    if (device.type === DeviceType.ENVIRONMENT) {
      return '#E8F8F3';
    }
    if (device.type === DeviceType.AIR_CONDITIONER) {
      return '#EAF4FF';
    }
    return '#EEF1FF';
  }

  private deviceSummary(device: DeviceInfo): string {
    if (!device.online) {
      return '设备离线';
    }
    if (device.type === DeviceType.LIGHT) {
      const light = device as LightDevice;
      return light.state.power ? '开启 · 亮度 ' + light.state.brightness.toFixed(0) + '%' : '关闭';
    }
    if (device.type === DeviceType.ENVIRONMENT) {
      const environment = device as EnvironmentDevice;
      return environment.state.temperatureCelsius.toFixed(1) + '°C · ' +
        environment.state.humidityPercent.toFixed(0) + '% 湿度';
    }
    if (device.type === DeviceType.AIR_CONDITIONER) {
      const airConditioner = device as AirConditionerDevice;
      return airConditioner.state.power ?
        this.modeLabel(airConditioner.state.mode) + ' · ' +
          airConditioner.state.targetTemperatureCelsius.toFixed(0) + '°C' : '关闭';
    }
    const doorLock = device as DoorLockDevice;
    if (doorLock.state.jammed) {
      return '锁体异常';
    }
    return doorLock.state.locked ? '已上锁' : '已解锁';
  }

  private modeLabel(mode: string): string {
    if (mode === 'cool') {
      return '制冷';
    }
    if (mode === 'heat') {
      return '制热';
    }
    if (mode === 'dry') {
      return '除湿';
    }
    if (mode === 'fan') {
      return '送风';
    }
    return '自动';
  }

  private headerSubtitle(): string {
    return '全屋设备已连接 · ' + this.deviceManager.getConnectionLabel();
  }

  private averageTemperature(): string {
    const sensors = this.deviceManager.getEnvironmentDevices();
    if (sensors.length === 0) {
      return '--';
    }
    let total = 0;
    for (let index = 0; index < sensors.length; index++) {
      total += sensors[index].state.temperatureCelsius;
    }
    return (total / sensors.length).toFixed(1) + '°';
  }

  private averageHumidity(): string {
    const sensors = this.deviceManager.getEnvironmentDevices();
    if (sensors.length === 0) {
      return '--';
    }
    let total = 0;
    for (let index = 0; index < sensors.length; index++) {
      total += sensors[index].state.humidityPercent;
    }
    return (total / sensors.length).toFixed(0) + '%';
  }

  private lightsOnCount(): number {
    let count = 0;
    const lights = this.deviceManager.getLights();
    for (let index = 0; index < lights.length; index++) {
      if (lights[index].state.power) {
        count++;
      }
    }
    return count;
  }
}
