module cyberparrot.patchmap;

import cyberparrot.pvalue;
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
    string name;
    @DataMember() string type;
    //@DataMember() ParamInfo[] params;
    @DataMember() ConnectionList[string] params;
    @DataMember() int width;
}

//FIXME: Rename?
class ParamInfo : Serializable
{
    @DataMember() string id;
    @DataMember() ConnectionList connections;
}

class ParamDef : Serializable
{
    string id;
    @DataMember() float maxValue;
    @DataMember() float minValue;
    @DataMember() float defaultValue;
    @DataMember() string controlID;

    this(string newID, float mn = 0, float mx = 0, float d = 0, string ci = null)
    {
        id = newID;
        minValue = mn;
        maxValue = mx;
        defaultValue = d;
        controlID = ci;
    }
}

class SwitchDef : Serializable
{
    string id;
    @DataMember() ConnectionList[] selections;
    @DataMember() int width;
    @DataMember() string controlID;
}

class OutputInfo : Serializable
{
    string id;
    @DataMember() string connection;
}

//FIXME: Exceptions are thrown here, but not handled as of yet.

//================================================================================
//These parsing functions return their correspoding data type, throwing an
//exception if the input PValue is not properly formatted.
//================================================================================
string[] getFileLines(string fileName)
{
    string[] lines;
    
    File input;

    try
    {
        input = File(fileName, "r");
    }
    catch(std.exception.ErrnoException)
    {
        return null;
    }
    
    foreach(line; input.byLineCopy)
        lines ~= line;
        
    return lines;
}

PatchMap readPatchMap(string filename)
{
    auto lines = getFileLines(filename);    

    PatchMap patch = new PatchMap;
    
    PValue[] pvs;
    
    foreach(line; lines)
    {
        //Strip the line of comments first.
        string expression = line.findSplitBefore(";;")[0];
        
        if(expression.empty)
            continue;
        
        pvs ~= parsePValue(expression);
    }

    //Extract all the data from the resulting PValues and throw
    //them into a PatchMap structure.
    foreach(pv; pvs)
    {
        try
        {
            pv.validateNumElements(2, "CPMLine");
            pv.validatePVType(0, true, "CPMLine");
            pv.validatePVType(1, false, "CPMLine");
            
            string directive = pv.elements[0].value;
            
            if(directive == "operator")
            {
                OperatorInfo operator = parseOperator(pv.elements[1]);
                patch.operators[operator.name] = operator;
            }
            else if(directive == "paramDef")
            {
                ParamDef paramDef = parseParamDef(pv.elements[1]);
                patch.paramDefs[paramDef.id] = paramDef;
            }
            else if(directive == "switchDef")
            {
                SwitchDef switchDef = parseSwitchDef(pv.elements[1]);
                patch.switchDefs[switchDef.id] = switchDef;
            }
            else if(directive == "output")
            {
                OutputInfo output = parseOutput(pv.elements[1]);
                patch.outputs[output.id] = output;
            }
            else
            {
                throw new Exception("Unknown directive " ~ directive ~ " in patch map");
            }
        }
        catch(Exception e)
        {
            writefln("Error while reading from PValue: %s", pv.express());
            writeln(e.msg);
            throw new Exception("readPatchMap() threw an exception");
        }
    }
    
    return patch;
}

OperatorInfo parseOperator(const PValue pv)
{
    OperatorInfo info = new OperatorInfo;

    pv.validateNumElements(4, "OperatorInfo");
    pv.validatePVType(0, true, "OperatorInfo");
    pv.validatePVType(1, true, "OperatorInfo");
    pv.validatePVType(2, false, "OperatorInfo");
    pv.validatePVType(3, true, "OperatorInfo");

    info.name = pv.elements[0].value;
    info.type = pv.elements[1].value;
    ParamInfo[] params = parseParams(pv.elements[2]);
    
    foreach(param; params)
        info.params[param.id] = param.connections;

    info.width = pv.extractElement!int(3);
    
    return info;
}

ParamInfo[] parseParams(const PValue pv)
{
    ParamInfo[] params;

    //Any number of parameters are allowed here, including zero.    
    foreach(i; 0 .. pv.numElements())
    {
        //Make sure it's a list.
        pv.validatePVType(i, false, "ParamList");
        params ~= parseParam(pv.elements[i]);
    }
    
    return params;
}

ParamInfo parseParam(const PValue pv)
{
    ParamInfo info = new ParamInfo;

    pv.validateNumElements(2, "ParamInfo");
    pv.validatePVType(0, true, "ParamInfo");
    pv.validatePVType(1, false, "ParamInfo");
    
    info.id = pv.elements[0].value;
    info.connections = parseConnectionList(pv.elements[1]);
    
    return info;
}

ConnectionList parseConnectionList(const PValue pv)
{
    ConnectionList connectionList;
    
    foreach(i; 0 .. pv.numElements())
    {
        pv.validatePVType(i, true, "ConnectionList");
        connectionList ~= pv.elements[i].value;
    }
    
    return connectionList;
}

ConnectionList[] parseSelectionList(const PValue pv)
{
    ConnectionList[] selectionList;
    
    foreach(i; 0 .. pv.numElements())
    {
        pv.validatePVType(i, false, "SelectionList");
        selectionList ~= parseConnectionList(pv.elements[i]);
    }
    
    return selectionList;
}

ParamDef parseParamDef(const PValue pv)
{
    pv.validateNumElements(4, "ParamDef");
    pv.validatePVType(0, true, "ParamDef");
    pv.validatePVType(1, true, "ParamDef");
    pv.validatePVType(2, true, "ParamDef");
    pv.validatePVType(3, true, "ParamDef");
    pv.validatePVType(4, true, "ParamDef");

    return new ParamDef(    pv.elements[0].value,
                            pv.extractElement!float(1),
                            pv.extractElement!float(2),
                            pv.extractElement!float(3),
                            pv.extractElement!string(4));
}

SwitchDef parseSwitchDef(const PValue pv)
{
    SwitchDef sdef = new SwitchDef;
    
    pv.validateNumElements(4, "SwitchDef");
    pv.validatePVType(0, true, "SwitchDef");
    pv.validatePVType(1, false, "SwitchDef");
    pv.validatePVType(2, true, "SwitchDef");
    pv.validatePVType(3, true, "SwitchDef");
    
    sdef.id = pv.elements[0].value;
    sdef.selections = parseSelectionList(pv.elements[1]);
    sdef.width = pv.extractElement!int(2);
    sdef.controlID = pv.extractElement!string(3);
    
    return sdef;
}

OutputInfo parseOutput(const PValue pv)
{
    OutputInfo info = new OutputInfo;
    
    pv.validateNumElements(2, "OutputInfo");
    pv.validatePVType(0, true, "OutputInfo");
    pv.validatePVType(1, true, "OutputInfo");
    
    info.id = pv.elements[0].value;
    info.connection = pv.elements[1].value;
    
    return info;
}
