module cyberparrot.time;

public import core.time;

Duration currentTime()
{
    return MonoTime.currTime - MonoTime.zero();
}


//FIXME: Quick and dirty benchmarking...
private long totalElapsed = 0;
private int numRun = 0;
Duration startTime;

void resetStopwatch()
{
    totalElapsed = 0;
    numRun = 0;
}

void startStopwatch()
{
    startTime = currentTime(); 
}

void clickStopwatch()
{
    totalElapsed = (currentTime - startTime).total!"hnsecs";
}
