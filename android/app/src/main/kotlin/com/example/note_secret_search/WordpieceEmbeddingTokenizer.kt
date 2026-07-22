package com.example.note_secret_search

import java.text.Normalizer
import java.util.Locale

data class EncodedEmbeddingInput(
    val inputIds: LongArray,
    val attentionMask: LongArray,
    val tokenTypeIds: LongArray,
)

class WordpieceEmbeddingTokenizer(
    private val definition: TokenizerDefinition,
    private val maxSequenceLength: Int,
) {
    constructor(
        vocab: Map<String, Int>,
        lowercase: Boolean,
        maxSequenceLength: Int,
    ) : this(
        definition = TokenizerDefinition.legacy(vocab, lowercase),
        maxSequenceLength = maxSequenceLength,
    )

    init {
        require(maxSequenceLength >= 2) {
            "TOKENIZER_SCHEMA_UNSUPPORTED: max sequence length must be at least 2"
        }
    }

    fun encode(
        text: String,
        padToLength: Int? = maxSequenceLength,
    ): EncodedEmbeddingInput {
        val sequenceLimit = padToLength ?: maxSequenceLength
        require(sequenceLimit in 2..maxSequenceLength) {
            "TOKENIZER_SCHEMA_UNSUPPORTED: invalid target sequence length"
        }

        val sequenceIds = tokenizeSequence(text)
        val specialCount = definition.singleTemplate.sumOf { part ->
            when (part) {
                is TokenizerTemplatePart.Sequence -> 0
                is TokenizerTemplatePart.SpecialToken -> part.ids.size
            }
        }
        val sequenceCapacity = sequenceLimit - specialCount
        require(sequenceCapacity >= 0) {
            "TOKENIZER_SCHEMA_UNSUPPORTED: template exceeds sequence length"
        }
        val truncatedSequence = sequenceIds.take(sequenceCapacity)
        val tokenIds = mutableListOf<Long>()
        val tokenTypeIds = mutableListOf<Long>()
        definition.singleTemplate.forEach { part ->
            when (part) {
                is TokenizerTemplatePart.SpecialToken -> {
                    part.ids.forEach { id ->
                        tokenIds.add(id)
                        tokenTypeIds.add(part.typeId)
                    }
                }

                is TokenizerTemplatePart.Sequence -> {
                    truncatedSequence.forEach { id ->
                        tokenIds.add(id)
                        tokenTypeIds.add(part.typeId)
                    }
                }
            }
        }

        val attentionMask = MutableList(tokenIds.size) { 1L }
        val targetLength = padToLength
        while (targetLength != null && tokenIds.size < targetLength) {
            tokenIds.add(definition.padTokenId.toLong())
            attentionMask.add(0L)
            tokenTypeIds.add(0L)
        }

        return EncodedEmbeddingInput(
            inputIds = tokenIds.toLongArray(),
            attentionMask = attentionMask.toLongArray(),
            tokenTypeIds = tokenTypeIds.toLongArray(),
        )
    }

    private fun tokenizeSequence(text: String): List<Long> {
        val tokenIds = mutableListOf<Long>()
        val specialTokens = definition.addedTokens
            .filter { it.special && !it.normalized && !it.singleWord }
            .sortedByDescending { it.content.length }
        var cursor = 0
        while (cursor < text.length) {
            val next = nextSpecialToken(text, cursor, specialTokens)
            if (next == null) {
                tokenIds.addAll(tokenizeOrdinaryText(text.substring(cursor)))
                break
            }
            var ordinary = text.substring(cursor, next.index)
            if (next.token.lstrip) {
                ordinary = ordinary.trimEnd()
            }
            tokenIds.addAll(tokenizeOrdinaryText(ordinary))
            tokenIds.add(next.token.id.toLong())
            cursor = next.index + next.token.content.length
            if (next.token.rstrip) {
                while (cursor < text.length) {
                    val codePoint = text.codePointAt(cursor)
                    if (!isWhitespace(codePoint)) {
                        break
                    }
                    cursor += Character.charCount(codePoint)
                }
            }
        }
        if (text.isEmpty()) {
            return emptyList()
        }
        return tokenIds
    }

    private fun nextSpecialToken(
        text: String,
        start: Int,
        specialTokens: List<AddedTokenDefinition>,
    ): SpecialTokenMatch? {
        var best: SpecialTokenMatch? = null
        specialTokens.forEach { token ->
            val index = text.indexOf(token.content, start)
            if (
                index >= 0 &&
                (
                    best == null ||
                        index < best!!.index ||
                        (index == best!!.index && token.content.length > best!!.token.content.length)
                    )
            ) {
                best = SpecialTokenMatch(index, token)
            }
        }
        return best
    }

    private fun tokenizeOrdinaryText(text: String): List<Long> {
        if (text.isEmpty()) {
            return emptyList()
        }
        return preTokenize(normalize(text)).flatMap(::tokenizeWord)
    }

    private fun normalize(text: String): String {
        val builder = StringBuilder()
        var index = 0
        while (index < text.length) {
            val codePoint = text.codePointAt(index)
            index += Character.charCount(codePoint)
            when {
                definition.normalizer.cleanText && isDiscardedControl(codePoint) -> Unit
                definition.normalizer.cleanText && isWhitespace(codePoint) -> builder.append(' ')
                definition.normalizer.handleChineseChars && isChineseCharacter(codePoint) -> {
                    builder.append(' ')
                    builder.appendCodePoint(codePoint)
                    builder.append(' ')
                }

                else -> builder.appendCodePoint(codePoint)
            }
        }

        var normalized = builder.toString()
        if (definition.normalizer.lowercase) {
            normalized = normalized.lowercase(Locale.ROOT)
        }
        val stripAccents =
            definition.normalizer.stripAccents ?: definition.normalizer.lowercase
        if (stripAccents) {
            val decomposed = Normalizer.normalize(normalized, Normalizer.Form.NFD)
            val withoutAccents = StringBuilder()
            var offset = 0
            while (offset < decomposed.length) {
                val codePoint = decomposed.codePointAt(offset)
                offset += Character.charCount(codePoint)
                if (Character.getType(codePoint) != Character.NON_SPACING_MARK.toInt()) {
                    withoutAccents.appendCodePoint(codePoint)
                }
            }
            normalized = withoutAccents.toString()
        }
        return normalized
    }

    private fun preTokenize(text: String): List<String> {
        val tokens = mutableListOf<String>()
        val current = StringBuilder()
        fun flush() {
            if (current.isNotEmpty()) {
                tokens.add(current.toString())
                current.setLength(0)
            }
        }

        var index = 0
        while (index < text.length) {
            val codePoint = text.codePointAt(index)
            index += Character.charCount(codePoint)
            when {
                isWhitespace(codePoint) -> flush()
                isPunctuation(codePoint) -> {
                    flush()
                    tokens.add(String(Character.toChars(codePoint)))
                }

                else -> current.appendCodePoint(codePoint)
            }
        }
        flush()
        return tokens
    }

    private fun tokenizeWord(word: String): List<Long> {
        if (word.isEmpty()) {
            return emptyList()
        }
        val direct = definition.vocab[word]
        if (direct != null) {
            return listOf(direct.toLong())
        }
        val offsets = codePointOffsets(word)
        val codePointCount = offsets.size - 1
        if (codePointCount > definition.maxInputCharsPerWord) {
            return listOf(definition.unknownTokenId.toLong())
        }

        val pieces = mutableListOf<Long>()
        var start = 0
        while (start < codePointCount) {
            var end = codePointCount
            var matched: Int? = null
            while (end > start) {
                val rawPiece = word.substring(offsets[start], offsets[end])
                val candidate = if (start == 0) {
                    rawPiece
                } else {
                    definition.continuingSubwordPrefix + rawPiece
                }
                val id = definition.vocab[candidate]
                if (id != null) {
                    matched = id
                    break
                }
                end--
            }

            if (matched == null) {
                return listOf(definition.unknownTokenId.toLong())
            }

            pieces.add(matched.toLong())
            start = end
        }

        return pieces
    }

    private fun codePointOffsets(value: String): IntArray {
        val count = value.codePointCount(0, value.length)
        val offsets = IntArray(count + 1)
        var charIndex = 0
        for (index in 0 until count) {
            offsets[index] = charIndex
            charIndex += Character.charCount(value.codePointAt(charIndex))
        }
        offsets[count] = value.length
        return offsets
    }

    private fun isDiscardedControl(codePoint: Int): Boolean {
        if (codePoint == 0 || codePoint == 0xFFFD) {
            return true
        }
        if (codePoint == '\t'.code || codePoint == '\n'.code || codePoint == '\r'.code) {
            return false
        }
        return when (Character.getType(codePoint)) {
            Character.CONTROL.toInt(),
            Character.FORMAT.toInt(),
            Character.PRIVATE_USE.toInt(),
            Character.SURROGATE.toInt(),
            Character.UNASSIGNED.toInt(),
            -> true

            else -> false
        }
    }

    private fun isWhitespace(codePoint: Int): Boolean {
        return Character.isWhitespace(codePoint) || Character.isSpaceChar(codePoint)
    }

    private fun isPunctuation(codePoint: Int): Boolean {
        return when (Character.getType(codePoint)) {
            Character.CONNECTOR_PUNCTUATION.toInt(),
            Character.DASH_PUNCTUATION.toInt(),
            Character.START_PUNCTUATION.toInt(),
            Character.END_PUNCTUATION.toInt(),
            Character.INITIAL_QUOTE_PUNCTUATION.toInt(),
            Character.FINAL_QUOTE_PUNCTUATION.toInt(),
            Character.OTHER_PUNCTUATION.toInt(),
            -> true

            else -> false
        }
    }

    private fun isChineseCharacter(codePoint: Int): Boolean {
        return codePoint in 0x4E00..0x9FFF ||
            codePoint in 0x3400..0x4DBF ||
            codePoint in 0x20000..0x2A6DF ||
            codePoint in 0x2A700..0x2B73F ||
            codePoint in 0x2B740..0x2B81F ||
            codePoint in 0x2B820..0x2CEAF ||
            codePoint in 0xF900..0xFAFF ||
            codePoint in 0x2F800..0x2FA1F
    }

    private data class SpecialTokenMatch(
        val index: Int,
        val token: AddedTokenDefinition,
    )
}
