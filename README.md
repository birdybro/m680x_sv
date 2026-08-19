# m680x_sv

`m680x_sv` is an independent, clean-room SystemVerilog implementation project
for documented Motorola M6800/M6801/M6803/M6805 and related Hitachi processor
families. The repository is in active architecture and verification development;
no device is yet claimed as production-complete.

Implementation facts come only from primary manufacturer hardware documents.
Existing HDL cores and emulator implementations are prohibited as source or as
behavioral/timing oracles. See [the clean-room policy](docs/CLEAN_ROOM.md) and
[the checksummed reference manifest](docs/references.yml).

Downloaded manuals are never committed. Run `make refs` to populate the ignored
`.reference/` cache and verify every file against its recorded SHA-256 digest.
`make quick` runs the current offline validation gate; `make help` lists the
available developer commands.

All original project code and documentation are licensed under the MIT License.
