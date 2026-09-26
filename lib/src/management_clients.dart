// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'channel/thunderid_channel.dart';
import 'models/management_models.dart';

Map<String, dynamic> _page({int? limit, int? offset, String? filter}) => {
      if (limit != null) 'limit': limit,
      if (offset != null) 'offset': offset,
      if (filter != null) 'filter': filter,
    };

/// Application management operations, reached through `ThunderIDClient.applications`.
/// Delegates to the native SDK's management API.
class ApplicationsClient {
  final ThunderIDChannel _channel;

  ApplicationsClient(this._channel);

  /// Returns a page of applications.
  Future<ApplicationListResponse> list({int? limit, int? offset}) async => ApplicationListResponse.fromMap(
        await _channel.invokeMap('applications.list', _page(limit: limit, offset: offset)),
      );

  /// Returns a single application.
  Future<Application> get(String id) async =>
      Application.fromMap(await _channel.invokeMap('applications.get', {'id': id}));

  /// Creates an application and returns it as the server stored it.
  Future<Application> create(ApplicationRequest application) async => Application.fromMap(
        await _channel.invokeMap('applications.create', {'payload': application.toMap()}),
      );

  /// Replaces an application's mutable fields and returns the updated application.
  Future<Application> update(String id, ApplicationRequest application) async => Application.fromMap(
        await _channel.invokeMap('applications.update', {'id': id, 'payload': application.toMap()}),
      );

  /// Deletes an application.
  Future<void> delete(String id) => _channel.invoke<void>('applications.delete', {'id': id});
}

/// User management operations, reached through `ThunderIDClient.users`.
/// Delegates to the native SDK's management API.
class UsersClient {
  final ThunderIDChannel _channel;

  UsersClient(this._channel);

  /// Returns a page of users, each with its resolved `display` value.
  Future<ManagedUserListResponse> list({int? limit, int? offset, String? filter}) async =>
      ManagedUserListResponse.fromMap(
        await _channel.invokeMap('users.list', _page(limit: limit, offset: offset, filter: filter)),
      );

  /// Returns a single user, with its resolved `display` value.
  Future<ManagedUser> get(String id) async => ManagedUser.fromMap(await _channel.invokeMap('users.get', {'id': id}));

  /// Creates a user and returns it as the server stored it.
  Future<ManagedUser> create(CreateManagedUserRequest user) async =>
      ManagedUser.fromMap(await _channel.invokeMap('users.create', {'payload': user.toMap()}));

  /// Updates a user and returns the updated user.
  Future<ManagedUser> update(String id, UpdateManagedUserRequest user) async => ManagedUser.fromMap(
        await _channel.invokeMap('users.update', {'id': id, 'payload': user.toMap()}),
      );

  /// Deletes a user.
  Future<void> delete(String id) => _channel.invoke<void>('users.delete', {'id': id});
}

/// Agent management operations, reached through `ThunderIDClient.agents`.
/// Delegates to the native SDK's management API.
class AgentsClient {
  final ThunderIDChannel _channel;

  AgentsClient(this._channel);

  /// Returns a page of agents.
  Future<AgentListResponse> list({int? limit, int? offset}) async => AgentListResponse.fromMap(
        await _channel.invokeMap('agents.list', _page(limit: limit, offset: offset)),
      );

  /// Returns a single agent.
  Future<Agent> get(String id) async => Agent.fromMap(await _channel.invokeMap('agents.get', {'id': id}));

  /// Creates an agent and returns it as the server stored it.
  Future<Agent> create(CreateAgentRequest agent) async =>
      Agent.fromMap(await _channel.invokeMap('agents.create', {'payload': agent.toMap()}));

  /// Updates an agent and returns the updated agent.
  Future<Agent> update(String id, UpdateAgentRequest agent) async =>
      Agent.fromMap(await _channel.invokeMap('agents.update', {'id': id, 'payload': agent.toMap()}));

  /// Deletes an agent.
  Future<void> delete(String id) => _channel.invoke<void>('agents.delete', {'id': id});
}
