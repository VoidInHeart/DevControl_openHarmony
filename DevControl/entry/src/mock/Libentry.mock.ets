const NativeMock: Record<string, Object> = {
  'generateMessageId': (): string => 'mock-message-id-000000000000',
  'generateNonce': (): string => 'mock-nonce-0000',
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
