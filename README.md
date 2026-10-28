<p align="center"><img src="docs/logo.svg" width="96" alt="" /></p>

# callmend

callmend is an offline command-line tool, written in Ruby with only the standard library, for people who build agents on language models. It repairs the broken JSON that models send as tool arguments, shows the best value after each chunk of a streamed reply, checks a value against a tool's JSON Schema, and replays a scripted conversation in which a rejected reply goes back to the model with feedback.

[![CI](https://github.com/Gulliby-development/callmend/actions/workflows/ci.yml/badge.svg)](https://github.com/Gulliby-development/callmend/actions/workflows/ci.yml) [![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

## Why

A model that calls a tool sends its arguments as JSON text, and that text is often wrong: wrapped in a code fence, with comments, trailing commas, single quotes, unquoted keys, Python literals, raw newlines, or cut off by a token limit. callmend lets you see exactly what is wrong and what a repair would change, and lets you test a retry loop deterministically.

It needs no API key, account or network access. Every model call goes through a provider object, and the only provider in this version is `Callmend::Guard::Scripted`, a deterministic fake that answers from a script file. A real provider, if one is added later, will be gated behind an explicit flag and an environment variable named in this README; this version has neither.

## Install

You need Ruby 3.4. The program itself uses only the standard library; the gems installed by Bundler are for development (tests and lint).

```sh
git clone https://github.com/Gulliby-development/callmend.git
cd callmend
bundle install
ruby exe/callmend --help
```

The launcher is the same on Windows, macOS and Linux: `ruby exe/callmend COMMAND ...` from the project root. In the examples below `callmend` stands for `ruby exe/callmend`.

## Usage

```text
usage: callmend repair [--pretty] [--indent N] [--report] [--strict] FILE
       callmend stream FILE
       callmend check SCHEMA FILE
       callmend guard --schema SCHEMA [--max-tries N] SCRIPT
```

A file name of `-` is standard input. Options start with `-`; `--` ends them. A value option is written `--name VALUE` or `--name=VALUE`, and a repeated one keeps the last value. With no argument callmend prints the usage to standard error and exits 2; `--help` or `-h` as the first argument prints it to standard output and exits 0.

Exit codes: 0 success, 1 a content failure (an unrepairable text, a rejected value, a guard that gave up), 2 an error in the command line or an input (an unknown option, an unreadable file, invalid UTF-8).

### Commands

| Command | What it does |
| --- | --- |
| `repair [--pretty] [--indent N] [--report] [--strict] FILE` | Finds the first JSON object or array in the text, repairs it and prints strict JSON (compact, or indented with `--pretty`, or by N spaces with `--indent N`, 1 to 8, which implies `--pretty`). `--report` lists each repair on standard error with its line, column and code (R01 to R13). `--strict` prints no JSON and exits 1 when any repair was needed. |
| `stream FILE` | Every non-blank line of FILE is one chunk written as a JSON string literal. After chunk K it prints `chunk K: JSON`, `chunk K: (no value)` while there is no `{` or `[` yet, or `chunk K: error: LINE:COL: MESSAGE`. An invalid chunk line exits 2; snapshots already printed stay on standard output. |
| `check SCHEMA FILE` | Validates FILE against SCHEMA, a subset of JSON Schema: `type`, `enum`, `const`, `minLength`, `maxLength`, `minimum`, `maximum`, `required`, `properties`, `additionalProperties`, `minItems`, `maxItems`, `items`. Prints `ok`, or one `PATH: MESSAGE` line per problem and a count. Both files go through the repairing parser. |
| `guard --schema SCHEMA [--max-tries N] SCRIPT` | Replays a retry loop against the scripted provider. SCRIPT holds one reply per section, separated by lines that are exactly `---`. Each rejected reply produces feedback that is added to the conversation; the loop stops at the first valid reply or after N attempts (1 to 99, default 3). |

## Examples

Create the example files (POSIX shell; on Windows use Git Bash):

```sh
printf '{"city": "Paris", "days": 3,}\n' > a.json
printf "Sure: {'city': 'Oslo', days: 2.0, ok: True} bye" > b.json
printf '{"city": "Pa' > cut.json
printf '"Sure! "\n"{\\"a\\": tr"\n"ue, \\"b\\": -"\n"1"\n' > chunks2.txt
printf '%s' '{"type": "object", "required": ["city", "days"], "properties": {"city": {"type": "string"}, "days": {"type": "integer", "minimum": 1}}}' > s.json
printf '{"city": "Paris"}\n---\n{"city": "Paris", "days": 3}' > p.txt
printf '{"city": 1}\n---\n{"city": 2}\n---\nnope\n' > p2.txt
printf '"ok"\nnot a string' > bad_chunks.txt
printf '{"city": }' > bad.json
```

Then run the commands. `$` starts a command, `stderr:` lines go to standard error, and `exit: N` is a non-zero exit code:

```text
$ callmend repair --report a.json
{"city":"Paris","days":3}
stderr: a.json:1:28: R07 trailing comma removed
$ callmend repair --pretty b.json
{
  "city": "Oslo",
  "days": 2.0,
  "ok": true
}
$ callmend repair --indent 4 a.json
{
    "city": "Paris",
    "days": 3
}
$ callmend repair --strict b.json
stderr: b.json:1:1: R02 text before the value skipped
stderr: b.json:1:8: R05 single-quoted string converted
stderr: b.json:1:16: R05 single-quoted string converted
stderr: b.json:1:24: R06 unquoted key quoted
stderr: b.json:1:35: R06 unquoted key quoted
stderr: b.json:1:39: R12 literal converted
stderr: b.json:1:45: R03 text after the value ignored
exit: 1
$ callmend repair cut.json
{"city":"Pa"}
$ callmend stream chunks2.txt
chunk 1: (no value)
chunk 2: {}
chunk 3: {"a":true}
chunk 4: {"a":true,"b":-1}
$ printf '{"city":1,"days":0}' | callmend check s.json -
$.city: expected string, got integer
$.days: number is below the minimum 1
2 problems
exit: 1
$ callmend guard --schema s.json p.txt
attempt 1: 1 problem
  $: missing required property "days"
  > The arguments were rejected:
  > - $: missing required property "days"
  > Reply with only the corrected JSON object.
attempt 2: ok
{"city":"Paris","days":3}
$ callmend guard --schema s.json p2.txt
attempt 1: 2 problems
  $: missing required property "days"
  $.city: expected string, got integer
  > The arguments were rejected:
  > - $: missing required property "days"
  > - $.city: expected string, got integer
  > Reply with only the corrected JSON object.
attempt 2: 2 problems
  $: missing required property "days"
  $.city: expected string, got integer
  > The arguments were rejected:
  > - $: missing required property "days"
  > - $.city: expected string, got integer
  > Reply with only the corrected JSON object.
attempt 3: 1 problem
  $: invalid JSON: 1:1: no JSON object or array found
gave up after 3 attempts
exit: 1
$ callmend guard --schema s.json --max-tries 2 p2.txt
attempt 1: 2 problems
  $: missing required property "days"
  $.city: expected string, got integer
  > The arguments were rejected:
  > - $: missing required property "days"
  > - $.city: expected string, got integer
  > Reply with only the corrected JSON object.
attempt 2: 2 problems
  $: missing required property "days"
  $.city: expected string, got integer
gave up after 2 attempts
exit: 1
$ callmend repair - < /dev/null
stderr: callmend: <stdin>:1:1: no JSON object or array found
exit: 1
$ callmend stream bad_chunks.txt
chunk 1: (no value)
stderr: callmend: bad_chunks.txt:2: invalid chunk (expected a JSON string)
exit: 2
$ callmend check s.json bad.json
error: 1:10: unexpected character "}"
exit: 1
$ callmend guard p.txt
stderr: callmend: guard needs --schema
exit: 2
```

## Development

```sh
bundle install
bundle exec rubocop
bundle exec rspec
```

The specs call the command layer with in-memory files and run the launcher once in a real process (invalid UTF-8 on standard input). CI runs both commands on Ubuntu, Windows and macOS.

## License

MIT, see [LICENSE](LICENSE).

---

Built with BAKED
