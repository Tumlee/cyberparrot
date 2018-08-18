typedef struct
{
    uint voiceID;
    uint vOff;      //Voice offset for this voice.
    float noteFrequency;    //Used to generate "noteFrequency" block.
    float pStart;   //PressClock for the start of this period.
    float pEnd;     //PressClock for the end of this period.
    float rStart;   //ReleaseClock for the start of this period.
    float rEnd;     //ReleaseClock for the end of this period.
    uint clipPosition;  //Used for clipping voices at the exact point that their
                        //ADSR envelope "dies"
    unsigned char isHeld;
}VoiceInfo;

kernel void generatePRClocks(   global float* heap,
                                constant VoiceInfo* activeVoices,
                                uint pClockOff,
                                uint rClockOff,
                                uint nFreqOff)
{
    uint i = get_global_id(0);
    constant VoiceInfo* vinfo = &activeVoices[get_global_id(1)];
    
    global float* pressClock = heap + vinfo->vOff + pClockOff;
    global float* releaseClock = heap + vinfo->vOff + rClockOff;
    global float* noteFrequency = heap + vinfo->vOff + nFreqOff;

    //We add the +1 here so that the pressClock is never zero, which would cause
    //any voice to terminate instantly.
    float endWeight = (1.0f * (i + 1)) / get_global_size(0);

    pressClock[i] = (vinfo->pStart * (1.0f - endWeight)) + (vinfo->pEnd * endWeight);
    releaseClock[i] = (vinfo->rStart * (1.0f - endWeight)) + (vinfo->rEnd * endWeight);
    noteFrequency[i] = vinfo->noteFrequency;
}

//NOTE: there are a lot of global values being access more than once in this function,
// is the compiler smart enough to optimize these accesses away?
kernel void adsr(   global float* heap,
                    constant uint* vOff,
                    constant uint* attackOff,
                    constant uint* decayOff,
                    constant uint* sustainOff,
                    constant uint* releaseOff,
                    constant uint* peakOff,
                    constant uint* baseOff,
                    constant uint* outOff,
                    uint pClockOff,
                    uint rClockOff)
{
    uint i = get_global_id(0);
    global float* attackTime =      heap + vOff[get_global_id(1)] + attackOff[get_global_id(2)];
    global float* decayTime =       heap + vOff[get_global_id(1)] + decayOff[get_global_id(2)];
    global float* sustainLevel =    heap + vOff[get_global_id(1)] + sustainOff[get_global_id(2)];
    global float* releaseTime =     heap + vOff[get_global_id(1)] + releaseOff[get_global_id(2)];
    global float* peak =            heap + vOff[get_global_id(1)] + peakOff[get_global_id(2)];
    global float* base =            heap + vOff[get_global_id(1)] + baseOff[get_global_id(2)];
    global float* out =             heap + vOff[get_global_id(1)] + outOff[get_global_id(2)];
    global float* pressClock =      heap + vOff[get_global_id(1)] + pClockOff;
    global float* releaseClock =    heap + vOff[get_global_id(1)] + rClockOff;
    
    float attackFactor = sustainLevel[i];
    float releaseFactor = 1.0f;
    
    if(pressClock[i] < attackTime[i])
    {
       //During the "attack" we should fade from 0.0 at pressClock=0, to 1.0 at pressClock=attackTime
       attackFactor = (pressClock[i] / attackTime[i]) * (pressClock[i] / attackTime[i]);
    } 
    else if(pressClock[i] < decayTime[i] + attackTime[i])
    {
        //During the decay, we should fade from 1.0 at decayPosition=0.0, to
        //sustainLevel at decayPosition=decayTime
        float decayPosition = pressClock[i] - attackTime[i];
        float decayFactor = decayPosition / decayTime[i];
        float decayAmount = 1.0f - sustainLevel[i];
        attackFactor = 1.0f - (decayFactor * decayAmount);
    }
    
    //We add 0.0001f here to ensure that we do not divide by zero when
    //releaseTime is zero.
    float rt = releaseTime[i] + 0.0001f;
    
    if(releaseClock[i] > rt)
    {
        //If time since release is larger than release time, envelope should be dead.
        releaseFactor = 0.0f;
    }
    else
    {
        //releaseFactor should be 1.0 at releaseClock=0
        //releaseFactor should be 0.0 at releaseClock=releaseTime
        releaseFactor = 1.0f - (releaseClock[i] / rt);
    }

    out[i] = (attackFactor * releaseFactor * releaseFactor) * (peak[i] - base[i]) + base[i];
}
