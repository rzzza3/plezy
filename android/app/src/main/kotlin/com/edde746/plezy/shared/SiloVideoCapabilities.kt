package com.edde746.plezy.shared

import android.content.Context
import android.hardware.display.DisplayManager
import android.hardware.display.HdrConversionMode
import android.media.MediaCodecInfo
import android.media.MediaCodecInfo.CodecProfileLevel
import android.media.MediaCodecList
import android.os.Build
import android.view.Display
import android.view.WindowManager
import java.util.Locale

/**
 * The decoder and display facts a Silo v3 playback start carries, probed the
 * way Silo's own Android client does (`MediaCodecCapabilitiesProbe` and
 * `DisplayHdrProbe` in silo-android's `android-shared`). Without them the
 * server sees a client with no HDR and no decoder bounds, and refuses a 4K HDR
 * original whenever its 4K transcoding is off.
 *
 * The decoder half is static for the process and probed once; the display
 * half is read on every call, since the active mode (and with it HDR output)
 * changes with the TV and the refresh-rate matcher.
 */
internal object SiloVideoCapabilities {
  fun probe(context: Context): Map<String, Any?> {
    val decoders = decoderProbe
    return mapOf(
      "videoDecode" to decoders.videoDecode,
      "decoderHdr" to decoders.hdr,
      "display" to displayProbe(context)
    )
  }

  private class DecoderProbe(val videoDecode: List<Map<String, Any?>>, val hdr: Map<String, Any?>)

  private val decoderProbe: DecoderProbe by lazy { probeDecoders() }

  private fun probeDecoders(): DecoderProbe {
    val detailed = mutableListOf<Map<String, Any?>>()
    var hdr10 = false
    var hdr10Plus = false
    var hevcHdr = false
    var av1Hdr = false
    val dv = sortedSetOf<Int>()
    val dvMaxLevels = mutableMapOf<Int, Int>()
    var dvP7MultiInstance = false
    var hevcMultiInstance = false

    for (info in MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos) {
      if (info.isEncoder || !MediaCodecQuery.isHardwareAccelerated(info)) continue
      for (type in info.supportedTypes) {
        val codec = codecName(type) ?: continue
        val caps = runCatching { info.getCapabilitiesForType(type) }.getOrNull() ?: continue
        detailed += videoDecodeEntry(codec, info.name, caps)
        val multiInstance = runCatching { caps.maxSupportedInstances >= 2 }.getOrDefault(false)
        when (codec) {
          "hevc" -> {
            hevcMultiInstance = hevcMultiInstance || multiInstance
            for (pl in caps.profileLevels) when (pl.profile) {
              CodecProfileLevel.HEVCProfileMain10HDR10 -> {
                hevcHdr = true
                hdr10 = true
              }
              CodecProfileLevel.HEVCProfileMain10HDR10Plus -> {
                hevcHdr = true
                hdr10 = true
                hdr10Plus = true
              }
            }
          }
          "av1" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            for (pl in caps.profileLevels) when (pl.profile) {
              CodecProfileLevel.AV1ProfileMain10HDR10 -> {
                av1Hdr = true
                hdr10 = true
              }
              CodecProfileLevel.AV1ProfileMain10HDR10Plus -> {
                av1Hdr = true
                hdr10 = true
                hdr10Plus = true
              }
            }
          }
          "dolby_vision" -> for (pl in caps.profileLevels) {
            val profile = dolbyVisionProfileNumber(pl.profile) ?: continue
            dv += profile
            if (profile == 7) dvP7MultiInstance = dvP7MultiInstance || multiInstance
            dolbyVisionLevelNumber(pl.level)?.let { dvMaxLevels[profile] = maxOf(dvMaxLevels[profile] ?: 0, it) }
          }
        }
      }
    }

    // Dual-layer profile 7 needs two concurrent HEVC instances.
    val dvProfiles = if (dvP7MultiInstance && hevcMultiInstance) dv.toList() else dv.filterNot { it == 7 }
    // Once any bounds are sent the server wants one per profile, so a
    // profile without a recognisable level drops every bound.
    val dvLevels = if (dvProfiles.all { it in dvMaxLevels }) {
      dvProfiles.map { mapOf("profile" to it, "max_level" to dvMaxLevels.getValue(it)) }
    } else {
      emptyList()
    }
    // An HDR profile counts only while a decoder that can carry it survived.
    val hdrSurvives = hevcHdr || av1Hdr || dvProfiles.isNotEmpty()
    // HLG needs no static metadata: any Main10 HDR10 decoder carries it, and
    // the display gates the claim.
    return DecoderProbe(
      videoDecode = detailed.sortedWith(compareBy({ it["codec"] as String }, { it["decoder_name"] as String })),
      hdr = mapOf(
        "hdr10" to (hdr10 && hdrSurvives),
        "hdr10_plus" to (hdr10Plus && hdrSurvives),
        "hlg" to (hdr10 && hdrSurvives),
        "dolby_vision_profiles" to dvProfiles,
        "dolby_vision_profile_levels" to dvLevels
      )
    )
  }

  /**
   * The active display's HDR output with its evidence tier: `exact` for a
   * successful probe (a confirmed SDR panel included), `unknown` when the
   * platform could not answer, which the server must not read as SDR.
   */
  private fun displayProbe(context: Context): Map<String, Any?> {
    val display = currentDisplay(context)
      ?: return mapOf("hdr_evidence" to "unknown", "hdr_types" to hdrTypes(emptySet()))
    val types = runCatching { displayHdrTypes(context, display) }.getOrNull()
    return mapOf(
      "hdr_evidence" to if (types == null) "unknown" else "exact",
      "hdr_types" to hdrTypes(types.orEmpty()),
      "display_id" to display.displayId.toString()
    )
  }

  private fun hdrTypes(types: Set<Int>): Map<String, Any?> = mapOf(
    "hdr10" to (Display.HdrCapabilities.HDR_TYPE_HDR10 in types),
    "hdr10_plus" to (Display.HdrCapabilities.HDR_TYPE_HDR10_PLUS in types),
    "hlg" to (Display.HdrCapabilities.HDR_TYPE_HLG in types),
    // The panel reports Dolby Vision without profiles; the decoder probe
    // names them, so the panel side admits every one.
    "dolby_vision_profiles" to if (Display.HdrCapabilities.HDR_TYPE_DOLBY_VISION in types) (0..10).toList() else emptyList()
  )

  /** Null when the display could not answer; empty for a confirmed SDR output. */
  private fun displayHdrTypes(context: Context, display: Display): Set<Int>? {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
      // Android 14's forced-SDR conversion tone-maps every HDR layer, though
      // the display still lists its HDR types.
      val dm = context.getSystemService(Context.DISPLAY_SERVICE) as? DisplayManager
      val conversion = runCatching { dm?.hdrConversionMode }.getOrNull()
      if (conversion?.conversionMode == HdrConversionMode.HDR_CONVERSION_FORCE &&
        conversion.preferredHdrOutputType == Display.HdrCapabilities.HDR_TYPE_INVALID
      ) {
        return emptySet()
      }
      // Per-mode types: a panel can carry HDR10 at 4K60 but not at 4K120.
      val active = runCatching { display.mode }.getOrNull()
      if (active != null && display.supportedModes.any { it.supportedHdrTypes.isNotEmpty() }) {
        return active.supportedHdrTypes.toSet()
      }
    }
    @Suppress("DEPRECATION")
    return display.hdrCapabilities?.supportedHdrTypes?.toSet()
  }

  private fun currentDisplay(context: Context): Display? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
    runCatching { context.display }.getOrNull()
      ?: (context.getSystemService(Context.DISPLAY_SERVICE) as? DisplayManager)?.getDisplay(Display.DEFAULT_DISPLAY)
  } else {
    @Suppress("DEPRECATION")
    (context.getSystemService(Context.WINDOW_SERVICE) as? WindowManager)?.defaultDisplay
  }

  private fun videoDecodeEntry(codec: String, decoderName: String, caps: MediaCodecInfo.CodecCapabilities): Map<String, Any?> {
    val profiles = sortedSetOf<String>()
    val levels = sortedSetOf<Int>()
    val bitDepths = sortedSetOf<Int>()
    for (pl in caps.profileLevels) {
      profileName(codec, pl.profile)?.let(profiles::add)
      profileBitDepth(codec, pl.profile)?.let(bitDepths::add)
      normalizedLevel(codec, pl.level)?.let(levels::add)
    }
    val video = caps.videoCapabilities
    val limits = video?.let(::conservativeLimits)
    return mapOf(
      "codec" to codec,
      "decoder_name" to decoderName,
      "profiles" to profiles.toList(),
      "levels" to levels.toList(),
      "bit_depths" to bitDepths.toList(),
      "max_width" to limits?.first?.takeIf { it > 0 },
      "max_height" to limits?.second?.takeIf { it > 0 },
      "max_frame_rate" to limits?.third?.takeIf { it > 0.0 },
      "max_bitrate_kbps" to ((video?.bitrateRange?.upper ?: 0) / 1_000).takeIf { it > 0 },
      "hardware" to true
    )
  }

  /**
   * Width, height and frame rate. Vendor frame-rate ranges are often global
   * (an Amlogic decoder reports 960 fps though its 4K point is 30), so the
   * rate is read at the largest standard size the decoder accepts and, on
   * API 29+, capped by its performance points.
   */
  private fun conservativeLimits(video: MediaCodecInfo.VideoCapabilities): Triple<Int, Int, Double> {
    fun supported(size: Pair<Int, Int>) = runCatching { video.isSizeSupported(size.first, size.second) }.getOrDefault(false)
    val largest = STANDARD_VIDEO_SIZES.firstOrNull(::supported)
    val points = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
      runCatching { video.supportedPerformancePoints }.getOrNull().orEmpty()
    } else {
      emptyList()
    }
    val pointBounded = if (points.isEmpty()) {
      null
    } else {
      STANDARD_VIDEO_SIZES.firstOrNull { size ->
        supported(size) && points.any { it.covers(MediaCodecInfo.VideoCapabilities.PerformancePoint(size.first, size.second, 24)) }
      }
    }
    val rateSize = pointBounded ?: largest
    val rangeUpper = rateSize?.let { (w, h) -> runCatching { video.getSupportedFrameRatesFor(w, h).upper }.getOrNull() }
      ?: video.supportedFrameRates?.upper?.toDouble() ?: 0.0
    val pointRate = if (points.isNotEmpty() && rateSize != null) {
      STANDARD_FRAME_RATES.firstOrNull { rate ->
        val wanted = MediaCodecInfo.VideoCapabilities.PerformancePoint(rateSize.first, rateSize.second, rate)
        points.any { it.covers(wanted) }
      }?.toDouble()
    } else {
      null
    }
    return Triple(
      pointBounded?.first ?: video.supportedWidths?.upper ?: 0,
      pointBounded?.second ?: video.supportedHeights?.upper ?: 0,
      pointRate?.let { minOf(rangeUpper, it) } ?: rangeUpper
    )
  }

  private val STANDARD_VIDEO_SIZES = listOf(
    7680 to 4320,
    4096 to 2160,
    3840 to 2160,
    2560 to 1440,
    1920 to 1080,
    1280 to 720,
    720 to 576,
    720 to 480
  )

  private val STANDARD_FRAME_RATES = listOf(240, 200, 120, 100, 60, 50, 48, 30, 25, 24)

  private fun codecName(mimeType: String): String? = when (mimeType.lowercase(Locale.ROOT)) {
    "video/avc" -> "h264"
    "video/hevc" -> "hevc"
    "video/x-vnd.on2.vp9" -> "vp9"
    "video/x-vnd.on2.vp8" -> "vp8"
    "video/av01" -> "av1"
    "video/dolby-vision" -> "dolby_vision"
    "video/mpeg2" -> "mpeg2video"
    "video/mp4v-es" -> "mpeg4"
    "video/3gpp" -> "h263"
    "video/wvc1", "video/x-ms-wmv", "video/vc1" -> "vc1"
    else -> null
  }

  // Profile names use FFmpeg's vocabulary, which is what the server stores.
  private fun profileName(codec: String, profile: Int): String? = when (codec) {
    "h264" -> when (profile) {
      CodecProfileLevel.AVCProfileBaseline -> "baseline"
      CodecProfileLevel.AVCProfileMain -> "main"
      CodecProfileLevel.AVCProfileExtended -> "extended"
      CodecProfileLevel.AVCProfileHigh -> "high"
      CodecProfileLevel.AVCProfileHigh10 -> "high 10"
      CodecProfileLevel.AVCProfileHigh422 -> "high 4:2:2"
      CodecProfileLevel.AVCProfileHigh444 -> "high 4:4:4 predictive"
      else -> null
    }
    "hevc" -> when (profile) {
      CodecProfileLevel.HEVCProfileMain -> "main"
      CodecProfileLevel.HEVCProfileMain10,
      CodecProfileLevel.HEVCProfileMain10HDR10,
      CodecProfileLevel.HEVCProfileMain10HDR10Plus -> "main 10"
      else -> null
    }
    "dolby_vision" -> dolbyVisionProfileNumber(profile)?.let { "profile $it" }
    "vp9" -> when (profile) {
      CodecProfileLevel.VP9Profile0 -> "profile 0"
      CodecProfileLevel.VP9Profile1 -> "profile 1"
      CodecProfileLevel.VP9Profile2,
      CodecProfileLevel.VP9Profile2HDR,
      CodecProfileLevel.VP9Profile2HDR10Plus -> "profile 2"
      CodecProfileLevel.VP9Profile3,
      CodecProfileLevel.VP9Profile3HDR,
      CodecProfileLevel.VP9Profile3HDR10Plus -> "profile 3"
      else -> null
    }
    "av1" -> when (profile) {
      CodecProfileLevel.AV1ProfileMain8,
      CodecProfileLevel.AV1ProfileMain10,
      CodecProfileLevel.AV1ProfileMain10HDR10,
      CodecProfileLevel.AV1ProfileMain10HDR10Plus -> "main"
      else -> null
    }
    "mpeg2video" -> when (profile) {
      CodecProfileLevel.MPEG2ProfileSimple -> "simple"
      CodecProfileLevel.MPEG2ProfileMain -> "main"
      CodecProfileLevel.MPEG2Profile422 -> "4:2:2"
      CodecProfileLevel.MPEG2ProfileSNR -> "snr scalable"
      CodecProfileLevel.MPEG2ProfileSpatial -> "spatially scalable"
      CodecProfileLevel.MPEG2ProfileHigh -> "high"
      else -> null
    }
    "mpeg4" -> when (profile) {
      CodecProfileLevel.MPEG4ProfileSimple -> "simple profile"
      CodecProfileLevel.MPEG4ProfileSimpleScalable -> "simple scalable profile"
      CodecProfileLevel.MPEG4ProfileCore -> "core profile"
      CodecProfileLevel.MPEG4ProfileMain -> "main profile"
      CodecProfileLevel.MPEG4ProfileNbit -> "n-bit profile"
      CodecProfileLevel.MPEG4ProfileScalableTexture -> "scalable texture profile"
      CodecProfileLevel.MPEG4ProfileSimpleFace,
      CodecProfileLevel.MPEG4ProfileSimpleFBA -> "simple face animation profile"
      CodecProfileLevel.MPEG4ProfileBasicAnimated -> "basic animated texture profile"
      CodecProfileLevel.MPEG4ProfileHybrid -> "hybrid profile"
      CodecProfileLevel.MPEG4ProfileAdvancedRealTime -> "advanced real time simple profile"
      CodecProfileLevel.MPEG4ProfileCoreScalable -> "code scalable profile"
      CodecProfileLevel.MPEG4ProfileAdvancedCoding -> "advanced coding profile"
      CodecProfileLevel.MPEG4ProfileAdvancedCore -> "advanced core profile"
      CodecProfileLevel.MPEG4ProfileAdvancedScalable -> "advanced scalable texture profile"
      CodecProfileLevel.MPEG4ProfileAdvancedSimple -> "advanced simple profile"
      else -> null
    }
    "vp8" -> if (profile == CodecProfileLevel.VP8ProfileMain) "main" else null
    "h263" -> when (profile) {
      CodecProfileLevel.H263ProfileBaseline -> "baseline"
      CodecProfileLevel.H263ProfileH320Coding -> "h320 coding"
      CodecProfileLevel.H263ProfileBackwardCompatible -> "backward compatible"
      CodecProfileLevel.H263ProfileISWV2 -> "iswv2"
      CodecProfileLevel.H263ProfileISWV3 -> "iswv3"
      CodecProfileLevel.H263ProfileHighCompression -> "high compression"
      CodecProfileLevel.H263ProfileInternet -> "internet"
      CodecProfileLevel.H263ProfileInterlace -> "interlace"
      CodecProfileLevel.H263ProfileHighLatency -> "high latency"
      else -> null
    }
    else -> null
  }

  private fun profileBitDepth(codec: String, profile: Int): Int? = when (codec) {
    "h264" -> when (profile) {
      CodecProfileLevel.AVCProfileHigh10,
      CodecProfileLevel.AVCProfileHigh422,
      CodecProfileLevel.AVCProfileHigh444 -> 10
      CodecProfileLevel.AVCProfileBaseline,
      CodecProfileLevel.AVCProfileMain,
      CodecProfileLevel.AVCProfileExtended,
      CodecProfileLevel.AVCProfileHigh -> 8
      else -> null
    }
    "hevc" -> when (profile) {
      CodecProfileLevel.HEVCProfileMain -> 8
      CodecProfileLevel.HEVCProfileMain10,
      CodecProfileLevel.HEVCProfileMain10HDR10,
      CodecProfileLevel.HEVCProfileMain10HDR10Plus -> 10
      else -> null
    }
    "vp9" -> when (profile) {
      CodecProfileLevel.VP9Profile0, CodecProfileLevel.VP9Profile1 -> 8
      CodecProfileLevel.VP9Profile2,
      CodecProfileLevel.VP9Profile2HDR,
      CodecProfileLevel.VP9Profile2HDR10Plus,
      CodecProfileLevel.VP9Profile3,
      CodecProfileLevel.VP9Profile3HDR,
      CodecProfileLevel.VP9Profile3HDR10Plus -> 10
      else -> null
    }
    "av1" -> when (profile) {
      CodecProfileLevel.AV1ProfileMain8 -> 8
      CodecProfileLevel.AV1ProfileMain10,
      CodecProfileLevel.AV1ProfileMain10HDR10,
      CodecProfileLevel.AV1ProfileMain10HDR10Plus -> 10
      else -> null
    }
    "dolby_vision" -> if (dolbyVisionProfileNumber(profile) != null) 10 else null
    else -> if (profileName(codec, profile) != null) 8 else null
  }

  private fun dolbyVisionProfileNumber(profile: Int): Int? = when (profile) {
    CodecProfileLevel.DolbyVisionProfileDvavPer -> 0
    CodecProfileLevel.DolbyVisionProfileDvavPen -> 1
    CodecProfileLevel.DolbyVisionProfileDvheDer -> 2
    CodecProfileLevel.DolbyVisionProfileDvheDen -> 3
    CodecProfileLevel.DolbyVisionProfileDvheDtr -> 4
    CodecProfileLevel.DolbyVisionProfileDvheStn -> 5
    CodecProfileLevel.DolbyVisionProfileDvheDth -> 6
    CodecProfileLevel.DolbyVisionProfileDvheDtb -> 7
    CodecProfileLevel.DolbyVisionProfileDvheSt -> 8
    CodecProfileLevel.DolbyVisionProfileDvavSe -> 9
    else -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && profile == CodecProfileLevel.DolbyVisionProfileDvav110) 10 else null
  }

  private fun dolbyVisionLevelNumber(level: Int): Int? = when (level) {
    CodecProfileLevel.DolbyVisionLevelHd24 -> 1
    CodecProfileLevel.DolbyVisionLevelHd30 -> 2
    CodecProfileLevel.DolbyVisionLevelFhd24 -> 3
    CodecProfileLevel.DolbyVisionLevelFhd30 -> 4
    CodecProfileLevel.DolbyVisionLevelFhd60 -> 5
    CodecProfileLevel.DolbyVisionLevelUhd24 -> 6
    CodecProfileLevel.DolbyVisionLevelUhd30 -> 7
    CodecProfileLevel.DolbyVisionLevelUhd48 -> 8
    CodecProfileLevel.DolbyVisionLevelUhd60 -> 9
    else -> when {
      Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU -> null
      level == CodecProfileLevel.DolbyVisionLevelUhd120 -> 10
      level == CodecProfileLevel.DolbyVisionLevel8k30 -> 11
      level == CodecProfileLevel.DolbyVisionLevel8k60 -> 12
      else -> null
    }
  }

  private fun normalizedLevel(codec: String, level: Int): Int? = when (codec) {
    "h264" -> AVC_LEVELS[level]
    "hevc" -> HEVC_LEVELS[level]
    "dolby_vision" -> dolbyVisionLevelNumber(level)
    else -> null
  }

  private val AVC_LEVELS = mapOf(
    CodecProfileLevel.AVCLevel1 to 10,
    CodecProfileLevel.AVCLevel1b to 9,
    CodecProfileLevel.AVCLevel11 to 11,
    CodecProfileLevel.AVCLevel12 to 12,
    CodecProfileLevel.AVCLevel13 to 13,
    CodecProfileLevel.AVCLevel2 to 20,
    CodecProfileLevel.AVCLevel21 to 21,
    CodecProfileLevel.AVCLevel22 to 22,
    CodecProfileLevel.AVCLevel3 to 30,
    CodecProfileLevel.AVCLevel31 to 31,
    CodecProfileLevel.AVCLevel32 to 32,
    CodecProfileLevel.AVCLevel4 to 40,
    CodecProfileLevel.AVCLevel41 to 41,
    CodecProfileLevel.AVCLevel42 to 42,
    CodecProfileLevel.AVCLevel5 to 50,
    CodecProfileLevel.AVCLevel51 to 51,
    CodecProfileLevel.AVCLevel52 to 52,
    CodecProfileLevel.AVCLevel6 to 60,
    CodecProfileLevel.AVCLevel61 to 61,
    CodecProfileLevel.AVCLevel62 to 62
  )

  private val HEVC_LEVELS = mapOf(
    CodecProfileLevel.HEVCMainTierLevel1 to 30,
    CodecProfileLevel.HEVCHighTierLevel1 to 30,
    CodecProfileLevel.HEVCMainTierLevel2 to 60,
    CodecProfileLevel.HEVCHighTierLevel2 to 60,
    CodecProfileLevel.HEVCMainTierLevel21 to 63,
    CodecProfileLevel.HEVCHighTierLevel21 to 63,
    CodecProfileLevel.HEVCMainTierLevel3 to 90,
    CodecProfileLevel.HEVCHighTierLevel3 to 90,
    CodecProfileLevel.HEVCMainTierLevel31 to 93,
    CodecProfileLevel.HEVCHighTierLevel31 to 93,
    CodecProfileLevel.HEVCMainTierLevel4 to 120,
    CodecProfileLevel.HEVCHighTierLevel4 to 120,
    CodecProfileLevel.HEVCMainTierLevel41 to 123,
    CodecProfileLevel.HEVCHighTierLevel41 to 123,
    CodecProfileLevel.HEVCMainTierLevel5 to 150,
    CodecProfileLevel.HEVCHighTierLevel5 to 150,
    CodecProfileLevel.HEVCMainTierLevel51 to 153,
    CodecProfileLevel.HEVCHighTierLevel51 to 153,
    CodecProfileLevel.HEVCMainTierLevel52 to 156,
    CodecProfileLevel.HEVCHighTierLevel52 to 156,
    CodecProfileLevel.HEVCMainTierLevel6 to 180,
    CodecProfileLevel.HEVCHighTierLevel6 to 180,
    CodecProfileLevel.HEVCMainTierLevel61 to 183,
    CodecProfileLevel.HEVCHighTierLevel61 to 183,
    CodecProfileLevel.HEVCMainTierLevel62 to 186,
    CodecProfileLevel.HEVCHighTierLevel62 to 186
  )
}
