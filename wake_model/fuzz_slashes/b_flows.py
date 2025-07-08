from wake.testing.core import TransactionStatusEnum
from ..common import *
from .a_init import *


class Flows(Init):
    @flow()
    def flow_request_slash(s):
        executed_time_caps = [exec.time_cap for exec in s.executed_slashes]
        time_last_capture = max(executed_time_caps) if len(executed_time_caps) > 0 else 0
        time_cap = random_int(
            # We need /at least/ 11 days in the past, but also /at least/ time of last capture
            max(chain.blocks[-1].timestamp - 11 * 24 * 60 * 60 + 1, time_last_capture + 1),
            chain.blocks[-1].timestamp - 1,
            edge_values_prob=0.05,
        )

        assert int(Decimal("100_000e18")) == s.NETWORK_DELEGATOR.stakeAt(s.SUBNETWORK, s.OPERATOR, time_cap, bytes())
        assert (i_cumulative_slash_at := s.cumulative_slash_at(time_cap)) == s.VETO_SLASHER.cumulativeSlashAt(
            s.SUBNETWORK, s.OPERATOR, time_cap, bytes()
        )
        i_cumulative_slash = s.executed_slashes[-1].cumulative_slash if len(s.executed_slashes) > 0 else 0
        assert i_cumulative_slash == s.VETO_SLASHER.cumulativeSlash(s.SUBNETWORK, s.OPERATOR)
        i_slashable_amt = max(
            int(Decimal("100_000e18")) + i_cumulative_slash_at - i_cumulative_slash,
            0
        )
        print(f"i_slashable_amt: {i_slashable_amt}, time_cap: {time_cap}")
        assert i_slashable_amt == s.VETO_SLASHER.slashableStake(s.SUBNETWORK, s.OPERATOR, time_cap, bytes())
        if i_slashable_amt > 0:
            i_requested_amt = random_int(
                0,
                i_slashable_amt,
                edge_values_prob=0.15,
            )
        else:
            i_requested_amt = 0

        with may_revert(TransactionRevertedError) as e:
            tx_request = s.VETO_SLASHER.requestSlash(
                s.SUBNETWORK,
                s.OPERATOR,
                i_requested_amt,
                time_cap,
                bytes(),
                from_=s.HYPERLANE_NETWORK
            )
        if i_requested_amt > 0:
            assert e.value is None and tx_request.status == TransactionStatusEnum.SUCCESS
            s.requested_slashes.append(Request(time_cap, tx_request.block.timestamp, i_requested_amt))
            with open(P_FLOWS_AND_TRANSACTIONS, 'a') as f:
                writer = csv.writer(f)
                writer.writerow([
                    None, None, None, True, s.stats.request_slash[True]
                ])
            s.stats.request_slash[True] += 1
        else:
            assert e.value is not None
            with open(P_FLOWS_AND_TRANSACTIONS, 'a') as f:
                writer = csv.writer(f)
                writer.writerow([
                    None, None, None, False, s.stats.request_slash[False]
                ])
            s.stats.request_slash[False] += 1
        print(s.stats)

    @flow()
    def flow_execute_slash(s):
        if len(s.requested_slashes) == 0:
            return

        i_idx = random.randint(
            0, len(s.requested_slashes) - 1
        )
        request = s.requested_slashes[i_idx]

        if chain.blocks[-1].timestamp < request.time_req + 3 * 24 * 60 * 60:
            chain.mine(lambda x: x + 3 * 24 * 60 * 60) # Mine a block 3 days later

        assert int(Decimal("100_000e18")) == s.NETWORK_DELEGATOR.stakeAt(
            s.SUBNETWORK, s.OPERATOR, request.time_cap, bytes()
        )
        assert (i_cumulative_slash_at := s.cumulative_slash_at(request.time_cap)) == s.VETO_SLASHER.cumulativeSlashAt(
            s.SUBNETWORK, s.OPERATOR, request.time_cap, bytes()
        )
        print("i_cumulative_slash_at", i_cumulative_slash_at)
        i_cumulative_slash = s.executed_slashes[-1].cumulative_slash if len(s.executed_slashes) > 0 else 0
        assert i_cumulative_slash == s.VETO_SLASHER.cumulativeSlash(s.SUBNETWORK, s.OPERATOR)
        print("i_cumulative_slash:", i_cumulative_slash)
        i_slashable_amt = max(
            int(Decimal("100_000e18")) + i_cumulative_slash_at - i_cumulative_slash,
            0
        )
        executed_time_caps = [exec.time_cap for exec in s.executed_slashes]
        time_last_capture = max(executed_time_caps) if len(executed_time_caps) > 0 else 0
        if (
            chain.blocks[-1].timestamp > request.time_cap + 14 * 24 * 60 * 60
            or request.time_cap < time_last_capture
        ):
            i_slashable_amt = 0
        assert i_slashable_amt == s.VETO_SLASHER.slashableStake(
            s.SUBNETWORK, s.OPERATOR, request.time_cap, bytes()
        )
        i_slashed_amt = min(i_slashable_amt, request.amount)

        with may_revert(TransactionRevertedError) as e:
            tx_execution = s.VETO_SLASHER.executeSlash(
                i_idx, # slashIndex is same as ours
                bytes(),
                from_=s.HYPERLANE_NETWORK
            )

        # Last block will include above txn
        if (
            request.executed
            or request.amount == 0
            or chain.blocks[-1].timestamp > request.time_cap + 14 * 24 * 60 * 60
            or i_slashable_amt == 0
        ):
            assert e.value is not None
            s.stats.execute_slash[False] += 1
        else:
            assert e.value is None and tx_execution.status == TransactionStatusEnum.SUCCESS
            assert tx_execution.return_value == i_slashed_amt
            request.executed = True
            s.stats.execute_slash[True] += 1
            i_cumulative_amount = s.executed_slashes[-1].cumulative_slash + i_slashed_amt if len(s.executed_slashes) > 0 else i_slashed_amt
            s.executed_slashes.append(Execution(request.time_cap, request.time_req, tx_execution.block.timestamp, i_cumulative_amount, i_slashed_amt))

