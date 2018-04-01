module cyberparrot.misc;

import std.algorithm;
import std.stdio;
import std.conv;

shared string[] globalArgs;

void saveArgs(string[] args)
{
    foreach(arg; args)
        globalArgs ~= arg;
}

bool flagExists(string flagName)
{
    return globalArgs.canFind("--" ~ flagName);
}

//Conditional debugging tools.
private bool[string] debugFlagCache;

void debugMSG(string debugType, lazy void printFunc)
{
    if((debugType in debugFlagCache) is null)
        debugFlagCache[debugType] = flagExists("debug-" ~ debugType) || flagExists("debug-all");

    if(debugFlagCache[debugType] == true)
        printFunc();
}
