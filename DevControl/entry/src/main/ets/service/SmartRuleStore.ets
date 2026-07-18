import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

const PREFERENCES_NAME = 'devcontrol_smart_rules';
const SMART_RULES_KEY = 'savedRules';
const MAX_TEXT_LENGTH = 120;

/**
 * The small rule library displayed in the Smart tab. Rules are intentionally
 * stored separately from the gateway session: they contain no credentials and
 * remain available after the app restarts or reconnects to the same gateway.
 */
export class SavedSmartRules {
  templateId: string = '';
  templateTitle: string = '';
  templateEnabled: boolean = true;
  customTitle: string = '';
  customConditionId: string = '';
  customActionId: string = '';
  customCondition: string = '';
  customAction: string = '';
  customEnabled: boolean = true;
}

export class SmartRuleStore {
  private context: common.UIAbilityContext;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  async restore(): Promise<SavedSmartRules> {
    const store = await preferences.getPreferences(this.context, PREFERENCES_NAME);
    const text = await store.get(SMART_RULES_KEY, '') as string;
    if (text.length === 0) {
      return new SavedSmartRules();
    }
    try {
      const raw = JSON.parse(text) as Record<string, Object>;
      return this.parse(raw);
    } catch (error) {
      // A malformed local preference must not prevent the Smart page from
      // loading. The next successful save replaces the invalid value.
      return new SavedSmartRules();
    }
  }

  async save(rules: SavedSmartRules): Promise<void> {
    const store = await preferences.getPreferences(this.context, PREFERENCES_NAME);
    await store.put(SMART_RULES_KEY, JSON.stringify(rules));
    await store.flush();
  }

  private parse(raw: Record<string, Object>): SavedSmartRules {
    const rules = new SavedSmartRules();
    rules.templateId = this.text(raw['templateId']);
    rules.templateTitle = this.text(raw['templateTitle']);
    rules.templateEnabled = this.boolean(raw['templateEnabled'], true);
    rules.customTitle = this.text(raw['customTitle']);
    rules.customConditionId = this.text(raw['customConditionId']);
    rules.customActionId = this.text(raw['customActionId']);
    rules.customCondition = this.text(raw['customCondition']);
    rules.customAction = this.text(raw['customAction']);
    rules.customEnabled = this.boolean(raw['customEnabled'], true);
    return rules;
  }

  private text(value: Object | undefined): string {
    if (typeof value !== 'string' || value.length > MAX_TEXT_LENGTH) {
      return '';
    }
    return value;
  }

  private boolean(value: Object | undefined, fallback: boolean): boolean {
    return typeof value === 'boolean' ? value : fallback;
  }
}
