import { router } from '@kit.ArkUI';
import { DeviceApplication } from '../model/DeviceApplication';
import { DeviceManager } from '../model/DeviceManager';

@Entry
@Component
struct AddRoom {
  @Provide deviceManager: DeviceManager = DeviceApplication.getDeviceManager();
  @State roomName: string = '';
  @State isCreating: boolean = false;
  @State statusMessage: string = '';
  @State statusIsError: boolean = false;
  private returnTimer: number = -1;

  aboutToDisappear(): void {
    if (this.returnTimer !== -1) {
      clearTimeout(this.returnTimer);
      this.returnTimer = -1;
    }
  }

  build() {
    Scroll() {
      Column() {
        this.Header()
        this.Introduction()
        this.RoomForm()
        if (this.statusMessage.length > 0) {
          Text(this.statusMessage)
            .id('add-room-status')
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
        .id('add-room-back-button')
        .fontSize(38)
        .fontColor('#14263A')
        .width(44)
        .height(48)
        .lineHeight(44)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          router.back();
        })
      Text('添加房间')
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
      Text('为家新增一个房间')
        .fontSize(21)
        .fontWeight(FontWeight.Bold)
        .fontColor('#14263A')
      Text('新建后可在添加设备时从“添加至房间”菜单中选择它。房间由已配对网关统一保存和校验。')
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
  RoomForm() {
    Column() {
      Text('房间名称')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor('#14263A')
        .width('100%')
      TextInput({ placeholder: '例如：书房', text: this.roomName })
        .id('add-room-name-input')
        .fontSize(16)
        .fontColor('#14263A')
        .placeholderColor('#AAB5C2')
        .width('100%')
        .height(48)
        .backgroundColor('#F4F7FA')
        .borderRadius(12)
        .margin({ top: 10 })
        .onChange((value: string) => {
          this.roomName = value;
        })
      Text('名称最多 64 个字符，不能与现有房间重名。')
        .fontSize(12)
        .fontColor('#748294')
        .width('100%')
        .margin({ top: 10, bottom: 18 })
      Button(this.isCreating ? '正在创建…' : '创建房间')
        .id('add-room-submit-button')
        .width('100%')
        .height(48)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .backgroundColor('#1769C2')
        .borderRadius(16)
        .enabled(!this.isCreating && this.roomName.trim().length > 0 && this.deviceManager.isOnline())
        .onClick(() => {
          this.createRoom();
        })
      if (!this.deviceManager.isOnline()) {
        Text('请先连接已配对网关，再创建房间。')
          .fontSize(12)
          .fontColor('#B54747')
          .width('100%')
          .margin({ top: 10 })
      }
    }
    .id('add-room-form')
    .width('100%')
    .padding(18)
    .backgroundColor(Color.White)
    .borderRadius(22)
  }

  private async createRoom(): Promise<void> {
    const name = this.roomName.trim();
    if (name.length === 0 || name.length > 64) {
      this.statusIsError = true;
      this.statusMessage = '请输入 1 到 64 个字符的房间名称。';
      return;
    }
    this.isCreating = true;
    this.statusMessage = '';
    const room = await this.deviceManager.createRoom(this.newRoomId(), name);
    this.isCreating = false;
    if (room === null) {
      this.statusIsError = true;
      this.statusMessage = this.deviceManager.lastError.length > 0 ?
        this.deviceManager.lastError : '房间创建失败，请稍后重试。';
      return;
    }
    this.statusIsError = false;
    this.statusMessage = room.name + '已创建，可在添加设备时选择。';
    AppStorage.setOrCreate('homeSelectedRoom', room.id);
    this.returnTimer = setTimeout(() => {
      this.returnTimer = -1;
      router.back();
    }, 1000) as number;
  }

  private newRoomId(): string {
    return 'room-' + Date.now().toString();
  }
}
