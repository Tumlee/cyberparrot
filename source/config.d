module cyberparrot.config;

public import cyberparrot.configpath;
import cyberparrot.misc;

import std.stdio;

import std.exception;
import std.path;
import std.array;
import std.algorithm;
import std.conv;

private string[string] configValues;

void extractConfigValues()
{
    File file;
    
    //All data should be extracted from cyberparrot.cfg    
    if(collectException!ErrnoException(file = File("cyberparrot.cfg".inConfigPath, "r")))
        throw new Exception("Unable to read cyberparrot.cfg");

    //The file format is simple key value pairs separated by whitespace.
    foreach(tokens; file.byLineCopy.map!split)
    {
        //Every line should have exactly 2 tokens.
        //We can safely skip any empty lines though.
        if(tokens.length == 0)
            continue;

        if(tokens.length != 2)
            throw new Exception("Syntax error in cyberparrot.cfg");

        configValues[tokens[0]] = tokens[1];
    }
}

T getConfigVar(T)(string varName, T defaultValue)
{
    T val;
        
    //First, check if this var has been passed as a command line parameter.
    foreach(i; 0 .. globalArgs.length - 1)
    {
        if(globalArgs[i] == "--" ~ varName)
        {
            if(collectException!ConvException(val = globalArgs[i + 1].to!T))
                throw new Exception("Expected parameter \'" ~ varName ~ "\' to be of type " ~ typeid(T).to!string);

            return val;
        }
    }

    //If it's not in the command line, either return the value from the config file,
    //or just return the defined default value.
    if(varName in configValues)
    {
        if(collectException!ConvException(val = configValues[varName].to!T))
            throw new Exception("Expected config variable \'" ~ varName ~ "\' to be of type " ~ typeid(T).to!string);

        return val;
    }

    return defaultValue;
}
