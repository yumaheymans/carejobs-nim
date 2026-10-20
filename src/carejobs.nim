## Client for the `CareJobs.Now <https://carejobs.now>`_ healthcare jobs API.
##
## Search open US healthcare jobs, see the hourly pay employers post, and look
## up employers and states. The API is free and needs no key. It is a remote
## MCP server (https://carejobs.now/api/mcp); this module posts the JSON-RPC
## calls for you and returns typed results. Standard library only.
##
## The calls go over HTTPS, so compile with ``-d:ssl``.
##
## .. code-block:: nim
##   import std/options
##   import carejobs
##
##   let client = newClient()
##   let res = client.searchJobs(query = "ICU", kind = some(Kind.nurses),
##                               state = "TX", limit = 5)
##   echo res.total, " jobs match"
##   for job in res.jobs:
##     echo job.title, " | ", job.employer, " | ", job.location, " | ", job.url
##
## Data from CareJobs.Now (https://carejobs.now), CC BY 4.0.

import std/[httpclient, json, options, strutils]

const
  Version* = "1.0.0"
    ## Version of this package, sent in the default User-Agent.
  DefaultBaseUrl* = "https://carejobs.now"
    ## The CareJobs.Now site. The MCP endpoint is this plus ``/api/mcp``.
  DefaultTimeoutMs* = 60_000
    ## How long a call may wait. The server answers a query it has not seen
    ## before in up to about 25 seconds, then repeats of it in a fraction of one.

type
  Kind* {.pure.} = enum
    ## A kind of healthcare job, the ``kind`` filter of the API. Its string
    ## value is the slug the API uses.
    nurses = "nurses"
    nursePractitioners = "nurse-practitioners"
    physicians = "physicians"
    nursingAssistants = "nursing-assistants"
    caregivers = "caregivers"
    therapyRehab = "therapy-rehab"
    mentalHealth = "mental-health"
    pharmacy = "pharmacy"
    imaging = "imaging"
    lab = "lab"
    surgicalTechs = "surgical-techs"
    emtsParamedics = "emts-paramedics"
    medicalAssistants = "medical-assistants"
    dental = "dental"
    admin = "admin"
    alliedHealth = "allied-health"
    aiTraining = "ai-training"

  CareJobsError* = object of CatchableError
    ## Raised for a network failure, a non-2xx answer, a JSON-RPC error, a tool
    ## the server refuses to run or an answer that is not what MCP promises.
    status*: int ## The HTTP status, or 0 when there was none.
    tool*: string ## The tool that was called, or empty.

  Client* = object
    ## Settings for calls to the API. Make one with `newClient`.
    baseUrl*: string
    timeoutMs*: int
    userAgent*: string

  Job* = object
    ## One open job. `url` is its page on CareJobs.Now, where a person applies.
    title*, employer*: string
    via*: string ## The job board it was read through, empty for an employer's own site.
    kind*: string ## The label of the kind of job, for example "Nurses".
    pay*: string ## The posted pay as text, empty when the posting states none.
    schedule*: seq[string]
    facility*, location*: string
    listed*: string ## ISO date (YYYY-MM-DD) the job was first listed.
    url*: string
    employerPage*: string

  SearchPay* = object
    ## Posted hourly pay in US dollars across the jobs a search matches.
    typicalLow*, typicalHigh*, median*: float
    rateSamples*, priced*, open*: int

  SearchResult* = object
    total*: int ## Every open job that matches, not only the ones in `jobs`.
    pay*: Option[SearchPay] ## None when no matching job posts a rate.
    jobs*: seq[Job]
    more*: string ## The same search on the CareJobs.Now site.

  PayStats* = object
    ## Posted hourly pay in US dollars, before shift differentials and bonuses.
    median*, typicalLow*, typicalHigh*: float
    rateSamples*, employers*, openJobs*, noRate*: int
    marketRate*: bool ## True only where at least three employers post a rate.

  EmployerPay* = object
    slug*, name*: string
    stats*: PayStats

  PayResult* = object
    asOf*: string ## ISO date the figures were measured.
    kind*: string
    openJobs*: int
    pay*: Option[PayStats] ## None when too few jobs post an hourly rate.
    bestPaying*: seq[EmployerPay]

  Employer* = object
    ## An employer, AI-training program or job board.
    slug*, name*: string
    kind*: string ## "employer", "ai-program" or "job-board".
    model*, care*, hq*: string
    states*: seq[string]
    openJobs*: int
    postedMedianHourly*: Option[float]
    url*: string

  EmployerList* = object
    total*: int
    entries*: seq[Employer]

  KindCount* = object
    kind*, label*: string
    openJobs*: int
    url*: string

  StateSummary* = object
    code*, name*: string
    openJobs*, employers*: int
    topKinds*: seq[KindCount]
    url*: string

proc newClient*(baseUrl = DefaultBaseUrl, timeoutMs = DefaultTimeoutMs,
                userAgent = "carejobs-nim/" & Version): Client =
  ## Settings for the live API. A trailing slash on `baseUrl` is ignored.
  Client(baseUrl: baseUrl.strip(leading = false, chars = {'/'}),
         timeoutMs: timeoutMs, userAgent: userAgent)

proc kinds*(): seq[Kind] =
  ## All 17 kinds of job, in the order the API documents them.
  for k in Kind: result.add k

# ---------------------------------------------------------------------------
# Reading answers
# ---------------------------------------------------------------------------

proc fail(msg: string, tool = "", status = 0) {.noreturn.} =
  var e = newException(CareJobsError, msg)
  e.status = status
  e.tool = tool
  raise e

proc str(n: JsonNode, key: string): string =
  if n.kind == JObject and n.hasKey(key) and n[key].kind == JString: n[key].getStr else: ""

proc num(n: JsonNode, key: string): float =
  if n.kind == JObject and n.hasKey(key) and n[key].kind in {JInt, JFloat}: n[key].getFloat else: 0.0

proc count(n: JsonNode, key: string): int =
  if n.kind == JObject and n.hasKey(key) and n[key].kind in {JInt, JFloat}: n[key].getInt else: 0

proc flag(n: JsonNode, key: string): bool =
  n.kind == JObject and n.hasKey(key) and n[key].kind == JBool and n[key].getBool

proc items(n: JsonNode, key: string): seq[JsonNode] =
  if n.kind == JObject and n.hasKey(key) and n[key].kind == JArray: n[key].elems else: @[]

proc strings(n: JsonNode, key: string): seq[string] =
  for e in n.items(key):
    if e.kind == JString: result.add e.getStr

proc present(n: JsonNode, key: string): bool =
  n.kind == JObject and n.hasKey(key) and n[key].kind == JObject

proc parseJob*(n: JsonNode): Job =
  ## Read one job of a ``search_healthcare_jobs`` answer.
  Job(title: n.str("title"), employer: n.str("employer"), via: n.str("via"),
      kind: n.str("kind"), pay: n.str("pay"), schedule: n.strings("schedule"),
      facility: n.str("facility"), location: n.str("location"),
      listed: n.str("listed"), url: n.str("url"),
      employerPage: n.str("employer_page"))

proc parseSearchResult*(n: JsonNode): SearchResult =
  ## Read the ``structuredContent`` of a ``search_healthcare_jobs`` answer.
  result.total = n.count("total")
  result.more = n.str("more")
  if n.present("pay"):
    let p = n["pay"]
    result.pay = some(SearchPay(typicalLow: p.num("typical_low"),
        typicalHigh: p.num("typical_high"), median: p.num("median"),
        rateSamples: p.count("rate_samples"), priced: p.count("priced"),
        open: p.count("open")))
  for j in n.items("jobs"): result.jobs.add parseJob(j)

proc parsePayStats*(n: JsonNode): PayStats =
  ## Read a pay figure (``median``, ``typical_low`` and so on).
  PayStats(median: n.num("median"), typicalLow: n.num("typical_low"),
           typicalHigh: n.num("typical_high"), rateSamples: n.count("rate_samples"),
           employers: n.count("employers"), openJobs: n.count("open_jobs"),
           noRate: n.count("no_rate"), marketRate: n.flag("market_rate"))

proc parsePayResult*(n: JsonNode): PayResult =
  ## Read the ``structuredContent`` of a ``get_healthcare_pay`` answer for one kind.
  result.asOf = n.str("as_of")
  result.kind = n.str("kind")
  result.openJobs = n.count("open_jobs")
  if n.present("pay"): result.pay = some(parsePayStats(n["pay"]))
  for e in n.items("best_paying"):
    result.bestPaying.add EmployerPay(slug: e.str("slug"), name: e.str("name"),
                                      stats: parsePayStats(e))

proc parseEmployerList*(n: JsonNode): EmployerList =
  ## Read the ``structuredContent`` of a ``list_healthcare_employers`` answer.
  result.total = n.count("total")
  for e in n.items("entries"):
    var emp = Employer(slug: e.str("slug"), name: e.str("name"),
                       kind: e.str("type"), model: e.str("model"),
                       care: e.str("care"), hq: e.str("hq"),
                       states: e.strings("states"), openJobs: e.count("open_jobs"),
                       url: e.str("url"))
    if e.hasKey("posted_median_hourly") and e["posted_median_hourly"].kind in {JInt, JFloat}:
      emp.postedMedianHourly = some(e["posted_median_hourly"].getFloat)
    result.entries.add emp

proc parseStates*(n: JsonNode): seq[StateSummary] =
  ## Read the ``structuredContent`` of a ``get_healthcare_jobs_by_state`` answer
  ## that covers every state.
  for s in n.items("states"):
    var st = StateSummary(code: s.str("code"), name: s.str("name"),
                          openJobs: s.count("open_jobs"),
                          employers: s.count("employers"), url: s.str("url"))
    for k in s.items("top_kinds"):
      st.topKinds.add KindCount(kind: k.str("kind"), label: k.str("label"),
                                openJobs: k.count("open_jobs"), url: k.str("url"))
    result.add st

# ---------------------------------------------------------------------------
# Calling the API
# ---------------------------------------------------------------------------

proc requestBody*(tool: string, arguments: JsonNode, id = 1): string =
  ## The JSON-RPC ``tools/call`` request for `tool`.
  $(%*{"jsonrpc": "2.0", "id": id, "method": "tools/call",
       "params": {"name": tool, "arguments": arguments}})

proc messageOf(body, contentType: string): JsonNode =
  ## The JSON-RPC message of a plain JSON or a text/event-stream body.
  try:
    if "text/event-stream" notin contentType:
      return parseJson(body)
    var data: seq[string]
    for line in body.replace("\r\n", "\n").splitLines:
      if line.startsWith("data:"):
        data.add line[5 .. ^1].strip(trailing = false, chars = {' '})
      elif line.len == 0 and data.len > 0:
        let msg = parseJson(data.join("\n"))
        if msg.kind == JObject and (msg.hasKey("result") or msg.hasKey("error")):
          return msg
        data.setLen(0)
    if data.len > 0:
      return parseJson(data.join("\n"))
  except JsonParsingError, ValueError:
    discard
  fail("the server did not answer with a JSON-RPC message")

proc callTool*(c: Client, tool: string, arguments: JsonNode): JsonNode =
  ## Run any tool and return its ``structuredContent``. The typed procs are
  ## built on it; use it for a tool or a field this package does not know yet.
  var http = newHttpClient(userAgent = c.userAgent, timeout = c.timeoutMs)
  defer: http.close()
  http.headers = newHttpHeaders({"Content-Type": "application/json",
                                 "Accept": "application/json, text/event-stream"})
  let url = c.baseUrl & "/api/mcp"
  var resp: Response
  try:
    resp = http.request(url, httpMethod = HttpPost,
                        body = requestBody(tool, arguments))
  except CatchableError as e:
    fail("could not reach " & url & ": " & e.msg, tool)
  let code = resp.code.int
  let body = resp.body
  let contentType = resp.headers.getOrDefault("content-type")
  if code < 200 or code > 299:
    var detail = body.strip
    try:
      let msg = messageOf(body, contentType)
      if msg.kind == JObject and msg.hasKey("error"):
        detail = msg["error"].str("message")
    except CareJobsError:
      discard
    if detail.len > 200: detail = detail[0 ..< 200]
    if detail.len == 0: detail = resp.status
    fail(detail, tool, code)
  let msg = messageOf(body, contentType)
  if msg.kind == JObject and msg.hasKey("error"):
    let m = msg["error"].str("message")
    fail(if m.len > 0: m else: "JSON-RPC error", tool, code)
  let res = if msg.kind == JObject and msg.hasKey("result"): msg["result"] else: newJNull()
  if res.kind != JObject:
    fail("the answer held no result", tool, code)
  if res.flag("isError"):
    var text = ""
    for part in res.items("content"):
      if part.str("type") == "text": text.add part.str("text")
    fail(if text.len > 0: text else: tool & " failed", tool, code)
  if not res.present("structuredContent"):
    fail("the tool answered without structured content", tool, code)
  res["structuredContent"]

proc searchJobs*(c: Client, query = "", kind = none(Kind), state = "",
                 limit = 0): SearchResult =
  ## Search the open healthcare jobs. Every filter is optional (an empty string,
  ## `none` or 0 leaves it off). `query` is words every job must carry in its
  ## title, place, department or schedule ("ICU", "night"), `state` is a US
  ## state code or name ("TX", "Texas") and `limit` is 1 to 25 (server default 10).
  var args = newJObject()
  if query.len > 0: args["query"] = %query
  if kind.isSome: args["kind"] = %($kind.get)
  if state.len > 0: args["state"] = %state
  if limit > 0: args["limit"] = %limit
  parseSearchResult(c.callTool("search_healthcare_jobs", args))

proc payByKind*(c: Client, kind: Kind): PayResult =
  ## What open jobs of one kind post as hourly pay, and the employers posting
  ## the most for it.
  parsePayResult(c.callTool("get_healthcare_pay", %*{"kind": $kind}))

proc employers*(c: Client, query = "", limit = 0): EmployerList =
  ## The employers, AI-training programs and job boards CareJobs.Now reads, most
  ## open jobs first. `query` is part of a name ("Kaiser"); `limit` is 1 to 100
  ## (server default 20).
  var args = newJObject()
  if query.len > 0: args["query"] = %query
  if limit > 0: args["limit"] = %limit
  parseEmployerList(c.callTool("list_healthcare_employers", args))

proc states*(c: Client): seq[StateSummary] =
  ## Open jobs for every US state, most first.
  parseStates(c.callTool("get_healthcare_jobs_by_state", newJObject()))
