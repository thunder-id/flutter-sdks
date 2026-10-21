// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../i18n/thunderid_i18n.dart';
import '../models/select.dart';
import 'select_list_layout.dart';
import 'thunderid_provider.dart';

/// A single-choice field: a trigger that opens a full-screen page listing [options].
///
/// It only shows the options it is given and reports what the user does, so it knows nothing
/// about fetching. To list options a page at a time, pass [onLoadMore] and keep the list up to
/// date, for example with an `InfiniteOptionsController`. The open page follows changes to
/// [options], [loading] and [onLoadMore], so rows can be appended while it is showing.
///
/// - The placeholder row clears the choice unless the field is [required].
/// - A "Load more" row follows the last option while [onLoadMore] is set. Choosing it asks for
///   more options and never changes the selection. It shows "Loading more…" and cannot be chosen
///   while [loading], and stays available after a failed load, so choosing it again repeats the
///   request.
/// - A [value] that is not among [options] is labelled by the option last picked here, then by
///   [selectedOption], then by the value itself.
class SelectField extends StatefulWidget {
  /// Identifies the field for accessibility and tests (`thunderid-field-<name>`).
  final String name;

  /// The submitted value of the chosen option, or an empty string.
  final String value;

  /// Called with the value of the chosen option, or an empty string when the choice is cleared.
  final ValueChanged<String> onChanged;

  /// The options to list.
  final List<SelectOption> options;

  /// The field's label.
  final String label;

  /// Text of the row that clears the choice, and of the trigger while nothing is chosen.
  final String? placeholder;

  /// A validation message shown below the field.
  final String? errorText;

  /// Whether a choice is mandatory. A required field cannot be cleared.
  final bool required;

  /// Whether the field responds to taps.
  final bool enabled;

  /// Whether options are being fetched.
  final bool loading;

  /// Called when the "Load more" row is chosen. Pass it only while more options may exist.
  final VoidCallback? onLoadMore;

  /// Shown when there are no options, nothing is loading and there is nothing more to load.
  final String? emptyText;

  /// Labels [value] while it is not among [options], such as a value loaded from saved data.
  final SelectOption? selectedOption;

  const SelectField({
    super.key,
    required this.name,
    required this.value,
    required this.onChanged,
    required this.options,
    required this.label,
    this.placeholder,
    this.errorText,
    this.required = false,
    this.enabled = true,
    this.loading = false,
    this.onLoadMore,
    this.emptyText,
    this.selectedOption,
  });

  @override
  State<SelectField> createState() => _SelectFieldState();
}

/// What the open page shows. It is rebuilt from the widget each time the widget changes.
class _SelectView {
  final List<SelectOption> options;
  final String value;
  final bool loading;
  final VoidCallback? onLoadMore;
  final SelectOption? outsideOption;

  const _SelectView({
    required this.options,
    required this.value,
    required this.loading,
    required this.onLoadMore,
    required this.outsideOption,
  });
}

/// The result of the page: the chosen option, or `null` for the row that clears the choice.
/// Dismissing the page without choosing returns no result at all.
class _SelectChoice {
  final SelectOption? option;

  const _SelectChoice(this.option);
}

class _SelectFieldState extends State<SelectField> {
  SelectOption? _picked;
  ValueNotifier<_SelectView>? _view;
  bool _isOpen = false;

  @override
  void dispose() {
    _view?.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(SelectField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isOpen) return;
    // The open page is not below this widget, so it cannot be marked for rebuild while the tree
    // is being built; it is told once the frame is done.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted && _isOpen) _view?.value = _currentView();
    });
  }

  _SelectView _currentView() {
    final chosen = resolveSelectOption(
      widget.value,
      widget.options,
      picked: _picked,
      selectedOption: widget.selectedOption,
    );
    return _SelectView(
      options: widget.options,
      value: widget.value,
      loading: widget.loading,
      onLoadMore: widget.onLoadMore,
      outsideOption: chosen != null && !widget.options.any((o) => o.value == chosen.value)
          ? chosen
          : null,
    );
  }

  Future<void> _open(BuildContext context, ThunderIDI18n i18n) async {
    final view = _view ??= ValueNotifier<_SelectView>(_currentView());
    view.value = _currentView();
    _isOpen = true;
    final choice = await Navigator.of(context).push<_SelectChoice>(
      PageRouteBuilder<_SelectChoice>(
        opaque: true,
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
        pageBuilder: (context, animation, secondaryAnimation) => _SelectListPage(
          name: widget.name,
          view: view,
          clearable: !widget.required,
          placeholderText: widget.placeholder ?? i18n.resolve('select.placeholder'),
          emptyText: widget.emptyText ?? i18n.resolve('select.empty'),
          i18n: i18n,
        ),
      ),
    );
    _isOpen = false;
    if (choice == null || !mounted) return;
    setState(() => _picked = choice.option);
    widget.onChanged(choice.option?.value ?? '');
  }

  @override
  Widget build(BuildContext context) {
    final i18n = ThunderIDProvider.of(context).i18n;
    final placeholderText = widget.placeholder ?? i18n.resolve('select.placeholder');
    final chosen = resolveSelectOption(
      widget.value,
      widget.options,
      picked: _picked,
      selectedOption: widget.selectedOption,
    );
    final triggerLabel = widget.value.isEmpty ? null : (chosen?.label ?? widget.value);
    final accessibleLabel =
        widget.required ? '${widget.label}, ${i18n.resolve('select.required')}' : widget.label;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      // See the note on FlowForm's own fields: Semantics.identifier is what an external,
      // black-box test driver can target (maps to resource-id/accessibilityIdentifier), so it
      // carries the field identifier alongside the widget Key used by in-process widget tests.
      // The children are excluded so a screen reader announces the label and the current choice
      // once, as one button.
      child: Semantics(
        identifier: 'thunderid-field-${widget.name}',
        container: true,
        button: true,
        enabled: widget.enabled,
        label: accessibleLabel,
        value: triggerLabel ?? placeholderText,
        hint: widget.errorText,
        excludeSemantics: true,
        onTap: widget.enabled ? () => _open(context, i18n) : null,
        child: InkWell(
          key: Key('thunderid-field-${widget.name}'),
          onTap: widget.enabled ? () => _open(context, i18n) : null,
          child: InputDecorator(
            isEmpty: false,
            decoration: InputDecoration(
              labelText: widget.required ? '${widget.label} *' : widget.label,
              errorText: widget.errorText,
              enabled: widget.enabled,
              floatingLabelBehavior: FloatingLabelBehavior.always,
              border: const OutlineInputBorder(),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    triggerLabel ?? placeholderText,
                    style: triggerLabel == null
                        ? TextStyle(color: Theme.of(context).hintColor)
                        : null,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.arrow_drop_down),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The full-screen page pushed by [_SelectFieldState._open]. It draws whatever [view] holds, so
/// it keeps up with a list that grows while it is open.
class _SelectListPage extends StatelessWidget {
  final String name;
  final ValueNotifier<_SelectView> view;
  final bool clearable;
  final String placeholderText;
  final String emptyText;
  final ThunderIDI18n i18n;

  const _SelectListPage({
    required this.name,
    required this.view,
    required this.clearable,
    required this.placeholderText,
    required this.emptyText,
    required this.i18n,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(leading: const CloseButton()),
      body: ValueListenableBuilder<_SelectView>(
        valueListenable: view,
        builder: (context, current, _) {
          final layout = SelectListLayout.of(
            optionCount: current.options.length,
            loading: current.loading,
            canLoadMore: current.onLoadMore != null,
          );
          final outside = current.outsideOption;
          return ListView(
            children: [
              _row(
                context,
                key: 'thunderid-option-clear',
                title: Text(placeholderText, style: TextStyle(color: Theme.of(context).hintColor)),
                selected: current.value.isEmpty,
                enabled: clearable,
                onTap: () => Navigator.of(context).pop(const _SelectChoice(null)),
              ),
              if (outside != null) _optionRow(context, outside, current.value),
              for (final option in current.options) _optionRow(context, option, current.value),
              if (layout.status == SelectListStatus.loading)
                _statusRow(i18n.resolve('select.loading')),
              if (layout.status == SelectListStatus.empty)
                Padding(padding: const EdgeInsets.all(16), child: Text(emptyText)),
              if (layout.showsLoadMore)
                current.loading
                    ? _statusRow(i18n.resolve('select.loadingMore'))
                    : TextButton(
                        key: Key('thunderid-load-more-$name'),
                        onPressed: current.onLoadMore,
                        child: Text(i18n.resolve('select.loadMore')),
                      ),
            ],
          );
        },
      ),
    );
  }

  Widget _optionRow(BuildContext context, SelectOption option, String value) {
    final selected = option.value == value;
    return _row(
      context,
      key: 'thunderid-option-${option.value}',
      title: Text(option.label),
      selected: selected,
      enabled: !option.disabled,
      trailing: selected ? const Icon(Icons.check) : null,
      onTap: () => Navigator.of(context).pop(_SelectChoice(option)),
    );
  }

  Widget _row(
    BuildContext context, {
    required String key,
    required Widget title,
    required bool selected,
    required bool enabled,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    return Semantics(
      identifier: key,
      child: ListTile(
        key: Key(key),
        enabled: enabled,
        selected: selected,
        title: title,
        trailing: trailing,
        onTap: enabled ? onTap : null,
      ),
    );
  }

  /// A progress row that a screen reader announces politely when it appears.
  Widget _statusRow(String text) {
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text(text),
          ],
        ),
      ),
    );
  }
}
