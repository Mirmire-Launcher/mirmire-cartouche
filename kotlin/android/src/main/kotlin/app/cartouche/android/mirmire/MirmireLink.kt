// SPDX-License-Identifier: GPL-3.0-or-later
package app.cartouche.android.mirmire

import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import app.cartouche.core.ContentUri
import app.cartouche.core.FileName
import app.cartouche.core.library.Disc
import app.cartouche.core.library.Game
import app.cartouche.core.library.GameId
import app.cartouche.core.library.Library
import app.cartouche.core.library.ListedFile
import app.cartouche.core.platforms.DefinitionSource
import app.cartouche.core.platforms.PlatformId
import arrow.core.None
import arrow.core.Option
import arrow.core.Some
import arrow.core.flatMap
import arrow.core.nonEmptyListOf
import arrow.core.toOption
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.putJsonObject
import java.io.ByteArrayOutputStream
import java.io.File

/**
 * Mirmire's library, as Mirmire shares it when it opens this app: a read grant on `content://com.mirmire.cartouche.bridge/`
 * and the library's URI in [EXTRA_LIBRARY]. Mirmire's side is `data/plugins/CartoucheBridge.kt` in Mirmire, version
 * [MirmireLibrary.version]. The games show on the shelves; starting one asks Mirmire to play it ([playIntent]), so its
 * emulator choice, downloads, saves, achievements and play time all stay Mirmire's.
 */
@Serializable
internal data class MirmireGame(
    val id: Long,
    val title: String,
    val system: String,
    val local: Boolean = true,
    val favorite: Boolean = false,
    val lastPlayed: Long? = null,
    val playCount: Int = 0,
    val year: String? = null,
    val genre: String? = null,
    val art: String? = null,
)

@Serializable
internal data class MirmireSystem(
    val id: String,
    val name: String,
    val shortName: String = name,
    val maker: String = "",
    val icon: String? = null,
    val games: Int = 0,
    val disc: Boolean = false,
)

@Serializable
internal data class MirmireSettings(
    val backdrop: String? = null,
    val buttonStyle: String? = null,
    val swapAB: Boolean = false,
    val soundLevel: Int? = null,
)

@Serializable
internal data class MirmireAchievements(
    val user: String = "",
    val points: Int = 0,
    val weekUnlocks: Int = 0,
    val weekPoints: Int = 0,
    val avatar: String? = null,
)

@Serializable
internal data class MirmireLibrary(
    val version: Int = 1,
    val profile: String = "",
    val systems: List<MirmireSystem> = emptyList(),
    val games: List<MirmireGame> = emptyList(),
    val settings: MirmireSettings = MirmireSettings(),
    val achievements: MirmireAchievements? = null,
    val logo: String? = null,
)

internal class MirmireLink private constructor(private val context: Context, val data: MirmireLibrary) {
    /** Every platform of Mirmire's games, as this app names it. */
    val platforms: Set<PlatformId> = data.games.map { platformOf(it.system) }.toSet()

    /** Mirmire's games as this app's library: one disc each, a made-up file standing for Mirmire's game. */
    fun library(): Library = Library(
        games = data.games.mapNotNull { g ->
            ContentUri.parse("content://mirmire/${g.id}").map { uri ->
                val disc = Disc(None, ListedFile(FileName(g.title), uri, None, None))
                Game(gameIdOf(g.id), platformOf(g.system), g.title, emptyList(), emptyList(), None, emptyList(), None, nonEmptyListOf(disc))
            }.getOrNull()
        },
    )

    /**
     * Platform definitions (Daijishō format) and profiles for the platforms of [missing], which the bundled data does
     * not define: no players (Mirmire plays them), any file name, the medium of their kind.
     */
    fun definitionsFor(missing: Set<PlatformId>): List<DefinitionSource> = missing.map { id ->
        val system = systemOf(id)
        val json = buildJsonObject {
            put("databaseVersion", 14)
            put("revisionNumber", 1)
            putJsonObject("platform") {
                put("name", system?.name ?: id.value)
                put("uniqueId", id.value)
                put("shortname", id.value)
                put("acceptedFilenameRegex", "^(.*)$")
                putJsonArray("scraperSourceList") {}
                putJsonArray("retroAchievementsConsoleIdList") {}
                put("extra", "")
            }
            putJsonArray("playerList") {}
        }
        DefinitionSource("mirmire/${id.value}.json", json.toString())
    }

    /** [profiles] (the bundled `profiles.json`) with a profile for each platform of [missing]. */
    fun profilesWith(profiles: String, missing: Set<PlatformId>): String {
        val bundled = runCatching { Json.parseToJsonElement(profiles).jsonObject }.getOrElse { return profiles }
        val added = missing.associate { id ->
            val disc = systemOf(id)?.disc == true
            id.value to buildJsonObject {
                put("media", if (disc) "dvd" else "cartridge")
                putJsonObject("medium") { put("default", if (disc) "ps1_cd" else "gba_cart") }
                put("minimumGameBytes", 0)
            }
        }
        return JsonObject(bundled + added).toString()
    }

    /** Asks Mirmire to play [game]; none for a game that is not Mirmire's. */
    fun playIntent(game: GameId): Option<Intent> = mirmireIdOf(game).map { id ->
        Intent(ACTION_PLAY).setPackage(MIRMIRE_PACKAGE).putExtra(EXTRA_GAME_ID, id).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }

    /**
     * The games whose label Mirmire has art for, and where it is: the favourites and the games played last first, the
     * ones the player is likeliest to look at while the rest are copied.
     */
    fun labels(): List<Pair<GameId, Uri>> = data.games
        .sortedWith(compareByDescending<MirmireGame> { it.favorite }.thenByDescending { it.lastPlayed ?: 0L })
        .mapNotNull { g -> g.art?.let { gameIdOf(g.id) to Uri.parse(it) } }

    /**
     * [uri]'s picture as a JPEG, the format this app keeps labels in; none when it cannot be read. Mirmire sends JPEGs,
     * kept as they come; anything else is decoded and written again.
     */
    fun jpeg(uri: Uri): Option<ByteArray> = runCatching {
        val bytes = context.contentResolver.openInputStream(uri)?.use { it.readBytes() } ?: return None
        if (bytes.size < 4) return None
        if (bytes[0] == 0xFF.toByte() && bytes[1] == 0xD8.toByte()) return Some(bytes)
        val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: return None
        ByteArrayOutputStream().also { bitmap.compress(Bitmap.CompressFormat.JPEG, 92, it) }.toByteArray()
    }.getOrNull().toOption().flatMap { it.toOption() }

    /**
     * Copies the console icons of [platforms] to [folder] (`<platform>.png`, `user://mirmire/icons/`): the generic
     * console's lid shows them, and the logo slots of a console without logos of its own.
     */
    fun copyIcons(platforms: Set<PlatformId>, folder: File) {
        folder.mkdirs()
        platforms.forEach { id ->
            val icon = systemOf(id)?.icon ?: return@forEach
            runCatching {
                context.contentResolver.openInputStream(Uri.parse(icon))?.use { input ->
                    File(folder, "${id.value}.png").outputStream().use(input::copyTo)
                }
            }
        }
    }

    /**
     * What the app's home shows ([MirmireLibrary.version] 2): the counts on its cards, the game to continue, the
     * player's RetroAchievements and Mirmire's logo, their pictures copied to [folder] (`user://mirmire/`).
     */
    fun home(folder: File): JsonObject {
        folder.mkdirs()
        val last = data.games.filter { it.lastPlayed != null }.maxByOrNull { it.lastPlayed ?: 0L }
        val logo = File(folder, "mirmire_logo.png")
        if (!logo.exists()) data.logo?.let { copy(it, logo) }
        val avatar = File(folder, "ra_avatar.png")
        val hasAvatar = data.achievements?.avatar?.let { copy(it, avatar) } ?: false
        return buildJsonObject {
            put("consoles", data.systems.size)
            put("games", data.games.size)
            put("favorites", data.games.count { it.favorite })
            put("recent", data.games.count { it.lastPlayed != null })
            last?.let { g ->
                putJsonObject("continue") {
                    put("game", gameIdOf(g.id).value)
                    put("title", g.title)
                    put("platform", platformOf(g.system).value)
                }
            }
            data.achievements?.let { ra ->
                putJsonObject("achievements") {
                    put("user", ra.user)
                    put("points", ra.points)
                    put("week_unlocks", ra.weekUnlocks)
                    put("week_points", ra.weekPoints)
                    put("avatar", if (hasAvatar) "user://mirmire/ra_avatar.png" else "")
                }
            }
            put("logo", if (logo.exists()) "user://mirmire/mirmire_logo.png" else "")
        }
    }

    /** Copies Mirmire's picture at [uri] to [file]; false when it cannot be read. */
    private fun copy(uri: String, file: File): Boolean = runCatching {
        context.contentResolver.openInputStream(Uri.parse(uri))?.use { input -> file.outputStream().use(input::copyTo) } != null
    }.getOrDefault(false)

    /** Asks Mirmire to open [screen] (settings, widgets or achievements) over Big Picture. */
    fun openIntent(screen: String): Intent =
        Intent(ACTION_OPEN).setPackage(MIRMIRE_PACKAGE).putExtra(EXTRA_SCREEN, screen).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

    /**
     * Tells Mirmire what is chosen, for its second screen: [shown] is `console:<platform id>`, `game:<game id>` or empty
     * for nothing. A console or game that is not Mirmire's is sent as nothing. Mirmire takes it through its bridge,
     * which it opened for writing ([SELECTED]); an older Mirmire, which did not, refuses it and nothing changes.
     */
    fun select(shown: String) {
        val values = ContentValues()
        when {
            shown.startsWith(CONSOLE) -> systemOf(PlatformId(shown.removePrefix(CONSOLE)))?.let { values.put("system", it.id) }
            shown.startsWith(GAME) -> mirmireIdOf(GameId(shown.removePrefix(GAME))).onSome { values.put("game", it) }
        }
        runCatching { context.contentResolver.update(SELECTED, values, null, null) }
    }

    private fun systemOf(id: PlatformId): MirmireSystem? = data.systems.firstOrNull { platformOf(it.id) == id }

    companion object {
        const val EXTRA_LIBRARY = "com.mirmire.extra.LIBRARY"
        const val MIRMIRE_PACKAGE = "com.mirmire"
        const val ACTION_PLAY = "com.mirmire.action.PLAY_GAME"
        const val EXTRA_GAME_ID = "com.mirmire.extra.GAME_ID"
        const val ACTION_OPEN = "com.mirmire.action.OPEN"
        const val EXTRA_SCREEN = "com.mirmire.extra.SCREEN"
        private const val ID_PREFIX = "mirmire/"
        private const val CONSOLE = "console:"
        private const val GAME = "game:"
        /** Where Mirmire takes what is chosen ([select]). */
        private val SELECTED: Uri = Uri.parse("content://com.mirmire.cartouche.bridge/selected")

        private val json = Json { ignoreUnknownKeys = true; coerceInputValues = true }

        /** Mirmire's console ids that are this app's under another name; the others keep theirs, prefixed. */
        private val PLATFORMS = mapOf(
            "nes" to "nes", "snes" to "snes", "n64" to "n64", "gb" to "gb", "gbc" to "gbc", "gba" to "gba", "nds" to "nds",
            "n3ds" to "3ds", "switch" to "switch", "megadrive" to "genesis", "mastersystem" to "master",
            "gamegear" to "gamegear", "pcengine" to "tg16", "atari2600" to "atari2600", "psx" to "psx", "ps2" to "ps2",
            "psp" to "psp", "psvita" to "psvita", "gc" to "gc", "wii" to "wii", "saturn" to "saturn",
            "dreamcast" to "dreamcast", "segacd" to "segacd", "xbox" to "xbox", "xbox360" to "xbox360",
        )

        fun platformOf(system: String): PlatformId = PlatformId(PLATFORMS[system] ?: "mirmire_$system")

        fun gameIdOf(mirmireId: Long): GameId = GameId("$ID_PREFIX$mirmireId")

        fun mirmireIdOf(game: GameId): Option<Long> =
            if (game.value.startsWith(ID_PREFIX)) game.value.removePrefix(ID_PREFIX).toLongOrNull().toOption() else None

        fun isMirmire(game: GameId): Boolean = game.value.startsWith(ID_PREFIX)

        /** The library Mirmire opened this app with, read once; none when it was not opened by Mirmire. */
        fun read(context: Context, intent: Intent?): Option<MirmireLink> {
            val uri = intent?.getStringExtra(EXTRA_LIBRARY)?.let(Uri::parse) ?: return None
            return runCatching {
                val text = context.contentResolver.openInputStream(uri)?.use { it.readBytes().decodeToString() } ?: return None
                MirmireLink(context.applicationContext, json.decodeFromString(MirmireLibrary.serializer(), text))
            }.getOrNull().toOption()
        }
    }
}
