"""Bots for fuzzing hyperdrive, along with mint/burn.
"""

from __future__ import annotations

import argparse
import logging
import os
import random
import sys
from typing import NamedTuple, Sequence

import numpy as np
from agent0 import LocalChain, LocalHyperdrive
from agent0.hyperfuzz.system_fuzz import generate_fuzz_hyperdrive_config, run_fuzz_bots
from agent0.hyperlogs.rollbar_utilities import initialize_rollbar, log_rollbar_exception
from fixedpointmath import FixedPoint
from hyperdrivetypes.types.IHyperdrive import Options, PairOptions
from pypechain.core import PypechainCallException
from web3.exceptions import ContractCustomError


def _fuzz_ignore_logging_to_rollbar(exc: Exception) -> bool:
    """Function defining errors to not log to rollbar during fuzzing.

    These are the two most common errors we see in local fuzz testing. These are
    known issues due to random bots not accounting for these cases, so we don't log them to
    rollbar.
    """
    if isinstance(exc, PypechainCallException):
        orig_exception = exc.orig_exception
        if orig_exception is None:
            return False

        # Insufficient liquidity error
        if isinstance(orig_exception, ContractCustomError) and exc.decoded_error == "InsufficientLiquidity()":
            return True

        # Circuit breaker triggered error
        if isinstance(orig_exception, ContractCustomError) and exc.decoded_error == "CircuitBreakerTriggered()":
            return True

    return False


def _fuzz_ignore_errors(exc: Exception) -> bool:
    """Function defining errors to ignore during fuzzing of hyperdrive pools."""
    # pylint: disable=too-many-return-statements
    # pylint: disable=too-many-branches
    # Ignored fuzz exceptions

    # Contract call exceptions
    if isinstance(exc, PypechainCallException):
        orig_exception = exc.orig_exception
        if orig_exception is None:
            return False

        # Insufficient liquidity error
        if isinstance(orig_exception, ContractCustomError) and exc.decoded_error == "InsufficientLiquidity()":
            return True

        # Circuit breaker triggered error
        if isinstance(orig_exception, ContractCustomError) and exc.decoded_error == "CircuitBreakerTriggered()":
            return True

        # DistributeExcessIdle error
        if isinstance(orig_exception, ContractCustomError) and exc.decoded_error == "DistributeExcessIdleFailed()":
            return True

        # MinimumTransactionAmount error
        if isinstance(orig_exception, ContractCustomError) and exc.decoded_error == "MinimumTransactionAmount()":
            return True

        # DecreasedPresentValueWhenAddingLiquidity error
        if (
            isinstance(orig_exception, ContractCustomError)
            and exc.decoded_error == "DecreasedPresentValueWhenAddingLiquidity()"
        ):
            return True

        # Closing long results in fees exceeding long proceeds
        if len(exc.args) > 1 and "Closing the long results in fees exceeding long proceeds" in exc.args[0]:
            return True

        # # Status == 0
        # if (
        #     isinstance(orig_exception, FailedTransaction)
        #     and len(orig_exception.args) > 0
        #     and "Receipt has status of 0" in orig_exception.args[0]
        # ):
        #     return True

    return False


def main(argv: Sequence[str] | None = None) -> None:
    """Runs the mint/burn fuzzing.

    Arguments
    ---------
    argv: Sequence[str]
        The argv values returned from argparser.
    """
    # pylint: disable=too-many-branches

    parsed_args = parse_arguments(argv)

    # Negative rng_seed means default
    if parsed_args.rng_seed < 0:
        rng_seed = random.randint(0, 10000000)
    else:
        rng_seed = parsed_args.rng_seed
    rng = np.random.default_rng(rng_seed)

    # Set up rollbar
    # TODO log additional crashes
    rollbar_environment_name = "fuzz_mint_burn"
    log_to_rollbar = initialize_rollbar(rollbar_environment_name)

    # Set up chain config
    local_chain_config = LocalChain.Config(
        block_timestamp_interval=12,
        log_level_threshold=logging.WARNING,
        preview_before_trade=True,
        log_to_rollbar=log_to_rollbar,
        rollbar_log_prefix="localfuzzbots",
        rollbar_log_filter_func=_fuzz_ignore_logging_to_rollbar,
        rng=rng,
        crash_log_level=logging.ERROR,
        rollbar_log_level_threshold=logging.ERROR,  # Only log errors and above to rollbar
        crash_report_additional_info={"rng_seed": rng_seed},
        gas_limit=int(1e6),  # Plenty of gas limit for transactions
    )

    # FIXME wrap all of this in a try catch to catch any exceptions thrown in fuzzing.
    # When an error occurs, we likely want to pause the chain to allow for remote connection
    # for debugging
    while True:
        # Build interactive local hyperdrive
        # TODO can likely reuse some of these resources
        # instead, we start from scratch every time.
        chain = LocalChain(local_chain_config)

        # Fuzz over config values
        hyperdrive_config = generate_fuzz_hyperdrive_config(rng, lp_share_price_test=False, steth=False)

        try:
            hyperdrive_pool = LocalHyperdrive(chain, hyperdrive_config)
        except Exception as e:  # pylint: disable=broad-except
            logging.error(
                "Error deploying hyperdrive: %s",
                repr(e),
            )
            log_rollbar_exception(
                e,
                log_level=logging.ERROR,
                rollbar_log_prefix="Error deploying hyperdrive poolError deploying hyperdrive pool",
            )
            chain.cleanup()
            continue

        agents = None

        # Run the fuzzing bot for an episode
        for _ in range(parsed_args.num_iterations_per_episode):
            # Run fuzzing via agent0 function on underlying hyperdrive pool.
            # By default, this sets up 4 agents.
            # `check_invariance` also runs the pool's invariance checks after trades.
            # We only run for 1 iteration here, as we want to make additional random trades
            # wrt mint/burn.
            agents = run_fuzz_bots(
                chain,
                hyperdrive_pools=[hyperdrive_pool],
                # We pass in the same agents when running fuzzing
                agents=agents,
                check_invariance=True,
                raise_error_on_failed_invariance_checks=True,
                raise_error_on_crash=True,
                log_to_rollbar=log_to_rollbar,
                ignore_raise_error_func=_fuzz_ignore_errors,
                random_advance_time=False,  # We take care of advancing time in the outer loop
                lp_share_price_test=False,
                base_budget_per_bot=FixedPoint(1_000_000),
                num_iterations=1,
                minimum_avg_agent_base=FixedPoint(100_000),
            )

            # Get access to the underlying hyperdrive contract for pypechain calls
            hyperdrive_contract = hyperdrive_pool.interface.hyperdrive_contract

            # Run random vault mint/burn
            for agent in agents:
                # Pick mint or burn at random
                trade = chain.config.rng.choice(["mint", "burn"])  # type: ignore
                match trade:
                    case "mint":
                        balance = agent.get_wallet().balance.amount
                        if balance > 0:
                            # TODO can't use numpy rng since it doesn't support uint256.
                            # Need to use the state from the chain config to use the same rng object.
                            amount = random.randint(0, balance.scaled_value)
                            logging.info(f"Agent {agent.address} is calling minting with {amount}")

                            # FIXME figure out what these options are
                            pair_options = PairOptions(
                                longDestination=agent.address,
                                shortDestination=agent.address,
                                asBase=True,
                                extraData=bytes(0),
                            )

                            hyperdrive_contract.functions.mint(
                                _amount=amount, _minOutput=0, _minVaultSharePrice=0, _options=pair_options
                            ).sign_transact_and_wait(account=agent.account, validate_transaction=True)

                    case "burn":
                        # FIXME figure out in what cases an agent can burn tokens
                        agent_longs = agent.get_longs()
                        num_longs = len(agent_longs)
                        if num_longs > 0 and agent_longs[0].balance > 0:
                            amount = random.randint(0, balance.scaled_value)
                            logging.info(f"Agent {agent.address} is calling burn with {amount}")

                            # FIXME figure out what these options are
                            # pair_options = PairOptions(
                            #     longDestination=agent.address,
                            #     shortDestination=agent.address,
                            #     asBase=True,
                            #     extraData=bytes(0),
                            # )
                            options = Options(
                                destination=agent.address,
                                asBase=True,
                                extraData=bytes(0),
                            )

                            # FIXME figure out what _maturityTime is
                            # FIXME burn is expecting `Options`, not `PairOptions`
                            hyperdrive_contract.functions.burn(
                                _maturityTime=0, _bondAmount=0, _minOutput=0, _options=options
                            ).sign_transact_and_wait(account=agent.account, validate_transaction=True)

            # FIXME add any additional invariance checks specific to mint/burn here.

        # Advance time for a day
        # TODO parameterize the amount of time to advance.
        chain.advance_time(60 * 60 * 24)


class Args(NamedTuple):
    """Command line arguments for fuzzing mint/burn."""

    rng_seed: int
    num_iterations_per_episode: int


def namespace_to_args(namespace: argparse.Namespace) -> Args:
    """Converts argprase.Namespace to Args.

    Arguments
    ---------
    namespace: argparse.Namespace
        Object for storing arg attributes.

    Returns
    -------
    Args
        Formatted arguments
    """
    return Args(
        rng_seed=namespace.rng_seed,
        num_iterations_per_episode=namespace.num_iterations_per_episode,
    )


def parse_arguments(argv: Sequence[str] | None = None) -> Args:
    """Parses input arguments.

    Arguments
    ---------
    argv: Sequence[str]
        The argv values returned from argparser.

    Returns
    -------
    Args
        Formatted arguments
    """
    parser = argparse.ArgumentParser(description="Runs fuzzing mint/burn")

    parser.add_argument(
        "--rng-seed",
        type=int,
        default=-1,
        help="The random seed to use for the fuzz run.",
    )
    parser.add_argument(
        "--num-iterations-per-episode",
        default=3000,
        help="The number of iterations to run for each random pool config.",
    )

    # Use system arguments if none were passed
    if argv is None:
        argv = sys.argv
    return namespace_to_args(parser.parse_args())


# Run fuzing
if __name__ == "__main__":
    # Wrap everything in a try catch to log any non-caught critical errors and log to rollbar
    try:
        main()
    except BaseException as exc:  # pylint: disable=broad-except
        # pylint: disable=invalid-name
        _rpc_uri = os.getenv("RPC_URI", None)
        if _rpc_uri is None:
            _log_prefix = "Uncaught Critical Error in Fuzzing mint/burn:"
        else:
            _chain_name = _rpc_uri.split("//")[-1].split("/")[0]
            _log_prefix = f"Uncaught Critical Error for {_chain_name} in Fuzz mint/burn:"
        log_rollbar_exception(exception=exc, log_level=logging.CRITICAL, rollbar_log_prefix=_log_prefix)
        raise exc
