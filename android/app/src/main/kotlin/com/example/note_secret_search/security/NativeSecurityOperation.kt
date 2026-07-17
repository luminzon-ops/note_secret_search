package com.example.note_secret_search.security

internal class CompletingResult<T>(
    override val operationId: Long,
    private val delegate: NativeResult<T>,
    private val complete: (
        CompletingResult<T>,
        () -> Unit,
    ) -> CompletionOutcome,
    private val isActive: (CompletingResult<T>) -> Boolean,
    private val registerCleanupDelegate: (
        CompletingResult<T>,
        () -> Unit,
    ) -> Boolean,
    private val runIfActiveDelegate: (CompletingResult<T>, () -> Unit) -> Boolean,
) : NativeResult<T>, OperationAwareResult {
    private val cancellationCleanups = mutableListOf<() -> Unit>()

    override fun isActiveOperation(): Boolean = isActive(this)

    override fun registerCancellationCleanup(cleanup: () -> Unit): Boolean {
        return registerCleanupDelegate(this, cleanup)
    }

    override fun runIfActive(operation: () -> Unit): Boolean {
        return runIfActiveDelegate(this, operation)
    }

    override fun success(value: T) {
        val outcome = complete(this) {
            delegate.success(value)
        }
        if (outcome != CompletionOutcome.DELIVERED &&
            value is NativeUnlockMaterial
        ) {
            value.zeroize()
        }
    }

    override fun error(error: NativeSecurityException) {
        complete(this) {
            delegate.error(error)
        }
    }

    fun cancelLocked() {
        val cleanups = cancellationCleanups.toList()
        cancellationCleanups.clear()
        cleanups.forEach { cleanup ->
            try {
                cleanup()
            } catch (_: Throwable) {
                // Continue clearing the remaining operation-owned material.
            }
        }
        try {
            delegate.error(NativeSecurityException(
                NativeSecurityErrorCode.AUTH_CANCELLED,
            ))
        } catch (_: Throwable) {
            // Transport failures must not skip prompt cancellation.
        }
    }

    fun addCancellationCleanup(cleanup: () -> Unit) {
        cancellationCleanups += cleanup
    }

    fun discardCancellationCleanups() {
        cancellationCleanups.clear()
    }
}

internal enum class CompletionOutcome {
    INACTIVE,
    DELIVERED,
    DELIVERY_FAILED,
}

internal interface OperationAwareResult {
    val operationId: Long

    fun isActiveOperation(): Boolean

    fun registerCancellationCleanup(cleanup: () -> Unit): Boolean

    fun runIfActive(operation: () -> Unit): Boolean
}

internal fun NativeResult<*>.isActiveOperation(): Boolean {
    return (this as? OperationAwareResult)?.isActiveOperation() ?: true
}

internal fun NativeResult<*>.operationId(): Long {
    return (this as? OperationAwareResult)?.operationId ?: 0
}

internal fun NativeResult<*>.registerCancellationCleanup(
    cleanup: () -> Unit,
): Boolean {
    return (this as? OperationAwareResult)
        ?.registerCancellationCleanup(cleanup)
        ?: true
}

internal fun NativeResult<*>.runIfActive(operation: () -> Unit): Boolean {
    return (this as? OperationAwareResult)?.runIfActive(operation)
        ?: run {
            operation()
            true
        }
}
