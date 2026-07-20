import { common } from '@kit.AbilityKit';
import { hdsMaterial, HdsTabs } from '@kit.UIDesignKit';
import { immersiveCardEffect } from '../common/ImmersiveUi';
import { ControlCenterTab } from '../components/ControlCenterTab';
import { LockIcon } from '../components/LockIcon';
import { PairingPage } from '../components/PairingPage';
import { SettingsTab } from '../components/SettingsTab';
import { DeviceApplication } from '../model/DeviceApplication';
import { DeviceManager } from '../model/DeviceManager';
import {
  DeviceInfo,
  DeviceType,
  SceneDeviceAction,
  SceneExecutionDetail
} from '../model/DeviceModel';
import {
  SavedAutomationRule,
  SavedQuickScene,
  SavedSmartRules,
  SmartRuleStore
} from '../service/SmartRuleStore';
import { DeviceRegistry } from '../model/DeviceRegistry';
import { GenericDevice } from '../model/GenericDeviceModel';

class SceneOperationOption {
  value: string = '';
}

@Entry
@Component
struct Index {
  @Provide deviceManager: DeviceManager = DeviceApplication.getDeviceManager();
  @State currentTab: string = 'home';
  @State settingsDetailVisible: boolean = false;
  @State smartDetailTemplateId: string = '';
  @State smartSavedDetailId: string = '';
  @State showCustomComposer: boolean = false;
  @State customCondition: string = 'motionDark';
  @State customAction: string = 'livingLight';
  @State savedAutomationRules: SavedAutomationRule[] = [];
  @State ruleSelectionMode: boolean = false;
  @State selectedRuleIds: string[] = [];
  @State quickScenes: SavedQuickScene[] = [];
  @State activeQuickSceneId: string = 'home';
  @State sceneContextId: string = '';
  @State sceneEditorId: string = '';
  @State sceneEditorName: string = '';
  @State sceneEditorSearch: string = '';
  @State sceneEditorActions: SceneDeviceAction[] = [];
  @State smartBusy: boolean = false;
  @State smartMessage: string = '';
  private smartRuleStore: SmartRuleStore | null = null;
  private smartRulesChangedBeforeRestore: boolean = false;
  private suppressedRuleTap: string = '';
  private suppressedSceneTapId: string = '';

  aboutToAppear(): void {
    const context = getContext(this) as common.UIAbilityContext;
    this.quickScenes = this.defaultQuickScenes();
    this.deviceManager.initialize(context);
    this.restoreSmartRules(context);
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

  private async restoreSmartRules(context: common.UIAbilityContext): Promise<void> {
    if (this.smartRuleStore !== null) {
      return;
    }
    const store = new SmartRuleStore(context);
    this.smartRuleStore = store;
    try {
      const rules = await store.restore();
      if (!this.smartRulesChangedBeforeRestore) {
        this.applySavedSmartRules(rules);
      }
    } catch (error) {
      this.smartMessage = '智能规则读取失败，请重新保存。';
    }
  }

  private async persistSmartRules(): Promise<boolean> {
    this.smartRulesChangedBeforeRestore = true;
    if (this.smartRuleStore === null) {
      return false;
    }
    try {
      await this.smartRuleStore.save(this.currentSmartRules());
      return true;
    } catch (error) {
      return false;
    }
  }

  private currentSmartRules(): SavedSmartRules {
    const rules = new SavedSmartRules();
    rules.automations = this.copySavedAutomationRules(this.savedAutomationRules);
    rules.activeQuickSceneId = this.activeQuickSceneId;
    rules.quickScenes = this.quickScenes;
    return rules;
  }

  private applySavedSmartRules(rules: SavedSmartRules): void {
    this.savedAutomationRules = this.copySavedAutomationRules(rules.automations);
    this.activeQuickSceneId = rules.activeQuickSceneId;
    this.quickScenes = this.mergeQuickScenes(rules.quickScenes);
  }

  private copySavedAutomationRules(source: SavedAutomationRule[]): SavedAutomationRule[] {
    const result: SavedAutomationRule[] = [];
    for (let index = 0; index < source.length; index++) {
      const item = source[index];
      const rule = new SavedAutomationRule();
      rule.id = item.id;
      rule.kind = item.kind;
      rule.title = item.title;
      rule.templateId = item.templateId;
      rule.conditionId = item.conditionId;
      rule.actionId = item.actionId;
      rule.condition = item.condition;
      rule.action = item.action;
      rule.enabled = item.enabled;
      result.push(rule);
    }
    return result;
  }

  build() {
    Column() {
      if (this.deviceManager.pairingRequired) {
        PairingPage({
          onPairingSucceeded: () => {
            this.currentTab = 'home';
          }
        })
      } else {
        HdsTabs() {
          TabContent() {
            ControlCenterTab()
          }
          .tabBar(this.TabButton('home', $r('app.media.nav_home'), '家'))

          TabContent() {
            this.SmartTab()
          }
          .tabBar(this.TabButton('smart', $r('app.media.nav_smart'), '智能'))

          TabContent() {
            SettingsTab({
              onDetailVisibilityChanged: (visible: boolean) => {
                this.settingsDetailVisible = visible;
              }
            })
          }
          .tabBar(this.TabButton('settings', $r('app.media.nav_settings'), '设置'))
        }
        .width('100%')
        .height('100%')
        .barPosition(BarPosition.End)
        .scrollable(false)
        .barOverlap(true)
        .barHeight(this.shouldShowBottomNavigation() ? 64 : 0)
        .barFloatingStyle({
          barSideMargin: 18,
          barBottomMargin: this.shouldShowBottomNavigation() ? 16 : 0,
          adaptToHandedness: true,
          lightColor: '#C9EAFF',
          barOpacity: this.shouldShowBottomNavigation() ? 1 : 0,
          systemMaterialEffect: {
            materialType: hdsMaterial.MaterialType.ADAPTIVE,
            materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
          }
        })
        .onChange((index: number) => {
          this.currentTab = this.tabKey(index);
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#DCEAF2')
  }

  @Builder
  TabButton(tab: string, icon: Resource, label: string) {
    Stack({ alignContent: Alignment.Center }) {
      Column() {
        Stack({ alignContent: Alignment.Center }) {
          Image(icon)
            .width(22)
            .height(22)
            .objectFit(ImageFit.Contain)
            .fillColor(tab === this.currentTab ? '#1769C2' : '#6F8094')
        }
        .width(26)
        .height(26)
        Text(label)
          .fontSize(12)
          .lineHeight(16)
          .fontWeight(tab === this.currentTab ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(tab === this.currentTab ? '#1769C2' : '#6F8094')
          .textAlign(TextAlign.Center)
          .width('100%')
      }
      .width(88)
      .height(48)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(tab === this.currentTab ? '#1A1769C2' : Color.Transparent)
      .borderRadius(24)
    }
    .width('100%')
    .height(60)
  }

  private tabKey(index: number): string {
    if (index === 1) {
      return 'smart';
    }
    if (index === 2) {
      return 'settings';
    }
    return 'home';
  }

  private shouldShowBottomNavigation(): boolean {
    if (this.currentTab === 'smart') {
      return !this.isSmartSecondaryPage();
    }
    if (this.currentTab === 'settings') {
      return !this.settingsDetailVisible;
    }
    return true;
  }

  private isSmartSecondaryPage(): boolean {
    return this.sceneEditorId.length > 0 ||
      this.smartSavedDetailId.length > 0 ||
      this.smartDetailTemplateId.length > 0;
  }

  @Builder
  SmartTab() {
    if (this.sceneEditorId.length > 0) {
      this.SceneEditorPage()
    } else if (this.smartSavedDetailId.length > 0) {
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
      .padding({ left: 18, right: 18, top: 42, bottom: 112 })
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
        if (this.ruleSelectionMode) {
          Button('删除')
            .id('smart-rule-delete-selected')
            .height(34)
            .fontSize(13)
            .fontColor(Color.White)
            .backgroundColor('#D64545')
            .borderRadius(12)
            .enabled(this.selectedRuleIds.length > 0)
            .onClick(() => {
              this.deleteSelectedRules();
            })
          Button('取消')
            .id('smart-rule-cancel-selection')
            .height(34)
            .fontSize(13)
            .fontColor('#D64545')
            .backgroundColor(Color.Transparent)
            .borderRadius(12)
            .margin({ left: 8 })
            .onClick(() => {
              this.exitRuleSelection();
            })
        } else {
          Text(this.runningRuleCountText())
            .fontSize(12)
            .fontColor('#748294')
        }
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
        ForEach(this.savedAutomationRules, (rule: SavedAutomationRule) => {
          this.SavedAutomationRuleRow(rule)
        }, (rule: SavedAutomationRule) => rule.id)
      }
    }
    .width('100%')
    .padding(18)
    .backgroundColor(Color.White)
    .borderRadius(24)
    .visualEffect(immersiveCardEffect())
    .margin({ bottom: 14 })
  }

  @Builder
  SavedAutomationRuleRow(rule: SavedAutomationRule) {
    Row() {
      this.RuleStatusOrSelection(rule.id, rule.enabled)
      Column() {
        Text(rule.title)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor('#14263A')
        Text('当 ' + this.savedRuleCondition(rule))
          .fontSize(12)
          .fontColor('#748294')
          .margin({ top: 5 })
        Text('执行 ' + this.savedRuleAction(rule))
          .fontSize(12)
          .fontColor('#748294')
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 12 })
      if (!this.ruleSelectionMode) {
        Toggle({ type: ToggleType.Switch, isOn: rule.enabled })
          .id('smart-rule-toggle-' + rule.id)
          .selectedColor('#1769C2')
          .onChange((value: boolean) => {
            this.setSavedRuleEnabled(rule.id, value);
            this.persistSmartRules();
          })
      }
    }
    .id('smart-rule-' + rule.id)
    .width('100%')
    .padding({ top: 12, bottom: 12 })
    .onClick(() => {
      if (this.consumeSuppressedRuleTap(rule.id)) {
        return;
      }
      if (this.ruleSelectionMode) {
        this.toggleRuleSelection(rule.id);
      } else {
        this.smartSavedDetailId = rule.id;
      }
    })
    .gesture(
      LongPressGesture({ repeat: false, duration: 500 })
        .onAction(() => {
          this.openRuleSelection(rule.id);
        })
    )
  }

  @Builder
  RuleStatusOrSelection(ruleType: string, enabled: boolean) {
    if (this.ruleSelectionMode) {
      Text(this.isRuleSelected(ruleType) ? '✓' : '')
        .id('smart-rule-select-' + ruleType)
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1769C2')
        .textAlign(TextAlign.Center)
        .width(24)
        .height(24)
        .border({ width: 1, color: this.isRuleSelected(ruleType) ? '#1769C2' : '#AEB9C6' })
        .borderRadius(12)
        .backgroundColor(Color.White)
    } else {
      Column() {
        Text(enabled ? '启用' : '暂停')
          .fontSize(12)
          .fontColor(enabled ? '#0F8F66' : '#748294')
      }
      .width(46)
      .height(46)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(enabled ? '#EAF8F1' : '#F2F5F9')
      .borderRadius(17)
    }
  }

  @Builder
  QuickScenePanel() {
    Column() {
      Row() {
        Text('常用场景')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#14263A')
          .layoutWeight(1)
        Text('+')
          .id('quick-scene-add')
          .fontSize(28)
          .fontColor('#1769C2')
          .width(34)
          .height(34)
          .textAlign(TextAlign.Center)
          .backgroundColor('#EAF4FF')
          .borderRadius(12)
          .onClick(() => {
            this.startNewQuickScene();
          })
      }
      .width('100%')
      .margin({ bottom: 12 })

      if (this.sceneContextId.length > 0) {
        this.SceneContextMenu()
      }
      Row() {
        this.SceneShortcut(this.quickSceneForId('home'))
        this.SceneShortcut(this.quickSceneForId('away'))
      }
      .width('100%')
      ForEach(this.customQuickScenes(), (scene: SavedQuickScene) => {
        this.CustomSceneRow(scene)
      }, (scene: SavedQuickScene) => scene.id)
    }
    .width('100%')
    .padding(18)
    .backgroundColor(Color.White)
    .borderRadius(24)
    .visualEffect(immersiveCardEffect())
    .margin({ bottom: 14 })
  }

  @Builder
  SceneShortcut(scene: SavedQuickScene) {
    Column() {
      Text(scene.name)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.isActiveQuickScene(scene) ? '#1769C2' : '#14263A')
      Text(this.quickSceneSubtitle(scene))
        .fontSize(12)
        .fontColor('#748294')
        .margin({ top: 6 })
    }
    .id('quick-scene-' + scene.id)
    .layoutWeight(1)
    .height(86)
    .padding(14)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(this.isActiveQuickScene(scene) ? '#EAF4FF' : '#F7FBFF')
    .borderRadius(20)
    .visualEffect(immersiveCardEffect())
    .clickEffect({ level: ClickEffectLevel.MIDDLE, scale: 0.98 })
    .margin({ right: scene.id === 'home' ? 10 : 0 })
    .onClick(() => {
      if (this.consumeSuppressedSceneTap(scene.id)) {
        return;
      }
      this.runQuickScene(scene);
    })
    .gesture(
      LongPressGesture({ repeat: false, duration: 500 })
        .onAction(() => {
          this.openSceneContext(scene.id);
        })
    )
  }

  @Builder
  CustomSceneRow(scene: SavedQuickScene) {
    Row() {
      Column() {
        Text(scene.name)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor('#14263A')
        Text(this.quickSceneSubtitle(scene))
          .fontSize(12)
          .fontColor('#748294')
          .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text('运行')
        .fontSize(13)
        .fontColor('#1769C2')
        .padding({ left: 12, right: 12, top: 7, bottom: 7 })
        .backgroundColor('#EAF4FF')
        .borderRadius(12)
    }
    .id('quick-scene-' + scene.id)
    .width('100%')
    .padding(14)
    .backgroundColor('#F7FBFF')
    .borderRadius(18)
    .visualEffect(immersiveCardEffect())
    .clickEffect({ level: ClickEffectLevel.MIDDLE, scale: 0.98 })
    .margin({ top: 10 })
    .onClick(() => {
      if (this.consumeSuppressedSceneTap(scene.id)) {
        return;
      }
      this.runQuickScene(scene);
    })
    .gesture(
      LongPressGesture({ repeat: false, duration: 500 })
        .onAction(() => {
          this.openSceneContext(scene.id);
        })
    )
  }

  @Builder
  SceneContextMenu() {
    Row() {
      Text('已选择「' + this.quickSceneForId(this.sceneContextId).name + '」')
        .fontSize(13)
        .fontColor('#14263A')
        .layoutWeight(1)
      Button('编辑')
        .id('quick-scene-context-edit')
        .height(34)
        .fontSize(13)
        .fontColor(Color.White)
        .backgroundColor('#1769C2')
          .borderRadius(12)
          .onClick(() => {
          this.startQuickSceneEditor(this.quickSceneForId(this.sceneContextId));
        })
      if (!this.quickSceneForId(this.sceneContextId).builtIn) {
        Button('删除')
          .id('quick-scene-context-delete')
          .height(34)
          .fontSize(13)
          .fontColor('#D64545')
          .backgroundColor(Color.Transparent)
          .borderRadius(12)
          .margin({ left: 6 })
          .onClick(() => {
            this.deleteQuickScene(this.sceneContextId);
          })
      }
      Button('取消')
        .id('quick-scene-context-cancel')
        .height(34)
        .fontSize(13)
        .fontColor('#748294')
        .backgroundColor(Color.Transparent)
        .borderRadius(12)
        .margin({ left: 6 })
        .onClick(() => {
          this.sceneContextId = '';
        })
    }
    .width('100%')
    .padding(12)
    .backgroundColor('#F7FBFF')
    .borderRadius(16)
    .margin({ bottom: 10 })
  }

  @Builder
  SceneEditorPage() {
    Scroll() {
      Column() {
        Row() {
          Text('‹')
            .id('quick-scene-editor-back')
            .fontSize(38)
            .fontColor('#14263A')
            .width(46)
            .height(46)
            .onClick(() => {
              this.sceneEditorId = '';
            })
          Text(this.sceneEditorId === 'new' ? '新建常用场景' : '编辑常用场景')
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor('#14263A')
            .layoutWeight(1)
        }
        .width('100%')
        .margin({ bottom: 18 })

        Text('场景名称')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor('#14263A')
          .width('100%')
        TextInput({ text: this.sceneEditorName, placeholder: '例如：睡前模式' })
          .id('quick-scene-editor-name')
          .width('100%')
          .height(46)
          .backgroundColor(Color.White)
          .borderRadius(14)
          .margin({ top: 8, bottom: 16 })
          .onChange((value: string) => {
            this.sceneEditorName = value;
          })

        Text('查找房间或设备')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor('#14263A')
          .width('100%')
        TextInput({ text: this.sceneEditorSearch, placeholder: '例如：主卧、空调' })
          .id('quick-scene-editor-search')
          .width('100%')
          .height(42)
          .backgroundColor(Color.White)
          .borderRadius(14)
          .margin({ top: 8, bottom: 12 })
          .onChange((value: string) => {
            this.sceneEditorSearch = value;
          })

        Text('为每台可控制设备选择操作；默认均为“维持”。')
          .fontSize(12)
          .fontColor('#748294')
          .width('100%')
          .margin({ bottom: 10 })

        if (this.sceneEditorRoomIds().length === 0) {
          Text('暂未同步到可编辑的设备，请先连接网关并同步设备。')
            .fontSize(13)
            .fontColor('#748294')
            .width('100%')
            .padding(18)
            .backgroundColor(Color.White)
            .borderRadius(18)
        } else {
          ForEach(this.sceneEditorRoomIds(), (roomId: string) => {
            this.SceneRoomEditorGroup(roomId)
          }, (roomId: string) => roomId)
        }

        if (this.sceneEditorId === 'home' || this.sceneEditorId === 'away') {
          Button('恢复默认场景')
            .id('quick-scene-editor-reset')
            .width('100%')
            .height(46)
            .fontColor('#1769C2')
            .backgroundColor(Color.Transparent)
            .borderRadius(16)
            .margin({ top: 14 })
            .onClick(() => {
              this.restoreDefaultQuickScene();
            })
        }

        Button(this.smartBusy ? '保存中' : '保存场景')
          .id('quick-scene-editor-save')
          .width('100%')
          .height(50)
          .fontColor(Color.White)
          .backgroundColor('#1769C2')
          .borderRadius(18)
          .enabled(!this.smartBusy)
          .margin({ top: 14, bottom: 18 })
          .onClick(() => {
            this.saveQuickScene();
          })
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 34, bottom: 28 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#DCEAF2')
    .scrollBar(BarState.Off)
  }

  @Builder
  SceneRoomEditorGroup(roomId: string) {
    Column() {
      Text(DeviceRegistry.getRoomLabel(roomId))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor('#14263A')
        .width('100%')
        .margin({ bottom: 8 })
      ForEach(this.sceneEditorDevices(roomId), (device: DeviceInfo) => {
        this.SceneDeviceOperationRow(device)
      }, (device: DeviceInfo) => device.id)
    }
    .width('100%')
    .padding(14)
    .backgroundColor(Color.White)
    .borderRadius(20)
    .margin({ bottom: 12 })
  }

  @Builder
  SceneDeviceOperationRow(device: DeviceInfo) {
    Row() {
      Column() {
        Text(device.name)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor('#14263A')
        Text(this.sceneDeviceKindLabel(device))
          .fontSize(12)
          .fontColor('#748294')
          .margin({ top: 3 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Row() {
        Text(this.sceneOperationLabel(device, this.currentSceneOperation(device)))
          .id('quick-scene-operation-value-' + device.id)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor('#1769C2')
          .width(64)
          .textAlign(TextAlign.Center)
        Select(this.sceneOperationOptions(device))
          .id('quick-scene-operation-' + device.id)
          .selected(this.sceneOperationIndex(device))
          .font({ size: 13, weight: FontWeight.Medium })
          .fontColor('#1769C2')
          .width(42)
          .backgroundColor(Color.Transparent)
          .onSelect((index: number) => {
            this.setSceneDeviceOperation(
              device.id,
              this.availableSceneOperations(device)[index]
            );
          })
      }
      .height(42)
      .backgroundColor('#EAF4FF')
      .borderRadius(12)
    }
    .width('100%')
    .padding({ top: 10, bottom: 10 })
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
    .visualEffect(immersiveCardEffect())
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
        this.TemplateFlowIcon(this.templateIcon(templateId), 26)
        Text('→')
          .fontSize(18)
          .fontColor('#AEB9C6')
          .margin({ left: 18, right: 18 })
        this.TemplateFlowIcon(this.templateResultIcon(templateId), 26)
      }
      .margin({ top: 24 })
      .width('100%')
    }
    .width('100%')
    .padding(18)
    .backgroundColor('#F7FBFF')
    .borderRadius(22)
    .visualEffect(immersiveCardEffect())
    .clickEffect({ level: ClickEffectLevel.MIDDLE, scale: 0.985 })
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
        this.TemplateFlowIcon(this.templateIcon(templateId), 22)
        Text('→')
          .fontSize(15)
          .fontColor('#AEB9C6')
          .margin({ left: 10, right: 10 })
        this.TemplateFlowIcon(this.templateResultIcon(templateId), 22)
      }
      .margin({ top: 24 })
    }
    .layoutWeight(1)
    .height(150)
    .padding(14)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor('#F7FBFF')
    .borderRadius(20)
    .visualEffect(immersiveCardEffect())
    .clickEffect({ level: ClickEffectLevel.MIDDLE, scale: 0.98 })
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
    .visualEffect(immersiveCardEffect())
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
      .visualEffect(immersiveCardEffect())
      .clickEffect({ level: ClickEffectLevel.MIDDLE, scale: 0.97 })
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
      .visualEffect(immersiveCardEffect())
      .clickEffect({ level: ClickEffectLevel.MIDDLE, scale: 0.97 })
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
    .padding({ left: 24, right: 24, top: 42, bottom: 28 })
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
            this.smartSavedDetailId = '';
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
            this.setSavedRuleEnabled(this.smartSavedDetailId, value);
            this.persistSmartRules();
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
        .id('smart-rule-run-once')
        .width('100%')
        .height(50)
        .fontColor(Color.White)
        .backgroundColor('#1769C2')
        .borderRadius(18)
        .enabled(!this.smartBusy)
        .margin({ bottom: 10 })
        .onClick(() => {
          this.runSavedRuleOnce();
        })
      Button('删除规则')
        .id('smart-rule-delete')
        .width('100%')
        .height(50)
        .fontColor(Color.White)
        .backgroundColor('#D64545')
        .borderRadius(18)
        .onClick(() => {
          this.deleteSavedRule(this.smartSavedDetailId);
        })
    }
    .width('100%')
    .height('100%')
    .padding({ left: 24, right: 24, top: 42, bottom: 28 })
    .backgroundColor('#DCEAF2')
  }

  @Builder
  DetailBlock(title: string, icon: string, body: string) {
    Row() {
      Stack({ alignContent: Alignment.Center }) {
        if (icon === 'lock-open') {
          LockIcon({ locked: false, iconSize: 28 })
        } else if (icon === 'lock-closed') {
          LockIcon({ locked: true, iconSize: 28 })
        } else {
          Text(icon)
            .fontSize(22)
            .fontColor('#1769C2')
            .width(54)
            .height(54)
            .lineHeight(54)
            .textAlign(TextAlign.Center)
        }
      }
      .width(54)
      .height(54)
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
    .visualEffect(immersiveCardEffect())
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
    .visualEffect(immersiveCardEffect())
  }

  @Builder
  TemplateFlowIcon(icon: string, size: number) {
    if (icon === 'lock-open') {
      LockIcon({ locked: false, iconSize: size })
        .id('smart-template-lock-open')
    } else if (icon === 'lock-closed') {
      LockIcon({ locked: true, iconSize: size })
        .id('smart-template-lock-closed')
    } else {
      Text(icon)
        .fontSize(size)
        .fontColor('#1769C2')
        .width(size + 12)
        .height(size + 12)
        .lineHeight(size + 12)
        .textAlign(TextAlign.Center)
    }
  }

  private enterRuleSelection(ruleId: string): void {
    this.ruleSelectionMode = true;
    this.selectedRuleIds = [ruleId];
  }

  private openRuleSelection(ruleId: string): void {
    this.suppressedRuleTap = ruleId;
    this.enterRuleSelection(ruleId);
    setTimeout(() => {
      if (this.suppressedRuleTap === ruleId) {
        this.suppressedRuleTap = '';
      }
    }, 300);
  }

  private consumeSuppressedRuleTap(ruleId: string): boolean {
    if (this.suppressedRuleTap !== ruleId) {
      return false;
    }
    this.suppressedRuleTap = '';
    return true;
  }

  private exitRuleSelection(): void {
    this.ruleSelectionMode = false;
    this.selectedRuleIds = [];
  }

  private isRuleSelected(ruleId: string): boolean {
    return this.selectedRuleIds.indexOf(ruleId) >= 0;
  }

  private toggleRuleSelection(ruleId: string): void {
    if (!this.ruleSelectionMode) {
      return;
    }
    if (this.isRuleSelected(ruleId)) {
      this.selectedRuleIds = this.selectedRuleIds.filter(
        (value: string) => value !== ruleId
      );
    } else {
      this.selectedRuleIds = [...this.selectedRuleIds, ruleId];
    }
  }

  private removeSavedRule(ruleId: string): void {
    this.savedAutomationRules = this.savedAutomationRules.filter(
      (rule: SavedAutomationRule) => rule.id !== ruleId
    );
  }

  private async deleteSavedRule(ruleId: string): Promise<void> {
    this.removeSavedRule(ruleId);
    this.smartSavedDetailId = '';
    this.exitRuleSelection();
    this.smartMessage = await this.persistSmartRules() ?
      '规则已删除。' : '规则已删除，但本地保存失败。';
  }

  private async deleteSelectedRules(): Promise<void> {
    if (this.selectedRuleIds.length === 0) {
      return;
    }
    const deletedCount = this.selectedRuleIds.length;
    const selected = this.selectedRuleIds;
    this.savedAutomationRules = this.savedAutomationRules.filter(
      (rule: SavedAutomationRule) => selected.indexOf(rule.id) < 0
    );
    this.exitRuleSelection();
    this.smartMessage = await this.persistSmartRules() ?
      '已删除 ' + deletedCount.toString() + ' 条规则。' :
      '已删除规则，但本地保存失败。';
  }

  private defaultQuickScenes(): SavedQuickScene[] {
    return [this.defaultQuickScene('home'), this.defaultQuickScene('away')];
  }

  private defaultQuickScene(id: string): SavedQuickScene {
    const scene = new SavedQuickScene();
    scene.id = id;
    scene.builtIn = id === 'home' || id === 'away';
    scene.customized = false;
    if (id === 'home') {
      scene.name = '回家';
      scene.actions = [
        this.sceneAction('light-living-01', 'on'),
        this.sceneAction('light-living-02', 'on'),
        this.sceneAction('ac-living-01', 'on'),
        this.sceneAction('door-entry-01', 'off')
      ];
      return scene;
    }
    if (id === 'away') {
      scene.name = '离家';
      for (let index = 0; index < this.deviceManager.devices.length; index++) {
        const device = this.deviceManager.devices[index];
        if (device.type !== DeviceType.ENVIRONMENT) {
          scene.actions.push(this.sceneAction(device.id, 'off'));
        }
      }
      return scene;
    }
    scene.name = '未命名场景';
    return scene;
  }

  private sceneAction(deviceId: string, operation: string): SceneDeviceAction {
    const action = new SceneDeviceAction();
    action.deviceId = deviceId;
    action.operation = operation;
    return action;
  }

  private copyQuickScene(source: SavedQuickScene): SavedQuickScene {
    const scene = new SavedQuickScene();
    scene.id = source.id;
    scene.name = source.name;
    scene.builtIn = source.builtIn;
    scene.customized = source.customized;
    for (let index = 0; index < source.actions.length; index++) {
      scene.actions.push(this.sceneAction(
        source.actions[index].deviceId,
        source.actions[index].operation
      ));
    }
    return scene;
  }

  private mergeQuickScenes(storedScenes: SavedQuickScene[]): SavedQuickScene[] {
    const merged = this.defaultQuickScenes();
    for (let index = 0; index < storedScenes.length; index++) {
      const stored = storedScenes[index];
      if (stored.id === 'home' || stored.id === 'away') {
        for (let defaultIndex = 0; defaultIndex < merged.length; defaultIndex++) {
          if (merged[defaultIndex].id === stored.id) {
            const scene = this.copyQuickScene(stored);
            scene.builtIn = true;
            merged[defaultIndex] = scene;
            break;
          }
        }
      } else if (!stored.builtIn) {
        merged.push(this.copyQuickScene(stored));
      }
    }
    return merged;
  }

  private quickSceneForId(id: string): SavedQuickScene {
    for (let index = 0; index < this.quickScenes.length; index++) {
      if (this.quickScenes[index].id === id) {
        return this.quickScenes[index];
      }
    }
    return this.defaultQuickScene(id);
  }

  private customQuickScenes(): SavedQuickScene[] {
    const result: SavedQuickScene[] = [];
    for (let index = 0; index < this.quickScenes.length; index++) {
      if (!this.quickScenes[index].builtIn) {
        result.push(this.quickScenes[index]);
      }
    }
    return result;
  }

  private quickSceneSubtitle(scene: SavedQuickScene): string {
    if (!scene.customized && scene.id === 'home') {
      return '开启客厅灯光和空调，并锁门';
    }
    if (!scene.customized && scene.id === 'away') {
      return '关闭灯光、电器和窗帘，并锁门';
    }
    let activeCount = 0;
    for (let index = 0; index < scene.actions.length; index++) {
      if (scene.actions[index].operation !== 'keep') {
        activeCount++;
      }
    }
    return activeCount.toString() + ' 台设备将执行操作';
  }

  private openSceneContext(sceneId: string): void {
    this.suppressedSceneTapId = sceneId;
    this.sceneContextId = sceneId;
    setTimeout(() => {
      if (this.suppressedSceneTapId === sceneId) {
        this.suppressedSceneTapId = '';
      }
    }, 300);
  }

  private consumeSuppressedSceneTap(sceneId: string): boolean {
    if (this.suppressedSceneTapId !== sceneId) {
      return false;
    }
    this.suppressedSceneTapId = '';
    return true;
  }

  private isActiveQuickScene(scene: SavedQuickScene): boolean {
    return (scene.id === 'home' || scene.id === 'away') && scene.id === this.activeQuickSceneId;
  }

  private async runQuickScene(scene: SavedQuickScene): Promise<void> {
    if (this.smartBusy) {
      return;
    }
    this.smartBusy = true;
    this.smartMessage = '';
    try {
      if (!scene.customized && scene.id === 'home') {
        await this.deviceManager.executeHomeScene();
      } else if (!scene.customized && scene.id === 'away') {
        await this.deviceManager.executeAwayScene();
      } else {
        await this.deviceManager.executeConfiguredScene(scene.actions);
      }
      if (scene.id === 'home' || scene.id === 'away') {
        this.activeQuickSceneId = scene.id;
        const persisted = await this.persistSmartRules();
        this.smartMessage = persisted ?
          '已下发「' + scene.name + '」场景。' :
          '已下发「' + scene.name + '」场景，但状态未能保存。';
      } else {
        this.smartMessage = '已下发「' + scene.name + '」场景。';
      }
    } catch (error) {
      this.smartMessage = '场景执行失败，请确认网关在线后再试。';
    } finally {
      this.smartBusy = false;
    }
  }

  private startNewQuickScene(): void {
    if (this.quickScenes.length >= 8) {
      this.smartMessage = '常用场景数量已达到上限，请先删除一个自定义场景。';
      return;
    }
    this.sceneContextId = '';
    this.sceneEditorId = 'new';
    this.sceneEditorName = '';
    this.sceneEditorSearch = '';
    this.sceneEditorActions = this.editorActionsFor(new SavedQuickScene());
  }

  private startQuickSceneEditor(scene: SavedQuickScene): void {
    this.sceneContextId = '';
    this.sceneEditorId = scene.id;
    this.sceneEditorName = scene.name;
    this.sceneEditorSearch = '';
    const editableScene = !scene.customized && scene.id === 'away' ?
      this.defaultQuickScene(scene.id) : scene;
    this.sceneEditorActions = this.editorActionsFor(editableScene);
  }

  private editorActionsFor(scene: SavedQuickScene): SceneDeviceAction[] {
    const result: SceneDeviceAction[] = [];
    for (let index = 0; index < this.deviceManager.devices.length; index++) {
      const device = this.deviceManager.devices[index];
      if (device.type === DeviceType.ENVIRONMENT) {
        continue;
      }
      let operation = 'keep';
      for (let actionIndex = 0; actionIndex < scene.actions.length; actionIndex++) {
        if (scene.actions[actionIndex].deviceId === device.id) {
          operation = scene.actions[actionIndex].operation;
          break;
        }
      }
      result.push(this.sceneAction(device.id, operation));
    }
    return result;
  }

  private sceneEditorRoomIds(): string[] {
    const result: string[] = [];
    const roomIds = this.deviceManager.getRoomIds();
    for (let index = 0; index < roomIds.length; index++) {
      if (this.sceneEditorDevices(roomIds[index]).length > 0) {
        result.push(roomIds[index]);
      }
    }
    return result;
  }

  private sceneEditorDevices(roomId: string): DeviceInfo[] {
    const query = this.sceneEditorSearch.trim().toLowerCase();
    const roomMatches = DeviceRegistry.getRoomLabel(roomId).toLowerCase().indexOf(query) >= 0;
    const devices = this.deviceManager.getDevicesByRoom(roomId);
    const result: DeviceInfo[] = [];
    for (let index = 0; index < devices.length; index++) {
      const device = devices[index];
      if (device.type === DeviceType.ENVIRONMENT) {
        continue;
      }
      if (
        query.length === 0 ||
        roomMatches ||
        device.name.toLowerCase().indexOf(query) >= 0
      ) {
        result.push(device);
      }
    }
    return result;
  }

  private availableSceneOperations(device: DeviceInfo): string[] {
    if (device.type === DeviceType.ENVIRONMENT) {
      return ['keep'];
    }
    if (device.type === DeviceType.DOOR_LOCK) {
      return ['keep', 'off'];
    }
    return ['keep', 'on', 'off'];
  }

  private sceneOperationOptions(device: DeviceInfo): SceneOperationOption[] {
    const options: SceneOperationOption[] = [];
    const operations = this.availableSceneOperations(device);
    for (let index = 0; index < operations.length; index++) {
      const option = new SceneOperationOption();
      option.value = this.sceneOperationLabel(device, operations[index]);
      options.push(option);
    }
    return options;
  }

  private sceneOperationLabel(device: DeviceInfo, operation: string): string {
    if (operation === 'keep') {
      return '维持';
    }
    if (device.type === DeviceType.DOOR_LOCK) {
      return operation === 'on' ? '解锁' : '上锁';
    }
    return operation === 'on' ? '开启' : '关闭';
  }

  private currentSceneOperation(device: DeviceInfo): string {
    for (let index = 0; index < this.sceneEditorActions.length; index++) {
      if (this.sceneEditorActions[index].deviceId === device.id) {
        return this.sceneEditorActions[index].operation;
      }
    }
    return 'keep';
  }

  private sceneOperationIndex(device: DeviceInfo): number {
    const operation = this.currentSceneOperation(device);
    const operations = this.availableSceneOperations(device);
    const found = operations.indexOf(operation);
    return found >= 0 ? found : 0;
  }

  private setSceneDeviceOperation(deviceId: string, operation: string): void {
    const updated: SceneDeviceAction[] = [];
    let found = false;
    for (let index = 0; index < this.sceneEditorActions.length; index++) {
      const action = this.sceneEditorActions[index];
      if (action.deviceId === deviceId) {
        updated.push(this.sceneAction(deviceId, operation));
        found = true;
      } else {
        updated.push(this.sceneAction(action.deviceId, action.operation));
      }
    }
    if (!found) {
      updated.push(this.sceneAction(deviceId, operation));
    }
    this.sceneEditorActions = updated;
  }

  private sceneDeviceKindLabel(device: DeviceInfo): string {
    if (device.type === DeviceType.LIGHT) {
      return '灯光';
    }
    if (device.type === DeviceType.AIR_CONDITIONER) {
      return '空调';
    }
    if (device.type === DeviceType.DOOR_LOCK) {
      return '门锁';
    }
    return (device as GenericDevice).category.title;
  }

  private async saveQuickScene(): Promise<void> {
    const name = this.sceneEditorName.trim();
    if (name.length === 0) {
      this.smartMessage = '请先填写场景名称。';
      return;
    }
    this.smartBusy = true;
    const scene = new SavedQuickScene();
    scene.id = this.sceneEditorId === 'new' ?
      'custom-' + Date.now().toString() : this.sceneEditorId;
    scene.name = name;
    const previous = this.quickSceneForId(this.sceneEditorId);
    scene.builtIn = previous.builtIn;
    scene.customized = true;
    const configuredActions = new SavedQuickScene();
    configuredActions.actions = this.sceneEditorActions;
    scene.actions = this.editorActionsFor(configuredActions);
    const scenes: SavedQuickScene[] = [];
    let replaced = false;
    for (let index = 0; index < this.quickScenes.length; index++) {
      if (this.quickScenes[index].id === scene.id) {
        scenes.push(scene);
        replaced = true;
      } else {
        scenes.push(this.copyQuickScene(this.quickScenes[index]));
      }
    }
    if (!replaced) {
      scenes.push(scene);
    }
    this.quickScenes = scenes;
    const persisted = await this.persistSmartRules();
    this.sceneEditorId = '';
    this.smartMessage = persisted ? '场景已保存。' : '场景已更新，但本地保存失败。';
    this.smartBusy = false;
  }

  private async restoreDefaultQuickScene(): Promise<void> {
    const scene = this.defaultQuickScene(this.sceneEditorId);
    const scenes: SavedQuickScene[] = [];
    for (let index = 0; index < this.quickScenes.length; index++) {
      scenes.push(this.quickScenes[index].id === scene.id ? scene :
        this.copyQuickScene(this.quickScenes[index]));
    }
    this.quickScenes = scenes;
    const persisted = await this.persistSmartRules();
    this.sceneEditorId = '';
    this.smartMessage = persisted ? '已恢复默认场景。' : '已恢复默认场景，但本地保存失败。';
  }

  private async deleteQuickScene(id: string): Promise<void> {
    const scene = this.quickSceneForId(id);
    if (scene.builtIn) {
      return;
    }
    this.quickScenes = this.quickScenes.filter((item: SavedQuickScene) => item.id !== id);
    this.sceneContextId = '';
    this.smartMessage = await this.persistSmartRules() ?
      '常用场景已删除。' : '常用场景已删除，但本地保存失败。';
  }

  private async createTemplate(templateId: string): Promise<void> {
    if (templateId.length === 0) {
      return;
    }
    this.smartBusy = true;
    this.smartMessage = '';
    try {
      await this.deviceManager.applySmartTemplate(templateId);
      const rule = new SavedAutomationRule();
      rule.id = this.newSavedAutomationId('template');
      rule.kind = 'template';
      rule.title = this.templateTitle(templateId);
      rule.templateId = templateId;
      rule.enabled = true;
      this.savedAutomationRules = [...this.savedAutomationRules, rule];
      this.smartDetailTemplateId = '';
      this.smartMessage = await this.persistSmartRules() ?
        '已保存到我的智能，并已下发到网关执行。' :
        '已下发到网关执行，但本地保存失败。';
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
      const rule = new SavedAutomationRule();
      rule.id = this.newSavedAutomationId('custom');
      rule.kind = 'custom';
      rule.title = this.conditionLabel() + '自动化';
      rule.conditionId = this.customCondition;
      rule.actionId = this.customAction;
      rule.condition = this.conditionLabel();
      rule.action = this.actionLabel();
      rule.enabled = true;
      this.savedAutomationRules = [...this.savedAutomationRules, rule];
      this.showCustomComposer = false;
      this.smartMessage = await this.persistSmartRules() ?
        '自动化已创建，并已下发相关网关控制。' :
        '自动化已下发到网关，但本地保存失败。';
    } catch (error) {
      this.smartMessage = '创建失败，请确认网关在线后再试。';
    } finally {
      this.smartBusy = false;
    }
  }

  private newSavedAutomationId(kind: string): string {
    return kind + '-' + Date.now().toString() + '-' + this.savedAutomationRules.length.toString();
  }

  private hasSavedSmartRules(): boolean {
    return this.savedAutomationRules.length > 0;
  }

  private smartSubtitle(): string {
    if (this.hasSavedSmartRules()) {
      return '规则可以单独开关，也可以点进去运行一次';
    }
    return '从推荐方案保存，或自己组合条件和动作';
  }

  private runningRuleCountText(): string {
    let count = 0;
    for (let index = 0; index < this.savedAutomationRules.length; index++) {
      if (this.savedAutomationRules[index].enabled) {
        count++;
      }
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
    if (templateId === 'away') {
      return 'lock-open';
    }
    if (templateId === 'home') {
      return '⌂';
    }
    if (templateId === 'cooling' || templateId === 'heating' || templateId === 'humidityDry') {
      return '≈';
    }
    return '○';
  }

  private templateResultIcon(templateId: string): string {
    if (templateId === 'away') {
      return 'lock-closed';
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

  private savedRuleForId(ruleId: string): SavedAutomationRule {
    for (let index = 0; index < this.savedAutomationRules.length; index++) {
      if (this.savedAutomationRules[index].id === ruleId) {
        return this.savedAutomationRules[index];
      }
    }
    return new SavedAutomationRule();
  }

  private savedRuleCondition(rule: SavedAutomationRule): string {
    if (rule.kind === 'template') {
      return this.templateCondition(rule.templateId);
    }
    return rule.condition;
  }

  private savedRuleAction(rule: SavedAutomationRule): string {
    if (rule.kind === 'template') {
      return this.templateAction(rule.templateId);
    }
    return rule.action;
  }

  private savedDetailTitle(): string {
    return this.savedRuleForId(this.smartSavedDetailId).title;
  }

  private savedDetailCondition(): string {
    return this.savedRuleCondition(this.savedRuleForId(this.smartSavedDetailId));
  }

  private savedDetailAction(): string {
    return this.savedRuleAction(this.savedRuleForId(this.smartSavedDetailId));
  }

  private savedDetailEnabled(): boolean {
    return this.savedRuleForId(this.smartSavedDetailId).enabled;
  }

  private setSavedRuleEnabled(ruleId: string, enabled: boolean): void {
    const result: SavedAutomationRule[] = [];
    for (let index = 0; index < this.savedAutomationRules.length; index++) {
      const rule = this.savedAutomationRules[index];
      const updated = new SavedAutomationRule();
      updated.id = rule.id;
      updated.kind = rule.kind;
      updated.title = rule.title;
      updated.templateId = rule.templateId;
      updated.conditionId = rule.conditionId;
      updated.actionId = rule.actionId;
      updated.condition = rule.condition;
      updated.action = rule.action;
      updated.enabled = rule.id === ruleId ? enabled : rule.enabled;
      result.push(updated);
    }
    this.savedAutomationRules = result;
  }

  private async runSavedRuleOnce(): Promise<void> {
    this.smartBusy = true;
    this.smartMessage = '';
    try {
      const rule = this.savedRuleForId(this.smartSavedDetailId);
      if (rule.kind === 'template') {
        await this.deviceManager.applySmartTemplate(rule.templateId);
      } else {
        await this.deviceManager.applyCustomAutomation(rule.conditionId, rule.actionId);
      }
      this.smartMessage = '规则已运行一次。';
      this.smartSavedDetailId = '';
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
