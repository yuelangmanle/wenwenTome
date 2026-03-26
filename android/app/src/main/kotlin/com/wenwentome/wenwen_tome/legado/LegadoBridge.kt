package com.wenwentome.wenwen_tome.legado

import android.content.Context
import android.net.Uri
import android.os.Build
import android.text.Html
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import okhttp3.OkHttpClient
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class LegadoBridge(
    private val activity: FlutterActivity,
) {
    private data class LegadoBookContext(
        val bookUrl: String,
        val origin: String,
        val book: JSONObject,
    )

    companion object {
        private val packageCandidates = listOf(
            "io.legado.app.release",
            "io.legado.app.debug",
            "io.legado.app",
        )
        private const val providerSuffix = ".readerProvider"
        private const val websocketPath = "searchBook"
        private val httpPorts = listOf(1234, 1122)
        private val websocketPorts = listOf(1235, 1123)
    }

    private val executor = Executors.newSingleThreadExecutor()

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "prewarm" -> executeAsync(result) {
                prewarm()
                null
            }
            "searchBooks" -> executeAsync(result) {
                searchBooks(call)
            }
            "getChapters" -> executeAsync(result) {
                getChapters(call)
            }
            "getChapterContent" -> executeAsync(result) {
                getChapterContent(call)
            }
            "getStatus" -> executeAsync(result) {
                getStatus()
            }
            else -> result.notImplemented()
        }
    }

    fun dispose() {
        executor.shutdownNow()
    }

    private fun executeAsync(
        result: MethodChannel.Result,
        block: () -> Any?,
    ) {
        executor.execute {
            try {
                val value = block()
                activity.runOnUiThread {
                    result.success(value)
                }
            } catch (error: Throwable) {
                activity.runOnUiThread {
                    result.error(
                        "legado_bridge_failure",
                        error.message ?: error.javaClass.simpleName,
                        null,
                    )
                }
            }
        }
    }

    private fun prewarm() {
        for (authority in authorityCandidates()) {
            if (queryProvider(authority, listOf("bookSources", "query")) != null) {
                return
            }
        }
    }

    private fun searchBooks(call: MethodCall): Any? {
        val query = call.argument<String>("query")?.trim().orEmpty()
        val sourceId = call.argument<String>("sourceId")?.trim()
        if (query.isEmpty()) {
            return emptyList<Map<String, Any?>>()
        }
        if (!sourceId.isNullOrEmpty()) {
            return null
        }
        if (!hasInstalledLegadoPackage()) {
            return null
        }
        return searchBooksViaWebSocket(query)
    }

    private fun getChapters(call: MethodCall): Any? {
        val webBookId = call.argument<String>("webBookId")?.trim().orEmpty()
        val refresh = call.argument<Boolean>("refresh") ?: false
        val meta = call.argument<Map<String, Any?>>("meta") ?: return null
        if (webBookId.isEmpty()) {
            return null
        }
        val context = resolveBookContext(meta) ?: return null
        if (!isHttpServiceAvailable()) {
            return null
        }
        saveBook(context.book) ?: return null
        if (refresh) {
            getJson("refreshToc", mapOf("url" to context.bookUrl))
        }
        val chapterResponse = getJson("getChapterList", mapOf("url" to context.bookUrl)) ?: return null
        if (!chapterResponse.optBoolean("isSuccess")) {
            return null
        }
        val chapters = chapterResponse.optJSONArray("data") ?: return null
        return List(chapters.length()) { index ->
            val item = chapters.optJSONObject(index) ?: JSONObject()
            mapOf(
                "id" to "$webBookId::$index",
                "webBookId" to webBookId,
                "sourceId" to (meta["sourceId"]?.toString() ?: context.origin),
                "title" to item.optString("title"),
                "url" to item.optString("url"),
                "chapterIndex" to item.optInt("index", index),
                "updatedAt" to null,
            )
        }
    }

    private fun getChapterContent(call: MethodCall): Any? {
        val webBookId = call.argument<String>("webBookId")?.trim().orEmpty()
        val chapterIndex = call.argument<Int>("chapterIndex") ?: return null
        val meta = call.argument<Map<String, Any?>>("meta") ?: return null
        val chapter = call.argument<Map<String, Any?>>("chapter") ?: emptyMap<String, Any?>()
        if (webBookId.isEmpty()) {
            return null
        }
        val context = resolveBookContext(meta) ?: return null
        if (!isHttpServiceAvailable()) {
            return null
        }
        saveBook(context.book) ?: return null
        val contentResponse = getJson(
            "getBookContent",
            mapOf(
                "url" to context.bookUrl,
                "index" to chapterIndex.toString(),
            ),
        ) ?: return null
        if (!contentResponse.optBoolean("isSuccess")) {
            return null
        }
        val rawContent = contentResponse.optString("data")
        if (rawContent.isBlank()) {
            return null
        }
        val chapterTitle = chapter["title"]?.toString()?.trim().orEmpty()
        return mapOf(
            "chapterId" to (chapter["id"]?.toString()?.takeIf { it.isNotBlank() } ?: "$webBookId::$chapterIndex"),
            "sourceId" to (chapter["sourceId"]?.toString()?.takeIf { it.isNotBlank() }
                ?: meta["sourceId"]?.toString()?.takeIf { it.isNotBlank() }
                ?: context.origin),
            "title" to chapterTitle.ifBlank { "正文" },
            "text" to toPlainText(rawContent),
            "html" to rawContent,
            "fetchedAt" to System.currentTimeMillis(),
            "isComplete" to true,
        )
    }

    private fun getStatus(): Map<String, Any?> {
        val packageName = installedPackageName().orEmpty()
        val providerAvailable = authorityCandidates().any { authority ->
            queryProvider(authority, listOf("bookSources", "query")) != null
        }
        val httpAvailable = isHttpServiceAvailable()
        return mapOf(
            "installed" to packageName.isNotEmpty(),
            "packageName" to packageName,
            "providerAvailable" to providerAvailable,
            "httpServiceAvailable" to httpAvailable,
            "webSocketAvailable" to probeSearchWebSocket(),
        )
    }

    private fun hasInstalledLegadoPackage(): Boolean {
        return installedPackageName() != null
    }

    private fun installedPackageName(): String? {
        return packageCandidates.firstOrNull { packageName ->
            runCatching {
                activity.packageManager.getPackageInfo(packageName, 0)
            }.isSuccess
        }
    }

    private fun authorityCandidates(): List<String> {
        return packageCandidates.map { packageName ->
            "$packageName$providerSuffix"
        }
    }

    private fun queryProvider(
        authority: String,
        pathSegments: List<String>,
        query: Map<String, String> = emptyMap(),
    ): String? {
        val uriBuilder = Uri.Builder().scheme("content").authority(authority)
        for (segment in pathSegments) {
            uriBuilder.appendPath(segment)
        }
        for ((key, value) in query) {
            uriBuilder.appendQueryParameter(key, value)
        }
        val cursor =
            activity.contentResolver.query(uriBuilder.build(), null, null, null, null)
                ?: return null
        cursor.use {
            if (!it.moveToFirst()) {
                return null
            }
            return it.getString(0)
        }
    }

    private fun isHttpServiceAvailable(): Boolean {
        val response = getJson("getBookSources")
        return response?.has("isSuccess") == true
    }

    private fun resolveBookContext(meta: Map<String, Any?>): LegadoBookContext? {
        val platformPayload = meta["platformPayload"]?.toString()?.trim().orEmpty()
        if (platformPayload.isEmpty()) {
            return null
        }
        val platformJson = JSONObject(platformPayload)
        val bookUrl = platformJson.optString("bookUrl").ifBlank {
            meta["detailUrl"]?.toString()?.trim().orEmpty()
        }
        val origin = platformJson.optString("origin").ifBlank {
            meta["sourceId"]?.toString()?.trim().orEmpty()
        }
        if (bookUrl.isBlank() || origin.isBlank()) {
            return null
        }
        val book = JSONObject().apply {
            put("bookUrl", bookUrl)
            put("tocUrl", platformJson.optString("tocUrl").ifBlank { bookUrl })
            put("origin", origin)
            put("originName", platformJson.optString("originName"))
            put("name", meta["title"]?.toString() ?: platformJson.optString("name"))
            put("author", meta["author"]?.toString() ?: platformJson.optString("author"))
            put("kind", platformJson.optString("kind"))
            put("coverUrl", meta["coverUrl"]?.toString() ?: platformJson.optString("coverUrl"))
            put("intro", meta["description"]?.toString() ?: platformJson.optString("intro"))
            put("type", platformJson.optInt("type", 0))
            put("latestChapterTitle", platformJson.optString("latestChapterTitle"))
            put("wordCount", platformJson.optString("wordCount"))
            put("originOrder", platformJson.optInt("originOrder", 0))
            put("variable", platformJson.optString("variable"))
            put("durChapterIndex", 0)
            put("durChapterPos", 0)
            put("durChapterTime", System.currentTimeMillis())
        }
        return LegadoBookContext(bookUrl = bookUrl, origin = origin, book = book)
    }

    private fun saveBook(book: JSONObject): JSONObject? {
        return postJson("saveBook", book.toString())
    }

    private fun toPlainText(rawHtml: String): String {
        val parsed = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            Html.fromHtml(rawHtml, Html.FROM_HTML_MODE_LEGACY)
        } else {
            @Suppress("DEPRECATION")
            Html.fromHtml(rawHtml)
        }
        return parsed.toString().replace("\u00A0", " ").trim()
    }

    private fun getJson(
        path: String,
        query: Map<String, String> = emptyMap(),
    ): JSONObject? {
        val client = OkHttpClient.Builder()
            .connectTimeout(2, TimeUnit.SECONDS)
            .readTimeout(6, TimeUnit.SECONDS)
            .build()

        for (port in httpPorts) {
            val builder = Uri.Builder()
                .scheme("http")
                .encodedAuthority("127.0.0.1:$port")
                .appendPath(path)
            for ((key, value) in query) {
                builder.appendQueryParameter(key, value)
            }
            val request = Request.Builder().url(builder.build().toString()).get().build()
            val payload = runCatching {
                client.newCall(request).execute().use { response ->
                    if (!response.isSuccessful) {
                        return@use null
                    }
                    val body = response.body?.string()?.trim().orEmpty()
                    if (body.isEmpty() || !body.startsWith("{")) {
                        return@use null
                    }
                    JSONObject(body)
                }
            }.getOrNull()
            if (payload != null) {
                return payload
            }
        }
        return null
    }

    private fun postJson(
        path: String,
        body: String,
    ): JSONObject? {
        val client = OkHttpClient.Builder()
            .connectTimeout(2, TimeUnit.SECONDS)
            .readTimeout(8, TimeUnit.SECONDS)
            .build()

        for (port in httpPorts) {
            val request = Request.Builder()
                .url("http://127.0.0.1:$port/$path")
                .post(body.toRequestBody("application/json; charset=utf-8".toMediaType()))
                .build()
            val payload = runCatching {
                client.newCall(request).execute().use { response ->
                    if (!response.isSuccessful) {
                        return@use null
                    }
                    val responseBody = response.body?.string()?.trim().orEmpty()
                    if (responseBody.isEmpty() || !responseBody.startsWith("{")) {
                        return@use null
                    }
                    JSONObject(responseBody)
                }
            }.getOrNull()
            if (payload != null) {
                return payload
            }
        }
        return null
    }

    private fun searchBooksViaWebSocket(query: String): List<Map<String, Any?>>? {
        for (port in websocketPorts) {
            val request = Request.Builder()
                .url("ws://127.0.0.1:$port/$websocketPath")
                .build()
            val finished = CountDownLatch(1)
            val items = mutableListOf<Map<String, Any?>>()
            var opened = false
            var failed = false
            val client = OkHttpClient.Builder()
                .connectTimeout(2, TimeUnit.SECONDS)
                .readTimeout(0, TimeUnit.MILLISECONDS)
                .build()
            val webSocket = client.newWebSocket(
                request,
                object : WebSocketListener() {
                    override fun onOpen(webSocket: WebSocket, response: Response) {
                        opened = true
                        webSocket.send(JSONObject(mapOf("key" to query)).toString())
                    }

                    override fun onMessage(webSocket: WebSocket, text: String) {
                        if (!text.trim().startsWith("[")) {
                            return
                        }
                        val json = JSONArray(text)
                        for (index in 0 until json.length()) {
                            val payload = json.optJSONObject(index) ?: continue
                            val mapped = payload.toSearchResultMap() ?: continue
                            items.add(mapped)
                        }
                    }

                    override fun onClosing(
                        webSocket: WebSocket,
                        code: Int,
                        reason: String,
                    ) {
                        webSocket.close(code, reason)
                        finished.countDown()
                    }

                    override fun onClosed(
                        webSocket: WebSocket,
                        code: Int,
                        reason: String,
                    ) {
                        finished.countDown()
                    }

                    override fun onFailure(
                        webSocket: WebSocket,
                        t: Throwable,
                        response: Response?,
                    ) {
                        failed = true
                        finished.countDown()
                    }
                },
            )
            val completed = finished.await(8, TimeUnit.SECONDS)
            webSocket.cancel()
            client.dispatcher.executorService.shutdown()
            client.connectionPool.evictAll()
            if (completed && !failed && opened && items.isNotEmpty()) {
                return items
            }
        }
        return null
    }

    private fun probeSearchWebSocket(): Boolean {
        for (port in websocketPorts) {
            val request = Request.Builder()
                .url("ws://127.0.0.1:$port/$websocketPath")
                .build()
            val finished = CountDownLatch(1)
            var opened = false
            val client = OkHttpClient.Builder()
                .connectTimeout(2, TimeUnit.SECONDS)
                .readTimeout(0, TimeUnit.MILLISECONDS)
                .build()
            val socket = client.newWebSocket(
                request,
                object : WebSocketListener() {
                    override fun onOpen(webSocket: WebSocket, response: Response) {
                        opened = true
                        webSocket.close(1000, "probe")
                        finished.countDown()
                    }

                    override fun onFailure(
                        webSocket: WebSocket,
                        t: Throwable,
                        response: Response?,
                    ) {
                        finished.countDown()
                    }
                },
            )
            finished.await(3, TimeUnit.SECONDS)
            socket.cancel()
            client.dispatcher.executorService.shutdown()
            client.connectionPool.evictAll()
            if (opened) {
                return true
            }
        }
        return false
    }
}

private fun JSONObject.toSearchResultMap(): Map<String, Any?>? {
    val title = optString("name").trim()
    val detailUrl = optString("bookUrl").trim()
    if (title.isEmpty() || detailUrl.isEmpty()) {
        return null
    }
    val sourceId = optString("origin").trim().ifEmpty { "legado" }
    return mapOf(
        "sourceId" to sourceId,
        "title" to title,
        "detailUrl" to detailUrl,
        "author" to optString("author").trim(),
        "coverUrl" to optString("coverUrl").trim(),
        "description" to optString("intro").trim(),
        "origin" to "direct",
        "platformPayload" to toString(),
    )
}
