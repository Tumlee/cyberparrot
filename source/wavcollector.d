module cyberparrot.wavcollector;

import std.stdio;
import std.file;

void writeDatum(T, U)(File file, U datum)
{
    ubyte[T.sizeof] buffer;
    T converted = cast(T) datum;

    foreach(i; 0 .. T.sizeof)
    {
        auto shift = i * 8;
        buffer[i] = cast(ubyte) ((converted & (0xff << shift)) >> shift);
    }

    file.rawWrite(buffer);
}

void writeFloatLE(File file, float f)
{
    union Caster
    {
        float f;
        uint i;
    }

    Caster val;
    val.f = f;
    file.writeDatum!uint(val.i); 
}

class WavCollector
{
    private float[][] sampleBuffers;
    private size_t bufferSize;
    private size_t bufferPosition = 0;
    private size_t numChannels;
    private size_t sampleRate;
    
    this(size_t sRate, size_t nChannels, size_t bSize = 65536)
    {
        sampleRate = sRate;
        numChannels = nChannels;
        bufferSize = bSize;
        pushBuffer();
    }

    void pushSamples(float[] samples)
    {   
        if(samples.length + bufferPosition >= bufferSize)
        {
            size_t clipLength = bufferSize - bufferPosition;
            
            sampleBuffers[$ - 1][bufferPosition .. bufferSize] = samples[0 .. clipLength];
            pushBuffer();
            pushSamples(samples[clipLength .. $]);
        }
        else
        {
            sampleBuffers[$ - 1][bufferPosition .. bufferPosition + samples.length] = samples[];
            bufferPosition += samples.length;
        }
    }
    
    private void pushBuffer()
    {
        float[] newBuffer;
        newBuffer.length = bufferSize;
        newBuffer[] = 0.0;
        
        sampleBuffers ~= newBuffer;
        
        bufferPosition = 0;
    }
    
    bool writeWAV(string filename)
    {
        File file;        

        try
        {
            file = File(filename, "wb");
        }
        catch(std.exception.ErrnoException)
        {
            return false;
        }
        
        size_t numBytes = getNumBytes();
        
        file.write("RIFF"); //ChunkID
        file.writeDatum!uint(numBytes + 36);    //ChunkSize
        file.write("WAVE"); //Format
        
        file.write("fmt "); //Subchunk1ID
        file.writeDatum!uint(16);   //Subchunk1Size
        file.writeDatum!ushort(3);  //AudioFormat
        file.writeDatum!ushort(numChannels);  //NumChannels
        file.writeDatum!uint(sampleRate);    //SampleRate
        file.writeDatum!uint(sampleRate * numChannels * float.sizeof); //ByteRate
        file.writeDatum!ushort(numChannels * float.sizeof);   //BlockAlign
        file.writeDatum!ushort(float.sizeof * 8);   //BitsPerSample
        
        file.write("data"); //Subchunk2ID
        file.writeDatum!uint(numBytes); //Subchunk2Size
        
        //Write the actual PCM data to the file.
        foreach(buffer; sampleBuffers[0 .. $ - 1])
        {
            foreach(sample; buffer)
                file.writeFloatLE(sample);
        }
            
        foreach(sample; sampleBuffers[$ - 1][0 .. bufferPosition])
            file.writeFloatLE(sample);
               
        //Close the file and report success.
        file.close();
        return true;
    }
    
    //Returns the number of bytes that the collected PCM
    //data takes up.
    size_t getNumBytes()
    {
        size_t numSamples = 0;
        
        foreach(i; 0 .. sampleBuffers.length - 1)
            numSamples += sampleBuffers[i].length;
        
        numSamples += bufferPosition;
        return numSamples * float.sizeof;
    }
}
