Cyberparrot is an experimental software synthesizer that allows patch designers to plug virtual signal generators together called "Operators" in order to produce a wide variety of sounds. These configurations of Operators are called Patches, and a reference patch is supplied in this project under bin/defaultconfig/000.cpm

Cyberparrot generates all sound waves on the fly rather than using pre-computed samples. In order to produce a high number of voices simultaneously without stuttering, these calculations are accelerated by the graphics card using OpenCL.

In its current state, it can perform calculations on 32 voices simultaneously with a 5ms delay on Intel Ivybridge integrated graphics at 48khz. On a discrete graphics card, it can perform much better and reach extremely high sampling rates, especially if the number of maximum number of voices is kept to a minimum.

This project has currently only been built and running under the Linux operating system, although there should be no barriers to getting it working
under Windows and Macintosh, until Apple decides to remove OpenCL support.
