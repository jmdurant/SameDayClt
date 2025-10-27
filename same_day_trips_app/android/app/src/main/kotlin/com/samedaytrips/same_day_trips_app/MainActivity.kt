package com.samedaytrips.same_day_trips_app

import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.samedaytrips/android_auto"
    
    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler {
            call, result ->
            when (call.method) {
                "isAndroidAutoMode" -> {
                    result.success(isAndroidAutoMode())
                }
                "launchNavigation" -> {
                    val destination = call.argument<String>("destination")
                    if (destination != null) {
                        launchGoogleMapsNavigation(destination)
                        result.success(true)
                    } else {
                        result.error("INVALID_ARGUMENT", "Destination is required", null)
                    }
                }
                "launchNavigationWithWaypoints" -> {
                    val destination = call.argument<String>("destination")
                    val waypoints = call.argument<List<String>>("waypoints")
                    if (destination != null) {
                        launchGoogleMapsWithWaypoints(destination, waypoints ?: emptyList())
                        result.success(true)
                    } else {
                        result.error("INVALID_ARGUMENT", "Destination is required", null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
    
    private fun isAndroidAutoMode(): Boolean {
        return try {
            // Check if Android Auto is available
            packageManager.getPackageInfo("com.google.android.projection.gearhead", 0)
            
            // Check if running in automotive mode
            packageManager.hasSystemFeature(PackageManager.FEATURE_AUTOMOTIVE) ||
            // Check if connected to Android Auto
            packageManager.hasSystemFeature("android.hardware.type.automotive")
        } catch (e: Exception) {
            false
        }
    }
    
    private fun launchGoogleMapsNavigation(destination: String) {
        try {
            // Launch Google Maps navigation
            val uri = Uri.parse("google.navigation:q=$destination&mode=d")
            val intent = Intent(Intent.ACTION_VIEW, uri)
            intent.setPackage("com.google.android.apps.maps")
            
            // This will work in both phone and Android Auto
            startActivity(intent)
        } catch (e: Exception) {
            // Fallback to browser if Maps not available
            val uri = Uri.parse("https://www.google.com/maps/dir/?api=1&destination=$destination")
            val intent = Intent(Intent.ACTION_VIEW, uri)
            startActivity(intent)
        }
    }
    
    private fun launchGoogleMapsWithWaypoints(destination: String, waypoints: List<String>) {
        try {
            // Build waypoints string
            val waypointsStr = waypoints.joinToString("|")
            
            // Launch Google Maps with waypoints
            val uri = if (waypoints.isNotEmpty()) {
                Uri.parse("https://www.google.com/maps/dir/?api=1&destination=$destination&waypoints=$waypointsStr&travelmode=driving")
            } else {
                Uri.parse("google.navigation:q=$destination&mode=d")
            }
            
            val intent = Intent(Intent.ACTION_VIEW, uri)
            intent.setPackage("com.google.android.apps.maps")
            startActivity(intent)
        } catch (e: Exception) {
            // Fallback to simple navigation
            launchGoogleMapsNavigation(destination)
        }
    }
}

