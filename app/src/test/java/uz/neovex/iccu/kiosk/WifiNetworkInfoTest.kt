package uz.neovex.iccu.kiosk

import org.junit.Assert.assertFalse
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class WifiNetworkInfoTest {
    @Test
    fun detectsSecuredNetworks() {
        assertTrue(WifiSecurityParser.isSecured("[WPA2-PSK-CCMP][ESS]"))
        assertTrue(WifiSecurityParser.isSecured("[WPA-PSK-CCMP][WPA2-PSK-CCMP][ESS]"))
        assertTrue(WifiSecurityParser.isSecured("[SAE][ESS]"))
        assertTrue(WifiSecurityParser.isSecured("[WEP][ESS]"))
        assertTrue(WifiSecurityParser.isSecured("[EAP/SHA1][ESS]"))
    }

    @Test
    fun detectsOpenNetworks() {
        assertFalse(WifiSecurityParser.isSecured("[ESS]"))
        assertFalse(WifiSecurityParser.isSecured(""))
    }

    @Test
    fun parsesSupportedConnectionSecurity() {
        assertEquals(WifiSecurity.OPEN, WifiSecurityParser.parse("[ESS]"))
        assertEquals(WifiSecurity.WPA_PSK, WifiSecurityParser.parse("[WPA-PSK-CCMP][ESS]"))
        assertEquals(WifiSecurity.WPA_PSK, WifiSecurityParser.parse("[WPA2-PSK-CCMP][ESS]"))
        assertEquals(WifiSecurity.WPA_PSK, WifiSecurityParser.parse("[WPA2-PSK-CCMP][SAE][ESS]"))
    }

    @Test
    fun parsesUnsupportedConnectionSecurity() {
        assertEquals(WifiSecurity.UNSUPPORTED, WifiSecurityParser.parse("[WEP][ESS]"))
        assertEquals(WifiSecurity.UNSUPPORTED, WifiSecurityParser.parse("[EAP/SHA1][ESS]"))
        assertEquals(WifiSecurity.UNSUPPORTED, WifiSecurityParser.parse("[SAE][ESS]"))
        assertEquals(WifiSecurity.UNSUPPORTED, WifiSecurityParser.parse("[WAPI-PSK][ESS]"))
        assertEquals(WifiSecurity.UNSUPPORTED, WifiSecurityParser.parse("[OWE][ESS]"))
    }
}
