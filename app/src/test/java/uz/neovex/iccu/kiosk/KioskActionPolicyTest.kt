package uz.neovex.iccu.kiosk

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class KioskActionPolicyTest {
    @Test
    fun wifiPanelMustNotStopKioskMode() {
        assertFalse(KioskActionPolicy.shouldStopKioskFor(KioskAction.WIFI_PANEL))
    }

    @Test
    fun wifiPanelMustNotAutoHide() {
        assertFalse(KioskActionPolicy.shouldAutoHide(KioskAction.WIFI_PANEL))
    }

    @Test
    fun pinExitCanStopKioskMode() {
        assertTrue(KioskActionPolicy.shouldStopKioskFor(KioskAction.PIN_EXIT))
    }
}
