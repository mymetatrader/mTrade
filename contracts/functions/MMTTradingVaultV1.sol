// SPDX-License-Identifier: MIT
import "../interfaces/StorageInterfaceV5.sol";
pragma solidity 0.8.10;

contract MMTTradingVaultV1 {
    uint256 public constant PRECISION = 1e5;
    StorageInterfaceV5 public immutable storageT;
    address public constant rewardDistributor =
        0xC66FbE50Dd33c9AAdd65707F7088D597C86fE00F;

    // PARAMS
    // 1. Refill
    uint256 public blocksBaseRefill = 2500; // block
    uint256 public refillLiqP = 0.1 * 1e5; // PRECISION (%)
    uint256 public powerRefill = 5; // no decimal

    // 2. Deplete
    uint256 public blocksBaseDeplete = 10000; // block
    uint256 public blocksMinDeplete = 2000; // block
    uint256 public depleteLiqP = 0.3 * 1e5; // PRECISION (%)
    uint256 public coeffDepleteP = 100; // %
    uint256 public thresholdDepleteP = 10; // %

    // 3. Staking
    uint256 public withdrawTimelock = 43200; // blocks
    uint256 public maxWithdrawP = 25; // %

    // 4. Trading
    uint256 public swapFeeP = 0.3 * 1e5; // PRECISION (%)

    // STATE
    // 1. DAI balance
    uint256 public maxBalanceDai; // 1e18
    uint256 public currentBalanceDai; // 1e18
    uint256 public lastActionBlock; // block

    // 2. DAI staking rewards
    uint256 public accDaiPerDai; // 1e18
    uint256 public rewardsDai; // 1e18

    // 3. MATIC staking rewards
    uint256 public maticPerBlock; // 1e18
    uint256 public accMaticPerDai; // 1e18
    uint256 public maticStartBlock; // 1e18
    uint256 public maticEndBlock; // 1e18
    uint256 public maticLastRewardBlock; // 1e18
    uint256 public rewardsMatic; // 1e18

    // 4. Mappings
    struct User {
        uint256 daiDeposited;
        uint256 maxDaiDeposited;
        uint256 withdrawBlock;
        uint256 debtDai;
        uint256 debtMatic;
    }
    mapping(address => User) public users;
    mapping(address => uint256) public daiToClaim;

    // EVENTS
    event Deposited(
        address caller,
        uint256 amount,
        uint256 newCurrentBalanceDai,
        uint256 newMaxBalanceDai
    );
    event Withdrawn(
        address caller,
        uint256 amount,
        uint256 newCurrentBalanceDai,
        uint256 newMaxBalanceDai
    );
    event Sent(
        address caller,
        address trader,
        uint256 amount,
        uint256 newCurrentBalanceDai,
        uint256 maxBalanceDai
    );
    event ToClaim(
        address caller,
        address trader,
        uint256 amount,
        uint256 currentBalanceDai,
        uint256 maxBalanceDai
    );
    event Claimed(
        address trader,
        uint256 amount,
        uint256 newCurrentBalanceDai,
        uint256 maxBalanceDai
    );
    event Refilled(
        address caller,
        uint256 daiAmount,
        uint256 newCurrentBalanceDai,
        uint256 maxBalanceDai,
        uint256 tokensMinted
    );
    event Depleted(
        address caller,
        uint256 daiAmount,
        uint256 newCurrentBalanceDai,
        uint256 maxBalanceDai,
        uint256 tokensBurnt
    );
    event ReceivedFromTrader(
        address caller,
        address trader,
        uint256 daiAmount,
        uint256 vaultFeeDai,
        uint256 newCurrentBalanceDai,
        uint256 maxBalanceDai
    );
    event AddressUpdated(string name, address a);
    event NumberUpdated(string name, uint256 value);

    constructor(StorageInterfaceV5 _storageT) {
        require(address(_storageT) != address(0), "ADDRESS_0");
        storageT = _storageT;
    }

    modifier onlyGov() {
        require(msg.sender == storageT.gov(), "GOV_ONLY");
        _;
    }
    modifier onlyCallbacks() {
        require(msg.sender == storageT.callbacks(), "CALLBACKS_ONLY");
        _;
    }

    // Manage state
    function setBlocksBaseRefill(uint256 _blocksBaseRefill) external onlyGov {
        require(_blocksBaseRefill >= 1000, "BELOW_1000");
        blocksBaseRefill = _blocksBaseRefill;
        emit NumberUpdated("blocksBaseRefill", _blocksBaseRefill);
    }

    function setBlocksBaseDeplete(uint256 _blocksBaseDeplete) external onlyGov {
        require(_blocksBaseDeplete >= 1000, "BELOW_1000");
        blocksBaseDeplete = _blocksBaseDeplete;
        emit NumberUpdated("blocksBaseDeplete", _blocksBaseDeplete);
    }

    function setBlocksMinDeplete(uint256 _blocksMinDeplete) external onlyGov {
        require(_blocksMinDeplete >= 1000, "BELOW_1000");
        blocksMinDeplete = _blocksMinDeplete;
        emit NumberUpdated("blocksMinDeplete", _blocksMinDeplete);
    }

    function setRefillLiqP(uint256 _refillLiqP) external onlyGov {
        require(_refillLiqP > 0, "VALUE_0");
        require(_refillLiqP <= (3 * PRECISION) / 10, "ABOVE_0_POINT_3");
        refillLiqP = _refillLiqP;
        emit NumberUpdated("refillLiqP", _refillLiqP);
    }

    function setDepleteLiqP(uint256 _depleteLiqP) external onlyGov {
        require(_depleteLiqP > 0, "VALUE_0");
        require(_depleteLiqP <= (3 * PRECISION) / 10, "ABOVE_0_POINT_3");
        depleteLiqP = _depleteLiqP;
        emit NumberUpdated("depleteLiqP", _depleteLiqP);
    }

    function setPowerRefill(uint256 _powerRefill) external onlyGov {
        require(_powerRefill >= 2, "BELOW_2");
        require(_powerRefill <= 10, "ABOVE_10");
        powerRefill = _powerRefill;
        emit NumberUpdated("powerRefill", _powerRefill);
    }

    function setCoeffDepleteP(uint256 _coeffDepleteP) external onlyGov {
        coeffDepleteP = _coeffDepleteP;
        emit NumberUpdated("coeffDepleteP", _coeffDepleteP);
    }

    function setThresholdDepleteP(uint256 _thresholdDepleteP) external onlyGov {
        require(_thresholdDepleteP <= 100, "ABOVE_100");
        thresholdDepleteP = _thresholdDepleteP;
        emit NumberUpdated("thresholdDepleteP", _thresholdDepleteP);
    }

    function setSwapFeeP(uint256 _swapFeeP) external onlyGov {
        require(_swapFeeP <= PRECISION, "ABOVE_1");
        swapFeeP = _swapFeeP;
        emit NumberUpdated("swapFeeP", _swapFeeP);
    }

    function setWithdrawTimelock(uint256 _withdrawTimelock) external onlyGov {
        require(_withdrawTimelock > 43200, "LESS_THAN_1_DAY");
        withdrawTimelock = _withdrawTimelock;
        emit NumberUpdated("withdrawTimelock", _withdrawTimelock);
    }

    function setMaxWithdrawP(uint256 _maxWithdrawP) external onlyGov {
        require(_maxWithdrawP >= 10, "BELOW_10");
        require(_maxWithdrawP <= 100, "ABOVE_100");
        maxWithdrawP = _maxWithdrawP;
        emit NumberUpdated("maxWithdrawP", _maxWithdrawP);
    }

    // Refill
    function refill() external {
        require(currentBalanceDai < maxBalanceDai, "ALREADY_FULL");
        require(
            block.number >=
                lastActionBlock +
                    blocksBetweenRefills(currentBalanceDai, maxBalanceDai),
            "TOO_EARLY"
        );

        (uint256 tokenReserve, ) = storageT
            .priceAggregator()
            .tokenDaiReservesLp();
        uint256 tokensToMint = (tokenReserve * refillLiqP) / 100 / PRECISION;

        storageT.handleTokens(address(this), tokensToMint, true);

        address[] memory tokenToDaiPath = new address[](2);
        tokenToDaiPath[0] = address(storageT.token());
        tokenToDaiPath[1] = address(storageT.dai());

        storageT.token().approve(
            address(storageT.tokenDaiRouter()),
            tokensToMint
        );
        uint256[] memory amounts = storageT
            .tokenDaiRouter()
            .swapExactTokensForTokens(
                tokensToMint,
                0,
                tokenToDaiPath,
                address(this),
                block.timestamp + 300
            );

        currentBalanceDai += amounts[1];
        lastActionBlock = block.number;

        emit Refilled(
            msg.sender,
            amounts[1],
            currentBalanceDai,
            maxBalanceDai,
            tokensToMint
        );
    }

    function blocksBetweenRefills(
        uint256 _currentBalanceDai,
        uint256 _maxBalanceDai
    ) public view returns (uint256) {
        uint256 blocks = (((_currentBalanceDai * PRECISION) / _maxBalanceDai) **
            powerRefill *
            blocksBaseRefill) / (PRECISION**powerRefill);
        return blocks >= 1 ? blocks : 1;
    }

    // Deplete
    function deplete() external {
        require(
            currentBalanceDai >
                (maxBalanceDai * (100 + thresholdDepleteP)) / 100,
            "NOT_FULL"
        );
        require(
            block.number >=
                lastActionBlock +
                    blocksBetweenDepletes(currentBalanceDai, maxBalanceDai),
            "TOO_EARLY"
        );

        (, uint256 daiReserve) = storageT
            .priceAggregator()
            .tokenDaiReservesLp();
        uint256 daiToBuy = (daiReserve * depleteLiqP) / 100 / PRECISION;

        address[] memory daiToTokenPath = new address[](2);
        daiToTokenPath[0] = address(storageT.dai());
        daiToTokenPath[1] = address(storageT.token());

        require(
            storageT.dai().approve(address(storageT.tokenDaiRouter()), daiToBuy)
        );
        uint256[] memory amounts = storageT
            .tokenDaiRouter()
            .swapExactTokensForTokens(
                daiToBuy,
                0,
                daiToTokenPath,
                address(this),
                block.timestamp + 300
            );

        storageT.handleTokens(address(this), amounts[1], false);

        currentBalanceDai -= daiToBuy;
        lastActionBlock = block.number;

        emit Depleted(
            msg.sender,
            daiToBuy,
            currentBalanceDai,
            maxBalanceDai,
            amounts[1]
        );
    }

    function blocksBetweenDepletes(
        uint256 _currentBalanceDai,
        uint256 _maxBalanceDai
    ) public view returns (uint256) {
        uint256 blocks = blocksBaseDeplete -
            ((100 *
                _currentBalanceDai -
                _maxBalanceDai *
                (100 + thresholdDepleteP)) * coeffDepleteP) /
            _currentBalanceDai;
        return blocks >= blocksMinDeplete ? blocks : blocksMinDeplete;
    }

    // Staking (user interaction)
    function harvest() public {
        User storage u = users[msg.sender];

        require(storageT.dai().transfer(msg.sender, pendingRewardDai()));
        u.debtDai = (u.daiDeposited * accDaiPerDai) / 1e18;

        uint256 pendingMatic = pendingRewardMatic();
        accMaticPerDai = pendingAccMaticPerDai();
        maticLastRewardBlock = block.number;
        u.debtMatic = (u.daiDeposited * accMaticPerDai) / 1e18;
        payable(msg.sender).transfer(pendingMatic);
    }

    function depositDai(uint256 _amount) external {
        User storage user = users[msg.sender];

        require(_amount > 0, "AMOUNT_0");
        require(
            storageT.dai().transferFrom(msg.sender, address(this), _amount)
        );

        harvest();

        currentBalanceDai += _amount;
        maxBalanceDai += _amount;

        user.daiDeposited += _amount;
        user.maxDaiDeposited = user.daiDeposited;
        user.debtDai = (user.daiDeposited * accDaiPerDai) / 1e18;
        user.debtMatic = (user.daiDeposited * accMaticPerDai) / 1e18;

        emit Deposited(msg.sender, _amount, currentBalanceDai, maxBalanceDai);
    }

    function withdrawDai(uint256 _amount) external {
        User storage user = users[msg.sender];

        require(_amount > 0, "AMOUNT_0");
        require(_amount <= currentBalanceDai, "BALANCE_TOO_LOW");
        require(
            _amount <= user.daiDeposited,
            "WITHDRAWING_MORE_THAN_DEPOSITED"
        );
        require(
            _amount <= (user.maxDaiDeposited * maxWithdrawP) / 100,
            "MAX_WITHDRAW_P"
        );
        require(
            block.number >= user.withdrawBlock + withdrawTimelock,
            "TOO_EARLY"
        );

        harvest();

        currentBalanceDai -= _amount;
        maxBalanceDai -= _amount;

        user.daiDeposited -= _amount;
        user.withdrawBlock = block.number;
        user.debtDai = (user.daiDeposited * accDaiPerDai) / 1e18;
        user.debtMatic = (user.daiDeposited * accMaticPerDai) / 1e18;

        require(storageT.dai().transfer(msg.sender, _amount));

        emit Withdrawn(msg.sender, _amount, currentBalanceDai, maxBalanceDai);
    }

    // MATIC incentives
    function distributeRewardMatic(uint256 _startBlock, uint256 _endBlock)
        external
        payable
    {
        require(msg.sender == rewardDistributor, "WRONG_CALLER");
        require(msg.value > 0, "AMOUNT_0");
        require(_startBlock < _endBlock, "START_AFTER_END");
        require(_startBlock > block.number, "START_BEFORE_NOW");
        require(_endBlock - _startBlock >= 100000, "TOO_SHORT");
        require(_endBlock - _startBlock <= 1500000, "TOO_LONG");
        require(
            block.number > maticEndBlock,
            "LAST_MATIC_DISTRIBUTION_NOT_ENDED"
        );
        require(maxBalanceDai > 0, "NO_DAI_STAKED");

        accMaticPerDai = pendingAccMaticPerDai();
        rewardsMatic += msg.value;
        maticLastRewardBlock = 0;

        maticPerBlock = msg.value / (_endBlock - _startBlock);
        maticStartBlock = _startBlock;
        maticEndBlock = _endBlock;
    }

    function pendingAccMaticPerDai() private view returns (uint256) {
        if (maxBalanceDai == 0) {
            return accMaticPerDai;
        }

        uint256 pendingRewardBlocks = 0;
        if (block.number > maticStartBlock) {
            if (block.number <= maticEndBlock) {
                pendingRewardBlocks = maticLastRewardBlock == 0
                    ? block.number - maticStartBlock
                    : block.number - maticLastRewardBlock;
            } else if (maticLastRewardBlock <= maticEndBlock) {
                pendingRewardBlocks = maticLastRewardBlock == 0
                    ? maticEndBlock - maticStartBlock
                    : maticEndBlock - maticLastRewardBlock;
            }
        }
        return
            accMaticPerDai +
            (pendingRewardBlocks * maticPerBlock * 1e18) /
            maxBalanceDai;
    }

    function pendingRewardMatic() public view returns (uint256) {
        User memory u = users[msg.sender];
        return (u.daiDeposited * pendingAccMaticPerDai()) / 1e18 - u.debtMatic;
    }

    // DAI incentives
    function distributeRewardDai(uint256 _amount) public onlyCallbacks {
        if (maxBalanceDai > 0) {
            currentBalanceDai -= _amount;
            accDaiPerDai += (_amount * 1e18) / maxBalanceDai;
            rewardsDai += _amount;
        }
    }

    function pendingRewardDai() public view returns (uint256) {
        User memory u = users[msg.sender];
        return (u.daiDeposited * accDaiPerDai) / 1e18 - u.debtDai;
    }

    // Handle traders DAI when a trade is closed
    function sendDaiToTrader(address _trader, uint256 _amount)
        external
        onlyCallbacks
    {
        _amount -= (swapFeeP * _amount) / 100 / PRECISION;

        if (_amount <= currentBalanceDai) {
            currentBalanceDai -= _amount;
            require(storageT.dai().transfer(_trader, _amount));
            emit Sent(
                msg.sender,
                _trader,
                _amount,
                currentBalanceDai,
                maxBalanceDai
            );
        } else {
            daiToClaim[_trader] += _amount;
            emit ToClaim(
                msg.sender,
                _trader,
                _amount,
                currentBalanceDai,
                maxBalanceDai
            );
        }
    }

    function claimDai() external {
        uint256 amount = daiToClaim[msg.sender];
        require(amount > 0, "NOTHING_TO_CLAIM");
        require(currentBalanceDai > amount, "BALANCE_TOO_LOW");

        currentBalanceDai -= amount;
        require(storageT.dai().transfer(msg.sender, amount));
        daiToClaim[msg.sender] = 0;

        emit Claimed(msg.sender, amount, currentBalanceDai, maxBalanceDai);
    }

    // Handle DAI from opened trades
    function receiveDaiFromTrader(
        address _trader,
        uint256 _amount,
        uint256 _vaultFee
    ) external onlyCallbacks {
        storageT.transferDai(address(storageT), address(this), _amount);
        currentBalanceDai += _amount;

        distributeRewardDai(_vaultFee);

        emit ReceivedFromTrader(
            msg.sender,
            _trader,
            _amount,
            _vaultFee,
            currentBalanceDai,
            maxBalanceDai
        );
    }

    // Useful backend function (ignore)
    function backend(address _trader)
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            StorageInterfaceV5.Trader memory,
            uint256[] memory,
            StorageInterfaceV5.PendingMarketOrder[] memory,
            uint256[][5] memory
        )
    {
        uint256[] memory pendingIds = storageT.getPendingOrderIds(_trader);

        StorageInterfaceV5.PendingMarketOrder[]
            memory pendingMarket = new StorageInterfaceV5.PendingMarketOrder[](
                pendingIds.length
            );
        for (uint256 i = 0; i < pendingIds.length; i++) {
            pendingMarket[i] = storageT.reqID_pendingMarketOrder(pendingIds[i]);
        }

        uint256[][5] memory nftIds;
        for (uint256 j = 0; j < 5; j++) {
            uint256 nftsCount = storageT.nfts(j).balanceOf(_trader);
            nftIds[j] = new uint256[](nftsCount);
            for (uint256 i = 0; i < nftsCount; i++) {
                nftIds[j][i] = storageT.nfts(j).tokenOfOwnerByIndex(_trader, i);
            }
        }

        return (
            storageT.dai().allowance(_trader, address(storageT)),
            storageT.dai().balanceOf(_trader),
            storageT.linkErc677().allowance(_trader, address(storageT)),
            storageT.traders(_trader),
            pendingIds,
            pendingMarket,
            nftIds
        );
    }
}
