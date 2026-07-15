#include <jni.h>

#include <dlfcn.h>

namespace {

using InitContextWithFdFn = jlong (*)(
    JNIEnv *,
    jobject,
    jint,
    jboolean,
    jint,
    jint,
    jint,
    jint,
    jboolean,
    jboolean,
    jboolean,
    jstring,
    jfloat,
    jfloat,
    jfloat);

using LoadModelDetailsFn = jobject (*)(JNIEnv *, jobject, jlong);

using DoCompletionFn = jobject (*)(
    JNIEnv *,
    jobject,
    jlong,
    jstring,
    jstring,
    jfloat,
    jint,
    jint,
    jint,
    jint,
    jfloat,
    jfloat,
    jfloat,
    jfloat,
    jfloat,
    jfloat,
    jboolean,
    jint,
    jfloat,
    jfloat,
    jfloat,
    jfloat,
    jfloat,
    jfloat,
    jint,
    jobjectArray,
    jboolean,
    jobjectArray,
    jobject);

using StopCompletionFn = void (*)(JNIEnv *, jobject, jlong);
using FreeContextFn = void (*)(JNIEnv *, jobject, jlong);

void *rnllama_handle = nullptr;
InitContextWithFdFn init_context_with_fd = nullptr;
LoadModelDetailsFn load_model_details = nullptr;
DoCompletionFn do_completion = nullptr;
StopCompletionFn stop_completion = nullptr;
FreeContextFn free_context = nullptr;

constexpr char kInitContextWithFdSymbol[] =
    "Java_org_nehuatl_llamacpp_LlamaContext_initContextWithFd";
constexpr char kLoadModelDetailsSymbol[] =
    "Java_org_nehuatl_llamacpp_LlamaContext_loadModelDetails";
constexpr char kDoCompletionSymbol[] =
    "Java_org_nehuatl_llamacpp_LlamaContext_doCompletion";
constexpr char kStopCompletionSymbol[] =
    "Java_org_nehuatl_llamacpp_LlamaContext_stopCompletion";
constexpr char kFreeContextSymbol[] =
    "Java_org_nehuatl_llamacpp_LlamaContext_freeContext";

void throw_unsatisfied_link_error(JNIEnv *env, const char *message) {
    if (env->ExceptionCheck()) {
        return;
    }
    jclass error_class = env->FindClass("java/lang/UnsatisfiedLinkError");
    if (error_class != nullptr) {
        env->ThrowNew(error_class, message);
    }
}

template <typename Function>
Function resolve_symbol(void *handle, const char *symbol) {
    return reinterpret_cast<Function>(dlsym(handle, symbol));
}

bool bridge_is_ready(JNIEnv *env) {
    if (rnllama_handle != nullptr &&
        init_context_with_fd != nullptr &&
        load_model_details != nullptr &&
        do_completion != nullptr &&
        stop_completion != nullptr &&
        free_context != nullptr) {
        return true;
    }
    throw_unsatisfied_link_error(
        env,
        "The selected rnllama library is not initialized.");
    return false;
}

}  // namespace

extern "C" JNIEXPORT void JNICALL
Java_com_example_nssllama_SilentLlamaNativeLoader_loadRnLlamaLibrary(
    JNIEnv *env,
    jobject,
    jstring library_name) {
    if (rnllama_handle != nullptr) {
        return;
    }

    const char *name = env->GetStringUTFChars(library_name, nullptr);
    if (name == nullptr) {
        return;
    }
    void *handle = dlopen(name, RTLD_NOW | RTLD_LOCAL);
    env->ReleaseStringUTFChars(library_name, name);

    if (handle == nullptr) {
        throw_unsatisfied_link_error(
            env,
            "The selected rnllama library could not be loaded.");
        return;
    }

    const auto resolved_init_context_with_fd =
        resolve_symbol<InitContextWithFdFn>(
            handle,
            kInitContextWithFdSymbol);
    const auto resolved_load_model_details =
        resolve_symbol<LoadModelDetailsFn>(
            handle,
            kLoadModelDetailsSymbol);
    const auto resolved_do_completion =
        resolve_symbol<DoCompletionFn>(
            handle,
            kDoCompletionSymbol);
    const auto resolved_stop_completion =
        resolve_symbol<StopCompletionFn>(
            handle,
            kStopCompletionSymbol);
    const auto resolved_free_context =
        resolve_symbol<FreeContextFn>(
            handle,
            kFreeContextSymbol);

    if (resolved_init_context_with_fd == nullptr ||
        resolved_load_model_details == nullptr ||
        resolved_do_completion == nullptr ||
        resolved_stop_completion == nullptr ||
        resolved_free_context == nullptr) {
        dlclose(handle);
        throw_unsatisfied_link_error(
            env,
            "The selected rnllama library is missing required symbols.");
        return;
    }

    init_context_with_fd = resolved_init_context_with_fd;
    load_model_details = resolved_load_model_details;
    do_completion = resolved_do_completion;
    stop_completion = resolved_stop_completion;
    free_context = resolved_free_context;
    rnllama_handle = handle;
}

extern "C" JNIEXPORT jlong JNICALL
Java_com_example_nssllama_SilentLlamaContext_initContextWithFd(
    JNIEnv *env,
    jobject context,
    jint model_fd,
    jboolean embedding,
    jint context_size,
    jint batch_size,
    jint thread_count,
    jint gpu_layer_count,
    jboolean use_mlock,
    jboolean use_mmap,
    jboolean vocab_only,
    jstring lora_path,
    jfloat lora_scale,
    jfloat rope_frequency_base,
    jfloat rope_frequency_scale) {
    if (!bridge_is_ready(env)) {
        return 0;
    }
    return init_context_with_fd(
        env,
        context,
        model_fd,
        embedding,
        context_size,
        batch_size,
        thread_count,
        gpu_layer_count,
        use_mlock,
        use_mmap,
        vocab_only,
        lora_path,
        lora_scale,
        rope_frequency_base,
        rope_frequency_scale);
}

extern "C" JNIEXPORT jobject JNICALL
Java_com_example_nssllama_SilentLlamaContext_loadModelDetails(
    JNIEnv *env,
    jobject context,
    jlong native_context) {
    if (!bridge_is_ready(env)) {
        return nullptr;
    }
    return load_model_details(env, context, native_context);
}

extern "C" JNIEXPORT jobject JNICALL
Java_com_example_nssllama_SilentLlamaContext_doCompletion(
    JNIEnv *env,
    jobject context,
    jlong native_context,
    jstring prompt,
    jstring grammar,
    jfloat temperature,
    jint thread_count,
    jint prediction_count,
    jint probability_count,
    jint penalty_last_n,
    jfloat penalty_repeat,
    jfloat penalty_frequency,
    jfloat penalty_presence,
    jfloat mirostat,
    jfloat mirostat_tau,
    jfloat mirostat_eta,
    jboolean penalize_newline,
    jint top_k,
    jfloat top_p,
    jfloat min_p,
    jfloat xtc_threshold,
    jfloat xtc_probability,
    jfloat tail_free_sampling_z,
    jfloat typical_p,
    jint seed,
    jobjectArray stop,
    jboolean ignore_eos,
    jobjectArray logit_bias,
    jobject callback) {
    if (!bridge_is_ready(env)) {
        return nullptr;
    }
    return do_completion(
        env,
        context,
        native_context,
        prompt,
        grammar,
        temperature,
        thread_count,
        prediction_count,
        probability_count,
        penalty_last_n,
        penalty_repeat,
        penalty_frequency,
        penalty_presence,
        mirostat,
        mirostat_tau,
        mirostat_eta,
        penalize_newline,
        top_k,
        top_p,
        min_p,
        xtc_threshold,
        xtc_probability,
        tail_free_sampling_z,
        typical_p,
        seed,
        stop,
        ignore_eos,
        logit_bias,
        callback);
}

extern "C" JNIEXPORT void JNICALL
Java_com_example_nssllama_SilentLlamaContext_stopCompletion(
    JNIEnv *env,
    jobject context,
    jlong native_context) {
    if (!bridge_is_ready(env)) {
        return;
    }
    stop_completion(env, context, native_context);
}

extern "C" JNIEXPORT void JNICALL
Java_com_example_nssllama_SilentLlamaContext_freeContext(
    JNIEnv *env,
    jobject context,
    jlong native_context) {
    if (!bridge_is_ready(env)) {
        return;
    }
    free_context(env, context, native_context);
}
