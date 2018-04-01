float modulo1(float x)
{
    return x - floor(x);
}

kernel void triangle(   global float* heap,
                        constant uint* vOff,
                        constant uint* tOff,
                        constant uint* outOff)
{
    uint i = get_global_id(0);
    global float* t = heap + vOff[get_global_id(1)] + tOff[get_global_id(2)];
    global float* out = heap + vOff[get_global_id(1)] + outOff[get_global_id(2)];

    float wp = modulo1(t[i] + .25f);
   
    out[i] = (wp < 0.5f) ?
                ((4.f * wp) - 1.f) :
                ((-4.f * wp) + 3.f);
}
