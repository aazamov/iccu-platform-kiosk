package uz.neovex.iccu.kiosk

enum class WifiSecurity {
    OPEN,
    WPA_PSK,
    UNSUPPORTED,
}

data class WifiNetworkInfo(
    val ssid: String,
    val signalLevel: Int,
    val secured: Boolean,
    val connected: Boolean,
    val security: WifiSecurity = if (secured) WifiSecurity.WPA_PSK else WifiSecurity.OPEN,
)

object WifiSecurityParser {
    fun parse(capabilities: String): WifiSecurity {
        val normalized = capabilities.uppercase()
        val hasPsk = normalized.contains("WPA-PSK") ||
            normalized.contains("WPA2-PSK") ||
            normalized.contains("PSK")
        if (hasPsk) return WifiSecurity.WPA_PSK

        val hasUnsupportedSecurity = listOf("WEP", "SAE", "EAP").any { token ->
            normalized.contains(token)
        }
        return if (hasUnsupportedSecurity) WifiSecurity.UNSUPPORTED else WifiSecurity.OPEN
    }

    fun isSecured(capabilities: String): Boolean {
        return parse(capabilities) != WifiSecurity.OPEN
    }
}
