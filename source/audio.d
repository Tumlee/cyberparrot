module cyberparrot.audio;

import derelict.openal.al;
import std.stdio;

import cyberparrot.time;
import cyberparrot.misc;

//FIXME: Some variables, like sample frequency and audio format,
//are hard-coded in right now. This will need to be a variable of
//some sort when this is all finished.

//FIXME: Should this be global?
//FIXME: audioSampleRate should be private, but is set in cyberparrot.d
uint audioSampleRate = 44100;
private uint audioNumChannels = 2;

uint getAudioSampleRate()
{
    return audioSampleRate;
}

uint getAudioNumChannels()
{
    return audioNumChannels;
}

//FIXME: Rename this function.
Duration getAudioLength(ulong numSamples)
{   
    return seconds(numSamples) / (audioSampleRate * audioNumChannels);
}

Duration getAudioLengthMono(ulong numSamples)
{
    return seconds(numSamples) / audioSampleRate;
}

//FIXME: Do this all with D's ranges wherever possible?
private ALCdevice* device;
private ALCcontext* context;

class AudioBuffer
{
    uint id;

    this(uint startingID = 0)
    {
        id = startingID;
    }

    void generate()
    {
        alGenBuffers(1, &id);
        assert(id != 0, "Failed to generate AudioBuffer.");
    }

    void feed(const float[] data)
    {
        assert(id != 0, "Tried to feed an ungenerated buffer.");

        alBufferData(id, AL_FORMAT_STEREO_FLOAT32, cast(void*) &data[0],
                        cast(int) (data.length * float.sizeof), audioSampleRate);
                        
        if(alGetError() != AL_NO_ERROR)
        {
            debugMSG("audio", writeln("Warning! OpenAL has detected an error."));
        }
    }
}

class AudioSource
{
    uint id = 0;
    private AudioBuffer[] availableBuffers;
    
    //Timestamp of when the playback is going to end, based on
    //how many samples have been fed to the buffer.
    private Duration playbackEnd;

    this(ulong numBuffers)
    {
        alGenSources(1, &id);
        
        foreach(i; 0 .. numBuffers)
        {
            auto newBuffer = new AudioBuffer;
            newBuffer.generate();
            availableBuffers ~= newBuffer;
        }
    }
    
    int get(int variableID)
    {
        int returnValue;
        alGetSourcei(id, variableID, &returnValue);
        return returnValue;
    }
    
    //Unqueues any buffers that are finished playing and places
    //them back on the available buffer list.
    void unqueueBuffers()
    {
        uint[] recycledBufferIDs;
        recycledBufferIDs.length = get(AL_BUFFERS_PROCESSED);

        if(recycledBufferIDs.length == 0)
            return;

        alSourceUnqueueBuffers(id, cast(int) recycledBufferIDs.length,
                                &recycledBufferIDs[0]);

        foreach(bufferID; recycledBufferIDs)
            availableBuffers ~= new AudioBuffer(bufferID);
    }

    bool feed(const float[] data)
    {
        if(!ready)
        {
            debugMSG("audio", writeln("Tried to feed a non-ready AudioSource"));
            return false;
        }

        //Feed the first available buffer.
        availableBuffers[0].feed(data);
        alSourceQueueBuffers(id, 1, &availableBuffers[0].id);
        
        //Remove the buffer from the list of available buffers.
        availableBuffers = availableBuffers[1 .. $];

        //Start playing the source if it's not already playing.
        if(get(AL_SOURCE_STATE) != AL_PLAYING)
        {
            long missedMS = (currentTime() - playbackEnd).total!"msecs";
            debugMSG("audio", writefln("<Audio stream underrun (missed by %dms)>", missedMS));
            playbackEnd = currentTime();
            alSourcePlay(id);
        }
        
        playbackEnd += getAudioLength(data.length);

        return true;
    }

    int numFed()
    {
        return get(AL_BUFFERS_QUEUED) - get(AL_BUFFERS_PROCESSED);
    }

    bool ready()
    {
        //First, make sure we don't have some buffers that need to be unqueued.
        unqueueBuffers();
        return availableBuffers.length != 0;
    }
    
    //FIXME: Rename this function.
    Duration audioLeft()
    {
        return playbackEnd - currentTime;
    }
}

AudioSource mainSource;

string[] getAudioDeviceList()
{
    string[] returnList;
    bool nullZero = false;
    
    auto deviceString = alcGetString(null, ALC_DEVICE_SPECIFIER);
    string current = "";
    
    size_t i = 0;

    while(true)
    {
        if(deviceString[i] == '\0')
        {
            if(nullZero == true)
                break;

            nullZero = true;
            returnList ~= current;
        }
        else
            current ~= deviceString[i];
            
        i++;
    }
    
    return returnList;
}

//FIXME: Throw exceptions here on error.
bool initAudio()
{
    debugMSG("audio", writeln("[ INITIALIZING OPENAL ]"));
    DerelictAL.load();

    debugMSG("audio", writeln("Available audio devices: ", getAudioDeviceList()));
    device = alcOpenDevice(null);

    if(!device)
    {
        writeln("Error opening audio device.");
        return false;
    }

    context = alcCreateContext(device, null);

    if(!alcMakeContextCurrent(context))
    {
        writeln("Error when creating context");
        return false;
    }

    mainSource = new AudioSource(10);
    alSourcef(mainSource.id, AL_PITCH, 1.0);
    alSourcef(mainSource.id, AL_GAIN, 10.0);
    alSource3f(mainSource.id, AL_POSITION, 0, 0, 0);
    alSource3f(mainSource.id, AL_VELOCITY, 0, 0, 0);
    alSourcei(mainSource.id, AL_LOOPING, false);

    return true;
}

void closeAudio()
{
    if(device !is null)
        alcCloseDevice(device);
}


