module cyberparrot.deviceheap;

import cyberparrot.clutil;

//A DeviceHeap is a range of device memory split up into blocks, which
//can be used to index ranges of data by using an identifier called a BlockID.
//The memory offset to a given block N is always (N * blockSize)
alias BlockID = uint;

//Before the heap is allocated, we must first determine how many
//blocks we need to allocate. To facilitate this, we 'reserve' and
//'unreserve' ranges of BlockIDs. Unreserving a BlockID means it can
//be reserved again.
class DeviceHeap
{
    //The actual range of memory.
    CLMemory!float heap;
    
    //Used to keep track of which BlockIDs are currently reserved.
    bool[BlockID] reservedBlocks;

    uint blockSize;

    this(uint bSize)
    {
        blockSize = bSize;
    }
    
    uint numBlocks()
    {
        return cast(uint) reservedBlocks.length;
    }

    CLMemory!float memory()
    {
        return heap;
    }

    //These functions pertain to the reserving and unreserving of BlockIDs.
    bool blockIsAvailable(BlockID id)
    {
        return reservedBlocks.get(id, false) == false;
    }
    
    void reserveBlock(BlockID id)
    { 
        if(!blockIsAvailable(id))
            throw new Exception("Tried to reserve an already-reserved BlockID");
    
        reservedBlocks[id] = true;
    }
    
    void unreserveBlock(BlockID id)
    {
        if(blockIsAvailable(id))
            throw new Exception("Tried to unreserve an already-available BlockID");
            
        reservedBlocks[id] = false;
    }
    
    //This function finds a contiguous range of free blockIDs of the given quantity.
    BlockID[] reserveAvailableBlocks(int amount)
    {
        for(BlockID startBlockID = 0; true; startBlockID++)
        {
            bool rangeIsFree = true;        
        
            foreach(offset; 0 .. amount)
            {
                if(!blockIsAvailable(startBlockID + offset))
                {
                    rangeIsFree = false;
                    break;
                }
            }
            
            if(rangeIsFree == false)
                continue;   //There's a reserved block in the way...
            
            //If we've made it here, it means all the blocks we need are
            //available, so we reserve them and return the blocks.
            BlockID[] resultBlocks;
            
            foreach(offset; 0 .. amount)
            {
                resultBlocks ~= (startBlockID + offset);
                reserveBlock(startBlockID + offset);
            }
            
            return resultBlocks;
        }
    }

    void allocate()
    {
        assert(heap is null);

        heap = new CLMemory!float(numBlocks * blockSize);
    }

    //These functions all pertain to the reading to, and
    //writing from, specific blocks in the heap.
    float[] readBlock(BlockID bid)
    {
        assert(bid < numBlocks);
        
        float[] data;
        data.length = blockSize;
        heap.read(data, bid * blockSize);

        return data;
    }

    void writeBlock(BlockID bid, float[] data)
    {
        assert(data.length == blockSize);
        assert(bid < numBlocks);
        heap.write(data, bid * blockSize);
    }
    
    void fillBlock(BlockID bid, float value)
    {
        assert(bid < numBlocks);
        heap.fill(value, bid * blockSize, blockSize);
    }
}

//A BlockList consists of a list of BlockIDs, plus a device-side
//list of offsets that point to the start of the given Blocks in the DeviceHeap.
class BlockList
{
    const DeviceHeap deviceHeap;  //The DeviceHeap that this BlockList belongs to.
    
    BlockID[] ids;
    CLMemory!uint offsets;

    this(const DeviceHeap dh, uint width)
    {
        deviceHeap = dh;

        //If width is zero, leave "offsets" null, meaning this
        //BlockList does not sync offsets to the device.
        if(width != 0)
            offsets = new CLMemory!uint(width);
    }

    void sync()
    {
        assert(canSync());

        //We need to generate a "wrapped" host copy first, because
        //the number of BlockIDs may be fewer than the number of offsets
        //that need to be generated.
        uint[] hostArray;
        hostArray.length = offsets.length;

        foreach(i; 0 .. hostArray.length)
            hostArray[i] = ids[i % $] * deviceHeap.blockSize;

        //Write the offsets to the device.
        offsets.write(hostArray);
    }

    bool canSync()
    {
        return (ids.length != 0) && (offsets !is null);
    }

    //Reserve the

    /*BlockID[] wrapBlockIDList(BlockID[] baseList, size_t width)
    {
        assert(baseList.length != 0);
        
        BlockID[] returnList;
        returnList.length = width;
        
        foreach(i; 0 .. width)
            returnList[i] = baseList[i % $];
        
        return returnList;
    }*/
}
