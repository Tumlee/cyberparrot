module cyberparrot.operators.integral;

import cyberparrot.operator;
import cyberparrot.clutil;

class OperatorIntegral : Operator
{
    mixin RegisterOperatorType!"integral";

    CLMemory!float stored;

    override int neededTempBlocks()
    {
        return 1;
    }
    
    override void setup()
    {
        auto kernelA = createKernel("integralA");
        auto kernelB = createKernel("integralB");
        auto partialOff = temp[0].offsets;
        stored = new CLMemory!float(tree.voiceCount * width);
        stored.fill(0);
        
        kernelA.setArgs(tree.heap.memory, tree.vOff, tree.deviceVInfo, tree.voiceCount, parmOffsets("in"), partialOff, stored, tree.timeStep);
        kernelB.setArgs(tree.heap.memory, tree.vOff, tree.deviceVInfo, tree.voiceCount, partialOff, output.offsets, stored);

        kernels = [kernelA, kernelB];
    }

    override void initVoice(VoiceID vid)
    {
        //FIXME: Should we rearrange the memory here so that stored values
        //that belong to a single voice are contiguous?
        foreach(i; 0 .. width)
            stored.fill(0, (i * tree.voiceCount) + vid, 1);
    }
}
