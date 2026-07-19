import { router } from '@kit.ArkUI';
import { immersiveCardEffect } from '../common/ImmersiveUi';
import { DeviceInfo } from '../model/DeviceModel';
import { DeviceRegistry } from '../model/DeviceRegistry';
import { GenericDevice } from '../model/GenericDeviceModel';
import { CurtainIcon } from './CurtainIcon';

@Component
export struct DeviceListItem {
  @Prop device: DeviceInfo;

  build() {
    Row() {
      Stack({ alignContent: Alignment.Center }) {
        if (this.isCurtainDevice()) {
          CurtainIcon({ iconSize: 30 })
        } else {
          Text(this.deviceIcon())
            .fontSize(30)
            .width(48)
            .height(48)
            .lineHeight(48)
            .textAlign(TextAlign.Center)
        }
      }
        .width(48)
        .height(48)
        .backgroundColor('#EAF5FF')
        .borderRadius(14)
      Column() {
        Text(this.device.name)
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.deviceSummary())
          .fontSize(13)
          .fontColor(this.device.online ? $r('app.color.text_secondary') :
            $r('app.color.status_offline'))
          .margin({ top: 4 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 12 })
      Text('›')
        .fontSize(30)
        .fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .padding(14)
    .margin({ bottom: 10 })
    .borderRadius(18)
    .backgroundColor(Color.White)
    .visualEffect(immersiveCardEffect())
    .clickEffect({ level: ClickEffectLevel.MIDDLE, scale: 0.985 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      router.pushUrl({
        url: 'pages/DeviceDetail',
        params: { deviceId: this.device.id }
      });
    })
  }

  private deviceIcon(): string {
    return DeviceRegistry.present(this.device).icon;
  }

  private isCurtainDevice(): boolean {
    return DeviceRegistry.getCapability(this.device.type) === null &&
      (this.device as GenericDevice).category.id === 'curtains';
  }

  private deviceSummary(): string {
    return DeviceRegistry.present(this.device).summary;
  }
}
