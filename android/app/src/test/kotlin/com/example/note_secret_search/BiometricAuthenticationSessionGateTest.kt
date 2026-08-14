package com.example.note_secret_search

import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class BiometricAuthenticationSessionGateTest {
    @Test
    fun `a second authentication is busy until the active session completes`() {
        val gate = BiometricAuthenticationSessionGate()
        val first = gate.begin(operationId = 11)

        val second = gate.begin(operationId = 12)

        assertNotNull(first)
        assertNull(second)
        assertTrue(gate.complete(first!!))
        assertNotNull(gate.begin(operationId = 12))
    }

    @Test
    fun `an old session completion cannot clear a newer session`() {
        val gate = BiometricAuthenticationSessionGate()
        val first = gate.begin(operationId = 21)!!
        assertTrue(gate.cancel(operationId = 21))
        val second = gate.begin(operationId = 22)!!

        assertFalse(gate.complete(first))
        assertTrue(gate.complete(second))
    }

    @Test
    fun `cancellation only revokes the matching operation`() {
        val gate = BiometricAuthenticationSessionGate()
        var cancellations = 0
        val active = gate.begin(operationId = 31) { cancellations += 1 }!!

        assertFalse(gate.cancel(operationId = 30))
        assertTrue(cancellations == 0)
        assertTrue(gate.cancel(operationId = 31))
        assertTrue(cancellations == 1)
        assertFalse(gate.complete(active))
    }

    @Test
    fun `platform cancellation failure still notifies and releases the session`() {
        val gate = BiometricAuthenticationSessionGate()
        var cancellations = 0
        gate.begin(operationId = 41) { cancellations += 1 }

        val cancelled = gate.cancel(operationId = 41) {
            throw IllegalStateException("prompt already detached")
        }

        assertTrue(cancelled)
        assertTrue(cancellations == 1)
        assertNotNull(gate.begin(operationId = 42))
    }

    @Test
    fun `stale session cancellation cannot revoke a replacement session`() {
        val gate = BiometricAuthenticationSessionGate()
        var cancellations = 0
        val first = gate.begin(operationId = 51) { cancellations += 1 }!!
        assertTrue(gate.cancelSession(first))
        val second = gate.begin(operationId = 52)!!

        assertFalse(gate.cancelSession(first))
        assertTrue(gate.isActive(second))
        assertTrue(gate.cancelSession(second))
        assertTrue(cancellations == 1)
    }
}
