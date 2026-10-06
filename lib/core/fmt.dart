import 'package:intl/intl.dart';

/// Formatting helpers. Server date-times are wall-clock strings 'YYYY-MM-DD HH:mm:ss'
/// in the business time zone, so they are sliced, never converted.
class Fmt {
  static final _d = DateFormat('yyyy-MM-dd');
  static final _dt = DateFormat('yyyy-MM-dd HH:mm');

  /// Difference between the business clock of the server (Syria time) and the clock of this device.
  /// Every "now" / "today" of the app uses the server clock, never the phone's time or time zone.
  static Duration _skew = Duration.zero;
  static bool synced = false;

  /// Called with the server's business wall time ('YYYY-MM-DD HH:mm:ss', header X-Business-Now).
  static void syncServerNow(String? wall) {
    if (wall == null || wall.length < 16) return;
    final server = DateTime.tryParse(wall.substring(0, 19).replaceFirst(' ', 'T'));
    if (server == null) return;
    _skew = server.difference(DateTime.now());
    synced = true;
  }

  /// Business "now" (server clock) as a wall-clock DateTime.
  static DateTime now() => DateTime.now().add(_skew);

  static String today() => _d.format(now());
  static String nowWall() => _dt.format(now());
  static String dateOf(DateTime d) => _d.format(d);
  static String wallOf(DateTime d) => _dt.format(d);
  static String thisMonth() => DateFormat('yyyy-MM').format(now());

  static DateTime? parse(String? s) {
    if (s == null || s.length < 10) return null;
    return DateTime.tryParse(s.length > 10 ? s.substring(0, 16).replaceFirst(' ', 'T') : s);
  }

  /// 03/10/2026
  static String date(String? s) {
    if (s == null || s.length < 10) return '-';
    return '${s.substring(8, 10)}/${s.substring(5, 7)}/${s.substring(0, 4)}';
  }

  /// Sat 03 Oct
  static String dayLabel(String? s) {
    final d = parse(s);
    return d == null ? '-' : DateFormat('EEE dd MMM').format(d);
  }

  static String monthLabel(String yyyymm) {
    final d = DateTime.tryParse('$yyyymm-01');
    return d == null ? yyyymm : DateFormat('MMMM yyyy').format(d);
  }

  /// 07:02
  static String time(String? s) => (s == null || s.length < 16) ? '--:--' : s.substring(11, 16);

  /// 07:02, or "18:00 +1" when the time is on the next day of [baseDate]
  static String timeOn(String? s, String? baseDate) {
    if (s == null || s.length < 16) return '--:--';
    final t = s.substring(11, 16);
    return (baseDate != null && s.substring(0, 10) != baseDate.substring(0, 10)) ? '$t +1' : t;
  }

  static String hoursFromMinutes(num? minutes) => minutes == null ? '-' : (minutes / 60).toStringAsFixed(2);

  static String duration(num? minutes) {
    if (minutes == null) return '-';
    final m = minutes.round();
    final h = m ~/ 60;
    final r = m % 60;
    if (h == 0) return '${r}m';
    return r == 0 ? '${h}h' : '${h}h ${r}m';
  }

  static String num2(num? v) => v == null ? '-' : NumberFormat('#,##0.00').format(v);

  static String money(num? v, [String? currency]) {
    if (v == null) return '-';
    final cur = currency ?? 'USD';
    if (cur == 'SYP') return 'SYP ${NumberFormat('#,##0').format(v)}';
    return '$cur ${NumberFormat('#,##0.00').format(v)}';
  }

  static String money2(String? v, [String? currency]) => money(double.tryParse(v ?? ''), currency);
}
