# Lexicon data provenance

The seed lexicon in `lexicon.tsv` and `translations.tsv` was written for the
LinguaFlow prototype. No third-party dictionary data is bundled in the current
database.

Potential future sources must be reviewed file by file before import. In
particular, a repository-level license does not necessarily cover aggregated
third-party dictionaries contained by that repository.

Candidate sources supplied for later evaluation:

- Peter Norvig `count_1w.txt`: English unigram counts, not bilingual translations.
- `wuhgit/CustomPinyinDictionary`: aggregated Chinese input-method dictionaries.
- `iDvel/rime-ice`: Rime configuration and dictionaries under GPL-3.0 at the repository root.
- Microsoft Windows SampleIME dictionary: sample IME data and implementation reference.
- `KyleBing/rime-wubi86-jidian`: Wubi dictionary, not a pinyin source.
