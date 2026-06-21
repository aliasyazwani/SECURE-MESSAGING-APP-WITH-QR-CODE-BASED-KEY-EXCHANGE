// ============================================================
//  android/app/src/main/kotlin/com/fyp/secure_link/MainActivity.kt
//
//  ANDROID SECURITY: FLAG_SECURE
//  This flag prevents the app from appearing in recent apps thumbnails
//  and disables screenshots/screen recording while the app is active.
//  This is important for a security app to prevent:
//  - Screen capture of sensitive messages
//  - Shoulder surfing via recent apps
//  - Screen recording of session keys / QR codes
// ============================================================

package com.fyp.secure_link

import io.flutter.embedding.android.FlutterActivity
import android.os.Bundle
import android.view.WindowManager

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Apply FLAG_SECURE to prevent screenshots and screen recording.
        // This protects sensitive content: messages, QR codes, session keys.
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE
        )
    }
}
