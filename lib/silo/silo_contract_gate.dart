/// The body Go's `http.NotFound` writes. Only a server that predates the v2
/// API answers `/api/v2/system/info` with it.
const String siloLegacyNotFoundBody = '404 page not found';

bool isSiloLegacyNotFound(String body) => body == siloLegacyNotFoundBody || body == '$siloLegacyNotFoundBody\n';

enum SiloContract { unknown, v2, updateRequired }

class SiloUpdateRequiredException implements Exception {
  static const String error = 'update_server';
  static const String message =
      'This server runs an older Silo release that this app no longer supports. Update the server, then try again.';

  const SiloUpdateRequiredException();

  @override
  String toString() => 'SiloUpdateRequiredException: $message';
}

/// Holds the server's contract verdict and blocks v2 calls while it says the
/// server must be updated. It never sends a request itself.
class SiloContractGate {
  SiloContract _contract;

  SiloContractGate([this._contract = SiloContract.unknown]);

  SiloContract get contract => _contract;

  bool get isBlocked => _contract == SiloContract.updateRequired;

  /// Records the verdict from a `/api/v2/system/info` probe. Every outcome
  /// other than a 200 with `api_major == 2` or the exact legacy 404 is a
  /// failed probe, which leaves the stored verdict alone.
  void recordProbe({required int status, required String body, int? apiMajor}) {
    if (status == 404 && isSiloLegacyNotFound(body)) {
      _contract = SiloContract.updateRequired;
    } else if (status == 200 && apiMajor == 2) {
      _contract = SiloContract.v2;
    }
  }

  void check() {
    if (isBlocked) throw const SiloUpdateRequiredException();
  }
}
