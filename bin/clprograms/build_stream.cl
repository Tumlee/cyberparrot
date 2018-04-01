typedef struct
{
    uint voiceID;
    uint vOff;      //Voice offset for this voice.
    float pStart;   //PressClock for the start of this period.
    float pEnd;     //PressClock for the end of this period.
    float rStart;   //ReleaseClock for the start of this period.
    float rEnd;     //ReleaseClock for the end of this period.
    uint clipPosition;  //Used for clipping voices at the exact point that their
                        //ADSR envelope "dies"
    unsigned char isHeld;
}VoiceInfo;

kernel void findZeros(  constant float* heap,
                        constant VoiceInfo* vinfo,
                        uint envelopeOff,
                        uint searches,              //Number of searches per worker.
                        local uint* localFinds,     //Local memory for storing what we've found.
                        global uint* globalFinds,   //The list of potential zeros we found (-1 means nothing found)
                        global uint* numIndexes)    //Number of indexes outputted, per voice, by this kernel
{
    constant float* envelope = heap + vinfo[get_global_id(1)].vOff + envelopeOff;
    uint startIndex = get_global_id(0) * searches;
    uint privateResult = -1;
    local uint* localSlice = &localFinds[get_local_id(1) * get_local_size(0)];

    //We iterate backwards here to avoid having to break out of the loop.
    for(int offset = searches - 1; offset >= 0; offset--)
    {
        if(envelope[startIndex + offset] <= 0.0)
            privateResult = startIndex + offset;
    }

    localSlice[get_local_id(0)] = privateResult;
    barrier(CLK_LOCAL_MEM_FENCE);
    privateResult = -1;
        
    if(get_local_id(0) == 0)
    {
        //Look through the list of local finds, outputting the first value in our list.
        for(uint l = 0; l < get_local_size(0); l++)
        {
            //Note that we look through this array backwards to avoid having to break out of the list.
            if(localSlice[get_local_size(0) - 1 - l] < privateResult)
                privateResult = localSlice[get_local_size(0) - 1 - l];
        }

        globalFinds[(get_global_id(1) * get_global_size(0)) + get_group_id(0)] = privateResult;
    }

    if(get_global_id(0) == 0 && get_global_id(1) == 0)
        *numIndexes = get_num_groups(0);
}

//This is the kernel that coalesces all the voices into one.
kernel void generateStream( constant float* heap,
                            global float* stream,
                            global VoiceInfo* vinfo,
                            uint numActiveVoices,
                            uint lOff,                  //Offset for lchannel
                            uint rOff,                  //Offset for rchannel
                            constant uint* globalFinds, //The list of findings we have.
                            constant uint* numIndexes,  //Number of indexes per voice.
                            uint indexStride)           //Distance between voices, equal to get_global_size(0) / searches
{
    constant float* lBlock = &heap[lOff];
    constant float* rBlock = &heap[rOff];
    
    float lAccumulator = 0;
    float rAccumulator = 0;
    
    //Step through every voice.
    for(int v = 0; v < numActiveVoices; v++)
    {
        uint gFindStart = v * indexStride;
        uint clipPosition = -1;
        
        //Find clipPosition, which will be the first valid index we find.
        for(int i = 0; i < *numIndexes; i++)
        {
            if(globalFinds[gFindStart + i] != -1)
            {
                clipPosition = globalFinds[gFindStart + i];
                break;
            }
        }

        //Store clip position for every voice, to allow host to discard voices.
        if(get_global_id(0) == 0)
            vinfo[v].clipPosition = clipPosition;

        //If we're before the clipPosition, add to the accumulators.
        if(get_global_id(0) < clipPosition)
        {
            lAccumulator += lBlock[vinfo[v].vOff + get_global_id(0)];
            rAccumulator += rBlock[vinfo[v].vOff + get_global_id(0)];
        }
    }

    if(lAccumulator > 8.0f)
        lAccumulator = 8.0f;

    if(rAccumulator > 8.0f)
        rAccumulator = 8.0f;

    if(lAccumulator < -8.0f)
        lAccumulator = -8.0f;

    if(rAccumulator < -8.0f)
        rAccumulator = -8.0f;

    //The format for the audio stream is LRLRLRLRLRLR....
    stream[(get_global_id(0) * 2) + 0] = lAccumulator / 8.0;
    stream[(get_global_id(0) * 2) + 1] = rAccumulator / 8.0;
}
