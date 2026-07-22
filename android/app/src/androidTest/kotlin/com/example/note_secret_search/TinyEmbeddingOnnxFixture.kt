package com.example.note_secret_search

import android.util.Base64
import java.io.File

internal object TinyEmbeddingOnnxFixture {
    fun writeTo(file: File): File {
        file.parentFile?.mkdirs()
        file.writeBytes(Base64.decode(MODEL_BASE64, Base64.DEFAULT))
        return file
    }

    private const val MODEL_BASE64 =
        "CAgSH25vdGUtc2VjcmV0LXNlYXJjaC10ZXN0LWZpeHR1cmU6wgUKJwoJaW5wdXRfaWRz" +
            "EglpZHNfZmxvYXQiBENhc3QqCQoCdG8YAaABAgotCg5hdHRlbnRpb25fbWFzaxIKbWFz" +
            "a19mbG9hdCIEQ2FzdCoJCgJ0bxgBoAECCi0KDnRva2VuX3R5cGVfaWRzEgp0eXBlX2Zs" +
            "b2F0IgRDYXN0KgkKAnRvGAGgAQIKLAoKbWFza19mbG9hdAoKdHlwZV9mbG9hdBINbWFz" +
            "a190eXBlX3N1bSIDQWRkCicKDW1hc2tfdHlwZV9zdW0KBHplcm8SC3VudXNlZF96ZXJv" +
            "IgNNdWwKLgoJaWRzX2Zsb2F0Cgt1bnVzZWRfemVybxIPZmlyc3RfY29tcG9uZW50IgNB" +
            "ZGQKLQoPZmlyc3RfY29tcG9uZW50CgNvbmUSEHNlY29uZF9jb21wb25lbnQiA0FkZAos" +
            "Cg9maXJzdF9jb21wb25lbnQKBGF4ZXMSCGZpcnN0XzNkIglVbnNxdWVlemUKLgoQc2Vj" +
            "b25kX2NvbXBvbmVudAoEYXhlcxIJc2Vjb25kXzNkIglVbnNxdWVlemUKPQoIZmlyc3Rf" +
            "M2QKCXNlY29uZF8zZBIRbGFzdF9oaWRkZW5fc3RhdGUiBkNvbmNhdCoLCgRheGlzGAKg" +
            "AQISDnRpbnlfZW1iZWRkaW5nKg4QASIEAAAAAEIEemVybyoNEAEiBAAAgD9CA29uZSoN" +
            "CAEQBzoBAkIEYXhlc1ojCglpbnB1dF9pZHMSFgoUCAcSEAoCCAEKChIIc2VxdWVuY2Va" +
            "KAoOYXR0ZW50aW9uX21hc2sSFgoUCAcSEAoCCAEKChIIc2VxdWVuY2VaKAoOdG9rZW5f" +
            "dHlwZV9pZHMSFgoUCAcSEAoCCAEKChIIc2VxdWVuY2ViLwoRbGFzdF9oaWRkZW5fc3Rh" +
            "dGUSGgoYCAESFAoCCAEKChIIc2VxdWVuY2UKAggCQgQKABAN"
}
