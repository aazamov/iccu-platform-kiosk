package uz.neovex.iccu.kiosk

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PinValidatorTest {
    @Test
    fun acceptsExitPin() {
        assertTrue(PinValidator.isExitPin("2026"))
    }

    @Test
    fun rejectsOtherValues() {
        assertFalse(PinValidator.isExitPin("2025"))
        assertFalse(PinValidator.isExitPin(""))
    }
}
