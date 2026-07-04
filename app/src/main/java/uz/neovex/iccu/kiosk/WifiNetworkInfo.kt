package uz.neovex.iccu.kiosk

data class WifiNetworkInfo(
    val ssid: String,
    val signalLevel: Int,
    val secured: Boolean,
    val connected: Boolean,
)

object WifiSecurityParser {
    fun isSecured(capabilities: String): Boolean {
        val normalized = capabilities.uppercase()
        return listOf("WPA", "WEP", "SAE", "EAP").any { token -> normalized.contains(token) }
    }
}
