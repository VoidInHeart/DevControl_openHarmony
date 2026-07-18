import { router } from '@kit.ArkUI';
import { DoorLockTab } from '../components/DoorLockTab';
import { LightingTab } from '../components/LightingTab';
import { TemperatureTab } from '../components/TemperatureTab';
import { GenericFeatureTab } from '../components/GenericFeatureTab';
import { DeviceApplication } from '../model/DeviceApplication';
import { DeviceManager } from '../model/DeviceManager';
import { DeviceRegistry } from '../model/DeviceRegistry';

@Entry
@Component
struct FeatureDevices {
  @Provide deviceManager: DeviceManager = DeviceApplication.getDeviceManager();
  @State featureId: string = '';

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, Object>;
    const featureId = params['featureId'];
    if (typeof featureId === 'string') {
      this.featureId = featureId;
    }
  }

  build() {
    Column() {
      this.NavigationHeader()
      if (this.featureId === 'lighting') {
        LightingTab()
      } else if (this.featureId === 'environment') {
        TemperatureTab()
      } else if (this.featureId === 'locks') {
        DoorLockTab()
      } else {
        GenericFeatureTab({ featureId: this.featureId })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#DCEAF2')
  }

  @Builder
  NavigationHeader() {
    Row() {
      Text('‹')
        .fontSize(40)
        .fontColor('#14263A')
        .width(44)
        .height(48)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          router.back();
        })
      Text(this.featureTitle())
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor('#14263A')
        .layoutWeight(1)
    }
    .width('100%')
    .height(64)
    .padding({ left: 8, right: 20 })
    .backgroundColor('#DCEAF2')
  }

  @Builder
  EmptyState() {
    Column() {
      Text(this.featureIcon())
        .fontSize(44)
      Text(this.featureTitle() + '暂未接入设备')
        .fontSize(19)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: 12 })
      Text('网关接入该类设备后，会自动显示在这里。')
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: 8 })
    }
    .width('100%')
    .layoutWeight(1)
    .padding(32)
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
  }

  private featureTitle(): string {
    const feature = DeviceRegistry.getFeature(this.featureId, this.deviceManager.devices);
    return feature === null ? '功能设备' : feature.title;
  }

  private featureIcon(): string {
    const feature = DeviceRegistry.getFeature(this.featureId, this.deviceManager.devices);
    return feature === null ? '⌂' : feature.icon;
  }
}
