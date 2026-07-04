package uz.neovex.iccu.kiosk

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TimedActionGateTest {
    @Test
    fun blocksRepeatedActionInsideCooldownWindow() {
        val gate = TimedActionGate(cooldownMs = 5_000L)

        assertTrue(gate.tryEnter(nowMs = 10_000L))
        assertFalse(gate.tryEnter(nowMs = 11_000L))
        assertFalse(gate.tryEnter(nowMs = 14_999L))
        assertTrue(gate.tryEnter(nowMs = 15_000L))
    }

    @Test
    fun canBeResetWhenExternalPanelReturns() {
        val gate = TimedActionGate(cooldownMs = 5_000L)

        assertTrue(gate.tryEnter(nowMs = 10_000L))
        gate.reset()

        assertTrue(gate.tryEnter(nowMs = 10_001L))
    }
}
