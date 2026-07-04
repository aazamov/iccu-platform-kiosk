package uz.neovex.iccu.kiosk

import org.junit.Assert.assertEquals
import org.junit.Test

class WifiPowerButtonTextTest {
    @Test
    fun showsCurrentWifiPowerState() {
        assertEquals("Wi-Fi ON", WifiPowerButtonText.forEnabled(true))
        assertEquals("Wi-Fi OFF", WifiPowerButtonText.forEnabled(false))
    }
}
