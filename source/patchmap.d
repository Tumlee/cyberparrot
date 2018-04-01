module cyberparrot.patchmap;

import cyberparrot.pvalue;
import std.stdio;
import std.string;
import std.algorithm;

//These are all the main types involved with a PatchMap, which is a
//bluerint that OpTree will use to spawn Operators and other objects
//and also connect them in the right configuration. 
alias ConnectionList = string[];

class PatchMap
{
    OperatorInfo[] operators;
    ParamDef[] paramDefs;
    SwitchDef[] switchDefs;
    OutputInfo[] outputs;
}

class OperatorInfo
{
    string name;
    string type;
    ParamInfo[] params;
    int width;
}

//FIXME: Rename?
class ParamInfo
{
    string id;
    ConnectionList connections;
}

class ParamDef
{
    string id;
    float maxValue;
    float minValue;
    float defaultValue;
    ubyte ccNum;

    this(string newID, float mn = 0, float mx = 0, float d = 0, ubyte cc = 0xff)
    {
        id = newID;
        minValue = mn;
        maxValue = mx;
        defaultValue = d;
        ccNum = cc;
    }
}

class SwitchDef
{
    string id;
    ConnectionList[] selections;
    int width;
    ubyte ccNum;
}

class OutputInfo
{
    string id;
    string connection;
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
                patch.operators ~= parseOperator(pv.elements[1]);
            }
            else if(directive == "paramDef")
            {
                patch.paramDefs ~= parseParamDef(pv.elements[1]);
            }
            else if(directive == "switchDef")
            {
                patch.switchDefs ~= parseSwitchDef(pv.elements[1]);
            }
            else if(directive == "output")
            {
                patch.outputs ~= parseOutput(pv.elements[1]);
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
    info.params = parseParams(pv.elements[2]);
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
                            pv.extractElement!ubyte(4));
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
    sdef.ccNum = pv.extractElement!ubyte(3);
    
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
