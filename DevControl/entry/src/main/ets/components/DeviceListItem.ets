import { router } from '@kit.ArkUI';
import { DeviceInfo } from '../model/DeviceModel';
import { DeviceRegistry } from '../model/DeviceRegistry';

@Component
export struct DeviceListItem {
  @Prop device: DeviceInfo;

  build() {
    Row() {
      Text(this.deviceIcon())
        .fontSize(30)
        .width(48)
        .height(48)
        .textAlign(TextAlign.Center)
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

  private deviceSummary(): string {
    return DeviceRegistry.present(this.device).summary;
  }
}
