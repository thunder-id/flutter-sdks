// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../flow_template_resolver.dart';
import '../models/flow_models.dart';
import 'adapters/facebook_button.dart';
import 'adapters/github_button.dart';
import 'adapters/google_button.dart';
import 'adapters/linkedin_button.dart';
import 'adapters/microsoft_button.dart';
import 'adapters/outlined_trigger_button.dart';
import 'adapters/passkey_button.dart';
import 'thunderid_provider.dart';

/// Internal widget used by [SignIn] and [SignUp] to render a
/// server-driven flow step. Supports `meta.components` layout when present,
/// with a plain `inputs`/`actions` fallback.
class FlowForm extends StatefulWidget {
  final String applicationId;
  final EmbeddedFlowResponse? currentStep;
  final bool isLoading;
  /// The actionId currently being submitted, if known. When set, only the
  /// button matching this id shows a spinner while `isLoading` is true —
  /// the rest are disabled but keep their label instead of all spinning
  /// together. Null falls back to spinning every button (e.g. builders that
  /// don't track which action is in flight).
  final String? loadingActionId;
  final String? error;
  final Future<void> Function(String actionId, Map<String, String> inputs)
      submit;
  final String submitLabel;

  const FlowForm({
    super.key,
    required this.applicationId,
    required this.currentStep,
    required this.isLoading,
    required this.error,
    required this.submit,
    this.loadingActionId,
    this.submitLabel = 'Submit',
  });

  @override
  State<FlowForm> createState() => _FlowFormState();
}

class _FlowFormState extends State<FlowForm> {
  final _controllers = <String, TextEditingController>{};
  final _linkRecognizers = <TapGestureRecognizer>[];
  FlowTemplateResolver? _resolver;

  @override
  void initState() {
    super.initState();
    if (widget.applicationId.isNotEmpty) {
      Future.microtask(_fetchMeta);
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      {
      c.dispose();
    }
    for (final r in _linkRecognizers) {
      r.dispose();
    }
    }
    super.dispose();
  }

  Future<void> _fetchMeta() async {
    try {
      final thunder = ThunderIDProvider.of(context);
      final meta = await thunder.client.getFlowMeta(widget.applicationId);
      if (mounted) setState(() => _resolver = FlowTemplateResolver(meta));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isLoading && widget.currentStep == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final step = widget.currentStep;
    if (step != null &&
        (step.flowStatus == FlowStatus.complete ||
            (step.assertion?.isNotEmpty ?? false))) {
      return const Center(child: CircularProgressIndicator());
    }

    // _renderRichText appends a fresh TapGestureRecognizer per link on every build; dispose the
    // previous build's recognizers first so they don't accumulate across rebuilds.
    for (final r in _linkRecognizers) {
      r.dispose();
    }
    _linkRecognizers.clear();

    final data = step?.data;
    final rawMeta = data?['meta'];
    final components = rawMeta is Map
        ? _readList(rawMeta['components'])
        : const <Map<String, dynamic>>[];
    final inputs = _readList(data?['inputs']);
    final actions = _readList(data?['actions']);

    // An error response carries no UI of its own — the previous step's inputs/actions are
    // stale once the server has rejected the last submission, so show only the error instead
    // of a form the user can no longer meaningfully interact with.
    final hasError = widget.error != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!hasError) ...[
          if (components.isNotEmpty) ...[
            ...components.map((c) => _renderComponent(context, c, actions)),
            ..._missingInputWidgets(context, inputs, components),
            if (!_hasActionComponent(components) && actions.isNotEmpty)
              ...actions.map((a) => _renderAction(context, a, actions)),
          ] else ...[
            ...inputs.map(
              (i) => _renderField(
                context,
                {'ref': _inputRef(i), 'label': '', 'type': i['type']},
                _str(i['type']),
              ),
            ),
            if (actions.isNotEmpty)
              ...actions.map((a) => _renderAction(context, a, actions))
            else
              _renderAction(
                context,
                {'label': widget.submitLabel, 'id': 'init'},
                const [],
              ),
          ],
        ],
        if (widget.error != null) _ErrorBanner(message: widget.error!),
      ],
    );
  }

  List<Widget> _missingInputWidgets(
    BuildContext context,
    List<Map<String, dynamic>> inputs,
    List<Map<String, dynamic>> components,
  ) {
    final fieldRefs = _componentFieldRefs(components);
    return inputs.where((i) {
      final ref = _inputRef(i);
      return ref.isNotEmpty && !fieldRefs.contains(ref);
    }).map((i) {
      final ref = _inputRef(i);
      return _renderField(
        context,
        {'ref': ref, 'label': _capitalize(ref), 'type': i['type']},
        _str(i['type']),
      );
    }).toList();
  }

  String _effectiveCategory(Map<String, dynamic> comp) {
    final category = _str(comp['category']);
    if (category.isNotEmpty) return category;
    switch (_str(comp['type'])) {
      case 'DIVIDER':
        return 'DIVIDER';
      case 'RICH_TEXT':
        return 'RICH_TEXT';
      case 'TEXT':
      case 'IMAGE':
        return 'DISPLAY';
      case 'BLOCK':
        return 'BLOCK';
      case 'TEXT_INPUT':
      case 'PASSWORD_INPUT':
      case 'EMAIL_INPUT':
      case 'NUMBER_INPUT':
        return 'FIELD';
      case 'ACTION':
        return 'ACTION';
      default:
        return '';
    }
  }

  Widget _renderComponent(
    BuildContext context,
    Map<String, dynamic> comp,
    List<Map<String, dynamic>> actions,
  ) {
    switch (_effectiveCategory(comp)) {
      case 'DISPLAY':
        return _renderDisplay(context, comp, actions);
      case 'DIVIDER':
        return _renderDivider(context, comp);
      case 'RICH_TEXT':
        return _renderRichText(context, comp, actions);
      case 'BLOCK':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: _readList(comp['components'])
              .map((c) => _renderComponent(context, c, actions))
              .toList(),
        );
      case 'FIELD':
        return _renderField(context, comp, _str(comp['type']));
      case 'ACTION':
        final nested = _readList(comp['components']);
        if (nested.isNotEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children:
                nested.map((c) => _renderComponent(context, c, actions)).toList(),
          );
        }
        return _renderAction(context, comp, actions);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _renderDisplay(
    BuildContext context,
    Map<String, dynamic> comp,
    List<Map<String, dynamic>> actions,
  ) {
    final type = _str(comp['type']);
    // The real backend sends an explicit `category: "DISPLAY"` on DIVIDER
    // and RICH_TEXT components too, so `_effectiveCategory` short-circuits
    // to 'DISPLAY' before ever consulting `type`. Dispatch on `type` here
    // so those components still render correctly instead of being dropped.
    if (type == 'DIVIDER') {
      return _renderDivider(context, comp);
    }
    if (type == 'RICH_TEXT') {
      return _renderRichText(context, comp, actions);
    }
    if (type == 'TEXT') {
      final label = _resolve(comp['label']);
      if (label.isEmpty) return const SizedBox.shrink();
      final style = _str(comp['variant']) == 'HEADING_1'
          ? Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.bold)
          : Theme.of(context).textTheme.bodyMedium;
      final align =
          _str(comp['align']) == 'center' ? TextAlign.center : TextAlign.start;
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Text(label, style: style, textAlign: align),
      );
    }
    if (type == 'IMAGE') {
      final src = _str(comp['src']);
      if (src.isEmpty || src.startsWith('{{')) return const SizedBox.shrink();
      final h = double.tryParse(_str(comp['height']));
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Image.network(src, height: h),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _renderDivider(BuildContext context, Map<String, dynamic> comp) {
    final label = _resolve(comp['label'], fallback: 'Or');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          const Expanded(child: Divider()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          const Expanded(child: Divider()),
        ],
      ),
    );
  }

  Widget _renderRichText(
    BuildContext context,
    Map<String, dynamic> comp,
    List<Map<String, dynamic>> actions,
  ) {
    final html = _resolve(comp['label']);
    if (html.isEmpty) return const SizedBox.shrink();

    // Anchors carry either an `href` (an external URL to open) or a
    // `data-action-ref` (a sentinel identifying a flow action to submit in-app,
    // matching the web SDK's sentinel-anchor contract). There's no DOM/browser
    // navigation on mobile, so `data-action-ref` always wins when present.
    final linkPattern = RegExp(r'<a\b([^>]*)>(.*?)</a>', dotAll: true);
    final attrPattern = RegExp(r'([\w-]+)\s*=\s*"([^"]*)"');
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final match in linkPattern.allMatches(html)) {
      if (match.start > cursor) {
        final plain = _stripTags(html.substring(cursor, match.start));
        if (plain.trim().isNotEmpty) spans.add(TextSpan(text: plain));
      }
      final attrs = <String, String>{};
      for (final attrMatch in attrPattern.allMatches(match.group(1) ?? '')) {
        attrs[attrMatch.group(1)!.toLowerCase()] = attrMatch.group(2) ?? '';
      }
      final actionRef = attrs['data-action-ref'] ?? '';
      final href = attrs['href'] ?? '';
      final linkText = _stripTags(match.group(2) ?? '').trim();
      final onTap = actionRef.isNotEmpty
          ? () => _dispatchRichTextAction(actionRef, actions)
          : () => _openLink(href);
      final recognizer = TapGestureRecognizer()..onTap = onTap;
      _linkRecognizers.add(recognizer);
      spans.add(
        TextSpan(
          text: linkText,
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            decoration: TextDecoration.underline,
          ),
          recognizer: recognizer,
        ),
      );
      cursor = match.end;
    }
    if (cursor < html.length) {
      final plain = _stripTags(html.substring(cursor));
      if (plain.trim().isNotEmpty) spans.add(TextSpan(text: plain));
    }
    if (spans.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 16),
      child: Text.rich(
        TextSpan(
          style: Theme.of(context).textTheme.bodyMedium,
          children: spans,
        ),
      ),
    );
  }

  void _dispatchRichTextAction(
    String actionRef,
    List<Map<String, dynamic>> actions,
  ) {
    if (widget.isLoading) return;
    final actionId = _findActionId(actionRef, actions);
    widget.submit(actionId, _controllers.map((k, v) => MapEntry(k, v.text)));
  }

  String _stripTags(String value) => value.replaceAll(RegExp(r'<[^>]+>'), '');

  Future<void> _openLink(String url) async {
    if (url.isEmpty || url.startsWith('{{')) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (uri.scheme.toLowerCase() != 'http' && uri.scheme.toLowerCase() != 'https') {
      return;
    }
    await launchUrl(uri);
  }

  Widget _renderField(
    BuildContext context,
    Map<String, dynamic> comp,
    String type,
  ) {
    final ref = _fieldRef(comp);
    if (ref.isEmpty) return const SizedBox.shrink();
    _controllers.putIfAbsent(ref, TextEditingController.new);
    final isPassword = type.toLowerCase().contains('password');
    final label = _resolve(comp['label'], fallback: _capitalize(ref));
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      // A widget Key is internal to the Flutter tree and never reaches the platform
      // accessibility tree, so it cannot be targeted by anything driving the app from outside
      // (UI Automator, XCUITest, and black-box runners such as Maestro). Semantics.identifier
      // is what maps to resource-id on Android and accessibilityIdentifier on iOS. The Key is
      // kept as well so widget tests can keep finding these fields by key.
      child: Semantics(
        identifier: 'thunderid-field-${_fieldTestId(comp)}',
        child: TextField(
          key: Key('thunderid-field-$ref'),
          controller: _controllers[ref],
          decoration: InputDecoration(
            labelText: label,
            hintText: _resolve(comp['placeholder'], fallback: _capitalize(ref)),
            floatingLabelBehavior: FloatingLabelBehavior.always,
            border: const OutlineInputBorder(),
          ),
          obscureText: isPassword,
          keyboardType: isPassword
              ? TextInputType.visiblePassword
              : TextInputType.emailAddress,
          autocorrect: false,
        ),
      ),
    );
  }

  Widget _renderAction(
    BuildContext context,
    Map<String, dynamic> comp,
    List<Map<String, dynamic>> actions,
  ) {
    final label = _resolve(comp['label'], fallback: widget.submitLabel);
    final metaActionId = _str(comp['ref'], fallback: _str(comp['id']));
    final actionId = _findActionId(metaActionId, actions);
    final eventType = _str(
      comp['eventType'],
      fallback: _str(_actionForId(metaActionId, actions)?['eventType']),
    );

    // Only the button whose actionId matches the in-flight submission shows a
    // spinner; the rest stay disabled (to prevent overlapping submits) but
    // keep their label instead of all spinning together.
    final isActiveAction =
        widget.loadingActionId == null || widget.loadingActionId == actionId;
    final isSpinning = widget.isLoading && isActiveAction;
    final isBlocked = widget.isLoading && !isActiveAction;

    if (eventType.toUpperCase() == 'TRIGGER') {
      void onPressed() => widget.submit(
            actionId,
            _controllers.map((k, v) => MapEntry(k, v.text)),
          );
      final hint =
          '$metaActionId $label ${_str(comp['icon'])}'.toLowerCase();
      if (hint.contains('google')) {
        return GoogleButton(
          label: label,
          isLoading: isSpinning,
          disabled: isBlocked,
          onPressed: onPressed,
        );
      }
      if (hint.contains('github')) {
        return GitHubButton(
          label: label,
          isLoading: isSpinning,
          disabled: isBlocked,
          onPressed: onPressed,
        );
      }
      if (hint.contains('facebook')) {
        return FacebookButton(
          label: label,
          isLoading: isSpinning,
          disabled: isBlocked,
          onPressed: onPressed,
        );
      }
      if (hint.contains('microsoft')) {
        return MicrosoftButton(
          label: label,
          isLoading: isSpinning,
          disabled: isBlocked,
          onPressed: onPressed,
        );
      }
      if (hint.contains('linkedin')) {
        return LinkedInButton(
          label: label,
          isLoading: isSpinning,
          disabled: isBlocked,
          onPressed: onPressed,
        );
      }
      if (hint.contains('passkey')) {
        return PasskeyButton(
          label: label,
          isLoading: isSpinning,
          disabled: isBlocked,
          onPressed: onPressed,
        );
      }
      return OutlinedTriggerButton(
        label: label,
        isLoading: isSpinning,
        disabled: isBlocked,
        onPressed: onPressed,
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      // See the note on the field above: the Key alone is invisible outside the Flutter tree,
      // so the identifier is what an external driver can actually target.
      child: Semantics(
        identifier: 'thunderid-action-$actionId',
        child: FilledButton(
          key: Key('thunderid-action-$actionId'),
          onPressed: widget.isLoading
              ? null
              : () => widget.submit(
                    actionId,
                    _controllers.map((k, v) => MapEntry(k, v.text)),
                  ),
          child: isSpinning
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(label),
        ),
      ),
    );
  }

  Map<String, dynamic>? _actionForId(
    String metaActionId,
    List<Map<String, dynamic>> actions,
  ) {
    for (final a in actions) {
      if (_str(a['ref']) == metaActionId || _str(a['id']) == metaActionId) {
        return a;
      }
    }
    return null;
  }

  String _findActionId(
    String metaActionId,
    List<Map<String, dynamic>> actions,
  ) {
    if (actions.isEmpty) return 'submit';
    final byRef = actions.firstWhere(
      (a) => _str(a['ref']) == metaActionId,
      orElse: () => const {},
    );
    if (byRef.isNotEmpty) return _actionSubmitId(byRef);
    final byId = actions.firstWhere(
      (a) => _str(a['id']) == metaActionId,
      orElse: () => const {},
    );
    if (byId.isNotEmpty) return _actionSubmitId(byId);
    final idx = _actionIndex(metaActionId);
    if (idx != null && idx >= 0 && idx < actions.length) {
      return _actionSubmitId(actions[idx]);
    }
    return _actionSubmitId(actions.first);
  }

  String _actionSubmitId(Map<String, dynamic> a) => _str(
        a['ref'],
        fallback: _str(
          a['id'],
          fallback: _str(a['nextNode'], fallback: 'submit'),
        ),
      );

  int? _actionIndex(String id) {
    if (!id.startsWith('action_')) return null;
    final parsed = int.tryParse(id.substring('action_'.length));
    return (parsed != null && parsed > 0) ? parsed - 1 : null;
  }

  Set<String> _componentFieldRefs(List<Map<String, dynamic>> comps) {
    final refs = <String>{};
    void walk(List<Map<String, dynamic>> list) {
      for (final c in list) {
        if (_effectiveCategory(c) == 'FIELD') {
          final ref = _fieldRef(c);
          if (ref.isNotEmpty) refs.add(ref);
        }
        walk(_readList(c['components']));
      }
    }

    walk(comps);
    return refs;
  }

  bool _hasActionComponent(List<Map<String, dynamic>> comps) {
    bool found = false;
    void walk(List<Map<String, dynamic>> list) {
      for (final c in list) {
        if (_effectiveCategory(c) == 'ACTION') {
          found = true;
          return;
        }
        walk(_readList(c['components']));
        if (found) return;
      }
    }

    walk(comps);
    return found;
  }

  List<Map<String, dynamic>> _readList(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((m) => m.map((k, v) => MapEntry('$k', v)))
        .toList();
  }

  String _str(dynamic v, {String fallback = ''}) =>
      (v is String && v.isNotEmpty) ? v : fallback;

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  String _fieldRef(Map<String, dynamic> comp) => _str(
        comp['ref'],
        fallback: _str(
          comp['identifier'],
          fallback: _str(comp['name'], fallback: _str(comp['id'])),
        ),
      );

  /// The value used to build a field's accessibility identifier.
  ///
  /// Deliberately different from [_fieldRef], which prefers `ref` because that is the key the
  /// flow submission is built from. The iOS and Android SDKs tag their fields with the server's
  /// `identifier` instead (`thunderid-field-username`, not `thunderid-field-input_001`), so
  /// preferring `identifier` here keeps one set of selectors working across all three platforms.
  String _fieldTestId(Map<String, dynamic> comp) => _str(
        comp['identifier'],
        fallback: _str(comp['name'], fallback: _fieldRef(comp)),
      );

  String _inputRef(Map<String, dynamic> input) => _str(
        input['name'],
        fallback: _str(
          input['identifier'],
          fallback: _str(input['ref'], fallback: _str(input['id'])),
        ),
      );

  String _resolve(dynamic value, {String fallback = ''}) {
    final s = value is String ? value.trim() : '';
    if (s.isEmpty) return fallback;
    final resolved = _resolver?.resolve(s) ?? s;
    return resolved.isEmpty ? fallback : resolved;
  }
}

/// Styled error banner shown in place of the (now stale) form after a flow step fails.
class _ErrorBanner extends StatelessWidget {
  final String message;

  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: colorScheme.onErrorContainer, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: colorScheme.onErrorContainer, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
