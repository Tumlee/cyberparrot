module cyberparrot.operators.multiply;

import cyberparrot.operator;
import cyberparrot.clutil;
import std.conv;

class OperatorMultiply : Operator
{
    mixin RegisterOperatorType!"multiply";

    override void setup()
    {
        CLMemory!uint[] operands;

        foreach(parm; parms)
            operands ~= parm.cachedBlocks.offsets;
           
        for(int opWidth = 5; opWidth > 1; opWidth--)
        {
            while(operands.length >= opWidth)
            {
                auto kernel = createKernel("multiply_" ~ opWidth.to!string ~ "o");

                kernel.setArgs(tree.heap.memory, tree.vOff);

                foreach(o; 0 .. opWidth)
                    kernel.setArg(o + 2, operands[o]);

                kernel.setArg(opWidth + 2, output.offsets);
                
                operands = operands[opWidth .. $];
                
                if(operands.length != 0)
                    operands = output.offsets ~ operands;
                    
                kernels ~= kernel;
            }
        }
    }
}

