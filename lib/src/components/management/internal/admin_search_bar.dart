// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';

import '../admin_render_state.dart';
import '../identity_candidate.dart';
import 'admin_context.dart';
import 'admin_inputs.dart';

/// Searches an admin list by one attribute. The server matches the whole value, so the search runs
/// when submitted rather than on every keystroke.
class AdminSearchBar extends StatefulWidget {
  final AdminContext ac;
  final String block;
  final List<AdminSelectOption> attributes;
  final AdminSearch? search;
  final ValueChanged<AdminSearch?> onSearch;

  const AdminSearchBar({
    super.key,
    required this.ac,
    required this.block,
    required this.attributes,
    required this.search,
    required this.onSearch,
  });

  @override
  State<AdminSearchBar> createState() => _AdminSearchBarState();
}

class _AdminSearchBarState extends State<AdminSearchBar> {
  late String _attribute =
      widget.search?.attribute ?? (widget.attributes.isEmpty ? '' : widget.attributes.first.value);
  late String _value = widget.search?.value ?? '';

  void _apply([String? _]) {
    final trimmed = _value.trim();
    widget.onSearch(trimmed.isEmpty ? null : AdminSearch(attribute: _attribute, value: trimmed));
  }

  @override
  Widget build(BuildContext context) {
    final ac = widget.ac;
    final label = widget.attributes
        .firstWhere((option) => option.value == _attribute, orElse: () => AdminSelectOption(value: _attribute, label: _attribute))
        .label;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.attributes.length > 1)
          AdminDropdown(
            ac: ac,
            label: ac.t('admin.common.search.attribute'),
            identifier: 'thunderid-field-${widget.block}-search-attribute',
            value: _attribute,
            options: widget.attributes,
            onChanged: (value) => setState(() => _attribute = value),
          ),
        AdminTextField(
          key: ValueKey('${widget.block}-search-${widget.search?.value ?? ''}'),
          ac: ac,
          label: label,
          identifier: 'thunderid-field-${widget.block}-search',
          initialValue: _value,
          hint: ac.t('admin.common.search.placeholder', {'attribute': label.toLowerCase()}),
          onChanged: (value) => _value = value,
          onSubmitted: _apply,
        ),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          children: [
            if (widget.search != null)
              AdminButton(
                ac: ac,
                label: ac.t('admin.common.search.clear'),
                identifier: 'thunderid-action-${widget.block}-search-clear',
                variant: AdminButtonVariant.text,
                onPressed: () {
                  _value = '';
                  widget.onSearch(null);
                },
              ),
            AdminButton(
              ac: ac,
              label: ac.t('admin.common.search.submit'),
              identifier: 'thunderid-action-${widget.block}-search',
              variant: AdminButtonVariant.outline,
              onPressed: _apply,
            ),
          ],
        ),
      ],
    );
  }
}
