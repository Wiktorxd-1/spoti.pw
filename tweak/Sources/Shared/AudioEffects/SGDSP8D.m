#import "SGDSPEffects.h"
#import <math.h>
#import <stdlib.h>
#import <string.h>

enum { kMaxDelayFrames = 128 };

struct SGDSP8D {
    double rate;
    double phase;
    double phaseIncrement;
    float delayBufferL[kMaxDelayFrames];
    float delayBufferR[kMaxDelayFrames];
    int writeIndex;
    SGBiquad shadowFilterL;
    SGBiquadState shadowStateL;
    SGBiquad shadowFilterR;
    SGBiquadState shadowStateR;
};

SGDSP8D *SGDSP8DCreate(double rate, double rotationSeconds) {
    SGDSP8D *dsp = calloc(1, sizeof *dsp);
    if (!dsp) return NULL;
    dsp->rate = rate > 0 ? rate : 44100.0;
    dsp->shadowFilterL = SGBiquadLowPass(dsp->rate, 4200.0, 0.707);
    dsp->shadowFilterR = SGBiquadLowPass(dsp->rate, 4200.0, 0.707);
    SGDSP8DSet(dsp, rotationSeconds);
    return dsp;
}

void SGDSP8DSet(SGDSP8D *dsp, double rotationSeconds) {
    if (!dsp) return;
    double sec = fmax(1.0, fmin(60.0, rotationSeconds));
    dsp->phaseIncrement = (2.0 * M_PI) / (dsp->rate * sec);
}

void SGDSP8DRun(void *state, float *left, float *right, uint32_t frames) {
    SGDSP8D *dsp = state;
    if (!dsp) return;

    double phase = dsp->phase;
    double inc = dsp->phaseIncrement;
    int wIdx = dsp->writeIndex;

    for (uint32_t i = 0; i < frames; i++) {
        float inL = left[i];
        float inR = right[i];

        dsp->delayBufferL[wIdx] = inL;
        dsp->delayBufferR[wIdx] = inR;

        // Angle theta: 0 is front, pi/2 is right, pi is back, 3pi/2 is left
        double theta = phase;
        double pan = sin(theta);   // -1 = left, +1 = right
        double depth = cos(theta); // +1 = front, -1 = back

        // Equal-power circular panning
        // angle in [0, pi/2] for stereo gains
        double panAngle = (pan + 1.0) * (M_PI * 0.25);
        double gainL = cos(panAngle);
        double gainR = sin(panAngle);

        // Interaural Time Difference (ITD): ~0.65ms max delay (approx 29 samples at 44.1k)
        double maxDelaySamples = (dsp->rate * 0.00065);
        double delayL = (pan > 0) ? (pan * maxDelaySamples) : 0;
        double delayR = (pan < 0) ? (-pan * maxDelaySamples) : 0;

        // Read delayed samples with linear interpolation
        int readIdxL = (int)(wIdx - delayL + kMaxDelayFrames) % kMaxDelayFrames;
        int readIdxR = (int)(wIdx - delayR + kMaxDelayFrames) % kMaxDelayFrames;

        float delayedL = dsp->delayBufferL[readIdxL];
        float delayedR = dsp->delayBufferR[readIdxR];

        // Head shadow attenuation for opposite ear
        if (pan > 0.1) {
            float filteredL = (float)SGBiquadTick(&dsp->shadowFilterL, &dsp->shadowStateL, delayedL);
            float blend = (float)fmin(1.0, pan * 0.7);
            delayedL = delayedL * (1.0f - blend) + filteredL * blend;
        }
        if (pan < -0.1) {
            float filteredR = (float)SGBiquadTick(&dsp->shadowFilterR, &dsp->shadowStateR, delayedR);
            float blend = (float)fmin(1.0, (-pan) * 0.7);
            delayedR = delayedR * (1.0f - blend) + filteredR * blend;
        }

        // Behind-the-head subtle high-frequency presence dip
        if (depth < 0) {
            float backAtten = (float)(1.0 + depth * 0.15); // gentle 15% attenuation when behind
            gainL *= backAtten;
            gainR *= backAtten;
        }

        left[i] = (float)(delayedL * gainL * 1.2);
        right[i] = (float)(delayedR * gainR * 1.2);

        wIdx = (wIdx + 1) % kMaxDelayFrames;
        phase += inc;
        if (phase >= 2.0 * M_PI) phase -= 2.0 * M_PI;
    }

    dsp->phase = phase;
    dsp->writeIndex = wIdx;
}

void SGDSP8DFree(void *dsp) {
    free(dsp);
}
