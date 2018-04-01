module cyberparrot.midi.midistate;

import cyberparrot.midi.midievent;

import std.stdio;

class MidiState
{
    MidiChannel[numMidiChannels] channels;
    
    void feedEvent(immutable MidiEvent event)
    {        
        if(event.isSystemEvent)
            return;
            
        if(channels[event.channel] is null)
            channels[event.channel] = new MidiChannel;
            
        channels[event.channel].feedEvent(event);
    }
}

class MidiChannel
{
    //MIDI parameters such as mod wheel, channel pitch, channel volume, etc.
    ushort[MidiChannelControl.numControls] controls = [0];
    bool[MidiChannelSwitch.numSwitches] switches = [false];
    ushort pitch = pitchCenter;
    
    void feedEvent(immutable MidiEvent event)
    {            
        if(event.isChannelControl)
            event.applyChannelControl(controls[event.channelControlID]);
            
        if(event.isChannelSwitch)
            switches[event.channelSwitchID] = event.channelSwitchValue;
            
        if(event.statusCode == MidiStatusCode.pitchWheel)
            pitch = event.pitchChange;
    }
}
