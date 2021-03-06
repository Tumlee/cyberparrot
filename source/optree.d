module cyberparrot.optree;

import cyberparrot.patchmap;
import cyberparrot.optree;
import cyberparrot.operator;
import cyberparrot.clutil;
import cyberparrot.misc;
import cyberparrot.deviceheap;
import std.algorithm;
import std.range;
import std.ascii;
import std.stdio;
import std.conv;
import std.array;

alias VoiceID = uint;

class ParameterControl
{
    BlockID outBlockID;
    float maxValue;
    float minValue;
    float defaultValue;
}

//FIXME: Move this function elsewhere
bool isValidOperatorID(string id)
{
    if(id is null || id == "")
        return false;
        
    if(!id[0].isAlpha)
        return false;
        
    foreach(c; id)
    {
        if(!isAlphaNum(c))
            return false;
    }
    
    return true;
}

bool isValidConstant(string id)
{
    try
    {
        id.to!float;
    }
    catch(std.conv.ConvException)
    {
        return false;
    }
    
    return true;
}

struct OParmAddress
{
    string operatorID;
    string parameterID;
}

class OParm
{
    ConnectionList idList;
    int width;
    Operator[] cachedDependencies;
    BlockList cachedBlocks;

    OpTree tree;

    //If non-null, this OParm's list of blockIDs will be synced to device memory
    //in the form of block offsets, to be used as kernel parameters by Operators during calculation.
    //CLMemory!uint blockOffsets;
    this(OpTree t, ConnectionList l, int w, bool syncToDevice)
    {
        idList = l;
        width = w;
        tree = t;
        cachedBlocks = new BlockList(tree.heap, syncToDevice ? width : 0);
    }
    
    //Do these even need to be abstract?
    void updateDependencies()
    {
        Operator[] list;
    
        //From the idList, build a list of all operators that have to be
        //calculated before we can evaluate this parameter.
        foreach(id; idList.map!(tk => tk.findSplitBefore(":")[0]))
        {
            if(id in tree.operators)
                list ~= tree.operators[id];
            
            if(id in tree.switches)
                list ~= tree.switches[id].getCurrentDependencies();
        }
        
        cachedDependencies = list[];
    }
    
    void updateBlockIDs()
    {
        cachedBlocks.ids = idList.map!(id => tree.resolveBlockIDs(id)).joiner.array;

        if(cachedBlocks.canSync())
            cachedBlocks.sync();
    }

    //These functions increment/decrement the reference counts of
    //the Operators that they point to.
    void updateRefCounts(int delta)
    {
        foreach(operator; getPotentialDependencies())
            operator.updateRefCount(delta);
    }

    Operator[] getPotentialDependencies()
    {
        Operator[] list;
        
        foreach(id; idList.map!(tk => tk.findSplitBefore(":")[0]))
        {
            if(id in tree.operators)
                list ~= tree.operators[id];

            if(id in tree.switches)
                list ~= tree.switches[id].getPotentialDependencies();
        }
        
        return list;
    }
}

class SwitchableConnection
{
    OpTree tree;
    OParm[] selections;
    OParmAddress[] dependentParameters;
    int currentSelectionID = 0;

    this(OpTree t)
    {
        tree = t;
    }
    
    void addDependent(string operatorID, string parmID)
    {
        OParmAddress newDependent;
        newDependent.operatorID = operatorID;
        newDependent.parameterID = parmID;
        
        //Do not add dupliciate dependents...
        if(!dependentParameters.canFind(newDependent))
            dependentParameters ~= newDependent;
    }
    
    void updateDependentParameters()
    {
        foreach(address; dependentParameters)
        {
            assert(address.operatorID in tree.operators);
            auto operator = tree.operators[address.operatorID];
            
            assert(address.parameterID in operator.parms);
            auto parm = operator.parms[address.parameterID];
            
            parm.updateDependencies();
            parm.updateBlockIDs();
        }
    }
    
    void changeSelection(int newSelectionID)
    {
        if(newSelectionID < 0 || newSelectionID >= selections.length)
            throw new Exception("changeSelection: Bad selectionID");
            
        currentSelectionID = newSelectionID;
        updateDependentParameters();
    }
    
    OParm currentSelection()
    {
        return selections[currentSelectionID];
    }
    
    //Note, we can get away with returning the cached dependencies
    //and blockIDs because they should not be pointing to any
    //switchable connections.
    Operator[] getCurrentDependencies()
    {
        return currentSelection.cachedDependencies;
    }
           
    BlockID[] getBlockIDs()
    {
        return currentSelection.cachedBlocks.ids;
    }

    Operator[] getPotentialDependencies()
    {
        return selections.map!(s => s.getPotentialDependencies()).joiner.array;
    }
}

struct VoiceInfo
{
    uint voiceID;       //Actual voice number, should be 0 .. tree.voiceCount
    uint vOff;          //Voice offset for this particular voice.
    float noteFrequency;    //Used to generate "noteFrequency" block.
    float pStart = 0;   //PressClock for the start of this period.
    float pEnd = 0;     //PressClock for the end of this period.
    float rStart = 0;   //ReleaseClock for the start of this period.
    float rEnd = 0;     //ReleaseClock for the end of this period.
    uint clipPosition = -1; //Used for clipping voices at the exact point that their
                            //ADSR envelope "dies"
    bool isHeld = true; //Whether the note is held down.

    this(OpTree tree, VoiceID vid)
    {
        voiceID = vid;
        vOff = vid * tree.sampleCount;
    }

    void advanceClock(float tDelta)
    {
        pStart = pEnd;
        rStart = rEnd;
        
        if(isHeld)
            pEnd += tDelta;

        else
            rEnd += tDelta;
    }
}

//FIXME: Rename this class?
class OpTree
{
    PatchMap patch;
    Operator[string] operators;
    ParameterControl[string] parameters;
    BlockID[float] constants;
    OParm[string] outputs;
    SwitchableConnection[string] switches;
    float[2] pitchWheel = [0, 0];   //index 0 stores current value, 1 stores old value.
    uint voiceCount;
    uint sampleCount;
    uint zeroKernelSearchCount;

    //The list of currently active voices, stored as voice number.
    VoiceInfo[] activeVoices;

    //A heap of memory that will be used by all Parameters, constants, and Operators
    //that belong to this OpTree. This memory is subdivided into Blocks, which is in turn
    //subdivided into <voiceCount> voice "lines" that are <sampleCount> samples long.
    DeviceHeap heap;

    //Various kernels for setting the pressClocks/releaseClocks,
    //keeping track of voice information, and finalizing the audio stream.
    CLKernel prKernel;  //press-release kernel, for generating pressClock and releaseClock
    CLKernel fzKernel;  //For finding zeros in the envelope, so we know when to kill a voice.
    CLKernel gsKernel;  //Genereates the final stream.
    CLMemory!float stream;  //The final audio stream to be fed to the audio system.
    CLMemory!uint finds;    //List of potential zero positions found by fzKernel
    CLMemory!uint numFinds; //Number of potential zero positions returned by fzKernel
    CLMemory!uint clipPositions;    //The position at which gsKernel decided to clip each voice.
    CLMemory!VoiceInfo deviceVInfo; //Device-side mirror of activeVoices[]
    CLMemory!float devicePitchWheel;
        
    //Whether or not the OpTree has been "built" using OpTree.build()
    bool isBuilt = false;

    //Memory offsets for each voice, each value should be voiceID * sampleCount
    CLMemory!uint vOff;

    //Delta-time per sample
    float timeStep;
        
    this(PatchMap p, uint vc, uint sc, float sampleRate, uint zksc)
    {
        assert(p !is null);
        assert(vc != 0);
        assert(sc != 0);

        patch = p;
        voiceCount = vc;
        sampleCount = sc;
        zeroKernelSearchCount = zksc;
        timeStep = 1.0 / sampleRate;
    }

    //Returns the number of elements (not bytes) in a Block
    uint blockSize()
    {
        return voiceCount * sampleCount;
    }

    float[] readVoice(BlockID bid, VoiceID vid)
    {
        assert(bid < heap.numBlocks);
        assert(vid < voiceCount);
        
        float[] data;
        data.length = sampleCount;
        heap.memory.read(data, (bid * blockSize) + (sampleCount * vid));

        return data;
    }

    void writeVoice(BlockID bid, VoiceID vid, float[] data)
    {
        assert(data.length == sampleCount);
        assert(bid < heap.numBlocks);
        assert(vid < voiceCount);
        heap.memory.write(data, (bid * blockSize) + (sampleCount * vid));
    }

    void fillVoice(BlockID bid, VoiceID vid, float value)
    {
        assert(bid < heap.numBlocks);
        assert(vid < voiceCount);
        heap.memory.fill(value, (bid * blockSize) + (sampleCount * vid), sampleCount);
    }
    
    //Throws an exception if the given name is already taken up by
    //an existing Operator, Switchable Connection, or Parameter.
    void checkNameAvailable(string name, string type)
    {
        string conflictType = null;
    
        if(name in parameters)
            conflictType = "parameter";
            
        if(name in operators)
            conflictType = "operator";
            
        if(name in switches)
            conflictType = "switchdef";
            
        if(conflictType !is null)
        {
            throw new Exception("Cannot add " ~ type ~ " with name " ~ name ~
                                " because it already exists as a " ~ conflictType);
        }
    }
    
    void addParameter(ParamDef info, string id)
    {
        checkNameAvailable(id, "parameter");
       
        auto param = new ParameterControl; 
        
        param.maxValue = info.maxValue;
        param.minValue = info.minValue;
        param.defaultValue = info.defaultValue;
        param.outBlockID = heap.reserveAvailableBlocks(1)[0];
        
        debugMSG("patch", writefln("[+] Param %s reserved block %d", id, param.outBlockID));
        
        parameters[id] = param;
    }
    
    void addOperator(OperatorInfo info, string id)
    {
        checkNameAvailable(id, "operator");

        if((info.type in operatorSpawners) is null)
            throw new Exception("Cannot spawn Operator of invalid type " ~ info.type);
            
        auto operator = operatorSpawners[info.type](this);
        operators[id] = operator;
        operator.name = id;
        operator.width = info.width;
        
        foreach(parmID; info.params.byKey)
            operator.parms[parmID] = new OParm(this, info.params[parmID], info.width, true);
    }
    
    void addSwitch(SwitchDef switchDef, string id)
    {
        checkNameAvailable(id, "switch");
        
        auto sw = new SwitchableConnection(this);
        
        switches[id] = sw;
        
        foreach(selection; switchDef.selections)
            switches[id].selections ~= new OParm(this, selection, switchDef.width, false);
    }
    
    void addOutput(OutputInfo info, string id)
    {
        outputs[id] = new OParm(this, [info.connection], 1, false);
    }
    
    void registerSwitchDependents()
    {
        foreach(operatorID; operators.byKey)
        {
            auto operator = operators[operatorID];
            
            foreach(parmID; operator.parms.byKey)
            {
                auto parm = operator.parms[parmID];
                
                foreach(connectionID; parm.idList)
                {
                    auto id = connectionID.findSplitBefore(":")[0];
                    
                    if(id in switches)
                        switches[id].addDependent(operatorID, parmID);
                }
            }
        }
    }

    //Finds any numeric constants that may be used in a PatchMap
    //and assign them their own BlockIDs.
    void findConstants()
    {
        auto opConstants = patch.operators.byValue              //Every Operator
            .map!(operator => operator.params.byValue).joiner   //Every parameter
            .joiner;                                            //Every connection

        auto swConstants = patch.switchDefs.byValue         //Every switch
            .map!(switchDef => switchDef.selections).joiner //Every selection
            .joiner;                                        //Every connection.

        chain(opConstants, swConstants)
            .filter!(token => token.isValidConstant())  //Valid constants only
            .each!(token => registerConstant(token));   //Register them.
    }
    
    void registerConstant(string constantString)
    {
        float constant = constantString.to!float;
        
        if(constant in constants)
            return; //This constant already has a BlockID...
            
        constants[constant] = heap.reserveAvailableBlocks(1)[0];
    }
    
    //FIXME: There is error-checking and lookups here that
    //could be accomplished during the 'compile'
    BlockID[] resolveBlockIDs(string token)
    {
        int subAddress = -1; 
        BlockID[] list; 

        if(token.canFind(':'))
        {
            try
            {
                subAddress = token.findSplitAfter(":")[1].to!int;
            }
            catch(std.conv.ConvException)
            {
                throw new Exception("Invalid subAddress");
            }
        }
            
        string id = token.findSplitBefore(":")[0];
        
        //If this points to a constant, get the blockID for that constant.
        if(id.isValidConstant())
        {
            if(subAddress != -1)
                throw new Exception("subAddress detected in constant");
        
            float f = id.to!float;
            
            if(f in constants)
            {
                return [constants[f]];
            }
            else
            {
                throw new Exception("Failed to resolve constant " ~ id);
            }
        }        
        else if(id in parameters)
        {
            return [parameters[id].outBlockID];
        }
        else if(id in operators)
        {
            list = operators[id].getBlockIDs();
        }
        else if(id in switches)
        {
            list = switches[id].getBlockIDs();
        }
        else
        {
            throw new Exception("Unable to resolve blockIDs for connection " ~ token);
        }
        
        //'subadress' is set, extract only that specific element in the blockIDlist.
        if(subAddress == -1)
        {
            return list;
        }   
        else
        {
            if(subAddress < 1 || subAddress > list.length)
                throw new Exception("subAddress out of range");
                
            return [list[subAddress - 1]];
        }
    }
    
    void readyOperators()
    {
        //foreach(operator; operators)
        //    operator.status = OperatorStatus.ready;
        operators.byValue.each!(operator => operator.status = OperatorStatus.ready);
    }
    
    void calculate()
    {
        //Mark all Operators as "ready"
        readyOperators();

        //Run the kernels that generate pressClock/releaseClock
        runPrimaryKernels();

        //Start at each output and recurively call all the need Operators.
        foreach(root; outputs)
        {
            //FIXME: Unless outputs can connect to switchable parameters,
            //this can be moved to the build process.
            root.updateDependencies();
            
            auto dependencies = root.cachedDependencies;
            
            foreach(dependency; dependencies)
                dependency.calculate();
        }

        runStreamKernels();
        pruneVoices();
    }

    void runPrimaryKernels()
    {
        foreach(ref vinfo; activeVoices)
            vinfo.advanceClock(timeStep * sampleCount);
            
        syncVoices();
        devicePitchWheel.write(pitchWheel); //Sync pitchWheel values to device as well.
        
        prKernel.enqueue([sampleCount, activeVoices.length]);
    }

    void runStreamKernels()
    {
        gsKernel.setArg(3, cast(uint) activeVoices.length);
        fzKernel.enqueue([sampleCount / zeroKernelSearchCount, activeVoices.length]);
        gsKernel.enqueue([sampleCount]);

        //Store current pitchwheel value into "old" pitchwheel value.
        pitchWheel[1] = pitchWheel[0];
    }

    void build()
    {
        if(isBuilt)
            throw new Exception("Tried to build an already-built OpTree");

        heap = new DeviceHeap(blockSize);

        debugMSG("patch", writeln("[Spawning reserved parameters...]"));
        foreach(reservedID; ["isHeld", "noteFrequency", "noteVelocity", "pressClock", "releaseClock"])
            addParameter(new ParamDef, reservedID);
        
        debugMSG("patch", writeln("[Spawning parameters...]"));
        foreach(id; patch.paramDefs.byKey)
            addParameter(patch.paramDefs[id], id);
            
        debugMSG("patch", writeln("[Finding constants...]"));
        findConstants();
        
        debugMSG("patch", writeln("[Spawning operators...]"));
        foreach(id; patch.operators.byKey)
            addOperator(patch.operators[id], id);
            
        debugMSG("patch", writeln("[Spawning switches...]"));
        foreach(id; patch.switchDefs.byKey)
            addSwitch(patch.switchDefs[id], id);

        debugMSG("patch", writeln("[Regsitering Outputs...]"));
        foreach(id; patch.outputs.byKey)
            addOutput(patch.outputs[id], id);
        
        debugMSG("patch", writeln("[Reserving BlockIDs for Operators]"));
        assignBlockIDs();
            
        debugMSG("patch", writeln("[Caching BlockIDs/Dependencies for Switches...]"));
        foreach(sw; switches)
        {
            foreach(selection; sw.selections)
            {
                selection.updateBlockIDs();
                selection.updateDependencies();
            }
        }
        
        registerSwitchDependents();
        
        debugMSG("patch", writeln("[Caching BlockIDs/Dependencies for Operators...]"));
        foreach(operator; operators)
        {
            foreach(parm; operator.parms)
            {
                parm.updateBlockIDs();
                parm.updateDependencies();
            }
        }

        debugMSG("patch", writeln("[Caching BlockIDs for Outputs...]"));
        foreach(output; outputs)
            output.updateBlockIDs();

        debugMSG("patch", writeln("[Initializing main kernels...]"));
        initDeviceData();
        
        isBuilt = true;
    }

    void initDeviceData()
    {
        //Allocate the device heap.
        heap.allocate();
        vOff = new CLMemory!uint(voiceCount);
        devicePitchWheel = new CLMemory!float(2);

        //Create the kernel.
        prKernel = new CLKernel("adsr", "generatePRClocks");

        //Fill the proper memory.
        deviceVInfo = new CLMemory!VoiceInfo(voiceCount);
        prKernel.setArgs(heap.memory, deviceVInfo,
                        resolveBlockIDs("pressClock")[0] * blockSize,
                        resolveBlockIDs("releaseClock")[0] * blockSize,
                        resolveBlockIDs("noteFrequency")[0] * blockSize,
                        devicePitchWheel);

        //'searches per work item' must be a multiple of the block width.
        assert(sampleCount % zeroKernelSearchCount == 0);

        auto lBlock = outputs["lchannel"].cachedBlocks.ids[0];
        auto rBlock = outputs["rchannel"].cachedBlocks.ids[0];
        auto eBlock = outputs["exist"].cachedBlocks.ids[0];

        //Allocate the "finds" result array. Theoretically, its size should be the number of
        //groups there are. Unfortunately, it is not possible to predict the work group size
        //that OpenCL will choose when passing it a null 'work_group_size'
        //Thus, we have to assume the worst case (get_local_size == 1)
        finds = new CLMemory!uint((sampleCount / zeroKernelSearchCount) * voiceCount);
        numFinds = new CLMemory!uint(1);
        stream = new CLMemory!float(sampleCount * 2);   //FIXME: Should be number of channels?
        clipPositions = new CLMemory!uint(voiceCount);

        fzKernel = new CLKernel("build_stream", "findZeros");
        fzKernel.setArgs(heap.memory, deviceVInfo, eBlock * blockSize, zeroKernelSearchCount,
                            CLLocalArg!uint(fzKernel.getWorkGroupSize), finds, numFinds);

        gsKernel = new CLKernel("build_stream", "generateStream");
        gsKernel.setArgs(heap.memory, stream, deviceVInfo, CLEmptyArg(),
                            lBlock * blockSize, rBlock * blockSize, finds, numFinds, sampleCount / zeroKernelSearchCount);

        //Allow each Operator to set up its own device-side data
        foreach(operator; operators)
        {
            operator.output.sync();
            operator.setup();
        }

        //Initialize constants with their intended values.
        foreach(val; constants.byKey)
            heap.fillBlock(constants[val], val);

        //Initialize parameters with their default values.
        foreach(parm; parameters)
            heap.fillBlock(parm.outBlockID, parm.defaultValue);
    }

    void assignBlockIDs()
    {
        //Step one is to set the "reference count" for all Operators,
        //or how many times an Operator is referenced in an OParm. Don't forget to count outputs.
        foreach(parm; operators.byValue.map!(operator => operator.parms.byValue).joiner)
        {
            //foreach(parm; operator.parms)
                parm.updateRefCounts(1);
        }

        foreach(output; outputs)
            output.updateRefCounts(1);

        //FIXME: If any Operators have a reference count of zero at this point,
        //prune them, (do not forget to decrement the reference counts for that Operator)
        //That means this potentially would have to be done recursively.

        //Next, we traverse the tree as if we were doing a calculation.
        //Mark all Operators as "ready"
        readyOperators();

        //Start at each output and recurively call all the need Operators.
        foreach(root; outputs)
        {
            root.idList.map!(token => token.findSplitBefore(":")[0])    //Only look at portion before ':'
                .filter!(token => token in operators)   //Only process the tokens that point to Operators.
                .each!(id => operators[id].assignBlockIDs());
        }
    }

    //===============================================
    //These functions all relate to voice management.
    //===============================================
    void activateVoice(VoiceID vid, float freq, float vel)
    {
        VoiceInfo newVoice;
        newVoice.voiceID = vid;
        newVoice.vOff = newVoice.voiceID * sampleCount;
        newVoice.noteFrequency = freq;

        foreach(operator; operators)
            operator.initVoice(vid);

        fillVoice(resolveBlockIDs("noteVelocity")[0], vid, vel);

        activeVoices ~= newVoice;
    }

    void releaseVoice(VoiceID vid)
    {
        foreach(ref voice; activeVoices)
        {
            if(voice.voiceID == vid)
            {
                voice.isHeld = false;
                return;
            }
        }
    }

    void pruneVoices()
    {
        VoiceInfo[] returnedVoices;
        returnedVoices.length = activeVoices.length;
        deviceVInfo.read(returnedVoices);

        VoiceInfo[] newVoices;

        foreach(i; 0 .. activeVoices.length)
        {
            if(returnedVoices[i].clipPosition >= sampleCount)
                newVoices ~= activeVoices[i];
        }
        
        activeVoices = newVoices;
    }

    //Generate vOff in device memory.
    void syncVoices()
    {
        uint[] hostVOff;

        //Offset = voiceID * period length
        foreach(vinfo; activeVoices)
            hostVOff ~= vinfo.voiceID * sampleCount;

        //Sort the array (Might make kernels more efficient?)
        hostVOff = hostVOff.sort.array;
        activeVoices = activeVoices.sort!((a, b) => a.voiceID < b.voiceID).array;

        //Write these offsets to the device.
        vOff.write(hostVOff);

        //Do the same for activeVoices (vOff may not be necessary in the future)
        deviceVInfo.write(activeVoices);

        foreach(i; 0 .. activeVoices.length)
            assert(activeVoices[i].vOff == hostVOff[i]);
    }
}
