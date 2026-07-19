import { router } from '@kit.ArkUI';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { detectBarcode } from '@kit.ScanKit';
import { DeviceApplication } from '../model/DeviceApplication';
import { DeviceManager } from '../model/DeviceManager';
import { DeviceRegistry } from '../model/DeviceRegistry';
import {
  DeviceRegistrationQr,
  DeviceRegistrationRequest
} from '../service/DeviceRegistration';

class RoomSelectOption {
  value: string = '';
}

@Entry
@Component
struct AddDevice {
  @Provide deviceManager: DeviceManager = DeviceApplication.getDeviceManager();
  @State selectedImageUri: string = '';
  @State registrationRequest: DeviceRegistrationRequest | null = null;
  @State selectedRoomId: string = '';
  @State isRecognizing: boolean = false;
  @State isRegistering: boolean = false;
  @State isRedirecting: boolean = false;
  @State statusMessage: string = '';
  @State statusIsError: boolean = false;
  private roomNavigationTimer: number = -1;

  aboutToDisappear(): void {
    this.cancelRoomNavigation();
  }

  build() {
    Scroll() {
      Column() {
        this.Header()
        this.Introduction()
        this.ScanOption()
        this.GalleryOption()
        if (this.isRecognizing) {
          this.ProgressCard('正在识别二维码…')
        }
        if (this.registrationRequest !== null) {
          this.RegistrationSummary()
        }
        if (this.statusMessage.length > 0) {
          Text(this.statusMessage)
            .id('add-device-status')
            .fontSize(13)
            .fontColor(this.statusIsError ? '#B54747' : '#0F8F66')
            .width('100%')
            .padding(14)
            .backgroundColor(this.statusIsError ? '#FFF0F0' : '#EAF8F1')
            .borderRadius(16)
            .margin({ top: 14 })
        }
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 34, bottom: 28 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#DCEAF2')
    .scrollBar(BarState.Off)
  }

  @Builder
  Header() {
    Row() {
      Text('‹')
        .id('add-device-back-button')
        .fontSize(38)
        .fontColor('#14263A')
        .width(44)
        .height(48)
        .lineHeight(44)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          router.back();
        })
      Text('添加设备')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor('#14263A')
        .margin({ left: 8 })
    }
    .width('100%')
    .margin({ bottom: 22 })
  }

  @Builder
  Introduction() {
    Column() {
      Text('通过设备二维码安全接入')
        .fontSize(21)
        .fontWeight(FontWeight.Bold)
        .fontColor('#14263A')
      Text('二维码只携带设备声明与网关签名证明；请选择添加房间后，由已配对网关验证、探测并同步。')
        .fontSize(13)
        .fontColor('#617287')
        .lineHeight(20)
        .margin({ top: 8 })
    }
    .width('100%')
    .padding(18)
    .backgroundColor(Color.White)
    .borderRadius(22)
    .margin({ bottom: 14 })
  }

  @Builder
  ScanOption() {
    Row() {
      Text('⌁')
        .fontSize(30)
        .fontColor('#99A7B6')
        .width(48)
        .height(48)
        .textAlign(TextAlign.Center)
        .backgroundColor('#EEF2F6')
        .borderRadius(16)
      Column() {
        Text('扫描二维码')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor('#99A7B6')
        Text('敬请期待')
          .fontSize(12)
          .fontColor('#99A7B6')
          .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text('›')
        .fontSize(28)
        .fontColor('#B8C2CD')
    }
    .id('add-device-camera-disabled')
    .width('100%')
    .padding(16)
    .backgroundColor('#F7F9FB')
    .borderRadius(20)
    .opacity(0.78)
    .margin({ bottom: 12 })
  }

  @Builder
  GalleryOption() {
    Row() {
      Text('▣')
        .fontSize(26)
        .fontColor('#1769C2')
        .width(48)
        .height(48)
        .lineHeight(48)
        .textAlign(TextAlign.Center)
        .backgroundColor('#E4F0FF')
        .borderRadius(16)
      Column() {
        Text('从图库选择二维码')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor('#14263A')
        Text('选择一张包含设备二维码的图片')
          .fontSize(12)
          .fontColor('#748294')
          .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text('›')
        .fontSize(28)
        .fontColor('#1769C2')
    }
    .id('add-device-gallery-button')
    .width('100%')
    .padding(16)
    .backgroundColor(Color.White)
    .borderRadius(20)
    .enabled(!this.isRecognizing && !this.isRegistering)
    .onClick(() => {
      this.selectQrFromGallery();
    })
  }

  @Builder
  ProgressCard(message: string) {
    Text(message)
      .id('add-device-recognizing')
      .fontSize(14)
      .fontColor('#1769C2')
      .width('100%')
      .padding(16)
      .backgroundColor('#EAF4FF')
      .borderRadius(18)
      .margin({ top: 14 })
  }

  @Builder
  RegistrationSummary() {
    Column() {
      Text('已识别设备')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor('#14263A')
        .width('100%')
      this.SummaryRow('设备序列号', this.requestDeviceId())
      this.SummaryRow('设备名称', this.requestDeviceName())
      this.SummaryRow('设备类型', this.requestDeviceType())
      this.SummaryRow('功能分类', this.requestCategoryId())
      this.RoomSelectionRow()
      this.SummaryRow('能力接口', this.requestCapabilities())
      Text('网关认证证明已读取，将由已配对网关完成签名验证。')
        .fontSize(12)
        .fontColor('#617287')
        .lineHeight(18)
        .width('100%')
        .margin({ top: 10, bottom: 14 })
      Button(this.isRegistering ? '正在验证…' :
        (this.isRedirecting ? '即将跳转…' : '验证并添加设备'))
        .id('add-device-register-button')
        .width('100%')
        .height(48)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .backgroundColor('#1769C2')
        .borderRadius(16)
        .enabled(!this.isRegistering && !this.isRedirecting && this.deviceManager.isOnline() &&
          this.hasSelectedRoom())
        .onClick(() => {
          this.registerRecognizedDevice();
        })
      if (!this.deviceManager.isOnline()) {
        Text('请先连接已配对网关，再验证设备。')
          .fontSize(12)
          .fontColor('#B54747')
          .margin({ top: 8 })
      }
      if (this.deviceManager.isOnline() && !this.hasSelectedRoom()) {
        Text('当前没有可选择的房间，请先同步网关设备快照。')
          .fontSize(12)
          .fontColor('#B54747')
          .margin({ top: 8 })
      }
    }
    .id('add-device-summary')
    .width('100%')
    .padding(18)
    .backgroundColor(Color.White)
    .borderRadius(22)
    .margin({ top: 14 })
  }

  @Builder
  SummaryRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(13)
        .fontColor('#748294')
        .width(92)
      Text(value)
        .fontSize(13)
        .fontColor('#14263A')
        .fontWeight(FontWeight.Medium)
        .layoutWeight(1)
        .textAlign(TextAlign.End)
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
    .border({ width: { bottom: 1 }, color: '#EDF1F5' })
  }

  @Builder
  RoomSelectionRow() {
    Row() {
      Text('添加至房间')
        .fontSize(13)
        .fontColor('#748294')
        .width(92)
      if (this.selectableRoomIds().length > 0) {
        Select(this.roomSelectionOptions())
          .id('add-device-room-select')
          .selected(this.selectedRoomIndex())
          .font({ size: 13, weight: FontWeight.Medium })
          .fontColor('#1769C2')
          .width(176)
          .backgroundColor('#EAF4FF')
          .borderRadius(10)
          .onSelect((index: number) => {
            const roomIds = this.selectableRoomIds();
            if (index >= 0 && index < roomIds.length) {
              this.selectedRoomId = roomIds[index];
            }
          })
      } else {
        Text('暂无可用房间')
          .fontSize(13)
          .fontColor('#B54747')
          .layoutWeight(1)
          .textAlign(TextAlign.End)
      }
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
    .border({ width: { bottom: 1 }, color: '#EDF1F5' })
  }

  private async selectQrFromGallery(): Promise<void> {
    this.cancelRoomNavigation();
    this.isRedirecting = false;
    this.statusMessage = '';
    this.registrationRequest = null;
    this.selectedRoomId = '';
    const options = new photoAccessHelper.PhotoSelectOptions();
    options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
    options.maxSelectNumber = 1;
    try {
      const picker = new photoAccessHelper.PhotoViewPicker();
      const selected = await picker.select(options);
      if (selected.photoUris.length === 0) {
        return;
      }
      this.selectedImageUri = selected.photoUris[0];
      this.isRecognizing = true;
      const scanResults = await detectBarcode.decode({ uri: this.selectedImageUri });
      if (scanResults.length === 0 || scanResults[0].originalValue.length === 0) {
        this.showError('未在图片中识别到二维码，请选择清晰的设备二维码。');
        return;
      }
      this.registrationRequest = DeviceRegistrationQr.parse(scanResults[0].originalValue);
      this.selectedRoomId = this.defaultSelectedRoomId();
      this.statusIsError = false;
      this.statusMessage = '已读取设备声明，请选择添加房间后继续验证。';
    } catch (error) {
      const message = error instanceof Error && error.message.length > 0 ?
        error.message : '无法读取所选图片中的二维码';
      this.showError(message);
    } finally {
      this.isRecognizing = false;
    }
  }

  private async registerRecognizedDevice(): Promise<void> {
    const request = this.registrationRequest;
    if (request === null) {
      return;
    }
    if (!this.hasSelectedRoom()) {
      this.showError('请选择设备要添加到的房间。');
      return;
    }
    request.roomId = this.selectedRoomId;
    this.isRegistering = true;
    this.isRedirecting = false;
    this.statusMessage = '';
    try {
      const result = await this.deviceManager.registerDevice(request);
      this.statusIsError = !result.registered;
      if (result.registered) {
        this.statusMessage = '设备已添加，将在 1.5 秒后进入' +
          DeviceRegistry.getRoomLabel(this.selectedRoomId);
        this.scheduleRoomNavigation(this.selectedRoomId);
      } else {
        this.statusMessage = result.message;
      }
    } finally {
      this.isRegistering = false;
    }
  }

  private scheduleRoomNavigation(roomId: string): void {
    this.cancelRoomNavigation();
    this.isRedirecting = true;
    this.roomNavigationTimer = setTimeout(() => {
      this.roomNavigationTimer = -1;
      AppStorage.setOrCreate('homeSelectedRoom', roomId);
      router.back();
    }, 1500) as number;
  }

  private cancelRoomNavigation(): void {
    if (this.roomNavigationTimer !== -1) {
      clearTimeout(this.roomNavigationTimer);
      this.roomNavigationTimer = -1;
    }
  }

  private showError(message: string): void {
    this.statusIsError = true;
    this.statusMessage = message;
  }

  private requestDeviceId(): string {
    return this.registrationRequest === null ? '' : this.registrationRequest.deviceId;
  }

  private requestDeviceName(): string {
    return this.registrationRequest === null ? '' : this.registrationRequest.deviceName;
  }

  private requestDeviceType(): string {
    return this.registrationRequest === null ? '' : this.registrationRequest.deviceType;
  }

  private requestCategoryId(): string {
    return this.registrationRequest === null ? '' : this.registrationRequest.categoryId;
  }

  private requestCapabilities(): string {
    return this.registrationRequest === null ? '' : this.registrationRequest.capabilities.join('、');
  }

  private selectableRoomIds(): string[] {
    const allRoomIds = this.deviceManager.getRoomIds();
    const result: string[] = [];
    for (let index = 0; index < allRoomIds.length; index++) {
      const roomId = allRoomIds[index];
      if (this.deviceManager.getDevicesByRoom(roomId).length > 0) {
        result.push(roomId);
      }
    }
    return result;
  }

  private roomSelectionOptions(): RoomSelectOption[] {
    const roomIds = this.selectableRoomIds();
    const options: RoomSelectOption[] = [];
    for (let index = 0; index < roomIds.length; index++) {
      const option = new RoomSelectOption();
      option.value = DeviceRegistry.getRoomLabel(roomIds[index]);
      options.push(option);
    }
    return options;
  }

  private selectedRoomIndex(): number {
    const index = this.selectableRoomIds().indexOf(this.selectedRoomId);
    return index >= 0 ? index : 0;
  }

  private defaultSelectedRoomId(): string {
    const roomIds = this.selectableRoomIds();
    return roomIds.length > 0 ? roomIds[0] : '';
  }

  private hasSelectedRoom(): boolean {
    return this.selectableRoomIds().indexOf(this.selectedRoomId) >= 0;
  }
}
