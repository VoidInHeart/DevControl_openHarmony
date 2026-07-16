export const generateMessageId: () => string;
export const generateNonce: () => string;
export const sealCommand: (keyBase64Url: string, payloadJson: string, aadJson: string) => string;
export const openForTest: (
  keyBase64Url: string,
  nonceBase64Url: string,
  ciphertextBase64Url: string,
  authTagBase64Url: string,
  aadJson: string
) => string;
export const redactDiagnostic: (text: string) => string;
