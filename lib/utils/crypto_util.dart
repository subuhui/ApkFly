import 'dart:convert';
import 'dart:typed_data';

import 'package:asn1lib/asn1lib.dart';
import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

String hmacSha256Hex(String data, String key) {
  final digest = Hmac(sha256, utf8.encode(key)).convert(utf8.encode(data));
  return digest.toString();
}

String md5Hex(String data) => md5.convert(utf8.encode(data)).toString();

String rsaEncryptX509ToHex(String content, String certificateText) {
  final publicKey = _publicKeyFromCertificate(certificateText);
  final cipher = PKCS1Encoding(RSAEngine())
    ..init(true, PublicKeyParameter<RSAPublicKey>(publicKey));
  final bytes = Uint8List.fromList(utf8.encode(content));
  final chunks = <int>[];
  const blockSize = 117;
  for (var offset = 0; offset < bytes.length; offset += blockSize) {
    final end = (offset + blockSize).clamp(0, bytes.length);
    chunks.addAll(cipher.process(bytes.sublist(offset, end)));
  }
  return chunks.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

RSAPublicKey _publicKeyFromCertificate(String certificateText) {
  final normalized = certificateText.replaceAll(
    RegExp(r'-----BEGIN CERTIFICATE-----|-----END CERTIFICATE-----|\s'),
    '',
  );
  final bytes = base64Decode(normalized);
  final cert =
      ASN1Parser(Uint8List.fromList(bytes)).nextObject() as ASN1Sequence;
  final tbs = cert.elements.first as ASN1Sequence;
  final subjectPublicKeyInfo = tbs.elements[6] as ASN1Sequence;
  final publicKeyBitString = subjectPublicKeyInfo.elements[1] as ASN1BitString;
  final keySeq =
      ASN1Parser(
            Uint8List.fromList(publicKeyBitString.stringValue),
          ).nextObject()
          as ASN1Sequence;
  final modulus = (keySeq.elements[0] as ASN1Integer).valueAsBigInteger;
  final exponent = (keySeq.elements[1] as ASN1Integer).valueAsBigInteger;
  return RSAPublicKey(modulus, exponent);
}
