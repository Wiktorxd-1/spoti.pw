#import "SGDSPEffects.h"
#import <math.h>
#import <stdlib.h>
#import <string.h>

enum {
    kMaxDelayFrames = 256,
    kReverbBufferFrames = 2048,
};

struct SGDSP8D {
    double rate;
    double phase;
    double phaseIncrement;
    double orbitWidth;       // 0.0 ... 1.0
    double reverbMix;        // 0.0 ... 1.0
    bool anchorBass;
    bool rearFilter;

    // Circular delay buffer for ITD
    float delayBufferL[kMaxDelayFrames];
    float delayBufferR[kMaxDelayFrames];
    int writeIndex;

    // Anchor Bass crossover filter (120 Hz)
    SGBiquad bassFilterL;
    SGBiquadState bassStateL;
    SGBiquad bassFilterR;
    SGBiquadState bassStateR;

    // Head shadow & rear dampening filter (3500 Hz)
    SGBiquad shadowFilterL;
    SGBiquadState shadowStateL;
    SGBiquad shadowFilterR;
    SGBiquadState shadowStateR;

    // Spatial reverb multi-tap early reflections
    float reverbRingL[kReverbBufferFrames];
    float reverbRingR[kReverbBufferFrames];
    int revWriteIndex;
};

SGDSP8D *SGDSP8DCreate(double rate, double rotationSeconds, double orbitWidth, double reverbMix, bool anchorBass, bool rearFilter) {
    SGDSP8D *dsp = calloc(1, sizeof *dsp);
    if (!dsp) return NULL;
    dsp->rate = rate > 0 ? rate : 44100.0;
    dsp->bassFilterL = SGBiquadLowPass(dsp->rate, 120.0, 0.707);
    dsp->bassFilterR = SGBiquadLowPass(dsp->rate, 120.0, 0.707);
    dsp->shadowFilterL = SGBiquadLowPass(dsp->rate, 3500.0, 0.707);
    dsp->shadowFilterR = SGBiquadLowPass(dsp->rate, 3500.0, 0.707);
    SGDSP8DSet(dsp, rotationSeconds, orbitWidth, reverbMix, anchorBass, rearFilter);
    return dsp;
}

void SGDSP8DSet(SGDSP8D *dsp, double rotationSeconds, double orbitWidth, double reverbMix, bool anchorBass, bool rearFilter) {
    if (!dsp) return;
    double sec = fmax(2.0, fmin(30.0, rotationSeconds > 0 ? rotationSeconds : 8.0));
    dsp->phaseIncrement = (2.0 * M_PI) / (dsp->rate * sec);
    dsp->orbitWidth = fmax(0.0, fmin(100.0, orbitWidth)) / 100.0;
    dsp->reverbMix = fmax(0.0, fmin(100.0, reverbMix)) / 100.0;
    dsp->anchorBass = anchorBass;
    dsp->rearFilter = rearFilter;
}

void SGDSP8DRun(void *state, float *left, float *right, uint32_t frames) {
    SGDSP8D *dsp = state;
    if (!dsp) return;

    double phase = dsp->phase;
    double inc = dsp->phaseIncrement;
    double widthScale = dsp->orbitWidth;
    double revMix = dsp->reverbMix;
    bool anchorBass = dsp->anchorBass;
    bool rearFilter = dsp->rearFilter;

    int wIdx = dsp->writeIndex;
    int revWIdx = dsp->revWriteIndex;
    double maxDelaySamples = dsp->rate * 0.00065 * widthScale; // ~0.65ms max ITD

    // 4 early reflection taps in samples
    int tap1 = (int)(0.007 * dsp->rate) % kReverbBufferFrames;
    int tap2 = (int)(0.013 * dsp->rate) % kReverbBufferFrames;
    int tap3 = (int)(0.021 * dsp->rate) % kReverbBufferFrames;
    int tap4 = (int)(0.033 * dsp->rate) % kReverbBufferFrames;

    for (uint32_t i = 0; i < frames; i++) {
        float inL = left[i];
        float inR = right[i];

        // 1. Anchor Bass (crossover below 120 Hz centered to maintain punch)
        float monoBass = 0.0f;
        float orbitL = inL;
        float orbitR = inR;
        if (anchorBass) {
            float lowL = (float)SGBiquadTick(&dsp->bassFilterL, &dsp->bassStateL, inL);
            float lowR = (float)SGBiquadTick(&dsp->bassFilterR, &dsp->bassStateR, inR);
            monoBass = 0.5f * (lowL + lowR);
            orbitL -= lowL;
            orbitR -= lowR;
        }

        // Store into delay ring buffer
        dsp->delayBufferL[wIdx] = orbitL;
        dsp->delayBufferR[wIdx] = orbitR;

        // 2. Azimuth theta: 0 = front, pi/2 = right, pi = back, 3pi/2 = left
        double theta = phase;

        // Virtual left and right speakers positioned 30 deg (+/- 0.52 rad * widthScale)
        double spread = 0.52 * fmax(0.2, widthScale);
        double thetaL = theta - spread;
        double thetaR = theta + spread;

        // Virtual Left speaker panning
        double panL = sin(thetaL) * widthScale;
        double depthL = cos(thetaL);
        double panAngleL = (panL + 1.0) * (M_PI * 0.25);
        double gLL = cos(panAngleL);
        double gLR = sin(panAngleL);

        // Virtual Right speaker panning
        double panR = sin(thetaR) * widthScale;
        double depthR = cos(thetaR);
        double panAngleR = (panR + 1.0) * (M_PI * 0.25);
        double gRL = cos(panAngleR);
        double gRR = sin(panAngleR);

        // 3. Behind-Head Dampening (dynamic low-pass filter & attenuation when audio orbits behind listener)
        if (rearFilter) {
            if (depthL < 0) {
                double backAtten = 1.0 + depthL * 0.20;
                gLL *= backAtten;
                gLR *= backAtten;
            }
            if (depthR < 0) {
                double backAtten = 1.0 + depthR * 0.20;
                gRL *= backAtten;
                gRR *= backAtten;
            }
        }

        // Delay lookup for opposite ears (Interaural Time Difference)
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

        // Behind-the-head dampening filter
        if (rearFilter && depthL < -0.1) {
            float filt = (float)SGBiquadTick(&dsp->shadowFilterL, &dsp->shadowStateL, sLL);
            float blend = (float)fmin(1.0, (-depthL) * 0.6);
            sLL = sLL * (1.0f - blend) + filt * blend;
            sLR = sLR * (1.0f - blend) + filt * blend;
        }
        if (rearFilter && depthR < -0.1) {
            float filt = (float)SGBiquadTick(&dsp->shadowFilterR, &dsp->shadowStateR, sRR);
            float blend = (float)fmin(1.0, (-depthR) * 0.6);
            sRL = sRL * (1.0f - blend) + filt * blend;
            sRR = sRR * (1.0f - blend) + filt * blend;
        }

        // Sum 8D orbit sound
        float dry8DL = (float)((sLL * gLL + sRL * gRL) * 0.85);
        float dry8DR = (float)((sLR * gLR + sRR * gRR) * 0.85);

        // 4. Spatial Reverb (Room reflection intensity to simulate physical distance)
        float finalL = dry8DL;
        float finalR = dry8DR;
        if (revMix > 0.001) {
            dsp->reverbRingL[revWIdx] = dry8DL;
            dsp->reverbRingR[revWIdx] = dry8DR;

            int idx1 = (revWIdx - tap1 + kReverbBufferFrames) % kReverbBufferFrames;
            int idx2 = (revWIdx - tap2 + kReverbBufferFrames) % kReverbBufferFrames;
            int idx3 = (revWIdx - tap3 + kReverbBufferFrames) % kReverbBufferFrames;
            int idx4 = (revWIdx - tap4 + kReverbBufferFrames) % kReverbBufferFrames;

            float revReflL = (dsp->reverbRingL[idx1] * 0.35f + dsp->reverbRingR[idx2] * 0.25f +
                              dsp->reverbRingL[idx3] * 0.20f + dsp->reverbRingR[idx4] * 0.15f);
            float revReflR = (dsp->reverbRingR[idx1] * 0.35f + dsp->reverbRingL[idx2] * 0.25f +
                              dsp->reverbRingR[idx3] * 0.20f + dsp->reverbRingL[idx4] * 0.15f);

            float wet = (float)revMix;
            finalL = dry8DL * (1.0f - wet * 0.3f) + revReflL * wet;
            finalR = dry8DR * (1.0f - wet * 0.3f) + revReflR * wet;
        }

        // Add back anchored centered bass if enabled
        if (anchorBass) {
            finalL += monoBass;
            finalR += monoBass;
        }

        left[i]  = finalL;
        right[i] = finalR;

        wIdx = (wIdx + 1) % kMaxDelayFrames;
        revWIdx = (revWIdx + 1) % kReverbBufferFrames;
        phase += inc;
        if (phase >= 2.0 * M_PI) phase -= 2.0 * M_PI;
    }

    dsp->phase = phase;
    dsp->writeIndex = wIdx;
    dsp->revWriteIndex = revWIdx;
}

void SGDSP8DFree(void *dsp) {
    free(dsp);
}
