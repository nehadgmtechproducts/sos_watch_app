/// Local development uses `adb reverse tcp:3000 tcp:3000` on the device.
/// Override with --dart-define=API_BASE_URL=https://your-server/api/v1.
class ApiConfig {
  static const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://sosbackend-omega.vercel.app/api/v1',
  );
}
