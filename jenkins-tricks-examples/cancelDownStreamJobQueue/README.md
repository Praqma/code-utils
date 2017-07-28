# Cancel a downstream job queue (before they are scheduled)

Scenario: A setup where there are long running tests (for example on hardware) and resources are limited. The result is that a long queue 
is building up on the test job(s). The project is usually (only) concerned about the latest/newest in the queue rather than the next scheduled.

## Prequisites

## HowTo