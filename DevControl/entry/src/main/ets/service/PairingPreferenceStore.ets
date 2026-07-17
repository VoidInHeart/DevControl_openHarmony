import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

const PREFERENCES_NAME = 'devcontrol_pairing_preferences';
const LAST_GATEWAY_ADDRESS_KEY = 'lastGatewayAddress';

export class PairingPreferenceStore {
  private context: common.UIAbilityContext;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  async restoreGatewayAddress(): Promise<string> {
    const store = await preferences.getPreferences(this.context, PREFERENCES_NAME);
    const address = await store.get(LAST_GATEWAY_ADDRESS_KEY, '') as string;
    return address.indexOf('https://') === 0 ? address : '';
  }

  async saveGatewayAddress(address: string): Promise<void> {
    const normalized = address.trim().replace(/\/+$/, '');
    if (normalized.indexOf('https://') !== 0) {
      return;
    }
    const store = await preferences.getPreferences(this.context, PREFERENCES_NAME);
    await store.put(LAST_GATEWAY_ADDRESS_KEY, normalized);
    await store.flush();
  }
}
