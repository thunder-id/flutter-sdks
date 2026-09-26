// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

package dev.thunderid.flutter

import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import dev.thunderid.android.IAMException
import dev.thunderid.android.ThunderIDClient
import dev.thunderid.android.ThunderIDErrorCode
import dev.thunderid.android.management.ApplicationRequest
import dev.thunderid.android.management.CreateAgentRequest
import dev.thunderid.android.management.CreateManagedUserRequest
import dev.thunderid.android.management.UpdateAgentRequest
import dev.thunderid.android.management.UpdateManagedUserRequest

/**
 * Routes `applications.*`, `users.*`, and `agents.*` method channel calls to the native
 * management API. Resources cross the channel as JSON maps, encoded and decoded with Gson,
 * which the native SDK already uses for its models.
 */
internal object ManagementMethodHandler {
    private val gson = Gson()
    private val mapType = object : TypeToken<Map<String, Any?>>() {}.type

    fun handles(method: String): Boolean = method.substringBefore('.') in setOf("applications", "users", "agents")

    suspend fun handle(method: String, args: Map<String, Any?>, client: ThunderIDClient): Any? {
        val id = args["id"] as? String ?: ""
        val limit = (args["limit"] as? Number)?.toInt()
        val offset = (args["offset"] as? Number)?.toInt()
        return when (method) {
            "applications.list" -> encode(client.applications.list(limit, offset))
            "applications.get" -> encode(client.applications.get(id))
            "applications.create" -> encode(client.applications.create(decode<ApplicationRequest>(args)))
            "applications.update" -> encode(client.applications.update(id, decode<ApplicationRequest>(args)))
            "applications.delete" -> client.applications.delete(id).let { null }
            "users.list" -> encode(client.users.list(limit, offset, args["filter"] as? String))
            "users.get" -> encode(client.users.get(id))
            "users.create" -> encode(client.users.create(decode<CreateManagedUserRequest>(args)))
            "users.update" -> encode(client.users.update(id, decode<UpdateManagedUserRequest>(args)))
            "users.delete" -> client.users.delete(id).let { null }
            "agents.list" -> encode(client.agents.list(limit, offset))
            "agents.get" -> encode(client.agents.get(id))
            "agents.create" -> encode(client.agents.create(decode<CreateAgentRequest>(args)))
            "agents.update" -> encode(client.agents.update(id, decode<UpdateAgentRequest>(args)))
            "agents.delete" -> client.agents.delete(id).let { null }
            else -> throw IAMException(ThunderIDErrorCode.UNKNOWN_ERROR, "Unknown method: $method")
        }
    }

    private fun encode(value: Any): Map<String, Any?> = gson.fromJson(gson.toJson(value), mapType)

    private inline fun <reified T> decode(args: Map<String, Any?>): T {
        val payload = args["payload"] ?: throw IAMException(ThunderIDErrorCode.INVALID_INPUT, "A payload is required")
        return gson.fromJson(gson.toJson(payload), T::class.java)
    }
}
