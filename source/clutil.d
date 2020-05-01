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

private bool isProfilingEnabled = false;
private bool useCLFillWorkaround = false;

//=====================================================================================
//This function initializes the OpenCL subsystem, opening a context, queue, and device.
//=====================================================================================
void initCL()
{
    isProfilingEnabled = flagExists("opencl-profiling");
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
    debugMSG("opencl", writefln("Supported OpenCL version: %s", getCLVersionString(chosenDevice)));
    
    int errorCode;
    context = clCreateContext(null, 1, &chosenDevice, null, null, &errorCode);
    checkErrorCode("clCeateContext", errorCode);
        
    int hostQueueFlags = 0;

    if(isProfilingEnabled)
        hostQueueFlags |= CL_QUEUE_PROFILING_ENABLE;

    queue = clCreateCommandQueue(context, chosenDevice, hostQueueFlags, &errorCode);
    checkErrorCode("clCreateCommandQueue", errorCode);
}

string getCLVersionString(cl_device_id deviceID)
{
    return getCLDeviceInfo!char(deviceID, CL_DEVICE_VERSION).idup;
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
    private string programName;
    private string functionName;

    this(string progName, string funcName)
    {
        programName = progName;
        functionName = funcName;

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

        cl_event executionEvent;
        cl_event* eventPtr = isProfilingEnabled ? &executionEvent : null;
            
        auto errorCode = clEnqueueNDRangeKernel(queue, kernel, cast(uint) workSizes.length,
                                &tempWorkOffsets[0], &workSizes[0], null, 0, null, eventPtr);
        checkErrorCode("clEnqueueNDRangeKernel", errorCode);

        if(isProfilingEnabled)
        {
            cl_ulong queuedTime, submitTime, startTime, endTime;
            clWaitForEvents(1, eventPtr);

            clGetEventProfilingInfo(executionEvent, CL_PROFILING_COMMAND_START, cl_ulong.sizeof, &startTime, null);
            clGetEventProfilingInfo(executionEvent, CL_PROFILING_COMMAND_END, cl_ulong.sizeof, &endTime, null);
            cl_ulong startToEnd = endTime - startTime;

            writefln("[%s/%s %(%dx%)] %dns", programName, functionName, workSizes, startToEnd);
        }
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
        throw new Exception(functionName ~ "() call failed with " ~ getErrorString(errorCode));
}

string getErrorString(int errorCode)
{
    switch(errorCode)
    {
        // run-time and JIT compiler errors
        case 0: return "CL_SUCCESS";
        case -1: return "CL_DEVICE_NOT_FOUND";
        case -2: return "CL_DEVICE_NOT_AVAILABLE";
        case -3: return "CL_COMPILER_NOT_AVAILABLE";
        case -4: return "CL_MEM_OBJECT_ALLOCATION_FAILURE";
        case -5: return "CL_OUT_OF_RESOURCES";
        case -6: return "CL_OUT_OF_HOST_MEMORY";
        case -7: return "CL_PROFILING_INFO_NOT_AVAILABLE";
        case -8: return "CL_MEM_COPY_OVERLAP";
        case -9: return "CL_IMAGE_FORMAT_MISMATCH";
        case -10: return "CL_IMAGE_FORMAT_NOT_SUPPORTED";
        case -11: return "CL_BUILD_PROGRAM_FAILURE";
        case -12: return "CL_MAP_FAILURE";
        case -13: return "CL_MISALIGNED_SUB_BUFFER_OFFSET";
        case -14: return "CL_EXEC_STATUS_ERROR_FOR_EVENTS_IN_WAIT_LIST";
        case -15: return "CL_COMPILE_PROGRAM_FAILURE";
        case -16: return "CL_LINKER_NOT_AVAILABLE";
        case -17: return "CL_LINK_PROGRAM_FAILURE";
        case -18: return "CL_DEVICE_PARTITION_FAILED";
        case -19: return "CL_KERNEL_ARG_INFO_NOT_AVAILABLE";

        // compile-time errors
        case -30: return "CL_INVALID_VALUE";
        case -31: return "CL_INVALID_DEVICE_TYPE";
        case -32: return "CL_INVALID_PLATFORM";
        case -33: return "CL_INVALID_DEVICE";
        case -34: return "CL_INVALID_CONTEXT";
        case -35: return "CL_INVALID_QUEUE_PROPERTIES";
        case -36: return "CL_INVALID_COMMAND_QUEUE";
        case -37: return "CL_INVALID_HOST_PTR";
        case -38: return "CL_INVALID_MEM_OBJECT";
        case -39: return "CL_INVALID_IMAGE_FORMAT_DESCRIPTOR";
        case -40: return "CL_INVALID_IMAGE_SIZE";
        case -41: return "CL_INVALID_SAMPLER";
        case -42: return "CL_INVALID_BINARY";
        case -43: return "CL_INVALID_BUILD_OPTIONS";
        case -44: return "CL_INVALID_PROGRAM";
        case -45: return "CL_INVALID_PROGRAM_EXECUTABLE";
        case -46: return "CL_INVALID_KERNEL_NAME";
        case -47: return "CL_INVALID_KERNEL_DEFINITION";
        case -48: return "CL_INVALID_KERNEL";
        case -49: return "CL_INVALID_ARG_INDEX";
        case -50: return "CL_INVALID_ARG_VALUE";
        case -51: return "CL_INVALID_ARG_SIZE";
        case -52: return "CL_INVALID_KERNEL_ARGS";
        case -53: return "CL_INVALID_WORK_DIMENSION";
        case -54: return "CL_INVALID_WORK_GROUP_SIZE";
        case -55: return "CL_INVALID_WORK_ITEM_SIZE";
        case -56: return "CL_INVALID_GLOBAL_OFFSET";
        case -57: return "CL_INVALID_EVENT_WAIT_LIST";
        case -58: return "CL_INVALID_EVENT";
        case -59: return "CL_INVALID_OPERATION";
        case -60: return "CL_INVALID_GL_OBJECT";
        case -61: return "CL_INVALID_BUFFER_SIZE";
        case -62: return "CL_INVALID_MIP_LEVEL";
        case -63: return "CL_INVALID_GLOBAL_WORK_SIZE";
        case -64: return "CL_INVALID_PROPERTY";
        case -65: return "CL_INVALID_IMAGE_DESCRIPTOR";
        case -66: return "CL_INVALID_COMPILER_OPTIONS";
        case -67: return "CL_INVALID_LINKER_OPTIONS";
        case -68: return "CL_INVALID_DEVICE_PARTITION_COUNT";

        // extension errors
        case -1000: return "CL_INVALID_GL_SHAREGROUP_REFERENCE_KHR";
        case -1001: return "CL_PLATFORM_NOT_FOUND_KHR";
        case -1002: return "CL_INVALID_D3D10_DEVICE_KHR";
        case -1003: return "CL_INVALID_D3D10_RESOURCE_KHR";
        case -1004: return "CL_D3D10_RESOURCE_ALREADY_ACQUIRED_KHR";
        case -1005: return "CL_D3D10_RESOURCE_NOT_ACQUIRED_KHR";
        default: return "Unknown OpenCL error";
    }
}