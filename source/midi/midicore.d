module cyberparrot.midi.midicore;

import std.stdio;
import std.conv;
import std.exception;

import derelict.portmidi.portmidi;
import derelict.portmidi.porttime;

import cyberparrot.core;
import cyberparrot.midi.midievent;
import cyberparrot.time;
import cyberparrot.misc;

//FIXME: Ensure PortMidi and all streams are closed when this object is destroyed.
class MidiCore : Core
{
    private PmDeviceID selectedDevice = pmNoDevice; //pmNoDevice means to open the default device.
    private PmStream* stream = null;
    private bool inSysex = false;
    private ubyte[] sysexData;
    
    this(string tName)
    {
        super(tName);
    }
    
    override void setup()
    {
        debugMSG("midi", writeln("[ INITIALIZING PORTMIDI ]"));
    
        DerelictPortMidi.load();
        DerelictPortTime.load();

        Pm_Initialize();
        
        debugMSG("midi", printDeviceList());
    }
    
    override void tick()
    {
        pollStream();
    }
    
    override bool receiveMessage()
    {
        //FIXME: Handle Variants here as well.
        return receiveTimeout(dur!"nsecs"(-1),
                            (immutable CoreSignal c) { handleMessage(c); });
    }
    
    private void handleMessage(immutable CoreSignal status)
    {
        handleTermination(status);
        
        //FIXME: Create a class for the below messages.
        if(status.message == "list-devices")
            printDeviceList();
            
        if(status.message == "open-stream")
            openStream();
            
        if(status.message == "close-stream")
            closeStream();
    }
    
    void printDeviceList()
    {
        writeln("Available MIDI Input Devices:");
            
        foreach(id; 0 .. Pm_CountDevices())
        {   
            auto deviceInfo = Pm_GetDeviceInfo(id);
            assert(deviceInfo !is null);
        
            if(deviceInfo.input)
                writefln("    [DeviceID %d] %s", id, deviceInfo.name.to!string); 
        }
        
        writeln();
    }
    
    //=========================================================================================
    //Closes any open MIDI streams and opens a new one with the given deviceID.
    //For further information on what the other arguments do, check the PortMidi documentation.
    //=========================================================================================
    void openStream()
    {
        //Close any open MIDI stream before doing anything else.
        closeStream();
        
        //Use the selected input device, or use PortMidi's default input device if not set.
        auto deviceID = selectedDevice == pmNoDevice ? Pm_GetDefaultInputDeviceID() : selectedDevice;
    
        if(Pm_GetDeviceInfo(deviceID) is null)
            throw new Exception("openStream() was supplied an invalid deviceID.");
    
        //Open the new stream.    
        Pm_OpenInput(&stream, deviceID, null, 0, null, null);
        
        debugMSG("midi", writefln("Opened device \'%s\' for MIDI input stream", Pm_GetDeviceInfo(deviceID).name.to!string));
        
        //FIXME: Check for errors after opening the stream.      
        //FIXME: Allow for a custom "reset" function that can be called by child classes?
    }
    
    //=============================================================================================
    //Closes the currently open MIDI stream. This also removes any SysEx data that the MidiReceiver
    //may have been collecting at the time, since the data is not complete.
    //=============================================================================================
    void closeStream()
    {       
        //Reset SysEx flag and data.
        killSysex();
        
        if(stream !is null)
        {
            //The return type of Pm_Close() is PmError, so even though the PortMidi documentation
            //doesn't mention any conditions that could cause an error, we'll check anyway.
            auto error = Pm_Close(stream);
            
            if(error != pmNoError)
                throw new Exception("closeStream() encountered an error in Pm_Close(): "
                                        ~ Pm_GetErrorText(error).to!string);
                
            stream = null;
        }
    }
    
    //=============================================================================================
    //Reads exactly one MIDI event from the input stream, or returns instantly if there's no input.
    //=============================================================================================
    void pollStream()
    {    
        if(stream is null)
            return;
    
        auto result = Pm_Poll(stream);

        if(result == true)
        {
            PmEvent event;
            Pm_Read(stream, &event, 1);
            
            ubyte[3] eventData = [  Pm_MessageStatus(event.message).to!ubyte,
                                    Pm_MessageData1(event.message).to!ubyte,
                                    Pm_MessageData2(event.message).to!ubyte];
                                             
            if(inSysex)
            {
                eatSysexData(eventData);
            }
            else
            {
                //Ignore events that don't have the MSB set, since they might be
                //left over from an earlier Sysex that we didn't catch.
                if(eventData[0] & 0x80)
                {
                    //Beginning of a Sysex message. Feed it the next two bytes.
                    if(eventData[0] == 0xf0)
                    {
                        inSysex = true;
                        eatSysexData(eventData[1 .. $]);
                    }
                    else 
                    {
                        debugMSG("midi", writefln("Received MidiEvent [%2x, %2x, %2x]",
                                                    eventData[0], eventData[1], eventData[2]));
                                                                        
                        send(ownerTid, new immutable MidiEvent( eventData[0],
                                                                eventData[1],
                                                                eventData[2],
                                                                currentTime()));
                    }
                }
            }
                      
            return;
        }
        
        //If the result is neither true nor false, it measn Pm_Poll returned an error.
        if(result != false)
            throw new Exception("Pm_Poll returned an error: " ~ Pm_GetErrorText(result).to!string);
    }
    
    void eatSysexData(ubyte[] data)
    {
        foreach(datum; data)
        {
            if(datum & 0x80)
            {
                //The documentation on PortMidi is not very clear, but based on some testing
                //it appears the library automatically separates realtime events that occur
                //during a Sysex transmission, placing them right before the beginning of
                //the SOX event.
            
                //PortMidi also seems to automatically filter abnormally terminated Sysex
                //messages. To be safe, though, we are still going to assert this.
                assert(datum == 0xf7, "eatSysexData() received a non-EOX status byte.");
                
                //FIXME: ACTUALLY SEND THE SYSEX MESSAGE BACK TO THE MAIN THREAD.
                debugMSG("midi", write("Sysex: "));
                foreach(sysexDatum; sysexData)
                    debugMSG("midi", writef(" %02x", sysexDatum));
                debugMSG("midi", writeln());
                
                killSysex();    //Flush all the Sysex data.
                return;         //Ignore any padding that comes after the EOX.
            }
            
            sysexData ~= datum;
        }
    }
    
    void killSysex()
    {
        inSysex = false;
        sysexData = [];
    }
    
    static void coreThread(string newCoreID)
    {
        auto core = new MidiCore(newCoreID);
        core.run();
    }
}

