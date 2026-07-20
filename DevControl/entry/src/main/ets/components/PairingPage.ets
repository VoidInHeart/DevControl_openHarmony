import { DeviceManager } from '../model/DeviceManager';

@Component
export struct PairingPage {
  @Consume deviceManager: DeviceManager;
  @State gatewayAddress: string = '';
  @State pairingCode: string = '';
  onPairingSucceeded: () => void = () => {
  };

  aboutToAppear(): void {
    if (this.deviceManager.lastGatewayAddress.length > 0) {
      this.gatewayAddress = this.deviceManager.lastGatewayAddress;
    }
  }

  build() {
    Scroll() {
      Column() {
        Text('鸿途智联')
          .fontSize(32)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary'))
          .margin({ top: 56 })

        Text('安全连接家庭虚拟网关')
          .fontSize(16)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 8, bottom: 36 })

        Column() {
          Text('网关 HTTPS 地址')
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
          TextInput({ text: this.gatewayAddress, placeholder: '例如：https://192.168.1.8:8443' })
            .width('100%')
            .margin({ top: 8, bottom: 20 })
            .onChange((value: string) => {
              this.gatewayAddress = value;
            })

          Text('六位一次性配对码')
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
          TextInput({ text: this.pairingCode, placeholder: '输入网关终端显示的六码' })
            .width('100%')
            .maxLength(6)
            .type(InputType.Number)
            .margin({ top: 8, bottom: 24 })
            .onChange((value: string) => {
              this.pairingCode = value;
            })

          Button(this.deviceManager.pairingBusy ? '正在验证并配对…' : '安全配对')
            .width('100%')
            .height(48)
            .enabled(!this.deviceManager.pairingBusy)
            .opacity(this.deviceManager.pairingBusy ? 0.6 : 1)
            .onClick(() => {
              this.deviceManager.pairGateway(this.gatewayAddress, this.pairingCode)
                .then((paired: boolean) => {
                  if (paired) {
                    this.onPairingSucceeded();
                  }
                });
            })

          if (this.deviceManager.lastError.length > 0) {
            Text(this.deviceManager.lastError)
              .fontSize(13)
              .fontColor($r('app.color.status_alert'))
              .width('100%')
              .textAlign(TextAlign.Center)
              .margin({ top: 16 })
          }
        }
        .width('100%')
        .padding(24)
        .borderRadius(20)
        .backgroundColor($r('app.color.card_background'))

        Text('仅支持 HTTPS/WSS；证书无效时不会降级到明文连接。')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .textAlign(TextAlign.Center)
          .margin({ top: 20 })
      }
      .width('100%')
      .padding({ left: 24, right: 24, bottom: 40 })
    }
    .width('100%')
    .height('100%')
  }
}

