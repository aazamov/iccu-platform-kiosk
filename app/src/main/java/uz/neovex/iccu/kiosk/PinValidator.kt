package uz.neovex.iccu.kiosk

object PinValidator {
    private const val EXIT_PIN = "2026"

    fun isExitPin(value: String): Boolean = value == EXIT_PIN
}
