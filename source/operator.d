module cyberparrot.operator;

public import cyberparrot.optree;
import cyberparrot.deviceheap;
import cyberparrot.clutil;
import std.stdio;
import cyberparrot.misc;

enum OperatorStatus
{
    ready,
    busy,
    done
}

class Operator
{
    OpTree tree;    //The OpTree that this Operator belongs to.
    
    string name;
    int width;
    OperatorStatus status = OperatorStatus.ready;

    BlockList output;
    BlockList[] temp;
    OParm[string] parms;
    
    Operator[] possibleDependencies;
    Operator[] possibleDependents;
    CLKernel[] kernels;
    
    //Reference count, used for assigning of blockIDs to Operators.
    int refCount = 0;

    abstract string operatorType();

    CLKernel createKernel(string functionName)
    {   
        return new CLKernel(operatorType, functionName);
    }

    CLMemory!uint parmOffsets(string parmID)
    {
        if((parmID in parms) is null)
            throw new Exception("Required parameter " ~ parmID ~ " was not defined in Operator " ~ name);

        return parms[parmID].cachedBlocks.offsets;
    }

    /*void generateOutBlockOffs()
    {
        outBlockOffs = new CLMemory!uint(width);
        uint[] hostOffs;
        hostOffs.length = width;
        hostOffs[] = outBlockIDs[] * tree.blockSize;
        outBlockOffs.write(hostOffs);
    }*/
    
    void updateRefCount(int delta)
    {
        assert(delta == 1 || delta == -1);
        
        if(refCount + delta < 0)
            throw new Exception("Operator reference count decremented below zero.");

        refCount += delta;

        //Reference count was decremented to zero, blockIDs can be unreserved.
        if(refCount == 0)
        {
            debugMSG("patch", writefln("[-] %s unreserved blocks", name));
            
            foreach(blockID; output.ids)
                tree.heap.unreserveBlock(blockID);
        }
    }
    
    void calculate()
    {        
        //Only run calculation of Operator is in 'ready' state.
        if(status == OperatorStatus.ready)
        {
            //Mark the operator as 'busy'
            status = OperatorStatus.busy;
            
            //Calculate all dependencies.
            foreach(parm; parms)
            {            
                foreach(dependency; parm.cachedDependencies)
                    dependency.calculate();
            }

            //Run the actual calculation.
            runKernels();
            
            //Mark the operator as 'done'
            status = OperatorStatus.done;
        }
        
        if(status == OperatorStatus.busy)
            throw new Exception("Circular dependency detected.");
    }

    void assignBlockIDs()
    {
        //Only run calculation of Operator is in 'ready' state.
        if(status == OperatorStatus.ready)
        {
            //Mark the operator as 'busy'
            status = OperatorStatus.busy;

            //Make sure that all dependencies get their blockIDs assigned first.
            foreach(parm; parms)
            {      
                foreach(operator; parm.getPotentialDependencies())
                    operator.assignBlockIDs();
            }
            
            output = new BlockList(tree.heap, width);
            output.ids = tree.heap.reserveAvailableBlocks(width);
            debugMSG("patch", writefln("[+] %s reserved blocks %s", name, output.ids));
            
            foreach(i; 0 .. neededTempBlocks)
            {
                auto newTemp = new BlockList(tree.heap, width);
                newTemp.ids = tree.heap.reserveAvailableBlocks(width);
                newTemp.sync();

                //Unreserve the blocks immediately because they won't be needed
                //after this Operator is done calculating.
                foreach(blockID; newTemp.ids)
                    tree.heap.unreserveBlock(blockID);
                
                temp ~= newTemp;
            }

            //Decrement reference count for all dependencies.
            foreach(parm; parms)
                parm.updateRefCounts(-1);
                
            //Mark the operator as 'done'
            status = OperatorStatus.done;
        }

        if(status == OperatorStatus.busy)
            throw new Exception("Circular Dependency detected while assigning BlockIDs");
    }
    
    BlockID[] getBlockIDs()
    {
        return output.ids;
    }

    //=====================================================================================================
    //All of the following functions are designed to be overridden by child classes of Operator, if needed.
    //=====================================================================================================
    //The setup() function should create any kernels needed to run the calculations,
    //as well as set their arguments.
    void setup()
    {
    }
    
    //Informs the OpTree how many temporary blocks may need to be reservered
    //for this Operator. Temporary blocks are considered "volatile" and should
    //only be read after being written to by the same Operator.
    int neededTempBlocks()
    {
        return 0;
    }

    //Actually run the kernels. Most of the time, we just run each one in a row
    //using these dimensions.
    void runKernels()
    {
        foreach(kernel; kernels)
            kernel.enqueue([tree.sampleCount, tree.activeVoices.length, width]);
    }

    //Whenever a voice is activated, some Operators may need to initialize certain
    //values in device memory.
    void initVoice(VoiceID vid)
    {
    }
}

//We need to be able to spawn operators of certain types based on string identifiers.
//For example, we should spawn an OperatorSine when we call spawners["sine"]()
Operator function(OpTree tree)[string] operatorSpawners;

//Every derived class of Operator has to register a "spawner" function in the operatorSpawners[] list.
//A spawned Operator must also be able to return a string identifying its exact type.
mixin template RegisterOperatorType(string oTypeName)
{
    static this()
    {
        static Operator spawner(OpTree tree)
        {
            auto o = new typeof(this)();
            o.tree = tree;
            return o;
        }
        
        operatorSpawners[oTypeName] = &spawner;
    }

    override string operatorType()
    {
        return oTypeName;
    }
}
