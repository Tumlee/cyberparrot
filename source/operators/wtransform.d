module cyberparrot.operators.wtransform;

import cyberparrot.operator;
import cyberparrot.clutil;

//An Operator that takes an incoming wave that oscillates from 1 to -1 and instead
//makes it oscillate from "peak" to "trough" instead.
class OperatorWTransform : Operator
{   
    mixin RegisterOperatorType!"wtransform";

    override void setup()
    {
        auto kernel = createKernel("wtransform");

        kernel.setArgs(tree.heap.memory, tree.vOff,
                        parmOffsets("wave"),
                        parmOffsets("peak"),
                        parmOffsets("trough"),
                        output.offsets);
                        
        kernels ~= kernel;
    }
}
