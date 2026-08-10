package com.example.note_secret_search

class PreparedEmbeddingSession(
    val identity: SessionIdentity,
    val tokenizer: WordpieceEmbeddingTokenizer,
    val handle: OnnxSessionHandle,
    val contract: ModelIoContract,
) : AutoCloseable {
    private var closed = false

    override fun close() {
        if (!closed) {
            closed = true
            handle.close()
        }
    }
}

class EmbeddingModelSessionManager : AutoCloseable {
    var state: SessionSlotState = SessionSlotState.Empty
        private set

    private var activeSession: PreparedEmbeddingSession? = null

    val currentIdentity: SessionIdentity?
        get() = currentIdentityOrNull()

    fun get(identity: SessionIdentity): PreparedEmbeddingSession? {
        return when (val current = state) {
            is SessionSlotState.Ready -> {
                activeSession?.takeIf { current.identity == identity }
            }
            is SessionSlotState.Running -> {
                activeSession?.takeIf { current.identity == identity }
            }
            SessionSlotState.Empty,
            is SessionSlotState.Loading,
            SessionSlotState.Closing,
            SessionSlotState.Closed,
            -> null
        }
    }

    fun getOrLoad(
        identity: SessionIdentity,
        load: () -> PreparedEmbeddingSession,
    ): PreparedEmbeddingSession {
        ensureOpen(identity.modelId)
        get(identity)?.let { return it }
        releaseCurrent(terminal = false)
        state = SessionSlotState.Loading(identity)
        return try {
            val prepared = load()
            if (prepared.identity != identity) {
                try {
                    prepared.close()
                } catch (closeError: Throwable) {
                    val identityError = IllegalArgumentException(
                        "Prepared embedding session identity does not match the load request.",
                    )
                    identityError.addSuppressed(closeError)
                    throw identityError
                }
                throw IllegalArgumentException(
                    "Prepared embedding session identity does not match the load request.",
                )
            }
            activeSession = prepared
            state = SessionSlotState.Ready(identity)
            prepared
        } catch (error: Throwable) {
            activeSession = null
            state = SessionSlotState.Empty
            throw error
        }
    }

    fun <T> run(
        identity: SessionIdentity,
        requestId: String,
        block: (PreparedEmbeddingSession) -> T,
    ): T {
        ensureOpen(identity.modelId)
        val session = get(identity)
            ?: throw EmbeddingRuntimeException(
                code = EmbeddingRuntimeErrorCode.ORT_FAILURE,
                stage = EmbeddingRuntimeStage.LIFECYCLE,
                modelId = identity.modelId,
            )
        state = SessionSlotState.Running(identity, requestId)
        return try {
            block(session)
        } finally {
            if (state is SessionSlotState.Running) {
                state = SessionSlotState.Ready(identity)
            }
        }
    }

    fun release(modelId: String) {
        val identity = currentIdentityOrNull() ?: return
        if (identity.modelId == modelId) {
            releaseCurrent(terminal = false)
        }
    }

    fun releaseAll() {
        if (state != SessionSlotState.Closed) {
            releaseCurrent(terminal = false)
        }
    }

    override fun close() {
        if (state == SessionSlotState.Closed) {
            return
        }
        releaseCurrent(terminal = true)
    }

    private fun releaseCurrent(terminal: Boolean) {
        val session = activeSession
        activeSession = null
        state = SessionSlotState.Closing
        try {
            session?.close()
        } finally {
            state = if (terminal) {
                SessionSlotState.Closed
            } else {
                SessionSlotState.Empty
            }
        }
    }

    private fun currentIdentityOrNull(): SessionIdentity? {
        return when (val current = state) {
            is SessionSlotState.Loading -> current.identity
            is SessionSlotState.Ready -> current.identity
            is SessionSlotState.Running -> current.identity
            SessionSlotState.Empty,
            SessionSlotState.Closing,
            SessionSlotState.Closed,
            -> null
        }
    }

    private fun ensureOpen(modelId: String) {
        if (state == SessionSlotState.Closed) {
            throw EmbeddingRuntimeException(
                code = EmbeddingRuntimeErrorCode.RUNTIME_CLOSED,
                stage = EmbeddingRuntimeStage.LIFECYCLE,
                modelId = modelId,
            )
        }
    }
}
