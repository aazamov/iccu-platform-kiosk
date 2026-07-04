package uz.neovex.iccu.kiosk

object WifiPowerButtonText {
    fun forEnabled(enabled: Boolean): String = if (enabled) "Wi-Fi ON" else "Wi-Fi OFF"
}
