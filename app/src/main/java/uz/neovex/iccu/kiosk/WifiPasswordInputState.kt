package uz.neovex.iccu.kiosk

enum class WifiKeyboardMode {
    LETTERS,
    SYMBOLS,
}

class WifiPasswordInputState {
    private val buffer = StringBuilder()
    var mode: WifiKeyboardMode = WifiKeyboardMode.LETTERS
        private set
    var shifted: Boolean = false
        private set
    var passwordVisible: Boolean = false
        private set

    val password: String
        get() = buffer.toString()

    fun appendKey(label: String) {
        val value = if (mode == WifiKeyboardMode.LETTERS && label.length == 1 && label[0].isLetter()) {
            if (shifted) label.uppercase() else label.lowercase()
        } else {
            label
        }
        buffer.append(value)
    }

    fun backspace() {
        if (buffer.isNotEmpty()) {
            buffer.deleteAt(buffer.lastIndex)
        }
    }

    fun clear() {
        buffer.clear()
        passwordVisible = false
    }

    fun reset() {
        buffer.clear()
        mode = WifiKeyboardMode.LETTERS
        shifted = false
        passwordVisible = false
    }

    fun toggleVisibility() {
        passwordVisible = !passwordVisible
    }

    fun toggleShift() {
        shifted = !shifted
    }

    fun toggleMode() {
        mode = if (mode == WifiKeyboardMode.LETTERS) WifiKeyboardMode.SYMBOLS else WifiKeyboardMode.LETTERS
        shifted = false
    }

    fun maskedPassword(): String = "•".repeat(buffer.length)

    fun displayPassword(): String = if (passwordVisible) password else maskedPassword()
}
