#import "SGDSPEffects.h"
#import <math.h>
#import <stdlib.h>
#import <string.h>

enum {
    kBinauralTapCount = 4,
    kBinauralBufferFrames = 4096
};

typedef struct {
    int delaySamples;
    float gainL;
    float gainR;
} BinauralTap;

struct SGDSPBinaural {
    double rate;
    int roomType;
    float bufferL[kBinauralBufferFrames];
    float bufferR[kBinauralBufferFrames];
    int writeIndex;
    BinauralTap taps[kBinauralTapCount];
    float wetLevel;
    float dryLevel;
    SGBiquad roomDampL;
    SGBiquadState dampStateL;
    SGBiquad roomDampR;
    SGBiquadState dampStateR;
};

static void configureRoom(SGDSPBinaural *dsp, int roomType) {
    dsp->roomType = roomType;
    double rate = dsp->rate;

    // Room configurations:
    // 0: Studio (intimate, tight reflections, minimal decay)
    // 1: Living Room (warm, natural acoustics, moderate reflections)
    // 2: Concert Hall (large, spaced reflections, spacious)
    // 3: Ambient Chamber (diffuse, deep reflections)
    double delaysMS[4][kBinauralTapCount] = {
        { 6.0,  11.0, 18.0, 24.0 },  // Studio
        { 12.0, 22.0, 31.0, 42.0 },  // Living Room
        { 24.0, 45.0, 62.0, 85.0 },  // Concert Hall
        { 35.0, 68.0, 95.0, 130.0 }  // Chamber
    };

    float tapGains[4][kBinauralTapCount] = {
        { 0.35f, 0.25f, 0.18f, 0.10f }, // Studio
        { 0.40f, 0.30f, 0.22f, 0.15f }, // Living Room
        { 0.45f, 0.35f, 0.28f, 0.20f }, // Concert Hall
        { 0.50f, 0.40f, 0.32f, 0.25f }  // Chamber
    };

    float dampCutoffs[4] = { 6500.0f, 4800.0f, 3800.0f, 3200.0f };
    float wetLevels[4]   = { 0.25f,   0.35f,   0.45f,   0.55f   };

    int type = roomType < 0 ? 0 : (roomType > 3 ? 3 : roomType);

    for (int t = 0; t < kBinauralTapCount; t++) {
        int delay = (int)(delaysMS[type][t] * 0.001 * rate);
        if (delay >= kBinauralBufferFrames) delay = kBinauralBufferFrames - 1;
        dsp->taps[t].delaySamples = delay;
        // Alternating contralateral reflections simulate stereo acoustic boundary bounces
        if (t % 2 == 0) {
            dsp->taps[t].gainL = tapGains[type][t] * 0.8f;
            dsp->taps[t].gainR = tapGains[type][t] * 0.5f;
        } else {
            dsp->taps[t].gainL = tapGains[type][t] * 0.5f;
            dsp->taps[t].gainR = tapGains[type][t] * 0.8f;
        }
    }

    dsp->wetLevel = wetLevels[type];
    dsp->dryLevel = 1.0f - (dsp->wetLevel * 0.3f);
    dsp->roomDampL = SGBiquadLowPass(rate, dampCutoffs[type], 0.707);
    dsp->roomDampR = SGBiquadLowPass(rate, dampCutoffs[type], 0.707);
}

SGDSPBinaural *SGDSPBinauralCreate(double rate, int roomType) {
    SGDSPBinaural *dsp = calloc(1, sizeof *dsp);
    if (!dsp) return NULL;
    dsp->rate = rate > 0 ? rate : 44100.0;
    configureRoom(dsp, roomType);
    return dsp;
}

void SGDSPBinauralSet(SGDSPBinaural *dsp, int roomType) {
    if (!dsp) return;
    configureRoom(dsp, roomType);
}

void SGDSPBinauralRun(void *state, float *left, float *right, uint32_t frames) {
    SGDSPBinaural *dsp = state;
    if (!dsp) return;

    int wIdx = dsp->writeIndex;
    float wet = dsp->wetLevel;
    float dry = dsp->dryLevel;

    for (uint32_t i = 0; i < frames; i++) {
        float inL = left[i];
        float inR = right[i];

        dsp->bufferL[wIdx] = inL;
        dsp->bufferR[wIdx] = inR;

        float refL = 0.0f;
        float refR = 0.0f;

        for (int t = 0; t < kBinauralTapCount; t++) {
            int rIdx = (wIdx - dsp->taps[t].delaySamples + kBinauralBufferFrames) % kBinauralBufferFrames;
            refL += dsp->bufferL[rIdx] * dsp->taps[t].gainL;
            refR += dsp->bufferR[rIdx] * dsp->taps[t].gainR;
        }

        // Room absorption damping
        refL = (float)SGBiquadTick(&dsp->roomDampL, &dsp->dampStateL, refL);
        refR = (float)SGBiquadTick(&dsp->roomDampR, &dsp->dampStateR, refR);

        left[i]  = inL * dry + refL * wet;
        right[i] = inR * dry + refR * wet;

        wIdx = (wIdx + 1) % kBinauralBufferFrames;
    }

    dsp->writeIndex = wIdx;
}

void SGDSPBinauralFree(void *dsp) {
    free(dsp);
}
