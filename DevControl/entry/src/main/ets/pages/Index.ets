import { common } from '@kit.AbilityKit';
import { ControlCenterTab } from '../components/ControlCenterTab';
import { PairingPage } from '../components/PairingPage';
import { SettingsTab } from '../components/SettingsTab';
import { DeviceApplication } from '../model/DeviceApplication';
import { DeviceManager } from '../model/DeviceManager';
import { SceneExecutionDetail } from '../model/DeviceModel';

@Entry
@Component
struct Index {
  @Provide deviceManager: DeviceManager = DeviceApplication.getDeviceManager();
  @State currentTab: string = 'home';
  @State smartDetailTemplateId: string = '';
  @State smartSavedDetailType: string = '';
  @State showCustomComposer: boolean = false;
  @State customCondition: string = 'motionDark';
  @State customAction: string = 'livingLight';
  @State savedTemplateId: string = '';
  @State savedTemplateTitle: string = '';
  @State savedCustomTitle: string = '';
  @State savedCustomConditionId: string = '';
  @State savedCustomActionId: string = '';
  @State savedCustomCondition: string = '';
  @State savedCustomAction: string = '';
  @State savedTemplateEnabled: boolean = true;
  @State savedCustomEnabled: boolean = true;
  @State smartBusy: boolean = false;
  @State smartMessage: string = '';

  aboutToAppear(): void {
    const context = getContext(this) as common.UIAbilityContext;
    this.deviceManager.initialize(context);
  }

  onPageShow(): void {
    if (
      this.deviceManager.initialized &&
      !this.deviceManager.pairingRequired &&
      !this.deviceManager.isOnline()
    ) {
      this.deviceManager.reconnect();
    }
  }

  build() {
    Column() {
      if (this.deviceManager.pairingRequired) {
        PairingPage()
      } else {
        Column() {
          if (this.currentTab === 'home') {
            ControlCenterTab()
          } else if (this.currentTab === 'smart') {
            this.SmartTab()
          } else {
            SettingsTab()
          }
        }
        .width('100%')
        .layoutWeight(1)
        this.BottomTabBar()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#DCEAF2')
  }

  @Builder
  BottomTabBar() {
    Row() {
      this.TabButton('home', '⌂', '家')
      this.TabButton('smart', '↯', '智能')
      this.TabButton('settings', '○', '设置')
    }
    .width('100%')
    .height(68)
    .padding({ left: 28, right: 28, top: 4, bottom: 6 })
    .justifyContent(FlexAlign.SpaceBetween)
    .backgroundColor(Color.White)
  }

  @Builder
  TabButton(tab: string, icon: string, label: string) {
    Column() {
      Text(icon)
        .fontSize(27)
        .fontWeight(FontWeight.Bold)
        .fontColor(tab === this.currentTab ? '#1769C2' : '#6F8094')
        .opacity(1)
      Text(label)
        .fontSize(12)
        .fontWeight(tab === this.currentTab ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(tab === this.currentTab ? '#1769C2' : '#6F8094')
        .opacity(1)
        .margin({ top: 2 })
    }
    .width(78)
    .height(56)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(Color.Transparent)
    .borderRadius(22)
    .onClick(() => {
      this.currentTab = tab;
    })
  }

  @Builder
  SmartTab() {
    if (this.smartSavedDetailType.length > 0) {
      this.SavedRuleDetailPage()
    } else if (this.smartDetailTemplateId.length > 0) {
      this.TemplateDetailPage()
    } else {
      this.SmartHomePage()
    }
  }

  @Builder
  SmartHomePage() {
    Scroll() {
      Column() {
        Row() {
          Column() {
            Text('我的智能')
              .fontSize(30)
              .fontWeight(FontWeight.Bold)
              .fontColor('#14263A')
            Text(this.smartSubtitle())
              .fontSize(13)
              .fontColor('#748294')
              .margin({ top: 6 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Text('+')
            .fontSize(30)
            .fontWeight(FontWeight.Medium)
            .fontColor('#14263A')
            .width(48)
            .height(48)
            .textAlign(TextAlign.Center)
            .backgroundColor('#F7FBFF')
            .borderRadius(18)
            .onClick(() => {
              this.showCustomComposer = !this.showCustomComposer;
            })
        }
        .width('100%')
        .margin({ bottom: 18 })

        if (this.smartMessage.length > 0) {
          Text(this.smartMessage)
            .fontSize(12)
            .fontColor('#0F8F66')
            .width('100%')
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .backgroundColor('#EAF8F1')
            .borderRadius(14)
            .margin({ bottom: 12 })
        }

        if (this.showCustomComposer) {
          this.CustomComposer()
        }

        this.MySmartPanel()
        this.QuickScenePanel()
        this.RecommendExplorePanel()
        this.SceneResultPanel()
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
  MySmartPanel() {
    Column() {
      Row() {
        Text('正在运行')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#14263A')
          .layoutWeight(1)
        Text(this.runningRuleCountText())
          .fontSize(12)
          .fontColor('#748294')
      }
      .width('100%')
      .margin({ bottom: 12 })

      if (!this.hasSavedSmartRules()) {
        Column() {
          Text('还没有自动化')
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor('#14263A')
          Text('点右上角加号创建，或从下面推荐模板里选择一个。')
            .fontSize(12)
            .fontColor('#748294')
            .margin({ top: 6 })
        }
        .width('100%')
        .padding(18)
        .alignItems(HorizontalAlign.Start)
        .backgroundColor('#F7FBFF')
        .borderRadius(18)
      } else {
        if (this.savedTemplateTitle.length > 0) {
          this.SavedTemplateRuleRow()
        }
        if (this.savedCustomTitle.length > 0) {
          this.SavedCustomRuleRow()
        }
      }
    }
    .width('100%')
    .padding(18)
    .backgroundColor(Color.White)
    .borderRadius(24)
    .margin({ bottom: 14 })
  }

  @Builder
  SavedTemplateRuleRow() {
    Row() {
      Column() {
        Text(this.savedTemplateEnabled ? '启用' : '暂停')
          .fontSize(12)
          .fontColor(this.savedTemplateEnabled ? '#0F8F66' : '#748294')
      }
      .width(46)
      .height(46)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(this.savedTemplateEnabled ? '#EAF8F1' : '#F2F5F9')
      .borderRadius(17)
      Column() {
        Text(this.savedTemplateTitle)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor('#14263A')
        Text('当 ' + this.templateCondition(this.savedTemplateId))
          .fontSize(12)
          .fontColor('#748294')
          .margin({ top: 5 })
        Text('执行 ' + this.templateAction(this.savedTemplateId))
          .fontSize(12)
          .fontColor('#748294')
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 12 })
      Toggle({ type: ToggleType.Switch, isOn: this.savedTemplateEnabled })
        .selectedColor('#1769C2')
        .onChange((value: boolean) => {
          this.savedTemplateEnabled = value;
        })
    }
    .width('100%')
    .padding({ top: 12, bottom: 12 })
    .onClick(() => {
      this.smartSavedDetailType = 'template';
    })
  }

  @Builder
  SavedCustomRuleRow() {
    Row() {
      Column() {
        Text(this.savedCustomEnabled ? '启用' : '暂停')
          .fontSize(12)
          .fontColor(this.savedCustomEnabled ? '#0F8F66' : '#748294')
      }
      .width(46)
      .height(46)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(this.savedCustomEnabled ? '#EAF8F1' : '#F2F5F9')
      .borderRadius(17)
      Column() {
        Text(this.savedCustomTitle)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor('#14263A')
        Text('当 ' + this.savedCustomCondition)
          .fontSize(12)
          .fontColor('#748294')
          .margin({ top: 5 })
        Text('执行 ' + this.savedCustomAction)
          .fontSize(12)
          .fontColor('#748294')
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 12 })
      Toggle({ type: ToggleType.Switch, isOn: this.savedCustomEnabled })
        .selectedColor('#1769C2')
        .onChange((value: boolean) => {
          this.savedCustomEnabled = value;
        })
    }
    .width('100%')
    .padding({ top: 12, bottom: 12 })
    .onClick(() => {
      this.smartSavedDetailType = 'custom';
    })
  }

  @Builder
  QuickScenePanel() {
    Column() {
      Text('常用场景')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor('#14263A')
        .width('100%')
        .margin({ bottom: 12 })
      Row() {
        this.SceneShortcut('回家', '开常用灯和空调', true)
        this.SceneShortcut('离家', '关灯关空调并锁门', false)
      }
      .width('100%')
    }
    .width('100%')
    .padding(18)
    .backgroundColor(Color.White)
    .borderRadius(24)
    .margin({ bottom: 14 })
  }

  @Builder
  SceneShortcut(title: string, subtitle: string, home: boolean) {
    Column() {
      Text(title)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(home ? '#1769C2' : '#14263A')
      Text(subtitle)
        .fontSize(12)
        .fontColor('#748294')
        .margin({ top: 6 })
    }
    .layoutWeight(1)
    .height(86)
    .padding(14)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(home ? '#EAF4FF' : '#F7FBFF')
    .borderRadius(20)
    .margin({ right: home ? 10 : 0 })
    .onClick(() => {
      if (home) {
        this.deviceManager.executeHomeScene();
        this.smartMessage = '已执行回家场景。';
      } else {
        this.deviceManager.executeAwayScene();
        this.smartMessage = '已执行离家场景。';
      }
    })
  }

  @Builder
  RecommendExplorePanel() {
    Column() {
      Row() {
        Text('推荐探索')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#14263A')
          .layoutWeight(1)
        Text('可直接保存')
          .fontSize(12)
          .fontColor('#748294')
      }
      .width('100%')
      .margin({ bottom: 12 })

      this.HeroTemplateCard('motionLight')
      Text('舒适环境')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor('#14263A')
        .width('100%')
        .margin({ top: 14, bottom: 10 })
      Row() {
        this.SmallTemplateCard('cooling')
        this.SmallTemplateCard('heating')
      }
      .width('100%')
      Text('日常生活')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor('#14263A')
        .width('100%')
        .margin({ top: 14, bottom: 10 })
      Row() {
        this.SmallTemplateCard('away')
        this.SmallTemplateCard('humidityDry')
      }
      .width('100%')
    }
    .width('100%')
    .padding(18)
    .backgroundColor(Color.White)
    .borderRadius(24)
    .margin({ bottom: 14 })
  }

  @Builder
  HeroTemplateCard(templateId: string) {
    Column() {
      Row() {
        Column() {
          Text(this.templateTag(templateId))
            .fontSize(12)
            .fontColor('#748294')
          Text(this.templateTitle(templateId))
            .fontSize(23)
            .fontWeight(FontWeight.Bold)
            .fontColor('#14263A')
            .margin({ top: 8 })
          Text(this.templateShortLine(templateId))
            .fontSize(13)
            .fontColor('#748294')
            .margin({ top: 10 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Text('去看看')
          .fontSize(13)
          .fontColor('#1769C2')
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .backgroundColor('#EAF4FF')
          .borderRadius(14)
      }
      .width('100%')
      Row() {
        Text(this.templateIcon(templateId))
          .fontSize(26)
          .fontColor('#1769C2')
        Text('→')
          .fontSize(18)
          .fontColor('#AEB9C6')
          .margin({ left: 18, right: 18 })
        Text(this.templateResultIcon(templateId))
          .fontSize(26)
          .fontColor('#1769C2')
      }
      .margin({ top: 24 })
      .width('100%')
    }
    .width('100%')
    .padding(18)
    .backgroundColor('#F7FBFF')
    .borderRadius(22)
    .onClick(() => {
      this.smartDetailTemplateId = templateId;
    })
  }

  @Builder
  SmallTemplateCard(templateId: string) {
    Column() {
      Text(this.templateTitle(templateId))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor('#14263A')
        .width('100%')
      Text(this.templateShortLine(templateId))
        .fontSize(12)
        .fontColor('#748294')
        .width('100%')
        .margin({ top: 6 })
      Row() {
        Text(this.templateIcon(templateId))
          .fontSize(22)
          .fontColor('#1769C2')
        Text('→')
          .fontSize(15)
          .fontColor('#AEB9C6')
          .margin({ left: 10, right: 10 })
        Text(this.templateResultIcon(templateId))
          .fontSize(22)
          .fontColor('#1769C2')
      }
      .margin({ top: 24 })
    }
    .layoutWeight(1)
    .height(150)
    .padding(14)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor('#F7FBFF')
    .borderRadius(20)
    .margin({ right: 10 })
    .onClick(() => {
      this.smartDetailTemplateId = templateId;
    })
  }

  @Builder
  CustomComposer() {
    Column() {
      Text('创建自动化')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor('#14263A')
        .width('100%')
      Text('当以下情况发生')
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor('#14263A')
        .width('100%')
        .margin({ top: 16, bottom: 8 })
      Row() {
        this.ConditionButton('motionDark', '有人且较暗')
        this.ConditionButton('humidityHigh', '湿度偏高')
        this.ConditionButton('doorUnlocked', '门锁解开')
      }
      .width('100%')
      Text('将设备调整到')
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor('#14263A')
        .width('100%')
        .margin({ top: 16, bottom: 8 })
      Row() {
        this.ActionButton('livingLight', '打开灯光')
        this.ActionButton('dryMode', '空调除湿')
        this.ActionButton('awayScene', '离家保护')
      }
      .width('100%')
      Button(this.smartBusy ? '创建中' : '创建')
        .width('100%')
        .height(46)
        .fontColor(Color.White)
        .backgroundColor('#1769C2')
        .borderRadius(18)
        .margin({ top: 16 })
        .enabled(!this.smartBusy)
        .onClick(() => {
          this.saveCustomAutomation();
        })
    }
    .width('100%')
    .padding(18)
    .backgroundColor(Color.White)
    .borderRadius(24)
    .margin({ bottom: 14 })
  }

  @Builder
  ConditionButton(value: string, label: string) {
    Text(label)
      .fontSize(12)
      .fontColor(this.customCondition === value ? '#1769C2' : '#14263A')
      .textAlign(TextAlign.Center)
      .height(42)
      .layoutWeight(1)
      .backgroundColor(this.customCondition === value ? '#EAF4FF' : '#F7FBFF')
      .borderRadius(16)
      .margin({ right: 8 })
      .onClick(() => {
        this.customCondition = value;
      })
  }

  @Builder
  ActionButton(value: string, label: string) {
    Text(label)
      .fontSize(12)
      .fontColor(this.customAction === value ? '#1769C2' : '#14263A')
      .textAlign(TextAlign.Center)
      .height(42)
      .layoutWeight(1)
      .backgroundColor(this.customAction === value ? '#EAF4FF' : '#F7FBFF')
      .borderRadius(16)
      .margin({ right: 8 })
      .onClick(() => {
        this.customAction = value;
      })
  }

  @Builder
  TemplateDetailPage() {
    Column() {
      Row() {
        Text('‹')
          .fontSize(38)
          .fontColor('#14263A')
          .width(46)
          .height(46)
          .onClick(() => {
            this.smartDetailTemplateId = '';
          })
        Blank()
      }
      .width('100%')
      Text(this.templateTitle(this.smartDetailTemplateId))
        .fontSize(34)
        .fontWeight(FontWeight.Bold)
        .fontColor('#14263A')
        .width('100%')
        .margin({ top: 12, bottom: 28 })

      this.DetailBlock('当以下情况发生', this.templateIcon(this.smartDetailTemplateId),
        this.templateCondition(this.smartDetailTemplateId))
      this.DetailBlock('将设备调整到', this.templateResultIcon(this.smartDetailTemplateId),
        this.templateAction(this.smartDetailTemplateId))
      this.DetailBlock('生效时间段', '24h', '全天')

      Blank()
      Row() {
        Button('编辑更多')
          .layoutWeight(1)
          .height(50)
          .fontColor('#14263A')
          .backgroundColor('#EEF3F7')
          .borderRadius(18)
          .margin({ right: 12 })
          .onClick(() => {
            this.customCondition = this.templateCustomCondition(this.smartDetailTemplateId);
            this.customAction = this.templateCustomAction(this.smartDetailTemplateId);
            this.showCustomComposer = true;
            this.smartDetailTemplateId = '';
          })
        Button(this.smartBusy ? '保存中' : '保存到我的智能')
          .layoutWeight(1)
          .height(50)
          .fontColor(Color.White)
          .backgroundColor('#1769C2')
          .borderRadius(18)
          .enabled(!this.smartBusy)
          .onClick(() => {
            this.createTemplate(this.smartDetailTemplateId);
          })
      }
      .width('100%')
      .margin({ bottom: 18 })
    }
    .width('100%')
    .height('100%')
    .padding({ left: 24, right: 24, top: 42, bottom: 18 })
    .backgroundColor('#DCEAF2')
  }

  @Builder
  SavedRuleDetailPage() {
    Column() {
      Row() {
        Text('‹')
          .fontSize(38)
          .fontColor('#14263A')
          .width(46)
          .height(46)
          .onClick(() => {
            this.smartSavedDetailType = '';
          })
        Blank()
      }
      .width('100%')

      Text(this.savedDetailTitle())
        .fontSize(32)
        .fontWeight(FontWeight.Bold)
        .fontColor('#14263A')
        .width('100%')
        .margin({ top: 12, bottom: 22 })

      Row() {
        Text(this.savedDetailEnabled() ? '已启用' : '已暂停')
          .fontSize(13)
          .fontColor(this.savedDetailEnabled() ? '#0F8F66' : '#748294')
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.savedDetailEnabled() })
          .selectedColor('#1769C2')
          .onChange((value: boolean) => {
            if (this.smartSavedDetailType === 'template') {
              this.savedTemplateEnabled = value;
            } else {
              this.savedCustomEnabled = value;
            }
          })
      }
      .width('100%')
      .padding(18)
      .backgroundColor(Color.White)
      .borderRadius(24)
      .margin({ bottom: 14 })

      this.DetailBlock('当以下情况发生', '当', this.savedDetailCondition())
      this.DetailBlock('将设备调整到', '做', this.savedDetailAction())
      this.DetailBlock('执行位置', '网关', '保存后通过网关下发控制命令，App 负责展示和管理。')

      Blank()
      Button(this.smartBusy ? '运行中' : '运行一次')
        .width('100%')
        .height(50)
        .fontColor(Color.White)
        .backgroundColor('#1769C2')
        .borderRadius(18)
        .enabled(!this.smartBusy)
        .margin({ bottom: 18 })
        .onClick(() => {
          this.runSavedRuleOnce();
        })
    }
    .width('100%')
    .height('100%')
    .padding({ left: 24, right: 24, top: 42, bottom: 18 })
    .backgroundColor('#DCEAF2')
  }

  @Builder
  DetailBlock(title: string, icon: string, body: string) {
    Row() {
      Text(icon)
        .fontSize(22)
        .fontColor('#1769C2')
        .width(54)
        .height(54)
        .textAlign(TextAlign.Center)
        .backgroundColor('#EAF4FF')
        .borderRadius(18)
      Column() {
        Text(title)
          .fontSize(14)
          .fontColor('#748294')
        Text(body)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#14263A')
          .margin({ top: 6 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 14 })
    }
    .width('100%')
    .padding(18)
    .backgroundColor(Color.White)
    .borderRadius(24)
    .margin({ bottom: 14 })
  }

  @Builder
  SceneResultPanel() {
    Column() {
      Text('最近场景结果')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor('#14263A')
        .width('100%')
      if (this.deviceManager.sceneResults.length === 0) {
        Text('执行回家或离家后，这里会显示每个设备的结果。')
          .fontSize(13)
          .fontColor('#748294')
          .width('100%')
          .margin({ top: 8 })
      } else {
        ForEach(this.deviceManager.sceneResults, (item: SceneExecutionDetail) => {
          Row() {
            Text(item.deviceId)
              .fontSize(12)
              .fontColor('#748294')
              .layoutWeight(1)
            Text(item.success ? '成功' : item.errorCode)
              .fontSize(12)
              .fontColor(item.success ? '#0F8F66' : '#D64545')
          }
          .width('100%')
          .margin({ top: 10 })
        }, (item: SceneExecutionDetail) => item.deviceId)
      }
    }
    .width('100%')
    .padding(18)
    .borderRadius(24)
    .backgroundColor(Color.White)
  }

  private async createTemplate(templateId: string): Promise<void> {
    if (templateId.length === 0) {
      return;
    }
    this.smartBusy = true;
    this.smartMessage = '';
    try {
      await this.deviceManager.applySmartTemplate(templateId);
      this.savedTemplateId = templateId;
      this.savedTemplateTitle = this.templateTitle(templateId);
      this.savedTemplateEnabled = true;
      this.smartDetailTemplateId = '';
      this.smartMessage = '已保存到我的智能，并已下发到网关执行。';
    } catch (error) {
      this.smartMessage = '创建失败，请确认网关在线后再试。';
    } finally {
      this.smartBusy = false;
    }
  }

  private async saveCustomAutomation(): Promise<void> {
    this.smartBusy = true;
    this.smartMessage = '';
    try {
      await this.deviceManager.applyCustomAutomation(this.customCondition, this.customAction);
      this.savedCustomTitle = this.conditionLabel() + '自动化';
      this.savedCustomConditionId = this.customCondition;
      this.savedCustomActionId = this.customAction;
      this.savedCustomCondition = this.conditionLabel();
      this.savedCustomAction = this.actionLabel();
      this.savedCustomEnabled = true;
      this.showCustomComposer = false;
      this.smartMessage = '自动化已创建，并已下发相关网关控制。';
    } catch (error) {
      this.smartMessage = '创建失败，请确认网关在线后再试。';
    } finally {
      this.smartBusy = false;
    }
  }

  private hasSavedSmartRules(): boolean {
    return this.savedTemplateTitle.length > 0 || this.savedCustomTitle.length > 0;
  }

  private smartSubtitle(): string {
    if (this.hasSavedSmartRules()) {
      return '规则可以单独开关，也可以点进去运行一次';
    }
    return '从推荐方案保存，或自己组合条件和动作';
  }

  private runningRuleCountText(): string {
    let count = 0;
    if (this.savedTemplateTitle.length > 0 && this.savedTemplateEnabled) {
      count += 1;
    }
    if (this.savedCustomTitle.length > 0 && this.savedCustomEnabled) {
      count += 1;
    }
    return count.toFixed(0) + ' 条启用';
  }

  private templateTitle(templateId: string): string {
    if (templateId === 'cooling') {
      return '空调自动制冷模式';
    }
    if (templateId === 'heating') {
      return '空调自动制热模式';
    }
    if (templateId === 'away') {
      return '离家保护';
    }
    if (templateId === 'humidityDry') {
      return '湿度过高自动除湿';
    }
    if (templateId === 'home') {
      return '欢迎回家';
    }
    return '人来灯亮';
  }

  private templateTag(templateId: string): string {
    if (templateId === 'motionLight') {
      return '灯光照明';
    }
    if (templateId === 'away' || templateId === 'home') {
      return '日常生活';
    }
    return '舒适环境';
  }

  private templateShortLine(templateId: string): string {
    if (templateId === 'away') {
      return '一键关灯、关空调、锁门';
    }
    if (templateId === 'cooling') {
      return '温度偏高时进入制冷';
    }
    if (templateId === 'heating') {
      return '温度偏低时进入制热';
    }
    if (templateId === 'humidityDry') {
      return '浴室湿度偏高时除湿';
    }
    return '有人经过且光线暗时开灯';
  }

  private templateCondition(templateId: string): string {
    if (templateId === 'away') {
      return '点击离家按钮或运行本规则';
    }
    if (templateId === 'cooling') {
      return '室温高于 28°C';
    }
    if (templateId === 'heating') {
      return '室温低于 18°C';
    }
    if (templateId === 'humidityDry') {
      return '浴室湿度高于 70%';
    }
    return '人体传感器检测到有人，且光照低于阈值';
  }

  private templateAction(templateId: string): string {
    if (templateId === 'away') {
      return '关闭灯光和空调，并锁定入户门';
    }
    if (templateId === 'cooling') {
      return '打开空调，制冷 24°C，风速自动';
    }
    if (templateId === 'heating') {
      return '打开空调，制热 26°C，低风';
    }
    if (templateId === 'humidityDry') {
      return '打开空调除湿，中风运行';
    }
    return '打开同房间灯光，无人 60 秒后关闭';
  }

  private templateIcon(templateId: string): string {
    if (templateId === 'away' || templateId === 'home') {
      return '⌂';
    }
    if (templateId === 'cooling' || templateId === 'heating' || templateId === 'humidityDry') {
      return '≈';
    }
    return '○';
  }

  private templateResultIcon(templateId: string): string {
    if (templateId === 'away') {
      return '□';
    }
    if (templateId === 'cooling' || templateId === 'heating' || templateId === 'humidityDry') {
      return '❄';
    }
    return '●';
  }

  private templateCustomCondition(templateId: string): string {
    if (templateId === 'humidityDry') {
      return 'humidityHigh';
    }
    if (templateId === 'away') {
      return 'doorUnlocked';
    }
    return 'motionDark';
  }

  private templateCustomAction(templateId: string): string {
    if (templateId === 'humidityDry' || templateId === 'cooling' || templateId === 'heating') {
      return 'dryMode';
    }
    if (templateId === 'away') {
      return 'awayScene';
    }
    return 'livingLight';
  }

  private templateConditionByTitle(title: string): string {
    if (title === '空调自动制冷模式') {
      return this.templateCondition('cooling');
    }
    if (title === '空调自动制热模式') {
      return this.templateCondition('heating');
    }
    if (title === '离家关电器') {
      return this.templateCondition('away');
    }
    if (title === '湿度过高自动除湿') {
      return this.templateCondition('humidityDry');
    }
    return this.templateCondition('motionLight');
  }

  private templateActionByTitle(title: string): string {
    if (title === '空调自动制冷模式') {
      return this.templateAction('cooling');
    }
    if (title === '空调自动制热模式') {
      return this.templateAction('heating');
    }
    if (title === '离家关电器') {
      return this.templateAction('away');
    }
    if (title === '湿度过高自动除湿') {
      return this.templateAction('humidityDry');
    }
    return this.templateAction('motionLight');
  }

  private savedDetailTitle(): string {
    if (this.smartSavedDetailType === 'template') {
      return this.savedTemplateTitle;
    }
    return this.savedCustomTitle;
  }

  private savedDetailCondition(): string {
    if (this.smartSavedDetailType === 'template') {
      return this.templateCondition(this.savedTemplateId);
    }
    return this.savedCustomCondition;
  }

  private savedDetailAction(): string {
    if (this.smartSavedDetailType === 'template') {
      return this.templateAction(this.savedTemplateId);
    }
    return this.savedCustomAction;
  }

  private savedDetailEnabled(): boolean {
    if (this.smartSavedDetailType === 'template') {
      return this.savedTemplateEnabled;
    }
    return this.savedCustomEnabled;
  }

  private async runSavedRuleOnce(): Promise<void> {
    this.smartBusy = true;
    this.smartMessage = '';
    try {
      if (this.smartSavedDetailType === 'template') {
        await this.deviceManager.applySmartTemplate(this.savedTemplateId);
      } else {
        await this.deviceManager.applyCustomAutomation(this.savedCustomConditionId, this.savedCustomActionId);
      }
      this.smartMessage = '规则已运行一次。';
      this.smartSavedDetailType = '';
    } catch (error) {
      this.smartMessage = '运行失败，请确认网关在线后再试。';
    } finally {
      this.smartBusy = false;
    }
  }

  private conditionLabel(): string {
    if (this.customCondition === 'humidityHigh') {
      return '浴室湿度偏高';
    }
    if (this.customCondition === 'doorUnlocked') {
      return '入户门锁被解开';
    }
    return '房间有人且光线较暗';
  }

  private actionLabel(): string {
    if (this.customAction === 'dryMode') {
      return '空调切换除湿';
    }
    if (this.customAction === 'awayScene') {
      return '执行离家保护';
    }
    return '打开对应灯光';
  }
}
