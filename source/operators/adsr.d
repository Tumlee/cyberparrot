module cyberparrot.operators.adsr;

import cyberparrot.operator;
import cyberparrot.clutil;

class OperatorADSR : Operator
{
    mixin RegisterOperatorType!"adsr";

    override void setup()
    {
        auto kernel = createKernel("adsr");

        auto pClockOff = tree.resolveBlockIDs("pressClock")[0] * tree.blockSize;
        auto rClockOff = tree.resolveBlockIDs("releaseClock")[0] * tree.blockSize;

        kernel.setArgs(tree.heap.memory, tree.vOff,
                        parmOffsets("attackTime"),
                        parmOffsets("decayTime"),
                        parmOffsets("sustainLevel"),
                        parmOffsets("releaseTime"),
                        parmOffsets("peak"),
                        parmOffsets("base"),
                        output.offsets,
                        pClockOff,
                        rClockOff);
                        
        kernels ~= kernel;
    }
}
