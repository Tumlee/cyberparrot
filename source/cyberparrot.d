module cyberparrot.cyberparrot;

import cyberparrot.config;
import cyberparrot.optree;
import cyberparrot.operator;
import cyberparrot.patchmap;
import cyberparrot.clutil;
import cyberparrot.misc;
import cyberparrot.midi.midievent;
import cyberparrot.midi.channelstate;
import cyberparrot.audio;
import cyberparrot.time;
import cyberparrot.serialization;

import std.stdio;
import std.algorithm;
import std.math;
import std.array;
import std.conv;

uint sampleLength = 512;
uint voiceCount = 16;

//FIXME: These variables should not be global... but they will be for the time being.
float[] outSamples;
float[] zeroArray;

//The main Operator tree for running all the calculations.
OpTree tree;

void initCyberparrot()
{
    initCL();
    
    sampleLength = getConfigVar("period", 512);
    voiceCount = getConfigVar("voicecount", 16);     
    audioSampleRate = getConfigVar("samplerate", 44100);

    PatchMap patch = loadFromJsonFile!PatchMap("patches/patch000.json".inConfigPath);
    tree = new OpTree(patch, voiceCount, sampleLength, audioSampleRate);
    
    //Build the tree.
    tree.build();
    buildParamLinks();
    buildSwitchLinks();
    
    //Initialize host-side arrays so we can collect samples from the OpenCL device
    //and feed it to the audio system.
    outSamples.length = sampleLength * getAudioNumChannels();
    zeroArray.length = sampleLength * getAudioNumChannels();
    zeroArray[] = 0.0;
        
    //debugMSG("opencl", writefln("This patch runs %d kernels per cycle", numKernels));
    //debugMSG("opencl", writefln("Total Memory allocated for OpenCL: %dkb", getTotalCLMemory() / 1024));
}

ref float[] generateSamples()
{
    //Don't bother calculating anything if no voices are playing.
    if(tree.activeVoices.length == 0)
        return zeroArray;

    tree.calculate();
    tree.stream.read(outSamples);
    
    //Make sure that heldNotes[] does not contain pointers to pruned voices.
    foreach(note; heldNotes.byKey)
    {
        if(!tree.activeVoices.canFind!(a => a.voiceID == heldNotes[note]))
            heldNotes.remove(note);
    }

    return outSamples;
}

ChannelState channelState;

void feedEvent(immutable MidiEvent event)
{    
    //Can't do anything with a system event.
    if(event.isSystemEvent)
        return;

    //Internally, MIDI channels are numbered 0-15.
    //We take away 1 here so that externally we use numbers 1-16
    if(event.channel != getConfigVar("midiChannel", 1) - 1)
        return;
    
    if(event.statusCode == MidiStatusCode.noteOn)
        tryActivateVoice(event);
    
    if(event.statusCode == MidiStatusCode.noteOff)
        tryReleaseVoice(event);
        
    if(event.statusCode == MidiStatusCode.controlChange)
    {
        if(channelState.processEvent(event))
        {
            auto change = channelState.getChangedControl(event);

            if(change.controlID !is null)
            {
                tryChangeParam(change);
                tryChangeSwitch(change);
            }
        }

        if(event.turnsNotesOff())
            releaseAllVoices();
    }

    if(event.statusCode == MidiStatusCode.pitchWheel)
    {
        if(channelState.processEvent(event))
        {
            //Currently, pitch wheel sensitivity is locked into range of +/- 2 semitones.
            float semitones = channelState.pitchWheel.normalizedValue() * 4.0 - 2.0;
            tree.pitchWheel[0] = semitones;
        }
    }
}

//Listing of held notes, by MIDI code.
VoiceID[ubyte] heldNotes;

void tryActivateVoice(immutable MidiEvent event)
{
    //Activating an already-held note means we release the one that's already playing.
    tryReleaseVoice(event);

    //According to MIDI standard, Note On with zero velocity
    //just releases that note, just like Note Off event.
    if(event.noteVelocity == 0)
        return;
    
    //First, try to find a free voice.
    foreach(v; 0 .. voiceCount)
    {
        if(tree.activeVoices.canFind!((a, b) => a.voiceID == b)(v))
            continue;   //Already taken.
            
        //The value of the "noteFrequency" parameter is expressed in hertz.
        //We use A440 tuning here, meaning that note A4 (note number 69) should be 440hz.
        int aDelta = event.noteNumber - 69;
        float noteFrequency = 440.0 * pow(2.0, aDelta / 12.0);

        tree.activateVoice(v, noteFrequency, event.noteVelocity / 127.0);
        heldNotes[event.noteNumber] = v;

        return;
    }
}

void tryReleaseVoice(immutable MidiEvent event)
{
    if(event.noteNumber in heldNotes)
    {
        tree.releaseVoice(heldNotes[event.noteNumber]);
        heldNotes.remove(event.noteNumber);
    }
}

void releaseAllVoices()
{
    foreach(vid; heldNotes)
        tree.releaseVoice(vid);

    heldNotes.clear();
}

void tryChangeParam(ChannelStateChange change)
{
    float weight = change.value;

    foreach(paramID; paramLinks.get(change.controlID, []))
    {
        auto param = tree.parameters[paramID];
        float paramValue = (param.minValue * (1.0 - weight)) + (param.maxValue * weight);
        debugMSG("patch", writefln("Setting param %s to %f", paramID, paramValue));
        tree.heap.fillBlock(tree.parameters[paramID].outBlockID, paramValue);
    }
}

void tryChangeSwitch(ChannelStateChange change)
{     
    float normalized = change.value;

    foreach(switchID; switchLinks.get(change.controlID, []))
    {
        auto sw = tree.switches[switchID];
        int selection = cast(int) (change.value * sw.selections.length);

        //Corner case --- if normalized is 1.0, then selection == numSelections
        if(selection >= sw.selections.length)
            selection = cast(int) (sw.selections.length - 1);

        sw.changeSelection(selection);
    }
}

//A lookup of parameter names, by CC number
string[][string] paramLinks;
string[][string] switchLinks;

void buildParamLinks()
{
    foreach(paramID; tree.patch.paramDefs.byKey)
    {
        auto pDef = tree.patch.paramDefs[paramID];

        if((pDef.controlID in paramLinks) is null)
            paramLinks[pDef.controlID] = [];
            
        debugMSG("patch", writefln("Linking %s to %s", pDef.controlID, paramID));
        paramLinks[pDef.controlID] ~= paramID;
    }
}

void buildSwitchLinks()
{
    foreach(switchID; tree.patch.switchDefs.byKey)
    {
        auto sDef = tree.patch.switchDefs[switchID];

        if((sDef.controlID in switchLinks) is null)
            switchLinks[sDef.controlID] = [];

        debugMSG("patch", writefln("Linking %s to %s", sDef.controlID, switchID));
        switchLinks[sDef.controlID] ~= switchID;
    }
}
