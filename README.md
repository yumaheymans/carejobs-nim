# carejobs-nim

Nim client for the [CareJobs.Now](https://carejobs.now) healthcare jobs API. Search open US healthcare jobs, see the hourly pay employers post, and look up employers and states.

- Free, no API key.
- Standard library only (`std/httpclient`, `std/json`). Nim 2.0 or newer.
- Typed results, one `CareJobsError` type.
- The same API is a remote MCP server at <https://carejobs.now/api/mcp>, so any MCP client can use it too.

## Install

```sh
nimble install carejobs
```

Or in your `.nimble` file:

```nim
requires "carejobs >= 1.0.0"
```

The calls go over HTTPS, so compile your program with `-d:ssl`.

## Quick start

```nim
import std/options
import carejobs

let client = newClient()

let res = client.searchJobs(query = "ICU", kind = some(Kind.nurses),
                            state = "TX", limit = 5)
echo res.total, " jobs match"
for job in res.jobs:
  echo job.title, " | ", job.employer, " | ", job.location, " | ", job.url

let pay = client.payByKind(Kind.nurses)
if pay.pay.isSome:
  echo "Median posted pay for nurses: $", pay.pay.get.median, "/hr"
```

```sh
nim c -r -d:ssl example.nim
```

## Procs

| Proc | What it answers | Result |
| --- | --- | --- |
| `newClient(baseUrl, timeoutMs, userAgent)` | Settings for the calls | `Client` |
| `searchJobs(client, query, kind, state, limit)` | Open jobs by words, kind, state and limit | `SearchResult` |
| `payByKind(client, kind)` | Posted hourly pay for one kind of job, and the employers posting the most | `PayResult` |
| `employers(client, query, limit)` | The employers, AI-training programs and job boards the site reads | `EmployerList` |
| `states(client)` | Open jobs in every US state | `seq[StateSummary]` |
| `kinds()` | The 17 kinds of job (no request) | `seq[Kind]` |
| `callTool(client, name, arguments)` | Any tool of the server, as raw JSON | `JsonNode` |

Every filter is optional: an empty string, `none(Kind)` or `0` leaves it off. `Kind` is an enum whose string values are the slugs the API uses (`$Kind.nurses == "nurses"`, `Kind.nursePractitioners` is `"nurse-practitioners"`).

Every `Job` carries `url`, its page on CareJobs.Now, where a person applies. The server has no separate job lookup by id: a job is described by the search answer.

Where the API sends `null`, a string field is empty and a number is 0. `SearchResult.pay` and `PayResult.pay` are `Option`s, `none` when too few jobs post an hourly rate to measure.

### Errors and timeouts

Every failure (network, HTTP status, JSON-RPC error, a tool the server refuses to run) raises a `CareJobsError`, which has `status` (the HTTP status or 0) and `tool`.

```nim
try:
  discard client.searchJobs(state = "TX")
except CareJobsError as e:
  echo e.msg, " (HTTP ", e.status, ")"
```

The default timeout is 60 seconds. The server answers a query it has not seen before in up to about 25 seconds (its database may be waking up), then repeats of it in a fraction of one. Change it with `newClient(timeoutMs = 120_000)`.

## Tests

```sh
nimble test    # offline, on answers recorded from the live API
nimble live    # the same procs against the real API
```

## Data

Data from [CareJobs.Now](https://carejobs.now), CC BY 4.0. Docs and downloads: <https://carejobs.now/data>.

## License

Code: MIT, copyright O-mega Enterprise, Inc. See [LICENSE](LICENSE).
