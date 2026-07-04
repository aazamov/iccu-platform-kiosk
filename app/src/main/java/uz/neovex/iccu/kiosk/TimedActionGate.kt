package uz.neovex.iccu.kiosk

class TimedActionGate(private val cooldownMs: Long) {
    private var nextAllowedAtMs: Long = 0L

    fun tryEnter(nowMs: Long = System.currentTimeMillis()): Boolean {
        if (nowMs < nextAllowedAtMs) return false
        nextAllowedAtMs = nowMs + cooldownMs
        return true
    }

    fun reset() {
        nextAllowedAtMs = 0L
    }
}
