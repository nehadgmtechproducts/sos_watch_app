import 'package:connectivity_plus/connectivity_plus.dart';

/// Whether the device currently has a network interface up (Wi-Fi or mobile
/// data). This is an interface check, not a guarantee of live internet (e.g. a
/// Wi-Fi network with no upstream connection still reports "connected") — but
/// it's enough to skip a doomed, slow network call when the device is plainly
/// offline (airplane mode, no SIM/Wi-Fi at all).
class ConnectivityService {
  ConnectivityService._();
  static final ConnectivityService instance = ConnectivityService._();

  final Connectivity _connectivity = Connectivity();

  Future<bool> hasNetwork() async {
    try {
      final results = await _connectivity.checkConnectivity();
      return results.any((r) => r != ConnectivityResult.none);
    } catch (_) {
      // If the platform check itself fails, don't let that block the SOS flow
      // — fall back to attempting the ring push and let it time out/fail on
      // its own rather than silently skip it.
      return true;
    }
  }
}
