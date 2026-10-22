// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';

import '../../management/management_display.dart';
import '../../management/management_filter.dart';
import '../../models/management/managed_user.dart';
import '../../models/management/management_page.dart';
import '../../models/preferences.dart';
import '../../state/management_resources.dart';
import '../../state/resource_notifiers.dart';
import 'admin_render_state.dart';
import 'identity_candidate.dart';
import 'internal/admin_connected.dart';
import 'internal/admin_context.dart';
import 'internal/admin_parts.dart';
import 'internal/admin_search_bar.dart';

/// Presentational user list: renders [users] and reports selection and paging. Supply the
/// data yourself, or use [UserList] to have it fetched.
///
/// Renders no navigation; [onSelect] hands the chosen user to the application, which decides
/// where to go (spec "UI", requirement 6).
class BaseUserList extends StatelessWidget {
  final List<ManagedUser> users;
  final bool isLoading;

  /// An already-translated error message. Never pass the server's text here.
  final String? error;
  final int limit;
  final int offset;
  final int? totalResults;
  final ValueChanged<int>? onPageChange;
  final ValueChanged<ManagedUser>? onSelect;
  final String? selectedUserId;
  final String? title;
  final String? description;
  final List<Widget> actions;
  final ThunderIDPreferences? preferences;

  /// The search currently applied, if any. While set, an empty page says nothing matched.
  final AdminSearch? search;

  /// The attributes that can be searched, with translated labels.
  final List<AdminSelectOption> searchAttributes;

  /// Applies a search on the server, or clears it with `null`. The search form shows only when this
  /// and [searchAttributes] are set.
  final ValueChanged<AdminSearch?>? onSearch;

  /// Builds custom UI in place of the default list, from the users, the loading and error state, and the paging and selection callbacks.
  final AdminWidgetBuilder<AdminListState<ManagedUser>>? builder;

  const BaseUserList({
    super.key,
    required this.users,
    this.isLoading = false,
    this.error,
    this.limit = 20,
    this.offset = 0,
    this.totalResults,
    this.onPageChange,
    this.onSelect,
    this.selectedUserId,
    this.title,
    this.description,
    this.actions = const [],
    this.preferences,
    this.search,
    this.searchAttributes = const [],
    this.onSearch,
    this.builder,
  });

  @override
  Widget build(BuildContext context) {
    final builder = this.builder;
    if (builder != null) {
      return builder(
        context,
        AdminListState(
          rows: users,
          isLoading: isLoading,
          error: error,
          limit: limit,
          offset: offset,
          totalResults: totalResults ?? users.length,
          selectedId: selectedUserId,
          onPageChange: onPageChange,
          onSelect: onSelect,
          search: search,
          searchAttributes: searchAttributes,
          onSearch: onSearch,
        ),
      );
    }
    final ac = AdminContext.of(context, preferences);
    String name(ManagedUser user) =>
        resolveManagedIdentityName(id: user.id, display: user.display, attributes: user.attributes);
    return AdminSection(
      ac: ac,
      block: 'user-list',
      title: title ?? ac.t('admin.users.list.title'),
      description: description,
      actions: actions,
      children: [
        if (onSearch != null && searchAttributes.isNotEmpty)
          AdminSearchBar(
            ac: ac,
            block: 'user-list',
            attributes: searchAttributes,
            search: search,
            onSearch: onSearch!,
          ),
        AdminTable<ManagedUser>(
          ac: ac,
          block: 'user-list',
          rows: users,
          rowId: (user) => user.id,
          isLoading: isLoading,
          error: error,
          emptyText: search == null
              ? ac.t('admin.users.list.empty')
              : ac.t('admin.common.search.no_results', {'value': search!.value}),
          onRowTap: onSelect,
          selectedRowId: selectedUserId,
          paging: onPageChange == null
              ? null
              : AdminPaging(
                  limit: limit,
                  offset: offset,
                  total: totalResults ?? users.length,
                  onChange: onPageChange!,
                ),
          columns: [
            AdminColumn(
              header: ac.t('admin.users.list.columns.name'),
              build: (user) => Row(
                children: [
                  AdminAvatar(name: name(user)),
                  const SizedBox(width: 10),
                  Flexible(child: Text(name(user), overflow: TextOverflow.ellipsis)),
                ],
              ),
            ),
            AdminColumn(header: ac.t('admin.users.list.columns.type'), build: (user) => Text(user.type)),
            AdminColumn(
              header: ac.t('admin.common.columns.organization_unit'),
              build: (user) => Text(user.ouHandle ?? user.ouId),
            ),
          ],
        ),
      ],
    );
  }
}

/// User list that fetches its own pages through the management API.
class UserList extends StatefulWidget {
  /// A server-side filter expression, passed through as `filter`.
  final String? filter;
  final int limit;
  final ValueChanged<ManagedUser>? onSelect;
  final String? selectedUserId;
  final String? title;
  final String? description;
  final List<Widget> actions;
  final ThunderIDPreferences? preferences;

  /// Whether to show a search form. The server matches the whole value of the chosen attribute.
  final bool searchable;

  /// The attributes to offer in the search form. Defaults to the list's own.
  final List<AdminSelectOption>? searchAttributes;

  /// Builds custom UI in place of the default list. See [BaseUserList.builder].
  final AdminWidgetBuilder<AdminListState<ManagedUser>>? builder;

  const UserList({
    super.key,
    this.filter,
    this.limit = 20,
    this.onSelect,
    this.selectedUserId,
    this.title,
    this.description,
    this.actions = const [],
    this.preferences,
    this.searchable = true,
    this.searchAttributes,
    this.builder,
  });

  @override
  State<UserList> createState() => _UserListState();
}

class _UserListState extends AdminConnectedState<UserList> {
  int _offset = 0;
  AdminSearch? _search;
  ResourceQuery<ManagementPage<ManagedUser>>? _users;

  @override
  void bind(ManagementResources resources) {
    _users = own(resources.usersQuery(filter: widget.filter ?? _searchFilter, limit: widget.limit, offset: _offset));
  }

  @override
  void didUpdateWidget(UserList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filter != widget.filter || oldWidget.limit != widget.limit) {
      _offset = 0;
      rebind();
    }
  }

  String? get _searchFilter {
    final search = _search;
    return search == null ? null : ManagementFilter.equality(search.attribute, search.value);
  }

  void _applySearch(AdminSearch? search) {
    setState(() {
      _search = search;
      _offset = 0;
    });
    rebind();
  }

  void _changePage(int offset) {
    setState(() => _offset = offset);
    rebind();
  }

  @override
  Widget build(BuildContext context) {
    final ac = AdminContext.of(context, widget.preferences);
    final query = _users;
    return BaseUserList(
      users: query?.data?.items ?? const [],
      totalResults: query?.data?.totalResults,
      isLoading: query?.isLoading ?? !providerFailed,
      error: providerFailed
          ? ac.t('admin.users.list.error')
          : toManagementErrorMessage(ac.t, query?.error, 'admin.users.list.error'),
      limit: widget.limit,
      offset: _offset,
      onPageChange: _changePage,
      onSelect: widget.onSelect,
      selectedUserId: widget.selectedUserId,
      title: widget.title,
      description: widget.description,
      actions: widget.actions,
      search: _search,
      searchAttributes: widget.searchAttributes ??
          [
            AdminSelectOption(value: 'username', label: ac.t('admin.users.list.search.username')),
            AdminSelectOption(value: 'email', label: ac.t('admin.users.list.search.email')),
          ],
      onSearch: widget.searchable && widget.filter == null ? _applySearch : null,
      preferences: widget.preferences,
      builder: widget.builder,
    );
  }
}
