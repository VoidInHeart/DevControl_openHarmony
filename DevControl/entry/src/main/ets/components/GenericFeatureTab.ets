import { DeviceInfo } from '../model/DeviceModel';
import { DeviceManager } from '../model/DeviceManager';
import { DeviceRegistry } from '../model/DeviceRegistry';
import { DeviceListItem } from './DeviceListItem';

@Component
export struct GenericFeatureTab {
  @Consume deviceManager: DeviceManager;
  @Prop featureId: string = '';

  build() {
    Scroll() {
      Column() {
        if (this.devices().length === 0) {
          this.EmptyState()
        } else {
          ForEach(this.devices(), (device: DeviceInfo) => {
            DeviceListItem({ device: device })
          }, (device: DeviceInfo) => device.id + ':' + device.stateVersion.toString())
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 20, bottom: 28 })
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Auto)
  }

  @Builder
  EmptyState() {
    Column() {
      Text('暂无已接入设备')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
      Text('网关注册该类设备后会自动显示。')
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: 8 })
    }
    .width('100%')
    .padding(32)
    .borderRadius(20)
    .backgroundColor(Color.White)
    .alignItems(HorizontalAlign.Center)
  }

  private devices(): DeviceInfo[] {
    return DeviceRegistry.getDevicesByFeature(
      this.deviceManager.devices,
      this.featureId
    );
  }
}

