package com.example.note_secret_search

import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Test

class RecentTaskShieldCoordinatorTest {
    @Test
    fun `attachIfNeeded attaches lazily created shield exactly once`() {
        var createCount = 0
        val attached = mutableListOf<Any>()
        val coordinator = RecentTaskShieldCoordinator(
            create = {
                createCount += 1
                Any()
            },
            attach = { attached += it },
        )

        val shield = coordinator.shield()

        coordinator.attachIfNeeded()
        coordinator.attachIfNeeded()

        assertEquals(1, createCount)
        assertEquals(1, attached.size)
        assertSame(shield, attached.single())
    }

    @Test
    fun `attachIfNeeded creates shield when configure path has not requested it yet`() {
        var createCount = 0
        val attached = mutableListOf<Any>()
        val coordinator = RecentTaskShieldCoordinator(
            create = {
                createCount += 1
                Any()
            },
            attach = { attached += it },
        )

        coordinator.attachIfNeeded()
        val shield = coordinator.shield()

        assertEquals(1, createCount)
        assertEquals(1, attached.size)
        assertSame(shield, attached.single())
    }
}
