from ..common import *
from .b_flows import *

class Invariants(Flows):
    # The idea of these: Is that if a number of slashes (captured / requested / executed) existed in
    # a 3-day window, then they also exist in the 3-day window starting at their smallest one. Hence
    # if we find all 3-day windows with a slash at the beginning and we can't find a counterexample,
    # it'll prove our hypothesis by contradiction.
    @invariant()
    def inv_capture_timestamps(s):
        for i, execution in enumerate(s.executed_slashes):
            execs_in_next_3_days = [
                exec for exec in s.executed_slashes if (
                    exec.time_cap >= execution.time_cap and exec.time_cap <= 3 * 24 * 60 * 60 + execution.time_cap
                )
            ]
            assert sum(exec.amount for exec in execs_in_next_3_days) <= int(Decimal("100_000e18"))

    @invariant()
    def inv_requested_timestamps(s):
        for i, execution in enumerate(s.executed_slashes):
            execs_in_next_3_days = [
                exec for exec in s.executed_slashes if (
                    exec.time_req >= execution.time_req and exec.time_req <= 3 * 24 * 60 * 60 + execution.time_req
                )
            ]
            assert sum(exec.amount for exec in execs_in_next_3_days) <= int(Decimal("100_000e18"))

    @invariant()
    def inv_executed_timestamps(s):
        for i, execution in enumerate(s.executed_slashes):
            execs_in_next_3_days = [
                exec for exec in s.executed_slashes if (
                    exec.time_exec >= execution.time_exec and exec.time_exec <= 3 * 24 * 60 * 60 + execution.time_exec
                )
            ]
            assert sum(exec.amount for exec in execs_in_next_3_days) <= int(Decimal("100_000e18"))
