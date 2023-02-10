// SPDX-License-Identifier: MIT
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "../interfaces/StorageInterfaceV5.sol";
import "../interfaces/GNSPairInfosInterfaceV6.sol";
import "../interfaces/GNSReferralsInterfaceV6_2.sol";
import "../interfaces/GNSStakingInterfaceV6_2.sol";
import "../interfaces/AggregatorInterfaceV6.sol";
import "hardhat/console.sol";
pragma solidity 0.8.10;

contract MMTTradingCallbacks is Initializable {
    // Contracts (constant)
    StorageInterfaceV5 public storageT;
    NftRewardsInterfaceV6 public nftRewards;
    GNSPairInfosInterfaceV6 public pairInfos;
    GNSReferralsInterfaceV6_2 public referrals;
    GNSStakingInterfaceV6_2 public staking;

    // Params (constant)
    uint256 constant PRECISION = 1e10; // 10 decimals

    uint256 constant MAX_SL_P = 75; // -75% PNL
    uint256 constant MAX_GAIN_P = 900; // 900% PnL (10x)

    // Params (adjustable)
    uint256 public daiVaultFeeP; // % of closing fee going to DAI vault (eg. 40)
    uint256 public lpFeeP; // % of closing fee going to GNS/DAI LPs (eg. 20)
    uint256 public sssFeeP; // % of closing fee going to GNS staking (eg. 40)

    // State
    bool public isPaused; // Prevent opening new trades
    bool public isDone; // Prevent any interaction with the contract

    // Custom data types
    struct AggregatorAnswer {
        uint256 orderId;
        uint256 price;
        uint256 spreadP;
    }

    // Useful to avoid stack too deep errors
    struct Values {
        uint256 posDai;
        uint256 levPosDai;
        uint256 tokenPriceDai;
        int256 profitP;
        uint256 price;
        uint256 liqPrice;
        uint256 daiSentToTrader;
        uint256 reward1;
        uint256 reward2;
        uint256 reward3;
    }

    // Events
    event MarketExecuted(
        uint256 indexed orderId,
        StorageInterfaceV5.Trade t,
        bool open,
        uint256 price,
        uint256 priceImpactP,
        uint256 positionSizeDai,
        int256 percentProfit,
        uint256 daiSentToTrader
    );

    event LimitExecuted(
        uint256 indexed orderId,
        uint256 limitIndex,
        StorageInterfaceV5.Trade t,
        address indexed nftHolder,
        StorageInterfaceV5.LimitOrder orderType,
        uint256 price,
        uint256 priceImpactP,
        uint256 positionSizeDai,
        int256 percentProfit,
        uint256 daiSentToTrader
    );

    event MarketOpenCanceled(
        uint256 indexed orderId,
        address indexed trader,
        uint256 indexed pairIndex
    );
    event MarketCloseCanceled(
        uint256 indexed orderId,
        address indexed trader,
        uint256 indexed pairIndex,
        uint256 index
    );

    event SlUpdated(
        uint256 indexed orderId,
        address indexed trader,
        uint256 indexed pairIndex,
        uint256 index,
        uint256 newSl
    );
    event SlCanceled(
        uint256 indexed orderId,
        address indexed trader,
        uint256 indexed pairIndex,
        uint256 index
    );

    event ClosingFeeSharesPUpdated(
        uint256 daiVaultFeeP,
        uint256 lpFeeP,
        uint256 sssFeeP
    );

    event Pause(bool paused);
    event Done(bool done);

    event DevGovFeeCharged(address indexed trader, uint256 valueDai);
    event ReferralFeeCharged(address indexed trader, uint256 valueDai);
    event NftBotFeeCharged(address indexed trader, uint256 valueDai);
    event SssFeeCharged(address indexed trader, uint256 valueDai);
    event DaiVaultFeeCharged(address indexed trader, uint256 valueDai);
    event LpFeeCharged(address indexed trader, uint256 valueDai);

    function initialize(
        StorageInterfaceV5 _storageT,
        NftRewardsInterfaceV6 _nftRewards,
        GNSPairInfosInterfaceV6 _pairInfos,
        GNSReferralsInterfaceV6_2 _referrals,
        GNSStakingInterfaceV6_2 _staking,
        address vaultToApprove,
        uint256 _daiVaultFeeP,
        uint256 _lpFeeP,
        uint256 _sssFeeP
    ) external initializer {
        require(
            address(_storageT) != address(0) &&
                address(_nftRewards) != address(0) &&
                address(_pairInfos) != address(0) &&
                address(_referrals) != address(0) &&
                address(_staking) != address(0) &&
                _daiVaultFeeP + _lpFeeP + _sssFeeP == 100,
            "WRONG_PARAMS"
        );

        storageT = _storageT;
        nftRewards = _nftRewards;
        pairInfos = _pairInfos;
        referrals = _referrals;
        staking = _staking;

        daiVaultFeeP = _daiVaultFeeP;
        lpFeeP = _lpFeeP;
        sssFeeP = _sssFeeP;

        storageT.dai().approve(address(staking), type(uint256).max);
        storageT.dai().approve(vaultToApprove, type(uint256).max);
    }

    // Modifiers
    modifier onlyGov() {
        require(msg.sender == storageT.gov(), "GOV_ONLY");
        _;
    }
    modifier onlyPriceAggregator() {
        require(
            msg.sender == address(storageT.priceAggregator()),
            "AGGREGATOR_ONLY"
        );
        _;
    }
    modifier notDone() {
        require(!isDone, "DONE");
        _;
    }

    // Manage params
    function setClosingFeeSharesP(
        uint256 _daiVaultFeeP,
        uint256 _lpFeeP,
        uint256 _sssFeeP
    ) external onlyGov {
        require(_daiVaultFeeP + _lpFeeP + _sssFeeP == 100, "SUM_NOT_100");

        daiVaultFeeP = _daiVaultFeeP;
        lpFeeP = _lpFeeP;
        sssFeeP = _sssFeeP;

        emit ClosingFeeSharesPUpdated(_daiVaultFeeP, _lpFeeP, _sssFeeP);
    }

    // Manage state
    function pause() external onlyGov {
        isPaused = !isPaused;
        emit Pause(isPaused);
    }

    function done() external onlyGov {
        isDone = !isDone;
        emit Done(isDone);
    }

    // Callbacks
    function openTradeMarketCallback(AggregatorAnswer memory a)
        external
        onlyPriceAggregator
        notDone
    {
        StorageInterfaceV5.PendingMarketOrder memory o = storageT
            .reqID_pendingMarketOrder(a.orderId);

        if (o.block == 0) {
            return;
        }

        StorageInterfaceV5.Trade memory t = o.trade;

        (uint256 priceImpactP, uint256 priceAfterImpact) = pairInfos
            .getTradePriceImpact(
                marketExecutionPrice(
                    a.price,
                    a.spreadP,
                    o.spreadReductionP,
                    t.buy
                ),
                t.pairIndex,
                t.buy,
                t.positionSizeDai * t.leverage
            );

        t.openPrice = priceAfterImpact;

        uint256 maxSlippage = (o.wantedPrice * o.slippageP) / 100 / PRECISION;
        if (
            isPaused ||
            a.price == 0 ||
            (
                t.buy
                    ? t.openPrice > o.wantedPrice + maxSlippage
                    : t.openPrice < o.wantedPrice - maxSlippage
            ) ||
            (t.tp > 0 && (t.buy ? t.openPrice >= t.tp : t.openPrice <= t.tp)) ||
            (t.sl > 0 && (t.buy ? t.openPrice <= t.sl : t.openPrice >= t.sl)) ||
            !withinExposureLimits(
                t.pairIndex,
                t.buy,
                t.positionSizeDai,
                t.leverage
            ) ||
            priceImpactP * t.leverage > pairInfos.maxNegativePnlOnOpenP()
        ) {
            uint256 devGovFeesDai = storageT.handleDevGovFees(
                t.pairIndex,
                t.positionSizeDai * t.leverage,
                true,
                true
            );

            storageT.transferDai(
                address(storageT),
                t.trader,
                t.positionSizeDai - devGovFeesDai
            );

            emit DevGovFeeCharged(t.trader, devGovFeesDai);

            emit MarketOpenCanceled(a.orderId, t.trader, t.pairIndex);
        } else {
            (
                StorageInterfaceV5.Trade memory finalTrade,
                uint256 tokenPriceDai
            ) = registerTrade(t, 1500, 0);

            emit MarketExecuted(
                a.orderId,
                finalTrade,
                true,
                finalTrade.openPrice,
                priceImpactP,
                (finalTrade.initialPosToken * tokenPriceDai) / PRECISION,
                0,
                0
            );
        }

        storageT.unregisterPendingMarketOrder(a.orderId, true);
    }

    function closeTradeMarketCallback(AggregatorAnswer memory a)
        external
        onlyPriceAggregator
        notDone
    {
        StorageInterfaceV5.PendingMarketOrder memory o = storageT
            .reqID_pendingMarketOrder(a.orderId);

        if (o.block == 0) {
            return;
        }

        StorageInterfaceV5.Trade memory t = storageT.openTrades(
            o.trade.trader,
            o.trade.pairIndex,
            o.trade.index
        );

        if (t.leverage > 0) {
            StorageInterfaceV5.TradeInfo memory i = storageT.openTradesInfo(
                t.trader,
                t.pairIndex,
                t.index
            );

            AggregatorInterfaceV6 aggregator = storageT.priceAggregator();
            PairsStorageInterfaceV6 pairsStorage = aggregator.pairsStorage();

            Values memory v;

            v.levPosDai =
                (t.initialPosToken * i.tokenPriceDai * t.leverage) /
                PRECISION;
            v.tokenPriceDai = aggregator.tokenPriceDai();

            if (a.price == 0) {
                // Dev / gov rewards to pay for oracle cost
                // Charge in DAI if collateral in storage or token if collateral in vault
                v.reward1 = t.positionSizeDai > 0
                    ? storageT.handleDevGovFees(
                        t.pairIndex,
                        v.levPosDai,
                        true,
                        true
                    )
                    : (storageT.handleDevGovFees(
                        t.pairIndex,
                        (v.levPosDai * PRECISION) / v.tokenPriceDai,
                        false,
                        true
                    ) * v.tokenPriceDai) / PRECISION;

                t.initialPosToken -= (v.reward1 * PRECISION) / i.tokenPriceDai;
                storageT.updateTrade(t);

                emit DevGovFeeCharged(t.trader, v.reward1);

                emit MarketCloseCanceled(
                    a.orderId,
                    t.trader,
                    t.pairIndex,
                    t.index
                );
            } else {
                v.profitP = currentPercentProfit(
                    t.openPrice,
                    a.price,
                    t.buy,
                    t.leverage
                );
                v.posDai = v.levPosDai / t.leverage;

                v.daiSentToTrader = unregisterTrade(
                    t,
                    true,
                    v.profitP,
                    v.posDai,
                    i.openInterestDai / t.leverage,
                    (v.levPosDai * pairsStorage.pairCloseFeeP(t.pairIndex)) /
                        100 /
                        PRECISION,
                    (v.levPosDai *
                        pairsStorage.pairNftLimitOrderFeeP(t.pairIndex)) /
                        100 /
                        PRECISION,
                    v.tokenPriceDai
                );

                emit MarketExecuted(
                    a.orderId,
                    t,
                    false,
                    a.price,
                    0,
                    v.posDai,
                    v.profitP,
                    v.daiSentToTrader
                );
            }
        }

        storageT.unregisterPendingMarketOrder(a.orderId, false);
    }

    function executeNftOpenOrderCallback(AggregatorAnswer memory a)
        external
        onlyPriceAggregator
        notDone
    {
        StorageInterfaceV5.PendingNftOrder memory n = storageT
            .reqID_pendingNftOrder(a.orderId);

        if (
            !isPaused &&
            a.price > 0 &&
            storageT.hasOpenLimitOrder(n.trader, n.pairIndex, n.index) &&
            block.number >=
            storageT.nftLastSuccess(n.nftId) + storageT.nftSuccessTimelock()
        ) {
            StorageInterfaceV5.OpenLimitOrder memory o = storageT
                .getOpenLimitOrder(n.trader, n.pairIndex, n.index);

            NftRewardsInterfaceV6.OpenLimitOrderType t = nftRewards
                .openLimitOrderTypes(n.trader, n.pairIndex, n.index);

            (uint256 priceImpactP, uint256 priceAfterImpact) = pairInfos
                .getTradePriceImpact(
                    marketExecutionPrice(
                        a.price,
                        a.spreadP,
                        o.spreadReductionP,
                        o.buy
                    ),
                    o.pairIndex,
                    o.buy,
                    o.positionSize * o.leverage
                );

            a.price = priceAfterImpact;
            if (
                (
                    t == NftRewardsInterfaceV6.OpenLimitOrderType.LEGACY
                        ? (a.price >= o.minPrice && a.price <= o.maxPrice)
                        : t == NftRewardsInterfaceV6.OpenLimitOrderType.REVERSAL
                        ? (
                            o.buy
                                ? a.price <= o.maxPrice
                                : a.price >= o.minPrice
                        )
                        : (
                            o.buy
                                ? a.price >= o.minPrice
                                : a.price <= o.maxPrice
                        )
                ) &&
                withinExposureLimits(
                    o.pairIndex,
                    o.buy,
                    o.positionSize,
                    o.leverage
                ) &&
                priceImpactP * o.leverage <= pairInfos.maxNegativePnlOnOpenP()
            ) {
                (
                    StorageInterfaceV5.Trade memory finalTrade,
                    uint256 tokenPriceDai
                ) = registerTrade(
                        StorageInterfaceV5.Trade(
                            o.trader,
                            o.pairIndex,
                            0,
                            0,
                            o.positionSize,
                            t ==
                                NftRewardsInterfaceV6
                                    .OpenLimitOrderType
                                    .REVERSAL
                                ? o.maxPrice // o.minPrice = o.maxPrice in that case
                                : a.price,
                            o.buy,
                            o.leverage,
                            o.tp,
                            o.sl
                        ),
                        n.nftId,
                        n.index
                    );

                storageT.unregisterOpenLimitOrder(
                    o.trader,
                    o.pairIndex,
                    o.index
                );

                emit LimitExecuted(
                    a.orderId,
                    n.index,
                    finalTrade,
                    n.nftHolder,
                    StorageInterfaceV5.LimitOrder.OPEN,
                    finalTrade.openPrice,
                    priceImpactP,
                    (finalTrade.initialPosToken * tokenPriceDai) / PRECISION,
                    0,
                    0
                );
            }
        }

        nftRewards.unregisterTrigger(
            NftRewardsInterfaceV6.TriggeredLimitId(
                n.trader,
                n.pairIndex,
                n.index,
                n.orderType
            )
        );

        storageT.unregisterPendingNftOrder(a.orderId);
    }

    function executeNftCloseOrderCallback(AggregatorAnswer memory a)
        external
        onlyPriceAggregator
        notDone
    {
        StorageInterfaceV5.PendingNftOrder memory o = storageT
            .reqID_pendingNftOrder(a.orderId);

        StorageInterfaceV5.Trade memory t = storageT.openTrades(
            o.trader,
            o.pairIndex,
            o.index
        );

        AggregatorInterfaceV6 aggregator = storageT.priceAggregator();

        if (
            a.price > 0 &&
            t.leverage > 0 &&
            block.number >=
            storageT.nftLastSuccess(o.nftId) + storageT.nftSuccessTimelock()
        ) {
            StorageInterfaceV5.TradeInfo memory i = storageT.openTradesInfo(
                t.trader,
                t.pairIndex,
                t.index
            );

            PairsStorageInterfaceV6 pairsStored = aggregator.pairsStorage();

            Values memory v;

            v.price = pairsStored.guaranteedSlEnabled(t.pairIndex)
                ? o.orderType == StorageInterfaceV5.LimitOrder.TP
                    ? t.tp
                    : o.orderType == StorageInterfaceV5.LimitOrder.SL
                    ? t.sl
                    : a.price
                : a.price;

            v.profitP = currentPercentProfit(
                t.openPrice,
                v.price,
                t.buy,
                t.leverage
            );
            v.levPosDai =
                (t.initialPosToken * i.tokenPriceDai * t.leverage) /
                PRECISION;
            v.posDai = v.levPosDai / t.leverage;

            if (o.orderType == StorageInterfaceV5.LimitOrder.LIQ) {
                v.liqPrice = pairInfos.getTradeLiquidationPrice(
                    t.trader,
                    t.pairIndex,
                    t.index,
                    t.openPrice,
                    t.buy,
                    v.posDai,
                    t.leverage
                );

                // NFT reward in DAI
                v.reward1 = (
                    t.buy ? a.price <= v.liqPrice : a.price >= v.liqPrice
                )
                    ? (v.posDai * 5) / 100
                    : 0;
            } else {
                // NFT reward in DAI
                v.reward1 = ((o.orderType == StorageInterfaceV5.LimitOrder.TP &&
                    t.tp > 0 &&
                    (t.buy ? a.price >= t.tp : a.price <= t.tp)) ||
                    (o.orderType == StorageInterfaceV5.LimitOrder.SL &&
                        t.sl > 0 &&
                        (t.buy ? a.price <= t.sl : a.price >= t.sl)))
                    ? (v.levPosDai *
                        pairsStored.pairNftLimitOrderFeeP(t.pairIndex)) /
                        100 /
                        PRECISION
                    : 0;
            }

            // If can be triggered
            if (v.reward1 > 0) {
                v.tokenPriceDai = aggregator.tokenPriceDai();

                v.daiSentToTrader = unregisterTrade(
                    t,
                    false,
                    v.profitP,
                    v.posDai,
                    i.openInterestDai / t.leverage,
                    o.orderType == StorageInterfaceV5.LimitOrder.LIQ
                        ? v.reward1
                        : (v.levPosDai *
                            pairsStored.pairCloseFeeP(t.pairIndex)) /
                            100 /
                            PRECISION,
                    v.reward1,
                    v.tokenPriceDai
                );

                // Convert NFT bot fee from DAI to token value
                v.reward2 = (v.reward1 * PRECISION) / v.tokenPriceDai;

                nftRewards.distributeNftReward(
                    NftRewardsInterfaceV6.TriggeredLimitId(
                        o.trader,
                        o.pairIndex,
                        o.index,
                        o.orderType
                    ),
                    v.reward2
                );

                storageT.increaseNftRewards(o.nftId, v.reward2);

                emit NftBotFeeCharged(t.trader, v.reward1);

                emit LimitExecuted(
                    a.orderId,
                    o.index,
                    t,
                    o.nftHolder,
                    o.orderType,
                    v.price,
                    0,
                    v.posDai,
                    v.profitP,
                    v.daiSentToTrader
                );
            }
        }

        nftRewards.unregisterTrigger(
            NftRewardsInterfaceV6.TriggeredLimitId(
                o.trader,
                o.pairIndex,
                o.index,
                o.orderType
            )
        );

        storageT.unregisterPendingNftOrder(a.orderId);
    }

    function updateSlCallback(AggregatorAnswer memory a)
        external
        onlyPriceAggregator
        notDone
    {
        AggregatorInterfaceV6 aggregator = storageT.priceAggregator();
        AggregatorInterfaceV6.PendingSl memory o = aggregator.pendingSlOrders(
            a.orderId
        );

        StorageInterfaceV5.Trade memory t = storageT.openTrades(
            o.trader,
            o.pairIndex,
            o.index
        );

        if (t.leverage > 0) {
            StorageInterfaceV5.TradeInfo memory i = storageT.openTradesInfo(
                o.trader,
                o.pairIndex,
                o.index
            );

            Values memory v;

            v.tokenPriceDai = aggregator.tokenPriceDai();
            v.levPosDai =
                (t.initialPosToken * i.tokenPriceDai * t.leverage) /
                PRECISION /
                2;

            // Charge in DAI if collateral in storage or token if collateral in vault
            v.reward1 = t.positionSizeDai > 0
                ? storageT.handleDevGovFees(
                    t.pairIndex,
                    v.levPosDai,
                    true,
                    false
                )
                : (storageT.handleDevGovFees(
                    t.pairIndex,
                    (v.levPosDai * PRECISION) / v.tokenPriceDai,
                    false,
                    false
                ) * v.tokenPriceDai) / PRECISION;

            t.initialPosToken -= (v.reward1 * PRECISION) / i.tokenPriceDai;
            storageT.updateTrade(t);

            emit DevGovFeeCharged(t.trader, v.reward1);

            if (
                a.price > 0 &&
                t.buy == o.buy &&
                t.openPrice == o.openPrice &&
                (t.buy ? o.newSl <= a.price : o.newSl >= a.price)
            ) {
                storageT.updateSl(o.trader, o.pairIndex, o.index, o.newSl);

                emit SlUpdated(
                    a.orderId,
                    o.trader,
                    o.pairIndex,
                    o.index,
                    o.newSl
                );
            } else {
                emit SlCanceled(a.orderId, o.trader, o.pairIndex, o.index);
            }
        }

        aggregator.unregisterPendingSlOrder(a.orderId);
    }

    // Shared code between market & limit callbacks
    function registerTrade(
        StorageInterfaceV5.Trade memory trade,
        uint256 nftId,
        uint256 limitIndex
    ) private returns (StorageInterfaceV5.Trade memory, uint256) {
        AggregatorInterfaceV6 aggregator = storageT.priceAggregator();
        PairsStorageInterfaceV6 pairsStored = aggregator.pairsStorage();

        Values memory v;

        v.levPosDai = trade.positionSizeDai * trade.leverage;
        v.tokenPriceDai = aggregator.tokenPriceDai();

        // 1. Charge referral fee (if applicable) and send DAI amount to vault
        if (referrals.getTraderReferrer(trade.trader) != address(0)) {
            // Use this variable to store lev pos dai for dev/gov fees after referral fees
            // and before volumeReferredDai increases
            v.posDai =
                (v.levPosDai *
                    (100 *
                        PRECISION -
                        referrals.getPercentOfOpenFeeP(trade.trader))) /
                100 /
                PRECISION;

            v.reward1 = referrals.distributePotentialReward(
                trade.trader,
                v.levPosDai,
                pairsStored.pairOpenFeeP(trade.pairIndex),
                v.tokenPriceDai
            );

            sendToVault(v.reward1, trade.trader);
            trade.positionSizeDai -= v.reward1;

            emit ReferralFeeCharged(trade.trader, v.reward1);
        }

        // 2. Charge opening fee - referral fee (if applicable)
        v.reward2 = storageT.handleDevGovFees(
            trade.pairIndex,
            (v.posDai > 0 ? v.posDai : v.levPosDai),
            true,
            true
        );

        trade.positionSizeDai -= v.reward2;

        emit DevGovFeeCharged(trade.trader, v.reward2);

        // 3. Charge NFT / SSS fee
        v.reward2 =
            (v.levPosDai * pairsStored.pairNftLimitOrderFeeP(trade.pairIndex)) /
            100 /
            PRECISION;
        trade.positionSizeDai -= v.reward2;

        // 3.1 Distribute NFT fee and send DAI amount to vault (if applicable)
        if (nftId < 1500) {
            sendToVault(v.reward2, trade.trader);

            // Convert NFT bot fee from DAI to token value
            v.reward3 = (v.reward2 * PRECISION) / v.tokenPriceDai;

            nftRewards.distributeNftReward(
                NftRewardsInterfaceV6.TriggeredLimitId(
                    trade.trader,
                    trade.pairIndex,
                    limitIndex,
                    StorageInterfaceV5.LimitOrder.OPEN
                ),
                v.reward3
            );
            storageT.increaseNftRewards(nftId, v.reward3);

            emit NftBotFeeCharged(trade.trader, v.reward2);

            // 3.2 Distribute SSS fee (if applicable)
        } else {
            distributeStakingReward(trade.trader, v.reward2);
        }

        // 4. Set trade final details
        trade.index = storageT.firstEmptyTradeIndex(
            trade.trader,
            trade.pairIndex
        );
        trade.initialPosToken =
            (trade.positionSizeDai * PRECISION) /
            v.tokenPriceDai;

        trade.tp = correctTp(
            trade.openPrice,
            trade.leverage,
            trade.tp,
            trade.buy
        );
        trade.sl = correctSl(
            trade.openPrice,
            trade.leverage,
            trade.sl,
            trade.buy
        );

        // 5. Call other contracts
        pairInfos.storeTradeInitialAccFees(
            trade.trader,
            trade.pairIndex,
            trade.index,
            trade.buy
        );
        pairsStored.updateGroupCollateral(
            trade.pairIndex,
            trade.positionSizeDai,
            trade.buy,
            true
        );

        // 6. Store final trade in storage contract
        storageT.storeTrade(
            trade,
            StorageInterfaceV5.TradeInfo(
                0,
                v.tokenPriceDai,
                trade.positionSizeDai * trade.leverage,
                0,
                0,
                false
            )
        );

        return (trade, v.tokenPriceDai);
    }

    function unregisterTrade(
        StorageInterfaceV5.Trade memory trade,
        bool marketOrder,
        int256 percentProfit, // PRECISION
        uint256 currentDaiPos, // 1e18
        uint256 initialDaiPos, // 1e18
        uint256 closingFeeDai, // 1e18
        uint256 nftFeeDai, // 1e18 (= SSS reward if market order)
        uint256 tokenPriceDai // PRECISION
    ) private returns (uint256 daiSentToTrader) {
        // 1. Calculate net PnL (after all closing fees)
        daiSentToTrader = pairInfos.getTradeValue(
            trade.trader,
            trade.pairIndex,
            trade.index,
            trade.buy,
            currentDaiPos,
            trade.leverage,
            percentProfit,
            closingFeeDai + nftFeeDai
        );

        Values memory v;

        // 2. LP reward
        if (lpFeeP > 0) {
            v.reward1 = (closingFeeDai * lpFeeP) / 100;
            storageT.distributeLpRewards(
                (v.reward1 * PRECISION) / tokenPriceDai
            );

            emit LpFeeCharged(trade.trader, v.reward1);
        }

        // 3.1 If collateral in storage (opened after update)
        if (trade.positionSizeDai > 0) {
            // 3.1.1 DAI vault reward
            v.reward2 = (closingFeeDai * daiVaultFeeP) / 100;
            storageT.transferDai(address(storageT), address(this), v.reward2);
            storageT.vault().distributeReward(v.reward2);
            emit DaiVaultFeeCharged(trade.trader, v.reward2);

            // 3.1.2 SSS reward
            v.reward3 = marketOrder
                ? nftFeeDai + (closingFeeDai * sssFeeP) / 100
                : (closingFeeDai * sssFeeP) / 100;

            distributeStakingReward(trade.trader, v.reward3);

            // 3.1.3 Take DAI from vault if winning trade
            // or send DAI to vault if losing trade
            uint256 daiLeftInStorage = currentDaiPos - v.reward3 - v.reward2;

            if (daiSentToTrader > daiLeftInStorage) {
                storageT.vault().sendAssets(
                    daiSentToTrader - daiLeftInStorage,
                    trade.trader
                );
                storageT.transferDai(
                    address(storageT),
                    trade.trader,
                    daiLeftInStorage
                );
            } else {
                sendToVault(daiLeftInStorage - daiSentToTrader, trade.trader);
                storageT.transferDai(
                    address(storageT),
                    trade.trader,
                    daiSentToTrader
                );
            }

            // 3.2 If collateral in vault (opened before update)
        } else {
            storageT.vault().sendAssets(daiSentToTrader, trade.trader);
        }

        // 4. Calls to other contracts
        storageT.priceAggregator().pairsStorage().updateGroupCollateral(
            trade.pairIndex,
            initialDaiPos,
            trade.buy,
            false
        );

        // 5. Unregister trade
        storageT.unregisterTrade(trade.trader, trade.pairIndex, trade.index);
    }

    // Utils
    function withinExposureLimits(
        uint256 pairIndex,
        bool buy,
        uint256 positionSizeDai,
        uint256 leverage
    ) private view returns (bool) {
        PairsStorageInterfaceV6 pairsStored = storageT
            .priceAggregator()
            .pairsStorage();
        console.log(
            "pairsStored.groupMaxCollateral(pairIndex)",
            pairsStored.groupMaxCollateral(pairIndex)
        );
        return
            storageT.openInterestDai(pairIndex, buy ? 0 : 1) +
                positionSizeDai *
                leverage <=
            storageT.openInterestDai(pairIndex, 2) &&
            pairsStored.groupCollateral(pairIndex, buy) + positionSizeDai <=
            pairsStored.groupMaxCollateral(pairIndex);
    }

    function currentPercentProfit(
        uint256 openPrice,
        uint256 currentPrice,
        bool buy,
        uint256 leverage
    ) private pure returns (int256 p) {
        int256 maxPnlP = int256(MAX_GAIN_P) * int256(PRECISION);

        p =
            ((
                buy
                    ? int256(currentPrice) - int256(openPrice)
                    : int256(openPrice) - int256(currentPrice)
            ) *
                100 *
                int256(PRECISION) *
                int256(leverage)) /
            int256(openPrice);

        p = p > maxPnlP ? maxPnlP : p;
    }

    function correctTp(
        uint256 openPrice,
        uint256 leverage,
        uint256 tp,
        bool buy
    ) private pure returns (uint256) {
        if (
            tp == 0 ||
            currentPercentProfit(openPrice, tp, buy, leverage) ==
            int256(MAX_GAIN_P) * int256(PRECISION)
        ) {
            uint256 tpDiff = (openPrice * MAX_GAIN_P) / leverage / 100;

            return
                buy ? openPrice + tpDiff : tpDiff <= openPrice
                    ? openPrice - tpDiff
                    : 0;
        }

        return tp;
    }

    function correctSl(
        uint256 openPrice,
        uint256 leverage,
        uint256 sl,
        bool buy
    ) private pure returns (uint256) {
        if (
            sl > 0 &&
            currentPercentProfit(openPrice, sl, buy, leverage) <
            int256(MAX_SL_P) * int256(PRECISION) * -1
        ) {
            uint256 slDiff = (openPrice * MAX_SL_P) / leverage / 100;

            return buy ? openPrice - slDiff : openPrice + slDiff;
        }

        return sl;
    }

    function marketExecutionPrice(
        uint256 price,
        uint256 spreadP,
        uint256 spreadReductionP,
        bool long
    ) private pure returns (uint256) {
        uint256 priceDiff = (price *
            (spreadP - (spreadP * spreadReductionP) / 100)) /
            100 /
            PRECISION;

        return long ? price + priceDiff : price - priceDiff;
    }

    function distributeStakingReward(address trader, uint256 amountDai)
        private
    {
        storageT.transferDai(address(storageT), address(this), amountDai);
        staking.distributeRewardDai(amountDai);
        emit SssFeeCharged(trader, amountDai);
    }

    function sendToVault(uint256 amountDai, address trader) private {
        storageT.transferDai(address(storageT), address(this), amountDai);

        storageT.vault().receiveAssets(amountDai, trader);
        //storageT.vault().receiveDaiFromTrader(trader, amountDai, 0);
    }
}
