module cyberparrot.midi.midievent;

import std.conv;
import core.time;

//Enumerates status bytes that a MidiEvent can contain, with the channel stripped out.
enum MidiStatusCode : ubyte
{
    noteOff = 0x80,
    noteOn = 0x90,
    polyAftertouch = 0xa0,
    controlChange = 0xb0,
    patchChange = 0xc0,
    channelAftertouch = 0xd0,
    pitchWheel = 0xe0,
    sysexStart = 0xf0,
    songPosition = 0xf2,
    songSelect = 0xf3,
    sysexEnd = 0xf7,
    rtClock = 0xf8,
    rtStart = 0xfa,
    rtContinue = 0xfb,
    rtStop = 0xfc,
    rtReset = 0xff
}

//Enumerates known channel controls defined by the MIDI standard.
enum MidiChannelControl : ubyte
{
    modWheel = 0x01,
    breath = 0x02,
    foot = 0x04,
    portamentoTime = 0x05,
    dataEntry = 0x06,
    volume = 0x07,
    numControls = 0x20
}

//==============================================================================
//Enumerates known channel switches defined by the MIDI standard.
//These values are shifted down so that it starts at zero, so even though a
//channel control with byte 2 = 0x41 controls portamento, we use 0x01 here, etc.
//==============================================================================
enum MidiChannelSwitch : ubyte
{
    sustain = 0x00,
    portamento = 0x01,
    sustenuto = 0x02,
    softPedal = 0x03,
    numSwitches = 0x20
}

enum numMidiChannels = 16;
enum pitchCenter = 0x2000;
enum numNotes = 128;

///===========================================================================
//A class that represents a timestamped MIDI event. This also includes various
//utility functions that help identify information about the event.

//It is up to the user to figure out which informaton is actually relevant.
//For example, there is nothing stopping the user from calling noteNumber()
//on a pitchWheel event and get a (nonsensical) value, so it's important to
//check the statusCode() property first.
//============================================================================
immutable class MidiEvent
{
    //Data bytes for the event.
    //We only need three bytes because Sysex events are handled seperately.
    ubyte[3] data;
    
    //Timestamp of the event.
    //We use long here so we don't have to expose PortMidi to the user.
    Duration timestamp;
    
    this(ubyte status, ubyte data1, ubyte data2, Duration tstamp)
    {
        //All MidiEvents coming through here should have the MSB set on the first byte,
        //and the MSB must be unset on the other two, otherwise it is not valid data.
        assert(status & 0x80, "Invalid status byte in MidiEvent constructor.");
        assert(!((data1 | data2) & 0x80), "Invalid data byte(s) in MidiEvent constructor.");
        
        data = [status, data1, data2];
        timestamp = tstamp;
    }
    
    //Returns true if this is a system event.
    @property bool isSystemEvent()
    {
        return data[0] >= 0xf0;
    }
    
    //Returns true if this is a realtime event.
    @property bool isRealtimeEvent()
    {
        return data[0] >= 0xf8;
    }
    
    //Returns the targeted channel number of an event.
    //Please note that the channels are numbered 0-15.
    @property ubyte channel()
    {
        assert(!isSystemEvent, "Cannot get channel property of system MidiEvent.");
        return data[0] & 0x0f;
    }
    
    //Pulls the channel number out of a MIDI event, leaving the event code only.
    //For example, 0x92 (Note on, channel 3) becomes 0x90 (MidiStatusCode.noteOn)
    @property MidiStatusCode statusCode()
    {
        return cast(MidiStatusCode) (isSystemEvent ? data[0] : data[0] & 0xf0);    
    }
    
    //Returns note number for noteOn, noteOff, and polyAftertouch events.
    @property ubyte noteNumber()
    {
        return data[1];
    }
    
    //Returns note velocity for noteOn and noteOff events.
    @property ubyte noteVelocity()
    {
        return data[2];
    }
    
    //Returns pressure for polyAftertouch and channelAftertouch events.
    @property ubyte aftertouchPressure()
    {
        //polyAftertouch pressure is data[2], channelAftertouch pressure is at data[1]
        return data[statusCode == MidiStatusCode.channelAftertouch ? 1 : 2];
    }
    
    //Returns patch number for patchChange events.
    @property ubyte patchNumber()
    {
        return data[1];
    }
    
    //Returns the pitch change value of a pitchWheel event, 0x2000 being centered.
    @property ushort pitchChange()
    {
        return (data[1].to!ushort | (data[2].to!ushort << 7)).to!ushort;
    }
    
    //Returns whether or not this is a continuous controller event.
    //Examples of this would be changes to the mod wheel and breath control.
    @property bool isChannelControl()
    {
        return statusCode == MidiStatusCode.controlChange && data[1] < 0x40;
    }
    
    //Returns the ID number of a continous controller change.
    @property ubyte channelControlID()
    {
        return data[1] & 0x1f;
    }
    
    //Returns the byte number of a continuous controller change.
    //1 = MSB, 0 = LSB
    @property int channelControlByte()
    {
        return data[1] < 0x20 ? 1 : 0;
    }
    
    //Applies a channel controller value to a ushort.
    void applyChannelControl(ref ushort value)
    {
        int shift = channelControlByte ? 7 : 0;
        
        //Mask out the bits.
        ushort mask = cast(ushort) (0x7f << shift);
        
        //Cut out the bits according to the mask.
        value &= ~mask;
        
        //Put the data in the correct spot
        value |= data[2] << shift;
    }
    
    //Returns whether or not this is a boolean controller event.
    //Examples of this would be the sustain pedal or the portamento switch.
    @property bool isChannelSwitch()
    {
        return statusCode == MidiStatusCode.controlChange && data[1] >= 0x40 && data[1] < 0x60;
    }
    
    //Returns the ID number of a boolean controller.
    //Sustain pedal = 0, Portamento = 1, Sustenuto = 2, etc...
    @property int channelSwitchID()
    {
        return data[1] - 0x40;
    }
    
    //Returns the value of a boolean controller.
    //The MIDI spec says 0=off, 127=on, but we'll treat any nonzero value as on.
    @property bool channelSwitchValue()
    {
        return data[2] != 0;
    }
    
    //Returns true for Data entry +1/-1 events.
    @property bool isDataEntry()
    {
        return data[1] == 0x60 || data[1] == 0x61;
    }
    
    //Returns whether the data entry event is a +1 or -1.
    @property byte dataEntryDelta()
    {
        return data[1] == 0x60 ? 1 : -1;
    }
    
    //Returns true for any event that turns all notes off in a channel.
    @property bool turnsNotesOff()
    {
        return data[1] >= 0x7b;
    }
    
}
