# About
Cyberparrot is an experimental software synthesizer that allows patch designers to plug virtual signal generators together called "Operators" in order to produce a wide variety of sounds. These configurations of Operators are called Patches, and a reference patch is supplied in this project under bin/defaultconfig/000.cpm

Cyberparrot generates all sound waves on the fly rather than using pre-computed samples. In order to produce a high number of voices simultaneously without stuttering, these calculations are accelerated by the graphics card using OpenCL.

In its current state, it can perform calculations on 32 voices simultaneously with a 5ms delay on Intel Ivybridge integrated graphics at 48khz. On a discrete graphics card, it can perform much better and reach extremely high sampling rates, especially if the number of maximum number of voices is kept to a minimum.

This project has currently only been built and running under the Linux operating system, although there should be no barriers to getting it working under Windows and Macintosh, until Apple decides to remove OpenCL support.

# Building
To build this project, simply navigate into the main Cyberparrot directory and execute 'dub'. Cyberparrot will be built and placed into the 'bin' directory where it can be run.

# Usage
Cyberparrot runs in the background with no direct user interface. An external MIDI keyboard or sequencer must be connected in order to get sound out of this program. Under Linux, it is a good idea to run JACK first in order to have minimal delay.
The following command line paramters are supported:


--samplerate <N>
  Sets the audio sample rate, default is 44100hz.
  
--voicecount <N>
  Sets the maximum number of voices that can be played simultaneously. Default is 32.
  
--period <N>
  Default is 512. Generate audio in N sample chunks. Because of the nature of OpenCL kernel calls, raising this value can greatly increase performance at the cost of increasing delay.
  
  The amount of GPU memory that Cyberparrot requires is usually in the order of a few Megabytes, and can vary depending on the patch configuration.
  In general, the maximum amount of memory that can be taken up by a given patch is (4 * period * voicecount * (number_of_operators + number_of_paramters))
  The delay, in milliseconds, is given by the formula (period * 1000 / samplerate)
