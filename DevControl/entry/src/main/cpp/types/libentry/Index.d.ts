export const createMessageId: () => string;
export const createNonce: () => string;
export const buildCommandEnvelope: (
  deviceId: string,
  action: string,
  payloadJson: string,
  expectedStateVersion: number
) => string;
export const buildSecureCommandEnvelope: (
  deviceId: string,
  action: string,
  payloadJson: string,
  base64Key: string,
  expectedStateVersion: number
) => string;
export const validateGatewayMessage: (raw: string, maxClockSkewMs: number) => string;
export const redactDiagnostic: (raw: string) => string;
