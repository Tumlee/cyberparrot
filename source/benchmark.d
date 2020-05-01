module cyberparrot.benchmark;

import std.stdio;
import std.math;
import cyberparrot.cyberparrot;
import cyberparrot.time;
import cyberparrot.audio;
import cyberparrot.midi.midievent;

//A class for collecting a dataset and calculating
//the standard deviation and average of the set.
class StatSampler
{
    private float[] samples;
    private float total;
    
    private size_t currentSample = 0;
    
    this(size_t nSamples, float initialValue = 0.0)
    {
        samples.length = nSamples;
        samples[] = initialValue;
        
        total = initialValue * nSamples;
    }
    
    void pushSample(float newSample)
    {
        float oldSample = samples[currentSample];
        samples[currentSample] = newSample;
        total += newSample - oldSample;
        
        currentSample = (currentSample + 1) % samples.length;
    }
    
    float mean()
    {
        return total / samples.length;
    }
    
    float standardDeviation()
    {
        float average = mean();
        
        float sum = 0.0;
        
        foreach(sample; samples)
            sum += ((sample - average) * (sample - average));
            
        return sqrt(sum / samples.length);
    }
}

//Quick and dirty performance analysis, printing out statistics in text form.
void analyzePerformance()
{
    auto sampler = new StatSampler(250);

    //Activate every voice available.
    foreach(v; 0 .. voiceCount)
        tree.activateVoice(v, 100.0 * v, 0.75);

    foreach(i; 0 .. 250)
    {
        auto startTime = currentTime();
        
        generateSamples();
         
        float elapsed = cast(float) (currentTime - startTime).total!"usecs";
        float goal = cast(float) getAudioLengthMono(sampleLength).total!"usecs";
        float stress = (elapsed / goal) * 100.0; 
        sampler.pushSample(stress);
    }
    
    writef("[rate=%d, block=%dx%d, %dms delay]\t",
                getAudioSampleRate(), sampleLength, voiceCount,
                (sampleLength * 1000) / getAudioSampleRate());
    writefln("a=%.2f%% (sd=%.2f%%)", sampler.mean(), sampler.standardDeviation());
}
