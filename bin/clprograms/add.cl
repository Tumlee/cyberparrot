kernel void add_2o( global float* heap,
                    constant uint* vOff,
                    constant uint* o1Off,
                    constant uint* o2Off,
                    constant uint* outOff)
{
    uint i = get_global_id(0);
    global float* o1 = heap + vOff[get_global_id(1)] + o1Off[get_global_id(2)];
    global float* o2 = heap + vOff[get_global_id(1)] + o2Off[get_global_id(2)];
    global float* out = heap + vOff[get_global_id(1)] + outOff[get_global_id(2)];

    out[i] = o1[i] + o2[i];
}

kernel void add_3o( global float* heap,
                    constant uint* vOff,
                    constant uint* o1Off,
                    constant uint* o2Off,
                    constant uint* o3Off,
                    constant uint* outOff)
{
    uint i = get_global_id(0);
    global float* o1 = heap + vOff[get_global_id(1)] + o1Off[get_global_id(2)];
    global float* o2 = heap + vOff[get_global_id(1)] + o2Off[get_global_id(2)];
    global float* o3 = heap + vOff[get_global_id(1)] + o3Off[get_global_id(2)];
    global float* out = heap + vOff[get_global_id(1)] + outOff[get_global_id(2)];

    out[i] = o1[i] + o2[i] + o3[i];
}

kernel void add_4o( global float* heap,
                    constant uint* vOff,
                    constant uint* o1Off,
                    constant uint* o2Off,
                    constant uint* o3Off,
                    constant uint* o4Off,
                    constant uint* outOff)
{
    uint i = get_global_id(0);
    global float* o1 = heap + vOff[get_global_id(1)] + o1Off[get_global_id(2)];
    global float* o2 = heap + vOff[get_global_id(1)] + o2Off[get_global_id(2)];
    global float* o3 = heap + vOff[get_global_id(1)] + o3Off[get_global_id(2)];
    global float* o4 = heap + vOff[get_global_id(1)] + o4Off[get_global_id(2)];
    global float* out = heap + vOff[get_global_id(1)] + outOff[get_global_id(2)];

    out[i] = o1[i] + o2[i] + o3[i] + o4[i];
}

kernel void add_5o( global float* heap,
                    constant uint* vOff,
                    constant uint* o1Off,
                    constant uint* o2Off,
                    constant uint* o3Off,
                    constant uint* o4Off,
                    constant uint* o5Off,
                    constant uint* outOff)
{
    uint i = get_global_id(0);
    global float* o1 = heap + vOff[get_global_id(1)] + o1Off[get_global_id(2)];
    global float* o2 = heap + vOff[get_global_id(1)] + o2Off[get_global_id(2)];
    global float* o3 = heap + vOff[get_global_id(1)] + o3Off[get_global_id(2)];
    global float* o4 = heap + vOff[get_global_id(1)] + o4Off[get_global_id(2)];
    global float* o5 = heap + vOff[get_global_id(1)] + o5Off[get_global_id(2)];
    global float* out = heap + vOff[get_global_id(1)] + outOff[get_global_id(2)];

    out[i] = o1[i] + o2[i] + o3[i] + o4[i] + o5[i];
}
