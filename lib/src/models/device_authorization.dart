// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'thunderid_error.dart';

/// A device authorization request (RFC 8628) started by
/// [ThunderIDClient.startDeviceAuthorization], for an input-constrained device such as a TV.
///
/// Show [userCode] and [verificationUri] (or [verificationUriComplete], for example as a QR code)
/// to the user, then hand this object to [ThunderIDClient.pollDeviceAuthorization].
///
/// [deviceCode] is a credential: never show or log it. [toString] leaves it out.
class DeviceAuthorization {
  /// The credential the token endpoint is polled with. Never shown or logged.
  final String deviceCode;

  /// The code the user enters on the verification page.
  final String userCode;

  /// Where the user enters [userCode].
  final String verificationUri;

  /// [verificationUri] with [userCode] already filled in, when the server returns one.
  final String? verificationUriComplete;

  /// The lifetime of [deviceCode], in seconds.
  final int expiresIn;

  /// The minimum wait between two polls, in seconds.
  final int interval;

  const DeviceAuthorization({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    this.verificationUriComplete,
    required this.expiresIn,
    required this.interval,
  });

  /// Reads the native SDK's answer. A missing interval takes the RFC 8628 default of 5 seconds.
  factory DeviceAuthorization.fromMap(Map<dynamic, dynamic> map) {
    final deviceCode = map['deviceCode'];
    final userCode = map['userCode'];
    final verificationUri = map['verificationUri'];
    if (deviceCode is! String || deviceCode.isEmpty || userCode is! String || userCode.isEmpty) {
      throw const IAMException(
        ThunderIDErrorCode.serverError,
        'startDeviceAuthorization: the response carries no device_code or user_code.',
      );
    }
    final complete = map['verificationUriComplete'];
    final expiresIn = map['expiresIn'];
    final interval = map['interval'];
    return DeviceAuthorization(
      deviceCode: deviceCode,
      userCode: userCode,
      verificationUri: verificationUri is String ? verificationUri : '',
      verificationUriComplete: complete is String && complete.isNotEmpty ? complete : null,
      expiresIn: expiresIn is num ? expiresIn.toInt() : 0,
      interval: interval is num ? interval.toInt() : 5,
    );
  }

  @override
  String toString() =>
      'DeviceAuthorization(userCode: $userCode, verificationUri: $verificationUri, expiresIn: $expiresIn, '
      'interval: $interval)';
}
