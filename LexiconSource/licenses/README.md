# Lexicon data provenance

The seed lexicon in `lexicon.tsv` and `translations.tsv` was written for the
LinguaFlow prototype.

The generated database imports
`External/rime_ice_base.dict.yaml` and `External/rime_ice_8105.dict.yaml` from
`iDvel/rime-ice`. The matching GPL-3.0 license text is stored locally as
`External/rime-ice-GPL-3.0.txt`.

English definitions are imported from the complete official CC-CEDICT V2
export, published by MDBG under CC BY-SA 4.0. The unmodified source export
retains its attribution and V2 metadata header in `External/cedict_ts.u8`; its
SHA-256 is `7f66eb15733ee32297f4fd3e87433a8c5f25dabd111b579690b55b091922ac2f`.
The license text is stored in `External/CC-BY-SA-4.0.txt`.

Potential future sources must be reviewed file by file before import. In
particular, a repository-level license does not necessarily cover aggregated
third-party dictionaries contained by that repository.

`External/tatoeba_zh_en.mdx` is the December 2020 Tatoeba Chinese-English
Vocabulary snapshot distributed by `lxs602/Chinese-Mandarin-Dictionaries`.
Its accompanying CC BY 2.0 FR license is stored at
`External/Tatoeba-CC-BY-2.0-FR.txt`. The generated
`tatoeba_examples.sqlite` keeps Tatoeba sentence pairs separate from manually
reviewed LinguaFlow phrase translations.

Candidate sources supplied for later evaluation:

- Peter Norvig `count_1w.txt`: English unigram counts, not bilingual translations.
- `wuhgit/CustomPinyinDictionary`: aggregated Chinese input-method dictionaries.
- `iDvel/rime-ice`: currently used by the local development build; GPL-3.0.
- CC-CEDICT: currently used for Chinese-to-English candidate definitions;
  CC BY-SA 4.0, published by MDBG.
- Microsoft Windows SampleIME dictionary: sample IME data and implementation reference.
- `KyleBing/rime-wubi86-jidian`: Wubi dictionary, not a pinyin source.
