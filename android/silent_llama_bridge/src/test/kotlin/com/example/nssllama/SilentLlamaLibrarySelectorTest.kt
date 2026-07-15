package com.example.nssllama

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class SilentLlamaLibrarySelectorTest {
    @Test
    fun `selects armv8_4 i8mm library when every required feature is present`() {
        assertEquals(
            "librnllama_v8_4_fp16_dotprod_i8mm.so",
            selectSilentRnLlamaLibrary(
                primaryAbi = "arm64-v8a",
                cpuFeatures = "fp asimd aes crc32 fphp asimddp dcpop uscat i8mm",
            ),
        )
    }

    @Test
    fun `selects Huawei-safe dot-product library without logging device features`() {
        assertEquals(
            "librnllama_v8_2_fp16_dotprod.so",
            selectSilentRnLlamaLibrary(
                primaryAbi = "arm64-v8a",
                cpuFeatures = "fp asimd aes crc32 fphp asimddp dcpop",
            ),
        )
    }

    @Test
    fun `selects fp16 library without dot-product support`() {
        assertEquals(
            "librnllama_v8_2_fp16.so",
            selectSilentRnLlamaLibrary(
                primaryAbi = "arm64-v8a",
                cpuFeatures = "fp asimd aes crc32 fp16",
            ),
        )
    }

    @Test
    fun `selects libraries without case sensitivity`() {
        assertEquals(
            "librnllama_v8_4_fp16_dotprod_i8mm.so",
            selectSilentRnLlamaLibrary(
                primaryAbi = "ARM64-V8A",
                cpuFeatures = "FP ASIMD AES CRC32 FPHP ASIMDDP DCPOP USCAT I8MM",
            ),
        )
    }

    @Test
    fun `falls back to armv8 library when optional features are absent`() {
        assertEquals(
            "librnllama_v8.so",
            selectSilentRnLlamaLibrary(
                primaryAbi = "arm64-v8a",
                cpuFeatures = "fp asimd",
            ),
        )
    }

    @Test
    fun `rejects unsupported ABIs`() {
        assertNull(
            selectSilentRnLlamaLibrary(
                primaryAbi = "x86_64",
                cpuFeatures = "",
            ),
        )
    }
}
