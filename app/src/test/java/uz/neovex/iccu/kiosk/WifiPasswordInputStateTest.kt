package uz.neovex.iccu.kiosk

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class WifiPasswordInputStateTest {
    @Test
    fun appendsLettersAndMasksPassword() {
        val state = WifiPasswordInputState()

        state.appendKey("n")
        state.appendKey("e")
        state.appendKey("o")

        assertEquals("neo", state.password)
        assertEquals("•••", state.maskedPassword())
    }

    @Test
    fun shiftUppercasesLetters() {
        val state = WifiPasswordInputState()

        state.toggleShift()
        state.appendKey("n")

        assertEquals("N", state.password)
        assertTrue(state.shifted)
    }

    @Test
    fun backspaceRemovesOneCharacter() {
        val state = WifiPasswordInputState()

        state.appendKey("1")
        state.appendKey("2")
        state.backspace()

        assertEquals("1", state.password)
    }

    @Test
    fun clearEmptiesPassword() {
        val state = WifiPasswordInputState()

        state.appendKey("a")
        state.clear()

        assertEquals("", state.password)
        assertEquals("", state.maskedPassword())
    }

    @Test
    fun symbolsModeAcceptsWifiPasswordSymbols() {
        val state = WifiPasswordInputState()

        state.toggleMode()
        state.appendKey("!")
        state.appendKey("@")
        state.appendKey("-")

        assertEquals(WifiKeyboardMode.SYMBOLS, state.mode)
        assertEquals("!@-", state.password)
    }

    @Test
    fun toggleModeReturnsToLettersAndClearsShift() {
        val state = WifiPasswordInputState()

        state.toggleShift()
        state.toggleMode()
        state.toggleMode()

        assertEquals(WifiKeyboardMode.LETTERS, state.mode)
        assertFalse(state.shifted)
    }
}
