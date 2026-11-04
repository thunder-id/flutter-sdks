// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../models/user.dart';
import '../../account/user_avatar.dart';
import 'admin_context.dart';
import 'admin_inputs.dart';

// Package-internal (not exported): layout pieces shared by the admin components. None of them
// renders navigation, an app bar, or routes; the application owns those (spec "UI",
// requirement 6).

/// The frame of every admin component: an optional header (title, description, actions) over
/// the content. Exposes `thunderid-admin-<block>` to the accessibility tree.
class AdminSection extends StatelessWidget {
  final AdminContext ac;
  final String block;
  final String? title;
  final String? description;
  final List<Widget> actions;
  final List<Widget> children;

  /// Smaller title for a section meant to sit inside a larger page, like React's `h3`.
  final bool nested;

  const AdminSection({
    super.key,
    required this.ac,
    required this.block,
    required this.children,
    this.title,
    this.description,
    this.actions = const [],
    this.nested = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = ac.colors;
    final hasHeader = (title?.isNotEmpty ?? false) || actions.isNotEmpty;
    return Semantics(
      identifier: 'thunderid-admin-$block',
      container: true,
      child: Material(
        type: MaterialType.transparency,
        child: DefaultTextStyle.merge(
          style: TextStyle(color: colors.text, fontSize: 14),
          child: Column(
            key: Key('thunderid-admin-$block'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (hasHeader)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (title?.isNotEmpty ?? false)
                            Semantics(
                              header: true,
                              child: Text(
                                title!,
                                style: TextStyle(
                                  fontSize: nested ? 16 : 20,
                                  fontWeight: FontWeight.w600,
                                  color: colors.text,
                                ),
                              ),
                            ),
                          if (description?.isNotEmpty ?? false)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(description!, style: TextStyle(color: colors.textSecondary)),
                            ),
                        ],
                      ),
                      if (actions.isNotEmpty) Wrap(spacing: 8, runSpacing: 8, children: actions),
                    ],
                  ),
                ),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

/// An error message, announced to assistive technology when it appears.
class AdminAlert extends StatelessWidget {
  final AdminContext ac;
  final String message;
  final String block;

  const AdminAlert({super.key, required this.ac, required this.message, required this.block});

  @override
  Widget build(BuildContext context) => Semantics(
        identifier: 'thunderid-admin-$block-error',
        liveRegion: true,
        child: Container(
          key: Key('thunderid-admin-$block-error'),
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: ac.colors.errorBackground,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: ac.colors.error.withValues(alpha: 0.4)),
          ),
          child: Text(message, style: TextStyle(color: ac.colors.error)),
        ),
      );
}

/// A small spinner with a label.
class AdminLoading extends StatelessWidget {
  final AdminContext ac;

  const AdminLoading({super.key, required this.ac});

  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        label: ac.t('admin.common.loading'),
        child: ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: ac.colors.primary),
                ),
                const SizedBox(width: 8),
                Text(ac.t('admin.common.loading'), style: TextStyle(color: ac.colors.textSecondary)),
              ],
            ),
          ),
        ),
      );
}

/// Muted placeholder text, e.g. an empty-list message.
class AdminMuted extends StatelessWidget {
  final AdminContext ac;
  final String text;

  const AdminMuted({super.key, required this.ac, required this.text});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(text, style: TextStyle(color: ac.colors.textSecondary)),
      );
}

/// An initials avatar for a managed identity, reusing [BaseUserAvatar]'s rendering.
class AdminAvatar extends StatelessWidget {
  final String name;
  final double size;

  const AdminAvatar({super.key, required this.name, this.size = 28});

  @override
  Widget build(BuildContext context) =>
      ExcludeSemantics(child: BaseUserAvatar(user: User({'displayName': name}), size: size));
}

/// One column of an [AdminTable]. The first column is the row's primary label.
class AdminColumn<T> {
  final String header;
  final Widget Function(T row) build;

  const AdminColumn({required this.header, required this.build});
}

/// Pagination state for an [AdminTable].
class AdminPaging {
  final int limit;
  final int offset;
  final int total;
  final ValueChanged<int> onChange;

  const AdminPaging({required this.limit, required this.offset, required this.total, required this.onChange});
}

/// A list of records rendered as stacked rows, which reads on a phone where a wide table
/// would not. Each row exposes `thunderid-admin-<block>-row-<id>`.
class AdminTable<T> extends StatelessWidget {
  final AdminContext ac;
  final String block;
  final List<AdminColumn<T>> columns;
  final List<T> rows;
  final String Function(T row) rowId;
  final bool isLoading;
  final String? error;
  final String emptyText;
  final ValueChanged<T>? onRowTap;
  final String? selectedRowId;
  final Widget Function(T row)? trailing;
  final AdminPaging? paging;

  const AdminTable({
    super.key,
    required this.ac,
    required this.block,
    required this.columns,
    required this.rows,
    required this.rowId,
    required this.emptyText,
    this.isLoading = false,
    this.error,
    this.onRowTap,
    this.selectedRowId,
    this.trailing,
    this.paging,
  });

  @override
  Widget build(BuildContext context) {
    final colors = ac.colors;
    final children = <Widget>[];
    if (error != null) {
      children.add(AdminAlert(ac: ac, message: error!, block: block));
    } else if (isLoading && rows.isEmpty) {
      children.add(AdminLoading(ac: ac));
    } else if (rows.isEmpty) {
      children.add(AdminMuted(ac: ac, text: emptyText));
    }

    for (final row in rows) {
      final id = rowId(row);
      final identifier = 'thunderid-admin-$block-row-$id';
      final selected = id == selectedRowId;
      final content = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DefaultTextStyle.merge(
                    style: TextStyle(fontWeight: FontWeight.w600, color: colors.text, fontSize: 15),
                    child: columns.first.build(row),
                  ),
                  if (columns.length > 1)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Wrap(
                        spacing: 16,
                        runSpacing: 4,
                        children: [
                          for (final column in columns.skip(1))
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${column.header}: ',
                                  style: TextStyle(color: colors.textSecondary, fontSize: 13),
                                ),
                                DefaultTextStyle.merge(
                                  style: TextStyle(color: colors.text, fontSize: 13),
                                  child: column.build(row),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            if (trailing != null) trailing!(row),
          ],
        ),
      );
      children.add(
        Semantics(
          identifier: identifier,
          button: onRowTap != null,
          selected: selected,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: selected ? colors.primary.withValues(alpha: 0.08) : null,
              border: Border(bottom: BorderSide(color: colors.border)),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: onRowTap == null
                  ? KeyedSubtree(key: Key(identifier), child: content)
                  : InkWell(key: Key(identifier), onTap: () => onRowTap!(row), child: content),
            ),
          ),
        ),
      );
    }

    final paging = this.paging;
    if (paging != null && paging.total > paging.limit) {
      children.add(AdminPagination(ac: ac, block: block, paging: paging));
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

/// Previous/next controls with a "1 to 20 of 45" range.
class AdminPagination extends StatelessWidget {
  final AdminContext ac;
  final String block;
  final AdminPaging paging;

  const AdminPagination({super.key, required this.ac, required this.block, required this.paging});

  @override
  Widget build(BuildContext context) {
    final start = paging.total == 0 ? 0 : paging.offset + 1;
    final end = math.min(paging.offset + paging.limit, paging.total);
    final hasPrevious = paging.offset > 0;
    final hasNext = paging.offset + paging.limit < paging.total;
    return Semantics(
      container: true,
      label: ac.t('admin.common.pagination.label'),
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Wrap(
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            Text(
              ac.t('admin.common.pagination.range', {'start': '$start', 'end': '$end', 'total': '${paging.total}'}),
              style: TextStyle(color: ac.colors.textSecondary),
            ),
            AdminButton(
              ac: ac,
              label: ac.t('admin.common.pagination.previous'),
              identifier: 'thunderid-action-$block-previous',
              variant: AdminButtonVariant.text,
              onPressed: hasPrevious ? () => paging.onChange(math.max(0, paging.offset - paging.limit)) : null,
            ),
            AdminButton(
              ac: ac,
              label: ac.t('admin.common.pagination.next'),
              identifier: 'thunderid-action-$block-next',
              variant: AdminButtonVariant.text,
              onPressed: hasNext ? () => paging.onChange(paging.offset + paging.limit) : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// A bordered sub-section with a title.
class AdminPanel extends StatelessWidget {
  final AdminContext ac;
  final String title;
  final Widget child;
  final Widget? action;

  const AdminPanel({super.key, required this.ac, required this.title, required this.child, this.action});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: ac.colors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: ac.colors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      title,
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: ac.colors.text),
                    ),
                  ),
                ),
                if (action != null) action!,
              ],
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      );
}

/// Label/value pairs.
class AdminDetailList extends StatelessWidget {
  final AdminContext ac;
  final List<(String, Widget)> items;

  const AdminDetailList({super.key, required this.ac, required this.items});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (label, value) in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: MergeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: TextStyle(color: ac.colors.textSecondary, fontSize: 13)),
                    DefaultTextStyle.merge(style: TextStyle(color: ac.colors.text), child: value),
                  ],
                ),
              ),
            ),
        ],
      );
}

/// One entry of an [AdminChipList].
class AdminChip {
  final String id;
  final String label;

  const AdminChip({required this.id, required this.label});
}

/// A wrap of labelled chips, or [emptyText] when there are none.
class AdminChipList extends StatelessWidget {
  final AdminContext ac;
  final String label;
  final String emptyText;
  final List<AdminChip> items;

  const AdminChipList({
    super.key,
    required this.ac,
    required this.label,
    required this.emptyText,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return AdminMuted(ac: ac, text: emptyText);
    return Semantics(
      label: label,
      container: true,
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final item in items)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: ac.colors.background,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: ac.colors.border),
              ),
              child: Text(item.label, style: TextStyle(color: ac.colors.text, fontSize: 13)),
            ),
        ],
      ),
    );
  }
}
