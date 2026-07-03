package uz.neovex.iccu.kiosk

import android.app.Activity
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.os.Bundle
import android.widget.Toast

class DebugRemoveOwnerActivity : Activity() {
    @Suppress("DEPRECATION")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val devicePolicyManager = getSystemService(DevicePolicyManager::class.java)
        val adminComponent = ComponentName(this, KioskDeviceAdminReceiver::class.java)

        runCatching { stopLockTask() }
        if (devicePolicyManager.isDeviceOwnerApp(packageName)) {
            runCatching {
                devicePolicyManager.setLockTaskPackages(adminComponent, emptyArray())
                devicePolicyManager.clearPackagePersistentPreferredActivities(
                    adminComponent,
                    packageName,
                )
            }
            devicePolicyManager.clearDeviceOwnerApp(packageName)
            Toast.makeText(this, "Device owner removed", Toast.LENGTH_SHORT).show()
        } else {
            Toast.makeText(this, "App is not device owner", Toast.LENGTH_SHORT).show()
        }

        finishAndRemoveTask()
    }
}
