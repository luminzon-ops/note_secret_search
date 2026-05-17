package com.example.note_secret_search

internal class RecentTaskShieldCoordinator<T>(
    private val create: () -> T,
    private val attach: (T) -> Unit,
) {
    private var shield: T? = null
    private var attached = false

    fun shield(): T {
        return shield ?: create().also { created ->
            shield = created
        }
    }

    fun attachIfNeeded() {
        if (attached) {
            return
        }

        attach(shield())
        attached = true
    }
}
