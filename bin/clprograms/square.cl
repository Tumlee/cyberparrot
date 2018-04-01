float modulo1(float x)
{
    return x - floor(x);
}

kernel void square( global float* heap,
                    constant uint* vOff,
                    constant uint* tOff,
                    constant uint* dutyOff,
                    constant uint* outOff)
{
    uint i = get_global_id(0);
    global float* t = heap + vOff[get_global_id(1)] + tOff[get_global_id(2)];
    global float* duty = heap + vOff[get_global_id(1)] + dutyOff[get_global_id(2)];
    global float* out = heap + vOff[get_global_id(1)] + outOff[get_global_id(2)];

    out[i] = modulo1(t[i]) < duty[i] ? 1.0 : -1.0;
}
