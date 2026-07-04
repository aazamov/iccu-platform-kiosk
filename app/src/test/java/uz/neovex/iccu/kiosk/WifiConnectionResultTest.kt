package uz.neovex.iccu.kiosk

import org.junit.Assert.assertEquals
import org.junit.Test

class WifiConnectionResultTest {
    @Test
    fun mapsBlockedOperationToSafeMessage() {
        val result = WifiOperationMessages.blocked()
        assertEquals("Wi-Fi action blocked by tablet firmware", result.message)
    }

    @Test
    fun mapsFailedOperationToSafeMessage() {
        val result = WifiOperationMessages.failed("connect")
        assertEquals("Could not connect Wi-Fi", result.message)
    }
}
