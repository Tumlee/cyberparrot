module cyberparrot.core;

public import std.concurrency; 
public import core.time;
public import core.thread;

import std.stdio;
import cyberparrot.misc;

//A CoreSignal is a basic message that is passed between cores,
//containing the sender's Core ID and a message.
immutable class CoreSignal
{
    string coreID;      //Registered name of the sending thread.
    string message;     //The message being sent.

    this(string cID, string msg)
    {   
        coreID = cID;
        message = msg;
    }
}

class Core
{
    //A flag determing whether this Core should terminate.
    bool terminating = false;
    
    //An identifier given to this Core by the parent thread that is
    //used for identification when sending messages back to the parent.
    string coreID;
    
    //The list of additional Cores spawned by this one.
    Tid[string] children;
    
    //Flag for checking if this is the main thread in the program.
    private bool isMainThread = false;

    this(string cID)
    {
        coreID = cID;
        
        //If this is the main thread, calling ownerTid throws an exception.
        try
        {
            auto o = ownerTid;
        }
        catch (TidMissingException e)
        {
            isMainThread = true;
        }
    }

    void setup()
    {
    }

    bool receiveMessage()
    {
        return false;
    }

    void tick()
    {
    }
    
    void end()
    {
    }

    final void run()
    {
        //Ensure all cores are terminated when finished running,
        //even when the cause is an unhandled exception.
        scope(success) terminate(true);
        scope(failure) terminate(false);
    
        setup();

        while(!terminating)
        {
            while(receiveMessage())
            {
                if(terminating)
                    return;
            }

            tick();
        }
    }
    
    final void terminate(bool isSuccess)
    {
        debugMSG("cores", writefln("[%s] Terminating thread...", coreID));
    
        //First, send a message to all active child cores telling them to terminate.
        foreach(childName; children.byKey)
            signalChild(childName, "terminate");
        
        //While waiting for all the children to terminate, run the core's end() function.
        end();
        
        //Wait for children to all be terminated before terminating yourself.
        while(children.length != 0)
        {
            //FIXME: Do we need to explicitly catch and discard Variants here?
            auto messageReceived = receiveTimeout(dur!"nsecs"(-1),
                            (immutable CoreSignal x) { handleTermination(x); });
        }
        
        //Let the parent know that the core has terminated.
        if(!isMainThread)
            signalParent(isSuccess ? "terminated" : "failed");
    }
    
    //===========================================================================
    //Handles a termination message from another Core. This function needs to be
    //called on all incoming CoreSignal messages to ensure the program terminates
    //gracefully, especially if a Core crashes or terminates abnormally.
    //===========================================================================
    final void handleTermination(immutable CoreSignal signal)
    {    
        //A null coreID means it's being sent by a parent Core.
        if(signal.coreID is null)
        {
            debugMSG("cores", writefln("[%s] Received \"%s\" from parent", coreID, signal.message));
        
            //Receiving a "terminate" message from parent means you terminate, no matter what.
            if(signal.message == "terminate")
                terminating = true;
        }
        else
        {
            debugMSG("cores", writefln("[%s] Received \"%s\" from %s", coreID, signal.message, signal.coreID));
        
            //CoreSignals should only be passed between direct parents and children.
            assert(childExists(signal.coreID),
                "Core " ~ coreID ~ " received CoreSignal from non-child Core" ~ signal.coreID);
                
            if(signal.message == "terminated" || signal.message == "failed")
                children.remove(signal.coreID);
        }
    }
    
    final bool childExists(string childName)
    {
        return (childName in children) !is null;
    }
    
    final void signalParent(string message)
    {
        assert(!isMainThread, "[" ~ coreID ~ "] Sent message to non-existent parent.");
        debugMSG("cores", writefln("[%s] Sent \"%s\" to parent", coreID, message));
        send(ownerTid, new immutable CoreSignal(coreID, message));
    }

    final void signalChild(string childID, string message)
    {
        debugMSG("cores", writefln("[%s] Sending \"%s\" to child \"%s\"", coreID, message, childID)); 
        assert(childExists(childID),
            "Core " ~ coreID ~ " tried to send CoreSignal to non-existent child " ~ childID);
    
        send(children[childID], new immutable CoreSignal(null, message));
    }
    
    final void spawnChild(void function(string coreID) spawner, string childID)
    {
        assert(!childExists(childID),
            "Tried to spawn child Core with already-used name " ~ childID);
            
        children[childID] = spawn(spawner, childID);
    }
}
