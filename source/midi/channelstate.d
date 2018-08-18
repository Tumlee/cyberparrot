module cyberparrot.midi.channelstate;

import derelict.portmidi.portmidi;
import derelict.portmidi.porttime;
import cyberparrot.midi.midievent;

//A structure that contains the state of a given MIDI channel.
//Note that this structure will happily process any MIDI events
//and not just those that belong to a particular channel. It is the
//caller's responsibility to feed only events that should be processed.
enum maxMidiValue = (128 * 128) - 1;

struct MidiBytePair
{
    //Because MIDI data bytes range from 0-127, impossible values >127 mean
    //that the data is not yet initialized.
    ubyte msb = 255;
    ubyte lsb = 255;
    
    this(ubyte m, ubyte l)
    {
        msb = m;
        lsb = l;
    }

    //Initialize from a normalized [0.0, 1.0] value, clamped betwen 0.0 and 127.127
    this(float f)
    {
        int fullValue = cast(int) (maxMidiValue * f);

        if(fullValue < 0)
            fullValue = 0;

        if(fullValue > maxMidiValue)
            fullValue = maxMidiValue;

        lsb = fullValue & 127;
        msb = (fullValue >> 7) & 127;
    }

    //Returns a value between 0.0 and 1.0 depending on the
    //value of the parameter. Note that so we can reach exactly
    //1.0, we will scale values beyond (128^2), so we 'cheat' it
    //when both bytes are 127.
    float normalizedValue()
    {
        //If LSB is uninitialized, treat it as if it is zero.
        int fullValue = (msb << 7) | (lsb <= 127 ? lsb : 0);

        if(fullValue == maxMidiValue)
            return 1.0;

        return cast(float) fullValue / maxMidiValue;
    }
}

enum ParamType
{
    none,
    rpn,
    nrpn,
    cc
}

//Reports which paramter changed and what value it changed to.
struct ChannelStateChange
{
    string controlID = null;
    float value;

    this(string cID, float v)
    {
        controlID = cID;
        value = v;
    }
}

struct ChannelState
{
    //Determines which RPN or NRPN is currently selected.
    MidiBytePair rpnPointer = MidiBytePair(127, 127);
    MidiBytePair nrpnPointer = MidiBytePair(127, 127);

    //Determines whether or not we are pointing at an RPN or NRPN.
    ParamType paramType = ParamType.none;
    
    MidiBytePair[127][127] rpnTable;
    MidiBytePair[127][127] nrpnTable;
    MidiBytePair pitchWheel = MidiBytePair(64, 0);
    ubyte[96] ccTable;

    //Processed a MIDI event and updates the relevant parts of the ChannelState.
    //This function returns true if a part of the ChannelState was updated.
    bool processEvent(immutable MidiEvent event)
    {
        if(event.isSystemEvent())
            return false;

        if(event.statusCode == MidiStatusCode.controlChange)
        {
            ParamType oldParamType = paramType;

            if(event.data[1] == 98)
            {
                paramType = ParamType.nrpn;
                return changeByte(nrpnPointer.lsb, event.data[2]) || oldParamType != paramType;
            }

            if(event.data[1] == 99)
            {
                paramType = ParamType.nrpn;
                return changeByte(nrpnPointer.msb, event.data[2]) || oldParamType != paramType;
            }

            if(event.data[1] == 100)
            {
                paramType = ParamType.rpn;
                return changeByte(rpnPointer.lsb, event.data[2]) || oldParamType != paramType;
            }

            if(event.data[1] == 101)
            {
                paramType = ParamType.rpn;
                return changeByte(nrpnPointer.msb, event.data[2]) || oldParamType != paramType;
            }
            
            if(event.channelControlID == 6)
            {
                MidiBytePair* target = getParamTarget();

                if(getParamTarget() is null)
                    return false;
                             
                if(event.channelControlByte == 1)   //MSB
                    return changeByte(getParamTarget().msb, event.data[2]);
                    
                else
                    return changeByte(getParamTarget().lsb, event.data[2]);
            }
            else
            {
                if(event.data[1] < 96)
                    return changeByte(ccTable[event.data[1]], event.data[2]);
            }
        }

        if(event.statusCode == MidiStatusCode.pitchWheel)
        {
            return changeByte(pitchWheel.msb, event.data[2]) ||
                    changeByte(pitchWheel.lsb, event.data[1]);
        }

        return false;
    }

    //Returns a reference to the correct entry
    //There may be a cleaner way to do this than using pointers but I haven't found one yet.
    MidiBytePair* getParamTarget()
    {
        switch(paramType)
        {
            case ParamType.rpn:
                if(rpnPointer.msb == 127 || rpnPointer.lsb == 127)
                    return null;
            
                return &rpnTable[rpnPointer.msb][rpnPointer.lsb];

            case ParamType.nrpn:
                if(nrpnPointer.msb == 127 || nrpnPointer.lsb == 127)
                    return null;
                    
                return &rpnTable[nrpnPointer.msb][nrpnPointer.lsb];

            default:
                return null;
        }
    }

    //Changes a ubyte, and return true if the new value is different than the old one.
    bool changeByte(ref ubyte val, ubyte newVal)
    {
        ubyte oldVal = val;
        val = newVal;

        return newVal != oldVal;
    }

    //Returns a "controlAddress" that determines what control has changed.
    ChannelStateChange getChangedControl(immutable MidiEvent event)
    {
        import std.format;
        
        ChannelStateChange change;
        
        if(event.statusCode == MidiStatusCode.controlChange)
        {
            if(event.data[1] == 6 || event.data[1] == 38)
            {
                if(paramType == ParamType.nrpn)
                {
                    change.controlID = format("nrpn%d:%d", nrpnPointer.msb, nrpnPointer.lsb);
                    change.value = getParamTarget().normalizedValue();
                }

                if(paramType == ParamType.rpn)
                {
                    change.controlID = format("rpn%d:%d", rpnPointer.msb, rpnPointer.lsb);
                    change.value = getParamTarget().normalizedValue();
                }
            }
            else if(event.data[1] < 96)
            {
                change.controlID = format("cc%d", event.data[1]);
                change.value = event.data[2] / 128.0;
            }
        }

        return change;
    }
}
