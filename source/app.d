import cyberparrot.core;
import cyberparrot.config;
import cyberparrot.time;
import cyberparrot.audio;
import cyberparrot.cyberparrot;
import cyberparrot.wavcollector;
import cyberparrot.misc;
import cyberparrot.midi.midievent;
import cyberparrot.midi.midicore;
import cyberparrot.benchmark;

void main(string[] args)
{
    createConfigDirs();
    extractConfigValues();
    saveArgs(args);
    
    SynthCore.coreThread("synth-core");
}

SynthCore synthCore;

class SynthCore : Core
{
    Duration baseTime;
    string captureFileName = null;
    WavCollector wav;

    this(string tName)
    {
        super(tName);

        //Open up a WavCollector if a capture file is specified in the command line or CFG file.
        captureFileName = getConfigVar!string("capture-file", null);

        if(captureFileName !is null)
            wav = new WavCollector(getAudioSampleRate(), getAudioNumChannels());
        
        initCyberparrot();
        synthCore = this;
    }

    override void setup()
    {
        //Benchmarking mode simply runs some tests and quits.
        if(flagExists("benchmark"))
        {
            analyzePerformance();
            terminating = true;
            return;
        }
        
        spawnChild(&MidiCore.coreThread, "midi-core");
        signalChild("midi-core", "open-stream");

        initAudio();  
    }

    override void tick()
    {      
        auto samples = generateSamples();
                
        mainSource.feed(samples);

        if(captureFileName !is null)
            wav.pushSamples(samples);

        auto loopTime = currentTime();
        while(mainSource.numFed() > 1 || !mainSource.ready())
        {
        }
    }
    
    override void end()
    {
        closeAudio();

        if(captureFileName !is null)
            wav.writeWAV(captureFileName);
    }

    override bool receiveMessage()
    {
        return receiveTimeout(dur!"nsecs"(-1),
                            (immutable CoreSignal x) { handleMessage(x); },
                            (immutable MidiEvent m) { handleMessage(m); } );
    }
    
    private void handleMessage(immutable CoreSignal signal)
    {
        handleTermination(signal);
    }
    
    private void handleMessage(immutable MidiEvent event)
    {            
        feedEvent(event);
    }

    static void coreThread(string newCoreID)
    {
        auto core = new SynthCore(newCoreID);
        core.run();
    }
}

