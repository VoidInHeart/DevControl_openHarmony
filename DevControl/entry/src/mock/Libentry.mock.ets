const NativeMock: Record<string, Object> = {
  'generateMessageId': (): string => 'mock-message-id-000000000000',
  // URL-safe Base64 encoding of 12 bytes, matching the HUKS AES-GCM IV size.
  'generateNonce': (): string => 'AAECAwQFBgcICQoL',
  'sealCommand': (): string => {
    return JSON.stringify({
      nonce: 'mock-nonce-0000',
      ciphertext: 'mock-ciphertext',
      authTag: 'mock-auth-tag-000000'
    });
  },
  'openForTest': (): string => '{}',
  'redactDiagnostic': (text: string): string => {
    return text.replace(/Bearer\s+[A-Za-z0-9_-]+/g, 'Bearer ***');
  }
};

export default NativeMock;
