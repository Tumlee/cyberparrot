kernel void subtract(   global float* heap,
                        constant uint* vOff,
                        constant uint* o1Off,
                        constant uint* o2Off,
                        constant uint* outOff)
{
    uint i = get_global_id(0);
    global float* o1 = heap + vOff[get_global_id(1)] + o1Off[get_global_id(2)];
    global float* o2 = heap + vOff[get_global_id(1)] + o2Off[get_global_id(2)];
    global float* out = heap + vOff[get_global_id(1)] + outOff[get_global_id(2)];

    out[i] = o1[i] - o2[i];
}
