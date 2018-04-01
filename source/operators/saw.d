module cyberparrot.operators.saw;

import cyberparrot.operator;
import cyberparrot.clutil;

class OperatorSaw : Operator
{   
    mixin RegisterOperatorType!"saw";

    override void setup()
    {
        auto kernel = createKernel("saw");

        kernel.setArgs(tree.heap.memory, tree.vOff, parmOffsets("in"), output.offsets);
        kernels ~= kernel;
    }
}
