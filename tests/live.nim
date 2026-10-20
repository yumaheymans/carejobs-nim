## Asks the live API. Run with: nimble live
import std/options
import ../src/carejobs

let client = newClient()
let res = client.searchJobs(query = "ICU", kind = some(Kind.nurses), state = "TX", limit = 3)
echo res.total, " jobs match"
for job in res.jobs:
  echo job.title, " | ", job.employer, " | ", job.location, " | ", job.url
let pay = client.payByKind(Kind.nurses)
echo "nurses median $", pay.pay.get.median, "/hr"
echo client.employers(query = "Kaiser", limit = 3).entries.len, " employers"
echo client.states().len, " states"
