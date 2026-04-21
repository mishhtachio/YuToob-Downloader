package com.example.yt_downloader

import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedInputStream
import java.net.HttpURLConnection
import java.net.URL

class MainActivity : FlutterActivity() {
    private val channelName = "yt_downloader/files"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveUrlToDownloads" -> {
                        val url = call.argument<String>("url")
                        val fileName = call.argument<String>("fileName")
                        val mimeType = call.argument<String>("mimeType")

                        if (url.isNullOrBlank() || fileName.isNullOrBlank()) {
                            result.error("INVALID_ARGS", "Missing url or fileName.", null)
                            return@setMethodCallHandler
                        }

                        Thread {
                            try {
                                saveUrlToDownloads(
                                    url = url,
                                    fileName = fileName,
                                    mimeType = mimeType ?: "application/octet-stream",
                                )
                                runOnUiThread {
                                    result.success(true)
                                }
                            } catch (e: Exception) {
                                runOnUiThread {
                                    result.error("SAVE_FAILED", e.message, null)
                                }
                            }
                        }.start()
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun saveUrlToDownloads(
        url: String,
        fileName: String,
        mimeType: String,
    ) {
        val resolver = applicationContext.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
            put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
            put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
        }

        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: throw IllegalStateException("Could not create download entry.")

        try {
            resolver.openOutputStream(uri)?.use { outputStream ->
                val connection = (URL(url).openConnection() as HttpURLConnection).apply {
                    requestMethod = "GET"
                    connectTimeout = 15000
                    readTimeout = 60000
                    doInput = true
                }

                try {
                    connection.connect()

                    if (connection.responseCode !in 200..299) {
                        throw IllegalStateException("Backend file request failed (${connection.responseCode}).")
                    }

                    BufferedInputStream(connection.inputStream).use { inputStream ->
                        inputStream.copyTo(outputStream)
                    }
                } finally {
                    connection.disconnect()
                }
            } ?: throw IllegalStateException("Could not open MediaStore output stream.")

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val finalizeValues = ContentValues().apply {
                    put(MediaStore.MediaColumns.IS_PENDING, 0)
                }
                resolver.update(uri, finalizeValues, null, null)
            }
        } catch (e: Exception) {
            resolver.delete(uri, null, null)
            throw e
        }
    }
}
