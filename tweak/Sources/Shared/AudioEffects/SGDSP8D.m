#import "SGDSPEffects.h"
#import <math.h>
#import <stdlib.h>
#import <string.h>

enum { kMaxDelayFrames = 256 };

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
    dsp->shadowFilterL = SGBiquadLowPass(dsp->rate, 3800.0, 0.707);
    dsp->shadowFilterR = SGBiquadLowPass(dsp->rate, 3800.0, 0.707);
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
    double maxDelaySamples = dsp->rate * 0.00065; // ~0.65ms interaural time difference

    for (uint32_t i = 0; i < frames; i++) {
        float inL = left[i];
        float inR = right[i];

        dsp->delayBufferL[wIdx] = inL;
        dsp->delayBufferR[wIdx] = inR;

        // Azimuth theta: 0 = front, pi/2 = right, pi = back, 3pi/2 = left
        double theta = phase;

        // Virtual left and right speakers positioned 30 deg (+/- 0.52 rad) from center
        double thetaL = theta - 0.52;
        double thetaR = theta + 0.52;

        // Panning gains and delays for Virtual Left Speaker
        double panL = sin(thetaL);
        double depthL = cos(thetaL);
        double panAngleL = (panL + 1.0) * (M_PI * 0.25);
        double gLL = cos(panAngleL);
        double gLR = sin(panAngleL);
        if (depthL < 0) {
            double backAtten = 1.0 + depthL * 0.18;
            gLL *= backAtten;
            gLR *= backAtten;
        }

        // Panning gains and delays for Virtual Right Speaker
        double panR = sin(thetaR);
        double depthR = cos(thetaR);
        double panAngleR = (panR + 1.0) * (M_PI * 0.25);
        double gRL = cos(panAngleR);
        double gRR = sin(panAngleR);
        if (depthR < 0) {
            double backAtten = 1.0 + depthR * 0.18;
            gRL *= backAtten;
            gRR *= backAtten;
        }

        // Delay lookup for opposite ears
        double delLL = (panL > 0) ? (panL * maxDelaySamples) : 0;
        double delLR = (panL < 0) ? (-panL * maxDelaySamples) : 0;
        double delRL = (panR > 0) ? (panR * maxDelaySamples) : 0;
        double delRR = (panR < 0) ? (-panR * maxDelaySamples) : 0;

        int rIdxLL = (int)(wIdx - delLL + kMaxDelayFrames) % kMaxDelayFrames;
        int rIdxLR = (int)(wIdx - delLR + kMaxDelayFrames) % kMaxDelayFrames;
        int rIdxRL = (int)(wIdx - delRL + kMaxDelayFrames) % kMaxDelayFrames;
        int rIdxRR = (int)(wIdx - delRR + kMaxDelayFrames) % kMaxDelayFrames;

        float sLL = dsp->delayBufferL[rIdxLL];
        float sLR = dsp->delayBufferL[rIdxLR];
        float sRL = dsp->delayBufferR[rIdxRL];
        float sRR = dsp->delayBufferR[rIdxRR];

        // Apply head shadow filter to sound reaching the far ear
        if (panL > 0.15) {
            float filtered = (float)SGBiquadTick(&dsp->shadowFilterL, &dsp->shadowStateL, sLL);
            float blend = (float)fmin(1.0, panL * 0.65);
            sLL = sLL * (1.0f - blend) + filtered * blend;
        }
        if (panL < -0.15) {
            float filtered = (float)SGBiquadTick(&dsp->shadowFilterR, &dsp->shadowStateR, sLR);
            float blend = (float)fmin(1.0, (-panL) * 0.65);
            sLR = sLR * (1.0f - blend) + filtered * blend;
        }
        if (panR > 0.15) {
            float filtered = (float)SGBiquadTick(&dsp->shadowFilterL, &dsp->shadowStateL, sRL);
            float blend = (float)fmin(1.0, panR * 0.65);
            sRL = sRL * (1.0f - blend) + filtered * blend;
        }
        if (panR < -0.15) {
            float filtered = (float)SGBiquadTick(&dsp->shadowFilterR, &dsp->shadowStateR, sRR);
            float blend = (float)fmin(1.0, (-panR) * 0.65);
            sRR = sRR * (1.0f - blend) + filtered * blend;
        }

        // Sum contributions into Left and Right ears
        left[i]  = (float)((sLL * gLL + sRL * gRL) * 0.85);
        right[i] = (float)((sLR * gLR + sRR * gRR) * 0.85);

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
