export class Constants {
  static readonly TICK_INTERVAL_MS: number = 5000;
  static readonly DEFAULT_GATEWAY_ENDPOINT: string = 'https://127.0.0.1:8443';
  static readonly HEARTBEAT_TIMEOUT_MS: number = 45000;
  static readonly MESSAGE_CLOCK_SKEW_MS: number = 60000;
  static readonly COMMAND_TIMEOUT_MS: number = 8000;
  static readonly TEMP_MIN: number = 16;
  static readonly TEMP_MAX: number = 30;
  static readonly HUMIDITY_MIN: number = 20;
  static readonly HUMIDITY_MAX: number = 80;
  static readonly BRIGHTNESS_MIN: number = 0;
  static readonly BRIGHTNESS_MAX: number = 100;
  static readonly ILLUMINANCE_THRESHOLD_MIN: number = 10;
  static readonly ILLUMINANCE_THRESHOLD_MAX: number = 500;
  static readonly NO_PRESENCE_DELAY_MIN: number = 5;
  static readonly NO_PRESENCE_DELAY_MAX: number = 600;
  static readonly BRAND_HAIER: string = 'haier';
  static readonly BRAND_GREE: string = 'gree';
  static readonly BRAND_MIDEA: string = 'midea';
}
