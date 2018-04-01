kernel void sine(   global float* heap,
                    constant uint* vOff,
                    constant uint* tOff,
                    constant uint* outOff)
{
    uint i = get_global_id(0);
    global float* t = heap + vOff[get_global_id(1)] + tOff[get_global_id(2)];
    global float* out = heap + vOff[get_global_id(1)] + outOff[get_global_id(2)];

    out[i] = sinpi(2.0f * t[i]);
}
