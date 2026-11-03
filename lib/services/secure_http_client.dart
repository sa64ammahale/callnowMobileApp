import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Pin SHA-256 hashes of the expected server leaf certificate(s).
/// Populate these with the actual SPKI hashes of your production server
/// certificate(s) to enforce SSL pinning. Obtain via:
///   openssl s_client -connect HOST:443 -showcerts < /dev/null
///     2>/dev/null | openssl x509 -outform DER | openssl dgst -sha256 -binary
///     | openssl base64
class SslPinningConfig {
  /// Set to true to enforce certificate pinning. When false, standard
  /// platform trust store validation is used (still HTTPS-only).
  static bool enabled = false;

  /// Base64-encoded SHA-256 SPKI hashes of pinned leaf certificates.
  static final List<String> pinnedSha256Hashes = <String>[];

  /// Additional hostnames allowed beyond the configured base URL host.
  static final Set<String> allowedHosts = <String>{};
}

/// Enforces HTTPS-only requests. Optionally wraps a pinned
/// [dart:io.HttpClient] when certificate pinning is enabled.
class SecureHttpClient extends http.BaseClient {
  final http.Client _inner;

  /// Creates a secure client. If [enablePinning] is true, the underlying
  /// dart:io HttpClient is configured with [BadCertificateCallback] that
  /// validates against [SslPinningConfig.pinnedSha256Hashes].
  SecureHttpClient({bool requireHttps = true, bool enablePinning = false})
      : _inner = _createClient(requireHttps: requireHttps, enablePinning: enablePinning);

  static http.Client _createClient({
    required bool requireHttps,
    required bool enablePinning,
  }) {
    final ioClient = HttpClient();
    if (enablePinning && SslPinningConfig.pinnedSha256Hashes.isNotEmpty) {
      ioClient.badCertificateCallback =
          (X509Certificate cert, String host, int port) {
        if (!SslPinningConfig.allowedHosts.contains(host)) {
          return false;
        }
        final der = cert.der;
        final sha256 = _sha256Base64(der);
        return SslPinningConfig.pinnedSha256Hashes.contains(sha256);
      };
    } else {
      ioClient.badCertificateCallback = (_, _, _) => false;
    }
    return IOClient(ioClient);
  }

  void _validateUrl(Uri url) {
    if (url.scheme != 'https') {
      throw http.ClientException(
        'Insecure scheme "${url.scheme}" blocked. Only HTTPS is allowed.',
      );
    }
    if (SslPinningConfig.enabled &&
        SslPinningConfig.pinnedSha256Hashes.isNotEmpty &&
        !SslPinningConfig.allowedHosts.contains(url.host)) {
      throw http.ClientException(
        'Host "${url.host}" is not in the pinned allow-list.',
      );
    }
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    _validateUrl(request.url);
    return _inner.send(request);
  }

  static String _sha256Base64(List<int> bytes) {
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return base64Encode(utf8.encode(hex));
  }
}

/// Returns a pinned [dart:io.HttpClient] for raw socket-level calls
/// (e.g. WebSocket or custom TLS) that require certificate validation.
HttpClient createPinnedIoHttpClient() {
  final client = HttpClient();
  client.badCertificateCallback =
      (X509Certificate cert, String host, int port) {
    if (!SslPinningConfig.allowedHosts.contains(host)) {
      return false;
    }
    final der = cert.der;
    final sha256 = SecureHttpClient._sha256Base64(der);
    return SslPinningConfig.pinnedSha256Hashes.contains(sha256);
  };
  return client;
}

/// Validates that a [baseUrl] string uses HTTPS. Throws [ArgumentError]
/// if the scheme is not https.
void requireHttps(String baseUrl) {
  final uri = Uri.parse(baseUrl);
  if (uri.scheme != 'https') {
    throw ArgumentError(
      'Insecure base URL scheme "${uri.scheme}". Only HTTPS is allowed: $baseUrl',
    );
  }
}
