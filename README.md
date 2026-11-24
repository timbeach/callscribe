# callscribe

Record both sides of any call audible on a PipeWire Linux machine (a Slack
huddle, a Teams call in the browser, Zoom, anything), transcribe it locally
with whisper.cpp, and get one timestamped Markdown transcript with You/Them
speaker labels. No bot joins the meeting, no audio leaves the machine.

**Headset required.** The speaker labels work because your microphone and
your system audio are recorded as two separate streams. On open speakers the
microphone hears the far end too and the labels silently degrade. Use a
headset.

**Consent.** Recording the people you talk to is a legal and workplace-policy
question before it is a technical one. callscribe records only when you start
it, and you are responsible for complying with the recording laws of your
jurisdiction and the policies of your workplace.
