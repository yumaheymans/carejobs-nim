import std/[json, options, strutils, unittest]
import ../src/carejobs

proc fixture(name: string): JsonNode =
  parseJson(readFile("tests/fixtures/" & name & ".json"))

suite "answers recorded from the live API":
  test "search":
    let r = parseSearchResult(fixture("search"))
    check r.total >= 2
    check r.jobs.len == 2
    check r.jobs[0].kind == "Nurses"
    check r.jobs[0].url.len > 0
    check r.pay.isSome
    check r.pay.get.median == 45.0
    check r.more.len > 0

  test "pay of one kind":
    let r = parsePayResult(fixture("pay"))
    check r.kind == "nurses"
    check r.pay.isSome
    check r.pay.get.median == 45.0
    check r.pay.get.marketRate
    check r.bestPaying.len == 2
    check r.bestPaying[0].slug.len > 0

  test "employers":
    let r = parseEmployerList(fixture("employers"))
    check r.entries.len == 2
    check r.entries[0].slug == "cross-country-healthcare"
    check r.entries[0].states.len > 10
    check r.entries[0].postedMedianHourly.isNone

  test "states":
    let s = parseStates(fixture("states"))
    check s.len == 2
    check s[0].code == "TX"
    check s[0].topKinds.len == 3

suite "kinds and requests":
  test "17 kinds with the API slugs":
    check kinds().len == 17
    check $Kind.nursePractitioners == "nurse-practitioners"
    check parseEnum[Kind]("emts-paramedics") == Kind.emtsParamedics

  test "request body":
    let b = parseJson(requestBody("search_healthcare_jobs", %*{"state": "TX"}))
    check b["method"].getStr == "tools/call"
    check b["params"]["name"].getStr == "search_healthcare_jobs"
    check b["params"]["arguments"]["state"].getStr == "TX"

  test "trailing slash of the base url is ignored":
    check newClient(baseUrl = "https://example.org/").baseUrl == "https://example.org"
