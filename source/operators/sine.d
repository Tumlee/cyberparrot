module cyberparrot.operators.sine;

import cyberparrot.operator;
import cyberparrot.clutil;

class OperatorSine : Operator
{   
    mixin RegisterOperatorType!"sine";

    override void setup()
    {
        auto kernel = createKernel("sine");

        kernel.setArgs(tree.heap.memory, tree.vOff, parmOffsets("in"), output.offsets);
        kernels ~= kernel;
    }
}
