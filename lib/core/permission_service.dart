import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  /// Requests the POST_NOTIFICATIONS permission for Android 13+.
  /// Returns true if granted, false if denied permanently.
  static Future<bool> requestNotificationPermission() async {
    final status = await Permission.notification.request();
    return !status.isPermanentlyDenied;
  }
}
