kernel void wtransform( global float* heap,
                    constant uint* vOff,
                    constant uint* waveOff,
                    constant uint* peakOff,
                    constant uint* troughOff,
                    constant uint* outOff)
{
    uint i = get_global_id(0);
    global float* wave = heap + vOff[get_global_id(1)] + waveOff[get_global_id(2)];
    global float* peak = heap + vOff[get_global_id(1)] + peakOff[get_global_id(2)];
    global float* trough = heap + vOff[get_global_id(1)] + troughOff[get_global_id(2)];
    global float* out = heap + vOff[get_global_id(1)] + outOff[get_global_id(2)];

    out[i] = (wave[i] * (peak[i] - trough[i]) + peak[i] + trough[i]) * 0.5f;
}
