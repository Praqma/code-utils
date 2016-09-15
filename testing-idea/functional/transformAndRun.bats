#!/usr/bin/env bats

@test "invoking transformAndRun without configuration file prints and error" {
  run groovy ../transformAndRun/transformAndRun.groovy
	  [ "$status" -eq 1 ]
		[[ "$output" =~ "Missing YAML configuration file argument" ]]
}
