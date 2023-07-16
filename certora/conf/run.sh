certoraRun certora/conf/BondWrapper.conf --rule erc20Solvency
certoraRun certora/conf/BondWrapper.conf --rule mintIntegrityUser
certoraRun certora/conf/BondWrapper.conf --rule mintIntegritySystem
certoraRun certora/conf/BondWrapper.conf --rule mintIntegrityOthers
certoraRun certora/conf/BondWrapper.conf --rule mintIntegritySmallsVsBig
certoraRun certora/conf/BondWrapper.conf --rule closeIntegrityUser
certoraRun certora/conf/BondWrapper.conf --rule closeIntegrityOthers

certoraRun certora/conf/BondWrapperBug.conf --rule implementationCorrectness

certoraRun certora/conf/AaveHyperdriveVerified.conf --rule aTokenTransferBalanceTest
certoraRun certora/conf/AaveHyperdriveVerified.conf --rule sharePriceChangesForOnlyOneCheckPoint
certoraRun certora/conf/AaveHyperdriveVerified.conf --rule cannotChangeCheckPointSharePriceTwice
certoraRun certora/conf/AaveHyperdriveVerified.conf --rule onlyOneTokenTotalSupplyChangesAtATime
certoraRun certora/conf/AaveHyperdriveVerified.conf --rule mintingTokensOnlyAtMaturityTime
certoraRun certora/conf/AaveHyperdriveVerified.conf --rule NoFutureTokens
certoraRun certora/conf/AaveHyperdriveVerified.conf --rule WithdrawalSharesGEReadyShares
certoraRun certora/conf/AaveHyperdriveVerified.conf --rule SumOfLongsGEOutstanding
certoraRun certora/conf/AaveHyperdriveVerified.conf --rule SumOfShortsGEOutstanding
certoraRun certora/conf/AaveHyperdriveVerified.conf --rule dontSpendMore

certoraRun certora/conf/AaveHyperdriveVerified2.conf --rule openLongReallyOpensLong

certoraRun certora/conf/AaveHyperdriveBugs.conf --rule updateWeightedAverageCheck
certoraRun certora/conf/AaveHyperdriveBugs.conf --rule checkPointPriceIsSetCorrectly
certoraRun certora/conf/AaveHyperdriveBugs.conf --rule SharePriceAlwaysGreaterThanInitial

