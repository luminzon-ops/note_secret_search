package com.example.note_secret_search

import android.content.Context
import android.os.ParcelFileDescriptor
import com.example.nssllama.SilentLlamaContext
import kotlinx.coroutines.flow.MutableSharedFlow
import java.io.File
import java.util.concurrent.atomic.AtomicInteger

internal const val FIXED_LOGICAL_MODEL_NAME = "local-model.gguf"

internal sealed interface LlamaRuntimeEvent {
    data class Ongoing(val text: String) : LlamaRuntimeEvent

    data class Done(val text: String) : LlamaRuntimeEvent

    data class Error(val message: String) : LlamaRuntimeEvent
}

internal interface LlamaContextClient {
    fun load(file: File, contextLength: Int, onLoaded: (Long) -> Unit)

    fun predict(
        prompt: String,
        emitPartialCompletion: Boolean,
        maxTokens: Int,
        config: LocalLlmGenerationConfig,
    )

    fun abort()

    fun release()
}

internal fun interface LlamaModelDescriptorOpener {
    fun open(file: File): LlamaModelDescriptor
}

internal interface LlamaModelDescriptor {
    val fd: Int

    fun close()
}

internal fun interface LlamaNativeContextFactory {
    fun create(contextId: Int, params: Map<String, Any>): LlamaNativeContext
}

internal interface LlamaNativeContext {
    fun setTokenCallback(callback: (String) -> Unit)

    fun completion(params: Map<String, Any>): Map<String, Any?>

    fun stopCompletion()

    fun release()
}

internal class DirectLlamaContextClient(
    private val descriptorOpener: LlamaModelDescriptorOpener,
    private val contextFactory: LlamaNativeContextFactory,
    private val events: MutableSharedFlow<LlamaRuntimeEvent>,
) : LlamaContextClient {
    constructor(
        context: Context,
        events: MutableSharedFlow<LlamaRuntimeEvent>,
    ) : this(
        descriptorOpener = LlamaModelDescriptorOpener { file ->
            AndroidLlamaModelDescriptor(
                ParcelFileDescriptor.open(
                    file,
                    ParcelFileDescriptor.MODE_READ_ONLY,
                ),
            )
        },
        contextFactory = LlamaNativeContextFactory { contextId, params ->
            AndroidLlamaNativeContext(SilentLlamaContext(contextId, params))
        },
        events = events,
    )

    private val lock = Any()
    private var descriptor: LlamaModelDescriptor? = null
    private var nativeContext: LlamaNativeContext? = null

    override fun load(
        file: File,
        contextLength: Int,
        onLoaded: (Long) -> Unit,
    ) {
        release()
        val openedDescriptor = descriptorOpener.open(file)
        val contextId = NEXT_CONTEXT_ID.getAndIncrement()
        val params = mapOf<String, Any>(
            "model" to FIXED_LOGICAL_MODEL_NAME,
            "model_fd" to openedDescriptor.fd,
            "use_mmap" to false,
            "use_mlock" to false,
            "n_ctx" to contextLength,
        )
        val createdContext = try {
            contextFactory.create(contextId, params)
        } catch (error: Throwable) {
            openedDescriptor.close()
            throw error
        }
        createdContext.setTokenCallback { token ->
            events.tryEmit(LlamaRuntimeEvent.Ongoing(token))
        }
        synchronized(lock) {
            descriptor = openedDescriptor
            nativeContext = createdContext
        }
        onLoaded(contextId.toLong())
    }

    override fun predict(
        prompt: String,
        emitPartialCompletion: Boolean,
        maxTokens: Int,
        config: LocalLlmGenerationConfig,
    ) {
        val context = synchronized(lock) { nativeContext }
            ?: throw IllegalStateException("Local LLM context is not loaded.")
        context.setTokenCallback { token ->
            if (emitPartialCompletion) {
                events.tryEmit(LlamaRuntimeEvent.Ongoing(token))
            }
        }
        val params = mapOf<String, Any>(
            "prompt" to prompt,
            "emit_partial_completion" to emitPartialCompletion,
            "n_predict" to maxTokens,
            "temperature" to config.temperature,
            "top_k" to config.topK,
            "top_p" to config.topP,
            "seed" to config.seed,
            "stop" to config.stopSequences,
        )
        try {
            val result = context.completion(params)
            val text = (result["text"] as? String).orEmpty()
            events.tryEmit(LlamaRuntimeEvent.Done(text))
        } catch (_: Throwable) {
            events.tryEmit(
                LlamaRuntimeEvent.Error("Local LLM completion failed."),
            )
        }
    }

    override fun abort() {
        val context = synchronized(lock) { nativeContext } ?: return
        try {
            context.stopCompletion()
        } catch (_: Throwable) {
        }
    }

    override fun release() {
        val context: LlamaNativeContext?
        val openedDescriptor: LlamaModelDescriptor?
        synchronized(lock) {
            context = nativeContext
            openedDescriptor = descriptor
            nativeContext = null
            descriptor = null
        }
        try {
            context?.release()
        } finally {
            openedDescriptor?.close()
        }
    }

    companion object {
        private val NEXT_CONTEXT_ID = AtomicInteger(1)
    }
}

private class AndroidLlamaModelDescriptor(
    private val delegate: ParcelFileDescriptor,
) : LlamaModelDescriptor {
    override val fd: Int
        get() = delegate.fd

    override fun close() {
        delegate.close()
    }
}

private class AndroidLlamaNativeContext(
    private val delegate: SilentLlamaContext,
) : LlamaNativeContext {
    override fun setTokenCallback(callback: (String) -> Unit) {
        delegate.setTokenCallback(callback)
    }

    override fun completion(params: Map<String, Any>): Map<String, Any?> {
        return delegate.completion(params)
    }

    override fun stopCompletion() {
        delegate.stopCompletion()
    }

    override fun release() {
        delegate.release()
    }
}
