Future<Map<String, dynamic>> createWebAuthnCredential(
  Map<String, dynamic> publicKey,
) {
  throw UnsupportedError('WebAuthn is only available in web builds');
}

Future<Map<String, dynamic>> getWebAuthnCredential(
  Map<String, dynamic> publicKey,
) {
  throw UnsupportedError('WebAuthn is only available in web builds');
}
