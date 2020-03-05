module cyberparrot.patchmap;

import cyberparrot.serialization;
import std.stdio;
import std.string;
import std.algorithm;

//These are all the main types involved with a PatchMap, which is a
//bluerint that OpTree will use to spawn Operators and other objects
//and also connect them in the right configuration. 
alias ConnectionList = string[];

class PatchMap : Serializable
{
    @DataMember() OperatorInfo[string] operators;
    @DataMember() ParamDef[string] paramDefs;
    @DataMember() SwitchDef[string] switchDefs;
    @DataMember() OutputInfo[string] outputs;
}

class OperatorInfo : Serializable
{
    @DataMember() string type;
    @DataMember() ConnectionList[string] params;
    @DataMember() int width;
}

class ParamDef : Serializable
{
    @DataMember() float maxValue = 0;
    @DataMember() float minValue = 0;
    @DataMember() float defaultValue = 0;
    @DataMember() string controlID = null;
}

class SwitchDef : Serializable
{
    @DataMember() ConnectionList[] selections;
    @DataMember() int width;
    @DataMember() string controlID;
}

class OutputInfo : Serializable
{
    @DataMember() string connection;
}