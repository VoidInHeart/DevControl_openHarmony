import { router } from '@kit.ArkUI';
import { DeviceFeature, DeviceRegistry } from '../model/DeviceRegistry';
import { DeviceManager } from '../model/DeviceManager';

@Component
export struct ControlCenterTab {
  @Consume deviceManager: DeviceManager;

  build() {
    Scroll() {
      Column() {
        this.HomeHeader()
        this.FeatureSection()
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#EAF5FF')
    .scrollBar(BarState.Auto)
  }

  @Builder
  HomeHeader() {
    Column() {
      Row() {
        Column() {
          Text('我的全屋')
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
          Text(this.headerSubtitle())
            .fontSize(13)
            .fontColor('#CDEBFF')
            .margin({ top: 6 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Text('⌂')
          .fontSize(30)
          .fontColor(Color.White)
      }
      .width('100%')
      this.MetricRow()
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 28, bottom: 22 })
    .backgroundColor('#197FC7')
  }

  @Builder
  MetricRow() {
    Row() {
      this.MetricCard('🌡', this.averageTemperature(), '温度')
      this.MetricCard('💧', this.averageHumidity(), '湿度')
      this.MetricCard('💡', this.lightsOnCount().toString(), '亮灯')
      this.MetricCard('●', this.deviceManager.getOnlineCount().toString(), '在线')
    }
    .width('100%')
    .margin({ top: 22 })
    .justifyContent(FlexAlign.SpaceBetween)
  }

  @Builder
  MetricCard(icon: string, value: string, label: string) {
    Column() {
      Text(icon)
        .fontSize(22)
      Text(value)
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor(Color.White)
        .margin({ top: 4 })
      Text(label)
        .fontSize(11)
        .fontColor('#CDEBFF')
        .margin({ top: 2 })
    }
    .width('23%')
    .padding({ top: 10, bottom: 10 })
    .borderRadius(16)
    .backgroundColor('#287FBA')
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  FeatureSection() {
    Column() {
      Text('全屋功能')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .margin({ bottom: 12 })
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
        ForEach(DeviceRegistry.getHomeFeatures(), (feature: DeviceFeature) => {
          this.FeatureCard(feature)
        }, (feature: DeviceFeature) => feature.id)
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 20, bottom: 28 })
  }

  @Builder
  FeatureCard(feature: DeviceFeature) {
    Column() {
      Row() {
        Text(feature.icon)
          .fontSize(34)
        Blank()
        Text('›')
          .fontSize(30)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      Text(feature.title)
        .fontSize(19)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .margin({ top: 20 })
      Text(this.featureSummary(feature))
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .margin({ top: 6 })
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('48.5%')
    .height(170)
    .padding(16)
    .margin({ bottom: 12 })
    .borderRadius(20)
    .backgroundColor(Color.White)
    .onClick(() => {
      this.openFeature(feature.id);
    })
  }

  private openFeature(featureId: string): void {
    router.pushUrl({
      url: 'pages/FeatureDevices',
      params: { featureId: featureId }
    });
  }

  private featureSummary(feature: DeviceFeature): string {
    const devices = DeviceRegistry.getDevicesByFeature(this.deviceManager.devices, feature.id);
    if (devices.length === 0) {
      return feature.id === 'curtains' ? '暂未接入窗帘设备' : '暂无已接入设备';
    }
    if (feature.id === 'lighting') {
      return this.lightsOnCount().toString() + ' 盏已开启 · 共 ' + devices.length.toString() + ' 盏';
    }
    if (feature.id === 'locks') {
      return devices.length.toString() + ' 把门锁 · 全屋安全入口';
    }
    return devices.length.toString() + ' 台设备 · 温湿度与空调';
  }

  private headerSubtitle(): string {
    return this.deviceManager.getOnlineCount().toString() + ' 台设备在线 · ' +
      this.deviceManager.getConnectionLabel();
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
