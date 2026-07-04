package uz.neovex.iccu.kiosk

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class WifiNetworkInfoTest {
    @Test
    fun detectsSecuredNetworks() {
        assertTrue(WifiSecurityParser.isSecured("[WPA2-PSK-CCMP][ESS]"))
        assertTrue(WifiSecurityParser.isSecured("[WPA-PSK-CCMP][WPA2-PSK-CCMP][ESS]"))
        assertTrue(WifiSecurityParser.isSecured("[SAE][ESS]"))
        assertTrue(WifiSecurityParser.isSecured("[WEP][ESS]"))
    }

    @Test
    fun detectsOpenNetworks() {
        assertFalse(WifiSecurityParser.isSecured("[ESS]"))
        assertFalse(WifiSecurityParser.isSecured(""))
    }
}
