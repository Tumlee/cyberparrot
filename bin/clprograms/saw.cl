float modulo1(float x)
{
    return x - floor(x);
}

kernel void saw(    global float* heap,
                    constant uint* vOff,
                    constant uint* tOff,
                    constant uint* outOff)
{
    uint i = get_global_id(0);
    global float* t = heap + vOff[get_global_id(1)] + tOff[get_global_id(2)];
    global float* out = heap + vOff[get_global_id(1)] + outOff[get_global_id(2)];

   float wposition = t[i] + 0.25f;
   out[i] = (modulo1(wposition * 2.0f) * 2.0f) - 1.0f;
}
