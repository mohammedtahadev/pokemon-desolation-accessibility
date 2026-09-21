/* beacon.c - Steam Audio HRTF navigation beacon for Pokemon Reborn (v2)
 * Written by Mohammed Taha (mohammedtahadev) with the help of Claude
 * (Anthropic's AI).
 *
 * v2 adds REAR-ONLY disambiguation cues on top of Steam Audio's HRTF, because
 * generic (non-personalised) HRTFs render left/right well but front/back
 * weakly:
    - pitch:    LOWER behind only (front and sides keep natural pitch)
 *    - muffling: a one-pole low-pass makes sounds behind you duller
 *    - gain:     slightly quieter behind
 * The beacon sound is decoded once into memory and played through a
 * fractional playhead, which is what makes real-time pitch shifting possible.
 *
 * Build: gcc -O2 -shared -o beacon.dll beacon.c phonon.dll -I. -lm
 */

#define MA_NO_FLAC
#define MINIAUDIO_IMPLEMENTATION
#include "miniaudio.h"

#include "phonon.h"

#include <string.h>
#include <stdio.h>
#include <math.h>

#define BEACON_FRAME_SIZE  512
#define BEACON_SAMPLE_RATE 48000

static IPLContext        g_ctx    = NULL;
static IPLHRTF           g_hrtf   = NULL;
static IPLBinauralEffect g_effect = NULL;

static ma_device g_device;
static int g_deviceInit = 0;
static int g_ready      = 0;
static int g_playing    = 0;

/* Beacon sound held in memory (mono f32) so we can pitch-shift it. */
static float*    g_pcm       = NULL;
static ma_uint64 g_pcmFrames = 0;
static double    g_playhead  = 0.0;

/* Direction to the beacon, listener-relative (+x right, +y up, -z forward). */
static volatile float g_dirX = 0.0f, g_dirY = 0.0f, g_dirZ = -1.0f;
static volatile float g_gain = 1.0f;

/* Front/back cue targets (set on the game thread, smoothed on the audio thread). */
static volatile float g_pitchTarget = 1.0f;   /* playback rate multiplier  */
static volatile float g_lpTarget    = 1.0f;   /* 1 = open, ->0 = muffled   */
static volatile float g_backGain    = 1.0f;

/* Tunables, adjustable at runtime from Ruby. */
static volatile float g_pitchRange = 0.22f;   /* +/- around 1.0            */
static volatile float g_backDamp   = 0.85f;   /* how muffled behind sounds */

static float g_pitchCur = 1.0f;
static float g_lpCur    = 1.0f;
static float g_lpState  = 0.0f;

static char g_err[512] = {0};

static float  g_mono[BEACON_FRAME_SIZE];
static float  g_outL[BEACON_FRAME_SIZE];
static float  g_outR[BEACON_FRAME_SIZE];
static float* g_inPtrs[1];
static float* g_outPtrs[2];
static IPLAudioBuffer g_inBuf;
static IPLAudioBuffer g_outBuf;

static int g_pending    = 0;
static int g_pendingPos = 0;

static void beacon_render_block(void)
{
    /* Smooth the cue parameters so direction changes never click. */
    g_pitchCur += (g_pitchTarget - g_pitchCur) * 0.25f;
    g_lpCur    += (g_lpTarget    - g_lpCur)    * 0.25f;

    float rate = g_pitchCur;
    if (rate < 0.25f) rate = 0.25f;
    if (rate > 4.0f)  rate = 4.0f;

    float a = g_lpCur;
    if (a < 0.02f) a = 0.02f;
    if (a > 1.0f)  a = 1.0f;

    if (g_pcm == NULL || g_pcmFrames == 0) {
        memset(g_mono, 0, sizeof(g_mono));
    } else {
        for (int i = 0; i < BEACON_FRAME_SIZE; ++i) {
            /* looping fractional read = pitch shift */
            while (g_playhead >= (double)g_pcmFrames) g_playhead -= (double)g_pcmFrames;
            ma_uint64 i0 = (ma_uint64)g_playhead;
            ma_uint64 i1 = i0 + 1;
            if (i1 >= g_pcmFrames) i1 = 0;
            float frac = (float)(g_playhead - (double)i0);
            float s = g_pcm[i0] * (1.0f - frac) + g_pcm[i1] * frac;

            /* one-pole low-pass: duller the further behind the beacon is */
            g_lpState += a * (s - g_lpState);
            g_mono[i] = g_lpState;

            g_playhead += (double)rate;
        }
    }

    IPLBinauralEffectParams p;
    memset(&p, 0, sizeof(p));
    p.direction.x   = g_dirX;
    p.direction.y   = g_dirY;
    p.direction.z   = g_dirZ;
    p.interpolation = IPL_HRTFINTERPOLATION_BILINEAR;
    p.spatialBlend  = 1.0f;
    p.hrtf          = g_hrtf;
    p.peakDelays    = NULL;

    iplBinauralEffectApply(g_effect, &p, &g_inBuf, &g_outBuf);

    g_pending    = BEACON_FRAME_SIZE;
    g_pendingPos = 0;
}

static void data_callback(ma_device* dev, void* out, const void* in, ma_uint32 frameCount)
{
    float* o = (float*)out;
    ma_uint32 written = 0;
    (void)dev; (void)in;

    if (!g_ready) { memset(o, 0, (size_t)frameCount * 2 * sizeof(float)); return; }

    while (written < frameCount) {
        if (g_pending == 0) beacon_render_block();

        ma_uint32 n = frameCount - written;
        if ((ma_uint32)g_pending < n) n = (ma_uint32)g_pending;

        float gain = g_gain * g_backGain;
        for (ma_uint32 i = 0; i < n; ++i) {
            o[(written + i) * 2 + 0] = g_outL[g_pendingPos + i] * gain;
            o[(written + i) * 2 + 1] = g_outR[g_pendingPos + i] * gain;
        }
        g_pendingPos += (int)n;
        g_pending    -= (int)n;
        written      += n;
    }
}

__declspec(dllexport) const char* beacon_last_error(void) { return g_err; }

__declspec(dllexport) int beacon_init(const char* soundPath)
{
    if (g_ready) return 0;
    g_err[0] = '\0';

    IPLContextSettings cs;
    memset(&cs, 0, sizeof(cs));
    cs.version = STEAMAUDIO_VERSION;
    if (iplContextCreate(&cs, &g_ctx) != IPL_STATUS_SUCCESS) {
        snprintf(g_err, sizeof(g_err), "iplContextCreate failed");
        return -1;
    }

    IPLAudioSettings as;
    memset(&as, 0, sizeof(as));
    as.samplingRate = BEACON_SAMPLE_RATE;
    as.frameSize    = BEACON_FRAME_SIZE;

    IPLHRTFSettings hs;
    memset(&hs, 0, sizeof(hs));
    hs.type     = IPL_HRTFTYPE_DEFAULT;
    hs.volume   = 1.0f;
    hs.normType = IPL_HRTFNORMTYPE_NONE;
    if (iplHRTFCreate(g_ctx, &as, &hs, &g_hrtf) != IPL_STATUS_SUCCESS) {
        snprintf(g_err, sizeof(g_err), "iplHRTFCreate failed");
        return -2;
    }

    IPLBinauralEffectSettings es;
    memset(&es, 0, sizeof(es));
    es.hrtf = g_hrtf;
    if (iplBinauralEffectCreate(g_ctx, &as, &es, &g_effect) != IPL_STATUS_SUCCESS) {
        snprintf(g_err, sizeof(g_err), "iplBinauralEffectCreate failed");
        return -3;
    }

    g_inPtrs[0] = g_mono;
    g_inBuf.numChannels = 1;
    g_inBuf.numSamples  = BEACON_FRAME_SIZE;
    g_inBuf.data        = g_inPtrs;

    g_outPtrs[0] = g_outL;
    g_outPtrs[1] = g_outR;
    g_outBuf.numChannels = 2;
    g_outBuf.numSamples  = BEACON_FRAME_SIZE;
    g_outBuf.data        = g_outPtrs;

    /* Decode the whole beacon sound into memory as MONO f32 at our rate. */
    ma_decoder_config dc = ma_decoder_config_init(ma_format_f32, 1, BEACON_SAMPLE_RATE);
    void* pcm = NULL;
    ma_uint64 frames = 0;
    if (ma_decode_file(soundPath, &dc, &frames, &pcm) != MA_SUCCESS || frames == 0) {
        snprintf(g_err, sizeof(g_err),
                 "could not decode beacon sound: %s (WAV or MP3 only - OGG is not supported)",
                 soundPath ? soundPath : "(null)");
        return -4;
    }
    g_pcm       = (float*)pcm;
    g_pcmFrames = frames;
    g_playhead  = 0.0;
    g_lpState   = 0.0f;

    ma_device_config cfg = ma_device_config_init(ma_device_type_playback);
    cfg.playback.format   = ma_format_f32;
    cfg.playback.channels = 2;
    cfg.sampleRate        = BEACON_SAMPLE_RATE;
    cfg.dataCallback      = data_callback;
    if (ma_device_init(NULL, &cfg, &g_device) != MA_SUCCESS) {
        snprintf(g_err, sizeof(g_err), "ma_device_init failed (no audio output device?)");
        return -5;
    }
    g_deviceInit = 1;
    g_ready = 1;
    snprintf(g_err, sizeof(g_err), "ok");
    return 0;
}

/* +x right, +y up, -z forward. Also derives the front/back cues. */
__declspec(dllexport) void beacon_set_direction(float x, float y, float z)
{
    float len = (float)sqrt((double)(x * x + y * y + z * z));
    if (len < 0.0001f) { x = 0.0f; y = 0.0f; z = -1.0f; len = 1.0f; }
    x /= len; y /= len; z /= len;
    g_dirX = x; g_dirY = y; g_dirZ = z;

    /* forwardness: +1 straight ahead, -1 straight behind */
    float f = -z;
    /* Rear-only cue: 0 across the whole FRONT hemisphere AND the sides,
       ramping to 1 directly behind. Front and sides therefore stay pure
       Steam Audio HRTF at natural pitch - we only disambiguate the back. */
    float backness = -f;
    if (backness < 0.0f) backness = 0.0f;

    g_pitchTarget = 1.0f - (g_pitchRange * backness); /* never raised, only LOWER behind */
    g_lpTarget    = 1.0f - (g_backDamp  * backness);  /* muffled only behind */
    g_backGain    = 1.0f - (0.20f * backness);        /* a touch quieter behind */
}

__declspec(dllexport) void beacon_set_gain(float g)
{
    if (g < 0.0f) g = 0.0f;
    if (g > 1.0f) g = 1.0f;
    g_gain = g;
}

/* Tune the front/back cues live: pitchRange ~0.0-0.6, backDamp 0.0-0.95 */
__declspec(dllexport) void beacon_set_tuning(float pitchRange, float backDamp)
{
    if (pitchRange < 0.0f) pitchRange = 0.0f;
    if (pitchRange > 0.6f) pitchRange = 0.6f;
    if (backDamp < 0.0f)   backDamp = 0.0f;
    if (backDamp > 0.95f)  backDamp = 0.95f;
    g_pitchRange = pitchRange;
    g_backDamp   = backDamp;
}

__declspec(dllexport) int beacon_start(void)
{
    if (!g_ready) return -1;
    if (g_playing) return 0;
    if (ma_device_start(&g_device) != MA_SUCCESS) {
        snprintf(g_err, sizeof(g_err), "ma_device_start failed");
        return -2;
    }
    g_playing = 1;
    return 0;
}

__declspec(dllexport) void beacon_stop(void)
{
    if (g_ready && g_playing) { ma_device_stop(&g_device); g_playing = 0; }
}

__declspec(dllexport) void beacon_shutdown(void)
{
    beacon_stop();
    if (g_deviceInit) { ma_device_uninit(&g_device); g_deviceInit = 0; }
    if (g_pcm) { ma_free(g_pcm, NULL); g_pcm = NULL; g_pcmFrames = 0; }
    if (g_effect) { iplBinauralEffectRelease(&g_effect); g_effect = NULL; }
    if (g_hrtf)   { iplHRTFRelease(&g_hrtf);             g_hrtf = NULL; }
    if (g_ctx)    { iplContextRelease(&g_ctx);           g_ctx = NULL; }
    g_ready = 0;
}

__declspec(dllexport) int beacon_ready(void) { return g_ready; }
