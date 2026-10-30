"""Extract one synthetic example from an existing user pack; synthesize original music."""
import math, pathlib, struct, sys, wave
root=pathlib.Path(__file__).resolve().parents[1]
pack=pathlib.Path(sys.argv[1])
for line in (pack/'spanish.tsv').read_text().splitlines():
    word,offset,length=line.split('\t')
    if word=='libro':break
else:raise ValueError('libro missing')
with (pack/'spanish.pack').open('rb')as f:
    f.seek(int(offset));(root/'public/audio/libro.flac').write_bytes(f.read(int(length)))
rate=24000;seconds=48.4
chords=[(130.81,164.81,196),(174.61,220,261.63),(110,130.81,164.81),(98,123.47,146.83)]
with wave.open(str(root/'public/audio/bed.wav'),'wb')as f:
    f.setnchannels(1);f.setsampwidth(2);f.setframerate(rate)
    audio=bytearray()
    for i in range(round(rate*seconds)):
        t=i/rate;c=chords[min(int(t/8),5)%4];phase=t%8
        env=min(1,phase/1.4,(8-phase)/1.5)*min(1,t/2,(seconds-t)/2)
        signal=sum(math.sin(2*math.pi*hz*t)*.009+math.sin(2*math.pi*hz*2*t)*.002 for hz in c)*max(0,env)
        audio+=struct.pack('<h',round(signal*32767))
    f.writeframes(audio)
