import 'dart:convert';
import 'dart:js_interop';

@JS('naiweaverWebAuthn.create')
external JSPromise<JSString> _createCredential(JSString publicKeyJson);

@JS('naiweaverWebAuthn.get')
external JSPromise<JSString> _getCredential(JSString publicKeyJson);

Future<Map<String, dynamic>> createWebAuthnCredential(
  Map<String, dynamic> publicKey,
) async {
  final result = (await _createCredential(
    jsonEncode(publicKey).toJS,
  ).toDart).toDart;
  return jsonDecode(result) as Map<String, dynamic>;
}

Future<Map<String, dynamic>> getWebAuthnCredential(
  Map<String, dynamic> publicKey,
) async {
  final result = (await _getCredential(
    jsonEncode(publicKey).toJS,
  ).toDart).toDart;
  return jsonDecode(result) as Map<String, dynamic>;
}
