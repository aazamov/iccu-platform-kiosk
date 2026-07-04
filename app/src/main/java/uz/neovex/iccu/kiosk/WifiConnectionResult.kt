package uz.neovex.iccu.kiosk

sealed class WifiConnectionResult {
    data object Success : WifiConnectionResult()
    data class Failure(val message: String) : WifiConnectionResult()
}

object WifiOperationMessages {
    fun blocked(): WifiConnectionResult.Failure =
        WifiConnectionResult.Failure("Wi-Fi action blocked by tablet firmware")

    fun failed(action: String): WifiConnectionResult.Failure =
        WifiConnectionResult.Failure("Could not $action Wi-Fi")
}
