# IMPORTANT

When creating a new genome make sure to make the picard .dict file
with CreateSequenceDictionary otherwise the Stats will fail with
strange error:

```
Exception in thread "main" java.lang.NullPointerException
	at htsjdk.samtools.reference.ReferenceSequenceFileWalker.get(ReferenceSequenceFileWalker.java:87)
	at picard.analysis.SinglePassSamProgram.makeItSo(SinglePassSamProgram.java:110)
```

