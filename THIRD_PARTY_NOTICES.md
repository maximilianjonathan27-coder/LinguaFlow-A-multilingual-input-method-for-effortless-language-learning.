# Third-party dictionary notices

## rime-ice

LinguaFlow uses dictionary data from
[iDvel/rime-ice](https://github.com/iDvel/rime-ice), licensed under the GNU
General Public License v3.0. The original license text is included at
`LexiconSource/External/rime-ice-GPL-3.0.txt`.

## CC-CEDICT

LinguaFlow uses Chinese-English definitions from CC-CEDICT, a community
maintained dictionary published by MDBG. CC-CEDICT is licensed under the
Creative Commons Attribution-ShareAlike 4.0 International License. The source
export retains its original attribution header, and the license text is
included at `LexiconSource/External/CC-BY-SA-4.0.txt`.

- Project: https://cc-cedict.org/
- Download: https://cc-cedict.org/editor/editor.php?handler=Download
- License: https://creativecommons.org/licenses/by-sa/4.0/

The generated `linguaflow.sqlite` database combines records from these sources
with LinguaFlow's manually maintained seed records. Each source remains subject
to its respective license and attribution requirements.

## Tatoeba Chinese-English Vocabulary

LinguaFlow includes a December 2020 Chinese-English sentence snapshot derived
from contributions to [Tatoeba](https://tatoeba.org/), distributed in MDX form
by `lxs602/Chinese-Mandarin-Dictionaries` under CC BY 2.0 FR. The original
license notice is included at
`LexiconSource/External/Tatoeba-CC-BY-2.0-FR.txt`.

The resulting `tatoeba_examples.sqlite` is used only for offline examples and
term indexes. LinguaFlow's reviewed phrase translations remain separately
identified as `linguaflow-reviewed`.

## mdict-utils build tool

The offline conversion script uses the vendored `mdict-utils` 1.3.14 wheel.
Package metadata is MIT-licensed, while its `readmdict.py` implementation
declares GPL-3.0. The applicable license texts are retained in `script/vendor`.
This build tool is not loaded or shipped by the running input method.
