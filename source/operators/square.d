module cyberparrot.operators.square;

import cyberparrot.operator;
import cyberparrot.clutil;

class OperatorSquare : Operator
{   
    mixin RegisterOperatorType!"square";

    override void setup()
    {
        auto kernel = createKernel("square");

        kernel.setArgs(tree.heap.memory, tree.vOff, parmOffsets("in"), parmOffsets("duty"), output.offsets);
        kernels ~= kernel;
    }
}
