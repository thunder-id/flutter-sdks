// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:material_ui/material_ui.dart';

import '../../models/thunderid_error.dart';
import '../auth/sign_in.dart';
import '../thunderid_provider.dart';

/// Thrown when the re-sign-in after a step-up refusal fails, is cancelled or signs in another user.
class ReauthenticationFailed implements Exception {
  final Object cause;

  const ReauthenticationFailed(this.cause);
}

/// Whether [error] is a re-sign-in that failed because another account signed in.
bool isAnotherAccount(Object error) {
  final cause = error is ReauthenticationFailed ? error.cause : error;
  return cause is IAMException && cause.isReauthenticationByAnotherAccount;
}

/// Signs the user in again with the server's `maxAge`, and tells whether that succeeded.
typedef Reauthenticator = Future<bool> Function(int? maxAge);

/// Runs [operation]. When the server answers [ThunderIDErrorCode.stepUpRequired] and [reauthenticator]
/// gives a re-sign-in, signs the user in again and runs [operation] exactly once more.
Future<T> runWithStepUp<T>({
  required Future<Reauthenticator?> Function()? reauthenticator,
  required Future<T> Function() operation,
}) async {
  try {
    return await operation();
  } on IAMException catch (e) {
    if (reauthenticator == null || e.code != ThunderIDErrorCode.stepUpRequired) rethrow;
    final reauthenticate = await reauthenticator();
    if (reauthenticate == null) rethrow;
    final bool signedIn;
    try {
      signedIn = await reauthenticate(e.authenticationChallenge?.maxAge);
    } catch (error) {
      throw ReauthenticationFailed(error);
    }
    if (!signedIn) throw ReauthenticationFailed(e);
    return operation();
  }
}

/// The re-sign-in for the session's method: the browser for a redirect session, the sign-in flow in a
/// dialog showing [message] for an app-native one, and `null` when sign-in runs on a backend.
Future<Reauthenticator?> reauthenticatorFor(BuildContext context, {required String message}) async {
  if (!context.mounted) return null;
  final state = ThunderIDProvider.of(context);
  final client = state.client;
  final applicationId = state.config.applicationId;
  final cancelLabel = state.i18n.resolve('userProfile.cancel');
  switch (await client.reauthenticationMethod()) {
    case ReauthenticationMethod.browser:
      return (maxAge) async {
        await client.reauthenticate(maxAge: maxAge);
        if (state.mounted) await state.refresh();
        return true;
      };
    case ReauthenticationMethod.flow:
      if (applicationId == null || applicationId.isEmpty) return null;
      return (maxAge) async {
        if (!context.mounted) return false;
        final provide = captureThunderIDProvider(context);
        final outcome = await showDialog<Object>(
          context: context,
          barrierDismissible: false,
          builder: (_) => provide(
            ReauthenticationDialog(
              applicationId: applicationId,
              maxAge: maxAge,
              message: message,
              cancelLabel: cancelLabel,
            ),
          ),
        );
        // The dialog closes with `true`, or with the error that ended the flow.
        if (outcome is IAMException && outcome.isReauthenticationByAnotherAccount) throw outcome;
        return outcome == true;
      };
    case ReauthenticationMethod.unavailable:
      return null;
  }
}

/// The sign-in flow, run to sign the signed-in user in again. Closes with `true` when the flow
/// completes, the error when a request fails, and `false` when the flow ends otherwise or the user
/// cancels.
class ReauthenticationDialog extends StatefulWidget {
  final String applicationId;
  final int? maxAge;
  final String message;
  final String cancelLabel;

  const ReauthenticationDialog({
    super.key,
    required this.applicationId,
    required this.maxAge,
    required this.message,
    required this.cancelLabel,
  });

  @override
  State<ReauthenticationDialog> createState() => _ReauthenticationDialogState();
}

class _ReauthenticationDialogState extends State<ReauthenticationDialog> {
  Object? _failure;
  bool _closed = false;

  /// Closes the dialog once: a step still in flight after Cancel cannot close it again.
  void _close(Object result) {
    if (_closed || !mounted) return;
    _closed = true;
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.message, style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: 12),
              reauthenticationSignIn(
                applicationId: widget.applicationId,
                maxAge: widget.maxAge,
                onSuccess: (_) => _close(true),
                onException: (error) => _failure = error,
                onError: () => _close(_failure ?? false),
              ),
              TextButton(
                onPressed: () => _close(false),
                child: Text(widget.cancelLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
