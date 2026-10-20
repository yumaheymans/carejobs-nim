# Package

version       = "1.0.0"
author        = "O-mega Enterprise, Inc."
description   = "Client for the free CareJobs.Now healthcare jobs API: search US healthcare jobs, posted pay, employers and states"
license       = "MIT"
srcDir        = "src"

# Dependencies

requires "nim >= 2.0.0"

task test, "Run the offline tests":
  exec "nim c -r --hints:off tests/test_carejobs.nim"

task live, "Ask the live API (needs a network)":
  exec "nim c -r -d:ssl --hints:off tests/live.nim"
