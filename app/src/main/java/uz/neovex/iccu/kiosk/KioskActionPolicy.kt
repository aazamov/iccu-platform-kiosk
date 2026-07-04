package uz.neovex.iccu.kiosk

enum class KioskAction {
    WIFI_PANEL,
    PIN_EXIT,
}

object KioskActionPolicy {
    fun shouldStopKioskFor(action: KioskAction): Boolean =
        when (action) {
            KioskAction.WIFI_PANEL -> false
            KioskAction.PIN_EXIT -> true
        }
}
