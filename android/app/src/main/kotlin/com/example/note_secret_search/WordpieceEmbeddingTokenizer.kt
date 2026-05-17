package com.example.note_secret_search

data class EncodedEmbeddingInput(
    val inputIds: LongArray,
    val attentionMask: LongArray,
    val tokenTypeIds: LongArray,
)

class WordpieceEmbeddingTokenizer(
    private val vocab: Map<String, Int>,
    private val lowercase: Boolean,
    private val maxSequenceLength: Int,
) {
    private val padId = vocab["[PAD]"] ?: 0
    private val unkId = vocab["[UNK]"] ?: 100
    private val clsId = vocab["[CLS]"] ?: 101
    private val sepId = vocab["[SEP]"] ?: 102

    fun encode(text: String): EncodedEmbeddingInput {
        val normalized = if (lowercase) text.lowercase() else text
        val words = normalized.trim().split(Regex("\\s+")).filter { it.isNotBlank() }
        val tokenIds = mutableListOf<Long>()
        tokenIds.add(clsId.toLong())

        for (word in words) {
            tokenIds.addAll(tokenizeWord(word))
        }

        tokenIds.add(sepId.toLong())

        val truncated = tokenIds.take(maxSequenceLength).toMutableList()
        if (truncated.isNotEmpty()) {
            truncated[truncated.lastIndex] = sepId.toLong()
        }

        val attentionMask = MutableList(truncated.size) { 1L }
        while (truncated.size < maxSequenceLength) {
            truncated.add(padId.toLong())
            attentionMask.add(0L)
        }

        return EncodedEmbeddingInput(
            inputIds = truncated.toLongArray(),
            attentionMask = attentionMask.toLongArray(),
            tokenTypeIds = LongArray(maxSequenceLength) { 0L },
        )
    }

    private fun tokenizeWord(word: String): List<Long> {
        if (word.isEmpty()) {
            return emptyList()
        }
        val direct = vocab[word]
        if (direct != null) {
            return listOf(direct.toLong())
        }

        val pieces = mutableListOf<Long>()
        var start = 0
        while (start < word.length) {
            var end = word.length
            var matched: Int? = null
            while (end > start) {
                val candidate = if (start == 0) {
                    word.substring(start, end)
                } else {
                    "##${word.substring(start, end)}"
                }
                val id = vocab[candidate]
                if (id != null) {
                    matched = id
                    break
                }
                end--
            }

            if (matched == null) {
                return listOf(unkId.toLong())
            }

            pieces.add(matched.toLong())
            start = end
        }

        return pieces
    }
}
