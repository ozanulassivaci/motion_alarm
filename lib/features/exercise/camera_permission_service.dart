import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

const _tag = '[CameraPermissionService]';

enum CameraPermissionState { granted, denied, permanentlyDenied }

/// Same rigor as AlarmSchedulingService's permission handling: check status,
/// request with the caller showing a rationale first, and detect when the
/// only way forward is the system Settings screen.
class CameraPermissionService {
  Future<CameraPermissionState> check() async {
    final status = await Permission.camera.status;
    debugPrint('$_tag status=$status');
    return _mapStatus(status);
  }

  Future<CameraPermissionState> request() async {
    final status = await Permission.camera.request();
    debugPrint('$_tag request result=$status');
    return _mapStatus(status);
  }

  Future<bool> openSettings() => openAppSettings();

  CameraPermissionState _mapStatus(PermissionStatus status) {
    if (status.isGranted) return CameraPermissionState.granted;
    if (status.isPermanentlyDenied) {
      return CameraPermissionState.permanentlyDenied;
    }
    return CameraPermissionState.denied;
  }
}
