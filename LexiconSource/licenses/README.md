# Lexicon data provenance

The seed lexicon in `lexicon.tsv` and `translations.tsv`, together with the
reviewed daily expressions in `curated_phrases.tsv`, was written for the
LinguaFlow prototype. The curated file is kept separate so its translations
can be reviewed and expanded without modifying imported dictionary exports.

The generated database imports
`External/rime_ice_base.dict.yaml` and `External/rime_ice_8105.dict.yaml` from
`iDvel/rime-ice`. The matching GPL-3.0 license text is stored locally as
`External/rime-ice-GPL-3.0.txt`.

English definitions are imported from CC-CEDICT, published by MDBG under
CC BY-SA 4.0. The unmodified source export retains its attribution header in
`External/cedict_ts.u8`, and the license text is stored in
`External/CC-BY-SA-4.0.txt`.

Potential future sources must be reviewed file by file before import. In
particular, a repository-level license does not necessarily cover aggregated
third-party dictionaries contained by that repository.

Candidate sources supplied for later evaluation:

- Peter Norvig `count_1w.txt`: English unigram counts, not bilingual translations.
- `wuhgit/CustomPinyinDictionary`: aggregated Chinese input-method dictionaries.
- `iDvel/rime-ice`: currently used by the local development build; GPL-3.0.
- CC-CEDICT: currently used for Chinese-to-English candidate definitions;
  CC BY-SA 4.0, published by MDBG.
- Microsoft Windows SampleIME dictionary: sample IME data and implementation reference.
- `KyleBing/rime-wubi86-jidian`: Wubi dictionary, not a pinyin source.
