module cyberparrot.operators.triangle;

import cyberparrot.operator;
import cyberparrot.clutil;

class OperatorTriangle : Operator
{   
    mixin RegisterOperatorType!"triangle";

    override void setup()
    {
        auto kernel = createKernel("triangle");

        kernel.setArgs(tree.heap.memory, tree.vOff, parmOffsets("in"), output.offsets);
        kernels ~= kernel;
    }
}
