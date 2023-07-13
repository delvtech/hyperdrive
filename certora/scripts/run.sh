certoraRun certora/conf/AaveHyperdrive.conf --rule cannotChangeCheckPointSharePriceTwice
certoraRun certora/conf/AaveHyperdrive.conf --rule onlyOneTokenTotalSupplyChangesAtATime
certoraRun certora/conf/AaveHyperdrive.conf --rule mintingTokensOnlyAtMaturityTime
certoraRun certora/conf/AaveHyperdrive.conf --rule NoFutureTokens
certoraRun certora/conf/AaveHyperdrive.conf --rule WithdrawalSharesGEReadyShares
certoraRun certora/conf/AaveHyperdrive.conf --rule SumOfLongsGEOutstanding
certoraRun certora/conf/AaveHyperdrive.conf --rule SumOfShortsGEOutstanding
certoraRun certora/conf/AaveHyperdrive.conf --rule openLongReallyOpensLong
