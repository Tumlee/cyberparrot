module cyberparrot.clutil;

public import derelict.opencl.cl;
import std.stdio;
import std.algorithm;
import std.string;
import std.conv;
import std.path;
import std.file;
import std.array;

import cyberparrot.misc;

//This library assumes a single context, queue, and device.
//This may change later but it seems unlikely given the headaches it would cause.
private cl_context context;
private cl_command_queue queue;
private cl_device_id chosenDevice;

//A cached list of built programs.
private cl_program[string] programs;

private bool useCLFillWorkaround = false;

//=====================================================================================
//This function initializes the OpenCL subsystem, opening a context, queue, and device.
//=====================================================================================
void initCL()
{
    debugMSG("opencl", writeln("[ INITIALIZING OPENCL ]"));
    DerelictCL.load();
    
    //Look through each available platform and gather a list of all
    //available OpenCL devices that support version 1.1 or later.
    auto platforms = getCLPlatforms();
    cl_device_id[] deviceIDs;
    
    foreach(platform; platforms)
    {
        foreach(deviceID; getPlatformDevices(platform))
        {
            if(deviceID.clVersionAtLeast(1, 1))
                deviceIDs ~= deviceID;
        }
    }
    
    //Load DerelictCL extensions.
    if(deviceIDs[0].clVersionAtLeast(1, 2))
    {
        DerelictCL.reload(CLVersion.CL12);     
        DerelictCL.loadEXT(platforms[0]);
    }
    else
    {
        useCLFillWorkaround = true;
        debugMSG("opencl", writefln("OpenCL version is older than 1.2, native filling not supported."));
    }
        
    //FIXME: Allow the user to select their device rather than picking the first one.
    if(deviceIDs.length == 0)
        throw new Exception("No OpenCL devices are available.");
        
    chosenDevice = deviceIDs[0];
    
    debugMSG("opencl", writefln("Selected OpenCL device: %s", getCLDeviceInfo!char(chosenDevice, CL_DEVICE_NAME)));
    
    int errorCode;
    context = clCreateContext(null, 1, &chosenDevice, null, null, &errorCode);
    checkErrorCode("clCeateContext", errorCode);
        
    queue = clCreateCommandQueue(context, chosenDevice, 0, &errorCode);
    checkErrorCode("clCreateCommandQueue", errorCode);
}

bool clVersionAtLeast(cl_device_id deviceID, int majorVersion, int minorVersion)
{
    int deviceMajor, deviceMinor;
    auto versionString = getCLDeviceInfo!char(deviceID, CL_DEVICE_VERSION).idup;
    
    //OpenCL version strings are always formated as "OpenCL <major.minor> ..."
    auto tokens = versionString.split;
    
    //If something is wrong with the version string, just return false.
    //That way, we can still run the program even if a malfunctioning device
    //or driver happens to be installed.
    if(tokens.length < 2)
        return false;
        
    if(!tokens[1].canFind('.'))
        return false;
    
    try
    {
        deviceMajor = tokens[1].findSplit(".")[0].to!int;
        deviceMinor = tokens[1].findSplit(".")[2].to!int;
    }
    catch(std.conv.ConvException)
    {
        return false;
    }
    
    //Check against major version first.
    //Only check against minor version if major versions are equal.
    if(deviceMajor > majorVersion)
        return true;
        
    if(deviceMajor < majorVersion)
        return false;
        
    return deviceMinor >= minorVersion;
}

//FIXME: Temporary
void temporaryCLFinish()
{
    clFinish(queue);
}

cl_platform_id[] getCLPlatforms()
{
    cl_platform_id[] platformIDs;
    cl_uint numPlatforms;
    
    clGetPlatformIDs(0, null, &numPlatforms);  
    platformIDs.length = numPlatforms;
    
    if(clGetPlatformIDs(numPlatforms, &platformIDs[0], null) != 0)
        throw new Exception("getCLPlatforms() threw an exception.");
        
    return platformIDs;
}

T[] getCLDeviceInfo(T)(cl_device_id deviceID, cl_device_info paramName)
{
    //First, find out how many bytes the parameter takes up.
    int errorCode;
    size_t paramSize;
    T[] parameter;
    
    errorCode = clGetDeviceInfo(deviceID, paramName, 0, null, &paramSize);
    checkErrorCode("clGetDeviceInfo", errorCode);
    
    parameter.length = paramSize / T.sizeof;
    
    errorCode = clGetDeviceInfo(deviceID, paramName, paramSize, parameter.ptr, null);
    checkErrorCode("clGetDeviceInfo", errorCode);
        
    return parameter;
}

T[] getCLPlatformInfo(T)(cl_platform_id platformID, cl_platform_info paramName)
{
    int errorCode;
    size_t paramSize;
    T[] parameter;
    
    errorCode = clGetPlatformInfo(platformID, paramName, 0, null, &paramSize);
    checkErrorCode("clGetPlatformInfo", errorCode);
        
    parameter.length = paramSize / T.sizeof;
        
    return parameter;
}

cl_device_id[] getPlatformDevices(cl_platform_id platformID)
{
    cl_device_id[] deviceIDs;
    cl_uint numDevices;
    
    //FIXME: Allow searching for any type of device, not just GPU
    clGetDeviceIDs(platformID, CL_DEVICE_TYPE_GPU, 0, null, &numDevices);
    deviceIDs.length = numDevices;

    //If there are no devices, just return an empty set.
    if(numDevices == 0)
        return [];
    
    clGetDeviceIDs(platformID, CL_DEVICE_TYPE_GPU, numDevices, &deviceIDs[0], null);
    return deviceIDs;
}

private size_t totalAllocated;

class CLMemory(T)
{
    //The actual OpenCL memory object.
    private cl_mem memory = null;
    
    //The number of elements contained in the memory buffer.
    private size_t numElements = 0;
    
    this()
    {
    }
    
    this(size_t newElements, cl_mem_flags flags = CL_MEM_READ_WRITE)
    {
        allocate(newElements, flags);
    }
    
    void allocate(size_t newElements, cl_mem_flags flags = CL_MEM_READ_WRITE)
    {
        free();
    
        int errorCode;
        memory = clCreateBuffer(context, flags, newElements * T.sizeof * 2, null, &errorCode);
        checkErrorCode("clCreateBuffer", errorCode);
            
        numElements = newElements;
        
        totalAllocated += numElements * T.sizeof;
    }
    
    void free()
    {
        //Do nothing 
        if(memory is null)
            return;
               
        totalAllocated -= numElements * T.sizeof;
    
        clReleaseMemObject(memory);
        numElements = 0;
    }
    
    void write(T[] buffer, size_t offset = 0)
    {
        size_t copyElements = min(buffer.length, numElements);
        
        if(copyElements == 0)
            return;
    
        int errorCode = clEnqueueWriteBuffer(queue, memory, true, offset * T.sizeof,
                            copyElements * T.sizeof, &buffer[0], 0, null, null);
        checkErrorCode("clEnqueueWriteBuffer", errorCode);
    }
    
    void fill(T value, size_t offset = 0, size_t elements = 0)
    {
        if(elements == 0)
            elements = numElements;
        
        if(useCLFillWorkaround == false)
        {
            //Ensure we don't write past the end of the cl_mem object.
            if(elements + offset >= numElements)
                elements = numElements - offset;
                
            int errorCode = clEnqueueFillBuffer(queue, memory, &value, T.sizeof,
                                                    offset * T.sizeof, elements * T.sizeof, 0, null, null);
            checkErrorCode("clEnqueueFillBuffer", errorCode);
        }
        else
        {
            T[] patternBuffer;
            patternBuffer.length = elements;
            patternBuffer[] = value;
            
            write(patternBuffer, offset);
        }
    }
    
    void read(T[] buffer, size_t offset = 0)
    {
        size_t copyElements = min(buffer.length, numElements);
        
        if(copyElements == 0)
            return;
        
        int errorCode = clEnqueueReadBuffer(queue, memory, true, offset * T.sizeof,
                            copyElements * T.sizeof, &buffer[0], 0, null, null);
        checkErrorCode("clEnqueueReadBuffer", errorCode);
    }

    //Returns an host-side array containing the contents of this memory.
    //This should be used only in areas where performance does not matter.
    T[] hostDup()
    {
        T[] array;
        array.length = numElements;
        read(array);
        return array;
    }
    
    @property cl_mem memoryObject()
    {
        return memory;
    }

    @property size_t length()
    {
        return numElements;
    }
    
    ~this()
    {
        free();
    }
}

size_t getTotalCLMemory()
{
    return totalAllocated;
}

struct CLLocalArg(T)
{
    size_t numElements;

    this(size_t n)
    {
        numElements = n;
    }
}

struct CLEmptyArg
{
}

class CLKernel
{
    private cl_kernel kernel;

    this(string programName, string functionName)
    {
        buildProgram(programName);
        
        int errorCode;        
        kernel = clCreateKernel(programs[programName], functionName.toStringz, &errorCode);
        
        if(errorCode != 0)
            throw new Exception("clCreateKernel failed with error code " ~ errorCode.to!string);
    }

    void setArg(T:CLMemory!U, U)(int argNumber, T arg)
    {
        setArg(argNumber, arg.memoryObject);
    }
    
    void setArg(T)(int argNumber, T arg)
    {        
        checkErrorCode("clSetKernelArg", clSetKernelArg(kernel, argNumber, T.sizeof, &arg));
    }

    void setArg(T:CLLocalArg!U, U)(int argNumber, T arg)
    {
        checkErrorCode("clSetKernelArg", clSetKernelArg(kernel, argNumber, arg.numElements * U.sizeof, null));
    }

    void setArg(T:CLEmptyArg)(int argNumber, T arg)
    {
        //No-op
    }

    void setArgs(U, V...)(U u, V v)
    {
        _setArgs(0, u, v);
    }

    private void _setArgs(int argNum)
    {
    }

    private void _setArgs(U, V...)(int argNumber, U u, V v)
    {
        setArg(argNumber, u);
        _setArgs(argNumber + 1, v);
    }
    
    void enqueue(size_t[] workSizes, size_t[] workOffsets = [])
    {
        //Don't bother enqueing anything if one of the dimensions are zero.
        foreach(ws; workSizes)
        {
            if(ws == 0)
                return;
        }
    
        //First, ensure that the workOffsets array is large enough.
        //We simply pad these with zeros if there aren't enough elements.
        size_t[] tempWorkOffsets;
        tempWorkOffsets.length = workSizes.length;
        
        foreach(i; 0 .. tempWorkOffsets.length)
            tempWorkOffsets[i] = i < workOffsets.length ? workOffsets[i] : 0;
            
        auto errorCode = clEnqueueNDRangeKernel(queue, kernel, cast(uint) workSizes.length,
                                &tempWorkOffsets[0], &workSizes[0], null, 0, null, null);
        checkErrorCode("clEnqueueNDRangeKernel", errorCode);
    }
    
    size_t getWorkGroupSize()
    {
        size_t wgs;
        
        int errorCode = clGetKernelWorkGroupInfo(kernel, chosenDevice, CL_KERNEL_WORK_GROUP_SIZE, size_t.sizeof, &wgs, null);
        checkErrorCode("clGetKernelWorkGroupInfo", errorCode);
        
        return wgs;
    }
}

private string getFileContents(string filename)
{
    string contents;
    
    File input;

    try
    {
        input = File(filename, "r");
    }
    catch(std.exception.ErrnoException)
    {
        return null;
    }
    
    foreach(line; input.byLineCopy)
    {
        contents ~= line;
        contents ~= '\n';
    }
        
    return contents;
}

void buildProgram(string programName)
{
    //No need to build the program if it's already there.
    if(programName in programs)
        return;
        
    //FIXME: Limit allowed characters in programName? 
    string filename = chainPath(thisExePath.dirName, "clprograms", programName ~ ".cl").array;

    int errorCode;
    
    auto source = getFileContents(filename);

    if(source is null)
        throw new Exception("Failed to open OpenCL source file: " ~ filename);
    
    auto sourceLength = source.length;
    
    const char* sPtr = &source[0];
    
    auto program = clCreateProgramWithSource(context, 1, &sPtr,
                                                &sourceLength, &errorCode);   
    checkErrorCode("clCreateProgramWithSource", errorCode);
    
    errorCode = clBuildProgram(program, 0, null, null, null, null);
    
    if(errorCode != 0)
    {
        printBuildLog(program);
        throw new Exception("Failed to build program");
    }
    
    programs[programName] = program;  
}

void printBuildLog(cl_program program)
{
    size_t logSize;
    clGetProgramBuildInfo(program, chosenDevice, CL_PROGRAM_BUILD_LOG, 0, null, &logSize);
    
    char[] log;
    log.length = logSize;
    
    clGetProgramBuildInfo(program, chosenDevice, CL_PROGRAM_BUILD_LOG, logSize, &log[0], null);
    
    writeln(log);
}

private void checkErrorCode(string functionName, int errorCode)
{
    if(errorCode != 0)
        throw new Exception(functionName ~ "() call failed with error code (" ~ errorCode.to!string ~ ")");
}

