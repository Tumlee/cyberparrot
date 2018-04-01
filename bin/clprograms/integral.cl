typedef struct
{
    uint voiceID;
    uint vOff;      //Voice offset for this voice.
    float pStart;   //PressClock for the start of this period.
    float pEnd;     //PressClock for the end of this period.
    float rStart;   //ReleaseClock for the start of this period.
    float rEnd;     //ReleaseClock for the end of this period.
    unsigned char isHeld;
    uint clipPosition;  //Used for clipping voices at the exact point that their
                        //ADSR envelope "dies"
}VoiceInfo;

//Because there is no such thing as global memory sync in OpenCL within a single kernel,
//the task of finding the integral (rolling sum) of an input signal must be broken
//into steps A and B.

//Step A generates partial rolling sums of small chunks. Step B takes the final values
//of each preceding chunk, if they exist, and adds them to their current value,
//so that the sum is complete.

//FIXME: Instead of using 64, we should be using a power-of-two value that is as
//close to sqrt(get_global_size(0)) as possible.
kernel void integralA(  global float* heap,
                        constant uint* vOff,
                        constant VoiceInfo* vinfo,
                        uint voiceCount,
                        constant uint* inOff,
                        constant uint* partialOff,
                        global float* stored,
                        float timeStep)
{
    uint i = get_global_id(0);
    global float* in = heap + vOff[get_global_id(1)] + inOff[get_global_id(2)];
    global float* partial = heap + vOff[get_global_id(1)] + partialOff[get_global_id(2)];
    uint vid = vinfo[get_global_id(1)].voiceID;
    uint storeIndex = (get_global_id(2) * voiceCount) + vid;
    
    float accumulator = 0;
    
    for(size_t j = 0; j <= i % 64; j++)
        accumulator += in[i - j];

    //The first "slice" of partials is elevated by the stored values,
    //while every subsequent slice isn't. This is to get around a race condition
    //that would occur if we read from and wrote to stored[] in integralB
    partial[i] = (accumulator * timeStep) + (stored[storeIndex] * (i < 64));
}

kernel void integralB(  global float* heap,
                        constant uint* vOff,
                        constant VoiceInfo* vinfo,
                        uint voiceCount,
                        constant uint* partialOff,
                        constant uint* outOff,
                        global float* stored)
{
    uint i = get_global_id(0);
    global float* partial = heap + vOff[get_global_id(1)] + partialOff[get_global_id(2)];
    global float* out = heap + vOff[get_global_id(1)] + outOff[get_global_id(2)];
    uint vid = vinfo[get_global_id(1)].voiceID;
    uint storeIndex = (get_global_id(2) * voiceCount) + vid;
    
    float accumulator = partial[i];
    
    //0 .. 63 should not copy.
    //64 .. 127 should copy from 63
    //128 .. 191 should copy from 63 and 127, etc.
    for(size_t off = 63; off < i; off += 64)
        accumulator += partial[off];

    out[i] = accumulator;
    
    if(i == get_global_size(0) - 1)
        stored[storeIndex] = accumulator;
}
