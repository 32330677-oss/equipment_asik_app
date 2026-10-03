/// Build-time configuration.
///   flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:5055/api
/// Android emulator: use http://10.0.2.2:5055/api ; a real phone: `http://PC-LAN-IP:5055/api`
class AppConfig {
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:5055/api',
  );
  static const String appName = 'Equipment Flow';
  static const String companyName = 'ASIK Engineering Construction';
}
